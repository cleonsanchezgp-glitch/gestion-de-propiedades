. (Join-Path $PSScriptRoot '../../deploy/windows/client/Common.ps1')
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
$s = [pscustomobject]@{OwnerSubject=[Guid]::NewGuid().ToString();Username='test-owner';OwnerPassword='test-only-password';LoginSecret='test-only-client-secret'}
$realm = New-Realm $s
Assert ($realm.users[0].id -eq $s.OwnerSubject) 'Owner ID must be preserved in realm import.'
Assert ($realm.users[0].emailVerified -and $realm.users[0].firstName -and $realm.users[0].lastName -and $realm.users[0].email) 'User profile must be complete for direct grants.'
Assert ($realm.users[0].requiredActions.Count -eq 0) 'Portal login cannot handle interactive required actions.'
Assert ($realm.clients[0].directAccessGrantsEnabled -and -not $realm.clients[0].publicClient) 'Portal requires a confidential client.'
$xml = [xml](New-ServiceXml 'AeliumPostgres' 'C:\Native Server\postgres.exe' '-D "C:\Native Server\data"' 'C:\Native Server' @() 'C:\Native Server\pg_ctl.exe' 'stop -m fast')
Assert ($xml.service.startarguments -and $xml.service.stoparguments -and -not $xml.service.SelectSingleNode('arguments')) 'PostgreSQL must use a graceful stop command.'
Assert ($xml.service.serviceaccount.user -eq 'LocalService') 'Services must not run as LocalSystem.'
Assert ($xml.service.executable -eq 'C:\Native Server\postgres.exe') 'XML must preserve paths with spaces.'
for ($i=0;$i -lt 10;$i++) { Assert ((New-Secret) -match '^[a-f0-9]{64}$') 'Generated secrets must be URL/SQL safe and cryptographically random.' }
$temp = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts'))) ('installer-integrity-'+[Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $temp | Out-Null
$fixture = Join-Path $temp 'fixture.txt'
Write-Utf8 $fixture 'original'
$hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $fixture).Hash
Write-Utf8 (Join-Path $temp 'manifest.json') (@{format=1;platform='windows-x64';files=@(@{path='fixture.txt';sha256=$hash})} | ConvertTo-Json -Depth 4)
Assert-Package $temp
Write-Utf8 $fixture 'modified'
$rejected=$false
try { Assert-Package $temp } catch { $rejected=$true }
Assert $rejected 'Modified installation payload must be rejected.'
Write-Host 'Windows installer configuration, secret generation and integrity checks: PASS'
