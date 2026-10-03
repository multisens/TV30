---
title: Início
layout: home
nav_order: 1
---

# TV 3.0 — Plataforma de Referência

Documentação técnica do monorepo **multisens/TV30**, um ambiente full-Docker para experimentação com o padrão brasileiro de TV digital (ISDB-Tb / TV 3.0), aderente à norma **ABNT NBR 25608**.

---

## O que é o TV30

Conjunto de microsserviços que reproduzem o ecossistema TV 3.0. Os componentes se dividem entre os **papéis definidos pela plataforma TV 3.0** (norma) e a **infraestrutura de implementação** escolhida por este projeto.

**Papéis da plataforma TV 3.0 (ABNT NBR 25608):**

- **AoP** (Application-Oriented Platform) — interface do receptor (Node.js, porta 8080)
- **tv3ws** — implementação dos Ginga CC WebServices (TV 3.0 WebServices) da ABNT NBR 25608 (TypeScript; acessada pela borda nas portas 44642/44643)
- **bcast** — simulação do broadcaster, hospeda apps de serviço (webmedia, users-test, etc.)

**Infraestrutura de implementação (escolha deste projeto, não exigida pela norma):**

- **Mosquitto + plugin C** — broker MQTT; o plugin valida o **esquema** das mensagens publicadas (não faz controle de acesso a tópicos nem consulta o Redis)
- **KrakenD** (`edgegateway`) — a borda: um container com as superfícies interna (44642) e externa (44643); valida credenciais (accessToken, bind-token, classe de cliente) no plugin Go `tv30-auth`, em modo `warn` por padrão
- **Redis** — estado de sessão, perfis e credenciais (parte do estado também vive em memória nos serviços e no `userData.json` de carga)

> **Norma × implementação:** a ABNT NBR 25608 especifica os Ginga CC WebServices, o modelo de consentimento e os perfis de usuário — **não** o transporte interno. O MQTT entre serviços, a borda KrakenD e o Redis são decisões de arquitetura deste testbed. (A comunicação interna não é só por MQTT: o AoP faz proxy HTTP direto ao bcast e AoP/tv3ws acessam o Redis diretamente.)

---

## Como navegar nesta documentação

| Seção | Conteúdo |
|-------|----------|
| [Arquitetura]({{ site.baseurl }}/arquitetura) | Topologia, containers, decisões arquiteturais |
| [Instalação]({{ site.baseurl }}/instalacao) | Pré-requisitos, WSL2/Docker, primeiros comandos |
| [Modelo de Dados Redis]({{ site.baseurl }}/modelo-redis) | Chaves, hashes, consent, sessão |
| [APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws) | Endpoints, mapeamento ABNT NBR 25608 |
| [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local) | Infra em containers + um módulo com `npm run dev`; teste `scripts/test-dev-host.sh` |
| [Verificação: descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao) | Anúncio SSDP medido no container, na bridge e no WSL; roteiro e cliente para a rede doméstica |
| [Criação de perfil (em Modelo de Dados Redis)]({{ site.baseurl }}/modelo-redis) | Do form do AoP direto ao Redis, seção "Sincronização entre JSON e Redis" |
| [Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos) | Tabela completa de tópicos e responsabilidades |
| [Troubleshooting]({{ site.baseurl }}/troubleshooting) | Erros comuns: WSL2, CORS, CRLF, etc. |

---

## Quick start

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
cd TV30
docker compose up -d
```

Acesse `http://localhost:8080` (AoP). Para inspecionar o Redis: Redis Commander na porta dinâmica mostrada por `docker port redis 18081`.

---

## Stack

| Tecnologia | Uso |
|------------|-----|
| Docker + Compose | Orquestração full-container |
| Node.js 23+ | AoP, tv3ws, bcast |
| TypeScript | tv3ws, bcast |
| Redis (ioredis) | Estado de sessão, perfis e credenciais (tv3ws, AoP) |
| Mosquitto + plugin C | MQTT broker + validação de esquema das mensagens |
| KrakenD + plugin Go | Borda única (`edgegateway`) com validação de credenciais (`tv30-auth`) |
| FFmpeg | Streaming de vídeo no bcast |
| Jekyll + just-the-docs | Esta documentação |
