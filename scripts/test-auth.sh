#!/usr/bin/env bash
# test-auth.sh — validacao de credenciais na BORDA (plugin tv30-auth do
# edgegateway, item 9 / decisao de 28/09). Roda contra a stack JA DE PE
# (localhost:44642 interna e 44643 externa) e imprime PASS/FAIL por caso;
# sai com codigo != 0 se algum caso falhar.
#
# Uso (Linux/WSL, com acesso ao docker):  bash scripts/test-auth.sh
#   (no WSL desta maquina: wsl.exe -u root bash /mnt/d/.../scripts/test-auth.sh)
#
# Reuniao de 05/10 com o Joel: toda a validacao de credencial fica na borda e
# o tv3ws fica "anonimo" (D-0510-1: sem 107 nem 106 por protocolo no tv3ws);
# a API C.6.8 (D-0510-2) e as APIs de informacao de API C.6.7.8/C.6.7.9
# (D-0510-3) sao RESPONDIDAS pela borda (infra/edgegateway/plugin/
# bindcontext.go e apiinfo.go), sem repasse ao tv3ws.
#
# O que ele faz:
#   1. modo WARN (o que estiver rodando): requisicao sem token passa e traz
#      X-TV30-Auth-Warn: 107; token adulterado tambem (o tv3ws nao confere
#      mais a credencial); API respondida pela borda (GET /tv3/api-info) sem
#      token responde 200 com o aviso; rota nao declarada da 100 nos dois
#      modos; Access-Control-Allow-Origin: * uma vez, com e sem Origin
#      (C.4.1.9.2); OPTIONS sem preflight em rota declarada da 200 com os
#      cabecalhos da C.4.1.9.3; caminho com %0A nao forja linha no log; tv3ws
#      congelado (docker pause) da 404 {error:200} da borda COM
#      X-TV30-Auth-Warn: 107 (P1 em warn); pop-up de autorizacao recusado
#      ("false") da 102.
#   2. recria SO o edgegateway com AUTH_ENFORCE=enforce (mesma variante,
#      mesmo JWT_SECRET/JWT_ISSUER do container em execucao) e cobre 107,
#      104, 106, 108, 100, preflight CORS, a API C.6.8 (POST/GET/DELETE
#      /tv3/bind-context) com HS256, HS512, RS256 e RS512, isolamento entre
#      servicos e confusao de algoritmo, e as APIs C.6.7.8/C.6.7.9
#      (GET /tv3/api-info[/{apiId}]) com a negociacao de versao da borda
#      (API-Version 2.1, a mais recente suportada, no erro 100; C.3.6.6).
#      GET /tv3/current-service (C.6.3.1, Tabela C.8) respondido pelo tv3ws:
#      404 {error:300} sem servico em uso e 200 com "serviceId" inteiro ou
#      omitido com servico em uso; erros 100/101 da negociacao de versao do
#      tv3ws com API-Version (2.1 no 100, 2.0 no 101).
#      Ainda em enforce: reuso de clientid (101, D-L2), pareamento REAL de
#      cliente nao local (pm=qrcode e pm=kex), Redis congelado (falha
#      explicita do tv3ws, 404 {error:200} em menos de 2 s, D-0510-6) e
#      backend fora do ar/lento (404 {error:200} da borda em vez de 500
#      vazio, P1).
#   3. no fim (trap EXIT, inclusive em erro/Ctrl+C) volta o edge ao modo que
#      ele tinha antes, religa/descongela o tv3ws e o redis se algum caso os
#      deixou parados e desfaz o que semeou no Redis.
#
# ORIGEM de cada erro: todo expect_err diz e confere QUEM respondeu.
#   borda = o plugin tv30-auth/KrakenD respondeu sem chegar ao tv3ws: o
#           writeError/writeC32 do plugin (infra/edgegateway/plugin/
#           handler.go) nao poe X-Powered-By;
#   tv3ws = a resposta veio do Express do tv3ws: o Express 5 poe
#           "X-Powered-By: Express" em toda resposta (app.handle em
#           express/lib/application.js; o tv3ws nao chama
#           app.disable('x-powered-by')) e o KrakenD repassa os cabecalhos
#           do backend (encoding no-op).
#
# Pre-requisito dos casos de REPASSE pela 44643: o backend da superficie
# externa e https://tv3ws:44653, que so existe com HTTPS_KEY/HTTPS_CERT no
# tv3ws/.env (sem eles o tv3ws sobe so em HTTP). O script detecta isso
# (GET 44643/health chegando ao tv3ws) e, se faltar, pula esses casos com
# uma linha explicativa em vez de dar FAIL; os erros da propria borda na
# 44643 continuam testados.
#
# O access token vem do fluxo REAL (/tv3/authorize + /tv3/token de cliente
# local autonomo): o script responde "true" ao pop-up sim/nao pelo broker
# (aop/display/layers/popup/yesno/response), no lugar do espectador. Chaves
# RSA e bind-tokens sao gerados na hora num container node:20-alpine (so
# biblioteca padrao do node).
#
# Cliente NAO local: o script faz o papel do aplicativo e do espectador. Le
# do broker o QR code (aop/display/layers/popup/qrcode) ou o PIN
# (aop/display/layers/popup/pin) que o tv3ws publica para a TV, resolve o
# desafio com a cripto de tv3ws/src/util/encryption.ts (AES-128-ECB/PKCS#7,
# SHA-256, ECDH P-256 — C.4.3.2, C.4.3.3, C.6.1.2.2, C.6.1.3) no mesmo
# container node e decifra a primeira resposta do /token. Segue o caminho que
# o SSDP anuncia (tv3ws/src/ssdp-config.ts): primeiro acesso por HTTP no
# Server-BaseURL (44642); depois, o Server-SecureBaseURL (44643), que na borda
# ainda e HTTP (L3), com o tv3ws atras dela em HTTPS. Sem HTTPS no tv3ws, os
# passos pela 44643 sao pulados com aviso; o pareamento pela 44642 roda.
#
# Estado tocado no Redis (tudo com sufixo unico desta execucao e desfeito no
# fim): session:current-service-id (salvo e restaurado), bind-context:<urn de
# teste>, origins:associated (uma origem de teste), clients:authorized e
# clients:blocked (os ids de teste; o tv3ws poe o cliente autorizado no
# primeiro e o recusado no segundo, D-0510-4) e client:<id de teste> (os
# clientes nao locais e o de reuso usam UUID, formato da C.6.1.4.3). O caso do
# Redis congelado (docker pause redis) dura poucos segundos e o trap
# descongela o container se o script cair no meio.
#
# Estado tocado no broker: o retido de aop/currentService (o servico em uso do
# tv3ws, core.app.sid; a plataforma o publica retido e o tv3ws o espelha em
# session:current-service-id e no hash session:current-service). Os casos da
# C.6.3.1 publicam no lugar da plataforma; o trap devolve o retido que havia
# (ou o apaga, se nao havia) e restaura o hash session:current-service.
set -u
cd "$(dirname "$0")/.." || exit 1

