# aop_infra

Infraestrutura distribuída do projeto GingaDistrib, desenvolvido no contexto do CEFET.
Simula um **receptor de TV 3.0** (padrão brasileiro de TV digital) usando microserviços.
Cada serviço vive em sua própria pasta com seu `docker-compose.yml` isolado.
Todos os containers se comunicam pela rede Docker compartilhada `ginga_net`.

---

## Detalhes técnicos críticos

- **Docker só disponível via WSL** — usar sempre `wsl bash << 'WSLEOF' ... WSLEOF`
- **KrakenD 2.7 usa Go 1.22.7** (confirmado via `strings /usr/bin/krakend | grep go1.`)
- **Plugin builder image `devopsfaith/krakend-plugin-builder:2.7` não existe** — usar `golang:1.22.7-alpine` com CGO e gcc
- **Authorization header no CCWS não usa prefixo "Bearer"** — bug conhecido no `authorization.ts` que passa o header completo para `jwt.decode`. O token deve ser enviado RAW, sem "Bearer "
- **CCWS trata expiração de forma diferente** — `exp` check está comentado em `manager.ts` linhas 100-108. O middleware Node.js usa `ignoreExpiration: true` para compatibilidade
- **CCWS rejeita clientes HTTP não-locais com erro 106** — `krakend-external` conecta ao CCWS via HTTPS (porta 44653 via relay). `allow_insecure_connections: true` no `krakend.json` resolve o cert self-signed. `krakend-internal` conecta via HTTP (porta 44652 via relay) — sem esse problema
- **host.docker.internal NÃO funciona com Docker via WSL** (funciona só no Docker Desktop). Solução: `extra_hosts: ["host.docker.internal:<GATEWAY>"]` no `docker-compose.yml` do KrakenD. O `<GATEWAY>` correto é o **IP do bridge Docker** (`docker network inspect ginga_net | grep Gateway`), pois o `ccws-relay.js` roda no WSL — não no Windows. Usar o IP do Windows (`ip route show | grep default` no WSL) é errado aqui.
- **WSL `networkingMode=mirrored` bloqueia porta do Docker** — com este modo ativo (`~/.wslconfig`), portas que o Windows já ocupa ficam indisponíveis para o Docker no WSL. Sintoma: `failed to bind host port: address already in use` mesmo sem nada aparente no WSL (`ss -tlnp` não mostra nada). Verificar com `netstat -ano | grep <porta>` no Windows. Solução: usar uma porta diferente no `docker-compose.yml`.
- **Porta 8090 permanentemente bloqueada nesta máquina** — `svchost.exe` (PID variável) ocupa a 8090 no Windows via mirrored networking como resíduo de container anterior. Os KrakenDs usam portas **44643** (externo) e **44642** (interno).
- **Com `networkingMode=mirrored` o `proxy-win.js` não é necessário** — portas Docker no WSL são automaticamente espelhadas para `localhost` no Windows. KrakenD externo em `:44643` e interno em `:44642` já são acessíveis diretamente no Windows.

---

## Estrutura do projeto

```
aop_infra/
  GingaDistrib/               # Repo git separado (ignorado via .gitignore) — aplicações do receptor TV 3.0
    aop/                      # Application-Oriented Platform (UI, Node.js, porta 8080)
    ccws/                     # TV 3.0 Ginga CC WebServices (API HTTP/HTTPS, TypeScript)
      .env                    # JWT_SECRET, HTTPS_KEY/CERT, USER_DATA_FILE (já configurado)
    user-files/               # Arquivos e dados de usuários
  redis/                      # Banco em memória compartilhado (auth, ACL, consentimento)
  krakenD_external/           # API Gateway externo (dispositivos remotos — com plugin consent-validator)
    plugin/                   # Código-fonte do plugin Go
      consent-validator.go    # Plugin HTTP Server
      go.mod                  # go 1.22, sem dependências externas
      Dockerfile.build        # Builder com golang:1.22.7-alpine + gcc + CGO
      build.sh                # Script de build (referência — usar Dockerfile.build)
    plugins/                  # Output da compilação (.so) — montado no container
    krakend.json              # Config: plugin/http-server, backend HTTPS:44655, allow_insecure_connections: true
    docker-compose.yml        # container: krakend-external, porta 44643
  krakenD_internal/           # API Gateway interno (comunicação confiável — sem plugin)
    krakend.json              # Config: backend HTTP:44654, allow_insecure_connections: false
    docker-compose.yml        # container: krakend-internal, porta 44642
  middleware/                 # Middleware de validação JWT para o gateway externo (Node.js)
    index.js                  # POST /validate — valida JWT; GET /openapi.json — spec do krakenD_external
    package.json
    Dockerfile
    docker-compose.yml        # containers: validation-middleware (3000) + swagger-ui (8085)
  middleware_internal/        # Middleware/Swagger para o gateway interno (Node.js)
    index.js                  # Mesma base do middleware externo
    package.json
    Dockerfile
    docker-compose.yml        # containers: middleware-internal (3001) + swagger-ui-internal (8086)
  mosquitto_plugin/           # Broker MQTT com plugin de segurança em C
    plugin/                   # Código-fonte do plugin C
      src/                    # mosquitto_plugin.c, authorize.c, schema_validator.c, response_time_tester.c
      include/                # Headers (.h)
      config/                 # mosquitto.conf, schemas.json, acl.json, userData.json
      docs/                   # Documentação do plugin
      tests/                  # Scripts de teste
    infra/                    # Infraestrutura Docker do Mosquitto
      docker-compose.yml      # container: mosquitto-plugin, portas 1883/9001
      Dockerfile
      entrypoint.sh
      migrate_to_redis.py
    brokertimetest/           # App Node.js para teste de latência broker↔cliente
    BaseTeoricaConsentManager/ # Base teórica do Consent Manager
  docs/                       # Diagramas de arquitetura (Mermaid)
  docker-compose.yml          # Orquestrador unificado — inclui todos os serviços via include:
  ccws-relay.js               # Dois relays TCP WSL: 44655→44653 (HTTPS) e 44654→44652 (HTTP)
  proxy-win.js                # Proxy Windows: localhost:8090 -> WSL IP:8090 (KrakenD)
  proxy-wsl.js                # Proxy WSL: 0.0.0.0:8091 -> localhost:8090 (Docker KrakenD)
```

