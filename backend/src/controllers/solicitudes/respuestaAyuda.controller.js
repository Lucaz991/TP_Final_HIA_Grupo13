const RespuestaAyuda = require('./../../models/solicitudes/respuestaAyuda.model');
const SolicitudAyuda = require('./../../models/solicitudes/solicitudAyuda.model');
const Usuario = require('./../../models/usuario.model');
const registrarAuditoria = require("../../helpers/auditoria.helper");
const respuestaCtrl = {};

const getUsuarioActual = async (req) => Usuario.findByPk(req.userId);
const esAdmin = (usuario) => usuario.rol === 'admin';
const puedeVerSolicitud = (usuario, solicitud) =>
    esAdmin(usuario) || usuario.id === solicitud.usuarioId ||
    (usuario.rol === 'profesor' && solicitud.estado === 'ABIERTA');
const esAutor = (usuario, respuesta) => usuario.id === respuesta.usuarioId;

// Listar todas las respuestas por ID de solicitud (GET)
respuestaCtrl.getRespuestasBySolicitud = async (req, res) => {
    /* #swagger.tags = ['Respuestas']
       #swagger.summary = 'Listar respuestas por solicitud'
       #swagger.description = 'Retorna todas las respuestas asociadas a una solicitud de ayuda específica.'
       #swagger.parameters['solicitudId'] = {
         in: 'path',
         description: 'ID de la solicitud.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Respuestas obtenidas correctamente.',
         schema: { $ref: '#/definitions/RespuestaAyudaResponse' }
       }
       #swagger.responses[500] = { description: 'Error interno del servidor.' }
    */
    try {
        const solicitud = await SolicitudAyuda.findByPk(req.params.solicitudId);
        if (!solicitud) return res.status(404).json({ status: 0, msg: 'Solicitud no encontrada.' });
        const usuario = await getUsuarioActual(req);
        if (!usuario || !puedeVerSolicitud(usuario, solicitud)) {
            return res.status(403).json({ status: 0, msg: 'No tiene permiso para ver estas respuestas.' });
        }
        const respuestas = await RespuestaAyuda.findAll({
            where: { solicitudId: req.params.solicitudId }
        });

        res.json({ status: 1, msg: 'success', data: respuestas });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al obtener respuestas' });
    }
};

