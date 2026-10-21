[CmdletBinding()]
param(
    [string]$DeliveryRoot,
    [string]$ExpectedArchiveSha256,
    [string]$CandidatePath,
    [string]$OutputDirectory
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'update/Updater.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(-not $OutputDirectory){$OutputDirectory=Join-Path $repo 'deploy/artifacts/desktop-updater'}
$output=[IO.Path]::GetFullPath($OutputDirectory);Assert-NoReparse $output
New-Item -ItemType Directory -Path $output -Force | Out-Null
$build=Join-Path $output ('build-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
$stage=Join-Path $build 'payload';New-Item -ItemType Directory -Path $stage | Out-Null
$files=@('desktop/Desktop.ps1','Inventariar-Instalacion-Cliente.ps1','update/Updater.ps1','update/Backup.ps1','update/Control.ps1','update/Package.ps1','update/NativeServices.cs','update/run-api.ps1')
foreach($file in $files){
    $relative=if($file -ceq 'desktop/Desktop.ps1'){'Desktop.ps1'}else{$file}
    $target=Join-Path $stage $relative
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
    [IO.File]::Copy((Join-Path $PSScriptRoot $file),$target,$false)
}
$meta=[ordered]@{format=1;mode='Preparation';installationRoot='C:\ProgramData\Aelium\Propiedades';archiveSha256=$null;candidate=$null;files=@()}
if($CandidatePath){
    $candidate=[IO.Path]::GetFullPath($CandidatePath);Assert-NoReparse $candidate
    $info=& $candidate --release-info
    if($LASTEXITCODE -ne 0){throw 'Candidate metadata unavailable.'}
    $meta.candidate=ConvertFrom-UpdateJson ($info -join "`n")
    if($meta.candidate.product -cne 'aelium-propiedades'){throw 'Unexpected candidate product.'}
    New-Item -ItemType Directory -Path (Join-Path $stage 'candidate') | Out-Null
    [IO.File]::Copy($candidate,(Join-Path $stage 'candidate/propiedades-backend.exe'),$false)
}
if($DeliveryRoot){
    if(-not $ExpectedArchiveSha256){throw 'An independently obtained application SHA256 is required.'}
    Assert-UpdateHash $ExpectedArchiveSha256
    $delivery=[IO.Path]::GetFullPath($DeliveryRoot);Assert-NoReparse $delivery
    $verified=Test-UpdateArchive (Join-Path $delivery 'application.zip') $ExpectedArchiveSha256
    $catalog=Read-UpdateJson (Join-Path $delivery 'catalog.json')
    $observation=Read-UpdateJson (Join-Path $delivery 'observation.json')
    $inventory=Read-UpdateJson (Join-Path $delivery 'inventory.json')
    Assert-UpdateInventory $inventory
    if($catalog.format -ne 1 -or $observation.format -ne 1 -or -not $observation.completeInventory){throw 'Reviewed source and observation required.'}
    foreach($accepted in $verified.manifest.acceptedSources){
        $matches=@($catalog.sources | Where-Object {$_.sourceId -ceq $accepted.sourceId -and $_.reviewed -eq $true -and $_.reviewer -and $_.evidence -ceq $accepted.evidence})
        if($matches.Count -ne 1){throw 'Every accepted source requires exactly one reviewed catalog entry.'}
    }
    if(-not [IO.Path]::IsPathRooted($observation.installationRoot)){throw 'Observed installation root must be absolute.'}
    if($meta.candidate -and ($meta.candidate.releaseId -cne $verified.manifest.releaseId -or $meta.candidate.buildId -cne $verified.manifest.buildId)){throw 'Optional candidate differs from application delivery.'}
    $meta.mode='ReviewedDelivery';$meta.installationRoot=$observation.installationRoot;$meta.archiveSha256=$ExpectedArchiveSha256
    New-Item -ItemType Directory -Path (Join-Path $stage 'delivery') | Out-Null
    foreach($file in @('application.zip','catalog.json','observation.json','inventory.json')){
        Assert-NoReparse (Join-Path $delivery $file)
        [IO.File]::Copy((Join-Path $delivery $file),(Join-Path $stage ('delivery/'+$file)),$false)
    }
    # Validate the copied archive too; never rely on the source staying unchanged during packaging.
    $null=Test-UpdateArchive (Join-Path $stage 'delivery/application.zip') $ExpectedArchiveSha256
}
$utf8=New-Object Text.UTF8Encoding($false)
$meta.files=@(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    [pscustomobject]@{path=$_.FullName.Substring($stage.Length+1).Replace('\','/');sha256=(Get-UpdateFileHash $_.FullName)}
})
[IO.File]::WriteAllText((Join-Path $stage 'bundle.json'),($meta | ConvertTo-Json -Depth 15),$utf8)
$null=& (Join-Path $stage 'Desktop.ps1') -ValidateOnly
$payload=Join-Path $build 'payload.zip'
# Forward slashes are required by the embedded extractor on Windows PowerShell 5.1.
$zip=[IO.Compression.ZipFile]::Open($payload,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($file in Get-ChildItem -LiteralPath $stage -Recurse -File){
    $relative=$file.FullName.Substring($stage.Length+1).Replace('\','/')
    $null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,$relative,[IO.Compression.CompressionLevel]::Optimal)
}}finally{$zip.Dispose()}
$hashFile=Join-Path $build 'payload.sha256';[IO.File]::WriteAllText($hashFile,(Get-UpdateFileHash $payload),$utf8)
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if(-not(Test-Path -LiteralPath $compiler)){throw 'Windows .NET Framework 4 compiler required.'}
$modeName=if($meta.mode -ceq 'ReviewedDelivery'){'Actualizar-Promalza'}else{'Preparar-Actualizacion-Promalza'}
$exe=Join-Path $build ($modeName+'.exe')
& $compiler /nologo /target:winexe /platform:x64 /optimize+ "/out:$exe" "/win32manifest:$(Join-Path $PSScriptRoot 'desktop/app.manifest')" /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll "/resource:$payload,payload.zip" "/resource:$hashFile,payload.sha256" (Join-Path $PSScriptRoot 'desktop/Launcher.cs')
if($LASTEXITCODE -ne 0){throw 'Desktop updater compilation failed.'}
$hash=Get-UpdateFileHash $exe
[IO.File]::WriteAllText(($exe+'.sha256'),($hash+'  '+[IO.Path]::GetFileName($exe)),$utf8)
$result=[pscustomobject]@{status='DesktopUpdaterBuilt';mode=$meta.mode;executable=$exe;sha256=$hash;clientAccepted=$false;requiresClientRehearsal=$true}
[IO.File]::WriteAllText((Join-Path $build 'build-result.json'),($result|ConvertTo-Json),$utf8)
$result | ConvertTo-Json
