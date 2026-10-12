# TV30 — TV 3.0 AoP Experimentation

> **Repositório:** https://github.com/multisens/TV30
> **Contexto:** Projeto de pesquisa CEFET — plataforma de experimentação do padrão brasileiro de TV digital (ISDB-Tb / TV 3.0)

Monorepo principal do ecossistema TV 3.0. Orquestra todos os componentes via **submodules Git** e **Docker Compose**.
Os serviços trocam sinalização e eventos via **MQTT** (broker Mosquitto), leem e escrevem estado no **Redis** e conversam por **HTTP direto** em dois trechos: a borda repassa ao tv3ws as APIs que não responde ela mesma, e o AoP faz proxy para o bcast. Clientes das APIs entram só pela **borda** (`edgegateway`).

> **Norma × implementação:** a ABNT NBR 25608 define os papéis da plataforma TV 3.0 (receptor, TV 3.0 WebServices, broadcaster) e o modelo de consentimento/perfis. O transporte interno via **MQTT**, a **borda KrakenD** e o **Redis** são escolhas de implementação deste projeto — **não fazem parte da norma**.

---

## Submodules e responsabilidades

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | https://github.com/multisens/AOP | **Application-Oriented Platform** — interface do receptor TV 3.0. Renderiza UI, gerencia perfis de usuário (no Redis, dono das chaves de perfil desde a rodada de 05/10; desde o P4, grava pelas funções do Redis que conferem o esquema), exibe catálogo de apps e camadas de vídeo/gráficos. Node.js, porta **8080** |
| `tv3ws/` | https://github.com/multisens/TV3WS | **TV 3.0 WebServices** — implementação das APIs do Anexo C, menos a C.6.8 e a C.6.7.8/C.6.7.9, que a borda responde. Emissão do JWT, usuários (no Redis, lê os perfis, de que o AoP é o dono, e grava os atributos de emissora da C.6.14.5), serviços e dispositivos remotos; não valida credencial. TypeScript, portas internas **44652** (HTTP) e **44653** (HTTPS opcional), acesso pela borda |
| `infra/` | https://github.com/multisens/Infra | **Infraestrutura Docker** — Redis, borda KrakenD (`edgegateway`, com o plugin Go `tv30-auth`), Mosquitto com plugin C de validação de esquema, dockerfiles |
| `bcast/` | https://github.com/multisens/BcastService | **Broadcaster** — simula transmissão de sinal TV 3.0. Vídeo por HLS, com segmentos preparados antes com FFmpeg (`bcast/scripts/ffmpeg-hls.sh`, fora do container; a imagem não traz FFmpeg) e playlist montada a cada pedido; sinalização via MQTT. Hospeda módulos de apps de serviço (webmedia, uff, etc.) seguindo padrão `src/modules/<nome>/` |

O `.gitmodules` tem só esses quatro. `eduplay` (motadv/eduplay), `sepe` (motadv/se-presentation-engine) e `utils` (multisens/TV30-Utils) são repositórios relacionados, não submódulos deste.

---

## Arquitetura

Estado atual do código:

