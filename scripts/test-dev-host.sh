#!/bin/bash
# Test of the development scenario: starts the MINIMUM of containers and
# runs REAL modules (tv3ws, aop, bcast or the example component of the
# template) outside Docker, with `npm ci && npm run dev`, checking the
# communication between the host and the Docker network in five
# combinations:
#
#   1  tv3ws on the host | containers: redis, mosquitto, edgegateway (windows
#      variant: backends on host.docker.internal:44654/44655), aop, bcast
#   2  aop on the host   | containers: redis, mosquitto, edgegateway (linux
#      variant), tv3ws, bcast (BCAST_HOSTNAME=localhost,
#      BCAST_PUBLISH=8081:8081)
#   3  bcast on the host | containers: redis, mosquitto, edgegateway (linux
#      variant), tv3ws, aop (reaches the host by host.docker.internal)
#   4  tv3ws, aop and bcast on the host AT THE SAME TIME | containers: redis,
#      mosquitto, edgegateway (windows variant); bcast with
#      BCAST_HOSTNAME=127.0.0.1 (the aop that reaches it is also on the host)
#   5  a new component on the host (the example of templates/componente) |
#      containers: redis and mosquitto; the edge is STOPPED during the
#      scenario
#
# Every scenario checks host->Redis and host->MQTT from the environment of
# the module, its connection logs and the specific path of the scenario, with
# a negative proof after killing the host process. At the end, the default
# stack comes back (the .env configuration) if it was up before, or goes
# down (docker compose down). The edge always runs on the bridge; the SSDP
# announcement (./tv30 up) is not part of this test.
#
# "Host" = a process on the host network. Two ways (DEVHOST_MODO):
#   node    node/npm of the PATH, on a temporary copy of the module (without
#           node_modules/.env; public/ goes in as a link)
#   docker  docker run --network host <node image> with the module mounted
#           read-only on /src and copied to /app: a network identical to the
#           host one, for machines without node (e.g. WSL without node)
#   auto    node if there is a Linux node in the PATH, otherwise docker
#           (default)
#
# Ports on the host: 44654/44655 and 45000-45199 (tv3ws, scenarios 1 and 4),
# 8080 (aop, 2 and 4), 8081 (bcast, 3 and 4) and 8090 (component, 5); 8080,
# 8081 and 45000-45199 are those of the container of the module, which the
# scenario stops first. The script checks that 44654, 8080, 8081 and 8090 are
# free before starting the process.
#
# Usage: ./scripts/test-dev-host.sh [--cenario N[,N...]] [--build] [-h]
#   --cenario  1, 2, 3, 4 and/or 5 (default: all, in order)
#   --build    passes --build to docker compose up (e.g. an edge with a new
#              plugin)
#
# Optional variables:
#   DEVHOST_MODO     auto | node | docker            (default auto)
#   DEVHOST_IMAGEM   node image of the docker mode   (default node:23-alpine,
#                    the same base as infra/dockerfiles/*.Dockerfile)
#   DEVHOST_TIMEOUT  seconds for the module to answer (default 300; includes
#                    npm ci in docker mode)
#   JWT_SECRET, JWT_ISSUER, SERVER_URL: shell > root .env > compose default.
#                    JWT_SECRET applies to the edge and to the tv3ws on the
#                    host. The MQTT over WebSocket port of the aop on the
#                    host comes from Docker (porta_ws_mqtt).
#   npm proxy and registry (HTTP_PROXY, HTTPS_PROXY, NO_PROXY,
#   NPM_CONFIG_REGISTRY, NPM_CONFIG_STRICT_SSL) are passed to the container.
#
# Native Linux and WSL2 with Docker Engine in WSL itself. Native Windows (Git
# Bash or PowerShell with Docker in WSL) is NOT covered: host-gateway points
# to the WSL VM, not to Windows. See docs/dev-local.md.
set -u
# Associative arrays (declare -A) need bash 4; /bin/bash of macOS is 3.2.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "test-dev-host.sh precisa do bash 4 ou mais novo (este e o $BASH_VERSION)." >&2
  echo "No macOS: brew install bash e rode /opt/homebrew/bin/bash scripts/test-dev-host.sh" >&2
  exit 2
fi
cd "$(dirname "$0")/.." || exit 2
ROOT=$(pwd)

uso() { sed -n '2,/^set -u/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; }

CENARIOS="1 2 3 4 5"
BUILD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cenario)   [ $# -ge 2 ] || { echo "--cenario precisa de um valor"; exit 2; }
                 CENARIOS=$2; shift 2 ;;
    --cenario=*) CENARIOS=${1#*=}; shift ;;
    --build)     BUILD="--build"; shift ;;
    -h|--help)   uso; exit 0 ;;
    *)           echo "opcao desconhecida: $1 (veja --help)"; exit 2 ;;
  esac
done
CENARIOS=${CENARIOS//,/ }
for n in $CENARIOS; do
  case "$n" in 1|2|3|4|5) ;; *) echo "cenario invalido: $n (use 1, 2, 3, 4 ou 5)"; exit 2 ;; esac
done

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "Windows nativo nao e coberto por este teste: rode no WSL2 ou em Linux."
    echo "(com o Docker no WSL, host.docker.internal aponta para a VM do WSL, nao"
    echo " para o Windows — ver docs/dev-local.md)"
    exit 2 ;;
esac

precisa() { command -v "$1" >/dev/null 2>&1 || { echo "falta '$1' no PATH"; exit 2; }; }
precisa docker
precisa curl
docker compose version >/dev/null 2>&1 || { echo "falta o Docker Compose v2 (docker compose)"; exit 2; }

# ------------------------------------------------------------------ config ---

# Value of a variable in the root .env (without quotes); empty if absent.
dotenv_get() {
  [ -f .env ] || return 0
  sed -n "s/^[[:space:]]*$1=//p" .env | tail -n 1 | tr -d '\r' \
    | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}
# Precedence: shell > root .env > default (the same as docker compose).
cfg() {
  local v="${!1:-}"
  [ -n "$v" ] || v=$(dotenv_get "$1")
  [ -n "$v" ] || v=$2
  printf '%s' "$v"
}

