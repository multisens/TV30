---
title: "Decisões pendentes (para o orientador)"
nav_order: 14
---

# Decisões pendentes — estado em 04/10/2026

Lista única dos pontos que dependem do orientador. Os que seguem em aberto estão marcados `PENDENTE (Joel)` no código ou na documentação, e nenhum deles foi resolvido por conta própria. O detalhe técnico está nos documentos citados.

**Decididos pelo Luís em 03/10:** A1 (D-L1), A2 (D-L2) e A5 (D-L4). Os rótulos D-L1, D-L2 e D-L4 que aparecem no código, nos scripts e nos outros documentos são estas três decisões. Ficam na tabela, marcados como decididos, com o que foi feito, para o orientador ver. Não foram decididos pelo Joel. O A3 continua aberto, em consulta. Da A5 só o risco do `Origin` forjado foi decidido; a origem própria por app (P1.3) continua aberta.

**Decidido em 04/10 (informado pelo Luís):** B1, a L6, pela opção B (anunciante SSDP num container próprio, em modo host). Com ela, o C8 ficou resolvido no deploy em container. A B2 (host padrão do anúncio) continua aberta.

**Esperam confirmação do Luís** (feitas na implementação e na integração, fora do texto das decisões, e já enviadas no tv3ws `cc0d1a9`): o 101 para `clientid` bloqueado, que antes dava 102, e a correção do `kex`. As duas estão descritas abaixo.

**Aprovados pelo Luís em 04/10** (escolhas da implementação da opção B):
1. O `SSDP_ADVERTISE_HOST` é lido por `env_file` (`tv3ws/.env` e depois o `.env` da raiz), e não pela seção `environment` do compose. Os efeitos colaterais estão em [ssdp-verificacao.md](ssdp-verificacao.md): um valor só exportado no shell não chega aos containers, e as outras chaves do `.env` da raiz entram nos dois.
2. O `tv3ws-ssdp` que fica de pé quando o perfil `ssdp` sai passou a ser avisado pelo `scripts/preflight.sh`, que também mostra o comando para removê-lo.
3. No cenário 1 do dev-host, o `tv3ws-ssdp` é parado enquanto o tv3ws do host anuncia, e é religado no fim.

- [Avaliação do item 9](avaliacao-item9-credenciais.md): credenciais e lacunas L1–L7.
- [Verificação SSDP](ssdp-verificacao.md): descoberta, L6 e testes de rede.

## A. Antes de ligar o `AUTH_ENFORCE=enforce` (item 9)

A validação na borda está em produção em modo `warn`: nada é bloqueado, só registrado. Estes pontos precisam de decisão antes do `enforce`.

| # | Ponto | Por que importa | Opções |
|---|---|---|---|
| A1 | **Redis 6379 publicado no host e sem senha** — **DECIDIDO (Luís, 03/10)** | A borda decide com dados do Redis. Quem alcança a 6379 grava `origins:associated` (vira associado) ou `bind-context:*` (registra a própria chave de emissora) | **Decidido:** a conexão com o Redis fica como está, sem senha e com a 6379 publicada. Só a interface administrativa (redis-commander) passa a exigir senha. Ver abaixo. Opções levantadas antes: publicar só em `127.0.0.1`, ou senha no Redis |
| A2 | **`GET /tv3/authorize` sem `pm` reemitia o refresh token de qualquer cliente já autorizado** (anterior à semana de 28/09) — **DECIDIDO (Luís, 03/10)** | Quem conhecesse o `clientid` de outro cliente obtinha um access token com a classe dele | **Decidido:** 101 no reuso de `clientid`, para qualquer classe (C.6.1.4.4). Ver abaixo. A outra opção era exigir prova de posse (o refresh token antigo) |
| A3 | **Onde fica a API C.6.8** (`/tv3/bind-context`) | Ficou no tv3ws; a reunião de 28/09 falou em "no plugin". Hoje há dois leitores de chave (tv3ws e borda), mantidos iguais por teste | manter no tv3ws, ou mover para o plugin. **Em aberto, em consulta** |
| A4 | **`POST /tv3/{serviceContextId}/users`** | Não existe na norma (só `current-service/users`). Foi para `token+bind` para não furar o bind-token | manter, ou tirar da tabela de rotas |
| A5 | **L1: como reconhecer o local associado** — risco do `Origin` forjado **DECIDIDO (Luís, 03/10)**; P1.3 **em aberto** | Hoje é o `Origin` em `origins:associated`. Um `Origin` forjado fora do navegador passa. E as apps de emissora são servidas pelo proxy do AoP, na origem do próprio AoP, enquanto o AoP grava em `origins:associated` a origem própria da app (alvo do proxy): elas não são reconhecidas como associadas | **Decidido: risco aceito do `Origin` forjado.** O critério continua sendo o `Origin`, sem mudança de comportamento. Ver abaixo. **Continua aberto: P1.3, origem própria por app**, pré-requisito do `enforce`: sem ela, as apps de emissora levam `X-TV30-Auth-Warn: 107` em `warn` e seriam bloqueadas em `enforce` (ver abaixo e `KNOWN-ISSUES.md`). Outra opção levantada antes: porta de origem (C.4.1.7) |
| A6 | **L2: identidade do serviço** | `serviceContextId` é constante para todo serviço; rotas `/tv3/<scid>/...` usam uma regra provisória | definir scid por serviço |
| A7 | **L3: TLS na borda (44643 em HTTP)** | Sem TLS não há 106 por protocolo para o não local, o `Server-SecureBaseURL` aponta para porta sem TLS e o remote-device devolve `ws://` em vez de `wss://` | decidir a PKI |
| A8 | **L4: 106 ao associado em `/authorize` e `/token`** | Implementado só no plugin e só em `enforce`; `/tv3/token` sem `Origin` passa | confirmar a regra |
| A9 | **L5: relógio do bind-token** | A norma usa o System Time Fragment; usamos o relógio do host | confirmar |
| A10 | **L7: liberar recursos ao revogar chave (C.4.4)** | Não implementado | prioridade |

