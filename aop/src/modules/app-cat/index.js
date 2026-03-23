const core = require('../../core');
const ejs = require('ejs');
const express = require('express');
const path = require('path');
const router = express.Router();
const service = require('./service');

router.get('/', async (req, res) => {
    const html = await ejs.renderFile(path.join(__dirname, 'view.ejs'),
        {
            cards: service.cards(),
            profile: service.profile(),
            basepath: core.GUI.app_catalogue
        });
    res.send(html);
});

router.get('/profile', (req, res) => {
    core.setDisplayGui(core.GUI.profile_chooser);
    res.status(200).send();
});

router.get('/select', (req, res) => {
    if (req.query.id) {
        core.setCurrentService(req.query.id);
        core.setDisplayGui(core.GUI.bootstrap_app);
        res.status(200).send();
        return;
    }
    res.status(400).send();
});

module.exports = router;