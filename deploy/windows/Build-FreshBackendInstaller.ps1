[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [string]$CompilerPath,
    [string]$OutputDirectory
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(-not $CompilerPath){$CompilerPath=Join-Path $repo 'deploy/tools/inno/ISCC.exe'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $repo 'deploy/artifacts/backend-fresh-installer-20261023-r4/PROMALZA'}
$package=[IO.Path]::GetFullPath($PackageDirectory).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not (Test-Path -LiteralPath (Join-Path $package 'manifest.json') -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $package 'Instalar.ps1') -PathType Leaf)) {throw 'An initial-install package directory is required.'}
. (Join-Path $PSScriptRoot 'client/Common.ps1')
Assert-Package $package
$manifest=Get-Content -Raw -Encoding UTF8 (Join-Path $package 'manifest.json')|ConvertFrom-Json
if(@($manifest.files|Where-Object {$_.path -cin @('payload/propiedades-backend.exe','payload/postgresql.zip','payload/keycloak.zip','payload/java.zip','payload/winsw.exe','payload/cloudflared.exe','payload/vc_redist.x64.exe','Instalar.ps1','Common.ps1','run-api.ps1','run-keycloak.ps1')}).Count -ne 11){throw 'The initial-install package is incomplete.'}
$signature=Get-AuthenticodeSignature -LiteralPath $CompilerPath
if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Pyrsys B.V.'){throw 'The official signed Inno Setup compiler is required.'}
New-Item -ItemType Directory -Force -Path $output|Out-Null
& $CompilerPath ('/DPackage='+$package) ('/DDelivery='+$output) (Join-Path $PSScriptRoot 'installer/FreshBackend.iss')
if($LASTEXITCODE -ne 0){throw 'Fresh installer compilation failed.'}
$filename='Instalar-Promalza-Desde-Cero.exe'
$exe=Join-Path $output $filename
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($exe+'.sha256'),($hash+'  '+$filename),(New-Object Text.UTF8Encoding($false)))
[IO.File]::Copy((Join-Path $PSScriptRoot 'installer/Guia-instalacion-PROMALZA-cliente.pdf'),(Join-Path $output 'Guia-instalacion-PROMALZA-cliente.pdf'),$true)
[pscustomobject]@{format=1;executable=$exe;sha256=$hash;releaseId=$manifest.releaseId;buildId=$manifest.buildId;compilerSignature='Valid';installerSignature=(Get-AuthenticodeSignature -LiteralPath $exe).Status.ToString();clientAccepted=$false}|ConvertTo-Json
