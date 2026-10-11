# Known Issues

## Redis sem senha e publicado no host — DECIDIDO pelo Luís em 03/10: a conexão fica assim, e o risco continua

O Redis publica a 6379 no host (`infra/redis/docker-compose.yml`) e não tem senha. Em `enforce`, a borda decide a partir de chaves desse Redis: um `HSET origins:associated <origem> x` faz uma origem passar por local associado (sem access token nem bind-token), e um `RPUSH bind-context:<serviço>` registra uma chave de bind.

**Decidido pelo Luís em 03/10:** a conexão com o banco fica como está. Só a interface administrativa (redis-commander) passou a exigir login com usuário e senha; usuário, senha padrão e como trocar estão no `README.md` da raiz, seção *Interface administrativa do Redis*. O risco descrito acima continua valendo. Registrado em `docs/decisoes-pendentes.md` (A1) e em `docs/avaliacao-item9-credenciais.md`.

**P4 (decidido pelo Luís em 10/10) não fecha este risco.** Desde o P4, o código do projeto grava só por funções do Redis que conferem o esquema (`infra/redis/esquema.json`), mas quem alcança a 6379 ainda grava direto. O Redis aplica o ACL de quem chama dentro da função, então não há como liberar só a escrita pela função. A auditoria (`docker exec redis redis-cli FCALL_RO tv30_auditoria 0`) mostra uma escrita direta que saia do esquema. Uma escrita direta que cumpra o esquema, como os dois exemplos acima com valores válidos, não se distingue da do código.

## Backend mais lento que 2 s ou fora do ar: a borda corta a requisição — ABERTO (formato do erro corrigido em 03/10)

Das 26 rotas de `infra/edgegateway/routes.json`, 21 são repassadas ao tv3ws; as outras 5 (C.6.8 e C.6.7.8/C.6.7.9) a própria borda responde desde a rodada de 05/10. Desde a P1.9 (decisão do Luís em 10/10), a superfície externa (44643) tem 24 delas: as mesmas 21 repassadas e 3 da borda, sem `POST` e `DELETE /tv3/bind-context`. Até a saída de `POST /tv3/{serviceContextId}/users` (A4, decisão do Luís em 11/10), eram 27 rotas, 22 repassadas, e 25 na externa. Nas 20 repassadas sem `timeout` próprio, a borda espera o tv3ws por no máximo 2 s, o padrão do KrakenD (`infra/edgegateway/generate.js`). Só o `GET /tv3/authorize` tem limite próprio, de 15 s, por causa do pop-up. Com o backend mais lento que isso, ou fora do ar, quem responde é o próprio KrakenD.
- **Até 03/10:** a resposta era 500 com corpo vazio, fora do formato C.3.2.
- **Desde 03/10:** o plugin `tv30-auth` troca qualquer 5xx que sai do KrakenD por 404 `{"error":200,"description":"Platform resource unavailable: <motivo>"}`, com `Content-Type: application/json`, `Access-Control-Allow-Origin: *` e `API-Version`, nos dois modos.
- **Continua:** os limites de tempo não mudaram. A rota cujo backend demora mais de 2 s recebe o erro 200, e não a resposta.
- **Redis fora do ar, desde a rodada de 05/10 (D-0510-6):** o tv3ws desiste de um comando do Redis em 1,5 s (`commandTimeout` em `tv3ws/src/redis-client.ts`) e responde ele mesmo 404 `{"error":200}`, antes dos 2 s da borda. Antes, com o padrão do ioredis, a requisição ficava presa até a borda cortar.

**Verificado na stack em 04/10** (imagem do edgegateway reconstruída): no `scripts/test-auth.sh`, com o tv3ws parado (`docker stop`), as duas superfícies (44642 e 44643) responderam 404 `{"error":200}` vindo da borda, com `API-Version: 2.0`, para um `GET /tv3/current-service` com token válido; com o tv3ws congelado (`docker pause`), caso do backend que não responde, a 44642 respondeu o mesmo 404 `{"error":200}`. Os testes Go do plugin (`krakend/builder:2.7.2`, go1.22.7) passaram: 44 PASS, 0 FAIL.

## Apps de emissora servidas pelo proxy do AoP não eram reconhecidas como associadas — RESOLVIDO em 10/10 (P1.3, decisão do Luís)

