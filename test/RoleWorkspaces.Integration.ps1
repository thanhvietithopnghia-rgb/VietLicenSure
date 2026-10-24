$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Dashboard-RoleWorkspaces.ps1')
$checks=0
function Check($condition,$message) { if(-not $condition){throw $message}; $script:checks++ }

Check (-not (Test-RoleWorkspaceActionVisible 'unselected' 'QuickAction' 1)) 'Unselected workspace exposes a quick action'
Check (-not (Test-RoleWorkspaceActionVisible 'unselected' 'ReportAction' 0)) 'Unselected workspace exposes a report'

foreach($number in 1..5){Check (Test-RoleWorkspaceActionVisible 'personal' 'QuickAction' $number) "Personal misses native action $number"}
foreach($number in @(6,7,8,9,10,11,12,13,14)){Check (-not (Test-RoleWorkspaceActionVisible 'personal' 'QuickAction' $number)) "Personal exposes privileged/support action $number"}
Check (Test-RoleWorkspaceActionVisible 'personal' 'ReportAction' 0) 'Personal misses native reports'

foreach($number in 1..14){Check (Test-RoleWorkspaceActionVisible 'helpdesk' 'QuickAction' $number) "Helpdesk misses action $number"}
Check (Test-RoleWorkspaceActionVisible 'helpdesk' 'ReportAction' 0) 'Helpdesk misses reports'

foreach($number in @(1,3,4,5,8,10)){Check (Test-RoleWorkspaceActionVisible 'itam' 'QuickAction' $number) "ITAM misses action $number"}
foreach($number in @(2,6,7,9,11,12,13,14)){Check (-not (Test-RoleWorkspaceActionVisible 'itam' 'QuickAction' $number)) "ITAM exposes out-of-scope action $number"}
Check (Test-RoleWorkspaceActionVisible 'itam' 'ReportAction' 0) 'ITAM misses reports'

$roleSource=Get-Content -LiteralPath (Join-Path $root 'Dashboard-RoleWorkspaces.ps1') -Raw -Encoding UTF8
$entrySource=Get-Content -LiteralPath (Join-Path $root 'Giao-Dien.ps1') -Raw -Encoding UTF8
$buildSource=Get-Content -LiteralPath (Join-Path $root 'BUILD.ps1') -Raw -Encoding UTF8
Check ($roleSource -notmatch 'PersonalWorkspace|personalBridge|LaunchUri|Start-Process') 'Role module still launches a Personal browser'
Check ($entrySource -notmatch 'Tool-PersonalWorkspace') 'Dashboard still imports the Personal web transport'
Check ($buildSource -notmatch 'Tool-PersonalWorkspace') 'Build still packages the Personal web transport'
Check (-not (Test-Path -LiteralPath (Join-Path $root 'Tool-PersonalWorkspace.ps1'))) 'Personal web transport source still exists'
Check ($roleSource -match '\$clientWidth -lt 560' -and $roleSource -match '\$menuCaption\.Visible = \$false') 'Narrow workspace does not replace the clipped duplicate caption'
Check ($roleSource -match '\$script:roleButton\.Width = \[Math\]::Max\(120, \$clientWidth - 32\)') 'Narrow role button can overflow its viewport'

[pscustomobject]@{Passed=$true;Checks=$checks;Mode='Native role-filtered WinForms only'}|ConvertTo-Json -Compress
