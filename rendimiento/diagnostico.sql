-- Rendimiento: ejecutar conectado a tpFinal, sin pruebas de carga simultaneas.
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '3s';

-- 1. Identidad, rol y configuracion activa.
SELECT current_database() AS base, version(), pg_is_in_recovery() AS replica,
       inet_server_addr() AS servidor, current_setting('TimeZone') AS zona;
SELECT name, setting, unit, source FROM pg_settings
WHERE name IN ('max_connections','shared_buffers','work_mem','effective_cache_size',
               'max_parallel_workers_per_gather','max_parallel_workers','max_worker_processes')
ORDER BY name;
SELECT tablename, indexname, indexdef FROM pg_indexes
WHERE schemaname='public' AND tablename IN ('tutorias','calificaciones','usuarios')
ORDER BY tablename,indexname;

-- 2. Resumen: aislar las agregaciones principales del endpoint.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT COUNT(id),
 COALESCE(SUM(CASE WHEN pagada THEN "precioAcordado" ELSE 0 END),0),
 COALESCE(SUM(CASE WHEN NOT pagada AND estado::text NOT IN ('rechazada','cancelada')
                   THEN "precioAcordado" ELSE 0 END),0),
 AVG("precioAcordado"),
 COALESCE(100.0 * COUNT(*) FILTER (WHERE pagada)/NULLIF(COUNT(*),0),0)
FROM public.tutorias;

EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT AVG(calificacion) FROM public.calificaciones;

-- 3. Listado: separar el costo del conteo global del acceso a primera pagina.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT COUNT(*) FROM public.tutorias;

-- Representacion de la seleccion de IDs actual; no mide hidratacion de Sequelize.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT t.id FROM public.tutorias t
LEFT JOIN public.usuarios a ON a.id=t."alumnoId"
LEFT JOIN public.usuarios p ON p.id=t."profesorId"
LEFT JOIN public.categorias c ON c.id=t."categoriaId"
ORDER BY t."createdAt" DESC,t.id DESC LIMIT 50 OFFSET 0;

-- 4. Mensual actual: mismo filtro y agregacion del controlador.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT TO_CHAR("createdAt",'MM') AS month,COUNT(id) AS count
FROM public.tutorias
WHERE EXTRACT(YEAR FROM "createdAt")=EXTRACT(YEAR FROM NOW())
GROUP BY TO_CHAR("createdAt",'MM') ORDER BY TO_CHAR("createdAt",'MM');

-- 5. Candidato: rango semiabierto anual, sin cambiar el backend.
-- Puede no mejorar si casi todas las filas pertenecen al anio actual.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON)
SELECT TO_CHAR("createdAt",'MM') AS month,COUNT(id) AS count
FROM public.tutorias
WHERE "createdAt">=date_trunc('year',NOW())
  AND "createdAt"<date_trunc('year',NOW())+INTERVAL '1 year'
GROUP BY TO_CHAR("createdAt",'MM') ORDER BY TO_CHAR("createdAt",'MM');

-- 6. Equivalencia en este dataset y zona de la sesion: esperado 0 diferencias.
WITH original AS (
 SELECT TO_CHAR("createdAt",'MM') AS mes,COUNT(id) AS cantidad
 FROM public.tutorias
 WHERE EXTRACT(YEAR FROM "createdAt")=EXTRACT(YEAR FROM NOW()) GROUP BY 1
), candidata AS (
 SELECT TO_CHAR("createdAt",'MM') AS mes,COUNT(id) AS cantidad
 FROM public.tutorias
 WHERE "createdAt">=date_trunc('year',NOW())
 AND "createdAt"<date_trunc('year',NOW())+INTERVAL '1 year' GROUP BY 1
)
SELECT COUNT(*) AS diferencias FROM (
 (SELECT * FROM original EXCEPT ALL SELECT * FROM candidata)
 UNION ALL
 (SELECT * FROM candidata EXCEPT ALL SELECT * FROM original)
) d;

ROLLBACK;
