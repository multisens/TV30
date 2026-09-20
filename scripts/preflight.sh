#!/bin/sh
# Preflight do TV30 — roda como one-shot ANTES dos servicos (network+pid do
# host). Nunca bloqueia a subida: diagnostica e imprime avisos legiveis para
# que, se o compose falhar logo depois (ex.: bind de porta), a causa ja
# esteja nomeada no log. Ver docs/troubleshooting.md.
set -u

# Politica de portas (plano de consolidacao, V10):
#   44642  — FIXA DA NORMA (C.3.4): ocupada = ERRO BLOQUEANTE
#   demais fixas por contrato local (aviso): 44643, 9001 (WS do browser),
#   8080 (URL humana), 6379 (convencao), 1883, 44652/44653 (servico)
#   dinamicas (docs, commander, bcast) nao entram na checagem
PORTS_WARN="1883 9001 6379 8080 8081 44643 44652 44653"
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

# 44642: unica porta INEGOCIAVEL (fixa pela norma C.3.4).
#   - ocupada por processo NATIVO  -> ERRO bloqueante (conflito real)
#   - ocupada por docker-proxy     -> aviso (ou e o proprio stack num re-up,
#     e o compose reusa o bind, ou e daemon Docker duplo — ver troubleshooting)
if echo "$LISTEN" | grep -qE "[:.]${PORT_BLOCK}$"; then
  OWNER=$(netstat -ltnp 2>/dev/null | grep -E "[:.]${PORT_BLOCK} " | awk '{print $7}' | head -1)
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
