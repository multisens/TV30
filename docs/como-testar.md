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

| Teste | Precisa da stack? | Último resultado registrado | Tempo aproximado |
|---|---|---|---|
| tv3ws: `npm test` | não | 123 PASS, 0 FAIL (12/10, à noite, com a G8 e a G9: o `Content-Type` da C.6.14.6 e o aviso da C.6.14.5; eram 115 à tarde, com as correções do pareamento, dos arquivos e da troca de aplicação, e 78 em 11/10, com a B3; ver *Como os números foram obtidos*) | de 25 a 38 s (duas rodadas de 12/10, à noite) |
| tv3ws: `npx tsc --noEmit` | não | sem erro (12/10, à noite) | 7 s |
| aop: `npm test` | não | 77 PASS, 0 FAIL (12/10, à noite, com a G8 e a G9: o arquivo do avatar e o aviso `info`; eram 64 à tarde, com o pop-up de pareamento, o escape das views, as cores do BAM e o id codificado, e 37 em 11/10) | de 7 a 11 s |
| Redis: `bash infra/redis/test/run.sh tudo` (P4) | não (Docker, com containers descartáveis) | funções com 30 testes desde a noite de 12/10 (entraram os dois do avatar, G8; eram 28 desde 12/10, com o do UUID estrito, e 27 em 11/10, quando entrou o do volume de antes da F-3), e o modo `imagem` confere também o UUID estrito da carga, o avatar dela (o nome do arquivo que o template traz), a versão do esquema e o morre-inteiro do commander (C2). Resultado de 11/10, segunda parte: ok nos quatro modos (estático, funções, contrato e imagem). Resultado de 12/10, com o UUID estrito e as correções da tarde: ok nos quatro modos. Resultado de 12/10, à noite, com a G8 (esquema versão 4): ok nos quatro modos, com funções 30/30 | não cronometrado |
| bcast: `npx tsc --noEmit` | não | sem erro (12/10, à noite, com o avatar do users-test pela C.6.14.6) | 8 s |
| borda: `node --test generate.test.js` | não | 16 PASS, 0 FAIL (12/10, à noite, com o CORS do plugin: o bloco `cors` do `routes.json` e a saída do módulo CORS do KrakenD); antes, 15 PASS (12/10, à tarde, com as rotas 2.1 de `/device/{handle}` só para o cliente local), 14 PASS (12/10, com a C.6.15.5) e 13 PASS (11/10, com a A4) | 1 s |
| broker: testes de unidade do plugin C (`test_error_json.c`, `test_json_payload.c`) | não (rodam no build da imagem do broker) | desde 12/10: 144516 conferências e 0 falha no `test_error_json`, com 7877 mensagens conferidas de novo pelo `json` do Python; 5242 conferências e 0 falha no `test_json_payload`, com 2645 casos conferidos pelo Python (12/10, à tarde) | parte do build |
| broker: `test_errors_json.sh` e `test_all_validations.sh` | não (Docker, com broker descartável) | 494 PASS, 0 FAIL e 118 PASS, 0 FAIL (12/10, à tarde) | cerca de 30 s os dois, com a imagem já construída (pela hora dos logs) |
| borda: testes Go do plugin `tv30-auth` | não (Docker, para o compilador) | 74 funções de teste desde a noite de 12/10 (eram 73: saiu a `TestOptionsPassaSempre` e entraram a `TestPreflightRespondidoPelaBorda` e a `TestExposeHeadersEmTodaResposta`, do CORS do plugin, opção b do Luís). Resultado de 12/10, à noite: 73 PASS e 1 SKIP; antes, 72 PASS e 1 SKIP (11/10, segunda parte, e 12/10, à tarde, com as rotas 2.1) (o contrato, que só roda com `TV30_REDIS_TESTE`, pelo `infra/redis/test/run.sh contrato`); `gofmt` limpo e `go vet` ok | 15 s, com a imagem do compilador já baixada |
| borda: testes Go do anunciante SSDP | não (Docker, para o compilador) | 19 funções de teste desde 11/10 (eram 20; saiu a do IP local, com a B2). Resultado de 11/10, segunda parte: 19 PASS; `gofmt` limpo e `go vet` ok | 7 s, idem |
| `scripts/test-auth.sh` | sim | 225 PASS, 0 FAIL, com a borda na bridge e em rede do host (11/10, antes das decisões da segunda parte; a suíte ganhou casos da B3, da A4 e da E6). Resultado de 11/10, segunda parte: 227 PASS, 0 FAIL com a borda na bridge e 227 PASS, 0 FAIL com a borda em rede do host. Em 12/10 a suíte ganhou os casos da C.6.15.5: 233 PASS, 0 FAIL nos dois modos de rede. Na tarde de 12/10 ganhou os do parâmetro vazio, do desafio repetido e das rotas 2.1: 246 PASS, 0 FAIL nos dois modos de rede; à noite, com a G8 e a G9, os mesmos 246/0; depois, com o CORS do plugin (opção b do Luís: o preflight com a lista fora de ordem, com espaços e em caminho não declarado, e o `Expose-Headers` da borda), 250 PASS, 0 FAIL nos dois modos de rede | 1,5 min |
| `scripts/test-dev-host.sh` | sobe e desce o que precisa | 65 PASS, 0 FAIL, nos 5 cenários (11/10, antes das decisões da segunda parte; a suíte ganhou o `/mqtt` do aop do host nos cenários 2 e 4). Resultado de 11/10, segunda parte: 67 PASS, 0 FAIL. Em 12/10 (manhã, tarde e noite): 67 PASS, 0 FAIL, com o `/mqtt` do aop do host na 9003 | 3 min, com o cache do npm já cheio |
| `scripts/test-template.sh` | sim | 13 PASS, 0 FAIL (10/10). Resultado de 11/10, segunda parte: 13 PASS, 0 FAIL três vezes seguidas, depois de corrigida a janela do `docker events` do caso do kill -9 | 30 s |
| `scripts/test-consolidacao.sh` | recria a stack | saída conferida, sem falha (10/10; desde 11/10, a morte do commander tem de derrubar e trazer de volta o Redis, C2). Resultado de 11/10, segunda parte: sem falha; o Redis caiu e voltou (reinícios 0 → 1) quando o commander morreu | 1 min |
| `scripts/test-fase0.sh` | sobe a stack | saída conferida, sem falha (10/10); em 11/10, segunda parte, também sem falha | 20 s |
| `scripts/test-bcast-shutdown.sh` | sim | `stop` em 608 ms, retidos limpos (10/10); em 11/10, segunda parte, sem falha (o tempo do `stop` não foi registrado) | 25 s |
| `scripts/test-virgin-up.sh` | derruba e sobe do zero | não roda nas integrações recentes; sem resultado registrado | — |

