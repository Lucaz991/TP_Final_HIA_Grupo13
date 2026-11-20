-- Tamaño actual por índice, en bytes y formato legible.
SELECT t.relname AS tabla,
       i.relname AS indice,
       x.indisvalid AS valido,
       x.indisready AS listo,
       pg_relation_size(i.oid) AS bytes,
       pg_size_pretty(pg_relation_size(i.oid)) AS tamano,
       pg_get_indexdef(i.oid) AS definicion
FROM pg_index x
JOIN pg_class i ON i.oid = x.indexrelid
JOIN pg_class t ON t.oid = x.indrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'public'
  AND t.relname IN ('tutorias', 'calificaciones', 'horarios_disponibles')
ORDER BY t.relname, i.relname;

SELECT pg_database_size(current_database()) AS base_bytes,
       pg_size_pretty(pg_database_size(current_database())) AS tamano;
