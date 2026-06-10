---
title: Instalação
nav_order: 3
---

# Instalação

## Pré-requisitos

- **Docker + Docker Compose v2**
- **Git** com suporte a submódulos

---

## Linux nativo

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
cd TV30
cp .env.example .env       # ativa profiles "linux" e "mqtt"
docker compose up -d
```

Acesse `http://localhost:8080`.

> **Importante:** sem o `.env` (ou sem `COMPOSE_PROFILES=mqtt,linux` setado de alguma forma), apenas a infra essencial sobe — `aop`, `ccws`, `bcast`, `mosquitto` e `sysctl-init` têm `profiles: ["linux"]` ou `["mqtt"]` no compose e ficam de fora do `up` sem o profile ativo.

---

## Windows + WSL2

### Configuração do WSL2

Edite `~/.wslconfig` no Windows (use o caminho `%USERPROFILE%\.wslconfig`):

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
vmIdleTimeout=86400000
```

**Importante:** **não use** `networkingMode=mirrored`. Mirrored + Docker tem problemas conhecidos de NAT/iptables que impedem o host de alcançar as portas dos containers.

Depois de editar:

```powershell
wsl --shutdown
```

E reabra a distribuição.

### Verificação

```powershell
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 8080 }
```

Deve mostrar `127.0.0.1:8080` em LISTENING.

### Subindo a stack

Dentro do WSL:

```bash
cd /mnt/d/ProjCEFET/TV30   # ou onde clonou
cp .env.example .env       # ativa profiles "linux" e "mqtt"
# (edite .env e defina MQTT_WS_PORT=9003 se a 9001 estiver ocupada no host)
docker compose up -d
```

---

## Configurações via `.env`

O `.env` na raiz controla defaults. Exemplo:

```bash
# Tags Docker
DOCKERHUB_NS=tv30
IMAGE_TAG=latest

# Profile padrão
COMPOSE_PROFILES=mqtt,linux

# Porta WebSocket MQTT no host (default 9001).
# Em Windows com Hyper-V usando 9001/9002, defina:
MQTT_WS_PORT=9003
```

---

## Submódulos

### Clone inicial

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
```

### Atualizar todos para o último commit

```bash
git submodule update --remote
```

### Atualizar apenas um

```bash
git submodule update --remote aop
```

### Status

```bash
git submodule status
```

---

## Próximos passos

- [Modelo de Dados Redis]({{ site.baseurl }}/modelo-redis) — chaves armazenadas
- [Fluxo: Criação de Perfil]({{ site.baseurl }}/fluxo-criacao-perfil) — primeiro test-drive
- [Troubleshooting]({{ site.baseurl }}/troubleshooting) — caso algo dê errado
