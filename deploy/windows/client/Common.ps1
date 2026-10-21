Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
function Write-Utf8($Path, $Content) {
    [IO.File]::WriteAllText($Path,$Content,(New-Object Text.UTF8Encoding($false)))
}
function New-Secret {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
}
function Expand-Vendor($Archive, $Destination, $Expected) {
    if (Test-Path -LiteralPath (Join-Path $Destination $Expected)) { return }
    $staging = $Destination + '.expanded'
    if (Test-Path -LiteralPath $staging) { throw ('Previous expansion exists: ' + $staging) }
    New-Item -ItemType Directory -Path $staging | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive,$staging)
    $top = @(Get-ChildItem -LiteralPath $staging -Directory)
    if ($top.Count -ne 1) { throw 'Unexpected vendor archive layout.' }
    Move-Item -LiteralPath $top[0].FullName -Destination $Destination
    # Keep the empty staging directory; no recursive deletion during installation.
    Remove-Item -LiteralPath $staging
    if (-not (Test-Path -LiteralPath (Join-Path $Destination $Expected))) { throw 'Incomplete vendor archive.' }
}
function Assert-Package($Directory) {
    $manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $Directory 'manifest.json') | ConvertFrom-Json
    if ($manifest.format -ne 1 -or $manifest.platform -ne 'windows-x64') { throw 'Unsupported package.' }
    $prefix = [IO.Path]::GetFullPath($Directory).TrimEnd('\') + '\'
    foreach ($file in $manifest.files) {
        $path = [IO.Path]::GetFullPath((Join-Path $Directory $file.path))
        if (-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid package path.' }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $file.sha256) { throw ('Package integrity failed: ' + $file.path) }
    }
}
function New-Realm($Settings) {
    return @{
        realm='propiedades';enabled=$true;sslRequired='none';bruteForceProtected=$true;registrationAllowed=$false
        users=@(@{id=$Settings.OwnerSubject;username=$Settings.Username;enabled=$true;firstName='Propietario';lastName='Portal';email=($Settings.OwnerSubject+'@example.invalid');emailVerified=$true;requiredActions=@();credentials=@(@{type='password';value=$Settings.OwnerPassword;temporary=$false})})
        clients=@(@{clientId='portal-login';enabled=$true;publicClient=$false;secret=$Settings.LoginSecret;standardFlowEnabled=$false;directAccessGrantsEnabled=$true;serviceAccountsEnabled=$false
            attributes=@{'access.token.lifespan'='1800';'client.session.idle.timeout'='1800';'client.session.max.lifespan'='1800'}
            protocolMappers=@(@{name='backend-audience';protocol='openid-connect';protocolMapper='oidc-audience-mapper';config=@{'included.custom.audience'='propiedades-api';'access.token.claim'='true';'id.token.claim'='false'}})})
    }
}
function New-ServiceXml($Id,$Executable,$Arguments,$Root,$Dependencies=@(),$StopExecutable='',$StopArguments='') {
    function Xml($value) { return [Security.SecurityElement]::Escape([string]$value) }
    $deps = ($Dependencies | ForEach-Object { '<depend>' + (Xml $_) + '</depend>' }) -join ''
    $argsElement = if ($StopExecutable) { '<startarguments>'+(Xml $Arguments)+'</startarguments><stopexecutable>'+(Xml $StopExecutable)+'</stopexecutable><stoparguments>'+(Xml $StopArguments)+'</stoparguments>' } else { '<arguments>'+(Xml $Arguments)+'</arguments>' }
    return '<service><id>'+(Xml $Id)+'</id><name>'+(Xml $Id)+'</name><description>Gestion de propiedades - servidor del cliente</description><executable>'+(Xml $Executable)+'</executable>'+$argsElement+'<workingdirectory>'+(Xml $Root)+'</workingdirectory><startmode>Automatic</startmode><delayedAutoStart>true</delayedAutoStart><serviceaccount><domain>NT AUTHORITY</domain><user>LocalService</user></serviceaccount>'+$deps+'<onfailure action="restart" delay="10 sec"/><stoptimeout>60 sec</stoptimeout><logpath>'+(Xml (Join-Path $Root 'logs'))+'</logpath><log mode="roll-by-size"><sizeThreshold>10240</sizeThreshold><keepFiles>5</keepFiles></log></service>'
}
function Wait-Http($Url,$Seconds=120) {
    $until = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        try { $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 3; if ($r.StatusCode -eq 200) { return } } catch {}
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $until)
    throw ('Service did not become ready: ' + $Url + '. Inspect the private logs directory.')
}
function Invoke-LocalApi($Method,$Url,$Origin='',$Body='',$Cookie='') {
    # Production cookies are Secure. For this loopback-only diagnostic, explicitly
    # send the cookie without .NET's automatic HTTP cookie filtering.
    $parsed = [Uri]$Url
    if ($parsed.Scheme -ne 'http' -or $parsed.Host -ne '127.0.0.1') { throw 'Local diagnostic must use loopback HTTP.' }
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.UseCookies = $false
    $handler.AllowAutoRedirect = $false
    $client = New-Object Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(15)
    $request = New-Object Net.Http.HttpRequestMessage((New-Object Net.Http.HttpMethod($Method)),$Url)
    try {
        if ($Origin) { $request.Headers.TryAddWithoutValidation('Origin',$Origin) | Out-Null }
        if ($Cookie) { $request.Headers.TryAddWithoutValidation('Cookie',$Cookie) | Out-Null }
        if ($Body) { $request.Content = New-Object Net.Http.StringContent($Body,[Text.Encoding]::UTF8,'application/json') }
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $cookies = @()
            if ($response.Headers.Contains('Set-Cookie')) { $cookies = @($response.Headers.GetValues('Set-Cookie')) }
            return [pscustomobject]@{Status=[int]$response.StatusCode;Content=$content;Cookies=$cookies}
        } finally { $response.Dispose() }
    } finally { $request.Dispose(); $client.Dispose(); $handler.Dispose() }
}
