# Pipeline de Segurança MQTT

O plugin C intercepta toda mensagem publicada no broker antes de entregá-la aos assinantes.

## Fluxo de validação por mensagem

```mermaid
flowchart TD
    PUB["Cliente publica mensagem\nclient_id: user_<userId>\ntopic: <tópico>\npayload: <JSON>"]

    PUB --> CHK_SKIP{Tópico especial?}

    CHK_SKIP -->|"errors/*"| ALLOW_SKIP["Entrega direta\n(evita loop)"]
    CHK_SKIP -->|"PluginResponseTime*"| ALLOW_SKIP
    CHK_SKIP -->|"PublisherResponseTime*"| LATENCY["Mede latência\nPublica em PluginResponseTime<id>/iteration<n>"]
    CHK_SKIP -->|"outros"| CHK_FMT

    CHK_FMT{"client_id no formato\nuser_<userId>?"}
    CHK_FMT -->|"Não"| DENY["MOSQ_ERR_ACL_DENIED\n+ publica em errors/<client_id>"]
    CHK_FMT -->|"Sim"| ACL

    ACL["Layer 1 — ACL\nRedis: SMEMBERS acl:<user_id>\ncompara tópico com padrões\n(wildcards + e #)"]
    ACL -->|"Sem match"| DENY
    ACL -->|"Match"| CHK_AOP

    CHK_AOP{"Tópico começa\ncom aop/?"}
    CHK_AOP -->|"Não"| CHK_SENSOR
    CHK_AOP -->|"Sim"| CONSENT

    CONSENT["Layer 2 — Consentimento\nExtrai serviceId do tópico\naop/<serviceId>/...\nRedis: SISMEMBER user:<user_id>:consent <serviceId>"]
    CONSENT -->|"Não consentido"| DENY
    CONSENT -->|"Consentido"| CHK_SENSOR

    CHK_SENSOR{"Tópico começa\ncom sensor/?"}
    CHK_SENSOR -->|"Não"| ALLOW
    CHK_SENSOR -->|"Sim"| SCHEMA

    SCHEMA["Layer 3 — Schema\nCarrega schema de schemas.json\nValida payload JSON\n(JSON Schema Draft-07 em C)"]
    SCHEMA -->|"Schema não encontrado"| ALLOW
    SCHEMA -->|"Payload inválido"| DENY
    SCHEMA -->|"Payload válido"| ALLOW

    ALLOW["Mensagem entregue\naos assinantes"]
```

---

## Estrutura do Plugin C

```mermaid
graph TD
    subgraph mosquitto_plugin.so
        MAIN["mosquitto_plugin.c\nOrquestrador\ncallback_acl_check()"]
        AUTH["authorize.c\nACL + Consentimento\nvalidate_acl()\nvalidate_consent()\nauthorize_access()"]
        SCHEMA["schema_validator.c\nValidação JSON Schema\nvalidate_json_schema()"]
        LATENCY["response_time_tester.c\nTeste de latência\nhandle_response_time()"]
    end

    REDIS[("Redis\nhiredis")]
    SCHEMAS_FILE["/mosquitto/config/schemas.json"]

    MAIN --> AUTH
    MAIN --> SCHEMA
    MAIN --> LATENCY
    AUTH -->|"SMEMBERS / SISMEMBER"| REDIS
    SCHEMA -->|"lê schemas na inicialização"| SCHEMAS_FILE
```

---

## Validações de Schema suportadas

```mermaid
mindmap
  root((JSON Schema\nDraft-07))
    Tipos
      string
      number
      integer
      boolean
      object
      array
      null
    String
      minLength
      maxLength
      pattern (POSIX ERE)
    Número
      minimum
      maximum
      exclusiveMinimum
      exclusiveMaximum
      multipleOf
    Array
      minItems
      maxItems
      uniqueItems
      items (por elemento)
    Objeto
      required
      properties
      minProperties
      maxProperties
      additionalProperties
    Enumeração
      enum
      const
```

---

## Inicialização do container Mosquitto

```mermaid
sequenceDiagram
    participant DC as Docker
    participant PY as migrate_to_redis.py
    participant REDIS as Redis
    participant MQ as Mosquitto + Plugin

    DC->>PY: entrypoint.sh — aguarda Redis...
    PY->>REDIS: PING (polling até conectar)
    REDIS-->>PY: PONG
    PY->>REDIS: SADD acl:<user_id> <padrões> (para cada usuário em acl.json)
    PY->>REDIS: SADD user:<user_id>:consent <serviceIds> (userData.json)
    PY->>REDIS: HSET user:<user_id>:profile <atributos> (userData.json)
    PY-->>DC: migração concluída
    DC->>MQ: mosquitto -c /mosquitto/config/mosquitto.conf
    MQ->>MQ: carrega mosquitto_plugin.so
    MQ->>REDIS: conecta via hiredis
    MQ->>MQ: carrega schemas.json
    Note over MQ: Pronto para receber conexões
```
