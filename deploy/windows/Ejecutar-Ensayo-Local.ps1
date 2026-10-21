[CmdletBinding()]
param(
    [ValidateSet('Preflight','Apply','Finalize','Recover')][string]$Action='Preflight',
    [string]$InstallationRoot='C:\ProgramData\Aelium\Propiedades',
    [string]$WorkDirectory='C:\AeliumEnsayo\ActualizacionLocal'
)
$ErrorActionPreference='Stop'
$parameters=@{Action=$Action;InstallationRoot=$InstallationRoot;LocalRehearsal=$true}
if($Action -cin @('Preflight','Apply')) {
    $archive=Join-Path $WorkDirectory 'application-update.zip'
    $hash=((Get-Content -LiteralPath ($archive+'.sha256') -Raw).Trim() -split '\s+')[0]
    $parameters.Archive=$archive;$parameters.ExpectedSha256=$hash
    $parameters.CatalogPath=Join-Path $WorkDirectory 'catalog.json'
    $parameters.ObservationPath=Join-Path $WorkDirectory 'observation.json'
    $parameters.InventoryPath=Join-Path $WorkDirectory 'inventory.json'
}
& (Join-Path $PSScriptRoot 'Actualizar.ps1') @parameters
exit $LASTEXITCODE
