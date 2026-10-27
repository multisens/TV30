#!/usr/bin/env bash
# test-auth.sh: credential validation at the EDGE (tv30-auth plugin of the
# edgegateway). Runs against the stack already up (44642 internal, 44643
# external), prints PASS/FAIL per case and exits != 0 if any fails.
#
# Usage (Linux/WSL, with docker access):  bash scripts/test-auth.sh
#
# Recreates the edge in warn and then in enforce mode, pauses or stops tv3ws
# and redis in some cases, publishes aop/currentService in place of the
# platform and a test BAMT in place of bcast (test services in the
# Application Catalog). At the end (trap EXIT, also on error or Ctrl+C) it
# restores everything and undoes in Redis what it seeded (ids with the
# suffix of this run); it writes through the functions of the schema
# (fcall), as the service would, and ends with the schema audit.
set -u
cd "$(dirname "$0")/.." || exit 1

H_INT=${H_INT:-http://localhost:44642}
AOP=${AOP_URL:-http://localhost:8080}
# With EDGE_EXT_PUBLISH=44643 (the number alone) Docker chooses the host
# port: ext_url reads it and is called again on every recreation of the edge
# (edge_mode). H_EXT in the environment fixes the address and disables the
# lookup.
ext_url() {
  local p
  p=$(docker port edgegateway 44643/tcp 2>/dev/null | head -1 | sed 's/.*://')
  # TLS on 44643, with the self-signed certificate of the receiver.
  echo "https://localhost:${p:-44643}"
}
H_EXT_FIXO=${H_EXT:-}
H_EXT=${H_EXT:-$(ext_url)}
NODE_IMG=${NODE_IMG:-node:20-alpine}
POP=aop/display/layers/popup/yesno
# tv3ws/src/core.ts (_t)
POP_QR=aop/display/layers/popup/qrcode
POP_PIN=aop/display/layers/popup/pin
RUN="$$$(date +%s)"
# clientid in the format of C.6.1.4.3 (UUID, IETF RFC 9562; here version 4).
uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid; return; fi
  local h; h=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  printf '%s-%s-4%s-%x%s-%s\n' "${h:0:8}" "${h:8:4}" "${h:13:3}" $(( (0x${h:16:1} & 3) | 8 )) "${h:17:3}" "${h:20:12}"
}
CLIENT="tv30-test-auth-$RUN"
REFUSED="tv30-test-recusa-$RUN"
# Stand-alone local client of the clientid reuse case.
REUSE=$(uuid)
# Non-local, pm=qrcode.
NL_QR=$(uuid)
# Non-local, pm=kex.
NL_KEX=$(uuid)
# /authorize with redis frozen: never authorized.
REDIS_CID=$(uuid)
# 103 with the graphics layer busy: the request waiting for the yes/no.
C103=$(uuid)
# And the other client that arrives at that moment (gets 103, never stored).
C103B=$(uuid)
# Authorized by the function: the valid access token of the 304 in warn.
WARN_CID=$(uuid)
# Non-local client that answers yes and does not complete the pairing.
NL_PEND=$(uuid)
SVC_A="urn:tv30:test:auth-a-$RUN"
SVC_B="urn:tv30:test:auth-b-$RUN"
# Never announced: not in the Application Catalog.
SVC_FORA="urn:tv30:test:auth-fora-$RUN"
# Test BAMT, in place of bcast.
LLS_TOPIC="tlm/lls/tv30-test-auth-$RUN/bamt"
# Simulated "associated" origin.
ASSOC="http://tv30-test-assoc-$RUN.invalid"
# Any browser (CORS).
OTHER_ORIGIN="http://tv30-test-cliente.invalid"
# Constant serviceContextId (regression): the scid is the globalServiceId of
# the service, and this value is no service.
SCID_CONST="c08b2c72-fd14-4095-adaf-2e5810850c57"
TMP=$(mktemp -d)
PASS=0; FAIL=0; FAILED=()

pass() { PASS=$((PASS+1)); echo "PASS  $*"; }
fail() { FAIL=$((FAIL+1)); FAILED+=("$*"); echo "FAIL  $*"; }
info() { echo "      $*"; }
die()  { echo "ERRO: $*" >&2; exit 2; }

rc() { docker exec redis redis-cli "$@"; }
# fcall <function> [args...]: writes through the function of the schema
# (numkeys 0), in place of the service that owns the family; a refusal
# (TV30SCHEMA) or an error gives a message and a return != 0.
fcall() {
  local out st
  out=$(docker exec redis redis-cli --no-raw FCALL "$1" 0 "${@:2}" 2>&1); st=$?
  # --no-raw: a Redis error reply comes out as "(error) ..." (redis-cli exits
  # with 0 anyway); a stopped container or no connection: st != 0.
  if [ "$st" -ne 0 ] || [[ "$out" == *"(error)"* ]]; then
    echo "ERRO: FCALL $1 nao gravou: $out" >&2
    return 1
  fi
  printf '%s\n' "$out"
}
# Current service in place of tv3ws (mirror of aop/currentService); empty
# means no current service.
servico_corrente() { fcall tv30_session_service_id "$1" >/dev/null; }
# Schema audit: one "key | family | reason" line per finding.
auditoria() {
  docker exec redis redis-cli --raw FCALL_RO tv30_audit 0 2>&1 \
    | awk 'NR%3==1{k=$0} NR%3==2{f=$0} NR%3==0{print k " | " f " | " $0}'
}
env_of() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" | sed -n "s/^$2=//p" | head -1; }

# ----------------------------------------------------------- prerequisites --
for c in edgegateway tv3ws redis mqtt-broker; do
  [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] \
    || die "container $c nao esta rodando (suba a stack: docker compose up -d)"
done
command -v curl >/dev/null || die "curl ausente"

ORIG_MODE=$(env_of edgegateway AUTH_ENFORCE); ORIG_MODE=${ORIG_MODE:-enforce}
ORIG_VARIANT=$(env_of edgegateway EDGE_VARIANT); ORIG_VARIANT=${ORIG_VARIANT:-linux}
EDGE_SECRET=$(env_of edgegateway JWT_SECRET)
EDGE_ISSUER=$(env_of edgegateway JWT_ISSUER); EDGE_ISSUER=${EDGE_ISSUER:-GenericIssuer}
[ -n "$EDGE_SECRET" ] || die "JWT_SECRET ausente no edgegateway"
ORIG_SVC=$(rc GET session:current-service-id)
# Retained aop/currentService and hash session:current-service before the
# test (restored in the trap if the C.6.3.1 cases touch them).
CS_TOPIC=aop/currentService
ORIG_CS=$(docker exec mqtt-broker mosquitto_sub -t "$CS_TOPIC" -C 1 -W 2 --retained-only 2>/dev/null)
ORIG_CS_HASH=$(rc HGETALL session:current-service | base64 | tr -d "\n")
# Services of the Application Catalog before the test (ids without spaces,
# one per line).
ORIG_ANUNCIADOS=$(rc --raw SMEMBERS services:announced | tr -d '\r')
echo "== borda: modo=$ORIG_MODE variante=$ORIG_VARIANT; servico corrente='${ORIG_SVC}'; $CS_TOPIC retido='${ORIG_CS}' =="
# Without the function library the script cannot act as the services.
VERSAO_ESQUEMA=$(rc --raw FCALL_RO tv30_version 0 2>&1)
case "$VERSAO_ESQUEMA" in
  ''|*ERR*|*rror*) die "funcoes do Redis ausentes (FCALL_RO tv30_version 0: '$VERSAO_ESQUEMA'): reconstrua a imagem do redis (docker compose build redis && docker compose up -d redis)" ;;
esac
echo "== Redis: biblioteca de funcoes tv30, esquema versao $VERSAO_ESQUEMA =="
AUD_ANTES=$(auditoria)
if [ -n "$AUD_ANTES" ]; then
  echo "ATENCAO: a auditoria do Redis ja tem achados ANTES da suite (o fim da suite exige vazia):"
  printf '%s\n' "$AUD_ANTES" | sed 's/^/  /'
fi

# Recreates only the edgegateway in the requested mode, keeping variant and
# secret.
edge_mode() {
  local mode=$1 i
  AUTH_ENFORCE=$mode EDGE_VARIANT=$ORIG_VARIANT JWT_SECRET=$EDGE_SECRET JWT_ISSUER=$EDGE_ISSUER \
    docker compose up -d --no-deps edgegateway >"$TMP/compose.log" 2>&1 \
    || { cat "$TMP/compose.log"; return 1; }
  # A new host port on every recreation.
  [ -n "$H_EXT_FIXO" ] || H_EXT=$(ext_url)
  for i in $(seq 1 60); do
    if [ "$(docker logs edgegateway 2>&1 | grep -c "registrado surface=.* modo=$mode")" -ge 2 ] \
       && curl -s -o /dev/null -m 3 "$H_INT/health" && curl -sk -o /dev/null -m 3 "$H_EXT/health"; then
      return 0
    fi
    sleep 1
  done
  docker logs --tail 30 edgegateway
  return 1
}

# 1 after a case stops or freezes tv3ws.
TV3WS_TOUCHED=0
# 1 after a case freezes redis.
REDIS_TOUCHED=0
# 1 after the C.6.3.1 cases publish aop/currentService.
CS_TOUCHED=0

# cs_publish <sid>: publishes aop/currentService retained in place of the
# platform (empty deletes the retained message; the broker delivers "" to the
# subscribers, as in unsetCurrentService of aop) and waits for tv3ws to
# mirror the value in session:current-service-id, a sign that its service in
# use (core.app.sid) changed.
cs_publish() {
  local i
  if [ -n "$1" ]; then docker exec mqtt-broker mosquitto_pub -r -q 1 -t "$CS_TOPIC" -m "$1"
  else docker exec mqtt-broker mosquitto_pub -r -q 1 -t "$CS_TOPIC" -n; fi
  for i in $(seq 1 40); do
    [ "$(rc GET session:current-service-id)" = "$1" ] && return 0
    sleep 0.25
  done
  return 1
}

