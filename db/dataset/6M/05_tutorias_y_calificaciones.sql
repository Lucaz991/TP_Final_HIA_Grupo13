-- CARGA UNIFICADA NUEVA: reemplaza 05_tutorias.sql y la carga separada de calificaciones.
-- No ejecutar ambos generadores. Requiere tutorias y calificaciones vacías al iniciar.
-- No borra datos. No completa datasets de la versión 3.
-- Ejecutar archivo completo con Auto-commit y backend detenido, en el líder de tpFinal.
-- Cambiar únicamente lote (1 a 6), conservando la misma configuración.
-- Definitiva: 100000 usuarios/rol, 1000000 tutorías/lote, 600000 calificaciones/lote.
-- Piloto: 1000 usuarios/rol, 10000 tutorías/lote, 6000 calificaciones/lote.
-- Un lote es atómico; un error exige ROLLBACK antes de repetirlo.
-- Las secuencias pueden tener huecos tras un rollback; no afecta a las relaciones.
-- PT-23 - Generador de tutorías para piloto o carga definitiva.
-- Piloto: 1000 usuarios por rol y seis lotes de 10000 tutorías.
-- Definitiva: 100000 usuarios por rol y seis lotes de 1000000 tutorías.
-- Destino: tpFinal.
-- Requiere usuarios @example.com, asignaciones, tarifas y horarios cargados.
-- Sesiones de una hora en el turno de cada profesor.
-- Turnos: 20 % mañana, 35 % tarde y 45 % noche.
-- Distribución creciente entre 2022 y el 16 de noviembre de 2026.
-- Mantener el backend detenido durante la carga.

BEGIN;

SET LOCAL lock_timeout = '10s';
SELECT pg_advisory_xact_lock(23004);
SELECT pg_advisory_xact_lock(24000);
LOCK TABLE public.tutorias, public.calificaciones IN SHARE ROW EXCLUSIVE MODE;
DO $calificaciones_vacias$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.tutorias)
       AND EXISTS (SELECT 1 FROM public.calificaciones) THEN
        RAISE EXCEPTION 'La carga nueva requiere calificaciones vacías.';
    END IF;
END;
$calificaciones_vacias$;

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
    version_generador integer NOT NULL CHECK (version_generador = 4),
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
           OR guardada.version_generador <> 4
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

-- Adaptar el control vacío de una versión anterior sin aceptar sus lotes.
ALTER TABLE pt23_dataset.configuracion
    DROP CONSTRAINT IF EXISTS configuracion_version_generador_check;

ALTER TABLE pt23_dataset.configuracion
    ADD CONSTRAINT configuracion_version_generador_check
        CHECK (version_generador = 4);

INSERT INTO pt23_dataset.configuracion (
    id, usuarios_por_rol, registros_por_lote, version_generador
)
SELECT 1, usuarios_por_rol, registros_por_lote, 4
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
DECLARE
    cantidad_profesores integer;
