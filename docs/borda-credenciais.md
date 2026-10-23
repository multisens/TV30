---
title: Borda e credenciais
parent: Como funciona
nav_order: 5
---

# Borda e credenciais

A **borda** é o container `edgegateway` (`infra/edgegateway/`). Todo cliente das APIs entra por ela: o tv3ws não publica as portas de API no host. Ela tem dois processos KrakenD, um por superfície, com o plugin Go `tv30-auth`, que decide sobre a credencial e a versão de cada requisição, e serve a documentação Swagger das duas superfícies.

{: .nota }
A norma define as classes de cliente (C.3.1), o access token (C.4.1.2, C.6.1), o bind-token (C.4.1.3, C.4.1.4, C.6.8), a versão (C.3.6) e o formato de erro (C.3.2). Não diz qual processo valida a credencial nem qual responde cada API: a borda, o plugin e a divisão de trabalho entre a borda e o tv3ws são decisões deste testbed.

---

## As duas superfícies

As duas têm as 26 rotas da tabela. O que muda é o 106:

| Superfície | Porta | Protocolo | Regra própria | Backend no tv3ws |
|---|---|---|---|---|
| interna | 44642, fixa pela C.3.4 (`Server-BaseURL`) | HTTP | o cliente não local só usa `/tv3/authorize` e `/tv3/token`; nas demais rotas, 106 (C.4.1.6) | `http://tv3ws:44652` |
| externa | 44643 (`Server-SecureBaseURL`) | **TLS**, terminado na borda | as rotas de uso exclusivo do cliente local (`POST`/`DELETE /tv3/bind-context`, C.6.15.5, rotas por `handle`) e o `/tv3/authorize` respondem 106 a qualquer requisição (C.4.1.8) | `https://tv3ws:44653` |

- **Uma tabela de rotas só.** O `infra/edgegateway/routes.json` declara método, caminho, política (`auth`, `classes`), a linha da Tabela C.2 (`api`), as versões servidas (`versions`), o erro sem serviço selecionado (`no_service`) e o erro do serviço fora do catálogo (`not_in_catalog`). O `generate.js` gera dela, no build da imagem, as configurações do KrakenD (variantes `linux` e `windows`, com um endpoint por par rota × versão), os dois OpenAPI e a tabela de rotas do plugin.
- **Certificado.** O serviço `tls-init` gera na primeira subida um certificado X.509 autoassinado em `.tv30/tls` (fora do git), sem ação do usuário (C.4.1.1). A borda termina com ele o TLS da 44643; o tv3ws o usa no HTTPS da 44653, no `serverCert` do pareamento (Tabela C.4) e no `wss://` do ponto de entrada do dispositivo remoto (Tabela C.76).
- **Variante.** `EDGE_VARIANT` escolhe onde a borda procura o tv3ws: `linux` (padrão, em container) ou `windows` (o tv3ws no host, com `npm run dev`; [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local)).

---

## A decisão sobre cada requisição

O plugin avalia nesta ordem, e a primeira etapa que falha define o erro (`evaluate` e `ServeHTTP`, em `infra/edgegateway/plugin/handler.go`):

| # | Etapa | Erro | Regra |
|---|---|---|---|
| 1 | Rota | 100 | Método e caminho declarados. Caminho não declarado não chega ao KrakenD |
| 2 | Superfície | 106 | O 106 da tabela acima, na externa |
| 3 | Classe | 106 | A classe vem do claim `class` do access token; sem `Authorization`, um `Origin` em `origins:associated` faz do cliente um local associado. Nas rotas que não admitem o associado (C.6.1.2, C.6.1.3, C.6.8.3), o `Origin` associado dá 106 também com token válido de outra classe |
| 4 | Não local por HTTP | 106 | Na interna, o token de classe `non-local` fora de `/tv3/authorize` e `/tv3/token` |
| 5 | Access token | 107 | `Authorization: Bearer <jwt>`, HS256 com o `JWT_SECRET`, `exp` válido, `iss` igual ao `JWT_ISSUER`, `sub` em `clients:authorized` e fora de `clients:blocked` |
| 6 | Serviço selecionado | 300 | Nas rotas cuja tabela lista o 300 (C.6.4.7, C.6.14.1 a C.6.14.6), sem serviço DTV selecionado |
| 7 | Serviço no catálogo | 304 | Na C.6.14.2 e na C.6.14.5 (`/tv3/{serviceContextId}/users/{userid}`), o `{serviceContextId}` explícito fora de `services:announced`, os serviços anunciados na LLS que o AoP grava ("DTV service not found", Tabelas C.71 e C.74) |
| 8 | Bind-token | 104 / 108 | Nas rotas `token+bind`. Sem o cabeçalho, 104. O token tem de ser assinado por uma chave registrada (C.6.8.2) para o **contexto de serviço da rota**: o `{serviceContextId}` do caminho, ou o serviço corrente em `current-service` e nas rotas sem o parâmetro. Senão, 108. Sem serviço selecionado na C.6.16.3, 108 |
| 9 | Versão | 100 / 101 | O `Accept-Version` contra as versões da rota (C.3.6.5). Ausente vale 2.0; fora do formato X.Y, 101; versão que a rota não serve, 100 |

