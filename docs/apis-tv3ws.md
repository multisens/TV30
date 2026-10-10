---
title: APIs do tv3ws
nav_order: 5
---

# APIs do tv3ws

O **tv3ws** é a implementação dos **TV 3.0 WebServices** da ABNT NBR 25608 (Anexo C) neste testbed. O roteamento fica em `tv3ws/src/app.ts`.

Desde a reunião de 05/10 com o Joel, dois grupos de APIs declarados na borda **não** chegam ao tv3ws: a borda os responde sozinha, no plugin `tv30-auth`. São a C.6.8 (`/tv3/bind-context`, D-0510-2) e a C.6.7.8 e a C.6.7.9 (`/tv3/api-info`, D-0510-3). Eles aparecem na tabela abaixo, marcados "(borda)", porque o cliente os vê na mesma superfície. Qual processo responde cada API é decisão deste testbed; a norma só define as APIs.

O cliente não fala com o tv3ws diretamente. As portas 44652 e 44653 não são publicadas no host, e todo acesso passa pela **borda** (`edgegateway`):

- superfície interna: `http://localhost:44642`, porta fixa da C.3.4;
- superfície externa: `http://localhost:44643`, ainda em HTTP, porque o TLS na borda está pendente.

> Borda, mensageria e Redis são decisões de implementação do testbed, não da norma.

---

## Acesso, credenciais e versionamento

- **Rotas.** A tabela única `infra/edgegateway/routes.json` declara método, caminho e superfícies de cada rota. A borda não repassa ao tv3ws um caminho que não esteja declarado.
- **Credenciais.** Desde a semana de 28/09, quem valida é a borda, com o plugin `tv30-auth` (detalhes em `infra/edgegateway/plugin/README.md`). Ele confere o accessToken, o bind-token e a classe de cliente, conforme a política de cada rota.
  - No modo padrão, `AUTH_ENFORCE=warn`, a borda não bloqueia falha de credencial: registra `[tv30-auth] WARN` e devolve o cabeçalho `X-TV30-Auth-Warn`. Rota não declarada (100) é bloqueada nos dois modos.
  - **O tv3ws não valida credencial** (D-0510-1, reunião de 05/10 com o Joel). Até ali, ele ainda respondia 107 a um `Authorization` presente e inválido (`src/middleware/authorization.ts`, removido) e 106 ao cliente não local que chegava por HTTP (`validateClientProtocol`, removido de `src/middleware/basic.ts`). Sob `/tv3`, o tv3ws só negocia a versão e emite a credencial (`/tv3/authorize`, `/tv3/token`). O 106 por protocolo da C.4.1.6 ficou sem quem o aplique até a borda ter TLS (lacuna L3); só o `/tv3/token` ainda responde 106 à renovação do não local por HTTP.
- **Erros.** Seguem o formato C.3.2: status 404 com corpo `{"error": <n>, "description": "..."}`.
- **Falha do Redis** (D-0510-6, reunião de 05/10 com o Joel). Comando que não obtém resposta em 1,5 s falha (`tv3ws/src/redis-client.ts`), e a API responde 404 `{"error":200}` ("Platform resource unavailable", Tabela C.1), em vez de travar ou de tratar a falha como lista vazia. Os 1,5 s ficam abaixo dos 2 s que a borda espera o tv3ws, então o erro sai do próprio tv3ws. O registro de remote-device só abre a porta do WebSocket depois de gravar o espelho no Redis.
- **CORS.** Quem aplica é a borda. O tv3ws **não** envia cabeçalhos CORS, para não duplicá-los (`tv3ws/src/middleware/basic.ts`). A borda põe `Access-Control-Allow-Origin: *` em toda resposta, também sem `Origin` na requisição (C.4.1.9.2). O preflight é respondido pelo módulo CORS do KrakenD; o `OPTIONS` sem preflight num caminho declarado recebe 200 com os três cabeçalhos da C.4.1.9.3.
- **`Accept-Version`.** Opcional (`basic.ts`; nas rotas da borda, `infra/edgegateway/plugin/edge.go`, com as mesmas regras).
  - Sem o cabeçalho, vale a versão 2.0.
  - São aceitas a 2.0 e a 2.1.
  - Valor malformado dá erro 101; versão fora desse conjunto dá erro 100.
  - Toda resposta sob `/tv3` traz `API-Version` (C.3.6.6, p. 201; p. 219 do PDF), inclusive as de erro. Na resposta normal e nos erros das próprias APIs, vai a versão negociada. No erro 100, a mais recente que o servidor suporta, hoje a 2.1, como manda a exceção da C.3.6.6. No erro 101, a 2.0, a mesma de quando falta o cabeçalho: um `Accept-Version` malformado não pede versão nenhuma. Esta última é leitura feita na implementação, em 10/10, e está marcada no código como "A CONFIRMAR (Luis)". A borda segue a mesma regra nas respostas que ela mesma escreve (`apiVersion`, em `infra/edgegateway/plugin/handler.go`).
  - A negociação roda antes dos leitores de corpo (`tv3ws/src/app.ts`), então o 101 de JSON malformado também leva o cabeçalho.
  - Até 10/10, os erros 100 e 101 da negociação no tv3ws saíam sem `API-Version`, e o 100 da borda saía com `2.0`.
  - Fora de `/tv3`, o `/health` e o `/manifest` não levam `API-Version`.

