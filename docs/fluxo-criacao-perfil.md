---
title: Fluxo — Criação de Perfil
nav_order: 6
---

# Fluxo: Criação de Perfil

## Visão geral

```
[Browser/AoP]   ──form submit──→   [CCWS /tv3/users]   ──→   [Redis + JSON]
                                          │
                                          └─MQTT aop/users──→   [AoP recarrega lista]
```

Características do fluxo:

- O AoP **não** mantém estado de usuários — só serve o HTML do form.
- O POST vai direto do browser para o KrakenD-internal → CCWS.
- O Redis é fonte de verdade. O `userData.json` é seed.

---

## Passo a passo

### 1. Usuário abre o form

`GET http://localhost:8080/profile/create` → `aop/src/modules/prf-mngr/index.js` → renderiza `aop/src/views/create-profile.ejs`.

### 2. Form valida e envia

Botão **Avançar** invoca `saveProfile()`:

```js
const CCWS = 'http://' + window.location.hostname + ':44642'; // KrakenD-internal
fetch(CCWS + '/tv3/users', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(newProfile)   // 14 atributos da Tabela 7
});
```

### 3. KrakenD-internal repassa pro CCWS

Endpoint registrado em `infra/krakenD_internal/krakend.linux.json`:

```json
{
  "endpoint": "/tv3/users",
  "method": "POST",
  "input_headers": ["Authorization", "Accept-Version", "Content-Type"],
  "backend": [{ "url_pattern": "/tv3/users", "host": ["http://ccws:44652"] }]
}
```

### 4. CCWS valida e persiste

`ccws/src/modules/user-api/service.ts` → função `createUser()`:

- Valida nickname (até 20 chars), maxContentRating (se parental), closedSigningWidth (14–28), closedSigningSide
- Gera `userId = user_${Date.now()}`
- Lê `session:current-service-id` do Redis
- Persiste:
  ```
  SADD users:index user_xxx
  HSET user:user_xxx <campos da Tabela 7>
  SADD user:user_xxx:consent <current-service>   ← consent automático
  ```
- Faz append no `userData.json`
- Publish MQTT `aop/users <path>`

### 5. AoP recarrega lista

`aop/src/core.js` está subscrito em `aop/users`. Ao receber a mensagem:

```js
function loadUserData() {
    POST  /tv3/current-service/users  body={and:[]}
    forEach user: GET /tv3/current-service/users/{id}
    DATA.users = [...]
}
```

### 6. Browser redireciona

Após o POST retornar 201:

```js
alert('Perfil criado com sucesso!');
window.location.href = '/prfchs';   // profile-chooser
```

O profile-chooser pede `DATA.users` ao AoP (via SSR/render server-side) e o novo perfil aparece.

---

## Onde o termo LGPD vira consent

O checkbox **"Concordo com a coleta..."** do form é validado client-side mas **não vai no payload**. O termo é tratado implicitamente pelo CCWS: quem cria perfil pelo profile-chooser está implicitamente concordando, e o consent é registrado para o serviço ativo.

Se quiser tornar isso explícito (e auditável), envie um campo `accessConsent: ["<service-id>"]` no payload — o CCWS faz merge com o automático.

---

## Conformidade ABNT NBR 25608

O form coleta exclusivamente os atributos da **Tabela 7** (atributos básicos do perfil). Atributos removidos por não constarem na norma:

- ~~`gender`~~ — não existe na Tabela 7
- ~~`isGroup`~~ — não é atributo básico
- ~~`ageRating`~~ — substituído pelo `maxContentRating` correto (condicionado a `parentalControl=true`)

Os campos condicionais respeitam as regras da norma:

| Campo | Aparece quando |
|-------|----------------|
| `maxContentRating` | `parentalControl = true` |
| `closedCaptioningLanguage` | `closedCaptioning = true` |
| `closedSigningSide`, `closedSigningWidth` | `closedSigning = true` |

---

## Navegação por teclado

Conforme ACFR-XX da norma, o form é totalmente navegável por teclas:

| Tecla | Ação |
|-------|------|
| Up/Down ou Left/Right | Move foco entre campos visíveis |
| Left/Right em `<select>` | Cicla opções |
| Left/Right no slider de largura | Ajusta valor (14–28) |
| Enter ou Space | Ativa (toggle checkbox, abrir avatar modal, etc.) |
| Esc | Volta para o profile-chooser |

A lista de stops é recalculada a cada navegação — campos condicionais entram na ordem automaticamente.
