'use strict';

const express = require('express');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3001;

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
            description: 'Rotas registradas no KrakenD Internal Gateway'
        },
        servers: [{ url: 'http://localhost:44642', description: 'KrakenD Internal Gateway' }],
        paths
    });
});

app.get('/health', (_req, res) => {
    res.status(200).json({ status: 'ok' });
});

app.listen(PORT, () => {
    console.log(`[middleware-internal] porta ${PORT}`);
});
