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
| tv3ws: `npm test` | não | 78 PASS, 0 FAIL (11/10, com a B3) | 22 s |
| tv3ws: `npx tsc --noEmit` | não | sem erro (11/10, com a B3) | 7 s |
| aop: `npm test` | não | 37 PASS, 0 FAIL (11/10, com o `/mqtt` da C1 e o UUID da F-3) | 9 s |
| Redis: `bash infra/redis/test/run.sh tudo` (P4) | não (Docker, com containers descartáveis) | funções com 27 testes desde 11/10 (eram 26: entrou o do volume de antes da F-3), e o modo `imagem` confere também o UUID da carga e o morre-inteiro do commander (C2). Resultado de 11/10, segunda parte: ok nos quatro modos (estático, funções, contrato e imagem) | não cronometrado |
| bcast: `npx tsc --noEmit` | não | sem erro (11/10, com o id novo do perfil na webmedia) | 8 s |
| borda: `node --test generate.test.js` | não | 13 PASS, 0 FAIL (11/10, com a A4) | 1 s |
| borda: testes Go do plugin `tv30-auth` | não (Docker, para o compilador) | 73 funções de teste desde 11/10 (eram 72; entrou a da E6, `TestDecisaoClientesAutorizados`). Resultado de 11/10, segunda parte: 72 PASS e 1 SKIP (o contrato, que só roda com `TV30_REDIS_TESTE`, pelo `infra/redis/test/run.sh contrato`); `gofmt` limpo e `go vet` ok | 15 s, com a imagem do compilador já baixada |
| borda: testes Go do anunciante SSDP | não (Docker, para o compilador) | 19 funções de teste desde 11/10 (eram 20; saiu a do IP local, com a B2). Resultado de 11/10, segunda parte: 19 PASS; `gofmt` limpo e `go vet` ok | 7 s, idem |
| `scripts/test-auth.sh` | sim | 225 PASS, 0 FAIL, com a borda na bridge e em rede do host (11/10, antes das decisões da segunda parte; a suíte ganhou casos da B3, da A4 e da E6). Resultado de 11/10, segunda parte: 227 PASS, 0 FAIL com a borda na bridge e 227 PASS, 0 FAIL com a borda em rede do host | 1,5 min |
| `scripts/test-dev-host.sh` | sobe e desce o que precisa | 65 PASS, 0 FAIL, nos 5 cenários (11/10, antes das decisões da segunda parte; a suíte ganhou o `/mqtt` do aop do host nos cenários 2 e 4). Resultado de 11/10, segunda parte: 67 PASS, 0 FAIL | 3 min, com o cache do npm já cheio |
| `scripts/test-template.sh` | sim | 13 PASS, 0 FAIL (10/10) | 30 s |
| `scripts/test-consolidacao.sh` | recria a stack | saída conferida, sem falha (10/10; desde 11/10, a morte do commander tem de derrubar e trazer de volta o Redis, C2). Resultado de 11/10, segunda parte: sem falha; o Redis caiu e voltou (reinícios 0 → 1) quando o commander morreu | 1 min |
| `scripts/test-fase0.sh` | sobe a stack | saída conferida, sem falha (10/10) | 20 s |
| `scripts/test-bcast-shutdown.sh` | sim | `stop` em 608 ms, retidos limpos (10/10) | 25 s |
| `scripts/test-virgin-up.sh` | derruba e sobe do zero | não roda nas integrações recentes; sem resultado registrado | — |

Como os números foram obtidos:
- **Resultados das suítes:** a integração da segunda leva, em 10/10, num Windows 11 com WSL2 e Docker Engine dentro do WSL, com as imagens construídas do código daquele dia.
- **Tempos das suítes:** saem da hora de gravação dos logs dessa integração. Não foram cronometrados.
- **Testes de unidade:** os resultados e os tempos foram medidos em 10/10, no mesmo Windows, com Node 20.8.1. As imagens dos módulos usam Node 23. Os de 11/10 (segunda parte: `npm test` do tv3ws e do aop, `generate.test.js` e `tsc --noEmit` do tv3ws e do bcast) foram rodados de novo no mesmo Windows, com o mesmo Node, com o código das decisões daquele dia; o tempo do tv3ws é o que o `node --test` registrou. Os testes que precisam de Docker (Redis e Go) e as suítes de `scripts/` ainda não têm resultado registrado depois dessas decisões.
- **Resultados mais recentes:** ficam também em [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes), no começo e em cada decisão, com o que cada rodada mediu.

---

## Testes de unidade (sem a stack)

Pré-requisitos: Node.js e `npm ci` na pasta do módulo. Nada aqui precisa de Redis, broker ou bcast de verdade.

