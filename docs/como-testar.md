---
title: Como testar
parent: Primeiros passos
nav_order: 3
---

# Como testar

O testbed tem dois tipos de teste:

- **Testes de unidade**, que rodam sem a stack, na pasta de cada módulo. Usam dublês no lugar do Redis, do broker e do bcast, e levam segundos.
- **Suítes de `scripts/`**, que rodam contra a stack de pé, em Linux ou no WSL2, e conferem os módulos juntos, pela rede do Docker. Algumas mudam o estado da stack enquanto rodam.

Antes de mandar uma mudança, rode os testes de unidade do módulo que você mexeu. Se ela toca a borda, as credenciais ou a conversa entre módulos, rode também o `scripts/test-auth.sh` e o `scripts/test-dev-host.sh`.

{: .nota }
Estes testes conferem o comportamento do testbed. Onde um caso cita uma seção da norma, ele confere aquele requisito; os casos de borda, mensageria e Redis conferem decisões do projeto.

---

## Resumo

| Teste | Precisa da stack? | Tempo aproximado |
|---|---|---|
| tv3ws: `npm test` | não | de 25 a 38 s |
| tv3ws: `npx tsc --noEmit` | não | 7 s |
| aop: `npm test` | não | de 7 a 11 s |
| Redis: `bash infra/redis/test/run.sh tudo` | não (Docker, com containers descartáveis) | — |
| bcast: `npx tsc --noEmit` | não | 8 s |
| borda: `node --test generate.test.js` | não | 1 s |
| broker: testes de unidade do plugin C (`test_error_json.c`, `test_json_payload.c`) | não (rodam no build da imagem do broker) | parte do build |
| broker: `test_errors_json.sh` e `test_all_validations.sh` | não (Docker, com broker descartável) | cerca de 30 s os dois, com a imagem já construída |
| borda: testes Go do plugin `tv30-auth` | não (Docker, para o compilador) | 15 s, com a imagem do compilador já baixada |
| anunciante SSDP: testes Go | não | 7 s |
| `scripts/test-auth.sh` | sim | 1,5 min |
| `scripts/test-dev-host.sh` | sobe e desce o que precisa | 3 min, com o cache do npm já cheio |
| `scripts/test-template.sh` | sim | 30 s |
| `scripts/test-consolidacao.sh` | recria a stack | 1 min |
| `scripts/test-fase0.sh` | sobe a stack | 20 s |
| `scripts/test-bcast-shutdown.sh` | sim | 25 s |
| `scripts/test-virgin-up.sh` | derruba e sobe do zero | — |

---

## Testes de unidade (sem a stack)

Pré-requisitos: Node.js e `npm ci` na pasta do módulo. Nada aqui precisa de Redis, broker ou bcast de verdade.

### tv3ws

```bash
cd tv3ws
npm ci
npm test            # node --test com ts-node, os 14 arquivos de test/
npx tsc --noEmit    # checagem de tipos
```

Os dublês ficam em `tv3ws/test/helpers/`: `fake-redis.ts`, um Redis em memória com falha injetável, e `fake-mqtt.ts`, que entrega mensagens aos tratadores sem broker. O `fake-redis.ts` imita o **efeito** das funções do Redis que o tv3ws chama (`FCALL`), sem conferir o esquema, e pode fazer uma função recusar como o Redis recusa (`recusar`). A conferência do esquema é testada num Redis real, em `infra/redis/test` (abaixo).

