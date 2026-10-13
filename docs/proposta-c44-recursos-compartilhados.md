---
title: "Proposta: recursos compartilhados (C.4.4)"
parent: "Decisões pendentes (para o orientador)"
nav_order: 1
---

# Proposta: liberação dos recursos compartilhados (C.4.4)

> **PROPOSTA, não decisão.** Levantamento para o Luís levar ao Joel, sobre o A10 de [Decisões pendentes](decisoes-pendentes.md) ("L7: liberar recursos ao revogar chave (C.4.4)", com a pergunta "prioridade"). O A10 cita só a revogação da chave; a C.4.4 tem três casos, e este documento trata dos três. Feito em 11/10/2026 só pela leitura do código, sem executar nem alterar nada. Nenhuma opção foi implementada. As recomendações são do levantamento; quem decide é o Joel.
>
> Estado lido: aop `6879d30`, bcast `2ae63c7`, infra `502ed71`, tv3ws `7267279` e raiz `fa8c4f1`, com as mudanças das outras frentes de 11/10 (E6, A4, C1, F-3) em andamento e sem commit. As linhas citadas são as do disco no fim deste levantamento; onde aquelas frentes ainda mexerem (o `handler.go` da borda, com a E6, por exemplo), a linha pode mudar. O `infra/edgegateway/routes.json` é citado pela rota (método e caminho), e não pela linha, porque a A4 tira uma rota dele no mesmo dia.
>
> Conferido de novo em 12/10, na auditoria da documentação, contra aop `56bf693`, bcast `b5a343d`, infra `6d8356e`, tv3ws `21a32b8`: as linhas que tinham mudado foram atualizadas (o `handler.go` da borda, com a E6, e o `generate.js` e o `funcoes.lua`, com as mudanças de 12/10), e o que se diz da C.6.15.5 segue a decisão do Luís em 12/10, que a deixou só para o cliente local (seções 3.2 e 8). As opções e a recomendação não mudaram.
>
> Conferido de novo na tarde de 12/10, com as correções do dia ainda sem commit: as rotas 2.1 de `/tv3/remote-device/device/{handle}` também ficaram só para o cliente local (segunda decisão do Luís em 12/10; seções 3.2 e 8), e as linhas que mudaram (`tv3ws/src/api/user/service.ts`, `tv3ws/src/api/client-identification/controller.ts` e `aop/src/modules/bootstrap-application/service.js`, seções 2 e 4) foram atualizadas. As opções e a recomendação não mudaram.
>
> Conferido de novo na madrugada de 13/10, com as decisões do Luís da noite de 12/10 já enviadas (o CORS respondido pelo plugin da borda, a H1 e a H2 nomeadas nos comentários e o 103 com a camada gráfica ocupada): mudaram as linhas do `handler.go` da borda (seções 3.2 e 4), do `generate.js` (seção 5.1) e do `controller.ts` da autorização no tv3ws (seção 4), e foram atualizadas. As opções e a recomendação não mudaram.
>
> Conferido de novo na noite de 12/10, com a G8 e a G9 (decisões do Luís) ainda sem commit: mudaram as linhas do `infra/redis/funcoes.lua` (seção 5.2), que ganhou a regra do avatar, e do `docker-compose.yml` da raiz (seção 3.1), e foram atualizadas; a do compose apontava, desde antes, para a linha do comentário, e não para a da faixa de portas. As opções e a recomendação não mudaram.

## Resumo

- **A norma** manda a implementação liberar os recursos compartilhados quando a app associada fecha. Para o não local e o autônomo, quem libera ao fechar é a própria app, com duas exceções em que a implementação libera sozinha: o usuário remove a autorização (C.4.2.2), ou a emissora revoga a chave do bind-token (C.6.8.4). Liberado, o recurso tem de voltar ao estado de antes do uso.
- **No testbed**, uma app reserva três recursos pelas APIs: o registro de dispositivo remoto (C.6.15.2), o ponto de entrada local para falar com ele (C.6.15.5) e o comando de um renderizador de efeito sensorial (C.6.16.3). **Nenhum dos três gatilhos libera nenhum deles hoje.**
- **Faltam três peças.** Saber quem reservou cada recurso: o tv3ws guarda os recursos, mas não sabe quem chama (D-0510-1). Levar o gatilho até o tv3ws: os gatilhos acontecem no AoP, na borda e no futuro menu de autorizações. E definir o que "liberar" e "estado anterior" querem dizer em cada recurso.
- **Recomendação** (seção 6): a borda repassa ao tv3ws o dono de cada requisição; as funções do Redis que já registram os três fatos (fechar a app, bloquear o cliente, revogar a chave) gravam também um evento, que o tv3ws lê para liberar; e cada recurso ganha uma regra de liberação.
- **Prioridade sugerida:** primeiro o fechamento da app associada, que não depende do `enforce` e é exercitado pelas apps do testbed (webmedia e uff). Depois os outros dois, junto com o `enforce`: em `warn`, a borda não barra o cliente bloqueado, e ele reservaria tudo de novo.

