# Pipeline de Segurança HTTP

O KrakenD atua como API Gateway na frente do CCWS, delegando a validação de políticas
a um middleware Node.js externo. Essa arquitetura espelha no plano HTTP o que o
plugin C faz no plano MQTT.

## Fluxo de validação por requisição

```mermaid
flowchart TD
    CLIENT["Dispositivo externo\nGET/POST /tv3/..."]

    CLIENT --> KD["KrakenD :8090\nHTTP Server Plugin (Go)"]

    KD -->|"POST /validate\nrepassa headers originais\n(Authorization, etc.)"| MW

    subgraph MW["Middleware Node.js"]
        CHK_JWT{"JWT válido?"}
        CHK_FUTURE["... futuras validações ...\n(consentimento, rate limit, etc.)"]
        OK["200 OK"]
        FAIL["401 / 403 / 429"]

        CHK_JWT -->|"Não"| FAIL
        CHK_JWT -->|"Sim"| CHK_FUTURE
        CHK_FUTURE -->|"Aprovado"| OK
        CHK_FUTURE -->|"Negado"| FAIL
    end

    MW -->|"200 OK"| KD
    MW -->|"4xx"| KD

    KD -->|"Autorizado:\nencaminha requisição"| CCWS["CCWS :44642/:44643"]
    KD -->|"Negado:\nretorna erro ao cliente"| CLIENT
    CCWS -->|"resposta"| CLIENT
```

---

## Simetria com o plugin MQTT

```mermaid
graph LR
    subgraph MQTT["Plano MQTT"]
        MQ_PUB["Cliente MQTT\n(user_<id>)"]
        MQ_PLUGIN["Plugin C\nmosquitto_plugin.so"]
        MQ_BROKER["Broker Mosquitto\n(entrega a mensagem)"]
        MQ_PUB --> MQ_PLUGIN --> MQ_BROKER
    end

    subgraph HTTP["Plano HTTP"]
        HTTP_CLIENT["Dispositivo Externo\nHTTP/HTTPS"]
        HTTP_KD["KrakenD\n+ Plugin Go"]
        HTTP_MW["Middleware Node.js\n(/validate)"]
        HTTP_CCWS["CCWS\n(processa requisição)"]
        HTTP_CLIENT --> HTTP_KD --> HTTP_MW
        HTTP_MW --> HTTP_KD --> HTTP_CCWS
    end

    REDIS[("Redis\nACL · Consentimento\nPerfis")]

    MQ_PLUGIN -.->|"consulta"| REDIS
    HTTP_MW -.->|"consultará\n(futuro)"| REDIS
```

---

## Estrutura do HTTP Server Plugin (Go)

```mermaid
graph TD
    subgraph KrakenD["KrakenD Process"]
        REQ["Requisição recebida"]
        PLUGIN["HTTP Server Plugin\n(Go)"]
        ROUTER["Router KrakenD\n(encaminha ao backend)"]
    end

    subgraph MW["Middleware Node.js (serviço separado)"]
        VALIDATE["/validate\nPOST"]
        JWT["Valida JWT"]
        FUTURE["Futuras validações"]
    end

    REQ --> PLUGIN
    PLUGIN -->|"POST /validate\n+ headers"| VALIDATE
    VALIDATE --> JWT --> FUTURE
    FUTURE -->|"200 OK"| PLUGIN
    FUTURE -->|"4xx"| PLUGIN
    PLUGIN -->|"200: passa adiante"| ROUTER
    PLUGIN -->|"4xx: rejeita"| REQ
```

---

## Configuração KrakenD (modelo a implementar)

```json
{
  "$schema": "https://www.krakend.io/schema/v2.7/krakend.json",
  "version": 3,
  "name": "GingaDistrib API Gateway",
  "port": 8080,
  "extra_config": {
    "plugin/http-server": {
      "name": ["consent-validator"],
      "consent-validator": {
        "middleware_url": "http://middleware-node:3000"
      }
    }
  },
  "endpoints": [
    {
      "endpoint": "/tv3/{path}",
      "backend": [
        { "url_pattern": "/tv3/{path}", "host": ["http://ccws:44642"] }
      ]
    }
  ]
}
```

---

## Estado atual vs. planejado

```mermaid
timeline
    title Evolução do Pipeline HTTP
    Hoje
        : KrakenD sobe mas sem endpoints configurados
        : krakend.json vazio
    Próximo passo
        : Criar middleware Node.js (valida JWT)
        : Criar HTTP Server Plugin Go
        : Configurar endpoints no krakend.json apontando para CCWS
    Futuro
        : Middleware consulta Redis para validar consentimento
        : Rate limiting por usuário/serviço
        : Outras políticas conforme requisitos evoluem
```
