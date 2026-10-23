# Roles are presentation preferences, never an authorization boundary.
function Get-RoleWorkspaceText([string]$Key) {
    return (Get-ToolText -Key ('roleWorkspace.' + $Key) -Culture $script:dashboardCulture)
}

function Test-RoleWorkspaceActionVisible {
    param([string]$Role, [string]$Kind, [int]$Number)
    if ($Role -notin @('personal','helpdesk','itam')) { return $false }
    if ($Role -eq 'personal') { return $false }
    if ($Kind -eq 'ReportAction') { return $true }
    switch ($Role) {
        'itam' { return ($Number -in @(1,3,4,5,8,10)) }
        'helpdesk' { return $true }
        default { return $false }
    }
}

function Get-RoleWorkspaceName([string]$Role) {
    switch ($Role) {
        'personal' { return (Get-RoleWorkspaceText 'role.personal') }
        'helpdesk' { return (Get-RoleWorkspaceText 'role.helpdesk') }
        'itam' { return (Get-RoleWorkspaceText 'role.itam') }
        default { return (Get-RoleWorkspaceText 'role.unselected') }
    }
}

function Update-RoleWorkspaceChrome {
    if (-not $script:roleButton) { return }
    $roleName = Get-RoleWorkspaceName $script:workspaceRole
    $script:roleButton.Text = [string]::Format((Get-RoleWorkspaceText 'buttonFormat'), @($roleName))
    $script:roleButton.AccessibleName = $script:roleButton.Text
    $script:roleButton.AccessibleDescription = Get-RoleWorkspaceText 'buttonDescription'
    $toolTip.SetToolTip($script:roleButton, $script:roleButton.AccessibleDescription)
    $licenseButton = @($buttons | Where-Object { $_.Tag -and [int]$_.Tag.Number -eq 8 } | Select-Object -First 1)
    if ($licenseButton.Count -eq 1) {
        $licenseButton = $licenseButton[0]
        if ($script:workspaceRole -eq 'itam') {
            $licenseButton.Tag.TitleKey = 'roleWorkspace.menu.enterprise.title'
            $licenseButton.Tag.DescriptionKey = 'roleWorkspace.menu.enterprise.description'
        } else {
            $licenseButton.Tag.TitleKey = 'menu.8.title'
            $licenseButton.Tag.DescriptionKey = 'menu.8.description'
        }
        $licenseButton.Tag.TitleLabel.Text = Get-ToolText -Key $licenseButton.Tag.TitleKey -Culture $script:dashboardCulture
        $licenseButton.Tag.DescriptionLabel.Text = Get-ToolText -Key $licenseButton.Tag.DescriptionKey -Culture $script:dashboardCulture
        $licenseButton.Text = $licenseButton.Tag.TitleLabel.Text
        $licenseButton.AccessibleName = $licenseButton.Tag.TitleLabel.Text
        $licenseButton.AccessibleDescription = $licenseButton.Tag.DescriptionLabel.Text
    }
}

function Test-ToolPersonalWorkspaceAllowed {
    param([bool]$ExplicitChoice, [string]$BindAddress = '127.0.0.1')
    # Separate local UI capability. Does not change offline/LAN/Internet policy.
    return ($ExplicitChoice -and $BindAddress -ceq '127.0.0.1')
}

function ConvertTo-RoleResultSnapshot {
    param($Result, [string]$TaskStatus, [bool]$Busy)
    $hasReport = [bool]($Result -and $Result.HasReport)
    $observedAt = $null
    if ($hasReport -and $Result.Latest) { $observedAt = ([datetime]$Result.Latest.CreatedAt).ToUniversalTime().ToString('o') }
    # No raw evidence, paths, keys, device identifiers or arbitrary report text.
    return [ordered]@{
        status=$TaskStatus; busy=$Busy; hasReport=$hasReport; observedAt=$observedAt
        coverage='unknown'; high=$(if($hasReport){[int]$Result.HighCount}else{0})
        medium=$(if($hasReport){[int]$Result.MediumCount}else{0})
        low=$(if($hasReport){[int]$Result.LowCount}else{0})
        culture=[string]$script:dashboardCulture
        offline=[bool]$script:offlineMode
        theme=[string]$script:dashboardTheme
        role=[string]$script:workspaceRole
    }
}

