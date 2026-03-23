const core = require('../../core');
require('dotenv').config();
const ejs = require('ejs');
const express = require('express');
const path = require('path');
const router = express.Router();

router.get('/', async (req, res) => {
    const html = await ejs.renderFile(path.join(__dirname, 'view.ejs'),
        {
            mqtt_host: process.env.MQTT_HOST || 'localhost'
        });
    res.send(html);
});

router.get('/ready', (req, res) => {
    core.setDisplayGui(core.GUI.profile_chooser);
    res.status(200).send();
});

router.get('/keydown/:keyCode', (req, res) => {
    if (!req.params.keyCode) {
        res.status(400).send();
        return;
    }

    if (['27', '93'].includes(req.params.keyCode)) {
        core.openServiceInfo();
    }
    else if (req.params.keyCode == '33') {
        console.log('channel +');
    }
    else if (req.params.keyCode == '34') {
        console.log('channel -');
    }
    res.status(200).send();
});

module.exports = router;