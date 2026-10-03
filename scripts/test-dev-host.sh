#!/bin/bash
# Teste do cenario de desenvolvimento (reunioes 21/09 e 28/09): sobe o MINIMO
# de containers e roda um modulo REAL (tv3ws, aop ou bcast) fora do Docker,
# com `npm ci && npm run dev`, verificando a comunicacao host <-> rede do
# Docker em tres combinacoes:
#
#   1  tv3ws no host | containers: redis, mosquitto, edgegateway (variante
#      windows: backends em host.docker.internal:44654/44655), aop, bcast
#   2  aop no host   | containers: redis, mosquitto, edgegateway (variante
#      linux), tv3ws, bcast (BCAST_HOSTNAME=localhost, BCAST_PORT=8081)
#   3  bcast no host | containers: redis, mosquitto, edgegateway (variante
#      linux), tv3ws, aop (alcanca o host por host.docker.internal)
#
# Todo cenario verifica host->Redis (PING) e host->MQTT (pub/sub) a partir do
# MESMO ambiente em que o modulo roda, os logs de conexao do proprio modulo e
# o caminho especifico:
#   1  borda (44642) -> tv3ws no host: /health e GET /tv3/current-service com
#      accessToken HS256 assinado com o mesmo JWT_SECRET da borda; depois de
#      matar o processo do host a borda deixa de responder (prova negativa)
#   2  aop no host servindo 8080, recebendo o BAMT do bcast por MQTT e
#      alcancando o bcast em container pelo proxy HTTP (/graphicsAppProxy)
#   3  bcast no host publicando a sinalizacao (bcastEntryPackageUrl com
#      host.docker.internal) e o aop em container alcancando o bcast do host
#      pelo proxy HTTP; depois de matar o processo do host o proxy falha
#
# Ao fim de cada cenario o processo do host morre. No fim de tudo a stack
# padrao (EDGE_VARIANT=linux) e restaurada se estava de pe antes do teste, ou
# derrubada (docker compose down) se nao estava.
#
# "Host" = processo na rede do host. Duas formas (DEVHOST_MODO):
#   node    node/npm do PATH, numa copia temporaria do modulo (sem
#           node_modules/.env; public/ entra como link)
#   docker  docker run --network host <imagem node> com o modulo montado
#           somente-leitura em /src e copiado para /app: rede identica a do
#           host, para maquinas sem node (ex.: WSL deste projeto)
#   auto    node se houver node Linux no PATH, senao docker (padrao)
#
# Uso: ./scripts/test-dev-host.sh [--cenario N[,N...]] [--build] [-h]
#   --cenario  1, 2 e/ou 3 (padrao: todos, em ordem)
#   --build    repassa --build ao docker compose up (ex.: borda com plugin novo)
#
# Variaveis opcionais:
#   DEVHOST_MODO     auto | node | docker            (padrao auto)
#   DEVHOST_IMAGEM   imagem node do modo docker      (padrao node:23-alpine,
#                    a mesma base de infra/dockerfiles/*.Dockerfile)
#   DEVHOST_TIMEOUT  segundos para o modulo responder (padrao 300; inclui o
#                    npm ci no modo docker)
#   JWT_SECRET, JWT_ISSUER, MQTT_WS_PORT, SERVER_URL: shell > .env da raiz >
#                    padrao do compose. O JWT_SECRET vale para a borda e para
#                    o tv3ws do host (os dois precisam do mesmo segredo).
#   Proxy/registro npm (HTTP_PROXY, HTTPS_PROXY, NO_PROXY,
#   NPM_CONFIG_REGISTRY, NPM_CONFIG_STRICT_SSL) sao repassados ao container.
#
# Linux nativo e WSL2 com Docker Engine no proprio WSL. Windows nativo (Git
# Bash/PowerShell com Docker no WSL) NAO e coberto: host-gateway aponta para
# a VM do WSL, nao para o Windows. Ver docs/dev-local.md.
set -u
cd "$(dirname "$0")/.." || exit 2
ROOT=$(pwd)

