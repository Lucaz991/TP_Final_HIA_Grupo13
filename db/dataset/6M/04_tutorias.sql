-- PT-23 - Seis lotes de 1000000 de tutorías.
-- Destino: tpFinal.
-- Requiere el esquema de la aplicación, los usuarios y las asignaciones.
-- Mantener el backend detenido durante la carga.

BEGIN;

SELECT pg_advisory_xact_lock(23004);

DO $destino$
BEGIN
    IF current_database() <> 'tpFinal' THEN
        RAISE EXCEPTION 'Ejecutar únicamente en tpFinal.';
    END IF;

    IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Conectarse al nodo líder.';
    END IF;
END;
$destino$;

-- Crear las tablas de control si todavía no existen.
CREATE SCHEMA IF NOT EXISTS pt23_dataset;

CREATE TABLE IF NOT EXISTS pt23_dataset.ejecucion (
    id integer PRIMARY KEY CHECK (id = 1),
    inicio timestamptz NOT NULL,
    tutorias_iniciales bigint NOT NULL,
    base_inicial_bytes bigint NOT NULL
);

CREATE TABLE IF NOT EXISTS pt23_dataset.lotes (
    lote integer PRIMARY KEY CHECK (lote BETWEEN 1 AND 6),
    registros integer NOT NULL CHECK (registros = 1000000),
    inicio timestamptz NOT NULL,
    fin timestamptz NOT NULL,
    duracion interval NOT NULL
);

-- Crear el registro inicial únicamente si no existe.
INSERT INTO pt23_dataset.ejecucion (
    id,
    inicio,
    tutorias_iniciales,
    base_inicial_bytes
)
SELECT
    1,
    clock_timestamp(),
    (SELECT COUNT(*) FROM public.tutorias),
    pg_database_size(current_database())
ON CONFLICT (id) DO NOTHING;

-- CAMBIAR ÚNICAMENTE EL NÚMERO DE LOTE: del 1 al 6.
CREATE TEMP TABLE pt23_config ON COMMIT DROP AS
SELECT
    1::integer AS lote,
    clock_timestamp() AS inicio;

DO $parametros$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pt23_config
        WHERE lote NOT BETWEEN 1 AND 6
    ) THEN
        RAISE EXCEPTION 'El lote debe estar entre 1 y 6.';
    END IF;

    -- Impedir mezclar el formato anterior con el nuevo.
    IF EXISTS (
        SELECT 1
        FROM pt23_dataset.lotes
        WHERE registros <> 1000000
           OR lote NOT BETWEEN 1 AND 6
    ) THEN
        RAISE EXCEPTION
            'Existen lotes del formato anterior. Revisar la limpieza.';
    END IF;
END;
$parametros$;

-- Actualizar las restricciones del registro de lotes.
ALTER TABLE pt23_dataset.lotes
    DROP CONSTRAINT IF EXISTS lotes_lote_check,
    DROP CONSTRAINT IF EXISTS lotes_registros_check;

ALTER TABLE pt23_dataset.lotes
    ADD CONSTRAINT lotes_lote_check
        CHECK (lote BETWEEN 1 AND 6),
    ADD CONSTRAINT lotes_registros_check
        CHECK (registros = 1000000);

-- El INSERT inicial conserva el punto de partida en las reejecuciones.

-- Recuperar los usuarios sintéticos.
CREATE TEMP TABLE pt23_usuarios ON COMMIT DROP AS
SELECT
    id,
    rol,
    estado,
    split_part(
        split_part(email, '@', 1),
        '.',
        2
    )::integer AS numero
FROM public.usuarios
WHERE email ~
    '^(alumno|profesor)\.([1-9][0-9]{0,4}|100000)@example\.invalid$';

CREATE UNIQUE INDEX
    ON pt23_usuarios (rol, numero);

ANALYZE pt23_usuarios;

DO $usuarios$
BEGIN
    IF (
        SELECT COUNT(*)
        FROM pt23_usuarios
        WHERE rol = 'alumno'
          AND estado = 'activo'
          AND numero BETWEEN 1 AND 100000
    ) <> 100000 THEN
        RAISE EXCEPTION
            'Se requieren 100000 alumnos sintéticos activos.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pt23_usuarios
        WHERE rol = 'profesor'
          AND estado = 'activo'
          AND numero BETWEEN 1 AND 100000
    ) <> 100000 THEN
        RAISE EXCEPTION
            'Se requieren 100000 profesores sintéticos activos.';
    END IF;
END;
$usuarios$;

-- Recuperar y numerar las cuatro categorías de cada profesor.
CREATE TEMP TABLE pt23_asignaciones ON COMMIT DROP AS
SELECT
    profesor.numero AS profesor_numero,
    profesor.id AS profesor_id,
    pc."categoriaId" AS categoria_id,
    pc.estado,
    row_number() OVER (
        PARTITION BY profesor.id
        ORDER BY pc."categoriaId"
    ) AS posicion
FROM pt23_usuarios profesor
JOIN public.profesores_categorias pc
    ON pc."profesorId" = profesor.id
JOIN public.categorias categoria
    ON categoria.id = pc."categoriaId"
WHERE profesor.rol = 'profesor';

CREATE UNIQUE INDEX
    ON pt23_asignaciones (profesor_numero, posicion);

ANALYZE pt23_asignaciones;

DO $asignaciones$
BEGIN
    IF EXISTS (
        SELECT profesor.numero
        FROM pt23_usuarios profesor
        LEFT JOIN pt23_asignaciones asignacion
            ON asignacion.profesor_numero = profesor.numero
        WHERE profesor.rol = 'profesor'
        GROUP BY profesor.numero
        HAVING COUNT(asignacion.categoria_id) <> 4
            OR COUNT(*) FILTER (
                WHERE asignacion.estado = 'activo'
            ) <> 4
    ) THEN
        RAISE EXCEPTION
            'Cada profesor sintético debe tener cuatro asignaciones activas.';
    END IF;
