---
title: Instalação
parent: Primeiros passos
nav_order: 1
---

# Instalação

## Pré-requisitos

- **Docker + Docker Compose v2**
- **Git** com suporte a submódulos. Chave SSH no GitHub não é mais necessária: desde 11/10 (C5, decisão do Luís) os quatro submódulos vêm por HTTPS (ver [Submódulos](#submódulos))
- **Node.js**, só para rodar os testes de unidade ou um módulo fora do Docker ([Como testar]({{ site.baseurl }}/como-testar), [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local))

---

## Linux nativo

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
cd TV30
cp .env.example .env       # ativa profiles "linux" e "mqtt"
docker compose up -d
```

Acesse `http://localhost:8080`.

> **Importante:** sem o `.env` (ou sem `COMPOSE_PROFILES=mqtt,linux` definido de alguma forma), o receptor não sobe. O `aop`, o `tv3ws`, o `bcast` e o `sysctl-init` têm `profiles: ["linux"]`, e o `mosquitto` tem `["mqtt"]` (`docker-compose.yml` e `infra/docker-compose.yml`); sem o perfil ativo, eles ficam fora do `up`. Sobem só o `redis`, a borda (`edgegateway`) e as tarefas `tv30-preflight` e `tv30-userfiles-seed`.

### Imagens publicadas ou código do clone

Com o `.env.example`, o compose usa as imagens publicadas no Docker Hub (`DOCKERHUB_NS=labmultisens`, `IMAGE_TAG=latest`). O CI de cada submódulo constrói e publica a imagem dele a cada push na `main`, com as tags `latest` e o hash do commit. A `latest` pode, portanto, estar atrás do código do seu clone, com commits ainda não enviados ou enviados depois da última publicação.

- Para rodar o código do clone: `docker compose up -d --build`, ou `docker compose build <serviço>` e depois `docker compose up -d`.
- Sem `DOCKERHUB_NS` e `IMAGE_TAG` no `.env`, os nomes padrão do compose são `tv30/tv30-<módulo>:dev` (aop, tv3ws e bcast) e `tv30/tv30-<componente>:latest` (borda, broker e Redis). Eles não existiam no Docker Hub em 10/10, e, sem a imagem no registro, o compose a constrói a partir do código, pela seção `build` de cada serviço.

### O que não vem no clone

- **Os segmentos de vídeo do bcast.** Os `.ts`, `.m3u8` e `.mp4` de `bcast/public/` estão no `bcast/.gitignore`; das pastas `bcast/public/hls/<nome>/`, o repositório só traz o `events.json`. Os segmentos são preparados fora da stack, a partir de um vídeo, com `bcast/scripts/ffmpeg-hls.sh` ou `ffmpeg-dash.sh` (precisam de FFmpeg). A `bcast/public/` é montada no container (`docker-compose.yml`), e o que estiver nela é servido sem rebuild.
- **O HTTPS do tv3ws.** A superfície externa da borda (44643, no container e no host; ver [Portas](#portas)) repassa ao HTTPS do tv3ws (`https://tv3ws:44653`), que só sobe com `HTTPS_KEY` e `HTTPS_CERT` no `tv3ws/.env` (o `tv3ws/.env.example` os traz vazios). Sem eles, as rotas que a borda repassa pela 44643 respondem 404 `{"error":200}`; a 44642 funciona normalmente. O passo a passo para gerar o certificado está na seção [*(Opcional) Habilitando HTTPS no tv3ws*](https://github.com/multisens/TV30/blob/main/README.md#opcional-habilitando-https-no-tv3ws) do `README.md` da raiz.

### Descoberta SSDP (opcional)

Para que outro aparelho da rede encontre o receptor por SSDP (C.3.4), ligue o override `docker-compose.ssdp.yml`: ele põe a borda (`edgegateway`) em rede do host e liga o anunciante dela (L6, opção A, decidido pelo Luís em 09/10). A descoberta só é suportada em Linux nativo com Docker Engine (decisão do Joel, informada pelo Luís em 04/10); nesse ambiente, ela foi validada com um segundo aparelho em 09/10, primeiro com a opção B, anterior, e depois com a opção A (um notebook no mesmo Wi-Fi, testes 40 a 43 das [Medições da descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao)). No `.env` da raiz:

```bash
COMPOSE_FILE=docker-compose.yml:docker-compose.ssdp.yml
SSDP_ADVERTISE_HOST=192.168.0.12   # IP desta máquina na rede local (obrigatório)
#SSDP_INTERFACE=wlan0              # só se a interface escolhida sozinha estiver errada
```

O `SSDP_ADVERTISE_HOST` é obrigatório com o override (B2, decisão do Luís em 11/10): sem ele, o `tv30-preflight` para a subida com a mensagem `ERRO: o anuncio SSDP esta ligado (docker-compose.ssdp.yml) e falta SSDP_ADVERTISE_HOST`, e a borda não sobe. O `LOCATION` anunciado é esse valor, fixo: numa troca de rede, atualize o `.env` e rode `docker compose up -d` de novo.

Depois, `docker compose up -d`, e libere a UDP 1900 e a TCP 44642 no firewall. Com o override, a borda ocupa a 44642, a 44643 e a 8085 direto no host (a 8085 só é fixa nesse modo), e um erro de configuração do anúncio (UDP 1900 ocupada sem `SO_REUSEADDR`, `SSDP_INTERFACE` inexistente) derruba a borda inteira até o `restart` trazê-la de volta; a falta de rede não a derruba, e o anunciante espera e tenta de novo (morre-inteiro decidido pelo Luís em 09/10, revisto por ele em 10/10). Sem o override, nada é anunciado, e o cliente chega pelo IP (`http://<IP>:44642/manifest`). Quem usava o perfil `ssdp` (opção B) remove o container antigo com `docker rm -f tv3ws-ssdp`; o perfil deixou de existir. O passo a passo da verificação, com um segundo aparelho, está em [Descoberta SSDP]({{ site.baseurl }}/ssdp#o-que-exige-rede-doméstica-e-um-segundo-dispositivo).

---

## Windows + WSL2

### Configuração do WSL2

Edite `~/.wslconfig` no Windows (use o caminho `%USERPROFILE%\.wslconfig`):

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
vmIdleTimeout=86400000
```

**Importante:** **não use** `networkingMode=mirrored`. Mirrored + Docker tem problemas conhecidos de NAT/iptables que impedem o host de alcançar as portas dos containers.

Depois de editar:

```powershell
wsl --shutdown
```

E reabra a distribuição.

### Verificação

```powershell
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 8080 }
```

Com a stack de pé, deve mostrar a porta 8080 em `127.0.0.1` (e em `::1`), com estado `Listen` (conferido em 12/10 nesta máquina do projeto).

### Subindo a stack

Dentro do WSL:

```bash
cd /mnt/d/Proj_CEFET/TV30  # ou onde clonou
cp .env.example .env       # ativa profiles "linux" e "mqtt"
docker compose up -d
```

Até 11/10, com a 9001 e a 9002 ocupadas pelo Hyper-V, era preciso definir `MQTT_WS_PORT=9003` no `.env`. Não é mais: a página da TV conecta no MQTT pelo próprio AoP (`ws://localhost:8080/mqtt`), e a 9001 do Mosquitto sai numa porta que o Docker escolhe (C1, decisão do Luís em 11/10; ver [Portas](#portas)). Para quem roda o AoP fora do Docker no Windows, há uma opção, que não é regra, para fixá-la em 9003: [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local#aop-fora-do-docker-no-windows-opção).

> **Descoberta SSDP no WSL2:** deixe o `COMPOSE_FILE` do `.env` comentado. Anunciado em rede do host, o anúncio não sai da máquina: chega ao próprio Windows e não chega aos outros aparelhos da rede (medido em 03 e 04/10 com um anunciante descartável em modo host; com a borda anunciando, não medido; [Medições da descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao)). O Docker Desktop, que também roda o Docker numa VM, fica fora do suporte (não medido). Nesses ambientes, o cliente chega ao receptor pelo IP, sem a etapa de descoberta.

---

## Configurações via `.env`

O `.env` da raiz (cópia do `.env.example`, que explica cada variável) controla os padrões da stack. O `.env` não vai para o repositório (`.gitignore`). As variáveis, com o valor do `.env.example`:

| Variável | Valor no `.env.example` | Para quê |
|---|---|---|
| `COMPOSE_PROFILES` | `mqtt,linux` | Liga o broker, o AoP, o tv3ws, o bcast e o `sysctl-init`. Sem ela, o receptor não sobe |
| `COMPOSE_FILE` | comentada | `docker-compose.yml:docker-compose.ssdp.yml` liga a descoberta SSDP (só Linux nativo; [Descoberta SSDP]({{ site.baseurl }}/ssdp)) |
| `DOCKERHUB_NS`, `IMAGE_TAG` | `labmultisens`, `latest` | Nome e tag das imagens (ver *Imagens publicadas ou código do clone*, acima) |
| `EDGE_EXT_PUBLISH` | comentada (padrão `44643:44643`) | O que vai em `ports` para a superfície externa da borda. O padrão a fixa na 44643 do host desde 12/10; só o número (`44643`) a põe numa porta escolhida pelo Docker, que o `/manifest` não anuncia (ver [Portas](#portas)) |
| `BCAST_PUBLISH`, `MQTT_WS_PUBLISH` | comentadas (padrões `8081` e `9001`) | O que vai em `ports` para o bcast e o WebSocket do Mosquitto. Só o número (o padrão) = a porta do container numa porta de host escolhida pelo Docker; `host:container` fixa (ver [Portas](#portas)) |
| `AOP_PUBLIC_PORT` | comentada (padrão `8080`) | Porta do AoP no host, fixa, e das origens das aplicações de emissora; por ela passa também o MQTT por WebSocket da página da TV (`/mqtt`) |
| `APPS_DOMAIN` | comentada (padrão `apps.localhost`) | Domínio dos hosts próprios das aplicações de emissora. `*.localhost` só resolve para a própria máquina de quem abre a tela do AoP |
| `EDGE_VARIANT` | `linux` | Onde a borda procura o tv3ws: `linux` (container) ou `windows` (o tv3ws no host; [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local)) |
| `JWT_SECRET`, `JWT_ISSUER` | comentadas | Segredo e emissor do access token, o mesmo valor para o tv3ws e a borda. Sem elas, valem os padrões de desenvolvimento do compose; troque fora do laboratório |
| `AUTH_ENFORCE` | comentada (padrão `warn`) | `warn` só avisa; `enforce` recusa a credencial inválida ([Borda e credenciais]({{ site.baseurl }}/borda-credenciais)) |
| `REDIS_COMMANDER_USER`, `REDIS_COMMANDER_PASSWORD` | comentadas (padrões `admin` e `tv30-redis-admin`) | Login da interface do redis-commander. A conexão com o banco (6379) segue sem senha |
| `SERVER_URL` | `localhost` | Host que aparelhos externos usam para abrir os WebSockets de remote-device; numa rede de verdade, o IP desta máquina |
| `SSDP_ADVERTISE_HOST`, `SSDP_INTERFACE` | comentadas | Host e interface do anúncio SSDP. O `SSDP_ADVERTISE_HOST` é obrigatório com o `docker-compose.ssdp.yml` (B2) |
| `WEBMEDIA_REMOTE_MEDIA_PATH`, `WEBMEDIA_REMOTE_USERFILES_PATH` | comentadas | Caminhos no dispositivo remoto do demo webmedia |

Saíram do `.env.example` em 11/10 o `BCAST_PORT` e o `MQTT_WS_PORT`: o compose não os lê mais, e um `.env` antigo com eles não muda nada (o `BCAST_PUBLISH` e o `MQTT_WS_PUBLISH` fazem o papel de antes, agora com porta aleatória por padrão).

### Portas

Política decidida pelo Luís em 11/10 (C1, opção b) e revista por ele em 12/10 num ponto: a 44643 ficou fixa também na bridge. A norma só fixa a 44642 (C.3.4); o resto é decisão do projeto.

| Fixas no host | Escolhidas pelo Docker a cada criação do container |
|---|---|
| 44642 (superfície interna da borda), 44643 (superfície externa da borda; na bridge, desde 12/10), a do AoP (8080, `AOP_PUBLIC_PORT`), 1883 (MQTT), 6379 (Redis), 45000–45199 (WebSockets de remote-device) e, com o `docker-compose.ssdp.yml`, a 8085 da borda | a 8081 do bcast, a 9001 (MQTT por WebSocket) do Mosquitto, a 8085 da documentação da borda na bridge e a 18081 do redis-commander |

Para achar a porta de host de uma delas, na raiz do clone: `docker compose port <serviço> <porta do container>`, por exemplo `docker compose port bcast 8081` ou `docker compose port mosquitto 9001`; ou `docker compose ps`, que mostra todas. Para fixar uma delas, defina no `.env` `BCAST_PUBLISH` ou `MQTT_WS_PUBLISH` como `host:container` (por exemplo, `BCAST_PUBLISH=8081:8081`) e recrie o serviço (`docker compose up -d <serviço>`).

A 44643 fica fixa porque o `/manifest` do tv3ws anuncia o `Server-SecureBaseURL` em `<host>:<EDGE_HTTPS_PORT>`, com padrão 44643 (`tv3ws/src/ssdp-config.ts`), e não sabe a porta de host que o Docker escolheria. O `EDGE_EXT_PUBLISH` (padrão `44643:44643`, `infra/docker-compose.yml`) muda isso: outra porta de host fixa (por exemplo, `EDGE_EXT_PUBLISH=44743:44643`) pede também `EDGE_HTTPS_PORT=44743` no `.env` da raiz, que o tv3ws lê pelo `env_file`, senão o `/manifest` anuncia a 44643; só o número (`EDGE_EXT_PUBLISH=44643`, o padrão de 11/10 a 12/10) põe a 44643 numa porta escolhida pelo Docker (`docker compose port edgegateway 44643`), que o `/manifest` não anuncia. Quanto às portas, o `tv30-preflight` avisa, sem bloquear, quando a 1883, a 6379, a 44643 ou a do AoP já estão ocupadas no host, e só para a subida quando a 44642 está ocupada por outro processo (`scripts/preflight.sh`).

---

## Submódulos

### Clone inicial

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
```

> **Clone antigo (anterior ao renome `ccws` → `tv3ws`):** o `git pull` não propaga renome de submódulo para um clone que já existe — o `ccws/` continua lá e o `tv3ws/` não fica registrado como submódulo inicializado (`git submodule status` mostra `-` na frente). Corrija com
>
> ```bash
> git submodule sync --recursive && git submodule update --init --recursive
> rm -rf ccws    # sobra do nome antigo (antes, confira que nao ha trabalho local nela)
> ```
>
> ou clone de novo.

> **URL do bcast por HTTPS (C5, decisão do Luís em 11/10):** o `.gitmodules` aponta o submódulo `bcast` para `https://github.com/multisens/BcastService.git`, como os outros três, e o clone não pede chave SSH. Até 11/10 a URL era SSH (`git@github.com:multisens/BcastService.git`), e sem chave cadastrada no GitHub o clone desse submódulo falhava. Num clone feito antes, o `git pull` traz o `.gitmodules` novo, mas a URL antiga fica no `.git/config`; atualize com
>
> ```bash
> git submodule sync --recursive && git submodule update --init --recursive
> ```

### Atualizar todos para o último commit

```bash
git submodule update --remote
```

### Atualizar apenas um

```bash
git submodule update --remote aop
```

### Status

```bash
git submodule status
```

---

## Próximos passos

- [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local): a infraestrutura em containers e um módulo com `npm run dev`
- [Como testar]({{ site.baseurl }}/como-testar): os testes de unidade e as suítes de `scripts/`
- [Glossário]({{ site.baseurl }}/glossario): os termos do código e da norma
- [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis): as chaves, e como o gestor de perfis do AoP cria um perfil (o primeiro teste à mão: criar um perfil pelo formulário do AoP e ver as chaves no Redis)
- [Solução de problemas]({{ site.baseurl }}/troubleshooting): caso algo dê errado