| Arquivo | O que cobre |
|---|---|
| `api-version.test.ts` | A versão decidida pela borda (`X-TV30-API-Version`) nas respostas e nos erros; sem o cabeçalho, 2.0; o `Accept-Version` do cliente não é lido; o tratador da 100.0 no caminho interno `/v100.0` |
| `client-identification.test.ts` | `/tv3/authorize` e `/tv3/token` (C.6.1): primeira autorização, reuso de `clientid` com 101, refresh token, recusa no pop-up com 102 (gravada na hora, também para o não local), pareamento `qrcode` e `kex` (com o `key` e o PIN de quatro dígitos), `clients:authorized` e `clients:blocked`, Redis fora do ar com 404 `{"error":200}`; o "sim" do não local sem pareamento concluído, que não grava nada (o mesmo `clientid` vê o pop-up de novo, e só o desafio novo conclui), e a gravação da autorização recusada no `/tv3/token` (404 `{"error":200}`, sem credencial nem registro, com o material de volta); parâmetro vazio ou só com espaços como ausente (105, sem credencial e sem pop-up; `pm=` vazio deixa o cliente local), o `challenge-response` repetido depois do sucesso (102, no `qrcode` e no `kex`) e o do cliente local (102), dois `/tv3/token` simultâneos com a mesma resposta (só um emite), a emissão que falha depois do desafio conferido (o material volta), as comparações em bytes e em tempo constante do refresh token e da resposta ao desafio, e o `challenge-response` que não decifra ou vem repetido na URL (102, como o hash errado, no `qrcode` e no `kex`) |
| `pairing-popup.test.ts` | O QR code e o PIN saem com o prazo de 120 s, ficam nos `/tv3/token` que falham e fecham (`{"close":true}`, depois da abertura, no mesmo tópico) no sucesso; a emissão que falha não fecha; o `/tv3/token` do cliente local não publica fechamento. O 103 com a camada ocupada: com o QR code ou o PIN de outro cliente na tela, e com o sim/não de outro pedido esperando resposta, inclusive do mesmo `clientid`, sem pop-up novo; o 101 antes do 103; a camada livre depois do sucesso, da recusa, de um erro e da trava de 120 s (com relógio de teste), e o fim tardio de um pareamento sem fechar o pop-up de outro; o novo `/tv3/authorize` do mesmo `clientid` com tentativa pendente, que a descarta (103 com o pop-up dela na tela; depois da trava, sim/não e QR code novos) e deixa o desafio anterior dando 102 |
| `app-files.test.ts` | A C.6.4.7 com caminho que sai do diretório da aplicação (`..`, codificado, barra invertida, NUL, absoluto e link simbólico) dando 305 sem o conteúdo de fora; arquivo dentro, com o MIME e a barra inicial opcional; inexistente com 305; a listagem da Tabela C.17 com `path` omitido, vazio, `/` ou de diretório; `appId` que não é o corrente; `Range` em vídeo (206); sem diretório da aplicação conhecido (305); e a troca de aplicação (a nova não serve o diretório da anterior antes do `.../path` dela; encerrar zera o diretório) |
| `current-service.test.ts` | `GET /tv3/current-service` (C.6.3.1): 300 sem serviço em uso, 200 sem `serviceId` nem `serviceName` (sem SLT); `aop/services` no formato do esquema (`serviceContextId`) |
| `manifest.test.ts` | O `/manifest` aponta para a borda (44642/44643), com o host da requisição (`X-TV30-Host`) ou o `SSDP_ADVERTISE_HOST`, e expõe ao navegador, em `Access-Control-Expose-Headers`, exatamente os cabeçalhos `Server-*` e `Device-*` que envia |
| `remote-device.test.ts` | Remote-device (C.6.15): registro e remoção, porta ocupada (`EADDRINUSE`), ponto de entrada local da 2.0 e da 100.0 (a rota escolhe a resposta: `/v100.0` só com *handles*), com o certificado o registro em `wss://` e o local em `ws://`, Redis fora do ar |
| `sensory-effect.test.ts` | Efeitos sensoriais (C.6.16): a capacidade `location` e os nomes de propriedade da Tabela A.30 e da A.3.19 (outro nome, 101) |
| `tls.test.ts`, `listen-hosts.test.ts` | O certificado do receptor (`TV30_TLS_DIR`, depois `HTTPS_KEY`/`HTTPS_CERT`; o `wss://` do dispositivo remoto e `TV3WS_WS_TLS`) e os endereços de escuta fora do container (127.0.0.1, mais a `docker0`; `TV3WS_LISTEN_HOST`) |
| `redis-client.test.ts` | O cliente Redis falha rápido: com a porta fechada, o comando rejeita em menos de 1,5 s; com um servidor que aceita e não responde, no `commandTimeout` de 1,5 s (o teste aceita de 1,4 s a 2 s, abaixo dos 2 s da borda) |
| `ssdp-config.test.ts` | As portas e o host que o `/manifest` anuncia |
| `user-service.test.ts` | Perfis só de leitura no tv3ws, C.6.14.1, C.6.14.4 (300, 305 e 405 da Tabela C.73, sem gravar nada), C.6.14.5 e C.6.14.6, falhas do Redis, escritas pelas funções e recusa de esquema com 404 `{"error":200}`. Na C.6.14.6, o caminho que sai de `USER_THUMBS` dá 305 sem o conteúdo, e o avatar só de perfis não visíveis no serviço, 405 (de ninguém, 305); o `Content-Type` pela extensão (`.svg`, `.png`, `.jpg`, `.jpeg`, `.webp`; outra, `application/octet-stream`), com os bytes e o `Content-Length` intactos. O avatar (nome do arquivo) devolvido como está pela C.6.14.2. O aviso da C.6.14.5 em `aop/display/layers/popup/info`, sem retenção, com o nome do serviço corrente ou o id do serviço e o apelido (ou sem ele), que não sai quando nada muda nem quando a gravação falha (recusa da função, Redis fora, 101, 305, 405, 300), e cuja própria falha só vai para o log, com a API respondendo o sucesso |
| `redis-escritas.test.ts` | Teste estático das escritas no Redis: o tv3ws só grava nas famílias do alcance pelo adaptador `src/redis-funcoes.ts` (regras em `infra/redis/test/escritas.js`; precisa do TV30 com os submódulos) |

