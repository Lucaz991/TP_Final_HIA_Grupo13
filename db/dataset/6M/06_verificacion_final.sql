-- Ejecutar en tpFinal, con Auto-commit activado y sin otras cargas.
-- Ejecutar primero los cinco ANALYZE como bloque separado.
-- Después ejecutar cada consulta numerada por separado y guardar su salida.
-- Actualizar estadísticas después de la carga.
ANALYZE public.usuarios;
ANALYZE public.categorias;
ANALYZE public.profesores_categorias;
ANALYZE public.tutorias;
ANALYZE public.horarios_disponibles;

-- 1. Conteos reales por tabla.
SELECT 'usuarios' AS tabla, COUNT(*) AS registros
FROM public.usuarios
UNION ALL
SELECT 'categorias', COUNT(*)
FROM public.categorias
UNION ALL
SELECT 'precios', COUNT(*)
FROM public.precios
UNION ALL
SELECT 'profesores_categorias', COUNT(*)
FROM public.profesores_categorias
UNION ALL
SELECT 'horarios_disponibles', COUNT(*)
FROM public.horarios_disponibles
UNION ALL
SELECT 'tutorias', COUNT(*)
FROM public.tutorias;

-- 2. Comparar el conteo real con el punto inicial.
-- Esperado: 60000 tutorías nuevas en piloto o 6000000 en definitiva.
-- Al terminar los seis lotes, coincide y completo deben ser true.
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
    configuracion.registros_por_lote::bigint * 6 AS tutorias_esperadas,
    c.tutorias_actuales - e.tutorias_iniciales =
        r.tutorias_registradas AS coincide,
    c.tutorias_actuales - e.tutorias_iniciales =
        configuracion.registros_por_lote::bigint * 6
        AND r.tutorias_registradas =
            configuracion.registros_por_lote::bigint * 6 AS completo
FROM pt23_dataset.ejecucion e
CROSS JOIN conteo c
CROSS JOIN registro r
CROSS JOIN pt23_dataset.configuracion configuracion
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
    'public.precios'::regclass,
    'public.profesores_categorias'::regclass,
    'public.horarios_disponibles'::regclass,
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
        ('public.precios'::regclass),
        ('public.profesores_categorias'::regclass),
        ('public.horarios_disponibles'::regclass),
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
      'horarios_disponibles',
      'tutorias',
      'precios'
  )
ORDER BY tablename, indexname;
-- 12. Cantidades esperadas según el modo registrado por el generador.
-- El piloto completo espera 2002 usuarios y 60000 tutorías.
-- La definitiva espera 200002 usuarios y 6000000 tutorías.
WITH configuracion AS (
    SELECT usuarios_por_rol, registros_por_lote
    FROM pt23_dataset.configuracion
    WHERE id = 1
),
cantidades AS (
    SELECT
        'usuarios' AS tabla,
        COUNT(*) AS actuales,
        (SELECT usuarios_por_rol::bigint * 2 + 2 FROM configuracion)
            AS esperados
    FROM public.usuarios

    UNION ALL

    SELECT 'categorias', COUNT(*), 100
    FROM public.categorias

    UNION ALL

    SELECT 'precios', COUNT(*), 10
    FROM public.precios

    UNION ALL

    SELECT 'profesores_categorias', COUNT(*),
        (SELECT usuarios_por_rol::bigint * 4 FROM configuracion)
    FROM public.profesores_categorias

    UNION ALL

    SELECT 'horarios_disponibles', COUNT(*),
        (SELECT usuarios_por_rol::bigint * 4 FROM configuracion)
    FROM public.horarios_disponibles

    UNION ALL

    SELECT 'tutorias', COUNT(*),
        (SELECT registros_por_lote::bigint * 6 FROM configuracion)
    FROM public.tutorias
)
SELECT
    tabla,
    actuales,
    esperados,
    actuales = esperados AS cumple
FROM cantidades
ORDER BY tabla;


-- 13. Distribución de usuarios y presencia de hashes válidos.
-- Esperado: 2 administradores y la cantidad configurada de cada otro rol.
-- usuarios_sin_hash_valido debe ser 0.
SELECT
    rol,
    COUNT(*) AS cantidad,
    COUNT(*) FILTER (
        WHERE "contraseniaHash" IS NULL
           OR "contraseniaHash" !~
              '^\$2[aby]\$10\$[./A-Za-z0-9]{53}$'
    ) AS usuarios_sin_hash_valido
FROM public.usuarios
GROUP BY rol
ORDER BY rol;


-- 14. Horarios con referencias, roles o intervalos incorrectos.
-- Esperado: 0.
SELECT COUNT(*) AS horarios_invalidos
FROM public.horarios_disponibles horario
LEFT JOIN public.usuarios profesor
    ON profesor.id = horario."profesorId"
