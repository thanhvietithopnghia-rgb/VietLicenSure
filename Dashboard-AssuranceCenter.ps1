# VietLicenSure v5.0 - dot-sourced function library
# Extracted mechanically from Giao-Dien.ps1; contains function definitions only.
# Keep this file beside its compatible entrypoint.

function Start-AssuranceReport {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("CertificateAudit","PluginAudit","TimelineExport")][string]$Operation,
        [Parameter(Mandatory = $true)][string]$ModuleId,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    if (-not (Test-Path -LiteralPath $assuranceScript -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "report.missingModule" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "report.errorTitle" -Culture $script:dashboardCulture),
            "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
        (Get-ToolText -Key "report.privacy.prompt" -Culture $script:dashboardCulture),
        (Get-ToolText -Key "report.privacy.title" -Culture $script:dashboardCulture),
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button1)
    if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
    $redactArgument = if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes) { " -RedactSensitive" } else { "" }
    try {
        Start-ProgressDisplay $DisplayName (Get-ToolText -Key "report.starting" -Culture $script:dashboardCulture) $false
        $output = New-ToolReportRunDirectory -Category "BaoDam-$Operation"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$assuranceScript`" -Operation `"$Operation`" -OutputDir `"$output`" -Culture `"$script:dashboardCulture`" -Pdf$redactArgument"
        [void](Start-ToolModuleProcess -ModuleId $ModuleId -Arguments $arguments -Action $DisplayName -Hidden)
        $status.Text = Get-ToolText -Key "report.running" -Culture $script:dashboardCulture -FormatArguments @($DisplayName)
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-ToolText -Key "report.startFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message))
    }
}

function Show-PluginTrustedPublisherPolicyRequired {
    param([Parameter(Mandatory = $true)][string]$PolicyPath)

    [System.Windows.Forms.MessageBox]::Show(
        (Get-DashboardText "plugin.trustedPublisherPolicyMissing" @($PolicyPath)),
        (Get-DashboardText "plugin.trustedPublisherPolicyMissingTitle"),
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    Write-ProgressLog (Get-DashboardText "plugin.trustedPublisherPolicyMissingLog" @($PolicyPath))
}

function Install-PluginFromDialog {
    $pluginDirectory = Get-ToolPluginDirectory
    try {
        if (-not (Test-Path -LiteralPath $pluginDirectory -PathType Container) -and $env:TOOL_SECURE_LAUNCH -ne "1") {
            New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null
        }
        $directoryState = Test-ToolPluginDirectory -Path $pluginDirectory
        if (-not $directoryState.Valid) { throw ($directoryState.Errors -join "; ") }
        $requireTrustedPluginSignature = [bool]($env:TOOL_SECURE_LAUNCH -eq '1')
        $trustedPluginSigners = @(Get-ToolPluginTrustedSignerCertificateSha256 -PluginDirectory $directoryState.Path)
        if ($requireTrustedPluginSignature -and $trustedPluginSigners.Count -eq 0) {
            Show-PluginTrustedPublisherPolicyRequired -PolicyPath (Get-ToolPluginPublisherTrustPath -PluginDirectory $directoryState.Path)
            return
        }
        $picker = New-Object System.Windows.Forms.OpenFileDialog
        $picker.Title = Get-DashboardText "plugin.pickerTitle"
        $picker.Filter = Get-DashboardText "plugin.pickerFilter"
        $picker.Multiselect = $false
        if ($picker.ShowDialog((Get-DashboardDialogOwner)) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $catalogInstall = [bool]$picker.FileName.EndsWith('.plugin-catalog.json', [StringComparison]::OrdinalIgnoreCase)
        $catalogResult = $null
        if ($catalogInstall) {
            if ($trustedPluginSigners.Count -eq 0) {
                Show-PluginTrustedPublisherPolicyRequired -PolicyPath (Get-ToolPluginPublisherTrustPath -PluginDirectory $directoryState.Path)
                return
            }
            $catalogResult = Read-ToolPluginCatalog -Path $picker.FileName `
                -TrustedSignerCertificateSha256 $trustedPluginSigners
            if (-not $catalogResult.Valid) { throw ($catalogResult.Errors -join "`r`n") }
            if (-not $catalogResult.InstallationAllowed) {
                throw (Get-DashboardText 'foundation.plugin.catalogInstallBlocked' @($catalogResult.FreshnessStatus))
            }
            $packagePicker = New-Object System.Windows.Forms.OpenFileDialog
            $packagePicker.Title = Get-DashboardText 'plugin.catalogPackagePickerTitle'
            $packagePicker.Filter = Get-DashboardText 'plugin.catalogPackagePickerFilter'
            $packagePicker.Multiselect = $false
            if ($packagePicker.ShowDialog((Get-DashboardDialogOwner)) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $package = Read-ToolPluginPackage -Path $packagePicker.FileName -AllowOutsideProtectedDirectory `
                -TrustedSignerCertificateSha256 @([string]$catalogResult.SignerCertificateSha256) -RequireTrustedSignature
        } else {
            $package = Read-ToolPluginPackage -Path $picker.FileName -AllowOutsideProtectedDirectory `
                -TrustedSignerCertificateSha256 $trustedPluginSigners -RequireTrustedSignature:$requireTrustedPluginSignature
        }
        if (-not $package.Valid) { throw ($package.Errors -join "`r`n") }
        $plugin = $package.Plugin
        if ($catalogInstall) {
            $catalogEntries = @($catalogResult.Entries | Where-Object {
                [string]::Equals([string]$_.PluginId, [string]$plugin.PluginId, [StringComparison]::Ordinal)
            })
            if ($catalogEntries.Count -ne 1 -or
                -not [string]::Equals([string]$catalogEntries[0].Version, [string]$plugin.Version, [StringComparison]::Ordinal)) {
                throw (Get-DashboardText 'foundation.plugin.catalogPackageIdentityMismatch')
            }
            if (-not [string]::Equals([string]$catalogEntries[0].PackageSha256, [string]$package.Sha256, [StringComparison]::OrdinalIgnoreCase)) {
                throw (Get-DashboardText 'foundation.plugin.catalogPackageHashMismatch')
            }
        }
        $promptKey = if ($catalogInstall) { 'plugin.catalogInstallPrompt' } else { 'plugin.installPrompt' }
        $promptArguments = if ($catalogInstall) {
            @($plugin.Name, $plugin.PluginId, $plugin.Version, $plugin.Publisher, @($plugin.Rules).Count, $package.Sha256,
                $catalogResult.Catalog.CatalogId, $catalogResult.FreshnessStatus, $catalogResult.SignerCertificateSha256)
        } else {
            @($plugin.Name, $plugin.PluginId, $plugin.Version, $plugin.Publisher, @($plugin.Rules).Count, $package.Sha256)
        }
        $confirmation = [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText $promptKey $promptArguments),
            (Get-DashboardText "plugin.confirmTitle"),
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $destination = Join-Path $directoryState.Path "$([string]$plugin.PluginId).plugin.json"
        $force = $false
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $overwrite = [System.Windows.Forms.MessageBox]::Show(
                (Get-DashboardText "plugin.overwritePrompt"),
                (Get-DashboardText "plugin.existsTitle"), "YesNo", "Warning")
            if ($overwrite -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $force = $true
        }
        $installed = if ($catalogInstall) {
            Install-ToolPluginPackageFromCatalog -CatalogPath $picker.FileName -PluginId ([string]$plugin.PluginId) `
                -SourcePath $package.Path -PluginDirectory $directoryState.Path -Force:$force `
                -TrustedSignerCertificateSha256 $trustedPluginSigners
        } else {
            Install-ToolPluginPackage -SourcePath $package.Path -PluginDirectory $directoryState.Path -Force:$force `
                -TrustedSignerCertificateSha256 $trustedPluginSigners -RequireTrustedSignature:$requireTrustedPluginSignature
        }
        [void](Write-ToolLog -Level "AUDIT" -Event "Plugin.Installed" -Message $installed.Name -Data ([ordered]@{
            PluginId=$installed.PluginId; Version=$installed.Version; Publisher=$installed.Publisher; Sha256=$installed.Sha256
            CatalogId=$(if ($installed.PSObject.Properties['CatalogId']) { [string]$installed.CatalogId } else { '' })
        }))
        [void](Write-LicenseTimelineEventSafe -EventType "PluginInstalled" -Source "GUI" -IsChange:$true -Data ([ordered]@{
            PluginId=$installed.PluginId; Version=$installed.Version; Publisher=$installed.Publisher; Sha256=$installed.Sha256
            CatalogId=$(if ($installed.PSObject.Properties['CatalogId']) { [string]$installed.CatalogId } else { '' })
        }))
        [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "plugin.installedMessage" @($installed.Path, $installed.Sha256)),
            (Get-DashboardText "plugin.installedTitle"), "OK", "Information") | Out-Null
        Write-ProgressLog (Get-DashboardText "plugin.installedLog" @($installed.PluginId, $installed.Version))
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, (Get-DashboardText "plugin.failedTitle"), "OK", "Error") | Out-Null
        Write-ProgressLog (Get-DashboardText "plugin.rejectedLog" @($_.Exception.Message))
    }
}

function Get-ResultCenterSeverityText {
    param([ValidateSet("High", "Medium", "Low")][string]$Severity)
    return Get-DashboardText ("resultCenter.severity." + $Severity.ToLowerInvariant())
}

function Get-ResultCenterComparisonText {
    param([ValidateSet("New", "Resolved", "Unchanged", "NoBaseline")][string]$ComparisonStatus)
    $key = switch ($ComparisonStatus) {
        "New" { "resultCenter.comparison.new" }
        "Resolved" { "resultCenter.comparison.resolved" }
        "Unchanged" { "resultCenter.comparison.unchanged" }
        default { "resultCenter.comparison.noBaseline" }
    }
    return Get-DashboardText $key
}

function Get-ResultCenterCategoryText {
    param([ValidateSet("Hardware", "Windows", "Office", "Software")][string]$Category)
    return Get-DashboardText ("resultCenter.category." + $Category.ToLowerInvariant())
}

function Get-ResultCenterDisplayName {
    param([Parameter(Mandatory = $true)][object]$Item)
    if ([string]$Item.StatusCode -eq "TechnicalInterventionIndicator") { return Get-DashboardText "resultCenter.name.technicalIndicator" }
    if ([string]$Item.Name -eq "Unknown software") { return Get-DashboardText "resultCenter.name.unknownSoftware" }
    return [string]$Item.Name
}

function Get-ResultCenterStatusText {
    param([Parameter(Mandatory = $true)][object]$Item)
    $code = [string]$Item.StatusCode
    $category = [string]$Item.Category
    if ($category -in @("Windows", "Office")) {
        $suffix = switch ($code) {
            "Unverifiable" { "unverifiable" }
            "NotLicensed" { "notLicensed" }
            "KmsApprovedHost" { "kmsApproved" }
            "KmsUnapprovedHost" { "kmsUnapproved" }
            "KmsEntitlementUnverified" { "kmsUnverified" }
            "ActivatedEntitlementUnverified" { "activatedUnverified" }
            default { "" }
        }
        if (-not [string]::IsNullOrWhiteSpace($suffix)) {
            return Get-DashboardText ("report.license." + $category.ToLowerInvariant() + "." + $suffix)
        }
    }
    if ($category -eq "Hardware") {
        $hardwareKey = switch ($code) {
            "Disabled" { "resultCenter.status.secureBootDisabled" }
            "NotPresent" { "resultCenter.status.tpmUnavailable" }
            "NotReady" { "resultCenter.status.tpmUnavailable" }
            "Unverified" {
                if ([string]$Item.Name -eq "TPM") { "resultCenter.status.tpmUnverified" } else { "resultCenter.status.secureBootUnverified" }
            }
            default { "" }
        }
        if (-not [string]::IsNullOrWhiteSpace($hardwareKey)) { return Get-DashboardText $hardwareKey }
    }
    if ($code -eq "TechnicalInterventionIndicator") { return Get-DashboardText "resultCenter.status.technicalIntervention" }
    if (-not [string]::IsNullOrWhiteSpace([string]$Item.StatusText)) { return [string]$Item.StatusText }
    return $code
}

function Open-ResultCenterReport {
    param([AllowNull()][string]$ReportPath)
    if ([string]::IsNullOrWhiteSpace($ReportPath) -or -not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "resultCenter.reportMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Warning") | Out-Null
        return
    }
    $htmlPath = [IO.Path]::ChangeExtension($ReportPath, ".html")
    if (Test-Path -LiteralPath $htmlPath -PathType Leaf) {
        [void](Open-ToolHtmlReport -Path $htmlPath)
    } else {
        Register-ToolReportPath -Path $ReportPath
        Start-Process -FilePath $nativeNotepadPath -ArgumentList ('"' + $ReportPath + '"')
    }
}

function Invoke-ResultCenterItemAction {
    param([AllowNull()][object]$Item)
    if ($null -eq $Item) { return $false }
    switch ([string]$Item.ActionCode) {
        "OpenHardware" {
            Start-Report "Hardware" (Get-DashboardText "menu.2.title")
            return $true
        }
        "OpenWindows" { return [bool](Show-CleanupFunctionScreen -Mode "Cleanup" -FixedScope "Windows") }
        "OpenOffice" { return [bool](Show-CleanupFunctionScreen -Mode "Cleanup" -FixedScope "Office") }
        "OpenSoftwareRemediation" { return [bool](Show-CleanupFunctionScreen -Mode "Cleanup" -FixedScope "ThirdParty") }
        "ReviewSoftware" {
            Start-ThirdPartyManualReview
            return $true
        }
        default {
            Open-ResultCenterReport -ReportPath ([string]$Item.SourceReportPath)
            return $false
        }
    }
}

function Update-ResultActionCard {
    param([switch]$UseCachedState, [switch]$HeaderOnly)
    if (-not $dashboardCards.ContainsKey("ActionCenter")) { return }
    $card = $dashboardCards["ActionCenter"]
    try {
        if ($HeaderOnly -and $null -eq $script:resultCenterState) {
            $candidate = @(Get-ToolResultReportCandidates -ReportRoot $reportRoot -MaximumCandidates 1)
            if ($candidate.Count -eq 0) {
                $card.Value.Text = Get-DashboardText "resultCenter.card.noReport"
                $tooltip = Get-DashboardText "resultCenter.card.noReportTooltip"
            } else {
                $card.Value.Text = Get-DashboardText "resultCenter.card.ready"
                $tooltip = Get-DashboardText "resultCenter.card.readyTooltip" @($candidate[0].LastWriteTime.ToString("g"))
            }
            $card.Value.ForeColor = (Get-DashboardStatusPalette -Tone Action -Mode $script:dashboardTheme).ValueColor
            $card.Value.Tag = $null
            $toolTip.SetToolTip($card.Panel, $tooltip)
            $toolTip.SetToolTip($card.Caption, $tooltip)
            $toolTip.SetToolTip($card.Value, $tooltip)
            Sync-DashboardCardAccessibility -CardKey "ActionCenter" -Detail $tooltip
            return
        }
        if (-not $UseCachedState -or $null -eq $script:resultCenterState) {
            $script:resultCenterState = Get-ToolResultCenterState -ReportRoot $reportRoot -MaximumReports 40
        }
        $state = $script:resultCenterState
        if (-not $state -or -not [bool]$state.HasReport) {
            $card.Value.Text = Get-DashboardText "resultCenter.card.noReport"
            $card.Value.ForeColor = (Get-DashboardStatusPalette -Tone Action -Mode $script:dashboardTheme).ValueColor
            $card.Value.Tag = $null
            $tooltip = Get-DashboardText "resultCenter.card.noReportTooltip"
        } else {
            $card.Value.Text = Get-DashboardText "resultCenter.card.summary" @([int]$state.HighCount, [int]$state.MediumCount, [int]$state.LowCount)
            $card.Value.ForeColor = if (Test-ToolUiHighContrast) {
                [System.Drawing.SystemColors]::WindowText
            } elseif ([int]$state.HighCount -gt 0) {
                if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(255, 142, 142) } else { [System.Drawing.Color]::FromArgb(185, 28, 28) }
            } elseif ([int]$state.MediumCount -gt 0) {
                if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(255, 193, 82) } else { [System.Drawing.Color]::FromArgb(180, 83, 9) }
            } else {
                if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(86, 230, 156) } else { [System.Drawing.Color]::FromArgb(0, 125, 69) }
            }
            $card.Value.Tag = "StatusColor"
            $latestText = if ($state.Latest) { $state.Latest.CreatedAt.ToString("g") } else { Get-DashboardText "common.unknown" }
            $tooltip = Get-DashboardText "resultCenter.card.resultTooltip" @($latestText, [string]$state.Latest.Mode)
        }
        $toolTip.SetToolTip($card.Panel, $tooltip)
        $toolTip.SetToolTip($card.Caption, $tooltip)
        $toolTip.SetToolTip($card.Value, $tooltip)
        Sync-DashboardCardAccessibility -CardKey "ActionCenter" -Detail $tooltip
    } catch {
        $card.Value.Text = Get-DashboardText "resultCenter.card.unavailable"
        $toolTip.SetToolTip($card.Panel, $_.Exception.Message)
        Sync-DashboardCardAccessibility -CardKey "ActionCenter" -Detail ([string]$_.Exception.Message)
    }
}

function Show-ResultActionCenter {
    $hasPreviousStep = [bool]($script:dashboardDialogStack.Count -gt 0)
    $form.UseWaitCursor = $true
    try { $state = Get-ToolResultCenterState -ReportRoot $reportRoot -MaximumReports 80 }
    catch { $state = [pscustomobject]@{ HasReport=$false; HasBaseline=$false; Latest=$null; Previous=$null; Items=@(); HighCount=0; MediumCount=0; LowCount=0 } }
    finally { $form.UseWaitCursor = $false }
    $script:resultCenterState = $state
    Update-ResultActionCard -UseCachedState

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "resultCenter.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MaximizeBox = $true
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(620, [Math]::Min(1180, $workArea.Width - 30))
    $dialogHeight = [Math]::Max(500, [Math]::Min(760, $workArea.Height - 30))
    $dialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(720, $dialogWidth), [Math]::Min(500, $dialogHeight))
    $dialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $dialog.Font = $fontNormal
    $dialog.Tag = "Close"

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
    $layout.ColumnCount = 1
    $layout.RowCount = 5
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 66)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 48)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 54)))
    $dialog.Controls.Add($layout)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Fill"
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "resultCenter.heading"
    $heading.Font = $fontTitle
    $heading.Location = New-Object System.Drawing.Point(4, 0)
    $heading.Size = New-Object System.Drawing.Size(($dialogWidth - 50), 30)
    $heading.Anchor = "Top,Left,Right"
    $header.Controls.Add($heading)
    $baseline = New-Object System.Windows.Forms.Label
    if (-not [bool]$state.HasReport) {
        $baseline.Text = Get-DashboardText "resultCenter.noReport"
    } elseif ([bool]$state.HasBaseline) {
        $baseline.Text = Get-DashboardText "resultCenter.baseline" @($state.Latest.CreatedAt.ToString("g"), $state.Previous.CreatedAt.ToString("g"), [string]$state.Latest.Mode)
    } else {
        $baseline.Text = Get-DashboardText "resultCenter.noBaseline" @($state.Latest.CreatedAt.ToString("g"), [string]$state.Latest.Mode)
    }
    $baseline.Location = New-Object System.Drawing.Point(5, 34)
    $baseline.Size = New-Object System.Drawing.Size(($dialogWidth - 50), 25)
    $baseline.Anchor = "Top,Left,Right"
    $baseline.AutoEllipsis = $true
    $header.Controls.Add($baseline)
    $layout.Controls.Add($header, 0, 0)

    $filterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $filterPanel.Dock = "Fill"
    $filterPanel.FlowDirection = "LeftToRight"
    $filterPanel.WrapContents = $false
    $filterPanel.AutoScroll = $true
    $filterPanel.Padding = New-Object System.Windows.Forms.Padding(2, 7, 2, 2)
    $searchLabel = New-Object System.Windows.Forms.Label
    $searchLabel.Text = Get-DashboardText "resultCenter.search"
    $searchLabel.AutoSize = $true
    $searchLabel.Margin = New-Object System.Windows.Forms.Padding(2, 7, 6, 0)
    $filterPanel.Controls.Add($searchLabel)
    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Width = 250
    $searchBox.Margin = New-Object System.Windows.Forms.Padding(0, 3, 18, 0)
    $filterPanel.Controls.Add($searchBox)
    $severityLabel = New-Object System.Windows.Forms.Label
    $severityLabel.Text = Get-DashboardText "resultCenter.severity"
    $severityLabel.AutoSize = $true
    $severityLabel.Margin = New-Object System.Windows.Forms.Padding(0, 7, 6, 0)
    $filterPanel.Controls.Add($severityLabel)
    $severityCombo = New-Object System.Windows.Forms.ComboBox
    $severityCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $severityCombo.Width = 145
    foreach ($text in @((Get-DashboardText "resultCenter.filter.all"), (Get-ResultCenterSeverityText High), (Get-ResultCenterSeverityText Medium), (Get-ResultCenterSeverityText Low))) { [void]$severityCombo.Items.Add($text) }
    $severityCombo.SelectedIndex = 0
    $severityCombo.Margin = New-Object System.Windows.Forms.Padding(0, 3, 18, 0)
    $filterPanel.Controls.Add($severityCombo)
    $comparisonLabel = New-Object System.Windows.Forms.Label
    $comparisonLabel.Text = Get-DashboardText "resultCenter.comparison"
    $comparisonLabel.AutoSize = $true
    $comparisonLabel.Margin = New-Object System.Windows.Forms.Padding(0, 7, 6, 0)
    $filterPanel.Controls.Add($comparisonLabel)
    $comparisonCombo = New-Object System.Windows.Forms.ComboBox
    $comparisonCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $comparisonCombo.Width = 170
    foreach ($text in @((Get-DashboardText "resultCenter.filter.all"), (Get-ResultCenterComparisonText New), (Get-ResultCenterComparisonText Resolved), (Get-ResultCenterComparisonText Unchanged), (Get-ResultCenterComparisonText NoBaseline))) { [void]$comparisonCombo.Items.Add($text) }
    $comparisonCombo.SelectedIndex = 0
    $comparisonCombo.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
    $filterPanel.Controls.Add($comparisonCombo)
    $layout.Controls.Add($filterPanel, 0, 1)

    $resultList = New-Object System.Windows.Forms.ListView
    $resultList.Dock = "Fill"
    $resultList.View = [System.Windows.Forms.View]::Details
    $resultList.FullRowSelect = $true
    $resultList.GridLines = $true
    $resultList.HideSelection = $false
    $resultList.MultiSelect = $false
    $resultList.ShowItemToolTips = $true
    [void]$resultList.Columns.Add((Get-DashboardText "resultCenter.column.comparison"), 125)
    [void]$resultList.Columns.Add((Get-DashboardText "resultCenter.column.severity"), 100)
    [void]$resultList.Columns.Add((Get-DashboardText "resultCenter.column.category"), 115)
    [void]$resultList.Columns.Add((Get-DashboardText "resultCenter.column.name"), 230)
    [void]$resultList.Columns.Add((Get-DashboardText "resultCenter.column.publisher"), 190)
    [void]$resultList.Columns.Add((Get-DashboardText "resultCenter.column.status"), 260)
    $layout.Controls.Add($resultList, 0, 2)

    $countLabel = New-Object System.Windows.Forms.Label
    $countLabel.Dock = "Fill"
    $countLabel.TextAlign = "MiddleLeft"
    $layout.Controls.Add($countLabel, 0, 3)

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = "Fill"
    $footer.FlowDirection = "RightToLeft"
    $footer.WrapContents = $false
    $footer.AutoScroll = $true
    $footer.Padding = New-Object System.Windows.Forms.Padding(0, 7, 0, 0)
    $layout.Controls.Add($footer, 0, 4)

    $closeButtonLocal = New-Object System.Windows.Forms.Button
    $closeButtonLocal.Text = Get-DashboardText "common.close"
    $closeButtonLocal.Size = New-Object System.Drawing.Size(104, 38)
    $closeButtonLocal.Add_Click({ $dialog.Tag = "Close"; Close-DashboardWorkflowSession -Dialog $dialog })
    $footer.Controls.Add($closeButtonLocal)
    if ($hasPreviousStep) {
        $backButtonLocal = New-Object System.Windows.Forms.Button
        $backButtonLocal.Text = Get-DashboardText "common.back"
        $backButtonLocal.Size = New-Object System.Drawing.Size(104, 38)
        $backButtonLocal.Add_Click({ $dialog.Tag = "Back"; $dialog.Close() })
        $dialog.CancelButton = $backButtonLocal
        $footer.Controls.Add($backButtonLocal)
    } else {
        $dialog.CancelButton = $closeButtonLocal
    }
    $directButton = New-Object System.Windows.Forms.Button
    $directButton.Text = Get-DashboardText "resultCenter.openFunction"
    $directButton.Font = $fontBold
    $directButton.Size = New-Object System.Drawing.Size(154, 38)
    $directButton.Enabled = $false
    $footer.Controls.Add($directButton)
    $openReportButton = New-Object System.Windows.Forms.Button
    $openReportButton.Text = Get-DashboardText "common.openReport"
    $openReportButton.Size = New-Object System.Drawing.Size(132, 38)
    $openReportButton.Enabled = $false
    $footer.Controls.Add($openReportButton)
    $supportButton = New-Object System.Windows.Forms.Button
    $supportButton.Text = Get-DashboardText "supportBundle.button"
    $supportButton.Size = New-Object System.Drawing.Size(146, 38)
    $supportButton.Add_Click({ Show-SupportBundlePreview })
    $footer.Controls.Add($supportButton)
    $backupButtonLocal = New-Object System.Windows.Forms.Button
    $backupButtonLocal.Text = Get-DashboardText "backupCenter.button"
    $backupButtonLocal.Size = New-Object System.Drawing.Size(176, 38)
    $backupButtonLocal.Add_Click({ Show-BackupRestoreCenter })
    $footer.Controls.Add($backupButtonLocal)
    $scanButton = New-Object System.Windows.Forms.Button
    $scanButton.Text = Get-DashboardText "resultCenter.scanNow"
    $scanButton.Size = New-Object System.Drawing.Size(112, 38)
    $scanButton.Add_Click({ $dialog.Close(); Start-Report "All" (Get-DashboardText "menu.1.title") })
    $footer.Controls.Add($scanButton)

    $severityValues = @("All", "High", "Medium", "Low")
    $comparisonValues = @("All", "New", "Resolved", "Unchanged", "NoBaseline")
    $refreshList = {
        $selectedSeverity = $severityValues[[Math]::Max(0, $severityCombo.SelectedIndex)]
        $selectedComparison = $comparisonValues[[Math]::Max(0, $comparisonCombo.SelectedIndex)]
        $visibleItems = @(Select-ToolResultCenterItems -Items @($state.Items) -SearchText $searchBox.Text -Severity $selectedSeverity -ComparisonStatus $selectedComparison)
        $resultList.BeginUpdate()
        try {
            $resultList.Items.Clear()
            foreach ($item in $visibleItems) {
                $row = New-Object System.Windows.Forms.ListViewItem((Get-ResultCenterComparisonText ([string]$item.ComparisonStatus)))
                [void]$row.SubItems.Add((Get-ResultCenterSeverityText ([string]$item.Severity)))
                [void]$row.SubItems.Add((Get-ResultCenterCategoryText ([string]$item.Category)))
                $displayName = Get-ResultCenterDisplayName -Item $item
                $displayStatus = Get-ResultCenterStatusText -Item $item
                [void]$row.SubItems.Add($displayName)
                [void]$row.SubItems.Add([string]$item.Publisher)
                [void]$row.SubItems.Add($displayStatus)
                $row.Tag = $item
                $row.ToolTipText = ((@($displayName, $displayStatus, $item.EvidenceText) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join "`r`n")
                if ([string]$item.ComparisonStatus -eq "Resolved") { $row.ForeColor = [System.Drawing.Color]::DarkGreen }
                elseif ([string]$item.Severity -eq "High") { $row.ForeColor = [System.Drawing.Color]::DarkRed }
                elseif ([string]$item.Severity -eq "Medium") { $row.ForeColor = [System.Drawing.Color]::DarkOrange }
                [void]$resultList.Items.Add($row)
            }
        } finally { $resultList.EndUpdate() }
        $countLabel.Text = Get-DashboardText "resultCenter.visibleCount" @($visibleItems.Count, @($state.Items).Count)
        $directButton.Enabled = $false
        $openReportButton.Enabled = $false
    }
    $selectionChanged = {
        $selected = if ($resultList.SelectedItems.Count -gt 0) { $resultList.SelectedItems[0].Tag } else { $null }
        $directButton.Enabled = [bool]($null -ne $selected -and [string]$selected.ComparisonStatus -ne "Resolved")
        $openReportButton.Enabled = [bool]($null -ne $selected -and -not [string]::IsNullOrWhiteSpace([string]$selected.SourceReportPath))
    }
    $searchBox.Add_TextChanged($refreshList)
    $severityCombo.Add_SelectedIndexChanged($refreshList)
    $comparisonCombo.Add_SelectedIndexChanged($refreshList)
    $resultList.Add_SelectedIndexChanged($selectionChanged)
    $openReportButton.Add_Click({ if ($resultList.SelectedItems.Count -gt 0) { Open-ResultCenterReport -ReportPath ([string]$resultList.SelectedItems[0].Tag.SourceReportPath) } })
    $directButton.Add_Click({
        if ($resultList.SelectedItems.Count -gt 0) {
            $selectedItem = $resultList.SelectedItems[0].Tag
            if (Invoke-ResultCenterItemAction -Item $selectedItem) { $dialog.Close() }
        }
    })
    $resultList.Add_DoubleClick({
        if ($resultList.SelectedItems.Count -gt 0 -and [string]$resultList.SelectedItems[0].Tag.ComparisonStatus -ne "Resolved") {
            $selectedItem = $resultList.SelectedItems[0].Tag
            if (Invoke-ResultCenterItemAction -Item $selectedItem) { $dialog.Close() }
        }
    })

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    $dialogPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
    $heading.ForeColor = $dialogPalette.Primary
    & $refreshList
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $navigation = [string]$dialog.Tag
    $dialog.Dispose()
    if ($navigation -eq "Close" -and $hasPreviousStep -and -not (Test-DashboardWorkflowCloseRequested)) {
        $previousDialog = Get-DashboardDialogOwner
        if ($previousDialog -and -not [object]::ReferenceEquals($previousDialog, $form)) {
            Close-DashboardWorkflowSession -Dialog $previousDialog
        }
    }
}

function Show-BackupRestoreCenter {
    $hasPreviousStep = [bool]($script:dashboardDialogStack.Count -gt 0)
    $dataRoot = if (Get-Command Get-ToolDataRoot -ErrorAction SilentlyContinue) { Get-ToolDataRoot } elseif (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_DATA_ROOT)) { [string]$env:TOOL_DATA_ROOT } else { Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "ThanhViet-VietLicenSure\v4.6" }
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "backupCenter.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(620, [Math]::Min(1080, $workArea.Width - 30))
    $dialogHeight = [Math]::Max(470, [Math]::Min(680, $workArea.Height - 30))
    $dialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(720, $dialogWidth), [Math]::Min(470, $dialogHeight))
    $dialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $dialog.Font = $fontNormal
    $dialog.Tag = "Close"

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
    $layout.ColumnCount = 1
    $layout.RowCount = 4
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 76)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 54)))
    $dialog.Controls.Add($layout)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Fill"
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "backupCenter.heading"
    $heading.Font = $fontTitle
    $heading.Location = New-Object System.Drawing.Point(4, 0)
    $heading.Size = New-Object System.Drawing.Size(($dialogWidth - 50), 32)
    $heading.Anchor = "Top,Left,Right"
    $header.Controls.Add($heading)
    $summary = New-Object System.Windows.Forms.Label
    $summary.Text = Get-DashboardText "backupCenter.summary"
    $summary.Location = New-Object System.Drawing.Point(5, 36)
    $summary.Size = New-Object System.Drawing.Size(($dialogWidth - 50), 34)
    $summary.Anchor = "Top,Left,Right"
    $summary.AutoEllipsis = $true
    $header.Controls.Add($summary)
    $layout.Controls.Add($header, 0, 0)

    $toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
    $toolbar.Dock = "Fill"
    $toolbar.FlowDirection = "LeftToRight"
    $toolbar.WrapContents = $false
    $toolbar.Padding = New-Object System.Windows.Forms.Padding(2, 5, 2, 2)
    $scopeLabel = New-Object System.Windows.Forms.Label
    $scopeLabel.Text = Get-DashboardText "backupCenter.restoreScope"
    $scopeLabel.AutoSize = $true
    $scopeLabel.Margin = New-Object System.Windows.Forms.Padding(2, 7, 6, 0)
    $toolbar.Controls.Add($scopeLabel)
    $scopeCombo = New-Object System.Windows.Forms.ComboBox
    $scopeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $scopeCombo.Width = 190
    foreach ($text in @((Get-CleanupScopeLabel All), (Get-CleanupScopeLabel Windows), (Get-CleanupScopeLabel Office), (Get-CleanupScopeLabel ThirdParty))) { [void]$scopeCombo.Items.Add($text) }
    $scopeCombo.SelectedIndex = 0
    $toolbar.Controls.Add($scopeCombo)
    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Text = Get-DashboardText "backupCenter.refresh"
    $refreshButton.Size = New-Object System.Drawing.Size(118, 32)
    $refreshButton.Margin = New-Object System.Windows.Forms.Padding(18, 1, 0, 0)
    $toolbar.Controls.Add($refreshButton)
    $layout.Controls.Add($toolbar, 0, 1)

    $backupList = New-Object System.Windows.Forms.ListView
    $backupList.Dock = "Fill"
    $backupList.View = [System.Windows.Forms.View]::Details
    $backupList.FullRowSelect = $true
    $backupList.GridLines = $true
    $backupList.HideSelection = $false
    $backupList.MultiSelect = $false
    $backupList.ShowItemToolTips = $true
    [void]$backupList.Columns.Add((Get-DashboardText "backupCenter.column.date"), 165)
    [void]$backupList.Columns.Add((Get-DashboardText "backupCenter.column.scope"), 130)
    [void]$backupList.Columns.Add((Get-DashboardText "backupCenter.column.items"), 85)
    [void]$backupList.Columns.Add((Get-DashboardText "backupCenter.column.integrity"), 150)
    [void]$backupList.Columns.Add((Get-DashboardText "backupCenter.column.folder"), 420)
    $layout.Controls.Add($backupList, 0, 2)

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = "Fill"
    $footer.FlowDirection = "RightToLeft"
    $footer.WrapContents = $false
    $footer.AutoScroll = $true
    $footer.Padding = New-Object System.Windows.Forms.Padding(0, 7, 0, 0)
    $layout.Controls.Add($footer, 0, 3)
    $closeBackupButton = New-Object System.Windows.Forms.Button
    $closeBackupButton.Text = Get-DashboardText "common.close"
    $closeBackupButton.Size = New-Object System.Drawing.Size(104, 38)
    $closeBackupButton.Add_Click({ $dialog.Tag = "Close"; Close-DashboardWorkflowSession -Dialog $dialog })
    $footer.Controls.Add($closeBackupButton)
    if ($hasPreviousStep) {
        $backBackupButton = New-Object System.Windows.Forms.Button
        $backBackupButton.Text = Get-DashboardText "common.back"
        $backBackupButton.Size = New-Object System.Drawing.Size(104, 38)
        $backBackupButton.Add_Click({ $dialog.Tag = "Back"; $dialog.Close() })
        $dialog.CancelButton = $backBackupButton
        $footer.Controls.Add($backBackupButton)
    } else {
        $dialog.CancelButton = $closeBackupButton
    }
    $restoreButton = New-Object System.Windows.Forms.Button
    $restoreButton.Text = Get-DashboardText "backupCenter.restore"
    $restoreButton.Font = $fontBold
    $restoreButton.Size = New-Object System.Drawing.Size(142, 38)
    $restoreButton.Enabled = $false
    $footer.Controls.Add($restoreButton)
    $verifyButton = New-Object System.Windows.Forms.Button
    $verifyButton.Text = Get-DashboardText "backupCenter.verify"
    $verifyButton.Size = New-Object System.Drawing.Size(130, 38)
    $verifyButton.Enabled = $false
    $footer.Controls.Add($verifyButton)
    $openFolderButton = New-Object System.Windows.Forms.Button
    $openFolderButton.Text = Get-DashboardText "backupCenter.openFolder"
    $openFolderButton.Size = New-Object System.Drawing.Size(150, 38)
    $openFolderButton.Enabled = $false
    $footer.Controls.Add($openFolderButton)
    $createButton = New-Object System.Windows.Forms.Button
    $createButton.Text = Get-DashboardText "backupCenter.create"
    $createButton.Size = New-Object System.Drawing.Size(150, 38)
    $createButton.Add_Click({
        if (Show-CleanupFunctionScreen -Mode "Backup") { $dialog.Close() }
    })
    $footer.Controls.Add($createButton)

    $refreshBackups = {
        $dialog.UseWaitCursor = $true
        try { $backupItems = @(Get-ToolBackupCenterItems -DataRoot $dataRoot -MaximumBackups 100) }
        finally { $dialog.UseWaitCursor = $false }
        $backupList.BeginUpdate()
        try {
            $backupList.Items.Clear()
            foreach ($backup in $backupItems) {
                $integrityText = Get-DashboardText ("backupCenter.integrity." + ([string]$backup.IntegrityStatus).ToLowerInvariant())
                $row = New-Object System.Windows.Forms.ListViewItem($backup.CreatedAt.ToString("g"))
                [void]$row.SubItems.Add((Get-CleanupScopeLabel -Scope $(if ([string]$backup.Scope -in @("All","Windows","Office","ThirdParty")) { [string]$backup.Scope } else { "All" })))
                [void]$row.SubItems.Add([string]$backup.ItemCount)
                [void]$row.SubItems.Add($integrityText)
                [void]$row.SubItems.Add([string]$backup.Name)
                $row.Tag = $backup
                $row.ToolTipText = [string]$backup.Directory
                [void]$backupList.Items.Add($row)
            }
        } finally { $backupList.EndUpdate() }
        $summary.Text = if ($backupItems.Count -gt 0) { Get-DashboardText "backupCenter.found" @($backupItems.Count, $dataRoot) } else { Get-DashboardText "backupCenter.none" @($dataRoot) }
        $verifyButton.Enabled = $false
        $restoreButton.Enabled = $false
        $openFolderButton.Enabled = $false
    }
    $verifySelected = {
        if ($backupList.SelectedItems.Count -eq 0) { return $null }
        $selectedRow = $backupList.SelectedItems[0]
        $backup = $selectedRow.Tag
        $dialog.UseWaitCursor = $true
        try { $check = Test-ToolBackupCenterItemIntegrity -BackupDirectory ([string]$backup.Directory) -DataRoot $dataRoot }
        finally { $dialog.UseWaitCursor = $false }
        $backup.IntegrityStatus = [string]$check.StatusCode
        $selectedRow.SubItems[3].Text = Get-DashboardText ("backupCenter.integrity." + ([string]$check.StatusCode).ToLowerInvariant())
        $restoreButton.Enabled = [bool]$check.Valid
        return $check
    }
    $backupList.Add_SelectedIndexChanged({
        $hasSelection = [bool]($backupList.SelectedItems.Count -gt 0)
        $verifyButton.Enabled = $hasSelection
        $openFolderButton.Enabled = $hasSelection
        $restoreButton.Enabled = [bool]($hasSelection -and [string]$backupList.SelectedItems[0].Tag.IntegrityStatus -eq "Valid")
    })
    $refreshButton.Add_Click($refreshBackups)
    $verifyButton.Add_Click({
        $check = & $verifySelected
        if ($check) {
            $message = if ($check.Valid) { Get-DashboardText "backupCenter.verifyPassed" @($check.CheckedFileCount) } else { Get-DashboardText "backupCenter.verifyFailed" @(($check.Errors -join "`r`n")) }
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "backupCenter.verifyTitle"), "OK", $(if ($check.Valid) { "Information" } else { "Warning" })) | Out-Null
        }
    })
    $openFolderButton.Add_Click({ if ($backupList.SelectedItems.Count -gt 0) { Start-Process -FilePath $nativeExplorerPath -ArgumentList ('"' + [string]$backupList.SelectedItems[0].Tag.Directory + '"') } })
    $restoreButton.Add_Click({
        if ($backupList.SelectedItems.Count -eq 0) { return }
        $check = & $verifySelected
        if (-not $check.Valid) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "backupCenter.restoreBlocked"), (Get-DashboardText "backupCenter.verifyTitle"), "OK", "Warning") | Out-Null
            return
        }
        $backupDirectory = [string]$backupList.SelectedItems[0].Tag.Directory
        $scopeValues = @("All", "Windows", "Office", "ThirdParty")
        $restoreSelectedScope = $scopeValues[[Math]::Max(0, $scopeCombo.SelectedIndex)]
        if (Start-CleanupRestore -Scope $restoreSelectedScope -BackupDirectory $backupDirectory) {
            $dialog.Close()
        }
    })

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    $dialogPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
    $heading.ForeColor = $dialogPalette.Primary
    & $refreshBackups
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $navigation = [string]$dialog.Tag
    $dialog.Dispose()
    if ($navigation -eq "Close" -and $hasPreviousStep -and -not (Test-DashboardWorkflowCloseRequested)) {
        $previousDialog = Get-DashboardDialogOwner
        if ($previousDialog -and -not [object]::ReferenceEquals($previousDialog, $form)) {
            Close-DashboardWorkflowSession -Dialog $previousDialog
        }
    }
}

function Show-SupportBundlePreview {
    $logPath = if ($loggingState -and $loggingState.Enabled) { [string]$loggingState.Path } else { "" }
    $sourceExecutablePath = [string]$env:TOOL_LAUNCHER_PATH
    $plan = Get-ToolSupportBundlePlan -ReportRoot $reportRoot -LogPath $logPath -SourceExecutablePath $sourceExecutablePath
    if (-not [bool]$plan.Ready) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "supportBundle.redactedRequired"), (Get-DashboardText "supportBundle.title"), "OK", "Information") | Out-Null
        return
    }
    $fileLines = @($plan.Files | ForEach-Object { "- $([string]$_.Target) ($([string]$_.Kind))" })
    $warningLines = if (@($plan.Warnings).Count -gt 0) { @($plan.Warnings | ForEach-Object { "- $_" }) -join "`r`n" } else { Get-DashboardText "supportBundle.noWarnings" }
    $previewMessage = Get-DashboardText "supportBundle.preview" @(($fileLines -join "`r`n"), $warningLines, [string]$plan.PrivacyNotice)
    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        $previewMessage,
        (Get-DashboardText "supportBundle.previewTitle"),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Title = Get-DashboardText "supportBundle.saveTitle"
    $saveDialog.Filter = "ZIP (*.zip)|*.zip"
    $saveDialog.DefaultExt = "zip"
    $saveDialog.AddExtension = $true
    $saveDialog.OverwritePrompt = $true
    $saveDialog.InitialDirectory = $desktop
    $saveDialog.FileName = "VietLicenSure-v5.0-Support-$((Get-Date).ToString('yyyyMMdd_HHmmss')).zip"
    if ($saveDialog.ShowDialog((Get-DashboardDialogOwner)) -ne [System.Windows.Forms.DialogResult]::OK) { $saveDialog.Dispose(); return }
    $destination = $saveDialog.FileName
    $saveDialog.Dispose()
    try {
        $form.UseWaitCursor = $true
        $result = New-ToolSupportBundle -ReportRoot $reportRoot -DestinationPath $destination -LogPath $logPath -SourceExecutablePath $sourceExecutablePath -AllowOverwrite
        $script:lastReportDirectory = Split-Path -Parent ([string]$result.Path)
        [void](Write-ToolLog -Level "AUDIT" -Event "SupportBundle.Created" -Message ([IO.Path]::GetFileName([string]$result.Path)) -Data ([ordered]@{ FileCount=[int]$result.FileCount; PrivacyModel=[string]$result.PrivacyModel; Sha256=[string]$result.Sha256 }))
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "supportBundle.completed" @($result.Path, $result.Sha256)), (Get-DashboardText "supportBundle.completedTitle"), "OK", "Information") | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "supportBundle.failed" @($_.Exception.Message)), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
    } finally { $form.UseWaitCursor = $false }
}

function Invoke-AssuranceCenterAction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Certificate", "PluginAudit", "Timeline", "InstallPlugin", "PluginFolder", "Guide", "History", "SupportBundle")]
        [string]$Choice
    )

    switch ($Choice) {
        "Certificate" { Start-AssuranceReport -Operation "CertificateAudit" -ModuleId "assurance.certificates" -DisplayName (Get-ToolText -Key "assurance.certificate" -Culture $script:dashboardCulture) }
        "PluginAudit" { Start-AssuranceReport -Operation "PluginAudit" -ModuleId "assurance.plugins" -DisplayName (Get-ToolText -Key "assurance.pluginAudit" -Culture $script:dashboardCulture) }
        "Timeline" { Start-AssuranceReport -Operation "TimelineExport" -ModuleId "assurance.timeline" -DisplayName (Get-ToolText -Key "assurance.timeline" -Culture $script:dashboardCulture) }
        "InstallPlugin" { Install-PluginFromDialog }
        "PluginFolder" {
            $pluginDirectory = Get-ToolPluginDirectory
            if (-not (Test-Path -LiteralPath $pluginDirectory -PathType Container) -and $env:TOOL_SECURE_LAUNCH -ne "1") { New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null }
            if (Test-Path -LiteralPath $pluginDirectory -PathType Container) { Start-Process -FilePath $nativeExplorerPath -ArgumentList "`"$pluginDirectory`"" }
        }
        "Guide" { Open-Guide }
        "History" { Open-VersionHistory }
        "SupportBundle" { Show-SupportBundlePreview }
    }
}

