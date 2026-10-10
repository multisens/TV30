# Template: componente novo no TV30

Pedido das reuniões de 21/09 e 28/09: quem cria um componente novo precisa saber como montar o compose dele e como rodar o mesmo componente fora do Docker enquanto desenvolve. Este diretório traz o modelo de compose ([`docker-compose.yml`](./docker-compose.yml)), um componente de exemplo que sobe com ele e as regras. O passo a passo do desenvolvimento no host está em [`docs/dev-local.md`](../../docs/dev-local.md).

> Mensageria (MQTT), borda (KrakenD) e armazenamento (Redis) são decisões de implementação deste testbed, não exigências da ABNT NBR 25608. O template segue essas decisões; não é requisito da norma.

## O que vem na pasta

| Arquivo | Papel |
|---|---|
| `docker-compose.yml` | O modelo: rede, nomes de serviço, restart, `init`, healthcheck e portas, com o porquê de cada escolha em comentário. |
| `Dockerfile`, `index.js`, `package.json` | Componente de **exemplo**, executável como veio. Um processo Node só com a biblioteca padrão (sem `npm install`), que dá `PING` e lê a chave `tv30:<nome>:exemplo` no Redis, assina `tv30/<nome>/exemplo/ping` no broker e responde em `tv30/<nome>/exemplo/pong` com o valor da chave. Expõe `GET /health` na 8090 e sai com erro se perder o Redis ou o broker. Troque pelo código do seu componente; um componente real usa as bibliotecas do projeto (`mqtt`, `ioredis`), como o tv3ws. |
| `package-lock.json` | Lockfile sem dependências. Existe para que `npm ci` funcione nesta pasta, como funciona num componente real e como o `scripts/test-dev-host.sh` faz no host. Ao trocar o nome do componente, troque aqui também. |

Para conferir o template de ponta a ponta, rode `scripts/test-template.sh` com a stack de pé. O teste copia esta pasta para um diretório temporário, troca o nome do componente, sobe o exemplo e confere:

- que o container entrou só na `ginga_net`;
- que o exemplo falou com o `redis` e com o `mosquitto` pelo nome do serviço: uma mensagem de ping por MQTT volta com o valor que o teste gravou no Redis;
- que o `/health` responde pela porta publicada;
- a regra morre-inteiro: matar o processo do componente derruba o container, e o `restart` o traz de volta respondendo.

No fim, o teste remove o container, a imagem e a chave de teste.

## Como usar

1. Copie a pasta para o lugar do componente e troque `meu-componente`, a porta `8090` e as variáveis.
2. Suba a stack da raiz antes (`docker compose up -d`). É ela que cria a rede `ginga_net`, os serviços `redis` e `mosquitto` e a borda.
3. Suba o componente:

   ```bash
   docker compose --env-file <raiz-do-TV30>/.env -f <pasta-do-componente>/docker-compose.yml up -d --build
   ```

   O `--env-file` faz o `.env` da raiz valer na interpolação. Sem ele, o Compose lê o `.env` da pasta do componente (o diretório do projeto é o do primeiro `-f`), e um `JWT_SECRET` ou `DOCKERHUB_NS` definido na raiz não chega ao componente.

O componente fica num projeto compose próprio (`name: tv30-meu-componente`). O `docker compose down` da raiz não o derruba, e o dele não derruba a stack.

Se o componente for passar a fazer parte da stack, cole o bloco do serviço no `docker-compose.yml` da raiz, sem o bloco `networks:` do fim, que lá já existe.

## Regras

