param([string]$SourceDirectory=(Split-Path $PSScriptRoot -Parent),[string]$OutputDirectory='')
$ErrorActionPreference='Stop'
if(-not $OutputDirectory){$OutputDirectory=Join-Path $env:TEMP ('VLS-RoleBrowser-'+[guid]::NewGuid().ToString('N'))}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
. (Join-Path $SourceDirectory 'Tool-PersonalWorkspace.ps1')
. (Join-Path $SourceDirectory 'Dashboard-RoleWorkspaces.ps1')
$edgeCandidates=@(
 (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
 (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
 (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
 (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')
)
$edge=$edgeCandidates|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1
if(-not $edge){throw 'Chromium browser not found'}
$assets=Get-PersonalWorkspaceAssets;$bridge=$null;$cases=@();$profileRoot=Join-Path $env:TEMP ('VLS-RoleBrowserProfile-'+[guid]::NewGuid().ToString('N'))
function Clear-BrowserProfile {
 if(-not(Test-Path -LiteralPath $profileRoot)){return}
 Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue |
  Where-Object{[string]$_.CommandLine -like ('*'+$profileRoot+'*')}|ForEach-Object{Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}
 for($attempt=0;$attempt -lt 10;$attempt++){
  try{Remove-Item -LiteralPath $profileRoot -Recurse -Force -ErrorAction Stop;return}catch{Start-Sleep -Milliseconds 250}
 }
 throw 'Temporary browser profile cleanup failed'
}
try{
 $bridge=Start-ToolPersonalWorkspace @assets
 foreach($culture in @('vi-VN','en-US')){
  $snapshot=[ordered]@{status='finished';busy=$false;hasReport=$true;observedAt=[datetime]::UtcNow.ToString('o');coverage='partial';high=1;medium=2;low=3;culture=$culture}
  Set-ToolPersonalWorkspaceSnapshot $bridge $snapshot -Ready $true -Busy $false
  $shot=Join-Path $OutputDirectory ($culture+'.png');$dom=Join-Path $OutputDirectory ($culture+'.html');$err=Join-Path $OutputDirectory ($culture+'.stderr.private.log')
  New-Item -ItemType Directory -Path $profileRoot -Force|Out-Null
  $args=@('--headless=new','--disable-gpu','--no-first-run','--disable-default-apps',('--user-data-dir='+$profileRoot),'--window-size=1100,760','--virtual-time-budget=3500',('--screenshot='+$shot),'--dump-dom',$bridge.LaunchUri)
  $browserProcess=Start-Process -FilePath $edge -ArgumentList $args -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $dom -RedirectStandardError $err
  $browserExit=$browserProcess.ExitCode
  if($browserExit -ne 0 -or -not(Test-Path -LiteralPath $shot)){throw "Chromium failed: $culture/$browserExit"}
  $html=Get-Content -Raw -Encoding UTF8 $dom
  $expected=if($culture -eq 'en-US'){'<html lang="en"'}else{'<html lang="vi"'}
  if($html -notmatch [regex]::Escape($expected) -or $html -notmatch '1 / 2 / 3' -or
      $html -match 'X-VietLicenSure-Session|#[A-Za-z0-9%+/=]{20,}') {throw "Browser rendering or secret redaction failed: $culture"}
  $cases+=[pscustomobject]@{Culture=$culture;Rendered=$true;Screenshot=(Split-Path $shot -Leaf);DomHasExpectedText=$true}
  if(Test-Path -LiteralPath $err){Remove-Item -LiteralPath $err -Force}
  Clear-BrowserProfile
 }
 $cases|ConvertTo-Json -Depth 3|Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
 [pscustomobject]@{Passed=$true;Cases=$cases.Count;OutputDirectory=$OutputDirectory}|ConvertTo-Json -Compress
}finally{
 if($bridge -and -not $bridge.State.Closed){Stop-ToolPersonalWorkspace $bridge}
 if(Test-Path -LiteralPath $profileRoot){Clear-BrowserProfile}
}
