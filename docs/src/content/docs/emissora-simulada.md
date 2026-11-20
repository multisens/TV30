---
title: Emissora simulada
description: O bcast-sim, a emissora simulada do testbed - o que ele serve, como se declara um serviço, os serviços de exemplo e o vídeo ao vivo.
---

O `bcast-sim` faz o papel da emissora, fora do receptor. Ele serve, por HTTP, a sinalização da camada
de transporte, os arquivos dos serviços e o vídeo ao vivo, e não publica nada na mensageria: quem vai
buscar e distribui dentro da plataforma é o `aop-cc`. O que isso representa no mundo real está em
[O que o testbed simula](../o-que-simula/).

O `bcast-sim` é só o motor. Os serviços são declarações e arquivos numa pasta de emissão; a que sobe
com o testbed é `bcast-sim/example/`, montada somente leitura em `/emission`. Mudar um arquivo dela
recarrega as declarações, sem reiniciar o container; no Docker Desktop, o recarregamento pode parar de
acontecer ([Solução de problemas](../troubleshooting/#emissora-simulada)).

## O que ele serve

Na porta 8082 (`LIVE_PUBLIC_PORT`):

| Rota | O que devolve |
|---|---|
| `/signaling/lls` | a SLT e a BAMT de cada canal RF, em JSON; `?rf=<bsid>`, as de um canal |
| `/signaling/sls/<serviceId>` | o pacote SLS (`multipart/related`): o envelope de metadados e, conforme a declaração, USBD, S-TSID, MPD, BALD e PRRD |
| `/signaling/emission/<serviceId>` | o descritor de emissão de um serviço com carrossel: os fluxos, a ordem e o período de cada objeto |
| `/services/<serviceId>/<caminho>` | um arquivo de `servicos/<serviceId>/arquivos/`; uma pasta declarada como pacote de entrada sai em `multipart/related`, uma parte por arquivo |
| `/live/<streamId>/…` | o fluxo ao vivo: `master.m3u8`, `playlist.m3u8`, `mpd`, `init.mp4` e `seg/<n>.m4s` |

Os fragmentos são JSON, campo a campo com os nomes da norma; só a MPD é XML. A versão de um fragmento
só muda quando o conteúdo muda.

O `aop-cc` busca a LLS a cada `llsCyclePeriod` e, para cada serviço da SLT, o pacote SLS. Num serviço
com carrossel, a SLS e os arquivos chegam pela comporta, que só os entrega depois de passarem no
carrossel ([aop-shell](../aop-shell/#aplicações-de-emissora)). Os tópicos onde a sinalização chega
estão em [Mensageria (MQTT)](../mensageria/#os-tópicos).

## Declarar um serviço

```
canais/<bsid>.json                  canal RF: largura de banda, agrupamento da BAMT e serviços
servicos/<serviceId>/
    servico.json                    entrada da SLT, BAM e entrega
    aplicacao.json                  as aplicações da BALD (opcional)
    carrossel.json                  o carrossel de radiodifusão (opcional)
    privacidade.json                a PRRD (opcional)
    fluxos/<streamId>.json          declaração de cada fluxo
    segmentos/<streamId>/           segmento de inicialização e segmentos de mídia
    arquivos/                       arquivos das aplicações e ícones
```

- Toda declaração tem esquema. A que não o satisfaz, ou que quebra uma regra entre arquivos, não é
  servida, e o motivo vai para o log (`docker logs bcast-sim`).
- Um serviço pertence a um só canal e tem pelo menos um fluxo; uma MPD junta os fluxos do serviço.
- As declarações podem citar as bases `${LIVE_BASE_URL}`, `${SERVICES_BASE_URL}` e
  `${SIGNALING_BASE_URL}`, que o compose define.
- Um arquivo do carrossel com `contentType` `multipart/related` é um pacote de entrada: a pasta de
  mesmo nome em `arquivos/` vira o pacote.

Um serviço novo é uma pasta nova em `servicos/` e o `serviceId` na lista `services` de um canal.

## Os serviços de exemplo

Todos no canal 10:

| Serviço | Entrega | Aplicação |
|---|---|---|
| 1001 | `Broadband`: o fluxo vem direto do `bcast-sim` | `AUTOSTART` por `bbandEntryPointUrl`, servida pela comporta na origem `bb-<h>` |
| 1002 | `Broadcast`: o fluxo e a aplicação passam pelo carrossel | `AUTOSTART` num pacote de entrada (`app.pkg`), na origem `ctx-<h>`; `aviso.txt` vence antes da passagem seguinte |
| 1003 | `Broadcast` | `STORED_AUTOSTART`: lançada quando o Application Context Cache a tem completa, e servida dele quando o carrossel não a oferece |

## O vídeo

Cada fluxo é um vídeo pré-gravado, repetido em laço como se fosse ao vivo. Toda resposta é função da
declaração do fluxo e do relógio: a janela ao vivo avança sozinha, sem estado guardado. O mesmo fluxo
sai em HLS (fMP4) e em DASH, com a mesma linha de tempo.

Os segmentos dos exemplos estão no repositório. Para gerar outros, a ferramenta de preparação recorta
um arquivo de vídeo em segmentos fMP4 de duração exata, um fluxo por componente, e escreve as
declarações; precisa do `ffmpeg` e do `ffprobe`:

```sh
cd bcast-sim
npm run prepare-content -- --source <arquivo> --services-dir example/servicos --service-id <id> \
    --video-stream-id <id>-video --audio-stream-id <id>-audio
```

`scripts/make-example.sh` refaz os fluxos sintéticos dos exemplos: barras de cor com o número do serviço
e um contador de quadros, e um bipe a cada segundo.

Os eventos de fluxo (`video/event`, repassados à aplicação como `stream_event`) não têm publicador: o
`bcast-sim` ainda não os gera.
