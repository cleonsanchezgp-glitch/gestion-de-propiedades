$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$directory=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020'
$report=Join-Path $directory 'r10-delivery.json'
try{
    $vm=Get-VM -Id 'a9d05c33-17e5-465f-a001-028342767c6a'
    if($vm.Name -cne 'Aelium-Ensayo-HyperV' -or $vm.State -ne 'Running'){throw 'Expected Hyper-V copy required.'}
    if(@(Get-VMNetworkAdapter -VM $vm|Where-Object{$_.SwitchName}).Count){throw 'Isolated networking required.'}
    $files=@(
        @{source=(Join-Path $directory 'delivery/aelium-maintenance-20261020T095513202Z.zip');name='Herramientas-r10.zip';hash='d13dd8e58c306a7b4d5202a2455914b64f6ab3c7ceb62c9a972db61fe5d4ddb0'},
        @{source=(Join-Path $directory 'delivery/candidate-r2.exe');name='candidate-r2.exe';hash='923177cce947865ad62c22ec3a4b227b87792c6af0e19f76d33145871540b0f2'},
        @{source=(Join-Path $directory 'delivery/Ejecutar-Ensayo-HyperV-r10.ps1');name='Ejecutar-Ensayo-HyperV-r10.ps1';hash=$null}
    )
    foreach($file in $files){
        if($file.hash -and (Get-FileHash -LiteralPath $file.source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.hash){throw 'Source delivery hash mismatch.'}
        Copy-VMFile -VM $vm -SourcePath $file.source -DestinationPath ('C:\AeliumHyperVPruebas\'+$file.name) -FileSource Host -CreateFullPath -Force
    }
    [pscustomobject]@{status='CorrectedRehearsalDelivered';releaseId='rehearsal-vm-20261020-r2';files=@($files.name);updateApplied=$false;productionAccepted=$false}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $report -Encoding UTF8
}catch{[pscustomobject]@{status='DeliveryFailed';reason=$_.Exception.Message}|ConvertTo-Json -Compress|Set-Content -LiteralPath $report -Encoding UTF8;exit 1}
