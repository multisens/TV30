# TV30 — TV 3.0 AoP Experimentation

> **Repositório:** https://github.com/multisens/TV30
> **Contexto:** Projeto de pesquisa CEFET — plataforma de experimentação do padrão brasileiro de TV digital (ISDB-Tb / TV 3.0)

Monorepo principal do ecossistema TV 3.0. Orquestra todos os componentes via **submodules Git** e **Docker Compose**.
Os serviços trocam sinalização e eventos via **MQTT** (broker Mosquitto), leem e escrevem estado no **Redis** e, num caso, conversam por **HTTP direto**: o AoP faz proxy para o bcast. Clientes das APIs entram só pela **borda** (`edgegateway`).

> **Norma × implementação:** a ABNT NBR 25608 define os papéis da plataforma TV 3.0 (receptor, TV 3.0 WebServices, broadcaster) e o modelo de consentimento/perfis. O transporte interno via **MQTT**, a **borda KrakenD** e o **Redis** são escolhas de implementação deste projeto — **não fazem parte da norma**.

---

## Submodules e responsabilidades

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | https://github.com/multisens/AOP | **Application-Oriented Platform** — interface do receptor TV 3.0. Renderiza UI, gerencia perfis de usuário (direto no Redis; dono das chaves de perfil desde a rodada de 05/10), exibe catálogo de apps e camadas de vídeo/gráficos. Node.js, porta **8080** |
| `tv3ws/` | https://github.com/multisens/TV3WS | **TV 3.0 WebServices** — implementação das APIs do Anexo C, menos a C.6.8 e a C.6.7.8/C.6.7.9, que a borda responde. Emissão do JWT, usuários (Redis, só leitura dos perfis), serviços e dispositivos remotos; não valida credencial. TypeScript, portas internas **44652** (HTTP) e **44653** (HTTPS opcional), acesso pela borda |
| `infra/` | https://github.com/multisens/Infra | **Infraestrutura Docker** — Redis, borda KrakenD (`edgegateway`, com o plugin Go `tv30-auth`), Mosquitto com plugin C de validação de esquema, dockerfiles |
| `bcast/` | https://github.com/multisens/BcastService | **Broadcaster** — simula transmissão de sinal TV 3.0. Streaming via FFmpeg, sinalização via MQTT. Hospeda módulos de apps de serviço (webmedia, uff, etc.) seguindo padrão `src/modules/<nome>/` |

O `.gitmodules` tem só esses quatro. `eduplay` (motadv/eduplay), `sepe` (motadv/se-presentation-engine) e `utils` (multisens/TV30-Utils) são repositórios relacionados, não submódulos deste.

---

## Arquitetura

Estado atual do código:

```
Cliente (app de emissora, app local autônomo, dispositivo remoto)
        ↓ HTTP :44642 (interna, porta fixa da C.3.4) | :44643 (externa)
  edgegateway (infra/)    ← borda única: KrakenD interno + externo + docs;
                            plugin Go tv30-auth valida credenciais (warn)
                            e responde ele mesmo a C.6.8 e a C.6.7.8/C.6.7.9
        ↓ HTTP na ginga_net
  tv3ws (tv3ws/)          ← TV 3.0 WebServices (Anexo C); emite o
                            accessToken e não valida credencial; estado no Redis
        ↕ MQTT                    ↕ Redis
  Mosquitto + plugin C    ← valida o ESQUEMA das mensagens publicadas
        ↕ MQTT
  AoP (aop/)              ← UI do receptor; dono dos perfis no Redis
        ↓ HTTP (proxy /graphicsAppProxy e /videoStreamProxy)
  bcast (bcast/)          ← sinalização (BAMT/ESG/BALD) por MQTT; apps de
                            serviço e mídia por HTTP

  Com o override docker-compose.ssdp.yml (opcional, só Linux nativo):
  edgegateway na rede do  ← + processo ssdp-announcer: anúncio SSDP (C.3.4)
  host                      em UDP 1900; LOCATION aponta para a própria borda
                            (/manifest); tv3ws por 127.0.0.1:44652/44653
```

**Descoberta SSDP.** Quem anuncia é a borda (L6, opção A, decidido pelo Luís em 09/10, no lugar da opção B, o container `tv3ws-ssdp`, decidida em 04/10). O anunciante é um processo a mais no container `edgegateway`: o binário Go `ssdp-announcer` (`infra/edgegateway/ssdp/`), que o `entrypoint.sh` só sobe com `SSDP_ENABLED=true`. Quem liga é o override `docker-compose.ssdp.yml`, que põe a borda em `network_mode: host` (variante `host`, com o tv3ws em `127.0.0.1:44652/44653`). Pelo morre-inteiro, decidido pelo Luís em 09/10 e revisto por ele em 10/10, o erro de configuração do anúncio derruba a borda inteira; a falta de rede não, e o anunciante espera e tenta de novo. O `/manifest` continua no tv3ws, atrás da borda, e o tv3ws da bridge não anuncia (`SSDP_ENABLED: "false"` no compose). A descoberta só é suportada em Linux nativo com Docker Engine (decisão do Joel, informada pelo Luís em 04/10; decisão do projeto, não da norma). Nesse ambiente, a descoberta por outro aparelho foi validada em 09/10, primeiro com a opção B e depois com a opção A (um notebook no mesmo Wi-Fi, testes 40 a 43). Ver [`docs/ssdp-verificacao.md`](./docs/ssdp-verificacao.md).

