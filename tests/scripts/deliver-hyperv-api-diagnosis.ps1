$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$report=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020/api-diagnosis-delivery.json'
try{
    $vm=Get-VM -Id 'a9d05c33-17e5-465f-a001-028342767c6a'
    if($vm.Name -cne 'Aelium-Ensayo-HyperV' -or $vm.State -ne 'Running'){throw 'Expected running Hyper-V copy required.'}
    Copy-VMFile -VM $vm -SourcePath (Join-Path $workspace 'tests/scripts/diagnose-api-startup.ps1') -DestinationPath 'C:\AeliumHyperVPruebas\Diagnosticar-Arranque-API.ps1' -FileSource Host -CreateFullPath -Force
    [pscustomobject]@{status='ApiStartupDiagnosisDelivered'}|ConvertTo-Json -Compress|Set-Content -LiteralPath $report -Encoding UTF8
}catch{[pscustomobject]@{status='DeliveryFailed';reason=$_.Exception.Message}|ConvertTo-Json -Compress|Set-Content -LiteralPath $report -Encoding UTF8;exit 1}
