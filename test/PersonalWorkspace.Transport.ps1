$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Tool-PersonalWorkspace.ps1')
Add-Type -AssemblyName System.Net.Http
$handler = New-Object Net.Http.HttpClientHandler
$handler.UseProxy = $false
$client = New-Object Net.Http.HttpClient($handler)
$client.Timeout = [TimeSpan]::FromSeconds(5)
$script:checks = 0
function Assert-Check([bool]$Value, [string]$Name) {
    if (-not $Value) { throw ('FAIL: ' + $Name) }
    $script:checks++
}
function Request([string]$Path, [string]$Method='GET', [string]$Auth=$script:token,
                 [string]$Origin='', [string]$HostHeader='', [string]$FetchSite='') {
    $msg = New-Object Net.Http.HttpRequestMessage((New-Object Net.Http.HttpMethod($Method)), ($bridge.Origin + $Path))
    try {
        if ($Auth) { [void]$msg.Headers.TryAddWithoutValidation('X-VietLicenSure-Session', $Auth) }
        if ($Origin) { [void]$msg.Headers.TryAddWithoutValidation('Origin', $Origin) }
        if ($HostHeader) { $msg.Headers.Host = $HostHeader }
        if ($FetchSite) { [void]$msg.Headers.TryAddWithoutValidation('Sec-Fetch-Site', $FetchSite) }
        $reply = $client.SendAsync($msg).GetAwaiter().GetResult()
        try { return @{ Code=[int]$reply.StatusCode; Body=$reply.Content.ReadAsStringAsync().GetAwaiter().GetResult(); Csp=[string]($reply.Headers.GetValues('Content-Security-Policy')) } }
        finally { $reply.Dispose() }
    } finally { $msg.Dispose() }
}
$bridge = $null
try {
    $bridge = Start-ToolPersonalWorkspace -Page '<!doctype html><title>Test</title>' -JavaScript '"use strict";'
    $script:token = [uri]::UnescapeDataString(([uri]$bridge.LaunchUri).Fragment.Substring(1))
    Assert-Check ($token.Length -ge 40) 'session entropy'
    Assert-Check ($bridge.Listener -is [Net.Sockets.TcpListener]) 'standard-user transport has no HTTP.sys URL ACL dependency'
    Assert-Check (([Net.IPEndPoint]$bridge.Listener.LocalEndpoint).Address.Equals([Net.IPAddress]::Loopback)) 'listener bound only to IPv4 loopback'
    Assert-Check ((Request '/' -Auth '').Code -eq 200) 'public static shell'
    Assert-Check ((Request '/api/state' -Auth '').Code -eq 401) 'unauthenticated state rejected'
    Assert-Check ((Request '/api/state' -Auth 'wrong').Code -eq 401) 'wrong token rejected'
    Assert-Check ((Request '/api/state' -Origin 'https://attacker.invalid').Code -eq 403) 'cross origin rejected'
    Assert-Check ((Request '/api/state' -FetchSite 'cross-site').Code -eq 403) 'cross site rejected'
    # HTTP.sys may reject a hostile Host before the application sees it.
    Assert-Check ((Request '/api/state' -HostHeader 'attacker.invalid').Code -ne 200) 'host rebinding rejected'
    Assert-Check ((Request '/api/scan' -Method POST -Origin $bridge.Origin).Code -eq 503) 'startup gate'
    $snapshot = @{ status='partial'; hasReport=$true; history=@(@{mode='Hardware'; status='partial'}) }
    Set-ToolPersonalWorkspaceSnapshot -Bridge $bridge -Snapshot $snapshot -Ready $true -Busy $false
    $reply = Request '/api/state'
    Assert-Check ($reply.Code -eq 200 -and ($reply.Body | ConvertFrom-Json).status -eq 'partial') 'shared snapshot preserved'
    Assert-Check ($reply.Csp -match "frame-ancestors 'none'") 'CSP applied'
    Assert-Check ((Request '/api/scan' -Method POST).Code -eq 403) 'mutation requires origin'
    Assert-Check ((Request '/api/scan' -Method POST -Origin 'null').Code -eq 403) 'null origin rejected'
    Assert-Check ((Request '/api/scan?path=C:/secret' -Method POST -Origin $bridge.Origin).Code -eq 400) 'query input rejected'
    $bodyRequest = New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Post, ($bridge.Origin + '/api/scan'))
    try {
        [void]$bodyRequest.Headers.TryAddWithoutValidation('X-VietLicenSure-Session', $script:token)
        [void]$bodyRequest.Headers.TryAddWithoutValidation('Origin', $bridge.Origin)
        $bodyRequest.Content = New-Object Net.Http.StringContent('unexpected')
        $bodyReply = $client.SendAsync($bodyRequest).GetAwaiter().GetResult()
        try { Assert-Check ([int]$bodyReply.StatusCode -eq 400) 'request body rejected' }
        finally { $bodyReply.Dispose() }
    } finally { $bodyRequest.Dispose() }
    Assert-Check ((Request '/api/execute' -Method POST -Origin $bridge.Origin).Code -eq 403) 'unknown action rejected'
    Assert-Check ((Request '/api/scan' -Method POST -Origin $bridge.Origin).Code -eq 202) 'scan queued'
    Assert-Check ((Request '/api/scan' -Method POST -Origin $bridge.Origin).Code -eq 409) 'duplicate queued rejected'
    Assert-Check ((Receive-ToolPersonalWorkspaceAction $bridge) -eq 'scan') 'desktop receives request'
    Assert-Check ((Request '/api/scan' -Method POST -Origin $bridge.Origin).Code -eq 409) 'active task rejected'
    Assert-Check ($null -eq (Receive-ToolPersonalWorkspaceAction $bridge)) 'one dispatch only'
    foreach ($status in @('no-result','error','cancelled','completed')) {
        Set-ToolPersonalWorkspaceSnapshot $bridge @{status=$status;hasReport=$false} -Ready $true -Busy $false
        Assert-Check (((Request '/api/state').Body | ConvertFrom-Json).status -eq $status) ('preserve ' + $status)
    }
    foreach ($action in @('overview','results')) {
        Assert-Check ((Request ('/api/'+$action) -Method POST -Origin $bridge.Origin).Code -eq 202) ('queue '+$action)
        Assert-Check ((Receive-ToolPersonalWorkspaceAction $bridge) -eq $action) ('receive '+$action)
        Set-ToolPersonalWorkspaceSnapshot $bridge @{status='idle'} -Ready $true -Busy $false
    }
    Stop-ToolPersonalWorkspace $bridge
    Assert-Check (-not $bridge.Listener.Server.IsBound -and -not $bridge.LaunchUri) 'explicit lifecycle cleanup'
    $bridge = $null
    [pscustomobject]@{ Passed=$true; Checks=$script:checks; Scope='Transport only; desktop engine and browser not integrated' } | ConvertTo-Json
} finally {
    if ($bridge -and -not $bridge.State.Closed) { Stop-ToolPersonalWorkspace $bridge }
    $client.Dispose(); $handler.Dispose()
}
