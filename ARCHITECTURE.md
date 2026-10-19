# TV30 — TV 3.0 AoP Experimentation

> **Repositório:** https://github.com/multisens/TV30
> **Contexto:** Projeto de pesquisa CEFET — plataforma de experimentação do padrão brasileiro de TV digital (ISDB-Tb / TV 3.0)

Monorepo principal do ecossistema TV 3.0. Orquestra todos os componentes via **submodules Git** e **Docker Compose**.
Os serviços trocam sinalização e eventos via **MQTT** (broker Mosquitto), leem e escrevem estado no **Redis** e conversam por **HTTP direto** em dois trechos: a borda repassa ao tv3ws as APIs que não responde ela mesma, e o AoP faz proxy para o bcast. Clientes das APIs entram só pela **borda** (`edgegateway`). O anunciante SSDP roda no host, fora do Docker.

> **Norma × implementação:** a ABNT NBR 25608 define os papéis da plataforma TV 3.0 (receptor, TV 3.0 WebServices, broadcaster) e o modelo de consentimento/perfis. O transporte interno via **MQTT**, a **borda KrakenD** e o **Redis** são escolhas de implementação deste projeto — **não fazem parte da norma**.

---

## Submodules e responsabilidades

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | https://github.com/multisens/AOP | **Application-Oriented Platform** — interface do receptor TV 3.0. Renderiza UI, gerencia perfis de usuário (no Redis, dono das chaves de perfil desde a rodada de 05/10; desde o P4, grava pelas funções do Redis que conferem o esquema; até cinco perfis, e o sexto é recusado, sem despejo, desde a resposta do Joel de 15/10), exibe catálogo de apps e camadas de vídeo/gráficos. Node.js, porta **8080** |
| `tv3ws/` | https://github.com/multisens/TV3WS | **TV 3.0 WebServices** — implementação das APIs do Anexo C, menos a C.6.8 e a C.6.7.8/C.6.7.9, que a borda responde. Emissão do JWT, usuários (no Redis, lê os perfis, de que o AoP é o dono, e grava os atributos de emissora da C.6.14.5, com um aviso ao espectador na tela desde a G9), serviços e dispositivos remotos; não valida credencial. TypeScript, portas internas **44652** (HTTP, atrás da 44642) e **44653** (HTTPS com o certificado do receptor, atrás da 44643; A7), acesso só pela borda; fora do container, escuta só em 127.0.0.1 (e na `docker0`, no Linux) por padrão |
| `infra/` | https://github.com/multisens/Infra | **Infraestrutura Docker** — Redis, borda KrakenD (`edgegateway`, com o plugin Go `tv30-auth`), Mosquitto com plugin C de validação de esquema, dockerfiles e o anunciante SSDP em Go (`edgegateway/ssdp`), que roda no host |
| `bcast/` | https://github.com/multisens/BcastService | **Broadcaster** — simula transmissão de sinal TV 3.0. Vídeo por HLS, com segmentos preparados antes com FFmpeg (`bcast/scripts/ffmpeg-hls.sh`, fora do container; a imagem não traz FFmpeg) e playlist montada a cada pedido; sinalização via MQTT. Hospeda módulos de apps de serviço (webmedia, uff, etc.) seguindo padrão `src/modules/<nome>/` |

O `.gitmodules` tem só esses quatro. `eduplay` (motadv/eduplay), `sepe` (motadv/se-presentation-engine) e `utils` (multisens/TV30-Utils) são repositórios relacionados, não submódulos deste.

---

## Arquitetura

Estado atual do código:

```
Cliente (app de emissora, app local autônomo, dispositivo remoto)
        ↓ HTTP  :44642 (interna, Server-BaseURL, porta fixa da C.3.4)
        ↓ HTTPS :44643 (externa, Server-SecureBaseURL, TLS na borda; A7)
          as duas com as 26 rotas do routes.json (F-1)
  edgegateway (infra/)    ← borda única: KrakenD interno + externo + docs;
                            plugin Go tv30-auth valida credenciais (enforce
                            por padrão), negocia a versão de API e responde
                            ele mesmo a C.6.8 e a C.6.7.8/C.6.7.9
        ↓ ginga_net: HTTP :44652 (da interna), HTTPS :44653 (da externa)
  tv3ws (tv3ws/)          ← TV 3.0 WebServices (Anexo C); emite o
                            accessToken e não valida credencial; estado no Redis
        ↕ MQTT                    ↕ Redis
  Mosquitto + plugin C    ← valida o ESQUEMA das mensagens publicadas
        ↕ MQTT
  AoP (aop/)              ← UI do receptor; dono dos perfis no Redis; atende
                            o host próprio de cada app (<app>.apps.localhost,
                            P1.3) e grava em origins:associated a origem
                            dela e o serviço que a lançou (H1)
        ↓ HTTP (proxy: host próprio da app, <app>.apps.localhost:8080/
                graphicsAppProxy/...; /videoStreamProxy)
  bcast (bcast/)          ← sinalização (BAMT/ESG/BALD) por MQTT; apps de
                            serviço e mídia por HTTP

  No host, fora do Docker (./tv30 up; no Windows, tv30.ps1):
  ssdp-announcer (Go)     ← anúncio SSDP (C.3.4) em UDP 1900; LOCATION
                            aponta para o /manifest na 44642 da borda
```

**Descoberta SSDP.** Quem anuncia é um processo nativo do host, fora do Docker, em Linux, macOS e Windows (complemento do Joel de 15/10, B1 e B2): o binário Go de `infra/edgegateway/ssdp/`, que o `./tv30 up` (no Windows, `tv30.ps1 up`) compila para a máquina e sobe depois do `docker compose up -d`, e que o `./tv30 down` encerra antes do compose, para que saia o `ssdp:byebye`. Motivo: o multicast só sai de um container em Linux nativo; no macOS e no Windows, o container fica na VM do Docker. O anunciante só divulga onde está o `/manifest` e responde a buscas; não guarda estado nem valida credencial. O host do `LOCATION` é detectado (o IPv4 da interface da rota padrão) e acompanha a troca de rede; o `SSDP_ADVERTISE_HOST`, opcional, o fixa. O `/manifest` continua no tv3ws, atrás da borda, e sai com o `SSDP_ADVERTISE_HOST`, se definido, ou com o `Host` original da requisição, que a borda repassa em `X-TV30-Host` (`tv3ws/src/manifest.ts`), para casar com o `LOCATION`. Só erro de configuração encerra o anunciante; a falta de rede é tolerada com novas tentativas (C8), e a borda não depende dele. `SSDP_ENABLED=false` não o sobe, e `docker compose up -d` sozinho sobe o testbed sem descoberta. O `docker-compose.ssdp.yml` (desde 09/10, a borda em rede do host, só em Linux) e o anunciante Node do tv3ws saíram em 19/10. As medições M1 a M7 de [`docs/ssdp.md`](./docs/ssdp.md) não foram feitas. A C.3.4 não diz onde o anunciante roda: é decisão do projeto.

**Canais internos.** A comunicação interna não é só por MQTT, ao contrário do que esta seção dizia antes (o código desmente):

- sinalização e eventos passam pelo MQTT;
- o AoP e o tv3ws acessam o Redis diretamente, e a borda também: lê o que a decisão de credencial precisa e, desde a reunião de 05/10, escreve as chaves da C.6.8 (`bind-context:*`). Quem escreve cada família está em [`docs/modelo-redis.md`](./docs/modelo-redis.md);
- o AoP e o tv3ws compartilham o diretório de miniaturas (`thumbs/` do volume `./user-files` da raiz, montado nos dois): desde a G8 (decisão do Luís em 12/10), o AoP grava ali o arquivo do avatar de cada perfil que cria, e o tv3ws o lê para a C.6.14.6 (`USER_THUMBS`);
- a página da TV (camada gráfica do AoP, no navegador) fala MQTT por WebSocket pelo próprio AoP: conecta em `ws(s)://<host da página>/mqtt`, e o AoP repassa a conexão ao WebSocket do Mosquitto pela `ginga_net` (`aop/src/mqtt-ws.js`; C1, decisão do Luís em 11/10). Só no host do AoP; num host de app, o `/mqtt` responde 404. Até 11/10, a página conectava direto na 9001 do host;
- o AoP busca as aplicações e o vídeo do bcast por proxy HTTP, no `bcastEntryPackageUrl` anunciado (`aop/src/server.js`). Desde o P1.3 (decisão do Luís em 10/10), cada aplicação de emissora é servida num nome de host próprio, na porta do AoP (origem `http://<app>.apps.localhost:8080`; `aop/src/app-hosts.js`), para que o navegador mande o `Origin` dela, que o AoP grava em `origins:associated` enquanto ela roda, com o id do serviço corrente (H1, Joel 15/10; sem serviço corrente, não grava). O `<app>` sai do `appId` da BALD, fixo por app desde 11/10 (`urn-tv30-app-users-test`, por exemplo). Desde 11/10 (decisão do Luís), a URL que a camada gráfica abre mantém o prefixo do caminho antigo, `http://<app>.apps.localhost:8080/graphicsAppProxy<bcastEntryPointUrl>`, e o `/graphicsAppProxy/...` no host do próprio AoP redireciona (302) para o host da app; até 11/10, servia a app na origem do AoP, sem gravar origem. A camada gráfica entrega teclas e eventos do vídeo à aplicação por `postMessage` (ponte `bcast/public/js/aop-bridge.js`).

