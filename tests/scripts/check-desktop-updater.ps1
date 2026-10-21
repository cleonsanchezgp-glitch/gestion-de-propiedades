param([string]$CandidatePath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $repo 'deploy/windows/update/Package.ps1')
if(-not $CandidatePath){$CandidatePath=Join-Path $repo 'deploy/artifacts/promalza-validation-20261021/candidate/backend/propiedades-backend.exe'}
$run=Join-Path $repo ('tests/artifacts/updates/desktop-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
New-Item -ItemType Directory -Path $run | Out-Null
$checks=New-Object Collections.Generic.List[object]
function Check([string]$Name,[scriptblock]$Action){& $Action;$checks.Add([pscustomobject]@{name=$Name;status='PASS'})}
function Build($Arguments){
    $result=& (Join-Path $repo 'deploy/windows/Build-DesktopUpdater.ps1') @Arguments
    return ($result -join "`n" | ConvertFrom-Json)
}
function Inspect($BuildResult,[string]$ExpectedMode,[string]$Name){
    $assembly=[Reflection.Assembly]::LoadFile($BuildResult.executable)
    $stream=$assembly.GetManifestResourceStream('payload.zip')
    $hashReader=New-Object IO.StreamReader($assembly.GetManifestResourceStream('payload.sha256'))
    try{$expected=$hashReader.ReadToEnd().Trim()}finally{$hashReader.Dispose()}
    $memory=New-Object IO.MemoryStream
    try{$stream.CopyTo($memory)}finally{$stream.Dispose()}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$actual=([BitConverter]::ToString($sha.ComputeHash($memory.ToArray()))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    if($actual -cne $expected){throw 'Embedded resource hash differs.'}
    $extract=Join-Path $run $Name;New-Item -ItemType Directory -Path $extract | Out-Null
    $memory.Position=0;$zip=New-Object IO.Compression.ZipArchive($memory,[IO.Compression.ZipArchiveMode]::Read)
    try{foreach($entry in $zip.Entries){
        if($entry.FullName -match '\\|:|\.\.'){throw 'Unsafe generated ZIP entry.'}
        $dest=Join-Path $extract $entry.FullName
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($dest)) -Force | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$dest,$false)
    }}finally{$zip.Dispose();$memory.Dispose()}
    $verified=& (Join-Path $extract 'Desktop.ps1') -ValidateOnly
    if($verified.mode -cne $ExpectedMode){throw 'Wrong desktop mode.'}
    $ui=& (Join-Path $extract 'Desktop.ps1') -UiSmokeTest
    if($ui.status -cne 'DesktopUiConstructed'){throw 'UI construction failed.'}
    return $extract
}
try {
    $preparation=Build @{CandidatePath=$CandidatePath;OutputDirectory=(Join-Path $run 'preparation-build')}
    Check 'Preparation EXE contains verifiable resources and constructs inventory UI' {
        $script:extract=Inspect $preparation 'Preparation' 'preparation-extracted'
    }
    Check 'Changed embedded script fails before displaying UI or modifying installation' {
        [IO.File]::AppendAllText((Join-Path $script:extract 'update/Updater.ps1'),'# altered')
        $rejected=$false;try{& (Join-Path $script:extract 'Desktop.ps1') -ValidateOnly | Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw 'Tampered maintenance code accepted.'}
    }
    $delivery=Join-Path $run 'delivery';$content=Join-Path $run 'content'
    New-Item -ItemType Directory -Path $delivery,(Join-Path $content 'bin') | Out-Null
    Copy-Item -LiteralPath $CandidatePath -Destination (Join-Path $content 'bin/propiedades-backend.exe')
    $info=(& $CandidatePath --release-info | ConvertFrom-Json)
    $dependencies=@(foreach($id in @('postgresql','keycloak','java','winsw','cloudflared','vc-runtime')){
        [pscustomobject]@{id=$id;version='fixture-1';files=@([pscustomobject]@{path=('dependencies/'+$id+'.fixture');sha256=('a'*64)})}
    })
    $definition=[pscustomobject]@{
        format=2;kind='application-update';product='aelium-propiedades';platform='windows-x64'
        releaseId=$info.releaseId;buildId=$info.buildId;apiContract=$info.apiContract
        acceptedSources=@([pscustomobject]@{sourceId='fixture-original';evidence='fixture-review'})
        files=@([pscustomobject]@{path='bin/propiedades-backend.exe';target='release'})
        dependencies=$dependencies;schemaBefore=$info.migrations;schemaAfter=$info.migrations;migrations=@()
        supportedFrontends=@([pscustomobject]@{id='fixture-web';apiContract=$info.apiContract;evidence='fixture-contract'})
        recovery=[pscustomobject]@{sourceIds=@('fixture-original');schema=$info.migrations;checks=@('version','identity','read','write','frontend','cleanup');preserve=@('application','schema','data','identity','config','attachments','services')}
    }
    $definition | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $run 'definition.json') -Encoding UTF8
    $null=& (Join-Path $repo 'deploy/windows/Build-UpdatePackage.ps1') -ContentRoot $content -DefinitionPath (Join-Path $run 'definition.json') -OutputArchive (Join-Path $delivery 'application.zip')
    $hash=Get-UpdateFileHash (Join-Path $delivery 'application.zip')
    $catalog=[pscustomobject]@{format=1;sources=@([pscustomobject]@{sourceId='fixture-original';reviewed=$true;reviewer='fixture-reviewer';evidence='fixture-review'})}
    $catalog | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $delivery 'catalog.json') -Encoding UTF8
    [pscustomobject]@{format=1;completeInventory=$true;installationRoot=(Join-Path $run 'nonexistent-installation')} | ConvertTo-Json | Set-Content (Join-Path $delivery 'observation.json') -Encoding UTF8
    [pscustomobject]@{format=1;complete=$true;evidence='fixture-storage';attachments=@()} | ConvertTo-Json | Set-Content (Join-Path $delivery 'inventory.json') -Encoding UTF8
    Check 'Reviewed delivery refuses a missing external archive reference' {
        $rejected=$false;try{$null=Build @{DeliveryRoot=$delivery;OutputDirectory=(Join-Path $run 'missing-reference')}}catch{$rejected=$true}
        if(-not $rejected){throw 'Missing external reference accepted.'}
    }
    Check 'Reviewed delivery refuses a mismatched archive reference' {
        $rejected=$false;try{$null=Build @{DeliveryRoot=$delivery;ExpectedArchiveSha256=('f'*64);OutputDirectory=(Join-Path $run 'bad-reference')}}catch{$rejected=$true}
        if(-not $rejected){throw 'Wrong external reference accepted.'}
    }
    Check 'Unreviewed source cannot enable the update edition' {
        $catalog.sources[0].reviewed=$false;$catalog | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $delivery 'catalog.json') -Encoding UTF8
        $rejected=$false;try{$null=Build @{DeliveryRoot=$delivery;ExpectedArchiveSha256=$hash;OutputDirectory=(Join-Path $run 'unreviewed')}}catch{$rejected=$true}
        if(-not $rejected){throw 'Unreviewed source accepted.'}
        $catalog.sources[0].reviewed=$true;$catalog | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $delivery 'catalog.json') -Encoding UTF8
    }
    Check 'Reviewed test bundle embeds application and metadata and constructs update UI' {
        $reviewed=Build @{DeliveryRoot=$delivery;ExpectedArchiveSha256=$hash;OutputDirectory=(Join-Path $run 'reviewed-build')}
        $path=Inspect $reviewed 'ReviewedDelivery' 'reviewed-extracted'
        if((Get-UpdateFileHash (Join-Path $path 'delivery/application.zip')) -cne $hash){throw 'Application changed in EXE.'}
        if($reviewed.clientAccepted){throw 'Builder falsely declares client acceptance.'}
    }
    $result='PASS'
}catch{$result='FAIL';throw}finally{
    [pscustomobject]@{status=$result;scope='Desktop compilation, embedded resources, UI construction and packaging guards; synthetic reviewed metadata, no services changed or client acceptance';checks=@($checks.ToArray())} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $run 'report.json') -Encoding UTF8
    Write-Host ($checks.Count.ToString()+' desktop checks passed; evidence: '+$run+'/report.json')
}
