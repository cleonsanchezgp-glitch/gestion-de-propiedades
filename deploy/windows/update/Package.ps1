# Native Windows PowerShell 5.1 tooling. This file never stops services or applies updates.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function ConvertFrom-UpdateJson([string]$Text) {
    # ConvertFrom-Json alone accepts repeated keys on Windows PowerShell 5.1.
    # Reject aliases before deserialization; JSON syntax is then checked by the parser.
    $stack = New-Object Collections.Generic.List[object]
    foreach ($token in [regex]::Matches($Text, '"(?:[^"\\]|\\.)*"|[{}\[\],:]|[^\s{}\[\],:]+')) {
        $value = $token.Value
        if ($value -in @('{','[')) { $stack.Add(@{kind=$value;key=$true;names=@{}}); continue }
        if ($value -in @('}',']')) { if ($stack.Count) { $stack.RemoveAt($stack.Count-1) }; continue }
        if (-not $stack.Count) { continue }
        $frame = $stack[$stack.Count-1]
        if ($value -eq ',') { $frame.key=$true; continue }
        if ($frame.kind -eq '{' -and $frame.key -and $value.StartsWith('"')) {
            $name = $value | ConvertFrom-Json -ErrorAction Stop
            if ($frame.names.ContainsKey($name)) { throw 'Duplicate or case-aliased JSON key.' }
            $frame.names[$name]=$true; $frame.key=$false
        }
    }
    $Text | ConvertFrom-Json -ErrorAction Stop
}
function Read-UpdateJson([string]$Path) {
    try {
        Assert-NoReparse $Path
        if ((Get-Item -LiteralPath $Path -Force).Length -gt 4194304) { throw 'JSON document too large.' }
        ConvertFrom-UpdateJson (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    }
    catch { throw 'Invalid or unreadable JSON document.' }
}
function Assert-Fields($Object, [string[]]$Names) {
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) { throw 'Expected JSON object.' }
    $actual = @($Object.PSObject.Properties.Name)
    if (@($actual | Where-Object { $_ -cnotin $Names }).Count -or @($Names | Where-Object { $_ -cnotin $actual }).Count) {
        throw 'Unknown or missing JSON fields.'
    }
}
function Assert-UpdateId($Value) {
    if ($Value -isnot [string] -or $Value -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$') { throw 'Invalid identifier.' }
}
function Assert-UpdateHash($Value, [int]$Length = 64) {
    if ($Value -isnot [string] -or $Value -cnotmatch ('^[a-f0-9]{' + $Length + '}$')) { throw 'Invalid checksum.' }
}
function Assert-UpdatePath($Value) {
    if ($Value -isnot [string] -or $Value.Length -gt 200 -or $Value -cnotmatch '^[a-zA-Z0-9_./-]+$') { throw 'Unsafe relative path.' }
    foreach ($segment in $Value.Split('/')) {
        if (-not $segment -or $segment -in @('.', '..') -or $segment.EndsWith('.') -or $segment -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])($|\.)') { throw 'Unsafe Windows path segment.' }
    }
}
function Assert-NoReparse([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not allowed.' }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
function Get-UpdateFileHash([string]$Path) {
    Assert-NoReparse $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Required file missing.' }
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Get-UpdateStreamHash($Stream, [long]$ExpectedLength) {
    $sha = [Security.Cryptography.SHA256]::Create(); $buffer = New-Object byte[] 65536; $count = [long]0
    try {
        while (($read = $Stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $count += $read
            if ($count -gt $ExpectedLength) { throw 'ZIP stream exceeds declared size.' }
            $null = $sha.TransformBlock($buffer,0,$read,$buffer,0)
        }
        if ($count -ne $ExpectedLength) { throw 'ZIP stream is shorter than declared size.' }
        $null = $sha.TransformFinalBlock((New-Object byte[] 0),0,0)
        [BitConverter]::ToString($sha.Hash).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
function Read-UpdateEntryJson($Entry) {
    if ($Entry.Length -gt 1048576 -or $Entry.Length -le 0) { throw 'Manifest exceeds size limit.' }
    $stream=$Entry.Open(); $memory=New-Object IO.MemoryStream; $buffer=New-Object byte[] 65536
    try {
        while (($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            if ($memory.Length + $read -gt $Entry.Length) { throw 'Manifest stream exceeds declared size.' }
            $memory.Write($buffer,0,$read)
        }
        if ($memory.Length -ne $Entry.Length) { throw 'Truncated manifest stream.' }
        ConvertFrom-UpdateJson ([Text.Encoding]::UTF8.GetString($memory.ToArray()).TrimStart([char]0xfeff))
    } finally { $memory.Dispose(); $stream.Dispose() }
}
function Assert-UpdateList($Items) {
    if ($Items -isnot [array] -or $Items.Count -eq 0) { throw 'Expected nonempty JSON array.' }
}
function Assert-MigrationHistory($Items, [switch]$Observed) {
    if ($Items -isnot [array]) { throw 'Expected migration array.' }
    $seen = @{}
    foreach ($item in $Items) {
        if ($Observed) { Assert-Fields $item @('version','checksum','success'); if ($item.success -isnot [bool] -or -not $item.success) { throw 'Failed migration in history.' } }
        else { Assert-Fields $item @('version','checksum') }
        if ($item.version -isnot [string] -or $item.version -cnotmatch '^[1-9][0-9]{0,17}$' -or $seen.ContainsKey($item.version)) { throw 'Invalid or duplicate migration version.' }
        Assert-UpdateHash $item.checksum 96
        $seen[$item.version] = $true
    }
}
function Test-MigrationEquality($Left,$Right) {
    if (@($Left).Count -ne @($Right).Count) {return $false}
    for ($index=0;$index -lt @($Left).Count;$index++) {
        if ($Left[$index].version -cne $Right[$index].version -or $Left[$index].checksum -cne $Right[$index].checksum) {return $false}
    }
    return $true
}
function Assert-DependencyPath([string]$Id,$Value) {
    # PostgreSQL's timezone tree contains literal vendor filenames GMT+N.
    # This exception applies only to installed dependency evidence, not payloads.
    if ($Id -ceq 'postgresql' -and $Value -is [string] -and
        $Value -cmatch '^postgresql/share/timezone/(Etc/)?GMT\+(0|[1-9]|1[0-4])$') {return}
    Assert-UpdatePath $Value
}
function Assert-Dependencies($Items) {
    Assert-UpdateList $Items
    $seen = @{}
    foreach ($item in $Items) {
        Assert-Fields $item @('id','version','files')
        Assert-UpdateId $item.id
        if ($item.id -cnotin @('postgresql','keycloak','java','winsw','cloudflared','vc-runtime')) { throw 'Unknown dependency.' }
        if ($seen.ContainsKey($item.id) -or $item.version -isnot [string] -or -not $item.version -or $item.version.Length -gt 100) { throw 'Invalid dependency.' }
        $seen[$item.id] = $true
        Assert-UpdateList $item.files
        $paths = @{}
        foreach ($file in $item.files) {
            Assert-Fields $file @('path','sha256'); Assert-DependencyPath $item.id $file.path; Assert-UpdateHash $file.sha256
            if ($paths.ContainsKey($file.path)) { throw 'Duplicate dependency file.' }; $paths[$file.path] = $true
        }
    }
    foreach ($required in @('postgresql','keycloak','java','winsw','cloudflared','vc-runtime')) {
        if (-not $seen.ContainsKey($required)) { throw 'Missing dependency evidence.' }
    }
    if ($seen.Count -ne 6) { throw 'Unsupported dependency change.' }
}
function Assert-Manifest($Manifest) {
    Assert-Fields $Manifest @('format','kind','product','platform','releaseId','buildId','acceptedSources','files','dependencies','schemaBefore','schemaAfter','migrations','apiContract','supportedFrontends','recovery')
    if ($Manifest.format -isnot [int] -or $Manifest.format -ne 2 -or $Manifest.kind -cne 'application-update' -or $Manifest.product -cne 'aelium-propiedades' -or $Manifest.platform -cne 'windows-x64') { throw 'Unsupported update format, product or platform.' }
    Assert-UpdateId $Manifest.releaseId; Assert-UpdateId $Manifest.buildId; Assert-UpdateId $Manifest.apiContract
    Assert-UpdateList $Manifest.acceptedSources
    $seen = @{}
    foreach ($source in $Manifest.acceptedSources) {
        Assert-Fields $source @('sourceId','evidence'); Assert-UpdateId $source.sourceId; Assert-UpdateId $source.evidence
        if ($source.sourceId -ceq $Manifest.releaseId -or $seen.ContainsKey($source.sourceId)) { throw 'Invalid or duplicate source.' }; $seen[$source.sourceId] = $true
    }
    Assert-UpdateList $Manifest.files
    $paths = @{}; $destinations = @{}; $total = [long]0
    foreach ($file in $Manifest.files) {
        Assert-Fields $file @('path','target','size','sha256'); Assert-UpdatePath $file.path; Assert-UpdateHash $file.sha256
        if ($file.path -cnotin @('bin/propiedades-backend.exe','scripts/run-api.ps1','scripts/application.ps1','docs/LEEME.md')) { throw 'Payload path is not an application destination.' }
        if ($file.target -cnotin @('release','stable') -or ($file.target -ceq 'stable' -and $file.path -cne 'scripts/run-api.ps1')) { throw 'Forbidden payload target.' }
        if (($file.size -isnot [int] -and $file.size -isnot [long]) -or $file.size -le 0 -or $file.size -gt 536870912) { throw 'Invalid file size.' }
        if ($paths.ContainsKey($file.path) -or $destinations.ContainsKey($file.target + '/' + $file.path)) { throw 'Duplicate payload path.' }
        $paths[$file.path] = $true; $destinations[$file.target + '/' + $file.path] = $true; $total += $file.size
    }
    if (-not $paths.ContainsKey('bin/propiedades-backend.exe') -or $total -gt 1073741824) { throw 'Missing API or oversized package.' }
    Assert-Dependencies $Manifest.dependencies
    Assert-MigrationHistory $Manifest.schemaBefore; Assert-MigrationHistory $Manifest.schemaAfter; Assert-MigrationHistory $Manifest.migrations
    $expected = @($Manifest.schemaBefore) + @($Manifest.migrations)
    Assert-MigrationHistory $expected
    if (($expected | ConvertTo-Json -Depth 5 -Compress) -cne ($Manifest.schemaAfter | ConvertTo-Json -Depth 5 -Compress)) { throw 'Schema transition is inconsistent.' }
    Assert-UpdateList $Manifest.supportedFrontends
    $frontends = @{}
    foreach ($frontend in $Manifest.supportedFrontends) {
        Assert-Fields $frontend @('id','apiContract','evidence'); Assert-UpdateId $frontend.id; Assert-UpdateId $frontend.apiContract; Assert-UpdateId $frontend.evidence
        if ($frontends.ContainsKey($frontend.id) -or $frontend.apiContract -cne $Manifest.apiContract) { throw 'Invalid frontend compatibility.' }; $frontends[$frontend.id] = $true
    }
    Assert-Fields $Manifest.recovery @('sourceIds','schema','checks','preserve')
    Assert-UpdateList $Manifest.recovery.sourceIds
    if (@($Manifest.recovery.sourceIds | Select-Object -Unique).Count -ne $seen.Count -or $Manifest.recovery.sourceIds.Count -ne $seen.Count) { throw 'Invalid recovery sources.' }
    foreach ($id in $Manifest.recovery.sourceIds) { if (-not $seen.ContainsKey($id)) { throw 'Missing recovery source.' } }
    Assert-MigrationHistory $Manifest.recovery.schema
    if (($Manifest.recovery.schema | ConvertTo-Json -Depth 5 -Compress) -cne ($Manifest.schemaBefore | ConvertTo-Json -Depth 5 -Compress)) { throw 'Invalid recovery schema.' }
    foreach ($pair in @(@('checks',@('version','identity','read','write','frontend','cleanup')), @('preserve',@('application','schema','data','identity','config','attachments','services')))) {
        $values = $Manifest.recovery.($pair[0]); Assert-UpdateList $values
        if ($values.Count -ne $pair[1].Count -or @($values | Select-Object -Unique).Count -ne $values.Count) { throw 'Incomplete recovery requirements.' }
        foreach ($value in $values) { if ($value -cnotin $pair[1]) { throw 'Unknown recovery requirement.' } }
    }
}
function Test-UpdateArchive([string]$ArchivePath, [string]$ExpectedSha256) {
    Assert-UpdateHash $ExpectedSha256
    Assert-NoReparse $ArchivePath
    # Hash and inspect the same handle while denying concurrent writes/deletion.
    $archiveStream=[IO.File]::Open([IO.Path]::GetFullPath($ArchivePath),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $zip=$null
    try {
        if ($archiveStream.Length -gt 1073741824) { throw 'Oversized ZIP.' }
        if ((Get-UpdateStreamHash $archiveStream $archiveStream.Length) -cne $ExpectedSha256) { throw 'ZIP hash differs from external delivery reference.' }
        $archiveStream.Position=0
        $zip=New-Object IO.Compression.ZipArchive($archiveStream,[IO.Compression.ZipArchiveMode]::Read,$true)
        $entries = @{}; $total = [long]0
        if ($zip.Entries.Count -gt 5) { throw 'Too many ZIP entries.' }
        foreach ($entry in $zip.Entries) {
            Assert-UpdatePath $entry.FullName
            # Reject directories, Unix symlinks/special files, and Windows reparse entries.
            $mode = ($entry.ExternalAttributes -shr 16) -band 0xf000
            if ($mode -notin @(0,0x8000) -or ($entry.ExternalAttributes -band 0x410) -ne 0 -or $entry.Length -gt 536870912 -or $entry.Length -le 0) { throw 'Unsafe ZIP entry.' }
            if ($entries.ContainsKey($entry.FullName)) { throw 'Duplicate ZIP entry.' }; $entries[$entry.FullName] = $entry
            $total += $entry.Length
        }
        if ($total -gt 1073741824 -or -not $entries.ContainsKey('manifest.json') -or $entries['manifest.json'].FullName -cne 'manifest.json' -or $entries['manifest.json'].Length -gt 1048576) { throw 'Invalid ZIP inventory.' }
        $manifest = Read-UpdateEntryJson $entries['manifest.json']
        Assert-Manifest $manifest
        if ($entries.Count -ne $manifest.files.Count + 1) { throw 'Undeclared ZIP content.' }
        foreach ($file in $manifest.files) {
            if (-not $entries.ContainsKey($file.path) -or $entries[$file.path].FullName -cne $file.path -or $entries[$file.path].Length -ne $file.size) { throw 'Missing or mismatched payload file.' }
            $stream = $entries[$file.path].Open()
            try { $hash = Get-UpdateStreamHash $stream $file.size } finally { $stream.Dispose() }
            if ($hash -cne $file.sha256) { throw 'Payload integrity check failed.' }
        }
        [pscustomobject]@{manifest=$manifest;archiveSha256=$ExpectedSha256;status='PackageVerified'}
    } finally { if ($null -ne $zip) { $zip.Dispose() }; $archiveStream.Dispose() }
}

function Assert-InstalledFiles([string]$InstallationRoot, $Files) {
    Assert-UpdateList $Files; $seen = @{}
    foreach ($file in $Files) {
        Assert-Fields $file @('path','sha256'); Assert-UpdatePath $file.path; Assert-UpdateHash $file.sha256
        if ($seen.ContainsKey($file.path)) { throw 'Duplicate installed file.' }; $seen[$file.path] = $true
        if ((Get-UpdateFileHash (Join-Path $InstallationRoot $file.path)) -cne $file.sha256) { throw 'Installed fingerprint differs from reviewed source.' }
    }
}
function Assert-ServiceEvidence($Services) {
    Assert-UpdateList $Services; $seen=@{}
    foreach ($service in $Services) {
        Assert-Fields $service @('id','executable','account')
        if ($service.id -cnotin @('AeliumAPI','AeliumPostgres','AeliumKeycloak','AeliumTunnel') -or $seen.ContainsKey($service.id)) { throw 'Unknown or duplicate service.' }
        if ($service.executable -cne ('services/' + $service.id + '.exe') -or $service.account -cne 'LocalService') { throw 'Unsupported service layout or account.' }
        $seen[$service.id]=$true
    }
    foreach ($id in @('AeliumAPI','AeliumPostgres','AeliumKeycloak')) { if (-not $seen.ContainsKey($id)) { throw 'Missing service evidence.' } }
}
function Assert-InstalledDependency([string]$Root,$Dependency) {
    foreach ($file in $Dependency.files) {
        Assert-Fields $file @('path','sha256');Assert-DependencyPath $Dependency.id $file.path;Assert-UpdateHash $file.sha256
        # The Microsoft runtime is installed by Windows outside the application
        # root. This reserved namespace permits only these actual runtime DLLs;
        # no arbitrary absolute paths, payload destinations or file writes.
        if ($Dependency.id -ceq 'vc-runtime' -and $file.path -cmatch '^system-runtime/(vcruntime140(_1)?|msvcp140)\.dll$') {
            if (-not [Environment]::Is64BitProcess) {throw 'Runtime evidence requires a 64-bit maintenance process.'}
            $path=Join-Path ([Environment]::SystemDirectory) ($file.path.Substring('system-runtime/'.Length))
            if ((Get-UpdateFileHash $path) -cne $file.sha256) {throw 'Installed Microsoft runtime differs from reviewed evidence.'}
        } else {
            if ((Get-UpdateFileHash (Join-Path $Root $file.path)) -cne $file.sha256) {throw 'Installed dependency differs from reviewed evidence.'}
        }
    }
}
function Test-UpdateSource($Manifest, [string]$InstallationRoot, $Catalog, $Observation) {
    Assert-Manifest $Manifest
    $install = [IO.Path]::GetFullPath($InstallationRoot).TrimEnd('\')
    Assert-NoReparse $install
    $settings = Read-UpdateJson (Join-Path $install 'config/settings.json')
    if (-not ($settings.PSObject.Properties.Name -contains 'Complete') -or $settings.Complete -isnot [bool] -or -not $settings.Complete -or $settings.Format -isnot [int] -or $settings.Format -ne 1) { throw 'Installation is incomplete or unsupported.' }
    Assert-Fields $Catalog @('format','sources')
    if ($Catalog.format -isnot [int] -or $Catalog.format -ne 1) { throw 'Unknown source catalog format.' }; Assert-UpdateList $Catalog.sources
    Assert-Fields $Observation @('format','installationRoot','completeInventory','dependencies','schema','frontend','apiContract','services','evidence')
    if ($Observation.format -isnot [int] -or $Observation.format -ne 1 -or $Observation.completeInventory -isnot [bool] -or -not $Observation.completeInventory -or [IO.Path]::GetFullPath($Observation.installationRoot).TrimEnd('\') -cne $install) { throw 'Observation does not cover this installation.' }
    Assert-UpdateId $Observation.evidence; Assert-UpdateId $Observation.frontend; Assert-UpdateId $Observation.apiContract
    Assert-Dependencies $Observation.dependencies; Assert-MigrationHistory $Observation.schema -Observed
    Assert-ServiceEvidence $Observation.services
    $sourceIds = @{}
    foreach ($source in $Catalog.sources) {
        Assert-Fields $source @('sourceId','reviewed','reviewer','evidence','originalArchiveSha256','files','dependencies','schema','frontend','apiContract','services')
        Assert-UpdateId $source.sourceId
        if ($sourceIds.ContainsKey($source.sourceId)) { throw 'Ambiguous catalog ID.' }; $sourceIds[$source.sourceId] = $true
    }
    $matches = @()
    foreach ($source in $Catalog.sources) {
        if ($source.reviewed -isnot [bool] -or -not $source.reviewed) { continue }
        Assert-UpdateId $source.reviewer; Assert-UpdateId $source.evidence; Assert-UpdateHash $source.originalArchiveSha256
        $admission = @($Manifest.acceptedSources | Where-Object { $_.sourceId -ceq $source.sourceId -and $_.evidence -ceq $source.evidence })
        if ($admission.Count -ne 1) { continue }
        try {
            Assert-Dependencies $source.dependencies; Assert-MigrationHistory $source.schema
            Assert-ServiceEvidence $source.services
            foreach ($required in @('bin/propiedades-backend.exe','scripts/run-api.ps1','scripts/Common.ps1','scripts/run-keycloak.ps1')) {
                if (@($source.files | Where-Object { $_.path -ceq $required }).Count -ne 1) { throw 'Missing application startup evidence.' }
            }
            $observedHistory = @($Observation.schema | ForEach-Object { [pscustomobject]@{version=$_.version;checksum=$_.checksum} })
            if (-not (Test-MigrationEquality $source.schema $observedHistory) -or -not (Test-MigrationEquality $source.schema $Manifest.schemaBefore)) {throw 'Incompatible migration history.'}
            foreach ($comparison in @(@($source.dependencies,$Observation.dependencies), @($source.dependencies,$Manifest.dependencies), @($source.services,$Observation.services))) {
                if (($comparison[0] | ConvertTo-Json -Depth 12 -Compress) -cne ($comparison[1] | ConvertTo-Json -Depth 12 -Compress)) { throw 'Incompatible observed environment.' }
            }
            if ($source.frontend -cne $Observation.frontend -or $source.apiContract -cne $Observation.apiContract -or @($Manifest.supportedFrontends | Where-Object { $_.id -ceq $source.frontend }).Count -ne 1) { throw 'Unrecognized frontend.' }
            Assert-InstalledFiles $install $source.files
            foreach ($dependency in $source.dependencies) { Assert-InstalledDependency $install $dependency }
            $matches += $source.sourceId
        } catch { continue }
    }
    if ($matches.Count -ne 1) { throw 'Source unknown, incompatible or ambiguous; no changes made.' }
    # Observations are reviewed external evidence, not a substitute for live WP-007/009 checks.
    [pscustomobject]@{status='SourceFingerprintMatched';sourceId=$matches[0];releaseId=$Manifest.releaseId;observationEvidence=$Observation.evidence;livePreflightComplete=$false}
}
