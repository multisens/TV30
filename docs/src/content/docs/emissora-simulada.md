---
title: Emissora simulada
description: O bcast, a emissora simulada do testbed - o que ele publica e serve, os serviços de exemplo e o vídeo.
---

O bcast faz o papel da emissora, fora do receptor. Ele anuncia os serviços de exemplo, publica a
sinalização de cada um e serve as aplicações de emissora e o vídeo. O que isso representa no mundo
real está em [O que o testbed simula](../o-que-simula/).

## O que ele publica e serve

| O quê | Onde |
|---|---|
| a BAMT, com um BAM por serviço | tópico `tlm/lls/<bsid>/bamt`, retido; o `<bsid>` é `tv30-default` |
| a ESG e a BALD de cada serviço | tópicos `tlm/sls/<id do serviço>/esg` e `tlm/sls/<id do serviço>/bald`, retidos |
| os eventos do vídeo | tópico `video/event` |
| as aplicações e os arquivos estáticos | HTTP na 8081, nas rotas de cada serviço e em `bcast/public/` |
| o vídeo | HTTP na 8081, em `/live/hls/<playlist>.m3u8` |

Ao parar, o bcast publica mensagem vazia nos tópicos retidos, e a casca deixa de mostrar os serviços.

Hoje o bcast publica a sinalização direto na mensageria do receptor. Está planejado o caminho da norma,
em que a emissora serve a sinalização e o receptor vai buscá-la
([O que o testbed simula](../o-que-simula/)).

## Os serviços de exemplo

Cada serviço é um módulo do bcast, e não um container:

| Módulo | O que é |
|---|---|
| `users-test`, `uff` | uma aplicação (`app.ejs`) |
| `webmedia` | uma aplicação e as telas do aparelho companheiro (`companion/`) |
| `eduplay` | um quiz, com a tela da TV e a do jogador |
| `live_stream` | o vídeo: os segmentos HLS e a playlist ao vivo simulada |

```
bcast/src/modules/<nome>/
├── index.ts        # a interface de serviço: BAM, sinalização e as rotas
└── *.ejs           # as telas da aplicação
```

O módulo implementa a interface de serviço do bcast (`bcast/src/types.ts`):

| Função | O que faz |
|---|---|
| `init` | recebe o endereço do bcast, de onde o módulo monta as URLs da aplicação |
| `bam` | devolve o BAM do serviço, que entra na BAMT |
| `sendSLS` | publica a ESG e a BALD do serviço, com o cliente MQTT que o bcast lhe passa |
| `dispose` | apaga a ESG e a BALD retidas |
| `router` | opcional: as rotas HTTP do serviço, em `/<módulo>` |

Os módulos são registrados em `bcast/src/index.ts`. Os ids dos serviços vêm do ambiente
(`WEBMEDIA_SID`, `UFF_SID`, `EDUPLAY_SID`, `USERS_TEST_SID`), com padrão `urn:tv30:service:<nome>`.

## O vídeo

O `live_stream` repete em laço um fluxo pré-gravado, como se fosse ao vivo, e publica em `video/event`
os eventos marcados em cada segmento. Os segmentos não vêm no repositório: são preparados com FFmpeg
(`bcast/scripts/ffmpeg-hls.sh`) e ficam em `bcast/public/hls/`.
