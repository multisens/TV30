#!/usr/bin/env bash
# test-template.sh — executa DE FATO o template de componente
# (templates/componente): copia a pasta para um diretorio temporario, troca o
# nome do componente (passo 1 do README do template), sobe o componente de
# exemplo com o compose do template e confere:
#   1. o container entrou na ginga_net e so nela (o projeto nao cria rede
#      propria), com restart unless-stopped e init;
#   2. o exemplo falou com o redis e com o mosquitto PELO NOME DO SERVICO:
#      logs de PING e de conexao com redis:6379 e mosquitto:1883, e um ping
#      por MQTT que volta com o valor que o teste acabou de gravar no Redis;
#   3. GET /health pela porta publicada no host;
#   4. morre-inteiro: matar o processo do componente derruba o container
#      (evento die) e o restart: unless-stopped o traz de volta
#      (RestartCount sobe), respondendo de novo ao ping.
# No fim (trap EXIT, inclusive em erro/Ctrl+C) derruba o projeto do
# componente (container e imagem construida), apaga a chave de teste do Redis
# e o diretorio temporario.
#
# Roda contra a stack JA DE PE (rede ginga_net, containers redis e
# mqtt-broker) e nao mexe nela. Imprime PASS/FAIL por verificacao e sai com
# codigo != 0 se alguma falhar.
#
# Uso (Linux/WSL, com acesso ao docker):  bash scripts/test-template.sh
#   (no WSL desta maquina: wsl.exe -u root bash /mnt/d/.../scripts/test-template.sh)
# Variaveis opcionais:
#   TPL_PORT     porta do host para o /health (padrao: a primeira livre de
#                18090 a 18129)
#   TPL_TIMEOUT  segundos para o container ficar healthy (padrao 120; inclui
#                o build e o pull da imagem base na primeira vez)
set -u
cd "$(dirname "$0")/.." || exit 2
ROOT=$(pwd)

RUN="$$$(date +%s)"
NAME="tpl$RUN"            # nome do componente na copia (servico e container)
PROJ="tv30-$NAME"         # projeto compose (o name: do template apos a troca)
TOPIC="tv30/$NAME/exemplo"   # padroes do index.js do exemplo
KEY="tv30:$NAME:exemplo"
TPL_TIMEOUT=${TPL_TIMEOUT:-120}
TMP=$(mktemp -d)
DIR="$TMP/$NAME"
IMG=""
PASS=0; FAIL=0; FAILED=()

pass() { PASS=$((PASS+1)); echo "PASS  $*"; }
fail() { FAIL=$((FAIL+1)); FAILED+=("$*"); echo "FAIL  $*"; }
info() { echo "      $*"; }
die()  { echo "ERRO: $*" >&2; exit 2; }
rc()   { docker exec redis redis-cli "$@"; }

# ---------------------------------------------------------------- pre-req --
command -v docker >/dev/null || die "docker ausente"
command -v curl >/dev/null || die "curl ausente"
docker compose version >/dev/null 2>&1 || die "docker compose ausente"
docker network inspect ginga_net >/dev/null 2>&1 \
  || die "rede ginga_net nao existe (suba a stack da raiz: docker compose up -d)"
for c in redis mqtt-broker; do
  [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] \
    || die "container $c nao esta rodando (suba a stack da raiz: docker compose up -d)"
done
[ "$(rc PING 2>/dev/null)" = PONG ] || die "redis nao responde ao PING"

port_busy() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
if [ -n "${TPL_PORT:-}" ]; then
  port_busy "$TPL_PORT" && die "TPL_PORT=$TPL_PORT ja esta ocupada no host"
else
  for p in $(seq 18090 18129); do port_busy "$p" || { TPL_PORT=$p; break; }; done
  [ -n "${TPL_PORT:-}" ] || die "nenhuma porta livre de 18090 a 18129 (defina TPL_PORT)"
fi

