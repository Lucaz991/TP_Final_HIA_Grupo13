-- PT-24 - Ocho consultas originales reconstruidas desde Sequelize.
-- Son equivalentes funcionales de las consultas de los controladores,
-- con alias explícitos para identificar las asociaciones.
-- El SQL literal emitido por Sequelize puede incluir alias o PK adicionales.
-- Conservar esta versión como línea base antes de crear índices candidatos.
--
-- PREPARACIÓN
-- 1. Ejecutar todos los lotes de 00_preparar_calificaciones.sql antes de
--    medir. Predeterminado: tres lotes de 200000 calificaciones.
-- 2. Guardar nuevamente el inventario de índices y estadísticas de diagnóstico.
-- 3. IDs confirmados en esta instalación el 10/11/2026.
--    Profesor principal (mañana): 10001, profesor.1@example.com.
--    Profesor de tarde: 50005, profesor.20001@example.com.
--    Profesor de noche: 115011, profesor.55001@example.com.
--    Alumno: 1, alumno.1@example.com. Categoría principal: 1.
-- 4. Q01 a Q05 ya utilizan esos parámetros. Verificar la consulta auxiliar
--    si se reproduce en otra instalación. Conservar los mismos IDs en
--    02_mediciones_iniciales.sql y en las mediciones posteriores.
-- 5. Q06 conserva el filtro del año actual y la zona de la sesión.
--    Guardar ambas condiciones y comparar dentro del mismo año y zona.
-- 6. Ejecutar cada consulta por separado. Q07 y Q08 devuelven millones de
--    filas: medir mediante EXPLAIN ANALYZE en el próximo script para evitar
--    transferir todos los resultados a pgAdmin.
-- Este archivo documenta consultas. No es un lote para ejecutar completo.

-- AUXILIAR: elegir un profesor de cada turno y un alumno.
SELECT
    u.id AS usuario_id,
    u.email,
    u.rol,
    pc."categoriaId" AS categoria_id
FROM public.usuarios u
LEFT JOIN public.profesores_categorias pc ON pc."profesorId" = u.id
WHERE u.email IN (
    'profesor.1@example.com',
    'profesor.20001@example.com',
    'profesor.55001@example.com',
    'alumno.1@example.com'
)
ORDER BY u.email, pc."categoriaId";

-- AUXILIAR: registrar el contexto temporal de Q06.
SELECT current_setting('TimeZone') AS zona_horaria,
       EXTRACT(YEAR FROM NOW())::integer AS anio_consultado;

-- Q01. Tutorías finalizadas de un profesor, con calificación y alumno.
-- Origen: usuario.controller.js, getUsuarios, consulta dentro del bucle.
-- El controlador repite esta búsqueda por profesor (patrón N+1).
-- El plan individual no mide el costo total de ese bucle ni la serialización.
-- Parámetro principal: profesor 10001. Otros casos: 50005 y 115011.
SELECT
    t.*,
    c.id AS calificacion_id,
    c.calificacion,
    c.comentario,
    c."createdAt" AS calificacion_creada,
    c."updatedAt" AS calificacion_actualizada,
    c."tutoriaId" AS calificacion_tutoria_id,
    alumno.nombre AS alumno_nombre,
    alumno.apellido AS alumno_apellido
FROM public.tutorias t
LEFT JOIN public.calificaciones c ON c."tutoriaId" = t.id
LEFT JOIN public.usuarios alumno ON alumno.id = t."alumnoId"
WHERE t."profesorId" = 10001
  AND t.estado = 'finalizada';

-- Q02. Dependencias de un usuario antes de permitir su eliminación.
-- Origen: admin.controller.js, deleteUser.
-- La operación de este archivo es únicamente un SELECT.
-- Parámetro principal: alumno 1. Mantener el mismo ID a ambos lados del OR.
SELECT COUNT(*) AS tutorias_asociadas
FROM public.tutorias
WHERE "alumnoId" = 1 OR "profesorId" = 1;

-- Q03. Dependencias de una categoría antes de permitir su eliminación.
-- Origen: admin.controller.js, deleteCategory.
-- Parámetro principal: categoría 1, asociada al profesor principal.
SELECT COUNT(*) AS tutorias_categoria
FROM public.tutorias
WHERE "categoriaId" = 1;