---

## Fluxo geral do sistema

### Gateway Externo (dispositivos remotos)
```
Dispositivo remoto (app, TV, celular)
    ↓ HTTP (porta 44643)
  krakend-external       [plugin consent-validator intercepta]
    ↓ proxy direto (HTTPS :44655)
  ccws-relay.js (WSL)    [relay TCP transparente]
    ↓ HTTPS :44653
  CCWS (porta 44653)     ← API TV 3.0 (Windows, nativo)
    ↓ publica/assina MQTT
  Mosquitto + Plugin C   ← valida ACL, consentimento (Redis) e schema
    ↓
  AoP (porta 8080)       ← renderiza a interface do receptor
    ↓
  Browser / Display
```

### Gateway Interno (comunicação confiável entre serviços)
```
Serviço interno
    ↓ HTTP (porta 44642)
  krakend-internal       [sem plugin — sem overhead de TLS/validação]
    ↓ proxy direto (HTTP :44654)
  ccws-relay.js (WSL)    [relay TCP transparente]
    ↓ HTTP :44652
  CCWS (porta 44652)     ← API TV 3.0 (Windows, nativo)
```

> **Nota:** o plugin `consent-validator` é um HTTP server plugin — intercepta **todas** as requisições antes do roteamento do `krakend-external` e as encaminha diretamente ao CCWS. O middleware Node.js (portas 3000/3001) existe mas não está sendo chamado pelo fluxo atual — o plugin faz proxy direto.

---

## Infraestrutura

### Redis (`redis/docker-compose.yml`)
- `redis:7-alpine`, porta `6379`, persistência AOF
- `redis-commander` na porta `8081` (UI web)
- Usa `ginga_net` como `external: true` — a rede agora é criada pelo `docker-compose.yml` da raiz

### KrakenD External (`krakenD_external/docker-compose.yml`)
- `devopsfaith/krakend:2.7`, container `krakend-external`, porta **`44643`**
- Plugin Go `consent-validator` intercepta **todas** as requisições — faz proxy direto ao CCWS via `host.docker.internal:44655` (relay HTTPS)
- `allow_insecure_connections: true` — cert self-signed do CCWS
- `extra_hosts: host.docker.internal:172.27.0.1` (fixo — gateway do bridge Docker)
- Monta `./plugins:/etc/krakend/plugins`

### KrakenD Internal (`krakenD_internal/docker-compose.yml`)
- `devopsfaith/krakend:2.7`, container `krakend-internal`, porta **`44642`**
- Sem plugin — comunicação confiável sem overhead de validação
- `allow_insecure_connections: false` — backend HTTP puro
- Backend de cada endpoint aponta para `http://host.docker.internal:44654` (relay HTTP)

### Middleware Externo (`middleware/docker-compose.yml`)
Sobe dois containers:

**`validation-middleware`** (porta `3000`):
- `POST /validate` — valida JWT (secret/issuer via env)
- `GET /openapi.json` — gera spec OpenAPI 3.0 lendo `krakenD_external/krakend.json` (volume readonly)
- `GET /health` — health check
- `ignoreExpiration: true` para compatibilidade com CCWS

**`swagger-ui`** (porta `8085`):
- Consome `http://localhost:3000/openapi.json`
- Acessar em: `http://localhost:8085`

