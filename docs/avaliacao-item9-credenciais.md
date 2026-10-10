---
title: "Avaliação: item 9 — validação de credenciais (P2)"
nav_order: 12
---

# Item 9 (P2) — validação de credenciais: avaliação antes de implementar

## Decisões da reunião de 05/10 (Joel)

Na reunião de 05/10, o Joel levou a decisão D1 de 28/09 até o fim e resolveu o A3. Onde o texto mais abaixo diz outra coisa, vale esta seção. Os rótulos são os do código; o que foi feito, com os arquivos, está em [Decisões pendentes](decisoes-pendentes.md), seção *Decididos na reunião de 05/10 com o Joel*. As quatro são decisões de desenho do testbed: a norma não diz qual processo valida a credencial nem qual processo responde cada API.

| | Decisão | O que mudou no código |
|---|---|---|
| **D-0510-1** | **O tv3ws fica "anônimo"**: só recebe e responde; toda a validação de credencial é da borda | Saíram do tv3ws o `src/middleware/authorization.ts` (107) e o `validateClientProtocol` de `src/middleware/basic.ts` (106 ao não local por HTTP). Ficaram nele a negociação de versão e a emissão de credencial (`/tv3/authorize`, `/tv3/token`). O 106 por protocolo da C.4.1.6 deixou de ser aplicado por qualquer processo até a borda ter TLS (L3) |
| **D-0510-2** | **A C.6.8 vai para a borda** (resolve o A3) | O plugin `tv30-auth` responde `POST`, `GET` e `DELETE /tv3/bind-context` (`infra/edgegateway/plugin/bindcontext.go`), com o contrato e o armazenamento do tv3ws; `tv3ws/src/api/broadcaster-security/` saiu. Há um leitor de chave só, e a borda passou a escrever `bind-context:{serviceId}` |
| **D-0510-3** | **A C.6.7.8 e a C.6.7.9 ficam na borda**, respondidas a partir da tabela de rotas | `GET /tv3/api-info/<api-id>` e `GET /tv3/api-info[?subsystem=...]` (`apiinfo.go`), com a lista de APIs e versões tirada do campo `api` do `routes.json` (Tabela C.2) |
| **D-0510-4** | **Guardar também os clientes autorizados**, para a futura tela de gerenciamento | SET `clients:authorized`, disjunto de `clients:blocked`; o `/tv3/token` exige o id nele. A borda continua conferindo só `clients:blocked`. A tela (C.4.2.2) não foi feita |

## Decisões de 03/10 (Luís)

Três pontos que estavam em aberto foram decididos **pelo Luís em 03/10**, e não pelo Joel. Ficam aqui para o orientador ver. Onde o texto mais abaixo os trata como abertos, vale esta seção. A numeração é a de [Decisões pendentes](decisoes-pendentes.md); entre parênteses, o rótulo usado no código, nos scripts e nos outros documentos (D-L1, D-L2, D-L4). O A3 (onde fica a API C.6.8), que seguiu aberto em 03/10, foi decidido pelo Joel em 05/10 (seção acima).

| | Ponto | Decisão |
|---|---|---|
| **A1** (D-L1) | Redis sem senha e publicado no host (6379) | A conexão com o Redis fica **como está**: sem senha, com a 6379 publicada, e sem mudança nos clientes, na carga inicial e no healthcheck. Só a interface administrativa (redis-commander, processo auxiliar do container `redis`) passa a exigir login, com `REDIS_COMMANDER_USER` (padrão `admin`) e `REDIS_COMMANDER_PASSWORD` (padrão `tv30-redis-admin`). Na versão instalada (0.9.0, fixada no `infra/redis/Dockerfile` desde 04/10), o login não é HTTP basic auth: a página de login abre sem credencial, e as rotas de dados respondem 401 sem o token que ele devolve. **O risco da 6379 continua:** em `enforce`, quem alcança a porta grava `origins:associated` ou `bind-context:*` e contorna a borda. |
| **A2** (D-L2) | `GET /tv3/authorize` sem `pm` reemitia o refresh token de qualquer cliente já autorizado | **101 no reuso de `clientid`**, para qualquer classe. Na norma, a Tabela C.3 prevê o erro 101 "if clientid has been used before" (p. 215; p. 233 do PDF), e a C.6.1.4.4 trata o reuso como colisão (p. 219; p. 237 do PDF). **A confirmar pelo Luís:** o `clientid` recusado pelo espectador também passou a dar 101, e não mais 102. É o que manda a nota da mesma tabela, mas a decisão falava só do `clientid` já usado; foi uma leitura dela feita na implementação. Quem perdeu o refresh token roda a autorização de novo com `clientid` novo (C.6.1.4.5), o que exige nova autorização do espectador. |
| **A5** (D-L4) | L1: reconhecer o local associado pelo `Origin` | **Risco aceito do `Origin` forjado**, sem mudança de comportamento. O critério continua sendo o `Origin` presente em `origins:associated`, e um `Origin` forjado fora do navegador passa como associado. O comentário no código é `DECIDIDO (Luis, 03/10): risco aceito`, no plugin da borda (`infra/edgegateway/plugin/handler.go`) e na classificação do cliente no tv3ws (`classifyClient`, em `tv3ws/src/api/client-identification/controller.ts`). **Não decidido, continua aberto: P1.3, origem própria por app.** As apps de emissora servidas pelo proxy do AoP chegam com o `Origin` do AoP, e o AoP grava em `origins:associated` a origem própria da app (`aop/src/core.js`, `registerAssociatedOrigin`); por isso elas não são reconhecidas como associadas e seriam bloqueadas em `enforce`. |

