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

E reabra a distro. Verifique:

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

## CORS duplicado

### Chrome console: `Multiple values 'Access-Control-Allow-Origin' header`

**Causa:** CCWS e KrakenD-internal estavam setando o header simultaneamente.

**Fix:** o KrakenD é o **único** que aplica CORS (config em `infra/krakenD_internal/krakend.linux.json`, seção `security/cors`). O CCWS não deve setar headers CORS — o middleware `basic.ts` foi limpo.

---

## Perfil criado não aparece no profile-chooser

**Causa:** o `getUserList` filtra por `user:{id}:consent` quando há `session:current-service-id`. Se o user não tem consent para o serviço ativo, fica invisível.

**Fix:**

1. **Automático**: o `createUser` no CCWS já adiciona consent para o `current-service`. Mas para users criados antes desta correção, é manual:
   ```bash
   docker exec redis-auth redis-cli SADD user:{userId}:consent {service-id}
   docker exec mosquitto-plugin mosquitto_pub -t aop/users -m /user-files
   ```

2. Verifique com:
   ```bash
   docker exec redis-auth redis-cli SMEMBERS user:{userId}:consent
   ```

---

## Avatar verde "padrão" aparece em todos os usuários

**Causa:** Redis tinha valores legados (`0.png`, `1.png` etc.) no campo `avatar`. A view do profile-chooser caía no fallback (verde #4d7c5b) ao falhar ao carregar.

**Fix:** force re-sync do JSON pro Redis:

```bash
docker exec mosquitto-plugin mosquitto_pub -t aop/users -m /user-files
```

O `userData.json` atualizado já tem os SVGs corretos.

---

## bcast inacessível via `bcastEntryPackageUrl`

### AoP → bcast: `ECONNREFUSED` no `/graphicsAppProxy`

**Causa:** `bcastEntryPackageUrl` usava `localhost:8081`. `localhost` dentro do container `aop` não resolve para o container `bcast`.

**Fix:** `bcast/src/index.ts` usa o env var `BCAST_HOSTNAME` (default `bcast`, que resolve via DNS interno da `ginga_net`). Definido no `docker-compose.yml`:

```yaml
bcast:
  environment:
    BCAST_HOSTNAME: bcast
```

---

## `Loaded 0 users from CCWS` ao subir

**Causa:** o AoP tenta ler o CCWS antes dele estar pronto.

**Fix:** retry automático já implementado em `aop/src/core.js` (`loadUserData` retenta até 5x com backoff 2s, 4s, 6s, 8s, 10s).

---

## Token JWT rejeitado

### `JsonWebTokenError: jwt malformed`

**Causa conhecida:** o middleware espera o token **sem** o prefixo `"Bearer "`. Bug histórico do CCWS.

**Fix temporário:** enviar `Authorization: <token>` (sem Bearer). A intenção é alinhar com RFC 6750 quando o middleware for retrabalhado.

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
