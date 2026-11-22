#Requires -Version 7.0
<#
.SYNOPSIS
  Read-only SwitchBot API v1.1 inventory and status exporter.
.DESCRIPTION
  Loads strict KEY=VALUE configuration, retrieves devices/status/scenes and exports XML/Text/CSV.
  No third-party PowerShell modules are required.
#>
[CmdletBinding()]
param(
    [ValidateSet('Devices','Status','Scenes')][string[]]$Include,
    [string[]]$DeviceId,
    [ValidateSet('XML','Text','CSV')][string]$Format,
    [ValidateSet('Structured','Raw')][string]$XmlMode,
    [string]$OutputPath,
    [string]$ConfigPath,
    [string]$Token,
    [string]$Secret,
    [string]$TokenEnv,
    [string]$SecretEnv,
    [switch]$Parallel,
    [ValidateRange(1,64)][int]$ThrottleLimit,
    [ValidateRange(1,600)][int]$TimeoutSec,
    [switch]$UseCache,
    [ValidateRange(0,86400)][int]$CacheTTL,
    [string]$LogPath,
    [ValidateSet('Debug','Info','Warning','Error')][string]$LogLevel,
    [switch]$MaskDeviceId,
    [switch]$SaveRawJson,
    [switch]$ShowConfig
)
$ErrorActionPreference = 'Stop'
$script:Version = '1.0.0'
$script:Config = [ordered]@{
    TOKEN=''; SECRET=''; TOKEN_ENV=''; SECRET_ENV=''; INCLUDE='Devices,Status,Scenes'; DEVICE_ID='';
    OUTPUT_FORMAT='XML'; XML_MODE='Structured'; OUTPUT_PATH=''; PARALLEL='false';
    THROTTLE_LIMIT='4'; TIMEOUT_SEC='15'; USE_CACHE='false'; CACHE_TTL='300';
    LOG_PATH=''; LOG_LEVEL='Info'; MASK_DEVICE_ID='false'; SAVE_RAW_JSON='false'
}
$script:Sources = @{}; foreach ($key in $script:Config.Keys) { $script:Sources[$key] = 'Default' }
$script:Errors = [System.Collections.Generic.List[string]]::new()
$script:RawResponses = [ordered]@{}
$script:Started = [DateTimeOffset]::Now
$script:HadAuthError = $false

