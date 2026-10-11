---
title: Glossário
parent: Primeiros passos
nav_order: 4
---

# Glossário

Termos e siglas que aparecem no código, nas páginas e nas reuniões. Cada termo traz o lugar onde está no código ou na norma. Seções citadas sem outro nome são da **ABNT NBR 25608**.

Quando o termo é da norma e o testbed o implementa de um jeito próprio, as duas coisas aparecem separadas: o que a norma define e o que é decisão deste projeto.

---

## As peças do testbed

| Termo | O que é | Onde |
|---|---|---|
| **AoP** | Na norma, a *TV 3.0 Application-oriented Platform*: a plataforma de software inteira do receptor, com back-end e front-end (3.38). No testbed, `aop` é o módulo da **interface do receptor**: catálogo de aplicações, camadas de vídeo e gráficos, gestor de perfis. Os TV 3.0 WebServices, que na norma são parte da AoP (C.1, C.2), ficam noutro módulo, o tv3ws | `aop/` ([multisens/AOP](https://github.com/multisens/AOP)) |
| **tv3ws** | A implementação dos **TV 3.0 WebServices** (Anexo C): as APIs REST que aplicações e outros aparelhos da casa usam. Até 20/09 se chamava `ccws` | `tv3ws/` ([multisens/TV3WS](https://github.com/multisens/TV3WS)) |
| **bcast** | O simulador da **emissora**, fora do receptor: publica a sinalização (BAMT, ESG, BALD) por MQTT e serve por HTTP as aplicações de emissora e a mídia. Cada serviço é um módulo | `bcast/src/modules/` ([multisens/BcastService](https://github.com/multisens/BcastService)) |
| **Borda** (`edgegateway`) | O container por onde entram todos os clientes das APIs: dois KrakenD (as duas superfícies), o plugin `tv30-auth` e a documentação Swagger. Decisão do projeto | `infra/edgegateway/`; [Borda e credenciais]({{ site.baseurl }}/borda-credenciais) |
| **`tv30-auth`** | O plugin Go da borda que decide sobre a credencial e responde a C.6.8 e a C.6.7.8/C.6.7.9 | `infra/edgegateway/plugin/` |
| **Broker** (`mqtt-broker`, serviço `mosquitto`) | O Mosquitto, com um plugin C que valida o esquema das mensagens dos tópicos que têm esquema declarado | `infra/mqtt-broker/plugin/` (esquemas em `config/schemas.json`); [Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos) |
| **Redis** | O armazenamento de sessão, perfis e credenciais, com carga inicial e o redis-commander embutidos no container | `infra/redis/`; [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis) |
| **redis-commander** | Interface web de inspeção do Redis, processo auxiliar do container `redis`, com login (D-L1). Desde 11/10 (C2, decisão do Luís), a morte dele derruba o container do Redis, e o `restart` o traz de volta; até ali, o banco seguia | `infra/redis/entrypoint.sh`; porta dinâmica: `docker port redis 18081` |
| **Carga inicial** (`seed:done`) | Os perfis do `infra/user-files-template/userData.json`, convertidos no build da imagem do Redis e aplicados pelo entrypoint só quando a chave `seed:done` não existe | `infra/redis/emit_seed.py`, `infra/redis/entrypoint.sh` |
| **Tarefas de subida** (`tv30-preflight`, `tv30-userfiles-seed`, `tv30-sysctl-init`) | Containers que rodam uma vez na subida: o diagnóstico de DNS e portas (que impede a borda de subir se a 44642 estiver ocupada por processo nativo), a cópia de `user-files/` a partir do modelo e o ajuste de sysctl no Linux | `scripts/preflight.sh`, `scripts/seed-user-files.sh`, `docker-compose.yml` |
| **`ginga_net`** | A rede Docker (bridge) que liga os containers do projeto. Componente novo entra nela | `infra/docker-compose.yml`; `templates/componente/` |
| **Template de componente** | O modelo para um componente novo em container, com um exemplo que fala com o Redis e o broker | `templates/componente/`; `scripts/test-template.sh` |
| **Guaraná** | Cliente das APIs mantido fora deste repositório (Pedro). Ainda não obtém access token, e por isso a borda roda em `warn` | `infra/docker-compose.yml` (comentário do `AUTH_ENFORCE`) |

---

## Clientes e credenciais (Anexo C)

| Termo | O que é | Onde |
|---|---|---|
| **Classes de cliente** | A norma distingue três (C.3.1): o **local associado** (*associated local client*: aplicação de emissora associada a um contexto de serviço DTV), o **local autônomo** (*stand-alone local client*: aplicação nativa ou instalada no receptor, sem contexto de serviço) e o **não local** (*non-local client*: aplicação noutro aparelho da rede da casa). No código, os valores são `local-associated`, `local-autonomous` e `non-local` | claim `class` do access token; `classes` de cada rota no `infra/edgegateway/routes.json`; `ClientClass` em `tv3ws/src/modules/auth-manager/client.ts` |
| **Access token** | JWT que dá acesso às APIs ao cliente não local e ao autônomo (C.4.1.2), obtido pelas APIs C.6.1.2 e C.6.1.3. No testbed, o tv3ws o emite em HS256 com o `JWT_SECRET`, e a borda o valida | emissão: `tv3ws/src/api/client-identification/`; validação: `infra/edgegateway/plugin/jwt.go` |
| **Refresh token** | Credencial que o cliente guarda para pedir novos access tokens no `/tv3/token`, sem nova autorização (C.6.1.3, C.6.1.4.5). O tv3ws troca o refresh token a cada `/tv3/token` | `rotateRefreshToken`, em `tv3ws/src/modules/auth-manager/manager.ts` |
| **`clientid`** | Identificador que o cliente gera (UUID, C.6.1.4.3) e passa ao `/tv3/authorize`. Reusar um `clientid` dá 101 (C.6.1.4.4; decisão D-L2) | `tv3ws/src/api/client-identification/controller.ts` |
| **Pareamento** (`pm=qrcode`, `pm=kex`, PIN) | Como o cliente não local prova ao espectador que é ele: pelo QR code que a TV mostra ou por troca de chaves ECDH com um PIN de quatro dígitos (C.4.3; Tabela C.3) | `tv3ws/src/api/client-identification/`, `tv3ws/src/util/encryption.ts` |
| **Bind-token** | JWT assinado pela **emissora**, que dá a clientes não locais e autônomos acesso às APIs protegidas de um contexto de serviço (C.4.1.2, C.4.1.3). O receptor não o emite: guarda as chaves que a emissora registra (C.6.8.2) e valida o token nas quatro frentes da C.4.1.4 | chaves em `bind-context:{serviceId}`; `infra/edgegateway/plugin/keys.go`, `bindcontext.go` |
| **`token+bind`, `token`, `none`** | A política de credencial de cada rota no testbed: access token e bind-token, só access token, ou nenhuma. O `token+bind` marca as APIs cujo "Security requirements" diz que o bind-token *shall* ser enviado | campo `auth` do `infra/edgegateway/routes.json` |
| **Origem associada** | A origem (`Origin`) de uma aplicação de emissora em execução, que o AoP grava no hash `origins:associated`. A borda trata como local associado a requisição sem `Authorization` com esse `Origin`. A norma deixa o mecanismo de diferenciação à implementação (C.4.1.7); o `Origin` é escolha do projeto, com o risco do `Origin` forjado aceito pelo Luís em 03/10 (L1) | `aop/src/core.js`, `aop/src/app-hosts.js`; `infra/edgegateway/plugin/handler.go` |
| **Host próprio da app** (`<app>.apps.localhost`) | Cada aplicação de emissora abre num nome de host próprio, na porta do AoP, para o navegador mandar o `Origin` dela (P1.3, decisão do Luís em 10/10). `<app>` sai do `appId` da BALD, fixo por app desde 11/10 (`urn-tv30-app-users-test`, por exemplo), e a URL leva o prefixo `/graphicsAppProxy` desde 11/10. `APPS_DOMAIN` troca o domínio | `aop/src/app-hosts.js`; `bcast/src/modules/*/index.ts`; `.env.example` |
| **`warn` / `enforce`** | Os dois modos da borda (`AUTH_ENFORCE`). Em `warn` (padrão), a falha de credencial só é registrada e marcada no cabeçalho `X-TV30-Auth-Warn`; em `enforce`, a requisição é recusada com o erro da C.3.2 | `infra/edgegateway/plugin/config.go`, `handler.go` |
| **`X-TV30-Auth-Warn`** | Cabeçalho que a borda acrescenta em `warn`, com o código que o `enforce` daria (por exemplo, `107`). Não é da norma | `infra/edgegateway/plugin/handler.go` |
| **Superfície interna / externa** | As duas portas das APIs na borda. A norma define o `Server-BaseURL` (HTTP, porta fixa 44642) e o `Server-SecureBaseURL` (HTTPS, porta livre) (C.3.4). No testbed, a interna (44642) expõe as 26 rotas e a externa (44643 no container, ainda HTTP) só as 24 que admitem o não local (P1.9); os conjuntos de rota por superfície são decisão do projeto. Desde 11/10 (C1), na bridge, a 44643 sai numa porta de host escolhida pelo Docker | `infra/edgegateway/routes.json` (`surfaces`), `generate.js` (`SURFACE_RULES`) |
| **`clients:authorized` / `clients:blocked`** | Os dois conjuntos de clientes no Redis, gravados pelo tv3ws: os autorizados pelo espectador no pop-up (D-0510-4) e os recusados ou bloqueados (C.4.2.2). Disjuntos. A borda recusa com 107 o access token de um `sub` bloqueado e, desde 11/10 (E6, decisão do Luís), o de um `sub` fora dos autorizados | `tv3ws/src/modules/auth-manager/manager.ts`; `infra/edgegateway/plugin/handler.go` |
| **Formato de erro C.3.2** e **códigos** | Erro de API sai com status 404 e corpo `{"error": <n>, "description": "..."}`. Os códigos são os da Tabela C.1: 100 (API não encontrada), 101 (argumento inválido), 102 (acesso não autorizado pelo usuário), 104 (bind-token ausente), 105 (argumento ausente), 106 (API indisponível para o ambiente), 107 (access token inválido), 108 (bind-token inválido), 200 (recurso da plataforma indisponível), 300 (nenhum serviço DTV em uso), entre outros | `tv3ws/src/util/error.ts`; `infra/edgegateway/plugin/handler.go` |
| **`Accept-Version` / `API-Version`** | Negociação de versão das APIs (C.3.6.5, C.3.6.6). O testbed aceita 2.0 (padrão) e 2.1 | `tv3ws/src/middleware/basic.ts`; `infra/edgegateway/plugin/edge.go` |
| **Consentimento** e ***consent*** | O **consentimento da norma** é o do Privacy Manager (8.8), que o testbed não implementa (o menu do AoP tem um item "Data Privacy settings" sem função). No código, *consent* tem outro sentido: a **visibilidade do perfil por serviço**, o SET `user:{id}:consent` (no `userData.json`, `accessConsent`), que filtra a lista de perfis da C.6.14.1. O antigo plugin `consent-validator` da borda, removido, era só um proxy | `user:{id}:consent` em `tv3ws/src/api/user/service.ts` e `aop/src/modules/profile-manager/service.js` |
| **Perfil de usuário** | Os atributos básicos do perfil do espectador (Tabela 7). No testbed, o hash `user:{id}`, cujo dono é o AoP (D-0510-5). Desde 11/10 (F-3, decisão do Luís), o `id` é UUID, como pede a Tabela 7 | `aop/src/modules/profile-manager/`; [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis) |

---

## Serviço, sinalização e aplicações

| Termo | O que é | Onde |
|---|---|---|
| **Serviço DTV** | Serviço de televisão digital (3.11). Na TV 3.0, um serviço baseado em Bootstrap Application | identificadores `urn:tv30:service:...` no compose (`BSID`, `*_SID`) |
| **Serviço corrente** | O serviço DTV selecionado no receptor. Nas APIs, `current-service` vale como apelido dele no lugar do `<service-context-id>` (C.3.5). No testbed, o AoP publica o id em `aop/currentService`, o tv3ws o espelha em `session:current-service-id`, e o `GET /tv3/current-service` (C.6.3.1) o informa | `aop/src/core.js`; `tv3ws/src/core.ts` |
| **`serviceContextId`** (`<service-context-id>`) | O identificador de um contexto de serviço DTV nas URLs das APIs (C.3.5; segue o `SLT.Service@globalServiceId`). No testbed é uma constante para todos os serviços (L2) | `tv3ws/src/core.ts` |
| **LLS / SLS** | *Low-Level Signaling* (7.2.2: descoberta e configuração dos serviços do canal) e *Service Layer Signaling* (7.2.3: reprodução de mídia e execução das aplicações de um serviço). No testbed, prefixos dos tópicos de sinalização do bcast | tópicos `tlm/lls/<bsid>/...` e `tlm/sls/<sid>/...` |
| **BAMT / BAM** | *Bootstrap Application Manifest Table*, no LLS, com um *Bootstrap Application Manifest* (BAM) por serviço DTV (8.4.4; Tabela 6). O AoP monta o catálogo a partir dela; o `initialMediaURLs` do BAM é o vídeo que a camada de vídeo toca | tópico `tlm/lls/<bsid>/bamt`; `bam()` de cada módulo do bcast; tipo em `bcast/src/types.ts` |
| **BALD** | *Broadcaster Application Location Descriptor* (Tabela 10, 10.1): a sinalização das aplicações de emissora de um serviço. A 7.2.3 a lista no SLS, e a 10.1.1 a chama de instância do LLS; o testbed a publica como SLS. O atributo `@bcastEntryPackageUrl` aponta, na norma, para um pacote entregue por ROUTE; no testbed, para a URL HTTP da aplicação no bcast | tópico `tlm/sls/<sid>/bald`; `aop/src/modules/bootstrap-application/service.js` |
| **ESG** | O guia de programação do serviço. No testbed, uma mensagem por serviço, publicada pelo bcast | tópico `tlm/sls/<sid>/esg` |
| **Bootstrap Application / aplicação de emissora** | A *Bootstrap Application* é a aplicação inicial de um serviço DTV, anunciada pela sinalização (3.5); a *Broadcaster Application*, a aplicação adicional associada ao contexto do serviço (3.7). Nas páginas, "aplicação de emissora" (ou "app de emissora") é a página de um módulo do bcast que o AoP abre na camada gráfica a partir da BALD | `bcast/src/modules/`; `aop/src/modules/graphic-overlays/` |
| **Camadas** (`rxgui`, vídeo, gráficos, pop-ups) | As camadas da tela do AoP, comandadas por tópicos `aop/display/layers/...` | `aop/src/modules/graphic-overlays/view.ejs`; [Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos) |
| **`/mqtt`** (MQTT por WebSocket pelo AoP) | O caminho, na porta do próprio AoP, em que a página da TV conecta no broker por WebSocket; o AoP repassa a conexão ao Mosquitto pela `ginga_net`. Só no host do AoP. Desde 11/10 (C1, decisão do Luís); até ali, a página conectava direto na 9001 do host. Decisão do projeto, fora da norma | `aop/src/mqtt-ws.js`; `aop/src/modules/graphic-overlays/view.ejs` |
| **Ponte de eventos** (`aop-bridge.js`) | Com a aplicação de emissora noutra origem, a camada gráfica lhe entrega teclas e eventos do vídeo por `postMessage`; a ponte, incluída em cada aplicação, os redespacha no documento dela. Contrato do projeto, fora da norma | `bcast/public/js/aop-bridge.js`; `aop/src/modules/graphic-overlays/view.ejs` |
| **`/graphicsAppProxy`** | Prefixo do caminho da aplicação de emissora. Desde 11/10 (decisão do Luís), fica na URL que a camada gráfica abre, no host próprio da app (`http://<app>.apps.localhost:8080/graphicsAppProxy/...`), e sai antes de o pedido ir ao bcast; ali é opcional. No host do próprio AoP, redireciona (302) para o host da app em execução, ou responde 404 sem app. Até 11/10, no host do AoP, era um proxy que servia a app na origem do AoP, sem gravar origem associada | `aop/src/app-hosts.js`; `aop/src/server.js` |
| **`/videoStreamProxy`** | O caminho de proxy do AoP para o vídeo do bcast (`initialMediaURLs` do BAM), na origem do próprio AoP | `aop/src/server.js` |
| **Remote device** e ***handle*** | Aparelho da rede da casa registrado para executar parte de uma aplicação (3.30; C.6.15), que conversa com o tv3ws por WebSocket. O fluxo por *handle* é a versão 2.1, a proposta ao Fórum | `tv3ws/src/api/multi-device/`, `tv3ws/src/modules/remotedevice-manager/` |
| **SSDP** e **`/manifest`** | A descoberta do receptor na rede local (C.3.4): anúncio e busca em UDP 1900 e um GET no `LOCATION`, que devolve os cabeçalhos `Server-*` e `Device-*`. No testbed, a borda anuncia (com o override `docker-compose.ssdp.yml`), e o tv3ws serve o `/manifest` | `infra/edgegateway/ssdp/`; `tv3ws/src/manifest.ts`; [Descoberta SSDP]({{ site.baseurl }}/ssdp) |
| **Ginga** | Na norma, os motores de apresentação da AoP (Ginga-NCL e Ginga-HTML5) e o *Ginga Common Core*, de que os TV 3.0 WebServices fazem parte (C.2). Não há motor Ginga neste repositório | — |

---

## Mecanismos e termos do projeto

| Termo | O que é | Onde |
|---|---|---|
| **Tabela única de rotas** (M4) | O `routes.json`, de onde o build da borda gera as configurações do KrakenD, os OpenAPI e a tabela do plugin | `infra/edgegateway/routes.json`, `generate.js` |
| **`EDGE_VARIANT`** | Onde a borda procura o tv3ws: `linux` (container, padrão), `windows` (no host, porta 44654; vale também em Linux) e `host` (a borda em rede do host, com o override do SSDP) | `infra/edgegateway/routes.json` (`backends`); [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local) |
| **Dev-host** | O arranjo de desenvolvimento com a infraestrutura em containers e um ou mais módulos rodando no host com `npm run dev`, e o teste que o automatiza | `scripts/test-dev-host.sh`; [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local) |
| **Morre-inteiro** | Regra do projeto para containers com mais de um processo: se um processo cai, o container inteiro cai, e o `restart` o traz de volta. Sem exceção desde 11/10 (C2, decisão do Luís): até ali, a morte do redis-commander não derrubava o container do Redis | `infra/edgegateway/entrypoint.sh`; `infra/redis/entrypoint.sh`; `templates/componente/` |
| **Porta fixa / porta escolhida pelo Docker** (C1) | Política de portas decidida pelo Luís em 11/10 (opção b): fixas no host a 44642 (norma), a do AoP, a 1883, a 6379 e a faixa 45000–45199, e a 44643 no modo SSDP; as outras saem numa porta livre que o Docker escolhe. `EDGE_EXT_PUBLISH`, `BCAST_PUBLISH` e `MQTT_WS_PUBLISH` são o valor que vai em `ports` (só o número = porta escolhida pelo Docker; `host:container` = fixa) | `docker-compose.yml`, `infra/docker-compose.yml`; `docker compose port <serviço> <porta>` |
| **Override `docker-compose.ssdp.yml`** | Arquivo de compose opcional que põe a borda em rede do host e liga o anunciante SSDP. Só Linux nativo | `docker-compose.ssdp.yml`; `COMPOSE_FILE` no `.env` |
| **Perfis do compose** (`linux`, `mqtt`) | Grupos de serviço do compose. Sem `COMPOSE_PROFILES=mqtt,linux`, o AoP, o tv3ws, o bcast e o broker não sobem | `docker-compose.yml`, `infra/docker-compose.yml`, `.env.example` |
| **Opção A / opção B** (L6) | As duas formas avaliadas de anunciar o SSDP: a borda anuncia em rede do host (A, a atual, decidida pelo Luís em 09/10) ou um container só para o anúncio (B, de 04 a 09/10) | [Medições da descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao) |

---

## Rótulos de decisão

Os rótulos aparecem nos comentários do código (`DECIDIDO (...)`, `PENDENTE (Joel)`), nos scripts e nas páginas. Todos remetem a [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes), que diz quem decidiu cada ponto e quando.

| Rótulo | O que é |
|---|---|
| **D1 a D6** | Decisões da reunião de 28/09 sobre a validação de credenciais na borda |
| **D-L1, D-L2, D-L4** | Decisões do Luís em 03/10 (itens A1, A2 e A5 de *Decisões pendentes*) |
| **D-0510-1 a D-0510-7** | Decisões do Joel na reunião de 05/10 |
| **P1.3, P1.9, P4, P5** | Itens da lista de decisões do projeto. P1.3 (uma origem por app de emissora), P1.9 (superfícies com rotas distintas) e P4 (esquema nas escritas do Redis) foram decididos pelo Luís em 10/10, e os pontos que o P1.3 e o P4 deixaram a confirmar, por ele em 11/10. Do P5, o critério "um dono por família de chave" foi aplicado na rodada de 05/10; a outra parte (o estado de documento Ginga) espera o componente do Rodrigo |
| **L1 a L8** | Lacunas: pontos que a norma deixa à implementação ou que ainda não têm decisão. L1 a L5 e L7 estão na seção A de *Decisões pendentes*, a L6 (onde roda o anunciante SSDP) no B1 e a L8 (URL SSH do bcast, trocada por HTTPS em 11/10) no C5 |
| **A1–A10, B1–B3, C1–C8, D1–D5, E1–E7** | Os itens das seções A a E de *Decisões pendentes*. O "D" da seção D (negociação de versão) não é o D1–D6 de 28/09. Vários deles foram decididos pelo Luís em 11/10 (A4, B2, B3, C1, C2, C5, E1, E3 e E6), reclassificados como escolhas de implementação do testbed |
| **F-2, F-3** | Pontos da seção F de *Decisões pendentes* decididos pelo Luís em 11/10: F-2, cada superfície lista na C.6.7.9 só as APIs que oferece (P1.9); F-3, id do perfil em UUID (P4) |
| **V1 a V13** | Decisões do [Plano de consolidação de containers]({{ site.baseurl }}/plano-consolidacao-containers), de 19/09 |
| **Item N** | Número de um item da lista de trabalho do projeto (por exemplo, o item 9, validação de credenciais) |
