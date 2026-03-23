# Mosquitto Plugin

Plugin modular para Mosquitto MQTT Broker com funcionalidades de validação de schema JSON, teste de tempo de resposta e **controle de acesso em duas camadas**.

## Estrutura do Projeto

```
mosquitto_plugin/
├── plugin/
│   ├── src/
│   │   ├── mosquitto_plugin.c            # Orquestrador principal
│   │   ├── schema_validator.c            # Validador de JSON Schema
│   │   ├── response_time_tester.c        # Teste de latência
│   │   └── authorize.c                   # Controle de acesso (ACL + Consent)
│   ├── include/
│   │   ├── schema_validator.h
│   │   ├── response_time_tester.h
│   │   └── authorize.h
│   ├── config/
│   │   ├── mosquitto.conf                # Config do broker
│   │   ├── schemas.json                  # Schemas de validação
│   │   ├── acl.json                      # ACL (wildcards por usuário)
│   │   └── userData.json                 # Dados de usuários com accessConsent
│   ├── tests/
│   └── docs/
│       ├── access_control_flow.md        # Documentação do fluxo de autorização
│       ├── authorization_tests.md        # Guia de testes
│       └── mosquitto_plugin_context.md
├── infra/
│   ├── Dockerfile
│   └── docker-compose.yml
├── brokertimetest/                       # App web de testes
│   ├── server.js
│   ├── public/
│   └── package.json
└── README.md
```

## Funcionalidades

### 1. Validação de JSON Schema
- Valida mensagens MQTT contra schemas JSON
- Publica erros em `errors/<client_id>`
- Suporta tópicos `sensor/*`

### 2. Teste de Tempo de Resposta
- Mede latência do broker
- Tópicos: `PublisherResponseTime<id>/iteration<N>`
- Responde em: `PluginResponseTime<id>/iteration<N>`

### 3. Controle de Acesso em Duas Camadas ⭐ NOVO
- **Camada 1 (ACL)**: Valida se usuário tem permissão para acessar padrão de tópico (wildcards)
- **Camada 2 (Consent)**: Valida se serviceId está no accessConsent do usuário (GDPR compliance)
- Formato Client ID: `user_<userId>`
- Suporta wildcards MQTT (`+` e `#`)

## Instalação

```bash
docker compose up --build -d
```

## Uso

### Validação de Schema
```bash
mosquitto_pub -h localhost -t "sensor/room1/temperature" -m '{"value": 25}'
```

### Teste de Latência
```bash
# Interface web
cd brokertimetest
npm start
# Abra http://localhost:3000
```

### Controle de Acesso
```bash
# Acesso permitido (ACL + Consent OK)
mosquitto_sub -V 5 -i user_c3167a18-5dc5 -h localhost -p 1883 \
  -t "aop/fe2481ea-5d44-4225-884b-504782636c3a/apps"

# Ver guia completo de testes
cat plugin/docs/authorization_tests.md
```

## Desenvolvimento

### Adicionar Nova Funcionalidade

1. Criar `src/nova_funcionalidade.c` e `include/nova_funcionalidade.h`
2. Implementar a lógica
3. Importar no `src/mosquitto_plugin.c`
4. Atualizar `Dockerfile` para compilar
5. Rebuild: `docker compose up --build -d`

### Estrutura Modular

Cada funcionalidade é independente:
- **schema_validator**: Validação de dados JSON Schema
- **response_time_tester**: Métricas de performance
- **authorize**: Controle de acesso ACL + Consent (GDPR)
- **mosquitto_plugin**: Orquestração e callbacks

## Arquitetura

```
mosquitto_plugin.c (orquestrador)
├── Registra callbacks do Mosquitto
├── Roteia mensagens para módulos
│   ├── authorize → Valida ACL e Consent (duas camadas)
│   ├── schema_validator → Valida schemas
│   └── response_time_tester → Mede latência
└── Gerencia ciclo de vida do plugin
```

## Documentação

- **Fluxo de Controle de Acesso**: `plugin/docs/access_control_flow.md`
- **Guia de Testes**: `plugin/docs/authorization_tests.md`
- **Contexto do Plugin**: `plugin/docs/mosquitto_plugin_context.md`
