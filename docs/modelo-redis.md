---
title: Modelo de Dados Redis
parent: Como funciona
nav_order: 3
---

# Modelo de Dados Redis

O Redis guarda o estado de sessão, os perfis de usuário e as credenciais. Ele **não** é fonte única de verdade: parte do estado também vive em memória nos serviços (lista de serviços e usuários no AoP; serviço corrente, cache dos clientes autorizados e WebSockets dos dispositivos remotos no tv3ws) e nos tópicos retidos do broker, de que as chaves STRING de `session:*` são espelho. O `userData.json` é só a carga inicial: a imagem do Redis a aplica uma vez, no banco vazio (`seed:done`).

Redis, borda e mensageria são decisões de implementação deste testbed, não da ABNT NBR 25608. O *consent* destas chaves é a visibilidade do perfil por serviço, e não o consentimento da seção 8.8 da norma.

**Porta e acesso.** A 6379 é publicada só em `127.0.0.1`: aberta à rede, um aparelho gravaria na lista de associados ou nas chaves de bind e contornaria a borda. O Redis fica sem senha e sem ACL; a escrita direta fora das funções que validam (abaixo) é vedada por convenção. Os serviços em container usam a `ginga_net`; os que rodam no host (dev-host) usam `127.0.0.1`.

UI de inspeção: Redis Commander, em porta dinâmica do host — `docker port redis 18081` mostra qual. A UI exige login: usuário `admin` e senha `tv30-redis-admin` por padrão, trocáveis por `REDIS_COMMANDER_USER`/`REDIS_COMMANDER_PASSWORD` no `.env` da raiz. A senha vale só para a UI: a conexão com o banco (6379) segue sem senha. A morte do commander derruba o container do Redis inteiro, e o `restart` o traz de volta (`infra/redis/entrypoint.sh`).

**Id do perfil em UUID.** O esquema exige o id do perfil no formato textual da IETF RFC 9562 (8-4-4-4-12 dígitos hexadecimais), em minúsculas, como pede a Tabela 7 ("UUID string"). O UUID é estrito: a versão (primeiro dígito do terceiro grupo) tem de ser de 1 a 8, e a variante (primeiro dígito do quarto grupo), a da RFC 9562 (`8`, `9`, `a` ou `b`); o UUID nulo (todo 0) e o máximo (todo f) são recusados, e a mensagem diz qual parte falhou (`motivoUuid`, em `infra/redis/funcoes.lua`). O AoP gera `crypto.randomUUID()` (versão 4), e a carga inicial traz `c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10` (versão 4, variante 9). Um id fora do formato, gravado à mão, fica fora do esquema (seção *Auditoria*, abaixo).

