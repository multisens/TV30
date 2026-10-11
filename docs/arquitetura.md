---
title: Arquitetura
parent: Como funciona
nav_order: 1
---

# Arquitetura

## Visão geral

O diagrama descreve o estado atual do código, não o desenho publicado anteriormente.

```
Cliente (app de emissora, app local autônomo, dispositivo remoto)
        ↓ HTTP :44642 (interna, porta fixa da C.3.4, todas as rotas)
        | :44643 (externa, só as rotas que admitem o não local; P1.9)
  edgegateway (infra/)    ← borda única: KrakenD interno + externo + docs;
                            plugin Go tv30-auth valida credenciais (warn)
                            e responde ele mesmo a C.6.8 e a C.6.7.8/C.6.7.9
        ↓ HTTP na ginga_net
  tv3ws (tv3ws/)          ← TV 3.0 WebServices (Anexo C); emite o
                            accessToken e não valida a credencial das
                            requisições; estado no Redis
        ↕ MQTT                    ↕ Redis
  Mosquitto + plugin C    ← valida o ESQUEMA das mensagens publicadas
        ↕ MQTT
  AoP (aop/)              ← UI do receptor; dono dos perfis no Redis; atende
                            o host próprio de cada app (<app>.apps.localhost,
                            P1.3) e grava a origem dela em origins:associated
        ↓ HTTP (proxy: host próprio da app, <app>.apps.localhost:8080/
                graphicsAppProxy/...; /videoStreamProxy)
  bcast (bcast/)          ← sinalização (BAMT/ESG/BALD) por MQTT; apps de
                            serviço e mídia por HTTP

  Com o override docker-compose.ssdp.yml (opcional, só Linux nativo):
  edgegateway na rede do  ← + processo ssdp-announcer: anúncio SSDP (C.3.4)
  host                      em UDP 1900; LOCATION aponta para a própria borda
                            (/manifest); tv3ws por 127.0.0.1:44652/44653
```

**Canais internos.** Pelo código, a comunicação interna não é toda por mensageria:

- **Sinalização e eventos** passam pelo MQTT.
- **Armazenamento:** o AoP e o tv3ws leem e escrevem no Redis diretamente. A borda lê dele o que a decisão de credencial precisa e, desde a reunião de 05/10, escreve as chaves da C.6.8 (`bind-context:*`). Quem escreve cada família de chave está em [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis).
- **MQTT da página da TV pelo AoP:** a camada gráfica, no navegador, fala MQTT por WebSocket com a própria origem: conecta em `ws(s)://<host da página>/mqtt`, e o AoP repassa a conexão ao WebSocket do Mosquitto pela `ginga_net` (`aop/src/mqtt-ws.js`; C1, decisão do Luís em 11/10). O repasse só existe no host do AoP: num host de app, ou noutro caminho, o pedido de WebSocket responde 404; com o broker fora do alcance, 502. Até 11/10, a página conectava direto na 9001 do host.
- **HTTP direto:** o AoP faz proxy HTTP para o bcast (`aop/src/server.js`): as aplicações vêm do `bcastEntryPackageUrl` que o bcast anuncia na BALD de cada serviço, e o vídeo, do primeiro `initialMediaURLs` do BAM, que chega pela BAMT (`/videoStreamProxy`; `aop/src/modules/bootstrap-application/service.js`). Desde o P1.3 (decisão do Luís em 10/10), cada aplicação de emissora é servida num nome de host próprio, na porta do AoP (origem `http://<app>.apps.localhost:8080`; `aop/src/app-hosts.js`), para que o navegador mande o `Origin` dela, que o AoP grava em `origins:associated` enquanto ela roda. O `<app>` sai do `appId` da BALD, fixo por app desde 11/10 (`urn-tv30-app-users-test`, por exemplo). Desde 11/10 (decisão do Luís), a URL que a camada gráfica abre mantém o prefixo do caminho antigo, `http://<app>.apps.localhost:8080/graphicsAppProxy<bcastEntryPointUrl>`, e o `/graphicsAppProxy/...` no host do próprio AoP redireciona (302) para o host da app; até 11/10, servia a app na origem do AoP, sem gravar origem. A camada gráfica entrega teclas e eventos do vídeo à aplicação por `postMessage` (ponte `bcast/public/js/aop-bridge.js`).

A versão anterior desta página dizia que "todos os serviços se comunicam via MQTT". Isso não corresponde ao código. Clientes das APIs entram **só pela borda**: as portas de API do tv3ws (44652/44653) não são publicadas no host (com o override do SSDP, abaixo, são publicadas só em `127.0.0.1`, para a borda). A exceção são os WebSockets de remote-device: o tv3ws publica a faixa 45000–45199, e o aparelho remoto os abre direto, sem passar pela borda.

