param([string]$RunDirectory,[string]$PgBin,[int]$PgPort,[ValidateSet('Capture','Compare','ProductionCompare')][string]$Action)
. (Join-Path $PSScriptRoot '../../deploy/windows/update/Updater.ps1')
$ErrorActionPreference='Stop'
$control=[pscustomobject]@{root=$RunDirectory;verificationMode='LocalRehearsal';operationPath=(Join-Path $RunDirectory 'operation.json')}
$pg=[pscustomobject]@{bin=$PgBin;port=$PgPort;user='postgres';password=''}
$manifestPath=Join-Path $RunDirectory 'fixture-backup.private.json'
function Get-UpdatePg($Control){return $pg}
function Get-UpdateRoleFingerprint($Pg){return 'fixture-roles'}
function Get-UpdateMembershipFingerprint($Pg){return 'fixture-members'}
function Read-CoherentUpdateBackup($Control){return [pscustomobject]@{manifest=(Read-UpdateJson $manifestPath)}}
function Write-ControlJson($Control,[string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 20))}
# SQL projection/conservation are real. Vendor-profile admission and control
# persistence are fixture hooks; this test is not evidence for SCM or Keycloak.
function Test-LocalIdentityRuntimeProfile($Control){return $Action -cne 'ProductionCompare'}
if($Action -ceq 'Capture'){
    $databases=@()
    foreach($name in @('propiedades','keycloak')){$databases += [pscustomobject]@{metadata=[pscustomobject]@{name=$name};fingerprint=(Get-UpdateDataFingerprint $pg $name -LogicalColumns)}}
    Write-ControlJson $control $manifestPath ([pscustomobject]@{format=2;operationId='policy-fixture-operation';verified=$true;rolesFingerprint='fixture-roles';membershipsFingerprint='fixture-members';databases=$databases;files=@()})
    Write-ControlJson $control $control.operationPath ([pscustomobject]@{operationId='policy-fixture-operation'})
    New-LocalIdentityRuntimeBaseline $control
}else{Test-ApplicationUpdateConservation $control}
Write-Output 'PASS'
