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

//Rutas 
app.use('/api/admin', require('./src/routes/admin.route'));
app.use('/api/autenticacion', require('./src/routes/autenticacion.route.js'));
app.use('/api/usuario', require('./src/routes/usuario.route.js'));

app.use('/api/solicitud', require('./src/routes/solicitudes/solicitudAyuda.route'));
app.use('/api/respuesta', require('./src/routes/solicitudes/respuestaAyuda.route'));
app.use('/api/tutoria', require('./src/routes/tutoria.route.js'));

app.use('/api/categoria', require('./src/routes/categoria.route.js'));
app.use('/api/mercadopago', require('./src/routes/mercadoPago.route.js'));
app.use('/api/calificacion', require('./src/routes/calificacion.route.js'));

app.use("/api/auditoria",require("./src/routes/auditoria.route.js"));

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


app.use('/api/precio', require('./src/routes/precio.route.js'));
app.use('/api/mercadopago', require('./src/routes/mercadoPago.route.js'));
app.use('/api/calificacion', require('./src/routes/calificacion.route.js'));

app.use('/api/horarioDisponible', require('./src/routes/horarioDisponible.route.js'))
app.use('/api/chat', require('./src/routes/chat.route'));


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