# TV30 — TV 3.0 AoP Experimentation

> **Repositório:** https://github.com/multisens/TV30
> **Diretório local:** `D:/ProjCEFET/TV30/`
> **Contexto:** Projeto de pesquisa CEFET — plataforma de experimentação do padrão brasileiro de TV digital (ISDB-Tb / TV 3.0)

Monorepo principal do ecossistema TV 3.0. Orquestra todos os componentes via **submodules Git** e **Docker Compose**.
A comunicação entre serviços é feita exclusivamente via **MQTT** (broker Mosquitto), seguindo arquitetura de microsserviços desacoplados.

---

## Submodules e responsabilidades

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | https://github.com/multisens/AOP | **Application-Oriented Platform** — interface do receptor TV 3.0. Renderiza UI, gerencia perfis de usuário, exibe catálogo de apps e camadas de vídeo/gráficos. Node.js, porta **8080** |
| `ccws/` | https://github.com/multisens/CCWS | **TV 3.0 Ginga CC WebServices** — API REST/HTTPS do padrão TV 3.0. Autenticação JWT, gerenciamento de usuários (estado em Redis), serviços e dispositivos remotos. TypeScript, portas **44652** (HTTP) e **44653** (HTTPS) |
| `infra/` | https://github.com/multisens/Infra | **Infraestrutura Docker** — Redis, KrakenD (gateways externo e interno), Mosquitto com plugin C, middlewares de validação, dockerfiles |
| `bcast/` | https://github.com/multisens/BcastService | **Broadcaster** — simula transmissão de sinal TV 3.0. Streaming via FFmpeg, sinalização via MQTT. Hospeda módulos de apps de serviço (webmedia, uff, etc.) seguindo padrão `src/modules/<nome>/` |
| `eduplay/` | https://github.com/motadv/eduplay | **EduPlay** — funcionalidades educacionais |
| `sepe/` | https://github.com/motadv/se-presentation-engine | **SE Presentation Engine** |
| `utils/` | https://github.com/multisens/TV30-Utils | **Utilitários** — explorador web de tópicos MQTT |

---

## Arquitetura

```
Dispositivo Remoto / App
        ↓ HTTPS :44643
  KrakenD External (infra/)       ← valida consentimento (plugin Go)
        ↓
  CCWS (ccws/)                    ← API TV 3.0, JWT, estado em Redis
        ↓ MQTT
  Mosquitto + Plugin C (infra/)   ← ACL, consentimento, schema validation
        ↓ MQTT
  AoP (aop/)                      ← UI do receptor, perfis, display layers
        ↑
  Broadcaster (bcast/)            ← streaming + módulos de apps de serviço
```

**Regra central:** todos os serviços se comunicam via MQTT. Nenhum serviço chama outro diretamente por HTTP internamente — isso é responsabilidade do CCWS via gateways.

---

## Tópicos MQTT principais

| Tópico | Publicado por | Consumido por | Significado |
|--------|--------------|---------------|-------------|
| `aop/currentUser` | CCWS | AoP | Usuário logado atualmente |
| `aop/currentService` | CCWS | AoP | Serviço TV selecionado |
| `aop/users` | (handler subscrito no CCWS) | CCWS | Trigger de re-sync userData.json → Redis |
| `aop/display/layers/*` | CCWS | AoP | Camadas de renderização (vídeo, GUI, gráficos, popup) |
| `aop/:serviceId/currentApp` | CCWS | AoP | App ativo no serviço |
| `tlm/lls/#` | bcast | AoP, CCWS | Metadados de Linear Live Service |
| `tlm/sls/+/#` | bcast | AoP, CCWS | Metadados por serviço |
| `aop/devices` | CCWS | AoP | Dispositivos remotos conectados |

---

## Execução

```bash
docker compose up -d
```

Defaults vêm do `.env` (raiz). Em Windows + WSL2 com 9001 ocupada no host, definir `MQTT_WS_PORT=9003` no `.env`.

### Containers e portas

