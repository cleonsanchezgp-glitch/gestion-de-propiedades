[CmdletBinding()]
param([string]$InstallationRoot='C:\ProgramData\Aelium\Propiedades')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'update/Updater.ps1')
Assert-ControlAdministrator
$root=[IO.Path]::GetFullPath($InstallationRoot).TrimEnd('\')
Assert-LocalRehearsal $root
$computer=Get-CimInstance Win32_ComputerSystem
$virtualBox=$computer.Model -match 'VirtualBox'
$hyperV=$computer.Manufacturer -ceq 'Microsoft Corporation' -and $computer.Model -ceq 'Virtual Machine'
if(-not($virtualBox -or $hyperV)){throw 'Solo para la VM aislada de ensayo (VirtualBox o Hyper-V).'}
$settings=Read-UpdateJson (Join-Path $root 'config/settings.json')
$secure=Read-Host ('Contrasena de pruebas de '+$settings.Username+' (no se guarda)') -AsSecureString
$credential=New-Object Management.Automation.PSCredential($settings.Username,$secure)
$control=$null
try {
    $token=Get-UpdateOwnerToken ([pscustomobject]@{root=$root}) $credential;$token=$null
    $control=Open-UpdateControl $root
    $control|Add-Member -NotePropertyName verificationMode -NotePropertyValue 'LocalRehearsal'
    $previous=Read-UpdateJson $control.operationPath
    $context=Read-UpdateJson (Join-Path $root 'maintenance/context.json')
    if($previous.phase -cne 'Recovered' -or $previous.operationId -cne $context.operationId -or $context.applicationChangeStarted -isnot [bool] -or $context.applicationChangeStarted -or (Get-UpdateVerificationMode $context) -cne 'LocalRehearsal' -or $previous.sourceReleaseId -cne $context.sourceId){throw 'Se requiere el ensayo anterior recuperado, sin cambios de aplicacion.'}
    $source=@($context.catalog.sources|Where-Object{$_.sourceId -ceq $context.sourceId})
    if($source.Count -ne 1){throw 'Origen ambiguo.'}
    Assert-InstalledFiles $root $source[0].files
    $history=@(Get-UpdateSchema (Get-UpdatePg $control)|ForEach-Object{[pscustomobject]@{version=$_.version;checksum=$_.checksum}})
    if(-not(Test-MigrationEquality $history $context.manifest.schemaBefore)){throw 'El esquema original no coincide.'}
    Assert-UpdateInventory $context.inventory
    # Retain the previous recovery records before starting a distinct operation.
    $record=Join-Path $root ('maintenance/'+$previous.operationId+'-recovered.json')
    if(-not(Test-Path -LiteralPath $record)){Write-ControlJson $control $record ([pscustomobject]@{operation=$previous;context=$context})}
    $operation=[pscustomobject]@{format=1;operationId=('update-'+[Guid]::NewGuid().ToString('N'));phase='Preflight';sourceReleaseId=$context.sourceId;targetReleaseId=$context.manifest.releaseId;backupReference=$null;checksPassed=$false;step='backup-only-preflight';services=@()}
    Set-UpdateOperation $control $operation
    $context.operationId=$operation.operationId
    Write-ControlJson $control (Join-Path $root 'maintenance/context.json') $context
    $verified=$false;$failure=$null
    try {
        Set-ApplicationUpdatePhase $control 'Quiescing' 'backup-only-protect-writers'
        Invoke-UpdateWriterAction $control 'stop'
        Set-ApplicationUpdatePhase $control 'BackingUp' 'backup-only-capture'
        $null=New-CoherentUpdateBackup $control $context.inventory
        $null=Test-CoherentUpdateBackup $control 55439
        $verified=$true
    }catch{
        $failure=[pscustomobject]@{reasonCode='BackupVerificationFailed';trace=$_.ScriptStackTrace}
    }
    try {
        $recovery=Invoke-ApplicationUpdateRecovery $control $context $credential
        $recoveryStatus=$recovery.status
    }catch{
        $recoveryFailure=$_
        try{Write-ControlJson $control (Join-Path $root 'maintenance/recovery-failure.json') ([pscustomobject]@{format=1;operationId=$operation.operationId;failureStep=(Read-UpdateJson $control.operationPath).step;reasonCode='RecoveryChecksFailed';trace=$recoveryFailure.ScriptStackTrace})}catch{}
        Set-ApplicationUpdatePhase $control 'RecoveryRequired' 'backup-only-recovery-required'
        $recoveryStatus='RecoveryRequired'
    }
    $diagnosticPath=Join-Path $root 'maintenance/backup-validation.json'
    $diagnostic=if(Test-Path -LiteralPath $diagnosticPath){Read-UpdateJson $diagnosticPath}else{$null}
    if($diagnostic -and $diagnostic.operationId -cne $operation.operationId){$diagnostic=$null}
    [pscustomobject]@{scope='Isolated backup restoration only; candidate never applied';operationId=$operation.operationId;backupVerified=$verified;recoveryStatus=$recoveryStatus;diagnostic=$diagnostic;failure=$failure;updateSucceeded=$false;productionAccepted=$false}|ConvertTo-Json -Depth 8
}finally{if($control){$control.lock.Dispose()};$credential=$null;$token=$null;$secure.Dispose()}
