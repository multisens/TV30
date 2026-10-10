---
title: Desenvolvimento com serviço no host
nav_order: 9
---

# Infra em containers e um módulo rodando no host

Pedido das reuniões de 21/09 e 28/09: quem está implementando algo num dos módulos (tv3ws, aop, bcast ou um componente novo) sobe **só o mínimo** em containers e roda o módulo em desenvolvimento **no host**, com `npm run dev`, sem refazer imagem a cada mudança. Na reunião de 05/10 com o Joel entraram mais duas combinações: os três módulos no host ao mesmo tempo, e um componente novo no host falando direto com o broker e o Redis, sem passar pela borda. Nesta página: o teste que automatiza isso, as cinco combinações com os comandos completos, as variáveis que cada módulo exige e as regras de rede que o código impõe.

> Mensageria, borda (KrakenD) e Redis são decisões de implementação deste testbed, não da ABNT NBR 25608. Só a porta 44642 da superfície interna é fixada pela norma (C.3.4).

## Teste automatizado: `scripts/test-dev-host.sh`

```bash
./scripts/test-dev-host.sh               # cenários 1 a 5, em ordem
./scripts/test-dev-host.sh --cenario 2   # um só (aceita também 1,3 ou 4,5)
./scripts/test-dev-host.sh --build       # repassa --build ao compose (ex.: borda nova)
```

Para cada cenário, o script:

1. para o container de cada módulo que vai para o host (no cenário 5, para a borda);
2. sobe o mínimo com a variante certa da borda;
3. roda o **módulo real** com `npm ci && npm run dev`, numa cópia temporária sem `node_modules` e sem `.env` (no cenário 4, os três módulos ao mesmo tempo, cada um na sua cópia);
4. faz as verificações;
5. mata os processos do host.

No fim, restaura a stack padrão (`EDGE_VARIANT=linux`) se ela estava de pé antes, ou a derruba (`docker compose down`) se não estava. Durante o teste, a borda roda sempre na bridge (`COMPOSE_FILE=docker-compose.yml`), mesmo que o `.env` da raiz ligue o override `docker-compose.ssdp.yml` (borda em rede do host, anunciando o SSDP), e fica parada no cenário 5; a restauração volta à configuração do `.env`, com o override, se ele estiver ligado. O resultado sai como PASS/FAIL por verificação, e o código de saída é diferente de zero se houver alguma falha. Os logs dos módulos ficam num diretório temporário indicado no fim da execução.

**"Host" tem duas formas** (`DEVHOST_MODO`):

| Modo | Como roda o módulo | Quando |
|---|---|---|
| `node` | `node`/`npm` do PATH, numa cópia em `$TMPDIR` | Linux com Node instalado |
| `docker` | `docker run --network host node:23-alpine`, com o módulo montado só-leitura em `/src` e copiado para `/app` | Máquina sem Node no Linux, como o WSL deste projeto. `--network host` dá ao processo a **mesma rede do host** |
| `auto` (padrão) | `node` se houver Node **Linux** no PATH, senão `docker` | O `node.exe` do Windows visível no WSL é ignorado, porque rodaria na rede do Windows |

Outras variáveis do script: `DEVHOST_IMAGEM` (padrão `node:23-alpine`, a mesma base dos Dockerfiles em `infra/dockerfiles/`) e `DEVHOST_TIMEOUT` (padrão 300 s, contando o `npm ci` no modo docker). `JWT_SECRET`, `JWT_ISSUER`, `MQTT_WS_PORT` e `SERVER_URL` são lidos do shell, depois do `.env` da raiz, depois do padrão do compose. As variáveis de proxy e registro do npm (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `NPM_CONFIG_REGISTRY`, `NPM_CONFIG_STRICT_SSL`) são repassadas ao container. Em rede corporativa que intercepta SSL, o `npm ci` dentro do container pode falhar por certificado.

No modo `docker`, o cache do npm fica no volume nomeado `tv30-devhost-npm` (montado em `/root/.npm`), para que o `npm ci` dos cenários seguintes não baixe tudo de novo. O script **não** apaga esse volume. Para removê-lo: `docker volume rm tv30-devhost-npm`.

