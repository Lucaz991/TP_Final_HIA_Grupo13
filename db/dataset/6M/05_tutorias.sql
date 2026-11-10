-- PT-23 - Generador de tutorías para piloto o carga definitiva.
-- Piloto: 1000 usuarios por rol y seis lotes de 10000 tutorías.
-- Definitiva: 100000 usuarios por rol y seis lotes de 1000000 tutorías.
-- Destino: tpFinal.
-- Requiere usuarios @example.com, asignaciones, tarifas y horarios cargados.
-- Sesiones de una hora, de 09:00 a 10:00, durante 15 semanas.
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

-- CONFIGURACIÓN: conservar el modo durante las seis ejecuciones.
-- Piloto: usuarios_por_rol = 1000, registros_por_lote = 10000.
-- Definitiva: usuarios_por_rol = 100000, registros_por_lote = 1000000.
-- Cambiar lote de 1 a 6, esperando cada confirmación.
CREATE TEMP TABLE pt23_config ON COMMIT DROP AS
SELECT
    1::integer AS lote,
    100000::integer AS usuarios_por_rol,
    1000000::integer AS registros_por_lote,
    clock_timestamp() AS inicio;

DO $parametros$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pt23_config
        WHERE lote NOT BETWEEN 1 AND 6
           OR usuarios_por_rol NOT IN (1000, 100000)
           OR registros_por_lote <> usuarios_por_rol * 10
    ) THEN
        RAISE EXCEPTION
            'Usar lotes 1 a 6 y los parámetros de piloto (1000, 10000) o definitiva (100000, 1000000).';
    END IF;
END;
$parametros$;

-- Crear las tablas de control si todavía no existen.
CREATE SCHEMA IF NOT EXISTS pt23_dataset;

CREATE TABLE IF NOT EXISTS pt23_dataset.configuracion (
    id integer PRIMARY KEY CHECK (id = 1),
    usuarios_por_rol integer NOT NULL CHECK (usuarios_por_rol IN (1000, 100000)),
    registros_por_lote integer NOT NULL,
    version_generador integer NOT NULL CHECK (version_generador = 2),
    CHECK (registros_por_lote = usuarios_por_rol * 10)
);

CREATE TABLE IF NOT EXISTS pt23_dataset.ejecucion (
    id integer PRIMARY KEY CHECK (id = 1),
    inicio timestamptz NOT NULL,
    tutorias_iniciales bigint NOT NULL,
    base_inicial_bytes bigint NOT NULL
);

CREATE TABLE IF NOT EXISTS pt23_dataset.lotes (
    lote integer PRIMARY KEY CHECK (lote BETWEEN 1 AND 6),
    registros integer NOT NULL CHECK (registros > 0),
    inicio timestamptz NOT NULL,
    fin timestamptz NOT NULL,
    duracion interval NOT NULL
);

DO $compatibilidad$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pt23_dataset.configuracion)
       AND (
           EXISTS (SELECT 1 FROM pt23_dataset.ejecucion)
           OR EXISTS (SELECT 1 FROM pt23_dataset.lotes)
           OR EXISTS (SELECT 1 FROM public.tutorias)
       ) THEN
        RAISE EXCEPTION
            'Existen datos de una ejecución anterior. Respaldar y preparar explícitamente la base y los controles antes de iniciar el nuevo dataset.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pt23_dataset.configuracion guardada
        CROSS JOIN pt23_config solicitada
        WHERE guardada.usuarios_por_rol <> solicitada.usuarios_por_rol
           OR guardada.registros_por_lote <> solicitada.registros_por_lote
           OR guardada.version_generador <> 2
    ) THEN
        RAISE EXCEPTION
            'La configuración difiere de la ejecución iniciada. Preparar una base limpia para cambiar entre piloto y definitiva.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pt23_dataset.lotes registrado
        CROSS JOIN pt23_config solicitada
        WHERE registrado.registros <> solicitada.registros_por_lote
           OR registrado.lote NOT BETWEEN 1 AND 6
    ) THEN
        RAISE EXCEPTION
            'Los lotes registrados no corresponden al modo solicitado.';
    END IF;
END;
$compatibilidad$;

INSERT INTO pt23_dataset.configuracion (
    id, usuarios_por_rol, registros_por_lote, version_generador
)
SELECT 1, usuarios_por_rol, registros_por_lote, 2
FROM pt23_config
ON CONFLICT (id) DO NOTHING;

-- Registrar el punto de partida una sola vez.
INSERT INTO pt23_dataset.ejecucion (
    id, inicio, tutorias_iniciales, base_inicial_bytes
)
SELECT
    1,
    clock_timestamp(),
    (SELECT COUNT(*) FROM public.tutorias),
    pg_database_size(current_database())
ON CONFLICT (id) DO NOTHING;

-- Actualizar las restricciones del registro de lotes.
ALTER TABLE pt23_dataset.lotes
    DROP CONSTRAINT IF EXISTS lotes_lote_check,
    DROP CONSTRAINT IF EXISTS lotes_registros_check;

ALTER TABLE pt23_dataset.lotes
    ADD CONSTRAINT lotes_lote_check
        CHECK (lote BETWEEN 1 AND 6),
    ADD CONSTRAINT lotes_registros_check
        CHECK (registros > 0);

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
    '^(alumno|profesor)\.([1-9][0-9]{0,4}|100000)@example\.com$';