## 1. O que a norma pede

### C.4.4 (p. 211; p. 229 do PDF)

| Cliente | Quando | Quem libera |
|---|---|---|
| Local associado (app de emissora) | quando a app fecha | a implementação: "the implementation shall ensure that when the application is closed, the platform's shared resources are released" |
| Não local e local autônomo | quando a app fecha | a própria app, porque as APIs "do not retain state": "it becomes the responsibility of the respective application, when it closes, to explicitly release any shared resources that have been reserved" |
| Não local e local autônomo | quando o usuário remove a autorização (C.4.2.2) ou a emissora revoga o bind-token (C.6.8.4) | a implementação, automaticamente: "shall automatically release the shared resources used by that application" |

Nos três casos: "The shared resources, once released, shall return to the state they were in prior to their use by the application."

### Os gatilhos nas outras seções

- **C.4.2.2** (p. 208; p. 226 do PDF). O receptor tem um menu com o histórico de autorizações. O usuário remove itens ou apaga tudo, e assim bloqueia um cliente já autorizado. O bloqueado não obtém access token, e o token válido que ele já tem "shall also be blocked". O parágrafo termina com "For more about shared resources used by the blocked client, see C.4.4".
- **C.6.8.4** (Tabela C.49, p. 287; p. 305 do PDF). Apaga a chave que valida o bind-token, "thus effectively denying access to TV 3.0 WebServices APIs to any client using tokens whose validation uses the respective key". Age sobre o serviço DTV selecionado. A nota remete à C.4.4.
- **C.6.2.2** (Tabela C.5, p. 220; p. 238 do PDF), só para notificações. Os registros do não local e do autônomo saem quando o serviço DTV corrente fecha, e os do associado, quando a app termina. É um quarto gatilho, restrito a uma API que o testbed não tem (seção 2).

### O que a norma não diz

Não lista os recursos compartilhados. Diz só que "Several APIs provided by TV 3.0 WebServices offer access to the platform's shared services, or content sent by the broadcaster". Não diz como ligar a app aos recursos dela, em quanto tempo liberar, nem como guardar o estado anterior. Isso fica com a implementação.

{: .nota }
Borda, Redis, MQTT e o tv3ws como processo separado são decisões deste testbed e não aparecem na norma. As opções da seção 5 são desenho do projeto. O que a norma exige é o resultado da tabela acima.

## 2. Quais APIs reservam recurso

Aqui, recurso compartilhado é o que uma API abre para a app e deixa aberto depois da resposta (devolve um *handle* para liberar depois, ou abre um socket), ou o estado da plataforma que a API muda para todos.

**Implementadas no testbed**

| API | Recurso | Liberação prevista na norma |
|---|---|---|
| C.6.15.2, registro de dispositivo remoto (Tabela C.74, p. 335; p. 353 do PDF) | o *handle* e um servidor WebSocket em porta própria ("opens a socket server on a dynamically assigned port") | C.6.15.3 (`DELETE /tv3/remote-device/<handle>`) |
| C.6.15.5, comunicação com dispositivo remoto (Tabela C.78, p. 339; p. 357 do PDF) | um ponto de entrada local (WebSocket) para falar com cada dispositivo listado | nenhuma API na versão 2.0. A 2.1 (proposta do Fórum) tem `DELETE /tv3/remote-device/device/<handle>` |
| C.6.16.3, controle de renderizador de efeito sensorial (Tabela C.81, p. 342; p. 360 do PDF) | o efeito ligado no aparelho (luz, cheiro, vento...) | a ação `stop`. A tabela prevê o 200 "due to resource limitations or conflicts" |

