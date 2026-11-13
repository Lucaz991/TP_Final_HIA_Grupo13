const { Op, fn, col, literal } = require('sequelize');
const Usuario = require('../models/usuario.model');
const Categoria = require('../models/categoria.model');
const HorarioDisponible = require('../models/horarioDisponible.model');
const registrarAuditoria = require("../helpers/auditoria.helper");

const usuarioCtrl = {};

usuarioCtrl.getUsuarios = async (req, res) => {
    /* #swagger.tags = ['Usuarios']
       #swagger.summary = 'Listar usuarios o profesores'
       #swagger.description = 'Retorna una página de hasta 100 usuarios. Permite filtrar por rol (ej. ?rol=profesor) para obtener sus tutorías dictadas, opiniones y rating.'
       #swagger.parameters['rol'] = {
         in: 'query',
         description: 'Filtrar por rol: alumno, profesor, admin.',
         required: false,
         type: 'string'
       }
       #swagger.responses[200] = {
         description: 'Usuarios obtenidos correctamente.',
         schema: { type: 'array', items: { $ref: '#/definitions/UsuarioUpdateRequest' } }
       }
       #swagger.responses[500] = { description: 'Error al obtener los usuarios.' }
    */
    const positive = value => /^\d+$/.test(String(value)) && Number.isSafeInteger(Number(value)) && Number(value) > 0;
    const page = Number(req.query.page || 1);
    const limit = Number(req.query.limit || 12);
    if (!positive(page) || !positive(limit) || limit > 100 || !Number.isSafeInteger((page - 1) * limit)
        || (req.query.id !== undefined && !positive(req.query.id))
        || (req.query.categoriaId && !positive(req.query.categoriaId))
        || (req.query.rol && !['profesor', 'alumno', 'admin'].includes(req.query.rol))) {
        return res.status(400).json({ status: 0, msg: 'Filtros o paginación inválidos.' });
    }
    let order = [['id', 'ASC']];
    if (req.query.orden === 'cercania') {
        const lat = Number(req.query.lat), lng = Number(req.query.lng);
        if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180
            || req.query.lat === '' || req.query.lng === '') {
            return res.status(400).json({ status: 0, msg: 'Coordenadas inválidas.' });
        }
        // Coseno del ángulo central: orden global por cercanía, antes de paginar.
        order = [[literal(`(sin(radians(${lat})) * sin(radians("Usuario".lat)) + cos(radians(${lat})) * cos(radians("Usuario".lat)) * cos(radians("Usuario".lng - ${lng})))`), 'DESC NULLS LAST'], ['id', 'ASC']];
    }
    try {
        const where = req.query.rol ? { rol: req.query.rol } : {};
        if (req.query.id) where.id = Number(req.query.id);
        if (req.query.categoriaId) {
            where[Op.and] = literal(`EXISTS (SELECT 1 FROM profesores_categorias pc WHERE pc."profesorId" = "Usuario".id AND pc."categoriaId" = ${Number(req.query.categoriaId)})`);
        }
        const total = await Usuario.count({ where });
        const ids = await Usuario.findAll({ where, attributes: ['id'], order, limit, offset: (page - 1) * limit });
        const include = [
            { model: Categoria, as: 'categoriasEnseniadas', attributes: ['id', 'nombre'], through: { attributes: [] } },
            { model: HorarioDisponible, as: 'horarios' }
        ];
        const users = ids.length ? await Usuario.findAll({
            where: { id: { [Op.in]: ids.map(u => u.id) } }, include,
            attributes: { exclude: ['contraseniaHash', 'createdAt', 'updatedAt'] }
        }) : [];
        const byId = new Map(users.map(u => [u.id, u.toJSON()]));
        const data = ids.map(u => byId.get(u.id)).filter(Boolean);
        const Tutoria = require('../models/tutoria.model');
        const Calificacion = require('../models/calificacion.model');
        const profesores = data.filter(u => u.rol === 'profesor');
        // Agregación SQL: no materializar las tutorías dictadas en Node.
        const stats = profesores.length ? await Tutoria.findAll({
            where: { profesorId: { [Op.in]: profesores.map(u => u.id) }, estado: 'finalizada' },
            attributes: ['profesorId', [fn('COUNT', fn('DISTINCT', col('Tutoria.id'))), 'cantidad'],
                [fn('AVG', col('calificacion.calificacion')), 'rating']],
            include: [{ model: Calificacion, as: 'calificacion', attributes: [], required: false }],
            group: ['profesorId'], raw: true
        }) : [];
        const statsById = new Map(stats.map(row => [Number(row.profesorId), row]));
        for (const profesor of profesores) {
            const stat = statsById.get(profesor.id);
            profesor.tutoriasDictadas = Number(stat?.cantidad || 0);
            profesor.rating = Number(Number(stat?.rating || 0).toFixed(1));
            // La interfaz muestra dos opiniones: recuperar únicamente esas dos.
            const recientes = await Tutoria.findAll({
                attributes: ['id'], where: { profesorId: profesor.id, estado: 'finalizada' },
                include: [{ model: Calificacion, as: 'calificacion', required: true },
                    { model: Usuario, as: 'alumno', attributes: ['nombre', 'apellido'] }],
                order: [['id', 'DESC']], limit: 2, subQuery: false
            });
            profesor.opiniones = recientes.map(t => ({ id: t.calificacion.id,
                calificacion: t.calificacion.calificacion, comentario: t.calificacion.comentario,
                fecha: t.calificacion.createdAt,
                alumno: t.alumno ? `${t.alumno.nombre} ${t.alumno.apellido}` : 'Alumno' }));
        }
        res.json({ data, pagination: { page, limit, total, totalPages: Math.ceil(total / limit) } });
    } catch (error) {
        console.error(error);
        res.status(500).json({ status: '0', msg: 'Error al obtener los usuarios.' });
    }
};

