. (Join-Path $PSScriptRoot 'Package.ps1')
if (-not ('Aelium.Update.NativeServices' -as [type])) {Add-Type -Path (Join-Path $PSScriptRoot 'NativeServices.cs')}
function Assert-ControlAdministrator {
    $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'Service protection and diagnostic grants require an administrator.'}
}
function Assert-Operation($Operation) {
    Assert-Fields $Operation @('format','operationId','phase','sourceReleaseId','targetReleaseId','backupReference','checksPassed','step','services')
    if ($Operation.format -ne 1 -or $Operation.phase -cnotin @('Preflight','Quiescing','BackingUp','Applying','Verifying','Committing','Committed','Recovering','Recovered','RecoveryRequired') -or $Operation.checksPassed -isnot [bool] -or $Operation.services -isnot [array]) {throw 'Invalid operation record.'}
    Assert-UpdateId $Operation.operationId;Assert-UpdateId $Operation.targetReleaseId;Assert-UpdateId $Operation.step
    if ($Operation.sourceReleaseId -isnot [string] -or -not $Operation.sourceReleaseId -or $Operation.sourceReleaseId.Length -gt 160) {throw 'Invalid source identity.'}
    if ($Operation.phase -cin @('Committed','Recovered') -and -not $Operation.checksPassed) {throw 'Terminal operation requires verified checks.'}
}
function Open-UpdateControl([string]$InstallationRoot) {
    $root=[IO.Path]::GetFullPath($InstallationRoot).TrimEnd('\');Assert-NoReparse $root
    if (-not (Test-Path -LiteralPath (Join-Path $root 'config/settings.json') -PathType Leaf)) {throw 'Not an installation root.'}
    $maintenance=Join-Path $root 'maintenance';Assert-NoReparse $maintenance
    New-Item -ItemType Directory -Path $maintenance -Force | Out-Null
    Assert-NoReparse (Join-Path $maintenance 'update.lock')
    $lock=[IO.File]::Open((Join-Path $maintenance 'update.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $gate=Join-Path $maintenance 'write-gate.lock';Assert-NoReparse $gate
        if (-not (Test-Path -LiteralPath $gate)) {$stream=[IO.File]::Open($gate,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$stream.Dispose()}
        [pscustomobject]@{root=$root;lock=$lock;operationPath=(Join-Path $maintenance 'operation.json');gatePath=$gate}
    } catch {$lock.Dispose();throw}
}
function Write-ControlJson($Control,[string]$Path,$Value) {
    if (-not $Control.lock.CanWrite) {throw 'Update control is closed.'}
    Assert-NoReparse $Path
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)) -cne (Join-Path $Control.root 'maintenance')) {throw 'Control destination outside maintenance.'}
    $gate=[IO.File]::Open($Control.gatePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
    try {
        # Shared Rust locks cover this byte too. A conflicting request causes a
        # retryable failure; no phase is published until admitted writes finish.
        $gate.Lock(0,1)
        $temp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
        $stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {$bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(($Value|ConvertTo-Json -Depth 20));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        if (Test-Path -LiteralPath $Path) {[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    } finally {$gate.Dispose()}
}
function Set-UpdateOperation($Control,$Operation) {
    Assert-Operation $Operation
    if (Test-Path -LiteralPath $Control.operationPath) {
        $before=Read-UpdateJson $Control.operationPath;Assert-Operation $before
        if ($before.operationId -cne $Operation.operationId -and $before.phase -cnotin @('Committed','Recovered')) {throw 'Another incomplete operation must be recovered first.'}
        if ($before.operationId -cne $Operation.operationId -and $Operation.phase -cne 'Preflight') {throw 'New operation must begin with preflight.'}
        if ($before.operationId -ceq $Operation.operationId) {
            if ($before.sourceReleaseId -cne $Operation.sourceReleaseId -or $before.targetReleaseId -cne $Operation.targetReleaseId) {throw 'Operation identities cannot change.'}
            $transitions=@{
                Preflight=@('Preflight','Quiescing','RecoveryRequired');Quiescing=@('Quiescing','BackingUp','Recovering','RecoveryRequired')
                BackingUp=@('BackingUp','Applying','Recovering','RecoveryRequired');Applying=@('Applying','Verifying','Recovering','RecoveryRequired')
                Verifying=@('Verifying','Committing','Recovering','RecoveryRequired');Committing=@('Committing','Committed','Recovering','RecoveryRequired')
                Committed=@('Committed');Recovering=@('Recovering','Recovered','RecoveryRequired');Recovered=@('Recovered');RecoveryRequired=@('RecoveryRequired','Recovering')
            }
            if ($Operation.phase -cnotin $transitions[$before.phase]) {throw 'Invalid operation phase transition.'}
        }
    } elseif ($Operation.phase -cne 'Preflight') {throw 'First operation must begin with preflight.'}
    Write-ControlJson $Control $Control.operationPath $Operation
}
function Set-DiagnosticGrant($Control,[string]$InstanceId,$Fixtures) {
    Assert-ControlAdministrator
    $operation=Read-UpdateJson $Control.operationPath;Assert-Operation $operation
    if ($operation.phase -cne 'Verifying') {throw 'Diagnostic grant requires Verifying.'}
    Assert-UpdateId $InstanceId;Assert-UpdateList $Fixtures
    if ($Fixtures.Count -gt 16) {throw 'Too many fixtures.'}
    $seen=@{}
    foreach ($fixture in $Fixtures) {
        Assert-Fields $fixture @('collection','id');Assert-UpdatePath $fixture.id
        if ($fixture.collection -cnotin @('edificios','propiedades','inquilinos','incidencias','documentos') -or -not $fixture.id.StartsWith(('maintenance-'+$operation.operationId+'-'),[StringComparison]::Ordinal) -or $fixture.id.Length -gt 128 -or $fixture.id.Contains('/') -or $seen.ContainsKey($fixture.collection+'/'+$fixture.id)) {throw 'Invalid diagnostic fixture.'}
        $seen[$fixture.collection+'/'+$fixture.id]=$true
    }
    $bytes=New-Object byte[] 32;$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try {$rng.GetBytes($bytes)} finally {$rng.Dispose()}
    $nonce=[BitConverter]::ToString($bytes).Replace('-','').ToLowerInvariant()
    $grant=[pscustomobject]@{format=1;operationId=$operation.operationId;instanceId=$InstanceId;nonce=$nonce;fixtures=$Fixtures}
    $path=Join-Path $Control.root 'maintenance/diagnostic.json'
    # Secure the directory before any secret is written. No token is printed.
    $directory=[IO.DirectoryInfo](Join-Path $Control.root 'maintenance')
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($entry in @(@('S-1-5-18','FullControl'),@('S-1-5-32-544','FullControl'),@('S-1-5-19','ReadAndExecute'))) {
        $sid=New-Object Security.Principal.SecurityIdentifier($entry[0])
        $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,$entry[1],'ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule)
    }
    $actor=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($actor,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
    $directory.SetAccessControl($acl)
    Write-ControlJson $Control $path $grant
    [pscustomobject]@{status='DiagnosticGrantWritten';operationId=$operation.operationId;instanceId=$InstanceId;fixtureCount=$Fixtures.Count}
}
function Get-OwnedWriterServices($Control) {
    $result=@()
    foreach ($id in @('AeliumTunnel','AeliumAPI','AeliumKeycloak')) {
        $service=Get-CimInstance Win32_Service -Filter ("Name='"+$id+"'")
        if (-not $service) {if ($id -ceq 'AeliumTunnel') {continue};throw 'Required writer service missing.'}
        $expected=Join-Path $Control.root ('services/'+$id+'.exe');Assert-NoReparse $expected
        if ($service.PathName -ine $expected -and $service.PathName -ine ('"'+$expected+'"')) {throw 'Service is outside the verified installation layout.'}
        if ($service.StartName -inotmatch '^(NT AUTHORITY\\)?LocalService$' -or $service.State -cnotin @('Running','Stopped')) {throw 'Unsupported service account or state.'}
        $result += [pscustomobject]@{id=$id;state=$service.State;options=[Aelium.Update.NativeServices]::Read($id)}
    }
    return $result
}
function Stop-UpdateWriterService($Service,[ValidateRange(1,600)][int]$TimeoutSeconds=90) {
    $Service.Refresh()
    if($Service.Status -eq 'Stopped'){return}
    # Stop-Service waits internally before returning, so a WaitForStatus after
    # it never bounded that wait. Request the stop directly, then wait once.
    if($Service.Status -ne 'StopPending'){
        # ServiceController.Stop can recursively stop dependents. Never let a
        # direct stop take down services outside the already-quiesced inventory.
        if(@($Service.DependentServices|Where-Object{$_.Status -ne 'Stopped'}).Count){throw 'Dependent service still active; refusing recursive service stop.'}
        $Service.Stop()
    }
    $Service.WaitForStatus('Stopped',[TimeSpan]::FromSeconds($TimeoutSeconds))
}
function Suspend-UpdateWriters($Control) {
    Assert-ControlAdministrator
    $operation=Read-UpdateJson $Control.operationPath;Assert-Operation $operation
    if ($operation.phase -cnotin @('Quiescing','Recovering')) {throw 'Writer protection requires Quiescing or Recovering.'}
    if ($operation.services.Count -eq 0) {
        $operation.services=@(Get-OwnedWriterServices $Control);$operation.step='services-inventoried';Set-UpdateOperation $Control $operation
    } else {
        # Resuming never replaces the original recovery/startup inventory.
        $null=Get-OwnedWriterServices $Control
    }
    foreach ($entry in $operation.services) {
        if ($entry.id -cnotin @('AeliumTunnel','AeliumAPI','AeliumKeycloak')) {throw 'Invalid writer inventory.'}
        $operation.step='protect-'+$entry.id;Set-UpdateOperation $Control $operation
        $disabled=New-Object Aelium.Update.ServiceOptions;$disabled.StartType=4;$disabled.Actions=@();$disabled.ResetPeriod=0;$disabled.DelayedAutoStart=$false;$disabled.NonCrashFailures=$false
        [Aelium.Update.NativeServices]::Write($entry.id,$disabled)
        $service=Get-Service -Name $entry.id
        if ($service.Status -ne 'Stopped') {Write-Host ('Deteniendo '+$entry.id+'; espera maxima de confirmacion: 90 segundos...');Stop-UpdateWriterService $service}
        $actual=[Aelium.Update.NativeServices]::Read($entry.id)
        if ($actual.StartType -ne 4 -or $actual.Actions.Count -ne 0 -or $actual.NonCrashFailures) {throw 'Service protection did not persist.'}
        $operation.step='stopped-'+$entry.id;Set-UpdateOperation $Control $operation
    }
    $prefix=$Control.root+'\'
    $remaining=@(Get-CimInstance Win32_Process | Where-Object {$_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and $_.Name -in @('propiedades-backend.exe','java.exe','cloudflared.exe')})
    if ($remaining.Count) {throw 'Writer process remains; do not copy or apply.'}
    [pscustomobject]@{status='WriterServicesProtected';databaseConnectionsVerified=$false;operationId=$operation.operationId}
}
function Start-UpdateVerificationWriters($Control,[switch]$IncludeTunnel,[switch]$IdentityOnly) {
    Assert-ControlAdministrator
    $operation=Read-UpdateJson $Control.operationPath;Assert-Operation $operation
    if ($operation.phase -cnotin @('Verifying','Recovering')) {throw 'Controlled startup requires verification/recovery.'}
    $null=Get-OwnedWriterServices $Control
    $ids=@('AeliumKeycloak');if (-not $IdentityOnly) {$ids+='AeliumAPI'};if ($IncludeTunnel -and -not $IdentityOnly) {$ids+='AeliumTunnel'}
    foreach ($id in $ids) {
        $entries=@($operation.services | Where-Object {$_.id -ceq $id})
        if ($entries.Count -eq 0 -and $id -ceq 'AeliumTunnel') {continue}
        if ($entries.Count -ne 1) {throw 'Original service inventory missing.'}
        $operation.step='verify-start-'+$id;Set-UpdateOperation $Control $operation
        $demand=New-Object Aelium.Update.ServiceOptions;$demand.StartType=3;$demand.Actions=@();$demand.ResetPeriod=0;$demand.DelayedAutoStart=$false;$demand.NonCrashFailures=$false
        [Aelium.Update.NativeServices]::Write($id,$demand)
        Start-Service -Name $id;(Get-Service -Name $id).WaitForStatus('Running',[TimeSpan]::FromSeconds(60))
        $actual=[Aelium.Update.NativeServices]::Read($id)
        if ($actual.StartType -ne 3 -or $actual.Actions.Count -ne 0 -or $actual.NonCrashFailures) {throw 'Verification startup is not protected against automatic recovery.'}
    }
    [pscustomobject]@{status='VerificationWritersStarted';automaticStartupRestored=$false}
}
function Restore-UpdateWriters($Control) {
    Assert-ControlAdministrator
    $operation=Read-UpdateJson $Control.operationPath;Assert-Operation $operation
    if ($operation.phase -cnotin @('Committing','Committed','Recovered') -or -not $operation.checksPassed) {throw 'Writer restoration requires verified application/data state.'}
    Assert-UpdateList $operation.services
    $null=Get-OwnedWriterServices $Control
    # Keycloak before API; tunnel last. PostgreSQL is never changed.
    foreach ($id in @('AeliumKeycloak','AeliumAPI','AeliumTunnel')) {
        $entries=@($operation.services | Where-Object {$_.id -ceq $id})
        if ($entries.Count -eq 0 -and $id -ceq 'AeliumTunnel') {continue}
        if ($entries.Count -ne 1) {throw 'Incomplete original service inventory.'}
        $entry=$entries[0];$options=New-Object Aelium.Update.ServiceOptions
        $options.StartType=$entry.options.StartType;$options.DelayedAutoStart=$entry.options.DelayedAutoStart;$options.ResetPeriod=$entry.options.ResetPeriod;$options.NonCrashFailures=$entry.options.NonCrashFailures
        $options.Actions=@($entry.options.Actions | ForEach-Object {$action=New-Object Aelium.Update.ActionInfo;$action.Type=$_.Type;$action.Delay=$_.Delay;$action})
        $operation.step='restore-'+$id;Set-UpdateOperation $Control $operation
        [Aelium.Update.NativeServices]::Write($id,$options)
        if ($entry.state -ceq 'Running') {Start-Service -Name $id;(Get-Service -Name $id).WaitForStatus('Running',[TimeSpan]::FromSeconds(60))}
        elseif ((Get-Service -Name $id).Status -ne 'Stopped') {Stop-UpdateWriterService (Get-Service -Name $id)}
        $actual=[Aelium.Update.NativeServices]::Read($id)
        if (($actual|ConvertTo-Json -Depth 8 -Compress) -cne ($options|ConvertTo-Json -Depth 8 -Compress)) {throw 'Original service options not restored.'}
        $operation.step='restored-'+$id;Set-UpdateOperation $Control $operation
    }
    [pscustomobject]@{status='WriterServiceOptionsRestored';operationId=$operation.operationId;updateSucceeded=$false}
}
