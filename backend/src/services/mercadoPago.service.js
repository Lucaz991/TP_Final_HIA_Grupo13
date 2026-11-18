const { MercadoPagoConfig, Preference, Payment } = require("mercadopago");

const RespuestaAyuda = require("../models/solicitudes/respuestaAyuda.model");
const SolicitudAyuda = require("../models/solicitudes/solicitudAyuda.model");
const Tutoria = require("../models/tutoria.model");
const registrarAuditoria = require("../helpers/auditoria.helper");

const client = new MercadoPagoConfig({
    accessToken: process.env.MP_ACCESS_TOKEN
});

const preference = new Preference(client);
const payment = new Payment(client);

async function crearPreferencia({ tipo, entidad }) {
    const precioCobrar = tipo === 'ayuda' ? Number(entidad.precio) : Number(entidad.precioAcordado);
    if (!Number.isFinite(precioCobrar) || precioCobrar <= 0) {
        throw new Error("El importe a cobrar no es válido");
    }

    const notificationUrl = process.env.MERCADOPAGO_NOTIFICATION_URL;
    if (!notificationUrl) {
        throw new Error("MERCADOPAGO_NOTIFICATION_URL no está configurada");
    }

    const frontendUrl = process.env.FRONTEND_URL || "http://localhost:4200";
    const prodFrontendUrl = process.env.PRODUCTION_FRONTEND_URL;
    const isBridge = !!prodFrontendUrl;
    const targetFrontendUrl = isBridge ? prodFrontendUrl : frontendUrl;
    const backUrls = isBridge
        ? {
            success: `${targetFrontendUrl}/pago-bridge?target=pago-exitoso`,
            failure: `${targetFrontendUrl}/pago-bridge?target=pago-error`,
            pending: `${targetFrontendUrl}/pago-bridge?target=pago-pendiente`
          }
        : {
            success: `${targetFrontendUrl}/pago-exitoso`,
            failure: `${targetFrontendUrl}/pago-error`,
            pending: `${targetFrontendUrl}/pago-pendiente`
          };

    const body = {
        items: [{
            title: tipo === 'ayuda'
                ? "Pago de respuesta a solicitud de ayuda"
                : "Pago de sesión de tutoría",
            quantity: 1,
            currency_id: "ARS",
            unit_price: precioCobrar
        }],
        external_reference: `${tipo}:${entidad.id}`,
        notification_url: notificationUrl,
        back_urls: backUrls
    };

    if (targetFrontendUrl.startsWith("https://")) {
        body.auto_return = "approved";
    }

    const preferencia = await preference.create({ body });

    if (entidad.constructor.rawAttributes.preferenceId) {
        entidad.preferenceId = preferencia.id;
        await entidad.save();
    }
    await registrarAuditoria(
        { ip: "Servidor", headers: { "user-agent": "Backend" } },
        "CREAR_PREFERENCIA_PAGO",
        tipo === "ayuda" ? "RespuestaAyuda" : "Tutoria",
        entidad.id,
        "Se generó una preferencia de pago en Mercado Pago.",
        tipo === "ayuda" ? entidad.solicitud?.usuarioId : entidad.alumnoId
    );

    return preferencia;
}

async function procesarWebhook(data) {
    if (data?.type !== "payment") return { ignored: true };

    const paymentId = String(data?.data?.id || '');
    if (!paymentId) throw new Error("Notificación de pago sin identificador");

    const pago = await payment.get({ id: paymentId });
    if (pago.status !== "approved") return { ignored: true };

    const [tipo, entidadId] = String(pago.external_reference || '').split(':');
    if (!['ayuda', 'tutoria'].includes(tipo) || !/^\d+$/.test(entidadId || '')) {
        return { ignored: true };
    }

    const entidad = tipo === 'ayuda'
        ? await RespuestaAyuda.findByPk(entidadId, {
            include: [{ model: SolicitudAyuda, as: 'solicitud' }]
        })
        : await Tutoria.findByPk(entidadId);
    if (!entidad) return { ignored: true };
    if (entidad.constructor.rawAttributes.preferenceId && entidad.preferenceId
        && pago.preference_id && entidad.preferenceId !== String(pago.preference_id)) {
        return { ignored: true };
    }

    const precioEsperado = tipo === 'ayuda' ? Number(entidad.precio) : Number(entidad.precioAcordado);
    if (pago.currency_id !== 'ARS'
        || Math.abs(Number(pago.transaction_amount) - precioEsperado) > 0.01) {
        return { ignored: true };
    }

    const paymentIdTexto = String(paymentId);
    if (entidad.pagada && entidad.paymentId === paymentIdTexto) {
        return { alreadyProcessed: true };
    }
    if (entidad.pagada) return { ignored: true };

    await entidad.update({ pagada: true, paymentId: paymentIdTexto });
    await registrarAuditoria(
        { ip: "MercadoPago Webhook", headers: { "user-agent": "Mercado Pago" } },
        "PAGO",
        tipo === "ayuda" ? "RespuestaAyuda" : "Tutoria",
        entidad.id,
        `Se aprobó el pago #${paymentIdTexto}.`,
        tipo === "ayuda" ? entidad.solicitud?.usuarioId : entidad.alumnoId
    );

    return { processed: true };
}

module.exports = {
    crearPreferencia,
    procesarWebhook
};
