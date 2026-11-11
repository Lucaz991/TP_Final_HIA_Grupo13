-- PT-24 - Cargar 600000 calificaciones sintéticas por lotes.
-- Ejecutar manualmente en tpFinal, con el backend detenido y Auto-commit.
-- Una calificación cada seis tutorías finalizadas y pagadas, ordenadas por ID.
-- Puntuaciones 1 a 5 con pesos 5 %, 10 %, 20 %, 30 % y 35 %.
-- Para cambiar una selección temporal anterior, abrir otra pestaña/conexión.
-- Ejecutar este archivo completo cambiando lote en cada ejecución.
-- Predeterminado: tres lotes de 200000. También admite dos de 300000
-- o seis de 100000. Conservar total_lotes durante la carga.
-- La selección se prepara una vez por conexión y se reutiliza.
-- Si se pierde la conexión, repetir el archivo con el lote pendiente.
-- Los lotes confirmados se conservan y pueden repetirse sin duplicarlos.
-- Requiere mantener estable el dataset. No crea índices persistentes.
-- Si hay un error, ejecutar ROLLBACK en esta misma pestaña.
-- Guardar el aviso de duración y la salida final como evidencia.
-- Durante la ejecución, consultar application_name en pg_stat_activity
-- desde otra conexión para identificar la fase. Se restaura al finalizar.

BEGIN;

SET LOCAL lock_timeout = '10s';
SELECT pg_advisory_xact_lock(24000);

DO $destino$
BEGIN
    IF current_database() <> 'tpFinal' OR pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Conectarse al líder de tpFinal.';
    END IF;
END;
$destino$;

-- CAMBIAR lote de 1 a total_lotes. Para dos lotes usar total_lotes = 2.
CREATE TEMP TABLE calificaciones_config ON COMMIT DROP AS
SELECT
    1::integer AS lote,
    3::integer AS total_lotes,
    clock_timestamp() AS inicio;

DO $parametros$
BEGIN
    IF EXISTS (
        SELECT 1 FROM calificaciones_config
        WHERE total_lotes IS NULL
           OR total_lotes NOT IN (2, 3, 6)
           OR lote IS NULL
           OR lote NOT BETWEEN 1 AND total_lotes
    ) THEN
        RAISE EXCEPTION
            'Usar total_lotes igual a 2, 3 o 6 y lote entre 1 y total_lotes.';
    END IF;
END;
$parametros$;

-- Mantener estable el conjunto y evitar dos cargas simultáneas.
LOCK TABLE public.tutorias IN SHARE MODE;
LOCK TABLE public.calificaciones IN SHARE ROW EXCLUSIVE MODE;

SELECT set_config('application_name', 'PT24 calificaciones: seleccion inicial', true);

CREATE TEMP TABLE IF NOT EXISTS calificaciones_objetivo
ON COMMIT PRESERVE ROWS AS
SELECT
    numero / 6 AS numero,
    id AS tutoria_id,
    -- La permutación de 100 posiciones reparte los pesos de forma determinista.
    CASE
        WHEN ((numero / 6 - 1) * 37) % 100 < 5 THEN 1
        WHEN ((numero / 6 - 1) * 37) % 100 < 15 THEN 2
        WHEN ((numero / 6 - 1) * 37) % 100 < 35 THEN 3
        WHEN ((numero / 6 - 1) * 37) % 100 < 65 THEN 4
        ELSE 5
    END AS puntuacion,
    "fechaHora" + interval '1 hour' AS fecha
FROM (
    SELECT
        id,
        "fechaHora",
        row_number() OVER (ORDER BY id) AS numero
    FROM public.tutorias
    WHERE estado = 'finalizada'
      AND pagada
) finalizadas
WHERE numero % 6 = 0;

SELECT set_config('application_name', 'PT24 calificaciones: indices temporales', true);