**Avatar como nome de arquivo.** A Tabela 7 define o `avatar` como "Path indicating the file with the graphical representation of the viewer profile" (*file path*, opcional). O esquema exige, quando o campo existe, o nome de um arquivo do diretório de miniaturas (`<USER_DATA_PATH>/thumbs` no AoP, o mesmo `USER_THUMBS` do tv3ws: `user-files/thumbs`, volume dos dois), no formato `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.(svg|png|jpg|jpeg|webp)$`: sem `/` nem `\`, começando por letra ou dígito, com a extensão em minúsculas (tipo `nomeArquivo`, conferido por partes em `motivoNomeArquivo`, `infra/redis/funcoes.lua`). Sem o campo, cada tela mostra o avatar padrão. O AoP grava `<id do perfil>.svg` na criação, e a carga traz `c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10.svg`, com o arquivo em `infra/user-files-template/thumbs/`. O SVG em linha no campo é recusado (`campo avatar: SVG em linha nao serve`). Restringir o caminho a um nome dentro de um diretório é decisão do projeto.

**Esquema nas escritas.** Toda escrita que o código do projeto faz nas famílias abaixo passa por uma **função do próprio Redis**, que confere o esquema e grava de forma atômica. Dado fora do esquema volta como erro `TV30ESQUEMA`, e nada é gravado. São 16 funções de escrita, uma por operação, e duas só de leitura: a auditoria, que aponta as chaves fora do esquema, e a que informa a versão do esquema. A escrita manual pelo `redis-cli` ou pelo commander continua possível. Como funciona, como inspecionar, como rodar a auditoria e como gravar à mão: seção *Esquema nas escritas*, logo abaixo da tabela de donos.

---

## Quem escreve e quem lê cada família

O critério do projeto é um dono por família de chave. Estado pelo código:

| Família | Escreve | Função que grava | Lê |
|---|---|---|---|
| `session:current-user`, `session:current-service-id` | tv3ws: espelho dos tópicos `aop/currentUser` e `aop/currentService`; o `session:current-user` também na C.6.14.4 | `tv30_sessao_usuario`, `tv30_sessao_servico_id` | tv3ws; a borda lê o `session:current-service-id` (bind-token e C.6.8); o AoP o lê na criação de perfil |
| `session:current-service` | tv3ws (`src/core.ts`; a API C.6.3.1 do tv3ws responde da memória, não deste hash). O `serviceContextId` é o `globalServiceId` do serviço; sem serviço selecionado, o hash não é regravado | `tv30_sessao_servico` | a borda, na C.6.8.3 |
| `users:index`, `user:{id}`, `user:{id}:consent` | **AoP** (gestor de perfis: criação, remoção e `lastAccess`). A carga inicial só escreve no banco vazio | `tv30_perfil_grava`, `tv30_perfil_ultimo_acesso`, `tv30_perfil_remove` | AoP; tv3ws, só leitura |
| `user:{id}:broadcaster-attrs:{scid}` | **dois escritores**: o tv3ws grava o conteúdo (C.6.14.5), e o AoP remove a família inteira ao remover o perfil, na mesma função que remove o perfil (atômico, sem chaves órfãs). O `esquema.json` registra os dois e a operação de cada um (campo `escritores`). O `{scid}` é o `globalServiceId` | `tv30_atributos_emissora`; na remoção do perfil, `tv30_perfil_remove` | tv3ws |
| `client:{id}`, `clients:authorized`, `clients:blocked` | tv3ws (`src/modules/auth-manager/manager.ts`) | `tv30_cliente_grava`, `tv30_cliente_autoriza`, `tv30_cliente_bloqueia`, `tv30_cliente_inclui_autorizado` | tv3ws; a borda lê `clients:blocked` e `clients:authorized` |
| `origins:associated` | AoP (`src/core.js`): origem da app -> o serviço que a lançou; sem serviço corrente, a origem não é registrada | `tv30_origem_registra`, `tv30_origem_remove`, `tv30_origens_limpa` | borda, que compara o serviço com o contexto da rota; tv3ws (`classifyClient`) |
| `bind-context:{serviceId}` | **só a borda**, na C.6.8.2 e na C.6.8.4 | `tv30_bind_registra`, `tv30_bind_remove` | só a borda (bind-token e C.6.8.3); a auditoria do esquema (`tv30_auditoria`) também a lê, para conferir o formato |
| `remote-devices:index`, `remote-devices:class:{classe}`, `remote-device:{handle}` | tv3ws: espelho dos dispositivos remotos conectados, limpo no boot | nenhuma: fora do alcance do esquema, escrita direta | só o próprio tv3ws, na limpeza do boot |
| `seed:done` | entrypoint do container `redis`, depois da carga inicial | nenhuma: fora do alcance do esquema (marca de controle) | o mesmo entrypoint e o healthcheck |

---

## Esquema nas escritas: funções do Redis e auditoria

Toda escrita do código do projeto (tv3ws, AoP, borda e carga inicial) nas famílias do alcance passa por uma função de uma biblioteca do próprio Redis (Redis Functions: `FUNCTION LOAD`, `FCALL`). A função confere o esquema e grava de forma atômica, inclusive as invariantes entre chaves. A conexão usa o usuário `default`, sem senha e com escrita. Não há usuário administrativo nem ACL. Redis, funções e esquema são decisões de implementação deste testbed; a norma não fala de armazenamento. O esquema só cita a norma onde a regra vem dela (a Tabela 7 nos perfis, por exemplo).

### Onde mora o esquema e como ele é carregado

- **Onde os esquemas são declarados:** `infra/redis/esquema.json`, um arquivo de dados versionado. Ele declara cada família (chave, tipo, dono, regra de cada campo, membro ou item, e a fonte de cada regra), as invariantes, as funções e o que fica fora do alcance. A biblioteca e os testes leem o mesmo arquivo. Algumas regras se repetem nos serviços, que conferem o dado antes de chamar a função para responder com o código da API ou com a mensagem do formulário (o gestor de perfis do AoP, os atributos de emissora no tv3ws).
- **Biblioteca:** `infra/redis/funcoes.lua`, montada por `infra/redis/biblioteca.sh` (cabeçalho `#!lua name=tv30` + o `esquema.json` embutido + o corpo). Ela interpreta as regras e registra 16 funções de escrita, uma por operação, e duas só de leitura (flag `no-writes`): `tv30_auditoria` e `tv30_versao`.
- **Carga:** o `infra/redis/entrypoint.sh` carrega a biblioteca **a cada partida**, com `FUNCTION LOAD REPLACE`, **antes** da carga inicial, que também passa pelas funções. O Redis guarda as funções no AOF; o `REPLACE` garante que vale a versão da imagem, não a que ficou no volume. Sem a biblioteca, o container encerra com a mensagem do Redis no log. O healthcheck só fica saudável depois da biblioteca e da carga.
- **No build:** o `infra/redis/confere-imagem.sh` carrega a biblioteca num Redis temporário, aplica a carga inicial e exige a auditoria vazia. Um `userData.json` fora do esquema não vira imagem.

