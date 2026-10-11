---
title: Descoberta SSDP
parent: Como funciona
nav_order: 6
---

# Descoberta SSDP (C.3.4)

Como o receptor se anuncia na rede local para que outro aparelho o encontre (ABNT NBR 25608, C.3.4): o que a norma pede, o que o código faz hoje, como ligar o anúncio no Linux nativo e como verificar com um segundo aparelho. A descoberta é opcional na stack: sem o override `docker-compose.ssdp.yml`, nada é anunciado, e o cliente chega ao receptor pelo IP (`http://<IP>:44642/manifest`).

Os números de teste citados nesta página (testes 6 a 57) são os das [Medições da descoberta SSDP](ssdp-verificacao.md), no Histórico, que registram cada medição com a data e o arranjo do dia.

{: .nota }
A norma pede o anúncio SSDP e o GET no `LOCATION`, sem dizer onde o anunciante roda. Quem anuncia (a borda, em rede do host) e o caminho `/manifest` são decisões deste testbed. Onde fica o anunciante era a lacuna **L6**, decidida pelo Luís em 09/10 (opção A).

**Arranjo atual, decidido pelo Luís em 09/10 (L6, opção A):** quem anuncia é a borda (`edgegateway`), posta em rede do host pelo override `docker-compose.ssdp.yml`, só em Linux nativo. A opção A substituiu a opção B, decidida em 04/10 (informado pelo Luís), em que o anúncio saía de um container próprio, o `tv3ws-ssdp`, em rede do host, com a borda, o tv3ws e o resto na bridge `ginga_net`.

## O que a norma pede

ABNT NBR 25608, C.3.4, p. 197–198 (p. 215–216 do PDF):

- O receptor anuncia por SSDP (HTTPU) em UDP 1900, no multicast 239.255.255.250 (IPv4) ou ff02::c (IPv6). O anúncio usa NOTIFY e a busca usa M-SEARCH com `ST: urn:schemas-sbtvd-org:service:TV3.0WebServices:1`.
- A resposta ao M-SEARCH vai em unicast e "shall contain the LOCATION header".
- O GET no LOCATION devolve os cabeçalhos `Server-BaseURL`, `Server-SecureBaseURL`, `Server-PairingMethods`, `Device-BrandName`, `Device-Model` e `Device-FriendlyName`. Os dois primeiros têm o formato `<ip_or_hostname>:<port>`, e a porta do `Server-BaseURL` "shall be fixed: 44642".

## O que o código faz hoje

Estado desde 09/10 (opção A), com a política de falha decidida pelo Luís em 10/10 e o host do anúncio decidido por ele em 11/10 (B2). O arranjo das medições de 02/10 e o da opção B estão nas [Medições da descoberta SSDP](ssdp-verificacao.md), seções *Medido aqui* e *Medido em 04/10 — opção B*.

