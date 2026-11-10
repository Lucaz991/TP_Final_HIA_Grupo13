# PT-23 — Dataset de seis millones de tutorías

La tabla seleccionada para la prueba de volumen es `public.tutorias`. Los scripts actuales preparan desde tablas vacías 100 categorías, 10 tarifas, dos administradores, alumnos, profesores, asignaciones, horarios y tutorías. La carga definitiva genera 6.000.000 de tutorías. El piloto utiliza los mismos generadores con un volumen menor.

## Requisitos

- Clúster PostgreSQL inicializado con el esquema de la aplicación. Las tablas y los tipos ENUM provienen de los modelos Sequelize del backend.
- Tablas del conjunto vacías antes de una nueva ejecución y controles de `pt23_dataset` preparados explícitamente. Respaldar los resultados anteriores antes de planificar una limpieza.
- Backend configurado para crear el esquema e iniciar sin invocar los seeders. Los datos se cargan mediante SQL.
- Backend actualizado con `sequelize.sync()` y el índice único de precios sobre `(nivel, modalidad)`.
- pgAdmin conectado a `tpFinal` mediante `proxy`, puerto `5432`, con un usuario autorizado para insertar datos y crear tablas y restricciones.
- Auto-commit activado, una pestaña sin transacciones pendientes y una sola ejecución de carga a la vez.
- Backend detenido después de inicializar el esquema. Mantener estables catálogos, usuarios, asignaciones y horarios durante la carga y la verificación.

Cada instalación local tiene su propia base. Para reproducir el dataset se ejecutan estos scripts o se restaura un respaldo de la base cargada.

## Orden de ejecución

| Archivo | Ejecución |
|---|---|
| [00_restriccion_precios.sql](00_restriccion_precios.sql) | Una vez. Comprueba duplicados y asegura una tarifa por nivel y modalidad. Admite repetir su ejecución. |
| [01_prevalidacion.sql](01_prevalidacion.sql) | Una vez antes de generar datos. Guardar conteos, tamaño inicial y resultados de integridad. |
| [01_catalogos.sql](01_catalogos.sql) | Después de la prevalidación. Carga 100 categorías y 10 tarifas. |
| [02_usuarios.sql](02_usuarios.sql) | Utilizar los tres hashes bcrypt con costo 10, uno por rol, y conservarlos durante la ejecución. Piloto con rango 1–1000. Definitiva con los cuatro rangos de 25.000 siguientes. Las dos cuentas admin se conservan por email único. |
| [03_asignaciones.sql](03_asignaciones.sql) | Después de cargar los usuarios. Utilizar las cuatro tandas de hasta 25.000 profesores indicadas abajo. Genera cuatro categorías por profesor y requiere exactamente 100 categorías. |
| [04_horarios.sql](04_horarios.sql) | Después de cargar los usuarios. Utilizar las cuatro tandas de hasta 25.000 profesores y `profesores_totales = 100000`. Genera cuatro franjas activas por profesor, lunes, martes, jueves y viernes, modalidad ambas, en el turno que corresponde a su número de email. |
| [05_tutorias.sql](05_tutorias.sql) | Configurar el modo y ejecutar seis veces, cambiando `lote` de 1 a 6. |
| [06_verificacion_final.sql](06_verificacion_final.sql) | Ejecutar los cinco `ANALYZE` como bloque separado. Después ejecutar individualmente las consultas numeradas. Las cantidades esperadas se obtienen de la configuración persistida. |

### Parámetros del piloto y de la carga definitiva

| Parámetro o resultado | Piloto | Definitiva |
|---|---:|---:|
| `usuarios_por_rol` en tutorías | 1000 | 100000 |
| `registros_por_lote` en tutorías | 10000 | 1000000 |
| Lotes de tutorías | 6 | 6 |
| Usuarios totales, incluidos dos admins | 2002 | 200002 |
| Asignaciones | 4000 | 400000 |
| Horarios | 4000 | 400000 |
| Tutorías | 60000 | 6000000 |