**Feito na integração de 04/10, espera o aval do Luís:** a correção do pareamento `kex` (o `/tv3/authorize?pm=kex` passou a devolver também `key`, como pedem a Tabela C.3, formato 3, e a C.4.3.3, passo 1). É correção de conformidade, não decisão de desenho; está descrita em [Decisões pendentes](decisoes-pendentes.md).

## Decisão de 28/09

A reunião de 28/09 decidiu o desenho que esta avaliação deixava em aberto. A seção abaixo **prevalece** sobre o resto do documento, que fica como estava em 21/09 com as correções marcadas adiante. A implementação entrou na semana de 28/09 em modo `warn`.

### Decidido

| | Decisão |
|---|---|
| **D1** | **Toda a validação de credenciais fica na borda**, num plugin Go **novo** no KrakenD (`edgegateway`, plugin `tv30-auth`). O tv3ws só implementa as APIs. Isso substitui a recomendação da "opção A" mais abaixo. |
| **D2** | **Access token:** são verificadas a assinatura e a expiração, sem `ignoreExpiration`. |
| **D3** | **Bind-token:** o testbed **não emite** bind-token. Ele registra o par `{alg, key}` da emissora pela C.6.8 e guarda (serviço, alg, chave) no Redis, em `bind-context:{serviceId}`. Os algoritmos aceitos são HS256, HS512, RS256 e RS512 (C.4.1.4.8). A validação segue as quatro frentes da C.4.1.4, nesta ordem: formato JWT, assinatura, `nbf`/`exp` e `iat`. |
| **D4** | **Isolamento entre emissoras:** o bind-token só vale se for assinado por uma chave registrada para o **serviço corrente** (`session:current-service-id`). A emissora pode registrar várias chaves, e qualquer uma delas valida. |
| **D5** | **Erros no formato C.3.2:** HTTP 404 com `{"error": <n>, "description": "..."}`, `Content-Type: application/json` e `Access-Control-Allow-Origin: *`. Os códigos são: 104, bind-token ausente; 107, access token ausente, inválido ou expirado, ou cliente bloqueado; 108, bind-token inválido, revogado ou de outro serviço; 106, classe de cliente errada; 100, rota não suportada. |
| **D6** | **Flag `AUTH_ENFORCE`**, com valor `warn` (padrão) ou `enforce`. Em `warn` nada é bloqueado: a borda registra `[tv30-auth] WARN ...` e devolve o cabeçalho `X-TV30-Auth-Warn: <código>`. O motivo é que o cliente Guaraná ainda não obtém token. |

**Estado corrente (não é a decisão).** Diferenças entre o que foi decidido e o que o código faz hoje:
- **D1:** até 05/10, o tv3ws ainda validava parte da credencial, nos dois modos: respondia 107 a um `Authorization` presente e inválido (`tv3ws/src/middleware/authorization.ts`) e 106 ao cliente não local que chegava por HTTP (`validateClientProtocol` em `tv3ws/src/middleware/basic.ts`). **Resolvido pela D-0510-1 (reunião de 05/10 com o Joel):** as duas validações saíram, e o tv3ws não confere credencial. O 106 por protocolo não foi para a borda, porque ela não tem TLS (L3).
- **D6:** em `warn`, a borda bloqueia duas coisas que não são credencial: o 100 (rota não declarada, que antes derrubava a conexão com o panic do Gin) e o 200 (panic do roteador). Nenhum cliente dependia dessas rotas, porque elas nunca chegavam ao tv3ws. Nas APIs que a borda responde desde 05/10 (C.6.8, C.6.7.8 e C.6.7.9), os erros da própria API (101, 104, 105, 108, 300, o 100 da negociação de versão e o 200 de Redis fora) também saem nos dois modos, porque não são decisão de credencial: são a resposta da API.

