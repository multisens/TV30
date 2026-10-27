---
title: APIs do tv3ws
parent: Como funciona
nav_order: 2
---

# APIs do tv3ws

O **tv3ws** é a implementação dos **TV 3.0 WebServices** da ABNT NBR 25608 (Anexo C) neste testbed. O roteamento das APIs fica em `tv3ws/src/app.ts`; o `/manifest` é registrado à parte, no boot (`tv3ws/src/manifest.ts`).

Dois grupos de APIs declarados na borda **não** chegam ao tv3ws: a borda os responde sozinha (C.6.8, `/tv3/bind-context`, e C.6.7.8/C.6.7.9, `/tv3/api-info`). Eles aparecem na tabela abaixo, marcados "(borda)". Qual processo responde cada API é decisão deste testbed; a norma só define as APIs.

O cliente não fala com o tv3ws diretamente: todo acesso às APIs passa pela **borda** ([Borda e credenciais]({{ site.baseurl }}/borda-credenciais)). As duas superfícies têm as 27 rotas: a interna, `http://<host>:44642` (`Server-BaseURL`), e a externa, `https://<host>:44643` (`Server-SecureBaseURL`, com TLS). A exceção são os WebSockets de remote-device: o tv3ws publica a faixa 45000–45199 no host, e o cliente abre direto a URL que a API devolve. O ponto de entrada do dispositivo remoto (registro, C.6.15.2) sai em `wss://<SERVER_URL>:<porta>`, com o certificado do receptor (ou `ws://` com `TV3WS_WS_TLS=false`); o local (C.6.15.5 e ativação por *handle*), sempre em `ws://<SERVER_URL>:<porta>`.

> Borda, mensageria e Redis são decisões de implementação do testbed, não da norma.

---

## Acesso, credenciais e versionamento

- **Credenciais.** Quem valida é a borda (plugin `tv30-auth`); o tv3ws não valida credencial. O tv3ws emite a credencial (`/tv3/authorize`, `/tv3/token`) e recusa com 106 a emissão ao cliente local associado. O `/tv3/token` responde 106 à renovação do não local por HTTP.
- **Contexto de serviço.** O `{serviceContextId}` das rotas `/tv3/{serviceContextId}/...` e o `serviceContextId` das respostas (C.6.3.1, C.6.8) são o `globalServiceId` do BAM; `current-service` é o serviço selecionado (C.3.5).
- **Erros.** Formato C.3.2: status 404 com corpo `{"error": <n>, "description": "..."}`.
- **Falha do Redis.** Comando sem resposta em 1,5 s falha (`tv3ws/src/redis-client.ts`), e a API responde 404 `{"error":200}`.
- **CORS.** Quem aplica é a borda. O tv3ws não envia cabeçalhos CORS, com uma exceção: o `/manifest` manda `Access-Control-Expose-Headers` com os seis nomes da C.3.4.
- **Versão (C.3.6).** Quem negocia é a borda, rota a rota, pelas versões do `routes.json` (campo `versions`; ausente = 2.0). Sem `Accept-Version` vale a 2.0; fora do formato X.Y, 101; versão que a rota não serve, 100. A versão decidida chega ao tv3ws no cabeçalho interno `X-TV30-API-Version`, e ele responde nela, com `API-Version` em toda resposta (C.3.6.6). No erro 100, `API-Version` é a versão mais recente do servidor, 100.0.
  - **2.0** é a norma. **100.0** é uma extensão do testbed com a proposta v2 da C.6.15 (as versões de 100 em diante ficam reservadas às extensões do testbed). O registro, o cancelamento e a listagem de dispositivos remotos servem as duas; a atualização do registro (`POST /tv3/remote-device/{handle}`) e as notificações (`GET /tv3/notifications/{className}`, `DELETE /tv3/notifications/{handle}`) só existem na 100.0: pedidas com 2.0, ou sem o cabeçalho, dão 100.
  - **Caminho interno das extensões.** Nas versões de 100 em diante, a borda repassa ao tv3ws em `/v<X.Y>` + o caminho público, e o tv3ws registra os tratadores da 100.0 sob `/v100.0` (`tv3ws/src/v100.0/`). O cliente usa só o caminho público: `/v...` vindo dele não é rota declarada e dá 100.
  - Fora de `/tv3`, o `/health` e o `/manifest` não levam `API-Version`.

