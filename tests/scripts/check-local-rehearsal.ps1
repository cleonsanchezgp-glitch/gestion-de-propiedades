. (Join-Path $PSScriptRoot '../../deploy/windows/update/Updater.ps1')
$ErrorActionPreference='Stop'
$run=Join-Path $PSScriptRoot ('../artifacts/updates/local-mode-'+[Guid]::NewGuid().ToString('N'))
$root=[IO.Path]::GetFullPath((Join-Path $run 'installation'))
New-Item -ItemType Directory -Path (Join-Path $root 'config') -Force|Out-Null
$results=New-Object Collections.Generic.List[object]
function Check([string]$Name,[scriptblock]$Action,[bool]$Reject=$false) {
    $failed=$false;try{$null=& $Action}catch{$failed=$true;if(-not $Reject){throw}}
    if($failed -ne $Reject){throw ('Unexpected result: '+$Name)}
    $results.Add([pscustomobject]@{variant=$Name;status='PASS'})
}
function Save($Name,$Value){[IO.File]::WriteAllText((Join-Path $root ('config/'+$Name)),($Value|ConvertTo-Json -Depth 10))}
$settings=[pscustomobject]@{Format=1;Complete=$true;Username='prueba';OwnerSubject='test-subject';PortalOrigin='https://portal.example.test'}
Save 'settings.json' $settings
$marker=[pscustomobject]@{format=1;purpose='isolated-vm-update-rehearsal';installationRoot=$root;ownerSubject='test-subject'}
Check 'local mode without marker rejected' {Assert-LocalRehearsal $root} $true
Save 'local-rehearsal.json' $marker
Check 'explicitly marked reserved-origin installation admitted' {Assert-LocalRehearsal $root}
$marker.ownerSubject='other';Save 'local-rehearsal.json' $marker
Check 'different owner binding rejected' {Assert-LocalRehearsal $root} $true
$marker.ownerSubject='test-subject';$marker.installationRoot=$root+'-other';Save 'local-rehearsal.json' $marker
Check 'different installation binding rejected' {Assert-LocalRehearsal $root} $true
$marker.installationRoot=$root;$marker.purpose='production';Save 'local-rehearsal.json' $marker
Check 'wrong marker purpose rejected' {Assert-LocalRehearsal $root} $true
$marker.purpose='isolated-vm-update-rehearsal';Save 'local-rehearsal.json' $marker
$settings.PortalOrigin='https://production.example.com';Save 'settings.json' $settings
Check 'production origin never admitted as local rehearsal' {Assert-LocalRehearsal $root} $true
$settings.PortalOrigin='https://portal.example.test';$settings.Username='customer';Save 'settings.json' $settings
Check 'customer username rejected' {Assert-LocalRehearsal $root} $true
$settings.Username='prueba';Save 'settings.json' $settings
Save 'tunnel-token.txt' 'synthetic-token'
Check 'configured tunnel rejected' {Assert-LocalRehearsal $root} $true
Check 'old contexts default to production' {if((Get-UpdateVerificationMode ([pscustomobject]@{})) -cne 'Production'){throw 'Wrong default'}}
Check 'unknown mode rejected' {Get-UpdateVerificationMode ([pscustomobject]@{verificationMode='skip'})} $true
$runtime=Join-Path ([Environment]::SystemDirectory) 'vcruntime140.dll'
if (Test-Path -LiteralPath $runtime) {
    $dependency=[pscustomobject]@{id='vc-runtime';files=@([pscustomobject]@{path='system-runtime/vcruntime140.dll';sha256=(Get-UpdateFileHash $runtime)})}
    Check 'runtime evidence checks actual system DLL without copying it' {Assert-InstalledDependency $root $dependency}
    $dependency.files[0].sha256='0'*64
    Check 'modified runtime evidence rejected' {Assert-InstalledDependency $root $dependency} $true
}
foreach($pair in @(@('UpdateSucceeded','LocalRehearsalSucceeded'),@('AlreadyApplied','LocalRehearsalAlreadyApplied'),@('PreflightVerified','LocalRehearsalPreflightVerified'),@('VerificationPending','VerificationPending'))) {
    $inputStatus=$pair[0];$expected=$pair[1]
    Check ('local result '+$inputStatus+' never declares production success') {
        $result=Get-UpdateResult $inputStatus ([pscustomobject]@{status=$inputStatus;updateSucceeded=$true}) 'LocalRehearsal'
        if($result.status -cne $expected -or $result.updateSucceeded -or $result.portalChecked -or $result.productionAccepted){throw 'Unsafe result'}
    }
}
Check 'production success retains existing meaning' {$r=Get-UpdateResult 'UpdateSucceeded' ([pscustomobject]@{updateSucceeded=$true}) 'Production';if($r.status -cne 'UpdateSucceeded' -or -not $r.updateSucceeded){throw 'Production result changed'}}
[IO.File]::WriteAllText((Join-Path $run 'report.json'),([pscustomobject]@{scope='Local rehearsal guard and result semantics; no services or guest acceptance';results=$results.ToArray();observedUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8))
Write-Output ($results.Count.ToString()+' local rehearsal guard checks PASS')
