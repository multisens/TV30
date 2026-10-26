// EXAMPLE component of the template (see README.md). Only the node standard
// library, to start without npm install; a real component uses mqtt and
// ioredis. Redis and MQTT by service name: answers <EXEMPLO_TOPICO>/ping on
// <EXEMPLO_TOPICO>/pong with the value of EXEMPLO_CHAVE in Redis; GET /health
// opens only with both connected; without one of them, exits with 1 and the
// restart brings it back.
'use strict';
const net = require('net');
const http = require('http');
const crypto = require('crypto');

const NOME = process.env.COMPONENTE_NOME || 'meu-componente';
const MQTT_HOST = process.env.MQTT_HOST || 'mosquitto';
const MQTT_PORT = Number(process.env.MQTT_PORT || 1883);
const REDIS_HOST = process.env.REDIS_HOST || 'redis';
const REDIS_PORT = Number(process.env.REDIS_PORT || 6379);
const PORT = Number(process.env.PORT || 8090);
const TOPICO = process.env.EXEMPLO_TOPICO || `tv30/${NOME}/exemplo`;
const CHAVE = process.env.EXEMPLO_CHAVE || `tv30:${NOME}:exemplo`;
// clientId with a random suffix: the broker drops the previous connection
// when another one arrives with the same id, so the example can run on the
// host and in a container at the same time.
const CLIENT_ID = `${NOME}-${crypto.randomBytes(4).toString('hex')}`;
// Seconds.
const KEEPALIVE = 30;

const log = (msg) => console.log(`[${NOME}] ${msg}`);
function morre(motivo) {
  console.error(`[${NOME}] FATAL: ${motivo}; saindo (morre-inteiro: o restart do Docker religa)`);
  process.exit(1);
}

// Redis (RESP2)
function respEncode(args) {
  const partes = [Buffer.from(`*${args.length}\r\n`)];
  for (const a of args) {
    const b = Buffer.from(String(a), 'utf8');
    partes.push(Buffer.from(`$${b.length}\r\n`), b, Buffer.from('\r\n'));
  }
  return Buffer.concat(partes);
}

// One reply from buf[i]: `{valor, erro, fim}`, or null if it has not fully
// arrived.
function respParse(buf, i) {
  if (i >= buf.length) return null;
  const crlf = buf.indexOf('\r\n', i);
  if (crlf < 0) return null;
  const tipo = String.fromCharCode(buf[i]);
  const linha = buf.toString('utf8', i + 1, crlf);
  const fim = crlf + 2;
  switch (tipo) {
    case '+': return { valor: linha, fim };
    case '-': return { valor: linha, erro: true, fim };
    case ':': return { valor: Number(linha), fim };
    case '$': {
      const n = Number(linha);
      if (n < 0) return { valor: null, fim };
      if (buf.length < fim + n + 2) return null;
      return { valor: buf.toString('utf8', fim, fim + n), fim: fim + n + 2 };
    }
    case '*': {
      const n = Number(linha);
      if (n < 0) return { valor: null, fim };
      const itens = [];
      let p = fim;
      for (let k = 0; k < n; k++) {
        const r = respParse(buf, p);
        if (!r) return null;
        itens.push(r.valor);
        p = r.fim;
      }
      return { valor: itens, fim: p };
    }
    default: throw new Error(`resposta RESP inesperada (tipo '${tipo}')`);
  }
}

// Connects and returns redis(...args), a Promise of the reply (one command
// at a time in the queue, as RESP keeps the order).
function redisConnect() {
  return new Promise((resolve, reject) => {
    const sock = net.connect(REDIS_PORT, REDIS_HOST);
    const fila = [];
    let buf = Buffer.alloc(0);
    let conectado = false;
    const redis = (...args) => new Promise((res, rej) => {
      fila.push({ res, rej });
      sock.write(respEncode(args));
    });
    sock.on('connect', () => { conectado = true; resolve(redis); });
    sock.on('error', (e) => (conectado ? morre(`redis ${REDIS_HOST}:${REDIS_PORT}: ${e.message}`) : reject(e)));
    sock.on('close', () => { if (conectado) morre(`conexao com o redis ${REDIS_HOST}:${REDIS_PORT} fechou`); });
    sock.on('data', (d) => {
      buf = Buffer.concat([buf, d]);
      for (;;) {
        const r = respParse(buf, 0);
        if (!r) break;
        buf = buf.subarray(r.fim);
        const f = fila.shift();
        if (f) (r.erro ? f.rej(new Error(r.valor)) : f.res(r.valor));
      }
    });
  });
}

// MQTT 3.1.1 (QoS 0)
function remLen(n) {
  const out = [];
  do {
    let b = n % 128;
    n = Math.floor(n / 128);
    if (n > 0) b |= 128;
    out.push(b);
  } while (n > 0);
  return Buffer.from(out);
}
function mqttStr(s) {
  const b = Buffer.from(s, 'utf8');
  const l = Buffer.alloc(2);
  l.writeUInt16BE(b.length);
  return Buffer.concat([l, b]);
}
const pacote = (cabecalho, corpo) => Buffer.concat([Buffer.from([cabecalho]), remLen(corpo.length), corpo]);