El generador de tutorías está guardado en modo definitivo, con `lote = 1`, `usuarios_por_rol = 100000` y `registros_por_lote = 1000000`. Mantener sus parámetros durante los seis lotes y cambiar únicamente `lote`. Para el piloto se usan `usuarios_por_rol = 1000` y `registros_por_lote = 10000`. Usuarios, asignaciones y horarios se ejecutan una vez con rango 1–1000 en ese modo. En horarios configurar también `profesores_totales = 1000` para conservar las proporciones de los tres turnos.

Para una nueva ejecución, comprobar el piloto y el login con una cuenta de cada rol antes de preparar la definitiva. El generador rechaza cambiar de modo sobre una ejecución iniciada y los controles anteriores sin versión. La preparación de una base vacía requiere un respaldo y una limpieza manual explícita de las tablas de la aplicación y de `pt23_dataset.configuracion`, `pt23_dataset.ejecucion` y `pt23_dataset.lotes`. Estos scripts conservan los datos al repetirse y no incluyen una limpieza automática. La ejecución del piloto y las pruebas de login de la versión actual todavía requieren evidencias propias.

| Lote de usuarios, asignaciones u horarios | Desde | Hasta |
|---|---:|---:|
| 1 | 1 | 25000 |
| 2 | 25001 | 50000 |
| 3 | 50001 | 75000 |
| 4 | 75001 | 100000 |

Cada lote de usuarios agrega hasta 25.000 alumnos y 25.000 profesores. El primer lote crea además los dos administradores. Los siguientes conservan esas cuentas por su email único. Desde una base vacía los totales acumulados son 50.002, 100.002, 150.002 y 200.002 usuarios. Cada tanda de asignaciones u horarios genera hasta 100.000 filas en su tabla.

Usuarios y horarios están guardados con rango 1–25000. El archivo de asignaciones está guardado con rango 1–10000 y admite hasta 25.000 profesores. Cambiar `hasta` a 25000 para seguir la tabla desde la primera tanda. Completar primero los usuarios antes de generar asignaciones y horarios. Si un rango ya fue procesado, se puede completar el siguiente tramo o repetirlo manteniendo estables los catálogos y las cuentas. Los hashes deben conservarse exactamente durante todas las ejecuciones de usuarios. Cambiar el tamaño de lote del archivo no modifica las cuentas que ya están cargadas.

Esperar la finalización de cada ejecución antes de iniciar la siguiente. Ante un error, ejecutar `ROLLBACK;` en la misma pestaña antes de volver a usarla. Registrar también el tiempo total informado por pgAdmin.

## Método de generación

Se utiliza SQL con `generate_series`, tablas temporales indexadas y estadísticas actualizadas mediante `ANALYZE`. Las claves primarias se asignan con las secuencias existentes. Los scripts mantienen habilitadas las restricciones del esquema.

Los usuarios se identifican mediante emails como `alumno.1@example.com`, `profesor.1@example.com` y `admin.1@example.com`, con apellido `Sintético`. `ON CONFLICT (email) DO NOTHING` permite repetir un rango. Se almacena un hash bcrypt con costo 10 por rol. Completar los tres marcadores y conservar exactamente los mismos hashes en los siguientes lotes. Las contraseñas se comparten por separado con el equipo. La comprobación SQL valida su formato y correspondencia por rol. El acceso debe probarse mediante el login de la aplicación.

Las categorías se numeran por ID y cada profesor recibe cuatro categorías diferentes. La clave compuesta y `ON CONFLICT` evitan pares repetidos. El catálogo debe permanecer estable entre ejecuciones.

Las tutorías se generan mediante 60 rondas de la cantidad configurada de alumnos, agrupadas en seis transacciones. Una permutación distribuye los profesores y una rotación selecciona sus categorías. Al completar cualquiera de los modos, cada alumno y profesor sintético participa en 60 tutorías y cada categoría asignada a un profesor se utiliza 15 veces.

### Turnos y fechas del generador actual

Cada profesor tiene cuatro franjas, los lunes, martes, jueves y viernes. El número de su email determina su turno. Las cantidades siguientes corresponden a la carga definitiva.

