const Categoria = require('../models/categoria.model');
const ProfesorCategoria = require('../models/profesorCategoria.model');
const Usuario = require('../models/usuario.model');
const Tutoria = require('../models/tutoria.model');

const categoriaCtrl = {};
const { Op, where } = require('sequelize');

const getUsuarioActual = async (req) => Usuario.findByPk(req.userId);

const puedeGestionarProfesor = (usuario, profesorId) =>
    usuario.rol === 'admin' || (usuario.rol === 'profesor' && usuario.id === Number(profesorId));

categoriaCtrl.getCategorias = async (req, res) => {
    /* #swagger.tags = ['Categorias']
       #swagger.summary = 'Listar todas las categorías'
       #swagger.description = 'Retorna la lista completa de asignaturas/categorías disponibles.'
       #swagger.responses[200] = {
         description: 'Categorías obtenidas correctamente.',
         schema: { status: 1, msg: 'success', data: [] }
       }
       #swagger.responses[500] = { description: 'Error al obtener categorías.' }
    */
    try {
        const categorias = await Categoria.findAll({
            attributes: {
                exclude: ['createdAt, updatedAt']
            }
        });
        res.json({ status: 1, msg: 'success', data: categorias });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al obtener categorías' });
    }
};


categoriaCtrl.getCategoria = async (req, res) => {
    /* #swagger.tags = ['Categorias']
       #swagger.summary = 'Obtener una categoría por ID'
       #swagger.description = 'Retorna los datos de una categoría específica.'
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID de la categoría.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Categoría encontrada.',
         schema: { $ref: '#/definitions/CategoriaResponse' }
       }
       #swagger.responses[500] = { description: 'Error al obtener categoría.' }
    */
    try {
        const categoria = await Categoria.findByPk(req.params.id);
        if (!categoria) return res.status(404).json({ status: 0, msg: 'Categoría no encontrada' });
        res.json({ status: 1, msg: 'success', data: categoria });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al obtener categoría' });
    }
};

categoriaCtrl.createCategoria = async (req, res) => {
    /* #swagger.tags = ['Categorias']
       #swagger.summary = 'Crear una categoría'
       #swagger.description = 'Crea una nueva categoría de asignatura.'
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos de la categoría a crear.',
         required: true,
         schema: { $ref: '#/definitions/CategoriaRequest' }
       }
       #swagger.responses[200] = {
         description: 'Categoría creada correctamente.',
         schema: { $ref: '#/definitions/CategoriaResponse' }
       }
       #swagger.responses[500] = { description: 'Error al crear categoría.' }
    */
    try {
        const nueva = await Categoria.create({
            nombre: req.body.nombre,
            nivel: req.body.nivel,
            descripcion: req.body.descripcion
        });
        res.json({ status: 1, msg: 'Categoría creada correctamente', data: nueva });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al crear categoría' });
    }
};

categoriaCtrl.editCategoria = async (req, res) => {
    /* #swagger.tags = ['Categorias']
       #swagger.summary = 'Actualizar una categoría'
       #swagger.description = 'Actualiza el nombre y descripción de una categoría existente.'
       #swagger.consumes = ['application/json']
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID de la categoría a actualizar.',
         required: true,
         type: 'integer'
       }
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos actualizados de la categoría.',
         required: true,
         schema: { $ref: '#/definitions/CategoriaRequest' }
       }
       #swagger.responses[200] = {
         description: 'Categoría actualizada correctamente.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[500] = { description: 'Error al actualizar categoría.' }
    */
    try {
        const cambios = {};
        for (const campo of ['nombre', 'nivel', 'descripcion']) {
            if (req.body[campo] !== undefined) cambios[campo] = req.body[campo];
        }
        await Categoria.update(cambios, { where: { id: req.params.id } });
        res.json({ status: 1, msg: 'Categoría actualizada correctamente' });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al actualizar categoría' });
    }
};

categoriaCtrl.deleteCategoria = async (req, res) => {
    /* #swagger.tags = ['Categorias']
       #swagger.summary = 'Eliminar una categoría'
       #swagger.description = 'Elimina físicamente una categoría por su ID.'
       #swagger.parameters['id'] = {
         in: 'path',
         description: 'ID de la categoría a eliminar.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Categoría eliminada correctamente.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[500] = { description: 'Error al eliminar categoría.' }
    */
    try {
        await Categoria.destroy({ where: { id: req.params.id } });
        res.json({ status: 1, msg: 'Categoría eliminada correctamente' });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al eliminar categoría' });
    }
};

