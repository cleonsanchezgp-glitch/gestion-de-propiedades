$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$report=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020/r11-diagnosis-delivery.json'
try {
    $vm=Get-VM -Id 'a9d05c33-17e5-465f-a001-028342767c6a'
    if($vm.Name -cne 'Aelium-Ensayo-HyperV' -or $vm.State -ne 'Running'){throw 'Expected running Hyper-V copy.'}
    if(@(Get-VMNetworkAdapter -VM $vm|Where-Object{$_.SwitchName}).Count){throw 'Isolated networking required.'}
    $source=Join-Path $PSScriptRoot 'Diagnosticar-Conservacion-HyperV-r11.ps1'
    $target='C:\AeliumHyperVPruebas\Diagnosticar-Conservacion-HyperV-r11.ps1'
    Copy-VMFile -VM $vm -SourcePath $source -DestinationPath $target -FileSource Host -CreateFullPath -Force
    [pscustomobject]@{status='ReadOnlyDiagnosisDelivered';guestPath=$target;sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;updateApplied=$false;productionAccepted=$false}|ConvertTo-Json|Set-Content -LiteralPath $report -Encoding UTF8
} catch {
    [pscustomobject]@{status='DeliveryFailed';reason=$_.Exception.Message}|ConvertTo-Json|Set-Content -LiteralPath $report -Encoding UTF8
    exit 1
}