Como os números foram obtidos:
- **Resultados das suítes:** as integrações de 10/10 (segunda leva) e de 11/10 (as duas partes), num Windows 11 com WSL2 e Docker Engine dentro do WSL, com as imagens construídas do código de cada dia. A de 11/10, segunda parte, também rodou os testes que precisam de Docker (Redis e Go), depois de recriar os volumes (`CHANGELOG.md`, entrada de 11/10).
- **Tempos das suítes:** saem da hora de gravação dos logs da integração de 10/10. Não foram cronometrados.
- **Testes de unidade:** os resultados e os tempos foram medidos em 10/10, no mesmo Windows, com Node 20.8.1. As imagens dos módulos usam Node 23. Os de 11/10 (segunda parte: `npm test` do tv3ws e do aop, `generate.test.js` e `tsc --noEmit` do tv3ws e do bcast) foram rodados de novo no mesmo Windows, com o mesmo Node, com o código das decisões daquele dia; o tempo do tv3ws é o que o `node --test` registrou.
- **Depois das decisões de 12/10:** só o `generate.test.js` foi rodado de novo (14 PASS, 0 FAIL, no mesmo Windows). O código do tv3ws, do aop e do bcast não mudou desde 11/10. Na integração do mesmo dia (WSL2): `infra/redis/test/run.sh tudo` ok, com funções 28/28; o build da imagem da borda, que roda o `go test` do plugin e do anunciante, ok; e as suítes de `scripts/` como nas linhas abaixo.
- **Depois das correções da tarde de 12/10** (defeitos achados pela auditoria; `CHANGELOG.md`): no mesmo Windows, com Node 20.8.1, `npm test` do tv3ws com 115 PASS e 0 FAIL e `npx tsc --noEmit` sem erro; `npm test` do aop com 64 PASS e 0 FAIL; `npx tsc --noEmit` do bcast sem erro; `node --test generate.test.js` com 15 PASS e 0 FAIL. Numa rodada intermediária do tv3ws (com 111 testes), o teste `EADDRINUSE na porta sorteada` (`multi-device.test.ts`) falhou uma vez e passou ao rodar o arquivo de novo e numa nova rodada completa: ele sorteia portas e depende de porta livre na máquina. Os testes do broker rodaram no WSL2, com Docker: os de unidade no build da imagem (com tag própria) e os dois de integração num broker descartável.
- **Depois das decisões da noite de 12/10** (G8 e G9, do Luís; `CHANGELOG.md`): no mesmo Windows, com Node 20.8.1, `npm test` do tv3ws com 123 PASS e 0 FAIL (o tempo é o que o `node --test` registrou) e `npx tsc --noEmit` sem erro; `npm test` do aop com 77 PASS e 0 FAIL; `npx tsc --noEmit` do bcast sem erro. No WSL2, com Docker, `infra/redis/test/run.sh tudo` ok, com funções 30/30.
- **Resultados mais recentes:** ficam também em [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes), no começo e em cada decisão, com o que cada rodada mediu.

---

## Testes de unidade (sem a stack)

Pré-requisitos: Node.js e `npm ci` na pasta do módulo. Nada aqui precisa de Redis, broker ou bcast de verdade.

### tv3ws

```bash
cd tv3ws
npm ci
npm test            # node --test com ts-node, os 13 arquivos de test/
npx tsc --noEmit    # checagem de tipos
```

Os dublês ficam em `tv3ws/test/helpers/`: `fake-redis.ts`, um Redis em memória com falha injetável, e `fake-mqtt.ts`, que entrega mensagens aos tratadores sem broker. Desde o P4, o `fake-redis.ts` imita o **efeito** das funções do Redis que o tv3ws chama (`FCALL`), sem conferir o esquema, e pode fazer uma função recusar como o Redis recusa (`recusar`). A conferência do esquema é testada num Redis real, em `infra/redis/test` (abaixo).

