# Modelo de Dados — Redis

O Redis é o repositório compartilhado de estado de segurança do sistema.
Todos os serviços que precisam de ACL, consentimento ou dados de usuário consultam aqui.

## Visão geral das chaves

```mermaid
graph TD
    subgraph Redis

        subgraph ACL["ACL (por usuário)"]
            ACL1["acl:user1\nSET\n─────────────\naop/+/#\nsensor/room1/+\ntlm/lls/#"]
            ACL2["acl:user2\nSET\n─────────────\naop/+/#\nsensor/+/+"]
        end

        subgraph CONSENT["Consentimento (por usuário)"]
            CON1["user:user1:consent\nSET\n─────────────\nnetflix\ngloboplay\ncanaltech"]
            CON2["user:user2:consent\nSET\n─────────────\ngloboplay"]
        end

        subgraph PROFILE["Perfil (por usuário)"]
            PRF1["user:user1:profile\nHASH\n─────────────\nname: Ana\navatar: ana.png\nage_rating: 18\naccessibility: false"]
            PRF2["user:user2:profile\nHASH\n─────────────\nname: João\navatar: joao.png\nage_rating: 12\naccessibility: true"]
        end
    end
```

---

## Quem lê e quem escreve

```mermaid
graph LR
    subgraph Escritores
        PY["migrate_to_redis.py\n(boot do container Mosquitto)"]
        CCWS["CCWS\n(sessões e tokens)"]
    end

    subgraph Redis
        ACL["acl:<user_id>"]
        CONSENT["user:<user_id>:consent"]
        PROFILE["user:<user_id>:profile"]
        SESSION["sessões / refresh tokens\n(gerenciado pelo CCWS)"]
    end

    subgraph Leitores
        PLUGIN["Plugin C\n(Mosquitto)"]
        MW["Middleware Node.js\n(futuro)"]
    end

    PY -->|"SADD"| ACL
    PY -->|"SADD"| CONSENT
    PY -->|"HSET"| PROFILE
    CCWS -->|"SET / EXPIRE"| SESSION

    PLUGIN -->|"SMEMBERS acl:<id>"| ACL
    PLUGIN -->|"SISMEMBER consent <serviceId>"| CONSENT
    MW -.->|"consultará (futuro)"| ACL
    MW -.->|"consultará (futuro)"| CONSENT
    CCWS -->|"GET"| SESSION
```

---

## Origem dos dados: JSONs → Redis

```mermaid
flowchart LR
    subgraph Arquivos["Arquivos de config (container Mosquitto)"]
        ACL_JSON["/mosquitto/config/acl.json\n{ userId: [padrões] }"]
        USER_JSON["/mosquitto/config/userData.json\n{ users: [{ id, name, accessConsent, ... }] }"]
    end

    PY["migrate_to_redis.py"]

    subgraph Redis
        R_ACL["acl:<userId>\nSET de padrões MQTT"]
        R_CONSENT["user:<userId>:consent\nSET de serviceIds"]
        R_PROFILE["user:<userId>:profile\nHASH de atributos"]
    end

    ACL_JSON -->|"lê"| PY
    USER_JSON -->|"lê"| PY
    PY -->|"SADD"| R_ACL
    PY -->|"SADD"| R_CONSENT
    PY -->|"HSET"| R_PROFILE
```

---

## Comandos Redis usados pelo Plugin C

| Operação | Comando Redis | Chave | Descrição |
|---|---|---|---|
| Listar ACL do usuário | `SMEMBERS` | `acl:<user_id>` | Retorna todos os padrões de tópico permitidos |
| Verificar consentimento | `SISMEMBER` | `user:<user_id>:consent` | Checa se serviceId está no set do usuário |

---

## Exemplo de dados populados

```
# ACL do usuário "alice"
acl:alice → { "aop/+/#", "sensor/sala/+", "tlm/lls/#" }

# Consentimento da usuária "alice"
user:alice:consent → { "netflix", "globoplay" }

# Perfil da usuária "alice"
user:alice:profile → {
    name: "Alice",
    avatar: "alice.png",
    age_rating: "18",
    accessibility: "false",
    language: "pt-BR"
}
```

---

## Validação de acesso — exemplos

| Usuário | Tópico | ACL? | Consentimento? | Resultado |
|---|---|---|---|---|
| alice | `aop/netflix/currentApp` | ✅ `aop/+/#` | ✅ netflix | **Permitido** |
| alice | `aop/hbomax/currentApp` | ✅ `aop/+/#` | ❌ hbomax não consentido | **Negado** |
| alice | `sensor/sala/temperature` | ✅ `sensor/sala/+` | N/A | **Permitido** |
| alice | `sensor/quarto/temperature` | ❌ sem padrão | N/A | **Negado** |
| bob | `aop/netflix/currentApp` | ❌ sem ACL | N/A | **Negado** |
