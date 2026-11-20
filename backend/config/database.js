//Importar sequelize 
const { Sequelize } = require('sequelize');

//Crear la conexion  
// se crea el objeto que representa la conexion a la BD : nombreBD,usuario,contraseña,configuracion 
const sequelize = new Sequelize(process.env.DB_NAME, process.env.DB_USER, process.env.DB_PASSWORD, {
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 5432),
    dialect: 'postgres',
    logging: false, // evita que llene la consola con logs de consultas SQL básicas 
});

//Probar la conexion 
sequelize.authenticate()
    .then(() => console.log('DB is connected to PostgreSQL'))
    .catch(err => console.error('Error al conectar a PostgreSQL:', err));

module.exports = sequelize;