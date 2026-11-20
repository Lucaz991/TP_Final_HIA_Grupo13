# Rendimiento - Rendimiento y concurrencia

Documento unico con procedimiento, resultados HTTP, recursos y analisis SQL. Las tablas conservan las metricas por ejecucion; no se requiere un CSV separado.

Para actualizar resultados: ejecutar ./rendimiento/consolidar.ps1 desde la raiz. No genera carga. Se requieren las mediciones originales en resultados/.

## Procedimiento

## Alcance

Se mide HTTP hacia el backend local y su recorrido por HAProxy al primario. No se mide renderizado Angular, Cloudflare ni servicios externos. Solo GET: no crear reservas, pagos o eventos de calendario. El login previo puede registrar una auditoria.

| Escenario | Operacion | Cuenta |
| --- | --- | --- |
| profesores | Galeria, pagina 1 de 12 profesores, asociaciones y opiniones | Usuario existente |
| tutorias | Mis tutorias, pagina 1 de 50 | Alumno o profesor con tutorias |
| listado | Listado administrativo, pagina 1 de 50 | Admin |
| resumen | Indicadores generales | Admin |
| mensual | Agrupacion mensual del anio actual | Admin |

## Preparar

1. Comprobar `docker compose ps` y los targets en http://localhost:9090/targets. Abrir Grafana en http://localhost:3001.
2. Instalar k6 en Windows con `winget install --id GrafanaLabs.k6 --exact --source winget`, abrir una nueva PowerShell y comprobar `k6 version`.
3. Iniciar sesion normalmente en la aplicacion con la cuenta adecuada. Copiar su JWT desde las herramientas de desarrollo, sin compartirlo ni guardarlo en archivos del repositorio:

```powershell
$env:RENDIMIENTO_TOKEN = Read-Host 'Pega el token JWT'
```

Para obtenerlo: abrir F12 en el navegador, ir a Red/Network, seleccionar Fetch/XHR y recargar la pagina. Abrir una solicitud a `/api/` (por ejemplo `tutoria?page=1&limit=50`) y buscar Authorization en Headers -> Request Headers. Copiar solo el token posterior a `Bearer `, sin esa palabra. Al ejecutar Read-Host, los dos puntos indican que PowerShell espera el token: pegarlo y pulsar Enter. No compartirlo en chats, capturas, commits ni archivos.

Ejecutar la prueba desde la raiz del proyecto y en la misma ventana de PowerShell donde se cargo el token. La variable dura solo esa sesion; si se cierra la terminal o vence el token, obtener uno valido y cargarlo de nuevo. Cada integrante debe usar su propia sesion: usuario existente para profesores, alumno/profesor con tutorias para tutorias, y administrador para listado, resumen y mensual. El token debe corresponder a la misma instalacion del backend que se prueba; por defecto se usa http://localhost:3000.

No repetir el login en cada iteracion: esta limitado a cinco solicitudes por IP en 15 minutos. No desactivar esa proteccion ni fabricar tokens. Para tutorias, usar una cuenta con datos; una respuesta vacia es valida tecnicamente pero no representa ese escenario.

## Ejecutar por etapas

Desde la raiz, primero una comprobacion con un usuario:

```powershell
./rendimiento/ejecutar.ps1 -Escenario profesores -Usuarios 1 -Segundos 15 -Etiqueta comprobacion
```

Luego ejecutar individualmente 10, 25, 50 y 100 usuarios para cada escenario, revisando cada resultado antes del siguiente:

```powershell
./rendimiento/ejecutar.ps1 -Escenario profesores -Usuarios 10 -Etiqueta actual
```

Cada ejecucion separa 30 s de calentamiento de 120 s de medicion, con una pausa de 1 s por iteracion. Usuarios virtuales son sesiones concurrentes, no necesariamente personas distintas: por defecto comparten cuenta, filtros y primera pagina. Esto favorece cache y limita la representatividad. No equivale a 100 solicitudes por segundo ni a una simulacion de navegadores completos.

Repetir tres veces cada combinacion para evaluar variacion. Esperar a que CPU, memoria y latencia vuelvan al nivel previo entre ejecuciones. Detener con Ctrl+C ante degradacion sostenida, falta de memoria o errores. El script corta si los errores funcionales alcanzan 5 % tras el periodo inicial; este umbral es una regla operativa, no un SLA acordado. Revisar tambien los timeouts y la salida de k6. No subir de nivel si falla.

