-- Base de destino y tamaño.
SELECT
    current_database() AS base,
    pg_database_size(current_database()) AS bytes,
    pg_size_pretty(pg_database_size(current_database())) AS tamanio;

-- Cantidad total de tutorias insertadas.
SELECT
    COUNT(*) AS tutorias_totales
FROM public.tutorias;

-- Debe devolver cero después de la carga.
SELECT COUNT(*) AS tutorias_invalidas
FROM public.tutorias t
LEFT JOIN public.usuarios alumno
    ON alumno.id = t."alumnoId"
LEFT JOIN public.usuarios profesor
    ON profesor.id = t."profesorId"
LEFT JOIN public.profesores_categorias pc
    ON pc."profesorId" = t."profesorId"
   AND pc."categoriaId" = t."categoriaId"
WHERE (
      alumno.rol IS DISTINCT FROM 'alumno'
      OR profesor.rol IS DISTINCT FROM 'profesor'
      OR pc."profesorId" IS NULL
  );