| Turno | Números de profesor | Profesores | Franja | Horarios |
|---|---|---:|---|---:|
| Mañana | 1–20000 | 20.000 | 09:00–13:00 | 80.000 |
| Tarde | 20001–55000 | 35.000 | 14:00–18:00 | 140.000 |
| Noche | 55001–100000 | 45.000 | 19:00–23:00 | 180.000 |
| Total | 1–100000 | 100.000 | | 400.000 |

El piloto conserva las proporciones con 200 profesores de mañana, 350 de tarde y 450 de noche. Las sesiones duran una hora y comienzan al inicio de la franja del profesor o una, dos o tres horas después. La sesión más tardía es de 22:00 a 23:00.

Las fechas locales abarcan del 3 de enero de 2022 al 16 de noviembre de 2026, inclusive, en la zona `America/Argentina/Buenos_Aires`.

| Año | Rondas | Tutorías definitivas | Tutorías del piloto |
|---|---:|---:|---:|
| 2022 | 6 | 600.000 | 6.000 |
| 2023 | 9 | 900.000 | 9.000 |
| 2024 | 12 | 1.200.000 | 12.000 |
| 2025 | 15 | 1.500.000 | 15.000 |
| 2026 | 18 | 1.800.000 | 18.000 |
| Total | 60 | 6.000.000 | 60.000 |

Las rondas se reparten entre meses de cada año y utilizan fechas compatibles con los días de disponibilidad. Las primeras 59 rondas se concentran en la primera semana de los meses seleccionados. La última ronda utiliza el lunes 16 de noviembre de 2026. Hay 60 fechas distintas, cada una con 100.000 tutorías en la carga definitiva. El lote 6 contiene diez fechas, de mayo a noviembre de 2026, y solo sus últimas 100.000 tutorías corresponden al 16 de noviembre. Cada participante tiene una sola tutoría por fecha.

El importe es la tarifa horaria del nivel de la categoría y la modalidad. Los mensajes alternan entre cinco textos. Las tutorías virtuales aceptadas o finalizadas incluyen enlaces como `https://meet.example.com/123456` y un identificador de evento ficticio. Las finalizadas incluyen identificadores de preferencia y pago ficticios. Los campos de las tutorías nuevas carecen del texto `pt23`.

Los identificadores `INTEGER` se conservan porque admiten hasta 2.147.483.647 valores positivos, por encima del volumen de esta prueba. Las cancelaciones y los conflictos pueden consumir números de secuencia y dejar saltos válidos.

## Registro y reanudación

`05_tutorias.sql` crea el esquema auxiliar `pt23_dataset` y las tablas `configuracion`, `ejecucion` y `lotes`. Guardan el modo y la versión del generador, el punto de partida de la carga y la cantidad y duración por lote, respectivamente.

La versión actual del control es 3. Los datos y controles de versiones anteriores requieren preparación explícita antes de una carga nueva. El último ajuste del 5 al 16 de noviembre afecta únicamente a la ronda 59. Si los primeros cinco lotes se generaron con los tres turnos y el rango 2022–2026, sus fechas se conservan al ejecutar el lote 6 con el archivo actualizado. Un lote 6 ya confirmado se omite al repetirlo. Cambiar el archivo no actualiza tutorías existentes.

Las tutorías y el registro de su lote se confirman dentro de la misma transacción. Si un lote ya figura como confirmado, se omite su inserción. Esta comprobación presupone conservar tanto los datos como las tablas de control. Para iniciar otro dataset desde cero hace falta planificar explícitamente su limpieza.

Tras una desconexión, reconectar mediante el proxy, comprobar el líder y consultar `pt23_dataset.lotes`. Si el lote no aparece, verificar que la sesión anterior haya terminado antes de repetirlo. El script emplea un bloqueo asesor para serializar sus ejecuciones.

Los seis registros de lotes se comparan con el conteo real de `tutorias` mediante la consulta 2 de la verificación. Al finalizar, `coincide` y `completo` deben devolver `true`. Si se eliminan tutorías manualmente pero se conservan los controles, repetir un lote confirmado seguirá omitiéndolo.

## Evidencias de la versión actual

