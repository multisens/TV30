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
                            e responde ele mesmo a C.6.8 e a C.6.7.8/C.6.7.9
        ↓ HTTP na ginga_net
  tv3ws (tv3ws/)          ← TV 3.0 WebServices (Anexo C); emite o
                            accessToken e não valida credencial; estado no Redis
        ↕ MQTT                    ↕ Redis
  Mosquitto + plugin C    ← valida o ESQUEMA das mensagens publicadas
        ↕ MQTT
  AoP (aop/)              ← UI do receptor; dono dos perfis no Redis
        ↓ HTTP (proxy /graphicsAppProxy e /videoStreamProxy)
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
- **HTTP direto:** o AoP faz proxy HTTP para o bcast, buscando aplicações e vídeo no `bcastEntryPackageUrl` que o bcast anuncia (`aop/src/server.js`).

A versão anterior desta página dizia que "todos os serviços se comunicam via MQTT". Isso não corresponde ao código. Clientes das APIs entram **só pela borda**: as portas do tv3ws não são publicadas no host (com o override do SSDP, abaixo, são publicadas só em `127.0.0.1`, para a borda).

**Descoberta SSDP.** Quem anuncia é a borda (L6, opção A, decidido pelo Luís em 09/10, no lugar da opção B, o container `tv3ws-ssdp`, decidida em 04/10). O anunciante é um processo a mais no container `edgegateway`: o binário Go `ssdp-announcer` (`infra/edgegateway/ssdp/`), que o `entrypoint.sh` só sobe com `SSDP_ENABLED=true`. Quem liga é o override opcional `docker-compose.ssdp.yml`, que põe a borda em `network_mode: host`, na variante `host` (o tv3ws é alcançado por `127.0.0.1:44652/44653`). Pelo morre-inteiro, decidido pelo Luís em 09/10 e revisto por ele em 10/10, o erro de configuração do anúncio derruba a borda inteira; a falta de rede não, e o anunciante espera e tenta de novo. O `/manifest` continua no tv3ws, atrás da borda, e o tv3ws da bridge não anuncia (`SSDP_ENABLED: "false"` no compose). A descoberta só é suportada em Linux nativo com Docker Engine (decisão do Joel, informada pelo Luís em 04/10; decisão do projeto, não da norma). Nesse ambiente, a descoberta por outro aparelho foi validada em 09/10, primeiro com a opção B e depois com a opção A (um notebook no mesmo Wi-Fi, testes 40 a 43). Detalhes e medições em [Verificação: descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao).

> **Norma × implementação:** o MQTT, a borda KrakenD e o Redis são decisões de arquitetura deste testbed, **não** exigências da ABNT NBR 25608. A norma especifica os TV 3.0 WebServices (Anexo C), o modelo de consentimento e os perfis de usuário, mas não o transporte interno nem a infraestrutura de back-end.

---

## Submódulos