categoriaCtrl.asociarProfesor = async (req, res) => {
    /* #swagger.tags = ['Categorias']
       #swagger.summary = 'Asociar profesor a categoría'
       #swagger.description = 'Establece una relación activa entre un profesor y una categoría.'
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos de la asociación.',
         required: true,
         schema: { $ref: '#/definitions/AsociarProfesorRequest' }
       }
       #swagger.responses[200] = {
         description: 'Profesor asociado correctamente.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[400] = { description: 'Profesor o categoría no válidos.' }
       #swagger.responses[500] = { description: 'Error al asociar profesor.' }
    */
    try {
        const { profesorId, categoriaId } = req.body;
        const usuario = await getUsuarioActual(req);
        if (!usuario) return res.status(401).json({ status: 0, msg: 'Sesión requerida.' });
        if (!puedeGestionarProfesor(usuario, profesorId)) {
            return res.status(403).json({ status: 0, msg: 'Solo puede asociar categorías a su propio perfil de profesor.' });
        }

        const profesor = await Usuario.findOne({ where: { id: profesorId, rol: 'profesor' } });
        const categoria = await Categoria.findByPk(categoriaId);
        if (!profesor || !categoria) return res.status(400).json({ status: 0, msg: 'El profesor o la categoría especificada no es válida.' });

        const relacion = await ProfesorCategoria.findOne({ where: { profesorId, categoriaId } });

        if (relacion && relacion.estado === 'inactivo') {
            relacion.estado = 'activo'; await relacion.save();
            return res.json({ status: 1, msg: 'Profesor asociado nuevamente a la categoría.', data: relacion });
        }

        const nuevaRelacion = await ProfesorCategoria.create({ profesorId, categoriaId, estado: 'activo' });
        return res.json({ status: 1, msg: 'Profesor asociado a la categoría.', data: nuevaRelacion });

    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al asociar profesor a la categoría' });
    }
};

categoriaCtrl.desasociarProfesor = async (req, res) => {
    /* #swagger.tags = ['Categorias']
       #swagger.summary = 'Desasociar profesor de categoría'
       #swagger.description = 'Cambia a inactivo el estado de la relación entre el profesor y la categoría.'
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Datos de la desasociación.',
         required: true,
         schema: { $ref: '#/definitions/AsociarProfesorRequest' }
       }
       #swagger.responses[200] = {
         description: 'Profesor desasociado correctamente.',
         schema: { $ref: '#/definitions/SuccessResponse' }
       }
       #swagger.responses[400] = { description: 'La asociación no existe.' }
       #swagger.responses[409] = { description: 'El profesor tiene tutorías activas en esta categoría.' }
       #swagger.responses[500] = { description: 'Error interno al desasociar.' }
    */
    try {
        const { profesorId, categoriaId } = req.body;
        const usuario = await getUsuarioActual(req);
        if (!usuario) return res.status(401).json({ status: 0, msg: 'Sesión requerida.' });
        if (!puedeGestionarProfesor(usuario, profesorId)) {
            return res.status(403).json({ status: 0, msg: 'Solo puede quitar categorías de su propio perfil de profesor.' });
        }

        const relacion = await ProfesorCategoria.findOne({ where: { profesorId, categoriaId } });
        if (!relacion) return res.status(400).json({ status: 0, msg: 'La asociación no existe.' });

        // Verificar que no tenga tutorías activas
        const tutoriaActiva = await Tutoria.findOne({
            where: {
                profesorId,
                categoriaId,
                estado: {
                    [Op.in]: ['pendiente', 'aceptada']
                }
            }
        });
        if (tutoriaActiva)
            return res.status(409).json({ status: 0, msg: 'No se puede quitar la categoría porque el profesor tiene tutorías activas en ella.' });

        relacion.estado = 'inactivo'; await relacion.save();
        res.json({ status: 1, msg: 'Profesor desasociado de la categoría' });
    } catch (error) {
        console.error("Error al desasociar profesor:", error);
        res.status(500).json({ status: 0, msg: 'Error interno al desasociar profesor' });
    }
};

categoriaCtrl.getCategoriasProfesor = async (req, res) => {
    /* #swagger.tags = ['Categorias']
       #swagger.summary = 'Obtener categorías de un profesor'
       #swagger.description = 'Retorna todas las asignaturas activas que enseña un profesor específico.'
       #swagger.parameters['profesorId'] = {
         in: 'path',
         description: 'ID del profesor.',
         required: true,
         type: 'integer'
       }
       #swagger.responses[200] = {
         description: 'Categorías del profesor obtenidas correctamente.',
         schema: { status: 1, data: [] }
       }
       #swagger.responses[500] = { description: 'Error al obtener categorías.' }
    */
    try {
        const { profesorId } = req.params;
        const categorias = await Categoria.findAll({
            attributes: {
                exclude: ['createdAt', 'updatedAt']
            },
            include: [{
                model: Usuario,
                as: 'profesores',
                where: { id: profesorId },
                attributes: [], // No necesitamos los atributos del profesor, solo filtrar
                through: {
                    where: { estado: 'activo' },
                    attributes: [] // No necesitamos los atributos de la tabla intermedia
                }
            }]
        });
        res.json({ status: 1, data: categorias });
    } catch (error) {
        res.status(500).json({ status: 0, msg: 'Error al obtener categorías del profesor' });
    }
}

module.exports = categoriaCtrl;