**Não implementadas** (sem rota na borda nem no tv3ws): C.6.2.2 e C.6.2.3, notificações; C.6.3.3, seleção de serviço; C.6.4.3, controle de app de emissora; C.6.4.9 e C.6.4.10, nós e edição de app NCL; C.6.6.3, player de mídia (a nota diz que o `unload` libera "its associated resources"); C.6.6.5 a C.6.6.7, fluxos de mídia, com *handle* e API de liberação; C.6.7.3, filtros de app-alvo; C.6.7.5, execução de app-alvo; C.6.10.2, janela de língua de sinais; C.6.11.2, C.6.11.3 e C.6.11.6, cache; C.6.12.4, parâmetros do player persistente para Xlink; C.6.13.1, sessões de medição de audiência; C.6.17.2 e C.6.17.3, filtros NRT. Quando entrarem, entram no mesmo mecanismo.

**Fora, a confirmar**

| API | Por que fica fora |
|---|---|
| C.6.8.2, registro de chave | a chave tem de sobreviver à app que a registrou. A nota da Tabela C.47 (p. 285; p. 303 do PDF) diz que as apps da casa acessam o serviço "without depending on the Broadcaster Application to run once again" |
| C.6.14.5, atributo de emissora no perfil | é dado persistente por desenho, não reserva |
| C.6.1.2, pop-up e pareamento | têm regra própria na C.4.2.3: a resposta ao pop-up não é guardada se o não local desconecta antes do fim |
| C.6.14.4, troca do usuário corrente (Tabela C.71, p. 331; p. 349 do PDF) | **zona cinzenta.** Muda um estado de todos (`tv3ws/src/api/user/service.ts:111-114` grava `session:current-user` e publica o retido `aop/currentUser`), mas não reserva nada nem tem API de liberação. Entra se o Joel ler "voltar ao estado anterior" como "restaurar o usuário de antes" (pergunta 1) |

## 3. Inventário no testbed

### 3.1 Registro de dispositivo remoto (C.6.15.2)

- **Quem reserva:** o próprio aparelho, um cliente não local. No testbed: o companion do webmedia (`bcast/src/modules/webmedia/companion/companion.ejs:110-115`), o Guaraná (a webmedia procura a classe `guarana`, `bcast/src/modules/webmedia/app.ejs:374`; o cliente fica fora deste repositório) e o aparelho de efeitos sensoriais (classe `sensory-effect`, `tv3ws/src/api/sensory-effect/service.ts:8`; também fora).
- **Na borda:** rota `POST /tv3/remote-device`, `auth: token`, sem `classes`. Não pede bind-token, como a Tabela C.74, que não lista 104 nem 108.
- **No tv3ws:** `src/api/multi-device/controller.ts:7-29` → `src/api/multi-device/service.ts:29-40` (`createWebSocket`; o *handle* é um UUID, linha 31) → `src/modules/remotedevice-manager/entry-point.ts:47-69` (`openEntryPoint`, porta sorteada na faixa `WS_PORT_MIN`–`WS_PORT_MAX`) → `src/modules/remotedevice-manager/manager.ts:70-90` (`addRemoteDevice`).
- **Onde fica o estado:** na memória do tv3ws (`manager.ts:20-21`, os mapas `devices` e `devclasses`, mais o `http.Server` e o `WebSocketServer` de cada aparelho); no espelho do Redis (`manager.ts:32-42`: `remote-devices:index`, `remote-devices:class:{classe}` e `remote-device:{handle}`, com `deviceClass`, `supportedTypes` e `url`), limpo no boot (`manager.ts:24-30`, chamado em `src/server.ts:25`); e no retido MQTT `aop/devices/<classe>`, com a lista de *handles* (`manager.ts:87` e `110`).
- **Dono registrado:** nenhum. Nem a memória nem o espelho guardam quem registrou.
- **Como é liberado hoje:** pelo `DELETE` da C.6.15.3 (`controller.ts:31-42` → `manager.ts:94-112`); quando o WebSocket do aparelho fecha (`src/modules/remotedevice-manager/remote-device.ts:91-97`, escolha do testbed); e no reinício do tv3ws. O `terminate()` fecha o socket, a porta e o ponto de entrada local (`remote-device.ts:475-484`; `entry-point.ts:71-76`).
- **Fora da borda:** o aparelho abre direto `ws://<SERVER_URL>:<porta>` (`remote-device.ts:317-320`), na faixa 45000–45199 que o tv3ws publica no host (`docker-compose.yml:99`; ver [APIs do tv3ws](apis-tv3ws.md)). Depois do registro, a conversa não passa pela borda, e bloquear o cliente na borda não fecha esse socket.