**Descoberta SSDP.** Quem anuncia é a borda (L6, opção A, decidido pelo Luís em 09/10, no lugar da opção B, o container `tv3ws-ssdp`, decidida em 04/10). O anunciante é um processo a mais no container `edgegateway`: o binário Go `ssdp-announcer` (`infra/edgegateway/ssdp/`), que o `entrypoint.sh` só sobe com `SSDP_ENABLED=true`. Quem liga é o override opcional `docker-compose.ssdp.yml`, que põe a borda em `network_mode: host`, na variante `host` (o tv3ws é alcançado por `127.0.0.1:44652/44653`). Pelo morre-inteiro, decidido pelo Luís em 09/10 e revisto por ele em 10/10, o erro de configuração do anúncio derruba a borda inteira; a falta de rede não, e o anunciante espera e tenta de novo. Desde 11/10 (B2, decisão do Luís), o host do `LOCATION` é o `SSDP_ADVERTISE_HOST`, obrigatório com o anúncio ligado (sem ele, o `preflight` para a subida); o `SERVER_URL` deixou de ser fonte do host do anúncio. O `/manifest` continua no tv3ws, atrás da borda, e o tv3ws da bridge não anuncia (`SSDP_ENABLED: "false"` no compose). A descoberta só é suportada em Linux nativo com Docker Engine (decisão do Joel, informada pelo Luís em 04/10; decisão do projeto, não da norma). Nesse ambiente, a descoberta por outro aparelho foi validada em 09/10, primeiro com a opção B e depois com a opção A (um notebook no mesmo Wi-Fi, testes 40 a 43). Detalhes em [Descoberta SSDP]({{ site.baseurl }}/ssdp), e as medições, nas [Medições da descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao).

> **Norma × implementação:** o MQTT, a borda KrakenD e o Redis são decisões de arquitetura deste testbed, **não** exigências da ABNT NBR 25608. A norma especifica os TV 3.0 WebServices (Anexo C), o modelo de consentimento e os perfis de usuário, mas não o transporte interno nem a infraestrutura de back-end.

---

