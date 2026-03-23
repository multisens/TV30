const core = require('../../core');
const ejs = require('ejs');
const express = require('express');
const path = require('path');
const router = express.Router();
const service = require('./service');

router.get('/', async (req, res, next) => {
    const html = await ejs.renderFile(path.join(__dirname, 'view.ejs'),
        {
            cards: service.cards(),
            basepath: core.GUI.profile_chooser
        });
    res.send(html);
});

router.get('/create', (req, res) => {
    core.setDisplayGui(core.GUI.profile_creator);
    res.status(200).send();
});

router.get('/select', (req, res) => {
    if (req.query.id) {
        core.setCurrentUser(req.query.id);
        core.setDisplayGui(core.GUI.app_catalogue);
        res.status(200).send();
        return;
    }
    res.status(400).send();
});


module.exports = router;