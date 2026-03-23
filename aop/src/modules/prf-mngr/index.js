const express = require('express');
const router = express.Router();
const service = require('./service');

router.get('/create', (req, res, next) => {
    res.render('create-profile');
});

router.post('/create', async (req, res, next) => {
    try {
        const newUser = await service.createUser(req.body);
        res.status(201).json({ 
            success: true, 
            message: 'Usuário criado com sucesso',
            user: newUser 
        });
    } catch (error) {
        res.status(400).json({ 
            success: false, 
            message: error.message 
        });
    }
});

module.exports = router;