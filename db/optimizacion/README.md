# PT-24 — Optimización de consultas SQL

La entrega crea seis índices definitivos y proporciona ocho consultas para medir el rendimiento. Q06 usa un rango anual y Q07 selecciona una página de 100 tutorías antes de cargar las asociaciones. El informe conserva las mediciones del listado completo y las pruebas que llevaron a esta selección.

## Instalar después del dataset

1. Completar los scripts de db/dataset/6M y levantar el esquema de la aplicación. Mantener el backend detenido durante la creación de índices y las mediciones.
2. Para cargas nuevas, usar [05_tutorias_y_calificaciones.sql](../dataset/6M/05_tutorias_y_calificaciones.sql) según [las instrucciones del dataset](../dataset/6M/README.md). La versión 4 genera conjuntamente 6.000.000 de tutorías y 3.600.000 calificaciones. Verificar las calificaciones y ejecutar `ANALYZE public.calificaciones` antes de medir. El script separado `00_preparar_calificaciones.sql` fue retirado; no hace falta una segunda carga de calificaciones. El generador unificado no completa datasets anteriores.
3. Ejecutar 03_indices.sql completo una sola vez. Crea los seis índices con los nombres definitivos dentro de una transacción. El archivo puede bloquear escrituras mientras construye los índices. Ante un error ejecutar ROLLBACK y revisar el mensaje. Las instalaciones que ya tienen el conjunto final pueden verificarlo con 06_tamanos_indices.sql.
4. Ejecutar por separado las dos consultas de 05_validaciones.sql. Para Q06 se esperan cero diferencias. Para Q07 se espera 100 | 100 | true.
5. Ejecutar cada bloque de 04_mediciones_posteriores.sql tres veces y conservar los planes. Q07 mide la primera página. Los parámetros principales son alumno 1, profesor 10001 y categoría 1. Verificarlos en 01_consultas_originales.sql al reproducir en otra instalación.
6. Ejecutar por separado los SELECT de 06_tamanos_indices.sql para registrar los tamaños de índices y de la base.

03 crea índices. Los archivos de consultas documentan y miden el SQL. La integración de la paginación y del rango anual en los controladores requiere un cambio del backend.

## Verificación adicional opcional en una copia del dataset

La ejecución actual se realizó en tpFinal. Crear una copia permite comprobar la instalación desde cero cuando se necesite reproducirla. Esta comprobación adicional queda sin ejecutar. La prueba de escritura del conjunto final se completó en tpFinal con tablas temporales y se documenta más abajo.

Crear un respaldo completo de tpFinal en formato Custom desde pgAdmin. Crear una base vacía llamada tpFinal_pt24_prueba y restaurar allí el respaldo con esquema, datos e índices. Esto reproduce los datos e IDs usados en las mediciones. La copia requiere espacio adicional para el dataset y sus índices. El backend puede permanecer detenido durante la verificación para reducir actividad concurrente.

El respaldo contiene los índices actuales. Para comprobar su creación desde cero, retirar únicamente los seis índices secundarios en la copia después de verificar current_database() = 'tpFinal_pt24_prueba'. Conservar las PK y restricciones únicas. Eliminar allí tutorias_profesor_estado_categoria, tutorias_alumno, tutorias_categoria, tutorias_creada_id, calificaciones_tutoria y horarios_profesor.

En el Query Tool de la copia, ejecutar 03_indices.sql completo, las dos sentencias de 05_validaciones.sql y los dos SELECT de 06_tamanos_indices.sql por separado. Registrar los estados, definiciones y resultados. El resultado esperado de Q06 es cero diferencias y el de Q07 es 100 | 100 | true. Como se reutiliza el dataset respaldado, la carga de calificaciones se considera ya realizada.

Después ejecutar 07_prueba_escrituras.sql hasta su SELECT final, guardar las 12 filas y ejecutar ROLLBACK. La prueba utiliza los cuatro índices finales de tutorías, incluido el compuesto por fecha e ID. Conservar las mediciones históricas y documentar este nuevo conjunto de resultados con el nombre de la base de prueba.

La copia permitiría comprobar la instalación y las validaciones consolidadas sobre el dataset respaldado.

## Reproducir el análisis

00_diagnostico.sql registra configuración, índices, cardinalidad y almacenamiento. 01_consultas_originales.sql documenta la línea base reconstruida desde los controladores. 02_mediciones_iniciales.sql mide esa base antes de instalar 03 en una instalación nueva. En una instalación ya optimizada, su resultado debe identificarse como ejecución con los índices actuales.

07_prueba_escrituras.sql es una prueba opcional con copias temporales y los cuatro índices finales de tutorías. Ejecutar hasta el SELECT final, copiar sus 12 filas y ejecutar ROLLBACK en la misma pestaña. El informe conserva las mediciones anteriores a la sustitución y la ejecución del conjunto final del 11/11/2026.

Los CSV existentes quedan a cargo del responsable. El README conserva tablas de mediciones y resúmenes de planes.

## Índices definitivos

| Índice | Tabla y claves | Consultas |
| --- | --- | --- |
| tutorias_profesor_estado_categoria | tutorias(profesorId, estado, categoriaId) | Q01, Q02, Q04 |
| tutorias_alumno | tutorias(alumnoId) | Q02 |
| tutorias_categoria | tutorias(categoriaId) | Q03 |
| calificaciones_tutoria | calificaciones(tutoriaId) | Q01 |
| horarios_profesor | horarios_disponibles(profesorId) | Q05, Q08 |
| tutorias_creada_id | tutorias(createdAt DESC, id DESC) | Q06, Q07 paginada |

## Método de medición

Se usó EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF, FORMAT JSON). Se compara Execution Time mediante medianas y se informa Planning Time por separado. Q01 y Q02 conservan cinco muestras iniciales y tres posteriores. Q03 a Q08 tienen tres muestras por etapa. Las condiciones de caché varían y se conservan todas las muestras. Los bloques Shared Read corresponden a lecturas hacia los buffers de PostgreSQL y pueden provenir de la caché del sistema operativo.

El contexto registrado es tpFinal, PostgreSQL 16, zona Etc/UTC, año 2026 y work_mem de 4MB. La aplicación quedó detenida durante las pruebas manuales. Los resultados de Q07 completa y de su primera página se presentan con su alcance respectivo.

## Conjunto de prueba y parámetros

El dataset preparado contiene 6.000.000 de tutorías, 200.002 usuarios, 100 categorías, 10 precios, 400.000 asignaciones profesor/categoría y 400.000 horarios. Las mediciones históricas de este informe utilizaron 600.000 calificaciones para evaluar los JOIN con opiniones. La nueva carga unificada prevé 3.600.000 calificaciones, una por cada tutoría finalizada y pagada. Es necesario volver a medir planes, tiempos y tamaños con ese volumen; los resultados históricos no se trasladan automáticamente al nuevo dataset. Las tablas auxiliares de solicitudes, respuestas y auditorías no forman parte de las consultas seleccionadas.

| Parámetro | Valor |
| --- | --- |
| Base de datos | `tpFinal` |
| Alumno | ID 1 — `alumno.1@example.com` |
| Profesor principal, turno mañana | ID 10001 — `profesor.1@example.com` |
| Profesor de referencia, turno tarde | ID 50005 — `profesor.20001@example.com` |
| Profesor de referencia, turno noche | ID 115011 — `profesor.55001@example.com` |
| Categoría principal | ID 1 |
| Categorías de los profesores de referencia | 1, 2, 3 y 4 |

La carga de calificaciones conserva una distribución prevista de 5 %, 10 %, 20 %, 30 % y 35 % para las puntuaciones de 1 a 5. En la nueva carga definitiva corresponde a 180.000, 360.000, 720.000, 1.080.000 y 1.260.000 filas, respectivamente. Adjuntar los conteos reales y especificar la versión del dataset utilizada en cada medición.

## Consultas seleccionadas

Los textos completos y los filtros exactos están en [01_consultas_originales.sql](01_consultas_originales.sql).

| ID | Consulta | Origen en el backend | Aspecto a evaluar |
| --- | --- | --- | --- |
| Q01 | Tutorías finalizadas de un profesor con calificación y alumno | `usuario.controller.js`, `getUsuarios` | Filtros y JOIN; consulta repetida por profesor |
| Q02 | Contar tutorías relacionadas con un usuario | `admin.controller.js`, `deleteUser` | Condición OR entre alumno y profesor |
| Q03 | Contar tutorías de una categoría | `admin.controller.js`, `deleteCategory` | Selectividad e índice por categoría |
| Q04 | Buscar tutoría activa de profesor/categoría | `categoria.controller.js`, `desasociarProfesor` | Filtros combinados y LIMIT 1 |
| Q05 | Horarios activos de un profesor | `horarioDisponible.controller.js`, `getHorariosProfesor` | Filtro por profesor y estado |
| Q06 | Cantidad mensual de tutorías creadas en el año actual | `admin.controller.js`, `getTutorialsByMonth` | EXTRACT sobre la columna y agrupación |
| Q07 | Listado administrativo completo y ordenado con asociaciones | `admin.controller.js`, `getFullTutorials` | Volumen, JOIN y ordenamiento |
| Q08 | Profesores con categorías y horarios | `usuario.controller.js`, `getUsuarios` | Multiplicación de filas de las asociaciones |

Q01 mide una consulta individual; no mide el costo completo del patrón N+1 de la galería. Q08 puede producir 16 filas por profesor con cuatro categorías y cuatro horarios antes de la reconstrucción de objetos de Sequelize. Q04 no tiene ORDER BY: se evalúa la existencia de resultados, no que siempre se devuelva el mismo ID. Agregar paginación a Q07 cambiaría el comportamiento y debe evaluarse como una decisión funcional separada.

## Evidencia histórica de diagnóstico y mediciones

Las secciones siguientes conservan la secuencia de medición y las hipótesis iniciales. La instalación utiliza los archivos y el conjunto definitivo descritos al inicio.

### Diagnóstico inicial

Los conteos estimados en cero se corrigieron ejecutando ANALYZE sobre las tablas cargadas. Las estimaciones de estadísticas no sustituyen los conteos exactos: por ejemplo, 5.999.908 tutorías estimadas es compatible con un conteo real de 6.000.000.

El inventario inicial mostró claves primarias y restricciones únicas, pero no índices secundarios por profesor o categoría en tutorías ni por `tutoriaId` en calificaciones. La clave primaria de `profesores_categorias` es compuesta por profesor y categoría. Los usuarios tienen unicidad de email; categorías y precios tienen restricciones únicas compuestas.

