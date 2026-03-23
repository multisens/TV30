# Contexto: Sistema de Validação MQTT com Schemas Dinâmicos

## Resumo do Projeto
Implementamos um sistema completo de validação de mensagens MQTT usando plugin Mosquitto com schemas dinâmicos baseados em arquivo JSON.

## Status Atual: ✅ COMPLETO E FUNCIONANDO

### Arquivos Implementados

#### 1. Plugin Principal
**Arquivo:** `/mnt/c/proj/mosquitto_plugin/validation_plugin.c`
- Plugin Mosquitto em C com validação JSON
- Carrega schemas do arquivo `/mosquitto/config/schemas.json` na inicialização
- Valida mensagens via callback `MOSQ_EVT_ACL_CHECK`
- Retorna reason code 135 "Not authorized" para mensagens inválidas
- Suporta validação de `max_value`, `min_value`, `required_fields`

#### 2. Configuração de Schemas
**Arquivo:** `/mnt/c/proj/mosquitto_plugin/schemas.json`
```json
{
  "sensor/room1/temperature": {
    "max_value": 30,
    "min_value": 0,
    "required_fields": ["value"]
  },
  "sensor/room2/humidity": {
    "max_value": 100,
    "min_value": 0,
    "required_fields": ["value", "unit"]
  }
}
```

#### 3. Configuração Mosquitto
**Arquivo:** `/mnt/c/proj/mosquitto_plugin/mosquitto.conf`
- Plugin carregado: `/usr/local/lib/validation_plugin.so`
- WebSocket habilitado na porta 9001
- Logs detalhados habilitados

#### 4. Interface Web (Opcional)
**Diretório:** `/mnt/c/proj/schema-admin/`
- `index.html` - Interface Bootstrap para gerenciar schemas
- `app.js` - Cliente MQTT.js para WebSocket
- `server.js` - Servidor Express.js
- `package.json` - Dependências Node.js

### Testes Realizados ✅

1. **Mensagem Válida**: `{"value": 25}` → RC:0 (Aceita)
2. **Valor Acima do Máximo**: `{"value": 50}` → RC:135 (Rejeitada)
3. **Campo Obrigatório Faltando**: `{"temp": 25}` → RC:135 (Rejeitada)
4. **Tópico Sem Schema**: Qualquer mensagem → RC:0 (Aceita)

### Logs de Validação
```
Value 50.00 exceeds maximum 30.00 in topic: sensor/room1/temperature
Validation FAILED for topic: sensor/room1/temperature
Denied PUBLISH from client (rc135)
```

## Evolução do Projeto

### Problema Inicial
- Plugin com validação hardcoded
- Reason code 153 "Payload format invalid" causava desconexão do cliente
- Necessidade de schemas dinâmicos

### Soluções Testadas
1. **RC:153** - Não funcionou (desconecta cliente)
2. **RC:135** - ✅ Funcionou perfeitamente
3. **Schemas via MQTT** - Callback de mensagem não funcionou
4. **Schemas via arquivo** - ✅ Solução final implementada

### Versões Mosquitto
- Inicial: 2.0.18
- Final: 2.0.22 (latest stable)

## Como Usar

### Em Containers (Docker)
```bash
cd /mnt/c/proj/mosquitto_plugin
docker compose down && docker compose up -d --build
```

### Em Ambiente Nativo
1. Editar `/path/to/schemas.json`
2. Reiniciar broker: `systemctl restart mosquitto`

### Adicionar Novos Schemas
Editar `schemas.json`:
```json
{
  "novo/topico": {
    "max_value": 100,
    "min_value": 0,
    "required_fields": ["campo1", "campo2"]
  }
}
```

## Arquitetura Técnica

### Fluxo de Validação
1. Cliente publica mensagem em tópico `sensor/*`
2. Plugin intercepta via `MOSQ_EVT_ACL_CHECK`
3. Verifica se existe schema para o tópico
4. Valida JSON contra schema (campos obrigatórios, min/max values)
5. Retorna `MOSQ_ERR_SUCCESS` (aceita) ou `MOSQ_ERR_ACL_DENIED` (rejeita com RC:135)