// Crear una nueva respuesta (POST)
respuestaCtrl.createRespuesta = async (req, res) => {
    /* #swagger.tags = ['Respuestas']
       #swagger.summary = 'Crear una respuesta'
       #swagger.description = 'Crea una nueva respuesta para una solicitud abierta. Requiere autenticación.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos de la respuesta a crear.',
         required: true,
         schema: { $ref: '#/definitions/RespuestaAyuda' }
       }
       #swagger.responses[200] = {
         description: 'Respuesta creada correctamente.',
         schema: { $ref: '#/definitions/RespuestaAyudaResponse' }
       }
       #swagger.responses[400] = { description: 'La solicitud ya no acepta respuestas.' }
       #swagger.responses[404] = { description: 'La solicitud no existe.' }
       #swagger.responses[500] = { description: 'Error al crear respuesta.' }
    */
    try {
        const usuario = await getUsuarioActual(req);
        if (!usuario) return res.status(401).json({ status: 0, msg: 'Sesión requerida.' });
        if (!['profesor', 'admin'].includes(usuario.rol)) {
            return res.status(403).json({ status: 0, msg: 'Solo un profesor puede responder solicitudes.' });
        }
        const usuarioId = Number(req.body.idUsuario || usuario.id);
        if (!esAdmin(usuario) && usuarioId !== usuario.id) {
            return res.status(403).json({ status: 0, msg: 'Solo puede crear respuestas con su propio usuario.' });
        }
        const solicitud = await SolicitudAyuda.findByPk(req.body.idSolicitud);

        if (!solicitud) {
            return res.status(404).json({
                status: 0,
                msg: 'La solicitud no existe.'
            });
        }

        if (solicitud.estado != 'ABIERTA') {
            return res.status(400).json({
                status: 0,
                msg: 'La solicitud ya no acepta respuestas.'
            });
        }

        const nueva = await RespuestaAyuda.create({
            solicitudId: req.body.idSolicitud,
            usuarioId,
            respuesta: req.body.respuesta,
            precio: req.body.precio,
            archivoAdjunto: req.body.archivoAdjunto
        });


        res.json({
            status: 1,
            msg: 'Respuesta creada correctamente',
            data: nueva
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({
            status: 0,
            msg: 'Error al crear respuesta'
        });
    }
};

// Actualizar una respuesta por su ID (PUT)
respuestaCtrl.editRespuesta = async (req, res) => {
    /* #swagger.tags = ['Respuestas']
       #swagger.summary = 'Actualizar una respuesta'
       #swagger.description = 'Actualiza el contenido de una respuesta existente. Requiere autenticación.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.consumes = ['application/json']
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID de la respuesta a actualizar.',
         required: true,
         type: 'integer'
       }
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos actualizados de la respuesta.',
         required: true,
         schema: { $ref: '#/definitions/RespuestaAyuda' }
       }
       #swagger.responses[200] = {
         description: 'Respuesta actualizada correctamente.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[500] = { description: 'Error al actualizar respuesta.' }
    */
    try {
        const respuesta = await RespuestaAyuda.findByPk(req.params.id);
        if (!respuesta) return res.status(404).json({ status: 0, msg: 'Respuesta no encontrada.' });
        const usuario = await getUsuarioActual(req);
        if (!usuario || (!esAdmin(usuario) && !esAutor(usuario, respuesta))) {
            return res.status(403).json({ status: 0, msg: 'Solo puede modificar sus propias respuestas.' });
        }
        const cambios = {};
        for (const campo of ['respuesta', 'precio', 'archivoAdjunto']) {
            if (req.body[campo] !== undefined) cambios[campo] = req.body[campo];
        }
        await respuesta.update(cambios);

        res.json({
            status: 1,
            msg: 'Respuesta actualizada correctamente'
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({
            status: 0,
            msg: 'Error al actualizar respuesta'
        });
    }
};

// Aceptar una respuesta por su ID (PUT)
respuestaCtrl.aceptarRespuesta = async (req, res) => {
    /* #swagger.tags = ['Respuestas']
       #swagger.summary = 'Aceptar una respuesta'
       #swagger.description = 'Marca una respuesta como ACEPTADA y cierra la solicitud como RESUELTA. Requiere autenticación.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID de la respuesta a aceptar.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Respuesta aceptada.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[404] = { description: 'Respuesta no encontrada.' }
       #swagger.responses[500] = { description: 'Error al aceptar la respuesta.' }
    */
    try {
        const respuesta = await RespuestaAyuda.findByPk(req.params.id);

        if (!respuesta) {
            return res.status(404).json({
                status: 0,
                msg: 'Respuesta no encontrada.'
            });
        }
        const solicitud = await SolicitudAyuda.findByPk(respuesta.solicitudId);
        if (!solicitud) {
            return res.status(404).json({ status: 0, msg: 'Solicitud no encontrada.' });
        }
        const usuario = await getUsuarioActual(req);
        if (!usuario || (!esAdmin(usuario) && usuario.id !== solicitud.usuarioId)) {
            return res.status(403).json({ status: 0, msg: 'Solo el autor de la solicitud puede aceptar respuestas.' });
        }

        await respuesta.update({
            estado: 'ACEPTADA'
        });
        await registrarAuditoria(
            req,
            "UPDATE",
            "RespuestaAyuda",
            respuesta.id,
            "Se aceptó una respuesta de ayuda.",
            respuesta.usuarioId
        );

        await SolicitudAyuda.update({
            estado: 'RESUELTA'
        }, {
            where: {
                id: respuesta.solicitudId
            }
        });
        await registrarAuditoria(
            req,
            "UPDATE",
            "RespuestaAyuda",
            respuesta.id,
            "Se aceptó una respuesta de ayuda.",
            respuesta.usuarioId
        );

        res.json({
            status: 1,
            msg: 'Respuesta aceptada.'
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({
            status: 0,
            msg: 'Error al aceptar la respuesta.'
        });
    }
};

// Eliminar una respuesta por su ID (DELETE)
respuestaCtrl.deleteRespuesta = async (req, res) => {
    /* #swagger.tags = ['Respuestas']
       #swagger.summary = 'Eliminar una respuesta'
       #swagger.description = 'Elimina una respuesta por su ID. Requiere autenticación.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID de la respuesta a eliminar.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Respuesta eliminada correctamente.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[500] = { description: 'Error al eliminar respuesta.' }
    */
    try {
        const respuesta = await RespuestaAyuda.findByPk(req.params.id);
        if (!respuesta) return res.status(404).json({ status: 0, msg: 'Respuesta no encontrada.' });
        const usuario = await getUsuarioActual(req);
        if (!usuario || (!esAdmin(usuario) && !esAutor(usuario, respuesta))) {
            return res.status(403).json({ status: 0, msg: 'Solo puede eliminar sus propias respuestas.' });
        }
        await respuesta.destroy();
                await registrarAuditoria(
            req,
            "DELETE",
            "RespuestaAyuda",
            req.params.id,
            "Se eliminó una respuesta de ayuda.",
            respuesta.usuarioId
        );

        res.json({
            status: 1,
            msg: 'Respuesta eliminada correctamente'
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({
            status: 0,
            msg: 'Error al eliminar respuesta'
        });
    }
};

module.exports = respuestaCtrl;