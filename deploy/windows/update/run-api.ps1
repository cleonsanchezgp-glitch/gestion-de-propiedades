[CmdletBinding()]
param([string]$InstallRoot,[switch]$CheckOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# In Windows PowerShell 5.1 PSScriptRoot can be empty during default-parameter
# evaluation when launched with -File. Resolve it after parameter binding.
if(-not $PSBoundParameters.ContainsKey('InstallRoot')){$InstallRoot=Split-Path -Path $PSScriptRoot -Parent}
if([string]::IsNullOrWhiteSpace($InstallRoot)){throw 'Installation root is required.'}
function CheckedPath([string]$Base,[string]$Relative) {
    if ($Relative -cnotmatch '^[a-zA-Z0-9_./-]+$' -or @($Relative.Split('/') | Where-Object { -not $_ -or $_ -in @('.','..') -or $_.EndsWith('.') }).Count) {throw 'Unsafe application path.'}
    $result=[IO.Path]::GetFullPath((Join-Path $Base $Relative))
    $current=$result
    while ($current) {
        if (Test-Path -LiteralPath $current) {if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Application path contains reparse point.'}}
        $current=[IO.Path]::GetDirectoryName($current)
    }
    if (-not $result.StartsWith($Base.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Application path escapes installation.'}
    return $result
}
function JsonFile([string]$File) {
    if ((Get-Item -LiteralPath $File).Length -gt 1048576) {throw 'Oversized application metadata.'}
    Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
}
$root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$selector=JsonFile (CheckedPath $root 'config/active-release.json')
if (@($selector.PSObject.Properties.Name).Count -ne 4 -or $selector.format -ne 1 -or $selector.releaseId -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$' -or $selector.path -cne ('releases/'+$selector.releaseId) -or $selector.manifestSha256 -cnotmatch '^[a-f0-9]{64}$') {throw 'Invalid active release selector.'}
$releasePath=CheckedPath $root $selector.path
$manifestPath=CheckedPath $releasePath 'manifest.json'
if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $selector.manifestSha256) {throw 'Active manifest integrity failed.'}
$manifest=JsonFile $manifestPath
if ($manifest.format -ne 2 -or $manifest.kind -cne 'application-update' -or $manifest.product -cne 'aelium-propiedades' -or $manifest.platform -cne 'windows-x64' -or $manifest.releaseId -cne $selector.releaseId) {throw 'Active manifest identity failed.'}
$seen=@{}
foreach ($file in $manifest.files) {
    if ($file.path -cnotin @('bin/propiedades-backend.exe','scripts/run-api.ps1','scripts/application.ps1','docs/LEEME.md') -or $file.target -cnotin @('release','stable') -or ($file.target -ceq 'stable' -and $file.path -cne 'scripts/run-api.ps1') -or $seen.ContainsKey($file.path)) {throw 'Invalid active inventory.'}
    $seen[$file.path]=$true
    $base=if ($file.target -ceq 'stable') {$root} else {$releasePath}
    $actual=CheckedPath $base $file.path
    if ((Get-Item -LiteralPath $actual).Length -ne $file.size -or (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) {throw 'Active application integrity failed.'}
}
if (-not $seen.ContainsKey('bin/propiedades-backend.exe')) {throw 'Active executable missing.'}
$operation=JsonFile (CheckedPath $root 'maintenance/operation.json')
$expected=if ($operation.phase -cin @('Recovering','Recovered')) {$operation.sourceReleaseId} else {$operation.targetReleaseId}
if ($operation.format -ne 1 -or $operation.phase -cnotin @('Verifying','Committing','Committed','Recovering','Recovered') -or $expected -cne $selector.releaseId -or ($operation.phase -cin @('Committed','Recovered') -and $operation.checksPassed -ne $true)) {throw 'Installation is not in a permitted startup state.'}
$null=CheckedPath $root 'maintenance/write-gate.lock'
if (-not (Test-Path -LiteralPath (Join-Path $root 'maintenance/write-gate.lock') -PathType Leaf)) {throw 'Maintenance write gate missing.'}
$binary=CheckedPath $releasePath 'bin/propiedades-backend.exe'
if ($CheckOnly) {return [pscustomobject]@{status='StartupMetadataVerified';releaseId=$selector.releaseId;executable=$binary;installRoot=$root;schemaChecked=$false}}
$info=& $binary --release-info
if ($LASTEXITCODE -ne 0) {throw 'Cannot identify active executable.'}
$info=$info | ConvertFrom-Json
if ($info.transactionalMigrations -ne $true -or $info.releaseId -cne $manifest.releaseId -or $info.buildId -cne $manifest.buildId -or $info.apiContract -cne $manifest.apiContract -or @($info.migrations).Count -ne @($manifest.schemaAfter).Count) {throw 'Executable metadata differs from active manifest.'}
for ($index=0;$index -lt @($info.migrations).Count;$index++) {
    if ($info.migrations[$index].version -cne $manifest.schemaAfter[$index].version -or $info.migrations[$index].checksum -cne $manifest.schemaAfter[$index].checksum) {throw 'Executable migrations differ from active manifest.'}
}
$settings=JsonFile (CheckedPath $root 'config/api.json')
$env:DATABASE_URL='postgres://propiedades:'+[Uri]::EscapeDataString($settings.ApiDbPassword)+'@127.0.0.1:'+$settings.PgPort+'/propiedades'
$env:BACKEND_BIND='127.0.0.1:'+$settings.ApiPort
$env:KEYCLOAK_ISSUER='http://127.0.0.1:'+$settings.KeycloakPort+'/realms/propiedades'
$env:KEYCLOAK_AUDIENCE='propiedades-api'
$env:KEYCLOAK_ALLOWED_SUBJECT=$settings.OwnerSubject
$env:KEYCLOAK_LOGIN_CLIENT_ID='portal-login'
$env:KEYCLOAK_LOGIN_CLIENT_SECRET=$settings.LoginSecret
$env:PORTAL_ORIGIN=$settings.PortalOrigin
$available=$false
for ($attempt=0;$attempt -lt 90;$attempt++) {
    try { $null=Invoke-WebRequest -UseBasicParsing -Uri ($env:KEYCLOAK_ISSUER+'/.well-known/openid-configuration') -TimeoutSec 2;$available=$true;break } catch {Start-Sleep -Seconds 2}
}
if (-not $available) {throw 'Private identity service unavailable.'}
& $binary --serve --no-migrate --install-root $root
exit $LASTEXITCODE
