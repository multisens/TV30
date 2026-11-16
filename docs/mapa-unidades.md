---
title: Mapa de unidades
parent: Como funciona
nav_order: 10
---

# Mapa de unidades

As unidades de implementação da TV 3.0 AoP estão distribuídas sobre a arquitetura da plataforma. Cada cor
mostra o estado da unidade no testbed. As seções citadas são as da ABNT NBR 25608, e cada uma se lê junto
da seção de mesmo número do guia operacional.

{% include aop-architecture.html %}

## Como ler

| Elemento | Significado |
|---|---|
| Caixa com título | Bloco da arquitetura da TV 3.0 AoP. O sufixo do título (`aop-`, `tv3ws-`, `ginga-html5-`, `rd-`) é o namespace, que fica fora do rótulo das unidades da caixa |
| Unidade | Uma unidade de implementação. Clicada, mostra o identificador completo, a natureza, as seções da norma, o estado e uma nota |
| Unidade com filhos | Unidade cujas partes são unidades próprias, desenhadas abaixo dela |
| Grupo | Resumo de várias unidades. A barra tem um segmento por unidade, colorido pelo estado dela, e o número dá o total. Clicado, lista as unidades do grupo |
| Caixa tracejada cinza | Bloco da arquitetura que não é unidade de implementação: as Broadcaster Applications, que são conteúdo da emissora, e os demais tocadores de mídia, que a norma não especifica |

Os botões da legenda filtram o diagrama por estado. Para tirar o filtro, clique de novo no mesmo botão.

| Estado | Critério |
|---|---|
| Implementado | No escopo. O comportamento que a norma pede existe no código, mesmo que haja divergência pontual registrada na nota |
| Parcial | No escopo. Existe parte do comportamento, ou ele existe sem ser componente próprio. A nota diz o que falta |
| No escopo, não implementado | No escopo. Não há código |
| Fora do escopo | Fora do recorte do testbed |

## Como atualizar

O estado, a caixa e a nota de cada unidade ficam em `docs/_data/aop-units.yml`, com uma entrada por unidade.
As cores, os grupos e as contagens saem desse arquivo. Para mudar o estado de uma unidade, troque o valor
de `status`: `implemented`, `partial`, `absent` ou `out`.

| Campo | Conteúdo |
|---|---|
| `id` | Identificador da unidade |
| `nature`, `sections` | Natureza e seções da norma |
| `status` | Estado no testbed |
| `box` | Caixa do diagrama onde a unidade é desenhada |
| `parent` | Unidade sob a qual ela é desenhada |
| `group` | Grupo em que ela é contada |
| `note` | Nota curta, mostrada no painel |

O desenho das caixas fica em `docs/_includes/aop-architecture.html`, o estilo em
`docs/assets/css/aop-architecture.css` e a interação em `docs/assets/js/aop-architecture.js`.

## Referências

- **Unidades de implementação da TV 3.0 AoP** (projeto Testbed-TV3.0): identificadores, natureza, seções da
  norma e agrupamento das unidades
- **O testbed TV 3.0 AoP — escopo e desenho** (projeto Testbed-TV3.0): as 69 unidades no escopo
- **ABNT NBR 25608 — TV 3.0 — Application coding**, Seção 6, Figura 2 (*TV 3.0 Application-oriented
  Platform architecture*): o desenho de que o diagrama parte
- **Código do testbed** (submódulos `aop`, `bcast`, `tv3ws` e `infra`): o estado de cada unidade. Esta fonte
  **não é autoritativa**: ela descreve o que existe, e não o que deve existir
