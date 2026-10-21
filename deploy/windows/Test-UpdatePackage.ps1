[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ArchivePath,
    [Parameter(Mandatory=$true)][string]$ExpectedSha256,
    [string]$InstallationRoot,
    [string]$CatalogPath,
    [string]$ObservationPath
)
. (Join-Path $PSScriptRoot 'update/Package.ps1')
$verified = Test-UpdateArchive $ArchivePath $ExpectedSha256
if ($InstallationRoot -or $CatalogPath -or $ObservationPath) {
    if (-not $InstallationRoot -or -not $CatalogPath -or -not $ObservationPath) { throw 'Supply installation root, catalog and observation together.' }
    Test-UpdateSource $verified.manifest $InstallationRoot (Read-UpdateJson $CatalogPath) (Read-UpdateJson $ObservationPath)
} else {
    [pscustomobject]@{status=$verified.status;releaseId=$verified.manifest.releaseId;buildId=$verified.manifest.buildId;sha256=$verified.archiveSha256;livePreflightComplete=$false}
}
