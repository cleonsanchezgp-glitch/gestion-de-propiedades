$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$directory=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020'
$report=Join-Path $directory 'r12-delivery.json'
try{
    $definition=Get-Content -LiteralPath (Join-Path $directory 'delivery/r12-delivery-definition.json') -Raw|ConvertFrom-Json
    $vm=Get-VM -Id 'a9d05c33-17e5-465f-a001-028342767c6a'
    if($vm.Name -cne 'Aelium-Ensayo-HyperV' -or $vm.State -ne 'Running'){throw 'Expected Hyper-V copy required.'}
    if(@(Get-VMNetworkAdapter -VM $vm|Where-Object{$_.SwitchName}).Count){throw 'Isolated networking required.'}
    $files=@(
        @{source=$definition.toolsArchive;hash=$definition.toolsSha256;name='Herramientas-r12.zip'},
        @{source=$definition.candidate;hash=$definition.candidateSha256;name='candidate-r3.exe'},
        @{source=$definition.wrapper;hash=$definition.wrapperSha256;name='Ejecutar-Ensayo-HyperV-r12.ps1'}
    )
    foreach($file in $files){
        $source=[IO.Path]::GetFullPath($file.source)
        if(-not $source.StartsWith($directory+'\delivery\',[StringComparison]::OrdinalIgnoreCase)){throw 'Source outside task delivery.'}
        if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.hash){throw 'Delivery integrity failed.'}
        Copy-VMFile -VM $vm -SourcePath $source -DestinationPath ('C:\AeliumHyperVPruebas\'+$file.name) -FileSource Host -CreateFullPath -Force
    }
    [pscustomobject]@{status='ExperimentalLocalRehearsalDelivered';releaseId=$definition.releaseId;files=@($files.name);updateApplied=$false;productionAccepted=$false}|ConvertTo-Json|Set-Content -LiteralPath $report -Encoding UTF8
}catch{[pscustomobject]@{status='DeliveryFailed';reason=$_.Exception.Message}|ConvertTo-Json|Set-Content -LiteralPath $report -Encoding UTF8;exit 1}
