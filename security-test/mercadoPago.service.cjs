const registrarAuditoria = require('../helpers/auditoria.helper');
const Tutoria = require('../models/tutoria.model');
const { RespuestaAyuda } = require('../models/solicitudes/asociaciones.model');

// Replica la firma y la logica de resolucion de entidad del servicio real
// (develop): intenta Tutoria por PK primero y luego RespuestaAyuda.
// Esto tambien reproduce la colision documentada si ambos PK coinciden.
async function crearPreferencia(idRespuesta) {
    let tipo = 'tutoria';
    let entidad = await Tutoria.findByPk(idRespuesta);
    if (!entidad) {
        entidad = await RespuestaAyuda.findByPk(idRespuesta);
        tipo = 'ayuda';
    }
    if (!entidad) {
        throw new Error("Entidad inexistente");
    }
    return {
        id: `pref-h24-${tipo}-${entidad.id}`,
        init_point: `http://127.0.0.1:9081/pago-simulado?tipo=${tipo}&id=${entidad.id}`
    };
}

async function procesarWebhook(data) {
    await registrarAuditoria(
        { ip: 'H24 Webhook Simulator', headers: { 'user-agent': 'H24' }, body: {} },
        'WEBHOOK_SIMULADO',
        'MercadoPago',
        Number(data?.data?.id || 0),
        'Webhook simulado procesado en laboratorio',
        null
    );
    return { processed: true };
}

module.exports = { crearPreferencia, procesarWebhook };
