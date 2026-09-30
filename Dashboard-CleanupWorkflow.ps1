# VietLicenSure v5.0 - dot-sourced function library
# Extracted mechanically from Giao-Dien.ps1; contains function definitions only.
# Keep this file beside its compatible entrypoint.

function Get-AutomaticSafeCleanupItems {
    param($CleanupItems)

    # Third-party licensing actions are always manual-selection only.  The
    # automatic path is limited to the Windows registry allowlist below.
    return @($CleanupItems | Where-Object {
        $type = [string]$_.Type
        $kind = [string]$_.Kind
        $path = [string]$_.Location
        ($type -eq "Registry" -and (
            ($kind -eq "KmsOverride" -and (Test-ToolRegistryValueRestoreAllowed -Path $path -ValueName "KeyManagementServiceName")) -or
            ($kind -eq "SppNoGenTicketPolicy" -and (Test-ToolRegistryValueRestoreAllowed -Path $path -ValueName "NoGenTicket"))
        ))
    })
}

function Confirm-AutomaticSafeCleanup {
    param($CleanupItems)

    $safeItems = @(Get-AutomaticSafeCleanupItems -CleanupItems $CleanupItems)
    if ($safeItems.Count -eq 0) {
        return [pscustomobject]@{ Confirmed=$false; SelectedIds=@(); SafeItemCount=0 }
    }

    $preview = @($safeItems | ForEach-Object {
        "- $([string]$_.Name)`r`n  $([string]$_.Location)`r`n  $([string]$_.Detail)"
    }) -join "`r`n"
    $message = Get-DashboardText "cleanup.auto.confirm" @($safeItems.Count, $preview)
    $answer = [System.Windows.Forms.MessageBox]::Show(
        $message,
        (Get-DashboardText "cleanup.auto.title"),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    return [pscustomobject]@{
        Confirmed = [bool]($answer -eq [System.Windows.Forms.DialogResult]::Yes)
        SelectedIds = @($safeItems | ForEach-Object { [string]$_.Id })
        SafeItemCount = [int]$safeItems.Count
    }
}

function Show-DeepCleanupSelection {
    param(
        $CleanupItems,
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")][string]$ScanScope = "All",
        [string[]]$SuggestedIds = @(),
        [switch]$RestoreExactSelection
    )
    $items = @(Get-GuiScopedCleanupItems -CleanupItems $CleanupItems -Scope $ScanScope)
    if ($items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "cleanup.selection.none"),
            (Get-DashboardText "cleanup.selection.noneTitle"), "OK", "Information") | Out-Null
        return [pscustomobject]@{ Confirmed=$false; SelectedIds=@(); ScanScope=$ScanScope; Navigation="Back" }
    }

    $chooser = New-Object System.Windows.Forms.Form
    $chooser.Text = Get-DashboardText "cleanup.selection.formTitle" @($toolDisplayVersion)
    $chooser.StartPosition = "CenterParent"
    $chooser.FormBorderStyle = "Sizable"
    $chooser.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(820, [Math]::Min(1280, $workArea.Width - 50))
    $dialogHeight = [Math]::Max(540, [Math]::Min(690, $workArea.Height - 70))
    $chooser.MinimumSize = New-Object System.Drawing.Size([Math]::Min(820, $dialogWidth), [Math]::Min(540, $dialogHeight))
    $chooser.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $chooser.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $chooser.Font = $fontNormal
    $chooser.Tag = [pscustomobject]@{ Confirmed=$false; SelectedIds=@($SuggestedIds); ScanScope=$ScanScope; Navigation="Close" }

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText $(if ($ScanScope -eq "ThirdParty") { "cleanup.selection.heading.thirdParty" } elseif ($ScanScope -eq "WindowsOffice") { "cleanup.selection.heading.windowsOffice" } else { "cleanup.selection.heading" })
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $heading.Location = New-Object System.Drawing.Point(18, 10)
    $heading.Size = New-Object System.Drawing.Size(($dialogWidth - 36), 42)
    $heading.Anchor = "Top,Left,Right"
    $chooser.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-DashboardText $(if ($ScanScope -eq "ThirdParty") { "cleanup.selection.hint.thirdParty" } elseif ($ScanScope -eq "WindowsOffice") { "cleanup.selection.hint.windowsOffice" } else { "cleanup.selection.hint" })
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.Location = New-Object System.Drawing.Point(22, 56)
    $hint.Size = New-Object System.Drawing.Size(($dialogWidth - 44), 50)
    $hint.Anchor = "Top,Left,Right"
    $chooser.Controls.Add($hint)

    $list = New-Object System.Windows.Forms.ListView
    $list.CheckBoxes = $true
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.HideSelection = $false
    $list.ShowItemToolTips = $true
    $list.Location = New-Object System.Drawing.Point(22, 112)
    $list.Size = New-Object System.Drawing.Size(($dialogWidth - 44), ($dialogHeight - 184))
    $list.Anchor = "Top,Bottom,Left,Right"
    [void]$list.Columns.Add((Get-DashboardText "common.type"), 132)
    [void]$list.Columns.Add((Get-DashboardText "common.name"), 320)
    [void]$list.Columns.Add((Get-DashboardText "common.locationDetail"), 580)
    $resizeCleanupColumns = {
        $usable = [Math]::Max(540, $list.ClientSize.Width - 8)
        $list.Columns[0].Width = 132
        $list.Columns[1].Width = [Math]::Max(260, [Math]::Floor(($usable - 132) * 0.44))
        $list.Columns[2].Width = [Math]::Max(260, $usable - $list.Columns[0].Width - $list.Columns[1].Width)
    }
    $list.Add_Resize($resizeCleanupColumns)
    $typeLabels = @{
        Service=(Get-DashboardText "cleanup.type.service"); ScheduledTask=(Get-DashboardText "cleanup.type.task"); Folder=(Get-DashboardText "cleanup.type.folder"); Registry=(Get-DashboardText "cleanup.type.registry")
        File=(Get-DashboardText "cleanup.type.file"); Process=(Get-DashboardText "cleanup.type.process"); Defender=(Get-DashboardText "cleanup.type.defender"); License=(Get-DashboardText "cleanup.type.license"); Application=(Get-DashboardText "cleanup.type.application")
        Hosts=(Get-DashboardText "cleanup.type.hosts"); Repair=(Get-DashboardText "cleanup.type.repair"); Uninstall=(Get-DashboardText "cleanup.type.uninstall"); Guidance=(Get-DashboardText "cleanup.type.guidance")
    }
    foreach ($cleanupItem in $items) {
        $typeText = if ($typeLabels.ContainsKey([string]$cleanupItem.Type)) { $typeLabels[[string]$cleanupItem.Type] } else { [string]$cleanupItem.Type }
        $row = New-Object System.Windows.Forms.ListViewItem($typeText)
        [void]$row.SubItems.Add([string]$cleanupItem.Name)
        $locationText = [string]$cleanupItem.Location
        if (-not [string]::IsNullOrWhiteSpace([string]$cleanupItem.Detail)) { $locationText += " - " + [string]$cleanupItem.Detail }
        [void]$row.SubItems.Add($locationText)
        $row.Tag = [string]$cleanupItem.Id
        $row.ToolTipText = "$([string]$cleanupItem.Name)`r`n$locationText"
        $row.Checked = if ($RestoreExactSelection) {
            [bool]($SuggestedIds -contains [string]$cleanupItem.Id)
        } else {
            [bool]($cleanupItem.DefaultSelected -or ($SuggestedIds -contains [string]$cleanupItem.Id))
        }
        [void]$list.Items.Add($row)
    }
    $chooser.Controls.Add($list)
    & $resizeCleanupColumns

    $buttonLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $buttonLayout.Location = New-Object System.Drawing.Point(22, ($dialogHeight - 60))
    $buttonLayout.Size = New-Object System.Drawing.Size(($dialogWidth - 44), 46)
    $buttonLayout.Anchor = "Bottom,Left,Right"
    $buttonLayout.ColumnCount = 2
    [void]$buttonLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$buttonLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    $chooser.Controls.Add($buttonLayout)

    $leftButtons = New-Object System.Windows.Forms.FlowLayoutPanel
    $leftButtons.Dock = "Fill"
    $leftButtons.WrapContents = $false
    $buttonLayout.Controls.Add($leftButtons, 0, 0)
    $rightButtons = New-Object System.Windows.Forms.FlowLayoutPanel
    $rightButtons.Dock = "Fill"
    $rightButtons.FlowDirection = "RightToLeft"
    $rightButtons.WrapContents = $false
    $buttonLayout.Controls.Add($rightButtons, 1, 0)

    $allButton = New-Object System.Windows.Forms.Button
    $allButton.Text = Get-DashboardText "common.selectAll"
    $allButton.Size = New-Object System.Drawing.Size(142, 36)
    $allButton.Add_Click({ foreach ($row in $list.Items) { $row.Checked = $true } })
    $leftButtons.Controls.Add($allButton)

    $noneButton = New-Object System.Windows.Forms.Button
    $noneButton.Text = Get-DashboardText "common.clearAll"
    $noneButton.Size = New-Object System.Drawing.Size(142, 36)
    $noneButton.Add_Click({ foreach ($row in $list.Items) { $row.Checked = $false } })
    $leftButtons.Controls.Add($noneButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = Get-DashboardText "common.close"
    $closeButton.Size = New-Object System.Drawing.Size(104, 36)
    $closeButton.Add_Click({
        $chooser.Tag = [pscustomobject]@{
            Confirmed=$false
            SelectedIds=@($list.CheckedItems | ForEach-Object { [string]$_.Tag })
            ScanScope=$ScanScope
            Navigation="Close"
        }
        Close-DashboardWorkflowSession -Dialog $chooser
    })
    $rightButtons.Controls.Add($closeButton)

    $backButton = New-Object System.Windows.Forms.Button
    $backButton.Text = Get-DashboardText "common.back"
    $backButton.Size = New-Object System.Drawing.Size(116, 36)
    $backButton.Add_Click({
        $chooser.Tag = [pscustomobject]@{
            Confirmed=$false
            SelectedIds=@($list.CheckedItems | ForEach-Object { [string]$_.Tag })
            ScanScope=$ScanScope
            Navigation="Back"
        }
        $chooser.Close()
    })
    $chooser.CancelButton = $backButton
    $rightButtons.Controls.Add($backButton)

    $applyButton = New-Object System.Windows.Forms.Button
    $applyButton.Text = Get-DashboardText "common.continue"
    $applyButton.Font = $fontBold
    $applyButton.Size = New-Object System.Drawing.Size(132, 36)
    $applyButton.Add_Click({
        $selectedIds = @($list.CheckedItems | ForEach-Object { [string]$_.Tag })
        if ($selectedIds.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                (Get-DashboardText "cleanup.selection.required"),
                (Get-DashboardText "cleanup.selection.requiredTitle"), "OK", "Warning") | Out-Null
            return
        }
        $selectedObjects = @($items | Where-Object { $selectedIds -contains [string]$_.Id })
        $licenseCount = @($selectedObjects | Where-Object { $_.Type -eq "License" }).Count
        # Guidance-only application rows are deliberately counted separately:
        # the artifact warning must never imply that selecting a vendor repair
        # guide will quarantine or alter that application.
        $applicationCount = @($selectedObjects | Where-Object {
            [string]$_.Type -eq 'Application' -and
            -not ($_.PSObject.Properties['GuidanceOnly'] -and [bool]$_.GuidanceOnly)
        }).Count
        $guidanceCount = @($selectedObjects | Where-Object {
            [string]$_.Type -eq 'Guidance' -or
            ($_.PSObject.Properties['GuidanceOnly'] -and [bool]$_.GuidanceOnly)
        }).Count
        $licenseWarning = if ($licenseCount -gt 0) { Get-DashboardText "cleanup.selection.licenseWarning" @($licenseCount) } else { "" }
        if ($applicationCount -gt 0) { $licenseWarning += Get-DashboardText "cleanup.selection.applicationWarning" @($applicationCount) }
        if ($guidanceCount -gt 0) { $licenseWarning += Get-DashboardText "cleanup.selection.guidanceWarning" @($guidanceCount) }
        $summary = Get-DashboardText "cleanup.selection.summary" @($selectedIds.Count, $list.Items.Count, $licenseWarning)
        $answer = [System.Windows.Forms.MessageBox]::Show($summary, (Get-DashboardText "cleanup.selection.finalTitle"), "YesNo", "Warning")
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            $chooser.Tag = [pscustomobject]@{ Confirmed=$true; SelectedIds=$selectedIds; ScanScope=$ScanScope; Navigation="Continue" }
            $chooser.Close()
        }
    })
    $rightButtons.Controls.Add($applyButton)

    Set-ToolWindowTheme -Root $chooser -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $chooser)
    $result = $chooser.Tag
    $chooser.Dispose()
    return $result
}

function Start-CleanupDeep {
    param(
        $CleanupItems,
        [switch]$AutomaticSafeMode,
        [string[]]$SuggestedIds = @(),
        [switch]$RestoreExactSelection,
        [switch]$ReturnNavigationResult
    )
    $scopedCleanupItems = @(Get-GuiScopedCleanupItems -CleanupItems $CleanupItems -Scope $script:cleanupScanScope)
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "cleanup.deep.integrityAction"))) {
        $script:cleanupAutoSafeMode = $false
        Set-ButtonsEnabled $true
        if ($ReturnNavigationResult) { return "Blocked" }
        return
    }
    # A selection made in the software assessment window is already an exact
    # user decision.  Do not merge it with DefaultSelected rows in the final
    # review, otherwise choosing one application appears to select the whole
    # cleanup scope.
    $useExactSuggestedSelection = [bool]($RestoreExactSelection -or
        (-not $AutomaticSafeMode -and @($SuggestedIds).Count -gt 0))
    $selection = if ($AutomaticSafeMode) {
        Confirm-AutomaticSafeCleanup -CleanupItems $scopedCleanupItems
    } else {
        Show-DeepCleanupSelection -CleanupItems $scopedCleanupItems -ScanScope $script:cleanupScanScope -SuggestedIds $SuggestedIds -RestoreExactSelection:$useExactSuggestedSelection
    }
    if (-not [bool]$selection.Confirmed) {
        $script:cleanupAutoSafeMode = $false
        $script:cleanupDryRunMode = $false
        Set-ButtonsEnabled $true
        $status.Text = if ($AutomaticSafeMode) { Get-DashboardText "cleanup.auto.cancelled" } else { Get-DashboardText "cleanup.deep.cancelled" }
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Write-ProgressLog $status.Text
        if ($ReturnNavigationResult) {
            if ($selection.PSObject.Properties['Navigation'] -and [string]$selection.Navigation -in @("Back", "Close")) {
                return [string]$selection.Navigation
            }
            return $(if ($AutomaticSafeMode) { "Close" } else { "Back" })
        }
        return
    }

    # Retain only the user's workflow choices.  Candidate objects and their
    # anti-TOCTOU snapshot are deliberately not cached here: after a real
    # remediation the result's fresh post-verification snapshot is the only
    # safe source that Back may use.
    $script:cleanupPreviousSession = [pscustomobject][ordered]@{
        Kind = "DeepCleanupSelection"
        ScanScope = [string]$script:cleanupScanScope
        SelectedIds = @($selection.SelectedIds | ForEach-Object { [string]$_ })
        DryRunMode = [bool]$script:cleanupDryRunMode
        AutomaticSafeMode = [bool]$AutomaticSafeMode
        CreatedAtUtc = [DateTimeOffset]::UtcNow.ToString("o")
    }
    try {
        Start-ProgressDisplay (Get-DashboardText "cleanup.deep.action") (Get-DashboardText "cleanup.deep.preparing") $true
        $selectionMode = if ($AutomaticSafeMode) { Get-DashboardText "cleanup.mode.automatic" } else { Get-DashboardText "cleanup.mode.manual" }
        Write-ProgressLog (Get-DashboardText "cleanup.deep.selected" @(@($selection.SelectedIds).Count, $selectionMode))
        Write-ProgressLog (Get-DashboardText "cleanup.deep.scopeNote")
        $output = New-ToolReportRunDirectory -Category "KhacPhuc-XuLy"
        $script:cleanupResultFile = New-SecureRuntimePath "tool-license-deep-clean-result-"
        $script:cleanupSelectionFile = New-SecureRuntimePath "tool-license-deep-selection-"
        if ($null -eq $script:cleanupScanSnapshot -or
            [string]$script:cleanupScanSnapshot.SnapshotId -notmatch '^[0-9a-fA-F-]{36}$' -or
            [string]$script:cleanupScanSnapshot.CandidateSetSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            throw (Get-DashboardText 'cleanup.selection.sourceSnapshotMissing')
        }
        $selectedCandidateSnapshots = @($scopedCleanupItems | Where-Object {
            @($selection.SelectedIds) -contains [string]$_.Id
        } | ForEach-Object {
            if (-not $_.PSObject.Properties['SnapshotSha256'] -or [string]$_.SnapshotSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
                throw (Get-DashboardText 'cleanup.selection.snapshotMissing' @([string]$_.Name))
            }
            [pscustomobject][ordered]@{
                Id=([string]$_.Id).ToLowerInvariant()
                SnapshotSha256=([string]$_.SnapshotSha256).ToUpperInvariant()
            }
        })
        if ($selectedCandidateSnapshots.Count -ne @($selection.SelectedIds).Count) {
            throw (Get-DashboardText 'cleanup.selection.snapshotCountMismatch')
        }
        [pscustomobject][ordered]@{
            SchemaVersion='1.1'
            RequestId=[guid]::NewGuid().ToString('D')
            CreatedAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
            SourceSnapshotId=[string]$script:cleanupScanSnapshot.SnapshotId
            SourceCandidateSetSha256=([string]$script:cleanupScanSnapshot.CandidateSetSha256).ToUpperInvariant()
            SelectedCandidates=@($selectedCandidateSnapshots)
            ScanScope=$script:cleanupScanScope
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:cleanupSelectionFile -Encoding UTF8
        $privacyArgument = if ($script:cleanupRedactSensitive) { " -RedactSensitive" } else { "" }
        $dryRunArgument = if ($script:cleanupDryRunMode) { " -DryRun" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$cleanupScript`" -OutputDir `"$output`" -Remediate -DeepClean$dryRunArgument -ApprovedKmsServerFile `"$approvedKmsFile`" -TreatUnapprovedKmsAsNonCompliant -DecisionFile `"$script:cleanupResultFile`" -SelectionFile `"$script:cleanupSelectionFile`" -ScanScope `"$script:cleanupScanScope`" -Culture `"$script:dashboardCulture`"$privacyArgument"
        $actionText = if ($script:cleanupDryRunMode) { Get-DashboardText 'cleanup.dryRun.action' } else { Get-DashboardText "cleanup.deep.action" }
        [void](Start-ToolModuleProcess -ModuleId "cleanup.deep" -Arguments $arguments -Action $actionText -Elevate)
        # Open a modeless, dedicated table for this run.  The dashboard's
        # "Recent activity" panel keeps receiving the same entries; the table
        # is an additional detailed view and does not replace or block it.
        try {
            Show-ProcessingTimelineWindow -Action $actionText
        } catch {
            Write-ProgressLog (Get-DashboardText 'processingTimeline.openFailed' @($_.Exception.Message))
        }
        $status.Text = if ($script:cleanupDryRunMode) { Get-DashboardText 'cleanup.dryRun.running' } else { Get-DashboardText "cleanup.deep.running" }
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-ButtonsEnabled $false
        $timer.Start()
        if ($ReturnNavigationResult) { return "Started" }
    } catch {
        $script:cleanupAutoSafeMode = $false
        $script:cleanupDryRunMode = $false
        if ($script:cleanupSelectionFile -and (Test-Path -LiteralPath $script:cleanupSelectionFile)) {
            Remove-Item -LiteralPath $script:cleanupSelectionFile -Force -ErrorAction SilentlyContinue
        }
        $script:cleanupSelectionFile = ""
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "cleanup.deep.elevationCancelled"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog (Get-DashboardText "cleanup.deep.notStarted")
        Stop-ProgressDisplay $status.Text
        if ($ReturnNavigationResult) { return "Failed" }
    }
}

function Show-ScanWarningRecoveryDialog {
    param($Scan)
    $warningLines = @($Scan.ScanWarnings | ForEach-Object { "- $_" })
    $warningText = if ($warningLines.Count -gt 0) { $warningLines -join "`r`n" } else { Get-DashboardText "scanWarning.noDetail" }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.Text = Get-DashboardText "scanWarning.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MinimumSize = New-Object System.Drawing.Size(700, 430)
    $dialog.ClientSize = New-Object System.Drawing.Size(760, 460)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Font = $fontNormal
    $dialog.Tag = "Close"

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "scanWarning.heading"
    $heading.Font = $fontBold
    $heading.ForeColor = [System.Drawing.Color]::DarkRed
    $heading.Location = New-Object System.Drawing.Point(18, 14)
    $heading.Size = New-Object System.Drawing.Size(706, 28)
    $heading.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($heading)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = Get-DashboardText "scanWarning.intro"
    $intro.Location = New-Object System.Drawing.Point(18, 48)
    $intro.Size = New-Object System.Drawing.Size(706, 56)
    $intro.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($intro)

    $warnings = New-Object System.Windows.Forms.TextBox
    $warnings.Multiline = $true
    $warnings.ReadOnly = $true
    $warnings.ScrollBars = "Vertical"
    $warnings.WordWrap = $true
    $warnings.Text = $warningText
    $warnings.Location = New-Object System.Drawing.Point(18, 110)
    $warnings.Size = New-Object System.Drawing.Size(706, 230)
    $warnings.Anchor = "Top,Bottom,Left,Right"
    $dialog.Controls.Add($warnings)

    $repairButton = New-Object System.Windows.Forms.Button
    $repairButton.Text = Get-DashboardText "scanWarning.repair"
    $repairButton.Font = $fontBold
    $repairButton.Location = New-Object System.Drawing.Point(274, 368)
    $repairButton.Size = New-Object System.Drawing.Size(200, 38)
    $repairButton.Anchor = "Bottom,Right"
    $repairButton.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 230)
    $repairButton.Add_Click({ $dialog.Tag = "Repair"; $dialog.Close() })
    $dialog.Controls.Add($repairButton)

    $retryButton = New-Object System.Windows.Forms.Button
    $retryButton.Text = Get-DashboardText "common.rescan"
    $retryButton.Location = New-Object System.Drawing.Point(484, 368)
    $retryButton.Size = New-Object System.Drawing.Size(120, 38)
    $retryButton.Anchor = "Bottom,Right"
    $retryButton.Add_Click({ $dialog.Tag = "Retry"; $dialog.Close() })
    $dialog.Controls.Add($retryButton)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-DashboardText "common.close"
    $close.Location = New-Object System.Drawing.Point(614, 368)
    $close.Size = New-Object System.Drawing.Size(110, 38)
    $close.Anchor = "Bottom,Right"
    $close.Add_Click({ $dialog.Tag = "Close"; Close-DashboardWorkflowSession -Dialog $dialog })
    $dialog.CancelButton = $close
    $dialog.Controls.Add($close)

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Start-ScanSourceRepair {
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "scanRepair.integrityAction"))) { Set-ButtonsEnabled $true; return }
    try {
        Start-ProgressDisplay (Get-DashboardText "scanRepair.action") (Get-DashboardText "scanRepair.detail") $true
        Write-ProgressLog (Get-DashboardText "scanRepair.requestAdmin")
        $output = New-ToolReportRunDirectory -Category "KhacPhuc-NguonQuet"
        $script:cleanupRepairDecisionFile = New-SecureRuntimePath "tool-scan-source-repair-"
        $privacyArgument = if ($script:cleanupRedactSensitive) { " -RedactSensitive" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$cleanupScript`" -OutputDir `"$output`" -RepairScanSources -DecisionFile `"$script:cleanupRepairDecisionFile`" -Culture `"$script:dashboardCulture`"$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "cleanup.repair" -Arguments $arguments -Action (Get-DashboardText "scanRepair.action") -Elevate)
        $status.Text = Get-DashboardText "scanRepair.running"
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-DashboardText "scanRepair.startFailed" @($_.Exception.Message))
    }
}