---

## Endpoints declarados na borda

As 27 rotas do `infra/edgegateway/routes.json`. **`auth`** = `none`, `token` ou `token+bind`; **`classes`** = as classes de cliente que a rota admite ("todas" quando o campo falta); **versões** = as que a rota serve. Na externa, as rotas só do cliente local e o `/tv3/authorize` respondem 106 a qualquer requisição (C.4.1.8); na interna, o não local recebe 106 fora de `/tv3/authorize` e `/tv3/token` (C.4.1.6).

| Método | Rota | Norma | `auth` | `classes` | versões |
|--------|------|-------|--------|-----------|---------|
| GET | `/health` | testbed (fora da norma) | `none` | todas | 2.0 |
| GET | `/manifest` | resposta ao `LOCATION` do anúncio SSDP | `none` | todas | 2.0 |
| GET | `/tv3/authorize` | C.6.1.2 | `none` | `standAlone`, `nonLocal` | 2.0 |
| GET | `/tv3/token` | C.6.1.3 | `none` | `standAlone`, `nonLocal` | 2.0 |
| GET | `/tv3/current-service` | C.6.3.1 | `token` | todas | 2.0 |
| POST | `/tv3/bind-context` | C.6.8.2 (borda) | `none` | `associated` | 2.0 |
| GET | `/tv3/bind-context` | C.6.8.3 (borda) | `token` | `standAlone`, `nonLocal` | 2.0 |
| DELETE | `/tv3/bind-context` | C.6.8.4 (borda) | `none` | `associated` | 2.0 |
| GET | `/tv3/api-info/{apiId}` | C.6.7.8 (borda) | `token` | todas | 2.0 |
| GET | `/tv3/api-info` | C.6.7.9 (borda) | `token` | todas | 2.0 |
| GET | `/tv3/current-service/apps/{appid}/files` | C.6.4.7 | `token+bind` (300 sem serviço) | todas | 2.0 |
| POST | `/tv3/current-service/users` | C.6.14.1 | `token+bind` (300 sem serviço) | todas | 2.0 |
| GET | `/tv3/current-service/users/{userid}` | C.6.14.2 | `token+bind` (300 sem serviço) | todas | 2.0 |
| GET | `/tv3/{serviceContextId}/users/{userid}` | C.6.14.2 | `token+bind` (300 sem serviço; 304 fora do catálogo) | todas | 2.0 |
| GET | `/tv3/current-service/users/current-user` | C.6.14.3 | `token+bind` (300 sem serviço) | todas | 2.0 |
| POST | `/tv3/current-service/users/current-user` | C.6.14.4 | `token+bind` (300 sem serviço) | todas | 2.0 |
| POST | `/tv3/{serviceContextId}/users/{userid}` | C.6.14.5 | `token+bind` (300 sem serviço; 304 fora do catálogo) | todas | 2.0 |
| GET | `/tv3/current-service/users/files` | C.6.14.6 | `token+bind` (300 sem serviço) | todas | 2.0 |
| POST | `/tv3/remote-device` | C.6.15.2 | `token` | todas | 2.0, 100.0 |
| POST | `/tv3/remote-device/{handle}` | C.6.15.2 (atualização) | `token` | todas | 100.0 |
| DELETE | `/tv3/remote-device/{handle}` | C.6.15.3 | `token` | todas | 2.0, 100.0 |
| GET | `/tv3/remote-device/devices/{classId}` | C.6.15.5 | `token` | `associated`, `standAlone` | 2.0, 100.0 |
| GET | `/tv3/notifications/{className}` | C.6.2.2 (só na 100.0) | `token` | `associated`, `standAlone` | 100.0 |
| DELETE | `/tv3/notifications/{handle}` | C.6.2.3 (só na 100.0) | `token` | `associated`, `standAlone` | 100.0 |
| GET | `/tv3/sensory-effect-renderers` | C.6.16.1 | `token` | todas | 2.0 |
| GET | `/tv3/sensory-effect-renderers/{rendererId}` | C.6.16.2 | `token` | todas | 2.0 |
| POST | `/tv3/sensory-effect-renderers/{rendererId}` | C.6.16.3 | `token+bind` (108 sem serviço) | todas | 2.0 |

