# TV30 — TV 3.0 AoP Experimentation

> **Repositório:** https://github.com/multisens/TV30
> **Contexto:** Projeto de pesquisa CEFET — plataforma de experimentação do padrão brasileiro de TV digital (ISDB-Tb / TV 3.0)

Monorepo principal do ecossistema TV 3.0. Orquestra todos os componentes via **submodules Git** e **Docker Compose**.
Os serviços trocam sinalização e eventos via **MQTT** (broker Mosquitto), leem e escrevem estado no **Redis** e, num caso, conversam por **HTTP direto**: o AoP faz proxy para o bcast. Clientes das APIs entram só pela **borda** (`edgegateway`).

> **Norma × implementação:** a ABNT NBR 25608 define os papéis da plataforma TV 3.0 (receptor, Ginga CC WebServices, broadcaster) e o modelo de consentimento/perfis. O transporte interno via **MQTT**, a **borda KrakenD** e o **Redis** são escolhas de implementação deste projeto — **não fazem parte da norma**.

---

## Submodules e responsabilidades

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | https://github.com/multisens/AOP | **Application-Oriented Platform** — interface do receptor TV 3.0. Renderiza UI, gerencia perfis de usuário (direto no Redis), exibe catálogo de apps e camadas de vídeo/gráficos. Node.js, porta **8080** |
| `tv3ws/` | https://github.com/multisens/TV3WS | **TV 3.0 WebServices** — implementação dos Ginga CC WebServices (Anexo C). JWT, usuários (Redis), serviços e dispositivos remotos. TypeScript, portas internas **44652** (HTTP) e **44653** (HTTPS opcional), acesso pela borda |
| `infra/` | https://github.com/multisens/Infra | **Infraestrutura Docker** — Redis, borda KrakenD (`edgegateway`, com o plugin Go `tv30-auth`), Mosquitto com plugin C de validação de esquema, dockerfiles |
| `bcast/` | https://github.com/multisens/BcastService | **Broadcaster** — simula transmissão de sinal TV 3.0. Streaming via FFmpeg, sinalização via MQTT. Hospeda módulos de apps de serviço (webmedia, uff, etc.) seguindo padrão `src/modules/<nome>/` |

O `.gitmodules` tem só esses quatro. `eduplay` (motadv/eduplay), `sepe` (motadv/se-presentation-engine) e `utils` (multisens/TV30-Utils) são repositórios relacionados, não submódulos deste.

---

## Arquitetura

Estado atual do código:

```
Cliente (app de emissora, app local autônomo, dispositivo remoto)
        ↓ HTTP :44642 (interna, porta fixa da C.3.4) | :44643 (externa)
  edgegateway (infra/)    ← borda única: KrakenD interno + externo + docs;
                            plugin Go tv30-auth valida credenciais (warn)
        ↓ HTTP na ginga_net
  tv3ws (tv3ws/)          ← Ginga CC WebServices (Anexo C); assina o
                            accessToken; estado no Redis
        ↕ MQTT                    ↕ Redis
  Mosquitto + plugin C    ← valida o ESQUEMA das mensagens publicadas
        ↕ MQTT
  AoP (aop/)              ← UI do receptor; perfis lidos/escritos direto no Redis
        ↓ HTTP (proxy /graphicsAppProxy e /videoStreamProxy)
  bcast (bcast/)          ← sinalização (BAMT/ESG/BALD) por MQTT; apps de
                            serviço e mídia por HTTP
```

**Canais internos.** A comunicação interna não é só por MQTT, ao contrário do que esta seção dizia antes (o código desmente):

- sinalização e eventos passam pelo MQTT;
- o AoP e o tv3ws acessam o Redis diretamente;
- o AoP busca as aplicações e o vídeo do bcast por proxy HTTP, no `bcastEntryPackageUrl` anunciado (`aop/src/server.js`).

Os gateways não validam consentimento, e o plugin C do broker não faz controle de acesso a tópicos. A validação de credenciais é feita na borda (decisão de 28/09), pelo plugin `tv30-auth`.

---

## Tópicos MQTT principais

Publicadores e consumidores conferidos nas chamadas `publish`/`subscribe` do código de aop, tv3ws e bcast.

| Tópico | Publicado por | Consumido por | Significado |
|--------|--------------|---------------|-------------|
| `aop/currentUser` | AoP; tv3ws (C.6.14.4) | AoP, tv3ws | Usuário corrente |
| `aop/currentService` | AoP | tv3ws, AoP | Serviço DTV selecionado |
| `aop/users` | AoP | tv3ws, AoP | Gatilho de re-sync `userData.json` → Redis |
| `aop/display/layers/*` | AoP; tv3ws (popups de autorização) | front do AoP | Camadas de renderização (vídeo, GUI, gráficos, popup) |
| `aop/:serviceId/currentApp` | — (nenhum publicador no código destes módulos) | tv3ws | App ativo no serviço |
| `aop/services` | — (nenhum publicador no código destes módulos) | tv3ws | Lista de serviços |
| `tlm/lls/#` | bcast | AoP | Metadados de serviço (BAMT) |
| `tlm/sls/+/#` | bcast | AoP | Metadados por serviço (ESG, BALD) |
| `aop/devices/<classe>` | tv3ws | — | Dispositivos remotos registrados |

