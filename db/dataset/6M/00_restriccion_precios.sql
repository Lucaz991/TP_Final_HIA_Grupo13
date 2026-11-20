-- PT-23 - Una tarifa base por nivel y modalidad.
-- Ejecutar en tpFinal antes de reiniciar el backend sin force.
-- Conserva los datos existentes y admite repetir la ejecución.

BEGIN;

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

LOCK TABLE public.precios IN SHARE ROW EXCLUSIVE MODE;

DO $restriccion$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.precios
        GROUP BY nivel, modalidad
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Hay tarifas duplicadas por nivel y modalidad. Revisarlas antes de continuar.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.precios'::regclass
          AND conname = 'precios_nivel_modalidad_unique'
          AND contype = 'u'
    ) THEN
        -- Reutilizar el índice creado por Sequelize si ya existe.
        IF to_regclass('public.precios_nivel_modalidad_unique') IS NOT NULL THEN
            ALTER TABLE public.precios
                ADD CONSTRAINT precios_nivel_modalidad_unique
                UNIQUE USING INDEX precios_nivel_modalidad_unique;
        ELSE
            ALTER TABLE public.precios
                ADD CONSTRAINT precios_nivel_modalidad_unique
                UNIQUE (nivel, modalidad);
        END IF;
    END IF;
END;
$restriccion$;

COMMIT;