### Lacunas sem decisão

Até 03/10, nenhuma destas lacunas tinha sido resolvida pelo Joel. A L1 foi decidida pelo Luís em 03/10, com o risco aceito (seção *Decisões de 03/10*), e a L6 foi decidida em 04/10 (opção B, informado pelo Luís) e re-decidida pelo Luís em 09/10 (opção A); as demais seguem sem decisão. Onde o código precisa de algum comportamento, adotou-se o mínimo provisório, marcado `PENDENTE (Joel)` no código. A exceção é a L1: o marcador dela virou `DECIDIDO (Luis, 03/10): risco aceito` (`infra/edgegateway/plugin/handler.go` e `classifyClient` em `tv3ws/src/api/client-identification/controller.ts`). **Correção (03/10):** a versão anterior desta frase dizia que o provisório valia "só enquanto a flag estiver em `warn`". É o contrário: o provisório (L1, L2, L4, L5) está ativo nos **dois** modos. Em `warn` ele só registra e marca `X-TV30-Auth-Warn`; em `enforce` ele bloqueia ou libera. Em `enforce`, o reconhecimento do associado pelo `Origin` (L1) é uma porta de entrada sem credencial: um `Origin` forjado fora do navegador, presente em `origins:associated`, dispensa access token e bind-token em toda rota que admite o associado, inclusive `POST` e `DELETE /tv3/bind-context`. Esse é o risco aceito pelo Luís em 03/10.

| | Lacuna | Comportamento provisório |
|---|---|---|
| **L1** | Mecanismo definitivo para reconhecer o cliente local associado. A C.4.1.7 sugere a porta de origem. | Requisição sem `Authorization` cujo `Origin` está em `origins:associated` é tratada como associada. Com `Authorization` presente e inválido, o `Origin` também é consultado, só para o 106 (não dispensa credencial). **Decidido pelo Luís em 03/10:** fica como está, com o risco aceito. |
| **L2** | Identidade do serviço e `serviceContextId` próprio de cada serviço. Hoje o `serviceContextId` é uma constante (`tv3ws/src/core.ts:51`). | Nas rotas `/tv3/{serviceContextId}/...`, o scid do caminho conta como serviço corrente quando é `current-service` ou igual à constante. Qualquer outro valor dá 108. |
| **L3** | TLS na borda e PKI. A porta 44643 ainda está em HTTP. | Nada implementado na borda, nem o 106 por protocolo. Até 05/10, o 106 por protocolo existia no tv3ws (`basic.ts`), para o não local que chegava por HTTP; saiu com a D-0510-1, e desde então ninguém o aplica (fica só o 106 da renovação por HTTP no `/tv3/token`). O `Server-SecureBaseURL` do `/manifest` anuncia `<host>:44643`, porta sem TLS. |
| **L4** | Se o tv3ws deve parar de emitir token para o associado (106 em `/authorize` e `/token`). | Só no plugin, e só em `enforce`. O 106 depende do `Origin`: um `/tv3/token` chamado fora do navegador, sem `Origin`, passa. |
| **L5** | Relógio de referência do bind-token. A norma usa o System Time Fragment. | Relógio do host. |
| **L6** | SSDP: anunciante na borda em rede do host (A) ou anunciante separado (B). | **Decidida pelo Luís em 09/10: opção A.** O anúncio sai da borda, em rede do host, quando o override `docker-compose.ssdp.yml` está ligado (só Linux nativo); o `/manifest` continua no tv3ws, atrás da borda. Pelo morre-inteiro, também decidido pelo Luís em 09/10 e revisto por ele em 10/10, o erro de configuração do anúncio derruba a borda inteira; a falta de rede não, e o anunciante espera e tenta de novo. Substituiu a opção B, decidida em 04/10 (informado pelo Luís): o container `tv3ws-ssdp`, com a imagem do tv3ws, em rede do host ([Verificação SSDP](ssdp-verificacao.md)). |
| **L7** | Liberação dos recursos compartilhados ao revogar uma chave (C.4.4). | Não implementado. |

