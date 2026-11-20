const rateLimit = require("express-rate-limit");

const chatLimiter = rateLimit({

    windowMs: 15 * 60 * 1000,

    max: 20,

    // Clave por usuario autenticado: cada JWT tiene su propia cuota
    // y no se agrupa bajo la IP del proxy como en el limitador de login.
    keyGenerator: (req) => `chat:${req.userId}`,

    message: {
        status: 0,
        msg: "Demasiados mensajes al asistente. Intente nuevamente en 15 minutos."
    },

    standardHeaders: true,

    legacyHeaders: false
});

module.exports = chatLimiter;