| Arquivo | O que cobre |
|---|---|
| `api-version.test.ts` | Negociação de versão (C.3.6): 100 com `API-Version: 2.1` para versão fora do conjunto, 101 com `2.0` para cabeçalho malformado, a versão negociada nas respostas e nos erros |
| `client-identification.test.ts` | `/tv3/authorize` e `/tv3/token` (C.6.1): primeira autorização, reuso de `clientid` com 101, refresh token, recusa no pop-up com 102, pareamento `qrcode` e `kex` (com o `key` e o PIN de quatro dígitos), `clients:authorized` e `clients:blocked`, Redis fora do ar com 404 `{"error":200}`. Desde 12/10, à tarde: parâmetro vazio ou só com espaços como ausente (105, sem credencial e sem pop-up; `pm=` vazio deixa o cliente local), o `challenge-response` repetido depois do sucesso (102, no `qrcode` e no `kex`) e o do cliente local (102), dois `/tv3/token` simultâneos com a mesma resposta (só um emite), a emissão que falha depois do desafio conferido (o material volta), e as comparações em bytes e em tempo constante do refresh token e da resposta ao desafio; e o `challenge-response` que não decifra ou vem repetido na URL (102, como o hash errado, no `qrcode` e no `kex`) |
| `pairing-popup.test.ts` | Desde 12/10, à tarde: o QR code e o PIN saem com o prazo de 120 s, ficam nos `/tv3/token` que falham e fecham (`{"close":true}`, depois da abertura, no mesmo tópico) no sucesso; o fim do pareamento de um cliente não fecha o pop-up de outro; a emissão que falha não fecha; o `/tv3/token` do cliente local não publica fechamento |
| `app-files.test.ts` | Desde 12/10, à tarde: a C.6.4.7 com caminho que sai do diretório da aplicação (`..`, codificado, barra invertida, NUL, absoluto e link simbólico) dando 305 sem o conteúdo de fora; arquivo dentro, com o MIME e a barra inicial opcional; inexistente com 305; a listagem da Tabela C.17 com `path` omitido, vazio, `/` ou de diretório; `appId` que não é o corrente; `Range` em vídeo (206); sem diretório da aplicação conhecido (305); e a troca de aplicação (a nova não serve o diretório da anterior antes do `.../path` dela; encerrar zera o diretório) |
| `current-service.test.ts` | `GET /tv3/current-service` (C.6.3.1): 300 sem serviço em uso, 200 com e sem `serviceId` |
| `manifest.test.ts` | O `/manifest` aponta para a borda (44642/44643), respeita `SSDP_ADVERTISE_HOST` e, desde 11/10 (B3), expõe ao navegador, em `Access-Control-Expose-Headers`, exatamente os cabeçalhos `Server-*` e `Device-*` que envia |
| `multi-device.test.ts` | Remote-device (C.6.15): registro e remoção, porta ocupada (`EADDRINUSE`), ponto de entrada local da 2.0 e da 2.1, Redis fora do ar |
| `redis-client.test.ts` | O cliente Redis falha rápido (D-0510-6): com a porta fechada, o comando rejeita em menos de 1,5 s; com um servidor que aceita e não responde, no `commandTimeout` de 1,5 s (o teste aceita de 1,4 s a 2 s, abaixo dos 2 s da borda) |
| `ssdp-config.test.ts`, `ssdp-interface.test.ts`, `ssdp-server.test.ts` | O anunciante SSDP do tv3ws, que só roda com o tv3ws sozinho no host: host anunciado, escolha da interface, avisos, falhas que encerram o processo e o `ssdp:byebye` |
| `user-service.test.ts` | Perfis só de leitura no tv3ws (D-0510-5), C.6.14.1, C.6.14.4, C.6.14.5 e C.6.14.6, falhas do Redis, escritas pelas funções e recusa de esquema com 404 `{"error":200}`. Desde 12/10, à tarde: na C.6.14.6, o caminho que sai de `USER_THUMBS` dá 305 sem o conteúdo, e o avatar só de perfis não visíveis no serviço, 405 (de ninguém, 305). Desde 12/10, à noite (G8 e G9): o `Content-Type` da C.6.14.6 pela extensão (`.svg`, `.png`, `.jpg`, `.jpeg`, `.webp`; outra, `application/octet-stream`), com os bytes e o `Content-Length` intactos; o avatar (nome do arquivo) devolvido como está pela C.6.14.2; e o aviso da C.6.14.5 em `aop/display/layers/popup/info`, sem retenção, com o nome do serviço corrente ou o id do serviço e o apelido (ou sem ele), que não sai quando nada muda nem quando a gravação falha (recusa da função, Redis fora, 101, 305, 405, 300), e cuja própria falha só vai para o log, com a API respondendo o sucesso |
| `redis-escritas.test.ts` | Teste estático do P4: o tv3ws só grava nas famílias do alcance pelo adaptador `src/redis-funcoes.ts` (regras em `infra/redis/test/escritas.js`; precisa do TV30 com os submódulos) |

### aop

```bash
cd aop
npm ci
npm test            # node --test test/redis.test.js test/app-hosts.test.js test/redis-escritas.test.js test/mqtt-ws.test.js test/popup.test.js test/views-escape.test.js
```

