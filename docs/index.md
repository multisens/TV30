---
title: Início
layout: home
nav_order: 1
---

# TV 3.0 — Plataforma de Referência

Documentação técnica do monorepo **multisens/TV30**, um ambiente full-Docker para experimentação com o padrão brasileiro de TV digital (ISDB-Tb / TV 3.0), aderente à norma **ABNT NBR 25608**.

---

## O que é o TV30

Conjunto de microsserviços que reproduzem o ecossistema TV 3.0:

- **AoP** (Application-Oriented Platform) — interface do receptor (Node.js, porta 8080)
- **CCWS** (TV 3.0 Ginga CC WebServices) — API REST conforme ABNT NBR 25608 (TypeScript, portas 44652/44653)
- **bcast** — simulação do broadcaster, hospeda apps de serviço (webmedia, users-test, etc.)
- **Mosquitto + plugin C** — broker MQTT com ACL e validação de consentimento via Redis
- **KrakenD** — dois gateways (externo com consent-validator Go; interno sem overhead) que permite a implementação distribuída do CCWS
- **Redis** — fonte única de verdade para estado de sessão e perfis

Comunicação interna é **exclusivamente via MQTT**. Nenhum serviço chama outro diretamente por HTTP — quando precisa, vai via gateway.

---

## Como navegar nesta documentação

| Seção | Conteúdo |
|-------|----------|
| [Arquitetura]({{ site.baseurl }}/arquitetura) | Topologia, containers, decisões arquiteturais |
| [Instalação]({{ site.baseurl }}/instalacao) | Pré-requisitos, WSL2/Docker, primeiros comandos |
| [Modelo de Dados Redis]({{ site.baseurl }}/modelo-redis) | Chaves, hashes, consent, sessão |
| [APIs CCWS]({{ site.baseurl }}/apis-ccws) | Endpoints, mapeamento ABNT NBR 25608 |
| [Fluxo: Criação de Perfil]({{ site.baseurl }}/fluxo-criacao-perfil) | Do form até o MQTT `aop/users` |
| [Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos) | Tabela completa de tópicos e responsabilidades |
| [Troubleshooting]({{ site.baseurl }}/troubleshooting) | Erros comuns: WSL2, CORS, CRLF, etc. |

---

## Quick start

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
cd TV30
docker compose up -d
```

Acesse `http://localhost:8080` (AoP). Para inspecionar o Redis: `http://localhost:18081` (Redis Commander).

---

## Stack

| Tecnologia | Uso |
|------------|-----|
| Docker + Compose | Orquestração full-container |
| Node.js 23+ | AoP, CCWS, bcast |
| TypeScript | CCWS |
| Redis (ioredis) | Estado de sessão e perfis no CCWS |
| Mosquitto + plugin C | MQTT broker + ACL/consent via Redis |
| KrakenD + plugin Go | Gateway externo com consent-validator |
| FFmpeg | Streaming de vídeo no bcast |
| Jekyll + just-the-docs | Esta documentação |
