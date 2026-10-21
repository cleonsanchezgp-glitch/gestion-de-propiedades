param([Parameter(Mandatory=$true)][string[]]$RunNames)
$base=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts/updates')).TrimEnd('\')
foreach ($name in $RunNames) {
    if ($name -cnotmatch '^runtime-[a-zA-Z0-9._-]+$') {throw 'Invalid trial name.'}
    $directory=[IO.Path]::GetFullPath((Join-Path $base $name))
    if (-not $directory.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Trial path escapes update artifacts.'}
    $report=Get-Content -LiteralPath (Join-Path $directory 'report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($report.runId -cne $name -or $report.status -cne 'FAIL') {throw 'Only recorded failed trials may be stopped with this helper.'}
    $cluster=Join-Path $directory 'cluster'
    if (Test-Path -LiteralPath (Join-Path $cluster 'postmaster.pid')) {
        & (Join-Path $directory 'postgres-tools/pgsql/bin/pg_ctl.exe') -D $cluster -m fast -w stop
        if ($LASTEXITCODE -ne 0) {throw 'Owned trial PostgreSQL did not stop.'}
    }
}
