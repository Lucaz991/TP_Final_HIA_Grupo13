const { Op } = require('sequelize');
const Tutoria = require('../models/tutoria.model');
const Usuario = require('../models/usuario.model');
const Categoria = require('../models/categoria.model'); 
const Calificacion = require('../models/calificacion.model');
const registrarAuditoria = require("../helpers/auditoria.helper");
const googleCalendarService = require('../services/google-calendar.service');
const sanitizeHtml = require('sanitize-html');

const tutoriaCtrl = {};
const solicitudCtrl = {};

solicitudCtrl.createSolicitud = async (req, res) => {
    try {
        const data = req.body;

        const textoOriginal = data.mensaje || ""; 
        
        // sanitizeHtml se encarga de borrar cualquier etiqueta <script>, <iframe> o HTML peligroso
        const mensajeSeguro = sanitizeHtml(textoOriginal);

        // Guardamos en la base de datos usando la versión LIMPIA
        const nuevaSolicitud = await Tutoria.create({
            usuarioId: data.usuarioId,
            profesorId: data.profesorId,
            categoriaId: data.categoriaId,
            fechaHora: data.fechaHora,
            modalidad: data.modalidad,
            precio: data.precio,

            mensaje: mensajeSeguro 
        });

        return res.status(201).json({ 
            status: 1, 
            msg: "Solicitud registrada correctamente", 
            data: nuevaSolicitud 
        });

    } catch (error) {
        console.log("Error al crear solicitud:", error);
        return res.status(500).json({ status: 0, msg: "Error interno del servidor" });
    }
}

module.exports = solicitudCtrl;

tutoriaCtrl.getTutorias = async (req, res) => {
    /* #swagger.tags = ['Tutorias']
       #swagger.summary = 'Listar una página de tutorías del usuario autenticado'
       #swagger.description = 'Obtiene hasta 100 tutorías del usuario autenticado, incluyendo información del alumno, profesor, categoría y calificación.'
       #swagger.responses[200] = {
           description: 'Listado obtenido con éxito.',
           schema: { $ref: '#/definitions/TutoriaResponse' }
       }
       #swagger.responses[500] = { description: 'Error del servidor.' }
    */
    const page = Number(req.query.page || 1), limit = Number(req.query.limit || 50);
    if (!Number.isSafeInteger(page) || page < 1 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100
        || !Number.isSafeInteger((page - 1) * limit)) {
        return res.status(400).json({ status: 0, msg: 'Paginación inválida.' });
    }
    if (!req.userId) return res.status(401).json({ status: 0, msg: 'Sesión requerida.' });
    try {
        // Filtrar por el usuario del JWT antes de consultar; nunca descargar el dataset global.
        const where = { [Op.or]: [{ alumnoId: req.userId }, { profesorId: req.userId }] };
        const total = await Tutoria.count({ where });
        const tutorias = await Tutoria.findAll({ where, limit, offset: (page - 1) * limit, subQuery: true,
            order: [['createdAt', 'DESC'], ['id', 'DESC']],
            include: [
                { model: Usuario, as: 'alumno', attributes: ['id', 'nombre', 'apellido', 'email'] },
                { model: Usuario, as: 'profesor', attributes: ['id', 'nombre', 'apellido', 'email'] },
                { model: Categoria, as: 'categoria', attributes: ['id', 'nombre'] },
                { model: Calificacion, as: 'calificacion' }
            ]
        });
        res.json({ status: 1, msg: 'success', data: tutorias,
            pagination: { page, limit, total, totalPages: Math.ceil(total / limit) } });
    } catch (error) {
        console.error(error);
        res.status(500).json({ status: 0, msg: 'Error al obtener tutorías' });
    }
};

