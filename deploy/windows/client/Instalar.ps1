[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:ProgramData 'Aelium/Propiedades'),
    [string]$PortalOrigin = '',
    [switch]$Resume,
    [switch]$SmokeTest
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
if ($root -match '[&%"<>|]' -or $root -eq [IO.Path]::GetPathRoot($root).TrimEnd('\')) { throw 'Invalid installation directory.' }
if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { throw 'This package requires Windows x64 (Intel/AMD).' }
if ([Environment]::OSVersion.Version.Build -lt 19041) { throw 'Windows 10 version 2004 or later is required; update to 22H2.' }
$admin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and -not $SmokeTest) { throw 'Run Instalar.cmd as administrator (right click).' }
Assert-Package $PSScriptRoot
$rootExists=Test-Path -LiteralPath $root -PathType Container
if ($Resume -and -not $rootExists) { throw 'No existe una instalacion interrumpida que se pueda reanudar.' }
$initialInstall= -not $rootExists -or (-not $Resume -and @(Get-ChildItem -LiteralPath $root -Force).Count -eq 0)
$ids = @('AeliumPostgres','AeliumKeycloak','AeliumAPI')
if (-not $SmokeTest) {
    if ($initialInstall) {
        foreach ($id in @($ids + 'AeliumTunnel')) {
            $orphan=Get-CimInstance Win32_Service -Filter ("Name='"+$id+"'")
            if (-not $orphan) { continue }
            $expected=[IO.Path]::GetFullPath((Join-Path $root ('services/'+$id+'.exe')))
            $servicePath=$orphan.PathName.Trim()
            if ($servicePath -match '^"([^"]+)"(?:\s|$)') { $servicePath=$Matches[1] }
            if ($servicePath -ine $expected) { throw ('El servicio ' + $id + ' pertenece a otra ruta: ' + $orphan.PathName + '. No se retira automaticamente.') }
            if ($orphan.State -ne 'Stopped') { Stop-Service -Name $id -ErrorAction Stop }
            & sc.exe delete $id | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('No se pudo retirar el servicio antiguo ' + $id) }
            $deadline=[DateTime]::UtcNow.AddSeconds(30)
            while ((Get-Service -Name $id -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 500 }
            if (Get-Service -Name $id -ErrorAction SilentlyContinue) { throw ('El servicio antiguo ' + $id + ' sigue pendiente de eliminacion. Reinicie Windows antes de instalar.') }
        }
    }
    foreach ($id in $ids) {
        $existing = Get-CimInstance Win32_Service -Filter ("Name='" + $id + "'")
        if ($existing -and (-not $Resume -or $existing.PathName -notlike ('*' + (Join-Path $root ('services/' + $id + '.exe')) + '*'))) { throw ('Queda registrado el servicio ' + $id + ' (' + $existing.PathName + '). La instalacion limpia exige retirar primero los servicios de la instalacion anterior; no se borran automaticamente.') }
    }
}
$settingsPath = Join-Path $root 'config/settings.json'
if (-not $initialInstall) {
    if (-not $Resume -or -not (Test-Path -LiteralPath $settingsPath)) { throw 'La carpeta de instalacion ya existe. La instalacion limpia necesita una carpeta nueva y vacia. Use -Resume solo para reanudar una instalacion interrumpida.' }
    $s = Get-Content -Raw -Encoding UTF8 $settingsPath | ConvertFrom-Json
    if ($s.Complete) { throw 'Already installed. Use Administrar.ps1; reinstalling must not reset passwords or databases.' }
    if ($PortalOrigin -and $PortalOrigin -ne $s.PortalOrigin) { throw 'Resume must preserve the original portal origin.' }
} else {
    if ($SmokeTest) { $PortalOrigin = 'https://portal.example.test' }
    if (-not $PortalOrigin) { $PortalOrigin = Read-Host 'Origen HTTPS del portal (ejemplo https://propiedades.sudominio.es, sin / final)' }
    $uri = $null
    if (-not [Uri]::TryCreate($PortalOrigin,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.GetLeftPart([UriPartial]::Authority) -cne $PortalOrigin -or $uri.UserInfo) { throw 'Provide an exact HTTPS origin without trailing slash, credentials or path.' }
    $username = if ($SmokeTest) { 'installer-test' } else { Read-Host 'Usuario del propietario del portal' }
    if ($username -notmatch '^[a-zA-Z0-9._@-]{1,100}$') { throw 'Use 1-100 letters, numbers, dot, underscore, @ or hyphen for username.' }
    if ($SmokeTest) { $password = New-Secret } else {
        $secure = Read-Host 'Contrasena del propietario (minimo 12 caracteres)' -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        if ($password.Length -lt 12) { throw 'Password must contain at least 12 characters.' }
    }
    $s = [pscustomobject]@{Format=1;Complete=$false;PortalOrigin=$PortalOrigin;Username=$username;OwnerSubject=[Guid]::NewGuid().ToString();OwnerPassword=$password;LoginSecret=(New-Secret);PostgresPassword=(New-Secret);ApiDbPassword=(New-Secret);KeycloakDbPassword=(New-Secret);AdminPassword=(New-Secret);PgPort=55434;ApiPort=58090;KeycloakPort=58082;SmokeTest=[bool]$SmokeTest}
    if ($SmokeTest) { $s.PgPort=55435; $s.ApiPort=58092; $s.KeycloakPort=58084 }
    foreach ($port in @($s.PgPort,$s.ApiPort,$s.KeycloakPort)) {
        if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) { throw ('Port already in use: ' + $port) }
    }
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    # Locale independent SIDs. initdb's restricted token needs an explicit installer-user ACE.
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $root /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-19:(OI)(CI)RX' (('*' + $sid) + ':(OI)(CI)F') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not secure installation directory.' }
    New-Item -ItemType Directory -Path (Join-Path $root 'config') | Out-Null
    Write-Utf8 $settingsPath ($s | ConvertTo-Json -Depth 4)
}
if ($s.SmokeTest -ne [bool]$SmokeTest) { throw 'Cannot resume with a different installation mode.' }
if ($Resume -and -not $SmokeTest) {
    # Services from this interrupted installation were checked above. Stop in
    # dependency order before replacing their locked wrapper executables.
    for ($i=$ids.Count-1; $i -ge 0; $i--) {
        $existing = Get-Service -Name $ids[$i] -ErrorAction SilentlyContinue
        if ($existing -and $existing.Status -ne 'Stopped') { Stop-Service -Name $ids[$i] }
    }
}
$processes = New-Object Collections.Generic.List[int]
function Run-Native($Exe,$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('Command failed: ' + [IO.Path]::GetFileName($Exe) + '. Inspect private logs; databases have been preserved.') }
}
function Start-OwnedProcess($Exe,$Arguments,$Name) {
    $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root ('logs/' + $Name + '.out.log')) -RedirectStandardError (Join-Path $root ('logs/' + $Name + '.err.log'))
    $processes.Add($p.Id)
}
function Stop-OwnedTree($PidToStop) {
    $children = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $PidToStop) -ErrorAction SilentlyContinue)
    foreach ($child in $children) { Stop-OwnedTree $child.ProcessId }
    Stop-Process -Id $PidToStop -ErrorAction SilentlyContinue
}
function Install-Service($Id) {
    if (-not (Get-Service -Name $Id -ErrorAction SilentlyContinue)) { Run-Native (Join-Path $root ('services/' + $Id + '.exe')) @('install') }
    Start-Service -Name $Id
}
try {
    Write-Host 'Preparando componentes nativos...'
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe (Join-Path $root 'config') /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' (('*' + $sid) + ':(OI)(CI)F') '*S-1-5-19:RX' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict administrative configuration.' }
    & icacls.exe $settingsPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' (('*' + $sid) + ':F') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict installation secrets.' }
    $apiSettings = @{ApiDbPassword=$s.ApiDbPassword;ApiPort=$s.ApiPort;PgPort=$s.PgPort;KeycloakPort=$s.KeycloakPort;LoginSecret=$s.LoginSecret;PortalOrigin=$s.PortalOrigin;OwnerSubject=$s.OwnerSubject}
    Write-Utf8 (Join-Path $root 'config/api.json') ($apiSettings | ConvertTo-Json)
    Write-Utf8 (Join-Path $root 'config/keycloak.json') (@{KeycloakDbPassword=$s.KeycloakDbPassword;AdminPassword=$s.AdminPassword} | ConvertTo-Json)
    foreach ($file in @('api.json','keycloak.json')) {
        & icacls.exe (Join-Path $root ('config/'+$file)) /grant '*S-1-5-19:R' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not configure service credentials.' }
    }
    foreach ($folder in @('bin','scripts','services','logs','data','backups')) { New-Item -ItemType Directory -Force -Path (Join-Path $root $folder) | Out-Null }
    foreach ($folder in @('logs','data')) {
        & icacls.exe (Join-Path $root $folder) /grant '*S-1-5-19:(OI)(CI)M' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not configure service data permissions.' }
    }
    if (-not $SmokeTest) {
        $runtime = Join-Path $PSScriptRoot 'payload/vc_redist.x64.exe'
        $signature = Get-AuthenticodeSignature -LiteralPath $runtime
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'Invalid Microsoft runtime signature.' }
        $p = Start-Process -FilePath $runtime -ArgumentList '/install','/quiet','/norestart' -PassThru -Wait -WindowStyle Hidden
        if ($p.ExitCode -notin @(0,1638,3010)) { throw 'Microsoft VC++ runtime installation failed.' }
        if ($p.ExitCode -eq 3010) { Write-Host 'Windows solicita reinicio al terminar la instalacion.' }
    }
    Expand-Vendor (Join-Path $PSScriptRoot 'payload/postgresql.zip') (Join-Path $root 'postgresql') 'bin/postgres.exe'
    Expand-Vendor (Join-Path $PSScriptRoot 'payload/java.zip') (Join-Path $root 'java') 'bin/java.exe'
    Expand-Vendor (Join-Path $PSScriptRoot 'payload/keycloak.zip') (Join-Path $root 'keycloak') 'bin/kc.bat'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'payload/propiedades-backend.exe') -Destination (Join-Path $root 'bin/propiedades-backend.exe')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'payload/cloudflared.exe') -Destination (Join-Path $root 'bin/cloudflared.exe')
    Copy-Item -Path (Join-Path $PSScriptRoot '*.ps1') -Destination (Join-Path $root 'scripts')
    $pg = Join-Path $root 'postgresql/bin'
    $data = Join-Path $root 'data/postgres'
    if (-not (Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))) {
        $pwfile = Join-Path $root 'config/initdb-password.txt'
        Write-Utf8 $pwfile ($s.PostgresPassword + "`n")
        try { Run-Native (Join-Path $pg 'initdb.exe') @('-D',$data,'-U','postgres','--encoding=UTF8','--locale=C','--auth=scram-sha-256',('--pwfile=' + $pwfile)) } finally { Remove-Item -LiteralPath $pwfile -ErrorAction SilentlyContinue }
        Write-Utf8 (Join-Path $data 'postgresql.auto.conf') ("listen_addresses = '127.0.0.1'`nport = " + $s.PgPort + "`npassword_encryption = 'scram-sha-256'`n")
    }
    $powerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $pgArgs = '-D "' + $data + '"'
    $apiArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'scripts/run-api.ps1') + '"'
    $kcArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'scripts/run-keycloak.ps1') + '"'
    $pgXml = New-ServiceXml 'AeliumPostgres' (Join-Path $pg 'postgres.exe') $pgArgs $root @() (Join-Path $pg 'pg_ctl.exe') ('stop -D "' + $data + '" -m fast -w -t 45')
    $kcXml = New-ServiceXml 'AeliumKeycloak' $powerShell $kcArgs $root @('AeliumPostgres')
    $apiXml = New-ServiceXml 'AeliumAPI' $powerShell $apiArgs $root @('AeliumPostgres','AeliumKeycloak')
    foreach ($entry in @(@('AeliumPostgres',$pgXml),@('AeliumKeycloak',$kcXml),@('AeliumAPI',$apiXml))) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'payload/winsw.exe') -Destination (Join-Path $root ('services/' + $entry[0] + '.exe'))
        Write-Utf8 (Join-Path $root ('services/' + $entry[0] + '.xml')) $entry[1]
    }
    if ($SmokeTest) { Start-OwnedProcess (Join-Path $pg 'postgres.exe') $pgArgs 'postgres' } else { Install-Service 'AeliumPostgres' }
    $until = [DateTime]::UtcNow.AddSeconds(60)
    do { & (Join-Path $pg 'pg_isready.exe') -h 127.0.0.1 -p $s.PgPort -q; if ($LASTEXITCODE -eq 0) { break }; Start-Sleep -Seconds 1 } while ([DateTime]::UtcNow -lt $until)
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL did not start.' }
    # Secrets go in a private SQL file; never in process arguments or console output.
    $sql = @"