El responsable comunicó la regeneración de horarios y el avance de los lotes con los tres turnos. El cambio final al 16 de noviembre se incorporó antes de ejecutar el lote 6. Las capturas de tamaños compartidas el 10 de noviembre de 2026 confirman las mediciones siguientes. Queda pendiente adjuntar las salidas finales de cantidades, distribución anual, turnos, integridad y tiempos de esta versión. Los resultados conservados más abajo bajo el título de carga anterior corresponden a otras ejecuciones.

### Tamaño final de la base actual

| Medición | Bytes |
|---|---:|
| Base antes de cargar tutorías | 175.555.087 |
| Base al finalizar | 1.442.061.335 |
| Crecimiento | 1.266.506.248 |

PostgreSQL informó `1375 MB` como tamaño final de `tpFinal`. La medición inicial corresponde al comienzo de la generación de tutorías, después de cargar los datos de apoyo. El crecimiento se obtiene restando ese valor al tamaño final. `pg_database_size` mide una copia de la base y los archivos de sus relaciones, sin sumar las réplicas ni el WAL del clúster.

### Tamaño actual de tablas e índices

| Tabla | Tabla y almacenamiento auxiliar, bytes | Índices, bytes | Total, bytes | Total informado por PostgreSQL |
|---|---:|---:|---:|---|
| `categorias` | 49.152 | 32.768 | 81.920 | 80 kB |
| `horarios_disponibles` | 27.344.896 | 9.003.008 | 36.347.904 | 35 MB |
| `precios` | 8.192 | 32.768 | 40.960 | 40 kB |
| `profesores_categorias` | 30.154.752 | 20.070.400 | 50.225.152 | 48 MB |
| `tutorias` | 1.131.454.464 | 134.840.320 | 1.266.294.784 | 1208 MB |
| `usuarios` | 58.466.304 | 21.905.408 | 80.371.712 | 77 MB |

Los valores proceden de `pg_table_size`, `pg_indexes_size` y `pg_total_relation_size`. El tamaño completo de la base incluye además otras relaciones y archivos del catálogo, por lo que puede superar la suma de estas seis tablas. Las unidades legibles se conservan tal como las muestra PostgreSQL.

Además de las consultas de `06_verificacion_final.sql`, guardar estas salidas para verificar el calendario y los turnos actuales.

```sql
SELECT
    MIN("fechaHora") AT TIME ZONE 'America/Argentina/Buenos_Aires'
        AS primera_tutoria,
    MAX("fechaHora") AT TIME ZONE 'America/Argentina/Buenos_Aires'
        AS ultima_tutoria
FROM public.tutorias;

SELECT
    EXTRACT(
        YEAR FROM "fechaHora" AT TIME ZONE 'America/Argentina/Buenos_Aires'
    )::integer AS anio,
    COUNT(*) AS tutorias
FROM public.tutorias
GROUP BY 1
ORDER BY 1;

SELECT
    "horaInicio",
    "horaFin",
    COUNT(DISTINCT "profesorId") AS profesores,
    COUNT(*) AS horarios
FROM public.horarios_disponibles
GROUP BY "horaInicio", "horaFin"
ORDER BY "horaInicio";
```

Comparar con las tablas de distribución anteriores. La última sesión esperada comienza el 16 de noviembre de 2026 a las 22:00 de Argentina y termina a las 23:00. En UTC su inicio corresponde al 17 de noviembre a la 01:00. Usar la conversión de zona indicada para validar el límite por fecha local.

## Resultados de la carga anterior del 9 al 10 de noviembre de 2026

Estas capturas preceden a la ampliación del calendario a 2022–2026 y a la distribución de profesores en tres turnos. Se conservan como mediciones de esa ejecución y deben complementarse con las de la versión actual.

La captura del registro de lotes muestra seis lotes de 1.000.000 confirmados. Las capturas de consultas a las tablas confirman los siguientes conteos. Las marcas de tiempo del registro están expresadas en UTC. El inicio visible fue el 10 de noviembre a las 02:26 UTC y el fin a las 03:08 UTC, equivalentes al 9 de noviembre a las 23:26 y al 10 a las 00:08 en Argentina.