# anuncia <id>...: puts the services in the Application Catalog; without
# arguments, removes them. With the AoP up, by a retained test BAMT, which
# the AoP (aop-transport-layer-metadata-lls) writes to services:announced and
# publishes on aop/services; without it, or if it does not write, by the
# function, in place of the AoP.
ANUNCIO_PELA_LLS=0; LLS_RETIDO=0; ANUNCIO_FCALL=0; TESTE_ANUNCIADOS=""
ICON_JSON='<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1 1\"/>'
anuncia() {
  local s i ok n=0 bamt=""
  if [ "$(docker inspect -f '{{.State.Running}}' aop 2>/dev/null)" = true ]; then
    if [ $# -gt 0 ]; then
      for s in "$@"; do
        n=$((n+1))
        bamt="$bamt${bamt:+,}{\"globalServiceId\":\"$s\",\"appVersion\":1,\"appName\":\"Teste $n\",\"appIcon\":\"$ICON_JSON\",\"bannerIcon\":\"$ICON_JSON\",\"backgroundColor\":\"#202020\",\"foregroundColor\":\"#e0e0e0\"}"
      done
      docker exec mqtt-broker mosquitto_pub -r -q 1 -t "$LLS_TOPIC" -m "[$bamt]" || return 1
      LLS_RETIDO=1
    else
      docker exec mqtt-broker mosquitto_pub -r -q 1 -t "$LLS_TOPIC" -n || return 1
      LLS_RETIDO=0
    fi
    for i in $(seq 1 40); do
      ok=1
      if [ $# -gt 0 ]; then
        for s in "$@"; do [ "$(rc SISMEMBER services:announced "$s")" = 1 ] || ok=0; done
      else
        for s in $TESTE_ANUNCIADOS; do [ "$(rc SISMEMBER services:announced "$s")" = 0 ] || ok=0; done
      fi
      if [ "$ok" = 1 ]; then ANUNCIO_PELA_LLS=1; ANUNCIO_FCALL=0; TESTE_ANUNCIADOS="$*"; return 0; fi
      sleep 0.25
    done
    echo "ATENCAO: o AoP nao refletiu a BAMT de teste em services:announced em 10 s; gravando pela funcao" >&2
  fi
  ANUNCIO_PELA_LLS=0
  # shellcheck disable=SC2086
  fcall tv30_announced_services $ORIG_ANUNCIADOS "$@" >/dev/null || return 1
  if [ $# -gt 0 ]; then ANUNCIO_FCALL=1; else ANUNCIO_FCALL=0; fi
  TESTE_ANUNCIADOS="$*"
}

# Undoes what the suite seeded in Redis (once: at the normal end, before the
# audit, or in the trap if the script stops midway).
REDIS_RESTAURADO=0
restaura_redis() {
  [ "$REDIS_RESTAURADO" = 1 ] && return 0
  REDIS_RESTAURADO=1
  # redis first: the rest of the cleanup talks to it.
  if [ "$REDIS_TOUCHED" = 1 ] && [ "$(docker inspect -f '{{.State.Paused}}' redis 2>/dev/null)" = true ]; then
    docker unpause redis >/dev/null && echo "redis descongelado"
  fi
  if [ "$TV3WS_TOUCHED" = 1 ]; then
    [ "$(docker inspect -f '{{.State.Paused}}' tv3ws 2>/dev/null)" = true ] \
      && docker unpause tv3ws >/dev/null && echo "tv3ws descongelado"
    [ "$(docker inspect -f '{{.State.Running}}' tv3ws 2>/dev/null)" = true ] \
      || { docker start tv3ws >/dev/null && echo "tv3ws religado"; }
  fi
  # The retained aop/currentService before Redis: tv3ws rewrites
  # session:current-service-id and the hash session:current-service when it
  # gets it. The previous hash comes back through the function
  # (tv30_session_service); without a previous hash, what tv3ws rewrote for the
  # restored message stays.
  if [ "$CS_TOUCHED" = 1 ]; then
    if cs_publish "$ORIG_CS"; then echo "$CS_TOPIC retido restaurado ('$ORIG_CS')"
    else echo "ATENCAO: $CS_TOPIC publicado ('$ORIG_CS'), mas o tv3ws nao o espelhou no Redis em 10 s"; fi
    local k v hs=()
    while IFS= read -r k && IFS= read -r v; do hs+=("$k" "$v"); done < <(printf '%s' "$ORIG_CS_HASH" | base64 -d)
    if [ "${#hs[@]}" -gt 0 ]; then
      fcall tv30_session_service "${hs[@]}" >/dev/null \
        || echo "ATENCAO: o hash session:current-service de antes da suite nao passou no esquema (veja a auditoria)"
    fi
  fi
  servico_corrente "$ORIG_SVC" || echo "ATENCAO: session:current-service-id de antes ('$ORIG_SVC') nao passou no esquema"
  # Without the test BAMT the AoP rewrites the list without its services;
  # written by the function, the previous list comes back.
  if [ "$LLS_RETIDO" = 1 ] || [ "$ANUNCIO_FCALL" = 1 ]; then
    anuncia 2>/dev/null || echo "ATENCAO: servicos de teste ainda em services:announced: $(rc --raw SMEMBERS services:announced | tr '\n' ' ')"
  fi
  fcall tv30_origin_remove "$ASSOC" >/dev/null
  # Test data (ids and services with the suffix of this run): a direct write
  # on purpose, since no service deletes a client or the whole bind-context
  # list, so there is no function for it. What is left (the sets without the
  # test ids) satisfies the schema; the audit at the end checks it.
  rc DEL "bind-context:$SVC_A" "bind-context:$SVC_B" "client:$CLIENT" "client:$REFUSED" \
    "client:$REUSE" "client:$NL_QR" "client:$NL_KEX" "client:$REDIS_CID" "client:$C103" "client:$C103B" "client:$WARN_CID" "client:$NL_PEND" >/dev/null
  rc SREM clients:authorized "$CLIENT" "$REFUSED" "$REUSE" "$NL_QR" "$NL_KEX" "$REDIS_CID" "$C103" "$C103B" "$WARN_CID" "$NL_PEND" >/dev/null
  rc SREM clients:blocked "$CLIENT" "$REFUSED" "$REUSE" "$NL_QR" "$NL_KEX" "$REDIS_CID" "$C103" "$C103B" "$WARN_CID" "$NL_PEND" >/dev/null
  echo "Redis restaurado (servico corrente='$(rc GET session:current-service-id)')"
}

cleanup() {
  set +e
  echo; echo "== limpeza =="
  restaura_redis
  if [ "$(env_of edgegateway AUTH_ENFORCE)" != "$ORIG_MODE" ]; then
    if edge_mode "$ORIG_MODE"; then echo "edgegateway de volta ao modo $ORIG_MODE"
    else echo "ATENCAO: nao consegui voltar o edgegateway para $ORIG_MODE"; fi
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ------------------------------------------------------------------ request --
# req METHOD URL [curl args] -> ST (status), CE (curl output), $TMP/h2, $TMP/b
req() {
  local m=$1 u=$2; shift 2
  : >"$TMP/h"; : >"$TMP/b"
  # -k: the certificate of 44643 is self-signed; a real non-local client
  # trusts it through the serverCert of the pairing.
  ST=$(curl -sk -m 20 -X "$m" -D "$TMP/h" -o "$TMP/b" -w '%{http_code}' "$@" "$u"); CE=$?
  tr -d '\r' <"$TMP/h" >"$TMP/h2"
}
hdr()  { grep -i "^$1:" "$TMP/h2" | head -1 | cut -d: -f2- | sed 's/^ *//'; }
body() { cat "$TMP/b"; }
short() { body | head -c 200 | tr '\n' ' '; }

# Who answered: the Express of tv3ws sets X-Powered-By on every response
# (and KrakenD passes it on); the edge plugin does not.
origin_of() { if hdr X-Powered-By | grep -q '^Express'; then echo tv3ws; else echo borda; fi; }

# Checks the last response: an error in the C.3.2 format (404,
# {error,description} JSON and ACAO *) from the expected origin
# (borda|tv3ws).
check_err() {
  local name=$1 code=$2 orig=$3 why="" got
  local b; b=$(body)
  [ "$CE" = 0 ] || why="$why curl=$CE(conexao)"
  [ "$ST" = 404 ] || why="$why status=$ST"
  printf '%s' "$b" | grep -Eq "^\{\"error\":$code,\"description\":\".*\"\}$" || why="$why corpo=$(short)"
  hdr Content-Type | grep -qi '^application/json' || why="$why content-type='$(hdr Content-Type)'"
  [ "$(hdr Access-Control-Allow-Origin)" = "*" ] || why="$why acao='$(hdr Access-Control-Allow-Origin)'"
  got=$(origin_of)
  [ "$got" = "$orig" ] || why="$why origem=$got"
  if [ -z "$why" ]; then pass "$name -> 404 {error:$code} (origem $orig)"
  else fail "$name -> esperado 404 {error:$code} com origem $orig:$why"; fi
}

# expect_err NAME CODE ORIGIN METHOD URL [curl args]
expect_err() {
  local name=$1 code=$2 orig=$3; shift 3
  case "$orig" in borda|tv3ws) ;; *) die "expect_err '$name': origem '$orig' (use borda ou tv3ws)" ;; esac
  req "$@"
  check_err "$name" "$code" "$orig"
}

# expect_api_version NAME [VERSION]: the last response has API-Version
# (C.3.6.6) = VERSION. Default 2.0: the one for a request without
# Accept-Version and for error 101 (malformed Accept-Version); on error 100
# (a version outside the set) it is the latest supported, 100.0.
expect_api_version() {
  local want=${2:-2.0} v; v=$(hdr API-Version)
  if [ "$v" = "$want" ]; then pass "$1 -> API-Version: $v"; else fail "$1 -> esperado API-Version: $want, veio '$v'"; fi
}

# expect_list_v100 NAME [curl args]: the listing of C.6.15.5 in 100.0
# (proposal v2 of C.6.15), answered by tv3ws with sequence and API-Version
# 100.0. tv3ws identifies the local client by the class and the identity the
# edge passes on (X-TV30-Client-Class, X-TV30-Client-Id): without them, it
# gives 107.
expect_list_v100() {
  local name=$1 why=""; shift
  req GET "$H_INT/tv3/remote-device/devices/x" -H 'Accept-Version: 100.0' "$@"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  [ "$ST" = 200 ] || why="$why status=$ST corpo=$(short)"
  [ "$(origin_of)" = tv3ws ] || why="$why origem=borda"
  body | grep -Eq '^\{"sequence":[0-9]+' || why="$why corpo=$(short)"
  [ "$(hdr API-Version)" = 100.0 ] || why="$why api-version='$(hdr API-Version)'"
  if [ -z "$why" ]; then pass "$name -> 200 do tv3ws $(short)"; else fail "$name -> esperado 200 do tv3ws com sequence:$why"; fi
}

# Reached tv3ws (X-Powered-By: Express) without a block or warning from the
# edge.
expect_pass() {
  local name=$1 why=""; shift
  req "$@"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  hdr X-Powered-By | grep -q Express || why="$why nao-chegou-ao-tv3ws(status=$ST corpo=$(short))"
  [ -z "$(hdr X-Tv30-Auth-Warn)" ] || why="$why aviso=$(hdr X-Tv30-Auth-Warn)"
  if [ -z "$why" ]; then pass "$name -> repassado ao tv3ws (status $ST)"; else fail "$name -> esperado repasse:$why"; fi
}

# C.4.1.9.2: exactly one Access-Control-Allow-Origin: * (a duplicated one is
# refused by Chrome), with or without Origin in the request, and an
# Access-Control-Expose-Headers with X-TV30-Auth-Warn (cors.expose_headers),
# for the browser to read the warning of warn mode.
expect_acao() {
  local name=$1 why=""; shift
  req "$@"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  local n; n=$(grep -ci '^Access-Control-Allow-Origin:' "$TMP/h2")
  [ "$n" = 1 ] || why="$why acao-linhas=$n"
  [ "$(hdr Access-Control-Allow-Origin)" = "*" ] || why="$why acao='$(hdr Access-Control-Allow-Origin)'"
  n=$(grep -ci '^Access-Control-Expose-Headers:' "$TMP/h2")
  [ "$n" = 1 ] || why="$why expose-linhas=$n"
  hdr Access-Control-Expose-Headers | grep -qi 'X-TV30-Auth-Warn' || why="$why expose='$(hdr Access-Control-Expose-Headers)'"
  if [ -z "$why" ]; then pass "$name -> um Access-Control-Allow-Origin: * e o Expose-Headers da borda (status $ST)"; else fail "$name -> esperado um ACAO * e o Expose-Headers:$why"; fi
}

# C.4.1.9.3: OPTIONS without preflight on a declared API gives 200 with ACAO,
# ACAM and ACAH.
expect_options() {
  local name=$1 why=""; shift
  req OPTIONS "$@"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  [ "$ST" = 200 ] || why="$why status=$ST corpo=$(short)"
  [ "$(hdr Access-Control-Allow-Origin)" = "*" ] || why="$why acao='$(hdr Access-Control-Allow-Origin)'"
  [ -n "$(hdr Access-Control-Allow-Methods)" ] || why="$why sem-allow-methods"
  hdr Access-Control-Allow-Headers | grep -qi 'bind-token' || why="$why allow-headers='$(hdr Access-Control-Allow-Headers)'"
  if [ -z "$why" ]; then pass "$name -> 200, Allow-Methods: $(hdr Access-Control-Allow-Methods)"; else fail "$name -> esperado 200 + cabecalhos CORS:$why"; fi
}

# warn mode: passed on to tv3ws and marked with X-TV30-Auth-Warn: <code>.
expect_warn() {
  local name=$1 code=$2 why=""; shift 2
  req "$@"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  hdr X-Powered-By | grep -q Express || why="$why nao-chegou-ao-tv3ws(status=$ST corpo=$(short))"
  [ "$(hdr X-Tv30-Auth-Warn)" = "$code" ] || why="$why aviso='$(hdr X-Tv30-Auth-Warn)'"
  if [ -z "$why" ]; then pass "$name -> repassado com X-TV30-Auth-Warn: $code"; else fail "$name -> esperado repasse com aviso $code:$why"; fi
}

# API ANSWERED BY THE EDGE (C.6.8, C.6.7.8/C.6.7.9; edge.go of the plugin):
# expect_edge NAME BODY_REGEX [VERSION] METHOD URL [curl args]: 200, a JSON
# body matching the (extended) regex, no X-Powered-By (it did not reach
# tv3ws), one ACAO *, API-Version = VERSION (default 2.0) and no warn
# header.
expect_edge() {
  local name=$1 re=$2 ver=2.0 why="" n; shift 2
  case "${1:-}" in [0-9]*.[0-9]*) ver=$1; shift ;; esac
  req "$@"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  [ "$ST" = 200 ] || why="$why status=$ST"
  body | grep -Eq "$re" || why="$why corpo=$(short)"
  hdr Content-Type | grep -qi '^application/json' || why="$why content-type='$(hdr Content-Type)'"
  [ "$(origin_of)" = borda ] || why="$why origem=tv3ws"
  n=$(grep -ci '^Access-Control-Allow-Origin: \*$' "$TMP/h2"); [ "$n" = 1 ] || why="$why acao-linhas=$n"
  [ "$(hdr API-Version)" = "$ver" ] || why="$why api-version='$(hdr API-Version)'"
  [ -z "$(hdr X-Tv30-Auth-Warn)" ] || why="$why aviso=$(hdr X-Tv30-Auth-Warn)"
  if [ -z "$why" ]; then pass "$name -> 200 da borda $(short)"; else fail "$name -> esperado 200 da borda:$why"; fi
}

# warn mode on an API answered by the edge: 200 from the edge itself (there
# is no passing on to tv3ws, so expect_warn does not apply) with
# X-TV30-Auth-Warn.
expect_edge_warn() {
  local name=$1 code=$2 re=$3 why=""; shift 3
  req "$@"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  [ "$ST" = 200 ] || why="$why status=$ST corpo=$(short)"
  body | grep -Eq "$re" || why="$why corpo=$(short)"
  [ "$(origin_of)" = borda ] || why="$why origem=tv3ws"
  [ "$(hdr X-Tv30-Auth-Warn)" = "$code" ] || why="$why aviso='$(hdr X-Tv30-Auth-Warn)'"
  if [ -z "$why" ]; then pass "$name -> 200 da borda com X-TV30-Auth-Warn: $code"; else fail "$name -> esperado 200 da borda com aviso $code:$why"; fi
}

# CORS preflight: expect_preflight NAME URL METHOD HEADERS. The edge plugin
# answers, on any path and with the list in any order. Response: 200 with
# ACAO *, ACAM * (C.4.1.9.3), the ACAH of routes.json and
# Access-Control-Max-Age 43200 (the max_age 12h of routes.json).
expect_preflight() {
  local name=$1 url=$2 m=$3 hs=$4 why="" h
  req OPTIONS "$url" -H "Origin: $OTHER_ORIGIN" -H "Access-Control-Request-Method: $m" \
      -H "Access-Control-Request-Headers: $hs"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  [ "${ST:0:1}" = 2 ] || why="$why status=$ST"
  [ "$(hdr Access-Control-Allow-Origin)" = "*" ] || why="$why acao='$(hdr Access-Control-Allow-Origin)'"
  [ "$(hdr Access-Control-Allow-Methods)" = "*" ] || why="$why allow-methods='$(hdr Access-Control-Allow-Methods)'"
  [ "$(hdr Access-Control-Max-Age)" = 43200 ] || why="$why max-age='$(hdr Access-Control-Max-Age)'"
  for h in ${hs//,/ }; do
    hdr Access-Control-Allow-Headers | grep -qi "$h" || why="$why allow-headers='$(hdr Access-Control-Allow-Headers)'"
  done
  if [ -z "$why" ]; then pass "$name -> $ST, Allow-Headers: $(hdr Access-Control-Allow-Headers)"; else fail "$name -> esperado preflight aceito:$why"; fi
}

# ------------------------------------------------------------ test material --
# node with the standard library only: HS secrets, RSA pairs, bind-tokens and
# an expired access token. Output: NAME=value lines (no line breaks).
cat >"$TMP/gen.js" <<'JS'
const crypto = require('crypto');
const now = Math.floor(Date.now() / 1000);
const b64u = b => Buffer.from(b).toString('base64url');
const out = (k, v) => console.log(`${k}=${v}`);
function jwt(header, payload, sign) {
  const si = b64u(JSON.stringify(header)) + '.' + b64u(JSON.stringify(payload));
  return si + '.' + sign(si);
}
const hs = (alg, secret) => si => crypto.createHmac(alg === 'HS256' ? 'sha256' : 'sha512', secret).update(si).digest('base64url');
const rs = (alg, priv) => si => crypto.sign(alg === 'RS256' ? 'sha256' : 'sha512', Buffer.from(si), priv).toString('base64url');
const ok = { iat: now, nbf: now, exp: now + 3600 };
const H = alg => ({ alg, typ: 'JWT' });

const hs256 = 'tv30-test-hs256-' + crypto.randomBytes(8).toString('hex');
const hs512 = 'tv30-test-hs512-' + crypto.randomBytes(8).toString('hex');
const unreg = 'tv30-test-nao-registrada-' + crypto.randomBytes(8).toString('hex');
const r256 = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const r512 = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const r256pem = r256.publicKey.export({ type: 'spki', format: 'pem' });
const r256der = r256.publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
// "Style of the standard": a PKCS#1 PRIVATE key in base64 of DER, no header.
const r512priv = r512.privateKey.export({ type: 'pkcs1', format: 'der' }).toString('base64');

out('HS256_KEY', hs256); out('HS512_KEY', hs512);
out('RS256_DER', r256der); out('RS512_PRIV', r512priv);
out('BODY_HS256', JSON.stringify({ alg: 'HS256', key: hs256 }));
out('BODY_HS512', JSON.stringify({ alg: 'HS512', key: hs512 }));
out('BODY_RS256', JSON.stringify({ alg: 'RS256', key: r256pem }));
out('BODY_RS512', JSON.stringify({ alg: 'RS512', key: r512priv }));
out('BT_HS256', jwt(H('HS256'), ok, hs('HS256', hs256)));
out('BT_HS512', jwt(H('HS512'), ok, hs('HS512', hs512)));
out('BT_RS256', jwt(H('RS256'), ok, rs('RS256', r256.privateKey)));
out('BT_RS512', jwt(H('RS512'), ok, rs('RS512', r512.privateKey)));
// The size of the example of the standard (512 bits, MIIBOgIBAAJB...): only
// valid for RS256.
try {
  const n = crypto.generateKeyPairSync('rsa', { modulusLength: 512 });
  const npriv = n.privateKey.export({ type: 'pkcs1', format: 'der' }).toString('base64');
  out('NORMA_PRIV', npriv);
  out('BODY_NORMA', JSON.stringify({ alg: 'RS256', key: npriv }));
  out('BT_NORMA', jwt(H('RS256'), ok, rs('RS256', n.privateKey)));
} catch (e) { out('NORMA_ERRO', String(e.message).replace(/\s+/g, ' ')); }
// Invalid cases.
out('BT_UNREG', jwt(H('HS256'), ok, hs('HS256', unreg)));
// HMAC with the registered RSA public key.
out('BT_CONFUSION', jwt(H('HS256'), ok, hs('HS256', r256pem)));
out('BT_NBF', jwt(H('HS256'), { iat: now, nbf: now + 3600, exp: now + 7200 }, hs('HS256', hs256)));
out('BT_EXP', jwt(H('HS256'), { iat: now - 7200, nbf: now - 7200, exp: now - 3600 }, hs('HS256', hs256)));
out('BT_IAT', jwt(H('HS256'), { iat: now + 3600, nbf: now - 10, exp: now + 7200 }, hs('HS256', hs256)));
out('BT_NONE', jwt({ alg: 'none', typ: 'JWT' }, ok, () => ''));
out('AT_EXPIRED', jwt(H('HS256'),
  { iat: now - 7200, nbf: now - 7200, exp: now - 3600, iss: process.env.ISS, sub: process.env.SUB, class: 'standAlone' },
  hs('HS256', process.env.SECRET)));
// Within its period, but signed with another secret (tampered, for warn).
out('AT_BADSIG', jwt(H('HS256'),
  { iat: now, nbf: now, exp: now + 3600, iss: process.env.ISS, sub: process.env.SUB, class: 'standAlone' },
  hs('HS256', 'tv30-test-outro-segredo-' + crypto.randomBytes(8).toString('hex'))));
// Valid, of the client the script puts in clients:authorized in place of
// tv3ws.
out('AT_WARN', jwt(H('HS256'),
  { iat: now, nbf: now, exp: now + 3600, iss: process.env.ISS, sub: process.env.WARN, class: 'standAlone' },
  hs('HS256', process.env.SECRET)));
JS
docker run --rm -i -e ISS="$EDGE_ISSUER" -e SUB="$CLIENT" -e WARN="$WARN_CID" -e SECRET="$EDGE_SECRET" "$NODE_IMG" node - <"$TMP/gen.js" >"$TMP/mat" 2>"$TMP/mat.err" \
  || { cat "$TMP/mat.err"; die "falha gerando chaves/tokens no container $NODE_IMG"; }
while IFS='=' read -r k v; do [ -n "$k" ] && printf -v "$k" '%s' "$v"; done <"$TMP/mat"
[ -n "${BT_RS512:-}" ] || die "material de teste incompleto"

# Real authorization flow of a stand-alone local client; $2 = answer of the
# "viewer" to the pop-up (true|false). Leaves the body in $TMP/b.
authorize() {
  local cid=$1 ans=$2 port=${3:-$H_INT}
  ( docker exec mqtt-broker mosquitto_sub -C 1 -W 15 -t "$POP/message" >/dev/null 2>&1 \
      && docker exec mqtt-broker mosquitto_pub -q 1 -t "$POP/response" -m "$ans" ) &
  local bg=$!
  sleep 1.5
  req GET "$port/tv3/authorize?clientid=$cid&display-name=tv30-test-auth"
  wait "$bg" 2>/dev/null
}
json_str() { body | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }
stop_bg() { kill "$@" 2>/dev/null; wait "$@" 2>/dev/null; }

# ------------------------------------------------------- NON-local client --
# Crypto of the non-local application, the same as
# tv3ws/src/api/client-identification/service.ts and util/encryption.ts.
# MODE:
#   kexkey  ECDH P-256 pair of the client: CPRIV (hex) and CPUB (SEC 1 point
#           without compression in base64url, C.4.3.4)
#   solve   PM=qrcode: QR = QR code key (base64url) -> secret =
#           SHA-256(key)[0:16] (C.4.3.2, C.6.1.2.2 steps 1-2);
#           PM=kex: CPRIV + SKEY (partial key of the server) -> h =
#           SHA-256(ECDH), PIN = h mod 10000 with 4 digits (leading zeros,
#           "a four-digit number"), secret = h[0:16] (C.4.3.3).
#           Then the challenge-response of Table C.4: decodes the
#           challenge, decrypts, SHA-256, encrypts, base64url. Output
#           SECRET, CR (and PIN for kex).
#   token   CT + BODY (body in base64) + SECRET: decrypts if the body came
#           as application/octet-stream (C.6.1.3.3) and extracts the fields
#           and the class/sub claims of the accessToken. Output ENC, AT, RT,
#           TT, EXP, CERT, CLASS, SUB.
# An error of any step (e.g. invalid padding = wrong key) comes out in ERR.
cat >"$TMP/pair.js" <<'JS'
const crypto = require('crypto');
const E = process.env;
const out = (k, v) => console.log(`${k}=${v}`);
const b64u = b => Buffer.from(b).toString('base64url');
const unb64u = s => Buffer.from(s || '', 'base64url');
const sha256 = b => crypto.createHash('sha256').update(b).digest();
function aes(encrypt, key, data) {
  const c = encrypt ? crypto.createCipheriv('aes-128-ecb', key, null) : crypto.createDecipheriv('aes-128-ecb', key, null);
  c.setAutoPadding(true);
  return Buffer.concat([c.update(data), c.final()]);
}
try {
  if (E.MODO === 'kexkey') {
    const ecdh = crypto.createECDH('prime256v1');
    ecdh.generateKeys();
    out('CPRIV', ecdh.getPrivateKey('hex'));
    out('CPUB', b64u(ecdh.getPublicKey(null, 'uncompressed')));
  } else if (E.MODO === 'solve') {
    let secret;
    if (E.PM === 'qrcode') {
      secret = sha256(unb64u(E.QR)).subarray(0, 16);
    } else {
      const ecdh = crypto.createECDH('prime256v1');
      ecdh.setPrivateKey(E.CPRIV, 'hex');
      const h = sha256(ecdh.computeSecret(unb64u(E.SKEY)));
      out('PIN', (BigInt('0x' + h.toString('hex')) % 10000n).toString().padStart(4, '0'));
      secret = h.subarray(0, 16);
    }
    const r = aes(false, secret, unb64u(E.CHALLENGE));
    out('SECRET', secret.toString('hex'));
    out('CR', b64u(aes(true, secret, sha256(r))));
  } else if (E.MODO === 'token') {
    const raw = Buffer.from(E.BODY || '', 'base64');
    const enc = /^application\/octet-stream/i.test(E.CT || '');
    const j = JSON.parse((enc ? aes(false, Buffer.from(E.SECRET || '', 'hex'), raw) : raw).toString('utf8'));
    const p = JSON.parse(unb64u(String(j.accessToken || '').split('.')[1]).toString('utf8') || '{}');
    out('ENC', enc ? 1 : 0);
    out('AT', j.accessToken || ''); out('RT', j.refreshToken || '');
    out('TT', j.tokenType || ''); out('EXP', j.expiresIn ?? '');
    out('CERT', j.serverCert ? 1 : 0);
    // sha256 of the PEM of the serverCert, to compare with .tv30/tls/cert.pem.
    out('CERTSHA', j.serverCert ? crypto.createHash('sha256').update(Buffer.from(j.serverCert, 'base64')).digest('hex') : '');
    out('CLASS', p.class || ''); out('SUB', p.sub || '');
  } else {
    out('ERR', `MODO desconhecido: ${E.MODO}`);
  }
} catch (e) { out('ERR', String((e && e.message) || e).replace(/\s+/g, ' ')); }
JS

# nl_node VAR=value... -> runs pair.js and loads each K=v line into NL_K.
nl_node() {
  local envs=() kv k v
  for kv in "$@"; do envs+=(-e "$kv"); done
  NL_ERR=""
  docker run --rm -i "${envs[@]}" "$NODE_IMG" node - <"$TMP/pair.js" >"$TMP/pair.out" 2>"$TMP/pair.err" \
    || { NL_ERR="node: $(head -c 300 "$TMP/pair.err" | tr '\n' ' ')"; return 1; }
  while IFS='=' read -r k v; do [ -n "$k" ] && printf -v "NL_$k" '%s' "$v"; done <"$TMP/pair.out"
  [ -z "$NL_ERR" ]
}

# REAL pairing of a non-local client through 44642 (first access over
# HTTP): $1 = qrcode|kex, $2 = clientid. Answers "true" to the yes/no pop-up,
# reads from the broker the QR code or PIN that tv3ws sent the TV to show,
# solves the challenge and decrypts the first response of /token. Leaves
# NL_AT, NL_RT (and NL_CLASS...). Returns != 0 if the pairing did not
# complete (the FAIL is already recorded).
pair() {
  local pm=$1 cid=$2 S="[nao local $1]" topic q="" bgp bgy pop ch skey ct
  NL_AT=""; NL_RT=""; NL_SECRET=""; NL_CR=""; NL_PIN=""
  if [ "$pm" = kex ]; then
    topic=$POP_PIN
    nl_node MODO=kexkey || { fail "$S par ECDH do cliente nao gerado: $NL_ERR"; return 1; }
    q="&key=$NL_CPUB"
  else
    topic=$POP_QR
  fi
  : >"$TMP/pop"
  docker exec mqtt-broker mosquitto_sub -R -C 1 -W 20 -t "$topic" >"$TMP/pop" 2>/dev/null &
  bgp=$!
  ( docker exec mqtt-broker mosquitto_sub -C 1 -W 15 -t "$POP/message" >/dev/null 2>&1 \
      && docker exec mqtt-broker mosquitto_pub -q 1 -t "$POP/response" -m true ) &
  bgy=$!
  sleep 1.5
  req GET "$H_INT/tv3/authorize?clientid=$cid&display-name=tv30-test-nao-local&pm=$pm$q"
  ch=$(json_str challenge); skey=$(json_str key)
  if [ "$ST" != 200 ] || [ -z "$ch" ]; then
    stop_bg "$bgp" "$bgy"
    fail "$S [44642] /authorize?pm=$pm -> esperado 200 {challenge}: status=$ST origem=$(origin_of) corpo=$(short)"
    return 1
  fi
  wait "$bgy" 2>/dev/null; wait "$bgp" 2>/dev/null
  pass "$S [44642] /authorize?pm=$pm (pop-up sim/nao aceito) -> 200 {challenge} (origem $(origin_of))"

  pop=$(sed -n 's/.*"value":"\([^"]*\)".*/\1/p' "$TMP/pop")
  if [ -z "$pop" ]; then
    fail "$S pop-up de pareamento nao chegou em $topic (lido: '$(head -c 120 "$TMP/pop")')"
    return 1
  fi
  if [ "$pm" = kex ]; then
    if [ -z "$skey" ]; then
      fail "$S /authorize?pm=kex respondeu sem o campo \"key\" (chave parcial do servidor, Tabela C.3): sem ela o cliente nao deriva a chave simetrica (C.4.3.3) e o pareamento kex nao se completa (corpo=$(short))"
      return 1
    fi
    nl_node MODO=solve PM=kex CPRIV="$NL_CPRIV" SKEY="$skey" CHALLENGE="$ch" \
      || { fail "$S desafio nao resolvido com a chave ECDH derivada: $NL_ERR"; return 1; }
    # C.4.3.3: "a four-digit number": "0042", not "42".
    if [[ "$pop" =~ ^[0-9]{4}$ ]] && [ "$pop" = "$NL_PIN" ]; then
      pass "$S PIN publicado em $POP_PIN ($pop, 4 digitos) = PIN que o cliente calculou da chave ECDH"
    else
      fail "$S PIN publicado '$pop' (esperado 4 digitos) != PIN calculado pelo cliente '$NL_PIN'"
      return 1
    fi
  else
    nl_node MODO=solve PM=qrcode QR="$pop" CHALLENGE="$ch" \
      || { fail "$S desafio nao resolvido com a chave do QR code: $NL_ERR"; return 1; }
    pass "$S chave lida do QR code publicado em $POP_QR; desafio decifrado"
  fi

  req GET "$H_INT/tv3/token?clientid=$cid&challenge-response=$NL_CR"
  ct=$(hdr Content-Type)
  if [ "$ST" != 200 ]; then
    fail "$S [44642] /token com challenge-response -> status=$ST origem=$(origin_of) corpo=$(short)"
    return 1
  fi
  nl_node MODO=token CT="$ct" BODY="$(base64 <"$TMP/b" | tr -d "\n")" SECRET="$NL_SECRET" \
    || { fail "$S [44642] primeira resposta do /token ilegivel (Content-Type '$ct'): $NL_ERR"; return 1; }
  if [ "$NL_ENC" = 1 ]; then
    pass "$S [44642] primeiro /token -> 200 cifrado (application/octet-stream), decifrado com a chave do pareamento"
  else
    fail "$S [44642] primeiro /token por HTTP -> esperado corpo cifrado application/octet-stream (C.6.1.3.3), veio '$ct'"
  fi
  if [ -n "$NL_AT" ] && [ "$NL_CLASS" = nonLocal ] && [ "$NL_SUB" = "$cid" ] && [ -n "$NL_RT" ]; then
    pass "$S accessToken com class=nonLocal e sub=clientid, mais refreshToken (tokenType=$NL_TT, expiresIn=$NL_EXP)"
  else
    fail "$S credencial do primeiro /token: class='$NL_CLASS' sub='$NL_SUB' accessToken=${NL_AT:+presente} refreshToken=${NL_RT:+presente}"
    return 1
  fi
  if [ "$EXT_OK" = 1 ]; then
    if [ "$NL_CERT" = 1 ]; then pass "$S serverCert presente (tv3ws com HTTPS)"
    else fail "$S serverCert ausente com o tv3ws em HTTPS (Tabela C.4: incluido no primeiro acesso do nao local)"; fi
    # The serverCert is the certificate of the receiver (.tv30/tls).
    CERT_SHA=$(openssl dgst -sha256 -r .tv30/tls/cert.pem 2>/dev/null | cut -d' ' -f1)
    if [ -n "$CERT_SHA" ] && [ "$NL_CERTSHA" = "$CERT_SHA" ]; then pass "$S serverCert = o certificado do receptor (.tv30/tls/cert.pem)"
    else fail "$S serverCert diferente do .tv30/tls/cert.pem (sha256 '$NL_CERTSHA' x '$CERT_SHA')"; fi
  elif [ "$NL_CERT" = 1 ]; then
    info "$S serverCert presente, embora a 44643 nao chegue ao tv3ws"
  else
    info "$S serverCert ausente: o tv3ws esta sem HTTPS_CERT (esperado neste arranjo)"
  fi
  return 0
}

# clientid reuse (C.6.1.4.4 and Table C.3: 101 "if clientid has been used
# before"): 404 {error:101} from tv3ws and NO pop-up published.
expect_reuse() {
  local name=$1 url=$2 bgw
  : >"$TMP/popw"
  docker exec mqtt-broker mosquitto_sub -C 1 -W 4 -t "$POP/message" >"$TMP/popw" 2>/dev/null &
  bgw=$!
  sleep 1
  expect_err "$name" 101 tv3ws GET "$url"
  wait "$bgw" 2>/dev/null
  if [ -s "$TMP/popw" ]; then fail "$name: pop-up sim/nao publicado no reuso ($(head -c 120 "$TMP/popw"))"
  else pass "$name: nenhum pop-up publicado"; fi
}

# Waits for the edge to reach tv3ws again (both surfaces if EXT_OK).
wait_tv3ws() {
  local i
  for i in $(seq 1 90); do
    req GET "$H_INT/health"
    if hdr X-Powered-By | grep -q Express; then
      [ "$EXT_OK" = 1 ] || return 0
      req GET "$H_EXT/health"
      hdr X-Powered-By | grep -q Express && return 0
    fi
    sleep 1
  done
  return 1
}

# Any browser: CORS returns ACAO.
AUTH_H=(-H "Origin: $OTHER_ORIGIN")

# 44643 passes on to https://tv3ws:44653, which exists only with HTTPS in
# tv3ws; without it, the cases passed on through it are skipped (the edge
# errors there are not).
req GET "$H_EXT/health"
if hdr X-Powered-By | grep -q Express; then EXT_OK=1
else
  EXT_OK=0
  info "AVISO: a 44643 nao chega ao tv3ws (status=$ST): sem HTTPS_KEY/HTTPS_CERT no tv3ws/.env o"
  info "       backend https://tv3ws:44653 nao existe. Casos de repasse pela 44643 serao PULADOS."
fi
# ext_skip <name>: true (and prints) if the case passed on through 44643
# must be skipped.
ext_skip() { if [ "$1" = "$H_EXT" ] && [ "$EXT_OK" != 1 ]; then info "pulado (sem HTTPS no tv3ws): $2"; return 0; fi; return 1; }

# C.6.14.2 and C.6.14.5 with a service not in the Application Catalog give
# 304: the test services go in it; $SVC_FORA never.
anuncia "$SVC_A" "$SVC_B" || die "nao consegui por $SVC_A e $SVC_B no Application Catalog"
if [ "$ANUNCIO_PELA_LLS" = 1 ]; then info "$SVC_A e $SVC_B no Application Catalog pela BAMT de teste ($LLS_TOPIC), gravada pelo AoP"
else info "$SVC_A e $SVC_B no Application Catalog pela funcao tv30_announced_services, no lugar do AoP"; fi

# ==================================================================== WARN ===
echo; echo "== 1. modo warn (borda recriada com AUTH_ENFORCE=warn; o padrao e enforce) =="
edge_mode warn || die "edgegateway nao subiu em warn"
if true; then
  for H in "$H_INT" "$H_EXT"; do
    ext_skip "$H" "[warn ${H##*:}] GET /tv3/current-service sem token" \
      || expect_warn "[warn ${H##*:}] GET /tv3/current-service sem token" 107 GET "$H/tv3/current-service"
    ext_skip "$H" "[warn ${H##*:}] GET current-user sem token" \
      || expect_warn "[warn ${H##*:}] GET current-user sem token" 107 GET "$H/tv3/current-service/users/current-user"
    ext_skip "$H" "[warn ${H##*:}] ACAO sem Origin" \
      || expect_acao "[warn ${H##*:}] resposta do tv3ws SEM Origin na requisicao" GET "$H/tv3/current-service"
    ext_skip "$H" "[warn ${H##*:}] ACAO com Origin" \
      || expect_acao "[warn ${H##*:}] resposta do tv3ws COM Origin (sem duplicar)" GET "$H/tv3/current-service" "${AUTH_H[@]}"
    expect_err  "[warn ${H##*:}] GET /tv3/xyz/abc (rota nao declarada)" 100 borda GET "$H/tv3/xyz/abc"
    expect_options "[warn ${H##*:}] OPTIONS sem preflight em rota declarada" "$H/tv3/current-service"
    expect_err  "[warn ${H##*:}] OPTIONS sem preflight em rota nao declarada" 100 borda OPTIONS "$H/tv3/xyz/abc"
    # tv3ws does not check the credential: in warn only the edge warns.
    ext_skip "$H" "[warn ${H##*:}] token adulterado chega ao tv3ws" \
      || expect_warn "[warn ${H##*:}] token adulterado chega ao tv3ws (sem 107 do tv3ws)" 107 GET "$H/tv3/current-service" -H "Authorization: Bearer $AT_BADSIG"
    # API answered by the edge: in warn it answers, with the warning.
    expect_edge_warn "[warn ${H##*:}] GET /tv3/api-info sem token" 107 '^\{"receiverApis":\[\{"id":"tv3ws-' GET "$H/tv3/api-info"
  done
  # 106 also blocks in warn: a client that is not associated does not
  # register a key, and on 44643 the routes exclusive to the local client and
  # /tv3/authorize give 106 (C.4.1.8).
  expect_err "[warn 44642] POST bind-context pelo nao associado (106 tambem em warn)" 106 borda POST "$H_INT/tv3/bind-context" -H 'Content-Type: application/json' -d '{"alg":"HS256","key":"tv30-test-warn"}'
  expect_err "[warn 44643] POST bind-context (exclusiva do cliente local: 106 tambem em warn)" 106 borda POST "$H_EXT/tv3/bind-context" -H 'Content-Type: application/json' -d '{"alg":"HS256","key":"tv30-test-warn"}'
  expect_err "[warn 44643] GET /tv3/authorize (so por HTTP, C.4.1.8: 106 tambem em warn)" 106 borda GET "$H_EXT/tv3/authorize?clientid=x&display-name=y"
  # 304 also blocks in warn, as 300: it needs a valid access token (107 in
  # warn only warns and ends the decision) of an authorized client.
  fcall tv30_client_authorize "$WARN_CID" class standAlone refreshToken tv30-test-warn >/dev/null \
    || fail "autorizacao de $WARN_CID pela funcao recusada"
  servico_corrente "$SVC_A"
  WARN_TOK=(-H "Authorization: Bearer $AT_WARN")
  expect_err "[warn 44642] GET /tv3/$SVC_FORA/users/x (fora do catalogo: 304 tambem em warn)" 304 borda GET "$H_INT/tv3/$SVC_FORA/users/x" "${WARN_TOK[@]}" -H "bind-token: $BT_UNREG"
  expect_err "[warn 44642] POST /tv3/$SVC_FORA/users/x (C.6.14.5 fora do catalogo, em warn)" 304 borda POST "$H_INT/tv3/$SVC_FORA/users/x" "${WARN_TOK[@]}" -H "bind-token: $BT_UNREG" -H 'Content-Type: application/json' -d '{}'
  expect_warn "[warn 44642] GET /tv3/$SVC_A/users/x (do catalogo) com bind-token nao registrado" 108 GET "$H_INT/tv3/$SVC_A/users/x" "${WARN_TOK[@]}" -H "bind-token: $BT_UNREG"
  servico_corrente "$ORIG_SVC"
  # A path with a line break (%0A) does not forge a line in the edge log.
  MARK="tv30forjado$RUN"
  req GET "$H_INT/tv3/abc%0A$MARK"
  if [ "$(docker logs --since 2m edgegateway 2>&1 | grep -c "^$MARK")" = 0 ]; then
    pass "[warn 44642] caminho com %0A nao gera linha forjada no log"
  else fail "[warn 44642] caminho com %0A gerou linha comecando por $MARK no log"; fi
  # Backend frozen in warn: the 404 {error:200} of the edge in place of the
  # 5xx keeps X-TV30-Auth-Warn. docker pause, not stop, so as not to publish
  # the tv3ws ports (45000-45199) again; the trap unfreezes it if the script
  # stops.
  TV3WS_TOUCHED=1
  if docker pause tv3ws >/dev/null 2>&1; then
    expect_err "[warn 44642] tv3ws congelado: GET /tv3/current-service sem token" 200 borda GET "$H_INT/tv3/current-service"
    if [ "$(hdr X-Tv30-Auth-Warn)" = 107 ]; then
      pass "[warn 44642] tv3ws congelado -> X-TV30-Auth-Warn: 107 mantido no 404 {error:200}"
    else
      fail "[warn 44642] tv3ws congelado -> esperado X-TV30-Auth-Warn: 107 no 404 {error:200}, veio '$(hdr X-Tv30-Auth-Warn)'"
    fi
    docker unpause tv3ws >/dev/null 2>&1
    if wait_tv3ws; then pass "[warn] tv3ws descongelado: a borda volta a chegar ao Express"
    else fail "[warn] tv3ws nao voltou a responder pela borda em 90 s"; fi
  else
    fail "[warn] docker pause tv3ws falhou (backend congelado em warn nao testado)"
  fi
fi
# "false" in the pop-up does not authorize (trap: Boolean("false") is true).
authorize "$REFUSED" false
check_err "pop-up recusado (\"false\"): cliente nao autorizado" 102 tv3ws
# The refused client goes to clients:blocked and never to clients:authorized.
if [ "$(rc SISMEMBER clients:blocked "$REFUSED")" = 1 ] && [ "$(rc SISMEMBER clients:authorized "$REFUSED")" = 0 ]; then
  pass "pop-up recusado: clientid em clients:blocked e fora de clients:authorized"
else
  fail "pop-up recusado: blocked=$(rc SISMEMBER clients:blocked "$REFUSED") authorized=$(rc SISMEMBER clients:authorized "$REFUSED") (esperado 1 e 0)"
fi

# 103 with the graphics layer busy (C.4.2.3, Table C.3): with the yes/no of
# a request waiting for an answer, another /tv3/authorize gets 103 at once,
# without a new pop-up, and the SAME clientid too; the first one gets the
# answer.
: >"$TMP/pop103"
docker exec mqtt-broker mosquitto_sub -C 2 -W 10 -t "$POP/message" >"$TMP/pop103" 2>/dev/null &
SUB103=$!
sleep 1
curl -s -m 25 -o "$TMP/b103" -w '%{http_code}' "$H_INT/tv3/authorize?clientid=$C103&display-name=tv30-test-103" >"$TMP/st103" 2>/dev/null &
A103=$!
for _ in $(seq 1 50); do [ -s "$TMP/pop103" ] && break; sleep 0.2; done
if [ -s "$TMP/pop103" ]; then
  expect_err "camada ocupada pelo sim/nao de outro pedido: /tv3/authorize de outro cliente" 103 tv3ws \
    GET "$H_INT/tv3/authorize?clientid=$C103B&display-name=tv30-test-103"
  expect_err "camada ocupada: o MESMO clientid ao mesmo tempo" 103 tv3ws \
    GET "$H_INT/tv3/authorize?clientid=$C103&display-name=tv30-test-103"
else
  fail "camada ocupada: o sim/nao do primeiro pedido nao chegou em $POP/message"
fi
docker exec mqtt-broker mosquitto_pub -q 1 -t "$POP/response" -m false
wait "$A103" 2>/dev/null
if [ "$(cat "$TMP/st103")" = 404 ] && grep -q '"error":102' "$TMP/b103"; then
  pass "camada ocupada: o primeiro pedido recebeu a resposta do espectador (recusa, 102)"
else
  fail "camada ocupada: o primeiro pedido -> status=$(cat "$TMP/st103") corpo=$(head -c 160 "$TMP/b103")"
fi
wait "$SUB103" 2>/dev/null
N103=$(grep -c . "$TMP/pop103")
if [ "$N103" = 1 ]; then pass "camada ocupada: um sim/nao so na tela (os dois 103 nao abriram pop-up)"
else fail "camada ocupada: $N103 mensagens de sim/nao (esperada 1)"; fi
if [ "$(rc SISMEMBER clients:blocked "$C103")" = 1 ] && [ "$(rc EXISTS "client:$C103B")" = 0 ] \
   && [ "$(rc SISMEMBER clients:blocked "$C103B")" = 0 ]; then
  pass "camada ocupada: so o primeiro pedido foi registrado (recusado); o do 103 nao"
else
  fail "camada ocupada: blocked($C103)=$(rc SISMEMBER clients:blocked "$C103") client:$C103B=$(rc EXISTS "client:$C103B") (esperado 1 e 0)"
fi

# ================================================================= ENFORCE ===
# The /manifest exposes to the browser its six own headers
# (Access-Control-Expose-Headers of tv3ws, tv3ws/src/manifest.ts). The edge
# plugin sends another line of the same header (Content-Length,
# X-Tv30-Auth-Warn) without overwriting: both apply, so the case joins them.
req GET "$H_INT/manifest" -H "Origin: $OTHER_ORIGIN"
EXPOSE=$(grep -i '^Access-Control-Expose-Headers:' "$TMP/h2" | cut -d: -f2- | tr '\n' ',')
FALTAM=""
for hname in Server-BaseURL Server-SecureBaseURL Server-PairingMethods Device-BrandName Device-Model Device-FriendlyName; do
  printf '%s' "$EXPOSE" | grep -qi "\(^\|[ ,]\)$hname\([ ,]\|$\)" || FALTAM="$FALTAM $hname"
done
if [ "$ST" = 200 ] && [ -z "$FALTAM" ]; then
  pass "[44642] /manifest expoe os seis cabecalhos ao navegador"
else
  fail "[44642] /manifest: status=$ST, faltam em Access-Control-Expose-Headers:$FALTAM (veio: $EXPOSE)"
fi

echo; echo "== 2. recriando o edgegateway com AUTH_ENFORCE=enforce =="
edge_mode enforce || die "edgegateway nao subiu em enforce"
echo "ok: as duas superficies registraram o plugin em enforce"

# In place of tv3ws (current service) and of the AoP (associated origin),
# through the functions of the schema.
servico_corrente "$SVC_A" || die "nao consegui gravar o servico corrente de teste pela funcao"
fcall tv30_origin_register "$ASSOC" "$SVC_A" >/dev/null || die "nao consegui registrar a origem associada de teste pela funcao"
ASSOC_H=(-H "Origin: $ASSOC")

echo; echo "-- access token (fluxo real /tv3/authorize + /tv3/token) --"
authorize "$CLIENT" true
RT=$(json_str refreshToken)
[ -n "$RT" ] && pass "GET /tv3/authorize (local autonomo, pop-up aceito) -> refreshToken" \
             || fail "GET /tv3/authorize -> sem refreshToken: status=$ST corpo=$(short)"
# The authorized client goes to clients:authorized.
if [ "$(rc SISMEMBER clients:authorized "$CLIENT")" = 1 ] && [ "$(rc SISMEMBER clients:blocked "$CLIENT")" = 0 ]; then
  pass "autorizado: clientid em clients:authorized e fora de clients:blocked"
else
  fail "autorizado: authorized=$(rc SISMEMBER clients:authorized "$CLIENT") blocked=$(rc SISMEMBER clients:blocked "$CLIENT") (esperado 1 e 0)"
fi
# An empty parameter counts as absent: 105 from tv3ws (Table C.4), and the
# legitimate refresh token is still valid right below.
expect_err "GET /tv3/token com refresh-token vazio" 105 tv3ws GET "$H_INT/tv3/token?clientid=$CLIENT&refresh-token="
expect_err "GET /tv3/token com challenge-response vazio" 105 tv3ws GET "$H_INT/tv3/token?clientid=$CLIENT&challenge-response="
req GET "$H_INT/tv3/token?clientid=$CLIENT&refresh-token=$RT"
AT=$(json_str accessToken)
[ -n "$AT" ] && pass "GET /tv3/token -> accessToken" || fail "GET /tv3/token -> sem accessToken: status=$ST corpo=$(short)"
SIG=${AT##*.}; C=${SIG:10:1}; [ "$C" = A ] && N=B || N=A
AT_TAMPER="${AT%.*}.${SIG:0:10}$N${SIG:11}"
TOK=(-H "Authorization: Bearer $AT")

for H in "$H_INT" "$H_EXT"; do
  S="[${H##*:}]"
  expect_err  "$S sem token (GET /tv3/current-service)" 107 borda GET "$H/tv3/current-service"
  expect_err  "$S token adulterado" 107 borda GET "$H/tv3/current-service" -H "Authorization: Bearer $AT_TAMPER"
  expect_err  "$S token expirado" 107 borda GET "$H/tv3/current-service" -H "Authorization: Bearer $AT_EXPIRED"
  expect_err  "$S token sem prefixo Bearer" 107 borda GET "$H/tv3/current-service" -H "Authorization: $AT"
  ext_skip "$H" "$S token valido" || expect_pass "$S token valido" GET "$H/tv3/current-service" "${TOK[@]}"
done

echo; echo "-- TLS na 44643 --"
# 44643 speaks only TLS, with the self-signed certificate of the receiver
# (tls-init).
if [ -z "$H_EXT_FIXO" ]; then
  EXT_HOSTPORT=${H_EXT#https://}
  # Plain HTTP on a TLS port: the Go server answers 400 ("Client sent an
  # HTTP request to an HTTPS server"), without reaching the edge or tv3ws.
  CODE_HTTP=$(curl -s -m 5 -o "$TMP/http44643" -w '%{http_code}' "http://$EXT_HOSTPORT/health")
  if [ "$CODE_HTTP" != 200 ] && grep -q 'HTTPS server' "$TMP/http44643" 2>/dev/null; then
    pass "[44643] HTTP puro recusado ($CODE_HTTP): so TLS"
  else fail "[44643] HTTP puro -> $CODE_HTTP $(head -c 80 "$TMP/http44643" 2>/dev/null) (esperado so TLS)"; fi
  FP_PORTA=$(echo | openssl s_client -connect "$EXT_HOSTPORT" -servername localhost 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
  FP_ARQ=$(openssl x509 -in .tv30/tls/cert.pem -noout -fingerprint -sha256 2>/dev/null)
  if [ -n "$FP_ARQ" ] && [ "$FP_PORTA" = "$FP_ARQ" ]; then pass "[44643] certificado apresentado = .tv30/tls/cert.pem (${FP_ARQ#*=})"
  else fail "[44643] certificado apresentado '$FP_PORTA' diferente do .tv30/tls/cert.pem '$FP_ARQ'"; fi
fi

echo; echo "-- GET /tv3/current-service (C.6.3.1, Tabela C.8) e API-Version nos 100/101 (C.3.6.6) --"
# Service in use of tv3ws = the last aop/currentService (core.app.sid); the
# key session:current-service-id, which the edge reads, is only its mirror.
# The test publishes the topic in place of the platform.
CS_TOUCHED=1
if cs_publish ""; then
  expect_err "[44642] GET /tv3/current-service sem servico em uso" 300 tv3ws GET "$H_INT/tv3/current-service" "${TOK[@]}"
  expect_api_version "[44642] 300 do tv3ws (sem Accept-Version)"
else
  fail "aop/currentService vazio publicado, mas o tv3ws nao o espelhou em session:current-service-id (300 nao testado)"
fi
if cs_publish "$SVC_A"; then
  req GET "$H_INT/tv3/current-service" "${TOK[@]}"
  why=""
  [ "$CE" = 0 ] || why="$why curl=$CE"
  [ "$ST" = 200 ] || why="$why status=$ST"
  [ "$(origin_of)" = tv3ws ] || why="$why origem=borda"
  # The serviceContextId is the globalServiceId of the service in use.
  body | grep -q "\"serviceContextId\":\"$SVC_A\"" || why="$why serviceContextId-diferente-de-$SVC_A"
  # "serviceId" as an integer (Table C.8), or omitted when the testbed does
  # not know it (no SLT; tv3ws would have it only from aop/services, which
  # nobody publishes).
  if body | grep -q '"serviceId":'; then
    body | grep -Eq '"serviceId":[0-9]+[,}]' || why="$why serviceId-nao-inteiro"
  fi
  if [ -z "$why" ]; then
    pass "[44642] GET /tv3/current-service com servico em uso -> 200 do tv3ws, serviceId $(body | grep -q '"serviceId":' && echo inteiro || echo omitido) $(short)"
  else
    fail "[44642] GET /tv3/current-service com servico em uso -> esperado 200 do tv3ws com serviceId inteiro ou omitido:$why corpo=$(short)"
  fi
else
  fail "aop/currentService=$SVC_A publicado, mas o tv3ws nao o espelhou em session:current-service-id (200 nao testado)"
fi
# The edge negotiates the version also on the routes it passes on, by the
# versions of the route in routes.json.
expect_err "[44642] GET /tv3/current-service com Accept-Version 3.0 (fora do conjunto)" 100 borda GET "$H_INT/tv3/current-service" "${TOK[@]}" -H 'Accept-Version: 3.0'
expect_api_version "[44642] 100 da borda: a versao mais recente suportada" 100.0
expect_err "[44642] GET /tv3/current-service com Accept-Version x (malformado)" 101 borda GET "$H_INT/tv3/current-service" "${TOK[@]}" -H 'Accept-Version: x'
expect_api_version "[44642] 101 da borda" 2.0
expect_err "[44642] GET /tv3/current-service com Accept-Version 100.0 (a rota so serve 2.0)" 100 borda GET "$H_INT/tv3/current-service" "${TOK[@]}" -H 'Accept-Version: 100.0'
expect_err "[44642] GET /tv3/current-service com Accept-Version 2.1 (fora do conjunto)" 100 borda GET "$H_INT/tv3/current-service" "${TOK[@]}" -H 'Accept-Version: 2.1'
expect_pass "[44642] GET /tv3/current-service com Accept-Version 2.0" GET "$H_INT/tv3/current-service" "${TOK[@]}" -H 'Accept-Version: 2.0'
expect_api_version "[44642] 200 do tv3ws com Accept-Version 2.0" 2.0
# The internal header sent by the client is removed by the edge: tv3ws
# answers in 2.0.
expect_pass "[44642] X-TV30-API-Version do cliente nao passa" GET "$H_INT/tv3/current-service" "${TOK[@]}" -H 'X-TV30-API-Version: 100.0'
expect_api_version "[44642] X-TV30-API-Version do cliente nao passa" 2.0

# Block by the viewer: the script acts as tv3ws and blocks through the
# function (tv30_client_block: leaves clients:authorized and enters
# clients:blocked, as BlockClient); from here on only the edge checks the
# token of this client. Unblock: there is no service operation, so the
# script removes the id from clients:blocked directly, on purpose; the id
# stays out of both sets, a state that satisfies the schema.
desbloqueia() { rc SREM clients:blocked "$1" >/dev/null; }
fcall tv30_client_block "$CLIENT" >/dev/null || fail "bloqueio de $CLIENT pela funcao recusado"
expect_err "[44642] cliente em clients:blocked" 107 borda GET "$H_INT/tv3/current-service" "${TOK[@]}"
desbloqueia "$CLIENT"
# The edge requires the client in clients:authorized: unblocked without a
# new authorization, it is still refused; back in the set
# (tv30_client_add_authorized, as tv3ws on boot), it passes.
expect_err "[44642] cliente desbloqueado, fora de clients:authorized" 107 borda GET "$H_INT/tv3/current-service" "${TOK[@]}"
fcall tv30_client_add_authorized "$CLIENT" >/dev/null || fail "reinclusao de $CLIENT em clients:authorized pela funcao recusada"
expect_pass "[44642] cliente de volta em clients:authorized passa" GET "$H_INT/tv3/current-service" "${TOK[@]}"

echo; echo "-- reuso de clientid: 101 sem nova consulta ao espectador --"
# A client of its own: if the 101 fails and the pop-up comes out, its
# timeout blocks THIS clientid, not the $CLIENT of the other cases.
authorize "$REUSE" true
if [ "$ST" = 200 ] && [ -n "$(json_str refreshToken)" ]; then
  pass "[44642] primeiro /authorize de $REUSE (local autonomo) -> refreshToken"
  expect_reuse "[44642] segundo /authorize do mesmo clientid local" \
    "$H_INT/tv3/authorize?clientid=$REUSE&display-name=tv30-test-auth"
else
  fail "[44642] primeiro /authorize de $REUSE -> status=$ST corpo=$(short) (reuso nao testado)"
fi

echo; echo "-- rotas token+bind sem bind-token --"
expect_err "[44642] GET current-user com token, sem bind-token" 104 borda GET "$H_INT/tv3/current-service/users/current-user" "${TOK[@]}"
expect_err "[44643] POST sensory-effect com token, sem bind-token" 104 borda POST "$H_EXT/tv3/sensory-effect-renderers/x" "${TOK[@]}" -H 'Content-Type: application/json' -d '{}'
expect_err "[44642] POST /tv3/current-service/users sem bind-token" 104 borda POST "$H_INT/tv3/current-service/users" "${TOK[@]}" -H 'Content-Type: application/json' -d '{}'
# POST /tv3/{serviceContextId}/users is not in Table C.2 (the standard
# defines only current-service/users, C.6.14.1): the edge answers 100.
expect_err "[44642] POST /tv3/xyz/users (rota fora da norma)" 100 borda POST "$H_INT/tv3/xyz/users" "${TOK[@]}" -H 'Content-Type: application/json' -d '{}'

echo; echo "-- POST /tv3/bind-context (associado simulado: Origin em origins:associated) --"
for A in HS256 HS512 RS256 RS512; do
  v="BODY_$A"
  req POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d "${!v}"
  if [ "$ST" = 200 ] && body | grep -q '"serviceContextId"'; then pass "POST bind-context $A -> 200 $(short)"
  else fail "POST bind-context $A -> status=$ST corpo=$(short)"; fi
done
if [ -n "${BODY_NORMA:-}" ]; then
  req POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d "$BODY_NORMA"
  [ "$ST" = 200 ] && pass "POST bind-context RS256 com chave privada de 512 bits (${NORMA_PRIV:0:12}..., como o exemplo da norma) -> 200" \
                  || fail "POST bind-context RS256 512 bits -> status=$ST corpo=$(short)"
else
  info "chave de 512 bits nao gerada neste node (${NORMA_ERRO:-?}) — caso pulado"
fi
N1=$(rc LLEN "bind-context:$SVC_A")
req POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d "$BODY_HS256"
N2=$(rc LLEN "bind-context:$SVC_A")
[ "$ST" = 200 ] && [ "$N1" = "$N2" ] && pass "POST repetido -> 200 sem duplicata (LLEN=$N2)" || fail "POST repetido -> status=$ST LLEN $N1 -> $N2"
expect_err "POST bind-context por nao associado (sem Origin associado)" 106 borda POST "$H_INT/tv3/bind-context" -H 'Content-Type: application/json' -d "$BODY_HS256"
# Body validation and logic of C.6.8.2, answered by the edge
# (infra/edgegateway/plugin/bindcontext.go).
expect_err "POST bind-context sem key" 105 borda POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d '{"alg":"HS256"}'
expect_err "POST bind-context alg fora dos 4" 101 borda POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d '{"alg":"ES256","key":"x"}'
expect_err "POST bind-context RS256 com chave que nao e RSA" 101 borda POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d '{"alg":"RS256","key":"nao-e-chave"}'
# Only JSON (not form-urlencoded).
expect_err "POST bind-context com Content-Type text/plain" 101 borda POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: text/plain' -d "$BODY_HS512"
expect_edge "POST bind-context com Accept-Version 2.0 (repetido; serviceContextId = o servico corrente)" '^\{"serviceContextId":"'"$SVC_A"'"\}$' 2.0 \
  POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Accept-Version: 2.0' -H 'Content-Type: application/json' -d "$BODY_HS512"
# C.4.1.8: on 44643 the API exclusive to the local client answers 106 to any
# request.
expect_err "[44643] POST bind-context (exclusiva do cliente local)" 106 borda \
  POST "$H_EXT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d "$BODY_HS512"
# Without a current service there is nothing to bind the key to: 300 ("No
# DTV service currently in use").
servico_corrente ""
expect_err "POST bind-context sem servico corrente" 300 borda POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d "$BODY_HS256"
servico_corrente "$SVC_A"

echo; echo "-- bind-token assinado com cada chave registrada --"
CU="/tv3/current-service/users/current-user"
for A in HS256 HS512 RS256 RS512 NORMA; do
  v="BT_$A"; [ -n "${!v:-}" ] || continue
  expect_pass "[44642] $CU com bind-token $A" GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: ${!v}"
done
ext_skip "$H_EXT" "[44643] $CU com bind-token RS512" \
  || expect_pass "[44643] $CU com bind-token RS512" GET "$H_EXT$CU" "${TOK[@]}" -H "bind-token: $BT_RS512"
expect_pass "[44642] GET /tv3/$SVC_A/users/x (scid = globalServiceId do corrente)" GET "$H_INT/tv3/$SVC_A/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "[44642] GET /tv3/$SCID_CONST/users/x (constante fixa, nao e servico: fora do catalogo)" 304 borda GET "$H_INT/tv3/$SCID_CONST/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "[44642] POST /tv3/$SVC_A/users com bind-token (rota fora da norma)" 100 borda POST "$H_INT/tv3/$SVC_A/users" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'

echo; echo "-- servico fora do Application Catalog (304 da C.6.14.2 e da C.6.14.5) --"
# 107 -> 300 -> 304 -> bind-token: outside services:announced there is no
# bind context, and 304 comes before 104 and 108.
expect_err "[44642] GET /tv3/$SVC_FORA/users/x com access token e bind-token valido de $SVC_A" 304 borda GET "$H_INT/tv3/$SVC_FORA/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "[44642] POST /tv3/$SVC_FORA/users/x (C.6.14.5) com access token e bind-token valido de $SVC_A" 304 borda POST "$H_INT/tv3/$SVC_FORA/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'
expect_err "[44642] GET /tv3/$SVC_FORA/users/x sem bind-token (304 antes do 104)" 304 borda GET "$H_INT/tv3/$SVC_FORA/users/x" "${TOK[@]}"
expect_err "[44642] GET /tv3/$SVC_FORA/users/x sem access token (107 antes do 304)" 107 borda GET "$H_INT/tv3/$SVC_FORA/users/x" -H "bind-token: $BT_HS256"
expect_err "[44643] GET /tv3/$SVC_FORA/users/x com access token e bind-token valido de $SVC_A" 304 borda GET "$H_EXT/tv3/$SVC_FORA/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "associado em /tv3/$SVC_FORA/users/x sem credencial" 304 borda GET "$H_INT/tv3/$SVC_FORA/users/x" "${ASSOC_H[@]}"
# The same request with a service of the catalog goes on to the bind-token.
expect_err "[44642] GET /tv3/$SVC_B/users/x (do catalogo, sem chave registrada) com bind-token de $SVC_A" 108 borda GET "$H_INT/tv3/$SVC_B/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_pass "[44642] POST /tv3/$SVC_A/users/x (C.6.14.5, do catalogo) com bind-token valido" POST "$H_INT/tv3/$SVC_A/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'
# current-service is the tuned service: the catalog is not checked.
expect_pass "[44642] POST /tv3/current-service/users/x com bind-token valido (sem conferencia do catalogo)" POST "$H_INT/tv3/current-service/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'

echo; echo "-- Application Catalog: os mesmos servicos na tela, em services:announced, em aop/services e na borda --"
if [ "$ANUNCIO_PELA_LLS" = 1 ] && curl -s -m 5 -o /dev/null "$AOP/appcat"; then
  TELA=$(curl -s -m 5 "$AOP/appcat" | grep -o 'selectParam="[^"]*"' | sed 's/^selectParam="//; s/"$//' | sort)
  NO_REDIS=$(rc --raw SMEMBERS services:announced | tr -d '\r' | sort)
  NO_TOPICO=$(docker exec mqtt-broker mosquitto_sub -t aop/services -C 1 -W 2 --retained-only 2>/dev/null \
    | grep -o '"serviceContextId":"[^"]*"' | sed 's/^"serviceContextId":"//; s/"$//' | sort)
  # shellcheck disable=SC2086
  if [ -n "$TELA" ] && [ "$TELA" = "$NO_REDIS" ]; then pass "tela do catalogo = services:announced ($(echo $TELA))"
  else fail "tela do catalogo '$(echo $TELA)' diferente de services:announced '$(echo $NO_REDIS)'"; fi
  # shellcheck disable=SC2086
  if [ "$NO_TOPICO" = "$NO_REDIS" ]; then pass "aop/services retido = services:announced"
  else fail "aop/services retido '$(echo $NO_TOPICO)' diferente de services:announced '$(echo $NO_REDIS)'"; fi
  if printf '%s\n' "$TELA" | grep -qxF "$SVC_A" && printf '%s\n' "$TELA" | grep -qxF "$SVC_B" && ! printf '%s\n' "$TELA" | grep -qxF "$SVC_FORA"; then
    pass "tela do catalogo com $SVC_A e $SVC_B (BAMT de teste) e sem $SVC_FORA"
  else fail "tela do catalogo sem $SVC_A ou $SVC_B, ou com $SVC_FORA: $(echo "$TELA" | tr '\n' ' ')"; fi
  # Every service of the screen is recognized by the edge: an unregistered
  # bind-token gives 108, not 304.
  N304=""
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    req GET "$H_INT/tv3/$s/users/x" "${TOK[@]}" -H "bind-token: $BT_UNREG"
    body | grep -q '"error":304' && N304="$N304 $s"
  done <<<"$TELA"
  if [ -z "$N304" ]; then pass "a borda reconhece cada servico da tela (nenhum 304)"
  else fail "a borda respondeu 304 a servico(s) da tela:$N304"; fi
else
  info "sem o AoP gravando a LLS (ou fora do ar em $AOP): tela do catalogo e aop/services nao conferidos"
fi

echo; echo "-- bind-token invalido --"
expect_err "bind-token de chave nao registrada" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_UNREG"
expect_err "confusao de algoritmo (HS256 assinado com a chave publica RS256 registrada)" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_CONFUSION"
expect_err "bind-token com nbf no futuro" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_NBF"
expect_err "bind-token expirado" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_EXP"
expect_err "bind-token com iat no futuro" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_IAT"
expect_err "bind-token alg none" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_NONE"
expect_err "bind-token que nao e JWT" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: abc"
expect_err "scid de outro servico do catalogo com bind-token do corrente (valem as chaves daquele servico)" 108 borda GET "$H_INT/tv3/$SVC_B/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "POST /tv3/xyz/users com bind-token valido (rota fora da norma)" 100 borda POST "$H_INT/tv3/xyz/users" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'
expect_err "POST /tv3/Current-Service/users (caixa trocada: nao casa com current-service)" 100 borda POST "$H_INT/tv3/Current-Service/users" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'

echo; echo "-- sem servico DTV selecionado --"
# 300 on the APIs whose table lists it (C.6.4.7, C.6.14.1 to C.6.14.6),
# after the access token and before the bind-token; 108 on C.6.16.3, whose
# table does not list it.
servico_corrente ""
expect_err "sem servico: $CU com token e bind-token" 300 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "sem servico: $CU sem bind-token (300 antes do 104)" 300 borda GET "$H_INT$CU" "${TOK[@]}"
expect_err "sem servico: $CU sem access token (107 antes do 300)" 107 borda GET "$H_INT$CU" -H "bind-token: $BT_HS256"
expect_err "sem servico: C.6.4.7 (apps/{appid}/files)" 300 borda GET "$H_INT/tv3/current-service/apps/x/files" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "sem servico: C.6.16.3 (a tabela nao lista o 300)" 108 borda POST "$H_INT/tv3/sensory-effect-renderers/x" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'
servico_corrente "$SVC_A"

echo; echo "-- isolamento entre emissoras --"
servico_corrente "$SVC_B"
expect_err "servico corrente trocado: bind-token da emissora A" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS256"
servico_corrente "$SVC_A"
expect_pass "servico A de volta: o mesmo bind-token passa" GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS256"

echo; echo "-- associado: sem access token e sem bind-token --"
expect_pass "associado em $CU sem credencial" GET "$H_INT$CU" "${ASSOC_H[@]}"
expect_err  "associado em /tv3/authorize (so em enforce)" 106 borda GET "$H_INT/tv3/authorize?clientid=x&display-name=y" "${ASSOC_H[@]}"
expect_err  "associado em /tv3/authorize com Authorization qualquer (nao escapa do 106)" 106 borda GET "$H_INT/tv3/authorize?clientid=x&display-name=y" "${ASSOC_H[@]}" -H 'Authorization: x'
expect_err  "associado em /tv3/token com Authorization qualquer (nao escapa do 106)" 106 borda GET "$H_INT/tv3/token?clientid=x&refresh-token=y" "${ASSOC_H[@]}" -H 'Authorization: x'
# The associated Origin gives 106 also with a VALID access token of another
# class.
expect_err  "associado em /tv3/authorize com access token valido de autonomo" 106 borda GET "$H_INT/tv3/authorize?clientid=x&display-name=y" "${ASSOC_H[@]}" "${TOK[@]}"
expect_err  "associado em /tv3/token com access token valido de autonomo" 106 borda GET "$H_INT/tv3/token?clientid=x&refresh-token=y" "${ASSOC_H[@]}" "${TOK[@]}"
# C.4.1.8: C.6.1.2 only over HTTP; on 44643, 106 to any request.
expect_err  "[44643] GET /tv3/authorize (C.6.1.2 so por HTTP)" 106 borda GET "$H_EXT/tv3/authorize?clientid=x&display-name=y"

echo; echo "-- associado em contexto de outra emissora --"
# The test origin was registered for $SVC_A (the service that "launched" the
# application); in its own context it is exempt from the bind-token; in
# another, the general rule applies.
expect_pass "associado em /tv3/$SVC_A/users/x (proprio contexto) sem credencial" GET "$H_INT/tv3/$SVC_A/users/x" "${ASSOC_H[@]}"
expect_err  "associado em /tv3/$SVC_B/users/x sem bind-token" 104 borda GET "$H_INT/tv3/$SVC_B/users/x" "${ASSOC_H[@]}"
expect_err  "associado em /tv3/$SVC_B/users/x com bind-token de $SVC_A" 108 borda GET "$H_INT/tv3/$SVC_B/users/x" "${ASSOC_H[@]}" -H "bind-token: $BT_HS256"
# Key registered for $SVC_B (the registration applies to the current
# service).
servico_corrente "$SVC_B"
req POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d "$BODY_HS512"
servico_corrente "$SVC_A"
expect_pass "associado em /tv3/$SVC_B/users/x com bind-token valido de $SVC_B" GET "$H_INT/tv3/$SVC_B/users/x" "${ASSOC_H[@]}" -H "bind-token: $BT_HS512"

echo; echo "-- associado de verdade: app do bcast aberta pelo AoP na origem propria --"
# The AoP opens each broadcaster application on
# http://<label>.apps.localhost:8080 and writes that origin to
# origins:associated when it launches it (and removes it when it closes);
# it is the Origin the browser sends in the calls of the application. The
# script acts as the browser: opens users-test by the flow of the AoP
# (catalog and full screen), reads the stored origin and calls the edge with
# it. Selecting the service publishes aop/currentService again (the trap
# restores the retained one), and the script sets session:current-service-id
# back to SVC_A right after.
SID_USERS_TEST=${USERS_TEST_SID:-urn:tv30:service:users-test}
if curl -s -m 5 -o /dev/null "$AOP/appcat"; then
  curl -s -m 5 -o /dev/null "$AOP/appcat/select?id=$SID_USERS_TEST"
  sleep 2
  curl -s -m 5 -o /dev/null "$AOP/btpapp/fullscr"
  APP_ORIGIN=""
  for _ in $(seq 1 10); do
    APP_ORIGIN=$(rc --raw HKEYS origins:associated | tr -d '\r' | grep -m1 -E '^http://[a-z0-9-]+\.apps\.localhost:[0-9]+$')
    [ -n "$APP_ORIGIN" ] && break
    sleep 1
  done
  if [ -n "$APP_ORIGIN" ]; then
    pass "AoP gravou a origem propria da app em origins:associated: $APP_ORIGIN"
    expect_pass "app aberta pelo AoP (Origin $APP_ORIGIN) em $CU sem credencial" GET "$H_INT$CU" -H "Origin: $APP_ORIGIN"
    expect_err "Origin do proprio AoP ($AOP), sem credencial" 107 borda GET "$H_INT$CU" -H "Origin: $AOP"
    # ESC: closes the graphics layer.
    curl -s -m 5 -o /dev/null "$AOP/keydown/27"
    if [ -z "$(rc HEXISTS origins:associated "$APP_ORIGIN" | tr -d '\r' | grep -x 1)" ]; then
      pass "ESC no AoP removeu $APP_ORIGIN de origins:associated"
    else
      fail "ESC no AoP nao removeu $APP_ORIGIN de origins:associated"
    fi
    expect_err "a mesma origem depois de a app fechar, sem credencial" 107 borda GET "$H_INT$CU" -H "Origin: $APP_ORIGIN"
  else
    fail "AoP nao gravou origem <rotulo>.apps.localhost em origins:associated depois de abrir $SID_USERS_TEST: $(rc --raw HKEYS origins:associated | tr '\n' ' ')"
    curl -s -m 5 -o /dev/null "$AOP/keydown/27"
  fi
  curl -s -m 5 -o /dev/null "$AOP/btpapp/appcat"
  servico_corrente "$SVC_A"
else
  info "AoP fora do ar em $AOP: casos da app de verdade pulados"
fi

echo; echo "-- GET /tv3/bind-context --"
req GET "$H_INT/tv3/bind-context" "${TOK[@]}" -H "bind-token: $BT_HS256"
if [ "$ST" = 200 ] && body | grep -q "\"boundServices\":\[{\"serviceContextId\":\"$SVC_A\""; then
  pass "GET bind-context -> 200 $(short)"
else fail "GET bind-context -> status=$ST corpo=$(short)"; fi
expect_edge "[44643] GET bind-context pela superficie externa" '^\{"boundServices":\[\{"serviceContextId":"'"$SVC_A"'"' \
  GET "$H_EXT/tv3/bind-context" "${TOK[@]}" -H "bind-token: $BT_RS512"
expect_err "GET bind-context sem bind-token" 104 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}" "${AUTH_H[@]}"
expect_err "GET bind-context sem bind-token, SEM Origin" 104 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}"
# A signature of a registered key, out of its period: 108 (the signature
# comes first).
expect_err "GET bind-context com bind-token expirado" 108 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}" -H "bind-token: $BT_EXP"
expect_err "GET bind-context com bind-token que nao e JWT" 108 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}" -H "bind-token: abc"
# An error from tv3ws, for a client outside the browser (no Origin) and with
# Origin: ACAO * once (C.4.1.9.2).
expect_err "POST /tv3/remote-device com {} (erro do tv3ws), SEM Origin" 105 tv3ws POST "$H_INT/tv3/remote-device" "${TOK[@]}" -H 'Content-Type: application/json' -d '{}'
expect_acao "erro do tv3ws SEM Origin: ACAO uma vez" POST "$H_INT/tv3/remote-device" "${TOK[@]}" -H 'Content-Type: application/json' -d '{}'
expect_acao "erro do tv3ws COM Origin: ACAO uma vez" POST "$H_INT/tv3/remote-device" "${TOK[@]}" "${AUTH_H[@]}" -H 'Content-Type: application/json' -d '{}'
expect_acao "erro da borda SEM Origin: ACAO uma vez" GET "$H_INT/tv3/current-service"
expect_acao "erro da API da borda (C.6.8) COM Origin: ACAO uma vez" GET "$H_INT/tv3/bind-context" "${TOK[@]}" "${AUTH_H[@]}"
expect_err "GET bind-context sem access token" 107 borda GET "$H_INT/tv3/bind-context" -H "bind-token: $BT_HS256"
expect_err "GET bind-context pelo associado" 106 borda GET "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H "bind-token: $BT_HS256"

echo; echo "-- DELETE /tv3/bind-context (revogacao) --"
req DELETE "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H "key: $HS256_KEY"
[ "$ST" = 200 ] && [ "$(body)" = "{}" ] && pass "DELETE bind-context HS256 -> 200 {}" || fail "DELETE bind-context -> status=$ST corpo=$(short)"
expect_err "bind-token da chave revogada" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "GET bind-context com token da chave revogada" 101 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}" "${AUTH_H[@]}" -H "bind-token: $BT_HS256"
expect_pass "as demais chaves continuam valendo (HS512)" GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS512"
req DELETE "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H "key: $RS256_DER"
expect_err "RS256 revogada pelo DER base64 (registrada em PEM)" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_RS256"
req DELETE "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H "key: tv30-test-inexistente"
[ "$ST" = 200 ] && pass "DELETE de chave inexistente -> 200" || fail "DELETE inexistente -> status=$ST corpo=$(short)"
expect_err "DELETE sem cabecalho key" 105 borda DELETE "$H_INT/tv3/bind-context" "${ASSOC_H[@]}"
expect_err "DELETE por nao associado" 106 borda DELETE "$H_INT/tv3/bind-context" -H "key: $HS512_KEY"
# The DELETE (classes: associated) also gives 106 on 44643.
expect_err "[44643] DELETE bind-context (exclusiva do cliente local)" 106 borda DELETE "$H_EXT/tv3/bind-context" "${ASSOC_H[@]}" -H "key: $HS512_KEY"
expect_pass "a HS512 continua registrada depois do DELETE recusado na 44643" GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS512"
servico_corrente ""
expect_edge "DELETE sem servico corrente -> {} (nada a remover)" '^\{\}$' DELETE "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H "key: $HS512_KEY"
servico_corrente "$SVC_A"
expect_pass "a HS512 continua registrada depois do DELETE sem servico corrente" GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS512"

