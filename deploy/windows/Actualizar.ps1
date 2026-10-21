[CmdletBinding()]
param([ValidateSet('Preflight','Apply','Finalize','Recover')][string]$Action='Preflight',
    [string]$InstallationRoot='C:\ProgramData\Aelium\Propiedades',
    [string]$Archive,[string]$ExpectedSha256,[string]$CatalogPath,[string]$ObservationPath,[string]$InventoryPath,
    [int]$VerificationPort=55439,[pscredential]$Credential,[switch]$LocalRehearsal)
. (Join-Path $PSScriptRoot 'update/Updater.ps1')
$catalog=$null;$observation=$null;$inventory=$null
try {
    if ($Action -cin @('Preflight','Apply')) {
        if (-not $Archive -or -not $ExpectedSha256 -or -not $CatalogPath -or -not $ObservationPath -or -not $InventoryPath) {throw 'Package external hash and reviewed catalog/environment/storage files required.'}
        $catalog=Read-UpdateJson $CatalogPath;$observation=Read-UpdateJson $ObservationPath;$inventory=Read-UpdateJson $InventoryPath
        if ($Action -ceq 'Apply') {
            # Validate before prompting, and again under the operation flow.
            $preflight=Test-ApplicationUpdatePreflight $InstallationRoot $Archive $ExpectedSha256 $catalog $observation $inventory -LocalRehearsal:$LocalRehearsal
            if ($preflight.status -ceq 'AlreadyApplied') {
                $mode=if ($LocalRehearsal) {'LocalRehearsal'}else{'Production'}
                Get-UpdateResult 'AlreadyApplied' $preflight $mode | ConvertTo-Json -Compress
                exit 0
            }
        }
    }
    if ($Action -cne 'Preflight' -and $null -eq $Credential) {$Credential=Get-Credential -Message 'Cuenta existente del propietario del portal (no se guarda la contraseña)'}
    $result=Invoke-ApplicationUpdate $InstallationRoot $Action $Archive $ExpectedSha256 $catalog $observation $inventory $VerificationPort $Credential -LocalRehearsal:$LocalRehearsal
    $result | ConvertTo-Json -Compress
    if ($result.status -cin @('UpdateSucceeded','AlreadyApplied','PreflightVerified','LocalRehearsalSucceeded','LocalRehearsalAlreadyApplied','LocalRehearsalPreflightVerified')) {exit 0}
    if ($result.status -ceq 'VerificationPending') {exit 2}
    if ($result.status -ceq 'UpdateFailedRecovered') {exit 3}
    exit 4
}catch {Write-Error 'Actualización rechazada o estado incompleto. No se declara éxito. Revise los metadatos locales y use Recover para una operación interrumpida.';exit 4}