| Tabla | Esperado | Resultado observado |
|---|---:|---|
| `usuarios` | 200.002 | 200.002, confirmado por captura |
| `categorias` | 100 | 100, confirmado por captura |
| `precios` | 10 | Pendiente de adjuntar conteo final |
| `profesores_categorias` | 400.000 | 400.000, confirmado por captura |
| `horarios_disponibles` | 400.000 | Carga comunicada como terminada, pendiente de adjuntar conteo final |
| `tutorias` | 6.000.000 | 6.000.000, confirmado por captura |

### Distribución observada

| Estado | Virtual | Presencial | Total |
|---|---:|---:|---:|
| Pendiente | 800.000 | 400.000 | 1.200.000 |
| Aceptada | 400.000 | 200.000 | 600.000 |
| Rechazada | 400.000 | 200.000 | 600.000 |
| Finalizada | 2.400.000 | 1.200.000 | 3.600.000 |
| Total | 4.000.000 | 2.000.000 | 6.000.000 |

La captura confirma pago simulado para las finalizadas y `pagada = false` para los demás estados.

### Tamaño medido

| Medición | Bytes |
|---|---:|
| Base antes de cargar tutorías | 175.684.631 |
| Base al finalizar | 1.469.463.575 |
| Crecimiento | 1.293.778.944 |

PostgreSQL informó `1401 MB` como tamaño final. La medición inicial corresponde al momento previo a la carga de tutorías, después de cargar catálogos, usuarios, asignaciones y horarios. Para el crecimiento del conjunto completo se necesita la salida inicial de prevalidación.

La captura de tamaño de relaciones muestra estos valores. `pg_table_size` incluye los archivos de la tabla y su almacenamiento auxiliar. Los índices se informan por separado.

| Tabla | Tabla y almacenamiento auxiliar, bytes | Índices, bytes | Total, bytes |
|---|---:|---:|---:|
| `categorias` | 49.152 | 32.768 | 81.920 |
| `profesores_categorias` | 30.154.752 | 20.070.400 | 50.225.152 |
| `tutorias` | 1.153.458.176 | 140.279.808 | 1.293.737.984 |
| `usuarios` | 58.466.304 | 21.905.408 | 80.371.712 |

Falta adjuntar los tamaños de precios y horarios. La verificación actual ya incluye las seis tablas. El tamaño de la base corresponde a una copia PostgreSQL y excluye la suma de las réplicas y los archivos adicionales de los volúmenes, como WAL.

### Registro de tiempos

La captura confirma los seis lotes, pero recorta parte de los decimales de sus duraciones. Para conservar la precisión del registro, queda pendiente exportar la salida de la consulta 10 de `06_verificacion_final.sql` y el detalle siguiente.

```sql
SELECT lote, registros, inicio, fin, duracion
FROM pt23_dataset.lotes
ORDER BY lote;
```

La suma de `duracion` mide el trabajo SQL desde la creación de la configuración temporal hasta terminar la inserción del lote, antes del `COMMIT`. El tiempo completo informado por pgAdmin debe conservarse aparte. Los tiempos de usuarios, asignaciones, horarios y catálogos requieren registros propios. Los tiempos de la primera ejecución, documentados más abajo, corresponden a esa versión anterior.

### Evidencias pendientes para cerrar la verificación

- Exportar el conteo de las seis tablas y los resultados `coincide` y `completo`.
- Guardar las salidas de referencias, roles, fechas, tarifas, disponibilidad y superposiciones. El resultado esperado es cero para cada consulta de inválidos.
- Guardar la comprobación de pagos duplicados y el inventario de restricciones e índices.
- Adjuntar los tiempos completos de los seis lotes y el tamaño inicial de prevalidación si se necesita medir el conjunto completo.
- Confirmar el login de un administrador, un profesor y un alumno con las credenciales compartidas por el equipo.

Las capturas de la nueva carga verifican los conteos y tamaños indicados. Los ceros de integridad comunicados en la primera ejecución se conservan como evidencia histórica. Los nuevos controles de horarios, tarifas y superposiciones requieren sus propias salidas.

## Resultados históricos de la primera ejecución del 9 de noviembre de 2026

Estos resultados corresponden al generador anterior, con 51 categorías, usuarios sin contraseña y fechas y precios generados con otras reglas. La nueva ejecución está documentada en el apartado anterior. Las consultas nuevas de horarios y tarifas pueden detectar diferencias si se aplican al dataset histórico.

