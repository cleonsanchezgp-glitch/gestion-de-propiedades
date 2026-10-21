[CmdletBinding()]
param([string]$InstallationRoot='C:\ProgramData\Aelium\Propiedades')
$ErrorActionPreference='Stop'
$cookie='';$body='';$password='';$pointer=[IntPtr]::Zero;$api='';$settings=$null
try {
    . (Join-Path $InstallationRoot 'scripts/Common.ps1')
    $settings=Get-Content -LiteralPath (Join-Path $InstallationRoot 'config/settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not $settings.Complete) {throw 'Installation is incomplete.'}
    $api='http://127.0.0.1:'+([int]$settings.ApiPort)
    $secure=Read-Host 'Contrasena de pruebas del propietario (no se guarda)' -AsSecureString
    try {
        $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        $password=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        $body=@{username=$settings.Username;password=$password}|ConvertTo-Json -Compress
        $login=Invoke-LocalApi 'POST' ($api+'/api/v1/session/login') $settings.PortalOrigin $body
    } finally {
        if($pointer -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer);$pointer=[IntPtr]::Zero}
        $password='';$body='';$secure.Dispose()
    }
    if($login.Status -ne 200 -or $login.Cookies.Count -ne 1) {throw 'Owner login failed; no acceptance recorded.'}
    $cookie=($login.Cookies[0] -split ';')[0]
    if($login.Cookies[0] -notmatch 'HttpOnly' -or $login.Cookies[0] -notmatch 'Secure') {throw 'Expected cookie protections missing.'}
    $identity=Invoke-LocalApi 'GET' ($api+'/api/v1/me') '' '' $cookie
    if($identity.Status -ne 200 -or ($identity.Content|ConvertFrom-Json).sub -ne $settings.OwnerSubject) {throw 'Owner identity verification failed.'}
    $logout=Invoke-LocalApi 'POST' ($api+'/api/v1/session/logout') $settings.PortalOrigin '' $cookie
    $expired=Invoke-LocalApi 'GET' ($api+'/api/v1/me') '' '' $cookie
    if($logout.Status -ne 200 -or $expired.Status -ne 401) {throw 'Logout verification failed.'}
    $cookie=''
    [pscustomobject]@{scope='Local owner access after reboot; not portal or update acceptance';observedUtc=[DateTime]::UtcNow.ToString('o');login='PASS';ownerIdentity='PASS';cookieProtection='PASS';logout='PASS';closedSessionRejected='PASS'}|ConvertTo-Json
} catch {
    Write-Error 'Comprobacion de acceso fallida. Conservar la instalacion; no compartir contrasenas, cookies ni configuracion privada.'
    exit 1
} finally {
    if($cookie -and $api -and $settings){try{Invoke-LocalApi 'POST' ($api+'/api/v1/session/logout') $settings.PortalOrigin '' $cookie|Out-Null}catch{}}
    $cookie='';$body='';$password=''
}