H_INT=${H_INT:-http://localhost:44642}
H_EXT=${H_EXT:-http://localhost:44643}
NODE_IMG=${NODE_IMG:-node:20-alpine}
POP=aop/display/layers/popup/yesno
POP_QR=aop/display/layers/popup/qrcode   # tv3ws/src/core.ts (_t)
POP_PIN=aop/display/layers/popup/pin
RUN="$$$(date +%s)"
# clientid no formato da C.6.1.4.3 (UUID, IETF RFC 9562; aqui versao 4)
uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid; return; fi
  local h; h=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  printf '%s-%s-4%s-%x%s-%s\n' "${h:0:8}" "${h:8:4}" "${h:13:3}" $(( (0x${h:16:1} & 3) | 8 )) "${h:17:3}" "${h:20:12}"
}
CLIENT="tv30-test-auth-$RUN"
REFUSED="tv30-test-recusa-$RUN"
REUSE=$(uuid)    # local autonomo do caso de reuso de clientid (D-L2)
NL_QR=$(uuid)    # nao local, pm=qrcode
NL_KEX=$(uuid)   # nao local, pm=kex
REDIS_CID=$(uuid) # /authorize com o redis congelado (D-0510-6): nunca autorizado
SVC_A="urn:tv30:test:auth-a-$RUN"
SVC_B="urn:tv30:test:auth-b-$RUN"
ASSOC="http://tv30-test-assoc-$RUN.invalid"     # origem "associada" simulada
OTHER_ORIGIN="http://tv30-test-cliente.invalid"  # navegador qualquer (CORS)
SCID_CONST="c08b2c72-fd14-4095-adaf-2e5810850c57" # tv3ws/src/core.ts (L2)
TMP=$(mktemp -d)
PASS=0; FAIL=0; FAILED=()

pass() { PASS=$((PASS+1)); echo "PASS  $*"; }
fail() { FAIL=$((FAIL+1)); FAILED+=("$*"); echo "FAIL  $*"; }
info() { echo "      $*"; }
die()  { echo "ERRO: $*" >&2; exit 2; }

rc() { docker exec redis redis-cli "$@"; }
env_of() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" | sed -n "s/^$2=//p" | head -1; }

# ---------------------------------------------------------------- pre-req --
for c in edgegateway tv3ws redis mqtt-broker; do
  [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] \
    || die "container $c nao esta rodando (suba a stack: docker compose up -d)"
done
command -v curl >/dev/null || die "curl ausente"

ORIG_MODE=$(env_of edgegateway AUTH_ENFORCE); ORIG_MODE=${ORIG_MODE:-warn}
ORIG_VARIANT=$(env_of edgegateway EDGE_VARIANT); ORIG_VARIANT=${ORIG_VARIANT:-linux}
EDGE_SECRET=$(env_of edgegateway JWT_SECRET)
EDGE_ISSUER=$(env_of edgegateway JWT_ISSUER); EDGE_ISSUER=${EDGE_ISSUER:-GenericIssuer}
[ -n "$EDGE_SECRET" ] || die "JWT_SECRET ausente no edgegateway"
ORIG_SVC=$(rc GET session:current-service-id)
# retido de aop/currentService e hash session:current-service antes do teste
# (restaurados no trap se os casos da C.6.3.1 os tocarem)
CS_TOPIC=aop/currentService
ORIG_CS=$(docker exec mqtt-broker mosquitto_sub -t "$CS_TOPIC" -C 1 -W 2 --retained-only 2>/dev/null)
ORIG_CS_HASH=$(rc HGETALL session:current-service | base64 -w0)
echo "== borda: modo=$ORIG_MODE variante=$ORIG_VARIANT; servico corrente='${ORIG_SVC}'; $CS_TOPIC retido='${ORIG_CS}' =="

# recria SO o edgegateway no modo pedido, preservando variante e segredo
edge_mode() {
  local mode=$1 i
  AUTH_ENFORCE=$mode EDGE_VARIANT=$ORIG_VARIANT JWT_SECRET=$EDGE_SECRET JWT_ISSUER=$EDGE_ISSUER \
    docker compose up -d --no-deps edgegateway >"$TMP/compose.log" 2>&1 \
    || { cat "$TMP/compose.log"; return 1; }
  for i in $(seq 1 60); do
    if [ "$(docker logs edgegateway 2>&1 | grep -c "registrado surface=.* modo=$mode")" -ge 2 ] \
       && curl -s -o /dev/null -m 3 "$H_INT/health" && curl -s -o /dev/null -m 3 "$H_EXT/health"; then
      return 0
    fi
    sleep 1
  done
  docker logs --tail 30 edgegateway
  return 1
}

TV3WS_TOUCHED=0   # 1 depois que o caso P1 parar/congelar o tv3ws
REDIS_TOUCHED=0   # 1 depois que o caso D-0510-6 congelar o redis
CS_TOUCHED=0      # 1 depois que os casos da C.6.3.1 publicarem aop/currentService

# cs_publish <sid>: publica aop/currentService retido no lugar da plataforma
# (vazio = apaga o retido; o broker entrega o "" aos assinantes, como no
# unsetCurrentService do aop) e espera o tv3ws espelhar o valor em
# session:current-service-id (tv3ws/src/api/user/service.ts), sinal de que o
# servico em uso dele (core.app.sid) ja mudou
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

cleanup() {
  set +e
  echo; echo "== limpeza =="
  # o redis primeiro: o resto da limpeza fala com ele
  if [ "$REDIS_TOUCHED" = 1 ] && [ "$(docker inspect -f '{{.State.Paused}}' redis 2>/dev/null)" = true ]; then
    docker unpause redis >/dev/null && echo "redis descongelado"
  fi
  if [ "$TV3WS_TOUCHED" = 1 ]; then
    [ "$(docker inspect -f '{{.State.Paused}}' tv3ws 2>/dev/null)" = true ] \
      && docker unpause tv3ws >/dev/null && echo "tv3ws descongelado"
    [ "$(docker inspect -f '{{.State.Running}}' tv3ws 2>/dev/null)" = true ] \
      || { docker start tv3ws >/dev/null && echo "tv3ws religado"; }
  fi
  # o retido de aop/currentService antes do Redis: o tv3ws reescreve
  # session:current-service-id e o hash session:current-service ao recebe-lo
  if [ "$CS_TOUCHED" = 1 ]; then
    if cs_publish "$ORIG_CS"; then echo "$CS_TOPIC retido restaurado ('$ORIG_CS')"
    else echo "ATENCAO: $CS_TOPIC publicado ('$ORIG_CS'), mas o tv3ws nao o espelhou no Redis em 10 s"; fi
    local k v hs=()
    while IFS= read -r k && IFS= read -r v; do hs+=("$k" "$v"); done < <(printf '%s' "$ORIG_CS_HASH" | base64 -d)
    rc DEL session:current-service >/dev/null
    [ "${#hs[@]}" -gt 0 ] && rc HSET session:current-service "${hs[@]}" >/dev/null
  fi
  if [ -n "$ORIG_SVC" ]; then rc SET session:current-service-id "$ORIG_SVC" >/dev/null
  else rc DEL session:current-service-id >/dev/null; fi
  rc DEL "bind-context:$SVC_A" "bind-context:$SVC_B" "client:$CLIENT" "client:$REFUSED" \
    "client:$REUSE" "client:$NL_QR" "client:$NL_KEX" "client:$REDIS_CID" >/dev/null
  rc HDEL origins:associated "$ASSOC" >/dev/null
  rc SREM clients:authorized "$CLIENT" "$REFUSED" "$REUSE" "$NL_QR" "$NL_KEX" "$REDIS_CID" >/dev/null
  rc SREM clients:blocked "$CLIENT" "$REFUSED" "$REUSE" "$NL_QR" "$NL_KEX" "$REDIS_CID" >/dev/null
  echo "Redis restaurado (servico corrente='$(rc GET session:current-service-id)')"
  if [ "$(env_of edgegateway AUTH_ENFORCE)" != "$ORIG_MODE" ]; then
    if edge_mode "$ORIG_MODE"; then echo "edgegateway de volta ao modo $ORIG_MODE"
    else echo "ATENCAO: nao consegui voltar o edgegateway para $ORIG_MODE"; fi
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ------------------------------------------------------------- requisicao --
# req METODO URL [args do curl] -> ST (status), CE (saida do curl), $TMP/h2, $TMP/b
req() {
  local m=$1 u=$2; shift 2
  : >"$TMP/h"; : >"$TMP/b"
  ST=$(curl -s -m 20 -X "$m" -D "$TMP/h" -o "$TMP/b" -w '%{http_code}' "$@" "$u"); CE=$?
  tr -d '\r' <"$TMP/h" >"$TMP/h2"
}
hdr()  { grep -i "^$1:" "$TMP/h2" | head -1 | cut -d: -f2- | sed 's/^ *//'; }
body() { cat "$TMP/b"; }
short() { body | head -c 200 | tr '\n' ' '; }

# quem respondeu a ultima requisicao (ver ORIGEM no cabecalho)
origin_of() { if hdr X-Powered-By | grep -q '^Express'; then echo tv3ws; else echo borda; fi; }

# confere a ULTIMA resposta: erro no formato C.3.2 (D5) — 404 +
# {error,description} JSON + ACAO * — vindo da origem esperada (borda|tv3ws)
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

# expect_err NOME CODIGO ORIGEM METODO URL [args do curl]
expect_err() {
  local name=$1 code=$2 orig=$3; shift 3
  case "$orig" in borda|tv3ws) ;; *) die "expect_err '$name': origem '$orig' (use borda ou tv3ws)" ;; esac
  req "$@"
  check_err "$name" "$code" "$orig"
}