Los resultados siguientes proceden de las salidas de pgAdmin compartidas durante la carga. Los totales incluyen las cuentas y asignaciones previas.

| Tabla | Registros finales |
|---|---:|
| `usuarios` | 200.000 |
| `categorias` | 100 |
| `profesores_categorias` | 400.000 |
| `tutorias` | 6.000.000 |

El conteo previo comunicado para categorías fue 55. La captura final muestra 51 y es la referencia utilizada en este documento. La causa de esa diferencia queda pendiente de identificar.

| Estado | Virtual | Presencial | Total |
|---|---:|---:|---:|
| Pendiente | 800.000 | 400.000 | 1.200.000 |
| Aceptada | 400.000 | 200.000 | 600.000 |
| Rechazada | 400.000 | 200.000 | 600.000 |
| Finalizada | 2.400.000 | 1.200.000 | 3.600.000 |
| Total | 4.000.000 | 2.000.000 | 6.000.000 |

Las finalizadas tienen `pagada = true`. El resto tiene `pagada = false`. Los pagos son simulados.

### Tamaño

| Medición | Bytes |
|---|---:|
| Base antes de cargar las tutorías | 123.706.391 |
| Base al finalizar | 1.394.121.751 |
| Crecimiento | 1.270.415.360 |

PostgreSQL informó `1330 MB` para el tamaño final. La medición corresponde a una base con `pg_database_size`, sin sumar las copias de las réplicas ni todos los archivos de los volúmenes Docker. El valor inicial se tomó después de cargar usuarios y asignaciones y de eliminar el piloto de tutorías. Puede incluir espacio reutilizable de esa prueba. El tamaño inicial de la base antes de generar usuarios debe conservarse en la salida de `01_prevalidacion.sql` si se requiere medir el crecimiento del conjunto completo.

### Tiempos de tutorías

| Lote | Registros | Duración SQL |
|---|---:|---|
| 1 | 1.000.000 | 00:01:43.515759 |
| 2 | 1.000.000 | 00:01:33.927955 |
| 3 | 1.000.000 | 00:04:24.787228 |
| 4 | 1.000.000 | 00:02:48.928012 |
| 5 | 1.000.000 | 00:04:48.174146 |
| 6 | 1.000.000 | 00:03:36.782593 |
| Total | 6.000.000 | 00:18:56.115693 |

El intervalo entre el inicio del primer lote exitoso y el fin del último fue `00:39:51.970199`. Incluye pausas y el período de la desconexión. La suma de duraciones corresponde a los lotes exitosos y termina antes del `COMMIT`. La preparación anterior a `pt23_config`, el intento fallido y los tiempos de usuarios y asignaciones quedan fuera de esa suma. No se dispone de una medición completa de carga de todas las tablas ni de los tiempos de confirmación de pgAdmin en las evidencias compartidas.

### Verificación e incidencias

- Se confirmó el conteo real de 6.000.000 de tutorías mediante consulta a la tabla.
- Las consultas de referencias y roles inválidos y de importes y fechas inválidos devolvieron cero, según el resultado comunicado por el responsable.
- El script final incluye la comprobación de pagos sintéticos duplicados y el inventario de restricciones e índices. Falta adjuntar sus salidas antes de declarar completa esa evidencia.
- La primera carga de usuarios se canceló por una verificación costosa. Se reemplazó por lotes con tablas temporales indexadas y se confirmó que el rollback dejó cero usuarios sintéticos de ese intento.
- Se eliminó el piloto de 100.000 tutorías antes de ejecutar los seis lotes definitivos.
- El primer intento del lote 3 perdió la conexión. Después de reconectar se comprobaron los lotes confirmados y la ausencia de una sesión de carga activa antes de repetirlo. La causa de la desconexión queda sin determinar.
- Se separó `ANALYZE` de las consultas finales para evitar el error al establecer el aislamiento después de consultas previas en la misma transacción.

Los conteos son resultados de esta instalación. Otras instalaciones pueden tener más cuentas o asignaciones iniciales. Las capturas y exportaciones originales de pgAdmin deben conservarse junto con la entrega como respaldo de estos resultados.
