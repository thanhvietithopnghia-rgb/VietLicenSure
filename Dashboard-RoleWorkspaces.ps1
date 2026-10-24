# Roles are presentation preferences, never an authorization boundary.
function Get-RoleWorkspaceText([string]$Key) {
    return (Get-ToolText -Key ('roleWorkspace.' + $Key) -Culture $script:dashboardCulture)
}

function Test-RoleWorkspaceActionVisible {
    param([string]$Role, [string]$Kind, [int]$Number)
    if ($Role -notin @('personal','helpdesk','itam')) { return $false }
    if ($Kind -eq 'ReportAction') { return $true }
    switch ($Role) {
        'personal' { return ($Number -in @(1,2,3,4,5)) }
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

function Set-RoleWorkspaceButtonVisual {
    param(
        [Parameter(Mandatory=$true)][Windows.Forms.Button]$Button,
        [Parameter(Mandatory=$true)][ValidateSet('personal','helpdesk','itam')][string]$Role,
        [switch]$Selected
    )
    $accent = switch ($Role) {
        'personal' { [Drawing.Color]::FromArgb(21, 101, 192) }
        'helpdesk' { [Drawing.Color]::FromArgb(230, 81, 0) }
        'itam' { [Drawing.Color]::FromArgb(106, 27, 154) }
    }
    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderColor = $accent
    $Button.FlatAppearance.BorderSize = $(if ($Selected) { 3 } else { 1 })
    $Button.BackColor = $accent
    $Button.ForeColor = [Drawing.Color]::White
    $Button.Font = $fontBold
    $Button.UseVisualStyleBackColor = $false
}

function Update-RoleWorkspaceChrome {
    if (-not $script:roleButton) { return }
    $roleName = Get-RoleWorkspaceName $script:workspaceRole
    $script:roleButton.Text = [string]::Format((Get-RoleWorkspaceText 'buttonFormat'), @($roleName))
    $script:roleButton.AccessibleName = $script:roleButton.Text
    $script:roleButton.AccessibleDescription = Get-RoleWorkspaceText 'buttonDescription'
    $toolTip.SetToolTip($script:roleButton, $script:roleButton.AccessibleDescription)
    if ($script:workspaceRole -in @('personal','helpdesk','itam')) {
        Set-RoleWorkspaceButtonVisual -Button $script:roleButton -Role $script:workspaceRole -Selected
    }
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
    $roleChoiceButtons = New-Object Collections.Generic.List[Windows.Forms.Button]
    for($i=0;$i -lt 3;$i++) {
        $button=New-Object Windows.Forms.Button
        $button.Size=New-Object Drawing.Size(590,58); $button.Text=$labels[$i]; $button.Tag=$roles[$i]
        $button.TextAlign='MiddleLeft'; $button.Padding=New-Object Windows.Forms.Padding(12,0,12,0)
        $button.AccessibleName=$button.Text; $button.AccessibleDescription=$button.Text
        $button.Add_Click({param($sender,$eventArgs) $sender.FindForm().Tag=[string]$sender.Tag; $sender.FindForm().Close()})
        $roleChoiceButtons.Add($button)
        $layout.Controls.Add($button)
    }
    $chooser.Add_FormClosing({param($sender,$e) if([string]::IsNullOrWhiteSpace([string]$sender.Tag)){$e.Cancel=$true}})
    Set-ToolWindowTheme -Root $chooser -Mode $script:dashboardTheme
    foreach ($choiceButton in $roleChoiceButtons) {
        Set-RoleWorkspaceButtonVisual -Button $choiceButton -Role ([string]$choiceButton.Tag) -Selected:([string]$choiceButton.Tag -eq [string]$script:workspaceRole)
    }
    [void](Show-DashboardModalDialog -Dialog $chooser); $selected=[string]$chooser.Tag; $chooser.Dispose()
    if (-not $selected) { throw 'RoleWorkspaceSelectionRequired' }
    $form.SuspendLayout()
    try {
        $script:workspaceRole=$selected
        Update-RoleWorkspaceChrome
        Set-DashboardSection -Section 'Overview'
        if (Get-Command Update-SharedScanResultDisplay -ErrorAction SilentlyContinue) {
            [void](Update-SharedScanResultDisplay -Mode $(if ($script:sharedScanDisplayMode) { [string]$script:sharedScanDisplayMode } else { 'All' }))
        }
    } finally { $form.ResumeLayout($true) }
}

function Initialize-RoleWorkspaces {
    if ($script:roleButton) { return }
    $script:roleWorkspaceReady=$true; $script:workspaceRole='unselected'
    $script:roleButton=New-Object Windows.Forms.Button
    $script:roleButton.Size=New-Object Drawing.Size(240,32)
    $script:roleButton.Top=4; $script:roleButton.Anchor='Top,Right'
    $script:roleButton.Left=[Math]::Max(0,$buttonPanel.ClientSize.Width-250)
    $script:roleButton.Add_Click({Show-RoleWorkspaceChooser})
    $buttonPanel.Controls.Add($script:roleButton); $script:roleButton.BringToFront()
    $buttonPanel.Add_SizeChanged({
        $script:roleButton.Left=[Math]::Max(0,$buttonPanel.ClientSize.Width-250)
        $menuCaption.Width=[Math]::Max(70,$buttonPanel.ClientSize.Width-280)
    })
    Update-RoleWorkspaceChrome
    [void]$form.BeginInvoke([Action]{Show-RoleWorkspaceChooser})
}
