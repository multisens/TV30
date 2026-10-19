---
title: Início
layout: home
nav_order: 1
---

# TV 3.0 — Plataforma de Referência

Documentação técnica do monorepo **multisens/TV30**: um testbed, todo em containers Docker, do lado do receptor da TV 3.0 (o sistema de TV digital terrestre das ABNT NBR 25601 a 25609, também chamado DTV+; ABNT NBR 25608, 3.37). Ele implementa parte dos TV 3.0 WebServices da **ABNT NBR 25608**, Anexo C, e simula a emissora que alimenta o receptor. O público destas páginas são os alunos que chegam ao projeto e quem desenvolve nele.

---

## O que é o TV30

São três módulos do projeto, cada um num submódulo git, mais a infraestrutura que este testbed escolheu para ligá-los.

**Peças que correspondem a papéis descritos na norma:**

- **AoP** (`aop/`): a interface do receptor. Tem o catálogo de aplicações, as camadas de vídeo e gráficos e o gestor de perfis. É Node.js e fica na porta 8080. Na norma, a *TV 3.0 Application-oriented Platform* (3.38) é a plataforma inteira do receptor, com back-end e front-end; o módulo `aop/` é só a parte de interface dela.
- **tv3ws** (`tv3ws/`): a implementação dos TV 3.0 WebServices (Anexo C), em TypeScript. Na norma, esse componente faz parte da AoP (C.1 e C.2). Os clientes das APIs chegam a ele pela borda, nas portas 44642 e 44643. A exceção são os WebSockets de remote-device, que vão direto ao tv3ws, na faixa 45000–45199.
- **bcast** (`bcast/`): faz o papel da **emissora**, fora do receptor. Publica a sinalização (BAMT, ESG e BALD) e serve as aplicações de emissora e a mídia (webmedia, users-test, uff, eduplay).

**Infraestrutura de implementação** (escolha deste projeto, não exigida pela norma):

- **Borda** (`edgegateway`, KrakenD): um container com as duas superfícies das APIs, a interna (44642) e a externa (44643). O plugin Go `tv30-auth` valida as credenciais (access token, bind-token e classe de cliente), em modo `warn` por padrão. Desde a reunião de 05/10 com o Joel, a borda é o único ponto que confere o access token, o bind-token e a classe de cliente das requisições às APIs; o tv3ws só confere, na emissão do token (`/tv3/token`, C.6.1.3), o refresh token e a resposta ao desafio, e recusa com 106 a renovação por HTTP de um cliente não local. O plugin também responde as APIs C.6.8 (`/tv3/bind-context`) e C.6.7.8/C.6.7.9 (`/tv3/api-info`), sem repassá-las ao tv3ws.
- **Mosquitto com plugin C**: o broker MQTT. O plugin valida o **esquema** das mensagens publicadas nos tópicos que têm esquema declarado. Ele não faz controle de acesso a tópicos nem consulta o Redis.
- **Redis**: estado de sessão, perfis e credenciais. Parte do estado também vive em memória nos serviços, e o `userData.json` é só a carga inicial.

{: .nota }
> A ABNT NBR 25608 especifica os TV 3.0 WebServices (Anexo C), o modelo de consentimento (8.8) e os perfis de usuário. Ela **não** especifica o transporte interno: o MQTT entre serviços, a borda KrakenD e o Redis são decisões de arquitetura deste testbed e não contam como cobertura nem como lacuna da norma. A comunicação interna também não é só por MQTT: o AoP faz proxy HTTP direto ao bcast, e o AoP, o tv3ws e a borda acessam o Redis diretamente.

---

## Por onde começar

Para quem acabou de chegar, a ordem sugerida é esta:

1. **Subir a stack:** [Instalação]({{ site.baseurl }}/instalacao), ou o *Quick start* logo abaixo.
2. **Desenvolver um módulo** sem refazer imagem a cada mudança: [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local).
3. **Rodar os testes:** [Como testar]({{ site.baseurl }}/como-testar).
4. **Os termos** que aparecem no código e nas reuniões: [Glossário]({{ site.baseurl }}/glossario).
5. **Como funciona:** [Arquitetura]({{ site.baseurl }}/arquitetura), depois [APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws), [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis), [Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos), [Borda e credenciais]({{ site.baseurl }}/borda-credenciais) e [Descoberta SSDP]({{ site.baseurl }}/ssdp).
6. **O que está decidido e o que espera o orientador:** [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes).
7. **Quando algo dá errado:** [Solução de problemas]({{ site.baseurl }}/troubleshooting).

A seção [Histórico]({{ site.baseurl }}/historico) guarda documentos que registram um estado anterior ou uma medição pontual. Eles servem de registro, e o estado atual de cada assunto está nas páginas acima.

---

## Quick start

