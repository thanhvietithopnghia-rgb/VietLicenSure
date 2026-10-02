# VietLicenSure v5.0 - dot-sourced function library
# Extracted mechanically from Giao-Dien.ps1; contains function definitions only.
# Keep this file beside its compatible entrypoint.

function Get-ApprovedKmsEntries {
    $entries = New-Object System.Collections.Generic.List[string]
    $invalid = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $approvedKmsFile -PathType Leaf)) {
        return [pscustomobject]@{ Exists=$false; Entries=@(); Invalid=@(); Path=$approvedKmsFile }
    }
    try {
        foreach ($line in Get-Content -LiteralPath $approvedKmsFile -ErrorAction Stop) {
            $value = ([string]$line).Trim()
            if (-not $value -or $value.StartsWith('#')) { continue }
            $candidate = $value -replace '^\[([^\]]+)\](?::\d+)?$', '$1'
            $candidate = $candidate -replace '^([^:]+):\d+$', '$1'
            if ($candidate -match '^[a-zA-Z0-9][a-zA-Z0-9._-]*(?:\.[a-zA-Z0-9][a-zA-Z0-9._-]*)*$' -or
                $candidate -match '^(?:\d{1,3}\.){3}\d{1,3}$' -or
                $candidate -match '^[0-9a-fA-F:]+$') {
                [void]$entries.Add($value)
            } else {
                [void]$invalid.Add($value)
            }
        }
    } catch { [void]$invalid.Add((Get-DashboardText "kms.readFailed" @($_.Exception.Message))) }
    return [pscustomobject]@{ Exists=$true; Entries=@($entries | Select-Object -Unique); Invalid=@($invalid); Path=$approvedKmsFile }
}

function Get-DetectedKmsServers {
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform',
        'HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform'
    )) {
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            foreach ($name in @('KeyManagementServiceName','DiscoveredKeyManagementServiceName')) {
                $value = [string]$item.$name
                if ($value -and $value -notmatch '^(localhost|127\.0\.0\.1|::1)$') { [void]$found.Add($value.Trim()) }
            }
        } catch {}
    }
    try {
        $slmgr = Get-ToolNativeSystemPath 'slmgr.vbs'
        if (Test-Path -LiteralPath $slmgr) {
            $text = (& $nativeCscriptPath //nologo $slmgr /dlv 2>$null) -join "`n"
            foreach ($pattern in @('(?im)^\s*KMS machine name from DNS:\s*(.+)$','(?im)^\s*Key Management Service machine name:\s*(.+)$','(?im)^\s*KMS machine IP address:\s*(.+)$')) {
                if ($text -match $pattern -and $matches[1].Trim() -notmatch '^(not available|localhost)$') { [void]$found.Add($matches[1].Trim()) }
            }
        }
    } catch {}
    return @($found | Where-Object { $_ } | Select-Object -Unique)
}

function Normalize-KmsServer([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    $candidate = $value.Trim().ToLowerInvariant()
    $candidate = $candidate -replace '^\[([^\]]+)\](?::\d+)?$', '$1'
    $candidate = $candidate -replace '^([^:]+):\d+$', '$1'
    return $candidate
}

function Test-DetectedKmsIsApproved([string]$server, [string[]]$approved) {
    $candidate = Normalize-KmsServer $server
    if (-not $candidate) { return $false }
    foreach ($entry in @($approved)) {
        if ($candidate -eq (Normalize-KmsServer $entry)) { return $true }
    }
    return $false
}

function Save-ApprovedKmsEntries([string[]]$entries) {
    try {
        $parent = Split-Path -Parent $approvedKmsFile
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $content = @(
            (Get-DashboardText "kms.file.header")
            (Get-DashboardText "kms.file.hint")
            (Get-DashboardText "kms.file.updated" @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
            @($entries | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
        )
        Set-Content -LiteralPath $approvedKmsFile -Value $content -Encoding UTF8 -Force
        if ($approvedKmsFile -ne $bundledApprovedKmsFile) {
            Set-Content -LiteralPath $bundledApprovedKmsFile -Value $content -Encoding UTF8 -Force
        }
        [void](Write-LicenseTimelineEventSafe -EventType "ApprovedKmsListUpdated" -Source "GUI" -IsChange:$true -Data ([ordered]@{
            ApprovedServerCount=@($entries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique).Count
            ServerNamesStoredInTimeline=$false
        }))
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "kms.saveFailed" @($_.Exception.Message)),
            (Get-DashboardText "kms.saveFailedTitle"), "OK", "Error") | Out-Null
        return $false
    }
}

function Confirm-KmsApprovalConfiguration {
    $config = Get-ApprovedKmsEntries
    $detected = @(Get-DetectedKmsServers)
    $unapprovedDetected = @($detected | Where-Object { -not (Test-DetectedKmsIsApproved $_ $config.Entries) })
    if ($config.Entries.Count -gt 0 -and $config.Invalid.Count -eq 0 -and $unapprovedDetected.Count -eq 0) { return $true }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.Text = Get-DashboardText "kms.dialog.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false; $dialog.ShowInTaskbar = $false
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(620, [Math]::Min(920, $workArea.Width - 36))
    $dialogHeight = [Math]::Max(440, [Math]::Min(540, $workArea.Height - 48))
    $dialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(720, $dialogWidth), [Math]::Min(440, $dialogHeight))
    $dialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244,246,249); $dialog.Font = $fontNormal

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.Padding = New-Object System.Windows.Forms.Padding(18, 14, 18, 14)
    $layout.ColumnCount = 1
    $layout.RowCount = 5
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $dialog.Controls.Add($layout)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "kms.dialog.heading"
    $heading.Font = $fontBold; $heading.ForeColor = [System.Drawing.Color]::DarkRed
    $heading.AutoSize = $true; $heading.Dock = 'Fill'; $heading.Margin = New-Object System.Windows.Forms.Padding(4, 2, 4, 8)
    $heading.MaximumSize = New-Object System.Drawing.Size(($dialogWidth - 52), 0)
    $layout.Controls.Add($heading, 0, 0)
    $info = New-Object System.Windows.Forms.Label
    $detectedText = if ($detected.Count) { $detected -join ', ' } else { Get-DashboardText "kms.dialog.noneDetected" }
    $unapprovedText = if ($unapprovedDetected.Count) { Get-DashboardText "kms.dialog.unapproved" @(($unapprovedDetected -join ', ')) } else { '' }
    $info.Text = Get-DashboardText "kms.dialog.summary" @($detectedText, $unapprovedText)
    $info.AutoSize = $true; $info.Dock = 'Fill'; $info.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 8)
    $info.MaximumSize = New-Object System.Drawing.Size(($dialogWidth - 52), 0)
    $layout.Controls.Add($info, 0, 1)
    $editor = New-Object System.Windows.Forms.TextBox
    $editor.Multiline = $true; $editor.ScrollBars = 'Vertical'; $editor.Font = $fontSmall
    $editor.Dock = 'Fill'; $editor.MinimumSize = New-Object System.Drawing.Size(300, 140)
    $editor.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 8)
    $editor.Text = (@($config.Entries) -join [Environment]::NewLine)
    $layout.Controls.Add($editor, 0, 2)
    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-DashboardText "kms.dialog.hint"
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(102,112,133)
    $hint.AutoSize = $true; $hint.Dock = 'Fill'; $hint.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 4)
    $hint.MaximumSize = New-Object System.Drawing.Size(($dialogWidth - 52), 0)
    $layout.Controls.Add($hint, 0, 3)

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = 'Fill'; $footer.AutoSize = $true; $footer.AutoSizeMode = 'GrowAndShrink'
    $footer.FlowDirection = 'LeftToRight'; $footer.WrapContents = $true
    $footer.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
    $footer.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $layout.Controls.Add($footer, 0, 4)

    $open = New-Object System.Windows.Forms.Button; $open.Text = Get-DashboardText "kms.dialog.openFile"
    $open.AutoSize = $true; $open.AutoSizeMode = 'GrowAndShrink'; $open.MinimumSize = New-Object System.Drawing.Size(150, 36); $open.Margin = New-Object System.Windows.Forms.Padding(4)
    $open.Add_Click({ Start-Process -FilePath $nativeNotepadPath -ArgumentList ('"' + $approvedKmsFile + '"') }); $footer.Controls.Add($open)
    $strict = New-Object System.Windows.Forms.Button; $strict.Text = Get-DashboardText "kms.dialog.strict"
    $strict.AutoSize = $true; $strict.AutoSizeMode = 'GrowAndShrink'; $strict.MinimumSize = New-Object System.Drawing.Size(184, 36); $strict.Margin = New-Object System.Windows.Forms.Padding(4)
    $strict.Add_Click({ $dialog.Tag = 'Strict'; $dialog.Close() }); $footer.Controls.Add($strict)
    $save = New-Object System.Windows.Forms.Button; $save.Text = Get-DashboardText "kms.dialog.save"; $save.Font = $fontBold
    $save.AutoSize = $true; $save.AutoSizeMode = 'GrowAndShrink'; $save.MinimumSize = New-Object System.Drawing.Size(150, 36); $save.Margin = New-Object System.Windows.Forms.Padding(4)
    $save.Add_Click({ $dialog.Tag = 'Save'; $dialog.Close() }); $footer.Controls.Add($save)
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = Get-DashboardText "app.close"
    $cancel.AutoSize = $true; $cancel.AutoSizeMode = 'GrowAndShrink'; $cancel.MinimumSize = New-Object System.Drawing.Size(108, 36); $cancel.Margin = New-Object System.Windows.Forms.Padding(4)
    $cancel.Add_Click({ $dialog.Tag = 'Cancel'; $dialog.Close() }); $dialog.CancelButton = $cancel; $footer.Controls.Add($cancel)

    $resizeKmsText = {
        $maximumTextWidth = [Math]::Max(300, $layout.ClientSize.Width - $layout.Padding.Horizontal - 12)
        $heading.MaximumSize = New-Object System.Drawing.Size($maximumTextWidth, 0)
        $info.MaximumSize = New-Object System.Drawing.Size($maximumTextWidth, 0)
        $hint.MaximumSize = New-Object System.Drawing.Size($maximumTextWidth, 0)
        $layout.PerformLayout()
    }
    $dialog.Add_SizeChanged($resizeKmsText)
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    & $resizeKmsText
    $footer.PerformLayout()
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $choice = [string]$dialog.Tag; $entriesToSave = @($editor.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $dialog.Dispose()
    if ($choice -eq 'Save') {
        if ($entriesToSave.Count -eq 0) {
            $confirm = [System.Windows.Forms.MessageBox]::Show(
                (Get-DashboardText "kms.empty.confirm"),
                (Get-DashboardText "kms.empty.title"), 'YesNo', 'Warning')
            if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
        }
        if (-not (Save-ApprovedKmsEntries $entriesToSave)) { return $false }
        Write-ProgressLog (Get-DashboardText "kms.updated" @($approvedKmsFile))
        return $true
    }
    if ($choice -eq 'Strict') { Write-ProgressLog (Get-DashboardText "kms.strictContinued"); return $true }
    return $false
}