usuarioCtrl.updateUsuario = async (req, res) => {
    /* #swagger.tags = ['Usuarios']
       #swagger.summary = 'Actualizar datos de perfil'
       #swagger.description = 'Actualiza la información del perfil del usuario (nombre, apellido, ubicación, carrera, tarifa base, etc.).'
       #swagger.consumes = ['application/json']
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID del usuario a actualizar.',
         required: true,
         type: 'integer'
       }
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos actualizados del usuario.',
         required: true,
         schema: { $ref: '#/definitions/UsuarioUpdateRequest' }
       }
       #swagger.responses[200] = {
         description: 'Usuario actualizado correctamente.',
         schema: { status: '1', msg: 'Usuario actualizado correctamente.' }
       }
       #swagger.responses[404] = { description: 'Usuario no encontrado.' }
       #swagger.responses[500] = { description: 'Error al actualizar el usuario.' }
    */
    try {
        const { id } = req.params;
        const data = req.body;

        const usuario = await Usuario.findByPk(id);
        if (!usuario) {
            return res.status(404).json({ status: '0', msg: 'Usuario no encontrado.' });
        }

        await usuario.update({
            nombre: data.nombre,
            apellido: data.apellido,
            ubicacion: data.ubicacion,
            universidad: data.universidad,
            carrera: data.carrera,
            nivelAcademico: data.nivelAcademico,
            biografia: data.biografia,
            tarifaBase: data.tarifaBase
        });

        if (usuario.rol === 'profesor' && data.perfilProfesor) {
            const [perfil] = await PerfilProfesor.findOrCreate({
                where: { usuarioId: id },
                defaults: { primario: false, secundario: false, universitario: false, doctorado: false }
            });
            await perfil.update({
                primario: !!data.perfilProfesor.primario,
                secundario: !!data.perfilProfesor.secundario,
                universitario: !!data.perfilProfesor.universitario,
                doctorado: !!data.perfilProfesor.doctorado
            });
        }

        const usuarioActualizado = await Usuario.findByPk(id, {
            include: [
                { model: PerfilProfesor, as: 'perfilProfesor' },
                { model: Categoria, as: 'categoriasEnseniadas', attributes: ['id', 'nombre'], through: { attributes: [] } },
                { model: HorarioDisponible, as: 'horarios' }
            ]
        });
                await registrarAuditoria(
                    req,
                    "UPDATE",
                    "Usuario",
                    usuario.id,
                    `Actualizó el perfil del usuario ${usuario.nombre} ${usuario.apellido}`,
                    usuario.id
                );

        res.json({ status: '1', msg: 'Usuario actualizado correctamente.', usuario: usuarioActualizado });
    } catch (error) {
        console.error(error);
        res.status(500).json({ status: '0', msg: 'Error al actualizar el usuario.' });
    }
};

usuarioCtrl.addHorario = async (req, res) => {
    /* #swagger.tags = ['Usuarios']
       #swagger.summary = 'Agregar horario disponible a profesor'
       #swagger.description = 'Registra un nuevo intervalo de disponibilidad horaria para un profesor.'
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos del nuevo horario.',
         required: true,
         schema: { $ref: '#/definitions/UsuarioAddHorarioRequest' }
       }
       #swagger.responses[200] = {
         description: 'Horario agregado correctamente.',
         schema: { status: 1, msg: 'Horario agregado correctamente' }
       }
       #swagger.responses[500] = { description: 'Error al agregar horario.' }
    */
    try {
        const { usuarioId, diaSemana, horaInicio, horaFin } = req.body;
        const nuevo = await HorarioDisponible.create({
            profesorId: usuarioId,
            diaSemana: diaSemana,
            horaInicio: horaInicio,
            horaFin: horaFin
        });
        await registrarAuditoria(
            req,
            "CREATE",
            "HorarioDisponible",
            nuevo.id,
            `Agregó un horario (${diaSemana} ${horaInicio}-${horaFin})`,
            usuarioId
        );
        res.json({ status: 1, msg: 'Horario agregado correctamente', data: nuevo });
    } catch (error) {
        console.error(error);
        res.status(500).json({ status: 0, msg: 'Error al agregar horario' });
    }
};

usuarioCtrl.deleteHorario = async (req, res) => {
    /* #swagger.tags = ['Usuarios']
       #swagger.summary = 'Eliminar horario disponible de profesor'
       #swagger.description = 'Elimina físicamente un intervalo de disponibilidad horaria.'
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID del horario disponible a eliminar.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Horario eliminado correctamente.',
         schema: { status: 1, msg: 'Horario eliminado correctamente' }
       }
       #swagger.responses[500] = { description: 'Error al eliminar horario.' }
    */
    try {
        const { id } = req.params;
        await HorarioDisponible.destroy({ where: { id } });
        await registrarAuditoria(
            req,
            "DELETE",
            "HorarioDisponible",
            id,
            `Eliminó un horario`,
            null
        );
        res.json({ status: 1, msg: 'Horario eliminado correctamente' });
    } catch (error) {
        console.error(error);
        res.status(500).json({ status: 0, msg: 'Error al eliminar horario' });
    }
};

module.exports = usuarioCtrl;