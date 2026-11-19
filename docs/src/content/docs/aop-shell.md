---
title: aop-shell
description: O componente aop-shell, a casca da plataforma - o que implementa, como recebe as chamadas, o que troca com o resto do testbed e o que ele define onde a norma deixa em aberto.
---

O `aop-shell` é a casca da plataforma: a página da TV, com as camadas de exibição e os avisos, e as telas
que a plataforma mostra nelas, que são o seletor e o gestor de perfis, o catálogo de aplicações e a
aplicação de abertura de cada serviço. Ele também lê a LLS e lança a aplicação da emissora. As
camadas e o caminho do espectador estão em [A AoP em 5 minutos](../aop-em-5-minutos/); quais
peças da norma estão implementadas, no mapa de [Escopo, limites e decisões](../escopo/#o-escopo-no-mapa).

## Como recebe as chamadas

- **A página da TV**, em `http://localhost:8080` (`AOP_PUBLIC_PORT`). É o navegador quem a abre; a
  casca não tem API da norma, e a borda não passa por ela.
- **O host de cada aplicação de emissora**, `http://<app>.apps.localhost:8080`. A casca repassa o
  pedido ao bcast, ao endereço que a BALD declara, e assim cada aplicação tem origem própria.
- **`/mqtt`.** A página da TV fala MQTT por aqui, e a casca repassa ao WebSocket do broker.
- **`/videoStreamProxy`.** O vídeo HLS ou DASH do serviço, repassado ao bcast.

## O que troca com o resto do testbed

| Canal | Assina ou lê | Publica ou grava |
|---|---|---|
| mensageria | o usuário e o serviço correntes; a BAMT de cada fluxo; o ESG e a BALD do serviço selecionado | a tela de cada camada, o vídeo e o tamanho dele; o usuário e o serviço correntes; o perfil removido; os serviços anunciados; o início e o fim de cada aplicação de emissora |
| armazenamento | os perfis; o serviço corrente, na criação de perfil | os perfis (criação, remoção e último acesso), as origens das aplicações em execução e os serviços anunciados |

A página da TV assina as camadas e os pop-ups e responde ao pop-up de sim ou não. Os tópicos estão em
[Mensageria (MQTT)](../mensageria/), e as famílias de chave, em
[Modelo de dados Redis](../modelo-redis/).

## O que a casca define

Valores e escolhas onde a norma deixa a decisão ao receptor ou não trata o caso.

### Perfis

| Caso | O que a casca faz |
|---|---|
| Nenhum perfil | Cria o perfil padrão `Viewer 1`, com os valores padrão da Tabela 7, sem avatar e sem visibilidade para nenhum serviço |
| Partida | Sem perfil corrente, o primeiro perfil passa a ser o corrente |
| Criação | O formulário confere os campos da Tabela 7. O novo perfil fica visível ao serviço corrente, se houver um, além dos que o formulário marca |
| Sexto perfil | Recusado, com a mensagem do limite; nenhum perfil é despejado (10.3.3) |
| Remoção | Pelo seletor, com confirmação. O perfil único não pode ser removido. A remoção apaga o perfil, a visibilidade e os atributos de emissora, publica o id em `aop/removedUser` e volta ao seletor |
| Remoção do perfil corrente | `aop/currentUser` fica vazio até a escolha no seletor |
| Último acesso | Gravado a cada troca de usuário corrente, também quando outro componente publica `aop/currentUser` (C.6.14.4) |

O avatar do perfil criado é um arquivo SVG em `user-files/thumbs`, e o campo `avatar` guarda o nome
dele.

### Pop-ups

Quem pede o pop-up e o prazo dele é quem o publica, o [tv3ws](../tv3ws/#o-que-o-tv3ws-define). A
casca define como eles se revezam na tela:

- Há um pop-up por vez. O novo substitui o que está na tela.
- O aviso de atributos da emissora (C.6.14.5) não substitui outro pop-up: espera numa fila de até
  três, e o quarto é descartado. Sem prazo na mensagem, fica 5 s.
- Só o pop-up de sim ou não toma as teclas. O tempo esgotado conta como "Não".
- O QR code e o PIN fecham com `{"close":true}` no mesmo tópico, ou no fim do prazo.
- Mensagem que não é um objeto JSON com `value` é ignorada, com um aviso no console da página.

### Aplicações de emissora

- **Lançamento:** quem decide é o gerente de ciclo de vida, no `aop-cc`, pelo `controlCode` da BALD
  do serviço sintonizado, sem esperar a tela cheia. A casca assina
  `aop/application-lifecycle-manager/graphics-application`: com uma aplicação, fecha a aplicação de
  abertura, põe o vídeo em tela cheia e carrega a aplicação na camada de gráficos; vazio, a
  aplicação de abertura volta em modo de informação. A tela cheia da aplicação de abertura só
  esconde as informações.
- **Origem própria:** o gerente grava a origem em `origins:associated` e a aplicação em
  `session:current-app` ao lançar, e as apaga ao encerrar. Na partida do `aop-cc`, limpa as duas.
- **Troca:** o fim da aplicação que sai é publicado antes do início da que entra.
- **Teclas:** a origem é outra, e a casca entrega a tecla, o `timeupdate` e o `stream_event` por
  `postMessage`. A aplicação só os recebe se incluir `bcast/public/js/aop-bridge.js`, que os
  dispara no documento dela.
- **Esc e Menu**, com uma aplicação de emissora, pedem ao gerente que a encerre
  (`aop/application-lifecycle-manager/end-request`); a aplicação de abertura volta em modo de
  informação, e a aplicação não recebe as teclas
  ([diverge da norma](../escopo/#onde-o-testbed-difere-da-norma)). PageUp e PageDown, a troca de canal, só vão para o log.
- **De outra máquina:** `*.apps.localhost` só resolve na máquina de quem abre a página. Para abrir a
  TV de outra máquina, use `APPS_DOMAIN` ([Instalação](../instalacao/#variáveis-do-env)).

## Desenvolver e testar

- Rodar a casca fora do Docker, com `npm run dev`:
  [Desenvolvimento com serviço no host](../dev-local/#casca-aop-no-host).
- Os testes de unidade (`npm test`, em `aop-shell/`): [Como testar](../como-testar/).
