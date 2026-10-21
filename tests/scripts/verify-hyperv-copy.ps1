$ErrorActionPreference='Stop'
$root='C:\ProgramData\Aelium\Propiedades'
$computer=Get-CimInstance Win32_ComputerSystem
if($computer.Manufacturer -cne 'Microsoft Corporation' -or $computer.Model -cne 'Virtual Machine'){throw 'Este diagnostico requiere la copia de pruebas en Hyper-V.'}
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Abrir PowerShell como administrador dentro de la copia.'}
$marker=Get-Content -LiteralPath (Join-Path $root 'config/local-rehearsal.json') -Raw -Encoding UTF8|ConvertFrom-Json
$settings=Get-Content -LiteralPath (Join-Path $root 'config/settings.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($marker.format -ne 1 -or $marker.purpose -cne 'isolated-vm-update-rehearsal' -or $marker.installationRoot.TrimEnd('\') -cne $root -or $settings.Username -cne 'prueba' -or -not $settings.Complete){throw 'No coincide con la instalacion sintetica de pruebas.'}
$services=@(Get-Service AeliumPostgres,AeliumKeycloak,AeliumAPI|ForEach-Object{[pscustomobject]@{Name=$_.Name;Status=[string]$_.Status;StartType=[string]$_.StartType}})
$operation=Get-Content -LiteralPath (Join-Path $root 'maintenance/operation.json') -Raw -Encoding UTF8|ConvertFrom-Json
[pscustomobject]@{scope='Hyper-V cloned baseline, before repeating any backup';observedUtc=[DateTime]::UtcNow.ToString('o');services=$services;operation=($operation|Select-Object operationId,phase,checksPassed);updateSucceeded=$false;productionAccepted=$false}|ConvertTo-Json -Depth 6
if($operation.phase -cne 'Recovered' -or -not $operation.checksPassed -or @($services|Where-Object{$_.Status -ne 'Running' -or $_.StartType -ne 'Automatic'}).Count){throw 'No repetir la copia: primero diagnosticar servicios y operacion.'}
Write-Host 'Comprobando acceso local con el propietario sintetico. No se aplica ninguna actualizacion.'
& (Join-Path $PSScriptRoot 'Comprobar-Acceso.ps1')