**Notas:**

- **C.6.7.8 e C.6.7.9 (borda).** Listam as 22 APIs implementadas nas duas superfícies, cada uma com a versão mais recente que serve (100.0 para as APIs da C.6.15 e da C.6.2, 2.0 para as demais). Um id da Tabela C.2 não implementado dá 101; sem `subsystem`, a lista traz todas.
- **`GET /tv3/current-service`** (C.6.3.1, Tabela C.8). Sem serviço em uso, 404 `{"error":300}`. Com serviço, 200 com `serviceContextId` (o `globalServiceId`), `transportStreamId` e `originalNetworkId`. O `serviceName` e o `serviceId` inteiro ficam de fora: sem SLT, o testbed não os tem, e o `aop/services` só traz o `serviceContextId`. O 302 não é emitido ([Não implementado]({{ site.baseurl }}/nao-implementado)).
- **304 (serviço fora do catálogo).** Na C.6.14.2 e na C.6.14.5 com `{serviceContextId}` explícito, a borda responde 304 ("DTV service not found", Tabelas C.71 e C.74) ao serviço fora de `services:announced`, a lista dos serviços anunciados na LLS que o AoP grava e que o Application Catalog mostra; `current-service` não confere. Vem depois do 107 e do 300 e antes do bind-token, para todo cliente e nos dois modos; Redis fora, 200.
- **`POST /tv3/current-service/users/current-user`** (C.6.14.4, Tabela C.73). Sem `id` no corpo, 105; sem serviço DTV em uso, 300; `id` fora de `users:index`, 305; perfil que não deu acesso à emissora do serviço corrente (`user:{id}:consent`), 405 (`setCurrentUser`, em `tv3ws/src/api/user/service.ts`). Aceito, o tv3ws grava `session:current-user` e publica `aop/currentUser` retido.
- **`POST /tv3/{serviceContextId}/users`** não existe na norma (só `POST /tv3/current-service/users`, C.6.14.1) e não é rota declarada: a borda responde 100.
- **Efeitos sensoriais (C.6.16).** A capacidade de posição do aparelho é `location` (Tabela A.45). No comando da C.6.16.3, valem as propriedades da Tabela A.30 (`intensityValue`, `color`, `scent`, `frequency`) e os atributos de posição da A.3.19 (`azimuthal`, `polar`, `width`, `height`, `direction`, `location`); outro nome dá 101 (`tv3ws/src/api/sensory-effect/service.ts`). O valor das propriedades não é conferido: `scent` aceita qualquer texto. Nas amostras do aquário (`bcast/public/hls/aquario*/events.json`), o efeito de cheiro manda `scent: "sea"` junto com `intensityValue`.
- **Remote-device, portas do WebSocket** (`tv3ws/src/modules/remotedevice-manager/entry-point.ts`). Cada registro (C.6.15.2) e cada ponto de entrada local abre um servidor próprio numa porta sorteada da faixa `WS_PORT_MIN`–`WS_PORT_MAX`, sem o máximo. O do dispositivo remoto (registro) tem TLS com o certificado do receptor quando ele existe (`wss://`, Tabela C.76), salvo com `TV3WS_WS_TLS=false`. O local (C.6.15.5 e ativação por *handle*) sai sempre em `ws://`, no esquema do `Server-BaseURL` que o cliente local usa; a Tabela C.80 pede `wss://` ([Não implementado]({{ site.baseurl }}/nao-implementado)). Porta ocupada leva a outro sorteio, em até 10 tentativas (`LISTEN_ATTEMPTS`); esgotadas, 404 `{"error":200}`. A remoção do dispositivo fecha os servidores dele.
- **Dispositivo remoto e `wss://`.** Um aparelho não abre `wss://` com certificado autoassinado em que não confia. Confie nele o `.tv30/tls/cert.pem`, ou rode o tv3ws com `TV3WS_WS_TLS=false`. A app de navegador no ponto de entrada local não depende do certificado.