# expect_api_version NOME [VERSAO]: a ultima resposta traz API-Version
# (C.3.6.6) = VERSAO. Padrao 2.0: a de quem nao manda Accept-Version e a do
# erro 101 (Accept-Version malformado); no erro 100 (versao fora do conjunto)
# vem a mais recente suportada, 2.1
expect_api_version() {
  local want=${2:-2.0} v; v=$(hdr API-Version)
  if [ "$v" = "$want" ]; then pass "$1 -> API-Version: $v"; else fail "$1 -> esperado API-Version: $want, veio '$v'"; fi
}

# chegou ao tv3ws (X-Powered-By: Express) sem bloqueio nem aviso da borda
expect_pass() {
  local name=$1 why=""; shift
  req "$@"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  hdr X-Powered-By | grep -q Express || why="$why nao-chegou-ao-tv3ws(status=$ST corpo=$(short))"
  [ -z "$(hdr X-Tv30-Auth-Warn)" ] || why="$why aviso=$(hdr X-Tv30-Auth-Warn)"
  if [ -z "$why" ]; then pass "$name -> repassado ao tv3ws (status $ST)"; else fail "$name -> esperado repasse:$why"; fi
}

# C.4.1.9.2: exatamente um Access-Control-Allow-Origin: * (duplicado, o
# Chrome recusa), com ou sem Origin na requisicao
expect_acao() {
  local name=$1 why=""; shift
  req "$@"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  local n; n=$(grep -ci '^Access-Control-Allow-Origin:' "$TMP/h2")
  [ "$n" = 1 ] || why="$why acao-linhas=$n"
  [ "$(hdr Access-Control-Allow-Origin)" = "*" ] || why="$why acao='$(hdr Access-Control-Allow-Origin)'"
  if [ -z "$why" ]; then pass "$name -> um Access-Control-Allow-Origin: * (status $ST)"; else fail "$name -> esperado um ACAO *:$why"; fi
}

# C.4.1.9.3: OPTIONS sem preflight numa API declarada -> 200 com ACAO, ACAM e ACAH
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

# modo warn: repassado ao tv3ws E marcado com X-TV30-Auth-Warn: <codigo>
expect_warn() {
  local name=$1 code=$2 why=""; shift 2
  req "$@"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  hdr X-Powered-By | grep -q Express || why="$why nao-chegou-ao-tv3ws(status=$ST corpo=$(short))"
  [ "$(hdr X-Tv30-Auth-Warn)" = "$code" ] || why="$why aviso='$(hdr X-Tv30-Auth-Warn)'"
  if [ -z "$why" ]; then pass "$name -> repassado com X-TV30-Auth-Warn: $code"; else fail "$name -> esperado repasse com aviso $code:$why"; fi
}

# API RESPONDIDA PELA BORDA (C.6.8, C.6.7.8/C.6.7.9; edge.go do plugin):
# expect_edge NOME REGEX_DO_CORPO [VERSAO] METODO URL [args do curl] — 200,
# corpo JSON casando a regex (estendida), sem X-Powered-By (nao chegou ao
# tv3ws), um ACAO *, API-Version = VERSAO (padrao 2.0) e sem aviso de warn
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

# modo warn numa API respondida pela borda: 200 da propria borda (nao ha
# repasse ao tv3ws, entao o expect_warn nao serve) com X-TV30-Auth-Warn
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