| Parámetro observado | Valor inicial |
| --- | --- |
| shared_buffers | 128 MiB |
| work_mem | 4 MiB |
| maintenance_work_mem | 64 MiB |
| effective_cache_size | 4 GiB |
| max_connections | 500 |
| max_parallel_workers_per_gather | 2 |
| max_parallel_workers | 8 |
| jit | on |
| track_io_timing | off |
| random_page_cost / seq_page_cost | 4 / 1 |

`effective_cache_size` es una estimación para el planificador, no memoria reservada. `work_mem` se aplica por operación y puede multiplicarse con operaciones y trabajadores concurrentes. No se propone aumentar estos valores sin medir recursos y concurrencia.

`pg_stat_statements` estaba disponible pero sin instalar, y `shared_preload_libraries` estaba vacío. Por ahora se utilizan los planes EXPLAIN de pgAdmin como herramienta de análisis. Falta completar la evaluación de herramientas agregadas y parámetros del motor. Actualizar el inventario de tamaños tras la carga de calificaciones para establecer la base de comparación de almacenamiento.

## Q01 — Mediciones iniciales

Profesor ID 10001 y estado `finalizada`. Las cinco ejecuciones devolvieron 36 filas.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read |
| --- | ---: | ---: | ---: | ---: |
| R1 | 24.944 | 28485.065 | 15847 | 129846 |
| R2 | 11.754 | 20764.279 | 15847 | 129846 |
| R3 | 3.085 | 10256.920 | 15944 | 129749 |
| R4 | 5.378 | 11285.209 | 15942 | 129751 |
| R5 | 22.413 | 12895.956 | 16049 | 129644 |

**Mediana inicial: 12895.956 ms (12,896 s).** Mínimo: 10256.920 ms. Máximo: 28485.065 ms. No hubo bloques temporales leídos ni escritos en estas ejecuciones.

R1 a R3 corresponden a las evidencias identificadas como tales. Los dos planes pegados posteriormente se registran como R4 y R5 en el orden recibido; no se confirmó su orden cronológico. Los tiempos comunicados manualmente de 15,506 s y 11,709 s no coinciden con los `Execution Time` de esos planes, por lo que no se utilizan para calcular la mediana. Se prioriza la evidencia del plan.

### Análisis del plan

- Gather con dos trabajadores paralelos planificados y lanzados.
- Recorrido paralelo de las 6.000.000 de tutorías para obtener 36 coincidencias. El plan muestra aproximadamente 1.999.988 filas descartadas por cada uno de los tres participantes.
- Recorrido paralelo de las 600.000 calificaciones y Hash Join con las tutorías seleccionadas.
- Acceso al alumno por `usuarios_pkey`, repetido 36 veces.
- Estimación de 37 filas frente a 36 reales: la cardinalidad final está bien estimada; el costo principal está en el volumen recorrido.
- La variación de tiempos exige conservar varias muestras y repetir el mismo procedimiento después de optimizar.

Como candidatos se evaluarán un índice de tutorías por profesor/estado y otro de calificaciones por `tutoriaId`. Un índice parcial para tutorías finalizadas es una alternativa que debe compararse con el índice compuesto según su utilidad para las otras consultas. No se consideran incorporados ni se afirma una mejora hasta disponer de mediciones posteriores.

## Q02 — Mediciones iniciales

Conteo de tutorías donde `"alumnoId" = 1 OR "profesorId" = 1`. Los cinco planes se registran en el orden recibido; no se identificó un plan separado como calentamiento.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read |
| --- | ---: | ---: | ---: | ---: |
| R1 | 6.286 | 14885.974 | 12938 | 125138 |
| R2 | 1.408 | 12415.807 | 12982 | 125094 |
| R3 | 0.236 | 10535.828 | 13078 | 124998 |
| R4 | 2.228 | 10010.540 | 13174 | 124902 |
| R5 | 0.668 | 10411.135 | 13270 | 124806 |

**Mediana inicial: 10535.828 ms (10,536 s).** Mínimo: 10010.540 ms. Máximo: 14885.974 ms. No se registraron bloques temporales ni bloques compartidos escritos o ensuciados durante la ejecución.

### Análisis y evidencia del plan

Los cinco planes tienen la misma estructura, que se conserva aquí en forma resumida con los valores de R3, la muestra de la mediana:

```text
Finalize Aggregate (actual rows=1 loops=1)
  Gather (workers planned=2, launched=2; actual rows=3 loops=1)
    Partial Aggregate (actual rows=1 loops=3)
      Parallel Seq Scan on tutorias
        Filter: (("alumnoId" = 1) OR ("profesorId" = 1))
        Estimated rows=50; actual rows=20 loops=3
        Rows Removed by Filter=1999980
Planning Time: 0.236 ms
Execution Time: 10535.828 ms
Shared Hit Blocks: 13078
Shared Read Blocks: 124998
Temp Read/Written Blocks: 0/0
JIT: 14 functions; inlining=false; optimization=false;
     expressions=true; deforming=true
Settings: {}
```

El recorrido paralelo examina las 6.000.000 de tutorías, aunque solo encuentra aproximadamente 60 coincidencias (20 filas por cada uno de los tres participantes). El agregado devuelve una fila con el conteo: `Actual Rows = 1` en la raíz no significa que el conteo sea 1. EXPLAIN no muestra el valor escalar del COUNT; confirmar ese valor con la consulta si se necesita documentarlo exactamente.

La selectividad observada es aproximadamente 0,001%. Los valores de filas en nodos paralelos son promedios por ejecución y pueden estar redondeados. La estimación del recorrido es de 50 filas por participante frente a 20 observadas. El plan no utiliza índices para el filtro y no contiene JOIN ni ordenamientos.

Se evaluarán índices que permitan acceder por `alumnoId` y por `profesorId`, con la posibilidad de que PostgreSQL los combine mediante BitmapOr. Un único índice compuesto por alumno/profesor no resuelve automáticamente ambas ramas del OR. La elección debe coordinarse con los índices candidatos de Q01 para evitar redundancias. Todavía no se incorporaron ni midieron estos índices.

## Q03 — Mediciones iniciales

Conteo de tutorías con `"categoriaId" = 1`. Tres ejecuciones consecutivas en el orden recibido, sin calentamiento adicional.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read |
| --- | ---: | ---: | ---: | ---: |
| R1 | 7.057 | 14855.935 | 13366 | 124710 |
| R2 | 1.133 | 7495.764 | 13462 | 124614 |
| R3 | 0.898 | 8451.313 | 13558 | 124518 |

**Mediana inicial: 8451.313 ms (8,451 s).** Mínimo: 7495.764 ms. Máximo: 14855.935 ms. En las tres ejecuciones no hubo bloques temporales ni bloques compartidos escritos o ensuciados.

### Análisis y evidencia del plan

Los tres planes tienen la misma estructura. Resumen de R3, correspondiente a la mediana:

```text
Finalize Aggregate (estimated rows=1; actual rows=1 loops=1)
  Gather (workers planned=2, launched=2; actual rows=3 loops=1)
    Partial Aggregate (actual rows=1 loops=3)
      Parallel Seq Scan on tutorias
        Filter: ("categoriaId" = 1)
        Estimated rows=27000; actual rows=20000 loops=3
        Rows Removed by Filter=1980000
Planning Time: 0.898 ms
Execution Time: 8451.313 ms
Shared Hit Blocks: 13558
Shared Read Blocks: 124518
Temp Read/Written Blocks: 0/0
JIT: 14 functions; inlining=false; optimization=false;
     expressions=true; deforming=true
Settings: {}
```

El plan recorre las 6.000.000 de tutorías para seleccionar aproximadamente 60.000, con una selectividad observada cercana al 1%. Cada uno de los tres participantes devuelve en promedio 20.000 filas y descarta 1.980.000. Los valores por participante pueden estar redondeados; el plan no muestra el valor escalar final del COUNT, que debe consultarse por separado si se necesita confirmar exactamente el resultado.

La estimación del recorrido es de 27.000 filas por participante frente a 20.000 reales. No hay JOIN ni ordenamientos. El filtro es una igualdad directa sobre la columna, por lo que admite acceso mediante índice; actualmente se usa un recorrido secuencial paralelo.

Se evaluará un índice B-tree por `categoriaId`. Podría permitir un recorrido de índice o solo de índice para este COUNT; el segundo depende también de la visibilidad de las páginas. Se comprobarán el plan elegido, los accesos al heap, el tiempo y el tamaño del índice antes de decidir su incorporación. La diferencia entre R1 y las siguientes ejecuciones no se atribuye exclusivamente a caché sin evidencia adicional.

## Q04 — Mediciones iniciales

Búsqueda de una tutoría del profesor ID 10001, categoría ID 1, con estado `pendiente` o `aceptada`, mediante LIMIT 1 y sin ORDER BY. Tres ejecuciones consecutivas registradas en el orden recibido.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Filas descartadas por participante (promedio) |
| --- | ---: | ---: | ---: | ---: | ---: |
| R1 | 38.699 | 5658.000 | 20 | 64766 | 938716 |
| R2 | 1.120 | 9111.589 | 156 | 40784 | 592834 |
| R3 | 0.628 | 6324.815 | 13459 | 32626 | 667728 |

**Mediana inicial: 6324.815 ms (6,325 s).** Mínimo: 5658.000 ms. Máximo: 9111.589 ms. Las tres ejecuciones devolvieron una fila. No hubo bloques temporales ni bloques compartidos escritos o ensuciados.

### Análisis y evidencia del plan

Los tres planes tienen la misma estructura. Resumen de R3, la muestra de la mediana:

```text
Limit (estimated rows=1; actual rows=1 loops=1)
  Gather (workers planned=2, launched=2; actual rows=1 loops=1)
    Parallel Seq Scan on tutorias t
      Filter: estado = ANY ('{pendiente,aceptada}'::enum_tutorias_estado[])
              AND "profesorId" = 10001 AND "categoriaId" = 1
      Estimated rows=1; actual rows=1 loops=3
      Rows Removed by Filter=667728
Planning Time: 0.628 ms
Execution Time: 6324.815 ms
Shared Hit Blocks: 13459
Shared Read Blocks: 32626
Temp Read/Written Blocks: 0/0
JIT: 7 functions; inlining=false; optimization=false;
     expressions=true; deforming=true
Settings: {}
```