Detalhes, a lista de funções com argumentos e como mudar uma regra: `infra/redis/README.md`.

### Esquema de cada família

| Família | Dono | Tipo | Esquema (resumo; o completo está no `esquema.json`) |
|---|---|---|---|
| `session:current-user` | tv3ws | STRING | texto de até 64 caracteres, vazio vale "sem usuário" (o mesmo teto de `aop/currentUser` no `schemas.json` do broker) |
| `session:current-service-id` | tv3ws | STRING | texto de até 256 caracteres, vazio vale "sem serviço" (o mesmo teto de `aop/currentService` no broker) |
| `session:current-service` | tv3ws | HASH | exatamente os cinco campos da Tabela C.8; `serviceId` inteiro em decimal ou vazio |
| `users:index` | AoP | SET | ids de perfil (`idPerfil`: UUID no formato da IETF RFC 9562, em minúsculas, estrito, com versão de 1 a 8, variante `8`, `9`, `a` ou `b` e sem o nulo e o máximo). O `{id}` das chaves `user:{id}`, `user:{id}:consent` e `user:{id}:broadcaster-attrs:{scid}` segue a mesma regra |
| `user:{id}` | AoP | HASH | Tabela 7 mais `lastAccess`: obrigatórios e condicionais da tabela, booleanos `"true"`/`"false"`, `nickname` de 1 a 20 caracteres, `maxContentRating` em `L`, `10`, `12`, `14`, `16` ou `18`, idiomas em IETF RFC 5646, `closedSigningWidth` de 14 a 28, `avatar` (opcional) como nome de arquivo do diretório de miniaturas, com extensão `.svg`, `.png`, `.jpg`, `.jpeg` ou `.webp`; o campo `id` igual ao da chave; nenhum campo fora da lista |
| `user:{id}:consent` | AoP | SET | ids de serviço (1 a 256 caracteres) |
| `user:{id}:broadcaster-attrs:{scid}` | tv3ws grava; AoP remove junto com o perfil | HASH | nome e valor não vazios, sem os básicos que a C.6.14.5 proíbe redefinir (`id`, `nickname`, `parentalControl`, `maxContentRating`), até 20 MB de nomes mais valores (10.3.3) |
| `client:{id}` | tv3ws | HASH | `class` em `local-associated`/`local-autonomous`/`non-local` e `refreshToken`, obrigatórios; `accessToken` opcional; nada além |
| `clients:authorized`, `clients:blocked` | tv3ws | SET | ids de cliente não vazios |
| `origins:associated` | AoP | HASH | campo = origem como o navegador a manda no `Origin` (esquema `http`/`https` e host em minúsculas, porta só se não for a padrão, sem caminho); valor = id de serviço |
| `bind-context:{serviceId}` | borda | LIST | cada item é um objeto JSON `{alg, key, registeredAt}` e nada mais: `alg` em HS256/HS512/RS256/RS512, `key` não vazia e `registeredAt` inteiro |

**Invariantes entre chaves** (conferidas pelas funções e pela auditoria):