---

## Endpoints declarados na borda

A coluna **bind-token** marca as APIs cujo campo "Security requirements" diz que o bind-token *shall* ser enviado. São 27 APIs na norma. Oito delas estão implementadas aqui, em 10 rotas: a norma aceita `current-service` no lugar de `<service-context-id>` (C.3.5).

| Método | Rota | Norma | bind-token |
|--------|------|-------|-----------|
| GET | `/health` | testbed (fora da norma) | |
| GET | `/manifest` | resposta ao `LOCATION` do anúncio SSDP | |
| GET | `/tv3/authorize` | C.6.1.2 | |
| GET | `/tv3/token` | C.6.1.3 | |
| GET | `/tv3/current-service` | C.6.3.1 | |
| POST | `/tv3/bind-context` | C.6.8.2 (borda) | |
| GET | `/tv3/bind-context` | C.6.8.3 (borda) | o próprio token é o objeto da API |
| DELETE | `/tv3/bind-context` | C.6.8.4 (borda) | |
| GET | `/tv3/api-info/{apiId}` | C.6.7.8 (borda) | |
| GET | `/tv3/api-info` | C.6.7.9 (borda) | |
| GET | `/tv3/current-service/apps/{appid}/files` | C.6.4.7 | shall |
| POST | `/tv3/current-service/users` | C.6.14.1 | shall |
| POST | `/tv3/{serviceContextId}/users` | C.6.14.1, em variante com `<scid>` do testbed (a norma define a rota com `current-service`; mesmo handler no tv3ws). PENDENTE: a rota fica ou sai | shall (a borda exige; scid fora de `current-service` e da constante dá 108, L2) |
| GET | `/tv3/current-service/users/{userid}` | C.6.14.2 | shall |
| GET | `/tv3/{serviceContextId}/users/{userid}` | C.6.14.2 | shall |
| GET | `/tv3/current-service/users/current-user` | C.6.14.3 | shall |
| POST | `/tv3/current-service/users/current-user` | C.6.14.4 | shall |
| POST | `/tv3/{serviceContextId}/users/{userid}` | C.6.14.5 | shall |
| GET | `/tv3/current-service/users/files` | C.6.14.6 | shall |
| POST | `/tv3/remote-device` | C.6.15.2 | |
| DELETE | `/tv3/remote-device/{handle}` | C.6.15.3 | |
| GET | `/tv3/remote-device/devices/{classId}` | C.6.15, ver nota | |
| GET | `/tv3/remote-device/device/{handle}` | C.6.15, ver nota | |
| DELETE | `/tv3/remote-device/device/{handle}` | C.6.15, ver nota | |
| GET | `/tv3/sensory-effect-renderers` | C.6.16.1 | |
| GET | `/tv3/sensory-effect-renderers/{rendererId}` | C.6.16.2 | |
| POST | `/tv3/sensory-effect-renderers/{rendererId}` | C.6.16.3 | shall |

**Notas:**

