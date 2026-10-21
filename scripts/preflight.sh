#!/bin/sh
# Preflight do TV30: one-shot ANTES dos servicos (rede e pid do host). Deixa no
# log a causa de uma falha de subida (ex.: bind de porta); so bloqueia (exit 1,
# e a borda nao sobe) com a 44642 ocupada por outro processo.
set -u

# Portas: 44642 (fixa da norma, C.3.4) ocupada = erro bloqueante; 1883, 6379,
# 44643 e a do AoP (AOP_PUBLIC_PORT) so avisam. Ficam de fora as que o Docker
# escolhe (9001, 8081, 8085, 18081) e a faixa 45000-45199, onde o tv3ws escolhe.
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

# Dono de uma porta em LISTEN. Sem CAP_SYS_PTRACE, o netstat nao le o /proc do
# docker-proxy e o dono sai "-"; a linha de comando dele (legivel com pid: host)
# identifica a porta.
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

# 44642: unica porta INEGOCIAVEL (fixa pela norma C.3.4).
#   - ocupada por processo NATIVO  -> ERRO bloqueante (conflito real)
#   - ocupada por docker-proxy     -> aviso (ou e o proprio stack num re-up,
#     e o compose reusa o bind, ou e daemon Docker duplo — ver troubleshooting)
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

# A UDP 1900 nao e checada aqui: o anunciante SSDP nativo (./tv30 up) avisa
# se ela estiver presa. Um container tv3ws-ssdp remanescente seria um segundo
# anunciante; fora do compose, so sai com docker rm (ou up -d --remove-orphans).
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