# Exported, so that the compose (edge and tv3ws in a container) and the
# tv3ws on the host read the same value.
JWT_SECRET=$(cfg JWT_SECRET tv30-dev-secret-nao-usar-em-producao); export JWT_SECRET
JWT_ISSUER=$(cfg JWT_ISSUER GenericIssuer); export JWT_ISSUER
# Host port where Docker published the 9001 of mosquitto; empty if the
# broker is not up.
porta_ws_mqtt() { docker port mqtt-broker 9001/tcp 2>/dev/null | head -1 | sed 's/.*://'; }
SERVER_URL_CFG=$(cfg SERVER_URL localhost)

TIMEOUT=${DEVHOST_TIMEOUT:-300}
IMAGEM=${DEVHOST_IMAGEM:-node:23-alpine}
MODO=${DEVHOST_MODO:-auto}
if [ "$MODO" = auto ]; then
  # A Windows node.exe/npm visible in the WSL PATH (/mnt/...) would run on the
  # Windows network, not the Docker one: in that case the docker mode is used.
  n=$(command -v node 2>/dev/null || true)
  m=$(command -v npm 2>/dev/null || true)
  if [ -n "$n" ] && [ -n "$m" ] && [ "${n#/mnt/}" = "$n" ] && [ "${m#/mnt/}" = "$m" ]; then
    MODO=node
  else
    MODO=docker
  fi
fi
case "$MODO" in
  node)   precisa node; precisa npm; precisa pgrep ;;
  docker) ;;
  *)      echo "DEVHOST_MODO invalido: $MODO (auto, node ou docker)"; exit 2 ;;
esac

LOGDIR=$(mktemp -d "${TMPDIR:-/tmp}/tv30-devhost-logs.XXXXXX")

# Every compose call enables both profiles: tv3ws, aop, bcast and
# sysctl-init have the "linux" profile and mosquitto "mqtt". The edge of the
# test starts in warn mode (DEVHOST_AUTH_ENFORCE changes it): in enforce, the
# test token (a sub not in clients:authorized) would get 107 before reaching
# the module on the host. The restore (compose_env) goes back to the mode of
# the .env.
compose() { COMPOSE_FILE=docker-compose.yml AUTH_ENFORCE=${DEVHOST_AUTH_ENFORCE:-warn} docker compose --profile mqtt --profile linux "$@"; }
# Restore: the configuration of the .env (COMPOSE_FILE included).
compose_env() { docker compose --profile mqtt --profile linux "$@"; }

# Basic infrastructure and the one-shots it needs (the preflight comes as a
# dependency of the edgegateway; userfiles-seed creates ./user-files for the
# module on the host).
INFRA="redis mosquitto edgegateway userfiles-seed"

# Leftovers of an interrupted run: the tv30-devhost-<module> container (host
# network) would hold the port of the module, and the scenarios would fail
# with "port in use". The name belongs to this script only; removed before
# starting.
RESTOS=$(docker ps -aq --filter name='^tv30-devhost-' 2>/dev/null | tr '\n' ' ')
if [ -n "${RESTOS// /}" ]; then
  echo "removendo restos de uma execucao interrompida: $(docker ps -a --filter name='^tv30-devhost-' --format '{{.Names}}' | tr '\n' ' ')"
  docker rm -f $RESTOS >/dev/null 2>&1
fi

# Services of the stack running before the test (they define the restore).
ANTES=$(docker ps --filter label=com.docker.compose.project=tv30 \
          --format '{{.Label "com.docker.compose.service"}}' 2>/dev/null | sort -u | tr '\n' ' ')

# ------------------------------------------------------------------ report ---

CEN="-"
PASS=0
FAIL=0
RESUMO=()
ok()     { PASS=$((PASS + 1)); RESUMO+=("PASS  [cenario $CEN] $1"); echo "  PASS  $1"; }
falha()  { FAIL=$((FAIL + 1)); RESUMO+=("FAIL  [cenario $CEN] $1"); echo "  FAIL  $1"; }
info()   { echo "  info  $1"; }
titulo() { echo; echo "=================================================================="; echo "$1"; echo "=================================================================="; }

# Response body plus a final HTTP_STATUS=<code> line (patterns may match
# either).
resposta() { curl -s -m 5 -w '\nHTTP_STATUS=%{http_code}' "$@" 2>/dev/null; }
recorte()  { printf '%s' "$1" | tr '\n' ' ' | cut -c1-200; }

# checar_http <description> <url> <pattern> <attempts> [curl args...]
checar_http() {
  local desc=$1 url=$2 pad=$3 n=$4 i=0 r=""; shift 4
  while [ "$i" -lt "$n" ]; do
    r=$(resposta "$@" "$url")
    if printf '%s' "$r" | grep -q -e "$pad"; then ok "$desc"; return 0; fi
    i=$((i + 1)); sleep 2
  done
  falha "$desc — resposta: $(recorte "$r")"; return 1
}

# checar_http_nao <description> <url> <pattern> <attempts> [curl args...]:
# passes when the pattern STOPS appearing (proof that the response came from
# the host process).
checar_http_nao() {
  local desc=$1 url=$2 pad=$3 n=$4 i=0 r=""; shift 4
  while [ "$i" -lt "$n" ]; do
    r=$(resposta "$@" "$url")
    if ! printf '%s' "$r" | grep -q -e "$pad"; then ok "$desc"; return 0; fi
    i=$((i + 1)); sleep 2
  done
  falha "$desc — ainda responde: $(recorte "$r")"; return 1
}

porta_livre() { ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

container_rodando() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }

# State and log tail of a container, when a check that depends on it fails
# (the container may be recreated later and take its log along).
diag_container() {
  info "$1: $(docker inspect -f 'status={{.State.Status}} reinicios={{.RestartCount}} inicio={{.State.StartedAt}}' "$1" 2>&1)"
  docker logs --tail 15 "$1" 2>&1 | sed 's/^/    | /'
}

