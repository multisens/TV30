# Known Issues

## Redis sem senha e publicado no host — DECIDIDO pelo Luís em 03/10: a conexão fica assim, e o risco continua

O Redis publica a 6379 no host (`infra/redis/docker-compose.yml`) e não tem senha. Em `enforce`, a borda decide a partir de chaves desse Redis: um `HSET origins:associated <origem> x` faz uma origem passar por local associado (sem access token nem bind-token), e um `RPUSH bind-context:<serviço>` registra uma chave de bind.

**Decidido pelo Luís em 03/10:** a conexão com o banco fica como está. Só a interface administrativa (redis-commander) passou a exigir login com usuário e senha; usuário, senha padrão e como trocar estão no `README.md` da raiz, seção *Interface administrativa do Redis*. O risco descrito acima continua valendo. Registrado em `docs/decisoes-pendentes.md` (A1) e em `docs/avaliacao-item9-credenciais.md`.

## Backend mais lento que 2 s ou fora do ar: a borda corta a requisição — ABERTO (formato do erro corrigido em 03/10)

Nas 24 rotas sem `timeout` próprio em `infra/edgegateway/routes.json`, a borda espera o tv3ws por no máximo 2 s, o padrão do KrakenD (`infra/edgegateway/generate.js`). Só o `GET /tv3/authorize` tem limite próprio, de 15 s, por causa do pop-up. Com o backend mais lento que isso, ou fora do ar, quem responde é o próprio KrakenD.
- **Até 03/10:** a resposta era 500 com corpo vazio, fora do formato C.3.2.
- **Desde 03/10:** o plugin `tv30-auth` troca qualquer 5xx que sai do KrakenD por 404 `{"error":200,"description":"Platform resource unavailable: <motivo>"}`, com `Content-Type: application/json`, `Access-Control-Allow-Origin: *` e `API-Version`, nos dois modos.
- **Continua:** os limites de tempo não mudaram. A rota cujo backend demora mais de 2 s recebe o erro 200, e não a resposta.

**Verificado na stack em 04/10** (imagem do edgegateway reconstruída): no `scripts/test-auth.sh`, com o tv3ws parado (`docker stop`), as duas superfícies (44642 e 44643) responderam 404 `{"error":200}` vindo da borda, com `API-Version: 2.0`, para um `GET /tv3/current-service` com token válido; com o tv3ws congelado (`docker pause`), caso do backend que não responde, a 44642 respondeu o mesmo 404 `{"error":200}`. Os testes Go do plugin (`krakend/builder:2.7.2`, go1.22.7) passaram: 44 PASS, 0 FAIL.

## Apps de emissora servidas pelo proxy do AoP não são reconhecidas como associadas — ABERTO (P1.3, pré-requisito do `enforce`)

O associado é reconhecido pelo `Origin` em `origins:associated` (L1; o risco do `Origin` forjado foi aceito pelo Luís em 03/10, D-L4). O AoP grava nessa lista a origem **própria** da app, alvo do proxy (`aop/src/core.js`, `registerAssociatedOrigin`). Mas o navegador abre a app pelo proxy do AoP (`/graphicsAppProxy/...`), e as chamadas dela chegam à borda com o `Origin` do próprio AoP. A origem própria por app (P1.3) não foi feita e **não** foi decidida em 03/10.

**Medido na stack em 04/10**, com o serviço sintonizado pelo catálogo do AoP: `origins:associated` tinha só `http://bcast:8081`. A sequência de chamadas das páginas users-test e webmedia, com `Origin: http://localhost:8080`, recebeu `X-TV30-Auth-Warn: 107` na lista de perfis, nas duas páginas e nas duas cargas. Em `warn` a chamada passa. Em `enforce`, pela lógica do plugin, essas apps seriam bloqueadas com 107, como cliente sem access token.

## Duas autorizações ao mesmo tempo se misturam no pop-up sim/não — ABERTO

O 101 no reuso de `clientid` (D-L2) não cobre o reuso **simultâneo**. Em `checkAuthorization` (`tv3ws/src/api/client-identification/controller.ts`), o `clientid` só passa a contar como autorizado ou bloqueado depois que o espectador responde ao pop-up, e essa espera chega a 10 s (`askAuthorization`). Um segundo `/tv3/authorize` com o mesmo `clientid` dentro dessa janela passa pelas duas checagens e abre outro pop-up.

Por trás disso há um defeito anterior a esta rodada: o tv3ws guarda **um** callback por tópico (`subscribe` em `tv3ws/src/core.ts`, `_topics.set(topic, callback)`). O segundo pop-up toma o lugar do primeiro no tópico de resposta. A resposta do espectador vai só para a segunda chamada. A primeira expira, cai em `wrapup(false)`, tira a inscrição do tópico (o que também derruba a da segunda, se ela ainda esperava) e grava o `clientid` em `clients:blocked`.

