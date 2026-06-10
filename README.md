# TV 3.0 AoP Experimentation

![Node Version](https://img.shields.io/badge/Node.js-23.11.0-blueviolet?logo=nodedotjs)  ![MQTT](https://img.shields.io/badge/MQTT-blueviolet?logo=mqtt)  ![Docker](https://img.shields.io/badge/Docker-blue?logo=docker)

Testbed do padrão brasileiro de TV digital interativa **TV 3.0** (ABNT NBR 25608). Implementa, em microsserviços, os papéis da plataforma TV 3.0 — receptor (AoP), webservices Ginga CC (CCWS) e broadcaster simulado (bcast) — sobre uma infraestrutura de apoio escolhida por este projeto: gateways KrakenD, broker MQTT (Mosquitto com plugin C de ACL/consentimento) e estado em Redis.

> **Norma × implementação:** a ABNT NBR 25608 especifica os Ginga CC WebServices (CCWS), o modelo de consentimento e os perfis de usuário. O transporte interno via **MQTT**, os **gateways KrakenD** e o **Redis** são decisões de arquitetura deste testbed — **não fazem parte da norma**.

É um **monorepo com submodules Git** orquestrado por um único `docker-compose.yml` na raiz. Toda a stack sobe de uma vez só, em qualquer host com Docker, sem build local — as imagens vêm do Docker Hub e são atualizadas automaticamente pelos workflows de cada submodule.

---

## Pré-requisitos

- **Docker Engine** + **Compose v2** (`docker compose`, não `docker-compose`).
- **Git** com suporte a submodules.
- **Windows:** WSL2 com `~/.wslconfig` em modo NAT (ver abaixo). Modo `mirrored` quebra a publicação de portas do Docker.
- **Linux:** funciona nativo, sem ajustes extras.

### `~/.wslconfig` recomendado (apenas Windows)

Crie ou edite `C:\Users\<voce>\.wslconfig`:

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
vmIdleTimeout=86400000
```

Depois aplique:

```powershell
wsl --shutdown
```

E reabra a distro. **Não use `networkingMode=mirrored`** — Docker faz NAT via iptables e o modo mirrored não espelha bem pro host Windows, dando timeout em `localhost:PORT`. O `vmIdleTimeout=86400000` (24h) evita que a VM seja desligada por idle, o que derrubaria os containers.

---

## Quick start

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
cd TV30
cp .env.example .env
# Windows: ver nota abaixo sobre MQTT_WS_PORT antes de subir
docker compose up -d
```

Abra http://localhost:8080 — interface do receptor (AoP).

> **Importante — não rode `docker compose` em `infra/`.** O `infra/` é submodule e seu compose é incluído automaticamente via `include:` no `docker-compose.yml` da raiz. **Toda a stack sobe de uma vez pela raiz.** Subir `compose` dentro de `infra/` não vê os serviços `aop`, `ccws` e `bcast` (que ficam no compose raiz) e gera confusão de rede.

> **Importante — sem `.env` na raiz, os serviços principais ficam fora silenciosamente.** Os containers `aop`, `ccws`, `bcast`, `mosquitto` e `sysctl-init` têm `profiles: [linux]` ou `[mqtt]` no compose. Sem `COMPOSE_PROFILES=mqtt,linux` (que vem no `.env.example`), só sobe a infra (redis, krakend, middlewares) e nada funciona end-to-end. Sempre comece com `cp .env.example .env`.

> **Importante — Windows + Hyper-V:** o serviço Hyper-V costuma ocupar as portas 9001/9002 no host. Como o Mosquitto WebSocket precisa expor a porta no host (o browser do AoP conecta direto no `localhost:MQTT_WS_PORT`), edite o `.env` **antes do `up -d`** e troque para `MQTT_WS_PORT=9003`. Sintoma quando esquece: o console do navegador mostra erro de conexão WebSocket no MQTT.

---

## Variáveis do `.env` (raiz)

| Variável | Default | Descrição |
|----------|---------|-----------|
| `COMPOSE_PROFILES` | `mqtt,linux` | Profiles ativos. Sem isto, `aop`/`ccws`/`bcast`/`mosquitto`/`sysctl-init` não sobem. |
| `DOCKERHUB_NS` | `luiscrjr` | Namespace do Docker Hub de onde puxar as imagens. Trocar para fork próprio se for buildar localmente. |
| `IMAGE_TAG` | `latest` | Tag das imagens. `latest` puxa o build mais recente da main de cada submodule. |
| `MQTT_WS_PORT` | `9001` | Porta WebSocket do Mosquitto exposta no host. **Em Windows com Hyper-V, trocar para `9003`.** |
| `BCAST_PORT` | `8081` | Porta do bcast exposta no host. Sobrescrever se 8081 estiver ocupada. |

Cada submodule também tem seu próprio `.env` (ex.: `ccws/.env`) — em deploy via container os valores são sobrescritos pelas `environment:` do compose raiz, mas alguns segredos (`JWT_SECRET`, `HTTPS_CERT`, `HTTPS_KEY` do CCWS) **vêm via `env_file: ./ccws/.env`** e precisam estar populados ali. Ver próxima seção.

---

## Gerando `HTTPS_CERT` e `HTTPS_KEY` para o CCWS

O CCWS sobe HTTPS na porta 44653 e precisa de cert + chave em **base64** nas variáveis `HTTPS_CERT` e `HTTPS_KEY` do arquivo `ccws/.env`. Para desenvolvimento, gere um cert self-signed:

### 1. Gerar cert e chave

```bash
openssl req -x509 -newkey rsa:2048 -days 365 -nodes \
  -subj "/CN=localhost/O=TV30Dev/C=BR" \
  -keyout key.pem -out cert.pem
```

### 2. Converter para base64 (sem quebras de linha)

**Linux / WSL:**
```bash
base64 -w0 cert.pem
base64 -w0 key.pem
```

**macOS** (o `base64` do BSD já vem sem quebras):
```bash
base64 -i cert.pem
base64 -i key.pem
```

**Windows PowerShell:**
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('cert.pem'))
[Convert]::ToBase64String([IO.File]::ReadAllBytes('key.pem'))
```

### 3. Colar no `ccws/.env`

```env
HTTPS_CERT=<saída base64 do cert.pem>
HTTPS_KEY=<saída base64 do key.pem>
```

Depois `docker compose up -d` (ou `docker compose restart ccws` se a stack já tava no ar).

---

## Mapa de portas e URLs úteis

| Serviço | Porta(s) host | URL / observação |
|---------|---------------|------------------|
| AoP (UI do receptor) | 8080 | http://localhost:8080 |
| CCWS (TV 3.0 WebServices) | 44652 / 44653 | HTTP / HTTPS — base do CCWS |
| KrakenD external | 44643 | HTTPS — gateway com plugin Go `consent-validator` |
| KrakenD internal | 44642 | HTTP — gateway interno (sem plugin) |
| bcast (broadcaster) | `${BCAST_PORT:-8081}` | http://localhost:8081 — apps de serviço (webmedia, uff, etc.) |
| Mosquitto MQTT | 1883 | Broker TCP |
| Mosquitto WS | `${MQTT_WS_PORT:-9001}` | WebSocket — em Windows usar **9003** |
| Redis Commander | 18081 | http://localhost:18081 — UI de inspeção do Redis |
| Validation middleware + Swagger | 3000 / 8085 | http://localhost:8085 |
| Middleware internal + Swagger | 3001 / 8086 | http://localhost:8086 |

---

## Consentimento (consent) — concedendo manualmente

A norma TV 3.0 exige **consentimento explícito** do usuário pra cada serviço DTV acessar seus dados. O CCWS e o plugin C do Mosquitto checam consent antes de liberar APIs e tópicos MQTT por serviço. Se um usuário não tem consent pro serviço ativo, ele **não aparece no profile-chooser**, e o broker pode rejeitar publish/subscribe em tópicos daquele serviço.

### Modelo no Redis

Consent é um **set Redis** por usuário, com a chave:

```
user:{userId}:consent
```

Cada elemento do set é um ID de serviço (ex.: `urn:tv30:service:webmedia`). Há um wildcard especial:

| Elemento | Significado |
|----------|-------------|
| `urn:tv30:service:webmedia` | Consent concedido para o serviço `webmedia`. |
| `urn:tv30:service:eduplay` | Consent concedido para o serviço `eduplay`. |
| `*` | **Bypass total** — usado para clientes de serviço confiáveis (bcast, ccws). Libera qualquer serviço sem checagem. |

O plugin C (`infra/mosquitto_plugin/plugin/src/authorize.c`) checa primeiro `SISMEMBER user:{id}:consent *` (bypass) e depois `SISMEMBER user:{id}:consent {service}` (consent específico).

### 1. Descobrir os IDs

**Listar todos os usuários:**

```bash
docker exec redis-auth redis-cli SMEMBERS users:index
```

Saída: lista de UUIDs / `user_<timestamp>`.

**Ver atributos de um usuário (inclui `nickname` pra identificar):**

```bash
docker exec redis-auth redis-cli HGETALL user:<userId>
```

**Ver o serviço DTV ativo:**

```bash
docker exec redis-auth redis-cli GET session:current-service-id
```

Os IDs fixos dos serviços do bcast estão definidos no `docker-compose.yml`:

| Serviço | ID |
|---------|----|
| webmedia | `urn:tv30:service:webmedia` |
| uff | `urn:tv30:service:uff` |
| eduplay | `urn:tv30:service:eduplay` |

### 2. Conceder consent

**Pra um serviço específico:**

```bash
docker exec redis-auth redis-cli SADD user:<userId>:consent urn:tv30:service:webmedia
```

**Bypass total (qualquer serviço):**

```bash
docker exec redis-auth redis-cli SADD user:<userId>:consent '*'
```

> O `*` precisa de aspas no shell pra não ser interpretado como glob. No Redis Commander (UI) basta digitar `*`.

**Conferir o que está no set:**

```bash
docker exec redis-auth redis-cli SMEMBERS user:<userId>:consent
```

Depois de mudar consent, **dispare um reload do AoP** publicando no tópico `aop/users` pra ele re-listar usuários:

```bash
docker exec mosquitto-plugin mosquitto_pub -t aop/users -m /user-files
```

(Sem isso, o profile-chooser pode continuar mostrando o estado em cache até o próximo refresh.)

### 3. Revogar consent

```bash
docker exec redis-auth redis-cli SREM user:<userId>:consent urn:tv30:service:webmedia
```

### 4. Inspecionar pela UI (mais fácil)

Abra http://localhost:18081 (Redis Commander).

1. No painel da esquerda, expanda a connection.
2. Procure a chave `user:<userId>:consent` (use o filtro `user:*:consent`).
3. Selecione — vai mostrar os elementos do set.
4. Botões `Add Member` / `Remove` operam o set diretamente.

> Em qualquer dúvida sobre quais users existem ou qual o serviço ativo, navegue por `users:index` e `session:current-service-id` na mesma UI.

---

## Troubleshooting rápido

Para casos mais detalhados, ver [`docs/troubleshooting.md`](./docs/troubleshooting.md).

### Browser dá erro de WebSocket no MQTT (console: "WebSocket connection failed")
**Causa:** porta `MQTT_WS_PORT` ocupada no host (Hyper-V usa 9001/9002 em Windows).
**Fix:** editar `.env`, `MQTT_WS_PORT=9003`, depois `docker compose up -d` (recria o container do mosquitto com a porta nova).

### `localhost:8080` dá timeout no Windows
**Causa:** `~/.wslconfig` com `networkingMode=mirrored` — incompatível com o NAT do Docker.
**Fix:** trocar para `networkingMode=NAT` + `localhostForwarding=true`, depois `wsl --shutdown` no PowerShell e reabrir a distro.

### Containers caem depois de um tempo sem uso
**Causa:** WSL2 desliga a VM por idle timeout, derrubando o Docker.
**Fix:** acrescentar `vmIdleTimeout=86400000` em `~/.wslconfig` e manter qualquer terminal aberto na distro.

### `docker compose ps` só mostra infra (redis, krakend, middleware); falta aop/ccws/bcast/mosquitto
**Causa:** `.env` ausente ou `COMPOSE_PROFILES` vazio — os serviços principais têm `profiles:` no compose e ficam fora silenciosamente quando o profile não está ativo.
**Fix:** `cp .env.example .env`, depois `docker compose up -d`.

### `exec /entrypoint.sh: no such file or directory` ao subir um container
**Causa:** script shell foi commitado com line-endings CRLF (Windows). O shebang `#!/bin/sh\r` fica inválido no container Linux.
**Fix:** `dos2unix infra/dockerfiles/entrypoint-user-files.sh`, ou forçar LF via `.gitattributes` na raiz com `*.sh text eol=lf` e re-checkout.