Los resultados se guardan en una carpeta por ejecucion, ignorada por Git. `resumen.json` registra latencia media, p90/p95/p99, solicitudes/s, errores HTTP y errores funcionales. Se comprueban HTTP 200 y estructura de respuesta para evitar contar errores de negocio como exitos. No se guardan cuerpos de respuesta ni tokens. La prevalidacion de setup agrega una solicitud al resumen; indicarlo especialmente en ejecuciones cortas.

El script consulta Prometheus al finalizar: CPU en nucleos, memoria en bytes, conexiones, transacciones, rollbacks, bloques, temporales y deadlocks. Verificar series por servicio/nodo y `up=1` durante toda la ventana. Una serie vacia significa metrica no disponible, nunca consumo cero. Las tasas de 1 minuto incluyen parte del calentamiento. Las metricas de base son agregadas e incluyen trafico de otros servicios. Conservar capturas de Grafana con el intervalo UTC de ejecucion. Para pruebas interrumpidas puede ser necesario exportar manualmente las metricas.

## Evidencia del entorno y analisis

Registrar CPU/RAM del host, recursos asignados a Docker Desktop, versiones reales, conteos de tablas, indices instalados, nodo lider, configuracion activa de PostgreSQL y servicios que comparten equipo. Si el generador corre en el mismo host, observar tambien su consumo: compite con el sistema probado. No dar por vigente la configuracion bootstrap de Patroni sin consultar el cluster.

Hipotesis a verificar, no cuellos de botella demostrados: espera del pool de Sequelize, agregaciones del dashboard, consultas de opiniones por profesor, ordenamiento/paginacion, disco y competencia por recursos. Correlacionar aumento de p95/errores y estancamiento de throughput con las metricas y planes SQL antes de concluir.

## Comparacion e informe

Los antecedentes de `../db/optimizacion/README.md` son mediciones SQL con otro volumen de calificaciones y no constituyen una linea base HTTP comparable. No borrar indices de la base actual para reconstruirla. Para antes/despues usar un entorno aislado con mismo dataset, recursos, cuentas, parametros y duracion; registrar commits y cambio concreto. Si no existe esa base, declarar comparacion historica no disponible y comparar escalabilidad 10/25/50/100 sin atribuir mejoras a optimizaciones.

Completar un informe con: entorno y limitaciones; escenarios; metodologia; tabla de resultados por repeticion (promedio, p95, p99, req/s, errores HTTP/funcionales, CPU y memoria maxima, conexiones); comparacion; evidencia de cuellos de botella; conclusiones y recomendaciones. Conservar las muestras originales y resumir medianas entre repeticiones, sin mezclar percentiles de distintas ejecuciones. Rendimiento queda pendiente hasta ejecutar las pruebas, analizar evidencia y elaborar el informe con resultados reales.

Al terminar, retirar el token de la terminal:

```powershell
Remove-Item Env:RENDIMIENTO_TOKEN
```


## Evidencia SQL

# Rendimiento - Evidencia SQL y cambio mensual

Planes aportados por el responsable el 17/11/2026. Validacion de equivalencia mensual: cero diferencias en el dataset y sesion utilizados. Version, zona y configuracion activa aun pendientes de adjuntar. Los planes completos fueron compartidos en la conversacion; conservar tambien los originales exportados de pgAdmin.

| Mensual | Muestra 1 ms | Muestra 2 ms | Muestra 3 ms | Mediana ms |
| --- | ---: | ---: | ---: | ---: |
| EXTRACT sobre createdAt | 975.219 | 927.856 | 898.581 | 927.856 |
| Rango anual semiabierto | 215.145 | 302.392 | 219.451 | 219.451 |

La mediana baja 76.35 %, factor 4.23. Condiciones de cache variables: esto es una comparacion SQL preliminar, no una mejora HTTP certificada.

Original: Index Only Scan sobre tutorias_creada_id con filtro posterior EXTRACT, unas 6 millones de entradas recorridas, subestimacion de filas y ordenamiento external merge con temporales. Candidata: Index Cond por rango, unas 1.645 millones de filas seleccionadas, agregacion parcial hash y ordenamiento final de 11 grupos en memoria, sin temporales. No se suman bloques de nodos padre/hijo porque sus contadores incluyen descendientes.

