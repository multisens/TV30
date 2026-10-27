---
title: Arquitetura
parent: Como funciona
nav_order: 1
---

# Arquitetura

## Visão geral

O diagrama descreve o estado atual do código. Cada seta é um canal que o código abre: HTTP, MQTT ou acesso direto ao Redis.

```
 Clientes das APIs: app de emissora (no navegador da TV), app local autônomo, cliente não local
       │ HTTP  :44642  interna (porta fixa da C.3.4): as 27 rotas; o não local só usa authorize e token
       │ HTTPS :44643  externa (TLS na borda): as 27 rotas; exclusivas do local e authorize dão 106
       ▼
 ┌─────────────┐  HTTP(S), ginga_net   ┌─────────┐   WebSocket 45000–45199,
 │ edgegateway │ ────────────────────▶ │  tv3ws  │ ◀── direto, sem a borda ── aparelho remoto
 └─────────────┘                       └─────────┘
       │ Redis                     Redis │     │ MQTT
       ▼                                 ▼     ▼
 ┌─────────────────────────────────────────┐ ┌─────────────────────────────────┐
 │ redis                                   │ │ mqtt-broker (Mosquitto)         │
 └─────────────────────────────────────────┘ └─────────────────────────────────┘
       ▲ Redis                                    ▲     ▲                  ▲
       │                                     MQTT │     │ WebSocket 9001   │ MQTT
 ┌─────────┐ ─────────────────────────────────────┘     │                  │
 │   aop   │ ── repasse do /mqtt ───────────────────────┘                  │
 └─────────┘ ── HTTP direto (proxy das apps e do vídeo) ───────────▶ ┌───────────┐
       ▲                                                             │   bcast   │
       │ HTTP :8080                                                  └───────────┘
 navegador da TV: telas do AoP, /mqtt e o host próprio de cada app de emissora

 no host, fora do Docker: ssdp-announcer (./tv30 up), UDP 1900, LOCATION http://<IP>:44642/manifest
```

- **edgegateway** (`infra/edgegateway/`): a borda única, com os dois KrakenD (interno e externo) e a documentação (8085). A externa termina o TLS com o certificado do receptor (`.tv30/tls`, gerado pelo `tls-init`). O plugin Go `tv30-auth` valida a credencial (access token, bind-token e classe do cliente), negocia a versão de cada rota e responde ele mesmo a C.6.8 e a C.6.7.8/C.6.7.9. Em `enforce` (o padrão), a recusa responde o erro da C.3.2; em `warn`, só as recusas de credencial (104, 107, 108) viram o aviso `X-TV30-Auth-Warn`. Ele não confere o consentimento do espectador (Privacy Manager, 8.8). A interna repassa a `http://tv3ws:44652`, e a externa, a `https://tv3ws:44653` (`infra/edgegateway/routes.json`).
- **tv3ws** (`tv3ws/`): os TV 3.0 WebServices (Anexo C). Emite o accessToken, serve o `/manifest` e não valida a credencial das requisições.
- **mqtt-broker** (`infra/mqtt-broker/`): Mosquitto com um plugin C que valida o esquema das mensagens publicadas nos tópicos que têm esquema declarado. Não faz controle de acesso a tópicos nem consulta o Redis (`plugin/src/mosquitto_plugin.c`).
- **aop** (`aop/`): a UI do receptor, dona dos perfis no Redis e da lista dos serviços anunciados na LLS (`services:announced` e o tópico `aop/services`, pela unidade `aop-transport-layer-metadata-lls`, que recebe a BAMT). Na porta dele (8080, `AOP_PUBLIC_PORT`) ficam as telas, o `/mqtt` da página da TV e o host próprio de cada app de emissora (`<app>.apps.localhost`), cuja origem o AoP grava em `origins:associated`.
- **bcast** (`bcast/`): simula a emissora. Publica a sinalização (BAMT, ESG e BALD) por MQTT e serve as apps de serviço e a mídia por HTTP.
- **ssdp-announcer** (`infra/edgegateway/ssdp/`): o anunciante SSDP (C.3.4), em Go, que roda no host, fora do Docker, nos três sistemas. O `./tv30 up` (no Windows, `.\tv30.ps1 up`) o compila e o sobe depois do `docker compose up -d`, com pid e log em `.tv30/`. Ele anuncia em UDP 1900 o `LOCATION` `http://<IP da máquina>:44642/manifest`, atrás da borda, e não guarda estado nem valida credencial.