### 3.2 Ponto de entrada local (C.6.15.5 e a 2.1)

- **Quem reserva:** um cliente local. No testbed, a app associada webmedia, que pede o ponto de entrada dos aparelhos `guarana` e `companion` e conecta nele (`bcast/src/modules/webmedia/app.ejs:374-392`, `431-507` e `622`).
- **Na borda:** rota `GET /tv3/remote-device/devices/{classId}` (2.0), `auth: token`, com as `classes` `local-associated` e `local-autonomous` desde 12/10 (decisão do Luís), e por isso só na 44642; e rotas `GET` e `DELETE /tv3/remote-device/device/{handle}` (2.1), `auth: token`, com as mesmas `classes` desde a tarde de 12/10 (segunda decisão do Luís), e por isso também só na 44642 (até ali, sem `classes`, nas duas superfícies). O associado passa sem token, reconhecido pelo `Origin` (`infra/edgegateway/plugin/handler.go:301-311` e `341-343`).
- **No tv3ws:** `src/api/multi-device/controller.ts:46-64` (a listagem 2.0, que já abre o ponto de entrada), `76-91` e `93-106` (as duas rotas da 2.1); `src/api/multi-device/service.ts:51-73` (`ensureLocalEntryPoint`); `remote-device.ts:418-422` (abre) e `432-442` (fecha).
- **Onde fica o estado:** na memória, um ponto de entrada por aparelho (`remote-device.ts:53-54`, `lws` e `lwss`), **compartilhado por todos os clientes locais** que listam o aparelho: `service.ts:53-55` devolve o que já existe. O `lws` guarda só a última conexão (`remote-device.ts:444-455`).
- **Dono registrado:** nenhum.
- **Como é liberado hoje:** pelo `DELETE` da 2.1 (`service.ts:109-115`) e junto com o aparelho (`terminate()`). Na 2.0 não há API de liberação. Quando a app associada fecha, o navegador fecha o WebSocket dela, o tv3ws só registra no log (`remote-device.ts:448-450`) e a porta continua aberta.

### 3.3 Comando de renderizador de efeito sensorial (C.6.16.3)

- **Quem reserva:** as apps associadas uff e webmedia, por `bcast/public/js/sepe.js` (`playLightEffect`, `playScentEffect` e `playWindEffect`, linhas 27-106). Pela norma, também o não local e o autônomo, com bind-token.
- **Na borda:** rota `POST /tv3/sensory-effect-renderers/{rendererId}`, `auth: token+bind`. É o único dos três recursos que exige bind-token.
- **No tv3ws:** `src/api/sensory-effect/controller.ts:37-66` → `src/api/sensory-effect/service.ts:34-61` → `remote-device.ts:334-337` (`controlDevice`), que manda o comando pelo WebSocket do aparelho. O renderizador é um dispositivo remoto da classe `sensory-effect` (`sensory-effect/service.ts:8` e `23`): um recurso (3.3) em cima de outro (3.1), com donos diferentes.
- **Onde fica o estado:** no aparelho. O tv3ws guarda só o `state` de cada tipo de efeito que o aparelho informa (`remote-device.ts:134-164`; começa em `stopped`, linhas 70-77). Não guarda quem mandou o comando, nem as propriedades (cor, intensidade), nem o estado de antes.
- **Dono registrado:** nenhum.
- **Como é liberado hoje:** pela plataforma, nunca. As apps tentam por conta própria ao descarregar a página. A uff manda `stop` só da luz, no `beforeunload` do `window` (`bcast/src/modules/uff/app.ejs:57-60`), embora use também cheiro e vento. A webmedia registra o mesmo ouvinte no `document` (`bcast/src/modules/webmedia/app.ejs:802-805`), mas o `beforeunload` é disparado no `window`, e o ouvinte não é chamado (lido, não medido). Mesmo na uff, o `fetch` sem `keepalive` disparado no descarregamento pode ser interrompido pelo navegador (não medido).

### 3.4 Precedente: a origem da app associada

O AoP já libera, quando a app fecha, um recurso do próprio desenho: a origem em `origins:associated`, gravada no lançamento e apagada no fechamento (`aop/src/core.js:150-158`), pelas funções `tv30_origem_registra` e `tv30_origem_remove`, e apagada inteira no boot do AoP (`core.js:30`, `tv30_origens_limpa`). Não é recurso da C.4.4: é o mecanismo do testbed para reconhecer o associado (P1.3). Mas é o ponto do código onde o fechamento da app já é tratado.