Otros planes: agregacion financiera 1370.457 y 1062.194 ms, escaneo secuencial paralelo de tutorias; promedio de calificaciones 1233.632 ms, escaneo secuencial paralelo de 3.6 millones de filas; conteo global 261.267 y 175.396 ms, Index Only Scan paralelo sobre tutorias_alumno; seleccion de 50 IDs 0.056 y 0.039 ms, Index Only Scan sobre tutorias_creada_id. La seleccion rapida de IDs no mide la carga posterior de asociaciones ni el endpoint completo. Shared Read no demuestra lectura fisica de disco: puede resolverse desde cache del sistema operativo.

## Implementacion y comprobacion

Se modifica unicamente el predicado de getTutorialsByMonth en admin.controller.js. Se mantienen TO_CHAR, COUNT(id), agrupacion, orden y estructura JSON. Limites calculados por PostgreSQL con NOW y la zona de la sesion; intervalo [inicio del anio, inicio del siguiente). No se crean indices ni se modifican datos o ajustes de memoria.

Comprobacion local: sintaxis JavaScript y diff. Equivalencia SQL con cero diferencias informada por el responsable. El responsable reconstruyo el backend y compartio logs de arranque correcto. Se completo la comprobacion HTTP y las mediciones mensual 10/25 con etiqueta mensual_rango, sin errores. Comparacion consolidada en README-RENDIMIENTO.md y README-RENDIMIENTO.md. Las etiquetas se conservan separadas de actual. Las versiones comparten HEAD porque el cambio no estaba committeado: no confundir SHA con identidad de imagen. Pendiente repetir para evaluar variacion y completar registro del entorno.


## Antecedente del analisis de profesores

# Rendimiento - Resultados parciales: galeria de profesores

Primera ejecucion por nivel, realizada el 16/11/2026 (hora Argentina). Fuente: carpetas `resultados/*-actual-profesores-{10,25,50,100}`, archivos resumen.json, ejecucion.json y exportaciones de Prometheus. No incluye repeticiones ni otros escenarios. Los archivos originales deben conservarse: estan ignorados por Git.

## Condiciones

Backend http://localhost:3000, GET /api/usuario?rol=profesor&page=1&limit=12. Cuenta compartida por usuarios virtuales, primera pagina fija, pausa de 1 s entre iteraciones, 30 s de calentamiento separado y 120 s de medicion. Cada resumen incluye una solicitud adicional de prevalidacion. Commit registrado: d9fc4b5e44f62ca24aaba1cf7872d06f4e0880b3; no verifica que la imagen desplegada corresponda a ese commit. Generador k6 2.4.0 en Windows. Recursos de Docker y hardware pendientes de registrar. No mide el navegador ni el tunel publico.

## HTTP

| Usuarios | Solicitudes | Promedio ms | p95 ms | p99 ms | Solicitudes/s | Errores HTTP/funcionales |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 1061 | 136.56 | 168.24 | 199.73 | 8.80 | 0 % |
| 25 | 2296 | 317.20 | 355.71 | 419.84 | 18.93 | 0 % |
| 50 | 3843 | 578.76 | 694.54 | 797.23 | 31.63 | 0 % |
| 100 | 5696 | 1111.23 | 1347.78 | 1409.42 | 47.25 | 0 % |

El throughput crece menos que la concurrencia. De 50 a 100 usuarios crece 49.4 %, mientras la latencia media crece 92 %. No se ha encontrado el maximo de capacidad ni validado un SLA.

## Recursos observados

Promedios de muestras exportadas, sin interpolar ni sumar series de contenedores. CPU expresada en nucleos utilizados: 1.00 equivale al consumo de un nucleo completo, no al 100 % de todo el host. Memoria working set en MiB (bytes / 1048576). Tasas CPU usan ventanas de 1 minuto e incluyen parte del calentamiento.

| Usuarios | CPU backend media | CPU node3 media | Backend memoria maxima MiB | Node3 memoria maxima MiB |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 0.117 | 0.401 | 152.4 | 909.1 |
| 25 | 0.220 | 0.804 | 157.4 | 869.3 |
| 50 | 0.397 | 1.428 | 155.6 | 853.9 |
| 100 | 0.572 | 2.136 | 206.5 | 846.3 |