# preflight CORS (modulo CORS do KrakenD): expect_preflight NOME URL METODO
# CABECALHOS. Os cabecalhos pedidos vao em ordem lexicografica, como o
# navegador manda: o modulo CORS do KrakenD 2.7.2 recusa a lista fora de
# ordem em qualquer rota (achado da rodada de 05/10)
expect_preflight() {
  local name=$1 url=$2 m=$3 hs=$4 why="" h
  req OPTIONS "$url" -H "Origin: $OTHER_ORIGIN" -H "Access-Control-Request-Method: $m" \
      -H "Access-Control-Request-Headers: $hs"
  [ "$CE" = 0 ] || why="$why curl=$CE"
  [ "${ST:0:1}" = 2 ] || why="$why status=$ST"
  [ "$(hdr Access-Control-Allow-Origin)" = "*" ] || why="$why acao='$(hdr Access-Control-Allow-Origin)'"
  hdr Access-Control-Allow-Methods | grep -qi "$m" || why="$why allow-methods='$(hdr Access-Control-Allow-Methods)'"
  for h in ${hs//,/ }; do
    hdr Access-Control-Allow-Headers | grep -qi "$h" || why="$why allow-headers='$(hdr Access-Control-Allow-Headers)'"
  done
  if [ -z "$why" ]; then pass "$name -> $ST, Allow-Headers: $(hdr Access-Control-Allow-Headers)"; else fail "$name -> esperado preflight aceito:$why"; fi
}

# -------------------------------------------------------- material de teste --
# node so com biblioteca padrao: segredos HS, pares RSA, bind-tokens e um
# access token expirado. Saida: linhas NOME=valor (sem quebra de linha).
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
// "estilo da norma": chave PRIVADA PKCS#1 em base64 de DER, sem cabecalho
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
// tamanho do exemplo da norma (512 bits, MIIBOgIBAAJB...): so serve RS256
try {
  const n = crypto.generateKeyPairSync('rsa', { modulusLength: 512 });
  const npriv = n.privateKey.export({ type: 'pkcs1', format: 'der' }).toString('base64');
  out('NORMA_PRIV', npriv);
  out('BODY_NORMA', JSON.stringify({ alg: 'RS256', key: npriv }));
  out('BT_NORMA', jwt(H('RS256'), ok, rs('RS256', n.privateKey)));
} catch (e) { out('NORMA_ERRO', String(e.message).replace(/\s+/g, ' ')); }
// casos invalidos
out('BT_UNREG', jwt(H('HS256'), ok, hs('HS256', unreg)));
out('BT_CONFUSION', jwt(H('HS256'), ok, hs('HS256', r256pem)));  // HMAC com a chave publica RSA registrada
out('BT_NBF', jwt(H('HS256'), { iat: now, nbf: now + 3600, exp: now + 7200 }, hs('HS256', hs256)));
out('BT_EXP', jwt(H('HS256'), { iat: now - 7200, nbf: now - 7200, exp: now - 3600 }, hs('HS256', hs256)));
out('BT_IAT', jwt(H('HS256'), { iat: now + 3600, nbf: now - 10, exp: now + 7200 }, hs('HS256', hs256)));
out('BT_NONE', jwt({ alg: 'none', typ: 'JWT' }, ok, () => ''));
out('AT_EXPIRED', jwt(H('HS256'),
  { iat: now - 7200, nbf: now - 7200, exp: now - 3600, iss: process.env.ISS, sub: process.env.SUB, class: 'local-autonomous' },
  hs('HS256', process.env.SECRET)));
// dentro do prazo, mas assinado com outro segredo (adulterado, para o warn)
out('AT_BADSIG', jwt(H('HS256'),
  { iat: now, nbf: now, exp: now + 3600, iss: process.env.ISS, sub: process.env.SUB, class: 'local-autonomous' },
  hs('HS256', 'tv30-test-outro-segredo-' + crypto.randomBytes(8).toString('hex'))));
// token valido com class local-associated (o bloqueio C.4.2.2 vale tambem para ele)
out('AT_ASSOC', jwt(H('HS256'),
  { iat: now, nbf: now, exp: now + 3600, iss: process.env.ISS, sub: process.env.SUB, class: 'local-associated' },
  hs('HS256', process.env.SECRET)));
JS
docker run --rm -i -e ISS="$EDGE_ISSUER" -e SUB="$CLIENT" -e SECRET="$EDGE_SECRET" "$NODE_IMG" node - <"$TMP/gen.js" >"$TMP/mat" 2>"$TMP/mat.err" \
  || { cat "$TMP/mat.err"; die "falha gerando chaves/tokens no container $NODE_IMG"; }
while IFS='=' read -r k v; do [ -n "$k" ] && printf -v "$k" '%s' "$v"; done <"$TMP/mat"
[ -n "${BT_RS512:-}" ] || die "material de teste incompleto"

# fluxo real de autorizacao de cliente local autonomo; $2 = resposta do
# "espectador" ao pop-up (true|false). Deixa o corpo em $TMP/b.
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

# ---------------------------------------------------- cliente NAO local --
# Cripto do aplicativo nao local, igual a de tv3ws/src/api/client-
# identification/service.ts e util/encryption.ts. MODO:
#   kexkey  par ECDH P-256 do cliente: CPRIV (hex) e CPUB (ponto SEC 1 sem
#           compressao em base64url, C.4.3.4)
#   solve   PM=qrcode: QR = chave do QR code (base64url) -> segredo =
#           SHA-256(chave)[0:16] (C.4.3.2, C.6.1.2.2 passos 1-2);
#           PM=kex: CPRIV + SKEY (chave parcial do servidor) -> h =
#           SHA-256(ECDH), PIN = h mod 10000 com 4 digitos (zeros a
#           esquerda, "a four-digit number"), segredo = h[0:16] (C.4.3.3).
#           Depois o challenge-response da Tabela C.4: decodifica o
#           challenge, decifra, SHA-256, cifra, base64url. Saida SECRET, CR
#           (e PIN no kex).
#   token   CT + BODY (corpo em base64) + SECRET: decifra se o corpo veio
#           application/octet-stream (C.6.1.3.3) e extrai os campos e os
#           claims class/sub do accessToken. Saida ENC, AT, RT, TT, EXP,
#           CERT, CLASS, SUB.
# Erro de qualquer passo (ex.: padding invalido = chave errada) sai em ERR.
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
    out('CLASS', p.class || ''); out('SUB', p.sub || '');
  } else {
    out('ERR', `MODO desconhecido: ${E.MODO}`);
  }
} catch (e) { out('ERR', String((e && e.message) || e).replace(/\s+/g, ' ')); }
JS

# nl_node VAR=valor... -> roda pair.js e carrega cada linha K=v em NL_K
nl_node() {
  local envs=() kv k v
  for kv in "$@"; do envs+=(-e "$kv"); done
  NL_ERR=""
  docker run --rm -i "${envs[@]}" "$NODE_IMG" node - <"$TMP/pair.js" >"$TMP/pair.out" 2>"$TMP/pair.err" \
    || { NL_ERR="node: $(head -c 300 "$TMP/pair.err" | tr '\n' ' ')"; return 1; }
  while IFS='=' read -r k v; do [ -n "$k" ] && printf -v "NL_$k" '%s' "$v"; done <"$TMP/pair.out"
  [ -z "$NL_ERR" ]
}

# pareamento REAL de cliente nao local pela 44642 (primeiro acesso por HTTP):
# $1 = qrcode|kex, $2 = clientid. Responde "true" ao pop-up sim/nao, le do
# broker o QR code/PIN que o tv3ws mandou a TV mostrar, resolve o desafio e
# decifra a primeira resposta do /token. Deixa NL_AT, NL_RT (e NL_CLASS...).
# Retorna != 0 se o pareamento nao se completou (o FAIL ja foi registrado).
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
    # C.4.3.3: "a four-digit number" — "0042", nao "42"
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
  nl_node MODO=token CT="$ct" BODY="$(base64 -w0 "$TMP/b")" SECRET="$NL_SECRET" \
    || { fail "$S [44642] primeira resposta do /token ilegivel (Content-Type '$ct'): $NL_ERR"; return 1; }
  if [ "$NL_ENC" = 1 ]; then
    pass "$S [44642] primeiro /token -> 200 cifrado (application/octet-stream), decifrado com a chave do pareamento"
  else
    fail "$S [44642] primeiro /token por HTTP -> esperado corpo cifrado application/octet-stream (C.6.1.3.3), veio '$ct'"
  fi
  if [ -n "$NL_AT" ] && [ "$NL_CLASS" = non-local ] && [ "$NL_SUB" = "$cid" ] && [ -n "$NL_RT" ]; then
    pass "$S accessToken com class=non-local e sub=clientid, mais refreshToken (tokenType=$NL_TT, expiresIn=$NL_EXP)"
  else
    fail "$S credencial do primeiro /token: class='$NL_CLASS' sub='$NL_SUB' accessToken=${NL_AT:+presente} refreshToken=${NL_RT:+presente}"
    return 1
  fi
  if [ "$EXT_OK" = 1 ]; then
    if [ "$NL_CERT" = 1 ]; then pass "$S serverCert presente (tv3ws com HTTPS)"
    else fail "$S serverCert ausente com o tv3ws em HTTPS (Tabela C.4: incluido no primeiro acesso do nao local)"; fi
  elif [ "$NL_CERT" = 1 ]; then
    info "$S serverCert presente, embora a 44643 nao chegue ao tv3ws"
  else
    info "$S serverCert ausente: o tv3ws esta sem HTTPS_CERT (esperado neste arranjo)"
  fi
  return 0
}

