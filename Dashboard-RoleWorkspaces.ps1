# Roles are presentation preferences, never an authorization boundary.
function Get-RoleText([string]$Vi, [string]$En) {
    if ($script:dashboardCulture -eq 'en-US') { return $En }; return $Vi
}

function Test-RoleWorkspaceActionVisible {
    param([string]$Role, [string]$Kind, [int]$Number)
    if ($Kind -eq 'ReportAction') { return ($Role -ne 'personal') }
    switch ($Role) {
        'personal' { return ($Number -in @(1,3,4,8,10)) }
        'itam' { return ($Number -in @(1,2,3,4,8,9,10)) }
        default { return $true }
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
    }
}

function Get-PersonalWorkspaceAssets {
    $page = @'
<!doctype html><html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>VietLicenSure · Personal</title><link rel="stylesheet" href="/app.css"><body><main><header><strong>VietLicenSure</strong><button data-action="overview" id="overview">Đổi vai trò / Tổng quan</button></header><h1 id="title">Không gian Cá nhân</h1><p id="intro">Kiểm tra → hiểu kết quả → chọn bước an toàn.</p><section><h2 id="scanTitle">Kiểm tra máy này</h2><p id="consent">Ứng dụng Windows sẽ hỏi phạm vi, quyền riêng tư và quyền đọc cần thiết. Không tự sửa giấy phép.</p><button data-action="scan" id="scan">Bắt đầu kiểm tra</button><p id="status" role="status" aria-live="polite"></p></section><section><h2 id="resultsTitle">Kết quả dùng chung với ứng dụng</h2><p id="result"></p><p id="limit">Kích hoạt không chứng minh quyền sở hữu. Phạm vi và bằng chứng cần xem trong báo cáo; kết quả cũ không phải kết quả của tác vụ đang chạy.</p><button data-action="results" id="results">Mở kết quả / báo cáo trong ứng dụng</button></section><footer id="foot">Chỉ kết nối nội bộ máy · Đóng tab không hủy tác vụ · Đóng ứng dụng kết thúc phiên web.</footer></main><script src="/app.js"></script></body></html>
'@
    $js = @'
'use strict';
let token='';try{token=decodeURIComponent(location.hash.slice(1))}catch{}
history.replaceState(null,'',location.pathname);
const el=id=>document.getElementById(id);let sending=false;
const messages={vi:{starting:'Đang chuẩn bị',idle:'Sẵn sàng',not_started:'Chưa bắt đầu: kiểm tra xác nhận trong ứng dụng.',awaiting_confirmation:'Chờ xác nhận trong ứng dụng Windows',running:'Đang chạy trong ứng dụng',finished:'Tiến trình đã kết thúc; xem phạm vi thực tế trong báo cáo.',error:'Tác vụ lỗi; xem chi tiết trong ứng dụng.'},en:{starting:'Starting',idle:'Ready',not_started:'Not started: check the desktop confirmation.',awaiting_confirmation:'Confirm in the Windows application',running:'Running in the application',finished:'Process finished; check actual coverage in the report.',error:'Task failed; see details in the application.'}};
let lang='vi';const originalLabels=Object.fromEntries(['overview','title','intro','scanTitle','consent','scan','resultsTitle','limit','results','foot'].map(id=>[id,el(id).textContent]));
function controls(disabled){document.querySelectorAll('[data-action]').forEach(b=>b.disabled=disabled);if(!disabled)el('results').disabled=el('results').dataset.empty==='true'}
function translate(en){const labels=en?{overview:'Change role / Overview',title:'Personal workspace',intro:'Check → understand → choose a safe next step.',scanTitle:'Check this computer',consent:'The desktop will request scope, privacy and required read permissions. No automatic license changes.',scan:'Start check',resultsTitle:'Results shared with the application',limit:'Activation does not prove ownership. Review coverage and evidence in the report. Previous results are not results of a running task.',results:'Open results / reports in the application',foot:'Local connection only · Closing this tab does not cancel tasks · Closing the application ends this session.'}:null;if(labels)Object.entries(labels).forEach(([id,t])=>el(id).textContent=t);document.documentElement.lang=en?'en':'vi'}
async function api(path,method='GET'){const r=await fetch(path,{method,headers:{'X-VietLicenSure-Session':token},cache:'no-store',credentials:'omit'});if(!r.ok)throw new Error(String(r.status));return r.json()}
async function refresh(){try{const s=await api('/api/state');lang=s.culture==='en-US'?'en':'vi';if(lang==='vi')Object.entries(originalLabels).forEach(([id,t])=>el(id).textContent=t);translate(lang==='en');el('status').textContent=messages[lang][s.status]||s.status;el('results').dataset.empty=String(!s.hasReport);el('result').textContent=s.hasReport?(lang==='en'?'Previous observed result: ':'Kết quả đã ghi nhận: ')+s.observedAt+' · '+(lang==='en'?'High / Medium / Low: ':'Cao / Vừa / Thấp: ')+[s.high,s.medium,s.low].join(' / '):(lang==='en'?'No saved report yet.':'Chưa có báo cáo đã lưu.');controls(s.busy||sending)}catch{controls(true);el('status').textContent=lang==='en'?'Session unavailable. Reopen Personal from the application.':'Phiên không khả dụng. Mở lại Cá nhân từ ứng dụng.'}}
document.querySelectorAll('[data-action]').forEach(b=>b.addEventListener('click',async()=>{sending=true;controls(true);try{await api('/api/'+b.dataset.action,'POST')}catch{el('status').textContent=lang==='en'?'Request not accepted. Check the application.':'Yêu cầu chưa được nhận. Kiểm tra ứng dụng.'}finally{sending=false;await refresh()}}));
if(token){refresh();setInterval(refresh,1500)}else{controls(true);el('status').textContent='Mở trang từ ứng dụng / Open from the application.'}
'@
    return @{ Page=$page; JavaScript=$js; StyleSheet=':root{font:16px Segoe UI,sans-serif;color:#20344e;background:#f3f6fb}body{margin:0}main{max-width:900px;margin:auto;padding:24px}header{display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap}section{background:white;padding:24px;border:1px solid #ccd8e6;border-radius:12px;margin:20px 0}button{font:inherit;background:#175fc5;color:white;border:0;border-radius:8px;padding:12px;cursor:pointer}button:disabled{opacity:.55;cursor:default}button:focus-visible{outline:3px solid #c57a00;outline-offset:3px}p,footer{line-height:1.6}footer{font-size:14px}@media(prefers-color-scheme:dark){:root{color:#e5edf7;background:#142034}section{background:#1d2e47}}' }
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
    $ready = [bool]($script:roleWorkspaceReady -and $script:dashboardMenusInitialized -and $languageCombo.Enabled)
    $snapshot = ConvertTo-RoleResultSnapshot $script:roleResult $script:roleTaskStatus $busy
    Set-ToolPersonalWorkspaceSnapshot $script:personalBridge $snapshot -Ready:$ready -Busy:$busy
    $action = Receive-ToolPersonalWorkspaceAction $script:personalBridge
    if (-not $action) { return }
    $script:roleTimer.Stop()
    try {
        switch ($action) {
            'scan' {
                $script:roleTaskStatus = 'awaiting_confirmation'
                $snapshot.status = $script:roleTaskStatus
                Set-ToolPersonalWorkspaceSnapshot $script:personalBridge $snapshot -Ready:$false -Busy:$true
                $form.Activate()
                Start-Report 'All' (Get-ToolText -Key 'menu.1.title' -Culture $script:dashboardCulture)
                if ($script:activeProcess -and -not $script:activeProcess.HasExited) {
                    $script:roleScanProcess = $script:activeProcess; $script:roleTaskStatus='running'
                } else { $script:roleTaskStatus='not_started' }
            }
            'results' { $form.Activate(); Show-ResultActionCenter }
            'overview' { $form.Activate(); Show-RoleWorkspaceChooser }
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
}

function Show-RoleWorkspaceChooser {
    $chooser=New-Object Windows.Forms.Form
    $chooser.Text=Get-RoleText 'Không gian làm việc' 'Workspaces'
    $chooser.Size=New-Object Drawing.Size(620,420)
    $chooser.StartPosition='CenterParent'
    $chooser.AutoScroll=$true
    $layout=New-Object Windows.Forms.FlowLayoutPanel
    $layout.Dock='Fill'; $layout.FlowDirection='TopDown'; $layout.WrapContents=$false; $layout.AutoScroll=$true
    $chooser.Controls.Add($layout)
    $note=New-Object Windows.Forms.Label
    $note.Size=New-Object Drawing.Size(550,65)
    $note.Text=Get-RoleText 'Tổng quan: kiểm tra, giấy phép, điều tra, tác vụ Agent và báo cáo. Chọn vai trò chỉ đổi không gian làm việc, không cấp thêm quyền.' 'Overview: checks, licensing, investigation, Agent tasks and reports. A role changes the workspace, not permissions.'
    $layout.Controls.Add($note)
    $labels=@((Get-RoleText 'Tổng quan · Tất cả nhóm chức năng' 'Overview · All functional groups'),(Get-RoleText 'Cá nhân · Mở web cục bộ' 'Personal · Open local web'),'IT Helpdesk · Desktop','ITAM / SAM · Desktop')
    $roles=@('overview','personal','helpdesk','itam')
    for($i=0;$i -lt 4;$i++) {
        $button=New-Object Windows.Forms.Button
        $button.Size=New-Object Drawing.Size(550,48); $button.Text=$labels[$i]; $button.Tag=$roles[$i]
        $button.Add_Click({param($sender,$eventArgs) $sender.FindForm().Tag=[string]$sender.Tag; $sender.FindForm().Close()})
        $layout.Controls.Add($button)
    }
    [void]$chooser.ShowDialog($form); $selected=[string]$chooser.Tag; $chooser.Dispose()
    if (-not $selected) { return }
    $script:workspaceRole=$selected
    Set-DashboardSection -Section 'Overview'
    if ($selected -eq 'personal') {
        try { Open-PersonalRoleWorkspace }
        catch { [void][Windows.Forms.MessageBox]::Show((Get-RoleText 'Không mở được web cục bộ. Không thay đổi quyền hoặc kết nối mạng; dùng giao diện Windows.' 'Local web unavailable. No permission or network changes were made; use the desktop.'),'VietLicenSure') }
    }
}

function Initialize-RoleWorkspaces {
    if ($script:roleTimer) { return }
    $script:roleWorkspaceReady=$true; $script:workspaceRole='overview'
    $script:roleTaskStatus='idle'
    $script:roleButton=New-Object Windows.Forms.Button
    $script:roleButton.Text='Vai trò / Workspace'; $script:roleButton.Size=New-Object Drawing.Size(180,28)
    $script:roleButton.Top=4; $script:roleButton.Anchor='Top,Right'
    $script:roleButton.Left=[Math]::Max(0,$buttonPanel.ClientSize.Width-190)
    $script:roleButton.Add_Click({Show-RoleWorkspaceChooser})
    $buttonPanel.Controls.Add($script:roleButton); $script:roleButton.BringToFront()
    $buttonPanel.Add_SizeChanged({
        $menuCaption.Width=[Math]::Max(70,$buttonPanel.ClientSize.Width-220)
    })
    $script:roleTimer=New-Object Windows.Forms.Timer; $script:roleTimer.Interval=1000
    $script:roleTimer.Add_Tick({Update-PersonalWorkspace}); $script:roleTimer.Start()
    $form.Add_FormClosed({
        $script:roleTimer.Stop(); $script:roleTimer.Dispose()
        if($script:personalBridge){Stop-ToolPersonalWorkspace $script:personalBridge; $script:personalBridge=$null}
    })
    [void]$form.BeginInvoke([Action]{Show-RoleWorkspaceChooser})
}
