---
title: Tópicos MQTT
parent: Como funciona
nav_order: 4
---

# Tópicos MQTT

O Mosquitto leva a **sinalização e os eventos** entre os serviços. Não é o único canal interno: o AoP, o tv3ws e a borda leem e escrevem no Redis diretamente, a borda repassa as chamadas das APIs ao tv3ws por HTTP, e o AoP faz proxy HTTP direto ao bcast (ver [Arquitetura]({{ site.baseurl }}/arquitetura)). O cliente no navegador, a camada gráfica do AoP (`aop/src/modules/graphic-overlays/view.ejs`, `clientId` `rp-display`), acessa o broker por WebSocket **pelo próprio AoP**: conecta em `ws(s)://<host da página>/mqtt`, na porta do AoP, e o AoP repassa a conexão ao WebSocket do Mosquitto, na 9001 interna da `ginga_net` (`aop/src/mqtt-ws.js`; C1, decisão do Luís em 11/10). O repasse só existe no host do AoP; num host de app, o `/mqtt` responde 404, e a app de emissora não alcança o broker pela origem dela. Até 11/10, a página conectava direto na porta `MQTT_WS_PORT` do host (padrão 9001; no Windows, 9003), que deixou de ser fixa: por padrão, a 9001 do Mosquitto sai numa porta de host escolhida pelo Docker (`docker compose port mosquitto 9001`), e `MQTT_WS_PUBLISH=<porta>:9001` no `.env` da raiz a fixa. Essa porta de host serve para depurar com um cliente MQTT de fora e para o AoP rodando no host, que repassa o `/mqtt` para ela (`MQTT_WS_PORT` no `aop/.env`; ver [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local)).

---

## Tópicos principais

Publicadores, consumidores e flag de retenção conferidos nas chamadas `publish`/`subscribe` do código de aop, tv3ws e bcast.

