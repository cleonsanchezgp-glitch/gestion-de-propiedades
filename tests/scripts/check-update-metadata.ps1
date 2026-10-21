$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../deploy/windows/update/Backup.ps1')
$a=@([pscustomobject]@{s='private-schema';n='private-sequence';owner='secret-owner';last_value=12},[pscustomobject]@{s='private-schema';n='other';owner='secret-owner';last_value=$null})
$b=@($a[1],$a[0])
$result=Compare-UpdateMetadataRows $a $b @('s','n')
if($result.changedFields.Count -or $result.missingCount -or $result.extraCount){throw 'Reordering must not be reported as metadata changes.'}
$b=@([pscustomobject]@{s='private-schema';n='private-sequence';owner='other-owner';last_value=13})
$result=Compare-UpdateMetadataRows $a $b @('s','n')
if($result.missingCount -ne 1 -or $result.extraCount -ne 0 -or ($result.changedFields.field -join ',') -cne 'last_value,owner'){throw 'Field difference/missing object diagnosis failed.'}
if(($result|ConvertTo-Json -Depth 8) -match 'private-|secret-|other-owner'){throw 'Diagnostic exported private metadata values.'}
$result=Compare-UpdateMetadataRows @() @() @('s','n')
if($result.sourceCount -or $result.restoredCount -or $result.changedFields.Count){throw 'Empty metadata diagnosis failed.'}
$result=Compare-UpdateMetadataRows @([pscustomobject]@{s='s';n='n';value=$null}) @([pscustomobject]@{s='s';n='n';value=0}) @('s','n')
if(($result.changedFields.field -join ',') -cne 'value'){throw 'NULL must differ from zero.'}
$wrapped=[pscustomobject]@{value=@($a);Count=$a.Count}
$result=Compare-UpdateMetadataRows $wrapped $a @('s','n')
if($result.sourceCount -ne 2 -or $result.changedFields.Count -or $result.missingCount){throw 'PS 5.1 serialized array wrapper diagnosis failed.'}
$nested=New-Object object[] 1;$nested[0]=$a
$result=Compare-UpdateMetadataRows $nested $a @('s','n')
if($result.sourceCount -ne 2 -or $result.missingCount -or $result.changedFields.Count){throw 'Nested pipeline array diagnosis failed.'}
Write-Output '7 metadata diagnostic checks PASS'
