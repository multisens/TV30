#!/usr/bin/env bash
# test-auth.sh — validacao de credenciais na BORDA (plugin tv30-auth do
# edgegateway, item 9 / decisao de 28/09). Roda contra a stack JA DE PE
# (localhost:44642 interna e 44643 externa) e imprime PASS/FAIL por caso;
# sai com codigo != 0 se algum caso falhar.
#
# Uso (Linux/WSL, com acesso ao docker):  bash scripts/test-auth.sh
#   (no WSL desta maquina: wsl.exe -u root bash /mnt/d/.../scripts/test-auth.sh)
#
# O que ele faz:
#   1. modo WARN (o que estiver rodando): requisicao sem token passa e traz
#      X-TV30-Auth-Warn: 107; rota nao declarada da 100 nos dois modos;
#      Access-Control-Allow-Origin: * uma vez, com e sem Origin (C.4.1.9.2);
#      OPTIONS sem preflight em rota declarada da 200 com os cabecalhos da
#      C.4.1.9.3; caminho com %0A nao forja linha no log;
#      pop-up de autorizacao recusado ("false") da 102.
#   2. recria SO o edgegateway com AUTH_ENFORCE=enforce (mesma variante,
#      mesmo JWT_SECRET/JWT_ISSUER do container em execucao) e cobre 107,
#      104, 106, 108, 100, preflight CORS, a API C.6.8 (POST/GET/DELETE
#      /tv3/bind-context) com HS256, HS512, RS256 e RS512, isolamento entre
#      servicos e confusao de algoritmo.
#   3. no fim (trap EXIT, inclusive em erro/Ctrl+C) volta o edge ao modo que
#      ele tinha antes e desfaz o que semeou no Redis.
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
# Estado tocado no Redis (tudo com sufixo unico desta execucao e desfeito no
# fim): session:current-service-id (salvo e restaurado), bind-context:<urn de
# teste>, origins:associated (uma origem de teste), clients:blocked (os ids de
# teste) e client:<id de teste>.
set -u
cd "$(dirname "$0")/.." || exit 1