# reuso de clientid (D-L2; C.6.1.4.4 e Tabela C.3: 101 "if clientid has been
# used before"): 404 {error:101} do tv3ws e NENHUM pop-up publicado
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

# espera a borda voltar a chegar ao tv3ws (as duas superficies se EXT_OK)
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

AUTH_H=(-H "Origin: $OTHER_ORIGIN")   # navegador qualquer: CORS devolve ACAO

# backend da superficie externa (https://tv3ws:44653) de pe? (ver cabecalho)
req GET "$H_EXT/health"
if hdr X-Powered-By | grep -q Express; then EXT_OK=1
else
  EXT_OK=0
  info "AVISO: a 44643 nao chega ao tv3ws (status=$ST): sem HTTPS_KEY/HTTPS_CERT no tv3ws/.env o"
  info "       backend https://tv3ws:44653 nao existe. Casos de repasse pela 44643 serao PULADOS."
fi
# ext_skip <nome>: true (e imprime) se o caso de repasse pela 44643 deve ser pulado
ext_skip() { if [ "$1" = "$H_EXT" ] && [ "$EXT_OK" != 1 ]; then info "pulado (sem HTTPS no tv3ws): $2"; return 0; fi; return 1; }

# ============================================================== WARN ======
echo; echo "== 1. modo $ORIG_MODE (stack como esta) =="
if [ "$ORIG_MODE" = warn ]; then
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
    # D-0510-1: o tv3ws nao confere mais a credencial (antes dava 107 a
    # Authorization invalido nos dois modos); em warn so a borda avisa
    ext_skip "$H" "[warn ${H##*:}] token adulterado chega ao tv3ws" \
      || expect_warn "[warn ${H##*:}] token adulterado chega ao tv3ws (sem 107 do tv3ws)" 107 GET "$H/tv3/current-service" -H "Authorization: Bearer $AT_BADSIG"
    # API respondida pela borda (D-0510-3): em warn responde, com o aviso
    expect_edge_warn "[warn ${H##*:}] GET /tv3/api-info sem token" 107 '^\{"receiverApis":\[\{"id":"tv3ws-' GET "$H/tv3/api-info"
  done
  # caminho com quebra de linha (%0A) nao forja linha no log da borda
  MARK="tv30forjado$RUN"
  req GET "$H_INT/tv3/abc%0A$MARK"
  if [ "$(docker logs --since 2m edgegateway 2>&1 | grep -c "^$MARK")" = 0 ]; then
    pass "[warn 44642] caminho com %0A nao gera linha forjada no log"
  else fail "[warn 44642] caminho com %0A gerou linha comecando por $MARK no log"; fi
  # backend congelado em warn (P1): a troca do 5xx pelo 404 {error:200} da
  # borda mantem o aviso X-TV30-Auth-Warn (o que o enforce faria; antes so o
  # teste Go cobria). docker pause, e nao stop, para nao republicar as portas
  # do tv3ws (45000-45199). O trap descongela se o script cair no meio.
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
    fail "[warn] docker pause tv3ws falhou (P1 em warn nao testado)"
  fi
else
  info "edge nao estava em warn ($ORIG_MODE): casos de warn pulados"
fi
# correcao do tv3ws: "false" do pop-up nao autoriza mais (Boolean("false"))
authorize "$REFUSED" false
check_err "pop-up recusado (\"false\"): cliente nao autorizado" 102 tv3ws
# D-0510-4: o recusado vai para clients:blocked e nunca para clients:authorized
if [ "$(rc SISMEMBER clients:blocked "$REFUSED")" = 1 ] && [ "$(rc SISMEMBER clients:authorized "$REFUSED")" = 0 ]; then
  pass "pop-up recusado: clientid em clients:blocked e fora de clients:authorized"
else
  fail "pop-up recusado: blocked=$(rc SISMEMBER clients:blocked "$REFUSED") authorized=$(rc SISMEMBER clients:authorized "$REFUSED") (esperado 1 e 0)"
fi

# ============================================================ ENFORCE =====
echo; echo "== 2. recriando o edgegateway com AUTH_ENFORCE=enforce =="
edge_mode enforce || die "edgegateway nao subiu em enforce"
echo "ok: as duas superficies registraram o plugin em enforce"

rc SET session:current-service-id "$SVC_A" >/dev/null
rc HSET origins:associated "$ASSOC" "$SVC_A" >/dev/null
ASSOC_H=(-H "Origin: $ASSOC")

echo; echo "-- access token (fluxo real /tv3/authorize + /tv3/token) --"
authorize "$CLIENT" true
RT=$(json_str refreshToken)
[ -n "$RT" ] && pass "GET /tv3/authorize (local autonomo, pop-up aceito) -> refreshToken" \
             || fail "GET /tv3/authorize -> sem refreshToken: status=$ST corpo=$(short)"
# D-0510-4: o autorizado vai para clients:authorized (base da futura tela)
if [ "$(rc SISMEMBER clients:authorized "$CLIENT")" = 1 ] && [ "$(rc SISMEMBER clients:blocked "$CLIENT")" = 0 ]; then
  pass "autorizado: clientid em clients:authorized e fora de clients:blocked"
else
  fail "autorizado: authorized=$(rc SISMEMBER clients:authorized "$CLIENT") blocked=$(rc SISMEMBER clients:blocked "$CLIENT") (esperado 1 e 0)"
fi
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

