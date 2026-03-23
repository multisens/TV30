# MQTT Broker Response Time Tester

Aplicação Node.js para testar o tempo de resposta do broker MQTT com múltiplos clientes paralelos.

## Instalação

```bash
npm install
```

## Uso

```bash
npm start
```

## Funcionalidades

- ✅ Configurar endereço e porta do broker MQTT
- ✅ Definir quantidade de clientes paralelos
- ✅ Personalizar prefixo dos nomes dos clientes
- ✅ Configurar número de iterações por cliente
- ✅ Medição automática de latência (tempo de ida e volta)
- ✅ Estatísticas: média, mínima e máxima
- ✅ Interface interativa via CLI

## Exemplo

```
Endereço do broker: localhost
Porta: 1883
Prefixo dos clientes: sensor
Quantidade de clientes: 10
Iterações por cliente: 4
```

Isso criará 10 clientes (sensor1, sensor2, ..., sensor10) que farão 4 iterações cada.

## Estrutura de Tópicos

- **Publisher**: `PublisherResponseTime<clientId>/iteration<N>`
- **Plugin Response**: `PluginResponseTime<clientId>/iteration<N>`

## Payload

```json
{
  "testResponsetime": true,
  "localtime": "2026-02-01 20:21:56.123",
  "id": "sensor1",
  "iteration": 1
}
```