# subir <EDGE_VARIANT> <services...> (extra variables: a VAR=value prefix on
# the call)
subir() {
  local variante=$1; shift
  echo "  ...   docker compose up -d $* (EDGE_VARIANT=$variante)"
  if ! EDGE_VARIANT=$variante compose up -d $BUILD "$@" >>"$LOGDIR/compose.log" 2>&1; then
    falha "docker compose up -d $* (ver $LOGDIR/compose.log)"
    tail -n 15 "$LOGDIR/compose.log" | sed 's/^/    | /'
    return 1
  fi
}

# parar <service> [reason]: the module on the host cannot coexist with the
# container (same port and same fixed MQTT clientId: tv3ws-client, aop-core,
# bcast_svc); the reason changes only the message (e.g. the edge in
# scenario 5).
parar() {
  compose stop "$1" >>"$LOGDIR/compose.log" 2>&1 || true
  if container_rodando "$1"; then falha "container $1 continua rodando"; return 1; fi
  ok "container $1 parado (${2:-o modulo roda so no host})"
}

# ------------------------------------------------------------ host process ---

# HOST_* describe the CURRENT module, the one host_vivo, host_logs, host_node
# and host_stop act on. More than one module may be on the host at the same
# time (scenario 4): the REG_* registry keeps the state of each, host_usar
# makes another one current and host_stop_todos stops all of them.
HOST_MOD=""; HOST_PID=""; HOST_DIR=""; HOST_CTR=""; HOST_LOG=""
declare -A REG_PID=() REG_DIR=() REG_CTR=() REG_LOG=()
# Modules up on the host, in the order they started.
HOST_LISTA=""

# Folder of the module, relative to the root (the component of scenario 5 is
# the example of the template; the other modules have a folder of their own
# name).
pasta_modulo() { case "$1" in componente) printf 'templates/componente' ;; *) printf '%s' "$1" ;; esac; }

# Saves the state of the current module in the registry.
host_registrar() {
  REG_PID[$HOST_MOD]=$HOST_PID; REG_DIR[$HOST_MOD]=$HOST_DIR
  REG_CTR[$HOST_MOD]=$HOST_CTR; REG_LOG[$HOST_MOD]=$HOST_LOG
  case " $HOST_LISTA " in *" $HOST_MOD "*) ;; *) HOST_LISTA="${HOST_LISTA:+$HOST_LISTA }$HOST_MOD" ;; esac
}

# host_usar <module>: makes current a module that is on the host.
host_usar() {
  case " $HOST_LISTA " in *" $1 "*) ;; *) falha "$1 nao esta rodando no host"; return 1 ;; esac
  HOST_MOD=$1; HOST_PID=${REG_PID[$1]}; HOST_DIR=${REG_DIR[$1]}
  HOST_CTR=${REG_CTR[$1]}; HOST_LOG=${REG_LOG[$1]}
}

# copiar_modulo <source> <target>
copiar_modulo() {
  local f nome
  for f in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -e "$f" ] || continue
    nome=${f##*/}
    case "$nome" in node_modules|.env|.git|public) continue ;; esac
    cp -R "$f" "$2/"
  done
  if [ -d "$1/public" ]; then ln -s "$1/public" "$2/public"; fi
  return 0
}

# The same copy, inside the container of the docker mode (alpine sh).
COPIA_SH='mkdir -p /app && cd /src && for f in * .[!.]* ..?*; do [ -e "$f" ] || continue; case "$f" in node_modules|.env|.git|public) ;; *) cp -R "$f" /app/ ;; esac; done; if [ -d /src/public ]; then ln -s /src/public /app/public; fi'

# user-files directory as seen by the module on the host.
dir_userfiles() { if [ "$MODO" = node ]; then printf '%s' "$ROOT/user-files"; else printf '/user-files'; fi; }

# host_start <module> VAR=value...: the new module becomes the current one.
host_start() {
  local mod=$1 kv src; shift
  src=$(pasta_modulo "$mod")
  case " $HOST_LISTA " in *" $mod "*) falha "$mod ja esta rodando no host"; return 1 ;; esac
  HOST_MOD=$mod; HOST_PID=""; HOST_DIR=""; HOST_CTR=""
  HOST_LOG="$LOGDIR/cenario$CEN-$mod.log"
  echo "  ...   $mod ($src) no host (modo $MODO): $(printf '%s ' "$@" | sed -E 's/(JWT_SECRET=)[^ ]*/\1***/')npm run dev"
  if [ "$MODO" = node ]; then
    HOST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tv30-devhost-$mod.XXXXXX")
    # Registered already here: host_stop_todos removes the copy if npm ci fails.
    host_registrar
    copiar_modulo "$ROOT/$src" "$HOST_DIR"
    echo "  ...   npm ci em $HOST_DIR"
    if ! ( cd "$HOST_DIR" && npm ci --include=dev --no-audit --no-fund ) >"$HOST_LOG" 2>&1; then
      falha "npm ci ($mod) — ver $HOST_LOG"; tail -n 20 "$HOST_LOG" | sed 's/^/    | /'
      return 1
    fi
    ( cd "$HOST_DIR" && exec env "$@" npm run dev ) >>"$HOST_LOG" 2>&1 &
    HOST_PID=$!
    host_registrar
  else
    HOST_CTR="tv30-devhost-$mod"
    host_registrar
    docker rm -f "$HOST_CTR" >/dev/null 2>&1
    local envs=()
    for kv in "$@"; do envs+=(-e "$kv"); done
    for kv in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy \
              NPM_CONFIG_REGISTRY NPM_CONFIG_STRICT_SSL npm_config_registry npm_config_strict_ssl; do
      if [ -n "${!kv:-}" ]; then envs+=(-e "$kv"); fi
    done
    if ! docker run -d --init --name "$HOST_CTR" --network host \
           -v "$ROOT/$src:/src:ro" -v "$ROOT/user-files:/user-files" \
           -v tv30-devhost-npm:/root/.npm \
           "${envs[@]}" "$IMAGEM" \
           sh -c "$COPIA_SH; cd /app && npm ci --include=dev --no-audit --no-fund && exec npm run dev" \
           >>"$LOGDIR/compose.log" 2>&1; then
      falha "docker run do $mod (imagem $IMAGEM) — ver $LOGDIR/compose.log"
      return 1
    fi
  fi
}

