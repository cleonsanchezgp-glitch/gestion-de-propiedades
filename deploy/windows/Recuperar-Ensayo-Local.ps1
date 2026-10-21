[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ExpectedOperationId,
    [string]$InstallationRoot='C:\ProgramData\Aelium\Propiedades'
)
. (Join-Path $PSScriptRoot 'update/Updater.ps1')
Assert-ControlAdministrator
$root=[IO.Path]::GetFullPath($InstallationRoot).TrimEnd('\')
Assert-LocalRehearsal $root
$control=[pscustomobject]@{root=$root}
$operation=Read-UpdateJson (Join-Path $root 'maintenance/operation.json')
$context=Read-UpdateJson (Join-Path $root 'maintenance/context.json')
if ($operation.operationId -cne $ExpectedOperationId -or $context.operationId -cne $ExpectedOperationId -or $operation.phase -cne 'RecoveryRequired' -or $context.applicationChangeStarted -isnot [bool] -or $context.applicationChangeStarted -ne $false -or (Get-UpdateVerificationMode $context) -cne 'LocalRehearsal') {throw 'Esta recuperacion revisada solo admite la operacion local indicada, sin cambios de aplicacion iniciados.'}
$settings=Read-UpdateJson (Join-Path $root 'config/settings.json')
if ($operation.backupReference -ceq ('backups/'+$ExpectedOperationId)) {
    $backupPath=Join-Path $root ($operation.backupReference+'/backup.private.json')
    if(Test-Path -LiteralPath $backupPath){$backup=Read-UpdateJson $backupPath;Write-Host ('Estado de comprobacion de la copia previa: verified='+$backup.verified)}
}
$secure=Read-Host ('Contrasena de pruebas de '+$settings.Username+' (no se guarda)') -AsSecureString
$credential=New-Object Management.Automation.PSCredential($settings.Username,$secure)
try {
    # Verify credentials against the currently running identity before stopping
    # anything. No raw response, access token or configuration is printed.
    $token=Get-UpdateOwnerToken $control $credential;$token=$null
    Write-Host 'Identidad disponible y credenciales aceptadas. Recuperando la operacion anterior, sin aplicar la candidata.'
    $result=Invoke-ApplicationUpdate $root 'Recover' '' '' $null $null $null 55439 $credential -LocalRehearsal
    $result|ConvertTo-Json -Depth 5
}finally{$token=$null;$credential=$null;$secure.Dispose()}