// Connects (CONNECT/CONNACK) and returns {publish, subscribe};
// onMessage(topic, text) gets each PUBLISH.
function mqttConnect(onMessage) {
  return new Promise((resolve, reject) => {
    const sock = net.connect(MQTT_PORT, MQTT_HOST);
    let buf = Buffer.alloc(0);
    let conectado = false;
    let ultimo = Date.now();
    const publish = (topico, texto) => sock.write(pacote(0x30, Buffer.concat([mqttStr(topico), Buffer.from(texto, 'utf8')])));
    const subscribe = (filtro) => sock.write(pacote(0x82, Buffer.concat([Buffer.from([0, 1]), mqttStr(filtro), Buffer.from([0])])));
    sock.on('connect', () => {
      // "MQTT", level 4 (3.1.1), clean session, keepalive.
      const vh = Buffer.concat([mqttStr('MQTT'), Buffer.from([4, 0x02, KEEPALIVE >> 8, KEEPALIVE & 255])]);
      sock.write(pacote(0x10, Buffer.concat([vh, mqttStr(CLIENT_ID)])));
    });
    sock.on('error', (e) => (conectado ? morre(`mqtt ${MQTT_HOST}:${MQTT_PORT}: ${e.message}`) : reject(e)));
    sock.on('close', () => {
      if (conectado) morre(`conexao com o broker ${MQTT_HOST}:${MQTT_PORT} fechou`);
      else reject(new Error('conexao fechada antes do CONNACK'));
    });
    sock.on('data', (d) => {
      ultimo = Date.now();
      buf = Buffer.concat([buf, d]);
      for (;;) {
        // Fixed header: type and flags, then the remaining length (1 to 4
        // bytes).
        let i = 1, len = 0, mult = 1, b;
        do {
          if (i >= buf.length) return;
          b = buf[i++];
          len += (b & 127) * mult;
          mult *= 128;
        } while (b & 128);
        if (buf.length < i + len) return;
        const tipo = buf[0] >> 4, flags = buf[0] & 15, corpo = buf.subarray(i, i + len);
        buf = buf.subarray(i + len);
        if (tipo === 2) {
          // CONNACK
          if (corpo[1] !== 0) { reject(new Error(`CONNACK recusado (codigo ${corpo[1]})`)); sock.destroy(); return; }
          conectado = true;
          resolve({ publish, subscribe });
        } else if (tipo === 3) {
          // PUBLISH received
          const tl = corpo.readUInt16BE(0);
          const qos = (flags >> 1) & 3;
          const ini = 2 + tl + (qos > 0 ? 2 : 0);
          onMessage(corpo.toString('utf8', 2, 2 + tl), corpo.toString('utf8', ini));
        }
        // SUBACK and PINGRESP only count as a sign of life (ultimo).
      }
    });
    // PINGREQ at half the keepalive; a broker silent for 1.5 keepalive exits
    // the process.
    setInterval(() => {
      if (!conectado) return;
      if (Date.now() - ultimo > KEEPALIVE * 1500) morre(`broker ${MQTT_HOST}:${MQTT_PORT} sem resposta (keepalive)`);
      sock.write(Buffer.from([0xc0, 0]));
    }, KEEPALIVE * 500);
  });
}

async function main() {
  let redis;
  try {
    redis = await redisConnect();
    log(`redis ${REDIS_HOST}:${REDIS_PORT} PING -> ${await redis('PING')}`);
    log(`redis GET ${CHAVE} -> ${JSON.stringify(await redis('GET', CHAVE))}`);
  } catch (e) {
    morre(`sem redis em ${REDIS_HOST}:${REDIS_PORT} (${e.message})`);
  }
  setInterval(() => redis('PING').catch((e) => morre(`PING no redis falhou (${e.message})`)), 15000);

  let mqtt;
  try {
    mqtt = await mqttConnect(async (topico, texto) => {
      if (topico !== `${TOPICO}/ping`) return;
      let valor;
      try { valor = await redis('GET', CHAVE); } catch (e) { morre(`GET ${CHAVE} falhou (${e.message})`); }
      mqtt.publish(`${TOPICO}/pong`, JSON.stringify({ componente: NOME, ping: texto, chave: CHAVE, valor }));
      log(`ping ${JSON.stringify(texto)} -> pong com ${CHAVE}=${JSON.stringify(valor)}`);
    });
    mqtt.subscribe(`${TOPICO}/ping`);
    log(`mqtt ${MQTT_HOST}:${MQTT_PORT} conectado (clientId ${CLIENT_ID}); assinando ${TOPICO}/ping`);
  } catch (e) {
    morre(`sem broker em ${MQTT_HOST}:${MQTT_PORT} (${e.message})`);
  }

  http.createServer((req, res) => {
    const ok = req.method === 'GET' && req.url === '/health';
    res.writeHead(ok ? 200 : 404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(ok ? { status: 'ok', componente: NOME } : { error: 'rota inexistente' }));
  }).on('error', (e) => morre(`http :${PORT}: ${e.message}`))
    .listen(PORT, () => log(`http :${PORT} (GET /health)`));
}

// docker stop: the init of the compose (init: true) forwards SIGTERM.
process.on('SIGTERM', () => { log('SIGTERM: encerrando'); process.exit(0); });
main();