SELECT 'CREATE ROLE propiedades LOGIN PASSWORD ''$($s.ApiDbPassword)''' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='propiedades') \gexec
SELECT 'CREATE ROLE keycloak LOGIN PASSWORD ''$($s.KeycloakDbPassword)''' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='keycloak') \gexec
SELECT 'CREATE DATABASE propiedades OWNER propiedades' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='propiedades') \gexec
SELECT 'CREATE DATABASE keycloak OWNER keycloak' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='keycloak') \gexec
"@
    $sqlPath = Join-Path $root 'config/setup.sql'
    Write-Utf8 $sqlPath $sql
    $env:PGPASSWORD = $s.PostgresPassword
    try { Run-Native (Join-Path $pg 'psql.exe') @('-h','127.0.0.1','-p',[string]$s.PgPort,'-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-f',$sqlPath) } finally { Remove-Item Env:PGPASSWORD; Remove-Item -LiteralPath $sqlPath -ErrorAction SilentlyContinue }
    $kcRoot = Join-Path $root 'keycloak'
    $env:JAVA_HOME = Join-Path $root 'java'
    Write-Utf8 (Join-Path $kcRoot 'conf/keycloak.conf') ("db=postgres`ndb-url=jdbc:postgresql://127.0.0.1:" + $s.PgPort + "/keycloak`ndb-username=keycloak`nhttp-enabled=true`nhttp-host=127.0.0.1`nhttp-port=" + $s.KeycloakPort + "`nhostname=http://127.0.0.1:" + $s.KeycloakPort + "`n")
    # Service can write only its own runtime subtree, not API executables or configuration.
    & icacls.exe $kcRoot /grant '*S-1-5-19:(OI)(CI)M' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure Keycloak runtime permissions.' }
    Run-Native (Join-Path $kcRoot 'bin/kc.bat') @('build','--db=postgres')
    $importDir = Join-Path $kcRoot 'data/import'
    New-Item -ItemType Directory -Force $importDir | Out-Null
    $realmPath = Join-Path $importDir 'propiedades-realm.json'
    Write-Utf8 $realmPath ((New-Realm $s) | ConvertTo-Json -Depth 12)
    if ($SmokeTest) { Start-OwnedProcess $powerShell $kcArgs 'keycloak' } else { Install-Service 'AeliumKeycloak' }
    Wait-Http ('http://127.0.0.1:' + $s.KeycloakPort + '/realms/propiedades/.well-known/openid-configuration') 180
    # Initial database preparation is explicit; normal service startup never migrates.
    $previousDatabase=$env:DATABASE_URL
    try {
        $env:DATABASE_URL='postgres://propiedades:'+[Uri]::EscapeDataString($s.ApiDbPassword)+'@127.0.0.1:'+$s.PgPort+'/propiedades'
        Run-Native (Join-Path $root 'bin/propiedades-backend.exe') @('--migrate-only','--bootstrap','--install-root',$root)
    } finally {$env:DATABASE_URL=$previousDatabase}
    if ($SmokeTest) { Start-OwnedProcess $powerShell $apiArgs 'api' } else { Install-Service 'AeliumAPI' }
    $api = 'http://127.0.0.1:' + $s.ApiPort
    Wait-Http ($api + '/health/live') 90
    $body = @{username=$s.Username;password=$s.OwnerPassword} | ConvertTo-Json -Compress
    $login = Invoke-LocalApi 'POST' ($api + '/api/v1/session/login') $s.PortalOrigin $body
    if ($login.Status -ne 200 -or $login.Cookies.Count -ne 1 -or $login.Cookies[0] -notmatch 'HttpOnly' -or $login.Cookies[0] -notmatch 'Secure') { throw 'Portal login validation failed.' }
    # HTTPS production cookie cannot be replayed on local HTTP by a browser. Test manually.
    $cookie = ($login.Cookies[0] -split ';')[0]
    $identity = Invoke-LocalApi 'GET' ($api + '/api/v1/me') '' '' $cookie
    if ($identity.Status -ne 200) { throw 'Session validation failed.' }
    $me = $identity.Content | ConvertFrom-Json
    if ($me.sub -ne $s.OwnerSubject) { throw 'Owner identity validation failed.' }
    $logout = Invoke-LocalApi 'POST' ($api + '/api/v1/session/logout') $s.PortalOrigin '' $cookie
    if ($logout.Status -ne 200) { throw 'Logout validation failed.' }
    $expired = Invoke-LocalApi 'GET' ($api + '/api/v1/me') '' '' $cookie
    if ($expired.Status -ne 401) { throw 'Logout must invalidate the previous session.' }
    Remove-Item -LiteralPath $realmPath
    $s.OwnerPassword = ''
    $s.Complete = $true
    Write-Utf8 $settingsPath ($s | ConvertTo-Json -Depth 4)
    Write-Utf8 (Join-Path $root 'config/keycloak.json') (@{KeycloakDbPassword=$s.KeycloakDbPassword} | ConvertTo-Json)
    Write-Utf8 (Join-Path $root 'config/RECUPERACION.txt') ("Cuenta administrativa Keycloak (solo local)`r`nURL: http://127.0.0.1:" + $s.KeycloakPort + "/admin`r`nUsuario: admin`r`nContrasena: " + $s.AdminPassword + "`r`nUsuario del portal: " + $s.Username + "`r`nPortal: " + $s.PortalOrigin + "`r`n")
    # Recovery is for administrators, not the LocalService account.
    & icacls.exe (Join-Path $root 'config/RECUPERACION.txt') /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not secure recovery information.' }
    if ($SmokeTest) {
        & (Join-Path $root 'scripts/Copia-Seguridad.ps1')
        $evidence = @{passed=$true;timeUtc=[DateTime]::UtcNow.ToString('o');osBuild=[Environment]::OSVersion.Version.ToString();servicesRegistered=$false;checks=@('postgres-init','keycloak-realm','api-migrations','owner-login','secure-cookie','owner-identity','logout','backup-two-databases')}
        Write-Utf8 (Join-Path $root 'smoke-result.json') ($evidence | ConvertTo-Json -Depth 4)
    }
    Write-Host 'Instalacion validada: PostgreSQL, Keycloak, API y acceso del propietario.'
    Write-Host ('Directorio: ' + $root)
    if (-not $SmokeTest) { Write-Host 'Falta conectar el tunel de Cloudflare y comprobar el portal publicado. Consulte LEEME.md.' }
} catch {
    Write-Host 'La instalacion se ha detenido. Los datos se conservan; no borre el directorio. Puede revisar logs y reanudar con -Resume.'
    throw
} finally {
    if ($SmokeTest) {
        for ($i=$processes.Count-1; $i -ge 0; $i--) {
            if ($i -eq 0 -and (Test-Path -LiteralPath (Join-Path $root 'postgresql/bin/pg_ctl.exe'))) {
                & (Join-Path $root 'postgresql/bin/pg_ctl.exe') stop -D (Join-Path $root 'data/postgres') -m fast -w -t 30 | Out-Null
            }
            Stop-OwnedTree $processes[$i]
        }
    }
}
