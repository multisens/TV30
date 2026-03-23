# Fluxo de Controle de Acesso MQTT

## Objetivo

Implementar controle de acesso em duas camadas no plugin Mosquitto para validar permissões de usuários ao acessar tópicos do sistema AoP (Application Orchestration Platform).

## Contexto: Access Consent

O `accessConsent` é um mecanismo de conformidade com GDPR que controla quais serviços (broadcasters/canais) têm permissão para acessar dados do perfil do usuário.

**Estrutura de dados** (`userData.json`):
```json
{
  "id": "c3167a18-5dc5",
  "name": "Anonymous",
  "accessConsent": [
    "fe2481ea-5d44-4225-884b-504782636c3a",
    "0"
  ]
}
```

Cada usuário possui um array `accessConsent` contendo os IDs dos serviços autorizados.

## Fluxo de Validação em Duas Camadas

### Exemplo de Requisição

- **Client ID**: `user_c3167a18-5dc5` (ID do usuário)
- **Tópico**: `aop/fe2481ea-5d44-4225-884b-504782636c3a/apps`
- **Operação**: SUBSCRIBE ou PUBLISH

### Camada 1: Validação de ACL (Access Control List)

**Objetivo**: Verificar se o usuário tem permissão para acessar o padrão de tópico.

**Passos**:
1. Extrair o `userId` do Client ID
   - Client ID: `user_c3167a18-5dc5`
   - Extraído: `c3167a18-5dc5`

2. Buscar lista de ACL do usuário em arquivo de configuração
   - Exemplo de ACL:
   ```json
   {
     "acl": {
       "c3167a18-5dc5": ["aop/+/#", "sensor/room1/+"],
       "4b58baf8-65ce": ["aop/0/#"]
     }
   }
   ```

3. Verificar se o tópico solicitado corresponde a algum wildcard da lista
   - Tópico: `aop/fe2481ea-5d44-4225-884b-504782636c3a/apps`
   - Wildcard: `aop/+/#`
   - Resultado: **MATCH** ✅

4. Se não houver match → **NEGAR ACESSO** (RC:135)

### Camada 2: Validação de Consent

**Objetivo**: Verificar se o serviço (serviceId) extraído do tópico está autorizado no `accessConsent` do usuário.

**Passos**:
1. Extrair o `serviceId` do tópico
   - Tópico: `aop/fe2481ea-5d44-4225-884b-504782636c3a/apps`
   - Padrão: `aop/<serviceId>/<recurso>`
   - Extraído: `fe2481ea-5d44-4225-884b-504782636c3a`

2. Carregar dados do usuário do arquivo `userData.json`
   - Buscar usuário com `id` = `c3167a18-5dc5`

3. Verificar se `serviceId` está no array `accessConsent` do usuário
   ```json
   "accessConsent": [
     "fe2481ea-5d44-4225-884b-504782636c3a",
     "0"
   ]
   ```
   - Resultado: **ENCONTRADO** ✅

4. Se não estiver no array → **NEGAR ACESSO** (RC:135)

### Resultado Final

- **Camada 1**: ✅ Usuário tem ACL para `aop/+/#`
- **Camada 2**: ✅ ServiceId está no `accessConsent`
- **Decisão**: **PERMITIR ACESSO** (RC:0)

## Casos de Uso

### Caso 1: Acesso Permitido
- Client ID: `user_c3167a18-5dc5`
- Tópico: `aop/fe2481ea-5d44-4225-884b-504782636c3a/apps`
- ACL: `["aop/+/#"]`
- Consent: `["fe2481ea-5d44-4225-884b-504782636c3a"]`
- **Resultado**: PERMITIDO ✅

### Caso 2: Negado por ACL
- Client ID: `user_c3167a18-5dc5`
- Tópico: `sensor/room5/temperature`
- ACL: `["aop/+/#"]`
- **Resultado**: NEGADO (não passa na Camada 1) ❌

### Caso 3: Negado por Consent
- Client ID: `user_c3167a18-5dc5`
- Tópico: `aop/unauthorized-service-id/apps`
- ACL: `["aop/+/#"]` ✅
- Consent: `["fe2481ea-5d44-4225-884b-504782636c3a"]` (não contém `unauthorized-service-id`)
- **Resultado**: NEGADO (não passa na Camada 2) ❌

### Caso 4: Tópico sem serviceId
- Client ID: `user_c3167a18-5dc5`
- Tópico: `aop/users` (tópico global sem serviceId)
- ACL: `["aop/+/#"]`
- **Resultado**: PERMITIDO (apenas Camada 1) ✅

## Arquivos de Configuração

### `/mosquitto/config/acl.json`
```json
{
  "acl": {
    "c3167a18-5dc5": ["aop/+/#", "sensor/room1/+"],
    "4b58baf8-65ce": ["aop/0/#"],
    "c41e7a99-5dce": ["aop/#"]
  }
}
```

### `/mosquitto/config/userData.json`
```json
{
  "users": [
    {
      "id": "c3167a18-5dc5",
      "name": "Anonymous",
      "accessConsent": ["fe2481ea-5d44-4225-884b-504782636c3a", "0"]
    },
    {
      "id": "4b58baf8-65ce",
      "name": "Débora",
      "accessConsent": ["0"]
    }
  ]
}
```

## Implementação no Plugin

### Callback ACL Check
```c
static int callback_acl_check(int event, void *event_data, void *userdata) {
    struct mosquitto_evt_acl_check *ed = event_data;
    const char *client_id = mosquitto_client_id(ed->client);
    
    // Camada 1: Validar ACL
    if (!validate_acl(client_id, ed->topic)) {
        mosquitto_log_printf(MOSQ_LOG_INFO, "ACL denied for %s on topic %s", client_id, ed->topic);
        return MOSQ_ERR_ACL_DENIED;
    }
    
    // Camada 2: Validar Consent (apenas para tópicos aop/<serviceId>/*)
    if (strncmp(ed->topic, "aop/", 4) == 0) {
        char *service_id = extract_service_id(ed->topic);
        if (service_id && !validate_consent(client_id, service_id)) {
            mosquitto_log_printf(MOSQ_LOG_INFO, "Consent denied for %s on service %s", client_id, service_id);
            free(service_id);
            return MOSQ_ERR_ACL_DENIED;
        }
        free(service_id);
    }
    
    return MOSQ_ERR_SUCCESS;
}
```

## Logs Esperados

### Acesso Permitido
```
ACL check: user_c3167a18-5dc5 -> aop/fe2481ea-5d44-4225-884b-504782636c3a/apps
ACL validation: PASSED (matches aop/+/#)
Consent validation: PASSED (service in accessConsent)
Access GRANTED
```

### Acesso Negado (ACL)
```
ACL check: user_c3167a18-5dc5 -> sensor/room5/temperature
ACL validation: FAILED (no matching pattern)
Access DENIED (RC:135)
```

### Acesso Negado (Consent)
```
ACL check: user_c3167a18-5dc5 -> aop/unauthorized-service/apps
ACL validation: PASSED (matches aop/+/#)
Consent validation: FAILED (service not in accessConsent)
Access DENIED (RC:135)
```
