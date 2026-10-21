[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallRoot,
    [string]$OutputPath = (Join-Path $env:USERPROFILE 'Desktop\promalza-inventario-cliente.json')
)

# Read-only inventory for reviewing a managed Promalza/Aelium Windows installation.
# It does not start/stop services, modify files, or print configuration secrets.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RelativePath([string]$Base,[string]$Path) {
    $baseFull=[IO.Path]::GetFullPath($Base).TrimEnd('\')+'\'
    $pathFull=[IO.Path]::GetFullPath($Path)
    if ($pathFull.StartsWith($baseFull,[StringComparison]::OrdinalIgnoreCase)) {
        return $pathFull.Substring($baseFull.Length).Replace('\','/')
    }
    return '[outside-installation]'
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    if ((Get-Item -LiteralPath $Path).Length -gt 1048576) { throw 'Metadata file exceeds the safe read limit.' }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
}

function Get-FileRecord([string]$Root,[string]$RelativePath) {
    $full=Join-Path $Root ($RelativePath.Replace('/','\'))
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    $item=Get-Item -LiteralPath $full
    $version=$null
    try { $version=$item.VersionInfo.FileVersion } catch {}
    [pscustomobject]@{
        path=$RelativePath
        sizeBytes=[long]$item.Length
        sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        fileVersion=$version
    }
}

$root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Installation root does not exist.' }

$metadata=Read-JsonFile (Join-Path $root 'config/active-release.json')
$settings=Read-JsonFile (Join-Path $root 'config/settings.json')
$apiSettings=Read-JsonFile (Join-Path $root 'config/api.json')
$serviceNames=@('AeliumAPI','AeliumPostgres','AeliumKeycloak','AeliumTunnel')
$services=@(foreach ($name in $serviceNames) {
    $svc=Get-CimInstance Win32_Service -Filter ("Name='"+$name+"'") -ErrorAction SilentlyContinue
    if ($svc) {
        [pscustomobject]@{
            name=$svc.Name;state=$svc.State;startMode=$svc.StartMode;account=$svc.StartName
            executable=(Get-RelativePath $root (($svc.PathName -replace '^"([^"]+)".*$','$1' -replace '\s+.*$','')))
        }
    }
})

$knownFiles=@(
    'bin/propiedades-backend.exe','scripts/run-api.ps1','scripts/application.ps1','scripts/Common.ps1',
    'scripts/run-keycloak.ps1','scripts/Administrar.ps1','scripts/Copia-Seguridad.ps1',
    'services/AeliumAPI.exe','services/AeliumPostgres.exe','services/AeliumKeycloak.exe','services/AeliumTunnel.exe',
    'postgresql/bin/postgres.exe','postgresql/bin/pg_ctl.exe','postgresql/bin/psql.exe',
    'keycloak/bin/kc.bat','java/bin/java.exe','cloudflared.exe'
)
$files=@(foreach ($relative in $knownFiles) { $record=Get-FileRecord $root $relative; if ($record) {$record} })
$codeFiles=@(foreach ($relativeDirectory in @('scripts','bin','services','keycloak/conf')) {
    $directory=Join-Path $root $relativeDirectory
    if (Test-Path -LiteralPath $directory -PathType Container) {
        Get-ChildItem -LiteralPath $directory -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
            ForEach-Object {
                $relative=Get-RelativePath $root $_.FullName
                [pscustomobject]@{path=$relative;sizeBytes=[long]$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
            }
    }
})

$activeRelease=$null
$releaseInfo=$null
if ($metadata -and $metadata.releaseId) { $activeRelease=[string]$metadata.releaseId }
$backendCandidates=@((Join-Path $root 'bin/propiedades-backend.exe'))
if ($activeRelease) { $backendCandidates+=Join-Path $root ('releases/'+$activeRelease+'/bin/propiedades-backend.exe') }
foreach ($backend in $backendCandidates) {
    if (Test-Path -LiteralPath $backend -PathType Leaf) {
        try {
            $raw=& $backend --release-info 2>$null
            if ($LASTEXITCODE -eq 0) { $releaseInfo=($raw | ConvertFrom-Json -ErrorAction Stop); break }
        } catch {}
    }
}

$migrationHistory=@()
$schemaStatus='Unavailable'
$pgExe=Join-Path $root 'postgresql/bin/psql.exe'
if ($apiSettings -and $apiSettings.ApiDbPassword -and (Test-Path -LiteralPath $pgExe -PathType Leaf)) {
    $oldPassword=[Environment]::GetEnvironmentVariable('PGPASSWORD','Process')
    try {
        $env:PGPASSWORD=[string]$apiSettings.ApiDbPassword
        $port=[string]$apiSettings.PgPort
        $raw=& $pgExe -X -q -A -t -h 127.0.0.1 -p $port -U propiedades -d propiedades -v ON_ERROR_STOP=1 -c "SELECT COALESCE(json_agg(json_build_object('version',version::text,'checksum',encode(checksum,'hex'),'success',success) ORDER BY version::bigint)::text,'[]') FROM public._sqlx_migrations" 2>$null
        if ($LASTEXITCODE -eq 0) { $migrationHistory=@(($raw | Out-String | ConvertFrom-Json -ErrorAction Stop)); $schemaStatus='Read' }
        else { $schemaStatus='QueryFailed' }
    } catch { $schemaStatus='QueryFailed' }
    finally { [Environment]::SetEnvironmentVariable('PGPASSWORD',$oldPassword,'Process') }
}

$frontend=$null
$portalOrigin=$null
if ($settings -and $settings.PortalOrigin -and ([string]$settings.PortalOrigin -match '^https://[^/]+$')) {
    try {
        $response=Invoke-WebRequest -UseBasicParsing -Uri ([string]$settings.PortalOrigin+'/release.json') -TimeoutSec 10 -MaximumRedirection 0
        if ($response.StatusCode -eq 200 -and $response.Content.Length -lt 65536) {
            $data=$response.Content | ConvertFrom-Json -ErrorAction Stop
            $portalOrigin=([Uri]$settings.PortalOrigin).GetLeftPart([UriPartial]::Authority)
            $frontend=[pscustomobject]@{status='Read';releaseId=$data.releaseId;apiContract=$data.apiContract;compatibleApiContracts=@($data.compatibleApiContracts)}
        }
    } catch { $frontend=[pscustomobject]@{status='Unavailable'} }
}
if (-not $frontend) { $frontend=[pscustomobject]@{status='NotConfiguredOrUnavailable'} }

$result=[pscustomobject]@{
    format=1
    scope='Read-only client installation inventory; no service, configuration, database or application changes'
    observedUtc=[DateTime]::UtcNow.ToString('o')
    machine=[pscustomobject]@{windowsProduct=(Get-CimInstance Win32_OperatingSystem).Caption;windowsVersion=(Get-CimInstance Win32_OperatingSystem).Version;architecture=(Get-CimInstance Win32_OperatingSystem).OSArchitecture}
    installationRoot=$root
    configuration=[pscustomobject]@{
        settingsPresent=[bool]$settings;apiSettingsPresent=[bool]$apiSettings;activeSelectorPresent=[bool]$metadata
        activeReleaseId=$activeRelease;portalOrigin=$portalOrigin
    }
    executableReleaseInfo=$releaseInfo
    files=$files
    applicationCodeFiles=$codeFiles
    services=$services
    database=[pscustomobject]@{migrationHistoryStatus=$schemaStatus;migrations=$migrationHistory}
    frontend=$frontend
}

$parent=Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Output directory does not exist; choose an existing directory.' }
$json=$result | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$json,(New-Object Text.UTF8Encoding($false)))
Write-Output ('Inventory written: '+[IO.Path]::GetFullPath($OutputPath))
Write-Output 'Review the JSON before sharing. It omits secrets and tenant data but includes service layout, hashes, release IDs, and the configured portal hostname.'
