-- PT-24. Seis índices definitivos. Ejecutar una sola vez después del dataset.
-- Base de pruebas, con backend detenido y sin otras cargas concurrentes.
-- Ejecutar el archivo completo. La creación es transaccional y toma bloqueos
-- de escritura durante la construcción. Si falla, ejecutar ROLLBACK.
-- En una instalación que ya tiene estos seis índices, pasar a 06 para verificarlos.
BEGIN;
DO $destino$
BEGIN
    IF current_database() NOT IN ('tpFinal', 'tpFinal_pt24_prueba') OR pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Ejecutar en el líder de tpFinal o tpFinal_pt24_prueba';
    END IF;
END
$destino$;

-- Q01, Q02 y Q04 comparten el prefijo profesor.
CREATE INDEX tutorias_profesor_estado_categoria
ON public.tutorias ("profesorId", estado, "categoriaId");

-- Q02 combina las ramas de alumno y profesor mediante BitmapOr.
CREATE INDEX tutorias_alumno ON public.tutorias ("alumnoId");

-- Q03 cuenta las tutorías de una categoría.
CREATE INDEX tutorias_categoria ON public.tutorias ("categoriaId");

-- Q01 busca las opiniones de las tutorías seleccionadas.
CREATE INDEX calificaciones_tutoria ON public.calificaciones ("tutoriaId");

-- Q05 y Q08 acceden a horarios por profesor.
CREATE INDEX horarios_profesor ON public.horarios_disponibles ("profesorId");

-- Q06 usa el rango anual. Q07 pagina por fecha y desempata con ID.
CREATE INDEX tutorias_creada_id ON public.tutorias ("createdAt" DESC, id DESC);
COMMIT;
