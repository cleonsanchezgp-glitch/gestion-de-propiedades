param([switch]$Json)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\Aelium\Propiedades'
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Ejecutar como administrador en la VM.'}
$secretValues=@()
foreach($name in @('settings.json','api.json','keycloak.json')){
    $path=Join-Path $root ('config/'+$name)
    if(Test-Path -LiteralPath $path){
        $settings=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        foreach($property in $settings.PSObject.Properties){if($property.Name -match 'password|secret|token' -and $property.Value -is [string] -and $property.Value.Length -ge 4){$secretValues+=$property.Value}}
    }
}
$logs=@(foreach($name in @('AeliumAPI.err.log','AeliumAPI.out.log','AeliumAPI.wrapper.log')){
    $path=Join-Path $root ('logs/'+$name)
    if(Test-Path -LiteralPath $path){
        $file=Get-Item -LiteralPath $path
        $lines=@(Get-Content -LiteralPath $path -Tail 140|Where-Object{$_ -match 'error|exception|denied|denegado|invalid|failed|cannot|timed out|panic|missing|unavailable|integrity|no se puede|no se encuentra'}|Select-Object -Last 8|ForEach-Object{
            $line=[string]$_
            foreach($secret in $secretValues){$line=$line.Replace($secret,'[REDACTED]')}
            $line=[regex]::Replace($line,'(?i)(postgres(?:ql)?://[^:\s]+:)[^@\s]+@','$1[REDACTED]@')
            if($line.Length -gt 300){$line.Substring(0,300)+'...'}else{$line}
        })
        [pscustomobject]@{file=$name;bytes=$file.Length;lastWriteUtc=$file.LastWriteTimeUtc.ToString('o');errors=$lines}
    }
})
$acl=@(foreach($relative in @('releases','releases/rehearsal-vm-20261016-r1','releases/rehearsal-vm-20261016-r1/manifest.json','releases/rehearsal-vm-20261016-r1/bin/propiedades-backend.exe','maintenance','maintenance/operation.json','maintenance/write-gate.lock')){
    $path=Join-Path $root $relative
    if(Test-Path -LiteralPath $path){
        $rules=@((Get-Acl -LiteralPath $path).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])|Where-Object{$_.IdentityReference.Value -eq 'S-1-5-19'}|ForEach-Object{[pscustomobject]@{rights=[string]$_.FileSystemRights;type=[string]$_.AccessControlType;inherited=$_.IsInherited}})
        [pscustomobject]@{path=$relative;localServiceRules=$rules}
    }
})
$result=[pscustomobject]@{scope='Read-only API startup diagnosis; configured secrets redacted; no service or data changes';observedUtc=[DateTime]::UtcNow.ToString('o');apiLogs=$logs;serviceReadPermissions=$acl}
if($Json){$result|ConvertTo-Json -Depth 7}else{
    Write-Output ('Diagnostico de solo lectura: '+$result.observedUtc)
    foreach($log in $logs){
        Write-Output ('--- '+$log.file+' ---')
        if($log.errors.Count){foreach($line in $log.errors){Write-Output $line}}else{Write-Output 'Sin errores coincidentes en las ultimas 140 lineas.'}
    }
    Write-Output '--- Permisos de lectura de LocalService ---'
    foreach($entry in $acl){
        $summary=(@($entry.localServiceRules|ForEach-Object{$_.type+':'+$_.rights}) -join '; ')
        if(-not $summary){$summary='SIN REGLA DIRECTA/HEREDADA PARA LocalService'}
        Write-Output ($entry.path+' => '+$summary)
    }
}
$secretValues=$null;$settings=$null