| Arquivo | O que cobre |
|---|---|
| `redis.test.js` | O cliente Redis que falha rápido (ioredis de verdade contra uma porta fechada e contra um servidor mudo), o `lastAccess` só de perfil existente, a criação de perfil (`POST /profile/create`), o despejo e, desde o P4, as escritas pelas funções do Redis, a conferência de idiomas e da visibilidade (400) e a recusa de esquema (404 `{"error":200}`). Desde 11/10 (F-3), o id criado em UUID (formato da RFC 9562, em minúsculas, com a versão de 1 a 8 e a variante da RFC 9562 que o esquema exige desde 12/10, e dois perfis com ids diferentes) e o despejo do perfil sem `lastAccess`, que conta como o mais antigo sem tirar instante do id. Desde 12/10, à noite (G8): a criação grava o SVG do formulário em `<thumbs>/<id>.svg`, com o `xmlns`, e o `avatar` é o nome do arquivo; avatar ausente ou que não é SVG grava o padrão; o perfil recusado pela função apaga o arquivo, e a falha ao gravar o arquivo não grava o perfil; o despejo apaga o arquivo do perfil despejado, e só ele |
| `mqtt-ws.test.js` | Desde 11/10 (C1): o `/mqtt` do AoP. A configuração (`ws://MQTT_HOST:MQTT_WS_PORT`, padrão 9001, valor inválido recusado); um upgrade WebSocket de verdade até um broker local, com quadros nos dois sentidos; o pacote `mqtt` da página conectando pelo AoP; 404 num host de aplicação e noutro caminho, sem nada chegar ao broker; 502 com o broker fora do ar; e a página da TV (`GET /`) conectando na própria origem, sem porta do broker |
| `redis-escritas.test.js` | Teste estático do P4: o AoP só grava no Redis pelo adaptador `src/redis-funcoes.js` |
| `popup.test.js` | Desde 12/10, à tarde: a camada gráfica de pop-ups (`public/js/popup.js`) num DOM de teste. O QR code e o PIN ficam até o `{"close":true}` no mesmo tópico, e saem pela trava sem ele; fechamento de outro tipo, no sim/não ou sem pop-up não muda nada; mensagem inválida não lança; o prazo de um pop-up que saiu ou foi substituído não fecha o seguinte; o sim/não publica a resposta e devolve as teclas à página; exceção no tratamento não escapa para o cliente MQTT; e o escape do `display-name` e do PIN (o QR code vai só para a biblioteca). Desde 12/10, à noite (G9): o aviso `info` na tela, sem botões nem resposta, escapado, fechando no prazo (5 s se o prazo for ausente, zero, negativo ou não numérico; o `{"close":true}` não o fecha); esperando o sim/não (a resposta ou o prazo dele), o QR code e o PIN (o fechamento ou a trava) e outro aviso; a fila de 3, com o excedente descartado e logado; e o aviso substituído por um sim/não, QR code ou PIN voltando à fila e aparecendo inteiro depois |
| `views-escape.test.js` | Desde 12/10, à tarde: `src/html.js` (`escapeHtml`, o SVG como `<img src="data:image/svg+xml;base64,...">`, com o `xmlns` acrescentado quando falta) e as páginas do catálogo (`/appcat`), da aplicação de abertura (`/btpapp`) e da escolha de perfil (`/prfchs`) com `appName`, `globalServiceId`, ícone, apelido e avatar hostis, mais o avatar padrão; `cssHexColor` e as cores do BAM e do gênero no `<style>` da aplicação de abertura (fora do formato, o padrão da view); e o id codificado na query de `selectService` e `selectProfile`. Desde 12/10, à noite (G8): o `avatarHtml` com o arquivo do avatar (o SVG em `data:image/svg+xml`, com o `xmlns` acrescentado quando falta, e PNG, JPG, JPEG e WEBP com o tipo da extensão e os bytes intactos) ou o padrão, sempre em `<img class="avatar">`; o padrão também para o avatar ausente, o SVG em linha de antes, o nome fora do formato (com diretório, `..`, outra extensão, maiúsculas, mais de 128 caracteres), o arquivo inexistente, o que não tem `<svg>`, o diretório, o maior que o teto (1 MB) e o link simbólico para fora do diretório, sem linha de erro no log |
| `app-hosts.test.js` | O P1.3: o rótulo DNS de cada app, a origem que o navegador manda, o registro e a remoção em `origins:associated` ao lançar, trocar e encerrar a app, o roteamento por `Host` (proxy para a app, 404 e 502), o prefixo `/graphicsAppProxy` na URL que a camada gráfica recebe e opcional no host da app (`stripPrefix`), e o caminho antigo `/graphicsAppProxy` no host do AoP, que desde 11/10 responde 302 para o host da app, ou 404 sem app, sem gravar origem. O "bcast" é um servidor HTTP local |

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

São 16 testes. Eles cobrem a derivação das superfícies a partir das `classes` (P1.9), a recusa do campo `surfaces`, que saiu do `routes.json`, os arquivos gerados (três variantes por superfície e os dois OpenAPI), as APIs que cada superfície lista na C.6.7.8/C.6.7.9 (F-2), desde 11/10 (A4) a saída de `POST /tv3/{serviceContextId}/users` de todas as configurações geradas, desde 12/10 a C.6.15.5 (`GET /tv3/remote-device/devices/{classId}`) só na interna, com as `classes` do cliente local, fora do plugin, dos endpoints e do OpenAPI da externa, e a API dela fora da lista da externa, e, desde a tarde de 12/10, as rotas 2.1 `GET` e `DELETE /tv3/remote-device/device/{handle}` do mesmo jeito, sem mudar as listas de APIs (elas não têm `api`), e, desde a noite de 12/10, o bloco `cors` do `routes.json` (só `allow_headers`, `expose_headers` e `max_age`, que chegam ao plugin das duas superfícies) e a ausência do módulo CORS do KrakenD (`security/cors`) nas configurações geradas. As contagens por superfície: 21 rotas na externa e 26 na interna, e 17 e 20 APIs (com a C.6.15.5 só na interna, 23 e 26 rotas; de 11/10 a 12/10, 24 e 26 rotas, e 18 e 20 APIs).

O plugin `tv30-auth` e o anunciante SSDP são Go, só com a biblioteca padrão. Rode os testes no mesmo compilador da imagem, o `krakend/builder:2.7.2` (Go 1.22.7, Alpine), num container:

```bash
docker run --rm -v "$PWD/infra/edgegateway/plugin:/src" -w /src krakend/builder:2.7.2 \
  sh -c 'go vet ./... && go test -count=1 ./...'
docker run --rm -v "$PWD/infra/edgegateway/ssdp:/src" -w /src krakend/builder:2.7.2 \
  sh -c 'go vet ./... && go test -count=1 ./...'
```

| Pasta | O que cobre |
|---|---|
| `plugin/` (73 funções de teste) | A decisão de credencial nas quatro etapas e os dois modos (`handler_test.go`; desde 11/10, a E6: fora de `clients:authorized`, sem `sub`, de volta ao conjunto, bloqueio antes, Redis fora e `warn`), o access token e o bind-token nas quatro frentes da C.4.1.4 (`jwt_test.go`), os formatos de chave (`keys_test.go`, com os casos de `testdata/keyformats.json`), a C.6.8 (`bindcontext_test.go`), a C.6.7.8/C.6.7.9 (`apiinfo_test.go`), o cliente Redis (`redis_test.go`), o casamento de rotas (`routes_test.go`), as superfícies da P1.9 (`surface_test.go`) e, desde o P4, o teste estático das escritas (`escritas_test.go`) e o contrato com as funções do Redis (`contrato_test.go`, que só roda com `TV30_REDIS_TESTE`, pelo `infra/redis/test/run.sh contrato`) |
| `ssdp/` (19 funções de teste, com subtestes) | O anunciante da borda: host e interface do anúncio, mensagens NOTIFY e respostas ao M-SEARCH (`ssdp_test.go`), a espera sem rede, os erros de configuração que encerram e o `ssdp:byebye` (`main_test.go`). Desde 11/10 (B2), o `SSDP_ADVERTISE_HOST` ausente ou vazio entre os erros de configuração, e o `SERVER_URL` e o IP local fora do host do anúncio |

**Os testes da borda também rodam no build da imagem.** O `infra/edgegateway/Dockerfile` roda `go vet` e `go test` nos estágios `plugin` e `ssdp`, e `node --test generate.test.js` no estágio `gen`. Então `docker compose build edgegateway` falha se algum deles falhar, e a imagem não sai.

### Redis (`infra/redis`): esquema nas escritas (P4)

Não precisa da stack. Precisa de Docker: os testes sobem containers descartáveis, com nome próprio, e os removem no fim. O container `redis` da stack não é tocado.

```bash
bash infra/redis/test/run.sh tudo     # ou um modo: funcoes | estatico | contrato | imagem
```

| Modo | O que cobre |
|---|---|
| `estatico` (`escritas.test.js`) | Nenhum serviço grava direto numa família do alcance fora do adaptador das funções: tv3ws, AoP, plugin da borda (Go) e carga inicial (Python) |
| `funcoes` (`funcoes.test.js`, 30 testes num `redis:7-alpine`: 18 escritos à mão e 12 gerados, um por família) | Aceitação; recusa de cada regra do esquema, com os casos **gerados** a partir do `esquema.json` (155 em 10/10, antes do tipo `uuid` da F-3) e conferência de que nada foi gravado; valores de fronteira; atomicidade; invariantes; a auditoria, que aponta cada tipo de problema gravado à mão e volta vazia; desde 11/10, o volume de antes da F-3 (id antigo: auditoria aponta, gravação recusada, despejo remove); e, desde 12/10, o UUID estrito (esquema versão 3): cada versão de 1 a 8 com cada variante 8, 9, `a` e `b` aceita, versão e variante fora disso recusadas com a mensagem da parte que falhou, o UUID nulo e o máximo recusados, e o id da carga e o `crypto.randomUUID()` do AoP aceitos; e, desde a noite de 12/10 (G8, esquema versão 4), o avatar como nome de arquivo: a regra do `esquema.json` decide igual à expressão do contrato nos valores de fronteira e em valores gerados, e o volume de antes da G8 (avatar em SVG em linha: auditoria aponta, regravação recusada, último acesso, atributos de emissora e despejo seguem) |
| `contrato` (`contrato.test.js` + `contrato_test.go`) | Os adaptadores e os gestores de verdade (auth-manager do tv3ws, gestor de perfis do AoP, `redisStore` da borda) contra as funções, inclusive, desde 11/10, a leitura de `clients:authorized` pela borda (E6) e, desde 12/10, o id do AoP em UUID versão 4 com a variante da RFC 9562 e a recusa do UUID nulo e da versão fora de 1 a 8 voltando ao serviço como erro `TV30ESQUEMA`, e, desde a noite de 12/10 (G8), o gestor de perfis do AoP gravando o avatar em `thumbs/` de um `USER_DATA_PATH` temporário (o `avatar` é `<id>.svg`, o arquivo tem o SVG do formulário, o despejo o apaga, e no fim sobram só os arquivos dos perfis existentes); termina com a auditoria vazia |
| `imagem` | Build da imagem `tv30-redis`, que já confere biblioteca, carga e auditoria (`confere-imagem.sh`); healthcheck igual ao do compose; carga pelas funções, com o id do perfil lido do template em UUID (F-3), estrito desde 12/10, e, desde a noite de 12/10 (G8), o avatar da carga igual ao nome do arquivo que o template traz em `thumbs/`; a versão do esquema na imagem igual à do `esquema.json`; recarga da biblioteca numa nova partida; e, desde 11/10, o morre-inteiro do commander (C2: a morte dele derruba o container, com saída 1) |

Mais detalhes em `infra/redis/README.md` e em [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis).

### Broker (`infra/mqtt-broker`): plugin C