---

## Autorização de cliente (`/tv3/authorize` e `/tv3/token`)

**`clientid` repetido dá 101.** O `GET /tv3/authorize` responde 404 `{"error":101}` quando o `clientid` já foi usado, para qualquer classe de cliente, com ou sem `pm`. Na norma:
- Tabela C.3, erro 101: "if clientid has been used before";
- C.6.1.4.4: no mesmo servidor, passar ao C.6.1.2 um `clientid` já usado é colisão e dá 101.

No tv3ws, "já usado" vale para dois casos, os dois sem pop-up (`checkAuthorization`, em `tv3ws/src/api/client-identification/controller.ts`, com uma leitura só, `clientIdStatus`):
- o cliente já autorizado, que está em `clients:authorized` ou tem o registro `client:{clientid}` no Redis, ou que está no cache em memória dos autorizados do próprio tv3ws (`clientIdStatus`, em `tv3ws/src/modules/auth-manager/manager.ts`);
- o cliente recusado pelo espectador, que fica em `clients:blocked`. A Tabela C.3 diz que, nesse caso, "any attempt to authorize immediately returns error 101, without displaying the authorization dialog".

A tentativa pendente do não local (o "sim" dado e o pareamento não concluído) não conta como uso: um novo `/tv3/authorize` com o mesmo `clientid` a descarta e segue como pedido novo, com 103 se a camada gráfica estiver ocupada e, senão, o pop-up.

**103 com a camada gráfica ocupada.** Um pedido de autorização de cada vez: enquanto houver na tela o sim/não de um pedido esperando resposta, ou o QR code ou o PIN de um pareamento, o `/tv3/authorize` responde 404 `{"error":103}` na hora, sem pop-up (C.4.2.3: "If there is any restriction preventing the pop-up from being displayed at that time, the implementation shall immediately send a response to the request with error code 103, so that the client can try again later"; Tabela C.3: "103: When the TV 3.0 receiver is unable to display the authorization pop-up"). O cliente tenta de novo depois. Vale também para o reuso **simultâneo**: um segundo `/tv3/authorize` com o mesmo `clientid` enquanto o sim/não do primeiro espera resposta. O 103 vem depois do 105 e do 101. A camada libera no fim do pedido, no sucesso do pareamento (o `/tv3/token` com o desafio resolvido) ou no fim da trava de 120 s do QR code e do PIN (`reservarCamada`, em `tv3ws/src/api/client-identification/service.ts`).

**Autorizados e bloqueados.** O tv3ws guarda os clientes autorizados no SET `clients:authorized` e os recusados em `clients:blocked`. Um id fica em no máximo um dos dois, porque autorizar e bloquear são uma função do Redis cada (`tv30_cliente_autoriza` e `tv30_cliente_bloqueia`), que tira o id de um conjunto e o põe no outro.
- **Quando grava.** O "não" é gravado na hora, em `clients:blocked`, para as duas classes. O "sim" do local autônomo é gravado na hora (`client:{id}` e `clients:authorized`). O "sim" do não local fica só na memória do tv3ws, como tentativa pendente com o material do pareamento (`StartPairing`, em `manager.ts`): `client:{id}` e `clients:authorized` só são gravados quando o `/tv3/token` confere o `challenge-response` (`AuthorizePairedClient`), e só então sai a credencial. Se essa gravação falhar, a resposta é 404 `{"error":200}`, e o material volta ao cliente. A trava de 120 s só fecha o pop-up; um reinício do tv3ws perde a tentativa.
- **No `/tv3/token`,** o fluxo por `challenge-response` aceita a tentativa pendente; o por `refresh-token` exige a autorização gravada (`clients:authorized`). Sem o que o fluxo exige, 102. Um cliente bloqueado depois de autorizado recebe 102, como pede a C.4.2.2 ("it is not able to request the access token").
- O bloqueio só acontece na recusa do pop-up (ou quando ele expira). A tela de gerenciamento da C.4.2.2 não existe ([Não implementado]({{ site.baseurl }}/nao-implementado)).
- A borda recusa com 107 o token de um `sub` que está em `clients:blocked`, o de um `sub` que não está em `clients:authorized` e o token sem `sub`. Vale nas rotas que pedem token, para toda classe; o bloqueio é conferido antes e mantém a mensagem dele. O token de classe `associated` segue a regra geral, com bind-token nas rotas `token+bind`; o tv3ws não emite essa classe.