H_INT=${H_INT:-http://localhost:44642}
H_EXT=${H_EXT:-http://localhost:44643}
NODE_IMG=${NODE_IMG:-node:20-alpine}
POP=aop/display/layers/popup/yesno
RUN="$$$(date +%s)"
CLIENT="tv30-test-auth-$RUN"
REFUSED="tv30-test-recusa-$RUN"
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
echo "== borda: modo=$ORIG_MODE variante=$ORIG_VARIANT; servico corrente='${ORIG_SVC}' =="

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

cleanup() {
  set +e
  echo; echo "== limpeza =="
  if [ -n "$ORIG_SVC" ]; then rc SET session:current-service-id "$ORIG_SVC" >/dev/null
  else rc DEL session:current-service-id >/dev/null; fi
  rc DEL "bind-context:$SVC_A" "bind-context:$SVC_B" "client:$CLIENT" "client:$REFUSED" >/dev/null
  rc HDEL origins:associated "$ASSOC" >/dev/null
  rc SREM clients:blocked "$CLIENT" "$REFUSED" >/dev/null
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

# erro no formato C.3.2 (D5): 404 + {error,description} JSON + ACAO *
expect_err() {
  local name=$1 code=$2 why=""; shift 2
  req "$@"
  local b; b=$(body)
  [ "$CE" = 0 ] || why="$why curl=$CE(conexao)"
  [ "$ST" = 404 ] || why="$why status=$ST"
  printf '%s' "$b" | grep -Eq "^\{\"error\":$code,\"description\":\".*\"\}$" || why="$why corpo=$(short)"
  hdr Content-Type | grep -qi '^application/json' || why="$why content-type='$(hdr Content-Type)'"
  [ "$(hdr Access-Control-Allow-Origin)" = "*" ] || why="$why acao='$(hdr Access-Control-Allow-Origin)'"
  if [ -z "$why" ]; then pass "$name -> 404 {error:$code}"; else fail "$name -> esperado 404 {error:$code}:$why"; fi
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
    expect_err  "[warn ${H##*:}] GET /tv3/xyz/abc (rota nao declarada)" 100 GET "$H/tv3/xyz/abc"
    expect_options "[warn ${H##*:}] OPTIONS sem preflight em rota declarada" "$H/tv3/current-service"
    expect_err  "[warn ${H##*:}] OPTIONS sem preflight em rota nao declarada" 100 OPTIONS "$H/tv3/xyz/abc"
  done
  # caminho com quebra de linha (%0A) nao forja linha no log da borda
  MARK="tv30forjado$RUN"
  req GET "$H_INT/tv3/abc%0A$MARK"
  if [ "$(docker logs --since 2m edgegateway 2>&1 | grep -c "^$MARK")" = 0 ]; then
    pass "[warn 44642] caminho com %0A nao gera linha forjada no log"
  else fail "[warn 44642] caminho com %0A gerou linha comecando por $MARK no log"; fi
else
  info "edge nao estava em warn ($ORIG_MODE): casos de warn pulados"
fi
# correcao do tv3ws: "false" do pop-up nao autoriza mais (Boolean("false"))
authorize "$REFUSED" false
if [ "$ST" = 404 ] && printf '%s' "$(body)" | grep -q '"error":102'; then
  pass "pop-up recusado (\"false\") -> 404 {error:102}, cliente nao autorizado"
else
  fail "pop-up recusado -> esperado {error:102}: status=$ST corpo=$(short)"
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
req GET "$H_INT/tv3/token?clientid=$CLIENT&refresh-token=$RT"
AT=$(json_str accessToken)
[ -n "$AT" ] && pass "GET /tv3/token -> accessToken" || fail "GET /tv3/token -> sem accessToken: status=$ST corpo=$(short)"
SIG=${AT##*.}; C=${SIG:10:1}; [ "$C" = A ] && N=B || N=A
AT_TAMPER="${AT%.*}.${SIG:0:10}$N${SIG:11}"
TOK=(-H "Authorization: Bearer $AT")

for H in "$H_INT" "$H_EXT"; do
  S="[${H##*:}]"
  expect_err  "$S sem token (GET /tv3/current-service)" 107 GET "$H/tv3/current-service"
  expect_err  "$S token adulterado" 107 GET "$H/tv3/current-service" -H "Authorization: Bearer $AT_TAMPER"
  expect_err  "$S token expirado" 107 GET "$H/tv3/current-service" -H "Authorization: Bearer $AT_EXPIRED"
  expect_err  "$S token sem prefixo Bearer" 107 GET "$H/tv3/current-service" -H "Authorization: $AT"
  ext_skip "$H" "$S token valido" || expect_pass "$S token valido" GET "$H/tv3/current-service" "${TOK[@]}"
done
rc SADD clients:blocked "$CLIENT" >/dev/null
expect_err "[44642] cliente em clients:blocked" 107 GET "$H_INT/tv3/current-service" "${TOK[@]}"
rc SREM clients:blocked "$CLIENT" >/dev/null
expect_pass "[44642] cliente desbloqueado volta a passar" GET "$H_INT/tv3/current-service" "${TOK[@]}"
# token valido com class local-associated: dispensa bind-token, mas nao o bloqueio
TOK_ASSOC=(-H "Authorization: Bearer $AT_ASSOC")
expect_pass "[44642] token de classe associado dispensa bind-token" GET "$H_INT/tv3/current-service/users/current-user" "${TOK_ASSOC[@]}"
rc SADD clients:blocked "$CLIENT" >/dev/null
expect_err "[44642] token de classe associado de cliente bloqueado" 107 GET "$H_INT/tv3/current-service/users/current-user" "${TOK_ASSOC[@]}"
rc SREM clients:blocked "$CLIENT" >/dev/null

echo; echo "-- rotas token+bind sem bind-token --"
expect_err "[44642] GET current-user com token, sem bind-token" 104 GET "$H_INT/tv3/current-service/users/current-user" "${TOK[@]}"
expect_err "[44643] POST sensory-effect com token, sem bind-token" 104 POST "$H_EXT/tv3/sensory-effect-renderers/x" "${TOK[@]}" -H 'Content-Type: application/json' -d '{}'
# POST {scid}/users cai no mesmo handler da C.6.14.1 (bind-token shall)
expect_err "[44642] POST /tv3/current-service/users sem bind-token" 104 POST "$H_INT/tv3/current-service/users" "${TOK[@]}" -H 'Content-Type: application/json' -d '{}'
expect_err "[44642] POST /tv3/xyz/users sem bind-token (antes passava so com token)" 104 POST "$H_INT/tv3/xyz/users" "${TOK[@]}" -H 'Content-Type: application/json' -d '{}'

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
expect_err "POST bind-context por nao associado (sem Origin associado)" 106 POST "$H_INT/tv3/bind-context" -H 'Content-Type: application/json' -d "$BODY_HS256"
expect_err "POST bind-context sem key" 105 POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d '{"alg":"HS256"}'
expect_err "POST bind-context alg fora dos 4" 101 POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d '{"alg":"ES256","key":"x"}'
expect_err "POST bind-context RS256 com chave que nao e RSA" 101 POST "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H 'Content-Type: application/json' -d '{"alg":"RS256","key":"nao-e-chave"}'

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
expect_err "bind-token de chave nao registrada" 108 GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_UNREG"
expect_err "confusao de algoritmo (HS256 assinado com a chave publica RS256 registrada)" 108 GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_CONFUSION"
expect_err "bind-token com nbf no futuro" 108 GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_NBF"
expect_err "bind-token expirado" 108 GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_EXP"
expect_err "bind-token com iat no futuro" 108 GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_IAT"
expect_err "bind-token alg none" 108 GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_NONE"
expect_err "bind-token que nao e JWT" 108 GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: abc"
expect_err "scid de outro servico no caminho (provisorio L2)" 108 GET "$H_INT/tv3/outro-scid/users/x" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "POST /tv3/xyz/users com bind-token valido (scid de outro servico, L2)" 108 POST "$H_INT/tv3/xyz/users" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'
expect_err "POST /tv3/Current-Service/users (caixa trocada; o Express nao diferencia)" 108 POST "$H_INT/tv3/Current-Service/users" "${TOK[@]}" -H "bind-token: $BT_HS256" -H 'Content-Type: application/json' -d '{}'

echo; echo "-- isolamento entre emissoras (D4) --"
rc SET session:current-service-id "$SVC_B" >/dev/null
expect_err "servico corrente trocado: bind-token da emissora A" 108 GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS256"
rc SET session:current-service-id "$SVC_A" >/dev/null
expect_pass "servico A de volta: o mesmo bind-token passa" GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS256"

echo; echo "-- associado (D8): sem access token e sem bind-token --"
expect_pass "associado em $CU sem credencial" GET "$H_INT$CU" "${ASSOC_H[@]}"
expect_err  "associado em /tv3/authorize (L4, so em enforce)" 106 GET "$H_INT/tv3/authorize?clientid=x&display-name=y" "${ASSOC_H[@]}"
expect_err  "associado em /tv3/authorize com Authorization qualquer (nao escapa do 106)" 106 GET "$H_INT/tv3/authorize?clientid=x&display-name=y" "${ASSOC_H[@]}" -H 'Authorization: x'
expect_err  "associado em /tv3/token com Authorization qualquer (nao escapa do 106)" 106 GET "$H_INT/tv3/token?clientid=x&refresh-token=y" "${ASSOC_H[@]}" -H 'Authorization: x'

echo; echo "-- GET /tv3/bind-context --"
req GET "$H_INT/tv3/bind-context" "${TOK[@]}" -H "bind-token: $BT_HS256"
if [ "$ST" = 200 ] && body | grep -q "\"boundServices\":\[{\"serviceContextId\":\"$SCID_CONST\""; then
  pass "GET bind-context -> 200 $(short)"
else fail "GET bind-context -> status=$ST corpo=$(short)"; fi
expect_err "GET bind-context sem bind-token (tv3ws)" 104 GET "$H_INT/tv3/bind-context" "${TOK[@]}" "${AUTH_H[@]}"
# erro do tv3ws para cliente fora do navegador (sem Origin): ACAO * tambem (C.4.1.9.2)
expect_err "GET bind-context sem bind-token (tv3ws), SEM Origin" 104 GET "$H_INT/tv3/bind-context" "${TOK[@]}"
expect_acao "erro do tv3ws SEM Origin: ACAO uma vez" GET "$H_INT/tv3/bind-context" "${TOK[@]}"
expect_acao "erro do tv3ws COM Origin: ACAO uma vez" GET "$H_INT/tv3/bind-context" "${TOK[@]}" "${AUTH_H[@]}"
expect_acao "erro da borda SEM Origin: ACAO uma vez" GET "$H_INT/tv3/current-service"
expect_err "GET bind-context sem access token" 107 GET "$H_INT/tv3/bind-context" -H "bind-token: $BT_HS256"
expect_err "GET bind-context pelo associado" 106 GET "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H "bind-token: $BT_HS256"

echo; echo "-- DELETE /tv3/bind-context (revogacao) --"
req DELETE "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H "key: $HS256_KEY"
[ "$ST" = 200 ] && [ "$(body)" = "{}" ] && pass "DELETE bind-context HS256 -> 200 {}" || fail "DELETE bind-context -> status=$ST corpo=$(short)"
expect_err "bind-token da chave revogada" 108 GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS256"
expect_err "GET bind-context com token da chave revogada (tv3ws)" 101 GET "$H_INT/tv3/bind-context" "${TOK[@]}" "${AUTH_H[@]}" -H "bind-token: $BT_HS256"
expect_pass "as demais chaves continuam valendo (HS512)" GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_HS512"
req DELETE "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H "key: $RS256_DER"
expect_err "RS256 revogada pelo DER base64 (registrada em PEM)" 108 GET "$H_INT$CU" "${TOK[@]}" -H "bind-token: $BT_RS256"
req DELETE "$H_INT/tv3/bind-context" "${ASSOC_H[@]}" -H "key: tv30-test-inexistente"
[ "$ST" = 200 ] && pass "DELETE de chave inexistente -> 200" || fail "DELETE inexistente -> status=$ST corpo=$(short)"
expect_err "DELETE sem cabecalho key" 105 DELETE "$H_INT/tv3/bind-context" "${ASSOC_H[@]}"
expect_err "DELETE por nao associado" 106 DELETE "$H_INT/tv3/bind-context" -H "key: $HS512_KEY"

echo; echo "-- rota nao declarada e preflight CORS --"
for H in "$H_INT" "$H_EXT"; do
  S="[${H##*:}]"
  expect_err "$S GET /tv3/naoexiste" 100 GET "$H/tv3/naoexiste"
  expect_err "$S GET /tv3/xyz/abc (antes: panic do Gin, conexao resetada)" 100 GET "$H/tv3/xyz/abc"
  expect_err "$S GET /tv3/abc" 100 GET "$H/tv3/abc"
  expect_err "$S POST /tv3/users (rota antiga)" 100 POST "$H/tv3/users" -H 'Content-Type: application/json' -d '{}'
  expect_err "$S PUT /tv3/current-service (metodo nao declarado)" 100 PUT "$H/tv3/current-service"
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
  expect_err "$S OPTIONS sem preflight em /tv3/xyz/abc" 100 OPTIONS "$H/tv3/xyz/abc"
done

# ================================================================ fim =====
echo
echo "== resultado: $PASS PASS, $FAIL FAIL =="
for f in "${FAILED[@]}"; do echo "  FAIL $f"; done
[ "$FAIL" -eq 0 ]
