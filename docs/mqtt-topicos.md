---
title: Tópicos MQTT
parent: Como funciona
nav_order: 4
---

# Tópicos MQTT

O Mosquitto leva a **sinalização e os eventos** entre os serviços. Não é o único canal interno: o AoP, o tv3ws e a borda leem e escrevem no Redis diretamente, a borda repassa as chamadas das APIs ao tv3ws por HTTP, e o AoP faz proxy HTTP direto ao bcast (ver [Arquitetura]({{ site.baseurl }}/arquitetura)). O cliente no navegador, a camada gráfica do AoP (`aop/src/modules/graphic-overlays/view.ejs`, `clientId` `rp-display`), acessa o broker por WebSocket **pelo próprio AoP**: conecta em `ws(s)://<host da página>/mqtt`, na porta do AoP, e o AoP repassa a conexão ao WebSocket do Mosquitto, na 9001 interna da `ginga_net` (`aop/src/mqtt-ws.js`). O repasse só existe no host do AoP; num host de app, o `/mqtt` responde 404, e a app de emissora não alcança o broker pela origem dela. Por padrão, a 9001 do Mosquitto sai numa porta de host escolhida pelo Docker (`docker compose port mosquitto 9001`), e `MQTT_WS_PUBLISH=<porta>:9001` no `.env` da raiz a fixa. Essa porta de host serve para depurar com um cliente MQTT de fora e para o AoP rodando no host, que repassa o `/mqtt` para ela (`MQTT_WS_PORT` no `aop/.env`; ver [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local)).

---

## Clientes MQTT

| Client ID | Processo | Arquivo | Conexão |
|---|---|---|---|
| `aop-core` | AoP (servidor) | `aop/src/core.js` | `mqtt://${MQTT_HOST}` (no compose, `mosquitto:1883`) |
| `rp-display` | página da TV, no navegador | `aop/src/modules/graphic-overlays/view.ejs`, `connect()` | `ws://<host da página>/mqtt`, que o AoP repassa à 9001 do Mosquitto (`aop/src/mqtt-ws.js`) |
| `tv3ws-client` | tv3ws | `tv3ws/src/mqtt-client.ts` | `mqtt://${MQTT_HOST}`, MQTT 5 |
| `bcast_svc` | bcast | `bcast/src/index.ts` | `mqtt://${MQTT_HOST}`, MQTT 5 |
| (sem cliente) | plugin C do broker | `infra/mqtt-broker/plugin/src/` | publica de dentro do broker (`mosquitto_broker_publish`) |

As assinaturas do AoP, da página e do tv3ws usam *no local* (`noLocal`, ou `nl: true` no tv3ws): ninguém recebe a própria publicação. O tv3ws assina com QoS 1, um tratador por tópico exato (`addTopicHandler`, em `tv3ws/src/mqtt-client.ts`).

---

## Tópicos principais

Publicadores, consumidores e flag de retenção conferidos nas chamadas `publish`/`subscribe` do código de aop, tv3ws e bcast.

