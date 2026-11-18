---
title: Solução de problemas
description: Sintoma, causa e o que fazer, para os problemas conhecidos do testbed.
---

Procure pela mensagem de erro ou pelo sintoma. Cada caso diz a causa e o que fazer. Os erros que já
se evitam antes estão em [Armadilhas](../armadilhas/).

:::tip[Não achou o problema?]
Procure também nas [issues do testbed](https://github.com/multisens/TV30/issues?q=is%3Aissue), abertas e
fechadas. Se não estiver lá, abra uma, com a mensagem de erro, o sistema operacional e os passos que
levam ao problema.
:::

## Subir

### Porta presa: `failed to bind host port ... address already in use`

Só as portas fixas do host colidem com outro processo: 44642, 44643, 8080, 1883, 6379 e a faixa
45000–45199, e a UDP 1900 do anunciante, fora do Docker
([Portas e endereços](../instalacao/#portas-e-endereços)). Antes da subida, a stack avisa quem
segura a 1883, a 6379, a 44643 ou a 8080, e não sobe se a 44642 estiver ocupada.

Triagem, nesta ordem:

```bash
# 1. quem esta com a porta?
sudo ss -ltnp | grep 44642

# 2. e um container deste daemon? remova-o ou derrube o projeto dono
sudo docker ps -a --format '{{.Names}}\t{{.Ports}}' | grep 44642

# 3. o ss mostra docker-proxy e o docker ps -a vem vazio? ha outro daemon
ps -ef | grep dockerd | grep -v grep
#    snap:    sudo snap stop docker --disable
#    Desktop: docker context ls, ou encerre o Docker Desktop

# 4. um daemon so e a porta continua presa: docker-proxy orfao
#    sudo kill -9 <pid do docker-proxy, do ss> e suba de novo
```

**Não use `kill` no `dockerd` do sistema:** o systemd o religa, e o socket pode ficar
dessincronizado (`/var/run/docker.sock: no such file or directory`). Reinicie assim:

```bash
sudo systemctl reset-failed docker.socket docker.service
sudo systemctl restart docker.socket docker.service
```

| Sintoma | Causa | O que fazer |
|---|---|---|
| A porta é recusada de vez em quando e está livre logo depois | No Linux e no WSL2, a 44642, a 44643 e a faixa 45000–45199 ficam dentro da faixa de portas que o sistema sorteia para as conexões de saída | Suba de novo. Para tirá-las do sorteio, há `net.ipv4.ip_local_reserved_ports=44642-44643,44652-44655,45000-45199`, uma configuração do kernel da máquina, e não só do testbed |
| A subida diz que a 44642 está ocupada com a stack de pé | Um processo fora do Docker está na 44642 | `sudo ss -ltnp \| grep 44642` |
| A subida avisa que o container `tv3ws-ssdp` está de pé | Sobra de uma versão antiga: seria um segundo anunciante | `docker rm -f tv3ws-ssdp` |

### O Redis não fica saudável, e o tv3ws ou a borda não sobem

O tv3ws e a borda esperam o Redis ficar saudável, o que acontece depois que a biblioteca de funções
carrega e a carga inicial é aplicada. `docker logs redis` mostra em que ponto está.

| No log | O que fazer |
|---|---|
| `[redis] ERROR: the tv30 function library did NOT load` | A imagem foi montada fora do repositório, com o esquema ou as funções quebrados. `docker compose build redis` |
| `[redis] ERROR: the initial load was refused by the schema` | Um perfil da carga inicial está fora do esquema, e o log diz qual campo. Corrija o template e reconstrua a imagem |
| `[redis] load already applied (seed:done present) — kept` | Normal: a carga só roda num volume novo. Mudança no template só entra com `docker compose down -v`, que apaga os perfis criados e os retidos do broker |

### Mac com Apple Silicon

As imagens publicadas são só `amd64`. Construa antes de subir: `docker compose build` e depois
`./tv30 up`.

### `exec /entrypoint.sh: no such file or directory`

O script foi commitado com CRLF, e o `#!/bin/sh\r` não vale. Converta com `dos2unix <arquivo>` e
reconstrua a imagem. A raiz e o `infra/` já têm `*.sh text eol=lf` no `.gitattributes`; o `aop`, o
`bcast` e o `tv3ws` não têm, e um script novo de container num deles precisa da mesma linha. Arquivo
commitado antes da regra só muda com `git add --renormalize .` e um commit.

### WSL2

| Sintoma | Causa | O que fazer |
|---|---|---|
| `localhost:8080` dá timeout no Windows | `networkingMode=mirrored` no `~/.wslconfig` | `networkingMode=NAT` e `localhostForwarding=true`, `wsl --shutdown` e reabra ([Instalação](../instalacao/#windows-com-wsl2)) |
| Os containers caem depois de um tempo sem uso | O WSL2 desliga a VM ociosa | `vmIdleTimeout=86400000` no `~/.wslconfig`, e um terminal aberto no WSL |
| `localhost:<porta>` responde "connection reset" depois do `docker compose down` | O repasse de portas do WSL2 ficou preso | `wsl --shutdown` e suba de novo |

## Descoberta na rede

`./tv30 status` diz se o anunciante está de pé, e `./tv30 logs` mostra o log. Sem o anúncio, o
aparelho ainda chega ao receptor pelo IP: `http://<IP>:44642/manifest`.

| Sintoma | Causa | O que fazer |
|---|---|---|
| `o anunciante SSDP saiu logo depois de subir`, e o log mostra `FALHA em ...` | Configuração inválida: `EDGE_HTTP_PORT` ou `EDGE_HTTPS_PORT`, `SSDP_INTERFACE` inexistente ou de loopback, `SSDP_ADVERTISE_HOST` vazio, ou a UDP 1900 presa | Corrija o `.env` e rode `./tv30 up` de novo |
| macOS: o log mostra `no route to host` | O terminal não tem a permissão de Rede Local | Ajustes > Privacidade e Segurança > Rede Local, e `./tv30 up` de novo |
| Windows: outro aparelho não recebe o anúncio | O Windows Defender não liberou o anunciante, ou a rede está como Pública | Libere em "redes privadas", com a rede como Privada |
| `AVISO sem rede para o anuncio` | Sem rede na interface da rota padrão | Nada: o anunciante volta a anunciar quando a rede volta |
| `SSDP_ENABLED=false: anunciante nao sobe` | `SSDP_ENABLED=false` no `.env` ou no shell | Tire a variável |
| A descoberta parou com a stack de pé | O anunciante saiu, e nada o reinicia ([defeito conhecido](#defeitos-conhecidos)) | `./tv30 status`; `./tv30 up` o sobe de novo |

## Redis e esquema

### Erro `TV30SCHEMA`

```
TV30SCHEMA tv30_profile_write: user:0b6e3c1a-... campo parentalControl: deve ser "true" ou "false" (veio "False")
```

Uma função do Redis recusou uma escrita fora do esquema, e nada foi gravado. A mensagem diz a
função, a chave, o campo e o motivo. O serviço responde 404 `{"error":200}`, com a mensagem no
`description` e no log.

- **Veio do código:** quem grava montou um dado fora do esquema. Corrija quem grava, e não o esquema.
- **Veio de um `FCALL` à mão:** os argumentos estão fora do formato da função
  ([As funções](../modelo-redis/#as-funções)).
- **`ERR Function not found`:** o Redis está sem a biblioteca. `docker compose build redis` e
  `docker compose up -d redis`.
- **Na criação de perfil, `deve ser UUID` ou `SVG em linha nao serve`:** a imagem da casca está
  desatualizada. `docker compose build aop redis`.

### Auditoria com achados

```bash
docker exec redis redis-cli FCALL_RO tv30_audit 0
```

Cada achado é `[chave, família, motivo]`, e o esperado é a lista vazia.

| Motivo | Causa | O que fazer |
|---|---|---|
| booleano como `"False"`, ou hash só com `lastAccess` | Escrita direta, pelo `redis-cli` ou pelo Redis Commander, por fora das funções | Grave pela função ([Gravar à mão](../modelo-redis/#gravar-à-mão)) ou apague a chave |
| `{id} da chave: deve ser UUID ...` ou `campo avatar: SVG em linha nao serve` | Um volume gravado por uma versão antiga | `docker compose down -v`, que apaga os perfis criados e os retidos do broker |
| `chave sem familia no esquema` | Uma chave com prefixo do esquema que não é de nenhuma família | Se ninguém a usa, apague |

### `O limite de 5 perfis foi atingido`

O sexto perfil é recusado (10.3.3). Remova um perfil no seletor ([aop](../aop/#perfis)), ou volte à
carga inicial com `docker compose down -v`.

## Casca e aplicações de emissora

### A aplicação não abre, ou abre e não responde

Para ver a aplicação em execução: `docker exec redis redis-cli HGETALL origins:associated`.

| Sintoma | Causa | O que fazer |
|---|---|---|
| Não carrega com a TV aberta de outra máquina | `*.apps.localhost` só resolve na máquina de quem abre a página | `APPS_DOMAIN` com um domínio resolvível na rede, com `*.<domínio>` apontando para a máquina da casca, e `docker compose up -d aop` |
| Não carrega com a casca publicada em outra porta | A origem da aplicação usa `AOP_PUBLIC_PORT` | Mude a porta pelo `AOP_PUBLIC_PORT`, que troca as duas juntas |
| `nenhuma aplicacao em execucao em <host>` (404) | A aplicação foi encerrada ou trocada, e a página antiga ficou aberta | Abra a aplicação de novo pelo catálogo |
| `Bad Gateway: aplicacao fora do ar` (502) | A casca não alcança o bcast | `docker logs aop` mostra `falha no proxy`; confira o bcast, ou o `BCAST_HOSTNAME` com módulos no host ([Desenvolvimento com serviço no host](../dev-local/#bcast_hostname)) |
| A casca não sobe: `APPS_DOMAIN invalido` ou `AOP_PUBLIC_PORT invalida` | Valor fora do formato | Corrija o `.env` |
| Abre, mas não recebe teclas, `timeupdate` nem `stream_event` | A aplicação não inclui a ponte | `<script src="js/aop-bridge.js"></script>` na aplicação ([aop](../aop/#aplicações-de-emissora)) |
| As chamadas da aplicação às APIs recebem 107, ou 106 nas rotas só do cliente local associado | A origem dela saiu de `origins:associated`: a aplicação foi encerrada ou trocada, e a página ficou aberta | Abra a aplicação pelo catálogo e pela tela cheia |

### A página da TV não conecta no MQTT (`/mqtt`)

| Sintoma | Causa | O que fazer |
|---|---|---|
| `broker MQTT fora do alcance` (502) | A casca não alcança o broker: ele está parado, ou, com a casca no host, `MQTT_WS_PORT` não é a porta publicada da 9001 | `docker logs aop` mostra `[mqtt-ws] falha no repasse`. Com a casca no host: `MQTT_WS_PORT=$(docker compose port mosquitto 9001 \| sed 's/.*://')` |
| `MQTT por WebSocket so no host do AoP` (404) | A página foi aberta no host de uma aplicação | Abra a TV em `http://localhost:8080` |
| `upgrade WebSocket so em /mqtt` (404) | WebSocket em outro caminho | Use `/mqtt` |
| A casca não sobe: `MQTT_WS_PORT invalida` ou `MQTT_HOST invalido para o MQTT por WebSocket` | Porta fora de 1 a 65535, ou `MQTT_HOST` com porta ou caminho | `MQTT_HOST` é só o nome ou o IP do broker |

Com a casca no Windows, fora do Docker, a porta da 9001 muda quando o broker é recriado; fixe-a
como em [Limites](../dev-local/#limites).

## APIs

### Os códigos de erro

| Código | Quando | O que fazer |
|---|---|---|
| 100 em `POST /tv3/<scid>/users` | A rota não existe na norma: só `POST /tv3/current-service/users` (C.6.14.1) | Use `current-service`, com bind-token |
| 103 no `/tv3/authorize` | A TV já mostra o sim ou não de outro pedido, ou o QR code ou o PIN de um pareamento (C.4.2.3) | Tente de novo depois. Um pareamento pela metade libera a tela em até 120 s |
| 106 na 44643 | A rota é só do cliente local (`bind-context`, C.6.15.5 e as notificações da 100.0), ou é o `/tv3/authorize`, que só vale por HTTP | Use a 44642 |
| 106 na 44642 | Cliente não local por HTTP fora do `/tv3/authorize` e do `/tv3/token` (C.4.1.6) | Depois de obter o token, use a 44643 |
| 107 com access token válido | O cliente não está em `clients:authorized`: o token não veio do fluxo de autorização, o cliente foi desbloqueado à mão ou o volume do Redis foi recriado | Obtenha o token pelo fluxo. Para devolver um cliente desbloqueado: `docker exec redis redis-cli FCALL tv30_client_add_authorized 0 <clientid>` |
| 300 | Nenhum serviço selecionado, nas rotas que o exigem | Selecione um serviço no catálogo |
| 304 em `/tv3/<scid>/users/<userid>` | O serviço do caminho não foi anunciado | Use o `globalServiceId` de um serviço de `services:announced`. A lista vazia indica o bcast parado |
| 104 | Sem o cabeçalho `bind-token` | Mande o bind-token assinado pela emissora |
| 108 | O bind-token não foi assinado por uma chave registrada para o contexto de serviço da rota | A emissora registra a chave pela C.6.8.2, no serviço corrente |
| 200, `Platform resource unavailable` | O tv3ws não respondeu em 2 s, ou está fora do ar ([Repasse ao serviço](../borda-credenciais/#repasse-ao-serviço)) | `docker logs tv3ws`. Uma rota que precise de mais tempo declara `timeout` próprio no `routes.json` |

O cliente local associado dispensa o bind-token só no contexto do serviço que o lançou. Em `warn`, o
107, o 104 e o 108 viram o aviso `X-TV30-Auth-Warn`, e a requisição passa.

### O QR code ou o PIN some antes da hora, ou fica na tela

| Sintoma | Causa | O que fazer |
|---|---|---|
| Some antes do fim do pareamento | Passaram os 120 s da trava | Se o cliente já leu o código, o pareamento continua valendo: a tentativa não expira. Se não leu, repita o `/tv3/authorize` |
| Fica na tela depois do `/tv3/token` | O `/tv3/token` não concluiu o pareamento (102, com o desafio errado), ou o tv3ws reiniciou no meio, ou o pop-up é de outro cliente | A trava fecha em 120 s. No fim do pareamento, o log do tv3ws mostra `Closing QRCode popup` ou `Closing PIN popup` |

O desafio errado não encerra a tentativa: o mesmo desafio pode ser respondido de novo. As tentativas
pendentes ficam só na memória do tv3ws, e `docker compose restart tv3ws` as descarta.

### A 44643 recusa o certificado, ou o dispositivo remoto não abre o `wss://`

O certificado do receptor é autoassinado e vale só para `localhost` e `127.0.0.1`.

- **`curl`:** `curl -k`, ou `--cacert .tv30/tls/cert.pem`. Por outro endereço, o nome não confere, e
  só o `-k` resolve.
- **Dispositivo remoto:** confie no certificado nele, ou `TV3WS_WS_TLS=false` no `.env` e
  `docker compose up -d tv3ws`.
- **Outro certificado:** `cert.pem` e `key.pem` em `.tv30/tls`, e recrie a stack.

### A superfície externa fora da 44643

O `/manifest` anuncia a porta de `EDGE_HTTPS_PORT`, que é 44643 por padrão. Com outra porta fixa em
`EDGE_EXT_PUBLISH`, defina o mesmo número em `EDGE_HTTPS_PORT` e recrie a borda e o tv3ws. Só o
número, sem porta de host, põe a externa numa porta escolhida pelo Docker, que o `/manifest` não
anuncia.

## Broker

### `errors/<client_id>`

| Sintoma | Causa | O que fazer |
|---|---|---|
| `INVALID_JSON` num payload que parece JSON | O plugin aceita exatamente um texto JSON: sobra depois do valor, NUL, comentário, aspas simples e vírgula sobrando são recusados | Mande só o JSON |
| Texto recusado num tópico de texto (`aop/currentUser`, as camadas) | Um payload que é JSON (`42`, `true`, `{"id":"x"}`) vale como esse valor, e não como texto | Mande o texto sem formar JSON |
| `"truncated":true` | A mensagem tem no máximo 2047 bytes, e um campo foi cortado | O `topic` e o `details` dizem a recusa |
| `�` no payload | Um byte que não formava UTF-8 | Confira a codificação de quem publica |
| A mensagem não chega em `errors/<meu client_id>` | `+`, `#`, `/` e controles do `client_id` viram `_` no tópico | Assine `errors/#` |

## Defeitos conhecidos

Defeitos a corrigir, com o contorno até lá.

| Defeito | Contorno |
|---|---|
| A página companion do webmedia não se registra como dispositivo remoto com a borda em `enforce`: chama a 44642 sem credencial e recebe 107 | Suba a borda com `AUTH_ENFORCE=warn` para a demonstração do webmedia |
| O OpenAPI da superfície externa, na documentação Swagger, diz 44643 em qualquer configuração, e o "Try it out" não chega à borda com outra porta ([Infra#3](https://github.com/multisens/Infra/issues/3)) | Mantenha o padrão, `EDGE_EXT_PUBLISH=44643:44643` |
| O anunciante caído não é percebido: a descoberta para, e a stack continua de pé sem aviso ([TV30#3](https://github.com/multisens/TV30/issues/3)) | `./tv30 status`, e `./tv30 up` o sobe de novo |
| O certificado do receptor vale só para `localhost` e `127.0.0.1` ([Infra#4](https://github.com/multisens/Infra/issues/4)) | `curl -k`, ou um certificado próprio ([A 44643 recusa o certificado](#a-44643-recusa-o-certificado-ou-o-dispositivo-remoto-não-abre-o-wss)) |

## Inspecionar o estado

```bash
# Redis
docker exec redis redis-cli SMEMBERS users:index
docker exec redis redis-cli HGETALL user:<id>
docker exec redis redis-cli GET session:current-service-id   # vazio = nenhum
docker exec redis redis-cli HGETALL origins:associated
docker exec redis redis-cli SMEMBERS services:announced
docker exec redis redis-cli SMEMBERS clients:authorized
docker exec redis redis-cli FCALL_RO tv30_audit 0            # vazio = ok

# MQTT
docker exec mqtt-broker mosquitto_sub -t '#' -v

# Logs
docker logs aop --tail 50
docker logs tv3ws --tail 50
docker logs mqtt-broker --tail 50
```

O Redis Commander está em `docker port redis 18081`, com usuário `admin` e senha
`tv30-redis-admin`, salvo o `.env`.

| Sintoma | Causa | O que fazer |
|---|---|---|
| O container `redis` reiniciou, e o log diz `commander (pid <n>) died` | O Redis Commander caiu e derrubou o container, que volta sozinho | Nada. Se a linha disser `redis-server`, foi o banco que caiu |
| O login padrão é recusado | O `.env` define outro usuário ou outra senha | `docker exec redis printenv REDIS_COMMANDER_USER REDIS_COMMANDER_PASSWORD`. Depois de mudar o `.env`, `docker compose up -d redis` |