LIMIT interrumpe el recorrido al recibir una coincidencia; estos planes no recorren necesariamente toda la tabla. Los descartes acumulados aproximados son 2.816.148 en R1, 1.778.502 en R2 y 2.003.184 en R3, calculados a partir del promedio informado por los tres participantes. Los valores por ejecución pueden estar redondeados. Las filas encontradas por los participantes no equivalen a filas entregadas al cliente: la raíz devuelve solamente una.

La cantidad de páginas recorridas varía entre ejecuciones. Sin ORDER BY no hay una fila determinada que deba devolverse, y la ejecución paralela puede detenerse en momentos distintos. Menos bloques leídos no garantizan menor tiempo: R2 leyó menos bloques que R1 y tardó más. No se atribuye esta variación a una sola causa a partir de estos planes.

Se evaluará un índice compuesto por profesor, categoría y estado, y como alternativa un índice parcial por profesor/categoría para estados pendiente o aceptada. La elección se coordinará con Q01 y Q02 para evitar índices redundantes. Para validar equivalencia se comprobará que la fila devuelta satisfaga los filtros y que se preserve la existencia de resultados, sin exigir el mismo ID. No se estima la selectividad total a partir de este recorrido interrumpido.

## Q05 — Mediciones iniciales

Horarios del profesor ID 10001 con estado `activo`. Tres ejecuciones consecutivas, sin calentamiento adicional, en el orden recibido.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Filas devueltas |
| --- | ---: | ---: | ---: | ---: | ---: |
| R1 | 17.396 | 3001.486 | 0 | 3334 | 4 |
| R2 | 0.620 | 437.276 | 3334 | 0 | 4 |
| R3 | 0.132 | 136.826 | 3334 | 0 | 4 |

**Mediana inicial: 437.276 ms (0,437 s).** Mínimo: 136.826 ms. Máximo: 3001.486 ms. No hubo bloques temporales ni bloques compartidos escritos o ensuciados.

### Análisis y evidencia del plan

Los tres planes tienen la misma estructura. Resumen de R2, la muestra de la mediana:

```text
Gather (estimated rows=4; actual rows=4 loops=1)
  Workers Planned: 2; Workers Launched: 2
  Parallel Seq Scan on horarios_disponibles h
    Filter: ("profesorId" = 10001)
            AND (estado = 'activo'::enum_horarios_disponibles_estado)
    Estimated rows=2; actual rows=1 loops=3
    Rows Removed by Filter=133332
Planning Time: 0.620 ms
Execution Time: 437.276 ms
Shared Hit Blocks: 3334
Shared Read Blocks: 0
Temp Read/Written Blocks: 0/0
Settings: {}
```

El recorrido secuencial paralelo examina los 400.000 horarios para devolver cuatro, una selectividad de 0,001%. La estimación en la raíz coincide con las cuatro filas reales. El nodo de recorrido informa promedios redondeados por participante: `actual rows=1 loops=3` no contradice las cuatro filas entregadas por Gather. No hay JOIN ni ordenamientos.

R1 registra 3.334 bloques leídos hacia los buffers y ningún acierto; R2 y R3 registran esos 3.334 bloques como aciertos y ninguna lectura. Esto evidencia un cambio de residencia de las páginas en los buffers. Aun con los mismos contadores de buffers, R2 y R3 tienen tiempos diferentes, por lo que la caché no explica por sí sola toda la variación. Se conservan las tres muestras, incluida R1, según el método acordado.

Se evaluará un índice por `profesorId` frente a uno compuesto por profesor/estado. Como todos los horarios del dataset están activos, el estado aporta poca selectividad adicional en este conjunto y un índice parcial por estado activo no reduciría sustancialmente sus entradas. La decisión final dependerá de los planes, tiempos y tamaños medidos. La consulta devuelve todas las columnas: un índice simple no garantiza un recorrido solo de índice.

## Q06 — Mediciones iniciales

Cantidad de tutorías por mes de creación dentro del año de NOW(), usando `createdAt`. Tres ejecuciones consecutivas, sin calentamiento adicional, en el orden de los planes recibidos. Los planes no incluyen el valor del año ni la zona horaria: falta adjuntar esos valores del bloque de contexto para fijar completamente la comparación.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Temp Read | Temp Written | Meses devueltos |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | 18.835 | 15151.919 | 12708 | 125442 | 3634 | 3655 | 11 |
| R2 | 2.647 | 13666.854 | 12746 | 125404 | 3634 | 3656 | 11 |
| R3 | 2.652 | 9262.196 | 12763 | 125387 | 3634 | 3656 | 11 |

**Mediana inicial: 13666.854 ms (13,667 s).** Mínimo: 9262.196 ms. Máximo: 15151.919 ms. No hubo bloques compartidos escritos o ensuciados, pero sí lectura y escritura de archivos temporales en las tres ejecuciones.

### Análisis y evidencia del plan

Los tres planes tienen la misma estructura. Resumen de R2, la muestra de la mediana:

```text
Finalize GroupAggregate (estimated groups=180; actual rows=11 loops=1)
  Group Key: to_char("createdAt", 'MM')
  Gather Merge (workers planned=2, launched=2; actual rows=33 loops=1)
    Partial GroupAggregate (actual rows=11 loops=3)
      Sort (estimated rows=12500; actual rows=548333 loops=3)
        Sort Key: to_char("createdAt", 'MM')
        Sort Method: external merge; Disk: 10560 kB
        Worker 0: external merge; Disk: 9008 kB
        Worker 1: external merge; Disk: 9504 kB
        Parallel Seq Scan on tutorias
          Filter: EXTRACT(year FROM "createdAt") = EXTRACT(year FROM now())
          Estimated rows=12500; actual rows=548333 loops=3
          Rows Removed by Filter=1451667
Planning Time: 2.647 ms
Execution Time: 13666.854 ms
Shared Hit/Read Blocks: 12746/125404
Temp Read/Written Blocks: 3634/3656
JIT: 30 functions; inlining=false; optimization=false;
     expressions=true; deforming=true
Settings: {}
```

Se recorren los 6.000.000 de registros y se seleccionan aproximadamente 1.645.000 por año de creación: cerca del 27,42% del conjunto. El número se infiere de promedios por participante redondeados; confirmar el conteo exacto por separado si se requiere. No confundir este resultado con la distribución por `fechaHora`: esta consulta usa `createdAt`.

La estimación del recorrido es de 12.500 filas por participante frente a 548.333 reales, una subestimación de aproximadamente 43,87 veces. En la raíz se estiman 180 grupos y se obtienen 11. El resultado contiene 11 meses con datos, no necesariamente todos los meses del año ni sus nombres específicos: el plan no incluye los valores de las filas.

El filtro aplica EXTRACT a la columna y no permite aprovechar directamente un índice B-tree convencional sobre `createdAt` como condición de rango. Se evaluará reescribirlo con límite inferior inclusivo al inicio del año y límite superior exclusivo al inicio del siguiente, conservando la zona horaria, el tipo de dato y la semántica de NOW(). Después se comparará un índice por fecha, eventualmente con cobertura para el COUNT(id), frente al recorrido secuencial dado el volumen seleccionado. La creación de un índice no garantiza que el planificador lo elija ni que reduzca el tiempo.

El ordenamiento usa `external merge` con archivos en disco en los tres participantes. En R2 los espacios informados suman 29.072 kB; no representan el tamaño total de la base ni deben sumarse a los contadores de bloques temporales como si fueran la misma medida. Se evaluarán una agrupación alternativa y, por separado, una prueba controlada de work_mem en la sesión para comprobar si elimina el derrame. No se modificó la configuración del motor. Es necesario revisar también la estimación de cardinalidad después de reescribir el filtro.

## Q07 — Mediciones iniciales

Listado administrativo completo de tutorías con alumno, profesor, categoría y calificación, ordenado por `t.createdAt DESC`, sin LIMIT. Tres ejecuciones consecutivas del bloque EXPLAIN, registradas en el orden recibido. Cada ejecución produjo 6.000.000 de filas en el servidor; EXPLAIN evita transferir ese listado al cliente.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Temp Read | Temp Written |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | 97.689 | 104427.544 | 13016 | 146873 | 381691 | 382139 |
| R2 | 16.830 | 53427.016 | 13592 | 146297 | 381686 | 382126 |
| R3 | 6.149 | 54077.900 | 14168 | 145721 | 381689 | 382127 |

**Mediana inicial: 54077.900 ms (54,078 s).** Mínimo: 53427.016 ms. Máximo: 104427.544 ms. Los planes no registran bloques compartidos escritos o ensuciados. Sí muestran un volumen elevado de lectura y escritura temporal.

### Análisis y evidencia del plan

Los tres planes tienen la misma estructura. Resumen de R3, la muestra de la mediana:

```text
Gather Merge (estimated rows=4999924; actual rows=6000000 loops=1)
  Workers Planned: 2; Workers Launched: 2
  Sort (actual rows=2000000 loops=3)
    Sort Key: t."createdAt" DESC
    Sort Method: external merge; Disk: 401296 kB
    Worker 0: external merge; Disk: 426616 kB
    Worker 1: external merge; Disk: 413416 kB
    Hash Left Join: t."categoriaId" = categoria.id
      Hash Left Join: t."profesorId" = profesor.id
        Hash Left Join: t."alumnoId" = alumno.id
          Hash Left Join: t.id = calificacion."tutoriaId"
            Parallel Seq Scan on tutorias (rows=2000000 loops=3)
            Parallel Hash on calificaciones (rows=200000 loops=3)
              Batches: 8; Peak Memory Usage: 7104 kB
              Parallel Seq Scan on calificaciones
          Parallel Hash on usuarios alumno (rows=66667 loops=3)
            Batches: 1; Peak Memory Usage: 20000 kB
            Parallel Seq Scan on usuarios
        Parallel Hash on usuarios profesor (rows=66667 loops=3)
          Batches: 1; Peak Memory Usage: 20000 kB
          Parallel Seq Scan on usuarios
      Hash on categorias (rows=100 loops=3)
        Batches: 1; Peak Memory Usage: 14 kB
        Seq Scan on categorias
Planning Time: 6.149 ms
Execution Time: 54077.900 ms
Shared Hit/Read Blocks: 14168/145721
Temp Read/Written Blocks: 381689/382127
JIT: 102 functions; inlining=true; optimization=true;
     expressions=true; deforming=true
Settings: {}
```

