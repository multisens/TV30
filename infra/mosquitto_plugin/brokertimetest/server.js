const express = require('express');
const mqtt = require('mqtt');
const WebSocket = require('ws');
const path = require('path');

const app = express();
const server = require('http').createServer(app);
const wss = new WebSocket.Server({ server });

app.use(express.json());
app.use(express.static('public'));

function formatTimestamp() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  const hours = String(now.getHours()).padStart(2, '0');
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const seconds = String(now.getSeconds()).padStart(2, '0');
  const ms = String(now.getMilliseconds()).padStart(3, '0');
  return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}.${ms}`;
}

wss.on('connection', (ws) => {
  ws.on('message', async (message) => {
    const config = JSON.parse(message);
    
    if (config.action === 'start') {
      await runTest(config, ws);
    }
  });
});

async function runTest(config, ws) {
  const { host, port, clientPrefix, numClients, numIterations } = config;
  const brokerUrl = `mqtt://${host}:${port}`;
  
  ws.send(JSON.stringify({ type: 'log', message: `Conectando ao broker ${brokerUrl}...` }));

  const results = [];
  const clients = [];

  try {
    // Criar clientes
    for (let c = 1; c <= numClients; c++) {
      const clientId = `${clientPrefix}${c}`;
      const client = mqtt.connect(brokerUrl, { clientId });
      
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('Timeout')), 5000);
        client.on('connect', () => {
          clearTimeout(timeout);
          ws.send(JSON.stringify({ type: 'log', message: `✓ Cliente ${clientId} conectado` }));
          resolve();
        });
        client.on('error', (err) => {
          clearTimeout(timeout);
          reject(err);
        });
      });

      const responseTopic = `PluginResponseTime${clientId}/#`;
      client.subscribe(responseTopic);

      const sentTimestamps = {};

      client.on('message', (topic, message) => {
        const response = JSON.parse(message.toString());
        const iteration = response.iteration;
        const receiveTime = Date.now();
        
        if (sentTimestamps[iteration]) {
          const latency = receiveTime - sentTimestamps[iteration];
          results.push({ client: clientId, iteration, latency, diffTime: response.diffTime });
          ws.send(JSON.stringify({ 
            type: 'result', 
            data: { client: clientId, iteration, latency, diffTime: response.diffTime }
          }));
        }
      });

      clients.push({ client, clientId, sentTimestamps });
    }

    await new Promise(resolve => setTimeout(resolve, 500));

    // Publicar mensagens
    for (let i = 1; i <= numIterations; i++) {
      for (const { client, clientId, sentTimestamps } of clients) {
        const topic = `PublisherResponseTime${clientId}/iteration${i}`;
        const payload = JSON.stringify({
          testResponsetime: true,
          localtime: formatTimestamp(),
          id: clientId,
          iteration: i
        });
        
        sentTimestamps[i] = Date.now();
        client.publish(topic, payload);
      }
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    await new Promise(resolve => setTimeout(resolve, 2000));

    // Estatísticas
    if (results.length > 0) {
      const latencies = results.map(r => r.latency);
      const avg = latencies.reduce((a, b) => a + b, 0) / latencies.length;
      const min = Math.min(...latencies);
      const max = Math.max(...latencies);
      
      ws.send(JSON.stringify({ 
        type: 'stats', 
        data: { total: results.length, avg: avg.toFixed(2), min, max }
      }));
    }

    // Desconectar
    for (const { client } of clients) {
      client.end();
    }

    ws.send(JSON.stringify({ type: 'complete' }));

  } catch (error) {
    ws.send(JSON.stringify({ type: 'error', message: error.message }));
  }
}

const PORT = 3000;
server.listen(PORT, () => {
  console.log(`Servidor rodando em http://localhost:${PORT}`);
});
