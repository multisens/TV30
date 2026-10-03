---
title: Arquitetura
nav_order: 2
---

# Arquitetura

## Visão geral

O diagrama descreve o estado atual do código, não o desenho publicado anteriormente.

```
Cliente (app de emissora, app local autônomo, dispositivo remoto)
        ↓ HTTP :44642 (interna, porta fixa da C.3.4) | :44643 (externa)
  edgegateway (infra/)    ← borda única: KrakenD interno + externo + docs;
                            plugin Go tv30-auth valida credenciais (warn)
        ↓ HTTP na ginga_net
  tv3ws (tv3ws/)          ← Ginga CC WebServices (Anexo C); assina o
                            accessToken; estado no Redis
        ↕ MQTT                    ↕ Redis
  Mosquitto + plugin C    ← valida o ESQUEMA das mensagens publicadas
        ↕ MQTT
  AoP (aop/)              ← UI do receptor; perfis lidos/escritos direto no Redis
        ↓ HTTP (proxy /graphicsAppProxy e /videoStreamProxy)
  bcast (bcast/)          ← sinalização (BAMT/ESG/BALD) por MQTT; apps de
                            serviço e mídia por HTTP
```

**Canais internos.** Pelo código, a comunicação interna não é toda por mensageria:

- **Sinalização e eventos** passam pelo MQTT.
- **Armazenamento:** o AoP e o tv3ws leem e escrevem no Redis diretamente.
- **HTTP direto:** o AoP faz proxy HTTP para o bcast, buscando aplicações e vídeo no `bcastEntryPackageUrl` que o bcast anuncia (`aop/src/server.js`).

A versão anterior desta página dizia que "todos os serviços se comunicam via MQTT". Isso não corresponde ao código. Clientes das APIs entram **só pela borda**: as portas do tv3ws não são publicadas no host.

> **Norma × implementação:** o MQTT, a borda KrakenD e o Redis são decisões de arquitetura deste testbed, **não** exigências da ABNT NBR 25608. A norma especifica os Ginga CC WebServices, o modelo de consentimento e os perfis de usuário, mas não o transporte interno nem a infraestrutura de back-end.

---

## Submódulos

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | [multisens/AOP](https://github.com/multisens/AOP) | Interface do receptor TV 3.0: UI, gestor de perfis, catálogo de apps e camadas de vídeo/gráficos. Node.js, porta **8080** |
| `tv3ws/` | [multisens/TV3WS](https://github.com/multisens/TV3WS) | Implementação dos Ginga CC WebServices: JWT, usuários (Redis), serviços e dispositivos. TypeScript, portas internas **44652/44653**, com acesso pela borda |
| `infra/` | [multisens/Infra](https://github.com/multisens/Infra) | Redis, a borda KrakenD (`edgegateway`), Mosquitto + plugin C e os dockerfiles |
| `bcast/` | [multisens/BcastService](https://github.com/multisens/BcastService) | Simula o broadcaster: streaming via FFmpeg, sinalização por MQTT e hospedagem das apps de serviço |

O `.gitmodules` contém só esses quatro. `eduplay`, `sepe` (se-presentation-engine) e `TV30-Utils` são repositórios relacionados, mas não são submódulos deste repositório.

---

## Containers e portas

| Container | Porta(s) no host | Descrição |
|-----------|----------|-----------|
| `redis` | 6379; commander em porta dinâmica (`docker port redis 18081`) | Redis, com carga inicial e o redis-commander embutido para debug |
| `mqtt-broker` (serviço `mosquitto`) | 1883, `${MQTT_WS_PORT:-9001}` | Mosquitto + plugin C de validação de esquema |
| `edgegateway` | 44642, 44643; docs em porta dinâmica (`docker port edgegateway 8085`) | Borda única. Contém os dois processos KrakenD (superfícies interna e externa) e a documentação Swagger. Morre-inteiro: se um processo cai, o container cai |
| `tv3ws` | 45000–45199 (WebSockets de remote-device) | Ginga CC WebServices. As portas 44652/44653 ficam só na `ginga_net` |
| `aop` | 8080 | Interface do receptor |
| `bcast` | `${BCAST_PORT:-8081}` | Broadcaster + módulos de apps de serviço |
| `tv30-preflight`, `tv30-userfiles-seed`, `tv30-sysctl-init` | — | Tarefas únicas de subida: diagnóstico de DNS e portas, carga de `./user-files` e ajuste de sysctl (Linux) |

---

## Apps de serviço (padrão webmedia)

As apps são **módulos** dentro do container `bcast`, não containers separados. Padrão:

```
bcast/src/modules/<nome>/
├── index.ts        # implementa ServiceInterface (router próprio + EJS)
├── app.ejs         # view principal
└── companion/      # assets, JS auxiliar
```

Os módulos reaproveitam o cliente MQTT do bcast e não criam conexão nem container novos. Exemplos atuais: `webmedia`, `users-test`, `uff` e `eduplay`.

---

## Decisões arquiteturais

| Decisão | Motivo |
|---------|--------|
| Docker | Um único caminho de deploy. Para desenvolvimento, a infra roda em containers e o módulo no host ([dev-local]({{ site.baseurl }}/dev-local)) |
| Monorepo com submódulos | Cada componente tem ciclo de vida e CI independentes |
| MQTT para sinalização e eventos entre serviços | Desacoplamento. Não é o único canal interno (ver *Canais internos*) |
| Estado de usuários em Redis | `userData.json` serve de carga inicial e de re-sincronização (tópico `aop/users`) |
| Apps de serviço como módulos do bcast | Um único container serve todas, sem duplicar MQTT e CORS |
| Borda única com duas superfícies (fase 2) | A interna fica na 44642, fixa pela C.3.4, e a externa na 44643. Credenciais validadas na borda (decisão de 28/09, plugin `tv30-auth`): pela decisão, o tv3ws só implementaria as APIs. Estado corrente: o tv3ws ainda responde 107 a credencial inválida e 106 ao não local na superfície HTTP, nos dois modos; limpeza pendente |
| Avatares como SVG inline | Dispensa servir arquivos PNG. Ficam no campo `avatar` do hash do usuário |

---

## CI/CD

Cada submódulo (aop, bcast, tv3ws, infra) tem um workflow `.github/workflows/bump-tv30-pointer.yml`. Ele dispara a cada push na `main` e atualiza automaticamente o ponteiro do submódulo no repositório TV30, usando o PAT `TV30_REPO_TOKEN`.

Cada submódulo também faz build e push da própria imagem Docker no Docker Hub (`labmultisens/tv30-<componente>`).
