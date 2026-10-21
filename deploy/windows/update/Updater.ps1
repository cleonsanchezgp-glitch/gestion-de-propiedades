. (Join-Path $PSScriptRoot 'Backup.ps1')

function Get-UpdateVerificationMode($Value) {
    $property=$Value.PSObject.Properties['verificationMode']
    if ($null -eq $property) {return 'Production'}
    if ($property.Value -cnotin @('Production','LocalRehearsal')) {throw 'Unknown verification mode.'}
    return $property.Value
}
function Assert-LocalRehearsal([string]$Root) {
    # An explicit switch alone must not turn a client installation into a test.
    $marker=Read-UpdateJson (Join-Path $Root 'config/local-rehearsal.json')
    Assert-Fields $marker @('format','purpose','installationRoot','ownerSubject')
    $settings=Read-UpdateJson (Join-Path $Root 'config/settings.json')
    if ($marker.format -ne 1 -or $marker.purpose -cne 'isolated-vm-update-rehearsal' -or
        [IO.Path]::GetFullPath($marker.installationRoot).TrimEnd('\') -cne $Root -or
        $marker.ownerSubject -cne $settings.OwnerSubject -or -not $marker.ownerSubject -or
        $settings.PortalOrigin -cne 'https://portal.example.test' -or $settings.Username -cne 'prueba') {
        throw 'Local rehearsal requires the explicitly prepared isolated test installation.'
    }
    if (Test-Path -LiteralPath (Join-Path $Root 'config/tunnel-token.txt')) {throw 'Local rehearsal cannot use a configured tunnel.'}
    if (-not (Test-UpdateFixtureRoot $Root) -and (Get-Service -Name AeliumTunnel -ErrorAction SilentlyContinue)) {throw 'Local rehearsal cannot use a tunnel service.'}
}
function Get-UpdateResult([string]$Status,$Value,[string]$Mode) {
    $Value | Add-Member -NotePropertyName verificationMode -NotePropertyValue $Mode -Force
    if ($Mode -ceq 'LocalRehearsal') {
        $Status=switch ($Status) {
            'UpdateSucceeded' {'LocalRehearsalSucceeded'}
            'AlreadyApplied' {'LocalRehearsalAlreadyApplied'}
            'PreflightVerified' {'LocalRehearsalPreflightVerified'}
            default {$Status}
        }
        $Value | Add-Member -NotePropertyName updateSucceeded -NotePropertyValue $false -Force
        $Value | Add-Member -NotePropertyName portalChecked -NotePropertyValue $false -Force
        $Value | Add-Member -NotePropertyName productionAccepted -NotePropertyValue $false -Force
    }
    $Value | Add-Member -NotePropertyName status -NotePropertyValue $Status -Force
    return $Value
}
function Test-UpdateFixtureRoot([string]$Root) {
    $allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../tests/artifacts/updates')).TrimEnd('\')+'\'
    return $Root.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)
}
function Assert-UpdatePortal([string]$Origin,[string]$Root) {
    $uri=New-Object Uri($Origin)
    if (-not $uri.IsAbsoluteUri -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $Origin -cne $uri.GetLeftPart([UriPartial]::Authority)) {throw 'Portal must be an exact trusted origin.'}
    if ($uri.Scheme -cne 'https' -and -not ((Test-UpdateFixtureRoot $Root) -and $uri.Scheme -ceq 'http' -and $uri.Host -ceq '127.0.0.1')) {throw 'Portal verification requires HTTPS.'}
}
function Invoke-UpdateHttp([string]$Uri,[string]$Method='GET',$Body=$null,$Headers=@{}) {
    $arguments=@{Uri=$Uri;Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=20;MaximumRedirection=0;ErrorAction='Stop'}
    if ($null -ne $Body) {$arguments.Body=($Body|ConvertTo-Json -Depth 10 -Compress);$arguments.ContentType='application/json; charset=utf-8'}
    try {
        $response=Invoke-WebRequest @arguments
        if ($response.StatusCode -ne 200 -or $response.Content.Length -gt 4194304) {throw 'Unexpected response.'}
        ConvertFrom-UpdateJson $response.Content
    }catch {throw 'Authenticated application/portal verification failed.'}
}
function Get-UpdateSchema($Pg) {
    $text=Invoke-UpdateSql $Pg 'propiedades' "SELECT coalesce(json_agg(x ORDER BY version::bigint)::text,'[]') FROM (SELECT version::text version,encode(checksum,'hex') checksum,success FROM public._sqlx_migrations) x"
    $items=$text | ConvertFrom-Json;Assert-MigrationHistory $items -Observed
    return $items
}
function Test-ApplicationUpdatePreflight([string]$Root,[string]$Archive,[string]$ExpectedSha256,$Catalog,$Observation,$Inventory,[switch]$ControlHeld,[switch]$LocalRehearsal) {
    $root=[IO.Path]::GetFullPath($Root).TrimEnd('\');Assert-NoReparse $root
    if ($LocalRehearsal) {Assert-LocalRehearsal $root}
    elseif (Test-Path -LiteralPath (Join-Path $root 'config/local-rehearsal.json')) {throw 'A marked rehearsal installation requires the explicit LocalRehearsal switch.'}
    $mode=if ($LocalRehearsal) {'LocalRehearsal'}else{'Production'}
    Assert-UpdateInventory $Inventory
    $verified=Test-UpdateArchive $Archive $ExpectedSha256
    $control=[pscustomobject]@{root=$root;operationPath=(Join-Path $root 'maintenance/operation.json')}
    $pg=Get-UpdatePg $control
    if (Test-Path -LiteralPath $control.operationPath) {
        $op=Read-UpdateJson $control.operationPath;Assert-Operation $op
        if ($op.phase -cnotin @('Committed','Recovered')) {throw 'Incomplete operation; use verification or recovery, do not begin another update.'}
    } elseif (Test-Path -LiteralPath (Join-Path $root 'maintenance')) {
        $names=@(Get-ChildItem -LiteralPath (Join-Path $root 'maintenance') -Force | ForEach-Object {$_.Name})
        if (-not $ControlHeld -or @($names | Where-Object {$_ -cnotin @('update.lock','write-gate.lock')}).Count) {throw 'Incomplete maintenance adoption; review state before proceeding.'}
    }
    $selectorPath=Join-Path $root 'config/active-release.json'
    if (Test-Path -LiteralPath $selectorPath) {
        $selector=Read-UpdateJson $selectorPath
        if ($selector.releaseId -ceq $verified.manifest.releaseId) {
            $receipt=Read-UpdateJson (Join-Path $root 'maintenance/applied-release.json')
            if ((Get-UpdateVerificationMode $receipt) -cne $mode) {throw 'Applied release belongs to a different verification mode.'}
            if ($receipt.archiveSha256 -cne $ExpectedSha256 -or $receipt.releaseId -cne $selector.releaseId -or $selector.path -cne ('releases/'+$selector.releaseId) -or (Get-UpdateFileHash (Join-Path $root ($selector.path+'/manifest.json'))) -cne $selector.manifestSha256) {throw 'Previously applied identity has different content.'}
            foreach ($file in $verified.manifest.files) {
                $base=if ($file.target -ceq 'stable') {$root}else{Join-Path $root $selector.path}
                if ((Get-UpdateFileHash (Join-Path $base $file.path)) -cne $file.sha256) {throw 'Previously applied files have changed.'}
            }
            $history=@(Get-UpdateSchema $pg | ForEach-Object {[pscustomobject]@{version=$_.version;checksum=$_.checksum}})
            if (-not (Test-MigrationEquality $history $verified.manifest.schemaAfter)) {throw 'Applied schema differs.'}
            return [pscustomobject]@{status='AlreadyApplied';releaseId=$selector.releaseId;archiveSha256=$ExpectedSha256}
        }
    }
    $source=Test-UpdateSource $verified.manifest $root $Catalog $Observation
    if (Test-Path -LiteralPath $selectorPath) {
        $selector=Read-UpdateJson $selectorPath
        if ($selector.releaseId -cne $source.sourceId) {throw 'Selected source differs from reviewed fingerprint identity.'}
        $null=& (Join-Path $PSScriptRoot 'run-api.ps1') -InstallRoot $root -CheckOnly
    }
    $history=@(Get-UpdateSchema $pg)
    $plain=@($history | ForEach-Object {[pscustomobject]@{version=$_.version;checksum=$_.checksum}})
    if (-not (Test-MigrationEquality $plain $verified.manifest.schemaBefore)) {throw 'Live migration history is incompatible.'}
    $settings=Read-UpdateJson (Join-Path $root 'config/settings.json')
    if (-not $LocalRehearsal) {
        Assert-UpdatePortal $settings.PortalOrigin $root
        $frontend=Invoke-UpdateHttp ($settings.PortalOrigin+'/release.json')
        if ($frontend.format -ne 1 -or $frontend.releaseId -cne $Observation.frontend -or $frontend.apiContract -cne $Observation.apiContract -or $verified.manifest.apiContract -cnotin $frontend.compatibleApiContracts) {throw 'Live frontend identity/contract not admitted.'}
    }
    $serviceControl=[pscustomobject]@{root=$root}
    if (-not (Test-UpdateFixtureRoot $root)) {
        $writers=@(Get-OwnedWriterServices $serviceControl)
        foreach ($entry in $writers) {if ($entry.state -cne 'Running') {throw 'Normal update requires writer services initially running.'}}
        foreach ($service in $Observation.services) {
            $actual=Get-CimInstance Win32_Service -Filter ("Name='"+$service.id+"'")
            $expected=Join-Path $root $service.executable
            if (-not $actual -or ($actual.PathName -ine $expected -and $actual.PathName -ine ('"'+$expected+'"')) -or $actual.StartName -inotmatch '^(NT AUTHORITY\\)?LocalService$') {throw 'Live service layout differs from reviewed evidence.'}
        }
    }
    # Standard recovery only supports the original libc/default-table-space
    # database layout. Estimate conservatively, including separate trial data.
    $size=[long](Invoke-UpdateSql $pg 'postgres' "SELECT sum(pg_database_size(datname)) FROM pg_database WHERE datname IN ('propiedades','keycloak')")
    $files=@(Get-UpdateTree $root (@('config','scripts','bin','services','keycloak/conf')+@($Inventory.attachments | ForEach-Object {$_.path})))
    $fileBytes=[long](($files | Measure-Object -Property size -Sum).Sum)
    $drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($root))
    $required=($size*5)+($fileBytes*3)+2147483648
    if ($drive.AvailableFreeSpace -lt $required) {throw 'Insufficient space for staging backup isolated verification and recovery.'}
    $verified | Add-Member -NotePropertyName sourceId -NotePropertyValue $source.sourceId
    $verified | Add-Member -NotePropertyName installationRoot -NotePropertyValue $root
    $verified | Add-Member -NotePropertyName requiredSpace -NotePropertyValue $required
    $verified.status='PreflightVerified'
    return $verified
}
function Expand-ApplicationUpdate($Control,[string]$Archive,[string]$ExpectedSha256) {
    $operation=Read-UpdateJson $Control.operationPath
    if ($operation.phase -cne 'Applying') {throw 'Staging activation requires Applying.'}
    $verified=Test-UpdateArchive $Archive $ExpectedSha256
    if ($verified.manifest.releaseId -cne $operation.targetReleaseId) {throw 'Candidate identity differs from operation.'}
    $release=Join-Path $Control.root ('releases/'+$verified.manifest.releaseId);Assert-NoReparse $release
    if (Test-Path -LiteralPath $release) {throw 'Candidate directory already exists; recover incomplete operation before retry.'}
    Set-PrivateUpdateDirectory $release
    $stream=[IO.File]::Open([IO.Path]::GetFullPath($Archive),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $zip=$null
    try {
        if ((Get-UpdateStreamHash $stream $stream.Length) -cne $ExpectedSha256) {throw 'Archive changed after preflight.'}
        $stream.Position=0;$zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Read,$true)
        foreach ($file in $verified.manifest.files) {
            $entry=$zip.GetEntry($file.path);$target=Join-Path $release $file.path;Assert-NoReparse $target
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
            if ((Get-UpdateFileHash $target) -cne $file.sha256) {throw 'Extracted candidate differs.'}
        }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry('manifest.json'),(Join-Path $release 'manifest.json'),$false)
    } finally {if ($zip) {$zip.Dispose()};$stream.Dispose()}
    $binary=Join-Path $release 'bin/propiedades-backend.exe'
    $info=& $binary --release-info
    if ($LASTEXITCODE -ne 0) {throw 'Candidate release-info failed.'};$info=ConvertFrom-UpdateJson ($info|Out-String)
    if ($info.product -cne 'aelium-propiedades' -or $info.releaseId -cne $verified.manifest.releaseId -or $info.buildId -cne $verified.manifest.buildId -or $info.apiContract -cne $verified.manifest.apiContract -or $info.transactionalMigrations -ne $true -or -not (Test-MigrationEquality $info.migrations $verified.manifest.schemaAfter)) {throw 'Candidate executable metadata is incompatible.'}
    # Stable launcher is our trusted maintenance delivery, not an arbitrary
    # package hook. A declared stable payload must match this exact launcher.
    $trustedLauncher=Join-Path $PSScriptRoot 'run-api.ps1'
    foreach ($file in $verified.manifest.files | Where-Object {$_.target -ceq 'stable'}) {if ($file.sha256 -cne (Get-UpdateFileHash $trustedLauncher)) {throw 'Stable launcher differs from authenticated maintenance tooling.'}}
    $targetLauncher=Join-Path $Control.root 'scripts/run-api.ps1';Assert-NoReparse $targetLauncher
    $operation.step='install-stable-launcher';Set-UpdateOperation $Control $operation
    $temp=$targetLauncher+'.'+[Guid]::NewGuid().ToString('N')+'.update';[IO.File]::Copy($trustedLauncher,$temp,$false)
    [IO.File]::Replace($temp,$targetLauncher,[NullString]::Value)
    # Service launcher reads the candidate; it may not write release files.
    & icacls.exe $release /grant '*S-1-5-19:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'Cannot grant service read access to immutable candidate.'}
    [pscustomobject]@{releasePath=$release;manifest=$verified.manifest;archiveSha256=$ExpectedSha256;manifestSha256=(Get-UpdateFileHash (Join-Path $release 'manifest.json'))}
}
function Set-ApplicationUpdateSelector($Control,$Candidate) {
    $operation=Read-UpdateJson $Control.operationPath
    if ($operation.phase -cne 'Applying') {throw 'Selector requires Applying.'}
    $selector=[pscustomobject]@{format=1;releaseId=$Candidate.manifest.releaseId;path=('releases/'+$Candidate.manifest.releaseId);manifestSha256=$Candidate.manifestSha256}
    $operation.step='select-candidate';Set-UpdateOperation $Control $operation
    Write-PrivateUpdateJson (Join-Path $Control.root 'config/active-release.json') $selector
    # Match the initial configuration's service-readable selector access.
    & icacls.exe (Join-Path $Control.root 'config/active-release.json') /grant '*S-1-5-19:R' | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'Cannot grant service read access to selector.'}
}
function Invoke-ApplicationUpdateMigration($Control,$Candidate) {
    $settings=Read-UpdateJson (Join-Path $Control.root 'config/api.json')
    $previous=[Environment]::GetEnvironmentVariable('DATABASE_URL','Process')
    try {
        $env:DATABASE_URL='postgres://propiedades:'+[Uri]::EscapeDataString($settings.ApiDbPassword)+'@127.0.0.1:'+$settings.PgPort+'/propiedades'
        $operation=Read-UpdateJson $Control.operationPath;$operation.step='migrate-candidate';Set-UpdateOperation $Control $operation
        $null=& (Join-Path $Candidate.releasePath 'bin/propiedades-backend.exe') --migrate-only --install-root $Control.root 2>&1
        if ($LASTEXITCODE -ne 0) {throw 'Candidate migration failed; coherent recovery required.'}
    }finally {[Environment]::SetEnvironmentVariable('DATABASE_URL',$previous,'Process')}
}
function Wait-UpdateIdentity($Control,[ValidateRange(1,180)][int]$Attempts=120,[ValidateRange(0,5)][int]$DelaySeconds=1) {
    $settings=Read-UpdateJson (Join-Path $Control.root 'config/api.json')
    $issuer='http://127.0.0.1:'+$settings.KeycloakPort+'/realms/propiedades'
    for ($attempt=0;$attempt -lt $Attempts;$attempt++) {
        try {
            $response=Invoke-WebRequest -UseBasicParsing -Uri ($issuer+'/.well-known/openid-configuration') -TimeoutSec 2 -MaximumRedirection 0 -ErrorAction Stop
            if ($response.StatusCode -eq 200 -and (ConvertFrom-UpdateJson $response.Content).issuer -ceq $issuer) {return}
        } catch {}
        if ($attempt+1 -lt $Attempts -and $DelaySeconds) {Start-Sleep -Seconds $DelaySeconds}
    }
    throw 'Keycloak readiness timed out; credentials were not submitted.'
}
function Get-UpdateOwnerToken($Control,[pscredential]$Credential) {
    $settings=Read-UpdateJson (Join-Path $Control.root 'config/api.json')
    Wait-UpdateIdentity $Control
    $password=$Credential.GetNetworkCredential().Password
    try {
        $body=@{grant_type='password';scope='openid';client_id='portal-login';client_secret=$settings.LoginSecret;username=$Credential.GetNetworkCredential().UserName;password=$password}
        $response=Invoke-WebRequest -UseBasicParsing -Method POST -Uri ('http://127.0.0.1:'+$settings.KeycloakPort+'/realms/propiedades/protocol/openid-connect/token') -Body $body -TimeoutSec 20 -MaximumRedirection 0
        $tokens=ConvertFrom-UpdateJson $response.Content
        if ($tokens.access_token -isnot [string] -or -not $tokens.access_token) {throw 'No access token.'}
        return $tokens.access_token
    }catch {
        $status=$null
        $responseProperty=$_.Exception.PSObject.Properties['Response']
        if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {$status=[int]$responseProperty.Value.StatusCode}
        if ($status -in @(400,401,403)) {throw ('Existing owner authentication rejected (HTTP '+$status+'); check test username/password locally.')}
        throw 'Existing owner identity unavailable; credentials and response body omitted.'
    }finally {$password=$null;if ($body) {$body.password=$null;$body.client_secret=$null}}
}
function Test-ApplicationUpdateFlows($Control,$Manifest,[pscredential]$Credential,[switch]$Recovery) {
    $settings=Read-UpdateJson (Join-Path $Control.root 'config/api.json')
    $operation=Read-UpdateJson $Control.operationPath
    $local='http://127.0.0.1:'+$settings.ApiPort
    $rehearsal=(Get-UpdateVerificationMode $Control) -ceq 'LocalRehearsal'
    if ($rehearsal) {Assert-LocalRehearsal $Control.root}
    $token=Get-UpdateOwnerToken $Control $Credential;$headers=@{Authorization=('Bearer '+$token)}
    $version=Invoke-UpdateHttp ($local+'/api/v1/system/version') 'GET' $null $headers
    $expected=if ($Recovery) {$operation.sourceReleaseId}else{$operation.targetReleaseId}
    if ($version.releaseId -cne $expected -or $version.operational -ne $false -or $version.apiContract -cne $Manifest.apiContract) {throw 'Protected API version/maintenance contract differs.'}
    $identity=Invoke-UpdateHttp ($local+'/api/v1/me') 'GET' $null $headers
    if ($identity.sub -cne $settings.OwnerSubject) {throw 'Owner subject changed.'}
    foreach ($collection in @('edificios','propiedades','inquilinos','incidencias','documentos')) {$null=Invoke-UpdateHttp ($local+'/api/v1/'+$collection+'?limit=1') 'GET' $null $headers}
    if (-not $rehearsal) {
    Assert-UpdatePortal $settings.PortalOrigin $Control.root
    $frontend=Invoke-UpdateHttp ($settings.PortalOrigin+'/release.json')
    if ($frontend.apiContract -cne $Manifest.apiContract -or @($Manifest.supportedFrontends | Where-Object {$_.id -ceq $frontend.releaseId}).Count -ne 1) {throw 'Portal frontend is not supported.'}
    $portalVersion=Invoke-UpdateHttp ($settings.PortalOrigin+'/api/v1/system/version') 'GET' $null $headers
    if ($portalVersion.releaseId -cne $expected -or $portalVersion.instanceId -cne $version.instanceId) {throw 'Portal/Worker/tunnel did not reach verified API instance.'}
    # Exercise the actual browser login route in addition to the local token.
    $session=New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $password=$Credential.GetNetworkCredential().Password
    try {
        $null=Invoke-WebRequest -UseBasicParsing -Method POST -Uri ($settings.PortalOrigin+'/api/v1/session/login') -Headers @{Origin=$settings.PortalOrigin} -Body (@{username=$Credential.GetNetworkCredential().UserName;password=$password}|ConvertTo-Json -Compress) -ContentType 'application/json' -WebSession $session -MaximumRedirection 0 -TimeoutSec 20
        $response=Invoke-WebRequest -UseBasicParsing -Uri ($settings.PortalOrigin+'/api/v1/me') -WebSession $session -MaximumRedirection 0 -TimeoutSec 20
        if ((ConvertFrom-UpdateJson $response.Content).sub -cne $settings.OwnerSubject) {throw 'Portal owner mismatch.'}
        $null=Invoke-WebRequest -UseBasicParsing -Method POST -Uri ($settings.PortalOrigin+'/api/v1/session/logout') -Headers @{Origin=$settings.PortalOrigin} -WebSession $session -MaximumRedirection 0 -TimeoutSec 20
    }catch {throw 'Portal session/login route could not be verified.'}finally {$password=$null}
    } else {
        Test-UpdateLocalSession $Control $Credential
    }
    if ($Recovery) {return [pscustomobject]@{status='RecoveredFlowsVerified';instanceId=$version.instanceId}}
    $fixtures=@([pscustomobject]@{collection='propiedades';id=('maintenance-'+$operation.operationId+'-property')},[pscustomobject]@{collection='edificios';id=('maintenance-'+$operation.operationId+'-building')})
    $null=Set-DiagnosticGrant $Control $version.instanceId $fixtures
    $grant=Read-UpdateJson (Join-Path $Control.root 'maintenance/diagnostic.json')
    $diagnostic=@{Authorization=('Bearer '+$token);'x-aelium-operation'=$operation.operationId;'x-aelium-capability'=$grant.nonce;'x-aelium-fixture'=$fixtures[0].id}
    $created=$false;$cleaned=$false;$recordVersion=1;$createdBuilding=$false;$buildingVersion=1
    try {
        $route=if ($rehearsal) {$local}else{$settings.PortalOrigin}
        $diagnostic['x-aelium-fixture']=$fixtures[1].id
        $building=Invoke-UpdateHttp ($route+'/api/v1/edificios') 'POST' @{nombre='Comprobación de edificio'} $diagnostic
        $createdBuilding=$true;$buildingVersion=$building.version
        if ($building.id -cne $fixtures[1].id) {throw 'Unexpected building fixture identity.'}
        $diagnostic['x-aelium-fixture']=$fixtures[0].id
        $createdRecord=Invoke-UpdateHttp ($route+'/api/v1/propiedades') 'POST' @{nombre='Comprobación de actualización';edificioId=$fixtures[1].id} $diagnostic
        $created=$true;$recordVersion=$createdRecord.version
        if ($createdRecord.id -cne $fixtures[0].id) {throw 'Unexpected fixture identity.'}
        $read=Invoke-UpdateHttp ($route+'/api/v1/propiedades/'+$fixtures[0].id) 'GET' $null $diagnostic
        if ($read.id -cne $fixtures[0].id) {throw 'Fixture read failed.'}
        $changed=Invoke-UpdateHttp ($route+'/api/v1/propiedades/'+$fixtures[0].id) 'PATCH' @{nombre='Comprobación actualizada';version=$recordVersion} $diagnostic
        $recordVersion=$changed.version
    } finally {
        if ($created) {$null=Invoke-UpdateHttp ($local+'/api/v1/propiedades/'+$fixtures[0].id+'?version='+$recordVersion) 'DELETE' $null $diagnostic;$cleaned=$true}
        if ($createdBuilding) {
            $diagnostic['x-aelium-fixture']=$fixtures[1].id
            $null=Invoke-UpdateHttp ($local+'/api/v1/edificios/'+$fixtures[1].id+'?version='+$buildingVersion) 'DELETE' $null $diagnostic
        }
        $pg=Get-UpdatePg $Control
        # This ID is generated internally, validated by the diagnostic grant.
        $id=$fixtures[0].id.Replace("'","''")
        $residue=Invoke-UpdateSql $pg 'propiedades' ("SELECT (SELECT count(*) FROM entities WHERE id='"+$id+"')+(SELECT count(*) FROM audit_events WHERE resource_id='"+$id+"')")
        if ($residue -cne '0' -or ($created -and -not $cleaned)) {throw 'Diagnostic cleanup not verified; cannot commit.'}
        $id=$fixtures[1].id.Replace("'","''")
        $residue=Invoke-UpdateSql $pg 'propiedades' ("SELECT (SELECT count(*) FROM entities WHERE id='"+$id+"')+(SELECT count(*) FROM audit_events WHERE resource_id='"+$id+"')")
        if ($residue -cne '0') {throw 'Building diagnostic cleanup not verified; cannot commit.'}
        $diagnostic=$null;$grant=$null;$token=$null
    }
    [pscustomobject]@{status='UpdateFlowsVerified';instanceId=$version.instanceId;portalChecked=(-not $rehearsal);cleanupChecked=$true}
}