### aop

```bash
cd aop
npm ci
npm test            # node --test test/redis.test.js test/app-hosts.test.js test/redis-escritas.test.js test/mqtt-ws.test.js test/popup.test.js test/views-escape.test.js test/lls.test.js
```

| Arquivo | O que cobre |
|---|---|
| `redis.test.js` | O cliente Redis que falha rápido (ioredis de verdade contra uma porta fechada e contra um servidor mudo), o `lastAccess` só de perfil existente, a criação de perfil (`POST /profile/create`), a recusa do sexto perfil pela função que grava (400 com a mensagem, sem despejo), a remoção (`POST /profile/remove`: o perfil único e o inexistente recusados com 400; perfil, visibilidade, atributos de emissora e arquivo do avatar removidos, e o arquivo de outro perfil fica; duas remoções ao mesmo tempo; com cinco perfis, remover um abre espaço), o perfil padrão "Viewer 1" na base sem perfil, as escritas pelas funções do Redis, a conferência de idiomas e da visibilidade (400) e a recusa de esquema (404 `{"error":200}`). O id criado em UUID (formato da RFC 9562, em minúsculas, com a versão de 1 a 8 e a variante da RFC 9562 que o esquema exige, e dois perfis com ids diferentes). A criação grava o SVG do formulário em `<thumbs>/<id>.svg`, com o `xmlns`, e o `avatar` é o nome do arquivo; avatar ausente ou que não é SVG grava o padrão; o perfil recusado pela função apaga o arquivo, e a falha ao gravar o arquivo não grava o perfil; o sexto perfil recusado não grava arquivo |
| `mqtt-ws.test.js` | O `/mqtt` do AoP. A configuração (`ws://MQTT_HOST:MQTT_WS_PORT`, padrão 9001, valor inválido recusado); um upgrade WebSocket de verdade até um broker local, com quadros nos dois sentidos; o pacote `mqtt` da página conectando pelo AoP; 404 num host de aplicação e noutro caminho, sem nada chegar ao broker; 502 com o broker fora do ar; e a página da TV (`GET /`) conectando na própria origem, sem porta do broker |
| `redis-escritas.test.js` | Teste estático das escritas no Redis: o AoP só grava no Redis pelo adaptador `src/redis-funcoes.js` |
| `popup.test.js` | A camada gráfica de pop-ups (`public/js/popup.js`) num DOM de teste. O QR code e o PIN ficam até o `{"close":true}` no mesmo tópico, e saem pela trava sem ele; fechamento de outro tipo, no sim/não ou sem pop-up não muda nada; mensagem inválida não lança; o prazo de um pop-up que saiu ou foi substituído não fecha o seguinte; o sim/não publica a resposta e devolve as teclas à página; exceção no tratamento não escapa para o cliente MQTT; e o escape do `display-name` e do PIN (o QR code vai só para a biblioteca). O aviso `info` na tela, sem botões nem resposta, escapado, fechando no prazo (5 s se o prazo for ausente, zero, negativo ou não numérico; o `{"close":true}` não o fecha); esperando o sim/não (a resposta ou o prazo dele), o QR code e o PIN (o fechamento ou a trava) e outro aviso; a fila de 3, com o excedente descartado e logado; e o aviso substituído por um sim/não, QR code ou PIN voltando à fila e aparecendo inteiro depois |
| `views-escape.test.js` | `src/html.js` (`escapeHtml`, o SVG como `<img src="data:image/svg+xml;base64,...">`, com o `xmlns` acrescentado quando falta) e as páginas do catálogo (`/appcat`), da aplicação de abertura (`/btpapp`) e da escolha de perfil (`/prfchs`) com `appName`, `globalServiceId`, ícone, apelido e avatar hostis, mais o avatar padrão; `cssHexColor` e as cores do BAM e do gênero no `<style>` da aplicação de abertura (fora do formato, o padrão da view); e o id codificado na query de `selectService` e `selectProfile`; na escolha de perfil, a opção de remover só com mais de um perfil e a tela de confirmação (apelido e erro como texto, um `POST` com o id inteiro, o Cancelar devolvendo o foco). O `avatarHtml` com o arquivo do avatar (o SVG em `data:image/svg+xml`, com o `xmlns` acrescentado quando falta, e PNG, JPG, JPEG e WEBP com o tipo da extensão e os bytes intactos) ou o padrão, sempre em `<img class="avatar">`; o padrão também para o avatar ausente, o SVG em linha no campo, o nome fora do formato (com diretório, `..`, outra extensão, maiúsculas, mais de 128 caracteres), o arquivo inexistente, o que não tem `<svg>`, o diretório, o maior que o teto (1 MB) e o link simbólico para fora do diretório, sem linha de erro no log |
| `app-hosts.test.js` | O host próprio de cada app de emissora: o rótulo DNS de cada app, a origem que o navegador manda, o registro e a remoção em `origins:associated` ao lançar, trocar e encerrar a app, o roteamento por `Host` (proxy para a app, 404 e 502), o prefixo `/graphicsAppProxy` na URL que a camada gráfica recebe e opcional no host da app (`stripPrefix`), e o `/graphicsAppProxy` no host do AoP, que responde 302 para o host da app, ou 404 sem app, sem gravar origem. O "bcast" é um servidor HTTP local. Também, no core: a partida com a base sem perfil (o perfil padrão vira o corrente), a remoção do perfil corrente (`aop/currentUser` vazio e retido, `aop/removedUser` com o id, volta ao seletor) e a BAMT até a unidade da LLS, com o serviço corrente saindo dela |
| `lls.test.js` | A unidade `aop-transport-layer-metadata-lls`: na partida, a lista vazia gravada e `[]` publicado retido; a BAMT gravada em `services:announced` pela função e o mesmo conteúdo em `aop/services`; serviço repetido entre fluxos entra uma vez, com o BAM da BAMT recebida por último; a BAMT retirada tira os serviços daquele fluxo; outras tabelas da LLS e BAMT que não é JSON não mudam a lista; a falha do Redis tenta de novo e só publica depois de gravar, e a recusa do esquema não repete; o Application Catalog mostrando só os serviços de `services:announced`, e 404 `{"error":200}` com o Redis fora |

