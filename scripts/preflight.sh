#!/bin/sh
# Preflight do TV30 — roda como one-shot ANTES dos servicos (network+pid do
# host). Nunca bloqueia a subida: diagnostica e imprime avisos legiveis para
# que, se o compose falhar logo depois (ex.: bind de porta), a causa ja
# esteja nomeada no log. Ver docs/troubleshooting.md.
set -u

PORTS="1883 9001 3000 3001 6379 8080 8081 8085 18081 44642 44643 44652 44653"
WARN=0

echo "[preflight] verificando DNS..."
if ! nslookup registry-1.docker.io >/dev/null 2>&1; then
  echo "[preflight] AVISO: DNS nao resolve registry-1.docker.io — pulls de imagem vao falhar."
  echo "[preflight]        (WSL2: conferir /etc/resolv.conf; rede corporativa: proxy/DNS)"
  WARN=1
fi

echo "[preflight] verificando portas usadas pelo stack..."
LISTEN=$(netstat -ltn 2>/dev/null | awk '{print $4}')
for p in $PORTS; do
  if echo "$LISTEN" | grep -qE "[:.]${p}$"; then
    OWNER=""
    for pid in /proc/[0-9]*; do
      if ls -l "$pid/fd" 2>/dev/null | grep -q socket; then :; fi
    done
    # identifica o dono via /proc (pid namespace do host)
    OWNER=$(netstat -ltnp 2>/dev/null | grep -E "[:.]${p} " | awk '{print $7}' | head -1)
    echo "[preflight] AVISO: porta ${p} ja esta em LISTEN (${OWNER:-dono desconhecido})."
    WARN=1
  fi
done

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