Dependência fora do projeto: o Guaraná (Pedro) precisa obter o access token antes do `enforce`.

### Decididos pelo Luís em 03/10: o que foi feito

- **A1. Senha só na interface administrativa do Redis.** A conexão com o banco não mudou: continua sem senha e com a 6379 publicada. Os clientes (tv3ws, aop e plugin da borda), a carga inicial e o healthcheck seguem iguais. O redis-commander é um processo auxiliar do container `redis` (`infra/redis/entrypoint.sh`) e agora exige login com usuário e senha. Na versão instalada (0.9.0, fixada no `infra/redis/Dockerfile` desde 04/10, porque o login depende dos nomes de variável dessa versão), isso não é HTTP basic auth: a página de login abre sem credencial, e as rotas de dados respondem 401 sem o token que o login devolve. As variáveis são `REDIS_COMMANDER_USER` (padrão `admin`) e `REDIS_COMMANDER_PASSWORD` (padrão `tv30-redis-admin`), lidas do `.env` da raiz e repassadas por `infra/redis/docker-compose.yml`. A URL e a senha padrão estão no `README.md` da raiz, seção *Interface administrativa do Redis*. **A decisão não fecha o risco da linha A1:** quem alcança a 6379 continua podendo gravar `origins:associated` e `bind-context:*`.
- **A2. 101 no reuso de `clientid`.** O `GET /tv3/authorize` responde 404 `{"error":101}` quando o `clientid` já foi usado, para qualquer classe. Na norma:
  - Tabela C.3, erro 101: "if clientid has been used before" (p. 215; p. 233 do PDF);
  - C.6.1.4.4: "it is considered an error to try to use the API C.6.1.2 by passing a previously used clientid" (p. 219; p. 237 do PDF).

  Saiu do tv3ws o trecho que reemitia o refresh token ao cliente local já autorizado (`tv3ws/src/api/client-identification/controller.ts`). **A confirmar pelo Luís:** o `clientid` recusado pelo espectador (`clients:blocked`), que antes dava 102, também passou a dar 101. A nota da Tabela C.3 manda isso ("any attempt to authorize immediately returns error 101, without displaying the authorization dialog", p. 233 do PDF), mas a decisão de 03/10 falava só do `clientid` já usado. É uma leitura da D-L2 feita na implementação, e está no código e nos testes. A consequência é que quem perdeu o refresh token roda a autorização de novo, com `clientid` novo, e passa por nova autorização do espectador (C.6.1.4.5). O detalhe está em [APIs do tv3ws](apis-tv3ws.md).
