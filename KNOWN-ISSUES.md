# Known Issues

Problemas conhecidos do testbed, cada um com o sintoma, a causa e o contorno. A triagem de erros de operação (porta presa, Redis que não sobe, códigos de erro das APIs) está em [`docs/troubleshooting.md`](./docs/troubleshooting.md).

## Redis sem senha: escrita direta alcança as decisões da borda

- **Sintoma:** quem alcança a 6379 (a própria máquina ou um container na `ginga_net`) grava no Redis sem credencial, e a borda decide em `enforce` a partir dessas chaves. `HSET origins:associated <origem> <serviço>` faz uma origem passar por local associado (sem access token e, no contexto daquele serviço, sem bind-token); `RPUSH bind-context:<serviço>` registra uma chave de bind.
- **Causa:** a conexão com o banco não tem senha (decisão do projeto); só a interface administrativa (redis-commander) pede login (`REDIS_COMMANDER_USER` e `REDIS_COMMANDER_PASSWORD`, na tabela de variáveis do `README.md`). As funções do esquema (`infra/redis/esquema.json`) não impedem a escrita direta: o Redis aplica o ACL de quem chama dentro da função, então não há como liberar só a escrita pela função.
- **Contorno:** a 6379 é publicada só em `127.0.0.1` (`infra/redis/docker-compose.yml`), fora do alcance dos outros aparelhos da rede. A auditoria (`docker exec redis redis-cli FCALL_RO tv30_auditoria 0`) mostra uma escrita direta que saia do esquema; uma que cumpra o esquema, como os dois exemplos acima com valores válidos, não se distingue da do código.

## Local associado reconhecido pelo `Origin`: `Origin` forjado passa

- **Sintoma:** um cliente fora do navegador que mande no `Origin` a origem de uma app de emissora em execução passa como local associado: dispensa o access token e, no contexto de serviço daquela origem, o bind-token, inclusive em `POST` e `DELETE /tv3/bind-context`. Vale nos dois modos.
- **Causa:** sem `Authorization`, a borda reconhece o local associado pelo `Origin` presente em `origins:associated` (`evaluate`, em `infra/edgegateway/plugin/handler.go`), e o tv3ws usa o mesmo critério (`classifyClient`, em `tv3ws/src/api/client-identification/controller.ts`). Fora do navegador, o `Origin` pode ser forjado. A C.4.1.7 deixa o mecanismo de diferenciação à implementação; o testbed usa o `Origin`.
- **Contorno:** nenhum no testbed.

## Portas fixas dentro da faixa efêmera do Linux: bind recusado de vez em quando

- **Sintoma:** intermitente, um `docker compose up` ou um teste falha com `address already in use` numa porta fixa que logo depois está livre (por exemplo, `failed to bind host port 0.0.0.0:45114/tcp: address already in use`, ou `EADDRINUSE :::44654` no tv3ws do host).
- **Causa:** o Linux sorteia a porta local de cada conexão de saída na faixa efêmera, `net.ipv4.ip_local_port_range` (no WSL2, de 32768 a 60999), sem nenhuma porta reservada (`net.ipv4.ip_local_reserved_ports` vazio). Dentro dela estão portas que o testbed escuta: a 44642 (fixa pela C.3.4) e a 44643 da borda, a faixa 45000–45199 do tv3ws e, no dev-host, a 44654 e a 44655 do tv3ws do host. Se uma conexão de saída qualquer (o `npm ci`, os `curl` de um teste, o próprio Docker) estiver usando uma delas na hora, o `listen` ou o `docker-proxy` falham.
- **Contorno:** subir de novo. Reservar as portas (`net.ipv4.ip_local_reserved_ports=44642-44643,44652-44655,45000-45199`) as tira do sorteio, e quem escuta nelas continua escutando, mas mexe numa configuração do kernel da máquina (do WSL ou do Linux nativo), e não só do testbed; o testbed não aplica essa reserva.

## Backend mais lento que 2 s ou fora do ar: a borda corta a requisição

- **Sintoma:** uma rota repassada ao tv3ws cujo backend demora mais de 2 s, ou está fora do ar, recebe 404 `{"error":200,"description":"Platform resource unavailable: <motivo>"}`, e não a resposta.
- **Causa:** das 26 rotas de `infra/edgegateway/routes.json`, 21 são repassadas ao tv3ws; as outras 5 (C.6.8 e C.6.7.8/C.6.7.9) a própria borda responde. Nas 20 repassadas sem `timeout` próprio, a borda espera o tv3ws por no máximo 2 s, o padrão do KrakenD (`infra/edgegateway/generate.js`). Só o `GET /tv3/authorize` tem limite próprio, de 15 s, porque o pop-up de autorização espera a resposta do espectador por até 10 s. O plugin `tv30-auth` troca o 5xx do KrakenD por esse erro 200, com `Content-Type: application/json`, `Access-Control-Allow-Origin: *` e `API-Version`, nos dois modos. Com o Redis fora do ar, o tv3ws desiste de um comando em 1,5 s (`commandTimeout`, em `tv3ws/src/redis-client.ts`) e responde ele mesmo o 404 `{"error":200}`, antes dos 2 s da borda.
- **Contorno:** o limite é deliberado: um tv3ws travado ou fora do ar não deixa o cliente esperando. Uma rota que precise de mais tempo recebe um `timeout` próprio no `routes.json` (por exemplo, `15s` ou `500ms`), que entra no rebuild da borda.