tutoriaCtrl.getTutoria = async (req, res) => {
    /* #swagger.tags = ['Tutorias']
       #swagger.summary = 'Obtener una tutoría por ID'
       #swagger.description = 'Busca y retorna los detalles de una tutoría en particular mediante su ID.'
       #swagger.parameters['id'] = {
           in: 'path',
           description: 'ID de la tutoría a buscar',
           required: true,
           type: 'integer'
       }
       #swagger.responses[200] = {
           description: 'Tutoría encontrada.',
           schema: { $ref: '#/definitions/TutoriaResponse' }
       }
       #swagger.responses[404] = { description: 'Tutoría no encontrada.' }
       #swagger.responses[500] = { description: 'Error del servidor.' }
    */
    try {
        const tutoria = await Tutoria.findOne({
            where: { id: req.params.id },
            include: [
                { model: Usuario, as: 'alumno', attributes: ['id', 'nombre', 'apellido', 'email'] },
                { model: Usuario, as: 'profesor', attributes: ['id', 'nombre', 'apellido', 'email'] },
                { model: Categoria, as: 'categoria', attributes: ['id', 'nombre'] },
                { model: Calificacion, as: 'calificacion' }
            ]
        });
        if (!tutoria) return res.json({ status: 0, msg: 'Tutoría no encontrada' });
        res.json({ status: 1, msg: 'success', data: tutoria });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al obtener tutoría' });
    }
};

tutoriaCtrl.createTutoria = async (req, res) => {
    /* #swagger.tags = ['Tutorias']
       #swagger.summary = 'Crear una nueva tutoría'
       #swagger.description = 'Crea una nueva tutoría asignando un alumno y un profesor, definiendo la categoría, modalidad y precio.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
           in: 'body',
           description: 'Datos necesarios para la tutoría.',
           required: true,
           schema: { $ref: '#/definitions/TutoriaRequest' }
       }
       #swagger.responses[200] = {
           description: 'Tutoría creada correctamente.',
           schema: { $ref: '#/definitions/TutoriaResponse' }
       }
       #swagger.responses[400] = { description: 'El alumno o profesor es inválido.' }
       #swagger.responses[500] = { description: 'Error del servidor.' }
    */
    try {
        const alumno = await Usuario.findOne({ where: { id: req.body.alumnoId, rol: 'alumno' } });
        const profesor = await Usuario.findOne({ where: { id: req.body.profesorId, rol: 'profesor' } });

        if (!alumno || !profesor) {
            return res.status(400).json({ status: 0, msg: 'El alumno o el profesor especificado no es válido para esta tutoría.' });
        }

        const nueva = await Tutoria.create({
            alumnoId: req.body.alumnoId,
            profesorId: req.body.profesorId,
            categoriaId: req.body.categoriaId,
            modalidad: req.body.modalidad,
            precioAcordado: req.body.precioAcordado,
            mensaje: req.body.mensaje,
            fechaHora: req.body.fechaHora,
            estado: req.body.estado || 'pendiente'
        });
        await registrarAuditoria(
                req,
                "CREATE",
                "Tutoria",
                nueva.id,
                `El alumno ${alumno.nombre} ${alumno.apellido} solicitó una tutoría con ${profesor.nombre} ${profesor.apellido}`,
                alumno.id
            );
        res.json({ status: 1, msg: 'Tutoría creada correctamente', data: nueva });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al crear tutoría' });
    }
};