host_vivo() {
  if [ "$MODO" = node ]; then [ -n "$HOST_PID" ] && kill -0 "$HOST_PID" 2>/dev/null
  else container_rodando "$HOST_CTR"; fi
}

host_logs() {
  if [ "$MODO" = node ]; then cat "$HOST_LOG" 2>/dev/null
  else docker logs "$HOST_CTR" 2>&1; fi
}

# Runs node -e <js> in the SAME network and file environment as the module
# on the host.
# host_node <js> VAR=value...
host_node() {
  local js=$1 kv; shift
  if [ "$MODO" = node ]; then
    ( cd "$HOST_DIR" && env "$@" node -e "$js" )
  else
    local e=()
    for kv in "$@"; do e+=(-e "$kv"); done
    docker exec ${e[@]+"${e[@]}"} -w /app "$HOST_CTR" node -e "$js"
  fi
}

arvore() { local p=$1 c; echo "$p"; for c in $(pgrep -P "$p" 2>/dev/null); do arvore "$c"; done; }

host_stop() {
  [ -n "$HOST_MOD" ] || return 0
  if [ "$MODO" = node ]; then
    if [ -n "$HOST_PID" ]; then
      local pids i=0
      pids=$(arvore "$HOST_PID")
      kill -TERM $pids 2>/dev/null
      while [ "$i" -lt 20 ] && kill -0 $pids 2>/dev/null; do sleep 0.5; i=$((i + 1)); done
      kill -KILL $pids 2>/dev/null
      wait "$HOST_PID" 2>/dev/null
    fi
    [ -n "$HOST_DIR" ] && rm -rf "$HOST_DIR"
  else
    docker logs "$HOST_CTR" >"$HOST_LOG" 2>&1
    docker stop -t 10 "$HOST_CTR" >/dev/null 2>&1
    docker rm -f "$HOST_CTR" >/dev/null 2>&1
  fi
  echo "  ...   $HOST_MOD do host encerrado (log: $HOST_LOG)"
  # Leaves the registry.
  local m resto=""
  for m in $HOST_LISTA; do [ "$m" = "$HOST_MOD" ] || resto="${resto:+$resto }$m"; done
  HOST_LISTA=$resto
  unset "REG_PID[$HOST_MOD]" "REG_DIR[$HOST_MOD]" "REG_CTR[$HOST_MOD]" "REG_LOG[$HOST_MOD]"
  HOST_MOD=""; HOST_PID=""; HOST_DIR=""; HOST_CTR=""
}

# Stops every module on the host, from the last one started to the first.
host_stop_todos() {
  local m lista=""
  for m in $HOST_LISTA; do lista="$m${lista:+ $lista}"; done
  for m in $lista; do host_usar "$m" && host_stop; done
  # A current module outside the registry (there should be none); no-op if
  # empty.
  host_stop
}

# Waits for the module on the host to answer; fails early if the process
# dies.
# esperar_modulo <description> <url> <pattern>
esperar_modulo() {
  local desc=$1 url=$2 pad=$3 t0=$SECONDS r=""
  while [ $((SECONDS - t0)) -lt "$TIMEOUT" ]; do
    r=$(resposta "$url")
    if printf '%s' "$r" | grep -q -e "$pad"; then ok "$desc ($((SECONDS - t0))s)"; return 0; fi
    if ! host_vivo; then
      falha "$desc — o processo do host morreu"; host_logs | tail -n 30 | sed 's/^/    | /'
      return 1
    fi
    sleep 3
  done
  falha "$desc — sem resposta em ${TIMEOUT}s"; host_logs | tail -n 30 | sed 's/^/    | /'
  return 1
}

# checar_log <description> <regex>: evidence from the module itself.
checar_log() {
  local i=0
  while [ "$i" -lt 10 ]; do
    if host_logs | grep -qE -e "$2"; then ok "$1"; return 0; fi
    i=$((i + 1)); sleep 1
  done
  falha "$1 — log sem /$2/"; return 1
}

# host -> Redis: PING over a raw socket, from the environment of the module
# (no dependency).
JS_REDIS='const s=require("net").connect(6379,"127.0.0.1");
const t=setTimeout(()=>{console.log("timeout");process.exit(1)},4000);
s.on("connect",()=>s.write("PING\r\n"));
s.on("data",d=>{const r=d.toString().trim();console.log(r);clearTimeout(t);s.destroy();process.exit(r==="+PONG"?0:1)});
s.on("error",e=>{console.log(e.message);process.exit(1)});'

# host -> MQTT: subscribes and publishes on its own topic with the mqtt
# library of the module.
JS_MQTT='const mqtt=require("mqtt");const tp="tv30/devhost/probe/"+process.pid+"-"+Date.now();
const c=mqtt.connect("mqtt://127.0.0.1:1883",{connectTimeout:4000,reconnectPeriod:0});
const t=setTimeout(()=>{console.log("timeout");process.exit(1)},8000);
c.on("connect",()=>c.subscribe(tp,e=>{if(e){console.log(e.message);process.exit(1)}c.publish(tp,"ping")}));
c.on("message",(x,m)=>{if(m.toString()==="ping"){console.log("pub/sub ok em "+tp);clearTimeout(t);c.end(true,()=>process.exit(0))}});
c.on("error",e=>{console.log(e.message);process.exit(1)});'

# HS256 accessToken with the same claims tv3ws issues (manager.ts).
JS_TOKEN='const c=require("crypto");const b=o=>Buffer.from(JSON.stringify(o)).toString("base64url");
const n=Math.floor(Date.now()/1000);
const h=b({alg:"HS256",typ:"JWT"}),p=b({iat:n,nbf:n,exp:n+600,iss:process.env.ISS,sub:"tv30-devhost-teste",class:"local-autonomous"});
process.stdout.write(h+"."+p+"."+c.createHmac("sha256",process.env.SEC).update(h+"."+p).digest("base64url"));'