- **A5. L1: risco aceito.** O associado continua reconhecido pelo `Origin` em `origins:associated`. Em `enforce`, um `Origin` forjado fora do navegador, presente nessa lista, passa como associado e dispensa access token e bind-token nas rotas que admitem o associado. O comentário `PENDENTE (Joel)` da L1 virou `DECIDIDO (Luis, 03/10): risco aceito` no plugin da borda (`infra/edgegateway/plugin/handler.go`), e o mesmo marcador entrou na classificação do cliente no tv3ws (`classifyClient`, em `tv3ws/src/api/client-identification/controller.ts`), que usa o mesmo critério.
  - **Continua aberto: P1.3, origem própria por app.** A decisão de 03/10 aceitou só o risco do `Origin` forjado. As apps de emissora servidas pelo proxy do AoP chegam à borda com o `Origin` do AoP, e o AoP grava em `origins:associated` a origem própria da app (`aop/src/core.js`, `registerAssociatedOrigin`). Medido em 04/10: com o serviço sintonizado, `origins:associated` tinha só `http://bcast:8081`, e a chamada da lista de perfis das páginas users-test e webmedia, reproduzida por curl com `Origin: http://localhost:8080`, recebeu `X-TV30-Auth-Warn: 107`. Em `enforce`, seriam bloqueadas. Sem o P1.3, o `enforce` barra os associados legítimos. Registrado em `KNOWN-ISSUES.md`; não resolvido.

## B. Descoberta SSDP (item 23, L6)

Medido em 02, 03 e 04/10, com o arranjo anterior à decisão da L6 (o tv3ws anunciava de dentro da bridge `ginga_net`) e com um anunciante descartável em modo host:
- o anúncio sai do container e chega à bridge do Docker, mas o kernel da VM do WSL não o repassa;
- com o anunciante em `network_mode: host`, ele chega ao próprio Windows;
- um celular na rede doméstica faz SSDP com o roteador, mas não acha o testbed (0 respostas).

**Decidido pelo Joel (informado pelo Luís em 04/10): a descoberta SSDP só precisa funcionar em Linux nativo.** Em Windows com WSL2, o anúncio não chega aos outros aparelhos da rede (medido). No Docker Desktop (Windows, Mac ou Linux), que também roda o Docker dentro de uma VM, espera-se o mesmo (não medido). Isso fica como limitação documentada, e não como defeito. Nesses ambientes, o cliente não local pode chegar ao receptor pelo IP, sem a etapa de descoberta (`http://<IP>:44642/manifest`).

| # | Ponto | Opções |
|---|---|---|
| B1 | **L6: onde roda o anunciante** — **DECIDIDO (informado pelo Luís em 04/10): opção B** | **Decidido:** um container só para o anúncio (`tv3ws-ssdp`), em modo host; a borda, o tv3ws e o resto continuam na bridge `ginga_net`. Ver abaixo. Opções levantadas antes: **A**, a borda anuncia em modo host (direção de 28/09; a borda é KrakenD, e o anúncio precisaria ser reescrito); **tv3ws em modo host**, o caminho mais curto, mas exigiria escutar só em `127.0.0.1` para não reabrir a porta direta. Contra a B pesava contrariar "a borda num container só" |
| B2 | **Host padrão do anúncio** (continua aberto) | Hoje é `localhost` (`SERVER_URL`), tanto no `LOCATION` do `tv3ws-ssdp` quanto no `/manifest` do tv3ws. Opções: cair no IP local quando for loopback, ou exigir `SSDP_ADVERTISE_HOST` |
| B3 | **Expor os cabeçalhos do `/manifest` ao navegador (CORS)** | expor `Server-*`/`Device-*` ou não |

A opção B, como as outras, não leva o anúncio à rede em Windows com WSL2 em NAT. Isso foi medido em 04/10: com o anunciante em modo host, o anúncio chega ao Windows, mas o celular na mesma rede doméstica recebe 0 respostas. O teste positivo precisa de Linux nativo com Docker Engine; o roteiro está em [ssdp-verificacao.md](ssdp-verificacao.md).

### B1 decidido (opção B): o que foi feito

Onde o anunciante roda é decisão de implementação deste testbed. A C.3.4 pede o anúncio e o GET no `LOCATION`, sem dizer quem anuncia.

