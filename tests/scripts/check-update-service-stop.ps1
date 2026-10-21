. (Join-Path $PSScriptRoot '../../deploy/windows/update/Control.ps1')
function Service([string]$Status,[switch]$Unresponsive){
    $service=[pscustomobject]@{Status=$Status;Requests=0;Waits=0;Limit=0;Unresponsive=[bool]$Unresponsive;DependentServices=@()}
    $service|Add-Member ScriptMethod Refresh {}
    $service|Add-Member ScriptMethod Stop {$this.Requests++;$this.Status='StopPending'}
    $service|Add-Member ScriptMethod WaitForStatus {param($Status,$Timeout);$this.Waits++;$this.Limit=$Timeout.TotalSeconds;if($this.Unresponsive){throw [TimeoutException]::new('Synthetic service remained pending.')};$this.Status=$Status}
    return $service
}
$stopped=Service 'Stopped';Stop-UpdateWriterService $stopped
if($stopped.Requests -or $stopped.Waits){throw 'Stopped service was unnecessarily controlled.'}
$running=Service 'Running';Stop-UpdateWriterService $running
if($running.Requests -ne 1 -or $running.Status -ne 'Stopped' -or $running.Limit -ne 90){throw 'Running service did not get one bounded stop.'}
$pending=Service 'StopPending';Stop-UpdateWriterService $pending
if($pending.Requests -ne 0 -or $pending.Waits -ne 1){throw 'A pending stop was reissued.'}
$hung=Service 'Running' -Unresponsive;$failed=$false
try{Stop-UpdateWriterService $hung -TimeoutSeconds 1}catch{$failed=$true}
if(-not $failed -or $hung.Status -ne 'StopPending' -or $hung.Limit -ne 1){throw 'Unconfirmed service stop was accepted.'}
$foreign=Service 'Running';$foreign.DependentServices=@([pscustomobject]@{Status='Running'});$refused=$false
try{Stop-UpdateWriterService $foreign}catch{$refused=$true}
if(-not $refused -or $foreign.Requests){throw 'Stop could recursively affect a dependent service.'}
Write-Output '5 bounded service-stop scenarios PASS (simulated service controller; no SCM changes)'
