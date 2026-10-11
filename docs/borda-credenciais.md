---
title: Borda e credenciais
parent: Como funciona
nav_order: 5
---

# Borda e credenciais

A **borda** é o container `edgegateway` (`infra/edgegateway/`). Todo cliente das APIs entra por ela: o tv3ws não publica as portas de API no host. Ela tem dois processos KrakenD, um por superfície, com o plugin Go `tv30-auth`, que decide sobre a credencial de cada requisição, e serve a documentação Swagger das duas superfícies. Com o override `docker-compose.ssdp.yml`, ela também anuncia o SSDP ([Descoberta SSDP]({{ site.baseurl }}/ssdp)).

{: .nota }
A norma define as classes de cliente (C.3.1), o access token (C.4.1.2, C.6.1), o bind-token (C.4.1.3, C.4.1.4, C.6.8) e o formato de erro (C.3.2). Não diz qual processo valida a credencial nem qual responde cada API: a borda, o plugin e a divisão de trabalho entre a borda e o tv3ws são decisões deste testbed (D1 de 28/09; D-0510-1 a D-0510-3, reunião de 05/10 com o Joel).

Esta página resume o comportamento atual. O detalhe, com cada caso, está no README do plugin ([`edgegateway/plugin/README.md`](https://github.com/multisens/Infra/blob/main/edgegateway/plugin/README.md), no repositório Infra) e em [`docs/05-autenticacao.md`](https://github.com/multisens/Infra/blob/main/docs/05-autenticacao.md), também no Infra.

---

## As duas superfícies

| Superfície | Porta | Rotas | Backend no tv3ws (variante `linux`) |
|---|---|---|---|
| interna | 44642, fixa pela C.3.4 (`Server-BaseURL`) | todas as 27 da tabela | `http://tv3ws:44652` |
| externa | 44643 (`Server-SecureBaseURL`); ainda HTTP, porque o TLS na borda está pendente (L3) | 25: só as que admitem o cliente não local | `https://tv3ws:44653` |

- **Uma tabela de rotas só.** O `infra/edgegateway/routes.json` declara método, caminho, política (`auth`, `classes`) e, quando a rota implementa uma API da norma, a linha da Tabela C.2 (`api`). O `generate.js` gera dela, no build da imagem, as configurações do KrakenD das duas superfícies (variantes `linux`, `windows` e `host`), os dois OpenAPI e a tabela de rotas do plugin.
- **Superfície derivada das classes** (P1.9, decisão do Luís em 10/10). A externa só recebe as rotas que admitem `non-local` (`SURFACE_RULES`, no `generate.js`); rota sem `classes` fica nas duas. Hoje saem da externa `POST` e `DELETE /tv3/bind-context`, que só o local associado usa; lá, elas respondem 100, como um caminho não declarado.
- **A externa depende do HTTPS do tv3ws.** O backend dela é a 44653 do tv3ws, que só sobe com `HTTPS_KEY` e `HTTPS_CERT` no `tv3ws/.env` (`tv3ws/src/server.ts`; passo a passo na seção *(Opcional) Habilitando HTTPS no tv3ws* do `README.md` da raiz). Sem eles, as rotas repassadas pela 44643 recebem 404 `{"error":200}` da borda, porque o KrakenD não alcança o backend.
- **Variante.** `EDGE_VARIANT` escolhe onde a borda procura o tv3ws: `linux` (padrão, o tv3ws em container), `windows` (o tv3ws no host, com `npm run dev`; ver [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local)) e `host` (a borda em rede do host, com o override do SSDP).

---

## A decisão de credencial

O plugin avalia cada requisição em quatro etapas, nesta ordem, e a primeira que falha define o erro (`evaluate`, em `infra/edgegateway/plugin/handler.go`):

| # | Etapa | Erro | Regra |
|---|---|---|---|
| 1 | Rota | 100 | Método e caminho declarados para a superfície. Caminho não declarado não chega ao KrakenD |
| 2 | Classe | 106 | A classe vem do claim `class` do access token. Sem `Authorization`, um `Origin` presente em `origins:associated` faz do cliente um local associado. A rota lista as classes que admite (`classes`) |
| 3 | Access token | 107 | `Authorization: Bearer <jwt>`, HS256 com o `JWT_SECRET`, `exp` obrigatório e válido, `nbf` se houver, `iss` igual ao `JWT_ISSUER`. Cliente cujo `sub` está em `clients:blocked` também recebe 107 (C.4.2.2) |
| 4 | Bind-token | 104 / 108 | Só nas rotas `token+bind`. Sem o cabeçalho `bind-token`, 104. O token tem de ser assinado por uma chave registrada (C.6.8.2) para o **serviço corrente** (`session:current-service-id`); se não for, 108 |

- **O local associado** (o `Origin` em `origins:associated`, sem `Authorization`) usa as rotas que o admitem sem access token e sem bind-token, como diz a C.4.1.1. Desde o P1.3 (decisão do Luís em 10/10), o AoP grava ali a origem própria de cada app de emissora em execução, `http://<app>.apps.localhost:8080` ([Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos) e [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis)). O risco do `Origin` forjado fora do navegador foi aceito pelo Luís em 03/10 (L1).
- **Token com `class` `local-associated`** dispensa o bind-token.
- **Falha do Redis** durante a decisão dá o código 200 ("Platform resource unavailable").

As políticas de cada rota (`auth` = `none`, `token` ou `token+bind`, e `classes`) estão na tabela da [página das APIs]({{ site.baseurl }}/apis-tv3ws#endpoints-declarados-na-borda) e no README do plugin. O critério do `token+bind` é o campo "Security requirements" = *shall* da tabela de cada API na norma.

### `warn` e `enforce`

`AUTH_ENFORCE` (no `.env` da raiz; padrão `warn`) define o que o plugin faz com a decisão (`infra/edgegateway/plugin/config.go` e `handler.go`):

- **`warn`:** nada que dependa de credencial é bloqueado. O plugin registra `[tv30-auth] WARN ...` no log e acrescenta à resposta o cabeçalho `X-TV30-Auth-Warn: <código>`, com o código que o `enforce` daria. O motivo do padrão é que clientes como o Guaraná ainda não obtêm token.
- **`enforce`:** a requisição recusada recebe o erro no formato C.3.2: status 404, corpo `{"error": <n>, "description": "..."}`, `Content-Type: application/json`, `Access-Control-Allow-Origin: *` e `API-Version`.
- **Nos dois modos:** o 100 (rota não declarada) é sempre bloqueado, e a resposta 5xx do KrakenD (backend lento ou fora do ar) vira 404 `{"error":200}`. Valor inválido em `AUTH_ENFORCE` derruba a borda no boot.

Para ligar o `enforce`: `AUTH_ENFORCE=enforce` no `.env` da raiz e `docker compose up -d edgegateway`. O `scripts/test-auth.sh` faz isso sozinho durante o teste e volta ao modo anterior no fim ([Como testar]({{ site.baseurl }}/como-testar)). Antes de deixar o `enforce` ligado, há pontos que dependem do orientador (seção A de [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes)).

---

## O que a borda responde sozinha

Desde a reunião de 05/10 com o Joel, três grupos de rota passam pela mesma decisão de credencial e são respondidos pelo próprio plugin, sem repasse ao tv3ws:

- **C.6.8** (`POST`, `GET` e `DELETE /tv3/bind-context`; D-0510-2, `bindcontext.go`): o registro, a consulta e a revogação das chaves de bind-token da emissora, guardadas em `bind-context:{serviceId}`. É a única escrita da borda no Redis.
- **C.6.7.8 e C.6.7.9** (`GET /tv3/api-info/{apiId}` e `GET /tv3/api-info`; D-0510-3, `apiinfo.go`): a lista de APIs implementadas na superfície, tirada do campo `api` das rotas dela no `routes.json`. São 20 APIs na interna e 18 na externa.

Nessas rotas, a borda também negocia a versão (`Accept-Version`), com as mesmas regras do tv3ws (`negotiateVersion`, em `edge.go`).

---

## Quem emite a credencial

- **Access token:** emitido pelo tv3ws, nas APIs `GET /tv3/authorize` (C.6.1.2) e `GET /tv3/token` (C.6.1.3), assinado em HS256 com o `JWT_SECRET`. A borda e o tv3ws precisam do mesmo segredo e do mesmo emissor; o compose passa aos dois os mesmos valores, do `.env` da raiz ou dos padrões de desenvolvimento. O fluxo do cliente e o pareamento do não local (QR code ou PIN) estão em [APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws#autorização-de-cliente-tv3authorize-e-tv3token).
- **Bind-token:** o testbed não emite. A emissora registra o par `{alg, key}` pela C.6.8.2 e assina os próprios tokens (C.4.1.2); a borda só os valida, nas quatro frentes da C.4.1.4.
- **O tv3ws não valida a credencial das requisições** (D-0510-1): nem o access token nem o bind-token. Ele só confere o que a própria emissão exige, no `/tv3/token`: o `clientid` autorizado, o refresh token e a resposta ao desafio (`tv3ws/src/api/client-identification/controller.ts`).

---

## Lacunas

O que a norma deixa em aberto, ou que o projeto ainda não decidiu, tem um comportamento provisório marcado `PENDENTE (Joel)` no código. A lista e o estado de cada ponto ficam em [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes), seção A:

- **L1:** reconhecer o local associado pelo `Origin` (risco aceito pelo Luís em 03/10);
- **L2:** o `serviceContextId` é uma constante do tv3ws, e nas rotas `/tv3/{serviceContextId}/...` só vale `current-service` ou a constante (outro valor dá 108);
- **L3:** sem TLS na 44643, o 106 por protocolo ao não local (C.4.1.6) não é aplicado por ninguém;
- **L4:** o 106 ao associado em `/authorize` e `/token` depende do `Origin` e só bloqueia em `enforce`;
- **L5:** o relógio do bind-token é o do host, e não o System Time Fragment;
- **L7:** liberar os recursos compartilhados ao revogar uma chave (C.4.4) não está implementado;
- **E6:** a borda recusa o `sub` em `clients:blocked`, mas não exige a presença em `clients:authorized`.

---

## Onde está no código e nos testes

| O quê | Onde |
|---|---|
| Tabela de rotas e políticas | `infra/edgegateway/routes.json` |
| Gerador das configurações, dos OpenAPI e da tabela do plugin | `infra/edgegateway/generate.js` (testes: `generate.test.js`, que rodam no build da imagem) |
| Decisão de credencial, erros C.3.2, CORS | `infra/edgegateway/plugin/handler.go` |
| Access token | `infra/edgegateway/plugin/jwt.go` |
| Chaves e bind-token | `infra/edgegateway/plugin/keys.go`, `bindcontext.go` |
| Consultas ao Redis (cliente RESP próprio) | `infra/edgegateway/plugin/redis.go` |
| Processos do container (morre-inteiro) | `infra/edgegateway/entrypoint.sh` |
| Testes de unidade do plugin | `infra/edgegateway/plugin/*_test.go`, que rodam no build da imagem |
| Teste na stack | `scripts/test-auth.sh` ([Como testar]({{ site.baseurl }}/como-testar)) |