### bcast

O bcast não tem testes de unidade. A checagem que existe é a de tipos:

```bash
cd bcast
npm ci
npx tsc --noEmit
```

### Borda (`infra/edgegateway`)

O gerador da tabela de rotas tem testes em JavaScript, sem dependências:

```bash
cd infra/edgegateway
node --test generate.test.js
```

Eles cobrem as duas superfícies com as 26 rotas e o 106 de cada uma, as versões por rota e a regra de uma versão por API, o caminho interno das extensões (`/v<X.Y>` de 100 em diante, um endpoint por par rota × versão, e o prefixo recusado num caminho declarado), o `no_service`, o `not_in_catalog` (304 só na C.6.14.2 e na C.6.14.5), o TLS da externa, os arquivos gerados (duas variantes por superfície, `linux` e `windows`, e os dois OpenAPI), as 20 APIs da C.6.7.8/C.6.7.9 nas duas, o bloco `cors`, a recusa do campo `surfaces` por rota e a ausência de `POST /tv3/{serviceContextId}/users` na tabela.

O plugin `tv30-auth` e o anunciante SSDP são Go, só com a biblioteca padrão. Rode os testes no compilador da imagem: `krakend/builder:2.7.2` (Go 1.22.7, Alpine) em amd64, ou `golang:1.22.7-alpine3.19` em arm64, como o Dockerfile escolhe pelo `TARGETARCH`:

```bash
GO_IMG=krakend/builder:2.7.2      # arm64 (Mac Apple Silicon): golang:1.22.7-alpine3.19
docker run --rm -v "$PWD/infra/edgegateway/plugin:/src" -w /src $GO_IMG \
  sh -c 'go vet ./... && go test -count=1 ./...'
docker run --rm -v "$PWD/infra/edgegateway/ssdp:/src" -w /src $GO_IMG \
  sh -c 'go vet ./... && go test -count=1 ./...'
```

| Pasta | O que cobre |
|---|---|
| `plugin/` | A decisão por classe, rota e modo (`handler_test.go`: o `sub` fora de `clients:authorized`, o `Origin` associado nas rotas que não admitem o associado, o não local por HTTP, o associado fora do próprio contexto de serviço, o token de classe `associated` com a regra geral do bind-token, o 300 e o 304 antes do bind-token, o `serviceContextId`, a versão negociada por rota, o caminho interno das extensões e os cabeçalhos internos), o access token e o bind-token nas quatro frentes da C.4.1.4 (`jwt_test.go`), os formatos de chave (`keys_test.go`, com os casos de `testdata/keyformats.json`), a C.6.8 (`bindcontext_test.go`), a C.6.7.8/C.6.7.9 (`apiinfo_test.go`), o cliente Redis (`redis_test.go`), o casamento de rotas (`routes_test.go`), as superfícies (`surface_test.go`), o teste estático das escritas (`escritas_test.go`) e o contrato com as funções do Redis (`contrato_test.go`, que só roda com `TV30_REDIS_TESTE`, pelo `infra/redis/test/run.sh contrato`) |
| `ssdp/` | O anunciante nativo: mensagens NOTIFY e respostas ao M-SEARCH (`ssdp_test.go`), a interface da rota padrão e o host detectado, a troca de rede, o arquivo de parada, a espera sem rede, os erros de configuração que encerram e o `ssdp:byebye` (`main_test.go`) |

