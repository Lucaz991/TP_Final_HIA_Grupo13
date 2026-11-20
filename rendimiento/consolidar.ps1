$ErrorActionPreference = 'Stop'
$filas = @(foreach ($directorio in Get-ChildItem (Join-Path $PSScriptRoot 'resultados') -Directory) {
    $meta = Join-Path $directorio.FullName 'ejecucion.json'
    $resumen = Join-Path $directorio.FullName 'resumen.json'
    if (-not (Test-Path $meta) -or -not (Test-Path $resumen)) { continue }
    $e = Get-Content $meta -Raw | ConvertFrom-Json
    if ($e.etiqueta -notin @('actual','mensual_rango')) { continue }
    $m = (Get-Content $resumen -Raw | ConvertFrom-Json).metrics
    [pscustomobject]@{
        version=$e.etiqueta; escenario=$e.escenario; usuarios=$e.usuarios; solicitudes=$m.http_reqs.count
        promedio_ms=$m.http_req_duration.avg; p95_ms=$m.http_req_duration.'p(95)'
        p99_ms=$m.http_req_duration.'p(99)'; solicitudes_s=$m.http_reqs.rate
        errores_http_pct=100*$m.http_req_failed.value
        errores_funcionales_pct=100*$m.errores_funcionales.value
        exitCode=$e.exitCode; fuente=$directorio.Name
    }
})
$filas = @($filas | Sort-Object escenario,usuarios,fuente)
foreach ($fila in $filas) {
    $carpeta = Join-Path (Join-Path $PSScriptRoot 'resultados') $fila.fuente
    foreach ($servicio in @('backend','node3')) {
        $nombre = if ($servicio -eq 'backend') { 'app-backend' } else { 'tp_final_hia_grupo13-node3-1' }
        foreach ($tipo in @('cpu','memoria')) {
            $archivo = Join-Path $carpeta "$tipo.json"
            $valores = @()
            if (Test-Path $archivo) {
                $datos = Get-Content $archivo -Raw | ConvertFrom-Json
                $series = @($datos.data.result | Where-Object { $_.metric.name -eq $nombre })
                if ($series.Count -eq 1) {
                    $valores = @($series[0].values | ForEach-Object { [double]::Parse($_[1], [cultureinfo]::InvariantCulture) })
                }
            }
            $medida = $valores | Measure-Object -Average -Maximum
            if ($tipo -eq 'cpu') {
                $fila | Add-Member -NotePropertyName "${servicio}_cpu_media_nucleos" -NotePropertyValue $(if ($valores.Count) { $medida.Average } else { $null })
                $fila | Add-Member -NotePropertyName "${servicio}_cpu_maxima_nucleos" -NotePropertyValue $(if ($valores.Count) { $medida.Maximum } else { $null })
            } else {
                $fila | Add-Member -NotePropertyName "${servicio}_memoria_maxima_MiB" -NotePropertyValue $(if ($valores.Count) { $medida.Maximum / 1MB } else { $null })
            }
        }
    }
}
$cultura = [cultureinfo]::InvariantCulture
function Numero($valor) { ([double]$valor).ToString('F2', $cultura) }
$tabla = @(
    '| Version | Escenario | Usuarios | Solicitudes | Promedio ms | p95 ms | p99 ms | Solicitudes/s | Error HTTP % | Error funcional % |'
    '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
    foreach ($f in $filas) {
        "| $($f.version) | $($f.escenario) | $($f.usuarios) | $($f.solicitudes) | $(Numero $f.promedio_ms) | $(Numero $f.p95_ms) | $(Numero $f.p99_ms) | $(Numero $f.solicitudes_s) | $(Numero $f.errores_http_pct) | $(Numero $f.errores_funcionales_pct) |"
    }
)
$introduccion = @'
# Rendimiento - Informe de rendimiento y concurrencia

