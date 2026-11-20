-- PT-24. Validar la equivalencia del filtro de Q06 en una misma sentencia.
-- Ejecutar manualmente en tpFinal; puede recorrer la tabla varias veces.
-- Debe devolver cero filas. No modifica datos ni configuración.
WITH original AS (
SELECT
    TO_CHAR("createdAt", 'MM') AS month,
    COUNT(id) AS count
FROM public.tutorias
WHERE EXTRACT(YEAR FROM "createdAt") = EXTRACT(YEAR FROM NOW())
GROUP BY TO_CHAR("createdAt", 'MM')
ORDER BY TO_CHAR("createdAt", 'MM') ASC
), optimizada AS (
SELECT
    TO_CHAR("createdAt", 'MM') AS month,
    COUNT(id) AS count
FROM public.tutorias
WHERE "createdAt" >= DATE_TRUNC('year', NOW())
  AND "createdAt" < DATE_TRUNC('year', NOW()) + INTERVAL '1 year'
GROUP BY TO_CHAR("createdAt", 'MM')
ORDER BY TO_CHAR("createdAt", 'MM') ASC
)
SELECT 'solo_original' AS diferencia, * FROM (
 SELECT * FROM original EXCEPT ALL SELECT * FROM optimizada
) a
UNION ALL
SELECT 'solo_optimizada', * FROM (
 SELECT * FROM optimizada EXCEPT ALL SELECT * FROM original
) b;

-- Q07: resultado esperado 100 | 100 | true.
-- Comparar los IDs únicos de la página con una referencia ordenada
-- independientemente. Las calificaciones pueden repetir una tutoría.
WITH pagina AS (
    SELECT id, "createdAt", "alumnoId", "profesorId", "categoriaId"
    FROM public.tutorias
    ORDER BY "createdAt" DESC, id DESC
    LIMIT 100
), asociados AS (
    SELECT t.id, t."createdAt"
    FROM pagina t
    LEFT JOIN public.usuarios alumno ON alumno.id = t."alumnoId"
    LEFT JOIN public.usuarios profesor ON profesor.id = t."profesorId"
    LEFT JOIN public.categorias categoria ON categoria.id = t."categoriaId"
    LEFT JOIN public.calificaciones c ON c."tutoriaId" = t.id
), comparacion AS (
    SELECT ARRAY(
               SELECT id
               FROM (SELECT DISTINCT id, "createdAt" FROM asociados) AS unicos
               ORDER BY "createdAt" DESC, id DESC
           ) AS ids_pagina,
           ARRAY(
               SELECT id
               FROM public.tutorias
               ORDER BY "createdAt" DESC, (id + 0) DESC
               LIMIT 100
           ) AS ids_referencia
)
SELECT cardinality(ids_pagina) AS tutorias_pagina,
       cardinality(ids_referencia) AS tutorias_referencia,
       ids_pagina = ids_referencia AS mismos_ids_y_orden
FROM comparacion;