### `Error response from daemon: network ginga_net ... has active endpoints` ou conflict de rede
**Causa:** rede `ginga_net` ficou pendurada de uma execução anterior.
**Fix:** `docker compose down`, depois `docker network rm ginga_net`, depois `docker compose up -d` (a rede é recriada limpa).

### Para inspecionar o Redis
Abra http://localhost:18081 (Redis Commander). Tem visão de todos os keys: `session:current-user`, `users:index`, atributos de broadcaster, etc.

---

## Atualizar submodules

```bash
# Após clone sem --recurse-submodules:
git submodule update --init --recursive

# Atualizar todos os submodules pro main mais recente:
git submodule update --remote

# Atualizar só um:
git submodule update --remote aop
```

Cada submodule (aop, bcast, ccws, infra) tem um workflow `.github/workflows/bump-tv30-pointer.yml` que dispara em push na main e atualiza automaticamente o ponteiro do submodule aqui no TV30 — então em geral basta `git pull` periódico na raiz.

---

## Documentação aprofundada

- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — arquitetura completa: fluxo entre serviços, tópicos MQTT, schema do Redis, decisões arquiteturais.
- [`docs/`](./docs/) — site Jekyll com guias detalhados (troubleshooting, padrões de apps de serviço, etc.).
- [`ABNT_NBR_25608.md`](./ABNT_NBR_25608.md) — norma TV 3.0 integral, para referência.

---

## Contribuições

Cada submodule da aplicação tem uma GitHub Action que, ao push na sua main, atualiza o hash do submodule aqui no TV30 e dispara o build/publish da imagem Docker correspondente no Docker Hub. Para o desenvolvedor, basta commitar na main do submodule — o TV30 e as imagens são atualizados sozinhos.
