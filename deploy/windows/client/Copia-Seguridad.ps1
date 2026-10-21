[CmdletBinding()]
param([string]$Destino='')
. (Join-Path $PSScriptRoot 'Common.ps1')
$root = Split-Path $PSScriptRoot -Parent
$s = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config/settings.json') | ConvertFrom-Json
if (-not $Destino) { $Destino=Join-Path $root ('backups/'+(Get-Date -Format 'yyyyMMdd-HHmmss')) }
$destination = [IO.Path]::GetFullPath($Destino)
if (Test-Path -LiteralPath $destination) { throw 'Choose a new backup directory; existing files will not be overwritten.' }
New-Item -ItemType Directory -Path $destination | Out-Null
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $destination /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' (('*'+$sid)+':(OI)(CI)F') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot secure backup directory.' }
$env:PGPASSWORD = $s.PostgresPassword
try {
    foreach ($db in @('propiedades','keycloak')) {
        $file = Join-Path $destination ($db+'.dump')
        & (Join-Path $root 'postgresql/bin/pg_dump.exe') -h 127.0.0.1 -p $s.PgPort -U postgres -d $db -Fc -f $file
        if ($LASTEXITCODE -ne 0) { throw ('Backup failed: '+$db+'. The partial backup must not be used.') }
        & (Join-Path $root 'postgresql/bin/pg_restore.exe') --list $file | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Backup archive validation failed.' }
    }
    Copy-Item -LiteralPath (Join-Path $root 'config/settings.json') -Destination (Join-Path $destination 'settings.json')
    $hashes = Get-ChildItem -LiteralPath $destination -File | ForEach-Object { @{file=$_.Name;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash} }
    Write-Utf8 (Join-Path $destination 'backup.json') (@{createdUtc=[DateTime]::UtcNow.ToString('o');postgres='16';files=@($hashes)} | ConvertTo-Json -Depth 5)
    Write-Host ('Copia completa: '+$destination+'. Guardela cifrada fuera del servidor.')
} finally { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
