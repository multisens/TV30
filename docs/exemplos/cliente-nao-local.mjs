// Non-local client of the TV 3.0 WebServices: pairing by PIN (kex),
// first access token and one API call over HTTPS.
//
// Usage: node cliente-nao-local.mjs [tv-host]   (default: localhost)
// Requires Node.js 18 or later; no dependencies.

import crypto from 'node:crypto';
import https from 'node:https';
import { createInterface } from 'node:readline/promises';

const TV_HOST = process.argv[2] || 'localhost';
// C.3.4: the port of Server-BaseURL is fixed.
const MANIFEST_URL = `http://${TV_HOST}:44642/manifest`;
const DISPLAY_NAME = 'Cliente de exemplo';
// C.4.3.3: ECDH on P-256.
const CURVE = 'prime256v1';
// C.4.3.3: the PIN is the hash modulo 10 000, with four digits.
const PIN_MODULUS = 10000n;
const PIN_DIGITS = 4;
// C.6.1.2.2: the symmetric key has 128 bits.
const KEY_BYTES = 16;

async function main() {
    const manifest = await readManifest();
    console.log(`TV encontrada: ${manifest.friendlyName}`);
    console.log(`  HTTP:  ${manifest.baseUrl}`);
    console.log(`  HTTPS: ${manifest.secureBaseUrl}`);

    const clientId = crypto.randomUUID();
    const ecdh = crypto.createECDH(CURVE);
    ecdh.generateKeys();
    const clientKey = ecdh.getPublicKey(null, 'uncompressed').toString('base64url');

    console.log('Pedindo autorização: responda "sim" na tela da TV.');
    const authorization = await authorize(manifest.baseUrl, clientId, clientKey);

    const hash = sha256(ecdh.computeSecret(Buffer.from(authorization.key, 'base64url')));
    const secret = hash.subarray(0, KEY_BYTES);
    await confirmPin(pinOf(hash));

    const challengeResponse = solveChallenge(authorization.challenge, secret);
    const token = await firstToken(manifest.baseUrl, clientId, challengeResponse, secret);
    console.log('Pareado. Guarde para os próximos acessos:');
    console.log(`  clientid:      ${clientId}`);
    console.log(`  refresh token: ${token.refreshToken}`);

    const serverCert = Buffer.from(token.serverCert, 'base64').toString('utf8');
    const service = await getOverHttps(
        `${manifest.secureBaseUrl}/tv3/current-service`,
        token.accessToken,
        serverCert,
    );
    console.log('Serviço corrente (GET /tv3/current-service, por HTTPS):');
    console.log(service);
}

// C.3.4: the manifest answers in headers.
async function readManifest() {
    const response = await fetch(MANIFEST_URL);
    if (!response.ok) {
        throw new Error(`manifesto respondeu ${response.status}`);
    }
    return {
        baseUrl: `http://${response.headers.get('Server-BaseURL')}`,
        secureBaseUrl: `https://${response.headers.get('Server-SecureBaseURL')}`,
        friendlyName: response.headers.get('Device-FriendlyName'),
    };
}

// C.6.1.2: the answer comes after the viewer answers the pop-up.
async function authorize(baseUrl, clientId, clientKey) {
    const query = new URLSearchParams({
        'clientid': clientId,
        'display-name': DISPLAY_NAME,
        'pm': 'kex',
        'key': clientKey,
    });
    const response = await fetch(`${baseUrl}/tv3/authorize?${query}`);
    const body = await response.json();
    if (!response.ok) {
        throw new Error(`authorize respondeu o erro ${body.error}`);
    }
    return body;
}

// C.4.3.3: the viewer types on the client the PIN shown by the TV.
async function confirmPin(expectedPin) {
    const prompt = createInterface({ input: process.stdin, output: process.stdout });
    const typed = await prompt.question('Digite o PIN que aparece na TV: ');
    prompt.close();
    if (typed.trim() !== expectedPin) {
        throw new Error('o PIN não confere: a chave não é a mesma da TV');
    }
}

// Table C.4: decrypt, SHA-256, encrypt, base64 URL safe.
function solveChallenge(challenge, secret) {
    const plain = aes(false, secret, Buffer.from(challenge, 'base64url'));
    return aes(true, secret, sha256(plain)).toString('base64url');
}

// C.6.1.3.3: the first answer comes encrypted with the symmetric key.
async function firstToken(baseUrl, clientId, challengeResponse, secret) {
    const query = new URLSearchParams({
        'clientid': clientId,
        'challenge-response': challengeResponse,
    });
    const response = await fetch(`${baseUrl}/tv3/token?${query}`);
    const raw = Buffer.from(await response.arrayBuffer());
    if (!response.ok) {
        throw new Error(`token respondeu ${raw.toString('utf8')}`);
    }
    return JSON.parse(aes(false, secret, raw).toString('utf8'));
}

// C.4.1.1: the client trusts the certificate received in the pairing, and
// only it, whatever the host name.
async function getOverHttps(url, accessToken, serverCert) {
    const expected = new crypto.X509Certificate(serverCert).fingerprint256;
    const options = {
        headers: { 'Authorization': `Bearer ${accessToken}` },
        ca: serverCert,
        checkServerIdentity: (host, cert) => {
            if (cert.fingerprint256 !== expected) {
                return new Error('o certificado não é o recebido no pareamento');
            }
            return undefined;
        },
    };
    return new Promise((resolve, reject) => {
        const request = https.get(url, options, (response) => {
            let text = '';
            response.setEncoding('utf8');
            response.on('data', (chunk) => {
                text += chunk;
            });
            response.on('end', () => {
                resolve(`${response.statusCode} ${text}`);
            });
        });
        request.on('error', reject);
    });
}

function pinOf(hash) {
    const value = BigInt(`0x${hash.toString('hex')}`) % PIN_MODULUS;
    return value.toString().padStart(PIN_DIGITS, '0');
}

function sha256(data) {
    return crypto.createHash('sha256').update(data).digest();
}

// C.6.1.3.3: AES-128 ECB with PKCS#7 padding.
function aes(encrypt, key, data) {
    const cipher = encrypt
        ? crypto.createCipheriv('aes-128-ecb', key, null)
        : crypto.createDecipheriv('aes-128-ecb', key, null);
    return Buffer.concat([cipher.update(data), cipher.final()]);
}

try {
    await main();
} catch (error) {
    console.error(`Falhou: ${error.message}`);
    process.exitCode = 1;
}