| Tópico | Publicado por | Consumido por | Retain | Significado |
|--------|--------------|---------------|--------|-------------|
| `aop/currentUser` | AoP; tv3ws (C.6.14.4) | AoP, tv3ws | sim | Id do usuário corrente. Ao receber, o tv3ws grava `session:current-user`, e o AoP grava o `lastAccess` do perfil (D-0510-5). Desde 11/10 (F-3), os ids de perfil são UUID; o esquema do tópico no broker continua texto de até 64 caracteres. De 11/10 a 12/10, o plugin do broker recusava o UUID que começa com dígito (lia o começo como número; ver *Plugin C do Mosquitto*), e a troca de usuário corrente para um perfil desses não chegava aos assinantes; corrigido em 12/10 |
| `aop/currentService` | AoP | tv3ws, AoP | sim | Id do serviço DTV ativo (`urn:tv30:service:...`) |
| `aop/display/layers/rxgui` | AoP | front do AoP | não | Camada GUI ativa |
| `aop/display/layers/video/url` | AoP | front do AoP | não | URL do stream de vídeo |
| `aop/display/layers/video/size` | AoP | front do AoP | não | Posição e tamanho do vídeo |
| `aop/display/layers/graphics` | AoP | front do AoP | não | URL do iframe gráfico. Desde 11/10 (decisão do Luís), `http://<app>.<APPS_DOMAIN>:<AOP_PUBLIC_PORT>/graphicsAppProxy<bcastEntryPointUrl>`, no host próprio da app (P1.3; padrão `<app>.apps.localhost:8080`; a porta some quando é 80, como o navegador escreve o `Origin`; `aop/src/app-hosts.js`), por exemplo `http://urn-tv30-app-users-test.apps.localhost:8080/graphicsAppProxy/users-test`; vazio encerra a app. De 10/10 até 11/10, o mesmo host sem o prefixo, `http://<app>.<APPS_DOMAIN>:<AOP_PUBLIC_PORT><bcastEntryPointUrl>`. Até 10/10, `/graphicsAppProxy<bcastEntryPointUrl>`, na origem do AoP |
| `aop/display/layers/popup/yesno/message` | tv3ws | front do AoP | não | Pop-up de autorização sim/não (`showYesNoPopUpAsync`, em `tv3ws/src/core.ts`) |
| `aop/display/layers/popup/yesno/response` | front do AoP (`aop/public/js/popup.js`) | tv3ws | não | Resposta do espectador: `true`, ou `false` no "Não" e no tempo esgotado |
| `aop/display/layers/popup/qrcode`, `aop/display/layers/popup/pin` | tv3ws | front do AoP (camada gráfica, pelo filtro `aop/display/layers/popup/+`, desde 11/10; ver nota abaixo) | não | QR code e PIN do pareamento do cliente não local (C.4.3): abertura `{value, timeout}` e, desde 12/10, fechamento `{"close":true}` no mesmo tópico, no fim do pareamento (ver nota abaixo) |
| `aop/display/layers/popup/info` | tv3ws (`notifyUserOfWrite`, em `tv3ws/src/api/user/service.ts`) | front do AoP (camada gráfica, pelo filtro `aop/display/layers/popup/+`) | não | Desde a G9 (decisão do Luís em 12/10, à noite): aviso ao espectador de que a emissora gravou atributos do perfil dele (C.6.14.5, Tabela C.72: "it is necessary to notify the user"), `{"value": "A emissora <serviço> atualizou os dados do perfil <apelido>.", "timeout": 5000}`, publicado depois da gravação, só quando algo mudou. Não pede resposta (ver nota abaixo) |
| `aop/:serviceId/currentApp` | — (nenhum publicador nestes módulos) | tv3ws | — | App ativo no serviço. Desde 12/10, a troca de app zera o diretório da app no tv3ws até chegar o `.../path` da nova (a C.6.4.7 responde 305 nesse meio-tempo), e a mensagem vazia encerra a app corrente (`setAppId`, em `tv3ws/src/core.ts`). Como o fim da app é sinalizado não está escrito em lugar nenhum, porque o tópico não tem publicador aqui: `PENDENTE (Joel)` no código |
| `aop/services` | — (nenhum publicador nestes módulos) | tv3ws | — | Lista de serviços |
| `aop/devices/<classe>` | tv3ws (`tv3ws/src/modules/remotedevice-manager/manager.ts`) | — (nenhum consumidor nestes módulos) | sim | Dispositivos remotos registrados: lista JSON dos *handles* da classe, regravada a cada registro e remoção; vazio quando a classe fica sem dispositivo |
| `aop/<sid>/<appId>/path`, `aop/<sid>/<appId>/doc/nodes` | — (nenhum publicador nestes módulos) | tv3ws (`tv3ws/src/mqtt-client.ts`, `core.ts`) | — | Caminho e nós do documento da aplicação, para o remote-device |
| `aop/<sid>/<appId>/doc/<nó>/...` | tv3ws (eventos do remote-device: `.../eventNotification` sem retain; `.../user` e `.../value` com retain) | tv3ws (`/interfaces`, `.../actionNotification`, `.../attributionEvent/value`) | misto | Troca de estado dos nós entre a aplicação e os dispositivos remotos (`tv3ws/src/modules/remotedevice-manager/remote-device.ts`). O `publish` do tv3ws retém por padrão (`tv3ws/src/mqtt-client.ts`) |
| `errors/<client_id>` | plugin do broker | — (nenhum consumidor nestes módulos) | não | Erro de validação de esquema de uma publicação daquele cliente, em JSON (ver *Plugin C do Mosquitto*). No `<client_id>` do tópico, `+`, `#`, `/` e controles viram `_` (desde 12/10) |
| `video/event` | bcast (`src/modules/live_stream/index.ts`) | front do AoP (camada gráfica) | não | Eventos do fluxo simulado. O front os repassa à app da camada gráfica como `stream_event`; desde o P1.3, com a app em outra origem, por `postMessage`, e a ponte `bcast/public/js/aop-bridge.js` os redespacha no documento dela |
| `tlm/lls/<bsid>/bamt` | bcast | AoP | sim | BAMT: aplicações anunciadas |
| `tlm/sls/<sid>/esg`, `tlm/sls/<sid>/bald` | bcast | AoP (assina o serviço selecionado) | sim | ESG e BALD por serviço; a BALD traz o `bcastEntryPackageUrl` |

**Os pop-ups de QR code e PIN não chegavam à tela** (achado de 10/10, pela leitura do código; **corrigido em 11/10**). O tv3ws os publica em `aop/display/layers/popup/qrcode` e `.../pin` (`tv3ws/src/core.ts`), mas a camada gráfica só assina `aop/display/layers/+`, `aop/display/layers/video/+` e `aop/display/layers/popup/+/message` (`aop/src/modules/graphic-overlays/view.ejs`), e nenhum desses filtros casa com os dois tópicos. O `aop/public/js/popup.js` sabe desenhar o QR code e o PIN, mas não os recebe. O `scripts/test-auth.sh` não pegava o defeito, porque lê o QR code e o PIN direto do broker, no lugar do espectador. Desde 11/10 a camada gráfica também assina `aop/display/layers/popup/+`. Conferido no mesmo dia num Chrome 154 sem interface, controlado por CDP: a camada gráfica do AoP reconstruído conectou ao broker e desenhou o PIN e o QR code publicados nos dois tópicos.