O associado é reconhecido pelo `Origin` em `origins:associated` (L1; o risco do `Origin` forjado foi aceito pelo Luís em 03/10, D-L4).

**Como ficou** (decisão do Luís em 10/10: um nome de host por app, na mesma porta do AoP; confirmações dele em 11/10):
- o AoP abre cada app de emissora em `http://<app>.<APPS_DOMAIN>:<AOP_PUBLIC_PORT>/graphicsAppProxy<bcastEntryPointUrl>` (padrão `<app>.apps.localhost:8080`; o prefixo `/graphicsAppProxy` está na URL desde 11/10, e no host da app é opcional) e atende esse nome com um proxy para o `bcastEntryPackageUrl` da app em execução (`aop/src/app-hosts.js`, montado antes de todas as rotas em `aop/src/server.js`). `<app>` é um rótulo DNS tirado do `appId` da BALD, fixo por app desde 11/10 (`urn:tv30:app:users-test` vira `urn-tv30-app-users-test`);
- ao lançar a app, o AoP grava essa origem em `origins:associated`, e a apaga ao encerrar ou trocar de app (`aop/src/core.js`). É a origem que o navegador manda no `Origin` das chamadas da app;
- a camada gráfica entrega teclas e eventos do vídeo à app por `postMessage`, e a ponte `bcast/public/js/aop-bridge.js` os redespacha no documento dela;
- no host do próprio AoP, o caminho antigo `/graphicsAppProxy/<caminho>` redireciona (302) para o mesmo caminho no host da app em execução, e responde 404 sem app (desde 11/10).

**Conferido em 11/10, fora da stack:** `npm test` do aop com 29 testes sem falha (o prefixo na URL, o prefixo opcional no host da app, o 302 do caminho antigo e o 404 sem app); `npx tsc --noEmit` do bcast sem erro.

**Conferido em 10/10, fora da stack:** `npm test` do aop com 22 testes (14 novos, do roteamento por `Host` e do registro da origem) sem falha; o Firefox 154 do receptor Linux resolveu `*.apps.localhost` para `::1` e mandou o `Origin` do nome; o Chrome 154 headless no Windows mandou o mesmo `Origin` que o AoP grava, e a ponte entregou os eventos. **Na stack, em 10/10 (borda na bridge):** `scripts/test-auth.sh` abriu o users-test pelo AoP, achou a origem `http://urn-tv30-app-<sorteio>.apps.localhost:8080` (o `appId` era sorteado até 11/10) em `origins:associated`, passou sem credencial com esse `Origin` em `enforce`, recebeu 107 com o `Origin` do próprio AoP e de novo 107 depois do ESC (224 PASS, 0 FAIL no script); `scripts/test-dev-host.sh` conferiu a origem gravada e o acesso pelo host da app nos cenários 2, 3 e 4 (66 PASS, 0 FAIL).

**Continua:**
- **Tela do AoP aberta de outra máquina:** `*.localhost` resolve para a máquina de quem abre a página, e as apps não carregam. `APPS_DOMAIN` permite usar um domínio resolvível na rede, com `*.<domínio>` apontando para a máquina do AoP.
- **App sem a ponte não recebe teclas:** toda app da camada gráfica precisa incluir `aop-bridge.js` (users-test, uff, webmedia e eduplay incluem). O contrato da ponte foi aceito pelo Luís como está em 11/10.
- **QtWebEngine** não foi testado.

**Resolvido em 11/10 (decisões do Luís):**
- **O nome mudava quando o bcast reiniciava:** até 11/10, o bcast sorteava o `appId` (`cuid.slug()`) a cada partida, e com ele mudavam o nome do host e o `localStorage` da app, que é por origem. Agora o `appId` é fixo por app, `urn:tv30:app:<módulo>`, trocável por `EDUPLAY_APP_ID`, `UFF_APP_ID`, `USERS_TEST_APP_ID` e `WEBMEDIA_APP_ID` com o bcast fora do container (`bcast/README.md`).
- **O caminho antigo `/graphicsAppProxy`**, até 11/10, servia a app na origem do AoP, sem gravar origem: a app aberta por ele não era reconhecida como associada. Agora ele redireciona (302) para o host da app, e o prefixo ficou na URL que a camada gráfica abre.

