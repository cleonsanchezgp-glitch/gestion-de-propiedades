$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../deploy/windows/update/Backup.ps1')
$exe=Join-Path $PSHOME 'powershell.exe'
function Run-Encoded([string]$Code,[int]$Timeout=20000,[string]$InputText=''){
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
    Invoke-UpdateBoundedProcess $exe @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) $InputText $Timeout
}
if((Run-Encoded '[Console]::Out.Write("ok");[Console]::Error.Write("private-stderr")') -cne 'ok'){throw 'stderr leaked into stdout.'}
if((Run-Encoded '[Console]::Out.Write([Console]::In.ReadToEnd())' 20000 'input-sentinel') -cne 'input-sentinel'){throw 'stdin delivery failed.'}
if((Run-Encoded '[Console]::Out.Write([Console]::In.ReadToEnd().Length)') -cne '0'){throw 'empty stdin not closed.'}
$watch=[Diagnostics.Stopwatch]::StartNew();$timedOut=$false
try{Run-Encoded 'Start-Sleep -Seconds 60' 1000}catch{$timedOut=$_.Exception.Message -ceq 'Database maintenance command timed out.'}
if(-not $timedOut -or $watch.Elapsed.TotalSeconds -gt 15){throw 'Process timeout failed.'}
$rejected=$false
try{Run-Encoded '[Console]::Error.Write("synthetic-password");exit 3'}catch{$rejected=$true;if($_.Exception.Message -match 'synthetic-password'){throw 'stderr secret leaked.'}}
if(-not $rejected){throw 'Nonzero exit accepted.'}
$failed=$false
try{Invoke-UpdateBoundedProcess 'nonexistent-owned-test-command.exe' @() '' 1000}catch{$failed=$true}
if(-not $failed){throw 'Missing process accepted.'}
Write-Output '6 bounded-process checks PASS'