**O QR code e o PIN ficam na tela até o fim do pareamento** (correção de 12/10, à tarde; C.4.3.2 e C.4.3.3). Até ali, o tv3ws os mandava com prazo de 1 s, e a página os fechava sozinha: o espectador mal via o QR code. Desde 12/10:
- o tv3ws abre o pop-up com prazo de 120 s, uma trava de segurança para o caso de o cliente desistir (`PAIRING_POPUP_TIMEOUT_MS`, em `tv3ws/src/api/client-identification/service.ts`; valor escolhido pelo projeto, a norma não fixa prazo);
- no fim do pareamento, o `GET /tv3/token` com o desafio resolvido, o tv3ws publica `{"close":true}` no mesmo tópico (`closeQRCodePopUp`/`closePINPopUp`, em `tv3ws/src/core.ts`), e a página fecha o pop-up aberto daquele tipo (`handlePopupMessage`, em `aop/public/js/popup.js`). O `/tv3/token` que falha não fecha;
- a camada gráfica tem um pop-up só: o novo substitui o da tela, menos o aviso da C.6.14.5 (abaixo), que espera. O fim do pareamento de um cliente não fecha o pop-up de outro (o tv3ws guarda de quem é cada pop-up). Desde a noite de 12/10 (decisão do Luís; G2 de [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes)), o tv3ws não manda um sim/não com outro sim/não, QR code ou PIN na tela: o pedido de autorização recebe 103, e o QR code ou o PIN de um pareamento em andamento não sai mais da tela por causa de outro cliente;
- mensagem inválida num tópico de pop-up vai para o console e não para mais a página. Até 12/10, um JSON inválido no tópico do QR code fazia a página parar de tratar todas as mensagens seguintes (medido no Chrome 154);
- o texto do sim/não (com o `display-name` do cliente) e o PIN entram escapados no HTML. Até 12/10, um `display-name` com HTML rodava script na tela da TV, e o script podia apertar o "Sim" do próprio pop-up: o cliente se autorizava sem o espectador (medido no Chrome 154).

O `scripts/test-auth.sh` lê a abertura do pop-up direto do broker (primeira mensagem do tópico) e não depende do prazo.

**O aviso da C.6.14.5** (`aop/display/layers/popup/info`; G9, decisão do Luís em 12/10, à noite). O tv3ws o publica, sem retenção, logo depois de gravar atributos de emissora com alguma mudança ([APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws)). Na página da TV (`aop/public/js/popup.js`, tipo `info`):
- o texto entra escapado no HTML, como o do sim/não (ele traz o apelido do perfil e o nome do serviço), sem botões, e as teclas seguem para a página;
- o aviso fecha sozinho no `timeout` da mensagem; prazo ausente, zero, negativo ou que não é número vale 5 s, e o `{"close":true}` não o fecha;
- ele nunca tira da tela outro pop-up: com um sim/não, QR code, PIN ou outro aviso aberto, espera numa fila e aparece quando a camada fica livre. Com 3 avisos já esperando, o novo é descartado, com registro no console. Um aviso na tela que um sim/não, QR code ou PIN substitui volta para o começo da fila e aparece inteiro depois;
- a fila é só do aviso: os outros pop-ups não chegam juntos, porque o tv3ws responde 103 ao pedido de autorização com a camada ocupada (G2, decisão do Luís em 12/10, à noite).

**Fora da tabela, só nos testes:** o exemplo do template de componente (`templates/componente/index.js`) assina `tv30/<nome>/exemplo/ping` e responde em `tv30/<nome>/exemplo/pong`, sem retain, com o valor que lê da chave `tv30:<nome>:exemplo` no Redis. Quem publica o ping é o `scripts/test-template.sh` e o cenário 5 do `scripts/test-dev-host.sh`. Nenhum desses tópicos tem esquema no broker.

---

## Tópico `aop/users` (fora de uso desde 05/10, removido em 10/10)

Até a rodada de 05/10, o tv3ws assinava `aop/users` e, a cada mensagem, regravava os perfis a partir do `userData.json` (`syncUsersFromFile`), e o AoP recarregava a lista do Redis. Quem publicaria era o AoP, com o caminho de `user-files` (`notifyUsersChanged`), mas essa função já não tinha chamador no código: a página dizia "publicado por AoP" sem que nada publicasse.

