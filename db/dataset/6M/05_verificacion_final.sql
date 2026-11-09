-- Ejecutar en tpFinal, con Auto-commit activado y sin otras cargas.
-- Ejecutar primero los cuatro ANALYZE como bloque separado.
-- Después ejecutar cada consulta numerada por separado y guardar su salida.
-- Actualizar estadísticas después de la carga.
ANALYZE public.usuarios;
ANALYZE public.categorias;
ANALYZE public.profesores_categorias;
ANALYZE public.tutorias;

-- 1. Conteos reales por tabla.
SELECT 'usuarios' AS tabla, COUNT(*) AS registros
FROM public.usuarios
UNION ALL
SELECT 'categorias', COUNT(*)
FROM public.categorias
UNION ALL
SELECT 'profesores_categorias', COUNT(*)
FROM public.profesores_categorias
UNION ALL
SELECT 'tutorias', COUNT(*)
FROM public.tutorias;

-- 2. Comparar el conteo real con el punto inicial.
-- Esperado: incremento_real = 6000000 y coincide = true.
WITH conteo AS (
    SELECT COUNT(*) AS tutorias_actuales
    FROM public.tutorias
),
registro AS (
    SELECT COALESCE(SUM(registros), 0) AS tutorias_registradas
    FROM pt23_dataset.lotes
)
SELECT
    e.tutorias_iniciales,
    c.tutorias_actuales,
    c.tutorias_actuales - e.tutorias_iniciales AS incremento_real,
    r.tutorias_registradas,
    c.tutorias_actuales - e.tutorias_iniciales =
        r.tutorias_registradas AS coincide
FROM pt23_dataset.ejecucion e
CROSS JOIN conteo c
CROSS JOIN registro r
WHERE e.id = 1;

-- 3. Integridad de relaciones y roles.
-- Esperado: 0.
SELECT COUNT(*) AS tutorias_invalidas
FROM public.tutorias t
LEFT JOIN public.usuarios alumno
    ON alumno.id = t."alumnoId"
LEFT JOIN public.usuarios profesor
    ON profesor.id = t."profesorId"
LEFT JOIN public.categorias categoria
    ON categoria.id = t."categoriaId"
LEFT JOIN public.profesores_categorias asignacion
    ON asignacion."profesorId" = t."profesorId"
   AND asignacion."categoriaId" = t."categoriaId"
WHERE alumno.rol IS DISTINCT FROM
          'alumno'::public.enum_usuarios_rol
   OR profesor.rol IS DISTINCT FROM
          'profesor'::public.enum_usuarios_rol
   OR categoria.id IS NULL
   OR asignacion."profesorId" IS NULL;

-- 4. Coherencia básica de importes y fechas.
-- Esperado: 0.
SELECT COUNT(*) AS tutorias_con_valores_invalidos
FROM public.tutorias
WHERE "precioAcordado" < 0
   OR "createdAt" IS NULL
   OR "updatedAt" IS NULL
   OR "fechaHora" IS NULL
   OR "updatedAt" < "createdAt"
   OR "fechaHora" < "createdAt";

-- 5. Distribución por estado, modalidad y pago.
SELECT
    estado,
    modalidad,
    pagada,
    COUNT(*) AS cantidad
FROM public.tutorias
GROUP BY estado, modalidad, pagada
ORDER BY estado, modalidad, pagada;

-- 6. Duplicados en identificadores de pagos sintéticos.
-- Esperado: cero filas.
SELECT
    "paymentId",
    COUNT(*) AS cantidad
FROM public.tutorias
WHERE "paymentId" LIKE 'pago-%'
GROUP BY "paymentId"
HAVING COUNT(*) > 1;

-- 7. Restricciones existentes y su estado.
SELECT
    conrelid::regclass AS tabla,
    conname AS restriccion,
    contype AS tipo,
    convalidated AS validada,
    pg_get_constraintdef(oid) AS definicion
FROM pg_constraint
WHERE conrelid IN (
    'public.usuarios'::regclass,
    'public.categorias'::regclass,
    'public.profesores_categorias'::regclass,
    'public.tutorias'::regclass
)
ORDER BY tabla, tipo, restriccion;

-- 8. Tamaño final de la base y crecimiento desde
-- el inicio de la carga de tutorías.
SELECT
    current_database() AS base,
    e.base_inicial_bytes,
    pg_database_size(current_database()) AS base_final_bytes,
    pg_size_pretty(
        pg_database_size(current_database())
    ) AS base_final_legible,
    pg_database_size(current_database())
        - e.base_inicial_bytes AS crecimiento_bytes
FROM pt23_dataset.ejecucion e
WHERE e.id = 1;

-- 9. Tamaño de las tablas y sus índices.
SELECT
    tabla,
    pg_table_size(tabla) AS tabla_bytes,
    pg_indexes_size(tabla) AS indices_bytes,
    pg_total_relation_size(tabla) AS total_bytes,
    pg_size_pretty(
        pg_total_relation_size(tabla)
    ) AS total_legible
FROM (
    VALUES
        ('public.usuarios'::regclass),
        ('public.categorias'::regclass),
        ('public.profesores_categorias'::regclass),
        ('public.tutorias'::regclass)
) AS tablas(tabla)
ORDER BY tabla::text;

-- 10. Tiempos registrados.
SELECT
    COUNT(*) AS lotes,
    SUM(registros) AS registros,
    SUM(duracion) AS tiempo_sql_lotes_exitosos,
    MAX(fin) - MIN(inicio) AS intervalo_transcurrido
FROM pt23_dataset.lotes;

-- 11. Índices, incluyendo UNIQUE definidos fuera de pg_constraint.
SELECT
    tablename AS tabla,
    indexname AS indice,
    indexdef AS definicion
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
      'usuarios',
      'categorias',
      'profesores_categorias',
      'tutorias',
      'precios'
  )
ORDER BY tablename, indexname;