| Container | Porta(s) | Descrição |
|-----------|----------|-----------|
| `redis` | 6379 | Estado de sessão + usuários |
| `redis-commander` | 18081 | UI de inspeção do Redis |
| `mosquitto` | 1883, `${MQTT_WS_PORT:-9001}` | MQTT broker + plugin C ACL/consentimento |
| `krakend-external` | 44643 | Gateway externo (com plugin Go consent-validator) |
| `krakend-internal` | 44642 | Gateway interno (sem plugin) |
| `validation-middleware` | 3000, 8085 | Middleware externo + Swagger |
| `middleware-internal` | 3001, 8086 | Middleware interno + Swagger |
| `ccws` | 44652, 44653 | TV 3.0 WebServices (HTTP, HTTPS) |
| `aop` | 8080 | Interface do receptor |
| `bcast` | 8081 | Broadcaster + módulos de apps de serviço |

### Apps de serviço (módulos do bcast)

Seguindo o padrão `webmedia` em `bcast/src/modules/<nome>/`: `index.ts` (implementa `ServiceInterface` com router próprio + EJS), `app.ejs`, `companion/`. Reaproveita o cliente MQTT do bcast — não cria novo container.

---

## Stack

| Tecnologia | Uso |
|------------|-----|
| Docker + Compose | Orquestração full-container |
| Redis (ioredis) | Estado de sessão + usuários no CCWS |
| Node.js 23+ | AoP, CCWS, bcast |
| TypeScript | CCWS, eduplay, sepe |
| MQTT (Mosquitto) | Comunicação entre todos os serviços |
| KrakenD + plugin Go | Gateway externo com consent-validator |
| Mosquitto plugin C | ACL/consentimento via Redis |
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

**CI:** cada submodule (aop, bcast, ccws, infra) tem `.github/workflows/bump-tv30-pointer.yml` que dispara em push em main e atualiza automaticamente o ponteiro do submodule no TV30. Secret `TV30_REPO_TOKEN` (PAT com `Contents: write` no TV30) configurado em cada repo.

---

## Decisões arquiteturais

| Decisão | Motivo |
|---------|--------|
| Modo único = Linux + Docker full-container | Simplificação — um único caminho de deploy |
| Monorepo com submodules | Cada componente tem ciclo de vida independente |
| MQTT como único canal interno | Desacoplamento total |
| Estado de usuários em Redis | Consistência cross-instance, sync inicial via `userData.json` |
| Apps de serviço como módulos do bcast | Único container `bcast` serve tudo (sem duplicação MQTT/CORS/ACL) |
| Dois gateways KrakenD | Externo valida consentimento; interno é confiável sem overhead |

---

## Conhecidos / atenção

- `host.docker.internal:host-gateway` (não IP fixo)
- Em Windows+WSL2 com 9001 ocupada no host: definir `MQTT_WS_PORT=9003` no `.env` da raiz (ex: serviço Hyper-V já usa 9001/9002)
- Token JWT no CCWS: sem prefixo "Bearer " (bug conhecido)
- `ignoreExpiration: true` no middleware (compat CCWS)
- Mosquitto plugin: `authorize_access` está **comentado** (todos clientes liberados — workaround temporário). Reativar quando ACL/consent estiverem maduros.

## Troubleshooting WSL2 + Docker

**Sintoma:** após `docker compose up -d`, containers Up no WSL mas `localhost:8080` no Windows host dá timeout/connection reset.

**Causa típica:** `~/.wslconfig` com `networkingMode=mirrored`. Mirrored mode + Docker tem issues conhecidos — Docker faz NAT via iptables que mirrored não espelha bem pro host Windows.

**Solução:** o default do WSL2 (`networkingMode=NAT` + `localhostForwarding=true`) funciona out-of-the-box com Docker. Se você editou o `.wslconfig`, garanta:

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
```

Depois: `wsl --shutdown` no PowerShell pra aplicar, então re-iniciar a distro.

**Verificação:** `Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 8080 }` no PowerShell deve mostrar a porta 8080 listening em 127.0.0.1.
