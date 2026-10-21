[CmdletBinding()]
param([ValidateSet('Estado','Iniciar','Detener','Reiniciar')][string]$Accion='Estado')
. (Join-Path $PSScriptRoot 'Common.ps1')
$root = Split-Path $PSScriptRoot -Parent
$s = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config/settings.json') | ConvertFrom-Json
$ids = @('AeliumPostgres','AeliumKeycloak','AeliumAPI')
if (Get-Service -Name AeliumTunnel -ErrorAction SilentlyContinue) { $ids += 'AeliumTunnel' }
foreach ($id in $ids) {
    $service = Get-CimInstance Win32_Service -Filter ("Name='"+$id+"'")
    if (-not $service -or $service.PathName -notlike ('*'+(Join-Path $root ('services/'+$id+'.exe'))+'*')) { throw ('Missing service or different installation: '+$id) }
}
if ($Accion -in @('Detener','Reiniciar')) { for ($i=$ids.Count-1;$i -ge 0;$i--) { Stop-Service -Name $ids[$i] } }
if ($Accion -in @('Iniciar','Reiniciar')) {
    foreach ($id in $ids) { Start-Service -Name $id }
    Wait-Http ('http://127.0.0.1:'+$s.ApiPort+'/health/live') 180
}
Get-Service -Name $ids | Select-Object Name,Status,StartType
