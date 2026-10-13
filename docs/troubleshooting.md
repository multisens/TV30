---
title: Solução de problemas
nav_order: 5
---

# Troubleshooting

## Porta presa: `failed to bind host port ... address already in use`

Triagem, nesta ordem (caso real: portas 3000/3001 presas por um segundo
daemon Docker via snap):

```bash
# 1. quem esta com a porta?
sudo ss -ltnp | grep -E '3000|3001'

# 2. e um container deste daemon?
sudo docker ps -a --format '{% raw %}{{.Names}}\t{{.Ports}}{% endraw %}' | grep 3001
#    -> apareceu: remova-o (docker rm -f <nome>) ou faca down no projeto dono.

# 3. ss mostra docker-proxy mas o docker ps -a vem vazio?
#    Ha OUTRO daemon Docker na maquina (snap ou Docker Desktop):
ps -ef | grep dockerd | grep -v grep
#    -> dois dockerd = o dono da porta e o outro daemon.
#       snap:    sudo snap stop docker --disable  (ou snap remove --purge docker)
#       Desktop: docker context ls / encerrar o Desktop
#    -> snap ja removido mas o processo sobrevive orfao: sudo kill <pid do
#       dockerd com --data-root=/var/snap/...>

# 4. um daemon so e mesmo assim a porta persiste: docker-proxy orfao.
#    sudo kill -9 <pids dos docker-proxy do ss> e suba de novo.
```

**Nunca use `kill` no dockerd do sistema** (`/usr/bin/dockerd -H fd://`) —
o systemd o religa e o socket pode ficar dessincronizado
(`/var/run/docker.sock: no such file or directory`). Sempre:

```bash
sudo systemctl reset-failed docker.socket docker.service
sudo systemctl restart docker.socket docker.service
```

O one-shot `preflight` do compose imprime, antes da subida, quem está
segurando cada porta fixa que ele confere (lista abaixo). Se a subida falhar
por bind, a causa já está nomeada no início do log.

### Quais portas podem estar presas (C1, decisão do Luís em 11/10)

Só as portas **fixas** do host podem colidir com outro processo: a 44642 (norma, C.3.4), a 44643 da borda, a do AoP (8080, `AOP_PUBLIC_PORT`), a 1883, a 6379 e a faixa 45000–45199, que o compose publica inteira para o tv3ws; com o `docker-compose.ssdp.yml`, também a 8085 da borda, em rede do host. A 44643 é fixa por padrão também na bridge desde 12/10 (decisão do Luís, que revê a C1 nesse ponto; `EDGE_EXT_PUBLISH`, padrão `44643:44643`). O `preflight` confere a 44642 (bloqueia a subida se um processo nativo a ocupa) e avisa se a 1883, a 6379, a 44643 ou a do AoP estão ocupadas; no modo SSDP, também a 8085 e a 44652/44653 (`scripts/preflight.sh`, `PORTS_WARN`). A faixa 45000–45199 não entra na checagem.

As outras portas saem numa porta livre que o Docker escolhe, e não colidem: a 8081 do bcast, a 9001 (MQTT por WebSocket) do Mosquitto, a 8085 da documentação na bridge e a 18081 do redis-commander. Até 11/10, a 44643, a 8081 e a 9001 eram fixas, e daí vinha o conselho de trocar `MQTT_WS_PORT` para 9003 no Windows com o Hyper-V ocupando a 9001 e a 9002; de 11/10 a 12/10, a 44643 saía numa porta livre na bridge. Hoje a 9003 vale só como opção para quem roda o AoP fora do Docker no Windows (*AoP fora do Docker no Windows*, abaixo). Se você fixou uma das portas livres no `.env` (`BCAST_PUBLISH` ou `MQTT_WS_PUBLISH` com `host:container`), ela volta a poder colidir; `EDGE_EXT_PUBLISH=44643`, só o número, faz o contrário com a 44643, que passa a sair numa porta livre.

### Onde está a porta de um serviço

A porta escolhida pelo Docker pode mudar quando o container é recriado. Na raiz do clone:

```bash
docker compose ps                          # todas, na coluna PORTS
docker compose port edgegateway 44643      # superficie externa (44643, salvo EDGE_EXT_PUBLISH)
docker compose port bcast 8081             # bcast
docker compose port mosquitto 9001         # MQTT por WebSocket
docker port edgegateway 8085               # documentacao Swagger
docker port redis 18081                    # redis-commander
```

O `docker compose port` usa o nome do serviço (`mosquitto`, `edgegateway`); o `docker port`, o do container (`mqtt-broker`, `edgegateway`). A resposta vem como endereço e porta, por exemplo `0.0.0.0:32768` (o `docker port` pode trazer também a linha do IPv6, `[::]:32768`).

