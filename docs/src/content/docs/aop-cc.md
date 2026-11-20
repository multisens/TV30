---
title: aop-cc
description: O componente aop-cc, o núcleo comum da plataforma - a aquisição da sinalização, a comporta de objetos, o cache de aplicações e o gerente de ciclo de vida; como recebe as chamadas, o que troca com o resto do testbed e o que ele define onde a norma deixa em aberto.
---

O `aop-cc` é o lado do receptor da camada de transporte. Ele faz quatro coisas:

- **Aquisição.** Busca no `bcast-sim` a LLS e a SLS de cada serviço e as distribui na mensageria.
- **Comporta.** Entrega os objetos de radiodifusão do serviço sintonizado só quando o carrossel os
  teria entregado, e serve cada aplicação de emissora na origem dela.
- **Cache de aplicações.** Guarda no Redis os arquivos das aplicações `STORED_*`.
- **Gerente de ciclo de vida.** Decide, pela BALD, que aplicação fica na camada de gráficos.

Como as quatro partes se encadeiam, com o carrossel e o ciclo de vida para experimentar, está em
[Camada de transporte simulada](../camada-de-transporte/). Quais peças da norma estão
implementadas está no mapa de [Escopo, limites e decisões](../escopo/#o-escopo-no-mapa).

## Como recebe as chamadas

A comporta, na porta 8081 (`OBJECT_PROXY_PUBLIC_PORT`), é a única porta do `aop-cc` fora do
container. Ela não tem API da norma, e a borda não passa por ela. Só `GET` e `HEAD`; outro método
recebe 405. O corpo de um erro diz o motivo, em texto.

**Família de serviço**, `/svc/<serviceId>/<caminho>`, em qualquer host que não seja uma origem de
aplicação:

| Pedido | Resposta |
|---|---|
| `sls`, depois da primeira passagem do canal de sinalização | 200, o pacote SLS, com `Last-Modified` no fim da última passagem |
| `sls` antes dela, ou um serviço sem descritor de emissão | 404 |
| um serviço que não é o sintonizado | 404 |
| antes da S-TSID do serviço | 503 |
| um arquivo da S-TSID | 200 enquanto disponível; 404 antes da passagem e depois do vencimento |
| um caminho do `fileTemplate` de um fluxo | o `bcast-sim` decide: 200 ou o 404 dele |
| um caminho que só o `BasePattern` de unicast da USBD casa | repassado ao `bcast-sim`, com os cabeçalhos dele |
| qualquer outro | 404, sem pedido ao `bcast-sim` |

**Família de aplicação**, qualquer caminho em `ctx-<h>.<APPS_DOMAIN>:8081`: um arquivo da S-TSID do
serviço sintonizado, ou uma parte de um pacote de entrada dele, cujo `appContextIdList` tem o
`appContextId` de hash `<h>`. Uma parte segue a disponibilidade do pacote. Quando o carrossel não
oferece o arquivo, a comporta o serve do cache, se ele estiver lá.

**Família de banda larga**, qualquer caminho em `bb-<h>.<APPS_DOMAIN>:8081`: repassado ao esquema e
ao host do `bbandEntryPointUrl` do mesmo `appContextId`, na BALD do serviço sintonizado, com o
caminho e a consulta do pedido, e respondido com o status e os cabeçalhos do servidor. Sem essa
entrada, 404.

**Ponte**, `/.tv30/bridge.js`, nas famílias de aplicação e de banda larga. Todo documento HTML que
elas servem com 200 leva a ponte antes de `</head>`; sem `</head>`, antes de `<body`; sem os dois, no
fim. Quando o corpo muda, o `ETag` do servidor de banda larga é retirado.

As respostas de radiodifusão levam o `Content-Type` da S-TSID (ou da parte), `Last-Modified` do
descritor de emissão, `Expires` pelo `maxExpiresDelta` e `Access-Control-Allow-Origin: *`. Um
`If-Modified-Since` igual ou posterior ao `Last-Modified` recebe 304. Falha do `bcast-sim` num objeto
declarado: 502, no log.

O cache tem rotas próprias, numa porta que só o próprio container alcança: `GET /app/<appContextId>`
diz se a aplicação está completa, e `GET /app/<appContextId>/<caminho>` devolve o arquivo.

## O que troca com o resto do testbed

| Canal | Assina, lê ou busca | Publica, grava ou serve |
|---|---|---|
| HTTP | a sinalização e os arquivos do `bcast-sim`; o servidor de cada aplicação de banda larga | a comporta, ao navegador e ao reprodutor de vídeo |
| mensageria | a sintonia; a LLS, a SLS e o descritor de emissão de cada serviço; os eventos de objeto; o pedido de encerramento da aplicação | a LLS, a SLS, o descritor de emissão e a marca de varredura; os eventos de objeto; o estado da aplicação, a aplicação da camada de gráficos e as aplicações `PRESENT` |
| armazenamento | os arquivos do cache | a origem da aplicação no ar em `origins:associated` e a aplicação em `session:current-app`; os arquivos do cache, em `cache:meta:*` e `cache:body:*` |

Toda escrita no Redis passa pelas funções da biblioteca `tv30`, que conferem o esquema. Os tópicos
estão em [Mensageria (MQTT)](../mensageria/#os-tópicos), e as famílias de chave, em
[Modelo de dados Redis](../modelo-redis/#as-famílias-de-chave).

## O que o aop-cc define

Valores e escolhas onde a norma deixa a decisão ao receptor ou não trata o caso.

### Aquisição

| Caso | O que o `aop-cc` faz |
|---|---|
| Intervalo da varredura | O menor `llsCyclePeriod` entre os canais RF; 5 s antes da primeira varredura e depois de uma que falhou |
| Falha do `bcast-sim` | Nada é publicado nem limpo: a plataforma fica com o que já tinha |
| Fragmento que não é JSON, ou MPD que não é XML bem formado | Não é publicado |
| Mensagem recusada pelo esquema do broker | Vai para o log e só é publicada de novo quando a versão mudar |
| Reinício | Tudo é publicado de novo; um tópico retido que a sinalização não declara mais é limpo na varredura seguinte |

### Comporta

| Caso | O que a comporta faz |
|---|---|
| Sintonia no meio de uma passagem | A passagem não conta: o objeto espera a seguinte |
| Troca de sintonia | Não gera `expired` para os objetos do serviço deixado |
| Origem de cada aplicação | `ctx-<h>` para radiodifusão e `bb-<h>` para banda larga, `<h>` os 16 primeiros dígitos hexadecimais do SHA-256 do `appContextId` |
| Aplicação de banda larga | Repassada pela comporta, na origem `bb-<h>`, e não aberta no endereço do servidor |

### Cache

| Caso | O que o cache faz |
|---|---|
| Quota por contexto de serviço DTV | `CACHE_QUOTA_BYTES`, 112 MB por padrão; o objeto que a passaria não é guardado |
| Total | `CACHE_TOTAL_BYTES`, 500 MB por padrão; passado o total, sai inteiro o contexto de último acesso mais antigo, exceto o que está sendo gravado |
| Último acesso | Toda leitura conta como acesso |

Os valores padrão são os do perfil de receptor 4K@60.

### Ciclo de vida

| Caso | O que o gerente faz |
|---|---|
| Várias entradas `AUTOSTART` ao mesmo tempo | Lança a última da BALD |
| Aplicação encerrada pelo espectador | Não volta enquanto o `controlCode` da entrada for o mesmo |
| Troca de serviço | Encerra a aplicação no ar |
| Troca de aplicação | O fim da que sai é publicado antes do início da que entra |
| Partida | Limpa `origins:associated` e `session:current-app` |
| Tipo de aplicação | Só `TV30-Ginga-HTML5` é lançada |

## Desenvolver e testar

- O `aop-cc` roda só em container, porque o compose fixa o endereço por que os outros containers o
  alcançam: [Desenvolvimento com serviço no host](../dev-local/).
- Os testes (`go vet ./...` e `go test ./...`, em `aop-cc/`): [Como testar](../como-testar/).
- As variáveis de ambiente e os pacotes do código: o `README.md` do `aop-cc`.
