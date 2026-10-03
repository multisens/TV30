---
title: Tópicos MQTT
nav_order: 7
---

# Tópicos MQTT

O Mosquitto leva a **sinalização e os eventos** entre os serviços. Não é o único canal interno: o AoP e o tv3ws leem e escrevem no Redis diretamente, e o AoP faz proxy HTTP direto ao bcast (ver [Arquitetura]({{ site.baseurl }}/arquitetura)). O cliente no navegador acessa o broker via WebSocket na porta `MQTT_WS_PORT` (padrão 9001; no Windows costuma ser 9003).

---

## Tópicos principais

Publicadores, consumidores e flag de retenção conferidos nas chamadas `publish`/`subscribe` do código de aop, tv3ws e bcast.

| Tópico | Publicado por | Consumido por | Retain | Significado |
|--------|--------------|---------------|--------|-------------|
| `aop/currentUser` | AoP; tv3ws (C.6.14.4) | AoP, tv3ws | sim | Id do usuário corrente |
| `aop/currentService` | AoP | tv3ws, AoP | sim | Id do serviço DTV ativo (`urn:tv30:service:...`) |
| `aop/users` | AoP | tv3ws, AoP | não | Gatilho de re-sync `userData.json` → Redis |
| `aop/display/layers/rxgui` | AoP | front do AoP | não | Camada GUI ativa |
| `aop/display/layers/video/url` | AoP | front do AoP | não | URL do stream de vídeo |
| `aop/display/layers/video/size` | AoP | front do AoP | não | Posição e tamanho do vídeo |
| `aop/display/layers/graphics` | AoP | front do AoP | não | URL do iframe gráfico (`/graphicsAppProxy/...`) |
| `aop/display/layers/popup/*` | tv3ws | front do AoP | não | Pop-ups de autorização (sim/não, QR code, PIN) |
| `aop/:serviceId/currentApp` | — (nenhum publicador nestes módulos) | tv3ws | — | App ativo no serviço |
| `aop/services` | — (nenhum publicador nestes módulos) | tv3ws | — | Lista de serviços |
| `aop/devices/<classe>` | tv3ws | — | sim | Dispositivos remotos registrados |
| `tlm/lls/<bsid>/bamt` | bcast | AoP | sim | BAMT: aplicações anunciadas |
| `tlm/sls/<sid>/esg`, `tlm/sls/<sid>/bald` | bcast | AoP (assina o serviço selecionado) | sim | ESG e BALD por serviço; a BALD traz o `bcastEntryPackageUrl` |

---

## Tópico `aop/users` (re-sync)

O AoP publica `aop/users` com o caminho de `user-files` quando algo muda o `userData.json`.

1. O tv3ws recebe a mensagem e roda `syncUsersFromFile` no arquivo.
2. O tv3ws regrava `users:index` e `user:{id}` no Redis sem apagar o *consent* (`SADD`, não `DEL`).
3. O AoP recebe a mesma mensagem e recarrega a lista de usuários **direto do Redis** (`loadUserData`, `aop/src/core.js`). Ele não chama mais a API HTTP do tv3ws.

**Importante:** o *consent* é **incremental**. `syncUsersFromFile` usa `SADD`, não `DEL` + `SADD`, então o que foi concedido fora do JSON sobrevive à re-sincronização. Esse *consent* é a visibilidade do perfil por serviço, não o consentimento da seção 8.8 da norma.

---

## Plugin C do Mosquitto

O plugin (`infra/mqtt-broker/plugin/src/mosquitto_plugin.c`) **só valida o esquema** das mensagens publicadas em tópicos que têm esquema declarado (`infra/mqtt-broker/plugin/config/schemas.json`). Quando a validação falha, ele publica o erro em `errors/<client_id>`.

O plugin não faz controle de acesso a tópicos nem consulta o Redis. O controle de acesso foi removido por decisão de desenho: o isolamento que a norma exige é por contexto de serviço DTV, na fronteira das APIs. A versão anterior desta página dizia que o plugin "verifica consent do usuário no Redis", o que não corresponde ao código.

---

## Padrão de retain

| Tipo de mensagem | Retain |
|------------------|--------|
| Estado atual (`currentUser`, `currentService`) | **sim**, para quem reconecta saber o estado |
| Eventos pontuais (`aop/users`, pop-ups) | **não**, só para quem está escutando |
| Camadas de display | **não** no código atual: o front que reabre não recebe a última camada |
| Sinalização do bcast (`tlm/*`) | **sim**, a última versão dos metadados. O bcast publica vazio ao encerrar, para limpar |