```
Cliente (app de emissora, app local autônomo, dispositivo remoto)
        ↓ HTTP :44642 (interna, porta fixa da C.3.4, todas as rotas)
        | :44643 (externa, só as rotas que admitem o não local; P1.9)
  edgegateway (infra/)    ← borda única: KrakenD interno + externo + docs;
                            plugin Go tv30-auth valida credenciais (warn)
                            e responde ele mesmo a C.6.8 e a C.6.7.8/C.6.7.9
        ↓ HTTP na ginga_net
  tv3ws (tv3ws/)          ← TV 3.0 WebServices (Anexo C); emite o
                            accessToken e não valida credencial; estado no Redis
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

**Descoberta SSDP.** Quem anuncia é a borda (L6, opção A, decidido pelo Luís em 09/10, no lugar da opção B, o container `tv3ws-ssdp`, decidida em 04/10). O anunciante é um processo a mais no container `edgegateway`: o binário Go `ssdp-announcer` (`infra/edgegateway/ssdp/`), que o `entrypoint.sh` só sobe com `SSDP_ENABLED=true`. Quem liga é o override `docker-compose.ssdp.yml`, que põe a borda em `network_mode: host` (variante `host`, com o tv3ws em `127.0.0.1:44652/44653`). Pelo morre-inteiro, decidido pelo Luís em 09/10 e revisto por ele em 10/10, o erro de configuração do anúncio derruba a borda inteira; a falta de rede não, e o anunciante espera e tenta de novo. Desde 11/10 (B2, decisão do Luís), o host do `LOCATION` é o `SSDP_ADVERTISE_HOST`, obrigatório com o anúncio ligado: sem ele, o `preflight` para a subida, e o anunciante sairia com erro de configuração; o `SERVER_URL` deixou de ser fonte do host do anúncio. O `/manifest` continua no tv3ws, atrás da borda, e o tv3ws da bridge não anuncia (`SSDP_ENABLED: "false"` no compose). A descoberta só é suportada em Linux nativo com Docker Engine (decisão do Joel, informada pelo Luís em 04/10; decisão do projeto, não da norma). Nesse ambiente, a descoberta por outro aparelho foi validada em 09/10, primeiro com a opção B e depois com a opção A (um notebook no mesmo Wi-Fi, testes 40 a 43). Ver [`docs/ssdp-verificacao.md`](./docs/ssdp-verificacao.md).

**Canais internos.** A comunicação interna não é só por MQTT, ao contrário do que esta seção dizia antes (o código desmente):

- sinalização e eventos passam pelo MQTT;
- o AoP e o tv3ws acessam o Redis diretamente, e a borda também: lê o que a decisão de credencial precisa e, desde a reunião de 05/10, escreve as chaves da C.6.8 (`bind-context:*`). Quem escreve cada família está em [`docs/modelo-redis.md`](./docs/modelo-redis.md);
- a página da TV (camada gráfica do AoP, no navegador) fala MQTT por WebSocket pelo próprio AoP: conecta em `ws(s)://<host da página>/mqtt`, e o AoP repassa a conexão ao WebSocket do Mosquitto pela `ginga_net` (`aop/src/mqtt-ws.js`; C1, decisão do Luís em 11/10). Só no host do AoP; num host de app, o `/mqtt` responde 404. Até 11/10, a página conectava direto na 9001 do host;
- o AoP busca as aplicações e o vídeo do bcast por proxy HTTP, no `bcastEntryPackageUrl` anunciado (`aop/src/server.js`). Desde o P1.3 (decisão do Luís em 10/10), cada aplicação de emissora é servida num nome de host próprio, na porta do AoP (origem `http://<app>.apps.localhost:8080`; `aop/src/app-hosts.js`), para que o navegador mande o `Origin` dela, que o AoP grava em `origins:associated` enquanto ela roda. O `<app>` sai do `appId` da BALD, fixo por app desde 11/10 (`urn-tv30-app-users-test`, por exemplo). Desde 11/10 (decisão do Luís), a URL que a camada gráfica abre mantém o prefixo do caminho antigo, `http://<app>.apps.localhost:8080/graphicsAppProxy<bcastEntryPointUrl>`, e o `/graphicsAppProxy/...` no host do próprio AoP redireciona (302) para o host da app; até 11/10, servia a app na origem do AoP, sem gravar origem. A camada gráfica entrega teclas e eventos do vídeo à aplicação por `postMessage` (ponte `bcast/public/js/aop-bridge.js`).

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
| `video/event` | bcast (eventos do `events.json` da playlist HLS) | front do AoP | Evento do vídeo, entregue à app da camada gráfica como `stream_event` |

---

## Execução

```bash
docker compose up -d
```

Defaults vêm do `.env` (raiz). Portas (C1, decisão do Luís em 11/10, revista por ele em 12/10 para a 44643): fixas no host a 44642, a 44643, a do AoP (8080), a 1883, a 6379 e a faixa 45000–45199; as demais saem numa porta livre que o Docker escolhe (`docker compose port <serviço> <porta>`), e `BCAST_PUBLISH` e `MQTT_WS_PUBLISH` as fixam; `EDGE_EXT_PUBLISH` muda a publicação da 44643 (`README.md`). A página da TV não usa a 9001 do host: com o AoP em container, nenhuma porta precisa mudar no Windows. Para quem roda o AoP fora do Docker no Windows, há uma dica (opção, decisão do Luís em 12/10): `MQTT_WS_PUBLISH=9003:9001` no `.env` da raiz e `MQTT_WS_PORT=9003` no `aop/.env`. Para desenvolver com um módulo no host (`npm run dev`), ver [`docs/dev-local.md`](./docs/dev-local.md). Para a descoberta SSDP em Linux nativo, defina `COMPOSE_FILE=docker-compose.yml:docker-compose.ssdp.yml` e `SSDP_ADVERTISE_HOST` com o IP da máquina na LAN no `.env` (`README.md`, seção *Descoberta SSDP*).

