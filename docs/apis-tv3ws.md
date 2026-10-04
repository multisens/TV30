---
title: APIs do tv3ws
nav_order: 5
---

# APIs do tv3ws

O **tv3ws** é a implementação dos **Ginga CC WebServices** da ABNT NBR 25608 (Anexo C) neste testbed. O roteamento fica em `tv3ws/src/app.ts`.

O cliente não fala com o tv3ws diretamente. As portas 44652 e 44653 não são publicadas no host, e todo acesso passa pela **borda** (`edgegateway`):

- superfície interna: `http://localhost:44642`, porta fixa da C.3.4;
- superfície externa: `http://localhost:44643`, ainda em HTTP, porque o TLS na borda está pendente.

> Borda, mensageria e Redis são decisões de implementação do testbed, não da norma.

---

## Acesso, credenciais e versionamento

- **Rotas.** A tabela única `infra/edgegateway/routes.json` declara método, caminho e superfícies de cada rota. A borda não repassa ao tv3ws um caminho que não esteja declarado.
- **Credenciais.** Desde a semana de 28/09, quem valida é a borda, com o plugin `tv30-auth` (detalhes em `infra/edgegateway/plugin/README.md`). Ele confere o accessToken, o bind-token e a classe de cliente, conforme a política de cada rota.
  - No modo padrão, `AUTH_ENFORCE=warn`, a borda não bloqueia falha de credencial: registra `[tv30-auth] WARN` e devolve o cabeçalho `X-TV30-Auth-Warn`. Rota não declarada (100) é bloqueada nos dois modos.
  - Pela decisão de 28/09 (D1), o tv3ws só implementaria as APIs. **Estado corrente:** o tv3ws não exige credencial, mas ainda valida parte dela, nos dois modos. Responde 107 a um `Authorization` presente e inválido (`tv3ws/src/middleware/authorization.ts`) e 106 ao cliente não local que chega por HTTP (`validateClientProtocol` em `tv3ws/src/middleware/basic.ts`), o que acontece, por exemplo, com token `non-local` na 44642. A limpeza está pendente.
- **Erros.** Seguem o formato C.3.2: status 404 com corpo `{"error": <n>, "description": "..."}`.
- **CORS.** Quem aplica é a borda. O tv3ws **não** envia cabeçalhos CORS, para não duplicá-los (`tv3ws/src/middleware/basic.ts`). A borda põe `Access-Control-Allow-Origin: *` em toda resposta, também sem `Origin` na requisição (C.4.1.9.2). O preflight é respondido pelo módulo CORS do KrakenD; o `OPTIONS` sem preflight num caminho declarado recebe 200 com os três cabeçalhos da C.4.1.9.3.
- **`Accept-Version`.** Opcional (`basic.ts`).
  - Sem o cabeçalho, vale a versão 2.0.
  - São aceitas a 2.0 e a 2.1.
  - Valor malformado dá erro 101; versão fora desse conjunto dá erro 100.
  - Toda resposta traz `API-Version`.

---

## Endpoints declarados na borda

A coluna **bind-token** marca as APIs cujo campo "Security requirements" diz que o bind-token *shall* ser enviado. São 27 APIs na norma. Oito delas estão implementadas aqui, em 10 rotas: a norma aceita `current-service` no lugar de `<service-context-id>` (C.3.5).

| Método | Rota | Norma | bind-token |
|--------|------|-------|-----------|
| GET | `/health` | testbed (fora da norma) | |
| GET | `/manifest` | resposta ao `LOCATION` do anúncio SSDP | |
| GET | `/tv3/authorize` | C.6.1.2 | |
| GET | `/tv3/token` | C.6.1.3 | |
| GET | `/tv3/current-service` | C.6.3.1 | |
| POST | `/tv3/bind-context` | C.6.8.2 | |
| GET | `/tv3/bind-context` | C.6.8.3 | o próprio token é o objeto da API |
| DELETE | `/tv3/bind-context` | C.6.8.4 | |
| GET | `/tv3/current-service/apps/{appid}/files` | C.6.4.7 | shall |
| POST | `/tv3/current-service/users` | C.6.14.1 | shall |
| POST | `/tv3/{serviceContextId}/users` | C.6.14.1, em variante com `<scid>` do testbed (a norma define a rota com `current-service`; mesmo handler no tv3ws). PENDENTE: a rota fica ou sai | shall (a borda exige; scid fora de `current-service` e da constante dá 108, L2) |
| GET | `/tv3/current-service/users/{userid}` | C.6.14.2 | shall |
| GET | `/tv3/{serviceContextId}/users/{userid}` | C.6.14.2 | shall |
| GET | `/tv3/current-service/users/current-user` | C.6.14.3 | shall |
| POST | `/tv3/current-service/users/current-user` | C.6.14.4 | shall |
| POST | `/tv3/{serviceContextId}/users/{userid}` | C.6.14.5 | shall |
| GET | `/tv3/current-service/users/files` | C.6.14.6 | shall |
| POST | `/tv3/remote-device` | C.6.15.2 | |
| DELETE | `/tv3/remote-device/{handle}` | C.6.15.3 | |
| GET | `/tv3/remote-device/devices/{classId}` | C.6.15, ver nota | |
| GET | `/tv3/remote-device/device/{handle}` | C.6.15, ver nota | |
| DELETE | `/tv3/remote-device/device/{handle}` | C.6.15, ver nota | |
| GET | `/tv3/sensory-effect-renderers` | C.6.16.1 | |
| GET | `/tv3/sensory-effect-renderers/{rendererId}` | C.6.16.2 | |
| POST | `/tv3/sensory-effect-renderers/{rendererId}` | C.6.16.3 | shall |

