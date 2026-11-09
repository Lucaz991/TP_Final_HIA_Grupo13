# Datasets de prueba

## PT-23 · Carga de seis millones de tutorías

La carga masiva y sus instrucciones están en [6M/README.md](6M/README.md). Incluye generación por lotes, verificación, registro de tiempos y resultados de la ejecución. La tabla seleccionada para el requisito de seis millones es `tutorias`.

## PT-15 · Piloto del dataset de tutorías

El piloto genera 1.000 tutorías sintéticas en PostgreSQL. Incluye 200 pendientes, 100 aceptadas, 100 rechazadas y 600 finalizadas con pago simulado. Aproximadamente dos tercios de las finalizadas reciben una calificación sintética. Se conserva como antecedente de la carga masiva implementada en PT-23.
## Requisitos

- PostgreSQL levantado con Docker Compose y acceso a `tpFinal` desde pgAdmin.
- Esquema y datos iniciales cargados, con la tabla `tutorias` vacía.
- Al menos un alumno activo y un profesor activo con una asignación activa en `profesores_categorias`.

El backend utiliza `sequelize.sync()` para conservar las tablas existentes. Inicializá el esquema antes de cargar los datos y mantené el backend detenido durante las mediciones. Este piloto requiere `tutorias` vacía y se ejecuta antes de una carga masiva.

## Orden de carga

| Orden | Tablas | Datos y relaciones |
|---|---|---|
| 1 | `usuarios`, `categorias` y `profesores_categorias` | La carga reutiliza los alumnos activos y los pares activos de profesor y categoría. La tabla de asignaciones tiene una clave primaria compuesta por ambos IDs. |
| 2 | `tutorias` | El script genera fechas, modalidades, estados e importes con `generate_series`. Cada fila referencia un alumno y toma el profesor y la categoría del mismo par. |
| 3 | `calificaciones` | El script usa los IDs devueltos por la inserción para asociar como máximo una calificación a cada tutoría seleccionada. |

## Ejecución y verificación

1. Abrí el **Query Tool** de `tpFinal` y ejecutá las consultas de [consulta.sql](consulta.sql) por separado. Registrá el tamaño inicial de la base y confirmá que `tutorias_totales` sea 0.
2. Ejecutá [carga.sql](carga.sql) completo. La carga usa una transacción y se detiene si `tutorias` ya contiene filas. Guardá los conteos de inserción de **Mensajes** y el tiempo de ejecución que informa pgAdmin.
3. Volvé a ejecutar [consulta.sql](consulta.sql) antes de crear tutorías desde la aplicación. El resultado esperado es **1.000 tutorías y 0 inválidas**. La consulta verifica los roles del alumno y el profesor y la existencia de la asignación profesor–categoría.
4. Registrá el tamaño final en bytes, el tiempo de carga, la cantidad de tutorías y calificaciones insertadas y el resultado de la verificación.