O `/manifest` (`Server-SecureBaseURL`, `tv3ws/src/ssdp-config.ts`) e o OpenAPI da superfície externa, na documentação Swagger (`servers: http://localhost:44643`, `infra/edgegateway/generate.js`), dizem 44643. Com o padrão (`EDGE_EXT_PUBLISH=44643:44643`, desde 12/10), essa é a porta de host da externa. Com `EDGE_EXT_PUBLISH=44643` (só o número), o Docker escolhe outra, e os dois deixam de valer. Com outra porta fixa (`X:44643`), defina também `EDGE_HTTPS_PORT=X` no `.env` da raiz, para o `/manifest` anunciá-la; o OpenAPI continua dizendo 44643. Depois de mudar o `.env`, recrie a borda e o tv3ws (`docker compose up -d edgegateway tv3ws`).

### `preflight`: "a porta 44642 esta ocupada (-)" com a stack de pé

Até 02/10/2026, um segundo `docker compose up -d` com a stack já de pé parava
no preflight com essa mensagem. O container do preflight não tem
`CAP_SYS_PTRACE`, então o `netstat` dele não enxerga que o dono da 44642 é o
`docker-proxy` e mostra `-`. O `scripts/preflight.sh` atual reconhece o
`docker-proxy` pela linha de comando. Em clone antigo, atualize o
repositório. Se a mensagem continuar, há um processo nativo na 44642:
confira com `sudo ss -ltnp | grep 44642`.

### `preflight`: "o anuncio SSDP esta ligado (docker-compose.ssdp.yml) e falta SSDP_ADVERTISE_HOST"

Desde 11/10 (B2, decisão do Luís), com o override `docker-compose.ssdp.yml` ligado, o `SSDP_ADVERTISE_HOST` é obrigatório. Sem ele, ou vazio, o `scripts/preflight.sh` sai com erro, e a borda, que depende dele, não sobe:

```
[preflight] ERRO: o anuncio SSDP esta ligado (docker-compose.ssdp.yml) e falta SSDP_ADVERTISE_HOST.
[preflight]       Defina no .env da raiz o IP (ou nome) desta maquina na rede, por exemplo
[preflight]       SSDP_ADVERTISE_HOST=192.168.0.23, e rode 'docker compose up -d' de novo.
```

Defina-o no `.env` da raiz (ou no `tv3ws/.env`; o da raiz prevalece). Um valor só exportado no shell não chega ao preflight nem à borda, que o leem dos mesmos arquivos de ambiente. Se a borda subisse sem ele (por exemplo, sem o preflight), o anunciante sairia com erro de configuração, e a borda cairia inteira, como nos outros erros de configuração da C8 (`docker logs edgegateway` mostra `[ssdp] FALHA em configuracao do anuncio (SSDP_ADVERTISE_HOST, EDGE_HTTP_PORT, EDGE_HTTPS_PORT)`). O `SERVER_URL` não serve mais de host do anúncio. Para desligar a descoberta, comente o `COMPOSE_FILE` no `.env`.

## Redis não fica saudável e o tv3ws ou a borda não sobem

O antigo container de carga `redis-seed`, que rodava `pip install redis` na partida e falhava sem rede, não existe mais. Desde a consolidação do armazenamento (fase 3), a carga inicial vem na própria imagem `tv30-redis`: o seed é gerado no build (estágio `seedgen` do `infra/redis/Dockerfile`, em Python só com a biblioteca padrão) e aplicado pelo `infra/redis/entrypoint.sh` com `redis-cli --pipe`. A partida não instala nada nem precisa de rede.

O healthcheck do `redis` só passa depois da carga (chave `seed:done`, testada a cada 2 s, até 30 vezes; `infra/redis/docker-compose.yml`). O `tv3ws` e o `edgegateway` dependem dele com `condition: service_healthy`; o broker não depende do Redis. Para ver em que ponto a carga está: `docker logs redis`, que registra `[redis] aplicando carga inicial pelas funcoes (redis-cli --pipe)...` e `[redis] carga concluida (<n> perfil(is))`, ou `[redis] carga ja aplicada (seed:done presente) — mantida`.

O seed sai do template `infra/user-files-template/userData.json` no build. Uma mudança no template só entra com a imagem reconstruída e, mesmo assim, só num volume `redis_data` que ainda não tenha `seed:done`: o entrypoint não reaplica a carga num volume já semeado.

Desde o P4 (decisão do Luís em 10/10), o healthcheck também exige que a biblioteca de funções `tv30` tenha carregado **nesta** partida (marca `/tmp/tv30-redis-pronto`, criada pelo entrypoint). No log aparece `[redis] biblioteca de funcoes tv30 carregada (esquema versao N)`. Se o log mostrar `ERRO: a biblioteca de funcoes tv30 NAO carregou`, o container encerra, porque sem as funções toda escrita dos serviços falharia. A causa é um `esquema.json` ou `funcoes.lua` quebrado numa imagem montada à mão: reconstrua a partir do repositório (`docker compose build redis`), já que o build confere a biblioteca. Se o log mostrar `ERRO: a carga inicial foi recusada pelo esquema`, um perfil do `userData.json` está fora do esquema: o log diz qual campo, `seed:done` não é gravado e o container fica *unhealthy*. Corrija o template e reconstrua a imagem.

