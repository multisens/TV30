---
title: Desenvolvimento com serviço no host
nav_order: 9
---

# Infra em containers e um módulo rodando no host

Pedido das reuniões de 21/09 e 28/09: quem está implementando algo num dos módulos (tv3ws, aop, bcast ou um componente novo) sobe **só o mínimo** em containers e roda o módulo em desenvolvimento **no host**, com `npm run dev`, sem refazer imagem a cada mudança. Nesta página: o teste que automatiza isso, as três combinações com os comandos completos, as variáveis que cada módulo exige e as regras de rede que o código impõe.

> Mensageria, borda (KrakenD) e Redis são decisões de implementação deste testbed, não da ABNT NBR 25608. Só a porta 44642 da superfície interna é fixada pela norma (C.3.4).

## Teste automatizado: `scripts/test-dev-host.sh`

```bash
./scripts/test-dev-host.sh               # cenários 1, 2 e 3, em ordem
./scripts/test-dev-host.sh --cenario 2   # um só (aceita também 1,3)
./scripts/test-dev-host.sh --build       # repassa --build ao compose (ex.: borda nova)
```

Para cada cenário, o script:

1. para o container do módulo que vai para o host;
2. sobe o mínimo com a variante certa da borda;
3. roda o **módulo real** com `npm ci && npm run dev`, numa cópia temporária sem `node_modules` e sem `.env`;
4. faz as verificações;
5. mata o processo do host.

No fim, restaura a stack padrão (`EDGE_VARIANT=linux`) se ela estava de pé antes, ou a derruba (`docker compose down`) se não estava. O resultado sai como PASS/FAIL por verificação, e o código de saída é diferente de zero se houver alguma falha. Os logs dos módulos ficam num diretório temporário indicado no fim da execução.

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
| 1 | **tv3ws** (HTTP 44654) | redis, mosquitto, edgegateway **windows**, aop, bcast; o `tv3ws-ssdp`, se estiver de pé, é parado e volta no fim | host → Redis (PING); host → MQTT (pub/sub); log `[Redis] Connected` e `Connected to MQTT broker` do tv3ws; borda `44642/health` → tv3ws do host; `GET /tv3/current-service` pela borda com accessToken HS256 assinado com o `JWT_SECRET` compartilhado; depois de matar o tv3ws do host, a borda **para** de responder (prova de que a resposta vinha do host) |
| 2 | **aop** (8080) | redis, mosquitto, edgegateway **linux**, tv3ws, bcast com `BCAST_HOSTNAME=localhost` e `BCAST_PORT=8081` | host → Redis; host → MQTT; log `Loaded N users from Redis` e `Connected to MQTT broker` do aop; o catálogo do aop do host mostra o serviço anunciado pelo bcast (BAMT por MQTT); `/graphicsAppProxy/users-test` do aop do host traz a aplicação do bcast em container (proxy HTTP); borda linux → tv3ws em container |
| 3 | **bcast** (8081) | redis, mosquitto, edgegateway **linux**, tv3ws, aop | host → Redis; host → MQTT; log `MQTT client connected` do bcast; a BALD retida no broker traz `bcastEntryPackageUrl` em `host.docker.internal:8081`; o aop em container mostra o serviço e alcança o bcast do host pelo proxy HTTP; depois de matar o bcast do host, o proxy falha |

As verificações host → Redis e host → MQTT rodam **no mesmo ambiente do módulo**: o mesmo processo Node, ou o mesmo container com `--network host`. O teste de MQTT usa a biblioteca `mqtt` do próprio módulo.

## Variante da borda: depende de onde está o tv3ws

O `edgegateway` encaminha para o tv3ws conforme `EDGE_VARIANT` (`infra/edgegateway/routes.json`, `backends`):

| `EDGE_VARIANT` | Superfície interna 44642 → | Superfície externa 44643 → | Use quando |
|---|---|---|---|
| `linux` (padrão) | `http://tv3ws:44652` | `https://tv3ws:44653` | o tv3ws está **em container** (cenários 2 e 3, deploy) |
| `windows` | `http://host.docker.internal:44654` | `https://host.docker.internal:44655` | o tv3ws está **no host** (cenário 1). O nome é histórico: vale para Linux também |

Com o tv3ws em container e a borda em `windows`, a borda fica sem backend, porque a 44654 não existe no host. Esse era o erro da tabela antiga desta página nas linhas do aop e do bcast.