## Panic do roteador do KrakenD em caminho não declarado, contido pelo plugin

- **Sintoma:** sem o plugin `tv30-auth`, um caminho não declarado que colide com o miolo das rotas-curinga (`GET /tv3/abc`, `GET /tv3/xyz/abc`, `POST /tv3/users`, `GET /tv3/naoexiste`) fecha a conexão sem resposta, e o log mostra `http: panic serving ...: invalid node type`.
- **Causa:** defeito do roteador Gin embutido no KrakenD 2.7.2. O plugin, carregado nas duas superfícies, casa método e caminho com as rotas da tabela (`infra/edgegateway/routes.json`) **antes** do roteador e responde fora dela 404 `{"error":100,"description":"API not found: <método> <caminho>"}` (C.3.2.1, C.3.3.2); um `recover()` em volta do roteador transforma um panic restante em 404 `{"error":200}`. O panic continua no roteador; o plugin só o torna inalcançável.
- **Contorno:** a borda não sobe sem o plugin. O build da imagem falha quando o `.so` não casa com o binário (`krakend check-plugin` e `krakend test-plugin`, no `infra/edgegateway/Dockerfile`), e configuração inválida do plugin derruba o container.

## Pareamento: challenge sem prazo e desafio errado que não encerra a tentativa

- **Sintoma:** o challenge do pareamento (QR code ou PIN) vale até o `/tv3/token` com a resposta certa ou até o tv3ws reiniciar. O `/tv3/token` com a resposta errada dá 102, e o mesmo challenge pode ser respondido de novo, sem limite.
- **Causa:** o material do pareamento só fica na memória do tv3ws, sem prazo nem limite de tentativas (`tv3ws/src/api/client-identification/service.ts`). A trava de 120 s (`PAIRING_POPUP_TIMEOUT_MS`) fecha o pop-up e libera a camada gráfica, mas não invalida o challenge.
- **Contorno:** reiniciar o tv3ws (`docker compose restart tv3ws`) descarta os pareamentos em andamento.

## Cinco perfis e nenhuma remoção: a criação do sexto é recusada

- **Sintoma:** com cinco perfis em `users:index`, o AoP recusa o sexto com 400 e a mensagem "O limite de 5 perfis foi atingido. O perfil não foi criado.", e o telespectador não tem como remover um perfil.
- **Causa:** o AoP limita os perfis a cinco e não despeja nenhum (`MAX_PROFILES`, em `aop/src/modules/profile-manager/service.js`). A remoção de perfil pelo telespectador, com confirmação explícita, não existe, e a função que removeria o perfil com os atributos de emissora (`tv30_perfil_remove`) não tem chamador.
- **Contorno:** remover um perfil por fora, com `docker exec redis redis-cli FCALL tv30_perfil_remove 0 <id>` (o arquivo do avatar fica em `user-files/thumbs`), ou `docker compose down -v`, que apaga o volume do Redis, com todos os perfis, e os retidos do broker.

## Aviso da C.6.14.5 com o id do serviço, e não o nome da emissora

- **Sintoma:** o aviso que a camada gráfica mostra quando uma emissora grava atributos do perfil (`aop/display/layers/popup/info`) traz o id do serviço (por exemplo, `urn:tv30:service:users-test`). O 304 (serviço fora do Application Catalog) também não é emitido.
- **Causa:** o nome é o `serviceName` do serviço corrente (`session:current-service`), quando a gravação é nele; sem nome, vale o id (`notifyUserOfWrite`, em `tv3ws/src/api/user/service.ts`). O nome viria de `aop/services`, e nenhum módulo deste repositório publica esse tópico; é o mesmo catálogo de que o 304 depende.
- **Contorno:** nenhum. O aviso também não tira pop-up da tela: com um sim/não, QR code, PIN ou outro aviso aberto, ele espera numa fila, e com 3 avisos já esperando o novo é descartado, com registro no console da página (`INFO_QUEUE_MAX`, em `aop/public/js/popup.js`).

## Apps de emissora: não carregam com o AoP aberto de outra máquina, nem recebem teclas sem a ponte

- **Sintoma:** com a tela do AoP aberta de outra máquina, as apps de emissora não carregam. Uma app que não inclui a ponte não recebe teclas, `timeupdate` nem `stream_event`.
- **Causa:** cada app abre em `http://<app>.<APPS_DOMAIN>:<AOP_PUBLIC_PORT>/graphicsAppProxy<bcastEntryPointUrl>` (`aop/src/app-hosts.js`), e `*.localhost`, do padrão `apps.localhost`, resolve para a máquina de quem abre a página. Com a app noutra origem, a camada gráfica entrega os eventos por `postMessage`, e quem os redespacha no documento da app é `bcast/public/js/aop-bridge.js`.
- **Contorno:** `APPS_DOMAIN` com um domínio resolvível na rede, com `*.<domínio>` apontando para a máquina do AoP (DNS curinga). Toda app da camada gráfica inclui `aop-bridge.js` (users-test, uff, webmedia e eduplay incluem). O QtWebEngine não foi testado com esses nomes.

