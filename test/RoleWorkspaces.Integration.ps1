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
$layoutSource=Get-Content -LiteralPath (Join-Path $root 'Dashboard-Core.ps1') -Raw -Encoding UTF8
$buildSource=Get-Content -LiteralPath (Join-Path $root 'BUILD.ps1') -Raw -Encoding UTF8
Check ($roleSource -notmatch 'PersonalWorkspace|personalBridge|LaunchUri|Start-Process') 'Role module still launches a Personal browser'
Check ($entrySource -notmatch 'Tool-PersonalWorkspace') 'Dashboard still imports the Personal web transport'
Check ($buildSource -notmatch 'Tool-PersonalWorkspace') 'Build still packages the Personal web transport'
Check (-not (Test-Path -LiteralPath (Join-Path $root 'Tool-PersonalWorkspace.ps1'))) 'Personal web transport source still exists'
Check ($roleSource -match '\$clientWidth -lt 560' -and $roleSource -match '\$menuCaption\.Visible = \$false') 'Narrow workspace does not replace the clipped duplicate caption'
Check ($roleSource -match "roleButton\.Anchor='Top,Left'" -and $roleSource -match 'verticalReserve') 'Narrow role button can drift or overlap the vertical scrollbar'
Check ($roleSource -match 'AutoScrollPosition = New-Object Drawing\.Point\(0, \$currentVerticalOffset\)') 'Narrow workspace does not force the horizontal offset back to zero'
Check ($layoutSource -match '\$menuCaption\.Width = \[Math\]::Max\(40, \$buttonPanel\.ClientSize\.Width - 28\)') 'Hidden narrow caption can still force a horizontal scrollbar'
Check ($roleSource -match '\$idleBack' -and $roleSource -match '\$selectedBack' -and $roleSource -match 'MouseOverBackColor') 'Role choices do not distinguish calm idle, hover, and selected states'
Check ($roleSource -match 'ResumeLayout\(\$false\)' -and $roleSource -notmatch 'ResumeLayout\(\$true\)') 'Role switching still forces a redundant full layout pass'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
function Test-ToolUiHighContrast { return $false }
$script:dashboardTheme = 'Light'
$fontBold = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$personalIdle = New-Object Windows.Forms.Button
$personalSelected = New-Object Windows.Forms.Button
try {
    Set-RoleWorkspaceButtonVisual -Button $personalIdle -Role personal
    Set-RoleWorkspaceButtonVisual -Button $personalSelected -Role personal -Selected
    Check ($personalIdle.BackColor.ToArgb() -ne $personalSelected.BackColor.ToArgb()) 'Selected role is not visually stronger than idle role'
    Check ($personalSelected.ForeColor.ToArgb() -ne $personalSelected.BackColor.ToArgb()) 'Selected role does not retain contrasting text'
    Check ($personalIdle.BackColor.R -ge 230 -and $personalIdle.BackColor.G -ge 230 -and $personalIdle.BackColor.B -ge 230) 'Idle role color is still overly saturated'
} finally {
    $personalIdle.Dispose(); $personalSelected.Dispose(); $fontBold.Dispose()
}

[pscustomobject]@{Passed=$true;Checks=$checks;Mode='Native role-filtered WinForms only'}|ConvertTo-Json -Compress
