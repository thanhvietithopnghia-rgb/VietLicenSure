param([string]$SourceDirectory=(Split-Path $PSScriptRoot -Parent),[string]$OutputDirectory='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if(-not $OutputDirectory){$OutputDirectory=Join-Path $env:TEMP ('VLS-RoleUI-'+[guid]::NewGuid().ToString('N'))}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$script:maps=@{}
foreach($culture in @('vi-VN','en-US')){$script:maps[$culture]=Get-Content -Raw -Encoding UTF8 (Join-Path $SourceDirectory ('Tool-Strings.'+$culture+'.json'))|ConvertFrom-Json}
function Get-ToolText{param([string]$Key,[string]$Culture) $value=$script:maps[$Culture].PSObject.Properties[$Key];if(-not $value){throw "Missing localization key: $Culture/$Key"};[string]$value.Value}
function Set-ToolWindowTheme{}
function Show-DashboardModalDialog{param($Dialog)[void]$Dialog.ShowDialog($script:form)}
function Set-DashboardSection{param([string]$Section)$script:lastSection=$Section}
. (Join-Path $SourceDirectory 'Dashboard-RoleWorkspaces.ps1')
$script:dashboardTheme='Light'
$script:form=New-Object Windows.Forms.Form
$script:form.ShowInTaskbar=$false;$script:form.Opacity=0;$script:form.Size=New-Object Drawing.Size(900,650)
$script:fontNormal=New-Object Drawing.Font('Segoe UI',9)
$script:toolTip=New-Object Windows.Forms.ToolTip
$results=@();$checks=0
try{
 foreach($culture in @('vi-VN','en-US')){
  $script:dashboardCulture=$culture
  foreach($role in @('personal','helpdesk','itam')){
   $script:lastSection=''
   $timer=New-Object Windows.Forms.Timer;$timer.Interval=180
   $timer.Add_Tick({
    $dialog=@([Windows.Forms.Application]::OpenForms|Where-Object{$_.Owner -eq $script:form -and $_ -ne $script:form})|Select-Object -First 1
    if(-not $dialog){return}
    $buttons=@($dialog.Controls|ForEach-Object{$_.Controls}|Where-Object{$_ -is [Windows.Forms.Button]})
    if($buttons.Count -ne 3){throw "Role chooser button count: $($buttons.Count)"}
    if($dialog.ControlBox){throw 'Mandatory role chooser must not expose a close button'}
    foreach($button in $buttons){
      $measured=[Windows.Forms.TextRenderer]::MeasureText($button.Text,$button.Font,(New-Object Drawing.Size(($button.ClientSize.Width-24),300)),([Windows.Forms.TextFormatFlags]::WordBreak -bor [Windows.Forms.TextFormatFlags]::NoPrefix))
      if($measured.Height -gt ($button.ClientSize.Height-4)){throw "Role text clipped: $culture/$($button.Tag)"}
      if([string]::IsNullOrWhiteSpace($button.AccessibilityObject.Name)){throw "Role button unnamed: $culture/$($button.Tag)"}
    }
    $bitmap=New-Object Drawing.Bitmap($dialog.ClientSize.Width,$dialog.ClientSize.Height)
    $dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)))
    $bitmap.Save((Join-Path $OutputDirectory ($culture+'-'+$role+'.png')),[Drawing.Imaging.ImageFormat]::Png);$bitmap.Dispose()
    $target=$buttons|Where-Object{[string]$_.Tag -eq $role}|Select-Object -First 1
    $timer.Stop();$target.PerformClick()
   })
   $timer.Start();Show-RoleWorkspaceChooser;$timer.Dispose()
   if($script:workspaceRole -cne $role){throw "Selected role mismatch: $culture/$role"};$checks++
   if($script:lastSection -cne 'Overview'){throw "Role did not return to overview: $culture/$role"};$checks++
   if($script:form.WindowState -eq [Windows.Forms.FormWindowState]::Minimized){throw "Native dashboard was minimized: $culture/$role"};$checks++
   $results+=[pscustomobject]@{Culture=$culture;Role=$role;Selected=$script:workspaceRole;NativeDashboard=$true;Passed=$true}
  }
 }
 $results|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
 [pscustomobject]@{Passed=$true;Checks=$checks;Cases=$results.Count;OutputDirectory=$OutputDirectory}|ConvertTo-Json -Compress
}finally{$script:toolTip.Dispose();$script:fontNormal.Dispose();$script:form.Dispose()}