# Both checks run in the environment of the CURRENT module; the label says
# which one (useful when there is more than one on the host, scenario 4).
checar_redis_host() {
  local r
  if r=$(host_node "$JS_REDIS" 2>&1); then ok "host ($HOST_MOD) -> Redis 127.0.0.1:6379 (PING: $r)"
  else falha "host ($HOST_MOD) -> Redis 127.0.0.1:6379 (PING: $(recorte "$r"))"; fi
}
# Requires the mqtt library of the module (tv3ws, aop and bcast have it; the
# component does not).
checar_mqtt_host() {
  local r
  if r=$(host_node "$JS_MQTT" 2>&1); then ok "host ($HOST_MOD) -> MQTT 127.0.0.1:1883 ($r)"
  else falha "host ($HOST_MOD) -> MQTT 127.0.0.1:1883 ($(recorte "$r"))"; fi
}
checar_redis_mqtt() { checar_redis_host; checar_mqtt_host; }

# GET /tv3/current-service through the edge, with the accessToken: the
# response must come from the Express of tv3ws (X-Powered-By). With a service
# in use, 200 with serviceContextId; without one (the case of scenario 1),
# 404 {"error":300} (C.6.3.1, Table C.8); either passes. It proves the path
# edge -> tv3ws on the host, NOT the shared JWT_SECRET: in warn the edge
# passes on even an invalid token. aop/currentService is not published to
# force the 200: the retained value would stay in the broker after the test.
# checar_current_service_host <token>
checar_current_service_host() {
  local desc="borda 44642 GET /tv3/current-service (Bearer assinado com o JWT_SECRET da borda) -> tv3ws no host"
  local i=0 h="" r=""
  while [ "$i" -lt 5 ]; do
    : >"$LOGDIR/current-service.body"
    h=$(curl -s -m 5 -D - -o "$LOGDIR/current-service.body" -H "Authorization: Bearer $1" \
          http://127.0.0.1:44642/tv3/current-service 2>/dev/null | tr -d '\r')
    r=$(cat "$LOGDIR/current-service.body" 2>/dev/null)
    if printf '%s' "$h" | grep -qi '^X-Powered-By: Express'; then
      if printf '%s' "$r" | grep -q '"serviceContextId"'; then
        ok "$desc: servico em uso, 200 com serviceContextId"; return 0
      fi
      if printf '%s' "$r" | grep -q '^{"error":300,'; then
        ok "$desc: sem servico em uso, 404 {error:300} do tv3ws (C.6.3.1)"; return 0
      fi
    fi
    i=$((i + 1)); sleep 2
  done
  falha "$desc — resposta: $(recorte "$r")"; return 1
}

# Edge (44642) -> tv3ws on the host: /health and GET /tv3/current-service
# with an HS256 accessToken signed in the environment of the tv3ws on the
# host, with the same JWT_SECRET as the edge. The tv3ws on the host must be
# the current module.
checar_borda_tv3ws_host() {
  checar_http "borda 44642 /health -> tv3ws no host" \
    http://127.0.0.1:44642/health '"status":"ok"' 15
  local tk h
  tk=$(host_node "$JS_TOKEN" SEC="$JWT_SECRET" ISS="$JWT_ISSUER" 2>/dev/null)
  if [ -n "$tk" ]; then
    checar_current_service_host "$tk"
    h=$(curl -s -m 5 -o /dev/null -D - -H "Authorization: Bearer $tk" \
          http://127.0.0.1:44642/tv3/current-service 2>/dev/null | tr -d '\r' | grep -i '^X-TV30-Auth-Warn:' || true)
    # The sub of the test token is not in clients:authorized: 107 even with
    # the right JWT_SECRET.
    info "X-TV30-Auth-Warn com token valido de cliente fora de clients:authorized (esperado 107): ${h:-ausente}"
  else
    falha "nao consegui gerar o accessToken de teste no ambiente do modulo"
  fi
  h=$(curl -s -m 5 -o /dev/null -D - http://127.0.0.1:44642/tv3/current-service 2>/dev/null \
        | tr -d '\r' | grep -i '^X-TV30-Auth-Warn:' || true)
  info "X-TV30-Auth-Warn sem token: ${h:-ausente} (em AUTH_ENFORCE=warn a borda deixa passar)"
}

# BALD of users-test retained in the broker, published by the bcast on the
# host: bcastEntryPackageUrl must carry the expected host:port.
# checar_bald <host:port>
checar_bald() {
  local r
  r=$(docker exec mqtt-broker mosquitto_sub -h localhost -t "tlm/sls/$SID_USERS_TEST/bald" -C 1 -W 5 2>/dev/null)
  if printf '%s' "$r" | grep -q -F -e "$1"; then
    ok "sinalizacao do bcast do host no broker (bcastEntryPackageUrl em $1)"
  else
    falha "sinalizacao do bcast do host no broker — esperado $1, lido: $(recorte "$r")"
  fi
}

# Opens the users-test application of bcast through the real flow of aop:
# selection in the catalog (subscribes to the signaling of the service) and
# full screen (startApp -> proxy target = bcastEntryPackageUrl of the BALD).
# The graphics layer opens the application on its own host,
# <label>.apps.localhost:8080/graphicsAppProxy/<path> (aop/src/app-hosts.js),
# and aop writes that origin to origins:associated. Closing = ESC
# (/keydown/27: closes the graphics layer and removes the origin) and back to
# the catalog; the catalog alone would leave the origin in Redis.
SID_USERS_TEST="urn:tv30:service:users-test"
abrir_users_test() {
  resposta "http://127.0.0.1:8080/appcat/select?id=$SID_USERS_TEST" >/dev/null
  sleep 2
  resposta "http://127.0.0.1:8080/btpapp/fullscr" >/dev/null
}
fechar_users_test() {
  resposta "http://127.0.0.1:8080/keydown/27" >/dev/null
  resposta "http://127.0.0.1:8080/btpapp/appcat" >/dev/null
}

# HOST_APP = host:port of the open application, read from the origin aop
# wrote to origins:associated; empty if none appeared in 10 s. The request
# goes to 127.0.0.1:8080 with that Host, without depending on the resolver
# of the test environment knowing *.localhost.
HOST_APP=""
checar_origem_app() {
  local o="" i=0
  HOST_APP=""
  while [ "$i" -lt 10 ]; do
    o=$(docker exec redis redis-cli --raw HKEYS origins:associated 2>/dev/null \
        | grep -m1 -E '^http://[a-z0-9-]+\.apps\.localhost:8080$')
    [ -n "$o" ] && break
    i=$((i + 1)); sleep 1
  done
  if [ -z "$o" ]; then
    falha "aop gravou a origem propria da app em origins:associated — nenhuma <rotulo>.apps.localhost:8080"
    return 1
  fi
  HOST_APP=${o#http://}
  ok "aop gravou a origem propria da app em origins:associated: $o"
}

# checar_mqtt_ws_aop <description>: the aop on the host serves the MQTT of
# the TV page over WebSocket on /mqtt and passes it on to mosquitto on the
# port Docker published (porta_ws_mqtt). 101 = the handshake reached the
# broker; an empty or wrong port would give 502.
checar_mqtt_ws_aop() {
  local r
  r=$(curl -s -i -N --max-time 3 -H "Connection: Upgrade" -H "Upgrade: websocket" \
        -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
        -H "Sec-WebSocket-Protocol: mqtt" http://127.0.0.1:8080/mqtt 2>/dev/null | head -1 | tr -d '\r')
  if printf '%s' "$r" | grep -q ' 101'; then ok "$1 (porta publicada da 9001: $(porta_ws_mqtt))"
  else falha "$1 — resposta: ${r:-nenhuma} (porta publicada da 9001: '$(porta_ws_mqtt)')"; fi
}

# checar_app_aberta <description>: the application answers on its own host,
# with the /graphicsAppProxy prefix (the URL the graphics layer opens), and
# the same path on the host of aop redirects (302) to that URL. Depends on
# HOST_APP.
checar_app_aberta() {
  [ -n "$HOST_APP" ] || return 1
  checar_http "$1 (host proprio da app)" \
    http://127.0.0.1:8080/graphicsAppProxy/users-test 'Trocar Usu' 10 -H "Host: $HOST_APP"
  checar_http "/graphicsAppProxy no host do aop -> 302 para o host da app" \
    http://127.0.0.1:8080/graphicsAppProxy/users-test "ocation: http://$HOST_APP/graphicsAppProxy/users-test" 5 -D -
}

# Component of scenario 5 (the example of templates/componente/index.js): a
# name of this test's own, so that a template container that is up
# (meu-componente) does not answer in place of the host process. Topic and
# key come from the name, as in index.js.
COMP_NOME="devhost-componente-$$"
COMP_TOPICO="tv30/$COMP_NOME/exemplo"
COMP_CHAVE="tv30:$COMP_NOME:exemplo"
COMP_PORTA=8090
# 1 when the test key may have been left in Redis.
COMP_SUJO=""

# ping_componente <value> <message> <wait_s>: writes <value> to the key of
# the example, publishes <message> on <topic>/ping and echoes the pong
# received (empty if none in <wait_s>). A test client in the broker
# container; the component is on the host.
ping_componente() {
  local val=$1 msg=$2 w=$3 out="$LOGDIR/pong-cenario$CEN" bg
  docker exec redis redis-cli SET "$COMP_CHAVE" "$val" >/dev/null 2>&1
  : >"$out"
  docker exec mqtt-broker mosquitto_sub -h localhost -C 1 -W "$w" -t "$COMP_TOPICO/pong" >"$out" 2>/dev/null &
  bg=$!
  sleep 1
  docker exec mqtt-broker mosquitto_pub -h localhost -t "$COMP_TOPICO/ping" -m "$msg" >/dev/null 2>&1
  wait "$bg" 2>/dev/null
  cat "$out"
}

limpar_componente() {
  [ -n "$COMP_SUJO" ] || return 0
  docker exec redis redis-cli DEL "$COMP_CHAVE" >/dev/null 2>&1 && COMP_SUJO=""
  return 0
}

# --------------------------------------------------------------- scenarios ---

cenario_1() {
  CEN=1
  titulo "CENARIO 1 — tv3ws no host | containers: infra (borda windows) + aop + bcast"
  parar tv3ws || return
  subir windows $INFRA aop bcast || return
  porta_livre 44654 || { falha "porta 44654 ja ocupada no host"; return; }
  local ud; ud=$(dir_userfiles)
  host_start tv3ws MQTT_HOST=127.0.0.1 REDIS_HOST=127.0.0.1 REDIS_PORT=6379 \
    HTTP_PORT=44654 HTTPS_PORT=44655 JWT_SECRET="$JWT_SECRET" JWT_ISSUER="$JWT_ISSUER" \
    USER_THUMBS="$ud/thumbs" \
    SERVER_URL="$SERVER_URL_CFG" WS_PORT_MIN=45000 WS_PORT_MAX=45199 LOG_LEVEL=INFO || return
  esperar_modulo "tv3ws no host respondendo em 44654/health" \
    http://127.0.0.1:44654/health '"status":"ok"' || { host_stop; return; }
  checar_redis_mqtt
  checar_log "tv3ws do host conectou no Redis do container" '\[redis\] pronto em 127\.0\.0\.1:6379'
  checar_log "tv3ws do host conectou no broker do container" 'Connected to MQTT broker'

  checar_borda_tv3ws_host

  host_stop
  checar_http_nao "sem o tv3ws do host a borda para de responder /health (resposta vinha do host)" \
    http://127.0.0.1:44642/health '"status":"ok"' 10
}

cenario_2() {
  CEN=2
  titulo "CENARIO 2 — aop no host | containers: infra (borda linux) + tv3ws + bcast"
  parar aop || return
  # bcast announces bcastEntryPackageUrl = http://BCAST_HOSTNAME:8081 (the
  # INTERNAL port). For the aop on the host, that is localhost:8081 published
  # by the container, so 8081 is published FIXED here (BCAST_PUBLISH; by
  # default it gets any free port).
  BCAST_HOSTNAME=localhost BCAST_PUBLISH=8081:8081 subir linux $INFRA tv3ws bcast || return
  porta_livre 8080 || { falha "porta 8080 ja ocupada no host"; return; }
  host_start aop PORT=8080 MQTT_HOST=127.0.0.1 MQTT_WS_PORT="$(porta_ws_mqtt)" \
    USER_DATA_PATH="$(dir_userfiles)" REDIS_HOST=127.0.0.1 REDIS_PORT=6379 || return
  esperar_modulo "aop no host servindo 8080" \
    http://127.0.0.1:8080/appcat 'HTTP_STATUS=200' || { host_stop; return; }
  checar_redis_mqtt
  checar_log "aop do host leu os perfis no Redis do container" 'Loaded [0-9]+ users from Redis'
  checar_log "aop do host conectou no broker do container" 'Connected to MQTT broker'
  checar_http "aop do host recebeu o BAMT do bcast em container (MQTT)" \
    http://127.0.0.1:8080/appcat 'Trocar Usu' 15
  abrir_users_test
  checar_origem_app && checar_app_aberta "aop do host -> bcast em container"
  checar_mqtt_ws_aop "aop do host -> mosquitto em container pelo WebSocket /mqtt"
  fechar_users_test
  checar_http "borda (linux) 44642 /health -> tv3ws em container" \
    http://127.0.0.1:44642/health '"status":"ok"' 30 || diag_container tv3ws
  host_stop
}

cenario_3() {
  CEN=3
  titulo "CENARIO 3 — bcast no host | containers: infra (borda linux) + tv3ws + aop"
  parar bcast || return
  subir linux $INFRA tv3ws aop || return
  if [ "$(docker inspect -f '{{join .HostConfig.ExtraHosts ","}}' aop 2>/dev/null)" = "" ]; then
    info "o container aop nao tem extra_hosts (host.docker.internal): compose antigo?"
  fi
  porta_livre 8081 || { falha "porta 8081 ja ocupada no host"; return; }
  host_start bcast PORT=8081 MQTT_HOST=127.0.0.1 BCAST_HOSTNAME=host.docker.internal \
    BSID=tv30-default WEBMEDIA_SID=urn:tv30:service:webmedia \
    UFF_SID=urn:tv30:service:uff EDUPLAY_SID=urn:tv30:service:eduplay || return
  esperar_modulo "bcast no host servindo 8081" \
    http://127.0.0.1:8081/users-test 'Trocar Usu' || { host_stop; return; }
  checar_redis_mqtt
  checar_log "bcast do host conectou no broker do container" 'MQTT client connected'
  checar_bald host.docker.internal:8081
  checar_http "aop em container recebeu o BAMT do bcast no host (MQTT)" \
    http://127.0.0.1:8080/appcat 'Trocar Usu' 15
  abrir_users_test
  checar_origem_app && checar_app_aberta "aop em container -> bcast no host (via host.docker.internal)"
  host_stop
  [ -n "$HOST_APP" ] && checar_http_nao "sem o bcast do host o proxy do aop falha (resposta vinha do host)" \
    http://127.0.0.1:8080/graphicsAppProxy/users-test 'Trocar Usu' 5 -H "Host: $HOST_APP"
  fechar_users_test
}

cenario_4() {
  CEN=4
  titulo "CENARIO 4 — tv3ws, aop e bcast no host | containers: infra (borda windows)"
  parar tv3ws || return
  parar aop || return
  parar bcast || return
  subir windows $INFRA || return
  local p ud
  for p in 44654 8080 8081; do
    porta_livre "$p" || { falha "porta $p ja ocupada no host"; return; }
  done
  ud=$(dir_userfiles)

  # tv3ws: the same variables as scenario 1 (the windows edge looks for
  # 44654).
  host_start tv3ws MQTT_HOST=127.0.0.1 REDIS_HOST=127.0.0.1 REDIS_PORT=6379 \
    HTTP_PORT=44654 HTTPS_PORT=44655 JWT_SECRET="$JWT_SECRET" JWT_ISSUER="$JWT_ISSUER" \
    USER_THUMBS="$ud/thumbs" \
    SERVER_URL="$SERVER_URL_CFG" WS_PORT_MIN=45000 WS_PORT_MAX=45199 LOG_LEVEL=INFO || return
  esperar_modulo "tv3ws no host respondendo em 44654/health" \
    http://127.0.0.1:44654/health '"status":"ok"' || return

  # bcast before aop: the BALD retained in the broker already carries the
  # address of the host. The one that follows bcastEntryPackageUrl is aop,
  # also on the host: 127.0.0.1:8081 (the port of the process itself;
  # 127.0.0.1 and not localhost so as not to depend on IPv6 resolution).
  host_start bcast PORT=8081 MQTT_HOST=127.0.0.1 BCAST_HOSTNAME=127.0.0.1 \
    BSID=tv30-default WEBMEDIA_SID=urn:tv30:service:webmedia \
    UFF_SID=urn:tv30:service:uff EDUPLAY_SID=urn:tv30:service:eduplay || return
  esperar_modulo "bcast no host servindo 8081" \
    http://127.0.0.1:8081/users-test 'Trocar Usu' || return

  host_start aop PORT=8080 MQTT_HOST=127.0.0.1 MQTT_WS_PORT="$(porta_ws_mqtt)" \
    USER_DATA_PATH="$ud" REDIS_HOST=127.0.0.1 REDIS_PORT=6379 || return
  esperar_modulo "aop no host servindo 8080" \
    http://127.0.0.1:8080/appcat 'HTTP_STATUS=200' || return
  info "no host ao mesmo tempo: $HOST_LISTA"

  # host -> Redis/MQTT from the environment of EACH module, and the
  # connection logs.
  host_usar tv3ws || return
  checar_redis_mqtt
  checar_log "tv3ws do host conectou no Redis do container" '\[redis\] pronto em 127\.0\.0\.1:6379'
  checar_log "tv3ws do host conectou no broker do container" 'Connected to MQTT broker'
  host_usar bcast || return
  checar_redis_mqtt
  checar_log "bcast do host conectou no broker do container" 'MQTT client connected'
  host_usar aop || return
  checar_redis_mqtt
  checar_log "aop do host leu os perfis no Redis do container" 'Loaded [0-9]+ users from Redis'
  checar_log "aop do host conectou no broker do container" 'Connected to MQTT broker'

  # Edge (container) -> tv3ws on the host.
  host_usar tv3ws || return
  checar_borda_tv3ws_host

  # bcast on the host -> broker -> aop on the host, and aop on the host ->
  # bcast on the host.
  checar_bald 127.0.0.1:8081
  checar_http "aop do host recebeu o BAMT do bcast do host (MQTT)" \
    http://127.0.0.1:8080/appcat 'Trocar Usu' 15
  abrir_users_test
  checar_origem_app && checar_app_aberta "aop do host -> bcast do host"
  checar_mqtt_ws_aop "aop do host -> mosquitto em container pelo WebSocket /mqtt"

  # Negative proofs: each response came from the host process.
  host_usar bcast && host_stop
  [ -n "$HOST_APP" ] && checar_http_nao "sem o bcast do host o proxy do aop do host falha (resposta vinha do bcast do host)" \
    http://127.0.0.1:8080/graphicsAppProxy/users-test 'Trocar Usu' 5 -H "Host: $HOST_APP"
  fechar_users_test
  host_usar tv3ws && host_stop
  checar_http_nao "sem o tv3ws do host a borda para de responder /health (resposta vinha do host)" \
    http://127.0.0.1:44642/health '"status":"ok"' 10
  host_usar aop && host_stop
}

cenario_5() {
  CEN=5
  titulo "CENARIO 5 — componente novo no host (templates/componente) | containers: redis, mosquitto (borda parada)"
  subir linux redis mosquitto || return
  # Proof that the path does not go through the edge: it stays stopped during
  # the scenario (another scenario or the restore brings it back).
  parar edgegateway "a borda fica fora do caminho: o componente fala direto com Redis e broker" || return
  porta_livre "$COMP_PORTA" || {
    falha "porta $COMP_PORTA ja ocupada no host (container meu-componente do template de pe?)"; return; }
  host_start componente COMPONENTE_NOME="$COMP_NOME" MQTT_HOST=127.0.0.1 MQTT_PORT=1883 \
    REDIS_HOST=127.0.0.1 REDIS_PORT=6379 PORT="$COMP_PORTA" || return
  esperar_modulo "componente no host respondendo em $COMP_PORTA/health (so abre com Redis e broker conectados)" \
    "http://127.0.0.1:$COMP_PORTA/health" '"status":"ok"' || return
  checar_redis_host
  checar_log "componente do host falou com o Redis do container por 127.0.0.1" \
    '\['"$COMP_NOME"'\] redis 127\.0\.0\.1:6379 PING -> PONG'
  checar_log "componente do host conectou no broker do container por 127.0.0.1" \
    '\['"$COMP_NOME"'\] mqtt 127\.0\.0\.1:1883 conectado'

  # Ping through the broker; the component reads the key in Redis and answers
  # on /pong.
  local i=0 val="" msg="" r=""
  COMP_SUJO=1
  while [ "$i" -lt 3 ]; do
    val="v-$$-$RANDOM"; msg="ping-$$-$RANDOM"
    r=$(ping_componente "$val" "$msg" 10)
    if printf '%s' "$r" | grep -q -F -e "\"ping\":\"$msg\"" \
       && printf '%s' "$r" | grep -q -F -e "\"valor\":\"$val\""; then break; fi
    i=$((i + 1))
  done
  if [ "$i" -lt 3 ]; then
    ok "ping em $COMP_TOPICO/ping voltou em /pong com o valor gravado agora no Redis (pub/sub e leitura do componente)"
  else
    falha "ping/pong do componente — esperado ping=$msg e valor=$val, recebido: $(recorte "$r")"
  fi
  checar_log "o proprio componente do host registrou o ping respondido" '\['"$COMP_NOME"'\] ping .* -> pong'

  host_stop
  r=$(ping_componente "v-$$-fim" "ping-$$-fim" 5)
  if [ -z "$r" ]; then ok "sem o componente do host o ping fica sem pong (a resposta vinha do host)"
  else falha "pong recebido com o componente do host encerrado: $(recorte "$r")"; fi
  limpar_componente
}

# ------------------------------------------------------------------ restore ---

RESTAURADO=""
restaurar() {
  [ -z "$RESTAURADO" ] || return 0
  RESTAURADO=1
  host_stop_todos
  # Test key of scenario 5, if it was interrupted.
  limpar_componente
  CEN="-"
  if [ -n "${ANTES// /}" ]; then
    titulo "restaurando a stack padrao (EDGE_VARIANT=linux; COMPOSE_FILE do .env)"
    if EDGE_VARIANT=linux compose_env up -d >>"$LOGDIR/compose.log" 2>&1; then
      echo "  ok    stack padrao de pe"
    else
      echo "  ERRO  falha ao restaurar (ver $LOGDIR/compose.log)"
    fi
  else
    titulo "a stack nao estava de pe antes do teste: docker compose down"
    compose_env down >>"$LOGDIR/compose.log" 2>&1 || echo "  ERRO  falha no down (ver $LOGDIR/compose.log)"
  fi
}
trap 'restaurar' EXIT
# HUP too: closing the session (e.g. wsl.exe ended on the Windows side)
# sends SIGHUP, which without a trap would kill the script without restoring.
trap 'echo; echo "interrompido"; exit 130' INT TERM HUP

# --------------------------------------------------------------------- main ---

echo "TV30 — teste dev-host: cenarios [$CENARIOS], modo $MODO$( [ "$MODO" = docker ] && echo " ($IMAGEM)")"
echo "stack antes do teste: ${ANTES:-nada rodando}"
echo "logs: $LOGDIR"

for n in $CENARIOS; do
  "cenario_$n"
  host_stop_todos
done

restaurar

titulo "RESUMO ($PASS PASS, $FAIL FAIL)"
for l in ${RESUMO[@]+"${RESUMO[@]}"}; do echo "  $l"; done
echo "logs dos modulos e do compose: $LOGDIR"
[ "$FAIL" -eq 0 ]
