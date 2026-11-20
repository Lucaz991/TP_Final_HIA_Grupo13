const { Op } = require('sequelize');
const Usuario = require('../models/usuario.model');
const Categoria = require('../models/categoria.model');
// const SolicitudAyuda = require('../models/solicitudes/solicitudAyuda.model');
// const RespuestaAyuda = require('../models/solicitudes/respuestaAyuda.model');
const Tutoria = require('../models/tutoria.model');
const Calificacion = require('../models/calificacion.model');
const HorarioDisponible = require('../models/horarioDisponible.model');
const Precio = require('../models/precio.model');

const contextService = {};

contextService.buildContext = async (userMessage = '', userId = null) => {

    const msg = (userMessage || '').toLowerCase();

    // categorías siempre
    const categorias = await Categoria.findAll({
        attributes: ['id', 'nombre', 'nivel', 'descripcion']
    });

    // precios siempre
    const precios = await Precio.findAll({
        attributes: ['id', 'nivel', 'modalidad', 'precio']
    });

    let profesores = [];
    // let solicitudesAbiertas = [];
    let tutorias = [];
    let calificaciones = [];

    // profesores solo si la pregunta es sobre ellos
    const keywords_profesores = ['profesor', 'tutor', 'enseña', 'dicta', 'horario', 'disponible', 'quién', 'quien', 'docente', 'maestro', 'catedrático', 'instructor', 'mentor', 'guía', 'profe'];
    if (keywords_profesores.some(k => msg.includes(k))) {
        profesores = await Usuario.findAll({
            where: { rol: 'profesor', estado: 'activo' },
            limit: 50,
            attributes: ['id', 'nombre', 'apellido', 'ubicacion', 'universidad', 'carrera'],
            include: [
                {
                    model: Categoria,
                    as: 'categoriasEnseniadas',
                    attributes: ['id', 'nombre', 'nivel'],
                    through: { attributes: ['estado'] }
                },
                {
                    model: HorarioDisponible,
                    as: 'horarios',
                    attributes: ['diaSemana', 'horaInicio', 'horaFin', 'modalidad'],
                    where: { estado: 'activo' },
                    required: false
                }
            ],
        });
    }

    // // solicitudes solo si la pregunta es sobre ayuda o solicitudes
    // const keywords_solicitudes = ['solicitud', 'ayuda', 'pregunta', 'duda', 'consulta', 'abierta', 'problema', 'tarea', 'proyecto', 'ensayo', 'examen', 'prueba', 'trabajo', 'investigación', 'tema'];
    // if (keywords_solicitudes.some(k => msg.includes(k))) {
    //     solicitudesAbiertas = await SolicitudAyuda.findAll({
    //         where: { estado: ['ABIERTA', 'RESUELTA'] },
    //         attributes: ['id', 'titulo', 'descripcion', 'estado', 'fecha_creacion'],
    //         include: [{
    //             model: RespuestaAyuda,
    //             as: 'respuestas',
    //             attributes: ['id', 'respuesta', 'precio', 'estado'],
    //         }],
    //     });
    // }

    // tutorías solo si la pregunta es sobre tutorías o clases,
    // y solo las del usuario autenticado: el chatbot no puede
    // devolver tutorías ajenas si la API tampoco lo permite
    const keywords_tutorias = ['tutoria', 'tutoría', 'clase', 'sesion', 'sesión', 'reserva', 'agendar'];
    if (userId && keywords_tutorias.some(k => msg.includes(k))) {
        tutorias = await Tutoria.findAll({
            where: { [Op.or]: [{ alumnoId: userId }, { profesorId: userId }] },
            attributes: ['id', 'modalidad', 'precioAcordado', 'fechaHora', 'estado'],
            include: [
                { model: Usuario, as: 'alumno', attributes: ['nombre', 'apellido'] },
                { model: Usuario, as: 'profesor', attributes: ['nombre', 'apellido'] },
                { model: Categoria, as: 'categoria', attributes: ['nombre', 'nivel'] }
            ],
            limit: 10
        });
    }

    // calificaciones solo si pregunta por reputación o calidad
    const keywords_calificaciones = ['calificacion', 'calificación', 'reputacion', 'reputación', 'mejor', 'recomendado', 'rating', 'puntaje'];
    if (keywords_calificaciones.some(k => msg.includes(k))) {
        // sin 'comentario': es texto libre de usuarios y podría
        // inyectar instrucciones dentro del system prompt
        calificaciones = await Calificacion.findAll({
            attributes: ['tutoriaId', 'calificacion'],
            include: [{
                model: Tutoria,
                as: 'tutoria',
                attributes: ['profesorId', 'categoriaId']
            }],
            limit: 20
        });
    }

    // armar el prompt solo con lo que encontramos
    let contexto = `Sos un asistente virtual de una plataforma de tutorías académicas universitarias.
Respondé siempre en español, de forma amable y concisa.
No uses markdown ni símbolos de formato como asteriscos, guiones o saltos de línea innecesarios.
Solo respondé preguntas relacionadas con la plataforma.
Si te preguntan algo que no está en el contexto respondé: "No tengo esa información disponible.".
Respondé en máximo 3 oraciones.

CONTEXTO ACTUAL:

CATEGORÍAS DISPONIBLES (${categorias.length}):
${JSON.stringify(categorias)}

PRECIOS DE REFERENCIA (${precios.length}):
${JSON.stringify(precios)}
`;

    if (profesores.length > 0) {
        contexto += `\nPROFESORES ACTIVOS (${profesores.length}):\n${JSON.stringify(profesores)}\n`;
    }

    // if (solicitudesAbiertas.length > 0) {
    //     contexto += `\nSOLICITUDES ABIERTAS (${solicitudesAbiertas.length}):\n${JSON.stringify(solicitudesAbiertas)}\n`;
    // }

    if (tutorias.length > 0) {
        contexto += `\nTUTORÍAS (${tutorias.length}):\n${JSON.stringify(tutorias)}\n`;
    }

    if (calificaciones.length > 0) {
        contexto += `\nCALIFICACIONES (${calificaciones.length}):\n${JSON.stringify(calificaciones)}\n`;
    }

    return contexto;
};

module.exports = contextService;