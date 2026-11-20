//Importaciones 
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const sequelize = require('./config/database');
const { DataTypes } = require('sequelize');

const pagoRoutes = require("./src/routes/mercadoPago.route.js");

require('./src/models/solicitudes/asociaciones.model.js'); // Importa las asociaciones para que se apliquen
// --------------------------------
//Creacion de la aplicacion 
var app = express();

// Detras de Nginx (y cloudflared en produccion): la IP real del cliente
// llega en X-Forwarded-For. Confiamos solo en saltos de red privada/loopback;
// sin esto express-rate-limit agrupa a todos los usuarios bajo la IP del proxy.
app.set('trust proxy', 'loopback, linklocal, uniquelocal');

//Middlewares  
app.use(express.json()); //permite recibir JSON 
app.use(cors({
    origin: process.env.FRONTEND_URL
        ? ['http://localhost:4200', process.env.FRONTEND_URL]
        : 'http://localhost:4200'
}));

// Cargar swagger
const swaggerUi = require('swagger-ui-express');
const swaggerFile = require('./swagger_output.json');

// Documentación Swagger UI
app.use('/api/docs', swaggerUi.serve, swaggerUi.setup(swaggerFile));

// Rechaza IDs no numéricos en la URL con 400 antes de llegar a Sequelize
// (un ID malformado provocaba HTTP 500 por el error de casteo en la consulta).
// Los param callbacks no se heredan a routers montados: hay que registrarlos
// sobre cada router individual.
const { nombresIds, validarParamIds } = require('./src/middleware/validarParamIds');
const aplicarIds = (router) => {
    for (const nombre of nombresIds) router.param(nombre, validarParamIds);
    return router;
};

//Rutas 
app.use('/api/admin', aplicarIds(require('./src/routes/admin.route')));
app.use('/api/autenticacion', aplicarIds(require('./src/routes/autenticacion.route.js')));
app.use('/api/usuario', aplicarIds(require('./src/routes/usuario.route.js')));

app.use('/api/solicitud', aplicarIds(require('./src/routes/solicitudes/solicitudAyuda.route')));
app.use('/api/respuesta', aplicarIds(require('./src/routes/solicitudes/respuestaAyuda.route')));
app.use('/api/tutoria', aplicarIds(require('./src/routes/tutoria.route.js')));

app.use('/api/categoria', aplicarIds(require('./src/routes/categoria.route.js')));
app.use('/api/mercadopago', aplicarIds(require('./src/routes/mercadoPago.route.js')));
app.use('/api/calificacion', aplicarIds(require('./src/routes/calificacion.route.js')));

app.use("/api/auditoria", aplicarIds(require("./src/routes/auditoria.route.js")));

// =========================
// REDIRECCIONES DE MERCADO PAGO
// AGREGUEN ACÁ
// =========================

app.get("/pago-exitoso", (req, res) => {
    // #swagger.tags = ['MercadoPago']
    // #swagger.summary = 'Redirección de pago exitoso'
    // #swagger.description = 'Endpoint al que redirige MercadoPago cuando el pago es exitoso.'
    const frontendUrl = process.env.FRONTEND_URL || "http://localhost:4200";
    res.redirect(
        `${frontendUrl}/pago-exitoso?` +
        new URLSearchParams(req.query).toString()
    );
});

app.get("/pago-error", (req, res) => {
    // #swagger.tags = ['MercadoPago']
    // #swagger.summary = 'Redirección de pago fallido'
    // #swagger.description = 'Endpoint al que redirige MercadoPago cuando el pago falla.'
    const frontendUrl = process.env.FRONTEND_URL || "http://localhost:4200";
    res.redirect(
        `${frontendUrl}/pago-error?` +
        new URLSearchParams(req.query).toString()
    );
});

app.get("/pago-pendiente", (req, res) => {
    // #swagger.tags = ['MercadoPago']
    // #swagger.summary = 'Redirección de pago pendiente'
    // #swagger.description = 'Endpoint al que redirige MercadoPago cuando el pago está pendiente.'
    const frontendUrl = process.env.FRONTEND_URL || "http://localhost:4200";
    res.redirect(
        `${frontendUrl}/pago-pendiente?` +
        new URLSearchParams(req.query).toString()
    );
});


app.use('/api/precio', aplicarIds(require('./src/routes/precio.route.js')));
app.use('/api/mercadopago', aplicarIds(require('./src/routes/mercadoPago.route.js')));
app.use('/api/calificacion', aplicarIds(require('./src/routes/calificacion.route.js')));

app.use('/api/horarioDisponible', aplicarIds(require('./src/routes/horarioDisponible.route.js')))
app.use('/api/chat', aplicarIds(require('./src/routes/chat.route')));


//Configuracion del puerto 
app.set('port', process.env.PORT || 3000);

// Los datos iniciales se cargan mediante los scripts SQL.
sequelize.sync()
    .then(() => {
        console.log('Tablas de PostgreSQL sincronizadas');

        app.listen(app.get('port'), () => {
            console.log(
                'Servidor iniciado en el puerto',
                app.get('port')
            );
        });
    })
    .catch(err => {
        console.error(
            'No se pudo iniciar el servidor debido a un error en la BD:',
            err
        );

        process.exitCode = 1;
    });