A superfície externa só tem backend se o tv3ws subir HTTPS (`HTTPS_KEY`/`HTTPS_CERT`). Uma cópia limpa do tv3ws no host, como a do script, sobe só HTTP, e a 44643 fica sem backend no cenário 1. O script não testa a 44643.

## As três combinações, à mão

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
USER_DATA_FILE="$PWD/../user-files/userData.json" USER_THUMBS="$PWD/../user-files/thumbs" \
SERVER_URL=localhost WS_PORT_MIN=45000 WS_PORT_MAX=45199 LOG_LEVEL=INFO \
npm run dev
```

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

**Volta à stack padrão:** `EDGE_VARIANT=linux docker compose $P up -d`. O compose recria o bcast com `BCAST_HOSTNAME=bcast` e a borda na variante linux.

Os três módulos chamam `dotenv.config()`. Um `.env` na pasta do módulo também é lido, mas a variável já definida no shell vence. Rodar `npm ci` direto na pasta do clone troca o `node_modules` dela; o script evita isso trabalhando numa cópia.

## Variáveis que cada módulo exige

Os três encerram com `exit 1` no boot se faltar alguma variável obrigatória.

| Módulo | Obrigatórias (código) | Também necessárias no host |
|---|---|---|
| tv3ws | `MQTT_HOST`, `REDIS_HOST`, `JWT_SECRET`, `USER_DATA_FILE`, `USER_THUMBS` (`tv3ws/src/server.ts:8-14`) | `HTTP_PORT`/`HTTPS_PORT`: o padrão do código é 44642/44643, **as portas da borda no host**, e daria conflito; a variante windows espera 44654/44655. `SERVER_URL`: sem ela, a URL de remote-device sai `ws://undefined:<porta>` (`core.ts:38`, `remote-device.ts:315`). `WS_PORT_MIN`/`WS_PORT_MAX`: o padrão 1000–9999 (`api/multi-device/service.ts:42-43`) pode colidir com 1883, 6379, 8080, 8081 e 9001; use a faixa do container, 45000–45199 |
| aop | `MQTT_HOST`, `USER_DATA_PATH`, `REDIS_HOST` (`aop/src/server.js:17`) | `PORT` (padrão 8080) e `MQTT_WS_PORT` (só vai para o HTML do navegador) |
| bcast | `MQTT_HOST`, `BCAST_HOSTNAME` (`bcast/src/index.ts:21`). O `\|\| 'localhost'` da linha 82 nunca é alcançado | `BSID` e `*_SID` fixos, iguais aos do compose; sem eles, cada boot cria tópicos retidos novos no broker |

### `JWT_SECRET` compartilhado entre a borda e o tv3ws

O tv3ws **assina** o accessToken (HS256, `JWT_SECRET`, emissor `JWT_ISSUER`). A borda **valida** o mesmo token no plugin `tv30-auth`, em modo `warn` por padrão. Os dois precisam do mesmo segredo e do mesmo emissor, vindos de uma única fonte: o `.env` da raiz ou o shell, com os padrões de desenvolvimento `tv30-dev-secret-nao-usar-em-producao` e `GenericIssuer`. Com o tv3ws no host, exporte os mesmos valores que o compose passa à borda. O script faz isso e prova o vínculo com um token assinado por ele. `JWT_SECRET` dentro de `tv3ws/.env` não tem efeito no container, porque a seção `environment:` do compose tem precedência.

## Regras do arranjo

1. **Quem está no host fala com containers por `127.0.0.1:<porta publicada>`**: 6379 (Redis), 1883 (MQTT), 44642/44643 (borda), 8080 (aop), 8081 (bcast). O script usa `127.0.0.1` em vez de `localhost` para não depender da resolução IPv6.
2. **Quem está em container fala com o host por `host.docker.internal`**, que em Linux só resolve com `extra_hosts: host.docker.internal:host-gateway`. Hoje o `edgegateway` e o `aop` têm essa entrada.
   - **A comunicação interna não é toda por mensageria.** O aop faz **proxy HTTP direto** para o bcast (`/graphicsAppProxy`, `/videoStreamProxy`, `aop/src/server.js:59-101`). O alvo é o `bcastEntryPackageUrl = http://${BCAST_HOSTNAME}:8081` que o bcast publica na BALD (`bcast/src/index.ts:82-85`). O aop e o tv3ws também leem e escrevem o Redis diretamente.
   - Por isso o `BCAST_HOSTNAME` muda por cenário: `bcast` no deploy, `localhost` com o aop no host (cenário 2) e `host.docker.internal` com o bcast no host (cenário 3).
   - A porta embutida na URL é a interna (8081), então com o aop no host a porta publicada do bcast também tem de ser 8081.
