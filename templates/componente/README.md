# Template: componente novo no TV30

Pedido das reuniões de 21/09 e 28/09: quem cria um componente novo precisa saber como montar o compose dele e como rodar o mesmo componente fora do Docker enquanto desenvolve. Este diretório traz o modelo de compose ([`docker-compose.yml`](./docker-compose.yml)) e as regras. O passo a passo do desenvolvimento no host está em [`docs/dev-local.md`](../../docs/dev-local.md).

> Mensageria (MQTT), borda (KrakenD) e armazenamento (Redis) são decisões de implementação deste testbed, não exigências da ABNT NBR 25608. O template segue essas decisões; não é requisito da norma.

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
cd <pasta-do-componente>
MQTT_HOST=127.0.0.1 REDIS_HOST=127.0.0.1 REDIS_PORT=6379 PORT=8090 npm run dev
```

Se um container precisar chamar o componente no host, configure nele `http://host.docker.internal:8090` e garanta o `extra_hosts` nesse container.

Para automatizar a verificação, use o padrão de `scripts/test-dev-host.sh`: subir só o necessário, parar o container do módulo, rodar o módulo real no host, conferir host → Redis (PING), host → MQTT (pub/sub) e o caminho específico, e no fim restaurar a stack.

**Fora do escopo:** Windows nativo (processo no PowerShell com o Docker no WSL). Nesse arranjo, o `host-gateway` aponta para a VM do WSL, não para o Windows.
