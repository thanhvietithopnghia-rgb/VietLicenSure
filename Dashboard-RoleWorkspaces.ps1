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
    $dark = [bool]($script:dashboardTheme -eq 'Dark')
    $accent = switch ($Role) {
        'personal' { [Drawing.Color]::FromArgb(48, 105, 170) }
        'helpdesk' { [Drawing.Color]::FromArgb(171, 97, 35) }
        'itam' { [Drawing.Color]::FromArgb(111, 77, 145) }
    }
    $selectedBack = if ($dark) {
        switch ($Role) {
            'personal' { [Drawing.Color]::FromArgb(31, 55, 82) }
            'helpdesk' { [Drawing.Color]::FromArgb(67, 48, 31) }
            'itam' { [Drawing.Color]::FromArgb(54, 43, 68) }
        }
    } else {
        switch ($Role) {
            'personal' { [Drawing.Color]::FromArgb(226, 236, 248) }
            'helpdesk' { [Drawing.Color]::FromArgb(249, 237, 225) }
            'itam' { [Drawing.Color]::FromArgb(239, 232, 247) }
        }
    }
    $idleBack = if ($dark) { [Drawing.Color]::FromArgb(38, 44, 57) } else { [Drawing.Color]::FromArgb(246, 248, 251) }
    $idleFore = if ($dark) {
        switch ($Role) {
            'personal' { [Drawing.Color]::FromArgb(155, 199, 246) }
            'helpdesk' { [Drawing.Color]::FromArgb(238, 186, 132) }
            'itam' { [Drawing.Color]::FromArgb(203, 174, 228) }
        }
    } else { $accent }
    $selectedFore = if ($dark) {
        switch ($Role) {
            'personal' { [Drawing.Color]::FromArgb(183, 214, 248) }
            'helpdesk' { [Drawing.Color]::FromArgb(244, 202, 160) }
            'itam' { [Drawing.Color]::FromArgb(216, 193, 238) }
        }
    } else {
        switch ($Role) {
            'personal' { [Drawing.Color]::FromArgb(32, 75, 125) }
            'helpdesk' { [Drawing.Color]::FromArgb(122, 62, 18) }
            'itam' { [Drawing.Color]::FromArgb(78, 48, 108) }
        }
    }
    if (Test-ToolUiHighContrast) {
        $accent = [Drawing.SystemColors]::Highlight
        $selectedBack = [Drawing.SystemColors]::Highlight
        $selectedFore = [Drawing.SystemColors]::HighlightText
        $idleBack = [Drawing.SystemColors]::Control
        $idleFore = [Drawing.SystemColors]::ControlText
    }
    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderColor = $accent
    $Button.FlatAppearance.BorderSize = $(if ($Selected) { 2 } else { 1 })
    $Button.FlatAppearance.MouseOverBackColor = $(if ($Selected) { $selectedBack } elseif ($dark) { [Drawing.Color]::FromArgb(48, 56, 72) } else { [Drawing.Color]::FromArgb(234, 239, 246) })
    $Button.FlatAppearance.MouseDownBackColor = $(if ($dark) { [Drawing.Color]::FromArgb(48, 56, 72) } else { [Drawing.Color]::FromArgb(218, 228, 240) })
    $Button.BackColor = $(if ($Selected) { $selectedBack } else { $idleBack })
    $Button.ForeColor = $(if ($Selected) { $selectedFore } else { $idleFore })
    $Button.Font = $fontBold
    $Button.UseVisualStyleBackColor = $false
}

function Update-RoleWorkspaceChrome {
    if (-not $script:roleButton) { return }
    $roleName = Get-RoleWorkspaceName $script:workspaceRole
    $fullRoleText = [string]::Format((Get-RoleWorkspaceText 'buttonFormat'), @($roleName))
    # The button already sits in the role header, so repeating the prefix can
    # clip the longer Business Inventory label at common DPI settings.
    $script:roleButton.Text = $roleName
    $script:roleButton.AccessibleName = $fullRoleText
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

function Update-RoleWorkspaceHeaderLayout {
    if (-not $script:roleButton -or -not $buttonPanel) { return }
    $clientWidth = [Math]::Max(1, $buttonPanel.ClientSize.Width)
    $verticalReserve = if ($buttonPanel.VerticalScroll.Visible -or
        $buttonPanel.AutoScrollMinSize.Height -gt $buttonPanel.ClientSize.Height) {
        [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth + 4
    } else { 4 }
    if ($clientWidth -lt 560) {
        # The role button replaces the duplicate caption in a narrow column.
        # Reserve the vertical scrollbar explicitly so AutoScroll never needs
        # to expose a horizontal scrollbar after the task list grows.
        $menuCaption.Visible = $false
        $script:roleButton.Left = 12
        $script:roleButton.Width = [Math]::Max(120, $clientWidth - $script:roleButton.Left - 12 - $verticalReserve)
    } else {
        $menuCaption.Visible = $true
        $script:roleButton.Width = 240
        $script:roleButton.Left = [Math]::Max(0, $clientWidth - $script:roleButton.Width - 12)
        $menuCaption.Width = [Math]::Max(70, $script:roleButton.Left - $menuCaption.Left - 10)
    }
    $currentVerticalOffset = [Math]::Abs($buttonPanel.AutoScrollPosition.Y)
    $buttonPanel.AutoScrollPosition = New-Object Drawing.Point(0, $currentVerticalOffset)
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
    } finally { $form.ResumeLayout($false) }
}

function Initialize-RoleWorkspaces {
    if ($script:roleButton) { return }
    $script:roleWorkspaceReady=$true; $script:workspaceRole='unselected'
    $script:roleButton=New-Object Windows.Forms.Button
    $script:roleButton.Size=New-Object Drawing.Size(240,32)
    $script:roleButton.Top=4; $script:roleButton.Anchor='Top,Left'
    $script:roleButton.Left=[Math]::Max(0,$buttonPanel.ClientSize.Width-250)
    $script:roleButton.Add_Click({Show-RoleWorkspaceChooser})
    $buttonPanel.Controls.Add($script:roleButton); $script:roleButton.BringToFront()
    $buttonPanel.Add_SizeChanged({ Update-RoleWorkspaceHeaderLayout })
    Update-RoleWorkspaceHeaderLayout
    Update-RoleWorkspaceChrome
    [void]$form.BeginInvoke([Action]{
        Show-RoleWorkspaceChooser
        if (-not $script:sharedScanDisplayInitialized -and $script:sharedScanStartupTimer) {
            $script:sharedScanDisplayInitialized = $true
            $script:sharedScanStartupTimer.Start()
        }
        if ($startupValidationTimer -and -not $startupValidationTimer.Enabled) {
            $startupValidationTimer.Interval = 15
            $startupValidationTimer.Start()
        }
    })
}
