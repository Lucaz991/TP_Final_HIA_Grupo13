-- Usuarios del dataset.
-- Dos administradores y hasta 100000 alumnos y profesores.
-- Completar un hash bcrypt por rol. Compartir las contraseñas por separado.
-- Ejecutar por rangos de hasta 10000 números.

BEGIN;

SELECT pg_advisory_xact_lock(23002);

DO $destino$
BEGIN
    IF current_database() <> 'tpFinal' THEN
        RAISE EXCEPTION 'Ejecutar únicamente en tpFinal.';
    END IF;

    IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Conectarse al nodo líder.';
    END IF;

    -- Evitar mezclar los usuarios anteriores con el nuevo dataset.
    IF EXISTS (
        SELECT 1
        FROM public.usuarios
        WHERE email ~
            '^(pt23\.)?(alumno|profesor)\.[0-9]+@example\.invalid$'
    ) THEN
        RAISE EXCEPTION
            'Existen usuarios del dataset anterior. Preparar la base limpia antes de esta carga.';
    END IF;
END;
$destino$;

-- Cambiar el rango para cada lote.
-- Conservar los mismos tres hashes durante todas las ejecuciones.
CREATE TEMP TABLE usuarios_config ON COMMIT DROP AS
SELECT
    1::integer AS desde,
    10000::integer AS hasta,
    '$2b$10$DA6GO0ktoJhv/SStxn4mn.ryG06TzCajsPTuVEr3.h4Jv3kfCETZW'::text AS hash_admin,
    '$2b$10$n0mVPZ1/h.FslNpiDqOHJ.KvH0llzo/mtgMetXgewM3oZzvvLSCqe'::text AS hash_profesor,
    '$2b$10$acdmx4hRCVICI4kzWmd69OUCfSE7VBlOCekLl57vv.RCAL9w6TNfi'::text AS hash_alumno;

DO $configuracion$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM usuarios_config
        WHERE desde < 1
           OR hasta > 100000
           OR hasta < desde
           OR hasta - desde + 1 > 10000
    ) THEN
        RAISE EXCEPTION
            'Rango inválido. Usar entre 1 y 100000, hasta 10000 por ejecución.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM usuarios_config configuracion
        CROSS JOIN LATERAL (
            VALUES
                (configuracion.hash_admin),
                (configuracion.hash_profesor),
                (configuracion.hash_alumno)
        ) AS hashes(valor)
        WHERE valor IS NULL
           OR length(valor) <> 60
           OR valor !~ '^\$2[aby]\$10\$[./A-Za-z0-9]{53}$'
    ) THEN
        RAISE EXCEPTION
            'Los tres hashes deben ser bcrypt completos con costo 10.';
    END IF;
END;
$configuracion$;

-- Conjunto esperado del lote.
CREATE TEMP TABLE usuarios_lote ON COMMIT DROP AS
SELECT
    serie.numero,
    roles.rol,
    roles.rol || '.' || serie.numero || '@example.com' AS email
FROM usuarios_config configuracion
CROSS JOIN LATERAL
    generate_series(
        configuracion.desde,
        configuracion.hasta
    ) AS serie(numero)
CROSS JOIN (
    VALUES ('alumno'), ('profesor')
) AS roles(rol)

UNION ALL

-- Incluir siempre las dos cuentas de administración.
-- La unicidad de email evita crearlas otra vez.
SELECT
    numero,
    'admin',
    'admin.' || numero || '@example.com'
FROM generate_series(1, 2) AS administradores(numero);

CREATE UNIQUE INDEX ON usuarios_lote (email);

ANALYZE usuarios_lote;

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
        WHEN 'profesor' THEN 'Profesor '
        ELSE 'Administrador '
    END || lote.numero,
    'Sintético',
    lote.email,
    CASE lote.rol
        WHEN 'admin' THEN configuracion.hash_admin
        WHEN 'profesor' THEN configuracion.hash_profesor
        WHEN 'alumno' THEN configuracion.hash_alumno
    END,
    (
        CASE WHEN lote.numero % 2 = 0
            THEN 'femenino'
            ELSE 'masculino'
        END
    )::public.enum_usuarios_genero,
    'activo'::public.enum_usuarios_estado,
    'local'::public."enum_usuarios_proveedorAuth",

    CASE WHEN lote.rol = 'admin' THEN
        'Administración del sistema'
    ELSE
        (
            ARRAY[
                'Universidad Nacional de Jujuy',
                'Universidad Nacional de Salta',
                'Universidad Nacional de Tucumán',
                'Universidad Nacional de Córdoba',
                'Universidad de Buenos Aires'
            ]
        )[1 + ((lote.numero - 1) % 5)]
    END,

    CASE WHEN lote.rol = 'admin' THEN
        'Administración'
    ELSE
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
        )[1 + ((lote.numero - 1) % 7)]
    END,

    'San Salvador de Jujuy',
    -24.20 + (lote.numero % 100) * 0.0004,
    -65.34 + (lote.numero % 113) * 0.0004,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM usuarios_lote lote
CROSS JOIN usuarios_config configuracion
ON CONFLICT (email) DO NOTHING;

ANALYZE public.usuarios;

DO $verificacion$
DECLARE
    invalidos bigint;
BEGIN
    SELECT COUNT(*)
    INTO invalidos
    FROM usuarios_lote esperado
    CROSS JOIN usuarios_config configuracion
    LEFT JOIN public.usuarios usuario
        ON usuario.email = esperado.email
    WHERE usuario.id IS NULL
       OR usuario.rol::text IS DISTINCT FROM esperado.rol
       OR usuario.estado IS DISTINCT FROM
          'activo'::public.enum_usuarios_estado
       OR usuario."proveedorAuth" IS DISTINCT FROM
          'local'::public."enum_usuarios_proveedorAuth"
       OR usuario."contraseniaHash" IS DISTINCT FROM
          CASE esperado.rol
              WHEN 'admin' THEN configuracion.hash_admin
              WHEN 'profesor' THEN configuracion.hash_profesor
              WHEN 'alumno' THEN configuracion.hash_alumno
          END;

    IF invalidos <> 0 THEN
        RAISE EXCEPTION
            'Hay % usuarios faltantes o con datos distintos a los esperados.',
            invalidos;
    END IF;

    RAISE NOTICE
        'Usuarios del lote y administradores verificados.';
END;
$verificacion$;

COMMIT;

-- Conteos acumulados de cuentas del dataset.
SELECT
    rol,
    COUNT(*) AS usuarios_dataset
FROM public.usuarios
WHERE email ~
    '^(alumno|profesor)\.([1-9][0-9]{0,4}|100000)@example\.com$'
   OR email IN (
       'admin.1@example.com',
       'admin.2@example.com'
   )
GROUP BY rol
ORDER BY rol;
