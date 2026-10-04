---
title: "Decisões pendentes (para o orientador)"
nav_order: 14
---

# Decisões pendentes — estado em 03/10/2026

Lista única dos pontos que dependem do orientador. Cada um está marcado `PENDENTE (Joel)` no código ou na documentação. Nenhum foi resolvido por conta própria. O detalhe técnico está nos documentos citados.

- [Avaliação do item 9](avaliacao-item9-credenciais.md): credenciais e lacunas L1–L7.
- [Verificação SSDP](ssdp-verificacao.md): descoberta, L6 e testes de rede.

## A. Antes de ligar o `AUTH_ENFORCE=enforce` (item 9)

A validação na borda está em produção em modo `warn`: nada é bloqueado, só registrado. Estes pontos precisam de decisão antes do `enforce`.

| # | Ponto | Por que importa | Opções |
|---|---|---|---|
| A1 | **Redis 6379 publicado no host e sem senha** | A borda decide com dados do Redis. Quem alcança a 6379 grava `origins:associated` (vira associado) ou `bind-context:*` (registra a própria chave de emissora) | publicar só em `127.0.0.1` (o dev-host continua funcionando), ou senha no Redis |
| A2 | **`GET /tv3/authorize` sem `pm` reemite o refresh token de qualquer cliente já autorizado** (anterior a esta semana) | Quem conhece o `clientid` de outro cliente obtém um access token com a classe dele | 101 no reuso de `clientid` (C.6.1.4.4), ou exigir prova de posse (o refresh token antigo) |
| A3 | **Onde fica a API C.6.8** (`/tv3/bind-context`) | Ficou no tv3ws; a reunião de 28/09 falou em "no plugin". Hoje há dois leitores de chave (tv3ws e borda), mantidos iguais por teste | manter no tv3ws, ou mover para o plugin |
| A4 | **`POST /tv3/{serviceContextId}/users`** | Não existe na norma (só `current-service/users`). Foi para `token+bind` para não furar o bind-token | manter, ou tirar da tabela de rotas |
| A5 | **L1: como reconhecer o local associado** | Hoje é o `Origin` em `origins:associated`. As apps de emissora são servidas pelo proxy do AoP na mesma origem (P1.3 não feito), e um `Origin` forjado fora do navegador passa | origem própria por app (P1.3), porta de origem (C.4.1.7), outro |
| A6 | **L2: identidade do serviço** | `serviceContextId` é constante para todo serviço; rotas `/tv3/<scid>/...` usam uma regra provisória | definir scid por serviço |
| A7 | **L3: TLS na borda (44643 em HTTP)** | Sem TLS não há 106 por protocolo para o não local, o `Server-SecureBaseURL` aponta para porta sem TLS e o remote-device devolve `ws://` em vez de `wss://` | decidir a PKI |
| A8 | **L4: 106 ao associado em `/authorize` e `/token`** | Implementado só no plugin e só em `enforce`; `/tv3/token` sem `Origin` passa | confirmar a regra |
| A9 | **L5: relógio do bind-token** | A norma usa o System Time Fragment; usamos o relógio do host | confirmar |
| A10 | **L7: liberar recursos ao revogar chave (C.4.4)** | Não implementado | prioridade |

Dependência fora do projeto: o Guaraná (Pedro) precisa obter o access token antes do `enforce`.

## B. Descoberta SSDP (item 23, L6)

Medido em 02 e 03/10:
- o anúncio sai do container e chega à bridge do Docker, mas o kernel da VM do WSL não o repassa;
- com o anunciante em `network_mode: host`, ele chega ao próprio Windows;
- um celular na rede doméstica faz SSDP com o roteador, mas não acha o testbed (0 respostas).

| # | Ponto | Opções |
|---|---|---|
| B1 | **L6: onde roda o anunciante** | **A:** a borda anuncia, em modo host (direção de 28/09; a borda é KrakenD, então o anúncio precisa ser reescrito). **B:** container só para o anúncio, em modo host (contraria "borda num container só"). **tv3ws em modo host:** o caminho mais curto, mas exige escutar só em `127.0.0.1` para não reabrir a porta direta |
| B2 | **Host padrão do anúncio** | Hoje é `localhost` (`SERVER_URL`). Opções: cair no IP local quando for loopback, ou exigir `SSDP_ADVERTISE_HOST` |
| B3 | **Expor os cabeçalhos do `/manifest` ao navegador (CORS)** | expor `Server-*`/`Device-*` ou não |

Nenhuma opção funciona em Windows com WSL2 em NAT. O teste positivo precisa de Linux nativo com Docker Engine; o roteiro está em [ssdp-verificacao.md](ssdp-verificacao.md).

## C. Outros pontos

| # | Ponto | Situação |
|---|---|---|
| C1 | **Portas fixas** | A decisão é "só a 44642 fixa". O código ainda fixa 44643, 1883, 9001, 6379, 8080, 8081 e a faixa 45000–45199. Confirmar quais são exceções aceitas (em 21/09 o MQTT foi citado como fixo) |
| C2 | **Morre-inteiro: exceção do redis-commander** | A morte do commander não derruba o banco (override 2 do plano de consolidação). Aceitar ou não |
| C3 | **`locator` × `location`** (efeitos sensoriais) | O tv3ws usa `locator` conforme o PDF; o cliente do bcast e a vacina usam `location`. Arbitrar |
| C4 | **Itens 12, 13, 14 e 21** | O 13 foi tirado da lista do Luís de forma explícita (28/09). O 12, o 14 e o 21 também, mas de forma genérica. Confirmar se saem do projeto ou passam para outra pessoa |
| C5 | **URL SSH do bcast no `.gitmodules`** (L8) | Quem não tem chave SSH no GitHub não clona o submódulo. Trocar por HTTPS? |
| C6 | **Lista de identificadores da norma para os nomes** (R-1) | Aguardando a lista. Os repositórios AOP, BcastService e Infra mantêm os nomes antigos |
| C7 | **Detalhamento do Privacy Manager** | Aguardando o material prometido em 15/09 |
| C8 | **Sem rede, o SSDP derruba o tv3ws inteiro** (regra morre-inteiro) | Num notebook offline, as APIs HTTP caem junto. Aceitar ou abrir exceção |

## Correções e respostas para levar

- **O plugin Go antigo nunca validou nada.** Era proxy puro (`infra@60e527f:gateway-external/plugin/consent-validator.go`). O `tv30-auth` foi escrito do zero.
- **"Registrar para quem cada token foi emitido?"** A norma não manda registrar, mas o bloqueio de cliente (C.4.2.2) e o refresh token por cliente (Tabela C.4) só funcionam com esse vínculo, e o código já o guarda em `client:{id}`. O ponto A2 enfraquece essa garantia.
- **O item 5 o Joel dispensou em 28/09.** Ele mesmo está avançando a parte de transporte (21/09).