### tv3ws

```bash
cd tv3ws
npm ci
npm test            # node --test com ts-node, os 11 arquivos de test/
npx tsc --noEmit    # checagem de tipos
```

Os dublês ficam em `tv3ws/test/helpers/`: `fake-redis.ts`, um Redis em memória com falha injetável, e `fake-mqtt.ts`, que entrega mensagens aos tratadores sem broker. Desde o P4, o `fake-redis.ts` imita o **efeito** das funções do Redis que o tv3ws chama (`FCALL`), sem conferir o esquema, e pode fazer uma função recusar como o Redis recusa (`recusar`). A conferência do esquema é testada num Redis real, em `infra/redis/test` (abaixo).

| Arquivo | O que cobre |
|---|---|
| `api-version.test.ts` | Negociação de versão (C.3.6): 100 com `API-Version: 2.1` para versão fora do conjunto, 101 com `2.0` para cabeçalho malformado, a versão negociada nas respostas e nos erros |
| `client-identification.test.ts` | `/tv3/authorize` e `/tv3/token` (C.6.1): primeira autorização, reuso de `clientid` com 101, refresh token, recusa no pop-up com 102, pareamento `qrcode` e `kex` (com o `key` e o PIN de quatro dígitos), `clients:authorized` e `clients:blocked`, Redis fora do ar com 404 `{"error":200}` |
| `current-service.test.ts` | `GET /tv3/current-service` (C.6.3.1): 300 sem serviço em uso, 200 com e sem `serviceId` |
| `manifest.test.ts` | O `/manifest` aponta para a borda (44642/44643), respeita `SSDP_ADVERTISE_HOST` e, desde 11/10 (B3), expõe ao navegador, em `Access-Control-Expose-Headers`, exatamente os cabeçalhos `Server-*` e `Device-*` que envia |
| `multi-device.test.ts` | Remote-device (C.6.15): registro e remoção, porta ocupada (`EADDRINUSE`), ponto de entrada local da 2.0 e da 2.1, Redis fora do ar |
| `redis-client.test.ts` | O cliente Redis falha rápido (D-0510-6): porta fechada e servidor que não responde rejeitam em até 1,5 s |
| `ssdp-config.test.ts`, `ssdp-interface.test.ts`, `ssdp-server.test.ts` | O anunciante SSDP do tv3ws, que só roda com o tv3ws sozinho no host: host anunciado, escolha da interface, avisos, falhas que encerram o processo e o `ssdp:byebye` |
| `user-service.test.ts` | Perfis só de leitura no tv3ws (D-0510-5), C.6.14.1, C.6.14.4 e C.6.14.5, falhas do Redis, escritas pelas funções e recusa de esquema com 404 `{"error":200}` |
| `redis-escritas.test.ts` | Teste estático do P4: o tv3ws só grava nas famílias do alcance pelo adaptador `src/redis-funcoes.ts` (regras em `infra/redis/test/escritas.js`; precisa do TV30 com os submódulos) |

### aop

```bash
cd aop
npm ci
npm test            # node --test test/redis.test.js test/app-hosts.test.js test/redis-escritas.test.js test/mqtt-ws.test.js
```

| Arquivo | O que cobre |
|---|---|
| `redis.test.js` | O cliente Redis que falha rápido (ioredis de verdade contra uma porta fechada e contra um servidor mudo), o `lastAccess` só de perfil existente, a criação de perfil (`POST /profile/create`), o despejo e, desde o P4, as escritas pelas funções do Redis, a conferência de idiomas e da visibilidade (400) e a recusa de esquema (404 `{"error":200}`). Desde 11/10 (F-3), o id criado em UUID (formato da RFC 9562, em minúsculas, dois perfis com ids diferentes) e o despejo do perfil sem `lastAccess`, que conta como o mais antigo sem tirar instante do id |
| `mqtt-ws.test.js` | Desde 11/10 (C1): o `/mqtt` do AoP. A configuração (`ws://MQTT_HOST:MQTT_WS_PORT`, padrão 9001, valor inválido recusado); um upgrade WebSocket de verdade até um broker local, com quadros nos dois sentidos; o pacote `mqtt` da página conectando pelo AoP; 404 num host de aplicação e noutro caminho, sem nada chegar ao broker; 502 com o broker fora do ar; e a página da TV (`GET /`) conectando na própria origem, sem porta do broker |
| `redis-escritas.test.js` | Teste estático do P4: o AoP só grava no Redis pelo adaptador `src/redis-funcoes.js` |
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

