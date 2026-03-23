# AOP — Infraestrutura

Infraestrutura distribuída que simula um **receptor de TV 3.0** (padrão Ginga, TV digital brasileira) usando microserviços.

## Visão geral

```
Browser / App
    ↓ HTTP :8092
KrakenD (API Gateway)         ← plugin consent-validator intercepta todas as rotas
    ↓ HTTPS :44645
ccws-relay.js (WSL)           ← relay TCP transparente
    ↓ HTTPS :44643
CCWS (Windows, nativo)        ← API TV 3.0 em TypeScript
    ↓ MQTT
Mosquitto + Plugin C          ← valida ACL, consentimento e schema via Redis
    ↓
AoP (porta 8080)              ← interface do receptor (Node.js)
```

---

## Pré-requisitos

- **Windows 11** com WSL2 (Ubuntu recomendado)
- **Docker** instalado no WSL (não Docker Desktop)
- **Node.js** no Windows (para o CCWS)
- **Node.js** no WSL (para o ccws-relay)

---

## Início rápido

```powershell
# Cenário padrão (com networkingMode=mirrored)
.\start.ps1

# Com Mosquitto (fluxo MQTT completo)
.\start.ps1 -Mosquitto

# Sem networkingMode=mirrored (usa proxy-win + proxy-wsl)
.\start.ps1 -Proxies

# Tudo
.\start.ps1 -Proxies -Mosquitto
```

O script:
- Verifica Docker no WSL
- Sobe Redis, Middleware, KrakenD na ordem correta
- Detecta e corrige automaticamente o IP do bridge Docker no `docker-compose.yml` do KrakenD
- Inicia o `ccws-relay.js` no WSL
- Abre o CCWS em nova janela Windows
- Com `-Proxies`: detecta o IP do WSL, atualiza e sobe `proxy-win.js` e `proxy-wsl.js`
- Com `-Mosquitto`: sobe o Mosquitto
- Faz health check ao final e exibe o resumo das URLs

---

## Configuração de rede (fazer uma vez)

### Opção A — com `networkingMode=mirrored` (recomendado)

Elimina a necessidade dos proxies e estabiliza os IPs. Adicionar em `~/.wslconfig` (Windows):

```ini
[wsl2]
networkingMode=mirrored
```

Aplicar: `wsl --shutdown` e reabrir o terminal WSL.

### Opção B — sem mirrored (IPs mudam a cada boot)

