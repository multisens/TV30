# TV 3.0 AoP Experimentation

![Node Version](https://img.shields.io/badge/Node.js-23.11.1-blueviolet?logo=nodedotjs)  ![MQTT](https://img.shields.io/badge/MQTT-blueviolet?logo=mqtt)  ![Docker](https://img.shields.io/badge/Docker-blue?logo=docker)

Testbed do padrão brasileiro de TV digital interativa **TV 3.0** (ABNT NBR 25608). Implementa, em microsserviços, os papéis da plataforma TV 3.0 — receptor (AoP), TV 3.0 WebServices (tv3ws) e broadcaster simulado (bcast) — sobre uma infraestrutura de apoio escolhida por este projeto: borda KrakenD (`edgegateway`, duas superfícies), broker MQTT (Mosquitto com plugin C de validação de schema) e estado em Redis.

> **Norma × implementação:** a ABNT NBR 25608 especifica os TV 3.0 WebServices (Anexo C), o gerenciador de perfis (8.7) e o de privacidade, que trata do consentimento (8.8). A norma não usa o nome "Ginga CC WebServices" nem a sigla CCWS: "Ginga Common Core WebServices" só aparece no título da ABNT NBR 15606-11, uma das referências normativas. O transporte interno via **MQTT**, a **borda KrakenD** e o **Redis** são decisões de arquitetura deste testbed — **não fazem parte da norma**.

É um **monorepo com submodules Git** orquestrado por um único `docker-compose.yml` na raiz. Toda a stack sobe de uma vez só, em qualquer host com Docker, sem build local: as imagens vêm do Docker Hub (`DOCKERHUB_NS` e `IMAGE_TAG` do `.env`), e o CI de cada submódulo as publica a cada push na main dele (ver [*Atualizar submodules*](#atualizar-submodules)).

> **Use imagens da mesma rodada.** Uma imagem que já está na máquina não se atualiza sozinha: depois de um `git pull`, rode `docker compose pull`, ou construa localmente o que ainda não foi publicado (`docker compose build <serviço>`). Pelo código, misturar imagens de rodadas diferentes quebra funções:
> - **Reunião de 05/10 com o Joel** (`tv30-edgegateway`, `tv30-tv3ws`, `tv30-aop`): a borda passou a responder a C.6.8 (`/tv3/bind-context`) e a C.6.7.8/C.6.7.9 (`/tv3/api-info`); o tv3ws ficou sem validação de credencial, sem a C.6.8 e sem escrita de perfis; o AoP ficou dono dos perfis, inclusive do `lastAccess`. Com a borda anterior e o tv3ws novo, a C.6.8 responde 404 `{"error":100}` (a borda antiga repassa a rota a um tv3ws que não a tem mais), e a `/tv3/api-info` também dá 100 (a borda antiga não a declara); com o tv3ws novo e o AoP anterior, ninguém atualiza o `lastAccess` na troca de usuário corrente, e o despejo de perfis passa a contar só a criação do perfil.
> - **Segunda leva de 10/10** (P1.3, P1.9 e P4, decisões do Luís; `tv30-redis`, `tv30-tv3ws`, `tv30-aop`, `tv30-edgegateway`, `tv30-bcast`): o Redis traz as funções que conferem o esquema das escritas, e os serviços gravam no Redis só por elas (P4, [seção própria](#interface-administrativa-do-redis)); o AoP abre cada app de emissora no host próprio dela, e o bcast traz a ponte `aop-bridge.js`, sem a qual as apps não recebem teclas nem eventos do vídeo (P1.3, [seção própria](#apps-de-emissora-um-nome-de-host-por-app)); a borda separa as rotas por superfície (P1.9). Com o Redis anterior, toda escrita dos serviços novos falha (`ERR Function not found`, e a rota responde 404 `{"error":200}`); com um serviço anterior, a escrita dele não passa pelas funções, e o que ficar fora do esquema aparece na auditoria.
> - **Decisões do Luís em 11/10, segunda parte** (as mesmas cinco imagens): o AoP atende o MQTT da página da TV no caminho `/mqtt` da própria porta e gera o id de perfil em UUID; o Redis traz o esquema na versão 2 (id de perfil em UUID) e cai inteiro quando o redis-commander morre; a borda exige o cliente em `clients:authorized`, não tem mais a rota `POST /tv3/{serviceContextId}/users` e exige `SSDP_ADVERTISE_HOST` com o anúncio ligado; o tv3ws expõe ao navegador os cabeçalhos do `/manifest`; o bcast cita o id novo do perfil da carga na webmedia. O AoP anterior com o compose novo quebra duas coisas: a página da TV conecta na 9001 do host, que deixou de ser porta fixa, e a criação de perfil grava `user_<epoch-ms>`, que o esquema recusa (404 `{"error":200}`). Um volume do Redis criado antes de 11/10 fica fora do esquema e precisa ser recriado (`docker compose down -v`; ver [*Interface administrativa do Redis*](#interface-administrativa-do-redis)).
> - **Decisões do Luís em 12/10** (`tv30-edgegateway`, `tv30-redis`): a borda tira da 44643 a `GET /tv3/remote-device/devices/{classId}` (C.6.15.5, só para o cliente local), e o Redis traz o esquema na versão 3 (UUID estrito no id do perfil). Pelo código, misturar estas duas com as de 11/10 não quebra função: com a borda anterior, a C.6.15.5 continua na 44643; com o Redis anterior, um UUID fora da versão ou da variante passa. O volume de 11/10 continua válido no esquema novo.

---

## Pré-requisitos

- **Docker Engine** + **Compose v2** (`docker compose`, não `docker-compose`).
- **Git** com suporte a submodules.

### `~/.wslconfig` recomendado (apenas Windows)

Crie ou edite `C:\Users\<voce>\.wslconfig`:

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
vmIdleTimeout=86400000
```

Depois aplique:

```powershell
wsl --shutdown
```

E reabra a distribuição. **Não use `networkingMode=mirrored`** — Docker faz NAT via iptables e o modo mirrored não espelha bem pro host Windows, dando timeout em `localhost:PORT`. O `vmIdleTimeout=86400000` (24h) evita que a VM seja desligada por idle, o que derrubaria os containers.

---

## Quick start

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
cd TV30
cp .env.example .env
docker compose up -d
```

Abra http://localhost:8080 — interface do receptor (AoP).

> **Clone antigo (anterior ao renome `ccws` → `tv3ws`):** o `git pull` não propaga renome de submódulo para um clone que já existe. Rode `git submodule sync --recursive && git submodule update --init --recursive` e apague à mão a pasta `ccws/` que sobrou — ou clone de novo.

> **URL do submódulo `bcast` (C5, decisão do Luís em 11/10):** o `.gitmodules` aponta o `bcast` por HTTPS (`https://github.com/multisens/BcastService.git`), e o clone não precisa mais de chave SSH no GitHub. Até 11/10 a URL era SSH (`git@github.com:multisens/BcastService.git`), e quem não tinha chave não clonava esse submódulo. Num clone feito antes, o `git pull` traz o `.gitmodules` novo, mas o `.git/config` guarda a URL antiga: rode `git submodule sync --recursive && git submodule update --init --recursive`.

> **Primeira subida — o que acontece sozinho:** one-shots preparam o
> ambiente antes dos serviços. O `preflight` diagnostica DNS e portas
> ocupadas e imprime avisos legíveis no início do log (`docker logs
> tv30-preflight`) — se a subida falhar com `address already in use`, o
> dono da porta já está nomeado ali (triagem completa em
> [`docs/troubleshooting.md`](./docs/troubleshooting.md)). Ele só para a
> subida em dois casos: a 44642 ocupada por outro processo e, com o
> `docker-compose.ssdp.yml`, a falta de `SSDP_ADVERTISE_HOST`. O
> `userfiles-seed` cria e popula `./user-files` a partir do template —
> não é preciso criar nada manualmente. No perfil `linux`, o `sysctl-init`
> desliga o `net.bridge.bridge-nf-call-iptables` do host, quando o kernel
> deixa. O `tv3ws/.env` também é
> **opcional**: sem ele o tv3ws sobe em HTTP com um `JWT_SECRET` default
> de desenvolvimento, e a superfície externa da borda não chega a ele (ver
> a seção de HTTPS abaixo para habilitar o 44653).

> **Importante — não rode `docker compose` em `infra/`.** O `infra/` é submodule e seu compose é incluído automaticamente via `include:` no `docker-compose.yml` da raiz. **Toda a stack sobe de uma vez pela raiz.** Subir `compose` dentro de `infra/` não vê os serviços `aop`,  `tv3ws` e `bcast` (que ficam no compose raiz) e gera confusão de rede.

> **Importante — sem `.env` na raiz, os serviços principais ficam fora silenciosamente.** Os containers `aop`, `tv3ws`, `bcast`, `mosquitto` e `sysctl-init` têm `profiles: [linux]` ou `[mqtt]` no compose. Sem `COMPOSE_PROFILES=mqtt,linux` (que vem no `.env.example`), só sobe a infra (redis, edgegateway) e nada funciona end-to-end. Sempre comece com `cp .env.example .env`.

> **Portas fixas e portas escolhidas pelo Docker (C1, decisão do Luís em 11/10; a 44643, revista por ele em 12/10).** Ficam fixas no host a 44642 (norma, C.3.4), a 44643 (superfície externa da borda), a do AoP (8080, `AOP_PUBLIC_PORT`), a 1883 (MQTT), a 6379 (Redis) e a faixa 45000–45199 (remote-device). A 44643 é fixa por padrão desde 12/10, também na bridge, porque o `/manifest` a anuncia (`Server-SecureBaseURL`); de 11/10 a 12/10 ela saía numa porta escolhida pelo Docker. As outras saem numa porta livre que o Docker escolhe a cada criação do container: a 8081 do bcast, a 9001 (MQTT por WebSocket) do Mosquitto, a 8085 da documentação e a 18081 do redis-commander; com o `docker-compose.ssdp.yml`, a 8085 também fica fixa. Para achar a porta de uma delas: `docker compose port <serviço> <porta do container>` (por exemplo, `docker compose port bcast 8081`) ou `docker compose ps`. Para fixar uma, defina no `.env` `BCAST_PUBLISH` ou `MQTT_WS_PUBLISH` como `host:container` (por exemplo, `BCAST_PUBLISH=8081:8081`); `EDGE_EXT_PUBLISH` faz o mesmo com a 44643 e, só com o número (`EDGE_EXT_PUBLISH=44643`), a põe numa porta escolhida pelo Docker, que o `/manifest` não anuncia. A página da TV não usa mais a 9001 do host: ela conecta em `ws://<host da página>/mqtt`, na porta do próprio AoP, que repassa ao Mosquitto (`aop/src/mqtt-ws.js`). Com o AoP em container, não é preciso trocar portas no Windows; para quem roda o AoP fora do Docker no Windows, ver a dica em [*Variáveis do `.env`*](#variáveis-do-env-raiz).

---

## Variáveis do `.env` (raiz)

| Variável | Default | Descrição |
|----------|---------|-----------|
| `COMPOSE_PROFILES` | `mqtt,linux` | Profiles ativos. Sem isto, `aop`/`tv3ws`/`bcast`/`mosquitto`/`sysctl-init` não sobem. O perfil `ssdp` deixou de existir em 09/10. |
| `COMPOSE_FILE` | comentada (só o `docker-compose.yml`) | `docker-compose.yml:docker-compose.ssdp.yml` liga a descoberta SSDP: a borda vai para a rede do host e anuncia (só Linux nativo, ver [seção própria](#descoberta-ssdp-só-linux-nativo)). |
| `DOCKERHUB_NS` | `labmultisens` | Namespace do Docker Hub de onde puxar as imagens. |
| `IMAGE_TAG` | `latest` | Tag das imagens. `latest` puxa o build mais recente da main de cada submodule. |
| `EDGE_EXT_PUBLISH` | comentada (padrão `44643:44643`) | O que vai em `ports` para a superfície externa da borda. `host:container` fixa (o padrão, desde 12/10, decisão do Luís); outra porta de host (por exemplo, `44743:44643`) pede o mesmo número em `EDGE_HTTPS_PORT`, que o tv3ws lê do `.env` da raiz ou do `tv3ws/.env`, senão o `/manifest` anuncia a 44643. Só o número (`44643`, o padrão de 11/10 a 12/10) = porta de host escolhida pelo Docker, que o `/manifest` não anuncia. No modo SSDP não vale: a borda fica em rede do host, na 44643. |
| `BCAST_PUBLISH` | comentada (padrão `8081`) | O mesmo para o bcast: só o número = porta de host escolhida pelo Docker; `8081:8081` fixa, o que o desenvolvimento com o aop no host precisa ([`docs/dev-local.md`](./docs/dev-local.md)). Substitui o `BCAST_PORT` de antes de 11/10, que o compose não lê mais. |
| `MQTT_WS_PUBLISH` | comentada (padrão `9001`) | O mesmo para o MQTT por WebSocket do Mosquitto (9001 do container): só o número = porta de host escolhida pelo Docker; `host:container` fixa. A página da TV não usa essa porta: conecta no `/mqtt` do AoP. Substitui o `MQTT_WS_PORT` no publish do Mosquitto. |
| `AOP_PUBLIC_PORT` | `8080` | Porta do AoP publicada no host, fixa (C1). É também a porta da origem de cada app de emissora (`http://<app>.<APPS_DOMAIN>:<porta>`), por isso vai ao container do AoP (ver [seção própria](#apps-de-emissora-um-nome-de-host-por-app)), e a do MQTT por WebSocket da página da TV (`/mqtt`). |
| `APPS_DOMAIN` | `apps.localhost` | Domínio dos nomes de host das apps de emissora. **`*.localhost` só funciona com a tela do AoP aberta na própria máquina**; para abrir de outra máquina, use um domínio resolvível na rede, com `*.<domínio>` apontando para a máquina do AoP. Valor inválido encerra o AoP no boot. |
| `EDGE_VARIANT` | `linux` | Para onde a borda encaminha: `linux` = tv3ws em container; `windows` = tv3ws rodando no host (desenvolvimento, ver [`docs/dev-local.md`](./docs/dev-local.md)); `host` = borda em rede do host, que o `docker-compose.ssdp.yml` define sozinho (não defina à mão). |
| `SERVER_URL` | `localhost` | Host que dispositivos externos usam para abrir os WebSockets de remote-device. Com `SSDP_ADVERTISE_HOST` vazia, também é o host do `/manifest` do tv3ws (`Server-BaseURL`). O anunciante da borda não o usa desde 11/10 (B2). |
| `SSDP_ADVERTISE_HOST` | vazia | Host do `LOCATION` do anúncio SSDP e do `/manifest` (`Server-BaseURL`): o IP (ou nome) da máquina na LAN. **Obrigatória com o `docker-compose.ssdp.yml`** (B2, decisão do Luís em 11/10): sem ela, o `preflight` para a subida com a mensagem, e o anunciante da borda sairia com erro de configuração. O `tv3ws` (`/manifest`) e a borda (anúncio) a leem do `.env` da raiz ou do `tv3ws/.env` (o da raiz prevalece); valor só exportado no shell não chega a eles. |
| `SSDP_INTERFACE` | vazia | Nome da interface de rede por onde a borda anuncia. Vazia = a que tem o IP anunciado, senão a da rota padrão. Nome de interface inexistente, ou a de loopback, derruba a borda (erro de configuração); interface que existe sem IPv4 faz o anunciante esperar a rede, sem derrubar a borda (decisão do Luís em 10/10). |
| `JWT_SECRET` / `JWT_ISSUER` | default de desenvolvimento / `GenericIssuer` | Segredo e emissor do accessToken. O **mesmo** valor vai para o tv3ws (que assina) e para a borda (que valida). |
| `AUTH_ENFORCE` | `warn` | Validação de credenciais na borda: `warn` só registra (log `[tv30-auth] WARN` + cabeçalho `X-TV30-Auth-Warn`); `enforce` rejeita com 404 + corpo C.3.2. |
| `REDIS_COMMANDER_USER` / `REDIS_COMMANDER_PASSWORD` | `admin` / `tv30-redis-admin` | Login da interface administrativa do Redis (ver [seção própria](#interface-administrativa-do-redis)). Não muda a conexão com o banco (6379), que segue sem senha. |

**Variáveis que saíram em 11/10 (C1):** o `BCAST_PORT` (porta de host fixa do bcast) e o `MQTT_WS_PORT` do `.env` da raiz (porta de host fixa do Mosquitto, que a página da TV usava) não são mais lidos pelo compose; um `.env` antigo com elas não muda nada. O `MQTT_WS_PORT` continua existindo no AoP, com outro sentido: a porta em que o AoP alcança o WebSocket do Mosquitto para o repasse do `/mqtt`. No compose ela é fixa em 9001, a porta interna do Mosquitto; com o AoP rodando no host, é a porta publicada (`docker compose port mosquitto 9001`; [`docs/dev-local.md`](./docs/dev-local.md)).

**Dica para quem roda o AoP fora do Docker no Windows** (opção, não regra; decisão do Luís em 12/10): `MQTT_WS_PUBLISH=9003:9001` no `.env` da raiz e `MQTT_WS_PORT=9003` no `aop/.env`. Assim a porta publicada do WebSocket do Mosquitto não muda a cada recriação do container e fica fora da 9001 e da 9002, que o conselho de antes de 11/10 dava como ocupadas pelo Hyper-V nessas máquinas. Esse arranjo (AoP no Windows, Docker no WSL) não é coberto pelo `scripts/test-dev-host.sh`.

O `tv3ws/.env` é **opcional**: sem ele o tv3ws sobe normalmente, em HTTP, com um `JWT_SECRET` default de desenvolvimento. Para usar um `JWT_SECRET` próprio, defina-o no **`.env` da raiz** (a seção `environment:` do compose tem precedência sobre `env_file`, então `JWT_SECRET` dentro de `tv3ws/.env` não tem efeito) — assim a borda recebe o mesmo valor. Para habilitar HTTPS, ver a próxima seção — `HTTPS_CERT`/`HTTPS_KEY` estes sim vêm do `tv3ws/.env`.

---

## (Opcional) Habilitando HTTPS no tv3ws

Por padrão o tv3ws sobe **somente em HTTP** (porta 44652, interna à rede do Docker), que é o backend da superfície interna da borda (44642). A superfície externa (44643) repassa ao HTTPS do tv3ws (`https://tv3ws:44653`, `infra/edgegateway/routes.json`): sem ele, as rotas que a borda repassa pela 44643, inclusive `/health` e `/manifest`, respondem 404 `{"error":200}`, e só as que a própria borda responde (ali, o `GET /tv3/bind-context` e a C.6.7.8/C.6.7.9) funcionam. Para habilitar o HTTPS (porta interna 44653), forneça cert + chave em **base64** nas variáveis `HTTPS_CERT` e `HTTPS_KEY` do arquivo `tv3ws/.env` (crie a partir de `tv3ws/.env.example`). A borda em si ainda escuta HTTP nas duas superfícies (TLS na borda: pendente). Para desenvolvimento, gere um certificado autoassinado:

### 1. Gerar cert e chave

```bash
openssl req -x509 -newkey rsa:2048 -days 365 -nodes \
  -subj "/CN=localhost/O=TV30Dev/C=BR" \
  -keyout key.pem -out cert.pem
```

### 2. Converter para base64 (sem quebras de linha)

**Linux / WSL:**
```bash
base64 -w0 cert.pem
base64 -w0 key.pem
```

**macOS** (o `base64` do BSD já vem sem quebras):
```bash
base64 -i cert.pem
base64 -i key.pem
```

**Windows PowerShell:**
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('cert.pem'))
[Convert]::ToBase64String([IO.File]::ReadAllBytes('key.pem'))
```

### 3. Colar no `tv3ws/.env`

```env
HTTPS_CERT=<saída base64 do cert.pem>
HTTPS_KEY=<saída base64 do key.pem>
```

Depois `docker compose up -d` (ou `docker compose restart tv3ws` se a stack já tava no ar).

---

## Mapa de portas e URLs úteis

| Serviço | Porta(s) host | URL / observação |
|---------|---------------|------------------|
| AoP (UI do receptor) | `${AOP_PUBLIC_PORT:-8080}`, fixa | http://localhost:8080. Na mesma porta, o MQTT por WebSocket da página da TV: `ws://<host da página>/mqtt`, repassado ao Mosquitto (só no host do AoP; num host de app, 404) |
| Apps de emissora (camada gráfica do AoP) | a mesma do AoP | `http://<app>.apps.localhost:8080/graphicsAppProxy<bcastEntryPointUrl>`: o AoP roteia pelo cabeçalho `Host` (P1.3; prefixo mantido desde 11/10). Só na própria máquina, ver [seção própria](#apps-de-emissora-um-nome-de-host-por-app) |
| tv3ws (TV 3.0 WebServices) | — (44652/44653 só na rede do Docker) | Não publicado no host: clientes entram pela borda (44642/44643). Com o `docker-compose.ssdp.yml`, a 44652/44653 é publicada só em `127.0.0.1`, para a borda. HTTPS interno somente com `HTTPS_CERT`/`HTTPS_KEY` no `tv3ws/.env` |
| tv3ws — WebSockets de remote-device | 45000–45199 | Portas dinâmicas devolvidas no registro (`ws://SERVER_URL:<porta>`) |
| edgegateway — anúncio SSDP (só com o `docker-compose.ssdp.yml`) | UDP 1900, na rede do host | Processo `ssdp-announcer` da borda. O `LOCATION` aponta para a própria borda (`http://<host>:44642/manifest`) |
| edgegateway — superfície externa | 44643, fixa por padrão (`EDGE_EXT_PUBLISH`, decisão do Luís em 12/10) | só as rotas que admitem o cliente não local (P1.9): 23 das 26 da tabela, sem `POST` e `DELETE /tv3/bind-context` e, desde 12/10, sem `GET /tv3/remote-device/devices/{classId}` (C.6.15.5, só para o cliente local), que ali dão 100 (tabela única M4). As rotas repassadas só chegam ao tv3ws com o HTTPS dele ligado (seção acima) |
| edgegateway — superfície interna | 44642 | porta FIXA da norma (C.3.4); as 26 rotas da tabela. Numa rota restrita por classe (por exemplo, a C.6.15.5, só para o cliente local), o cliente de outra classe recebe 106 em `enforce`, e só o aviso em `warn` |
| bcast (broadcaster) | 8081 do container, numa porta de host escolhida pelo Docker (`docker compose port bcast 8081`; `BCAST_PUBLISH` fixa) | `http://localhost:<porta>` — apps de serviço (webmedia, uff, etc.). O AoP chega ao bcast pela `ginga_net` (`bcast:8081`), sem depender dessa porta |
| Mosquitto MQTT | 1883, fixa | Broker TCP |
| Mosquitto WS | 9001 do container, numa porta de host escolhida pelo Docker (`docker compose port mosquitto 9001`; `MQTT_WS_PUBLISH` fixa) | WebSocket. A página da TV não o usa direto: conecta no `/mqtt` do AoP |
| Redis | 6379, fixa | Estado de sessão + perfis (acesso TCP, ex.: `redis-cli`), sem senha |
| Redis Commander (embutido no redis) | dinâmica | `docker port redis 18081` mostra a porta; exige login (ver abaixo) |
| edgegateway — docs | dinâmica (8085 fixa com o `docker-compose.ssdp.yml`) | Swagger UI + 2 specs: `docker port edgegateway 8085`; com a borda em rede do host, `http://localhost:8085` |

> **A 44643 é fixa por padrão porque o receptor a divulga** (decisão do Luís em 12/10, revendo a C1 de 11/10 nesse ponto): o `/manifest` diz `Server-SecureBaseURL: <host>:44643` (`tv3ws/src/ssdp-config.ts`, porta `EDGE_HTTPS_PORT`, padrão 44643), e o OpenAPI da externa, na documentação Swagger, aponta para `http://localhost:44643` (`infra/edgegateway/generate.js`, porta da superfície no `routes.json`). Com `EDGE_EXT_PUBLISH=44643` (só o número), a externa vai para uma porta escolhida pelo Docker, e nenhum dos dois a acompanha; com outra porta fixa, `EDGE_HTTPS_PORT` corrige o `/manifest`, mas não o OpenAPI. Ver `KNOWN-ISSUES.md`.

---

## Apps de emissora: um nome de host por app

Decisão do Luís em 10/10 (P1.3): o AoP abre cada app de emissora num nome de host próprio, na mesma porta do AoP, e não mais na origem do próprio AoP. Desde 11/10 (decisão do Luís), a URL mantém o prefixo do caminho antigo, para quem já conhece o projeto ver por onde a app passa: `http://<app>.apps.localhost:8080/graphicsAppProxy<bcastEntryPointUrl>`, por exemplo `http://urn-tv30-app-users-test.apps.localhost:8080/graphicsAppProxy/users-test`. Assim o navegador manda, nas chamadas da app às APIs, o `Origin` dela, que é só esquema, host e porta. O AoP grava essa origem em `origins:associated` ao lançar a app e a apaga ao encerrá-la, e é por ela que a borda reconhece a app como cliente local associado (L1). Nome de host por app, proxy e lista no Redis são escolhas deste testbed: a norma deixa o mecanismo de diferenciação à implementação (C.4.1.7).

- **O nome.** `<app>` é um rótulo DNS tirado do `appId` da BALD: minúsculas, só `[a-z0-9-]`, até 63 caracteres (`urn:tv30:app:users-test` vira `urn-tv30-app-users-test`). Desde 11/10 (decisão do Luís), cada app do bcast tem `appId` fixo, `urn:tv30:app:<módulo>` (`eduplay`, `uff`, `users-test`, `webmedia`), e o nome e o que a app guarda no navegador sobrevivem ao reinício do bcast. Com o bcast fora do container, `EDUPLAY_APP_ID`, `UFF_APP_ID`, `USERS_TEST_APP_ID` e `WEBMEDIA_APP_ID` trocam o `appId` (`bcast/README.md`); o compose não as repassa ao container. Até 11/10, o bcast sorteava o `appId` a cada partida, e o nome mudava quando o bcast reiniciava.
- **O proxy.** O AoP atende esses nomes com um proxy para o `bcastEntryPackageUrl` da app em execução (`aop/src/app-hosts.js`). Nome sem app em execução responde 404; app fora do ar, 502. No host da app, o prefixo `/graphicsAppProxy` é opcional: com ele, sai antes de o pedido ir ao bcast; sem ele, como nos `/js/...` e `/media/...` que a página pede a partir da raiz, o caminho vai como está.
- **Limite: só na própria máquina.** `*.localhost` resolve para a máquina de quem abre a página. Com a tela do AoP aberta de **outra máquina**, as apps não carregam. Para esse caso, defina `APPS_DOMAIN` com um domínio resolvível na rede, com `*.<domínio>` apontando para a máquina do AoP (DNS curinga). Se a porta do AoP no host não for 8080, defina `AOP_PUBLIC_PORT`: ela muda a porta publicada e a origem das apps juntas.
- **Navegadores conferidos em 10/10, fora da stack:** Firefox 154 no receptor Linux (`*.apps.localhost` resolve para `::1`, e uma requisição para outra origem saiu com `Origin: http://teste.apps.localhost:8099`) e Chrome 154 headless no Windows (o `Origin` foi o mesmo que o AoP grava). O QtWebEngine não foi testado.
- **Teclas e eventos do vídeo.** Com a app em outra origem, o AoP os entrega por `postMessage`. Toda app da camada gráfica precisa incluir `bcast/public/js/aop-bridge.js` (ver `bcast/README.md`); sem ela, não recebe teclas.
- **Caminho antigo.** No host do próprio AoP, `http://localhost:8080/graphicsAppProxy/<caminho>` redireciona (302) para o mesmo caminho no host da app em execução; sem app em execução, responde 404 (decisão do Luís em 11/10). Ele não serve mais a app na origem do AoP. Até 11/10, servia, para scripts de teste e `curl`, sem gravar origem associada.

Detalhes, decisões de 10/10 e 11/10 e o que segue aberto: [`docs/decisoes-pendentes.md`](./docs/decisoes-pendentes.md), seção F.

---

## Interface administrativa do Redis

O container `redis` embute o Redis Commander (0.9.0, versão fixada no `infra/redis/Dockerfile`, porque o login depende dos nomes de variável dela), interface web para inspecionar o banco durante o desenvolvimento. Ela exige usuário e senha (decisão D-L1, tomada pelo Luís em 03/10).

- **URL:** a porta de host é dinâmica. `docker port redis 18081` mostra qual é (ex.: `0.0.0.0:32768`), e a interface fica em `http://localhost:<porta>/`.
- **Morre-inteiro também para ela (C2, decisão do Luís em 11/10):** se o processo do commander cair, o container `redis` inteiro cai, e o `restart: unless-stopped` o traz de volta (`infra/redis/entrypoint.sh`). Até o Redis voltar e ficar saudável, os serviços recebem a falha do Redis (as APIs respondem 404 `{"error":200}`). Até 11/10, o commander era a exceção do morre-inteiro, e a morte dele não derrubava o banco.
- **Usuário padrão:** `admin`
- **Senha padrão:** `tv30-redis-admin`
- **Para trocar:** defina `REDIS_COMMANDER_USER` e `REDIS_COMMANDER_PASSWORD` no `.env` da raiz e recrie o container com `docker compose up -d redis`. Valor vazio volta ao padrão. Troque a senha padrão fora do laboratório.
- **Como o login funciona:** não é HTTP basic auth, então o navegador não abre a janela de autenticação. A página inicial carrega e mostra um formulário de login. Sem login, as rotas que leem o banco respondem 401.

> **A conexão com o banco (porta 6379) continua sem senha.** A senha protege só a interface administrativa. tv3ws, AoP, borda e `redis-cli` conectam como antes, sem `requirepass`.

> **Esquema nas escritas (P4, decisão do Luís em 10/10):** o código grava no Redis só por funções que conferem o esquema (`infra/redis/esquema.json`), e o que for gravado à mão pela interface ou pelo `redis-cli` aparece na auditoria, `docker exec redis redis-cli FCALL_RO tv30_auditoria 0` (ver [Modelo de dados Redis](docs/modelo-redis.md)).

O login é configurado pelo entrypoint da imagem `tv30-redis`. Uma imagem construída antes de 03/10, ou puxada do Docker Hub antes da publicação das imagens novas, sobe a interface **sem** login, mesmo com as variáveis definidas. Nesse caso, reconstrua com `docker compose build redis && docker compose up -d redis`.

> **Volume de antes de 11/10: id de perfil fora do esquema (F-3, decisão do Luís em 11/10).** O esquema do Redis exige o id do perfil em UUID, como a Tabela 7, sem compatibilidade com os ids antigos (`user_<epoch-ms>`, gerados pelo AoP, e `c3167a18-5dc5`, da carga inicial). Desde 12/10 (decisão do Luís, esquema na versão 3), o UUID é estrito: versão de 1 a 8 e variante da RFC 9562 (`8`, `9`, `a` ou `b`), com o UUID nulo e o máximo recusados. A carga nova traz `c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10` (versão 4, variante `9`), e o AoP gera `crypto.randomUUID()` (versão 4): um volume de 11/10 continua válido. Num volume de antes, a auditoria aponta os perfis antigos, e as funções recusam gravar perfil e atributos de emissora com o id antigo (`infra/redis/README.md`). Como a carga só roda em banco vazio, o volume antigo também não recebe o perfil novo. Para começar limpo: `docker compose down -v`, que apaga os perfis criados e os retidos do broker. Quem clona o projeto agora não é afetado. O `user-files/userData.json` da raiz, cópia local do template feita na primeira subida (fora do git), fica com os ids antigos, mas nenhum serviço o lê.

---

## Descoberta SSDP (só Linux nativo)

O receptor se anuncia por SSDP (ABNT NBR 25608, C.3.4) para que outro aparelho da rede o encontre. Quem anuncia é a borda (L6, opção A, decidido pelo Luís em 09/10): o override `docker-compose.ssdp.yml` põe o `edgegateway` em rede do host e liga o anunciante dele, um processo em Go (`infra/edgegateway/ssdp/`). O `/manifest` continua no tv3ws, atrás da borda, e o resto da stack continua na `ginga_net`. A descoberta só é suportada em **Linux nativo com Docker Engine** (decisão do Joel, informada pelo Luís em 04/10). Nesse ambiente, um segundo aparelho encontrou o receptor em 09/10, primeiro com a opção B, anterior (o container `tv3ws-ssdp`), e depois com a opção A (um notebook no mesmo Wi-Fi; testes 40 a 43 de [`docs/ssdp-verificacao.md`](./docs/ssdp-verificacao.md)). No Windows com WSL2, o anúncio em rede do host não sai da máquina (medido em 03 e 04/10, com um anunciante descartável em modo host). O Docker Desktop, que também roda o Docker numa VM, fica fora do suporte.

No `.env` da raiz (o `COMPOSE_PROFILES` fica como está):

```env
COMPOSE_FILE=docker-compose.yml:docker-compose.ssdp.yml
SSDP_ADVERTISE_HOST=192.168.0.12   # IP desta máquina na rede local (obrigatório)
```

Depois, `docker compose up -d` e `docker logs edgegateway`. Libere a UDP 1900 e a TCP 44642 no firewall do host.

- Com o override, a borda sai da `ginga_net`: ocupa a 44642, a 44643 e a 8085 direto no host, fixas nesse modo, e fala com o tv3ws por `127.0.0.1` (o tv3ws publica a 44652/44653 só nesse endereço).
- **`SSDP_ADVERTISE_HOST` é obrigatório (B2, decisão do Luís em 11/10).** Sem ele, ou vazio, o `preflight` para a subida (`docker logs tv30-preflight`: `ERRO: o anuncio SSDP esta ligado (docker-compose.ssdp.yml) e falta SSDP_ADVERTISE_HOST`), e a borda não sobe; se chegasse a subir, o anunciante sairia com erro de configuração e a derrubaria. O `SERVER_URL` deixou de ser fonte do host do anúncio. Consequência: o `LOCATION` é o do `.env` e não acompanha uma troca de rede. Um valor de loopback (`localhost`, `127.0.0.1`) é aceito, com `[ssdp] AVISO`, e outro aparelho não alcança o endereço.
- **Falha do anúncio (morre-inteiro decidido pelo Luís em 09/10, revisto por ele em 10/10):** erro de configuração (`SSDP_ADVERTISE_HOST` ausente ou vazio, UDP 1900 ocupada por outro processo sem `SO_REUSEADDR`, interface inexistente (ou a de loopback) em `SSDP_INTERFACE`, porta inválida em `EDGE_HTTP_PORT`/`EDGE_HTTPS_PORT`) derruba a borda inteira, com todas as APIs, e o `restart` a traz de volta. A falta de rede (nenhuma interface com IPv4, nenhuma rota padrão, erro de envio por rede) não derruba: o anunciante para de anunciar, avisa no log e tenta de novo, e as APIs ficam de pé. Detalhes no C8 de [`docs/decisoes-pendentes.md`](./docs/decisoes-pendentes.md).
- **O `/manifest` expõe os seus cabeçalhos ao navegador (B3, decisão do Luís em 11/10):** ele manda `Access-Control-Expose-Headers` com os seis nomes (`Server-BaseURL`, `Server-SecureBaseURL`, `Server-PairingMethods`, `Device-BrandName`, `Device-Model`, `Device-FriendlyName`; `tv3ws/src/manifest.ts`), e uma página de outra origem os lê pelo `fetch`.
- Sem o override, nada é anunciado. O cliente ainda chega ao receptor pelo IP: `http://<IP>:44642/manifest`. Para desligar, comente o `COMPOSE_FILE` e rode `docker compose up -d`.
- **Quem usava a opção B** (perfil `ssdp`, que deixou de existir): remova o container antigo, `docker rm -f tv3ws-ssdp` (ou `docker compose up -d --remove-orphans`). O `preflight` avisa se ele estiver de pé.
- Uma imagem da borda de antes de 09/10 não tem o anunciante nem a variante `host`: `docker compose pull edgegateway` ou `docker compose build edgegateway`.
- Arranjo, como ligar e roteiro de teste com um segundo aparelho: [`docs/ssdp.md`](./docs/ssdp.md); medições: [`docs/ssdp-verificacao.md`](./docs/ssdp-verificacao.md).

---

## Atualizar submodules

```bash
# Após clone sem --recurse-submodules:
git submodule update --init --recursive

# Atualizar todos os submodules pro main mais recente:
git submodule update --remote

# Atualizar só um:
git submodule update --remote aop
```

Cada submodule (aop, bcast, tv3ws, infra) tem um workflow `.github/workflows/bump-tv30-pointer.yml` que dispara em push na main e atualiza automaticamente o ponteiro do submodule aqui no TV30 — então em geral basta `git pull` periódico na raiz.

---

## Documentação aprofundada

- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — arquitetura: canais entre serviços, tópicos MQTT, containers e portas, decisões arquiteturais. O modelo de dados do Redis está em [`docs/modelo-redis.md`](./docs/modelo-redis.md).
- [`docs/`](./docs/) — site Jekyll com guias detalhados (troubleshooting, padrões de apps de serviço, etc.).
- [`docs/dev-local.md`](./docs/dev-local.md) — desenvolvimento com um módulo rodando no host (`npm run dev`) e a infra em containers; teste automatizado em `scripts/test-dev-host.sh` e template de compose para componente novo em [`templates/componente/`](./templates/componente/README.md).

---

## Contribuições

Cada submodule tem uma GitHub Action que, ao push na sua main, constrói e publica no Docker Hub as imagens dele (o `infra` publica `tv30-edgegateway`, `tv30-redis` e `tv30-mosquitto`) e depois atualiza o hash do submodule aqui no TV30. Para o desenvolvedor, basta commitar na main do submodule — o TV30 e as imagens são atualizados sozinhos.
