[CmdletBinding()]
param([string]$InstallationRoot='C:\ProgramData\Aelium\Propiedades')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($InstallationRoot).TrimEnd('\')
function Read-PrivateRecord([string]$Relative){
    $path=Join-Path $root $Relative
    if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json}
}
$operation=Read-PrivateRecord 'maintenance/operation.json'
$context=Read-PrivateRecord 'maintenance/context.json'
$failure=Read-PrivateRecord 'maintenance/recovery-failure.json'
$initial=Read-PrivateRecord 'maintenance/initial-failure.json'
$backupSummary=$null
if($operation -and $operation.operationId -cmatch '^update-[a-f0-9]{32}$' -and $operation.backupReference -ceq ('backups/'+$operation.operationId)){
    $backup=Read-PrivateRecord ($operation.backupReference+'/backup.private.json')
    $journal=Read-PrivateRecord ($operation.backupReference+'/recovery.private.json')
    if($backup){$backupSummary=[pscustomobject]@{format=$backup.format;verified=$backup.verified;databaseCount=@($backup.databases).Count;recoveryJournalVerified=if($journal){$journal.verified}else{$null};filesRestored=if($journal){$journal.filesRestored}else{$null}}}
}
$services=@(foreach($id in @('AeliumPostgres','AeliumKeycloak','AeliumAPI')){
    $s=Get-CimInstance Win32_Service -Filter ("Name='"+$id+"'")
    if($s){[pscustomobject]@{name=$s.Name;state=$s.State;startMode=$s.StartMode;account=$s.StartName;exitCode=$s.ExitCode;serviceSpecificExitCode=$s.ServiceSpecificExitCode}}
})
$logs=@(foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'logs') -File -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'Keycloak'}){
    $tail=@(Get-Content -LiteralPath $file.FullName -Tail 100 -ErrorAction SilentlyContinue)
    $categories=@(foreach($pattern in @('AccessDeniedException','Access is denied','Acceso denegado','Permission denied','password authentication failed','Connection refused','OutOfMemoryError','Address already in use','Failed to start','ERROR','FATAL')){
        if(@($tail|Where-Object{$_ -match [regex]::Escape($pattern)}).Count){$pattern}
    })
    [pscustomobject]@{file=$file.Name;bytes=$file.Length;lastWriteUtc=$file.LastWriteTimeUtc.ToString('o');categories=$categories}
})
$listeners=@(foreach($port in @(55434,58082,58090)){
    [pscustomobject]@{port=$port;listening=(@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count -gt 0)}
})
[pscustomobject]@{
    scope='Read-only recovery diagnosis; no service changes, credentials or raw logs'
    observedUtc=[DateTime]::UtcNow.ToString('o')
    operation=if($operation){$operation|Select-Object operationId,phase,step,checksPassed,backupReference}else{$null}
    applicationChangeStarted=if($context){$context.applicationChangeStarted}else{$null}
    initialFailure=if($initial -and $initial.operationId -ceq $operation.operationId){$initial|Select-Object operationId,failureStep,reasonCode,trace}else{$null}
    recoveryFailure=if($failure -and $failure.operationId -ceq $operation.operationId){$failure|Select-Object failureStep,reasonCode,trace}else{$null}
    backup=$backupSummary
    services=$services;listeners=$listeners;keycloakLogSummary=$logs
}|ConvertTo-Json -Depth 8