| Regra | Por quê |
|---|---|
| Entra na `ginga_net` **externa** | A rede é criada pela infra (`infra/docker-compose.yml`). O componente se junta a ela em vez de criar outra. |
| MQTT e Redis **pelo nome do serviço**: `MQTT_HOST=mosquitto`, `REDIS_HOST=redis` | Dentro do container, `localhost` é o próprio container. |
| `extra_hosts: host.docker.internal:host-gateway` | Faz `host.docker.internal` resolver também em Linux, para alcançar um processo rodando no host. Sem uso, é inócuo. |
| `restart: unless-stopped` e **morre-inteiro** | Se um processo do componente cair, o container inteiro cai e o Docker religa. Nenhuma parte morre em silêncio. Com mais de um processo, use um supervisor no modelo de `infra/edgegateway/entrypoint.sh`. |
| `init: true` | O init mínimo do Docker fica como PID 1 e o processo do componente como filho. O `SIGTERM` do `docker stop` chega ao processo (o Node como PID 1 o ignoraria e esperaria o `SIGKILL`). Se o processo morrer, o init sai junto, e o container cai como a regra anterior exige. |
| Publicar só a porta que um cliente fora do Docker usa | Clientes das APIs da norma acessam a **borda** (44642, porta fixa da C.3.4, e 44643), não a implementação interna. |
| Tolerar dependência ainda subindo | O `depends_on` não alcança serviços de outro projeto compose. Tente de novo ou saia com erro e deixe o `restart` religar. |
| Componente novo **não valida credencial** | Decisão de 28/09 (D1): access token e bind-token são validados só na borda (plugin `tv30-auth`). Uma rota nova da norma entra em `infra/edgegateway/routes.json`, com `auth` e `classes`. |
| Mesmo `JWT_SECRET`/`JWT_ISSUER` do tv3ws e da borda, só se o componente **emitir** accessToken | A borda valida o token que o tv3ws assina, e os dois leem o `.env` da raiz, com o padrão `tv30-dev-secret-nao-usar-em-producao` / `GenericIssuer`. Outro emissor de token além do tv3ws é caso a confirmar com o Joel. |
| `clientId` MQTT fixo só se houver uma única instância | O broker derruba a conexão anterior quando chega outra com o mesmo `clientId`. Por isso o mesmo módulo não pode rodar no host e em container ao mesmo tempo (vale para `tv3ws-client`, `aop-core` e `bcast_svc`). |

## O mesmo componente rodando no host

Enquanto desenvolve, rode o processo direto no host e deixe a infra em containers. O host fala com os containers pelas **portas publicadas**:

| Destino | Do host | De dentro de um container |
|---|---|---|
| Redis | `127.0.0.1:6379` | `redis:6379` |
| MQTT | `127.0.0.1:1883` | `mosquitto:1883` |
| Borda (superfície interna) | `127.0.0.1:44642` | `edgegateway:44642` |
| Processo no host | — | `host.docker.internal:<porta>` (requer o `extra_hosts`) |

```bash
# pare o container do componente antes (mesma porta, mesmo clientId MQTT)
docker compose -f <pasta-do-componente>/docker-compose.yml stop
cd <pasta-do-componente> && npm ci
MQTT_HOST=127.0.0.1 REDIS_HOST=127.0.0.1 REDIS_PORT=6379 PORT=8090 npm run dev
```

No exemplo, o `npm ci` não instala nada (não há dependências) e o `npm run dev` é `node --watch index.js`: o processo reinicia a cada mudança no arquivo. Se o processo sair com erro, o `node --watch` fica esperando a próxima mudança em vez de encerrar.

Se um container precisar chamar o componente no host, configure nele `http://host.docker.internal:8090` e garanta o `extra_hosts` nesse container.

O cenário 5 de `scripts/test-dev-host.sh` automatiza isso com este exemplo (pedido da reunião de 05/10 com o Joel). Ele sobe só o Redis e o broker, para a borda, roda o exemplo no host com `npm ci && npm run dev` e confere:

- o `/health` na 8090;
- os logs de conexão com `127.0.0.1:6379` e `127.0.0.1:1883`;
- um ping por MQTT que volta com o valor que o teste acabou de gravar no Redis;
- que, sem o processo do host, o ping fica sem resposta.

No fim, restaura a stack. Para outro componente, siga o mesmo padrão: subir só o necessário, parar o container do módulo, rodar o módulo real no host, conferir host → Redis (PING), host → MQTT (pub/sub) e o caminho específico, e no fim restaurar a stack. Detalhes em [`docs/dev-local.md`](../../docs/dev-local.md).

**Fora do escopo:** Windows nativo (processo no PowerShell com o Docker no WSL). Nesse arranjo, o `host-gateway` aponta para a VM do WSL, não para o Windows.
