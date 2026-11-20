---
title: Desenvolvimento com serviço no host
description: Rodar o tv3ws ou a casca fora do Docker, com npm run dev, e o resto da stack em containers.
---

Para mudar o código de um módulo sem reconstruir a imagem a cada vez, rode-o no computador com
`npm run dev` e deixe o resto da stack em containers. O processo reinicia a cada arquivo salvo. Vale
para o tv3ws e a casca; o `aop-cc` e o `bcast-sim` rodam só em container, porque o compose fixa o
endereço por que os outros containers os alcançam (`aop-cc:8081`, `bcast-sim:8082`).

Para um componente novo, o caminho é outro e mais curto:
[Estender o testbed com um componente](../estender-com-componente/#desenvolver-sem-reconstruir-a-imagem).

## Quem fala com quem

| De | Para | Endereço |
|---|---|---|
| Módulo no host | Container | `127.0.0.1:<porta no host>`: 6379 (Redis), 1883 (broker), 44642 e 44643 (borda), 8080 (casca). As demais, `docker compose port <serviço> <porta>` |
| Container | Módulo no host | `host.docker.internal`, que só a borda, a casca e o `aop-cc` resolvem no Linux (`extra_hosts` do compose) |
| Cliente das APIs | tv3ws | Sempre pela borda. O tv3ws no host escuta só na própria máquina (`TV3WS_LISTEN_HOST` muda) |

**Pare o container do módulo antes de rodá-lo no host.** Os dois disputariam a mesma porta e o
mesmo `clientId` do broker, que derruba a conexão anterior.

## Onde a borda procura o tv3ws

| `EDGE_VARIANT` | 44642 → | 44643 → | Quando |
|---|---|---|---|
| `linux` (padrão) | `tv3ws:44652` | `tv3ws:44653` | o tv3ws em container |
| `windows` | `host.docker.internal:44654` | `host.docker.internal:44655` | o tv3ws no host, também no Linux |

Com o tv3ws em container e a borda em `windows`, ou o contrário, a borda fica sem destino.

## Os comandos

Na raiz do clone. Sem o `.env` copiado do `.env.example`, ponha antes de cada `docker compose`
o `$P` abaixo, que liga os perfis:

```bash
P="--profile mqtt --profile linux"
```

### tv3ws no host

```bash
docker compose $P stop tv3ws
EDGE_VARIANT=windows docker compose $P up -d redis mqtt-broker edgegateway userfiles-seed aop-shell aop-cc bcast-sim
cd tv3ws && npm ci
MQTT_HOST=127.0.0.1 REDIS_HOST=127.0.0.1 REDIS_PORT=6379 \
HTTP_PORT=44654 HTTPS_PORT=44655 \
OBJECT_PROXY_URL=http://127.0.0.1:8081/ APPS_DOMAIN=apps.localhost \
JWT_SECRET=tv30-dev-secret-nao-usar-em-producao JWT_ISSUER=GenericIssuer \
USER_THUMBS="$PWD/../user-files/thumbs" TV30_TLS_DIR=../.tv30/tls \
SERVER_URL=localhost WS_PORT_MIN=45000 WS_PORT_MAX=45199 \
LISTEN_ATTEMPTS=10 MAX_REGISTRATIONS=32 PING_INTERVAL_MS=15000 LOG_LEVEL=INFO \
npm run dev
```

- `HTTP_PORT` e `HTTPS_PORT` têm de ser 44654 e 44655, as da variante `windows`. As 44642 e 44643 são
  da borda.
- `JWT_SECRET` e `JWT_ISSUER` têm de ser os da borda: os do `.env` da raiz, ou os padrões acima.
- `TV30_TLS_DIR` liga o HTTPS na 44655. Sem ele, a 44643 da borda fica sem destino, e o ponto de
  entrada do dispositivo remoto sai em `ws://`.

### Casca (aop-shell) no host

```bash
docker compose $P stop aop-shell
EDGE_VARIANT=linux docker compose $P up -d redis mqtt-broker edgegateway userfiles-seed tv3ws aop-cc bcast-sim
WS=$(docker compose $P port mqtt-broker 9001 | sed 's/.*://')
cd aop-shell && npm ci
PORT=8080 MQTT_HOST=127.0.0.1 MQTT_WS_PORT="$WS" REDIS_HOST=127.0.0.1 REDIS_PORT=6379 \
USER_DATA_PATH="$PWD/../user-files" npm run dev
```

- `MQTT_WS_PORT` é a porta em que o Docker publicou a 9001 do broker: a casca repassa a ela o
  `/mqtt` da página da TV. Errada, o `/mqtt` responde 502. Ela muda quando o container do broker é
  recriado; `MQTT_WS_PUBLISH` no `.env` a fixa.
- A casca no host segue os padrões de `APPS_DOMAIN` (`apps.localhost`) e de
  `OBJECT_PROXY_PUBLIC_PORT` (8081), os mesmos do `aop-cc`; mudou um deles no `.env`, passe o mesmo
  valor à casca.

### Os dois no host

Só a infraestrutura, o `aop-cc` e o `bcast-sim` em containers, com a borda em `windows`:

```bash
docker compose $P stop tv3ws aop-shell
EDGE_VARIANT=windows docker compose $P up -d redis mqtt-broker edgegateway userfiles-seed aop-cc bcast-sim
```

Depois, um terminal para cada módulo: o tv3ws e a casca, como acima.

### Voltar à stack padrão

```bash
EDGE_VARIANT=linux docker compose $P up -d
```

Ou `./tv30 up`, que também sobe o anunciante da descoberta na rede.

## Variáveis que cada módulo exige

Falta de variável obrigatória encerra o módulo na partida.

:::caution[O módulo morre, e o `npm run dev` fica de pé]
Sob `npm run dev`, o `nodemon` continua de pé (`app crashed - waiting for file changes before
starting...`) e só tenta de novo quando um arquivo muda. Confira o terminal antes de concluir que o
módulo está no ar.
:::

| Módulo | Obrigatórias | Também no host |
|---|---|---|
| tv3ws | `MQTT_HOST`, `REDIS_HOST`, `JWT_SECRET`, `JWT_ISSUER`, `USER_THUMBS`, `HTTP_PORT`, `HTTPS_PORT`, `WS_PORT_MIN`, `WS_PORT_MAX`, `LISTEN_ATTEMPTS`, `MAX_REGISTRATIONS`, `PING_INTERVAL_MS`, `OBJECT_PROXY_URL`, `APPS_DOMAIN` | `SERVER_URL`, sem a qual os endereços de dispositivo remoto saem com `undefined`. `WS_PORT_MIN` e `WS_PORT_MAX` na faixa 45000–45199, que não colide com as outras portas |
| aop-shell | `MQTT_HOST`, `USER_DATA_PATH`, `REDIS_HOST` | `PORT` (8080) e `MQTT_WS_PORT`. `MQTT_HOST` é só o nome ou IP do broker, sem porta |

Os dois módulos também leem um `.env` na própria pasta. A variável definida no shell vence.

## O teste automatizado

`scripts/test-dev-host.sh` roda cada combinação com o módulo real e confere que ele fala com o Redis,
com o broker e com quem depende dele.

```bash
./scripts/test-dev-host.sh               # cenários 1 a 5, em ordem
./scripts/test-dev-host.sh --cenario 2   # um só, ou uma lista: 1,3
./scripts/test-dev-host.sh --build       # reconstrói as imagens antes
```

| # | No host | Borda |
|---|---|---|
| 1 | tv3ws | `windows` |
| 2 | casca | `linux` |
| 3 | bcast | `linux` |
| 4 | tv3ws, casca e bcast | `windows` |
| 5 | o componente de exemplo do modelo | parada |

- O script precisa do bash 4. No macOS, `brew install bash` e
  `/opt/homebrew/bin/bash scripts/test-dev-host.sh`.
- Sem Node no Linux, ele roda o módulo num container `node` com a rede do host
  (`DEVHOST_MODO=docker`).
- No fim, ele restaura a stack padrão, se ela estava de pé, ou a derruba.
- O que cada cenário confere está em [Como testar](../como-testar/).

## Limites

- **Windows fora do WSL não é coberto.** Rode o módulo dentro do WSL. Para a casca no Windows, com a
  stack no WSL, fixe a porta do broker: `MQTT_WS_PUBLISH=9003:9001` no `.env` da raiz e
  `MQTT_WS_PORT=9003` no `aop-shell/.env`. A 9003 evita a 9001 e a 9002, que o Hyper-V ocupa em algumas
  máquinas.
- **Docker Desktop** não foi testado.
- **Aplicações de emissora só na própria máquina.** Elas abrem em `*.apps.localhost`, que só resolve
  na máquina de quem abre a tela. De outra máquina, use `APPS_DOMAIN`
  ([Instalação](../instalacao/#variáveis-do-env)).