Eles cobrem a derivação das superfícies a partir das `classes` (P1.9), a recusa do campo `surfaces`, que saiu do `routes.json`, e, desde 11/10 (A4), a saída de `POST /tv3/{serviceContextId}/users` de todas as configurações geradas, com as contagens por superfície: 24 rotas na externa e 26 na interna, e 18 e 20 APIs.

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
| `funcoes` (`funcoes.test.js`, 27 testes num `redis:7-alpine`) | Aceitação; recusa de cada regra do esquema, com os casos **gerados** a partir do `esquema.json` (155 em 10/10, antes do tipo `uuid` da F-3) e conferência de que nada foi gravado; valores de fronteira; atomicidade; invariantes; a auditoria, que aponta cada tipo de problema gravado à mão e volta vazia; e, desde 11/10, o volume de antes da F-3 (id antigo: auditoria aponta, gravação recusada, despejo remove) |
| `contrato` (`contrato.test.js` + `contrato_test.go`) | Os adaptadores e os gestores de verdade (auth-manager do tv3ws, gestor de perfis do AoP, `redisStore` da borda) contra as funções, inclusive, desde 11/10, a leitura de `clients:authorized` pela borda (E6); termina com a auditoria vazia |
| `imagem` | Build da imagem `tv30-redis`, que já confere biblioteca, carga e auditoria (`confere-imagem.sh`); healthcheck igual ao do compose; carga pelas funções, com o id do perfil em UUID lido do template (F-3); recarga da biblioteca numa nova partida; e, desde 11/10, o morre-inteiro do commander (C2: a morte dele derruba o container, com saída 1) |

Mais detalhes em `infra/redis/README.md` e em [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis).

**Sem teste de unidade:** o bcast (só a checagem de tipos), o componente de exemplo do template e o plugin C do broker. Os scripts abaixo cobrem parte deles na stack. O entrypoint do Redis é coberto pelo modo `imagem` acima.

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

- **O que cobre:** a decisão de credencial do plugin `tv30-auth` contra a stack de pé, nas duas superfícies. Em `warn`, o que passa com aviso. Depois o script recria **só** a borda em `enforce` e cobre os erros 100, 104, 106, 107 e 108, o CORS, a C.6.8 com chaves HS256, HS512, RS256 e RS512, o isolamento entre serviços, a C.6.7.8/C.6.7.9, a negociação de versão, a C.6.3.1, as superfícies da P1.9 e o associado de verdade da P1.3 (abre o users-test pelo AoP, usa a origem gravada e confere o 107 depois do ESC). Também cobre o reuso de `clientid`, o pareamento real do não local (`qrcode` e `kex`), o Redis congelado e o tv3ws parado ou lento. Desde 11/10 (decisões do Luís, segunda parte): o `/manifest` com os seis cabeçalhos em `Access-Control-Expose-Headers` (B3), o 100 de `POST /tv3/{serviceContextId}/users` em todos os casos que antes esperavam 104, 108 ou sucesso (A4) e o 107 do cliente desbloqueado que não voltou a `clients:authorized`, seguido da volta dele pela função `tv30_cliente_inclui_autorizado` (E6).
- **A 44643 na bridge:** desde a C1 (11/10), o script lê a porta de host da superfície externa com `docker port edgegateway 44643` e a lê de novo a cada recriação da borda; `H_EXT` no ambiente fixa o endereço e desliga a descoberta.
- **O access token vem do fluxo real:** o script faz o papel do espectador e responde ao pop-up pelo broker. Chaves RSA e bind-tokens são gerados num container `node:20-alpine`.
- **Pré-requisitos:** os containers `edgegateway`, `tv3ws`, `redis` e `mqtt-broker` rodando. Os casos de repasse pela 44643 precisam do HTTPS do tv3ws (`HTTPS_KEY` e `HTTPS_CERT` no `tv3ws/.env`); sem ele, o script os pula com uma linha explicativa, em vez de dar FAIL.
- **O que ele mexe:** recria a borda, congela e para por alguns segundos o tv3ws e o Redis, e grava chaves de teste no Redis e um retido no broker, todos com sufixo único. No fim, inclusive com erro ou Ctrl+C, volta a borda ao modo de antes, religa o que parou e desfaz o que gravou.
- **Esquema do Redis (P4, desde 10/10):** quando faz o papel de um serviço no Redis (serviço corrente, origem associada, bloqueio de cliente), o script grava pelas funções do esquema. No fim, depois de desfazer o que gravou, ele exige a auditoria vazia (`FCALL_RO tv30_auditoria 0`) e dá FAIL se não estiver. Se a auditoria já tinha achados antes da suíte (um volume de antes do P4, por exemplo), ele avisa no começo. Pede a imagem do `redis` com as funções; sem elas, para logo no começo com a mensagem. Em 11/10, a auditoria saiu vazia no começo e no fim, nos dois modos de rede da borda.
- **Resultado esperado:** `== resultado: N PASS, 0 FAIL ==`. Em 11/10, depois do P1.3, da P1.9 e do P4 e antes das decisões da segunda parte, foram 225 PASS e 0 FAIL com a borda na bridge e 225 PASS e 0 FAIL com a borda em rede do host (override do SSDP, sem reinício da borda). Depois das decisões da segunda parte: 227 PASS e 0 FAIL com a borda na bridge e 227 PASS e 0 FAIL com a borda em rede do host, sem reinício da borda.

