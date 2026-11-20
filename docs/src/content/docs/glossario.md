---
title: Glossário
description: Os termos que aparecem em mais de uma página, cada um com a página que o trata.
---

Os termos que aparecem em mais de uma página. Seção citada sem outro nome é da ABNT NBR 25608; termo
sem seção é do testbed.

## As peças

| Termo | O que é |
|---|---|
| **AoP** | Na norma, a *TV 3.0 Application-oriented Platform*, a plataforma inteira do receptor (3.40). No testbed, `aop-shell` é o nome do componente da casca ([A AoP em 5 minutos](../aop-em-5-minutos/)) |
| **Casca** | O componente `aop-shell`: a página da TV, com as camadas, e as telas da plataforma ([aop-shell](../aop-shell/)) |
| **tv3ws** | O componente dos TV 3.0 WebServices (Anexo C) ([tv3ws](../tv3ws/)) |
| **bcast-sim** | A emissora simulada, fora do receptor ([Emissora simulada](../emissora-simulada/)) |
| **aop-cc** | O núcleo comum da plataforma: aquisição da sinalização, comporta, Application Context Cache e gerente de ciclo de vida ([Arquitetura](../arquitetura/)) |
| **Comporta** | A comporta de entrega de objeto do `aop-cc` (7.3, 10.1): serve o carrossel do serviço sintonizado e as aplicações de emissora, cada uma na origem dela ([aop-shell](../aop-shell/#aplicações-de-emissora)) |
| **Carrossel** | A transmissão cíclica dos arquivos de um serviço pela radiodifusão, simulada pelo relógio ([Emissora simulada](../emissora-simulada/)) |
| **Borda** | O container por onde entram as chamadas às APIs, que confere a credencial e a versão ([Borda e credenciais](../borda-credenciais/)) |
| **Broker** | O Mosquitto, a mensageria entre os componentes ([Mensageria (MQTT)](../mensageria/)) |
| **Redis** | O armazenamento único da plataforma ([Modelo de dados Redis](../modelo-redis/)) |
| **Componente** | Um serviço do testbed, ligado aos outros pela mensageria e pelo armazenamento ([Estender o testbed com um componente](../estender-com-componente/)) |

## Clientes e credenciais

| Termo | O que é |
|---|---|
| **Classes de cliente** | Local associado, local autônomo e não local (C.3.1) ([Chamar as APIs de outro aparelho](../apis-de-outro-aparelho/)) |
| **Origem associada** | A origem de uma aplicação de emissora em execução, pela qual a borda reconhece o cliente local associado ([Borda e credenciais](../borda-credenciais/)) |
| **Access token** | A credencial do cliente autônomo e do não local (C.4.1.2), emitida pelo `/tv3/authorize` e pelo `/tv3/token` |
| **Refresh token** | A credencial que o cliente guarda para pedir um novo access token sem nova autorização (C.6.1.3) |
| **`clientid`** | O identificador que o cliente gera e passa ao `/tv3/authorize` (C.6.1.4) |
| **Pareamento** | Como o cliente não local prova ao espectador que é ele, por QR code ou PIN (C.4.3) |
| **Bind-token** | A credencial assinada pela emissora que dá acesso às APIs de um contexto de serviço (C.4.1.3) |
| **Superfície interna e externa** | As duas portas das APIs: a 44642, em HTTP, fixa pela norma, e a 44643, em HTTPS (C.3.4) ([Borda e credenciais](../borda-credenciais/)) |
| **Formato de erro** | O status 404 com `{"error": <código>, "description": "..."}` e os códigos da Tabela C.1 (C.3.2) |
| **`Accept-Version` e `API-Version`** | A negociação da versão de cada API (C.3.6). Sem `Accept-Version`, vale a 2.0 ([tv3ws](../tv3ws/#versões)) |
| **`warn` e `enforce`** | Os modos da borda: `enforce` recusa a credencial inválida; `warn` só avisa ([Borda e credenciais](../borda-credenciais/)) |

## Serviço, sinalização e tela

| Termo | O que é |
|---|---|
| **Serviço DTV** | Um serviço de televisão digital; na TV 3.0, baseado em Bootstrap Application (3.37) |
| **Serviço corrente** | O serviço selecionado no receptor. Nas URLs, `current-service` vale por ele (C.3.5) |
| **`serviceContextId`** | O identificador do contexto de serviço nas URLs das APIs (C.3.5). No testbed, o `globalServiceId` do BAM do serviço |
| **LLS e SLS** | A sinalização de baixo nível, dos serviços do canal (7.2.2), e a de cada serviço (7.2.3) ([Emissora simulada](../emissora-simulada/)) |
| **BAMT e BAM** | A tabela da LLS com um *Bootstrap Application Manifest* por serviço (8.4.4) |
| **BALD** | A sinalização das aplicações de emissora de um serviço (10.1) |
| **Bootstrap Application** | A aplicação inicial de um serviço, também chamada de aplicação bootstrap (3.13) |
| **Aplicação de emissora** | A aplicação associada ao contexto de um serviço, na camada de gráficos (3.14) ([aop-shell](../aop-shell/#aplicações-de-emissora)) |
| **Camadas** | Vídeo, gráficos e interface da plataforma, com os avisos por cima ([A AoP em 5 minutos](../aop-em-5-minutos/#as-camadas-da-tela)) |
| **Pop-ups** | O sim ou não da autorização, o QR code e o PIN do pareamento e o aviso de atributos da emissora ([aop-shell](../aop-shell/#pop-ups)) |
| **Ponte de eventos** | O `/.tv30/bridge.js`, que a comporta põe em todo documento HTML da aplicação de emissora para dispará-lhe as teclas e os eventos do vídeo ([aop-shell](../aop-shell/#aplicações-de-emissora)) |
| **Dispositivo remoto** e ***handle*** | Um aparelho da rede registrado para executar parte de uma aplicação (C.6.15). O *handle* identifica o registro ([tv3ws](../tv3ws/)) |
| **SSDP** e **`/manifest`** | A descoberta do receptor na rede e o endereço que devolve as URLs das APIs (C.3.4) ([Descoberta na rede](../instalacao/#descoberta-na-rede)) |
| **Esquema na escrita** | O formato declarado de cada tópico e de cada família de chave, conferido na publicação e na gravação ([Mensageria (MQTT)](../mensageria/#esquema-das-mensagens), [Modelo de dados Redis](../modelo-redis/#o-esquema-na-escrita)) |
| **Visibilidade do perfil** | O conjunto de serviços para os quais um perfil é visível, em `user:{id}:consent`. Não é o consentimento do Privacy Manager (8.8) |