CREATE UNIQUE INDEX IF NOT EXISTS calificaciones_objetivo_tutoria_id_idx
    ON calificaciones_objetivo (tutoria_id);
CREATE UNIQUE INDEX IF NOT EXISTS calificaciones_objetivo_numero_idx
    ON calificaciones_objetivo (numero);
ANALYZE calificaciones_objetivo;
ANALYZE public.calificaciones;

SELECT set_config('application_name', 'PT24 calificaciones: requisitos', true);

DO $requisitos$
BEGIN
    IF (SELECT COUNT(*) FROM calificaciones_objetivo) <> 600000 THEN
        RAISE EXCEPTION
            'Se esperaban 600000 tutorías seleccionadas. Revisar el dataset definitivo.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM calificaciones_objetivo
        WHERE puntuacion IS DISTINCT FROM
            CASE
                WHEN ((numero - 1) * 37) % 100 < 5 THEN 1
                WHEN ((numero - 1) * 37) % 100 < 15 THEN 2
                WHEN ((numero - 1) * 37) % 100 < 35 THEN 3
                WHEN ((numero - 1) * 37) % 100 < 65 THEN 4
                ELSE 5
            END
    ) THEN
        RAISE EXCEPTION
            'La selección temporal corresponde a otras puntuaciones. Ejecutar ROLLBACK y abrir otra pestaña/conexión para preparar la nueva selección.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.calificaciones existente
        LEFT JOIN calificaciones_objetivo objetivo
            ON objetivo.tutoria_id = existente."tutoriaId"
        WHERE objetivo.tutoria_id IS NULL
    ) THEN
        RAISE EXCEPTION
            'Existen calificaciones fuera del conjunto previsto. Revisarlas antes de continuar.';
    END IF;

    IF EXISTS (
        SELECT "tutoriaId"
        FROM public.calificaciones
        GROUP BY "tutoriaId"
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Existen calificaciones duplicadas por tutoría. Revisarlas antes de continuar.';
    END IF;
END;
$requisitos$;

-- Seleccionar pendientes antes de modificar la tabla de calificaciones.
-- Si la tabla está vacía, todos los registros del lote están pendientes.
SELECT set_config('application_name', 'PT24 calificaciones: pendientes', true);

DO $pendientes$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.calificaciones) THEN
        CREATE TEMP TABLE calificaciones_pendientes ON COMMIT DROP AS
        SELECT objetivo.tutoria_id, objetivo.puntuacion, objetivo.fecha
        FROM calificaciones_objetivo objetivo
        CROSS JOIN calificaciones_config configuracion
        WHERE objetivo.numero BETWEEN
                  (configuracion.lote - 1) * (600000 / configuracion.total_lotes) + 1
                  AND configuracion.lote * (600000 / configuracion.total_lotes);
    ELSE
        CREATE TEMP TABLE calificaciones_pendientes ON COMMIT DROP AS
        SELECT objetivo.tutoria_id, objetivo.puntuacion, objetivo.fecha
        FROM calificaciones_objetivo objetivo
        CROSS JOIN calificaciones_config configuracion
        WHERE objetivo.numero BETWEEN
                  (configuracion.lote - 1) * (600000 / configuracion.total_lotes) + 1
                  AND configuracion.lote * (600000 / configuracion.total_lotes)
          AND NOT EXISTS (
              SELECT 1
              FROM public.calificaciones existente
              WHERE existente."tutoriaId" = objetivo.tutoria_id
          );
    END IF;
END;
$pendientes$;

SELECT set_config('application_name', 'PT24 calificaciones: insercion', true);

DO $insercion$
DECLARE
    insertadas bigint;