function Get-PersonalWorkspaceAssets {
    $page = @'
<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>VietLicenSure · Personal</title><link rel="stylesheet" href="/app.css"></head><body><main><header><strong>VietLicenSure</strong><nav aria-label="Điều khiển"><button data-action="back" id="back">Trở về</button><button data-action="role" id="role">Đổi vai trò</button><button data-action="network" id="network">Offline</button><button data-action="language" id="language">VI</button><button data-action="theme" id="theme">Sáng</button><button data-action="about" id="about">Giới thiệu</button><button data-action="assistant" id="assistant">Trợ lý</button></nav></header><h1 id="title">Không gian Cá nhân</h1><p id="intro">Kiểm tra → hiểu kết quả → chọn bước an toàn.</p><section><h2 id="scanTitle">Bắt đầu kiểm tra</h2><p id="consent">Chọn phạm vi. Ứng dụng Windows vẫn giữ các bước xác nhận quyền riêng tư/quyền đọc và không tự sửa giấy phép.</p><div class="scopes"><button data-run data-action="scan-all" id="scanAll">Toàn bộ</button><button data-run data-action="scan-hardware" id="scanHardware">Phần cứng</button><button data-run data-action="scan-windows" id="scanWindows">Windows</button><button data-run data-action="scan-office" id="scanOffice">Office</button><button data-run data-action="scan-software" id="scanSoftware">Phần mềm &amp; dấu hiệu can thiệp</button><button data-run data-action="reports" id="reports">Báo cáo</button></div><p id="status" role="status" aria-live="polite"></p></section><section><h2 id="resultsTitle">Kết quả dùng chung với ứng dụng</h2><p id="result"></p><p id="limit">Kích hoạt không chứng minh quyền sở hữu. Kết quả cũ không được trộn với tác vụ đang chạy; xem phạm vi và bằng chứng trong báo cáo.</p></section><footer id="foot">Web cục bộ trên máy · Dùng chung engine và dữ liệu với ứng dụng · Đóng tab không hủy tác vụ.</footer></main><script src="/app.js"></script></body></html>
'@
    $js = @'
'use strict';
let token='';try{token=decodeURIComponent(location.hash.slice(1))}catch{}
history.replaceState(null,'',location.pathname);
const el=id=>document.getElementById(id);let sending=false;
const messages={vi:{starting:'Đang chuẩn bị',idle:'Sẵn sàng',not_started:'Chưa bắt đầu: kiểm tra xác nhận trong ứng dụng.',awaiting_confirmation:'Chờ xác nhận trong ứng dụng Windows',running:'Đang chạy trong ứng dụng',finished:'Tiến trình đã kết thúc; xem phạm vi thực tế trong báo cáo.',error:'Tác vụ lỗi; xem chi tiết trong ứng dụng.'},en:{starting:'Starting',idle:'Ready',not_started:'Not started: check the desktop confirmation.',awaiting_confirmation:'Confirm in the Windows application',running:'Running in the application',finished:'Process finished; check actual coverage in the report.',error:'Task failed; see details in the application.'}};
let lang='vi';const ids=['back','role','network','language','theme','about','assistant','title','intro','scanTitle','consent','scanAll','scanHardware','scanWindows','scanOffice','scanSoftware','reports','resultsTitle','limit','foot'];const viLabels=Object.fromEntries(ids.map(id=>[id,el(id).textContent]));
function controls(disabled){document.querySelectorAll('[data-run]').forEach(b=>b.disabled=disabled)}
function translate(en,state){const labels=en?{back:'Back',role:'Change role',network:state.offline?'Offline':'Online',language:'EN',theme:state.theme==='Dark'?'Dark':'Light',about:'About',assistant:'Assistant',title:'Personal workspace',intro:'Check → understand → choose a safe next step.',scanTitle:'Start a check',consent:'Choose a scope. The Windows application still enforces privacy/read-permission confirmations and never changes licenses automatically.',scanAll:'Complete',scanHardware:'Hardware',scanWindows:'Windows',scanOffice:'Office',scanSoftware:'Software & tampering indicators',reports:'Reports',resultsTitle:'Results shared with the application',limit:'Activation does not prove ownership. Previous results are not mixed with a running task; review coverage and evidence in the report.',foot:'Local web UI · Shared engine and data with the application · Closing the tab does not cancel tasks.'}:Object.assign({},viLabels,{network:state.offline?'Offline':'Online',language:'VI',theme:state.theme==='Dark'?'Tối':'Sáng'});Object.entries(labels).forEach(([id,t])=>el(id).textContent=t);document.documentElement.lang=en?'en':'vi';document.documentElement.dataset.theme=state.theme==='Dark'?'dark':'light'}
async function api(path,method='GET'){const r=await fetch(path,{method,headers:{'X-VietLicenSure-Session':token},cache:'no-store',credentials:'omit'});if(!r.ok)throw new Error(String(r.status));return r.json()}
async function refresh(){try{const s=await api('/api/state');lang=s.culture==='en-US'?'en':'vi';translate(lang==='en',s);el('status').textContent=messages[lang][s.status]||s.status;el('result').textContent=s.hasReport?(lang==='en'?'Previous observed result: ':'Kết quả đã ghi nhận: ')+s.observedAt+' · '+(lang==='en'?'High / Medium / Low: ':'Cao / Vừa / Thấp: ')+[s.high,s.medium,s.low].join(' / '):(lang==='en'?'No saved report yet.':'Chưa có báo cáo đã lưu.');controls(s.busy||sending)}catch{controls(true);el('status').textContent=lang==='en'?'Session unavailable. Reopen Personal from the application.':'Phiên không khả dụng. Mở lại Cá nhân từ ứng dụng.'}}
document.querySelectorAll('[data-action]').forEach(b=>b.addEventListener('click',async()=>{sending=true;controls(true);try{await api('/api/'+b.dataset.action,'POST')}catch{el('status').textContent=lang==='en'?'Request not accepted. Check the application.':'Yêu cầu chưa được nhận. Kiểm tra ứng dụng.'}finally{sending=false;await refresh()}}));
if(token){refresh();setInterval(refresh,1500)}else{controls(true);el('status').textContent='Mở trang từ ứng dụng / Open from the application.'}
'@
    return @{ Page=$page; JavaScript=$js; StyleSheet=':root{font:16px Segoe UI,sans-serif;color:#20344e;background:#f3f6fb}body{margin:0}main{max-width:1040px;margin:auto;padding:24px}header{display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap}nav,.scopes{display:flex;gap:8px;flex-wrap:wrap}.scopes{display:grid;grid-template-columns:repeat(3,minmax(180px,1fr))}section{background:white;padding:24px;border:1px solid #ccd8e6;border-radius:12px;margin:20px 0}button{font:inherit;background:#175fc5;color:white;border:0;border-radius:8px;padding:11px 13px;cursor:pointer}nav button{background:#fff;color:#175fc5;border:1px solid #b9cae0}button:disabled{opacity:.55;cursor:default}button:focus-visible{outline:3px solid #c57a00;outline-offset:3px}p,footer{line-height:1.6}footer{font-size:14px}[data-theme=dark]{color:#e5edf7;background:#142034}[data-theme=dark] section{background:#1d2e47;border-color:#40536e}[data-theme=dark] nav button{background:#1d2e47;color:#e5edf7;border-color:#60738d}@media(max-width:720px){.scopes{grid-template-columns:1fr}main{padding:14px}}' }
}

