. (Join-Path $PSScriptRoot '../../deploy/windows/update/Package.ps1')
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$runId = 'package-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$run = Join-Path $repo ('tests/artifacts/updates/' + $runId)
New-Item -ItemType Directory -Path $run | Out-Null
$content = Join-Path $run 'content'; $install = Join-Path $run 'installation'
New-Item -ItemType Directory -Path (Join-Path $content 'bin'),(Join-Path $install 'bin'),(Join-Path $install 'config') | Out-Null
[IO.File]::WriteAllText((Join-Path $content 'bin/propiedades-backend.exe'),'synthetic candidate, never executable')
[IO.File]::WriteAllText((Join-Path $install 'bin/propiedades-backend.exe'),'synthetic original, never executable')
[IO.File]::WriteAllText((Join-Path $install 'config/settings.json'),'{"Format":1,"Complete":true}')
$dependencies = @()
foreach ($id in @('postgresql','keycloak','java','winsw','cloudflared','vc-runtime')) {
    $relative = 'dependencies/' + $id + '.fixture'
    New-Item -ItemType Directory -Path (Join-Path $install 'dependencies') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $install $relative),('synthetic dependency ' + $id))
    $dependencies += [pscustomobject]@{id=$id;version='fixture-1';files=@([pscustomobject]@{path=$relative;sha256=(Get-UpdateFileHash (Join-Path $install $relative))})}
}
$history = @([pscustomobject]@{version='1';checksum=('a' * 96)})
$definition = [pscustomobject]@{
    format=2;kind='application-update';product='aelium-propiedades';platform='windows-x64';releaseId='fixture-new';buildId='fixture-build'
    acceptedSources=@([pscustomobject]@{sourceId='fixture-original';evidence='fixture-review'})
    files=@([pscustomobject]@{path='bin/propiedades-backend.exe';target='release'})
    dependencies=$dependencies;schemaBefore=$history;schemaAfter=$history;migrations=@();apiContract='fixture-v1'
    supportedFrontends=@([pscustomobject]@{id='fixture-web';apiContract='fixture-v1';evidence='fixture-contract'})
    recovery=[pscustomobject]@{sourceIds=@('fixture-original');schema=$history;checks=@('version','identity','read','write','frontend','cleanup');preserve=@('application','schema','data','identity','config','attachments','services')}
}
function Clone($Object) { $Object | ConvertTo-Json -Depth 30 | ConvertFrom-Json }
$definitionPath = Join-Path $run 'definition.json'
[IO.File]::WriteAllText($definitionPath,($definition | ConvertTo-Json -Depth 20))
$archive = Join-Path $run 'candidate.zip'
$built = & (Join-Path $repo 'deploy/windows/Build-UpdatePackage.ps1') -SyntheticFixture -ContentRoot $content -DefinitionPath $definitionPath -OutputArchive $archive
$verified = Test-UpdateArchive $archive $built.sha256
$manifest = $verified.manifest
$originalFiles=@([pscustomobject]@{path='bin/propiedades-backend.exe';sha256=(Get-UpdateFileHash (Join-Path $install 'bin/propiedades-backend.exe'))})
New-Item -ItemType Directory -Path (Join-Path $install 'scripts') | Out-Null
foreach ($name in @('run-api.ps1','Common.ps1','run-keycloak.ps1')) {
    [IO.File]::WriteAllText((Join-Path $install ('scripts/' + $name)),('synthetic startup ' + $name))
    $originalFiles += [pscustomobject]@{path=('scripts/' + $name);sha256=(Get-UpdateFileHash (Join-Path $install ('scripts/' + $name)))}
}
$services=@('AeliumAPI','AeliumPostgres','AeliumKeycloak') | ForEach-Object { [pscustomobject]@{id=$_;executable=('services/' + $_ + '.exe');account='LocalService'} }
$catalog = [pscustomobject]@{format=1;sources=@([pscustomobject]@{
    sourceId='fixture-original';reviewed=$true;reviewer='synthetic-reviewer';evidence='fixture-review';originalArchiveSha256=('b' * 64)
    files=$originalFiles
    dependencies=$dependencies;schema=$history;frontend='fixture-web';apiContract='fixture-v1';services=$services
})}
$observation = [pscustomobject]@{format=1;installationRoot=$install;completeInventory=$true;dependencies=$dependencies;schema=@([pscustomobject]@{version='1';checksum=('a' * 96);success=$true});frontend='fixture-web';apiContract='fixture-v1';services=$services;evidence='fixture-observation'}
$results = New-Object Collections.Generic.List[object]
function Check([string]$Name,[scriptblock]$Action,[bool]$Reject=$false) {
    $rejected = $false
    try { $null = & $Action } catch { $rejected = $true; if (-not $Reject) { throw } }
    if ($Reject -ne $rejected) { throw ('Unexpected outcome: ' + $Name) }
    $results.Add([pscustomobject]@{variant=$Name;expected= $(if($Reject){'Reject'}else{'Accept'});actual= $(if($rejected){'Reject'}else{'Accept'});status='PASS'})
}
Check 'native builder and externally checked archive' { Test-UpdateArchive $archive $built.sha256 }
Check 'reviewed synthetic source fingerprint' { Test-UpdateSource $manifest $install $catalog $observation }
Check 'unreviewed source not admitted' { $c=Clone $catalog; $c.sources[0].reviewed=$false; Test-UpdateSource $manifest $install $c $observation } $true
Check 'wrong external ZIP reference' { Test-UpdateArchive $archive ('0' * 64) } $true
Check 'format 1 cannot be used as update' { $m=Clone $manifest; $m.format=1; Assert-Manifest $m } $true
Check 'incorrect product' { $m=Clone $manifest; $m.product='other-product'; Assert-Manifest $m } $true
Check 'incorrect platform' { $m=Clone $manifest; $m.platform='linux-x64'; Assert-Manifest $m } $true
Check 'missing mandatory field' { $m=Clone $manifest; $m.PSObject.Properties.Remove('buildId'); Assert-Manifest $m } $true
Check 'unknown field or hook' { $m=Clone $manifest; $m | Add-Member hook 'run-anything'; Assert-Manifest $m } $true
Check 'duplicate JSON keys' { ConvertFrom-UpdateJson '{"format":2,"format":1}' } $true
Check 'escaped duplicate JSON keys' { ConvertFrom-UpdateJson '{"format":2,"\u0066ormat":1}' } $true
Check 'case alias JSON keys' { ConvertFrom-UpdateJson '{"format":2,"Format":1}' } $true
Check 'decompression cannot exceed declared size' { $s=New-Object IO.MemoryStream(,[Text.Encoding]::UTF8.GetBytes('too long'));try{Get-UpdateStreamHash $s 2}finally{$s.Dispose()} } $true
foreach ($bad in @('../bin/propiedades-backend.exe','/bin/propiedades-backend.exe','C:/bin/propiedades-backend.exe','bin\propiedades-backend.exe','bin/CON.exe','bin/file.','bin/file.exe:stream')) {
    Check ('unsafe path ' + $bad) { Assert-UpdatePath $bad } $true
}
Check 'duplicate payload' { $m=Clone $manifest; $m.files=@($m.files[0],$m.files[0]); Assert-Manifest $m } $true
Check 'configuration is not payload' { $m=Clone $manifest; $m.files[0].path='config/settings.json'; Assert-Manifest $m } $true
Check 'dependency distribution is not payload' { $m=Clone $manifest; $m.files[0].path='payload/postgresql.zip'; Assert-Manifest $m } $true
Check 'forbidden stable destination' { $m=Clone $manifest; $m.files[0].target='stable'; Assert-Manifest $m } $true
Check 'missing dependency evidence' { $m=Clone $manifest; $m.dependencies=@($m.dependencies[0]); Assert-Manifest $m } $true
Check 'inconsistent schema transition' { $m=Clone $manifest; $m.schemaAfter[0].checksum='c' * 96; Assert-Manifest $m } $true
Check 'incomplete recovery checks' { $m=Clone $manifest; $m.recovery.checks=@('version'); Assert-Manifest $m } $true
Check 'unsupported frontend' { $o=Clone $observation; $o.frontend='unknown'; Test-UpdateSource $manifest $install $catalog $o } $true
Check 'failed migration' { $o=Clone $observation; $o.schema[0].success=$false; Test-UpdateSource $manifest $install $catalog $o } $true
Check 'modified SQLx checksum' { $o=Clone $observation; $o.schema[0].checksum='c' * 96; Test-UpdateSource $manifest $install $catalog $o } $true
Check 'changed dependency version' { $o=Clone $observation; $o.dependencies[0].version='fixture-2'; Test-UpdateSource $manifest $install $catalog $o } $true
Check 'different service account' { $o=Clone $observation; $o.services[0].account='LocalSystem'; Test-UpdateSource $manifest $install $catalog $o } $true
Check 'incomplete service inventory' { $o=Clone $observation; $o.services=@($o.services[0]); Test-UpdateSource $manifest $install $catalog $o } $true
Check 'missing startup fingerprint' { $c=Clone $catalog; $c.sources[0].files=@($c.sources[0].files[0]); Test-UpdateSource $manifest $install $c $observation } $true
Check 'different observed root' { $o=Clone $observation; $o.installationRoot=$run; Test-UpdateSource $manifest $install $catalog $o } $true
Check 'ambiguous catalog identity' { $c=Clone $catalog; $c.sources=@($c.sources[0],$c.sources[0]); Test-UpdateSource $manifest $install $c $observation } $true
$before = @(Get-ChildItem -LiteralPath $install -File -Recurse | ForEach-Object { @{path=$_.FullName;hash=(Get-UpdateFileHash $_.FullName)} }) | ConvertTo-Json -Compress
Check 'read-only matching does not mutate installation' { Test-UpdateSource $manifest $install $catalog $observation }
$after = @(Get-ChildItem -LiteralPath $install -File -Recurse | ForEach-Object { @{path=$_.FullName;hash=(Get-UpdateFileHash $_.FullName)} }) | ConvertTo-Json -Compress
if ($before -cne $after) { throw 'Source verification changed installation.' }
[IO.File]::WriteAllText((Join-Path $install 'bin/propiedades-backend.exe'),'changed source')
Check 'modified installed binary' { Test-UpdateSource $manifest $install $catalog $observation } $true
[IO.File]::WriteAllText((Join-Path $install 'config/settings.json'),'{"Format":1,"Complete":false}')
Check 'partial installation' { Test-UpdateSource $manifest $install $catalog $observation } $true

