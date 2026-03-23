// Proxy Windows localhost:8090 -> WSL 10.21.104.75:8090
const net = require('net');
const WSL_IP = '10.21.104.75';
const PORT = 8090;

net.createServer(src => {
  const dst = net.connect(PORT, WSL_IP);
  src.pipe(dst);
  dst.pipe(src);
  dst.on('error', () => src.destroy());
  src.on('error', () => dst.destroy());
}).listen(PORT, '127.0.0.1', () => {
  console.log(`Proxy: localhost:${PORT} -> ${WSL_IP}:${PORT}`);
});
