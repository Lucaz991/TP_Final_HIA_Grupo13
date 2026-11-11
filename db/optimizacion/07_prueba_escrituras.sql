-- Prueba opcional del conjunto definitivo de índices.
-- Las mediciones históricas del README usaron fecha con INCLUDE(id).
-- Ejecutar en una pestaña nueva de pgAdmin en tpFinal o tpFinal_pt24_prueba.
-- Ejecutar hasta el SELECT final y copiar las 12 filas. Ejecutar ROLLBACK aparte.
-- Si hay un error, ejecutar ROLLBACK antes de reintentar.
-- Copias temporales: ambas tienen PK y solo una tiene los cuatro índices extra.
BEGIN;

CREATE TEMP TABLE pt24_muestra ON COMMIT DROP AS
SELECT *
FROM public.tutorias
ORDER BY id
LIMIT 220000;

CREATE TEMP TABLE pt24_lote ON COMMIT DROP AS
SELECT *
FROM pg_temp.pt24_muestra
ORDER BY id
OFFSET 200000;

CREATE TEMP TABLE pt24_resultados (
    repeticion integer,
    variante text,
    operacion text,
    plan jsonb
) ON COMMIT DROP;

DO $prueba$
DECLARE
    repeticion integer;
    destino text;
    destinos text[];
    limite_actualizacion integer;
    plan_medicion jsonb;
BEGIN
    IF current_database() NOT IN ('tpFinal', 'tpFinal_pt24_prueba') OR pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Ejecutar en el líder de tpFinal o tpFinal_pt24_prueba';
    END IF;
    IF (SELECT count(*) FROM pg_temp.pt24_muestra) <> 220000 THEN
        RAISE EXCEPTION 'Se necesitan al menos 220000 tutorías';
    END IF;

    SELECT id INTO STRICT limite_actualizacion
    FROM pg_temp.pt24_muestra
    ORDER BY id
    OFFSET 9999 LIMIT 1;

    FOR repeticion IN 1..3 LOOP
        CREATE TEMP TABLE pt24_base ON COMMIT DROP AS
        SELECT * FROM pg_temp.pt24_muestra ORDER BY id LIMIT 200000;
        CREATE TEMP TABLE pt24_indices ON COMMIT DROP AS
        SELECT * FROM pg_temp.pt24_base;

        ALTER TABLE pg_temp.pt24_base ADD PRIMARY KEY (id);
        ALTER TABLE pg_temp.pt24_indices ADD PRIMARY KEY (id);
        CREATE INDEX ON pg_temp.pt24_indices ("profesorId", estado, "categoriaId");
        CREATE INDEX ON pg_temp.pt24_indices ("alumnoId");
        CREATE INDEX ON pg_temp.pt24_indices ("categoriaId");
        CREATE INDEX ON pg_temp.pt24_indices ("createdAt" DESC, id DESC);
        ANALYZE pg_temp.pt24_base;
        ANALYZE pg_temp.pt24_indices;

        -- Alternar cuál variante se mide primero.
        destinos := ARRAY['pt24_base', 'pt24_indices'];
        IF repeticion = 2 THEN
            destinos := ARRAY['pt24_indices', 'pt24_base'];
        END IF;

        FOREACH destino IN ARRAY destinos LOOP
            EXECUTE format($sql$
                EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, FORMAT JSON)
                INSERT INTO pg_temp.%I
                SELECT * FROM pg_temp.pt24_lote
                RETURNING id
            $sql$, destino) INTO plan_medicion;
            INSERT INTO pg_temp.pt24_resultados
            VALUES (repeticion, destino, 'INSERT', plan_medicion);

            EXECUTE format($sql$
                EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, FORMAT JSON)
                UPDATE pg_temp.%I
                SET "createdAt" = "createdAt" + interval '1 second'
                WHERE id <= $1
                RETURNING id
            $sql$, destino) INTO plan_medicion USING limite_actualizacion;
            INSERT INTO pg_temp.pt24_resultados
            VALUES (repeticion, destino, 'UPDATE', plan_medicion);
        END LOOP;

        DROP TABLE pg_temp.pt24_base, pg_temp.pt24_indices;
    END LOOP;
END
$prueba$;

SELECT repeticion, variante, operacion,
       (plan->0->>'Execution Time')::numeric AS ejecucion_ms,
       (plan->0->'Plan'->>'Actual Rows')::integer AS filas,
       (plan->0->'Plan'->>'Local Dirtied Blocks')::integer AS bloques_locales_ensuciados
FROM pg_temp.pt24_resultados
ORDER BY operacion, repeticion, variante;

-- Ejecutar por separado después de copiar los resultados.
-- ROLLBACK;
