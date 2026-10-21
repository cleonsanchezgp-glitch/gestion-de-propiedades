$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$directory=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020'
$report=Join-Path $directory 'rehearsal-delivery.json'
try{
    $vm=Get-VM -Id 'a9d05c33-17e5-465f-a001-028342767c6a'
    if($vm.Name -cne 'Aelium-Ensayo-HyperV' -or $vm.State -ne 'Running'){throw 'Expected running Hyper-V copy required.'}
    $archive=Join-Path $directory 'delivery/aelium-maintenance-20261020T090804410Z.zip'
    if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne '0adb0c9ba1bfe755a2c1b831c6b9a3fd3950f4c1ff09d66bab954f6e8a8ba487'){throw 'Unexpected source archive hash.'}
    Copy-VMFile -VM $vm -SourcePath $archive -DestinationPath 'C:\AeliumHyperVPruebas\Ensayo-HyperV-r8.zip' -FileSource Host -CreateFullPath -Force
    Copy-VMFile -VM $vm -SourcePath (Join-Path $directory 'delivery/Comprobar-Copia-HyperV-r8.ps1') -DestinationPath 'C:\AeliumHyperVPruebas\Comprobar-Copia-HyperV-r8.ps1' -FileSource Host -CreateFullPath -Force
    [pscustomobject]@{status='RehearsalToolsDelivered';vmId=[string]$vm.Id;sha256='0adb0c9ba1bfe755a2c1b831c6b9a3fd3950f4c1ff09d66bab954f6e8a8ba487';updateApplied=$false}|ConvertTo-Json -Compress|Set-Content -LiteralPath $report -Encoding UTF8
}catch{[pscustomobject]@{status='DeliveryFailed';reason=$_.Exception.Message}|ConvertTo-Json -Compress|Set-Content -LiteralPath $report -Encoding UTF8;exit 1}