-- Q04. Tutoría activa que impide desasociar profesor y categoría.
-- Origen: categoria.controller.js, desasociarProfesor.
-- Parámetros principales: profesor 10001 y categoría 1, par confirmado.
-- No tiene ORDER BY en el original. La aplicación comprueba existencia,
-- por lo que la equivalencia posterior debe comparar existencia, no un ID fijo.
SELECT t.*
FROM public.tutorias t
WHERE t."profesorId" = 10001
  AND t."categoriaId" = 1
  AND t.estado IN ('pendiente', 'aceptada')
LIMIT 1;

-- Q05. Disponibilidad activa de un profesor.
-- Origen: horarioDisponible.controller.js, getHorariosProfesor.
-- Parámetro principal: profesor 10001.
SELECT h.*
FROM public.horarios_disponibles h
WHERE h."profesorId" = 10001
  AND h.estado = 'activo';

-- Q06. Gráfico mensual del año actual.
-- Origen: admin.controller.js, getTutorialsByMonth.
-- Conservar EXTRACT sobre la columna para medir la versión original.
-- La posible reescritura por rango debe conservar createdAt y la zona horaria.
SELECT
    TO_CHAR("createdAt", 'MM') AS month,
    COUNT(id) AS count
FROM public.tutorias
WHERE EXTRACT(YEAR FROM "createdAt") = EXTRACT(YEAR FROM NOW())
GROUP BY TO_CHAR("createdAt", 'MM')
ORDER BY TO_CHAR("createdAt", 'MM') ASC;

-- Q07. Listado administrativo completo con asociaciones y ordenamiento.
-- Origen: admin.controller.js, getFullTutorials.
-- El original no incluye LIMIT. Agregar paginación cambia el alcance funcional
-- y requiere una evaluación separada del cambio de índices.
SELECT
    t.id, t.modalidad, t."precioAcordado", t."fechaHora",
    t.estado, t."enlaceMeet", t.pagada, t."createdAt",
    alumno.id AS alumno_id,
    alumno.nombre AS alumno_nombre,
    alumno.apellido AS alumno_apellido,
    alumno.email AS alumno_email,
    profesor.id AS profesor_id,
    profesor.nombre AS profesor_nombre,
    profesor.apellido AS profesor_apellido,
    profesor.email AS profesor_email,
    categoria.id AS categoria_id,
    categoria.nombre AS categoria_nombre,
    calificacion.id AS calificacion_id,
    calificacion.calificacion,
    calificacion.comentario
FROM public.tutorias t
LEFT JOIN public.usuarios alumno ON alumno.id = t."alumnoId"
LEFT JOIN public.usuarios profesor ON profesor.id = t."profesorId"
LEFT JOIN public.categorias categoria ON categoria.id = t."categoriaId"
LEFT JOIN public.calificaciones calificacion
    ON calificacion."tutoriaId" = t.id
ORDER BY t."createdAt" DESC;

-- Q08. Profesores con categorías y horarios (consulta inicial de la galería).
-- Origen: usuario.controller.js, getUsuarios con ?rol=profesor.
-- Se mantienen los atributos que el controlador selecciona actualmente.
-- Medir el plan sin exportar todas las filas, que incluyen hashes de prueba.
-- La relación de cuatro categorías y cuatro horarios produce hasta 16 filas
-- por profesor. Sequelize reconstruye las colecciones en la aplicación.
-- La medición completa de la galería debe incluir también el N+1 de Q01.
SELECT
    u.id, u.rol, u.nombre, u.apellido, u.email, u."contraseniaHash",
    u.genero, u.estado, u."proveedorAuth", u.foto,
    u.ubicacion, u.lat, u.lng, u.universidad, u.carrera,
    categoria.id AS categoria_id,
    categoria.nombre AS categoria_nombre,
    horario.id AS horario_id,
    horario."diaSemana", horario."horaInicio", horario."horaFin",
    horario.modalidad AS horario_modalidad,
    horario.estado AS horario_estado,
    horario."profesorId" AS horario_profesor_id
FROM public.usuarios u
LEFT JOIN (
    public.profesores_categorias pc
    INNER JOIN public.categorias categoria ON categoria.id = pc."categoriaId"
) ON pc."profesorId" = u.id
LEFT JOIN public.horarios_disponibles horario ON horario."profesorId" = u.id
WHERE u.rol = 'profesor';