La actividad se concentra en node3; verificar su rol con Patroni antes de afirmar que fue el lider. Los otros nodos consumen poca CPU. En tpFinal de node3, no hubo tasa de rollbacks ni temporales y el contador de deadlocks fue cero en las muestras de estos cuatro niveles. En 100 usuarios se observaron hasta 13 conexiones a tpFinal, incluyendo conexiones ajenas al backend; esto no representa 100 conexiones PostgreSQL. En 50 y 100 usuarios no se observaron bloques leidos hacia buffers en las muestras, lo que limita extrapolar estos resultados a cache fria o a otros filtros.

## Hipotesis y limites

El codigo actual realiza cuatro consultas iniciales y despues una consulta secuencial de opiniones por profesor (hasta 12 en esta pagina): unas 16 consultas de Sequelize por solicitud con pagina completa. Es un candidato concreto para investigar el costo acumulado y las esperas bajo concurrencia, pendiente de confirmar en la imagen ejecutada y mediante trazas SQL. El pool no se configura explicitamente en database.js; no se midio su tiempo de espera. No se puede afirmar saturacion del pool ni de CPU sin datos adicionales de limites y esperas. Tampoco se midio presion de memoria del host o throttling.

## Continuacion

Validar Mis tutorias con una cuenta con datos y un usuario virtual; luego probar sus niveles 10/25/50/100 gradualmente. Completar escenarios administrativos con una cuenta admin. Repetir combinaciones para estudiar variacion. Registrar entorno real y contrastar hipotesis antes de introducir mejoras. Una comparacion antes/despues requiere mismos datos, recursos, parametros y codigo desplegado identificado; los antecedentes SQL no sustituyen esta comparacion HTTP.


<!-- RESULTADOS_RENDIMIENTO -->

# Rendimiento - Informe de rendimiento y concurrencia

Estado: informe de validacion preparado para revision de Rendimiento, con limitaciones explicitas. Primera ronda y comparacion HTTP mensual completadas, incluyendo tres repeticiones por nivel de la version optimizada. No se certifica capacidad maxima ni cumplimiento de un SLA.

## Entorno y metodo

Pruebas locales al backend http://localhost:3000, con k6 2.4.0 en Windows, 30 segundos de calentamiento separado y 120 segundos de carga por nivel. Pausa de un segundo por iteracion. Una cuenta por escenario y parametros fijos; tutorias devuelve 50 registros de 60 de la cuenta comprobada. Los usuarios virtuales no equivalen a personas distintas ni a solicitudes por segundo. No se mide el renderizado Angular o Cloudflare.

Docker reporta 16 CPU logicas y 7207546880 bytes de memoria (6.71 GiB), compartidos con otros servicios y el generador de carga. Commit registrado en las ejecuciones: d9fc4b5e44f62ca24aaba1cf7872d06f4e0880b3; falta comprobar correspondencia de las imagenes ejecutadas con ese codigo. Configuracion activa aportada por el responsable: max_connections=500; max_parallel_workers=8; max_parallel_workers_per_gather=2; shared_buffers=16384 bloques de 8 KiB (128 MiB); work_mem=4096 KiB (4 MiB). Son valores relevados despues de las pruebas, no una captura contemporanea a cada ejecucion. Identidad confirmada por captura del responsable: PostgreSQL 18.7 sobre Debian x86_64, base tpFinal y pg_is_in_recovery=false (conexion al primario en ese momento). Zona de la sesion confirmada por el responsable: Etc/UTC. No se identifica el nombre Patroni del nodo. Pendientes hardware del host y limites efectivos de contenedores.

Cada resumen incluye una solicitud de prevalidacion. El tiempo real puede superar 120 segundos por prevalidacion y finalizacion de iteraciones. Las comprobaciones cortas con un usuario se excluyen de esta tabla. Cada fila conserva una ejecucion, sin promediar ni combinar percentiles. Las fuentes exactas figuran en las tablas de este documento.

## Resultados HTTP

