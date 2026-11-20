const crypto = require('crypto');
const mercadoPagoService = require('../services/mercadoPago.service');

const mercadoPagoCtrl = {};

// Verifica la firma HMAC que Mercado Pago envia en x-signature
// (ts + v1) con la clave secreta configurada en el panel de desarrollador.
// Devuelve 0 si es valida o el codigo HTTP de error correspondiente.
const validarFirmaWebhook = (req) => {
    const secret = process.env.MP_WEBHOOK_SECRET;
    if (!secret) return 503;

    const signature = req.get('x-signature') || '';
    const requestId = req.get('x-request-id') || '';
    const parts = Object.fromEntries(signature.split(',')
        .map(part => part.split('=', 2).map(value => value.trim())));
    const { ts, v1 } = parts;
    const dataId = req.query['data.id'] || req.body?.data?.id;
    if (!ts || !v1 || !requestId || !dataId || !/^\d{13}$/.test(ts)
        || !/^[a-f0-9]{64}$/i.test(v1)) {
        return 400;
    }
    if (Math.abs(Date.now() - Number(ts)) > 5 * 60 * 1000) return 401;

    const manifest = `id:${String(dataId).toLowerCase()};request-id:${requestId};ts:${ts};`;
    const expected = crypto.createHmac('sha256', secret).update(manifest).digest('hex');
    const expectedBuffer = Buffer.from(expected);
    const receivedBuffer = Buffer.from(v1);
    return expectedBuffer.length === receivedBuffer.length
        && crypto.timingSafeEqual(expectedBuffer, receivedBuffer) ? 0 : 401;
};

mercadoPagoCtrl.crearPreferencia = async (req, res) => {
    /* #swagger.tags = ['MercadoPago']
       #swagger.summary = 'Crear preferencia de pago'
       #swagger.description = 'Genera una preferencia en Mercado Pago asociada a una respuesta de ayuda para poder iniciar el checkout en el frontend.'
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'ID de la respuesta de ayuda a pagar.',
         required: true,
         schema: { $ref: '#/definitions/PreferenciaRequest' }
       }
       #swagger.responses[200] = {
         description: 'Preferencia de pago creada correctamente.',
         schema: { $ref: '#/definitions/PreferenciaResponse' }
       }
       #swagger.responses[500] = { description: 'Error al crear la preferencia.' }
    */
    try {
        const respuesta = await mercadoPagoService.crearPreferencia(
            req.body.respuestaId
        );

        res.json({
            status: 1,
            init_point: respuesta.init_point
        });

    } catch (error) {

        console.error(error);

        res.status(500).json({
            status: 0,
            msg: "Error al crear la preferencia"
        });

    }

};

mercadoPagoCtrl.webhook = async (req, res) => {
    /* #swagger.tags = ['MercadoPago']
       #swagger.summary = 'Webhook de notificaciones de pago'
       #swagger.description = 'Recibe notificaciones instantáneas de pago (IPN) desde Mercado Pago para procesar y validar el estado de los pagos.'
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Payload enviado por Mercado Pago.',
         required: true,
         schema: { type: 'object' }
       }
       #swagger.responses[200] = { description: 'Notificación procesada.' }
       #swagger.responses[400] = { description: 'Firma malformada.' }
       #swagger.responses[401] = { description: 'Firma inválida o expirada.' }
       #swagger.responses[500] = { description: 'Error interno.' }
       #swagger.responses[503] = { description: 'Webhook sin secreto configurado.' }
    */
    const signatureStatus = validarFirmaWebhook(req);
    if (signatureStatus !== 0) {
        return res.status(signatureStatus).json({ status: 0, msg: 'Webhook no autorizado.' });
    }
    try {
        await mercadoPagoService.procesarWebhook(req.body);

        res.sendStatus(200);

    } catch (error) {

        console.error(error);

        res.sendStatus(500);

    }

};

module.exports = mercadoPagoCtrl;