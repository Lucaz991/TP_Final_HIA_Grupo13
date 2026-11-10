-- PT-23 - Estado inicial del conjunto de prueba.
-- Ejecutar antes de la carga y conservar los resultados.

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

-- 1. Comprobar el destino y la conexión.
DO $validacion$
BEGIN
    IF current_database() <> 'tpFinal' THEN
        RAISE EXCEPTION
            'Base incorrecta. Se esperaba tpFinal y se recibió %.',
            current_database();
    END IF;

    IF pg_is_in_recovery() THEN
        RAISE EXCEPTION
            'La conexión corresponde a una réplica. Conectarse al líder.';
    END IF;
END;
$validacion$;

SELECT
    current_database() AS base,
    current_user AS usuario,
    clock_timestamp() AS fecha_verificacion,
    version() AS version_postgresql;

-- 2. Registrar cantidades iniciales.
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

-- 3. Registrar usuarios por rol y estado.
SELECT
    rol,
    estado,
    COUNT(*) AS cantidad
FROM public.usuarios
GROUP BY rol, estado
ORDER BY rol, estado;

-- 4. Registrar el tamaño inicial de la base.
SELECT
    pg_database_size(current_database()) AS tamanio_inicial_bytes,
    pg_size_pretty(
        pg_database_size(current_database())
    ) AS tamanio_inicial_legible;

-- 5. Registrar tamaño de tablas e índices.
SELECT
    tabla,
    pg_table_size(tabla) AS tabla_bytes,
    pg_indexes_size(tabla) AS indices_bytes,
    pg_total_relation_size(tabla) AS total_bytes
FROM (
    VALUES
        ('public.usuarios'::regclass),
        ('public.categorias'::regclass),
        ('public.profesores_categorias'::regclass),
        ('public.tutorias'::regclass)
) AS tablas(tabla)
ORDER BY tabla::text;

-- 6. Verificar referencias y roles de tutorías existentes.
-- Resultado esperado: 0.
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
WHERE alumno.rol IS DISTINCT FROM 'alumno'
   OR profesor.rol IS DISTINCT FROM 'profesor'
   OR categoria.id IS NULL
   OR asignacion."profesorId" IS NULL;

-- 7. Verificar asignaciones existentes.
-- Resultado esperado: 0.
SELECT COUNT(*) AS asignaciones_invalidas
FROM public.profesores_categorias asignacion
LEFT JOIN public.usuarios profesor
    ON profesor.id = asignacion."profesorId"
LEFT JOIN public.categorias categoria
    ON categoria.id = asignacion."categoriaId"
WHERE profesor.rol IS DISTINCT FROM 'profesor'
   OR categoria.id IS NULL;

COMMIT;