tutoriaCtrl.editTutoria = async (req, res) => {
    /* #swagger.tags = ['Tutorias']
       #swagger.summary = 'Actualizar o cambiar estado de una tutoría'
       #swagger.description = 'Permite modificar los datos de una tutoría (incluyendo estado). Si el estado cambia a "aceptada", se generará automáticamente un evento y un enlace de Google Meet si corresponde.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.consumes = ['application/json']
       #swagger.parameters['id'] = {
           in: 'path',
           description: 'ID de la tutoría a actualizar',
           required: true,
           type: 'integer'
       }
       #swagger.parameters['body'] = {
           in: 'body',
           description: 'Datos de la tutoría a actualizar.',
           required: true,
           schema: { $ref: '#/definitions/TutoriaRequest' }
       }
       #swagger.responses[200] = {
           description: 'Tutoría actualizada correctamente.',
           schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[404] = { description: 'Tutoría no encontrada.' }
       #swagger.responses[500] = { description: 'Error del servidor.' }
    */
    try {
        const tutoriaExistente = await Tutoria.findByPk(req.params.id);
        if (!tutoriaExistente) {
            return res.status(404).json({ status: 0, msg: 'Tutoría no encontrada.' });
        }

        const alumno = await Usuario.findOne({ where: { id: req.body.alumnoId || tutoriaExistente.alumnoId, rol: 'alumno' } });
        const profesor = await Usuario.findOne({ where: { id: req.body.profesorId || tutoriaExistente.profesorId, rol: 'profesor' } });
        const categoria = await Categoria.findOne({ where: { id: req.body.categoriaId || tutoriaExistente.categoriaId } });

        if (!alumno || !profesor) {
            return res.status(400).json({ status: 0, msg: 'El alumno o el profesor especificado no es válido.' });
        }

        const modalidad = req.body.modalidad || tutoriaExistente.modalidad;
        const precioAcordado = req.body.precioAcordado || tutoriaExistente.precioAcordado;
        const mensaje = req.body.mensaje !== undefined ? req.body.mensaje : tutoriaExistente.mensaje;
        const fechaHora = req.body.fechaHora || tutoriaExistente.fechaHora;

        let enlaceMeet = req.body.enlaceMeet || tutoriaExistente.enlaceMeet || null;
        let eventId = req.body.googleEventId || tutoriaExistente.googleEventId || null;

        if (req.body.estado === 'aceptada') {
            try {
                const googleData = await googleCalendarService.agendarTutoria(
                    {
                        id: req.params.id,
                        fechaHora: fechaHora,
                        categoria: categoria.nombre,
                        modalidad: modalidad,
                        mensaje: mensaje
                    },
                    alumno,
                    profesor
                );
                enlaceMeet = googleData.linkMeet || null;
                eventId = googleData.idEvento;
                    await registrarAuditoria(
                    req,
                    "CREATE",
                    "GoogleCalendar",
                    req.params.id,
                    "Se creó el evento de Google Calendar y el enlace Meet.",
                    profesor.id
                  );
            } catch (googleError) {
                console.error("Error en Google Calendar (usando fallback de simulación):", googleError);
                enlaceMeet = modalidad === 'virtual' ? "https://meet.google.com/abc-defg-hij" : null;
                eventId = "simulated-event-id";
            }
        }

        await Tutoria.update({
            alumnoId: req.body.alumnoId || tutoriaExistente.alumnoId,
            profesorId: req.body.profesorId || tutoriaExistente.profesorId,
            categoriaId: req.body.categoriaId || tutoriaExistente.categoriaId,
            modalidad: modalidad,
            precioAcordado: precioAcordado,
            mensaje: mensaje,
            fechaHora: fechaHora,
            estado: req.body.estado,
            enlaceMeet: enlaceMeet,
            googleEventId: eventId
        }, { where: { id: req.params.id } });
            let descripcion = "Actualizó una tutoría";

            switch(req.body.estado){

                case "aceptada":
                    descripcion =
                    `El profesor ${profesor.nombre} ${profesor.apellido} aceptó la tutoría`;
                    break;

                case "rechazada":
                    descripcion =
                    `El profesor ${profesor.nombre} ${profesor.apellido} rechazó la tutoría`;
                    break;

                case "finalizada":
                    descripcion =
                    `La tutoría fue marcada como finalizada`;
                    break;

            }
            await registrarAuditoria(
                req,
                "UPDATE",
                "Tutoria",
                req.params.id,
                descripcion,
                profesor.id
            );


        res.json({ status: 1, msg: 'Tutoría actualizada correctamente', enlaceMeet: enlaceMeet });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al actualizar tutoría' });
    }
};

tutoriaCtrl.deleteTutoria = async (req, res) => {
    /* #swagger.tags = ['Tutorias']
       #swagger.summary = 'Eliminar una tutoría'
       #swagger.description = 'Elimina una tutoría por su ID. Falla si tiene registros dependientes a menos que se hayan eliminado previamente.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.parameters['id'] = {
           in: 'path',
           description: 'ID de la tutoría a eliminar.',
           required: true,
           type: 'integer'
       }
       #swagger.responses[200] = {
           description: 'Tutoría eliminada correctamente.',
           schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[500] = { description: 'Error del servidor.' }
    */
    try {
        await Tutoria.destroy({ where: { id: req.params.id } });
        await registrarAuditoria(
            req,
            "DELETE",
            "Tutoria",
            req.params.id,
            "Se eliminó la tutoría",
            null
        );
        res.json({ status: 1, msg: 'Tutoría eliminada correctamente' });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al eliminar tutoría' });
    }
};

module.exports = tutoriaCtrl;