function Show-AssuranceCenter {
    $hasPreviousStep = [bool]($script:dashboardDialogStack.Count -gt 0)
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-ToolText -Key "assurance.form.title" -Culture $script:dashboardCulture
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(720, 640)
    $dialog.MinimumSize = New-Object System.Drawing.Size(620, 590)
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.AutoScroll = $true
    $dialog.Font = $fontNormal
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Tag = ""

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ToolText -Key "assurance.heading" -Culture $script:dashboardCulture -FormatArguments @($toolDisplayVersion)
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.Location = New-Object System.Drawing.Point(28, 18)
    $heading.Size = New-Object System.Drawing.Size(640, 38)
    $dialog.Controls.Add($heading)

    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = Get-ToolText -Key "assurance.description" -Culture $script:dashboardCulture
    $descriptionLabel.Location = New-Object System.Drawing.Point(30, 60)
    $descriptionLabel.Size = New-Object System.Drawing.Size(640, 42)
    $dialog.Controls.Add($descriptionLabel)

    $choices = @(
        @{Tag="Certificate"; Text=(Get-ToolText -Key "assurance.certificate" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(234,242,255)},
        @{Tag="PluginAudit"; Text=(Get-ToolText -Key "assurance.pluginAudit" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(232,247,240)},
        @{Tag="Timeline"; Text=(Get-ToolText -Key "assurance.timeline" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(255,248,230)},
        @{Tag="InstallPlugin"; Text=(Get-ToolText -Key "assurance.installPlugin" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(245,238,255)},
        @{Tag="PluginFolder"; Text=(Get-ToolText -Key "assurance.pluginFolder" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(244,246,249)},
        @{Tag="Guide"; Text=(Get-ToolText -Key "assurance.guide" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(244,246,249)},
        @{Tag="History"; Text=(Get-ToolText -Key "assurance.history" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(238,246,255)},
        @{Tag="SupportBundle"; Text=(Get-ToolText -Key "assurance.supportBundle" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(238,246,255)}
    )
    for ($index = 0; $index -lt $choices.Count; $index++) {
        $choice = $choices[$index]
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $choice.Text
        $button.Tag = $choice.Tag
        $button.Font = $fontBold
        $button.TextAlign = "MiddleLeft"
        $button.Location = New-Object System.Drawing.Point(42, (106 + ($index * 47)))
        $button.Size = New-Object System.Drawing.Size(620, 40)
        $button.Anchor = "Top,Left,Right"
        $button.BackColor = $choice.Color
        $button.Add_Click({
            param($sender,$eventArgs)
            $selectedChoice = [string]$sender.Tag
            if ($selectedChoice -in @("Certificate", "PluginAudit", "Timeline")) {
                $dialog.Tag = $selectedChoice
                $dialog.Close()
                return
            }
            Invoke-AssuranceCenterAction -Choice $selectedChoice
        })
        $dialog.Controls.Add($button)
    }
    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-ToolText -Key "common.close" -Culture $script:dashboardCulture
    $close.Location = New-Object System.Drawing.Point(542, 512)
    $close.Size = New-Object System.Drawing.Size(120, 34)
    $close.Anchor = "Bottom,Right"
    $close.Add_Click({ $dialog.Tag = ""; Close-DashboardWorkflowSession -Dialog $dialog })
    $dialog.Controls.Add($close)
    if ($hasPreviousStep) {
        $back = New-Object System.Windows.Forms.Button
        $back.Text = Get-ToolText -Key "common.back" -Culture $script:dashboardCulture
        $back.Location = New-Object System.Drawing.Point(414, 512)
        $back.Size = New-Object System.Drawing.Size(120, 34)
        $back.Anchor = "Bottom,Right"
        $back.Add_Click({ $dialog.Tag = ""; $dialog.Close() })
        $dialog.CancelButton = $back
        $dialog.Controls.Add($back)
    } else {
        $dialog.CancelButton = $close
    }
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    $dialogPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
    $heading.ForeColor = $dialogPalette.Primary
    $descriptionLabel.ForeColor = $dialogPalette.Text
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    if (-not [string]::IsNullOrWhiteSpace($choice)) { Invoke-AssuranceCenterAction -Choice $choice }
}

function Get-DashboardMenuIconKind([int]$Number) {
    switch ($Number) {
        1 { return "Search" }
        2 { return "Hardware" }
        3 { return "Windows" }
        4 { return "Office" }
        5 { return "Software" }
        6 { return "Repair" }
        7 { return "Key" }
        8 { return "License" }
        9 { return "DeepScan" }
        10 { return "Report" }
        11 { return "Windows" }
        12 { return "Office" }
        13 { return "Software" }
        14 { return "Repair" }
        default { return "Search" }
    }
}

function Set-DashboardCompositeButtonAccessibility {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$Button,
        [Parameter(Mandatory = $true)][string]$AccessibleText
    )

    # The PowerShell-hosted WinForms UI Automation bridge derives the name of
    # a Button from Text. AccessibleName alone is not surfaced reliably when
    # Text is empty, leaving keyboard tab stops unnamed for screen readers.
    # Keep semantic Text on the real Button and mask only the base-rendered
    # text area; the visible child labels are painted afterwards.
    $Button.Text = $AccessibleText
    $Button.AccessibleName = $AccessibleText
    $Button.AccessibleRole = [System.Windows.Forms.AccessibleRole]::PushButton
    $Button.UseMnemonic = $false
    $Button.Add_Paint({
        param($sender, $eventArgs)
        $maskLeft = 52
        $maskTop = 2
        $maskWidth = [Math]::Max(0, $sender.ClientSize.Width - $maskLeft - 2)
        $maskHeight = [Math]::Max(0, $sender.ClientSize.Height - 4)
        if ($maskWidth -gt 0 -and $maskHeight -gt 0) {
            $brush = New-Object System.Drawing.SolidBrush($sender.BackColor)
            try {
                $eventArgs.Graphics.FillRectangle($brush, $maskLeft, $maskTop, $maskWidth, $maskHeight)
            } finally {
                $brush.Dispose()
            }
        }
    })
}

function Add-MenuButton([int]$number, [string]$titleKey, [string]$descriptionKey, [int]$index, [scriptblock]$action, [bool]$warning) {
    $button = New-Object System.Windows.Forms.Button
    $metadata = [pscustomobject][ordered]@{
        Kind = "QuickAction"
        Number = $number
        TitleKey = $titleKey
        DescriptionKey = $descriptionKey
        Tone = if ($number -eq 8) { "Enterprise" } elseif ($warning) { "Warning" } else { "Normal" }
        IconKind = Get-DashboardMenuIconKind -Number $number
        TitleLabel = $null
        DescriptionLabel = $null
    }
    $buttonText = Get-ToolText -Key $titleKey -Culture $script:dashboardCulture
    Set-DashboardCompositeButtonAccessibility -Button $button -AccessibleText $buttonText
    $button.Font = $fontTile
    $button.ImageAlign = "MiddleLeft"
    $button.Padding = New-Object System.Windows.Forms.Padding(12, 0, 10, 0)
    $row = [Math]::Floor($index / 2)
    $column = $index % 2
    $button.Location = New-Object System.Drawing.Point((14 + ($column * 420)), (34 + ($row * 58)))
    $button.Size = New-Object System.Drawing.Size(410, 50)
    $menuIconImage = New-DashboardTileIconBitmap -Kind ([string]$metadata.IconKind) -IconSize 32 -RightGap 12
    [void]$dashboardIconImages.Add($menuIconImage)
    $button.Image = $menuIconImage
    $initialTilePalette = Get-DashboardTilePalette -Tone ([string]$metadata.Tone) -Mode $script:dashboardTheme
    $button.BackColor = $initialTilePalette.BackColor
    $button.ForeColor = $initialTilePalette.ForeColor
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Tag = $metadata
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = Get-ToolText -Key $titleKey -Culture $script:dashboardCulture
    $titleLabel.Font = $fontBold
    $titleLabel.BackColor = [System.Drawing.Color]::Transparent
    $titleLabel.ForeColor = $initialTilePalette.TitleColor
    $titleLabel.AutoEllipsis = $true
    $titleLabel.UseCompatibleTextRendering = $false
    $titleLabel.UseMnemonic = $false
    $titleLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $titleLabel.Location = New-Object System.Drawing.Point(60, 4)
    $titleLabel.Size = New-Object System.Drawing.Size(334, 20)
    $titleLabel.Add_Click({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.PerformClick() } })
    $titleLabel.Add_MouseEnter({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.BackColor = (Get-DashboardTilePalette -Tone ([string]$sender.Parent.Tag.Tone) -Mode $script:dashboardTheme -Hover).BackColor } })
    $titleLabel.Add_MouseLeave({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.BackColor = (Get-DashboardTilePalette -Tone ([string]$sender.Parent.Tag.Tone) -Mode $script:dashboardTheme).BackColor } })
    $button.Controls.Add($titleLabel)
    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture
    $descriptionLabel.Font = $fontSupportSmall
    $descriptionLabel.BackColor = [System.Drawing.Color]::Transparent
    $descriptionLabel.ForeColor = $initialTilePalette.DescriptionColor
    $descriptionLabel.AutoEllipsis = $false
    $descriptionLabel.UseCompatibleTextRendering = $false
    $descriptionLabel.UseMnemonic = $false
    $descriptionLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $descriptionLabel.Location = New-Object System.Drawing.Point(60, 24)
    $descriptionLabel.Size = New-Object System.Drawing.Size(334, 19)
    $descriptionLabel.Add_Click({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.PerformClick() } })
    $descriptionLabel.Add_MouseEnter({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.BackColor = (Get-DashboardTilePalette -Tone ([string]$sender.Parent.Tag.Tone) -Mode $script:dashboardTheme -Hover).BackColor } })
    $descriptionLabel.Add_MouseLeave({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.BackColor = (Get-DashboardTilePalette -Tone ([string]$sender.Parent.Tag.Tone) -Mode $script:dashboardTheme).BackColor } })
    $button.Controls.Add($descriptionLabel)
    $metadata.TitleLabel = $titleLabel
    $metadata.DescriptionLabel = $descriptionLabel
    $button.AccessibleName = $buttonText
    $button.AccessibleDescription = Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture
    $rootAction = $action
    $button.Add_Click({
        Invoke-DashboardRootAction -Action $rootAction
    }.GetNewClosure())
    $button.Add_MouseEnter({
        param($sender, $eventArgs)
        $tone = if ($sender.Tag -and $sender.Tag.PSObject.Properties["Tone"]) { [string]$sender.Tag.Tone } else { "Normal" }
        $hoverPalette = Get-DashboardTilePalette -Tone $tone -Mode $script:dashboardTheme -Hover
        $sender.BackColor = $hoverPalette.BackColor
        $sender.ForeColor = $hoverPalette.ForeColor
    })
    $button.Add_MouseLeave({
        param($sender, $eventArgs)
        $tone = if ($sender.Tag -and $sender.Tag.PSObject.Properties["Tone"]) { [string]$sender.Tag.Tone } else { "Normal" }
        $normalPalette = Get-DashboardTilePalette -Tone $tone -Mode $script:dashboardTheme
        $sender.BackColor = $normalPalette.BackColor
        $sender.ForeColor = $normalPalette.ForeColor
    })
    $toolTip.SetToolTip($button, (Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture))
    $menuButtonMetadata[[string]$number] = $metadata
    [void]$buttons.Add($button)
    $buttonPanel.Controls.Add($button)
}

function Add-ReportMenuButton([string]$actionId, [string]$titleKey, [string]$descriptionKey, [int]$index, [string]$iconKind) {
    $button = New-Object System.Windows.Forms.Button
    $metadata = [pscustomobject][ordered]@{
        Kind = "ReportAction"
        Number = 0
        ActionId = $actionId
        TitleKey = $titleKey
        DescriptionKey = $descriptionKey
        Tone = "Normal"
        IconKind = $iconKind
        TitleLabel = $null
        DescriptionLabel = $null
    }
    $buttonText = Get-ToolText -Key $titleKey -Culture $script:dashboardCulture
    Set-DashboardCompositeButtonAccessibility -Button $button -AccessibleText $buttonText
    $button.Font = $fontTile
    $button.ImageAlign = "MiddleLeft"
    $button.Padding = New-Object System.Windows.Forms.Padding(12, 0, 10, 0)
    $button.UseMnemonic = $false
    $row = [Math]::Floor($index / 2)
    $column = $index % 2
    $button.Location = New-Object System.Drawing.Point((14 + ($column * 420)), (34 + ($row * 58)))
    $button.Size = New-Object System.Drawing.Size(410, 50)
    $menuIconImage = New-DashboardTileIconBitmap -Kind $iconKind -IconSize 32 -RightGap 12
    [void]$dashboardIconImages.Add($menuIconImage)
    $button.Image = $menuIconImage
    $initialTilePalette = Get-DashboardTilePalette -Tone "Normal" -Mode $script:dashboardTheme
    $button.BackColor = $initialTilePalette.BackColor
    $button.ForeColor = $initialTilePalette.ForeColor
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Tag = $metadata
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = Get-ToolText -Key $titleKey -Culture $script:dashboardCulture
    $titleLabel.Font = $fontBold
    $titleLabel.BackColor = [System.Drawing.Color]::Transparent
    $titleLabel.ForeColor = $initialTilePalette.TitleColor
    $titleLabel.AutoEllipsis = $true
    $titleLabel.UseCompatibleTextRendering = $false
    $titleLabel.UseMnemonic = $false
    $titleLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $titleLabel.Location = New-Object System.Drawing.Point(60, 4)
    $titleLabel.Size = New-Object System.Drawing.Size(334, 20)
    $titleLabel.Add_Click({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.PerformClick() } })
    $button.Controls.Add($titleLabel)
    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture
    $descriptionLabel.Font = $fontSupportSmall
    $descriptionLabel.BackColor = [System.Drawing.Color]::Transparent
    $descriptionLabel.ForeColor = $initialTilePalette.DescriptionColor
    $descriptionLabel.AutoEllipsis = $true
    $descriptionLabel.UseCompatibleTextRendering = $false
    $descriptionLabel.UseMnemonic = $false
    $descriptionLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $descriptionLabel.Location = New-Object System.Drawing.Point(60, 24)
    $descriptionLabel.Size = New-Object System.Drawing.Size(334, 19)
    $descriptionLabel.Add_Click({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.PerformClick() } })
    $button.Controls.Add($descriptionLabel)
    foreach ($label in @($titleLabel, $descriptionLabel)) {
        $label.Add_MouseEnter({
            param($sender, $eventArgs)
            if ($sender.Parent) {
                $palette = Get-DashboardTilePalette -Tone "Normal" -Mode $script:dashboardTheme -Hover
                $sender.Parent.BackColor = $palette.BackColor
                $sender.Parent.Tag.TitleLabel.ForeColor = $palette.TitleColor
                $sender.Parent.Tag.DescriptionLabel.ForeColor = $palette.DescriptionColor
            }
        })
        $label.Add_MouseLeave({
            param($sender, $eventArgs)
            if ($sender.Parent) {
                $palette = Get-DashboardTilePalette -Tone "Normal" -Mode $script:dashboardTheme
                $sender.Parent.BackColor = $palette.BackColor
                $sender.Parent.Tag.TitleLabel.ForeColor = $palette.TitleColor
                $sender.Parent.Tag.DescriptionLabel.ForeColor = $palette.DescriptionColor
            }
        })
    }
    $metadata.TitleLabel = $titleLabel
    $metadata.DescriptionLabel = $descriptionLabel
    $button.AccessibleName = $buttonText
    $button.AccessibleDescription = Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture
    $button.Visible = $false
    $button.Add_Click({
        param($sender, $eventArgs)
        $selectedActionId = [string]$sender.Tag.ActionId
        Invoke-DashboardRootAction -Action ({
            Invoke-AssuranceCenterAction -Choice $selectedActionId
        }.GetNewClosure())
    })
    $button.Add_MouseEnter({
        param($sender, $eventArgs)
        $hoverPalette = Get-DashboardTilePalette -Tone "Normal" -Mode $script:dashboardTheme -Hover
        $sender.BackColor = $hoverPalette.BackColor
        $sender.ForeColor = $hoverPalette.ForeColor
        if ($sender.Tag.TitleLabel) { $sender.Tag.TitleLabel.ForeColor = $hoverPalette.TitleColor }
        if ($sender.Tag.DescriptionLabel) { $sender.Tag.DescriptionLabel.ForeColor = $hoverPalette.DescriptionColor }
    })
    $button.Add_MouseLeave({
        param($sender, $eventArgs)
        $normalPalette = Get-DashboardTilePalette -Tone "Normal" -Mode $script:dashboardTheme
        $sender.BackColor = $normalPalette.BackColor
        $sender.ForeColor = $normalPalette.ForeColor
        if ($sender.Tag.TitleLabel) { $sender.Tag.TitleLabel.ForeColor = $normalPalette.TitleColor }
        if ($sender.Tag.DescriptionLabel) { $sender.Tag.DescriptionLabel.ForeColor = $normalPalette.DescriptionColor }
    })
    $toolTip.SetToolTip($button, (Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture))
    [void]$buttons.Add($button)
    $buttonPanel.Controls.Add($button)
}

