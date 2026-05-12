---
title: Tópicos MQTT
nav_order: 7
---

# Tópicos MQTT

Todos os serviços usam o Mosquitto como **único canal de comunicação interna**. Browser cliente pode acessar via WebSocket na porta `MQTT_WS_PORT` (default 9001; em Windows costuma ser 9003).

---

## Tópicos principais

| Tópico | Publicado por | Consumido por | Retain | Significado |
|--------|--------------|---------------|--------|-------------|
| `aop/currentUser` | CCWS | AoP | sim | UUID do usuário logado |
| `aop/currentService` | CCWS | AoP | sim | ID do serviço DTV ativo (`urn:tv30:service:...`) |
| `aop/users` | CCWS / AoP | CCWS, AoP | não | Trigger de re-sync `userData.json` → Redis |
| `aop/display/layers/rxgui` | AoP | AoP front | sim | Camada GUI ativa |
| `aop/display/layers/video/url` | AoP | AoP front | sim | URL do stream de vídeo |
| `aop/display/layers/video/size` | AoP | AoP front | sim | Posição/tamanho do video |
| `aop/display/layers/graphics` | AoP | AoP front | sim | URL do iframe gráfico |
| `aop/:serviceId/currentApp` | AoP | AoP front | sim | App ativo no serviço |
| `aop/devices` | CCWS | AoP | sim | Dispositivos remotos conectados |
| `tlm/lls/#` | bcast | AoP, CCWS | depende | Linear Live Service metadata |
| `tlm/sls/+/#` | bcast | AoP, CCWS | depende | Service Layer Signaling por serviço |

---

## Tópico `aop/users` (re-sync)

Disparado quando algo modifica `userData.json`:

1. AoP publica `aop/users /user-files` ao boot ou após editar JSON
2. CCWS escuta, faz `syncUsersFromFile(/user-files/userData.json)`
3. CCWS regrava `users:index` e `user:{id}` no Redis (sem apagar consent)
4. AoP também escuta, recarrega `DATA.users` via `GET /tv3/current-service/users`

**Importante:** o consent é **incremental**. `syncUsersFromFile` usa `SADD`, não `DEL` + `SADD`. Consents concedidos fora do JSON sobrevivem.

---

## Plugin C de ACL (Mosquitto)

`infra/mosquitto_plugin` carrega um plugin escrito em C que:

- Valida tópicos contra schema JSON
- Verifica consent do usuário no Redis antes de permitir publish/subscribe

Atualmente a função `authorize_access` está **comentada** (todos clientes liberados — workaround temporário enquanto a stack de consent madura). Reativar quando os clients estiverem todos publicando com identidade própria.



## Padrão de retain

| Tipo de mensagem | Retain |
|------------------|--------|
| Estado atual (currentUser, currentService) | **sim** — para receptor reconectar e saber o estado |
| Eventos pontuais (aop/users, trigger de reload) | **não** — só observers ativos |
| Display layers | **sim** — para o frontend reabrir e re-renderizar |
| Telemetria (`tlm/*`) | **sim** — última versão dos metadados |