La consulta solicita el conjunto completo: un recorrido secuencial no constituye por sí solo un problema cuando deben devolverse todas las filas. Las asociaciones conservan 6.000.000 de filas en este dataset; no se observa multiplicación del resultado final por calificaciones. La raíz estima 4.999.924 filas frente a 6.000.000 reales. La validación posterior debe preservar las asociaciones, las filas sin calificación y el orden descendente por fecha; los empates no tienen un orden secundario definido.

El sort usa archivos en disco en los tres participantes. En R3 sus espacios informados suman 1.241.328 kB (aproximadamente 1,18 GiB). Además, el hash de calificaciones trabaja con ocho lotes y los JOIN ya acumulan actividad temporal antes del sort. Los contadores de buffers de nodos superiores incluyen a sus descendientes: no deben sumarse entre niveles, porque duplicaría el total. Tampoco se debe confundir el espacio de sort con el volumen acumulado de operaciones de lectura/escritura temporal.

Se evaluará un índice por `createdAt` para el ordenamiento, comprobando si el plan completo puede aprovecharlo sin introducir JOIN o accesos al heap más costosos. No se garantiza una mejora: ordenar seis millones de filas con sus asociaciones puede seguir siendo costoso, y los índices de las claves foráneas no necesariamente benefician un listado sin filtros. Se evaluará por separado una prueba de memoria de sesión para sort y hash, conservando un presupuesto compatible con la concurrencia. No se alteró la configuración global.

La paginación puede reducir sustancialmente el trabajo de un listado utilizado por personas, pero cambia el alcance de esta consulta. Una eventual versión paginada deberá identificarse como cambio funcional y no compararse como equivalente al listado completo. Los tiempos registrados aquí excluyen la transferencia de seis millones de filas y su procesamiento por Sequelize o el frontend; no representan el tiempo completo del endpoint.

## Q08 — Mediciones iniciales

Listado de profesores con sus categorías y horarios. Tres ejecuciones consecutivas del bloque EXPLAIN, sin calentamiento adicional, registradas en el orden recibido.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Temp Read | Temp Written | Filas devueltas |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | 106.328 | 11434.759 | 735 | 13565 | 21271 | 21600 | 1600000 |
| R2 | 4.087 | 6210.552 | 7842 | 6458 | 21271 | 21664 | 1600000 |
| R3 | 2.437 | 3308.038 | 7938 | 6362 | 21280 | 21656 | 1600000 |

**Mediana inicial: 6210.552 ms (6,211 s).** Mínimo: 3308.038 ms. Máximo: 11434.759 ms. Las tres ejecuciones presentan actividad temporal. No incluyen una sección JIT y `Settings` está vacío.

### Análisis y evidencia del plan

Los tres planes tienen la misma estructura. Resumen de R2, la muestra de la mediana:

```text
Gather (estimated rows=400608; actual rows=1600000 loops=1)
  Workers Planned: 2; Workers Launched: 2
  Parallel Hash Right Join: horario."profesorId" = u.id
    Actual rows=533333 loops=3
    Parallel Seq Scan on horarios_disponibles horario
      Actual rows=133333 loops=3
    Parallel Hash (actual rows=133333 loops=3)
      Batches: 32; Peak Memory Usage: 3936 kB
      Parallel Hash Right Join: pc."profesorId" = u.id
        Hash Inner Join: pc."categoriaId" = categoria.id
          Parallel Seq Scan on profesores_categorias pc
            Actual rows=133333 loops=3
          Hash on categorias (rows=100 loops=3; batches=1; memory=14 kB)
            Seq Scan on categorias
        Parallel Hash (actual rows=33333 loops=3)
          Batches: 16; Peak Memory Usage: 1920 kB
          Parallel Seq Scan on usuarios u
            Filter: rol = 'profesor'::enum_usuarios_rol
            Estimated rows=41731; actual rows=33333 loops=3
            Rows Removed by Filter=33334
Planning Time: 4.087 ms
Execution Time: 6210.552 ms
Shared Hit/Read Blocks: 7842/6458
Temp Read/Written Blocks: 21271/21664
Settings: {}
```

Los 100.000 profesores producen 1.600.000 filas: cuatro categorías por cuatro horarios generan 16 combinaciones por profesor. Es una multiplicación propia de los JOIN, no una duplicación de usuarios almacenados. Sequelize reconstruye las colecciones después de recibir las filas. La raíz estima 400.608 filas frente a 1.600.000 reales, una subestimación cercana a cuatro veces. Los valores de nodos paralelos son promedios redondeados por participante.

Los JOIN se ejecutan como Hash Right Join aunque el SQL los expresa como LEFT JOIN: el planificador intercambia los lados preservando la relación externa. El hash de usuarios usa 16 lotes y el del resultado profesor/categoría usa 32, con escritura y lectura temporal. No hay ordenamiento en este plan. Los contadores de los nodos superiores ya incluyen sus descendientes y no deben sumarse entre niveles.

En R2 y R3, horarios y asignaciones se leen mediante aciertos de buffers; persisten lecturas en usuarios. Esto acompaña la reducción de tiempo, pero no permite atribuir toda la variación únicamente a caché. La consulta selecciona aproximadamente la mitad de los usuarios y todas las asignaciones y horarios del conjunto; un índice solo por rol puede aportar poco frente a un recorrido secuencial. Los índices por profesor deben evaluarse con el plan completo y su utilidad compartida con Q05, sin asumir que mejorarán un listado de todos los profesores.

Se evaluará una prueba controlada de memoria de sesión para reducir los lotes y la actividad temporal. Como alternativa funcional se puede estudiar recuperar profesores y sus colecciones mediante consultas separadas o agregación por profesor para evitar las 16 combinaciones. Ese cambio altera la forma del resultado y requiere validar su reconstrucción y medir el conjunto de consultas; no sería una comparación equivalente de este SQL aislado. El costo del N+1 de Q01 y la transferencia/reconstrucción de 1.600.000 filas no están incluidos en el tiempo completo del endpoint medido aquí mediante EXPLAIN.

## Q01 — Después de índices, etapa A

Se recibieron tres planes posteriores, en orden. Se aceptan estas tres muestras según la decisión del responsable; la línea base conserva sus cinco muestras. No se eliminaron las ejecuciones más lentas ni se las reclasificó como calentamiento. La cantidad desigual de muestras y los estados de caché limitan la precisión de la comparación; no se presenta como una prueba estadística de rendimiento general.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Shared Dirtied | Filas |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | 180.065 | 161.218 | 143 | 154 | 6 | 36 |
| R2 | 2.035 | 2.465 | 297 | 0 | 0 | 36 |
| R3 | 1.009 | 0.949 | 297 | 0 | 0 | 36 |

**Mediana posterior: 2.465 ms.** Mínimo: 0.949 ms. Máximo: 161.218 ms. Frente a la mediana inicial de 12895.956 ms, la reducción observada es **99,9809%**, equivalente a un factor aproximado de **5231,63** entre medianas. Estos valores corresponden a Execution Time; Planning Time se informa por separado. Incluso la primera ejecución posterior es sustancialmente más rápida que las iniciales, aunque no deben suponerse condiciones de caché idénticas.

### Plan posterior y justificación de la mejora

```text
Nested Loop Left Join (estimated rows=37; actual rows=36 loops=1)
  Nested Loop Left Join (actual rows=36 loops=1)
    Bitmap Heap Scan on tutorias t (actual rows=36 loops=1)
      Recheck Cond: "profesorId" = 10001 AND estado = 'finalizada'
      Exact Heap Blocks: 36; Lossy Heap Blocks: 0
      Rows Removed by Index Recheck: 0
      Bitmap Index Scan on tutorias_profesor_estado_categoria
        Index Cond: "profesorId" = 10001 AND estado = 'finalizada'
        Actual rows=36 loops=1
    Index Scan using calificaciones_tutoria on calificaciones c
      Index Cond: "tutoriaId" = t.id
      Actual rows=0 loops=36
  Index Scan using usuarios_pkey on usuarios alumno
    Index Cond: id = t."alumnoId"
    Actual rows=1 loops=36
Planning Time (R2): 2.035 ms
Execution Time (R2): 2.465 ms
Shared Hit/Read Blocks: 297/0
Temp Read/Written Blocks: 0/0
Settings: {}
```

El plan sustituye los recorridos paralelos completos de tutorías y calificaciones por acceso a las 36 tutorías del profesor mediante el índice compuesto y búsquedas individuales de calificaciones mediante su índice. Mantiene el acceso al alumno por clave primaria. No hay Gather ni Hash Join en el nuevo plan y no se informa sección JIT. El SQL no cambió: la mejora observada se asocia al nuevo acceso por índices y al estado de caché de las muestras.

En las ejecuciones posteriores se contabilizan 297 accesos a bloques compartidos en la raíz, frente a 145.693 en las iniciales (hit más read); son accesos acumulados, no necesariamente páginas distintas. R1 posterior lee 154 bloques, mientras R2 y R3 tienen todos los accesos como aciertos. No hay actividad temporal ni bloques compartidos escritos. R1 informa seis bloques ensuciados en el acceso a calificaciones; esto no demuestra una modificación de datos de negocio y su causa no queda determinada por el plan.

La estimación final sigue siendo 37 filas frente a 36 reales y el conteo coincide con las ejecuciones iniciales. Esto confirma cardinalidad, no una comparación completa de valores; la equivalencia se apoya además en que el SQL y los filtros son idénticos. `Actual rows=0 loops=36` en calificaciones es un promedio redondeado y no permite concluir que ninguna tutoría tenga calificación.

## Q02 — Después de índices, etapa A

Tres ejecuciones posteriores, registradas en el orden recibido. La línea base conserva cinco muestras; se informa esta diferencia y no se descarta ninguna ejecución posterior como calentamiento.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Filas de tutorías contadas |
| --- | ---: | ---: | ---: | ---: | ---: |
| R1 | 3.009 | 124.552 | 17 | 49 | 60 |
| R2 | 3.250 | 7.541 | 66 | 0 | 60 |
| R3 | 0.182 | 0.319 | 66 | 0 | 60 |

**Mediana posterior: 7.541 ms.** Mínimo: 0.319 ms. Máximo: 124.552 ms. Frente a 10535.828 ms iniciales, la reducción observada entre medianas es **99,9284%**. No hubo bloques temporales ni bloques compartidos ensuciados o escritos en las tres ejecuciones.

### Plan posterior y justificación de la mejora

Los tres planes comparten esta estructura; los tiempos y buffers siguientes corresponden a R2, la muestra de la mediana:

```text
Aggregate (actual rows=1 loops=1)
  Bitmap Heap Scan on tutorias (estimated rows=121; actual rows=60 loops=1)
    Recheck Cond: ("alumnoId" = 1) OR ("profesorId" = 1)
    Exact Heap Blocks: 60; Lossy Heap Blocks: 0
    Rows Removed by Index Recheck: 0
    BitmapOr
      Bitmap Index Scan on tutorias_alumno
        Index Cond: "alumnoId" = 1
        Estimated rows=60; actual rows=60 loops=1
      Bitmap Index Scan on tutorias_profesor_estado_categoria
        Index Cond: "profesorId" = 1
        Estimated rows=61; actual rows=0 loops=1
Planning Time: 3.250 ms
Execution Time: 7.541 ms
Shared Hit/Read Blocks: 66/0
Temp Read/Written Blocks: 0/0
Settings: {}
```

PostgreSQL combina mediante BitmapOr el índice de alumno y el prefijo profesor del índice compuesto. Recupera 60 tutorías en 60 páginas del heap en lugar de recorrer seis millones de filas. La rama alumno encuentra las 60 coincidencias y la rama profesor ninguna para el ID 1. BitmapOr combina ubicaciones de filas, preservando la semántica del OR sin contar dos veces una fila que cumpla ambas ramas. Su `Actual Rows = 0` no representa el número de coincidencias del resultado: estas se observan en Bitmap Heap Scan.

El agregado devuelve una fila con el COUNT de las 60 filas recibidas; los planes iniciales permitían inferir aproximadamente ese mismo volumen. El SQL y los parámetros permanecen iguales. La estimación de 121 filas frente a 60 reales sobreestima especialmente la rama de profesor para este ID; no impide elegir un acceso eficiente. No hay ejecución paralela ni sección JIT en los planes posteriores.

La raíz registra 66 accesos a bloques compartidos por ejecución, frente a 138.076 en las iniciales. R1 posterior tiene 49 lecturas y 17 aciertos; R2 y R3 son íntegramente aciertos. Se documenta el estado de buffers junto con los tiempos: la mejora observada no constituye una garantía para cualquier caché o concurrencia. El costo de las escrituras y el almacenamiento de ambos índices se evalúan por separado.

## Q03 — Después de índices, etapa A

Tres ejecuciones posteriores registradas en el orden recibido, con el mismo COUNT por categoriaId = 1 y sin calentamiento adicional.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Heap Fetches | Filas contadas |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | 0.193 | 1819.793 | 2297 | 1768 | 8000 | 60000 |
| R2 | 4.542 | 969.982 | 4065 | 0 | 8000 | 60000 |
| R3 | 0.248 | 19.469 | 4065 | 0 | 8000 | 60000 |

**Mediana posterior: 969.982 ms.** Mínimo: 19.469 ms. Máximo: 1819.793 ms. Frente a la mediana inicial de 8451.313 ms, la reducción observada es **88,5227%**. La variación es amplia: se conservan las tres muestras sin sustituir la mediana por el mejor tiempo. No hubo bloques temporales ni bloques compartidos ensuciados o escritos.

### Plan posterior y justificación de la mejora

Los tres planes tienen la misma estructura. Resumen de R2, la muestra de la mediana:

```text
Aggregate (actual rows=1 loops=1)
  Index Only Scan using tutorias_categoria on tutorias
    Index Cond: "categoriaId" = 1
    Estimated rows=64800; actual rows=60000 loops=1
    Rows Removed by Index Recheck: 0
    Heap Fetches: 8000
Planning Time: 4.542 ms
Execution Time: 969.982 ms
Shared Hit/Read Blocks: 4065/0
Temp Read/Written Blocks: 0/0
Settings: {}
```

El acceso pasa de un recorrido paralelo de las seis millones de filas a un Index Only Scan restringido a las 60.000 entradas de la categoría. El COUNT conserva el SQL original y el nodo de acceso confirma 60.000 filas, frente al volumen aproximado inferido de los planes iniciales. La estimación posterior es de 64.800 filas, un 8% por encima de las reales. La raíz del agregado entrega una fila con el resultado, no una sola tutoría.

Aunque el nodo se denomina Index Only Scan, informa 8.000 Heap Fetches en las tres ejecuciones: para esas comprobaciones se consulta el heap porque la visibilidad no puede resolverse únicamente con el mapa de visibilidad. No equivale a 8.000 páginas distintas ni demuestra lecturas físicas del dispositivo. El índice permite cubrir el COUNT(*) sin añadir otras columnas, pero la visibilidad impide evitar todos los accesos a la tabla.

La raíz registra 4.065 accesos a bloques compartidos en cada ejecución posterior, frente a 138.076 en las iniciales. R1 incluye 1.768 lecturas; R2 y R3 tienen todos los accesos como aciertos. La diferencia entre 969.982 ms y 19.469 ms con los mismos contadores de buffers no puede explicarse exclusivamente por esos contadores: faltan mediciones de carga concurrente y tiempos de I/O para determinar la causa. No se extrapola el mejor tiempo a todas las ejecuciones.

No se ejecuta VACUUM como parte de esta etapa: modificar el estado de visibilidad entre mediciones introduciría otro factor. Una prueba de mantenimiento para reducir Heap Fetches podría evaluarse después, por separado y documentando su efecto. El índice por categoría queda justificado por la reducción de recorrido y tiempo observada; el costo de escritura se midió para el conjunto de cuatro índices de tutorías.

## Q04 — Después de índices, etapa A

Tres ejecuciones posteriores, en el orden recibido, conservando profesor ID 10001, categoría ID 1, estados pendiente/aceptada y LIMIT 1 sin ORDER BY.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Filas devueltas |
| --- | ---: | ---: | ---: | ---: | ---: |
| R1 | 6.042 | 6.604 | 3 | 1 | 1 |
| R2 | 2.608 | 2.537 | 4 | 0 | 1 |
| R3 | 2.696 | 0.569 | 4 | 0 | 1 |

**Mediana posterior: 2.537 ms.** Mínimo: 0.569 ms. Máximo: 6.604 ms. Frente a la mediana inicial de 6324.815 ms, la reducción observada es **99,9599%**. No hubo bloques temporales ni bloques compartidos ensuciados o escritos.

### Plan posterior y justificación de la mejora

Los tres planes presentan esta estructura. Resumen de R2, la muestra de la mediana:

```text
Limit (estimated rows=1; actual rows=1 loops=1)
  Index Scan using tutorias_profesor_estado_categoria on tutorias t
    Estimated rows=1; actual rows=1 loops=1
    Index Cond: "profesorId" = 10001 AND "categoriaId" = 1
    Filter: estado = ANY ('{pendiente,aceptada}'::enum_tutorias_estado[])
    Rows Removed by Filter: 0
    Rows Removed by Index Recheck: 0
Planning Time: 2.608 ms
Execution Time: 2.537 ms
Shared Hit/Read Blocks: 4/0
Temp Read/Written Blocks: 0/0
Settings: {}
```

El índice compuesto reemplaza el recorrido secuencial paralelo por un Index Scan que devuelve una coincidencia y se detiene por LIMIT. El plan utiliza profesor y categoría como condición de índice; el estado aparece como filtro, no como Index Cond. Por lo tanto, no se afirma que las tres columnas estén resolviendo directamente el acceso mediante condiciones de índice. No se descartan filas por estado antes de alcanzar el límite en estas ejecuciones.

La raíz acumula solo cuatro accesos a bloques compartidos en cada ejecución posterior. R1 incluye una lectura y tres aciertos; R2 y R3 son cuatro aciertos. La versión inicial descartaba cientos de miles de filas por participante antes de devolver una. El nuevo plan no usa paralelismo ni informa sección JIT.

La estimación de una fila coincide con la fila devuelta, pero LIMIT impide deducir la cardinalidad total de coincidencias. El SQL conserva los filtros originales y confirma la existencia de un resultado. Como no hay ORDER BY, no se exige el mismo ID entre planes. La mejora respalda reutilizar el índice compuesto compartido con Q01 y Q02; no se incorporó un índice parcial adicional para este caso.

## Q05 — Después de índices, etapa A

Tres ejecuciones posteriores, en el orden recibido, conservando profesor ID 10001 y estado activo. El SQL no cambia respecto de la línea base.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Shared Dirtied | Filas devueltas |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | 15.150 | 26.356 | 0 | 7 | 4 | 4 |
| R2 | 1.118 | 1.171 | 7 | 0 | 0 | 4 |
| R3 | 0.160 | 0.096 | 7 | 0 | 0 | 4 |

**Mediana posterior: 1.171 ms.** Mínimo: 0.096 ms. Máximo: 26.356 ms. Frente a la mediana inicial de 437.276 ms, la reducción observada es **99,7322%**. No hubo bloques temporales ni bloques compartidos escritos.

### Plan posterior y justificación de la mejora

Los tres planes tienen la misma estructura. Resumen de R2, la muestra de la mediana:

```text
Index Scan using horarios_profesor on horarios_disponibles h
  Estimated rows=4; actual rows=4 loops=1
  Index Cond: "profesorId" = 10001
  Filter: estado = 'activo'::enum_horarios_disponibles_estado
  Rows Removed by Filter: 0
  Rows Removed by Index Recheck: 0
Planning Time: 1.118 ms
Execution Time: 1.171 ms
Shared Hit/Read Blocks: 7/0
Temp Read/Written Blocks: 0/0
Settings: {}
```

El acceso por profesor sustituye el recorrido secuencial paralelo de los 400.000 horarios por un Index Scan que devuelve cuatro. La estimación coincide con el resultado. El estado se comprueba como filtro después del acceso por índice y no descarta filas en estas muestras; no fue necesario añadir estado al índice para este conjunto de datos. No hay Gather ni sección JIT en los planes posteriores.

Los accesos a bloques compartidos de ejecución pasan de 3.334 a siete. R1 registra siete lecturas y cuatro bloques ensuciados; R2 y R3 registran siete aciertos y ningún bloque ensuciado. Los bloques ensuciados no demuestran una modificación de datos de negocio y su causa no puede determinarse solo con este plan. Los contadores de planificación se mantienen separados de los de ejecución.

El SQL idéntico y las cuatro filas devueltas en ambas etapas respaldan la conservación del resultado; los planes no muestran los valores completos de esas filas. Se conserva la primera ejecución posterior y se compara la mediana de las tres, sin atribuir toda la variación exclusivamente a caché. El índice queda justificado para Q05 por la reducción observada en recorrido y tiempo. Su utilidad para Q08 y su costo en escrituras se evalúan por separado.

