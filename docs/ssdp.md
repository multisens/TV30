---
title: Descoberta SSDP
parent: Como funciona
nav_order: 7
---

# Descoberta SSDP (C.3.4)

Como o receptor se anuncia na rede local para que outro aparelho o encontre (ABNT NBR 25608, C.3.4), o arranjo do testbed e como verificá-lo. Sem o anúncio, o cliente ainda chega ao receptor pelo IP: `http://<IP>:44642/manifest`.

{: .nota }
A norma pede o anúncio SSDP e o GET no `LOCATION`, sem dizer onde o anunciante roda. Quem anuncia, onde ele roda e o caminho `/manifest` são decisões deste testbed.

## O que a norma pede

ABNT NBR 25608, C.3.4:

- O receptor anuncia por SSDP (HTTPU) em UDP 1900, no multicast 239.255.255.250. O anúncio usa NOTIFY, e a busca, M-SEARCH com `ST: urn:schemas-sbtvd-org:service:TV3.0WebServices:1`.
- A resposta ao M-SEARCH vai em unicast e "shall contain the LOCATION header".
- O GET no `LOCATION` devolve `Server-BaseURL`, `Server-SecureBaseURL`, `Server-PairingMethods`, `Device-BrandName`, `Device-Model` e `Device-FriendlyName`. Os dois primeiros têm o formato `<ip_or_hostname>:<port>`, e a porta do `Server-BaseURL` "shall be fixed: 44642".

## O arranjo: anunciante nativo no host

Dentro do Docker, o multicast só sai em Linux nativo: no Mac e no Windows o container roda na VM do Docker, e nenhuma configuração dele muda isso. Por isso o anunciante roda **no host, fora do Docker, nos três sistemas**, e o resto do testbed continua em container.

- **O programa:** `infra/edgegateway/ssdp/`, em Go, só com a biblioteca padrão. Ele só divulga onde está o `/manifest` e responde a buscas: não guarda estado nem valida credencial, e por isso ficar fora da borda não abre caminho em volta dela.
- **Quem o sobe:** `./tv30 up` (no Windows, `.\tv30.ps1 up`), depois do `docker compose up -d`. O comando compila o binário para a máquina — com o Go do host, ou num container `golang` — quando falta ou quando o código muda, depois de `go vet` e `go test`, e o roda em segundo plano, com pid, log e arquivo de parada em `.tv30/`. `./tv30 down` o encerra antes do `docker compose down`, para o `ssdp:byebye` sair. `./tv30 status` e `./tv30 logs` mostram o estado e o log. `SSDP_ENABLED=false` no `.env` não sobe o anunciante.
- **Mensagens:** dois NOTIFY a cada 10 s, com TTL 4 (um com `NT` igual ao URN e outro com o UDN), `CACHE-CONTROL: max-age=1800`, e resposta ao M-SEARCH com `MAN: "ssdp:discover"`, `MX` e `ST` igual ao URN, ao UDN ou a `ssdp:all` (`ssdp.go`). O UDN é fixo (`uuid:TV30-1234-5678-9012-345678901234`); a variável `UDN` o troca.
- **Interface e host:** o anúncio sai pela interface da rota padrão, que o próprio sistema indica (`iface.go`, socket UDP "conectado"; vale nos três sistemas), e o host do `LOCATION` é o IPv4 dela, **detectado**. A cada NOTIFY o anunciante confere a rota padrão: se a interface ou o IPv4 mudaram, manda o `byebye` do endereço antigo, avisa no log e volta a anunciar com o IP novo. `SSDP_INTERFACE` força a interface; `SSDP_ADVERTISE_HOST` fixa o host (sobreposição).
- **`/manifest`:** servido pelo tv3ws, atrás da borda. O host do `Server-BaseURL` e do `Server-SecureBaseURL` é o endereço pelo qual o cliente acabou de alcançá-lo — o `Host` original, que a borda repassa em `X-TV30-Host` —, e assim casa com o `LOCATION`. Com `SSDP_ADVERTISE_HOST`, vale ele, nos dois. A 44643 do `Server-SecureBaseURL` tem TLS. O `/manifest` expõe os seis cabeçalhos ao navegador (`Access-Control-Expose-Headers`).
- **Falha:** só o erro de configuração encerra o anunciante (porta inválida em `EDGE_HTTP_PORT`/`EDGE_HTTPS_PORT`, `SSDP_INTERFACE` inexistente ou de loopback, `SSDP_ADVERTISE_HOST` sem host, a UDP 1900 presa por socket sem `SO_REUSEADDR`, e os erros que não são de rede). A falta de rede não encerra: ele fecha os sockets, avisa uma vez, tenta de novo com espera crescente até 30 s e volta a anunciar quando a rede volta. As APIs não dependem dele.
- **Parada:** SIGTERM, SIGINT ou o arquivo de parada (`SSDP_STOP_FILE`, que o `./tv30 down` cria; no Windows não há SIGTERM para processo em segundo plano). Nos três casos ele manda o `ssdp:byebye` e sai. Sem rede, sai sem `byebye`.
- **Binários dos três sistemas:** o mesmo código compila para `linux`, `darwin` e `windows` (`GOOS`), com as opções de socket de cada sistema em `sockopt_other.go` e `sockopt_windows.go`.