function Write-Diagnostic([string]$Level,[string]$Message) {
    $ranks = @{Debug=0;Info=1;Warning=2;Error=3}
    if ($ranks[$Level] -lt $ranks[$script:Config.LOG_LEVEL]) { return }
    $line = '[{0}] [{1}] {2}' -f ([DateTimeOffset]::Now.ToString('o')), $Level, $Message
    [Console]::Error.WriteLine($line)
    if ($script:Config.LOG_PATH) {
        $path = [IO.Path]::GetFullPath($script:Config.LOG_PATH)
        $dir = [IO.Path]::GetDirectoryName($path)
        if ($dir) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
        [IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
}
function Read-SettingsFile([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { throw "Config file not found: $Path" }
    $lines = [IO.File]::ReadAllLines($Path, [Text.UTF8Encoding]::new($false))
    for ($i=0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i].Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([A-Za-z][A-Za-z0-9_]*)\s*=(.*)$') { throw "Invalid configuration syntax: ${Path}:$($i+1)" }
        $key = $Matches[1].ToUpperInvariant(); $value = $Matches[2].Trim()
        if (-not $script:Config.Contains($key)) { throw "Unknown configuration key '$key': ${Path}:$($i+1)" }
        Assert-Setting $key $value "${Path}:$($i+1)"
        $script:Config[$key] = $value; $script:Sources[$key] = "${Path}:$($i+1)"
    }
}
function Assert-Setting([string]$Key,[string]$Value,[string]$Source) {
    switch ($Key) {
        {$_ -in 'PARALLEL','USE_CACHE','MASK_DEVICE_ID','SAVE_RAW_JSON'} {
            if ($Value -notin 'true','false') { throw "Invalid boolean '$Key' at $Source" }; break
        }
        'THROTTLE_LIMIT' { if ($Value -notmatch '^\d+$' -or [long]$Value -lt 1 -or [long]$Value -gt 64) { throw "Invalid THROTTLE_LIMIT at $Source" }; break }
        'TIMEOUT_SEC' { if ($Value -notmatch '^\d+$' -or [long]$Value -lt 1 -or [long]$Value -gt 600) { throw "Invalid TIMEOUT_SEC at $Source" }; break }
        'CACHE_TTL' { if ($Value -notmatch '^\d+$' -or [long]$Value -gt 86400) { throw "Invalid CACHE_TTL at $Source" }; break }
        'OUTPUT_FORMAT' { if ($Value -notin 'XML','Text','CSV') { throw "Invalid OUTPUT_FORMAT at $Source" }; break }
        'XML_MODE' { if ($Value -notin 'Structured','Raw') { throw "Invalid XML_MODE at $Source" }; break }
        'LOG_LEVEL' { if ($Value -notin 'Debug','Info','Warning','Error') { throw "Invalid LOG_LEVEL at $Source" }; break }
        'INCLUDE' { if (@($Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -notin 'Devices','Status','Scenes' }).Count) { throw "Invalid INCLUDE at $Source" }; break }
    }
}
function Set-Option([string]$Key,[object]$Value) {
    if ($PSBoundParameters.ContainsKey('Value') -and $null -ne $Value) {
        $script:Config[$Key] = [string]$Value; $script:Sources[$Key] = 'CommandLine'
    }
}
function Initialize-Settings {
    $paths = @(
        (Join-Path $PSScriptRoot '.sbview.conf'),
        (Join-Path (Get-Location).Path '.sbview.conf'),
        (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.sbview.conf')
    )
    if ($ConfigPath) { $paths += $ConfigPath }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $paths) {
        $full = [IO.Path]::GetFullPath($path)
        if (-not $seen.Add($full)) { continue }
        if ([IO.File]::Exists($full)) { Read-SettingsFile $full }
        elseif ($ConfigPath -and $full -eq [IO.Path]::GetFullPath($ConfigPath)) { throw "Config file not found: $full" }
    }
    $map = @{
        Include='INCLUDE'; DeviceId='DEVICE_ID'; Format='OUTPUT_FORMAT'; XmlMode='XML_MODE';
        OutputPath='OUTPUT_PATH'; Token='TOKEN'; Secret='SECRET'; TokenEnv='TOKEN_ENV';
        SecretEnv='SECRET_ENV'; Parallel='PARALLEL'; ThrottleLimit='THROTTLE_LIMIT';
        TimeoutSec='TIMEOUT_SEC'; UseCache='USE_CACHE'; CacheTTL='CACHE_TTL';
        LogPath='LOG_PATH'; LogLevel='LOG_LEVEL'; MaskDeviceId='MASK_DEVICE_ID'; SaveRawJson='SAVE_RAW_JSON'
    }
    foreach ($parameter in $map.Keys) {
        if ($script:CLIArgs.ContainsKey($parameter)) {
            $value = $script:CLIArgs[$parameter]
            if ($value -is [switch]) { $value = if ($value.IsPresent) { 'true' } else { 'false' } }
            elseif ($value -is [array]) { $value = $value -join ',' }
            $script:Config[$map[$parameter]] = [string]$value
            $script:Sources[$map[$parameter]] = 'CommandLine'
        }
    }
    foreach ($key in $script:Config.Keys) { Assert-Setting $key $script:Config[$key] $script:Sources[$key] }
}
function Resolve-Credentials {
    if (-not $script:Config.TOKEN -and $script:Config.TOKEN_ENV) { $script:Config.TOKEN = [Environment]::GetEnvironmentVariable($script:Config.TOKEN_ENV) }
    if (-not $script:Config.SECRET -and $script:Config.SECRET_ENV) { $script:Config.SECRET = [Environment]::GetEnvironmentVariable($script:Config.SECRET_ENV) }
    if (-not $script:Config.TOKEN -or -not $script:Config.SECRET) { throw 'Missing SwitchBot Token or Secret' }
}
function Show-ResolvedConfig {
    '{0,-20} {1,-24} {2}' -f 'Setting','Value','Source'
    '-' * 84
    foreach ($key in $script:Config.Keys) {
        $value = if ($key -in 'TOKEN','SECRET') { if ($script:Config[$key]) { '[Configured]' } else { '[Not configured]' } }
            elseif ($key -in 'TOKEN_ENV','SECRET_ENV') { if ($script:Config[$key]) { '[Configured environment variable name]' } else { '[Not configured]' } }
            else { [string]$script:Config[$key] }
        '{0,-20} {1,-24} {2}' -f $key,$value,$script:Sources[$key]
    }
}
function Get-CacheFolder {
    if ($IsWindows) { return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'sbview/Cache') }
    return (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache/sbview')
}
function Get-CacheFile([string]$Endpoint) {
    $sha = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($script:Config.TOKEN + ':' + $Endpoint))
    return (Join-Path (Get-CacheFolder) ([Convert]::ToHexString($sha).ToLowerInvariant() + '.json'))
}
function Invoke-SwitchBotGet([string]$Endpoint) {
    $cacheEnabled = $script:Config.USE_CACHE -eq 'true'
    if ($cacheEnabled) {
        $cacheFile = Get-CacheFile $Endpoint
        if ([int]$script:Config.CACHE_TTL -gt 0 -and [IO.File]::Exists($cacheFile)) {
            $age = [DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($cacheFile)
            if ($age.TotalSeconds -le [int]$script:Config.CACHE_TTL) {
                Write-Diagnostic Debug "Cache hit: $Endpoint"
                return ([IO.File]::ReadAllText($cacheFile) | ConvertFrom-Json -AsHashtable)
            }
        }
    }
    $url = 'https://api.switch-bot.com' + $Endpoint
    for ($attempt=0; $attempt -le 3; $attempt++) {
        $nonce = [guid]::NewGuid().ToString('N')
        $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
        $bytes = [Text.Encoding]::UTF8.GetBytes($script:Config.TOKEN + $timestamp + $nonce)
        $key = [Text.Encoding]::UTF8.GetBytes($script:Config.SECRET)
        $sign = [Convert]::ToBase64String([Security.Cryptography.HMACSHA256]::HashData($key,$bytes))
        $headers = @{ Authorization=$script:Config.TOKEN; sign=$sign; t=$timestamp; nonce=$nonce }
        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -TimeoutSec ([int]$script:Config.TIMEOUT_SEC) -ErrorAction Stop
            if ($response -isnot [System.Collections.IDictionary]) { $response = $response | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable }
            $status = [string]$response.statusCode
            if ($status -ne '100') {
                if ($status -in '190','401','403') { $script:HadAuthError = $true; throw "AUTH: API status $status ($($response.message))" }
                if ($status -in '429','500','502','503','504' -and $attempt -lt 3) { Start-Sleep -Seconds ([math]::Pow(2,$attempt)); continue }
                throw "API status $status ($($response.message))"
            }
            if ($cacheEnabled) {
                [IO.Directory]::CreateDirectory((Get-CacheFolder)) | Out-Null
                [IO.File]::WriteAllText($cacheFile, ($response | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
            }
            return $response
        } catch {
            if ($_.Exception.Message.StartsWith('AUTH:')) { throw }
            $http = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $http = [int]$_.Exception.Response.StatusCode }
            if ($http -in 401,403) { $script:HadAuthError = $true; throw "AUTH: HTTP $http" }
            if ($attempt -ge 3 -or ($http -and $http -notin 429,500,502,503,504)) { throw }
            Write-Diagnostic Warning "Request retry $($attempt+1)/3 for $Endpoint (HTTP $http)"
            Start-Sleep -Seconds ([math]::Pow(2,$attempt))
        }
    }
}
function Mask-Id([string]$Id) {
    if ($script:Config.MASK_DEVICE_ID -ne 'true') { return $Id }
    if ($Id.Length -le 4) { return ('*' * $Id.Length) }
    return ('*' * ($Id.Length - 4)) + $Id.Substring($Id.Length-4)
}
function Protect-Data($Data) {
    if ($null -eq $Data) { return $null }
    if ($Data -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($k in $Data.Keys) {
            $v = $Data[$k]
            $out[$k] = if ($k -eq 'deviceId' -and $null -ne $v) { Mask-Id ([string]$v) } else { Protect-Data $v }
        }
        return $out
    }
    if ($Data -is [array]) { return ,@($Data | ForEach-Object { Protect-Data $_ }) }
    return $Data
}
function Add-XmlNode([xml]$Document,[System.Xml.XmlNode]$Parent,[string]$Name,$Value) {
    $safe = $Name -match '^[A-Za-z_][A-Za-z0-9_.-]*$' -and -not $Name.StartsWith('xml',[StringComparison]::OrdinalIgnoreCase)
    $element = $Document.CreateElement($(if ($safe) { $Name } else { 'Property' }))
    if (-not $safe) { $element.SetAttribute('originalName',$Name) }
    [void]$Parent.AppendChild($element)
    if ($null -eq $Value) { $element.SetAttribute('isNull','true'); return }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($k in $Value.Keys) { Add-XmlNode $Document $element ([string]$k) $Value[$k] }
    } elseif ($Value -is [array]) {
        foreach ($item in $Value) { Add-XmlNode $Document $element 'Item' $item }
    } else { $element.InnerText = [string]$Value }
}
function Convert-ToXml($Data) {
    $doc = [xml]'<?xml version="1.0" encoding="utf-8"?><SwitchBot schemaVersion="1.0" />'
    foreach ($key in $Data.Keys) { Add-XmlNode $doc $doc.DocumentElement $key $Data[$key] }
    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Indent = $true; $settings.IndentChars = '  '; $settings.NewLineChars = [Environment]::NewLine
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $writer = [IO.StringWriter]::new()
    $xmlWriter = [Xml.XmlWriter]::Create($writer,$settings)
    $doc.Save($xmlWriter); $xmlWriter.Dispose()
    return ($writer.ToString() -replace '^<\?xml version="1.0" encoding="utf-16"\?>','<?xml version="1.0" encoding="utf-8"?>')
}
function Add-TextLines([Collections.Generic.List[string]]$Lines,[string]$Key,$Value,[int]$Depth) {
    $prefix = '  ' * $Depth
    if ($null -eq $Value) { return }
    if ($Value -is [System.Collections.IDictionary]) {
        $Lines.Add("${prefix}${Key}:")
        foreach ($k in $Value.Keys) { Add-TextLines $Lines ([string]$k) $Value[$k] ($Depth+1) }
    } elseif ($Value -is [array]) {
        $Lines.Add("${prefix}${Key}:")
        foreach ($item in $Value) { Add-TextLines $Lines '-' $item ($Depth+1) }
    } else { $Lines.Add("${prefix}${Key}: $Value") }
}
function Convert-ToText($Data) {
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($key in $Data.Keys) { Add-TextLines $lines $key $Data[$key] 0 }
    return ($lines -join [Environment]::NewLine)
}
function Flatten-Row($Value,[string]$Prefix='') {
    $row = [ordered]@{}
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $name = if ($Prefix) { "$Prefix.$key" } else { [string]$key }
            if ($Value[$key] -is [System.Collections.IDictionary] -or $Value[$key] -is [array]) { $row[$name] = ConvertTo-Json -InputObject $Value[$key] -Depth 100 -Compress }
            else { $row[$name] = $Value[$key] }
        }
    } else { $row['Value'] = $Value }
    return $row
}
function Convert-ToCsvText($Rows) {
    $rowsArray = @($Rows)
    if (-not $rowsArray.Count) { return '' }
    $names = [Collections.Generic.List[string]]::new()
    foreach ($row in $rowsArray) { foreach ($name in $row.Keys) { if (-not $names.Contains([string]$name)) { $names.Add([string]$name) } } }
    $objects = foreach ($row in $rowsArray) {
        $obj = [ordered]@{}; foreach ($name in $names) { $obj[$name] = if ($row.Contains($name)) { $row[$name] } else { $null } }
        [pscustomobject]$obj
    }
    return (($objects | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine)
}
function Save-Utf8([string]$Path,[string]$Content) {
    $full = [IO.Path]::GetFullPath($Path)
    $dir = [IO.Path]::GetDirectoryName($full)
    if ($dir) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
    [IO.File]::WriteAllText($full,$Content,[Text.UTF8Encoding]::new($false))
}
function Sort-Records($Items,[string]$NameField,[string]$IdField) {
    return @($Items | Sort-Object -Stable -Property @{Expression={ [string]$_[$NameField] }},@{Expression={ [string]$_[$IdField] }})
}
function Run-Exporter {
    $categories = @($script:Config.INCLUDE -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $ids = @($script:Config.DEVICE_ID -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $wantDevices = 'Devices' -in $categories; $wantStatus = 'Status' -in $categories; $wantScenes = 'Scenes' -in $categories
    if ($script:Config.PARALLEL -eq 'true') { Write-Diagnostic Warning 'Parallel execution is not yet implemented; using sequential requests' }
    $devices = @(); $statuses = @(); $scenes = @(); $raw = [ordered]@{}
    $successes = 0; $failures = 0
    if ($wantDevices -or $wantStatus -or $ids.Count) {
        try {
            $response = Invoke-SwitchBotGet '/v1.1/devices'; $successes++
            $raw['devices'] = $response
            $body = $response.body
            $devices = @(@($body.deviceList) + @($body.infraredRemoteList) | Where-Object { $null -ne $_ })
            $devices = Sort-Records $devices 'deviceName' 'deviceId'
        } catch {
            if ($script:HadAuthError) { throw }
            $script:Errors.Add("Devices: $($_.Exception.Message)"); $failures++
        }
    }
    if ($ids.Count -and $successes -gt 0) {
        $known = @($devices | ForEach-Object { [string]$_.deviceId })
        foreach ($id in $ids) { if ($id -cnotin $known) { $script:Errors.Add("Unknown device ID: $(Mask-Id $id)"); $failures++ } }
        $devices = @($devices | Where-Object { $_.deviceId -cin $ids })
        if (-not $devices.Count) { throw 'NO_TARGET: None of the specified device IDs exist' }
    }
    if ($wantStatus) {
        foreach ($device in $devices) {
            $id = [string]$device.deviceId
            try {
                $response = Invoke-SwitchBotGet ("/v1.1/devices/$([uri]::EscapeDataString($id))/status")
                $raw["status_$id"] = $response; $successes++
                $record = [ordered]@{deviceId=$id;deviceName=$device.deviceName}
                if ($response.body -is [System.Collections.IDictionary]) { foreach ($key in $response.body.Keys) { $record[$key] = $response.body[$key] } }
                $statuses += $record
            } catch {
                if ($script:HadAuthError) { throw }
                $script:Errors.Add("Status $(Mask-Id $id): $($_.Exception.Message)"); $failures++
            }
        }
    }
    if ($wantScenes) {
        try {
            $response = Invoke-SwitchBotGet '/v1.1/scenes'; $raw['scenes'] = $response; $successes++
            $scenes = Sort-Records @($response.body | Where-Object { $null -ne $_ }) 'sceneName' 'sceneId'
        } catch {
            if ($script:HadAuthError) { throw }
            $script:Errors.Add("Scenes: $($_.Exception.Message)"); $failures++
        }
    }
    $metadata = [ordered]@{
        Tool='sbview.ps1'; ToolVersion=$script:Version; SchemaVersion='1.0';
        Started=$script:Started.ToString('o'); Finished=[DateTimeOffset]::Now.ToString('o');
        Include=$categories; DeviceIds=@($ids | ForEach-Object { Mask-Id $_ });
        SuccessfulRequests=$successes; FailedRequests=$failures;
        Result=$(if ($failures -eq 0) { 'Success' } elseif ($successes -gt 0) { 'PartialFailure' } else { 'Failure' });
        Errors=@($script:Errors)
    }
    $data = [ordered]@{Metadata=$metadata}
    if ($wantDevices) { $data['Devices'] = @($devices | ForEach-Object { Protect-Data $_ }) }
    if ($wantStatus) { $data['Status'] = @($statuses | ForEach-Object { Protect-Data $_ }) }
    if ($wantScenes) { $data['Scenes'] = @($scenes | ForEach-Object { Protect-Data $_ }) }
    $path = $script:Config.OUTPUT_PATH
    if ($script:Config.SAVE_RAW_JSON -eq 'true') {
        $base = if ($path) { Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))) ([IO.Path]::GetFileNameWithoutExtension($path) + '_raw') } else { Join-Path (Get-Location).Path 'sbview_raw' }
        foreach ($key in $raw.Keys) {
            $filename = ($key -replace '[^A-Za-z0-9_-]','_') + '.json'
            Save-Utf8 (Join-Path $base $filename) (ConvertTo-Json -InputObject $raw[$key] -Depth 100)
        }
    }
    switch ($script:Config.OUTPUT_FORMAT.ToUpperInvariant()) {
        'XML' {
            $export = if ($script:Config.XML_MODE -eq 'Raw') { [ordered]@{Metadata=$metadata;Responses=(Protect-Data $raw)} } else { $data }
            $content = Convert-ToXml $export
            if ($path) { Save-Utf8 $path $content } else { Write-Output $content }
        }
        'TEXT' {
            $content = Convert-ToText $data
            if ($path) { Save-Utf8 $path $content } else { Write-Output $content }
        }
        'CSV' {
            $csvSets = [ordered]@{}
            if ($wantDevices) { $csvSets['Devices'] = @($data.Devices | ForEach-Object { Flatten-Row $_ }) }
            if ($wantStatus) { $csvSets['Status'] = @($data.Status | ForEach-Object { Flatten-Row $_ }) }
            if ($wantScenes) { $csvSets['Scenes'] = @($data.Scenes | ForEach-Object { Flatten-Row $_ }) }
            $csvSets['Metadata'] = @($metadata.GetEnumerator() | ForEach-Object { [ordered]@{Key=$_.Key;Value=$(if ($_.Value -is [array]) { ConvertTo-Json -InputObject $_.Value -Compress -Depth 100 } else { $_.Value })} })
            foreach ($category in $csvSets.Keys) {
                $content = Convert-ToCsvText $csvSets[$category]
                if ($path) {
                    $dir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))
                    $prefix = [IO.Path]::GetFileNameWithoutExtension($path)
                    Save-Utf8 (Join-Path $dir "${prefix}_${category}.csv") $content
                } else { Write-Output "# $category"; Write-Output $content }
            }
        }
    }
    foreach ($errorMessage in $script:Errors) { Write-Diagnostic Warning $errorMessage }
    if ($successes -eq 0 -and $failures -gt 0) { return 4 }
    if ($failures -gt 0) { return 1 }
    return 0
}
$script:CLIArgs = @{}; foreach ($name in $PSBoundParameters.Keys) { $script:CLIArgs[$name] = $PSBoundParameters[$name] }
try {
    Initialize-Settings
    if ($ShowConfig) { Show-ResolvedConfig; exit 0 }
    Resolve-Credentials
    Write-Diagnostic Info 'sbview started'
    $exitCode = Run-Exporter
    Write-Diagnostic Info "sbview finished (exit $exitCode)"
    exit $exitCode
} catch {
    $message = $_.Exception.Message
    $exitCode = if ($message.StartsWith('AUTH:')) { 3 } elseif ($message.StartsWith('NO_TARGET:')) { 4 }
        elseif ($message -match 'Missing SwitchBot Token|Config|configuration|Invalid |Unknown configuration') { 2 }
        elseif ($message -match 'Access|path|directory|disk|write|XML|CSV') { 5 }
        else { 4 }
    [Console]::Error.WriteLine("[Error] $message")
    exit $exitCode
}