echo; echo "-- APIs de informacao de API (C.6.7.8, C.6.7.9), respondidas pela borda --"
# List and version come from infra/edgegateway/routes.json (field api, Table
# C.2), in the order of the table; the testbed implements only APIs of the
# tv3ws subsystem.
API_N=$(grep -o '"id": *"tv3ws-[^"]*"' infra/edgegateway/routes.json | sort -u | wc -l | tr -d " ")
req GET "$H_INT/tv3/api-info" "${TOK[@]}"
N=$(body | grep -o '"id":' | wc -l | tr -d " ")
if [ "$ST" = 200 ] && [ "$(origin_of)" = borda ] && [ "$N" = "$API_N" ] \
   && body | grep -q '^{"receiverApis":\[{"id":"tv3ws-application-authorization","version":"2.0"}'; then
  pass "[44642] GET /tv3/api-info (C.6.7.9) -> 200 da borda, $N APIs (= ids distintos do routes.json), a primeira tv3ws-application-authorization"
else
  fail "[44642] GET /tv3/api-info -> status=$ST origem=$(origin_of) ids=$N (routes.json: $API_N) corpo=$(short)"
fi
LIST_ALL=$(body)
expect_edge "[44642] GET /tv3/api-info (cabecalhos da resposta)" '^\{"receiverApis":' GET "$H_INT/tv3/api-info" "${TOK[@]}"
req GET "$H_INT/tv3/api-info?subsystem=tv3ws" "${TOK[@]}"
[ "$ST" = 200 ] && [ "$(body)" = "$LIST_ALL" ] && pass "[44642] GET /tv3/api-info?subsystem=tv3ws -> a mesma lista" \
  || fail "[44642] ?subsystem=tv3ws -> status=$ST corpo diferente da lista sem subsystem: $(short)"