## 4. Os três gatilhos hoje

| Gatilho | Onde acontece no testbed | Quem fica sabendo | O que é liberado |
|---|---|---|---|
| (a) app associada fecha | `setDisplayGraphics` do AoP (`aop/src/core.js:143-163`), ao limpar ou trocar a app: tecla 27 ou 93 (`aop/src/modules/graphic-overlays/index.js:21-31` → `openServiceInfo`, `core.js:373-381`) ou outra app no lugar (`aop/src/modules/bootstrap-application/service.js:109-124`) | o AoP e, pela `tv30_origem_remove`, o Redis. O tv3ws não assina nenhum tópico que diga isso | só a origem (3.4) |
| (b) usuário remove a autorização (C.4.2.2) | não há menu (E5). O único bloqueio é a recusa no pop-up (`tv3ws/src/api/client-identification/controller.ts:226-233` → `BlockClient`, `tv3ws/src/modules/auth-manager/manager.ts:103-106`), quando o cliente ainda não tem recurso. Hoje, só gravando direto no Redis (`FCALL tv30_cliente_bloqueia`) | a borda, a cada requisição: 107 ao `sub` bloqueado (`handler.go:366-372`) e, desde a E6 (Luís, 11/10), também ao `sub` fora de `clients:authorized` e ao token sem `sub` (`handler.go:363-365` e `373-379`), o que cobre a remoção do histórico | nada. O WebSocket do aparelho (3.1) e o do ponto de entrada (3.2) não passam pela borda e continuam funcionando |
| (c) emissora revoga a chave (C.6.8.4) | `bindRemove` da borda (`infra/edgegateway/plugin/bindcontext.go:309-344`), com o `PENDENTE (Joel)` da L7 nas linhas 307-308 | a borda: o bind-token que só a chave apagada validava passa a dar 108 (`handler.go:385-410`) | nada. A borda não guarda qual chave validou qual requisição (`verifyBindToken`, `infra/edgegateway/plugin/jwt.go:242-261`, só devolve erro), nem quais clientes usaram cada chave |

## 5. Opções de desenho

As três peças que faltam são independentes, e cada uma tem as suas opções.

### 5.1 Quem atribui o dono do recurso

O tv3ws guarda os recursos, mas não sabe quem chama. Pela D-0510-1, ele não lê a identidade do cliente: dos cabeçalhos, só lê `Accept-Version`, o `Range` da C.6.4.7 e o `Origin` do `/tv3/authorize`. A borda sabe: o `sub` e a classe do access token, o `Origin` do associado e a chave que validou o bind-token.

| | Opção | A favor | Contra |
|---|---|---|---|
| **1A** | **A borda repassa o dono ao tv3ws** em cabeçalhos próprios, apagando os que vierem do cliente. Nomes de exemplo: `X-TV30-Owner` = `client:<sub>` ou `origin:<Origin>`; `X-TV30-Bind-Key` = um resumo (*hash*) da entrada de `bind-context:{serviceId}` que validou o bind-token, nunca a chave, porque nas chaves HS a chave é o segredo. O tv3ws guarda o dono junto do recurso | o tv3ws continua sem validar credencial, e a D-0510-1 fica; a identidade sai do mesmo lugar que decide o acesso; a borda já calcula tudo isso | muda a consequência registrada na D-0510-1 ("a borda não precisa repassá-la"). O tv3ws passa a confiar num cabeçalho, o que só é seguro enquanto a porta dele não for alcançável sem a borda: no compose, as 44652 e 44653 não são publicadas (`docker-compose.yml:87-96`), mas no dev-host o tv3ws roda no host e escuta em todas as interfaces (`tv3ws/src/server.ts:44`). O `verifyBindToken` tem de dizer qual chave validou, e o `generate.js` tem de repassar os cabeçalhos novos (`headersOf`, `infra/edgegateway/generate.js:248-252`) |
| **1B** | **O tv3ws lê sozinho:** decodifica o `Authorization`, que já recebe, com o `JWT_SECRET`, que já tem, e confere o bind-token contra `bind-context:{serviceId}` | nada muda na borda | desfaz em parte duas decisões do Joel: a D-0510-1 (o tv3ws volta a ler credencial) e o leitor único de chave da D-0510-2. Listada para completar; não recomendada |
| **1C** | **A borda guarda o registro das reservas** | o tv3ws não muda | a borda teria de entender o corpo da resposta de cada API para saber o *handle*, e quem fecha o socket continua sendo o tv3ws. Descartada |

