---
title: tv3ws
description: O componente tv3ws, os TV 3.0 WebServices do testbed - o que implementa, como recebe as chamadas, o que troca com o resto do testbed e o que ele define onde a norma deixa em aberto.
---

O `tv3ws` implementa as APIs dos TV 3.0 WebServices (ABNT NBR 25608, Anexo C), menos duas, que a
[borda](../borda-credenciais/) responde sozinha: o contexto de vínculo do bind-token (C.6.8) e a
descrição das APIs (C.6.7.8 e C.6.7.9). Quais APIs estão implementadas está no mapa de
[Escopo, limites e decisões](../escopo/#o-escopo-no-mapa); como chamá-las, em
[Chamar as APIs de outro aparelho](../apis-de-outro-aparelho/). A lista de rotas, com o que cada uma
exige, está na documentação que a borda gera (`docker port edgegateway 8085`).

## Como recebe as chamadas

- **Só pela borda.** As portas das APIs (44652 em HTTP e 44653 em HTTPS) existem só na rede do Docker.
  A chamada chega com a credencial e a versão já conferidas, e a borda informa a versão, a classe e o
  `clientid` do cliente nos cabeçalhos `X-TV30-*` ([Borda e credenciais](../borda-credenciais/#repasse-ao-serviço)).
- **Emite, mas não confere, a credencial.** O access token sai do `/tv3/authorize` e do `/tv3/token`;
  quem o confere nas demais chamadas é a borda.
- **WebSockets por fora da borda.** Os dos dispositivos remotos ficam na faixa 45000 a 45199, publicada
  no host, e o cliente os abre no endereço que a API devolve.
- **`/manifest`.** Responde à descoberta SSDP com as duas URLs base, montadas com o host pelo qual o
  cliente chegou.

## O que troca com o resto do testbed

| Canal | Assina ou lê | Publica ou grava |
|---|---|---|
| mensageria | o serviço e o usuário correntes, os serviços anunciados, o estado e o diretório da aplicação de emissora, o cliente bloqueado | os pedidos de autorização, de pareamento e o aviso de atributos, que a TV mostra; o usuário corrente, quando uma aplicação o troca; os dispositivos remotos registrados |
| armazenamento | os perfis e a visibilidade de cada um | atributos da emissora, clientes autorizados e bloqueados, sessão (serviço e usuário correntes) e dispositivos remotos registrados |

Os tópicos estão em [Mensageria (MQTT)](../mensageria/), e as famílias de chave, em
[Modelo de dados Redis](../modelo-redis/).

## Versões

A 2.0 é a da norma e vale sem `Accept-Version`. A 100.0 é uma versão de proposta do testbed, alcançada
só quando pedida:

| API | 2.0 | 100.0 |
|---|---|---|
| registro, atualização, cancelamento e listagem de dispositivos remotos (C.6.15) | sim | sim |
| notificações (C.6.2) | não | sim |

O código de cada versão de proposta fica numa pasta própria, `tv3ws/src/v100.0/`, com estado próprio.

## O que o tv3ws define

Valores e escolhas onde a norma deixa a decisão ao receptor ou não trata o caso. As divergências da
norma estão em [Escopo, limites e decisões](../escopo/#onde-o-testbed-difere-da-norma).

| API | O que o testbed define |
|---|---|
| autorização (C.6.1.2) | o pop-up de sim ou não dura 10 s, e o tempo esgotado conta como recusa e bloqueia o cliente; o QR code e o PIN ficam na tela até o fim do pareamento ou por 120 s, no máximo; o 103 também vale enquanto a TV mostra o QR code ou o PIN de outro pedido |
| access token (C.6.1.3) | vale 24 h; enquanto vale, o `/tv3/token` devolve o mesmo token; o refresh token muda a cada chamada |
| serviço corrente (C.6.3.1) | sai sem `serviceName` e sem `serviceId`, que o testbed ainda não recebe |
| arquivos da aplicação (C.6.4.7) | vale qualquer `appId` da BALD do serviço sintonizado, e não só o da aplicação em execução; a árvore são os arquivos do contexto da aplicação na S-TSID, recebidos ou não, com o tamanho declarado nela, mais as partes do pacote de entrada já recebido; o conteúdo vem pela comporta, e o arquivo ainda não recebido responde 305; a listagem sai por ordem de nome; sem serviço sintonizado, 300 |
| atributos da emissora (C.6.14.5) | até 20 MB por perfil; quando algum valor muda, a TV mostra por 5 s "A emissora `<serviço>` atualizou os dados do perfil `<apelido>`", sem pedir confirmação |
| avatar (C.6.14.6) | o `path` é o valor do campo `avatar` do perfil, como a C.6.14.2 o devolve |
| dispositivos remotos (C.6.15) | cada registro abre um WebSocket numa porta da faixa 45000 a 45199; o ponto de entrada do dispositivo remoto sai em `wss://`, com o certificado do receptor |
| efeitos sensoriais (C.6.16) | os renderizadores são os dispositivos remotos da classe `sensory-effect`; o valor das propriedades do comando não é conferido |

Os efeitos sensoriais ainda não seguem o desenho do testbed, que prevê um registro único de
renderizadores, com o renderizador local
([Escopo, limites e decisões](../escopo/#no-escopo-e-ainda-não-implementado)).

## Dispositivo remoto e certificado

Um aparelho não abre `wss://` com certificado autoassinado em que não confia. Confie nele o
`.tv30/tls/cert.pem`, ou suba o `tv3ws` com `TV3WS_WS_TLS=false`, que abre o ponto de entrada em `ws://`.

## Desenvolver e testar

- Rodar o `tv3ws` fora do Docker, com `npm run dev`: [Desenvolvimento com serviço no host](../dev-local/).
- Os testes de unidade (`npm test`, em `tv3ws/`) e as suítes com a stack de pé: [Como testar](../como-testar/).
