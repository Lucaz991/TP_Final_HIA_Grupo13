require('./guard.cjs')();
const assert = require('node:assert/strict');
const sequelize = require('../config/database');
const Usuario = require('../src/models/usuario.model');
const Categoria = require('../src/models/categoria.model');
const Precio = require('../src/models/precio.model');
const Horario = require('../src/models/horarioDisponible.model');
const ProfesorCategoria = require('../src/models/profesorCategoria.model');
const Tutoria = require('../src/models/tutoria.model');
const Calificacion = require('../src/models/calificacion.model');
const { SolicitudAyuda, RespuestaAyuda } = require('../src/models/solicitudes/asociaciones.model');
const passwordService = require('../src/services/password.service');

async function seed() {
    assert.match(process.env.SECURITY_ACCOUNT_PASSWORD || '', /^[a-f0-9]{64}$/);
    const [identity] = await sequelize.query(
        "SELECT current_database() AS db, current_user AS role, rolsuper FROM pg_roles WHERE rolname = current_user"
    );
    assert.equal(identity[0].db, 'h24_security_test');
    assert.equal(identity[0].role, 'h24_app');
    assert.equal(identity[0].rolsuper, false);
    // No limpiar ni sobreescribir datos existentes: reiniciar explicitamente el volumen.
    assert.equal(await Usuario.count(), 0, 'La base ya tiene usuarios; seed cancelado sin borrar datos.');
    const hash = await passwordService.hashPassword(process.env.SECURITY_ACCOUNT_PASSWORD);
    await sequelize.transaction(async transaction => {
        const users = [];
        for (const [name, rol] of [
            ['admin', 'admin'], ['alumno.a', 'alumno'], ['alumno.b', 'alumno'],
            ['profesor.a', 'profesor'], ['profesor.b', 'profesor']
        ]) {
            users.push(await Usuario.create({
                email: `${name}@h24.test`, nombre: `H24 ${name}`, apellido: 'Ficticio',
                rol, contraseniaHash: hash, genero: 'masculino', estado: 'activo',
                proveedorAuth: 'local', universidad: 'Universidad ficticia H24',
                carrera: 'Carrera de prueba', ubicacion: 'Laboratorio H24'
            }, { transaction }));
        }
        const categoria = await Categoria.create({
            nombre: 'Matematica H24', nivel: 'universitario',
            descripcion: 'Categoria sintetica para pruebas de seguridad'
        }, { transaction });
        await Precio.bulkCreate(['virtual', 'presencial'].map(modalidad => ({
            nivel: 'universitario', modalidad, precio: 100
        })), { transaction });
        for (let i = 0; i < 2; i++) {
            const alumno = users[i + 1], profesor = users[i + 3];
            await ProfesorCategoria.create({
                profesorId: profesor.id, categoriaId: categoria.id, estado: 'activo'
            }, { transaction });
            await Horario.create({
                profesorId: profesor.id, diaSemana: 'lunes', horaInicio: '10:00',
                horaFin: '18:00', modalidad: 'ambas', estado: 'activo'
            }, { transaction });
            for (const estado of ['pendiente', 'finalizada']) {
                const tutoria = await Tutoria.create({
                    alumnoId: alumno.id, profesorId: profesor.id, categoriaId: categoria.id,
                    modalidad: 'virtual', precioAcordado: 100,
                    fechaHora: '2026-11-23T15:00:00Z', estado,
                    mensaje: `H24 ficticia ${i + 1} ${estado}`,
                    pagada: estado === 'finalizada'
                }, { transaction });
                if (estado === 'finalizada') {
                    await Calificacion.create({
                        tutoriaId: tutoria.id, calificacion: 4, comentario: 'H24: dato sintetico'
                    }, { transaction });
                }
            }
            const solicitud = await SolicitudAyuda.create({
                usuarioId: alumno.id, categoriaId: categoria.id,
                titulo: `Ayuda H24 ${i + 1}`, descripcion: 'Solicitud ficticia'
            }, { transaction });
            await RespuestaAyuda.create({
                solicitudId: solicitud.id, usuarioId: profesor.id,
                respuesta: 'Respuesta ficticia H24', precio: 100
            }, { transaction });
        }
    });
    console.log('H24: 5 usuarios, 1 categoria, 2 precios, 2 horarios, 2 asignaciones,');
    console.log('4 tutorias, 2 calificaciones, 2 solicitudes y 2 respuestas ficticias.');
}

seed().catch(error => {
    console.error(error.message);
    process.exitCode = 1;
}).finally(() => sequelize.close());