```
outro aparelho (LAN)                    máquina do testbed (Linux, macOS ou Windows)
celular ── M-SEARCH (UDP 1900) ───────▶ ssdp-announcer   no host, fora do Docker (./tv30 up)
        ◀─ resposta: LOCATION http://<IP da LAN>:44642/manifest
celular ── GET /manifest (TCP 44642) ─▶ edgegateway      container (bridge), 44642 publicada
                                          └─▶ tv3ws       ginga_net; Server-BaseURL = <IP da LAN>:44642
```

## Firewall e permissões

- Libere a UDP 1900 e a TCP 44642 (e a 44643, para o cliente não local).
- **macOS:** com o firewall ligado, aceite o pedido de conexões na primeira execução. O terminal que roda o `./tv30 up` precisa da permissão de Rede Local (Ajustes > Privacidade e Segurança > Rede Local); sem ela, o envio multicast falha com `no route to host`, e o anunciante fica esperando a rede.
- **Windows:** aceite o pedido do Windows Defender marcando "redes privadas", com o perfil da rede como Privada. O serviço "Descoberta SSDP" (`SSDPSRV`) também usa a UDP 1900: se o anunciante não abrir a porta com ele no ar, o erro aparece em `./tv30 logs` (verificação 7, abaixo).

## Como verificar a descoberta

**O cliente de teste roda em outro aparelho da mesma rede**, e não na máquina do testbed: o que se verifica é se o anúncio chega à rede.

| # | Verificação | Passa quando |
|---|---|---|
| 1 | Anúncio chega à rede: `./tv30 up` e o cliente abaixo por 30 s no outro aparelho | NOTIFY `ssdp:alive` a cada 10 s e RESPOSTA ao M-SEARCH, com `LOCATION` no IP da máquina na LAN (não 127.0.0.1 nem IP da rede do Docker) |
| 2 | `/manifest` coerente: `curl -i` no `LOCATION`, do outro aparelho | 200, com `Server-BaseURL` e `Server-SecureBaseURL` no mesmo host do `LOCATION` |
| 3 | Despedida: `./tv30 down` com o cliente rodando | NOTIFY `ssdp:byebye` antes de o anúncio parar |
| 4 | Troca de rede, com o testbed no ar | o anunciante avisa no log, não cai e volta a anunciar com o IP novo; a 1 e a 2 passam na rede nova |
| 5 | UDP 1900 sem conflito | o anunciante abre a 1900 sem `address already in use`, e nenhum container publica a 1900 |
| 6 | Firewall, na primeira execução numa máquina sem regra anterior | o que o sistema pede ao usuário é o que a seção acima descreve |
| 7 | Serviço SSDP do Windows (`SSDPSRV`) no ar | o anunciante abre a 1900 e responde ao M-SEARCH |

Cliente de teste (Python 3, só biblioteca padrão), para o outro aparelho:

```python
# cliente-ssdp.py — rodar em OUTRO aparelho da rede: python3 cliente-ssdp.py [segundos]
import socket, struct, sys, time, select
GRP, PORT, ST = '239.255.255.250', 1900, 'urn:schemas-sbtvd-org:service:TV3.0WebServices:1'
dur = float(sys.argv[1]) if len(sys.argv) > 1 else 30
ouve = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
ouve.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
ouve.bind(('', PORT))
ouve.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                struct.pack('4sl', socket.inet_aton(GRP), socket.INADDR_ANY))
busca = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
busca.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
msg = (f'M-SEARCH * HTTP/1.1\r\nHOST: {GRP}:{PORT}\r\nMAN: "ssdp:discover"\r\n'
       f'MX: 2\r\nST: {ST}\r\n\r\n').encode()
fim, prox = time.time() + dur, 0
while time.time() < fim:
    if time.time() >= prox:
        busca.sendto(msg, (GRP, PORT)); prox = time.time() + 5
    for s in select.select([ouve, busca], [], [], 0.5)[0]:
        dado, orig = s.recvfrom(4096)
        txt = dado.decode(errors='replace')
        if ST in txt and not txt.startswith('M-SEARCH'):
            tipo = 'RESPOSTA' if s is busca else txt.split(' ', 1)[0]
            linhas = [l for l in txt.split('\r\n') if l.upper().startswith(('LOCATION', 'NTS'))]
            print(time.strftime('%H:%M:%S'), tipo, orig[0], *linhas)
```

Um celular com aplicativo de descoberta SSDP/UPnP também serve. Uma página web no navegador não serve: o navegador não manda UDP para 239.255.255.250:1900.
