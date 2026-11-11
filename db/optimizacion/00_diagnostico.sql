-- PT-24 - Diagnóstico previo a las mediciones de consultas.
-- PostgreSQL 16. Conectarse a tpFinal mediante el proxy del clúster.
-- Solo lectura: no crea índices, extensiones ni cambia parámetros.
-- En pgAdmin activar Auto-commit y ejecutar cada sección por separado,
-- en orden, guardando su salida como CSV o captura.
-- Antes de empezar, cerrar cualquier transacción abortada con ROLLBACK.
-- Evitar cargas y actividad de la aplicación durante las mediciones.
-- Las secciones 12 y 13 recorren datos y pueden tardar y calentar la caché.
-- Este diagnóstico no constituye la medición inicial de las ocho consultas.

-- 01. Identificar servidor, destino y zona horaria.
-- destino_correcto y es_lider deben ser true para medir en el líder de tpFinal.
SELECT
    clock_timestamp() AS fecha_diagnostico,
    version() AS version_postgresql,
    current_database() AS base,
    current_database() = 'tpFinal' AS destino_correcto,
    current_user AS usuario,
    inet_server_addr() AS direccion_servidor,
    inet_server_port() AS puerto_servidor,
    NOT pg_is_in_recovery() AS es_lider,
    current_setting('transaction_read_only') AS transaccion_solo_lectura,
    current_setting('TimeZone') AS zona_horaria,
    pg_postmaster_start_time() AS inicio_servidor;

-- 02. Tamaño total de la base.
-- No suma las otras réplicas ni todos los archivos de los volúmenes Docker.
SELECT
    current_database() AS base,
    pg_database_size(current_database()) AS base_bytes,
    pg_size_pretty(pg_database_size(current_database())) AS base_legible;

-- 03. Tamaños de tablas e índices y cantidad estimada de filas.
-- n_live_tup es una estimación. Los conteos exactos están en la sección 12.
SELECT
    s.relname AS tabla,
    s.n_live_tup AS filas_vivas_estimadas,
    s.n_dead_tup AS filas_muertas_estimadas,
    pg_table_size(s.relid) AS tabla_bytes,
    pg_indexes_size(s.relid) AS indices_bytes,
    pg_total_relation_size(s.relid) AS total_bytes,
    pg_size_pretty(pg_total_relation_size(s.relid)) AS total_legible
FROM pg_stat_user_tables s
WHERE s.schemaname = 'public'
ORDER BY pg_total_relation_size(s.relid) DESC, s.relname;

-- 04. Inventario de índices existentes.
-- Los índices asociados a PK y UNIQUE ya forman parte de la línea base.
-- Una FK por sí sola no implica un índice en sus columnas de origen.
SELECT
    tabla.relname AS tabla,
    indice.relname AS indice,
    metodo.amname AS metodo,
    i.indisprimary AS clave_primaria,
    i.indisunique AS unico,
    i.indisvalid AS valido,
    i.indisready AS listo_para_escrituras,
    pg_relation_size(indice.oid) AS indice_bytes,
    pg_get_indexdef(indice.oid) AS definicion
FROM pg_index i
JOIN pg_class tabla ON tabla.oid = i.indrelid
JOIN pg_namespace esquema ON esquema.oid = tabla.relnamespace
JOIN pg_class indice ON indice.oid = i.indexrelid
JOIN pg_am metodo ON metodo.oid = indice.relam
WHERE esquema.nspname = 'public'
ORDER BY tabla.relname, indice.relname;

-- 05. Uso acumulado de índices.
-- idx_scan = 0 no demuestra que un índice sea innecesario.
-- Interpretar junto al período de estadísticas y las consultas evaluadas.
SELECT
    relname AS tabla,
    indexrelname AS indice,
    idx_scan AS recorridos,
    idx_tup_read AS entradas_leidas,
    idx_tup_fetch AS filas_recuperadas
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY relname, indexrelname;

-- 06. Recorridos y mantenimiento acumulados de tablas.
-- Un recorrido secuencial puede ser adecuado para resultados grandes.
SELECT
    relname AS tabla,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_tup_hot_upd,
    last_analyze,
    last_autoanalyze,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY relname;

-- 07. Restricciones existentes.
SELECT
    c.conrelid::regclass AS tabla,
    c.conname AS restriccion,
    c.contype AS tipo,
    c.convalidated AS validada,
    pg_get_constraintdef(c.oid) AS definicion
FROM pg_constraint c
JOIN pg_class tabla ON tabla.oid = c.conrelid
JOIN pg_namespace esquema ON esquema.oid = tabla.relnamespace
WHERE esquema.nspname = 'public'
ORDER BY tabla.relname, c.conname;

-- 08. Estadísticas de columnas relevantes para filtros y JOIN.
-- n_distinct positivo representa una cantidad estimada de valores distintos.
-- Un valor negativo representa una fracción del número de filas.
-- correlation aproxima la relación entre orden de valores y orden físico.
-- La ausencia de una fila puede indicar estadísticas faltantes o permisos.
SELECT
    tablename AS tabla,
    attname AS columna,
    null_frac,
    n_distinct,
    avg_width,
    correlation,
    most_common_vals::text AS valores_frecuentes,
    most_common_freqs AS frecuencias