function Complete-ScanSourceRepair {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:cleanupRepairDecisionFile -PathType Leaf)) {
            if ($script:lastModuleResult -and
                [string]$script:lastModuleResult.ModuleId -eq 'cleanup.repair' -and
                [int]$script:lastModuleResult.ExitCode -ne 0) {
                throw (Get-DashboardText "scanRepair.processFailed" @([int]$script:lastModuleResult.ExitCode))
            }
            throw (Get-DashboardText "scanRepair.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:cleanupRepairDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:cleanupRepairDecisionFile -Force -ErrorAction SilentlyContinue
        $script:cleanupRepairDecisionFile = ""
        $beforeState = @($result.ServiceStateBefore) | ConvertTo-Json -Depth 5 -Compress
        $afterState = @($result.ServiceStateAfter) | ConvertTo-Json -Depth 5 -Compress
        $serviceStateChanged = [bool]($beforeState -ne $afterState -and -not [bool]$result.RollbackApplied)
        [void](Write-LicenseTimelineEventSafe -EventType "ScanSourceRepairCompleted" -Source "GUI" -IsChange:$serviceStateChanged -Data ([ordered]@{
            RecheckPassed=[bool]$result.RecheckPassed
            ServiceStateChanged=$serviceStateChanged
            StartupTypeChanged=[bool]$result.StartupTypeChanged
            RollbackApplied=[bool]$result.RollbackApplied
        }))
        $checkLines = @($result.Checks | ForEach-Object { "- [$($_.Status)] $($_.Name): $($_.Detail)" })
        $guidanceLines = @($result.HandlingGuidance | ForEach-Object { "- $_" })
        $resultLabel = if ([bool]$result.RecheckPassed) { Get-DashboardText "common.pass" } else { Get-DashboardText "common.fail" }
        $message = Get-DashboardText "scanRepair.resultSummary" @($resultLabel, ($checkLines -join "`r`n"), ($guidanceLines -join "`r`n"), $result.ReportPath)
        if ([bool]$result.RecheckPassed) {
            $answer = [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "scanRepair.retryPrompt" @($message)), (Get-DashboardText "scanRepair.readyTitle"), "YesNo", "Information")
            $status.Text = Get-DashboardText "scanRepair.readyStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
            Write-ProgressLog (Get-DashboardText "scanRepair.passLog")
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { Start-Cleanup -ReuseSessionSettings }
        } else {
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "scanRepair.errorTitle"), "OK", "Warning") | Out-Null
            $status.Text = Get-DashboardText "scanRepair.errorStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog (Get-DashboardText "scanRepair.errorLog")
        }
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            Register-ToolReportPath -Path ([string]$result.ReportPath)
            Write-ProgressLog (Get-DashboardText "cleanup.report.readyOnDemand" @($result.ReportPath))
        }
    } catch {
        if ($script:cleanupRepairDecisionFile -and (Test-Path -LiteralPath $script:cleanupRepairDecisionFile -PathType Leaf)) {
            Remove-Item -LiteralPath $script:cleanupRepairDecisionFile -Force -ErrorAction SilentlyContinue
        }
        $script:cleanupRepairDecisionFile = ""
        $status.Text = Get-DashboardText "scanRepair.readFailed" @($_.Exception.Message)
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
    }
}

function Test-GuiThirdPartyCleanupFinding {
    param($Application)
    if (-not $Application) { return $false }
    if ($Application.PSObject.Properties['CleanupFinding']) { return [bool]$Application.CleanupFinding }
    return [bool]([string]$Application.AssessmentCode -in @('NonGenuine','Suspicious','IntegrityCompromised'))
}

function Test-GuiSystemComponent {
    param($Application)

    # The final assessment owns this classification.  Do not infer it from a
    # product being free, paid, a runtime, its publisher, or its name: that
    # would put user applications such as PC-NVR in the wrong view.
    return [bool]($Application -and (
        ($Application.PSObject.Properties['IsSystemComponent'] -and [bool]$Application.IsSystemComponent) -or
        ($Application.PSObject.Properties['IsCompanionComponent'] -and [bool]$Application.IsCompanionComponent)))
}

function Test-GuiThirdPartyDirectRemediationEvidence {
    param($Application)

    if (-not (Test-GuiThirdPartyCleanupFinding -Application $Application)) { return $false }
    if (-not $Application.PSObject.Properties['CleanupCandidateId'] -or
        -not $Application.PSObject.Properties['RemediationSupported']) { return $false }
    $hasCandidate = [bool](-not [string]::IsNullOrWhiteSpace([string]$Application.CleanupCandidateId) -and
        [bool]$Application.RemediationSupported)
    if (-not $hasCandidate) { return $false }
    if ($Application.PSObject.Properties['StandaloneArtifact'] -and [bool]$Application.StandaloneArtifact) {
        return [bool]($Application.PSObject.Properties['ArtifactCleanupAllowed'] -and [bool]$Application.ArtifactCleanupAllowed -and
            $Application.PSObject.Properties['CleanupArtifactCleanupAllowed'] -and [bool]$Application.CleanupArtifactCleanupAllowed)
    }
    $manualArtifactQuarantine = [bool](
        $Application.PSObject.Properties['ManualArtifactQuarantineAllowed'] -and [bool]$Application.ManualArtifactQuarantineAllowed -and
        $Application.PSObject.Properties['CleanupManualArtifactQuarantineOnly'] -and [bool]$Application.CleanupManualArtifactQuarantineOnly -and
        $Application.PSObject.Properties['LicenseTechnicalState'] -and [string]$Application.LicenseTechnicalState -eq 'Suspicious'
    )
    if ($manualArtifactQuarantine) {
        return [bool]($Application.PSObject.Properties['CleanupArtifactCleanupAllowed'] -and [bool]$Application.CleanupArtifactCleanupAllowed)
    }
    if (-not ($Application.PSObject.Properties['LicenseTechnicalState'] -and [string]$Application.LicenseTechnicalState -eq 'CrackConfirmed')) { return $false }
    if (-not ($Application.PSObject.Properties['ArtifactCleanupAllowed'] -and [bool]$Application.ArtifactCleanupAllowed)) { return $false }
    return [bool]($Application.PSObject.Properties['CleanupArtifactCleanupAllowed'] -and [bool]$Application.CleanupArtifactCleanupAllowed)
}

function Test-GuiThirdPartySelectionAllowed {
    param($Application)

    if (Test-GuiThirdPartyDirectRemediationEvidence -Application $Application) { return $true }
    if (-not ($Application.PSObject.Properties['CleanupCandidateId'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Application.CleanupCandidateId))) { return $false }
    return [bool](
        $Application.PSObject.Properties['GuidedRemediationSupported'] -and [bool]$Application.GuidedRemediationSupported -and
        $Application.PSObject.Properties['CleanupGuidanceOnly'] -and [bool]$Application.CleanupGuidanceOnly
    )
}

function Get-GuiThirdPartyCleanupFindings {
    param($Applications)
    return @($Applications | Where-Object { Test-GuiThirdPartyCleanupFinding -Application $_ })
}

function Get-GuiThirdPartyDisplayStatus {
    param($Application)

    if (-not $Application) { return Get-DashboardText 'software.results.status.noIssue' }
    $assessmentCode = [string]$Application.AssessmentCode
    $licenseModel = if ($Application.PSObject.Properties['LicenseModel']) { [string]$Application.LicenseModel } else { '' }
    # The main list never treats an unverified commercial entitlement as "no
    # issue".  It asks for a licence check without claiming that the software
    # is illegal.  A confirmed direct finding remains a clear finding.
    if ($assessmentCode -eq 'NonGenuine') { return Get-DashboardText 'software.results.status.clearFinding' }
    if ($assessmentCode -eq 'Unactivated') { return Get-DashboardText 'software.results.status.notActivated' }
    if ($licenseModel -in @('Paid','Subscription','Trial') -and $assessmentCode -ne 'GenuineVerified') {
        return Get-DashboardText 'software.results.status.commercialReview'
    }
    if ($assessmentCode -in @('Suspicious','IntegrityCompromised')) {
        return Get-DashboardText 'software.results.status.reviewOnly'
    }
    if ($licenseModel -eq 'Unknown' -and $assessmentCode -in @('Unverified','TrialOrUnverified','')) {
        return Get-DashboardText 'software.results.status.unknownReview'
    }
    return Get-DashboardText 'software.results.status.noIssue'
}

function Get-GuiThirdPartyStandaloneCleanupRows {
    param($Candidates)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($Candidates | Where-Object {
        @($_.ApplicationIds).Count -eq 0 -and
        @($_.PlanItems | Where-Object { [string]$_.Type -eq 'File' -and [string]$_.Kind -eq 'ThirdPartyUnauthorizedArtifact' }).Count -gt 0
    })) {
        $rows.Add([pscustomobject][ordered]@{
            Id=('standalone:' + [string]$candidate.Id); Name=[string]$candidate.Name; Version=''; Publisher=''
            LicenseModel='Unknown'; AssessmentCode='Suspicious'; TechnicalStatus=(Get-DashboardText 'report.software.status.suspicious')
            Confidence='Medium'; AttentionLevel='High'; AssessmentSortPriority=0; Evidence=@($candidate.Evidence); NeedsReview=$true; CleanupFinding=$true
            IsSystemComponent=$false; SystemComponentReason=''
            RemediationSupported=$true; CleanupCandidateId=[string]$candidate.Id
            CleanupRemediationMode=[string]$candidate.RemediationMode; OfficialReferenceUrl=''
            StandaloneArtifact=$true; LicenseTechnicalState='ArtifactConfirmed'
            ArtifactCleanupAllowed=[bool]$candidate.ArtifactCleanupAllowed
            CleanupArtifactCleanupAllowed=[bool]$candidate.ArtifactCleanupAllowed
            CleanupLicenseStateResetAllowed=[bool]$candidate.LicenseStateResetAllowed
            RecoveryMode=[string]$candidate.RecoveryMode
        })
    }
    return $rows.ToArray()
}

function Get-GuiScanIntegerProperty {
    param($Scan, [string]$Name, [int]$Default = 0)

    if (-not $Scan -or -not $Scan.PSObject.Properties[$Name]) { return $Default }
    $value = 0
    if ([int]::TryParse([string]$Scan.PSObject.Properties[$Name].Value, [ref]$value)) { return $value }
    return $Default
}

function Get-GuiCleanupComponentLicenseState {
    param(
        $Scan,
        [ValidateSet('Windows','Office')][string]$Component
    )

    if (-not $Scan -or -not $Scan.PSObject.Properties['OfficialLicensePostCheck']) { return 'Unverified' }
    $postCheck = $Scan.PSObject.Properties['OfficialLicensePostCheck'].Value
    if (-not $postCheck -or -not $postCheck.PSObject.Properties[$Component]) { return 'Unverified' }
    $componentResult = $postCheck.PSObject.Properties[$Component].Value
    if ($componentResult -and $componentResult.PSObject.Properties['StateCode'] -and
        -not [string]::IsNullOrWhiteSpace([string]$componentResult.StateCode)) {
        return [string]$componentResult.StateCode
    }
    return 'Unverified'
}

function Get-GuiCleanupLicenseStateLabel {
    param([string]$StateCode)

    $key = switch ($StateCode) {
        'Licensed' { 'cleanup.scan.state.licensed' }
        'Unactivated' { 'cleanup.scan.state.unactivated' }
        'NeedsRepair' { 'cleanup.scan.state.needsRepair' }
        'NotDetected' { 'cleanup.scan.state.notDetected' }
        'NotScanned' { 'cleanup.scan.state.notScanned' }
        'CrackEvidencePresent' { 'cleanup.scan.state.crackEvidence' }
        'ActivationRequired' { 'cleanup.scan.state.activationRequired' }
        default { 'cleanup.scan.state.unverified' }
    }
    return Get-DashboardText $key
}

function Get-GuiCleanupComponentStatusLines {
    param(
        $Scan,
        [ValidateSet('All','Windows','Office','ThirdParty','WindowsOffice','WindowsThirdParty','OfficeThirdParty')][string]$Scope
    )

    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-GuiCleanupScopeIncludes -Scope $Scope -Component 'Windows') {
        $lines.Add((Get-DashboardText 'cleanup.scan.component.windows' @(
            (Get-GuiCleanupLicenseStateLabel (Get-GuiCleanupComponentLicenseState -Scan $Scan -Component 'Windows')),
            (Get-GuiScanIntegerProperty -Scan $Scan -Name 'WindowsKmsCount'))))
    }
    if (Test-GuiCleanupScopeIncludes -Scope $Scope -Component 'Office') {
        $lines.Add((Get-DashboardText 'cleanup.scan.component.office' @(
            (Get-GuiCleanupLicenseStateLabel (Get-GuiCleanupComponentLicenseState -Scan $Scan -Component 'Office')),
            (Get-GuiScanIntegerProperty -Scan $Scan -Name 'OfficeKmsCount'))))
    }
    if (Test-GuiCleanupScopeIncludes -Scope $Scope -Component 'ThirdParty') {
        $lines.Add((Get-DashboardText 'cleanup.scan.component.thirdParty' @(
            (Get-GuiScanIntegerProperty -Scan $Scan -Name 'ThirdPartyApplicationCount'),
            (Get-GuiScanIntegerProperty -Scan $Scan -Name 'ThirdPartyRemediationFindingCount'))))
    }
    if ($lines.Count -eq 0) { $lines.Add((Get-DashboardText 'cleanup.scan.component.none')) }
    return $lines.ToArray()
}

function Get-GuiCleanupNoFindingMessage {
    param(
        $Scan,
        [ValidateSet('All','Windows','Office','ThirdParty','WindowsOffice','WindowsThirdParty','OfficeThirdParty')][string]$Scope
    )

    $conclusion = if ($Scan -and $Scan.PSObject.Properties['CleanupConclusion'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Scan.CleanupConclusion)) {
        [string]$Scan.CleanupConclusion
    } else {
        Get-DashboardText 'common.unknown'
    }
    return Get-DashboardText 'cleanup.scan.noFindingResult' @(
        (Get-CleanupScopeLabel -Scope $Scope),
        (@(Get-GuiCleanupComponentStatusLines -Scan $Scan -Scope $Scope) -join "`r`n"),
        (Get-GuiScanIntegerProperty -Scan $Scan -Name 'HistoryFindingCount'),
        $conclusion)
}