**Canais internos.** Pelo código, a comunicação interna não é toda por mensageria:

- **Sinalização e eventos** passam pelo MQTT.
- **Armazenamento:** o AoP e o tv3ws leem e escrevem no Redis diretamente. A borda lê dele o que a decisão de credencial precisa e escreve as chaves da C.6.8 (`bind-context:*`). Quem escreve cada família de chave está em [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis). O Redis não guarda todo o estado: o AoP mantém em memória o serviço corrente e a app em execução (`DATA`, `aop/src/core.js`) e os BAM recebidos (`aop/src/modules/transport-layer-metadata-lls/`; no Redis, só os ids dos serviços, em `services:announced`), e o broker guarda as mensagens retidas da sinalização e do estado (`retain`, com `persistence true` no `mosquitto.conf`).
- **Arquivos do volume `./user-files`:** o AoP grava o arquivo do avatar de cada perfil que cria em `thumbs/` (`<USER_DATA_PATH>/thumbs`), e o tv3ws o lê do mesmo diretório (`USER_THUMBS`) para a C.6.14.6. O diretório é o volume `./user-files` da raiz, montado nos dois containers, e o `userfiles-seed` copia para ele os arquivos do modelo que faltam.
- **MQTT da página da TV pelo AoP:** a camada gráfica, no navegador, fala MQTT por WebSocket com a própria origem: conecta em `ws(s)://<host da página>/mqtt`, e o AoP repassa a conexão ao WebSocket do Mosquitto pela `ginga_net` (`aop/src/mqtt-ws.js`). O repasse só existe no host do AoP: num host de app, ou noutro caminho, o pedido de WebSocket responde 404; com o broker fora do alcance, 502.
- **HTTP direto:** o AoP faz proxy HTTP para o bcast (`aop/src/server.js`): as aplicações vêm do `bcastEntryPackageUrl` que o bcast anuncia na BALD de cada serviço, e o vídeo, do primeiro `initialMediaURLs` do BAM, que chega pela BAMT (`/videoStreamProxy`; `aop/src/modules/bootstrap-application/service.js`). Cada aplicação de emissora é servida num nome de host próprio, na porta do AoP (origem `http://<app>.apps.localhost:8080`; `aop/src/app-hosts.js`), para que o navegador mande o `Origin` dela, que o AoP grava em `origins:associated` enquanto ela roda. O `<app>` sai do `appId` da BALD (`urn-tv30-app-users-test`, por exemplo). A URL que a camada gráfica abre leva o prefixo `/graphicsAppProxy`, `http://<app>.apps.localhost:8080/graphicsAppProxy<bcastEntryPointUrl>`, e o `/graphicsAppProxy/...` no host do próprio AoP redireciona (302) para o host da app. A camada gráfica entrega teclas e eventos do vídeo à aplicação por `postMessage` (ponte `bcast/public/js/aop-bridge.js`).

Clientes das APIs entram **só pela borda**: as portas de API do tv3ws (44652/44653) não são publicadas no host, e, fora do container (dev-host), o tv3ws escuta só na própria máquina (`tv3ws/src/listen-hosts.ts`). A exceção são os WebSockets de remote-device: o tv3ws publica a faixa 45000–45199, e o cliente os abre direto, sem passar pela borda. O ponto de entrada do dispositivo remoto sai em `wss://`, com o certificado do receptor (`TV3WS_WS_TLS=false` o abre em `ws://`); o local, sempre em `ws://`.