function Get-Sha256([string]$path) {
    try {
        if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
            return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        }
        $stream = [IO.File]::OpenRead($path)
        try {
            $sha = [Security.Cryptography.SHA256]::Create()
            return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant()
        } finally {
            $stream.Dispose()
        }
    } catch { return "" }
}

function Test-ToolIntegrity {
    if (-not (Test-Path -LiteralPath $integrityManifest)) {
        return [pscustomobject]@{ Checked=$false; Valid=$false; Message=(Get-DashboardText "integrity.manifestMissing") }
    }
    $problems = New-Object System.Collections.Generic.List[string]
    $required = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($requiredName in $requiredIntegrityFiles) { [void]$required.Add($requiredName) }
    try {
        foreach ($line in Get-Content -LiteralPath $integrityManifest -ErrorAction Stop) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
            if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?(.+)$') {
                $problems.Add((Get-DashboardText "integrity.invalidManifestLine" @($line)))
                continue
            }
            $expected = $matches[1].ToUpperInvariant()
            $relativeName = $matches[2].Trim()
            if ([IO.Path]::GetFileName($relativeName) -ne $relativeName -or $relativeName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
                $problems.Add((Get-DashboardText "integrity.unsafeManifestName" @($relativeName)))
                continue
            }
            if (-not $required.Contains($relativeName)) {
                $problems.Add((Get-DashboardText "integrity.unexpectedFile" @($relativeName)))
                continue
            }
            if (-not $seen.Add($relativeName)) {
                $problems.Add((Get-DashboardText "integrity.duplicateFile" @($relativeName)))
                continue
            }
            $target = Join-Path $baseDir $relativeName
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                $problems.Add((Get-DashboardText "integrity.fileMissing" @($relativeName)))
                continue
            }
            $actual = Get-Sha256 $target
            if (-not $actual -or $actual -ne $expected) { $problems.Add((Get-DashboardText "integrity.hashMismatch" @($relativeName))) }
        }
        foreach ($requiredName in $requiredIntegrityFiles) {
            if (-not $seen.Contains($requiredName)) { $problems.Add((Get-DashboardText "integrity.requiredEntryMissing" @($requiredName))) }
        }
    } catch {
        return [pscustomobject]@{ Checked=$false; Valid=$false; Message=(Get-DashboardText "integrity.manifestReadFailed" @($_.Exception.Message)) }
    }
    if ($problems.Count -eq 0) {
        return [pscustomobject]@{ Checked=$true; Valid=$true; Message=(Get-DashboardText "integrity.valid") }
    }
    return [pscustomobject]@{ Checked=$true; Valid=$false; Message=(Get-DashboardText "integrity.warning" @(($problems -join '; '))) }
}

function New-SecureRuntimePath([string]$prefix) {
    if (-not (Test-Path -LiteralPath $runtimeDir -PathType Container)) {
        New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
    }
    return (Join-Path $runtimeDir ($prefix + [guid]::NewGuid().ToString("N") + ".json"))
}

function Confirm-IntegrityForElevatedAction([string]$actionName) {
    if ($env:TOOL_SECURE_LAUNCH -ne "1" -or -not (Test-ProtectedToolDirectoryAcl $baseDir)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "integrity.adminSourceBlocked" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "integrity.adminBlockedTitle" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
        return $false
    }
    if (-not (Test-ProtectedToolDirectoryAcl $runtimeDir)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "integrity.runtimeBlocked" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "integrity.protectionTitle" -Culture $script:dashboardCulture),
            "OK",
            "Error"
        ) | Out-Null
        return $false
    }
    $env:TOOL_SECURE_RUNTIME_FAILED = "0"
    $freshResult = Test-ToolIntegrity
    if ($freshResult.Valid) { return $true }
    Write-ProgressLog (Get-DashboardText "integrity.blockedLog" @($actionName, $freshResult.Message))
    $status.Text = Get-ToolText -Key "integrity.statusBlocked" -Culture $script:dashboardCulture
    $status.ForeColor = [System.Drawing.Color]::DarkRed
    [System.Windows.Forms.MessageBox]::Show(
        (Get-ToolText -Key "integrity.actionBlocked" -Culture $script:dashboardCulture -FormatArguments @($actionName, $freshResult.Message)),
        (Get-ToolText -Key "integrity.protectionTitle" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
    return $false
}

function Test-ProcessingTimelineWindowOpen {
    return [bool]($script:processingTimelineForm -and -not $script:processingTimelineForm.IsDisposed)
}

function Add-ProcessingTimelineEntry {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Timestamp = '',
        [int]$Percent = -1
    )
    if (-not $script:processingTimelineCapturing -or -not (Test-ProcessingTimelineWindowOpen) -or
        $null -eq $script:processingTimelineList -or $script:processingTimelineList.IsDisposed) { return }
    if ([string]::IsNullOrWhiteSpace($Timestamp)) { $Timestamp = (Get-Date).ToString('HH:mm:ss') }
    if ($Percent -lt 0) {
        $Percent = if ($script:processingTimelineProgressBar) { [int]$script:processingTimelineProgressBar.Value } else { 0 }
    }
    $row = New-Object System.Windows.Forms.ListViewItem($Timestamp)
    [void]$row.SubItems.Add(('{0}%' -f [Math]::Max(0, [Math]::Min(100, $Percent))))
    [void]$row.SubItems.Add($Message)
    [void]$script:processingTimelineList.Items.Add($row)
    while ($script:processingTimelineList.Items.Count -gt 500) { $script:processingTimelineList.Items.RemoveAt(0) }
    $row.EnsureVisible()
}

function Update-ProcessingTimelineProgress {
    param([int]$Percent, [string]$Summary, [string]$ElapsedText = '')
    if (-not (Test-ProcessingTimelineWindowOpen)) { return }
    if ($script:processingTimelineProgressBar -and -not $script:processingTimelineProgressBar.IsDisposed) {
        $script:processingTimelineProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Percent))
    }
    if ($script:processingTimelineStatus -and -not $script:processingTimelineStatus.IsDisposed -and
        -not [string]::IsNullOrWhiteSpace($Summary)) {
        $script:processingTimelineStatus.Text = $Summary
    }
    if ($script:processingTimelineElapsed -and -not $script:processingTimelineElapsed.IsDisposed) {
        $script:processingTimelineElapsed.Text = $ElapsedText
    }
}

function Refresh-ProcessingTimelineLocalization {
    if (-not (Test-ProcessingTimelineWindowOpen)) { return }
    $script:processingTimelineForm.Text = Get-DashboardText 'processingTimeline.title'
    if ($script:processingTimelineHeading) { $script:processingTimelineHeading.Text = Get-DashboardText 'processingTimeline.heading' }
    if ($script:processingTimelineList -and $script:processingTimelineList.Columns.Count -ge 3) {
        $script:processingTimelineList.Columns[0].Text = Get-DashboardText 'processingTimeline.time'
        $script:processingTimelineList.Columns[1].Text = Get-DashboardText 'processingTimeline.progress'
        $script:processingTimelineList.Columns[2].Text = Get-DashboardText 'processingTimeline.step'
    }
    if ($script:processingTimelineStopButton) { $script:processingTimelineStopButton.Text = Get-DashboardText 'progress.stop' }
    if ($script:processingTimelineCloseButton) { $script:processingTimelineCloseButton.Text = Get-DashboardText 'common.close' }
}