**Os testes da borda também rodam no build da imagem.** O `infra/edgegateway/Dockerfile` roda `go vet` e `go test` no estágio `plugin` e `node --test generate.test.js` no estágio `gen`. Então `docker compose build edgegateway` falha se algum deles falhar, e a imagem não sai. Os do anunciante rodam no `./tv30 up` (e no `./tv30 ssdp-build`) antes de compilar o binário.

### Redis (`infra/redis`): esquema nas escritas

Não precisa da stack. Precisa de Docker: os testes sobem containers descartáveis, com nome próprio, e os removem no fim. O container `redis` da stack não é tocado.

```bash
bash infra/redis/test/run.sh tudo     # ou um modo: funcoes | estatico | contrato | imagem
```

| Modo | O que cobre |
|---|---|
| `estatico` (`escritas.test.js`) | Nenhum serviço grava direto numa família do alcance fora do adaptador das funções: tv3ws, AoP, plugin da borda (Go) e carga inicial (Python) |
| `funcoes` (`funcoes.test.js`, num `redis:7-alpine`) | Aceitação; recusa de cada regra do esquema, com os casos **gerados** a partir do `esquema.json`, e conferência de que nada foi gravado; valores de fronteira; atomicidade; invariantes; a auditoria, que aponta cada tipo de problema gravado à mão e volta vazia; o id de perfil que não é UUID, gravado à mão (auditoria aponta, gravação recusada, remoção passa); o teto de cinco perfis na gravação (id novo além dele recusado, regravar existente aceito, remover libera, membro gravado à mão contado); `services:announced` regravado inteiro; o UUID estrito: cada versão de 1 a 8 com cada variante 8, 9, `a` e `b` aceita, versão e variante fora disso recusadas com a mensagem da parte que falhou, o UUID nulo e o máximo recusados, e o id da carga e o `crypto.randomUUID()` do AoP aceitos; e o avatar como nome de arquivo: a regra do `esquema.json` decide igual à expressão do contrato nos valores de fronteira e em valores gerados, e o avatar em SVG em linha, gravado à mão (auditoria aponta, regravação recusada, último acesso, atributos de emissora e remoção seguem) |
| `contrato` (`contrato.test.js` + `contrato_test.go`) | Os adaptadores e os gestores de verdade (auth-manager do tv3ws, gestor de perfis do AoP, `redisStore` da borda) contra as funções, inclusive a leitura de `clients:authorized` pela borda; o id do AoP em UUID versão 4 com a variante da RFC 9562 e a recusa do UUID nulo e da versão fora de 1 a 8 voltando ao serviço como erro `TV30ESQUEMA`; o gestor de perfis do AoP gravando o avatar em `thumbs/` de um `USER_DATA_PATH` temporário (o `avatar` é `<id>.svg`, o arquivo tem o SVG do formulário, o sexto perfil é recusado sem gravar arquivo, e sobram só os arquivos dos perfis existentes); a remoção do perfil pelo adaptador do AoP levando os atributos de emissora; o perfil padrão no esquema; e a unidade da LLS do AoP gravando `services:announced` pela função. Termina com a auditoria vazia |
| `imagem` | Build da imagem `tv30-redis`, que já confere biblioteca, carga e auditoria (`confere-imagem.sh`); healthcheck igual ao do compose; carga pelas funções, com o id do perfil lido do template em UUID estrito e o avatar da carga igual ao nome do arquivo que o template traz em `thumbs/`; a versão do esquema na imagem igual à do `esquema.json`; recarga da biblioteca numa nova partida; e o morre-inteiro do commander (a morte dele derruba o container, com saída 1) |

Mais detalhes em [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis).

### Broker (`infra/mqtt-broker`): plugin C

O plugin C tem dois testes de unidade, que rodam **no build da imagem** do broker, antes de compilar o plugin (`infra/mqtt-broker/infra/Dockerfile`): `docker compose build mosquitto` falha se um deles falhar, e a imagem não sai.

| Arquivo | O que cobre |
|---|---|
| `plugin/tests/test_error_json.c` | A mensagem de `errors/<client_id>` (escape da RFC 8259, UTF-8 inválido trocado por U+FFFD, NUL no payload, tetos por campo, corte só entre unidades inteiras, `"truncated":true`, até 2047 bytes), o tópico (`+`, `#`, `/` e controles trocados por `_`, corte em fronteira UTF-8, até 255 bytes) e o escape do `id` do teste de latência. Cada mensagem gerada é conferida de novo pelo `json` do Python da imagem |
| `plugin/tests/test_json_payload.c` | A leitura do payload: exatamente um texto JSON, lido inteiro; sobra, NUL, comentário, aspas simples, vírgula sobrando e `\f`/`\v` recusados; espaço, tab, CR e LF em volta aceitos. O veredito de cada caso é conferido de novo pelo `json` do Python (`check_json_payload.py`) |

