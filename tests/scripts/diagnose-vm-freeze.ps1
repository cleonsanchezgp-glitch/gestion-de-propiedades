[CmdletBinding()]
param([string]$InstallationRoot='C:\ProgramData\Aelium\Propiedades')
$ErrorActionPreference='Stop'
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Ejecutar PowerShell como administrador dentro de la VM.'}
$root=[IO.Path]::GetFullPath($InstallationRoot).TrimEnd('\')
$os=Get-CimInstance Win32_OperatingSystem
$disk=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$operation=$null;$context=$null
foreach($name in @('operation','context')){
    $path=Join-Path $root ('maintenance/'+$name+'.json')
    if(Test-Path -LiteralPath $path){Set-Variable -Name $name -Value (Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json)}
}
$services=@(foreach($id in @('AeliumPostgres','AeliumKeycloak','AeliumAPI')){
    $s=Get-CimInstance Win32_Service -Filter ("Name='"+$id+"'")
    if($s){$s|Select-Object Name,State,StartMode,ExitCode}
})
$processes=@(Get-Process | Where-Object {$_.ProcessName -in @('powershell','postgres','pg_dump','pg_dumpall','pg_restore','psql','initdb','pg_ctl','java','propiedades-backend')} | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 ProcessName,Id,WorkingSet64,PrivateMemorySize64,CPU)
$since=(Get-Date).AddDays(-2)
$events=@(foreach($query in @(
    @{LogName='System';ProviderName='Microsoft-Windows-Resource-Exhaustion-Detector';Id=2004;StartTime=$since},
    @{LogName='System';ProviderName='Microsoft-Windows-Kernel-Power';Id=41;StartTime=$since},
    @{LogName='System';ProviderName='EventLog';Id=6008;StartTime=$since},
    @{LogName='System';ProviderName='disk';Id=7,51,153;StartTime=$since},
    @{LogName='System';ProviderName='storahci';Id=129;StartTime=$since},
    @{LogName='Application';ProviderName='Application Hang';Id=1002;StartTime=$since}
)){
    try{Get-WinEvent -FilterHashtable $query -MaxEvents 10 -ErrorAction Stop | ForEach-Object {[pscustomobject]@{observedUtc=$_.TimeCreated.ToUniversalTime().ToString('o');provider=$_.ProviderName;id=$_.Id;level=$_.LevelDisplayName}}}catch{}
})
$partial=@()
if($operation -and $operation.operationId -cmatch '^update-[a-f0-9]{32}$'){
    $directory=Join-Path $root ('backups/'+$operation.operationId)
    if(Test-Path -LiteralPath $directory -PathType Container){
        # Fixed names only; no recursive inventory or dump/configuration contents.
        foreach($name in @('propiedades.dump','keycloak.dump','globals.private.sql','backup.private.json')){
            $path=Join-Path $directory $name
            if(Test-Path -LiteralPath $path -PathType Leaf){$file=Get-Item -LiteralPath $path;$partial+=[pscustomobject]@{file=$name;bytes=$file.Length;lastWriteUtc=$file.LastWriteTimeUtc.ToString('o')}}
        }
    }
}
[pscustomobject]@{
    scope='Read-only guest freeze diagnosis; current resources are not historical proof; no changes or raw event messages'
    observedUtc=[DateTime]::UtcNow.ToString('o')
    lastBootUtc=$os.LastBootUpTime.ToUniversalTime().ToString('o')
    memory=[pscustomobject]@{totalPhysicalKiB=$os.TotalVisibleMemorySize;freePhysicalKiB=$os.FreePhysicalMemory;totalVirtualKiB=$os.TotalVirtualMemorySize;freeVirtualKiB=$os.FreeVirtualMemory}
    disk=[pscustomobject]@{sizeBytes=$disk.Size;freeBytes=$disk.FreeSpace}
    pageFiles=@(Get-CimInstance Win32_PageFileUsage|Select-Object AllocatedBaseSize,CurrentUsage,PeakUsage)
    operation=if($operation){$operation|Select-Object operationId,phase,step,checksPassed,backupReference}else{$null}
    applicationChangeStarted=if($context){$context.applicationChangeStarted}else{$null}
    services=$services;processes=$processes;partialBackupFiles=$partial;events=$events
}|ConvertTo-Json -Depth 7