Desde 12/10, o plugin C tem dois testes de unidade, que rodam **no build da imagem** do broker, antes de compilar o plugin (`infra/mqtt-broker/infra/Dockerfile`): `docker compose build mosquitto` falha se um deles falhar, e a imagem não sai.

| Arquivo | O que cobre |
|---|---|
| `plugin/tests/test_error_json.c` | A mensagem de `errors/<client_id>` (escape da RFC 8259, UTF-8 inválido trocado por U+FFFD, NUL no payload, tetos por campo, corte só entre unidades inteiras, `"truncated":true`, até 2047 bytes), o tópico (`+`, `#`, `/` e controles trocados por `_`, corte em fronteira UTF-8, até 255 bytes) e o escape do `id` do teste de latência. Cada mensagem gerada é conferida de novo pelo `json` do Python da imagem |
| `plugin/tests/test_json_payload.c` | A leitura do payload: exatamente um texto JSON, lido inteiro; sobra, NUL, comentário, aspas simples, vírgula sobrando e `\f`/`\v` recusados; espaço, tab, CR e LF em volta aceitos. O veredito de cada caso é conferido de novo pelo `json` do Python (`check_json_payload.py`) |

Dois testes de integração sobem um broker **descartável** (imagem com tag própria, rede própria, sem portas publicadas) e não tocam a stack. Precisam de Docker:

```bash
bash infra/mqtt-broker/plugin/tests/test_errors_json.sh       # errors/<client_id>, leitura do payload, teste de latência
bash infra/mqtt-broker/plugin/tests/test_all_validations.sh   # 1 publicação válida e 19 violações do sensor/comprehensive/test
```

- `test_errors_json.sh` (com o driver `errors_json_driver.py`): payloads com aspas, barra invertida, quebra de linha, controles, NUL, UTF-8 inválido e tamanhos acima do limite, conferindo cada mensagem de `errors/` com o `json` do Python e o tamanho; o payload inteiro (sobra, NUL, comentário viram `INVALID_JSON`; o UUID que começa com dígito passa em `aop/currentUser`); o fechamento do pop-up (`{"close":true}` nos tópicos do QR code e do PIN) entregue sem erro; o tópico de `errors/` com `+`, `#` e `/` no `client_id`; e a resposta do teste de latência com aspas e barra no `id`. Em 12/10, à tarde: 494 PASS e 0 FAIL; contra a imagem de antes das correções, 58 FAIL.
- `test_all_validations.sh`: a publicação válida chega ao assinante sem erro, e cada violação não é entregue e gera exatamente uma mensagem em `errors/test-client`, JSON válido, com o `details` esperado. Em 12/10, à tarde: 118 PASS e 0 FAIL.
- Os dois aceitam `IMG=<imagem> NOBUILD=1` (imagem já construída) e `KEEP_IMG=1` (guarda a imagem construída).

**Sem teste de unidade:** o bcast (só a checagem de tipos) e o componente de exemplo do template. Os scripts abaixo cobrem parte deles na stack. O entrypoint do Redis é coberto pelo modo `imagem` acima.

---

## Suítes de `scripts/` (com a stack)

Pré-requisitos comuns:
- **Ambiente:** bash em Linux ou no WSL2, com `docker` (Compose v2) e `curl`. Nesta máquina do projeto, o Docker roda dentro do WSL, e os scripts rodam assim: `wsl.exe -u root bash /mnt/d/<caminho do clone>/scripts/<script>.sh`. O `scripts/test-dev-host.sh` recusa rodar no Git Bash.
- **Stack:** a maioria espera a stack de pé, com o `.env` da raiz (`COMPOSE_PROFILES=mqtt,linux`). Para testar o código do clone, e não as imagens publicadas, suba antes com `docker compose up -d --build`.
- **Saída:** `test-auth.sh`, `test-dev-host.sh` e `test-template.sh` imprimem PASS/FAIL por verificação e saem com código diferente de zero se algo falhar. `test-consolidacao.sh`, `test-fase0.sh` e `test-bcast-shutdown.sh` só imprimem o que observaram, e a saída tem de ser lida.

### `scripts/test-auth.sh`: credenciais na borda

```bash
bash scripts/test-auth.sh
```

