require('./guard.cjs')();
const assert = require('node:assert/strict');
const sequelize = require('../config/database');
const Usuario = require('../src/models/usuario.model');
const passwordService = require('../src/services/password.service');

(async () => {
    const password = process.env.SECURITY_ACCOUNT_PASSWORD || '';
    assert.match(password, /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z\d]).{8,20}$/);
    const hash = await passwordService.hashPassword(password);
    const users = await Usuario.findAll({ where: { proveedorAuth: 'local' } });
    assert.equal(users.length, 5, 'Se esperaban las cinco cuentas ficticias H24');
    for (const user of users) {
        assert.match(user.email, /@h24\.test$/);
        await user.update({ contraseniaHash: hash });
    }
    console.log('H24: contrasena ficticia actualizada para las cinco cuentas.');
})().catch(error => {
    console.error(error.message);
    process.exitCode = 1;
}).finally(() => sequelize.close());
