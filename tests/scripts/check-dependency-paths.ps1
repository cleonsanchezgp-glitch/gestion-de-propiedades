. (Join-Path $PSScriptRoot '../../deploy/windows/update/Package.ps1')
$ErrorActionPreference='Stop'
$checks=0
function Check([scriptblock]$Action,[bool]$Reject=$false){
    $failed=$false;try{& $Action|Out-Null}catch{$failed=$true;if(-not $Reject){throw}}
    if($failed -ne $Reject){throw 'Unexpected dependency path validation result.'}
    $script:checks++
}
# Exercise the actual vendor tree which triggered the failure in the VM.
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $repo 'deploy/windows/.cache/postgresql.zip'))
try {
    $vendorPaths=@($zip.Entries|ForEach-Object{$_.FullName.Replace('\','/')}|Where-Object{$_ -cmatch '^pgsql/(bin|lib|share)/' -and -not $_.EndsWith('/')}|ForEach-Object{$_ -creplace '^pgsql/','postgresql/'})
    if(-not ($vendorPaths -ccontains 'postgresql/share/timezone/Etc/GMT+1')){throw 'Regression fixture missing.'}
    foreach($vendorPath in $vendorPaths){Check {Assert-DependencyPath 'postgresql' $vendorPath}}
}finally{$zip.Dispose()}
foreach($bad in @('../postgresql/share/timezone/GMT+1','postgresql/share/timezone/../GMT+1','postgresql/share/timezone/Etc/GMT+1/../x','postgresql/share/timezone/Etc/GMT+1:stream','postgresql/share/timezone/GMT+1.exe','C:/postgresql/share/timezone/GMT+1','postgresql/share/timezone/Etc/GMT+1.')) {
    Check {Assert-DependencyPath 'postgresql' $bad} $true
}
Check {Assert-DependencyPath 'java' 'postgresql/share/timezone/Etc/GMT+1'} $true
Check {Assert-UpdatePath 'postgresql/share/timezone/Etc/GMT+1'} $true
$root=Join-Path $repo ('tests/artifacts/updates/dependency-path-'+[Guid]::NewGuid().ToString('N'))
$folder=Join-Path $root 'postgresql/share/timezone/Etc'
New-Item -ItemType Directory -Path $folder -Force|Out-Null
$file=Join-Path $folder 'GMT+1';[IO.File]::WriteAllBytes($file,[byte[]]@(1,2,3))
$dependency=[pscustomobject]@{id='postgresql';files=@([pscustomobject]@{path='postgresql/share/timezone/Etc/GMT+1';sha256=(Get-UpdateFileHash $file)})}
Check {
    $items=@($dependency|Select-Object id,@{n='version';e={'test'}},files)
    foreach($id in @('keycloak','java','winsw','cloudflared','vc-runtime')){
        $items+=@([pscustomobject]@{id=$id;version='test';files=@([pscustomobject]@{path=('dependencies/'+$id+'.fixture');sha256=('0'*64)})})
    }
    Assert-Dependencies $items
}
Check {Assert-InstalledDependency $root $dependency}
[IO.File]::WriteAllBytes($file,[byte[]]@(3,2,1))
Check {Assert-InstalledDependency $root $dependency} $true
Write-Output ($checks.ToString()+' dependency path checks PASS; real vendor paths, escape rejection and file integrity')