function Show-ProcessingTimelineWindow {
    param([string]$Action)

    if (-not (Test-ProcessingTimelineWindowOpen)) {
        $timelineForm = New-Object System.Windows.Forms.Form
        $timelineForm.StartPosition = 'CenterParent'
        $timelineForm.FormBorderStyle = 'Sizable'
        $timelineForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
        $timelineForm.MinimumSize = New-Object System.Drawing.Size(720, 440)
        $timelineForm.ClientSize = New-Object System.Drawing.Size(840, 500)
        $timelineForm.ShowInTaskbar = $false
        $timelineForm.Font = $fontNormal

        $timelineHeading = New-Object System.Windows.Forms.Label
        $timelineHeading.Font = $fontTitle
        $timelineHeading.Location = New-Object System.Drawing.Point(20, 14)
        $timelineHeading.Size = New-Object System.Drawing.Size(800, 34)
        $timelineHeading.Anchor = 'Top,Left,Right'
        $timelineHeading.TextAlign = 'MiddleLeft'
        $timelineForm.Controls.Add($timelineHeading)

        $timelineStatus = New-Object System.Windows.Forms.Label
        $timelineStatus.Location = New-Object System.Drawing.Point(20, 52)
        $timelineStatus.Size = New-Object System.Drawing.Size(710, 42)
        $timelineStatus.Anchor = 'Top,Left,Right'
        $timelineStatus.TextAlign = 'MiddleLeft'
        $timelineStatus.AutoEllipsis = $true
        $timelineForm.Controls.Add($timelineStatus)

        $timelineElapsed = New-Object System.Windows.Forms.Label
        $timelineElapsed.Location = New-Object System.Drawing.Point(735, 52)
        $timelineElapsed.Size = New-Object System.Drawing.Size(85, 42)
        $timelineElapsed.Anchor = 'Top,Right'
        $timelineElapsed.TextAlign = 'MiddleRight'
        $timelineForm.Controls.Add($timelineElapsed)

        $timelineProgress = New-Object System.Windows.Forms.ProgressBar
        $timelineProgress.Location = New-Object System.Drawing.Point(20, 98)
        $timelineProgress.Size = New-Object System.Drawing.Size(800, 18)
        $timelineProgress.Anchor = 'Top,Left,Right'
        $timelineProgress.Minimum = 0
        $timelineProgress.Maximum = 100
        $timelineProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
        $timelineForm.Controls.Add($timelineProgress)

        $timelineList = New-Object System.Windows.Forms.ListView
        $timelineList.Location = New-Object System.Drawing.Point(20, 128)
        $timelineList.Size = New-Object System.Drawing.Size(800, 310)
        $timelineList.Anchor = 'Top,Bottom,Left,Right'
        $timelineList.View = [System.Windows.Forms.View]::Details
        $timelineList.FullRowSelect = $true
        $timelineList.GridLines = $true
        $timelineList.HideSelection = $false
        [void]$timelineList.Columns.Add('', 90)
        [void]$timelineList.Columns.Add('', 82)
        [void]$timelineList.Columns.Add('', 620)
        $timelineForm.Controls.Add($timelineList)

        $timelineClose = New-Object System.Windows.Forms.Button
        $timelineClose.Location = New-Object System.Drawing.Point(700, 452)
        $timelineClose.Size = New-Object System.Drawing.Size(120, 34)
        $timelineClose.Anchor = 'Bottom,Right'
        $timelineClose.Add_Click({
            if (Test-ProcessingTimelineWindowOpen) { $script:processingTimelineForm.Close() }
        })
        $timelineForm.Controls.Add($timelineClose)

        $timelineStop = New-Object System.Windows.Forms.Button
        $timelineStop.Location = New-Object System.Drawing.Point(568, 452)
        $timelineStop.Size = New-Object System.Drawing.Size(120, 34)
        $timelineStop.Anchor = 'Bottom,Right'
        $timelineStop.Add_Click({ Stop-ActiveTask })
        $timelineForm.Controls.Add($timelineStop)

        $script:processingTimelineForm = $timelineForm
        $script:processingTimelineList = $timelineList
        $script:processingTimelineStatus = $timelineStatus
        $script:processingTimelineProgressBar = $timelineProgress
        $script:processingTimelineElapsed = $timelineElapsed
        $script:processingTimelineStopButton = $timelineStop
        $script:processingTimelineCloseButton = $timelineClose
        $script:processingTimelineHeading = $timelineHeading

        $timelineList.Add_SizeChanged({
            if ($script:processingTimelineList -and -not $script:processingTimelineList.IsDisposed -and
                $script:processingTimelineList.Columns.Count -ge 3) {
                $usable = [Math]::Max(360, $script:processingTimelineList.ClientSize.Width - 8)
                $script:processingTimelineList.Columns[2].Width = [Math]::Max(180, $usable - 172)
            }
        })
        $timelineForm.Add_FormClosed({
            param($sender, $eventArgs)
            if ($script:processingTimelineForm -and [object]::ReferenceEquals($sender, $script:processingTimelineForm)) {
                $script:processingTimelineCapturing = $false
                $script:processingTimelineForm = $null
                $script:processingTimelineList = $null
                $script:processingTimelineStatus = $null
                $script:processingTimelineProgressBar = $null
                $script:processingTimelineElapsed = $null
                $script:processingTimelineStopButton = $null
                $script:processingTimelineCloseButton = $null
                $script:processingTimelineHeading = $null
            }
        })
        Set-ToolWindowTheme -Root $timelineForm -Mode $script:dashboardTheme
    } else {
        $script:processingTimelineList.Items.Clear()
    }

    Refresh-ProcessingTimelineLocalization
    $script:processingTimelineStatus.Text = if ([string]::IsNullOrWhiteSpace($Action)) {
        Get-DashboardText 'processingTimeline.running'
    } else {
        Get-DashboardText 'processingTimeline.runningAction' @($Action)
    }
    $script:processingTimelineProgressBar.Value = [Math]::Max(0, [Math]::Min(100, [int]$progressBar.Value))
    $script:processingTimelineElapsed.Text = [string]$elapsedLabel.Text
    $script:processingTimelineStopButton.Enabled = [bool]($script:activeProcess -and -not $script:activeProcess.HasExited)
    $script:processingTimelineCapturing = $true
    foreach ($entry in @($script:currentTaskProgressEntries.ToArray())) {
        Add-ProcessingTimelineEntry -Message ([string]$entry.Message) -Timestamp ([string]$entry.Timestamp) -Percent ([int]$entry.Percent)
    }
    if (-not $script:processingTimelineForm.Visible) {
        $script:processingTimelineForm.Show($form)
    } else {
        $script:processingTimelineForm.Activate()
    }
}

function Write-ProgressLog([string]$message) {
    $stamp = (Get-Date).ToString("HH:mm:ss")
    if ($progressLog.TextLength -gt 0) { [void]$progressLog.AppendText([Environment]::NewLine) }
    [void]$progressLog.AppendText("[$stamp] $message")
    $progressLog.SelectionStart = $progressLog.TextLength
    $progressLog.ScrollToCaret()
    $entryPercent = [int]$progressBar.Value
    if ($script:taskStartedAt) {
        $script:currentTaskProgressEntries.Add([pscustomobject]@{ Timestamp=$stamp; Percent=$entryPercent; Message=$message })
        while ($script:currentTaskProgressEntries.Count -gt 500) { $script:currentTaskProgressEntries.RemoveAt(0) }
    }
    Add-ProcessingTimelineEntry -Message $message -Timestamp $stamp -Percent $entryPercent
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-TaskProgressPlan([string]$TaskKind) {
    $scanPlan = @(
        [pscustomobject]@{ Ratio=0.00; Percent=3; Key='progress.phase.prepare' },
        [pscustomobject]@{ Ratio=0.10; Percent=15; Key='progress.phase.inventory' },
        [pscustomobject]@{ Ratio=0.36; Percent=42; Key='progress.phase.classify' },
        [pscustomobject]@{ Ratio=0.62; Percent=70; Key='progress.phase.evidence' },
        [pscustomobject]@{ Ratio=0.84; Percent=90; Key='progress.phase.finalize' }
    )
    $repairPlan = @(
        [pscustomobject]@{ Ratio=0.00; Percent=3; Key='progress.phase.prepare' },
        [pscustomobject]@{ Ratio=0.12; Percent=18; Key='progress.phase.backup' },
        [pscustomobject]@{ Ratio=0.30; Percent=40; Key='progress.phase.apply' },
        [pscustomobject]@{ Ratio=0.66; Percent=72; Key='progress.phase.verify' },
        [pscustomobject]@{ Ratio=0.86; Percent=92; Key='progress.phase.finalize' }
    )
    $networkPlan = @(
        [pscustomobject]@{ Ratio=0.00; Percent=5; Key='progress.phase.prepare' },
        [pscustomobject]@{ Ratio=0.18; Percent=28; Key='progress.phase.network' },
        [pscustomobject]@{ Ratio=0.58; Percent=68; Key='progress.phase.verify' },
        [pscustomobject]@{ Ratio=0.82; Percent=90; Key='progress.phase.finalize' }
    )
    $reportPlan = @(
        [pscustomobject]@{ Ratio=0.00; Percent=4; Key='progress.phase.prepare' },
        [pscustomobject]@{ Ratio=0.12; Percent=20; Key='progress.phase.inventory' },
        [pscustomobject]@{ Ratio=0.42; Percent=52; Key='progress.phase.evidence' },
        [pscustomobject]@{ Ratio=0.72; Percent=78; Key='progress.phase.package' },
        [pscustomobject]@{ Ratio=0.88; Percent=93; Key='progress.phase.finalize' }
    )
    if ($TaskKind -in @('CleanupScan','DeepLicenseScan','ForensicsScan')) { return $scanPlan }
    if ($TaskKind -in @('CleanupRemediate','CleanupDeep','CleanupScanRepair','CleanupRestore','OemApply')) { return $repairPlan }
    if ($TaskKind -in @('SoftwareCatalogUpdate','ApplicationUpdateCheck','ApplicationUpdateApply')) { return $networkPlan }
    if ($TaskKind -in @('Report','CleanupBackup','OemInspect','CertificateAudit','PluginAudit','TimelineExport')) { return $reportPlan }
    return $scanPlan
}

function Update-TaskProgressDisplay([TimeSpan]$Elapsed) {
    $targetSeconds = [Math]::Max(30, [int]$script:taskProgressTargetSeconds)
    $ratio = [Math]::Min(0.98, [Math]::Max(0.0, $Elapsed.TotalSeconds / $targetSeconds))
    $plan = @(Get-TaskProgressPlan -TaskKind ([string]$script:activeTaskKind))
    $phaseIndex = 0
    for ($index = 0; $index -lt $plan.Count; $index++) {
        if ($ratio -ge [double]$plan[$index].Ratio) { $phaseIndex = $index }
    }
    $phase = $plan[$phaseIndex]
    $nextPercent = if ($phaseIndex -lt ($plan.Count - 1)) { [int]$plan[$phaseIndex + 1].Percent } else { 98 }
    $phaseStart = [double]$phase.Ratio
    $phaseEnd = if ($phaseIndex -lt ($plan.Count - 1)) { [double]$plan[$phaseIndex + 1].Ratio } else { 1.0 }
    $phaseRatio = if ($phaseEnd -gt $phaseStart) { [Math]::Min(1.0, ($ratio - $phaseStart) / ($phaseEnd - $phaseStart)) } else { 1.0 }
    $percent = [int][Math]::Min(98, [Math]::Round(([int]$phase.Percent + (($nextPercent - [int]$phase.Percent) * $phaseRatio))))
    $remainingSeconds = [Math]::Max(0, [int][Math]::Ceiling($targetSeconds - $Elapsed.TotalSeconds))
    $remainingText = if ($remainingSeconds -gt 0) {
        '{0:00}:{1:00}' -f [Math]::Floor($remainingSeconds / 60), ($remainingSeconds % 60)
    } else {
        Get-DashboardText 'progress.eta.finishing'
    }
    $phaseText = Get-DashboardText ([string]$phase.Key)
    $activityLabel.Text = Get-DashboardText 'progress.phase.summary' @($percent, $phaseText, $remainingText)
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    $progressBar.Value = [Math]::Max(0, [Math]::Min(100, $percent))
    Update-ProcessingTimelineProgress -Percent $percent -Summary $activityLabel.Text -ElapsedText $elapsedLabel.Text
    if ($phaseIndex -ne [int]$script:taskProgressPhaseIndex) {
        $script:taskProgressPhaseIndex = $phaseIndex
        Write-ProgressLog (Get-DashboardText 'progress.phase.log' @($percent, $phaseText))
    }
}

function Refresh-DashboardLocalizedActivity {
    param([switch]$ResetRenderedHistory)

    if ($ResetRenderedHistory -and -not $script:activeProcess) {
        Reset-IdleTaskDisplay
        return
    }
    if (-not $script:hasTaskActivity) {
        $status.Text = Get-DashboardText "status.chooseTask"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(20, 126, 82)
        $activityLabel.Text = ""
        $elapsedLabel.Text = ""
        $progressLog.Clear()
        return
    }
    if (-not $script:activeProcess) { $activityLabel.Text = $status.Text }
}

function Write-LicenseTimelineEventSafe {
    param(
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)][string]$Source,
        [AllowNull()][object]$Data = $null,
        [bool]$IsChange = $false
    )

    if (-not $timelineState.Enabled) {
        return [pscustomobject]@{ Written=$false; Error=[string]$timelineState.Error }
    }
    try {
        return Write-ToolLicenseTimelineEvent -EventType $EventType -Source $Source -Data $Data -IsChange:$IsChange
    } catch {
        $message = Get-DashboardText "timeline.writeRejected" @($_.Exception.Message)
        [void](Write-ToolLog -Level "WARN" -Event "Timeline.WriteRejected" -Message $message -Data ([ordered]@{ EventType=$EventType; Source=$Source }))
        Write-ProgressLog (Get-DashboardText "common.warning" @($message))
        return [pscustomobject]@{ Written=$false; Error=$_.Exception.Message }
    }
}