### Pontos sem decisão levantados na implementação (para o Joel)

Estes pontos não estão entre L1–L7. Dois foram decididos pelo Luís em 03/10 (o Redis e o reuso de `clientid`, marcados abaixo e na seção *Decisões de 03/10*), e um pelo Joel em 05/10 (onde fica a C.6.8). Os demais seguem sem decisão, e o código só registra.

- **Abertos pela rodada de 05/10** (detalhe na seção E de [Decisões pendentes](decisoes-pendentes.md)): a borda só recusa o `sub` em `clients:blocked` e não exige a presença em `clients:authorized` (E6); a futura tela da C.4.2.2 precisa decidir o que o desbloqueio faz e guardar o `display-name` (E5); e o 106 por protocolo ficou sem quem o aplique (E7, L3).

- **Redis sem senha e publicado no host (6379).** **Decidido pelo Luís em 03/10 (A1):** a conexão fica como está; só o redis-commander passa a exigir senha. O risco descrito a seguir continua. Em `enforce`, a decisão da borda vem de chaves desse Redis. Quem alcança a porta pode gravar `origins:associated` (vira local associado) ou `bind-context:{serviceId}` (registra a própria chave de bind) e contornar a borda. Publicar a 6379 é decisão anterior (V10 do plano de consolidação). As opções levantadas aqui eram publicar só em `127.0.0.1` (o teste dev-host continuaria funcionando, porque usa `127.0.0.1` e `--network host`) ou exigir senha no Redis. Nenhuma das duas foi adotada para a conexão.
- **Onde fica a API C.6.8 (`POST|GET|DELETE /tv3/bind-context`).** **Decidido pelo Joel em 05/10 (A3, D-0510-2): na borda.** Até ali, a reunião de 28/09 não tinha decidido se ela ficava no tv3ws ou no plugin. A especificação da semana de 28/09 a pôs no tv3ws, que por isso tinha um segundo leitor de chave e de bind-token (`broadcaster-security/bind-token.ts`) para o `GET /tv3/bind-context`; na reunião de 28/09, o Joel já tinha rejeitado um `bind-token.ts` no tv3ws ("tem que ser lá no KrakenD ainda. No plugin"). Os dois leitores eram mantidos iguais por um teste cruzado (`tv3ws/test/fixtures/keyformats.json` = `infra/edgegateway/plugin/testdata/keyformats.json`). Desde a D-0510-2, o plugin responde as três rotas (`bindcontext.go`), o leitor do tv3ws e a cópia do arquivo de casos saíram, e o `testdata/keyformats.json` ficou como teste de regressão do plugin.
- **`POST /tv3/{serviceContextId}/users`.** A rota não existe na norma (só `POST /tv3/current-service/users`, C.6.14.1, bind-token *shall*), mas o tv3ws a atende com o mesmo handler. Ela começou como `token`, o que deixava passar sem bind-token. Agora está como `token+bind`, com a regra provisória da L2. Falta decidir se a rota fica ou sai.
- **`GET /tv3/authorize` sem `pm` reemitia o refresh token de qualquer cliente já autorizado.** **Decidido pelo Luís em 03/10 (A2): 101 no reuso de `clientid`, para qualquer classe.** O trecho era anterior à semana de 28/09 (`tv3ws/src/api/client-identification/controller.ts`, "Cliente local ja autorizado que perdeu o refresh token"). Quem conhecesse o `clientid` de um cliente autorizado obtinha o refresh token dele e, com o `/tv3/token`, um access token com a classe da vítima. A borda não impedia, porque `/tv3/authorize` é `auth=none`. A norma prevê 101 no reuso de `clientid` na C.6.1.2 (Tabela C.3 e C.6.1.4.4). O mínimo sugerido aqui antes da decisão não foi adotado: reemitir só quando a classe gravada fosse local e igual à atual, com prova de posse (o refresh token antigo).
- **SSDP.** Com o padrão do compose (`SERVER_URL=localhost`), o anúncio e o `/manifest` divulgam o host de loopback, e um cliente em outro equipamento não alcança o `LOCATION`. O tv3ws e o anunciante da borda avisam no boot (`[ssdp] AVISO`), mas o padrão não mudou. Falta decidir entre cair no IP local quando `SERVER_URL` for loopback e exigir `SSDP_ADVERTISE_HOST`. Também falta decidir o que o `Server-SecureBaseURL` anuncia enquanto a L3 estiver aberta: a 44643 da borda, que é HTTP, ou o HTTPS do próprio tv3ws, que não é publicado no host.

