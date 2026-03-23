# Módulo de Autorização - Testes

## Arquivos Implementados

- `plugin/include/authorize.h` - Header do módulo
- `plugin/src/authorize.c` - Implementação da validação em duas camadas
- `plugin/config/acl.json` - Configuração de ACL (wildcards por usuário)
- `plugin/config/userData.json` - Dados de usuários com accessConsent
- `plugin/docs/access_control_flow.md` - Documentação do fluxo

## Build e Deploy

```bash
cd /mnt/c/projcefet/mosquitto_plugin
docker compose down && docker compose up -d --build
```

## Testes

### Teste 1: Acesso Permitido (ACL + Consent OK)

**Cenário**: Usuário Anonymous acessa serviço autorizado

```bash
# Client ID: user_c3167a18-5dc5
# Tópico: aop/fe2481ea-5d44-4225-884b-504782636c3a/apps
# ACL: ["aop/+/#"] ✅
# Consent: ["fe2481ea-5d44-4225-884b-504782636c3a"] ✅

mosquitto_sub -V 5 -i user_c3167a18-5dc5 -h localhost -p 1883 \
  -t "aop/fe2481ea-5d44-4225-884b-504782636c3a/apps"
```

**Resultado Esperado**: Conexão aceita, logs mostram:
```
ACL matched: c3167a18-5dc5 -> aop/fe2481ea-5d44-4225-884b-504782636c3a/apps (pattern: aop/+/#)
Consent granted: c3167a18-5dc5 -> service fe2481ea-5d44-4225-884b-504782636c3a
```

### Teste 2: Negado por ACL

**Cenário**: Usuário tenta acessar tópico fora da ACL

```bash
# Client ID: user_c3167a18-5dc5
# Tópico: sensor/room5/temperature
# ACL: ["aop/+/#", "sensor/room1/+"] ❌ (não match)

mosquitto_sub -V 5 -i user_c3167a18-5dc5 -h localhost -p 1883 \
  -t "sensor/room5/temperature"
```

**Resultado Esperado**: Conexão negada (RC:135), logs mostram:
```
ACL denied: c3167a18-5dc5 -> sensor/room5/temperature (no matching pattern)
Authorization denied: user_c3167a18-5dc5 -> sensor/room5/temperature
```

### Teste 3: Negado por Consent

**Cenário**: Usuário acessa serviço não autorizado

```bash
# Client ID: user_c3167a18-5dc5
# Tópico: aop/unauthorized-service-id/apps
# ACL: ["aop/+/#"] ✅
# Consent: ["fe2481ea-5d44-4225-884b-504782636c3a", "0"] ❌ (não contém unauthorized-service-id)

mosquitto_sub -V 5 -i user_c3167a18-5dc5 -h localhost -p 1883 \
  -t "aop/unauthorized-service-id/apps"
```

**Resultado Esperado**: Conexão negada (RC:135), logs mostram:
```
ACL matched: c3167a18-5dc5 -> aop/unauthorized-service-id/apps (pattern: aop/+/#)
Consent denied: c3167a18-5dc5 -> service unauthorized-service-id (not in accessConsent)
Authorization denied: user_c3167a18-5dc5 -> aop/unauthorized-service-id/apps
```

### Teste 4: Tópico Global (sem serviceId)

**Cenário**: Acesso a tópico que não requer consent

```bash
# Client ID: user_c3167a18-5dc5
# Tópico: aop/users (tópico global)
# ACL: ["aop/+/#"] ✅
# Consent: Não aplicável (tópico não tem serviceId)

mosquitto_sub -V 5 -i user_c3167a18-5dc5 -h localhost -p 1883 \
  -t "aop/users"
```

**Resultado Esperado**: Conexão aceita, logs mostram:
```
ACL matched: c3167a18-5dc5 -> aop/users (pattern: aop/+/#)
```

### Teste 5: Client ID Inválido

**Cenário**: Client ID sem prefixo "user_"

```bash
# Client ID: invalid_client
# Tópico: aop/0/apps

mosquitto_sub -V 5 -i invalid_client -h localhost -p 1883 \
  -t "aop/0/apps"
```

**Resultado Esperado**: Conexão negada, logs mostram:
```
Invalid client_id format: invalid_client
Authorization denied: invalid_client -> aop/0/apps
```

### Teste 6: Usuário com ACL Ampla

**Cenário**: Usuário user_1759609131451 tem ACL ["aop/#", "sensor/#"]

```bash
# Deve permitir qualquer tópico aop/* e sensor/*
mosquitto_sub -V 5 -i user_user_1759609131451 -h localhost -p 1883 \
  -t "aop/0/apps"

mosquitto_sub -V 5 -i user_user_1759609131451 -h localhost -p 1883 \
  -t "sensor/room1/temperature"
```

**Resultado Esperado**: Ambos aceitos (mas consent ainda será validado para tópicos aop)

## Verificar Logs

```bash
docker logs mosquitto-plugin -f
```

## Estrutura de Dados

### acl.json
```json
{
  "acl": {
    "c3167a18-5dc5": ["aop/+/#", "sensor/room1/+"],
    "4b58baf8-65ce": ["aop/0/#"],
    "c41e7a99-5dce": ["aop/#"]
  }
}
```

### userData.json (excerpt)
```json
{
  "users": [
    {
      "id": "c3167a18-5dc5",
      "name": "Anonymous",
      "accessConsent": ["fe2481ea-5d44-4225-884b-504782636c3a", "0"]
    }
  ]
}
```

## Wildcards MQTT

- `+` - Match de um único nível (ex: `sensor/+/temperature` match `sensor/room1/temperature`)
- `#` - Match de múltiplos níveis (ex: `aop/#` match `aop/1/apps` e `aop/1/2/path`)

## Troubleshooting

### Erro: "Failed to load ACL file"
- Verificar se `/mosquitto/config/acl.json` existe no container
- Verificar sintaxe JSON

### Erro: "Failed to load user data file"
- Verificar se `/mosquitto/config/userData.json` existe no container
- Verificar sintaxe JSON

### Todos os acessos negados
- Verificar formato do client_id (deve ser `user_<userId>`)
- Verificar se userId existe no acl.json
- Verificar logs para identificar qual camada está falhando
