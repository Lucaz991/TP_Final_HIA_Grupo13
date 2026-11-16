param(
    [Parameter(Mandatory = $true)]
    [string]$Archivo,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string]$Sha256Esperado
)

$ErrorActionPreference = 'Stop'
$contenedor = 'postgres-restauracion'
$base = 'tpFinal_restaurada'
$usuario = 'backup_admin'

$archivoReal = (Resolve-Path -LiteralPath $Archivo).Path
$carpeta = Split-Path -Parent $archivoReal
$id = (Get-Date -Format 'yyyyMMdd-HHmmss') +
    '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)

$remoto = "/tmp/restauracion-$id.dump"
$registro = Join-Path $carpeta "restauracion-$id.json"
$log = Join-Path $carpeta "restauracion-$id.log"
$inicio = Get-Date

$informe = [ordered]@{
    archivo = $archivoReal
    contenedor = $contenedor
    base = $base
    inicio = $inicio.ToString('o')
    estado = 'iniciado'
    integridad_datos_verificada = $false
    propietarios_y_permisos_restaurados = $false
}

try {
    $hash = (Get-FileHash -LiteralPath $archivoReal `
        -Algorithm SHA256).Hash

    if ($hash -ne $Sha256Esperado) {
        throw 'El SHA-256 no coincide con el respaldo registrado.'
    }
    $informe['sha256'] = $hash

    # No sobrescribir una base utilizada en una ejecucion anterior.
    $consulta = @"
SELECT
  (SELECT COUNT(*) FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema')
  +
  (SELECT COUNT(*) FROM pg_type t
   JOIN pg_namespace n ON n.oid = t.typnamespace
   WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema')
  +
  (SELECT COUNT(*) FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema')
  +
  (SELECT COUNT(*) FROM pg_namespace
   WHERE nspname !~ '^pg_'
     AND nspname NOT IN ('public', 'information_schema'));
"@

    $objetos = @(
        & docker exec $contenedor psql -X -w `
            -U $usuario -d $base -At `
            -v ON_ERROR_STOP=1 -c $consulta
    )

    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudo consultar la base de restauracion.'
    }
    if ($objetos.Count -ne 1 -or $objetos[0].Trim() -ne '0') {
        throw 'La base contiene objetos. Se cancela sin sobrescribirlos.'
    }

    Write-Host 'Copiando el respaldo al entorno de prueba...'
    & docker cp $archivoReal "${contenedor}:$remoto"
    if ($LASTEXITCODE -ne 0) {
        throw 'Fallo la copia al contenedor.'
    }

    $salidaHash = @(
        & docker exec $contenedor sha256sum $remoto
    )
    if ($LASTEXITCODE -ne 0 -or $salidaHash.Count -ne 1) {
        throw 'No se pudo verificar la copia.'
    }
    if (($salidaHash[0] -split '\s+')[0] -ne $hash) {
        throw 'La copia dentro del contenedor tiene un hash diferente.'
    }

    & docker exec $contenedor pg_restore --list $remoto |
        Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudo leer el inventario del respaldo.'
    }

    Write-Host 'Restaurando estructura, datos, indices y restricciones...'
    $inicioRestauracion = Get-Date
    $preferenciaAnterior = $ErrorActionPreference

    try {
        # PowerShell 5.1 puede tratar stderr nativo como ErrorRecord.
        # El resultado se determina mediante el codigo de salida.
        $ErrorActionPreference = 'Continue'

        & docker exec $contenedor pg_restore `
            -U $usuario -d $base `
            --no-owner --no-privileges `
            --single-transaction --exit-on-error --verbose `
            $remoto 2>&1 |
            ForEach-Object { $_.ToString() } |
            Tee-Object -FilePath $log

        $codigo = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $preferenciaAnterior
    }

    $informe['codigo_salida'] = $codigo
    $informe['segundos_restauracion'] =
        [math]::Round(
            ((Get-Date) - $inicioRestauracion).TotalSeconds, 3
        )

    if ($codigo -ne 0) {
        throw "Fallo la restauracion. Revisar $log"
    }

    $informe['estado'] = 'restaurado_verificacion_datos_pendiente'

    & docker exec $contenedor rm -- $remoto
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'La restauracion termino; quedo el archivo temporal.'
    }

    Write-Host "Restauracion completada en $base."
}
catch {
    $informe['estado'] = 'fallido'
    $informe['error'] = $_.Exception.Message
    throw
}
finally {
    $informe['fin'] = (Get-Date).ToString('o')
    $informe['segundos_totales'] =
        [math]::Round(((Get-Date) - $inicio).TotalSeconds, 3)

    $informe | ConvertTo-Json |
        Set-Content -LiteralPath $registro -Encoding UTF8

    Write-Host "Registro: $registro"
}