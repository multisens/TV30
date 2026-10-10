---
title: Troubleshooting
nav_order: 8
---

# Troubleshooting

## Porta presa: `failed to bind host port ... address already in use`

Triagem, nesta ordem (caso real: portas 3000/3001 presas por um segundo
daemon Docker via snap):

```bash
# 1. quem esta com a porta?
sudo ss -ltnp | grep -E '3000|3001'

# 2. e um container deste daemon?
sudo docker ps -a --format '{{.Names}}\t{{.Ports}}' | grep 3001
#    -> apareceu: remova-o (docker rm -f <nome>) ou faca down no projeto dono.

# 3. ss mostra docker-proxy mas o docker ps -a vem vazio?
#    Ha OUTRO daemon Docker na maquina (snap ou Docker Desktop):
ps -ef | grep dockerd | grep -v grep
#    -> dois dockerd = o dono da porta e o outro daemon.
#       snap:    sudo snap stop docker --disable  (ou snap remove --purge docker)
#       Desktop: docker context ls / encerrar o Desktop
#    -> snap ja removido mas o processo sobrevive orfao: sudo kill <pid do
#       dockerd com --data-root=/var/snap/...>

# 4. um daemon so e mesmo assim a porta persiste: docker-proxy orfao.
#    sudo kill -9 <pids dos docker-proxy do ss> e suba de novo.
```

**Nunca use `kill` no dockerd do sistema** (`/usr/bin/dockerd -H fd://`) —
o systemd o religa e o socket pode ficar dessincronizado
(`/var/run/docker.sock: no such file or directory`). Sempre:

```bash
sudo systemctl reset-failed docker.socket docker.service
sudo systemctl restart docker.socket docker.service
```

O one-shot `preflight` do compose imprime, antes da subida, quem esta
segurando cada porta do stack — se a subida falhar por bind, a causa ja
esta nomeada no inicio do log.

### `preflight`: "a porta 44642 esta ocupada (-)" com a stack de pé

Até 02/10/2026, um segundo `docker compose up -d` com a stack já de pé parava
no preflight com essa mensagem. O container do preflight não tem
`CAP_SYS_PTRACE`, então o `netstat` dele não enxerga que o dono da 44642 é o
`docker-proxy` e mostra `-`. O `scripts/preflight.sh` atual reconhece o
`docker-proxy` pela linha de comando. Em clone antigo, atualize o
repositório. Se a mensagem continuar, há um processo nativo na 44642:
confira com `sudo ss -ltnp | grep 44642`.

## Redis não fica saudável e o tv3ws ou a borda não sobem

O antigo container de carga `redis-seed`, que rodava `pip install redis` na partida e falhava sem rede, não existe mais. Desde a consolidação do armazenamento (fase 3), a carga inicial vem na própria imagem `tv30-redis`: o seed é gerado no build (estágio `seedgen` do `infra/redis/Dockerfile`, em Python só com a biblioteca padrão) e aplicado pelo `infra/redis/entrypoint.sh` com `redis-cli --pipe`. A partida não instala nada nem precisa de rede.

O healthcheck do `redis` só passa depois da carga (chave `seed:done`, testada a cada 2 s, até 30 vezes; `infra/redis/docker-compose.yml`). O `tv3ws` e o `edgegateway` dependem dele com `condition: service_healthy`; o broker não depende do Redis. Para ver em que ponto a carga está: `docker logs redis`, que registra `[redis] aplicando carga inicial (redis-cli --pipe)...` e `[redis] carga concluida`, ou `[redis] carga ja aplicada (seed:done presente) — mantida`.

O seed sai do template `infra/user-files-template/userData.json` no build. Uma mudança no template só entra com a imagem reconstruída e, mesmo assim, só num volume `redis_data` que ainda não tenha `seed:done`: o entrypoint não reaplica a carga num volume já semeado.

## WSL2 + Docker

### `localhost:8080` dá timeout no Windows host

**Causa típica:** `~/.wslconfig` com `networkingMode=mirrored`. Mirrored + Docker tem problemas de NAT/iptables que impedem o host de alcançar as portas dos containers.

**Fix:**

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
```

Depois:

```powershell
wsl --shutdown
```

E reabra a distribuição. Verifique:

```powershell
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 8080 }
```

### Containers caem após período sem uso

**Causa:** WSL2 desligava a VM por idle timeout, derrubando os containers.

**Fix:** acrescente no `~/.wslconfig`:

```ini
vmIdleTimeout=86400000   # 24h
```

E mantenha um processo leve rodando no WSL (qualquer terminal aberto).

### Portas não voltam após `docker compose down`

**Sintoma:** `localhost:XXXX` continua respondendo "connection reset" mesmo após os containers pararem.

**Fix:**

```powershell
wsl --shutdown
```

E suba a stack de novo.

---

## CRLF em scripts shell

### `exec /entrypoint.sh: no such file or directory`

**Causa:** o arquivo foi commitado com `\r\n` (CRLF). O shebang `#!/bin/sh\r` fica inválido.

**Fix:**

1. Converta o arquivo:
   ```bash
   dos2unix infra/dockerfiles/entrypoint-user-files.sh
   ```

2. Force LF nesse tipo de arquivo via `.gitattributes` na raiz:
   ```
   *.sh   text eol=lf
   ```

3. Rebuild a imagem.

---

## Inspecionar estado do sistema

```bash
# Redis
docker exec redis redis-cli SMEMBERS users:index
docker exec redis redis-cli HGETALL user:user_xxx
docker exec redis redis-cli GET session:current-user

# MQTT
docker exec mqtt-broker mosquitto_sub -t '#' -v

# Logs
docker logs aop --tail 50
docker logs tv3ws --tail 50
docker logs mqtt-broker --tail 50
```

Redis Commander: a porta de host é dinâmica. `docker port redis 18081` mostra qual é, e a UI fica em `http://localhost:<porta>/`. A UI exige login: usuário `admin` e senha `tv30-redis-admin` por padrão, ou os valores de `REDIS_COMMANDER_USER`/`REDIS_COMMANDER_PASSWORD` no `.env` da raiz (D-L1, decidida pelo Luís em 03/10). A conexão com o banco (6379, `redis-cli`) segue sem senha.

## Redis Commander abre sem pedir login, ou o login padrão é recusado

- **Abre direto, sem formulário de login:** a imagem `tv30-redis` foi construída antes de 03/10, ou puxada do Docker Hub antes da publicação das imagens novas, e o entrypoint antigo ignora as variáveis. Reconstrua com `docker compose build redis && docker compose up -d redis`.
- **Login recusado com `admin`/`tv30-redis-admin`:** o `.env` da raiz define outro usuário ou outra senha. Para ver o valor em uso, rode `docker exec redis printenv REDIS_COMMANDER_USER REDIS_COMMANDER_PASSWORD`. Depois de mudar o `.env`, recrie o container com `docker compose up -d redis`, porque o valor só é lido na subida.
