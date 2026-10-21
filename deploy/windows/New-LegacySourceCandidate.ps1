[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OriginalArchive,
    [Parameter(Mandatory=$true)][string]$ExpectedSha256,
    [Parameter(Mandatory=$true)][string]$OutputCatalog
)
. (Join-Path $PSScriptRoot 'update/Package.ps1')
Assert-UpdateHash $ExpectedSha256
if ((Get-UpdateFileHash $OriginalArchive) -cne $ExpectedSha256) { throw 'Original ZIP differs from external reference.' }
Assert-NoReparse $OutputCatalog
if (Test-Path -LiteralPath $OutputCatalog) { throw 'Catalog output already exists.' }
$zip = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($OriginalArchive))
try {
    $entries = @{}
    foreach ($entry in $zip.Entries) {
        # .NET Framework's old full-installer builder uses backslashes in ZIP names.
        # Normalize only this legacy reader; format=2 continues to reject them.
        $name = $entry.FullName.Replace('\','/')
        # The legacy builder emits directory entries. Never extract them.
        if ($name.EndsWith('/')) { Assert-UpdatePath $name.TrimEnd('/'); continue }
        Assert-UpdatePath $name
        if ($entries.ContainsKey($name)) { throw 'Duplicate original ZIP file.' }; $entries[$name] = $entry
    }
    if (-not $entries.ContainsKey('manifest.json') -or $entries['manifest.json'].Length -gt 1048576) { throw 'Missing original manifest.' }
    $original = Read-UpdateEntryJson $entries['manifest.json']
    if ($original.format -ne 1 -or $original.platform -cne 'windows-x64') { throw 'Not an original Windows installation package.' }
    Assert-UpdateList $original.files
    if ($entries.Count -ne $original.files.Count + 1) { throw 'Original inventory differs from archive.' }
    $files = @(); $seen = @{}
    foreach ($file in $original.files) {
        Assert-Fields $file @('path','sha256'); Assert-UpdatePath $file.path; Assert-UpdateHash $file.sha256
        if ($seen.ContainsKey($file.path) -or -not $entries.ContainsKey($file.path) -or $entries[$file.path].FullName.Replace('\','/') -cne $file.path) { throw 'Invalid original file inventory.' }; $seen[$file.path] = $true
        $stream = $entries[$file.path].Open()
        try { $hash = Get-UpdateStreamHash $stream $entries[$file.path].Length } finally { $stream.Dispose() }
        if ($hash -cne $file.sha256) { throw 'Original payload checksum failed.' }
        if ($file.path -ceq 'payload/propiedades-backend.exe') { $files += [pscustomobject]@{path='bin/propiedades-backend.exe';sha256=$hash} }
        elseif ($file.path -match '^[^/]+\.ps1$') { $files += [pscustomobject]@{path=('scripts/' + $file.path);sha256=$hash} }
    }
    if (@($files | Where-Object { $_.path -ceq 'bin/propiedades-backend.exe' }).Count -ne 1) { throw 'Original API missing.' }
    $sourceId = 'legacy-' + $ExpectedSha256
    if ($original.PSObject.Properties.Name -contains 'releaseId') {Assert-UpdateId $original.releaseId;$sourceId=$original.releaseId}
    $source = [ordered]@{sourceId=$sourceId;reviewed=$false;reviewer=$null;evidence=$null;originalArchiveSha256=$ExpectedSha256;files=$files;dependencies=@();schema=@();frontend=$null;apiContract=$null;services=@()}
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputCatalog),(@{format=1;sources=@($source)} | ConvertTo-Json -Depth 15),(New-Object Text.UTF8Encoding($false)))
    [pscustomobject]@{status='UnreviewedCandidate';sourceId=$sourceId;applicationFiles=$files.Count;missingEvidence=@('installed-dependencies','sqlx-history','frontend-contract','services','independent-review');clientSourceAccepted=$false}
} finally { $zip.Dispose() }