Dois testes de integração sobem um broker **descartável** (imagem com tag própria, rede própria, sem portas publicadas) e não tocam a stack. Precisam de Docker:

```bash
bash infra/mqtt-broker/plugin/tests/test_errors_json.sh       # errors/<client_id>, leitura do payload, teste de latência
bash infra/mqtt-broker/plugin/tests/test_all_validations.sh   # 1 publicação válida e 19 violações do sensor/comprehensive/test
```

- `test_errors_json.sh` (com o driver `errors_json_driver.py`): payloads com aspas, barra invertida, quebra de linha, controles, NUL, UTF-8 inválido e tamanhos acima do limite, conferindo cada mensagem de `errors/` com o `json` do Python e o tamanho; o payload inteiro (sobra, NUL, comentário viram `INVALID_JSON`; o UUID que começa com dígito passa em `aop/currentUser`); o fechamento do pop-up (`{"close":true}` nos tópicos do QR code e do PIN) entregue sem erro; o tópico de `errors/` com `+`, `#` e `/` no `client_id`; e a resposta do teste de latência com aspas e barra no `id`.
- `test_all_validations.sh`: a publicação válida chega ao assinante sem erro, e cada violação não é entregue e gera exatamente uma mensagem em `errors/test-client`, JSON válido, com o `details` esperado.
- Os dois aceitam `IMG=<imagem> NOBUILD=1` (imagem já construída) e `KEEP_IMG=1` (guarda a imagem construída).

**Sem teste de unidade:** o bcast (só a checagem de tipos) e o componente de exemplo do template. Os scripts abaixo cobrem parte deles na stack. O entrypoint do Redis é coberto pelo modo `imagem` acima.

---

## Suítes de `scripts/` (com a stack)

Pré-requisitos comuns:
- **Ambiente:** bash em Linux ou no WSL2, com `docker` (Compose v2) e `curl`. Com o Docker dentro do WSL, os scripts rodam assim: `wsl.exe -u root bash /mnt/d/<caminho do clone>/scripts/<script>.sh`. O `scripts/test-dev-host.sh` recusa rodar no Git Bash.
- **Stack:** a maioria espera a stack de pé, com o `.env` da raiz (`COMPOSE_PROFILES=mqtt,linux`). Para testar o código do clone, e não as imagens publicadas, suba antes com `docker compose up -d --build`.
- **Saída:** `test-auth.sh`, `test-dev-host.sh` e `test-template.sh` imprimem PASS/FAIL por verificação e saem com código diferente de zero se algo falhar. `test-consolidacao.sh`, `test-fase0.sh` e `test-bcast-shutdown.sh` só imprimem o que observaram, e a saída tem de ser lida.

### `scripts/test-auth.sh`: credenciais na borda

```bash
bash scripts/test-auth.sh
```

- **O que cobre:** a decisão de credencial do plugin `tv30-auth` contra a stack de pé, nas duas superfícies. Em `warn`, o que passa com aviso. Depois o script recria **só** a borda em `enforce` e cobre:
  - os erros 100, 104, 106, 107, 108 e 304, o CORS (preflight e `OPTIONS` sem preflight), a negociação de versão e a C.6.3.1, com o `serviceContextId` igual ao `globalServiceId`;
  - a C.6.8 com chaves HS256, HS512, RS256 e RS512, o isolamento entre serviços e a C.6.7.8/C.6.7.9, com as 20 APIs nas duas superfícies;
  - o 106 por superfície: na 44643, as rotas de uso exclusivo do cliente local e o `/tv3/authorize`; na 44642, o não local fora de `/tv3/authorize` e `/tv3/token`; a C.6.15.5 e as rotas por *handle* (só na 100.0) só para o cliente local; o 106 ao `Origin` associado também com token válido de outra classe;
  - as rotas por *handle* da 100.0 chegando ao tv3ws pelo caminho interno (o 101 do *handle* inexistente vem do tv3ws) e o `/v100.0/...` vindo do cliente com 100;
  - o 300 antes do bind-token e o associado em contexto de outra emissora;
  - o 304 da C.6.14.2 e da C.6.14.5: o script publica uma BAMT de teste retida (`tlm/lls/tv30-test-auth-<execução>/bamt`), no lugar do bcast, que o AoP grava em `services:announced` (sem o AoP, grava pela função `tv30_servicos_anunciados`), e confere a ordem 107 → 300 → 304 → bind-token, o 304 também em `warn` e ao associado, a tela do catálogo igual a `services:announced` e a `aop/services`, e o 304 depois de retirar a BAMT;
  - o associado de verdade: abre o users-test pelo AoP, usa a origem gravada e confere o 107 depois do ESC, que fecha a app;
  - o reuso de `clientid`, o pareamento real do não local (`qrcode` e `kex`), o `challenge-response` repetido depois do pareamento (102), `refresh-token=` e `challenge-response=` vazios no `/tv3/token` (105, sem invalidar o refresh token legítimo), o HTTPS na 44643 (`curl -k`) e o `serverCert` igual ao certificado;
  - o `/manifest` com os seis cabeçalhos em `Access-Control-Expose-Headers`, o 100 de `POST /tv3/{serviceContextId}/users` e o 107 do cliente desbloqueado que não voltou a `clients:authorized`, seguido da volta dele pela função `tv30_cliente_inclui_autorizado`;
  - o Redis congelado e o tv3ws parado ou lento.
