# TV30 — testbed aberto da camada de Codificação de Aplicações da TV 3.0

![Node Version](https://img.shields.io/badge/Node.js-23.11.1-blueviolet?logo=nodedotjs)  ![MQTT](https://img.shields.io/badge/MQTT-blueviolet?logo=mqtt)  ![Docker](https://img.shields.io/badge/Docker-blue?logo=docker)

Testbed do padrão brasileiro de TV digital interativa **TV 3.0** (ABNT NBR 25608). Implementa, em microsserviços, os papéis da plataforma TV 3.0:
- o receptor (AoP);
- os TV 3.0 WebServices (tv3ws);
- o broadcaster simulado (bcast).

Por baixo, uma infraestrutura de apoio escolhida por este projeto:
- a borda KrakenD (`edgegateway`);
- o broker MQTT (Mosquitto, com plugin C de validação de schema);
- o estado em Redis.

> **Norma × implementação:** a ABNT NBR 25608 especifica os TV 3.0 WebServices (Anexo C), o gerenciador de perfis (8.7) e o de privacidade (8.8). O transporte interno via **MQTT**, a **borda KrakenD** e o **Redis** são decisões de arquitetura deste testbed: **não fazem parte da norma**.

É um **monorepo com submodules Git**, orquestrado por um único `docker-compose.yml` na raiz. A stack sobe inteira de uma vez, em qualquer host `amd64` com Docker, sem build local; no Mac com Apple Silicon, o build local é necessário (Pré-requisitos). As imagens vêm do Docker Hub, publicadas pelos workflows de cada submodule. Depois de um `git pull`, rode `docker compose pull` para atualizar as imagens locais.

---

## Pré-requisitos

- **Docker Engine** e **Compose v2** (`docker compose`, não `docker-compose`).
- **Git** com suporte a submodules.
- **Mac com Apple Silicon:** as imagens publicadas são `amd64`. Rode `docker compose build` antes de subir.
- **Windows:** WSL2 configurado como em [Instalação](./docs/instalacao.md#windows--wsl2).

---

## Quick start

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
cd TV30
cp .env.example .env
./tv30 up            # Windows: .\tv30.ps1 up
```

Abra http://localhost:8080, a interface do receptor (AoP). Para descer: `./tv30 down`.

O `./tv30 up` faz o `docker compose up -d` e sobe o anunciante da descoberta SSDP, que roda no host, fora do Docker. Também há `./tv30 status` e `./tv30 logs`. Só `docker compose up -d` também funciona, mas sem a descoberta.

> **Primeira subida, o que acontece sozinho:** três tarefas preparam o ambiente antes dos serviços.
> - O `preflight` diagnostica DNS e portas ocupadas e imprime os avisos no início do log (`docker logs tv30-preflight`). Se a subida falhar com `address already in use`, o dono da porta já está nomeado ali; a triagem completa está em [`docs/troubleshooting.md`](./docs/troubleshooting.md).
> - O `userfiles-seed` cria e popula `./user-files` a partir do template.
> - O `tls-init` gera o certificado do receptor em `.tv30/tls`.
>
> O `tv3ws/.env` é opcional.

> **Importante: não rode `docker compose` em `infra/`.** O `infra/` é submodule, e o compose dele já entra pelo `include:` do `docker-compose.yml` da raiz. Subido de dentro de `infra/`, o compose não vê os serviços `aop`, `tv3ws` e `bcast`.

> **Importante: sem `.env` na raiz, os serviços principais ficam de fora sem aviso.** O `aop`, o `tv3ws`, o `bcast`, o `mosquitto` e o `sysctl-init` têm `profiles` no compose. Sem `COMPOSE_PROFILES=mqtt,linux`, que vem no `.env.example`, só sobe a infra. Comece sempre com `cp .env.example .env`.

---

## Documentação

A documentação está em [`docs/`](./docs/index.md), que é a fonte única:
- [Instalação](./docs/instalacao.md): pré-requisitos, `.env`, portas, HTTPS e submódulos;
- [Arquitetura](./docs/arquitetura.md) e as demais páginas de *Como funciona*;
- [Decisões](./docs/decisoes.md) e [Não implementado](./docs/nao-implementado.md);
- [Solução de problemas](./docs/troubleshooting.md) e [Known Issues](./KNOWN-ISSUES.md).