- **O `serviceContextId` é o `globalServiceId` do BAM.** Na C.6.14.2 e na C.6.14.5, ele tem de estar no Application Catalog (`services:announced`), senão 304, para todo cliente, inclusive o associado; `current-service` não confere.
- **O local associado** usa as rotas que o admitem sem access token. No próprio contexto de serviço (o serviço que lançou a app, valor de `origins:associated`), também sem bind-token; em contexto de outra emissora, segue a regra geral: 104, 108, ou atende com bind-token válido daquele contexto (C.4.1.1). Um access token de classe `local-associated` segue a regra geral, com bind-token nas rotas `token+bind`.
- **Versão repassada.** A borda manda ao serviço a versão decidida no cabeçalho interno `X-TV30-API-Version`, e o Host original do cliente em `X-TV30-Host` (para o `/manifest`), apagando o que vier do cliente. O tv3ws não interpreta o `Accept-Version`. A versão não escolhe o serviço de destino: ele é sempre o backend da superfície. Nas versões de 100 em diante (extensões do testbed), o caminho do salto borda → serviço é `/v<X.Y>` + o caminho público (`internalPath`, em `edge.go`), e o `generate.js` cria um endpoint do KrakenD por par rota × versão. O cliente usa só o caminho público; `/v...` vindo dele não é rota declarada (100).
- **Relógio do bind-token:** o do host, sem tolerância (`checkTime`, `jwt.go`). A emissora simulada e o receptor rodam na mesma máquina.
- **Falha do Redis** durante a decisão dá o código 200 ("Platform resource unavailable").

### `warn` e `enforce`

`AUTH_ENFORCE` no `.env` da raiz. Padrão: **`enforce`**.

- **Só as recusas de credencial seguem o modo:** 104, 107 e 108. Em `warn`, opção explícita e transitória (por exemplo, para um cliente que ainda não obtém token), elas viram o aviso `X-TV30-Auth-Warn: <código>` e o log `[tv30-auth] WARN`, e a requisição segue.
- **Nos dois modos:** 100 e 101 (rota e versão), 106 (tipo de cliente), 300 (estado do receptor), 304 (serviço fora do catálogo) e 200 (Redis fora do ar). A resposta 5xx do KrakenD (backend lento ou fora do ar) vira 404 `{"error":200}`.
- Valor inválido em `AUTH_ENFORCE` derruba a borda no boot.

---

## O que a borda responde sozinha

- **C.6.8** (`POST`, `GET` e `DELETE /tv3/bind-context`; `bindcontext.go`): registro, consulta e revogação das chaves de bind-token, em `bind-context:{serviceId}`. O `serviceContextId` das respostas é o `globalServiceId` de cada serviço. A borda é a única que escreve essa chave (a auditoria do esquema também a lê).
- **C.6.7.8 e C.6.7.9** (`GET /tv3/api-info[/{apiId}]`; `apiinfo.go`): as 20 APIs implementadas, nas duas superfícies, cada uma com a versão mais recente que serve (100.0 para a `tv3ws-remotedevice-communication`, 2.0 para as demais).

---

## Quem emite a credencial

- **Access token:** o tv3ws, em `GET /tv3/authorize` (C.6.1.2) e `GET /tv3/token` (C.6.1.3), HS256 com o `JWT_SECRET`. O tv3ws nunca emite credencial de classe associada: responde 106. Fluxo e pareamento em [APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws#autorização-de-cliente-tv3authorize-e-tv3token).
- **Bind-token:** o testbed não emite. A emissora registra o par `{alg, key}` pela C.6.8.2 e assina os próprios tokens; a borda só os valida.
- **O tv3ws não valida a credencial das requisições.** Ele só confere o que a emissão exige no `/tv3/token`.

---

## Lacunas

- O local associado é reconhecido pelo `Origin`, forjável fora do navegador. A chamada sem `Origin` também fica de fora do 106 dado ao associado nas rotas que não o admitem.
- Os recursos compartilhados (C.4.4) não são liberados ao fechar a app associada, ao remover a autorização nem ao revogar uma chave: dependem do Application Lifecycle Manager e do menu de autorizações, que não existem no testbed.

---

## Onde está no código e nos testes

| O quê | Onde |
|---|---|
| Tabela de rotas, políticas e versões | `infra/edgegateway/routes.json` |
| Gerador das configurações, dos OpenAPI e da tabela do plugin | `infra/edgegateway/generate.js` (testes: `generate.test.js`, no build da imagem) |
| Decisão, versão, erros C.3.2, CORS | `infra/edgegateway/plugin/handler.go`, `edge.go` |
| Access token e bind-token | `infra/edgegateway/plugin/jwt.go`, `keys.go`, `bindcontext.go` |
| Consultas ao Redis | `infra/edgegateway/plugin/redis.go` |
| Certificado do receptor | `infra/edgegateway/tls-init.sh` (serviço `tls-init`) |
| Testes de unidade do plugin | `infra/edgegateway/plugin/*_test.go`, no build da imagem |
| Teste na stack | `scripts/test-auth.sh` ([Como testar]({{ site.baseurl }}/como-testar)) |
