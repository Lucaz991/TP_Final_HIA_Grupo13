const registrarAuditoria = require('../helpers/auditoria.helper');

async function crearPreferencia({ tipo, entidad }) {
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
