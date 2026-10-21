$ErrorActionPreference='Stop'
$results=@(Get-WinEvent -FilterHashtable @{LogName='Application';Id=1002;StartTime=(Get-Date).AddDays(-2)} -MaxEvents 10 -ErrorAction SilentlyContinue|ForEach-Object{
    $event=$_;$xml=[xml]$event.ToXml();$application=$null
    foreach($data in @($xml.Event.EventData.Data)){
        if($data.Name -in @('AppName','ExeFileName')){
            $candidate=[IO.Path]::GetFileName([string]$data.'#text')
            if($candidate -match '^[a-zA-Z0-9_. -]{1,80}\.exe$'){$application=$candidate;break}
        }
    }
    [pscustomobject]@{observedUtc=$event.TimeCreated.ToUniversalTime().ToString('o');id=$event.Id;application=$application}
})
[pscustomobject]@{scope='Read-only application hang identifiers; no raw event messages';applicationHangs=$results}|ConvertTo-Json -Depth 4
