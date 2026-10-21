param([switch]$ValidateOnly,[switch]$UiSmokeTest)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$bundle=Join-Path $PSScriptRoot 'bundle.json'
$metadata=Get-Content -LiteralPath $bundle -Raw -Encoding UTF8 | ConvertFrom-Json
if ($metadata.format -ne 1 -or $metadata.mode -cnotin @('Preparation','ReviewedDelivery')) {throw 'Invalid desktop bundle.'}
# Validate all bundled files before loading maintenance code. Hashes are embedded in the EXE.
foreach ($file in $metadata.files) {
    if ($file.path -match '(^/|\\|:|\.\.)') {throw 'Invalid bundle path.'}
    $path=Join-Path $PSScriptRoot $file.path
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) {throw 'Bundle content differs.'}
}
if ($ValidateOnly) {return [pscustomobject]@{mode=$metadata.mode;files=$metadata.files.Count;status='DesktopBundleVerified'}}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form=New-Object Windows.Forms.Form
$form.Text='Actualizar PROMALZA';$form.Size=New-Object Drawing.Size(660,470)
$form.MinimumSize=$form.Size;$form.MaximumSize=$form.Size;$form.StartPosition='CenterScreen'
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$title=New-Object Windows.Forms.Label
$title.Text='Actualización del servidor PROMALZA';$title.SetBounds(24,20,600,32)
$title.Font=New-Object Drawing.Font('Segoe UI',16,[Drawing.FontStyle]::Bold)
$form.Controls.Add($title)
$description=New-Object Windows.Forms.Label
$description.SetBounds(24,65,600,72)
$description.Text=if($metadata.mode -ceq 'ReviewedDelivery') {'Comprueba la instalación, prepara la copia de seguridad y actualiza el backend. Mantén el ordenador encendido hasta terminar.'}else{'Falta revisar la instalación de este cliente. Obtén el inventario y envía el JSON al responsable para recibir el EXE de actualización compatible. Esta edición no modifica el backend.'}
$form.Controls.Add($description)
$label=New-Object Windows.Forms.Label;$label.Text='Carpeta de instalación';$label.SetBounds(24,144,550,24);$form.Controls.Add($label)
$root=New-Object Windows.Forms.TextBox;$root.SetBounds(24,172,510,28)
$root.Text='C:\ProgramData\Aelium\Propiedades'
if ($metadata.mode -ceq 'ReviewedDelivery') {$root.Text=$metadata.installationRoot}
$form.Controls.Add($root)
$browse=New-Object Windows.Forms.Button;$browse.Text='Buscar';$browse.SetBounds(544,170,78,30);$form.Controls.Add($browse)
$browse.Add_Click({$picker=New-Object Windows.Forms.FolderBrowserDialog;try{if($picker.ShowDialog() -eq 'OK'){$root.Text=$picker.SelectedPath}}finally{$picker.Dispose()}})
$progress=New-Object Windows.Forms.ProgressBar;$progress.SetBounds(24,222,598,18);$form.Controls.Add($progress)
$status=New-Object Windows.Forms.Label;$status.SetBounds(24,254,598,76);$status.Text='Listo.';$form.Controls.Add($status)
$primary=New-Object Windows.Forms.Button;$primary.SetBounds(24,352,190,42)
$primary.Text=if($metadata.mode -ceq 'ReviewedDelivery'){'Actualizar backend'}else{'Obtener inventario'};$form.Controls.Add($primary)
$finalize=New-Object Windows.Forms.Button;$finalize.Text='Reintentar verificación';$finalize.SetBounds(224,352,190,42);$finalize.Visible=($metadata.mode -ceq 'ReviewedDelivery');$form.Controls.Add($finalize)
$recover=New-Object Windows.Forms.Button;$recover.Text='Recuperar';$recover.SetBounds(424,352,100,42);$recover.Visible=$finalize.Visible;$form.Controls.Add($recover)
$close=New-Object Windows.Forms.Button;$close.Text='Cerrar';$close.SetBounds(534,352,88,42);$close.Add_Click({$form.Close()});$form.Controls.Add($close)
$script:job=$null;$script:handle=$null;$script:pendingAction='';$script:outputPath=''
$timer=New-Object Windows.Forms.Timer;$timer.Interval=500
function Get-OwnerCredential {
    $dialog=New-Object Windows.Forms.Form;$dialog.Text='Cuenta del propietario';$dialog.Size=New-Object Drawing.Size(410,240);$dialog.StartPosition='CenterParent';$dialog.FormBorderStyle='FixedDialog';$dialog.MaximizeBox=$false;$dialog.MinimizeBox=$false
    $userLabel=New-Object Windows.Forms.Label;$userLabel.Text='Usuario del portal';$userLabel.SetBounds(20,15,350,22)
    $user=New-Object Windows.Forms.TextBox;$user.SetBounds(20,40,350,25)
    $passLabel=New-Object Windows.Forms.Label;$passLabel.Text='Contraseña (no se guarda)';$passLabel.SetBounds(20,75,350,22)
    $pass=New-Object Windows.Forms.TextBox;$pass.SetBounds(20,100,350,25);$pass.UseSystemPasswordChar=$true
    $ok=New-Object Windows.Forms.Button;$ok.Text='Continuar';$ok.SetBounds(160,150,100,32);$ok.DialogResult='OK'
    $cancel=New-Object Windows.Forms.Button;$cancel.Text='Cancelar';$cancel.SetBounds(270,150,100,32);$cancel.DialogResult='Cancel'
    $dialog.Controls.AddRange(@($userLabel,$user,$passLabel,$pass,$ok,$cancel));$dialog.AcceptButton=$ok;$dialog.CancelButton=$cancel
    try {if($dialog.ShowDialog($form) -ne 'OK'){return $null};if(-not $user.Text -or -not $pass.Text){return $null};$secure=ConvertTo-SecureString $pass.Text -AsPlainText -Force;return New-Object Management.Automation.PSCredential($user.Text,$secure)}finally{$pass.Clear();$dialog.Dispose()}
}
function Start-DesktopAction([string]$Action) {
    if($null -ne $script:job){return}
    $installation=[IO.Path]::GetFullPath($root.Text).TrimEnd('\')
    if(-not(Test-Path -LiteralPath (Join-Path $installation 'config/settings.json') -PathType Leaf)){$status.Text='No se encuentra una instalación en esa carpeta.';return}
    $credential=$null;$output=''
    if($Action -ceq 'Inventory'){
        $save=New-Object Windows.Forms.SaveFileDialog;$save.Filter='Inventario JSON (*.json)|*.json';$save.FileName='promalza-inventario-cliente.json'
        try{if($save.ShowDialog($form) -ne 'OK'){return};$output=$save.FileName}finally{$save.Dispose()}
        if([IO.Path]::GetFullPath($output).StartsWith($installation+'\',[StringComparison]::OrdinalIgnoreCase)){
            $status.Text='Guarda el inventario fuera de la carpeta de instalación, por ejemplo en el Escritorio.';return
        }
    }else{
        if($metadata.mode -cne 'ReviewedDelivery') {return}
        if($Action -ceq 'Recover' -and [Windows.Forms.MessageBox]::Show($form,'Recuperar solo una operación interrumpida o fallida. ¿Continuar?','PROMALZA','YesNo','Question') -ne 'Yes'){return}
        $credential=Get-OwnerCredential;if($null -eq $credential){return}
    }
    $script:pendingAction=$Action;$script:outputPath=$output
    $worker={param($Directory,$Action,$Root,$Credential,$Output)
        $ErrorActionPreference='Stop'
        if($Action -ceq 'Inventory'){
            & (Join-Path $Directory 'Inventariar-Instalacion-Cliente.ps1') -InstallRoot $Root -OutputPath $Output | Out-Null
            return [pscustomobject]@{status='InventoryCreated'}
        }
        . (Join-Path $Directory 'update/Updater.ps1')
        $meta=Read-UpdateJson (Join-Path $Directory 'bundle.json')
        if($meta.mode -cne 'ReviewedDelivery'){throw 'Delivery not reviewed.'}
        $catalog=Read-UpdateJson (Join-Path $Directory 'delivery/catalog.json')
        $observation=Read-UpdateJson (Join-Path $Directory 'delivery/observation.json')
        $inventory=Read-UpdateJson (Join-Path $Directory 'delivery/inventory.json')
        $archive=Join-Path $Directory 'delivery/application.zip'
        if($Action -ceq 'Apply'){
            $preflight=Test-ApplicationUpdatePreflight $Root $archive $meta.archiveSha256 $catalog $observation $inventory
            if($preflight.status -ceq 'AlreadyApplied'){return [pscustomobject]@{status='AlreadyApplied'}}
        }
        Invoke-ApplicationUpdate $Root $Action $archive $meta.archiveSha256 $catalog $observation $inventory 55439 $Credential
    }
    $script:job=[PowerShell]::Create()
    $null=$script:job.AddScript($worker.ToString()).AddArgument($PSScriptRoot).AddArgument($Action).AddArgument($installation).AddArgument($credential).AddArgument($output)
    $script:handle=$script:job.BeginInvoke()
    foreach($control in @($root,$browse,$primary,$finalize,$recover,$close)){$control.Enabled=$false}
    $progress.Style='Marquee';$status.Text=if($Action -ceq 'Inventory'){'Consultando la instalación. No se modifica el backend.'}else{'Comprobando y ejecutando la operación. No cierres ni apagues el equipo.'};$timer.Start()
}
$timer.Add_Tick({
    if($null -eq $script:job -or -not $script:handle.IsCompleted){return}
    $timer.Stop()
    try {
        $result=@($script:job.EndInvoke($script:handle))
        if($script:job.HadErrors -or -not $result.Count){throw 'Operation failed.'}
        $last=$result[-1];$status.Text=switch([string]$last.status){
            'InventoryCreated' {'Inventario guardado. Envíalo al responsable; no envíes configuraciones ni bases de datos.'}
            'UpdateSucceeded' {'Backend actualizado y verificado. Ya puedes comprobar el portal.'}
            'AlreadyApplied' {'Esta actualización exacta ya estaba aplicada.'}
            'VerificationPending' {'Verificación pendiente. Comprueba el portal con el responsable y pulsa Reintentar verificación.'}
            'UpdateFailedRecovered' {'La actualización ha fallado y se ha recuperado la versión anterior. Contacta con el responsable.'}
            'Recovered' {'Versión anterior recuperada. Comprueba el portal con el responsable.'}
            default {'No se declara una actualización completada. Contacta con el responsable antes de continuar.'}
        }
    }catch{$status.Text='No se ha completado la operación. No reinstales ni borres copias. Contacta con el responsable; una operación interrumpida puede necesitar recuperación.'}
    finally{$script:job.Dispose();$script:job=$null;$script:handle=$null;$progress.Style='Blocks';foreach($control in @($root,$browse,$primary,$finalize,$recover,$close)){$control.Enabled=$true}}
})
$primary.Add_Click({try{Start-DesktopAction $(if($metadata.mode -ceq 'ReviewedDelivery'){'Apply'}else{'Inventory'})}catch{$status.Text='No se ha podido iniciar. Revisa la carpeta y contacta con el responsable.'}})
$finalize.Add_Click({try{Start-DesktopAction 'Finalize'}catch{$status.Text='No se ha podido iniciar la verificación.'}})
$recover.Add_Click({try{Start-DesktopAction 'Recover'}catch{$status.Text='No se ha podido iniciar la recuperación.'}})
$form.Add_FormClosing({param($sender,$eventArgs) if($null -ne $script:job){$eventArgs.Cancel=$true}})
if($UiSmokeTest){
    try {
        # Construct the real controls and event handlers, without showing a window or running maintenance.
        if($metadata.mode -ceq 'Preparation' -and $primary.Text -cne 'Obtener inventario'){throw 'Unsafe preparation action.'}
        if($metadata.mode -ceq 'ReviewedDelivery' -and $primary.Text -cne 'Actualizar backend'){throw 'Missing update action.'}
        if($form.Controls.Count -lt 10){throw 'Incomplete desktop window.'}
        return [pscustomobject]@{status='DesktopUiConstructed';mode=$metadata.mode;controls=$form.Controls.Count}
    }finally{$timer.Dispose();$form.Dispose()}
}
try{[Windows.Forms.Application]::Run($form)}finally{$timer.Dispose();$form.Dispose()}