- **Uma imagem, dois containers.** O `tv3ws-ssdp` usa a mesma imagem `tv30-tv3ws`, do mesmo build, e só troca o comando: `node dist/ssdp-announcer.js` (`tv3ws/src/ssdp-announcer.ts`). Esse processo só anuncia: não sobe Express, não conecta no Redis nem no MQTT e não abre porta TCP. Fica no perfil `ssdp` do compose da raiz, em `network_mode: host`, com `restart: unless-stopped`.
- **O `/manifest` continua no tv3ws,** na bridge, atrás da borda (`infra/edgegateway/routes.json`, `auth: none`), e responde sempre. O compose põe `SSDP_ENABLED: "false"` no tv3ws, que não anuncia e registra `[ssdp] anuncio desligado (SSDP_ENABLED=false)`. Fora do compose o padrão é ligado, para o tv3ws rodando sozinho no host (cenário 1 do [dev-host](dev-local.md)).
- **Mesmo host no anúncio e no `/manifest`.** Os dois saem do `tv3ws/src/ssdp-config.ts`. No compose, os dois containers recebem o mesmo `SERVER_URL` e leem o `SSDP_ADVERTISE_HOST` dos mesmos arquivos de ambiente: `tv3ws/.env` e depois o `.env` da raiz, que prevalece. A cadeia não mudou, porque a B2 segue aberta: `SSDP_ADVERTISE_HOST`, senão `SERVER_URL`, senão o IP local, com o aviso de loopback no boot.
- **Uma interface só.** O anunciante usa a interface IPv4 que tem o IP do host anunciado. Quando o host não é um IP da máquina (um nome, por exemplo), usa a interface da rota padrão e avisa no log. `SSDP_INTERFACE` força a escolha. O objetivo é acabar com as respostas duplicadas do teste 7 de [ssdp-verificacao.md](ssdp-verificacao.md), em que a biblioteca respondia por todas as interfaces da máquina.
- **Como ligar (só Linux nativo):** `COMPOSE_PROFILES=mqtt,linux,ssdp` e `SSDP_ADVERTISE_HOST=<IP da LAN>` no `.env` da raiz. Ver o `README.md`, seção *Descoberta SSDP (só Linux nativo)*. Sem o perfil, nada é anunciado.
- **Medido em 04/10, no WSL2:** 1 resposta por M-SEARCH, de um cliente no Windows, contra 32 respostas a cerca de 5 buscas no teste 7. O NOTIFY saiu só pela `eth0` da VM. Processo morto, porta UDP 1900 ocupada e interface inexistente derrubaram só o `tv3ws-ssdp`, e as APIs seguiram respondendo pela borda. Ver a seção *Medido em 04/10 — opção B* de [ssdp-verificacao.md](ssdp-verificacao.md).
- **Ainda não medido:** a descoberta por outro aparelho com o `tv3ws-ssdp` em Linux nativo (camada 3).

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
| C8 | **Sem rede, o SSDP derrubava o tv3ws inteiro** (regra morre-inteiro) — **RESOLVIDO pela opção B no deploy em container** | Num notebook offline, as APIs HTTP caíam junto. Com o anúncio no `tv3ws-ssdp` (B1), uma falha do SSDP derruba só esse container, que o Docker reinicia (`restart: unless-stopped`); as APIs do tv3ws ficam de pé. O isolamento foi medido em 04/10 com processo morto, UDP 1900 ocupada e interface inexistente (testes 19 a 21 de [ssdp-verificacao.md](ssdp-verificacao.md)); a máquina sem rede não foi reproduzida. **Continua no cenário dev-host:** o tv3ws rodando sozinho no host anuncia por padrão (`SSDP_ENABLED` ligado), e uma falha do SSDP ainda derruba as APIs junto. Nesse cenário, `SSDP_ENABLED=false` desliga o anúncio |

## D. Negociação de versão de API

> **Origem desta seção:** o documento de trabalho **`negociacao-de-versao-no-testbed.md`**, recebido em 04/10. Ele fica na raiz do TV30 e está **fora do controle de versão** (`.git/info/exclude`). As perguntas abaixo **não vêm das reuniões**: saem do confronto desse documento com o código atual. O próprio documento declara que é "documento de trabalho" e "não é decisão de projeto". As lacunas **L-04, L-05 e L-06** que ele cita são da numeração dele, não as L1–L8 deste testbed.

O que o documento propõe, em resumo:
- usar o mecanismo da C.3.6: `Accept-Version`, valendo 2.0 quando ausente, e `API-Version` em toda resposta, inclusive nas de erro;
- gravar a versão no recurso que sobrevive à requisição;
- manter um modelo interno único com uma projeção por versão;
- a borda negocia (passos 1 a 4) e o serviço monta a resposta;
- conjunto de versões `{2.0, 2.1, 3.0}`.

