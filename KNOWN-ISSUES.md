# Known Issues

## Redis sem senha e publicado no host — DECIDIDO pelo Luís em 03/10: a conexão fica assim, e o risco continua

O Redis publica a 6379 no host (`infra/redis/docker-compose.yml`) e não tem senha. Em `enforce`, a borda decide a partir de chaves desse Redis: um `HSET origins:associated <origem> x` faz uma origem passar por local associado (sem access token nem bind-token), e um `RPUSH bind-context:<serviço>` registra uma chave de bind.

**Decidido pelo Luís em 03/10:** a conexão com o banco fica como está. Só a interface administrativa (redis-commander) passou a exigir login com usuário e senha; usuário, senha padrão e como trocar estão no `README.md` da raiz, seção *Interface administrativa do Redis*. O risco descrito acima continua valendo. Registrado em `docs/decisoes-pendentes.md` (A1) e em `docs/avaliacao-item9-credenciais.md`.

## Backend mais lento que 2 s ou fora do ar: a borda corta a requisição — ABERTO (formato do erro corrigido em 03/10)

Das 27 rotas de `infra/edgegateway/routes.json`, 22 são repassadas ao tv3ws; as outras 5 (C.6.8 e C.6.7.8/C.6.7.9) a própria borda responde desde a rodada de 05/10. Nas 21 repassadas sem `timeout` próprio, a borda espera o tv3ws por no máximo 2 s, o padrão do KrakenD (`infra/edgegateway/generate.js`). Só o `GET /tv3/authorize` tem limite próprio, de 15 s, por causa do pop-up. Com o backend mais lento que isso, ou fora do ar, quem responde é o próprio KrakenD.
- **Até 03/10:** a resposta era 500 com corpo vazio, fora do formato C.3.2.
- **Desde 03/10:** o plugin `tv30-auth` troca qualquer 5xx que sai do KrakenD por 404 `{"error":200,"description":"Platform resource unavailable: <motivo>"}`, com `Content-Type: application/json`, `Access-Control-Allow-Origin: *` e `API-Version`, nos dois modos.
- **Continua:** os limites de tempo não mudaram. A rota cujo backend demora mais de 2 s recebe o erro 200, e não a resposta.
- **Redis fora do ar, desde a rodada de 05/10 (D-0510-6):** o tv3ws desiste de um comando do Redis em 1,5 s (`commandTimeout` em `tv3ws/src/redis-client.ts`) e responde ele mesmo 404 `{"error":200}`, antes dos 2 s da borda. Antes, com o padrão do ioredis, a requisição ficava presa até a borda cortar.

**Verificado na stack em 04/10** (imagem do edgegateway reconstruída): no `scripts/test-auth.sh`, com o tv3ws parado (`docker stop`), as duas superfícies (44642 e 44643) responderam 404 `{"error":200}` vindo da borda, com `API-Version: 2.0`, para um `GET /tv3/current-service` com token válido; com o tv3ws congelado (`docker pause`), caso do backend que não responde, a 44642 respondeu o mesmo 404 `{"error":200}`. Os testes Go do plugin (`krakend/builder:2.7.2`, go1.22.7) passaram: 44 PASS, 0 FAIL.

## Apps de emissora servidas pelo proxy do AoP não são reconhecidas como associadas — ABERTO (P1.3, pré-requisito do `enforce`)

O associado é reconhecido pelo `Origin` em `origins:associated` (L1; o risco do `Origin` forjado foi aceito pelo Luís em 03/10, D-L4). O AoP grava nessa lista a origem **própria** da app, alvo do proxy (`aop/src/core.js`, `registerAssociatedOrigin`). Mas o navegador abre a app pelo proxy do AoP (`/graphicsAppProxy/...`), e as chamadas dela chegam à borda com o `Origin` do próprio AoP. A origem própria por app (P1.3) não foi feita e **não** foi decidida em 03/10.

**Medido na stack em 04/10**, com o serviço sintonizado pelo catálogo do AoP: `origins:associated` tinha só `http://bcast:8081`. A sequência de chamadas das páginas users-test e webmedia, com `Origin: http://localhost:8080`, recebeu `X-TV30-Auth-Warn: 107` na lista de perfis, nas duas páginas e nas duas cargas. Em `warn` a chamada passa. Em `enforce`, pela lógica do plugin, essas apps seriam bloqueadas com 107, como cliente sem access token.

## Duas autorizações ao mesmo tempo se misturam no pop-up sim/não — ABERTO

O 101 no reuso de `clientid` (D-L2) não cobre o reuso **simultâneo**. Em `checkAuthorization` (`tv3ws/src/api/client-identification/controller.ts`), o `clientid` só passa a contar como autorizado ou bloqueado depois que o espectador responde ao pop-up, e essa espera chega a 10 s (`askAuthorization`). Um segundo `/tv3/authorize` com o mesmo `clientid` dentro dessa janela passa pelas duas checagens e abre outro pop-up.