**Descoberta SSDP.** O anunciante roda no host, fora do Docker, nos três sistemas: dentro do Docker, o multicast só sai em Linux nativo. O host do `LOCATION` é o IPv4 da interface da rota padrão, detectado, e acompanha a troca de rede; `SSDP_ADVERTISE_HOST` o fixa. O `/manifest` fica no tv3ws, atrás da borda, e sai com o host pelo qual o cliente o alcançou, o `Host` original que a borda repassa em `X-TV30-Host` (com `SSDP_ADVERTISE_HOST`, vale ele; `tv3ws/src/manifest.ts`). Só o erro de configuração encerra o anunciante; sem rede, ele espera e tenta de novo, e as APIs não dependem dele. O `./tv30 down` o encerra antes do `docker compose down`, com `ssdp:byebye`. A C.3.4 não diz onde o anunciante roda: é decisão do projeto. Detalhes em [Descoberta SSDP]({{ site.baseurl }}/ssdp).

> **Norma × implementação:** o MQTT, a borda KrakenD e o Redis são decisões de arquitetura deste testbed, **não** exigências da ABNT NBR 25608. A norma especifica os TV 3.0 WebServices (Anexo C), o modelo de consentimento e os perfis de usuário, mas não o transporte interno nem a infraestrutura de back-end.

---