| # | Ponto | Hoje no código | Pergunta |
|---|---|---|---|
| D1 | **Qual conjunto de versões vale** | `SUPPORTED_VERSIONS = ['2.0', '2.1']` (`tv3ws/src/middleware/basic.ts:10`). A **2.1 de hoje** é o fluxo de remote-device por `handle`, a proposta do Luís ao Fórum (decisão de 21/09, item 15). No documento, a 2.1 é outra coisa: a "recomposição aditiva" da *Avaliação*, 6.3. Ele classifica a separação por `handle` (Issue #30) como 3.0, ou como 2.1 só se a rota antiga continuar servindo o formato 2.0, o que o código já faz | Adotar `{2.0, 2.1, 3.0}`? Se sim, a 2.1 atual muda de número ou é absorvida? |
| D2 | **Onde a versão é negociada** | O tv3ws faz tudo (`basic.ts:35-57`). O plugin da borda repete a lista `2.0`/`2.1` à mão (`infra/edgegateway/plugin/handler.go:432`), só para os erros dele | Passar os passos 1 a 4 para a borda, com um cabeçalho interno para o serviço, como o documento propõe (Seção 6)? |
| D3 | **Gravar a versão no recurso** (registro de dispositivo remoto, registro de notificação, ponto de entrada WebSocket) | Não grava. A forma da listagem é decidida a cada requisição (`tv3ws/src/api/multi-device/controller.ts:50`) | Gravar `registrationVersion` no `handle`, como na Seção 3 do documento? |
| D4 | **APIs de consulta de versão por API** (C.6.7.8 e C.6.7.9) | Não existem | Implementar como projeção do registro de versões (Seção 8.a do documento)? |
| D5 | **Escopo** | O documento lembra que o grupo de notificações do Anexo C e as unidades `rd-` (software do dispositivo remoto) estão fora do escopo (*Escopo e desenho*, Seção 9) | Trazer para o escopo, para exercitar a 3.0 (Seção 8.b e 8.c)? |

O documento cita outros que não estão no repositório: *Avaliação das propostas de alteração das APIs de dispositivo remoto*, *Escopo e desenho*, *Princípios e critérios*, *Unidades de implementação da TV 3.0 AoP* e *Lacunas sem decisão*. As referências a eles não foram conferidas.

**Divergência que não depende de decisão:** os erros 100 e 101 que o tv3ws devolve na negociação saem **sem** `API-Version`, porque o cabeçalho só é gravado depois da validação (`basic.ts:44-52`). A C.3.6.6 e o passo 6 do documento pedem `API-Version` em toda resposta. A borda já o põe nos erros dela, mas num erro 100 devolve `2.0` em vez da versão mais recente suportada. Ainda não foi corrigido.

## Correções e respostas para levar

- **O plugin Go antigo nunca validou nada.** Era proxy puro (`infra@60e527f:gateway-external/plugin/consent-validator.go`). O `tv30-auth` foi escrito do zero.
- **"Registrar para quem cada token foi emitido?"** A norma não manda registrar, mas o bloqueio de cliente (C.4.2.2) e o refresh token por cliente (Tabela C.4) só funcionam com esse vínculo, e o código já o guarda em `client:{id}`. O ponto A2 enfraquecia essa garantia; com o 101 no reuso de `clientid` (decidido pelo Luís em 03/10), o `/tv3/authorize` deixou de reemitir o refresh token.
- **O item 5 o Joel dispensou em 28/09.** Ele mesmo está avançando a parte de transporte (21/09).
- **O pareamento por PIN (`pm=kex`) nunca se completava.** O tv3ws respondia só `{challenge}`, e a Tabela C.3 (formato 3, p. 214; p. 232 do PDF) manda responder também `key`, a chave parcial ECDH do servidor (C.4.3.3, passo 1). Sem ela, o aplicativo não deriva a chave. O teste novo do não local achou a falha, e ela foi corrigida na integração de 04/10 (uma linha em `tv3ws/src/api/client-identification/controller.ts`). É correção de conformidade (Tabela C.3, formato 3; C.4.3.3, passo 1), não decisão de desenho. Já foi commitada e enviada (tv3ws `cc0d1a9`, 04/10) e **espera o aval do Luís**; para reverter, basta tirar o campo `key` da resposta do `kex`. O PIN continua publicado sem zeros à esquerda (por exemplo, `42`); a nota da C.4.3.3 fala em "a four-digit number".
