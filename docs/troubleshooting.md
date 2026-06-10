---
title: Troubleshooting
nav_order: 8
---

# Troubleshooting

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
docker exec redis-auth redis-cli SMEMBERS users:index
docker exec redis-auth redis-cli HGETALL user:user_xxx
docker exec redis-auth redis-cli GET session:current-user

# MQTT
docker exec mosquitto-plugin mosquitto_sub -t '#' -v

# Logs
docker logs aop --tail 50
docker logs ccws --tail 50
docker logs mosquitto-plugin --tail 50
```

Redis Commander: **http://localhost:18081**