**Canais internos.** A comunicação interna não é só por MQTT, ao contrário do que esta seção dizia antes (o código desmente):

- sinalização e eventos passam pelo MQTT;
- o AoP e o tv3ws acessam o Redis diretamente, e a borda também: lê o que a decisão de credencial precisa e, desde a reunião de 05/10, escreve as chaves da C.6.8 (`bind-context:*`). Quem escreve cada família está em [`docs/modelo-redis.md`](./docs/modelo-redis.md);
- o AoP busca as aplicações e o vídeo do bcast por proxy HTTP, no `bcastEntryPackageUrl` anunciado (`aop/src/server.js`).

Os gateways não validam consentimento, e o plugin C do broker não faz controle de acesso a tópicos. A validação de credenciais é feita só na borda (decisão de 28/09), pelo plugin `tv30-auth`. Na reunião de 05/10, o Joel decidiu tirar do tv3ws a validação que ainda restava nele (D-0510-1) e pôr na borda a C.6.8 (D-0510-2) e a C.6.7.8/C.6.7.9 (D-0510-3); o plugin responde essas APIs sem repassá-las ao tv3ws. São decisões de desenho do testbed: a norma define as APIs, não qual processo as responde.

---

## Tópicos MQTT principais

Publicadores e consumidores conferidos nas chamadas `publish`/`subscribe` do código de aop, tv3ws e bcast.

| Tópico | Publicado por | Consumido por | Significado |
|--------|--------------|---------------|-------------|
| `aop/currentUser` | AoP; tv3ws (C.6.14.4) | AoP, tv3ws | Usuário corrente |
| `aop/currentService` | AoP | tv3ws, AoP | Serviço DTV selecionado |
| `aop/display/layers/*` | AoP; tv3ws (popups de autorização) | front do AoP | Camadas de renderização (vídeo, GUI, gráficos, popup) |
| `aop/:serviceId/currentApp` | — (nenhum publicador no código destes módulos) | tv3ws | App ativo no serviço |
| `aop/services` | — (nenhum publicador no código destes módulos) | tv3ws | Lista de serviços |
| `tlm/lls/#` | bcast | AoP | Metadados de serviço (BAMT) |
| `tlm/sls/+/#` | bcast | AoP | Metadados por serviço (ESG, BALD) |
| `aop/devices/<classe>` | tv3ws | — | Dispositivos remotos registrados |

---

## Execução

```bash
docker compose up -d
```

Defaults vêm do `.env` (raiz). Em Windows + WSL2 com 9001 ocupada no host, definir `MQTT_WS_PORT=9003` no `.env`. Para desenvolver com um módulo no host (`npm run dev`), ver [`docs/dev-local.md`](./docs/dev-local.md). Para a descoberta SSDP em Linux nativo, defina `COMPOSE_FILE=docker-compose.yml:docker-compose.ssdp.yml` e `SSDP_ADVERTISE_HOST` com o IP da máquina na LAN no `.env` (`README.md`, seção *Descoberta SSDP*).

### Containers e portas

Seis containers contínuos. Com o override `docker-compose.ssdp.yml`, a borda roda em rede do host e tem um processo a mais, o anunciante SSDP.

| Container | Porta(s) no host | Descrição |
|-----------|----------|-----------|
| `redis` | 6379 (sem senha); commander em porta dinâmica, com login | Estado de sessão, usuários e credenciais + redis-commander embutido (debug) |
| `mqtt-broker` (serviço `mosquitto`) | 1883, `${MQTT_WS_PORT:-9001}` | MQTT broker + plugin C de validação de esquema |
| `edgegateway` | 44642, 44643; docs (8085) em porta dinâmica. Com o override `docker-compose.ssdp.yml`: rede do host, com 44642, 44643 e 8085 direto no host e UDP 1900 | Borda única: KrakenD interno e externo + Swagger UI; plugin `tv30-auth`, que valida as credenciais e responde a C.6.8 e a C.6.7.8/C.6.7.9; morre-inteiro. Com o override (só Linux nativo), também o anunciante SSDP (`ssdp-announcer`), e o erro de configuração dele derruba a borda inteira (a falta de rede não; decisão do Luís em 10/10) |
| `tv3ws` | 45000–45199 (WebSockets) | TV 3.0 WebServices. 44652/44653 só na `ginga_net`; com o override, publicadas também em `127.0.0.1`, para a borda |
| `aop` | 8080 | Interface do receptor |
| `bcast` | `${BCAST_PORT:-8081}` | Broadcaster + módulos de apps de serviço |

### Apps de serviço (módulos do bcast)

