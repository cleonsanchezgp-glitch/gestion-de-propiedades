. (Join-Path $PSScriptRoot '../../deploy/windows/update/Updater.ps1')
$script:changedDatabase='';$script:captured=$null
function Read-CoherentUpdateBackup($Control){
    [pscustomobject]@{manifest=[pscustomobject]@{format=2;rolesFingerprint='roles';membershipsFingerprint='members';files=@();databases=@(
        [pscustomobject]@{metadata=[pscustomobject]@{name='propiedades'};fingerprint=[pscustomobject]@{largeObjects='large';tables=@([pscustomobject]@{schema='public';table='entities';digest='1:private-business-digest'},[pscustomobject]@{schema='public';table='_sqlx_migrations';digest='2:old-schema-digest'})}},
        [pscustomobject]@{metadata=[pscustomobject]@{name='keycloak'};fingerprint=[pscustomobject]@{largeObjects='large';tables=@([pscustomobject]@{schema='public';table='identity_fixture';digest='1:private-identity-digest'})}}
    )}}
}
function Get-UpdatePg($Control){[pscustomobject]@{}}
function Get-UpdateRoleFingerprint($Pg){'roles'}
function Get-UpdateMembershipFingerprint($Pg){'members'}
function Get-UpdateDataFingerprint($Pg,$Database,[switch]$LogicalColumns){
    if($Database -ceq 'propiedades'){$tables=@([pscustomobject]@{schema='public';table='entities';digest='1:private-business-digest'},[pscustomobject]@{schema='public';table='_sqlx_migrations';digest='3:expected-schema-change'})}
    else{$tables=@([pscustomobject]@{schema='public';table='identity_fixture';digest='1:private-identity-digest'})}
    if($script:changedDatabase -ceq $Database){$tables[0].digest='1:private-changed-digest'}
    [pscustomobject]@{tables=$tables;largeObjects='large'}
}
function Read-UpdateJson($Path){[pscustomobject]@{operationId='synthetic-operation'}}
function Write-ControlJson($Control,$Path,$Value){$script:captured=$Value}
$control=[pscustomobject]@{root='C:\synthetic-fixture';operationPath='synthetic-record'}
Test-ApplicationUpdateConservation $control
if($script:captured){throw 'Unchanged business/identity data generated a failure.'}
foreach($database in @('propiedades','keycloak')){
    $script:changedDatabase=$database;$script:captured=$null;$failed=$false
    try{Test-ApplicationUpdateConservation $control}catch{$failed=$_.Exception.Message -ceq 'Existing business/identity data changed; cannot commit automatically.'}
    if(-not $failed -or $script:captured.tables.Count -ne 1 -or $script:captured.tables[0].database -cne $database){throw 'Changed data was not rejected and attributed correctly.'}
    if(($script:captured|ConvertTo-Json -Depth 8) -match 'private-|digest'){throw 'Sensitive data fingerprint leaked into diagnosis.'}
}
Write-Output '3 conservation scenarios PASS (unchanged/migration metadata, business drift, identity drift; no acceptance relaxation)'