echo; echo "-- GET /tv3/current-service (C.6.3.1, Tabela C.8) e API-Version nos 100/101 do tv3ws (C.3.6.6) --"
# servico em uso do tv3ws = ultimo aop/currentService (core.app.sid), nao a
# chave session:current-service-id que a borda le (o tv3ws so a escreve, como
# espelho do mesmo topico). O teste publica o topico no lugar da plataforma;
# com o servico de teste $SVC_A o espelho fica igual ao que a borda ja ve.
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
  body | grep -q "\"serviceContextId\":\"$SCID_CONST\"" || why="$why sem-serviceContextId"
  # "serviceId" inteiro (Tabela C.8) ou omitido quando o testbed nao o
  # conhece (sem SLT; o tv3ws so o teria por aop/services, que ninguem publica)
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
# a borda nao negocia versao nas rotas que repassa: estes saem do tv3ws
expect_err "[44642] GET /tv3/current-service com Accept-Version 3.0 (fora do conjunto)" 100 tv3ws GET "$H_INT/tv3/current-service" "${TOK[@]}" -H 'Accept-Version: 3.0'
expect_api_version "[44642] 100 do tv3ws: a versao mais recente suportada" 2.1
expect_err "[44642] GET /tv3/current-service com Accept-Version x (malformado)" 101 tv3ws GET "$H_INT/tv3/current-service" "${TOK[@]}" -H 'Accept-Version: x'
expect_api_version "[44642] 101 do tv3ws" 2.0
expect_pass "[44642] GET /tv3/current-service com Accept-Version 2.1" GET "$H_INT/tv3/current-service" "${TOK[@]}" -H 'Accept-Version: 2.1'
expect_api_version "[44642] 200 do tv3ws com Accept-Version 2.1" 2.1

rc SADD clients:blocked "$CLIENT" >/dev/null
expect_err "[44642] cliente em clients:blocked" 107 borda GET "$H_INT/tv3/current-service" "${TOK[@]}"
rc SREM clients:blocked "$CLIENT" >/dev/null
expect_pass "[44642] cliente desbloqueado volta a passar" GET "$H_INT/tv3/current-service" "${TOK[@]}"
# token valido com class local-associated: dispensa bind-token, mas nao o bloqueio
TOK_ASSOC=(-H "Authorization: Bearer $AT_ASSOC")
expect_pass "[44642] token de classe associado dispensa bind-token" GET "$H_INT/tv3/current-service/users/current-user" "${TOK_ASSOC[@]}"
rc SADD clients:blocked "$CLIENT" >/dev/null
expect_err "[44642] token de classe associado de cliente bloqueado" 107 borda GET "$H_INT/tv3/current-service/users/current-user" "${TOK_ASSOC[@]}"
rc SREM clients:blocked "$CLIENT" >/dev/null

echo; echo "-- reuso de clientid (D-L2): 101 sem nova consulta ao espectador --"
# cliente proprio do caso: se o 101 falhar e o pop-up sair, o timeout dele
# bloqueia ESTE clientid, nao o $CLIENT dos demais casos
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
# POST {scid}/users cai no mesmo handler da C.6.14.1 (bind-token shall)
expect_err "[44642] POST /tv3/current-service/users sem bind-token" 104 borda POST "$H_INT/tv3/current-service/users" "${TOK[@]}" -H 'Content-Type: application/json' -d '{}'
expect_err "[44642] POST /tv3/xyz/users sem bind-token (antes passava so com token)" 104 borda POST "$H_INT/tv3/xyz/users" "${TOK[@]}" -H 'Content-Type: application/json' -d '{}'

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
# validacao do corpo e logica da propria API C.6.8.2, respondida pela borda
# desde a reuniao de 05/10 (D-0510-2; infra/edgegateway/plugin/bindcontext.go)
expect_err "POST bind-context sem key" 105 borda POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d '{"alg":"HS256"}'
expect_err "POST bind-context alg fora dos 4" 101 borda POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d '{"alg":"ES256","key":"x"}'
expect_err "POST bind-context RS256 com chave que nao e RSA" 101 borda POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d '{"alg":"RS256","key":"nao-e-chave"}'
# so JSON (o tv3ws aceitava form-urlencoded por acidente, via express.urlencoded)
expect_err "POST bind-context com Content-Type text/plain" 101 borda POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: text/plain' -d "$BODY_HS512"
expect_edge "POST bind-context com Accept-Version 2.1 (repetido)" '^\{"serviceContextId":"'"$SCID_CONST"'"\}$' 2.1 \
  POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Accept-Version: 2.1' -H 'Content-Type: application/json' -d "$BODY_HS512"
expect_edge "[44643] POST bind-context repetido pela superficie externa" '^\{"serviceContextId":"'"$SCID_CONST"'"\}$' \
  POST "$H_EXT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d "$BODY_HS512"
# sem servico corrente nao ha a que ligar a chave: 300 ("No DTV service currently in use")
rc DEL session:current-service-id >/dev/null
expect_err "POST bind-context sem servico corrente" 300 borda POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d "$BODY_HS256"
rc SET session:current-service-id "$SVC_A" >/dev/null

echo; echo "-- bind-token assinado com cada chave registrada --"
CU="/tv3/current-service/users/current-user"
for A in HS256 HS512 RS256 RS512 NORMA; do
  v="BT_$A"; [ -n "${!v:-}" ] || continue
  expect_pass "[44642] $CU com bind-token $A" GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: ${!v}"
done
ext_skip "$H_EXT" "[44643] $CU com bind-token RS512" \
  || expect_pass "[44643] $CU com bind-token RS512" GET "$H_EXT$CU" "${TOK[@]}" -H "bind-token: $BT_RS512"
expect_pass "[44642] GET /tv3/$SCID_CONST/users/x (scid constante = servico corrente, L2)" GET "$H_INT/tv3/$SCID_CONST/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_pass "[44642] POST /tv3/$SCID_CONST/users com bind-token (L2)" POST "$H_INT/tv3/$SCID_CONST/users" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'

echo; echo "-- bind-token invalido --"
expect_err "bind-token de chave nao registrada" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_UNREG"
expect_err "confusao de algoritmo (HS256 assinado com a chave publica RS256 registrada)" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_CONFUSION"
expect_err "bind-token com nbf no futuro" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_NBF"
expect_err "bind-token expirado" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_EXP"
expect_err "bind-token com iat no futuro" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_IAT"
expect_err "bind-token alg none" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_NONE"
expect_err "bind-token que nao e JWT" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: abc"
expect_err "scid de outro servico no caminho (provisorio L2)" 108 borda GET "$H_INT/tv3/outro-scid/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "POST /tv3/xyz/users com bind-token valido (scid de outro servico, L2)" 108 borda POST "$H_INT/tv3/xyz/users" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'
expect_err "POST /tv3/Current-Service/users (caixa trocada; o Express nao diferencia)" 108 borda POST "$H_INT/tv3/Current-Service/users" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'

echo; echo "-- isolamento entre emissoras (D4) --"
rc SET session:current-service-id "$SVC_B" >/dev/null
expect_err "servico corrente trocado: bind-token da emissora A" 108 borda GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS256"
rc SET session:current-service-id "$SVC_A" >/dev/null
expect_pass "servico A de volta: o mesmo bind-token passa" GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS256"

echo; echo "-- associado (D8): sem access token e sem bind-token --"
expect_pass "associado em $CU sem credencial" GET "$H_INT$CU" "${ASSOC_H[@]}"
expect_err  "associado em /tv3/authorize (L4, so em enforce)" 106 borda GET "$H_INT/tv3/authorize?clientid=x&display-name=y" "${ASSOC_H[@]}"
expect_err  "associado em /tv3/authorize com Authorization qualquer (nao escapa do 106)" 106 borda GET "$H_INT/tv3/authorize?clientid=x&display-name=y" "${ASSOC_H[@]}" -H 'Authorization: x'
expect_err  "associado em /tv3/token com Authorization qualquer (nao escapa do 106)" 106 borda GET "$H_INT/tv3/token?clientid=x&refresh-token=y" "${ASSOC_H[@]}" -H 'Authorization: x'

