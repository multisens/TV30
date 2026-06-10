---
title: Arquitetura
nav_order: 2
---

# Arquitetura

## Visão geral

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

**Regra central:** todos os serviços se comunicam via MQTT. Nenhum serviço chama outro diretamente por HTTP internamente.

> **Norma × implementação:** MQTT, os gateways KrakenD e o Redis são decisões de arquitetura deste testbed, **não** exigências da ABNT NBR 25608. A norma especifica os Ginga CC WebServices (CCWS), o modelo de consentimento e os perfis de usuário — não o transporte interno nem a infraestrutura de back-end.

---

## Submódulos

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | [multisens/AOP](https://github.com/multisens/AOP) | Interface do receptor TV 3.0. UI, perfis de usuário, catálogo de apps, camadas de vídeo/gráficos. Node.js, porta **8080** |
| `ccws/` | [multisens/CCWS](https://github.com/multisens/CCWS) | API REST/HTTPS do padrão. JWT, gerenciamento de usuários (Redis), serviços e dispositivos. TypeScript, portas **44652/44653** |
| `infra/` | [multisens/Infra](https://github.com/multisens/Infra) | Redis, KrakenD (externo+interno), Mosquitto + plugin C, middlewares de validação |
| `bcast/` | [multisens/BcastService](https://github.com/multisens/BcastService) | Simula broadcaster. Streaming via FFmpeg, sinalização MQTT. Hospeda apps de serviço |
| `eduplay/` | [motadv/eduplay](https://github.com/motadv/eduplay) | Funcionalidades educacionais |
| `sepe/` | [motadv/se-presentation-engine](https://github.com/motadv/se-presentation-engine) | Sensory Effect Presentation Engine |
| `utils/` | [multisens/TV30-Utils](https://github.com/multisens/TV30-Utils) | Explorador web de tópicos MQTT |

---

## Containers e portas

| Container | Porta(s) | Descrição |
|-----------|----------|-----------|
| `redis` | 6379 | Estado de sessão + usuários |
| `redis-commander` | 18081 | UI de inspeção do Redis |
| `mosquitto` | 1883, `${MQTT_WS_PORT:-9001}` | MQTT broker + plugin C ACL |
| `krakend-external` | 44643 | Gateway externo com consent-validator (Go) |
| `krakend-internal` | 44642 | Gateway interno, sem overhead |
| `validation-middleware` | 3000, 8085 | Middleware externo + Swagger |
| `middleware-internal` | 3001, 8086 | Middleware interno + Swagger |
| `ccws` | 44652, 44653 | TV 3.0 WebServices (HTTP, HTTPS) |
| `aop` | 8080 | Interface do receptor |
| `bcast` | 8081 | Broadcaster + módulos de apps de serviço |

---

## Apps de serviço (padrão webmedia)

Apps são **módulos** dentro do container `bcast`, não containers separados. Padrão:

```
bcast/src/modules/<nome>/
├── index.ts        # implementa ServiceInterface (router próprio + EJS)
├── app.ejs         # view principal
└── companion/      # assets, JS auxiliar
```

Reaproveitam o cliente MQTT do bcast — não criam nova conexão nem novo container. Exemplos atuais: `webmedia`, `users-test`, `uff`, `eduplay`.

---

## Decisões arquiteturais

| Decisão | Motivo |
|---------|--------|
| Docker| Um único caminho de deploy. |
| Monorepo com submódulos | Cada componente tem ciclo de vida e CI independentes |
| MQTT como único canal interno | Desacoplamento total entre serviços |
| Estado de usuários em Redis | Consistência cross-instance. `userData.json` é só seed inicial |
| Apps de serviço como módulos do bcast | Um único container serve todos (sem duplicar MQTT/CORS/ACL) |
| Dois gateways KrakenD | Externo valida consent; interno é confiável e sem overhead |
| Avatares como SVG inline | Sem necessidade de servir arquivos PNG; armazenados no campo `avatar` do hash do user |

---

## CI/CD

Cada submódulo (aop, bcast, ccws, infra) tem workflow `.github/workflows/bump-tv30-pointer.yml` que dispara em push na `main` e atualiza automaticamente o ponteiro do submódulo no repo TV30 (via PAT `TV30_REPO_TOKEN`).

Cada submódulo também faz build+push da própria imagem Docker (`tv30/<componente>:latest`) no Docker Hub.