expect_edge "[44643] GET /tv3/api-info?subsystem=tv3ws" '^\{"receiverApis":\[\{"id":"tv3ws-application-authorization"' GET "$H_EXT/tv3/api-info?subsystem=tv3ws" "${TOK[@]}"
# 44643 lists ALL implemented APIs, as 44642 does, and C.6.7.8 answers for
# all of them.
req GET "$H_EXT/tv3/api-info" "${TOK[@]}"
if [ "$ST" = 200 ] && [ "$(origin_of)" = borda ] && [ "$(body)" = "$LIST_ALL" ]; then
  pass "[44643] GET /tv3/api-info -> a mesma lista da 44642 ($API_N APIs)"
else
  fail "[44643] GET /tv3/api-info -> status=$ST origem=$(origin_of), esperada a lista da 44642 corpo=$(short)"
fi
expect_edge "[44643] GET /tv3/api-info/tv3ws-bind-context-register" '^\{"receiverApi":\{"id":"tv3ws-bind-context-register","version":"2.0"\}\}$' GET "$H_EXT/tv3/api-info/tv3ws-bind-context-register" "${TOK[@]}"
# C.6.7.8: the APIs of C.6.15 and C.6.2 report 100.0, the latest version
# they serve.
for API in tv3ws-remotedevice-register tv3ws-remotedevice-cancel tv3ws-remotedevice-communication tv3ws-register-notifications tv3ws-deregister-notifications; do
  expect_edge "[44643] GET /tv3/api-info/$API" "^\\{\"receiverApi\":\\{\"id\":\"$API\",\"version\":\"100\\.0\"\\}\\}\$" GET "$H_EXT/tv3/api-info/$API" "${TOK[@]}"
