[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ContentRoot,
    [Parameter(Mandatory=$true)][string]$DefinitionPath,
    [Parameter(Mandatory=$true)][string]$OutputArchive,
    [switch]$SyntheticFixture
)
. (Join-Path $PSScriptRoot 'update/Package.ps1')
$content = [IO.Path]::GetFullPath($ContentRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputArchive)
Assert-NoReparse $content; Assert-NoReparse $output
if (Test-Path -LiteralPath $output) { throw 'Output already exists; release archives are never overwritten.' }
Assert-NoReparse ($output + '.sha256')
if (Test-Path -LiteralPath ($output + '.sha256')) { throw 'External reference already exists; it is never overwritten.' }
if ($output.StartsWith($content + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be outside the content directory.' }
$manifest = Read-UpdateJson $DefinitionPath
Assert-UpdateList $manifest.files
foreach ($file in $manifest.files) {
    Assert-Fields $file @('path','target'); Assert-UpdatePath $file.path
    $source = Join-Path $content $file.path
    $file | Add-Member -NotePropertyName size -NotePropertyValue (Get-Item -LiteralPath $source -Force).Length
    $file | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-UpdateFileHash $source)
}
Assert-Manifest $manifest
if ($SyntheticFixture) {
    $testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../tests/artifacts/updates')).TrimEnd('\')+'\'
    if (-not $content.StartsWith($testRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $manifest.releaseId.StartsWith('fixture-',[StringComparison]::Ordinal) -or -not $manifest.buildId.StartsWith('fixture-',[StringComparison]::Ordinal)) {throw 'Synthetic packages are restricted to the test fixture directory and identities.'}
} else {
    $binary=Join-Path $content 'bin/propiedades-backend.exe'
    $info=& $binary --release-info
    if ($LASTEXITCODE -ne 0) {throw 'Cannot identify the candidate executable.'}
    $info=ConvertFrom-UpdateJson ($info -join "`n")
    if ($info.product -cne 'aelium-propiedades' -or $info.transactionalMigrations -ne $true -or $info.releaseId -cne $manifest.releaseId -or $info.buildId -cne $manifest.buildId -or $info.apiContract -cne $manifest.apiContract -or -not (Test-MigrationEquality $info.migrations $manifest.schemaAfter)) {throw 'Candidate executable metadata differs from package definition or needs a separate migration plan.'}
}
$inventory = @(Get-ChildItem -LiteralPath $content -Recurse -Force)
foreach ($item in $inventory) { Assert-NoReparse $item.FullName }
$actual = @($inventory | Where-Object { -not $_.PSIsContainer } | ForEach-Object { $_.FullName.Substring($content.Length + 1).Replace('\','/') })
if ($actual.Count -ne $manifest.files.Count) { throw 'Content directory must contain exactly the declared payload.' }
foreach ($name in $actual) { if ($name -cnotin @($manifest.files.path)) { throw 'Undeclared content file.' } }
$ledgerPath = Join-Path ([IO.Path]::GetDirectoryName($output)) 'release-ledger.json'
Assert-NoReparse $ledgerPath; Assert-NoReparse ($ledgerPath + '.lock')
$lock = [IO.File]::Open($ledgerPath + '.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
    $ledger = [pscustomobject]@{format=1;releases=@()}
    if (Test-Path -LiteralPath $ledgerPath) { $ledger = Read-UpdateJson $ledgerPath }
    Assert-Fields $ledger @('format','releases')
    if ($ledger.format -ne 1 -or $ledger.releases -isnot [array]) { throw 'Invalid release ledger.' }
    foreach ($release in $ledger.releases) {
        Assert-Fields $release @('releaseId','buildId','archiveSha256')
        Assert-UpdateId $release.releaseId; Assert-UpdateId $release.buildId; Assert-UpdateHash $release.archiveSha256
        if ($release.releaseId -ieq $manifest.releaseId -or $release.buildId -ieq $manifest.buildId) { throw 'Release/build ID already recorded; use a new identity, or distribute the original ZIP unchanged.' }
    }
    $zip = [IO.Compression.ZipFile]::Open($output,[IO.Compression.ZipArchiveMode]::Create)
    try {
    $entry = $zip.CreateEntry('manifest.json')
    $writer = New-Object IO.StreamWriter($entry.Open(), (New-Object Text.UTF8Encoding($false)))
    try { $writer.Write(($manifest | ConvertTo-Json -Depth 20)) } finally { $writer.Dispose() }
    foreach ($file in $manifest.files) { [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $content $file.path),$file.path,[IO.Compression.CompressionLevel]::Optimal) | Out-Null }
    } finally { $zip.Dispose() }
$hash = Get-UpdateFileHash $output
$null = Test-UpdateArchive $output $hash
# This sidecar must travel through an authenticated channel independent of the ZIP.
[IO.File]::WriteAllText($output + '.sha256', $hash + '  ' + [IO.Path]::GetFileName($output) + [Environment]::NewLine, [Text.Encoding]::ASCII)
    $ledger.releases = @($ledger.releases) + @([pscustomobject]@{releaseId=$manifest.releaseId;buildId=$manifest.buildId;archiveSha256=$hash})
    $temporaryLedger = $ledgerPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporaryLedger,($ledger | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $ledgerPath) { [IO.File]::Replace($temporaryLedger,$ledgerPath,[NullString]::Value) }
    else { [IO.File]::Move($temporaryLedger,$ledgerPath) }
[pscustomobject]@{status='PackageBuilt';releaseId=$manifest.releaseId;buildId=$manifest.buildId;sha256=$hash;archive=$output;clientUpdateReady=$false}
} finally { $lock.Dispose() }
