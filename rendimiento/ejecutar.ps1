param(
    [ValidateSet('profesores','tutorias','listado','resumen','mensual')]
    [string]$Escenario = 'profesores',
    [ValidateSet(1,10,25,50,100)][int]$Usuarios = 1,
    [ValidateRange(5,600)][int]$Segundos = 120,
    [string]$Etiqueta = 'actual',
    [string]$BaseUrl = 'http://localhost:3000',
    [string]$PrometheusUrl = 'http://localhost:9090'
)
$ErrorActionPreference = 'Stop'
if (-not $env:RENDIMIENTO_TOKEN -and -not $env:H23_TOKEN) { throw 'Definir RENDIMIENTO_TOKEN con un token obtenido al iniciar sesion.' }
if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) { throw 'Instalar k6 y abrir una nueva terminal.' }
if ($Etiqueta -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Etiqueta: solo letras, numeros, guion y guion bajo.' }
$carpeta = Join-Path $PSScriptRoot ('resultados/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + "-$Etiqueta-$Escenario-$Usuarios")
New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
$env:ESCENARIO = $Escenario
$env:USUARIOS = "$Usuarios"
$env:BASE_URL = $BaseUrl
$scriptCarga = Join-Path $PSScriptRoot 'carga.js'
# Calentamiento separado: sus muestras no entran en el resumen de medicion.
$env:DURACION = '30s'
& k6 run $scriptCarga
if ($LASTEXITCODE -ne 0) { throw 'Fallo el calentamiento. No se inicia la medicion.' }
$inicio = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$env:DURACION = "${Segundos}s"
& k6 run --summary-export (Join-Path $carpeta 'resumen.json') $scriptCarga 2>&1 |
    Tee-Object -FilePath (Join-Path $carpeta 'salida.txt')
$codigo = $LASTEXITCODE
$fin = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
@{ escenario=$Escenario; usuarios=$Usuarios; segundos=$Segundos; etiqueta=$Etiqueta;
   inicioUTC=$inicio; finUTC=$fin; baseUrl=$BaseUrl; exitCode=$codigo;
   commit=(& git rev-parse HEAD); k6=(& k6 version) } |
    ConvertTo-Json | Set-Content (Join-Path $carpeta 'ejecucion.json') -Encoding UTF8
$consultas = @{
    disponibilidad='up'
    cpu='rate(container_cpu_usage_seconds_total{image!=""}[1m])'
    memoria='container_memory_working_set_bytes{image!=""}'
    postgres='pg_up'
    conexiones='pg_stat_database_numbackends'
    transacciones='rate(pg_stat_database_xact_commit[1m])'
    rollback='rate(pg_stat_database_xact_rollback[1m])'
    temporales='rate(pg_stat_database_temp_bytes[1m])'
    bloques_leidos='rate(pg_stat_database_blks_read[1m])'
    cache='rate(pg_stat_database_blks_hit[1m])'
    conflictos='pg_stat_database_deadlocks'
}
foreach ($nombre in $consultas.Keys) {
    try {
        $q = [Uri]::EscapeDataString($consultas[$nombre])
        $r = Invoke-RestMethod "$PrometheusUrl/api/v1/query_range?query=$q&start=$inicio&end=$fin&step=15" -TimeoutSec 15
        $r | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $carpeta "$nombre.json") -Encoding UTF8
        if ($r.status -ne 'success' -or @($r.data.result).Count -eq 0) { Write-Warning "Sin series para $nombre; registrar limitacion." }
    } catch { Write-Warning "No se pudo capturar ${nombre}: $($_.Exception.Message)" }
}
Write-Host "Resultados: $carpeta"
if ($codigo -ne 0) { throw 'Prueba fallida o interrumpida: revisar resultados antes de aumentar usuarios.' }