function Initialize-DashboardMenus {
    if ($script:dashboardMenusInitialized) { return }
    $buttonPanel.SuspendLayout()
    try {
        Write-DashboardStartupTrace "MenuBuild.Started"
        Add-MenuButton 1 "menu.1.title" "menu.1.description" 0 { Start-Report "All" (Get-ToolText -Key "menu.1.title" -Culture $script:dashboardCulture) } $false
        Add-MenuButton 2 "menu.2.title" "menu.2.description" 1 { Start-Report "Hardware" (Get-ToolText -Key "menu.2.title" -Culture $script:dashboardCulture) } $false
        Add-MenuButton 3 "menu.3.title" "menu.3.description" 2 { Start-Report "Windows" (Get-ToolText -Key "menu.3.title" -Culture $script:dashboardCulture) } $false
        Add-MenuButton 4 "menu.4.title" "menu.4.description" 3 { Start-Report "Office" (Get-ToolText -Key "menu.4.title" -Culture $script:dashboardCulture) } $false
        Add-MenuButton 5 "menu.5.title" "menu.5.description" 4 { Start-ThirdPartyManualReview } $false
        Add-MenuButton 6 "menu.6.title" "menu.6.description" 5 { Show-CleanupMenu } $true
        Add-MenuButton 11 "menu.11.title" "menu.11.description" 10 { [void](Show-CleanupFunctionScreen -Mode "Cleanup" -FixedScope "Windows") } $true
        Add-MenuButton 12 "menu.12.title" "menu.12.description" 11 { [void](Show-CleanupFunctionScreen -Mode "Cleanup" -FixedScope "Office") } $true
        Add-MenuButton 13 "menu.13.title" "menu.13.description" 12 { [void](Show-CleanupFunctionScreen -Mode "Cleanup" -FixedScope "ThirdParty") } $true
        Add-MenuButton 14 "menu.14.title" "menu.14.description" 13 { Show-BackupRestoreCenter } $false
        Add-MenuButton 7 "menu.7.title" "menu.7.description" 6 { Start-OemInspect } $true
        Add-MenuButton 8 "menu.8.title" "menu.8.description" 7 { Open-LicenseManager } $false
        Add-MenuButton 9 "menu.9.title" "menu.9.description" 8 { Show-AdvancedScanMenu } $false
        Add-MenuButton 10 "menu.10.title" "menu.10.description" 9 { Show-AssuranceCenter } $false
        Write-DashboardStartupTrace "MenuQuick.Ready"

        Add-ReportMenuButton "Certificate" "assurance.certificate" "dashboard.report.certificate.description" 0 "Shield"
        Add-ReportMenuButton "PluginAudit" "assurance.pluginAudit" "dashboard.report.pluginAudit.description" 1 "Software"
        Add-ReportMenuButton "Timeline" "assurance.timeline" "dashboard.report.timeline.description" 2 "DeepScan"
        Add-ReportMenuButton "InstallPlugin" "assurance.installPlugin" "dashboard.report.installPlugin.description" 3 "License"
        Add-ReportMenuButton "PluginFolder" "assurance.pluginFolder" "dashboard.report.pluginFolder.description" 4 "Report"
        Add-ReportMenuButton "Guide" "assurance.guide" "dashboard.report.guide.description" 5 "Report"
        Add-ReportMenuButton "History" "assurance.history" "dashboard.report.history.description" 6 "License"
        Add-ReportMenuButton "SupportBundle" "assurance.supportBundle" "dashboard.report.supportBundle.description" 7 "Report"
        Write-DashboardStartupTrace "MenuReports.Ready"
        $script:dashboardMenusInitialized = $true
    } finally {
        $buttonPanel.ResumeLayout($false)
    }
    Set-DashboardSection -Section $script:dashboardSection
    Write-DashboardStartupTrace "Menus.Ready"
}
