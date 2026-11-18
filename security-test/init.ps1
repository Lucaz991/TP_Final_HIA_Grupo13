$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path $PSScriptRoot -Parent) '.env.security-test'
if (Test-Path $target) {
    Write-Host '.env.security-test ya existe; se conservan las credenciales.'
    exit 0
}

function New-TestSecret {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

$lines = @(
    '# Credenciales generadas para H24. No reutilizar fuera de este entorno.'
    "SECURITY_DB_ROOT_PASSWORD=$(New-TestSecret)"
    "SECURITY_DB_PASSWORD=$(New-TestSecret)"
    "SECURITY_JWT_SECRET=$(New-TestSecret)"
    "SECURITY_ACCOUNT_PASSWORD=$(New-TestSecret)"
)
[IO.File]::WriteAllLines($target, $lines, [Text.UTF8Encoding]::new($false))
Write-Host 'Creado .env.security-test. La clave de las cuentas ficticias es SECURITY_ACCOUNT_PASSWORD.'