uso() { sed -n '2,/^set -u/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; }

CENARIOS="1 2 3"
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
  case "$n" in 1|2|3) ;; *) echo "cenario invalido: $n (use 1, 2 ou 3)"; exit 2 ;; esac
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

# ---------------------------------------------------------------- config ---

# valor de uma variavel no .env da raiz (sem aspas); vazio se ausente
dotenv_get() {
  [ -f .env ] || return 0
  sed -n "s/^[[:space:]]*$1=//p" .env | tail -n 1 | tr -d '\r' \
    | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}
# precedencia: shell > .env da raiz > padrao (a mesma do docker compose)
cfg() {
  local v="${!1:-}"
  [ -n "$v" ] || v=$(dotenv_get "$1")
  [ -n "$v" ] || v=$2
  printf '%s' "$v"
}

# Exportados: o compose (borda e tv3ws em container) e o tv3ws do host leem o
# MESMO valor — a borda valida o accessToken que o tv3ws assina.
JWT_SECRET=$(cfg JWT_SECRET tv30-dev-secret-nao-usar-em-producao); export JWT_SECRET
JWT_ISSUER=$(cfg JWT_ISSUER GenericIssuer); export JWT_ISSUER
MQTT_WS_PORT_CFG=$(cfg MQTT_WS_PORT 9001)
SERVER_URL_CFG=$(cfg SERVER_URL localhost)

TIMEOUT=${DEVHOST_TIMEOUT:-300}
IMAGEM=${DEVHOST_IMAGEM:-node:23-alpine}
MODO=${DEVHOST_MODO:-auto}
if [ "$MODO" = auto ]; then
  # node.exe/npm do Windows visiveis pelo PATH do WSL (/mnt/...) rodariam na
  # rede do WINDOWS, nao na do Docker: nesse caso vai o modo docker.
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

# Toda chamada ao compose ativa os dois profiles: tv3ws/aop/bcast/sysctl-init
# tem profile "linux" e o mosquitto "mqtt" (sem eles, clone sem .env nao os ve).
compose() { docker compose --profile mqtt --profile linux "$@"; }

# Infra basica + one-shots que ela precisa (o preflight vem como dependencia
# do edgegateway; userfiles-seed cria ./user-files para o modulo do host).
INFRA="redis mosquitto edgegateway userfiles-seed"

# Servicos da stack que estavam rodando antes do teste (define a restauracao).
ANTES=$(docker ps --filter label=com.docker.compose.project=tv30 \
          --format '{{.Label "com.docker.compose.service"}}' 2>/dev/null | sort -u | tr '\n' ' ')

# ------------------------------------------------------------- relatorio ---

CEN="-"
PASS=0
FAIL=0
RESUMO=()
ok()     { PASS=$((PASS + 1)); RESUMO+=("PASS  [cenario $CEN] $1"); echo "  PASS  $1"; }
falha()  { FAIL=$((FAIL + 1)); RESUMO+=("FAIL  [cenario $CEN] $1"); echo "  FAIL  $1"; }
info()   { echo "  info  $1"; }
titulo() { echo; echo "=================================================================="; echo "$1"; echo "=================================================================="; }

# corpo da resposta + linha final HTTP_STATUS=<codigo> (padroes podem casar com os dois)
resposta() { curl -s -m 5 -w '\nHTTP_STATUS=%{http_code}' "$@" 2>/dev/null; }
recorte()  { printf '%s' "$1" | tr '\n' ' ' | cut -c1-200; }

# checar_http <descricao> <url> <padrao> <tentativas> [args do curl...]
checar_http() {
  local desc=$1 url=$2 pad=$3 n=$4 i=0 r=""; shift 4
  while [ "$i" -lt "$n" ]; do
    r=$(resposta "$@" "$url")
    if printf '%s' "$r" | grep -q -e "$pad"; then ok "$desc"; return 0; fi
    i=$((i + 1)); sleep 2
  done
  falha "$desc — resposta: $(recorte "$r")"; return 1
}

