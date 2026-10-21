. (Join-Path $PSScriptRoot 'Common.ps1')
$root = Split-Path $PSScriptRoot -Parent
$s = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config/keycloak.json') | ConvertFrom-Json
$env:JAVA_HOME = Join-Path $root 'java'
$env:KC_DB_PASSWORD = $s.KeycloakDbPassword
if ($s.PSObject.Properties.Name -contains 'AdminPassword') {
    $env:KC_BOOTSTRAP_ADMIN_USERNAME = 'admin'
    $env:KC_BOOTSTRAP_ADMIN_PASSWORD = $s.AdminPassword
} else {
    Remove-Item Env:KC_BOOTSTRAP_ADMIN_USERNAME,Env:KC_BOOTSTRAP_ADMIN_PASSWORD -ErrorAction SilentlyContinue
}
& (Join-Path $root 'keycloak/bin/kc.bat') start --optimized --import-realm
exit $LASTEXITCODE
