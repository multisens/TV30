import * as dotenv from 'dotenv';
import http from 'http';
import https from 'https';
import logger from './logger';
dotenv.config();

import app from './app';
const http_server = http.createServer(app);
const https_server = https.createServer({
    key: Buffer.from(process.env.HTTPS_KEY!, 'base64'),
    cert: Buffer.from(process.env.HTTPS_CERT!, 'base64')
}, app);

let _PORT = process.env.HTTP_PORT || 44642;
http_server.listen(_PORT, () => {
    logger.info(`TV 3.0 HTTP Webservice running on port: ${_PORT}`);
});

_PORT = process.env.HTTPS_PORT || 44643;
https_server.listen(_PORT, () => {
    logger.info(`TV 3.0 HTTPS Webservice running on port: ${_PORT}`);
});


import ssdpServer from './ssdp-server';
ssdpServer.start();
logger.info('SSDP server running on port 1900');


if (process.send) {
    process.send('ready');
}