function Show-ThirdPartyAssessmentResults {
    param(
        $Scan,
        [switch]$ReadOnly,
        [string[]]$Warnings = @(),
        [string[]]$SelectedCandidateIds = @()
    )

    $inventoryApplications = @($Scan.ThirdPartyApplications)
    $standaloneRows = @(Get-GuiThirdPartyStandaloneCleanupRows -Candidates @($Scan.ThirdPartyCandidates))
    $allApplications = @($inventoryApplications) + @($standaloneRows)
    $sortProperties = @(
        @{ Expression = { if ($_.PSObject.Properties['AssessmentSortPriority']) { [int]$_.AssessmentSortPriority } else { 500 } }; Ascending = $true }
        @{ Expression = { if (Test-GuiThirdPartyDirectRemediationEvidence -Application $_) { 0 } elseif (Test-GuiThirdPartySelectionAllowed -Application $_) { 1 } else { 2 } }; Ascending = $true }
        @{ Expression = { [string]$_.Name }; Ascending = $true }
        @{ Expression = { [string]$_.Publisher }; Ascending = $true }
    )
    $applications = @($allApplications | Sort-Object -Property $sortProperties)
    # Do not treat free software as a system component.  The final assessment's
    # IsSystemComponent field is the only source of truth for this split.
    $thirdPartyApplications = @($applications | Where-Object { -not (Test-GuiSystemComponent -Application $_) })
    # System components remain available in the internal inventory/report but
    # are intentionally omitted from this user-action dialog.  They must never
    # be offered as software to review, select or remediate.
    $systemComponentCount = @($applications | Where-Object { Test-GuiSystemComponent -Application $_ }).Count
    $actionableCount = @($thirdPartyApplications | Where-Object { Test-GuiThirdPartyDirectRemediationEvidence -Application $_ }).Count
    $selectableCount = @($thirdPartyApplications | Where-Object { Test-GuiThirdPartySelectionAllowed -Application $_ }).Count
    $confirmedFindingCount = @($thirdPartyApplications | Where-Object { Test-GuiThirdPartyDirectRemediationEvidence -Application $_ }).Count
    $reviewFindingCount = @($thirdPartyApplications | Where-Object {
        -not (Test-GuiThirdPartyDirectRemediationEvidence -Application $_) -and
        ((Test-GuiThirdPartySelectionAllowed -Application $_) -or
            ($_.PSObject.Properties['NeedsReview'] -and [bool]$_.NeedsReview) -or
            [string]$_.AssessmentCode -in @('NonGenuine','Suspicious','IntegrityCompromised','Unverified','TrialOrUnverified'))
    }).Count
    $noIssueCount = [Math]::Max(0, [int]$thirdPartyApplications.Count - [int]$confirmedFindingCount - [int]$reviewFindingCount)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "software.results.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.MaximizeBox = $true
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(660, [Math]::Min(1460, $workArea.Width - 36))
    $dialogHeight = [Math]::Max(560, [Math]::Min(820, $workArea.Height - 54))
    $dialog.MinimumSize = New-Object System.Drawing.Size(660, 560)
    $dialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Font = $fontNormal
    $dialog.Tag = [pscustomobject]@{ Proceed=$false; SelectedCandidateIds=@($SelectedCandidateIds); RepairSources=$false; Back=$false; Navigation="Close" }

    $mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $mainLayout.Dock = "Fill"
    $mainLayout.Padding = New-Object System.Windows.Forms.Padding(18)
    $mainLayout.ColumnCount = 1
    $mainLayout.RowCount = 6
    [void]$mainLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 112)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $dialog.Controls.Add($mainLayout)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText $(if ($ReadOnly) { "software.results.heading.readOnly" } else { "software.results.heading" })
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.AutoSize = $true
    $heading.AutoEllipsis = $false
    $heading.UseMnemonic = $false
    $heading.MaximumSize = New-Object System.Drawing.Size(([Math]::Max(120, $dialogWidth - 54)), 0)
    $heading.TextAlign = "MiddleCenter"
    $heading.Dock = "Top"
    $mainLayout.Controls.Add($heading, 0, 0)

    $summary = New-Object System.Windows.Forms.Label
    $summary.Text = Get-DashboardText "software.results.summary" @(
        $thirdPartyApplications.Count,
        $selectableCount,
        $actionableCount,
        $confirmedFindingCount,
        $reviewFindingCount,
        $noIssueCount,
        $systemComponentCount)
    $summary.Font = $fontBold
    $summary.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $summary.AutoSize = $true
    $summary.AutoEllipsis = $false
    $summary.UseMnemonic = $false
    $summary.MaximumSize = New-Object System.Drawing.Size(([Math]::Max(120, $dialogWidth - 54)), 0)
    $summary.Dock = "Top"
    $mainLayout.Controls.Add($summary, 0, 1)

    $hint = New-Object System.Windows.Forms.Label
    $hintKey = if ($ReadOnly) {
        "software.results.hint.readOnly"
    } elseif ($thirdPartyApplications.Count -eq 0) {
        "software.results.noApplications"
    } elseif ($selectableCount -eq 0) {
        "software.results.hint.noSelectable"
    } else {
        "software.results.hint"
    }
    $hint.Text = (Get-DashboardText "software.results.scopeNote") + "`r`n" + (Get-DashboardText $hintKey)
    if ($ReadOnly -and @($Warnings).Count -gt 0) {
        $hint.Text = (Get-DashboardText 'software.results.hint.scanWarning' @((@($Warnings | Select-Object -First 3) -join '; '))) + "`r`n" + $hint.Text
    }
    if ($Scan.PSObject.Properties['DeepSoftwareScanEnabled'] -and [bool]$Scan.DeepSoftwareScanEnabled) {
        $deepCompleteText = Get-DashboardText $(if ([bool]$Scan.DeepSoftwareScanComplete) { 'common.yes' } else { 'common.no' })
        $hint.Text = (Get-DashboardText "software.results.deepSummary" @(
            $deepCompleteText,
            [int]$Scan.DeepSoftwareScanApplicationsScanned,
            [int]$Scan.DeepSoftwareScanRelevantFiles,
            [int]$Scan.DeepSoftwareScanSignatureChecks,
            [int]$Scan.DeepSoftwareScanHashChecks,
            [int]$Scan.DeepSoftwareScanAccessWarningCount)) + "`r`n" + $hint.Text
    }
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.AutoSize = $true
    $hint.AutoEllipsis = $false
    $hint.UseMnemonic = $false
    $hint.MaximumSize = New-Object System.Drawing.Size(([Math]::Max(120, $dialogWidth - 54)), 0)
    $hint.Dock = "Top"
    $mainLayout.Controls.Add($hint, 0, 2)

    $details = New-Object System.Windows.Forms.RichTextBox
    $details.Dock = "Fill"
    $details.ReadOnly = $true
    $details.DetectUrls = $false
    $details.WordWrap = $true
    $details.ScrollBars = "ForcedVertical"
    $details.BackColor = [System.Drawing.Color]::White
    $details.ForeColor = [System.Drawing.Color]::FromArgb(35, 45, 62)
    $details.Font = $fontNormal
    $details.Text = Get-DashboardText 'software.results.detail.selectRow'
    $mainLayout.Controls.Add($details, 0, 4)

    $licenseLabels = @{
        Free=(Get-DashboardText "software.license.free"); OpenSource=(Get-DashboardText "software.license.openSource")
        Freeware=(Get-DashboardText "software.license.freeware"); Freemium=(Get-DashboardText "software.license.freemium")
        Paid=(Get-DashboardText "software.license.paid"); Subscription=(Get-DashboardText "software.license.subscription")
        Perpetual=(Get-DashboardText "software.license.perpetual"); Trialware=(Get-DashboardText "software.license.trialware")
        SystemComponent=(Get-DashboardText "software.license.systemComponent"); Driver=(Get-DashboardText "software.license.driver")
        Runtime=(Get-DashboardText "software.license.runtime"); Unknown=(Get-DashboardText "software.license.unknown")
    }
    $confidenceLabels = @{
        High=(Get-DashboardText "software.confidence.high"); Medium=(Get-DashboardText "software.confidence.medium"); Low=(Get-DashboardText "software.confidence.low")
    }
    $presenceLabels = @{}
    foreach ($presenceState in @('InstalledConfirmed','RegisteredInstallation','VendorRegisteredProduct','PackagePresent','PortableApplication',
        'ResidualOrPortableFiles','LaunchReferenceOnly','CompanionOrSystemComponent','UnverifiedPresence')) {
        $presenceLabels[$presenceState] = Get-DashboardText ('software.presence.' + $presenceState)
    }

    $resizeListColumns = {
        param($Target)
        if ($null -eq $Target -or $Target.Columns.Count -lt 7) { return }
        $availableWidth = [Math]::Max(280, [int]$Target.ClientSize.Width - 8)
        $Target.BeginUpdate()
        try {
            if ($availableWidth -lt 860) {
                # At narrow widths, keep just identity, version and status. All
                # hidden values remain visible in the word-wrapped detail pane.
                $applicationWidth = [Math]::Max(155, [int][Math]::Floor($availableWidth * 0.43))
                $priorityWidth = [Math]::Max(84, [int][Math]::Floor($availableWidth * 0.17))
                $statusWidth = [Math]::Max(1, $availableWidth - $applicationWidth - $priorityWidth)
                $widths = @($applicationWidth, $priorityWidth, 0, 0, 0, $statusWidth, 0)
            } else {
                $applicationWidth = [Math]::Max(180, [int][Math]::Floor($availableWidth * 0.22))
                $priorityWidth = [Math]::Max(82, [int][Math]::Floor($availableWidth * 0.10))
                $versionWidth = [Math]::Max(70, [int][Math]::Floor($availableWidth * 0.09))
                $publisherWidth = [Math]::Max(105, [int][Math]::Floor($availableWidth * 0.16))
                $modelWidth = [Math]::Max(80, [int][Math]::Floor($availableWidth * 0.12))
                $statusWidth = [Math]::Max(125, [int][Math]::Floor($availableWidth * 0.18))
                $confidenceWidth = [Math]::Max(1, $availableWidth - $applicationWidth - $priorityWidth - $versionWidth - $publisherWidth - $modelWidth - $statusWidth)
                $widths = @($applicationWidth, $priorityWidth, $versionWidth, $publisherWidth, $modelWidth, $statusWidth, $confidenceWidth)
            }
            for ($columnIndex = 0; $columnIndex -lt $widths.Count; $columnIndex++) {
                $Target.Columns[$columnIndex].Width = [int]$widths[$columnIndex]
            }
        } finally {
            $Target.EndUpdate()
        }
    }

    $renderSelectionDetails = {
        param($SourceList)
        if ($null -eq $SourceList -or $SourceList.SelectedItems.Count -eq 0) {
            $details.Text = Get-DashboardText 'software.results.detail.selectRow'
            return
        }
        $metadata = $SourceList.SelectedItems[0].Tag
        $application = $metadata.Application
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add((Get-DashboardText 'software.results.column.application') + ': ' + [string]$application.Name)
        $lines.Add((Get-DashboardText 'software.results.column.priority') + ': ' + [string]$metadata.PriorityText)
        $lines.Add((Get-DashboardText 'software.results.column.version') + ': ' + [string]$application.Version)
        $lines.Add((Get-DashboardText 'software.results.column.publisher') + ': ' + [string]$application.Publisher)
        $lines.Add((Get-DashboardText 'software.results.column.model') + ': ' + [string]$metadata.LicenseText)
        $lines.Add((Get-DashboardText 'software.results.column.status') + ': ' + [string]$metadata.StatusText)
        $lines.Add((Get-DashboardText 'software.results.column.confidence') + ': ' + [string]$metadata.ConfidenceText)
        if ($metadata.PSObject.Properties['PresenceText'] -and $metadata.PresenceText) {
            $lines.Add((Get-DashboardText 'software.results.detail.presence') + ': ' + [string]$metadata.PresenceText)
        }
        if ($application.PSObject.Properties['ProductFamily'] -and
            -not [string]::IsNullOrWhiteSpace([string]$application.ProductFamily)) {
            $lines.Add((Get-DashboardText 'software.results.detail.productFamily') + ': ' + [string]$application.ProductFamily)
        }
        if ($application.PSObject.Properties['MergedRecordCount'] -and [int]$application.MergedRecordCount -gt 1) {
            $lines.Add((Get-DashboardText 'software.results.detail.mergedRecords' @([int]$application.MergedRecordCount)))
        }
        if ([bool]$metadata.IsSystemComponent) {
            $lines.Add('')
            $lines.Add((Get-DashboardText 'software.results.detail.systemReadOnly'))
        }
        $lines.Add('')
        $lines.Add((Get-DashboardText 'software.results.detail.evidence'))
        $lines.Add([string]$metadata.EvidenceText)
        $lines.Add('')
        $lines.Add((Get-DashboardText 'software.results.detail.action'))
        $lines.Add([string]$metadata.ActionText)
        $officialNavigation = Get-GuiSoftwareOfficialNavigationTarget -Application $application
        $lines.Add('')
        $lines.Add((Get-DashboardText $(if ([string]$officialNavigation.Mode -eq 'VerifiedDirect') {
            'software.results.officialDirectHint'
        } else {
            'software.results.officialSearchHint'
        })))
        $details.Text = $lines -join "`r`n"
        $details.SelectionStart = 0
        $details.SelectionLength = 0
        $details.ScrollToCaret()
    }

    $newApplicationList = {
        param(
            [object[]]$Rows = @(),
            [bool]$IsSystemView = $false
        )

        $list = New-Object System.Windows.Forms.ListView
        $list.CheckBoxes = [bool](-not $ReadOnly -and -not $IsSystemView)
        $list.View = [System.Windows.Forms.View]::Details
        $list.FullRowSelect = $true
        $list.GridLines = $true
        $list.HideSelection = $false
        $list.ShowItemToolTips = $true
        $list.MultiSelect = $true
        $list.Dock = "Fill"
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.application"), 220)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.priority"), 92)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.version"), 92)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.publisher"), 152)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.model"), 110)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.status"), 152)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.confidence"), 96)

        foreach ($application in @($Rows)) {
            $candidateId = if ($application.PSObject.Properties['CleanupCandidateId']) { [string]$application.CleanupCandidateId } else { '' }
            $actionable = if ($IsSystemView) { $false } else { Test-GuiThirdPartyDirectRemediationEvidence -Application $application }
            $selectionAllowed = if ($IsSystemView) { $false } else { Test-GuiThirdPartySelectionAllowed -Application $application }
            $guidanceOnly = [bool]($selectionAllowed -and -not $actionable)
            $evidenceText = @($application.Evidence | ForEach-Object {
                $detail = if ($_.PSObject.Properties['Location'] -and -not [string]::IsNullOrWhiteSpace([string]$_.Location)) { [string]$_.Location } else { [string]$_.Detail }
                if ([string]::IsNullOrWhiteSpace($detail)) { [string]$_.Code } else { "$([string]$_.Code): $detail" }
            }) -join '; '
            if ([string]::IsNullOrWhiteSpace($evidenceText)) { $evidenceText = Get-DashboardText "software.results.noEvidence" }
            $remediationMode = if ($application.PSObject.Properties['CleanupRemediationMode']) { [string]$application.CleanupRemediationMode } else { '' }
            $actionText = if ($IsSystemView) {
                Get-DashboardText 'software.results.detail.systemReadOnly'
            } elseif ($actionable) {
                $actionDetail = switch ($remediationMode) {
                    'VendorSharedReset' { Get-DashboardText "software.results.action.resetSupported" }
                    'ArtifactCleanupOnly' { Get-DashboardText "software.results.action.artifactCleanupOnly" }
                    'ArtifactCleanup' { Get-DashboardText "software.results.action.artifactCleanup" }
                    'ManualArtifactQuarantine' { Get-DashboardText "software.results.action.manualArtifactQuarantine" }
                    'ManualOfficialReinstall' { Get-DashboardText "software.results.action.manualReinstall" }
                    default { Get-DashboardText "software.results.action.guidedRepair" }
                }
                Get-DashboardText 'software.results.action.classified' @(
                    (Get-DashboardText 'software.results.classification.actionable'), $actionDetail)
            } elseif ($guidanceOnly) {
                Get-DashboardText 'software.results.action.classified' @(
                    (Get-DashboardText 'software.results.classification.actionable'),
                    (Get-DashboardText 'software.results.action.guidedOnly'))
            } elseif (Test-GuiThirdPartyCleanupFinding -Application $application) {
                Get-DashboardText 'software.results.action.classified' @(
                    (Get-DashboardText 'software.results.classification.manualReview'),
                    (Get-DashboardText "software.results.action.officialRepair"))
            } elseif (($application.PSObject.Properties['NeedsReview'] -and [bool]$application.NeedsReview) -or
                [string]$application.AssessmentCode -in @('Unverified','TrialOrUnverified','IntegrityCompromised')) {
                Get-DashboardText 'software.results.action.classified' @(
                    (Get-DashboardText 'software.results.classification.manualReview'),
                    (Get-DashboardText 'software.results.action.manualReview'))
            } else {
                Get-DashboardText "software.results.action.none"
            }
            $licenseModel = [string]$application.LicenseModel
            if (-not $licenseLabels.ContainsKey($licenseModel)) { $licenseModel = 'Unknown' }
            $confidence = [string]$application.Confidence
            if (-not $confidenceLabels.ContainsKey($confidence)) { $confidence = 'Low' }
            $licenseText = [string]$licenseLabels[$licenseModel]
            $confidenceText = [string]$confidenceLabels[$confidence]
            $attentionLevel = if ($application.PSObject.Properties['AttentionLevel']) { [string]$application.AttentionLevel } else { 'Low' }
            $priorityText = switch ($attentionLevel) {
                'High' { Get-DashboardText 'software.results.priority.high' }
                'Medium' { Get-DashboardText 'software.results.priority.medium' }
                'System' { Get-DashboardText 'software.results.priority.system' }
                default { Get-DashboardText 'software.results.priority.low' }
            }
            $presenceState = if ($application.PSObject.Properties['PresenceState'] -and $application.PresenceState) { [string]$application.PresenceState } else { 'UnverifiedPresence' }
            $presenceText = if ($presenceLabels.ContainsKey($presenceState)) { [string]$presenceLabels[$presenceState] } else { [string]$presenceLabels.UnverifiedPresence }
            $statusText = Get-GuiThirdPartyDisplayStatus -Application $application
            if ($presenceState -in @('ResidualOrPortableFiles','PortableApplication','LaunchReferenceOnly','RegisteredInstallation','VendorRegisteredProduct')) {
                $statusText = $presenceText + ' | ' + $statusText
            }
            $row = New-Object System.Windows.Forms.ListViewItem([string]$application.Name)
            [void]$row.SubItems.Add($priorityText)
            [void]$row.SubItems.Add([string]$application.Version)
            [void]$row.SubItems.Add([string]$application.Publisher)
            [void]$row.SubItems.Add($licenseText)
            [void]$row.SubItems.Add($statusText)
            [void]$row.SubItems.Add($confidenceText)
            $row.Tag = [pscustomobject]@{
                Application=$application; CandidateId=$candidateId; Actionable=$actionable; SelectionAllowed=$selectionAllowed
                GuidanceOnly=$guidanceOnly; IsSystemComponent=$IsSystemView; EvidenceText=$evidenceText; ActionText=$actionText
                PriorityText=$priorityText; LicenseText=$licenseText; ConfidenceText=$confidenceText; PresenceText=$presenceText; StatusText=$statusText
            }
            $row.ToolTipText = "$([string]$application.Name)`r`n$statusText`r`n$evidenceText`r`n$actionText"
            if (-not $selectionAllowed) { $row.ForeColor = [System.Drawing.Color]::FromArgb(105, 112, 125) }
            $row.Checked = [bool]($selectionAllowed -and $candidateId -and ($SelectedCandidateIds -contains $candidateId))
            [void]$list.Items.Add($row)
        }
        $list.Add_ItemCheck({
            param($sender, $eventArgs)
            if ($eventArgs.Index -lt 0 -or $eventArgs.Index -ge $sender.Items.Count) { return }
            $metadata = $sender.Items[$eventArgs.Index].Tag
            if (-not [bool]$metadata.SelectionAllowed) { $eventArgs.NewValue = [System.Windows.Forms.CheckState]::Unchecked }
        })
        $list.Add_SelectedIndexChanged({ param($sender, $eventArgs) & $renderSelectionDetails $sender })
        $list.Add_SizeChanged({ param($sender, $eventArgs) & $resizeListColumns $sender })
        & $resizeListColumns $list
        return $list
    }

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    $tabControl.Multiline = $true
    $thirdPartyPage = New-Object System.Windows.Forms.TabPage
    $thirdPartyPage.Text = Get-DashboardText 'software.results.tab.thirdParty' @($thirdPartyApplications.Count)
    $thirdPartyList = & $newApplicationList -Rows $thirdPartyApplications -IsSystemView $false
    $thirdPartyPage.Controls.Add($thirdPartyList)
    $thirdPartyPage.Tag = $thirdPartyList
    [void]$tabControl.TabPages.Add($thirdPartyPage)
    $tabControl.Add_SelectedIndexChanged({
        param($sender, $eventArgs)
        $selectedList = if ($sender.SelectedTab -and $sender.SelectedTab.Tag) { $sender.SelectedTab.Tag } else { $null }
        & $renderSelectionDetails $selectedList
    })
    $mainLayout.Controls.Add($tabControl, 0, 3)

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = "Top"
    $footer.FlowDirection = "RightToLeft"
    $footer.WrapContents = $true
    $footer.AutoScroll = $false
    $footer.AutoSize = $true
    $footer.AutoSizeMode = "GrowAndShrink"
    $footer.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $mainLayout.Controls.Add($footer, 0, 5)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = Get-DashboardText "common.close"
    $closeButton.Size = New-Object System.Drawing.Size(104, 38)
    $closeButton.Add_Click({
        $dialog.Tag = [pscustomobject]@{
            Proceed=$false
            SelectedCandidateIds=@($thirdPartyList.CheckedItems | ForEach-Object { [string]$_.Tag.CandidateId } | Where-Object { $_ } | Select-Object -Unique)
            RepairSources=$false
            Back=$false
            Navigation="Close"
        }
        Close-DashboardWorkflowSession -Dialog $dialog
    })
    $footer.Controls.Add($closeButton)

    $backButton = New-Object System.Windows.Forms.Button
    $backButton.Text = Get-DashboardText "common.back"
    $backButton.Size = New-Object System.Drawing.Size(116, 38)
    $backButton.Add_Click({
        $dialog.Tag = [pscustomobject]@{
            Proceed=$false
            SelectedCandidateIds=@($thirdPartyList.CheckedItems | ForEach-Object { [string]$_.Tag.CandidateId } | Where-Object { $_ } | Select-Object -Unique)
            RepairSources=$false
            Back=$true
            Navigation="Back"
        }
        $dialog.Close()
    })
    $dialog.CancelButton = $backButton
    $footer.Controls.Add($backButton)

    if (-not $ReadOnly -and $selectableCount -gt 0) {
        $continueButton = New-Object System.Windows.Forms.Button
        $continueButton.Text = Get-DashboardText "software.results.continueCleanup"
        $continueButton.Font = $fontBold
        $continueButton.Size = New-Object System.Drawing.Size(210, 38)
        $continueButton.Add_Click({
            $candidateIds = @($thirdPartyList.CheckedItems | ForEach-Object { [string]$_.Tag.CandidateId } | Where-Object { $_ } | Select-Object -Unique)
            if ($candidateIds.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "software.results.selectionRequired"), (Get-DashboardText "software.results.selectionRequiredTitle"), "OK", "Warning") | Out-Null
                return
            }
            $warning = [System.Windows.Forms.MessageBox]::Show(
                (Get-DashboardText "software.results.sharedResetWarning" @($candidateIds.Count)),
                (Get-DashboardText "software.results.sharedResetTitle"),
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
            if ($warning -eq [System.Windows.Forms.DialogResult]::Yes) {
                $dialog.Tag = [pscustomobject]@{ Proceed=$true; SelectedCandidateIds=$candidateIds; RepairSources=$false; Back=$false; Navigation="Continue" }
                $dialog.Close()
            }
        })
        $footer.Controls.Add($continueButton)
    }

    if ($ReadOnly -and @($Warnings).Count -gt 0) {
        $repairSourcesButton = New-Object System.Windows.Forms.Button
        $repairSourcesButton.Text = Get-DashboardText "software.results.repairScanSources"
        $repairSourcesButton.Font = $fontBold
        $repairSourcesButton.Size = New-Object System.Drawing.Size(210, 38)
        $repairSourcesButton.Add_Click({
            $dialog.Tag = [pscustomobject]@{ Proceed=$false; SelectedCandidateIds=@(); RepairSources=$true; Back=$false; Navigation="Repair" }
            $dialog.Close()
        })
        $footer.Controls.Add($repairSourcesButton)
    }

    $officialButton = New-Object System.Windows.Forms.Button
    $officialButton.Text = Get-DashboardText "software.results.openOrFindOfficial"
    $officialButton.Size = New-Object System.Drawing.Size(220, 38)
    $officialButton.Add_Click({
        $selectedList = if ($tabControl.SelectedTab -and $tabControl.SelectedTab.Tag) { $tabControl.SelectedTab.Tag } else { $thirdPartyList }
        if ($selectedList.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "software.results.selectForOfficial"), (Get-DashboardText "software.results.title"), "OK", "Information") | Out-Null
            return
        }
        $navigation = Get-GuiSoftwareOfficialNavigationTarget -Application $selectedList.SelectedItems[0].Tag.Application
        [void](Open-GuiExternalHttpsTarget -Target ([string]$navigation.Target))
    })
    $footer.Controls.Add($officialButton)

    if (-not $ReadOnly -and $selectableCount -gt 0) {
        $clearButton = New-Object System.Windows.Forms.Button
        $clearButton.Text = Get-DashboardText "common.clearAll"
        $clearButton.Size = New-Object System.Drawing.Size(138, 38)
        $clearButton.Add_Click({ foreach ($row in $thirdPartyList.Items) { $row.Checked = $false } })
        $footer.Controls.Add($clearButton)

        $selectAllButton = New-Object System.Windows.Forms.Button
        $selectAllButton.Text = Get-DashboardText "common.selectAll"
        $selectAllButton.Size = New-Object System.Drawing.Size(138, 38)
        $selectAllButton.Add_Click({ foreach ($row in $thirdPartyList.Items) { if ([bool]$row.Tag.SelectionAllowed) { $row.Checked = $true } } })
        $footer.Controls.Add($selectAllButton)
    }

    $setTextMaximumWidth = {
        $availableWidth = [Math]::Max(120, $mainLayout.ClientSize.Width - $mainLayout.Padding.Horizontal)
        foreach ($label in @($heading, $summary, $hint)) {
            if ($label.MaximumSize.Width -ne $availableWidth) {
                $label.MaximumSize = New-Object System.Drawing.Size($availableWidth, 0)
            }
        }
    }
    $refreshLayout = {
        $mainLayout.SuspendLayout()
        try {
            & $setTextMaximumWidth
            & $resizeListColumns $thirdPartyList
            $footer.AutoScroll = $false
            $footer.PerformLayout()
        } finally {
            $mainLayout.ResumeLayout($true)
        }
    }
    $mainLayout.Add_SizeChanged({ & $refreshLayout })
    $dialog.Add_Shown({ & $refreshLayout })

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $result = $dialog.Tag
    $dialog.Dispose()
    return $result
}

function Complete-CleanupScan {
    try {
        if (-not (Test-Path -LiteralPath $script:cleanupDecisionFile)) {
            if ($script:lastModuleResult -and
                [string]$script:lastModuleResult.ModuleId -eq 'cleanup.scan' -and
                [int]$script:lastModuleResult.ExitCode -ne 0) {
                throw (Get-DashboardText "cleanup.scan.processFailed" @([int]$script:lastModuleResult.ExitCode))
            }
            throw (Get-DashboardText "cleanup.scan.resultMissing")
        }
        $scan = Get-Content -LiteralPath $script:cleanupDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:cleanupDecisionFile -Force -ErrorAction SilentlyContinue
        $script:cleanupDecisionFile = ""
        if ($scan.PSObject.Properties['ScanScope'] -and [string]$scan.ScanScope -in @("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")) {
            $script:cleanupScanScope = [string]$scan.ScanScope
        }
        $script:cleanupScanSnapshot = if ($scan.PSObject.Properties['ScanSnapshot']) { $scan.ScanSnapshot } else { $null }
        $scopedCleanupItems = @(Get-GuiScopedCleanupItems -CleanupItems @($scan.CleanupItems) -Scope $script:cleanupScanScope)
        $scan.CleanupItems = $scopedCleanupItems
        if ($scan.ReportPath -and (Test-Path -LiteralPath $scan.ReportPath -PathType Leaf)) {
            Register-ToolReportPath -Path ([string]$scan.ReportPath)
            Write-ProgressLog (Get-DashboardText "cleanup.report.readyOnDemand" @($scan.ReportPath))
        }
        $thirdPartySuggestedIds = @()

        if ([int]$scan.ScanWarningCount -gt 0) {
            Set-ButtonsEnabled $true
            $status.Text = Get-DashboardText "cleanup.scan.incompleteStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog (Get-DashboardText "cleanup.scan.incompleteLog" @($scan.ScanWarningCount))
            if (Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "ThirdParty") {
                $assessmentChoice = Show-ThirdPartyAssessmentResults -Scan $scan -ReadOnly -Warnings @($scan.ScanWarnings)
                if ($assessmentChoice.PSObject.Properties['RepairSources'] -and [bool]$assessmentChoice.RepairSources) {
                    Start-ScanSourceRepair
                    return
                }
                if ($assessmentChoice.PSObject.Properties['Navigation'] -and [string]$assessmentChoice.Navigation -eq "Close") {
                    return
                }
                if ($assessmentChoice.PSObject.Properties['Back'] -and [bool]$assessmentChoice.Back) {
                    Open-CleanupEntrySession -ScanScope $script:cleanupScanScope
                    return
                }
            }
            $choice = Show-ScanWarningRecoveryDialog -Scan $scan
            if ($choice -eq "Repair") {
                Start-ScanSourceRepair
            } elseif ($choice -eq "Retry") {
                Start-Cleanup -ReuseSessionSettings
            } else {
                $script:cleanupAutoSafeMode = $false
                Write-ProgressLog (Get-DashboardText "cleanup.scan.closedLog")
            }
            return
        }

        if ($script:cleanupScanScope -eq "ThirdParty") {
            $script:cleanupAutoSafeMode = $false
            Set-ButtonsEnabled $true
            $assessmentSessionIds = @()
            while ($true) {
                $assessmentChoice = Show-ThirdPartyAssessmentResults -Scan $scan -SelectedCandidateIds $assessmentSessionIds
                $assessmentSessionIds = @($assessmentChoice.SelectedCandidateIds)
                if ([bool]$assessmentChoice.Proceed) {
                    $navigationResult = Start-CleanupDeep -CleanupItems $scopedCleanupItems -SuggestedIds $assessmentSessionIds -ReturnNavigationResult
                    if ([string]$navigationResult -eq "Back") { continue }
                    return
                }
                $remainingThirdPartyCount = if ($scan.PSObject.Properties['ThirdPartyRemediationFindingCount']) {
                    [int]$scan.ThirdPartyRemediationFindingCount
                } else {
                    [int]$scan.ThirdPartyCandidateCount
                }
                $status.Text = Get-DashboardText "software.results.closedStatus" @(
                    [int]$scan.ThirdPartyApplicationCount,
                    $remainingThirdPartyCount)
                $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
                Write-ProgressLog (Get-DashboardText "software.results.closedLog")
                if ($assessmentChoice.PSObject.Properties['Back'] -and [bool]$assessmentChoice.Back) {
                    Open-CleanupEntrySession -ScanScope $script:cleanupScanScope
                }
                return
            }
        }

        if (Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "ThirdParty") {
            # In a normal combined scan, let the user choose eligible third-party
            # artifacts one-by-one or all at once.  The choices only preselect
            # IDs for the unified final review; they are never auto-applied.
            if ([bool]$script:cleanupAutoSafeMode) {
                $assessmentChoice = Show-ThirdPartyAssessmentResults -Scan $scan -ReadOnly
                if ($assessmentChoice.PSObject.Properties['Navigation'] -and [string]$assessmentChoice.Navigation -eq "Close") {
                    $script:cleanupAutoSafeMode = $false
                    return
                }
                if ($assessmentChoice.PSObject.Properties['Back'] -and [bool]$assessmentChoice.Back) {
                    $script:cleanupAutoSafeMode = $false
                    Open-CleanupEntrySession -ScanScope $script:cleanupScanScope
                    return
                }
            } else {
                $assessmentChoice = Show-ThirdPartyAssessmentResults -Scan $scan
                if ([bool]$assessmentChoice.Proceed) {
                    $thirdPartySuggestedIds = @($assessmentChoice.SelectedCandidateIds)
                } elseif ($assessmentChoice.PSObject.Properties['Navigation'] -and [string]$assessmentChoice.Navigation -eq "Close") {
                    return
                } elseif ($assessmentChoice.PSObject.Properties['Back'] -and [bool]$assessmentChoice.Back) {
                    Open-CleanupEntrySession -ScanScope $script:cleanupScanScope
                    return
                }
            }
        }

        if ($scopedCleanupItems.Count -gt 0) {
            if ([bool]$script:cleanupAutoSafeMode) {
                $automaticSafeItems = @(Get-AutomaticSafeCleanupItems -CleanupItems $scopedCleanupItems)
                if ($automaticSafeItems.Count -gt 0) {
                    Write-ProgressLog (Get-DashboardText "cleanup.auto.safeFound" @($automaticSafeItems.Count))
                    Start-CleanupDeep -CleanupItems $scopedCleanupItems -AutomaticSafeMode
                    return
                }

                $script:cleanupAutoSafeMode = $false
                Set-ButtonsEnabled $true
                $manualAnswer = [System.Windows.Forms.MessageBox]::Show(
                    (Get-DashboardText "cleanup.auto.nonePrompt"),
                    (Get-DashboardText "cleanup.auto.noneTitle"),
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Information)
                if ($manualAnswer -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Start-CleanupDeep -CleanupItems $scopedCleanupItems
                } else {
                    $status.Text = Get-DashboardText "cleanup.auto.noneStatus"
                    $status.ForeColor = [System.Drawing.Color]::DarkOrange
                }
                return
            }

            while ($true) {
                $licenseNote = if ((Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "Windows") -and [bool]$scan.ProtectedLicense) {
                    Get-DashboardText "cleanup.scan.protectedNote" @($scan.ProtectedChannel, $scan.ProtectedReason)
                } elseif (Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "Windows") {
                    Get-DashboardText "cleanup.scan.unprotectedNote"
                } else {
                    ""
                }
                $findingMessage = switch ($script:cleanupScanScope) {
                    "WindowsOffice" { Get-DashboardText "cleanup.scan.findingSummary.windowsOffice" @($scan.ActivatorFindingCount, $scan.ConfigurationResidueCount, $scan.WindowsKmsCount, $scan.OfficeKmsCount, $scopedCleanupItems.Count) }
                    "ThirdParty" { Get-DashboardText "cleanup.scan.findingSummary.thirdParty" @($scopedCleanupItems.Count) }
                    default { Get-DashboardText "cleanup.scan.findingSummary" @($scan.ActivatorFindingCount, $scan.ConfigurationResidueCount, $scan.WindowsKmsCount, $scan.OfficeKmsCount, $scan.HistoryFindingCount, $scan.ThirdPartyCandidateCount) }
                }
                $message = $licenseNote + $findingMessage
                $answer = [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "cleanup.scan.selectionTitle"), "YesNo", "Warning")
                if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                    Set-ButtonsEnabled $true
                    $status.Text = Get-DashboardText "cleanup.scan.cancelledStatus"
                    Write-ProgressLog (Get-DashboardText "cleanup.scan.cancelledLog")
                    $status.ForeColor = [System.Drawing.Color]::DarkOrange
                    return
                }
                $navigationResult = Start-CleanupDeep -CleanupItems $scopedCleanupItems -SuggestedIds $thirdPartySuggestedIds -ReturnNavigationResult
                if ([string]$navigationResult -ne "Back") { return }
                if (Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "ThirdParty") {
                    $assessmentChoice = Show-ThirdPartyAssessmentResults -Scan $scan -SelectedCandidateIds $thirdPartySuggestedIds
                    if ($assessmentChoice.PSObject.Properties['Navigation'] -and [string]$assessmentChoice.Navigation -eq "Close") {
                        return
                    }
                    if ($assessmentChoice.PSObject.Properties['Back'] -and [bool]$assessmentChoice.Back) {
                        Open-CleanupEntrySession -ScanScope $script:cleanupScanScope
                        return
                    }
                    $thirdPartySuggestedIds = if ([bool]$assessmentChoice.Proceed) { @($assessmentChoice.SelectedCandidateIds) } else { @() }
                }
            }
        }

        $script:cleanupAutoSafeMode = $false
        Set-ButtonsEnabled $true
        $componentSummary = @(Get-GuiCleanupComponentStatusLines -Scan $scan -Scope $script:cleanupScanScope) -join "`r`n"
        $scopeLabel = Get-CleanupScopeLabel -Scope $script:cleanupScanScope
        if ([bool]$scan.ProtectedLicense) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "cleanup.scan.protectedResult" @($scan.ProtectedChannel, $componentSummary, (Get-GuiScanIntegerProperty -Scan $scan -Name 'HistoryFindingCount'), $scan.CleanupConclusion)), (Get-DashboardText "cleanup.scan.protectedTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "cleanup.scan.protectedStatus" @($scan.ProtectedChannel)
            Write-ProgressLog (Get-DashboardText "cleanup.scan.cleanLog" @($scopeLabel))
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            [System.Windows.Forms.MessageBox]::Show((Get-GuiCleanupNoFindingMessage -Scan $scan -Scope $script:cleanupScanScope), (Get-DashboardText "cleanup.scan.resultTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "cleanup.scan.noFindingStatus"
            Write-ProgressLog (Get-DashboardText "cleanup.scan.noFindingLog")
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    } catch {
        if ($script:cleanupDecisionFile -and (Test-Path -LiteralPath $script:cleanupDecisionFile -PathType Leaf)) {
            Remove-Item -LiteralPath $script:cleanupDecisionFile -Force -ErrorAction SilentlyContinue
        }
        $script:cleanupDecisionFile = ""
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "cleanup.scan.readFailed" @($_.Exception.Message)
        Write-ProgressLog (Get-DashboardText "cleanup.scan.readFailedLog" @($_.Exception.Message))
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Test-GuiOfficialHttpsTarget([string]$Target) {
    $uri = $null
    return [bool]([Uri]::TryCreate($Target, [UriKind]::Absolute, [ref]$uri) -and
        $uri.Scheme -eq 'https' -and -not [string]::IsNullOrWhiteSpace($uri.Host) -and
        [string]::IsNullOrWhiteSpace($uri.UserInfo))
}

function Get-GuiSoftwareOfficialNavigationTarget {
    param($Application)

    $directTarget = if ($Application -and $Application.PSObject.Properties['OfficialReferenceUrl']) {
        [string]$Application.OfficialReferenceUrl
    } else { '' }
    if (Test-GuiOfficialHttpsTarget $directTarget) {
        return [pscustomobject][ordered]@{
            Target = $directTarget
            Mode = 'VerifiedDirect'
        }
    }

    # A missing signed-catalog URL must not be replaced with a guessed domain.
    # Search only by a small, encoded identity tuple and let the user verify the
    # vendor domain in the browser.  No paths, versions, licence state or other
    # machine data are included in the query.
    $normalizeSearchTerm = {
        param([AllowNull()][string]$Value, [int]$MaximumLength)
        $normalized = (($Value -replace '[\u0000-\u001F\u007F]', ' ') -replace '\s+', ' ').Trim()
        if ($normalized.Length -gt $MaximumLength) { $normalized = $normalized.Substring(0, $MaximumLength).Trim() }
        return $normalized
    }
    $name = & $normalizeSearchTerm $(if ($Application -and $Application.PSObject.Properties['Name']) { [string]$Application.Name } else { '' }) 140
    $publisher = & $normalizeSearchTerm $(if ($Application -and $Application.PSObject.Properties['Publisher']) { [string]$Application.Publisher } else { '' }) 100
    if ([string]::IsNullOrWhiteSpace($publisher) -and $Application -and $Application.PSObject.Properties['SignaturePublisher']) {
        $publisher = & $normalizeSearchTerm ([string]$Application.SignaturePublisher) 100
    }
    if ([string]::IsNullOrWhiteSpace($publisher) -and $Application -and $Application.PSObject.Properties['VendorScope']) {
        $publisher = & $normalizeSearchTerm ([string]$Application.VendorScope) 100
    }
    $identity = @($name, $publisher) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique
    $query = if (@($identity).Count -gt 0) {
        ((@($identity) + @('official website')) -join ' ').Trim()
    } else {
        'software official website'
    }
    $searchTarget = 'https://www.bing.com/search?q=' + [Uri]::EscapeDataString($query)
    return [pscustomobject][ordered]@{
        Target = $searchTarget
        Mode = 'SearchFallback'
    }
}

function Open-GuiExternalHttpsTarget {
    param([Parameter(Mandatory = $true)][string]$Target)

    if (-not (Test-GuiOfficialHttpsTarget $Target)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'software.results.invalidOfficialTarget'), (Get-DashboardText 'common.errorTitle'), 'OK', 'Error') | Out-Null
        return $false
    }
    if ($script:offlineMode) {
        $consent = [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText 'software.results.onlineNavigationConsent'),
            (Get-DashboardText 'software.results.onlineNavigationTitle'),
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($consent -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
        $script:offlineMode = $false
        [void](Set-ToolOfflineModePreference -OfflineMode $false)
        $env:TOOL_OFFLINE_MODE = '0'
        Update-DashboardOfflineUi
        Set-DashboardTheme -Mode $script:dashboardTheme
        Refresh-DashboardLocalizedActivity
        [void](Write-ToolLog -Level 'AUDIT' -Event 'OnlineMode.ExternalNavigationEnabled' -Message (Get-DashboardText 'offline.networkAllowedLog') -Data ([ordered]@{
            Source='OfficialPageNavigation'; SessionOnly=$true; OpenedTargetHost=([Uri]$Target).Host
        }))
    }
    try {
        Start-Process -FilePath $Target
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'software.results.openOfficialFailed' @($_.Exception.Message)), (Get-DashboardText 'common.errorTitle'), 'OK', 'Error') | Out-Null
        return $false
    }
}

