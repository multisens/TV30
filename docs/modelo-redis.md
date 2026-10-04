---
title: Modelo de Dados Redis
nav_order: 4
---

# Modelo de Dados Redis

O Redis guarda o estado de sessão, os perfis de usuário e as credenciais. Ele **não** é fonte única de verdade: parte do estado também vive em memória nos serviços (lista de serviços e usuários no AoP, serviço corrente no tv3ws) e o `userData.json` é a carga inicial — a imagem do Redis aplica a carga na primeira subida (`seed:done`) e o tv3ws re-sincroniza a partir do arquivo em `initFromRedis` (quando `users:index` está vazio) e a cada `aop/users`.

UI de inspeção: Redis Commander, em porta dinâmica do host — `docker port redis 18081` mostra qual. A UI exige login: usuário `admin` e senha `tv30-redis-admin` por padrão, trocáveis por `REDIS_COMMANDER_USER`/`REDIS_COMMANDER_PASSWORD` no `.env` da raiz (decisão D-L1, tomada pelo Luís em 03/10; ver [README](../README.md#interface-administrativa-do-redis)). A senha vale só para a UI: a conexão com o banco (6379) segue sem senha.

---

## Chaves de sessão

| Chave | Tipo | Conteúdo |
|-------|------|----------|
| `session:current-user` | STRING | UUID do usuário ativo no momento |
| `session:current-service-id` | STRING | ID do serviço DTV ativo (ex.: `urn:tv30:service:users-test`) |
| `session:current-service` | HASH | Serviço corrente, gravado pelo tv3ws a cada troca de serviço, com os campos de `GET /tv3/current-service` (`serviceContextId`, `serviceId`, `serviceName`, `transportStreamId`, `originalNetworkId`) |

As duas chaves STRING espelham os tópicos MQTT retidos `aop/currentUser` e `aop/currentService`: o tv3ws as grava ao receber cada mensagem.

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
docker exec redis redis-cli HGETALL user:user_1778457650050
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

## Chaves de credenciais

| Chave | Tipo | Quem escreve | Conteúdo |
|-------|------|--------------|----------|
| `client:{id}` | HASH | tv3ws (autorização, C.6.1) | `class` (`local-associated`, `local-autonomous` ou `non-local`), `refreshToken`, `accessToken` — o vínculo cliente↔token |
| `clients:blocked` | SET | tv3ws | Ids de cliente bloqueados pelo usuário (C.4.2.2); a borda responde 107 a token de cliente nesta lista |
| `origins:associated` | HASH | AoP (P1) | `origem → id do serviço corrente` (o valor de `aop/currentService`, o mesmo de `session:current-service-id`, ou `current-service` sem serviço; não é o `serviceContextId`, que é constante no tv3ws) das aplicações de emissora lançadas; base provisória para reconhecer o cliente local associado (lacuna sem decisão: a C.4.1.7 sugere porta de origem) |
| `bind-context:{serviceId}` | LIST | tv3ws (`POST /tv3/bind-context`, C.6.8.2) | Uma entrada JSON por chave registrada pela emissora: `{"alg":"RS256","key":"<string recebida>","registeredAt":<ms>}` |

### `bind-context:{serviceId}` (LIST)

Chaves de validação de bind-token registradas pela emissora (C.6.8). O receptor **não emite** bind-token: guarda o par (algoritmo, chave) e valida os tokens que a emissora assina.

- `{serviceId}` é o valor de `session:current-service-id` no momento do registro (a C.6.8.2 registra para o serviço selecionado). O registro sem serviço corrente responde erro 300 (norma silente — decisão de implementação).
- `alg` ∈ {`HS256`, `HS512`, `RS256`, `RS512`} (C.4.1.4.8). Sem duplicatas: o mesmo par alg+key não entra duas vezes.
- A emissora pode ter **várias** chaves (rotação): qualquer uma da lista valida (C.4.1.3). O bind-token só vale contra as chaves do **serviço corrente** — isolamento entre emissoras.
- `DELETE /tv3/bind-context` (cabeçalho `key`, C.6.8.4) remove a chave da lista do serviço corrente; sucesso mesmo se não existir, e também sem serviço corrente (não há lista de que remover).
- Codificação da `key` (norma silente — decisão de implementação): HS = bytes UTF-8 do segredo, sem trim (duplicata só se o texto for idêntico); RS = PEM (o texto começa por `-----BEGIN` e o rótulo é `PUBLIC KEY`, `RSA PUBLIC KEY`, `RSA PRIVATE KEY` ou `PRIVATE KEY`) ou base64 de DER (SPKI ou PKCS#1); chave privada recebida tem a pública derivada. Módulo RSA pequeno demais para o algoritmo dá 101. As mesmas regras valem no tv3ws e na borda (teste cruzado).

```bash
docker exec redis redis-cli LRANGE bind-context:urn:tv30:service:users-test 0 -1
```

---

## Sincronização entre JSON e Redis

```
userData.json (seed)
        │
        ↓  MQTT aop/users
   tv3ws.syncUsersFromFile
        │
        ↓  pipeline SADD/HSET
       Redis
```

- O AoP publica `aop/users <path>` quando algo no JSON muda.
- O tv3ws escuta e refaz o seed (sem apagar dados pré-existentes — usa SADD/HSET, não DEL).
- `accessConsent` é **incremental**: consents concedidos fora do JSON sobrevivem a reload.

Quando o usuário cria um perfil pelo form, quem grava é o **gestor de perfis do AoP** (`aop/src/modules/profile-manager/service.js`, `createProfile`) — direto no Redis; a antiga rota `POST /tv3/users` do tv3ws não existe mais:

1. Teto de 5 perfis: acima dele, despeja o de último acesso mais antigo (P3)
2. SADD `users:index` `{userId}`
3. DEL + HSET `user:{userId}` `<campos da Tabela 7>`
4. SADD `user:{userId}:consent` `{session:current-service-id}` (visibilidade automática para o serviço ativo — termo aceito no form)
5. O AoP recarrega a própria lista de usuários do Redis (`loadUserData`); o `userData.json` não é alterado

O *consent* destas chaves é visibilidade de perfil por serviço — não é o consentimento da seção 8.8 da norma.
