param([ValidateSet(2,3)][int]$Revision=2)
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$output=Join-Path $workspace ('tests/artifacts/hyperv-copy-20261020/delivery/candidate-r'+$Revision+'.exe')
if(Test-Path -LiteralPath $output){throw 'Rehearsal candidate already exists; preserve its immutable identity.'}
$before=@{}
foreach($name in @('RUSTFLAGS','AELIUM_RELEASE_ID','AELIUM_BUILD_ID','AELIUM_API_CONTRACT')){$before[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try{
    $env:RUSTFLAGS='-C target-feature=+crt-static'
    $env:AELIUM_RELEASE_ID='rehearsal-vm-20261020-r'+$Revision
    $env:AELIUM_BUILD_ID='rehearsal-vm-20261020-build'+$Revision
    $env:AELIUM_API_CONTRACT='propiedades-v1'
    & cargo build --manifest-path (Join-Path $workspace 'backend/Cargo.toml') --release --target x86_64-pc-windows-msvc --locked --offline
    if($LASTEXITCODE -ne 0){throw 'Rehearsal build failed.'}
    [IO.File]::Copy((Join-Path $workspace 'backend/target/x86_64-pc-windows-msvc/release/propiedades-backend.exe'),$output,$false)
    $info=(& $output --release-info)|ConvertFrom-Json
    if($LASTEXITCODE -ne 0 -or $info.releaseId -cne $env:AELIUM_RELEASE_ID -or $info.buildId -cne $env:AELIUM_BUILD_ID -or -not $info.transactionalMigrations){throw 'Unexpected rehearsal build metadata.'}
    [pscustomobject]@{sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant();releaseInfo=$info;productionAccepted=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath ($output+'.json') -Encoding UTF8
}finally{foreach($name in $before.Keys){[Environment]::SetEnvironmentVariable($name,$before[$name],'Process')}}