function Open-GuiVendorLicenseAction {
    param($Action, $Result)
    $targets = @(if ($Action -and $Action.PSObject.Properties['Target'] -and (Test-GuiOfficialHttpsTarget ([string]$Action.Target))) {
        @($Action)
    } elseif ($Action -and $Action.PSObject.Properties['Targets']) {
        @($Action.Targets | Where-Object { Test-GuiOfficialHttpsTarget ([string]$_.Target) })
    } elseif ($Result -and $Result.PSObject.Properties['OfficialLicensePostCheck']) {
        @($Result.OfficialLicensePostCheck.OfficialActions | Where-Object {
            [string]$_.Code -in @('OpenVendorActivation','OpenVendorRepair') -and
            (Test-GuiOfficialHttpsTarget ([string]$_.Target))
        })
    } else { @() })
    if ($targets.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'cleanup.result.vendorTargetMissing'), (Get-DashboardText 'cleanup.result.vendorTitle'), 'OK', 'Information') | Out-Null
        return "Unavailable"
    }
    $picker = New-Object System.Windows.Forms.Form
    $picker.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $picker.Text = Get-DashboardText 'cleanup.result.vendorTitle'
    $picker.StartPosition = 'CenterParent'; $picker.FormBorderStyle = 'Sizable'; $picker.MaximizeBox = $false; $picker.MinimizeBox = $false
    $picker.MinimumSize = New-Object System.Drawing.Size(620, 220); $picker.ClientSize = New-Object System.Drawing.Size(760,190); $picker.Tag = 'Close'
    $label = New-Object System.Windows.Forms.Label
    $label.Text = Get-DashboardText 'cleanup.result.vendorHint'; $label.Location = New-Object System.Drawing.Point(16,14); $label.Size = New-Object System.Drawing.Size(728,52); $label.Anchor = 'Top,Left,Right'
    $picker.Controls.Add($label)
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'; $combo.Location = New-Object System.Drawing.Point(16,72); $combo.Size = New-Object System.Drawing.Size(728,28); $combo.Anchor = 'Top,Left,Right'
    foreach ($target in $targets) {
        [void]$combo.Items.Add([pscustomobject]@{ Label="$([string]$target.Name) — $([string]$target.Target)"; Target=[string]$target.Target })
    }
    $combo.DisplayMember = 'Label'; if ($combo.Items.Count -gt 0) { $combo.SelectedIndex = 0 }; $picker.Controls.Add($combo)
    $open = New-Object System.Windows.Forms.Button
    $open.Text = Get-DashboardText 'software.results.openOfficial'; $open.Location = New-Object System.Drawing.Point(340,132); $open.Size = New-Object System.Drawing.Size(190,36); $open.Anchor = 'Bottom,Right'
    $open.Add_Click({ if ($combo.SelectedItem) { $picker.Tag=[string]$combo.SelectedItem.Target; $picker.Close() } }); $picker.Controls.Add($open)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = Get-DashboardText 'common.back'; $cancel.Location = New-Object System.Drawing.Point(538,132); $cancel.Size = New-Object System.Drawing.Size(104,36); $cancel.Anchor = 'Bottom,Right'
    $cancel.Add_Click({ $picker.Tag='Back'; $picker.Close() }); $picker.CancelButton=$cancel; $picker.Controls.Add($cancel)
    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-DashboardText 'common.close'; $close.Location = New-Object System.Drawing.Point(650,132); $close.Size = New-Object System.Drawing.Size(104,36); $close.Anchor = 'Bottom,Right'
    $close.Add_Click({ $picker.Tag='Close'; Close-DashboardWorkflowSession -Dialog $picker }); $picker.Controls.Add($close)
    Set-ToolWindowTheme -Root $picker -Mode $script:dashboardTheme
    $resizeVendorButtons = {
        $close.Width = [Math]::Max(94, (Get-ToolUiButtonRequiredWidth -Button $close -HorizontalSafety 12))
        $cancel.Width = [Math]::Max(94, (Get-ToolUiButtonRequiredWidth -Button $cancel -HorizontalSafety 12))
        $open.Width = [Math]::Max(180, (Get-ToolUiButtonRequiredWidth -Button $open -HorizontalSafety 12))
        $close.Left = $picker.ClientSize.Width - $close.Width - 16
        $cancel.Left = $close.Left - $cancel.Width - 8
        $open.Left = $cancel.Left - $open.Width - 8
    }
    $picker.Add_SizeChanged($resizeVendorButtons)
    & $resizeVendorButtons
    [void](Show-DashboardModalDialog -Dialog $picker); $targetUrl=[string]$picker.Tag; $picker.Dispose()
    if (Test-GuiOfficialHttpsTarget $targetUrl) {
        [void](Open-GuiExternalHttpsTarget -Target $targetUrl)
        return "Opened"
    }
    return $(if ($targetUrl -eq "Back") { "Back" } else { "Close" })
}

function Get-GuiPostVerificationDispositionLabel {
    param([string]$Disposition)

    $key = switch ($Disposition) {
        'ResidualAfterSelectedAction' { 'cleanup.result.postDisposition.residual' }
        'RemainingActionable' { 'cleanup.result.postDisposition.actionable' }
        'OfficialActionRequired' { 'cleanup.result.postDisposition.officialAction' }
        'OfficialGuidanceAvailable' { 'cleanup.result.postDisposition.officialGuidance' }
        'ActionFailed' { 'cleanup.result.postDisposition.failed' }
        'ScanIncomplete' { 'cleanup.result.postDisposition.scanIncomplete' }
        default { 'cleanup.result.postDisposition.cannotAutoHandle' }
    }
    return Get-DashboardText $key
}

function Get-GuiPostVerificationOutcomeLabel {
    param([string]$Outcome)

    $key = switch ($Outcome) {
        'VerifiedValid' { 'cleanup.result.postOutcome.verifiedValid' }
        'FullyHandled' { 'cleanup.result.postOutcome.fullyHandled' }
        'RemainingActionable' { 'cleanup.result.postOutcome.remainingActionable' }
        default { 'cleanup.result.postOutcome.cannotAutoHandle' }
    }
    return Get-DashboardText $key
}