- As rotas `/manifest` e `bind-context` entram na tabela de rotas na semana de 28/09; as de `api-info`, na rodada de 05/10.
- **Rotas "(borda)".** O plugin `tv30-auth` as responde depois da mesma decisão de credencial das demais, sem repasse ao tv3ws. A C.6.8 tem o mesmo contrato que o tv3ws implementava até 05/10, com uma diferença: o `POST` só aceita corpo JSON. A C.6.7.8 e a C.6.7.9 listam as 20 APIs implementadas (o campo `api` do `routes.json`, com o id e a versão da Tabela C.2), todas na versão 2.0. Os detalhes e os comportamentos provisórios estão em `infra/edgegateway/plugin/README.md`, seção *APIs respondidas pela borda*.
- **`GET /tv3/current-service`** (C.6.3.1, Tabela C.8, p. 222; p. 240 do PDF). O serviço em uso é o último valor de `aop/currentService`, que a plataforma publica ao selecionar um serviço e esvazia ao desfazer a seleção (`core.app.sid`, em `tv3ws/src/core.ts`).
  - Sem serviço em uso, a resposta é 404 `{"error":300}`, o erro da tabela para "If the DTV function is not in use in the receiver". O 302 (sem recepção do sinal) não é emitido, porque o testbed não tem estado de recepção.
  - Com serviço em uso, a resposta é 200 com `serviceContextId`, `transportStreamId` e `originalNetworkId`, mais `serviceName` quando é conhecido. O `serviceId` é inteiro, como na Tabela C.8, e fica de fora quando o testbed não o conhece. Hoje ele nunca é conhecido: não há SLT, e o tv3ws só o teria por `aop/services`, que nenhum módulo publica (L2, A6 de [`decisoes-pendentes.md`]({{ site.baseurl }}/decisoes-pendentes)). O `transportStreamId` e o `originalNetworkId` não estão na Tabela C.8.
  - Até 10/10, a rota respondia sempre 200, com o `serviceId` em texto (`"-1"` ou `"undefined"`).
- A antiga `POST /tv3/users` (criação de perfil, fora da norma) **não existe mais**: saiu no commit `8d5949d` da infra. A criação de perfil passou a ser função do gestor de perfis da plataforma, que grava direto no armazenamento (`aop/src/modules/profile-manager/service.js`).
- Remote-device: os comentários de `tv3ws/src/api/multi-device/index.ts` citam C.6.15.5, C.6.15.6 e C.6.15.7. No PDF consultado (`docs/P_ABNTNBR25608_202X_en-US.pdf`), a seção C.6.15 só vai até a C.6.15.5. O fluxo por *handle* corresponde à versão 2.1, a proposta em discussão no Fórum (`basic.ts`).
- Remote-device, portas do WebSocket (corrigido em 10/10; `tv3ws/src/modules/remotedevice-manager/entry-point.ts`). Cada registro (C.6.15.2) e cada ponto de entrada local (listagem 2.0 da C.6.15.5, ou ativação por *handle* da 2.1) abre um `http.Server` próprio numa porta sorteada da faixa `WS_PORT_MIN`–`WS_PORT_MAX` (45000–45199 no compose). A porta só é devolvida na URL depois de estar escutando. Porta ocupada (`EADDRINUSE`) leva a outro sorteio, até 10 vezes; esgotadas as tentativas, a API responde 404 `{"error":200}` (Tabela C.74: "If the request exceeds the number of devices that can be registered on the platform"), sem derrubar o processo. Na remoção do dispositivo, o `terminate()` fecha os dois servidores, inclusive o `http.Server`, e a desativação por *handle* fecha o ponto de entrada local. Até 10/10, a porta seguia escutando depois da remoção, e uma porta ocupada derrubava o tv3ws, pela leitura do código.
- A contagem completa das 27 APIs *shall*, inclusive as ainda não implementadas, está em [`avaliacao-item9-credenciais.md`]({{ site.baseurl }}/avaliacao-item9-credenciais).

---

## Autorização de cliente (`/tv3/authorize` e `/tv3/token`)

**`clientid` repetido dá 101.** Decisão do Luís em 03/10 (A2 de [`decisoes-pendentes.md`]({{ site.baseurl }}/decisoes-pendentes)). O `GET /tv3/authorize` responde 404 `{"error":101}` quando o `clientid` já foi usado, para qualquer classe de cliente, com ou sem `pm`. Na norma:
- Tabela C.3, erro 101: "if clientid has been used before" (p. 215; p. 233 do PDF);
- C.6.1.4.4: no mesmo servidor, passar ao C.6.1.2 um `clientid` já usado é colisão e dá 101 (p. 219; p. 237 do PDF).

