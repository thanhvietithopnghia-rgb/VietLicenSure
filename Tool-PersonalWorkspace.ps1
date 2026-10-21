# Authenticated, session-only loopback transport. No arbitrary commands or paths.
# The desktop owns all execution, authorization, result projection and lifetime.
function Start-ToolPersonalWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Page,
          [Parameter(Mandatory=$true)][string]$JavaScript,
          [string]$StyleSheet = '')

    $listener = New-Object Net.HttpListener
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    $secret = New-Object byte[] 32
    $random.GetBytes($secret)
    $token = [Convert]::ToBase64String($secret)
    $random.Dispose()
    # HTTP.sys reservation can fail for an ordinary user. Fail closed; never
    # request elevation, add a wildcard URL ACL, or bind to LAN as a fallback.
    $started = $false
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $port = Get-Random -Minimum 49152 -Maximum 65535
        $origin = 'http://127.0.0.1:' + $port
        $listener.Prefixes.Clear()
        $listener.Prefixes.Add($origin + '/')
        try { $listener.Start(); $started = $true; break } catch {}
    }
    if (-not $started) { $listener.Close(); throw 'PersonalWorkspaceLoopbackUnavailable' }
    $state = [hashtable]::Synchronized(@{
        Snapshot = '{"status":"starting","hasReport":false}'
        Pending = ''; Busy = $false; Ready = $false; Closed = $false
    })
    $worker = [PowerShell]::Create()
    $server = {
        param($listener, $state, $token, $origin, $page, $javascript, $stylesheet)
        while ($listener.IsListening) {
            try { $context = $listener.GetContext() } catch { break }
            $request = $context.Request
            $response = $context.Response
            $code = 404; $body = '{"error":"not_found"}'; $type = 'application/json; charset=utf-8'
            try {
                $response.Headers['Cache-Control'] = 'no-store'
                $response.Headers['X-Content-Type-Options'] = 'nosniff'
                $response.Headers['Referrer-Policy'] = 'no-referrer'
                $response.Headers['X-Frame-Options'] = 'DENY'
                $response.Headers['Content-Security-Policy'] = "default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
                $expectedHost = ([uri]$origin).Authority
                $remoteOk = [Net.IPAddress]::IsLoopback($request.RemoteEndPoint.Address)
                $hostOk = $request.Headers['Host'] -ceq $expectedHost
                $originHeader = [string]$request.Headers['Origin']
                $originOk = ($originHeader -ceq $origin)
                $fetchSite = [string]$request.Headers['Sec-Fetch-Site']
                $crossSite = $fetchSite -in @('cross-site','same-site')
                $path = $request.Url.AbsolutePath
                if (-not $remoteOk -or -not $hostOk -or $crossSite -or
                    ($originHeader -and -not $originOk)) {
                    $code = 403; $body = '{"error":"origin"}'
                } elseif ($request.HasEntityBody -or $request.Url.Query) {
                    $code = 400; $body = '{"error":"unexpected_input"}'
                } elseif ($request.HttpMethod -eq 'GET' -and $path -in @('/','/app.js','/app.css')) {
                    $code = 200
                    if ($path -eq '/') { $body = $page; $type = 'text/html; charset=utf-8' }
                    elseif ($path -eq '/app.js') { $body = $javascript; $type = 'text/javascript; charset=utf-8' }
                    else { $body = $stylesheet; $type = 'text/css; charset=utf-8' }
                } elseif ($request.Headers['X-VietLicenSure-Session'] -cne $token) {
                    $code = 401; $body = '{"error":"session"}'
                } elseif ($request.HttpMethod -eq 'GET' -and $path -eq '/api/state') {
                    $code = 200; $body = [string]$state.Snapshot
                } elseif ($request.HttpMethod -eq 'POST' -and $originOk -and
                    $path -in @('/api/scan','/api/overview','/api/results')) {
                    # One bounded mailbox, locked across listener and UI threads.
                    # These are requests to the existing desktop workflow, not
                    # authorization to bypass its privacy, integrity or UAC gates.
                    [Threading.Monitor]::Enter($state.SyncRoot)
                    try {
                        if (-not $state.Ready) { $code = 503; $body = '{"error":"not_ready"}' }
                        elseif ($state.Pending -or $state.Busy) { $code = 409; $body = '{"error":"busy"}' }
                        else {
                            $state.Pending = $path.Substring(5)
                            $code = 202; $body = '{"status":"queued"}'
                        }
                    } finally { [Threading.Monitor]::Exit($state.SyncRoot) }
                } elseif ($request.HttpMethod -ne 'GET') {
                    $code = 403; $body = '{"error":"action"}'
                }
                $bytes = [Text.Encoding]::UTF8.GetBytes($body)
                $response.StatusCode = $code
                $response.ContentType = $type
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } catch {
                # A disconnected tab is not a cancellation request.
            } finally { $response.Close() }
        }
    }
    try {
        [void]$worker.AddScript($server.ToString()).AddArgument($listener).AddArgument($state).AddArgument($token).AddArgument($origin).AddArgument($Page).AddArgument($JavaScript).AddArgument($StyleSheet)
        $handle = $worker.BeginInvoke()
        return [pscustomobject]@{ Listener=$listener; Worker=$worker; Handle=$handle; State=$state; Origin=$origin; LaunchUri=($origin + '/#' + [uri]::EscapeDataString($token)) }
    } catch { $listener.Close(); $worker.Dispose(); throw }
}

function Set-ToolPersonalWorkspaceSnapshot {
    param([Parameter(Mandatory=$true)]$Bridge,
          [Parameter(Mandatory=$true)]$Snapshot,
          [bool]$Ready, [bool]$Busy)
    # Caller supplies a deliberate safe projection, never raw report contents.
    $json = ConvertTo-Json -InputObject $Snapshot -Depth 8 -Compress
    [Threading.Monitor]::Enter($Bridge.State.SyncRoot)
    try {
        $Bridge.State.Snapshot = $json
        $Bridge.State.Ready = $Ready
        $Bridge.State.Busy = $Busy
    } finally { [Threading.Monitor]::Exit($Bridge.State.SyncRoot) }
}

function Receive-ToolPersonalWorkspaceAction {
    param([Parameter(Mandatory=$true)]$Bridge)
    [Threading.Monitor]::Enter($Bridge.State.SyncRoot)
    try {
        if ($Bridge.State.Pending -and $Bridge.State.Ready -and -not $Bridge.State.Busy) {
            $action = [string]$Bridge.State.Pending
            $Bridge.State.Pending = ''
            $Bridge.State.Busy = $true
            return $action
        }
    } finally { [Threading.Monitor]::Exit($Bridge.State.SyncRoot) }
}

function Stop-ToolPersonalWorkspace {
    param([Parameter(Mandatory=$true)]$Bridge)
    $Bridge.State.Closed = $true
    $Bridge.State.Ready = $false
    $Bridge.Listener.Close()
    try { [void]$Bridge.Worker.EndInvoke($Bridge.Handle) }
    finally { $Bridge.Worker.Dispose(); $Bridge.LaunchUri = '' }
}