END;
$asignaciones$;

DO $carga$
DECLARE
    numero_lote integer;
    inicio_lote timestamptz;
    fin_lote timestamptz;
    insertadas bigint;
    desde bigint;
    hasta bigint;
BEGIN
    SELECT lote, inicio
    INTO numero_lote, inicio_lote
    FROM pt23_config;

    IF EXISTS (
        SELECT 1
        FROM pt23_dataset.lotes
        WHERE lote = numero_lote
    ) THEN
        RAISE NOTICE
            'El lote % ya fue confirmado. Se omite.',
            numero_lote;
        RETURN;
    END IF;

    desde := (numero_lote - 1)::bigint * 1000000 + 1;
    hasta := numero_lote::bigint * 1000000;

    WITH numeracion AS (
        SELECT
            serie.numero_global,
            1 + ((serie.numero_global - 1) % 100000)
                AS alumno_numero,
            (serie.numero_global - 1) / 100000
                AS ronda
        FROM generate_series(desde, hasta) AS serie(numero_global)
    ),
    base AS (
        SELECT
            numero_global,
            alumno_numero,
            ronda,
            CASE
                WHEN (alumno_numero + ronda + 1) % 3 = 0
                    THEN 'presencial'
                ELSE 'virtual'
            END AS modalidad,
            CASE
                WHEN (alumno_numero + ronda + 1) % 10 < 6
                    THEN 'finalizada'
                WHEN (alumno_numero + ronda + 1) % 10 < 8
                    THEN 'pendiente'
                WHEN (alumno_numero + ronda + 1) % 10 = 8
                    THEN 'aceptada'
                ELSE 'rechazada'
            END AS estado
        FROM numeracion
    )
    INSERT INTO public.tutorias (
        "alumnoId",
        "profesorId",
        "categoriaId",
        modalidad,
        "precioAcordado",
        mensaje,
        "fechaHora",
        estado,
        pagada,
        "enlaceMeet",
        "googleEventId",
        "preferenceId",
        "paymentId",
        "createdAt",
        "updatedAt"
    )
    SELECT
        alumno.id,
        asignacion.profesor_id,
        asignacion.categoria_id,
        base.modalidad::public.enum_tutorias_modalidad,

        5000 + (
            (base.numero_global * 17 + base.ronda) % 21
        ) * 500,

        (
            ARRAY[
                'Necesito repasar los temas del último examen.',
                'Quisiera resolver ejercicios prácticos.',
                'Necesito apoyo para preparar un examen.',
                'Quisiera reforzar los conceptos de la materia.',
                'Necesito ayuda para comprender un trabajo práctico.'
            ]
        )[1 + ((base.numero_global - 1) % 5)::integer],

        fechas.fecha,
        base.estado::public.enum_tutorias_estado,
        base.estado = 'finalizada',

        CASE
            WHEN base.modalidad = 'virtual'
             AND base.estado IN ('aceptada', 'finalizada')
            THEN
                'https://meet.example.com/' || base.numero_global
            ELSE NULL
        END,

        CASE
            WHEN base.modalidad = 'virtual'
             AND base.estado IN ('aceptada', 'finalizada')
            THEN 'evento-' || base.numero_global
            ELSE NULL
        END,

        CASE
            WHEN base.estado = 'finalizada'
            THEN 'preferencia-' || base.numero_global
            ELSE NULL
        END,

        CASE
            WHEN base.estado = 'finalizada'
            THEN 'pago-' || base.numero_global
            ELSE NULL
        END,

        fechas.fecha - interval '2 days',
        fechas.fecha - interval '1 day'

    FROM base
    JOIN pt23_usuarios alumno
        ON alumno.rol = 'alumno'
       AND alumno.numero = base.alumno_numero
    JOIN pt23_asignaciones asignacion
        ON asignacion.profesor_numero =
            1 + (
                (
                    (base.alumno_numero - 1) * 7919
                    + base.ronda * 1543
                ) % 100000
            )
       AND asignacion.posicion = 1 + (base.ronda % 4)
    CROSS JOIN LATERAL (
        SELECT
            timestamptz '2026-01-01 09:00:00-03'
            + base.ronda * interval '5 days'
            + (base.alumno_numero % 8) * interval '1 hour'
            AS fecha
    ) fechas;

    GET DIAGNOSTICS insertadas = ROW_COUNT;

    IF insertadas <> 1000000 THEN
        RAISE EXCEPTION
            'Se esperaban 1000000 tutorías y se insertaron %.',
            insertadas;
    END IF;

    fin_lote := clock_timestamp();

    INSERT INTO pt23_dataset.lotes (
        lote,
        registros,
        inicio,
        fin,
        duracion
    )
    VALUES (
        numero_lote,
        insertadas,
        inicio_lote,
        fin_lote,
        fin_lote - inicio_lote
    );

    RAISE NOTICE
        'Lote % confirmado al completar la transacción. Registros: %. Duración SQL: %.',
        numero_lote,
        insertadas,
        fin_lote - inicio_lote;
END;
$carga$;

COMMIT;

-- Progreso registrado.
SELECT
    COUNT(*) AS lotes_confirmados,
    COALESCE(SUM(registros), 0) AS tutorias_registradas,
    SUM(duracion) AS tiempo_sql_acumulado
FROM pt23_dataset.lotes;

-- Detalle de los lotes confirmados.
SELECT
    lote,
    registros,
    inicio,
    fin,
    duracion
FROM pt23_dataset.lotes
ORDER BY lote;
