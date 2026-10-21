[CmdletBinding()]
param(
    [switch]$ConfirmIsolatedVM,
    [string]$InstallationRoot='C:\ProgramData\Aelium\Propiedades',
    [string]$WorkDirectory='C:\AeliumEnsayo\ActualizacionLocal'
)
. (Join-Path $PSScriptRoot 'update/Updater.ps1')
Assert-ControlAdministrator
if (-not $ConfirmIsolatedVM) {throw 'Confirme una VM aislada sin datos del cliente mediante -ConfirmIsolatedVM.'}
$machine=Get-CimInstance Win32_ComputerSystem
if ($machine.Model -notmatch 'VirtualBox') {throw 'Esta preparacion esta limitada a la VM VirtualBox de ensayo.'}
$root=[IO.Path]::GetFullPath($InstallationRoot).TrimEnd('\');Assert-NoReparse $root
$work=[IO.Path]::GetFullPath($WorkDirectory).TrimEnd('\');Assert-NoReparse $work
if ($work.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or $work -ieq $root -or (Test-Path -LiteralPath $work)) {throw 'Use un directorio de trabajo nuevo fuera de la instalacion.'}
$settings=Read-UpdateJson (Join-Path $root 'config/settings.json')
if ($settings.Format -ne 1 -or -not $settings.Complete -or $settings.Username -cne 'prueba' -or $settings.PortalOrigin -cne 'https://portal.example.test') {throw 'Esta herramienta solo prepara la instalacion de ensayo acordada.'}
if ((Test-Path -LiteralPath (Join-Path $root 'maintenance')) -or (Test-Path -LiteralPath (Join-Path $root 'config/active-release.json'))) {throw 'La instalacion ya tiene mantenimiento; conservar su contexto, no regenerar referencias.'}
if ((Get-Service -Name AeliumTunnel -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath (Join-Path $root 'config/tunnel-token.txt'))) {throw 'No se admite un tunel en este ensayo local.'}
$legacy=(Read-UpdateJson (Join-Path $PSScriptRoot 'update/catalogs/legacy-20261010-185325.json')).sources[0]
Assert-InstalledFiles $root $legacy.files
$services=@(foreach($id in @('AeliumAPI','AeliumPostgres','AeliumKeycloak')) {
    $actual=Get-CimInstance Win32_Service -Filter ("Name='"+$id+"'")
    $expected=Join-Path $root ('services/'+$id+'.exe')
    if(-not $actual -or $actual.State -cne 'Running' -or $actual.StartName -inotmatch '^(NT AUTHORITY\\)?LocalService$' -or ($actual.PathName -ine $expected -and $actual.PathName -ine ('"'+$expected+'"'))) {throw 'Servicio fuera del inventario de ensayo.'}
    [pscustomobject]@{id=$id;executable=('services/'+$id+'.exe');account='LocalService'}
})
$pg=Get-UpdatePg ([pscustomobject]@{root=$root})
$history=@(Get-UpdateSchema $pg)
$schema=@($history|ForEach-Object{[pscustomobject]@{version=$_.version;checksum=$_.checksum}})
$candidate=Join-Path $PSScriptRoot 'candidate/bin/propiedades-backend.exe'
$delivery=Read-UpdateJson (Join-Path $PSScriptRoot 'delivery.json')
foreach($file in $delivery.files){Assert-UpdatePath $file.path;if((Get-UpdateFileHash (Join-Path $PSScriptRoot $file.path)) -cne $file.sha256){throw 'Entrega de ensayo alterada; no ejecutar candidata.'}}
$info=& $candidate --release-info
if($LASTEXITCODE -ne 0){throw 'No se puede identificar la candidata.'}
$info=ConvertFrom-UpdateJson ($info -join "`n")
if($info.releaseId -cnotlike 'rehearsal-*' -or $info.transactionalMigrations -ne $true -or -not (Test-MigrationEquality $schema $info.migrations)) {throw 'Este primer ensayo exige candidata identificada y sin migraciones nuevas.'}
function InstalledFiles([string[]]$Paths){
    $files=@(foreach($relative in $Paths){
        Assert-UpdatePath $relative;$full=Join-Path $root $relative;Assert-NoReparse $full
        $entry=Get-Item -LiteralPath $full
        if($entry.PSIsContainer){
            foreach($child in Get-ChildItem -LiteralPath $full -Recurse -File){Assert-NoReparse $child.FullName;[pscustomobject]@{path=$child.FullName.Substring($root.Length+1).Replace('\','/');sha256=(Get-UpdateFileHash $child.FullName)}}
        }else{[pscustomobject]@{path=$relative;sha256=(Get-UpdateFileHash $full)}}
    })
    return @($files|Sort-Object path)
}
function InstalledVersion([string]$Path) {
    $version=(Get-Item -LiteralPath $Path).VersionInfo.FileVersion
    if ($version -is [string] -and $version) {return $version}
    return 'installed-files-identified-by-sha256'
}
$runtimeFiles=@(foreach($dll in @('vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll')) {
    [pscustomobject]@{path=('system-runtime/'+$dll);sha256=(Get-UpdateFileHash (Join-Path ([Environment]::SystemDirectory) $dll))}
})
$dependencies=@(
    [pscustomobject]@{id='postgresql';version=(InstalledVersion (Join-Path $root 'postgresql/bin/postgres.exe'));files=@(InstalledFiles @('postgresql/bin','postgresql/lib','postgresql/share'))},
    [pscustomobject]@{id='keycloak';version='26.7.4-conserved-original';files=@(InstalledFiles @('keycloak/bin','keycloak/lib','keycloak/providers'))},
    [pscustomobject]@{id='java';version=(InstalledVersion (Join-Path $root 'java/bin/java.exe'));files=@(InstalledFiles @('java/bin','java/lib','java/release'))},
    [pscustomobject]@{id='winsw';version='2.12.0-conserved-original';files=@(InstalledFiles @('services/AeliumAPI.exe','services/AeliumPostgres.exe','services/AeliumKeycloak.exe'))},
    [pscustomobject]@{id='cloudflared';version='conserved-original-hash';files=@(InstalledFiles @('bin/cloudflared.exe'))},
    [pscustomobject]@{id='vc-runtime';version=(InstalledVersion (Join-Path ([Environment]::SystemDirectory) 'vcruntime140.dll'));files=$runtimeFiles}
)
Assert-Dependencies $dependencies
foreach($dependency in $dependencies){Assert-InstalledDependency $root $dependency}
# Only a fresh synthetic database is seeded. Never merge fixtures into unknown data.
if((Invoke-UpdateSql $pg 'propiedades' 'SELECT (SELECT count(*) FROM entities)+(SELECT count(*) FROM pagos)+(SELECT count(*) FROM audit_events)') -cne '0'){throw 'La base debe estar vacia antes de sembrar esta baseline sintetica.'}
if ((Test-Path -LiteralPath (Join-Path $root 'attachments')) -and @(Get-ChildItem -LiteralPath (Join-Path $root 'attachments') -Force).Count) {throw 'La baseline inicial no debe contener adjuntos desconocidos.'}
$seed=@'
BEGIN;
INSERT INTO entities(kind,id,payload) VALUES
('propiedades','vm-rehearsal-property','{"nombre":"Inmueble sintetico de ensayo"}'),
('inquilinos','vm-rehearsal-tenant','{"nombre":"Inquilino sintetico","propiedadId":"vm-rehearsal-property","renta":600,"recibos":[{"id":"vm-rehearsal-receipt","mes":"2026-10","contenido":"cHJ1ZWJh"}]}'),
('incidencias','vm-rehearsal-incident','{"titulo":"Incidencia sintetica","propiedadId":"vm-rehearsal-property"}'),
('documentos','vm-rehearsal-document','{"nombre":"Documento sintetico","inquilinoId":"vm-rehearsal-tenant","contenido":"cHJ1ZWJh"}');
INSERT INTO pagos(id,inquilino_id,mes,estado,amount_due,amount_paid) VALUES
('vm-rehearsal-known','vm-rehearsal-tenant','2026-10','parcial',600,250),
('vm-rehearsal-historic','vm-rehearsal-tenant','2026-09','pagado',NULL,NULL);
COMMIT;
'@
# Artifacts and marker persist locally. No catalog for the actual client is changed.
Set-PrivateUpdateDirectory $work
$null=Invoke-UpdateSql $pg 'propiedades' $seed
$attachment=Join-Path $root 'attachments/rehearsal';Set-PrivateUpdateDirectory $attachment
[IO.File]::WriteAllBytes((Join-Path $attachment 'sentinel.bin'),[byte[]]@(0,1,255,42))
$marker=[pscustomobject]@{format=1;purpose='isolated-vm-update-rehearsal';installationRoot=$root;ownerSubject=$settings.OwnerSubject}
Write-PrivateUpdateJson (Join-Path $root 'config/local-rehearsal.json') $marker
Assert-LocalRehearsal $root
$evidence='vm-local-source-review-20261016'
$sourceId=$legacy.sourceId
$catalog=[pscustomobject]@{format=1;sources=@([pscustomobject]@{sourceId=$sourceId;reviewed=$true;reviewer='isolated-vm-operator';evidence=$evidence;originalArchiveSha256=$legacy.originalArchiveSha256;files=$legacy.files;dependencies=$dependencies;schema=$schema;frontend='local-rehearsal-no-portal';apiContract=$info.apiContract;services=$services})}
$observation=[pscustomobject]@{format=1;installationRoot=$root;completeInventory=$true;dependencies=$dependencies;schema=$history;frontend='local-rehearsal-no-portal';apiContract=$info.apiContract;services=$services;evidence=$evidence}
$inventory=[pscustomobject]@{format=1;complete=$true;evidence='vm-local-storage-review';attachments=@([pscustomobject]@{path='attachments/rehearsal'})}
$definition=[pscustomobject]@{format=2;kind='application-update';product='aelium-propiedades';platform='windows-x64';releaseId=$info.releaseId;buildId=$info.buildId;acceptedSources=@([pscustomobject]@{sourceId=$sourceId;evidence=$evidence});files=@([pscustomobject]@{path='bin/propiedades-backend.exe';target='release'});dependencies=$dependencies;schemaBefore=$schema;schemaAfter=$schema;migrations=@();apiContract=$info.apiContract;supportedFrontends=@([pscustomobject]@{id='local-rehearsal-no-portal';apiContract=$info.apiContract;evidence='local-only-no-frontend-acceptance'});recovery=[pscustomobject]@{sourceIds=@($sourceId);schema=$schema;checks=@('version','identity','read','write','frontend','cleanup');preserve=@('application','schema','data','identity','config','attachments','services')}}
foreach($pair in @(@('catalog.json',$catalog),@('observation.json',$observation),@('inventory.json',$inventory),@('definition.json',$definition))){Write-PrivateUpdateJson (Join-Path $work $pair[0]) $pair[1]}
$content=Join-Path $work 'content';New-Item -ItemType Directory -Path (Join-Path $content 'bin')|Out-Null
[IO.File]::Copy($candidate,(Join-Path $content 'bin/propiedades-backend.exe'),$false)
$archive=Join-Path $work 'application-update.zip'
$null=& (Join-Path $PSScriptRoot 'Build-UpdatePackage.ps1') -ContentRoot $content -DefinitionPath (Join-Path $work 'definition.json') -OutputArchive $archive
$hash=Get-UpdateFileHash $archive
$result=Invoke-ApplicationUpdate $root 'Preflight' $archive $hash $catalog $observation $inventory 55439 $null -LocalRehearsal
$result|Add-Member -NotePropertyName workDirectory -NotePropertyValue $work
$result|Add-Member -NotePropertyName archiveSha256 -NotePropertyValue $hash
$result|ConvertTo-Json -Depth 5