- **O que cobre:** a decisão de credencial do plugin `tv30-auth` contra a stack de pé, nas duas superfícies. Em `warn`, o que passa com aviso. Depois o script recria **só** a borda em `enforce` e cobre os erros 100, 104, 106, 107 e 108, o CORS, a C.6.8 com chaves HS256, HS512, RS256 e RS512, o isolamento entre serviços, a C.6.7.8/C.6.7.9, a negociação de versão, a C.6.3.1, as superfícies da P1.9 e o associado de verdade da P1.3 (abre o users-test pelo AoP, usa a origem gravada e confere o 107 depois do ESC). Também cobre o reuso de `clientid`, o pareamento real do não local (`qrcode` e `kex`), o Redis congelado e o tv3ws parado ou lento. Desde 11/10 (decisões do Luís, segunda parte): o `/manifest` com os seis cabeçalhos em `Access-Control-Expose-Headers` (B3), o 100 de `POST /tv3/{serviceContextId}/users` em todos os casos que antes esperavam 104, 108 ou sucesso (A4) e o 107 do cliente desbloqueado que não voltou a `clients:authorized`, seguido da volta dele pela função `tv30_cliente_inclui_autorizado` (E6). Desde 12/10 (decisão do Luís), a C.6.15.5 só para o cliente local: o não local recebe 106 da borda em `GET /tv3/remote-device/devices/{classId}` na 44642 e 100 na 44643, onde a rota não existe; o local passa na 44642; e `GET /tv3/api-info/tv3ws-remotedevice-communication` dá 101 na 44643. O código que o não local recebe na 44642 está pendente com o Joel (F-1, [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes)). Desde a tarde de 12/10 (correções e segunda decisão do Luís): `refresh-token=` e `challenge-response=` vazios no `/tv3/token` dão 105 e não invalidam o refresh token legítimo; o `challenge-response` repetido depois do pareamento dá 102 (`qrcode` e `kex`); e as rotas 2.1 `GET` e `DELETE /tv3/remote-device/device/x` dão 106 ao não local na 44642 e 100 na 44643, com o `GET` do cliente local passando na 44642.
- **O pop-up do pareamento:** o script lê do broker a primeira mensagem do tópico do QR code ou do PIN (a abertura) e não depende do prazo do pop-up, que passou de 1 s a 120 s em 12/10.
- **A porta da 44643:** a superfície externa fica na 44643 do host por padrão (desde 12/10, também na bridge). O script lê a porta de host com `docker port edgegateway 44643` e a lê de novo a cada recriação da borda, o que segue valendo com `EDGE_EXT_PUBLISH=44643`, em que o Docker escolhe a porta (de 11/10 a 12/10, o padrão); `H_EXT` no ambiente fixa o endereço e desliga a descoberta.
- **O access token vem do fluxo real:** o script faz o papel do espectador e responde ao pop-up pelo broker. Chaves RSA e bind-tokens são gerados num container `node:20-alpine`.
- **Pré-requisitos:** os containers `edgegateway`, `tv3ws`, `redis` e `mqtt-broker` rodando; sem um deles, o script para logo no começo. Os casos do associado de verdade (P1.3) usam também o AoP e o bcast, e o script os pula, com uma linha explicativa, se o AoP não responder em `localhost:8080` (`AOP_URL` muda o endereço). Os casos de repasse pela 44643 precisam do HTTPS do tv3ws (`HTTPS_KEY` e `HTTPS_CERT` no `tv3ws/.env`); sem ele, o script os pula com uma linha explicativa, em vez de dar FAIL.
- **O que ele mexe:** recria a borda, congela e para por alguns segundos o tv3ws e o Redis, e grava chaves de teste no Redis e um retido no broker, todos com sufixo único. No fim, inclusive com erro ou Ctrl+C, volta a borda ao modo de antes, religa o que parou e desfaz o que gravou.
- **Esquema do Redis (P4, desde 10/10):** quando faz o papel de um serviço no Redis (serviço corrente, origem associada, bloqueio de cliente), o script grava pelas funções do esquema. No fim, depois de desfazer o que gravou, ele exige a auditoria vazia (`FCALL_RO tv30_auditoria 0`) e dá FAIL se não estiver. Se a auditoria já tinha achados antes da suíte (um volume de antes do P4, por exemplo), ele avisa no começo. Pede a imagem do `redis` com as funções; sem elas, para logo no começo com a mensagem. Em 11/10, a auditoria saiu vazia no começo e no fim, nos dois modos de rede da borda.
- **Resultado esperado:** `== resultado: N PASS, 0 FAIL ==`. Em 11/10, depois do P1.3, da P1.9 e do P4 e antes das decisões da segunda parte, foram 225 PASS e 0 FAIL com a borda na bridge e 225 PASS e 0 FAIL com a borda em rede do host (override do SSDP, sem reinício da borda). Depois das decisões da segunda parte: 227 PASS e 0 FAIL com a borda na bridge e 227 PASS e 0 FAIL com a borda em rede do host, sem reinício da borda. Com as decisões de 12/10 (os casos da C.6.15.5 e a 44643 fixa na bridge): 233 PASS e 0 FAIL nos dois modos. Com os casos da tarde de 12/10 (parâmetro vazio, desafio repetido e rotas 2.1): 246 PASS e 0 FAIL nos dois modos. Com os do CORS do plugin (noite de 12/10): 250 PASS e 0 FAIL nos dois modos.

### `scripts/test-dev-host.sh`: módulos rodando no host

```bash
./scripts/test-dev-host.sh               # cenários 1 a 5
./scripts/test-dev-host.sh --cenario 2   # um só
```

