---
title: Desenvolvimento com serviço no host
parent: Primeiros passos
nav_order: 2
---

# Infra em containers e um módulo rodando no host

Quem está implementando algo num dos módulos (tv3ws, aop, bcast ou um componente novo) sobe **só o mínimo** em containers e roda o módulo em desenvolvimento **no host**, com `npm run dev`, sem refazer imagem a cada mudança. Entre as combinações estão os três módulos no host ao mesmo tempo e um componente novo no host falando direto com o broker e o Redis, sem passar pela borda. Nesta página: o teste que automatiza isso, as cinco combinações com os comandos completos, as variáveis que cada módulo exige e as regras de rede que o código impõe.

> Mensageria, borda (KrakenD) e Redis são decisões de implementação deste testbed, não da ABNT NBR 25608. Só a porta 44642 da superfície interna é fixada pela norma (C.3.4).

## Teste automatizado: `scripts/test-dev-host.sh`

```bash
./scripts/test-dev-host.sh               # cenários 1 a 5, em ordem
./scripts/test-dev-host.sh --cenario 2   # um só (aceita também 1,3 ou 4,5)
./scripts/test-dev-host.sh --build       # repassa --build ao compose (ex.: borda nova)
```

Para cada cenário, o script:

1. para o container de cada módulo que vai para o host;
2. sobe o mínimo com a variante certa da borda (no cenário 5, sobe o Redis e o broker e depois para a borda);
3. roda o **módulo real** com `npm ci && npm run dev`, numa cópia temporária sem `node_modules` e sem `.env` (no cenário 4, os três módulos ao mesmo tempo, cada um na sua cópia);
4. faz as verificações;
5. mata os processos do host.

No fim, se havia qualquer container do projeto `tv30` de pé antes do teste, restaura a stack padrão (`EDGE_VARIANT=linux`), subindo todos os serviços dos perfis `mqtt` e `linux`, mesmo que antes só uma parte deles estivesse de pé; se não havia nenhum, a derruba (`docker compose down`). A borda fica parada no cenário 5. O script não mexe no anunciante SSDP, que é do `./tv30 up` e roda fora do Docker. O script sobe a borda em `warn`, e a restauração volta ao modo do `.env` (ver *`JWT_SECRET` compartilhado*, abaixo). O resultado sai como PASS/FAIL por verificação, e o código de saída é diferente de zero se houver alguma falha. Os logs dos módulos ficam num diretório temporário indicado no fim da execução.

**"Host" tem duas formas** (`DEVHOST_MODO`):

| Modo | Como roda o módulo | Quando |
|---|---|---|
| `node` | `node`/`npm` do PATH, numa cópia em `$TMPDIR` | Linux com Node instalado |
| `docker` | `docker run --network host node:23-alpine`, com o módulo montado só-leitura em `/src` e copiado para `/app` | Máquina sem Node no Linux, como o WSL deste projeto. `--network host` dá ao processo a **mesma rede do host** |
| `auto` (padrão) | `node` se houver Node **Linux** no PATH, senão `docker` | O `node.exe` do Windows visível no WSL é ignorado, porque rodaria na rede do Windows |

Outras variáveis do script: `DEVHOST_IMAGEM` (padrão `node:23-alpine`, a mesma base dos Dockerfiles em `infra/dockerfiles/`) e `DEVHOST_TIMEOUT` (padrão 300 s, contando o `npm ci` no modo docker). `JWT_SECRET`, `JWT_ISSUER` e `SERVER_URL` são lidos do shell, depois do `.env` da raiz, depois do padrão do compose. O `MQTT_WS_PORT` do aop do host não vem do `.env`: o script o tira do Docker, com a porta em que a 9001 do Mosquitto foi publicada (`porta_ws_mqtt`). As variáveis de proxy e registro do npm (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `NPM_CONFIG_REGISTRY`, `NPM_CONFIG_STRICT_SSL`) são repassadas ao container. Em rede corporativa que intercepta SSL, o `npm ci` dentro do container pode falhar por certificado.

No modo `docker`, cada módulo do host roda num container `tv30-devhost-<módulo>`, que o script remove no fim de cada cenário. Ao começar, ele também remove os que uma execução interrompida tenha deixado de pé (segurariam a porta do módulo, como a 8081 do bcast, e os cenários falhariam com "porta ja ocupada"), e restaura a stack também quando a sessão é fechada (SIGHUP). O cache do npm fica no volume nomeado `tv30-devhost-npm` (montado em `/root/.npm`), para que o `npm ci` dos cenários seguintes não baixe tudo de novo. O script **não** apaga esse volume. Para removê-lo: `docker volume rm tv30-devhost-npm`.