function Update-PersonalWorkspace {
    if (-not $script:personalBridge) { return }
    # Timer runs on the desktop UI thread; never starts a parallel engine.
    $busy = [bool]($script:activeProcess -and -not $script:activeProcess.HasExited)
    if ($script:roleScanProcess) {
        if ($script:roleScanProcess.HasExited) {
            $script:roleTaskStatus = if ($script:roleScanProcess.ExitCode -eq 0) {'finished'} else {'error'}
            $script:roleScanProcess = $null
            $script:roleResultRefresh = [datetime]::MinValue
        } else { $script:roleTaskStatus = 'running' }
    }
    if (-not $script:roleResultRefresh -or ((Get-Date)-$script:roleResultRefresh).TotalSeconds -ge 5) {
        try { $script:roleResult = Get-ToolResultCenterState -ReportRoot $reportRoot -MaximumReports 40 }
        catch { $script:roleResult = $null }
        $script:roleResultRefresh = Get-Date
    }
    $ready = [bool]($script:roleWorkspaceReady -and $script:workspaceRole -eq 'personal' -and $script:dashboardMenusInitialized -and $languageCombo.Enabled)
    $snapshot = ConvertTo-RoleResultSnapshot $script:roleResult $script:roleTaskStatus $busy
    Set-ToolPersonalWorkspaceSnapshot $script:personalBridge $snapshot -Ready:$ready -Busy:$busy
    $action = Receive-ToolPersonalWorkspaceAction $script:personalBridge
    if (-not $action) { return }
    $script:roleTimer.Stop()
    try {
        switch ($action) {
            { $_ -in @('scan-all','scan-hardware','scan-windows','scan-office','scan-software') } {
                $scope = switch ($action) {
                    'scan-hardware' { 'Hardware' }
                    'scan-windows' { 'Windows' }
                    'scan-office' { 'Office' }
                    'scan-software' { 'Software' }
                    default { 'All' }
                }
                $menuNumber = switch ($scope) { 'Hardware' {2} 'Windows' {3} 'Office' {4} 'Software' {5} default {1} }
                $script:roleTaskStatus = 'awaiting_confirmation'
                $snapshot.status = $script:roleTaskStatus
                Set-ToolPersonalWorkspaceSnapshot $script:personalBridge $snapshot -Ready:$false -Busy:$true
                $form.Activate()
                Start-Report $scope (Get-ToolText -Key ("menu.$menuNumber.title") -Culture $script:dashboardCulture)
                if ($script:activeProcess -and -not $script:activeProcess.HasExited) {
                    $script:roleScanProcess = $script:activeProcess; $script:roleTaskStatus='running'
                } else { $script:roleTaskStatus='not_started' }
            }
            'reports' { $form.WindowState='Normal'; $form.Show(); $form.Activate(); Show-ResultActionCenter }
            'back' { $form.WindowState='Normal'; $form.Show(); $form.Activate() }
            'role' { $form.WindowState='Normal'; $form.Show(); $form.Activate(); Show-RoleWorkspaceChooser }
            'network' { $form.WindowState='Normal'; $form.Show(); $form.Activate(); Toggle-DashboardOfflineMode }
            'language' { Set-DashboardLanguage -Culture $(if($script:dashboardCulture -eq 'en-US'){'vi-VN'}else{'en-US'}) }
            'theme' { $themeButton.PerformClick() }
            'about' { $form.WindowState='Normal'; $form.Show(); $introDetailButton.PerformClick() }
            'assistant' { $form.WindowState='Normal'; $form.Show(); $introAssistantButton.PerformClick() }
        }
    } catch { $script:roleTaskStatus='error' }
    finally { $script:roleTimer.Start() }
}