### Dependências
- `libmosquitto-dev`
- `libjson-c-dev`
- `gcc` para compilação

### Compilação
```bash
gcc -fPIC -shared -o validation_plugin.so validation_plugin.c -ljson-c -I/path/to/mosquitto/include
```

## Próximos Passos Possíveis

1. **Recarregamento Dinâmico**: Monitorar arquivo com `inotify`
2. **API REST**: Interface para editar schemas sem restart
3. **Validação Avançada**: Regex, tipos de dados, ranges
4. **Métricas**: Contadores de mensagens válidas/inválidas
5. **Multi-arquivo**: Schemas organizados por diretório

## Comandos de Teste

```bash
# Mensagem válida
mosquitto_pub -V 5 -q 1 -h localhost -p 1883 -t "sensor/room1/temperature" -m '{"value": 25}'

# Mensagem inválida (valor alto)
mosquitto_pub -V 5 -q 1 -h localhost -p 1883 -t "sensor/room1/temperature" -m '{"value": 50}'

# Verificar logs
docker logs mosquitto-plugin | tail -10
```

## Conclusão
Sistema completo e funcional para validação MQTT com schemas dinâmicos baseados em arquivo JSON. Solução robusta, flexível e pronta para produção.

---

## Sessão de Troubleshooting - 17/01/2026

### Problema Identificado
Usuário reportou erro ao publicar mensagem no tópico `sensor/room2/humidity`:
```json
{ "value": 101, "unit": "C" }
```

**Erro observado:**
```
Value 101.00 is greater than maximum 100.00
Validation FAILED for topic: sensor/room2/humidity
```

### Investigação

1. **Verificação do schema no host** (`schemas.json`):
   - Configurado com `"maximum": 200` para o campo `value`
   - Schema tecnicamente correto (embora semanticamente estranho para umidade)

2. **Verificação do schema no container**:
   ```bash
   docker exec mosquitto-plugin cat /mosquitto/config/schemas.json
   ```
   - Descoberto que o container tinha `"maximum": 100` (versão antiga)

3. **Análise do código** (`validation_plugin.c`):
   - Confirmado que o plugin **lê dinamicamente** do arquivo `/mosquitto/config/schemas.json`
   - Função `load_schemas_from_file()` carrega schemas na inicialização
   - **Não há validação hardcoded** - tudo vem do JSON

### Causa Raiz
O container estava usando uma versão antiga do arquivo `schemas.json` porque:
- O arquivo foi atualizado no host após a última build
- O container não foi reconstruído para copiar a nova versão
- Dockerfile copia o arquivo durante o build: `COPY schemas.json /mosquitto/config/`

### Solução Aplicada
```bash
cd /mnt/c/projcefet/mosquitto_plugin
docker compose down && docker compose up -d --build
```

### Resultado
✅ Mensagem com `value: 101` agora é aceita corretamente
✅ Confirmado que o plugin lê schemas dinamicamente do JSON
✅ Não há validação hardcoded no código

### Lições Aprendidas
1. **Sempre reconstruir containers** após modificar arquivos copiados no Dockerfile
2. **O plugin funciona corretamente** - lê schemas do arquivo JSON dinamicamente
3. **Para atualizar schemas em produção**: 
   - Editar `schemas.json` no host
   - Executar `docker compose up -d --build` para reconstruir
   - Ou montar o arquivo como volume para hot-reload (requer restart do broker)

### Schema Atual - sensor/room2/humidity
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "value": {
      "type": "number",
      "minimum": 0,
      "maximum": 200,
      "description": "Humidity percentage"
    },
    "unit": {
      "type": "string",
      "enum": ["C", "F"],
      "description": "Temperature unit: Celsius or Fahrenheit"
    },
    "sensor_id": {
      "type": "string",
      "pattern": "^[A-Z]{3}-[0-9]{4}$",
      "description": "Sensor ID in format XXX-0000"
    }
  },
  "required": ["value", "unit"],
  "additionalProperties": false
}
```

**Nota:** O schema aceita valores até 200 e unidades "C"/"F" por design, mesmo que semanticamente umidade não use essas unidades. Isso é intencional para testes de validação técnica.
