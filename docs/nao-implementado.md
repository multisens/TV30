---
title: Não implementado
parent: Como funciona
nav_order: 9
---

# Não implementado

O que a ABNT NBR 25608 especifica e o testbed não implementa, e o que ele implementa de forma diferente da norma, com a seção de cada item. As seções citadas são as da ABNT NBR 25608; leia cada uma junto da seção de mesmo número do guia operacional (*TV 3.0 Operational Guidelines — Application Coding*). Problemas de operação, com sintoma e contorno, estão em [Known Issues](https://github.com/multisens/TV30/blob/main/KNOWN-ISSUES.md); decisões do projeto, em [Decisões]({{ site.baseurl }}/decisoes).

## Componentes da plataforma

| Seção | O que falta | Efeito no testbed |
|---|---|---|
| 8.8 | Privacy Manager (declaração de requisitos, registro e recibo de privacidade) | O item "Data Privacy settings" do menu do catálogo do AoP não tem função. A visibilidade do perfil por serviço (`user:{id}:consent`) não é o consentimento de 8.8 ([Modelo de dados Redis]({{ site.baseurl }}/modelo-redis)) |
| C.4.2.2 | Tela de gerenciamento do histórico de autorizações | O espectador não consulta, bloqueia nem desbloqueia clientes; o bloqueio só ocorre na recusa do pop-up ([APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws)) |
| C.4.4 | Liberação dos recursos compartilhados | Nada é liberado ao fechar a aplicação associada, ao remover a autorização nem ao revogar uma chave pela C.6.8.4 |
| C.6.3.1, Tabela C.8 | Fonte do `serviceName` e do `serviceId` (sem SLT na sinalização simulada) | A C.6.3.1 omite os dois campos, e o aviso da C.6.14.5 traz o id do serviço no lugar do nome |

## Comportamento das APIs implementadas

| Seção | Diferença | Onde |
|---|---|---|
| C.6.3.1, Tabela C.8 | O erro 302 não é emitido | `tv3ws/src/api/aop-communication/current-service/controller.ts` |
| C.4.1.3 | A validação do bind-token compara as datas com o relógio do host, sem tolerância, e não com o System Time Fragment | `infra/edgegateway/plugin/jwt.go` |
| C.6.14.1, C.6.14.2, C.6.14.5 | Com um serviço em uso, perfis em `users:index` e nenhum deles visível para o serviço (nenhum `user:{id}:consent` o contém), a C.6.14.1 responde 300, e não a lista vazia; a C.6.14.2 e a C.6.14.5, pelo alias `current-service`, respondem 300, e não 405. As tabelas das três reservam o 300 para a função DTV fora de uso | `tv3ws/src/api/user/service.ts` (`resolveActiveService`) |
| C.6.14.3, Tabela C.72 | Sem perfil corrente (entre a remoção do perfil corrente e a escolha de outro no seletor), a API responde 200 `{"id":""}`; a resposta para esse caso não está definida no testbed | `tv3ws/src/api/user/service.ts` (`getCurrentUser`) |
| C.6.15.5, Tabela C.80 | O cliente não local recebe 106, e não o 107 que a tabela lista para ele | `infra/edgegateway/routes.json` (`classes`) |
| C.6.15.5, Tabela C.80 | O ponto de entrada local sai em `ws://`, e não em `wss://` | `tv3ws/src/modules/remotedevice-manager/` |

## APIs da Tabela C.2 não implementadas

Das 66 APIs da Tabela C.2, o testbed implementa 20, listadas pela C.6.7.9 (`GET /tv3/api-info`) e em [APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws). Faltam:

| Seção | API id | Título da seção |
|---|---|---|
| C.6.2.2 | `tv3ws-register-notifications` | Registering event notifications |
| C.6.2.3 | `tv3ws-deregister-notifications` | Deregistering event notifications |
| C.6.3.2 | `tv3ws-list-service` | Obtaining the list of the available DTV services |
| C.6.3.3 | `tv3ws-select-service` | Selecting a DTV service |
| C.6.4.1 | `tv3ws-service-apps` | Obtaining the list of Broadcaster Applications available in a service |
| C.6.4.2 | `tv3ws-service-app-info` | Obtaining information about a Broadcaster Application |
| C.6.4.3 | `tv3ws-current-service-app-action` | Controlling a Broadcaster Application |
| C.6.4.4 | `tv3ws-current-service-app-property` | Obtaining properties defined by a Broadcaster Application |
| C.6.4.5 | `tv3ws-current-service-app-persistent-read` | Reading values persisted by Broadcaster Applications |
| C.6.4.6 | `tv3ws-current-service-app-persistent-write` | Writing values in the persistence area of Broadcaster Applications |
| C.6.4.8 | `tv3ws-current-service-app-nodes` | Listing the nodes of a running TV 3.0 Ginga-NCL application |
| C.6.4.9 | `tv3ws-current-service-app-node-operation` | Controlling a node of a running TV 3.0 Ginga-NCL application |
| C.6.4.10 | `tv3ws-current-service-app-edit` | Sending editing commands to a running TV 3.0 Ginga-NCL application |
| C.6.5.2 | `tv3ws-current-service-info-time` | Obtaining the date and time from the broadcaster |
| C.6.5.3 | `tv3ws-current-service-info-table` | Obtaining data from a ROUTE/DASH table/fragment |
| C.6.5.4 | `tv3ws-current-service-info-esg` | Obtaining data from the programming schedule |
| C.6.6.1 | `tv3ws-mediaplayer-list` | Obtaining available media players |
| C.6.6.2 | `tv3ws-mediaplayer-info` | Obtaining information about a specific media player |
| C.6.6.3 | `tv3ws-mediaplayer-operation` | Controlling a specific media player |
| C.6.6.5 | `tv3ws-current-service-stream` | Accessing a single media stream |
| C.6.6.6 | `tv3ws-current-service-streams` | Accessing multiple media streams |
| C.6.6.7 | `tv3ws-current-service-stream-release` | Releasing a media stream resource |
| C.6.6.10 | `tv3ws-current-service-stream-time` | Access stream time |
| C.6.7.1 | `tv3ws-platform-capabilities` | Querying the platform’s features, capabilities and resources |
| C.6.7.2 | `tv3ws-drm-list` | Querying DRM systems supported on the platform |
| C.6.7.3 | `tv3ws-target-app-register-url-filter` | Registering filters for target applications |
| C.6.7.4 | `tv3ws-target-app-list` | Listing the target applications installed on the receiver |
| C.6.7.5 | `tv3ws-target-app-operation` | Running a target application |
| C.6.7.6 | `tv3ws-target-app-deep-link` | Querying a deep link |
| C.6.7.7 | `tv3ws-ota-physical-layer` | Querying over-the-air physical layer information |
| C.6.9 | `tv3ws-geolocation-info` | API for geolocation — Obtaining the geolocation |
| C.6.10.1 | `tv3ws-closed-signing-signlanguage-info` | Obtaining information about a sign language window player |
| C.6.10.2 | `tv3ws-closed-signing-signlanguage-operation` | Operating on a sign language window player |
| C.6.11.1 | `tv3ws-current-service-cache-url` | Obtaining the Application Context Cache base directory URL |
| C.6.11.2 | `tv3ws-current-service-cache-download` | Caching broadband files |
| C.6.11.3 | `tv3ws-current-service-cache-dash-download` | Caching broadband DASH media segments files |
| C.6.11.4 | `tv3ws-current-service-cache-download-info` | Querying the status of files caching process |
| C.6.11.5 | `tv3ws-current-service-cache-usage` | Querying the cache usage status |
| C.6.11.6 | `tv3ws-current-service-cache-free` | Freeing up cache space |
| C.6.12.2 | `tv3ws-current-service-alternative-mpd-resolve` | Resolving an alternative MPD |
| C.6.12.4 | `tv3ws-current-service-alternative-mpd-configuration` | Setting the parameters of the Persistent Media Player for resolving alternative MPDs |
| C.6.12.5 | `tv3ws-current-service-alternative-mpd-player-info` | Obtaining Persistent Media Player parameterization for resolving alternative MPDs |
| C.6.13.1 | `tv3ws-audience-measurement-operation` | Controlling audience measurement data collection sessions |
| C.6.13.2 | `tv3ws-audience-measurement-info` | Obtaining status information of an audience measurement data collection session |
| C.6.17.2 | `tv3ws-current-service-nrt-filters-enable` | Enabling filters for local caching of files transmitted via NRT |
| C.6.17.3 | `tv3ws-current-service-nrt-filters-disable` | Disabling filters for local caching of files transmitted via NRT |
