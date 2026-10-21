$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$directory=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020'
$report=Join-Path $directory 'startup.json'
$stage='validate-copy'
try {
    $prepared=Get-Content -LiteralPath (Join-Path $directory 'status.json') -Raw|ConvertFrom-Json
    if($prepared.status -cne 'HyperVCopyCreated'){throw 'Clone preparation is not complete.'}
    $vm=Get-VM -Id ([guid]$prepared.details.vmId)
    if($vm.Name -cne 'Aelium-Ensayo-HyperV' -or $vm.Generation -ne 1 -or $vm.MemoryStartup -ne 4GB){throw 'Unexpected copied VM.'}
    $source=& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' showvminfo 'bdafd07c-22f5-445a-ba5f-88bb09eddfad' --machinereadable
    if($LASTEXITCODE -ne 0 -or $source -cnotcontains 'VMState="poweroff"'){throw 'Keep source VM powered off before starting copy.'}
    if(@(Get-VMNetworkAdapter -VM $vm|Where-Object{$_.SwitchName}).Count){throw 'Copy must have disconnected networking.'}
    $stage='start-isolated-copy'
    Get-VMIntegrationService -VM $vm|Enable-VMIntegrationService
    if($vm.State -eq 'Off'){Start-VM -VM $vm|Out-Null}elseif($vm.State -ne 'Running'){throw 'Unexpected VM power state.'}
    $stage='deliver-read-only-checks'
    $files=@(
        @{source=(Join-Path $workspace 'tests/scripts/verify-hyperv-copy.ps1');name='Verificar-Copia-HyperV.ps1'},
        @{source=(Join-Path $workspace 'tests/scripts/check-vm-owner-access.ps1');name='Comprobar-Acceso.ps1'},
        @{source=(Join-Path $workspace 'tests/scripts/diagnose-vm-freeze.ps1');name='Diagnosticar-Bloqueo-VM.ps1'}
    )
    $deadline=[DateTime]::UtcNow.AddMinutes(4);$delivered=$false
    do {
        try{
            foreach($file in $files){Copy-VMFile -VM $vm -SourcePath $file.source -DestinationPath ('C:\AeliumHyperVPruebas\'+$file.name) -FileSource Host -CreateFullPath -Force -ErrorAction Stop}
            $delivered=$true
        }catch{if([DateTime]::UtcNow -ge $deadline){throw 'Guest integration file transfer unavailable; use read-only ISO fallback.'};Start-Sleep -Seconds 5}
    }while(-not $delivered)
    $stage='ready-for-guest-check'
    [pscustomobject]@{status='GuestChecksDelivered';observedUtc=[DateTime]::UtcNow.ToString('o');vmId=[string]$vm.Id;vmName=$vm.Name;network='Disconnected';guestCommand='powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\AeliumHyperVPruebas\Verificar-Copia-HyperV.ps1';ownerAccessVerified=$false;updateSucceeded=$false}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $report -Encoding UTF8
    # Interactive console is intended for the user to inspect Windows and run
    # the local check; it is not a hidden background helper.
    Start-Process -FilePath 'C:\Windows\System32\vmconnect.exe' -ArgumentList @('localhost',$vm.Name)|Out-Null
}catch{
    [pscustomobject]@{status='StartupIncomplete';stage=$stage;reason=$_.Exception.Message;trace=$_.ScriptStackTrace;updateSucceeded=$false}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $report -Encoding UTF8
    exit 1
}