function Show-CleanupResultCenter {
    param($Result, [bool]$WasDeepCleanup, [bool]$SafetyBlocked)

    $isDryRun = [bool]($Result.PSObject.Properties['SimulationOnly'] -and [bool]$Result.SimulationOnly)
    $hasPostVerification = [bool]$Result.PSObject.Properties['PostVerificationItems']
    $postVerificationItems = if ($hasPostVerification) { @($Result.PostVerificationItems) } else { @() }
    $remainingItems = if ($hasPostVerification) { @($postVerificationItems) } else { @($Result.CleanupItems) }
    $postVerificationOutcome = if ($Result.PSObject.Properties['PostVerificationOutcome']) { [string]$Result.PostVerificationOutcome } else { '' }
    $thirdPartyExecutionResults = @($(if ($Result.PSObject.Properties['ThirdPartyExecutionResults']) { @($Result.ThirdPartyExecutionResults) }))
    $systemChangeApplied = [bool]($Result.PSObject.Properties['SystemChangeApplied'] -and [bool]$Result.SystemChangeApplied)
    $noAutomaticChange = [bool](-not $isDryRun -and -not $SafetyBlocked -and [int]$Result.SelectedCleanupItemCount -gt 0 -and -not $systemChangeApplied -and $thirdPartyExecutionResults.Count -gt 0)
    $guidedActionOnly = [bool]($Result.PSObject.Properties['DecisionCode'] -and [string]$Result.DecisionCode -eq 'GuidedActionRequired')
    $officiallyLicensed = [bool]($Result.PSObject.Properties['OfficiallyLicensed'] -and [bool]$Result.OfficiallyLicensed)
    $officialLicenseStateCode = if ($Result.PSObject.Properties['OfficialLicenseStateCode']) { [string]$Result.OfficialLicenseStateCode } else { 'Unknown' }
    $officialPostCheck = if ($Result.PSObject.Properties['OfficialLicensePostCheck']) { $Result.OfficialLicensePostCheck } else { $null }
    $hasExplicitSelection = [bool]($Result.PSObject.Properties['SelectedCleanupItemCount'] -and [int]$Result.SelectedCleanupItemCount -gt 0)
    $postVerificationSuggestedIds = if ($Result.PSObject.Properties['PostVerificationSuggestedIds']) {
        @($Result.PostVerificationSuggestedIds | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    } else { @() }
    $nextActions = @($Result.NextActions)
    if ($isDryRun) {
        $nextActions = @([pscustomobject]@{
            Code='ExecuteDryRunPlan'; Label=(Get-DashboardText 'cleanup.dryRun.executeButton')
            Detail=(Get-DashboardText 'cleanup.dryRun.executeDetail'); CandidateCount=[int]@($Result.SelectedCleanupIds).Count
        }) + @($nextActions | Where-Object { [string]$_.Code -in @('Recheck','OpenReport') })
    }
    if ($SafetyBlocked) {
        $nextActions = @($nextActions | Where-Object { [string]$_.Code -in @('Recheck','OpenReport') })
    }
    if ($hasExplicitSelection -and $postVerificationSuggestedIds.Count -eq 0) {
        # Defense in depth for result files produced by older code: without an
        # exact remaining ID this button could reopen the chooser with defaults
        # and appear to select/process the whole machine.
        $nextActions = @($nextActions | Where-Object { [string]$_.Code -ne 'RemediateRemaining' })
    }

    $headingText = if ($isDryRun) {
        Get-DashboardText 'cleanup.dryRun.completedHeading' @([int]$Result.PlannedActionCount)
    } elseif ($SafetyBlocked) {
        Get-DashboardText "cleanup.result.blockedHeading"
    } elseif ($guidedActionOnly) {
        Get-DashboardText 'cleanup.result.guidedActionHeading'
    } elseif ($noAutomaticChange) {
        Get-DashboardText "cleanup.result.noAutomaticChangeHeading"
    } elseif ($postVerificationOutcome -eq 'VerifiedValid' -or $officiallyLicensed) {
        Get-DashboardText 'cleanup.result.licensedHeading'
    } elseif ($postVerificationOutcome -eq 'FullyHandled') {
        Get-DashboardText 'cleanup.result.fullyHandledHeading'
    } elseif ([bool]$Result.ReadyForOfficialActivation) {
        Get-DashboardText "cleanup.result.readyHeading"
    } elseif ($remainingItems.Count -gt 0) {
        Get-DashboardText "cleanup.result.remainingHeading" @($remainingItems.Count)
    } else {
        Get-DashboardText "cleanup.result.reviewHeading"
    }
    $headingColor = if ($isDryRun) { [System.Drawing.Color]::FromArgb(18, 59, 116) } elseif ($officiallyLicensed -or $postVerificationOutcome -eq 'FullyHandled') { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
    if ($SafetyBlocked) { $headingColor = [System.Drawing.Color]::DarkRed }

    $body = New-Object System.Collections.Generic.List[string]
    $body.Add([string]$Result.CleanupConclusion)
    $body.Add("")
    $body.Add((Get-DashboardText "cleanup.result.verificationHeading"))
    $body.Add((Get-DashboardText "cleanup.result.activatorCount" @($Result.ActivatorFindingCount)))
    $body.Add((Get-DashboardText "cleanup.result.residueCount" @($Result.ConfigurationResidueCount)))
    $body.Add((Get-DashboardText "cleanup.result.windowsKmsCount" @($Result.WindowsKmsCount)))
    $body.Add((Get-DashboardText "cleanup.result.officeKmsCount" @($Result.OfficeKmsCount)))
    if ($hasExplicitSelection) {
        $targetedThirdPartyCount = if ($Result.PSObject.Properties['TargetedThirdPartyCandidateCount']) {
            [int]$Result.TargetedThirdPartyCandidateCount
        } elseif ($Result.PSObject.Properties['SelectedThirdPartyCandidateCount']) {
            [int]$Result.SelectedThirdPartyCandidateCount
        } else { 0 }
        $targetedThirdPartyRemaining = if ($Result.PSObject.Properties['SelectedThirdPartyRemainingCount']) {
            [int]$Result.SelectedThirdPartyRemainingCount
        } else {
            [int]@($postVerificationItems | Where-Object { [string]$_.ComponentScope -eq 'ThirdParty' }).Count
        }
        $body.Add((Get-DashboardText 'cleanup.result.targetedThirdPartyCount' @($targetedThirdPartyCount, $targetedThirdPartyRemaining)))
    } else {
        $body.Add((Get-DashboardText "cleanup.result.thirdPartyCount" @($Result.ThirdPartyCandidateCount)))
    }
    if ($Result.PSObject.Properties['SelectedThirdPartyCandidateCount'] -and [int]$Result.SelectedThirdPartyCandidateCount -gt 0) {
        $body.Add((Get-DashboardText 'cleanup.result.selectedThirdPartySummary' @(
            [int]$Result.SelectedThirdPartyResolvedCount,
            [int]$Result.SelectedThirdPartyCandidateCount,
            [int]$Result.SelectedThirdPartyRemainingCount
        )))
    }
    $body.Add((Get-DashboardText "cleanup.result.historyCount" @($Result.HistoryFindingCount)))
    $body.Add((Get-DashboardText "cleanup.result.warningCount" @($Result.ScanWarningCount)))
    $body.Add((Get-DashboardText "cleanup.result.reviewCount" @($Result.ReadinessReviewCount)))
    $body.Add((Get-DashboardText 'cleanup.result.licenseState' @(
        $(if ($officiallyLicensed) { 'True' } else { 'False' }),
        $officialLicenseStateCode,
        $(if ([bool]$Result.ReadyForOfficialActivation) { 'True' } else { 'False' })
    )))
    if ($hasPostVerification) {
        $body.Add((Get-DashboardText 'cleanup.result.postVerificationHeading'))
        $body.Add((Get-DashboardText 'cleanup.result.postVerificationOutcome' @(
            (Get-GuiPostVerificationOutcomeLabel -Outcome $postVerificationOutcome))))
    }
    if ($officialPostCheck) {
        foreach ($outcome in @($officialPostCheck.Windows, $officialPostCheck.Office) | Where-Object { $_ -and [bool]$_.Applicable }) {
            $body.Add((Get-DashboardText 'cleanup.result.componentLicenseState' @(
                [string]$outcome.Component,
                $(if ([bool]$outcome.OfficiallyLicensed) { 'True' } else { 'False' }),
                [string]$outcome.StateCode
            )))
        }
        $thirdPartyOutcomes = @($officialPostCheck.ThirdParty | Where-Object { [bool]$_.Applicable })
        if ($thirdPartyOutcomes.Count -gt 0) {
            $body.Add((Get-DashboardText 'cleanup.result.thirdPartyLicenseState' @(
                @($thirdPartyOutcomes | Where-Object { [bool]$_.OfficiallyLicensed }).Count,
                $thirdPartyOutcomes.Count
            )))
        }
    }

    if ($isDryRun) {
        $body.Add("")
        $body.Add((Get-DashboardText 'cleanup.dryRun.noChangesHeading'))
        $body.Add((Get-DashboardText 'cleanup.dryRun.noChangesDetail'))
        $body.Add("")
        $body.Add((Get-DashboardText 'cleanup.dryRun.planHeading' @([int]$Result.PlannedActionCount)))
        foreach ($planned in @($Result.PlannedActions)) {
            $restoreLabel = if ([bool]$planned.Restorable) { Get-DashboardText 'cleanup.dryRun.restorable' } else { Get-DashboardText 'cleanup.dryRun.notRestorable' }
            $body.Add("$($planned.Order). $($planned.Action) - $($planned.Target) [$restoreLabel]")
        }
    }

    if ($thirdPartyExecutionResults.Count -gt 0) {
        $body.Add("")
        $body.Add((Get-DashboardText 'cleanup.result.thirdPartyExecutionHeading'))
        foreach ($execution in @($thirdPartyExecutionResults)) {
            $statusKey = if ($execution.PSObject.Properties['PostCheckStatus'] -and [string]$execution.PostCheckStatus -eq 'ResidualRemaining') {
                'cleanup.result.execution.residueRemaining'
            } else { switch ([string]$execution.Status) {
                'Succeeded' { 'cleanup.result.execution.succeeded' }
                'SucceededNeedsVerification' { 'cleanup.result.execution.needsVerification' }
                'Failed' { 'cleanup.result.execution.failed' }
                'NoChange' { 'cleanup.result.execution.noChange' }
                default { 'cleanup.result.execution.guidanceOnly' }
            } }
            $executionStatus = Get-DashboardText $statusKey
            $executionTarget = if ([string]::IsNullOrWhiteSpace([string]$execution.Target)) { Get-DashboardText 'common.unknown' } else { [string]$execution.Target }
            $body.Add("- [$executionStatus] $([string]$execution.Name) - $executionTarget")
        }
    }

    if ($nextActions.Count -gt 0) {
        $body.Add("")
        $body.Add((Get-DashboardText "cleanup.result.nextHeading"))
        $stepNumber = 0
        foreach ($next in $nextActions) {
            if ([string]$next.Code -eq 'OpenReport') { continue }
            $stepNumber++
            $candidateText = if ([int]$next.CandidateCount -gt 0) { Get-DashboardText "cleanup.result.candidateSuffix" @($next.CandidateCount) } else { "" }
            $body.Add("$stepNumber. $($next.Label)$candidateText - $($next.Detail)")
        }
    }

    if ($remainingItems.Count -gt 0) {
        $body.Add("")
        $body.Add((Get-DashboardText $(if ($hasPostVerification) { 'cleanup.result.postVerificationItemsHeading' } else { 'cleanup.result.remainingItemsHeading' })))
        foreach ($item in @($remainingItems)) {
            if ($hasPostVerification) {
                $location = (([string]$item.Location) -replace "`0|`r?`n", " ").Trim()
                if ([string]::IsNullOrWhiteSpace($location)) { $location = Get-DashboardText 'common.unknown' }
                $reason = (([string]$item.Reason) -replace "`0|`r?`n", " ").Trim()
                if ([string]::IsNullOrWhiteSpace($reason)) { $reason = (([string]$item.Detail) -replace "`0|`r?`n", " ").Trim() }
                $body.Add((Get-DashboardText 'cleanup.result.postVerificationItem' @(
                    (Get-GuiPostVerificationDispositionLabel -Disposition ([string]$item.Disposition)),
                    [string]$item.Name, $location, $reason)))
            } else {
                $detail = (([string]$item.Detail) -replace "`0|`r?`n", " ").Trim()
                $body.Add("- [$($item.Type)] $($item.Name) - $detail")
            }
        }
    }

    $guidance = @($Result.HandlingGuidance)
    if ($guidance.Count -gt 0) {
        $body.Add("")
        $body.Add((Get-DashboardText "cleanup.result.guidanceHeading"))
        foreach ($line in $guidance) { $body.Add("• $line") }
    }

    $rawActions = @($Result.Actions)
    if ($rawActions.Count -gt 0) {
        $body.Add("")
        $body.Add((Get-DashboardText "cleanup.result.actionsHeading"))
        foreach ($action in @($rawActions)) {
            $line = (([string]$action) -replace "`0|`r?`n", " | ").Trim()
            $body.Add("• $line")
        }
    }
    $body.Add("")
    $body.Add([string]$Result.ScopeNote)
    $body.Add((Get-DashboardText "common.reportPath" @($Result.ReportPath)))

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = if ($isDryRun) { Get-DashboardText 'cleanup.dryRun.resultTitle' } elseif ($postVerificationOutcome -eq 'VerifiedValid' -or $officiallyLicensed) { Get-DashboardText 'cleanup.result.licensedTitle' } elseif ($postVerificationOutcome -eq 'FullyHandled') { Get-DashboardText 'cleanup.result.fullyHandledTitle' } elseif ($guidedActionOnly) { Get-DashboardText 'cleanup.result.guidedActionTitle' } elseif ($noAutomaticChange) { Get-DashboardText 'cleanup.result.noAutomaticChangeTitle' } elseif ([bool]$Result.ReadyForOfficialActivation) { Get-DashboardText "cleanup.result.readyTitle" } else { Get-DashboardText "cleanup.result.remainingTitle" }
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MaximizeBox = $true
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Font = $fontNormal
    $dialog.Tag = "Close"
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(660, [Math]::Min(940, $workArea.Width - 70))
    $dialogHeight = [Math]::Max(440, [Math]::Min(700, $workArea.Height - 70))
    $dialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(660, $dialogWidth), [Math]::Min(440, $dialogHeight))
    $dialog.Size = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(14)
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $dialog.Controls.Add($layout)

    $header = New-Object System.Windows.Forms.TableLayoutPanel
    $header.Dock = "Top"
    $header.AutoSize = $true
    $header.AutoSizeMode = "GrowAndShrink"
    $header.ColumnCount = 1
    $header.RowCount = 2
    [void]$header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$header.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$header.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = $headingText
    $heading.Font = $fontTitle
    $heading.ForeColor = $headingColor
    $heading.AutoSize = $true
    $heading.Dock = "Top"
    $header.Controls.Add($heading, 0, 0)
    $subheading = New-Object System.Windows.Forms.Label
    $subheading.Text = if ($isDryRun) { Get-DashboardText 'cleanup.dryRun.resultHint' } elseif ($SafetyBlocked) { Get-DashboardText "cleanup.result.blockedHint" } elseif ($guidedActionOnly) { Get-DashboardText 'cleanup.result.guidedActionHint' } elseif ($postVerificationOutcome -eq 'FullyHandled') { Get-DashboardText 'cleanup.result.fullyHandledHint' } elseif ($postVerificationOutcome -eq 'CannotAutoHandle') { Get-DashboardText 'cleanup.result.cannotAutoHandleHint' } elseif ($remainingItems.Count -gt 0) { Get-DashboardText "cleanup.result.remainingHint" } else { Get-DashboardText "cleanup.result.defaultHint" }
    $subheading.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $subheading.AutoSize = $true
    $subheading.Dock = "Top"
    $header.Controls.Add($subheading, 0, 1)
    $layout.Controls.Add($header, 0, 0)

    $details = New-Object System.Windows.Forms.RichTextBox
    $details.Dock = "Fill"
    $details.ReadOnly = $true
    $details.DetectUrls = $false
    $details.WordWrap = $true
    $details.ScrollBars = "ForcedVertical"
    $details.BackColor = [System.Drawing.Color]::White
    $details.ForeColor = [System.Drawing.Color]::FromArgb(35, 45, 62)
    $details.Font = $fontNormal
    $details.Text = $body -join "`r`n"
    $layout.Controls.Add($details, 0, 1)

    $buttonBar = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonBar.Dock = "Top"
    $buttonBar.FlowDirection = "RightToLeft"
    $buttonBar.WrapContents = $true
    $buttonBar.AutoScroll = $false
    $buttonBar.AutoSize = $true
    $buttonBar.AutoSizeMode = "GrowAndShrink"
    $buttonBar.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $layout.Controls.Add($buttonBar, 0, 2)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-DashboardText "common.close"
    $close.Size = New-Object System.Drawing.Size(92, 34)
    $close.Tag = "Close"
    $close.Add_Click({ param($sender,$eventArgs) $dialog.Tag = [string]$sender.Tag; Close-DashboardWorkflowSession -Dialog $dialog })
    $buttonBar.Controls.Add($close)

    $back = New-Object System.Windows.Forms.Button
    $back.Text = Get-DashboardText "common.back"
    $back.Size = New-Object System.Drawing.Size(104, 34)
    $back.Tag = "Back"
    $back.Add_Click({ param($sender,$eventArgs) $dialog.Tag = [string]$sender.Tag; $dialog.Close() })
    $dialog.CancelButton = $back
    $buttonBar.Controls.Add($back)

    $reportButton = New-Object System.Windows.Forms.Button
    $reportButton.Text = Get-DashboardText "common.openReport"
    $reportButton.Size = New-Object System.Drawing.Size(128, 34)
    $reportButton.Add_Click({
        if ($Result.ReportPath -and (Test-Path -LiteralPath $Result.ReportPath -PathType Leaf)) {
            [void](Open-ToolReportPresentation -SourcePath ([string]$Result.ReportPath) -Title (Get-DashboardText "cleanup.report.inspectionTitle") -FilePrefix "BaoCao_KhacPhucKMS_KetQua")
        }
    })
    $buttonBar.Controls.Add($reportButton)

    foreach ($next in @($nextActions | Where-Object { [string]$_.Code -ne 'OpenReport' })) {
        $actionButton = New-Object System.Windows.Forms.Button
        $actionButton.Text = [string]$next.Label
        $actionButton.AutoSize = $true
        $actionButton.MinimumSize = New-Object System.Drawing.Size(108, 34)
        $actionButton.MaximumSize = New-Object System.Drawing.Size(280, 34)
        $actionButton.Tag = [string]$next.Code
        if ([string]$next.Code -in @('ExecuteDryRunPlan','RemediateRemaining','RepairScanSources','OpenLicenseManager','ReviewVendorActivation','OpenVendorActivation','OpenVendorRepair')) {
            $actionButton.Font = $fontBold
            $actionButton.BackColor = if ([string]$next.Code -in @('OpenLicenseManager','ReviewVendorActivation','OpenVendorActivation')) { [System.Drawing.Color]::FromArgb(230, 247, 236) } else { [System.Drawing.Color]::FromArgb(255, 248, 230) }
        }
        $actionButton.Add_Click({ param($sender,$eventArgs) $dialog.Tag = [string]$sender.Tag; $dialog.Close() })
        $buttonBar.Controls.Add($actionButton)
        if (-not $dialog.AcceptButton -and [string]$next.Code -in @('ExecuteDryRunPlan','RemediateRemaining','RepairScanSources','OpenLicenseManager','ReviewVendorActivation','OpenVendorActivation','OpenVendorRepair','Recheck')) { $dialog.AcceptButton = $actionButton }
    }

    $updateResultHeaderWidth = {
        $availableWidth = [Math]::Max(120, $layout.ClientSize.Width - $layout.Padding.Horizontal)
        foreach ($label in @($heading, $subheading)) {
            if ($label.MaximumSize.Width -ne $availableWidth) {
                $label.MaximumSize = New-Object System.Drawing.Size($availableWidth, 0)
            }
        }
        $layout.PerformLayout()
    }
    $layout.Add_SizeChanged({ & $updateResultHeaderWidth })
    $dialog.Add_Shown({
        & $updateResultHeaderWidth
        $buttonBar.AutoScroll = $false
        $buttonBar.PerformLayout()
        $details.SelectionStart = 0; $details.SelectionLength = 0; $details.ScrollToCaret()
    })
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Open-CleanupEntrySession {
    param(
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")]
        [string]$ScanScope = "All"
    )

    $fixedScope = if ($ScanScope -in @("Windows", "Office", "ThirdParty")) { $ScanScope } else { "" }
    [void](Show-CleanupFunctionScreen -Mode "Cleanup" -FixedScope $fixedScope)
}

function Restore-CleanupPreExecutionSession {
    param($Result)

    $session = $script:cleanupPreviousSession
    $scope = if ($session -and [string]$session.ScanScope -in @("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")) {
        [string]$session.ScanScope
    } elseif ($Result.PSObject.Properties['ScanScope'] -and [string]$Result.ScanScope -in @("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")) {
        [string]$Result.ScanScope
    } else {
        [string]$script:cleanupScanScope
    }
    $script:cleanupScanScope = $scope
    $script:cleanupScanSnapshot = if ($Result.PSObject.Properties['ScanSnapshot']) { $Result.ScanSnapshot } else { $null }
    $script:cleanupAutoSafeMode = $false
    $script:cleanupDryRunMode = if ($session -and $session.PSObject.Properties['DryRunMode']) {
        [bool]$session.DryRunMode
    } elseif ($Result.PSObject.Properties['SimulationOnly']) {
        [bool]$Result.SimulationOnly
    } else { $false }

    # Restore against the fresh post-verification candidates only.  IDs that
    # were already handled disappear; still-valid choices remain checked.
    $currentItems = @(Get-GuiScopedCleanupItems -CleanupItems @($Result.CleanupItems) -Scope $scope)
    if ($currentItems.Count -eq 0) {
        Open-CleanupEntrySession -ScanScope $scope
        return
    }
    $requestedIds = if ($session -and $session.PSObject.Properties['SelectedIds']) {
        @($session.SelectedIds | ForEach-Object { [string]$_ })
    } elseif ($Result.PSObject.Properties['SelectedCleanupIds']) {
        @($Result.SelectedCleanupIds | ForEach-Object { [string]$_ })
    } else { @() }
    $currentIds = @($currentItems | ForEach-Object { [string]$_.Id })
    $restoredIds = @($requestedIds | Where-Object { $currentIds -contains [string]$_ } | Select-Object -Unique)
    Set-ButtonsEnabled $true
    $navigationResult = Start-CleanupDeep -CleanupItems $currentItems -SuggestedIds $restoredIds -RestoreExactSelection -ReturnNavigationResult
    if ([string]$navigationResult -eq "Back") {
        Open-CleanupEntrySession -ScanScope $scope
    }
}

function Complete-CleanupRemediation([bool]$wasDeepCleanup) {
    Set-ButtonsEnabled $true
    $completedAutoSafeMode = [bool]$script:cleanupAutoSafeMode
    $completedDryRunMode = [bool]$script:cleanupDryRunMode
    $script:cleanupAutoSafeMode = $false
    $script:cleanupDryRunMode = $false
    try {
        if ($script:cleanupSelectionFile -and (Test-Path -LiteralPath $script:cleanupSelectionFile)) {
            Remove-Item -LiteralPath $script:cleanupSelectionFile -Force -ErrorAction SilentlyContinue
        }
        $script:cleanupSelectionFile = ""
        if (-not (Test-Path -LiteralPath $script:cleanupResultFile)) {
            throw (Get-DashboardText "cleanup.remediation.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:cleanupResultFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:cleanupResultFile -Force -ErrorAction SilentlyContinue
        $script:cleanupResultFile = ""
        if ($result.PSObject.Properties['ScanScope'] -and [string]$result.ScanScope -in @("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")) {
            $script:cleanupScanScope = [string]$result.ScanScope
        }
        if ($result.PSObject.Properties['ScanSnapshot']) { $script:cleanupScanSnapshot = $result.ScanSnapshot }
        $result.CleanupItems = @(Get-GuiScopedCleanupItems -CleanupItems @($result.CleanupItems) -Scope $script:cleanupScanScope)
        $postVerificationItems = if ($result.PSObject.Properties['PostVerificationItems']) { @($result.PostVerificationItems) } else { @($result.CleanupItems) }
        $postVerificationSuggestedIds = if ($result.PSObject.Properties['PostVerificationSuggestedIds']) { @($result.PostVerificationSuggestedIds) } else { @() }
        $overallReadyForActivation = [bool]$result.ReadyForOfficialActivation
        $scopeReadyForOriginalState = if ($result.PSObject.Properties['ScopeReadyForOriginalState']) { [bool]$result.ScopeReadyForOriginalState } else { $overallReadyForActivation }
        $result | Add-Member -NotePropertyName OverallReadyForOfficialActivation -NotePropertyValue $overallReadyForActivation -Force
        $result.ReadyForOfficialActivation = $scopeReadyForOriginalState
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            Register-ToolReportPath -Path ([string]$result.ReportPath)
            Write-ProgressLog (Get-DashboardText "cleanup.report.readyOnDemand" @($result.ReportPath))
        }
        $wasSafetyBlocked = [bool](
            ($result.PSObject.Properties['DecisionCode'] -and [string]$result.DecisionCode -in @('SelectionRejected','RemediationFailed')) -or
            @($result.Actions | Where-Object { [string]$_ -match '^(?:ĐÃ KHÓA XỬ LÝ:|REMEDIATION BLOCKED:)' }).Count -gt 0
        )
        $systemChangeApplied = if ($result.PSObject.Properties['SystemChangeApplied']) { [bool]$result.SystemChangeApplied } else { $false }
        $confirmedActionCount = if ($result.PSObject.Properties['SystemChangeCount']) { [int]$result.SystemChangeCount } else { 0 }
        $timelineEventType = if ($completedDryRunMode) { 'LicenseCleanupDryRunCompleted' } else { 'LicenseCleanupCompleted' }
        [void](Write-LicenseTimelineEventSafe -EventType $timelineEventType -Source "GUI" -IsChange:([bool](-not $completedDryRunMode -and -not $wasSafetyBlocked -and $systemChangeApplied)) -Data ([ordered]@{
            SafetyBlocked=$wasSafetyBlocked
            SelectedItemCount=[int]$result.SelectedCleanupItemCount
            ConfirmedActionCount=$confirmedActionCount
            ReadyForOfficialActivation=[bool]$result.ReadyForOfficialActivation
            RemainingItemCount=[int]$postVerificationItems.Count
            BackupCreated=[bool](-not [string]::IsNullOrWhiteSpace([string]$result.BackupDirectory))
            AutomaticSafeMode=$completedAutoSafeMode
            SimulationOnly=$completedDryRunMode
            PlannedActionCount=[int]$result.PlannedActionCount
        }))
        if ($completedDryRunMode) {
            $status.Text = Get-DashboardText 'cleanup.dryRun.completedStatus' @([int]$result.PlannedActionCount)
            $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        } elseif ($wasSafetyBlocked) {
            $status.Text = Get-DashboardText "cleanup.remediation.blockedStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        } elseif ($result.PSObject.Properties['PostVerificationOutcome'] -and [string]$result.PostVerificationOutcome -eq 'FullyHandled') {
            $status.Text = Get-DashboardText 'cleanup.remediation.fullyHandledStatus'
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } elseif ([int]$result.SelectedCleanupItemCount -gt 0 -and -not $systemChangeApplied) {
            $status.Text = Get-DashboardText "cleanup.remediation.noAutomaticChangeStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        } elseif ($result.PSObject.Properties['OfficiallyLicensed'] -and [bool]$result.OfficiallyLicensed) {
            $status.Text = Get-DashboardText 'cleanup.remediation.licensedStatus'
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } elseif ([bool]$result.ReadyForOfficialActivation) {
            $status.Text = Get-DashboardText "cleanup.remediation.readyStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        } else {
            $status.Text = Get-DashboardText "cleanup.remediation.remainingStatus" @($postVerificationItems.Count)
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        Write-ProgressLog (Get-DashboardText "cleanup.remediation.completedLog" @($result.CleanupConclusion))
        if ($wasDeepCleanup -and -not [string]::IsNullOrWhiteSpace([string]$result.BackupDirectory)) {
            Write-ProgressLog (Get-DashboardText "cleanup.remediation.backupLog" @($result.BackupDirectory))
        }
        while ($true) {
            $nextChoice = Show-CleanupResultCenter -Result $result -WasDeepCleanup $wasDeepCleanup -SafetyBlocked $wasSafetyBlocked
            switch ($nextChoice) {
                "Back" {
                    Restore-CleanupPreExecutionSession -Result $result
                    return
                }
                "ExecuteDryRunPlan" {
                    $script:cleanupDryRunMode = $false
                    Write-ProgressLog (Get-DashboardText 'cleanup.dryRun.executeLog')
                    $navigation = Start-CleanupDeep -CleanupItems @($result.CleanupItems) -SuggestedIds @($result.SelectedCleanupIds) -ReturnNavigationResult
                    if ([string]$navigation -eq "Back") { continue }
                    return
                }
                "RemediateRemaining" {
                    if ($postVerificationSuggestedIds.Count -eq 0) {
                        Write-ProgressLog (Get-DashboardText 'cleanup.remediation.noRemainingSelectedLog')
                        continue
                    }
                    Write-ProgressLog (Get-DashboardText "cleanup.remediation.openRemainingLog")
                    $navigation = Start-CleanupDeep -CleanupItems @($result.CleanupItems) -SuggestedIds @($postVerificationSuggestedIds) -RestoreExactSelection -ReturnNavigationResult
                    if ([string]$navigation -eq "Back") { continue }
                    return
                }
                "ConfigureApprovedKms" {
                    if (Confirm-KmsApprovalConfiguration) {
                        Write-ProgressLog (Get-DashboardText "cleanup.remediation.kmsConfirmedLog")
                        Start-Cleanup -ReuseSessionSettings
                        return
                    }
                    $status.Text = Get-DashboardText "cleanup.remediation.kmsUnchangedStatus"
                    $status.ForeColor = [System.Drawing.Color]::DarkOrange
                    continue
                }
                "RepairScanSources" { Start-ScanSourceRepair; return }
                "Recheck" { Start-Cleanup -ReuseSessionSettings; return }
                "OpenLicenseManager" { Open-LicenseManager; return }
                { $_ -in @('ReviewVendorActivation','OpenVendorActivation','OpenVendorRepair') } {
                    $vendorAction = @($result.NextActions | Where-Object { [string]$_.Code -eq [string]$nextChoice } | Select-Object -First 1)
                    $vendorNavigation = Open-GuiVendorLicenseAction -Action $(if ($vendorAction.Count -gt 0) { $vendorAction[0] } else { $null }) -Result $result
                    if ([string]$vendorNavigation -eq "Back") { continue }
                    return
                }
                "RestoreBackup" {
                    $restoreScope = Show-LicenseScopeChooser -Mode "Restore"
                    if ([string]$restoreScope -eq "__CloseWorkflow") { return }
                    if ([string]::IsNullOrWhiteSpace([string]$restoreScope)) { continue }
                    $restoreNavigation = Start-CleanupRestore -Scope $restoreScope -ReturnNavigationResult
                    if ([string]$restoreNavigation -eq "Back") { continue }
                    return
                }
                default {
                    if (-not [bool]$result.ReadyForOfficialActivation) {
                        Write-ProgressLog (Get-DashboardText "cleanup.remediation.closedLog")
                    }
                    return
                }
            }
        }
    } catch {
        $status.Text = Get-DashboardText "cleanup.remediation.readFailed" @($_.Exception.Message)
        Write-ProgressLog (Get-DashboardText "cleanup.remediation.failureGuidance")
        Write-ProgressLog (Get-DashboardText "cleanup.remediation.versionGuidance")
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Start-OemInspect {
    if (-not (Test-Path -LiteralPath $oemScript)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "oem.moduleMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    try {
        Start-ProgressDisplay (Get-DashboardText "oem.inspect.action") (Get-DashboardText "oem.inspect.detail") $false
        Write-ProgressLog (Get-DashboardText "oem.inspect.progressLog")
        Write-ProgressLog (Get-DashboardText "oem.keyPrivacyLog")
        $script:oemDecisionFile = New-SecureRuntimePath "tool-oem-decision-"
        $output = New-ToolReportRunDirectory -Category "OEM-KiemTra"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$oemScript`" -Mode Inspect -OutputDir `"$output`" -DecisionFile `"$script:oemDecisionFile`" -Culture `"$script:dashboardCulture`""
        [void](Start-ToolModuleProcess -ModuleId "oem.inspect" -Arguments $arguments -Action (Get-DashboardText "oem.inspect.action") -Hidden)
        $status.Text = Get-DashboardText "oem.inspect.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-DashboardText "oem.inspect.startFailed" @($_.Exception.Message))
    }
}

function Start-OemApply {
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "oem.apply.integrityAction"))) { return }
    try {
        Start-ProgressDisplay (Get-DashboardText "oem.apply.action") (Get-DashboardText "oem.apply.detail") $true
        Write-ProgressLog (Get-DashboardText "oem.apply.requestAdmin")
        Write-ProgressLog (Get-DashboardText "oem.apply.preserveKeyLog")
        $script:oemDecisionFile = New-SecureRuntimePath "tool-oem-apply-result-"
        $output = New-ToolReportRunDirectory -Category "OEM-ApDung"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$oemScript`" -Mode Apply -OutputDir `"$output`" -DecisionFile `"$script:oemDecisionFile`" -Culture `"$script:dashboardCulture`""
        [void](Start-ToolModuleProcess -ModuleId "oem.apply" -Arguments $arguments -Action (Get-DashboardText "oem.apply.action") -Elevate -Hidden)
        $status.Text = Get-DashboardText "oem.apply.running"
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        if ($script:oemDecisionFile -and (Test-Path -LiteralPath $script:oemDecisionFile -PathType Leaf)) {
            Remove-Item -LiteralPath $script:oemDecisionFile -Force -ErrorAction SilentlyContinue
        }
        $script:oemDecisionFile = ""
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "oem.apply.cancelled"
        Write-ProgressLog (Get-DashboardText "common.noSystemChanges")
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-OemInspect {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:oemDecisionFile)) {
            throw (Get-DashboardText "oem.inspect.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:oemDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:oemDecisionFile -Force -ErrorAction SilentlyContinue
        $script:oemDecisionFile = ""
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            [void](Open-ToolReportPresentation -SourcePath ([string]$result.ReportPath) -Title (Get-DashboardText "oem.report.inspectTitle") -FilePrefix "BaoCao_Key_OEM_BIOS")
        }

        if (-not [bool]$result.FirmwareKeyFound) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "oem.inspect.notFoundMessage"), (Get-DashboardText "oem.inspect.notFoundTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "oem.inspect.notFoundStatus"
            Write-ProgressLog (Get-DashboardText "oem.inspect.notFoundLog")
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            return
        }

        $activation = if ([bool]$result.IsActivated) { Get-DashboardText "common.licensed" } else { Get-DashboardText "common.notLicensedConfirmed" }
        $message = Get-DashboardText "oem.inspect.foundPrompt" @($result.FirmwareKeyMasked, $result.ProductName, $result.CurrentEdition, $activation, $result.CurrentChannel, $result.CurrentPartialKey)
        $answer = [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "oem.apply.confirmTitle"), "YesNo", "Warning")
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            Start-OemApply
            return
        }
        $status.Text = Get-DashboardText "oem.inspect.declinedStatus"
        Write-ProgressLog (Get-DashboardText "oem.inspect.declinedLog")
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
    } catch {
        $status.Text = Get-DashboardText "oem.inspect.readFailed" @($_.Exception.Message)
        Write-ProgressLog (Get-DashboardText "oem.inspect.readFailedLog")
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Start-DeepLicenseScan {
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "deepScan.integrityAction"))) { return }
    if (-not (Test-Path -LiteralPath $deepScanScript)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "deepScan.moduleMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
        (Get-DashboardText "deepScan.privacyPrompt"),
        (Get-DashboardText "deepScan.privacyTitle"), "YesNoCancel", "Information")
    if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
    $privacyArgument = if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes) { " -RedactSensitive" } else { "" }
    try {
        Start-ProgressDisplay (Get-DashboardText "deepScan.action") (Get-DashboardText "deepScan.detail") $false
        Write-ProgressLog (Get-DashboardText "deepScan.progressLog")
        Write-ProgressLog (Get-DashboardText "deepScan.adminLog")
        Write-ProgressLog (Get-DashboardText "deepScan.readOnlyLog")
        $script:deepScanDecisionFile = New-SecureRuntimePath "tool-deep-license-"
        $output = New-ToolReportRunDirectory -Category "Quet-ChuyenSau"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$deepScanScript`" -OutputDir `"$output`" -ApprovedKmsServerFile `"$approvedKmsFile`" -DecisionFile `"$script:deepScanDecisionFile`" -Culture `"$script:dashboardCulture`" -NoOpen$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "license.deep-scan" -Arguments $arguments -Action (Get-DashboardText "deepScan.action") -Elevate -Hidden)
        $status.Text = Get-DashboardText "deepScan.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-DashboardText "deepScan.startFailed" @($_.Exception.Message))
    }
}