# checar_http_nao <descricao> <url> <padrao> <tentativas>: passa quando o
# padrao DEIXA de aparecer (prova de que a resposta vinha do processo do host)
checar_http_nao() {
  local desc=$1 url=$2 pad=$3 n=$4 i=0 r=""
  while [ "$i" -lt "$n" ]; do
    r=$(resposta "$url")
    if ! printf '%s' "$r" | grep -q -e "$pad"; then ok "$desc"; return 0; fi
    i=$((i + 1)); sleep 2
  done
  falha "$desc — ainda responde: $(recorte "$r")"; return 1
}

porta_livre() { ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

container_rodando() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }

# estado e fim do log de um container, quando uma verificacao que depende
# dele falha (o container pode ser recriado depois e levar o log junto)
diag_container() {
  info "$1: $(docker inspect -f 'status={{.State.Status}} reinicios={{.RestartCount}} inicio={{.State.StartedAt}}' "$1" 2>&1)"
  docker logs --tail 15 "$1" 2>&1 | sed 's/^/    | /'
}

subir() { # subir <EDGE_VARIANT> <servicos...> (variaveis extras: prefixo VAR=valor na chamada)
  local variante=$1; shift
  echo "  ...   docker compose up -d $* (EDGE_VARIANT=$variante)"
  if ! EDGE_VARIANT=$variante compose up -d $BUILD "$@" >>"$LOGDIR/compose.log" 2>&1; then
    falha "docker compose up -d $* (ver $LOGDIR/compose.log)"
    tail -n 15 "$LOGDIR/compose.log" | sed 's/^/    | /'
    return 1
  fi
}

parar() { # parar <servico>: o modulo do host nao pode coexistir com o container
  # (mesma porta e mesmo clientId MQTT fixo: tv3ws-client, aop-core, bcast_svc)
  compose stop "$1" >>"$LOGDIR/compose.log" 2>&1 || true
  if container_rodando "$1"; then falha "container $1 continua rodando"; return 1; fi
  ok "container $1 parado (o modulo roda so no host)"
}

# ------------------------------------------------------ processo do host ---

HOST_MOD=""; HOST_PID=""; HOST_DIR=""; HOST_CTR=""; HOST_LOG=""

