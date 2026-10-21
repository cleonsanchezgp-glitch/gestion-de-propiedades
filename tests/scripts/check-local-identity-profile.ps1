. (Join-Path $PSScriptRoot '../../deploy/windows/update/Updater.ps1')
$root=Join-Path $PSScriptRoot ('../artifacts/updates/identity-profile-'+[Guid]::NewGuid().ToString('N'))
$control=[pscustomobject]@{root=$root;verificationMode='Production'}
if(Test-LocalIdentityRuntimeProfile $control){throw 'Production admitted an experimental runtime profile.'}
$control.verificationMode='LocalRehearsal'
if(Test-LocalIdentityRuntimeProfile $control){throw 'Absent pinned runtime admitted.'}
$directory=Join-Path $root 'keycloak/lib/lib/main'
$null=New-Item -ItemType Directory -Path $directory -Force
foreach($name in @('org.keycloak.keycloak-model-jpa-26.7.4.jar','org.keycloak.keycloak-model-infinispan-26.7.4.jar')){[IO.File]::WriteAllText((Join-Path $directory $name),'synthetic untrusted runtime')}
$rejected=$false
try{$null=Test-LocalIdentityRuntimeProfile $control}catch{$rejected=$_.Exception.Message -ceq 'Unreviewed local identity runtime.'}
if(-not $rejected){throw 'Altered runtime hash was not rejected.'}
Write-Output '3 identity-profile admission checks PASS (production, absent vendor, altered vendor)'
