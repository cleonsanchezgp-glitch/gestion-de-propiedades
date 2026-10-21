. (Join-Path $PSScriptRoot 'Control.ps1')

function Test-UpdateAclEquivalent([string]$Actual,[string]$Expected) {
    if ($Actual -ceq $Expected) {return $true}
    $left=New-Object Security.AccessControl.RawSecurityDescriptor($Actual)
    $right=New-Object Security.AccessControl.RawSecurityDescriptor($Expected)
    if ($left.Owner.Value -cne $right.Owner.Value -or $left.Group.Value -cne $right.Group.Value -or $left.ControlFlags -ne $right.ControlFlags) {return $false}
    # Windows may reorder inherited allow ACEs. Only an all-allow ACL can
    # ignore ordering; mixed deny/callback ACLs still require exact SDDL.
    $signatures=@()
    foreach ($descriptor in @($left,$right)) {
        $aces=@();foreach ($ace in $descriptor.DiscretionaryAcl) {
            if ($ace.AceType -ne [Security.AccessControl.AceType]::AccessAllowed) {return $false}
            $bytes=New-Object byte[] $ace.BinaryLength;$ace.GetBinaryForm($bytes,0);$aces+=[Convert]::ToBase64String($bytes)
        }
        $signatures+=(@($aces|Sort-Object) -join '|')
    }
    return $signatures[0] -ceq $signatures[1]
}

