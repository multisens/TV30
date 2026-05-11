---
title: APIs CCWS
nav_order: 5
---

# APIs CCWS

O CCWS expõe endpoints aderentes à norma **ABNT NBR 25608**. Roteamento interno em `ccws/src/app.ts`. Acesso externo pelo KrakenD-internal (`http://localhost:44642`) e KrakenD-external (`https://localhost:44643`, com validação de consent).

---

## Acesso e versionamento

Todas as requisições passam pelo KrakenD-internal (porta 44642). O KrakenD aplica CORS uniformemente — o CCWS **não** seta headers CORS para evitar duplicação.

Header padrão: `Accept-Version: 2.0` (não obrigatório no MVP).

---

## Endpoints (resumo)

| Método | Endpoint | Descrição | Tabela ABNT |
|--------|----------|-----------|-------------|
| GET | `/health` | Health check | — |
| GET | `/tv3/authorize` | Início do fluxo de autorização | C.6.1 |
| GET | `/tv3/token` | Troca challenge por JWT | C.6.2 |
| GET | `/tv3/current-service` | Info do serviço ativo | C.6.7 |
| GET | `/tv3/current-service/users/current-user` | UUID do usuário atual | C.6.12.1 |
| POST | `/tv3/current-service/users/current-user` | Define usuário corrente | C.6.12.2 |
| POST | `/tv3/current-service/users` | Lista usuários (com filtros) | C.6.14.1 |
| GET | `/tv3/current-service/users/{uuid}` | Atributos do usuário | C.6.14.2 |
| GET | `/tv3/current-service/users/files` | Download de arquivo do user | C.6.15 |
| **POST** | **`/tv3/users`** | **Cria perfil (fora da spec, usado pelo profile-creator do AoP)** | **—** |
| GET | `/tv3/{serviceContextId}/users/{uuid}/broadcaster-attrs` | Atributos da emissora | C.6.16.1 |
| PUT | `/tv3/{serviceContextId}/users/{uuid}/broadcaster-attrs` | Atualiza atributos da emissora | C.6.16.2 |
| POST | `/tv3/remote-device` | Registra dispositivo remoto | C.6.17 |
| GET | `/tv3/remote-device/devices/{classId}` | Lista dispositivos por classe | C.6.18 |
| GET/POST | `/tv3/sensory-effect-renderers[/{id}]` | Renderizadores de efeitos sensoriais | C.6.10 |

---

## `POST /tv3/users` — Criar perfil

Não faz parte da spec ABNT (a norma não define criação de perfil via API). É usado pelo profile-creator do AoP. Mapeamento direto para a **Tabela 7** da norma.

### Request

```http
POST /tv3/users HTTP/1.1
Content-Type: application/json

{
  "nickname": "Diagnóstico",
  "avatar": "<svg>...</svg>",
  "parentalControl": true,
  "maxContentRating": "12",
  "audioLanguage": "pt-BR",
  "closedCaptioningLanguage": "pt-BR",
  "userInterfaceLanguage": "pt-BR",
  "closedCaptioning": true,
  "closedSigning": false,
  "audioDescription": false,
  "dialogEnhancement": false,
  "voiceGuidance": false
}
```

### Validações

- `nickname` requerido, até 20 caracteres
- `maxContentRating` ∈ {L, 10, 12, 14, 16, 18} — requerido se `parentalControl=true`
- `closedSigningWidth` ∈ [14, 28] — se `closedSigning=true`
- `closedSigningSide` ∈ {left, right} — se `closedSigning=true`

### Response (201 Created)

Retorna o objeto do usuário criado, incluindo `id` (`user_{timestamp}`).

### Efeitos colaterais

1. SADD `users:index`
2. HSET `user:{id}` com os campos da Tabela 7
3. **Consent automático** para o `session:current-service-id` (termo LGPD do form é o aceite)
4. Append no `userData.json` (seed)
5. Publish `aop/users` (trigger de reload no AoP)

---

## Filtragem de usuários (`POST /tv3/current-service/users`)

Body suporta expressões de filtro (`and`, `or`, `simpleExpression`):

```json
{
  "or": [
    { "attribute": "parentalControl", "comparator": "eq", "value": "false" },
    {
      "and": [
        { "attribute": "parentalControl", "comparator": "eq", "value": "true" },
        { "attribute": "maxContentRating", "comparator": "gte", "value": "14" }
      ]
    }
  ]
}
```

Comparadores: `eq`, `neq`, `lt`, `lte`, `gt`, `gte`.

**Importante:** quando há `session:current-service-id` ativo, a listagem filtra apenas usuários com `user:{id}:consent` contendo o `current-service`. Sem serviço ativo (boot do AoP / profile-chooser), retorna **todos**.

---

## Encoding especial (no-op)

Alguns endpoints retornam dados binários ou text/plain — KrakenD-internal os marca como `output_encoding: "no-op"` para não tentar parsear JSON:

- `POST /tv3/current-service/users/current-user` (CCWS retorna `text/plain "OK"`)
- `GET /tv3/current-service/users/files` (binário)

Sem esse encoding, KrakenD retorna 500 ao tentar fazer JSON parse.