| Version | Escenario | Usuarios | Solicitudes | Promedio ms | p95 ms | p99 ms | Solicitudes/s | Error HTTP % | Error funcional % |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| actual | listado | 10 | 871 | 381.44 | 472.28 | 500.30 | 7.23 | 0.00 | 0.00 |
| actual | listado | 25 | 1455 | 1071.44 | 1252.24 | 1282.97 | 11.97 | 0.00 | 0.00 |
| actual | listado | 50 | 2292 | 1653.73 | 2124.51 | 2288.06 | 18.75 | 0.00 | 0.00 |
| actual | listado | 100 | 2596 | 3731.86 | 4442.43 | 4716.61 | 20.98 | 0.00 | 0.00 |
| actual | mensual | 10 | 436 | 1775.63 | 3424.76 | 3915.91 | 3.54 | 0.00 | 0.00 |
| mensual_rango | mensual | 10 | 1008 | 196.40 | 262.37 | 466.08 | 8.32 | 0.00 | 0.00 |
| mensual_rango | mensual | 10 | 1010 | 194.94 | 255.16 | 407.22 | 8.32 | 0.00 | 0.00 |
| mensual_rango | mensual | 10 | 1015 | 188.51 | 246.46 | 351.67 | 8.37 | 0.00 | 0.00 |
| actual | mensual | 25 | 459 | 5732.68 | 7332.12 | 7832.05 | 3.60 | 0.00 | 0.00 |
| mensual_rango | mensual | 25 | 1898 | 589.55 | 983.21 | 1121.52 | 15.61 | 0.00 | 0.00 |
| mensual_rango | mensual | 25 | 1879 | 606.89 | 1015.51 | 1188.63 | 15.43 | 0.00 | 0.00 |
| mensual_rango | mensual | 25 | 1874 | 611.18 | 1039.23 | 1182.71 | 15.40 | 0.00 | 0.00 |
| actual | profesores | 10 | 1061 | 136.56 | 168.25 | 199.74 | 8.80 | 0.00 | 0.00 |
| actual | profesores | 25 | 2296 | 317.21 | 355.72 | 419.84 | 18.93 | 0.00 | 0.00 |
| actual | profesores | 50 | 3843 | 578.76 | 694.54 | 797.23 | 31.63 | 0.00 | 0.00 |
| actual | profesores | 100 | 5696 | 1111.23 | 1347.78 | 1409.42 | 47.25 | 0.00 | 0.00 |
| actual | resumen | 10 | 548 | 1214.64 | 2161.16 | 2448.63 | 4.47 | 0.00 | 0.00 |
| actual | resumen | 25 | 590 | 4183.77 | 5191.53 | 5959.66 | 4.75 | 0.00 | 0.00 |
| actual | resumen | 50 | 605 | 9473.81 | 10287.22 | 10956.25 | 4.69 | 0.00 | 0.00 |
| actual | tutorias | 10 | 1191 | 8.63 | 11.50 | 18.97 | 9.91 | 0.00 | 0.00 |
| actual | tutorias | 25 | 2976 | 9.82 | 15.18 | 35.68 | 24.71 | 0.00 | 0.00 |
| actual | tutorias | 50 | 5951 | 10.05 | 15.30 | 47.37 | 49.38 | 0.00 | 0.00 |
| actual | tutorias | 100 | 11901 | 11.94 | 18.29 | 74.45 | 98.38 | 0.00 | 0.00 |

## Interpretacion

- Profesores: el promedio llega a 1111 ms y el p95 a 1348 ms con 100 usuarios. El codigo actual consulta opiniones por separado para cada profesor, candidato para investigar; no se midieron trazas de consultas de la imagen desplegada.
- Mis tutorias: en esta cuenta/pagina el throughput crece de 9.91 a 98.38 solicitudes/s con latencia media de 8.63 a 11.94 ms. Cache caliente y cuenta repetida limitan la generalizacion a otros usuarios y volumenes personales.
- Listado administrativo: de 50 a 100 usuarios el throughput crece solo 12 %, y el promedio pasa de 1654 a 3732 ms. Se observa degradacion y rendimiento marginal decreciente, sin errores.
- Resumen: de 25 a 50 usuarios el throughput permanece cerca de 4.7 solicitudes/s, mientras el promedio pasa de 4184 a 9474 ms. Se decidio no ejecutar 100 por demora creciente sin ganancia de throughput.
- Mensual: de 10 a 25 usuarios el throughput permanece cerca de 3.6 solicitudes/s, con promedio de 1776 a 5733 ms. Se decidio no ejecutar 50/100 por el mismo criterio operativo. Son niveles no ejecutados, no fallos medidos.

## Recursos y candidatos a cuello de botella

Las exportaciones de Prometheus contienen CPU, working set de memoria, conexiones y actividad de PostgreSQL. La actividad observada se concentra en node3, cuyo rol debe confirmarse con Patroni. CPU expresada en nucleos consumidos, no porcentaje de todo el host. Las tasas de un minuto incluyen parte del calentamiento y agregan trafico ajeno a la prueba.