### O que cada cenário verifica

| # | No host | Em container | Verificações |
|---|---|---|---|
| 1 | **tv3ws** (HTTP 44654) | redis, mosquitto, edgegateway **windows**, aop, bcast | host → Redis (PING); host → MQTT (pub/sub); logs `[redis] pronto em 127.0.0.1:6379` e `Connected to MQTT broker` do tv3ws; borda `44642/health` → tv3ws do host; `GET /tv3/current-service` pela borda com accessToken HS256 assinado com o `JWT_SECRET` compartilhado, respondido pelo Express do tv3ws do host (200 com `serviceContextId`, ou 404 `{"error":300}` quando não há serviço em uso, C.6.3.1; os dois valem). O token do script tem `sub` `tv30-devhost-teste`, fora de `clients:authorized`, e a borda o recusa com 107: em `warn`, o modo do script, a requisição passa com `X-TV30-Auth-Warn: 107` (registrado como `info`); com `DEVHOST_AUTH_ENFORCE=enforce`, a borda responde ela mesma 404 `{"error":107}`, e a verificação falha (ver *`JWT_SECRET` compartilhado*, abaixo); depois de matar o tv3ws do host, a borda **para** de responder (prova de que a resposta vinha do host) |
| 2 | **aop** (8080) | redis, mosquitto, edgegateway **linux**, tv3ws, bcast com `BCAST_HOSTNAME=localhost` e `BCAST_PUBLISH=8081:8081` | host → Redis; host → MQTT; log `Loaded N users from Redis` e `Connected to MQTT broker` do aop; o catálogo do aop do host mostra o serviço anunciado pelo bcast (BAMT por MQTT); com a aplicação users-test aberta pelo fluxo do aop, a origem própria dela (`http://<rótulo>.apps.localhost:8080`; rótulo `urn-tv30-app-users-test`) aparece em `origins:associated`, e o aop do host traz a aplicação do bcast em container (proxy HTTP) por esse host, com o prefixo, em `/graphicsAppProxy/users-test`; o mesmo caminho no host do aop responde 302 para essa URL; o aop do host atende o MQTT por WebSocket em `/mqtt` e o repassa ao mosquitto em container, na porta publicada da 9001 (`checar_mqtt_ws_aop`: a requisição de WebSocket em `http://127.0.0.1:8080/mqtt` tem de receber 101); borda linux → tv3ws em container |
| 3 | **bcast** (8081) | redis, mosquitto, edgegateway **linux**, tv3ws, aop | host → Redis; host → MQTT; log `MQTT client connected` do bcast; a BALD retida no broker traz `bcastEntryPackageUrl` em `host.docker.internal:8081`; o aop em container mostra o serviço, grava a origem própria da aplicação e alcança o bcast do host pelo proxy HTTP do host próprio, em `/graphicsAppProxy/users-test`; o mesmo caminho no host do aop responde 302 para essa URL; depois de matar o bcast do host, o proxy do host próprio falha |
| 4 | **tv3ws** (44654), **aop** (8080) e **bcast** (8081), ao mesmo tempo | redis, mosquitto, edgegateway **windows** | host → Redis e host → MQTT a partir de cada um dos três; os logs de conexão dos três (os mesmos dos cenários 1 a 3); borda `44642/health` e `GET /tv3/current-service` com accessToken → tv3ws do host, como no cenário 1; a BALD retida no broker traz `bcastEntryPackageUrl` em `127.0.0.1:8081`; o catálogo do aop do host mostra o serviço anunciado pelo bcast do host (BAMT por MQTT); o aop do host grava a origem própria da aplicação e a traz do bcast do host (proxy HTTP) pelo host próprio, em `/graphicsAppProxy/users-test`; o mesmo caminho no host do aop responde 302 para essa URL; o `/mqtt` do aop do host chega ao mosquitto em container, como no cenário 2; depois de matar o bcast do host, o proxy do host próprio falha; depois de matar o tv3ws do host, a borda para de responder |
| 5 | **componente novo**: o exemplo de [`templates/componente/`](https://github.com/multisens/TV30/tree/main/templates/componente) (8090) | redis, mosquitto; a borda (`edgegateway`) fica **parada**. O cenário não para tv3ws, aop e bcast: na sequência completa eles já estão parados pelo cenário 4, mas com `--cenario 5` sozinho, os containers que estavam de pé continuam | host → Redis (PING) do ambiente do componente; logs do próprio componente com `redis 127.0.0.1:6379 PING -> PONG` e `mqtt 127.0.0.1:1883 conectado`; `/health` na 8090, que só abre com Redis e broker conectados; um ping por MQTT em `tv30/<nome>/exemplo/ping` volta em `/pong` com o valor que o teste acabou de gravar no Redis, e o log do componente registra o ping; depois de matar o componente do host, o ping fica sem resposta |

As verificações host → Redis e host → MQTT rodam **no mesmo ambiente do módulo**: no modo `node`, um `node -e` à parte, na cópia do módulo (mesmos arquivos, `node_modules` e rede, mas não o processo do módulo); no modo `docker`, um `docker exec` no mesmo container, com `--network host`. O teste de MQTT usa a biblioteca `mqtt` do próprio módulo. No cenário 4 elas rodam uma vez em cada um dos três módulos.

Detalhes dos cenários 4 e 5:

- **Cenário 4.** O bcast sobe com `BCAST_HOSTNAME=127.0.0.1`. Quem segue o `bcastEntryPackageUrl` é o aop, que também está no host, então o endereço é a porta do próprio processo do bcast; `127.0.0.1`, e não `localhost`, para não depender da resolução IPv6. O bcast sobe antes do aop, e a BALD retida no broker já sai com esse endereço. As provas negativas matam primeiro o bcast (o proxy do aop falha) e depois o tv3ws (a borda para de responder).
- **Cenário 5.** A borda é parada de propósito: se o componente responde com ela parada, o caminho não passa por ela. O exemplo do template não traz a biblioteca `mqtt`, então o host → MQTT desse cenário é o pub/sub do próprio componente (o cliente MQTT mínimo do `index.js`), e não a sonda que os outros cenários rodam com a biblioteca do módulo. O componente roda com um nome próprio do teste (`COMPONENTE_NOME=devhost-componente-<pid>`, que muda o tópico e a chave do exemplo), para que um container do template de pé (`meu-componente`) não responda no lugar dele. A chave de teste é apagada no fim, também quando o teste é interrompido.

### Portas no host

| Porta | Quem usa | Cenários |
|---|---|---|
| 44654 (44655 só com certificado) | tv3ws | 1, 4 |
| 45000–45199 | WebSockets de remote-device do tv3ws | 1, 4 |
| 8080 | aop | 2, 4 |
| 8081 | bcast | 3, 4 |
| 8090 | componente de exemplo | 5 |

Nenhuma dessas portas colide com as portas fixas da infra (6379, 1883, 44642 e 44643). A 9001 do mosquitto, a 8081 do bcast em container, a documentação da borda e o redis-commander saem em portas de host escolhidas pelo Docker; a 44643 da borda é fixa por padrão (`EDGE_EXT_PUBLISH`, padrão `44643:44643`). As portas 8080 e 45000–45199 são as mesmas que os containers do aop e do tv3ws publicam, e por isso o script para o container antes; a 8081 do bcast em container só é fixa no cenário 2 (`BCAST_PUBLISH=8081:8081`), e o bcast do host dos cenários 3 e 4 usa a 8081 com o container parado. Antes de subir cada processo, o script confere que 44654, 8080, 8081 e 8090 estão livres.

## Variante da borda: depende de onde está o tv3ws

O `edgegateway` encaminha para o tv3ws conforme `EDGE_VARIANT` (`infra/edgegateway/routes.json`, `backends`):

| `EDGE_VARIANT` | Superfície interna 44642 → | Superfície externa 44643 → | Use quando |
|---|---|---|---|
| `linux` (padrão) | `http://tv3ws:44652` | `https://tv3ws:44653` | o tv3ws está **em container** (cenários 2 e 3, deploy) |
| `windows` | `http://host.docker.internal:44654` | `https://host.docker.internal:44655` | o tv3ws está **no host** (cenários 1 e 4), também em Linux |

Com o tv3ws em container e a borda em `windows`, a borda fica sem backend, porque a 44654 não existe no host.

O tv3ws do host escuta, por padrão, só na própria máquina: em `127.0.0.1` e, no Linux, também no IPv4 da `docker0`, que é o `host.docker.internal` da borda no Docker Engine (`host-gateway`; `tv3ws/src/listen-hosts.ts`). `TV3WS_LISTEN_HOST` (lista separada por vírgula) troca os endereços. Quem alcança o tv3ws direto escapa da validação da borda, e por isso a porta dele não fica aberta à rede. No container, o compose define `TV3WS_LISTEN_HOST=0.0.0.0`, e a porta não é publicada no host. As portas WebSocket do remote-device ficam abertas à rede, de propósito.

A superfície externa só tem backend se o tv3ws do host subir HTTPS: com `TV30_TLS_DIR=../.tv30/tls`, o certificado do receptor que o `tls-init` gera, ou com `HTTPS_KEY`/`HTTPS_CERT` em base64 (`tv3ws/src/tls.ts`). O script não passa nenhum dos dois: o tv3ws dele sobe só em HTTP, com os pontos de entrada do remote-device em `ws://`, e a 44643 fica sem backend nos cenários 1 e 4. O script não testa a 44643.

## As combinações, à mão

`tv3ws`, `aop`, `bcast` e `sysctl-init` têm `profiles: ["linux"]`, e `mosquitto` tem `["mqtt"]`. Sem `COMPOSE_PROFILES=mqtt,linux` no `.env`, passe `--profile mqtt --profile linux` como abaixo. **Pare o container do módulo antes de rodá-lo no host.** Os dois disputariam a mesma porta e o mesmo `clientId` MQTT fixo (`tv3ws-client`, `aop-core`, `bcast_svc`), e o broker derruba a conexão anterior quando chega outra com o mesmo id.

```bash
P="--profile mqtt --profile linux"
```

**tv3ws no host** (cenário 1):

```bash
docker compose $P stop tv3ws
EDGE_VARIANT=windows docker compose $P up -d redis mosquitto edgegateway userfiles-seed aop bcast
cd tv3ws && npm ci
MQTT_HOST=127.0.0.1 REDIS_HOST=127.0.0.1 REDIS_PORT=6379 \
HTTP_PORT=44654 HTTPS_PORT=44655 \
JWT_SECRET=tv30-dev-secret-nao-usar-em-producao JWT_ISSUER=GenericIssuer \
USER_THUMBS="$PWD/../user-files/thumbs" TV30_TLS_DIR=../.tv30/tls \
SERVER_URL=localhost WS_PORT_MIN=45000 WS_PORT_MAX=45199 LOG_LEVEL=INFO \
npm run dev
```

O `TV30_TLS_DIR` é opcional: com ele, o tv3ws do host sobe também o HTTPS na 44655 (o backend da 44643 na variante windows) e usa o certificado no `serverCert` do pareamento e no `wss://` do ponto de entrada do dispositivo remoto (o local sai sempre em `ws://`); sem ele, só HTTP. A chave (`key.pem`, modo 0600) tem de ser legível pelo seu usuário: o `./tv30 up` cria o `.tv30/tls` antes do compose para isso, e o `tls-init` deixa os arquivos com o dono do diretório (`infra/edgegateway/tls-init.sh`).

O tv3ws não lê `USER_DATA_FILE`: os perfis vêm do Redis, que já tem a carga inicial, e quem os escreve é o aop.

**aop no host** (cenário 2):

```bash
docker compose $P stop aop
EDGE_VARIANT=linux BCAST_HOSTNAME=localhost BCAST_PUBLISH=8081:8081 \
  docker compose $P up -d redis mosquitto edgegateway userfiles-seed tv3ws bcast
WS=$(docker compose $P port mosquitto 9001 | sed 's/.*://')   # porta publicada da 9001
cd aop && npm ci
PORT=8080 MQTT_HOST=127.0.0.1 MQTT_WS_PORT="$WS" REDIS_HOST=127.0.0.1 REDIS_PORT=6379 \
USER_DATA_PATH="$PWD/../user-files" npm run dev
```

A página da TV fala MQTT pelo aop, em `ws://localhost:8080/mqtt`, e o aop repassa a `ws://${MQTT_HOST}:${MQTT_WS_PORT}`. Com o mosquitto em container, `MQTT_WS_PORT` é a porta em que o Docker publicou a 9001, que, no padrão, muda quando o container é recriado (`MQTT_WS_PUBLISH` a fixa; ver [aop fora do Docker no Windows](#aop-fora-do-docker-no-windows-opção)); sem ela, o padrão 9001 não acha o broker, e o `/mqtt` responde 502. O `BCAST_PUBLISH=8081:8081` fixa a porta do bcast, porque o aop do host segue `http://localhost:8081` (regra 2, abaixo).

**bcast no host** (cenário 3):

```bash
docker compose $P stop bcast
EDGE_VARIANT=linux docker compose $P up -d redis mosquitto edgegateway userfiles-seed tv3ws aop
cd bcast && npm ci
PORT=8081 MQTT_HOST=127.0.0.1 BCAST_HOSTNAME=host.docker.internal \
BSID=tv30-default WEBMEDIA_SID=urn:tv30:service:webmedia \
UFF_SID=urn:tv30:service:uff EDUPLAY_SID=urn:tv30:service:eduplay \
npm run dev
```

**tv3ws, aop e bcast no host** (cenário 4): só a infra em containers, com a borda na variante windows. Rode cada módulo num terminal: o tv3ws com o mesmo comando do cenário 1, o aop com o mesmo do cenário 2 e o bcast como no cenário 3, mudando só o `BCAST_HOSTNAME`. Suba o bcast antes do aop.

```bash
docker compose $P stop tv3ws aop bcast
EDGE_VARIANT=windows docker compose $P up -d redis mosquitto edgegateway userfiles-seed
# terminal 1: tv3ws, como no cenário 1
# terminal 2: bcast
cd bcast && npm ci
PORT=8081 MQTT_HOST=127.0.0.1 BCAST_HOSTNAME=127.0.0.1 \
BSID=tv30-default WEBMEDIA_SID=urn:tv30:service:webmedia \
UFF_SID=urn:tv30:service:uff EDUPLAY_SID=urn:tv30:service:eduplay \
npm run dev
# terminal 3: aop, como no cenário 2 (com o MQTT_WS_PORT da porta publicada da 9001)
```

**Componente novo no host** (cenário 5): só Redis e broker; a borda não entra no caminho. O exemplo do template não tem dependências, e o `npm ci` funciona porque a pasta traz um `package-lock.json`.

```bash
docker compose $P up -d redis mosquitto
cd templates/componente && npm ci
MQTT_HOST=127.0.0.1 REDIS_HOST=127.0.0.1 REDIS_PORT=6379 PORT=8090 npm run dev
# noutro terminal: grava a chave, assina o pong e manda o ping pelo broker
docker exec redis redis-cli SET tv30:meu-componente:exemplo ola
docker exec mqtt-broker mosquitto_sub -h localhost -C 1 -W 10 -t tv30/meu-componente/exemplo/pong &
sleep 1; docker exec mqtt-broker mosquitto_pub -h localhost -t tv30/meu-componente/exemplo/ping -m oi
# esperado: {"componente":"meu-componente","ping":"oi","chave":"tv30:meu-componente:exemplo","valor":"ola"}
```

**Volta à stack padrão:** `EDGE_VARIANT=linux docker compose $P up -d`. O compose recria o bcast com `BCAST_HOSTNAME=bcast` e a borda na variante linux, e sobe de novo os containers parados nos cenários 4 e 5. Com o `.env` copiado do `.env.example`, `./tv30 up` faz o mesmo e sobe também o anunciante SSDP.

Os três módulos chamam `dotenv.config()`. Um `.env` na pasta do módulo também é lido, mas a variável já definida no shell vence. Rodar `npm ci` direto na pasta do clone troca o `node_modules` dela; o script evita isso trabalhando numa cópia.

### aop fora do Docker no Windows (opção)

Uma opção, e não uma regra, para quem roda o aop fora do Docker no Windows, com a stack no WSL: em vez de ler a porta publicada da 9001 a cada recriação do container do mosquitto, fixá-la. No `.env` da raiz, `MQTT_WS_PUBLISH=9003:9001` (a linha já vem comentada no `.env.example`), seguido de `docker compose up -d mosquitto`; no `aop/.env`, `MQTT_WS_PORT=9003`, que o aop lê pelo `dotenv.config()` quando não há valor no shell. A 9003 evita a 9001 e a 9002, que o Hyper-V ocupa em algumas máquinas Windows (`netsh interface ipv4 show excludedportrange protocol=tcp` mostra as reservadas). Com essa porta fixa, o `docker compose port mosquitto 9001` do comando do cenário 2 também responde 9003. O resto segue o aop no host (cenário 2), e o arranjo com o aop no Windows continua fora do que o `scripts/test-dev-host.sh` cobre (ver [Limites](#limites)).

## Variáveis que cada módulo exige

tv3ws, aop e bcast encerram com `exit 1` no boot se faltar alguma variável obrigatória. Sob `npm run dev`, quem sai é o processo do módulo: o `nodemon` continua de pé (`app crashed - waiting for file changes before starting...`) e só reinicia o módulo quando um arquivo muda.

| Módulo | Obrigatórias (código) | Também necessárias no host |
|---|---|---|
| tv3ws | `MQTT_HOST`, `REDIS_HOST`, `JWT_SECRET`, `USER_THUMBS` (`assertEnv`, em `tv3ws/src/server.ts`) | `HTTP_PORT`/`HTTPS_PORT`: o padrão do código é 44642/44643, **as portas da borda no host**, e daria conflito; a variante windows espera 44654/44655. `SERVER_URL`: sem ela, a URL de remote-device sai `ws://undefined:<porta>` (ou `wss://`, no ponto de entrada do dispositivo remoto com TLS; `server.url`, em `tv3ws/src/core.ts`, usado por `getUrl` e `getLocalEntryPointUrl`, em `tv3ws/src/modules/remotedevice-manager/remote-device.ts`). `WS_PORT_MIN`/`WS_PORT_MAX`: o padrão 1000–9999 (`generateDynamicallyPort`, em `tv3ws/src/modules/remotedevice-manager/entry-point.ts`) pode colidir com 1883, 6379, 8080 e 8081; use a faixa do container, 45000–45199. Opcionais: `TV30_TLS_DIR` (HTTPS, `serverCert` e o `wss://` do dispositivo remoto; sem ele nem `HTTPS_KEY`/`HTTPS_CERT`, só HTTP e `ws://`; `loadTls`, em `tv3ws/src/tls.ts`) e `TV3WS_LISTEN_HOST` (endereços de escuta; padrão `127.0.0.1`, mais a `docker0` no Linux; `listenHosts`, em `tv3ws/src/listen-hosts.ts`) |
| aop | `MQTT_HOST`, `USER_DATA_PATH`, `REDIS_HOST` (`assertEnv`, em `aop/src/server.js`) | `PORT` (padrão 8080) e `MQTT_WS_PORT` (padrão 9001): a porta em que o aop alcança o WebSocket do mosquitto para repassar o `/mqtt` da página da TV (`mqttWsConfig`, em `aop/src/mqtt-ws.js`); com o mosquitto em container, a porta publicada da 9001 (`docker compose port mosquitto 9001`). `MQTT_HOST` também vale para o repasse e tem de ser só o nome ou IP do broker, sem porta; valor inválido de um dos dois encerra o boot. Opcionais: `APPS_DOMAIN` (padrão `apps.localhost`) e `AOP_PUBLIC_PORT` (padrão `PORT`, senão 8080), que formam a origem de cada aplicação de emissora, `http://<rótulo>.<APPS_DOMAIN>:<AOP_PUBLIC_PORT>` (`appsConfig`, em `aop/src/app-hosts.js`). Valor inválido encerra o boot com `exit 1`. No host, o padrão já casa com a porta do processo; defina `AOP_PUBLIC_PORT` só se o navegador chegar ao aop por outra porta |
| bcast | `MQTT_HOST`, `BCAST_HOSTNAME` (`assertEnv`, em `bcast/src/index.ts`). O `\|\| 'localhost'` de `baseHost`, no mesmo arquivo, nunca é alcançado | `BSID` e `*_SID` fixos, iguais aos do compose; sem eles, cada boot cria tópicos retidos novos no broker |
| componente de exemplo (`templates/componente`) | nenhuma: os padrões são `mosquitto`, `redis` e a porta 8090 (constantes `MQTT_HOST`, `REDIS_HOST` e `PORT` de `templates/componente/index.js`) | `MQTT_HOST=127.0.0.1` e `REDIS_HOST=127.0.0.1`: os padrões são nomes de serviço, que só resolvem dentro da `ginga_net`, e sem broker ou Redis o exemplo sai com `exit 1` (morre-inteiro). `COMPONENTE_NOME` muda o tópico e a chave do exemplo |

### `JWT_SECRET` compartilhado entre a borda e o tv3ws

O tv3ws **assina** o accessToken (HS256, `JWT_SECRET`, emissor `JWT_ISSUER`). A borda **valida** o mesmo token no plugin `tv30-auth`, em modo `enforce` por padrão. Os dois precisam do mesmo segredo e do mesmo emissor, vindos de uma única fonte: o `.env` da raiz ou o shell, com os padrões de desenvolvimento `tv30-dev-secret-nao-usar-em-producao` e `GenericIssuer`. Com o tv3ws no host, exporte os mesmos valores que o compose passa à borda. O script faz isso e assina um token com esse segredo, mas não prova o vínculo: a borda também exige o `sub` do token em `clients:authorized`, e o do token do script (`tv30-devhost-teste`) não está lá, então a borda o recusa com 107 mesmo com o segredo certo. Por isso o script sobe a borda dele em `warn`, explícito (`DEVHOST_AUTH_ENFORCE` muda; a restauração volta ao modo do `.env`): a requisição passa com `X-TV30-Auth-Warn: 107`, e o PASS do `GET /tv3/current-service` confere que a resposta veio do Express do tv3ws do host. O que o script prova é o caminho de rede; a credencial é do `scripts/test-auth.sh`. `JWT_SECRET` dentro de `tv3ws/.env` não tem efeito no container, porque a seção `environment:` do compose tem precedência.

## Regras do arranjo

1. **Quem está no host fala com containers por `127.0.0.1:<porta publicada>`**: 6379 (Redis, publicada só em `127.0.0.1`), 1883 (MQTT), 44642 e 44643 (borda) e 8080 (aop), fixas. A 8081 do bcast e a 9001 (MQTT por WebSocket) do mosquitto saem numa porta de host escolhida pelo Docker: `docker compose port <serviço> <porta>` diz qual, e `BCAST_PUBLISH` ou `MQTT_WS_PUBLISH` (valor `host:container`) a fixam. Com outro processo do host, fala pela porta desse processo, também em `127.0.0.1` (no cenário 4, o aop alcança o bcast em `127.0.0.1:8081`). O script usa `127.0.0.1` em vez de `localhost` para não depender da resolução IPv6, com uma exceção: no cenário 2, o bcast sobe com `BCAST_HOSTNAME=localhost`, e o aop do host segue `http://localhost:8081`.
2. **Quem está em container fala com o host por `host.docker.internal`**, que em Linux só resolve com `extra_hosts: host.docker.internal:host-gateway`. Hoje o `edgegateway` e o `aop` têm essa entrada.
   - **A comunicação interna não é toda por mensageria.** O aop faz **proxy HTTP direto** para o bcast: pelo host próprio de cada aplicação de emissora (`<rótulo>.apps.localhost`; `appHostProxy`, em `aop/src/app-hosts.js`, montado antes de todas as rotas em `aop/src/server.js`) e pelo `/videoStreamProxy` (`proxyStream`, em `aop/src/server.js`). O host próprio vai ao `bcastEntryPackageUrl` que o bcast publica na BALD de cada serviço (`aop/src/modules/bootstrap-application/service.js`), com ou sem o prefixo `/graphicsAppProxy`, que sai antes do pedido ir ao bcast. O `/graphicsAppProxy` no host do aop não é proxy: redireciona (302) para o host próprio da aplicação em execução (`legacyGraphicsRedirect`, em `aop/src/app-hosts.js`); o `/videoStreamProxy` vai ao primeiro `initialMediaURLs` do BAM, que chega pela BAMT (`core.getVideoStreamURL`, `aop/src/core.js`). As duas URLs são montadas pelos módulos do bcast com `http://${BCAST_HOSTNAME}:${PORT}` (`baseHost` e a chamada a `mod.init`, em `bcast/src/index.ts`; a string de cada uma fica no módulo, por exemplo `bcast/src/modules/users-test/index.ts`). O aop e o tv3ws também leem e escrevem o Redis diretamente.
   - O host próprio da aplicação é escolhido pelo cabeçalho `Host`, e não pela resolução de nome do lado do aop. O `scripts/test-dev-host.sh` chama `127.0.0.1:8080/graphicsAppProxy/users-test` com `Host: <rótulo>.apps.localhost:8080`, lido de `origins:associated`, para não depender de o ambiente do teste resolver `*.localhost`. Sem esse cabeçalho, o mesmo pedido cai no host do aop, e o script confere o `Location` do 302 (`checar_app_aberta`).
   - Por isso o `BCAST_HOSTNAME` muda por cenário: `bcast` no deploy, `localhost` com o aop no host (cenário 2), `host.docker.internal` com o bcast no host (cenário 3) e `127.0.0.1` com os dois no host (cenário 4).
   - A porta embutida na URL é a do processo do bcast (`PORT`, padrão 8081; o compose e os comandos desta página passam 8081), e não a porta publicada. Com o aop no host e o bcast em container, a porta publicada do bcast também tem de ser 8081: `BCAST_PUBLISH=8081:8081`, porque ela é aleatória por padrão.
3. **As portas do tv3ws no host (44654/44655) têm de casar com a variante windows** (`infra/edgegateway/routes.json`, `backends.*.windows`).
4. **Cliente acessa a borda**, não a implementação. As portas 44652/44653 do tv3ws não são publicadas no host, e o tv3ws do host escuta só na própria máquina (ver *Variante da borda*, acima).
5. **Componente novo em container segue o template** [`templates/componente/`](https://github.com/multisens/TV30/tree/main/templates/componente): `ginga_net` externa, MQTT/Redis pelo nome do serviço, `extra_hosts`, `restart: unless-stopped`, `init: true` e morre-inteiro. Se um processo interno cair, o container cai inteiro. O modelo com mais de um processo é `infra/edgegateway/entrypoint.sh`.
   - O template sobe como veio: traz um componente de exemplo (`Dockerfile`, `index.js`, `package.json` e `package-lock.json`, só com a biblioteca padrão do Node). O exemplo responde por MQTT com um valor lido do Redis e expõe `/health`.
   - `scripts/test-template.sh` executa o template com a stack de pé. Ele copia a pasta, troca o nome, sobe o exemplo e confere a `ginga_net`, a conversa com `redis` e `mosquitto` pelo nome do serviço, a porta publicada e a regra morre-inteiro: mata o processo, o container cai e o `restart` o traz de volta. No fim, remove tudo o que criou.
   - O mesmo exemplo roda no host com `npm run dev`, como na seção "O mesmo componente rodando no host" do README do template. O cenário 5 do `scripts/test-dev-host.sh` faz isso e confere a conversa direta com o Redis e o broker por `127.0.0.1`, com a borda parada.

## Limites

- **Windows nativo não é coberto.** Com o Docker Engine no WSL, `host-gateway` aponta para a VM do WSL, não para o Windows, e um `npm run` no PowerShell não é alcançado pela borda. A 1883 do WSL pode recusar conexão vinda do Windows. Para desenvolver no Windows, rode o módulo dentro do WSL (o modo `docker` do script faz isso). O script recusa rodar no Git Bash. Para quem ainda assim roda o aop no Windows, há a opção da seção [aop fora do Docker no Windows](#aop-fora-do-docker-no-windows-opção), que não muda o que o script cobre.
- **Docker Desktop** não foi testado.
- **Aplicações de emissora só na própria máquina.** A camada gráfica abre cada aplicação em `http://<rótulo>.apps.localhost:<porta do aop>`, com o prefixo `/graphicsAppProxy` no caminho, e `*.localhost` resolve para a máquina de quem abre a página. Com a tela do aop aberta de outra máquina, as aplicações não carregam; use `APPS_DOMAIN` com um domínio resolvível na rede (tabela de variáveis do README da raiz).
- **A morte do módulo na subida só aparece no fim do prazo, em todos os cenários.** O `npm run dev` do tv3ws, do aop e do bcast é `nodemon` (sem `--exitcrash`), e o do exemplo do cenário 5 é `node --watch index.js`. Se o módulo sai com erro (variável faltando, sem Redis ou sem broker), o `nodemon` ou o `node --watch` continua de pé esperando mudança no arquivo, o script não vê o processo morrer e só acusa a falha ao fim do `DEVHOST_TIMEOUT`, mostrando o log do módulo.
- **Sem anúncio SSDP no dev-host.** O tv3ws não anuncia: quem anuncia é o anunciante nativo do host (`./tv30 up`; [Descoberta SSDP]({{ site.baseurl }}/ssdp)). O `/manifest` do tv3ws do host sai com o `Host` da requisição, que a borda repassa em `X-TV30-Host`, ou com o `SSDP_ADVERTISE_HOST` do ambiente dele (à mão, na pasta do clone, o `dotenv` lê o `tv3ws/.env`; o script roda numa cópia sem `.env`).