## Erro `TV30ESQUEMA` numa resposta ou no log

```
TV30ESQUEMA tv30_perfil_grava: user:0b6e3c1a-7f2d-4e8b-9a5c-3d1f2e4a6b8c campo parentalControl: deve ser "true" ou "false" (veio "False")
```

É uma função do Redis recusando uma escrita fora do esquema (P4, decisão do Luís em 10/10). A mensagem diz a função, a chave, o campo e o motivo, e nada foi gravado. Para o serviço, é defeito de quem grava. O tv3ws e o AoP respondem 404 `{"error":200}` com a mensagem no `description` e no log (`[error] <método> <url>: TV30ESQUEMA ...`). A borda responde com `escrita recusada pelo esquema do Redis (...)`. Um handler MQTT só loga (no tv3ws, `[mqtt] FALHA no handler de <tópico>`).

- **Veio de uma escrita do código:** o serviço montou um dado que o esquema não aceita. Compare a mensagem com a regra no `infra/redis/esquema.json` (o campo `fonte` diz de onde ela veio) e corrija quem grava, não a regra. Mudar a regra é decisão e vai registrada.
- **Veio de um script ou de uma chamada à mão (`FCALL`):** os argumentos estão fora do esquema. Os formatos de cada função estão em `infra/redis/README.md`.
- **`ERR Function not found`:** o Redis está sem a biblioteca. Pode ser uma imagem anterior ao P4 ou um Redis que não é o da stack. Reconstrua com `docker compose build redis && docker compose up -d redis`.
- **`deve ser UUID no formato da RFC 9562` na criação de perfil:** desde 11/10 (F-3, decisão do Luís), o esquema exige o id do perfil em UUID, em minúsculas. Desde 12/10 (versão 3 do esquema, decisão do Luís), o UUID é estrito, e a mensagem diz qual parte falhou: `versao do UUID deve ser de 1 a 8`, `variante do UUID deve ser a da RFC 9562` (primeiro dígito do quarto grupo em `8`, `9`, `a` ou `b`), `UUID nulo` ou `UUID maximo` (`infra/redis/funcoes.lua`, `motivoUuid`). O AoP novo gera `crypto.randomUUID()` (versão 4, válido); um AoP de imagem anterior a 11/10 ainda gera `user_<epoch-ms>`, e a criação responde 404 `{"error":200}`. Reconstrua o AoP com o Redis (`docker compose build aop redis`). Num volume de antes, ver *Auditoria do Redis com achados*, abaixo.
- **`campo avatar: SVG em linha nao serve` na criação de perfil:** desde a G8 (decisão do Luís em 12/10, à noite; esquema na versão 4), o `avatar` é o nome de um arquivo do diretório de miniaturas (por exemplo, `c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10.svg`), e não o SVG. Um AoP de imagem anterior à G8 ainda grava o SVG em linha, e a criação responde 404 `{"error":200}`: reconstrua o AoP com o Redis (`docker compose build aop redis`). As outras recusas do mesmo campo dizem o que falhou: diretório no nome (`/` ou `\`), extensão fora de `.svg`, `.png`, `.jpg`, `.jpeg` e `.webp` (ou em maiúsculas), primeiro caractere que não é letra nem dígito, caractere fora de letras sem acento, dígitos, `.`, `_` e `-`, ou mais de 128 caracteres antes da extensão (`motivoNomeArquivo`, em `infra/redis/funcoes.lua`).

## Auditoria do Redis com achados

```bash
docker exec redis redis-cli FCALL_RO tv30_auditoria 0
```

Cada achado é `[chave, familia, motivo]`, e a auditoria vazia é o estado esperado. O `scripts/test-auth.sh` dá FAIL se ela não terminar vazia e avisa no começo se já havia achados antes da suíte. Causas comuns:

- **Volume de antes do P4.** A carga antiga gravava os booleanos como `"False"`/`"True"`, e o `lastAccess` avulso de antes de 05/10 deixava hashes `user:{id}` só com `lastAccess`, fora de `users:index` (por exemplo, `user:abc-123`). Para começar limpo, use `docker compose down -v`, que apaga o volume e com ele os perfis criados. A outra saída é corrigir ou apagar as chaves apontadas.
- **Volume de antes de 11/10 (F-3): `{id} da chave: deve ser UUID ...`.** O esquema exige o id do perfil em UUID desde a versão 2 (11/10), e em UUID estrito desde a versão 3 (12/10), sem compatibilidade com os ids antigos (decisões do Luís). Todo perfil criado antes de 11/10 (`user_<epoch-ms>`) e o da carga antiga (`c3167a18-5dc5`) aparecem em `users:index`, `user:{id}`, `user:{id}:consent` e `user:{id}:broadcaster-attrs:*`. A carga não roda de novo num volume já semeado (`seed:done`), então o perfil novo da carga (`c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10`) não entra. Saída: `docker compose down -v`, que apaga os perfis criados e também os retidos do broker. Um id que passou na versão 2 (de 11 a 12/10) sem ser UUID estrito aparece com o motivo da versão 3 (`versao do UUID ...`, `variante do UUID ...`, `UUID nulo` ou `UUID maximo`); os do AoP (`crypto.randomUUID()`) e o da carga atual passam. Para conferir a versão carregada: `docker exec redis redis-cli FCALL_RO tv30_versao 0` (tem de dar `4` desde a noite de 12/10, G8, e dava `3` de 12/10 até ali; `infra/redis/esquema.json`).
- **Volume de antes da G8 (12/10, à noite): `campo avatar: SVG em linha nao serve: ...`.** Desde a versão 4 do esquema, o `avatar` é o nome de um arquivo, e cada perfil gravado com o SVG em linha (os criados pelo AoP até a G8 e o da carga) aparece em `user:{id}`. A escolha do perfil, os atributos de emissora e o despejo continuam funcionando, e as telas mostram o avatar padrão para eles. O perfil da carga se conserta com `docker exec redis redis-cli HSET user:c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10 avatar c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10.svg`; o arquivo vem do template para `./user-files/thumbs` pelo `userfiles-seed` (se ainda não estiver lá, `docker compose up -d` o copia). Um perfil criado pelo AoP antes da G8 não tem arquivo: tire o campo (`docker exec redis redis-cli HDEL user:<id> avatar`, e as telas mostram o padrão) ou recrie o volume (`docker compose down -v`, que apaga os perfis criados e os retidos do broker).
- **Escrita à mão** pelo `redis-cli` ou pelo Redis Commander, que não passa pelas funções. Grave pela função (`FCALL <funcao> 0 ...`, exemplos em [Modelo de dados Redis](modelo-redis.md)) ou desfaça a escrita.
- **`chave sem familia no esquema`:** a chave tem um prefixo do alcance (`user:`, `session:`, `client:`...) mas não é de nenhuma família, como a antiga `user:{id}:profile`. Se ninguém a usa, apague.

## WSL2 + Docker

### `localhost:8080` dá timeout no Windows host

**Causa típica:** `~/.wslconfig` com `networkingMode=mirrored`. Mirrored + Docker tem problemas de NAT/iptables que impedem o host de alcançar as portas dos containers.

**Fix:**

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
```

Depois:

```powershell
wsl --shutdown
```

E reabra a distribuição. Verifique:

```powershell
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 8080 }
```

### Containers caem após período sem uso

**Causa:** WSL2 desligava a VM por idle timeout, derrubando os containers.

**Fix:** acrescente no `~/.wslconfig`:

```ini
vmIdleTimeout=86400000   # 24h
```

E mantenha um processo leve rodando no WSL (qualquer terminal aberto).

### AoP fora do Docker no Windows: porta do WebSocket do Mosquitto

O AoP rodando no Windows, fora do Docker (caso que o `scripts/test-dev-host.sh` não cobre; [Limites]({{ site.baseurl }}/dev-local#limites)), repassa o `/mqtt` da página da TV para `ws://${MQTT_HOST}:${MQTT_WS_PORT}`, e o `MQTT_WS_PORT` tem de ser a porta de host da 9001 do Mosquitto (`aop/src/mqtt-ws.js`). Por padrão, essa porta é escolhida pelo Docker e muda quando o container é recriado. Uma opção (dica do Luís em 12/10, não regra) é fixá-la na 9003, a porta que o `.env` usava até 11/10, quando o motivo registrado era a 9001 e a 9002 ocupadas pelo Hyper-V (detalhe em [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local#aop-fora-do-docker-no-windows-opção)):

- no `.env` da raiz: `MQTT_WS_PUBLISH=9003:9001`, e `docker compose up -d mosquitto`;
- no `aop/.env`: `MQTT_WS_PORT=9003`.

Sem a opção, use a porta do momento: `docker compose port mosquitto 9001`. Com o `MQTT_WS_PORT` errado, o `/mqtt` responde 502 (*A página da TV não conecta no MQTT*, abaixo).

### Portas não voltam após `docker compose down`

**Sintoma:** `localhost:XXXX` continua respondendo "connection reset" mesmo após os containers pararem.

**Fix:**

```powershell
wsl --shutdown
```

E suba a stack de novo.

---

## CRLF em scripts shell

### `exec /entrypoint.sh: no such file or directory`

**Causa:** o arquivo foi commitado com `\r\n` (CRLF). O shebang `#!/bin/sh\r` fica inválido.

**Fix:**

1. Converta o arquivo:
   ```bash
   dos2unix infra/dockerfiles/entrypoint-user-files.sh
   ```

2. Confira a regra de LF no `.gitattributes`. A raiz e o `infra/` já a têm (`*.sh text eol=lf`; no `infra/`, também `*.Dockerfile` e `Dockerfile`). O aop, o bcast e o tv3ws não têm `.gitattributes`; um script novo de container num deles precisa da mesma linha:
   ```
   *.sh   text eol=lf
   ```
   Um arquivo commitado com CRLF antes da regra continua assim no repositório até `git add --renormalize .` e um commit.

3. Rebuild a imagem.

---

## App de emissora não abre na camada gráfica, ou abre e não responde às teclas

Desde o P1.3 (decisão do Luís em 10/10), o AoP abre cada app de emissora num nome de host próprio, na porta dele. Desde 11/10 (decisão do Luís), a URL leva o prefixo do caminho antigo: `http://<rótulo>.apps.localhost:8080/graphicsAppProxy<bcastEntryPointUrl>` (`aop/src/app-hosts.js`). O `<rótulo>` sai do `appId` da BALD, fixo por app desde 11/10: o users-test, por exemplo, abre em `http://urn-tv30-app-users-test.apps.localhost:8080/graphicsAppProxy/users-test`. No host do próprio AoP, `/graphicsAppProxy/...` redireciona (302) para o host da app em execução. Para ver o endereço da app em execução, que é a origem gravada pelo AoP:

```bash
docker exec redis redis-cli HGETALL origins:associated
docker logs aop --tail 50 | grep '\[apps\]'
```

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| A app não carrega com a tela do AoP aberta de **outra máquina** | `*.localhost` resolve para a máquina de quem abre a página, e não para a do AoP | Defina `APPS_DOMAIN` no `.env` da raiz com um domínio resolvível na rede, com `*.<domínio>` apontando para a máquina do AoP (DNS curinga), e recrie o AoP (`docker compose up -d aop`) |
| A app não carrega, e o AoP está publicado noutra porta do host | A origem da app usa `AOP_PUBLIC_PORT` (padrão 8080), e não a porta pela qual o navegador chegou | Mude a porta pelo `AOP_PUBLIC_PORT` do `.env` da raiz, que troca a porta publicada e a origem juntas |
| `nenhuma aplicacao em execucao em <host>` (404) | Nenhuma app em execução tem esse rótulo: a app foi encerrada, ou trocada por outra, e a página antiga ficou aberta. Com o `appId` trocado no bcast (`EDUPLAY_APP_ID`, `UFF_APP_ID`, `USERS_TEST_APP_ID`, `WEBMEDIA_APP_ID`), o rótulo também muda. Até 11/10, o bcast sorteava o `appId` a cada partida, e o rótulo mudava a cada reinício dele | Abra a app de novo pelo catálogo do AoP |
| `nenhuma aplicacao em execucao na camada grafica` (404), em `/graphicsAppProxy/...` no host do AoP | Nenhuma app em execução para onde redirecionar | Abra a app pelo catálogo do AoP |
| `Bad Gateway: aplicacao fora do ar` (502) | O AoP não alcança o `bcastEntryPackageUrl` da app (bcast parado, ou `BCAST_HOSTNAME` errado no dev-host) | `docker logs aop` mostra a falha do proxy (`[apps] falha no proxy ...`); confira o bcast |
| O AoP não sobe: `[boot] APPS_DOMAIN invalido` ou `AOP_PUBLIC_PORT invalida` | Valor fora do formato (rótulos `[a-z0-9-]` separados por ponto; porta inteira de 1 a 65535) | Corrija o `.env` da raiz |
| A app abre, mas não recebe teclas, `timeupdate` nem `stream_event` | Com a app em outra origem, o AoP entrega os eventos por `postMessage`, e a app não inclui a ponte `bcast/public/js/aop-bridge.js`; ou a imagem do bcast é anterior a 10/10 | Inclua `<script src="js/aop-bridge.js"></script>` na app (ver `bcast/README.md`); reconstrua o bcast junto com o AoP |
| As chamadas da app às APIs levam `X-TV30-Auth-Warn: 107` (ou 106, nas rotas só do local associado, como `POST /tv3/bind-context`) | A origem da app não está em `origins:associated`: a app foi encerrada (ESC) ou trocada, e a página ficou aberta; ou a gravação no Redis falhou (log do AoP). Com uma imagem do AoP anterior a 11/10, a app aberta pelo caminho antigo `/graphicsAppProxy` ficava na origem do AoP, que não é gravada | Abra a app pelo AoP (catálogo e tela cheia); reconstrua o AoP se a imagem for anterior a 11/10 |

O QtWebEngine não foi testado com os nomes `*.apps.localhost`; o Firefox 154 (Linux) e o Chrome 154 (Windows) foram conferidos em 10/10.

## `POST` ou `DELETE /tv3/bind-context` dá 100 na 44643

É a regra da P1.9 (decisão do Luís em 10/10): a superfície externa (44643) só expõe as rotas que admitem o cliente não local, e essas duas são só do local associado. Use a superfície interna (44642). O `GET /tv3/bind-context` existe nas duas. Na 44643, a C.6.7.9 lista 17 APIs, e não 20, e a C.6.7.8 dá 101 para `tv3ws-bind-context-register`, `tv3ws-bind-context-remove` e, desde 12/10, `tv3ws-remotedevice-communication` (cada superfície lista só o que oferece; F-2, decisão do Luís em 11/10). Hoje, a interna tem 26 rotas e a externa, 21 (`infra/edgegateway/routes.json`, regra em `generate.js`).

## `GET /tv3/remote-device/devices/{classId}` ou `/tv3/remote-device/device/{handle}` dá 100 na 44643 ou 106 na 44642

Desde 12/10 (decisão do Luís), a C.6.15.5 é só do cliente local: a rota tem as `classes` `local-associated` e `local-autonomous` no `infra/edgegateway/routes.json`. Desde a tarde de 12/10 (segunda decisão do Luís), as rotas 2.1 `GET` e `DELETE /tv3/remote-device/device/{handle}` também, e o que segue vale para as três, menos a lista da C.6.7.9: as rotas 2.1 não têm API nela. Pela regra da P1.9, as três saem da 44643, onde respondem 404 `{"error":100}` nos dois modos, e a API da C.6.15.5, `tv3ws-remotedevice-communication`, sai da lista da C.6.7.9 ali. Na 44642, o cliente não local recebe o 106 da regra de classe da borda (`rota nao disponivel para ...`, `infra/edgegateway/plugin/handler.go`): em `enforce`, 404 `{"error":106}`; em `warn`, a requisição passa com `X-TV30-Auth-Warn: 106`. Chame-as de um cliente local, pela 44642.

O código exato ainda não está decidido: a Tabela C.78 (p. 339; p. 357 do PDF) pede 107 ao não local, e a C.4.1.8 (p. 206-207; p. 224-225 do PDF) fala em 106 para o não local que chama uma API de uso exclusivo do cliente local. Fica com o Joel, na F-1 ([Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes), seção F); se as rotas 2.1 entram nela é a G3 (*Achados de 12/10*, na mesma página).

## `POST /tv3/<scid>/users` dá 100

É a A4 (decisão do Luís em 11/10): `POST /tv3/{serviceContextId}/users` não existe na norma, que só define `POST /tv3/current-service/users` (C.6.14.1), e saiu da tabela de rotas (`infra/edgegateway/routes.json`). A borda responde 404 `{"error":100}` em qualquer scid, inclusive a constante do tv3ws e `Current-Service` com a caixa trocada, nas duas superfícies e nos dois modos. Use `POST /tv3/current-service/users`, com bind-token. As rotas `GET` e `POST /tv3/{serviceContextId}/users/{userid}` (C.6.14.2 e C.6.14.5) continuam.

## Access token válido recebe 107 (`cliente fora de clients:authorized`)

Desde 11/10 (E6, decisão do Luís), a borda exige que o `sub` do access token esteja no SET `clients:authorized`, nas rotas que pedem token (`token` e `token+bind`; as de `auth: none` não mudam). Fora dele, a resposta é 107, como a do cliente bloqueado, também com token de classe `local-associated`; em `warn`, só o aviso `X-TV30-Auth-Warn: 107`. O log da borda diz `cliente fora de clients:authorized (E6)`; token sem `sub` dá `access token sem sub: cliente fora de clients:authorized (E6)`, e o bloqueado mantém `cliente bloqueado pelo usuario (C.4.2.2)`, porque é conferido antes.

| Causa | O que fazer |
|---|---|
| O token não veio do fluxo `/tv3/authorize` + `/tv3/token` (assinado à mão com o `JWT_SECRET`, por exemplo o do `scripts/test-dev-host.sh`), e o `sub` dele nunca foi autorizado pelo espectador | Obtenha o token pelo fluxo real. Em `warn`, a requisição passa com o aviso |
| O cliente foi bloqueado e depois desbloqueado à mão (`SREM clients:blocked`) | O desbloqueio não o devolve a `clients:authorized`. A tela de gerenciamento da C.4.2.2 não existe (E5); até lá, inclua o id com a função do esquema, como o tv3ws faz no boot e o `scripts/test-auth.sh` faz no teste: `docker exec redis redis-cli FCALL tv30_cliente_inclui_autorizado 0 <clientid>`. A função só inclui quem tem `client:{id}` (que fica gravado depois do bloqueio) e está fora de `clients:blocked` |
| O cliente foi autorizado num volume do Redis que foi recriado (`docker compose down -v`) | O registro sumiu com o volume. Autorize de novo com `clientid` novo (o refresh token antigo não vale mais) |

```bash
docker exec redis redis-cli SISMEMBER clients:authorized <clientid>   # 1 = autorizado
docker exec redis redis-cli SISMEMBER clients:blocked <clientid>      # 1 = bloqueado
```

## A página da TV não conecta no MQTT (`/mqtt`)

Desde 11/10 (C1, decisão do Luís), a camada gráfica do AoP conecta em `ws(s)://<host da página>/mqtt`, na porta do AoP, e o AoP repassa a conexão ao WebSocket do Mosquitto (`aop/src/mqtt-ws.js`). O boot do AoP registra o alvo: `[mqtt-ws] MQTT por WebSocket em ws://<host do AoP>/mqtt -> ws://mosquitto:9001`.

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `broker MQTT fora do alcance (ws://...)` (502) | O AoP não alcança o Mosquitto no `MQTT_HOST`/`MQTT_WS_PORT` (broker parado; ou, com o AoP no host, `MQTT_WS_PORT` diferente da porta publicada da 9001) | `docker logs aop` mostra `[mqtt-ws] falha no repasse`. Com o AoP no host, `MQTT_WS_PORT=$(docker compose port mosquitto 9001 \| sed 's/.*://')` ([Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local)) |
| `MQTT por WebSocket so no host do AoP` (404) | A página foi aberta num host de app (`<app>.apps.localhost`). O repasse só existe no host do AoP, de propósito | Abra a tela do AoP pelo host dele (`http://localhost:8080`) |
| `upgrade WebSocket so em /mqtt` (404) | Pedido de WebSocket noutro caminho | Use o caminho `/mqtt` |
| O AoP não sobe: `[boot] MQTT_WS_PORT invalida` ou `MQTT_HOST invalido para o MQTT por WebSocket` | Porta fora de 1 a 65535, ou `MQTT_HOST` com porta ou caminho | Corrija a variável; o `MQTT_HOST` é só o nome ou IP do broker |
| A página tenta `ws://<host>:9001/mqtt` | Imagem do AoP anterior a 11/10, que ainda conecta direto na porta do Mosquitto no host, e essa porta não é mais fixa | Reconstrua o AoP (`docker compose build aop && docker compose up -d aop`) |

## `GET /tv3/authorize` dá 103 (`Unable to ask for user authorization`)

Desde a noite de 12/10 (decisão do Luís; G2 de [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes)), a TV atende um pedido de autorização de cada vez. Enquanto houver na tela o sim/não de outro pedido esperando resposta (até 10 s), ou o QR code ou o PIN de um pareamento (até o `/tv3/token` com o desafio resolvido, ou até a trava de 120 s), o `/tv3/authorize` responde 404 `{"error":103}` na hora, sem pop-up. É o que a C.4.2.3 manda ("so that the client can try again later"). Vale também para o mesmo `clientid` mandado duas vezes ao mesmo tempo.

- **O que fazer:** tentar de novo depois. Se o pareamento de outro cliente ficou pela metade, a camada só libera no fim da trava de 120 s.
- **No log do tv3ws:** `Camada grafica ocupada (<tipo> do cliente <id>): /tv3/authorize do cliente <id> recebe 103`.

## O QR code ou o PIN do pareamento some antes da hora, ou fica na tela

Desde 12/10 (correção; C.4.3.2 e C.4.3.3), o pop-up do QR code e o do PIN ficam na tela até o fim do pareamento, o `GET /tv3/token` com a resposta ao desafio aceita. Nessa hora o tv3ws publica `{"close":true}` no mesmo tópico, e a camada gráfica fecha o pop-up. O pop-up também tem uma trava de 120 s, escolhida pelo projeto ([APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws)).

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Some cerca de 1 s depois de aparecer | Imagem do tv3ws anterior a 12/10, que manda o pop-up com prazo de 1000 ms | Reconstrua o tv3ws (`docker compose build tv3ws && docker compose up -d tv3ws`) |
| Some antes do fim do pareamento | A trava de 120 s acabou. Desde a noite de 12/10, outro pedido de autorização não toma mais o lugar dele: recebe 103 (G2 de [Decisões pendentes]({{ site.baseurl }}/decisoes-pendentes)); com uma imagem do tv3ws anterior, o sim/não ou o pareamento de outro cliente o substituía. O aviso da C.6.14.5 (`popup/info`, desde a G9) não toma o lugar: espera o QR code ou o PIN sair | Se o cliente já leu o código, o pareamento continua valendo: o challenge não expira. Se não leu, repita o `/tv3/authorize` com `clientid` novo (o antigo dá 101) |
| Fica na tela depois do `/tv3/token` | O `/tv3/token` não concluiu o pareamento: falhou (102, por exemplo, com o desafio errado, que deixa a tentativa aberta) ou foi uma renovação por `refresh-token`; ou o tv3ws reiniciou entre o `/authorize` e o `/token` e perdeu o pareamento (o `/token` dá 102); ou o pop-up na tela é de outro cliente | A trava de 120 s o fecha. No fim do pareamento, o log do tv3ws mostra `Closing QRCode popup` ou `Closing PIN popup` |

## `errors/<client_id>`: `INVALID_JSON` num payload que parece JSON, ou mensagem com `"truncated":true`

Desde 12/10, o plugin do broker lê o payload inteiro e monta a mensagem de erro sempre como JSON válido ([Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos), *Plugin C do Mosquitto*; detalhes em `infra/docs/09-schema-validation.md`).

- **`INVALID_JSON` num payload que começa como JSON:** o plugin só aceita exatamente um texto JSON. Sobra depois do valor (`{"value":1}lixo`, `{"a":1}{"b":2}`), NUL em qualquer posição (um terminador de string C contado no comprimento, por exemplo), comentário, aspas simples e vírgula sobrando dão `INVALID_JSON`; espaço, tab, CR e LF em volta do valor passam. Até 12/10, a sobra passava e era entregue. Mande só o JSON.
- **Texto recusado num tópico de string** (`aop/currentUser`, `aop/currentService` e as camadas `rxgui`, `graphics` e `video/url`): o payload que não é texto JSON vale inteiro como string; o que é JSON (`42`, `true`, `{"id":"x"}`) vale como esse valor e falha no `type`. De 11/10 a 12/10, um UUID que começa com dígito era recusado em `aop/currentUser` (`Expected type 'string', got 'int'`): reconstrua o broker (`docker compose build mosquitto && docker compose up -d mosquitto`).
- **`"truncated":true`:** a mensagem tem no máximo 2047 bytes, e cada campo tem um teto em bytes já escapados (`topic` 512, `details` 768, `client_id` 256; o payload fica com o resto). O campo que não coube foi cortado entre caracteres inteiros, e o payload completo não está na mensagem; o `topic` e o `details` dizem qual foi a recusa.
- **`�` no payload da mensagem:** era um byte que não formava UTF-8 válido no payload recusado.
- **A mensagem não chega em `errors/<meu client_id>`:** no tópico, `+`, `#`, `/` e controles do `client_id` viram `_`. Assine `errors/#`; o campo `client_id` da mensagem traz o original.

---

## Inspecionar estado do sistema

```bash
# Redis
docker exec redis redis-cli SMEMBERS users:index
docker exec redis redis-cli HGETALL user:<id>              # id em UUID desde 11/10 (F-3)
docker exec redis redis-cli GET session:current-user
docker exec redis redis-cli HGETALL origins:associated   # origem da app em execucao -> servico
docker exec redis redis-cli FCALL_RO tv30_auditoria 0    # chaves fora do esquema (P4); vazio = ok
docker exec redis redis-cli FCALL_RO tv30_versao 0       # versao do esquema carregado (4 desde a noite de 12/10, G8)
docker exec redis redis-cli SMEMBERS clients:authorized  # clientes que a borda aceita (E6)

# MQTT
docker exec mqtt-broker mosquitto_sub -t '#' -v

# Logs
docker logs aop --tail 50
docker logs tv3ws --tail 50
docker logs mqtt-broker --tail 50
```

Redis Commander: a porta de host é dinâmica. `docker port redis 18081` mostra qual é, e a UI fica em `http://localhost:<porta>/`. A UI exige login: usuário `admin` e senha `tv30-redis-admin` por padrão, ou os valores de `REDIS_COMMANDER_USER`/`REDIS_COMMANDER_PASSWORD` no `.env` da raiz (D-L1, decidida pelo Luís em 03/10). A conexão com o banco (6379, `redis-cli`) segue sem senha.

## Redis Commander abre sem pedir login, recusa o login padrão ou derruba o Redis

- **Abre direto, sem formulário de login:** a imagem `tv30-redis` foi construída antes de 03/10, ou puxada do Docker Hub antes da publicação das imagens novas, e o entrypoint antigo ignora as variáveis. Reconstrua com `docker compose build redis && docker compose up -d redis`.
- **O container `redis` reiniciou sozinho, e o log termina com `[redis] commander (pid <n>) morreu — derrubando o container inteiro (morre-inteiro, C2)`:** é o comportamento desde 11/10 (C2, decisão do Luís). A morte do commander derruba o container, e o `restart: unless-stopped` o traz de volta; até ele ficar saudável de novo, os serviços recebem a falha do Redis. Até 11/10, o commander morria sozinho, e o banco seguia. Se a linha disser `redis-server`, foi o banco que caiu.
- **Login recusado com `admin`/`tv30-redis-admin`:** o `.env` da raiz define outro usuário ou outra senha. Para ver o valor em uso, rode `docker exec redis printenv REDIS_COMMANDER_USER REDIS_COMMANDER_PASSWORD`. Depois de mudar o `.env`, recrie o container com `docker compose up -d redis`, porque o valor só é lido na subida.
