---
title: Como testar
description: Que teste rodar para cada parte que você mudou, os testes de unidade e as suítes contra a stack.
---

O testbed tem dois tipos de teste:

- **Testes de unidade**, na pasta de cada parte, sem a stack. Levam segundos.
- **Suítes de `scripts/`**, contra a stack de pé, em Linux, no WSL2 ou no macOS. Conferem as partes
  juntas, e algumas mudam a stack enquanto rodam.

## Mexeu em quê, rode o quê

| Mudou | Rode |
|---|---|
| tv3ws | `npm test` e `npx tsc --noEmit` no `tv3ws`; nas APIs ou nas credenciais, também `test-auth.sh`; nos dispositivos remotos, `test-remote-device-v100.sh` |
| Casca (aop) | `npm test` no `aop` |
| bcast | `npx tsc --noEmit` no `bcast`; na parada, `test-bcast-shutdown.sh` |
| Rotas da borda (`routes.json`) | `node --test generate.test.js` e `test-auth.sh` |
| Plugin de credenciais da borda | os testes Go do `plugin/` e `test-auth.sh` |
| Anunciante da descoberta | os testes Go do `ssdp/` |
| Esquema ou funções do Redis | `bash infra/redis/test/run.sh all` e `test-edge-redis.sh` |
| Plugin do broker ou esquema de tópico | `docker compose build mosquitto`, os dois testes do plugin e `test-broker-smoke.sh` |
| Modelo de componente | `test-template.sh` |
| Compose, subida, ou a conversa entre módulos | `test-dev-host.sh` e `test-virgin-up.sh` |

Para testar o código do clone, e não as imagens publicadas, suba a stack com
`docker compose up -d --build`.

## Resumo

| Teste | Stack | Tempo |
|---|---|---|
| tv3ws: `npm test`, `npx tsc --noEmit` | não | de 25 a 38 s, 7 s |
| aop: `npm test` | não | de 7 a 11 s |
| bcast: `npx tsc --noEmit` | não | 8 s |
| borda: `node --test generate.test.js` | não | 1 s |
| borda e anunciante: testes Go | não (Docker) | 15 s e 7 s |
| Redis: `run.sh all` | não (Docker, containers descartáveis) | — |
| broker: testes do plugin | não (Docker, broker descartável) | cerca de 30 s |
| `test-auth.sh` | de pé; recria a borda | 1,5 min |
| `test-remote-device-v100.sh` | de pé | — |
| `test-dev-host.sh` | sobe e desce o que precisa | 3 min |
| `test-template.sh` | de pé | 30 s |
| `test-edge-redis.sh` | derruba e sobe | 1 min |
| `test-broker-smoke.sh` | sobe | 20 s |
| `test-bcast-shutdown.sh` | de pé; para o bcast | 25 s |
| `test-virgin-up.sh` | derruba e sobe do zero | — |

## Testes de unidade

Na pasta de cada módulo, depois do `npm ci`. Dublês fazem o papel do Redis, do broker e do bcast.

```bash
cd tv3ws && npm test && npx tsc --noEmit   # os 17 arquivos de test/
cd aop && npm test
cd bcast && npx tsc --noEmit               # o bcast não tem teste de unidade
```

### Borda e anunciante

O gerador das rotas tem testes em JavaScript, sem dependências:

```bash
cd infra/edgegateway && node --test generate.test.js
```

O plugin de credenciais e o anunciante são Go. Rode os testes no compilador da imagem da borda, na
raiz do clone:

```bash
GO_IMG=krakend/builder:2.7.2      # Apple Silicon: golang:1.22.7-alpine3.19
docker run --rm -v "$PWD/infra/edgegateway/plugin:/src" -w /src $GO_IMG \
  sh -c 'go vet ./... && go test -count=1 ./...'
docker run --rm -v "$PWD/infra/edgegateway/ssdp:/src" -w /src $GO_IMG \
  sh -c 'go vet ./... && go test -count=1 ./...'
```

Os testes do plugin e do gerador também rodam no build da imagem da borda:
`docker compose build edgegateway` falha se um deles falhar.

### Redis

Os testes sobem containers descartáveis e não tocam o Redis da stack.

```bash
bash infra/redis/test/run.sh all   # ou um modo: static, functions, contract, image
```

| Modo | O que confere |
|---|---|
| `static` | Nenhum serviço grava no Redis por fora das funções do esquema |
| `functions` (o padrão, sem argumento) | Cada função aceita o que o esquema permite e recusa, sem gravar nada, cada violação |
| `contract` | O tv3ws, a casca e a borda de verdade contra as funções |
| `image` | O build da imagem do Redis, a carga inicial e o healthcheck |

### Broker

Os testes de unidade do plugin rodam no build da imagem: `docker compose build mosquitto` falha se
um deles falhar. Os de integração sobem um broker descartável:

```bash
bash infra/mqtt-broker/plugin/tests/test_errors_json.sh       # a mensagem de errors/<client_id>
bash infra/mqtt-broker/plugin/tests/test_all_validations.sh   # uma publicação válida e 19 violações
```

