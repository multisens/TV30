# Known Issues

## `GET /tv3/authorize` reemite o refresh token de qualquer cliente já autorizado — ABERTO (aguarda o Joel)

Anterior à semana de 28/09. Em `tv3ws/src/api/client-identification/controller.ts`, um `GET /tv3/authorize?clientid=<id>&display-name=x` **sem `pm`** devolve o `refreshToken` corrente do cliente `<id>` quando ele já está autorizado, sem pop-up e sem conferir a classe gravada (o trecho "Cliente local ja autorizado que perdeu o refresh token"). A classe que decide a reemissão é a de quem pede, não a do cliente gravado. Com o refresh token, `GET /tv3/token` devolve um access token com a classe da vítima. Basta conhecer o `clientid`, que trafega em query string. A borda não impede, porque `/tv3/authorize` é `auth=none`. A norma trata o reuso de `clientid` na C.6.1.2 como colisão, com erro 101 (C.6.1.4.4). Verificado lendo o código; não foi explorado contra a stack.

## Redis sem senha e publicado no host — ABERTO (decidir antes de qualquer `enforce`)

O Redis publica a 6379 no host (`infra/redis/docker-compose.yml`) e não tem senha. Em `enforce`, a borda decide a partir de chaves desse Redis: um `HSET origins:associated <origem> x` faz uma origem passar por local associado (sem access token nem bind-token), e um `RPUSH bind-context:<serviço>` registra uma chave de bind. Opções: publicar só em `127.0.0.1` ou exigir senha. Registrado em `docs/avaliacao-item9-credenciais.md`.

## SSDP anuncia `localhost` por padrão e um endereço "seguro" sem TLS — ABERTO (aguarda o Joel)

Com o padrão do compose (`SERVER_URL=localhost`), o anúncio SSDP e o `/manifest` divulgam `http://localhost:44642/manifest` e `Server-BaseURL: localhost:44642`. Um cliente em outro equipamento recebe o anúncio e não alcança o endereço (medido pela integração: `ECONNREFUSED`, ver `docs/ssdp-verificacao.md`). O tv3ws avisa no boot (`[ssdp] AVISO`); para anunciar outro host, defina `SSDP_ADVERTISE_HOST` no `tv3ws/.env`. O `Server-SecureBaseURL` anuncia `<host>:44643`, que na borda é HTTP puro (lacuna L3).

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
