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

# Dono de uma porta em LISTEN. Este container nao tem CAP_SYS_PTRACE, entao o
# netstat nao le /proc/<pid>/fd de processo do host com capacidades plenas —
# caso do docker-proxy — e o dono sai "-" (medido em 02/10: com a stack de pe,
# um segundo `docker compose up -d` parava aqui com "ocupada (-)"). Nesse caso
# a linha de comando do docker-proxy (/proc/<pid>/cmdline, legivel sem ptrace
# com pid: host) identifica a porta.
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

# UDP 1900 (SSDP), so com o perfil "ssdp": o tv3ws-ssdp anuncia em rede do
# host. Aviso, sem bloquear: o anunciante abre a porta com SO_REUSEADDR e
# convive com outro socket que tambem use a opcao; se o dono atual nao usar,
# o bind falha e o tv3ws-ssdp sai com [ssdp] FALHA e reinicia em laco.
# COMPOSE_PROFILES chega pela secao environment do preflight no compose;
# perfil ligado so por --profile na linha de comando nao e visto aqui.
PROFILES=$(printf '%s' "${COMPOSE_PROFILES:-}" | tr -d ' ')
case ",${PROFILES}," in
  *,ssdp,*|*,\*,*)
    if netstat -lun 2>/dev/null | awk '{print $4}' | grep -qE '[:.]1900$'; then
      if ps -o args 2>/dev/null | grep -qE '[n]ode dist/ssdp-announcer\.js'; then
        echo "[preflight] ok: UDP 1900 em uso pelo tv3ws-ssdp ja em execucao (re-up)."
      else
        # dono "-" = sem CAP_SYS_PTRACE para ler o processo (ver owner_of)
        OWNER=$(netstat -lunp 2>/dev/null | grep -E '[:.]1900 ' | awk '{print $NF}' | grep -v '^-$' | sort -u | tr '\n' ' ' | sed 's/ *$//')
        echo "[preflight] AVISO: UDP 1900 (SSDP) ja esta em uso no host (${OWNER:-dono desconhecido})."
        echo "[preflight]        O tv3ws-ssdp convive se o outro socket usar SO_REUSEADDR; senao"
        echo "[preflight]        sai com '[ssdp] FALHA' e reinicia (docker logs tv3ws-ssdp)."
        WARN=1
      fi
    fi ;;
  *)
    # Perfil "ssdp" fora do COMPOSE_PROFILES, mas anunciante de pe: o compose
    # nao derruba servico de perfil desligado, e o tv3ws-ssdp segue anunciando
    # o host antigo enquanto o tv3ws recriado responde outro no /manifest.
    if ps -o args 2>/dev/null | grep -qE '[n]ode dist/ssdp-announcer\.js'; then
      echo "[preflight] AVISO: o tv3ws-ssdp esta de pe, mas o perfil 'ssdp' nao esta no COMPOSE_PROFILES."
      echo "[preflight]        Ele continua anunciando a configuracao antiga. Para remover:"
      echo "[preflight]        docker compose --profile ssdp rm -sf tv3ws-ssdp"
      echo "[preflight]        (ignore se o perfil foi ligado so por --profile na linha de comando)"
      WARN=1
    fi ;;
esac

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