# o .env da raiz vale na interpolacao, como o README do template manda
ENVF=()
[ -f "$ROOT/.env" ] && ENVF=(--env-file "$ROOT/.env")
# -p explicito: o projeto do componente nunca se confunde com o da stack
dc() { MEU_COMPONENTE_PORT=$TPL_PORT docker compose -p "$PROJ" "${ENVF[@]}" -f "$DIR/docker-compose.yml" "$@"; }

cleanup() {
  set +e
  echo; echo "== limpeza =="
  if [ -f "$DIR/docker-compose.yml" ]; then
    dc down --rmi all -t 5 >"$TMP/down.log" 2>&1 || cat "$TMP/down.log"
  fi
  rc DEL "$KEY" >/dev/null
  if [ -n "$(docker ps -aq --filter "label=com.docker.compose.project=$PROJ")" ]; then
    echo "ATENCAO: sobrou container do projeto $PROJ"
  else
    echo "container do projeto $PROJ removido"
  fi
  if [ -n "$IMG" ] && docker image inspect "$IMG" >/dev/null 2>&1; then
    echo "ATENCAO: sobrou a imagem $IMG"
  elif [ -n "$IMG" ]; then
    echo "imagem $IMG removida"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ------------------------------------------------------- copia e troca --
cp -r "$ROOT/templates/componente" "$DIR" || die "falha copiando templates/componente"
grep -rl 'meu-componente' "$DIR" | while IFS= read -r f; do sed -i "s/meu-componente/$NAME/g" "$f"; done
if grep -rq 'meu-componente' "$DIR"; then die "a troca do nome deixou 'meu-componente' na copia"; fi
echo "== template copiado para $DIR (componente '$NAME', porta $TPL_PORT no host) =="

# ------------------------------------------------------------------ sobe --
wait_healthy() {
  local i s
  for i in $(seq 1 "$TPL_TIMEOUT"); do
    s=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$NAME" 2>/dev/null)
    [ "$s" = healthy ] && return 0
    sleep 1
  done
  return 1
}

if ! dc up -d --build >"$TMP/up.log" 2>&1; then
  tail -40 "$TMP/up.log"
  die "docker compose up -d --build do template falhou"
fi
pass "docker compose up -d --build do template (projeto $PROJ)"
IMG=$(docker inspect -f '{{.Config.Image}}' "$NAME" 2>/dev/null)
if wait_healthy; then
  pass "container $NAME healthy (o /health do exemplo so abre com Redis e broker conectados)"
else
  docker logs --tail 30 "$NAME" 2>&1
  die "container $NAME nao ficou healthy em ${TPL_TIMEOUT}s"
fi

# ------------------------------------------------------------ verificacoes --
echo; echo "-- rede e politica do container --"
NETS=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$NAME")
if [ "$NETS" = "ginga_net " ]; then pass "container na ginga_net, e so nela"
else fail "redes do container: '$NETS' (esperado so ginga_net)"; fi
PNETS=$(docker network ls -q --filter "label=com.docker.compose.project=$PROJ")
if [ -z "$PNETS" ]; then pass "o projeto $PROJ nao criou rede propria (ginga_net externa)"
else fail "o projeto $PROJ criou rede(s) propria(s): $PNETS"; fi
RP=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$NAME")
INIT=$(docker inspect -f '{{if .HostConfig.Init}}{{.HostConfig.Init}}{{end}}' "$NAME")
if [ "$RP" = unless-stopped ] && [ "$INIT" = true ]; then pass "restart: unless-stopped e init: true"
else fail "restart='$RP' init='$INIT' (esperado unless-stopped e true)"; fi

echo; echo "-- Redis e broker pelo nome do servico --"
LOGS=$(docker logs "$NAME" 2>&1)
if grep -q 'redis redis:6379 PING -> PONG' <<<"$LOGS"; then pass "log do exemplo: redis redis:6379 PING -> PONG"
else fail "log sem 'redis redis:6379 PING -> PONG': $(head -c 300 <<<"$LOGS" | tr '\n' ' ')"; fi
if grep -q "mqtt mosquitto:1883 conectado" <<<"$LOGS"; then pass "log do exemplo: mqtt mosquitto:1883 conectado"
else fail "log sem 'mqtt mosquitto:1883 conectado': $(head -c 300 <<<"$LOGS" | tr '\n' ' ')"; fi

# ping pelo broker; o exemplo responde com o valor da chave lido do Redis
ping_pong() {
  local label=$1 val="v-$RUN-$RANDOM" msg="ping-$RUN-$RANDOM" bg
  rc SET "$KEY" "$val" >/dev/null
  : >"$TMP/pong"
  docker exec mqtt-broker mosquitto_sub -C 1 -W 15 -t "$TOPIC/pong" >"$TMP/pong" 2>/dev/null &
  bg=$!
  sleep 1
  docker exec mqtt-broker mosquitto_pub -t "$TOPIC/ping" -m "$msg"
  wait "$bg" 2>/dev/null
  if grep -q "\"ping\":\"$msg\"" "$TMP/pong" && grep -q "\"valor\":\"$val\"" "$TMP/pong"; then
    pass "$label: ping em $TOPIC/ping voltou em $TOPIC/pong com o valor gravado agora no Redis"
  else
    fail "$label: esperado pong com ping=$msg e valor=$val, recebido '$(head -c 200 "$TMP/pong")'"
  fi
}
ping_pong "MQTT + Redis"

echo; echo "-- porta publicada --"
HS=$(curl -s -o "$TMP/health" -w '%{http_code}' -m 5 "http://127.0.0.1:$TPL_PORT/health")
if [ "$HS" = 200 ] && grep -q '"status":"ok"' "$TMP/health"; then pass "GET http://127.0.0.1:$TPL_PORT/health -> 200 $(cat "$TMP/health")"
else fail "GET /health pela porta $TPL_PORT -> status=$HS corpo=$(head -c 200 "$TMP/health")"; fi

echo; echo "-- morre-inteiro: matar o processo derruba o container; o restart religa --"
RC0=$(docker inspect -f '{{.RestartCount}}' "$NAME")
PID1=$(docker exec "$NAME" cat /proc/1/comm 2>/dev/null)
PIDN=$(docker exec "$NAME" pidof node 2>/dev/null)
info "PID 1 do container: '$PID1'; processo do componente: node, PID ${PIDN:-?}"
T0=$(date +%s)
if [ -n "$PIDN" ]; then
  docker exec "$NAME" kill -9 $PIDN >/dev/null 2>&1
  BACK=0
  for i in $(seq 1 60); do
    RC1=$(docker inspect -f '{{.RestartCount}}' "$NAME" 2>/dev/null)
    if [ "${RC1:-0}" -gt "$RC0" ] && [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = true ]; then
      BACK=1; break
    fi
    sleep 1
  done
  DIE=$(docker events --since "$T0" --until "$(date +%s)" --filter "container=$NAME" --filter event=die \
        --format '{{.Actor.Attributes.exitCode}}' 2>/dev/null | head -1)
  if [ -n "$DIE" ]; then pass "kill -9 no node derrubou o container (evento die, exitCode=$DIE)"
  else fail "kill -9 no node nao derrubou o container (nenhum evento die desde $T0)"; fi
  if [ "$BACK" = 1 ]; then pass "restart: unless-stopped religou o container (RestartCount $RC0 -> $RC1)"
  else fail "o container nao voltou em 60 s (RestartCount ${RC1:-?}, esperado > $RC0)"; fi
  if [ "$BACK" = 1 ] && wait_healthy; then
    pass "religado e healthy de novo"
    ping_pong "depois do restart"
  else
    fail "o container religado nao ficou healthy: $(docker logs --tail 5 "$NAME" 2>&1 | tr '\n' ' ')"
  fi
else
  fail "processo node nao encontrado no container (pidof node vazio)"
fi

# ================================================================ fim =====
echo
echo "== resultado: $PASS PASS, $FAIL FAIL =="
for f in "${FAILED[@]}"; do echo "  FAIL $f"; done
[ "$FAIL" -eq 0 ]