O 102 fica só para a recusa no próprio pop-up ("If the user does not grant access"), o que inclui o pop-up que expira sem resposta: o tempo esgotado conta como recusa e também bloqueia o cliente (`showYesNoPopUpAsync`, em `tv3ws/src/core.ts`, e `checkAuthorization`, em `controller.ts`).

**Erros do `GET /tv3/authorize`** (Tabela C.3), nesta ordem:

| Código | Situação |
|---|---|
| 106 | `Origin` em `origins:associated`: o associado não obtém credencial (C.4.1.1). A borda o recusa antes |
| 105 | Falta `clientid`, `display-name` ou, no `kex`, `key`. Parâmetro vazio ou só com espaços conta como ausente |
| 101 | `pm` não suportado, ou `clientid` já usado (autorizado ou bloqueado) |
| 103 | A camada gráfica está ocupada pelo sim/não de outro pedido, ou pelo QR code ou o PIN de um pareamento, também para o mesmo `clientid` |
| 102 | O espectador recusou no pop-up, ou o pop-up expirou |

**Erros do `GET /tv3/token`** (Tabela C.4):

| Código | Situação |
|---|---|
| 105 | Falta `clientid`, ou faltam o `challenge-response` e o `refresh-token` |
| 106 | Cliente não local com `refresh-token` por HTTP; cliente registrado como associado |
| 102 | Cliente sem a autorização que o fluxo exige; `challenge-response` errado, que não decifra ou repetido na URL; `challenge-response` sem desafio pendente (repetido depois do sucesso, de cliente local ou depois de um reinício do tv3ws) |
| 101 | `refresh-token` que não pertence ao cliente, ou repetido na URL |
| 200 | Falha da plataforma, como o Redis fora do ar, inclusive na gravação da autorização do não local |

**O access token.** JWT HS256 assinado com o `JWT_SECRET`, com os claims `iat`, `nbf`, `exp` (24 h), `iss` (o `JWT_ISSUER`, padrão `GenericIssuer`), `sub` (o `clientid`) e `class` (`tv3ws/src/modules/auth-manager/manager.ts`). O `/tv3/token` reaproveita o token já emitido enquanto ele vale, e o `expiresIn` é o tempo que resta, em segundos (C.6.1.3). O refresh token é trocado a cada chamada.

**O que o cliente faz** (C.6.1.4.5):
1. Gera um `clientid` no formato UUID da RFC 9562 (C.6.1.4.3) e o guarda.
2. Chama o `/tv3/authorize` uma vez. O local autônomo recebe o refresh token direto. O não local recebe o `challenge` e obtém o primeiro access token e o refresh token no `/tv3/token`, que conclui o pareamento e grava a autorização.
3. Guarda o refresh token. Nos acessos seguintes, chama `GET /tv3/token?clientid=<id>&refresh-token=<rt>`, sem voltar ao `/tv3/authorize`.
4. Guarda sempre o último refresh token recebido: o tv3ws troca o refresh token a cada `/tv3/token` (`rotateRefreshToken`, em `manager.ts`).

**Resposta do não local por método de pareamento** (Tabela C.3, formatos 2 e 3):
- `pm=qrcode`: `{"challenge"}`. A chave vai no QR code que a TV mostra.
- `pm=kex`: `{"challenge","key"}`. O `key` é a chave parcial ECDH do servidor (ponto SEC 1 sem compressão, em base64 URL safe, C.4.3.4). O cliente deriva dela o segredo (C.4.3.3) e resolve o `challenge`. O PIN que a TV mostra sai com quatro dígitos, com zeros à esquerda (`0042`): a C.4.3.3 diz que ele é "a four-digit number" (`pinFromHash`, em `tv3ws/src/api/client-identification/service.ts`).

