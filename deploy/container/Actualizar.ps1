[CmdletBinding()]
param([ValidateSet('Install','Update','Recover')][string]$Action='Update')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$envFile=Join-Path $root '.env'
$stateDir=Join-Path $root 'state'
$currentFile=Join-Path $stateDir 'current.json'
$pendingFile=Join-Path $stateDir 'pending.json'
if(-not (Test-Path -LiteralPath $envFile -PathType Leaf)){throw 'Falta deploy/container/.env.'}
if(-not (Get-Command docker -ErrorAction SilentlyContinue)){throw 'Docker Desktop no esta disponible.'}
$lines=Get-Content -LiteralPath $envFile -Encoding UTF8
$values=@{}
foreach($line in $lines){
    if($line -match '^\s*([A-Z_]+)=(.*)$'){$values[$Matches[1]]=$Matches[2].Trim()}
}
foreach($name in @('BACKUP_DIR','API_IMAGE')){if(-not $values[$name]){throw "Falta $name en .env."}}
$apiPort=if($values.API_PORT){$values.API_PORT}else{'58090'}
$keycloakPort=if($values.KEYCLOAK_PORT){$values.KEYCLOAK_PORT}else{'58082'}
foreach($port in @($apiPort,$keycloakPort)){if($port -notmatch '^[0-9]{2,5}$' -or [int]$port -gt 65535){throw 'Puerto local invalido.'}}
$backupRoot=[IO.Path]::GetFullPath($values.BACKUP_DIR)
if(-not [IO.Path]::IsPathRooted($backupRoot) -or $backupRoot -eq [IO.Path]::GetPathRoot($backupRoot)){throw 'BACKUP_DIR debe ser una carpeta absoluta dedicada.'}
New-Item -ItemType Directory -Force -Path $stateDir,$backupRoot | Out-Null
Start-Transcript -Path (Join-Path $stateDir 'update.log') -Append | Out-Null
$compose=@('compose','--env-file',$envFile,'-f',(Join-Path $root 'compose.yaml'))
function Run-Docker {
    $arguments=if($args.Count -eq 1 -and $args[0] -is [array]){$args[0]}else{$args}
    & docker @arguments
    if($LASTEXITCODE -ne 0){throw ('Docker fallo: '+($arguments -join ' '))}
}
function Compose {
    $arguments=if($args.Count -eq 1 -and $args[0] -is [array]){$args[0]}else{$args}
    Run-Docker ($compose+$arguments)
}
function Save-Json([string]$Path,[object]$Value){
    $tmp=$Path+'.tmp'
    [IO.File]::WriteAllText($tmp,($Value|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Image-Info([string]$Image){
    $raw=& docker run --rm $Image --release-info
    if($LASTEXITCODE -ne 0){throw 'La imagen no declara metadatos de version.'}
    $info=($raw|Out-String|ConvertFrom-Json)
    if($info.product -ne 'aelium-propiedades' -or $info.format -ne 1 -or -not $info.transactionalMigrations -or $info.apiContract -ne 'propiedades-v3'){
        throw 'Imagen incompatible: producto, contrato o migraciones.'
    }
    return $info
}
function Image-Id([string]$Image){
    $id=& docker image inspect --format '{{.Id}}' $Image
    if($LASTEXITCODE -ne 0 -or $id -notmatch '^sha256:[a-f0-9]{64}$'){throw 'No se pudo identificar la imagen.'}
    return $id.Trim()
}
function Wait-Http([string]$Url,[int]$Seconds){
    $limit=(Get-Date).AddSeconds($Seconds)
    do{
        try{ $response=Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5; if($response.StatusCode -eq 200){return} }catch{}
        Start-Sleep -Seconds 3
    }while((Get-Date) -lt $limit)
    throw ('No responde: '+$Url)
}
function Verify-Dump([string]$Service,[string]$User,[string]$Operation,[string]$Filename){
    $database='verify_'+(Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
    Compose @('exec','-T',$Service,'createdb','-U',$User,$database)
    try{Compose @('exec','-T',$Service,'pg_restore','-U',$User,'--exit-on-error','-d',$database,('/backups/'+$Operation+'/'+$Filename))}
    finally{Compose @('exec','-T',$Service,'dropdb','-U',$User,'--if-exists',$database)}
}
function Start-Current([string]$Image,[string]$ExpectedRelease){
    $env:API_IMAGE=$Image
    Compose @('up','-d','--no-deps','keycloak')
    Compose @('up','-d','--no-deps','api')
    Wait-Http ('http://127.0.0.1:'+$apiPort+'/health/live') 90
    Wait-Http ('http://127.0.0.1:'+$keycloakPort+'/realms/'+$values.KEYCLOAK_REALM+'/.well-known/openid-configuration') 120
    $active=& docker @compose exec -T api propiedades-backend --release-info
    if($LASTEXITCODE -ne 0 -or (($active|Out-String|ConvertFrom-Json).releaseId -ne $ExpectedRelease)){throw 'La API activa no coincide con la version esperada.'}
}
function Restore-Backup([object]$Record){
    $folder=Join-Path $backupRoot $Record.operation
    Compose @('stop','api','keycloak')
    if($Record.stage -ne 'PreBackup'){
        foreach($item in @(@('postgres','propiedades','propiedades.dump'),@('keycloak-db','keycloak','keycloak.dump'))){
            if(-not (Test-Path -LiteralPath (Join-Path $folder $item[2]) -PathType Leaf)){throw 'Falta una copia para recuperar.'}
        }
        foreach($item in @(@('postgres','propiedades','propiedades.dump'),@('keycloak-db','keycloak','keycloak.dump'))){
            $service=$item[0];$database=$item[1];$file=$item[2]
            Compose @('exec','-T',$service,'dropdb','-U',$database,'--if-exists',$database)
            Compose @('exec','-T',$service,'createdb','-U',$database,$database)
            Compose @('exec','-T',$service,'pg_restore','-U',$database,'--exit-on-error','-d',$database,('/backups/'+$Record.operation+'/'+$file))
        }
    }
    Start-Current $Record.previousImage $Record.previousRelease
    Save-Json $currentFile @{image=$Record.previousImage;releaseId=$Record.previousRelease;updatedAt=(Get-Date).ToUniversalTime().ToString('o')}
    Remove-Item -LiteralPath $pendingFile
}
$mutex=[Threading.Mutex]::new($false,'Local\AeliumPropiedadesDockerUpdate')
if(-not $mutex.WaitOne(0)){$mutex.Dispose();Stop-Transcript|Out-Null;throw 'Ya hay una actualizacion Docker en curso.'}
try{
if($Action -eq 'Recover'){
    if(-not (Test-Path -LiteralPath $pendingFile)){throw 'No existe una actualizacion pendiente de recuperacion.'}
    Restore-Backup (Get-Content -LiteralPath $pendingFile -Raw|ConvertFrom-Json)
    Write-Host 'Recuperacion comprobada.'
    return
}
if(Test-Path -LiteralPath $pendingFile){throw 'Hay una actualizacion incompleta. Ejecute Actualizar.ps1 -Action Recover.'}
if($Action -eq 'Install' -and (Test-Path -LiteralPath $currentFile)){throw 'La instalacion ya esta registrada.'}
if($Action -eq 'Update' -and -not (Test-Path -LiteralPath $currentFile)){throw 'Ejecute primero Actualizar.ps1 -Action Install.'}
try{
    Run-Docker @('info','--format','{{.ServerVersion}}')
    if($Action -eq 'Install'){
        Compose @('config','--quiet')
        Compose @('pull','--policy','always','postgres','keycloak-db','keycloak')
    }
    Run-Docker @('pull',$values.API_IMAGE)
    $candidate=Image-Id $values.API_IMAGE
    $target=Image-Info $candidate
    if($Action -eq 'Install'){
        $env:API_IMAGE=$candidate
        Compose @('up','-d','postgres','keycloak-db','keycloak')
        Compose @('run','--rm','api','--container-migrate')
        Compose @('up','-d','--no-deps','api')
        Wait-Http ('http://127.0.0.1:'+$apiPort+'/health/live') 90
        Wait-Http ('http://127.0.0.1:'+$keycloakPort+'/realms/master/.well-known/openid-configuration') 120
        $active=& docker @compose exec -T api propiedades-backend --release-info
        if($LASTEXITCODE -ne 0 -or (($active|Out-String|ConvertFrom-Json).releaseId -ne $target.releaseId)){throw 'La API activa no coincide con la imagen instalada.'}
        Save-Json $currentFile @{image=$candidate;releaseId=$target.releaseId;updatedAt=(Get-Date).ToUniversalTime().ToString('o')}
        Write-Host ('Instalada '+$target.releaseId)
        return
    }
    $current=Get-Content -LiteralPath $currentFile -Raw|ConvertFrom-Json
    if($candidate -eq $current.image){Write-Host 'Ya esta instalada la imagen publicada.';return}
    $source=Image-Info $current.image
    if($source.releaseId -ne $current.releaseId){throw 'La version registrada no coincide con la imagen local.'}
    if(@($target.migrations).Count -lt @($source.migrations).Count){throw 'La imagen publicada retrocede el esquema.'}
    for($i=0;$i -lt @($source.migrations).Count;$i++){
        if($source.migrations[$i].version -ne $target.migrations[$i].version -or $source.migrations[$i].checksum -ne $target.migrations[$i].checksum){throw 'Historial de migraciones incompatible.'}
    }
    $operation='update-'+(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $folder=Join-Path $backupRoot $operation
    New-Item -ItemType Directory -Path $folder | Out-Null
    $record=@{operation=$operation;previousImage=$current.image;previousRelease=$current.releaseId;targetImage=$candidate;targetRelease=$target.releaseId;stage='PreBackup'}
    Save-Json $pendingFile $record
    Compose @('stop','api','keycloak')
    Compose @('exec','-T','postgres','pg_dump','-U','propiedades','-Fc','-f',('/backups/'+$operation+'/propiedades.dump'),'propiedades')
    Compose @('exec','-T','keycloak-db','pg_dump','-U','keycloak','-Fc','-f',('/backups/'+$operation+'/keycloak.dump'),'keycloak')
    foreach($item in @(@('postgres','propiedades','propiedades.dump'),@('keycloak-db','keycloak','keycloak.dump'))){
        $file=Join-Path $folder $item[2]
        if(-not (Test-Path -LiteralPath $file) -or (Get-Item -LiteralPath $file).Length -lt 100){throw 'La copia esta incompleta.'}
        Verify-Dump $item[0] $item[1] $operation $item[2]
    }
    Copy-Item -LiteralPath $envFile -Destination (Join-Path $folder 'configuration.env')
    $record.stage='BackedUp'
    Save-Json $pendingFile $record
    $env:API_IMAGE=$candidate
    Compose @('run','--rm','--no-deps','api','--container-migrate')
    Start-Current $candidate $target.releaseId
    Save-Json $currentFile @{image=$candidate;releaseId=$target.releaseId;updatedAt=(Get-Date).ToUniversalTime().ToString('o')}
    Remove-Item -LiteralPath $pendingFile
    Write-Host ('Actualizada '+$current.releaseId+' -> '+$target.releaseId+'; copia: '+$folder)
}catch{
    $reason=$_.Exception.Message
    if($Action -eq 'Update' -and (Test-Path -LiteralPath $pendingFile)){
        try{Restore-Backup (Get-Content -LiteralPath $pendingFile -Raw|ConvertFrom-Json)}
        catch{throw ('Actualizacion fallida: '+$reason+'. Recuperacion pendiente: '+$_.Exception.Message)}
    }
    throw ('Operacion fallida: '+$reason)
}finally{
    Remove-Item Env:API_IMAGE -ErrorAction SilentlyContinue
}
}finally{
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    Stop-Transcript | Out-Null
}
