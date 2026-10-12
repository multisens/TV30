#!/bin/sh
# Preflight do TV30 — roda como one-shot ANTES dos servicos (network+pid do
# host). Diagnostica e imprime avisos legiveis para que, se o compose falhar
# logo depois (ex.: bind de porta), a causa ja esteja nomeada no log. So
# bloqueia a subida em dois casos (exit 1, abaixo): a 44642 ocupada por outro
# processo, e o SSDP ligado sem SSDP_ADVERTISE_HOST (B2, decisao do Luis em
# 11/10); a borda depende deste servico e entao nao sobe. Ver
# docs/troubleshooting.md.
set -u

# Politica de portas (C1, decisao do Luis em 11/10; antes, V10 do plano de
# consolidacao):
#   44642  — FIXA DA NORMA (C.3.4): ocupada = ERRO BLOQUEANTE
#   fixas (aviso se ocupadas): 1883 (MQTT), 6379 (Redis), a 44643 (fixa
#   tambem na bridge desde 12/10: o /manifest a anuncia), a do AoP
#   (AOP_PUBLIC_PORT, padrao 8080; tambem a porta das apps de emissora em
#   <app>.apps.localhost, P1.3); com a borda em rede do host (SSDP_EDGE), a
#   8085 e as 44652/44653 do tv3ws em 127.0.0.1
#   sem porta fixa (o Docker escolhe uma livre; nao entram na checagem): a
#   9001 do mosquitto, a 8081 do bcast, a 8085 na bridge e a 18081 do
#   commander. A faixa 45000-45199 do remote-device fica de fora:
#   o tv3ws escolhe uma porta livre dentro dela.
PORTS_WARN="1883 6379 44643 ${AOP_PUBLIC_PORT:-8080}"
if [ "${SSDP_EDGE:-}" = "true" ]; then
  PORTS_WARN="$PORTS_WARN 8085 44652 44653"
fi
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
#   - com a borda em rede do host (SSDP_EDGE, docker-compose.ssdp.yml), quem
#     segura a 44642 num re-up e o krakend da propria borda -> aviso
if echo "$LISTEN" | grep -qE "[:.]${PORT_BLOCK}$"; then
  OWNER=$(owner_of "$PORT_BLOCK")
  case "$OWNER" in
    *docker-proxy*)
      echo "[preflight] AVISO: 44642 em LISTEN por docker-proxy — re-up do proprio"
      echo "[preflight]        stack (ok) ou segundo daemon Docker (ver troubleshooting)."
      WARN=1 ;;
    *)
      if [ "${SSDP_EDGE:-}" = "true" ] && ps -o args 2>/dev/null | grep -qE '[k]rakend run -c /etc/krakend/krakend-internal\.'; then
        echo "[preflight] AVISO: 44642 em LISTEN pela propria borda em rede do host (re-up, ok)."
        WARN=1
      else
        echo "[preflight] ERRO: a porta ${PORT_BLOCK} esta ocupada (${OWNER:-dono desconhecido})."
        echo "[preflight]       Ela e FIXA pela norma (C.3.4) e precisa estar livre."
        echo "[preflight]       Libere a porta e rode 'docker compose up -d' de novo."
        exit 1
      fi ;;
  esac
fi

# B2 (decisao do Luis em 11/10): com o anuncio ligado, o host do LOCATION e
# o SSDP_ADVERTISE_HOST, obrigatorio. Sem ele o anunciante da borda sai com
# erro de configuracao (C8) e a borda cai; aqui a subida para antes, com a
# mensagem. O override do SSDP repassa ao preflight os mesmos arquivos de
# ambiente da borda (tv3ws/.env e .env).
if [ "${SSDP_EDGE:-}" = "true" ] && [ -z "$(printf '%s' "${SSDP_ADVERTISE_HOST:-}" | tr -d ' ')" ]; then
  echo "[preflight] ERRO: o anuncio SSDP esta ligado (docker-compose.ssdp.yml) e falta SSDP_ADVERTISE_HOST."
  echo "[preflight]       Defina no .env da raiz o IP (ou nome) desta maquina na rede, por exemplo"
  echo "[preflight]       SSDP_ADVERTISE_HOST=192.168.0.23, e rode 'docker compose up -d' de novo."
  exit 1
fi

for p in $PORTS_WARN; do
  if echo "$LISTEN" | grep -qE "[:.]${p}$"; then
    OWNER=$(owner_of "$p")
    echo "[preflight] AVISO: porta ${p} ja esta em LISTEN (${OWNER:-dono desconhecido})."
    WARN=1
  fi
done

# UDP 1900 (SSDP): com a borda em rede do host (SSDP_EDGE=true, definido pelo
# docker-compose.ssdp.yml; L6 = opcao A, 09/10) quem anuncia e a borda. Aviso,
# sem bloquear: o anunciante abre a porta com SO_REUSEADDR e convive com outro
# socket que tambem use a opcao; se o dono atual nao usar, o bind falha e,
# pelo morre-inteiro, a borda inteira cai e reinicia (docker logs edgegateway).
if [ "${SSDP_EDGE:-}" = "true" ]; then
  if netstat -lun 2>/dev/null | awk '{print $4}' | grep -qE '[:.]1900$'; then
    if ps -o args 2>/dev/null | grep -qE '(^|[ /])[s]sdp-announcer( |$)'; then
      echo "[preflight] ok: UDP 1900 em uso pelo anunciante da propria borda (re-up)."
    else
      # dono "-" = sem CAP_SYS_PTRACE para ler o processo (ver owner_of)
      OWNER=$(netstat -lunp 2>/dev/null | grep -E '[:.]1900 ' | awk '{print $NF}' | grep -v '^-$' | sort -u | tr '\n' ' ' | sed 's/ *$//')
      echo "[preflight] AVISO: UDP 1900 (SSDP) ja esta em uso no host (${OWNER:-dono desconhecido})."
      echo "[preflight]        O anunciante da borda convive se o outro socket usar SO_REUSEADDR;"
      echo "[preflight]        senao a borda inteira cai e reinicia (docker logs edgegateway)."
      WARN=1
    fi
  fi
fi

# Anunciante da opcao B (container tv3ws-ssdp, substituido pela opcao A em
# 09/10) ainda de pe: seriam dois anunciantes. O servico saiu do compose, entao
# ele so sai com docker rm (ou docker compose up -d --remove-orphans).
if ps -o args 2>/dev/null | grep -qE '[n]ode dist/ssdp-announcer\.js'; then
  echo "[preflight] AVISO: o container antigo tv3ws-ssdp ainda esta de pe (anunciante da opcao B)."
  echo "[preflight]        Agora quem anuncia e a borda. Para remover: docker rm -f tv3ws-ssdp"
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
