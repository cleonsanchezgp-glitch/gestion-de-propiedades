. (Join-Path $PSScriptRoot '../../deploy/windows/update/Control.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$runId='control-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$run=Join-Path $repo ('tests/artifacts/updates/'+$runId)
$root=Join-Path $run 'installation'
New-Item -ItemType Directory -Path (Join-Path $root 'config') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'config/settings.json'),'{"Format":1,"Complete":true}')
$results=New-Object Collections.Generic.List[object]
function Check([string]$Name,[scriptblock]$Action,[bool]$Reject=$false) {
    $failed=$false;try{$null=& $Action}catch{$failed=$true;if(-not $Reject){throw}}
    if($Reject -ne $failed){throw ('Unexpected outcome: '+$Name)}
    $results.Add([pscustomobject]@{variant=$Name;status='PASS'})
}
$control=Open-UpdateControl $root
try {
    $op=[pscustomobject]@{format=1;operationId='control-operation';phase='Preflight';sourceReleaseId='fixture-before';targetReleaseId='fixture-after';backupReference=$null;checksPassed=$false;step='test';services=@()}
    Check 'exclusive maintenance lock prevents second operator' {$other=Open-UpdateControl $root;try{}finally{$other.lock.Dispose()}} $true
    Check 'initial record starts at preflight' {Set-UpdateOperation $control $op}
    Check 'phase cannot jump directly to committed' {$bad=$op|ConvertTo-Json -Depth 10|ConvertFrom-Json;$bad.phase='Committed';$bad.checksPassed=$true;Set-UpdateOperation $control $bad} $true
    Check 'second incomplete operation is rejected' {$bad=$op|ConvertTo-Json -Depth 10|ConvertFrom-Json;$bad.operationId='other';Set-UpdateOperation $control $bad} $true
    Check 'target identity cannot change within operation' {$bad=$op|ConvertTo-Json -Depth 10|ConvertFrom-Json;$bad.targetReleaseId='other';Set-UpdateOperation $control $bad} $true
    Check 'native services cannot address unrelated service' {[Aelium.Update.NativeServices]::Read('UnrelatedService')} $true
    Check 'recovery snapshot roundtrips restart options' {$options=New-Object Aelium.Update.ServiceOptions;$options.StartType=2;$options.DelayedAutoStart=$true;$options.ResetPeriod=86400;$options.NonCrashFailures=$true;$a=New-Object Aelium.Update.ActionInfo;$a.Type=1;$a.Delay=10000;$options.Actions=@($a);$json=$options|ConvertTo-Json -Depth 10|ConvertFrom-Json;if($json.StartType -ne 2 -or -not $json.DelayedAutoStart -or $json.Actions[0].Delay -ne 10000){throw 'Snapshot changed'}}
    foreach($phase in @('Quiescing','BackingUp','Applying','Verifying','Committing')){$op.phase=$phase;Set-UpdateOperation $control $op}
    Check 'unverified terminal record is rejected' {$op.phase='Committed';Set-UpdateOperation $control $op} $true
    $op.phase='Committing';$op.checksPassed=$true;Set-UpdateOperation $control $op
    $gate=[IO.File]::Open($control.gatePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
    try{$gate.Lock(0,1);Check 'phase publication fails while native write gate is held' {Set-UpdateOperation $control $op} $true}finally{$gate.Dispose()}
    $op.phase='Committed';Set-UpdateOperation $control $op
    $new=$op|ConvertTo-Json -Depth 10|ConvertFrom-Json;$new.operationId='next-operation';$new.phase='Preflight';$new.checksPassed=$false
    Check 'verified terminal state allows a new preflight operation' {Set-UpdateOperation $control $new}
    Check 'control cannot publish outside maintenance directory' {Write-ControlJson $control (Join-Path $run 'escaped.json') $new} $true
    $null=Assert-Operation (Read-UpdateJson $control.operationPath)
}finally{$control.lock.Dispose()}

# Test stable launcher against synthetic files: no executable or service is started.
$releaseRoot=Join-Path $root 'releases/fixture-after';New-Item -ItemType Directory -Path (Join-Path $releaseRoot 'bin') -Force | Out-Null
$exe=Join-Path $releaseRoot 'bin/propiedades-backend.exe';[IO.File]::WriteAllText($exe,'synthetic, never executable')
$manifest=[pscustomobject]@{format=2;kind='application-update';product='aelium-propiedades';platform='windows-x64';releaseId='fixture-after';files=@([pscustomobject]@{path='bin/propiedades-backend.exe';target='release';size=(Get-Item -LiteralPath $exe).Length;sha256=(Get-UpdateFileHash $exe)})}
$manifestPath=Join-Path $releaseRoot 'manifest.json';[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 10))
$selector=[pscustomobject]@{format=1;releaseId='fixture-after';path='releases/fixture-after';manifestSha256=(Get-UpdateFileHash $manifestPath)}
$selectorPath=Join-Path $root 'config/active-release.json';[IO.File]::WriteAllText($selectorPath,($selector|ConvertTo-Json))
$op.operationId='next-operation';$op.phase='Verifying';$op.checksPassed=$false
[IO.File]::WriteAllText((Join-Path $root 'maintenance/operation.json'),($op|ConvertTo-Json -Depth 10))
$launcher=Join-Path $repo 'deploy/windows/update/run-api.ps1'
Check 'stable launcher uses explicit installation root under releases' {& $launcher -InstallRoot $root -CheckOnly}
Check 'Windows PowerShell File startup resolves root without an InstallRoot argument' {
    $scripts=Join-Path $root 'scripts';New-Item -ItemType Directory -Path $scripts -Force|Out-Null
    $serviceLauncher=Join-Path $scripts 'run-api.ps1';[IO.File]::Copy($launcher,$serviceLauncher,$false)
    # Use the actual SCM command form, not an in-process invocation with an
    # explicit root that hides parameter-binding bugs in Windows PowerShell.
    $reply=& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $serviceLauncher -CheckOnly 2>&1
    if($LASTEXITCODE -ne 0 -or ($reply|Out-String) -notmatch 'StartupMetadataVerified'){throw 'Default-root service command failed.'}
}
Check 'an explicitly empty installation root remains rejected' {& $launcher -InstallRoot '' -CheckOnly} $true
Check 'stable launcher blocks incomplete applying phase' {$op.phase='Applying';[IO.File]::WriteAllText((Join-Path $root 'maintenance/operation.json'),($op|ConvertTo-Json -Depth 10));& $launcher -InstallRoot $root -CheckOnly} $true
$op.phase='Verifying';[IO.File]::WriteAllText((Join-Path $root 'maintenance/operation.json'),($op|ConvertTo-Json -Depth 10))
Check 'stable selector cannot escape releases directory' {$selector.path='../outside';[IO.File]::WriteAllText($selectorPath,($selector|ConvertTo-Json));& $launcher -InstallRoot $root -CheckOnly} $true
$selector.path='releases/fixture-after';[IO.File]::WriteAllText($selectorPath,($selector|ConvertTo-Json))
[IO.File]::WriteAllText($exe,'modified')
Check 'stable launcher rejects changed executable before launch' {& $launcher -InstallRoot $root -CheckOnly} $true
$report=@{runId=$runId;createdUtc=[DateTime]::UtcNow.ToString('o');scope='Native Windows control, locks, journal and launcher metadata';results=@($results.ToArray());os=[Environment]::OSVersion.VersionString;servicesModified=$false;limitations=@('No actual SCM service changes or system reboot','Launcher CheckOnly does not execute API or inspect database');familyStatus='Not Run - partial tooling evidence'}
[IO.File]::WriteAllText((Join-Path $run 'report.json'),($report|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
Write-Host ($results.Count.ToString()+' control checks PASS; evidence: tests/artifacts/updates/'+$runId+'/report.json')
