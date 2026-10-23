# Authenticated, session-only loopback transport. No arbitrary commands or paths.
# The desktop owns all execution, authorization, result projection and lifetime.
function Start-ToolPersonalWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Page,
          [Parameter(Mandatory=$true)][string]$JavaScript,
          [string]$StyleSheet = '')

    # TcpListener avoids machine-wide HTTP.sys URL ACL changes and therefore
    # works for a standard user.  The server below accepts only a tiny,
    # bodyless, fixed-route HTTP subset on the IPv4 loopback interface.
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Server.ExclusiveAddressUse = $true
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    $secret = New-Object byte[] 32
    $random.GetBytes($secret)
    $token = [Convert]::ToBase64String($secret)
    $random.Dispose()
    try { $listener.Start(8) } catch { $listener.Stop(); throw 'PersonalWorkspaceLoopbackUnavailable' }
    $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $origin = 'http://127.0.0.1:' + $port
    $state = [hashtable]::Synchronized(@{
        Snapshot = '{"status":"starting","hasReport":false}'
        Pending = ''; Busy = $false; Ready = $false; Closed = $false
    })
    $worker = [PowerShell]::Create()
    $server = {
        param($listener, $state, $token, $origin, $page, $javascript, $stylesheet)
        while ($state.Closed -eq $false) {
            $client = $null
            try { $client = $listener.AcceptTcpClient() } catch { break }
            $code = 404; $body = '{"error":"not_found"}'; $type = 'application/json; charset=utf-8'
            try {
                $client.ReceiveTimeout = 3000
                $client.SendTimeout = 3000
                $stream = $client.GetStream()
                $headerBytes = New-Object Collections.Generic.List[byte]
                $tail = ''
                while ($headerBytes.Count -lt 16384 -and $tail -ne "`r`n`r`n") {
                    $value = $stream.ReadByte()
                    if ($value -lt 0) { break }
                    [void]$headerBytes.Add([byte]$value)
                    $tail = if ($headerBytes.Count -ge 4) {
                        [Text.Encoding]::ASCII.GetString($headerBytes.GetRange($headerBytes.Count - 4, 4).ToArray())
                    } else { '' }
                }
                if ($tail -ne "`r`n`r`n") { throw 'PersonalWorkspaceHeaderInvalid' }
                $headerText = [Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
                $lines = @($headerText.Substring(0, $headerText.Length - 4) -split "`r`n")
                if ($lines.Count -lt 2 -or $lines[0] -notmatch '^(GET|POST) ([^ ]+) HTTP/1\.[01]$') {
                    throw 'PersonalWorkspaceRequestLineInvalid'
                }
                $method = [string]$Matches[1]
                $target = [string]$Matches[2]
                $headers = New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
                foreach ($line in @($lines | Select-Object -Skip 1)) {
                    $separator = $line.IndexOf(':')
                    if ($separator -le 0) { throw 'PersonalWorkspaceHeaderInvalid' }
                    $name = $line.Substring(0, $separator).Trim()
                    $value = $line.Substring($separator + 1).Trim()
                    if ($name -notmatch '^[A-Za-z0-9-]{1,64}$' -or $headers.ContainsKey($name)) {
                        throw 'PersonalWorkspaceHeaderInvalid'
                    }
                    $headers.Add($name, $value)
                }
                $expectedHost = ([uri]$origin).Authority
                $remoteOk = [Net.IPAddress]::IsLoopback(([Net.IPEndPoint]$client.Client.RemoteEndPoint).Address)
                $hostOk = ($headers.ContainsKey('Host') -and $headers['Host'] -ceq $expectedHost)
                $originHeader = if ($headers.ContainsKey('Origin')) { [string]$headers['Origin'] } else { '' }
                $originOk = ($originHeader -ceq $origin)
                $fetchSite = if ($headers.ContainsKey('Sec-Fetch-Site')) { [string]$headers['Sec-Fetch-Site'] } else { '' }
                $crossSite = $fetchSite -in @('cross-site','same-site')
                $path = $target
                $hasBody = (($headers.ContainsKey('Content-Length') -and $headers['Content-Length'] -ne '0') -or
                    $headers.ContainsKey('Transfer-Encoding'))
                if (-not $remoteOk -or -not $hostOk -or $crossSite -or
                    ($originHeader -and -not $originOk)) {
                    $code = 403; $body = '{"error":"origin"}'
                } elseif ($hasBody -or $target.Contains('?')) {
                    $code = 400; $body = '{"error":"unexpected_input"}'
                } elseif ($method -eq 'GET' -and $path -in @('/','/app.js','/app.css')) {
                    $code = 200
                    if ($path -eq '/') { $body = $page; $type = 'text/html; charset=utf-8' }
                    elseif ($path -eq '/app.js') { $body = $javascript; $type = 'text/javascript; charset=utf-8' }
                    else { $body = $stylesheet; $type = 'text/css; charset=utf-8' }
                } elseif (-not $headers.ContainsKey('X-VietLicenSure-Session') -or
                    $headers['X-VietLicenSure-Session'] -cne $token) {
                    $code = 401; $body = '{"error":"session"}'
                } elseif ($method -eq 'GET' -and $path -eq '/api/state') {
                    $code = 200; $body = [string]$state.Snapshot
                } elseif ($method -eq 'POST' -and $originOk -and
                    $path -in @('/api/scan-all','/api/scan-hardware','/api/scan-windows','/api/scan-office','/api/scan-software','/api/reports','/api/back','/api/role','/api/network','/api/language','/api/theme','/api/about','/api/assistant')) {
                    # One bounded mailbox, locked across listener and UI threads.
                    # These are requests to the existing desktop workflow, not
                    # authorization to bypass its privacy, integrity or UAC gates.
                    [Threading.Monitor]::Enter($state.SyncRoot)
                    try {
                        $safeUiAction = $path -in @('/api/back','/api/role','/api/network','/api/language','/api/theme','/api/about','/api/assistant')
                        if (-not $state.Ready) { $code = 503; $body = '{"error":"not_ready"}' }
                        elseif ($state.Pending -or ($state.Busy -and -not $safeUiAction)) { $code = 409; $body = '{"error":"busy"}' }
                        else {
                            $state.Pending = $path.Substring(5)
                            $code = 202; $body = '{"status":"queued"}'
                        }
                    } finally { [Threading.Monitor]::Exit($state.SyncRoot) }
                } elseif ($method -ne 'GET') {
                    $code = 403; $body = '{"error":"action"}'
                }
                $bytes = [Text.Encoding]::UTF8.GetBytes($body)
                $reason = switch ($code) { 200 {'OK'} 202 {'Accepted'} 400 {'Bad Request'} 401 {'Unauthorized'} 403 {'Forbidden'} 404 {'Not Found'} 409 {'Conflict'} 503 {'Service Unavailable'} default {'Error'} }
                $responseHead = "HTTP/1.1 $code $reason`r`nContent-Type: $type`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nReferrer-Policy: no-referrer`r`nX-Frame-Options: DENY`r`nContent-Security-Policy: default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'`r`nConnection: close`r`n`r`n"
                $headBytes = [Text.Encoding]::ASCII.GetBytes($responseHead)
                $stream.Write($headBytes, 0, $headBytes.Length)
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            } catch {
                # A disconnected tab is not a cancellation request.
            } finally { if ($client) { $client.Close() } }
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
        $safeUiAction = [string]$Bridge.State.Pending -in @('back','role','network','language','theme','about','assistant')
        if ($Bridge.State.Pending -and $Bridge.State.Ready -and (-not $Bridge.State.Busy -or $safeUiAction)) {
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
    $Bridge.Listener.Stop()
    try { [void]$Bridge.Worker.EndInvoke($Bridge.Handle) }
    finally { $Bridge.Worker.Dispose(); $Bridge.LaunchUri = '' }
}