done
expect_edge "[44642] GET /tv3/api-info/tv3ws-bind-context-register" '^\{"receiverApi":\{"id":"tv3ws-bind-context-register","version":"2.0"\}\}$' GET "$H_INT/tv3/api-info/tv3ws-bind-context-register" "${TOK[@]}"
expect_edge "[44642] GET /tv3/api-info?subsystem=ncl (subsistema conhecido, sem API)" '^\{"receiverApis":\[\]\}$' GET "$H_INT/tv3/api-info?subsystem=ncl" "${TOK[@]}"
expect_edge "[44642] GET /tv3/api-info?subsystem=nclua" '^\{"receiverApis":\[\]\}$' GET "$H_INT/tv3/api-info?subsystem=nclua" "${TOK[@]}"
expect_err "[44642] GET /tv3/api-info?subsystem=x (desconhecido)" 101 borda GET "$H_INT/tv3/api-info?subsystem=x" "${TOK[@]}"
expect_err "[44642] GET /tv3/api-info?subsystem= (vazio)" 101 borda GET "$H_INT/tv3/api-info?subsystem=" "${TOK[@]}"
expect_edge "[44642] GET /tv3/api-info/tv3ws-api-info (C.6.7.8)" '^\{"receiverApi":\{"id":"tv3ws-api-info","version":"2.0"\}\}$' GET "$H_INT/tv3/api-info/tv3ws-api-info" "${TOK[@]}"
expect_edge "[44643] GET /tv3/api-info/tv3ws-bind-context-list" '^\{"receiverApi":\{"id":"tv3ws-bind-context-list","version":"2.0"\}\}$' GET "$H_EXT/tv3/api-info/tv3ws-bind-context-list" "${TOK[@]}"
expect_err "[44642] GET /tv3/api-info/tv3ws-geolocation-info (na Tabela C.2, nao implementada)" 101 borda GET "$H_INT/tv3/api-info/tv3ws-geolocation-info" "${TOK[@]}"
expect_err "[44642] GET /tv3/api-info/nao-existe" 101 borda GET "$H_INT/tv3/api-info/nao-existe" "${TOK[@]}"
expect_err "[44642] GET /tv3/api-info sem access token" 107 borda GET "$H_INT/tv3/api-info"
expect_err "[44643] GET /tv3/api-info/tv3ws-api-info sem access token" 107 borda GET "$H_EXT/tv3/api-info/tv3ws-api-info"
expect_err "[44642] GET /tv3/api-info com token adulterado" 107 borda GET "$H_INT/tv3/api-info" -H "Authorization: Bearer $AT_TAMPER"
expect_edge "[44642] GET /tv3/api-info pelo associado (Origin, sem token)" '^\{"receiverApis":\[\{"id":"tv3ws-' GET "$H_INT/tv3/api-info" "${ASSOC_H[@]}"
# Version negotiation (C.3.6.5) on the edge APIs: the same contract as
# tv3ws.
expect_edge "[44642] GET /tv3/api-info com Accept-Version 2.0" '^\{"receiverApis":' 2.0 GET "$H_INT/tv3/api-info" "${TOK[@]}" -H 'Accept-Version: 2.0'
expect_err "[44642] GET /tv3/api-info com Accept-Version 100.0 (a API so serve 2.0)" 100 borda GET "$H_INT/tv3/api-info" "${TOK[@]}" -H 'Accept-Version: 100.0'
# API-Version (C.3.6.6) of these edge errors: 100.0 (the latest supported)
# on 100, 2.0 on 101, the same as tv3ws.
expect_err "[44642] GET /tv3/api-info com Accept-Version 3.0 (fora do conjunto)" 100 borda GET "$H_INT/tv3/api-info" "${TOK[@]}" -H 'Accept-Version: 3.0'
expect_api_version "[44642] 100 da borda: a versao mais recente suportada" 100.0
expect_err "[44642] GET /tv3/api-info com Accept-Version x (malformado)" 101 borda GET "$H_INT/tv3/api-info" "${TOK[@]}" -H 'Accept-Version: x'
expect_api_version "[44642] 101 da borda" 2.0
expect_err "[44642] GET /tv3/bind-context com Accept-Version 3.0" 100 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}" -H "bind-token: $BT_HS512" -H 'Accept-Version: 3.0'
expect_api_version "[44642] 100 da borda em /tv3/bind-context" 100.0
expect_err "[44642] PUT /tv3/api-info (metodo nao declarado)" 100 borda PUT "$H_INT/tv3/api-info" "${TOK[@]}"
# CORS of the edge routes: the plugin answers the preflight and the OPTIONS
# without preflight.
for H in "$H_INT" "$H_EXT"; do
  S="[${H##*:}]"
  expect_preflight "$S preflight GET /tv3/api-info" "$H/tv3/api-info" GET authorization
  expect_preflight "$S preflight GET /tv3/api-info/{apiId}" "$H/tv3/api-info/tv3ws-api-info" GET accept-version,authorization
  expect_preflight "$S preflight POST /tv3/bind-context" "$H/tv3/bind-context" POST content-type
  expect_preflight "$S preflight GET /tv3/bind-context" "$H/tv3/bind-context" GET authorization,bind-token
  expect_preflight "$S preflight DELETE /tv3/bind-context" "$H/tv3/bind-context" DELETE key
  expect_options "$S OPTIONS sem preflight em /tv3/api-info" "$H/tv3/api-info"
  expect_options "$S OPTIONS sem preflight em /tv3/bind-context" "$H/tv3/bind-context"