- **O pop-up do pareamento:** o script lê do broker a primeira mensagem do tópico do QR code ou do PIN (a abertura) e não depende do prazo do pop-up.
- **A porta da 44643:** a superfície externa fica na 44643 do host por padrão. O script lê a porta de host com `docker port edgegateway 44643` e a lê de novo a cada recriação da borda, o que também vale com `EDGE_EXT_PUBLISH=44643`, em que o Docker escolhe a porta; `H_EXT` no ambiente fixa o endereço e desliga a descoberta.
- **O access token vem do fluxo real:** o script faz o papel do espectador e responde ao pop-up pelo broker. Chaves RSA e bind-tokens são gerados num container `node:20-alpine`.
- **Pré-requisitos:** os containers `edgegateway`, `tv3ws`, `redis` e `mqtt-broker` rodando; sem um deles, o script para logo no começo. Os casos do associado de verdade usam também o AoP e o bcast, e o script os pula, com uma linha explicativa, se o AoP não responder em `localhost:8080` (`AOP_URL` muda o endereço). Os casos de repasse pela 44643 usam o certificado do receptor, que o `tls-init` gera na subida.
- **O que ele mexe:** recria a borda, congela e para por alguns segundos o tv3ws e o Redis, grava chaves de teste no Redis, com sufixo único, e publica retidos no broker: o `aop/currentService` e a BAMT de teste. No fim, inclusive com erro ou Ctrl+C, volta a borda ao modo de antes, religa o que parou e desfaz o que gravou e publicou.
- **Esquema do Redis:** quando faz o papel de um serviço no Redis (serviço corrente, origem associada, bloqueio de cliente, serviços anunciados), o script grava pelas funções do esquema. No fim, depois de desfazer o que gravou, ele exige a auditoria vazia (`FCALL_RO tv30_auditoria 0`) e dá FAIL se não estiver. Se a auditoria já tinha achados antes da suíte, ele avisa no começo. Pede a imagem do `redis` com as funções; sem elas, para logo no começo com a mensagem.
- **Resultado esperado:** `== resultado: N PASS, 0 FAIL ==`.

### `scripts/test-dev-host.sh`: módulos rodando no host

```bash
./scripts/test-dev-host.sh               # cenários 1 a 5
./scripts/test-dev-host.sh --cenario 2   # um só
```

- **O que cobre:** as cinco combinações de [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local), com o módulo real (`npm ci && npm run dev`) fora do Docker. São elas: o tv3ws, o aop e o bcast, um de cada vez; os três ao mesmo tempo; e um componente novo falando direto com o Redis e o broker. Em cada uma, confere a conversa com o Redis e o broker a partir do ambiente do módulo, os logs de conexão dele e o caminho próprio do cenário, com uma prova negativa: o módulo é morto e o caminho para de responder. Nos cenários 2 a 4, confere a app users-test no host próprio, com o prefixo (`/graphicsAppProxy/users-test` e `Host: <rótulo>.apps.localhost:8080`), e o 302 do mesmo caminho no host do aop para essa URL (`checar_app_aberta`). Nos cenários 2 e 4, confere que o aop do host atende o MQTT por WebSocket em `/mqtt` e o repassa ao mosquitto em container (101 no pedido de WebSocket; `checar_mqtt_ws_aop`), com o `MQTT_WS_PORT` tirado da porta publicada da 9001; e o cenário 2 sobe o bcast com `BCAST_PUBLISH=8081:8081`, porque a 8081 do host não é fixa.
- **Pré-requisitos:** Linux ou WSL2 com Docker Engine, ou macOS com Colima. Precisa do bash 4 ou mais novo: no macOS, o `/bin/bash` é o 3.2 e o script para com um aviso; instale com `brew install bash` e rode `/opt/homebrew/bin/bash scripts/test-dev-host.sh`. Sem Node Linux no PATH, o script roda cada módulo num container `node:23-alpine` com `--network host`. O `npm ci` precisa alcançar o registro do npm; em rede corporativa que intercepta SSL, ele pode falhar dentro do container.
- **O que ele mexe:** para os containers dos módulos que vão para o host e recria a borda na variante certa. No fim, restaura a stack padrão se havia algum container do projeto de pé, ou a derruba, também quando é interrompido (Ctrl+C, `kill` ou o fechamento da sessão). Ao começar, remove os containers `tv30-devhost-*` que uma execução interrompida tenha deixado de pé (eles seguram a porta do módulo, como a 8081 do bcast). O cache do npm fica no volume `tv30-devhost-npm`, que o script não apaga.
- **Tempo:** cerca de 3 minutos com o cache do npm já cheio. A primeira execução, que baixa as dependências dos módulos, demora mais.
- **Resultado esperado:** `RESUMO (N PASS, 0 FAIL)`, com os logs dos módulos num diretório temporário indicado no fim.
- **Aviso esperado no cenário 1 e no 4:** a linha `info` `X-TV30-Auth-Warn com token valido` deve mostrar `107`, e não `ausente`, porque o token que o script assina tem `sub` `tv30-devhost-teste`, fora de `clients:authorized`. Não muda o PASS, que em `warn` não depende do aviso.

