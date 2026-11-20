const { MercadoPagoConfig, Preference, Payment } = require("mercadopago");

const RespuestaAyuda = require("../models/solicitudes/respuestaAyuda.model");
const Tutoria = require("../models/tutoria.model");
const registrarAuditoria = require("../helpers/auditoria.helper");

const client = new MercadoPagoConfig({
    accessToken: process.env.MP_ACCESS_TOKEN
    
});

const preference = new Preference(client);
const payment = new Payment(client);

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

    const precioCobrar = tipo === 'ayuda' ? Number(entidad.precio) : Number(entidad.precioAcordado);
    const tituloItem = tipo === 'ayuda' ? "Pago de respuesta a solicitud de ayuda" : "Pago de sesión de tutoría";

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

        items: [
            {
                title: tituloItem,
                quantity: 1,
                currency_id: "ARS",
                unit_price: precioCobrar
            }
        ],

        external_reference: `${tipo}:${entidad.id}`,

        //notification_url: "https://thesaurus-thong-doing.ngrok-free.dev/api/mercadopago/webhook",
        notification_url: "https://thesaurus-thong-doing.ngrok-free.dev/api/mercadopago/webhook",

        back_urls: backUrls

    };

    if (targetFrontendUrl.startsWith("https://")) {
        body.auto_return = "approved";
    }

    const preferencia = await preference.create({ body });

    entidad.preferenceId = preferencia.id;

        await entidad.save();
        await registrarAuditoria(
            {
                ip: "Servidor",
                headers: {
                    "user-agent": "Backend"
                }
            },
            "CREAR_PREFERENCIA_PAGO",
            tipo === "ayuda" ? "RespuestaAyuda" : "Tutoria",
            entidad.id,
            `Se generó una preferencia de pago en Mercado Pago.`,
            tipo === "ayuda" ? entidad.idUsuario : entidad.alumnoId
        );

    return preferencia;

}

async function procesarWebhook(data) {

    if (data.type !== "payment") return;

    const paymentId = data.data.id;

    const pago = await payment.get({
        id: paymentId
    });

    if (pago.status !== "approved") return;

    const ref = pago.external_reference;
    let tipo = 'ayuda';
    let id = ref;

    if (ref && ref.includes(':')) {
        const parts = ref.split(':');
        tipo = parts[0];
        id = parts[1];
    }

    if (tipo === "ayuda") {

    const respuesta = await RespuestaAyuda.findByPk(id);

    if (respuesta) {

        respuesta.pagada = true;
        respuesta.paymentId = paymentId;

        await respuesta.save();

        await registrarAuditoria(
            {
                ip: "MercadoPago Webhook",
                headers: {
                    "user-agent": "Mercado Pago"
                }
            },
            "PAGO",
            "RespuestaAyuda",
            respuesta.id,
            `Se aprobó el pago de la respuesta de ayuda #${respuesta.id}. PaymentId: ${paymentId}`,
            respuesta.idUsuario
        );

        console.log("Respuesta pagada correctamente");

    }


    } else if (tipo === "tutoria") {

    const tutoria = await Tutoria.findByPk(id);

    if (tutoria) {

        tutoria.pagada = true;
        tutoria.paymentId = paymentId;

        await tutoria.save();

        await registrarAuditoria(
            {
                ip: "MercadoPago Webhook",
                headers: {
                    "user-agent": "Mercado Pago"
                }
            },
            "PAGO",
            "Tutoria",
            tutoria.id,
            `El alumno realizó el pago de la tutoría #${tutoria.id}. PaymentId: ${paymentId}`,
            tutoria.alumnoId
        );

        console.log("Tutoría pagada correctamente");

    }


}}

module.exports = {

    crearPreferencia,

    procesarWebhook

};