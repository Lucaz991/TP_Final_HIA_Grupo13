const crypto = require('node:crypto');
const mercadoPagoService = require('../services/mercadoPago.service');
const Usuario = require('../models/usuario.model');
const Tutoria = require('../models/tutoria.model');
const SolicitudAyuda = require('../models/solicitudes/solicitudAyuda.model');
const RespuestaAyuda = require('../models/solicitudes/respuestaAyuda.model');

const mercadoPagoCtrl = {};

const httpError = (status, msg) => Object.assign(new Error(msg), { status });

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

const resolverEntidadPago = async (req) => {
    const tipo = req.body.tipo;
    const entidadId = Number(req.body.entidadId);
    if (!['ayuda', 'tutoria'].includes(tipo) || !Number.isSafeInteger(entidadId) || entidadId < 1) {
        throw httpError(400, 'Tipo o identificador de pago inválido.');
    }

    const usuario = await Usuario.findByPk(req.userId);
    if (!usuario) throw httpError(401, 'Sesión requerida.');

    let entidad;
    let pagadorId;
    if (tipo === 'ayuda') {
        entidad = await RespuestaAyuda.findByPk(entidadId, {
            include: [{ model: SolicitudAyuda, as: 'solicitud' }]
        });
        if (!entidad?.solicitud) throw httpError(404, 'Respuesta no encontrada.');
        pagadorId = entidad.solicitud.usuarioId;
        if (entidad.estado !== 'ACEPTADA') {
            throw httpError(400, 'Solo se pueden pagar respuestas aceptadas.');
        }
    } else {
        entidad = await Tutoria.findByPk(entidadId);
        if (!entidad) throw httpError(404, 'Tutoría no encontrada.');
        pagadorId = entidad.alumnoId;
        if (!['pendiente', 'aceptada'].includes(entidad.estado)) {
            throw httpError(400, 'La tutoría no admite una preferencia de pago.');
        }
    }

    if (usuario.rol !== 'admin' && usuario.id !== pagadorId) {
        throw httpError(403, 'Solo el pagador autorizado puede crear la preferencia.');
    }
    if (entidad.pagada) throw httpError(400, 'El pago ya fue registrado.');

    return { tipo, entidad };
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
        const { tipo, entidad } = await resolverEntidadPago(req);
        const respuesta = await mercadoPagoService.crearPreferencia({ tipo, entidad });

        res.json({
            status: 1,
            init_point: respuesta.init_point
        });

    } catch (error) {
        const status = error.status || 500;
        if (status === 500) console.error(error);
        res.status(status).json({
            status: 0,
            msg: status === 500 ? "Error al crear la preferencia" : error.message
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
       #swagger.responses[500] = { description: 'Error interno.' }
    */
    const signatureStatus = validarFirmaWebhook(req);
    if (signatureStatus) return res.sendStatus(signatureStatus);

    res.sendStatus(200);
    setImmediate(async () => {
        try {
            await mercadoPagoService.procesarWebhook(req.body);
        } catch (error) {
            console.error(error);
        }
    });

};

module.exports = mercadoPagoCtrl;