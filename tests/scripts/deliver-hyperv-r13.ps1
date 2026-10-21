$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$directory=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020'
$report=Join-Path $directory 'r13-delivery.json'
try{
    $prepared=Get-Content -LiteralPath (Join-Path $directory 'status.json') -Raw|ConvertFrom-Json
    $startup=Get-Content -LiteralPath (Join-Path $directory 'startup.json') -Raw|ConvertFrom-Json
    if($prepared.status -cne 'HyperVCopyCreated' -or $startup.status -cne 'GuestChecksDelivered'){throw 'Prepared and booted isolated copy required.'}
    $vm=Get-VM -Id ([guid]$prepared.details.vmId)
    if($vm.Name -cne 'Aelium-Ensayo-HyperV' -or $vm.State -ne 'Running' -or $startup.vmId -cne [string]$vm.Id){throw 'Expected running Hyper-V copy required.'}
    if(@(Get-VMNetworkAdapter -VM $vm|Where-Object{$_.SwitchName}).Count){throw 'Isolated networking required.'}
    $definition=Get-Content -LiteralPath (Join-Path $directory 'delivery/r13-delivery-definition.json') -Raw|ConvertFrom-Json
    if($definition.baselineOperationId -cne 'update-8368add0f6f54a0bb24c6f77f281695d' -or $definition.productionAccepted){throw 'Unexpected rehearsal delivery definition.'}
    $files=@(
        @{source=$definition.toolsArchive;hash=$definition.toolsSha256;name='Herramientas-r12.zip'},
        @{source=$definition.candidate;hash=$definition.candidateSha256;name='candidate-r3.exe'},
        @{source=$definition.wrapper;hash=$definition.wrapperSha256;name='Ejecutar-Ensayo-HyperV-r13.ps1'}
    )
    foreach($file in $files){
        $source=[IO.Path]::GetFullPath($file.source)
        if(-not $source.StartsWith((Join-Path $directory 'delivery')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Source outside task delivery.'}
        if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.hash){throw 'Delivery integrity failed.'}
        Copy-VMFile -VM $vm -SourcePath $source -DestinationPath ('C:\AeliumHyperVPruebas\'+$file.name) -FileSource Host -CreateFullPath -Force
    }
    [pscustomobject]@{status='ExperimentalLocalRehearsalDelivered';releaseId=$definition.releaseId;baselineOperationId=$definition.baselineOperationId;vmId=[string]$vm.Id;files=@($files.name);updateApplied=$false;productionAccepted=$false}|ConvertTo-Json|Set-Content -LiteralPath $report -Encoding UTF8
}catch{[pscustomobject]@{status='DeliveryFailed';reason=$_.Exception.Message;updateApplied=$false;productionAccepted=$false}|ConvertTo-Json|Set-Content -LiteralPath $report -Encoding UTF8;exit 1}