**Notas:**

- As rotas `/manifest` e `bind-context` entram na tabela de rotas na semana de 28/09.
- A antiga `POST /tv3/users` (criação de perfil, fora da norma) **não existe mais**: saiu no commit `8d5949d` da infra. A criação de perfil passou a ser função do gestor de perfis da plataforma, que grava direto no armazenamento (`aop/src/modules/profile-manager/service.js`).
- Remote-device: os comentários de `tv3ws/src/api/multi-device/index.ts` citam C.6.15.5, C.6.15.6 e C.6.15.7. No PDF consultado (`docs/P_ABNTNBR25608_202X_en-US.pdf`), a seção C.6.15 só vai até a C.6.15.5. O fluxo por *handle* corresponde à versão 2.1, a proposta em discussão no Fórum (`basic.ts`).
- A contagem completa das 27 APIs *shall*, inclusive as ainda não implementadas, está em [`avaliacao-item9-credenciais.md`]({{ site.baseurl }}/avaliacao-item9-credenciais).

---

## Autorização de cliente (`/tv3/authorize` e `/tv3/token`)

**`clientid` repetido dá 101.** Decisão do Luís em 03/10 (A2 de [`decisoes-pendentes.md`]({{ site.baseurl }}/decisoes-pendentes)). O `GET /tv3/authorize` responde 404 `{"error":101}` quando o `clientid` já foi usado, para qualquer classe de cliente, com ou sem `pm`. Na norma:
- Tabela C.3, erro 101: "if clientid has been used before" (p. 215; p. 233 do PDF);
- C.6.1.4.4: no mesmo servidor, passar ao C.6.1.2 um `clientid` já usado é colisão e dá 101 (p. 219; p. 237 do PDF).

No tv3ws, "já usado" vale para dois casos, os dois sem pop-up (`checkAuthorization`, em `tv3ws/src/api/client-identification/controller.ts`):
- o cliente já autorizado, que tem o registro `client:{clientid}` no Redis, gravado quando o espectador o autoriza (`tv3ws/src/modules/auth-manager/manager.ts`);
- o cliente recusado pelo espectador, que fica em `clients:blocked`. A Tabela C.3 diz que, nesse caso, "any attempt to authorize immediately returns error 101, without displaying the authorization dialog". Até 03/10, o tv3ws respondia 102 aqui. Este segundo caso é conformidade com a nota da tabela, numa leitura da decisão de 03/10 feita na implementação, e **ainda espera a confirmação do Luís**.

O 101 não cobre o reuso **simultâneo**: um segundo `/tv3/authorize` com o mesmo `clientid` enquanto o pop-up do primeiro ainda está aberto abre outro pop-up (ver `KNOWN-ISSUES.md`).

O 102 fica só para a recusa no próprio pop-up ("If the user does not grant access"). Até 03/10, o cliente local já autorizado que chamava o `/tv3/authorize` de novo sem `pm` recebia o refresh token corrente, sem pop-up. Esse atalho saiu.

**O que o cliente faz** (C.6.1.4.5, p. 219; p. 237 do PDF):
1. Gera um `clientid` no formato UUID da RFC 9562 (C.6.1.4.3) e o guarda.
2. Chama o `/tv3/authorize` uma vez. O local autônomo recebe o refresh token direto. O não local recebe o `challenge` e obtém o primeiro access token e o refresh token no `/tv3/token`.
3. Guarda o refresh token. Nos acessos seguintes, chama `GET /tv3/token?clientid=<id>&refresh-token=<rt>`, sem voltar ao `/tv3/authorize`.
4. Guarda sempre o último refresh token recebido: o tv3ws troca o refresh token a cada `/tv3/token` (`rotateRefreshToken`, em `manager.ts`).