**Era assim** (até 10/10). O AoP gravava nessa lista o alvo do proxy, `http://bcast:8081`, mas o navegador abria a app pelo proxy do AoP (`/graphicsAppProxy/...`), e as chamadas dela chegavam à borda com o `Origin` do próprio AoP. **Medido na stack em 04/10**, com o serviço sintonizado pelo catálogo do AoP: `origins:associated` tinha só `http://bcast:8081`. A sequência de chamadas das páginas users-test e webmedia, com `Origin: http://localhost:8080`, recebeu `X-TV30-Auth-Warn: 107` na lista de perfis, nas duas páginas e nas duas cargas. Em `warn` a chamada passava. Em `enforce`, pela lógica do plugin, essas apps seriam bloqueadas com 107, como cliente sem access token.

## Rotas exclusivas do associado na superfície externa: 100, e não 106 — ABERTO (aguarda o Joel; P1.9, ligado à L3)

Desde a P1.9 (decisão do Luís em 10/10), a superfície externa (44643) só expõe as rotas que admitem o cliente não local. `POST` e `DELETE /tv3/bind-context` (C.6.8.2 e C.6.8.4, só `local-associated`) existem só na 44642; na 44643 respondem 404 `{"error":100}`, como um caminho não declarado (`infra/edgegateway/generate.js`, `SURFACE_RULES`). A C.4.1.8 (p. 206-207; p. 224-225 do PDF) manda responder 106 ao não local que chama por HTTPS uma API de uso exclusivo do cliente local. Enquanto a 44643 for HTTP (L3), ela não se aplica ao pé da letra; com TLS, falta decidir entre 100 e 106. Na mesma superfície, a C.6.7.8 e a C.6.7.9 listam 18 APIs, e não as 20 da interna. Isso foi decidido pelo Luís em 11/10 (F-2, `docs/decisoes-pendentes.md`, seção F): cada superfície lista só as APIs que oferece, como já estava. O 100 ou 106 com TLS continua com o Joel.

## Duas autorizações ao mesmo tempo se misturam no pop-up sim/não — ABERTO

O 101 no reuso de `clientid` (D-L2) não cobre o reuso **simultâneo**. Em `checkAuthorization` (`tv3ws/src/api/client-identification/controller.ts`), o `clientid` só passa a contar como autorizado ou bloqueado depois que o espectador responde ao pop-up, e essa espera chega a 10 s (`askAuthorization`). Um segundo `/tv3/authorize` com o mesmo `clientid` dentro dessa janela passa pelas duas checagens e abre outro pop-up.

Por trás disso há um defeito anterior a esta rodada: o tv3ws guarda **um** callback por tópico (`subscribe` em `tv3ws/src/core.ts`, `_topics.set(topic, callback)`). O segundo pop-up toma o lugar do primeiro no tópico de resposta. A resposta do espectador vai só para a segunda chamada. A primeira expira, cai em `wrapup(false)`, tira a inscrição do tópico (o que também derruba a da segunda, se ela ainda esperava) e grava o `clientid` em `clients:blocked`.

Com o mesmo `clientid`, a primeira chamada recebe 102. Até 05/10, o resultado ficava incoerente: `client:{id}` autorizado com a classe da segunda chamada e o mesmo id em `clients:blocked`. Desde a rodada de 05/10 (D-0510-4), o bloqueio tira o id de `clients:authorized` e o põe em `clients:blocked` numa operação atômica (uma transação até o P4; desde então, a função `tv30_cliente_bloqueia`), então ele termina só bloqueado: a segunda chamada recebe a resposta de sucesso, mas o `/tv3/token` desse id dá 102, e em `enforce` a borda barra o token dele pelo bloqueio (107). O `client:{id}` fica gravado. O defeito do callback único também mistura autorizações simultâneas de `clientid` **diferentes**. Lido no código em 04/10 e de novo em 10/10; não reproduzido na stack. Correção possível, não feita: marcar o `clientid` como pendente antes do pop-up (por exemplo, `SET client-pending:{id} NX EX 15` no Redis) e devolver 101 se a marca existir; e uma fila ou um id por pop-up no `core.ts`.

## Host do anúncio SSDP: `SSDP_ADVERTISE_HOST` obrigatório — DECIDIDO pelo Luís em 11/10 (B2); o endereço "seguro" sem TLS segue ABERTO (L3, aguarda o Joel)