## Superfície externa fora da 44643: `/manifest` e OpenAPI anunciam outra porta

- **Sintoma:** com `EDGE_EXT_PUBLISH=44643` (só o número), a superfície externa sai numa porta de host escolhida pelo Docker (`docker compose port edgegateway 44643`), que nem o `/manifest` nem o OpenAPI da externa anunciam. Com outra porta fixa (`EDGE_EXT_PUBLISH=<porta>:44643`) e sem `EDGE_HTTPS_PORT`, o `/manifest` anuncia a 44643; o OpenAPI diz 44643 em qualquer caso, e o "Try it out" da externa não chega à borda.
- **Causa:** o `/manifest` manda `Server-SecureBaseURL: <host>:<EDGE_HTTPS_PORT>`, com padrão 44643 (`secureBaseURL`, em `tv3ws/src/ssdp-config.ts`), e não conhece a porta publicada. O OpenAPI tira a porta de `surfaces.external.port` do `routes.json` (`servers: https://localhost:44643`, `infra/edgegateway/generate.js`).
- **Contorno:** manter o padrão, `EDGE_EXT_PUBLISH=44643:44643` (`infra/docker-compose.yml`). Com outra porta fixa, defina o mesmo número em `EDGE_HTTPS_PORT` no `.env` da raiz, que o tv3ws lê, e recrie a borda e o tv3ws (`docker compose up -d edgegateway tv3ws`).

## Certificado do receptor só para `localhost` e `127.0.0.1`

- **Sintoma:** quem confere o nome do servidor recusa o certificado da 44643 e dos `wss://` quando chega pelo IP da rede, mesmo confiando no certificado.
- **Causa:** o `tls-init` gera o certificado autoassinado com `subjectAltName` só para `localhost` e `127.0.0.1` (`infra/edgegateway/tls-init.sh`). O cliente não local o recebe no `serverCert` do pareamento (Tabela C.4).
- **Contorno:** `curl -k`; ou pôr em `.tv30/tls` um `cert.pem` e um `key.pem` próprios e recriar a stack (o `tls-init` só gera o par quando falta um dos dois). App de navegador que não confia no certificado: `TV3WS_WS_TLS=false`, para os pontos de entrada em `ws://`.

## Anunciante SSDP: nada o reinicia

- **Sintoma:** se o anunciante sai, a descoberta para até o próximo `./tv30 up`, e os clientes deixam de achar o receptor pelo SSDP.
- **Causa:** o anunciante é um processo nativo do host, subido pelo `./tv30 up` (no Windows, `tv30.ps1`), sem supervisor. Só erro de configuração o encerra (`infra/edgegateway/ssdp/main.go`); na falta de rede, ele fecha os sockets, avisa e tenta de novo, com espera de 1 s a 30 s. Se ele sai logo na subida, o `./tv30 up` termina com erro e mostra o fim do log, com o compose já de pé.
- **Contorno:** `./tv30 status` diz se ele está de pé, e `./tv30 logs` mostra o log (`.tv30/ssdp.log`); corrija a configuração e rode `./tv30 up` de novo. Sem o anúncio, o cliente chega ao receptor pelo IP: `http://<IP>:44642/manifest`. Não foram medidos o anúncio recebido por outro aparelho da rede nem o arranjo no Windows ([`docs/ssdp.md`](./docs/ssdp.md)).

## Volume do Redis com perfis fora do esquema

- **Sintoma:** a auditoria (`docker exec redis redis-cli FCALL_RO tv30_auditoria 0`) aponta perfis com `{id} da chave: deve ser UUID ...` ou `campo avatar: SVG em linha nao serve`, a regravação deles é recusada, e o `scripts/test-auth.sh` dá FAIL.
- **Causa:** o esquema (`infra/redis/esquema.json`) exige o id do perfil em UUID estrito, em minúsculas (Tabela 7), e o `avatar` como nome de um arquivo do diretório de miniaturas, sem compatibilidade com outros formatos. A carga inicial só roda em banco vazio (`seed:done`), então não corrige um volume `redis_data` já gravado. Com o id fora do esquema, `tv30_perfil_grava` e `tv30_atributos_emissora` recusam a escrita; `tv30_perfil_ultimo_acesso` e `tv30_perfil_remove` funcionam (`infra/redis/README.md`).
- **Contorno:** `docker compose down -v`, que apaga o volume do Redis, com os perfis criados, e os retidos do broker; ou corrigir as chaves apontadas, como em [`docs/troubleshooting.md`](./docs/troubleshooting.md), seção *Auditoria do Redis com achados*.
