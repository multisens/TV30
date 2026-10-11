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

O one-shot `preflight` do compose imprime, antes da subida, quem esta
segurando cada porta do stack — se a subida falhar por bind, a causa ja
esta nomeada no inicio do log.

### `preflight`: "a porta 44642 esta ocupada (-)" com a stack de pé

Até 02/10/2026, um segundo `docker compose up -d` com a stack já de pé parava
no preflight com essa mensagem. O container do preflight não tem
`CAP_SYS_PTRACE`, então o `netstat` dele não enxerga que o dono da 44642 é o
`docker-proxy` e mostra `-`. O `scripts/preflight.sh` atual reconhece o
`docker-proxy` pela linha de comando. Em clone antigo, atualize o
repositório. Se a mensagem continuar, há um processo nativo na 44642:
confira com `sudo ss -ltnp | grep 44642`.

## Redis não fica saudável e o tv3ws ou a borda não sobem

O antigo container de carga `redis-seed`, que rodava `pip install redis` na partida e falhava sem rede, não existe mais. Desde a consolidação do armazenamento (fase 3), a carga inicial vem na própria imagem `tv30-redis`: o seed é gerado no build (estágio `seedgen` do `infra/redis/Dockerfile`, em Python só com a biblioteca padrão) e aplicado pelo `infra/redis/entrypoint.sh` com `redis-cli --pipe`. A partida não instala nada nem precisa de rede.

O healthcheck do `redis` só passa depois da carga (chave `seed:done`, testada a cada 2 s, até 30 vezes; `infra/redis/docker-compose.yml`). O `tv3ws` e o `edgegateway` dependem dele com `condition: service_healthy`; o broker não depende do Redis. Para ver em que ponto a carga está: `docker logs redis`, que registra `[redis] aplicando carga inicial (redis-cli --pipe)...` e `[redis] carga concluida`, ou `[redis] carga ja aplicada (seed:done presente) — mantida`.

O seed sai do template `infra/user-files-template/userData.json` no build. Uma mudança no template só entra com a imagem reconstruída e, mesmo assim, só num volume `redis_data` que ainda não tenha `seed:done`: o entrypoint não reaplica a carga num volume já semeado.

Desde o P4 (decisão do Luís em 10/10), o healthcheck também exige que a biblioteca de funções `tv30` tenha carregado **nesta** partida (marca `/tmp/tv30-redis-pronto`, criada pelo entrypoint). No log aparece `[redis] biblioteca de funcoes tv30 carregada (esquema versao N)`. Se o log mostrar `ERRO: a biblioteca de funcoes tv30 NAO carregou`, o container encerra, porque sem as funções toda escrita dos serviços falharia. A causa é um `esquema.json` ou `funcoes.lua` quebrado numa imagem montada à mão: reconstrua a partir do repositório (`docker compose build redis`), já que o build confere a biblioteca. Se o log mostrar `ERRO: a carga inicial foi recusada pelo esquema`, um perfil do `userData.json` está fora do esquema: o log diz qual campo, `seed:done` não é gravado e o container fica *unhealthy*. Corrija o template e reconstrua a imagem.

## Erro `TV30ESQUEMA` numa resposta ou no log

```
TV30ESQUEMA tv30_perfil_grava: user:u2 campo parentalControl: deve ser "true" ou "false" (veio "False")
```

É uma função do Redis recusando uma escrita fora do esquema (P4, decisão do Luís em 10/10). A mensagem diz a função, a chave, o campo e o motivo, e nada foi gravado. Para o serviço, é defeito de quem grava. O tv3ws e o AoP respondem 404 `{"error":200}` com a mensagem no `description` e no log (`[error] <método> <url>: TV30ESQUEMA ...`). A borda responde com `escrita recusada pelo esquema do Redis (...)`. Um handler MQTT só loga (no tv3ws, `[mqtt] FALHA no handler de <tópico>`).

- **Veio de uma escrita do código:** o serviço montou um dado que o esquema não aceita. Compare a mensagem com a regra no `infra/redis/esquema.json` (o campo `fonte` diz de onde ela veio) e corrija quem grava, não a regra. Mudar a regra é decisão e vai registrada.
- **Veio de um script ou de uma chamada à mão (`FCALL`):** os argumentos estão fora do esquema. Os formatos de cada função estão em `infra/redis/README.md`.
- **`ERR Function not found`:** o Redis está sem a biblioteca. Pode ser uma imagem anterior ao P4 ou um Redis que não é o da stack. Reconstrua com `docker compose build redis && docker compose up -d redis`.