Os gateways não validam consentimento, e o plugin C do broker não faz controle de acesso a tópicos. A validação de credenciais é feita só na borda (decisão de 28/09), pelo plugin `tv30-auth`. Na reunião de 05/10, o Joel decidiu tirar do tv3ws a validação que ainda restava nele (D-0510-1) e pôr na borda a C.6.8 (D-0510-2) e a C.6.7.8/C.6.7.9 (D-0510-3); o plugin responde essas APIs sem repassá-las ao tv3ws. São decisões de desenho do testbed: a norma define as APIs, não qual processo as responde.

A borda também negocia a versão de API em cada rota (C.3.6.5; D2 e D4, Joel 15/10): o `routes.json` declara as `versions` de cada rota (ausente = 2.0); sem `Accept-Version` vale a 2.0, fora do formato X.Y dá 101, versão que a rota não serve dá 100. A versão decidida vai ao tv3ws em `X-TV30-API-Version`, e o `Host` original em `X-TV30-Host`; os dois apagam o que vier do cliente, e o tv3ws não lê o `Accept-Version`. A C.6.15.5 serve 2.0 e 100.0; as rotas `/tv3/remote-device/device/{handle}`, fora da Tabela C.2, só a 100.0 (a antiga 2.1; D1). As versões de 100.0 em diante são as das propostas do testbed.

O `AUTH_ENFORCE` tem padrão `enforce` (Joel, 15/10). Só as recusas de credencial (104, 107, 108) seguem o modo: em `warn`, opção explícita e transitória, elas só marcam `X-TV30-Auth-Warn`. O 100, o 101, o 106, o 300 e o 200 saem nos dois modos (`followsMode`, `infra/edgegateway/plugin/handler.go`).

---

## Tópicos MQTT principais

Publicadores e consumidores conferidos nas chamadas `publish`/`subscribe` do código de aop, tv3ws e bcast.

| Tópico | Publicado por | Consumido por | Significado |
|--------|--------------|---------------|-------------|
| `aop/currentUser` | AoP; tv3ws (C.6.14.4) | AoP, tv3ws | Usuário corrente |
| `aop/currentService` | AoP | tv3ws, AoP | Serviço DTV selecionado: o `globalServiceId` do BAM, que é o `serviceContextId` (A6) |
| `aop/display/layers/*` | AoP; tv3ws (pop-ups da autorização e do pareamento e, desde a G9, o aviso da C.6.14.5 em `popup/info`) | front do AoP | Camadas de renderização (vídeo, GUI, gráficos, popup) |
| `aop/:serviceId/currentApp` | — (nenhum publicador no código destes módulos; o contrato, `appId` retido e mensagem vazia no fim, está no esquema do broker desde a G4) | tv3ws (na troca de serviço, tira a assinatura do serviço anterior) | App ativo no serviço |
| `aop/services` | — (nenhum publicador no código destes módulos) | tv3ws | Lista de serviços. Sem ela, o tv3ws não tem o `serviceName`, e o 304 da A6 (serviço fora do catálogo) não é emitido |
| `tlm/lls/#` | bcast | AoP | Metadados de serviço (BAMT) |
| `tlm/sls/+/#` | bcast | AoP | Metadados por serviço (ESG, BALD) |
| `aop/devices/<classe>` | tv3ws | — | Dispositivos remotos registrados |
| `video/event` | bcast (eventos do `events.json` da playlist HLS) | front do AoP | Evento do vídeo, entregue à app da camada gráfica como `stream_event` |

