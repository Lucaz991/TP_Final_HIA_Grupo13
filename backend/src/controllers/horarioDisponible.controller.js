const HorarioDisponible = require('../models/horarioDisponible.model');
const Usuario = require('../models/usuario.model');

const horarioCtrl = {};


horarioCtrl.getHorariosProfesor = async (req, res) => {
    /* #swagger.tags = ['Horarios']
       #swagger.summary = 'Obtener horarios de un profesor'
       #swagger.description = 'Retorna todos los horarios disponibles registrados como activos para un profesor.'
       #swagger.parameters['profesorId'] = {
         in: 'path',
         description: 'ID del profesor.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Horarios obtenidos correctamente.',
         schema: { status: 1, data: [] }
       }
       #swagger.responses[500] = { description: 'Error al obtener horarios.' }
    */
    try {
        const horarios = await HorarioDisponible.findAll({
            where: {
                profesorId: req.params.profesorId,
                estado: 'activo'
            },
            attributes: {
                exclude: ['createdAt', 'updatedAt']
            }
        });
        res.json({ status: 1, data: horarios });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al obtener horarios' });
    }
};

horarioCtrl.createHorario = async (req, res) => {
    /* #swagger.tags = ['Horarios']
       #swagger.summary = 'Crear un horario disponible'
       #swagger.description = 'Registra un nuevo horario disponible para dar tutorías.'
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos del horario.',
         required: true,
         schema: { $ref: '#/definitions/HorarioRequest' }
       }
       #swagger.responses[200] = {
         description: 'Horario creado o reactivado correctamente.',
         schema: { $ref: '#/definitions/HorarioResponse' }
       }
       #swagger.responses[500] = { description: 'Error al crear horario.' }
    */
    try {
        const usuario = await Usuario.findByPk(req.userId);
        const profesorId = Number(req.body.profesorId);
        if (!usuario) return res.status(401).json({ status: 0, msg: 'Sesión requerida.' });
        if (usuario.rol !== 'admin' && (usuario.rol !== 'profesor' || profesorId !== usuario.id)) {
            return res.status(403).json({ status: 0, msg: 'Solo puede crear horarios en su propio perfil de profesor.' });
        }
        const profesor = await Usuario.findOne({ where: { id: profesorId, rol: 'profesor' } });
        if (!profesor) return res.status(400).json({ status: 0, msg: 'Profesor inválido.' });

        const busq = await HorarioDisponible.findOne({
            where: {
                profesorId,
                diaSemana: req.body.diaSemana,
                horaInicio: req.body.horaInicio,
                horaFin: req.body.horaFin,
                modalidad: req.body.modalidad,
            }
        });
        if (busq) {
            busq.estado = 'activo';
            await busq.save();
            return res.json({ status: 1, msg: 'Horario reactivado', data: busq });
        }
        const nuevo = await HorarioDisponible.create({
            profesorId,
            diaSemana: req.body.diaSemana,
            horaInicio: req.body.horaInicio,
            horaFin: req.body.horaFin,
            modalidad: req.body.modalidad,
            estado: 'activo'
        });
        return res.json({ status: 1, msg: 'Horario creado', data: nuevo });

    } catch (error) {
        console.log(error);
        res.status(500).json({ status: 0, msg: 'Error al crear horario' });
    }
};


horarioCtrl.deleteHorario = async (req, res) => {
    /* #swagger.tags = ['Horarios']
       #swagger.summary = 'Eliminar un horario'
       #swagger.description = 'Desactiva lógicamente el horario disponible de un profesor (lo marca como inactivo).'
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID del horario disponible a eliminar.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Horario eliminado correctamente.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[404] = { description: 'Horario no encontrado.' }
       #swagger.responses[500] = { description: 'Error al eliminar horario.' }
    */
    try {
        const horario = await HorarioDisponible.findByPk(req.params.id);
        if (!horario) return res.status(404).json({ status: 0, msg: 'Horario no encontrado' });
        const usuario = await Usuario.findByPk(req.userId);
        if (!usuario) return res.status(401).json({ status: 0, msg: 'Sesión requerida.' });
        if (usuario.rol !== 'admin' && horario.profesorId !== usuario.id) {
            return res.status(403).json({ status: 0, msg: 'Solo puede eliminar sus propios horarios.' });
        }

        horario.estado = 'inactivo';
        await horario.save();
        return res.json({ status: 1, msg: 'Horario eliminado lógicamente' });
    } catch (error) {
        return res.status(500).json({ status: 0, msg: 'Error al eliminar horario' });
    }
};

module.exports = horarioCtrl;