function Open-PersonalRoleWorkspace {
    if (-not (Test-ToolPersonalWorkspaceAllowed -ExplicitChoice $true)) { return }
    if (-not $script:personalBridge) {
        $assets=Get-PersonalWorkspaceAssets
        $script:personalBridge=Start-ToolPersonalWorkspace @assets
        $script:roleTaskStatus='idle'
    }
    Update-PersonalWorkspace
    # No token in logs, preferences or process evidence. Browser URL fragment only.
    Start-Process -FilePath $script:personalBridge.LaunchUri | Out-Null
    $form.WindowState='Minimized'
}

function Show-RoleWorkspaceChooser {
    $chooser=New-Object Windows.Forms.Form
    $chooser.Text=Get-RoleWorkspaceText 'chooser.title'
    $chooser.Size=New-Object Drawing.Size(660,400)
    $chooser.MinimumSize=New-Object Drawing.Size(560,360)
    $chooser.StartPosition='CenterParent'
    $chooser.FormBorderStyle='FixedDialog'; $chooser.ControlBox=$false
    $chooser.AutoScroll=$true
    $chooser.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi
    $chooser.Font=$fontNormal
    $layout=New-Object Windows.Forms.FlowLayoutPanel
    $layout.Dock='Fill'; $layout.FlowDirection='TopDown'; $layout.WrapContents=$false; $layout.AutoScroll=$true
    $layout.Padding=New-Object Windows.Forms.Padding(22,20,22,20)
    $chooser.Controls.Add($layout)
    $note=New-Object Windows.Forms.Label
    $note.Size=New-Object Drawing.Size(590,68)
    $note.Text=Get-RoleWorkspaceText 'chooser.intro'
    $layout.Controls.Add($note)
    $labels=@((Get-RoleWorkspaceText 'choice.personal'),(Get-RoleWorkspaceText 'choice.helpdesk'),(Get-RoleWorkspaceText 'choice.itam'))
    $roles=@('personal','helpdesk','itam')
    for($i=0;$i -lt 3;$i++) {
        $button=New-Object Windows.Forms.Button
        $button.Size=New-Object Drawing.Size(590,58); $button.Text=$labels[$i]; $button.Tag=$roles[$i]
        $button.TextAlign='MiddleLeft'; $button.Padding=New-Object Windows.Forms.Padding(12,0,12,0)
        $button.AccessibleName=$button.Text; $button.AccessibleDescription=$button.Text
        $button.Add_Click({param($sender,$eventArgs) $sender.FindForm().Tag=[string]$sender.Tag; $sender.FindForm().Close()})
        $layout.Controls.Add($button)
    }
    $chooser.Add_FormClosing({param($sender,$e) if([string]::IsNullOrWhiteSpace([string]$sender.Tag)){$e.Cancel=$true}})
    Set-ToolWindowTheme -Root $chooser -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $chooser); $selected=[string]$chooser.Tag; $chooser.Dispose()
    if (-not $selected) { throw 'RoleWorkspaceSelectionRequired' }
    $script:workspaceRole=$selected
    Update-RoleWorkspaceChrome
    Set-DashboardSection -Section 'Overview'
    if ($selected -eq 'personal') {
        try { Open-PersonalRoleWorkspace }
        catch { [void][Windows.Forms.MessageBox]::Show((Get-RoleWorkspaceText 'webUnavailable'),'VietLicenSure') }
    } elseif ($script:personalBridge) {
        # Switching workspace closes only the local browser session. A desktop
        # task already confirmed by the user continues under the shared engine.
        Stop-ToolPersonalWorkspace $script:personalBridge
        $script:personalBridge=$null
    }
}