Por trás disso há um defeito anterior a esta rodada: o tv3ws guarda **um** callback por tópico (`subscribe` em `tv3ws/src/core.ts`, `_topics.set(topic, callback)`). O segundo pop-up toma o lugar do primeiro no tópico de resposta. A resposta do espectador vai só para a segunda chamada. A primeira expira, cai em `wrapup(false)`, tira a inscrição do tópico (o que também derruba a da segunda, se ela ainda esperava) e grava o `clientid` em `clients:blocked`.

Com o mesmo `clientid`, a primeira chamada recebe 102. Até 05/10, o resultado ficava incoerente: `client:{id}` autorizado com a classe da segunda chamada e o mesmo id em `clients:blocked`. Desde a rodada de 05/10 (D-0510-4), o bloqueio tira o id de `clients:authorized` e o põe em `clients:blocked` numa transação, então ele termina só bloqueado: a segunda chamada recebe a resposta de sucesso, mas o `/tv3/token` desse id dá 102, e em `enforce` a borda barra o token dele pelo bloqueio (107). O `client:{id}` fica gravado. O defeito do callback único também mistura autorizações simultâneas de `clientid` **diferentes**. Lido no código em 04/10 e de novo em 10/10; não reproduzido na stack. Correção possível, não feita: marcar o `clientid` como pendente antes do pop-up (por exemplo, `SET client-pending:{id} NX EX 15` no Redis) e devolver 101 se a marca existir; e uma fila ou um id por pop-up no `core.ts`.

## SSDP anuncia `localhost` por padrão e um endereço "seguro" sem TLS — ABERTO (aguarda o Joel)

Com o padrão do compose (`SERVER_URL=localhost`), o anúncio SSDP e o `/manifest` divulgam `http://localhost:44642/manifest` e `Server-BaseURL: localhost:44642`. Um cliente em outro equipamento recebe o anúncio e não alcança o endereço (medido pela integração: `ECONNREFUSED`, ver `docs/ssdp-verificacao.md`). O boot do tv3ws e o do anunciante da borda avisam (`[ssdp] AVISO`); para anunciar outro host, defina `SSDP_ADVERTISE_HOST` no `.env` da raiz (ou no `tv3ws/.env`; o da raiz prevalece). O tv3ws (`/manifest`) e a borda (anúncio, com o `docker-compose.ssdp.yml`, desde a opção A da L6, decidida pelo Luís em 09/10) leem os dois arquivos. O `Server-SecureBaseURL` anuncia `<host>:44643`, que na borda é HTTP puro (lacuna L3).

## Com o `docker-compose.ssdp.yml`, só um erro de configuração do SSDP derruba a borda inteira — DECIDIDO pelo Luís em 09/10, revisto por ele em 10/10

Com a borda anunciando em rede do host (L6, opção A), o anunciante segue o morre-inteiro da borda (`infra/edgegateway/entrypoint.sh`): se ele sai, a borda cai com todas as APIs, e o `restart` a traz de volta.
- **De 09/10 até a decisão de 10/10,** ele saía em qualquer falha do anúncio (UDP 1900 ocupada por socket sem `SO_REUSEADDR`, interface inexistente em `SSDP_INTERFACE`, erro de envio ou rede caindo). Numa troca de rede em Linux nativo, sem IPv4 no Wi-Fi, a borda reiniciou 12 vezes (teste 44 de `docs/ssdp-verificacao.md`).
- **Desde 10/10** (decisão do Luís: "derrubar a borda só em erro de configuração e tolerar a falta de rede com novas tentativas"), o anunciante só sai por erro de configuração: porta inválida em `EDGE_HTTP_PORT`/`EDGE_HTTPS_PORT`, `SSDP_INTERFACE` com um nome que não existe, UDP 1900 presa sem `SO_REUSEADDR` (`EADDRINUSE`) e os erros que não são de rede (`infra/edgegateway/ssdp/main.go`). Na falta de rede, ele fecha os sockets, registra um aviso, tenta de novo com espera de 1 s a 30 s e volta a anunciar quando a rede volta; as APIs ficam de pé.
- **Medido no WSL2 em 10/10,** com a borda real em rede do host e uma interface de teste (testes 52 a 56 de `docs/ssdp-verificacao.md`): sem IPv4 e com a interface derrubada, a borda ficou de pé, com `/health` 200 e 0 reinícios, e voltou a anunciar; `SSDP_INTERFACE=eth9` e a UDP 1900 presa a derrubaram, e o `restart` a trouxe de volta quando a porta foi liberada. Em Linux nativo, com troca de rede de verdade, a regra nova não foi medida.
- **Continua:** um erro de configuração do anúncio derruba todas as APIs. O `LOCATION` com IP fixo no `.env` não acompanha a troca de rede (teste 45; B2, sem decisão). O anunciante Node do tv3ws, que só roda no dev-host, não mudou: qualquer falha dele ainda derruba o processo inteiro.

Registrado em `docs/decisoes-pendentes.md` (C8) e em `docs/ssdp-verificacao.md`. Sem o override, a borda não anuncia, e nada disso acontece.

## Container antigo `tv3ws-ssdp` (opção B) de pé depois da troca para a opção A — remover à mão