function Set-PrivateUpdateDirectory([string]$Directory) {
    Assert-NoReparse $Directory
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $Directory /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' (('*'+$sid)+':(OI)(CI)F') | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'Cannot secure private maintenance directory.'}
}
function Write-PrivateUpdateJson([string]$Path,$Value) {
    Assert-NoReparse $Path
    $temp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    $stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(($Value|ConvertTo-Json -Depth 30));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    if (Test-Path -LiteralPath $Path) {[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
}
function Get-UpdatePg($Control) {
    $settings=Read-UpdateJson (Join-Path $Control.root 'config/settings.json')
    if ($settings.Format -ne 1 -or $settings.Complete -ne $true -or $settings.PgPort -lt 1024 -or $settings.PgPort -gt 65535 -or $settings.PostgresPassword -isnot [string]) {throw 'Unsupported database configuration.'}
    $bin=Join-Path $Control.root 'postgresql/bin';Assert-NoReparse $bin
    foreach ($tool in @('psql.exe','pg_dump.exe','pg_dumpall.exe','pg_restore.exe','initdb.exe','pg_ctl.exe')) {Assert-NoReparse (Join-Path $bin $tool);if (-not (Test-Path -LiteralPath (Join-Path $bin $tool) -PathType Leaf)) {throw 'Database tools missing.'}}
    [pscustomobject]@{bin=$bin;port=[int]$settings.PgPort;user='postgres';password=$settings.PostgresPassword}
}
function Invoke-UpdateBoundedProcess([string]$File,[string[]]$Arguments,[string]$InputText,[int]$TimeoutMilliseconds) {
    if($TimeoutMilliseconds -lt 1){throw 'Positive command timeout required.'}
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$File;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.Arguments=(@($Arguments|ForEach-Object{
        # Windows argv quoting: double backslashes preceding quotes and the
        # closing quote; SQL and passwords are never command-line arguments.
        '"'+[regex]::Replace([regex]::Replace($_,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
    }) -join ' ')
    $process=New-Object Diagnostics.Process;$process.StartInfo=$info;$started=$false
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        if(-not $process.Start()){throw 'Database maintenance process could not start.'};$started=$true
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if($InputText){
            $write=$process.StandardInput.WriteAsync($InputText+"`n")
            if(-not $write.Wait([Math]::Max(1,$TimeoutMilliseconds-[int]$watch.ElapsedMilliseconds))){throw 'Database maintenance command timed out.'}
        }
        # Close stdin even without SQL: never leave a client waiting for input.
        $process.StandardInput.Close()
        if(-not $process.WaitForExit([Math]::Max(1,$TimeoutMilliseconds-[int]$watch.ElapsedMilliseconds))){throw 'Database maintenance command timed out.'}
        foreach($read in @($stdout,$stderr)){
            if(-not $read.Wait([Math]::Max(1,$TimeoutMilliseconds-[int]$watch.ElapsedMilliseconds))){throw 'Database maintenance command timed out.'}
        }
        if($process.ExitCode -ne 0){throw ('Database maintenance command failed ('+[IO.Path]::GetFileName($File)+'); writers must remain protected.')}
        $stdout.Result.Trim()
    }finally{
        if($started -and -not $process.HasExited){$process.Kill();$null=$process.WaitForExit(5000)}
        $process.Dispose();$watch.Stop()
    }
}
function Invoke-UpdatePg($Pg,[string]$Tool,[string[]]$Arguments,[string]$InputText='', [int]$TimeoutSeconds=300) {
    $before=@{};foreach ($key in @('PGPASSWORD','PGAPPNAME','PGSERVICE','PGSERVICEFILE','PGOPTIONS','PGHOST','PGPORT','PGDATABASE','PGUSER','PGPASSFILE','PGCONNECT_TIMEOUT')) {$before[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$null,'Process')}
    try {
        $env:PGPASSWORD=$Pg.password;$env:PGAPPNAME='aelium-maintenance';$env:PGCONNECT_TIMEOUT='10'
        if ($Tool -ceq 'pg_ctl.exe' -and $Arguments -ccontains 'start') {
            # A daemon must not inherit the updater's redirected stdout pipes.
            # Waiting on the pg_ctl PID avoids waiting for its server child.
            $start=New-Object Diagnostics.ProcessStartInfo
            $start.FileName=Join-Path $Pg.bin $Tool;$start.UseShellExecute=$true;$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
            $start.Arguments=(@($Arguments | ForEach-Object {'"'+$_.Replace('"','\"')+'"'}) -join ' ')
            $process=[Diagnostics.Process]::Start($start)
            try {if (-not $process.WaitForExit(60000) -or $process.ExitCode -ne 0) {throw 'Isolated PostgreSQL startup failed.'}}finally {$process.Dispose()}
            return ''
        }
        Invoke-UpdateBoundedProcess (Join-Path $Pg.bin $Tool) $Arguments $InputText ($TimeoutSeconds*1000)
    } finally {foreach ($key in $before.Keys) {[Environment]::SetEnvironmentVariable($key,$before[$key],'Process')}}
}
function Invoke-UpdateSql($Pg,[string]$Database,[string]$Sql) {
    Invoke-UpdatePg $Pg 'psql.exe' @('-X','-h','127.0.0.1','-p',[string]$Pg.port,'-U',$Pg.user,'-d',$Database,'-v','ON_ERROR_STOP=1','-At','-f','-') $Sql
}
function Assert-NoUpdateConnections($Pg) {
    if ((Invoke-UpdateSql $Pg 'postgres' "SELECT count(*) FROM pg_stat_activity WHERE datname IN ('propiedades','keycloak') AND pid <> pg_backend_pid()") -cne '0') {throw 'Database writers/connections remain; no backup or swap allowed.'}
}
function Get-UpdateRoleFingerprint($Pg) {
    # Password hashes and role settings never leave this private digest operation.
    Invoke-UpdateSql $Pg 'postgres' "SELECT md5(coalesce(string_agg(row_to_json(r)::text, E'\n' ORDER BY rolname),'')) FROM (SELECT rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolconnlimit,rolpassword,rolvaliduntil,rolbypassrls,(SELECT setconfig FROM pg_db_role_setting WHERE setrole=pg_authid.oid AND setdatabase=0) rolconfig FROM pg_authid WHERE rolname !~ '^pg_' ORDER BY rolname) r"
}
function Get-UpdateMembershipFingerprint($Pg) {
    Invoke-UpdateSql $Pg 'postgres' "SELECT md5(coalesce(string_agg(row_to_json(x)::text,'' ORDER BY role,member,grantor),'')) FROM (SELECT pg_get_userbyid(roleid) role,pg_get_userbyid(member) member,pg_get_userbyid(grantor) grantor,admin_option,inherit_option,set_option FROM pg_auth_members) x"
}
function Get-UpdateDataFingerprint($Pg,[string]$Database,[switch]$LogicalColumns) {
    # Read-only SQL; JSON row hashes preserve NULLs, bytea, IDs and relationships.
    $tables=Invoke-UpdateSql $Pg $Database "SELECT json_agg(x ORDER BY s,n)::text FROM (SELECT ns.nspname s,c.relname n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE c.relkind IN ('r','m') AND ns.nspname !~ '^pg_' AND ns.nspname <> 'information_schema') x"
    $result=@()
    if ($tables -and $tables -cne '') {
        foreach ($table in ($tables|ConvertFrom-Json)) {
            $qualified='"'+$table.s.Replace('"','""')+'"."'+$table.n.Replace('"','""')+'"'
            $digest=Invoke-UpdateSql $Pg $Database ("SELECT count(*)::text||':'||md5(coalesce(string_agg(h,'' ORDER BY h),'')) FROM (SELECT md5(row_to_json(t)::text) h FROM "+$qualified+' t) rows')
            $result += [pscustomobject]@{schema=$table.s;table=$table.n;digest=$digest}
        }
    }
    # Large objects may hold attachments; include contents, not just their OIDs.
    $large=Invoke-UpdateSql $Pg $Database "SELECT count(*)::text||':'||md5(coalesce(string_agg(loid::text||':'||pageno::text||':'||md5(encode(data,'hex')),'' ORDER BY loid,pageno),'')) FROM pg_largeobject"
    $sequences=Invoke-UpdateSql $Pg $Database "SELECT coalesce(json_agg(x ORDER BY schemaname,sequencename)::text,'[]') FROM (SELECT schemaname,sequencename,sequenceowner,data_type::text,start_value,min_value,max_value,increment_by,cycle,cache_size,last_value FROM pg_sequences WHERE schemaname !~ '^pg_') x"
    # Logical dumps omit dropped columns. Keep surviving column order, but do
    # not compare physical attribute-number holes left by old migrations.
    # Format 1 backups retain their original physical-number fingerprint.
    $columnNumber=if($LogicalColumns){'row_number() OVER (ORDER BY attnum) AS attnum'}else{'attnum'}
    $structure=Invoke-UpdateSql $Pg $Database "SELECT md5(coalesce(string_agg(row_to_json(x)::text,'' ORDER BY s,n),'')) FROM (SELECT ns.nspname s,c.relname n,c.relkind,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner) owner,c.relacl::text acl,(SELECT json_agg(a ORDER BY attnum) FROM (SELECT attname,$columnNumber,atttypid::regtype::text type,attnotnull,attidentity,attgenerated,attcollation::regcollation::text collation FROM pg_attribute WHERE attrelid=c.oid AND attnum>0 AND NOT attisdropped) a) columns,(SELECT json_agg(d ORDER BY d) FROM (SELECT pg_get_constraintdef(oid) d FROM pg_constraint WHERE conrelid=c.oid) q) constraints FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE c.relkind IN ('r','m','v','S') AND ns.nspname !~ '^pg_' AND ns.nspname<>'information_schema') x"
    [pscustomobject]@{tables=$result;largeObjects=$large;sequences=($sequences|ConvertFrom-Json);structure=$structure}
}
function Expand-UpdateMetadataRows($Value) {
    if($null -eq $Value){return}
    if($Value -is [array]){foreach($item in $Value){Expand-UpdateMetadataRows $item};return}
    if(@($Value.PSObject.Properties.Name).Count -eq 2 -and $Value.PSObject.Properties['value'] -and $Value.PSObject.Properties['Count']){
        if($Value.value -is [array] -and $Value.Count -eq $Value.value.Count){Expand-UpdateMetadataRows $Value.value;return}
    }
    Write-Output $Value
}
function Compare-UpdateMetadataRows($Before,$After,[string[]]$Keys) {
    # Some PS 5.1 array expressions serialize as {value:[...],Count:N}.
    # Unwrap only for diagnosis; the strict backup fingerprint is unchanged.
    $left=@(Expand-UpdateMetadataRows $Before);$right=@(Expand-UpdateMetadataRows $After)
    $missing=0;$extra=0;$fields=@{}
    foreach($row in $left){
        $matches=@($right | Where-Object {$candidate=$_;$equal=$true;foreach($key in $Keys){if($candidate.$key -cne $row.$key){$equal=$false}};$equal})
        if($matches.Count -ne 1){$missing++;continue}
        foreach($property in $row.PSObject.Properties){
            if($Keys -ccontains $property.Name){continue}
            if(($property.Value|ConvertTo-Json -Depth 12 -Compress) -cne ($matches[0].($property.Name)|ConvertTo-Json -Depth 12 -Compress)){
                if(-not $fields.ContainsKey($property.Name)){$fields[$property.Name]=0};$fields[$property.Name]++
            }
        }
    }
    foreach($row in $right){
        $matches=@($left | Where-Object {$candidate=$_;$equal=$true;foreach($key in $Keys){if($candidate.$key -cne $row.$key){$equal=$false}};$equal})
        if($matches.Count -ne 1){$extra++}
    }
    [pscustomobject]@{sourceCount=$left.Count;restoredCount=$right.Count;missingCount=$missing;extraCount=$extra;changedFields=@($fields.Keys|Sort-Object|ForEach-Object{[pscustomobject]@{field=$_;objectCount=$fields[$_]}})}
}
function Get-UpdateStructureDiagnosticRows($Pg,[string]$Database) {
    # Metadata only, used internally. Export field names/counts, never definitions,
    # ACLs, object names, row contents or hashes through the public diagnosis.
    $json=Invoke-UpdateSql $Pg $Database "SELECT coalesce(json_agg(x ORDER BY s,n)::text,'[]') FROM (SELECT ns.nspname s,c.relname n,c.relkind,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner) owner,c.relacl::text acl,(SELECT json_agg(a ORDER BY attnum) FROM (SELECT attname,attnum,atttypid::regtype::text type,attnotnull,attidentity,attgenerated,attcollation::regcollation::text collation FROM pg_attribute WHERE attrelid=c.oid AND attnum>0 AND NOT attisdropped) a) columns,(SELECT json_agg(d ORDER BY d) FROM (SELECT pg_get_constraintdef(oid) d FROM pg_constraint WHERE conrelid=c.oid) q) constraints FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE c.relkind IN ('r','m','v','S') AND ns.nspname !~ '^pg_' AND ns.nspname<>'information_schema') x"
    $json|ConvertFrom-Json
}
function Get-UpdateColumnDiagnosticRows($Pg,[string]$Database) {
    $json=Invoke-UpdateSql $Pg $Database "SELECT coalesce(json_agg(x ORDER BY s,n,attnum)::text,'[]') FROM (SELECT ns.nspname s,c.relname n,a.attname,a.attnum,a.atttypid::regtype::text type,a.attnotnull,a.attidentity,a.attgenerated,a.attcollation::regcollation::text collation FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE a.attnum>0 AND NOT a.attisdropped AND c.relkind IN ('r','m','v','S') AND ns.nspname !~ '^pg_' AND ns.nspname<>'information_schema') x"
    $json|ConvertFrom-Json
}
function Assert-UpdateInventory($Inventory) {
    Assert-Fields $Inventory @('format','complete','evidence','attachments')
    if ($Inventory.format -ne 1 -or $Inventory.complete -isnot [bool] -or -not $Inventory.complete -or $Inventory.attachments -isnot [array]) {throw 'Reviewed complete storage inventory required.'}
    Assert-UpdateId $Inventory.evidence
    $seen=@{}
    foreach ($item in $Inventory.attachments) {
        Assert-Fields $item @('path');Assert-UpdatePath $item.path
        if (-not $item.path.StartsWith('attachments/',[StringComparison]::Ordinal) -or $seen.ContainsKey($item.path)) {throw 'External attachment roots must be unique installation attachments subdirectories.'}
        $seen[$item.path]=$true
    }
}
function Get-UpdateTree([string]$Root,[string[]]$Paths) {
    $items=New-Object Collections.Generic.List[object]
    $seen=@{}
    foreach ($relative in $Paths) {
        Assert-UpdatePath $relative;$start=Join-Path $Root $relative;Assert-NoReparse $start
        if (-not (Test-Path -LiteralPath $start)) {throw 'Inventory path missing.'}
        $queue=New-Object Collections.Generic.Queue[string];$queue.Enqueue($start)
        while ($queue.Count) {
            $full=$queue.Dequeue();Assert-NoReparse $full
            $entry=Get-Item -LiteralPath $full -Force
            $name=$full.Substring($Root.TrimEnd('\').Length+1).Replace('\','/');Assert-UpdatePath $name
            if ($seen.ContainsKey($name)) {continue};$seen[$name]=$true
            $sddl=(Get-Acl -LiteralPath $full).Sddl
            if ($entry.PSIsContainer) {
                $items.Add([pscustomobject]@{path=$name;directory=$true;size=0;sha256=$null;sddl=$sddl})
                foreach ($child in @(Get-ChildItem -LiteralPath $full -Force)) {$queue.Enqueue($child.FullName)}
            } else {
                $items.Add([pscustomobject]@{path=$name;directory=$false;size=$entry.Length;sha256=(Get-UpdateFileHash $full);sddl=$sddl})
            }
        }
    }
    return @($items | Sort-Object path)
}
function Assert-BackupWriters($Control,$Pg) {
    $operation=Read-UpdateJson $Control.operationPath;Assert-Operation $operation
    if ($operation.phase -cnotin @('BackingUp','Recovering','RecoveryRequired')) {throw 'Backup/recovery requires protected maintenance phase.'}
    if ($operation.services.Count -ne 0) {
        foreach ($entry in $operation.services) {
            if ($entry.id -cnotin @('AeliumAPI','AeliumKeycloak','AeliumTunnel')) {throw 'Unknown writer in operation.'}
            if ((Get-Service -Name $entry.id).Status -ne 'Stopped') {throw 'Writer service remains running.'}
            $options=[Aelium.Update.NativeServices]::Read($entry.id)
            if ($options.StartType -ne 4 -or $options.Actions.Count -ne 0 -or $options.NonCrashFailures) {throw 'Writer service is not persistently protected.'}
        }
    } else {
        # Empty services only for explicit fixtures, never a service installation.
        $allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../tests/artifacts/updates')).TrimEnd('\')+'\'
        if (-not $Control.root.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) {throw 'Writer service inventory required.'}
    }
    Assert-NoUpdateConnections $Pg
}
function New-CoherentUpdateBackup($Control,$Inventory) {
    Assert-UpdateInventory $Inventory;$operation=Read-UpdateJson $Control.operationPath
    if ($operation.phase -cne 'BackingUp') {throw 'Backup requires BackingUp.'}
    $pg=Get-UpdatePg $Control;Assert-BackupWriters $Control $pg
    if ((Invoke-UpdateSql $pg 'postgres' "SELECT count(*) FROM pg_tablespace WHERE spcname NOT IN ('pg_default','pg_global')") -cne '0') {throw 'Custom tablespaces require a separate recovery plan.'}
    if ((Invoke-UpdateSql $pg 'postgres' "SELECT count(*) FROM pg_roles WHERE rolname='aelium_verifier'") -cne '0') {throw 'Reserved verification role already exists.'}
    $backup=Join-Path $Control.root ('backups/'+$operation.operationId);Assert-NoReparse $backup
    if (Test-Path -LiteralPath $backup) {throw 'Backup already exists; verify it or use a new operation, never overwrite.'}
    Set-PrivateUpdateDirectory $backup
    $paths=@('config','scripts','bin','services','keycloak/conf')+@($Inventory.attachments | ForEach-Object {$_.path})
    $selectorPath=Join-Path $Control.root 'config/active-release.json'
    if (Test-Path -LiteralPath $selectorPath) {
        $selector=Read-UpdateJson $selectorPath;Assert-UpdateId $selector.releaseId
        if ($selector.path -cne ('releases/'+$selector.releaseId)) {throw 'Invalid original selector.'}
        $paths += $selector.path
    }
    $tree=@(Get-UpdateTree $Control.root $paths)
    foreach ($item in $tree) {
        $target=Join-Path $backup ('files/'+$item.path);Assert-NoReparse $target
        if ($item.directory) {New-Item -ItemType Directory -Path $target -Force | Out-Null}
        else {New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null;[IO.File]::Copy((Join-Path $Control.root $item.path),$target,$false)}
    }
    $databases=@()
    foreach ($db in @('propiedades','keycloak')) {
        Assert-NoUpdateConnections $pg
        $meta=Invoke-UpdateSql $pg 'postgres' ("SELECT row_to_json(x)::text FROM (SELECT oid::text oid,datname name,pg_get_userbyid(datdba) owner,pg_encoding_to_char(encoding) encoding,datcollate collate,datctype ctype,datacl::text acl FROM pg_database WHERE datname='"+$db+"') x")
        if (-not $meta) {throw 'Required database missing.'}
        $metadata=$meta|ConvertFrom-Json
        # The supported initial layout has default database ACL/settings/tablespace.
        if ($null -ne $metadata.acl) {throw 'Custom database ACL requires a separate recovery plan.'}
        $unsupported=Invoke-UpdateSql $pg 'postgres' ("SELECT count(*) FROM pg_db_role_setting WHERE setdatabase=(SELECT oid FROM pg_database WHERE datname='"+$db+"')")
        if ($unsupported -cne '0') {throw 'Database-specific settings require a separate recovery plan.'}
        $operation.step='backup-fingerprint-'+$db;Set-UpdateOperation $Control $operation
        if($operation.services.Count){Write-Host ('Comprobando datos de '+$db+' antes de la copia...')}
        $fingerprint=Get-UpdateDataFingerprint $pg $db -LogicalColumns
        $dump=Join-Path $backup ($db+'.dump')
        $operation.step='backup-dump-'+$db;Set-UpdateOperation $Control $operation
        if($operation.services.Count){Write-Host ('Creando copia de '+$db+'...')}
        $null=Invoke-UpdatePg $pg 'pg_dump.exe' @('-h','127.0.0.1','-p',[string]$pg.port,'-U',$pg.user,'-d',$db,'-Fc','-f',$dump)
        $operation.step='backup-postdump-'+$db;Set-UpdateOperation $Control $operation
        if($operation.services.Count){Write-Host ('Comprobando datos de '+$db+' despues de la copia...')}
        if (($fingerprint|ConvertTo-Json -Depth 12 -Compress) -cne ((Get-UpdateDataFingerprint $pg $db -LogicalColumns)|ConvertTo-Json -Depth 12 -Compress)) {throw 'Database changed during backup.'}
        $databases += [pscustomobject]@{metadata=$metadata;dump=($db+'.dump');sha256=(Get-UpdateFileHash $dump);fingerprint=$fingerprint}
    }
    $globals=Join-Path $backup 'globals.private.sql'
    $operation.step='backup-globals';Set-UpdateOperation $Control $operation
    if($operation.services.Count){Write-Host 'Copiando roles de PostgreSQL...'}
    $null=Invoke-UpdatePg $pg 'pg_dumpall.exe' @('-h','127.0.0.1','-p',[string]$pg.port,'-U',$pg.user,'--globals-only','-f',$globals)
    $operation.step='backup-roles-check';Set-UpdateOperation $Control $operation
    $manifest=[pscustomobject]@{format=2;operationId=$operation.operationId;sourceReleaseId=$operation.sourceReleaseId;createdUtc=[DateTime]::UtcNow.ToString('o');verified=$false;inventory=$Inventory;files=$tree;databases=$databases;globalsSha256=(Get-UpdateFileHash $globals);rolesFingerprint=(Get-UpdateRoleFingerprint $pg);membershipsFingerprint=(Get-UpdateMembershipFingerprint $pg);services=$operation.services}
    Assert-NoUpdateConnections $pg
    foreach ($item in $tree | Where-Object {-not $_.directory}) {if ((Get-UpdateFileHash (Join-Path $backup ('files/'+$item.path))) -cne $item.sha256 -or (Get-UpdateFileHash (Join-Path $Control.root $item.path)) -cne $item.sha256) {throw 'File changed or copied incorrectly.'}}
    Write-PrivateUpdateJson (Join-Path $backup 'backup.private.json') $manifest
    $operation.backupReference='backups/'+$operation.operationId;$operation.step='backup-captured';Set-UpdateOperation $Control $operation
    [pscustomobject]@{status='BackupCaptured';operationId=$operation.operationId;verified=$false}
}
function Read-CoherentUpdateBackup($Control) {
    $operation=Read-UpdateJson $Control.operationPath
    if ($operation.backupReference -cne ('backups/'+$operation.operationId)) {throw 'Backup reference does not belong to operation.'}
    $directory=Join-Path $Control.root $operation.backupReference;Assert-NoReparse $directory
    $manifest=Read-UpdateJson (Join-Path $directory 'backup.private.json')
    Assert-Fields $manifest @('format','operationId','sourceReleaseId','createdUtc','verified','inventory','files','databases','globalsSha256','rolesFingerprint','membershipsFingerprint','services')
    if ($manifest.format -notin @(1,2) -or $manifest.operationId -cne $operation.operationId -or $manifest.sourceReleaseId -cne $operation.sourceReleaseId -or $manifest.verified -isnot [bool]) {throw 'Backup identity mismatch.'}
    Assert-UpdateInventory $manifest.inventory
    if (@($manifest.databases).Count -ne 2 -or ((@($manifest.databases.metadata.name | Sort-Object) -join ',') -cne 'keycloak,propiedades')) {throw 'Backup database inventory mismatch.'}
    foreach ($db in $manifest.databases) {if ($db.dump -cne ($db.metadata.name+'.dump') -or (Get-UpdateFileHash (Join-Path $directory $db.dump)) -cne $db.sha256) {throw 'Dump integrity failed.'}}
    foreach ($item in $manifest.files) {
        Assert-UpdatePath $item.path
        if ($item.path -cnotmatch '^(config|scripts|bin|services|keycloak/conf|attachments|releases/[a-zA-Z0-9][a-zA-Z0-9._-]{0,79})(/|$)') {throw 'Backup destination outside recoverable layout.'}
        if (-not $item.directory -and (Get-UpdateFileHash (Join-Path $directory ('files/'+$item.path))) -cne $item.sha256) {throw 'Backup file integrity failed.'}
    }
    if ((Get-UpdateFileHash (Join-Path $directory 'globals.private.sql')) -cne $manifest.globalsSha256) {throw 'Globals integrity failed.'}
    [pscustomobject]@{directory=$directory;manifest=$manifest}
}
function New-UpdateRestoreDatabase($Pg,$Metadata,[string]$Name) {
    if ($Name -cnotmatch '^aelium_[a-z0-9_]{1,55}$') {throw 'Invalid owned restore database name.'}
    $owner='"'+$Metadata.owner.Replace('"','""')+'"'
    $collate=$Metadata.collate.Replace("'","''");$ctype=$Metadata.ctype.Replace("'","''");$encoding=$Metadata.encoding.Replace("'","''")
    $null=Invoke-UpdateSql $Pg 'postgres' ('CREATE DATABASE "'+$Name+'" WITH TEMPLATE template0 OWNER '+$owner+" ENCODING '$encoding' LC_COLLATE '$collate' LC_CTYPE '$ctype'")
}
function Test-CoherentUpdateBackup($Control,[int]$VerificationPort) {
    $pg=Get-UpdatePg $Control;Assert-BackupWriters $Control $pg
    $backup=Read-CoherentUpdateBackup $Control
    if ($VerificationPort -lt 1024 -or $VerificationPort -gt 65535 -or $VerificationPort -eq $pg.port) {throw 'Separate verification port required.'}
    # PostgreSQL's Windows build still has path-length limits in initdb. Keep
    # the private trial close to the root rather than below backups/operation.
    $trial=Join-Path $Control.root ('maintenance/v-'+[Guid]::NewGuid().ToString('N').Substring(0,8));Set-PrivateUpdateDirectory $trial
    if ((Join-Path $trial 'cluster/pg_wal/archive_status').Length -gt 240) {throw 'Installation path too long for isolated PostgreSQL verification.'}
    $cluster=Join-Path $trial 'cluster';$trialPg=[pscustomobject]@{bin=$pg.bin;port=$VerificationPort;user='aelium_verifier';password=([Guid]::NewGuid().ToString('N')+[Guid]::NewGuid().ToString('N'))}
    $started=$false
    $stage='initialize';$database=$null;$comparison=$null
    try {
        $pwfile=Join-Path $trial 'initdb-password.private';[IO.File]::WriteAllText($pwfile,$trialPg.password,(New-Object Text.UTF8Encoding($false)))
        $null=Invoke-UpdatePg $trialPg 'initdb.exe' @('-D',$cluster,'-U',$trialPg.user,'--auth-local=scram-sha-256','--auth-host=scram-sha-256','--encoding=UTF8',('--pwfile='+$pwfile))
        [IO.File]::Delete($pwfile)
        # TCP trust would expose restored roles to other local users. Restrict all
        # connections to the generated verifier role before importing globals.
        [IO.File]::WriteAllText((Join-Path $cluster 'pg_hba.conf'),"host all aelium_verifier 127.0.0.1/32 scram-sha-256`nhost all all 0.0.0.0/0 reject`nhost all all ::/0 reject`n",(New-Object Text.UTF8Encoding($false)))
        $stage='start-isolated-cluster'
        $started=$true
        $null=Invoke-UpdatePg $trialPg 'pg_ctl.exe' @('-D',$cluster,'-l',(Join-Path $trial 'postgres.private.log'),'-o',('-h 127.0.0.1 -p '+$VerificationPort),'-w','start')
        $stage='import-roles'
        $null=Invoke-UpdatePg $trialPg 'psql.exe' @('-X','-h','127.0.0.1','-p',[string]$VerificationPort,'-U',$trialPg.user,'-d','postgres','-v','ON_ERROR_STOP=1','-f',(Join-Path $backup.directory 'globals.private.sql'))
        foreach ($db in $backup.manifest.databases) {
            $database=$db.metadata.name;$stage='create-database'
            New-UpdateRestoreDatabase $trialPg $db.metadata ('aelium_verify_'+$db.metadata.name)
            $stage='restore-database'
            $null=Invoke-UpdatePg $trialPg 'pg_restore.exe' @('-h','127.0.0.1','-p',[string]$VerificationPort,'-U',$trialPg.user,'-d',('aelium_verify_'+$db.metadata.name),'--exit-on-error','--single-transaction',(Join-Path $backup.directory $db.dump))
            $stage='compare-fingerprint'
            $actual=Get-UpdateDataFingerprint $trialPg ('aelium_verify_'+$db.metadata.name) -LogicalColumns:($backup.manifest.format -eq 2)
            $comparison=[pscustomobject]@{tablesEqual=(($actual.tables|ConvertTo-Json -Depth 12 -Compress) -ceq ($db.fingerprint.tables|ConvertTo-Json -Depth 12 -Compress));largeObjectsEqual=($actual.largeObjects -ceq $db.fingerprint.largeObjects);sequencesEqual=(($actual.sequences|ConvertTo-Json -Depth 12 -Compress) -ceq ($db.fingerprint.sequences|ConvertTo-Json -Depth 12 -Compress));structureEqual=($actual.structure -ceq $db.fingerprint.structure)}
            if (($actual|ConvertTo-Json -Depth 12 -Compress) -cne ($db.fingerprint|ConvertTo-Json -Depth 12 -Compress)) {
                # Diagnosis cannot waive a mismatch or replace its original error.
                try {
                    $sequenceDetails=Compare-UpdateMetadataRows $db.fingerprint.sequences $actual.sequences @('schemaname','sequencename')
                    # Public diagnosis compares the actual metadata rows rather
                    # than PS 5.1's empty-array/wrapper serialization.
                    $comparison.sequencesEqual=($sequenceDetails.missingCount -eq 0 -and $sequenceDetails.extraCount -eq 0 -and $sequenceDetails.changedFields.Count -eq 0)
                    $sourceRows=@(Get-UpdateStructureDiagnosticRows $pg $db.metadata.name)
                    $restoredRows=@(Get-UpdateStructureDiagnosticRows $trialPg ('aelium_verify_'+$db.metadata.name))
                    $structureDetails=Compare-UpdateMetadataRows $sourceRows $restoredRows @('s','n')
                    $comparison|Add-Member -NotePropertyName sequenceDetails -NotePropertyValue $sequenceDetails
                    $comparison|Add-Member -NotePropertyName structureDetails -NotePropertyValue $structureDetails
                    $columnDetails=Compare-UpdateMetadataRows @(Get-UpdateColumnDiagnosticRows $pg $db.metadata.name) @(Get-UpdateColumnDiagnosticRows $trialPg ('aelium_verify_'+$db.metadata.name)) @('s','n','attname')
                    $comparison|Add-Member -NotePropertyName columnDetails -NotePropertyValue $columnDetails
                }catch{$comparison|Add-Member -NotePropertyName detailFailureTrace -NotePropertyValue ($_.FullyQualifiedErrorId+' '+$_.ScriptStackTrace)}
                throw 'Isolated restored data differs from backup baseline.'
            }
        }
        # Active cluster roles must remain unchanged. Globals are applied ONLY
        # to the newly initialized trial cluster, never to the live installation.
        $stage='compare-live-roles';$database=$null;$comparison=$null
        if ((Get-UpdateRoleFingerprint $pg) -cne $backup.manifest.rolesFingerprint -or (Get-UpdateMembershipFingerprint $pg) -cne $backup.manifest.membershipsFingerprint) {throw 'Active cluster roles changed.'}
        $backup.manifest.verified=$true;Write-PrivateUpdateJson (Join-Path $backup.directory 'backup.private.json') $backup.manifest
        $operation=Read-UpdateJson $Control.operationPath;$operation.step='backup-restore-verified';Set-UpdateOperation $Control $operation
        [pscustomobject]@{status='BackupRestoreVerified';operationId=$operation.operationId;databaseCount=2}
    } catch {
        $original=$_
        try {Write-ControlJson $Control (Join-Path $Control.root 'maintenance/backup-validation.json') ([pscustomobject]@{format=1;operationId=$backup.manifest.operationId;stage=$stage;database=$database;comparison=$comparison;reasonCode='IsolatedBackupValidationFailed';trace=$original.ScriptStackTrace})}catch{}
        throw $original
    } finally {
        if ($started) {$null=Invoke-UpdatePg $trialPg 'pg_ctl.exe' @('-D',$cluster,'-m','fast','-w','stop')}
    }
}

function Get-UpdateDatabaseIdentity($Pg,[string]$Name) {
    if ($Name -cnotmatch '^[a-z][a-z0-9_]{0,62}$') {throw 'Invalid database name.'}
    Invoke-UpdateSql $Pg 'postgres' ("SELECT oid::text FROM pg_database WHERE datname='"+$Name+"'")
}
function Restore-CoherentUpdateBackup($Control) {
    $operation=Read-UpdateJson $Control.operationPath
    if ($operation.phase -cne 'Recovering') {throw 'Recovery requires Recovering; committed backups cannot discard later writes.'}
    $pg=Get-UpdatePg $Control;Assert-BackupWriters $Control $pg
    $backup=Read-CoherentUpdateBackup $Control
    if (-not $backup.manifest.verified) {throw 'Backup has not passed isolated restoration.'}
    if ((Get-UpdateRoleFingerprint $pg) -cne $backup.manifest.rolesFingerprint -or (Get-UpdateMembershipFingerprint $pg) -cne $backup.manifest.membershipsFingerprint) {throw 'Live roles differ; automatic globals restoration is prohibited.'}
    $journalPath=Join-Path $backup.directory 'recovery.private.json'
    if (Test-Path -LiteralPath $journalPath) {
        $journal=Read-UpdateJson $journalPath
        Assert-Fields $journal @('format','operationId','databases','filesRestored','verified')
        if ($journal.format -ne 1 -or $journal.operationId -cne $operation.operationId -or @($journal.databases).Count -ne 2) {throw 'Invalid recovery journal.'}
    } else {
        $suffix=[Guid]::NewGuid().ToString('N').Substring(0,16)
        $records=@($backup.manifest.databases | ForEach-Object {[pscustomobject]@{name=$_.metadata.name;originalOid=$_.metadata.oid;restoredName=('aelium_restore_'+$suffix+'_'+$_.metadata.name);quarantineName=('aelium_failed_'+$suffix+'_'+$_.metadata.name);restoredOid=$null;restored=$false;swapped=$false}})
        $journal=[pscustomobject]@{format=1;operationId=$operation.operationId;databases=$records;filesRestored=$false;verified=$false}
        Write-PrivateUpdateJson $journalPath $journal
    }
    # Restore both databases BEFORE either name is exchanged. Never overwrite
    # an unclaimed database or an interrupted partial restore.
    foreach ($record in $journal.databases) {
        if ($record.name -cnotin @('propiedades','keycloak') -or $record.originalOid -cnotmatch '^[0-9]+$' -or $record.restoredName -cnotmatch '^aelium_restore_[a-f0-9]{16}_(propiedades|keycloak)$' -or $record.quarantineName -cnotmatch '^aelium_failed_[a-f0-9]{16}_(propiedades|keycloak)$') {throw 'Recovery database identity invalid.'}
        $db=@($backup.manifest.databases | Where-Object {$_.metadata.name -ceq $record.name})[0]
        if (-not $record.restored) {
            if (Get-UpdateDatabaseIdentity $pg $record.restoredName) {throw 'Interrupted/unclaimed restore preserved; requires a reviewed recovery retry.'}
            New-UpdateRestoreDatabase $pg $db.metadata $record.restoredName
            $record.restoredOid=Get-UpdateDatabaseIdentity $pg $record.restoredName;Write-PrivateUpdateJson $journalPath $journal
            $null=Invoke-UpdatePg $pg 'pg_restore.exe' @('-h','127.0.0.1','-p',[string]$pg.port,'-U',$pg.user,'-d',$record.restoredName,'--exit-on-error','--single-transaction',(Join-Path $backup.directory $db.dump))
            if (((Get-UpdateDataFingerprint $pg $record.restoredName -LogicalColumns:($backup.manifest.format -eq 2))|ConvertTo-Json -Depth 12 -Compress) -cne ($db.fingerprint|ConvertTo-Json -Depth 12 -Compress)) {throw 'Recovery restore differs from baseline.'}
            $record.restored=$true;Write-PrivateUpdateJson $journalPath $journal
        }
        if ($record.restoredOid -cnotmatch '^[0-9]+$') {throw 'Recovery OID missing.'}
    }
    foreach ($record in $journal.databases) {
        Assert-NoUpdateConnections $pg
        $live=Get-UpdateDatabaseIdentity $pg $record.name;$saved=Get-UpdateDatabaseIdentity $pg $record.quarantineName;$fresh=Get-UpdateDatabaseIdentity $pg $record.restoredName
        if ($live -ceq $record.originalOid -and -not $saved -and $fresh -ceq $record.restoredOid) {
            $operation.step='quarantine-'+$record.name;Set-UpdateOperation $Control $operation
            $null=Invoke-UpdateSql $pg 'postgres' ('ALTER DATABASE "'+$record.name+'" ALLOW_CONNECTIONS false')
            $null=Invoke-UpdateSql $pg 'postgres' ('ALTER DATABASE "'+$record.name+'" RENAME TO "'+$record.quarantineName+'"')
            $live='';$saved=$record.originalOid
        }
        if (-not $live -and $saved -ceq $record.originalOid -and $fresh -ceq $record.restoredOid) {
            $operation.step='activate-restored-'+$record.name;Set-UpdateOperation $Control $operation
            $null=Invoke-UpdateSql $pg 'postgres' ('ALTER DATABASE "'+$record.restoredName+'" ALLOW_CONNECTIONS false')
            $null=Invoke-UpdateSql $pg 'postgres' ('ALTER DATABASE "'+$record.restoredName+'" RENAME TO "'+$record.name+'"')
            $live=$record.restoredOid;$fresh=''
        }
        if ($live -cne $record.restoredOid -or $saved -cne $record.originalOid -or $fresh) {throw 'Recovery name/OID state ambiguous; no writer may start.'}
        $record.swapped=$true;Write-PrivateUpdateJson $journalPath $journal
    }
    # Both names now represent the same baseline. Restore only inventoried
    # installation paths, preserving ACLs; releases/quarantine remain retained.
    foreach ($item in $backup.manifest.files) {
        $target=Join-Path $Control.root $item.path;Assert-NoReparse $target
        if ($item.directory) {New-Item -ItemType Directory -Path $target -Force | Out-Null}
        else {
            # Recovery retries need not replace a file already restored byte for
            # byte. ACLs are still checked/restored below for every inventory item.
            if ((Test-Path -LiteralPath $target -PathType Leaf) -and (Get-UpdateFileHash $target) -ceq $item.sha256) {continue}
            $temp=$target+'.'+[Guid]::NewGuid().ToString('N')+'.recover'
            [IO.File]::Copy((Join-Path $backup.directory ('files/'+$item.path)),$temp,$false)
            if (Test-Path -LiteralPath $target) {[IO.File]::Replace($temp,$target,[NullString]::Value)}else{[IO.File]::Move($temp,$target)}
            if ((Get-UpdateFileHash $target) -cne $item.sha256) {throw 'Recovered file differs.'}
        }
    }
    # The only newly introduced configuration file removed on initial adoption.
    if (@($backup.manifest.files | Where-Object {$_.path -ceq 'config/active-release.json'}).Count -eq 0) {
        $selector=Join-Path $Control.root 'config/active-release.json';Assert-NoReparse $selector
        if (Test-Path -LiteralPath $selector) {[IO.File]::Delete($selector)}
    }
    foreach ($item in @($backup.manifest.files | Sort-Object {$_.path.Length})) {
        $target=Join-Path $Control.root $item.path
        $acl=if ($item.directory) {[IO.Directory]::GetAccessControl($target)}else{[IO.File]::GetAccessControl($target)}
        $baseline=if ($item.directory) {New-Object Security.AccessControl.DirectorySecurity}else{New-Object Security.AccessControl.FileSecurity}
        $baseline.SetSecurityDescriptorSddlForm($item.sddl)
        $acl.SetSecurityDescriptorSddlForm($item.sddl,[Security.AccessControl.AccessControlSections]::Access)
        if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $baseline.GetOwner([Security.Principal.SecurityIdentifier]).Value) {$acl.SetOwner($baseline.GetOwner([Security.Principal.SecurityIdentifier]))}
        if ($acl.GetGroup([Security.Principal.SecurityIdentifier]).Value -cne $baseline.GetGroup([Security.Principal.SecurityIdentifier]).Value) {$acl.SetGroup($baseline.GetGroup([Security.Principal.SecurityIdentifier]))}
        if ($item.directory) {[IO.Directory]::SetAccessControl($target,$acl)}else{[IO.File]::SetAccessControl($target,$acl)}
    }
    foreach ($item in $backup.manifest.files) {
        if (-not (Test-UpdateAclEquivalent (Get-Acl -LiteralPath (Join-Path $Control.root $item.path)).Sddl $item.sddl)) {throw 'Recovered ACL differs.'}
    }
    $journal.filesRestored=$true;Write-PrivateUpdateJson $journalPath $journal
    foreach ($record in $journal.databases) {$null=Invoke-UpdateSql $pg 'postgres' ('ALTER DATABASE "'+$record.name+'" ALLOW_CONNECTIONS true')}
    foreach ($db in $backup.manifest.databases) {
        if (((Get-UpdateDataFingerprint $pg $db.metadata.name -LogicalColumns:($backup.manifest.format -eq 2))|ConvertTo-Json -Depth 12 -Compress) -cne ($db.fingerprint|ConvertTo-Json -Depth 12 -Compress)) {throw 'Recovered database differs.'}
    }
    Assert-NoUpdateConnections $pg
    $journal.verified=$true;Write-PrivateUpdateJson $journalPath $journal
    $operation.step='recovered-baseline-verified';Set-UpdateOperation $Control $operation
    # Caller must still verify identity/frontend and restore service state.
    [pscustomobject]@{status='RecoveryBaselineVerified';operationId=$operation.operationId;servicesRestored=$false;updateSucceeded=$false}
}