## Q06 — Después de índices y filtro por rango, etapa A

Tres ejecuciones recibidas en orden, correspondientes al filtro anual por rango sobre createdAt. La validación del archivo 05 devolvió cero filas en pgAdmin. El EXCEPT ALL en ambas direcciones confirma que coinciden los pares (mes, conteo) para el conjunto de datos y la sesión probados.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Heap Fetches | Meses devueltos |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | 56.700 | 6708.608 | 51807 | 27312 | 1000118 | 11 |
| R2 | 3.422 | 2737.687 | 49831 | 29314 | 1000118 | 11 |
| R3 | 0.338 | 820.288 | 49627 | 29319 | 1000118 | 11 |

**Mediana posterior: 2737.687 ms (2,738 s).** Mínimo: 820.288 ms. Máximo: 6708.608 ms. Frente a la mediana inicial de 13666.854 ms, la reducción de tiempo observada es **79,9684%**. En las tres muestras los bloques temporales leídos y escritos son cero; tampoco hubo bloques compartidos escritos o ensuciados.

### Plan posterior y justificación de la mejora

Los tres planes tienen la misma estructura. Resumen de R2, la muestra de la mediana:

```text
Finalize GroupAggregate (estimated groups=180; actual rows=11 loops=1)
  Group Key: to_char("createdAt", 'MM')
  Gather Merge (workers planned=2, launched=2; actual rows=33 loops=1)
    Sort (actual rows=11 loops=3)
      Sort Key: to_char("createdAt", 'MM')
      Sort Method: quicksort; Memory: 25 kB per participant
      Partial HashAggregate (actual rows=11 loops=3)
        HashAgg Batches: 1; Peak Memory Usage: 40 kB per participant
        Disk Usage: 0 kB
        Parallel Index Only Scan using tutorias_creada on tutorias
          Index Cond: "createdAt" >= date_trunc('year', now())
                      AND "createdAt" < date_trunc('year', now()) + '1 year'
          Estimated rows=679453; actual rows=548333 loops=3
          Heap Fetches: 1000118
Planning Time: 3.422 ms
Execution Time: 2737.687 ms
Shared Hit/Read Blocks: 49831/29314
Temp Read/Written Blocks: 0/0
Settings: {}
```

El filtro por rango se incorpora a Index Cond y permite utilizar tutorias_creada, con cobertura de id para COUNT(id). El recorrido selecciona aproximadamente 1.645.000 filas a partir del promedio redondeado de 548.333 por participante; ya no examina todo el conjunto por un filtro EXTRACT. La estimación del recorrido mejora de 12.500 a 679.453 filas por participante frente a 548.333 reales. La estimación de 180 grupos finales sigue por encima de los once observados.

También cambia el orden de las operaciones: antes se ordenaban las filas seleccionadas y luego se agregaban; ahora Partial HashAggregate reduce a once grupos por participante antes del sort. Se ordenan solamente esos grupos con quicksort en memoria, en lugar del external merge en disco inicial. Cada hash agregado ocupa 40 kB y un lote, y cada sort 25 kB según el plan. Se elimina la actividad temporal sin una ampliación de memoria documentada en esta etapa. Settings vacío no acredita por sí solo el valor de work_mem; se conserva el contexto comunicado de 4MB y debe mantenerse durante las comparaciones.

El Index Only Scan aún registra 1.000.118 Heap Fetches para comprobaciones de visibilidad. Este contador es acumulado para el nodo y no debe multiplicarse por los tres loops; tampoco equivale a páginas distintas ni a lecturas físicas de disco. Los accesos al heap impiden considerar el recorrido completamente independiente de la tabla. No se ejecuta mantenimiento adicional dentro de esta comparación.

Las lecturas compartidas posteriores no disminuyen de forma monótona con los tiempos: R2 y R3 leen más bloques que R1 y tardan menos. Se conserva esa variación sin atribuirla a una causa única. La mejora corresponde al conjunto de índices y reescritura, no a una medición aislada del efecto de INCLUDE o del filtro. No se informa sección JIT en los planes posteriores. La comparación bidireccional confirmó los valores mensuales.

## Q07 — Después de índices, etapa A

Tres ejecuciones registradas en el orden recibido, con el mismo listado completo y el mismo orden descendente por `createdAt`. Cada plan entrega 6.000.000 de filas en el servidor.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Temp Read | Temp Written |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | 84.921 | 89036.083 | 12548 | 147341 | 381684 | 382130 |
| R2 | 9.934 | 55828.901 | 13126 | 146763 | 381688 | 382134 |
| R3 | 45.219 | 43954.386 | 13702 | 146187 | 381686 | 382109 |

**Mediana posterior: 55828.901 ms (55,829 s).** Mínimo: 43954.386 ms. Máximo: 89036.083 ms. La mediana inicial fue 54077.900 ms: el aumento observado es de **3,24%**. Los rangos se solapan y la estructura del plan permanece igual; estas muestras no demuestran una mejora ni permiten atribuir el aumento a los índices.

### Plan posterior

Resumen de R2, correspondiente a la mediana:

```text
Gather Merge (estimated rows=5000000; actual rows=6000000 loops=1)
  Workers Planned: 2; Workers Launched: 2
  Sort (actual rows=2000000 loops=3)
    Sort Key: t."createdAt" DESC
    Sort Method: external merge; Disk: 413984 kB
    Worker 0: external merge; Disk: 418568 kB
    Worker 1: external merge; Disk: 408768 kB
    Hash Left Join con categorias
      Parallel Hash Left Join con usuarios (profesor)
        Parallel Hash Left Join con usuarios (alumno)
          Parallel Hash Left Join con calificaciones
            Parallel Seq Scan on tutorias (actual rows=2000000 loops=3)
            Parallel Hash on calificaciones (batches=8)
              Parallel Seq Scan on calificaciones
Planning Time: 9.934 ms
Execution Time: 55828.901 ms
Shared Hit/Read Blocks: 13126/146763
Temp Read/Written Blocks: 381688/382134
JIT: 102 functions; inlining, optimization, expressions and deforming enabled
Settings: {}
```

Ningún plan posterior usa `tutorias_creada` ni los otros índices nuevos. El listado sigue recorriendo todas las tutorías, ejecutando cuatro LEFT JOIN y ordenando el resultado completo. En R2 el ordenamiento utiliza 1.241.320 kB en disco sumando los tres participantes (aproximadamente 1,18 GiB), casi lo mismo que en la línea base. El hash de calificaciones sigue dividido en ocho lotes. Los contadores temporales de la raíz también se mantienen prácticamente iguales. No se observaron bloques compartidos escritos ni ensuciados.

Q07 queda sin mejora demostrada en la etapa A. Después de medir Q08, la prueba de memoria de la etapa B permitirá comprobar si se reducen los lotes del hash y la actividad temporal manteniendo el listado completo. No se presupone que 64MB alcancen para eliminar un sort de este tamaño. Una eventual paginación se evaluaría por separado porque cambia el alcance del resultado.

## Q08 — Después de índices, etapa A

Tres ejecuciones en el orden recibido. El SQL conserva los filtros y las asociaciones de la línea base. Los tres planes devuelven 1.600.000 filas.

| Ejecución | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Shared Dirtied | Temp Read/Written |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | 40.732 | 4380.329 | 272929 | 13224 | 3334 | 0/0 |
| R2 | 5.726 | 2038.512 | 286153 | 0 | 0 | 0/0 |
| R3 | 0.609 | 1026.576 | 286153 | 0 | 0 | 0/0 |

La mediana bajó de 6210.552 a **2038.512 ms**, una reducción observada del **67,18%**. El rango posterior va de 1026.576 a 4380.329 ms.

Resumen del plan de R2, la muestra de la mediana:

```text
Merge Left Join (estimated rows=400608; actual rows=1600000 loops=1)
  Merge Cond: u.id = pc."profesorId"
  Merge Left Join (actual rows=400000)
    Merge Cond: u.id = horario."profesorId"
    Index Scan using usuarios_pkey (actual rows=100000)
    Index Scan using horarios_profesor (actual rows=400000)
  Materialize (actual rows=1599997)
    Nested Loop (actual rows=400000)
      Index Only Scan using profesores_categorias_pkey (actual rows=400000)
      Memoize (loops=400000)
        Index Scan using categorias_pkey (loops=100)
Planning Time: 5.726 ms
Execution Time: 2038.512 ms
Shared Hit/Read Blocks: 286153/0
Temp Read/Written Blocks: 0/0
Settings: {}
```

El plan pasa de uniones hash paralelas a dos Merge Left Join que aprovechan el orden de los índices, incluido el nuevo `horarios_profesor`. Desaparecen los archivos temporales y Memoize permite reutilizar las búsquedas de categorías. Se mantienen las 16 combinaciones por profesor y la estimación final sigue siendo unas cuatro veces menor que las filas reales. Los accesos a bloques compartidos suben de 14.300 a 286.153 por ejecución. En R2 y R3 todos se resuelven en los buffers de PostgreSQL. El tiempo medido corresponde al servidor y excluye la transferencia y reconstrucción de filas en Sequelize.

## Q07 paginada — Evaluación del índice por fecha e ID

Esta prueba se limita a la primera página de 100 tutorías del listado administrativo. Selecciona las tutorías por `createdAt DESC, id DESC` antes de cargar las asociaciones. El ID desempata fechas iguales. Las mediciones del listado completo se conservan en las secciones de Q07. El rendimiento de páginas posteriores queda fuera de esta medición.


El índice existente `tutorias_creada` ordena por fecha y lleva el ID como columna incluida. El candidato `tutorias_creada_id`, sin prefijo, usa el ID como segunda clave para entregar directamente el orden de la página. Se conserva el índice existente mientras se mide el aporte del candidato. Si el candidato aporta una mejora, corresponde evaluar si puede reemplazar al anterior y volver a medir Q06 antes de decidir.

| Muestra inicial | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Filas devueltas |
| --- | ---: | ---: | ---: | ---: | ---: |
| R1 | 112.337 | 1607.565 | 1102 | 2690 | 100 |

R1 usa `tutorias_creada`. Su Index Scan entrega 45.001 filas al Incremental Sort, que aprovecha el orden por fecha y aplica el desempate por ID antes del LIMIT. La consulta devuelve 100 filas y registra cero bloques temporales.

