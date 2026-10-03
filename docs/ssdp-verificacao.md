---
title: "Verificação: descoberta SSDP"
nav_order: 13
---

# Descoberta SSDP (C.3.4): o que foi medido e o que falta

Medição de 02/10/2026, com a stack completa de pé e a imagem do tv3ws reconstruída nesta semana. Ela cobre as camadas 1 e 2 do plano de teste: se o anúncio sai do container e se passa da rede do Docker. A camada 3, que é a descoberta por outro dispositivo da LAN, não pôde ser medida nesta máquina e está descrita no fim, com o roteiro e o script de cliente.

> **Norma × implementação.** A norma pede o anúncio SSDP e o GET no LOCATION, sem dizer onde o anunciante roda. Quem anuncia (hoje o tv3ws, num container da bridge `ginga_net`) e o caminho `/manifest` são decisões deste testbed. Mudar o anunciante de lugar é a lacuna **L6**, ainda sem decisão: borda em rede do host ou anunciante separado.

## O que a norma pede

ABNT NBR 25608, C.3.4, p. 197–198 (p. 215–216 do PDF):

- O receptor anuncia por SSDP (HTTPU) em UDP 1900, no multicast 239.255.255.250 (IPv4) ou ff02::c (IPv6). O anúncio usa NOTIFY e a busca usa M-SEARCH com `ST: urn:schemas-sbtvd-org:service:TV3.0WebServices:1`.
- A resposta ao M-SEARCH vai em unicast e "shall contain the LOCATION header".
- O GET no LOCATION devolve os cabeçalhos `Server-BaseURL`, `Server-SecureBaseURL`, `Server-PairingMethods`, `Device-BrandName`, `Device-Model` e `Device-FriendlyName`. Os dois primeiros têm o formato `<ip_or_hostname>:<port>`, e a porta do `Server-BaseURL` "shall be fixed: 44642".

## O que o código faz hoje

- **Anunciante:** `tv3ws/src/ssdp-server.ts`, com a biblioteca `@lvcabral/node-ssdp`. Ele manda dois NOTIFY a cada 10 s: um com `NT` igual ao URN do serviço e outro com o UDN puro. O UDN é fixo (`uuid:TV30-1234-5678-9012-345678901234`).
- **LOCATION:** `http://<host>:44642/manifest`. O `<host>` é `SSDP_ADVERTISE_HOST`, senão `SERVER_URL`, senão o IP local (`tv3ws/src/ssdp-config.ts`). As portas são as da **borda**, 44642 e 44643, configuráveis por `EDGE_HTTP_PORT` e `EDGE_HTTPS_PORT`.
- **`/manifest`:** declarado na tabela única da borda (`infra/edgegateway/routes.json`, `auth: none`, nas duas superfícies). O cliente chega ao tv3ws pela borda (D10), e não pelas portas 44652/44653, que não são publicadas.
- **Morre-inteiro (D9):** falha ao iniciar o SSDP encerra o processo com o log `[ssdp] FALHA ...`. No SIGTERM sai `ssdp:byebye`.
- **Compose:** o compose da raiz passa `SERVER_URL=${SERVER_URL:-localhost}`. Sem configuração, o anúncio diz `localhost`. `SSDP_ADVERTISE_HOST` chega ao container só pelo `tv3ws/.env`.

