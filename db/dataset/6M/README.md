# PT-23 — Dataset de seis millones de tutorías

La tabla seleccionada para la prueba de volumen es `public.tutorias`. La carga agrega 6.000.000 de tutorías, 100.000 alumnos, 100.000 profesores y 400.000 asignaciones profesor–categoría. Reutiliza las categorías de la aplicación y conserva los registros anteriores.

## Requisitos

- Clúster PostgreSQL inicializado con el esquema de la aplicación y sus datos iniciales. Las tablas y los tipos ENUM provienen de los modelos Sequelize del backend.
- Al menos cuatro categorías disponibles. La ejecución documentada utilizó 51.
- Backend actualizado con `sequelize.sync()` y el índice único de precios sobre `(nivel, modalidad)`.
- pgAdmin conectado a `tpFinal` mediante `proxy`, puerto `5432`, con un usuario autorizado para insertar datos y crear tablas y restricciones.
- Auto-commit activado, una pestaña sin transacciones pendientes y una sola ejecución de carga a la vez.
- Backend detenido después de inicializar el esquema. Mantener estables los usuarios, las categorías y las asignaciones durante la carga y la verificación.

Cada instalación local tiene su propia base. Para reproducir el dataset se ejecutan estos scripts o se restaura un respaldo de la base cargada.

## Orden de ejecución

| Archivo | Ejecución |
|---|---|
| [00_restriccion_precios.sql](00_restriccion_precios.sql) | Una vez. Comprueba duplicados y asegura una tarifa por nivel y modalidad. Admite repetir su ejecución. |
| [01_prevalidacion.sql](01_prevalidacion.sql) | Una vez antes de generar datos. Guardar conteos, tamaño inicial y resultados de integridad. |
| [02_usuarios.sql](02_usuarios.sql) | Diez ejecuciones, modificando `desde` y `hasta` según la tabla siguiente. Cada rango agrega hasta 10.000 alumnos y 10.000 profesores. |
| [03_asignaciones.sql](03_asignaciones.sql) | Diez ejecuciones con los mismos rangos. Cada rango agrega hasta 40.000 asignaciones. |
| [04_tutorias.sql](04_tutorias.sql) | Seis ejecuciones completas, cambiando únicamente `lote` de 1 a 6. Cada una agrega 1.000.000 de tutorías. |
| [05_verificacion_final.sql](05_verificacion_final.sql) | Ejecutar los cuatro `ANALYZE` como bloque separado. Después ejecutar individualmente las consultas numeradas y guardar sus resultados. |

| Ejecución de usuarios o asignaciones | Desde | Hasta |
|---|---:|---:|
| 1 | 1 | 10000 |
| 2 | 10001 | 20000 |
| 3 | 20001 | 30000 |
| 4 | 30001 | 40000 |
| 5 | 40001 | 50000 |
| 6 | 50001 | 60000 |
| 7 | 60001 | 70000 |
| 8 | 70001 | 80000 |
| 9 | 80001 | 90000 |
| 10 | 90001 | 100000 |

Esperar la finalización de cada ejecución antes de iniciar la siguiente. Ante un error, ejecutar `ROLLBACK;` en la misma pestaña antes de volver a usarla. Registrar también el tiempo total informado por pgAdmin.

## Método de generación

Se utiliza SQL con `generate_series`, tablas temporales indexadas y estadísticas actualizadas mediante `ANALYZE`. Las claves primarias se asignan con las secuencias existentes. Los scripts mantienen habilitadas las restricciones del esquema.

Los usuarios nuevos se identifican mediante emails como `alumno.1@example.invalid` y `profesor.1@example.invalid`, con apellido `Sintético`. `ON CONFLICT (email) DO NOTHING` permite repetir un rango. Las contraseñas sintéticas son nulas. Para ingresar a la aplicación se utilizan las cuentas iniciales.

### Actualizar usuarios de una base ya cargada

La carga documentada se realizó inicialmente con emails como `pt23.alumno.1@example.invalid` y apellido `Sintético PT-23`. Para adoptar el formato nuevo, detener el backend y ejecutar [06_actualizar_usuarios.sql](06_actualizar_usuarios.sql) una vez. El script verifica colisiones de emails antes de actualizar, conserva los IDs y las relaciones y permite repetir su ejecución. Si falla, ejecutar `ROLLBACK;` en la misma pestaña y revisar el mensaje.

Este paso corresponde a instalaciones que ya tienen los usuarios anteriores. Debe realizarse antes de volver a ejecutar los generadores actualizados. `02_usuarios.sql` se detiene si encuentra el formato antiguo para evitar crear un segundo conjunto de usuarios. En una instalación nueva se sigue el orden del 00 al 05 directamente.

Las mediciones históricas de esta documentación corresponden a la carga anterior al cambio de emails. La actualización requiere volver a medir el tamaño si se necesita documentar el estado posterior.

Las categorías se numeran por ID y cada profesor recibe cuatro categorías diferentes. La clave compuesta y `ON CONFLICT` evitan pares repetidos. El catálogo debe permanecer estable entre ejecuciones.

Las tutorías se generan mediante 60 rondas de 100.000 alumnos, agrupadas en seis transacciones. Una permutación distribuye los profesores y una rotación selecciona sus categorías. Al completar la carga, cada alumno y profesor sintético participa en 60 tutorías y cada categoría asignada a un profesor se utiliza 15 veces.

Las fechas abarcan del 1 de enero al 23 de octubre de 2026. Los importes varían entre 5.000 y 15.000. Los mensajes alternan entre cinco textos. Las tutorías virtuales aceptadas o finalizadas incluyen enlaces como `https://meet.example.com/123456` y un identificador de evento ficticio. Las finalizadas incluyen identificadores de preferencia y pago ficticios. Los campos de las tutorías nuevas carecen del texto `pt23`.

Los identificadores `INTEGER` se conservan porque admiten hasta 2.147.483.647 valores positivos, por encima del volumen de esta prueba. Las cancelaciones y los conflictos pueden consumir números de secuencia y dejar saltos válidos.

## Registro y reanudación

`04_tutorias.sql` crea el esquema auxiliar `pt23_dataset` y las tablas `ejecucion` y `lotes`. La primera guarda el punto de partida de la carga de tutorías. La segunda registra cantidad y duración por lote.

Las tutorías y el registro de su lote se confirman dentro de la misma transacción. Si un lote ya figura como confirmado, se omite su inserción. Esta comprobación presupone conservar tanto los datos como las tablas de control. Para iniciar otro dataset desde cero hace falta planificar explícitamente su limpieza.

Tras una desconexión, reconectar mediante el proxy, comprobar el líder y consultar `pt23_dataset.lotes`. Si el lote no aparece, verificar que la sesión anterior haya terminado antes de repetirlo. El script emplea un bloqueo asesor para serializar sus ejecuciones.

## Resultados de la ejecución del 9 de noviembre de 2026

Los resultados siguientes proceden de las salidas de pgAdmin compartidas durante la carga. Los totales incluyen las cuentas y asignaciones previas.

| Tabla | Registros finales |
|---|---:|
| `usuarios` | 200.014 |
| `categorias` | 51 |
| `profesores_categorias` | 400.014 |
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
