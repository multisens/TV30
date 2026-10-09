---
title: "Verificação: descoberta SSDP"
nav_order: 13
---

# Descoberta SSDP (C.3.4): o que foi medido e o que falta

Medição de 02/10/2026, com a stack completa de pé e a imagem do tv3ws reconstruída nesta semana. Ela cobre as camadas 1 e 2 do plano de teste: se o anúncio sai do container e se passa da rede do Docker. A camada 3, que é a descoberta por outro dispositivo da LAN, não pôde ser medida nesta máquina e está descrita no fim, com o roteiro e o script de cliente.

**Arranjo atual, decidido pelo Luís em 09/10 (L6, opção A):** quem anuncia é a borda (`edgegateway`), posta em rede do host pelo override `docker-compose.ssdp.yml`, só em Linux nativo. A opção A substituiu a opção B, decidida em 04/10 (informado pelo Luís), em que o anúncio saía de um container próprio, o `tv3ws-ssdp`, em rede do host, com a borda, o tv3ws e o resto na bridge `ginga_net`.

Registro das medições: as de 02/10 foram feitas com o arranjo anterior às duas opções, em que o tv3ws anunciava de dentro da bridge. As de 03 e 04/10 em modo host (testes 6, 7, 11 e 12) usaram um anunciante descartável com a mesma biblioteca do tv3ws. **Os testes 14 a 32 foram feitos com a opção B.** Nenhuma medição da opção A está registrada ainda; a descoberta por outro aparelho em Linux nativo vai ser refeita com ela. O arranjo atual e como ligá-lo estão na seção [Arranjo decidido](#arranjo-decidido-a-borda-anuncia-em-rede-do-host).

> **Norma × implementação.** A norma pede o anúncio SSDP e o GET no LOCATION, sem dizer onde o anunciante roda. Quem anuncia (desde 09/10, a borda, em rede do host; de 04 a 09/10, o container `tv3ws-ssdp`, em rede do host; antes, o tv3ws, num container da bridge `ginga_net`) e o caminho `/manifest` são decisões deste testbed. Onde fica o anunciante era a lacuna **L6**, decidida em 04/10 pela opção B e re-decidida pelo Luís em 09/10 pela opção A.

## O que a norma pede

ABNT NBR 25608, C.3.4, p. 197–198 (p. 215–216 do PDF):

- O receptor anuncia por SSDP (HTTPU) em UDP 1900, no multicast 239.255.255.250 (IPv4) ou ff02::c (IPv6). O anúncio usa NOTIFY e a busca usa M-SEARCH com `ST: urn:schemas-sbtvd-org:service:TV3.0WebServices:1`.
- A resposta ao M-SEARCH vai em unicast e "shall contain the LOCATION header".
- O GET no LOCATION devolve os cabeçalhos `Server-BaseURL`, `Server-SecureBaseURL`, `Server-PairingMethods`, `Device-BrandName`, `Device-Model` e `Device-FriendlyName`. Os dois primeiros têm o formato `<ip_or_hostname>:<port>`, e a porta do `Server-BaseURL` "shall be fixed: 44642".

## O que o código faz hoje

Estado desde 09/10 (opção A). O arranjo das medições de 02/10 está descrito na seção seguinte, e o da opção B, na seção *Medido em 04/10 — opção B*.

- **Quem anuncia:** a borda (`edgegateway`). O anunciante é um processo a mais no container dela, o binário `/usr/local/bin/ssdp-announcer`, escrito em Go só com a biblioteca padrão (`infra/edgegateway/ssdp/`). Ele é compilado no estágio `ssdp` do `infra/edgegateway/Dockerfile`, depois de `go vet` e `go test`: teste falhando, a imagem não sai. O `entrypoint.sh` da borda só o sobe com `SSDP_ENABLED=true` (ou `1`); o padrão é desligado, e o boot registra `ssdp=desligado`. Quem liga é o override `docker-compose.ssdp.yml` da raiz, junto com a rede do host (seção [Arranjo decidido](#arranjo-decidido-a-borda-anuncia-em-rede-do-host)). O anunciante manda dois NOTIFY a cada 10 s, com TTL 4: um com `NT` igual ao URN do serviço e outro com o UDN puro. O UDN é fixo (`uuid:TV30-1234-5678-9012-345678901234`), e a variável `UDN` o troca.
- **Formato das mensagens:** o mesmo do anunciante anterior (a biblioteca `@lvcabral/node-ssdp`, no tv3ws): `USN` igual a `<UDN>::<URN>` e a `<UDN>`, `LOCATION` e `CACHE-CONTROL: max-age=1800` no NOTIFY. Duas diferenças, conferidas no código (`infra/edgegateway/ssdp/ssdp.go`): a resposta ao M-SEARCH sai com `max-age=1800`, e não mais `max-age=4` (testes 17 e 18), e o cabeçalho `SERVER` passou a ser `Linux UPnP/1.1 tv30-ssdp/1.0`, no lugar da assinatura da biblioteca. O primeiro NOTIFY sai logo depois de abrir os sockets; na biblioteca, saía 3 s depois. O M-SEARCH é respondido quando traz `MAN: "ssdp:discover"`, `MX` e um `ST` igual ao URN, ao UDN ou a `ssdp:all`.
- **O tv3ws da bridge não anuncia.** O compose põe `SSDP_ENABLED: "false"` nele, e o boot registra `[ssdp] anuncio desligado (SSDP_ENABLED=false)`. Fora do compose, `SSDP_ENABLED` vale ligado por padrão: o tv3ws rodando sozinho no host anuncia por conta própria, com a biblioteca node-ssdp (`tv3ws/src/ssdp-server.ts`), como antes.
- **Interface:** o anúncio sai só pela interface IPv4 que tem o IP do host anunciado, e a busca é respondida por ela. Se o host não for um IP da máquina (um nome, ou um IP que não está em nenhuma interface), sai pela interface da rota padrão (`/proc/net/route`), com aviso no log. `SSDP_INTERFACE` (nome da interface) força a escolha. Na borda, sem nenhuma interface possível, o anunciante não sobe (erro, morre-inteiro, abaixo); no tv3ws, esse caso anuncia por todas as interfaces, com aviso.
- **LOCATION:** `http://<host>:44642/manifest`. O `<host>` é `SSDP_ADVERTISE_HOST`, senão `SERVER_URL`, senão o IP local. As portas são as da **borda**, 44642 e 44643. `EDGE_HTTP_PORT` e `EDGE_HTTPS_PORT` mudam só as portas anunciadas, e não as portas em que o KrakenD escuta, fixas em `infra/edgegateway/routes.json` (`surfaces.*.port`). A regra está escrita duas vezes, com a mesma ordem e a mesma limpeza do valor (tira esquema, caminho e porta): em Go na borda (`infra/edgegateway/ssdp/config.go`), para o `LOCATION`, e em TypeScript no tv3ws (`tv3ws/src/ssdp-config.ts`), para o `/manifest`. Não há teste cruzado entre as duas.
- **`/manifest`:** servido pelo tv3ws, na bridge, e declarado na tabela única da borda (`infra/edgegateway/routes.json`, `auth: none`, nas duas superfícies). O cliente chega ao tv3ws pela borda (D10). As portas 44652/44653 do tv3ws não são publicadas na stack padrão; com o override, são publicadas só em `127.0.0.1`, para a borda. No compose, a borda e o tv3ws recebem a mesma configuração (item *Compose*, abaixo), e por isso o `Server-BaseURL` e o `LOCATION` saem do mesmo host. O ramo do IP local não acontece no compose, porque o `SERVER_URL` sempre chega com valor (`localhost` por padrão); se acontecesse, os dois divergiriam, porque cada um calcula o IP local na própria rede. Com o tv3ws rodando no host, fora do compose, a igualdade não é garantida: o tv3ws do host não lê o `.env` da raiz ([dev-local.md](dev-local.md#limites)).
- **Morre-inteiro (D9; na borda, decidido pelo Luís em 09/10):** uma falha do anúncio encerra o anunciante com saída 1 e o log `[ssdp] FALHA em <etapa>: <erro> — encerrando (morre-inteiro: a borda cai junto)`. O `entrypoint.sh` da borda vigia o anunciante junto com os dois KrakenD e o httpd da documentação: se ele sai, o container inteiro encerra, **todas as APIs caem**, e o `restart: unless-stopped` traz a borda de volta. As etapas que derrubam são: porta inválida em `EDGE_HTTP_PORT`/`EDGE_HTTPS_PORT`; nenhuma interface para anunciar (`SSDP_INTERFACE` inexistente, ou nem interface com o IP anunciado nem rota padrão); a UDP 1900 que não abre (ocupada por um socket sem `SO_REUSEADDR`); o envio de um NOTIFY, a cada 10 s; e a leitura do grupo multicast. A falha ao responder um M-SEARCH só gera `[ssdp] AVISO`. No tv3ws rodando sozinho com `SSDP_ENABLED` ligado, o processo inteiro cai, APIs inclusive, como antes.
- **Parada:** no SIGTERM, o `entrypoint.sh` para o anunciante primeiro e espera que ele saia, para o `ssdp:byebye` (um por `NT`) sair antes de o container acabar. O anunciante envia o byebye e sai, sem `ssdp:alive` depois dele (o envio periódico e o tratamento do sinal ficam no mesmo laço, em `main.go`). Não medido com a opção A; com a B, os testes 25 e 26.
- **Compose:** o `SERVER_URL` vem da seção `environment` da borda (no override) e do tv3ws (`${SERVER_URL:-localhost}`, do `.env` da raiz ou do shell). `SSDP_ADVERTISE_HOST`, `SSDP_INTERFACE`, `EDGE_HTTP_PORT` e `EDGE_HTTPS_PORT` (e, na borda, `UDN`) ficam fora da seção `environment`: a borda e o tv3ws leem os mesmos arquivos de ambiente, primeiro o `tv3ws/.env` e depois o `.env` da raiz, que prevalece. Um valor só exportado no shell não chega a eles. Motivo (conferido com `docker compose config`, compose v5.4.0, em 04/10, com a opção B): na seção `environment`, até o valor vazio (`${SSDP_ADVERTISE_HOST:-}`) apagaria o do `tv3ws/.env`. Efeito colateral: as outras chaves do `.env` da raiz também entram no ambiente dos dois containers. Na borda, as chaves que a seção `environment` define (`EDGE_VARIANT`, `REDIS_HOST`, `REDIS_PORT`, `SSDP_ENABLED`, `SERVER_URL`, `JWT_SECRET`, `JWT_ISSUER` e `AUTH_ENFORCE`) continuam valendo, porque ela tem precedência sobre o `env_file`. Sem configuração, o anúncio diz `localhost`. Sem o override, nada é anunciado.

## Medido aqui (Windows 11 + WSL2 em NAT, Docker Engine dentro do WSL)

> **Arranjo desta medição (02/10):** o anterior às opções B e A. O tv3ws anunciava de dentro da bridge `ginga_net`, e não havia `tv3ws-ssdp` nem anúncio na borda.

Rede no momento da medição:
- `eth0` da VM do WSL: 172.27.57.172/20;
- bridge da `ginga_net`: `br-8db76461e4d3`, 172.20.0.0/16;
- tv3ws: 172.20.0.2;
- `SERVER_URL`: padrão `localhost`.

As capturas usaram a imagem `nicolaka/netshoot`, com timeout de 35 s cada.

| Camada | Onde | Comando | Resultado |
|---|---|---|---|
| 1 | `eth0` do container tv3ws | `docker run --rm --net container:tv3ws nicolaka/netshoot tcpdump -ni eth0 -c 4 -A udp port 1900` | 4 pacotes em 10 s: `172.20.0.2.1900 > 239.255.255.250.1900`, dois NOTIFY por ciclo (`NT: urn:schemas-sbtvd-org:service:TV3.0WebServices:1` e `NT: uuid:TV30-…`), `NTS: ssdp:alive`, `LOCATION: http://localhost:44642/manifest` |
| 2a | bridge `br-<id>` na VM do WSL | `docker run --rm --net host nicolaka/netshoot tcpdump -ni br-8db76461e4d3 -c 2 -A udp port 1900` | 2 NOTIFY, com o mesmo conteúdo |
| 2b | `eth0` da VM do WSL | `docker run --rm --net host nicolaka/netshoot tcpdump -ni eth0 -c 2 -A udp port 1900` | **0 pacotes em 35 s** |
| 2 | rotas multicast da VM | `ip mroute` | vazio |
| — | M-SEARCH de um container na `ginga_net` | script Node com `dgram`, TTL 1 | 1 resposta unicast de `172.20.0.2:1900`, com o LOCATION e o USN acima |
| — | M-SEARCH da VM do WSL pela interface da bridge (172.20.0.1) | o mesmo script, com `setMulticastInterface` | 1 resposta unicast |
| — | GET pela borda | `curl -i http://localhost:44642/manifest` (e `:44643`) | 200 com `Server-Baseurl: localhost:44642`, `Server-Securebaseurl: localhost:44643`, `Server-Pairingmethods: qrcode,kex`, `Device-Brandname`, `Device-Model`, `Device-Friendlyname` |
| — | byebye | `docker stop tv3ws`, com captura na bridge | 2 NOTIFY `ssdp:byebye`; o processo saiu com 143 em ~2,3 s |
| controle positivo | cliente node-ssdp (o script abaixo) num container da `ginga_net`, com o tv3ws recriado com `SERVER_URL=edgegateway` só para o teste | `node cliente-ssdp.js 14` | M-SEARCH e NOTIFY recebidos; `GET http://edgegateway:44642/manifest` → 200 com `server-baseurl: edgegateway:44642` e os outros cinco cabeçalhos. O tv3ws voltou ao padrão (`SERVER_URL=localhost`) logo depois |

Com o padrão `localhost`, o mesmo cliente recebeu o anúncio, mas o GET no LOCATION falhou com `ECONNREFUSED`, porque `localhost` aponta para o próprio dispositivo que buscou.

### O que isso mostra

1. **O anúncio sai do container e chega à bridge, mas não sai da VM do WSL.** Nada apareceu na `eth0` da VM, e não há roteamento multicast. Nesta máquina, nenhum dispositivo da LAN recebe o NOTIFY, e um M-SEARCH vindo da LAN não chegaria ao tv3ws.
   - Em Linux nativo com a bridge do Docker, a expectativa é a mesma: o Docker não roteia multicast da bridge para a interface física. Isso **não foi medido** aqui; é inferência.
2. **Dentro da rede do Docker, o fluxo de duas etapas funciona de ponta a ponta pela borda,** desde que o host anunciado seja alcançável por quem busca (controle positivo acima).
3. **Com a configuração padrão, o anúncio aponta para `localhost`.** Mesmo que o pacote chegasse a outro dispositivo, o LOCATION e o `Server-BaseURL` não serviriam. Para o teste em rede doméstica, defina `SERVER_URL=<IP da máquina na LAN>` no `.env` da raiz. Esse valor também é o que vai na URL de WebSocket do remote-device. Outra opção, que muda só o anúncio e o `/manifest`, é `SSDP_ADVERTISE_HOST`: desde a opção B, no `.env` da raiz ou no `tv3ws/.env` (o da raiz prevalece), que o tv3ws e o anunciante (o `tv3ws-ssdp` na opção B; a borda, desde a opção A) leem como arquivos de ambiente. Em 02/10 ela chegava ao tv3ws só pelo `tv3ws/.env`.
   - Desde 03/10 o tv3ws registra no boot um `[ssdp] AVISO` quando o host anunciado é de loopback; o anunciante da borda registra o mesmo aviso. O padrão não mudou. PENDENTE (Joel): cair no IP local quando `SERVER_URL` for loopback, ou exigir `SSDP_ADVERTISE_HOST`.
   - **`Server-SecureBaseURL` aponta para porta sem TLS.** O `/manifest` anuncia `<host>:44643`, a superfície externa da borda, que ainda é HTTP puro (lacuna L3). Um cliente não local que siga a C.3.4 e use `https://<Server-SecureBaseURL>/tv3/<API>` falha nessa porta. O tv3ws e o anunciante da borda também registram isso no boot. PENDENTE (Joel): até a decisão da L3, anunciar a borda (como hoje) ou o HTTPS do próprio tv3ws, que não é publicado no host.
4. **Observações, sem correção nesta semana:**
   - **Nomes dos cabeçalhos.** A borda (Go) entrega os nomes canonizados: `Server-Baseurl` em vez de `Server-BaseURL`. Nome de cabeçalho HTTP não diferencia maiúsculas (RFC 9110, 5.1), então cliente correto lê os dois. Cliente que compare com distinção de maiúsculas falha.
   - **CORS.** A borda expõe ao navegador só `Content-Length` e `X-TV30-Auth-Warn`. Um script de página que leia `/manifest` por `fetch` não enxerga os cabeçalhos `Server-*` e `Device-*`. Não há decisão sobre expô-los.
   - **UDN fixo.** Dois testbeds na mesma LAN anunciam o mesmo UDN e o mesmo USN. A C.6.1.4.1 usa o USN para distinguir receptores.
   - **Fora do código atual:** IPv6 (ff02::c), porque os sockets são só `udp4`, e a descoberta de TV 2.X WebServices (ABNT NBR 15606-11, 6.3).

Os comandos acima rodaram dentro da VM do WSL (`wsl.exe -u root bash <script>`). O M-SEARCH enviado à bridge usou TTL 1 e não saiu da VM. Nenhum pacote foi enviado à rede da ONS.

## Medido em 03/10: modo host no WSL e celular na rede doméstica

Dois testes novos. O primeiro foi feito com um anunciante **descartável**, separado da stack; nada da stack mudou.

| # | Teste | Como | Resultado |
|---|---|---|---|
| 6 | Anunciante em `network_mode: host` no WSL | container `node:20-alpine` com a mesma biblioteca do tv3ws (`@lvcabral/node-ssdp`), `ssdpTtl: 1`, LOCATION `http://172.27.57.172:44699/manifest` (manifesto falso numa porta livre) | o NOTIFY **aparece na `eth0` da VM do WSL**, onde com a bridge apareciam 0 pacotes |
| 7 | Cliente no Windows, preso à interface `vEthernet (WSL)` (172.27.48.1), TTL 1 | script Node com `dgram`: escuta passiva do grupo + M-SEARCH | 8 NOTIFY, 32 respostas a cerca de 5 M-SEARCH e GET no LOCATION com 200 e os seis cabeçalhos. As respostas vêm duplicadas porque, em modo host, a biblioteca responde por todas as interfaces IPv4 da VM (`eth0`, `docker0`, `br-*`) |
| 8 | Controle negativo do 7 | o mesmo cliente, só com a stack (tv3ws na bridge) | 0 NOTIFY, 0 respostas |
| 9 | Celular Android na rede doméstica (Termux, Python com `socket`), controle positivo | `M-SEARCH` com `ST: ssdp:all` | cerca de 15 respostas do roteador doméstico (192.168.0.1), uma por serviço UPnP. A rede e o celular fazem SSDP |
| 10 | O mesmo celular, buscando o receptor | `M-SEARCH` com `ST: urn:schemas-sbtvd-org:service:TV3.0WebServices:1`, com a stack de pé no notebook (WSL2) na mesma rede | **0 respostas** |

O teste 9 só prova que o celular fala SSDP com o roteador. Não prova a ausência de isolamento entre clientes do Wi-Fi.

As duplicatas do teste 7 levaram o anunciante a usar uma interface só, regra que a opção A manteve na borda (seção [Arranjo decidido](#arranjo-decidido-a-borda-anuncia-em-rede-do-host)). Com o `tv3ws-ssdp` da opção B, o mesmo cliente do Windows recebeu 1 resposta por M-SEARCH (teste 18, na seção *Medido em 04/10 — opção B*, mais abaixo). Com a opção A, isso não foi medido.

**Medido em 04/10: modo host no WSL e celular.** Notebook na rede doméstica (Wi-Fi 192.168.0.12/24, VPN corporativa desligada), mesmo roteador do teste 9.

| # | Teste | Como | Resultado |
|---|---|---|---|
| 11 | Anunciante descartável em `network_mode: host` no WSL, agora com `ssdpTtl: 4` (TTL 1 seria descartado no primeiro salto e enviesaria o teste) | o mesmo do teste 6; captura na `eth0` da VM | NOTIFY saindo pela `eth0` da VM (172.27.57.172) |
| 12 | Controle no próprio PC, logo antes do 13 | M-SEARCH pela `vEthernet (WSL)` (172.27.48.1) | 16 respostas de 172.27.57.172 |
| 13 | Celular no Wi-Fi doméstico, com o anunciante do 11 no ar | `M-SEARCH` com `ST: urn:schemas-sbtvd-org:service:TV3.0WebServices:1`, rodado duas vezes | **0 respostas** nas duas |

O anunciante foi removido depois do teste.

### Onde o anúncio para

```
container tv3ws        VM do WSL (Linux)                        Windows                       rede doméstica
eth0 172.20.0.2 ──▶ br-8db76461e4d3 ─✗─▶ eth0 172.27.57.172 ──▶ vEthernet (WSL) 172.27.48.1 ─✗─▶ Wi-Fi ──▶ celular
     ✅ (1)               ✅ (2a)            ❌ (2b)                  ✅ só em modo host (7, 12)        ❌ (10, 13)
```

1. **Primeira barreira, medida:** o kernel da VM do WSL, entre a bridge `br-*` e a `eth0`. Sem rota multicast (`ip mroute` vazio), ele entrega o pacote dentro da VM e não o encaminha. O NAT do Docker só traduz unicast. Essa barreira é do kernel Linux, não do WSL: num Linux nativo, a bridge do Docker barra do mesmo jeito.
2. **Segunda barreira, medida em 04/10:** o Windows, entre a `vEthernet (WSL)` e o Wi-Fi. Em modo host o anúncio chega ao próprio Windows (testes 7 e 12), mas não ao celular na mesma rede doméstica (teste 13). Isso bate com o Windows não rotear multicast entre interfaces por padrão.

**Consequência:** numa máquina Windows com WSL2 em NAT, nenhuma das opções da L6 leva o anúncio ao celular sozinha. O teste positivo da camada 3 precisa de Linux nativo com Docker Engine (o Docker Desktop também roda o Docker numa VM; espera-se o mesmo problema, não medido).

Com as opções B e A, o anúncio sai de um processo em modo host, sem passar pela bridge, e por isso não encontra a primeira barreira (testes 6, 11 e 17, com o anunciante descartável e com a opção B; com a A, não medido). A segunda barreira é do Windows e continua. Por isso a descoberta só é suportada em Linux nativo (decisão do Joel, informada pelo Luís em 04/10).

## Arranjo decidido: a borda anuncia em rede do host

**L6 re-decidida pelo Luís em 09/10: opção A.** Quem anuncia é a borda, posta em rede do host. A opção A substituiu a opção B (o container `tv3ws-ssdp`), decidida em 04/10 (informado pelo Luís) e validada em Linux nativo em 09/10 (testes 28 a 32), antes da troca. Na avaliação de 03/10, a A aparece como a direção dita pelo Joel em 28/09 (seção *L6: as opções avaliadas antes da decisão*, mais abaixo). É decisão de implementação deste testbed, não da norma: a C.3.4 não diz onde o anunciante roda.

```
outro aparelho (LAN)                    máquina com Linux nativo e Docker Engine
celular ── M-SEARCH (UDP 1900) ───────▶ edgegateway   rede do host; processo ssdp-announcer
        ◀─ resposta: LOCATION http://<IP da LAN>:44642/manifest
celular ── GET /manifest (TCP 44642) ─▶ edgegateway   KrakenD interno, direto no host (variante host)
                                          └─▶ tv3ws   ginga_net; alcançado por 127.0.0.1:44652,
                                                      publicada só no loopback; responde Server-*, Device-*
```

- **O anunciante é um processo da borda.** `/usr/local/bin/ssdp-announcer`, binário estático em Go, só com a biblioteca padrão (`infra/edgegateway/ssdp/`: `main.go`, `config.go`, `iface.go`, `ssdp.go` e os testes em `ssdp_test.go`). O `entrypoint.sh` da borda só o sobe com `SSDP_ENABLED=true` e o põe na vigia do morre-inteiro. Com o override, o boot registra `[edgegateway] externa=44643 interna=44642 docs=8085 (variant=host, ssdp=ligado)`.
- **O override `docker-compose.ssdp.yml` (raiz) liga tudo junto.**
  - Na borda: `network_mode: host`, sem `networks`, `ports` nem `extra_hosts`; `EDGE_VARIANT=host`, `REDIS_HOST=127.0.0.1` e `SSDP_ENABLED=true`; o `SERVER_URL` e os arquivos de ambiente do item *Compose*, acima.
  - No tv3ws: publica a 44652 e a 44653 só em `127.0.0.1`, para a borda. Da LAN elas não são alcançáveis, e a porta direta fechada no item 8 segue fechada para a rede; um processo da própria máquina, porém, chega ao tv3ws sem passar pela borda.
  - No `preflight`: `SSDP_EDGE=true`, que liga as checagens da borda em rede do host (*Como ligar*, abaixo).
- **Variante `host` da borda.** `infra/edgegateway/routes.json` ganhou backends `host`: `http://127.0.0.1:44652` na superfície interna e `https://127.0.0.1:44653` na externa. O `generate.js` gera `krakend-internal.host.json` e `krakend-external.host.json` no build, ao lado das variantes `linux` e `windows`. O Redis é alcançado pela 6379 publicada.
- **Portas da borda direto no host.** 44642, 44643 e a 8085 da documentação passam a ser abertas pelos processos da borda na rede do host, sem `docker-proxy`. A 8085 deixa de ser dinâmica nesse modo: a documentação fica em `http://localhost:8085`.
- **O `/manifest` fica no tv3ws,** atrás da borda, e responde com ou sem o override. O tv3ws da bridge recebe `SSDP_ENABLED: "false"` e não anuncia.
- **No compose, o host do `LOCATION` e o do `/manifest` vêm da mesma configuração:** a mesma regra, em Go na borda e em TypeScript no tv3ws, com o mesmo `SERVER_URL` e o `SSDP_ADVERTISE_HOST` lido dos mesmos arquivos de ambiente (`tv3ws/.env` e `.env` da raiz, que prevalece). O padrão continua `localhost`, com aviso no boot. Qual deve ser o padrão é a B2, ainda aberta.
- **Interface:** a que tem o IP anunciado; senão, a da rota padrão, com aviso; `SSDP_INTERFACE` força. Sem nenhuma, erro.
- **Falha do anúncio derruba a borda inteira** (morre-inteiro, decidido pelo Luís em 09/10), e o `restart` a traz de volta. Na opção B, a falha derrubava só o `tv3ws-ssdp`, e as APIs não caíam; a decisão reabre, na borda, o efeito do ponto C8 de [Decisões pendentes](decisoes-pendentes.md). Pelo código, numa máquina sem interface com IPv4 e sem rota padrão, o anunciante falha a cada subida, e a borda fica reiniciando sem servir as APIs enquanto a rede não volta (inferência; não medido).
- **Só Linux nativo com Docker Engine** (decisão do Joel, informada pelo Luís em 04/10, que continua valendo).

### Como ligar no Linux nativo

1. No `.env` da raiz (o `COMPOSE_PROFILES=mqtt,linux` fica como está; o perfil `ssdp` deixou de existir):

   ```bash
   COMPOSE_FILE=docker-compose.yml:docker-compose.ssdp.yml
   SSDP_ADVERTISE_HOST=192.168.0.12   # IP desta máquina na rede local
   #SSDP_INTERFACE=wlan0              # só se a escolha automática errar
   ```

2. Quem tinha a opção B de pé remove o container antigo: `docker rm -f tv3ws-ssdp`, ou `docker compose up -d --remove-orphans`. O serviço saiu do compose, e sem isso ficariam dois anunciantes.
3. `docker compose up -d`. O `preflight` (`docker logs tv30-preflight`) avisa, sem bloquear, quando a UDP 1900 já está ocupada por outro processo e quando o `tv3ws-ssdp` antigo está de pé. Num novo `up -d`, a 44642 ocupada pelo KrakenD da própria borda vira aviso, e não erro. As checagens vêm do `SSDP_EDGE=true` do próprio override, e por isso acompanham o arranjo, o que com o perfil `ssdp` dependia de como ele era ligado (teste 24).
4. Confira os logs:
   - `docker logs edgegateway`: a linha `[edgegateway] ... (variant=host, ssdp=ligado)`, as linhas `[ssdp] AVISO` e a linha `[ssdp] anunciando urn:schemas-sbtvd-org:service:TV3.0WebServices:1 em UDP 1900 pela interface <nome> (<IP>, via host-ip); LOCATION http://<IP da LAN>:44642/manifest (host via SSDP_ADVERTISE_HOST)`;
   - `docker logs tv3ws`: `[ssdp] anuncio desligado (SSDP_ENABLED=false); o /manifest continua servido por este processo`.
5. Confira que o anúncio sai: `sudo tcpdump -ni <interface> udp port 1900` mostra dois NOTIFY a cada 10 s, com o `LOCATION` acima.
6. Libere no firewall do host a UDP 1900 e a TCP 44642 (e a 44643, para o cliente não local).
7. No segundo aparelho, rode o roteiro da seção *O que exige rede doméstica e um segundo dispositivo*, mais abaixo.

Os textos de log acima são os do código (`infra/edgegateway/entrypoint.sh` e `infra/edgegateway/ssdp/main.go`); com a opção A, ainda não foram conferidos numa subida.

Cuidados:
- **Para desligar,** comente o `COMPOSE_FILE` no `.env` da raiz e rode `docker compose up -d`. A borda e o tv3ws são recriados com a configuração padrão: a borda volta à `ginga_net`, sem anúncio, e as portas 44652/44653 deixam de ser publicadas (não medido com a opção A).
- **Desenvolvimento com módulo no host:** o `scripts/test-dev-host.sh` roda sempre com a borda na bridge (`COMPOSE_FILE=docker-compose.yml`) e, no fim, restaura a configuração do `.env`, com o override se ele estiver ligado. À mão, use o mesmo prefixo ([dev-local.md](dev-local.md)).

Em Windows com WSL2, o anúncio em modo host chega ao próprio Windows, mas não aos outros aparelhos da rede (testes 12 e 13, com o anunciante descartável em modo host). O Docker Desktop, que também roda o Docker numa VM, fica fora do suporte, sem medição. Nesses ambientes, deixe o `COMPOSE_FILE` comentado; o cliente chega pelo IP, sem a etapa de descoberta: `http://<IP>:44642/manifest`.

## Medido em 04/10 — opção B

> **Arranjo destas medições e das de 09/10 (opção B, substituída pela opção A em 09/10):** o anúncio saía do container `tv3ws-ssdp`, do perfil `ssdp` do compose da raiz, que não existem mais. Era a imagem `tv30-tv3ws` com o comando `node dist/ssdp-announcer.js` (`tv3ws/src/ssdp-announcer.ts`, removido em 09/10), em `network_mode: host`, só com o anúncio, sem porta TCP e com a biblioteca node-ssdp. A borda e o tv3ws ficavam na `ginga_net`, e uma falha do anúncio derrubava só esse container. Os comandos citados nos testes (`--profile ssdp`, `docker compose stop tv3ws-ssdp`, `docker logs tv3ws-ssdp`) não valem para a opção A.

Integração do código da opção B, na mesma máquina (Windows 11 + WSL2 em NAT, Docker Engine no WSL, compose v5.4.0), com a imagem `tv30-tv3ws` reconstruída (`docker compose build tv3ws`, rc 0; `dist/ssdp-announcer.js` presente na imagem). Rede no momento:
- `eth0` da VM do WSL: 172.27.57.172;
- bridge da `ginga_net`: `br-a2b848077008`;
- `vEthernet (WSL)` do Windows: 172.27.48.1;
- Wi-Fi do notebook na rede doméstica (192.168.0.12).

Para ligar o anúncio sem alterar o `.env` da raiz, o `SSDP_ADVERTISE_HOST=172.27.57.172` entrou por um arquivo de ambiente de teste, acrescentado aos dois serviços por um override do compose. O perfil entrou por `COMPOSE_PROFILES=mqtt,linux,ssdp` no shell. A ordem e a precedência dos arquivos (`tv3ws/.env`, depois o `.env` da raiz) foram conferidas só com `docker compose config`, sem a stack de pé.

| # | Teste | Como | Resultado |
|---|---|---|---|
| 14 | Stack padrão, sem o perfil `ssdp` | `docker compose up -d` com `COMPOSE_PROFILES=mqtt,linux` do `.env` | Nenhum container `tv3ws-ssdp`. O log do tv3ws diz `[ssdp] anuncio desligado (SSDP_ENABLED=false); o /manifest continua servido por este processo`. No netns do tv3ws não há socket na UDP 1900. Em 30 s de `tcpdump`, nenhum pacote UDP 1900, nem na `br-a2b848077008` nem em `-i any`. O `GET /manifest` pela borda (44642) dá 200, com os seis cabeçalhos e `Server-Baseurl: localhost:44642` |
| 15 | Seleção de perfis | `docker compose config --services` | Só com `--profile ssdp` saem `preflight`, `redis`, `edgegateway`, `tv3ws-ssdp` e `userfiles-seed`, sem tv3ws, aop, bcast e mosquitto. Com `COMPOSE_PROFILES=mqtt,linux,ssdp` saem os dez serviços |
| 16 | Perfil `ssdp` ligado | `up -d` com o perfil e o host de teste | O `tv3ws-ssdp` roda em `network_mode: host`, com `["node","dist/ssdp-announcer.js"]`, `restart: unless-stopped` e nenhum volume. O log diz `[ssdp] anunciando ... pela interface eth0 (172.27.57.172, via host-ip); LOCATION http://172.27.57.172:44642/manifest (host via SSDP_ADVERTISE_HOST)`. O processo tem um socket só, UDP `0.0.0.0:1900`, e nenhum TCP em escuta. Na stack, o `LOG_LEVEL` era `INFO`, vindo do `tv3ws/.env`. Num container avulso com `LOG_LEVEL=ERROR`, a linha "anunciando" também saiu. O `GET /manifest` pela borda, por `localhost` e por 172.27.57.172, dá `Server-Baseurl: 172.27.57.172:44642`, o mesmo host e porta do `LOCATION` |
| 17 | Por onde o NOTIFY sai | `tcpdump` de 25 s em cada interface da VM | Na `eth0`, 6 pacotes para 239.255.255.250:1900: 3 ciclos de 2 NOTIFY, um com `NT` = URN e outro com `NT` = UDN. Todos com TTL 4, `LOCATION` acima e `CACHE-CONTROL: max-age=1800`. Na `docker0`, nas três `br-*` e na `sta0`, 0 pacotes |
| 18 | Cliente no Windows | `node` do Windows, com o socket ligado a 172.27.48.1 (`vEthernet (WSL)`) e o multicast saindo por ela com TTL 1. Seis M-SEARCH, a cada 4 s, e escuta passiva do grupo | 6 respostas aos 6 M-SEARCH, **1 por busca**, todas de 172.27.57.172:1900. No teste 7 foram 32 respostas a cerca de 5 buscas. Chegaram 6 NOTIFY, 3 de cada `NT`. O `GET` no `LOCATION` dá 200 pela borda (`X-Krakend`), com os seis cabeçalhos. Na captura da `eth0` da VM, no mesmo intervalo: 6 M-SEARCH com TTL 1 e 6 respostas unicast |
| 19 | Processo morto | `kill -9` no PID do node do `tv3ws-ssdp`, a partir da VM | O Docker o reiniciou em cerca de 1 s (1 reinício), e o anúncio voltou. O tv3ws ficou com o mesmo `StartedAt`. `/manifest`, `/health` e `GET /tv3/current-service` pela borda deram 200 em todas as amostras |
| 20 | Falha de bind | Um processo node segura `0.0.0.0:1900` na VM, sem `SO_REUSEADDR`. Depois, `up -d` | O `preflight` diz `[preflight] AVISO: UDP 1900 (SSDP) ja esta em uso no host (23021/node).` O `tv3ws-ssdp` diz `[ssdp] FALHA em socket UDP 1900 (172.27.57.172): bind EADDRINUSE 0.0.0.0:1900 — encerrando o processo ...` e sai com 1: 8 reinícios em cerca de 30 s. O tv3ws não reiniciou, e as APIs pela borda deram 200. Com a porta liberada, o anúncio voltou em cerca de 10 s |
| 21 | Interface inexistente | `docker compose run --rm --no-deps -e SSDP_INTERFACE=eth9 tv3ws-ssdp` | Saída 1, com `[ssdp] FALHA em escolha da interface do anuncio (SSDP_INTERFACE): SSDP_INTERFACE='eth9' nao existe ou nao tem IPv4 externo (interfaces com IPv4: eth0 ..., br-..., sta0 ...)`. As APIs pela borda deram 200 |
| 22 | Desligar o perfil | Perfil `ssdp` fora do `COMPOSE_PROFILES`, `docker compose up -d` e depois `docker compose down` | O `tv3ws-ssdp` **continuou de pé** nos dois casos e seguiu anunciando com a configuração antiga: o `LOCATION` em 172.27.57.172, enquanto o tv3ws recriado já dizia `localhost`. Só saiu com `docker compose --profile ssdp rm -sf tv3ws-ssdp` |
| 23 | Dev-host, cenário 1 (tv3ws no host, `SSDP_ENABLED` padrão) | `scripts/test-dev-host.sh` | 27 PASS, 0 FAIL nos três cenários. O tv3ws do host anunciou `pela interface eth0 (172.27.57.172, via default-route)`, com o aviso de que `'localhost'` não é um IPv4 |

Testes 24 a 27: mesma máquina e mesmo arranjo, depois da correção do byebye (`tv3ws/src/ssdp-server.ts`) e do cenário 1 do `scripts/test-dev-host.sh`, com a imagem `tv30-tv3ws` reconstruída de novo (`docker compose build tv3ws`, rc 0).

| # | Teste | Como | Resultado |
|---|---|---|---|
| 24 | Preflight conforme o modo de ligar o perfil | Novo `up -d` com o `tv3ws-ssdp` já segurando a UDP 1900: uma vez com `COMPOSE_PROFILES=mqtt,linux,ssdp` no shell; outra com `--profile mqtt --profile linux --profile ssdp` e o `COMPOSE_PROFILES=mqtt,linux` do `.env` | Com `COMPOSE_PROFILES`, o preflight diz `[preflight] ok: UDP 1900 em uso pelo tv3ws-ssdp ja em execucao (re-up).` Só com `--profile`, o preflight recebe `COMPOSE_PROFILES=mqtt,linux` e não diz nada sobre a UDP 1900 |
| 25 | Parada pelo compose, com o perfil fora do `COMPOSE_PROFILES` | `docker compose stop tv3ws-ssdp`, com o `.env` em `mqtt,linux`; captura na `eth0` | rc 0 em cerca de 1,2 s; saída 143; log `[ssdp] SIGTERM: enviando ssdp:byebye`. Na captura, 2 `ssdp:byebye` (um por `NT`) e nenhum `ssdp:alive` depois deles |
| 26 | SIGTERM no meio do laço de anúncio | Anunciante avulso (`node dist/ssdp-announcer.js`, `--network host`, `LOG_LEVEL=ERROR`). `kill -TERM` no PID, cerca de 145 ms antes do `ssdp:alive` periódico seguinte (período medido: 10,01 s). Controle: o mesmo `dist/ssdp-server.js` com a guarda anulada | Controle: 2 `ssdp:byebye` e, 138 ms depois, 2 `ssdp:alive` com `max-age=1800`. Com a guarda: 2 `ssdp:byebye` e nenhum `ssdp:alive`. Nos dois casos, saída 143 cerca de 308 ms depois do sinal, e a linha `[ssdp] SIGTERM: enviando ssdp:byebye` sai com `LOG_LEVEL=ERROR` |
| 27 | Dev-host, cenário 1, com o `tv3ws-ssdp` de pé antes (`LOCATION` em 172.27.57.172) | `scripts/test-dev-host.sh --cenario 1`; captura de 12 s na `eth0` a partir do momento em que o tv3ws do host passa a anunciar | 10 PASS, 0 FAIL, rc 0. O script parou o `tv3ws-ssdp` (saída 143) antes de subir o tv3ws do host. Na captura, 4 `ssdp:alive`, todos com `LOCATION: http://localhost:44642/manifest` (o tv3ws do host), e nenhum com 172.27.57.172. Também saíram 2 `ssdp:byebye`, sem `LOCATION`; com o `tv3ws-ssdp` já parado, devem ser do tv3ws do host ao ser encerrado (inferência). Na restauração, o `tv3ws-ssdp` voltou a rodar |

O que isso mostra:
- **Depois do `ssdp:byebye` não sai mais `ssdp:alive`** (testes 25 e 26). Sem a guarda, um `ssdp:alive` saía depois do byebye quando o sinal caía nos 300 ms anteriores a um anúncio periódico (controle do teste 26).
- **As duplicatas do teste 7 acabaram,** pelo menos entre a VM do WSL e o Windows: 1 resposta por M-SEARCH, e o NOTIFY só na `eth0`.
- **O morre-inteiro ficou isolado no deploy em container, com a opção B.** Processo morto, porta ocupada e interface errada derrubavam só o `tv3ws-ssdp`, e a borda e o tv3ws seguiam respondendo. Com a opção A, por decisão do Luís em 09/10, as mesmas falhas derrubam a borda inteira.
- **No compose, o `LOCATION` e o `Server-BaseURL` saíram do mesmo host** (teste 16).
- **Ainda não medido nesta rodada:** a descoberta por um segundo aparelho numa LAN, com Linux nativo (camada 3). Ela foi medida em 09/10 (seção seguinte).

O que foi enviado à rede: os M-SEARCH de teste saíram com TTL 1, presos à `vEthernet (WSL)`. O NOTIFY do `tv3ws-ssdp` saía com TTL 4 pela `eth0` da VM, que só alcança o Windows; o Windows não roteia multicast entre interfaces (teste 13). Os containers e processos de teste foram removidos depois.

## Medido em 09/10 — teste positivo em Linux nativo (camada 3), com a opção B

> Medição feita com a opção B, antes da troca para a opção A no mesmo dia. Com a opção A, este teste ainda não foi refeito.

Ambiente:
- **Receptor:** máquina Linux nativa (Ubuntu 26.04.1, Docker Engine 29.1.3, contexto `default`), no Wi-Fi doméstico pela `wlp2s0`, IP 192.168.2.7. `ufw` ativo, sem regra nova.
- **Configuração:** stack com as imagens `labmultisens/*:latest` (a `tv30-tv3ws` já com `dist/ssdp-announcer.js`). No `.env` da raiz, `COMPOSE_PROFILES=mqtt,linux,ssdp` e `SSDP_ADVERTISE_HOST=192.168.2.7`.

| # | Teste | Como | Resultado |
|---|---|---|---|
| 28 | Subida com o perfil `ssdp` | `docker compose up -d`; logs | o `tv3ws-ssdp` registra `anunciando ... pela interface wlp2s0 (192.168.2.7, via host-ip); LOCATION http://192.168.2.7:44642/manifest`. O tv3ws registra `anuncio desligado (SSDP_ENABLED=false)` |
| 29 | `/manifest` pela borda, no próprio Linux | `curl http://192.168.2.7:44642/manifest` | 200, `Server-BaseURL: 192.168.2.7:44642`, o mesmo host do `LOCATION` |
| 30 | **Segundo aparelho: notebook** no mesmo Wi-Fi (192.168.2.5) | 3 M-SEARCH pelo Wi-Fi, TTL 1; depois GET no `LOCATION` | **3 respostas de 192.168.2.7, uma por busca**; GET com 200 e os seis cabeçalhos (`Server-BaseURL`, `Server-SecureBaseURL`, `Server-PairingMethods`, `Device-BrandName`, `Device-Model`, `Device-FriendlyName`) |
| 31 | Celular Android, com VPN ligada e sem ter confirmado o Wi-Fi | M-SEARCH pelo Termux | 0 respostas. **Não vale como teste:** o celular falava com o Linux por um endereço 100.x (túnel VPN), não pela rede local |
| 32 | **Celular Android no Wi-Fi doméstico**, VPN desligada | o mesmo M-SEARCH | **resposta de `('192.168.2.7', 1900)`** |

**O que isso mostra:** em Linux nativo, com o anunciante isolado em modo host (opção B), a descoberta da C.3.4 funciona de ponta a ponta. Um aparelho da rede doméstica encontra o receptor, lê o `LOCATION` e obtém pelo `/manifest` o `Server-BaseURL` da borda (44642). Cuidado com o celular: VPN e dados móveis tiram o M-SEARCH da rede local (teste 31). O resultado não se transfere sozinho para a opção A: o anúncio também sai em rede do host, mas de outro programa (Go, na borda), e a borda alcança o tv3ws por outro caminho (`127.0.0.1`). Por isso o teste vai ser refeito.

Uma captura no Linux durante o teste 32 não registrou o M-SEARCH, provavelmente por erro no filtro. Isso não muda o resultado: o receptor respondeu ao celular.

## L6: as opções avaliadas antes da decisão (decisão do projeto, não da norma)

> **Registro da avaliação de 03/10, anterior às decisões.** A opção escolhida em 04/10 foi a B; em 09/10, o Luís a trocou pela A. Os números de linha citados são do código daquela data. A opção A foi feita como a linha dela previa: anunciante reescrito em Go, variante nova da borda (declarada no `routes.json`; o `generate.js` a gera sem mudança no código dele) e tv3ws publicado em `127.0.0.1`.

A norma não diz onde o anunciante roda (C.3.4). O que segue é decisão de implementação deste testbed. Para o teste em Linux nativo não é preciso mexer em código: dá para colocar o tv3ws em `network_mode: host` só por compose e `.env`, com `MQTT_HOST`/`REDIS_HOST=localhost`, `EDGE_VARIANT=windows` com o tv3ws em 44654/44655 (o arranjo do cenário 1 do dev-host) e `SERVER_URL=<IP da LAN>`.

| Opção | O que muda | Código |
|---|---|---|
| tv3ws em modo host (caminho mais curto, fora de A e B) | a borda acha o tv3ws por `host.docker.internal`; o tv3ws acha MQTT e Redis por `localhost` | **pequeno:** o tv3ws escuta em todas as interfaces (`tv3ws/src/server.ts:20`, `listen(httpPort)` sem endereço), então em modo host a API fica exposta na LAN sem passar pela borda, o que reabre a porta direta fechada no item 8. Precisa de um endereço de escuta configurável (`127.0.0.1`). Também é preciso restringir o anúncio à interface certa (`tv3ws/src/ssdp-server.ts`, `new Server` sem `interfaces`), para evitar as duplicatas |
| **B (escolhida em 04/10; substituída pela A em 09/10):** container só para o anúncio, em modo host | serviço novo no compose; borda e tv3ws continuam na bridge | **médio:** o anúncio está acoplado ao tv3ws. O `ssdp-server.ts` registra `/manifest` no app do tv3ws (linha 42) e é chamado no boot (`server.ts:46`). É preciso um modo "só anunciar". Contraria "a borda num container só" |
| **A (escolhida pelo Luís em 09/10):** a borda anuncia, em modo host (direção dita pelo Joel em 28/09) | a borda sai da `ginga_net` e passa a achar tv3ws e Redis por `localhost` | **grande:** a imagem da borda é KrakenD, sem Node. O anunciante precisa ser reescrito (Go, por exemplo) ou virar um processo Node a mais na borda. O `generate.js` precisa de uma variante nova, e o tv3ws precisa ser publicado em `127.0.0.1` |
| macvlan | o container ganha IP próprio na LAN | nenhum no código; configuração de rede específica de cada máquina |

Em todas as opções continuam valendo: `SERVER_URL` (ou `SSDP_ADVERTISE_HOST`) com o IP da LAN, UDP 1900 e TCP 44642 liberados no firewall do host, e nenhum isolamento de clientes no Wi-Fi.

## O que exige rede doméstica e um segundo dispositivo

A camada 3, a descoberta por outro dispositivo da LAN, precisa de:
- uma rede doméstica ou o hotspot do celular. Na rede corporativa, isolamento de clientes e firewall podem bloquear o multicast;
- uma máquina com Linux nativo rodando a stack com o override `docker-compose.ssdp.yml`, porque no WSL2 em NAT o multicast não sai da VM (medido acima);
- um segundo dispositivo na mesma rede.

Roteiro:

1. Na máquina da stack, ligue o anúncio da borda como na seção [Como ligar no Linux nativo](#como-ligar-no-linux-nativo) e confira os logs e o `tcpdump`.
2. No segundo dispositivo, rode o script abaixo. Ele tem dois resultados possíveis:
   - **positivo:** imprime a resposta ao M-SEARCH ou o NOTIFY, faz o GET no LOCATION e lista os seis cabeçalhos. Em seguida dá para seguir para `http://<Server-BaseURL>/tv3/authorize`;
   - **negativo:** termina com `nada encontrado`. Nesse caso, o GET direto em `http://<IP da LAN>:44642/manifest` ainda deve funcionar, porque é TCP na porta da borda. Isso separa a falha de descoberta da falha de acesso. Com a borda anunciando em Linux nativo, as causas a olhar são o firewall do host, o isolamento de clientes no Wi-Fi e a interface escolhida para o anúncio (`SSDP_INTERFACE` força outra). No arranjo anterior às opções B e A, com o tv3ws anunciando de dentro da bridge, esse era o resultado esperado.
3. **Controle positivo, se o resultado for negativo.** Desligue o anunciante da stack: comente o `COMPOSE_FILE` no `.env` e rode `docker compose up -d`, porque o anunciante não para sozinho sem derrubar a borda. Depois, confirme que o cliente e a rede funcionam com outro anunciante em modo host: um node-ssdp `Server` rodando direto no Linux, ou num container com `--network host`, anunciando o mesmo ST.
4. Registre os resultados, com a data e o arranjo usado.

Script de cliente (Node.js, com a mesma biblioteca do anunciante). Testado em 02/10 dentro da `ginga_net`, como controle positivo:

```js
// cliente-ssdp.js — descoberta do receptor TV 3.0 (C.3.4) a partir de OUTRO
// dispositivo da mesma rede. Requer Node.js e o pacote do anunciante:
//   npm install @lvcabral/node-ssdp && node cliente-ssdp.js [segundos]
const { Client } = require('@lvcabral/node-ssdp');
const http = require('http');
const ST = 'urn:schemas-sbtvd-org:service:TV3.0WebServices:1';
const secs = Number(process.argv[2] || 30);
const vistos = new Set();

function manifest(location) {            // 2a etapa: GET no LOCATION (TCP)
  if (vistos.has(location)) return;
  vistos.add(location);
  http.get(location, res => {
    const h = res.headers;               // nomes chegam em minusculas no node
    console.log(`  GET ${location} -> ${res.statusCode}`);
    for (const k of ['server-baseurl', 'server-securebaseurl', 'server-pairingmethods',
                     'device-brandname', 'device-model', 'device-friendlyname']) {
      console.log(`    ${k}: ${h[k] ?? '(ausente)'}`);
    }
    res.resume();
  }).on('error', e => console.log(`  GET ${location} falhou: ${e.code || e.message}`));
}

// ativo: M-SEARCH multicast, respostas unicast
const ativo = new Client();
ativo.on('response', (h, code, r) => {
  console.log(`resposta ao M-SEARCH de ${r.address}:${r.port} LOCATION=${h.LOCATION} USN=${h.USN}`);
  if (h.LOCATION) manifest(h.LOCATION);
});
ativo.search(ST);
setInterval(() => ativo.search(ST), 5000);

// passivo: NOTIFY multicast (precisa da porta UDP 1900 livre neste dispositivo)
const passivo = new Client({ sourcePort: 1900 });
passivo.on('advertise-alive', (h, r) => {
  if (h.NT !== ST) return;
  console.log(`NOTIFY de ${r.address} LOCATION=${h.LOCATION} USN=${h.USN}`);
  if (h.LOCATION) manifest(h.LOCATION);
});
passivo.start().catch(e => console.log(`escuta passiva indisponivel: ${e.message}`));

setTimeout(() => {
  console.log(vistos.size ? `fim: ${vistos.size} LOCATION(s) encontrado(s)` : `fim: nada encontrado em ${secs} s`);
  ativo.stop(); passivo.stop(); process.exit(vistos.size ? 0 : 1);
}, secs * 1000);
```

- **No celular Android:** use o Termux (`pkg install nodejs`, depois `npm install @lvcabral/node-ssdp`) e rode o mesmo script. Apps de DLNA costumam filtrar por MediaServer/MediaRenderer e não listam este ST.
- **Sem Node:** o `gssdp-discover --target urn:schemas-sbtvd-org:service:TV3.0WebServices:1` (pacote gupnp-tools) ou um script Python só com `socket` também servem.

> **Página web no navegador não faz UDP.** `fetch` e WebSocket usam TCP. WebTransport fala HTTP/3 com um servidor. WebRTC usa UDP só para ICE/DTLS entre pares negociados. A Direct Sockets API fica restrita a Isolated Web Apps. Nenhuma dessas APIs envia um M-SEARCH para 239.255.255.250:1900, então uma página aberta no celular não descobre o receptor. O navegador serve só para a segunda etapa: abrir `http://<IP da LAN>:44642/manifest` e ver os cabeçalhos no devtools.

## Pendências

- **Plataforma, decidida pelo Joel (informado pelo Luís em 04/10):** a descoberta SSDP só precisa funcionar em **Linux nativo** com Docker Engine. Windows com WSL2 e Docker Desktop ficam fora, como limitação documentada (testes 10 e 13).
- **L6, re-decidida pelo Luís em 09/10: opção A,** a borda anunciando em rede do host, com o override `docker-compose.ssdp.yml`. Substituiu a opção B (o container `tv3ws-ssdp`, decidida em 04/10, informado pelo Luís). O arranjo está na seção [Arranjo decidido](#arranjo-decidido-a-borda-anuncia-em-rede-do-host); a avaliação anterior às decisões ficou como registro.
- **Medições da opção A: nenhuma registrada.** Falta refazer, com ela, a subida e os logs, a captura do NOTIFY, a camada 3 com outro aparelho em Linux nativo e as falhas que derrubam a borda (UDP 1900 ocupada, interface inexistente, rede caindo).
- **Camada 3:** negativa no WSL2 (testes 10 e 13) e **positiva em Linux nativo em 09/10, com a opção B** (testes 30 e 32: notebook e celular no Wi-Fi doméstico encontram o receptor). **Com a opção A, ainda não medida**; o teste vai ser refeito.
- **Morre-inteiro na borda (decidido pelo Luís em 09/10):** com o override, uma falha do anúncio derruba todas as APIs até o `restart` trazer a borda de volta. Reabre o efeito do C8 de [Decisões pendentes](decisoes-pendentes.md), que a opção B tinha resolvido.
- **Duplicatas do teste 7:** resolvidas com a opção B. Entre a VM do WSL e o Windows, 1 resposta por M-SEARCH (teste 18); numa LAN com Linux nativo, 3 respostas a 3 buscas (teste 30). A opção A também anuncia e responde por uma interface só (`infra/edgegateway/ssdp/iface.go`), sem medição.
- **Imagem publicada:** até o push do infra e a publicação pelo CI, a `tv30-edgegateway` do Docker Hub não tem o `ssdp-announcer` nem os `krakend-*.host.json`. Pelo código do `entrypoint.sh` (o antigo também monta o nome do arquivo com `EDGE_VARIANT`), o override com essa imagem derruba a borda no boot, porque o KrakenD não acha a configuração `host`. Até lá, construa a imagem localmente (`docker compose build edgegateway`). A `tv30-tv3ws` publicada já tinha `dist/ssdp-announcer.js` em 09/10 (teste 28); com a opção A, ele não é mais usado.
- **`CACHE-CONTROL` da resposta ao M-SEARCH:** resolvido na opção A. A resposta da borda sai com `max-age=1800`, igual ao NOTIFY (`infra/edgegateway/ssdp/ssdp.go`). Até a opção B, saía `max-age=4` (testes 17 e 18). O tv3ws rodando sozinho no host (dev-host) continua com `max-age=4`, porque segue com a biblioteca node-ssdp e `ttl: 4` (`tv3ws/src/ssdp-server.ts`).
- **Segunda barreira (Windows):** medida em 04/10 (teste 13). Com o anunciante em modo host no WSL2, o celular continua sem receber nada.
- **B2, sem decisão:** o host padrão do anúncio. Continua `localhost` (`SERVER_URL`), com o aviso de loopback no boot.