## Medido aqui (Windows 11 + WSL2 em NAT, Docker Engine dentro do WSL)

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
3. **Com a configuração padrão, o anúncio aponta para `localhost`.** Mesmo que o pacote chegasse a outro dispositivo, o LOCATION e o `Server-BaseURL` não serviriam. Para o teste em rede doméstica, defina `SERVER_URL=<IP da máquina na LAN>` no `.env` da raiz. Esse valor também é o que vai na URL de WebSocket do remote-device. Outra opção é `SSDP_ADVERTISE_HOST` no `tv3ws/.env`.
   - Desde 03/10 o tv3ws registra no boot um `[ssdp] AVISO` quando o host anunciado é de loopback. O padrão não mudou. PENDENTE (Joel): cair no IP local quando `SERVER_URL` for loopback, ou exigir `SSDP_ADVERTISE_HOST`.
   - **`Server-SecureBaseURL` aponta para porta sem TLS.** O `/manifest` anuncia `<host>:44643`, a superfície externa da borda, que ainda é HTTP puro (lacuna L3). Um cliente não local que siga a C.3.4 e use `https://<Server-SecureBaseURL>/tv3/<API>` falha nessa porta. O tv3ws também registra isso no boot. PENDENTE (Joel): até a decisão da L3, anunciar a borda (como hoje) ou o HTTPS do próprio tv3ws, que não é publicado no host.
4. **Observações, sem correção nesta semana:**
   - **Nomes dos cabeçalhos.** A borda (Go) entrega os nomes canonizados: `Server-Baseurl` em vez de `Server-BaseURL`. Nome de cabeçalho HTTP não diferencia maiúsculas (RFC 9110, 5.1), então cliente correto lê os dois. Cliente que compare com distinção de maiúsculas falha.
   - **CORS.** A borda expõe ao navegador só `Content-Length` e `X-TV30-Auth-Warn`. Um script de página que leia `/manifest` por `fetch` não enxerga os cabeçalhos `Server-*` e `Device-*`. Não há decisão sobre expô-los.
   - **UDN fixo.** Dois testbeds na mesma LAN anunciam o mesmo UDN e o mesmo USN. A C.6.1.4.1 usa o USN para distinguir receptores.
   - **Fora do código atual:** IPv6 (ff02::c), porque os sockets são só `udp4`, e a descoberta de TV 2.X WebServices (ABNT NBR 15606-11, 6.3).

Os comandos acima rodaram dentro da VM do WSL (`wsl.exe -u root bash <script>`). O M-SEARCH enviado à bridge usou TTL 1 e não saiu da VM. Nenhum pacote foi enviado à rede da ONS.

## O que exige rede doméstica e um segundo dispositivo

A camada 3, a descoberta por outro dispositivo da LAN, precisa de:
- uma rede doméstica ou o hotspot do celular. Na rede corporativa, isolamento de clientes e firewall podem bloquear o multicast;
- uma máquina com Linux nativo rodando a stack, porque no WSL2 em NAT o multicast não sai da VM (medido acima);
- um segundo dispositivo na mesma rede.

Roteiro:

1. Na máquina da stack, defina `SERVER_URL=<IP da LAN>` no `.env` da raiz e rode `docker compose up -d`. No log do tv3ws deve aparecer `[ssdp] anunciando ... LOCATION http://<IP da LAN>:44642/manifest (host via SERVER_URL)`.
2. **Controle positivo.** Antes, confirme que o cliente e a rede funcionam com um anunciante fora da bridge: um node-ssdp `Server` rodando direto no Linux, ou num container com `--network host`, anunciando o mesmo ST.
3. No segundo dispositivo, rode o script abaixo. Ele tem dois resultados possíveis:
   - **positivo:** imprime a resposta ao M-SEARCH ou o NOTIFY, faz o GET no LOCATION e lista os seis cabeçalhos. Em seguida dá para seguir para `http://<Server-BaseURL>/tv3/authorize`;
   - **negativo, o esperado com o tv3ws na bridge:** termina com `nada encontrado`. Nesse caso, o GET direto em `http://<IP da LAN>:44642/manifest` ainda deve funcionar, porque é TCP pela porta publicada. Isso separa a falha de descoberta da falha de acesso.
4. Registre os dois resultados. Eles alimentam a decisão da L6.

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

- **L6, sem decisão:** onde roda o anunciante. As opções são a borda em `network_mode: host` ou um anunciante separado na rede do host. Nada foi mudado.
- **Camada 3 não medida:** depende de rede doméstica, Linux nativo e um segundo dispositivo (roteiro acima).