### Correções a esta avaliação

As afirmações de 21/09 que estão erradas seguem abaixo, cada uma marcada como **correção**.

- **Correção: o plugin Go antigo nunca validou nada.** O handler de `infra@60e527f:gateway-external/plugin/consent-validator.go` repassava toda requisição ao ccws e devolvia a resposta sem olhar credencial; ignorava até o próximo handler do KrakenD. Era proxy puro. Por isso o plugin `tv30-auth` foi escrito do zero. Quando a seção *O que mudou* fala no "plugin Go que o chamaria", supõe um validador que nunca existiu.
- **Correção: o cliente local associado não usa bind-token nem access token.** Ele usa as APIs do próprio contexto de serviço sem bind-token (C.4.1.1: "may use the APIs protected by the broadcaster, referencing their own service context, without using the bind-token") e não passa pelas etapas da C.6.1. O mecanismo que o reconhece fica a cargo da implementação (C.4.1.7). Estão erradas, portanto:
  - a frase "ele se identifica pelo bind-token";
  - a linha "local associado | bind-token" da tabela;
  - o item 3 do plano de ativação, que dá bind-token ao associado.
- **Correção: o cliente local autônomo também precisa de bind-token.** Além do access token, ele envia bind-token nas APIs protegidas. Os erros 104 e 108 de cada API valem para "non-local client or stand-alone local client".
- **Correção: o receptor não assina nem emite bind-token.** Ele só registra a chave (C.6.8.2), valida o token e revoga a chave (C.6.8.4). O token é obtido "directly with DTV service providers" (A.4.9). Estão erradas as afirmações "a mais nova assina" e "hoje não há emissor... pré-requisito de implementação". Uma ferramenta que simule a emissora seria decisão do projeto, não exigência da norma.
- **Correção: a contagem é 27, não 20.** São **27 APIs** cujo campo "Security requirements" exige o bind-token (*shall*), além de 3 classes de evento. Somando as 8 que listam 104/108 com o campo em branco, chega-se a 35. Somando também as 2 de persistência, 37. Nenhum critério dá 20; o número veio da vacina (P2.5) e foi copiado para cá.

Tabela corrigida, que substitui a da seção *Descoberta na norma*. Os nomes de classe são os que o tv3ws grava no claim `class`:

| Classe (`class`) | Credencial nas APIs |
|---|---|
| local associado (`local-associated`) | nenhuma, nas APIs do próprio contexto de serviço (C.4.1.1) |
| local autônomo (`local-autonomous`) | accessToken; bind-token nas 27 APIs *shall* |
| não local (`non-local`) | accessToken, via HTTPS fora de C.6.1.2 e C.6.1.3 (C.4.1.6); bind-token nas 27 APIs *shall* |

---

> Combinado da reunião de 21/09: **avaliar primeiro e apresentar**, porque
> "tem que ver se vai ser tão tranquilo assim". Este documento é essa
> avaliação. Nada daqui está implementado.

## O que P2 exige (vacina, decisão tomada)

1. accessToken validado **na borda**, por configuração estática.
2. `POST /validate` ligado como ponto de validação do **bind-token**, sem o
   `ignoreExpiration: true`.
3. Chave de bind-token em **lista rotacionável** por contexto de serviço.
4. Gateways/middleware conhecendo o **cabeçalho de bind-token** (exigido em
   20 APIs do Anexo C).
5. Cabeçalho liberado no **CORS** das duas superfícies.

## O que mudou desde que P2 foi escrita

- **O container do middleware morreu na consolidação (fase 2).** O código do
  `POST /validate` sobrevive só no histórico (`infra@f2eb652^:middleware/index.js`).
  Detalhe importante: aquele `/validate` validava **accessToken**, não
  bind-token — e nunca teve chamador (o plugin Go que o chamaria foi
  removido junto com o buraco do proxy-tudo).
- **O item 8 já fez metade do caminho:** o `exp` do JWT funciona (era
  inválido desde sempre — o token nascia "expirado em 1970" e por isso o
  middleware antigo precisava do `ignoreExpiration`), a classe do cliente
  viaja na credencial, e o tv3ws valida token **quando presente** (107 no
  formato C.3.2). Falta só a *exigência*.
- **P5 moveu o estado dinâmico pro Redis** — o "componente que guarda estado
  dinâmico" da P2 hoje é o tv3ws lendo `client:{id}` do armazenamento.

