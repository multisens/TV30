---
title: Modelo de Dados Redis
nav_order: 4
---

# Modelo de Dados Redis

O Redis guarda o estado de sessão, os perfis de usuário e as credenciais. Ele **não** é fonte única de verdade: parte do estado também vive em memória nos serviços (lista de serviços e usuários no AoP, serviço corrente no tv3ws). O `userData.json` é só a carga inicial: a imagem do Redis a aplica uma vez, no banco vazio (`seed:done`). Até a rodada de 05/10, o tv3ws também re-sincronizava os perfis a partir do arquivo (`initFromRedis`, quando `users:index` estava vazio, e a cada `aop/users`); isso saiu com a D-0510-5.

Redis, borda e mensageria são decisões de implementação deste testbed, não da ABNT NBR 25608. O *consent* destas chaves é a visibilidade do perfil por serviço, e não o consentimento da seção 8.8 da norma.

UI de inspeção: Redis Commander, em porta dinâmica do host — `docker port redis 18081` mostra qual. A UI exige login: usuário `admin` e senha `tv30-redis-admin` por padrão, trocáveis por `REDIS_COMMANDER_USER`/`REDIS_COMMANDER_PASSWORD` no `.env` da raiz (decisão D-L1, tomada pelo Luís em 03/10; ver [README](../README.md#interface-administrativa-do-redis)). A senha vale só para a UI: a conexão com o banco (6379) segue sem senha.

---

## Quem escreve e quem lê cada família (P5)

O P5, decidido antes da rodada de 05/10, pede um dono por família de chave. Na reunião de 05/10, o Joel apontou que os perfis tinham três escritores (a carga inicial, o tv3ws e a plataforma). A correção (D-0510-5) pôs a plataforma como dona dos perfis; a escolha da plataforma foi feita na implementação, pelo critério do P5. Na mesma rodada, a C.6.8 foi para a borda (D-0510-2), e a borda passou a escrever `bind-context:*`. Estado pelo código em 10/10:

| Família | Escreve | Lê |
|---|---|---|
| `session:current-user`, `session:current-service-id` | tv3ws: espelho dos tópicos `aop/currentUser` e `aop/currentService`; o `session:current-user` também na C.6.14.4 | tv3ws; a borda lê o `session:current-service-id` (bind-token e C.6.8); o AoP o lê na criação de perfil |
| `session:current-service` | tv3ws (`src/core.ts`; a API C.6.3.1 do tv3ws responde da memória, não deste hash) | a borda, na C.6.8.3 |
| `users:index`, `user:{id}`, `user:{id}:consent` | **AoP** (gestor de perfis: criação, despejo e `lastAccess`). A carga inicial só escreve no banco vazio | AoP; tv3ws, só leitura desde 05/10 |
| `user:{id}:broadcaster-attrs:{scid}` | tv3ws (C.6.14.5) e AoP (apaga no despejo): **dois escritores**, ponto em aberto (E4 de [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes)) | tv3ws |
| `client:{id}`, `clients:authorized`, `clients:blocked` | tv3ws (`src/modules/auth-manager/manager.ts`) | tv3ws; a borda lê `clients:blocked` |
| `origins:associated` | AoP (`src/core.js`) | borda; tv3ws (`classifyClient`) |
| `bind-context:{serviceId}` | **borda**, na C.6.8.2 e na C.6.8.4, desde 05/10 (antes, o tv3ws) | borda |
| `remote-devices:index`, `remote-devices:class:{classe}`, `remote-device:{handle}` | tv3ws: espelho dos dispositivos remotos conectados, limpo no boot | só o próprio tv3ws, na limpeza do boot |
| `seed:done` | entrypoint do container `redis`, depois da carga inicial | o mesmo entrypoint |

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
| `client:{id}` | HASH | tv3ws (autorização, C.6.1) | `class` (`local-associated`, `local-autonomous` ou `non-local`), `refreshToken`, `accessToken` — o vínculo cliente↔token. Fica também depois de um bloqueio |
| `clients:authorized` | SET | tv3ws | Ids de cliente autorizados pelo espectador (D-0510-4, reunião de 05/10 com o Joel). O `/tv3/token` só emite para quem está aqui. Disjunto de `clients:blocked`: autorizar e bloquear são transações (`MULTI`) que tiram o id de um conjunto e o põem no outro. No boot, o tv3ws inclui aqui os `client:{id}` anteriores ao conjunto que não estão bloqueados. Base da futura tela de histórico de autorizações (C.4.2.2), que não existe |
| `clients:blocked` | SET | tv3ws | Ids de cliente bloqueados pelo usuário (C.4.2.2); a borda responde 107 a token de cliente nesta lista |
| `origins:associated` | HASH | AoP (P1) | `origem → id do serviço corrente` (o valor de `aop/currentService`, o mesmo de `session:current-service-id`, ou `current-service` sem serviço; não é o `serviceContextId`, que é constante no tv3ws) das aplicações de emissora lançadas; base provisória para reconhecer o cliente local associado (lacuna sem decisão: a C.4.1.7 sugere porta de origem) |
| `bind-context:{serviceId}` | LIST | borda (`POST /tv3/bind-context`, C.6.8.2, respondida pelo plugin `tv30-auth` desde a reunião de 05/10; antes, o tv3ws) | Uma entrada JSON por chave registrada pela emissora: `{"alg":"RS256","key":"<string recebida>","registeredAt":<ms>}` |

### `bind-context:{serviceId}` (LIST)

Chaves de validação de bind-token registradas pela emissora (C.6.8). O receptor **não emite** bind-token: guarda o par (algoritmo, chave) e valida os tokens que a emissora assina.

- `{serviceId}` é o valor de `session:current-service-id` no momento do registro (a C.6.8.2 registra para o serviço selecionado). O registro sem serviço corrente responde erro 300 (norma silente — decisão de implementação).
- `alg` ∈ {`HS256`, `HS512`, `RS256`, `RS512`} (C.4.1.4.8). Sem duplicatas: o mesmo par alg+key não entra duas vezes.
- A emissora pode ter **várias** chaves (rotação): qualquer uma da lista valida (C.4.1.3). Nas rotas `token+bind`, o bind-token só vale contra as chaves do **serviço corrente** — isolamento entre emissoras. A exceção é a própria C.6.8.3 (`GET /tv3/bind-context`), que procura, entre as chaves de **todos** os serviços (`SCAN bind-context:*`), os que validam o token e os lista.
- `DELETE /tv3/bind-context` (cabeçalho `key`, C.6.8.4) remove a chave da lista do serviço corrente; sucesso mesmo se não existir, e também sem serviço corrente (não há lista de que remover).
- Codificação da `key` (norma silente — decisão de implementação): HS = bytes UTF-8 do segredo, sem trim (duplicata só se o texto for idêntico); RS = PEM (o texto começa por `-----BEGIN` e o rótulo é `PUBLIC KEY`, `RSA PUBLIC KEY`, `RSA PRIVATE KEY` ou `PRIVATE KEY`) ou base64 de DER (SPKI ou PKCS#1); chave privada recebida tem a pública derivada. Módulo RSA pequeno demais para o algoritmo dá 101. Desde 05/10, o registro e a validação usam a mesma função de leitura de chave, no plugin da borda (`infra/edgegateway/plugin/keys.go`); até ali, o tv3ws tinha uma cópia das regras, mantida igual por teste cruzado.
- A leitura e a gravação do registro não são atômicas (LRANGE seguido de RPUSH): dois registros simultâneos da mesma chave podem gravar uma duplicata, o que não muda o resultado.

```bash
docker exec redis redis-cli LRANGE bind-context:urn:tv30:service:users-test 0 -1
```

---

## Carga inicial e escrita dos perfis

```
userData.json ──(build da imagem redis: emit_seed.py)──> seed.resp
                                                            │
                    entrypoint do redis, só sem seed:done ──┘──> Redis

gestor de perfis do AoP ──(criação, despejo, lastAccess)──> Redis
tv3ws ──(só leitura de perfis)──> Redis
```

- **Carga inicial.** O `infra/redis/emit_seed.py` gera o seed a partir do `userData.json` no build da imagem, e o `infra/redis/entrypoint.sh` o aplica uma vez, no banco vazio (sem `seed:done`). Depois disso, o arquivo não é mais lido.
- **Sem re-sincronização** (D-0510-5, reunião de 05/10 com o Joel). Até 05/10, o tv3ws refazia a carga a partir do arquivo no boot (com `users:index` vazio) e a cada mensagem em `aop/users` (`syncUsersFromFile`). Os dois caminhos saíram, e o `USER_DATA_FILE` deixou de ser exigido pelo tv3ws.

Quem grava os perfis é o **gestor de perfis do AoP** (`aop/src/modules/profile-manager/service.js`), direto no Redis. A antiga rota `POST /tv3/users` do tv3ws não existe mais. Na criação pelo form (`createProfile`):

1. Teto de 5 perfis: acima dele, despeja o de último acesso mais antigo (P3), apagando `user:{id}`, `user:{id}:consent` e `user:{id}:broadcaster-attrs:*`
2. SADD `users:index` `{userId}`
3. DEL + HSET `user:{userId}` `<campos da Tabela 7>`, com `lastAccess` igual ao instante da criação
4. SADD `user:{userId}:consent` `{session:current-service-id}` (visibilidade automática para o serviço ativo — termo aceito no form)
5. O AoP recarrega a própria lista de usuários do Redis (`refreshUserData`); o `userData.json` não é alterado

**`lastAccess`** (campo de `user:{id}`, usado pelo despejo). Desde 05/10, só o AoP o grava (`touchLastAccess`), em toda troca de usuário corrente: a feita pela própria plataforma (seletor de perfis) e a que chega pelo tópico `aop/currentUser`, publicada por outro componente (por exemplo, a C.6.14.4 no tv3ws). A gravação é um script Lua que só escreve se o id estiver em `users:index`, para não criar um hash avulso de um perfil inexistente ou despejado. Perfil sem `lastAccess` conta pelo instante embutido no id (`user_<epoch-ms>`). Até 05/10, quem gravava era o tv3ws.

---

## Clientes do Redis e falha

- **tv3ws e AoP** (ioredis; D-0510-6, reunião de 05/10 com o Joel): `maxRetriesPerRequest: 1`, `commandTimeout` de 1500 ms, `connectTimeout` de 2000 ms, fila offline ligada e reconexão contínua (200 ms a 2 s). Comando sem resposta falha, e a rota HTTP responde 404 `{"error":200}` (no tv3ws, `src/util/error.ts`; no AoP, `src/http-error.js`). O log registra `[redis] pronto em ...`, a perda da conexão e o erro. Configuração em `tv3ws/src/redis-client.ts` e `aop/src/redis-options.js`.
- **Borda** (cliente RESP próprio, `infra/edgegateway/plugin/redis.go`): limite de 500 ms por comando (`REDIS_TIMEOUT_MS`), e uma nova tentativa numa conexão nova quando a do pool morreu, menos para o RPUSH que já saiu. Falha na decisão de credencial: em `warn`, passa; em `enforce`, 404 `{"error":200}`. Na C.6.8, que a própria borda responde, 404 `{"error":200}` nos dois modos (a C.6.7.8 e a C.6.7.9 não usam o Redis).