**Como era** (até 11/10): com o padrão do compose (`SERVER_URL=localhost`), o anúncio SSDP e o `/manifest` divulgavam `http://localhost:44642/manifest` e `Server-BaseURL: localhost:44642`. Um cliente em outro equipamento recebia o anúncio e não alcançava o endereço (medido pela integração: `ECONNREFUSED`, ver `docs/ssdp-verificacao.md`), e o boot só avisava (`[ssdp] AVISO`).

**Decidido pelo Luís em 11/10 (B2):** com o anúncio ligado (`docker-compose.ssdp.yml`, `SSDP_ENABLED=true` na borda), o `SSDP_ADVERTISE_HOST` é obrigatório. Ausente ou vazio, é erro de configuração: o anunciante sai com 1 e a borda cai inteira, como os outros erros de configuração da C8 (`infra/edgegateway/ssdp/config.go`). Antes disso, o `scripts/preflight.sh` para a subida (exit 1) com a mensagem, porque o override lhe passa os mesmos arquivos de ambiente da borda. O `SERVER_URL` e o IP local deixaram de ser fonte do host do anúncio da borda. Um valor de loopback configurado de propósito segue aceito, com `[ssdp] AVISO`.

**Continua:**
- **O `LOCATION` não acompanha troca de rede:** é o valor do `.env` (teste 45 de `docs/ssdp-verificacao.md`). É consequência da B2.
- **O tv3ws não mudou:** o `/manifest` dele ainda usa `SSDP_ADVERTISE_HOST`, senão `SERVER_URL`, senão o IP local (`tv3ws/src/ssdp-config.ts`). Com o anúncio ligado, os dois saem do mesmo `SSDP_ADVERTISE_HOST`, lido dos mesmos arquivos (`tv3ws/.env` e `.env` da raiz, que prevalece). Sem o anúncio e sem `SSDP_ADVERTISE_HOST` no `.env`, um `/manifest` pedido pelo IP ainda divulga `localhost:44642`, o padrão do `SERVER_URL` no compose. O anunciante Node do tv3ws (só dev-host) também segue a cadeia antiga.
- **Endereço "seguro" sem TLS (L3):** o `Server-SecureBaseURL` anuncia `<host>:44643`, que na borda é HTTP puro.

## Na bridge, o receptor divulga a 44643, mas a porta de host da externa é outra — ABERTO (consequência da C1, sem decisão)

Desde a C1 (decisão do Luís em 11/10), a 44643 da borda na bridge sai numa porta de host escolhida pelo Docker (`EDGE_EXT_PUBLISH`, padrão `44643`, só o número; `infra/docker-compose.yml`). Dois lugares continuam dizendo 44643, pela leitura do código:
- o `/manifest` do tv3ws manda `Server-SecureBaseURL: <host>:<EDGE_HTTPS_PORT>`, com padrão 44643 (`tv3ws/src/ssdp-config.ts`). O `EDGE_HTTPS_PORT` só muda o número anunciado, e a porta sorteada pode mudar a cada recriação da borda;
- o OpenAPI da superfície externa, na documentação Swagger da borda, tem `servers: http://localhost:44643` (`infra/edgegateway/generate.js`, a porta de `surfaces.external.port`), e o "Try it out" da externa não chega à borda.

No modo SSDP (borda em rede do host), a 44643 é a própria porta do host, e os dois valem. Na bridge, `EDGE_EXT_PUBLISH=44643:44643` no `.env` da raiz devolve o comportamento de antes. Não medido na stack. Não há decisão sobre o que o `/manifest` deve divulgar na bridge.

## Volume do Redis de antes de 11/10: perfis fora do esquema — sem compatibilidade, por decisão (F-3, Luís, 11/10)