---

## Execução

```bash
./tv30 up        # no Windows: .\tv30.ps1 up
./tv30 down
```

O `./tv30 up` roda o `docker compose up -d` e sobe o anunciante SSDP no host; o `./tv30 down` o encerra antes do `docker compose down`. O `docker compose up -d` sozinho sobe o testbed, sem a descoberta. Na primeira subida, o serviço `tls-init` gera em `.tv30/tls` (fora do git) o certificado autoassinado do receptor (A7).

Defaults vêm do `.env` (raiz). Portas (C1, decisão do Luís em 11/10, revista por ele em 12/10 para a 44643): fixas no host a 44642, a 44643, a do AoP (8080), a 1883, a 6379 (só em `127.0.0.1`, A1) e a faixa 45000–45199; as demais saem numa porta livre que o Docker escolhe (`docker compose port <serviço> <porta>`), e `BCAST_PUBLISH` e `MQTT_WS_PUBLISH` as fixam; `EDGE_EXT_PUBLISH` muda a publicação da 44643 (`README.md`). A página da TV não usa a 9001 do host: com o AoP em container, nenhuma porta precisa mudar no Windows. Para quem roda o AoP fora do Docker no Windows, há uma dica (opção, decisão do Luís em 12/10): `MQTT_WS_PUBLISH=9003:9001` no `.env` da raiz e `MQTT_WS_PORT=9003` no `aop/.env`. Para desenvolver com um módulo no host (`npm run dev`), ver [`docs/dev-local.md`](./docs/dev-local.md). Descoberta SSDP: `README.md`, seção *Descoberta SSDP*.

### Containers e portas

Seis containers contínuos, mais os de execução única (`preflight`, `userfiles-seed`, `tls-init` e, no perfil `linux`, `sysctl-init`). O anunciante SSDP não é container. `EDGE_VARIANT` escolhe o backend da borda: `linux` (o tv3ws em container) ou `windows` (o tv3ws no host, por `host.docker.internal`; também o dev-host em Linux).

