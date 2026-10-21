[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')
$root = Split-Path $PSScriptRoot -Parent
$s = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config/settings.json') | ConvertFrom-Json
$admin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run PowerShell as administrator.' }
if (Get-Service AeliumTunnel -ErrorAction SilentlyContinue) { throw 'Tunnel service already exists; do not replace its credentials.' }
$secure = Read-Host 'Token del tunel de Cloudflare (entrada oculta)' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
if ($token -notmatch '^[A-Za-z0-9+/=_-]{40,4096}$') { throw 'Invalid tunnel token.' }
$tokenFile = Join-Path $root 'config/tunnel-token.txt'
Write-Utf8 $tokenFile $token
& icacls.exe $tokenFile /grant '*S-1-5-19:R' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not grant tunnel service read access.' }
$args = 'tunnel --no-autoupdate run --token-file "'+$tokenFile+'"'
$xml = New-ServiceXml 'AeliumTunnel' (Join-Path $root 'bin/cloudflared.exe') $args $root @('AeliumAPI')
Copy-Item -LiteralPath (Join-Path $root 'services/AeliumAPI.exe') -Destination (Join-Path $root 'services/AeliumTunnel.exe')
Write-Utf8 (Join-Path $root 'services/AeliumTunnel.xml') $xml
& (Join-Path $root 'services/AeliumTunnel.exe') install
if ($LASTEXITCODE -ne 0) { throw 'Tunnel service installation failed.' }
Start-Service AeliumTunnel
Write-Host ('Tunel instalado. En Cloudflare, publique la API hacia http://127.0.0.1:'+$s.ApiPort+' y protejala con Access Service Auth. No publique PostgreSQL ni Keycloak.')