Linux com Docker Engine e Docker Compose v2 (no Windows, o mesmo dentro do WSL2; ver [Instalação]({{ site.baseurl }}/instalacao)):

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
cd TV30
cp .env.example .env    # liga os perfis mqtt e linux
docker compose up -d
```

- **Sem o `.env`, o receptor não sobe.** O `aop`, o `tv3ws`, o `bcast` e o `sysctl-init` estão no perfil `linux`, e o `mosquitto` no perfil `mqtt` (`docker-compose.yml` e `infra/docker-compose.yml`). Sem `COMPOSE_PROFILES=mqtt,linux`, que vem do `.env.example`, sobem só o `redis`, a borda e as tarefas de subida, e `http://localhost:8080` não responde.
- **Os quatro submódulos vêm por HTTPS**, sem chave SSH no GitHub. Até 11/10, o `bcast` usava URL SSH no `.gitmodules` (`git@github.com:multisens/BcastService.git`), e sem a chave o clone dele falhava; o Luís decidiu trocar por HTTPS em 11/10 (C5). Num clone feito antes, rode `git submodule sync --recursive && git submodule update --init --recursive` ([Instalação]({{ site.baseurl }}/instalacao#submódulos)).
- **Imagens:** o `.env.example` aponta para as imagens publicadas no Docker Hub (`DOCKERHUB_NS=labmultisens`, `IMAGE_TAG=latest`). O CI de cada submódulo publica a `latest` a cada push na `main`, então ela pode estar atrás do código do seu clone. Para rodar o que está no clone, use `docker compose up -d --build`.

Depois de subir:

| O quê | Onde |
|---|---|
| AoP (interface do receptor) | `http://localhost:8080` (`AOP_PUBLIC_PORT`) |
| APIs, superfície interna | `http://localhost:44642` (por exemplo, `/health` e `/manifest`) |
| APIs, superfície externa | `http://localhost:44643`, fixa desde 12/10 (ainda HTTP; o TLS está pendente). As rotas que a borda repassa ao tv3ws por ela precisam do HTTPS do tv3ws ([Instalação]({{ site.baseurl }}/instalacao#o-que-não-vem-no-clone)) |
| Documentação Swagger das duas superfícies | porta dinâmica: `docker port edgegateway 8085` |
| bcast (apps de emissora e mídia, direto) | porta dinâmica: `docker compose port bcast 8081` |
| Redis Commander | porta dinâmica: `docker port redis 18081`; pede login (usuário `admin` e senha `tv30-redis-admin` por padrão; `REDIS_COMMANDER_USER` e `REDIS_COMMANDER_PASSWORD` no `.env` da raiz). A conexão com o banco (6379) segue sem senha |

Ficam fixas no host a 44642, a 44643, a do AoP (8080), a 1883, a 6379 e a faixa 45000–45199 dos WebSockets de remote-device (C1, decisão do Luís em 11/10; a 44643 ficou fixa também na bridge em 12/10, também por decisão dele, porque o `/manifest` a anuncia). As outras saem numa porta livre que o Docker escolhe, e a tabela acima diz como achá-las; `docker compose ps` mostra todas. A página da TV fala MQTT pelo próprio AoP, em `ws://localhost:8080/mqtt`.

---

## Mapa da documentação

| Seção | Páginas |
|---|---|
| **Primeiros passos** | [Instalação]({{ site.baseurl }}/instalacao) · [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local) · [Como testar]({{ site.baseurl }}/como-testar) · [Glossário]({{ site.baseurl }}/glossario) |
| **Como funciona** | [Arquitetura]({{ site.baseurl }}/arquitetura) · [APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws) · [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis) · [Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos) · [Borda e credenciais]({{ site.baseurl }}/borda-credenciais) · [Descoberta SSDP]({{ site.baseurl }}/ssdp) |
| **Decisões** | [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes): o que depende do orientador, o que já foi decidido e por quem |
| **Solução de problemas** | [Solução de problemas]({{ site.baseurl }}/troubleshooting) |
| **Histórico** | [Medições da descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao) · [Avaliação do item 9 (credenciais)]({{ site.baseurl }}/avaliacao-item9-credenciais) · [Plano de consolidação de containers]({{ site.baseurl }}/plano-consolidacao-containers) |

A documentação da infraestrutura (borda, broker, Redis) fica no repositório [multisens/Infra](https://github.com/multisens/Infra/tree/main/docs), fora deste site.

---

## Stack

| Tecnologia | Uso |
|------------|-----|
| Docker + Compose v2 | Orquestração; tudo roda em containers |
| Node.js 23 (imagens `node:23-alpine`) | AoP, tv3ws e bcast |
| TypeScript | tv3ws e bcast |
| Redis | Estado de sessão, perfis e credenciais. Clientes: ioredis no tv3ws e no AoP; um cliente RESP próprio, em Go, na borda |
| Mosquitto + plugin C | Broker MQTT, com validação de esquema das mensagens |
| KrakenD + plugin Go | A borda (`edgegateway`), com a validação de credenciais (`tv30-auth`) |
| FFmpeg | Só para preparar, fora da stack, os segmentos de vídeo que o bcast serve (`bcast/scripts/ffmpeg-hls.sh` e `ffmpeg-dash.sh`). A imagem do bcast não traz FFmpeg |
| Jekyll + just-the-docs | Esta documentação |
