# TV 3.0 AoP Experimentation

![Node Version](https://img.shields.io/badge/Node.js-23.11.0-blueviolet?logo=nodedotjs)  ![MQTT](https://img.shields.io/badge/MQTT-blueviolet?logo=mqtt)  ![Docker](https://img.shields.io/badge/Docker-blue?logo=docker)

Testbed do padrão brasileiro de TV digital interativa **TV 3.0** (ABNT NBR 25608). Implementa, em microsserviços, os papéis da plataforma TV 3.0 — receptor (AoP), TV 3.0 WebServices (tv3ws) e broadcaster simulado (bcast) — sobre uma infraestrutura de apoio escolhida por este projeto: borda KrakenD (`edgegateway`, duas superfícies), broker MQTT (Mosquitto com plugin C de validação de schema) e estado em Redis.

> **Norma × implementação:** a ABNT NBR 25608 especifica os Ginga CC WebServices (CCWS), o modelo de consentimento e os perfis de usuário. O transporte interno via **MQTT**, a **borda KrakenD** e o **Redis** são decisões de arquitetura deste testbed — **não fazem parte da norma**.

É um **monorepo com submodules Git** orquestrado por um único `docker-compose.yml` na raiz. Toda a stack sobe de uma vez só, em qualquer host com Docker, sem build local — as imagens vêm do Docker Hub e são atualizadas automaticamente pelos workflows de cada submodule.

> **Exceção temporária (04/10/2026):** as imagens com as mudanças de 03 e 04/10 (`tv30-redis` com login no Redis Commander, `tv30-tv3ws` com o 101 no reuso de `clientid` e o `kex` com `key`, `tv30-edgegateway` com o 404 `{"error":200}` no lugar do 500 vazio) ainda só existem em build local. Até serem publicadas, um clone novo puxa do Docker Hub as versões anteriores; para ter as novas, rode `docker compose build redis tv3ws edgegateway` antes do `docker compose up -d`.

> **Imagens da rodada de 05/10 andam juntas.** As decisões da reunião de 05/10 com o Joel mudaram três imagens ao mesmo tempo: `tv30-edgegateway` (a borda passa a responder a C.6.8, `/tv3/bind-context`, e a C.6.7.8/C.6.7.9, `/tv3/api-info`), `tv30-tv3ws` (sem validação de credencial, sem a C.6.8 e sem escrita de perfis) e `tv30-aop` (dono dos perfis, inclusive do `lastAccess`). Pelo código, misturar versões quebra funções: com a borda anterior e o tv3ws novo, a C.6.8 responde 404 `{"error":100}` (a borda antiga repassa a rota a um tv3ws que não a tem mais), e a `/tv3/api-info` também dá 100 (a borda antiga não a declara); com o tv3ws novo e o AoP anterior, ninguém atualiza o `lastAccess` na troca de usuário corrente, e o despejo de perfis passa a contar só a criação do perfil. Use as três da mesma rodada, publicadas ou construídas localmente (`docker compose build edgegateway tv3ws aop`).

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
# Windows: ver nota abaixo sobre MQTT_WS_PORT antes de subir
docker compose up -d
```

Abra http://localhost:8080 — interface do receptor (AoP).

> **Clone antigo (anterior ao renome `ccws` → `tv3ws`):** o `git pull` não propaga renome de submódulo para um clone que já existe. Rode `git submodule sync --recursive && git submodule update --init --recursive` e apague à mão a pasta `ccws/` que sobrou — ou clone de novo. Atenção também: o submódulo `bcast` usa URL SSH no `.gitmodules` (`git@github.com:multisens/BcastService.git`); sem chave SSH cadastrada no GitHub, o clone desse submódulo falha (a troca da URL ainda não foi decidida).

> **Primeira subida — o que acontece sozinho:** dois one-shots preparam o
> ambiente antes dos serviços. O `preflight` diagnostica DNS e portas
> ocupadas e imprime avisos legíveis no início do log (`docker logs
> tv30-preflight`) — se a subida falhar com `address already in use`, o
> dono da porta já está nomeado ali (triagem completa em
> [`docs/troubleshooting.md`](./docs/troubleshooting.md)). O
> `userfiles-seed` cria e popula `./user-files` a partir do template —
> não é preciso criar nada manualmente. O `tv3ws/.env` também é
> **opcional**: sem ele o tv3ws sobe em HTTP com um `JWT_SECRET` default
> de desenvolvimento (ver seção de HTTPS abaixo para habilitar o 44653).

> **Importante — não rode `docker compose` em `infra/`.** O `infra/` é submodule e seu compose é incluído automaticamente via `include:` no `docker-compose.yml` da raiz. **Toda a stack sobe de uma vez pela raiz.** Subir `compose` dentro de `infra/` não vê os serviços `aop`,  `tv3ws` e `bcast` (que ficam no compose raiz) e gera confusão de rede.

> **Importante — sem `.env` na raiz, os serviços principais ficam fora silenciosamente.** Os containers `aop`, `tv3ws`, `bcast`, `mosquitto` e `sysctl-init` têm `profiles: [linux]` ou `[mqtt]` no compose. Sem `COMPOSE_PROFILES=mqtt,linux` (que vem no `.env.example`), só sobe a infra (redis, edgegateway) e nada funciona end-to-end. Sempre comece com `cp .env.example .env`.

> **Importante — Windows + Hyper-V:** o serviço Hyper-V costuma ocupar as portas 9001/9002 no host. Como o Mosquitto WebSocket precisa expor a porta no host (o browser do AoP conecta direto no `localhost:MQTT_WS_PORT`), edite o `.env` **antes do `up -d`** e troque para `MQTT_WS_PORT=9003`. Sintoma quando esquece: o console do navegador mostra erro de conexão WebSocket no MQTT.

---

## Variáveis do `.env` (raiz)

| Variável | Default | Descrição |
|----------|---------|-----------|
| `COMPOSE_PROFILES` | `mqtt,linux` | Profiles ativos. Sem isto, `aop`/`tv3ws`/`bcast`/`mosquitto`/`sysctl-init` não sobem. O perfil `ssdp` deixou de existir em 09/10. |
| `COMPOSE_FILE` | comentada (só o `docker-compose.yml`) | `docker-compose.yml:docker-compose.ssdp.yml` liga a descoberta SSDP: a borda vai para a rede do host e anuncia (só Linux nativo, ver [seção própria](#descoberta-ssdp-só-linux-nativo)). |
| `DOCKERHUB_NS` | `labmultisens` | Namespace do Docker Hub de onde puxar as imagens. |
| `IMAGE_TAG` | `latest` | Tag das imagens. `latest` puxa o build mais recente da main de cada submodule. |
| `MQTT_WS_PORT` | `9001` | Porta WebSocket do Mosquitto exposta no host. **Em Windows com Hyper-V, trocar para `9003`.** |
| `BCAST_PORT` | `8081` | Porta do bcast exposta no host. Sobrescrever se 8081 estiver ocupada. |
| `EDGE_VARIANT` | `linux` | Para onde a borda encaminha: `linux` = tv3ws em container; `windows` = tv3ws rodando no host (desenvolvimento, ver [`docs/dev-local.md`](./docs/dev-local.md)); `host` = borda em rede do host, que o `docker-compose.ssdp.yml` define sozinho (não defina à mão). |
| `SERVER_URL` | `localhost` | Host que dispositivos externos usam para abrir os WebSockets de remote-device. Também é o host anunciado por SSDP quando `SSDP_ADVERTISE_HOST` está vazia. |
| `SSDP_ADVERTISE_HOST` | vazia | Host do `LOCATION` do anúncio SSDP e do `/manifest` (`Server-BaseURL`). Para a descoberta na rede, o IP da máquina na LAN. O `tv3ws` (`/manifest`) e a borda (anúncio, com o `docker-compose.ssdp.yml`) a leem do `.env` da raiz ou do `tv3ws/.env` (o da raiz prevalece); valor só exportado no shell não chega a eles. |
| `SSDP_INTERFACE` | vazia | Nome da interface de rede por onde a borda anuncia. Vazia = a que tem o IP anunciado, senão a da rota padrão. Interface inexistente derruba a borda (morre-inteiro). |
| `JWT_SECRET` / `JWT_ISSUER` | default de desenvolvimento / `GenericIssuer` | Segredo e emissor do accessToken. O **mesmo** valor vai para o tv3ws (que assina) e para a borda (que valida). |
| `AUTH_ENFORCE` | `warn` | Validação de credenciais na borda: `warn` só registra (log `[tv30-auth] WARN` + cabeçalho `X-TV30-Auth-Warn`); `enforce` rejeita com 404 + corpo C.3.2. |
| `REDIS_COMMANDER_USER` / `REDIS_COMMANDER_PASSWORD` | `admin` / `tv30-redis-admin` | Login da interface administrativa do Redis (ver [seção própria](#interface-administrativa-do-redis)). Não muda a conexão com o banco (6379), que segue sem senha. |

O `tv3ws/.env` é **opcional**: sem ele o tv3ws sobe normalmente, em HTTP, com um `JWT_SECRET` default de desenvolvimento. Para usar um `JWT_SECRET` próprio, defina-o no **`.env` da raiz** (a seção `environment:` do compose tem precedência sobre `env_file`, então `JWT_SECRET` dentro de `tv3ws/.env` não tem efeito) — assim a borda recebe o mesmo valor. Para habilitar HTTPS, ver a próxima seção — `HTTPS_CERT`/`HTTPS_KEY` estes sim vêm do `tv3ws/.env`.

---

## (Opcional) Habilitando HTTPS no tv3ws

Por padrão o tv3ws sobe **somente em HTTP** (porta 44652, interna à rede do Docker) — suficiente para desenvolvimento local. Para habilitar também o HTTPS (porta interna 44653, backend da superfície externa da borda), forneça cert + chave em **base64** nas variáveis `HTTPS_CERT` e `HTTPS_KEY` do arquivo `tv3ws/.env` (crie a partir de `tv3ws/.env.example`). A borda em si ainda escuta HTTP nas duas superfícies (TLS na borda: pendente). Para desenvolvimento, gere um certificado autoassinado:

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
| AoP (UI do receptor) | 8080 | http://localhost:8080 |
| tv3ws (TV 3.0 WebServices) | — (44652/44653 só na rede do Docker) | Não publicado no host: clientes entram pela borda (44642/44643). Com o `docker-compose.ssdp.yml`, a 44652/44653 é publicada só em `127.0.0.1`, para a borda. HTTPS interno somente com `HTTPS_CERT`/`HTTPS_KEY` no `tv3ws/.env` |
| tv3ws — WebSockets de remote-device | 45000–45199 | Portas dinâmicas devolvidas no registro (`ws://SERVER_URL:<porta>`) |
| edgegateway — anúncio SSDP (só com o `docker-compose.ssdp.yml`) | UDP 1900, na rede do host | Processo `ssdp-announcer` da borda. O `LOCATION` aponta para a própria borda (`http://<host>:44642/manifest`) |
| edgegateway — superfície externa | 44643 | rotas para clientes não-locais (tabela única M4) |
| edgegateway — superfície interna | 44642 | porta FIXA da norma (C.3.4); rotas de clientes locais |
| bcast (broadcaster) | `${BCAST_PORT:-8081}` | http://localhost:8081 — apps de serviço (webmedia, uff, etc.) |
| Mosquitto MQTT | 1883 | Broker TCP |
| Mosquitto WS | `${MQTT_WS_PORT:-9001}` | WebSocket — em Windows usar **9003** |
| Redis | 6379 | Estado de sessão + perfis (acesso TCP, ex.: `redis-cli`), sem senha |
| Redis Commander (embutido no redis) | dinâmica | `docker port redis 18081` mostra a porta; exige login (ver abaixo) |
| edgegateway — docs | dinâmica (8085 fixa com o `docker-compose.ssdp.yml`) | Swagger UI + 2 specs: `docker port edgegateway 8085`; com a borda em rede do host, `http://localhost:8085` |

---

## Interface administrativa do Redis

O container `redis` embute o Redis Commander (0.9.0, versão fixada no `infra/redis/Dockerfile`, porque o login depende dos nomes de variável dela), interface web para inspecionar o banco durante o desenvolvimento. Ela exige usuário e senha (decisão D-L1, tomada pelo Luís em 03/10).

- **URL:** a porta de host é dinâmica. `docker port redis 18081` mostra qual é (ex.: `0.0.0.0:32768`), e a interface fica em `http://localhost:<porta>/`.
- **Usuário padrão:** `admin`
- **Senha padrão:** `tv30-redis-admin`
- **Para trocar:** defina `REDIS_COMMANDER_USER` e `REDIS_COMMANDER_PASSWORD` no `.env` da raiz e recrie o container com `docker compose up -d redis`. Valor vazio volta ao padrão. Troque a senha padrão fora do laboratório.
- **Como o login funciona:** não é HTTP basic auth, então o navegador não abre a janela de autenticação. A página inicial carrega e mostra um formulário de login. Sem login, as rotas que leem o banco respondem 401.

> **A conexão com o banco (porta 6379) continua sem senha.** A senha protege só a interface administrativa. tv3ws, AoP, borda e `redis-cli` conectam como antes, sem `requirepass`.

O login é configurado pelo entrypoint da imagem `tv30-redis`. Uma imagem construída antes de 03/10, ou puxada do Docker Hub antes da publicação das imagens novas, sobe a interface **sem** login, mesmo com as variáveis definidas. Nesse caso, reconstrua com `docker compose build redis && docker compose up -d redis`.

---

## Descoberta SSDP (só Linux nativo)

O receptor se anuncia por SSDP (ABNT NBR 25608, C.3.4) para que outro aparelho da rede o encontre. Quem anuncia é a borda (L6, opção A, decidido pelo Luís em 09/10): o override `docker-compose.ssdp.yml` põe o `edgegateway` em rede do host e liga o anunciante dele, um processo em Go (`infra/edgegateway/ssdp/`). O `/manifest` continua no tv3ws, atrás da borda, e o resto da stack continua na `ginga_net`. A descoberta só é suportada em **Linux nativo com Docker Engine** (decisão do Joel, informada pelo Luís em 04/10). Nesse ambiente, um segundo aparelho encontrou o receptor em 09/10, primeiro com a opção B, anterior (o container `tv3ws-ssdp`), e depois com a opção A (um notebook no mesmo Wi-Fi; testes 40 a 43 de [`docs/ssdp-verificacao.md`](./docs/ssdp-verificacao.md)). No Windows com WSL2, o anúncio em rede do host não sai da máquina (medido em 03 e 04/10, com um anunciante descartável em modo host). O Docker Desktop, que também roda o Docker numa VM, fica fora do suporte.

No `.env` da raiz (o `COMPOSE_PROFILES` fica como está):

```env
COMPOSE_FILE=docker-compose.yml:docker-compose.ssdp.yml
SSDP_ADVERTISE_HOST=192.168.0.12   # IP desta máquina na rede local
```

Depois, `docker compose up -d` e `docker logs edgegateway`. Libere a UDP 1900 e a TCP 44642 no firewall do host.

- Com o override, a borda sai da `ginga_net`: ocupa a 44642, a 44643 e a 8085 direto no host e fala com o tv3ws por `127.0.0.1` (o tv3ws publica a 44652/44653 só nesse endereço).
- **Morre-inteiro (decisão do Luís em 09/10):** se o anúncio falhar (UDP 1900 ocupada, interface inexistente em `SSDP_INTERFACE`, rede caindo), a borda inteira cai, com todas as APIs, e o `restart` a traz de volta.
- Sem `SSDP_ADVERTISE_HOST`, o anúncio usa `SERVER_URL`, que por padrão é `localhost`, e outro aparelho não alcança o endereço. O anunciante avisa no log (`[ssdp] AVISO`).
- Sem o override, nada é anunciado. O cliente ainda chega ao receptor pelo IP: `http://<IP>:44642/manifest`. Para desligar, comente o `COMPOSE_FILE` e rode `docker compose up -d`.
- **Quem usava a opção B** (perfil `ssdp`, que deixou de existir): remova o container antigo, `docker rm -f tv3ws-ssdp` (ou `docker compose up -d --remove-orphans`). O `preflight` avisa se ele estiver de pé.
- Até a imagem nova da borda ser publicada pelo CI, a do Docker Hub não tem o anunciante nem a variante `host`; construa-a localmente (`docker compose build edgegateway`).
- Medições, arranjo e roteiro de teste com um segundo aparelho: [`docs/ssdp-verificacao.md`](./docs/ssdp-verificacao.md).

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

- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — arquitetura completa: fluxo entre serviços, tópicos MQTT, schema do Redis, decisões arquiteturais.
- [`docs/`](./docs/) — site Jekyll com guias detalhados (troubleshooting, padrões de apps de serviço, etc.).
- [`docs/dev-local.md`](./docs/dev-local.md) — desenvolvimento com um módulo rodando no host (`npm run dev`) e a infra em containers; teste automatizado em `scripts/test-dev-host.sh` e template de compose para componente novo em [`templates/componente/`](./templates/componente/README.md).

---

## Contribuições

Cada submodule da aplicação tem uma GitHub Action que, ao push na sua main, atualiza o hash do submodule aqui no TV30 e dispara o build/publish da imagem Docker correspondente no Docker Hub. Para o desenvolvedor, basta commitar na main do submodule — o TV30 e as imagens são atualizados sozinhos.