function Complete-DeepLicenseScan {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:deepScanDecisionFile)) {
            throw (Get-DashboardText "deepScan.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:deepScanDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:deepScanDecisionFile -Force -ErrorAction SilentlyContinue
        $script:deepScanDecisionFile = ""
        if ([bool]$result.AccessDenied) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "deepScan.accessDeniedMessage"), (Get-DashboardText "common.accessDeniedTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "deepScan.accessDeniedStatus"
            Write-ProgressLog (Get-DashboardText "common.noSystemChanges")
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            return
        }
        $guidanceLines = @($result.HandlingGuidance | ForEach-Object { "- $_" })
        $reviewLines = @($result.ReviewItems | Select-Object -First 3 | ForEach-Object { "- $($_.Name): $($_.Recommendation)" })
        $guidanceSummary = if ($guidanceLines.Count -gt 0) { Get-DashboardText "deepScan.guidanceSummary" @(($guidanceLines -join "`r`n")) } else { "" }
        $reviewSummary = if ($reviewLines.Count -gt 0) { Get-DashboardText "deepScan.reviewSummary" @(($reviewLines -join "`r`n")) } else { "" }
        $oemState = if ([bool]$result.OemKeyPresent) { Get-DashboardText "common.yes" } else { Get-DashboardText "common.notFound" }
        $message = Get-DashboardText "deepScan.resultSummary" @($result.Overall, $result.HighCount, $result.ReviewCount, $result.ActiveChannel, $oemState, $guidanceSummary, $reviewSummary, $result.ReportPath)
        [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "deepScan.completedTitle"), "OK", $(if ([int]$result.HighCount -gt 0) { "Warning" } else { "Information" })) | Out-Null
        [void](Open-ToolHtmlReport -Path ([string]$result.ReportPath))
        $status.Text = Get-DashboardText "deepScan.completedStatus" @($result.Overall)
        Write-ProgressLog (Get-DashboardText "deepScan.completedLog")
        $status.ForeColor = if ([int]$result.HighCount -gt 0) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::DarkGreen }
    } catch {
        $status.Text = Get-DashboardText "deepScan.readFailed" @($_.Exception.Message)
        Write-ProgressLog (Get-DashboardText "deepScan.readFailedLog")
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Start-ForensicsScan {
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "forensics.integrityAction"))) { return }
    if (-not (Test-Path -LiteralPath $forensicsScript)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "forensics.moduleMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
        (Get-DashboardText "forensics.privacyPrompt"),
        (Get-DashboardText "forensics.privacyTitle"), "YesNoCancel", "Information")
    if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
    $privacyArgument = if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes) { " -RedactSensitive" } else { "" }
    try {
        Start-ProgressDisplay (Get-DashboardText "forensics.action") (Get-DashboardText "forensics.detail") $false
        Write-ProgressLog (Get-DashboardText "forensics.progressLog")
        Write-ProgressLog (Get-DashboardText "forensics.adminLog")
        Write-ProgressLog (Get-DashboardText "forensics.readOnlyLog")
        $script:forensicsDecisionFile = New-SecureRuntimePath "tool-license-forensics-"
        $output = New-ToolReportRunDirectory -Category "Quet-Forensics"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$forensicsScript`" -OutputDir `"$output`" -ApprovedKmsServerFile `"$approvedKmsFile`" -DecisionFile `"$script:forensicsDecisionFile`" -Culture `"$script:dashboardCulture`" -NoOpen$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "forensics.scan" -Arguments $arguments -Action (Get-DashboardText "forensics.action") -Elevate -Hidden)
        $status.Text = Get-DashboardText "forensics.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "forensics.cancelled"
        Write-ProgressLog (Get-DashboardText "common.noSystemChanges")
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-ForensicsScan {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:forensicsDecisionFile)) {
            throw (Get-DashboardText "forensics.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:forensicsDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:forensicsDecisionFile -Force -ErrorAction SilentlyContinue
        $script:forensicsDecisionFile = ""
        if ([bool]$result.AccessDenied) {
            $status.Text = Get-DashboardText "forensics.accessDeniedStatus"
            Write-ProgressLog (Get-DashboardText "common.noSystemChanges")
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            return
        }
        $message = Get-DashboardText "forensics.resultSummary" @($result.Overall, $result.RiskScore, $result.RiskLevel, $result.HighCount, $result.ReviewCount, $result.NewFindingCount, $result.ResolvedFindingCount, $result.EvidenceFolder)
        $icon = if ([int]$result.RiskScore -ge 40) { "Warning" } else { "Information" }
        [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "forensics.completedTitle"), "OK", $icon) | Out-Null
        [void](Open-ToolHtmlReport -Path ([string]$result.ReportPath))
        $status.Text = Get-DashboardText "forensics.completedStatus" @($result.RiskScore, $result.RiskLevel)
        Write-ProgressLog (Get-DashboardText "forensics.completedLog")
        $status.ForeColor = if ([int]$result.RiskScore -ge 40) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::DarkGreen }
    } catch {
        $status.Text = Get-DashboardText "forensics.readFailed" @($_.Exception.Message)
        Write-ProgressLog (Get-DashboardText "forensics.readFailedLog")
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Open-LicenseManager {
    if (-not (Confirm-IntegrityForElevatedAction (Get-ToolText -Key "status.enterprise.action" -Culture $script:dashboardCulture))) { return }
    if (-not (Test-Path -LiteralPath $licenseManagerScript)) {
        $status.Text = Get-ToolText -Key "status.enterprise.missing" -Culture $script:dashboardCulture
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        return
    }
    try {
        Start-ProgressDisplay `
            (Get-ToolText -Key "status.enterprise.opening" -Culture $script:dashboardCulture) `
            (Get-ToolText -Key "status.enterprise.elevation" -Culture $script:dashboardCulture) `
            $false
        $env:TOOL_UI_THEME = $script:dashboardTheme
        $launcherPath = [string]$env:TOOL_LAUNCHER_PATH
        if ($env:TOOL_SECURE_LAUNCH -eq "1" -and -not [string]::IsNullOrWhiteSpace($launcherPath) -and (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
            [void](Get-ReadyToolModule -moduleId "license.manager" -elevatedLaunch $true)
            $enterpriseProcess = Start-Process -FilePath $launcherPath -ArgumentList "--enterprise-ui" -Verb RunAs -PassThru
            if (-not $enterpriseProcess) { throw (Get-ToolText -Key "status.enterprise.launchFailed" -Culture $script:dashboardCulture) }
            [void](Write-ToolLog -Level "AUDIT" -Event "Module.Launched" -Message (Get-ToolText -Key "status.enterprise.action" -Culture $script:dashboardCulture) -Data ([ordered]@{
                ModuleId="license.manager"; ProcessId=$enterpriseProcess.Id; LaunchMode="--enterprise-ui"; OfflineMode=[bool]$script:offlineMode
            }))
        } else {
            $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$licenseManagerScript`""
            [void](Start-DetachedToolModuleProcess -ModuleId "license.manager" -Arguments $arguments -Elevate)
        }
        $status.Text = Get-ToolText -Key "status.enterprise.opened" -Culture $script:dashboardCulture
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
        Write-ProgressLog (Get-ToolText -Key "status.enterprise.adminNotice" -Culture $script:dashboardCulture)
        Stop-ProgressDisplay $status.Text
    } catch {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            $status.Text = Get-ToolText -Key "status.enterprise.cancelled" -Culture $script:dashboardCulture
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog (Get-ToolText -Key "status.enterprise.cancelledLog" -Culture $script:dashboardCulture)
        } else {
            $status.Text = Get-ToolText -Key "status.enterprise.failed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)
            $status.ForeColor = [System.Drawing.Color]::DarkRed
            Write-ProgressLog $status.Text
        }
        Stop-ProgressDisplay $status.Text
    }
}

function Test-GuideHeading {
    param([AllowNull()][string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    $trimmed = $Line.Trim()
    if ($trimmed -match '^#{1,4}\s+(.+)$') {
        return [string]$matches[1].Trim()
    }
    if ($trimmed.Length -le 130 -and $trimmed -notmatch '^[-+*]\s+' -and $trimmed -notmatch '[.!?:;]$') {
        $lettersOnly = $trimmed -replace '[^\p{L}]', ''
        if ($lettersOnly.Length -ge 4 -and $trimmed -ceq $trimmed.ToUpperInvariant()) {
            return $trimmed
        }
    }
    return $null
}

function Convert-GuideLinesToHtml {
    param([AllowNull()][object[]]$Lines)

    $htmlBuilder = New-Object Text.StringBuilder
    $listType = ""
    $insideCode = $false
    foreach ($rawLine in @($Lines)) {
        $line = [string]$rawLine
        $trimmed = $line.Trim()
        if ($trimmed -eq '```powershell' -or $trimmed -eq '```') {
            if (-not [string]::IsNullOrWhiteSpace($listType)) {
                [void]$htmlBuilder.Append("</$listType>")
                $listType = ""
            }
            if ($insideCode) {
                [void]$htmlBuilder.Append("</code></pre>")
                $insideCode = $false
            } else {
                [void]$htmlBuilder.Append("<pre class='guide-code'><code>")
                $insideCode = $true
            }
            continue
        }
        if ($insideCode) {
            [void]$htmlBuilder.Append((ConvertTo-ToolHtmlText $line))
            [void]$htmlBuilder.Append("`n")
            continue
        }
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            if (-not [string]::IsNullOrWhiteSpace($listType)) {
                [void]$htmlBuilder.Append("</$listType>")
                $listType = ""
            }
            continue
        }

        $targetList = ""
        $itemText = ""
        if ($trimmed -match '^[-+*]\s+(.+)$') {
            $targetList = "ul"
            $itemText = [string]$matches[1]
        } elseif ($trimmed -match '^\d+[.)]\s+(.+)$') {
            $targetList = "ol"
            $itemText = [string]$matches[1]
        }
        if (-not [string]::IsNullOrWhiteSpace($targetList)) {
            if ($listType -ne $targetList) {
                if (-not [string]::IsNullOrWhiteSpace($listType)) { [void]$htmlBuilder.Append("</$listType>") }
                [void]$htmlBuilder.Append("<$targetList>")
                $listType = $targetList
            }
            [void]$htmlBuilder.Append("<li>$(ConvertTo-ToolHtmlText $itemText)</li>")
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($listType)) {
            [void]$htmlBuilder.Append("</$listType>")
            $listType = ""
        }
        [void]$htmlBuilder.Append("<p>$(ConvertTo-ToolHtmlText $trimmed)</p>")
    }
    if (-not [string]::IsNullOrWhiteSpace($listType)) { [void]$htmlBuilder.Append("</$listType>") }
    if ($insideCode) { [void]$htmlBuilder.Append("</code></pre>") }
    return $htmlBuilder.ToString()
}

function Convert-GuideSourceToSections {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$FallbackTitle
    )

    $groups = New-Object System.Collections.ArrayList
    $documentTitle = $FallbackTitle
    $currentTitle = Get-DashboardText "document.overview"
    $currentLines = New-Object System.Collections.ArrayList
    $firstHeading = $true
    foreach ($line in $Lines) {
        $headingText = Test-GuideHeading -Line ([string]$line)
        if (-not [string]::IsNullOrWhiteSpace([string]$headingText)) {
            if ($firstHeading) {
                $documentTitle = [string]$headingText
                $firstHeading = $false
                continue
            }
            # The preamble after the document title is already the overview.
            # When the first explicit heading is also Overview/Tổng quan, keep
            # both bodies in one section instead of emitting duplicate TOC rows.
            $normalizedCurrentTitle = ([string]$currentTitle).Trim().Normalize([Text.NormalizationForm]::FormKC)
            $normalizedHeadingText = ([string]$headingText).Trim().Normalize([Text.NormalizationForm]::FormKC)
            if ($groups.Count -eq 0 -and
                [string]::Equals($normalizedCurrentTitle, $normalizedHeadingText, [StringComparison]::OrdinalIgnoreCase)) {
                $currentTitle = [string]$headingText
                continue
            }
            if ($currentLines.Count -gt 0) {
                [void]$groups.Add([pscustomobject][ordered]@{
                    Title = $currentTitle
                    BodyHtml = Convert-GuideLinesToHtml -Lines @($currentLines.ToArray())
                })
                $currentLines = New-Object System.Collections.ArrayList
            }
            $currentTitle = [string]$headingText
            continue
        }
        [void]$currentLines.Add([string]$line)
    }
    if ($currentLines.Count -gt 0 -or $groups.Count -eq 0) {
        [void]$groups.Add([pscustomobject][ordered]@{
            Title = $currentTitle
            BodyHtml = Convert-GuideLinesToHtml -Lines @($currentLines.ToArray())
        })
    }
    return [pscustomobject][ordered]@{ Title=$documentTitle; Sections=@($groups.ToArray()) }
}

function Open-ToolEmbeddedDocument {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$FilePrefix,
        [Parameter(Mandatory = $true)][string]$TitleKey,
        [Parameter(Mandatory = $true)][string]$SubtitleKey,
        [Parameter(Mandatory = $true)][string]$EyebrowKey,
        [Parameter(Mandatory = $true)][string]$FooterKey,
        [Parameter(Mandatory = $true)][string]$MissingKey,
        [Parameter(Mandatory = $true)][string]$ExportingKey,
        [Parameter(Mandatory = $true)][string]$ExportingDetailKey,
        [Parameter(Mandatory = $true)][string]$ExportedKey,
        [Parameter(Mandatory = $true)][string]$ExportFailedKey
    )

    if (-not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) {
        $status.Text = Get-ToolText -Key $MissingKey -Culture $script:dashboardCulture
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        return
    }

    try {
        $documentAction = Get-ToolText -Key $ExportingKey -Culture $script:dashboardCulture
        Start-ProgressDisplay $documentAction (Get-ToolText -Key $ExportingDetailKey -Culture $script:dashboardCulture) $false
        [System.Windows.Forms.Application]::DoEvents()

        # Revision 4 invalidates renderer-3 caches that could retain a duplicate
        # Overview/Tổng quan row even after the source parser was corrected.
        $documentRendererRevision = "4"
        $sourceHash = Get-ToolSha256Hex -Path $SourceFile
        $documentDirectory = Join-Path $reportRoot "TaiLieu"
        if (-not (Test-Path -LiteralPath $documentDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $documentDirectory -Force | Out-Null
        }
        $script:lastReportDirectory = $documentDirectory
        $documentBasePath = Join-Path $documentDirectory "$FilePrefix-v$releaseVersion-$($script:dashboardCulture)"
        $htmlPath = "$documentBasePath.html"
        $pdfPath = "$documentBasePath.pdf"
        $manifestPath = "${documentBasePath}-SHA256SUMS.txt"
        $cacheValid = $false
        $pdfCacheValid = $false
        if ((Test-Path -LiteralPath $htmlPath -PathType Leaf) -and
            (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            $manifestLines = @([IO.File]::ReadAllLines($manifestPath, [Text.Encoding]::UTF8))
            $htmlHash = Get-ToolSha256Hex -Path $htmlPath
            $cacheValid = [bool](
                $manifestLines -contains "# Source-SHA256: $sourceHash" -and
                $manifestLines -contains "# Renderer-Revision: $documentRendererRevision" -and
                $manifestLines -contains "$htmlHash  $([IO.Path]::GetFileName($htmlPath))" -and
                (Test-ToolHtmlOfflineSafe -HtmlPath $htmlPath)
            )
            if ($cacheValid -and (Test-Path -LiteralPath $pdfPath -PathType Leaf)) {
                $pdfHash = Get-ToolSha256Hex -Path $pdfPath
                $pdfCacheValid = [bool]($manifestLines -contains "$pdfHash  $([IO.Path]::GetFileName($pdfPath))")
            }
        }

        if (-not $cacheValid) {
            $sourceLines = [IO.File]::ReadAllLines($SourceFile, [Text.Encoding]::UTF8)
            $fallbackTitle = Get-ToolText -Key $TitleKey -Culture $script:dashboardCulture
            $document = Convert-GuideSourceToSections -Lines $sourceLines -FallbackTitle $fallbackTitle
            $metadata = @(
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.version" -Culture $script:dashboardCulture); Value=$releaseDisplayName },
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.language" -Culture $script:dashboardCulture); Value=$script:dashboardCulture },
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.format" -Culture $script:dashboardCulture); Value="HTML / PDF · A4" }
            )
            $cards = @(
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.complete" -Culture $script:dashboardCulture); Value="100%"; Tone="ok" },
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.sections" -Culture $script:dashboardCulture); Value=[string](@($document.Sections).Count); Tone="info" },
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.lines" -Culture $script:dashboardCulture); Value=[string]$sourceLines.Count; Tone="info" }
            )
            $html = New-ToolProfessionalHtmlDocument `
                -Title ([string]$document.Title) `
                -Subtitle (Get-ToolText -Key $SubtitleKey -Culture $script:dashboardCulture) `
                -Eyebrow (Get-ToolText -Key $EyebrowKey -Culture $script:dashboardCulture) `
                -Metadata $metadata -Cards $cards -Sections @($document.Sections) `
                -Footer (Get-ToolText -Key $FooterKey -Culture $script:dashboardCulture) `
                -Culture $script:dashboardCulture -OfflineMode $true
            $documentCss = @'
.guide-code{background:#111827;border-radius:8px;color:#e5e7eb;overflow:auto;padding:12px 14px;white-space:pre-wrap}
section p{margin:6px 0}section li{margin:4px 0}section ul,section ol{padding-left:25px}
@media print{section{break-inside:auto!important}.guide-code{background:#f4f4f4!important;color:#111!important}}
'@
            $html = $html.Replace("</style>", "$documentCss`r`n</style>")
            foreach ($stalePath in @($htmlPath, $pdfPath, $manifestPath)) {
                if (Test-Path -LiteralPath $stalePath -PathType Leaf) {
                    Remove-Item -LiteralPath $stalePath -Force -ErrorAction Stop
                }
            }
            [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
            if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $htmlPath)) {
                throw (Get-DashboardText "document.offlineSafetyFailed")
            }
            $initialHashLines = @(
                "# SHA-256 local documentation package.",
                "# Source-SHA256: $sourceHash",
                "# Renderer-Revision: $documentRendererRevision",
                "$(Get-ToolSha256Hex -Path $htmlPath)  $([IO.Path]::GetFileName($htmlPath))"
            )
            [IO.File]::WriteAllLines($manifestPath, $initialHashLines, (New-Object Text.UTF8Encoding($false)))
        }

        [void](Open-ToolHtmlReport -Path $htmlPath)
        $status.Text = Get-ToolText -Key $ExportedKey -Culture $script:dashboardCulture -FormatArguments @([IO.Path]::GetFileName($htmlPath))
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
        Write-ProgressLog $status.Text
        Stop-ProgressDisplay $status.Text
        [System.Windows.Forms.Application]::DoEvents()

        if (-not $pdfCacheValid) {
            $pdfResult = Convert-ToolHtmlToPdf -HtmlPath $htmlPath -PdfPath $pdfPath
            $hashLines = @(
                "# SHA-256 local documentation package.",
                "# Source-SHA256: $sourceHash",
                "# Renderer-Revision: $documentRendererRevision",
                "$(Get-ToolSha256Hex -Path $htmlPath)  $([IO.Path]::GetFileName($htmlPath))"
            )
            if ($pdfResult.Success -and (Test-Path -LiteralPath $pdfPath -PathType Leaf)) {
                $hashLines += "$(Get-ToolSha256Hex -Path $pdfPath)  $([IO.Path]::GetFileName($pdfPath))"
                Write-ProgressLog (Get-ToolText -Key "document.pdfSaved" -Culture $script:dashboardCulture -FormatArguments @([IO.Path]::GetFileName($pdfPath)))
            } else {
                Write-ProgressLog (Get-ToolText -Key "document.pdfFailed" -Culture $script:dashboardCulture -FormatArguments @([string]$pdfResult.Error))
            }
            [IO.File]::WriteAllLines($manifestPath, $hashLines, (New-Object Text.UTF8Encoding($false)))
        } else {
            Write-ProgressLog (Get-ToolText -Key "document.cacheUsed" -Culture $script:dashboardCulture)
        }
    } catch {
        $status.Text = Get-ToolText -Key $ExportFailedKey -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
        Stop-ProgressDisplay $status.Text
    }
}

function Open-Guide {
    $selectedGuideFile = if ($script:dashboardCulture -eq "en-US") { $englishGuideFile } else { $guideFile }
    Open-ToolEmbeddedDocument `
        -SourceFile $selectedGuideFile -FilePrefix "HUONG-DAN-VietLicenSure" `
        -TitleKey "guide.title" -SubtitleKey "guide.subtitle" -EyebrowKey "guide.eyebrow" -FooterKey "guide.footer" `
        -MissingKey "guide.missing" -ExportingKey "guide.exporting" -ExportingDetailKey "guide.exportingDetail" `
        -ExportedKey "guide.exported" -ExportFailedKey "guide.exportFailed"
}

function Open-FirstRunFaq {
    $selectedFaqFile = if ($script:dashboardCulture -eq "en-US") { $englishFirstRunFaqFile } else { $firstRunFaqFile }
    Open-ToolEmbeddedDocument `
        -SourceFile $selectedFaqFile -FilePrefix "FAQ-Nguoi-Dung-Moi-VietLicenSure" `
        -TitleKey "faq.title" -SubtitleKey "faq.subtitle" -EyebrowKey "faq.eyebrow" -FooterKey "faq.footer" `
        -MissingKey "faq.missing" -ExportingKey "faq.exporting" -ExportingDetailKey "faq.exportingDetail" `
        -ExportedKey "faq.exported" -ExportFailedKey "faq.exportFailed"
}

function Open-VersionHistory {
    $hasPreviousStep = [bool]($script:dashboardDialogStack.Count -gt 0)
    $selectedHistoryFile = if ($script:dashboardCulture -eq "en-US") { $englishHistoryFile } else { $historyFile }
    if (-not (Test-Path -LiteralPath $selectedHistoryFile -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "history.missing" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "history.title" -Culture $script:dashboardCulture), "OK", "Warning") | Out-Null
        return
    }
    try {
        $dialog = New-Object System.Windows.Forms.Form
        $dialog.Text = Get-ToolText -Key "history.title" -Culture $script:dashboardCulture
        $dialog.StartPosition = "CenterParent"
        $dialog.ShowInTaskbar = $false
        $dialog.MinimizeBox = $false
        $dialog.MaximizeBox = $true
        $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
        $dialog.ClientSize = New-Object System.Drawing.Size(850, 620)
        $dialog.MinimumSize = New-Object System.Drawing.Size(620, 440)
        $dialog.Font = $fontNormal
        $dialog.Tag = "Close"

        $heading = New-Object System.Windows.Forms.Label
        $heading.Text = Get-ToolText -Key "history.eyebrow" -Culture $script:dashboardCulture
        $heading.Font = $fontTitle
        $heading.Location = New-Object System.Drawing.Point(18, 14)
        $heading.Size = New-Object System.Drawing.Size(800, 38)
        $heading.Anchor = "Top,Left,Right"
        $dialog.Controls.Add($heading)

        $historyBox = New-Object System.Windows.Forms.RichTextBox
        $historyBox.ReadOnly = $true
        $historyBox.DetectUrls = $false
        $historyBox.WordWrap = $true
        $historyBox.ScrollBars = "Vertical"
        $historyBox.Font = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.NormalSize)
        $historyBox.Location = New-Object System.Drawing.Point(18, 58)
        $historyBox.Size = New-Object System.Drawing.Size(814, 500)
        $historyBox.Anchor = "Top,Bottom,Left,Right"
        $historyBox.Text = [IO.File]::ReadAllText($selectedHistoryFile, [Text.Encoding]::UTF8)
        $dialog.Controls.Add($historyBox)

        $copyButton = New-Object System.Windows.Forms.Button
        $copyButton.Text = Get-ToolText -Key "history.copy" -Culture $script:dashboardCulture
        $copyButton.Size = New-Object System.Drawing.Size(230, 32)
        $copyButton.Location = New-Object System.Drawing.Point(18, 572)
        $copyButton.Anchor = "Bottom,Left"
        $copyButton.Add_Click({ if ($historyBox.TextLength -gt 0) { [System.Windows.Forms.Clipboard]::SetText($historyBox.Text) } })
        $dialog.Controls.Add($copyButton)

        $close = New-Object System.Windows.Forms.Button
        $close.Text = Get-ToolText -Key "common.close" -Culture $script:dashboardCulture
        $close.Size = New-Object System.Drawing.Size(120, 32)
        $close.Location = New-Object System.Drawing.Point(712, 572)
        $close.Anchor = "Bottom,Right"
        $close.Add_Click({ $dialog.Tag = "Close"; Close-DashboardWorkflowSession -Dialog $dialog })
        $dialog.Controls.Add($close)
        $dialog.AcceptButton = $close
        if ($hasPreviousStep) {
            $back = New-Object System.Windows.Forms.Button
            $back.Text = Get-ToolText -Key "common.back" -Culture $script:dashboardCulture
            $back.Size = New-Object System.Drawing.Size(120, 32)
            $back.Location = New-Object System.Drawing.Point(584, 572)
            $back.Anchor = "Bottom,Right"
            $back.Add_Click({ $dialog.Tag = "Back"; $dialog.Close() })
            $dialog.Controls.Add($back)
            $dialog.CancelButton = $back
        } else {
            $dialog.CancelButton = $close
        }
        Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
        [void](Show-DashboardModalDialog -Dialog $dialog)
        $navigation = [string]$dialog.Tag
        $historyBox.Font.Dispose()
        $dialog.Dispose()
        if ($navigation -eq "Close" -and $hasPreviousStep -and -not (Test-DashboardWorkflowCloseRequested)) {
            $previousDialog = Get-DashboardDialogOwner
            if ($previousDialog -and -not [object]::ReferenceEquals($previousDialog, $form)) {
                Close-DashboardWorkflowSession -Dialog $previousDialog
            }
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "history.openFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)),
            (Get-ToolText -Key "history.title" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
    }
}

function Show-AdvancedScanMenu {
    $chooser = New-Object System.Windows.Forms.Form
    $chooser.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $chooser.Text = Get-ToolText -Key "advanced.form.title" -Culture $script:dashboardCulture
    $chooser.StartPosition = "CenterParent"
    $chooser.FormBorderStyle = "FixedDialog"
    $chooser.MaximizeBox = $false
    $chooser.MinimizeBox = $false
    $chooser.ShowInTaskbar = $false
    $chooser.ClientSize = New-Object System.Drawing.Size(590, 248)
    $chooser.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $chooser.Font = $fontNormal
    $chooser.Tag = ""

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ToolText -Key "advanced.heading" -Culture $script:dashboardCulture
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $heading.Location = New-Object System.Drawing.Point(20, 12)
    $heading.Size = New-Object System.Drawing.Size(550, 34)
    $chooser.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-ToolText -Key "advanced.hint" -Culture $script:dashboardCulture
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.TextAlign = "MiddleCenter"
    $hint.Location = New-Object System.Drawing.Point(28, 48)
    $hint.Size = New-Object System.Drawing.Size(534, 32)
    $chooser.Controls.Add($hint)

    $deepButton = New-Object System.Windows.Forms.Button
    $deepButton.Text = Get-ToolText -Key "advanced.deep.title" -Culture $script:dashboardCulture
    $deepButton.Font = $fontBold
    $deepButton.TextAlign = "MiddleLeft"
    $deepButton.Location = New-Object System.Drawing.Point(34, 88)
    $deepButton.Size = New-Object System.Drawing.Size(522, 42)
    $deepButton.BackColor = [System.Drawing.Color]::FromArgb(234, 242, 255)
    $deepButton.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $deepButton.FlatStyle = "Flat"
    $deepButton.Add_Click({ $chooser.Tag = "Deep"; $chooser.Close() })
    $chooser.Controls.Add($deepButton)

    $forensicsButton = New-Object System.Windows.Forms.Button
    $forensicsButton.Text = Get-ToolText -Key "advanced.forensics.title" -Culture $script:dashboardCulture
    $forensicsButton.Font = $fontBold
    $forensicsButton.TextAlign = "MiddleLeft"
    $forensicsButton.Location = New-Object System.Drawing.Point(34, 136)
    $forensicsButton.Size = New-Object System.Drawing.Size(522, 42)
    $forensicsButton.BackColor = [System.Drawing.Color]::FromArgb(232, 247, 240)
    $forensicsButton.ForeColor = [System.Drawing.Color]::FromArgb(20, 96, 66)
    $forensicsButton.FlatStyle = "Flat"
    $forensicsButton.Add_Click({ $chooser.Tag = "Forensics"; $chooser.Close() })
    $chooser.Controls.Add($forensicsButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-ToolText -Key "common.close" -Culture $script:dashboardCulture
    $cancelButton.Location = New-Object System.Drawing.Point(448, 194)
    $cancelButton.Size = New-Object System.Drawing.Size(108, 32)
    $cancelButton.Add_Click({ $chooser.Tag = ""; Close-DashboardWorkflowSession -Dialog $chooser })
    $chooser.CancelButton = $cancelButton
    $chooser.Controls.Add($cancelButton)

    Set-ToolWindowTheme -Root $chooser -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $chooser)
    $choice = [string]$chooser.Tag
    $chooser.Dispose()
    if ($choice -eq "Deep") { Start-DeepLicenseScan; return }
    if ($choice -eq "Forensics") { Start-ForensicsScan; return }
    $status.Text = Get-DashboardText "advanced.cancelled"
    $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
}

function Start-CleanupBackup {
    param([ValidateSet("All", "Windows", "Office", "ThirdParty")][string]$Scope = "All")
    $script:backupScope = $Scope
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "backup.integrityAction"))) { return }
    if (-not (Test-Path -LiteralPath $backupScript -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "backup.moduleMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    try {
        Start-ProgressDisplay (Get-DashboardText "backup.action") (Get-DashboardText "backup.detail") $true
        $output = New-ToolReportRunDirectory -Category "SaoLuu-BanQuyen"
        $script:backupResultFile = New-SecureRuntimePath "tool-license-backup-result-"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$backupScript`" -OutputDir `"$output`" -DecisionFile `"$script:backupResultFile`" -Scope `"$script:backupScope`" -Culture `"$script:dashboardCulture`""
        [void](Start-ToolModuleProcess -ModuleId "backup.create" -Arguments $arguments -Action (Get-DashboardText "backup.action") -Elevate)
        $status.Text = Get-DashboardText "backup.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Write-ProgressLog (Get-DashboardText "backup.readOnlyLog")
        Write-ProgressLog (Get-DashboardText "backup.scopeLog" @((Get-CleanupScopeLabel -Scope $script:backupScope)))
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "backup.cancelled"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-CleanupBackup {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:backupResultFile -PathType Leaf)) {
            throw (Get-DashboardText "backup.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:backupResultFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:backupResultFile -Force -ErrorAction SilentlyContinue
        $script:backupResultFile = ""
        $message = Get-DashboardText "backup.resultSummary" @($result.Message, $result.ItemCount, $result.ErrorCount, $result.BackupDirectory)
        if ([bool]$result.Success) {
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "backup.completedTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "backup.completedStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "backup.warningTitle"), "OK", "Warning") | Out-Null
            $status.Text = Get-DashboardText "backup.warningStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        Write-ProgressLog (Get-DashboardText "backup.pathLog" @($result.BackupDirectory))
        Write-ProgressLog (Get-DashboardText "backup.securityLog")
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            Register-ToolReportPath -Path ([string]$result.ReportPath)
            Write-ProgressLog (Get-DashboardText "cleanup.report.readyOnDemand" @($result.ReportPath))
        }
    } catch {
        $status.Text = Get-DashboardText "backup.readFailed" @($_.Exception.Message)
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
    }
}

