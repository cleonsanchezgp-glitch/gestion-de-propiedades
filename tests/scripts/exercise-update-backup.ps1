[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$InstallationRoot,[Parameter(Mandatory=$true)][ValidateSet('capture','verify','restore','interrupt-restore','inspect','column-check')][string]$Action,[int]$VerificationPort=0)
. (Join-Path $PSScriptRoot '../../deploy/windows/update/Backup.ps1')
$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts/updates')).TrimEnd('\')+'\'
$root=[IO.Path]::GetFullPath($InstallationRoot).TrimEnd('\')
if (-not $root.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) {throw 'Fixture root outside update test artifacts.'}
$control=Open-UpdateControl $root
try {
    switch ($Action) {
        column-check {
            $pg=Get-UpdatePg $control
            $before=Get-UpdateDataFingerprint $pg 'keycloak' -LogicalColumns
            try {
                $null=Invoke-UpdateSql $pg 'keycloak' 'ALTER TABLE synthetic_column_history ALTER COLUMN retained DROP NOT NULL'
                $after=Get-UpdateDataFingerprint $pg 'keycloak' -LogicalColumns
                if($before.structure -ceq $after.structure){throw 'Logical fingerprint missed a changed nullability constraint.'}
            }finally{$null=Invoke-UpdateSql $pg 'keycloak' 'ALTER TABLE synthetic_column_history ALTER COLUMN retained SET NOT NULL'}
            if((Get-UpdateDataFingerprint $pg 'keycloak' -LogicalColumns).structure -cne $before.structure){throw 'Fixture schema did not return to baseline.'}
            [pscustomobject]@{status='ColumnConstraintChangeDetected'}|ConvertTo-Json -Compress
        }
        capture {New-CoherentUpdateBackup $control ([pscustomobject]@{format=1;complete=$true;evidence='synthetic-storage-review';attachments=@([pscustomobject]@{path='attachments/documents'})}) | ConvertTo-Json -Compress}
        verify {Test-CoherentUpdateBackup $control $VerificationPort | ConvertTo-Json -Compress}
        restore {Restore-CoherentUpdateBackup $control | ConvertTo-Json -Compress}
        interrupt-restore {
            $script:originalSql=${function:Invoke-UpdateSql}
            function Invoke-UpdateSql($Pg,[string]$Database,[string]$Sql) {
                $result=& $script:originalSql $Pg $Database $Sql
                if ($Sql -match '^ALTER DATABASE "propiedades" RENAME') {throw 'Synthetic crash immediately after first database quarantine rename.'}
                return $result
            }
            Restore-CoherentUpdateBackup $control | ConvertTo-Json -Compress
        }
        inspect {$backup=Read-CoherentUpdateBackup $control;[pscustomobject]@{verified=$backup.manifest.verified;databases=@($backup.manifest.databases.metadata.name);files=$backup.manifest.files.Count}|ConvertTo-Json -Compress}
    }
}catch {Write-Host $_.ScriptStackTrace;throw}finally{$control.lock.Dispose()}