BEGIN
    SELECT usuarios_por_rol
    INTO cantidad_profesores
    FROM pt23_config;

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
                  AND horario.hora_inicio =
                      CASE
                          WHEN profesor.numero <= cantidad_profesores / 5
                              THEN time '09:00'
                          WHEN profesor.numero <= cantidad_profesores * 55 / 100
                              THEN time '14:00'
                          ELSE time '19:00'
                      END
                  AND horario.hora_fin =
                      CASE
                          WHEN profesor.numero <= cantidad_profesores / 5
                              THEN time '13:00'
                          WHEN profesor.numero <= cantidad_profesores * 55 / 100
                              THEN time '18:00'
                          ELSE time '23:00'
                      END
                  AND horario.modalidad = 'ambas'
                  AND horario.estado = 'activo'
            ) <> 4
    ) THEN
        RAISE EXCEPTION
            'Cada profesor debe tener los cuatro horarios activos correspondientes a su turno.';
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
    calificaciones_insertadas bigint;
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
    ), tutorias_insertadas AS (
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
    -- Distribuir las 60 rondas entre los cinco años.
    CROSS JOIN LATERAL (
        SELECT
            CASE
                WHEN base.ronda < 6 THEN 2022
                WHEN base.ronda < 15 THEN 2023
                WHEN base.ronda < 27 THEN 2024
                WHEN base.ronda < 42 THEN 2025
                ELSE 2026
            END AS anio,
            CASE
                WHEN base.ronda < 6 THEN base.ronda
                WHEN base.ronda < 15 THEN base.ronda - 6
                WHEN base.ronda < 27 THEN base.ronda - 15
                WHEN base.ronda < 42 THEN base.ronda - 27
                ELSE base.ronda - 42
            END AS ronda_anual,
            CASE
                WHEN base.ronda < 6 THEN 6
                WHEN base.ronda < 15 THEN 9
                WHEN base.ronda < 27 THEN 12
                WHEN base.ronda < 42 THEN 15
                ELSE 18
            END AS rondas_anuales,
            CASE WHEN base.ronda < 42 THEN 12 ELSE 11 END
                AS meses_disponibles
    ) distribucion
    CROSS JOIN LATERAL (
        SELECT
            make_date(
                distribucion.anio,
                1 + (
                    distribucion.ronda_anual
                    * distribucion.meses_disponibles
                    / distribucion.rondas_anuales
                )::integer,
                1
            ) AS inicio_mes,
            -- La última ronda corresponde al lunes 16/11/2026.
            CASE
                WHEN base.ronda = 59 THEN 1
                ELSE (
                    ARRAY[1, 2, 4, 5]
                )[1 + (base.ronda % 4)::integer]
            END AS dia_objetivo,
            (base.ronda % 4) * interval '1 hour'
                AS desplazamiento
    ) calendario
    JOIN pt23_horarios horario
        ON horario.profesor_id = asignacion.profesor_id
       AND horario.dia_semana =
           CASE calendario.dia_objetivo
               WHEN 1 THEN 'lunes'
               WHEN 2 THEN 'martes'
               WHEN 4 THEN 'jueves'
               ELSE 'viernes'
           END
    CROSS JOIN LATERAL (
        SELECT
            (
                (
                    calendario.inicio_mes
                    + CASE WHEN base.ronda = 59 THEN 14 ELSE 0 END
                    + (
                        (
                            calendario.dia_objetivo
                            - EXTRACT(
                                ISODOW FROM calendario.inicio_mes
                            )::integer
                            + 7
                        ) % 7
                    )
                ) + horario.hora_inicio + calendario.desplazamiento
            ) AT TIME ZONE 'America/Argentina/Buenos_Aires'
            AS fecha
    ) fechas
    RETURNING id, estado, pagada, "fechaHora"
    ), finalizadas AS (
        -- Solo ordena las finalizadas del lote recién insertado.
        -- No depende del orden de salida de RETURNING ni de IDs sin huecos.
        SELECT id, "fechaHora", row_number() OVER (ORDER BY id) AS numero
        FROM tutorias_insertadas
        WHERE estado = 'finalizada' AND pagada
    ), puntuadas AS (
        SELECT id, "fechaHora",
            CASE
                WHEN ((numero - 1) * 37) % 100 < 5 THEN 1
                WHEN ((numero - 1) * 37) % 100 < 15 THEN 2
                WHEN ((numero - 1) * 37) % 100 < 35 THEN 3
                WHEN ((numero - 1) * 37) % 100 < 65 THEN 4
                ELSE 5
            END AS puntuacion
        FROM finalizadas
    ), calificaciones_nuevas AS (
        INSERT INTO public.calificaciones (
            "tutoriaId", calificacion, comentario, "createdAt", "updatedAt"
        )
        SELECT id, puntuacion,
            CASE puntuacion
                WHEN 1 THEN 'Necesito una explicación más clara de los temas.'
                WHEN 2 THEN 'La clase resolvió algunas de mis dudas.'
                WHEN 3 THEN 'La explicación fue adecuada.'
                WHEN 4 THEN 'La clase fue clara y útil.'
                ELSE 'Excelente explicación y acompañamiento.'
            END,
            "fechaHora" + interval '1 hour',
            "fechaHora" + interval '1 hour'
        FROM puntuadas
        RETURNING id
    )
    SELECT (SELECT count(*) FROM tutorias_insertadas),
           (SELECT count(*) FROM calificaciones_nuevas)
    INTO insertadas, calificaciones_insertadas;

    IF calificaciones_insertadas <> cantidad_lote::bigint * 6 / 10 THEN
        RAISE EXCEPTION 'Se esperaban % calificaciones y se insertaron %.',
            cantidad_lote::bigint * 6 / 10, calificaciones_insertadas;
    END IF;
    RAISE NOTICE 'Calificaciones insertadas en lote %: %.',
        numero_lote, calificaciones_insertadas;

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

-- Totales esperados según los lotes confirmados (sin escanear tablas completas).
SELECT SUM(registros) AS tutorias_confirmadas,
       SUM(registros)::bigint * 6 / 10 AS calificaciones_confirmadas_esperadas
FROM pt23_dataset.lotes;

-- Ejecutar UNA VEZ al terminar los seis lotes:
-- ANALYZE public.tutorias;
-- ANALYZE public.calificaciones;
-- SELECT calificacion, count(*) FROM public.calificaciones
-- GROUP BY calificacion ORDER BY calificacion;
-- Definitiva: 1=180000, 2=360000, 3=720000, 4=1080000, 5=1260000.