| Tópico | Publicado por | Consumido por | Retain | Significado |
|--------|--------------|---------------|--------|-------------|
| `aop/currentUser` | AoP; tv3ws (C.6.14.4) | AoP, tv3ws | sim | Id do usuário corrente. Ao receber, o tv3ws grava `session:current-user`, e o AoP grava o `lastAccess` do perfil. Os ids de perfil são UUID; o esquema do tópico no broker é texto de até 64 caracteres. Vazio depois da remoção do perfil corrente, até a escolha no seletor |
| `aop/removedUser` | AoP (`profileRemoved`, em `aop/src/core.js`) | — (nenhum consumidor nestes módulos) | não | Id do perfil que o telespectador removeu no seletor, publicado depois da remoção do perfil, da visibilidade, dos atributos de emissora e do arquivo do avatar. Texto de 1 a 64 caracteres no esquema do broker |
| `aop/currentService` | AoP | tv3ws, AoP | sim | Id do serviço DTV ativo (`urn:tv30:service:...`) |
| `aop/display/layers/rxgui` | AoP | front do AoP | não | Camada GUI ativa |
| `aop/display/layers/video/url` | AoP | front do AoP | não | URL do stream de vídeo |
| `aop/display/layers/video/size` | AoP | front do AoP | não | Posição e tamanho do vídeo |
| `aop/display/layers/graphics` | AoP | front do AoP | não | URL do iframe gráfico: `http://<app>.<APPS_DOMAIN>:<AOP_PUBLIC_PORT>/graphicsAppProxy<bcastEntryPointUrl>`, no host próprio da app (padrão `<app>.apps.localhost:8080`; a porta some quando é 80, como o navegador escreve o `Origin`; `aop/src/app-hosts.js`), por exemplo `http://urn-tv30-app-users-test.apps.localhost:8080/graphicsAppProxy/users-test`; vazio encerra a app |
| `aop/application-lifecycle-manager/application-state` | AoP (`setDisplayGraphics`, em `aop/src/core.js`), no lugar do Application Lifecycle Manager | tv3ws (`src/modules/associated-app/`) | não | Mudança de estado da aplicação de emissora: JSON `{serviceContextId, appId, origin, state}`, `state` em `started` ou `ended`; numa troca, `ended` da que sai antes de `started` da que entra. O tv3ws identifica o cliente associado pela aplicação em execução e, no `ended`, libera os recursos dela (par, pontos de entrada locais, ouvintes de notificação e registros de dispositivo remoto; C.4.4). O broker valida o formato |
| `aop/access-panel/client-blocked` | Access Panel (ainda não implementado); nos testes, o próprio script | tv3ws (`src/modules/client-revocation/`) | não | `clientid` do cliente bloqueado pelo telespectador no histórico de autorizações (C.4.2.2), publicado depois de gravar o bloqueio no Redis. O tv3ws libera os recursos do cliente (C.4.4): registros de dispositivo remoto que ele fez, nas duas versões, e, na 100.0, o par, os pontos de entrada locais e os ouvintes de notificação |
| `aop/display/layers/popup/yesno/message` | tv3ws | front do AoP | não | Pop-up de autorização sim/não (`showYesNoPopUpAsync`, em `tv3ws/src/core.ts`) |
| `aop/display/layers/popup/yesno/response` | front do AoP (`aop/public/js/popup.js`) | tv3ws | não | Resposta do espectador: `true`, ou `false` no "Não" e no tempo esgotado |
| `aop/display/layers/popup/qrcode`, `aop/display/layers/popup/pin` | tv3ws | front do AoP (camada gráfica, pelo filtro `aop/display/layers/popup/+`) | não | QR code e PIN do pareamento do cliente não local (C.4.3): abertura `{value, timeout}` e fechamento `{"close":true}` no mesmo tópico, no fim do pareamento (ver nota abaixo) |
| `aop/display/layers/popup/info` | tv3ws (`notifyUserOfWrite`, em `tv3ws/src/api/user/service.ts`) | front do AoP (camada gráfica, pelo filtro `aop/display/layers/popup/+`) | não | Aviso ao espectador de que a emissora gravou atributos do perfil dele (C.6.14.5, Tabela C.74: "it is necessary to notify the user"), `{"value": "A emissora <serviço> atualizou os dados do perfil <apelido>.", "timeout": 5000}`, publicado depois da gravação, só quando algo mudou. Não pede resposta (ver nota abaixo) |
| `aop/:serviceId/currentApp` | — (nenhum publicador nestes módulos; o contrato prevê o Application Lifecycle Manager ou, enquanto ele não existir, o AoP) | tv3ws | — | Contrato: o `appId` da app corrente do serviço `{serviceId}` (o `globalServiceId`), **retido**. A mensagem vazia retida é o fim da app (DESTROY, KILL, troca de serviço, saída para o catálogo) e apaga o retido; na troca de serviço, o publicador apaga o retido do serviço que deixa. O broker valida o formato (string, até 256 caracteres; `infra/mqtt-broker/plugin/config/schemas.json`). No tv3ws, a troca de app zera o diretório da app até chegar o `.../path` da nova (a C.6.4.7 responde 305 nesse meio-tempo), e a mensagem vazia encerra a app corrente (`setAppId`, em `tv3ws/src/core.ts`) |
| `aop/services` | AoP (unidade `aop-transport-layer-metadata-lls`, `aop/src/modules/transport-layer-metadata-lls/`) | tv3ws (guarda a lista; nenhuma resposta a usa) | sim | Os serviços anunciados na LLS, um por BAM, sem repetição: array de `{"serviceContextId": "<globalServiceId>"}`; `[]` = nenhum. O mesmo conteúdo de `services:announced`, publicado depois de gravado no Redis, a cada BAMT recebida ou retirada e na partida. Sem `serviceName` nem `serviceId`, que o BAM não traz |
| `aop/devices/<classe>` | tv3ws (`tv3ws/src/modules/remotedevice-manager/manager.ts`) | — (nenhum consumidor nestes módulos) | sim | Dispositivos remotos registrados: lista JSON dos *handles* da classe, regravada a cada registro e remoção; vazio quando a classe fica sem dispositivo |
| `aop/<sid>/<appId>/path`, `aop/<sid>/<appId>/doc/nodes` | — (nenhum publicador nestes módulos; o `path`, do mesmo publicador de `currentApp`, retido) | tv3ws (`tv3ws/src/mqtt-client.ts`, `core.ts`) | — | Diretório da aplicação (a C.6.4.7 lê dele) e nós do documento, para o remote-device |
| `aop/<sid>/<appId>/doc/<nó>/...` | tv3ws (eventos do remote-device: `.../eventNotification` sem retain; `.../user` e `.../value` com retain) | tv3ws (`/interfaces`, `.../actionNotification`, `.../attributionEvent/value`) | misto | Troca de estado dos nós entre a aplicação e os dispositivos remotos (`tv3ws/src/modules/remotedevice-manager/remote-device.ts`). O `publish` do tv3ws retém por padrão (`tv3ws/src/mqtt-client.ts`) |
| `errors/<client_id>` | plugin do broker | — (nenhum consumidor nestes módulos) | não | Erro de validação de esquema de uma publicação daquele cliente, em JSON ([Broker MQTT]({{ site.baseurl }}/broker-mqtt)). No `<client_id>` do tópico, `+`, `#`, `/` e controles viram `_` |
| `PublisherResponseTime<id>/iteration<n>` | medidor de `infra/mqtt-broker/brokertimetest/` (`server.js`, `headless-run.js`) | plugin do broker, que o deixa passar | não | Pedido do teste de latência ([Broker MQTT]({{ site.baseurl }}/broker-mqtt#teste-de-latência)) |
| `PluginResponseTime<id>/iteration<n>` | plugin do broker (`response_time_tester.c`) | o medidor (`PluginResponseTime<id>/#`) | não | Resposta do teste de latência, `{localtime, id, iteration, diffTime}`; não sai se passar de 511 bytes |
| `video/event` | bcast (`src/modules/live_stream/index.ts`) | front do AoP (camada gráfica) | não | Eventos do fluxo simulado. O front os repassa à app da camada gráfica como `stream_event`; com a app em outra origem, por `postMessage`, e a ponte `bcast/public/js/aop-bridge.js` os redespacha no documento dela |
| `tlm/lls/<bsid>/bamt` | bcast | AoP (`aop-transport-layer-metadata-lls`) | sim | BAMT: os serviços anunciados, um BAM por serviço; mensagem vazia retira o fluxo `<bsid>`. As outras tabelas de `tlm/lls/#` não mudam a lista |
| `tlm/sls/<sid>/esg`, `tlm/sls/<sid>/bald` | bcast | AoP (assina o serviço selecionado) | sim | ESG e BALD por serviço; a BALD traz o `bcastEntryPackageUrl` |

**O QR code e o PIN ficam na tela até o fim do pareamento** (C.4.3.2 e C.4.3.3):
- o tv3ws abre o pop-up com prazo de 120 s, que o fecha se o cliente desistir (`PAIRING_POPUP_TIMEOUT_MS`, em `tv3ws/src/api/client-identification/service.ts`);
- no fim do pareamento, o `GET /tv3/token` com o desafio resolvido, o tv3ws publica `{"close":true}` no mesmo tópico (`closeQRCodePopUp`/`closePINPopUp`, em `tv3ws/src/core.ts`), e a página fecha o pop-up aberto daquele tipo (`handlePopupMessage`, em `aop/public/js/popup.js`). O `/tv3/token` que falha não fecha;
- a camada gráfica tem um pop-up só: o novo substitui o da tela, menos o aviso da C.6.14.5 (abaixo), que espera. O fim do pareamento de um cliente não fecha o pop-up de outro (o tv3ws guarda de quem é cada pop-up). O tv3ws não manda um sim/não com outro sim/não, QR code ou PIN na tela: o pedido de autorização recebe 103, e o QR code ou o PIN de um pareamento em andamento não sai da tela por causa de outro cliente;
- mensagem inválida num tópico de pop-up vai para o console e não para a página;
- o texto do sim/não (com o `display-name` do cliente) e o PIN entram escapados no HTML.

O `scripts/test-auth.sh` lê a abertura do pop-up direto do broker (primeira mensagem do tópico) e não depende do prazo.

**O aviso da C.6.14.5** (`aop/display/layers/popup/info`). O tv3ws o publica, sem retenção, logo depois de gravar atributos de emissora com alguma mudança ([APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws)). Na página da TV (`aop/public/js/popup.js`, tipo `info`):
- o texto entra escapado no HTML, como o do sim/não (ele traz o apelido do perfil e o nome do serviço), sem botões, e as teclas seguem para a página;
- o aviso fecha sozinho no `timeout` da mensagem; prazo ausente, zero, negativo ou que não é número vale 5 s, e o `{"close":true}` não o fecha;
- ele nunca tira da tela outro pop-up: com um sim/não, QR code, PIN ou outro aviso aberto, espera numa fila e aparece quando a camada fica livre. Com 3 avisos já esperando, o novo é descartado, com registro no console. Um aviso na tela que um sim/não, QR code ou PIN substitui volta para o começo da fila e aparece inteiro depois;
- a fila é só do aviso: os outros pop-ups não chegam juntos, porque o tv3ws responde 103 ao pedido de autorização com a camada ocupada.

**Fora da tabela, só nos testes:** o exemplo do template de componente (`templates/componente/index.js`) assina `tv30/<nome>/exemplo/ping` e responde em `tv30/<nome>/exemplo/pong`, sem retain, com o valor que lê da chave `tv30:<nome>:exemplo` no Redis. Quem publica o ping é o `scripts/test-template.sh` e o cenário 5 do `scripts/test-dev-host.sh`. Nenhum desses tópicos tem esquema no broker.

---

## Validação de esquema no broker

O plugin C do Mosquitto valida o payload das publicações nos tópicos com esquema declarado e recusa as que não o cumprem: [Broker MQTT]({{ site.baseurl }}/broker-mqtt).

---

## Padrão de retain

| Tipo de mensagem | Retain |
|------------------|--------|
| Estado atual (`currentUser`, `currentService`, `services`) | **sim**, para quem reconecta saber o estado |
| Eventos pontuais (pop-ups, `removedUser`) | **não**, só para quem está escutando |
| Eventos dos nós no remote-device (`.../user`, `.../value`) | **sim**, porque o `publish` do tv3ws retém por padrão (`tv3ws/src/mqtt-client.ts`); o `.../eventNotification` sai sem retain |
| Camadas de display | **não** no código atual: o front que reabre não recebe a última camada |
| Sinalização do bcast (`tlm/*`) | **sim**, a última versão dos metadados. O bcast publica vazio ao encerrar, para limpar |
