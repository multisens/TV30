// Roda dentro do WSL: escuta em 0.0.0.0:8091 e repassa para Docker localhost:8090
const net = require('net');
net.createServer(src => {
  const dst = net.connect(8090, 'localhost');
  src.pipe(dst); dst.pipe(src);
  dst.on('error', () => src.destroy());
  src.on('error', () => dst.destroy());
}).listen(8091, '0.0.0.0', () => console.log('Proxy WSL: 0.0.0.0:8091 -> localhost:8090'));
