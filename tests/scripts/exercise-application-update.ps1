[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$InputPath)
. (Join-Path $PSScriptRoot '../../deploy/windows/update/Updater.ps1')
$fixtureConfig=Read-UpdateJson $InputPath
$root=[IO.Path]::GetFullPath($fixtureConfig.installationRoot).TrimEnd('\')
if (-not (Test-UpdateFixtureRoot $root)) {throw 'Fixture root outside update artifacts.'}
# ONLY this fixture wrapper replaces the administrator check: no SCM function
# is invoked. Production Actualizar.ps1 always enforces native administration.
function Assert-ControlAdministrator {if (-not (Test-UpdateFixtureRoot $root)) {throw 'Fixture administrator seam outside owned root.'}}
function Invoke-FixtureLifecycle($Control,[string]$Action) {
    $id=[Guid]::NewGuid().ToString('N');$request=Join-Path $Control.root 'maintenance/fixture-request.json'
    Write-PrivateUpdateJson $request ([pscustomobject]@{id=$id;action=$Action})
    $ack=Join-Path $Control.root 'maintenance/fixture-ack.json'
    for ($i=0;$i -lt 400;$i++) {
        $value=$null
        if (Test-Path -LiteralPath $ack) {try{$value=Read-UpdateJson $ack}catch{}}
        if ($null -ne $value -and $value.id -ceq $id) {if ($value.status -cne 'ready') {throw 'Fixture lifecycle failed.'};return}
        Start-Sleep -Milliseconds 50
    }
    throw 'Fixture lifecycle acknowledgment timed out.'
}
$hooks=[pscustomobject]@{start={param($Control) Invoke-FixtureLifecycle $Control 'start'};stop={param($Control) Invoke-FixtureLifecycle $Control 'stop'}}
$secure=ConvertTo-SecureString 'fixture-owner-password' -AsPlainText -Force
$credential=New-Object Management.Automation.PSCredential('fixture-owner',$secure)
try {
    $local=$fixtureConfig.PSObject.Properties['localRehearsal'] -and $fixtureConfig.localRehearsal -eq $true
    $result=Invoke-ApplicationUpdate $root $fixtureConfig.action $fixtureConfig.archive $fixtureConfig.expectedSha256 $fixtureConfig.catalog $fixtureConfig.observation $fixtureConfig.inventory $fixtureConfig.verificationPort $credential $hooks -LocalRehearsal:$local
    $result | ConvertTo-Json -Compress
}catch {Write-Host $_.ScriptStackTrace;throw}
