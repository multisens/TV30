---
title: Modelo de Dados Redis
parent: Como funciona
nav_order: 3
---

# Modelo de Dados Redis

O Redis guarda o estado de sessão, os perfis de usuário e as credenciais. Ele **não** é fonte única de verdade: parte do estado também vive em memória nos serviços (lista de serviços e usuários no AoP, serviço corrente no tv3ws). O `userData.json` é só a carga inicial: a imagem do Redis a aplica uma vez, no banco vazio (`seed:done`). Até a rodada de 05/10, o tv3ws também re-sincronizava os perfis a partir do arquivo (`initFromRedis`, quando `users:index` estava vazio, e a cada `aop/users`); isso saiu com a D-0510-5.

Redis, borda e mensageria são decisões de implementação deste testbed, não da ABNT NBR 25608. O *consent* destas chaves é a visibilidade do perfil por serviço, e não o consentimento da seção 8.8 da norma.

UI de inspeção: Redis Commander, em porta dinâmica do host — `docker port redis 18081` mostra qual. A UI exige login: usuário `admin` e senha `tv30-redis-admin` por padrão, trocáveis por `REDIS_COMMANDER_USER`/`REDIS_COMMANDER_PASSWORD` no `.env` da raiz (decisão D-L1, tomada pelo Luís em 03/10; ver [README](https://github.com/multisens/TV30/blob/main/README.md#interface-administrativa-do-redis)). A senha vale só para a UI: a conexão com o banco (6379) segue sem senha.

**Esquema nas escritas (P4, decisão do Luís em 10/10).** Toda escrita que o código do projeto faz nas famílias abaixo passa por uma **função do próprio Redis**, que confere o esquema e grava de forma atômica. Dado fora do esquema volta como erro `TV30ESQUEMA`, e nada é gravado. Uma função só de leitura, a auditoria, aponta as chaves fora do esquema. A escrita manual pelo `redis-cli` ou pelo commander continua possível. Como funciona, como inspecionar, como rodar a auditoria e como gravar à mão: seção *Esquema nas escritas*, logo abaixo da tabela de donos.

---

## Quem escreve e quem lê cada família (P5)

O P5, decidido antes da rodada de 05/10, pede um dono por família de chave. Na reunião de 05/10, o Joel apontou que os perfis tinham três escritores (a carga inicial, o tv3ws e a plataforma). A correção (D-0510-5) pôs a plataforma como dona dos perfis; a escolha da plataforma foi feita na implementação, pelo critério do P5. Na mesma rodada, a C.6.8 foi para a borda (D-0510-2), e a borda passou a escrever `bind-context:*`. Estado pelo código em 10/10:

| Família | Escreve | Função que grava (P4) | Lê |
|---|---|---|---|
| `session:current-user`, `session:current-service-id` | tv3ws: espelho dos tópicos `aop/currentUser` e `aop/currentService`; o `session:current-user` também na C.6.14.4 | `tv30_sessao_usuario`, `tv30_sessao_servico_id` | tv3ws; a borda lê o `session:current-service-id` (bind-token e C.6.8); o AoP o lê na criação de perfil |
| `session:current-service` | tv3ws (`src/core.ts`; a API C.6.3.1 do tv3ws responde da memória, não deste hash) | `tv30_sessao_servico` | a borda, na C.6.8.3 |
| `users:index`, `user:{id}`, `user:{id}:consent` | **AoP** (gestor de perfis: criação, despejo e `lastAccess`). A carga inicial só escreve no banco vazio | `tv30_perfil_grava`, `tv30_perfil_ultimo_acesso`, `tv30_perfil_remove` | AoP; tv3ws, só leitura desde 05/10 |
| `user:{id}:broadcaster-attrs:{scid}` | tv3ws (C.6.14.5) e AoP (apaga no despejo): **dois escritores**, ponto em aberto (E4 de [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes)) | `tv30_atributos_emissora`; no despejo, `tv30_perfil_remove` | tv3ws |
| `client:{id}`, `clients:authorized`, `clients:blocked` | tv3ws (`src/modules/auth-manager/manager.ts`) | `tv30_cliente_grava`, `tv30_cliente_autoriza`, `tv30_cliente_bloqueia`, `tv30_cliente_inclui_autorizado` | tv3ws; a borda lê `clients:blocked` |
| `origins:associated` | AoP (`src/core.js`) | `tv30_origem_registra`, `tv30_origem_remove`, `tv30_origens_limpa` | borda; tv3ws (`classifyClient`) |
| `bind-context:{serviceId}` | **borda**, na C.6.8.2 e na C.6.8.4, desde 05/10 (antes, o tv3ws) | `tv30_bind_registra`, `tv30_bind_remove` | borda |
| `remote-devices:index`, `remote-devices:class:{classe}`, `remote-device:{handle}` | tv3ws: espelho dos dispositivos remotos conectados, limpo no boot | nenhuma: fora do alcance do P4, escrita direta | só o próprio tv3ws, na limpeza do boot |
| `seed:done` | entrypoint do container `redis`, depois da carga inicial | nenhuma: fora do alcance do P4 (marca de controle) | o mesmo entrypoint e o healthcheck |

---

## Esquema nas escritas: funções do Redis e auditoria (P4)

**Decisão do Luís em 10/10, "Funções + auditoria".** Toda escrita do código do projeto (tv3ws, AoP, borda e carga inicial) nas famílias do alcance passa por uma função de uma biblioteca do próprio Redis (Redis Functions: `FUNCTION LOAD`, `FCALL`). A função confere o esquema e grava de forma atômica, inclusive as invariantes entre chaves. A conexão fica como antes: usuário `default`, sem senha e com escrita (A1, decidida em 03/10). Não há usuário administrativo nem ACL novo. Redis, funções e esquema são decisões de implementação deste testbed; a norma não fala de armazenamento. O esquema só cita a norma onde a regra vem dela (a Tabela 7 nos perfis, por exemplo).

### Onde mora o esquema e como ele é carregado

- **Fonte única dos esquemas:** `infra/redis/esquema.json`, um arquivo de dados versionado. Ele declara cada família (chave, tipo, dono, regra de cada campo, membro ou item, e a fonte de cada regra), as invariantes, as funções e o que fica fora do alcance. A biblioteca e os testes leem o mesmo arquivo.
- **Biblioteca:** `infra/redis/funcoes.lua`, montada por `infra/redis/biblioteca.sh` (cabeçalho `#!lua name=tv30` + o `esquema.json` embutido + o corpo). Ela interpreta as regras, tem uma função por operação de escrita e a auditoria.
- **Carga:** o `infra/redis/entrypoint.sh` carrega a biblioteca **a cada partida**, com `FUNCTION LOAD REPLACE`, **antes** da carga inicial, que também passa pelas funções. O Redis guarda as funções no AOF; o `REPLACE` garante que vale a versão da imagem, não a que ficou no volume. Sem a biblioteca, o container encerra com a mensagem do Redis no log. O healthcheck só fica saudável depois da biblioteca e da carga.
- **No build:** o `infra/redis/confere-imagem.sh` carrega a biblioteca num Redis temporário, aplica a carga inicial e exige a auditoria vazia. Um `userData.json` fora do esquema não vira imagem.

Detalhes, a lista de funções com argumentos e como mudar uma regra: `infra/redis/README.md`.

### Esquema de cada família

| Família | Dono | Tipo | Esquema (resumo; o completo está no `esquema.json`) |
|---|---|---|---|
| `session:current-user` | tv3ws | STRING | texto de até 64 caracteres, vazio vale "sem usuário" (o mesmo teto de `aop/currentUser` no `schemas.json` do broker) |
| `session:current-service-id` | tv3ws | STRING | texto de até 256 caracteres, vazio vale "sem serviço" (o mesmo teto de `aop/currentService` no broker) |
| `session:current-service` | tv3ws | HASH | exatamente os cinco campos da Tabela C.8; `serviceId` inteiro em decimal ou vazio |
| `users:index` | AoP | SET | ids de perfil (`idPerfil`: 1 a 64 caracteres, sem `:`) |
| `user:{id}` | AoP | HASH | Tabela 7 mais `lastAccess`: obrigatórios e condicionais da tabela, booleanos `"true"`/`"false"`, `nickname` de 1 a 20 caracteres, `maxContentRating` em L/10/12/14/16/18, idiomas em IETF RFC 5646, `closedSigningWidth` de 14 a 28; o campo `id` igual ao da chave; nenhum campo fora da lista |
| `user:{id}:consent` | AoP | SET | ids de serviço (1 a 256 caracteres) |
| `user:{id}:broadcaster-attrs:{scid}` | tv3ws grava; AoP apaga no despejo (E4) | HASH | nome e valor não vazios, sem os básicos que a C.6.14.5 proíbe redefinir (`id`, `nickname`, `parentalControl`, `maxContentRating`), até 20 MB de nomes mais valores (P3/10.3.3) |
| `client:{id}` | tv3ws | HASH | `class` em `local-associated`/`local-autonomous`/`non-local` e `refreshToken`, obrigatórios; `accessToken` opcional; nada além |
| `clients:authorized`, `clients:blocked` | tv3ws | SET | ids de cliente não vazios |
| `origins:associated` | AoP | HASH | campo = origem como o navegador a manda no `Origin` (esquema `http`/`https` e host em minúsculas, porta só se não for a padrão, sem caminho); valor = id de serviço |
| `bind-context:{serviceId}` | borda | LIST | cada item é um objeto JSON `{alg, key, registeredAt}` e nada mais: `alg` em HS256/HS512/RS256/RS512, `key` não vazia e `registeredAt` inteiro |

**Invariantes entre chaves** (conferidas pelas funções e pela auditoria):

- `perfil-indexado`: todo membro de `users:index` tem o hash `user:{id}`, e todo hash `user:{id}` tem o id em `users:index` (decisão do Luís em 10/10). `tv30_perfil_grava` grava os dois juntos, e `tv30_perfil_remove` tira os dois juntos.
- `perfil-dependentes`: `user:{id}:consent` e `user:{id}:broadcaster-attrs:*` só existem para id em `users:index`. Invariante derivada do código: a criação grava perfil e visibilidade juntos, e o despejo apaga as quatro famílias juntas.
- `clientes-disjuntos`: nenhum id fica nos dois conjuntos de clientes (D-0510-4). Autorizar e bloquear são uma função cada; antes eram transações `MULTI`.
- `autorizado-tem-registro`: todo membro de `clients:authorized` tem o hash `client:{id}`. Invariante derivada do código: a autorização grava os dois juntos.

**Registro que já existe.** Quando a função só acrescenta campos a um hash existente (o `lastAccess`, o token de um cliente), ela confere os campos que grava. O que já estava gravado fora do esquema não trava a escrita; a auditoria o mostra. Registro novo ou regravado é conferido inteiro, de modo que nenhuma função cria um registro incompleto.

### Erro de esquema

O erro diz a função, a chave, o campo e o motivo, e nada é gravado:

```
TV30ESQUEMA tv30_perfil_grava: user:u2 campo parentalControl: deve ser "true" ou "false" (veio "False")
TV30ESQUEMA tv30_origem_registra: origins:associated nome de campo: host deve estar em minusculas (como o navegador o manda no Origin) (veio "http://X.apps.localhost")
```

Para o serviço, a recusa é **defeito do serviço**. O erro sobe como uma falha do Redis: a rota HTTP responde 404 `{"error":200}`, com a mensagem no `description` e no log (no tv3ws, `src/util/error.ts`; no AoP, `src/http-error.js`). Um handler MQTT só loga. Na borda, o `description` diz `escrita recusada pelo esquema do Redis (...)`. O gestor de perfis do AoP confere antes o que vem do formulário (inclusive os idiomas e a lista de visibilidade) e responde 400 com a mensagem, sem chegar à função.

### Como inspecionar

```bash
docker exec redis redis-cli FCALL_RO tv30_versao 0                 # versao do esquema carregado
docker exec redis redis-cli FUNCTION LIST LIBRARYNAME tv30         # funcoes e flags
docker logs redis 2>&1 | grep -E 'biblioteca|carga'                 # carregou nesta partida?
```

### Auditoria

```bash
docker exec redis redis-cli FCALL_RO tv30_auditoria 0
```

A auditoria é só de leitura (flag `no-writes`). Ela percorre as chaves dos prefixos do alcance (`session:`, `users:`, `user:`, `clients:`, `client:`, `origins:`, `bind-context:`) e devolve uma entrada `[chave, familia, motivo]` por problema: chave sem família (por exemplo, a antiga `user:{id}:profile`), tipo errado, campo, membro ou item fora da regra e cada invariante quebrada. **Vazia = tudo no esquema.** O `scripts/test-auth.sh` exige a auditoria vazia no fim, depois de desfazer o que semeou, e avisa no começo se já havia achados. O `scripts/test-consolidacao.sh` a mostra.

**Volume de antes do P4.** Dados gravados antes das funções podem estar fora do esquema, e a auditoria os aponta. Dois casos foram vistos em 10/10:

- a carga inicial antiga gravava os booleanos como `"False"`/`"True"` (o `str()` do Python). O AoP grava `"false"`/`"true"`, e o filtro da C.6.14.1 compara texto, então `closedCaptioning eq false` não achava os perfis da carga. A carga nova grava `"false"`;
- no volume da stack em 10/10, a auditoria (rodada sobre uma cópia) apontou `user:abc-123`, um hash só com `lastAccess`, de 25/09: o hash fantasma que o `lastAccess` avulso de antes de 05/10 criava.

Para começar limpo, use `docker compose down -v`, que apaga o volume e com ele os perfis criados. A outra saída é corrigir ou apagar as chaves apontadas.

### Gravar à mão para depurar

Para gravar como o serviço gravaria, use a função (`numkeys` é sempre 0):

```bash
docker exec redis redis-cli FCALL tv30_sessao_servico_id 0 urn:tv30:service:users-test
docker exec redis redis-cli FCALL tv30_origem_registra 0 http://users-test.apps.localhost:8080 urn:tv30:service:users-test
docker exec redis redis-cli FCALL tv30_cliente_bloqueia 0 <clientid>
```

A escrita direta (`SET`, `HSET`, `SADD`...) pelo `redis-cli` ou pelo commander **continua possível** e não passa pelo esquema. Depois de uma, rode a auditoria. Uma escrita manual que cumpra o esquema não se distingue da do código, e o risco da A1 continua.

### Por que não há bloqueio por ACL

A sugestão anterior era deixar o `default` só com leitura e `FCALL`, e um usuário administrativo para o resto. Num teste em `redis:7-alpine` (7.4.11), em 10/10, o Redis aplicou o ACL de quem chama **dentro** da função. Com o `default` sem `@write` e com `+fcall`, a função recebe:

```
ERR ACL failure in script: User default has no permissions to run the 'set' command
```

No Redis puro, não há como bloquear a escrita direta e liberar só a escrita pela função. As garantias ficaram em duas partes:

- **Teste estático:** falha se algum serviço gravar direto numa família do alcance fora do adaptador das funções (`tv3ws/src/redis-funcoes.ts`, `aop/src/redis-funcoes.js`, `fcall` em `infra/edgegateway/plugin/redis.go` e `FCALL` na carga inicial). Roda no `npm test` do tv3ws e do AoP, no `go test` da borda (inclusive no build da imagem dela) e em `infra/redis/test/run.sh estatico`.
- **Auditoria:** mostra o que entrou por fora.

Os testes das funções num Redis real ficam em `infra/redis/test/run.sh`, nos modos `funcoes`, `contrato` e `imagem`.

### O que fica fora do alcance, e por quê

- `remote-devices:index`, `remote-devices:class:{classe}`, `remote-device:{handle}`: espelho dos dispositivos remotos conectados (WebSockets vivos), limpo no boot e lido só pelo próprio tv3ws. Não entrou no alcance da decisão de 10/10, e o tv3ws o grava direto (`src/modules/remotedevice-manager/manager.ts`, o único arquivo com escrita direta permitida; o teste estático exige que ele não cite chave do alcance).
- `seed:done`: marca de controle da carga inicial.
- `tv30:{componente}:exemplo`: chave do exemplo do template de componente, gravada só por `scripts/test-template.sh` e `scripts/test-dev-host.sh`.

### Onde o código não segue a norma (registrado no `esquema.json`, em `divergencias`)

- A Tabela 7 pede "UUID string" no `id`. O AoP gera `user_<epoch-ms>`, e a carga inicial traz `c3167a18-5dc5`, que o bcast/webmedia também cita. O esquema exige só `idPerfil`. PENDENTE (Joel): adotar UUID ou registrar a exceção.
- A Tabela 7 pede "file path" no `avatar`. O AoP e a carga gravam o SVG em linha, e o esquema aceita qualquer texto.

---

## Chaves de sessão

| Chave | Tipo | Conteúdo |
|-------|------|----------|
| `session:current-user` | STRING | Id do perfil ativo no momento, o mesmo de `aop/currentUser` (ex.: `user_1760000000000`; vazio = sem usuário). Até 64 caracteres, o teto do tópico |
| `session:current-service-id` | STRING | ID do serviço DTV ativo (ex.: `urn:tv30:service:users-test`; vazio = sem serviço). Até 256 caracteres, o teto do tópico |
| `session:current-service` | HASH | Serviço corrente, regravado inteiro pelo tv3ws a cada troca de serviço (`tv30_sessao_servico`), com os campos de `GET /tv3/current-service` (`serviceContextId`, `serviceId`, `serviceName`, `transportStreamId`, `originalNetworkId`). O `serviceId` vai como inteiro em decimal ou vazio (Tabela C.8; até 10/10 ia o texto que viesse em `aop/services`) |

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

Atributos básicos do perfil (conforme **ABNT NBR 25608, Tabela 7**) mais o `lastAccess` do testbed. Tudo é gravado como texto; a coluna da direita é o que a função `tv30_perfil_grava` exige (P4, `infra/redis/esquema.json`):

| Campo | Tabela 7 | Esquema no Redis (P4) |
|-------|----------|-----------------------|
| `id` | UUID, requerido | obrigatório, igual ao `{id}` da chave, 1 a 64 caracteres sem `:` (não exige UUID: ver *Onde o código não segue a norma*) |
| `nickname` | string até 20 caracteres, requerido | obrigatório, 1 a 20 caracteres (contados como caracteres, não bytes) |
| `avatar` | file path, opcional | opcional, qualquer texto (o testbed grava SVG em linha) |
| `parentalControl` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `maxContentRating` | valores do país, requerido só se `parentalControl = true` | `L`, `10`, `12`, `14`, `16` ou `18`; obrigatório com `parentalControl` `"true"` |
| `audioLanguage` | RFC 5646 (`pt-BR`, `en`...), opcional | opcional, formato IETF RFC 5646 |
| `closedCaptioningLanguage` | RFC 5646, opcional (aplicável se `closedCaptioning = true`) | opcional, formato IETF RFC 5646 (até 10/10 esta página dizia "requerido"; a Tabela 7 diz *optional*) |
| `userInterfaceLanguage` | RFC 5646, opcional | opcional, formato IETF RFC 5646 |
| `closedCaptioning` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `closedSigning` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `closedSigningSide` | left/right, aplicável se `closedSigning = true` (padrão: right) | `left` ou `right`; obrigatório com `closedSigning` `"true"` |
| `closedSigningWidth` | inteiro de 14 a 28, aplicável se `closedSigning = true` (padrão: 28) | inteiro de 14 a 28; obrigatório com `closedSigning` `"true"` |
| `audioDescription` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `dialogEnhancement` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `voiceGuidance` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `lastAccess` | (não é da norma) | opcional, inteiro (instante em ms; despejo P3) |

Nenhum outro campo entra no hash.

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
| `clients:authorized` | SET | tv3ws | Ids de cliente autorizados pelo espectador (D-0510-4, reunião de 05/10 com o Joel). O `/tv3/token` só emite para quem está aqui. Disjunto de `clients:blocked`: autorizar e bloquear são uma função cada (`tv30_cliente_autoriza` e `tv30_cliente_bloqueia`, P4; antes, transações `MULTI`), que tira o id de um conjunto e o põe no outro. No boot, o tv3ws inclui aqui os `client:{id}` anteriores ao conjunto que não estão bloqueados (`tv30_cliente_inclui_autorizado`). Base da futura tela de histórico de autorizações (C.4.2.2), que não existe |
| `clients:blocked` | SET | tv3ws | Ids de cliente bloqueados pelo usuário (C.4.2.2); a borda responde 107 a token de cliente nesta lista |
| `origins:associated` | HASH | AoP (P1; `aop/src/core.js`) | `origem → id do serviço corrente` (o valor de `aop/currentService`, o mesmo de `session:current-service-id`, ou `current-service` sem serviço; não é o `serviceContextId`, que é constante no tv3ws) das aplicações de emissora lançadas. Desde o P1.3 (decisão do Luís em 10/10), a origem é a **própria** da aplicação, `http://<rótulo>.<APPS_DOMAIN>:<AOP_PUBLIC_PORT>` (padrão `http://<rótulo>.apps.localhost:8080`; porta 80 omitida), em que a camada gráfica a abre e que o navegador manda no `Origin` das chamadas dela; o rótulo sai do `appId` da BALD (`aop/src/app-hosts.js`), fixo por app desde 11/10 (o users-test grava `http://urn-tv30-app-users-test.apps.localhost:8080`), e a mesma entrada volta a cada lançamento, também depois de o bcast reiniciar. O caminho da URL, com o prefixo `/graphicsAppProxy` desde 11/10, não entra na origem. O AoP grava a entrada ao lançar a aplicação, apaga ao encerrá-la ou trocá-la, e limpa a chave no boot. O caminho antigo `/graphicsAppProxy`, no host do AoP, não grava nada: até 11/10 servia a aplicação na origem do AoP, e desde 11/10 redireciona (302) para o host dela. Até 10/10, a origem gravada era a do alvo do proxy, `http://bcast:8081`, que nenhum navegador manda. Base para reconhecer o cliente local associado (L1, risco do `Origin` forjado aceito pelo Luís em 03/10; a C.4.1.7 sugere porta de origem e deixa o mecanismo à implementação) |
| `bind-context:{serviceId}` | LIST | borda (`POST /tv3/bind-context`, C.6.8.2, respondida pelo plugin `tv30-auth` desde a reunião de 05/10; antes, o tv3ws) | Uma entrada JSON por chave registrada pela emissora: `{"alg":"RS256","key":"<string recebida>","registeredAt":<ms>}` |

### `bind-context:{serviceId}` (LIST)

Chaves de validação de bind-token registradas pela emissora (C.6.8). O receptor **não emite** bind-token: guarda o par (algoritmo, chave) e valida os tokens que a emissora assina.

- `{serviceId}` é o valor de `session:current-service-id` no momento do registro (a C.6.8.2 registra para o serviço selecionado). O registro sem serviço corrente responde erro 300 (norma silente — decisão de implementação).
- `alg` ∈ {`HS256`, `HS512`, `RS256`, `RS512`} (C.4.1.4.8). Sem duplicatas: o mesmo par alg+key não entra duas vezes.
- A emissora pode ter **várias** chaves (rotação): qualquer uma da lista valida (C.4.1.3). Nas rotas `token+bind`, o bind-token só vale contra as chaves do **serviço corrente** — isolamento entre emissoras. A exceção é a própria C.6.8.3 (`GET /tv3/bind-context`), que procura, entre as chaves de **todos** os serviços (`SCAN bind-context:*`), os que validam o token e os lista.
- `DELETE /tv3/bind-context` (cabeçalho `key`, C.6.8.4) remove a chave da lista do serviço corrente; sucesso mesmo se não existir, e também sem serviço corrente (não há lista de que remover).
- Codificação da `key` (norma silente — decisão de implementação): HS = bytes UTF-8 do segredo, sem trim (duplicata só se o texto for idêntico); RS = PEM (o texto começa por `-----BEGIN` e o rótulo é `PUBLIC KEY`, `RSA PUBLIC KEY`, `RSA PRIVATE KEY` ou `PRIVATE KEY`) ou base64 de DER (SPKI ou PKCS#1); chave privada recebida tem a pública derivada. Módulo RSA pequeno demais para o algoritmo dá 101. Desde 05/10, o registro e a validação usam a mesma função de leitura de chave, no plugin da borda (`infra/edgegateway/plugin/keys.go`); até ali, o tv3ws tinha uma cópia das regras, mantida igual por teste cruzado.
- A gravação é pela função `tv30_bind_registra` (um `RPUSH`), e a revogação pela `tv30_bind_remove` (um `LREM 0`), ambas desde o P4. A função confere a entrada (um objeto JSON `{alg, key, registeredAt}` e nada mais, com `alg` entre os quatro, `key` não vazia e `registeredAt` inteiro) e o `serviceId`.
- A leitura e a gravação do registro não são atômicas (LRANGE seguido da função de registro): dois registros simultâneos da mesma chave podem gravar uma duplicata, o que não muda o resultado. A detecção de duplicata fica na borda porque ela compara chaves RSA pela chave pública, coisa que a função não faz.

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

- **Carga inicial.** O `infra/redis/emit_seed.py` gera o seed a partir do `userData.json` no build da imagem, e o `infra/redis/entrypoint.sh` o aplica uma vez, no banco vazio (sem `seed:done`). Depois disso, o arquivo não é mais lido. Desde o P4, cada perfil vira uma chamada `FCALL tv30_perfil_grava` (antes, `SADD`/`DEL`/`HSET`/`SADD` avulsos), com os booleanos em `"true"`/`"false"` (antes, `"True"`/`"False"`). Um perfil do template fora do esquema faz o build da imagem falhar (`confere-imagem.sh`). O `migrate_to_redis.py` da imagem do broker, que só serve à depuração manual, usa a mesma chamada.
- **Sem re-sincronização** (D-0510-5, reunião de 05/10 com o Joel). Até 05/10, o tv3ws refazia a carga a partir do arquivo no boot (com `users:index` vazio) e a cada mensagem em `aop/users` (`syncUsersFromFile`). Os dois caminhos saíram, e o `USER_DATA_FILE` deixou de ser exigido pelo tv3ws.

Quem grava os perfis é o **gestor de perfis do AoP** (`aop/src/modules/profile-manager/service.js`), pelas funções do Redis (adaptador `aop/src/redis-funcoes.js`, P4). A antiga rota `POST /tv3/users` do tv3ws não existe mais. Na criação pelo form (`createProfile`):

1. O dado do form é conferido: nickname, classificação, Libras e, desde o P4, os idiomas (IETF RFC 5646) e a lista de visibilidade (ids de serviço). Dado inválido dá 400, com a mensagem.
2. Teto de 5 perfis: acima dele, despeja o de último acesso mais antigo (P3) com `tv30_perfil_remove`, que apaga numa operação só `users:index`, `user:{id}`, `user:{id}:consent` e todos os `user:{id}:broadcaster-attrs:*`. Antes eram `SREM`, `DEL`, `KEYS` e `DEL` avulsos.
3. `tv30_perfil_grava` numa operação só: `users:index` recebe o `{userId}`, `user:{userId}` é regravado com os campos da Tabela 7 (com `lastAccess` igual ao instante da criação) e `user:{userId}:consent` recebe o `{session:current-service-id}` (visibilidade automática para o serviço ativo — termo aceito no form). Antes, `SADD`, `DEL`, `HSET` e `SADD` avulsos.
4. O AoP recarrega a própria lista de usuários do Redis (`refreshUserData`); o `userData.json` não é alterado.

**`lastAccess`** (campo de `user:{id}`, usado pelo despejo). Desde 05/10, só o AoP o grava (`touchLastAccess`), em toda troca de usuário corrente: a feita pela própria plataforma (seletor de perfis) e a que chega pelo tópico `aop/currentUser`, publicada por outro componente (por exemplo, a C.6.14.4 no tv3ws). A gravação é a função `tv30_perfil_ultimo_acesso` (antes, um script Lua do AoP), que só escreve se o id estiver em `users:index`, para não criar um hash avulso de um perfil inexistente ou despejado. Perfil sem `lastAccess` conta pelo instante embutido no id (`user_<epoch-ms>`). Até 05/10, quem gravava era o tv3ws.

---

## Clientes do Redis e falha

- **tv3ws e AoP** (ioredis; D-0510-6, reunião de 05/10 com o Joel): `maxRetriesPerRequest: 1`, `commandTimeout` de 1500 ms, `connectTimeout` de 2000 ms, fila offline ligada e reconexão contínua (200 ms a 2 s). Comando sem resposta falha, e a rota HTTP responde 404 `{"error":200}` (no tv3ws, `src/util/error.ts`; no AoP, `src/http-error.js`). O log registra `[redis] pronto em ...`, a perda da conexão e o erro. Configuração em `tv3ws/src/redis-client.ts` e `aop/src/redis-options.js`.
- **Borda** (cliente RESP próprio, `infra/edgegateway/plugin/redis.go`): limite de 500 ms por comando (`REDIS_TIMEOUT_MS`), e uma nova tentativa numa conexão nova quando a do pool morreu, menos para o registro de bind-context (`tv30_bind_registra`) que já saiu. Falha na decisão de credencial: em `warn`, passa; em `enforce`, 404 `{"error":200}`. Na C.6.8, que a própria borda responde, 404 `{"error":200}` nos dois modos (a C.6.7.8 e a C.6.7.9 não usam o Redis).
- **Recusa de esquema (P4)**: erro `TV30ESQUEMA` de uma função. Os três serviços a tratam como as outras falhas do Redis (404 `{"error":200}`, com a mensagem no `description` e no log), porque ela é defeito de quem grava. O que o cliente da API manda errado é recusado antes, pelo próprio serviço, com o código da norma (101, 105...).