CREATE UNIQUE INDEX
    ON pt23_usuarios (rol, numero);

ANALYZE pt23_usuarios;

DO $usuarios$
DECLARE
    cantidad_usuarios integer;
BEGIN
    SELECT usuarios_por_rol INTO cantidad_usuarios FROM pt23_config;

    IF (SELECT COUNT(*) FROM pt23_usuarios) <> cantidad_usuarios * 2 THEN
        RAISE EXCEPTION
            'Se requieren exactamente % alumnos y % profesores sintéticos para este modo.',
            cantidad_usuarios, cantidad_usuarios;
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pt23_usuarios
        WHERE rol = 'alumno'
          AND estado = 'activo'
          AND numero BETWEEN 1 AND cantidad_usuarios
    ) <> cantidad_usuarios THEN
        RAISE EXCEPTION
            'Se requieren % alumnos sintéticos activos numerados desde 1.', cantidad_usuarios;
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pt23_usuarios
        WHERE rol = 'profesor'
          AND estado = 'activo'
          AND numero BETWEEN 1 AND cantidad_usuarios
    ) <> cantidad_usuarios THEN
        RAISE EXCEPTION
            'Se requieren % profesores sintéticos activos numerados desde 1.', cantidad_usuarios;
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

-- Preparar horarios con un índice para las búsquedas de la carga.
CREATE TEMP TABLE pt23_horarios ON COMMIT DROP AS
SELECT
    horario."profesorId" AS profesor_id,
    horario."diaSemana"::text AS dia_semana,
    horario."horaInicio" AS hora_inicio,
    horario."horaFin" AS hora_fin,
    horario.modalidad,
    horario.estado
FROM public.horarios_disponibles horario
JOIN pt23_usuarios profesor
    ON profesor.id = horario."profesorId"
WHERE profesor.rol = 'profesor';

CREATE UNIQUE INDEX
    ON pt23_horarios (profesor_id, dia_semana);

ANALYZE pt23_horarios;

DO $horarios$
BEGIN
    IF EXISTS (
        SELECT profesor.id
        FROM pt23_usuarios profesor
        LEFT JOIN pt23_horarios horario
            ON horario.profesor_id = profesor.id
        WHERE profesor.rol = 'profesor'
        GROUP BY profesor.id
        HAVING COUNT(horario.profesor_id) <> 4
            OR COUNT(*) FILTER (
                WHERE horario.dia_semana IN (
                    'lunes', 'martes', 'jueves', 'viernes'
                )
                  AND horario.hora_inicio = time '09:00'
                  AND horario.hora_fin = time '13:00'
                  AND horario.modalidad = 'ambas'
                  AND horario.estado = 'activo'
            ) <> 4
    ) THEN
        RAISE EXCEPTION
            'Cada profesor debe tener los cuatro horarios activos definidos para el dataset.';
    END IF;
END;
$horarios$;

DO $carga$
DECLARE
    numero_lote integer;
    cantidad_usuarios integer;
    cantidad_lote integer;
    inicio_lote timestamptz;
    fin_lote timestamptz;
    insertadas bigint;
    desde bigint;
    hasta bigint;
BEGIN
    SELECT lote, usuarios_por_rol, registros_por_lote, inicio
    INTO numero_lote, cantidad_usuarios, cantidad_lote, inicio_lote
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

    desde := (numero_lote - 1)::bigint * cantidad_lote + 1;
    hasta := numero_lote::bigint * cantidad_lote;

    WITH numeracion AS (
        SELECT
            serie.numero_global,
            1 + ((serie.numero_global - 1) % cantidad_usuarios)
                AS alumno_numero,
            (serie.numero_global - 1) / cantidad_usuarios
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

        tarifa.precio,

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
                ) % cantidad_usuarios
            )
       AND asignacion.posicion = 1 + (base.ronda % 4)
    JOIN public.categorias categoria
        ON categoria.id = asignacion.categoria_id
    JOIN public.precios tarifa
        ON tarifa.nivel::text = categoria.nivel::text
       AND tarifa.modalidad::text = base.modalidad
    JOIN pt23_horarios horario
        ON horario.profesor_id = asignacion.profesor_id
       AND horario.dia_semana =
           CASE base.ronda % 4
               WHEN 0 THEN 'lunes'
               WHEN 1 THEN 'martes'
               WHEN 2 THEN 'jueves'
               ELSE 'viernes'
           END
    CROSS JOIN LATERAL (
        SELECT
            (
                timestamp '2026-01-05 09:00:00'
                + (base.ronda / 4) * interval '7 days'
                + (
                    CASE base.ronda % 4
                        WHEN 0 THEN 0
                        WHEN 1 THEN 1
                        WHEN 2 THEN 3
                        ELSE 4
                    END
                ) * interval '1 day'
            ) AT TIME ZONE 'America/Argentina/Buenos_Aires'
            AS fecha
    ) fechas;

    GET DIAGNOSTICS insertadas = ROW_COUNT;

    IF insertadas <> cantidad_lote THEN
        RAISE EXCEPTION
            'Se esperaban % tutorías y se insertaron %.',
            cantidad_lote, insertadas;
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