echo; echo "-- GET /tv3/bind-context --"
req GET "$H_INT/tv3/bind-context" "${TOK[@]}" -H "bind-token: $BT_HS256"
if [ "$ST" = 200 ] && body | grep -q "\"boundServices\":\[{\"serviceContextId\":\"$SCID_CONST\""; then
  pass "GET bind-context -> 200 $(short)"
else fail "GET bind-context -> status=$ST corpo=$(short)"; fi
expect_edge "[44643] GET bind-context pela superficie externa" '^\{"boundServices":\[\{"serviceContextId":"'"$SCID_CONST"'"' \
  GET "$H_EXT/tv3/bind-context" "${TOK[@]}" -H "bind-token: $BT_RS512"
expect_err "GET bind-context sem bind-token" 104 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}" "${AUTH_H[@]}"
expect_err "GET bind-context sem bind-token, SEM Origin" 104 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}"
# assinatura de chave registrada, fora do prazo: 108 (a assinatura vem antes)
expect_err "GET bind-context com bind-token expirado" 108 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}" -H "bind-token: $BT_EXP"
expect_err "GET bind-context com bind-token que nao e JWT" 108 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}" -H "bind-token: abc"
# erro que ainda sai do tv3ws (a C.6.8 saiu dele), para cliente fora do
# navegador (sem Origin) e com Origin: ACAO * uma vez (C.4.1.9.2)
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
rc DEL session:current-service-id >/dev/null
expect_edge "DELETE sem servico corrente -> {} (nada a remover)" '^\{\}$' DELETE "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H "key: $HS512_KEY"
rc SET session:current-service-id "$SVC_A" >/dev/null
expect_pass "a HS512 continua registrada depois do DELETE sem servico corrente" GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS512"

echo; echo "-- APIs de informacao de API (C.6.7.8, C.6.7.9), respondidas pela borda --"
# lista e versao saem do infra/edgegateway/routes.json (campo api, Tabela
# C.2), na ordem da tabela; o testbed so implementa APIs do subsistema tv3ws
API_N=$(grep -o '"id": *"tv3ws-[^"]*"' infra/edgegateway/routes.json | sort -u | wc -l)
req GET "$H_INT/tv3/api-info" "${TOK[@]}"
N=$(body | grep -o '"id":' | wc -l)
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
# negociacao de versao (C.3.6.5) nas APIs da borda: o mesmo contrato do tv3ws
expect_edge "[44642] GET /tv3/api-info com Accept-Version 2.1" '^\{"receiverApis":' 2.1 GET "$H_INT/tv3/api-info" "${TOK[@]}" -H 'Accept-Version: 2.1'
# API-Version (C.3.6.6) desses erros da borda: 2.1 (a mais recente
# suportada) no 100, 2.0 no 101 — o mesmo do tv3ws
expect_err "[44642] GET /tv3/api-info com Accept-Version 3.0 (fora do conjunto)" 100 borda GET "$H_INT/tv3/api-info" "${TOK[@]}" -H 'Accept-Version: 3.0'
expect_api_version "[44642] 100 da borda: a versao mais recente suportada" 2.1
expect_err "[44642] GET /tv3/api-info com Accept-Version x (malformado)" 101 borda GET "$H_INT/tv3/api-info" "${TOK[@]}" -H 'Accept-Version: x'
expect_api_version "[44642] 101 da borda" 2.0
expect_err "[44642] GET /tv3/bind-context com Accept-Version 3.0" 100 borda GET "$H_INT/tv3/bind-context" "${TOK[@]}" -H "bind-token: $BT_HS512" -H 'Accept-Version: 3.0'
expect_api_version "[44642] 100 da borda em /tv3/bind-context" 2.1
expect_err "[44642] PUT /tv3/api-info (metodo nao declarado)" 100 borda PUT "$H_INT/tv3/api-info" "${TOK[@]}"
# CORS das rotas da borda: o preflight passa ao modulo CORS do KrakenD (o
# endpoint continua gerado); OPTIONS sem preflight o plugin responde
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
# primeiro acesso por HTTP na 44642 (Server-BaseURL do SSDP); uso e renovacao
# pela 44643 (Server-SecureBaseURL). A renovacao do /token por HTTP continua
# recusada com 106 pelo proprio tv3ws (emissao de credencial, client-
# identification/controller.ts). O 106 por protocolo nas DEMAIS APIs (nao
# local por HTTP fora de /authorize e /token, C.4.1.6) saiu do tv3ws com a
# D-0510-1 (reuniao de 05/10; era o validateClientProtocol de
# tv3ws/src/middleware/basic.ts) e a borda nao o aplica (sem TLS nela, lacuna
# L3, PENDENTE com o Joel): o caso abaixo registra que, hoje, a requisicao
# chega ao tv3ws.
for PM in qrcode kex; do
  if [ "$PM" = qrcode ]; then NCID=$NL_QR; else NCID=$NL_KEX; fi
  S="[nao local $PM]"
  pair "$PM" "$NCID" || { info "$S pareamento incompleto: uso, renovacao e reuso deste cliente pulados"; continue; }
  NL_REUSE_KEY=${NL_CPUB:-}   # chave ECDH do cliente usada no pareamento (kex)
  NL_TOK=(-H "Authorization: Bearer $NL_AT")
  if [ "$(rc SISMEMBER clients:authorized "$NCID")" = 1 ]; then
    pass "$S clientid em clients:authorized depois do pareamento (D-0510-4)"
  else
    fail "$S clientid fora de clients:authorized depois do pareamento"
  fi
  if ! ext_skip "$H_EXT" "$S [44643] GET /tv3/current-service com o accessToken"; then
    expect_pass "$S [44643] GET /tv3/current-service com o accessToken" GET "$H_EXT/tv3/current-service" "${NL_TOK[@]}"
  fi
  if ! ext_skip "$H_EXT" "$S [44643] $CU com bind-token HS512"; then
    expect_pass "$S [44643] $CU com bind-token HS512" GET "$H_EXT$CU" "${NL_TOK[@]}" -H "bind-token: $BT_HS512"
  fi
  expect_pass "$S [44642] API fora de /authorize e /token por HTTP (sem 106 de ninguem, L3)" GET "$H_INT/tv3/current-service" "${NL_TOK[@]}"
  expect_err "$S [44642] renovacao por HTTP com refresh-token" 106 tv3ws GET "$H_INT/tv3/token?clientid=$NCID&refresh-token=$NL_RT"
  if ! ext_skip "$H_EXT" "$S [44643] renovacao com refresh-token"; then
    req GET "$H_EXT/tv3/token?clientid=$NCID&refresh-token=$NL_RT"
    RCT=$(hdr Content-Type)
    if [ "$ST" = 200 ] && nl_node MODO=token CT="$RCT" BODY="$(base64 -w0 "$TMP/b")" SECRET="$NL_SECRET" \
       && [ "$NL_ENC" = 0 ] && [ -n "$NL_AT" ] && [ "$NL_CLASS" = non-local ]; then
      pass "$S [44643] renovacao com refresh-token -> 200 JSON sem a cifra do primeiro acesso, accessToken class=non-local"
    else
      fail "$S [44643] renovacao com refresh-token -> status=$ST content-type='$RCT' corpo=$(short) ${NL_ERR}"
    fi
  fi
  # reuso pelo MESMO metodo de pareamento: no kex vai tambem a chave do
  # cliente (sem key o tv3ws daria 105 antes de olhar o clientid)
  if [ "$PM" = kex ]; then RQ="&key=$NL_REUSE_KEY"; else RQ=""; fi
  expect_reuse "$S segundo /authorize do mesmo clientid (pm=$PM)" \
    "$H_INT/tv3/authorize?clientid=$NCID&display-name=tv30-test-nao-local&pm=$PM$RQ"
