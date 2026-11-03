---
title: Decisões
parent: Como funciona
nav_order: 8
---

# Decisões

Decisões do projeto e o motivo de cada uma. O comportamento que delas resulta está descrito nas outras páginas, indicadas em cada linha; o que não está implementado ou diverge da norma está em [Não implementado]({{ site.baseurl }}/nao-implementado).

## Arquitetura e composição

Decisões do projeto, fora da norma, salvo onde a linha cita uma seção dela.

| Decisão | Motivo | Descrição |
|---|---|---|
| Docker, com um único caminho de deploy | Um só arranjo a manter; para desenvolvimento, a infraestrutura roda em containers e o módulo no host | [Desenvolvimento local]({{ site.baseurl }}/dev-local) |
| Monorepo com submódulos | Cada componente tem repositório e CI próprios | [Arquitetura]({{ site.baseurl }}/arquitetura) |
| MQTT para sinalização e eventos entre serviços | Desacoplamento entre os serviços; não é o único canal interno | [Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos) |
| Estado da plataforma num Redis único, com um dono por família de chave | Um armazenamento consultado por todos, em vez de uma cópia por serviço; os perfis são da plataforma (AoP), e o tv3ws só os lê | [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis) |
| Esquema nas escritas do Redis, por funções do próprio Redis, com auditoria | Evitar que um serviço grave dado fora do formato; a validação fica no armazenamento, com a escrita atômica | [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis) |
| Redis sem senha e sem ACL, publicado só em `127.0.0.1` | O Redis aplica o ACL de quem chama dentro da função: com o usuário `default` sem `@write`, a própria função recebe `ERR ACL failure in script`, e não há como liberar só a escrita pela função. A garantia fica no teste estático e na auditoria | [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis), [Known Issues](https://github.com/multisens/TV30/blob/main/KNOWN-ISSUES.md) |
| Broker sem controle de acesso a tópicos; o plugin só valida o esquema | O isolamento que a norma exige é por contexto de serviço DTV, na fronteira das APIs; entre componentes internos, não há isolamento | [Broker MQTT]({{ site.baseurl }}/broker-mqtt) |
| Aplicações de serviço como módulos do bcast | Um único container serve todas, sem duplicar MQTT e CORS | [Arquitetura]({{ site.baseurl }}/arquitetura) |
| Uma borda com duas superfícies, a interna (44642, HTTP) e a externa (44643, HTTPS) | A C.3.4 define as duas URLs base; concentrar a validação de credencial e a negociação de versão num ponto de entrada por superfície | [Borda e credenciais]({{ site.baseurl }}/borda-credenciais) |
| Credenciais validadas só na borda (plugin `tv30-auth`); o tv3ws não confere credencial | Um ponto de validação; as portas do tv3ws não são publicadas | [Borda e credenciais]({{ site.baseurl }}/borda-credenciais) |
| Certificado autoassinado do receptor, gerado na primeira subida, com o TLS da 44643 terminado na borda | A C.4.1.1 admite o certificado autoassinado pela plataforma; a borda precisa ler os cabeçalhos para validar a credencial | [Borda e credenciais]({{ site.baseurl }}/borda-credenciais) |
| Versões de API registradas no `routes.json` e negociadas na borda | Uma declaração só das versões de cada rota; a numeração 100.0 das extensões e o caminho interno `/v<X.Y>` são do testbed | [APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws) |
| `AUTH_ENFORCE=enforce` por padrão; `warn` como opção explícita | O `warn` serve a um cliente que ainda não obtém o token | [Borda e credenciais]({{ site.baseurl }}/borda-credenciais) |
| Um nome de host por aplicação de emissora | O local associado é reconhecido pelo `Origin` (a C.4.1.7 deixa o mecanismo de diferenciação à implementação); servidas na origem do AoP, as aplicações chegariam à borda com o `Origin` do AoP | [Arquitetura]({{ site.baseurl }}/arquitetura) |
| Anunciante SSDP nativo do host, fora do Docker | Dentro do Docker, o multicast só sai em Linux nativo; no macOS e no Windows o container fica na VM do Docker. O anunciante só divulga onde está o `/manifest`, sem estado nem credencial | [Descoberta SSDP]({{ site.baseurl }}/ssdp) |
| Avatar como nome de arquivo do diretório de miniaturas | A Tabela 7 pede *file path* no `avatar`. As telas do AoP embutem o arquivo, sem rota própria: uma rota do AoP entregaria o avatar sem a restrição da Tabela C.75, e um SVG aberto como documento na origem do AoP rodaria o script dele | [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis) |
| Id do perfil em UUID estrito | A Tabela 7 pede "UUID string" no `id` | [Modelo de dados Redis]({{ site.baseurl }}/modelo-redis) |
| Portas fixas só as necessárias | A norma fixa só a 44642 (C.3.4); as demais fixas são as que se digitam ou que o `/manifest` anuncia | [Instalação]({{ site.baseurl }}/instalacao) |
| Morre-inteiro, sem exceção | Peça caída não pode deixar o container aparentemente de pé; o `restart` o traz de volta | [Arquitetura]({{ site.baseurl }}/arquitetura) |
| Limite de 2 s da borda para o backend, salvo `timeout` próprio da rota | Um tv3ws travado ou fora do ar não deixa o cliente esperando | [Known Issues](https://github.com/multisens/TV30/blob/main/KNOWN-ISSUES.md) |

## Leituras da norma

| Ponto | Leitura do projeto | Descrição |
|---|---|---|
| Tabela C.74, "Restrictions": "it is necessary to notify the user that the application wants to change/add the attribute" | Aviso informativo depois de gravar, e não pedido de confirmação antes | [APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws) |