Resumen con 25/50 usuarios: node3 usa en promedio 11.44/11.41 nucleos; backend cerca de 0.03. Mensual con 10/25: node3 usa 9.86/10.50 nucleos; backend cerca de 0.013/0.014. Esto apunta al trabajo SQL como principal candidato, sin demostrar que toda la CPU disponible estuviera saturada. No se midieron esperas del pool, throttling, presion de memoria del host ni planes durante carga. El numero de conexiones de base incluye clientes ajenos al backend.

## Comparacion y limitaciones

La etiqueta actual identifica la linea base; mensual_rango identifica el endpoint mensual tras reemplazar EXTRACT por un rango anual semiabierto. La comparacion utiliza los mismos parametros, concurrencia y duracion programada. El responsable reconstruyo el backend y verifico su arranque. Ambas versiones registran el mismo HEAD de Git porque el cambio estaba sin commit: ese SHA por si solo no identifica la version desplegada. Se conserva la etiqueta y el diff del controlador como evidencia adicional. Las mediciones se realizaron en horarios distintos; no se demostro aislamiento respecto de otros servicios. Los antecedentes SQL de db/optimizacion no se mezclan con estas mediciones HTTP.

## Mejora mensual antes/despues

El predicado anterior aplicaba EXTRACT a createdAt y recorria el indice completo antes de filtrar. El rango anual permite Index Cond sobre tutorias_creada_id. Los planes aportados muestran agregacion parcial hash y eliminacion de temporales. La validacion SQL devolvio cero diferencias; detalle en Rendimiento_ANALISIS_SQL.md. No se modificaron indices ni datos.

| Usuarios | Promedio antes/despues ms | p95 antes/despues ms | Solicitudes/s antes/despues | CPU media node3 antes/despues, nucleos |
| ---: | --- | --- | --- | --- |
| 10 | 1775.63 / 196.40 | 3424.76 / 262.37 | 3.54 / 8.32 | 9.86 / 4.34 |
| 25 | 5732.68 / 589.55 | 7332.12 / 983.21 | 3.60 / 15.61 | 10.50 / 10.47 |

En 10 usuarios, promedio -88.94 % y throughput x2.35; en 25, promedio -89.72 % y throughput x4.33. Sin errores HTTP o funcionales en ambas versiones. A 25 usuarios, CPU similar atiende muchas mas solicitudes. La tabla anterior conserva la primera pareja por nivel. Las repeticiones posteriores se incluyen en la tabla detallada y se resumen abajo; la version anterior conserva una sola muestra. Sin intervalo de confianza ni capacidad maxima certificada. No se extrapola la mejora a resumen o listado. Los valores de esta tabla son redondeados; los JSON originales conservan la precision completa.

La linea base y los otros escenarios tienen una ejecucion por combinacion. La version mensual optimizada tiene tres ejecuciones con 10 y tres con 25 usuarios, todas sin errores. Medianas entre ejecuciones: con 10 usuarios, promedio 194.94 ms, p95 255.16 ms y throughput 8.32 solicitudes/s; con 25, promedio 606.89 ms, p95 1015.51 ms y throughput 15.43 solicitudes/s. Son medianas de metricas por ejecucion, no percentiles globales de solicitudes combinadas. No se repitio aun la version anterior. Tampoco se prueban escrituras, navegacion mixta, cuentas diversas, paginas profundas o cache fria. No se establecio un SLA de latencia; ausencia de errores no implica experiencia aceptable.

## Criterios de aceptacion y evidencia

| Criterio | Evidencia y alcance |
| --- | --- |
| Escenarios definidos | Cinco operaciones GET documentadas en README y carga.js |
| Concurrencia probada | 10/25/50/100 en profesores, tutorias y listado; resumen hasta 50 y mensual original hasta 25 por degradacion documentada |
| Tiempos registrados | Promedio, p95 y p99 por ejecucion en tablas del informe |
| Throughput y errores | Solicitudes/s y errores HTTP/funcionales por ejecucion |
| Recursos observados | Exportaciones Prometheus y Rendimiento_RECURSOS.md; sin necesidad de Grafana |
| Cuellos de botella investigados | Agregaciones globales y filtro mensual sustentados con planes; esperas del pool no medidas |
| Comparacion realizada | SQL con equivalencia y HTTP mensual antes/despues; base con una muestra, optimizada con tres por nivel |
| Informe elaborado | Este informe unificado, SQL reproducible y mediciones originales |