El inventario posterior confirmó que `tutorias_creada` y `tutorias_creada_id` están válidos y listos. Cada uno ocupa 189.276.160 bytes (180,51 MiB), por lo que mantener ambos ocupa 378.552.320 bytes. El índice compuesto ya existe y se omite su creación en esta instalación. Como se desconoce si ya existía al capturar R1, esa muestra sirve como referencia del acceso con `tutorias_creada`. La comparación controlada con tres muestras previas a la creación queda sin completar.

### Mediciones con el índice compuesto

| Muestra | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Filas devueltas |
| --- | ---: | ---: | ---: | ---: | ---: |
| R1 | 97.380 | 598.136 | 1131 | 188 | 100 |
| R2 | 8.416 | 23.991 | 1319 | 0 | 100 |
| R3 | 1.184 | 1.963 | 1319 | 0 | 100 |

La mediana de ejecución es **23.991 ms**. Los tres planes usan `tutorias_creada_id`. El Index Scan entrega 100 filas al LIMIT, frente a las 45.001 que el recorrido de referencia entregaba al Incremental Sort. Los tres planes eliminan el nodo de ordenamiento y registran cero bloques temporales. Las asociaciones se resuelven después del LIMIT con Nested Loop y sus índices correspondientes.

R1 registra 188 bloques leídos y R2 y R3 solo aciertos en los buffers compartidos. Los tiempos muestran una variación amplia. La mediana del índice compuesto y la única muestra con `tutorias_creada` tienen distinto número de muestras y condiciones de buffers. La reducción de trabajo se verifica directamente en los planes. La validación de la página Q07 devolvió `100 | 100 | true`, confirmando los IDs únicos y el orden lógico de la primera página para los datos probados.

El candidato se justifica para la primera página de Q07. El listado completo conserva su evaluación anterior. La decisión de sustituir `tutorias_creada` requiere una prueba separada de Q06 que compruebe su plan y rendimiento con el compuesto.

### Q06 usando el índice compuesto

Se recibieron tres planes con `tutorias_creada_id`. Las dos últimas muestras se obtuvieron excluyendo temporalmente el índice anterior dentro de una transacción. El inventario final confirma ambos índices válidos después del ROLLBACK.

| Muestra | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read | Heap Fetches | Grupos |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | 25.143 | 15299.270 | 54038 | 29300 | 1000118 | 11 |
| R2 | 8.195 | 2605.231 | 53876 | 29317 | 1000118 | 11 |
| R3 | 3.198 | 2162.442 | 53933 | 29316 | 1000118 | 11 |

El Parallel Index Only Scan usa el rango anual sobre el índice compuesto. Devuelve en promedio 548.333 filas por participante, con tres loops. Mantiene once grupos y cero bloques temporales en las tres muestras. La mediana con el compuesto es **2605.231 ms**, frente a **2737.687 ms** de la etapa A con el índice anterior. La diferencia observada es aproximadamente 4,84%. La variación de las muestras y la ausencia de una prueba alternada entre ambos índices limitan la interpretación de esa pequeña diferencia.

El compuesto cubre el acceso anual de Q06 y entrega directamente el orden de la primera página de Q07. El responsable retiró manualmente `tutorias_creada`. El inventario final confirma `tutorias_creada_id` válido y listo y la ausencia del índice anterior. Se liberó el espacio de un índice de 189.276.160 bytes (180,51 MiB). El tamaño de base comunicado después de la retirada es 1.891.253.271 bytes (1804 MB). La validación de la página Q07 confirmó `100 | 100 | true` para Q07 paginada. El costo de escritura registrado antes de esta sustitución corresponde al índice por fecha con INCLUDE(id).

| Índice final de tutorías | Válido | Listo | Bytes |
| --- | --- | --- | ---: |
| tutorias_alumno | true | true | 41123840 |
| tutorias_categoria | true | true | 41639936 |
| tutorias_creada_id | true | true | 189276160 |
| tutorias_pkey | true | true | 134807552 |
| tutorias_profesor_estado_categoria | true | true | 84426752 |

Los cuatro índices secundarios de tutorías suman 356.466.688 bytes. Con los índices de calificaciones y horarios, los seis índices secundarios añadidos conservados suman 374.915.072 bytes (357,55 MiB). La sustitución mantiene el mismo tamaño de índice por fecha que el candidato inicial. El valor global de la base coincide con una captura previa a esta última prueba y se conserva tal como fue comunicado, sin atribuirle un ahorro global medido de 180,51 MiB.

Las dos muestras siguientes usaron `tutorias_creada`, según el nombre del índice en sus planes. Se conservan como observaciones adicionales del índice anterior.

| Muestra adicional | Índice utilizado | Planning Time (ms) | Execution Time (ms) | Shared Hit | Shared Read |
| --- | --- | ---: | ---: | ---: | ---: |
| A1 | tutorias_creada | 6.697 | 7234.947 | 51783 | 26840 |
| A2 | tutorias_creada | 2.519 | 1112.024 | 49404 | 29318 |

Ambas entregan once grupos, registran 1.000.118 Heap Fetches y cero bloques temporales. Se conservan fuera de las tres muestras del compuesto porque sus planes utilizaron el índice anterior. La prueba posterior con exclusión transaccional permitió completar la comparación.


## Resultados de las mediciones

| Consulta | Mediana antes (ms) | Mediana después (ms) | Estado |
| --- | ---: | ---: | --- |
| Q01 | 12895.956 | 2.465 | Etapa A: reducción observada 99,9809%; cinco muestras antes y tres después |
| Q02 | 10535.828 | 7.541 | Etapa A: reducción observada 99,9284%; cinco muestras antes y tres después |
| Q03 | 8451.313 | 969.982 | Etapa A: reducción observada 88,5227%; tres muestras por etapa |
| Q04 | 6324.815 | 2.537 | Etapa A: reducción observada 99,9599%; tres muestras por etapa |
| Q05 | 437.276 | 1.171 | Etapa A: reducción observada 99,7322%; tres muestras por etapa |
| Q06 | 13666.854 | 2737.687 | Etapa A: reducción observada 79,9684%, conteos mensuales equivalentes |
| Q07 | 54077.900 | 55828.901 | Etapa A: sin mejora demostrada; mediana +3,24% |
| Q08 | 6210.552 | 2038.512 | Etapa A: reducción observada 67,18%, sin actividad temporal |
| Q06 con índice compuesto final | — | 2605.231 | Tres muestras con tutorias_creada_id |
| Q07 primera página | Referencia única 1607.565 | 23.991 | Tres muestras con el compuesto, página validada |




## Costo de escritura y tamaño actual

La última medición de `pg_database_size` reportó **1.891.253.271 bytes (1804 MB)** para `tpFinal`. La captura anterior registró 1.891.236.887 bytes.

El siguiente inventario corresponde a la etapa anterior a sustituir el índice por fecha. Los nueve índices inventariados figuraban válidos y listos. Los tamaños legibles corresponden a la salida redondeada de PostgreSQL. El inventario final de tutorías se conserva en la sección de Q06 con el compuesto.

| Tabla | Índice | Tipo | Bytes | Tamaño reportado |
| --- | --- | --- | ---: | ---: |
| calificaciones | `calificaciones_pkey` | PK | 13500416 | 13 MB |
| calificaciones | `calificaciones_tutoria` | Nuevo | 13500416 | 13 MB |
| horarios_disponibles | `horarios_disponibles_pkey` | PK | 9003008 | 8792 kB |
| horarios_disponibles | `horarios_profesor` | Nuevo | 4947968 | 4832 kB |
| tutorias | `tutorias_alumno` | Nuevo | 41123840 | 39 MB |
| tutorias | `tutorias_categoria` | Nuevo | 41639936 | 40 MB |
| tutorias | `tutorias_creada` | Nuevo | 189276160 | 181 MB |
| tutorias | `tutorias_pkey` | PK | 134807552 | 129 MB |
| tutorias | `tutorias_profesor_estado_categoria` | Nuevo | 84426752 | 81 MB |
| | **Total de los seis nuevos** | | **374915072** | **357,55 MiB** |

La decisión final conserva seis índices secundarios y sustituye el candidato por fecha con INCLUDE(id) por `tutorias_creada_id`. El compuesto sirve a Q06 y Q07 paginada y representa el 50,5% del espacio añadido. Q07 completa conserva su evaluación sin mejora demostrada. El costo de escritura medido corresponde al conjunto anterior a la sustitución.

La prueba comparó dos copias temporales de 200.000 tutorías. Ambas tenían clave primaria y una tenía los cuatro índices adicionales. Cada ejecución procesó 20.000 filas en el INSERT y 10.000 en el UPDATE de `createdAt`.

| Operación | Repetición | Solo PK (ms) | PK y cuatro índices (ms) | Bloques locales ensuciados, solo PK | Bloques locales ensuciados, con índices |
| --- | ---: | ---: | ---: | ---: | ---: |
| INSERT | 1 | 193.427 | 418.984 | 517 | 3377 |
| INSERT | 2 | 96.440 | 325.127 | 517 | 3203 |
| INSERT | 3 | 97.520 | 290.522 | 517 | 3388 |
| UPDATE | 1 | 158.379 | 600.999 | 510 | 3492 |
| UPDATE | 2 | 130.679 | 552.016 | 510 | 3492 |
| UPDATE | 3 | 142.838 | 489.286 | 510 | 3497 |

| Operación | Mediana solo PK (ms) | Mediana con índices (ms) | Diferencia (ms) | Factor |
| --- | ---: | ---: | ---: | ---: |
| INSERT | 97.520 | 325.127 | +227.607 | 3,33× |
| UPDATE | 142.838 | 552.016 | +409.178 | 3,86× |

Los cuatro índices se evaluaron en conjunto. El UPDATE modifica una columna indexada. Los bloques ensuciados corresponden a buffers locales de las copias temporales. La prueba excluye WAL, triggers y claves foráneas de la tabla real, y no mide el costo de los índices de calificaciones y horarios.

### Escrituras con los índices definitivos — 11/11/2026

Ejecución en tpFinal mediante el archivo 07 actualizado, con el índice compuesto por createdAt e id. Todas las muestras procesaron las 20.000 inserciones y las 10.000 actualizaciones esperadas por variante. Se conserva la medición anterior como evidencia del conjunto con INCLUDE(id).

| Operación | Repetición | Solo PK (ms) | PK y cuatro índices finales (ms) | Bloques locales ensuciados, solo PK | Bloques locales ensuciados, con índices |
| --- | ---: | ---: | ---: | ---: | ---: |
| INSERT | 1 | 198.109 | 536.057 | 517 | 3410 |
| INSERT | 2 | 205.365 | 563.042 | 517 | 3237 |
| INSERT | 3 | 67.874 | 398.439 | 517 | 3413 |
| UPDATE | 1 | 120.076 | 685.332 | 510 | 3464 |
| UPDATE | 2 | 169.921 | 784.152 | 510 | 3466 |
| UPDATE | 3 | 146.272 | 526.531 | 510 | 3460 |

