$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$directory=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020'
$report=Join-Path $directory 'apply-delivery.json'
try{
    $vm=Get-VM -Id 'a9d05c33-17e5-465f-a001-028342767c6a'
    if($vm.Name -cne 'Aelium-Ensayo-HyperV' -or $vm.State -ne 'Running'){throw 'Expected running Hyper-V copy required.'}
    if(@(Get-VMNetworkAdapter -VM $vm|Where-Object{$_.SwitchName}).Count){throw 'Test copy must remain disconnected.'}
    Copy-VMFile -VM $vm -SourcePath (Join-Path $directory 'delivery/Aplicar-Ensayo-HyperV-r9.ps1') -DestinationPath 'C:\AeliumHyperVPruebas\Aplicar-Ensayo-HyperV-r9.ps1' -FileSource Host -CreateFullPath -Force
    [pscustomobject]@{status='LocalApplyWrapperDelivered';vmId=[string]$vm.Id;updateApplied=$false}|ConvertTo-Json -Compress|Set-Content -LiteralPath $report -Encoding UTF8
}catch{[pscustomobject]@{status='DeliveryFailed';reason=$_.Exception.Message}|ConvertTo-Json -Compress|Set-Content -LiteralPath $report -Encoding UTF8;exit 1}