function Get-RestoreUiItemScope($Item) {
    $kind = [string]$Item.Kind
    $combined = "$kind|$([string]$Item.Name)|$([string]$Item.OriginalPath)"
    if ($kind -match '^ThirdParty' -or $combined -match '(?i)ThirdPartyInventory|InstalledSoftware') { return "ThirdParty" }
    if ($kind -match '^Office' -or $combined -match '(?i)OfficeSoftwareProtectionPlatform|\bospp(?:svc|\.vbs)?\b|Office_SPP') { return "Office" }
    if ($kind -match '^Windows' -or $combined -match '(?i)Windows NT\\CurrentVersion\\SoftwareProtectionPlatform|\bsppsvc\b|SppExtComObj|Windows_SPP|NoGenTicket') { return "Windows" }
    return "WindowsOfficeShared"
}

function Get-RestoreUiItemsForScope {
    param($Items, [ValidateSet("All", "Windows", "Office", "ThirdParty")][string]$Scope)
    $allItems = @($Items)
    switch ($Scope) {
        "Windows" { return @($allItems | Where-Object { (Get-RestoreUiItemScope $_) -in @("Windows", "WindowsOfficeShared") }) }
        "Office" { return @($allItems | Where-Object { (Get-RestoreUiItemScope $_) -in @("Office", "WindowsOfficeShared") }) }
        "ThirdParty" { return @($allItems | Where-Object { (Get-RestoreUiItemScope $_) -eq "ThirdParty" }) }
        default { return $allItems }
    }
}

function Show-RestorePreview($manifest, [string]$backupDir, [ValidateSet("All", "Windows", "Office", "ThirdParty")][string]$Scope = "All") {
    $items = @(Get-RestoreUiItemsForScope -Items @($manifest.Items) -Scope $Scope)
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "restore.preview.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(840, [Math]::Min(1100, $workArea.Width - 70))
    $dialogHeight = [Math]::Max(560, [Math]::Min(680, $workArea.Height - 70))
    $dialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(840, $dialogWidth), [Math]::Min(560, $dialogHeight))
    $dialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Font = $fontNormal
    $dialog.Tag = "Close"

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "restore.preview.heading" @($items.Count)
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.Location = New-Object System.Drawing.Point(18, 12)
    $heading.Size = New-Object System.Drawing.Size(($dialogWidth - 36), 36)
    $heading.TextAlign = "MiddleCenter"
    $heading.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($heading)

    $sourceLabel = New-Object System.Windows.Forms.Label
    $sourceLabel.Text = Get-DashboardText "restore.preview.source" @($backupDir)
    $sourceLabel.Location = New-Object System.Drawing.Point(20, 50)
    $sourceLabel.Size = New-Object System.Drawing.Size(($dialogWidth - 40), 24)
    $sourceLabel.AutoEllipsis = $true
    $sourceLabel.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($sourceLabel)

    $list = New-Object System.Windows.Forms.ListView
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.HideSelection = $false
    $list.ShowItemToolTips = $true
    $list.Location = New-Object System.Drawing.Point(20, 78)
    $list.Size = New-Object System.Drawing.Size(($dialogWidth - 40), ($dialogHeight - 170))
    $list.Anchor = "Top,Bottom,Left,Right"
    [void]$list.Columns.Add((Get-DashboardText "common.type"), 125)
    [void]$list.Columns.Add((Get-DashboardText "common.name"), 220)
    [void]$list.Columns.Add((Get-DashboardText "restore.preview.originalLocation"), 390)
    [void]$list.Columns.Add((Get-DashboardText "restore.preview.handling"), 140)
    $resizeRestoreColumns = {
        $usable = [Math]::Max(620, $list.ClientSize.Width - 8)
        $list.Columns[0].Width = 125
        $list.Columns[1].Width = [Math]::Max(220, [Math]::Floor(($usable - 265) * 0.34))
        $list.Columns[3].Width = 140
        $list.Columns[2].Width = [Math]::Max(260, $usable - $list.Columns[0].Width - $list.Columns[1].Width - $list.Columns[3].Width)
    }
    $list.Add_Resize($resizeRestoreColumns)
    foreach ($item in $items) {
        $explicitlyNotRestorable = [bool]($item.PSObject.Properties['Restorable'] -and -not [bool]$item.Restorable)
        $action = if ($explicitlyNotRestorable) { Get-DashboardText "restore.preview.notRestorable" } elseif ([string]$item.Type -eq "Defender") { Get-DashboardText "restore.preview.safeSkip" } elseif ([string]$item.Type -eq "LicenseNotice") { Get-DashboardText "restore.preview.notRestorable" } else { Get-DashboardText "restore.preview.restorable" }
        $row = New-Object System.Windows.Forms.ListViewItem([string]$item.Type)
        [void]$row.SubItems.Add([string]$item.Name)
        [void]$row.SubItems.Add([string]$item.OriginalPath)
        [void]$row.SubItems.Add($action)
        $row.ToolTipText = "$([string]$item.Name)`r`n$([string]$item.OriginalPath)`r`n$action"
        [void]$list.Items.Add($row)
    }
    $dialog.Controls.Add($list)
    & $resizeRestoreColumns

    $note = New-Object System.Windows.Forms.Label
    $note.Text = Get-DashboardText "restore.preview.note"
    $note.Location = New-Object System.Drawing.Point(20, ($dialogHeight - 82))
    $note.Size = New-Object System.Drawing.Size(($dialogWidth - 462), 64)
    $note.Anchor = "Bottom,Left,Right"
    $dialog.Controls.Add($note)

    $confirm = New-Object System.Windows.Forms.Button
    $confirm.Text = Get-DashboardText "restore.preview.confirm"
    $confirm.Font = $fontBold
    $confirm.Location = New-Object System.Drawing.Point(($dialogWidth - 428), ($dialogHeight - 58))
    $confirm.Size = New-Object System.Drawing.Size(188, 38)
    $confirm.Anchor = "Bottom,Right"
    $confirm.Add_Click({ $dialog.Tag = "Confirm"; $dialog.Close() })
    $dialog.Controls.Add($confirm)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = Get-DashboardText "common.back"
    $cancel.Location = New-Object System.Drawing.Point(($dialogWidth - 232), ($dialogHeight - 58))
    $cancel.Size = New-Object System.Drawing.Size(104, 38)
    $cancel.Anchor = "Bottom,Right"
    $cancel.Add_Click({ $dialog.Tag = "Back"; $dialog.Close() })
    $dialog.CancelButton = $cancel
    $dialog.Controls.Add($cancel)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-DashboardText "common.close"
    $close.Location = New-Object System.Drawing.Point(($dialogWidth - 120), ($dialogHeight - 58))
    $close.Size = New-Object System.Drawing.Size(104, 38)
    $close.Anchor = "Bottom,Right"
    $close.Add_Click({ $dialog.Tag = "Close"; Close-DashboardWorkflowSession -Dialog $dialog })
    $dialog.Controls.Add($close)

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $navigation = [string]$dialog.Tag
    $dialog.Dispose()
    return $navigation
}

function Start-CleanupRestore {
    param(
        [ValidateSet("All", "Windows", "Office", "ThirdParty")][string]$Scope = "All",
        [string]$BackupDirectory = "",
        [switch]$ReturnNavigationResult
    )
    $formatRestoreResult = {
        param([ValidateSet("Started", "Back", "Close")][string]$Navigation)
        if ($ReturnNavigationResult) { return $Navigation }
        return [bool]($Navigation -eq "Started")
    }
    $script:restoreScope = $Scope
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "restore.integrityAction"))) { return (& $formatRestoreResult "Back") }
    if (-not (Test-Path -LiteralPath $restoreScript -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "restore.moduleMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return (& $formatRestoreResult "Back")
    }
    $dataRoot = if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_DATA_ROOT)) { [string]$env:TOOL_DATA_ROOT } else { Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "ThanhViet-VietLicenSure\v4.6" }
    $secureBackupRoot = Join-Path $dataRoot "backups"
    $backupDir = ""
    if (-not [string]::IsNullOrWhiteSpace($BackupDirectory)) {
        try {
            $backupDir = [IO.Path]::GetFullPath($BackupDirectory)
            if (-not (Test-ToolResultPathWithinRoot -Path $backupDir -Root $secureBackupRoot)) { throw "OutsideProtectedBackupRoot" }
        } catch {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "restore.invalidSelectedBackup" @($_.Exception.Message)), (Get-DashboardText "restore.invalidFolderTitle"), "OK", "Warning") | Out-Null
            return (& $formatRestoreResult "Back")
        }
    } else {
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = Get-DashboardText "restore.pickerDescription"
        $picker.ShowNewFolderButton = $false
        if (Test-Path -LiteralPath $secureBackupRoot -PathType Container) { $picker.SelectedPath = $secureBackupRoot }
        if ($picker.ShowDialog((Get-DashboardDialogOwner)) -ne [System.Windows.Forms.DialogResult]::OK) {
            $picker.Dispose()
            return (& $formatRestoreResult "Back")
        }
        $backupDir = $picker.SelectedPath
        $picker.Dispose()
    }
    $manifestPath = Join-Path $backupDir "RESTORE-MANIFEST.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "restore.manifestMissing"), (Get-DashboardText "restore.invalidFolderTitle"), "OK", "Warning") | Out-Null
        return (& $formatRestoreResult "Back")
    }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $scopedRestoreItems = @(Get-RestoreUiItemsForScope -Items @($manifest.Items) -Scope $script:restoreScope)
        $itemCount = $scopedRestoreItems.Count
        if ([string]$manifest.SchemaVersion -ne "2.0" -or [string]$manifest.ToolVersion -ne $toolVersion) { throw (Get-DashboardText "restore.versionMismatch" @($toolVersion)) }
    } catch {
        $manifestError = Get-DashboardText "restore.manifestInvalid" @($_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($manifestError, (Get-DashboardText "restore.manifestInvalidTitle"), "OK", "Error") | Out-Null
        return (& $formatRestoreResult "Back")
    }
    if ($itemCount -eq 0) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "restore.noItems"), (Get-DashboardText "restore.noItemsTitle"), "OK", "Information") | Out-Null
        return (& $formatRestoreResult "Back")
    }
    $previewNavigation = Show-RestorePreview -manifest $manifest -backupDir $backupDir -Scope $script:restoreScope
    if ([string]$previewNavigation -ne "Confirm") {
        if ([string]$previewNavigation -eq "Close" -and
            $script:dashboardDialogStack.Count -gt 0 -and
            -not (Test-DashboardWorkflowCloseRequested)) {
            $previousDialog = Get-DashboardDialogOwner
            if ($previousDialog -and -not [object]::ReferenceEquals($previousDialog, $form)) {
                Close-DashboardWorkflowSession -Dialog $previousDialog
            }
        }
        return (& $formatRestoreResult $(if ([string]$previewNavigation -eq "Close") { "Close" } else { "Back" }))
    }

    try {
        Start-ProgressDisplay (Get-DashboardText "restore.action") (Get-DashboardText "restore.detail") $true
        $script:restoreResultFile = New-SecureRuntimePath "tool-license-restore-result-"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$restoreScript`" -BackupDir `"$backupDir`" -DecisionFile `"$script:restoreResultFile`" -Scope `"$script:restoreScope`" -Culture `"$script:dashboardCulture`""
        [void](Start-ToolModuleProcess -ModuleId "restore.apply" -Arguments $arguments -Action (Get-DashboardText "restore.action") -Elevate)
        $status.Text = Get-DashboardText "restore.running"
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Write-ProgressLog (Get-DashboardText "restore.runningLog" @($itemCount, $backupDir))
        Write-ProgressLog (Get-DashboardText "restore.scopeLog" @((Get-CleanupScopeLabel -Scope $script:restoreScope)))
        Set-ButtonsEnabled $false
        $timer.Start()
        return (& $formatRestoreResult "Started")
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "restore.cancelled"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Stop-ProgressDisplay $status.Text
        return (& $formatRestoreResult "Back")
    }
}

function Complete-CleanupRestore {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:restoreResultFile -PathType Leaf)) {
            throw (Get-DashboardText "restore.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:restoreResultFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:restoreResultFile -Force -ErrorAction SilentlyContinue
        $script:restoreResultFile = ""
        [void](Write-LicenseTimelineEventSafe -EventType "LicenseRestoreCompleted" -Source "GUI" -IsChange:([bool]([int]$result.RestoredCount -gt 0)) -Data ([ordered]@{
            Success=[bool]$result.Success
            RestoredCount=[int]$result.RestoredCount
            SkippedCount=[int]$result.SkippedCount
            ErrorCount=[int]$result.ErrorCount
        }))
        $restoreNextStep = if ([int]$result.ErrorCount -gt 0) { Get-DashboardText "restore.failureNextStep" } else { Get-DashboardText "restore.successNextStep" }
        $message = Get-DashboardText "restore.resultSummary" @($result.Message, $result.RestoredCount, $result.SkippedCount, $result.ErrorCount, $restoreNextStep, $result.ReportPath)
        if ([bool]$result.Success) {
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "restore.completedTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "restore.completedStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "restore.warningTitle"), "OK", "Warning") | Out-Null
            $status.Text = Get-DashboardText "restore.warningStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        Write-ProgressLog $message
        if (Test-Path -LiteralPath $result.ReportPath) {
            Register-ToolReportPath -Path ([string]$result.ReportPath)
            Write-ProgressLog (Get-DashboardText "cleanup.report.readyOnDemand" @($result.ReportPath))
        }
    } catch {
        $status.Text = Get-DashboardText "restore.readFailed" @($_.Exception.Message)
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
        Write-ProgressLog (Get-DashboardText "restore.failureGuidance")
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "restore.failureMessage" @($status.Text)), (Get-DashboardText "restore.failureTitle"), "OK", "Error") | Out-Null
    }
}