function MutatedArchive([string]$Name,[scriptblock]$Mutation) {
    $destination=Join-Path $run ($Name + '.zip'); Copy-Item -LiteralPath $archive -Destination $destination
    $zip=[IO.Compression.ZipFile]::Open($destination,[IO.Compression.ZipArchiveMode]::Update)
    try { & $Mutation $zip } finally { $zip.Dispose() }
    return $destination
}
$changed = MutatedArchive 'tampered' { param($z) $z.GetEntry('bin/propiedades-backend.exe').Delete(); $e=$z.CreateEntry('bin/propiedades-backend.exe'); $w=New-Object IO.StreamWriter($e.Open()); try{$w.Write('altered')}finally{$w.Dispose()} }
Check 'tampered file even with recomputed ZIP reference' { Test-UpdateArchive $changed (Get-UpdateFileHash $changed) } $true
$extra = MutatedArchive 'extra' { param($z) $e=$z.CreateEntry('extra.exe'); $w=New-Object IO.StreamWriter($e.Open());try{$w.Write('extra')}finally{$w.Dispose()} }
Check 'undeclared executable' { Test-UpdateArchive $extra (Get-UpdateFileHash $extra) } $true
$missing = MutatedArchive 'missing' { param($z) $z.GetEntry('bin/propiedades-backend.exe').Delete() }
Check 'missing payload' { Test-UpdateArchive $missing (Get-UpdateFileHash $missing) } $true
$duplicate = MutatedArchive 'duplicate' { param($z) $e=$z.CreateEntry('BIN/propiedades-backend.exe');$w=New-Object IO.StreamWriter($e.Open());try{$w.Write('duplicate')}finally{$w.Dispose()} }
Check 'Windows case alias' { Test-UpdateArchive $duplicate (Get-UpdateFileHash $duplicate) } $true
$symlink = MutatedArchive 'symlink' { param($z) $z.GetEntry('bin/propiedades-backend.exe').ExternalAttributes=([int]0xa000 -shl 16) }
Check 'ZIP symlink' { Test-UpdateArchive $symlink (Get-UpdateFileHash $symlink) } $true
$reparse = MutatedArchive 'reparse' { param($z) $z.GetEntry('bin/propiedades-backend.exe').ExternalAttributes=0x400 }
Check 'ZIP reparse point' { Test-UpdateArchive $reparse (Get-UpdateFileHash $reparse) } $true
Check 'builder refuses overwrite of same release archive' { & (Join-Path $repo 'deploy/windows/Build-UpdatePackage.ps1') -SyntheticFixture -ContentRoot $content -DefinitionPath $definitionPath -OutputArchive $archive } $true
Check 'builder refuses overwrite of existing external reference' {
    $output=Join-Path $run 'existing-reference.zip'
    [IO.File]::WriteAllText($output + '.sha256','preserve original reference')
    & (Join-Path $repo 'deploy/windows/Build-UpdatePackage.ps1') -SyntheticFixture -ContentRoot $content -DefinitionPath $definitionPath -OutputArchive $output
} $true
Check 'release identity cannot be reused at another output filename' { & (Join-Path $repo 'deploy/windows/Build-UpdatePackage.ps1') -SyntheticFixture -ContentRoot $content -DefinitionPath $definitionPath -OutputArchive (Join-Path $run 'reused-id.zip') } $true
$junction=Join-Path $run 'junction'
New-Item -ItemType Junction -Path $junction -Target $install | Out-Null
if (-not ((Get-Item -LiteralPath $junction -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Junction fixture was not created.' }
Check 'junction in native filesystem is rejected' {
    Assert-NoReparse (Join-Path $junction 'bin/propiedades-backend.exe')
} $true

$originalZip=Join-Path $run 'original-fixture.zip'
$zip=[IO.Compression.ZipFile]::Open($originalZip,[IO.Compression.ZipArchiveMode]::Create)
try {
    $entry=$zip.CreateEntry('payload\propiedades-backend.exe')
    $writer=New-Object IO.StreamWriter($entry.Open(),(New-Object Text.UTF8Encoding($false)))
    try { $writer.Write('synthetic original') } finally { $writer.Dispose() }
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('synthetic original'))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    $entry=$zip.CreateEntry('manifest.json');$writer=New-Object IO.StreamWriter($entry.Open())
    try { $writer.Write((@{format=1;platform='windows-x64';files=@(@{path='payload/propiedades-backend.exe';sha256=$hash})} | ConvertTo-Json -Depth 5)) } finally { $writer.Dispose() }
} finally { $zip.Dispose() }
Check 'legacy backslash ZIP produces unreviewed candidate only' {
    $catalogPath=Join-Path $run 'legacy-fixture.json'
    $candidate=& (Join-Path $repo 'deploy/windows/New-LegacySourceCandidate.ps1') -OriginalArchive $originalZip -ExpectedSha256 (Get-UpdateFileHash $originalZip) -OutputCatalog $catalogPath
    $c=Read-UpdateJson $catalogPath
    if ($candidate.clientSourceAccepted -or $c.sources[0].reviewed -or $c.sources[0].files[0].path -cne 'bin/propiedades-backend.exe' -or $c.sources[0].dependencies.Count) { throw 'Legacy candidate invented compatibility.' }
}
$definition.files[0].target='release'
Check 'second distinct release atomically extends existing ledger' {
    $next=Clone $definition;$next.releaseId='fixture-next';$next.buildId='fixture-next-build'
    $nextPath=Join-Path $run 'next-definition.json';[IO.File]::WriteAllText($nextPath,($next|ConvertTo-Json -Depth 20))
    & (Join-Path $repo 'deploy/windows/Build-UpdatePackage.ps1') -SyntheticFixture -ContentRoot $content -DefinitionPath $nextPath -OutputArchive (Join-Path $run 'next-release.zip')
    if ((Read-UpdateJson (Join-Path $run 'release-ledger.json')).releases.Count -ne 2) {throw 'Ledger replacement lost releases.'}
}
[IO.File]::WriteAllText((Join-Path $content 'extra-secret.json'),'synthetic secret')
Check 'builder rejects undeclared content before creating output' {
    & (Join-Path $repo 'deploy/windows/Build-UpdatePackage.ps1') -SyntheticFixture -ContentRoot $content -DefinitionPath $definitionPath -OutputArchive (Join-Path $run 'undeclared-content.zip')
} $true
$report=[ordered]@{runId=$runId;createdUtc=[DateTime]::UtcNow.ToString('o');level='native Windows package tooling with synthetic files';tests=@('TEST-023','TEST-024','TEST-035');familyStatus='Not Run - partial static/tooling evidence only';releaseId=$manifest.releaseId;buildId=$manifest.buildId;archiveSha256=$built.sha256;schemaBefore=$history;schemaAfter=$history;os=[Environment]::OSVersion.VersionString;installation='synthetic fixture';liveServicesChecked=$false;results=@($results.ToArray());limitations=@('No executable API, live services, database or real frontend tested','No update applied; no family or requirement acceptance claimed','Real reboot and service coverage pending WP-010')}
[IO.File]::WriteAllText((Join-Path $run 'report.json'),($report | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
Write-Host ('Package tooling checks: ' + $results.Count + ' PASS; partial evidence: tests/artifacts/updates/' + $runId + '/report.json')