function Start-ProgressDisplay([string]$action, [string]$detail, [bool]$preserveLog) {
    if (-not $preserveLog) { $progressLog.Clear() }
    $script:processingTimelineCapturing = $false
    $script:currentTaskProgressEntries.Clear()
    $script:hasTaskActivity = $true
    $script:taskCancellationRequested = $false
    $script:taskStartedAt = Get-Date
    $script:lastProgressHeartbeat = 0
    $script:taskStallWarningShown = $false
    $script:progressTick = 0
    $script:progressPhase = 0
    $script:taskProgressPhaseIndex = -1
    $script:taskProgressTargetSeconds = 120
    $activityLabel.Text = $detail
    $activityLabel.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $elapsedLabel.Text = "00:00"
    $progressBar.Value = 0
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    $progressBar.MarqueeAnimationSpeed = 0
    $progressBar.Value = 2
    Update-MainLayout
    Write-ProgressLog (Get-ToolText -Key "progress.started" -Culture $script:dashboardCulture -FormatArguments @($action))
    [void](Write-ToolLog -Level "INFO" -Event "Action.Start" -Message $action -Data ([ordered]@{
        Detail = $detail
        CompatibilityTier = $capabilityState.CompatibilityTier
    }))
}

function Stop-ProgressDisplay([string]$summary) {
    $durationMs = $null
    if ($script:taskStartedAt) {
        $elapsed = (Get-Date) - $script:taskStartedAt
        $durationMs = [long][Math]::Round($elapsed.TotalMilliseconds)
        $elapsedLabel.Text = "{0:00}:{1:00}" -f [Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
    }
    $script:taskStartedAt = $null
    $progressBar.MarqueeAnimationSpeed = 0
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    $progressBar.Value = 100
    $activityLabel.Text = $summary
    $activityLabel.ForeColor = $status.ForeColor
    if (Test-ProcessingTimelineWindowOpen) {
        $lastTimelineText = if ($script:processingTimelineList.Items.Count -gt 0) {
            [string]$script:processingTimelineList.Items[$script:processingTimelineList.Items.Count - 1].SubItems[2].Text
        } else { '' }
        if ($script:processingTimelineCapturing -and -not [string]::Equals($lastTimelineText, $summary, [StringComparison]::Ordinal)) {
            Add-ProcessingTimelineEntry -Message $summary -Percent 100
        }
        Update-ProcessingTimelineProgress -Percent 100 -Summary $summary -ElapsedText $elapsedLabel.Text
        $script:processingTimelineStopButton.Enabled = $false
    }
    $script:processingTimelineCapturing = $false
    [void](Write-ToolLog -Level "INFO" -Event "Action.DisplayStopped" -Message $summary -DurationMs $durationMs)
}

function Reset-IdleTaskDisplay {
    $script:hasTaskActivity = $false
    $script:taskCancellationRequested = $false
    $status.Text = Get-DashboardText "status.chooseTask"
    $status.ForeColor = [System.Drawing.Color]::FromArgb(20, 126, 82)
    $activityLabel.Text = ""
    $elapsedLabel.Text = ""
    $progressBar.MarqueeAnimationSpeed = 0
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    $progressBar.Value = 0
    $progressLog.Clear()
    $script:processingTimelineCapturing = $false
    $script:currentTaskProgressEntries.Clear()
    $stopButton.Visible = $false
    $stopButton.Enabled = $false
    Update-MainLayout
}

function Stop-ProgressOnStartError([string]$message) {
    $status.Text = $message
    $status.ForeColor = [System.Drawing.Color]::DarkRed
    Write-ProgressLog $message
    [void](Write-ToolLog -Level "ERROR" -Event "Action.StartFailed" -Message $message)
    Stop-ProgressDisplay $message
}

function Stop-ProgressIfIdle {
    if (-not $script:activeProcess) { Stop-ProgressDisplay $status.Text }
}

function Complete-DashboardStartupValidation {
    Write-DashboardStartupTrace "Validation.Started"
    try {
        $integrityResult = Test-ToolIntegrity
        [void](Write-ToolLog -Level "INFO" -Event "Application.Start" -Message (Get-DashboardText "log.dashboardStarted") -Data ([ordered]@{
            DashboardSchemaVersion = $dashboardSchemaVersion
            ReportSchemaVersion = $reportSchemaState.SchemaVersion
            SafetyPolicySchemaVersion = $safetyPolicyState.SchemaVersion
            CompatibilitySchemaVersion = $compatibilityState.SchemaVersion
            LocalizationSchemaVersion = $localizationState.SchemaVersion
            OfflinePolicySchemaVersion = $offlinePolicyState.SchemaVersion
            Culture = $script:dashboardCulture
            OfflineMode = [bool]$script:offlineMode
            Capabilities = $capabilityState
        }))
        Update-DashboardStatus -IntegrityResult $integrityResult
        Refresh-DashboardLocalizedActivity
        if (-not $loggingState.Enabled) {
            Write-ProgressLog (Get-DashboardText "progress.logWarning" @($loggingState.Error))
        }
        if (-not $timelineState.Enabled) {
            Write-ProgressLog (Get-DashboardText "progress.timelineWarning" @($timelineState.Error))
        } else {
            $timelineCheck = Get-ToolLicenseTimeline
            Write-ProgressLog $(if ($timelineCheck.Valid) {
                Get-ToolText -Key "progress.timeline.valid" -Culture $script:dashboardCulture -FormatArguments @($timelineCheck.RecordCount, $timelineCheck.ChangeCount)
            } else {
                Get-ToolText -Key "progress.timeline.invalid" -Culture $script:dashboardCulture
            })
        }
        if (-not $integrityResult.Valid) {
            $status.Text = Get-ToolText -Key "progress.integrity.locked" -Culture $script:dashboardCulture
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        $kmsConfigAtStartup = Get-ApprovedKmsEntries
        if (-not $kmsConfigAtStartup.Exists -or $kmsConfigAtStartup.Entries.Count -eq 0) {
            Write-ProgressLog (Get-ToolText -Key "progress.kms.missing" -Culture $script:dashboardCulture)
        } elseif ($kmsConfigAtStartup.Invalid.Count -gt 0) {
            Write-ProgressLog (Get-ToolText -Key "progress.kms.invalid" -Culture $script:dashboardCulture -FormatArguments @($kmsConfigAtStartup.Invalid.Count))
        } else {
            Write-ProgressLog (Get-ToolText -Key "progress.kms.approved" -Culture $script:dashboardCulture -FormatArguments @($kmsConfigAtStartup.Entries.Count))
        }
        Reset-IdleTaskDisplay
        [void]$form.BeginInvoke([System.Action]{ Update-ResultActionCard -HeaderOnly })
    } catch {
        $status.Text = $_.Exception.Message
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $_.Exception.Message
    } finally {
        try { Complete-DashboardThemeInitialization -Mode $script:dashboardTheme } catch { Write-ProgressLog $_.Exception.Message }
        Set-ButtonsEnabled $true
        Write-DashboardStartupTrace "Validation.Ready"
    }
}

function Set-ButtonsEnabled([bool]$enabled) {
    foreach ($button in $buttons) { $button.Enabled = $enabled }
    $languageCombo.Enabled = $enabled
    $canStop = [bool]((-not $enabled) -and $script:activeProcess -and -not $script:activeProcess.HasExited)
    $stopButton.Visible = $canStop
    $stopButton.Enabled = $canStop
    $stopButton.Text = Get-ToolText -Key "progress.stop" -Culture $script:dashboardCulture
    if ((Test-ProcessingTimelineWindowOpen) -and $script:processingTimelineStopButton) {
        $script:processingTimelineStopButton.Enabled = $canStop
        $script:processingTimelineStopButton.Text = Get-ToolText -Key "progress.stop" -Culture $script:dashboardCulture
    }
    Update-MainLayout
}

function Stop-ActiveTask {
    if (-not $script:activeProcess -or $script:activeProcess.HasExited) {
        Set-ButtonsEnabled $true
        return
    }

    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        (Get-ToolText -Key "progress.stopConfirm" -Culture $script:dashboardCulture),
        (Get-ToolText -Key "progress.stopTitle" -Culture $script:dashboardCulture),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $script:taskCancellationRequested = $true
    $stopButton.Enabled = $false
    $stopButton.Text = Get-ToolText -Key "progress.stopping" -Culture $script:dashboardCulture
    $activityLabel.Text = Get-ToolText -Key "progress.stopping" -Culture $script:dashboardCulture
    if ((Test-ProcessingTimelineWindowOpen) -and $script:processingTimelineStopButton) {
        $script:processingTimelineStopButton.Enabled = $false
        $script:processingTimelineStopButton.Text = Get-ToolText -Key "progress.stopping" -Culture $script:dashboardCulture
        Update-ProcessingTimelineProgress -Percent ([int]$progressBar.Value) -Summary $activityLabel.Text -ElapsedText $elapsedLabel.Text
    }
    Write-ProgressLog (Get-ToolText -Key "progress.stopRequested" -Culture $script:dashboardCulture)
    [void](Write-ToolLog -Level "WARN" -Event "Action.StopRequested" -Message $script:activeAction -Data ([ordered]@{
        ProcessId = [int]$script:activeProcess.Id
        TaskKind = [string]$script:activeTaskKind
        ModuleId = [string]$script:activeModuleId
    }))

    try {
        $taskKillPath = Get-ToolNativeSystemPath "taskkill.exe"
        if (Test-Path -LiteralPath $taskKillPath -PathType Leaf) {
            $taskKillProcess = Start-Process -FilePath $taskKillPath -ArgumentList @('/PID', [string][int]$script:activeProcess.Id, '/T', '/F') -WindowStyle Hidden -Wait -PassThru
            if ($taskKillProcess.ExitCode -ne 0 -and -not $script:activeProcess.HasExited) {
                $script:activeProcess.Kill()
            }
        } else {
            $script:activeProcess.Kill()
        }
    } catch {
        $script:taskCancellationRequested = $false
        $stopButton.Enabled = $true
        $stopButton.Text = Get-ToolText -Key "progress.stop" -Culture $script:dashboardCulture
        $message = Get-ToolText -Key "progress.stopFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)
        Write-ProgressLog $message
        [void](Write-ToolLog -Level "ERROR" -Event "Action.StopFailed" -Message $message)
        [System.Windows.Forms.MessageBox]::Show($message, (Get-ToolText -Key "progress.stopTitle" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
    }
}

function Get-ReadyToolModule([string]$moduleId, [bool]$elevatedLaunch) {
    $availability = Test-ToolModuleAvailability -ModuleId $moduleId -CapabilityProfile $capabilityState -SourceDirectory $baseDir
    if (-not $availability.Available) { throw (Get-DashboardText "module.unavailable" @($moduleId, $availability.Message)) }
    if ([string]$availability.Descriptor.AccessMode -eq 'SystemChange' -and [string]$env:TOOL_OFFICIAL_BUILD_STATE -notin @('Official','OfficialSelfSigned','Store')) {
        throw (Get-DashboardText 'officialBuild.systemChangeBlocked' @([string]$env:TOOL_OFFICIAL_VERIFICATION_URL))
    }
    if ($availability.Descriptor.RequiresElevation -and -not $elevatedLaunch) { throw (Get-DashboardText "module.elevationRequired" @($moduleId)) }
    return $availability.Descriptor
}

function Get-ToolElevatedEnvironmentSnapshot {
    $allowedNames = @(
        'TOOL_APPROVED_KMS_FILE','TOOL_BUILD_ARCHITECTURE','TOOL_CAPABILITY_SCHEMA',
        'TOOL_COMPATIBILITY_CATALOG','TOOL_COMPATIBILITY_SCHEMA','TOOL_CORRELATION_ID',
        'TOOL_DASHBOARD_SCHEMA','TOOL_DATA_OWNER_SID','TOOL_DATA_ROOT','TOOL_DATA_SCHEMA_VERSION','TOOL_DATA_SCOPE',
        'TOOL_ENTERPRISE_NETWORK_ALLOWED','TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH','TOOL_ENTERPRISE_ROOT',
        'TOOL_ENTERPRISE_SCHEMA','TOOL_EXPECTED_PROCESS_ARCHITECTURE','TOOL_LAUNCHER_PATH',
        'TOOL_LAUNCHER_PID','TOOL_LAUNCH_MODE','TOOL_LEGACY_DATA_ROOT','TOOL_LOCALIZATION_SCHEMA',
        'TOOL_LOG_PATH','TOOL_MODULE_CONTRACT_SCHEMA','TOOL_MODULE_ID','TOOL_MODULE_INVOCATION_ID',
        'TOOL_OFFLINE_MODE','TOOL_OFFLINE_POLICY_SCHEMA','TOOL_OFFLINE_SETTINGS_PATH','TOOL_PLUGIN_DIR',
        'TOOL_POWERSHELL_PATH','TOOL_REPORT_SCHEMA','TOOL_SAFETY_POLICY_SCHEMA','TOOL_SECURE_LAUNCH',
        'TOOL_OFFICIAL_BUILD_STATE','TOOL_OFFICIAL_BUILD_FAILURE','TOOL_OFFICIAL_BUILD_ID','TOOL_OFFICIAL_VERIFICATION_URL',
        'TOOL_SELF_UPDATE_ALLOWED',
        'TOOL_SECURE_RUNTIME_DIR','TOOL_SECURE_RUNTIME_FAILED','TOOL_TIMELINE_KEY_PATH','TOOL_TIMELINE_PATH',
        'TOOL_TOOL_VERSION','TOOL_UI_CULTURE','TOOL_UI_CULTURE_SETTINGS_PATH','TOOL_UI_THEME',
        'TOOL_UI_THEME_SETTINGS_PATH'
    )
    $snapshot = [ordered]@{}
    foreach ($name in $allowedNames) {
        $value = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::Process)
        $snapshot[$name] = if ($null -eq $value) { $null } else { [string]$value }
    }
    if ([string]$snapshot['TOOL_SECURE_LAUNCH'] -ne '1') { throw 'ElevatedBridgeSecureLaunchRequired' }
    if ([string]::IsNullOrWhiteSpace([string]$snapshot['TOOL_SECURE_RUNTIME_DIR'])) { throw 'ElevatedBridgeRuntimeMissing' }
    if ([string]$snapshot['TOOL_DATA_SCOPE'] -eq 'User') {
        try {
            $dataOwnerSid = New-Object Security.Principal.SecurityIdentifier([string]$snapshot['TOOL_DATA_OWNER_SID'])
            if (-not $dataOwnerSid.IsAccountSid()) { throw 'ElevatedBridgeDataOwnerSidInvalid' }
        } catch { throw 'ElevatedBridgeDataOwnerSidInvalid' }
    }
    if ([string]$snapshot['TOOL_MODULE_ID'] -notmatch '^[a-z0-9][a-z0-9._-]{0,127}$') { throw 'ElevatedBridgeModuleIdInvalid' }
    $invocationId = [guid]::Empty
    if (-not [guid]::TryParse([string]$snapshot['TOOL_MODULE_INVOCATION_ID'], [ref]$invocationId) -or $invocationId -eq [guid]::Empty) {
        throw 'ElevatedBridgeInvocationIdInvalid'
    }
    return $snapshot
}

function New-ToolElevatedBootstrapArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BridgeScriptPath,
        [Parameter(Mandatory = $true)][string]$TargetFilePath,
        [Parameter(Mandatory = $true)][string]$TargetArguments,
        [bool]$HiddenWindow = $false
    )

    if (-not (Test-Path -LiteralPath $BridgeScriptPath -PathType Leaf)) { throw 'ElevatedBridgeScriptMissing' }
    if (-not (Test-Path -LiteralPath $TargetFilePath -PathType Leaf)) { throw 'ElevatedBridgeTargetMissing' }
    $elevatedLauncherPath = [string]$env:TOOL_LAUNCHER_PATH
    if ([string]::IsNullOrWhiteSpace($elevatedLauncherPath) -or -not (Test-Path -LiteralPath $elevatedLauncherPath -PathType Leaf)) {
        throw 'ElevatedBrokerLauncherMissing'
    }
    $elevatedLauncherItem = Get-Item -LiteralPath $elevatedLauncherPath -Force -ErrorAction Stop
    if (($elevatedLauncherItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ElevatedBrokerLauncherReparsePointRejected' }
    $payload = [ordered]@{
        SchemaVersion = '2.0'
        CreatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        TargetFilePath = [IO.Path]::GetFullPath($TargetFilePath)
        TargetArguments = [string]$TargetArguments
        HiddenWindow = [bool]$HiddenWindow
        Environment = Get-ToolElevatedEnvironmentSnapshot
    }
    $payloadJson = $payload | ConvertTo-Json -Depth 5 -Compress
    $payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payloadJson))
    if ($payloadBase64.Length -gt 24000) { throw 'ElevatedBridgePayloadTooLarge' }
    return "--elevated-module-broker `"$payloadBase64`""
}

function Start-ToolModuleProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ModuleId,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [Parameter(Mandatory = $true)][string]$Action,
        [switch]$Elevate,
        [switch]$Hidden
    )

    if ($script:activeProcess -and -not $script:activeProcess.HasExited) { throw (Get-DashboardText "module.alreadyRunning") }
    $descriptor = Get-ReadyToolModule -moduleId $ModuleId -elevatedLaunch ([bool]$Elevate)
    $invocation = New-ToolModuleInvocation -ModuleId $descriptor.ModuleId
    $previousModuleId = [string]$env:TOOL_MODULE_ID
    $previousInvocationId = [string]$env:TOOL_MODULE_INVOCATION_ID
    try {
        $env:TOOL_MODULE_ID = $descriptor.ModuleId
        $env:TOOL_MODULE_INVOCATION_ID = $invocation.InvocationId
        $startParameters = @{
            FilePath = $toolPowerShellPath
            ArgumentList = $Arguments
            PassThru = $true
        }
        if ($Elevate) {
            $startParameters.ArgumentList = New-ToolElevatedBootstrapArguments -BridgeScriptPath $elevatedBridgeScript -TargetFilePath $toolPowerShellPath -TargetArguments $Arguments -HiddenWindow ([bool]$Hidden)
            $startParameters.FilePath = [IO.Path]::GetFullPath([string]$env:TOOL_LAUNCHER_PATH)
            $startParameters.Verb = "RunAs"
        }
        if ($Hidden) { $startParameters.WindowStyle = "Hidden" }
        $process = Start-Process @startParameters
        if (-not $process) { throw (Get-DashboardText "module.processMissing") }
    } finally {
        $env:TOOL_MODULE_ID = $previousModuleId
        $env:TOOL_MODULE_INVOCATION_ID = $previousInvocationId
    }

    $script:activeProcess = $process
    $script:lastModuleResult = $null
    $script:activeAction = $Action
    $script:activeTaskKind = $descriptor.TaskKind
    $script:activeModuleId = $descriptor.ModuleId
    $script:activeModuleInvocation = $invocation
    [void](Write-ToolLog -Level "AUDIT" -Event "Module.Start" -Message $Action -Data ([ordered]@{
        ModuleId = $descriptor.ModuleId
        InvocationId = $invocation.InvocationId
        AccessMode = $descriptor.AccessMode
        RequiresElevation = [bool]$descriptor.RequiresElevation
    }))
    return $process
}

function Start-DetachedToolModuleProcess {
    param(
        [Parameter(Mandatory = $true)][string]$ModuleId,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [switch]$Elevate,
        [switch]$Hidden
    )

    $descriptor = Get-ReadyToolModule -moduleId $ModuleId -elevatedLaunch ([bool]$Elevate)
    $invocation = New-ToolModuleInvocation -ModuleId $descriptor.ModuleId
    $previousModuleId = [string]$env:TOOL_MODULE_ID
    $previousInvocationId = [string]$env:TOOL_MODULE_INVOCATION_ID
    try {
        $env:TOOL_MODULE_ID = $descriptor.ModuleId
        $env:TOOL_MODULE_INVOCATION_ID = $invocation.InvocationId
        $startParameters = @{ FilePath=$toolPowerShellPath; ArgumentList=$Arguments; PassThru=$true }
        if ($Elevate) {
            $startParameters.ArgumentList = New-ToolElevatedBootstrapArguments -BridgeScriptPath $elevatedBridgeScript -TargetFilePath $toolPowerShellPath -TargetArguments $Arguments -HiddenWindow ([bool]$Hidden)
            $startParameters.FilePath = [IO.Path]::GetFullPath([string]$env:TOOL_LAUNCHER_PATH)
            $startParameters.Verb = "RunAs"
        }
        if ($Hidden) { $startParameters.WindowStyle = "Hidden" }
        $process = Start-Process @startParameters
        if (-not $process) { throw (Get-DashboardText "module.processMissing") }
    } finally {
        $env:TOOL_MODULE_ID = $previousModuleId
        $env:TOOL_MODULE_INVOCATION_ID = $previousInvocationId
    }
    [void](Write-ToolLog -Level "AUDIT" -Event "Module.Launched" -Message $descriptor.DisplayName -Data ([ordered]@{
        ModuleId=$descriptor.ModuleId; InvocationId=$invocation.InvocationId; ProcessId=$process.Id
    }))
    [void](Write-LicenseTimelineEventSafe -EventType "ModuleLaunched" -Source "GUI" -IsChange:$false -Data ([ordered]@{
        ModuleId=$descriptor.ModuleId; InvocationId=$invocation.InvocationId; AccessMode=$descriptor.AccessMode
        ChangeCapable=[bool]($descriptor.AccessMode -eq "SystemChange")
    }))
    return $process
}

function Show-ReportPrivacyChooser {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-ToolText -Key 'report.privacy.title' -Culture $script:dashboardCulture
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.ClientSize = New-Object System.Drawing.Size(760, 300)
    $dialog.Tag = 'Cancel'

    $message = New-Object System.Windows.Forms.Label
    $message.Text = Get-ToolText -Key 'report.privacy.promptExplicit' -Culture $script:dashboardCulture
    $message.Font = $fontNormal
    $message.Location = New-Object System.Drawing.Point(28, 24)
    $message.Size = New-Object System.Drawing.Size(704, 176)
    $message.Anchor = 'Top,Bottom,Left,Right'
    $message.AutoEllipsis = $false
    $dialog.Controls.Add($message)

    $privacyFooter = New-Object System.Windows.Forms.FlowLayoutPanel
    $privacyFooter.Location = New-Object System.Drawing.Point(20, 222)
    $privacyFooter.Size = New-Object System.Drawing.Size(720, 56)
    $privacyFooter.Anchor = 'Bottom,Left,Right'
    $privacyFooter.FlowDirection = 'LeftToRight'
    $privacyFooter.WrapContents = $false
    $privacyFooter.Padding = New-Object System.Windows.Forms.Padding(4)
    $dialog.Controls.Add($privacyFooter)

    $redactedButton = New-Object System.Windows.Forms.Button
    $redactedButton.Text = Get-ToolText -Key 'report.privacy.redactedButton' -Culture $script:dashboardCulture
    $redactedButton.AutoSize = $true; $redactedButton.AutoSizeMode = 'GrowAndShrink'; $redactedButton.MinimumSize = New-Object System.Drawing.Size(212, 42)
    $redactedButton.Margin = New-Object System.Windows.Forms.Padding(4)
    $redactedButton.Font = $fontBold
    $redactedButton.Add_Click({ $dialog.Tag = 'Redacted'; $dialog.Close() })
    $privacyFooter.Controls.Add($redactedButton)

    $internalButton = New-Object System.Windows.Forms.Button
    $internalButton.Text = Get-ToolText -Key 'report.privacy.internalButton' -Culture $script:dashboardCulture
    $internalButton.AutoSize = $true; $internalButton.AutoSizeMode = 'GrowAndShrink'; $internalButton.MinimumSize = New-Object System.Drawing.Size(220, 42)
    $internalButton.Margin = New-Object System.Windows.Forms.Padding(4)
    $internalButton.Add_Click({ $dialog.Tag = 'Internal'; $dialog.Close() })
    $privacyFooter.Controls.Add($internalButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-ToolText -Key 'report.privacy.cancelButton' -Culture $script:dashboardCulture
    $cancelButton.AutoSize = $true; $cancelButton.AutoSizeMode = 'GrowAndShrink'; $cancelButton.MinimumSize = New-Object System.Drawing.Size(138, 42)
    $cancelButton.Margin = New-Object System.Windows.Forms.Padding(4)
    $cancelButton.Add_Click({ $dialog.Tag = 'Cancel'; $dialog.Close() })
    $privacyFooter.Controls.Add($cancelButton)
    $dialog.AcceptButton = $redactedButton
    $dialog.CancelButton = $cancelButton

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    Set-ToolUiPrimaryActionButtonVisual -Button $redactedButton -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Show-ReportScanChooser {
    $preference = Get-ToolScanPreference
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText 'scan.dialog.title'
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'Sizable'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.MinimumSize = New-Object System.Drawing.Size(640, 650)
    $dialog.ClientSize = New-Object System.Drawing.Size(690, 680)
    $dialog.Tag = $null

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.Padding = New-Object System.Windows.Forms.Padding(22, 18, 22, 16)
    $layout.ColumnCount = 1
    $layout.RowCount = 10
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 40)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 46)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 46)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52)))
    $dialog.Controls.Add($layout)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = Get-DashboardText 'scan.dialog.summary'
    $intro.Dock = 'Fill'
    $intro.AutoEllipsis = $true
    $layout.Controls.Add($intro, 0, 0)

    $profileRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $profileRow.Dock = 'Fill'
    $profileRow.WrapContents = $false
    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = Get-DashboardText 'scan.dialog.level'
    $profileLabel.Size = New-Object System.Drawing.Size(180, 28)
    $profileLabel.TextAlign = 'MiddleLeft'
    $profileCombo = New-Object System.Windows.Forms.ComboBox
    $profileCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $profileCombo.Size = New-Object System.Drawing.Size(260, 30)
    [void]$profileCombo.Items.Add((Get-DashboardText 'scan.profile.quick'))
    [void]$profileCombo.Items.Add((Get-DashboardText 'scan.profile.standard'))
    [void]$profileCombo.Items.Add((Get-DashboardText 'scan.profile.deep'))
    $profileCombo.SelectedIndex = switch ([string]$preference.Profile) { 'Quick' { 0 }; 'Deep' { 2 }; default { 1 } }
    $profileRow.Controls.Add($profileLabel)
    $profileRow.Controls.Add($profileCombo)
    $layout.Controls.Add($profileRow, 0, 1)

    $lowResourceCheck = New-Object System.Windows.Forms.CheckBox
    $lowResourceCheck.Text = Get-DashboardText 'scan.dialog.lowResource'
    $lowResourceCheck.Checked = [bool]$preference.LowResource
    $lowResourceCheck.Dock = 'Fill'
    $layout.Controls.Add($lowResourceCheck, 0, 2)

    $rootLabel = New-Object System.Windows.Forms.Label
    $rootLabel.Text = Get-DashboardText 'scan.dialog.roots'
    $rootLabel.Dock = 'Fill'
    $rootLabel.TextAlign = 'MiddleLeft'
    $layout.Controls.Add($rootLabel, 0, 3)

    $rootList = New-Object System.Windows.Forms.ListBox
    $rootList.Dock = 'Fill'
    $rootList.HorizontalScrollbar = $true
    foreach ($root in @($preference.IncludedRoots)) { if ($root) { [void]$rootList.Items.Add([string]$root) } }
    $layout.Controls.Add($rootList, 0, 4)

    $rootButtons = New-Object System.Windows.Forms.FlowLayoutPanel
    $rootButtons.Dock = 'Fill'
    $rootButtons.WrapContents = $false
    $addRootButton = New-Object System.Windows.Forms.Button
    $addRootButton.Text = Get-DashboardText 'scan.dialog.addFolder'
    $addRootButton.Size = New-Object System.Drawing.Size(150, 34)
    $addRootButton.Add_Click({
        if ($rootList.Items.Count -ge 8) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'scan.dialog.maximumRoots'), $dialog.Text, 'OK', 'Warning') | Out-Null
            return
        }
        $folderPicker = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderPicker.Description = Get-DashboardText 'scan.dialog.folderPrompt'
        if ($folderPicker.ShowDialog($dialog) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            $currentExcludedRoots = @($excludedRootList.Items | ForEach-Object { [string]$_ })
            $candidatePlan = Resolve-ToolScanPlan -Profile 'Standard' -IncludedRoots @([string]$folderPicker.SelectedPath) -ExcludedRoots $currentExcludedRoots
            $candidateRoot = [string]@($candidatePlan.IncludedRoots)[0]
            if ([string]::IsNullOrWhiteSpace($candidateRoot)) { throw 'ScanRootRejected' }
            if (-not @($rootList.Items) -contains $candidateRoot) { [void]$rootList.Items.Add($candidateRoot) }
        } catch {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'scan.dialog.invalidRoot' @($_.Exception.Message)), $dialog.Text, 'OK', 'Warning') | Out-Null
        }
    })
    $removeRootButton = New-Object System.Windows.Forms.Button
    $removeRootButton.Text = Get-DashboardText 'scan.dialog.removeFolder'
    $removeRootButton.Size = New-Object System.Drawing.Size(150, 34)
    $removeRootButton.Add_Click({ if ($rootList.SelectedIndex -ge 0) { $rootList.Items.RemoveAt($rootList.SelectedIndex) } })
    $defaultRootsButton = New-Object System.Windows.Forms.Button
    $defaultRootsButton.Text = Get-DashboardText 'scan.dialog.defaultScope'
    $defaultRootsButton.Size = New-Object System.Drawing.Size(190, 34)
    $defaultRootsButton.Add_Click({ $rootList.Items.Clear() })
    $rootButtons.Controls.Add($addRootButton)
    $rootButtons.Controls.Add($removeRootButton)
    $rootButtons.Controls.Add($defaultRootsButton)
    $layout.Controls.Add($rootButtons, 0, 5)

    $excludedRootLabel = New-Object System.Windows.Forms.Label
    $excludedRootLabel.Text = Get-DashboardText 'scan.dialog.excludedRoots'
    $excludedRootLabel.Dock = 'Fill'
    $excludedRootLabel.TextAlign = 'MiddleLeft'
    $layout.Controls.Add($excludedRootLabel, 0, 6)

    $excludedRootList = New-Object System.Windows.Forms.ListBox
    $excludedRootList.Dock = 'Fill'
    $excludedRootList.HorizontalScrollbar = $true
    foreach ($excludedRoot in @($preference.ExcludedRoots)) {
        if ($excludedRoot) { [void]$excludedRootList.Items.Add([string]$excludedRoot) }
    }
    $layout.Controls.Add($excludedRootList, 0, 7)

    $excludedRootButtons = New-Object System.Windows.Forms.FlowLayoutPanel
    $excludedRootButtons.Dock = 'Fill'
    $excludedRootButtons.WrapContents = $false
    $addExcludedRootButton = New-Object System.Windows.Forms.Button
    $addExcludedRootButton.Text = Get-DashboardText 'scan.dialog.addExclusion'
    $addExcludedRootButton.Size = New-Object System.Drawing.Size(150, 34)
    $addExcludedRootButton.Add_Click({
        if ($excludedRootList.Items.Count -ge 8) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'scan.dialog.maximumRoots'), $dialog.Text, 'OK', 'Warning') | Out-Null
            return
        }
        $folderPicker = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderPicker.Description = Get-DashboardText 'scan.dialog.exclusionPrompt'
        if ($folderPicker.ShowDialog($dialog) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            $currentIncludedRoots = @($rootList.Items | ForEach-Object { [string]$_ })
            $candidatePlan = Resolve-ToolScanPlan -Profile 'Standard' -IncludedRoots $currentIncludedRoots -ExcludedRoots @([string]$folderPicker.SelectedPath)
            $candidateRoot = [string]@($candidatePlan.ExcludedRoots)[0]
            if ([string]::IsNullOrWhiteSpace($candidateRoot)) { throw 'ScanRootRejected' }
            if (-not @($excludedRootList.Items) -contains $candidateRoot) { [void]$excludedRootList.Items.Add($candidateRoot) }
        } catch {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'scan.dialog.invalidRoot' @($_.Exception.Message)), $dialog.Text, 'OK', 'Warning') | Out-Null
        }
    })
    $removeExcludedRootButton = New-Object System.Windows.Forms.Button
    $removeExcludedRootButton.Text = Get-DashboardText 'scan.dialog.removeExclusion'
    $removeExcludedRootButton.Size = New-Object System.Drawing.Size(150, 34)
    $removeExcludedRootButton.Add_Click({
        if ($excludedRootList.SelectedIndex -ge 0) { $excludedRootList.Items.RemoveAt($excludedRootList.SelectedIndex) }
    })
    $clearExcludedRootsButton = New-Object System.Windows.Forms.Button
    $clearExcludedRootsButton.Text = Get-DashboardText 'scan.dialog.clearExclusions'
    $clearExcludedRootsButton.Size = New-Object System.Drawing.Size(190, 34)
    $clearExcludedRootsButton.Add_Click({ $excludedRootList.Items.Clear() })
    $excludedRootButtons.Controls.Add($addExcludedRootButton)
    $excludedRootButtons.Controls.Add($removeExcludedRootButton)
    $excludedRootButtons.Controls.Add($clearExcludedRootsButton)
    $layout.Controls.Add($excludedRootButtons, 0, 8)

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = 'Fill'
    $footer.FlowDirection = 'RightToLeft'
    $footer.WrapContents = $false
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = Get-DashboardText 'scan.dialog.continue'
    $okButton.Size = New-Object System.Drawing.Size(150, 38)
    $okButton.Add_Click({
        $profile = switch ($profileCombo.SelectedIndex) { 0 { 'Quick' }; 2 { 'Deep' }; default { 'Standard' } }
        $roots = @($rootList.Items | ForEach-Object { [string]$_ })
        $excludedRoots = @($excludedRootList.Items | ForEach-Object { [string]$_ })
        try {
            $validatedPlan = Resolve-ToolScanPlan -Profile $profile -LowResource:([bool]$lowResourceCheck.Checked) -IncludedRoots $roots -ExcludedRoots $excludedRoots
            [void](Set-ToolScanPreference -Profile $profile -LowResource:([bool]$lowResourceCheck.Checked) -IncludedRoots @($validatedPlan.IncludedRoots) -ExcludedRoots @($validatedPlan.ExcludedRoots))
            $dialog.Tag = [pscustomobject][ordered]@{
                Profile = $profile
                LowResource = [bool]$lowResourceCheck.Checked
                IncludedRoots = @($validatedPlan.IncludedRoots)
                ExcludedRoots = @($validatedPlan.ExcludedRoots)
                DeleteAfterRead = $true
            }
            $dialog.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'scan.dialog.invalidRoot' @($_.Exception.Message)), $dialog.Text, 'OK', 'Warning') | Out-Null
        }
    })
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-DashboardText 'report.privacy.cancelButton'
    $cancelButton.Size = New-Object System.Drawing.Size(130, 38)
    $cancelButton.Add_Click({ $dialog.Tag = $null; $dialog.Close() })
    $footer.Controls.Add($okButton)
    $footer.Controls.Add($cancelButton)
    $layout.Controls.Add($footer, 0, 9)
    $dialog.AcceptButton = $okButton
    $dialog.CancelButton = $cancelButton
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    Set-ToolUiPrimaryActionButtonVisual -Button $okButton -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $result = $dialog.Tag
    $dialog.Dispose()
    return $result
}

function Start-Report([string]$mode, [string]$displayName) {
    if (-not (Test-Path -LiteralPath $reportScript)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "report.missingModule" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "report.errorTitle" -Culture $script:dashboardCulture),
            "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = Show-ReportPrivacyChooser
    if ($privacyChoice -eq 'Cancel') { return }
    $scanChoice = Show-ReportScanChooser
    if ($null -eq $scanChoice) { return }
    $redactSensitive = [bool]($privacyChoice -eq 'Redacted')
    try {
        Start-ProgressDisplay $displayName (Get-ToolText -Key "report.starting" -Culture $script:dashboardCulture) $false
        Write-ProgressLog (Get-ToolText -Key $(if ($redactSensitive) { "report.redactedProgress" } else { "report.internalProgress" }) -Culture $script:dashboardCulture)
        $privacyArgument = if ($redactSensitive) { " -RedactSensitive" } else { " -FullInternal" }
        $output = New-ToolReportRunDirectory -Category "BaoCao-$mode"
        $scanSettingsPath = Join-Path $output 'scan-request.json'
        $scanRequestJson = $scanChoice | ConvertTo-Json -Depth 4
        [IO.File]::WriteAllText($scanSettingsPath, $scanRequestJson, (New-Object Text.UTF8Encoding($false)))
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$reportScript`" -OutputDir `"$output`" -Mode `"$mode`" -Culture `"$script:dashboardCulture`" -ApprovedKmsServerFile `"$approvedKmsFile`" -ScanSettingsPath `"$scanSettingsPath`" -Pdf$privacyArgument"
        $moduleId = Get-ToolReportModuleId -Mode $mode
        # Windows licensing, all-user AppX and other-user registry hives can
        # require an elevated token. The click is the user's action and UAC is
        # still the final consent boundary; cancellation remains non-destructive.
        $needsCompleteMachineRead = [bool]($mode -in @('All','Windows','Office','Software'))
        [void](Start-ToolModuleProcess -ModuleId $moduleId -Arguments $arguments -Action $displayName -Hidden -Elevate:$needsCompleteMachineRead)
        $status.Text = Get-ToolText -Key "report.running" -Culture $script:dashboardCulture -FormatArguments @($displayName)
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-ToolText -Key "report.startFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message))
    }
}