- `perfil-indexado`: todo membro de `users:index` tem o hash `user:{id}`, e todo hash `user:{id}` tem o id em `users:index`. `tv30_perfil_grava` grava os dois juntos, e `tv30_perfil_remove` tira os dois juntos.
- `perfil-dependentes`: `user:{id}:consent` e `user:{id}:broadcaster-attrs:*` só existem para id em `users:index`. Invariante derivada do código: a criação grava perfil e visibilidade juntos, e a remoção do perfil (`tv30_perfil_remove`) apaga as quatro famílias juntas.
- `clientes-disjuntos`: nenhum id fica nos dois conjuntos de clientes. Autorizar e bloquear são uma função cada.
- `autorizado-tem-registro`: todo membro de `clients:authorized` tem o hash `client:{id}`. Invariante derivada do código: a autorização grava os dois juntos.

**Registro que já existe.** Quando a função só acrescenta campos a um hash existente (o `lastAccess`, o token de um cliente), ela confere os campos que grava. O que já estava gravado fora do esquema não trava a escrita; a auditoria o mostra. Registro novo ou regravado é conferido inteiro, de modo que nenhuma função cria um registro incompleto.

### Erro de esquema

O erro diz a função, a chave, o campo e o motivo, e nada é gravado:

```
TV30ESQUEMA tv30_perfil_grava: user:0b6e3c1a-7f2d-4e8b-9a5c-3d1f2e4a6b8c campo parentalControl: deve ser "true" ou "false" (veio "False")
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

A auditoria é só de leitura (flag `no-writes`). Ela percorre as chaves dos prefixos do alcance (`session:`, `users:`, `user:`, `clients:`, `client:`, `origins:`, `bind-context:`) e devolve uma entrada `[chave, familia, motivo]` por problema: chave sem família, tipo errado, campo, membro ou item fora da regra e cada invariante quebrada. **Vazia = tudo no esquema.** O `scripts/test-auth.sh` exige a auditoria vazia no fim, depois de desfazer o que semeou, e avisa no começo se já havia achados. O `scripts/test-consolidacao.sh` a mostra.

Dados gravados por fora das funções podem estar fora do esquema, e a auditoria os aponta. Num registro que já existe, as funções conferem só o que gravam: o perfil fora do esquema ainda recebe o `lastAccess` e pode ser removido, mas não é regravado. Para começar limpo, use `docker compose down -v`, que apaga os volumes, com os perfis criados e os retidos do broker. A outra saída é corrigir ou apagar as chaves apontadas.

### Gravar à mão para depurar

Para gravar como o serviço gravaria, use a função (`numkeys` é sempre 0):

```bash
docker exec redis redis-cli FCALL tv30_sessao_servico_id 0 urn:tv30:service:users-test
docker exec redis redis-cli FCALL tv30_origem_registra 0 http://urn-tv30-app-users-test.apps.localhost:8080 urn:tv30:service:users-test
docker exec redis redis-cli FCALL tv30_cliente_bloqueia 0 <clientid>
```

A escrita direta (`SET`, `HSET`, `SADD`...) pelo `redis-cli` ou pelo commander **continua possível** e não passa pelo esquema. Depois de uma, rode a auditoria. Uma escrita manual que cumpra o esquema não se distingue da do código.

### Por que não há bloqueio por ACL

Deixar o `default` só com leitura e `FCALL`, e um usuário administrativo para o resto, não funciona: o Redis aplica o ACL de quem chama **dentro** da função. Com o `default` sem `@write` e com `+fcall`, a função recebe:

```
ERR ACL failure in script: User default has no permissions to run the 'set' command
```

No Redis puro, não há como bloquear a escrita direta e liberar só a escrita pela função. As garantias ficam em duas partes:

- **Teste estático:** falha se algum serviço gravar direto numa família do alcance fora do adaptador das funções (`tv3ws/src/redis-funcoes.ts`, `aop/src/redis-funcoes.js`, `fcall` em `infra/edgegateway/plugin/redis.go` e `FCALL` na carga inicial). Roda no `npm test` do tv3ws e do AoP, no `go test` da borda (inclusive no build da imagem dela) e em `infra/redis/test/run.sh estatico`.
- **Auditoria:** mostra o que entrou por fora.

Os testes das funções num Redis real ficam em `infra/redis/test/run.sh`, nos modos `funcoes`, `contrato` e `imagem`.

### O que fica fora do alcance, e por quê

- `remote-devices:index`, `remote-devices:class:{classe}`, `remote-device:{handle}`: espelho dos dispositivos remotos conectados (WebSockets vivos), limpo no boot e lido só pelo próprio tv3ws. O tv3ws o grava direto (`src/modules/remotedevice-manager/manager.ts`, o único arquivo com escrita direta permitida; o teste estático exige que ele não cite chave do alcance).
- `seed:done`: marca de controle da carga inicial.
- `tv30:{componente}:exemplo`: chave do exemplo do template de componente, gravada só por `scripts/test-template.sh` e `scripts/test-dev-host.sh`.

---

## Chaves de sessão

| Chave | Tipo | Conteúdo |
|-------|------|----------|
| `session:current-user` | STRING | Id do perfil ativo no momento, o mesmo de `aop/currentUser` (ex.: `c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10`; vazio = sem usuário). Até 64 caracteres, o teto do tópico; o esquema desta chave não exige UUID |
| `session:current-service-id` | STRING | ID do serviço DTV ativo (ex.: `urn:tv30:service:users-test`; vazio = sem serviço). Até 256 caracteres, o teto do tópico |
| `session:current-service` | HASH | Serviço corrente, regravado inteiro pelo tv3ws a cada troca de serviço (`tv30_sessao_servico`), com os campos de `GET /tv3/current-service` (`serviceContextId`, `serviceId`, `serviceName`, `transportStreamId`, `originalNetworkId`). O `serviceId` vai como inteiro em decimal ou vazio (Tabela C.8) |

As duas chaves STRING espelham os tópicos MQTT retidos `aop/currentUser` e `aop/currentService`: o tv3ws as grava ao receber cada mensagem.

---

## Chaves de usuário

### `users:index` (SET)

Index de todos os IDs de usuário existentes.

```
SMEMBERS users:index
1) "c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10"
2) "5f0c2b9e-8d4a-4c1e-a7b3-2e6f9d1c4a80"
...
```

Só UUID estrito: o perfil da carga inicial e os que o AoP cria com `crypto.randomUUID()` (o segundo id acima é ilustrativo, versão 4 e variante `a`).

### `user:{id}` (HASH)

Atributos básicos do perfil (conforme **ABNT NBR 25608, Tabela 7**) mais o `lastAccess` do testbed. Tudo é gravado como texto; a coluna da direita é o que a função `tv30_perfil_grava` exige (`infra/redis/esquema.json`):

| Campo | Tabela 7 | Esquema no Redis |
|-------|----------|-----------------------|
| `id` | UUID, requerido | obrigatório, igual ao `{id}` da chave, UUID no formato da IETF RFC 9562, em minúsculas, estrito: versão de 1 a 8, variante `8`, `9`, `a` ou `b`, e o UUID nulo e o máximo recusados |
| `nickname` | string até 20 caracteres, requerido | obrigatório, 1 a 20 caracteres (contados como caracteres, não bytes) |
| `avatar` | file path, opcional | opcional; o nome de um arquivo do diretório de miniaturas: sem `/` nem `\`, começando por letra ou dígito, com letras sem acento, dígitos, `.`, `_` e `-`, até 128 caracteres antes da extensão, e a extensão `.svg`, `.png`, `.jpg`, `.jpeg` ou `.webp`, em minúsculas. O AoP grava `<id>.svg` |
| `parentalControl` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `maxContentRating` | valores do país, requerido só se `parentalControl = true` | `L`, `10`, `12`, `14`, `16` ou `18`; obrigatório com `parentalControl` `"true"` |
| `audioLanguage` | RFC 5646 (`pt-BR`, `en`...), opcional | opcional, formato IETF RFC 5646 |
| `closedCaptioningLanguage` | RFC 5646, opcional (aplicável se `closedCaptioning = true`) | opcional, formato IETF RFC 5646 |
| `userInterfaceLanguage` | RFC 5646, opcional | opcional, formato IETF RFC 5646 |
| `closedCaptioning` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `closedSigning` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `closedSigningSide` | left/right, aplicável se `closedSigning = true` (padrão: right) | `left` ou `right`; obrigatório com `closedSigning` `"true"` |
| `closedSigningWidth` | inteiro de 14 a 28, aplicável se `closedSigning = true` (padrão: 28) | inteiro de 14 a 28; obrigatório com `closedSigning` `"true"` |
| `audioDescription` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `dialogEnhancement` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `voiceGuidance` | true/false, requerido | obrigatório, `"true"` ou `"false"` |
| `lastAccess` | (não é da norma) | opcional, inteiro (instante em ms) |

Nenhum outro campo entra no hash.

Inspecionar:

```bash
docker exec redis redis-cli HGETALL user:c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10
```

### `user:{id}:consent` (SET)

Serviços DTV para os quais o perfil é visível: a visibilidade do perfil por serviço, e não o consentimento da seção 8.8 da norma (o Privacy Manager, que o testbed não implementa). O tv3ws lê este SET (`tv3ws/src/api/user/service.ts`) em três lugares: no filtro da lista de perfis da C.6.14.1 (`getUserList`: só entram os perfis com o serviço corrente aqui; sem serviço corrente, ou com um serviço que nenhum perfil tem, a chamada responde 300), no 405 da C.6.14.2 e da C.6.14.5 (`assertUserVisible`, para o serviço da chamada) e no `GET /tv3/current-service/users/files` (`checkConsent`: o arquivo sai se ele é o avatar de um perfil visível no serviço corrente; o avatar só de perfis não visíveis dá 405, e o que não é avatar de ninguém, 305). O AoP o grava na criação do perfil (abaixo); a carga inicial o traz do `accessConsent` do `userData.json`.

```
SMEMBERS user:c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10:consent
1) "urn:tv30:service:webmedia"
2) "urn:tv30:service:uff"
3) "urn:tv30:service:eduplay"
4) "urn:tv30:service:users-test"
```

(o perfil da carga inicial, com o `accessConsent` do `infra/user-files-template/userData.json`; o Redis não garante a ordem dos membros)

### `user:{id}:broadcaster-attrs:{serviceContextId}` (HASH)

Atributos extras definidos pela emissora para o usuário, **dentro do contexto de um serviço DTV** (C.6.14.5), gravados pelo tv3ws com `tv30_atributos_emissora`. Ficam num hash à parte: a escrita não muda o `user:{id}`, e `id`, `nickname`, `parentalControl` e `maxContentRating` não podem ser redefinidos aqui (101 no tv3ws, recusa na função). Na leitura (C.6.14.2, `getUserAttributes` em `tv3ws/src/api/user/service.ts`), com o nome do atributo na query vale o básico, quando existe; sem atributo na query, o JSON junta os dois hashes, e o de emissora prevalece num nome repetido (por exemplo, um `avatar` gravado pela emissora).

---

## Chaves de credenciais

| Chave | Tipo | Quem escreve | Conteúdo |
|-------|------|--------------|----------|
| `client:{id}` | HASH | tv3ws (autorização, C.6.1) | `class` (`local-associated`, `local-autonomous` ou `non-local`), `refreshToken`, `accessToken` — o vínculo cliente↔token. Fica também depois de um bloqueio |
| `clients:authorized` | SET | tv3ws | Ids de cliente autorizados pelo espectador. O `/tv3/token` só emite para quem está aqui. Disjunto de `clients:blocked`: autorizar e bloquear são uma função cada (`tv30_cliente_autoriza` e `tv30_cliente_bloqueia`), que tira o id de um conjunto e o põe no outro. No boot, o tv3ws inclui aqui todo `client:{id}` que não está bloqueado (`backfillAuthorizedClients`, com `tv30_cliente_inclui_autorizado`), sem distinguir a origem do registro. Base da futura tela de histórico de autorizações (C.4.2.2), que não existe. A borda também o lê: o `sub` do access token tem de estar aqui, e fora dele a resposta é 107, como a do bloqueado (só nas rotas que pedem token). Um cliente desbloqueado à mão (`SREM clients:blocked`) fica fora dos dois conjuntos e continua recusado até voltar a este, o que acontece na próxima partida do tv3ws, porque o `client:{id}` dele fica |
| `clients:blocked` | SET | tv3ws | Ids de cliente bloqueados pelo usuário (C.4.2.2); a borda responde 107 a token de cliente nesta lista, conferida antes de `clients:authorized` |
| `origins:associated` | HASH | AoP (`aop/src/core.js`) | `origem → id do serviço corrente` das aplicações de emissora lançadas: o valor de `aop/currentService`, o mesmo de `session:current-service-id`, que é o `globalServiceId` e o `serviceContextId` do serviço; sem serviço corrente, a origem não é registrada. A origem é a **própria** da aplicação, `http://<rótulo>.<APPS_DOMAIN>:<AOP_PUBLIC_PORT>` (padrão `http://<rótulo>.apps.localhost:8080`; porta 80 omitida), em que a camada gráfica a abre e que o navegador manda no `Origin` das chamadas dela; o rótulo sai do `appId` da BALD (`aop/src/app-hosts.js`; o users-test grava `http://urn-tv30-app-users-test.apps.localhost:8080`), e a mesma entrada volta a cada lançamento, também depois de o bcast reiniciar. O caminho da URL, com o prefixo `/graphicsAppProxy`, não entra na origem. O AoP grava a entrada ao lançar a aplicação, apaga ao encerrá-la ou trocá-la, e limpa a chave no boot. O `/graphicsAppProxy` no host do AoP não grava nada: redireciona (302) para o host da aplicação. Base para reconhecer o cliente local associado (o `Origin` é forjável fora do navegador; a C.4.1.7 sugere porta de origem e deixa o mecanismo à implementação) |
| `bind-context:{serviceId}` | LIST | borda (`POST /tv3/bind-context`, C.6.8.2, respondida pelo plugin `tv30-auth`) | Uma entrada JSON por chave registrada pela emissora: `{"alg":"RS256","key":"<string recebida>","registeredAt":<ms>}` |