## Auditoria do Redis com achados

```bash
docker exec redis redis-cli FCALL_RO tv30_auditoria 0
```

Cada achado é `[chave, familia, motivo]`, e a auditoria vazia é o estado esperado. O `scripts/test-auth.sh` dá FAIL se ela não terminar vazia e avisa no começo se já havia achados antes da suíte. Causas comuns:

- **Volume de antes do P4.** A carga antiga gravava os booleanos como `"False"`/`"True"`, e o `lastAccess` avulso de antes de 05/10 deixava hashes `user:{id}` só com `lastAccess`, fora de `users:index` (por exemplo, `user:abc-123`). Para começar limpo, use `docker compose down -v`, que apaga o volume e com ele os perfis criados. A outra saída é corrigir ou apagar as chaves apontadas.
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

2. Force LF nesse tipo de arquivo via `.gitattributes` na raiz:
   ```
   *.sh   text eol=lf
   ```

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
| As chamadas da app às APIs levam `X-TV30-Auth-Warn: 107` | A origem da app não está em `origins:associated`: a app foi encerrada (ESC) ou trocada, e a página ficou aberta; ou a gravação no Redis falhou (log do AoP). Com uma imagem do AoP anterior a 11/10, a app aberta pelo caminho antigo `/graphicsAppProxy` ficava na origem do AoP, que não é gravada | Abra a app pelo AoP (catálogo e tela cheia); reconstrua o AoP se a imagem for anterior a 11/10 |

O QtWebEngine não foi testado com os nomes `*.apps.localhost`; o Firefox 154 (Linux) e o Chrome 154 (Windows) foram conferidos em 10/10.

## `POST` ou `DELETE /tv3/bind-context` dá 100 na 44643

É a regra da P1.9 (decisão do Luís em 10/10): a superfície externa (44643) só expõe as rotas que admitem o cliente não local, e essas duas são só do local associado. Use a superfície interna (44642). O `GET /tv3/bind-context` existe nas duas. Na 44643, a C.6.7.9 lista 18 APIs, e não 20, e a C.6.7.8 dá 101 para `tv3ws-bind-context-register` e `tv3ws-bind-context-remove`.

---

## Inspecionar estado do sistema

```bash
# Redis
docker exec redis redis-cli SMEMBERS users:index
docker exec redis redis-cli HGETALL user:user_xxx
docker exec redis redis-cli GET session:current-user
docker exec redis redis-cli HGETALL origins:associated   # origem da app em execucao -> servico
docker exec redis redis-cli FCALL_RO tv30_auditoria 0    # chaves fora do esquema (P4); vazio = ok
docker exec redis redis-cli FCALL_RO tv30_versao 0       # versao do esquema carregado

# MQTT
docker exec mqtt-broker mosquitto_sub -t '#' -v

# Logs
docker logs aop --tail 50
docker logs tv3ws --tail 50
docker logs mqtt-broker --tail 50
```

Redis Commander: a porta de host é dinâmica. `docker port redis 18081` mostra qual é, e a UI fica em `http://localhost:<porta>/`. A UI exige login: usuário `admin` e senha `tv30-redis-admin` por padrão, ou os valores de `REDIS_COMMANDER_USER`/`REDIS_COMMANDER_PASSWORD` no `.env` da raiz (D-L1, decidida pelo Luís em 03/10). A conexão com o banco (6379, `redis-cli`) segue sem senha.

## Redis Commander abre sem pedir login, ou o login padrão é recusado

- **Abre direto, sem formulário de login:** a imagem `tv30-redis` foi construída antes de 03/10, ou puxada do Docker Hub antes da publicação das imagens novas, e o entrypoint antigo ignora as variáveis. Reconstrua com `docker compose build redis && docker compose up -d redis`.
- **Login recusado com `admin`/`tv30-redis-admin`:** o `.env` da raiz define outro usuário ou outra senha. Para ver o valor em uso, rode `docker exec redis printenv REDIS_COMMANDER_USER REDIS_COMMANDER_PASSWORD`. Depois de mudar o `.env`, recrie o container com `docker compose up -d redis`, porque o valor só é lido na subida.
