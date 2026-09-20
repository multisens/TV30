---
title: "Plano: consolidação de containers"
nav_order: 10
---

# Plano de mudança — consolidação de containers

> **Status: fases 0–3 EXECUTADAS (20/09/2026)**; resta a fase 4 (renome
> R1 + faxina do Docker Hub). Decisões V1–V13 validadas pelo mantenedor
> em 19/09; overrides a alinhar com o orientador em §5.
>
> Resultado medido: **11 → 6 contínuos** (aop, bcast, ccws, mqtt-broker,
> redis, edgegateway) + 3 one-shots. Descoberta da execução: no arranjo
> antigo o plugin Go do gateway externo proxyava QUALQUER caminho ao
> CCWS (toda a API interna alcançável por fora) — o edgegateway fecha
> esse vazamento servindo só o que a tabela declara. Known-issue novo
> registrado: panic do roteador Gin em caminhos não-mapeados da
> superfície externa (conexão resetada em vez de 404; rotas declaradas
> intactas) — correção pertence ao trabalho futuro de formato de
> erro/106. Ver KNOWN-ISSUES.md.

## 1. Resumo

Hoje: **11 serviços contínuos + 4 one-shots**. Alvo: **6 contínuos +
3 one-shots** (o `redis-seed` é absorvido pelo container do Redis).
Nenhuma funcionalidade nova — realocação, com duas descontinuações
(middleware-interno; commander como serviço próprio).

## 2. Mapa da mudança (novo → antigos)

| Container NOVO | Absorve (antigos) | Portas | O que muda por dentro |
|---|---|---|---|
| **`edgegateway`** (V2) | ← `krakend-external` ← `krakend-internal` ← `validation-middleware` ← `swagger` | 44642 (fixa da norma), 44643 (HTTPS), 8085 (docs) | Quatro papéis num container sob **dumb-init + script** (V4): as duas superfícies de gateway (conjuntos de rota distintos — origem do erro 106), validação de accessToken como módulo interno e **um** Swagger UI com **dois** specs no dropdown (V6). Configs de gateway e OpenAPI gerados **no build** (V5) a partir da tabela única de rotas com metadados (M4) |
| **✝ descontinuado** (V3) | ← `middleware-internal` | — | Só gerava doc do gateway interno; com M4 não sobra papel |
| **`redis`** (V8+V9) | ← `redis-auth` (renomeado: era so o conteudo historico de autenticacao) ← `redis-seed` ← `redis-commander` | 6379 (convenção); UI do commander em porta dinâmica | Entrypoint: sobe o redis-server → roda a carga via **`redis-cli --pipe`** (elimina o pip-install da partida — resolve o defeito 1) → sobe o commander como processo auxiliar. `healthcheck` só fica saudável **após a carga** (substitui o `service_completed_successfully` que o mosquitto usa hoje). **Semântica registrada:** o redis é o processo principal; morte do commander NÃO derruba o banco (exceção consciente ao "morre inteiro", por ser ferramenta de debug) — ver §5 |
| **`tv3ws`** (renome R1, fase 4) | ← `ccws` | atrás da borda | Mesmo conteúdo; renome de pasta/repo/imagem/container. Porta direta fechada na fase 3 (V12) |
| **`aop`** | ← `aop` | 8080 (fixa — URL que humanos digitam) | Inalterado nesta frente |
| **`bcast`** | ← `bcast` | dinâmica (V10) | Inalterado nesta frente |
| **`mqtt-broker`** | ← `mqtt-broker` | 1883; **WS 9001 fixa** (o browser do AoP conecta em localhost:MQTT_WS_PORT conhecido antes da subida) | Separado do Redis (reunião) |

**One-shots restantes (3):** `sysctl-init` (motivo registrado no
compose), `preflight` (**muda**, V10: a 44642 ocupada vira **erro
bloqueante** com mensagem clara; demais checagens viram aviso),
`userfiles-seed`.

## 3. Portas — política (V10)

| Porta | Regime | Motivo |
|---|---|---|
| 44642 | **Fixa e bloqueante** no preflight | Fixada pela norma (C.3.4) |
| 44643 | Fixa | SecureBaseURL anunciada na descoberta |
| 9001 (MQTT WS) | Fixa | Browser do AoP conecta em valor conhecido pré-subida |
| 8080 (AoP) | Fixa | URL de uso humano |
| 6379 (Redis) | Fixa | Convenção |
| bcast, docs (8085), UI do commander | **Dinâmicas** | Sem contrato externo; quem precisa descobre via `docker compose ps` |

## 4. Fases de execução

| Fase | Conteúdo | Risco |
|---|---|---|
| 0 | Item 3 da lista (remover resíduo do controle de acesso do broker) + renomeações baratas R2/R5 | baixo |
| 1 | **M4**: tabela única de rotas → gera as 2 configs + os 2 OpenAPI no build (containers atuais passam a consumir os artefatos) | médio |
| 2 | **`edgegateway`**: imagem única (dumb-init) absorvendo os 4; morre o `middleware-internal`; preflight ajustado (44642 bloqueante, resto aviso/dinâmico) | médio-alto |
| 3 | **`redis` consolidado** (seed via `redis-cli --pipe` no entrypoint + commander embutido + healthcheck pós-carga) + **fechamento da porta direta do serviço** (V12, junto com a classificação P1) | médio |
| 4 | Renome **R1** (`ccws`→`tv3ws`) + **faxina do Docker Hub** (órfãos labmultisens: tv30-ccws, tv30-validation-middleware, tv30-middleware-internal; + namespace pessoal luiscrjr/tv30-*) — coordenar com a chegada dos alunos (V13) | alto |

**Critérios de aceite por fase:** `docker compose config` limpo; subida
em máquina virgem com um comando; smoke: AoP :8080, dropdown do Swagger
com 2 specs, rota externa exige token e interna não, `docker stop bcast`
limpa retidos (scripts/test-bcast-shutdown.sh); mosquitto só sobe após
redis saudável (pós-carga).

**Rollback:** imagens atuais permanecem no Hub até o fim da fase 4.

**Investigação prévia à fase 2 (V11):** verificar se a descoberta SSDP
(multicast) sai da rede de contêineres; o resultado decide se o
edgegateway roda na rede do host ou se o anunciante fica fora dele.

## 5. Registro de decisões (validação do mantenedor, 19/09/2026)

V1 sim · V2 `edgegateway` · V3 descontinuar · V4 dumb-init+script ·
V5 build · V6 1 UI/2 specs · V7 sem bind-token nesta etapa ·
**V8+V9 commander e seed DENTRO do container do redis** · V10 dinâmicas
com exceções (§3) · V11 investigar SSDP antes · V12 fase 3 · V13 fase 4.

**Overrides a alinhar com o orientador:**
1. *Seed dentro do redis* contraria a restrição da vacina "o job de
   inicialização continua sendo unidade própria" — justificativa: padrão
   idiomático (Postgres init), elimina o defeito 1 (dependência de rede
   na partida) e o healthcheck preserva a ordem de subida.
2. *Commander dentro do redis* cria segundo processo permanente no
   container — exceção ao "morre inteiro", registrada com a semântica:
   morte do commander não derruba o banco; morte do redis derruba tudo.

**Pendências externas:** lista de identificadores do orientador pode
renomear `edgegateway` e módulos na fase 4; detalhamento do Privacy
Manager (frente paralela, não bloqueia este plano).