3. **As portas do tv3ws no host (44654/44655) têm de casar com a variante windows** (`infra/edgegateway/routes.json`, `backends.*.windows`).
4. **Cliente acessa a borda**, não a implementação. As portas 44652/44653 do tv3ws não são publicadas no host.
5. **Componente novo em container segue o template** [`templates/componente/`](../templates/componente/README.md): `ginga_net` externa, MQTT/Redis pelo nome do serviço, `extra_hosts`, `restart: unless-stopped`, `init: true` e morre-inteiro. Se um processo interno cair, o container cai inteiro. O modelo com mais de um processo é `infra/edgegateway/entrypoint.sh`.
   - O template sobe como veio: traz um componente de exemplo (`Dockerfile`, `index.js`, `package.json`, só com a biblioteca padrão do Node). O exemplo responde por MQTT com um valor lido do Redis e expõe `/health`.
   - `scripts/test-template.sh` executa o template com a stack de pé. Ele copia a pasta, troca o nome, sobe o exemplo e confere a `ginga_net`, a conversa com `redis` e `mosquitto` pelo nome do serviço, a porta publicada e a regra morre-inteiro: mata o processo, o container cai e o `restart` o traz de volta. No fim, remove tudo o que criou.
   - O mesmo exemplo roda no host com `npm run dev`, como na seção "O mesmo componente rodando no host" do README do template.

## Limites

- **Windows nativo não é coberto.** Com o Docker Engine no WSL, `host-gateway` aponta para a VM do WSL, não para o Windows, e um `npm run` no PowerShell não é alcançado pela borda. Também já se observou a porta 1883 do WSL recusando conexão vinda do Windows. Para desenvolver no Windows, rode o módulo dentro do WSL (o modo `docker` do script faz isso). O script recusa rodar no Git Bash.
- **Docker Desktop** não foi testado.
- **O tv3ws do host anuncia SSDP** na rede do host (UDP 1900), porque fora do compose `SSDP_ENABLED` vale ligado por padrão. No compose, quem anuncia é o container `tv3ws-ssdp` (perfil `ssdp`), e o tv3ws da bridge recebe `SSDP_ENABLED: "false"`.
  - Pela regra morre-inteiro, se o anúncio falhar, o processo do host encerra inteiro, APIs inclusive, e o cenário 1 falha mostrando o log do tv3ws. No deploy em container isso não acontece mais: a falha derruba só o `tv3ws-ssdp`. Para desenvolver sem o anúncio, acrescente `SSDP_ENABLED=false` ao comando do cenário 1.
  - **Com o `tv3ws-ssdp` de pé, ficam dois anunciantes do mesmo UDN** na rede do host, e o `LOCATION` do `tv3ws-ssdp` pode não casar com o `/manifest` que responde de fato, o do tv3ws do host. O `tv3ws-ssdp` lê o `SSDP_ADVERTISE_HOST` do `.env` da raiz, e o tv3ws do host não lê esse arquivo: o `/manifest` dele responde com o `SERVER_URL`, `localhost` por padrão. Só `SSDP_ENABLED=false` no tv3ws do host tira o segundo anunciante, mas não essa divergência.
  - Por isso o `scripts/test-dev-host.sh` para o `tv3ws-ssdp` no cenário 1 e o religa no fim (teste 27 de [ssdp-verificacao.md](ssdp-verificacao.md)). À mão, pare o anunciante com `docker compose stop tv3ws-ssdp`, que funciona mesmo sem o perfil `ssdp` ativo (teste 25). Para mantê-lo de pé, rode o tv3ws do host com `SSDP_ENABLED=false` e com os valores de `SSDP_ADVERTISE_HOST`, `SERVER_URL`, `EDGE_HTTP_PORT` e `EDGE_HTTPS_PORT` que o `tv3ws-ssdp` recebe (`docker exec tv3ws-ssdp printenv` mostra os valores).
- **A descoberta SSDP por outro aparelho só funciona em Linux nativo** (decisão do Joel, informada pelo Luís em 04/10). No WSL2 o anúncio não sai da máquina (medido). No Docker Desktop, que também roda o Docker numa VM, espera-se o mesmo (não medido). Nesses ambientes, o cliente não local chega pelo IP (`http://<IP>:44642/manifest`). As medições estão em [ssdp-verificacao.md](ssdp-verificacao.md).