Em `warn`, a borda só repassaria o dono quando a credencial é válida. Reserva feita sem credencial, como a do companion hoje (`companion.ejs:110-115`, sem `Authorization`), fica sem dono e só sai pelos caminhos de hoje.

### 5.2 Como o gatilho chega ao tv3ws

Os três fatos já passam por funções do Redis (P4): `tv30_origem_remove` e `tv30_origens_limpa` no (a), `tv30_cliente_bloqueia` no (b), e mais a futura remoção do histórico (E5), e `tv30_bind_remove` no (c) (`infra/redis/funcoes.lua:711-721`, `751-762` e `777-784`).

| | Opção | A favor | Contra |
|---|---|---|---|
| **2A** | **As funções gravam o evento** junto com o fato, numa família nova do tipo *stream* (`XADD`; nome de exemplo `events:release`), que o tv3ws lê com `XREAD` a partir do último id lido | atômico com a mudança de estado; não perde evento numa queda da conexão do tv3ws com o Redis; nenhum produtor novo: AoP e borda continuam chamando as mesmas funções, e o AoP não muda | família nova no esquema (`infra/redis/esquema.json`), com teto de tamanho (`MAXLEN`), e o Redis passa a carregar também eventos. Variante mais simples, `PUBLISH` no lugar do *stream*: perde o evento durante uma queda de conexão |
| **2B** | **Mensageria MQTT:** o AoP publica o fechamento da app, quem bloquear publica o bloqueio, e a borda publica a revogação | segue o padrão de comunicação entre AoP e tv3ws | a borda não tem cliente MQTT (dependência nova no plugin Go); são três produtores, com três formatos; sem retenção, o evento se perde com o tv3ws desconectado. O tópico que já existe, `aop/display/layers/graphics` (`core.js:161`), é da camada de tela e só diz qual origem fechou se o tv3ws interpretar a URL |
| **2C** | **Só reconciliação:** o tv3ws confere de tempos em tempos cada recurso contra o Redis (o dono está em `clients:authorized`? a origem em `origins:associated`? a chave em `bind-context:{serviceId}`?) e libera o que perdeu o dono | não perde evento; não muda as funções nem a borda | tem o atraso do período, e não vê fechamento seguido de relançamento: com o `appId` fixo (Luís, 11/10), a app relançada volta com a mesma origem, e a reconciliação não distingue isso de "nunca fechou". O mesmo vale para bloquear e desbloquear em seguida |
| **2D** | **Chamada HTTP interna** do AoP e da borda a uma rota do tv3ws | síncrona | API interna fora da norma; acopla a borda ao tv3ws por fora do roteador do KrakenD; a chamada se perde com o tv3ws fora do ar |

### 5.3 O que "liberar" faz em cada recurso

| Recurso | Liberar | Estado anterior (C.4.4) | Observação |
|---|---|---|---|
| Registro de dispositivo remoto (3.1) | o mesmo que o `DELETE`: fecha o socket e a porta, tira do espelho e atualiza `aop/devices/<classe>` (`manager.ts:94-112`) | "não registrado": coincide | o companion se registra de novo 3 s depois que o socket cai (`companion.ejs:128-131`); com `enforce`, o bloqueado leva 107 |
| Ponto de entrada local (3.2) | hoje é um por aparelho, para todos os clientes locais. **(i)** guardar o conjunto de donos e fechar quando ele esvazia; **(ii)** um ponto de entrada por dono; **(iii)** fechar ao liberar qualquer dono | "sem ponto de entrada", para aquele dono | a (iii) derruba outro cliente local. A (ii) muda a resposta da 2.0, em que cada cliente veria uma URL diferente, e o repasse de mensagens, que só fala com o último `lws` (`remote-device.ts:457-470`). A norma é ambígua: a nota depois da Tabela C.78 diz "For each client, a local entry point enables the client application to exchange metadata messages with the remote device", o que pode ser lido como um ponto por cliente local, a (ii). Recomendada a (i), salvo se o Joel ler a nota assim (pergunta 1) |
| Comando de efeito sensorial (3.3) | **(i)** `stop` em cada tipo de efeito cujo último comando veio do dono que sai; **(ii)** guardar o estado de cada tipo antes do primeiro comando do dono e restaurá-lo | a (i) acerta quando o efeito estava parado antes, o caso comum. A (ii) é a leitura literal, mas o tv3ws não tem as propriedades (cor, intensidade) de quem usava antes, e o aparelho não as informa | "o último comando veio do dono" evita desligar o efeito que outra app ligou depois. Recomendada a (i), com o estado de antes registrado no log e a restauração completa como `PENDENTE (Joel)` |

