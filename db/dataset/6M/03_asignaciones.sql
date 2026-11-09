-- PT-23 - Asignaciones profesor-categoría.
-- Cuatro categorías distintas por profesor sintético.
-- Primer lote: profesores 1 a 10000.

BEGIN;

SELECT pg_advisory_xact_lock(23003);

DO $validacion$
BEGIN
    IF current_database() <> 'tpFinal' THEN
        RAISE EXCEPTION 'Ejecutar únicamente en tpFinal.';
    END IF;

    IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Conectarse al nodo líder.';
    END IF;
END;
$validacion$;

-- Cambiar estos valores para cada lote.
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
        RAISE EXCEPTION 'Rango inválido.';
    END IF;
END;
$rango$;

-- Obtener los profesores por su email único.
CREATE TEMP TABLE pt23_profesores_lote ON COMMIT DROP AS
SELECT
    serie.numero,
    usuario.id AS profesor_id
FROM pt23_rango rango
CROSS JOIN LATERAL
    generate_series(rango.desde, rango.hasta) AS serie(numero)
JOIN public.usuarios usuario
    ON usuario.email =
        'profesor.' || serie.numero || '@example.invalid'
WHERE usuario.rol = 'profesor'
  AND usuario.estado = 'activo';

CREATE UNIQUE INDEX
    ON pt23_profesores_lote (numero);

-- Numerar las categorías sin depender de IDs consecutivos.
CREATE TEMP TABLE pt23_categorias ON COMMIT DROP AS
SELECT
    id AS categoria_id,
    row_number() OVER (ORDER BY id) AS numero
FROM public.categorias;

CREATE UNIQUE INDEX ON pt23_categorias (numero);

DO $requisitos$
DECLARE
    esperados integer;
BEGIN
    SELECT hasta - desde + 1
    INTO esperados
    FROM pt23_rango;

    IF (SELECT COUNT(*) FROM pt23_profesores_lote) <> esperados THEN
        RAISE EXCEPTION
            'Faltan profesores del rango o tienen rol/estado incorrecto.';
    END IF;

    IF (SELECT COUNT(*) FROM pt23_categorias) < 4 THEN
        RAISE EXCEPTION 'Se necesitan al menos cuatro categorías.';
    END IF;
END;
$requisitos$;

-- Crear cuatro pares distintos por profesor.
CREATE TEMP TABLE pt23_asignaciones_lote ON COMMIT DROP AS
SELECT
    profesor.profesor_id,
    categoria.categoria_id
FROM pt23_profesores_lote profesor
CROSS JOIN generate_series(0, 3) AS posicion(numero)
JOIN pt23_categorias categoria
    ON categoria.numero =
        1 + (
            (profesor.numero::bigint - 1 + posicion.numero)
            % (SELECT COUNT(*) FROM pt23_categorias)
        );

CREATE UNIQUE INDEX
    ON pt23_asignaciones_lote (profesor_id, categoria_id);

ANALYZE pt23_asignaciones_lote;

INSERT INTO public.profesores_categorias (
    "profesorId",
    "categoriaId",
    estado,
    "createdAt",
    "updatedAt"
)
SELECT
    profesor_id,
    categoria_id,
    'activo'::public.enum_profesores_categorias_estado,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM pt23_asignaciones_lote
ON CONFLICT ("profesorId", "categoriaId") DO NOTHING;

ANALYZE public.profesores_categorias;

DO $verificacion$
DECLARE
    invalidas bigint;
BEGIN
    SELECT COUNT(*)
    INTO invalidas
    FROM pt23_asignaciones_lote esperado
    LEFT JOIN public.profesores_categorias asignacion
        ON asignacion."profesorId" = esperado.profesor_id
       AND asignacion."categoriaId" = esperado.categoria_id
    WHERE asignacion."profesorId" IS NULL
       OR asignacion.estado IS DISTINCT FROM
          'activo'::public.enum_profesores_categorias_estado;

    IF invalidas <> 0 THEN
        RAISE EXCEPTION
            'Hay % asignaciones faltantes o inactivas.', invalidas;
    END IF;

    RAISE NOTICE 'Lote de asignaciones verificado correctamente.';
END;
$verificacion$;

COMMIT;

-- Conteo total, incluyendo las asignaciones previas.
SELECT COUNT(*) AS asignaciones_totales
FROM public.profesores_categorias;