copiar_modulo() { # copiar_modulo <origem> <destino>
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

# mesma copia, dentro do container do modo docker (sh do alpine)
COPIA_SH='mkdir -p /app && cd /src && for f in * .[!.]* ..?*; do [ -e "$f" ] || continue; case "$f" in node_modules|.env|.git|public) ;; *) cp -R "$f" /app/ ;; esac; done; if [ -d /src/public ]; then ln -s /src/public /app/public; fi'

# Diretorio de user-files visto pelo modulo do host
dir_userfiles() { if [ "$MODO" = node ]; then printf '%s' "$ROOT/user-files"; else printf '/user-files'; fi; }

host_start() { # host_start <modulo> VAR=valor...
  local mod=$1 kv; shift
  HOST_MOD=$mod
  HOST_LOG="$LOGDIR/cenario$CEN-$mod.log"
  echo "  ...   $mod no host (modo $MODO): $(printf '%s ' "$@" | sed -E 's/(JWT_SECRET=)[^ ]*/\1***/')npm run dev"
  if [ "$MODO" = node ]; then
    HOST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tv30-devhost-$mod.XXXXXX")
    copiar_modulo "$ROOT/$mod" "$HOST_DIR"
    echo "  ...   npm ci em $HOST_DIR"
    if ! ( cd "$HOST_DIR" && npm ci --include=dev --no-audit --no-fund ) >"$HOST_LOG" 2>&1; then
      falha "npm ci ($mod) — ver $HOST_LOG"; tail -n 20 "$HOST_LOG" | sed 's/^/    | /'
      return 1
    fi
    ( cd "$HOST_DIR" && exec env "$@" npm run dev ) >>"$HOST_LOG" 2>&1 &
    HOST_PID=$!
  else
    HOST_CTR="tv30-devhost-$mod"
    docker rm -f "$HOST_CTR" >/dev/null 2>&1
    local envs=()
    for kv in "$@"; do envs+=(-e "$kv"); done
    for kv in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy \
              NPM_CONFIG_REGISTRY NPM_CONFIG_STRICT_SSL npm_config_registry npm_config_strict_ssl; do
      if [ -n "${!kv:-}" ]; then envs+=(-e "$kv"); fi
    done
    if ! docker run -d --init --name "$HOST_CTR" --network host \
           -v "$ROOT/$mod:/src:ro" -v "$ROOT/user-files:/user-files" \
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

# executa node -e <js> no MESMO ambiente de rede/arquivos do modulo do host
host_node() { # host_node <js> VAR=valor...
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
  HOST_MOD=""; HOST_PID=""; HOST_DIR=""; HOST_CTR=""
}

# espera o modulo do host responder; falha cedo se o processo morrer
esperar_modulo() { # esperar_modulo <descricao> <url> <padrao>
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

checar_log() { # checar_log <descricao> <regex>: evidencia vinda do proprio modulo
  local i=0
  while [ "$i" -lt 10 ]; do
    if host_logs | grep -qE -e "$2"; then ok "$1"; return 0; fi
    i=$((i + 1)); sleep 1
  done
  falha "$1 — log sem /$2/"; return 1
}

# host -> Redis: PING por socket cru, do ambiente do modulo (sem dependencia)
JS_REDIS='const s=require("net").connect(6379,"127.0.0.1");
const t=setTimeout(()=>{console.log("timeout");process.exit(1)},4000);
s.on("connect",()=>s.write("PING\r\n"));
s.on("data",d=>{const r=d.toString().trim();console.log(r);clearTimeout(t);s.destroy();process.exit(r==="+PONG"?0:1)});
s.on("error",e=>{console.log(e.message);process.exit(1)});'

# host -> MQTT: assina e publica num topico proprio com a lib mqtt do modulo
JS_MQTT='const mqtt=require("mqtt");const tp="tv30/devhost/probe/"+process.pid+"-"+Date.now();
const c=mqtt.connect("mqtt://127.0.0.1:1883",{connectTimeout:4000,reconnectPeriod:0});
const t=setTimeout(()=>{console.log("timeout");process.exit(1)},8000);
c.on("connect",()=>c.subscribe(tp,e=>{if(e){console.log(e.message);process.exit(1)}c.publish(tp,"ping")}));
c.on("message",(x,m)=>{if(m.toString()==="ping"){console.log("pub/sub ok em "+tp);clearTimeout(t);c.end(true,()=>process.exit(0))}});
c.on("error",e=>{console.log(e.message);process.exit(1)});'

# accessToken HS256 com as mesmas claims que o tv3ws emite (manager.ts)
JS_TOKEN='const c=require("crypto");const b=o=>Buffer.from(JSON.stringify(o)).toString("base64url");
const n=Math.floor(Date.now()/1000);
const h=b({alg:"HS256",typ:"JWT"}),p=b({iat:n,nbf:n,exp:n+600,iss:process.env.ISS,sub:"tv30-devhost-teste",class:"local-autonomous"});
process.stdout.write(h+"."+p+"."+c.createHmac("sha256",process.env.SEC).update(h+"."+p).digest("base64url"));'

checar_redis_mqtt() {
  local r
  if r=$(host_node "$JS_REDIS" 2>&1); then ok "host -> Redis 127.0.0.1:6379 (PING: $r)"
  else falha "host -> Redis 127.0.0.1:6379 (PING: $(recorte "$r"))"; fi
  if r=$(host_node "$JS_MQTT" 2>&1); then ok "host -> MQTT 127.0.0.1:1883 ($r)"
  else falha "host -> MQTT 127.0.0.1:1883 ($(recorte "$r"))"; fi
}

# Abre o app users-test do bcast pelo fluxo real do aop: selecao no catalogo
# (assina a sinalizacao do servico) e tela cheia (startApp -> graphicsAppURL
# = bcastEntryPackageUrl da BALD). Depois /graphicsAppProxy/... vai ao bcast.
SID_USERS_TEST="urn:tv30:service:users-test"
abrir_users_test() {
  resposta "http://127.0.0.1:8080/appcat/select?id=$SID_USERS_TEST" >/dev/null
  sleep 2
  resposta "http://127.0.0.1:8080/btpapp/fullscr" >/dev/null
}
fechar_users_test() { resposta "http://127.0.0.1:8080/btpapp/appcat" >/dev/null; }

# ------------------------------------------------------------- cenarios ---

cenario_1() {
  CEN=1
  titulo "CENARIO 1 — tv3ws no host | containers: infra (borda windows) + aop + bcast"
  parar tv3ws || return
  subir windows $INFRA aop bcast || return
  porta_livre 44654 || { falha "porta 44654 ja ocupada no host"; return; }
  local ud; ud=$(dir_userfiles)
  host_start tv3ws MQTT_HOST=127.0.0.1 REDIS_HOST=127.0.0.1 REDIS_PORT=6379 \
    HTTP_PORT=44654 HTTPS_PORT=44655 JWT_SECRET="$JWT_SECRET" JWT_ISSUER="$JWT_ISSUER" \
    USER_DATA_FILE="$ud/userData.json" USER_THUMBS="$ud/thumbs" \
    SERVER_URL="$SERVER_URL_CFG" WS_PORT_MIN=45000 WS_PORT_MAX=45199 LOG_LEVEL=INFO || return
  esperar_modulo "tv3ws no host respondendo em 44654/health" \
    http://127.0.0.1:44654/health '"status":"ok"' || { host_stop; return; }
  checar_redis_mqtt
  checar_log "tv3ws do host conectou no Redis do container" '\[Redis\] Connected'
  checar_log "tv3ws do host conectou no broker do container" 'Connected to MQTT broker'

  checar_http "borda 44642 /health -> tv3ws no host" \
    http://127.0.0.1:44642/health '"status":"ok"' 15
  local tk h
  tk=$(host_node "$JS_TOKEN" SEC="$JWT_SECRET" ISS="$JWT_ISSUER" 2>/dev/null)
  if [ -n "$tk" ]; then
    checar_http "borda 44642 GET /tv3/current-service (Bearer, JWT_SECRET compartilhado) -> tv3ws no host" \
      http://127.0.0.1:44642/tv3/current-service '"serviceContextId"' 5 -H "Authorization: Bearer $tk"
    h=$(curl -s -m 5 -o /dev/null -D - -H "Authorization: Bearer $tk" \
          http://127.0.0.1:44642/tv3/current-service 2>/dev/null | tr -d '\r' | grep -i '^X-TV30-Auth-Warn:' || true)
    info "X-TV30-Auth-Warn com token valido: ${h:-ausente}"
  else
    falha "nao consegui gerar o accessToken de teste no ambiente do modulo"
  fi
  h=$(curl -s -m 5 -o /dev/null -D - http://127.0.0.1:44642/tv3/current-service 2>/dev/null \
        | tr -d '\r' | grep -i '^X-TV30-Auth-Warn:' || true)
  info "X-TV30-Auth-Warn sem token: ${h:-ausente} (em AUTH_ENFORCE=warn a borda deixa passar)"

  host_stop
  checar_http_nao "sem o tv3ws do host a borda para de responder /health (resposta vinha do host)" \
    http://127.0.0.1:44642/health '"status":"ok"' 10
}

cenario_2() {
  CEN=2
  titulo "CENARIO 2 — aop no host | containers: infra (borda linux) + tv3ws + bcast"
  parar aop || return
  # O bcast anuncia bcastEntryPackageUrl = http://BCAST_HOSTNAME:8081 (porta
  # INTERNA). Para o aop do host, isso e localhost:8081 publicado pelo
  # container — por isso BCAST_PORT=8081 aqui.
  BCAST_HOSTNAME=localhost BCAST_PORT=8081 subir linux $INFRA tv3ws bcast || return
  porta_livre 8080 || { falha "porta 8080 ja ocupada no host"; return; }
  host_start aop PORT=8080 MQTT_HOST=127.0.0.1 MQTT_WS_PORT="$MQTT_WS_PORT_CFG" \
    USER_DATA_PATH="$(dir_userfiles)" REDIS_HOST=127.0.0.1 REDIS_PORT=6379 || return
  esperar_modulo "aop no host servindo 8080" \
    http://127.0.0.1:8080/appcat 'HTTP_STATUS=200' || { host_stop; return; }
  checar_redis_mqtt
  checar_log "aop do host leu os perfis no Redis do container" 'Loaded [0-9]+ users from Redis'
  checar_log "aop do host conectou no broker do container" 'Connected to MQTT broker'
  checar_http "aop do host recebeu o BAMT do bcast em container (MQTT)" \
    http://127.0.0.1:8080/appcat 'Trocar Usu' 15
  abrir_users_test
  checar_http "aop do host -> bcast em container (proxy HTTP /graphicsAppProxy)" \
    http://127.0.0.1:8080/graphicsAppProxy/users-test 'Trocar Usu' 10
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
  local r
  r=$(docker exec mqtt-broker mosquitto_sub -h localhost -t "tlm/sls/$SID_USERS_TEST/bald" -C 1 -W 5 2>/dev/null)
  if printf '%s' "$r" | grep -q 'host.docker.internal:8081'; then
    ok "sinalizacao do bcast do host no broker (bcastEntryPackageUrl em host.docker.internal:8081)"
  else
    falha "sinalizacao do bcast do host no broker — lido: $(recorte "$r")"
  fi
  checar_http "aop em container recebeu o BAMT do bcast no host (MQTT)" \
    http://127.0.0.1:8080/appcat 'Trocar Usu' 15
  abrir_users_test
  checar_http "aop em container -> bcast no host (proxy HTTP via host.docker.internal)" \
    http://127.0.0.1:8080/graphicsAppProxy/users-test 'Trocar Usu' 10
  host_stop
  checar_http_nao "sem o bcast do host o proxy do aop falha (resposta vinha do host)" \
    http://127.0.0.1:8080/graphicsAppProxy/users-test 'Trocar Usu' 5
  fechar_users_test
}

# ----------------------------------------------------------- restauracao ---

RESTAURADO=""
restaurar() {
  [ -z "$RESTAURADO" ] || return 0
  RESTAURADO=1
  host_stop
  CEN="-"
  if [ -n "${ANTES// /}" ]; then
    titulo "restaurando a stack padrao (EDGE_VARIANT=linux)"
    if EDGE_VARIANT=linux compose up -d >>"$LOGDIR/compose.log" 2>&1; then
      echo "  ok    stack padrao de pe"
    else
      echo "  ERRO  falha ao restaurar (ver $LOGDIR/compose.log)"
    fi
  else
    titulo "a stack nao estava de pe antes do teste: docker compose down"
    compose down >>"$LOGDIR/compose.log" 2>&1 || echo "  ERRO  falha no down (ver $LOGDIR/compose.log)"
  fi
}
trap 'restaurar' EXIT
trap 'echo; echo "interrompido"; exit 130' INT TERM

# ------------------------------------------------------------------ main ---

echo "TV30 — teste dev-host: cenarios [$CENARIOS], modo $MODO$( [ "$MODO" = docker ] && echo " ($IMAGEM)")"
echo "stack antes do teste: ${ANTES:-nada rodando}"
echo "logs: $LOGDIR"

for n in $CENARIOS; do
  "cenario_$n"
  host_stop
done

restaurar

titulo "RESUMO ($PASS PASS, $FAIL FAIL)"
for l in ${RESUMO[@]+"${RESUMO[@]}"}; do echo "  $l"; done
echo "logs dos modulos e do compose: $LOGDIR"
[ "$FAIL" -eq 0 ]