**O QR code e o PIN ficam na tela até o fim do pareamento** (C.4.3.2, C.4.3.3). O fim do pareamento é o `GET /tv3/token` que confere o `challenge-response` com sucesso: logo depois da resposta, o tv3ws manda a camada gráfica fechar o pop-up daquele cliente (`{"close":true}` no tópico do pop-up; [Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos)). O pop-up vai com uma trava de 120 s (`PAIRING_POPUP_TIMEOUT_MS`), escolha do projeto, para não ficar preso se o cliente desistir. O `/tv3/token` que falha não fecha o pop-up.

**Parâmetro vazio conta como ausente.** Em `/tv3/authorize` e `/tv3/token`, um parâmetro vazio ou só com espaços (`clientid=`, `display-name=`, `pm=`, `key=`, `refresh-token=`, `challenge-response=`) vale como não informado (`queryParam`, em `tv3ws/src/api/client-identification/controller.ts`): o exigido dá 105 (Tabelas C.3 e C.4), e `pm=` vazio deixa o cliente local, como quem não manda `pm`.

**O desafio vale uma vez.** Depois do `challenge-response` conferido, o tv3ws descarta o challenge, a chave simétrica e o par ECDH do cliente; a Tabela C.4 diz que a chave "can be discarded" depois do primeiro acesso. Repetir a resposta dá 102 ("If the challenge-response value is not validated by the TV 3.0 receiver as correct"), o mesmo do desafio errado; o cliente local que manda `challenge-response`, também. O `challenge-response` que não decifra (tamanho ou *padding* inválido no AES, ou o parâmetro repetido na URL) também dá 102. O desafio errado deixa a tentativa aberta, e o challenge não expira.

**Comparações em tempo constante:** o refresh token e a resposta ao desafio são comparados com `crypto.timingSafeEqual`, em bytes (`safeEqual`, em `tv3ws/src/util/encryption.ts`; `validateRefreshToken` e `validateChallenge`, em `tv3ws/src/modules/auth-manager/client.ts`).

**Quem perdeu o refresh token** precisa de `clientid` novo e de nova autorização do espectador, com novo pop-up. É o caso da recarga de página sem armazenamento persistente e do armazenamento apagado. O mesmo vale quando o `/tv3/token` responde 101 porque o refresh token não está associado ao cliente (C.6.1.4.5). Repetir o `clientid` antigo só dá 101.

**Testes.** A sequência (primeira autorização, reuso com 101, refresh token guardado e trocado, `clientid` novo com novo pop-up) é coberta fora da stack, com dublês, em `tv3ws/test/client-identification.test.ts`, e na stack, em parte, pelo `scripts/test-auth.sh` ([Como testar]({{ site.baseurl }}/como-testar)).

**Consumidores neste repositório.** Nenhum app do bcast nem o aop chama o `/tv3/authorize`. Os `clientId` fixos que aparecem neles (`bcast_svc`, `aop-core`, `rp-display`) são identificadores de cliente MQTT. Os únicos consumidores são os testes: o `scripts/test-auth.sh`, que gera um `clientid` novo a cada execução, e os testes de unidade do tv3ws (`tv3ws/test/client-identification.test.ts`).

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

Com um serviço corrente ativo (`session:current-service-id`), a listagem só traz usuários cujo `user:{id}:consent` contém esse serviço. Sem serviço ativo, a listagem responde 404 `{"error":300}` ("No DTV service currently in use"; `getUserList`, em `tv3ws/src/api/user/service.ts`). Conta como sem serviço ativo também o serviço corrente que nenhum dos perfis existentes tem em `user:{id}:consent` (`resolveActiveService`, no mesmo arquivo), o que diverge da norma ([Não implementado]({{ site.baseurl }}/nao-implementado)). Sem nenhum perfil em `users:index`, o serviço corrente vale, e a lista sai vazia.

Esse *consent* é a visibilidade do perfil por serviço guardada no Redis. Não é o consentimento da seção 8.8 da norma.

