$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$directory=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020/delivery'
$baseDefinition=Get-Content -LiteralPath (Join-Path $directory 'r12-delivery-definition.json') -Raw|ConvertFrom-Json
$sourceWrapper=Join-Path $directory 'Ejecutar-Ensayo-HyperV-r12.ps1'
$wrapper=Join-Path $directory 'Ejecutar-Ensayo-HyperV-r13.ps1'
$definitionPath=Join-Path $directory 'r13-delivery-definition.json'
if((Test-Path -LiteralPath $wrapper) -or (Test-Path -LiteralPath $definitionPath)){throw 'Revision 13 delivery already exists; preserve its immutable identity.'}
if((Get-FileHash -LiteralPath $baseDefinition.candidate -Algorithm SHA256).Hash.ToLowerInvariant() -cne $baseDefinition.candidateSha256){throw 'Pinned rehearsal candidate changed.'}
$oldOperationId='update-4f39e0a1a88e41318707ef72746f2136'
$newOperationId='update-8368add0f6f54a0bb24c6f77f281695d'
$template=Get-Content -LiteralPath $sourceWrapper -Raw
if(-not $template.Contains($oldOperationId)){throw 'Expected previous baseline operation ID not found in source wrapper.'}
$template=$template.Replace($oldOperationId,$newOperationId)
[IO.File]::WriteAllText($wrapper,$template,(New-Object Text.UTF8Encoding($true)))
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($wrapper,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Generated revision 13 wrapper syntax failed.'}
$definition=[pscustomobject]@{
    toolsArchive=$baseDefinition.toolsArchive
    toolsSha256=$baseDefinition.toolsSha256
    wrapper=$wrapper
    wrapperSha256=(Get-FileHash -LiteralPath $wrapper -Algorithm SHA256).Hash.ToLowerInvariant()
    candidate=$baseDefinition.candidate
    candidateSha256=$baseDefinition.candidateSha256
    releaseId=$baseDefinition.releaseId
    experimentalPolicy=$baseDefinition.experimentalPolicy
    productionAccepted=$false
    baselineOperationId=$newOperationId
}
$definition|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $definitionPath -Encoding UTF8
Write-Output 'Revision 13 delivery prepared for the verified recovered baseline; no VM changes or update applied.'