**Resposta do não local por método de pareamento** (Tabela C.3, formatos 2 e 3, p. 214; p. 232 do PDF):
- `pm=qrcode`: `{"challenge"}`. A chave vai no QR code que a TV mostra.
- `pm=kex`: `{"challenge","key"}`. O `key` é a chave parcial ECDH do servidor (ponto SEC 1 sem compressão, em base64 URL safe, C.4.3.4). O cliente deriva dela o segredo (C.4.3.3) e resolve o `challenge`. Até a integração de 04/10, o tv3ws respondia só `{"challenge"}` no `kex`, e o pareamento por PIN não se completava. A correção é de conformidade (Tabela C.3, formato 3; C.4.3.3, passo 1) e espera o aval do Luís. O PIN continua publicado sem zeros à esquerda (por exemplo, `42`).

**Quem perdeu o refresh token** precisa de `clientid` novo e de nova autorização do espectador, com novo pop-up. É o caso da recarga de página sem armazenamento persistente e do armazenamento apagado. O mesmo vale quando o `/tv3/token` responde 101 porque o refresh token não está associado ao cliente (C.6.1.4.5). Repetir o `clientid` antigo só dá 101.

**Verificado na stack em 04/10**, na integração e de novo na rodada de correção, com um script de curl que **não faz parte do repositório** (não há teste versionado que reproduza esta seção). Duas cargas seguidas de um cliente local autônomo:
- a primeira carga autoriza um `clientid` novo, com pop-up;
- a segunda usa só o `/tv3/token` com o refresh token guardado, sem pop-up, e a API responde 200;
- o refresh token já trocado dá 101;
- repetir o `clientid` no `/tv3/authorize` dá 101, sem pop-up;
- com o armazenamento apagado, um `clientid` novo abre o pop-up de novo.

Páginas do bcast que chamam a API (users-test e webmedia): o navegador não foi usado. O script baixou a página e reproduziu por curl a sequência de chamadas dela, com o serviço sintonizado pelo catálogo do AoP e o `Origin` do AoP (`http://localhost:8080`). As duas cargas deram respostas iguais entre si:
- users-test: a lista (`POST /tv3/current-service/users`) deu 404 `{"error":300}` nas duas cargas, e o `current-user` deu 200. O 300 vem de `resolveActiveService` (`tv3ws/src/api/user/service.ts`): nenhum perfil tem esse serviço em `user:{id}:consent` (visibilidade de perfil, C.6.14.1), e o tv3ws trata o serviço como não ativo;
- webmedia: a lista deu 200 com 5 perfis, e os detalhes e o `current-user` deram 200, nas duas cargas; o `remote-device` (`Accept-Version: 2.1`) também deu 200.

Nenhuma dessas chamadas usa o `/tv3/authorize`, então o resultado não depende da D-L2. Em `warn`, a chamada da lista levou `X-TV30-Auth-Warn: 107` nas duas páginas e nas duas cargas (o aviso das outras chamadas não foi registrado), porque o `Origin` do AoP não está em `origins:associated`, que tinha só `http://bcast:8081` (P1.3, ver `KNOWN-ISSUES.md`).

**Consumidores neste repositório.** Nenhum app do bcast nem o aop chama o `/tv3/authorize`. Os `clientId` fixos que aparecem neles (`bcast_svc`, `aop-core`, `rp-display`) são identificadores de cliente MQTT. O único consumidor é o `scripts/test-auth.sh`, que gera um `clientid` novo a cada execução.

---

## Filtragem de usuários (`POST /tv3/current-service/users`)

O corpo aceita expressões de filtro (`and`, `or` e expressão simples):

```json
{
  "or": [
    { "attribute": "parentalControl", "comparator": "eq", "value": "false" },
    {
      "and": [
        { "attribute": "parentalControl", "comparator": "eq", "value": "true" },
        { "attribute": "maxContentRating", "comparator": "gte", "value": "14" }
      ]
    }
  ]
}
```

Os comparadores são `eq`, `neq`, `lt`, `lte`, `gt` e `gte`.

Com um serviço corrente ativo (`session:current-service-id`), a listagem só traz usuários cujo `user:{id}:consent` contém esse serviço. Sem serviço ativo, a listagem traz **todos** (`tv3ws/src/api/user/service.ts`, `getUserList`).

Esse *consent* é a visibilidade do perfil por serviço guardada no Redis. Não é o consentimento da seção 8.8 da norma.

---

## Proxy puro na borda

Toda rota da borda é **proxy puro** (`output_encoding: "no-op"`, `infra/edgegateway/generate.js`). O status, os cabeçalhos e o corpo do tv3ws passam sem reinterpretação, o que inclui as respostas binárias (`GET .../users/files`) e as de texto.
