---
title: Solução de problemas
nav_order: 4
---

# Troubleshooting

## Porta presa: `failed to bind host port ... address already in use`

Triagem, nesta ordem (exemplo: portas 3000/3001 presas por um segundo
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

### Quais portas podem estar presas

Só as portas **fixas** do host podem colidir com outro processo: a 44642 (norma, C.3.4), a 44643 da borda, a do AoP (8080, `AOP_PUBLIC_PORT`), a 1883, a 6379 (só em `127.0.0.1`) e a faixa 45000–45199, que o compose publica inteira para o tv3ws; fora do Docker, a UDP 1900 do anunciante SSDP. A 44643 é fixa por padrão (`EDGE_EXT_PUBLISH`, padrão `44643:44643`). O `preflight` confere a 44642 (bloqueia a subida se um processo nativo a ocupa) e avisa se a 1883, a 6379, a 44643 ou a do AoP estão ocupadas (`scripts/preflight.sh`, `PORTS_WARN`). A faixa 45000–45199 e a UDP 1900 não entram na checagem; com a 1900 presa, o próprio anunciante encerra com erro (*Descoberta SSDP*, abaixo). Uma porta fixa dentro da faixa efêmera do Linux também pode ser recusada de vez em quando, com a porta livre logo depois ([problemas conhecidos](https://github.com/multisens/TV30/blob/main/KNOWN-ISSUES.md)).

As outras portas saem numa porta livre que o Docker escolhe, e não colidem: a 8081 do bcast, a 9001 (MQTT por WebSocket) do Mosquitto, a 8085 da documentação e a 18081 do redis-commander. A 9003 é uma opção para quem roda o AoP fora do Docker no Windows (*AoP fora do Docker no Windows*, abaixo). Se você fixou uma das portas livres no `.env` (`BCAST_PUBLISH` ou `MQTT_WS_PUBLISH` com `host:container`), ela volta a poder colidir; `EDGE_EXT_PUBLISH=44643`, só o número, faz o contrário com a 44643, que passa a sair numa porta livre.

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

O `/manifest` (`Server-SecureBaseURL`, `tv3ws/src/ssdp-config.ts`) e o OpenAPI da superfície externa, na documentação Swagger (`servers: https://localhost:44643`, `infra/edgegateway/generate.js`), dizem 44643. Com o padrão (`EDGE_EXT_PUBLISH=44643:44643`), essa é a porta de host da externa. Com `EDGE_EXT_PUBLISH=44643` (só o número), o Docker escolhe outra, e os dois deixam de valer. Com outra porta fixa (`X:44643`), defina também `EDGE_HTTPS_PORT=X` no `.env` da raiz, para o `/manifest` anunciá-la; o OpenAPI continua dizendo 44643. Depois de mudar o `.env`, recrie a borda e o tv3ws (`docker compose up -d edgegateway tv3ws`).

### `preflight`: "a porta 44642 esta ocupada" com a stack de pé

O container do preflight não tem `CAP_SYS_PTRACE`, então o `netstat` dele não
enxerga o dono de uma porta do `docker-proxy` e mostra `-`; o preflight
reconhece o `docker-proxy` da própria stack pela linha de comando (`owner_of`,
em `scripts/preflight.sh`) e só avisa. O erro, então, indica um processo
nativo na 44642: confira com `sudo ss -ltnp | grep 44642`.

## Descoberta SSDP: o anunciante não sobe ou não anuncia

O anunciante roda no host, fora do Docker, subido pelo `./tv30 up` (no Windows, `.\tv30.ps1 up`), com pid e log em `.tv30/` ([Descoberta SSDP]({{ site.baseurl }}/ssdp)). `./tv30 status` diz se ele está de pé, e `./tv30 logs` mostra o log (`.tv30/ssdp.log`). Sem ele, o cliente ainda chega ao receptor pelo IP: `http://<IP>:44642/manifest`.

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `o anunciante SSDP saiu logo depois de subir` no `./tv30 up`, e o log mostra `[ssdp] FALHA em ...` | Erro de configuração: porta inválida em `EDGE_HTTP_PORT` ou `EDGE_HTTPS_PORT`, `SSDP_INTERFACE` inexistente ou de loopback, `SSDP_ADVERTISE_HOST` sem host, ou a UDP 1900 presa por um socket sem `SO_REUSEADDR` | Corrija o `.env` da raiz (ou o `tv3ws/.env`) e rode `./tv30 up` de novo. O anunciante lê os dois arquivos, e o shell prevalece |
| No macOS, o log mostra `no route to host`, e o anunciante fica esperando a rede | O terminal que roda o `./tv30 up` não tem a permissão de Rede Local | Ajustes > Privacidade e Segurança > Rede Local; depois, `./tv30 up` de novo |
| No Windows, outro aparelho não recebe o anúncio | O Windows Defender não liberou o anunciante em redes privadas, ou o perfil da rede é Público | Aceite a solicitação do Defender marcando "redes privadas", com o perfil da rede como Privada |
| `AVISO sem rede para o anuncio` | Sem rede na interface da rota padrão | Nada: o anunciante tenta de novo sozinho, com espera crescente até 30 s, e volta a anunciar quando a rede volta. As APIs não dependem dele |
| `SSDP_ENABLED=false: anunciante nao sobe` | `SSDP_ENABLED=false` no `.env` ou no shell | Tire a variável para ligar a descoberta |

Se o `preflight` avisar que o container `tv3ws-ssdp` está de pé, ele é um segundo anunciante: `docker rm -f tv3ws-ssdp` o remove.

## Redis não fica saudável e o tv3ws ou a borda não sobem

A carga inicial vem na própria imagem `tv30-redis`: o seed é gerado no build (estágio `seedgen` do `infra/redis/Dockerfile`, em Python só com a biblioteca padrão) e aplicado pelo `infra/redis/entrypoint.sh` com `redis-cli --pipe`. A partida não instala nada nem precisa de rede.

O healthcheck do `redis` só passa depois da carga (chave `seed:done`, testada a cada 2 s, até 30 vezes; `infra/redis/docker-compose.yml`). O `tv3ws` e o `edgegateway` dependem dele com `condition: service_healthy`; o broker não depende do Redis. Para ver em que ponto a carga está: `docker logs redis`, que registra `[redis] aplicando carga inicial pelas funcoes (redis-cli --pipe)...` e `[redis] carga concluida (<n> perfil(is))`, ou `[redis] carga ja aplicada (seed:done presente) — mantida`.

O seed sai do template `infra/user-files-template/userData.json` no build. Uma mudança no template só entra com a imagem reconstruída e, mesmo assim, só num volume `redis_data` que ainda não tenha `seed:done`: o entrypoint não reaplica a carga num volume já semeado.

O healthcheck também exige que a biblioteca de funções `tv30` tenha carregado **nesta** partida (marca `/tmp/tv30-redis-pronto`, criada pelo entrypoint). No log aparece `[redis] biblioteca de funcoes tv30 carregada (esquema versao N)`. Se o log mostrar `ERRO: a biblioteca de funcoes tv30 NAO carregou`, o container encerra, porque sem as funções toda escrita dos serviços falharia. A causa é um `esquema.json` ou `funcoes.lua` quebrado numa imagem montada à mão: reconstrua a partir do repositório (`docker compose build redis`), já que o build confere a biblioteca. Se o log mostrar `ERRO: a carga inicial foi recusada pelo esquema`, um perfil do `userData.json` está fora do esquema: o log diz qual campo, `seed:done` não é gravado e o container fica *unhealthy*. Corrija o template e reconstrua a imagem.

## Erro `TV30ESQUEMA` numa resposta ou no log

```
TV30ESQUEMA tv30_perfil_grava: user:0b6e3c1a-7f2d-4e8b-9a5c-3d1f2e4a6b8c campo parentalControl: deve ser "true" ou "false" (veio "False")
```

É uma função do Redis recusando uma escrita fora do esquema. A mensagem diz a função, a chave, o campo e o motivo, e nada foi gravado. Para o serviço, é defeito de quem grava. O tv3ws e o AoP respondem 404 `{"error":200}` com a mensagem no `description` e no log (`[error] <método> <url>: TV30ESQUEMA ...`). A borda responde com `escrita recusada pelo esquema do Redis (...)`. Um handler MQTT só loga (no tv3ws, `[mqtt] FALHA no handler de <tópico>`).

- **Veio de uma escrita do código:** o serviço montou um dado que o esquema não aceita. Compare a mensagem com a regra no `infra/redis/esquema.json` (o campo `fonte` diz de onde ela veio) e corrija quem grava, não a regra. Mudar a regra é decisão do projeto.
- **Veio de um script ou de uma chamada à mão (`FCALL`):** os argumentos estão fora do esquema. Os formatos de cada função estão em [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis#as-funções).
- **`ERR Function not found`:** o Redis está sem a biblioteca. Pode ser uma imagem desatualizada ou um Redis que não é o da stack. Reconstrua com `docker compose build redis && docker compose up -d redis`.
- **`deve ser UUID no formato da RFC 9562` na criação de perfil:** o esquema exige o id do perfil em UUID estrito, em minúsculas, e a mensagem diz qual parte falhou: `versao do UUID deve ser de 1 a 8`, `variante do UUID deve ser a da RFC 9562` (primeiro dígito do quarto grupo em `8`, `9`, `a` ou `b`), `UUID nulo` ou `UUID maximo` (`motivoUuid`, em `infra/redis/funcoes.lua`). O AoP gera `crypto.randomUUID()` (versão 4, válido); com uma imagem desatualizada do AoP, que gere outro formato, a criação responde 404 `{"error":200}`: reconstrua o AoP com o Redis (`docker compose build aop redis`). Num volume com perfis fora do esquema, ver *Auditoria do Redis com achados*, abaixo.
- **`campo avatar: SVG em linha nao serve` na criação de perfil:** o `avatar` é o nome de um arquivo do diretório de miniaturas (por exemplo, `c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10.svg`), e não o SVG. Uma imagem desatualizada do AoP que grave o SVG em linha recebe 404 `{"error":200}` na criação: reconstrua o AoP com o Redis (`docker compose build aop redis`). As outras recusas do mesmo campo dizem o que falhou: diretório no nome (`/` ou `\`), extensão fora de `.svg`, `.png`, `.jpg`, `.jpeg` e `.webp` (ou em maiúsculas), primeiro caractere que não é letra nem dígito, caractere fora de letras sem acento, dígitos, `.`, `_` e `-`, ou mais de 128 caracteres antes da extensão (`motivoNomeArquivo`, em `infra/redis/funcoes.lua`).

## Auditoria do Redis com achados

```bash
docker exec redis redis-cli FCALL_RO tv30_auditoria 0
```

Cada achado é `[chave, familia, motivo]`, e a auditoria vazia é o estado esperado. O `scripts/test-auth.sh` dá FAIL se ela não terminar vazia e avisa no começo se já havia achados antes da suíte. Causas comuns:

- **Dados gravados sem passar pelas funções:** booleanos como `"False"`/`"True"`, ou hashes `user:{id}` só com `lastAccess`, fora de `users:index` (por exemplo, `user:abc-123`). Para começar limpo, use `docker compose down -v`, que apaga o volume e com ele os perfis criados. A outra saída é corrigir ou apagar as chaves apontadas.
- **`{id} da chave: deve ser UUID ...`:** o esquema exige o id do perfil em UUID estrito, sem compatibilidade com outros formatos. Um perfil com outro id (como `user_<epoch-ms>` ou `c3167a18-5dc5`) aparece em `users:index`, `user:{id}`, `user:{id}:consent` e `user:{id}:broadcaster-attrs:*`, também com os motivos `versao do UUID ...`, `variante do UUID ...`, `UUID nulo` ou `UUID maximo`. A carga não roda de novo num volume já semeado (`seed:done`), então o perfil da carga (`c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10`) não entra. Saída: `docker compose down -v`, que apaga os perfis criados e também os retidos do broker. Para conferir a versão do esquema carregada: `docker exec redis redis-cli FCALL_RO tv30_versao 0`, que tem de dar a versão de `infra/redis/esquema.json`.
- **`campo avatar: SVG em linha nao serve: ...`:** o `avatar` é o nome de um arquivo, e cada perfil gravado com o SVG em linha aparece em `user:{id}`. A escolha do perfil e os atributos de emissora continuam funcionando, e as telas mostram o avatar padrão para eles. O perfil da carga se conserta com `docker exec redis redis-cli HSET user:c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10 avatar c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10.svg`; o arquivo vem do template para `./user-files/thumbs` pelo `userfiles-seed` (se ainda não estiver lá, `docker compose up -d` o copia). Um perfil sem arquivo de avatar: tire o campo (`docker exec redis redis-cli HDEL user:<id> avatar`, e as telas mostram o padrão) ou recrie o volume (`docker compose down -v`, que apaga os perfis criados e os retidos do broker).
- **Escrita à mão** pelo `redis-cli` ou pelo Redis Commander, que não passa pelas funções. Grave pela função (`FCALL <funcao> 0 ...`, exemplos em [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis)) ou desfaça a escrita.
- **`chave sem familia no esquema`:** a chave tem um prefixo do alcance (`user:`, `session:`, `client:`...) mas não é de nenhuma família, como `user:{id}:profile`. Se ninguém a usa, apague.

## Criação de perfil recusada: `O limite de 5 perfis foi atingido`

O sexto perfil é recusado, sem despejar nenhum (10.3.3). Quem confere é a função `tv30_perfil_grava`, na mesma operação da gravação (`maxMembros` de `users:index`, em `infra/redis/esquema.json`): a recusa (`TV30ESQUEMA tv30_perfil_grava: users:index teto de 5 perfis atingido ...`) vira, no AoP, o 400 com a mensagem. Para abrir espaço, remova um perfil no seletor de perfil: a opção "Remove", embaixo de cada perfil, só aparece com mais de um perfil e pede confirmação; a remoção apaga o perfil, a visibilidade, os atributos de emissora e o arquivo do avatar ([Modelo de dados Redis]({{ site.baseurl }}/modelo-redis)). Num ambiente de teste, `docker compose down -v` volta à carga inicial, apagando os perfis criados e os retidos do broker.

Com o Redis sem nenhum perfil, o AoP cria o perfil padrão "Viewer 1", sem avatar, idiomas nem visibilidade, na partida e ao abrir o seletor.

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

**Causa:** o WSL2 desliga a VM por inatividade, derrubando os containers.

**Fix:** acrescente no `~/.wslconfig`:

```ini
vmIdleTimeout=86400000   # 24h
```

E mantenha um processo leve rodando no WSL (qualquer terminal aberto).

### AoP fora do Docker no Windows: porta do WebSocket do Mosquitto

O AoP rodando no Windows, fora do Docker (caso que o `scripts/test-dev-host.sh` não cobre; [Limites]({{ site.baseurl }}/dev-local#limites)), repassa o `/mqtt` da página da TV para `ws://${MQTT_HOST}:${MQTT_WS_PORT}`, e o `MQTT_WS_PORT` tem de ser a porta de host da 9001 do Mosquitto (`aop/src/mqtt-ws.js`). Por padrão, essa porta é escolhida pelo Docker e muda quando o container é recriado. Uma opção, e não regra, é fixá-la na 9003, que evita a 9001 e a 9002, ocupadas pelo Hyper-V em algumas máquinas (detalhe em [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local#aop-fora-do-docker-no-windows-opção)):

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

## Mac com Apple Silicon: imagens só `amd64`

As imagens do Docker Hub saem só para `amd64` (o workflow de CI não define `platforms`). Num Mac com Apple Silicon, construa as imagens localmente antes de subir: `docker compose build` e depois `./tv30 up`. O Dockerfile da borda escolhe o Go pela arquitetura (`TARGETARCH`): o `krakend/builder` em `amd64` e o `golang:1.22.7-alpine3.19` em `arm64`, com o mesmo Go e a mesma libc do KrakenD; outra arquitetura falha no build (`infra/edgegateway/Dockerfile`).

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

O AoP abre cada app de emissora num nome de host próprio, na porta dele, com o prefixo `/graphicsAppProxy` na URL: `http://<rótulo>.apps.localhost:8080/graphicsAppProxy<bcastEntryPointUrl>` (`aop/src/app-hosts.js`). O `<rótulo>` sai do `appId` da BALD, fixo por app: o users-test, por exemplo, abre em `http://urn-tv30-app-users-test.apps.localhost:8080/graphicsAppProxy/users-test`. No host do próprio AoP, `/graphicsAppProxy/...` redireciona (302) para o host da app em execução. Para ver o endereço da app em execução, que é a origem gravada pelo AoP:

```bash
docker exec redis redis-cli HGETALL origins:associated
docker logs aop --tail 50 | grep '\[apps\]'
```

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| A app não carrega com a tela do AoP aberta de **outra máquina** | `*.localhost` resolve para a máquina de quem abre a página, e não para a do AoP | Defina `APPS_DOMAIN` no `.env` da raiz com um domínio resolvível na rede, com `*.<domínio>` apontando para a máquina do AoP (DNS curinga), e recrie o AoP (`docker compose up -d aop`) |
| A app não carrega, e o AoP está publicado noutra porta do host | A origem da app usa `AOP_PUBLIC_PORT` (padrão 8080), e não a porta pela qual o navegador chegou | Mude a porta pelo `AOP_PUBLIC_PORT` do `.env` da raiz, que troca a porta publicada e a origem juntas |
| `nenhuma aplicacao em execucao em <host>` (404) | Nenhuma app em execução tem esse rótulo: a app foi encerrada, ou trocada por outra, e a página antiga ficou aberta. Com o `appId` trocado no bcast (`EDUPLAY_APP_ID`, `UFF_APP_ID`, `USERS_TEST_APP_ID`, `WEBMEDIA_APP_ID`), o rótulo também muda | Abra a app de novo pelo catálogo do AoP |
| `nenhuma aplicacao em execucao na camada grafica` (404), em `/graphicsAppProxy/...` no host do AoP | Nenhuma app em execução para onde redirecionar | Abra a app pelo catálogo do AoP |
| `Bad Gateway: aplicacao fora do ar` (502) | O AoP não alcança o `bcastEntryPackageUrl` da app (bcast parado, ou `BCAST_HOSTNAME` errado no dev-host) | `docker logs aop` mostra a falha do proxy (`[apps] falha no proxy ...`); confira o bcast |
| O AoP não sobe: `[boot] APPS_DOMAIN invalido` ou `AOP_PUBLIC_PORT invalida` | Valor fora do formato (rótulos `[a-z0-9-]` separados por ponto; porta inteira de 1 a 65535) | Corrija o `.env` da raiz |
| A app abre, mas não recebe teclas, `timeupdate` nem `stream_event` | Com a app em outra origem, o AoP entrega os eventos por `postMessage`, e a app não inclui a ponte `bcast/public/js/aop-bridge.js` | Inclua `<script src="js/aop-bridge.js"></script>` na app (ver `bcast/README.md`) |
| As chamadas da app às APIs recebem 107 (em `warn`, passam com `X-TV30-Auth-Warn: 107`), ou 106 nas rotas só do local associado, como `POST /tv3/bind-context` | A origem da app não está em `origins:associated`: a app foi encerrada (ESC) ou trocada, e a página ficou aberta; ou a gravação no Redis falhou (log do AoP) | Abra a app pelo AoP (catálogo e tela cheia) |

O QtWebEngine não foi testado com os nomes `*.apps.localhost`.

## Rota exclusiva do cliente local, ou o `/tv3/authorize`, dá 106

As duas superfícies têm as 26 rotas; o que muda de uma para a outra é o 106 ([Borda e credenciais]({{ site.baseurl }}/borda-credenciais)). Sai nos dois modos, `enforce` e `warn`:

- **Na 44643 (externa, HTTPS):** as rotas de uso exclusivo do cliente local (`POST` e `DELETE /tv3/bind-context`, `GET /tv3/remote-device/devices/{classId}` da C.6.15.5 e as rotas por *handle*, `GET` e `DELETE /tv3/remote-device/device/{handle}`) e o `GET /tv3/authorize` respondem 404 `{"error":106}` a qualquer requisição (C.4.1.8; a C.6.1.2 "can only be accessed via the HTTP protocol"; na C.6.15.5, a Tabela C.80 lista 107 para o não local: [Não implementado]({{ site.baseurl }}/nao-implementado)). Use a 44642.
- **Na 44642 (interna, HTTP):** o access token de classe `nonLocal` só vale no `/tv3/authorize` e no `/tv3/token`; nas demais rotas, 106 (C.4.1.6), com o log `cliente nao local por HTTP fora da C.6.1.2/C.6.1.3`. Depois de obter o token, o cliente não local usa a 44643. Nas rotas só do cliente local, ele recebe antes o 106 da regra de classe (`rota nao disponivel para nonLocal`; `infra/edgegateway/plugin/handler.go`).

A C.6.7.9 lista as 20 APIs nas duas superfícies: a restrição aparece pelo 106 no uso, e não na lista.

## `POST /tv3/<scid>/users` dá 100

`POST /tv3/{serviceContextId}/users` não existe na norma, que só define `POST /tv3/current-service/users` (C.6.14.1), e não está na tabela de rotas (`infra/edgegateway/routes.json`). A borda responde 404 `{"error":100}` em qualquer scid, inclusive o `globalServiceId` de um serviço e `Current-Service` com a caixa trocada, nas duas superfícies e nos dois modos. Use `POST /tv3/current-service/users`, com bind-token. As rotas `GET` e `POST /tv3/{serviceContextId}/users/{userid}` (C.6.14.2 e C.6.14.5) são declaradas e conferem o catálogo (304, abaixo).

## Access token válido recebe 107 (`cliente fora de clients:authorized`)

A borda exige que o `sub` do access token esteja no SET `clients:authorized`, nas rotas que pedem token (`token` e `token+bind`; as de `auth: none` não mudam). Fora dele, a resposta é 404 `{"error":107}` (em `warn`, só o aviso `X-TV30-Auth-Warn: 107`), como a do cliente bloqueado, também com token de classe `associated`. O log da borda diz `cliente fora de clients:authorized: autorizacao do espectador ausente ou removida`; token sem `sub` dá `access token sem sub: cliente fora de clients:authorized`, e o bloqueado mantém `cliente bloqueado pelo usuario (C.4.2.2)`, porque é conferido antes.

| Causa | O que fazer |
|---|---|
| O token não veio do fluxo `/tv3/authorize` + `/tv3/token` (assinado à mão com o `JWT_SECRET`, por exemplo o do `scripts/test-dev-host.sh`), e o `sub` dele nunca foi autorizado pelo espectador | Obtenha o token pelo fluxo real. Em `warn`, a requisição passa com o aviso |
| O cliente foi bloqueado e depois desbloqueado à mão (`SREM clients:blocked`) | O desbloqueio não o devolve a `clients:authorized`. A tela de gerenciamento da C.4.2.2 não existe; inclua o id com a função do esquema, como o tv3ws faz no boot e o `scripts/test-auth.sh` faz no teste: `docker exec redis redis-cli FCALL tv30_cliente_inclui_autorizado 0 <clientid>`. A função só inclui quem tem `client:{id}` (que fica gravado depois do bloqueio) e está fora de `clients:blocked` |
| O cliente foi autorizado num volume do Redis que foi recriado (`docker compose down -v`) | O registro sumiu com o volume. Autorize de novo com `clientid` novo (o refresh token antigo não vale mais) |

```bash
docker exec redis redis-cli SISMEMBER clients:authorized <clientid>   # 1 = autorizado
docker exec redis redis-cli SISMEMBER clients:blocked <clientid>      # 1 = bloqueado
```

## Rota com bind-token dá 300, 304, 104 ou 108

Nas rotas `token+bind` (`infra/edgegateway/routes.json`), depois da classe e do access token (o local associado reconhecido pelo `Origin` não passa pelo token), a borda confere nesta ordem (`evaluate`, em `infra/edgegateway/plugin/handler.go`; [Borda e credenciais]({{ site.baseurl }}/borda-credenciais)):

| Código | Quando | O que fazer |
|---|---|---|
| 300 | Nenhum serviço DTV selecionado, nas rotas cuja tabela lista o 300 (C.6.4.7 e C.6.14.1 a C.6.14.6). Vem antes do bind-token e sai nos dois modos | Selecione um serviço no catálogo do AoP. `docker exec redis redis-cli GET session:current-service-id` mostra o serviço corrente (vazio = nenhum) |
| 304 | Em `/tv3/{serviceContextId}/users/{userid}` (C.6.14.2 e C.6.14.5), o serviço do caminho não está no Application Catalog (`services:announced`). Vem antes do bind-token e sai nos dois modos | Use o `globalServiceId` de um serviço anunciado: `docker exec redis redis-cli SMEMBERS services:announced` lista os que a BAMT trouxe; a lista vazia indica o bcast parado ou o AoP sem a BAMT (`docker logs aop \| grep '\[lls\]'`) |
| 104 | Sem o cabeçalho `bind-token` | Mande o bind-token assinado pela emissora |
| 108 | O bind-token não foi assinado por uma chave registrada (C.6.8.2) para o contexto de serviço da rota: o `{serviceContextId}` do caminho, que é o `globalServiceId` do BAM, ou o serviço corrente em `current-service`. Na C.6.16.3, também sem serviço selecionado | A app da emissora registra a chave pela C.6.8.2 (`POST /tv3/bind-context`, que grava no serviço corrente; `bindcontext.go`). Confira se o contexto da rota é esse serviço |

A app de emissora reconhecida pelo `Origin` (local associado) dispensa o bind-token só no próprio contexto de serviço, o do serviço que a lançou (valor em `origins:associated`). Noutro contexto, recebe 104 ou 108 como qualquer cliente (C.4.1.1). Um access token de classe `associated` não dispensa o bind-token: segue a regra geral. O 104 e o 108 seguem o modo: em `warn`, só o aviso `X-TV30-Auth-Warn`.

## A página da TV não conecta no MQTT (`/mqtt`)

A camada gráfica do AoP conecta em `ws(s)://<host da página>/mqtt`, na porta do AoP, e o AoP repassa a conexão ao WebSocket do Mosquitto (`aop/src/mqtt-ws.js`). O boot do AoP registra o alvo: `[mqtt-ws] MQTT por WebSocket em ws://<host do AoP>/mqtt -> ws://mosquitto:9001`.

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `broker MQTT fora do alcance (ws://...)` (502) | O AoP não alcança o Mosquitto no `MQTT_HOST`/`MQTT_WS_PORT` (broker parado; ou, com o AoP no host, `MQTT_WS_PORT` diferente da porta publicada da 9001) | `docker logs aop` mostra `[mqtt-ws] falha no repasse`. Com o AoP no host, `MQTT_WS_PORT=$(docker compose port mosquitto 9001 \| sed 's/.*://')` ([Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local)) |
| `MQTT por WebSocket so no host do AoP` (404) | A página foi aberta num host de app (`<app>.apps.localhost`). O repasse só existe no host do AoP, de propósito | Abra a tela do AoP pelo host dele (`http://localhost:8080`) |
| `upgrade WebSocket so em /mqtt` (404) | Pedido de WebSocket noutro caminho | Use o caminho `/mqtt` |
| O AoP não sobe: `[boot] MQTT_WS_PORT invalida` ou `MQTT_HOST invalido para o MQTT por WebSocket` | Porta fora de 1 a 65535, ou `MQTT_HOST` com porta ou caminho | Corrija a variável; o `MQTT_HOST` é só o nome ou IP do broker |

## `GET /tv3/authorize` dá 103 (`Unable to ask for user authorization`)

A TV atende uma autorização de cada vez. Enquanto houver na tela o sim/não de outro pedido esperando resposta (até 10 s), ou o QR code ou o PIN de um pareamento (até o `/tv3/token` com o desafio resolvido, ou até a trava de 120 s), o `/tv3/authorize` responde 404 `{"error":103}` na hora, sem pop-up. É o que a C.4.2.3 manda ("so that the client can try again later"). Vale também para o mesmo `clientid` mandado duas vezes ao mesmo tempo.

- **O que fazer:** tentar de novo depois. Se o pareamento de outro cliente ficou pela metade, a camada só libera no fim da trava de 120 s.
- **No log do tv3ws:** `Camada grafica ocupada (<tipo> do cliente <id>): /tv3/authorize do cliente <id> recebe 103`.

## O QR code ou o PIN do pareamento some antes da hora, ou fica na tela

O pop-up do QR code e o do PIN ficam na tela até o fim do pareamento (C.4.3.2 e C.4.3.3), o `GET /tv3/token` com a resposta ao desafio aceita. Nessa hora o tv3ws publica `{"close":true}` no mesmo tópico, e a camada gráfica fecha o pop-up. O pop-up também tem uma trava de 120 s, escolhida pelo projeto ([APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws)).

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Some antes do fim do pareamento | A trava de 120 s acabou. Outra autorização não toma o lugar dele (recebe 103), e o aviso da C.6.14.5 (`popup/info`) espera o QR code ou o PIN sair | Se o cliente já leu o código, o pareamento continua valendo: a tentativa pendente não expira. Se não leu, repita o `/tv3/authorize`, com o mesmo `clientid` ou outro: a tentativa pendente não conta como uso, e o novo pedido a descarta |
| Fica na tela depois do `/tv3/token` | O `/tv3/token` não concluiu o pareamento: falhou (102, por exemplo, com o desafio errado, que deixa a tentativa aberta) ou foi uma renovação por `refresh-token`; ou o tv3ws reiniciou entre o `/authorize` e o `/token` e perdeu o pareamento (o `/token` dá 102); ou o pop-up na tela é de outro cliente | A trava de 120 s o fecha. No fim do pareamento, o log do tv3ws mostra `Closing QRCode popup` ou `Closing PIN popup` |

## A 44643 recusa o certificado, ou o dispositivo remoto não abre o `wss://`

A 44643 (superfície externa) fala TLS com o certificado autoassinado do receptor, que o `tls-init` gera em `.tv30/tls` na primeira subida (`docker logs tv30-tls-init` mostra o assunto e a validade). O mesmo certificado vale para o HTTPS do tv3ws, o `serverCert` do pareamento (Tabela C.4) e o `wss://` do ponto de entrada do dispositivo remoto (registro, C.6.15.2). O ponto de entrada local (C.6.15.5 e ativação por *handle*) sai sempre em `ws://` e não depende do certificado.

- **`curl` na 44643 falha com erro de certificado:** use `curl -k https://localhost:44643/...`, ou `--cacert .tv30/tls/cert.pem`. O certificado vale para `localhost` e `127.0.0.1` (`subjectAltName`, `infra/edgegateway/tls-init.sh`): por outro endereço, o nome não confere, e só o `-k` resolve.
- **Dispositivo remoto não abre o `wss://`:** um aparelho não abre `wss://` com certificado autoassinado em que não confia. Confie no certificado nele, ou defina `TV3WS_WS_TLS=false` no `.env` da raiz e recrie o tv3ws (`docker compose up -d tv3ws`): o ponto de entrada do dispositivo remoto sai em `ws://`.
- **Trocar o certificado:** ponha `cert.pem` e `key.pem` em `.tv30/tls` e recrie a stack. O `tls-init` só gera o par quando falta um dos dois.

## `errors/<client_id>`: `INVALID_JSON` num payload que parece JSON, ou mensagem com `"truncated":true`

O plugin do broker lê o payload inteiro e monta a mensagem de erro sempre como JSON válido ([Broker MQTT]({{ site.baseurl }}/broker-mqtt)).

- **`INVALID_JSON` num payload que começa como JSON:** o plugin só aceita exatamente um texto JSON. Sobra depois do valor (`{"value":1}lixo`, `{"a":1}{"b":2}`), NUL em qualquer posição (um terminador de string C contado no comprimento, por exemplo), comentário, aspas simples e vírgula sobrando dão `INVALID_JSON`; espaço, tab, CR e LF em volta do valor passam. Mande só o JSON.
- **Texto recusado num tópico de string** (`aop/currentUser`, `aop/currentService` e as camadas `rxgui`, `graphics` e `video/url`): o payload que não é texto JSON vale inteiro como string; o que é JSON (`42`, `true`, `{"id":"x"}`) vale como esse valor e falha no `type`.
- **`"truncated":true`:** a mensagem tem no máximo 2047 bytes, e cada campo tem um teto em bytes já escapados (`topic` 512, `details` 768, `client_id` 256; o payload fica com o resto). O campo que não coube foi cortado entre caracteres inteiros, e o payload completo não está na mensagem; o `topic` e o `details` dizem qual foi a recusa.
- **`�` no payload da mensagem:** era um byte que não formava UTF-8 válido no payload recusado.
- **A mensagem não chega em `errors/<meu client_id>`:** no tópico, `+`, `#`, `/` e controles do `client_id` viram `_`. Assine `errors/#`; o campo `client_id` da mensagem traz o original.

---

## Inspecionar estado do sistema

```bash
# Redis
docker exec redis redis-cli SMEMBERS users:index
docker exec redis redis-cli HGETALL user:<id>              # id em UUID
docker exec redis redis-cli GET session:current-user
docker exec redis redis-cli GET session:current-service-id # servico corrente (vazio = nenhum)
docker exec redis redis-cli HGETALL origins:associated   # origem da app em execucao -> servico
docker exec redis redis-cli SMEMBERS services:announced  # servicos do Application Catalog (BAMT)
docker exec redis redis-cli FCALL_RO tv30_auditoria 0    # chaves fora do esquema; vazio = ok
docker exec redis redis-cli FCALL_RO tv30_versao 0       # versao do esquema carregado
docker exec redis redis-cli SMEMBERS clients:authorized  # clientes que a borda aceita

# MQTT
docker exec mqtt-broker mosquitto_sub -t '#' -v

# Logs
docker logs aop --tail 50
docker logs tv3ws --tail 50
docker logs mqtt-broker --tail 50
```

Redis Commander: a porta de host é dinâmica. `docker port redis 18081` mostra qual é, e a UI fica em `http://localhost:<porta>/`. A UI exige login: usuário `admin` e senha `tv30-redis-admin` por padrão, ou os valores de `REDIS_COMMANDER_USER`/`REDIS_COMMANDER_PASSWORD` no `.env` da raiz. A conexão com o banco (6379, `redis-cli`) segue sem senha, e a 6379 só escuta em `127.0.0.1`.

## Redis Commander recusa o login padrão ou derruba o Redis

- **O container `redis` reiniciou sozinho, e o log termina com `[redis] commander (pid <n>) morreu — derrubando o container inteiro (morre-inteiro)`:** a morte do commander derruba o container, e o `restart: unless-stopped` o traz de volta; até ele ficar saudável de novo, os serviços recebem a falha do Redis. Se a linha disser `redis-server`, foi o banco que caiu.
- **Login recusado com `admin`/`tv30-redis-admin`:** o `.env` da raiz define outro usuário ou outra senha. Para ver o valor em uso, rode `docker exec redis printenv REDIS_COMMANDER_USER REDIS_COMMANDER_PASSWORD`. Depois de mudar o `.env`, recrie o container com `docker compose up -d redis`, porque o valor só é lido na subida.