### `scripts/test-dev-host.sh`: módulos rodando no host

```bash
./scripts/test-dev-host.sh               # cenários 1 a 5
./scripts/test-dev-host.sh --cenario 2   # um só
```

- **O que cobre:** as cinco combinações de [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local), com o módulo real (`npm ci && npm run dev`) fora do Docker. São elas: o tv3ws, o aop e o bcast, um de cada vez; os três ao mesmo tempo; e um componente novo falando direto com o Redis e o broker. Em cada uma, confere a conversa com o Redis e o broker a partir do ambiente do módulo, os logs de conexão dele e o caminho próprio do cenário, com uma prova negativa: o módulo é morto e o caminho para de responder. Nos cenários 2 a 4, desde 11/10, confere a app users-test no host próprio, com o prefixo (`/graphicsAppProxy/users-test` e `Host: <rótulo>.apps.localhost:8080`), e o 302 do mesmo caminho no host do aop para essa URL (`checar_app_aberta`). Nos cenários 2 e 4, desde 11/10 (C1), confere que o aop do host atende o MQTT por WebSocket em `/mqtt` e o repassa ao mosquitto em container (101 no pedido de WebSocket; `checar_mqtt_ws_aop`), com o `MQTT_WS_PORT` tirado da porta publicada da 9001; e o cenário 2 sobe o bcast com `BCAST_PUBLISH=8081:8081`, porque a 8081 do host deixou de ser fixa.
- **Pré-requisitos:** Linux ou WSL2 com Docker Engine. Sem Node Linux no PATH, o script roda cada módulo num container `node:23-alpine` com `--network host`. O `npm ci` precisa alcançar o registro do npm; em rede corporativa que intercepta SSL, ele pode falhar dentro do container.
- **O que ele mexe:** para os containers dos módulos que vão para o host e recria a borda na variante certa. No fim, restaura a stack padrão se havia algum container do projeto de pé, ou a derruba. O cache do npm fica no volume `tv30-devhost-npm`, que o script não apaga.
- **Tempo:** cerca de 3 minutos em 10/10, com o cache do npm já cheio. A primeira execução, que baixa as dependências dos módulos, demora mais; esse tempo não foi medido.
- **Resultado esperado:** `RESUMO (N PASS, 0 FAIL)`, com os logs dos módulos num diretório temporário indicado no fim. Em 11/10, depois das confirmações do Luís (host próprio com o prefixo `/graphicsAppProxy`, 302 do caminho antigo), 65 PASS e 0 FAIL nos 5 cenários. Antes delas eram 66: no cenário 3, as duas provas negativas (host da app e caminho antigo) viraram uma, porque o caminho antigo só redireciona. Depois das decisões da segunda parte de 11/10: 67 PASS e 0 FAIL (os dois a mais são o `/mqtt` do aop do host, nos cenários 2 e 4).
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
- o healthcheck do Redis, a quantidade de perfis da carga inicial e o login do redis-commander (401 sem credencial, 200 com ela, senha errada recusada);
- a 6379 sem senha;
- que matar o commander derruba o container do Redis e que o `restart` o traz de volta, saudável, com o número de reinícios antes e depois (desde 11/10, C2; até ali, o script mostrava que o banco seguia sem o commander);
- as duas superfícies e o Swagger;
- a diferença entre rota declarada e caminho não declarado (100 no formato C.3.2) nas duas portas;
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
- **`infra/mqtt-broker/plugin/tests/test_all_validations.sh`:** casos de validação de esquema do plugin do broker. Ele chama o container `mosquitto-plugin`, nome anterior ao compose atual (hoje o broker é o `mqtt-broker`), então não roda contra a stack de hoje sem ajuste.
- **`infra/mqtt-broker/brokertimetest/`:** medição do tempo de resposta do broker com vários clientes em paralelo. Os resultados registrados ali são de 21/08, quando o plugin ainda consultava o Redis para autorização, o que não acontece mais.