### O que cada cenário verifica

| # | No host | Em container | Verificações |
|---|---|---|---|
| 1 | **tv3ws** (HTTP 44654) | redis, mosquitto, edgegateway **windows** (na bridge, sem anúncio SSDP), aop, bcast | host → Redis (PING); host → MQTT (pub/sub); log de Redis pronto e `Connected to MQTT broker` do tv3ws (desde a rodada de 05/10, o tv3ws registra `[redis] pronto em <host>:<porta>`; antes, `[Redis] Connected`); borda `44642/health` → tv3ws do host; `GET /tv3/current-service` pela borda com accessToken HS256 assinado com o `JWT_SECRET` compartilhado, respondido pelo Express do tv3ws do host (200 com `serviceContextId`, ou, desde 10/10, 404 `{"error":300}` quando não há serviço em uso, C.6.3.1; os dois valem); depois de matar o tv3ws do host, a borda **para** de responder (prova de que a resposta vinha do host) |
| 2 | **aop** (8080) | redis, mosquitto, edgegateway **linux**, tv3ws, bcast com `BCAST_HOSTNAME=localhost` e `BCAST_PORT=8081` | host → Redis; host → MQTT; log `Loaded N users from Redis` e `Connected to MQTT broker` do aop; o catálogo do aop do host mostra o serviço anunciado pelo bcast (BAMT por MQTT); `/graphicsAppProxy/users-test` do aop do host traz a aplicação do bcast em container (proxy HTTP); borda linux → tv3ws em container |
| 3 | **bcast** (8081) | redis, mosquitto, edgegateway **linux**, tv3ws, aop | host → Redis; host → MQTT; log `MQTT client connected` do bcast; a BALD retida no broker traz `bcastEntryPackageUrl` em `host.docker.internal:8081`; o aop em container mostra o serviço e alcança o bcast do host pelo proxy HTTP; depois de matar o bcast do host, o proxy falha |
| 4 | **tv3ws** (44654), **aop** (8080) e **bcast** (8081), ao mesmo tempo | redis, mosquitto, edgegateway **windows** (na bridge, sem anúncio SSDP) | host → Redis e host → MQTT a partir de cada um dos três; os logs de conexão dos três (os mesmos dos cenários 1 a 3); borda `44642/health` e `GET /tv3/current-service` com accessToken → tv3ws do host, como no cenário 1; a BALD retida no broker traz `bcastEntryPackageUrl` em `127.0.0.1:8081`; o catálogo do aop do host mostra o serviço anunciado pelo bcast do host (BAMT por MQTT); `/graphicsAppProxy/users-test` do aop do host traz a aplicação do bcast do host (proxy HTTP); depois de matar o bcast do host, o proxy falha; depois de matar o tv3ws do host, a borda para de responder |
| 5 | **componente novo**: o exemplo de [`templates/componente/`](../templates/componente/README.md) (8090) | redis, mosquitto; a borda (`edgegateway`) fica **parada** | host → Redis (PING) do ambiente do componente; logs do próprio componente com `redis 127.0.0.1:6379 PING -> PONG` e `mqtt 127.0.0.1:1883 conectado`; `/health` na 8090, que só abre com Redis e broker conectados; um ping por MQTT em `tv30/<nome>/exemplo/ping` volta em `/pong` com o valor que o teste acabou de gravar no Redis, e o log do componente registra o ping; depois de matar o componente do host, o ping fica sem resposta |

As verificações host → Redis e host → MQTT rodam **no mesmo ambiente do módulo**: o mesmo processo Node, ou o mesmo container com `--network host`. O teste de MQTT usa a biblioteca `mqtt` do próprio módulo. No cenário 4 elas rodam uma vez em cada um dos três módulos.

Os cenários 4 e 5 foram pedidos na reunião de 05/10 com o Joel. Detalhes de cada um:

- **Cenário 4.** O bcast sobe com `BCAST_HOSTNAME=127.0.0.1`. Quem segue o `bcastEntryPackageUrl` é o aop, que também está no host, então o endereço é a porta do próprio processo do bcast; `127.0.0.1`, e não `localhost`, para não depender da resolução IPv6. O bcast sobe antes do aop, e a BALD retida no broker já sai com esse endereço. As provas negativas matam primeiro o bcast (o proxy do aop falha) e depois o tv3ws (a borda para de responder).
- **Cenário 5.** A borda é parada de propósito: se o componente responde com ela parada, o caminho não passa por ela. O exemplo do template não traz a biblioteca `mqtt`, então o host → MQTT desse cenário é o pub/sub do próprio componente (o cliente MQTT mínimo do `index.js`), e não a sonda que os outros cenários rodam com a biblioteca do módulo. O componente roda com um nome próprio do teste (`COMPONENTE_NOME=devhost-componente-<pid>`, que muda o tópico e a chave do exemplo), para que um container do template de pé (`meu-componente`) não responda no lugar dele. A chave de teste é apagada no fim, também quando o teste é interrompido.

### Portas no host

| Porta | Quem usa | Cenários |
|---|---|---|
| 44654 (44655 só com HTTPS) | tv3ws | 1, 4 |
| 45000–45199 | WebSockets de remote-device do tv3ws | 1, 4 |
| UDP 1900 | anúncio SSDP do tv3ws do host (ver [Limites](#limites)) | 1, 4 |
| 8080 | aop | 2, 4 |
| 8081 | bcast | 3, 4 |
| 8090 | componente de exemplo | 5 |

Nenhuma dessas portas colide com a infra: 6379, 1883, 9001, 44642/44643, e as portas dinâmicas da documentação da borda e do redis-commander. As portas 8080, 8081 e 45000–45199 são as mesmas que os containers do aop, do bcast e do tv3ws publicam, e por isso o script para o container antes. Antes de subir cada processo, ele confere que 44654, 8080, 8081 e 8090 estão livres.

## Variante da borda: depende de onde está o tv3ws

O `edgegateway` encaminha para o tv3ws conforme `EDGE_VARIANT` (`infra/edgegateway/routes.json`, `backends`):

| `EDGE_VARIANT` | Superfície interna 44642 → | Superfície externa 44643 → | Use quando |
|---|---|---|---|
| `linux` (padrão) | `http://tv3ws:44652` | `https://tv3ws:44653` | o tv3ws está **em container** (cenários 2 e 3, deploy) |
| `windows` | `http://host.docker.internal:44654` | `https://host.docker.internal:44655` | o tv3ws está **no host** (cenários 1 e 4). O nome é histórico: vale para Linux também |
| `host` | `http://127.0.0.1:44652` | `https://127.0.0.1:44653` | a **borda** está em rede do host, com o tv3ws em container (override `docker-compose.ssdp.yml`, que a define sozinho, para o anúncio SSDP em Linux nativo). Não serve para os cenários deste documento |

Com o tv3ws em container e a borda em `windows`, a borda fica sem backend, porque a 44654 não existe no host. Esse era o erro da tabela antiga desta página nas linhas do aop e do bcast.

A superfície externa só tem backend se o tv3ws subir HTTPS (`HTTPS_KEY`/`HTTPS_CERT`). Uma cópia limpa do tv3ws no host, como a do script, sobe só HTTP, e a 44643 fica sem backend nos cenários 1 e 4. O script não testa a 44643.

## As combinações, à mão

`tv3ws`, `aop`, `bcast` e `sysctl-init` têm `profiles: ["linux"]`, e `mosquitto` tem `["mqtt"]`. Sem `COMPOSE_PROFILES=mqtt,linux` no `.env`, passe `--profile mqtt --profile linux` como abaixo. **Pare o container do módulo antes de rodá-lo no host.** Os dois disputariam a mesma porta e o mesmo `clientId` MQTT fixo (`tv3ws-client`, `aop-core`, `bcast_svc`), e o broker derruba a conexão anterior quando chega outra com o mesmo id.

```bash
P="--profile mqtt --profile linux"
```

**Se o `.env` da raiz liga o override do SSDP** (`COMPOSE_FILE=docker-compose.yml:docker-compose.ssdp.yml`), prefixe os comandos de subida abaixo com `COMPOSE_FILE=docker-compose.yml`, como o script faz. O override fixa `EDGE_VARIANT=host` e põe a borda em rede do host, então o `EDGE_VARIANT` do comando não teria efeito na borda.

**tv3ws no host** (cenário 1):

```bash
docker compose $P stop tv3ws
EDGE_VARIANT=windows docker compose $P up -d redis mosquitto edgegateway userfiles-seed aop bcast
cd tv3ws && npm ci
MQTT_HOST=127.0.0.1 REDIS_HOST=127.0.0.1 REDIS_PORT=6379 \
HTTP_PORT=44654 HTTPS_PORT=44655 \
JWT_SECRET=tv30-dev-secret-nao-usar-em-producao JWT_ISSUER=GenericIssuer \
USER_THUMBS="$PWD/../user-files/thumbs" \
SERVER_URL=localhost WS_PORT_MIN=45000 WS_PORT_MAX=45199 LOG_LEVEL=INFO \
npm run dev
```

Desde a rodada da reunião de 05/10 com o Joel (D-0510-5), o tv3ws não lê o `USER_DATA_FILE`: os perfis vêm do Redis, que já tem a carga inicial, e quem os escreve é o aop. Desde 10/10, nem o `docker-compose.yml` nem o `scripts/test-dev-host.sh` passam mais essa variável ao tv3ws.

**aop no host** (cenário 2):

```bash
docker compose $P stop aop
EDGE_VARIANT=linux BCAST_HOSTNAME=localhost BCAST_PORT=8081 \
  docker compose $P up -d redis mosquitto edgegateway userfiles-seed tv3ws bcast
cd aop && npm ci
PORT=8080 MQTT_HOST=127.0.0.1 REDIS_HOST=127.0.0.1 REDIS_PORT=6379 \
USER_DATA_PATH="$PWD/../user-files" npm run dev
```

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
# terminal 3: aop, como no cenário 2
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

**Volta à stack padrão:** `EDGE_VARIANT=linux docker compose $P up -d`. O compose recria o bcast com `BCAST_HOSTNAME=bcast` e a borda na variante linux, e sobe de novo os containers parados nos cenários 4 e 5. Sem o prefixo `COMPOSE_FILE`, a volta respeita o `.env`: com o override ligado, a borda volta à rede do host, na variante `host`.

Os três módulos chamam `dotenv.config()`. Um `.env` na pasta do módulo também é lido, mas a variável já definida no shell vence. Rodar `npm ci` direto na pasta do clone troca o `node_modules` dela; o script evita isso trabalhando numa cópia.

## Variáveis que cada módulo exige

tv3ws, aop e bcast encerram com `exit 1` no boot se faltar alguma variável obrigatória.

| Módulo | Obrigatórias (código) | Também necessárias no host |
|---|---|---|
| tv3ws | `MQTT_HOST`, `REDIS_HOST`, `JWT_SECRET`, `USER_THUMBS` (`tv3ws/src/server.ts:10-15`). O `USER_DATA_FILE` saiu da lista na rodada de 05/10 | `HTTP_PORT`/`HTTPS_PORT`: o padrão do código é 44642/44643, **as portas da borda no host**, e daria conflito; a variante windows espera 44654/44655. `SERVER_URL`: sem ela, a URL de remote-device sai `ws://undefined:<porta>` (`core.ts:38`, `modules/remotedevice-manager/remote-device.ts:319`). `WS_PORT_MIN`/`WS_PORT_MAX`: o padrão 1000–9999 (`modules/remotedevice-manager/entry-point.ts:26-27`) pode colidir com 1883, 6379, 8080, 8081 e 9001; use a faixa do container, 45000–45199 |
| aop | `MQTT_HOST`, `USER_DATA_PATH`, `REDIS_HOST` (`aop/src/server.js:17`) | `PORT` (padrão 8080) e `MQTT_WS_PORT` (só vai para o HTML do navegador) |
| bcast | `MQTT_HOST`, `BCAST_HOSTNAME` (`bcast/src/index.ts:21`). O `\|\| 'localhost'` da linha 82 nunca é alcançado | `BSID` e `*_SID` fixos, iguais aos do compose; sem eles, cada boot cria tópicos retidos novos no broker |
| componente de exemplo (`templates/componente`) | nenhuma: os padrões são `mosquitto`, `redis` e a porta 8090 (`templates/componente/index.js:24-31`) | `MQTT_HOST=127.0.0.1` e `REDIS_HOST=127.0.0.1`: os padrões são nomes de serviço, que só resolvem dentro da `ginga_net`, e sem broker ou Redis o exemplo sai com `exit 1` (morre-inteiro). `COMPONENTE_NOME` muda o tópico e a chave do exemplo |

### `JWT_SECRET` compartilhado entre a borda e o tv3ws

O tv3ws **assina** o accessToken (HS256, `JWT_SECRET`, emissor `JWT_ISSUER`). A borda **valida** o mesmo token no plugin `tv30-auth`, em modo `warn` por padrão. Os dois precisam do mesmo segredo e do mesmo emissor, vindos de uma única fonte: o `.env` da raiz ou o shell, com os padrões de desenvolvimento `tv30-dev-secret-nao-usar-em-producao` e `GenericIssuer`. Com o tv3ws no host, exporte os mesmos valores que o compose passa à borda. O script faz isso e prova o vínculo com um token assinado por ele. `JWT_SECRET` dentro de `tv3ws/.env` não tem efeito no container, porque a seção `environment:` do compose tem precedência.

## Regras do arranjo

1. **Quem está no host fala com containers por `127.0.0.1:<porta publicada>`**: 6379 (Redis), 1883 (MQTT), 44642/44643 (borda), 8080 (aop), 8081 (bcast). Com outro processo do host, fala pela porta desse processo, também em `127.0.0.1` (no cenário 4, o aop alcança o bcast em `127.0.0.1:8081`). O script usa `127.0.0.1` em vez de `localhost` para não depender da resolução IPv6.
2. **Quem está em container fala com o host por `host.docker.internal`**, que em Linux só resolve com `extra_hosts: host.docker.internal:host-gateway`. Hoje o `edgegateway` e o `aop` têm essa entrada. Com o override `docker-compose.ssdp.yml`, a borda fica em rede do host e o override tira dela essa entrada.
   - **A comunicação interna não é toda por mensageria.** O aop faz **proxy HTTP direto** para o bcast (`/graphicsAppProxy`, `/videoStreamProxy`, `aop/src/server.js:59-101`). O alvo é o `bcastEntryPackageUrl = http://${BCAST_HOSTNAME}:8081` que o bcast publica na BALD (`bcast/src/index.ts:82-85`). O aop e o tv3ws também leem e escrevem o Redis diretamente.
   - Por isso o `BCAST_HOSTNAME` muda por cenário: `bcast` no deploy, `localhost` com o aop no host (cenário 2), `host.docker.internal` com o bcast no host (cenário 3) e `127.0.0.1` com os dois no host (cenário 4).
   - A porta embutida na URL é a interna (8081), então com o aop no host a porta publicada do bcast também tem de ser 8081.
3. **As portas do tv3ws no host (44654/44655) têm de casar com a variante windows** (`infra/edgegateway/routes.json`, `backends.*.windows`).
4. **Cliente acessa a borda**, não a implementação. As portas 44652/44653 do tv3ws não são publicadas no host; com o override `docker-compose.ssdp.yml`, são publicadas só em `127.0.0.1`, para a borda em rede do host.
5. **Componente novo em container segue o template** [`templates/componente/`](../templates/componente/README.md): `ginga_net` externa, MQTT/Redis pelo nome do serviço, `extra_hosts`, `restart: unless-stopped`, `init: true` e morre-inteiro. Se um processo interno cair, o container cai inteiro. O modelo com mais de um processo é `infra/edgegateway/entrypoint.sh`.
   - O template sobe como veio: traz um componente de exemplo (`Dockerfile`, `index.js`, `package.json` e `package-lock.json`, só com a biblioteca padrão do Node). O exemplo responde por MQTT com um valor lido do Redis e expõe `/health`.
   - `scripts/test-template.sh` executa o template com a stack de pé. Ele copia a pasta, troca o nome, sobe o exemplo e confere a `ginga_net`, a conversa com `redis` e `mosquitto` pelo nome do serviço, a porta publicada e a regra morre-inteiro: mata o processo, o container cai e o `restart` o traz de volta. No fim, remove tudo o que criou.
   - O mesmo exemplo roda no host com `npm run dev`, como na seção "O mesmo componente rodando no host" do README do template. O cenário 5 do `scripts/test-dev-host.sh` faz isso e confere a conversa direta com o Redis e o broker por `127.0.0.1`, com a borda parada.

## Limites

- **Windows nativo não é coberto.** Com o Docker Engine no WSL, `host-gateway` aponta para a VM do WSL, não para o Windows, e um `npm run` no PowerShell não é alcançado pela borda. Também já se observou a porta 1883 do WSL recusando conexão vinda do Windows. Para desenvolver no Windows, rode o módulo dentro do WSL (o modo `docker` do script faz isso). O script recusa rodar no Git Bash.
- **Docker Desktop** não foi testado.
- **No cenário 5, a morte do componente só aparece no fim do prazo.** O `npm run dev` do exemplo é `node --watch index.js`. Se o componente sai com erro (sem Redis ou sem broker), o `node --watch` continua de pé esperando mudança no arquivo, e o script só acusa a falha ao fim do `DEVHOST_TIMEOUT`, mostrando o log do componente.
- **O tv3ws do host anuncia SSDP** na rede do host (UDP 1900), porque fora do compose `SSDP_ENABLED` vale ligado por padrão. No compose, quem anuncia é a borda, só com o override `docker-compose.ssdp.yml` (rede do host; L6, opção A, decidido pelo Luís em 09/10), e o tv3ws da bridge recebe `SSDP_ENABLED: "false"`.
  - Pela regra morre-inteiro, se o anúncio falhar, o processo do host encerra inteiro, APIs inclusive, e o cenário 1 (ou o 4) falha mostrando o log do tv3ws. No deploy com o override, a borda se comporta de outro jeito desde a decisão do Luís de 10/10: só o erro de configuração do anúncio (UDP 1900 ocupada sem `SO_REUSEADDR`, `SSDP_INTERFACE` inexistente, porta inválida) a derruba inteira; sem rede, o anunciante da borda espera e tenta de novo, e as APIs ficam de pé. O anunciante Node do tv3ws não mudou nessa rodada. Para desenvolver sem o anúncio, acrescente `SSDP_ENABLED=false` ao comando do tv3ws (cenários 1 e 4).
  - **Nos cenários 1 e 4, o tv3ws do host é o único anunciante.** O `scripts/test-dev-host.sh` sobe a borda com `COMPOSE_FILE=docker-compose.yml`, na bridge e na variante `windows`, e ela não anuncia. À mão, use o mesmo prefixo: com o override ligado, a borda ficaria em rede do host, na variante `host`, sem backend (ela procura o tv3ws em `127.0.0.1:44652`, e o do host está na 44654) e anunciando junto com o tv3ws do host, com o mesmo UDN.
  - O `LOCATION` e o `/manifest` do tv3ws do host saem do ambiente dele: o tv3ws do host não lê o `.env` da raiz, e responde com o `SERVER_URL` do comando, `localhost` por padrão.
  - Se o container antigo `tv3ws-ssdp` (opção B, substituída em 09/10) ainda estiver de pé, ele é um segundo anunciante do mesmo UDN, e o script não o para mais. Remova-o com `docker rm -f tv3ws-ssdp`; o `preflight` avisa quando ele está de pé.
- **A descoberta SSDP por outro aparelho só funciona em Linux nativo** (decisão do Joel, informada pelo Luís em 04/10). No WSL2 o anúncio não sai da máquina (medido). No Docker Desktop, que também roda o Docker numa VM, espera-se o mesmo (não medido). Nesses ambientes, o cliente não local chega pelo IP (`http://<IP>:44642/manifest`). As medições estão em [ssdp-verificacao.md](ssdp-verificacao.md).