---

## Atributos de emissora e o aviso ao espectador (C.6.14.5)

**`POST /tv3/{serviceContextId}/users/{userid}`** (C.6.14.5, Tabela C.74). O corpo é um objeto de atributos; valor `""` remove o atributo. O tv3ws grava no hash `user:{id}:broadcaster-attrs:{scid}`, pela função `tv30_atributos_emissora` (`writeBroadcasterAttrs`, em `tv3ws/src/api/user/service.ts`), e responde o JSON dos atributos enviados. Corpo sem atributo, ou com `id`, `nickname`, `parentalControl` ou `maxContentRating`, dá 101; perfil inexistente, 305; perfil não visível no serviço, 405; `current-service` sem serviço em uso, 300; serviço do caminho fora do Application Catalog, 304 (na borda); mais de 20 MB no hash resultante, 404 `{"error":200}`.

**O aviso.** A Tabela C.74, em "Restrictions", diz que "it is necessary to notify the user that the application wants to change/add the attribute". O tv3ws avisa, sem pedir confirmação ([Decisões]({{ site.baseurl }}/decisoes)). Depois de gravar, e só se algum valor mudou (gravar o mesmo valor ou remover um atributo que não existe não avisa), o tv3ws publica, sem retenção, em `aop/display/layers/popup/info` (`notifyUserOfWrite`):

```json
{"value": "A emissora <serviço> atualizou os dados do perfil <apelido>.", "timeout": 5000}
```

- `<serviço>` é o `serviceName` do serviço corrente (o hash `session:current-service`, com os campos da Tabela C.8) quando a gravação é no contexto dele; sem nome, ou com outro `<service-context-id>`, o id do serviço da gravação. O `serviceName` não tem fonte no testbed (o `aop/services` só traz o `serviceContextId`), então na stack o aviso traz o id (por exemplo, `urn:tv30:service:users-test`);
- `<apelido>` é o `nickname` do perfil; sem ele, o texto termina em "...dados do perfil.";
- gravação recusada ou que falha não avisa; falha ao montar ou publicar o aviso só vai para o log, e a resposta da API continua a de sucesso;
- a mudança é medida contra o hash lido antes da gravação (o mesmo da conferência da quota), que não é atômico com ela: uma escrita concorrente no meio pode decidir o aviso pelo estado lido.

A camada gráfica do AoP mostra o aviso por 5 s, escapado e sem botões, e não tira da tela um sim/não, QR code ou PIN aberto: ele espera numa fila e aparece quando a camada fica livre ([Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos)).

---

## Arquivos da aplicação e do perfil (C.6.4.7 e C.6.14.6)

As duas rotas leem arquivos do disco do tv3ws a partir de um `path` que o cliente manda. O caminho é resolvido **dentro** de um diretório-base e não sai dele (`resolveInsideDir`, em `tv3ws/src/util/safe-path.ts`):
- a barra no começo é opcional, e o caminho é sempre a partir da base (Tabela C.17: "even with its use, the path from the base directory shall be responded"): `/etc/passwd` é o `etc/passwd` de dentro da base;
- `..` que sai da base é recusado, inclusive o que veio codificado na URL (`%2e%2e%2f`), que a query já entrega decodificado; nada se decodifica de novo;
- barra invertida e NUL são recusados; o separador é só `/`;
- link simbólico vale pelo destino real, que também tem de estar dentro da base;
- base vazia ou ausente é recusa.

Caminho recusado e caminho inexistente têm a mesma resposta: o 305 de cada API. Outras falhas do sistema de arquivos (permissão, por exemplo) dão 404 `{"error":200}`.

