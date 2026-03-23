require('dotenv').config();
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');

const _PORT = process.env.PORT || 8080;

// start core component
const core = require('./core');

// import modules routes
const mod_disp = require('./modules/disp-lyr');
const mod_prfchs = require('./modules/prf-chs');
const mod_appcat = require('./modules/app-cat');
const mod_btpapp = require('./modules/btp-app');

// middleware configuration
const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended : false}));
app.use(express.static('public'));
app.use(express.static(`${process.env.USER_DATA_PATH}/thumbs`));
app.set('view engine', 'ejs');
app.set('views', 'src/views');

// allowing local clients to connect to the server
app.use(function (req, res, next) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, PATCH, DELETE');
    res.setHeader('Access-Control-Allow-Headers', 'X-Requested-With,content-type');
    next();
});

// use routes
app.use(core.GUI.profile_chooser, mod_prfchs);
app.use(core.GUI.app_catalogue, mod_appcat);
app.use(core.GUI.bootstrap_app, mod_btpapp);
app.use('/', mod_disp);

// proxy for graphics iframe
const proxyGraphics = createProxyMiddleware({
    target: '',
    changeOrigin: true,
    router: (req) => {
        return core.getGraphicsAppURL();
    },
    pathRewrite: {
        '^/graphicsAppProxy': ''
    },
    on: {
        proxyReq: (proxyReq, req, res) => {
            console.log(`Redirecting '${req.url}' to '${core.getGraphicsAppURL()}${proxyReq.path}'`);
        },
        error: (err, req, res) => {
            console.error('GraphicsAppProxy Error:', err);
            res.status(500).send('GraphicsAppProxy Error');
        }
    }
});
app.use('/graphicsAppProxy', proxyGraphics);

const proxyStream = createProxyMiddleware({
    target: '',
    changeOrigin: true,
    router: (req) => {
        return core.getVideoStreamURL();
    },
    pathRewrite: {
        '^/videoStreamProxy': ''
    },
    on: {
        proxyReq: (proxyReq, req, res) => {
            // console.log(`Redirecting '${req.url}' to '${core.getGraphicsAppURL()}${proxyReq.path}'`);
        },
        error: (err, req, res) => {
            console.error('VideoStreamProxy Error:', err);
            res.status(500).send('VideoStreamProxy Error');
        }
    }
});
app.use('/videoStreamProxy', proxyStream);

app.listen(_PORT, () => {
    console.log(`AoP running on port: ${_PORT}`);
});

// notify loading is complete
if (process.send) {
    process.send('ready');
}