Desde a F-3 (decisão do Luís em 11/10), o esquema do Redis (versão 2, `infra/redis/esquema.json`) exige o id do perfil em UUID, no formato da IETF RFC 9562, em minúsculas (Tabela 7), sem compatibilidade com os ids antigos: `user_<epoch-ms>`, gerados pelo AoP, e `c3167a18-5dc5`, da carga inicial. A carga passou a `c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10`, e o AoP gera `crypto.randomUUID()`.
- **Num volume de antes,** a auditoria (`docker exec redis redis-cli FCALL_RO tv30_auditoria 0`) aponta `users:index`, `user:{id}`, `user:{id}:consent` e `user:{id}:broadcaster-attrs:*` de cada perfil antigo. Com o id antigo, `tv30_perfil_grava` e `tv30_atributos_emissora` recusam a escrita; `tv30_perfil_ultimo_acesso` e `tv30_perfil_remove` ainda funcionam (`infra/redis/README.md`). O `scripts/test-auth.sh` dá FAIL se a auditoria não terminar vazia.
- **A carga não corrige:** ela só roda em banco vazio (`seed:done`), então o volume antigo não recebe o perfil novo.
- **Saída:** `docker compose down -v`, que apaga o volume do Redis, com os perfis criados, e os retidos do broker. Quem clona o projeto agora não é afetado.
- **Não muda:** o `session:current-user` continua texto de até 64 caracteres, espelho do tópico `aop/currentUser` (`schemas.json` do broker), e não exige UUID.

## Com o `docker-compose.ssdp.yml`, só um erro de configuração do SSDP derruba a borda inteira — DECIDIDO pelo Luís em 09/10, revisto por ele em 10/10

Com a borda anunciando em rede do host (L6, opção A), o anunciante segue o morre-inteiro da borda (`infra/edgegateway/entrypoint.sh`): se ele sai, a borda cai com todas as APIs, e o `restart` a traz de volta.
- **De 09/10 até a decisão de 10/10,** ele saía em qualquer falha do anúncio (UDP 1900 ocupada por socket sem `SO_REUSEADDR`, interface inexistente em `SSDP_INTERFACE`, erro de envio ou rede caindo). Numa troca de rede em Linux nativo, sem IPv4 no Wi-Fi, a borda reiniciou 12 vezes (teste 44 de `docs/ssdp-verificacao.md`).
- **Desde 10/10** (decisão do Luís: "derrubar a borda só em erro de configuração e tolerar a falta de rede com novas tentativas"), o anunciante só sai por erro de configuração: porta inválida em `EDGE_HTTP_PORT`/`EDGE_HTTPS_PORT`, `SSDP_INTERFACE` com um nome que não existe, UDP 1900 presa sem `SO_REUSEADDR` (`EADDRINUSE`) e os erros que não são de rede (`infra/edgegateway/ssdp/main.go`). Desde 11/10 (B2), também o `SSDP_ADVERTISE_HOST` ausente ou vazio, que o `preflight` já barra antes da subida. Na falta de rede, ele fecha os sockets, registra um aviso, tenta de novo com espera de 1 s a 30 s e volta a anunciar quando a rede volta; as APIs ficam de pé.
- **Medido no WSL2 em 10/10,** com a borda real em rede do host e uma interface de teste (testes 52 a 56 de `docs/ssdp-verificacao.md`): sem IPv4 e com a interface derrubada, a borda ficou de pé, com `/health` 200 e 0 reinícios, e voltou a anunciar; `SSDP_INTERFACE=eth9` e a UDP 1900 presa a derrubaram, e o `restart` a trouxe de volta quando a porta foi liberada. Em Linux nativo, com troca de rede de verdade, a regra nova não foi medida.
- **Continua:** um erro de configuração do anúncio derruba todas as APIs. O `LOCATION` com IP fixo no `.env` não acompanha a troca de rede (teste 45); desde a B2 (Luís, 11/10), que fez do `SSDP_ADVERTISE_HOST` a única fonte do host do anúncio, isso é consequência da decisão, e não ponto aberto. O anunciante Node do tv3ws, que só roda no dev-host, não mudou: qualquer falha dele ainda derruba o processo inteiro.

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

**Como ficou:** o plugin `tv30-auth` (`infra/edgegateway/plugin/`, carregado nas duas superfícies) casa método e caminho com as rotas da superfície, tiradas da tabela única (`infra/edgegateway/routes.json`; desde a P1.9, em 10/10, a superfície de cada rota é derivada das `classes`), **antes** do roteador.
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

Contexto que a consolidação revelou: no arranjo anterior, o plugin Go do gateway externo **repassava qualquer caminho** direto ao tv3ws (na época, CCWS), ignorando as rotas declaradas, e toda a API interna era alcançável por fora. O edgegateway fecha esse vazamento: cada superfície só serve as rotas que a tabela única lhe atribui.
