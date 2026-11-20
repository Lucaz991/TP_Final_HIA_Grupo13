BEGIN;

DO $carga$
DECLARE
    cantidad CONSTANT integer := 1000;
    alumnos integer[];
    total_asignaciones bigint;
    tutorias_insertadas bigint;
    calificaciones_insertadas bigint;
BEGIN
    IF current_database() <> 'tpFinal' THEN
        RAISE EXCEPTION 'Ejecutar en tpFinal. Base actual: %', current_database();
    END IF;

    -- Protege la comprobación de tabla vacía durante la carga.
    LOCK TABLE public.tutorias IN SHARE ROW EXCLUSIVE MODE;

    IF EXISTS (SELECT 1 FROM public.tutorias) THEN
        RAISE EXCEPTION 'La carga requiere que la tabla tutorias este vacia.';
    END IF;

    SELECT array_agg(id ORDER BY id)
    INTO alumnos
    FROM public.usuarios
    WHERE rol = 'alumno'
      AND estado = 'activo';

    CREATE TEMP TABLE asignaciones_carga ON COMMIT DROP AS
    SELECT
        row_number() OVER (ORDER BY pc."profesorId", pc."categoriaId") AS numero,
        pc."profesorId",
        pc."categoriaId"
    FROM public.profesores_categorias pc
    JOIN public.usuarios profesor ON profesor.id = pc."profesorId"
    WHERE profesor.rol = 'profesor'
      AND profesor.estado = 'activo'
      AND pc.estado = 'activo';

    SELECT COUNT(*) INTO total_asignaciones FROM asignaciones_carga;

    IF alumnos IS NULL OR total_asignaciones = 0 THEN
        RAISE EXCEPTION
            'Se requiere un alumno activo y un profesor activo con una categoria asignada activa.';
    END IF;

    WITH nuevas_tutorias AS (
        INSERT INTO public.tutorias (
            "alumnoId", "profesorId", "categoriaId", "fechaHora",
            "createdAt", "updatedAt", modalidad, estado,
            "precioAcordado", pagada
        )
        SELECT
            alumnos[1 + (n - 1) % cardinality(alumnos)],
            a."profesorId",
            a."categoriaId",
            fechas.creacion + interval '1 day',
            fechas.creacion,
            fechas.creacion,
            (CASE WHEN n % 3 = 0 THEN 'presencial' ELSE 'virtual' END)
                ::public.enum_tutorias_modalidad,
            (CASE
                WHEN n % 10 < 6 THEN 'finalizada'
                WHEN n % 10 < 8 THEN 'pendiente'
                WHEN n % 10 = 8 THEN 'aceptada'
                ELSE 'rechazada'
            END)::public.enum_tutorias_estado,
            5000 + (n % 20) * 250,
            n % 10 < 6
        FROM generate_series(1, cantidad) AS serie(n)
        JOIN asignaciones_carga a
            ON a.numero = 1 + ((n - 1) / 3) % total_asignaciones
        CROSS JOIN LATERAL (
            SELECT timestamptz '2024-01-01 09:00:00-03'
                   + (n - 1) * interval '1 day' AS creacion
        ) fechas
        RETURNING id, estado
    ),
    nuevas_calificaciones AS (
        INSERT INTO public.calificaciones (
            "tutoriaId", calificacion, comentario, "createdAt", "updatedAt"
        )
        SELECT
            id,
            3 + (id % 5) % 3,
            'Calificacion sintetica',
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
        FROM nuevas_tutorias
        WHERE estado = 'finalizada'
          AND id % 3 <> 0
        RETURNING id
    )
    SELECT
        (SELECT COUNT(*) FROM nuevas_tutorias),
        (SELECT COUNT(*) FROM nuevas_calificaciones)
    INTO tutorias_insertadas, calificaciones_insertadas;

    IF tutorias_insertadas <> cantidad THEN
        RAISE EXCEPTION 'Se esperaban % tutorias y se insertaron %.',
            cantidad, tutorias_insertadas;
    END IF;

    RAISE NOTICE 'Tutorias insertadas: %. Calificaciones insertadas: %.',
        tutorias_insertadas, calificaciones_insertadas;
END;
$carga$;

COMMIT;