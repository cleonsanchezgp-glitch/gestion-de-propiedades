. (Join-Path $PSScriptRoot '../../deploy/windows/update/Updater.ps1')
$root=Join-Path $PSScriptRoot ('../artifacts/updates/identity-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'config') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $root 'config/api.json'),'{"KeycloakPort":58082,"LoginSecret":"synthetic-secret"}')
$control=[pscustomobject]@{root=$root}
$script:readyAfter=0;$script:getCalls=0;$script:postCalls=0;$script:rejectPassword=$false;$script:wrongIssuer=$false
function Start-Sleep {param($Seconds)}
function Invoke-WebRequest {
    param([switch]$UseBasicParsing,$Method,$Uri,$Body,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    if($Method -ceq 'POST') {
        $script:postCalls++
        if($script:getCalls -le $script:readyAfter){throw 'Credentials submitted before ready.'}
        if($Body.username -cne 'prueba'){throw 'Windows domain leaked into Keycloak username.'}
        if($script:rejectPassword){$error=New-Object Exception('synthetic-private-error');$error|Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{StatusCode=401});throw $error}
        return [pscustomobject]@{StatusCode=200;Content='{"access_token":"synthetic-token"}'}
    }
    $script:getCalls++
    if($script:getCalls -le $script:readyAfter){throw 'Starting up.'}
    $issuer=if($script:wrongIssuer){'https://other.example/realms/propiedades'}else{'http://127.0.0.1:58082/realms/propiedades'}
    [pscustomobject]@{StatusCode=200;Content=(@{issuer=$issuer}|ConvertTo-Json -Compress)}
}
$script:checks=0
function Check($Name,[scriptblock]$Action){& $Action;$script:checks++;Write-Output ('PASS '+$Name)}
Check 'readiness retries without credentials' {$script:readyAfter=2;$script:getCalls=0;Wait-UpdateIdentity $control -Attempts 3 -DelaySeconds 0;if($script:getCalls -ne 3 -or $script:postCalls){throw 'Incorrect readiness behavior'}}
Check 'readiness timeout does not submit password' {$script:readyAfter=10;$script:getCalls=0;$failed=$false;try{Wait-UpdateIdentity $control -Attempts 2 -DelaySeconds 0}catch{$failed=$true};if(-not $failed -or $script:postCalls){throw 'Timeout not protected'}}
Check 'wrong issuer is not ready' {$script:readyAfter=0;$script:wrongIssuer=$true;$failed=$false;try{Wait-UpdateIdentity $control -Attempts 1 -DelaySeconds 0}catch{$failed=$true};if(-not $failed){throw 'Wrong issuer admitted'};$script:wrongIssuer=$false}
$credential=New-Object Management.Automation.PSCredential('VM\prueba',(ConvertTo-SecureString 'synthetic-password' -AsPlainText -Force))
Check 'Windows qualified username normalized for Keycloak' {$script:getCalls=0;$script:postCalls=0;if((Get-UpdateOwnerToken $control $credential) -cne 'synthetic-token' -or $script:postCalls -ne 1){throw 'Authentication failed'}}
Check 'wrong password not retried and private response omitted' {$script:rejectPassword=$true;$script:postCalls=0;$message='';try{$null=Get-UpdateOwnerToken $control $credential}catch{$message=$_.Exception.Message};if($script:postCalls -ne 1 -or $message -notmatch 'HTTP 401' -or $message -match 'synthetic-private-error|synthetic-password'){throw 'Authentication rejection incorrectly handled'}}
Write-Output ($script:checks.ToString()+' identity readiness checks PASS; mocked HTTP, not guest acceptance')
