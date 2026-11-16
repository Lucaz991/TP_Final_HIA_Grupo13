# Ejecutar desde PowerShell, con Docker y el cluster iniciados.
# Usa las credenciales existentes dentro del servicio backup.
param(
    [Parameter(Mandatory = $true)]
    [string]$Destino
)

$ErrorActionPreference = 'Stop'
$proyecto = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$compose = Join-Path $proyecto 'compose.yaml'

if (-not (Test-Path -LiteralPath $compose)) {
    throw "No se encontro compose.yaml."
}

New-Item -ItemType Directory -Path $Destino -Force | Out-Null
$destinoReal = (Resolve-Path -LiteralPath $Destino).Path
$identificador = (Get-Date -Format 'yyyyMMdd-HHmmss') +
    '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)

$nombre = "tpFinal-$identificador"
$archivo = Join-Path $destinoReal "$nombre.dump"
$parcial = "$archivo.partial"
$inventario = Join-Path $destinoReal "$nombre-inventario.txt"
$registro = Join-Path $destinoReal "$nombre-registro.json"
$remoto = "/tmp/$nombre.dump"
$inicio = Get-Date

$informe = [ordered]@{
    base = 'tpFinal'
    conexion = 'proxy:5465'
    inicio = $inicio.ToString('o')
    estado = 'iniciado'
    restauracion_verificada = $false
}

try {
    $contenedores = @(
        & docker compose --project-directory $proyecto `
            -f $compose ps -q backup
    )

    if ($LASTEXITCODE -ne 0 -or $contenedores.Count -ne 1) {
        throw 'No se pudo identificar el contenedor backup iniciado.'
    }

    $contenedor = $contenedores[0].Trim()

    # El programa se envia por stdin; las credenciales solo se
    # expanden dentro del contenedor.
    $programa = @'
set -eu
umask 077
: "${DB_ADMIN_USER:?Falta DB_ADMIN_USER}"
: "${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD}"
export PGPASSWORD="$DB_ADMIN_PASSWORD"
export PGCONNECT_TIMEOUT=10

origen=$(psql -X -w -h proxy -p 5465 -U "$DB_ADMIN_USER" -d tpFinal -At -v ON_ERROR_STOP=1 -c "SELECT current_database() || '|' || pg_is_in_recovery()::text")
if [ "$origen" != "tpFinal|false" ]; then
    echo "La conexion no corresponde al lider de tpFinal." >&2
    exit 1
fi

pg_dump -w -h proxy -p 5465 -U "$DB_ADMIN_USER" \
    -d tpFinal --format=custom --file="$1"

pg_restore --list "$1" > "$1.list"
'@

    $programaLinux = $programa.Replace("`r`n", "`n") + "`n# fin"

    $programaLinux |
        & docker exec -i $contenedor sh -s -- $remoto

    if ($LASTEXITCODE -ne 0) {
        throw 'Fallo el backup o la lectura de su inventario.'
    }

    $informe['segundos_backup_e_inventario'] =
        [math]::Round(((Get-Date) - $inicio).TotalSeconds, 3)

    # docker cp conserva el archivo binario.
    & docker cp "${contenedor}:$remoto" $parcial
    if ($LASTEXITCODE -ne 0) {
        throw 'Fallo la copia del backup a Windows.'
    }

    & docker cp "${contenedor}:$remoto.list" $inventario
    if ($LASTEXITCODE -ne 0) {
        throw 'Fallo la copia del inventario.'
    }

    $salidaHash = @(
        & docker exec $contenedor sha256sum $remoto
    )
    if ($LASTEXITCODE -ne 0 -or $salidaHash.Count -ne 1) {
        throw 'No se pudo calcular el hash del archivo original.'
    }

    $hashRemoto = ($salidaHash[0] -split '\s+')[0]
    $hashLocal = (Get-FileHash -LiteralPath $parcial `
        -Algorithm SHA256).Hash

    if ($hashRemoto -ne $hashLocal) {
        throw 'La copia tiene un SHA-256 diferente del original.'
    }

    Move-Item -LiteralPath $parcial -Destination $archivo

    $informe['archivo'] = $archivo
    $informe['bytes'] = (Get-Item -LiteralPath $archivo).Length
    $informe['sha256'] = $hashLocal
    $informe['estado'] = 'backup_verificado_restauracion_pendiente'

    # Eliminar solo los temporales de esta ejecucion.
    & docker exec $contenedor rm -- $remoto "$remoto.list"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'El backup esta guardado; quedaron temporales en backup.'
    }

    Write-Host "Backup guardado: $archivo"
    Write-Host "Inventario: $inventario"
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