FROM pg_stats
WHERE schemaname = 'public'
  AND (
      (tablename = 'tutorias' AND attname IN (
          'alumnoId', 'profesorId', 'categoriaId', 'estado',
          'modalidad', 'pagada', 'fechaHora', 'createdAt'
      ))
      OR (tablename = 'usuarios' AND attname IN ('rol', 'estado'))
      OR (tablename = 'horarios_disponibles' AND attname IN (
          'profesorId', 'diaSemana', 'estado', 'modalidad'
      ))
      OR (tablename = 'profesores_categorias' AND attname IN (
          'profesorId', 'categoriaId', 'estado'
      ))
      OR (tablename = 'calificaciones' AND attname = 'tutoriaId')
  )
ORDER BY tablename, attname;

-- 09. Parámetros efectivos de memoria, planificación y observabilidad.
-- setting se interpreta con unit. source indica el origen del valor.
-- Esta consulta no aplica cambios ni requiere reiniciar el servidor.
SELECT
    name AS parametro,
    setting AS valor,
    unit AS unidad,
    source AS origen,
    context AS contexto,
    pending_restart AS reinicio_pendiente
FROM pg_settings
WHERE name IN (
    'shared_buffers', 'effective_cache_size', 'work_mem',
    'maintenance_work_mem', 'max_connections',
    'max_worker_processes', 'max_parallel_workers',
    'max_parallel_workers_per_gather',
    'random_page_cost', 'seq_page_cost', 'effective_io_concurrency',
    'default_statistics_target', 'jit', 'autovacuum',
    'track_counts', 'track_io_timing', 'compute_query_id',
    'shared_preload_libraries', 'logging_collector',
    'log_destination', 'log_min_duration_statement'
)
ORDER BY name;

-- 10. Período e indicadores acumulados de la base.
-- blks_hit/blks_read miden accesos de PostgreSQL, no la caché del SO.
-- Los contadores corresponden a este servidor y su historial de estadísticas.
SELECT
    datname AS base,
    stats_reset AS reinicio_estadisticas,
    numbackends AS conexiones,
    xact_commit,
    xact_rollback,
    blks_read,
    blks_hit,
    temp_files,
    temp_bytes,
    deadlocks,
    blk_read_time,
    blk_write_time
FROM pg_stat_database
WHERE datname = current_database();

-- 11. Disponibilidad de pg_stat_statements.
-- No instala ni activa la extensión. Cero filas indica que no está disponible.
-- La presencia de la extensión debe contrastarse con la precarga y su uso real.
SELECT
    disponible.name AS extension,
    disponible.default_version AS version_disponible,
    instalada.extversion AS version_instalada,
    esquema.nspname AS esquema_instalacion,
    current_setting('shared_preload_libraries') AS bibliotecas_precargadas
FROM pg_available_extensions disponible
LEFT JOIN pg_extension instalada ON instalada.extname = disponible.name
LEFT JOIN pg_namespace esquema ON esquema.oid = instalada.extnamespace
WHERE disponible.name = 'pg_stat_statements';

-- 12. Conteos exactos del conjunto de prueba.
-- Este bloque recorre tablas y puede tardar. No usarlo como benchmark.
SELECT 'usuarios' AS tabla, COUNT(*) AS filas
FROM public.usuarios
UNION ALL
SELECT 'categorias', COUNT(*) FROM public.categorias
UNION ALL
SELECT 'precios', COUNT(*) FROM public.precios
UNION ALL
SELECT 'profesores_categorias', COUNT(*) FROM public.profesores_categorias
UNION ALL
SELECT 'horarios_disponibles', COUNT(*) FROM public.horarios_disponibles
UNION ALL
SELECT 'tutorias', COUNT(*) FROM public.tutorias
UNION ALL
SELECT 'calificaciones', COUNT(*) FROM public.calificaciones;

-- 13. Distribución anual para elegir rangos de distinta selectividad.
-- La aplicación utiliza createdAt en el gráfico mensual.
-- Usar la misma zona horaria al comparar la consulta original y la reescrita.
SELECT
    EXTRACT(YEAR FROM "fechaHora"
        AT TIME ZONE 'America/Argentina/Buenos_Aires')::integer AS anio,
    COUNT(*) AS tutorias
FROM public.tutorias
GROUP BY 1
ORDER BY 1;

-- 14. IDs de ejemplo para parametrizar consultas sin asumir secuencias.
-- Devuelve solo identificadores de las cuentas sintéticas seleccionadas.
SELECT id, rol, email
FROM public.usuarios
WHERE email IN (
    'alumno.1@example.com',
    'profesor.1@example.com',
    'profesor.20001@example.com',
    'profesor.55001@example.com'
)
ORDER BY rol, email;
