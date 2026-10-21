[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CandidatePath,
    [string]$OutputDirectory
)
. (Join-Path $PSScriptRoot 'update/Package.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(-not $OutputDirectory){$OutputDirectory=Join-Path $repo 'tests/artifacts/vm-delivery'}
$output=[IO.Path]::GetFullPath($OutputDirectory);Assert-NoReparse $output
$info=& $CandidatePath --release-info
if($LASTEXITCODE -ne 0){throw 'Candidate metadata unavailable.'}
$info=ConvertFrom-UpdateJson ($info -join "`n")
if($info.releaseId -cnotlike 'rehearsal-*' -or $info.transactionalMigrations -ne $true){throw 'Explicit rehearsal candidate required.'}
$files=@('Actualizar.ps1','Build-UpdatePackage.ps1','Preparar-Ensayo-Local.ps1','Ejecutar-Ensayo-Local.ps1','update/Updater.ps1','update/Backup.ps1','update/Control.ps1','update/Package.ps1','update/NativeServices.cs','update/run-api.ps1','update/catalogs/legacy-20261010-185325.json','update/ENSAYO-LOCAL.md')
$runId='local-delivery-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$stage=Join-Path $repo ('tests/artifacts/updates/'+$runId)
New-Item -ItemType Directory -Path $stage|Out-Null
$inventory=@(foreach($relative in $files){
    $target=Join-Path $stage $relative
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force|Out-Null
    [IO.File]::Copy((Join-Path $PSScriptRoot $relative),$target,$false)
    [pscustomobject]@{path=$relative;sha256=(Get-UpdateFileHash $target)}
})
$binary='candidate/bin/propiedades-backend.exe'
New-Item -ItemType Directory -Path (Join-Path $stage 'candidate/bin')|Out-Null
[IO.File]::Copy([IO.Path]::GetFullPath($CandidatePath),(Join-Path $stage $binary),$false)
$inventory+=@([pscustomobject]@{path=$binary;sha256=(Get-UpdateFileHash (Join-Path $stage $binary))})
$delivery=[pscustomobject]@{format=1;purpose='isolated-vm-update-rehearsal';releaseId=$info.releaseId;productionAccepted=$false;files=$inventory}
[IO.File]::WriteAllText((Join-Path $stage 'delivery.json'),($delivery|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
New-Item -ItemType Directory -Path $output -Force|Out-Null
$archive=Join-Path $output ($runId+'.zip')
$zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($relative in @($inventory.path)+@('delivery.json')){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $stage $relative),$relative,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$zip.Dispose()}
$hash=Get-UpdateFileHash $archive
[IO.File]::WriteAllText($archive+'.sha256',$hash+'  '+[IO.Path]::GetFileName($archive))
[pscustomobject]@{status='LocalRehearsalDeliveryBuilt';archive=$archive;sha256=$hash;releaseId=$info.releaseId;productionAccepted=$false}|ConvertTo-Json
