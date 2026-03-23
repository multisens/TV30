# Documentação — GingaDistrib Infra

Diagramas de arquitetura da solução GingaDistrib.

## Índice

| Arquivo | Conteúdo |
|---|---|
| [01-visao-geral.md](01-visao-geral.md) | Visão geral do sistema e interação entre todos os serviços |
| [02-rede-docker.md](02-rede-docker.md) | Containers, portas expostas e rede compartilhada `ginga_net` |
| [03-pipeline-mqtt.md](03-pipeline-mqtt.md) | Pipeline de segurança do broker MQTT (plugin C) |
| [04-pipeline-http.md](04-pipeline-http.md) | Pipeline de segurança HTTP via KrakenD + middleware Node.js |
| [05-autenticacao.md](05-autenticacao.md) | Fluxos de autenticação TV 3.0 (local e remoto) |
| [06-modelo-redis.md](06-modelo-redis.md) | Modelo de dados do Redis (ACL, consentimento, perfis) |