`IMG=<imagem> NOBUILD=1` usa uma imagem já construída. Para medir o tempo de resposta do broker com
vários clientes, há `infra/mqtt-broker/brokertimetest/`
([Mensageria (MQTT)](../mensageria/#teste-de-latência)).

## Suítes de `scripts/`

Rode da raiz do clone, com a stack de pé e o `.env` copiado do `.env.example`. No WSL, com o Docker
dentro dele: `wsl.exe -u root bash /mnt/<caminho do clone>/scripts/<script>.sh`.

As que imprimem PASS/FAIL saem com código diferente de zero se algo falhar. As outras só mostram o
que observaram, e a saída tem de ser lida.

### `test-auth.sh`: credenciais na borda

```bash
bash scripts/test-auth.sh
```

- **Confere:** a decisão de credencial nas duas superfícies, em `warn` e em `enforce`. Isso cobre os
  códigos de erro, o 106 por superfície e classe de cliente, o CORS, a versão, o bind-token (C.6.8),
  o pareamento real do cliente não local, o cliente associado de verdade (com a casca e o bcast) e o
  Redis ou o tv3ws parado.
- **Mexe:** recria a borda, congela e para por alguns segundos o tv3ws e o Redis, grava chaves de
  teste e publica retidos. No fim, também com Ctrl+C, desfaz tudo e exige a auditoria do Redis vazia.
- **Precisa:** `edgegateway`, `tv3ws`, `redis` e `mqtt-broker` de pé. Sem a casca em
  `localhost:8080`, pula os casos do cliente associado.
- **Passa:** `== resultado: N PASS, 0 FAIL ==`.

### `test-remote-device-v100.sh`: dispositivos remotos na 100.0

```bash
bash scripts/test-remote-device-v100.sh
```

- **Confere:** dispositivos da 2.0 e da 100.0 registrados e conectados ao mesmo tempo, pela borda:
  - cada versão lista só os seus registros, e o *handle* de uma dá 305 na outra;
  - a atualização e a remoção do próprio registro;
  - o par de comunicação da 100.0 e a mensagem nos dois sentidos;
  - o bloqueio do cliente, que fecha o par com 4002 e remove os registros dele nas duas versões.
- **Mexe:** autoriza um cliente de teste em `clients:authorized` e, no fim, o remove com os
  dispositivos que registrou.
- **Precisa:** `edgegateway`, `tv3ws` e `redis` de pé, e Node 22 ou mais novo no computador.
- **Passa:** PASS em todos os casos.

### `test-dev-host.sh`: módulos rodando no host

```bash
./scripts/test-dev-host.sh               # cenários 1 a 5
./scripts/test-dev-host.sh --cenario 2   # um só
```

- **Confere:** as combinações de
  [Desenvolvimento com serviço no host](../dev-local/#o-teste-automatizado), com o módulo real fora
  do Docker. Em cada uma, a conversa com o Redis e o broker, o caminho próprio do cenário e uma prova
  negativa: o módulo é morto, e o caminho para de responder.
- **Mexe:** para os containers dos módulos que vão para o host e recria a borda na variante certa.
  No fim, restaura a stack padrão, ou a derruba se nada estava de pé.
- **Precisa:** bash 4 (no macOS, `brew install bash`).
- **Passa:** `RESUMO (N PASS, 0 FAIL)`. Nos cenários 1 e 4, a linha `X-TV30-Auth-Warn com token
  valido` mostra `107`, e isso é esperado.

### `test-template.sh`: o modelo de componente

```bash
bash scripts/test-template.sh
```

- **Confere:** copia e renomeia o modelo, sobe o exemplo e confere a rede, a conversa com o Redis e
  o broker, o `/health` e que o container cai inteiro e volta quando o processo morre.
- **Mexe:** nada na stack. No fim, remove o que criou.
- **Passa:** PASS em todas as verificações.

### `test-edge-redis.sh`: borda e Redis

```bash
bash scripts/test-edge-redis.sh
```

- **Confere:** depois de subir do zero, mostra o healthcheck do Redis, a versão das funções, a
  auditoria, o login do Redis Commander, as duas superfícies, uma rota declarada contra um caminho
  não declarado e que a borda e o Redis caem inteiros e voltam.
- **Mexe:** **derruba a stack e a sobe de novo.**
- **Passa:** a saída tem de ser lida.

### `test-broker-smoke.sh`: broker e casca

```bash
bash scripts/test-broker-smoke.sh
```

- **Confere:** o plugin do broker carregado, uma mensagem inválida recusada e uma válida aceita, e
  duas páginas da casca respondendo 200.
- **Mexe:** sobe a stack, se não estiver de pé.
- **Passa:** a saída tem de ser lida.

### `test-bcast-shutdown.sh`: parada do bcast

```bash
bash scripts/test-bcast-shutdown.sh
```

- **Confere:** o bcast para bem antes do prazo de 10 s e limpa os tópicos retidos que publicou.
- **Mexe:** para o bcast e o religa.
- **Passa:** a saída tem de ser lida.

### `test-virgin-up.sh`: máquina nova

```bash
bash scripts/test-virgin-up.sh
```

- **Confere:** a stack sobe com um só comando numa máquina sem `tv3ws/.env` e sem `user-files/`.
  Mostra os logs da subida.
- **Mexe:** **derruba a stack e a sobe do zero.** No fim, também com erro, devolve o `tv3ws/.env` e
  o conteúdo de `user-files/`, e recria o tv3ws e a casca.
- **Passa:** a saída tem de ser lida.