### 5.4 Alcance da revogação (C.6.8.4)

O bind-token é da emissora, que o distribui às apps (C.4.1.2, p. 204; p. 222 do PDF), e a C.4.1.3 (p. 205; p. 223 do PDF) não pede campo que identifique a app. Dos três recursos, só o comando de efeito sensorial exige bind-token. O registro de aparelho e o ponto de entrada não exigem (Tabelas C.74 e C.78).

| | Opção | A favor | Contra |
|---|---|---|---|
| **4A** | **Por requisição:** libera só o que foi reservado com bind-token validado pela chave revogada | basta o `X-TV30-Bind-Key` da 1A; a borda não guarda nada | hoje libera só os comandos de efeito sensorial. É uma leitura estreita de "the shared resources used by that application" |
| **4B** | **Por aplicação:** libera tudo de toda app (`sub`) que apresentou bind-token validado por aquela chave, no serviço da chave | é a leitura literal da C.4.4 e da C.6.8.4 ("denying access [...] to any client using tokens whose validation uses the respective key") | a borda tem de guardar quem usou cada chave, inclusive no `GET /tv3/bind-context` (C.6.8.3), que ela mesma responde e o tv3ws nunca vê. É uma família nova, gravada pela borda por função (P4), com uma escrita a cada bind-token validado |

### 5.5 Modo `warn`

O gatilho (a) libera sempre, porque não é decisão de credencial. O (b) e o (c) seguem o `AUTH_ENFORCE`, como a borda: em `warn`, o tv3ws só registra no log o que liberaria. Liberar de verdade em `warn` não adiantaria, porque o cliente bloqueado continua passando pela borda, e o companion, por exemplo, reservaria de novo em 3 s.

## 6. Recomendação (proposta)

1. **Dono: 1A.** A borda repassa `client:<sub>` (não local e autônomo com access token válido) ou `origin:<Origin>` (associado reconhecido pelo `Origin`) e, nas rotas `token+bind`, o resumo da entrada da chave que validou o bind-token. O tv3ws guarda o dono na memória, junto do recurso, e no espelho `remote-device:{handle}`.
2. **Gatilho: 2A, com *stream*.** `tv30_origem_remove`, `tv30_origens_limpa`, `tv30_cliente_bloqueia` (e a futura remoção do histórico) e `tv30_bind_remove` gravam o evento, e o tv3ws lê e libera. No boot, o tv3ws começa do fim do *stream*, porque os recursos dele não sobrevivem ao reinício.
3. **Liberação:** o registro de aparelho como o `DELETE`; o ponto de entrada com o conjunto de donos; o efeito sensorial com `stop` nos tipos de efeito cujo último comando veio do dono.
4. **Revogação: 4B**, a leitura literal. Se o custo da família nova pesar, a 4A primeiro, que é parte da 4B.
5. **`warn`:** como em 5.5.
6. **Ordem:** o (a) primeiro, sem esperar o `enforce`. Ele só precisa da 1A para o associado, do evento da `tv30_origem_remove` e do conjunto de donos do ponto de entrada. Depois, o (c) e o (b), junto com o `enforce`. O (b) só tem quem o dispare quando houver o menu da E5; até lá, testa-se com `FCALL tv30_cliente_bloqueia`.

**O que mudaria em cada componente** (estimativa a partir da leitura; nenhum código foi escrito):
- **borda:** `handler.go`, `jwt.go`, `generate.js` e os testes Go;
- **Redis:** `funcoes.lua`, `esquema.json` e os testes de `infra/redis/test/`; na 4B, também a família de uso das chaves;
- **tv3ws:** o leitor do *stream*, o dono e o conjunto de donos em `src/modules/remotedevice-manager/`, o último comando por tipo de efeito em `src/api/sensory-effect/service.ts` e os testes;
- **AoP:** nada, porque já chama `tv30_origem_remove` ao fechar a app e `tv30_origens_limpa` no boot;
- **bcast:** nada obrigatório.

