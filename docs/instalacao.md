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

> **Importante:** sem o `.env` (ou sem `COMPOSE_PROFILES=mqtt,linux` setado de alguma forma), apenas a infra essencial sobe — `aop`, `tv3ws`, `bcast`, `mosquitto` e `sysctl-init` têm `profiles: ["linux"]` ou `["mqtt"]` no compose e ficam de fora do `up` sem o profile ativo.

### Descoberta SSDP (opcional)

Para que outro aparelho da rede encontre o receptor por SSDP (C.3.4), suba o container `tv3ws-ssdp`, que anuncia em rede do host. A descoberta só é suportada em Linux nativo com Docker Engine (decisão do Joel, informada pelo Luís em 04/10); nesse ambiente, o teste com um segundo aparelho ainda não foi feito. No `.env` da raiz:

```bash
COMPOSE_PROFILES=mqtt,linux,ssdp
SSDP_ADVERTISE_HOST=192.168.0.12   # IP desta máquina na rede local
#SSDP_INTERFACE=wlan0              # só se a interface escolhida sozinha estiver errada
```

Depois, `docker compose up -d`, e libere a UDP 1900 e a TCP 44642 no firewall. Sem o perfil `ssdp`, nada é anunciado, e o cliente chega pelo IP (`http://<IP>:44642/manifest`). O passo a passo da verificação, com um segundo aparelho, está em [Verificação: descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao).

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

> **Descoberta SSDP no WSL2:** o perfil `ssdp` sobe, mas o anúncio não sai da máquina. Ele chega ao próprio Windows e não chega aos outros aparelhos da rede (medido em 03 e 04/10 com um anunciante descartável no mesmo arranjo, [Verificação: descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao)). O Docker Desktop, que também roda o Docker numa VM, fica fora do suporte (não medido). Nesses ambientes, o cliente chega ao receptor pelo IP, sem a etapa de descoberta.

---

## Configurações via `.env`

O `.env` na raiz controla defaults. Exemplo:

```bash
# Tags Docker
DOCKERHUB_NS=tv30
IMAGE_TAG=latest

# Profile padrão (Linux nativo com descoberta SSDP: mqtt,linux,ssdp)
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

> **Clone antigo (anterior ao renome `ccws` → `tv3ws`):** o `git pull` não propaga renome de submódulo para um clone que já existe — o `ccws/` continua lá e o `tv3ws/` não fica registrado como submódulo inicializado (`git submodule status` mostra `-` na frente). Corrija com
>
> ```bash
> git submodule sync --recursive && git submodule update --init --recursive
> rm -rf ccws    # sobra do nome antigo (antes, confira que nao ha trabalho local nela)
> ```
>
> ou clone de novo.

> **URL SSH do bcast:** o `.gitmodules` aponta o submódulo `bcast` para `git@github.com:multisens/BcastService.git`. Sem chave SSH cadastrada no GitHub, o clone desse submódulo falha (a troca da URL ainda não foi decidida).

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
- [Criação de perfil (em Modelo de Dados Redis)]({{ site.baseurl }}/modelo-redis) — primeiro test-drive, seção "Sincronização entre JSON e Redis"
- [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local) — infra em containers e um módulo com `npm run dev`
- [Troubleshooting]({{ site.baseurl }}/troubleshooting) — caso algo dê errado
