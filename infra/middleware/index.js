'use strict';

const express = require('express');
const jwt = require('jsonwebtoken');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || '0123456789';
const JWT_ISSUER = process.env.JWT_ISSUER || 'GenericIssuer';

app.use(express.json());

// POST /validate — chamado pelo plugin Go do KrakenD para cada requisição
app.post('/validate', (req, res) => {
    const token = req.headers['authorization'];

    if (!token) {
        return res.status(401).json({ error: 'Authorization header ausente' });
    }

    try {
        // ignoreExpiration: true para compatibilidade com o CCWS,
        // que tem a validação de expiração comentada no manager.ts
        jwt.verify(token, JWT_SECRET, {
            issuer: JWT_ISSUER,
            ignoreExpiration: true
        });

        console.log('[validate] token válido');
        return res.status(200).end();
    } catch (err) {
        console.log('[validate] token inválido:', err.message);
        return res.status(401).json({ error: 'Token inválido', details: err.message });
    }
});

app.get('/openapi.json', (_req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    const krakendPath = process.env.KRAKEND_CONFIG || '/etc/krakend/krakend.json';
    let krakend;
    try {
        krakend = JSON.parse(fs.readFileSync(krakendPath, 'utf-8'));
    } catch (err) {
        return res.status(500).json({ error: 'Não foi possível ler krakend.json', details: err.message });
    }

    const paths = {};
    for (const endpoint of krakend.endpoints || []) {
        const path = endpoint.endpoint;
        const method = (endpoint.method || 'GET').toLowerCase();
        const parameters = (endpoint.input_headers || []).map(h => ({
            name: h,
            in: 'header',
            required: h === 'Authorization',
            schema: { type: 'string' }
        }));
        const backends = (endpoint.backend || []).flatMap(b => b.host || []);
        paths[path] = {
            [method]: {
                summary: path,
                parameters,
                'x-backend': backends,
                responses: {
                    '200': { description: 'OK' },
                    '401': { description: 'Unauthorized' },
                    '500': { description: 'Internal Server Error' }
                }
            }
        };
    }

    res.json({
        openapi: '3.0.0',
        info: {
            title: krakend.name || 'KrakenD API',
            version: String(krakend.version || '1'),
            description: 'Rotas registradas no KrakenD API Gateway'
        },
        servers: [{ url: 'https://localhost:44643', description: 'KrakenD External Gateway' }],
        paths
    });
});

app.get('/health', (_req, res) => {
    res.status(200).json({ status: 'ok' });
});

app.listen(PORT, () => {
    console.log(`[consent-middleware] porta ${PORT}`);
    console.log(`[consent-middleware] JWT_ISSUER=${JWT_ISSUER}`);
});
