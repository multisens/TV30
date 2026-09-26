---
title: "Avaliação: item 9 — validação de credenciais (P2)"
nav_order: 12
---

# Item 9 (P2) — validação de credenciais: avaliação antes de implementar

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