Na reunião de 05/10, o Joel apontou que os perfis tinham três escritores. A correção (D-0510-5) aplicou o P5, "um dono por família de chave": a plataforma (AoP) é a dona dos perfis, e o tv3ws só os lê. Saíram a função de publicação do AoP e a assinatura do tv3ws, que não sincroniza mais nada a partir do arquivo. O `userData.json` ficou só como carga inicial do Redis (ver [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis)).

Sobraram duas referências sem efeito, e as duas saíram em 10/10: a assinatura do AoP, que recarregava a lista quando chegava mensagem (`aop/src/core.js`), e o esquema do tópico no `infra/mqtt-broker/plugin/config/schemas.json`. Desde então, nenhum módulo publica nem assina `aop/users`. O AoP continua carregando a lista de perfis do Redis quando conecta no broker (`loadUserData`, no `connect`).

---

## Plugin C do Mosquitto

O plugin (`infra/mqtt-broker/plugin/src/mosquitto_plugin.c`) **valida o esquema** das mensagens publicadas em tópicos que têm esquema declarado (`infra/mqtt-broker/plugin/config/schemas.json`):
- **Tópicos com esquema:** `aop/currentUser`, `aop/currentService`, `aop/display/layers/rxgui`, `aop/display/layers/graphics`, `aop/display/layers/video/url`, `aop/display/layers/video/size`, `video/event`, `tlm/lls/+/bamt`, `tlm/sls/+/esg` e `tlm/sls/+/bald`, mais três tópicos de teste (`sensor/room1/temperature`, `sensor/room2/humidity` e `sensor/comprehensive/test`). Os demais, inclusive os pop-ups, `aop/devices/*` e os tópicos do remote-device, passam sem validação.
- **Publicação inválida é recusada,** e não só registrada: o plugin devolve `MOSQ_ERR_ACL_DENIED` ao broker e publica o erro em `errors/<client_id>` (QoS 0, sem retain). Payload vazio não é validado, e por isso a limpeza dos retidos de `tlm/*` com mensagem vazia passa.
- **Payload inteiro** (desde 12/10, `infra/mqtt-broker/plugin/src/json_payload.c`): o payload é lido pelo comprimento e só vale como JSON se for exatamente um texto JSON (RFC 8259, json-c no modo estrito); sobra depois do valor (`{"value":1}lixo`), NUL, comentário, aspas simples ou vírgula sobrando dão `INVALID_JSON`. Nos tópicos de esquema `type: string` (`aop/currentUser`, `aop/currentService`, `aop/display/layers/rxgui`, `.../graphics` e `.../video/url`), o payload que não é texto JSON vale **inteiro** como string. Até 12/10, o plugin lia só até o primeiro NUL e ignorava o que vinha depois do primeiro valor: `{"value":1}lixo` passava e era entregue, e o UUID que começa com dígito virava o número do começo e era recusado em `aop/currentUser` (desde a F-3, 11/10).
- **Mensagem de erro sempre JSON válido** (desde 12/10, `infra/mqtt-broker/plugin/src/error_json.c`): `{"timestamp", "topic", "error_type", "details", "client_id", "payload"}`, com escape da RFC 8259, UTF-8 inválido trocado por U+FFFD, até 2047 bytes e `"truncated":true` quando algum campo foi cortado. Até 12/10 os campos entravam sem escape, e um payload com aspas gerava JSON inválido. Formato e limites em `infra/docs/09-schema-validation.md`.
- **Medidor de tempo de resposta:** o plugin também responde às mensagens dos tópicos `PublisherResponseTime*`, publicando em `PluginResponseTime<id>/iteration<n>` (`response_time_tester.c`). Serve à medição de `infra/mqtt-broker/brokertimetest/`.

O plugin não faz controle de acesso a tópicos nem consulta o Redis. O controle de acesso foi removido por decisão de desenho: o isolamento que a norma exige é por contexto de serviço DTV, na fronteira das APIs. A versão anterior desta página dizia que o plugin "verifica consent do usuário no Redis", o que não corresponde ao código.

---

## Padrão de retain

| Tipo de mensagem | Retain |
|------------------|--------|
| Estado atual (`currentUser`, `currentService`) | **sim**, para quem reconecta saber o estado |
| Eventos pontuais (pop-ups) | **não**, só para quem está escutando |
| Eventos dos nós no remote-device (`.../user`, `.../value`) | **sim**, porque o `publish` do tv3ws retém por padrão (`tv3ws/src/mqtt-client.ts`); o `.../eventNotification` sai sem retain |
| Camadas de display | **não** no código atual: o front que reabre não recebe a última camada |
| Sinalização do bcast (`tlm/*`) | **sim**, a última versão dos metadados. O bcast publica vazio ao encerrar, para limpar |