function Test-UpdateLocalSession($Control,[pscredential]$Credential) {
    # Exercise real session endpoints on loopback. Send Secure cookie manually
    # only here; this is a diagnostic, not evidence of HTTPS/browser behavior.
    $settings=Read-UpdateJson (Join-Path $Control.root 'config/api.json')
    $base='http://127.0.0.1:'+$settings.ApiPort
    Add-Type -AssemblyName System.Net.Http
    $handler=New-Object Net.Http.HttpClientHandler;$handler.UseCookies=$false;$handler.AllowAutoRedirect=$false
    $client=New-Object Net.Http.HttpClient($handler);$client.Timeout=[TimeSpan]::FromSeconds(20)
    $cookie=$null;$loggedOut=$false
    try {
        $request=New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Post,($base+'/api/v1/session/login'))
        try {
            $null=$request.Headers.TryAddWithoutValidation('Origin',$settings.PortalOrigin)
            $json=@{username=$Credential.GetNetworkCredential().UserName;password=$Credential.GetNetworkCredential().Password}|ConvertTo-Json -Compress
            $request.Content=New-Object Net.Http.StringContent($json,[Text.Encoding]::UTF8,'application/json');$json=$null
            $response=$client.SendAsync($request).GetAwaiter().GetResult()
            try {
                if ([int]$response.StatusCode -ne 200 -or -not $response.Headers.Contains('Set-Cookie')) {throw 'Local login failed.'}
                $cookies=@($response.Headers.GetValues('Set-Cookie'))
                if ($cookies.Count -ne 1 -or $cookies[0] -notmatch 'HttpOnly' -or $cookies[0] -notmatch 'Secure') {throw 'Local cookie protections differ.'}
                $cookie=($cookies[0] -split ';')[0]
            } finally {$response.Dispose()}
        } finally {$request.Dispose();$json=$null}
        foreach ($step in @('identity','logout','rejected')) {
            $url=if ($step -ceq 'logout') {$base+'/api/v1/session/logout'}else{$base+'/api/v1/me'}
            $method=if ($step -ceq 'logout') {[Net.Http.HttpMethod]::Post}else{[Net.Http.HttpMethod]::Get}
            $request=New-Object Net.Http.HttpRequestMessage($method,$url)
            try {
                $null=$request.Headers.TryAddWithoutValidation('Cookie',$cookie)
                $null=$request.Headers.TryAddWithoutValidation('Origin',$settings.PortalOrigin)
                $response=$client.SendAsync($request).GetAwaiter().GetResult()
                try {
                    $expected=if ($step -ceq 'rejected') {401}else{200}
                    if ([int]$response.StatusCode -ne $expected) {throw 'Local session verification failed.'}
                    if ($step -ceq 'logout') {$loggedOut=$true}
                    if ($step -ceq 'identity' -and (ConvertFrom-UpdateJson ($response.Content.ReadAsStringAsync().GetAwaiter().GetResult())).sub -cne $settings.OwnerSubject) {throw 'Local session identity differs.'}
                } finally {$response.Dispose()}
            } finally {$request.Dispose()}
        }
    } finally {
        if ($cookie -and -not $loggedOut) {
            $request=New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Post,($base+'/api/v1/session/logout'))
            try {
                $null=$request.Headers.TryAddWithoutValidation('Cookie',$cookie)
                $null=$request.Headers.TryAddWithoutValidation('Origin',$settings.PortalOrigin)
                $response=$client.SendAsync($request).GetAwaiter().GetResult();$response.Dispose()
            } catch {} finally {$request.Dispose()}
        }
        $cookie=$null;$client.Dispose();$handler.Dispose()
    }
}

