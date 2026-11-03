#!/usr/bin/env bash
# test-remote-device-v100.sh: end-to-end test of version 100.0 of the Remote
# device communication APIs (proposal v2 of C.6.15) through the edge, with
# remote devices connected by WebSocket. Runs against the stack already up,
# prints PASS/FAIL per case and exits != 0 if any fails.
#
# Usage: bash scripts/test-remote-device-v100.sh
#
# Needs Node.js 22 or later on the host (global WebSocket). Puts a test
# client in clients:authorized through the function of the schema, issues
# its access token with the secret of the edge and, at the end (trap EXIT),
# removes the client and the devices it registered.
set -u
cd "$(dirname "$0")/.." || exit 1

H_INT=${H_INT:-http://localhost:44642}
RUN="$$$(date +%s)"
CLIENT="tv30-test-rd100-$RUN"
DEVICE_CLASS="tv30-test-rd100-$RUN"
MIN_NODE_MAJOR=22
TMP=$(mktemp -d)

die() { echo "ERRO: $*" >&2; exit 2; }
rc() { docker exec redis redis-cli "$@"; }
# fcall <function> [args...]: writes through the function of the schema
# (numkeys 0); a refusal or an error gives a message and a return != 0.
fcall() {
  local out st
  out=$(docker exec redis redis-cli --no-raw FCALL "$1" 0 "${@:2}" 2>&1); st=$?
  if [ "$st" -ne 0 ] || [[ "$out" == *"(error)"* ]]; then
    echo "ERRO: FCALL $1 nao gravou: $out" >&2
    return 1
  fi
}
env_of() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" | sed -n "s/^$2=//p" | head -1; }

# Test data: a direct write on purpose, since no service deletes a client,
# so there is no function for it (the same as scripts/test-auth.sh).
cleanup() {
  rc DEL "client:$CLIENT" >/dev/null
  rc SREM clients:authorized "$CLIENT" >/dev/null
  rm -rf "$TMP"
}

# ----------------------------------------------------------- prerequisites --
for c in edgegateway tv3ws redis; do
  [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] \
    || die "container $c nao esta rodando (suba a stack: ./tv30 up)"
done
command -v node >/dev/null || die "node ausente"
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
[ "$NODE_MAJOR" -ge "$MIN_NODE_MAJOR" ] || die "node $NODE_MAJOR; precisa do $MIN_NODE_MAJOR ou mais (WebSocket global)"

EDGE_SECRET=$(env_of edgegateway JWT_SECRET)
EDGE_ISSUER=$(env_of edgegateway JWT_ISSUER)
[ -n "$EDGE_SECRET" ] || die "JWT_SECRET ausente no edgegateway"
[ -n "$EDGE_ISSUER" ] || die "JWT_ISSUER ausente no edgegateway"

trap cleanup EXIT
trap 'exit 130' INT TERM

fcall tv30_client_authorize "$CLIENT" class standAlone refreshToken "tv30-test-rd100" \
  || die "nao consegui autorizar o cliente de teste pela funcao"

cat >"$TMP/test.mjs" <<'EOF'
// Remote devices of 2.0 and of 100.0 registered and connected at the same
// time, through the edge.
import { createHmac } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const H = process.env.H_INT;
const DEVICE_CLASS = process.env.DEVICE_CLASS;
const OPEN_TIMEOUT_MS = 5000;
const MESSAGE_TIMEOUT_MS = 5000;

let passed = 0;
let failed = 0;

function pass(name) {
    passed++;
    console.log(`PASS  ${name}`);
}

function fail(name, detail) {
    failed++;
    console.log(`FAIL  ${name} -> ${detail}`);
}

function check(name, ok, detail) {
    if (ok) {
        pass(name);
    } else {
        fail(name, detail);
    }
}

function base64Url(value) {
    return Buffer.from(value).toString('base64url');
}

// Access token of the test client, signed with the secret of the edge.
function accessToken() {
    const now = Math.floor(Date.now() / 1000);
    const header = base64Url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
    const payload = base64Url(JSON.stringify({
        iat: now, nbf: now, exp: now + 3600,
        iss: process.env.ISSUER, sub: process.env.CLIENT, class: 'standAlone',
    }));
    const signature = createHmac('sha256', process.env.SECRET).update(`${header}.${payload}`).digest('base64url');
    return `${header}.${payload}.${signature}`;
}

const AUTH = { Authorization: `Bearer ${accessToken()}` };

async function call(method, path, version, body) {
    const headers = { ...AUTH };
    if (version) {
        headers['Accept-Version'] = version;
    }
    if (body !== undefined) {
        headers['Content-Type'] = 'application/json';
    }
    const res = await fetch(`${H}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await res.text();
    let json;
    try {
        json = text ? JSON.parse(text) : undefined;
    } catch {
        json = text;
    }
    return { status: res.status, json, apiVersion: res.headers.get('API-Version') };
}

// Opens a WebSocket and keeps the messages it receives.
function connect(url) {
    const ws = new WebSocket(url);
    ws.received = [];
    ws.addEventListener('message', (event) => {
        ws.received.push(String(event.data));
    });
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`timeout opening ${url}`)), OPEN_TIMEOUT_MS);
        ws.addEventListener('open', () => {
            clearTimeout(timer);
            resolve(ws);
        });
        ws.addEventListener('error', () => {
            clearTimeout(timer);
            reject(new Error(`error opening ${url}`));
        });
    });
}

// Waits for a message of the socket that satisfies the predicate.
async function waitMessage(ws, predicate) {
    const deadline = Date.now() + MESSAGE_TIMEOUT_MS;
    while (Date.now() < deadline) {
        const found = ws.received.find(predicate);
        if (found !== undefined) {
            return found;
        }
        await new Promise((resolve) => setTimeout(resolve, 50));
    }
    return undefined;
}

async function main() {
    const body = { deviceClass: DEVICE_CLASS, supportedTypes: ['application/x-tv30-test'] };
    const listPath = `/tv3/remote-device/devices/${DEVICE_CLASS}`;

    // Registration in each version.
    const reg20 = await call('POST', '/tv3/remote-device', undefined, body);
    check('registro na 2.0', reg20.status === 200 && reg20.json?.handle && reg20.json?.url, `status=${reg20.status} corpo=${JSON.stringify(reg20.json)}`);
    const reg100 = await call('POST', '/tv3/remote-device', '100.0', body);
    check('registro na 100.0, com API-Version 100.0', reg100.status === 200 && reg100.json?.handle && reg100.json?.url && reg100.apiVersion === '100.0',
        `status=${reg100.status} api-version=${reg100.apiVersion} corpo=${JSON.stringify(reg100.json)}`);
    if (!reg20.json?.url || !reg100.json?.url) {
        return;
    }
    check('o ponto de entrada da 100.0 e por caminho (/rd/<token>) e o token difere do handle',
        /\/rd\/[^/]+$/.test(reg100.json.url) && !reg100.json.url.includes(reg100.json.handle), reg100.json.url);

    // Both devices connected.
    const dev20 = await connect(reg20.json.url);
    const dev100 = await connect(reg100.json.url);
    pass('dispositivos da 2.0 e da 100.0 conectados');

    // Each listing sees only the devices of its version.
    const list20 = await call('GET', listPath);
    const handles20 = (list20.json?.devices ?? []).map((d) => d.handle);
    check('listagem 2.0: so o dispositivo da 2.0, com url', list20.status === 200 && handles20.length === 1
        && handles20[0] === reg20.json.handle && typeof list20.json.devices[0].url === 'string',
        `status=${list20.status} corpo=${JSON.stringify(list20.json)}`);
    const list100 = await call('GET', listPath, '100.0');
    const devices100 = list100.json?.devices ?? [];
    check('listagem 100.0: so o dispositivo da 100.0, com sequence, deviceId, paired e url',
        list100.status === 200 && typeof list100.json?.sequence === 'number' && devices100.length === 1
        && typeof devices100[0].deviceId === 'string' && devices100[0].paired === false && typeof devices100[0].url === 'string'
        && !JSON.stringify(list100.json).includes(reg20.json.handle) && list100.apiVersion === '100.0',
        `status=${list100.status} api-version=${list100.apiVersion} corpo=${JSON.stringify(list100.json)}`);

    // A handle of the other version: 305 in 100.0, 101 in 2.0; the
    // registration stays.
    const cross100 = await call('DELETE', `/tv3/remote-device/${reg20.json.handle}`, '100.0');
    check('DELETE na 100.0 com handle da 2.0 -> 305', cross100.status === 404 && cross100.json?.error === 305, JSON.stringify(cross100.json));
    const cross20 = await call('DELETE', `/tv3/remote-device/${reg100.json.handle}`, '2.0');
    check('DELETE na 2.0 com handle da 100.0 -> 305', cross20.status === 404 && cross20.json?.error === 305, JSON.stringify(cross20.json));
    const crossUpdate20 = await call('POST', `/tv3/remote-device/${reg100.json.handle}`, '2.0', body);
    check('atualizacao na 2.0 com handle da 100.0 -> 305', crossUpdate20.status === 404 && crossUpdate20.json?.error === 305, JSON.stringify(crossUpdate20.json));
    const update20 = await call('POST', `/tv3/remote-device/${reg20.json.handle}`, '100.0', body);
    check('atualizacao na 100.0 com handle da 2.0 -> 305', update20.status === 404 && update20.json?.error === 305, JSON.stringify(update20.json));
    const again20 = await call('GET', listPath);
    const again100 = await call('GET', listPath, '100.0');
    check('os dois registros continuam depois dos pedidos com handle da outra versao',
        (again20.json?.devices ?? []).length === 1 && (again100.json?.devices ?? []).length === 1,
        `2.0=${JSON.stringify(again20.json)} 100.0=${JSON.stringify(again100.json)}`);

    // Update of the 100.0 registration.
    const update100 = await call('POST', `/tv3/remote-device/${reg100.json.handle}`, '100.0', body);
    check('atualizacao na 100.0 do proprio registro -> 200 com o handle', update100.status === 200 && update100.json?.handle === reg100.json.handle,
        `status=${update100.status} corpo=${JSON.stringify(update100.json)}`);

    // Communication pair through the local entry point of 100.0.
    if (devices100.length === 1) {
        const client = await connect(devices100[0].url);
        const formed = await waitMessage(dev100, (m) => m.includes('pairFormed'));
        check('par formado: o dispositivo recebe pairFormed com clientType standAlone',
            formed !== undefined && JSON.parse(formed).clientType === 'standAlone', `mensagens=${JSON.stringify(dev100.received)}`);
        const paired = await call('GET', listPath, '100.0');
        check('listagem 100.0 com o par formado: paired true', paired.json?.devices?.[0]?.paired === true, JSON.stringify(paired.json));
        dev100.send('do-dispositivo');
        const toClient = await waitMessage(client, (m) => m === 'do-dispositivo');
        check('mensagem do dispositivo chega ao cliente local', toClient !== undefined, `mensagens=${JSON.stringify(client.received)}`);
        client.send('do-cliente');
        const toDevice = await waitMessage(dev100, (m) => m === 'do-cliente');
        check('mensagem do cliente local chega ao dispositivo', toDevice !== undefined, `mensagens=${JSON.stringify(dev100.received)}`);
        client.close();
    }

    // Deregistration in each version.
    const del100 = await call('DELETE', `/tv3/remote-device/${reg100.json.handle}`, '100.0');
    check('DELETE na 100.0 do proprio registro -> 200 {}', del100.status === 200 && JSON.stringify(del100.json) === '{}', `status=${del100.status} corpo=${JSON.stringify(del100.json)}`);
    const del20 = await call('DELETE', `/tv3/remote-device/${reg20.json.handle}`);
    check('DELETE na 2.0 do proprio registro -> 200 {}', del20.status === 200 && JSON.stringify(del20.json) === '{}', `status=${del20.status} corpo=${JSON.stringify(del20.json)}`);
    dev20.close();
    dev100.close();

    await revocation(body, listPath);
}

// C.4.2.2 and C.4.4: the block of the client, published in place of the
// Access Panel, removes the registrations it made in both versions and ends
// its communication pair.
async function revocation(body, listPath) {
    const reg20 = await call('POST', '/tv3/remote-device', undefined, body);
    const reg100 = await call('POST', '/tv3/remote-device', '100.0', body);
    const dev100 = await connect(reg100.json.url);
    const list100 = await call('GET', listPath, '100.0');
    const client = await connect(list100.json.devices[0].url);
    await waitMessage(dev100, (m) => m.includes('pairFormed'));
    const clientClosed = new Promise((resolve) => client.addEventListener('close', (event) => resolve(event.code)));

    execFileSync('docker', ['exec', 'mqtt-broker', 'mosquitto_pub', '-q', '1', '-t', 'aop/access-panel/client-blocked', '-m', process.env.CLIENT]);

    const code = await Promise.race([clientClosed, new Promise((resolve) => setTimeout(() => resolve('timeout'), MESSAGE_TIMEOUT_MS))]);
    check('bloqueio do cliente: o par termina com 4002 (deviceUnavailable)', code === 4002, `codigo=${code}`);
    const after20 = await call('GET', listPath);
    const after100 = await call('GET', listPath, '100.0');
    check('bloqueio do cliente: os registros que ele fez saem das duas versoes',
        !JSON.stringify(after20.json).includes(reg20.json.handle) && (after100.json?.devices ?? []).length === 0,
        `2.0=${JSON.stringify(after20.json)} 100.0=${JSON.stringify(after100.json)}`);
    const gone20 = await call('DELETE', `/tv3/remote-device/${reg20.json.handle}`);
    const gone100 = await call('DELETE', `/tv3/remote-device/${reg100.json.handle}`, '100.0');
    check('bloqueio do cliente: os handles dos registros removidos dao 305', gone20.json?.error === 305 && gone100.json?.error === 305,
        `2.0=${JSON.stringify(gone20.json)} 100.0=${JSON.stringify(gone100.json)}`);
    dev100.close();
}

try {
    await main();
} catch (err) {
    fail('execucao', err.message);
}
console.log(`\n== ${passed} PASS, ${failed} FAIL ==`);
process.exit(failed === 0 ? 0 : 1);
EOF

echo "== remote-device 2.0 e 100.0 pela borda ($H_INT) =="
# The device entry point uses the self-signed certificate of the receiver.
H_INT="$H_INT" DEVICE_CLASS="$DEVICE_CLASS" CLIENT="$CLIENT" SECRET="$EDGE_SECRET" ISSUER="$EDGE_ISSUER" \
  NODE_TLS_REJECT_UNAUTHORIZED=0 node --no-warnings "$TMP/test.mjs"
