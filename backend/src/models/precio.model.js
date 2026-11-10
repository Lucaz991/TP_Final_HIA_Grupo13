const { DataTypes } = require('sequelize');
const sequelize = require('../../config/database');

const Precio = sequelize.define('Precio', {
    // id automatico
    nivel: { 
        type: DataTypes.ENUM('primario','secundario','terciario','universitario','doctorado'),
        allowNull: false
    },
    modalidad: {
        type: DataTypes.ENUM('presencial', 'virtual'),
        allowNull: false
    },
    precio: { type: DataTypes.FLOAT, allowNull: false }
}, {
    tableName: 'precios',
    timestamps: true,
    indexes: [
        {
            name: 'precios_nivel_modalidad_unique',
            unique: true,
            fields: ['nivel', 'modalidad']
        }
    ]
});

module.exports = Precio;