done

echo; echo "-- cliente NAO local: pareamento real (C.4.3, C.6.1.2, C.6.1.3) --"
# First access over HTTP on 44642 (Server-BaseURL of SSDP); use and renewal
# on 44643 (Server-SecureBaseURL). Renewal of /token over HTTP gets 106 from
# tv3ws itself (client-identification/controller.ts); on the OTHER APIs, a
# non-local client over HTTP gets 106 from the edge (C.4.1.6), also in warn.
for PM in qrcode kex; do
  if [ "$PM" = qrcode ]; then NCID=$NL_QR; else NCID=$NL_KEX; fi
  S="[nao local $PM]"
  pair "$PM" "$NCID" || { info "$S pareamento incompleto: uso, renovacao e reuso deste cliente pulados"; continue; }
  # ECDH key of the client used in the pairing (kex).
  NL_REUSE_KEY=${NL_CPUB:-}
  NL_TOK=(-H "Authorization: Bearer $NL_AT")
  # The challenge is discarded on success: 102 from tv3ws (Table C.4).
  expect_err "$S [44642] challenge-response repetido (desafio ja usado)" 102 tv3ws GET "$H_INT/tv3/token?clientid=$NCID&challenge-response=$NL_CR"
  if [ "$(rc SISMEMBER clients:authorized "$NCID")" = 1 ]; then
    pass "$S clientid em clients:authorized depois do pareamento"
  else
    fail "$S clientid fora de clients:authorized depois do pareamento"
  fi
  if ! ext_skip "$H_EXT" "$S [44643] GET /tv3/current-service com o accessToken"; then
    expect_pass "$S [44643] GET /tv3/current-service com o accessToken" GET "$H_EXT/tv3/current-service" "${NL_TOK[@]}"
  fi
  if ! ext_skip "$H_EXT" "$S [44643] $CU com bind-token HS512"; then
    expect_pass "$S [44643] $CU com bind-token HS512" GET "$H_EXT$CU" "${NL_TOK[@]}" -H "bind-token: $BT_HS512"
  fi
  # C.4.1.6: on 44642 (HTTP) a non-local client only uses C.6.1.2 and
  # C.6.1.3; on the others, 106 from the edge, also on the APIs it answers.
  expect_err "$S [44642] API fora de /authorize e /token por HTTP" 106 borda GET "$H_INT/tv3/current-service" "${NL_TOK[@]}"
  expect_err "$S [44642] /tv3/api-info por HTTP" 106 borda GET "$H_INT/tv3/api-info" "${NL_TOK[@]}"
  # C.6.15.5 only for the local client: 106 to a non-local one on both ports
  # (on 44642, a class rule; on 44643, exclusive to the local client,
  # C.4.1.8).
  expect_err "$S [44642] GET /tv3/remote-device/devices/x (C.6.15.5, so cliente local)" 106 borda GET "$H_INT/tv3/remote-device/devices/x" "${NL_TOK[@]}"
  expect_err "$S [44643] GET /tv3/remote-device/devices/x (exclusiva do cliente local)" 106 borda GET "$H_EXT/tv3/remote-device/devices/x" "${NL_TOK[@]}"
  # Notifications (C.6.2.2, C.6.2.3; only 100.0): the same rule.
  expect_err "$S [44642] GET /tv3/notifications/remote-device (100.0, so cliente local)" 106 borda GET "$H_INT/tv3/notifications/remote-device" "${NL_TOK[@]}" -H 'Accept-Version: 100.0'
  expect_err "$S [44643] GET /tv3/notifications/remote-device (exclusiva do cliente local)" 106 borda GET "$H_EXT/tv3/notifications/remote-device" "${NL_TOK[@]}" -H 'Accept-Version: 100.0'
  expect_err "$S [44642] DELETE /tv3/notifications/x (100.0, so cliente local)" 106 borda DELETE "$H_INT/tv3/notifications/x" "${NL_TOK[@]}" -H 'Accept-Version: 100.0'
  expect_err "$S [44643] DELETE /tv3/notifications/x (exclusiva do cliente local)" 106 borda DELETE "$H_EXT/tv3/notifications/x" "${NL_TOK[@]}" -H 'Accept-Version: 100.0'
  expect_err "$S [44642] renovacao por HTTP com refresh-token" 106 tv3ws GET "$H_INT/tv3/token?clientid=$NCID&refresh-token=$NL_RT"
  if ! ext_skip "$H_EXT" "$S [44643] renovacao com refresh-token"; then
    req GET "$H_EXT/tv3/token?clientid=$NCID&refresh-token=$NL_RT"
    RCT=$(hdr Content-Type)
    if [ "$ST" = 200 ] && nl_node MODO=token CT="$RCT" BODY="$(base64 <"$TMP/b" | tr -d "\n")" SECRET="$NL_SECRET" \
       && [ "$NL_ENC" = 0 ] && [ -n "$NL_AT" ] && [ "$NL_CLASS" = nonLocal ]; then
      pass "$S [44643] renovacao com refresh-token -> 200 JSON sem a cifra do primeiro acesso, accessToken class=nonLocal"
    else
      fail "$S [44643] renovacao com refresh-token -> status=$ST content-type='$RCT' corpo=$(short) ${NL_ERR}"
    fi
  fi
  # Reuse by the SAME pairing method: for kex the key of the client goes too
  # (without key tv3ws would give 105 before looking at the clientid).
  if [ "$PM" = kex ]; then RQ="&key=$NL_REUSE_KEY"; else RQ=""; fi
  expect_reuse "$S segundo /authorize do mesmo clientid (pm=$PM)" \
    "$H_INT/tv3/authorize?clientid=$NCID&display-name=tv30-test-nao-local&pm=$PM$RQ"