### Middleware Interno (`middleware_internal/docker-compose.yml`)
Sobe dois containers:

**`middleware-internal`** (porta `3001`):
- Mesma base do middleware externo, sem JWT_SECRET/JWT_ISSUER
- `GET /openapi.json` — gera spec OpenAPI 3.0 lendo `krakenD_internal/krakend.json` (volume readonly)

**`swagger-ui-internal`** (porta `8086`):
- Consome `http://localhost:3001/openapi.json`
- Acessar em: `http://localhost:8086`

### Mosquitto Plugin (`mosquitto_plugin/infra/docker-compose.yml`)
- Mosquitto 2.0.22, portas `1883` e `9001`
- Plugin C: ACL + Consentimento + Schema Validation via Redis

---

## Scripts de proxy/relay (raiz)

| Script | Onde rodar | Função | Necessário? |
|---|---|---|---|
| `proxy-win.js` | Windows (Node.js) | Escuta `localhost:8090`, repassa para WSL IP:8091 | Apenas **sem** `networkingMode=mirrored` |
| `proxy-wsl.js` | WSL | Escuta `0.0.0.0:8091`, repassa para Docker `localhost:8090` | Apenas **sem** `networkingMode=mirrored` |
| `ccws-relay.js` | WSL | Dois relays TCP: `44655→44653` (HTTPS, externo) e `44654→44652` (HTTP, interno) | **Sempre necessário** |

> **Por que o relay?** Docker corre dentro do WSL numa rede bridge isolada. Ele enxerga o WSL host via IP do gateway (`172.27.0.1`), não o Windows diretamente. O `ccws-relay.js` escuta no WSL e retransmite os bytes para `localhost:4465x` — que aponta para o Windows. É um tubo TCP transparente, sem interpretar o protocolo. O CCWS no Windows precisa escutar em **duas portas**: `44653` (HTTPS, para o gateway externo) e `44652` (HTTP, para o gateway interno).

---

## Cenário alternativo: sem `networkingMode=mirrored`

Se o desenvolvedor **não** usar mirrored networking no WSL (`~/.wslconfig`), os dois proxies são necessários e os IPs mudam a cada boot.

### Diferenças em relação ao cenário mirrored

| | Com mirrored | Sem mirrored |
|---|---|---|
| KrakenDs acessíveis no Windows | `localhost:44643` e `localhost:44642` direto | Via `proxy-win.js` → `proxy-wsl.js` |
| Portas KrakenD | 44643 (externo) e 44642 (interno) | Idem, mas sem conflito com svchost |
| IPs estáveis | Sim | Não — mudam a cada boot |
| `extra_hosts` no docker-compose | `172.27.0.1` (fixo) | Gateway Docker (verificar a cada boot) |

### Passos extras necessários

**1. Descobrir o IP atual do WSL** (no Windows, a cada boot):
```bash
wsl -- bash -c "hostname -I | awk '{print $1}'"
```

**2. Atualizar `proxy-win.js`** com o IP obtido:
```js
const WSL_IP = '<IP_DO_WSL>';  // ex: 10.21.104.75
```

**3. Verificar gateway Docker** e atualizar `krakenD_external/docker-compose.yml` e `krakenD_internal/docker-compose.yml`:
```bash
wsl -- bash -c "docker network inspect ginga_net | grep Gateway"
# Atualizar extra_hosts: host.docker.internal:<GATEWAY> nos dois arquivos
```

**4. Subir os proxies** (além da ordem normal):
```bash
# WSL — antes do KrakenD
wsl -- bash -c "node /mnt/d/ProjCEFET/aop_infra/proxy-wsl.js &>/tmp/proxy-wsl.log & disown"

# Windows — terminal separado
node D:\ProjCEFET\aop_infra\proxy-win.js
```

**5. KrakenDs usam portas 44643 e 44642** — não conflitam com svchost neste cenário.

> **Recomendação:** usar `networkingMode=mirrored` elimina toda essa complexidade. Adicionar ao `~/.wslconfig`:
> ```ini
> [wsl2]
> networkingMode=mirrored
> ```
> Reiniciar WSL: `wsl --shutdown` e reabrir terminal.

---

## Rede compartilhada: `ginga_net`

- Criada pelo `docker-compose.yml` da **raiz** (com `ipam` fixo)
- Todos os demais declaram `external: true`
- Hostnames: `redis-auth`, `krakend-external`, `krakend-internal`, `mosquitto-plugin`, `validation-middleware`, `middleware-internal`
- **Subnet fixo: `172.27.0.0/16`, gateway `172.27.0.1`** — definido via `ipam` no `docker-compose.yml` da raiz para que o `extra_hosts` do KrakenD nunca precise ser alterado
- Se precisar recriar a rede: `docker network rm ginga_net` e subir novamente via `docker compose up -d`

---

