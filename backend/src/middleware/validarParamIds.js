// Nombres de parámetros de ruta que deben ser IDs numéricos.
const nombresIds = ['id', 'profesorId', 'solicitudId', 'tutoriaId', 'respuestaId', 'horarioId'];

// Callback de app.param(): se ejecuta al extraer el parámetro durante el
// matcheo de ruta, antes de entrar al controlador. Responde 400 si no es dígito.
const validarParamIds = (req, res, next, valor, nombre) => {
    if (!/^\d+$/.test(valor)) {
        return res.status(400).json({ status: 0, msg: `El parámetro ${nombre} debe ser numérico.` });
    }
    next();
};

module.exports = { nombresIds, validarParamIds };
