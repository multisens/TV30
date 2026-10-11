---
title: Tópicos MQTT
parent: Como funciona
nav_order: 4
---

# Tópicos MQTT

O Mosquitto leva a **sinalização e os eventos** entre os serviços. Não é o único canal interno: o AoP, o tv3ws e a borda leem e escrevem no Redis diretamente, e o AoP faz proxy HTTP direto ao bcast (ver [Arquitetura]({{ site.baseurl }}/arquitetura)). O cliente no navegador, a camada gráfica do AoP (`aop/src/modules/graphic-overlays/view.ejs`, `clientId` `rp-display`), acessa o broker por WebSocket **pelo próprio AoP**: conecta em `ws(s)://<host da página>/mqtt`, na porta do AoP, e o AoP repassa a conexão ao WebSocket do Mosquitto, na 9001 interna da `ginga_net` (`aop/src/mqtt-ws.js`; C1, decisão do Luís em 11/10). O repasse só existe no host do AoP; num host de app, o `/mqtt` responde 404, e a app de emissora não alcança o broker pela origem dela. Até 11/10, a página conectava direto na porta `MQTT_WS_PORT` do host (padrão 9001; no Windows, 9003), que deixou de ser fixa: a 9001 do Mosquitto sai numa porta de host escolhida pelo Docker (`docker compose port mosquitto 9001`), útil só para depurar com um cliente MQTT de fora.

---

## Tópicos principais

Publicadores, consumidores e flag de retenção conferidos nas chamadas `publish`/`subscribe` do código de aop, tv3ws e bcast.

| Tópico | Publicado por | Consumido por | Retain | Significado |
|--------|--------------|---------------|--------|-------------|
| `aop/currentUser` | AoP; tv3ws (C.6.14.4) | AoP, tv3ws | sim | Id do usuário corrente. Ao receber, o tv3ws grava `session:current-user`, e o AoP grava o `lastAccess` do perfil (D-0510-5). Desde 11/10 (F-3), os ids de perfil são UUID; o esquema do tópico no broker continua texto de até 64 caracteres |
| `aop/currentService` | AoP | tv3ws, AoP | sim | Id do serviço DTV ativo (`urn:tv30:service:...`) |
| `aop/display/layers/rxgui` | AoP | front do AoP | não | Camada GUI ativa |
| `aop/display/layers/video/url` | AoP | front do AoP | não | URL do stream de vídeo |
| `aop/display/layers/video/size` | AoP | front do AoP | não | Posição e tamanho do vídeo |
| `aop/display/layers/graphics` | AoP | front do AoP | não | URL do iframe gráfico. Desde 11/10 (decisão do Luís), `http://<app>.<APPS_DOMAIN>:<AOP_PUBLIC_PORT>/graphicsAppProxy<bcastEntryPointUrl>`, no host próprio da app (P1.3; padrão `<app>.apps.localhost:8080`; a porta some quando é 80, como o navegador escreve o `Origin`; `aop/src/app-hosts.js`), por exemplo `http://urn-tv30-app-users-test.apps.localhost:8080/graphicsAppProxy/users-test`; vazio encerra a app. De 10/10 até 11/10, o mesmo host sem o prefixo, `http://<app>.<APPS_DOMAIN>:<AOP_PUBLIC_PORT><bcastEntryPointUrl>`. Até 10/10, `/graphicsAppProxy<bcastEntryPointUrl>`, na origem do AoP |
| `aop/display/layers/popup/yesno/message` | tv3ws | front do AoP | não | Pop-up de autorização sim/não (`showYesNoPopUpAsync`, em `tv3ws/src/core.ts`) |
| `aop/display/layers/popup/yesno/response` | front do AoP (`aop/public/js/popup.js`) | tv3ws | não | Resposta do espectador: `true`, ou `false` no "Não" e no tempo esgotado |
| `aop/display/layers/popup/qrcode`, `aop/display/layers/popup/pin` | tv3ws | AoP, camada gráfica (`aop/display/layers/popup/+`, desde 11/10; ver nota abaixo) | não | QR code e PIN do pareamento do cliente não local (C.4.3) |
| `aop/:serviceId/currentApp` | — (nenhum publicador nestes módulos) | tv3ws | — | App ativo no serviço |
| `aop/services` | — (nenhum publicador nestes módulos) | tv3ws | — | Lista de serviços |
| `aop/devices/<classe>` | tv3ws | — | sim | Dispositivos remotos registrados |
| `aop/<sid>/<appId>/path`, `aop/<sid>/<appId>/doc/nodes` | — (nenhum publicador nestes módulos) | tv3ws (`tv3ws/src/mqtt-client.ts`, `core.ts`) | — | Caminho e nós do documento da aplicação, para o remote-device |
| `aop/<sid>/<appId>/doc/<nó>/...` | tv3ws (eventos do remote-device: `.../eventNotification` sem retain; `.../user` e `.../value` com retain) | tv3ws (`/interfaces`, `.../actionNotification`, `.../attributionEvent/value`) | misto | Troca de estado dos nós entre a aplicação e os dispositivos remotos (`tv3ws/src/modules/remotedevice-manager/remote-device.ts`). O `publish` do tv3ws retém por padrão (`tv3ws/src/mqtt-client.ts`) |
| `errors/<client_id>` | plugin do broker | — (nenhum consumidor nestes módulos) | não | Erro de validação de esquema de uma publicação daquele cliente (ver *Plugin C do Mosquitto*) |
| `video/event` | bcast (`src/modules/live_stream/index.ts`) | front do AoP (camada gráfica) | não | Eventos do fluxo simulado. O front os repassa à app da camada gráfica como `stream_event`; desde o P1.3, com a app em outra origem, por `postMessage`, e a ponte `bcast/public/js/aop-bridge.js` os redespacha no documento dela |
| `tlm/lls/<bsid>/bamt` | bcast | AoP | sim | BAMT: aplicações anunciadas |
| `tlm/sls/<sid>/esg`, `tlm/sls/<sid>/bald` | bcast | AoP (assina o serviço selecionado) | sim | ESG e BALD por serviço; a BALD traz o `bcastEntryPackageUrl` |

**Os pop-ups de QR code e PIN não chegavam à tela** (achado de 10/10, pela leitura do código; **corrigido em 11/10**). O tv3ws os publica em `aop/display/layers/popup/qrcode` e `.../pin` (`tv3ws/src/core.ts`), mas a camada gráfica só assina `aop/display/layers/+`, `aop/display/layers/video/+` e `aop/display/layers/popup/+/message` (`aop/src/modules/graphic-overlays/view.ejs`), e nenhum desses filtros casa com os dois tópicos. O `aop/public/js/popup.js` sabe desenhar o QR code e o PIN, mas não os recebe. O `scripts/test-auth.sh` não pegava o defeito, porque lê o QR code e o PIN direto do broker, no lugar do espectador. Desde 11/10 a camada gráfica também assina `aop/display/layers/popup/+`. Conferido no mesmo dia num Chrome 154 sem interface, controlado por CDP: a camada gráfica do AoP reconstruído conectou ao broker e desenhou o PIN e o QR code publicados nos dois tópicos.

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
