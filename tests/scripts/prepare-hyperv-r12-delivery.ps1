$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$directory=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020/delivery'
$candidate=Join-Path $directory 'candidate-r3.exe'
$candidateHash='eecba3065b2ab12029ee4985cc6b01599492bc347435ffd804207fb9fb31385f'
if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -cne $candidateHash){throw 'Unexpected immutable revision 3.'}
$bundle=(& (Join-Path $workspace 'deploy/windows/Build-MaintenancePackage.ps1') -OutputDirectory $directory)|ConvertFrom-Json
$template=Get-Content -LiteralPath (Join-Path $directory 'Ejecutar-Ensayo-HyperV-r10.ps1') -Raw
$replacements=[ordered]@{
    'r10'='r12'
    'r2'='r3'
    'build2'='build3'
    'revision 2'='revision 3'
    'd13dd8e58c306a7b4d5202a2455914b64f6ab3c7ceb62c9a972db61fe5d4ddb0'=$bundle.sha256
    '923177cce947865ad62c22ec3a4b227b87792c6af0e19f76d33145871540b0f2'=$candidateHash
    'update-6aca6a2f1610481398f5af957b4ea8c9'='update-4f39e0a1a88e41318707ef72746f2136'
}
foreach($key in $replacements.Keys){
    if(-not $template.Contains($key)){throw ('Expected rehearsal template token missing: '+$key)}
    $template=$template.Replace($key,$replacements[$key])
}
$wrapper=Join-Path $directory 'Ejecutar-Ensayo-HyperV-r12.ps1'
if(Test-Path -LiteralPath $wrapper){throw 'Existing delivery must be retained.'}
[IO.File]::WriteAllText($wrapper,$template,(New-Object Text.UTF8Encoding($true)))
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($wrapper,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Generated guest wrapper syntax failed.'}
[pscustomobject]@{
    toolsArchive=$bundle.archive;toolsSha256=$bundle.sha256
    wrapper=$wrapper;wrapperSha256=(Get-FileHash -LiteralPath $wrapper -Algorithm SHA256).Hash.ToLowerInvariant()
    candidate=$candidate;candidateSha256=$candidateHash
    releaseId='rehearsal-vm-20261020-r3';experimentalPolicy='keycloak-26.7.4-local-runtime-v1';productionAccepted=$false
}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $directory 'r12-delivery-definition.json') -Encoding UTF8
Write-Output 'Revision 12 delivery prepared; no VM changes or update applied.'