WHERE profesor.rol IS DISTINCT FROM
          'profesor'::public.enum_usuarios_rol
   OR horario."horaInicio" >= horario."horaFin";


-- 15. Profesores con cantidad incorrecta de horarios.
-- Esperado: cero filas.
SELECT
    profesor.id,
    profesor.email,
    COUNT(horario.id) AS horarios,
    COUNT(*) FILTER (
        WHERE horario.estado = 'activo'
    ) AS horarios_activos
FROM public.usuarios profesor
LEFT JOIN public.horarios_disponibles horario
    ON horario."profesorId" = profesor.id
WHERE profesor.rol = 'profesor'
GROUP BY profesor.id, profesor.email
HAVING COUNT(horario.id) <> 4
    OR COUNT(*) FILTER (
        WHERE horario.estado = 'activo'
    ) <> 4;


-- 16. Superposiciones entre horarios activos de un profesor.
-- Esperado: 0.
WITH intervalos AS (
    SELECT
        id,
        "profesorId",
        "diaSemana",
        "horaInicio",
        MAX("horaFin") OVER (
            PARTITION BY "profesorId", "diaSemana"
            ORDER BY "horaInicio", id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS fin_anterior
    FROM public.horarios_disponibles
    WHERE estado = 'activo'
)
SELECT COUNT(*) AS horarios_superpuestos
FROM intervalos
WHERE "horaInicio" < fin_anterior;


-- 17. Tutorías cuyo precio difiere de la tarifa del catálogo.
-- Se asume una hora de duración por tutoría.
-- Esperado: 0.
SELECT COUNT(*) AS tutorias_con_tarifa_incorrecta
FROM public.tutorias tutoria
LEFT JOIN public.categorias categoria
    ON categoria.id = tutoria."categoriaId"
LEFT JOIN public.precios tarifa
    ON tarifa.nivel::text = categoria.nivel::text
   AND tarifa.modalidad::text = tutoria.modalidad::text
WHERE tarifa.id IS NULL
   OR tutoria."precioAcordado" IS DISTINCT FROM tarifa.precio;


-- 18. Tutorías fuera del horario activo del profesor.
-- Se asume una hora de duración.
-- La comparación utiliza la hora de Argentina.
-- Esperado: 0.
WITH sesiones AS (
    SELECT
        "profesorId",
        modalidad,
        "fechaHora"
            AT TIME ZONE 'America/Argentina/Buenos_Aires'
            AS inicio_local,
        ("fechaHora" + interval '1 hour')
            AT TIME ZONE 'America/Argentina/Buenos_Aires'
            AS fin_local
    FROM public.tutorias
)
SELECT COUNT(*) AS tutorias_fuera_de_horario
FROM sesiones sesion
WHERE sesion.inicio_local::date <> sesion.fin_local::date
   OR NOT EXISTS (
       SELECT 1
       FROM public.horarios_disponibles horario
       WHERE horario."profesorId" = sesion."profesorId"
         AND horario.estado = 'activo'
         AND horario."diaSemana"::text =
             (
                 ARRAY[
                     'lunes',
                     'martes',
                     'miercoles',
                     'jueves',
                     'viernes',
                     'sabado',
                     'domingo'
                 ]
             )[EXTRACT(ISODOW FROM sesion.inicio_local)::integer]
         AND horario."horaInicio" <= sesion.inicio_local::time
         AND horario."horaFin" >= sesion.fin_local::time
         AND (
             horario.modalidad = 'ambas'
             OR horario.modalidad::text = sesion.modalidad::text
         )
   );


-- 19. Superposiciones de tutorías por profesor.
-- Se revisan todos los estados, con duración de una hora.
-- Esperado: 0.
WITH sesiones AS (
    SELECT
        id,
        "fechaHora",
        MAX("fechaHora" + interval '1 hour') OVER (
            PARTITION BY "profesorId"
            ORDER BY "fechaHora", id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS fin_anterior
    FROM public.tutorias
)
SELECT COUNT(*) AS tutorias_superpuestas_profesor
FROM sesiones
WHERE "fechaHora" < fin_anterior;


-- 20. Superposiciones de tutorías por alumno.
-- Se revisan todos los estados, con duración de una hora.
-- Esperado: 0.
WITH sesiones AS (
    SELECT
        id,
        "fechaHora",
        MAX("fechaHora" + interval '1 hour') OVER (
            PARTITION BY "alumnoId"
            ORDER BY "fechaHora", id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS fin_anterior
    FROM public.tutorias
)
SELECT COUNT(*) AS tutorias_superpuestas_alumno
FROM sesiones
WHERE "fechaHora" < fin_anterior;
