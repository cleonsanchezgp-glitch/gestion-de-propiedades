[CmdletBinding()]
param([string]$OutputDirectory)
if (-not $OutputDirectory) {$OutputDirectory=Join-Path $PSScriptRoot '../../tests/artifacts/maintenance-delivery'}
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$files=@('Actualizar.ps1','Build-UpdatePackage.ps1','Recuperar-Ensayo-Local.ps1','Comprobar-Copia-Ensayo-Local.ps1','update/Updater.ps1','update/Backup.ps1','update/Control.ps1','update/Package.ps1','update/NativeServices.cs','update/run-api.ps1','update/manifest.schema.json','update/USO.md','update/README.md','update/STARTUP.md','update/ENSAYO-LOCAL.md')
$output=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force|Out-Null
$archive=Join-Path $output ('aelium-maintenance-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'.zip')
$stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew)
$zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try {foreach($relative in $files){$source=Join-Path $PSScriptRoot $relative;if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw 'Missing maintenance source.'};[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$source,$relative,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$zip.Dispose();$stream.Dispose()}
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($archive+'.sha256',$hash+'  '+[IO.Path]::GetFileName($archive),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{status='MaintenanceBundleCreated';archive=$archive;sha256=$hash;clientAccepted=$false}|ConvertTo-Json -Compress
