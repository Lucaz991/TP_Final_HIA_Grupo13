const assert = require('node:assert/strict');

module.exports = function assertTestEnvironment() {
    assert.equal(process.env.SECURITY_TEST_MODE, 'isolated-h24');
    assert.equal(process.env.NODE_ENV, 'test');
    assert.equal(process.env.DB_HOST, 'database');
    assert.equal(process.env.DB_NAME, 'h24_security_test');
    assert.equal(process.env.DB_USER, 'h24_app');
    assert.equal(process.env.FRONTEND_URL, 'http://localhost:9081');
    for (const name of ['DB_PASSWORD', 'JWT_SECRET']) {
        assert.match(process.env[name] || '', /^[a-f0-9]{64}$/, `Falta credencial de prueba: ${name}`);
    }
    for (const name of [
        'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_REFRESH_TOKEN',
        'MP_ACCESS_TOKEN', 'MP_PUBLIC_KEY', 'GROQ_API_KEY', 'TUNNEL_TOKEN',
        'PRODUCTION_FRONTEND_URL'
    ]) {
        assert.ok(!process.env[name], `No se permiten credenciales externas: ${name}`);
    }
};