## Submódulos

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | [multisens/AOP](https://github.com/multisens/AOP) | Interface do receptor TV 3.0: UI, gestor de perfis, catálogo de apps e camadas de vídeo/gráficos. Node.js, porta **8080** |
| `tv3ws/` | [multisens/TV3WS](https://github.com/multisens/TV3WS) | Implementação dos TV 3.0 WebServices (Anexo C), menos a C.6.8 e a C.6.7.8/C.6.7.9, que a borda responde: emissão do JWT, usuários (lê os perfis do Redis; dos dados de usuário, grava só os atributos da emissora, C.6.14.5, e o usuário corrente da sessão, C.6.14.4), serviços e dispositivos. TypeScript, portas internas **44652/44653**, com acesso pela borda |
| `infra/` | [multisens/Infra](https://github.com/multisens/Infra) | Redis, a borda KrakenD (`edgegateway`), Mosquitto + plugin C e os dockerfiles |
| `bcast/` | [multisens/BcastService](https://github.com/multisens/BcastService) | Simula a emissora: sinalização por MQTT, hospedagem das apps de serviço e a mídia por HTTP (o Express serve os segmentos HLS e simula a playlist ao vivo, `bcast/src/modules/live_stream/`). Os segmentos não estão no repositório: são preparados fora da stack, com FFmpeg (`bcast/scripts/ffmpeg-hls.sh`, `ffmpeg-dash.sh`) |

O `.gitmodules` contém só esses quatro. `eduplay`, `sepe` (se-presentation-engine) e `TV30-Utils` são repositórios relacionados, mas não são submódulos deste repositório.

---

## Containers e portas

Seis containers contínuos (`redis` a `bcast`) e três tarefas únicas de subida. O `tv3ws`, o `aop`, o `bcast` e o `tv30-sysctl-init` estão no perfil `linux`, e o broker no perfil `mqtt`: sem `COMPOSE_PROFILES=mqtt,linux` (`.env.example`), sobem só o `redis`, a borda, o `tv30-preflight` e o `tv30-userfiles-seed`. Com o override `docker-compose.ssdp.yml`, a borda roda em rede do host e tem um processo a mais, o anunciante SSDP.

**Portas (C1, decisão do Luís em 11/10, opção b).** Fixas no host: a 44642 (norma, C.3.4), a do AoP (8080, `AOP_PUBLIC_PORT`), a 1883, a 6379 e a faixa 45000–45199, e a 44643 no modo SSDP, que vai no anúncio. Numa porta livre escolhida pelo Docker: a 44643 na bridge, a 8081 do bcast, a 9001 do Mosquitto, a 8085 e a 18081. `docker compose port <serviço> <porta>` mostra a porta de host de cada uma, e `EDGE_EXT_PUBLISH`, `BCAST_PUBLISH` e `MQTT_WS_PUBLISH` (valor `host:container`) fixam as três primeiras ([Instalação]({{ site.baseurl }}/instalacao#portas)). A norma só fixa a 44642; o resto é decisão do projeto. Até 11/10, a 44643, a 8081 e a 9001 também eram fixas.

| Container | Porta(s) no host | Descrição |
|-----------|----------|-----------|
| `redis` | 6379 (sem senha); commander em porta dinâmica (`docker port redis 18081`), com login | Redis, com carga inicial e o redis-commander embutido para debug. Morre-inteiro desde 11/10 (C2, decisão do Luís): se o `redis-server` ou o commander cair, o container cai, e o `restart` o traz de volta; até 11/10, a morte do commander não derrubava o banco |
| `mqtt-broker` (serviço `mosquitto`) | 1883; WebSocket (9001 do container) em porta dinâmica (`docker compose port mosquitto 9001`) | Mosquitto + plugin C de validação de esquema. A página da TV não usa a porta do WebSocket: fala MQTT pelo `/mqtt` do AoP |
| `edgegateway` | 44642; externa (44643 do container) e docs em porta dinâmica (`docker compose port edgegateway 44643`, `docker port edgegateway 8085`). Com o override `docker-compose.ssdp.yml`: rede do host, com 44642, 44643 e 8085 (fixa) direto no host e UDP 1900 | Borda única. Contém os dois processos KrakenD (superfícies interna e externa), com o plugin `tv30-auth`, que valida as credenciais e responde a C.6.8 e a C.6.7.8/C.6.7.9, e a documentação Swagger; com o override (só Linux nativo), também o anunciante SSDP (`ssdp-announcer`). Morre-inteiro: se um processo cai, o container cai, inclusive o anunciante (decisão do Luís, 09/10), e o `restart` o traz de volta. Desde 10/10 (decisão do Luís), o anunciante só sai por erro de configuração; sem rede, ele espera e tenta de novo |
| `tv3ws` | 45000–45199 (WebSockets de remote-device) | TV 3.0 WebServices. As portas 44652/44653 ficam só na `ginga_net`; com o override, são publicadas também em `127.0.0.1`, para a borda |
| `aop` | `${AOP_PUBLIC_PORT:-8080}` | Interface do receptor; na mesma porta, os hosts próprios das apps de emissora (`<app>.<APPS_DOMAIN>`, padrão `apps.localhost`; P1.3) e o MQTT por WebSocket da página da TV (`/mqtt`, C1) |
| `bcast` | 8081 do container em porta dinâmica (`docker compose port bcast 8081`) | Broadcaster + módulos de apps de serviço. O AoP o alcança pela `ginga_net` (`bcast:8081`) |
| `tv30-preflight`, `tv30-userfiles-seed`, `tv30-sysctl-init` | — | Tarefas únicas de subida: diagnóstico de DNS e portas, carga de `./user-files` e ajuste de sysctl (Linux). O preflight só avisa, menos em dois casos: com a 44642 ocupada por processo nativo, e, com o override do SSDP, sem `SSDP_ADVERTISE_HOST` (B2, desde 11/10). Nos dois, ele sai com erro (`scripts/preflight.sh`), e a borda, que depende dele com `service_completed_successfully`, não sobe |

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

| Decisão | Motivo |
|---------|--------|
| Docker | Um único caminho de deploy. Para desenvolvimento, a infra roda em containers e o módulo no host ([dev-local]({{ site.baseurl }}/dev-local)) |
| Monorepo com submódulos | Cada componente tem repositório e CI próprios. O build da imagem de aop, tv3ws e bcast depende do repositório Infra, de onde o CI tira o Dockerfile (`infra/dockerfiles/`) |
| MQTT para sinalização e eventos entre serviços | Desacoplamento. Não é o único canal interno (ver *Canais internos*) |
| Estado de usuários em Redis | `userData.json` serve só de carga inicial: o `infra/user-files-template/userData.json`, embutido na imagem do Redis no build, aplicado quando a chave `seed:done` não existe (um volume novo). Os perfis têm um dono, a plataforma (AoP): o P5 ("um dono por família de chave") foi aplicado na rodada da reunião de 05/10 com o Joel (D-0510-5), e o tv3ws deixou de re-sincronizar a partir do arquivo |
| Apps de serviço como módulos do bcast | Um único container serve todas, sem duplicar MQTT e CORS |
| Borda única com duas superfícies (fase 2) | A interna fica na 44642, fixa pela C.3.4, e a externa na 44643. Credenciais validadas na borda (decisão de 28/09, plugin `tv30-auth`). Na reunião de 05/10, o Joel decidiu que o tv3ws fica "anônimo", sem validar credencial (D-0510-1), e que a borda responde a C.6.8 (D-0510-2) e a C.6.7.8/C.6.7.9 (D-0510-3). As três foram feitas. Sem TLS na borda, o 106 por protocolo ao não local (C.4.1.6) ficou sem quem o aplique (lacuna L3). Desde a P1.9 (decisão do Luís em 10/10), a externa só expõe as rotas que admitem o não local, e a interna expõe todas; a superfície de cada rota sai das `classes` no `generate.js`. Saem da externa `POST` e `DELETE /tv3/bind-context`, que dão 100 ali; se dariam 106 com TLS (C.4.1.8) está com o Joel. A norma (C.3.4) só define as duas URLs base, e os conjuntos de rota por superfície são decisão do projeto |
| Um nome de host por app de emissora (P1.3; decidido pelo Luís em 10/10) | O associado é reconhecido pelo `Origin` em `origins:associated` (L1, risco aceito em 03/10). Servidas pelo proxy na origem do AoP, as apps chegavam à borda com o `Origin` do AoP e não eram reconhecidas. Com um host por app, na porta do AoP, o `Origin` passa a ser o da app, e o AoP grava essa origem ao lançá-la. Limite: `*.localhost` resolve para a máquina de quem abre a página, então a tela do AoP aberta de outra máquina não carrega as apps; `APPS_DOMAIN` aceita um domínio resolvível na rede. A C.4.1.7 deixa o mecanismo de diferenciação à implementação; host por app e proxy são decisão do projeto |
| A borda anuncia o SSDP, em rede do host (L6, opção A; decidido pelo Luís em 09/10) | O multicast do anúncio não saiu da bridge do Docker para a rede (medido no WSL2 em 02/10), então quem anuncia tem de estar na rede do host. Com o override `docker-compose.ssdp.yml`, a borda vai para a rede do host e alcança o tv3ws por `127.0.0.1`; um erro de configuração do SSDP derruba a borda inteira, e a falta de rede não (morre-inteiro decidido pelo Luís em 09/10, revisto por ele em 10/10). Substituiu a opção B (decidida em 04/10, informado pelo Luís): um container próprio para o anúncio, `tv3ws-ssdp`, com a borda e o tv3ws na `ginga_net`, em que a falha do SSDP não derrubava as APIs. A C.3.4 não diz onde o anunciante roda; é decisão do projeto |
| Avatares como SVG inline | Dispensa servir arquivos PNG. Ficam no campo `avatar` do hash do usuário |
| Id do perfil em UUID (F-3; decidido pelo Luís em 11/10) | A Tabela 7 pede "UUID string" no `id`. O AoP gera `crypto.randomUUID()`, a carga inicial traz `c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10`, e o esquema do Redis (versão 2) exige o formato da IETF RFC 9562, em minúsculas, sem compatibilidade com os ids antigos (`user_<epoch-ms>`, `c3167a18-5dc5`). Um volume de antes precisa ser recriado ([Modelo de dados Redis]({{ site.baseurl }}/modelo-redis)) |
| Portas fixas só as necessárias (C1, opção b; decidido pelo Luís em 11/10) | Pedido do Joel na primeira reunião: só a 44642 fixa, o resto em porta livre. Ficaram fixas também a do AoP (o endereço que se digita e a origem das apps), a 1883, a 6379 e a faixa do remote-device, e a 44643 no modo SSDP. Para a 9001 do Mosquitto sair do host sem quebrar a página da TV, o AoP passou a atender o MQTT por WebSocket na própria porta (`/mqtt`) |
| Morre-inteiro sem exceção (C2; decidido pelo Luís em 11/10) | A morte do redis-commander derruba o container do Redis, como nos outros containers com mais de um processo. Até 11/10 ele era a exceção (V8/V9 do plano de consolidação), por ser ferramenta de inspeção |

---

## CI/CD

Cada submódulo (aop, bcast, tv3ws, infra) tem um workflow só, `.github/workflows/bump-tv30-pointer.yml` ("Build, push e bump submodule <nome> em TV30"), que dispara a cada push na `main` e faz duas coisas, nesta ordem:

1. **Constrói e publica a imagem no Docker Hub**, com as tags `<hash do commit>` e `latest`, no namespace do segredo `DOCKERHUB_USERNAME` (o `.env.example` usa `labmultisens`). O infra publica três imagens: `tv30-mosquitto`, `tv30-edgegateway` e `tv30-redis`. O aop, o tv3ws e o bcast fazem checkout do repositório Infra para usar o Dockerfile de lá.
2. **Atualiza o ponteiro do submódulo no repositório TV30**, com o PAT `TV30_REPO_TOKEN`. Esse passo depende do primeiro (`needs`): se o build ou o push falham, o ponteiro não muda.

A `latest` acompanha a `main` de cada submódulo; um clone com commits ainda não publicados roda o código dele com `docker compose up -d --build`.
