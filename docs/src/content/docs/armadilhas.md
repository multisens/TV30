---
title: Armadilhas
description: O que parece certo no testbed e não é, dito antes de causar problema.
---

O que parece certo e não é. Cada item diz o que acontece e leva ao lugar onde está o detalhe. Se o
problema já apareceu, comece por [Solução de problemas](../troubleshooting/).

## Subir

- **Sem o `.env`, o receptor não sobe.** A casca, o tv3ws, o bcast e o broker só sobem com os perfis
  do compose, que o `.env.example` liga. Sem ele, só o Redis e a borda ficam de pé
  ([Instalação](../instalacao/)).
- **`docker compose up -d` não anuncia a TV na rede.** Quem sobe o anunciante é o `./tv30 up`
  ([Descoberta na rede](../instalacao/#descoberta-na-rede)).
- **A imagem publicada pode estar atrás do seu clone.** Sem `--build`, você roda e testa a `latest` do
  Docker Hub, e não o código que acabou de mudar
  ([Imagens publicadas ou código do clone](../instalacao/#imagens-publicadas-ou-código-do-clone)).

## Rede

- **A TV aberta de outra máquina não carrega as aplicações de emissora.** Elas abrem em
  `*.apps.localhost`, que só resolve na máquina de quem abre a página. Use `APPS_DOMAIN`
  ([Instalação](../instalacao/#variáveis-do-env)).
- **O tv3ws não é alcançável direto.** As APIs entram só pela borda, nas portas 44642 e 44643
  ([Borda e credenciais](../borda-credenciais/)).

## Desenvolver

- **Um módulo no host sem parar o container dele cai do broker.** Os dois usam o mesmo `clientId`, e o
  broker derruba a conexão anterior a cada nova
  ([Desenvolvimento com serviço no host](../dev-local/)).
- **O `npm run dev` fica de pé quando o módulo morre.** O `nodemon` espera uma mudança de arquivo. Leia
  o terminal antes de concluir que o módulo está no ar
  ([Variáveis que cada módulo exige](../dev-local/#variáveis-que-cada-módulo-exige)).

## Estado

- **Tópico sem esquema passa sem conferência.** O broker só recusa a mensagem fora do esquema de um
  tópico que tem esquema declarado ([Mensageria (MQTT)](../mensageria/#esquema-das-mensagens)).
- **Gravar no Redis por fora das funções funciona, mas aparece na auditoria.** Nada impede a escrita
  direta; quem confere o formato são as funções do esquema
  ([Modelo de dados Redis](../modelo-redis/#o-esquema-na-escrita)).
- **O `avatar` do perfil é o nome de um arquivo, e não o desenho**
  ([aop-shell](../aop-shell/#perfis)).
- **`user:{id}:consent` é a visibilidade do perfil por serviço**, e não o consentimento do Privacy
  Manager (8.8), que o testbed não implementa ([Modelo de dados Redis](../modelo-redis/)).

## APIs

- **Sem `Accept-Version`, vale a 2.0.** A 100.0, versão de proposta do testbed, só responde quando
  pedida ([tv3ws](../tv3ws/#versões)).
- **O `serviceContextId` das URLs é o `globalServiceId` do BAM do serviço**
  ([Glossário](../glossario/)).

## Aplicações de emissora

- **O Esc chega à aplicação como `BrowserBack`.** Sem `preventDefault`, a casca encerra a
  aplicação ([aop-shell](../aop-shell/#aplicações-de-emissora)).
- **A aplicação de banda larga não roda na origem do servidor dela.** Ela abre em
  `bb-<hash>.<APPS_DOMAIN>`: URL relativa vai à comporta, que a repassa ao servidor, e URL absoluta
  para o próprio servidor é pedido entre origens, que pede CORS (B.6.2). A comporta repassa só
  GET e HEAD ([aop-shell](../aop-shell/#aplicações-de-emissora)).
- **Com o QR code, o PIN ou um aviso na tela, a tecla segue para a aplicação.** Só o pop-up de sim
  ou não toma as teclas ([aop-shell](../aop-shell/#pop-ups)).
- **Aplicações NCL não são lançadas.** A casca lança só as `TV30-Ginga-HTML5`
  ([aop-shell](../aop-shell/#aplicações-de-emissora)).