function Set-ApplicationUpdatePhase($Control,[string]$Phase,[string]$Step,[bool]$Checks=$false) {
    $operation=Read-UpdateJson $Control.operationPath;$operation.phase=$Phase;$operation.step=$Step;$operation.checksPassed=$Checks
    Set-UpdateOperation $Control $operation
}
function Wait-UpdateApi($Control) {
    $settings=Read-UpdateJson (Join-Path $Control.root 'config/api.json')
    for ($i=0;$i -lt 90;$i++) {
        try {$response=Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:'+$settings.ApiPort+'/health/live') -TimeoutSec 2 -MaximumRedirection 0;if ($response.StatusCode -eq 200) {return}}catch {}
        Start-Sleep -Seconds 1
    }
    throw 'API startup timed out; maintenance remains active.'
}
function Invoke-UpdateWriterAction($Control,[string]$Action,$FixtureHooks=$null,[switch]$IdentityOnly) {
    if (Test-UpdateFixtureRoot $Control.root) {
        if ($null -eq $FixtureHooks -or $FixtureHooks.start -isnot [scriptblock] -or $FixtureHooks.stop -isnot [scriptblock]) {throw 'Fixture process lifecycle hooks required; production entry never accepts hooks.'}
        if ($Action -ceq 'stop') {& $FixtureHooks.stop $Control}else{& $FixtureHooks.start $Control}
        return
    }
    if ($Action -ceq 'stop') {$null=Suspend-UpdateWriters $Control}
    else {$null=Start-UpdateVerificationWriters $Control -IncludeTunnel:(-not $IdentityOnly) -IdentityOnly:$IdentityOnly}
}
function Test-LegacyRecoveryIdentity($Control,$Context,[pscredential]$Credential) {
    # Old launchers have no write guard. Keep their API and tunnel stopped;
    # verify the restored DB/config/identity set before enabling them at all.
    $settings=Read-UpdateJson (Join-Path $Control.root 'config/api.json')
    $token=Get-UpdateOwnerToken $Control $Credential
    try {
        $user=Invoke-UpdateHttp ('http://127.0.0.1:'+$settings.KeycloakPort+'/realms/propiedades/protocol/openid-connect/userinfo') 'GET' $null @{Authorization=('Bearer '+$token)}
        if ($user.sub -cne $settings.OwnerSubject) {throw 'Restored identity differs.'}
        $source=@($Context.catalog.sources | Where-Object {$_.sourceId -ceq $Context.sourceId})[0]
        Assert-InstalledFiles $Control.root $source.files
        $history=@(Get-UpdateSchema (Get-UpdatePg $Control) | ForEach-Object {[pscustomobject]@{version=$_.version;checksum=$_.checksum}})
        if (-not (Test-MigrationEquality $history $Context.manifest.schemaBefore)) {throw 'Restored schema differs.'}
        if ((Get-UpdateVerificationMode $Control) -cne 'LocalRehearsal') {
            $frontend=Invoke-UpdateHttp ($settings.PortalOrigin+'/release.json')
            if ($frontend.releaseId -cne $Context.observation.frontend -or $frontend.apiContract -cne $Context.observation.apiContract) {throw 'Legacy frontend evidence differs.'}
        }
    }finally {$token=$null}
}
function Invoke-ApplicationUpdateRecovery($Control,$Context,[pscredential]$Credential,$FixtureHooks=$null) {
    $operation=Read-UpdateJson $Control.operationPath
    if ($operation.phase -cin @('Committed','Recovered')) {throw 'Terminal operation cannot restore an old backup; preserve later writes.'}
    Set-ApplicationUpdatePhase $Control 'Recovering' 'protect-recovery'
    Invoke-UpdateWriterAction $Control 'stop' $FixtureHooks
    if ($Context.applicationChangeStarted) {
        $null=Restore-CoherentUpdateBackup $Control
    } else {
        # Before Applying nothing in the update flow alters application/data.
        # Do not restore an older copy over writes made before a partial cut.
        $source=@($Context.catalog.sources | Where-Object {$_.sourceId -ceq $Context.sourceId})[0]
        Assert-InstalledFiles $Control.root $source.files
        $history=@(Get-UpdateSchema (Get-UpdatePg $Control) | ForEach-Object {[pscustomobject]@{version=$_.version;checksum=$_.checksum}})
        if (-not (Test-MigrationEquality $history $Context.manifest.schemaBefore)) {throw 'Original schema is not intact.'}
    }
    $legacy=$Context.sourceId.StartsWith('legacy-',[StringComparison]::Ordinal)
    Invoke-UpdateWriterAction $Control 'start' $FixtureHooks -IdentityOnly:$legacy
    if ($legacy) {Test-LegacyRecoveryIdentity $Control $Context $Credential}
    else {
        Wait-UpdateApi $Control
        $sourceManifest=[pscustomobject]@{apiContract=$Context.observation.apiContract;supportedFrontends=$Context.manifest.supportedFrontends}
        $null=Test-ApplicationUpdateFlows $Control $sourceManifest $Credential -Recovery
    }
    Set-ApplicationUpdatePhase $Control 'Recovered' 'recovered-checks-complete' $true
    if (-not (Test-UpdateFixtureRoot $Control.root)) {$null=Restore-UpdateWriters $Control}
    [pscustomobject]@{status='UpdateFailedRecovered';operationId=$operation.operationId;releaseId=$operation.sourceReleaseId;backupReference=$operation.backupReference;updateSucceeded=$false}
}
function Test-LocalIdentityRuntimeProfile($Control) {
    # Experimental conservation profile: never used for production acceptance.
    if ((Get-UpdateVerificationMode $Control) -cne 'LocalRehearsal') {return $false}
    $pins=@{
        'org.keycloak.keycloak-model-jpa-26.7.4.jar'='f5d0f579e25e6714a225047329f7d89f1cd8db4a0f89c72071c9f849c9598748'
        'org.keycloak.keycloak-model-infinispan-26.7.4.jar'='935ba54b52f9656eaf35751f23311b569246394ca71ffbf356d111f7a828a5ee'
    }
    foreach($name in $pins.Keys){
        $path=Join-Path $Control.root ('keycloak/lib/lib/main/'+$name)
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $false}
        Assert-NoReparse $path
        if((Get-UpdateFileHash $path) -cne $pins[$name]){throw 'Unreviewed local identity runtime.'}
    }
    Assert-LocalRehearsal $Control.root
    return $true
}
function Get-LocalIdentityRuntimeProjection($Pg) {
    # Keep all offline sessions (flag 1) and all server configuration except
    # the single monotonic JGroups address counter. crt_jgroups stays strict.
    # Full dumps/restoration fingerprints are deliberately NOT projected.
    $sql=@'
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '10s';
SET LOCAL lock_timeout = '2s';
SELECT json_build_object(
 'unknownFlags', (SELECT count(*) FROM public.offline_user_session WHERE offline_flag IS NULL OR offline_flag NOT IN ('0','1')) + (SELECT count(*) FROM public.offline_client_session WHERE offline_flag IS NULL OR offline_flag NOT IN ('0','1')),
 'offlineUsers', (SELECT count(*)::text||':'||md5(coalesce(string_agg(h,'' ORDER BY h),'')) FROM (SELECT md5(row_to_json(t)::text) h FROM public.offline_user_session t WHERE offline_flag = '1') r),
 'offlineClients', (SELECT count(*)::text||':'||md5(coalesce(string_agg(h,'' ORDER BY h),'')) FROM (SELECT md5(row_to_json(t)::text) h FROM public.offline_client_session t WHERE offline_flag = '1') r),
 'serverConfig', (SELECT count(*)::text||':'||md5(coalesce(string_agg(h,'' ORDER BY h),'')) FROM (SELECT md5(row_to_json(t)::text) h FROM public.server_config t WHERE server_config_key IS DISTINCT FROM 'JGROUPS_ADDRESS_SEQUENCE') r),
 'counterRows', (SELECT count(*) FROM public.server_config WHERE server_config_key = 'JGROUPS_ADDRESS_SEQUENCE'),
 'counter', (SELECT value FROM public.server_config WHERE server_config_key = 'JGROUPS_ADDRESS_SEQUENCE'),
 'counterVersion', (SELECT version FROM public.server_config WHERE server_config_key = 'JGROUPS_ADDRESS_SEQUENCE')
);
COMMIT;
'@
    $raw=Invoke-UpdatePg $Pg 'psql.exe' @('-X','-q','-h','127.0.0.1','-p',[string]$Pg.port,'-U',$Pg.user,'-d','keycloak','-v','ON_ERROR_STOP=1','-At','-f','-') $sql 20
    $projection=ConvertFrom-UpdateJson $raw
    Assert-LocalIdentityRuntimeProjection $projection
    return $projection
}
function Assert-LocalIdentityRuntimeProjection($Projection) {
    Assert-Fields $Projection @('unknownFlags','offlineUsers','offlineClients','serverConfig','counterRows','counter','counterVersion')
    if($Projection.unknownFlags -ne 0 -or $Projection.counterRows -ne 1 -or $Projection.counter -isnot [string] -or $Projection.counter -cnotmatch '^(0|[1-9][0-9]{0,18})$'){throw 'Unrecognized identity runtime state.'}
    $counter=[long]0
    if(-not [long]::TryParse($Projection.counter,[ref]$counter) -or $counter -lt 0 -or $Projection.counterVersion -isnot [int] -or $Projection.counterVersion -lt 0){throw 'Invalid identity runtime counter.'}
    foreach($field in @('offlineUsers','offlineClients','serverConfig')){if($Projection.$field -isnot [string] -or $Projection.$field -cnotmatch '^[0-9]+:[0-9a-f]{32}$'){throw 'Invalid protected identity fingerprint.'}}
}
function Test-LocalIdentityRuntimeProjection($Before,$After) {
    Assert-LocalIdentityRuntimeProjection $Before
    Assert-LocalIdentityRuntimeProjection $After
    if([long]$After.counter -lt [long]$Before.counter -or $After.counterVersion -lt $Before.counterVersion){return $false}
    foreach($field in @('offlineUsers','offlineClients','serverConfig')){if($Before.$field -cne $After.$field){return $false}}
    return $true
}
function New-LocalIdentityRuntimeBaseline($Control) {
    if(-not(Test-LocalIdentityRuntimeProfile $Control)){return}
    $backup=Read-CoherentUpdateBackup $Control
    if(-not $backup.manifest.verified){throw 'Verified full backup required before local projection.'}
    $db=@($backup.manifest.databases|Where-Object{$_.metadata.name -ceq 'keycloak'})[0]
    $pg=Get-UpdatePg $Control
    $current=Get-UpdateDataFingerprint $pg 'keycloak' -LogicalColumns:($backup.manifest.format -eq 2)
    if(($current|ConvertTo-Json -Depth 12 -Compress) -cne ($db.fingerprint|ConvertTo-Json -Depth 12 -Compress)){throw 'Identity changed before local baseline capture.'}
    $projection=Get-LocalIdentityRuntimeProjection $pg
    Write-ControlJson $Control (Join-Path $Control.root 'maintenance/local-identity-baseline.json') ([pscustomobject]@{format=1;policyId='keycloak-26.7.4-local-runtime-v1';operationId=$backup.manifest.operationId;projection=$projection})
}
function Test-ApplicationUpdateConservation($Control) {
    $backup=Read-CoherentUpdateBackup $Control;$pg=Get-UpdatePg $Control
    if ((Get-UpdateRoleFingerprint $pg) -cne $backup.manifest.rolesFingerprint -or (Get-UpdateMembershipFingerprint $pg) -cne $backup.manifest.membershipsFingerprint) {throw 'Roles changed during application update.'}
    $changed=@()
    $localRuntime=Test-LocalIdentityRuntimeProfile $Control
    $localBaseline=$null
    if($localRuntime){
        $localBaseline=Read-UpdateJson (Join-Path $Control.root 'maintenance/local-identity-baseline.json')
        Assert-Fields $localBaseline @('format','policyId','operationId','projection')
        if($localBaseline.format -ne 1 -or $localBaseline.policyId -cne 'keycloak-26.7.4-local-runtime-v1' -or $localBaseline.operationId -cne $backup.manifest.operationId){throw 'Local identity baseline does not belong to this operation.'}
        if(-not(Test-LocalIdentityRuntimeProjection $localBaseline.projection (Get-LocalIdentityRuntimeProjection $pg))){throw 'Protected offline sessions or server configuration changed.'}
    }
    foreach ($db in $backup.manifest.databases) {
        $current=Get-UpdateDataFingerprint $pg $db.metadata.name -LogicalColumns:($backup.manifest.format -eq 2)
        if($localRuntime -and $db.metadata.name -ceq 'keycloak' -and $current.structure -cne $db.fingerprint.structure){throw 'Identity database structure changed.'}
        foreach ($table in $db.fingerprint.tables) {
            if ($db.metadata.name -ceq 'propiedades' -and $table.table -ceq '_sqlx_migrations' -and $table.schema -ceq 'public') {continue}
            $matches=@($current.tables | Where-Object {$_.schema -ceq $table.schema -and $_.table -ceq $table.table})
            if($localRuntime -and $db.metadata.name -ceq 'keycloak' -and $table.schema -ceq 'public' -and $table.table -cin @('jgroups_ping','offline_user_session','offline_client_session','server_config') -and $matches.Count -eq 1){continue}
            if ($matches.Count -ne 1 -or $matches[0].digest -cne $table.digest) {
                $changed += [pscustomobject]@{database=$db.metadata.name;schema=$table.schema;table=$table.table;presentExactlyOnce=($matches.Count -eq 1)}
            }
        }
        if ($current.largeObjects -cne $db.fingerprint.largeObjects) {throw 'Database attachments changed.'}
    }
    if($changed.Count){
        # Preserve only affected table identities, never row contents or hashes,
        # before recovery replaces the failed candidate databases.
        try{
            $operation=Read-UpdateJson $Control.operationPath
            Write-ControlJson $Control (Join-Path $Control.root 'maintenance/conservation-failure.json') ([pscustomobject]@{format=1;operationId=$operation.operationId;reasonCode='ExistingDataChanged';tables=$changed})
        }catch{}
        throw 'Existing business/identity data changed; cannot commit automatically.'
    }
    foreach ($item in $backup.manifest.files | Where-Object {-not $_.directory -and $_.path -cmatch '^(config|services|keycloak/conf|attachments)/' -and $_.path -cne 'config/active-release.json'}) {
        if ((Get-UpdateFileHash (Join-Path $Control.root $item.path)) -cne $item.sha256) {throw 'Persistent configuration/attachments changed.'}
    }
}
function Complete-ApplicationUpdate($Control,$Context,[pscredential]$Credential,$FixtureHooks=$null) {
    $operation=Read-UpdateJson $Control.operationPath
    if ($operation.phase -cne 'Verifying') {throw 'Only a verifying operation can commit.'}
    Invoke-UpdateWriterAction $Control 'start' $FixtureHooks;Wait-UpdateApi $Control
    try {$null=Test-ApplicationUpdateFlows $Control $Context.manifest $Credential}
    catch {
        # A stopped/unavailable portal or wrong password is retryable, but never
        # success. Backend continues to reject normal writes in Verifying.
        $operation=Read-UpdateJson $Control.operationPath;$operation.step='verification-pending';Set-UpdateOperation $Control $operation
        return [pscustomobject]@{status='VerificationPending';operationId=$operation.operationId;releaseId=$operation.targetReleaseId;backupReference=$operation.backupReference;updateSucceeded=$false}
    }
    Test-ApplicationUpdateConservation $Control
    $grant=Join-Path $Control.root 'maintenance/diagnostic.json';Assert-NoReparse $grant
    if (Test-Path -LiteralPath $grant) {[IO.File]::Delete($grant)}
    Write-ControlJson $Control (Join-Path $Control.root 'maintenance/applied-release.json') ([pscustomobject]@{format=1;releaseId=$Context.manifest.releaseId;archiveSha256=$Context.archiveSha256;operationId=$operation.operationId;verificationMode=(Get-UpdateVerificationMode $Control)})
    Set-ApplicationUpdatePhase $Control 'Committing' 'restore-service-options' $true
    if (-not (Test-UpdateFixtureRoot $Control.root)) {$null=Restore-UpdateWriters $Control}
    Set-ApplicationUpdatePhase $Control 'Committed' 'update-complete' $true
    [pscustomobject]@{status='UpdateSucceeded';operationId=$operation.operationId;releaseId=$operation.targetReleaseId;backupReference=$operation.backupReference;updateSucceeded=$true}
}
function Invoke-ApplicationUpdate([string]$Root,[string]$Action,[string]$Archive,[string]$ExpectedSha256,$Catalog,$Observation,$Inventory,[int]$VerificationPort,[pscredential]$Credential,$FixtureHooks=$null,[switch]$LocalRehearsal) {
    $root=[IO.Path]::GetFullPath($Root).TrimEnd('\');Assert-NoReparse $root
    if (-not (Test-UpdateFixtureRoot $root)) {Assert-ControlAdministrator}
    $mode=if ($LocalRehearsal) {'LocalRehearsal'}else{'Production'}
    if ($LocalRehearsal) {Assert-LocalRehearsal $root}
    elseif (Test-Path -LiteralPath (Join-Path $root 'config/local-rehearsal.json')) {throw 'A marked rehearsal installation requires the explicit LocalRehearsal switch.'}
    if ($Action -cin @('Preflight','Apply')) {
        $preflight=Test-ApplicationUpdatePreflight $root $Archive $ExpectedSha256 $Catalog $Observation $Inventory -LocalRehearsal:$LocalRehearsal
        if ($preflight.status -ceq 'AlreadyApplied') {return Get-UpdateResult 'AlreadyApplied' ([pscustomobject]@{releaseId=$preflight.releaseId;updateSucceeded=$true}) $mode}
        if ($Action -ceq 'Preflight') {return Get-UpdateResult $preflight.status ([pscustomobject]@{releaseId=$preflight.manifest.releaseId;updateSucceeded=$false}) $mode}
    }
    if ($null -eq $Credential) {throw 'Existing owner credentials required before maintenance begins.'}
    $control=Open-UpdateControl $root
    $control | Add-Member -NotePropertyName verificationMode -NotePropertyValue $mode
    try {
        $contextPath=Join-Path $root 'maintenance/context.json'
        if ($Action -ceq 'Apply') {
            # Recheck under exclusion: preflight observations can become stale
            # while waiting for the lock. A new first adoption has only our two
            # newly opened control files at this point.
            $preflight=Test-ApplicationUpdatePreflight $root $Archive $ExpectedSha256 $Catalog $Observation $Inventory -ControlHeld -LocalRehearsal:$LocalRehearsal
            if ($preflight.status -ceq 'AlreadyApplied') {return Get-UpdateResult 'AlreadyApplied' ([pscustomobject]@{releaseId=$preflight.releaseId;updateSucceeded=$true}) $mode}
            $operation=[pscustomobject]@{format=1;operationId=('update-'+[Guid]::NewGuid().ToString('N'));phase='Preflight';sourceReleaseId=$preflight.sourceId;targetReleaseId=$preflight.manifest.releaseId;backupReference=$null;checksPassed=$false;step='preflight-verified';services=@()}
            Set-UpdateOperation $control $operation
            $context=[pscustomobject]@{format=1;operationId=$operation.operationId;sourceId=$preflight.sourceId;manifest=$preflight.manifest;archiveSha256=$ExpectedSha256;catalog=$Catalog;observation=$Observation;inventory=$Inventory;applicationChangeStarted=$false;verificationMode=$mode}
            Write-ControlJson $control $contextPath $context
            try {
                Set-ApplicationUpdatePhase $control 'Quiescing' 'protect-writers'
                Invoke-UpdateWriterAction $control 'stop' $FixtureHooks
                Set-ApplicationUpdatePhase $control 'BackingUp' 'capture-coherent-backup'
                $null=New-CoherentUpdateBackup $control $Inventory
                $null=Test-CoherentUpdateBackup $control $VerificationPort
                New-LocalIdentityRuntimeBaseline $control
                Set-ApplicationUpdatePhase $control 'Applying' 'prepare-application-change'
                # Durable intent BEFORE changing launcher, schema or selector.
                $context.applicationChangeStarted=$true;Write-ControlJson $control $contextPath $context
                $candidate=Expand-ApplicationUpdate $control $Archive $ExpectedSha256
                Invoke-ApplicationUpdateMigration $control $candidate
                Set-ApplicationUpdateSelector $control $candidate
                Set-ApplicationUpdatePhase $control 'Verifying' 'verify-application'
                $result=Complete-ApplicationUpdate $control $context $Credential $FixtureHooks
                return Get-UpdateResult $result.status $result $mode
            }catch {
                $initialFailure=$_
                # Preserve the original failure before recovery can replace the
                # last step. Only allowlisted diagnostics, never raw responses.
                try {
                $initial=Read-UpdateJson $control.operationPath
                $reason='UpdateStepFailed'
                foreach ($known in @('Isolated restored data differs from backup baseline.','Active cluster roles changed.','Isolated PostgreSQL startup failed.','Database maintenance command timed out.','Database changed during backup.','File changed or copied incorrectly.')) {
                    if ($initialFailure.Exception.Message -ceq $known) {$reason=$known;break}
                }
                Write-ControlJson $control (Join-Path $control.root 'maintenance/initial-failure.json') ([pscustomobject]@{format=1;operationId=$initial.operationId;failureStep=$initial.step;reasonCode=$reason;trace=$initialFailure.ScriptStackTrace})
                } catch {} # An unavailable diagnostic file must not prevent recovery.
                try {$result=Invoke-ApplicationUpdateRecovery $control $context $Credential $FixtureHooks;return Get-UpdateResult $result.status $result $mode}
                catch {
                    $failure=Read-UpdateJson $control.operationPath
                    Write-ControlJson $control (Join-Path $control.root 'maintenance/recovery-failure.json') ([pscustomobject]@{format=1;operationId=$failure.operationId;failureStep=$failure.step;reasonCode='RecoveryChecksFailed';trace=$_.ScriptStackTrace})
                    Set-ApplicationUpdatePhase $control 'RecoveryRequired' 'recovery-required';return [pscustomobject]@{status='RecoveryRequired';operationId=$operation.operationId;failureStep=$failure.step;updateSucceeded=$false}
                }
            }
        }
        $context=Read-UpdateJson $contextPath
        if ((Get-UpdateVerificationMode $context) -cne $mode) {throw 'Resume/recovery must use the original verification mode.'}
        $operation=Read-UpdateJson $control.operationPath
        if ($context.format -ne 1 -or $context.operationId -cne $operation.operationId -or $context.sourceId -cne $operation.sourceReleaseId -or $context.manifest.releaseId -cne $operation.targetReleaseId) {throw 'Persisted update context is inconsistent.'}
        if ($Action -ceq 'Finalize') {$result=Complete-ApplicationUpdate $control $context $Credential $FixtureHooks;return Get-UpdateResult $result.status $result $mode}
        if ($Action -ceq 'Recover') {
            if ($operation.phase -cin @('Committed','Recovered')) {return [pscustomobject]@{status='RecoveryNotPermitted';operationId=$operation.operationId;updateSucceeded=$false}}
            try {$result=Invoke-ApplicationUpdateRecovery $control $context $Credential $FixtureHooks;return Get-UpdateResult $result.status $result $mode}
            catch {
                $failure=Read-UpdateJson $control.operationPath
                Write-ControlJson $control (Join-Path $control.root 'maintenance/recovery-failure.json') ([pscustomobject]@{format=1;operationId=$failure.operationId;failureStep=$failure.step;reasonCode='RecoveryChecksFailed';trace=$_.ScriptStackTrace})
                Set-ApplicationUpdatePhase $control 'RecoveryRequired' 'recovery-required';return [pscustomobject]@{status='RecoveryRequired';operationId=$operation.operationId;failureStep=$failure.step;updateSucceeded=$false}
            }
        }
        throw 'Unsupported update action.'
    }finally {$control.lock.Dispose()}
}