## Descoberta na norma que muda o desenho

**C.6.1.3 (Tabela C.4): a API de token "shall only be accessible to
non-local clients and stand-alone local clients."** O cliente **local
associado não obtém accessToken** — ele se identifica pelo **bind-token**
vinculado ao contexto de serviço (C.6.8). Consequência: a borda **não pode
exigir accessToken de todas as requisições** — a exigência é por classe:

| Classe | Credencial esperada nas APIs |
|---|---|
| local associado | bind-token (nas 20 APIs que o exigem) |
| local autônomo | accessToken |
| não local | accessToken (+ bind-token nas 20 APIs) |

## A tensão central: P2 ("na borda") × C.3.2 (formato de erro)

O validador JWT nativo do KrakenD responde **401 sem corpo**. A norma exige
que erro de API seja **404 + corpo `{error: 107, description}`** (C.3.2) —
acabamos de implementar exatamente isso no item 6, e a borda virou proxy
puro para **não** engolir esse formato. Validar na borda com o mecanismo
nativo reintroduz resposta fora da norma; customizar o corpo de erro do
KrakenD exige plugin próprio — e foi um plugin próprio que criou o buraco
de segurança que fechamos na fase 2.

## Opções

**A. Exigência no tv3ws (recomendada).** O middleware `authorization.ts` já
valida credencial presente; vira exigência (sem credencial → 107; nas 20
APIs, sem bind-token → 104). Erros saem no formato C.3.2 pela camada do
item 6. A borda segue como topologia (superfícies/rotas/CORS). P2 fica
atendida "na fronteira do serviço" em vez de "no processo do gateway" — a
diferença é de processo, não de superfície exposta: a porta direta do
serviço já foi fechada no item 8.

**B. Exigência no KrakenD (literal de P2).** JWT validator por rota na
tabela M4 (gera `auth/validator` com JWK derivada do `JWT_SECRET`).
Custos: 401 seco fora do formato C.3.2; sem como validar bind-token
(estado dinâmico — KrakenD não consulta Redis sem plugin); a regra "por
classe" acima não é expressável (o validador não distingue associado sem
accessToken de autônomo sem accessToken).

**C. Híbrida.** KrakenD valida assinatura/expiração do accessToken *quando o
header vem* (gate barato contra lixo), e o tv3ws aplica exigência, classe e
bind-token com erros conformes. Custo: dois pontos de verdade.

## Bind-token — desenho proposto (para as opções A ou C)

- Chaves rotacionáveis por contexto: `bind-keys:{scid}` (lista no Redis;
  a mais nova assina, todas verificam — rotação sem janela de corte).
- Validação num middleware `bind-token.ts` do tv3ws (o sucessor natural do
  `POST /validate` pós-consolidação), **sem** `ignoreExpiration`.
- Cabeçalho `bind-token` entra em `allow_headers` do CORS e nos
  `input_headers` das rotas na tabela M4 (uma edição em `routes.json`).
- Erros: 104 (ausente), 108 (inválido/revogado/de outro serviço) — códigos
  já estão no catálogo do item 6.
- Emissão/registro do bind-token (C.6.8) precisa existir antes da exigência
  — hoje não há emissor. **Isso é pré-requisito de implementação.**

## Plano de ativação sem quebrar o testbed

1. Emissor de bind-token (C.6.8) + chaves rotacionáveis no Redis.
2. Middleware de exigência com **flag** (`AUTH_ENFORCE=warn|enforce`):
   em `warn`, loga o que SERIA rejeitado (dá tempo de adaptar os apps de
   demonstração); em `enforce`, rejeita com 104/107/108.
3. Adaptar consumidores: apps do bcast (users-test, webmedia, companion)
   ganham o fluxo authorize→token (autônomo/não-local) ou bind-token
   (associado). O companion (não local) precisa do pareamento real
   (QR/PIN) — é o maior trabalho de consumidor.
4. Virar a flag para `enforce` e registrar no CHANGELOG.

## Perguntas para o orientador

1. **Onde vale P2 "na borda"** dado o conflito com o formato C.3.2 — opção
   A, B ou C? (Recomendo A; a literalidade de B custa conformidade de erro
   ou um plugin novo no gateway.)
2. **C.6.8**: o detalhamento da emissão do bind-token (quem emite, quando,
   payload) — tem material do Fórum além do Anexo C?
3. O pareamento real no companion do demo entra nesta frente ou espera?
