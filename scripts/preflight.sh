#!/bin/sh
# TV30 preflight: a one-shot before the services (host network and pid). It
# logs the cause of a startup failure (e.g. a port bind); it blocks (exit 1,
# and the edge does not start) only when 44642 is held by another process.
set -u

# Ports: 44642 (C.3.4) held is a blocking error; 1883, 6379, 44643 and the
# AoP port (AOP_PUBLIC_PORT) only warn. Left out: the ports Docker chooses
# (9001, 8081, 8085, 18081) and the range 45000-45199, where tv3ws chooses.
PORTS_WARN="1883 6379 44643 ${AOP_PUBLIC_PORT:-8080}"
PORT_BLOCK="44642"
WARN=0

echo "[preflight] verificando DNS..."
if ! nslookup registry-1.docker.io >/dev/null 2>&1; then
  echo "[preflight] AVISO: DNS nao resolve registry-1.docker.io — pulls de imagem vao falhar."
  echo "[preflight]        (WSL2: conferir /etc/resolv.conf; rede corporativa: proxy/DNS)"
  WARN=1
fi

echo "[preflight] verificando portas usadas pelo stack..."
LISTEN=$(netstat -ltn 2>/dev/null | awk '{print $4}')

# Owner of a port in LISTEN. Without CAP_SYS_PTRACE, netstat does not read
# the /proc of docker-proxy and the owner is "-"; its command line (readable
# with pid: host) identifies the port.
owner_of() {
  o=$(netstat -ltnp 2>/dev/null | grep -E "[:.]$1 " | awk '{print $7}' | head -1)
  case "$o" in
    ""|-)
      if ps -o args 2>/dev/null | grep -qE "[d]ocker-proxy .*-host-port $1( |$)"; then
        o="docker-proxy"
      fi ;;
  esac
  printf '%s' "$o"
}

# 44642 (C.3.4):
#   - held by a native process: blocking error;
#   - held by docker-proxy: warning (the stack itself on a re-up, where
#     compose reuses the bind, or a second Docker daemon).
if echo "$LISTEN" | grep -qE "[:.]${PORT_BLOCK}$"; then
  OWNER=$(owner_of "$PORT_BLOCK")
  case "$OWNER" in
    *docker-proxy*)
      echo "[preflight] AVISO: 44642 em LISTEN por docker-proxy — re-up do proprio"
      echo "[preflight]        stack (ok) ou segundo daemon Docker (ver troubleshooting)."
      WARN=1 ;;
    *)
      echo "[preflight] ERRO: a porta ${PORT_BLOCK} esta ocupada (${OWNER:-dono desconhecido})."
      echo "[preflight]       Ela e FIXA pela norma (C.3.4) e precisa estar livre."
      echo "[preflight]       Libere a porta e rode 'docker compose up -d' de novo."
      exit 1 ;;
  esac
fi

for p in $PORTS_WARN; do
  if echo "$LISTEN" | grep -qE "[:.]${p}$"; then
    OWNER=$(owner_of "$p")
    echo "[preflight] AVISO: porta ${p} ja esta em LISTEN (${OWNER:-dono desconhecido})."
    WARN=1
  fi
done

# UDP 1900 is not checked here. A leftover tv3ws-ssdp container would be a
# second announcer; outside the compose, only docker rm (or up -d
# --remove-orphans) removes it.
if ps -o args 2>/dev/null | grep -qE '[n]ode dist/ssdp-announcer\.js'; then
  echo "[preflight] AVISO: o container tv3ws-ssdp esta de pe (seria um segundo anunciante SSDP)."
  echo "[preflight]        Quem anuncia e o anunciante nativo do host (./tv30 up). Para remover: docker rm -f tv3ws-ssdp"
  WARN=1
fi

if [ "$WARN" -eq 1 ]; then
  echo "[preflight] ---------------------------------------------------------------"
  echo "[preflight] Avisos acima NAO impedem a subida. Se o compose falhar com"
  echo "[preflight] 'address already in use', o dono da porta esta listado acima."
  echo "[preflight] Porta presa por docker-proxy sem container correspondente ="
  echo "[preflight] provavel segundo daemon Docker (snap/Desktop)."
  echo "[preflight] Triagem completa: docs/troubleshooting.md, secao 'Porta presa'."
  echo "[preflight] ---------------------------------------------------------------"
else
  echo "[preflight] ok: DNS funcional e portas livres."
fi
exit 0