---

## Execução

```bash
docker compose up -d
```

Defaults vêm do `.env` (raiz). Em Windows + WSL2 com 9001 ocupada no host, definir `MQTT_WS_PORT=9003` no `.env`. Para desenvolver com um módulo no host (`npm run dev`), ver [`docs/dev-local.md`](./docs/dev-local.md).

### Containers e portas

| Container | Porta(s) no host | Descrição |
|-----------|----------|-----------|
| `redis` | 6379; commander em porta dinâmica | Estado de sessão, usuários e credenciais + redis-commander embutido (debug) |
| `mqtt-broker` (serviço `mosquitto`) | 1883, `${MQTT_WS_PORT:-9001}` | MQTT broker + plugin C de validação de esquema |
| `edgegateway` | 44642, 44643; docs (8085) em porta dinâmica | Borda única: KrakenD interno e externo + Swagger UI; plugin `tv30-auth`; morre-inteiro |
| `tv3ws` | 45000–45199 (WebSockets) | TV 3.0 WebServices. 44652/44653 só na `ginga_net` |
| `aop` | 8080 | Interface do receptor |
| `bcast` | `${BCAST_PORT:-8081}` | Broadcaster + módulos de apps de serviço |

### Apps de serviço (módulos do bcast)

Seguindo o padrão `webmedia` em `bcast/src/modules/<nome>/`: `index.ts` (implementa `ServiceInterface` com router próprio + EJS), `app.ejs`, `companion/`. Reaproveita o cliente MQTT do bcast — não cria novo container.

---

## Stack

| Tecnologia | Uso |
|------------|-----|
| Docker + Compose | Orquestração full-container |
| Redis (ioredis) | Estado de sessão, usuários e credenciais (tv3ws, AoP) |
| Node.js 23+ | AoP, tv3ws, bcast |
| TypeScript | tv3ws, bcast |
| MQTT (Mosquitto) | Sinalização e eventos entre serviços |
| KrakenD + plugin Go | Borda única (`edgegateway`) com validação de credenciais (`tv30-auth`) |
| Mosquitto plugin C | Validação de esquema das mensagens publicadas |
| FFmpeg | Streaming de vídeo no broadcaster |

---

## Gerenciamento de submodules

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
git submodule update --init --recursive
git submodule update --remote                # atualiza todos
git submodule update --remote aop            # só aop
git submodule status
```

Clone anterior ao renome `ccws` → `tv3ws`: `git submodule sync --recursive && git submodule update --init --recursive` e apagar a pasta `ccws/` que sobrou (ou clonar de novo) — ver [`docs/instalacao.md`](./docs/instalacao.md).

**CI:** cada submodule (aop, bcast, tv3ws, infra) tem `.github/workflows/bump-tv30-pointer.yml` que dispara em push em main e atualiza automaticamente o ponteiro do submodule no TV30. Secret `TV30_REPO_TOKEN` (PAT com `Contents: write` no TV30) configurado em cada repo.

---

## Decisões arquiteturais

| Decisão | Motivo |
|---------|--------|
| Modo único = Linux + Docker full-container | Simplificação — um único caminho de deploy (desenvolvimento: infra em containers + módulo no host) |
| Monorepo com submodules | Cada componente tem ciclo de vida independente |
| MQTT para sinalização e eventos | Desacoplamento — não é o único canal interno (ver *Canais internos*) |
| Estado de usuários em Redis | Consistência entre serviços; `userData.json` é carga inicial e re-sync |
| Apps de serviço como módulos do bcast | Único container `bcast` serve tudo (sem duplicação MQTT/CORS) |
| Borda única com duas superfícies | Interna 44642 (fixa C.3.4) e externa 44643; credenciais validadas na borda (decisão de 28/09: o tv3ws só implementaria as APIs). Estado corrente: o tv3ws ainda responde 107 a credencial inválida e 106 ao não local na superfície HTTP, nos dois modos; limpeza pendente |

---

## Conhecidos / atenção

- `host.docker.internal:host-gateway` (não IP fixo)
- Em Windows+WSL2 com 9001 ocupada no host: definir `MQTT_WS_PORT=9003` no `.env` da raiz (ex: serviço Hyper-V já usa 9001/9002)

## Troubleshooting WSL2 + Docker

**Sintoma:** após `docker compose up -d`, containers Up no WSL mas `localhost:8080` no Windows host dá timeout/connection reset.

**Causa típica:** `~/.wslconfig` com `networkingMode=mirrored`. Mirrored mode + Docker tem issues conhecidos — Docker faz NAT via iptables que mirrored não espelha bem pro host Windows.

**Solução:** o default do WSL2 (`networkingMode=NAT` + `localhostForwarding=true`) funciona out-of-the-box com Docker. Se você editou o `.wslconfig`, garanta:

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
```

Depois: `wsl --shutdown` no PowerShell pra aplicar, então re-iniciar a distribuição.

**Verificação:** `Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 8080 }` no PowerShell deve mostrar a porta 8080 listening em 127.0.0.1.
