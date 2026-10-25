[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot 'Actualizar.ps1'
if(-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'state/current.json'))){throw 'Instale y compruebe primero la aplicacion.'}
$name='Aelium-Propiedades-Actualizar-Docker'
$command='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$script+'" -Action Update'
$taskAction=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $command -WorkingDirectory $PSScriptRoot
$start=(Get-Date).AddMinutes(5)
$trigger=New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Hours 1)
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$logon=New-ScheduledTaskTrigger -AtLogOn -User $identity
$principal=New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $name -Action $taskAction -Trigger @($trigger,$logon) -Principal $principal -Settings $settings -Force | Out-Null
Write-Host ('Tarea '+$name+' creada para la sesion actual. Proxima comprobacion: '+$start)
