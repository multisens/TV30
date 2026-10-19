# TV 3.0 AoP Experimentation

![Node Version](https://img.shields.io/badge/Node.js-23.11.1-blueviolet?logo=nodedotjs)  ![MQTT](https://img.shields.io/badge/MQTT-blueviolet?logo=mqtt)  ![Docker](https://img.shields.io/badge/Docker-blue?logo=docker)

Testbed do padrão brasileiro de TV digital interativa **TV 3.0** (ABNT NBR 25608). Implementa, em microsserviços, os papéis da plataforma TV 3.0:
- o receptor (AoP);
- os TV 3.0 WebServices (tv3ws);
- o broadcaster simulado (bcast).

Por baixo, uma infraestrutura de apoio escolhida por este projeto:
- a borda KrakenD (`edgegateway`);
- o broker MQTT (Mosquitto, com plugin C de validação de schema);
- o estado em Redis.

> **Norma × implementação:** a ABNT NBR 25608 especifica os TV 3.0 WebServices (Anexo C), o gerenciador de perfis (8.7) e o de privacidade (8.8). O transporte interno via **MQTT**, a **borda KrakenD** e o **Redis** são decisões de arquitetura deste testbed: **não fazem parte da norma**.

É um **monorepo com submodules Git**, orquestrado por um único `docker-compose.yml` na raiz. A stack sobe inteira de uma vez, em qualquer host com Docker, sem build local. As imagens vêm do Docker Hub, publicadas pelos workflows de cada submodule. Depois de um `git pull`, rode `docker compose pull` para atualizar as imagens locais.

---

## Pré-requisitos

- **Docker Engine** + **Compose v2** (`docker compose`, não `docker-compose`).
- **Git** com suporte a submodules.
- **Mac com Apple Silicon:** as imagens publicadas são `amd64`. Rode `docker compose build` antes de subir.

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

E reabra a distribuição. **Não use `networkingMode=mirrored`**: o Docker faz NAT via iptables, e o modo mirrored não espelha bem para o host Windows, o que dá timeout em `localhost:PORT`. O `vmIdleTimeout=86400000` (24 h) evita que a VM seja desligada por inatividade, o que derrubaria os containers.

---

## Quick start

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
cd TV30
cp .env.example .env
./tv30 up            # Windows: .\tv30.ps1 up
```

Abra http://localhost:8080, a interface do receptor (AoP). Para descer: `./tv30 down`.

O `./tv30 up` faz o `docker compose up -d` e sobe o anunciante da descoberta SSDP, que roda no host, fora do Docker. Também há `./tv30 status` e `./tv30 logs`. Só `docker compose up -d` também funciona, mas sem a descoberta.

> **Primeira subida, o que acontece sozinho:** três tarefas preparam o ambiente antes dos serviços.
> - O `preflight` diagnostica DNS e portas ocupadas e imprime os avisos no início do log (`docker logs tv30-preflight`). Se a subida falhar com `address already in use`, o dono da porta já está nomeado ali; a triagem completa está em [`docs/troubleshooting.md`](./docs/troubleshooting.md).
> - O `userfiles-seed` cria e popula `./user-files` a partir do template.
> - O `tls-init` gera o certificado do receptor em `.tv30/tls`.
>
> O `tv3ws/.env` é opcional.

> **Importante: não rode `docker compose` em `infra/`.** O `infra/` é submodule, e o compose dele já entra pelo `include:` do `docker-compose.yml` da raiz. Subido de dentro de `infra/`, o compose não vê os serviços `aop`, `tv3ws` e `bcast`.

> **Importante: sem `.env` na raiz, os serviços principais ficam de fora sem aviso.** O `aop`, o `tv3ws`, o `bcast`, o `mosquitto` e o `sysctl-init` têm `profiles` no compose. Sem `COMPOSE_PROFILES=mqtt,linux`, que vem no `.env.example`, só sobe a infra. Comece sempre com `cp .env.example .env`.

---

## Variáveis do `.env` (raiz)

| Variável | Default | Descrição |
|----------|---------|-----------|
| `COMPOSE_PROFILES` | `mqtt,linux` | Profiles ativos. Sem isto, `aop`, `tv3ws`, `bcast`, `mosquitto` e `sysctl-init` não sobem. |
| `DOCKERHUB_NS` | `labmultisens` | Namespace do Docker Hub de onde puxar as imagens. |
| `IMAGE_TAG` | `latest` | Tag das imagens. |
| `AOP_PUBLIC_PORT` | `8080` | Porta do AoP no host. |
| `APPS_DOMAIN` | `apps.localhost` | Domínio dos hosts das apps de emissora (`<app>.apps.localhost`). Só resolve na própria máquina; para abrir a TV de outra máquina, use um domínio resolvível na rede. |
| `BCAST_PUBLISH` / `MQTT_WS_PUBLISH` | `8081` / `9001` | Publicação no host do bcast e do MQTT por WebSocket. Só o número = porta escolhida pelo Docker; `host:container` = porta fixa. |
| `EDGE_EXT_PUBLISH` | `44643:44643` | Publicação da superfície externa da borda. |
| `EDGE_VARIANT` | `linux` | `linux` = tv3ws em container; `windows` = tv3ws no host ([`docs/dev-local.md`](./docs/dev-local.md)). |
| `SERVER_URL` | `localhost` | Host que os dispositivos externos usam para abrir os WebSockets de remote-device. |
| `TV3WS_WS_TLS` | `true` | `false` = WebSockets de remote-device em `ws://` em vez de `wss://`. |
| `JWT_SECRET` / `JWT_ISSUER` | default de desenvolvimento / `GenericIssuer` | Segredo e emissor do access token, os mesmos para o tv3ws e para a borda. Defina-os aqui, e não no `tv3ws/.env`. |
| `AUTH_ENFORCE` | `enforce` | `warn` só registra as recusas de credencial (log `[tv30-auth] WARN` e cabeçalho `X-TV30-Auth-Warn`). |
| `SSDP_ENABLED` | `true` | `false` = o `./tv30 up` não sobe o anunciante SSDP. |
| `SSDP_ADVERTISE_HOST` | vazia | Fixa o host do anúncio e do `/manifest`. Vazia = IP da máquina, detectado. |
| `SSDP_INTERFACE` | vazia | Força a interface do anúncio (ex.: `eth0`, `en0`). |
| `REDIS_COMMANDER_USER` / `REDIS_COMMANDER_PASSWORD` | `admin` / `tv30-redis-admin` | Login da interface administrativa do Redis. O banco (6379) não tem senha. |

---

## HTTPS

A superfície externa da borda (44643) fala HTTPS. O certificado é autoassinado, gerado na primeira subida em `.tv30/tls`, e não há nada a configurar. O mesmo certificado serve:
- ao HTTPS interno do tv3ws;
- ao pareamento do cliente não local;
- aos WebSockets de remote-device (`wss://`).

- **Cliente de teste:** `curl -k https://localhost:44643/...`, ou confie no `.tv30/tls/cert.pem`.
- **App de navegador com `wss://`:** o navegador não abre `wss://` com certificado em que não confia. Confie no certificado ou use `TV3WS_WS_TLS=false`.
- **Trocar o certificado:** ponha `cert.pem` e `key.pem` em `.tv30/tls` e recrie a stack.
- **tv3ws no host (`npm run dev`):** `TV30_TLS_DIR=../.tv30/tls`.

---

## Descoberta SSDP

O `./tv30 up` sobe o anunciante SSDP (C.3.4) no host. O anúncio aponta para `http://<IP da máquina>:44642/manifest`.

- Libere a UDP 1900 e a TCP 44642 no firewall.
- **Windows:** aceite o pedido do Defender para "redes privadas".
- **macOS:** dê ao terminal a permissão de Rede Local (Ajustes > Privacidade e Segurança > Rede Local).
- Sem o anúncio, o cliente chega ao receptor pelo IP: `http://<IP>:44642/manifest`.

Detalhes e medições: [`docs/ssdp.md`](./docs/ssdp.md).

---

## Mapa de portas e URLs úteis

| Serviço | Porta(s) host | URL / observação |
|---------|---------------|------------------|
| AoP (UI do receptor) | 8080 | http://localhost:8080; o MQTT da página da TV passa por `/mqtt` |
| Apps de emissora | 8080 | `http://<app>.apps.localhost:8080/graphicsAppProxy/...` |
| edgegateway, superfície interna | 44642 | HTTP, porta fixa da norma (C.3.4) |
| edgegateway, superfície externa | 44643 | HTTPS |
| edgegateway, docs | dinâmica | Swagger UI: `docker port edgegateway 8085` |
| tv3ws | — | Não publicado no host: os clientes entram pela borda |
| tv3ws, WebSockets de remote-device | 45000–45199 | `wss://SERVER_URL:<porta>`, devolvida no registro |
| Anunciante SSDP (no host) | UDP 1900 | Subido pelo `./tv30 up` |
| bcast (broadcaster) | dinâmica | `docker compose port bcast 8081` |
| Mosquitto MQTT | 1883 | Broker TCP |
| Mosquitto WS | dinâmica | `docker compose port mosquitto 9001` |
| Redis | 6379, só em `127.0.0.1` | Sem senha |
| Redis Commander | dinâmica | `docker port redis 18081`; login na tabela de variáveis |

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

Cada submodule (aop, bcast, tv3ws, infra) tem um workflow `.github/workflows/bump-tv30-pointer.yml`. Ele dispara a cada push na main e atualiza o ponteiro do submodule aqui no TV30; em geral, basta um `git pull` periódico na raiz.

---

## Documentação aprofundada

- [`docs/`](./docs/): site Jekyll com guias detalhados (primeiros passos, como funciona, troubleshooting, padrões de apps de serviço etc.).
- [`ARCHITECTURE.md`](./ARCHITECTURE.md): canais entre serviços, tópicos MQTT, containers e portas.
- [`docs/dev-local.md`](./docs/dev-local.md): desenvolvimento com um módulo rodando no host.

---

## Contribuições

Cada submodule tem uma GitHub Action que, a cada push na main, faz duas coisas:
1. constrói e publica no Docker Hub as imagens do submodule;
2. atualiza o hash do submodule aqui no TV30.

Para o desenvolvedor, basta commitar na main do submodule.