| Operación | Mediana solo PK (ms) | Mediana con índices finales (ms) | Diferencia (ms) | Factor |
| --- | ---: | ---: | ---: | ---: |
| INSERT | 198.109 | 536.057 | +337.948 | 2,71× |
| UPDATE | 146.272 | 685.332 | +539.060 | 4,69× |

El conjunto definitivo aumenta el costo de escritura observado en la muestra y mantiene las mejoras de acceso documentadas para las consultas. Las dos campañas de escritura tienen diferentes tiempos incluso en la variante que solo lleva PK. Se comparan las variantes dentro de cada campaña. La diferencia entre campañas requiere condiciones controladas para atribuirla a la sustitución del índice. La prueba usa tablas temporales y excluye WAL, triggers y claves foráneas de la tabla real. La salida confirma las cantidades procesadas. El cierre mediante ROLLBACK se ejecuta después de copiar estos resultados.

## Pruebas evaluadas y decisión final

El índice por fecha con INCLUDE(id) mejoró Q06, pero la primera página Q07 necesitaba ordenar los empates por ID. Se probó tutorias_creada_id, que permitió entregar 100 filas directamente al LIMIT. Después se comprobó su uso en Q06 y se retiró manualmente el índice anterior. La entrega crea directamente el compuesto.

Q07 completa conservó su recorrido de seis millones de filas con ordenamiento externo. Los intentos con work_mem de 64MB y 8MB fallaron con SQLSTATE 53100 al ampliar segmentos de memoria compartida. Con 4MB y enable_parallel_hash desactivado, una muestra tardó 66866.757 ms y registró 525702 bloques temporales leídos y 526074 escritos. Esa variante se descartó tras observar más trabajo en las tablas hash. Los scripts de entrega mantienen el contexto de 4MB.

La sustitución se probó temporalmente dentro de una transacción y se revirtió con ROLLBACK antes de retirar definitivamente el índice anterior. Un intento dejó un índice inválido que se retiró y se completó el índice por categoría. Estos pasos explican las decisiones y los inventarios históricos. La instalación final usa el archivo 03.

Q07 paginada obtuvo una mediana de 23.991 ms y validó sus IDs y orden. La comparación de acceso usa una muestra de referencia que eligió el índice anterior y tres con el compuesto. La cronología de creación del candidato impide presentar esos tiempos como un antes y después controlado. El listado completo permanece sin mejora demostrada. Los resultados de siete consultas originales y la variante paginada deben evaluarse con esas limitaciones al revisar PT-24.

## Evidencia del plan Q01

Se conserva a continuación el JSON completo de R5 como plan representativo de la medición inicial. Los tiempos de las otras repeticiones permanecen en la tabla anterior.

<details>
<summary>Q01 antes — R5, plan completo</summary>

```json
[
  {
    "Plan": {
      "Node Type": "Gather",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 176576.03,
      "Total Cost": 187273.50,
      "Plan Rows": 37,
      "Plan Width": 266,
      "Actual Rows": 36,
      "Actual Loops": 1,
      "Workers Planned": 2,
      "Workers Launched": 2,
      "Single Copy": false,
      "Shared Hit Blocks": 16049,
      "Shared Read Blocks": 129644,
      "Shared Dirtied Blocks": 0,
      "Shared Written Blocks": 0,
      "Local Hit Blocks": 0,
      "Local Read Blocks": 0,
      "Local Dirtied Blocks": 0,
      "Local Written Blocks": 0,
      "Temp Read Blocks": 0,
      "Temp Written Blocks": 0,
      "Plans": [
        {
          "Node Type": "Nested Loop",
          "Parent Relationship": "Outer",
          "Parallel Aware": false,
          "Async Capable": false,
          "Join Type": "Left",
          "Startup Cost": 175576.03,
          "Total Cost": 186269.80,
          "Plan Rows": 15,
          "Plan Width": 266,
          "Actual Rows": 12,
          "Actual Loops": 3,
          "Inner Unique": true,
          "Shared Hit Blocks": 16049,
          "Shared Read Blocks": 129644,
          "Shared Dirtied Blocks": 0,
          "Shared Written Blocks": 0,
          "Local Hit Blocks": 0,
          "Local Read Blocks": 0,
          "Local Dirtied Blocks": 0,
          "Local Written Blocks": 0,
          "Temp Read Blocks": 0,
          "Temp Written Blocks": 0,
          "Workers": [
          ],
          "Plans": [
            {
              "Node Type": "Hash Join",
              "Parent Relationship": "Outer",
              "Parallel Aware": true,
              "Async Capable": false,
              "Join Type": "Right",
              "Startup Cost": 175575.61,
              "Total Cost": 186144.86,
              "Plan Rows": 15,
              "Plan Width": 242,
              "Actual Rows": 12,
              "Actual Loops": 3,
              "Inner Unique": true,
              "Hash Cond": "(c.\"tutoriaId\" = t.id)",
              "Shared Hit Blocks": 15903,
              "Shared Read Blocks": 129644,
              "Shared Dirtied Blocks": 0,
              "Shared Written Blocks": 0,
              "Local Hit Blocks": 0,
              "Local Read Blocks": 0,
              "Local Dirtied Blocks": 0,
              "Local Written Blocks": 0,
              "Temp Read Blocks": 0,
              "Temp Written Blocks": 0,
              "Workers": [
              ],
              "Plans": [
                {
                  "Node Type": "Seq Scan",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": true,
                  "Async Capable": false,
                  "Relation Name": "calificaciones",
                  "Alias": "c",
                  "Startup Cost": 0.00,
                  "Total Cost": 9913.00,
                  "Plan Rows": 250000,
                  "Plan Width": 63,
                  "Actual Rows": 200000,
                  "Actual Loops": 3,
                  "Shared Hit Blocks": 2887,
                  "Shared Read Blocks": 4526,
                  "Shared Dirtied Blocks": 0,
                  "Shared Written Blocks": 0,
                  "Local Hit Blocks": 0,
                  "Local Read Blocks": 0,
                  "Local Dirtied Blocks": 0,
                  "Local Written Blocks": 0,
                  "Temp Read Blocks": 0,
                  "Temp Written Blocks": 0,
                  "Workers": [
                  ]
                },
                {
                  "Node Type": "Hash",
                  "Parent Relationship": "Inner",
                  "Parallel Aware": true,
                  "Async Capable": false,
                  "Startup Cost": 175575.42,
                  "Total Cost": 175575.42,
                  "Plan Rows": 15,
                  "Plan Width": 179,
                  "Actual Rows": 12,
                  "Actual Loops": 3,
                  "Hash Buckets": 1024,
                  "Original Hash Buckets": 1024,
                  "Hash Batches": 1,
                  "Original Hash Batches": 1,
                  "Peak Memory Usage": 104,
                  "Shared Hit Blocks": 12958,
                  "Shared Read Blocks": 125118,
                  "Shared Dirtied Blocks": 0,
                  "Shared Written Blocks": 0,
                  "Local Hit Blocks": 0,
                  "Local Read Blocks": 0,
                  "Local Dirtied Blocks": 0,
                  "Local Written Blocks": 0,
                  "Temp Read Blocks": 0,
                  "Temp Written Blocks": 0,
                  "Workers": [
                  ],
                  "Plans": [
                    {
                      "Node Type": "Seq Scan",
                      "Parent Relationship": "Outer",
                      "Parallel Aware": true,
                      "Async Capable": false,
                      "Relation Name": "tutorias",
                      "Alias": "t",
                      "Startup Cost": 0.00,
                      "Total Cost": 175575.42,
                      "Plan Rows": 15,
                      "Plan Width": 179,
                      "Actual Rows": 12,
                      "Actual Loops": 3,
                      "Filter": "((\"profesorId\" = 10001) AND (estado = 'finalizada'::enum_tutorias_estado))",
                      "Rows Removed by Filter": 1999988,
                      "Shared Hit Blocks": 12958,
                      "Shared Read Blocks": 125118,
                      "Shared Dirtied Blocks": 0,
                      "Shared Written Blocks": 0,
                      "Local Hit Blocks": 0,
                      "Local Read Blocks": 0,
                      "Local Dirtied Blocks": 0,
                      "Local Written Blocks": 0,
                      "Temp Read Blocks": 0,
                      "Temp Written Blocks": 0,
                      "Workers": [
                      ]
                    }
                  ]
                }
              ]
            },
            {
              "Node Type": "Index Scan",
              "Parent Relationship": "Inner",
              "Parallel Aware": false,
              "Async Capable": false,
              "Scan Direction": "Forward",
              "Index Name": "usuarios_pkey",
              "Relation Name": "usuarios",
              "Alias": "alumno",
              "Startup Cost": 0.42,
              "Total Cost": 8.33,
              "Plan Rows": 1,
              "Plan Width": 28,
              "Actual Rows": 1,
              "Actual Loops": 36,
              "Index Cond": "(id = t.\"alumnoId\")",
              "Rows Removed by Index Recheck": 0,
              "Shared Hit Blocks": 146,
              "Shared Read Blocks": 0,
              "Shared Dirtied Blocks": 0,
              "Shared Written Blocks": 0,
              "Local Hit Blocks": 0,
              "Local Read Blocks": 0,
              "Local Dirtied Blocks": 0,
              "Local Written Blocks": 0,
              "Temp Read Blocks": 0,
              "Temp Written Blocks": 0,
              "Workers": [
              ]
            }
          ]
        }
      ]
    },
    "Settings": {
    },
    "Planning": {
      "Shared Hit Blocks": 12,
      "Shared Read Blocks": 0,
      "Shared Dirtied Blocks": 0,
      "Shared Written Blocks": 0,
      "Local Hit Blocks": 0,
      "Local Read Blocks": 0,
      "Local Dirtied Blocks": 0,
      "Local Written Blocks": 0,
      "Temp Read Blocks": 0,
      "Temp Written Blocks": 0
    },
    "Planning Time": 22.413,
    "Triggers": [
    ],
    "JIT": {
      "Functions": 51,
      "Options": {
        "Inlining": false,
        "Optimization": false,
        "Expressions": true,
        "Deforming": true
      }
    },
    "Execution Time": 12895.956
  }
]
```

</details>

