---
title: Borda e credenciais
description: Para que serve a borda e como ela decide cada requisição às APIs - superfícies, credenciais, versão, CORS e repasse.
---

A **borda** é o container `edgegateway`, a entrada única das APIs. Todo cliente chega por ela: os
serviços que implementam as APIs não publicam porta no host. Ela tem dois processos KrakenD, um gateway
de API, um por superfície, e um plugin, `tv30-auth`, que decide sobre a credencial e a versão de cada
requisição. Onde ela fica no conjunto está em [Arquitetura](../arquitetura/).

## Para que serve a borda

A norma especifica as APIs dos TV 3.0 WebServices, mas não diz que processo as atende. No testbed,
cada API pode ser implementada por um serviço diferente, e um componente novo pode trazer as suas. A
borda é o que permite isso sem que o cliente perceba:

- **Um endereço por superfície.** O cliente chama sempre a 44642 ou a 44643, qualquer que seja o
  serviço que responde a rota. Acrescentar ou trocar esse serviço não muda a URL que a norma fixa.
- **A credencial conferida num lugar só.** O access token, o bind-token, a classe do cliente e a versão
  são conferidos na borda, antes do repasse. O serviço que implementa a API recebe a chamada já
  decidida e não precisa repetir essa lógica.
- **As rotas declaradas num lugar só.** Cada rota diz o que exige e quais versões serve, e é dessa
  declaração que a borda se configura ([Acrescentar ou mudar uma rota](#acrescentar-ou-mudar-uma-rota)).

Hoje toda rota vai ao `tv3ws` ou é respondida pela própria borda: encaminhar uma rota a outro serviço
ainda não é possível.

## As duas superfícies

As duas servem as mesmas 27 rotas. O que muda é quem recebe 106:

| Superfície | Porta | Protocolo | Responde 106 |
|---|---|---|---|
| interna (`Server-BaseURL`) | 44642, fixada pela C.3.4 | HTTP | ao cliente não local, fora de `/tv3/authorize` e `/tv3/token` (C.4.1.6) |
| externa (`Server-SecureBaseURL`) | 44643 | HTTPS, terminado na borda | às rotas só do cliente local (`POST` e `DELETE /tv3/bind-context`, C.6.15.5, rotas por `handle`) e ao `/tv3/authorize`, para qualquer cliente (C.4.1.8) |

- **Certificado.** Na primeira subida, a tarefa `tv30-tls-init` gera um certificado autoassinado em
  `.tv30/tls`, sem ação do usuário (C.4.1.1). A borda o usa na 44643, e o `tv3ws`, no HTTPS interno,
  no `serverCert` do pareamento e no `wss://` do dispositivo remoto.
- **Variante.** `EDGE_VARIANT` diz onde a borda procura os serviços: `linux` (padrão, em container) ou
  `windows` (o serviço rodando no computador; [Desenvolvimento com serviço no host](../dev-local/)).

## Como a borda decide cada requisição

O plugin confere nesta ordem, e a primeira etapa que falha dá o erro:

| # | Etapa | Erro | O que confere |
|---|---|---|---|
| 1 | Rota | 100 | método e caminho declarados |
| 2 | Superfície | 106 | o 106 da externa, na tabela acima |
| 3 | Classe | 106 | a classe do cliente contra as que a rota admite. A classe vem do access token; sem `Authorization`, um `Origin` na lista de origens associadas faz do cliente um local associado |
| 4 | Não local por HTTP | 106 | na interna, o token de classe não local fora de `/tv3/authorize` e `/tv3/token` |
| 5 | Access token | 107 | `Authorization: Bearer <jwt>` assinado com o `JWT_SECRET`, dentro do prazo, com o `iss` igual ao `JWT_ISSUER`, de um cliente autorizado e não bloqueado |
| 6 | Serviço selecionado | 300 | nas rotas que pedem serviço DTV em uso (C.6.4.7, C.6.14.1 a C.6.14.6) |
| 7 | Serviço no catálogo | 304 | na C.6.14.2 e na C.6.14.5 com `{serviceContextId}` no caminho, um serviço que não foi anunciado |
| 8 | Bind-token | 104, 108 | nas rotas `token+bind`: sem o cabeçalho, 104; sem assinatura de uma chave registrada (C.6.8.2) para o contexto de serviço da rota, 108 |
| 9 | Versão | 100, 101 | o `Accept-Version` contra as versões da rota (C.3.6.5): sem ele, vale 2.0; fora do formato X.Y, 101; versão que a rota não serve, 100 |

- **O cliente local associado** não leva access token. No contexto do serviço que lançou a aplicação,
  também dispensa o bind-token; no de outra emissora, segue a regra geral da etapa 8 (C.4.1.1).
- **O contexto de serviço da rota** é o `{serviceContextId}` do caminho ou, nas rotas sem ele, o
  serviço corrente. O `serviceContextId` é o `globalServiceId` do BAM.
- **O relógio** do bind-token é o do computador, sem tolerância: a emissora simulada e o receptor rodam
  na mesma máquina.
- **Redis fora do ar** durante a decisão dá 200.

### `warn` e `enforce`

`AUTH_ENFORCE`, no `.env` da raiz, vale `enforce` por padrão.

- Em `warn`, só as recusas de credencial (104, 107 e 108) deixam de recusar: a requisição segue, com o
  cabeçalho `X-TV30-Auth-Warn: <código>` e um aviso no log da borda. Serve, por exemplo, para um
  cliente que ainda não obtém token.
- 100, 101, 106, 300, 304 e 200 valem nos dois modos.

## CORS

A borda responde todo o CORS (C.4.1.9); o serviço que implementa a API não manda cabeçalho CORS.

- **Toda resposta** leva `Access-Control-Allow-Origin: *` e expõe `Content-Length` e
  `X-TV30-Auth-Warn`.
- **Preflight**, em qualquer caminho: 200, com `Access-Control-Allow-Methods: *`,
  `Access-Control-Allow-Headers: Content-Type, Authorization, bind-token, Accept, Accept-Version, key`
  e `Access-Control-Max-Age: 43200`. O `key` é o cabeçalho do `DELETE /tv3/bind-context` (C.6.8.4).

## Repasse ao serviço

A rota que a borda não responde sozinha é repassada ao serviço que a implementa.

- **Proxy puro.** Status, cabeçalhos e corpo do serviço chegam intactos ao cliente, inclusive as
  respostas binárias.
- **Cabeçalhos.** Passam só os cabeçalhos e os parâmetros declarados em cada rota, o `bind-token` nas
  rotas `token+bind` e quatro cabeçalhos que a borda acrescenta, apagando o que vier do cliente:

  | Cabeçalho | Leva |
  |---|---|
  | `X-TV30-API-Version` | a versão decidida na etapa 9; o serviço responde nela |
  | `X-TV30-Host` | o `Host` original, para o `/manifest` |
  | `X-TV30-Client-Class` | a classe do cliente |
  | `X-TV30-Client-Id` | o `clientid`, para as classes que se autorizam |

- **Versões de proposta.** Nas versões de 100 em diante, a borda repassa ao serviço em `/v<X.Y>` mais o
  caminho público. O cliente usa só o caminho público.
- **Tempo de espera.** 2 s, salvo a rota que declara outro (o `GET /tv3/authorize` espera 15 s pela
  resposta do espectador). Sem resposta, ou com o serviço fora do ar, a borda responde 200.

## Configuração

O ambiente da borda, no `.env` da raiz:

| Variável | Padrão | Uso |
|---|---|---|
| `AUTH_ENFORCE` | `enforce` | `warn` só avisa nas recusas de credencial |
| `JWT_SECRET` | o de desenvolvimento | o segredo do access token; o mesmo do serviço que o emite |
| `JWT_ISSUER` | `GenericIssuer` | o `iss` exigido no access token |

Configuração inválida derruba o container na partida, com `[tv30-auth] FATAL` no log
(`docker logs edgegateway`).

## Acrescentar ou mudar uma rota

As rotas estão declaradas num lugar só, `infra/edgegateway/routes.json`. Cada rota tem:

| Campo | O que diz |
|---|---|
| `method`, `path` | a rota |
| `auth` | `none`, `token` ou `token+bind` |
| `classes` | as classes de cliente admitidas; sem o campo, todas |
| `api` | a linha da Tabela C.2, que entra na descrição das APIs (C.6.7.8, C.6.7.9) |
| `versions` | as versões servidas; sem o campo, 2.0 |
| `no_service`, `not_in_catalog` | as etapas 6 e 7 da decisão |

As configurações do KrakenD, a documentação das rotas e a tabela do plugin são geradas dela no build
da imagem, que também roda os testes e para se algum falhar. Depois de mudar o arquivo, reconstrua a
borda:

```bash
docker compose up -d --build edgegateway
```

A documentação das rotas das duas superfícies fica numa porta escolhida pelo Docker
(`docker port edgegateway 8085`).

## Quem emite a credencial

- **Access token:** o `tv3ws`, no `/tv3/authorize` e no `/tv3/token`
  ([Chamar as APIs de outro aparelho](../apis-de-outro-aparelho/)). Ele não emite credencial ao cliente local
  associado: responde 106.
- **Bind-token:** o testbed não emite. A emissora registra a chave pela C.6.8.2 e assina os próprios
  tokens; a borda só os confere.

O teste das credenciais na stack é o `scripts/test-auth.sh` ([Como testar](../como-testar/)).
