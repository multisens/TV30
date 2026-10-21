---
title: Instalação
parent: Primeiros passos
nav_order: 1
---

# Instalação

## Pré-requisitos

- **Docker + Docker Compose v2**
- **Git** com suporte a submódulos. Os quatro submódulos vêm por HTTPS, sem chave SSH no GitHub (ver [Submódulos](#submódulos))
- **Node.js**, só para rodar os testes de unidade ou um módulo fora do Docker ([Como testar]({{ site.baseurl }}/como-testar), [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local))

---

## Linux nativo

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
cd TV30
cp .env.example .env       # ativa profiles "linux" e "mqtt"
./tv30 up                  # docker compose up -d + anunciante SSDP
```

Acesse `http://localhost:8080`. Para descer: `./tv30 down`. Só `docker compose up -d` também funciona, sem a descoberta SSDP.

> **Importante:** sem o `.env` (ou sem `COMPOSE_PROFILES=mqtt,linux` definido de alguma forma), o receptor não sobe. O `aop`, o `tv3ws`, o `bcast` e o `sysctl-init` têm `profiles: ["linux"]`, e o `mosquitto` tem `["mqtt"]` (`docker-compose.yml` e `infra/docker-compose.yml`); sem o perfil ativo, eles ficam fora do `up`. Sobem só o `redis`, a borda (`edgegateway`) e as tarefas `tv30-preflight`, `tv30-userfiles-seed` e `tv30-tls-init`.

### Imagens publicadas ou código do clone

Com o `.env.example`, o compose usa as imagens publicadas no Docker Hub (`DOCKERHUB_NS=labmultisens`, `IMAGE_TAG=latest`). O CI de cada submódulo constrói e publica a imagem dele a cada push na `main`, com as tags `latest` e o hash do commit. A `latest` pode, portanto, estar atrás do código do seu clone, com commits ainda não enviados ou enviados depois da última publicação.

- Para rodar o código do clone: `docker compose up -d --build`, ou `docker compose build <serviço>` e depois `docker compose up -d`.
- Sem `DOCKERHUB_NS` e `IMAGE_TAG` no `.env`, os nomes padrão do compose são `tv30/tv30-<módulo>:dev` (aop, tv3ws e bcast) e `tv30/tv30-<componente>:latest` (borda, broker e Redis). Sem a imagem no registro, o compose a constrói a partir do código, pela seção `build` de cada serviço.

### O que não vem no clone

- **Os segmentos de vídeo do bcast.** Os `.ts`, `.m3u8` e `.mp4` de `bcast/public/` estão no `bcast/.gitignore`; das pastas `bcast/public/hls/<nome>/`, o repositório só traz o `events.json`. Os segmentos são preparados fora da stack, a partir de um vídeo, com `bcast/scripts/ffmpeg-hls.sh` ou `ffmpeg-dash.sh` (precisam de FFmpeg). A `bcast/public/` é montada no container (`docker-compose.yml`), e o que estiver nela é servido sem rebuild.

### Certificado e descoberta

Duas coisas acontecem sozinhas na subida:

- **Certificado do receptor.** O serviço `tls-init` gera em `.tv30/tls` um certificado autoassinado, usado no TLS da 44643, no HTTPS interno do tv3ws, no `serverCert` do pareamento e nos `wss://` do remote-device ([HTTPS](https://github.com/multisens/TV30/blob/main/README.md#https) no `README.md` da raiz).
- **Descoberta SSDP (C.3.4).** O `./tv30 up` compila e sobe, no host e fora do Docker, o anunciante de `infra/edgegateway/ssdp/`, com o IP da máquina detectado. Libere a UDP 1900 e a TCP 44642 no firewall. Arranjo e permissões em [Descoberta SSDP]({{ site.baseurl }}/ssdp).

---

## macOS

O Docker roda numa VM (Docker Desktop, Colima ou outro); o anunciante SSDP roda fora dela, pelo `./tv30 up`, como no Linux. Em Apple Silicon, as imagens do Docker Hub são `amd64`, e a borda não roda emulada: construa as imagens com `docker compose build` antes do `./tv30 up` (a borda escolhe o Go pela arquitetura, `infra/edgegateway/Dockerfile`). O terminal precisa da permissão de Rede Local para o anúncio sair (Ajustes > Privacidade e Segurança > Rede Local).

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

Com a stack de pé, deve mostrar a porta 8080 em `127.0.0.1` (e em `::1`), com estado `Listen`.

### Subindo a stack

Dentro do WSL:

```bash
cd /mnt/d/Proj_CEFET/TV30  # ou onde clonou
cp .env.example .env       # ativa profiles "linux" e "mqtt"
docker compose up -d
```

Nenhuma porta precisa mudar no Windows: a página da TV conecta no MQTT pelo próprio AoP (`ws://localhost:8080/mqtt`), e a 9001 do Mosquitto sai numa porta que o Docker escolhe (ver [Portas](#portas)). Para quem roda o AoP fora do Docker no Windows, há uma opção, que não é regra, para fixá-la em 9003: [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local#aop-fora-do-docker-no-windows-opção).

> **Descoberta SSDP no Windows:** de dentro do WSL2, o anúncio não sai da máquina. O anunciante tem de rodar no Windows: `.\tv30.ps1 up`, no PowerShell, na raiz do clone. Sem `docker` no PowerShell, o script chama o do WSL (`wsl docker compose`). Não medido no Windows: se outro aparelho da rede recebe o anúncio ([Descoberta SSDP]({{ site.baseurl }}/ssdp)) e alcança as portas que o Docker do WSL2 publica (44642, 44643), que o WSL2 em NAT só repassa ao `localhost` do Windows.

---

## Configurações via `.env`

O `.env` da raiz (cópia do `.env.example`, que explica cada variável) controla os padrões da stack. O `.env` não vai para o repositório (`.gitignore`). As variáveis, com o valor do `.env.example`:

| Variável | Valor no `.env.example` | Para quê |
|---|---|---|
| `COMPOSE_PROFILES` | `mqtt,linux` | Liga o broker, o AoP, o tv3ws, o bcast e o `sysctl-init`. Sem ela, o receptor não sobe |
| `DOCKERHUB_NS`, `IMAGE_TAG` | `labmultisens`, `latest` | Nome e tag das imagens (ver *Imagens publicadas ou código do clone*, acima) |
| `EDGE_EXT_PUBLISH` | comentada (padrão `44643:44643`) | O que vai em `ports` para a superfície externa da borda. O padrão a fixa na 44643 do host; só o número (`44643`) a põe numa porta escolhida pelo Docker, que o `/manifest` não anuncia (ver [Portas](#portas)) |
| `BCAST_PUBLISH`, `MQTT_WS_PUBLISH` | comentadas (padrões `8081` e `9001`) | O que vai em `ports` para o bcast e o WebSocket do Mosquitto. Só o número (o padrão) = a porta do container numa porta de host escolhida pelo Docker; `host:container` fixa (ver [Portas](#portas)) |
| `AOP_PUBLIC_PORT` | comentada (padrão `8080`) | Porta do AoP no host, fixa, e das origens das aplicações de emissora; por ela passa também o MQTT por WebSocket da página da TV (`/mqtt`) |
| `APPS_DOMAIN` | comentada (padrão `apps.localhost`) | Domínio dos hosts próprios das aplicações de emissora. `*.localhost` só resolve para a própria máquina de quem abre a tela do AoP |
| `EDGE_VARIANT` | `linux` | Onde a borda procura o tv3ws: `linux` (container) ou `windows` (o tv3ws no host; [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local)) |
| `JWT_SECRET`, `JWT_ISSUER` | comentadas | Segredo e emissor do access token, o mesmo valor para o tv3ws e a borda. Sem elas, valem os padrões de desenvolvimento do compose; troque fora do laboratório |
| `AUTH_ENFORCE` | comentada (padrão `enforce`) | `enforce` recusa a credencial inválida; `warn`, opção transitória, só avisa nas recusas de credencial (104, 107, 108) ([Borda e credenciais]({{ site.baseurl }}/borda-credenciais)) |
| `REDIS_COMMANDER_USER`, `REDIS_COMMANDER_PASSWORD` | comentadas (padrões `admin` e `tv30-redis-admin`) | Login da interface do redis-commander. A conexão com o banco (6379) segue sem senha |
| `SERVER_URL` | `localhost` | Host que aparelhos externos usam para abrir os WebSockets de remote-device; numa rede de verdade, o IP desta máquina |
| `TV3WS_WS_TLS` | comentada (padrão: `wss://`) | `false` = WebSockets de remote-device em `ws://` |
| `SSDP_ENABLED`, `SSDP_ADVERTISE_HOST`, `SSDP_INTERFACE` | comentadas | Liga o anunciante (padrão `true`), fixa o host do anúncio e do `/manifest` (sobreposição; sem ele, o IP detectado) e força a interface |
| `WEBMEDIA_REMOTE_MEDIA_PATH`, `WEBMEDIA_REMOTE_USERFILES_PATH` | comentadas | Caminhos no dispositivo remoto do demo webmedia |

### Portas

A norma só fixa a 44642 (C.3.4); as demais portas fixas são decisão do projeto.

| Fixas no host | Escolhidas pelo Docker a cada criação do container |
|---|---|
| 44642 (superfície interna da borda, HTTP), 44643 (superfície externa da borda, HTTPS), a do AoP (8080, `AOP_PUBLIC_PORT`), 1883 (MQTT), 6379 (Redis, só em `127.0.0.1`), 45000–45199 (WebSockets de remote-device) e a UDP 1900 do anunciante SSDP, no host | a 8081 do bcast, a 9001 (MQTT por WebSocket) do Mosquitto, a 8085 da documentação da borda e a 18081 do redis-commander |

Para achar a porta de host de uma delas, na raiz do clone: `docker compose port <serviço> <porta do container>`, por exemplo `docker compose port bcast 8081` ou `docker compose port mosquitto 9001`; ou `docker compose ps`, que mostra todas. Para fixar uma delas, defina no `.env` `BCAST_PUBLISH` ou `MQTT_WS_PUBLISH` como `host:container` (por exemplo, `BCAST_PUBLISH=8081:8081`) e recrie o serviço (`docker compose up -d <serviço>`).

A 44643 fica fixa porque o `/manifest` do tv3ws anuncia o `Server-SecureBaseURL` em `<host>:<EDGE_HTTPS_PORT>`, com padrão 44643 (`secureBaseURL`, em `tv3ws/src/ssdp-config.ts`), e não sabe a porta de host que o Docker escolheria. O `EDGE_EXT_PUBLISH` (padrão `44643:44643`, `infra/docker-compose.yml`) muda isso: outra porta de host fixa (por exemplo, `EDGE_EXT_PUBLISH=44743:44643`) pede também `EDGE_HTTPS_PORT=44743` no `.env` da raiz, que o tv3ws lê pelo `env_file`, senão o `/manifest` anuncia a 44643; só o número (`EDGE_EXT_PUBLISH=44643`) põe a 44643 numa porta escolhida pelo Docker (`docker compose port edgegateway 44643`), que o `/manifest` não anuncia. Quanto às portas, o `tv30-preflight` avisa, sem bloquear, quando a 1883, a 6379, a 44643 ou a do AoP já estão ocupadas no host, e só para a subida quando a 44642 está ocupada por outro processo (`scripts/preflight.sh`).

---

## Submódulos

### Clone inicial

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
```

> **Submódulo sem inicializar ou com URL desatualizada** (`git submodule status` mostra `-` na frente, ou o clone de um submódulo pede chave SSH): o `git pull` traz o `.gitmodules`, mas a URL gravada no `.git/config` não muda sozinha. Corrija com
>
> ```bash
> git submodule sync --recursive && git submodule update --init --recursive
> ```
>
> ou clone de novo.

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
