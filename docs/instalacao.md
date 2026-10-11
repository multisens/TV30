---
title: Instalação
parent: Primeiros passos
nav_order: 1
---

# Instalação

## Pré-requisitos

- **Docker + Docker Compose v2**
- **Git** com suporte a submódulos
- **Chave SSH cadastrada no GitHub**, para o submódulo `bcast` (ver *URL SSH do bcast*, em [Submódulos](#submódulos))
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
- **O HTTPS do tv3ws.** A superfície externa da borda (44643) repassa ao HTTPS do tv3ws (`https://tv3ws:44653`), que só sobe com `HTTPS_KEY` e `HTTPS_CERT` no `tv3ws/.env` (o `tv3ws/.env.example` os traz vazios). Sem eles, as rotas que a borda repassa pela 44643 respondem 404 `{"error":200}`; a 44642 funciona normalmente. O passo a passo para gerar o certificado está na seção [*(Opcional) Habilitando HTTPS no tv3ws*](https://github.com/multisens/TV30/blob/main/README.md#opcional-habilitando-https-no-tv3ws) do `README.md` da raiz.

### Descoberta SSDP (opcional)

Para que outro aparelho da rede encontre o receptor por SSDP (C.3.4), ligue o override `docker-compose.ssdp.yml`: ele põe a borda (`edgegateway`) em rede do host e liga o anunciante dela (L6, opção A, decidido pelo Luís em 09/10). A descoberta só é suportada em Linux nativo com Docker Engine (decisão do Joel, informada pelo Luís em 04/10); nesse ambiente, ela foi validada com um segundo aparelho em 09/10, primeiro com a opção B, anterior, e depois com a opção A (um notebook no mesmo Wi-Fi, testes 40 a 43 das [Medições da descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao)). No `.env` da raiz:

```bash
COMPOSE_FILE=docker-compose.yml:docker-compose.ssdp.yml
SSDP_ADVERTISE_HOST=192.168.0.12   # IP desta máquina na rede local
#SSDP_INTERFACE=wlan0              # só se a interface escolhida sozinha estiver errada
```

Depois, `docker compose up -d`, e libere a UDP 1900 e a TCP 44642 no firewall. Com o override, a borda ocupa a 44642, a 44643 e a 8085 direto no host, e um erro de configuração do anúncio (UDP 1900 ocupada sem `SO_REUSEADDR`, `SSDP_INTERFACE` inexistente) derruba a borda inteira até o `restart` trazê-la de volta; a falta de rede não a derruba, e o anunciante espera e tenta de novo (morre-inteiro decidido pelo Luís em 09/10, revisto por ele em 10/10). Sem o override, nada é anunciado, e o cliente chega pelo IP (`http://<IP>:44642/manifest`). Quem usava o perfil `ssdp` (opção B) remove o container antigo com `docker rm -f tv3ws-ssdp`; o perfil deixou de existir. O passo a passo da verificação, com um segundo aparelho, está em [Descoberta SSDP]({{ site.baseurl }}/ssdp#o-que-exige-rede-doméstica-e-um-segundo-dispositivo).

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

Deve mostrar `127.0.0.1:8080` em LISTENING.

### Subindo a stack

Dentro do WSL:

```bash
cd /mnt/d/ProjCEFET/TV30   # ou onde clonou
cp .env.example .env       # ativa profiles "linux" e "mqtt"
# (edite .env e defina MQTT_WS_PORT=9003 se a 9001 estiver ocupada no host)
docker compose up -d
```

> **Descoberta SSDP no WSL2:** deixe o `COMPOSE_FILE` do `.env` comentado. Anunciado em rede do host, o anúncio não sai da máquina: chega ao próprio Windows e não chega aos outros aparelhos da rede (medido em 03 e 04/10 com um anunciante descartável em modo host; com a borda anunciando, não medido; [Medições da descoberta SSDP]({{ site.baseurl }}/ssdp-verificacao)). O Docker Desktop, que também roda o Docker numa VM, fica fora do suporte (não medido). Nesses ambientes, o cliente chega ao receptor pelo IP, sem a etapa de descoberta.

---

## Configurações via `.env`

O `.env` da raiz (cópia do `.env.example`, que explica cada variável) controla os padrões da stack. O `.env` não vai para o repositório (`.gitignore`). As variáveis, com o valor do `.env.example`:

| Variável | Valor no `.env.example` | Para quê |
|---|---|---|
| `COMPOSE_PROFILES` | `mqtt,linux` | Liga o broker, o AoP, o tv3ws, o bcast e o `sysctl-init`. Sem ela, o receptor não sobe |
| `COMPOSE_FILE` | comentada | `docker-compose.yml:docker-compose.ssdp.yml` liga a descoberta SSDP (só Linux nativo; [Descoberta SSDP]({{ site.baseurl }}/ssdp)) |
| `DOCKERHUB_NS`, `IMAGE_TAG` | `labmultisens`, `latest` | Nome e tag das imagens (ver *Imagens publicadas ou código do clone*, acima) |
| `MQTT_WS_PORT` | `9001` | Porta do WebSocket do broker no host, que o navegador da tela do AoP usa. No Windows com a 9001 e a 9002 ocupadas pelo Hyper-V, `9003` |
| `BCAST_PORT` | `8081` | Porta do bcast no host (dentro do container continua 8081) |
| `AOP_PUBLIC_PORT` | comentada (padrão `8080`) | Porta do AoP no host e das origens das aplicações de emissora |
| `APPS_DOMAIN` | comentada (padrão `apps.localhost`) | Domínio dos hosts próprios das aplicações de emissora. `*.localhost` só resolve para a própria máquina de quem abre a tela do AoP |
| `EDGE_VARIANT` | `linux` | Onde a borda procura o tv3ws: `linux` (container) ou `windows` (o tv3ws no host; [Desenvolvimento com serviço no host]({{ site.baseurl }}/dev-local)) |
| `JWT_SECRET`, `JWT_ISSUER` | comentadas | Segredo e emissor do access token, o mesmo valor para o tv3ws e a borda. Sem elas, valem os padrões de desenvolvimento do compose; troque fora do laboratório |
| `AUTH_ENFORCE` | comentada (padrão `warn`) | `warn` só avisa; `enforce` recusa a credencial inválida ([Borda e credenciais]({{ site.baseurl }}/borda-credenciais)) |
| `REDIS_COMMANDER_USER`, `REDIS_COMMANDER_PASSWORD` | comentadas (padrões `admin` e `tv30-redis-admin`) | Login da interface do redis-commander. A conexão com o banco (6379) segue sem senha |
| `SERVER_URL` | `localhost` | Host que aparelhos externos usam para abrir os WebSockets de remote-device; numa rede de verdade, o IP desta máquina |
| `SSDP_ADVERTISE_HOST`, `SSDP_INTERFACE` | comentadas | Host e interface do anúncio SSDP |
| `WEBMEDIA_REMOTE_MEDIA_PATH`, `WEBMEDIA_REMOTE_USERFILES_PATH` | comentadas | Caminhos no dispositivo remoto do demo webmedia |

No Windows com o Hyper-V ocupando a 9001 e a 9002, basta trocar no `.env` o `MQTT_WS_PORT` para `9003`; o resto fica como no `.env.example`.

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

> **URL SSH do bcast:** o `.gitmodules` aponta o submódulo `bcast` para `git@github.com:multisens/BcastService.git`. Sem chave SSH cadastrada no GitHub, o clone desse submódulo falha (a troca da URL ainda não foi decidida).

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