BEGIN
    INSERT INTO public.calificaciones (
        "tutoriaId", calificacion, comentario, "createdAt", "updatedAt"
    )
    SELECT
        tutoria_id,
        puntuacion,
        CASE puntuacion
            WHEN 1 THEN 'Necesito una explicación más clara de los temas.'
            WHEN 2 THEN 'La clase resolvió algunas de mis dudas.'
            WHEN 3 THEN 'La explicación fue adecuada.'
            WHEN 4 THEN 'La clase fue clara y útil.'
            ELSE 'Excelente explicación y acompañamiento.'
        END,
        fecha,
        fecha
    FROM calificaciones_pendientes;

    GET DIAGNOSTICS insertadas = ROW_COUNT;
    RAISE NOTICE 'Calificaciones insertadas en este intento: %.', insertadas;
END;
$insercion$;

SELECT set_config('application_name', 'PT24 calificaciones: estadisticas', true);

ANALYZE public.calificaciones;

SELECT set_config('application_name', 'PT24 calificaciones: verificacion', true);

-- Agregar una sola vez y materializar antes de cruzar los resultados.
-- Evita verificar cada tutoría contra la tabla de calificaciones sin índice.
-- El índice siguiente es temporal y no altera la línea base de PT-24.
CREATE TEMP TABLE calificaciones_resumen ON COMMIT DROP AS
SELECT
    "tutoriaId" AS tutoria_id,
    COUNT(*) AS cantidad,
    MIN(calificacion) AS puntuacion,
    MIN("createdAt") AS fecha_creacion,
    MIN("updatedAt") AS fecha_actualizacion
FROM public.calificaciones
GROUP BY "tutoriaId";

CREATE UNIQUE INDEX ON calificaciones_resumen (tutoria_id);
ANALYZE calificaciones_resumen;

DO $verificacion$
DECLARE
    numero_lote integer;
    cantidad_lote integer;
    invalidas bigint;
    duracion interval;
BEGIN
    SELECT lote, 600000 / total_lotes
    INTO numero_lote, cantidad_lote
    FROM calificaciones_config;

    IF (
        SELECT COUNT(*)
        FROM calificaciones_objetivo
        WHERE numero BETWEEN (numero_lote - 1) * cantidad_lote + 1
                         AND numero_lote * cantidad_lote
    ) <> cantidad_lote THEN
        RAISE EXCEPTION 'La selección del lote debe contener % tutorías.', cantidad_lote;
    END IF;

    SELECT COUNT(*)
    INTO invalidas
    FROM calificaciones_objetivo objetivo
    LEFT JOIN calificaciones_resumen resumen
        ON resumen.tutoria_id = objetivo.tutoria_id
    WHERE objetivo.numero BETWEEN (numero_lote - 1) * cantidad_lote + 1
                              AND numero_lote * cantidad_lote
      AND (
          resumen.cantidad IS DISTINCT FROM 1::bigint
          OR resumen.puntuacion IS DISTINCT FROM objetivo.puntuacion
          OR resumen.fecha_creacion IS DISTINCT FROM objetivo.fecha
          OR resumen.fecha_actualizacion IS DISTINCT FROM objetivo.fecha
      );

    IF invalidas <> 0 THEN
        RAISE EXCEPTION
            'El lote contiene % calificaciones faltantes, duplicadas o con valores distintos a los esperados.',
            invalidas;
    END IF;

    SELECT clock_timestamp() - inicio INTO duracion
    FROM calificaciones_config;
    RAISE NOTICE
        'Lote % verificado (% registros). Tiempo SQL previo al COMMIT: %.',
        numero_lote, cantidad_lote, duracion;
END;
$verificacion$;

COMMIT;

SELECT
    (SELECT COUNT(*) FROM calificaciones_objetivo) AS tutorias_preparadas,
    (SELECT COUNT(*) FROM public.calificaciones) AS calificaciones_confirmadas;

-- Al completar todos los lotes, para puntuaciones 1 a 5 se esperan
-- respectivamente 30000, 60000, 120000, 180000 y 210000 filas.
SELECT calificacion, COUNT(*) AS cantidad
FROM public.calificaciones
GROUP BY calificacion
ORDER BY calificacion;