- **O que cobre:** as cinco combinações de [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local), com o módulo real (`npm ci && npm run dev`) fora do Docker. São elas: o tv3ws, o aop e o bcast, um de cada vez; os três ao mesmo tempo; e um componente novo falando direto com o Redis e o broker. Em cada uma, confere a conversa com o Redis e o broker a partir do ambiente do módulo, os logs de conexão dele e o caminho próprio do cenário, com uma prova negativa: o módulo é morto e o caminho para de responder. Nos cenários 2 a 4, desde 11/10, confere a app users-test no host próprio, com o prefixo (`/graphicsAppProxy/users-test` e `Host: <rótulo>.apps.localhost:8080`), e o 302 do mesmo caminho no host do aop para essa URL (`checar_app_aberta`). Nos cenários 2 e 4, desde 11/10 (C1), confere que o aop do host atende o MQTT por WebSocket em `/mqtt` e o repassa ao mosquitto em container (101 no pedido de WebSocket; `checar_mqtt_ws_aop`), com o `MQTT_WS_PORT` tirado da porta publicada da 9001; e o cenário 2 sobe o bcast com `BCAST_PUBLISH=8081:8081`, porque a 8081 do host deixou de ser fixa.
- **Pré-requisitos:** Linux ou WSL2 com Docker Engine. Sem Node Linux no PATH, o script roda cada módulo num container `node:23-alpine` com `--network host`. O `npm ci` precisa alcançar o registro do npm; em rede corporativa que intercepta SSL, ele pode falhar dentro do container.
- **O que ele mexe:** para os containers dos módulos que vão para o host e recria a borda na variante certa. No fim, restaura a stack padrão se havia algum container do projeto de pé, ou a derruba, também quando é interrompido (Ctrl+C, `kill` ou o fechamento da sessão, desde a noite de 12/10). Ao começar, remove os containers `tv30-devhost-*` que uma execução interrompida tenha deixado de pé (eles seguram a porta do módulo, como a 8081 do bcast). O cache do npm fica no volume `tv30-devhost-npm`, que o script não apaga.
- **Tempo:** cerca de 3 minutos em 10/10, com o cache do npm já cheio. A primeira execução, que baixa as dependências dos módulos, demora mais; esse tempo não foi medido.
- **Resultado esperado:** `RESUMO (N PASS, 0 FAIL)`, com os logs dos módulos num diretório temporário indicado no fim. Em 11/10, depois das confirmações do Luís (host próprio com o prefixo `/graphicsAppProxy`, 302 do caminho antigo), 65 PASS e 0 FAIL nos 5 cenários. Antes delas eram 66: no cenário 3, as duas provas negativas (host da app e caminho antigo) viraram uma, porque o caminho antigo só redireciona. Depois das decisões da segunda parte de 11/10: 67 PASS e 0 FAIL (os dois a mais são o `/mqtt` do aop do host, nos cenários 2 e 4). Em 12/10 o script só mudou em comentário: 67 PASS e 0 FAIL, com o `/mqtt` do aop do host na 9003 (o `.env` local fixava `MQTT_WS_PUBLISH=9003:9001`).
- **Aviso esperado no cenário 1 e no 4, desde a E6 (11/10):** a linha `info` `X-TV30-Auth-Warn com token valido` deve mostrar `107`, e não `ausente`, porque o token que o script assina tem `sub` `tv30-devhost-teste`, fora de `clients:authorized` (pelo código; não muda o PASS, que em `warn` não depende do aviso).

### `scripts/test-template.sh`: o template de componente

```bash
bash scripts/test-template.sh
```

Copia `templates/componente/` para uma pasta temporária, troca o nome, constrói e sobe o exemplo. Depois confere a entrada na `ginga_net`, a conversa com `redis` e `mosquitto` pelo nome do serviço, o `/health` na porta publicada e o morre-inteiro: o processo é morto, o container cai e o `restart` o traz de volta. No fim, remove o container, a imagem, a chave de teste e a pasta. Precisa da stack de pé (a rede `ginga_net` e os containers `redis` e `mqtt-broker`) e não mexe nela. Em 10/10: 13 PASS e 0 FAIL.

### `scripts/test-consolidacao.sh`: borda e Redis consolidados

```bash
bash scripts/test-consolidacao.sh
```

**Derruba a stack (`docker compose down --remove-orphans`) e a sobe de novo.** Depois mostra:
- os containers de pé;
- o healthcheck do Redis, a quantidade de perfis da carga inicial, a versão do esquema das funções (`FCALL_RO tv30_versao 0`; 4 desde a noite de 12/10, G8, com a imagem do `redis` construída do código atual; 3 de 12/10 até ali), a auditoria do esquema (vazia, ou os achados) e o login do redis-commander (401 sem credencial, 200 com ela, senha errada recusada);
- a 6379 sem senha;
- que matar o commander derruba o container do Redis e que o `restart` o traz de volta, saudável, com o número de reinícios antes e depois (desde 11/10, C2; até ali, o script mostrava que o banco seguia sem o commander);
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

Lista os tópicos `tlm/*` retidos no broker, para o bcast com tempo cronometrado, confere que os retidos foram limpos (o bcast publica vazio ao encerrar) e religa o bcast. Em 10/10, a parada levou 608 ms, com saída 0, e os 9 retidos sumiram e voltaram depois do religamento.

### `scripts/test-virgin-up.sh`: máquina virgem

```bash
bash scripts/test-virgin-up.sh
```

**Derruba a stack e a sobe do zero,** sem `tv3ws/.env` e sem `user-files/`, para simular uma máquina nova, e mostra os logs do preflight, da semeadura de `user-files` e do boot do tv3ws. No fim, inclusive com erro, devolve o `tv3ws/.env` e o conteúdo original de `user-files/` e recria o tv3ws e o aop. O próprio cabeçalho o chama de teste temporário, e ele não roda nas integrações recentes.

---

## Outros testes no repositório Infra

Ficam fora de `scripts/` e não rodam nas integrações:
- **`infra/mqtt-broker/plugin/tests/test_errors_json.sh` e `test_all_validations.sh`:** os testes de integração do plugin do broker, num broker descartável (seção *Broker*, acima). Até 12/10, o `test_all_validations.sh` chamava o container `mosquitto-plugin`, nome anterior ao compose atual, e esperava o erro em `errors/validation`; não rodava contra a stack de hoje.
- **`infra/mqtt-broker/brokertimetest/`:** medição do tempo de resposta do broker com vários clientes em paralelo. Os resultados registrados ali são de 21/08, quando o plugin ainda se conectava ao Redis na subida; o próprio registro (`RESULTADOS_2026-08-21.md`) diz que a autorização já estava desligada no código e que o Redis não era consultado por mensagem, então os números cobrem só o callback e a validação de esquema. Desde 19/09 o plugin não tem controle de acesso nem cliente Redis (`infra/mqtt-broker/plugin/src/mosquitto_plugin.c`).
