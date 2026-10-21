[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunDirectory)
. (Join-Path $PSScriptRoot '../../deploy/windows/update/Package.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'tests/artifacts/updates')).TrimEnd('\')+'\'
$run=[IO.Path]::GetFullPath($RunDirectory).TrimEnd('\');Assert-NoReparse $run
if (-not $run.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) {throw 'Native test directory must be inside update artifacts.'}
$archive=Join-Path $repo 'deploy/windows/.cache/postgresql.zip'
$original=Read-UpdateJson (Join-Path $repo 'deploy/artifacts/backend-windows-x64-20261010-185325/manifest.json')
$expected=@($original.files | Where-Object {$_.path -ceq 'payload/postgresql.zip'})
if ($expected.Count -ne 1 -or (Get-UpdateFileHash $archive) -cne $expected[0].sha256) {throw 'Cached PostgreSQL differs from conserved original reference.'}
$destination=Join-Path $run 'postgres-tools'
if (Test-Path -LiteralPath $destination) {throw 'Test tool directory must be new.'}
New-Item -ItemType Directory -Path $destination | Out-Null
$zip=[IO.Compression.ZipFile]::OpenRead($archive)
try {
    $seen=@{};$total=[long]0
    foreach ($entry in $zip.Entries) {
        $name=$entry.FullName.Replace('\','/')
        # Only server tools/runtime resources are needed, not pgAdmin or docs.
        if ($name -cnotmatch '^pgsql/(bin|lib|share)/') {continue}
        $relative=$name.TrimEnd('/')
        if ($relative -cnotmatch '^[a-zA-Z0-9_./+-]+$' -or @($relative.Split('/') | Where-Object {-not $_ -or $_ -in @('.','..') -or $_.EndsWith('.')}).Count) {throw 'Unsafe vendor tool path.'}
        if ($seen.ContainsKey($relative)) {throw 'Duplicate vendor ZIP path.'};$seen[$relative]=$true
        $mode=($entry.ExternalAttributes -shr 16) -band 0xf000
        if ($mode -notin @(0,0x8000,0x4000) -or ($entry.ExternalAttributes -band 0x400)) {throw 'Vendor ZIP contains special link.'}
        $target=[IO.Path]::GetFullPath((Join-Path $destination $relative))
        if (-not $target.StartsWith($destination+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Vendor ZIP escapes test directory.'}
        if ($name.EndsWith('/')) {New-Item -ItemType Directory -Path $target -Force | Out-Null;continue}
        $total+=$entry.Length;if ($total -gt 2147483648) {throw 'Oversized vendor ZIP.'}
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
    }
}finally{$zip.Dispose()}
$bin=Join-Path $destination 'pgsql/bin'
if (-not (Test-Path -LiteralPath (Join-Path $bin 'initdb.exe'))) {throw 'Native test PostgreSQL missing.'}
# initdb uses a restricted Windows token; grant this test owner explicitly.
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $run /grant (('*'+$sid)+':(OI)(CI)F') | Out-Null
if ($LASTEXITCODE -ne 0) {throw 'Cannot prepare private synthetic test directory.'}
Write-Output $bin
