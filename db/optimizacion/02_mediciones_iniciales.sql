-- PT-24 - Medición inicial de las ocho consultas originales.
-- Ejecutar manualmente en tpFinal con Auto-commit y el backend detenido.
-- Conservar dataset, servidor, zona horaria y parámetros entre antes/después.
-- Requiere 600000 calificaciones cargadas y estadísticas actualizadas.
-- Este archivo no crea índices ni cambia parámetros de configuración.
--
-- ORDEN
-- A. Ejecutar las comprobaciones de contexto y parámetros siguientes.
-- B. Seleccionar SOLO el bloque EXPLAIN de la consulta a medir.
-- C. Desde Q03 hasta Q08 ejecutar ese bloque tres veces consecutivas,
--    sin calentamiento adicional. Registrar los tres planes en el README.
-- D. Q01 y Q02 ya tienen cinco mediciones iniciales registradas;
--    conservar cinco repeticiones en su comparación posterior.
-- E. Registrar Planning Time, Execution Time, filas, loops, buffers,
--    temporales y tipo de recorrido. Comparar medianas y rangos según
--    la cantidad de muestras de cada consulta. No es obligatorio guardar CSV.
-- Q07 y Q08 conservan los listados completos. El servidor los ejecuta,
-- pero EXPLAIN devuelve el plan en vez de transferir todas sus filas.
-- Su ejecución puede tardar y utilizar espacio temporal.
-- TIMING OFF desactiva tiempos individuales por nodo, conservando
-- Execution Time global, cantidades reales de filas y buffers.
-- Guardar la misma opción en las mediciones posteriores.
-- Si se cancela una medición, registrarla como cancelada y no como un
-- tiempo completo. Interrumpir el resto hasta revisar la causa.

-- CONTEXTO: verificar destino_correcto y es_lider en true.
SELECT
    clock_timestamp() AS fecha_medicion,
    current_database() AS base,
    current_database() = 'tpFinal' AS destino_correcto,
    NOT pg_is_in_recovery() AS es_lider,
    inet_server_addr() AS servidor,
    current_setting('server_version') AS version_postgresql,
    current_setting('TimeZone') AS zona_horaria,
    EXTRACT(YEAR FROM NOW())::integer AS anio_q06,
    current_setting('work_mem') AS work_mem,
    current_setting('shared_buffers') AS shared_buffers,
    current_setting('max_parallel_workers_per_gather') AS paralelismo,
    current_setting('jit') AS jit;

-- PARÁMETROS: las cuatro filas deben mostrar coincide = true.
SELECT
    esperado.id AS usuario_id,
    esperado.email AS email_esperado,
    esperado.rol AS rol_esperado,
    u.id IS NOT NULL AND u.email = esperado.email
        AND u.rol::text = esperado.rol AS coincide
FROM (
    VALUES
        (1, 'alumno.1@example.com', 'alumno'),
        (10001, 'profesor.1@example.com', 'profesor'),
        (50005, 'profesor.20001@example.com', 'profesor'),
        (115011, 'profesor.55001@example.com', 'profesor')
) AS esperado(id, email, rol)
LEFT JOIN public.usuarios u ON u.id = esperado.id;

-- La asociación principal también debe existir y estar activa.
SELECT EXISTS (
    SELECT 1 FROM public.profesores_categorias
    WHERE "profesorId" = 10001 AND "categoriaId" = 1 AND estado = 'activo'
) AS asociacion_principal_valida;

-- Comprobar 600000 calificaciones y conservar la distribución observada.
SELECT calificacion, COUNT(*) AS cantidad
FROM public.calificaciones
GROUP BY calificacion
ORDER BY calificacion;

-- Q01. Tutorías finalizadas de un profesor, con calificación y alumno.
-- Origen: usuario.controller.js, getUsuarios, consulta dentro del bucle.
-- El controlador repite esta búsqueda por profesor (patrón N+1).
-- El plan individual no mide el costo total de ese bucle ni la serialización.
-- Parámetro principal: profesor 10001. Otros casos: 50005 y 115011.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
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
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT COUNT(*) AS tutorias_asociadas
FROM public.tutorias
WHERE "alumnoId" = 1 OR "profesorId" = 1;

-- Q03. Dependencias de una categoría antes de permitir su eliminación.
-- Origen: admin.controller.js, deleteCategory.
-- Parámetro principal: categoría 1, asociada al profesor principal.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT COUNT(*) AS tutorias_categoria
FROM public.tutorias
WHERE "categoriaId" = 1;

-- Q04. Tutoría activa que impide desasociar profesor y categoría.
-- Origen: categoria.controller.js, desasociarProfesor.
-- Parámetros principales: profesor 10001 y categoría 1, par confirmado.
-- No tiene ORDER BY en el original. La aplicación comprueba existencia,
-- por lo que la equivalencia posterior debe comparar existencia, no un ID fijo.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT t.*
FROM public.tutorias t
WHERE t."profesorId" = 10001
  AND t."categoriaId" = 1
  AND t.estado IN ('pendiente', 'aceptada')
LIMIT 1;

-- Q05. Disponibilidad activa de un profesor.
-- Origen: horarioDisponible.controller.js, getHorariosProfesor.
-- Parámetro principal: profesor 10001.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT h.*
FROM public.horarios_disponibles h
WHERE h."profesorId" = 10001
  AND h.estado = 'activo';

-- Q06. Gráfico mensual del año actual.
-- Origen: admin.controller.js, getTutorialsByMonth.
-- Conservar EXTRACT sobre la columna para medir la versión original.
-- La posible reescritura por rango debe conservar createdAt y la zona horaria.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
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
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
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
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
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