Com o mesmo `clientid`, o resultado é `client:{id}` autorizado com a classe da segunda chamada e o mesmo id em `clients:blocked`; a primeira chamada recebe 102. Em `enforce` a borda barra esse id pelo bloqueio (107). O defeito do callback único também mistura autorizações simultâneas de `clientid` **diferentes**. Lido no código em 04/10; não reproduzido na stack. Correção possível, não feita: marcar o `clientid` como pendente antes do pop-up (por exemplo, `SET client-pending:{id} NX EX 15` no Redis) e devolver 101 se a marca existir; e uma fila ou um id por pop-up no `core.ts`.

## SSDP anuncia `localhost` por padrão e um endereço "seguro" sem TLS — ABERTO (aguarda o Joel)

Com o padrão do compose (`SERVER_URL=localhost`), o anúncio SSDP e o `/manifest` divulgam `http://localhost:44642/manifest` e `Server-BaseURL: localhost:44642`. Um cliente em outro equipamento recebe o anúncio e não alcança o endereço (medido pela integração: `ECONNREFUSED`, ver `docs/ssdp-verificacao.md`). O boot avisa (`[ssdp] AVISO`); para anunciar outro host, defina `SSDP_ADVERTISE_HOST` no `.env` da raiz (ou no `tv3ws/.env`; o da raiz prevalece). O tv3ws (`/manifest`) e o `tv3ws-ssdp` (anúncio, desde a opção B da L6, 04/10) leem os dois arquivos. O `Server-SecureBaseURL` anuncia `<host>:44643`, que na borda é HTTP puro (lacuna L3).

## `tv3ws-ssdp` fica de pé quando o perfil `ssdp` sai — ABERTO (aguarda o Luís; medido em 04/10)

Depois de tirar o `ssdp` do `COMPOSE_PROFILES`, nem `docker compose up -d` nem `docker compose down` param o `tv3ws-ssdp`: o compose só mexe nos serviços dos perfis ativos. O anunciante segue no ar com a configuração da subida anterior. Na medição, o `LOCATION` continuou em 172.27.57.172, enquanto o tv3ws recriado já respondia `Server-BaseURL: localhost:44642`. Para desligar: `docker compose --profile ssdp rm -sf tv3ws-ssdp`. Detalhes no teste 22 de `docs/ssdp-verificacao.md`.

## Caminho não declarado resetava a conexão na borda — RESOLVIDO em 02/10/2026

**Era assim:** no `edgegateway`, caminhos NÃO declarados que colidem com o miolo das rotas-curinga (`GET /tv3/abc`, `GET /tv3/xyz/abc`, `POST /tv3/users`, `GET /tv3/naoexiste`) disparavam um panic do roteador Gin embutido no KrakenD 2.7.2 ("invalid node type"). O cliente via a conexão fechada sem resposta, e não um 404. O tratamento de rota não encontrada do tv3ws (erro 100, `tv3ws/src/util/error.ts`) não era alcançável, porque esses caminhos nunca chegavam a ele.

**Como ficou:** o plugin `tv30-auth` (`infra/edgegateway/plugin/`, carregado nas duas superfícies) casa método e caminho com a tabela única (`infra/edgegateway/routes.json`) **antes** do roteador.
- Fora da tabela, a borda responde 404 com `{"error":100,"description":"API not found: <método> <caminho>"}` (C.3.2.1, C.3.3.2), `Content-Type: application/json` e `Access-Control-Allow-Origin: *`.
- Isso vale nos dois modos (`AUTH_ENFORCE=warn` e `enforce`) e também para `OPTIONS` sem `Access-Control-Request-Method` em caminho não declarado. Desde 03/10, o `OPTIONS` sem preflight num caminho **declarado** recebe 200 com `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods` e `Access-Control-Allow-Headers` (C.4.1.9.3).
- O preflight CORS passa ao roteador e responde 204, inclusive em caminho não declarado.
- Um `recover()` em volta do roteador transforma qualquer panic restante em 404 `{"error":200}`.

**Verificado em 02/10/2026** com `scripts/test-auth.sh` (84 PASS, 0 FAIL), na stack completa e com a imagem reconstruída. Nas portas 44642 e 44643, cada um destes devolveu 404 `{error:100}` com a conexão íntegra (saída 0 do curl):
- `GET /tv3/naoexiste`, `GET /tv3/xyz/abc` e `GET /tv3/abc`;
- `POST /tv3/users`;
- `PUT /tv3/current-service`, que tem método não declarado;
- `OPTIONS` sem preflight.

**O panic continua no roteador; o plugin só o torna inalcançável.** No mesmo dia, a configuração gerada da superfície interna rodou **sem** o bloco do plugin num KrakenD 2.7.2 avulso. Os mesmos quatro caminhos voltaram a fechar a conexão (curl 52, sem resposta), e o log mostrou `http: panic serving ...: invalid node type`. Se o plugin deixar de carregar, o defeito volta. Por isso o build da imagem falha quando o `.so` não casa com o binário: o `krakend check-plugin` e o `test-plugin` rodam no Dockerfile. Pelo mesmo motivo, configuração inválida do plugin derruba o container.

Contexto que a consolidação revelou: no arranjo anterior, o plugin Go do gateway externo **repassava qualquer caminho** direto ao tv3ws (na época, CCWS), ignorando as rotas declaradas, e toda a API interna era alcançável por fora. O edgegateway fecha esse vazamento: só serve o que a tabela única declara.