### Containers e portas

Seis containers contínuos. Com o override `docker-compose.ssdp.yml`, a borda roda em rede do host e tem um processo a mais, o anunciante SSDP.

| Container | Porta(s) no host | Descrição |
|-----------|----------|-----------|
| `redis` | 6379 (sem senha); commander em porta dinâmica, com login | Estado de sessão, usuários e credenciais + redis-commander embutido (debug). Morre-inteiro desde 11/10 (C2): a morte do commander derruba o container |
| `mqtt-broker` (serviço `mosquitto`) | 1883; WebSocket (9001 do container) em porta dinâmica (`MQTT_WS_PUBLISH`) | MQTT broker + plugin C de validação de esquema |
| `edgegateway` | 44642 e 44643, fixas (a 44643 por padrão, `EDGE_EXT_PUBLISH`, desde 12/10); docs (8085) em porta dinâmica. Com o override `docker-compose.ssdp.yml`: rede do host, com 44642, 44643 e 8085 direto no host e UDP 1900 | Borda única: KrakenD interno e externo + Swagger UI; plugin `tv30-auth`, que valida as credenciais e responde a C.6.8 e a C.6.7.8/C.6.7.9; morre-inteiro. Com o override (só Linux nativo), também o anunciante SSDP (`ssdp-announcer`), e o erro de configuração dele derruba a borda inteira (a falta de rede não; decisão do Luís em 10/10) |
| `tv3ws` | 45000–45199 (WebSockets) | TV 3.0 WebServices. 44652/44653 só na `ginga_net`; com o override, publicadas também em `127.0.0.1`, para a borda |
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
| KrakenD + plugin Go | Borda única (`edgegateway`) com validação de credenciais (`tv30-auth`), que também responde a C.6.8 e a C.6.7.8/C.6.7.9 |
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
| Estado de usuários em Redis | Consistência entre serviços; `userData.json` é só a carga inicial, no banco vazio. Desde a rodada da reunião de 05/10 (D-0510-5, aplicando o P5), a plataforma (AoP) é a única dona dos perfis, e o tv3ws só os lê. Os atributos de emissora de cada perfil (`user:{id}:broadcaster-attrs:*`, C.6.14.5) seguem com dois escritores: o tv3ws os grava, e o AoP os apaga no despejo (E4, aberto; `docs/modelo-redis.md`) |
| Esquema nas escritas do Redis por funções do próprio Redis, com auditoria (P4; decidido pelo Luís em 10/10) | Toda escrita do código nas famílias de chave do testbed passa por uma função da biblioteca `tv30` (`infra/redis/funcoes.lua`, esquema em `infra/redis/esquema.json`), que confere o esquema e grava de forma atômica, inclusive as invariantes entre chaves. Um teste estático impede o código de gravar direto, e a função de auditoria aponta o que está fora do esquema. A conexão segue sem senha e com escrita (A1): o Redis aplica o ACL de quem chama dentro da função, então não dá para liberar só a escrita pela função, e a escrita manual continua possível. Desde 11/10 (F-3, decisão do Luís), o esquema exige o id do perfil em UUID, como a Tabela 7, sem compatibilidade com os ids antigos; desde 12/10 (decisão do Luís, esquema na versão 3), o UUID é estrito: versão de 1 a 8, variante da RFC 9562 e o UUID nulo e o máximo recusados. Redis e funções são decisão do projeto; a norma não fala de armazenamento |
| Apps de serviço como módulos do bcast | Único container `bcast` serve tudo (sem duplicação MQTT/CORS) |
| Borda única com duas superfícies | Interna 44642 (fixa C.3.4) e externa 44643; credenciais validadas na borda (decisão de 28/09). Na reunião de 05/10, o Joel decidiu que o tv3ws fica "anônimo", sem validar credencial (D-0510-1), e que a borda responde a C.6.8 (D-0510-2) e a C.6.7.8/C.6.7.9 (D-0510-3); as três foram feitas. Sem TLS na borda, o 106 por protocolo ao não local (C.4.1.6) ficou sem quem o aplique (lacuna L3). Desde a P1.9 (decisão do Luís em 10/10), a externa só expõe as rotas que admitem o não local, e a interna expõe todas; a superfície de cada rota sai das `classes` no `generate.js`. Saem da externa `POST` e `DELETE /tv3/bind-context` e, desde 12/10 (decisão do Luís: a C.6.15.5 só para o cliente local), `GET /tv3/remote-device/devices/{classId}`, que dão 100 ali; se dariam 106 com TLS (C.4.1.8) está com o Joel. Na 44642, o não local que chama a C.6.15.5 recebe 106 da regra de classe (em `enforce`), e a Tabela C.78 pede 107: o código exato também está com o Joel (F-1, `docs/decisoes-pendentes.md`). A norma (C.3.4) só define as duas URLs base, e os conjuntos de rota por superfície são decisão do projeto |
| Um nome de host por app de emissora (P1.3; decidido pelo Luís em 10/10) | O associado é reconhecido pelo `Origin` em `origins:associated` (L1, risco aceito em 03/10). Servidas pelo proxy na origem do AoP, as apps chegavam à borda com o `Origin` do AoP e não eram reconhecidas. Com um host por app, na porta do AoP, o `Origin` passa a ser o da app, e o AoP grava essa origem ao lançá-la. Limite: `*.localhost` resolve para a máquina de quem abre a página, então a tela do AoP aberta de outra máquina não carrega as apps; `APPS_DOMAIN` aceita um domínio resolvível na rede. A C.4.1.7 deixa o mecanismo de diferenciação à implementação; host por app e proxy são decisão do projeto |
| A borda anuncia o SSDP, em rede do host (L6, opção A; decidido pelo Luís em 09/10) | O multicast do anúncio não saiu da bridge do Docker para a rede (medido no WSL2 em 02/10), então quem anuncia tem de estar na rede do host. Com o override `docker-compose.ssdp.yml`, a borda vai para a rede do host e alcança o tv3ws por `127.0.0.1`; um erro de configuração do SSDP derruba a borda inteira, e a falta de rede não (morre-inteiro decidido pelo Luís em 09/10, revisto por ele em 10/10). Substituiu a opção B (decidida em 04/10, informado pelo Luís): um container próprio para o anúncio, `tv3ws-ssdp`, com a borda e o tv3ws na `ginga_net`, em que a falha do SSDP não derrubava as APIs. A C.3.4 não diz onde o anunciante roda; é decisão do projeto |
| Portas fixas só as necessárias; o resto numa porta que o Docker escolhe (C1, opção b; decidido pelo Luís em 11/10, revisto por ele em 12/10 para a 44643) | Pedido do Joel na primeira reunião: só a 44642 fixa, o resto em porta livre. A opção b manteve fixas também a do AoP (endereço que a pessoa digita e origem das apps de emissora), a 1883, a 6379 e a faixa 45000–45199, e a 44643 no modo SSDP, que vai no anúncio. Em 12/10, o Luís fixou a 44643 também na bridge (`EDGE_EXT_PUBLISH`, padrão `44643:44643`): o `/manifest` a anuncia no `Server-SecureBaseURL`, e a porta que o Docker escolheria não sairia ali. Para a 9001 do Mosquitto sair do host sem quebrar a página da TV, o AoP passou a atender o MQTT por WebSocket na própria porta (`/mqtt`). A norma só fixa a 44642 (C.3.4); o resto é decisão do projeto |
| Morre-inteiro sem exceção, inclusive no container do Redis (C2; decidido pelo Luís em 11/10) | A morte do redis-commander derruba o container do Redis, e o `restart` o traz de volta, como nos outros containers com mais de um processo. Até 11/10 o commander era a exceção (decisão V8/V9 do plano de consolidação), por ser ferramenta de inspeção |

---

## Conhecidos / atenção

- `host.docker.internal:host-gateway` (não IP fixo)
- Apps de emissora em `<app>.apps.localhost`: com a tela do AoP aberta de outra máquina, elas não carregam (`*.localhost` resolve para a máquina de quem abre). Use `APPS_DOMAIN` com um domínio resolvível na rede (README, seção *Apps de emissora: um nome de host por app*)
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