done

expect_pass "[44642] GET /tv3/remote-device/devices/x (C.6.15.5) pelo cliente local" GET "$H_INT/tv3/remote-device/devices/x" "${TOK[@]}"
# 100.0 (proposal v2 of C.6.15) reaches tv3ws on the internal path /v100.0.
expect_list_v100 "[44642] C.6.15.5 com 100.0 pelo local autonomo (classe e clientid repassados)" "${TOK[@]}"
expect_list_v100 "[44642] C.6.15.5 com 100.0 pelo associado (classe repassada)" "${ASSOC_H[@]}"
expect_list_v100 "[44642] C.6.15.5 com 100.0 e X-TV30-Client-Class forjado (apagado pela borda)" "${TOK[@]}" -H 'X-TV30-Client-Class: associated' -H 'X-TV30-Client-Id: forjado'
# Update of a registration (C.6.15.2): only 100.0; without Accept-Version,
# 2.0, which does not serve it.
expect_err "[44642] POST /tv3/remote-device/x sem Accept-Version (so existe na 100.0)" 100 borda POST "$H_INT/tv3/remote-device/x" "${TOK[@]}" -H 'Content-Type: application/json' -d '{"deviceClass":"x","supportedTypes":[]}'
expect_err "[44642] POST /tv3/remote-device/x com 2.0" 100 borda POST "$H_INT/tv3/remote-device/x" "${TOK[@]}" -H 'Accept-Version: 2.0' -H 'Content-Type: application/json' -d '{"deviceClass":"x","supportedTypes":[]}'
expect_err "[44642] POST /tv3/remote-device/x com 100.0 (handle inexistente)" 305 tv3ws POST "$H_INT/tv3/remote-device/x" "${TOK[@]}" -H 'Accept-Version: 100.0' -H 'Content-Type: application/json' -d '{"deviceClass":"x","supportedTypes":[]}'
expect_api_version "[44642] atualizacao com 100.0" 100.0
# Deregistration (C.6.15.3) of a nonexistent handle: 305 in 100.0; the 2.0
# keeps its 101.
expect_err "[44642] DELETE /tv3/remote-device/x com 100.0 (handle inexistente)" 305 tv3ws DELETE "$H_INT/tv3/remote-device/x" "${TOK[@]}" -H 'Accept-Version: 100.0'
expect_err "[44642] DELETE /tv3/remote-device/x com 2.0 (handle inexistente)" 101 tv3ws DELETE "$H_INT/tv3/remote-device/x" "${TOK[@]}" -H 'Accept-Version: 2.0'
# Notifications (C.6.2.2, C.6.2.3): only 100.0, for the local client.
req GET "$H_INT/tv3/notifications/remote-device" "${TOK[@]}" -H 'Accept-Version: 100.0'
if [ "$ST" = 200 ] && [ "$(origin_of)" = tv3ws ] && body | grep -q '"url":"ws://' && [ "$(hdr API-Version)" = 100.0 ]; then
  pass "[44642] GET /tv3/notifications/remote-device com 100.0 -> 200 do tv3ws com a url do ouvinte"