done

echo; echo "-- rota nao declarada e preflight CORS --"
for H in "$H_INT" "$H_EXT"; do
  S="[${H##*:}]"
  expect_err "$S GET /tv3/naoexiste" 100 borda GET "$H/tv3/naoexiste"
  expect_err "$S GET /tv3/xyz/abc (antes: panic do Gin, conexao resetada)" 100 borda GET "$H/tv3/xyz/abc"
  expect_err "$S GET /tv3/abc" 100 borda GET "$H/tv3/abc"
  expect_err "$S POST /tv3/users (rota antiga)" 100 borda POST "$H/tv3/users" -H 'Content-Type: application/json' -d '{}'
  expect_err "$S PUT /tv3/current-service (metodo nao declarado)" 100 borda PUT "$H/tv3/current-service"
  req OPTIONS "$H$CU" -H "Origin: $OTHER_ORIGIN" -H 'Access-Control-Request-Method: GET' \
      -H 'Access-Control-Request-Headers: authorization,bind-token'
  if [ "$CE" = 0 ] && [ "${ST:0:1}" = 2 ] && hdr Access-Control-Allow-Headers | grep -qi 'bind-token'; then
    pass "$S OPTIONS preflight (bind-token) -> $ST, Allow-Headers: $(hdr Access-Control-Allow-Headers)"
  else
    fail "$S OPTIONS preflight -> curl=$CE status=$ST allow-headers='$(hdr Access-Control-Allow-Headers)'"
  fi
  req OPTIONS "$H/tv3/xyz/abc" -H "Origin: $OTHER_ORIGIN" -H 'Access-Control-Request-Method: GET'
  if [ "$CE" = 0 ]; then pass "$S OPTIONS preflight em caminho nao declarado -> $ST (sem reset)"
  else fail "$S OPTIONS preflight em caminho nao declarado -> curl=$CE (conexao)"; fi
  # OPTIONS sem Access-Control-Request-Method nao e preflight: numa API
  # declarada responde com os cabecalhos da C.4.1.9.3; fora da tabela, 100
  expect_options "$S OPTIONS sem preflight em rota declarada" "$H$CU"
  expect_options "$S OPTIONS sem preflight em rota com {param}" "$H/tv3/$SCID_CONST/users/x"
  expect_err "$S OPTIONS sem preflight em /tv3/xyz/abc" 100 borda OPTIONS "$H/tv3/xyz/abc"
done

echo; echo "-- Redis congelado (D-0510-6): o tv3ws falha rapido e de forma explicita --"
# docker pause redis: o Redis aceita a conexao e nao responde (o pior caso: com
# o padrao do ioredis o comando esperava sem limite). /tv3/authorize SEM
# Origin nao consulta o Redis na borda (rota sem token, nenhum Origin a
# conferir) e chega ao tv3ws; o comando dele estoura o commandTimeout
# (tv3ws/src/redis-client.ts) e a camada de erro responde 404 {error:200} do
# PROPRIO tv3ws antes dos 2 s — bem antes dos 15 s de timeout da rota na borda
# (routes.json), que dariam o 404 {error:200} com origem borda. O trap
# descongela o redis se o script cair no meio.
REDIS_TOUCHED=1
if docker pause redis >/dev/null 2>&1; then
  T0=$(date +%s%N)
  expect_err "[44642] redis congelado: GET /tv3/authorize sem Origin" 200 tv3ws GET "$H_INT/tv3/authorize?clientid=$REDIS_CID&display-name=tv30-test-auth"
  MS=$(( ($(date +%s%N) - T0) / 1000000 ))
  docker unpause redis >/dev/null 2>&1
  if [ "$MS" -lt 2000 ]; then pass "[44642] redis congelado: resposta do tv3ws em $MS ms (< 2 s)"
  else fail "[44642] redis congelado: resposta em $MS ms (esperado < 2 s)"; fi
  # errorHandler do tv3ws (src/util/error.ts): "[error] <metodo> <url>: <motivo>"
  LOGL=$(docker logs --since 2m tv3ws 2>&1 | grep -F "[error] GET /tv3/authorize?clientid=$REDIS_CID" | tail -1)
  if [ -n "$LOGL" ]; then
    pass "[44642] redis congelado: a falha aparece no log do tv3ws (${LOGL##*: })"
  else
    fail "[44642] redis congelado: nenhuma linha [error] do /tv3/authorize no log do tv3ws (falha silenciosa)"
  fi
  # descongelado, o mesmo tv3ws volta a usar o Redis (sem reinicio)
  req GET "$H_INT/tv3/token?clientid=$REDIS_CID&refresh-token=x"
  for i in 1 2 3 4 5; do
    if [ "$CE" = 0 ] && [ "$ST" = 404 ] && body | grep -q '"error":102'; then break; fi
    sleep 1; req GET "$H_INT/tv3/token?clientid=$REDIS_CID&refresh-token=x"
  done
  check_err "[44642] redis descongelado: /tv3/token de clientid nunca autorizado volta a ser o 102 do tv3ws" 102 tv3ws
else
  fail "docker pause redis falhou (caso D-0510-6 nao testado)"
fi

echo; echo "-- backend fora do ar ou lento (P1): 404 {error:200} da borda, nao 500 vazio --"
# por ultimo: para e congela o tv3ws (o trap religa/descongela se o script
# cair no meio). Token valido, para a requisicao passar pelo plugin e chegar
# ao repasse do KrakenD.
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
  # o KrakenD espera o timeout padrao (2 s) nas rotas sem timeout proprio
  expect_err "[44642] tv3ws congelado (docker pause): timeout da borda" 200 borda GET "$H_INT/tv3/current-service" "${TOK[@]}"
  expect_api_version "[44642] tv3ws congelado"
  docker unpause tv3ws >/dev/null 2>&1
  expect_pass "[44642] tv3ws descongelado volta a responder" GET "$H_INT/tv3/current-service" "${TOK[@]}"
else
  fail "docker pause tv3ws falhou (caso do backend lento nao testado)"
fi

# ================================================================ fim =====
echo
echo "== resultado: $PASS PASS, $FAIL FAIL =="
for f in "${FAILED[@]}"; do echo "  FAIL $f"; done
[ "$FAIL" -eq 0 ]