Seguindo o padrão `webmedia` em `bcast/src/modules/<nome>/`: `index.ts` (implementa `ServiceInterface` com router próprio + EJS), `app.ejs`, `companion/`. Reaproveita o cliente MQTT do bcast — não cria novo container.

---

## Stack

| Tecnologia | Uso |
|------------|-----|
| Docker + Compose | Orquestração full-container |
| Redis (ioredis) | Estado de sessão, usuários e credenciais (tv3ws, AoP; a borda usa um cliente RESP próprio, em Go) |
| Node.js 23+ | AoP, tv3ws, bcast |
| TypeScript | tv3ws, bcast |
| MQTT (Mosquitto) | Sinalização e eventos entre serviços |
| KrakenD + plugin Go | Borda única (`edgegateway`) com validação de credenciais (`tv30-auth`), que também responde a C.6.8 e a C.6.7.8/C.6.7.9 |
| Mosquitto plugin C | Validação de esquema das mensagens publicadas |
| FFmpeg | Streaming de vídeo no broadcaster |

---

## Gerenciamento de submodules

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
git submodule update --init --recursive
git submodule update --remote                # atualiza todos
git submodule update --remote aop            # só aop
git submodule status
```

Clone anterior ao renome `ccws` → `tv3ws`: `git submodule sync --recursive && git submodule update --init --recursive` e apagar a pasta `ccws/` que sobrou (ou clonar de novo) — ver [`docs/instalacao.md`](./docs/instalacao.md).

**CI:** cada submodule (aop, bcast, tv3ws, infra) tem `.github/workflows/bump-tv30-pointer.yml` que dispara em push em main e atualiza automaticamente o ponteiro do submodule no TV30. Secret `TV30_REPO_TOKEN` (PAT com `Contents: write` no TV30) configurado em cada repo.

---

## Decisões arquiteturais

| Decisão | Motivo |
|---------|--------|
| Modo único = Linux + Docker full-container | Simplificação — um único caminho de deploy (desenvolvimento: infra em containers + módulo no host) |
| Monorepo com submodules | Cada componente tem ciclo de vida independente |
| MQTT para sinalização e eventos | Desacoplamento — não é o único canal interno (ver *Canais internos*) |
| Estado de usuários em Redis | Consistência entre serviços; `userData.json` é só a carga inicial, no banco vazio. Desde a rodada da reunião de 05/10 (D-0510-5, aplicando o P5), a plataforma (AoP) é a única dona dos perfis, e o tv3ws só os lê |
| Apps de serviço como módulos do bcast | Único container `bcast` serve tudo (sem duplicação MQTT/CORS) |
| Borda única com duas superfícies | Interna 44642 (fixa C.3.4) e externa 44643; credenciais validadas na borda (decisão de 28/09). Na reunião de 05/10, o Joel decidiu que o tv3ws fica "anônimo", sem validar credencial (D-0510-1), e que a borda responde a C.6.8 (D-0510-2) e a C.6.7.8/C.6.7.9 (D-0510-3); as três foram feitas. Sem TLS na borda, o 106 por protocolo ao não local (C.4.1.6) ficou sem quem o aplique (lacuna L3) |
| A borda anuncia o SSDP, em rede do host (L6, opção A; decidido pelo Luís em 09/10) | O multicast do anúncio não saiu da bridge do Docker para a rede (medido no WSL2 em 02/10), então quem anuncia tem de estar na rede do host. Com o override `docker-compose.ssdp.yml`, a borda vai para a rede do host e alcança o tv3ws por `127.0.0.1`; um erro de configuração do SSDP derruba a borda inteira, e a falta de rede não (morre-inteiro decidido pelo Luís em 09/10, revisto por ele em 10/10). Substituiu a opção B (decidida em 04/10, informado pelo Luís): um container próprio para o anúncio, `tv3ws-ssdp`, com a borda e o tv3ws na `ginga_net`, em que a falha do SSDP não derrubava as APIs. A C.3.4 não diz onde o anunciante roda; é decisão do projeto |

---

## Conhecidos / atenção

- `host.docker.internal:host-gateway` (não IP fixo)
- Em Windows+WSL2 com 9001 ocupada no host: definir `MQTT_WS_PORT=9003` no `.env` da raiz (ex: serviço Hyper-V já usa 9001/9002)

## Troubleshooting WSL2 + Docker

**Sintoma:** após `docker compose up -d`, containers Up no WSL mas `localhost:8080` no Windows host dá timeout/connection reset.

**Causa típica:** `~/.wslconfig` com `networkingMode=mirrored`. Mirrored mode + Docker tem issues conhecidos — Docker faz NAT via iptables que mirrored não espelha bem pro host Windows.

**Solução:** o default do WSL2 (`networkingMode=NAT` + `localhostForwarding=true`) funciona out-of-the-box com Docker. Se você editou o `.wslconfig`, garanta:

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
```

Depois: `wsl --shutdown` no PowerShell pra aplicar, então re-iniciar a distribuição.

**Verificação:** `Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 8080 }` no PowerShell deve mostrar a porta 8080 listening em 127.0.0.1.
