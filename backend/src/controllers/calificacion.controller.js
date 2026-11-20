const Calificacion = require('../models/calificacion.model');
const Tutoria = require('../models/tutoria.model');
const Usuario = require('../models/usuario.model');

const calificacionCtrl = {};

const getUsuarioActual = async (req) => Usuario.findByPk(req.userId);
const puedeAccederTutoria = (usuario, tutoria) =>
    usuario.rol === 'admin' || usuario.id === tutoria.alumnoId || usuario.id === tutoria.profesorId;

calificacionCtrl.crearCalificacion = async (req, res) => {
    /* #swagger.tags = ['Calificaciones']
       #swagger.summary = 'Crear una calificación para una tutoría'
       #swagger.description = 'Permite al alumno calificar una tutoría finalizada o completada.'
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos de la calificación.',
         required: true,
         schema: { $ref: '#/definitions/CalificacionRequest' }
       }
       #swagger.responses[200] = {
         description: 'Calificación creada correctamente.',
         schema: { $ref: '#/definitions/CalificacionResponse' }
       }
       #swagger.responses[400] = { description: 'Faltan campos obligatorios o tutoría no finalizada.' }
       #swagger.responses[404] = { description: 'Tutoría no encontrada.' }
       #swagger.responses[500] = { description: 'Error al calificar la tutoría.' }
    */
    try {
        const { tutoriaId, calificacion, comentario } = req.body;

        if (!tutoriaId || !calificacion) {
            return res.status(400).json({ status: 0, msg: 'La tutoría y la calificación son obligatorias.' });
        }

        const usuario = await getUsuarioActual(req);
        if (!usuario) return res.status(401).json({ status: 0, msg: 'Sesión requerida.' });
        const tutoria = await Tutoria.findByPk(tutoriaId);
        if (!tutoria) {
            return res.status(404).json({ status: 0, msg: 'Tutoría no encontrada.' });
        }
        if (usuario.rol !== 'alumno' || usuario.id !== tutoria.alumnoId) {
            return res.status(403).json({ status: 0, msg: 'Solo el alumno de la tutoría puede calificarla.' });
        }

        if (tutoria.estado !== 'finalizada' && tutoria.estado !== 'completada') {
            return res.status(400).json({ status: 0, msg: 'Solo se pueden calificar tutorías finalizadas o completadas.' });
        }

        const calificacionExistente = await Calificacion.findOne({ where: { tutoriaId: tutoriaId } });
        if (calificacionExistente) {
            return res.status(400).json({ status: 0, msg: 'Esta tutoría ya ha sido calificada.' });
        }

        const nuevaCalificacion = await Calificacion.create({
            tutoriaId,
            calificacion,
            comentario
        });

        res.json({ status: 1, msg: 'Calificación creada correctamente', data: nuevaCalificacion });
    } catch (error) {
        console.error("Error al crear calificación:", error);
        res.status(500).json({ status: 0, msg: 'Error al calificar la tutoría.' });
    }
};

calificacionCtrl.obtenerCalificacionPorTutoria = async (req, res) => {
    /* #swagger.tags = ['Calificaciones']
       #swagger.summary = 'Obtener calificación de una tutoría'
       #swagger.description = 'Obtiene los detalles de calificación asociados a un ID de tutoría.'
       #swagger.parameters['tutoriaId'] = {
         in: 'path',
         description: 'ID de la tutoría.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Calificación obtenida correctamente.',
         schema: { $ref: '#/definitions/CalificacionResponse' }
       }
       #swagger.responses[500] = { description: 'Error al obtener calificación.' }
    */
    try {
        const usuario = await getUsuarioActual(req);
        if (!usuario) return res.status(401).json({ status: 0, msg: 'Sesión requerida.' });
        const tutoria = await Tutoria.findByPk(req.params.tutoriaId);
        if (!tutoria) return res.status(404).json({ status: 0, msg: 'Tutoría no encontrada.' });
        if (!puedeAccederTutoria(usuario, tutoria)) {
            return res.status(403).json({ status: 0, msg: 'No tiene permiso para ver esta calificación.' });
        }
        const rating = await Calificacion.findOne({ where: { tutoriaId: req.params.tutoriaId } });
        res.json({ status: 1, data: rating });
    } catch (error) {
        console.error("Error al obtener calificación:", error);
        res.status(500).json({ status: 0, msg: 'Error al obtener calificación.' });
    }
};

module.exports = calificacionCtrl;