Estado: informe de validacion preparado para revision de Rendimiento, con limitaciones explicitas. Primera ronda y comparacion HTTP mensual completadas, incluyendo tres repeticiones por nivel de la version optimizada. No se certifica capacidad maxima ni cumplimiento de un SLA.

## Entorno y metodo

Pruebas locales al backend http://localhost:3000, con k6 2.4.0 en Windows, 30 segundos de calentamiento separado y 120 segundos de carga por nivel. Pausa de un segundo por iteracion. Una cuenta por escenario y parametros fijos; tutorias devuelve 50 registros de 60 de la cuenta comprobada. Los usuarios virtuales no equivalen a personas distintas ni a solicitudes por segundo. No se mide el renderizado Angular o Cloudflare.

Docker reporta 16 CPU logicas y 7207546880 bytes de memoria (6.71 GiB), compartidos con otros servicios y el generador de carga. Commit registrado en las ejecuciones: d9fc4b5e44f62ca24aaba1cf7872d06f4e0880b3; falta comprobar correspondencia de las imagenes ejecutadas con ese codigo. Configuracion activa aportada por el responsable: max_connections=500; max_parallel_workers=8; max_parallel_workers_per_gather=2; shared_buffers=16384 bloques de 8 KiB (128 MiB); work_mem=4096 KiB (4 MiB). Son valores relevados despues de las pruebas, no una captura contemporanea a cada ejecucion. Identidad confirmada por captura del responsable: PostgreSQL 18.7 sobre Debian x86_64, base tpFinal y pg_is_in_recovery=false (conexion al primario en ese momento). Zona de la sesion confirmada por el responsable: Etc/UTC. No se identifica el nombre Patroni del nodo. Pendientes hardware del host y limites efectivos de contenedores.

Cada resumen incluye una solicitud de prevalidacion. El tiempo real puede superar 120 segundos por prevalidacion y finalizacion de iteraciones. Las comprobaciones cortas con un usuario se excluyen de esta tabla. Cada fila conserva una ejecucion, sin promediar ni combinar percentiles. Las fuentes exactas figuran en las tablas de este documento.

## Resultados HTTP

'@
$conclusiones = @'

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
'@
$recursos = @(
    '## CPU y memoria por ejecucion'
    ''
    'CPU en nucleos y memoria working set en MiB. Tasas CPU de 1 minuto incluyen parte del calentamiento. NA indica serie ausente o ambigua, no consumo cero. No se suma backend con PostgreSQL.'
    ''
    '| Fuente | CPU backend media | CPU node3 media | Memoria backend maxima MiB | Memoria node3 maxima MiB |'
    '| --- | ---: | ---: | ---: | ---: |'
    foreach ($f in $filas) {
        $v = foreach ($campo in @('backend_cpu_media_nucleos','node3_cpu_media_nucleos','backend_memoria_maxima_MiB','node3_memoria_maxima_MiB')) {
            if ($null -eq $f.$campo) { 'NA' } else { Numero $f.$campo }
        }
        "| $($f.fuente) | $($v -join ' | ') |"
    }
)
$destino = Join-Path $PSScriptRoot 'README-RENDIMIENTO.md'
$documento = Get-Content $destino -Raw
$marca = '<!-- RESULTADOS_RENDIMIENTO -->'
$posicion = $documento.IndexOf($marca)
if ($posicion -lt 0) { throw 'Falta marcador de resultados en README-RENDIMIENTO.md' }
$contenido = $documento.Substring(0, $posicion) + $marca + "`n`n" + $introduccion + "`n" + ($tabla -join "`n") + "`n" + $conclusiones + "`n" + ($recursos -join "`n")
$contenido = $contenido.Replace('Solo se dispone de una ejecucion por combinacion.', 'Consultar el numero de repeticiones en la seccion de resultados.')
$contenido | Set-Content $destino -Encoding UTF8
Write-Host "Consolidadas $($filas.Count) ejecuciones. No se ejecutaron nuevas pruebas de carga."
