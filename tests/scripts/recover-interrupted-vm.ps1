[CmdletBinding()]
param(
    [string]$ExpectedOperationId='update-97776b9fb9cd4eff8bd1c5bbaf6a3c25'
)
$ErrorActionPreference='Stop'
$stage='administrator-check';$secure=$null;$control=$null;$credential=$null
try {
    $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        Write-Host 'Abre Windows PowerShell con Ejecutar como administrador y repite este comando. No se ha cambiado ningun servicio.'
        return
    }
    $stage='virtual-machine-check'
    if((Get-CimInstance Win32_ComputerSystem).Model -notmatch 'VirtualBox'){throw 'VM required.'}
    $stage='tool-integrity-check'
    $toolRoot='C:\AeliumCopia-r6';$archive='C:\AeliumCopia-r6.zip'
    if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne '0c5183f9a2762277809159e8172cbeb9d85224a460326eb750949c352bc63c32'){throw 'Pinned tools mismatch.'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach($directory in @($toolRoot,(Join-Path $toolRoot 'update'))){if((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unsafe tools directory.'}}
        foreach($name in @('update/Updater.ps1','update/Backup.ps1','update/Control.ps1','update/Package.ps1','update/NativeServices.cs')){
            $entry=$zip.GetEntry($name);if(-not $entry){throw 'Missing pinned tool.'}
            $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
            try{$expected=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
            $path=Join-Path $toolRoot $name
            if((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unsafe tool file.'}
            if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $expected){throw 'Installed tool mismatch.'}
        }
    }finally{$zip.Dispose()}
    . (Join-Path $toolRoot 'update/Updater.ps1')
    $root='C:\ProgramData\Aelium\Propiedades'
    $stage='rehearsal-check';Assert-LocalRehearsal $root
    $stage='exclusive-operation-check'
    $control=Open-UpdateControl $root
    $control|Add-Member -NotePropertyName verificationMode -NotePropertyValue 'LocalRehearsal'
    $operation=Read-UpdateJson $control.operationPath;Assert-Operation $operation
    $context=Read-UpdateJson (Join-Path $root 'maintenance/context.json')
    if($operation.operationId -cne $ExpectedOperationId -or $context.operationId -cne $ExpectedOperationId -or $context.format -ne 1 -or $operation.sourceReleaseId -cne $context.sourceId -or $operation.targetReleaseId -cne $context.manifest.releaseId -or $context.applicationChangeStarted -isnot [bool] -or $context.applicationChangeStarted -or (Get-UpdateVerificationMode $context) -cne 'LocalRehearsal'){throw 'Unexpected operation; no recovery attempted.'}
    if($operation.phase -ceq 'Recovered'){
        [pscustomobject]@{status='AlreadyRecovered';operationId=$ExpectedOperationId;updateSucceeded=$false}|ConvertTo-Json -Compress
        return
    }
    if($operation.phase -cnotin @('BackingUp','Recovering','RecoveryRequired')){throw 'Unexpected phase; no recovery attempted.'}
    $settings=Read-UpdateJson (Join-Path $root 'config/settings.json')
    $stage='credential-input'
    $secure=Read-Host ('Contrasena de pruebas de '+$settings.Username+' (no se guarda)') -AsSecureString
    $credential=New-Object Management.Automation.PSCredential($settings.Username,$secure)
    Write-Host 'Recuperando la instalacion anterior. No se aplica la candidata ni se restaura una copia incompleta.'
    $stage='controlled-recovery'
    try {
        $result=Invoke-ApplicationUpdateRecovery $control $context $credential
        Get-UpdateResult $result.status $result 'LocalRehearsal'|ConvertTo-Json -Depth 6
    }catch{
        $failure=$_;$current=Read-UpdateJson $control.operationPath
        Write-ControlJson $control (Join-Path $root 'maintenance/recovery-failure.json') ([pscustomobject]@{format=1;operationId=$current.operationId;failureStep=$current.step;reasonCode='RecoveryChecksFailed';trace=$failure.ScriptStackTrace})
        Set-ApplicationUpdatePhase $control 'RecoveryRequired' 'recovery-required'
        [pscustomobject]@{status='RecoveryRequired';operationId=$ExpectedOperationId;failureStep=$current.step;trace=$failure.ScriptStackTrace;updateSucceeded=$false}|ConvertTo-Json -Depth 5
    }
}catch{
    [pscustomobject]@{status='RecoveryRejected';stage=$stage;errorType=$_.Exception.GetType().Name;trace=$_.ScriptStackTrace;updateSucceeded=$false}|ConvertTo-Json -Depth 5
}finally{
    if($control){$control.lock.Dispose()}
    $credential=$null
    if($secure){$secure.Dispose()}
}
