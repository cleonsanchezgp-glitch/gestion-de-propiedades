$ErrorActionPreference='Stop'
$stage='environment'
try {
    $computer=Get-CimInstance Win32_ComputerSystem
    if($computer.Manufacturer -cne 'Microsoft Corporation' -or $computer.Model -cne 'Virtual Machine'){throw 'Expected isolated Hyper-V copy.'}
    $toolRoot='C:\AeliumHyperVActualizador-r10'
    $archive='C:\AeliumHyperVPruebas\Herramientas-r10.zip'
    $stage='tool-integrity'
    if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'd13dd8e58c306a7b4d5202a2455914b64f6ab3c7ceb62c9a972db61fe5d4ddb0'){throw 'Pinned tools required.'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach($directory in @($toolRoot,(Join-Path $toolRoot 'update'))){if((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unsafe tool directory.'}}
        foreach($entry in @($zip.Entries|Where-Object{$_.FullName -match '\.(ps1|cs)$'})){
            if($entry.FullName -notmatch '^[A-Za-z0-9_./-]+$' -or $entry.FullName.Contains('..')){throw 'Unsafe tool name.'}
            $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
            try{$expected=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
            $path=Join-Path $toolRoot $entry.FullName
            if((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unsafe tool file.'}
            if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $expected){throw 'Installed tool integrity failed.'}
        }
    } finally {$zip.Dispose()}
    . (Join-Path $toolRoot 'update/Updater.ps1')
    $root='C:\ProgramData\Aelium\Propiedades'
    Assert-LocalRehearsal $root
    $operation=Read-UpdateJson (Join-Path $root 'maintenance/operation.json')
    Assert-Operation $operation
    if($operation.phase -cne 'Recovered' -or -not $operation.checksPassed -or $operation.targetReleaseId -cne 'rehearsal-vm-20261020-r2'){throw 'Recovered revision 2 required; no automatic recovery is attempted.'}
    $stage='read-only-database-query'
    $pg=Get-UpdatePg ([pscustomobject]@{root=$root})
    # No row contents, identifiers, tokens, hashes or configuration values leave
    # PostgreSQL. Key names and grouped session categories are diagnostic only.
    # READ ONLY is enforced by the server, with bounded query/lock waits.
    $sql=@'
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '10s';
SET LOCAL lock_timeout = '2s';
SELECT json_build_object(
  'onlineUserRows', (SELECT count(*) FROM public.offline_user_session WHERE offline_flag = '0'),
  'offlineUserRows', (SELECT count(*) FROM public.offline_user_session WHERE offline_flag = '1'),
  'unknownUserFlags', (SELECT count(*) FROM public.offline_user_session WHERE offline_flag IS NULL OR offline_flag NOT IN ('0','1')),
  'onlineClientRows', (SELECT count(*) FROM public.offline_client_session WHERE offline_flag = '0'),
  'offlineClientRows', (SELECT count(*) FROM public.offline_client_session WHERE offline_flag = '1'),
  'unknownClientFlags', (SELECT count(*) FROM public.offline_client_session WHERE offline_flag IS NULL OR offline_flag NOT IN ('0','1')),
  'discoveryRows', (SELECT count(*) FROM public.jgroups_ping),
  'serverConfigKeyCount', (SELECT count(*) FROM public.server_config),
  'serverConfigKeys', (SELECT coalesce(json_agg(server_config_key ORDER BY server_config_key),'[]'::json) FROM (SELECT server_config_key FROM public.server_config ORDER BY server_config_key LIMIT 40) k)
);
COMMIT;
'@
    $raw=Invoke-UpdatePg $pg 'psql.exe' @('-X','-q','-h','127.0.0.1','-p',[string]$pg.port,'-U',$pg.user,'-d','keycloak','-v','ON_ERROR_STOP=1','-At','-f','-') $sql 20
    $summary=ConvertFrom-UpdateJson $raw
    $versionPath=Join-Path $root 'keycloak/version.txt'
    $version=if(Test-Path -LiteralPath $versionPath){(Get-Content -LiteralPath $versionPath -Raw).Trim()}else{'unavailable'}
    if($version -notmatch '^\d+\.\d+\.\d+$'){$version='unavailable'}
    [pscustomobject]@{
        scope='Read-only recovered VM; no service changes, update or database writes'
        operationId=$operation.operationId
        phase=$operation.phase
        keycloakVersion=$version
        sessionsAndRuntime=$summary
        updateSucceeded=$false
        productionAccepted=$false
    }|ConvertTo-Json -Depth 6
} catch {
    # Do not print raw SQL errors, command arguments or private settings.
    [pscustomobject]@{status='DiagnosisUnavailable';stage=$stage;updateSucceeded=$false;productionAccepted=$false}|ConvertTo-Json
    exit 1
}