**Como verificar**, no estilo do `scripts/test-auth.sh`:
- **(a):** com o `Origin` de uma app associada, pedir a listagem 2.0 de uma classe, ver a porta do ponto de entrada abrir, chamar `tv30_origem_remove` com a origem e ver a porta recusar conexão;
- **(b):** registrar um aparelho com o token do cliente X, chamar `tv30_cliente_bloqueia` com X e ver a porta fechar, o espelho sair e `aop/devices/<classe>` mudar;
- **(c):** registrar uma chave, mandar `start` a um renderizador falso (um cliente WebSocket registrado como `sensory-effect`) com bind-token dessa chave, revogar a chave e ver o renderizador receber `stop`;
- nos três, derrubar a conexão do tv3ws com o Redis antes do gatilho e conferir que o evento é lido na volta.

## 7. Perguntas para o Joel

1. A lista da seção 2 está certa? Em particular, a troca do usuário corrente (C.6.14.4) é recurso compartilhado? E o ponto de entrada local da C.6.15.5 é um por dispositivo, como no testbed, ou um por cliente local (5.3)?
2. O dono atribuído pela borda (1A), aceitando que ela passe a repassar a identidade ao tv3ws?
3. O evento gravado pelas funções do Redis (2A), num *stream*?
4. A revogação por aplicação (4B) ou por requisição (4A)?
5. No efeito sensorial, o `stop` basta como "estado anterior", ou é preciso restaurar o efeito de antes?
6. O fechamento do serviço DTV (C.6.2.2) também deve liberar desde já, ou só quando houver notificações?
7. Em `warn`, o (b) e o (c) só registram no log?
8. A prioridade do A10: o (a) antes do `enforce`, e o (b) e o (c) junto com ele?

## 8. Achados laterais (só registro; fora da C.4.4)

- **C.6.15.5 sem restrição de classe na borda** (achado de 11/10; decidido pelo Luís em 12/10). A Tabela C.78 prevê "107: If invoked from a non-local client", mas, em 11/10, a rota `GET /tv3/remote-device/devices/{classId}` não tinha `classes`, e rota sem `classes` admite todas (`infra/edgegateway/plugin/routes.go:85-98`) e entra também na superfície externa (P1.9): um não local com access token abria ponto de entrada local. Desde 12/10, a rota tem as `classes` `local-associated` e `local-autonomous`: saiu da 44643, onde dá 100, e, na 44642, o não local identificado pelo access token recebe 106 (em `warn`, só o aviso `X-TV30-Auth-Warn`). O código exato, 107 da Tabela C.78 ou 106 da C.4.1.8, ficou com o Joel (F-1 de [Decisões pendentes](decisoes-pendentes.md)). As rotas da 2.1, `GET` e `DELETE /tv3/remote-device/device/{handle}`, ficaram sem `classes` e nas duas superfícies até a tarde de 12/10: com `Accept-Version: 2.1`, um não local com access token e um *handle* conhecido, como o do próprio registro, abria o ponto de entrada local daquele aparelho (lido, não medido). Desde a segunda decisão do Luís em 12/10, elas têm as mesmas `classes` da C.6.15.5: 100 na 44643 e 106 ao não local na 44642. Se o código delas entra na F-1 também está com o Joel.
- **Repasse preso depois que o cliente local sai.** Quando o cliente local desconecta, o `bridge` continua `true` (`remote-device.ts:444-455`). As mensagens do aparelho vão para um socket fechado, que o `ws` 8.18.1 descarta sem erro, em vez de voltarem ao tratamento do próprio tv3ws (transições e capacidades). Só o `DELETE` da 2.1 ou o `terminate()` desfazem isso (lido, não medido).
- **Pontos de entrada sem credencial.** As duas portas WebSocket aceitam qualquer conexão, e a nova toma o lugar da anterior (`remote-device.ts:87-89` e `444-446`). Quem varrer a faixa 45000–45199 conecta (lido, não medido). A norma não fala de credencial nesse socket.
- **`turnOffEffects` sem chamador** (`bcast/public/js/sepe.js:108-115`), e com `findSepe()` sem `await`.
- **Registro que nunca conecta não expira.** A porta fica aberta até o `DELETE` ou o reinício do tv3ws. A norma não pede prazo. Seria escolha da implementação, e não é proposta aqui.