## Ordem de subida

### Orquestrador unificado (recomendado)

```bash
# Stack base (sem Mosquitto)
wsl bash -c "cd /mnt/d/ProjCEFET/aop_infra && docker compose up -d"

# Com Mosquitto
wsl bash -c "cd /mnt/d/ProjCEFET/aop_infra && docker compose --profile mqtt up -d"
```

O `docker-compose.yml` da raiz orquestra via `include:`:
1. `redis/docker-compose.yml` — Redis + redis-commander
2. `middleware/docker-compose.yml` — validation-middleware + swagger-ui (externo)
3. `middleware_internal/docker-compose.yml` — middleware-internal + swagger-ui-internal
4. `krakenD_external/docker-compose.yml` — krakend-external
5. `krakenD_internal/docker-compose.yml` — krakend-internal
6. Serviço `redis-seed` integrado — popula Redis com ACL/usuários de `mosquitto_plugin/plugin/config/`
7. `mosquitto` via `--profile mqtt` — opcional

Antes de subir, iniciar o relay no WSL:
```bash
wsl bash -c "node /mnt/d/ProjCEFET/aop_infra/ccws-relay.js &>/tmp/ccws-relay.log & disown"
```

### Script PowerShell (alternativa)

```powershell
# Padrao (com networkingMode=mirrored)
.\start.ps1

# Com Mosquitto
.\start.ps1 -Mosquitto

# Sem networkingMode=mirrored (sobe proxy-win + proxy-wsl automaticamente)
.\start.ps1 -Proxies

# Tudo
.\start.ps1 -Proxies -Mosquitto
```

### Verificar saúde do stack
```bash
# Containers rodando
wsl -- bash -c "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Relays escutando
wsl -- bash -c "ss -tlnp | grep -E '44654|44655'"

# Teste end-to-end (aguardar ~10s para CCWS inicializar)
curl http://localhost:44643/health   # gateway externo
curl http://localhost:44642/health   # gateway interno
```

---

## Simetria de segurança

| Plano | Porteiro | Tecnologia |
|---|---|---|
| MQTT | Mosquitto Plugin | C + hiredis + Redis |
| HTTP | KrakenD + Middleware | Go (plugin) + Node.js |
| Dados compartilhados | Redis | ACL, consentimento, perfis |

---

## Decisões técnicas

| Decisão | Motivo |
|---|---|
| Um `docker-compose.yml` por serviço + orquestrador na raiz | Permite subir serviços individualmente ou tudo de uma vez |
| Rede `ginga_net` criada pelo `docker-compose.yml` da raiz | Centraliza o `ipam` (subnet/gateway fixos) — redis e demais usam `external: true` |
| Dois gateways KrakenD (externo + interno) | Separar tráfego externo (validação de consentimento via plugin) do interno (confiável, sem overhead) |
| Plugin Go no gateway externo apenas | Gateway interno não precisa recompilar plugin para mudanças de validação |
| `ccws-relay.js` com dois relays (HTTPS + HTTP) | CCWS expõe portas distintas para cada tipo de cliente |
| `ignoreExpiration: true` no middleware | Compatibilidade com CCWS (exp check comentado) |
| Token sem "Bearer " no Authorization | Bug no CCWS — `jwt.decode` recebe header completo |
| `allow_insecure_connections: true` no externo | Cert self-signed no CCWS para dev |
| `extra_hosts` no docker-compose dos KrakenDs | `host.docker.internal` não resolve no Docker via WSL — IP fixado manualmente com o **gateway do bridge Docker** (não o IP do Windows) |
| KrakenDs nas portas 44643/44642 | Portas convenientes que não conflitam com svchost.exe |
| `proxy-win.js` e `proxy-wsl.js` não usados | `networkingMode=mirrored` no WSL espelha portas Docker diretamente para `localhost` no Windows |
| `redis-seed` no `docker-compose.yml` da raiz | Elimina necessidade de script externo para popular o Redis |

---

## Próximos passos

- [x] Criar middleware de validação Node.js
- [x] Desenvolver HTTP Server Plugin Go
- [x] Configurar endpoints no `krakenD_external/krakend.json`
- [x] Compilar e testar o plugin (fluxo completo validado — 200 com token válido, 401 sem/inválido)
- [x] Inicializar repositório Git (raiz: aop_infra, remote: github.com/luiscrjr/aop_infra)
- [x] Separar KrakenD em gateway externo (com plugin) e interno (sem plugin)
- [x] Adicionar middleware_internal com Swagger para o gateway interno
- [x] Criar `docker-compose.yml` unificado na raiz com `include:` e `redis-seed`
- [ ] Adicionar mais endpoints ao KrakenD
- [ ] Expandir validações no middleware (consentimento, rate limit)
- [ ] Atualizar `start.ps1` para refletir a nova estrutura de dois gateways