| Pasta | Repositório | Responsabilidade |
|-------|-------------|------------------|
| `aop/` | [multisens/AOP](https://github.com/multisens/AOP) | Interface do receptor TV 3.0: UI, gestor de perfis, catálogo de apps e camadas de vídeo/gráficos. Node.js, porta **8080** |
| `tv3ws/` | [multisens/TV3WS](https://github.com/multisens/TV3WS) | Implementação dos TV 3.0 WebServices (Anexo C), menos a C.6.8 e a C.6.7.8/C.6.7.9, que a borda responde: emissão do JWT, usuários (Redis, só leitura dos perfis), serviços e dispositivos. TypeScript, portas internas **44652/44653**, com acesso pela borda |
| `infra/` | [multisens/Infra](https://github.com/multisens/Infra) | Redis, a borda KrakenD (`edgegateway`), Mosquitto + plugin C e os dockerfiles |
| `bcast/` | [multisens/BcastService](https://github.com/multisens/BcastService) | Simula o broadcaster: streaming via FFmpeg, sinalização por MQTT e hospedagem das apps de serviço |

O `.gitmodules` contém só esses quatro. `eduplay`, `sepe` (se-presentation-engine) e `TV30-Utils` são repositórios relacionados, mas não são submódulos deste repositório.

---

## Containers e portas

Seis containers contínuos (`redis` a `bcast`) e três tarefas únicas de subida. Com o override `docker-compose.ssdp.yml`, a borda roda em rede do host e tem um processo a mais, o anunciante SSDP.

| Container | Porta(s) no host | Descrição |
|-----------|----------|-----------|
| `redis` | 6379 (sem senha); commander em porta dinâmica (`docker port redis 18081`), com login | Redis, com carga inicial e o redis-commander embutido para debug |
| `mqtt-broker` (serviço `mosquitto`) | 1883, `${MQTT_WS_PORT:-9001}` | Mosquitto + plugin C de validação de esquema |
| `edgegateway` | 44642, 44643; docs em porta dinâmica (`docker port edgegateway 8085`). Com o override `docker-compose.ssdp.yml`: rede do host, com 44642, 44643 e 8085 (fixa) direto no host e UDP 1900 | Borda única. Contém os dois processos KrakenD (superfícies interna e externa), com o plugin `tv30-auth`, que valida as credenciais e responde a C.6.8 e a C.6.7.8/C.6.7.9, e a documentação Swagger; com o override (só Linux nativo), também o anunciante SSDP (`ssdp-announcer`). Morre-inteiro: se um processo cai, o container cai, inclusive o anunciante (decisão do Luís, 09/10), e o `restart` o traz de volta. Desde 10/10 (decisão do Luís), o anunciante só sai por erro de configuração; sem rede, ele espera e tenta de novo |
| `tv3ws` | 45000–45199 (WebSockets de remote-device) | TV 3.0 WebServices. As portas 44652/44653 ficam só na `ginga_net`; com o override, são publicadas também em `127.0.0.1`, para a borda |
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
| Estado de usuários em Redis | `userData.json` serve só de carga inicial, no banco vazio. Os perfis têm um dono, a plataforma (AoP): o P5 ("um dono por família de chave") foi aplicado na rodada da reunião de 05/10 com o Joel (D-0510-5), e o tv3ws deixou de re-sincronizar a partir do arquivo |
| Apps de serviço como módulos do bcast | Um único container serve todas, sem duplicar MQTT e CORS |
| Borda única com duas superfícies (fase 2) | A interna fica na 44642, fixa pela C.3.4, e a externa na 44643. Credenciais validadas na borda (decisão de 28/09, plugin `tv30-auth`). Na reunião de 05/10, o Joel decidiu que o tv3ws fica "anônimo", sem validar credencial (D-0510-1), e que a borda responde a C.6.8 (D-0510-2) e a C.6.7.8/C.6.7.9 (D-0510-3). As três foram feitas. Sem TLS na borda, o 106 por protocolo ao não local (C.4.1.6) ficou sem quem o aplique (lacuna L3) |
| A borda anuncia o SSDP, em rede do host (L6, opção A; decidido pelo Luís em 09/10) | O multicast do anúncio não saiu da bridge do Docker para a rede (medido no WSL2 em 02/10), então quem anuncia tem de estar na rede do host. Com o override `docker-compose.ssdp.yml`, a borda vai para a rede do host e alcança o tv3ws por `127.0.0.1`; um erro de configuração do SSDP derruba a borda inteira, e a falta de rede não (morre-inteiro decidido pelo Luís em 09/10, revisto por ele em 10/10). Substituiu a opção B (decidida em 04/10, informado pelo Luís): um container próprio para o anúncio, `tv3ws-ssdp`, com a borda e o tv3ws na `ginga_net`, em que a falha do SSDP não derrubava as APIs. A C.3.4 não diz onde o anunciante roda; é decisão do projeto |
| Avatares como SVG inline | Dispensa servir arquivos PNG. Ficam no campo `avatar` do hash do usuário |

---

## CI/CD

Cada submódulo (aop, bcast, tv3ws, infra) tem um workflow `.github/workflows/bump-tv30-pointer.yml`. Ele dispara a cada push na `main` e atualiza automaticamente o ponteiro do submódulo no repositório TV30, usando o PAT `TV30_REPO_TOKEN`.

Cada submódulo também faz build e push da própria imagem Docker no Docker Hub (`labmultisens/tv30-<componente>`).
