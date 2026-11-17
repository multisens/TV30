---
title: O que o testbed simula
description: O que no testbed é implementação da norma e o que faz o papel da emissora, da TV e da casa.
---

O testbed implementa a plataforma do receptor, a TV 3.0 AoP, com o comportamento que a norma
especifica. Tudo o que fica em volta dela — a emissora, o aparelho de TV, o controle remoto e a casa —
é simulado ou trocado por algo que se tem num computador.

## Do mundo real para o testbed

| No mundo real | No testbed |
|---|---|
| Ligar o receptor | `./tv30 up`, que sobe os containers |
| O software do fabricante, que aciona a plataforma | Não existe: abrir a página da TV entrega o controle à plataforma |
| A tela da TV | Uma página no navegador, em `http://localhost:8080` |
| O controle remoto | O teclado: setas, Enter e Esc |
| A emissora, transmitindo pelo ar | O container `bcast`, com quatro serviços de exemplo: `webmedia`, `uff`, `eduplay` e `users-test` |
| O programa ao vivo | Um vídeo pré-gravado, repetido em loop e servido como transmissão ao vivo em HLS. Trechos do vídeo disparam eventos que chegam à aplicação da emissora |
| A sinalização dos serviços, na camada de transporte | Mensagens na mensageria interna: a lista de serviços com o manifesto de cada Bootstrap Application (BAMT) e, por serviço, o programa no ar (ESG) e as aplicações (BALD), em JSON |
| Os arquivos das aplicações, entregues pelo ar | Servidos pela emissora por HTTP, como se viessem pela internet |
| A memória não volátil do receptor | O Redis, onde ficam os perfis, as credenciais e a sessão |
| A rede da casa | A sua rede local. A TV se anuncia de verdade, por SSDP, a partir do seu computador |
| O celular com um aplicativo da emissora | O seu celular, ou os scripts de teste em `scripts/` |
| Um dispositivo remoto, como um renderizador de efeitos sensoriais ou óculos de realidade virtual | Software próprio do aparelho, que não faz parte do testbed. O testbed implementa o lado do receptor |

:::note[Planejado]
Hoje a emissora publica a sinalização direto na mensageria da plataforma. Está planejado o caminho da
norma: a emissora serve a sinalização — SLT, BAMT, USBD, S-TSID, MPD, BALD e PRRD — e a plataforma a
busca e a decodifica. Com ele vêm o vídeo em DASH e a entrega de arquivos pelo ar, com carrossel.
:::

## O que é de verdade

As APIs dos WebServices respondem nas portas que a norma fixa, em HTTP e HTTPS, com as rotas, as
credenciais e os códigos de erro da norma. Um cliente escrito contra a norma deve funcionar contra o
testbed sem adaptação: é por isso que ele serve para testar aplicações e aparelhos.

O mesmo vale para o que o espectador vê e faz: perfis, catálogo, Bootstrap Application, aplicação da
emissora, pedido de autorização e pareamento seguem o comportamento da norma, dentro do que está
implementado. O que falta e onde o testbed difere da norma estão em
[Escopo, limites e decisões](../escopo/).

## O que o testbed não é

- **Não é um receptor de produção nem um receptor certificado.** Serve para estudar, testar e
  experimentar.
- **Não se defende de quem tenta enganá-lo.** Um cliente que mente sobre o que é consegue passar. O
  certificado HTTPS é gerado pelo próprio testbed, na primeira subida.
- **Não se recupera sozinho de cada falha.** Quando uma peça cai, o container dela para por inteiro e
  sobe de novo. Se algo ficar estranho, `./tv30 down` e `./tv30 up` resolvem.