- **Quem anuncia:** a borda (`edgegateway`). O anunciante é um processo a mais no container dela, o binário `/usr/local/bin/ssdp-announcer`, escrito em Go só com a biblioteca padrão (`infra/edgegateway/ssdp/`). Ele é compilado no estágio `ssdp` do `infra/edgegateway/Dockerfile`, depois de `go vet` e `go test`: teste falhando, a imagem não sai. O `entrypoint.sh` da borda só o sobe com `SSDP_ENABLED=true` (ou `1`); o padrão é desligado, e o boot registra `ssdp=desligado`. Quem liga é o override `docker-compose.ssdp.yml` da raiz, junto com a rede do host (seção [Arranjo decidido](#arranjo-decidido-a-borda-anuncia-em-rede-do-host)). O anunciante manda dois NOTIFY a cada 10 s, com TTL 4: um com `NT` igual ao URN do serviço e outro com o UDN puro. O UDN é fixo (`uuid:TV30-1234-5678-9012-345678901234`), e a variável `UDN` o troca.
- **Formato das mensagens:** o mesmo do anunciante anterior (a biblioteca `@lvcabral/node-ssdp`, no tv3ws): `USN` igual a `<UDN>::<URN>` e a `<UDN>`, `LOCATION` e `CACHE-CONTROL: max-age=1800` no NOTIFY. Duas diferenças, conferidas no código (`infra/edgegateway/ssdp/ssdp.go`): a resposta ao M-SEARCH sai com `max-age=1800`, e não mais `max-age=4` (testes 17 e 18), e o cabeçalho `SERVER` passou a ser `Linux UPnP/1.1 tv30-ssdp/1.0`, no lugar da assinatura da biblioteca. O primeiro NOTIFY sai logo depois de abrir os sockets; na biblioteca, saía 3 s depois. O M-SEARCH é respondido quando traz `MAN: "ssdp:discover"`, `MX` e um `ST` igual ao URN, ao UDN ou a `ssdp:all`.
- **O tv3ws da bridge não anuncia.** O compose põe `SSDP_ENABLED: "false"` nele, e o boot registra `[ssdp] anuncio desligado (SSDP_ENABLED=false)`. Fora do compose, `SSDP_ENABLED` vale ligado por padrão: o tv3ws rodando sozinho no host anuncia por conta própria, com a biblioteca node-ssdp (`tv3ws/src/ssdp-server.ts`), como antes.
- **Interface:** o anúncio sai só pela interface IPv4 que tem o IP do host anunciado, e a busca é respondida por ela. Se o host não for um IP da máquina (um nome, ou um IP que não está em nenhuma interface), sai pela interface da rota padrão (`/proc/net/route`), com aviso no log. `SSDP_INTERFACE` (nome da interface) força a escolha. Na borda, sem nenhuma interface possível, o anunciante espera a rede e tenta de novo (falta de rede, abaixo); até 09/10, isso era erro e derrubava a borda. No tv3ws, esse caso anuncia por todas as interfaces, com aviso.
- **LOCATION:** `http://<host>:44642/manifest`. Na borda, desde 11/10 (B2, decisão do Luís), o `<host>` é o `SSDP_ADVERTISE_HOST`, **obrigatório** com o anúncio ligado: ausente ou vazio é erro de configuração, e o `SERVER_URL` e o IP local deixaram de ser fonte do host (`infra/edgegateway/ssdp/config.go`). O valor é limpo do mesmo jeito que antes (tira esquema, caminho e porta). Até 11/10, a borda seguia a cadeia `SSDP_ADVERTISE_HOST`, senão `SERVER_URL`, senão o IP local, a mesma do tv3ws. As portas são as da **borda**, 44642 e 44643. `EDGE_HTTP_PORT` e `EDGE_HTTPS_PORT` mudam só as portas anunciadas, e não as portas em que o KrakenD escuta, fixas em `infra/edgegateway/routes.json` (`surfaces.*.port`).
- **`/manifest`:** servido pelo tv3ws, na bridge, e declarado na tabela única da borda (`infra/edgegateway/routes.json`, `auth: none`, nas duas superfícies). O cliente chega ao tv3ws pela borda (D10). As portas 44652/44653 do tv3ws não são publicadas na stack padrão; com o override, são publicadas só em `127.0.0.1`, para a borda. O tv3ws manteve a cadeia antiga (`SSDP_ADVERTISE_HOST`, senão `SERVER_URL`, senão o IP local; `tv3ws/src/ssdp-config.ts`). Com o anúncio ligado, a borda e o tv3ws leem o `SSDP_ADVERTISE_HOST` dos mesmos arquivos (item *Compose*, abaixo), e, como ele é obrigatório, o `Server-BaseURL` e o `LOCATION` saem do mesmo valor. Sem o anúncio, o `/manifest` pedido pelo IP usa o `SSDP_ADVERTISE_HOST` se estiver no `.env`, senão o `SERVER_URL` (`localhost` por padrão). Com o tv3ws rodando no host, fora do compose, a igualdade não é garantida: o tv3ws do host não lê o `.env` da raiz ([dev-local.md](dev-local.md#limites)).
- **Cabeçalhos legíveis pelo navegador (B3, decisão do Luís em 11/10):** o `/manifest` manda `Access-Control-Expose-Headers` com os seis nomes da C.3.4 (`tv3ws/src/manifest.ts`), e um script de outra origem lê os cabeçalhos pelo `fetch`. Até 11/10, o navegador entregava a resposta sem mostrar esses cabeçalhos ao script.
- **`Server-SecureBaseURL` na bridge:** o `/manifest` diz `<host>:<EDGE_HTTPS_PORT>` (padrão 44643). Desde a C1 (decisão do Luís em 11/10), na bridge, a 44643 da borda sai numa porta de host escolhida pelo Docker, e esse endereço não é o da superfície externa no host (pelo código; sem decisão, `KNOWN-ISSUES.md`). No modo SSDP, a borda está em rede do host, e a 44643 vale. Na bridge, `EDGE_EXT_PUBLISH=44643:44643` no `.env` da raiz a fixa.
- **Falha do anúncio na borda (D9; morre-inteiro decidido pelo Luís em 09/10 e revisto por ele em 10/10):** "derrubar a borda só em erro de configuração e tolerar a falta de rede com novas tentativas". O `entrypoint.sh` da borda vigia o anunciante junto com os dois KrakenD e o httpd da documentação: se ele sai, o container inteiro encerra, **todas as APIs caem**, e o `restart: unless-stopped` traz a borda de volta. O que muda com a decisão de 10/10 é quando o anunciante sai.
  - **Encerra (saída 1; a borda cai inteira), por erro de configuração:** desde 11/10 (B2), o `SSDP_ADVERTISE_HOST` ausente, vazio ou sem host (o `preflight` já barra a subida antes); porta inválida em `EDGE_HTTP_PORT`/`EDGE_HTTPS_PORT`; `SSDP_INTERFACE` com um nome que não existe na máquina; a UDP 1900 ocupada por outro processo com um socket sem `SO_REUSEADDR` (`EADDRINUSE` no bind); e os outros erros que não são de rede.
  - **Espera e tenta de novo, sem derrubar a borda, por falta de rede:** nenhuma interface com IPv4; nenhuma rota padrão; a interface de `SSDP_INTERFACE` existe, mas sem IPv4; erro de envio por falta de rede (`ENETUNREACH`, `EADDRNOTAVAIL`, `EHOSTUNREACH`, `ENETDOWN` e afins). Nesse estado, o anunciante fecha os sockets, e não anuncia nem responde a buscas. Ele registra um aviso ao entrar no estado e outro ao sair, sem repetir a cada tentativa, e tenta de novo com espera crescente, escolhendo de novo a interface e o IP de origem a cada tentativa. Quando a rede volta, volta a anunciar. As APIs ficam de pé o tempo todo.
  - O `LOCATION` sai do `SSDP_ADVERTISE_HOST`, conferido uma vez, na partida: ele não acompanha a troca de rede (teste 45). Desde a B2 (Luís, 11/10), isso é consequência da decisão. Numa troca de rede, o anúncio volta pela interface escolhida de novo, com o mesmo `LOCATION`, e com aviso se o IPv4 configurado não estiver mais em nenhuma interface (`infra/edgegateway/ssdp/main.go`).
  - A falha ao responder um M-SEARCH só gera `[ssdp] AVISO`, como antes. O texto exato dos logs está em `infra/edgegateway/ssdp/`.
  - Até 09/10, qualquer falha do anúncio encerrava o anunciante: inclusive a falta de interface e o erro de envio de um NOTIFY. Numa troca de rede, isso fez a borda reiniciar 12 vezes (teste 44).
  - **O tv3ws não mudou** (diferença registrada em 10/10): rodando sozinho no host, com `SSDP_ENABLED` ligado, o anunciante Node (`tv3ws/src/ssdp-server.ts`) ainda encerra o processo inteiro, APIs inclusive, em qualquer falha de configuração ou de socket do anúncio. Sem interface escolhida, ele anuncia por todas as interfaces IPv4, com aviso, em vez de esperar.
- **Parada:** no SIGTERM, o `entrypoint.sh` para o anunciante primeiro e espera que ele saia, para o `ssdp:byebye` (um por `NT`) sair antes de o container acabar. O anunciante envia o byebye e sai, sem `ssdp:alive` depois dele (o envio periódico e o tratamento do sinal ficam no mesmo laço, em `main.go`). Medido com a opção A nos testes 37, 51 e 54 (2 `ssdp:byebye`, um por `NT`); com a B, nos testes 25 e 26. Sem rede, o anunciante sai sem byebye, porque não há socket aberto.
- **Compose:** o `SERVER_URL` vem da seção `environment` da borda (no override) e do tv3ws (`${SERVER_URL:-localhost}`, do `.env` da raiz ou do shell). `SSDP_ADVERTISE_HOST`, `SSDP_INTERFACE`, `EDGE_HTTP_PORT` e `EDGE_HTTPS_PORT` (e, na borda, `UDN`) ficam fora da seção `environment`: a borda e o tv3ws leem os mesmos arquivos de ambiente, primeiro o `tv3ws/.env` e depois o `.env` da raiz, que prevalece. Um valor só exportado no shell não chega a eles. Motivo (conferido com `docker compose config`, compose v5.4.0, em 04/10, com a opção B): na seção `environment`, até o valor vazio (`${SSDP_ADVERTISE_HOST:-}`) apagaria o do `tv3ws/.env`. Efeito colateral: as outras chaves do `.env` da raiz também entram no ambiente dos dois containers. Na borda, as chaves que a seção `environment` define (`EDGE_VARIANT`, `REDIS_HOST`, `REDIS_PORT`, `SSDP_ENABLED`, `SERVER_URL`, `JWT_SECRET`, `JWT_ISSUER` e `AUTH_ENFORCE`) continuam valendo, porque ela tem precedência sobre o `env_file`. Desde 11/10 (B2), o override passa os mesmos dois arquivos também ao `preflight`, que confere o `SSDP_ADVERTISE_HOST` com o valor que a borda vai usar e para a subida (exit 1) sem ele; até ali, sem configuração, o anúncio dizia `localhost`. Sem o override, nada é anunciado.

## Arranjo decidido: a borda anuncia em rede do host

**L6 re-decidida pelo Luís em 09/10: opção A.** Quem anuncia é a borda, posta em rede do host. A opção A substituiu a opção B (o container `tv3ws-ssdp`), decidida em 04/10 (informado pelo Luís) e validada em Linux nativo em 09/10 (testes 28 a 32), antes da troca. Na avaliação de 03/10, a A aparece como a direção dita pelo Joel em 28/09 (seção [*L6: as opções avaliadas antes da decisão*](ssdp-verificacao.md#l6-as-opções-avaliadas-antes-da-decisão-decisão-do-projeto-não-da-norma), nas Medições). É decisão de implementação deste testbed, não da norma: a C.3.4 não diz onde o anunciante roda.

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
  - No `preflight`: `SSDP_EDGE=true`, que liga as checagens da borda em rede do host (*Como ligar*, abaixo), e, desde 11/10, os mesmos arquivos de ambiente da borda, para a checagem do `SSDP_ADVERTISE_HOST` (B2).
- **Variante `host` da borda.** `infra/edgegateway/routes.json` ganhou backends `host`: `http://127.0.0.1:44652` na superfície interna e `https://127.0.0.1:44653` na externa. O `generate.js` gera `krakend-internal.host.json` e `krakend-external.host.json` no build, ao lado das variantes `linux` e `windows`. O Redis é alcançado pela 6379 publicada.
- **Portas da borda direto no host.** 44642, 44643 e a 8085 da documentação passam a ser abertas pelos processos da borda na rede do host, sem `docker-proxy`, e ficam fixas. A 8085 deixa de ser dinâmica nesse modo: a documentação fica em `http://localhost:8085`. A 44643, que na bridge sai numa porta de host escolhida pelo Docker desde a C1 (decisão do Luís em 11/10), aqui é a própria 44643, a que vai no `Server-SecureBaseURL`; o `EDGE_EXT_PUBLISH` não vale nesse modo, porque o override zera os `ports` da borda.
- **O `/manifest` fica no tv3ws,** atrás da borda, e responde com ou sem o override. O tv3ws da bridge recebe `SSDP_ENABLED: "false"` e não anuncia.
- **No compose, o host do `LOCATION` e o do `/manifest` vêm do mesmo `SSDP_ADVERTISE_HOST`,** lido dos mesmos arquivos de ambiente (`tv3ws/.env` e `.env` da raiz, que prevalece). Desde a B2 (decisão do Luís em 11/10), ele é obrigatório com o override: a borda não cai mais no `SERVER_URL`, e o tv3ws, que ainda cairia, recebe o mesmo valor. Até 11/10, o padrão era `localhost`, com aviso no boot.
- **Interface:** a que tem o IP anunciado; senão, a da rota padrão, com aviso; `SSDP_INTERFACE` força. Sem nenhuma, o anunciante espera a rede e tenta de novo (desde 10/10); `SSDP_INTERFACE` com um nome que não existe na máquina é erro.
- **Só o erro de configuração do anúncio derruba a borda inteira** (decisão do Luís em 10/10, que revê o morre-inteiro de 09/10), e o `restart` a traz de volta. A falta de rede não derruba: o anunciante espera e tenta de novo, e as APIs ficam de pé. A lista do que encerra e do que espera está no item *Falha do anúncio na borda*, acima, e no C8 de [Decisões pendentes](decisoes-pendentes.md). Na opção B, qualquer falha derrubava só o `tv3ws-ssdp`, e as APIs não caíam. De 09/10 até a decisão de 10/10, qualquer falha derrubava a borda inteira, e na troca de rede do teste 44 ela reiniciou 12 vezes sem servir as APIs.
- **Só Linux nativo com Docker Engine** (decisão do Joel, informada pelo Luís em 04/10, que continua valendo).

### Como ligar no Linux nativo

1. No `.env` da raiz (o `COMPOSE_PROFILES=mqtt,linux` fica como está; o perfil `ssdp` deixou de existir):

   ```bash
   COMPOSE_FILE=docker-compose.yml:docker-compose.ssdp.yml
   SSDP_ADVERTISE_HOST=192.168.0.12   # IP desta máquina na rede local (obrigatório desde 11/10, B2)
   #SSDP_INTERFACE=wlan0              # só se a escolha automática errar
   ```

2. Quem tinha a opção B de pé remove o container antigo: `docker rm -f tv3ws-ssdp`, ou `docker compose up -d --remove-orphans`. O serviço saiu do compose, e sem isso ficariam dois anunciantes.
3. `docker compose up -d`. O `preflight` (`docker logs tv30-preflight`) para a subida sem `SSDP_ADVERTISE_HOST` (`ERRO: o anuncio SSDP esta ligado (docker-compose.ssdp.yml) e falta SSDP_ADVERTISE_HOST`; desde 11/10), e avisa, sem bloquear, quando a UDP 1900 já está ocupada por outro processo e quando o `tv3ws-ssdp` antigo está de pé. Num novo `up -d`, a 44642 ocupada pelo KrakenD da própria borda vira aviso, e não erro. As checagens vêm do `SSDP_EDGE=true` do próprio override, e por isso acompanham o arranjo, o que com o perfil `ssdp` dependia de como ele era ligado (teste 24).
4. Confira os logs:
   - `docker logs edgegateway`: a linha `[edgegateway] ... (variant=host, ssdp=ligado)`, as linhas `[ssdp] AVISO` e a linha `[ssdp] anunciando urn:schemas-sbtvd-org:service:TV3.0WebServices:1 em UDP 1900 pela interface <nome> (<IP>, via host-ip); LOCATION http://<IP da LAN>:44642/manifest (host de SSDP_ADVERTISE_HOST)` (até 11/10, o fim da linha era `(host via SSDP_ADVERTISE_HOST)`, ou `via SERVER_URL`, ou `via local-ip`);
   - `docker logs tv3ws`: `[ssdp] anuncio desligado (SSDP_ENABLED=false); o /manifest continua servido por este processo`.
5. Confira que o anúncio sai: `sudo tcpdump -ni <interface> udp port 1900` mostra dois NOTIFY a cada 10 s, com o `LOCATION` acima.
6. Libere no firewall do host a UDP 1900 e a TCP 44642 (e a 44643, para o cliente não local).
7. No segundo aparelho, rode o roteiro da seção *O que exige rede doméstica e um segundo dispositivo*, mais abaixo.

Os textos de log acima são os do código (`infra/edgegateway/entrypoint.sh` e `infra/edgegateway/ssdp/main.go`). Com a opção A, foram conferidos numa subida no WSL2 em 10/10 (testes 52 a 57), com o texto de antes de 11/10; o `(host de SSDP_ADVERTISE_HOST)` e a mensagem do `preflight` são do código de 11/10, sem medição registrada aqui.

Cuidados:
- **Para desligar,** comente o `COMPOSE_FILE` no `.env` da raiz e rode `docker compose up -d`. A borda e o tv3ws são recriados com a configuração padrão: a borda volta à `ginga_net`, sem anúncio, e as portas 44652/44653 deixam de ser publicadas (conferido com a opção A no WSL2 em 10/10, teste 57, desligando o override no shell).
- **Desenvolvimento com módulo no host:** o `scripts/test-dev-host.sh` roda sempre com a borda na bridge (`COMPOSE_FILE=docker-compose.yml`) e, no fim, restaura a configuração do `.env`, com o override se ele estiver ligado. À mão, use o mesmo prefixo ([dev-local.md](dev-local.md)).

Em Windows com WSL2, o anúncio em modo host chega ao próprio Windows, mas não aos outros aparelhos da rede (testes 12 e 13, com o anunciante descartável em modo host). O Docker Desktop, que também roda o Docker numa VM, fica fora do suporte, sem medição. Nesses ambientes, deixe o `COMPOSE_FILE` comentado; o cliente chega pelo IP, sem a etapa de descoberta: `http://<IP>:44642/manifest`.

## O que exige rede doméstica e um segundo dispositivo

A camada 3, a descoberta por outro dispositivo da LAN, precisa de:
- uma rede doméstica ou o hotspot do celular. Na rede corporativa, isolamento de clientes e firewall podem bloquear o multicast;
- uma máquina com Linux nativo rodando a stack com o override `docker-compose.ssdp.yml`, porque no WSL2 em NAT o multicast não sai da VM (medido em 02 e 04/10, testes 10 e 13);
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

> **Página web no navegador não faz UDP.** `fetch` e WebSocket usam TCP. WebTransport fala HTTP/3 com um servidor. WebRTC usa UDP só para ICE/DTLS entre pares negociados. A Direct Sockets API fica restrita a Isolated Web Apps. Nenhuma dessas APIs envia um M-SEARCH para 239.255.255.250:1900, então uma página aberta no celular não descobre o receptor. O navegador serve só para a segunda etapa: abrir `http://<IP da LAN>:44642/manifest` e ver os cabeçalhos no devtools, ou, desde a B3 (11/10), lê-los por `fetch` num script de outra origem.

## Pendências

- **Plataforma, decidida pelo Joel (informado pelo Luís em 04/10):** a descoberta SSDP só precisa funcionar em **Linux nativo** com Docker Engine. Windows com WSL2 e Docker Desktop ficam fora, como limitação documentada (testes 10 e 13).
- **L6, re-decidida pelo Luís em 09/10: opção A,** a borda anunciando em rede do host, com o override `docker-compose.ssdp.yml`. Substituiu a opção B (o container `tv3ws-ssdp`, decidida em 04/10, informado pelo Luís). O arranjo está na seção [Arranjo decidido](#arranjo-decidido-a-borda-anuncia-em-rede-do-host); a avaliação anterior às decisões ficou como registro.
- **Medições da opção A:** a subida e os logs, o NOTIFY, a camada 3 com outro aparelho em Linux nativo, a morte do processo e a troca de rede estão nos testes 33 a 46. A política de falha decidida em 10/10 foi medida no WSL2 nos testes 47 a 57: a UDP 1900 ocupada e a `SSDP_INTERFACE` inexistente derrubam a borda, e a rede caindo e voltando não a derruba. Falta medi-la em Linux nativo, numa troca de rede de verdade (o caso do teste 44), e, com a borda real, a máquina sem nenhuma interface com IPv4.
- **Camada 3:** negativa no WSL2 (testes 10 e 13) e **positiva em Linux nativo em 09/10, com a opção B** (testes 30 e 32: notebook e celular no Wi-Fi doméstico encontram o receptor). **Com a opção A, positiva em Linux nativo em 09/10** (testes 40 a 43, com o notebook como segundo aparelho).
- **Falha do anúncio na borda (morre-inteiro decidido pelo Luís em 09/10, revisto por ele em 10/10):** com o override, só o erro de configuração do anúncio derruba todas as APIs até o `restart` trazer a borda de volta; a falta de rede faz o anunciante esperar e tentar de novo, com as APIs de pé (C8 de [Decisões pendentes](decisoes-pendentes.md)). **Diferença que ficou:** o anunciante Node do tv3ws, usado só no dev-host, não mudou, e qualquer falha dele ainda derruba o processo inteiro.
- **Duplicatas do teste 7:** resolvidas com a opção B. Entre a VM do WSL e o Windows, 1 resposta por M-SEARCH (teste 18); numa LAN com Linux nativo, 3 respostas a 3 buscas (teste 30). A opção A também anuncia e responde por uma interface só (`infra/edgegateway/ssdp/iface.go`), sem medição.
- **Imagem publicada** (revisto em 10/10, pela data das imagens no Docker Hub; o conteúdo da imagem não foi inspecionado): o anunciante e os `krakend-*.host.json` entraram no infra `a671419` (09/10), e a `labmultisens/tv30-edgegateway:latest` mais recente foi publicada em 10/10, às 14:45 UTC, logo depois do push do infra `2bc858c`; os testes 40 a 43 (09/10) já usaram imagens publicadas pelo CI. Até 09/10, antes do push, a imagem publicada não tinha o anunciante, e o override com ela derrubava a borda no boot, porque o KrakenD não achava a configuração `host` (pelo código do `entrypoint.sh`). Com o código do clone mais novo que a imagem publicada, construa a borda localmente (`docker compose build edgegateway`).
- **`CACHE-CONTROL` da resposta ao M-SEARCH:** resolvido na opção A. A resposta da borda sai com `max-age=1800`, igual ao NOTIFY (`infra/edgegateway/ssdp/ssdp.go`). Até a opção B, saía `max-age=4` (testes 17 e 18). O tv3ws rodando sozinho no host (dev-host) continua com `max-age=4`, porque segue com a biblioteca node-ssdp e `ttl: 4` (`tv3ws/src/ssdp-server.ts`).
- **Segunda barreira (Windows):** medida em 04/10 (teste 13). Com o anunciante em modo host no WSL2, o celular continua sem receber nada.
- **B2, decidida pelo Luís em 11/10:** com o anúncio ligado, `SSDP_ADVERTISE_HOST` obrigatório; sem ele, o `preflight` para a subida, e o anunciante da borda sai com erro de configuração. Até 11/10, o padrão era `localhost` (`SERVER_URL`), com o aviso de loopback no boot. Consequência: o `LOCATION` não acompanha troca de rede. O anunciante Node do tv3ws (só dev-host) não mudou.
- **B3, decidida pelo Luís em 11/10:** o `/manifest` expõe os seis cabeçalhos ao navegador (`Access-Control-Expose-Headers`).
- **`Server-SecureBaseURL` na bridge, sem decisão:** com a C1, ele diz 44643, que na bridge não é a porta de host da externa (item *`Server-SecureBaseURL` na bridge*, acima). O que anunciar enquanto a L3 estiver aberta também segue com o Joel.
