[CmdletBinding()]
param([switch]$SkipBuild,[switch]$SkipArchive,[string]$ReleaseId,[string]$BuildId)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$cache = Join-Path $PSScriptRoot '.cache'
$output = Join-Path $repo ('deploy/artifacts/backend-windows-x64-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $cache,$output,(Join-Path $output 'payload') | Out-Null
if (-not $SkipBuild) {
    if (-not $ReleaseId -or -not $BuildId) {throw 'Provide explicit -ReleaseId and -BuildId for a production build.'}
    $oldFlags = $env:RUSTFLAGS
    $oldRelease=$env:AELIUM_RELEASE_ID;$oldBuild=$env:AELIUM_BUILD_ID
    try {
        $env:RUSTFLAGS = '-C target-feature=+crt-static'
        $env:AELIUM_RELEASE_ID=$ReleaseId;$env:AELIUM_BUILD_ID=$BuildId
        & cargo build --locked --release --target x86_64-pc-windows-msvc --manifest-path (Join-Path $repo 'backend/Cargo.toml')
        if ($LASTEXITCODE -ne 0) { throw 'API build failed.' }
    } finally { $env:RUSTFLAGS = $oldFlags;$env:AELIUM_RELEASE_ID=$oldRelease;$env:AELIUM_BUILD_ID=$oldBuild }
}
$binary = Join-Path $repo 'backend/target/x86_64-pc-windows-msvc/release/propiedades-backend.exe'
if (-not (Test-Path -LiteralPath $binary)) { throw 'Compile the Windows release API first.' }
$releaseInfo=& $binary --release-info
if ($LASTEXITCODE -ne 0) {throw 'Executable must support release-info.'}
$releaseInfo=$releaseInfo|ConvertFrom-Json
if ($ReleaseId -and $releaseInfo.releaseId -cne $ReleaseId) {throw 'Compiled release identity differs.'}
if ($BuildId -and $releaseInfo.buildId -cne $BuildId) {throw 'Compiled build identity differs.'}
Copy-Item -LiteralPath $binary -Destination (Join-Path $output 'payload/propiedades-backend.exe')
$dependencies = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'dependencies.json') | ConvertFrom-Json
foreach ($dependency in $dependencies) {
    $cached = Join-Path $cache $dependency.file
    if (-not (Test-Path -LiteralPath $cached)) {
        Write-Host ('Downloading ' + $dependency.file + ' (' + $dependency.version + ')')
        $partial = $cached + '.partial'
        Invoke-WebRequest -UseBasicParsing -Uri $dependency.url -OutFile $partial
        Move-Item -LiteralPath $partial -Destination $cached
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $cached).Hash.ToLowerInvariant()
    if ($dependency.PSObject.Properties.Name -contains 'sha256' -and $dependency.sha256 -ne $hash) { throw ('Checksum mismatch: ' + $dependency.file) }
    if ($dependency.file -eq 'vc_redist.x64.exe') {
        $signature = Get-AuthenticodeSignature -LiteralPath $cached
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'Invalid Microsoft runtime signature.' }
    }
    Copy-Item -LiteralPath $cached -Destination (Join-Path $output ('payload/' + $dependency.file))
}
Copy-Item -Path (Join-Path $PSScriptRoot 'client/*') -Destination $output -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $output 'LEEME.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'VALIDACION.md') -Destination (Join-Path $output 'VALIDACION.md')
New-Item -ItemType Directory -Path (Join-Path $output 'licenses') | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/winsw/winsw/v2.12.0/LICENSE.txt -OutFile (Join-Path $output 'licenses/WinSW-LICENSE.txt')
Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/cloudflare/cloudflared/2026.10.0/LICENSE -OutFile (Join-Path $output 'licenses/cloudflared-LICENSE.txt')
$files = Get-ChildItem -LiteralPath $output -File -Recurse | ForEach-Object {
    @{path=$_.FullName.Substring($output.Length + 1).Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()}
}
@{format=1;createdUtc=[DateTime]::UtcNow.ToString('o');platform='windows-x64';releaseId=$releaseInfo.releaseId;buildId=$releaseInfo.buildId;apiContract=$releaseInfo.apiContract;migrations=$releaseInfo.migrations;dependencies=$dependencies;files=@($files)} | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $output 'manifest.json')
if ($SkipArchive) { Write-Host ('Package directory: ' + $output); return }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = $output + '.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($output,$archive,[IO.Compression.CompressionLevel]::Fastest,$false)
$zipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
($zipHash + '  ' + [IO.Path]::GetFileName($archive)) | Set-Content -Encoding ASCII ($archive + '.sha256')
Write-Host ('Package: ' + $archive)
Write-Host ('SHA256: ' + $zipHash)
