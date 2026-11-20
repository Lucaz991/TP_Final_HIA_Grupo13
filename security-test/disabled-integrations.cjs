// Defensa adicional si alguien llama directamente al backend dentro de la red.
async function disabled() {
    throw new Error('H24: integracion externa deshabilitada en el entorno de prueba');
}

module.exports = {
    crearPreferencia: disabled,
    procesarWebhook: disabled,
    getResponse: disabled
};