Ver seção [Sem mirrored networking](#sem-mirrored-networking) ao final.

---

## Subindo o stack

### 1. Clonar / garantir estrutura

```
aop_infra/
  GingaDistrib/ccws/     ← repositório separado, clonar aqui
  redis/
  krakenD/
  middleware/
  start.ps1
  ccws-relay.js
```

### 2. Usar o script de inicialização

```powershell
.\start.ps1
```

O script cuida de tudo automaticamente: detecta IPs, sobe os serviços na ordem correta, popula o Redis com ACL e usuários, inicia o relay e abre o CCWS.

Ver seção [Início rápido](#início-rápido) para todas as opções de flags.

### 3. Verificar saúde do stack

```bash
# Containers rodando
wsl -- bash -c "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Relay ativo
wsl -- bash -c "ss -tlnp | grep 44645"

# Teste end-to-end (aguardar ~10s para o CCWS inicializar)
curl http://localhost:8092/health
# Esperado: 200 OK
```

### Subida manual (alternativa ao script)

<details>
<summary>Expandir comandos manuais</summary>

```bash
# 1. Redis — cria a rede ginga_net
wsl -- bash -c "cd /mnt/d/ProjCEFET/aop_infra/redis && docker compose up -d"

# 2. Middleware + Swagger UI
wsl -- bash -c "cd /mnt/d/ProjCEFET/aop_infra/middleware && docker compose up -d"

# 3. ccws-relay
wsl -- bash -c "node /mnt/d/ProjCEFET/aop_infra/ccws-relay.js &>/tmp/ccws-relay.log & disown"

# 4. KrakenD
wsl -- bash -c "cd /mnt/d/ProjCEFET/aop_infra/krakenD && docker compose up -d"

# 5. CCWS (nativo Windows — nova janela)
powershell -Command "Start-Process cmd -ArgumentList '/c cd /d D:\ProjCEFET\aop_infra\GingaDistrib\ccws && npm run dev' -WindowStyle Normal"

# 6. Mosquitto (opcional)
wsl -- bash -c "cd /mnt/d/ProjCEFET/aop_infra/mosquitto_plugin/infra && docker compose up -d"
```

</details>

---

## Serviços e portas

| Serviço | Porta | Descrição |
|---|---|---|
| KrakenD | `8092` | API Gateway — entrada de todas as requisições |
| CCWS | `44643` (HTTPS) | API TV 3.0 — roda nativo no Windows |
| ccws-relay | `44645` (WSL) | Relay TCP Docker → CCWS |
| Middleware | `3000` | Validação JWT + geração do OpenAPI spec |
| Swagger UI | `8085` | Documentação interativa das rotas |
| Redis | `6379` | Cache e estado compartilhado |
| Redis Commander | `8081` | UI web do Redis |
| Mosquitto | `1883` / `9001` | Broker MQTT |
| AoP | `8080` | Interface do receptor TV |

---

## Documentação das rotas

Acesse **`http://localhost:8085`** para o Swagger UI com todas as rotas do KrakenD.

O spec é gerado dinamicamente pelo middleware a partir do `krakenD/krakend.json`.

---

## Fluxo de autenticação

As rotas protegidas exigem um JWT no header `Authorization` (sem prefixo "Bearer"):

```
Authorization: <token>
```

**Passo 1 — Autorizar cliente** (exibe popup na AoP por 10s):
```bash
GET http://localhost:8092/tv3/authorize?clientid=myapp&display-name=MeuApp&pm=qrcode
# Retorna: { "challenge": "<base64>" }
```

**Passo 2 — Obter token** (após resolver o challenge):
```bash
GET http://localhost:8092/tv3/token?clientid=myapp&challenge-response=<base64>
# Retorna: { "accessToken": "...", "refreshToken": "...", "expiresIn": ... }
```

**Passo 3 — Usar token nas rotas protegidas**:
```bash
curl -H "Authorization: <accessToken>" http://localhost:8092/tv3/current-service
curl -H "Authorization: <accessToken>" http://localhost:8092/tv3/current-service/users/current-user
```

---

## Sem mirrored networking

Se o `networkingMode=mirrored` não estiver ativo, é necessário usar os proxies e atualizar IPs a cada boot.

### A cada boot

**1. Descobrir IP atual do WSL:**
```bash
wsl -- bash -c "hostname -I | awk '{print $1}'"
```

**2. Atualizar `proxy-win.js`** com o IP obtido:
```js
const WSL_IP = '<IP_DO_WSL>';
```

**3. Verificar gateway Docker** e atualizar `krakenD/docker-compose.yml` se necessário:
```bash
wsl -- bash -c "docker network inspect ginga_net | grep Gateway"
```

### Subir proxies (além da ordem normal)

```bash
# WSL — antes de subir o KrakenD
wsl -- bash -c "node /mnt/d/ProjCEFET/aop_infra/proxy-wsl.js &>/tmp/proxy-wsl.log & disown"

# Windows — terminal separado
node D:\ProjCEFET\aop_infra\proxy-win.js
```

Com os proxies, o fluxo de rede é:
```
Browser :8090 (Windows)
  → proxy-win.js → proxy-wsl.js
    → KrakenD Docker :8090
```

> Neste cenário a porta 8090 está disponível para o KrakenD (alterar `docker-compose.yml` de 8092 para 8090).

---

## Estrutura do repositório

```
aop_infra/
  GingaDistrib/               # Repo separado — aplicações do receptor
    ccws/                     # API TV 3.0 (TypeScript, Windows nativo)
    aop/                      # Interface do receptor (Node.js)
    user-files/               # Dados de usuários
  redis/                      # Redis + Redis Commander
  krakenD/                    # API Gateway + plugin Go
    plugin/                   # Código-fonte do plugin consent-validator
    plugins/                  # Plugin compilado (.so)
    krakend.json              # Configuração de endpoints
  middleware/                 # Validação JWT + OpenAPI spec + Swagger UI
  mosquitto_plugin/           # Broker MQTT com plugin C
  ccws-relay.js               # Relay WSL: Docker → CCWS Windows
  proxy-win.js                # Proxy Windows (sem mirrored)
  proxy-wsl.js                # Proxy WSL (sem mirrored)
```
