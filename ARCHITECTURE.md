# TV30 — TV 3.0 AoP Experimentation

> **Repositório:** https://github.com/multisens/TV30
> **Diretório local:** `D:/ProjCEFET/TV30/`
> **Contexto:** Projeto de pesquisa CEFET — plataforma de experimentação do padrão brasileiro de TV digital (ISDB-Tb / TV 3.0)

Monorepo principal do ecossistema TV 3.0. Orquestra todos os componentes via **submodules Git** e **PM2**.
A comunicação entre serviços é feita exclusivamente via **MQTT** (broker Mosquitto), seguindo arquitetura de microsserviços desacoplados.

---

## Submodules e responsabilidades

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | https://github.com/multisens/AOP | **Application-Oriented Platform** — interface do receptor TV 3.0. Renderiza UI, gerencia perfis de usuário, exibe catálogo de apps e camadas de vídeo/gráficos. Node.js, porta **8080** |
| `ccws/` | https://github.com/multisens/CCWS | **TV 3.0 Ginga CC WebServices** — API REST/HTTPS do padrão TV 3.0. Autenticação JWT, gerenciamento de usuários, serviços e dispositivos remotos. TypeScript, portas **44652** (HTTP) e **44653** (HTTPS) |
| `infra/` | https://github.com/multisens/Infra | **Infraestrutura Docker** — Redis, KrakenD (gateways externo e interno), Mosquitto com plugin C, middlewares de validação, relay TCP WSL↔Windows |
| `ginga/` | https://github.com/multisens/GingaDistrib | **Ginga-NCL Runtime** — middleware interativo de TV digital. Agendador NCL, simulador de dispositivo remoto, explorador de tópicos MQTT |
| `bcast/` | https://github.com/multisens/BcastService | **Broadcaster** — simula transmissão de sinal TV 3.0. Streaming via FFmpeg, sinalização via MQTT |
| `eduplay/` | https://github.com/motadv/eduplay | **EduPlay** — funcionalidades educacionais sobre a plataforma TV 3.0 |
| `sepe/` | https://github.com/motadv/se-presentation-engine | **SE Presentation Engine** — motor de apresentação de conteúdo |
| `utils/` | https://github.com/multisens/TV30-Utils | **Utilitários** — explorador web de tópicos MQTT, utilitários de dispositivo remoto |

---

## Arquitetura

```
Dispositivo Remoto / App
        ↓ HTTPS :44643
  KrakenD External (infra/)       ← valida consentimento (plugin Go)
        ↓
  CCWS (ccws/)                    ← API TV 3.0, autenticação JWT
        ↓ MQTT
  Mosquitto + Plugin C (infra/)   ← ACL, consentimento, schema validation
        ↓ MQTT
  AoP (aop/)                      ← UI do receptor, perfis, display layers
        ↑
  Broadcaster (bcast/)            ← streaming de conteúdo
  Ginga-NCL (ginga/)              ← apps interativos NCL
```

**Regra central:** todos os serviços se comunicam via MQTT. Nenhum serviço chama outro diretamente por HTTP internamente — isso é responsabilidade exclusiva do CCWS via gateways.

---

## Tópicos MQTT principais

| Tópico | Publicado por | Consumido por | Significado |
|--------|--------------|---------------|-------------|
| `aop/currentUser` | CCWS | AoP | Usuário logado atualmente |
| `aop/currentService` | CCWS | AoP | Serviço TV selecionado |
| `aop/users` | CCWS | AoP | Lista de usuários disponíveis |
| `aop/display/layers/*` | CCWS | AoP | Camadas de renderização (vídeo, GUI, gráficos, popup) |
| `aop/:serviceId/currentApp` | CCWS | AoP | App ativo no serviço |
| `tlm/lls/#` | bcast | AoP, CCWS | Metadados de Linear Live Service |
| `tlm/sls/+/#` | bcast | AoP, CCWS | Metadados por serviço |
| `aop/devices` | CCWS | AoP | Dispositivos remotos conectados |

---

## Stack

| Tecnologia | Uso |
|------------|-----|
| Node.js 23+ | AoP, CCWS, bcast, utils |
| TypeScript | CCWS, eduplay, sepe |
| MQTT (Mosquitto) | Comunicação entre todos os serviços |
| PM2 | Orquestração de processos (ambiente sem Docker) |
| Docker + WSL | Infraestrutura (Redis, KrakenD, Mosquitto plugin) |
| FFmpeg | Streaming de vídeo no broadcaster |
| NW.js | Apps desktop (Ginga) |
| Lua | Agendador NCL no Ginga |
| Go | Plugin KrakenD consent-validator |
| C | Plugin Mosquitto ACL/consentimento |

---

## Gerenciamento de submodules

```bash
# Clonar o TV30 com todos os submodules
git clone --recurse-submodules https://github.com/multisens/TV30.git

# Inicializar submodules em um clone existente
git submodule update --init --recursive

# Atualizar todos os submodules para o commit mais recente do remote
git submodule update --remote

# Atualizar um submodule específico
git submodule update --remote aop

# Ver estado de todos os submodules
git submodule status
```

---

## Execução (PM2)

```bash
# Linux / macOS
pm2 start linux.config.js
pm2 start mac.config.js

# WSL
pm2 start wsl.config.js

# Ambiente de exposição/demo
pm2 start setexpo.config.js
```

**Serviços gerenciados pelo PM2:**

| Nome PM2 | Pasta | Porta | Descrição |
|----------|-------|-------|-----------|
| `broker` | — | 1883 | Mosquitto MQTT Broker |
| `aop` | `aop/` | 8080 | Interface do receptor |
| `apps` | `bcast/` | 8081 | Broadcaster apps |
| `tv3ws` | `ccws/` | 44642 | TV 3.0 WebServices |
| `eduplay` | `eduplay/` | — | EduPlay |
| `sepe` | `sepe/` | — | Presentation Engine |
| `chrome-aop` | — | — | Abre browser no AoP |

> Para a infraestrutura Docker (Redis, KrakenD, Mosquitto plugin), consultar o `CLAUDE.md` em `infra/`.

---

## Decisões arquiteturais

| Decisão | Motivo |
|---------|--------|
| Monorepo com submodules | Cada componente tem ciclo de vida e equipe independentes, mas o TV30 os orquestra |
| MQTT como único canal interno | Desacoplamento total — nenhum serviço conhece o endereço de outro |
| `aop` e `ccws` extraídos do GingaDistrib | Separação de responsabilidades — eram um monólito dentro do GingaDistrib |
| Dois gateways KrakenD (externo/interno) | Externo valida consentimento; interno é confiável sem overhead |
| Infra separada em repo próprio | Infraestrutura tem ciclo de vida diferente das aplicações |
