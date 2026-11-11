-- PT-24. Consultas finales: índices definitivos, rango anual y Q07 paginada.
-- Ejecutar manualmente, una consulta por vez, después de 03_indices.sql.
-- Mantener work_mem original (observado: 4MB), zona, año, servidor y dataset.
-- Q01..Q08: tres repeticiones registradas, sin calentamiento adicional.
-- No cambiar configuración para estos bloques. No transferir resultados crudos.
-- Registrar planes, Planning/Execution Time, filas, buffers y temporales.
-- Q01..Q05/Q08 conservan el SQL original. Q07 usa paginación de 100 tutorías.
-- Q06 cambia solo el filtro por un rango con límites en la zona de sesión.
-- Validar Q06 y la página Q07 con 05_validaciones.sql.

SELECT current_database(), inet_server_addr(),
       current_setting('TimeZone') AS zona_horaria,
       EXTRACT(YEAR FROM NOW()) AS anio,
       current_setting('work_mem') AS work_mem;

-- Q01 — Consulta con índices definitivos.
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

-- Q02 — Consulta con índices definitivos.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT COUNT(*) AS tutorias_asociadas
FROM public.tutorias
WHERE "alumnoId" = 1 OR "profesorId" = 1;

-- Q03 — Consulta con índices definitivos.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT COUNT(*) AS tutorias_categoria
FROM public.tutorias
WHERE "categoriaId" = 1;

-- Q04 — Consulta con índices definitivos.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT t.*
FROM public.tutorias t
WHERE t."profesorId" = 10001
  AND t."categoriaId" = 1
  AND t.estado IN ('pendiente', 'aceptada')
LIMIT 1;

-- Q05 — Consulta con índices definitivos.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT h.*
FROM public.horarios_disponibles h
WHERE h."profesorId" = 10001
  AND h.estado = 'activo';

-- Q06 — Consulta con índices definitivos.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT
    TO_CHAR("createdAt", 'MM') AS month,
    COUNT(id) AS count
FROM public.tutorias
WHERE "createdAt" >= DATE_TRUNC('year', NOW())
  AND "createdAt" < DATE_TRUNC('year', NOW()) + INTERVAL '1 year'
GROUP BY TO_CHAR("createdAt", 'MM')
ORDER BY TO_CHAR("createdAt", 'MM') ASC;

-- Q07 — Primera página de 100 tutorías, orden por fecha e ID.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
WITH pagina AS (
    SELECT id, modalidad, "precioAcordado", "fechaHora",
           estado, "enlaceMeet", pagada, "createdAt",
           "alumnoId", "profesorId", "categoriaId"
    FROM public.tutorias
    ORDER BY "createdAt" DESC, id DESC
    LIMIT 100
)
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
FROM pagina t
LEFT JOIN public.usuarios alumno ON alumno.id = t."alumnoId"
LEFT JOIN public.usuarios profesor ON profesor.id = t."profesorId"
LEFT JOIN public.categorias categoria ON categoria.id = t."categoriaId"
LEFT JOIN public.calificaciones calificacion
    ON calificacion."tutoriaId" = t.id
ORDER BY t."createdAt" DESC, t.id DESC;

-- Q08 — Consulta con índices definitivos.
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
