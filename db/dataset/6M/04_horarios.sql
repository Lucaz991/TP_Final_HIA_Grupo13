-- Horarios disponibles del dataset.
-- Cuatro franjas semanales por profesor.
-- Ejecutar por rangos de hasta 25000 profesores.

BEGIN;

SELECT pg_advisory_xact_lock(23005);

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

-- Cambiar estos valores para cada lote.
CREATE TEMP TABLE horarios_config ON COMMIT DROP AS
SELECT
    1::integer AS desde,
    25000::integer AS hasta;

DO $rango$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM horarios_config
        WHERE desde < 1
           OR hasta > 100000
           OR hasta < desde
           OR hasta - desde + 1 > 25000
    ) THEN
        RAISE EXCEPTION
            'Rango inválido. Usar entre 1 y 100000, hasta 25000 por ejecución.';
    END IF;
END;
$rango$;

CREATE TEMP TABLE profesores_horarios ON COMMIT DROP AS
SELECT
    serie.numero,
    usuario.id AS profesor_id
FROM horarios_config configuracion
CROSS JOIN LATERAL
    generate_series(
        configuracion.desde,
        configuracion.hasta
    ) AS serie(numero)
JOIN public.usuarios usuario
    ON usuario.email =
        'profesor.' || serie.numero || '@example.com'
WHERE usuario.rol = 'profesor'
  AND usuario.estado = 'activo';

CREATE UNIQUE INDEX ON profesores_horarios (profesor_id);

ANALYZE profesores_horarios;

DO $profesores$
DECLARE
    esperados integer;
BEGIN
    SELECT hasta - desde + 1
    INTO esperados
    FROM horarios_config;

    IF (SELECT COUNT(*) FROM profesores_horarios) <> esperados THEN
        RAISE EXCEPTION
            'Faltan profesores del rango o tienen rol/estado incorrecto.';
    END IF;
END;
$profesores$;

CREATE TEMP TABLE horarios_lote ON COMMIT DROP AS
SELECT
    profesor.profesor_id,
    dias.dia::public."enum_horarios_disponibles_diaSemana"
        AS dia_semana,
    time '09:00' AS hora_inicio,
    time '13:00' AS hora_fin,
    'ambas'::public.enum_horarios_disponibles_modalidad
        AS modalidad
FROM profesores_horarios profesor
CROSS JOIN (
    VALUES ('lunes'), ('martes'), ('jueves'), ('viernes')
) AS dias(dia);

CREATE UNIQUE INDEX
    ON horarios_lote (
        profesor_id,
        dia_semana,
        hora_inicio,
        hora_fin,
        modalidad
    );

ANALYZE horarios_lote;

-- Serializar la comprobación y la inserción.
-- La tabla todavía no tiene una restricción única para estas franjas.
LOCK TABLE public.horarios_disponibles
    IN SHARE ROW EXCLUSIVE MODE;

-- Rechazar franjas existentes que se superpongan con las esperadas.
DO $superposiciones$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM horarios_lote esperado
        JOIN public.horarios_disponibles existente
            ON existente."profesorId" = esperado.profesor_id
           AND existente."diaSemana" = esperado.dia_semana
           AND existente."horaInicio" < esperado.hora_fin
           AND existente."horaFin" > esperado.hora_inicio
        WHERE existente."horaInicio" <> esperado.hora_inicio
           OR existente."horaFin" <> esperado.hora_fin
           OR existente.modalidad <> esperado.modalidad
    ) THEN
        RAISE EXCEPTION
            'Hay horarios existentes que se superponen con las franjas del dataset.';
    END IF;
END;
$superposiciones$;

INSERT INTO public.horarios_disponibles (
    "profesorId",
    "diaSemana",
    "horaInicio",
    "horaFin",
    modalidad,
    estado
)
SELECT
    esperado.profesor_id,
    esperado.dia_semana,
    esperado.hora_inicio,
    esperado.hora_fin,
    esperado.modalidad,
    'activo'::public.enum_horarios_disponibles_estado
FROM horarios_lote esperado
WHERE NOT EXISTS (
    SELECT 1
    FROM public.horarios_disponibles existente
    WHERE existente."profesorId" = esperado.profesor_id
      AND existente."diaSemana" = esperado.dia_semana
      AND existente."horaInicio" = esperado.hora_inicio
      AND existente."horaFin" = esperado.hora_fin
      AND existente.modalidad = esperado.modalidad
);

ANALYZE public.horarios_disponibles;

-- Verificar que cada franja exista exactamente una vez y esté activa.
DO $verificacion$
BEGIN
    IF EXISTS (
        SELECT
            esperado.profesor_id,
            esperado.dia_semana,
            esperado.hora_inicio,
            esperado.hora_fin,
            esperado.modalidad
        FROM horarios_lote esperado
        LEFT JOIN public.horarios_disponibles existente
            ON existente."profesorId" = esperado.profesor_id
           AND existente."diaSemana" = esperado.dia_semana
           AND existente."horaInicio" = esperado.hora_inicio
           AND existente."horaFin" = esperado.hora_fin
           AND existente.modalidad = esperado.modalidad
        GROUP BY
            esperado.profesor_id,
            esperado.dia_semana,
            esperado.hora_inicio,
            esperado.hora_fin,
            esperado.modalidad
        HAVING COUNT(existente.id) <> 1
            OR COUNT(*) FILTER (
                WHERE existente.estado = 'activo'
            ) <> 1
    ) THEN
        RAISE EXCEPTION
            'Hay horarios faltantes, duplicados o inactivos.';
    END IF;

    RAISE NOTICE 'Horarios del lote verificados correctamente.';
END;
$verificacion$;

COMMIT;

-- Conteo acumulado de horarios de profesores sintéticos.
SELECT COUNT(*) AS horarios_dataset
FROM public.horarios_disponibles horario
JOIN public.usuarios profesor
    ON profesor.id = horario."profesorId"
WHERE profesor.rol = 'profesor'
  AND profesor.email ~
      '^profesor\.([1-9][0-9]{0,4}|100000)@example\.com$';