No tv3ws, "já usado" vale para dois casos, os dois sem pop-up (`checkAuthorization`, em `tv3ws/src/api/client-identification/controller.ts`, com uma leitura só, `clientIdStatus`):
- o cliente já autorizado, que está em `clients:authorized` ou tem o registro `client:{clientid}` no Redis, gravados quando o espectador o autoriza (`tv3ws/src/modules/auth-manager/manager.ts`);
- o cliente recusado pelo espectador, que fica em `clients:blocked`. A Tabela C.3 diz que, nesse caso, "any attempt to authorize immediately returns error 101, without displaying the authorization dialog". Até 03/10, o tv3ws respondia 102 aqui. Este segundo caso é conformidade com a nota da tabela, numa leitura da decisão de 03/10 feita na implementação, e **ainda espera a confirmação do Luís**.

O 101 não cobre o reuso **simultâneo**: um segundo `/tv3/authorize` com o mesmo `clientid` enquanto o pop-up do primeiro ainda está aberto abre outro pop-up (ver `KNOWN-ISSUES.md`).

**Autorizados e bloqueados** (D-0510-4, reunião de 05/10 com o Joel). O tv3ws guarda os clientes autorizados no SET `clients:authorized` e os recusados em `clients:blocked`. Um id fica em no máximo um dos dois, porque autorizar e bloquear são transações (`MULTI`).
- O `/tv3/token` só emite para quem está em `clients:authorized`. Um cliente bloqueado depois de autorizado recebe 102, como pede a C.4.2.2 ("it is not able to request the access token", p. 208; p. 226 do PDF). Até 05/10, bastava o `client:{id}` existir.
- Hoje o bloqueio só acontece na recusa do pop-up (ou quando ele expira). A tela de gerenciamento que a C.4.2.2 pede, onde o espectador consulta o histórico e bloqueia ou desbloqueia, não existe; `listAuthorizedClients` e `listBlockedClients` (`manager.ts`) são a base dela.
- A borda recusa com 107 o token de um `sub` que está em `clients:blocked`. Ela não confere `clients:authorized` (ponto em aberto, E6 de [`decisoes-pendentes.md`]({{ site.baseurl }}/decisoes-pendentes)).

O 102 fica só para a recusa no próprio pop-up ("If the user does not grant access"). Até 03/10, o cliente local já autorizado que chamava o `/tv3/authorize` de novo sem `pm` recebia o refresh token corrente, sem pop-up. Esse atalho saiu.

**O que o cliente faz** (C.6.1.4.5, p. 219; p. 237 do PDF):
1. Gera um `clientid` no formato UUID da RFC 9562 (C.6.1.4.3) e o guarda.
2. Chama o `/tv3/authorize` uma vez. O local autônomo recebe o refresh token direto. O não local recebe o `challenge` e obtém o primeiro access token e o refresh token no `/tv3/token`.
3. Guarda o refresh token. Nos acessos seguintes, chama `GET /tv3/token?clientid=<id>&refresh-token=<rt>`, sem voltar ao `/tv3/authorize`.
4. Guarda sempre o último refresh token recebido: o tv3ws troca o refresh token a cada `/tv3/token` (`rotateRefreshToken`, em `manager.ts`).

**Resposta do não local por método de pareamento** (Tabela C.3, formatos 2 e 3, p. 214; p. 232 do PDF):
- `pm=qrcode`: `{"challenge"}`. A chave vai no QR code que a TV mostra.
- `pm=kex`: `{"challenge","key"}`. O `key` é a chave parcial ECDH do servidor (ponto SEC 1 sem compressão, em base64 URL safe, C.4.3.4). O cliente deriva dela o segredo (C.4.3.3) e resolve o `challenge`. Até a integração de 04/10, o tv3ws respondia só `{"challenge"}` no `kex`, e o pareamento por PIN não se completava. A correção é de conformidade (Tabela C.3, formato 3; C.4.3.3, passo 1) e espera o aval do Luís. Desde 10/10, o PIN que a TV mostra sai com quatro dígitos, com zeros à esquerda (`0042`), porque a C.4.3.3 diz que ele é "a four-digit number" (p. 211; p. 229 do PDF); até ali saía `42` (`pinFromHash`, em `tv3ws/src/api/client-identification/service.ts`).

