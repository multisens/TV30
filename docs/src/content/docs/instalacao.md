---
title: Instalação
description: Pré-requisitos, cada sistema operacional, portas, variáveis do .env, HTTPS, descoberta na rede e submódulos.
---

Os comandos para subir e o que experimentar depois estão em
[Subir e passear pela TV](../subir-e-passear/). Esta página traz o que muda de um sistema para
outro e o que se pode configurar.

## Pré-requisitos

- **Docker** com **Docker Compose v2**.
- **Git**. Os quatro submódulos vêm por HTTPS, sem chave SSH ([Submódulos](#submódulos)).
- **Node.js**, só para rodar os testes de unidade ou um módulo fora do Docker
  ([Como testar](../como-testar/), [Desenvolvimento com serviço no host](../dev-local/)).

:::caution[Sem o `.env`, o receptor não sobe]
O `aop`, o `tv3ws`, o `bcast` e o broker só sobem com os perfis `mqtt` e `linux` do compose. O
`.env.example` já os liga (`COMPOSE_PROFILES=mqtt,linux`): copie-o para `.env` antes de subir. Sem
eles, sobem só o Redis e a borda.
:::

## Linux

`./tv30 up` sobe a stack (`docker compose up -d`) e o anunciante da
[descoberta na rede](#descoberta-na-rede). Só `docker compose up -d` também funciona, sem a
descoberta.

## macOS

O Docker roda numa VM (Docker Desktop, Colima ou outro). O anunciante roda fora dela, pelo
`./tv30 up`, como no Linux.

- **Apple Silicon:** as imagens do Docker Hub são `amd64`, e a borda não roda emulada. Rode
  `docker compose build` antes do primeiro `./tv30 up`.
- O terminal precisa da permissão de **Rede Local** (Ajustes > Privacidade e Segurança > Rede Local)
  para o anúncio sair.

## Windows com WSL2

1. Em `%USERPROFILE%\.wslconfig`:

   ```ini
   [wsl2]
   networkingMode=NAT
   localhostForwarding=true
   vmIdleTimeout=86400000
   ```

   **Não use** `networkingMode=mirrored`: com o Docker, o Windows deixa de alcançar as portas dos
   containers.

2. `wsl --shutdown` e reabra a distribuição.

3. Dentro do WSL, na raiz do clone:

   ```bash
   cp .env.example .env
   docker compose up -d
   ```

4. Confira, no PowerShell, que a 8080 está em `Listen`:

   ```powershell
   Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 8080 }
   ```

O anúncio na rede não sai de dentro do WSL2: o anunciante tem de rodar no Windows, com
`.\tv30.ps1 up` no PowerShell, na raiz do clone. Sem `docker` no PowerShell, o script usa o do WSL.
Não foi medido se outro aparelho da rede alcança as portas que o Docker do WSL2 publica: em NAT, o
WSL2 só as repassa ao `localhost` do Windows.

## Imagens publicadas ou código do clone

- Com o `.env.example`, o compose usa as imagens publicadas no Docker Hub (`DOCKERHUB_NS`,
  `IMAGE_TAG=latest`). A `latest` é o último build da `main` de cada submódulo e pode estar atrás do
  seu clone.
- Para rodar o código do clone: `docker compose up -d --build`.

## Portas e endereços

A norma fixa só a 44642 (C.3.4). As demais portas fixas são as que se digitam ou que o `/manifest`
anuncia; as outras saem numa porta escolhida pelo Docker, que muda quando o container é recriado.

| O quê | Porta no host | Para achar ou mudar |
|---|---|---|
| Tela do receptor (AoP) e aplicações de emissora | 8080 | `AOP_PUBLIC_PORT`. As aplicações abrem em `http://<app>.apps.localhost:8080/graphicsAppProxy/...`, e o MQTT da página da TV passa por `/mqtt` |
| APIs, superfície interna (HTTP) | 44642 | fixa pela norma |
| APIs, superfície externa (HTTPS) | 44643 | `EDGE_EXT_PUBLISH`; outra porta pede também `EDGE_HTTPS_PORT` igual, senão o `/manifest` anuncia a 44643 |
| WebSockets dos dispositivos remotos | 45000–45199 | — |
| Broker MQTT | 1883 | — |
| Broker MQTT por WebSocket | escolhida pelo Docker | `docker compose port mosquitto 9001`; `MQTT_WS_PUBLISH` fixa |
| Redis | 6379, só em `127.0.0.1` | sem senha |
| Redis Commander | escolhida pelo Docker | `docker port redis 18081`; login `admin`, senha `tv30-redis-admin` |
| Documentação Swagger das APIs | escolhida pelo Docker | `docker port edgegateway 8085` |
| bcast (aplicações e mídia, direto) | escolhida pelo Docker | `docker compose port bcast 8081`; `BCAST_PUBLISH` fixa |
| Anunciante da descoberta | UDP 1900 | fora do Docker |

`docker compose ps` mostra todas. Para fixar uma porta escolhida pelo Docker, defina a variável no
`.env` como `host:container` (por exemplo, `BCAST_PUBLISH=8081:8081`) e recrie o serviço
(`docker compose up -d bcast`).

Na subida, a stack avisa quando a 1883, a 6379, a 44643 ou a 8080 já estão ocupadas no host, e não
sobe se a 44642 estiver.

## Variáveis do `.env`

O `.env` da raiz é uma cópia do `.env.example`, que comenta cada variável. As que vêm comentadas
valem o padrão entre parênteses.

| Variável | Valor | Para quê |
|---|---|---|
| `COMPOSE_PROFILES` | `mqtt,linux` | Liga o broker, o AoP, o tv3ws e o bcast |
| `DOCKERHUB_NS`, `IMAGE_TAG` | `labmultisens`, `latest` | Nome e tag das imagens |
| `EDGE_EXT_PUBLISH`, `BCAST_PUBLISH`, `MQTT_WS_PUBLISH` | comentadas | A porta de host da superfície externa, do bcast e do WebSocket do broker ([Portas e endereços](#portas-e-endereços)) |
| `AOP_PUBLIC_PORT` | comentada (`8080`) | A porta da tela do receptor e das origens das aplicações de emissora |
| `APPS_DOMAIN` | comentada (`apps.localhost`) | O domínio dos hosts das aplicações. `*.localhost` só resolve na máquina de quem abre a tela; com a tela aberta de outra máquina, use um domínio resolvível na rede |
| `EDGE_VARIANT` | `linux` | Onde a borda procura o tv3ws: `linux` (container) ou `windows` (no host; [Desenvolvimento com serviço no host](../dev-local/)) |
| `JWT_SECRET`, `JWT_ISSUER` | comentadas | Segredo e emissor do access token, os mesmos para o tv3ws e a borda. Troque fora do laboratório |
| `AUTH_ENFORCE` | comentada (`enforce`) | `warn` só avisa nas recusas de credencial ([Borda e credenciais](../borda-credenciais/)) |
| `REDIS_COMMANDER_USER`, `REDIS_COMMANDER_PASSWORD` | comentadas (`admin`, `tv30-redis-admin`) | Login do Redis Commander |
| `SERVER_URL` | `localhost` | O host que os aparelhos da rede usam para abrir os WebSockets dos dispositivos remotos: numa rede de verdade, o IP desta máquina |
| `TV3WS_WS_TLS` | comentada | `false` abre o ponto de entrada do dispositivo remoto em `ws://`, e não em `wss://` |
| `SSDP_ENABLED`, `SSDP_ADVERTISE_HOST`, `SSDP_INTERFACE` | comentadas | Descoberta na rede: `false` não sobe o anunciante; fixa o host anunciado, em vez do IP detectado; força a interface |
| `WEBMEDIA_REMOTE_MEDIA_PATH`, `WEBMEDIA_REMOTE_USERFILES_PATH` | comentadas | Caminhos no dispositivo remoto do exemplo webmedia |

## HTTPS

Na primeira subida, a stack gera em `.tv30/tls` um certificado autoassinado do receptor. Ele serve à
superfície externa (44643), ao pareamento do cliente não local e ao `wss://` do ponto de entrada do
dispositivo remoto.

- **Cliente de teste:** `curl -k https://localhost:44643/...`, ou confie em `.tv30/tls/cert.pem`. O
  certificado vale só para `localhost` e `127.0.0.1`.
- **Dispositivo remoto que não confia no certificado:** confie nele, ou use `TV3WS_WS_TLS=false`.
- **Trocar o certificado:** ponha `cert.pem` e `key.pem` em `.tv30/tls` e recrie a stack.

## Descoberta na rede

O receptor se anuncia na rede local por SSDP (ABNT NBR 25608, C.3.4), e um aparelho da rede o acha
sem saber o IP. Sem o anúncio, o aparelho ainda chega ao receptor pelo IP:
`http://<IP>:44642/manifest`.

O anunciante roda **no computador, fora do Docker**, nos três sistemas: de dentro de um container, o
anúncio só sai em Linux nativo. Ele anuncia o IP da interface da rota padrão e acompanha a troca de
rede.

| Comando | O que faz |
|---|---|
| `./tv30 up` | Sobe a stack e o anunciante, que é compilado na primeira vez e quando o código muda |
| `./tv30 down` | Encerra o anunciante, que se despede da rede, e derruba a stack |
| `./tv30 status` | Diz se o anunciante está de pé |
| `./tv30 logs` | Mostra o log do anunciante |

No Windows, `.\tv30.ps1`, com os mesmos comandos.

### Firewall

- Libere a UDP 1900 e a TCP 44642, e a 44643 para o cliente não local.
- **macOS:** aceite o pedido de conexões na primeira execução, e dê ao terminal a permissão de Rede
  Local. Sem ela, o log mostra `no route to host`, e o anunciante fica esperando a rede.
- **Windows:** aceite o pedido do Windows Defender em "redes privadas", com a rede como Privada. O
  serviço "Descoberta SSDP" do Windows (`SSDPSRV`) também usa a UDP 1900; se o anunciante não
  conseguir abri-la, o erro aparece em `.\tv30.ps1 logs`.
- Nenhum container pode publicar a UDP 1900: o log mostraria `address already in use`.

### Verificar

Verifique de **outro aparelho da mesma rede**, e não da máquina do testbed.

| Verificação | Passa quando |
|---|---|
| Com o testbed de pé, o cliente abaixo por 30 s | Aparece um `ssdp:alive` a cada 10 s e uma RESPOSTA, com o `LOCATION` no IP da máquina na rede (não `127.0.0.1` nem um IP do Docker) |
| `curl -i` no `LOCATION` | 200, com `Server-BaseURL` e `Server-SecureBaseURL` no mesmo host do `LOCATION` |
| `./tv30 down` com o cliente rodando | Aparece um `ssdp:byebye` antes de o anúncio parar |

Cliente de teste, em Python 3 sem dependências: `python3 ssdp-client.py [segundos]`.

```python
import select
import socket
import struct
import sys
import time

GROUP = '239.255.255.250'
PORT = 1900
ST = 'urn:schemas-sbtvd-org:service:TV3.0WebServices:1'
SEARCH = (f'M-SEARCH * HTTP/1.1\r\nHOST: {GROUP}:{PORT}\r\nMAN: "ssdp:discover"\r\n'
          f'MX: 2\r\nST: {ST}\r\n\r\n').encode()

duration = float(sys.argv[1]) if len(sys.argv) > 1 else 30
listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(('', PORT))
membership = struct.pack('4sl', socket.inet_aton(GROUP), socket.INADDR_ANY)
listener.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
searcher = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
searcher.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)

end = time.time() + duration
next_search = 0
while time.time() < end:
    if time.time() >= next_search:
        searcher.sendto(SEARCH, (GROUP, PORT))
        next_search = time.time() + 5
    for sock in select.select([listener, searcher], [], [], 0.5)[0]:
        data, origin = sock.recvfrom(4096)
        text = data.decode(errors='replace')
        if ST in text and not text.startswith('M-SEARCH'):
            kind = 'RESPOSTA' if sock is searcher else text.split(' ', 1)[0]
            lines = [line for line in text.split('\r\n')
                     if line.upper().startswith(('LOCATION', 'NTS'))]
            print(time.strftime('%H:%M:%S'), kind, origin[0], *lines)
```

Um aplicativo de descoberta SSDP/UPnP no celular também serve. Uma página no navegador não serve,
porque o navegador não manda UDP.

## Submódulos

```bash
git clone --recurse-submodules https://github.com/multisens/TV30.git
git submodule status                 # o estado de cada um
git submodule update --remote        # todos para o último commit
git submodule update --remote aop    # só um
```

Se `git submodule status` mostra `-` na frente de um submódulo, ou se o clone dele pede chave SSH, a
URL gravada ficou desatualizada:

```bash
git submodule sync --recursive && git submodule update --init --recursive
```