## Submódulos

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | [multisens/AOP](https://github.com/multisens/AOP) | Interface do receptor TV 3.0: UI, gestor de perfis, catálogo de apps e camadas de vídeo/gráficos. Node.js, porta **8080** |
| `tv3ws/` | [multisens/TV3WS](https://github.com/multisens/TV3WS) | Implementação dos TV 3.0 WebServices (Anexo C), menos a C.6.8 e a C.6.7.8/C.6.7.9, que a borda responde: emissão do JWT, usuários (lê os perfis do Redis; dos dados de usuário, grava só os atributos da emissora, C.6.14.5, com um aviso na tela, e o usuário corrente da sessão, C.6.14.4), serviços e dispositivos. TypeScript, portas internas **44652/44653**, com acesso pela borda |
| `infra/` | [multisens/Infra](https://github.com/multisens/Infra) | Redis, a borda KrakenD (`edgegateway`), Mosquitto + plugin C e os dockerfiles |
| `bcast/` | [multisens/BcastService](https://github.com/multisens/BcastService) | Simula a emissora: sinalização por MQTT, hospedagem das apps de serviço e a mídia por HTTP (o Express serve os segmentos HLS e simula a playlist ao vivo, `bcast/src/modules/live_stream/`). Os segmentos não estão no repositório: são preparados fora da stack, com FFmpeg (`bcast/scripts/ffmpeg-hls.sh`, `ffmpeg-dash.sh`) |

O `.gitmodules` contém só esses quatro. `eduplay`, `sepe` (se-presentation-engine) e `TV30-Utils` são repositórios relacionados, mas não são submódulos deste repositório.

---

## Containers e portas

Seis containers contínuos (`redis` a `bcast`) e quatro tarefas únicas de subida. O `tv3ws`, o `aop`, o `bcast` e o `tv30-sysctl-init` estão no perfil `linux`, e o broker no perfil `mqtt`: sem `COMPOSE_PROFILES=mqtt,linux` (`.env.example`), sobem só o `redis`, a borda, o `tv30-preflight`, o `tv30-userfiles-seed` e o `tv30-tls-init`. O anunciante SSDP não é container: roda no host (`./tv30 up`).

**Portas.** Fixas no host: a 44642 (norma, C.3.4), a 44643, a do AoP (8080, `AOP_PUBLIC_PORT`), a 1883, a 6379 (só em `127.0.0.1`) e a faixa 45000–45199; fora do Docker, a UDP 1900 do anunciante SSDP. A 44643 é fixa por padrão (`EDGE_EXT_PUBLISH`, padrão `44643:44643`, `infra/docker-compose.yml`), porque o `/manifest` a anuncia no `Server-SecureBaseURL` e não sabe a porta que o Docker escolheria. Numa porta livre escolhida pelo Docker: a 8081 do bcast, a 9001 do Mosquitto, a 8085 e a 18081. `docker compose port <serviço> <porta>` mostra a porta de host de cada uma. `EDGE_EXT_PUBLISH`, `BCAST_PUBLISH` e `MQTT_WS_PUBLISH` são o valor que vai no `ports` do serviço: `host:container` fixa a porta de host, e só o número deixa o Docker escolher ([Instalação]({{ site.baseurl }}/instalacao#portas)). Na 44643, só o número (`EDGE_EXT_PUBLISH=44643`) dá uma porta livre que o `/manifest` não anuncia, e outra porta fixa (`X:44643`) pede `EDGE_HTTPS_PORT=X` no `.env` da raiz, senão o `/manifest` anuncia a errada. A norma só fixa a 44642; o resto é decisão do projeto.

| Container | Porta(s) no host | Descrição |
|-----------|----------|-----------|
| `redis` | 6379, só em `127.0.0.1` (sem senha); commander em porta dinâmica (`docker port redis 18081`), com login | Redis, com carga inicial e o redis-commander embutido para debug. Morre-inteiro: se o `redis-server` ou o commander cair, o container cai, e o `restart` o traz de volta |
| `mqtt-broker` (serviço `mosquitto`) | 1883; WebSocket (9001 do container) em porta dinâmica (`docker compose port mosquitto 9001`; `MQTT_WS_PUBLISH` fixa) | Mosquitto + plugin C de validação de esquema, sem controle de acesso a tópicos. A página da TV não usa a porta do WebSocket: fala MQTT pelo `/mqtt` do AoP |
| `edgegateway` | 44642 (HTTP) e 44643 (HTTPS; fixa por padrão, `EDGE_EXT_PUBLISH`); docs em porta dinâmica (`docker port edgegateway 8085`) | Borda única. Contém os dois processos KrakenD (superfícies interna e externa; a externa termina o TLS com o certificado de `.tv30/tls`), com o plugin `tv30-auth`, que valida as credenciais, negocia a versão e responde a C.6.8 e a C.6.7.8/C.6.7.9, e a documentação Swagger. A externa repassa ao HTTPS do tv3ws (`https://tv3ws:44653`), com o mesmo certificado. Morre-inteiro: se um processo cai, o container cai, e o `restart` o traz de volta |
| `tv3ws` | 45000–45199 (WebSockets de remote-device: o do dispositivo remoto em `wss://` com o certificado do receptor, o local em `ws://`, e não no `wss://` da Tabela C.80; ver [Não implementado]({{ site.baseurl }}/nao-implementado)) | TV 3.0 WebServices. As portas 44652 (HTTP) e 44653 (HTTPS, com o certificado de `.tv30/tls`) ficam só na `ginga_net` |
| `aop` | `${AOP_PUBLIC_PORT:-8080}` | Interface do receptor; na mesma porta, os hosts próprios das apps de emissora (`<app>.<APPS_DOMAIN>`, padrão `apps.localhost`) e o MQTT por WebSocket da página da TV (`/mqtt`) |
| `bcast` | 8081 do container em porta dinâmica (`docker compose port bcast 8081`; `BCAST_PUBLISH` fixa) | Broadcaster + módulos de apps de serviço. O AoP o alcança pela `ginga_net` (`bcast:8081`) |
| `tv30-preflight`, `tv30-userfiles-seed`, `tv30-tls-init`, `tv30-sysctl-init` | — | Tarefas únicas de subida: diagnóstico de DNS e portas, carga de `./user-files`, certificado do receptor em `.tv30/tls` (gerado só na primeira subida) e ajuste de sysctl (Linux). O preflight só avisa, menos num caso: com a 44642 ocupada por processo nativo, ele sai com erro (`scripts/preflight.sh`), e a borda, que depende dele com `service_completed_successfully`, não sobe. A borda e o tv3ws também esperam o `tls-init` terminar |

---

### Ordem de subida

| Serviço | Espera |
|---|---|
| `edgegateway` | `tv30-preflight` e `tv30-tls-init` terminarem com 0; `redis` saudável |
| `tv3ws` | `redis` saudável; `mosquitto` iniciado; `tv30-userfiles-seed` e `tv30-tls-init` terminarem com 0 |
| `aop` | `mosquitto`, `redis` e `tv30-userfiles-seed` iniciados (o AoP tenta de novo a leitura dos perfis no Redis, `loadUserData`) |
| `bcast` | `mosquitto` iniciado |

O `redis` fica saudável depois de carregar a biblioteca de funções nesta partida e aplicar a carga inicial ([Modelo de dados Redis]({{ site.baseurl }}/modelo-redis)). Nenhum serviço espera o `tv30-sysctl-init`. O compose da raiz tem nome fixo de projeto (`name: tv30`) e inclui o `infra/docker-compose.yml`, que inclui o `infra/redis/docker-compose.yml`; o compose da `infra/` sozinho não é projeto válido, porque a borda depende do `preflight`, que só existe na raiz.

---

## Apps de serviço (padrão webmedia)

As apps são **módulos** dentro do container `bcast`, não containers separados. Cada módulo tem um `index.ts` que implementa a `ServiceInterface` (`bcast/src/types.ts`: `init`, `sendSLS`, `dispose`, `bam` e, opcional, `router`) e as views EJS dele:

```
bcast/src/modules/<nome>/
├── index.ts        # ServiceInterface: BAM, sinalização (sendSLS) e o router opcional
└── *.ejs           # views da aplicação
```

| Módulo | Views |
|---|---|
| `users-test`, `uff` | `app.ejs` |
| `webmedia` | `app.ejs` e a pasta `companion/`, com as views do aparelho companheiro (`companion.ejs`, `replay_menu.ejs`, `replay_player.ejs`, `vote_menu.ejs`) |
| `eduplay` | `quiz-presenter.ejs` e `quiz-player.ejs` |
| `live_stream` | nenhuma: serve os segmentos HLS e simula a playlist ao vivo |

Os módulos recebem o cliente MQTT do bcast (`sendSLS(client)` e `dispose(client)`) e não criam conexão nem container novos. Os arquivos estáticos das aplicações (`js/`, `media/`, `hls/`) ficam em `bcast/public/`, montada no container.

---

## Decisões arquiteturais

As decisões do projeto e o motivo de cada uma estão em [Decisões]({{ site.baseurl }}/decisoes).

---

## CI/CD

Cada submódulo (aop, bcast, tv3ws, infra) tem um workflow só, `.github/workflows/bump-tv30-pointer.yml` ("Build, push e bump submodule <nome> em TV30"), que dispara a cada push na `main` e faz duas coisas, nesta ordem:

1. **Constrói e publica a imagem no Docker Hub**, com as tags `<hash do commit>` e `latest`, no namespace do segredo `DOCKERHUB_USERNAME` (o `.env.example` usa `labmultisens`). O infra publica três imagens: `tv30-mosquitto`, `tv30-edgegateway` e `tv30-redis`. O aop, o tv3ws e o bcast fazem checkout do repositório Infra para usar o Dockerfile de lá.
2. **Atualiza o ponteiro do submódulo no repositório TV30**, com o PAT `TV30_REPO_TOKEN`. Esse passo depende do primeiro (`needs`): se o build ou o push falham, o ponteiro não muda.

A `latest` acompanha a `main` de cada submódulo; um clone com commits ainda não publicados roda o código dele com `docker compose up -d --build`. As imagens saem só para `amd64` (o workflow não define `platforms`): num Mac com Apple Silicon, construa-as localmente com `docker compose build`; o Dockerfile da borda escolhe o Go pela arquitetura (`TARGETARCH`, `infra/edgegateway/Dockerfile`).
