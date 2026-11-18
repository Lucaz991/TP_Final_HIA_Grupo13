const { Op } = require('sequelize');
const SolicitudAyuda = require('../../models/solicitudes/solicitudAyuda.model');
const RespuestaAyuda = require('../../models/solicitudes/respuestaAyuda.model');
const Usuario = require('../../models/usuario.model');
const registrarAuditoria = require("../../helpers/auditoria.helper");
const solicitudCtrl = {};

const getUsuarioActual = async (req) => Usuario.findByPk(req.userId);

const esAdmin = (usuario) => usuario.rol === 'admin';
const esPropietario = (usuario, solicitud) => usuario.id === solicitud.usuarioId;
const puedeVerSolicitud = (usuario, solicitud) =>
    esAdmin(usuario) || esPropietario(usuario, solicitud) ||
    (usuario.rol === 'profesor' && solicitud.estado === 'ABIERTA');
const puedeGestionarSolicitud = (usuario, solicitud) =>
    esAdmin(usuario) || esPropietario(usuario, solicitud);

// Listar todas las solicitudes (GET)
solicitudCtrl.getSolicitudes = async (req, res) => {
    /* #swagger.tags = ['Solicitudes']
       #swagger.summary = 'Listar todas las solicitudes'
       #swagger.description = 'Retorna el listado completo de solicitudes de ayuda.'
       #swagger.responses[200] = {
         description: 'Listado de solicitudes obtenido correctamente.',
         schema: { $ref: '#/definitions/SolicitudAyudaResponse' }
       }
       #swagger.responses[500] = { description: 'Error interno del servidor.' }
    */
    try {
        const usuario = await getUsuarioActual(req);
        if (!usuario) return res.status(401).json({ status: 0, msg: 'Sesión requerida.' });
        const where = esAdmin(usuario) ? {} :
            usuario.rol === 'profesor' ? { [Op.or]: [{ usuarioId: usuario.id }, { estado: 'ABIERTA' }] } :
            { usuarioId: usuario.id };
        const solicitudes = await SolicitudAyuda.findAll({ where });
        res.json({ status: 1, msg: 'success', data: solicitudes });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al obtener solicitudes' });
    }
};

// Obtener una solicitud por su ID (GET)
solicitudCtrl.getSolicitud = async (req, res) => {
    /* #swagger.tags = ['Solicitudes']
       #swagger.summary = 'Obtener una solicitud por ID'
       #swagger.description = 'Retorna una solicitud de ayuda específica junto con sus respuestas.'
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID de la solicitud.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Solicitud encontrada.',
         schema: { $ref: '#/definitions/SolicitudAyudaResponse' }
       }
       #swagger.responses[404] = { description: 'Solicitud no encontrada.' }
       #swagger.responses[500] = { description: 'Error interno del servidor.' }
    */
    try {
        const solicitud = await SolicitudAyuda.findOne({
            where: { id: req.params.id },
            include: [{ model: RespuestaAyuda, as: 'respuestas' }
                
            ]
        });
        if (!solicitud) return res.status(404).json({ status: 0, msg: 'Solicitud no encontrada' });
        const usuario = await getUsuarioActual(req);
        if (!usuario || !puedeVerSolicitud(usuario, solicitud)) {
            return res.status(403).json({ status: 0, msg: 'No tiene permiso para ver esta solicitud.' });
        }

        res.json({ status: 1, msg: 'success', data: solicitud });
    } catch (error) {
        console.error(error);
        res.status(500).json({
            status: 0,
            msg: "Error al obtener solicitud"
        });
    }
};

// Crear una nueva solicitud (POST)
solicitudCtrl.createSolicitud = async (req, res) => {
    /* #swagger.tags = ['Solicitudes']
       #swagger.summary = 'Crear una solicitud de ayuda'
       #swagger.description = 'Crea una nueva solicitud de ayuda. Requiere autenticación.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos de la solicitud a crear.',
         required: true,
         schema: { $ref: '#/definitions/SolicitudAyuda' }
       }
       #swagger.responses[200] = {
         description: 'Solicitud creada correctamente.',
         schema: { $ref: '#/definitions/SolicitudAyudaResponse' }
       }
       #swagger.responses[500] = { description: 'Error al crear solicitud.' }
    */
    try {
        const usuario = await getUsuarioActual(req);
        if (!usuario) return res.status(401).json({ status: 0, msg: 'Sesión requerida.' });
        const usuarioId = Number(req.body.usuarioId || usuario.id);
        if (!esAdmin(usuario) && usuarioId !== usuario.id) {
            return res.status(403).json({ status: 0, msg: 'Solo puede crear solicitudes para su propio usuario.' });
        }
        const nueva = await SolicitudAyuda.create({
            usuarioId,
            categoriaId: req.body.categoriaId,
            titulo: req.body.titulo,
            descripcion: req.body.descripcion,
            archivoAdjunto: req.body.archivoAdjunto
        });
            await registrarAuditoria(

            req,

            "CREATE",

            "SolicitudAyuda",

            nueva.id,

            `Creó la solicitud "${nueva.titulo}"`

             );
        res.json({ status: 1, msg: 'Solicitud creada correctamente', data: nueva });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al crear solicitud' });
    }
};

