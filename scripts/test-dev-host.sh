#!/bin/bash
# Cenario de desenvolvimento (reuniao 21/09): sobe SO a infra basica em
# containers (redis + broker + edge) e verifica que um servico rodando NO
# HOST e alcancavel pela borda — a ponte rede-de-containers -> host.
#
# O edge na variante "windows" aponta os backends para host.docker.internal
# (que em Linux resolve para o host via host-gateway). Este teste sobe um
# servidor HTTP descartavel na porta 44654 do host no lugar do tv3ws e
# consulta /health atraves da borda (44642).
#
# Uso: ./scripts/test-dev-host.sh   (na raiz do TV30, com Docker de pe)
set -e
cd "$(dirname "$0")/.."

echo "== subindo infra basica (redis, mqtt-broker, edgegateway) com backend no host =="
EDGE_VARIANT=windows docker compose --profile mqtt up -d redis mosquitto edgegateway

echo "== servico de mentira no host: porta 44654 respondendo /health =="
python3 - <<'EOF' &
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"status": "ok", "origem": "servico no host"}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(('0.0.0.0', 44654), H).serve_forever()
EOF
FAKE_PID=$!
trap 'kill $FAKE_PID 2>/dev/null' EXIT
sleep 2

echo "== borda (44642) deve alcancar o servico do host =="
for i in $(seq 1 30); do
  resp=$(curl -s -m 3 http://localhost:44642/health || true)
  echo "$resp" | grep -q 'servico no host' && break
  sleep 2
done

if echo "$resp" | grep -q 'servico no host'; then
  echo "PASS  ponte containers->host funcionando: $resp"
  echo
  echo "Pra desenvolver de verdade: rode o tv3ws no host com"
  echo "  HTTP_PORT=44654 HTTPS_PORT=44655 REDIS_HOST=localhost MQTT_HOST=localhost npm run dev"
  echo "e mantenha EDGE_VARIANT=windows no .env. Ver docs/dev-local.md."
  exit 0
else
  echo "FAIL  a borda nao alcancou o servico do host. Resposta: $resp"
  echo "Confira: extra_hosts host.docker.internal no edgegateway; firewall do host na 44654."
  exit 1
fi