function Get-CleanupScopeLabel {
    param([ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")][string]$Scope)
    $key = switch ($Scope) {
        "WindowsOffice" { "cleanup.scope.windowsOffice" }
        "WindowsThirdParty" { "cleanup.scope.windowsThirdParty" }
        "OfficeThirdParty" { "cleanup.scope.officeThirdParty" }
        "ThirdParty" { "cleanup.scope.thirdParty" }
        "Windows" { "cleanup.scope.windows" }
        "Office" { "cleanup.scope.office" }
        default { "cleanup.scope.all" }
    }
    return Get-DashboardText $key
}

function ConvertTo-CleanupScanScope {
    param([bool]$Windows, [bool]$Office, [bool]$ThirdParty)

    $selectionKey = "{0}{1}{2}" -f [int]$Windows, [int]$Office, [int]$ThirdParty
    switch ($selectionKey) {
        "100" { return "Windows" }
        "010" { return "Office" }
        "001" { return "ThirdParty" }
        "110" { return "WindowsOffice" }
        "101" { return "WindowsThirdParty" }
        "011" { return "OfficeThirdParty" }
        "111" { return "All" }
        default { return "" }
    }
}

function Test-GuiCleanupScopeIncludes {
    param(
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")][string]$Scope,
        [ValidateSet("Windows", "Office", "ThirdParty")][string]$Component
    )

    switch ($Component) {
        "Windows" { return [bool]($Scope -in @("All", "Windows", "WindowsOffice", "WindowsThirdParty")) }
        "Office" { return [bool]($Scope -in @("All", "Office", "WindowsOffice", "OfficeThirdParty")) }
        "ThirdParty" { return [bool]($Scope -in @("All", "ThirdParty", "WindowsThirdParty", "OfficeThirdParty")) }
    }
    return $false
}

function Get-GuiCleanupItemComponentScope {
    param($CleanupItem)

    if ($CleanupItem.PSObject.Properties['ComponentScope']) {
        $explicitScope = [string]$CleanupItem.ComponentScope
        if ($explicitScope -in @("Windows", "Office", "ThirdParty", "Shared")) { return $explicitScope }
    }
    $type = [string]$CleanupItem.Type
    $kind = [string]$CleanupItem.Kind
    $text = (([string]$CleanupItem.Name) + " " + ([string]$CleanupItem.Location) + " " + ([string]$CleanupItem.Detail)).Trim()
    if ($type -eq "Application" -or $kind -match '^ThirdParty') { return "ThirdParty" }
    if ($kind -eq "OfficeKmsLicense" -or $text -match '(?i)OfficeSoftwareProtectionPlatform|\bospp(?:svc|\.vbs)?\b|\bOffice\s+KMS\b') { return "Office" }
    if ($kind -eq "WindowsKmsLicense" -or $kind -eq "SppNoGenTicketPolicy" -or
        $text -match '(?i)Windows NT\\CurrentVersion\\SoftwareProtectionPlatform|\bsppsvc\b|\bSppExtComObj\b|\bNoGenTicket\b') { return "Windows" }
    return "Shared"
}

function Get-GuiScopedCleanupItems {
    param(
        $CleanupItems,
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")][string]$Scope = "All"
    )
    return @($CleanupItems | Where-Object {
        $componentScope = Get-GuiCleanupItemComponentScope -CleanupItem $_
        if ($componentScope -eq "Shared") {
            return [bool]((Test-GuiCleanupScopeIncludes -Scope $Scope -Component "Windows") -or
                (Test-GuiCleanupScopeIncludes -Scope $Scope -Component "Office"))
        }
        return Test-GuiCleanupScopeIncludes -Scope $Scope -Component $componentScope
    })
}

function Start-Cleanup {
    param(
        [switch]$ReuseSessionSettings,
        [switch]$AutoSafeMode,
        [switch]$DryRunMode,
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")][string]$ScanScope = "All"
    )
    if (-not (Test-Path -LiteralPath $cleanupScript)) {
        $script:cleanupAutoSafeMode = $false
        $script:cleanupDryRunMode = $false
        [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "cleanup.moduleMissing"),
            (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    if (-not $ReuseSessionSettings) {
        # A newly requested scan starts a new navigation session.  Never let a
        # later Back action reuse candidates from an older machine snapshot.
        $script:cleanupPreviousSession = $null
        $script:cleanupScanScope = $ScanScope
        $script:cleanupAutoSafeMode = [bool]$AutoSafeMode
        $script:cleanupDryRunMode = [bool]$DryRunMode
        if (((Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "Windows") -or
            (Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "Office")) -and
            -not (Confirm-KmsApprovalConfiguration)) {
            $script:cleanupAutoSafeMode = $false
            $status.Text = Get-DashboardText "cleanup.kmsCancelled"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog (Get-DashboardText "cleanup.kmsNotConfirmed")
            return
        }
        $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "cleanup.privacy.prompt"),
            (Get-DashboardText "cleanup.privacy.title"),
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Information,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1)
        if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) {
            $script:cleanupAutoSafeMode = $false
            $script:cleanupDryRunMode = $false
            return
        }
        $script:cleanupRedactSensitive = [bool]($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    try {
        Start-ProgressDisplay (Get-DashboardText "cleanup.scan.action") (Get-DashboardText "cleanup.scan.detail") $false
        Write-ProgressLog (Get-DashboardText "cleanup.scan.scopeLog" @((Get-CleanupScopeLabel -Scope $script:cleanupScanScope)))
        $output = New-ToolReportRunDirectory -Category "KhacPhuc-Quet"
        $script:cleanupDecisionFile = New-SecureRuntimePath "tool-license-decision-"
        $privacyArgument = if ($script:cleanupRedactSensitive) { " -RedactSensitive" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$cleanupScript`" -OutputDir `"$output`" -ApprovedKmsServerFile `"$approvedKmsFile`" -TreatUnapprovedKmsAsNonCompliant -DecisionFile `"$script:cleanupDecisionFile`" -ScanScope `"$script:cleanupScanScope`" -Culture `"$script:dashboardCulture`"$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "cleanup.scan" -Arguments $arguments -Action (Get-DashboardText "cleanup.scan.action") -Elevate -Hidden)
        $status.Text = Get-DashboardText "cleanup.scan.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        $script:cleanupAutoSafeMode = $false
        $script:cleanupDryRunMode = $false
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-DashboardText "cleanup.scan.startFailed" @($_.Exception.Message))
    }
}

function Start-ThirdPartyManualReview {
    # Menu 5 is report-only.  Every state-changing software action is exposed
    # exclusively from menu 6 (Khắc phục), after a fresh synchronized scan,
    # explicit selection, backup/preview and final confirmation.
    Start-Report "Software" (Get-ToolText -Key "menu.5.title" -Culture $script:dashboardCulture)
}
