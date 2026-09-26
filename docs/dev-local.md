---
title: Desenvolvimento com serviço no host
nav_order: 9
---

# Template: infra em containers + o SEU serviço rodando no host

Cenário da reunião de 21/09: quem está implementando uma funcionalidade num
dos serviços (tv3ws, aop, bcast, ou um componente novo) sobe **só a infra
básica** em containers e roda o serviço em desenvolvimento **no host**, via
`npm run dev` — sem rebuildar imagem a cada mudança.

## A infra básica (3 containers)

```bash
EDGE_VARIANT=windows docker compose --profile mqtt up -d redis mosquitto edgegateway
```

- `redis` publica `6379` no host → o serviço local usa `REDIS_HOST=localhost`.
- `mqtt-broker` publica `1883` → `MQTT_HOST=localhost`.
- `edgegateway` com `EDGE_VARIANT=windows` aponta os backends para
  `host.docker.internal` — que em Linux resolve para o host (o compose já
  mapeia via `host-gateway`). Apesar do nome, a variante serve para
  **qualquer** cenário com backend no host.

Validação automática da ponte containers→host: `./scripts/test-dev-host.sh`.

## Combinações

| Quero desenvolver | Sobe em container | Rodo no host |
|---|---|---|
| tv3ws | infra básica | `HTTP_PORT=44654 HTTPS_PORT=44655 REDIS_HOST=localhost MQTT_HOST=localhost USER_DATA_FILE=... npm run dev` (em `tv3ws/`) |
| aop | infra básica + tv3ws | `PORT=8080 MQTT_HOST=localhost REDIS_HOST=localhost USER_DATA_PATH=./user-files npm run dev` (em `aop/`) |
| bcast | infra básica + tv3ws + aop | `PORT=8081 MQTT_HOST=localhost npm run dev` (em `bcast/`) |
| componente novo | infra básica (+ o que ele consome) | seu processo, falando `localhost:6379`/`localhost:1883`/`localhost:44642` |

Regras do arranjo:

1. **Quem está no host fala com containers por `localhost:<porta publicada>`**
   (6379, 1883, 44642/44643, 8080, 8081).
2. **Quem está em container fala com o host por `host.docker.internal`** —
   só a borda precisa disso (via `EDGE_VARIANT=windows`); os demais serviços
   se falam por MQTT/Redis, nunca por HTTP direto.
3. As portas do serviço local (44654/44655 pro tv3ws) têm que casar com o
   que a variante do edge espera — estão em `infra/edgegateway/routes.json`
   (`backends.*.windows`).
4. Componente novo em container deve tratar a **própria resiliência**
   (morre-inteiro: se um processo interno cair, o container cai) — o padrão
   dos containers da stack, ver `infra/edgegateway/entrypoint.sh`.
