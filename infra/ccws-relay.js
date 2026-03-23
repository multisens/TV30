// Roda no WSL: relay TCP Docker → CCWS Windows (HTTPS + HTTP)
const net = require('net');

function createRelay(listenPort, targetPort) {
  net.createServer(src => {
    const dst = net.connect(targetPort, 'localhost');
    src.pipe(dst); dst.pipe(src);
    dst.on('error', () => src.destroy());
    src.on('error', () => dst.destroy());
  }).listen(listenPort, '0.0.0.0', () => {
    console.log(`CCWS relay: 0.0.0.0:${listenPort} -> localhost:${targetPort}`);
  });
}

createRelay(44655, 44653); // HTTPS relay (KrakenD_external → CCWS)
createRelay(44654, 44652); // HTTP  relay (KrakenD_internal → CCWS)