function Show-CleanupScopeChecklist {
    $scopeDialog = New-Object System.Windows.Forms.Form
    $scopeDialog.Text = Get-DashboardText "cleanup.scope.dialogTitle" @($releaseDisplayName)
    $scopeDialog.StartPosition = "CenterParent"
    $scopeDialog.FormBorderStyle = "Sizable"
    $scopeDialog.MaximizeBox = $false
    $scopeDialog.MinimizeBox = $false
    $scopeDialog.ShowInTaskbar = $false
    $scopeDialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(680, [Math]::Min(820, $workArea.Width - 70))
    $dialogHeight = [Math]::Max(430, [Math]::Min(470, $workArea.Height - 70))
    $scopeDialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(680, $dialogWidth), [Math]::Min(430, $dialogHeight))
    $scopeDialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $scopeDialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $scopeDialog.Font = $fontNormal
    $scopeDialog.Tag = "__CloseWorkflow"

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(18, 12, 18, 12)
    $layout.ColumnCount = 1
    $layout.RowCount = 6
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 66)))
    foreach ($unused in 1..3) {
        [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 68)))
    }
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $scopeDialog.Controls.Add($layout)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "cleanup.scope.cleanupHeading"
    $heading.Dock = "Fill"
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $layout.Controls.Add($heading, 0, 0)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-DashboardText "cleanup.scope.cleanupHint"
    $hint.Dock = "Fill"
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.TextAlign = "MiddleLeft"
    $layout.Controls.Add($hint, 0, 1)

    $checkDefinitions = @(
        [pscustomobject]@{ Name="Windows"; TextKey="cleanup.scope.scanWindows" },
        [pscustomobject]@{ Name="Office"; TextKey="cleanup.scope.scanOffice" },
        [pscustomobject]@{ Name="ThirdParty"; TextKey="cleanup.scope.scanThirdParty" }
    )
    $scopeChecks = @{}
    [int]$rowIndex = 2
    foreach ($definition in $checkDefinitions) {
        $scopeCheck = New-Object System.Windows.Forms.CheckBox
        $scopeCheck.Name = "cleanupScope$([string]$definition.Name)"
        $scopeCheck.Text = Get-DashboardText ([string]$definition.TextKey)
        $scopeCheck.Tag = [string]$definition.Name
        $scopeCheck.Dock = "Fill"
        $scopeCheck.Margin = New-Object System.Windows.Forms.Padding(16, 5, 16, 5)
        $scopeCheck.Padding = New-Object System.Windows.Forms.Padding(16, 0, 12, 0)
        $scopeCheck.Font = $fontBold
        $scopeCheck.TextAlign = "MiddleLeft"
        $scopeCheck.CheckAlign = "MiddleLeft"
        $scopeCheck.AutoCheck = $true
        $scopeCheck.ThreeState = $false
        $scopeChecks[[string]$definition.Name] = $scopeCheck
        $layout.Controls.Add($scopeCheck, 0, $rowIndex)
        $rowIndex++
    }

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = "Fill"
    $footer.FlowDirection = "RightToLeft"
    $footer.WrapContents = $false
    $footer.Padding = New-Object System.Windows.Forms.Padding(0, 8, 8, 0)
    $layout.Controls.Add($footer, 0, 5)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = Get-DashboardText "common.close"
    $closeButton.Font = $fontBold
    $closeButton.Size = New-Object System.Drawing.Size(104, 38)
    $closeButton.Add_Click({
        $scopeDialog.Tag = "__CloseWorkflow"
        Close-DashboardWorkflowSession -Dialog $scopeDialog
    })
    $footer.Controls.Add($closeButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-DashboardText "common.back"
    $cancelButton.Font = $fontBold
    $cancelButton.Size = New-Object System.Drawing.Size(132, 38)
    $cancelButton.Add_Click({ $scopeDialog.Tag = ""; $scopeDialog.Close() })
    $scopeDialog.CancelButton = $cancelButton
    $footer.Controls.Add($cancelButton)

    $continueButton = New-Object System.Windows.Forms.Button
    $continueButton.Text = Get-DashboardText "common.continue"
    $continueButton.Font = $fontBold
    $continueButton.Size = New-Object System.Drawing.Size(156, 38)
    $continueButton.Enabled = $false
    $continueButton.BackColor = [System.Drawing.Color]::FromArgb(234, 242, 255)
    $continueButton.Add_Click({
        $scopeDialog.Tag = ConvertTo-CleanupScanScope `
            -Windows ([bool]$scopeChecks['Windows'].Checked) `
            -Office ([bool]$scopeChecks['Office'].Checked) `
            -ThirdParty ([bool]$scopeChecks['ThirdParty'].Checked)
        if (-not [string]::IsNullOrWhiteSpace([string]$scopeDialog.Tag)) { $scopeDialog.Close() }
    })
    $footer.Controls.Add($continueButton)
    $scopeDialog.AcceptButton = $continueButton

    $updateContinueState = {
        $continueButton.Enabled = [bool]($scopeChecks['Windows'].Checked -or $scopeChecks['Office'].Checked -or $scopeChecks['ThirdParty'].Checked)
    }
    foreach ($scopeCheck in $scopeChecks.Values) { $scopeCheck.Add_CheckedChanged($updateContinueState) }

    Set-ToolWindowTheme -Root $scopeDialog -Mode $script:dashboardTheme
    $scopeDialog.Add_Shown({ $scopeChecks['Windows'].Focus() })
    [void](Show-DashboardModalDialog -Dialog $scopeDialog)
    $scope = [string]$scopeDialog.Tag
    $scopeDialog.Dispose()
    return $scope
}

function Show-LicenseScopeChooser {
    param([ValidateSet("Cleanup", "Backup", "Restore")][string]$Mode)

    if ($Mode -eq "Cleanup") { return Show-CleanupScopeChecklist }

    $options = if ($Mode -eq "Backup") {
        @(
            [pscustomobject]@{ Scope="All"; TextKey="cleanup.scope.backupAll" },
            [pscustomobject]@{ Scope="Windows"; TextKey="cleanup.scope.backupWindows" },
            [pscustomobject]@{ Scope="Office"; TextKey="cleanup.scope.backupOffice" },
            [pscustomobject]@{ Scope="ThirdParty"; TextKey="cleanup.scope.backupThirdParty" }
        )
    } else {
        @(
            [pscustomobject]@{ Scope="All"; TextKey="cleanup.scope.restoreAll" },
            [pscustomobject]@{ Scope="Windows"; TextKey="cleanup.scope.restoreWindows" },
            [pscustomobject]@{ Scope="Office"; TextKey="cleanup.scope.restoreOffice" },
            [pscustomobject]@{ Scope="ThirdParty"; TextKey="cleanup.scope.restoreThirdParty" }
        )
    }
    $headingKey = "cleanup.scope.$($Mode.ToLowerInvariant())Heading"
    $hintKey = "cleanup.scope.$($Mode.ToLowerInvariant())Hint"

    $scopeDialog = New-Object System.Windows.Forms.Form
    $scopeDialog.Text = Get-DashboardText "cleanup.scope.dialogTitle" @($releaseDisplayName)
    $scopeDialog.StartPosition = "CenterParent"
    $scopeDialog.FormBorderStyle = "Sizable"
    $scopeDialog.MaximizeBox = $false
    $scopeDialog.MinimizeBox = $false
    $scopeDialog.ShowInTaskbar = $false
    $scopeDialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $desiredHeight = 226 + ($options.Count * 66)
    $dialogWidth = [Math]::Max(680, [Math]::Min(820, $workArea.Width - 70))
    $dialogHeight = [Math]::Max(410, [Math]::Min($desiredHeight, $workArea.Height - 70))
    $scopeDialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(680, $dialogWidth), [Math]::Min(410, $dialogHeight))
    $scopeDialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $scopeDialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $scopeDialog.Font = $fontNormal
    $scopeDialog.Tag = "__CloseWorkflow"

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(18, 12, 18, 12)
    $layout.ColumnCount = 1
    $layout.RowCount = 3 + $options.Count
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
    foreach ($unused in $options) {
        [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 66)))
    }
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $scopeDialog.Controls.Add($layout)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText $headingKey
    $heading.Dock = "Fill"
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $layout.Controls.Add($heading, 0, 0)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-DashboardText $hintKey
    $hint.Dock = "Fill"
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.TextAlign = "MiddleLeft"
    $layout.Controls.Add($hint, 0, 1)

    $optionIndex = 0
    foreach ($option in $options) {
        $scopeButton = New-Object System.Windows.Forms.Button
        $scopeButton.Text = Get-DashboardText ([string]$option.TextKey)
        $scopeButton.Tag = [string]$option.Scope
        $scopeButton.Dock = "Fill"
        $scopeButton.Margin = New-Object System.Windows.Forms.Padding(16, 5, 16, 5)
        $scopeButton.Font = $fontBold
        $scopeButton.TextAlign = "MiddleLeft"
        $scopeButton.Add_Click({
            param($sender, $eventArgs)
            $scopeDialog.Tag = [string]$sender.Tag
            $scopeDialog.Close()
        })
        $layout.Controls.Add($scopeButton, 0, (2 + $optionIndex))
        $optionIndex++
    }

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = "Fill"
    $footer.FlowDirection = "RightToLeft"
    $footer.WrapContents = $false
    $footer.AutoScroll = $true
    $footer.Padding = New-Object System.Windows.Forms.Padding(0, 8, 8, 0)
    $layout.Controls.Add($footer, 0, (2 + $options.Count))

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = Get-DashboardText "common.close"
    $closeButton.Font = $fontBold
    $closeButton.Size = New-Object System.Drawing.Size(104, 38)
    $closeButton.Add_Click({
        $scopeDialog.Tag = "__CloseWorkflow"
        Close-DashboardWorkflowSession -Dialog $scopeDialog
    })
    $footer.Controls.Add($closeButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-DashboardText "common.back"
    $cancelButton.Font = $fontBold
    $cancelButton.Size = New-Object System.Drawing.Size(132, 38)
    $cancelButton.Add_Click({ $scopeDialog.Tag = ""; $scopeDialog.Close() })
    $scopeDialog.CancelButton = $cancelButton
    $footer.Controls.Add($cancelButton)

    Set-ToolWindowTheme -Root $scopeDialog -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $scopeDialog)
    $scope = [string]$scopeDialog.Tag
    $scopeDialog.Dispose()
    return $scope
}

function Show-CleanupFunctionScreen {
    param(
        [ValidateSet("Backup","Cleanup","Restore","AutoCleanup")][string]$Mode,
        [ValidateSet("", "Windows", "Office", "ThirdParty")][string]$FixedScope = "",
        [switch]$AllowBack
    )

    $hasPreviousStep = [bool]($AllowBack -or $script:dashboardDialogStack.Count -gt 0)
    $titleKeys = @{
        Backup="cleanup.menu.backupTitle"
        Cleanup="cleanup.menu.cleanupTitle"
        Restore="cleanup.menu.restoreTitle"
        AutoCleanup="cleanup.menu.autoTitle"
    }
    $descriptionKeys = @{
        Backup="cleanup.menu.backupDescription"
        Cleanup="cleanup.menu.cleanupDescription"
        Restore="cleanup.menu.restoreDescription"
        AutoCleanup="cleanup.menu.autoDescription"
    }
    if ($Mode -eq "Cleanup" -and -not [string]::IsNullOrWhiteSpace($FixedScope)) {
        switch ($FixedScope) {
            "Windows" {
                $titleKeys["Cleanup"] = "menu.11.title"
                $descriptionKeys["Cleanup"] = "menu.11.description"
            }
            "Office" {
                $titleKeys["Cleanup"] = "menu.12.title"
                $descriptionKeys["Cleanup"] = "menu.12.description"
            }
            "ThirdParty" {
                $titleKeys["Cleanup"] = "menu.13.title"
                $descriptionKeys["Cleanup"] = "menu.13.description"
            }
        }
    }
    $actionKeys = @{ Backup="cleanup.menu.backupAction"; Cleanup="cleanup.menu.cleanupAction"; Restore="cleanup.menu.restoreAction"; AutoCleanup="cleanup.menu.autoAction" }

    $screen = New-Object System.Windows.Forms.Form
    $screen.Text = Get-DashboardText $titleKeys[$Mode]
    $screen.StartPosition = "CenterParent"
    $screen.FormBorderStyle = "Sizable"
    $screen.MaximizeBox = $false
    $screen.MinimizeBox = $false
    $screen.ShowInTaskbar = $false
    $screen.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $screenWidth = [Math]::Max(680, [Math]::Min(780, $workArea.Width - 70))
    $screenHeight = [Math]::Max(360, [Math]::Min($(if ($Mode -eq "Cleanup") { 410 } else { 380 }), $workArea.Height - 70))
    $screen.MinimumSize = New-Object System.Drawing.Size([Math]::Min(680, $screenWidth), [Math]::Min(360, $screenHeight))
    $screen.ClientSize = New-Object System.Drawing.Size($screenWidth, $screenHeight)
    $screen.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $screen.Font = $fontNormal
    $screen.Tag = "Close"

    $screenLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $screenLayout.Dock = "Fill"
    $screenLayout.Padding = New-Object System.Windows.Forms.Padding(22, 14, 22, 14)
    $screenLayout.ColumnCount = 1
    $screenLayout.RowCount = 3
    [void]$screenLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$screenLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 62)))
    [void]$screenLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$screenLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $(if ($Mode -eq "Cleanup") { 74 } else { 58 }))))
    $screen.Controls.Add($screenLayout)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText $titleKeys[$Mode]
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $heading.Dock = "Fill"
    $screenLayout.Controls.Add($heading, 0, 0)

    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = Get-DashboardText $descriptionKeys[$Mode]
    if (-not [string]::IsNullOrWhiteSpace($FixedScope)) {
        $descriptionLabel.Text += "`r`n`r`n" + (Get-DashboardText "cleanup.menu.fixedScopeNote" @((Get-CleanupScopeLabel -Scope $FixedScope)))
    }
    $descriptionLabel.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $descriptionLabel.TextAlign = "MiddleLeft"
    $descriptionLabel.Dock = "Fill"
    $descriptionLabel.Padding = New-Object System.Windows.Forms.Padding(18, 8, 18, 8)
    $screenLayout.Controls.Add($descriptionLabel, 0, 1)

    $footer = if ($Mode -eq "Cleanup") {
        $cleanupFooter = New-Object System.Windows.Forms.TableLayoutPanel
        $cleanupFooter.ColumnCount = 1
        $cleanupFooter.RowCount = 1
        $cleanupFooter.GrowStyle = [System.Windows.Forms.TableLayoutPanelGrowStyle]::FixedSize
        [void]$cleanupFooter.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $cleanupFooter
    } else {
        $standardFooter = New-Object System.Windows.Forms.FlowLayoutPanel
        $standardFooter.FlowDirection = "RightToLeft"
        $standardFooter.WrapContents = $false
        $standardFooter.AutoScroll = $false
        $standardFooter
    }
    $footer.Dock = "Fill"
    $footer.Padding = New-Object System.Windows.Forms.Padding(0, 7, 0, 0)
    $screenLayout.Controls.Add($footer, 0, 2)
    $footerButtons = New-Object System.Collections.ArrayList

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = Get-DashboardText "common.close"
    $closeButton.Font = $fontTile
    $closeButton.Size = New-Object System.Drawing.Size($(if ($Mode -eq "Cleanup") { 96 } else { 104 }), 44)
    $closeButton.Add_Click({
        $screen.Tag = "Close"
        Close-DashboardWorkflowSession -Dialog $screen
    })
    [void]$footerButtons.Add($closeButton)

    if ($hasPreviousStep) {
        $backButton = New-Object System.Windows.Forms.Button
        $backButton.Text = Get-DashboardText "common.back"
        $backButton.Font = $fontTile
        $backButton.Size = New-Object System.Drawing.Size($(if ($Mode -eq "Cleanup") { 104 } else { 132 }), 44)
        $backButton.Add_Click({ $screen.Tag = "Back"; $screen.Close() })
        $screen.CancelButton = $backButton
        [void]$footerButtons.Add($backButton)
    } else {
        $screen.CancelButton = $closeButton
    }

    $runChoice = {
        param([ValidateSet("Action", "DryRun", "Online")][string]$Choice)

        if (Test-DashboardWorkflowCloseRequested) { return }
        if ($Mode -eq "AutoCleanup") {
            $autoScope = if ([string]::IsNullOrWhiteSpace($FixedScope)) { "All" } else { $FixedScope }
            Start-Cleanup -AutoSafeMode -ScanScope $autoScope
            $screen.Tag = "Started"
            $screen.Close()
            return
        }

        $scopeMode = if ($Mode -eq "Cleanup") { "Cleanup" } elseif ($Mode -eq "Backup") { "Backup" } else { "Restore" }
        $selectedScope = if ([string]::IsNullOrWhiteSpace($FixedScope)) {
            Show-LicenseScopeChooser -Mode $scopeMode
        } else {
            $FixedScope
        }
        if (Test-DashboardWorkflowCloseRequested) { return }
        if ([string]$selectedScope -eq "__CloseWorkflow") {
            Close-DashboardWorkflowSession -Dialog $screen
            return
        }
        if ([string]::IsNullOrWhiteSpace([string]$selectedScope)) {
            # Back from scope selection leaves this functional step visible.
            return
        }

        $started = $true
        if ($Mode -eq "Cleanup" -and $Choice -eq "Online") {
            Start-SoftwareCatalogOnlineUpdate -ScanScope $selectedScope
        } elseif ($Mode -eq "Backup") {
            Start-CleanupBackup -Scope $selectedScope
        } elseif ($Mode -eq "Cleanup") {
            Start-Cleanup -ScanScope $selectedScope -DryRunMode:([bool]($Choice -eq "DryRun"))
        } elseif ($Mode -eq "Restore") {
            $started = [bool](Start-CleanupRestore -Scope $selectedScope)
        }
        if (Test-DashboardWorkflowCloseRequested) { return }
        if ($started) {
            $screen.Tag = "Started"
            $screen.Close()
        }
    }

    $actionButton = New-Object System.Windows.Forms.Button
    $actionButton.Text = if ($Mode -eq "Cleanup") { Get-DashboardText 'cleanup.menu.cleanupActionCompact' } else { Get-DashboardText $actionKeys[$Mode] }
    $actionButton.Font = $fontTile
    $actionButton.Size = New-Object System.Drawing.Size($(if ($Mode -eq "Cleanup") { 148 } else { 250 }), 44)
    $actionButton.BackColor = [System.Drawing.Color]::FromArgb(234, 242, 255)
    $actionButton.Add_Click({ & $runChoice "Action" })
    [void]$footerButtons.Add($actionButton)

    if ($Mode -eq "Cleanup") {
        $dryRunButton = New-Object System.Windows.Forms.Button
        $dryRunButton.Text = Get-DashboardText 'cleanup.dryRun.buttonCompact'
        $dryRunButton.Font = $fontTile
        $dryRunButton.Size = New-Object System.Drawing.Size(118, 44)
        $dryRunButton.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 230)
        $dryRunButton.Add_Click({ & $runChoice "DryRun" })
        [void]$footerButtons.Add($dryRunButton)

        if ($FixedScope -notin @("Windows", "Office")) {
            $onlineButton = New-Object System.Windows.Forms.Button
            $onlineButton.Text = Get-DashboardText "software.online.buttonCompact"
            $onlineButton.Font = $fontTile
            $onlineButton.Size = New-Object System.Drawing.Size(144, 44)
            $onlineButton.BackColor = [System.Drawing.Color]::FromArgb(232, 247, 240)
            $onlineButton.Add_Click({ & $runChoice "Online" })
            [void]$footerButtons.Add($onlineButton)
        }
    }

    if ($Mode -eq "Cleanup") {
        $footer.ColumnCount = [Math]::Max(1, $footerButtons.Count)
        $footer.ColumnStyles.Clear()
        $columnPercent = [single](100.0 / [Math]::Max(1, $footerButtons.Count))
        for ($buttonIndex = $footerButtons.Count - 1; $buttonIndex -ge 0; $buttonIndex--) {
            [void]$footer.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, $columnPercent)))
            $footerButton = $footerButtons[$buttonIndex]
            $footerButton.Dock = "Fill"
            $footerButton.Margin = New-Object System.Windows.Forms.Padding(3)
            $footerButton.TextAlign = "MiddleCenter"
            $footerButton.Tag = 'ToolUiCompactTextOnly'
            $footer.Controls.Add($footerButton, (($footerButtons.Count - 1) - $buttonIndex), 0)
        }
    } else {
        foreach ($footerButton in $footerButtons) { $footer.Controls.Add($footerButton) }
    }

    Set-ToolWindowTheme -Root $screen -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $screen)
    $choice = [string]$screen.Tag
    $screen.Dispose()
    if ($choice -eq "Close" -and $hasPreviousStep -and -not (Test-DashboardWorkflowCloseRequested)) {
        $previousDialog = Get-DashboardDialogOwner
        if ($previousDialog -and -not [object]::ReferenceEquals($previousDialog, $form)) {
            Close-DashboardWorkflowSession -Dialog $previousDialog
        }
    }
    return [bool]($choice -eq "Started")
}

function Show-CleanupMenu {
    param([ValidateSet("", "Windows", "Office", "ThirdParty")][string]$FixedScope = "")
    $fixedScopeLabel = if ([string]::IsNullOrWhiteSpace($FixedScope)) { "" } else { Get-CleanupScopeLabel -Scope $FixedScope }
    $chooser = New-Object System.Windows.Forms.Form
        $chooser.Text = Get-DashboardText "cleanup.menu.title"
        $chooser.StartPosition = "CenterParent"
        $chooser.FormBorderStyle = "Sizable"
        $chooser.MaximizeBox = $false
        $chooser.MinimizeBox = $false
        $chooser.ShowInTaskbar = $false
        $chooser.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
        $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
        $chooserWidth = [Math]::Max(700, [Math]::Min(820, $workArea.Width - 70))
        $chooserHeight = [Math]::Max(470, [Math]::Min(540, $workArea.Height - 70))
        $chooser.MinimumSize = New-Object System.Drawing.Size([Math]::Min(700, $chooserWidth), [Math]::Min(470, $chooserHeight))
        $chooser.ClientSize = New-Object System.Drawing.Size($chooserWidth, $chooserHeight)
        $chooser.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
        $chooser.Font = $fontNormal
        $chooser.Tag = ""

        $layout = New-Object System.Windows.Forms.TableLayoutPanel
        $layout.Dock = "Fill"
        $layout.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 12)
        $layout.ColumnCount = 1
        $layout.RowCount = 6
        [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 82)))
        foreach ($unused in 1..4) { [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 66))) }
        [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $chooser.Controls.Add($layout)

        $heading = New-Object System.Windows.Forms.Label
        $heading.Text = if ([string]::IsNullOrWhiteSpace($fixedScopeLabel)) {
            Get-DashboardText "cleanup.menu.heading"
        } else {
            Get-DashboardText "cleanup.menu.fixedScopeHeading" @($fixedScopeLabel)
        }
        $heading.Font = $fontTitle
        $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        $heading.TextAlign = "MiddleCenter"
        $heading.Dock = "Fill"
        $layout.Controls.Add($heading, 0, 0)

        $menuOptions = @(
            [pscustomobject]@{ Code="Backup"; TextKey="cleanup.menu.backupTitle"; Color=[System.Drawing.Color]::FromArgb(232, 247, 240) },
            [pscustomobject]@{ Code="Cleanup"; TextKey="cleanup.menu.cleanupFullTitle"; Color=[System.Drawing.Color]::FromArgb(255, 248, 230) },
            [pscustomobject]@{ Code="Restore"; TextKey="cleanup.menu.restoreTitle"; Color=[System.Drawing.Color]::FromArgb(234, 242, 255) },
            [pscustomobject]@{ Code="AutoCleanup"; TextKey="cleanup.menu.autoFullTitle"; Color=[System.Drawing.Color]::FromArgb(255, 238, 238) }
        )
        $menuIndex = 0
        foreach ($menuOption in $menuOptions) {
            $menuButton = New-Object System.Windows.Forms.Button
            $menuButton.Text = Get-DashboardText ([string]$menuOption.TextKey)
            $menuButton.Tag = [string]$menuOption.Code
            $menuButton.Font = $fontBold
            $menuButton.TextAlign = "MiddleLeft"
            $menuButton.Dock = "Fill"
            $menuButton.Margin = New-Object System.Windows.Forms.Padding(18, 5, 18, 5)
            $menuButton.BackColor = $menuOption.Color
            $menuButton.Add_Click({
                param($sender, $eventArgs)
                $selectedMode = [string]$sender.Tag
                if (Show-CleanupFunctionScreen -Mode $selectedMode -FixedScope $FixedScope) {
                    $chooser.Tag = "Started"
                    $chooser.Close()
                }
            })
            $layout.Controls.Add($menuButton, 0, (1 + $menuIndex))
            $menuIndex++
        }

        $footer = New-Object System.Windows.Forms.FlowLayoutPanel
        $footer.Dock = "Fill"
        $footer.FlowDirection = "RightToLeft"
        $footer.WrapContents = $false
        $footer.Padding = New-Object System.Windows.Forms.Padding(0, 10, 10, 0)
        $layout.Controls.Add($footer, 0, 5)

        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = Get-DashboardText "common.close"
        $cancelButton.Font = $fontBold
        $cancelButton.Size = New-Object System.Drawing.Size(132, 40)
        $cancelButton.Add_Click({ Close-DashboardWorkflowSession -Dialog $chooser })
        $chooser.CancelButton = $cancelButton
        $footer.Controls.Add($cancelButton)

        Set-ToolWindowTheme -Root $chooser -Mode $script:dashboardTheme
        [void](Show-DashboardModalDialog -Dialog $chooser)
        $choice = [string]$chooser.Tag
        $chooser.Dispose()
        if ([string]$choice -ne "Started" -and -not (Test-DashboardWorkflowCloseRequested)) {
            $status.Text = Get-DashboardText "status.chooseTask"
            $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
        }
}