| Container | Porta(s) no host | Descrição |
|-----------|----------|-----------|
| `redis` | 6379 só em `127.0.0.1` (sem senha; A1); commander em porta dinâmica, com login | Estado de sessão, usuários e credenciais + redis-commander embutido (debug). Morre-inteiro desde 11/10 (C2): a morte do commander derruba o container |
| `mqtt-broker` (serviço `mosquitto`) | 1883; WebSocket (9001 do container) em porta dinâmica (`MQTT_WS_PUBLISH`) | MQTT broker + plugin C de validação de esquema |
| `edgegateway` | 44642 (HTTP) e 44643 (HTTPS, certificado de `.tv30/tls`), fixas (a 44643 por padrão, `EDGE_EXT_PUBLISH`, desde 12/10); docs (8085) em porta dinâmica | Borda única: KrakenD interno e externo + Swagger UI; plugin `tv30-auth`, que valida as credenciais, negocia a versão e responde a C.6.8 e a C.6.7.8/C.6.7.9; morre-inteiro |
| `tv3ws` | 45000–45199 (WebSockets dos dispositivos remotos: `wss://` com o certificado do receptor; `TV3WS_WS_TLS=false` volta a `ws://`) | TV 3.0 WebServices. 44652/44653 só na `ginga_net`, sem publicação no host |
| `aop` | `${AOP_PUBLIC_PORT:-8080}` | Interface do receptor; na mesma porta, os hosts próprios das apps de emissora (`<app>.<APPS_DOMAIN>`, padrão `apps.localhost`; P1.3) e o MQTT por WebSocket da página da TV (`/mqtt`, C1) |
| `bcast` | 8081 do container em porta dinâmica (`BCAST_PUBLISH`) | Broadcaster + módulos de apps de serviço |

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
| KrakenD + plugin Go | Borda única (`edgegateway`) com validação de credenciais e negociação de versão (`tv30-auth`), que também responde a C.6.8 e a C.6.7.8/C.6.7.9; TLS da 44643 terminado no KrakenD |
| Go (nativo no host) | Anunciante SSDP (`infra/edgegateway/ssdp`), compilado pelo `./tv30` com o Go do host ou num container `golang` |
| OpenSSL | Certificado autoassinado do receptor (`infra/edgegateway/tls-init.sh`, serviço `tls-init`) |
| Mosquitto plugin C | Validação de esquema das mensagens publicadas |
| FFmpeg | Preparo dos segmentos HLS que o broadcaster serve (`bcast/scripts/ffmpeg-hls.sh`, fora do container) |

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
| Estado de usuários em Redis | Consistência entre serviços; `userData.json` é só a carga inicial, no banco vazio. Desde a rodada da reunião de 05/10 (D-0510-5, aplicando o P5), a plataforma (AoP) é a única dona dos perfis, e o tv3ws só os lê. Os atributos de emissora de cada perfil (`user:{id}:broadcaster-attrs:{scid}`, C.6.14.5) têm dois escritores, como o Joel decidiu em 15/10 (E4): o tv3ws os grava, e o AoP os remove na função `tv30_perfil_remove`, junto com o perfil. Hoje essa função não tem chamador: o despejo do sexto perfil saiu, e a remoção pelo telespectador não existe (`docs/modelo-redis.md`) |
| Esquema nas escritas do Redis por funções do próprio Redis, com auditoria (P4; decidido pelo Luís em 10/10) | Toda escrita do código nas famílias de chave do testbed passa por uma função da biblioteca `tv30` (`infra/redis/funcoes.lua`, esquema em `infra/redis/esquema.json`), que confere o esquema e grava de forma atômica, inclusive as invariantes entre chaves. Um teste estático impede o código de gravar direto, e a função de auditoria aponta o que está fora do esquema. A conexão segue sem senha e com escrita (A1): o Redis aplica o ACL de quem chama dentro da função, então não dá para liberar só a escrita pela função, e a escrita manual continua possível. Desde 11/10 (F-3, decisão do Luís), o esquema exige o id do perfil em UUID, como a Tabela 7, sem compatibilidade com os ids antigos; desde 12/10 (decisão do Luís, esquema na versão 3), o UUID é estrito: versão de 1 a 8, variante da RFC 9562 e o UUID nulo e o máximo recusados; desde a noite de 12/10 (G8, decisão do Luís, versão 4), o `avatar` é o nome de um arquivo do diretório de miniaturas, como a Tabela 7 pede (*file path*), e o SVG em linha de antes é recusado. Redis e funções são decisão do projeto; a norma não fala de armazenamento |
| Avatar como nome de arquivo do diretório de miniaturas (G8; decidido pelo Luís em 12/10, à noite) | A Tabela 7 pede *file path* no `avatar`. O AoP grava `<id do perfil>.svg` em `user-files/thumbs` ao criar o perfil e o apaga se a gravação do perfil falhar; o tv3ws entrega o arquivo pela C.6.14.6, com o `Content-Type` da extensão e a restrição da Tabela C.73; as telas do AoP leem o arquivo e o embutem como `<img src="data:...">`, sem rota que sirva o diretório (ela entregaria o avatar sem a restrição da Tabela C.73, e um SVG aberto como documento na origem do AoP rodaria o script dele); o users-test do bcast pede o avatar pela C.6.14.6, na borda. Restringir o caminho a um nome dentro de um diretório é decisão do projeto |
| Apps de serviço como módulos do bcast | Único container `bcast` serve tudo (sem duplicação MQTT/CORS) |
| Borda única com duas superfícies | Interna 44642 (HTTP, `Server-BaseURL`, fixa pela C.3.4) e externa 44643 (HTTPS, `Server-SecureBaseURL`; A7); credenciais validadas só na borda (decisão de 28/09; o tv3ws fica "anônimo" desde a D-0510-1), que também responde a C.6.8 (D-0510-2) e a C.6.7.8/C.6.7.9 (D-0510-3). Desde 19/10 (F-1, F-2 e E7, Joel 15/10, revendo a P1.9 do Luís de 10/10), as duas têm as 26 rotas, e a regra de cada uma sai das `classes` e da seção da API (`SURFACE_RULES`, `generate.js`): na externa, as rotas exclusivas do cliente local (`POST` e `DELETE /tv3/bind-context`, a C.6.15.5 e as rotas por *handle* da 100.0) e a C.6.1.2 respondem 106 a qualquer requisição (C.4.1.8); na interna, o access token `non-local` fora da C.6.1.2 e da C.6.1.3 recebe 106 (C.4.1.6). A C.6.7.8 e a C.6.7.9 listam as 20 APIs nas duas. Ordem da decisão no plugin: rota (100), superfície (106), classe (106), não local por HTTP (106), access token (107), serviço selecionado (300), bind-token (104/108). O associado reconhecido pelo `Origin` dispensa o bind-token só no próprio contexto de serviço (H1; C.4.1.1, "referencing their own service context") e recebe 106 nas rotas que não o admitem (C.6.1.2, C.6.1.3, C.6.8.3), também com access token válido (A8); o tv3ws também não emite credencial ao associado. Sem serviço selecionado, as APIs cuja tabela lista o 300 (C.6.4.7, C.6.14.1 a C.6.14.6) o respondem antes do bind-token (H2); a C.6.16.3 dá 108. O `{serviceContextId}` do caminho é o `globalServiceId` do BAM, sem constante (A6). A norma (C.3.4) só define as duas URLs base; duas superfícies numa borda e as regras por superfície são decisão do projeto |
| Certificado autoassinado do receptor, com o TLS da 44643 terminado na borda (A7, Joel 15/10) | O serviço `tls-init` gera o certificado na primeira subida, em `.tv30/tls`, sem ação do usuário (`infra/edgegateway/tls-init.sh`). O mesmo certificado serve a 44643 da borda, o HTTPS da 44653 do tv3ws, o `serverCert` do pareamento e os `wss://` dos dispositivos remotos (`tv3ws/src/tls.ts`). A C.4.1.1 admite o HTTPS com certificado autoassinado pela plataforma. Terminar o TLS na borda decorre da D-0510-1: ela precisa ler os cabeçalhos. Onde terminar o TLS é decisão do projeto |
| Versões de API registradas no `routes.json` e negociadas na borda (D1 a D4, Joel 15/10) | Um registro só: o que a borda aceita em cada rota, o `API-Version` e a versão da C.6.7.8/C.6.7.9 saem das `versions` da rota. Até 15/10, o tv3ws e a borda negociavam cada um nas suas rotas, com o conjunto 2.0/2.1 escrito à mão nos dois. A C.3.6 define a negociação; quem a faz e a numeração 100.0 das propostas do testbed são decisão do projeto. A escolha do serviço pela versão (D2) não foi feita: toda rota tem um backend só |
| `AUTH_ENFORCE=enforce` por padrão (Joel, 15/10) | O `warn` fica como opção explícita e transitória (por exemplo, um cliente que ainda não obtém o token). Só 104, 107 e 108 seguem o modo; 100, 101, 106, 300 e 200 saem nos dois. Até 15/10 o padrão era `warn`, e só o 100 saía nele. Modo é decisão do projeto |
| Um nome de host por app de emissora (P1.3; decidido pelo Luís em 10/10) | O associado é reconhecido pelo `Origin` em `origins:associated` (L1, risco aceito em 03/10). Servidas pelo proxy na origem do AoP, as apps chegavam à borda com o `Origin` do AoP e não eram reconhecidas. Com um host por app, na porta do AoP, o `Origin` passa a ser o da app, e o AoP grava essa origem, com o serviço corrente, ao lançá-la. Limite: `*.localhost` resolve para a máquina de quem abre a página, então a tela do AoP aberta de outra máquina não carrega as apps; `APPS_DOMAIN` aceita um domínio resolvível na rede. A C.4.1.7 deixa o mecanismo de diferenciação à implementação; host por app e proxy são decisão do projeto |
| Anunciante SSDP nativo no host, fora do Docker, nos três sistemas (complemento do Joel de 15/10, B1 e B2) | Dentro do Docker, o multicast só sai em Linux nativo; no macOS e no Windows, o container fica na VM do Docker. O anunciante só divulga o `/manifest` e responde a buscas, sem estado nem credencial, então ficar fora da borda não abre caminho em volta dela. O `./tv30` (no Windows, `tv30.ps1`) o compila e o sobe depois do compose, e o encerra antes, com `ssdp:byebye`. O host do `LOCATION` é detectado e acompanha a troca de rede; `SSDP_ADVERTISE_HOST` é sobreposição opcional. Só erro de configuração o encerra (C8). Substituiu a opção A (decidida pelo Luís em 09/10: a borda anunciava em rede do host, só em Linux nativo, e um erro de configuração do anúncio derrubava a borda inteira). A C.3.4 não diz onde o anunciante roda; é decisão do projeto |
| Portas fixas só as necessárias; o resto numa porta que o Docker escolhe (C1, opção b; decidido pelo Luís em 11/10, revisto por ele em 12/10 para a 44643) | Pedido do Joel na primeira reunião: só a 44642 fixa, o resto em porta livre. A opção b manteve fixas também a do AoP (endereço que a pessoa digita e origem das apps de emissora), a 1883, a 6379 e a faixa 45000–45199. Em 12/10, o Luís fixou a 44643 também (`EDGE_EXT_PUBLISH`, padrão `44643:44643`): o `/manifest` a anuncia no `Server-SecureBaseURL`, e a porta que o Docker escolheria não sairia ali. Para a 9001 do Mosquitto sair do host sem quebrar a página da TV, o AoP passou a atender o MQTT por WebSocket na própria porta (`/mqtt`). A norma só fixa a 44642 (C.3.4); o resto é decisão do projeto |
| Morre-inteiro sem exceção, inclusive no container do Redis (C2; decidido pelo Luís em 11/10) | A morte do redis-commander derruba o container do Redis, e o `restart` o traz de volta, como nos outros containers com mais de um processo. Até 11/10 o commander era a exceção (decisão V8/V9 do plano de consolidação), por ser ferramenta de inspeção |

