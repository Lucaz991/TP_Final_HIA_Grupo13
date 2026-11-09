-- PT-23 - Carga de usuarios por lotes.
-- Primer lote: números 1 a 10000.
-- Inserta hasta 20000 usuarios por ejecución.

BEGIN;

SELECT pg_advisory_xact_lock(23002);

DO $validacion$
BEGIN
    IF current_database() <> 'tpFinal' THEN
        RAISE EXCEPTION 'Ejecutar únicamente en tpFinal.';
    END IF;

    IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Conectarse al nodo líder.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.usuarios
        WHERE email ~
            '^pt23\.(alumno|profesor)\.([1-9][0-9]{0,4}|100000)@example\.invalid$'
    ) THEN
        RAISE EXCEPTION
            'Existen emails del formato anterior. Ejecutar 06_actualizar_usuarios.sql antes de generar usuarios.';
    END IF;
END;
$validacion$;

-- Cambiar únicamente estos dos valores para cada lote.
CREATE TEMP TABLE pt23_rango ON COMMIT DROP AS
SELECT
    1::integer AS desde,
    10000::integer AS hasta;

DO $rango$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pt23_rango
        WHERE desde < 1
           OR hasta > 100000
           OR hasta < desde
           OR hasta - desde + 1 > 10000
    ) THEN
        RAISE EXCEPTION
            'Rango inválido. Usar entre 1 y 100000, hasta 10000 por lote.';
    END IF;
END;
$rango$;

-- Materializar el conjunto esperado evita repetir generate_series
-- dentro de la comprobación contra cada usuario.
CREATE TEMP TABLE pt23_usuarios_lote ON COMMIT DROP AS
SELECT
    serie.numero,
    roles.rol,
    roles.rol || '.' || serie.numero
        || '@example.invalid' AS email
FROM pt23_rango rango
CROSS JOIN LATERAL
    generate_series(rango.desde, rango.hasta) AS serie(numero)
CROSS JOIN (
    VALUES ('alumno'), ('profesor')
) AS roles(rol);

CREATE UNIQUE INDEX ON pt23_usuarios_lote (email);

ANALYZE pt23_usuarios_lote;

INSERT INTO public.usuarios (
    rol,
    nombre,
    apellido,
    email,
    "contraseniaHash",
    genero,
    estado,
    "proveedorAuth",
    universidad,
    carrera,
    ubicacion,
    lat,
    lng,
    "createdAt",
    "updatedAt"
)
SELECT
    lote.rol::public.enum_usuarios_rol,
    CASE lote.rol
        WHEN 'alumno' THEN 'Alumno '
        ELSE 'Profesor '
    END || lote.numero,
    'Sintético',
    lote.email,
    NULL,
    (
        CASE WHEN lote.numero % 2 = 0
            THEN 'femenino'
            ELSE 'masculino'
        END
    )::public.enum_usuarios_genero,
    'activo'::public.enum_usuarios_estado,
    'local'::public."enum_usuarios_proveedorAuth",
    (
        ARRAY[
            'Universidad Nacional de Jujuy',
            'Universidad Nacional de Salta',
            'Universidad Nacional de Tucumán',
            'Universidad Nacional de Córdoba',
            'Universidad de Buenos Aires'
        ]
    )[1 + ((lote.numero - 1) % 5)],
    (
        ARRAY[
            'Ingeniería Informática',
            'Contador Público',
            'Licenciatura en Administración',
            'Profesorado en Matemática',
            'Licenciatura en Física',
            'Ingeniería Industrial',
            'Licenciatura en Química'
        ]
    )[1 + ((lote.numero - 1) % 7)],
    'San Salvador de Jujuy',
    -24.20 + (lote.numero % 100) * 0.0004,
    -65.34 + (lote.numero % 113) * 0.0004,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM pt23_usuarios_lote lote
ON CONFLICT (email) DO NOTHING;

ANALYZE public.usuarios;

DO $verificacion$
DECLARE
    invalidos bigint;
BEGIN
    SELECT COUNT(*)
    INTO invalidos
    FROM pt23_usuarios_lote esperado
    LEFT JOIN public.usuarios usuario
        ON usuario.email = esperado.email
    WHERE usuario.id IS NULL
       OR usuario.rol::text IS DISTINCT FROM esperado.rol
       OR usuario.estado
            IS DISTINCT FROM 'activo'::public.enum_usuarios_estado;

    IF invalidos <> 0 THEN
        RAISE EXCEPTION
            'El lote contiene % usuarios faltantes o inválidos.',
            invalidos;
    END IF;

    RAISE NOTICE 'Lote verificado correctamente.';
END;
$verificacion$;

COMMIT;

-- Cantidad acumulada de usuarios sintéticos confirmados.
SELECT
    rol,
    COUNT(*) AS usuarios_sinteticos
FROM public.usuarios
WHERE email ~
    '^(alumno|profesor)\.([1-9][0-9]{0,4}|100000)@example\.invalid$'
GROUP BY rol
ORDER BY rol;
