param([Parameter(Mandatory=$true)][string]$InstallationRoot)
. (Join-Path $PSScriptRoot '../../deploy/windows/update/Package.ps1')
$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts/updates')).TrimEnd('\')+'\'
$root=[IO.Path]::GetFullPath($InstallationRoot);Assert-NoReparse $root
if (-not $root.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) {throw 'Gate holder is restricted to synthetic update roots.'}
$ready=Join-Path $root 'maintenance/gate-ready.fixture'
$release=Join-Path $root 'maintenance/gate-release.fixture'
$gate=[IO.File]::Open((Join-Path $root 'maintenance/write-gate.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
try {
    $gate.Lock(0,1);[IO.File]::WriteAllText($ready,'ready')
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $release)) {Start-Sleep -Milliseconds 50}
}finally{$gate.Dispose()}