function Initialize-RoleWorkspaces {
    if ($script:roleTimer) { return }
    $script:roleWorkspaceReady=$true; $script:workspaceRole='unselected'
    $script:roleTaskStatus='idle'
    $script:roleButton=New-Object Windows.Forms.Button
    $script:roleButton.Size=New-Object Drawing.Size(220,28)
    $script:roleButton.Top=4; $script:roleButton.Anchor='Top,Right'
    $script:roleButton.Left=[Math]::Max(0,$buttonPanel.ClientSize.Width-230)
    $script:roleButton.Add_Click({Show-RoleWorkspaceChooser})
    $buttonPanel.Controls.Add($script:roleButton); $script:roleButton.BringToFront()
    $buttonPanel.Add_SizeChanged({
        $script:roleButton.Left=[Math]::Max(0,$buttonPanel.ClientSize.Width-230)
        $menuCaption.Width=[Math]::Max(70,$buttonPanel.ClientSize.Width-260)
    })
    Update-RoleWorkspaceChrome
    $script:roleTimer=New-Object Windows.Forms.Timer; $script:roleTimer.Interval=1000
    $script:roleTimer.Add_Tick({Update-PersonalWorkspace}); $script:roleTimer.Start()
    $form.Add_FormClosed({
        $script:roleTimer.Stop(); $script:roleTimer.Dispose()
        if($script:personalBridge){Stop-ToolPersonalWorkspace $script:personalBridge; $script:personalBridge=$null}
    })
    [void]$form.BeginInvoke([Action]{Show-RoleWorkspaceChooser})
}