else
  fail "[44642] GET /tv3/notifications/remote-device com 100.0 -> status=$ST origem=$(origin_of) api-version='$(hdr API-Version)' corpo=$(short)"
fi
expect_err "[44642] GET /tv3/notifications/remote-device sem Accept-Version (so existe na 100.0)" 100 borda GET "$H_INT/tv3/notifications/remote-device" "${TOK[@]}"
expect_err "[44642] GET /tv3/notifications/remote-device com 2.0" 100 borda GET "$H_INT/tv3/notifications/remote-device" "${TOK[@]}" -H 'Accept-Version: 2.0'
# The routes by handle of the former 100.0 no longer exist.
for V in 2.0 100.0; do
  for M in GET DELETE; do
    expect_err "[44642] $M /tv3/remote-device/device/x com $V (rota retirada)" 100 borda $M "$H_INT/tv3/remote-device/device/x" "${TOK[@]}" -H "Accept-Version: $V"
  done
done

echo; echo "-- rota nao declarada e preflight CORS --"
for H in "$H_INT" "$H_EXT"; do
  S="[${H##*:}]"
  expect_err "$S GET /tv3/naoexiste" 100 borda GET "$H/tv3/naoexiste"
  # The internal path (edge -> service) sent by the client is not a declared
  # route.
  expect_err "$S GET /v100.0/tv3/notifications/remote-device (caminho interno)" 100 borda GET "$H/v100.0/tv3/notifications/remote-device" "${TOK[@]}" -H 'Accept-Version: 100.0'
  expect_err "$S GET /v100.0/tv3/remote-device/devices/x (caminho interno)" 100 borda GET "$H/v100.0/tv3/remote-device/devices/x" "${TOK[@]}" -H 'Accept-Version: 100.0'
  expect_err "$S GET /tv3/xyz/abc" 100 borda GET "$H/tv3/xyz/abc"
  expect_err "$S GET /tv3/abc" 100 borda GET "$H/tv3/abc"
  expect_err "$S POST /tv3/users (rota nao declarada)" 100 borda POST "$H/tv3/users" -H 'Content-Type: application/json' -d '{}'
  expect_err "$S PUT /tv3/current-service (metodo nao declarado)" 100 borda PUT "$H/tv3/current-service"
  expect_preflight "$S OPTIONS preflight (bind-token)" "$H$CU" GET authorization,bind-token
  # A list out of lexicographic order.
  expect_preflight "$S OPTIONS preflight com a lista fora de ordem" "$H$CU" POST content-type,bind-token
  expect_preflight "$S OPTIONS preflight com a lista fora de ordem e espacos" "$H$CU" GET "bind-token, authorization, accept-version"
  # Undeclared path: the preflight passes too, and the browser reads the 100
  # of the request that follows.
  expect_preflight "$S OPTIONS preflight em caminho nao declarado" "$H/tv3/xyz/abc" GET authorization
  # OPTIONS without Access-Control-Request-Method is not a preflight: on a
  # declared API it answers with the headers of C.4.1.9.3; outside the table,
  # 100.
  expect_options "$S OPTIONS sem preflight em rota declarada" "$H$CU"
  expect_options "$S OPTIONS sem preflight em rota com {param}" "$H/tv3/$SVC_A/users/x"
  expect_err "$S OPTIONS sem preflight em /tv3/xyz/abc" 100 borda OPTIONS "$H/tv3/xyz/abc"
done

echo; echo "-- Redis congelado: o tv3ws falha rapido e de forma explicita --"
# docker pause redis: Redis accepts the connection and does not answer.
# /tv3/authorize WITHOUT Origin does not look up Redis at the edge and
# reaches tv3ws, whose commandTimeout (tv3ws/src/redis-client.ts) gives 404
# {error:200} from tv3ws ITSELF before 2 s, well before the 15 s timeout of
# the route at the edge (routes.json).
REDIS_TOUCHED=1
if docker pause redis >/dev/null 2>&1; then
  T0=$(date +%s%N)
  expect_err "[44642] redis congelado: GET /tv3/authorize sem Origin" 200 tv3ws GET "$H_INT/tv3/authorize?clientid=$REDIS_CID&display-name=tv30-test-auth"
  MS=$(( ($(date +%s%N) - T0) / 1000000 ))
  docker unpause redis >/dev/null 2>&1
  if [ "$MS" -lt 2000 ]; then pass "[44642] redis congelado: resposta do tv3ws em $MS ms (< 2 s)"
  else fail "[44642] redis congelado: resposta em $MS ms (esperado < 2 s)"; fi
  # errorHandler of tv3ws (src/util/error.ts): "[error] <method> <url>:
  # <reason>"
  LOGL=$(docker logs --since 2m tv3ws 2>&1 | grep -F "[error] GET /tv3/authorize?clientid=$REDIS_CID" | tail -1)
  if [ -n "$LOGL" ]; then
    pass "[44642] redis congelado: a falha aparece no log do tv3ws (${LOGL##*: })"
  else
    fail "[44642] redis congelado: nenhuma linha [error] do /tv3/authorize no log do tv3ws (falha silenciosa)"
  fi
  # Unfrozen, the same tv3ws uses Redis again (no restart).
  req GET "$H_INT/tv3/token?clientid=$REDIS_CID&refresh-token=x"
  for i in 1 2 3 4 5; do
    if [ "$CE" = 0 ] && [ "$ST" = 404 ] && body | grep -q '"error":102'; then break; fi
    sleep 1; req GET "$H_INT/tv3/token?clientid=$REDIS_CID&refresh-token=x"
  done
  check_err "[44642] redis descongelado: /tv3/token de clientid nunca autorizado volta a ser o 102 do tv3ws" 102 tv3ws
else
  fail "docker pause redis falhou (caso do redis congelado nao testado)"
fi

echo; echo "-- backend fora do ar ou lento: 404 {error:200} da borda, nao 500 vazio --"
# Last: stops and freezes tv3ws (the trap starts or unfreezes it if the
# script stops midway). A valid token, so that the request goes through the
# plugin and reaches the KrakenD passing on.
TV3WS_TOUCHED=1
docker stop -t 10 tv3ws >/dev/null 2>&1 || fail "docker stop tv3ws falhou"
for H in "$H_INT" "$H_EXT"; do
  S="[${H##*:}]"
  expect_err "$S tv3ws parado: GET /tv3/current-service com token valido" 200 borda GET "$H/tv3/current-service" "${TOK[@]}"
  expect_api_version "$S tv3ws parado"
done
docker start tv3ws >/dev/null 2>&1
if wait_tv3ws; then pass "tv3ws religado: a borda volta a chegar ao Express"
else fail "tv3ws nao voltou a responder pela borda em 90 s"; fi
if docker pause tv3ws >/dev/null 2>&1; then
  # KrakenD waits for the default timeout (2 s) on routes without their own
  # timeout.
  expect_err "[44642] tv3ws congelado (docker pause): timeout da borda" 200 borda GET "$H_INT/tv3/current-service" "${TOK[@]}"
  expect_api_version "[44642] tv3ws congelado"
  docker unpause tv3ws >/dev/null 2>&1
  expect_pass "[44642] tv3ws descongelado volta a responder" GET "$H_INT/tv3/current-service" "${TOK[@]}"
else
  fail "docker pause tv3ws falhou (caso do backend lento nao testado)"
fi

echo; echo "-- nao local: sim no pop-up sem /tv3/token nao grava nada --"
# The QR code of the attempt stays on screen until the 120 s lock; that is
# why this case comes last.
: >"$TMP/popp"
docker exec mqtt-broker mosquitto_sub -R -C 1 -W 20 -t "$POP_QR" >"$TMP/popp" 2>/dev/null &
bgp=$!
( docker exec mqtt-broker mosquitto_sub -C 1 -W 15 -t "$POP/message" >/dev/null 2>&1 \
    && docker exec mqtt-broker mosquitto_pub -q 1 -t "$POP/response" -m true ) &
bgy=$!
sleep 1.5
req GET "$H_INT/tv3/authorize?clientid=$NL_PEND&display-name=tv30-test-pendente&pm=qrcode"
wait "$bgy" 2>/dev/null; wait "$bgp" 2>/dev/null
if [ "$ST" = 200 ] && [ -n "$(json_str challenge)" ]; then
  pass "[nao local] sim no pop-up: /tv3/authorize devolve o desafio"
  if [ "$(rc EXISTS "client:$NL_PEND")" = 0 ] && [ "$(rc SISMEMBER clients:authorized "$NL_PEND")" = 0 ]; then
    pass "[nao local] sem /tv3/token: sem client:{id} e fora de clients:authorized"
  else
    fail "[nao local] sem /tv3/token: client:{id}=$(rc EXISTS "client:$NL_PEND") authorized=$(rc SISMEMBER clients:authorized "$NL_PEND") (esperado 0 e 0)"
  fi
  # A new request of the same clientid never gives 101; with the QR code of
  # the attempt on screen, 103.
  : >"$TMP/popp2"
  ( docker exec mqtt-broker mosquitto_sub -C 1 -W 6 -t "$POP/message" >"$TMP/popp2" 2>/dev/null \
      && docker exec mqtt-broker mosquitto_pub -q 1 -t "$POP/response" -m false ) &
  bgy=$!
  req GET "$H_INT/tv3/authorize?clientid=$NL_PEND&display-name=tv30-test-pendente&pm=qrcode"
  wait "$bgy" 2>/dev/null
  if [ "$ST" = 404 ] && body | grep -q '"error":103'; then
    pass "[nao local] novo /tv3/authorize com a tentativa pendente: 103 com o QR code na tela, e nao 101"
  elif [ -s "$TMP/popp2" ]; then
    pass "[nao local] novo /tv3/authorize com a tentativa pendente: pop-up de novo, e nao 101"
  else
    fail "[nao local] novo /tv3/authorize com a tentativa pendente: status=$ST corpo=$(short) (esperado 103 ou o pop-up, nunca 101)"
  fi
else
  fail "[nao local] sim no pop-up: /tv3/authorize sem desafio (status=$ST corpo=$(short))"
fi

echo; echo "-- BAMT de teste retirada: o servico sai do catalogo e a borda passa a dar 304 --"
# tv3ws, started again above, rewrites session:current-service-id from the
# retained message.
servico_corrente "$SVC_A"
if anuncia; then
  expect_err "[44642] GET /tv3/$SVC_A/users/x depois da retirada, com bind-token valido" 304 borda GET "$H_INT/tv3/$SVC_A/users/x" "${TOK[@]}" -H "bind-token: $BT_HS512"
  if [ "$ANUNCIO_PELA_LLS" = 1 ]; then
    if curl -s -m 5 "$AOP/appcat" | grep -qF "selectParam=\"$SVC_A\""; then fail "tela do catalogo ainda mostra $SVC_A depois da retirada"
    else pass "tela do catalogo sem $SVC_A depois da retirada"; fi
  fi
else
  fail "nao consegui retirar $SVC_A e $SVC_B do Application Catalog"
fi

echo; echo "-- esquema do Redis: auditoria depois de desfazer o que a suite semeou --"
restaura_redis
AUD=$(auditoria)
if [ -z "$AUD" ]; then
  pass "auditoria do esquema vazia (FCALL_RO tv30_audit 0) depois da suite"
else
  ANTES=""
  [ -n "$AUD_ANTES" ] && ANTES=" (ja havia achados ANTES da suite: volume antigo? ver o aviso do comeco e docs/modelo-redis.md)"
  fail "auditoria do esquema com achados depois da suite${ANTES}:"$'\n'"$(printf '%s\n' "$AUD" | sed 's/^/        /')"
fi

# ===================================================================== end ===
echo
echo "== resultado: $PASS PASS, $FAIL FAIL =="
# ${FAILED[@]+...}: in bash 3.2 (macOS), an empty array under set -u is
# "unbound".
for f in ${FAILED[@]+"${FAILED[@]}"}; do echo "  FAIL $f"; done
[ "$FAIL" -eq 0 ]
