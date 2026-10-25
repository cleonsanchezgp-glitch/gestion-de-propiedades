. (Join-Path $PSScriptRoot 'Common.ps1')
$root = Split-Path $PSScriptRoot -Parent
$s = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config/api.json') | ConvertFrom-Json
$env:DATABASE_URL = 'postgres://propiedades:' + $s.ApiDbPassword + '@127.0.0.1:' + $s.PgPort + '/propiedades'
$env:BACKEND_BIND = '127.0.0.1:' + $s.ApiPort
$env:KEYCLOAK_ISSUER = 'http://127.0.0.1:' + $s.KeycloakPort + '/realms/propiedades'
$env:KEYCLOAK_AUDIENCE = 'propiedades-api'
$env:KEYCLOAK_ALLOWED_SUBJECT = $s.OwnerSubject
$env:KEYCLOAK_ACCESS_MODE = 'realm-users'
$env:KEYCLOAK_LOGIN_CLIENT_ID = 'portal-login'
$env:KEYCLOAK_LOGIN_CLIENT_SECRET = $s.LoginSecret
$env:PORTAL_ORIGIN = $s.PortalOrigin
Wait-Http ($env:KEYCLOAK_ISSUER + '/.well-known/openid-configuration') 180
& (Join-Path $root 'bin/propiedades-backend.exe') --serve --no-migrate --initial-layout --install-root $root
exit $LASTEXITCODE