// Actualizar una solicitud por su ID (PUT)
solicitudCtrl.editSolicitud = async (req, res) => {
    /* #swagger.tags = ['Solicitudes']
       #swagger.summary = 'Actualizar una solicitud'
       #swagger.description = 'Actualiza los datos de una solicitud de ayuda existente. Requiere autenticación.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.consumes = ['application/json']
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID de la solicitud a actualizar.',
         required: true,
         type: 'integer'
       }
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos actualizados de la solicitud.',
         required: true,
         schema: { $ref: '#/definitions/SolicitudAyuda' }
       }
       #swagger.responses[200] = {
         description: 'Solicitud actualizada correctamente.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[500] = { description: 'Error al actualizar solicitud.' }
    */
    try {
        const solicitud = await SolicitudAyuda.findByPk(req.params.id);
        if (!solicitud) return res.status(404).json({ status: 0, msg: 'Solicitud no encontrada.' });
        const usuario = await getUsuarioActual(req);
        if (!usuario || !puedeGestionarSolicitud(usuario, solicitud)) {
            return res.status(403).json({ status: 0, msg: 'Solo puede modificar sus propias solicitudes.' });
        }
        const cambios = {};
        for (const campo of ['titulo', 'descripcion', 'categoriaId', 'archivoAdjunto']) {
            if (req.body[campo] !== undefined) cambios[campo] = req.body[campo];
        }
        await solicitud.update(cambios);
        await registrarAuditoria(
            req,
            "UPDATE",
            "SolicitudAyuda",
            req.params.id,
            "Se actualizó la solicitud de ayuda",
            null
        );
        res.json({ status: 1, msg: 'Solicitud actualizada correctamente' });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al actualizar solicitud' });
    }
};

// Cerrar una solicitud por su ID (PUT)
solicitudCtrl.cerrarSolicitud = async (req, res) => {
    /* #swagger.tags = ['Solicitudes']
       #swagger.summary = 'Cerrar una solicitud'
       #swagger.description = 'Cambia el estado de una solicitud a CERRADA. Requiere autenticación.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID de la solicitud a cerrar.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Solicitud cerrada correctamente.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[500] = { description: 'Error al cerrar solicitud.' }
    */
    try {
        const solicitud = await SolicitudAyuda.findByPk(req.params.id);
        if (!solicitud) return res.status(404).json({ status: 0, msg: 'Solicitud no encontrada.' });
        const usuario = await getUsuarioActual(req);
        if (!usuario || !puedeGestionarSolicitud(usuario, solicitud)) {
            return res.status(403).json({ status: 0, msg: 'Solo puede cerrar sus propias solicitudes.' });
        }
        await solicitud.update({ estado: 'CERRADA' });
         await registrarAuditoria(
            req,
            "UPDATE",
            "SolicitudAyuda",
            solicitud.id,
            `Se cerró la solicitud "${solicitud.titulo}"`,
            solicitud.usuarioId
        );
        res.json({ status: 1, msg: 'Solicitud cerrada correctamente' });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al cerrar solicitud' });
    }
};

// Eliminar una solicitud por su ID (DELETE)
solicitudCtrl.deleteSolicitud = async (req, res) => {
    /* #swagger.tags = ['Solicitudes']
       #swagger.summary = 'Eliminar una solicitud'
       #swagger.description = 'Elimina una solicitud de ayuda por su ID. Requiere autenticación.'
       #swagger.security = [{ bearerAuth: [] }]
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID de la solicitud a eliminar.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Solicitud eliminada correctamente.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[500] = { description: 'Error al eliminar solicitud.' }
    */
    try {
        const solicitud = await SolicitudAyuda.findByPk(req.params.id);
        if (!solicitud) return res.status(404).json({ status: 0, msg: 'Solicitud no encontrada.' });
        const usuario = await getUsuarioActual(req);
        if (!usuario || !puedeGestionarSolicitud(usuario, solicitud)) {
            return res.status(403).json({ status: 0, msg: 'Solo puede eliminar sus propias solicitudes.' });
        }
        await solicitud.destroy();
          await registrarAuditoria(
            req,
            "DELETE",
            "SolicitudAyuda",
            req.params.id,
            `Se eliminó la solicitud "${solicitud.titulo}"`,
            solicitud.usuarioId
        );
        res.json({ status: 1, msg: 'Solicitud eliminada correctamente' });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al eliminar solicitud' });
    }
};

module.exports = solicitudCtrl;