### `bind-context:{serviceId}` (LIST)

Chaves de validação de bind-token registradas pela emissora (C.6.8). O receptor **não emite** bind-token: guarda o par (algoritmo, chave) e valida os tokens que a emissora assina.

- `{serviceId}` é o valor de `session:current-service-id` no momento do registro (a C.6.8.2 registra para o serviço selecionado). O registro sem serviço corrente responde erro 300 (norma silente — decisão de implementação).
- `alg` ∈ {`HS256`, `HS512`, `RS256`, `RS512`} (C.4.1.4.8). Sem duplicatas: o mesmo par alg+key não entra duas vezes.
- A emissora pode ter **várias** chaves (rotação): qualquer uma da lista valida (C.4.1.3). Nas rotas `token+bind`, o bind-token só vale contra as chaves do **serviço corrente** — isolamento entre emissoras. A exceção é a própria C.6.8.3 (`GET /tv3/bind-context`), que procura, entre as chaves de **todos** os serviços (`SCAN bind-context:*`), os que validam o token e os lista.
- `DELETE /tv3/bind-context` (cabeçalho `key`, C.6.8.4) remove a chave da lista do serviço corrente; sucesso mesmo se não existir, e também sem serviço corrente (não há lista de que remover).
- Codificação da `key` (norma silente — decisão de implementação): HS = bytes UTF-8 do segredo, sem trim (duplicata só se o texto for idêntico); RS = PEM (o texto começa por `-----BEGIN` e o rótulo é `PUBLIC KEY`, `RSA PUBLIC KEY`, `RSA PRIVATE KEY` ou `PRIVATE KEY`) ou base64 de DER (SPKI ou PKCS#1); chave privada recebida tem a pública derivada. Módulo RSA pequeno demais para o algoritmo dá 101. O registro e a validação usam a mesma função de leitura de chave, no plugin da borda (`infra/edgegateway/plugin/keys.go`).
- A gravação é pela função `tv30_bind_registra` (um `RPUSH`), e a revogação pela `tv30_bind_remove` (um `LREM 0`). A função confere a entrada (um objeto JSON `{alg, key, registeredAt}` e nada mais, com `alg` entre os quatro, `key` não vazia e `registeredAt` inteiro) e o `serviceId`.
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

user-files-template/thumbs ──(userfiles-seed, a cada subida, o que falta)──> user-files/thumbs

gestor de perfis do AoP ──(criação, lastAccess)──> Redis
gestor de perfis do AoP ──(arquivo do avatar: criação)──> user-files/thumbs
tv3ws ──(só leitura de perfis)──> Redis
tv3ws ──(C.6.14.6: só leitura)──> user-files/thumbs
```

- **Carga inicial.** O `infra/redis/emit_seed.py` gera o seed a partir do `userData.json` no build da imagem, e o `infra/redis/entrypoint.sh` o aplica uma vez, no banco vazio (sem `seed:done`). Depois disso, o arquivo não é mais lido. Cada perfil vira uma chamada `FCALL tv30_perfil_grava`, com os booleanos em `"true"`/`"false"`. Um perfil do template fora do esquema faz o build da imagem falhar (`confere-imagem.sh`). O `migrate_to_redis.py` da imagem do broker, que só serve à depuração manual, usa a mesma chamada.
- **Sem re-sincronização.** O tv3ws não relê o arquivo: os perfis vêm só do Redis, e o tv3ws não exige o `USER_DATA_FILE`.

Quem grava os perfis é o **gestor de perfis do AoP** (`aop/src/modules/profile-manager/service.js`), pelas funções do Redis (adaptador `aop/src/redis-funcoes.js`). O tv3ws não tem rota de criação de perfil. Na criação pelo form (`createProfile`):

1. O dado do form é conferido: nickname, classificação, Libras, os idiomas (IETF RFC 5646) e a lista de visibilidade (ids de serviço). Dado inválido dá 400, com a mensagem.
2. Teto de 5 perfis (10.3.3): com cinco, o sexto é **recusado** com 400 e a mensagem, que a tela mostra ao telespectador, e nenhum perfil é despejado. O despejo por último acesso da 10.3.3 é da quota de área privativa, e não dos perfis. A função `tv30_perfil_remove` existe para a remoção do perfil, que apaga numa operação só `users:index`, `user:{id}`, `user:{id}:consent` e todos os `user:{id}:broadcaster-attrs:*`; nada a chama, porque a remoção pelo telespectador não existe.
3. O arquivo do avatar antes do perfil: o SVG do formulário, conferido como as telas conferem (texto que começa por `<svg` e tem o elemento `<svg>`; fora disso, o avatar padrão), vai para `<USER_DATA_PATH>/thumbs/<userId>.svg`, com o `xmlns` acrescentado quando falta e sem sobrescrever arquivo existente (`aop/src/modules/profile-manager/avatar.js`). Falha ao gravar o arquivo responde 404 `{"error":200}` sem gravar o perfil.
4. `tv30_perfil_grava` numa operação só, com o `{userId}` gerado por `crypto.randomUUID()`: `users:index` recebe o `{userId}`, `user:{userId}` é regravado com os campos da Tabela 7 (com `lastAccess` igual ao instante da criação) e `user:{userId}:consent` recebe o `{session:current-service-id}` (visibilidade automática para o serviço ativo — termo aceito no form), mais a lista `accessConsent` do pedido, quando ele a traz (o form do AoP não a manda). O `avatar` gravado é o nome do arquivo do passo 3, `<userId>.svg`. Se a função recusar o perfil, o AoP apaga o arquivo e responde o erro.
5. O AoP recarrega a própria lista de usuários do Redis (`refreshUserData`); o `userData.json` não é alterado.

**`lastAccess`** (campo de `user:{id}`). Só o AoP o grava (`touchLastAccess`), em toda troca de usuário corrente: a feita pela própria plataforma (seletor de perfis) e a que chega pelo tópico `aop/currentUser`, publicada por outro componente (por exemplo, a C.6.14.4 no tv3ws). A gravação é a função `tv30_perfil_ultimo_acesso`, que só escreve se o id estiver em `users:index`, para não criar um hash avulso de um perfil inexistente. O AoP grava o `lastAccess` também na criação.

---

## Clientes do Redis e falha

- **tv3ws e AoP** (ioredis): `maxRetriesPerRequest: 1`, `commandTimeout` de 1500 ms, `connectTimeout` de 2000 ms, fila offline ligada e reconexão contínua (200 ms a 2 s). Comando sem resposta falha, e a rota HTTP responde 404 `{"error":200}` (no tv3ws, `src/util/error.ts`; no AoP, `src/http-error.js`). O log registra `[redis] pronto em ...`, a perda da conexão e o erro. Configuração em `tv3ws/src/redis-client.ts` e `aop/src/redis-options.js`.
- **Borda** (cliente RESP próprio, `infra/edgegateway/plugin/redis.go`): limite de 500 ms por comando (`REDIS_TIMEOUT_MS`), e uma nova tentativa numa conexão nova quando a do pool morreu, menos para o registro de bind-context (`tv30_bind_registra`) que já saiu. A falha dá 404 `{"error":200}` nos dois modos, tanto na decisão de credencial (o 200 não segue o `AUTH_ENFORCE`; `followsMode`, em `handler.go`) quanto na C.6.8, que a própria borda responde (a C.6.7.8 e a C.6.7.9 não usam o Redis).
- **Recusa de esquema**: erro `TV30ESQUEMA` de uma função. Os três serviços a tratam como as outras falhas do Redis (404 `{"error":200}`, com a mensagem no `description` e no log), porque ela é defeito de quem grava. O que o cliente da API manda errado é recusado antes, pelo próprio serviço, com o código da norma (101, 105...).