---

## Conhecidos / atenção

- `host.docker.internal:host-gateway` (não IP fixo)
- Apps de emissora em `<app>.apps.localhost`: com a tela do AoP aberta de outra máquina, elas não carregam (`*.localhost` resolve para a máquina de quem abre). Use `APPS_DOMAIN` com um domínio resolvível na rede (README, seção *Apps de emissora*)
- Certificado autoassinado na 44643 (A7): `curl` e navegador o recusam sem `-k` ou sem confiar em `.tv30/tls/cert.pem` (README, seção *HTTPS*); o `subjectAltName` cobre só `localhost` e `127.0.0.1`. O cliente não local o recebe no `serverCert` do pareamento. Um navegador não abre `wss://` com certificado em que não confia: para app de navegador, `TV3WS_WS_TLS=false`
- tv3ws fora do container (dev-host): escuta só em `127.0.0.1` (e na `docker0`, no Linux) por padrão (`tv3ws/src/listen-hosts.ts`; `TV3WS_LISTEN_HOST` muda). Alcançado direto, ele não confere credencial (D-0510-1)
- Anunciante SSDP: nada o reinicia. Se ele sai, a descoberta para até o próximo `./tv30 up`; o log fica em `.tv30/ssdp.log` (`./tv30 logs`)
- Portas escolhidas pelo Docker (C1, 11/10): a 8081 do bcast, a 9001 do Mosquitto, a 8085 da documentação e a 18081 do commander podem mudar a cada vez que o container é recriado; `docker compose port <serviço> <porta>` mostra a atual. A 44643 é fixa por padrão desde 12/10; com `EDGE_EXT_PUBLISH=44643` (só o número) ela também passa a ser escolhida pelo Docker, e o `/manifest` e o OpenAPI da externa continuam dizendo 44643 (`KNOWN-ISSUES.md`). Até 11/10, em Windows+WSL2 com a 9001 ocupada (Hyper-V), definia-se `MQTT_WS_PORT=9003` para a página da TV; com o AoP em container não é mais preciso, e para o AoP fora do Docker no Windows a dica de 12/10 está na seção *Execução*

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