## Recomendaciones y limites del cierre

Se propone revision y cierre de la historia con el alcance probado y las limitaciones declaradas. La aprobacion corresponde al equipo. Optimizar resumen, conteos del listado y opiniones de profesores puede planificarse en tareas posteriores. Como ampliacion de validacion: repetir la base, diversificar cuentas y paginas, medir esperas, confirmar identidad de imagen y limites efectivos de contenedores. Los indices aportados, PostgreSQL 18.7 y configuracion activa quedan documentados; el primario consultado no identifica retrospectivamente el rol de cada nodo durante todas las pruebas.

Conservar los originales en resultados/ junto con el informe. La carpeta esta ignorada por Git; el ZIP de evidencia permite adjuntarla a la entrega. No contiene archivos .env ni tokens por diseno de los scripts. Los planes completos de pgAdmin compartidos en la conversacion deben exportarse y adjuntarse por separado si la entrega exige sus JSON originales; el paquete incluye el resumen de esos planes y el SQL reproducible.
## CPU y memoria por ejecucion

CPU en nucleos y memoria working set en MiB. Tasas CPU de 1 minuto incluyen parte del calentamiento. NA indica serie ausente o ambigua, no consumo cero. No se suma backend con PostgreSQL.

| Fuente | CPU backend media | CPU node3 media | Memoria backend maxima MiB | Memoria node3 maxima MiB |
| --- | ---: | ---: | ---: | ---: |
| 20261116-234944-898-actual-listado-10 | 0.06 | 3.26 | 144.23 | 1439.29 |
| 20261116-235342-637-actual-listado-25 | 0.10 | 5.90 | 140.50 | 1209.95 |
| 20261117-000018-864-actual-listado-50 | 0.16 | 8.84 | 144.95 | 1156.77 |
| 20261117-000447-232-actual-listado-100 | 0.19 | 10.40 | 219.70 | 1135.75 |
| 20261117-002710-526-actual-mensual-10 | 0.01 | 9.86 | 95.07 | 1821.00 |
| 20261117-094733-917-mensual_rango-mensual-10 | 0.03 | 4.34 | 154.81 | 1266.87 |
| 20261117-104415-694-mensual_rango-mensual-10 | 0.03 | 4.12 | 140.22 | 1088.91 |
| 20261117-104905-472-mensual_rango-mensual-10 | 0.02 | 4.24 | 153.04 | 1078.86 |
| 20261117-003143-090-actual-mensual-25 | 0.01 | 10.50 | 93.19 | 1772.66 |
| 20261117-095144-730-mensual_rango-mensual-25 | 0.06 | 10.47 | 155.17 | 1183.91 |
| 20261117-105312-173-mensual_rango-mensual-25 | 0.05 | 10.61 | 153.45 | 1088.59 |
| 20261117-105807-509-mensual_rango-mensual-25 | 0.05 | 10.85 | 153.34 | 1084.10 |
| 20261116-221848-819-actual-profesores-10 | 0.12 | 0.40 | 152.39 | 909.14 |
| 20261116-222401-021-actual-profesores-25 | 0.22 | 0.80 | 157.36 | 869.33 |
| 20261116-222958-480-actual-profesores-50 | 0.40 | 1.43 | 155.62 | 853.85 |
| 20261116-223533-146-actual-profesores-100 | 0.57 | 2.14 | 206.50 | 846.26 |
| 20261117-001102-012-actual-resumen-10 | 0.03 | 11.06 | 109.36 | 1964.74 |
| 20261117-001456-846-actual-resumen-25 | 0.03 | 11.44 | 116.11 | 1926.12 |
| 20261117-002039-814-actual-resumen-50 | 0.03 | 11.41 | 102.25 | 1834.17 |
| 20261116-232920-988-actual-tutorias-10 | 0.06 | 0.02 | 151.43 | 794.62 |
| 20261116-233300-272-actual-tutorias-25 | 0.13 | 0.04 | 157.44 | 794.01 |
| 20261116-233637-398-actual-tutorias-50 | 0.26 | 0.07 | 217.71 | 784.17 |
| 20261116-234019-052-actual-tutorias-100 | 0.51 | 0.14 | 293.40 | 776.55 |
