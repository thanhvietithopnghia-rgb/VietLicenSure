$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Tool-PersonalWorkspace.ps1')
. (Join-Path $root 'Dashboard-RoleWorkspaces.ps1')
$script:dashboardCulture='en-US'
$checks=0
function Check($condition,$message) { if(-not $condition){throw $message}; $script:checks++ }
Check (-not (Test-ToolPersonalWorkspaceAllowed $false)) 'Explicit choice required'
Check (-not (Test-ToolPersonalWorkspaceAllowed $true '0.0.0.0')) 'Wildcard denied'
Check (-not (Test-ToolPersonalWorkspaceAllowed $true '192.168.1.2')) 'LAN denied'
Check (Test-ToolPersonalWorkspaceAllowed $true) 'Loopback permitted'
Check (-not (Test-RoleWorkspaceActionVisible 'itam' 'QuickAction' 6)) 'ITAM excludes cleanup'
Check (Test-RoleWorkspaceActionVisible 'helpdesk' 'QuickAction' 6) 'Helpdesk retains gated cleanup'
Check (Test-RoleWorkspaceActionVisible 'overview' 'QuickAction' 6) 'Overview retains all groups'
Check (-not (Test-RoleWorkspaceActionVisible 'personal' 'QuickAction' 8)) 'Personal excludes Enterprise management'
Check (Test-RoleWorkspaceActionVisible 'personal' 'QuickAction' 5) 'Personal retains software check'
Check (Test-RoleWorkspaceActionVisible 'personal' 'ReportAction' 0) 'Personal retains report access'
Check (-not (Test-RoleWorkspaceActionVisible 'itam' 'QuickAction' 9)) 'ITAM excludes forensic scan'
$fake=[pscustomobject]@{HasReport=$true;Latest=[pscustomobject]@{CreatedAt=(Get-Date);Path='secret';Report='private'};HighCount=1;MediumCount=2;LowCount=3;Items=@('secret')}
$state=ConvertTo-RoleResultSnapshot $fake 'running' $true
Check ($state.hasReport -and $state.busy -and $state.coverage -eq 'unknown') 'Existing report not proof of completed scan'
Check (($state | ConvertTo-Json -Depth 5) -notmatch 'secret|private|Path|Items') 'Safe projection'
$assets=Get-PersonalWorkspaceAssets
$bridge=$null
Add-Type -AssemblyName System.Net.Http
$handler=New-Object Net.Http.HttpClientHandler; $handler.UseProxy=$false
$client=New-Object Net.Http.HttpClient($handler)
try {
    $bridge=Start-ToolPersonalWorkspace @assets
    $css=$client.GetAsync($bridge.Origin+'/app.css').GetAwaiter().GetResult()
    Check ($css.IsSuccessStatusCode -and $css.Content.Headers.ContentType.MediaType -eq 'text/css') 'Stylesheet fixed route'
    $css.Dispose()
    Set-ToolPersonalWorkspaceSnapshot $bridge $state -Ready $true -Busy $false
    $token=[uri]::UnescapeDataString(([uri]$bridge.LaunchUri).Fragment.Substring(1))
    $request=New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Post,($bridge.Origin+'/api/scan'))
    [void]$request.Headers.TryAddWithoutValidation('X-VietLicenSure-Session',$token)
    [void]$request.Headers.TryAddWithoutValidation('Origin',$bridge.Origin)
    $reply=$client.SendAsync($request).GetAwaiter().GetResult()
    Check ([int]$reply.StatusCode -eq 202) 'Authenticated request queued'
    Check ((Receive-ToolPersonalWorkspaceAction $bridge) -eq 'scan') 'UI dispatcher receives scan'
    Check ($null -eq (Receive-ToolPersonalWorkspaceAction $bridge)) 'Request consumed once'
    $reply.Dispose();$request.Dispose()
} finally {
    if($bridge){Stop-ToolPersonalWorkspace $bridge}
    $client.Dispose(); $handler.Dispose()
}
Write-Output "Role integration contracts: $checks PASS. Desktop engine/browser/standard-user proof pending."