### `scripts/test-template.sh`: o template de componente

```bash
bash scripts/test-template.sh
```

Copia `templates/componente/` para uma pasta temporária, troca o nome, constrói e sobe o exemplo. Depois confere a entrada na `ginga_net`, a conversa com `redis` e `mosquitto` pelo nome do serviço, o `/health` na porta publicada e o morre-inteiro: o processo é morto, o container cai e o `restart` o traz de volta. No fim, remove o container, a imagem, a chave de teste e a pasta. Precisa da stack de pé (a rede `ginga_net` e os containers `redis` e `mqtt-broker`) e não mexe nela.

### `scripts/test-consolidacao.sh`: borda e Redis consolidados

```bash
bash scripts/test-consolidacao.sh
```

**Derruba a stack (`docker compose down --remove-orphans`) e a sobe de novo.** Depois mostra:
- os containers de pé;
- o healthcheck do Redis, a quantidade de perfis da carga inicial, a versão do esquema das funções (`FCALL_RO tv30_versao 0`), a auditoria do esquema (vazia, ou os achados) e o login do redis-commander (401 sem credencial, 200 com ela, senha errada recusada);
- a 6379 sem senha;
- que matar o commander derruba o container do Redis e que o `restart` o traz de volta, saudável, com o número de reinícios antes e depois;
- as duas superfícies e o Swagger;
- a diferença entre rota declarada (`POST /tv3/current-service/users`, que tem de chegar ao tv3ws) e caminho não declarado (`POST /tv3/users`, 100 no formato C.3.2) nas duas portas;
- o morre-inteiro da borda.

A saída tem de ser lida.

### `scripts/test-fase0.sh`: broker e AoP

```bash
bash scripts/test-fase0.sh
```

Sobe a stack, confere no log que o plugin do broker carregou, publica uma mensagem inválida num tópico de teste com esquema (`sensor/room1/temperature`, que tem de aparecer como `Validation FAILED`) e uma válida, e confere que as páginas `/` e `/profile/create` do AoP respondem 200. A saída tem de ser lida.

### `scripts/test-bcast-shutdown.sh`: parada limpa do bcast

```bash
bash scripts/test-bcast-shutdown.sh
```

Lista os tópicos `tlm/*` retidos no broker, para o bcast com tempo cronometrado, confere que os retidos foram limpos (o bcast publica vazio ao encerrar) e religa o bcast.

### `scripts/test-virgin-up.sh`: máquina virgem

```bash
bash scripts/test-virgin-up.sh
```

**Derruba a stack e a sobe do zero,** sem `tv3ws/.env` e sem `user-files/`, para simular uma máquina nova, e mostra os logs do preflight, da semeadura de `user-files` e do boot do tv3ws. No fim, inclusive com erro, devolve o `tv3ws/.env` e o conteúdo original de `user-files/` e recria o tv3ws e o aop. O próprio cabeçalho o chama de teste temporário.

---

## Outros testes no repositório Infra

Ficam fora de `scripts/`:
- **`infra/mqtt-broker/plugin/tests/test_errors_json.sh` e `test_all_validations.sh`:** os testes de integração do plugin do broker, num broker descartável (seção *Broker*, acima).
- **`infra/mqtt-broker/brokertimetest/`:** medição do tempo de resposta do broker com vários clientes em paralelo, pelos tópicos de teste de latência que o plugin responde ([Broker MQTT]({{ site.baseurl }}/broker-mqtt#teste-de-latência)).
