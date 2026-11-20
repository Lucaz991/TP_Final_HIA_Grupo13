const express = require('express');
const router = express.Router();

const mercadoPagoCtrl = require('../controllers/mercadoPago.controller');
const authCtrl = require('../controllers/auth.controller');


router.post('/crear-preferencia', authCtrl.verifyToken, mercadoPagoCtrl.crearPreferencia);

// Webhook
router.post('/webhook', mercadoPagoCtrl.webhook);
module.exports = router;