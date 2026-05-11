---
title: Modelo de Dados Redis
nav_order: 4
---

# Modelo de Dados Redis

O Redis é a **fonte única de verdade** para estado de sessão e perfis de usuário. O arquivo `userData.json` é apenas seed inicial — o CCWS popula o Redis em `initFromRedis` quando `users:index` está vazio.

UI de inspeção: **[http://localhost:18081](http://localhost:18081)** (Redis Commander).

---

## Chaves de sessão

| Chave | Tipo | Conteúdo |
|-------|------|----------|
| `session:current-user` | STRING | UUID do usuário ativo no momento |
| `session:current-service-id` | STRING | ID do serviço DTV ativo (ex.: `urn:tv30:service:users-test`) |

Essas duas chaves também são publicadas como tópicos MQTT retidos (`aop/currentUser`, `aop/currentService`) para o AoP reagir a mudanças.

---

## Chaves de usuário

### `users:index` (SET)

Index de todos os IDs de usuário existentes.

```
SMEMBERS users:index
1) "c3167a18-5dc5"
2) "user_lote_alice"
3) "user_1778457650050"
...
```

### `user:{id}` (HASH)

Atributos básicos do perfil (conforme **ABNT NBR 25608, Tabela 7**):

| Campo | Tipo | Norma |
|-------|------|-------|
| `id` | UUID | requerido |
| `nickname` | string (até 20 chars) | requerido |
| `avatar` | string SVG inline | opcional |
| `parentalControl` | bool | requerido |
| `maxContentRating` | L/10/12/14/16/18 | requerido **se** `parentalControl=true` |
| `audioLanguage` | RFC 5646 (`pt-BR`, `en`...) | opcional |
| `closedCaptioningLanguage` | RFC 5646 | requerido **se** `closedCaptioning=true` |
| `userInterfaceLanguage` | RFC 5646 | opcional |
| `closedCaptioning` | bool | requerido |
| `closedSigning` | bool | requerido |
| `closedSigningSide` | left/right | requerido **se** `closedSigning=true` (padrão: right) |
| `closedSigningWidth` | int (14–28) | requerido **se** `closedSigning=true` (padrão: 28) |
| `audioDescription` | bool | requerido |
| `dialogEnhancement` | bool | requerido |
| `voiceGuidance` | bool | requerido |

Inspecionar:

```bash
docker exec redis-auth redis-cli HGETALL user:user_1778457650050
```

### `user:{id}:consent` (SET)

Lista de serviços DTV para os quais este usuário concedeu consent. Filtragem em `getUserList` usa este SET — usuários sem consent para o `current-service` não aparecem na listagem com serviço ativo.

```
SMEMBERS user:user_lote_alice:consent
1) "urn:tv30:service:users-test"
2) "urn:tv30:service:webmedia"
```

### `user:{id}:broadcaster-attrs:{serviceContextId}` (HASH)

Atributos extras definidos pela emissora para o usuário, **dentro do contexto de um serviço DTV**. Não interfere nos atributos básicos.

---

## Sincronização entre JSON e Redis

```
userData.json (seed)
        │
        ↓  MQTT aop/users
   CCWS.syncUsersFromFile
        │
        ↓  pipeline SADD/HSET
       Redis
```

- O AoP publica `aop/users <path>` quando algo no JSON muda.
- O CCWS escuta e refaz o seed (sem apagar dados pré-existentes — usa SADD/HSET, não DEL).
- `accessConsent` é **incremental**: consents concedidos fora do JSON sobrevivem a reload.

Quando o usuário cria um perfil pelo form, o CCWS:

1. SADD `users:index` `{userId}`
2. HSET `user:{userId}` `<campos da Tabela 7>`
3. SADD `user:{userId}:consent` `{current-service}` (consent automático — termo LGPD aceito no form)
4. Append no `userData.json` (seed sincronizado para rebuild)
5. Publish `aop/users` (trigger de reload no AoP)
