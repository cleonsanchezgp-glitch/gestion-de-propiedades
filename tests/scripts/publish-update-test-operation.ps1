param([Parameter(Mandatory=$true)][string]$InstallationRoot,[Parameter(Mandatory=$true)][string]$RecordPath)
. (Join-Path $PSScriptRoot '../../deploy/windows/update/Control.ps1')
$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts/updates')).TrimEnd('\')+'\'
if (-not [IO.Path]::GetFullPath($InstallationRoot).StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) {throw 'This publisher is only for isolated test roots.'}
$control=Open-UpdateControl $InstallationRoot
try {Set-UpdateOperation $control (Read-UpdateJson $RecordPath)}finally{$control.lock.Dispose()}