**`GET /tv3/current-service/apps/{appid}/files[?path=<path>]`** (C.6.4.7, Tabela C.17). A base é o diretório da aplicação corrente, que o tv3ws recebe no tópico `aop/<sid>/<appId>/path` (`core.app.url`; [Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos)).
- `appid` que não é o da aplicação corrente: 305. O `appid` só é comparado e não entra em caminho nenhum.
- Caminho recusado ou inexistente: 305 ("the path indicated in `<path>` does not exist in the application's filesystem").
- Arquivo: o conteúdo, com o MIME da extensão; `Range` em vídeo e áudio dá 206 com o trecho.
- Diretório, ou `path` omitido, vazio ou `/`: a estrutura de primeiro nível, em JSON, no formato da Tabela C.17, `{"files": [{"name", "size"}], "dirs": [{"name"}]}`. Escolhas da implementação, que a tabela não trata: arquivo comum vai em `files`, com o tamanho em bytes; link simbólico entra pelo destino, e só se o destino estiver dentro da base; outros tipos (socket, fifo) e nomes com barra invertida ficam de fora; a ordem é por nome.
- Sem diretório da aplicação conhecido (`core.app.url` vazio: depois da troca de serviço ou de aplicação e antes de chegar o `.../path` da nova): 305 (`tv3ws/src/api/aop-communication/app-files/service.ts`).

**`GET /tv3/current-service/users/files?path=<path>`** (C.6.14.6, Tabela C.75). A base é o `USER_THUMBS` do tv3ws, o diretório de miniaturas (`user-files/thumbs`, o mesmo em que o AoP grava o avatar de cada perfil).
- Sem query: 105.
- O arquivo só sai se o texto do `path` for igual ao campo `avatar` de algum perfil visível no serviço corrente (`checkConsent`, em `tv3ws/src/api/user/service.ts`). O `avatar` é o nome do arquivo (o AoP grava `<id do perfil>.svg`; a carga traz `c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10.svg`), e o `path` que o cliente manda é esse nome, como a C.6.14.2 o devolve. Basta um perfil visível com aquele `avatar`. Se ele só é o `avatar` de perfis que não são visíveis no serviço, a resposta é 405, o código da Tabela C.75 para "If the user has not granted access to the broadcaster corresponding to the informed service"; se não é o `avatar` de perfil nenhum, 305. A visibilidade é o `user:{id}:consent` do testbed, e não o consentimento da seção 8.8.
- Caminho fora de `USER_THUMBS` ou inexistente: 305 ("If a non-existent `<path>` is specified in the receiver"). O esquema do Redis confere o `avatar` (nome de arquivo sem diretório, com extensão `.svg`, `.png`, `.jpg`, `.jpeg` ou `.webp`), e o AoP grava o nome que ele mesmo gera; a conferência do caminho no tv3ws vale para qualquer valor do campo.
- `Content-Type` pela extensão do arquivo, como pede a Tabela C.75 ("derived from its extension, considering the MIME types supported by TV 3.0 AoP"): `image/svg+xml` (`.svg`), `image/png` (`.png`), `image/jpeg` (`.jpg`, `.jpeg`) e `image/webp` (`.webp`), sem diferença de caixa na extensão; outra extensão, `application/octet-stream` (`getMime`, em `tv3ws/src/api/user/service.ts`). A resposta leva também `Content-Length` e `Content-Disposition: attachment`.
- **Quem chama:** o users-test do bcast (`bcast/src/modules/users-test/app.ejs`) pede o avatar de cada perfil por esta API, na borda (44642), com `fetch`, para que o pedido leve o `Origin` da app e a borda a reconheça como associada; o conteúdo vira um `<img src="blob:...">`, e a falha (305, 405, rede ou `Content-Type` que não é `image/...`) mostra o avatar padrão da página. As telas do próprio AoP não passam por aqui: leem o arquivo do diretório e o embutem como `<img src="data:...">` (`aop/src/modules/profile-manager/avatar.js`).

---

## Proxy puro na borda

Toda rota que a borda repassa ao tv3ws é **proxy puro** (`output_encoding: "no-op"`, `infra/edgegateway/generate.js`). O status, os cabeçalhos e o corpo do tv3ws passam sem reinterpretação, o que inclui as respostas binárias (`GET .../users/files`) e as de texto. A exceção é o 5xx do próprio KrakenD (backend lento ou fora do ar), que o plugin troca por 404 `{"error":200}`. As rotas marcadas "(borda)" na tabela acima não são repassadas: o plugin as responde.
