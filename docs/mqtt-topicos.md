---
title: Tópicos MQTT
nav_order: 7
---

# Tópicos MQTT

O Mosquitto leva a **sinalização e os eventos** entre os serviços. Não é o único canal interno: o AoP, o tv3ws e a borda leem e escrevem no Redis diretamente, e o AoP faz proxy HTTP direto ao bcast (ver [Arquitetura]({{ site.baseurl }}/arquitetura)). O cliente no navegador acessa o broker via WebSocket na porta `MQTT_WS_PORT` (padrão 9001; no Windows costuma ser 9003).

---

## Tópicos principais

Publicadores, consumidores e flag de retenção conferidos nas chamadas `publish`/`subscribe` do código de aop, tv3ws e bcast.

| Tópico | Publicado por | Consumido por | Retain | Significado |
|--------|--------------|---------------|--------|-------------|
| `aop/currentUser` | AoP; tv3ws (C.6.14.4) | AoP, tv3ws | sim | Id do usuário corrente. Ao receber, o tv3ws grava `session:current-user`, e o AoP grava o `lastAccess` do perfil (D-0510-5) |
| `aop/currentService` | AoP | tv3ws, AoP | sim | Id do serviço DTV ativo (`urn:tv30:service:...`) |
| `aop/users` | — (nenhum publicador no código) | AoP, assinatura que sobrou | não | Era o gatilho de re-sync `userData.json` → Redis no tv3ws, que saiu em 05/10; ver abaixo |
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

## Tópico `aop/users` (fora de uso desde 05/10)

Até a rodada de 05/10, o tv3ws assinava `aop/users` e, a cada mensagem, regravava os perfis a partir do `userData.json` (`syncUsersFromFile`), e o AoP recarregava a lista do Redis. Quem publicaria era o AoP, com o caminho de `user-files` (`notifyUsersChanged`), mas essa função já não tinha chamador no código: a página dizia "publicado por AoP" sem que nada publicasse.

Na reunião de 05/10, o Joel apontou que os perfis tinham três escritores. A correção (D-0510-5) aplicou o P5, "um dono por família de chave": a plataforma (AoP) é a dona dos perfis, e o tv3ws só os lê. Saíram a função de publicação do AoP e a assinatura do tv3ws, que não sincroniza mais nada a partir do arquivo. O `userData.json` ficou só como carga inicial do Redis (ver [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis)).

Sobraram duas referências sem efeito: o AoP ainda assina o tópico e recarrega a lista quando chega mensagem (`aop/src/core.js`), e o `infra/mqtt-broker/plugin/config/schemas.json` ainda declara o esquema dele.

---

## Plugin C do Mosquitto

O plugin (`infra/mqtt-broker/plugin/src/mosquitto_plugin.c`) **só valida o esquema** das mensagens publicadas em tópicos que têm esquema declarado (`infra/mqtt-broker/plugin/config/schemas.json`). Quando a validação falha, ele publica o erro em `errors/<client_id>`.

O plugin não faz controle de acesso a tópicos nem consulta o Redis. O controle de acesso foi removido por decisão de desenho: o isolamento que a norma exige é por contexto de serviço DTV, na fronteira das APIs. A versão anterior desta página dizia que o plugin "verifica consent do usuário no Redis", o que não corresponde ao código.

---

## Padrão de retain

| Tipo de mensagem | Retain |
|------------------|--------|
| Estado atual (`currentUser`, `currentService`) | **sim**, para quem reconecta saber o estado |
| Eventos pontuais (pop-ups) | **não**, só para quem está escutando |
| Camadas de display | **não** no código atual: o front que reabre não recebe a última camada |
| Sinalização do bcast (`tlm/*`) | **sim**, a última versão dos metadados. O bcast publica vazio ao encerrar, para limpar |