O serviço `tv3ws-ssdp` e o perfil `ssdp` saíram do compose em 09/10. Um `tv3ws-ssdp` que estava de pé continua anunciando com a configuração antiga (e, com a borda anunciando, ficam dois anunciantes do mesmo UDN). Remova-o com `docker rm -f tv3ws-ssdp` (ou `docker compose up -d --remove-orphans`). O `scripts/preflight.sh` avisa quando ele está de pé.

## Remote-device: a porta do WebSocket continuava escutando depois da remoção — RESOLVIDO em 10/10

**Como ficou** (`tv3ws/src/modules/remotedevice-manager/entry-point.ts`, usado pelo registro e pelo ponto de entrada local):
- a porta sorteada só entra na URL devolvida depois de estar escutando;
- porta ocupada (`EADDRINUSE`) leva a outro sorteio, até 10 vezes; esgotadas as tentativas, ou com outro erro de `listen`, a API responde 404 `{"error":200}` (Tabela C.74: "If the request exceeds the number of devices that can be registered on the platform"), e o processo não cai;
- o `terminate()` do dispositivo fecha os dois pontos de entrada com os seus `http.Server`, e a desativação por *handle* (versão 2.1) fecha o ponto de entrada local e esquece a URL.

**Verificado em 10/10.** No `npm test` do tv3ws (`test/multi-device.test.ts`): porta liberada depois do `DELETE`, porta ocupada contornada e esgotamento com 404 `{"error":200}`. Na stack (borda na bridge, `warn`): um `POST /tv3/remote-device` abriu a 45066, a listagem 2.0 abriu o ponto de entrada local na 45102, e depois do `DELETE /tv3/remote-device/{handle}` (204) as duas portas recusaram conexão (`ECONNREFUSED`, conferido de dentro do container do tv3ws), o registro saiu do Redis e o retido `aop/devices/<classe>` foi apagado. O `EADDRINUSE` não foi provocado na stack.

**Era assim** (achado na rodada de 05/10, lido no código; não medido na stack). Cada `POST /tv3/remote-device` (C.6.15.2) cria um `http.Server` próprio numa porta sorteada da faixa `WS_PORT_MIN`–`WS_PORT_MAX` (45000–45199 no compose) e põe nele um `WebSocketServer` (`tv3ws/src/api/multi-device/service.ts`, `createWebSocket`). O ponto de entrada local que a listagem cria para cada dispositivo (`ensureLocalEntryPoint`, no mesmo arquivo) segue o mesmo padrão.
- **Porta que não fecha.** Na remoção do dispositivo (`DELETE /tv3/remote-device/{handle}`, C.6.15.3, ou o fechamento do socket), o `RemoteDevice.terminate()` chama só `wss.close()` (`tv3ws/src/modules/remotedevice-manager/remote-device.ts`). No `ws` 8.18.1, instalado no tv3ws, o `close()` de um `WebSocketServer` criado sobre um servidor externo (`{ server }`) não fecha esse servidor: só tira os ouvintes dele. A porta segue em LISTEN até o processo acabar, e cada registro removido deixa uma porta presa da faixa de 200.
- **`EADDRINUSE` sem tratamento.** O sorteio não confere se a porta está livre, e o `server.listen(port)` não tem tratamento de erro. Pela leitura do código, o erro do `listen` chega ao `WebSocketServer` (que repassa o `error` do servidor), que não tem ouvinte de `error`, e o processo do tv3ws cai (inferência, não reproduzida). Como o `listen` é assíncrono, a API já respondeu 200 com a URL quando isso acontece. As portas presas pelo defeito acima aumentam a chance de colisão.

## Preflight CORS com a lista de cabeçalhos fora de ordem é recusado pela borda — ABERTO (do KrakenD)

Medido pela frente da borda em 09/10, numa borda isolada (imagem local, sem a stack). O módulo CORS do KrakenD 2.7.2, que responde o preflight (`OPTIONS` com `Access-Control-Request-Method`) nas duas superfícies, não concede o pedido quando o `Access-Control-Request-Headers` vem fora de ordem lexicográfica (por exemplo, `content-type,bind-token`), em qualquer rota: a resposta não passa na verificação do teste da borda (status 2xx, `Access-Control-Allow-Origin: *` e `Access-Control-Allow-Methods` com o método pedido). Com a mesma lista em ordem (`bind-token,content-type`), o preflight passa. Os cabeçalhos exatos da resposta recusada não foram registrados.
- **Quem é afetado.** Os navegadores mandam a lista em minúsculas e em ordem (especificação Fetch), então o efeito esperado é só sobre clientes que montam o preflight à mão, como scripts de teste.
- **O plugin `tv30-auth` não interfere:** ele deixa o preflight passar ao módulo CORS.
- **Norma.** A C.4.1.9.3 (p. 207; p. 225 do PDF) manda responder todo `OPTIONS` com `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods` e `Access-Control-Allow-Headers`. Se a resposta recusada não traz os três, a borda não cumpre a C.4.1.9.3 nesse caso.

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
