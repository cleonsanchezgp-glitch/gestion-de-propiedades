[CmdletBinding()]
param([switch]$UseCompletedClone)
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$output=Join-Path $workspace 'tests/artifacts/hyperv-copy-20261020'
$report=Join-Path $output 'status.json'
$vmName='Aelium-Ensayo-HyperV'
$sourceId='bdafd07c-22f5-445a-ba5f-88bb09eddfad'
$diskId='acd6fc22-d6f6-4b67-b169-b9a494d4b879'
$vbox='C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$destination=Join-Path $output 'aelium-ensayo.vhd'
$stage='administrator-check';$clone=$null
function Publish-Status([string]$Status,$Details=$null){
    $value=[pscustomobject]@{status=$Status;stage=$script:stage;observedUtc=[DateTime]::UtcNow.ToString('o');sourceVmId=$script:sourceId;vmName=$script:vmName;details=$Details}
    $temp=$script:report+'.tmp'
    [IO.File]::WriteAllText($temp,($value|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    if(Test-Path -LiteralPath $script:report){[IO.File]::Replace($temp,$script:report,[NullString]::Value)}else{[IO.File]::Move($temp,$script:report)}
}
function Assert-SourceOff {
    $info=& $script:vbox showvminfo $script:sourceId --machinereadable
    if($LASTEXITCODE -ne 0 -or $info -cnotcontains 'VMState="poweroff"' -or $info -cnotcontains 'firmware="BIOS"' -or $info -cnotcontains ('"SATA-ImageUUID-0-0"="'+$script:diskId+'"')){throw 'Source must be normally powered off with the reviewed BIOS/disk identity.'}
}
try {
    # Fail before any VM/disk changes if not running as host administrator.
    $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Host administrator required.'}
    $stage='preflight'
    $null=Get-VMHost -ErrorAction Stop
    Assert-SourceOff
    if(Get-VM -Name $vmName -ErrorAction SilentlyContinue){throw 'Destination VM already exists; preserve it.'}
    if((Test-Path -LiteralPath $destination) -and -not $UseCompletedClone){throw 'Destination disk already exists; preserve it.'}
    $reserve=12GB
    $drive=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    if($drive.FreeSpace -lt $reserve -or (-not $UseCompletedClone -and $drive.FreeSpace -lt (20GB+$reserve))){throw 'Insufficient free host disk space.'}
    New-Item -ItemType Directory -Path $output -Force|Out-Null
    if($UseCompletedClone){
        $completion=Get-Content -LiteralPath (Join-Path $output 'clone.stdout.log') -Raw
        $receipt=$completion -cmatch "^Clone medium created in format 'VHD'\. UUID: [a-f0-9-]{36}\s*$"
        if(-not $receipt){
            $failure=Get-Content -LiteralPath (Join-Path $output 'clone.stderr.log') -Raw
            $pathPattern=[regex]::Escape($destination)
            $registrationConflict="(?s)Cannot register the hard disk '$pathPattern' \{[a-f0-9-]{36}\} because a hard disk '$pathPattern' with UUID \{[a-f0-9-]{36}\} already exists"
            if($failure -notmatch $registrationConflict -or $failure -notmatch 'E_INVALIDARG'){
                throw 'No successful clone receipt or recognized VirtualBox registration-conflict failure; preserve destination.'
            }
            $mediumInfo=& $vbox showmediuminfo $destination
            if($LASTEXITCODE -ne 0 -or ($mediumInfo -join "`n") -notmatch '(?m)^Storage format:\s+VHD\s*$' -or ($mediumInfo -join "`n") -notmatch '(?m)^Capacity:\s+51200 MBytes\s*$'){
                throw 'The registration-conflict clone is not a readable 50 GiB VHD; preserve destination.'
            }
        }
    }else{
    $stage='clone-offline-disk';Publish-Status 'Running' @{reserveBytes=$reserve;sourceDiskId=$diskId}
    $arguments=@('clonemedium','disk',$diskId,('"'+$destination+'"'),'--format','VHD','--variant','Standard')
    $clone=Start-Process -FilePath $vbox -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'clone.stdout.log') -RedirectStandardError (Join-Path $output 'clone.stderr.log')
    $null=$clone.Handle # Retain process handle so PS 5.1 can read its exit code.
    $watch=[Diagnostics.Stopwatch]::StartNew();$lastReport=0
    while(-not $clone.HasExited){
        $free=(Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
        if($free -lt $reserve){$clone.Kill();$null=$clone.WaitForExit(10000);throw 'Clone stopped to preserve host free-space reserve; partial destination retained.'}
        if($watch.Elapsed.TotalMinutes -gt 45){$clone.Kill();$null=$clone.WaitForExit(10000);throw 'Clone time limit exceeded; partial destination retained.'}
        if(($watch.Elapsed.TotalSeconds-$lastReport) -gt 15){
            $length=if(Test-Path -LiteralPath $destination){(Get-Item -LiteralPath $destination).Length}else{0}
            Publish-Status 'Running' @{destinationBytes=$length;freeHostBytes=$free};$lastReport=$watch.Elapsed.TotalSeconds
        }
        Start-Sleep -Seconds 1;$clone.Refresh()
    }
    $clone.WaitForExit();$clone.Refresh()
    if($clone.ExitCode -ne 0){throw 'Disk cloning failed; preserve original and diagnostic files.'}
    $clone.Dispose();$clone=$null
    }
    $stage='validate-independent-disk';Assert-SourceOff
    $disk=Get-VHD -Path $destination -ErrorAction Stop
    if($disk.Size -ne 50GB -or $disk.VhdFormat -ne 'VHD' -or $disk.VhdType -ne 'Dynamic' -or $disk.ParentPath){throw 'Unexpected cloned disk layout.'}
    $stage='create-powered-off-vm'
    $vm=New-VM -Name $vmName -Generation 1 -MemoryStartupBytes 4GB -VHDPath $destination -Path (Join-Path $output 'config')
    Set-VMProcessor -VM $vm -Count 2
    Set-VMMemory -VM $vm -DynamicMemoryEnabled $false
    Set-VM -VM $vm -AutomaticStartAction Nothing -AutomaticStopAction ShutDown -AutomaticCheckpointsEnabled $false -CheckpointType Disabled
    $adapters=@(Get-VMNetworkAdapter -VM $vm)
    if(@($adapters|Where-Object{$_.SwitchName}).Count){throw 'Unexpected network connection; do not start VM.'}
    $current=Get-VM -Id $vm.Id
    if($current.State -ne 'Off'){throw 'Destination VM must remain off.'}
    $stage='copy-ready'
    Publish-Status 'HyperVCopyCreated' @{vmId=[string]$vm.Id;generation=1;state='Off';memoryBytes=4GB;virtualProcessors=2;network='Disconnected';disk=$destination;diskBytes=(Get-Item -LiteralPath $destination).Length;freeHostBytes=(Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace;originalPreserved=$true;guestBootVerified=$false;updateSucceeded=$false}
}catch{
    if(-not(Test-Path -LiteralPath $output)){New-Item -ItemType Directory -Path $output -Force|Out-Null}
    Publish-Status 'Failed' @{reason=$_.Exception.Message;errorType=$_.Exception.GetType().Name;trace=$_.ScriptStackTrace;originalPreserved=$true}
    exit 1
}finally{if($clone){if(-not $clone.HasExited){$clone.Kill();$null=$clone.WaitForExit(10000)};$clone.Dispose()}}