**Quem perdeu o refresh token** precisa de `clientid` novo e de nova autorização do espectador, com novo pop-up. É o caso da recarga de página sem armazenamento persistente e do armazenamento apagado. O mesmo vale quando o `/tv3/token` responde 101 porque o refresh token não está associado ao cliente (C.6.1.4.5). Repetir o `clientid` antigo só dá 101.

**Verificado na stack em 04/10**, na integração e de novo na rodada de correção, com um script de curl que **não faz parte do repositório** (não há teste versionado que reproduza esta seção). Duas cargas seguidas de um cliente local autônomo:
- a primeira carga autoriza um `clientid` novo, com pop-up;
- a segunda usa só o `/tv3/token` com o refresh token guardado, sem pop-up, e a API responde 200;
- o refresh token já trocado dá 101;
- repetir o `clientid` no `/tv3/authorize` dá 101, sem pop-up;
- com o armazenamento apagado, um `clientid` novo abre o pop-up de novo.

Páginas do bcast que chamam a API (users-test e webmedia): o navegador não foi usado. O script baixou a página e reproduziu por curl a sequência de chamadas dela, com o serviço sintonizado pelo catálogo do AoP e o `Origin` do AoP (`http://localhost:8080`). As duas cargas deram respostas iguais entre si:
- users-test: a lista (`POST /tv3/current-service/users`) deu 404 `{"error":300}` nas duas cargas, e o `current-user` deu 200. O 300 vem de `resolveActiveService` (`tv3ws/src/api/user/service.ts`): nenhum perfil tem esse serviço em `user:{id}:consent` (visibilidade de perfil, C.6.14.1), e o tv3ws trata o serviço como não ativo;
- webmedia: a lista deu 200 com 5 perfis, e os detalhes e o `current-user` deram 200, nas duas cargas; o `remote-device` (`Accept-Version: 2.1`) também deu 200.

Nenhuma dessas chamadas usa o `/tv3/authorize`, então o resultado não depende da D-L2. Em `warn`, a chamada da lista levou `X-TV30-Auth-Warn: 107` nas duas páginas e nas duas cargas (o aviso das outras chamadas não foi registrado), porque o `Origin` do AoP não está em `origins:associated`, que tinha só `http://bcast:8081` (P1.3, ver `KNOWN-ISSUES.md`).

**Consumidores neste repositório.** Nenhum app do bcast nem o aop chama o `/tv3/authorize`. Os `clientId` fixos que aparecem neles (`bcast_svc`, `aop-core`, `rp-display`) são identificadores de cliente MQTT. O único consumidor é o `scripts/test-auth.sh`, que gera um `clientid` novo a cada execução.

---

## Filtragem de usuários (`POST /tv3/current-service/users`)

O corpo aceita expressões de filtro (`and`, `or` e expressão simples):

```json
{
  "or": [
    { "attribute": "parentalControl", "comparator": "eq", "value": "false" },
    {
      "and": [
        { "attribute": "parentalControl", "comparator": "eq", "value": "true" },
        { "attribute": "maxContentRating", "comparator": "gte", "value": "14" }
      ]
    }
  ]
}
```

Os comparadores são `eq`, `neq`, `lt`, `lte`, `gt` e `gte`.

Com um serviço corrente ativo (`session:current-service-id`), a listagem só traz usuários cujo `user:{id}:consent` contém esse serviço. Sem serviço ativo, a listagem traz **todos** (`tv3ws/src/api/user/service.ts`, `getUserList`).

Esse *consent* é a visibilidade do perfil por serviço guardada no Redis. Não é o consentimento da seção 8.8 da norma.

---

## Proxy puro na borda

Toda rota que a borda repassa ao tv3ws é **proxy puro** (`output_encoding: "no-op"`, `infra/edgegateway/generate.js`). O status, os cabeçalhos e o corpo do tv3ws passam sem reinterpretação, o que inclui as respostas binárias (`GET .../users/files`) e as de texto. A exceção é o 5xx do próprio KrakenD (backend lento ou fora do ar), que o plugin troca por 404 `{"error":200}`. As rotas marcadas "(borda)" na tabela acima não são repassadas: o plugin as responde.
