# VietLicenSure v5.0 - dot-sourced function library
# Extracted mechanically from Giao-Dien.ps1; contains function definitions only.
# Keep this file beside its compatible entrypoint.

function Enable-DashboardOnlineForCurrentCatalogSession {
    param([switch]$ConsentAlreadyGranted)

    if (-not $ConsentAlreadyGranted) {
        $consent = [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "software.online.consentMessage"),
            (Get-DashboardText "software.online.consentTitle"),
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($consent -ne [System.Windows.Forms.DialogResult]::Yes) {
            $status.Text = Get-DashboardText "software.online.cancelledStatus"
            $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
            return $false
        }
    }

    # This is intentionally local to the current process.  The Offline policy
    # writes NextLaunchMode=Offline, so a new VietLicenSure launch will fail closed even
    # though the catalog button can enable Online for this one approved run.
    if ($script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne '0' -or
        -not (Test-ToolNetworkActionAllowed -Scope Internet)) {
        $script:offlineMode = $false
        [void](Set-ToolOfflineModePreference -OfflineMode $false)
        $env:TOOL_OFFLINE_MODE = '0'
        Update-DashboardOfflineUi
        Set-DashboardTheme -Mode $script:dashboardTheme
        Refresh-DashboardLocalizedActivity
        [void](Write-ToolLog -Level 'AUDIT' -Event 'OnlineMode.CatalogSessionEnabled' -Message (Get-DashboardText 'offline.networkAllowedLog') -Data ([ordered]@{
            Source='SoftwareCatalog'; SessionOnly=$true; UploadedInventory=$false; SentLicenseKeys=$false
        }))
    }
    return [bool](Test-ToolNetworkActionAllowed -Scope Internet)
}

function Start-SoftwareCatalogOnlineUpdate {
    param(
        [ValidateSet("Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty", "All")]
        [string]$ScanScope = "ThirdParty",
        [switch]$ResumeCleanup,
        [switch]$ConsentAlreadyGranted,
        [switch]$BackgroundSync
    )

    $script:softwareCatalogBackgroundSync = $false
    $script:softwareCatalogResumeCleanup = $false
    $script:softwareCatalogResumeCleanupScope = "ThirdParty"
    if (-not (Enable-DashboardOnlineForCurrentCatalogSession -ConsentAlreadyGranted:$ConsentAlreadyGranted)) {
        return
    }
    $script:softwareCatalogBackgroundSync = [bool]$BackgroundSync
    $script:softwareCatalogResumeCleanup = [bool]$ResumeCleanup
    $script:softwareCatalogResumeCleanupScope = $ScanScope
    try {
        Start-ProgressDisplay (Get-DashboardText "software.online.action") (Get-DashboardText "software.online.connecting") $false
        Write-ProgressLog (Get-DashboardText "software.online.privacyLog")
        $script:softwareCatalogUpdateResultFile = New-SecureRuntimePath "tool-software-catalog-update-"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$softwareCatalogUpdateScript`" -ResultFile `"$script:softwareCatalogUpdateResultFile`" -ConsentGranted -Culture `"$script:dashboardCulture`""
        [void](Start-ToolModuleProcess -ModuleId "software.catalog.update" -Arguments $arguments -Action (Get-DashboardText "software.online.action") -Hidden)
        $status.Text = Get-DashboardText "software.online.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        $wasBackgroundSync = [bool]$script:softwareCatalogBackgroundSync
        $script:softwareCatalogBackgroundSync = $false
        $script:softwareCatalogResumeCleanup = $false
        $script:softwareCatalogResumeCleanupScope = "ThirdParty"
        if ($script:softwareCatalogUpdateResultFile -and (Test-Path -LiteralPath $script:softwareCatalogUpdateResultFile -PathType Leaf)) {
            Remove-Item -LiteralPath $script:softwareCatalogUpdateResultFile -Force -ErrorAction SilentlyContinue
        }
        $script:softwareCatalogUpdateResultFile = ""
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-DashboardText "software.online.startFailed" @($_.Exception.Message))
        if ($wasBackgroundSync) { Invoke-PendingOnlineSessionWork }
    }
}

function Get-SoftwareCatalogOnlineFailureDetail {
    param($Result)

    $errorText = if ($Result -and $Result.PSObject.Properties['Error'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
        [string]$Result.Error
    } else { Get-DashboardText 'common.unknown' }
    $code = if ($Result -and $Result.PSObject.Properties['ErrorCode']) { [string]$Result.ErrorCode } else { '' }
    if ([string]::IsNullOrWhiteSpace($code) -and (Get-Command Get-ToolSoftwareCatalogFailureCode -ErrorAction SilentlyContinue)) {
        $code = Get-ToolSoftwareCatalogFailureCode -Message $errorText
    }
    $causeKey = switch ($code) {
        'OfflinePolicy' { 'software.online.failure.offlinePolicy' }
        'Allowlist' { 'software.online.failure.allowlist' }
        'Signature' { 'software.online.failure.signature' }
        'Schema' { 'software.online.failure.schema' }
        'Version' { 'software.online.failure.version' }
        'Proxy' { 'software.online.failure.proxy' }
        'Connectivity' { 'software.online.failure.connectivity' }
        default { 'software.online.failure.unknown' }
    }
    return Get-DashboardText 'software.online.failure.detail' @((Get-DashboardText $causeKey), $errorText)
}

function Show-SoftwareCatalogFailureDialog {
    param([Parameter(Mandatory = $true)][string]$Detail)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.Text = Get-DashboardText 'software.online.failedTitle'
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ClientSize = New-Object System.Drawing.Size(650, 230)
    $dialog.Font = $fontNormal
    $dialog.Tag = 'Close'

    $message = New-Object System.Windows.Forms.Label
    $message.Text = $Detail
    $message.AutoEllipsis = $true
    $message.Location = New-Object System.Drawing.Point(20, 18)
    $message.Size = New-Object System.Drawing.Size(610, 142)
    $message.Anchor = 'Top,Left,Right'
    $dialog.Controls.Add($message)

    $retry = New-Object System.Windows.Forms.Button
    $retry.Text = Get-DashboardText 'software.online.retry'
    $retry.Size = New-Object System.Drawing.Size(160, 38)
    $retry.Location = New-Object System.Drawing.Point(190, 174)
    $retry.Add_Click({ $dialog.Tag='Retry'; $dialog.Close() })
    $dialog.Controls.Add($retry)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-DashboardText 'app.close'
    $close.Size = New-Object System.Drawing.Size(120, 38)
    $close.Location = New-Object System.Drawing.Point(370, 174)
    $close.Add_Click({ $dialog.Close() })
    $dialog.CancelButton = $close
    $dialog.AcceptButton = $retry
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Complete-SoftwareCatalogOnlineUpdate {
    Set-ButtonsEnabled $true
    $wasBackgroundSync = [bool]$script:softwareCatalogBackgroundSync
    $resumeCleanup = [bool]$script:softwareCatalogResumeCleanup
    $resumeScope = if ([string]::IsNullOrWhiteSpace([string]$script:softwareCatalogResumeCleanupScope)) { "ThirdParty" } else { [string]$script:softwareCatalogResumeCleanupScope }
    $script:softwareCatalogBackgroundSync = $false
    $script:softwareCatalogResumeCleanup = $false
    $script:softwareCatalogResumeCleanupScope = "ThirdParty"
    $result = $null
    try {
        if (-not $script:softwareCatalogUpdateResultFile -or -not (Test-Path -LiteralPath $script:softwareCatalogUpdateResultFile -PathType Leaf)) {
            throw (Get-DashboardText "software.online.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:softwareCatalogUpdateResultFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $result = [pscustomobject]@{ Success=$false; Error=[string]$_.Exception.Message; ErrorCode='Unknown'; CatalogVersion=''; ProductRuleCount=0; CachePath='' }
    } finally {
        if ($script:softwareCatalogUpdateResultFile -and (Test-Path -LiteralPath $script:softwareCatalogUpdateResultFile -PathType Leaf)) {
            Remove-Item -LiteralPath $script:softwareCatalogUpdateResultFile -Force -ErrorAction SilentlyContinue
        }
        $script:softwareCatalogUpdateResultFile = ""
    }

    if ([bool]$result.Success) {
        try {
            $updatedSoftwareCatalog = Get-ToolSoftwareLicenseCatalog -PreferCache
            if ($updatedSoftwareCatalog) { $script:softwareCatalogFreshnessState = Get-ToolSoftwareCatalogFreshness -Catalog $updatedSoftwareCatalog }
            if ($script:lastIntegrityResult) { Update-DashboardStatus -IntegrityResult $script:lastIntegrityResult }
        } catch {}
        $resultCode = if ($result.PSObject.Properties['ResultCode']) { [string]$result.ResultCode } else { 'Updated' }
        $downloadedVersion = if ($result.PSObject.Properties['DownloadedCatalogVersion']) { [string]$result.DownloadedCatalogVersion } else { [string]$result.CatalogVersion }
        if ($resultCode -eq 'LocalNewer') {
            $status.Text = Get-DashboardText 'software.online.localNewerStatus' @($result.CatalogVersion, $downloadedVersion)
            $successLog = Get-DashboardText 'software.online.localNewerLog' @($result.CatalogVersion, $downloadedVersion)
            $successMessage = Get-DashboardText 'software.online.localNewerMessage' @($result.CatalogVersion, $downloadedVersion, $result.ProductRuleCount)
            $successTitle = Get-DashboardText 'software.online.readyTitle'
        } elseif ($resultCode -eq 'AlreadyCurrent') {
            $status.Text = Get-DashboardText 'software.online.alreadyCurrentStatus' @($result.CatalogVersion, $result.ProductRuleCount)
            $successLog = Get-DashboardText 'software.online.alreadyCurrentLog' @($result.CatalogVersion)
            $successMessage = Get-DashboardText 'software.online.alreadyCurrentMessage' @($result.CatalogVersion, $result.ProductRuleCount)
            $successTitle = Get-DashboardText 'software.online.readyTitle'
        } else {
            $status.Text = Get-DashboardText "software.online.successStatus" @($result.CatalogVersion, $result.ProductRuleCount)
            $successLog = Get-DashboardText "software.online.successLog" @($result.CatalogVersion, $result.ProductRuleCount, $result.CachePath)
            $successMessage = Get-DashboardText "software.online.successMessage" @($result.CatalogVersion, $result.ProductRuleCount)
            $successTitle = Get-DashboardText "software.online.successTitle"
        }
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
        Write-ProgressLog $successLog
        if (-not $wasBackgroundSync) {
            [System.Windows.Forms.MessageBox]::Show(
                $successMessage, $successTitle, "OK", "Information") | Out-Null
        }
        if ($resumeCleanup) {
            [void](Write-ToolLog -Level "AUDIT" -Event "OnlineMode.PendingCleanupResumed" -Message "Signed catalog updated; resuming the user-requested remediation scan." -Data ([ordered]@{
                Scope=$resumeScope; CatalogUpdated=$true; Rescan=$true; PreviewRequired=$true; SeparateConfirmationRequired=$true; AutoRemediation=$false; Report=$false
            }))
            Start-Cleanup -ScanScope $resumeScope
        }
        return
    }

    $failureDetail = Get-SoftwareCatalogOnlineFailureDetail -Result $result
    $status.Text = Get-DashboardText "software.online.failedStatus"
    $status.ForeColor = [System.Drawing.Color]::DarkOrange
    Write-ProgressLog (Get-DashboardText "software.online.failedLog" @($failureDetail))
    if ($wasBackgroundSync) {
        Invoke-PendingOnlineSessionWork
        return
    }
    $fallback = Show-SoftwareCatalogFailureDialog -Detail (Get-DashboardText "software.online.fallbackPrompt" @($failureDetail))
    if ($fallback -eq 'Retry') {
        Start-SoftwareCatalogOnlineUpdate -ScanScope $resumeScope -ResumeCleanup:$resumeCleanup -ConsentAlreadyGranted
    }
}

function Request-OnlineSessionRefresh {
    if ($script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0" -or
        -not (Test-ToolNetworkActionAllowed -Scope Internet)) {
        return
    }

    # A fresh launch remains Offline.  This queue is populated only after the
    # user explicitly enables Online for the current session.  This action is
    # catalog-only: it never starts a scan, report, privacy prompt, application
    # update check, or any other follow-up task.
    $script:softwareCatalogRefreshPending = $true
    [void](Write-ToolLog -Level "AUDIT" -Event "OnlineMode.RefreshQueued" -Message (Get-DashboardText "online.refresh.queued") -Data ([ordered]@{
        Catalog=$true; ApplicationVersion=$false; Scan=$false; Report=$false; SessionOnly=$true; SilentInstall=$false
    }))
    Invoke-PendingOnlineSessionWork
}

function Invoke-PendingOnlineSessionWork {
    if ($script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0" -or
        -not (Test-ToolNetworkActionAllowed -Scope Internet)) {
        $script:softwareCatalogRefreshPending = $false
        return
    }
    if (($script:activeProcess -and -not $script:activeProcess.HasExited) -or
        ($script:applicationUpdateProcess -and -not $script:applicationUpdateProcess.HasExited)) {
        return
    }
    if ($script:softwareCatalogRefreshPending) {
        $script:softwareCatalogRefreshPending = $false
        Start-SoftwareCatalogOnlineUpdate -ConsentAlreadyGranted -BackgroundSync
        return
    }
}

function Get-ApplicationUpdateFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace("-", "").ToUpperInvariant() }
        finally { $algorithm.Dispose() }
    } finally {
        $stream.Dispose()
    }
}

function Test-ApplicationSelfUpdateAllowed {
    # The EXE launcher creates this value from a compile-time marker.  Missing
    # or malformed values fail closed so extracted/source/dev payloads cannot
    # hand off to the public self-updater.
    return ([string]$env:TOOL_SECURE_LAUNCH -eq '1' -and [string]$env:TOOL_SELF_UPDATE_ALLOWED -eq '1')
}

function Remove-ApplicationUpdateResultFile {
    if ($script:applicationUpdateResultFile -and (Test-Path -LiteralPath $script:applicationUpdateResultFile -PathType Leaf)) {
        Remove-Item -LiteralPath $script:applicationUpdateResultFile -Force -ErrorAction SilentlyContinue
    }
    $script:applicationUpdateResultFile = ""
}

function Reset-ApplicationUpdateForOffline {
    $script:applicationUpdateCheckPending = $false
    $script:applicationUpdatePromptPending = $false
    $script:applicationUpdateReminderPending = $false
    $script:applicationUpdateReminderDueUtc = [DateTime]::MinValue
    $script:applicationUpdateTaskObservedAfterDeferral = $false
    $script:availableApplicationUpdate = $null
    $script:applicationUpdateCancelledForOffline = $false
    if ($script:applicationUpdateProcess) {
        $script:applicationUpdateCancelledForOffline = $true
        if (-not $script:applicationUpdateProcess.HasExited) {
            try { $script:applicationUpdateProcess.Kill() } catch {}
        }
    }
    Remove-ApplicationUpdateResultFile
    [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.DisabledOffline" -Message (Get-DashboardText "offline.enabledLog"))
}

function Request-ApplicationUpdateCheck {
    if (-not (Test-ApplicationSelfUpdateAllowed) -or $script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0" -or
        $script:applicationUpdateDismissedForSession -or $script:applicationUpdateApplyStarted) {
        return
    }
    if ($script:applicationUpdateProcess -and -not $script:applicationUpdateProcess.HasExited) { return }
    $script:applicationUpdateCheckPending = $true
    Invoke-PendingApplicationUpdateWork
}

function Start-ApplicationUpdateCheck {
    if (-not (Test-ApplicationSelfUpdateAllowed) -or $script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0" -or
        $script:applicationUpdateDismissedForSession -or $script:applicationUpdateApplyStarted) {
        $script:applicationUpdateCheckPending = $false
        $script:applicationUpdatePromptPending = $false
        $script:availableApplicationUpdate = $null
        return
    }
    try {
        $freshIntegrity = Test-ToolIntegrity
        if (-not $freshIntegrity.Valid) { throw $freshIntegrity.Message }
        $descriptor = Get-ReadyToolModule -moduleId "application.update.check" -elevatedLaunch $false
        $invocation = New-ToolModuleInvocation -ModuleId $descriptor.ModuleId
        $script:applicationUpdateResultFile = New-SecureRuntimePath "tool-application-update-check-"
        $currentLauncherSha256 = ""
        $launcherPath = [string]$env:TOOL_LAUNCHER_PATH
        if ([string]$env:TOOL_SECURE_LAUNCH -eq "1") {
            if ([string]::IsNullOrWhiteSpace($launcherPath) -or -not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
                throw (Get-DashboardText "update.secureLauncherRequired")
            }
            $currentLauncherSha256 = Get-ApplicationUpdateFileSha256 $launcherPath
        }
        $currentHashArgument = if ($currentLauncherSha256) { " -ExpectedCurrentSha256 `"$currentLauncherSha256`"" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$applicationUpdateScript`" -Mode Check -ConsentGranted -Culture `"$script:dashboardCulture`" -CurrentVersion `"$releaseVersion`" -ResultFile `"$script:applicationUpdateResultFile`" -ManifestUrl `"$applicationUpdateManifestUrl`"$currentHashArgument"
        $previousModuleId = [string]$env:TOOL_MODULE_ID
        $previousInvocationId = [string]$env:TOOL_MODULE_INVOCATION_ID
        try {
            $env:TOOL_MODULE_ID = $descriptor.ModuleId
            $env:TOOL_MODULE_INVOCATION_ID = $invocation.InvocationId
            $updateCheckStartParameters = @{
                FilePath = $toolPowerShellPath
                ArgumentList = $arguments
                WindowStyle = "Hidden"
                PassThru = $true
            }
            $process = Start-Process @updateCheckStartParameters
            if (-not $process) { throw (Get-DashboardText "module.processMissing") }
        } finally {
            $env:TOOL_MODULE_ID = $previousModuleId
            $env:TOOL_MODULE_INVOCATION_ID = $previousInvocationId
        }
        $script:applicationUpdateProcess = $process
        $script:applicationUpdateInvocation = $invocation
        $script:applicationUpdateCheckPending = $false
        $script:applicationUpdateCancelledForOffline = $false
        if (-not $script:activeProcess) {
            $status.Text = Get-DashboardText "update.check.running"
            $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        }
        [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.CheckStarted" -Message (Get-DashboardText "update.check.checking") -Data ([ordered]@{
            CurrentVersion=$releaseVersion; ManifestHost="raw.githubusercontent.com"; OnlineConsent=$true
        }))
    } catch {
        $script:applicationUpdateCheckPending = $false
        $script:applicationUpdateProcess = $null
        $script:applicationUpdateInvocation = $null
        Remove-ApplicationUpdateResultFile
        $message = Get-DashboardText "update.check.startFailed" @($_.Exception.Message)
        if (-not $script:activeProcess) {
            $status.Text = $message
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        [void](Write-ToolLog -Level "WARN" -Event "ApplicationUpdate.CheckStartFailed" -Message $message)
    }
}

function Complete-ApplicationUpdateCheck {
    if (-not $script:applicationUpdateProcess -or -not $script:applicationUpdateProcess.HasExited) { return }
    $exitCode = [int]$script:applicationUpdateProcess.ExitCode
    $invocation = $script:applicationUpdateInvocation
    $script:applicationUpdateProcess = $null
    $script:applicationUpdateInvocation = $null
    if ($invocation) {
        try {
            $moduleResult = Complete-ToolModuleInvocation -Invocation $invocation -ExitCode $exitCode -Summary (Get-DashboardText "update.check.action")
            $moduleValidation = Test-ToolModuleResult -Result $moduleResult
            if (-not $moduleValidation.Valid) {
                [void](Write-ToolLog -Level "ERROR" -Event "ApplicationUpdate.ModuleResultInvalid" -Message ($moduleValidation.Errors -join "; "))
            }
        } catch {
            [void](Write-ToolLog -Level "WARN" -Event "ApplicationUpdate.ModuleCompletionFailed" -Message $_.Exception.Message)
        }
    }

    $result = $null
    try {
        if (-not $script:applicationUpdateResultFile -or -not (Test-Path -LiteralPath $script:applicationUpdateResultFile -PathType Leaf)) {
            throw (Get-DashboardText "update.check.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:applicationUpdateResultFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $result = [pscustomobject]@{ Success=$false; Error=[string]$_.Exception.Message }
    } finally {
        Remove-ApplicationUpdateResultFile
    }

    if ($script:applicationUpdateCancelledForOffline -or $script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0") {
        $script:applicationUpdateCancelledForOffline = $false
        return
    }
    if (-not [bool]$result.Success) {
        $errorText = if ($result.PSObject.Properties["Error"]) { [string]$result.Error } else { Get-DashboardText "common.unknown" }
        if (-not $script:activeProcess) {
            $status.Text = Get-DashboardText "update.check.failedStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        [void](Write-ToolLog -Level "WARN" -Event "ApplicationUpdate.CheckFailed" -Message (Get-DashboardText "update.check.failedLog" @($errorText)) -Data ([ordered]@{ ExitCode=$exitCode }))
        return
    }

    if ([bool]$result.UpdateAvailable) {
        $script:availableApplicationUpdate = $result
        $script:applicationUpdatePromptPending = $true
        if (-not $script:activeProcess) {
            $status.Text = Get-DashboardText "update.check.availableStatus" @($result.LatestVersion)
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.Available" -Message (Get-DashboardText "update.check.availableLog" @($result.LatestVersion)) -Data ([ordered]@{
            CurrentVersion=$result.CurrentVersion; LatestVersion=$result.LatestVersion; DownloadStarted=$false
        }))
        Invoke-PendingApplicationUpdateWork
        return
    }

    $script:availableApplicationUpdate = $null
    $script:applicationUpdatePromptPending = $false
    if (-not $script:activeProcess) {
        $status.Text = Get-DashboardText "update.check.latestStatus" @($result.CurrentVersion)
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
    }
    [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.Current" -Message (Get-DashboardText "update.check.latestLog" @($result.CurrentVersion)))
}

function Show-ApplicationUpdateDialog {
    param([Parameter(Mandatory = $true)][object]$Candidate)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.Text = Get-DashboardText "update.dialog.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(750, 610)
    $dialog.MinimumSize = New-Object System.Drawing.Size(750, 610)
    $dialog.MaximumSize = New-Object System.Drawing.Size(750, 610)
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.Tag = "Later"

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "update.dialog.heading" @([string]$Candidate.Title, [string]$Candidate.LatestVersion)
    $heading.Font = $fontTitle
    $heading.Location = New-Object System.Drawing.Point(28, 24)
    $heading.Size = New-Object System.Drawing.Size(680, 46)
    $dialog.Controls.Add($heading)

    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = Get-DashboardText "update.dialog.version" @([string]$Candidate.CurrentVersion, [string]$Candidate.LatestVersion)
    $versionLabel.Font = $fontBold
    $versionLabel.Location = New-Object System.Drawing.Point(30, 76)
    $versionLabel.Size = New-Object System.Drawing.Size(670, 26)
    $dialog.Controls.Add($versionLabel)

    $publishedAt = [DateTime]::MinValue
    $publishedText = [string]$Candidate.PublishedAtUtc
    if ([DateTime]::TryParse([string]$Candidate.PublishedAtUtc, [ref]$publishedAt)) {
        $publishedText = $publishedAt.ToLocalTime().ToString("dd/MM/yyyy HH:mm")
    }
    $publishedLabel = New-Object System.Windows.Forms.Label
    $publishedLabel.Text = Get-DashboardText "update.dialog.published" @($publishedText)
    $publishedLabel.Location = New-Object System.Drawing.Point(30, 104)
    $publishedLabel.Size = New-Object System.Drawing.Size(670, 24)
    $dialog.Controls.Add($publishedLabel)

    $changesText = (@($Candidate.Changes | ForEach-Object { "• " + [string]$_ }) -join "`r`n")
    $changes = New-Object System.Windows.Forms.TextBox
    $changes.Multiline = $true
    $changes.ReadOnly = $true
    $changes.ScrollBars = "Vertical"
    $changes.WordWrap = $true
    $changes.Text = Get-DashboardText "update.dialog.changes" @($changesText)
    $changes.Font = $fontNormal
    $changes.Location = New-Object System.Drawing.Point(30, 136)
    $changes.Size = New-Object System.Drawing.Size(670, 230)
    $dialog.Controls.Add($changes)

    $privacy = New-Object System.Windows.Forms.Label
    $privacy.Text = Get-DashboardText "update.dialog.privacy"
    $privacy.Location = New-Object System.Drawing.Point(30, 380)
    $privacy.Size = New-Object System.Drawing.Size(670, 88)
    $privacy.Font = $fontSmall
    $dialog.Controls.Add($privacy)

    $updateNowButton = New-Object System.Windows.Forms.Button
    $updateNowButton.Text = Get-DashboardText "update.choice.updateNow"
    $updateNowButton.Font = $fontBold
    $updateNowButton.Location = New-Object System.Drawing.Point(76, 494)
    $updateNowButton.Size = New-Object System.Drawing.Size(180, 42)
    $updateNowButton.Add_Click({ $dialog.Tag = "UpdateNow"; $dialog.Close() })
    $dialog.Controls.Add($updateNowButton)

    $laterButton = New-Object System.Windows.Forms.Button
    $laterButton.Text = Get-DashboardText "update.choice.remindLater"
    $laterButton.Location = New-Object System.Drawing.Point(274, 494)
    $laterButton.Size = New-Object System.Drawing.Size(180, 42)
    $laterButton.Add_Click({ $dialog.Tag = "Later"; $dialog.Close() })
    $dialog.Controls.Add($laterButton)

    $dismissButton = New-Object System.Windows.Forms.Button
    $dismissButton.Text = Get-DashboardText "update.choice.dismissSession"
    $dismissButton.Location = New-Object System.Drawing.Point(472, 494)
    $dismissButton.Size = New-Object System.Drawing.Size(180, 42)
    $dismissButton.Add_Click({ $dialog.Tag = "Dismiss"; $dialog.Close() })
    $dialog.Controls.Add($dismissButton)
    $dialog.AcceptButton = $updateNowButton
    $dialog.CancelButton = $laterButton

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    $palette = Get-ToolUiPalette -Mode $script:dashboardTheme
    $updateNowButton.BackColor = $palette.Primary
    $updateNowButton.ForeColor = if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    foreach ($button in @($updateNowButton, $laterButton, $dismissButton)) {
        $button.FlatStyle = "Flat"
        $button.FlatAppearance.BorderSize = 0
        Set-ModernRoundedRegion -Control $button -Radius 9
    }
    $changes.SelectionStart = 0
    $changes.SelectionLength = 0
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Start-ApplicationUpdateApply {
    param([Parameter(Mandatory = $true)][object]$Candidate)

    try {
        if (-not (Test-ApplicationSelfUpdateAllowed)) { throw (Get-DashboardText "update.selfUpdateUnavailable") }
        if ($script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0") { throw (Get-DashboardText "foundation.offline.actionBlocked" @((Get-DashboardText "update.check.action"))) }
        if (-not [bool]$Candidate.CanSelfUpdate) { throw (Get-DashboardText "update.selfUpdateUnavailable") }
        if ([string]$env:TOOL_SECURE_LAUNCH -ne "1") { throw (Get-DashboardText "update.secureLauncherRequired") }
        $launcherPath = [string]$env:TOOL_LAUNCHER_PATH
        $launcherProcessId = 0
        if ([string]::IsNullOrWhiteSpace($launcherPath) -or -not (Test-Path -LiteralPath $launcherPath -PathType Leaf) -or
            -not [int]::TryParse([string]$env:TOOL_LAUNCHER_PID, [ref]$launcherProcessId) -or $launcherProcessId -le 0) {
            throw (Get-DashboardText "update.secureLauncherRequired")
        }
        $freshIntegrity = Test-ToolIntegrity
        if (-not $freshIntegrity.Valid) { throw $freshIntegrity.Message }
        $currentLauncherSha256 = Get-ApplicationUpdateFileSha256 $launcherPath
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$applicationUpdateScript`" -Mode Apply -ConsentGranted -Culture `"$script:dashboardCulture`" -CurrentVersion `"$releaseVersion`" -ExpectedVersion `"$($Candidate.LatestVersion)`" -ManifestUrl `"$applicationUpdateManifestUrl`" -LauncherPath `"$launcherPath`" -LauncherProcessId $launcherProcessId -ExpectedCurrentSha256 `"$currentLauncherSha256`""
        # Do not call RunAs directly here.  The Windows RunAs broker may drop
        # the secure-launch variables; the bridge restores only the reviewed
        # environment and binds this request to Tool-UpdateManager.ps1.
        $updaterProcess = Start-DetachedToolModuleProcess -ModuleId "application.update.apply" -Arguments $arguments -Elevate -Hidden
        if (-not $updaterProcess) { throw (Get-DashboardText "module.processMissing") }
        $script:applicationUpdateApplyStarted = $true
        $script:applicationUpdatePromptPending = $false
        $script:applicationUpdateReminderPending = $false
        [void](Write-ToolLog -Level "AUDIT" -Event "ApplicationUpdate.Confirmed" -Message (Get-DashboardText "update.choice.updateNow") -Data ([ordered]@{
            CurrentVersion=$releaseVersion; TargetVersion=[string]$Candidate.LatestVersion; UpdaterProcessId=[int]$updaterProcess.Id
        }))
        $form.Close()
    } catch {
        $message = Get-DashboardText "update.apply.startFailed" @($_.Exception.Message)
        $status.Text = $message
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        [void](Write-ToolLog -Level "ERROR" -Event "ApplicationUpdate.ApplyStartFailed" -Message $message)
        [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "update.apply.failedTitle"), "OK", "Error") | Out-Null
        $script:applicationUpdateReminderPending = $true
        $script:applicationUpdateReminderDueUtc = [DateTime]::UtcNow.AddMinutes(10)
        $script:applicationUpdateTaskObservedAfterDeferral = $false
    }
}

function Invoke-PendingApplicationUpdateWork {
    if ($script:applicationUpdateApplyStarted -or $script:applicationUpdateDialogVisible -or
        -not (Test-ApplicationSelfUpdateAllowed) -or $script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0" -or
        $script:applicationUpdateDismissedForSession) {
        return
    }
    if ($script:applicationUpdateProcess -and -not $script:applicationUpdateProcess.HasExited) { return }
    if ($script:activeProcess -and -not $script:activeProcess.HasExited) { return }

    if ($script:applicationUpdateReminderPending -and $script:availableApplicationUpdate -and
        ($script:applicationUpdateTaskObservedAfterDeferral -or [DateTime]::UtcNow -ge $script:applicationUpdateReminderDueUtc)) {
        $script:applicationUpdateReminderPending = $false
        $script:applicationUpdatePromptPending = $true
    }
    if ($script:applicationUpdatePromptPending -and $script:availableApplicationUpdate) {
        $script:applicationUpdateDialogVisible = $true
        try {
            $choice = Show-ApplicationUpdateDialog -Candidate $script:availableApplicationUpdate
            $script:applicationUpdatePromptPending = $false
            if ($choice -eq "UpdateNow") {
                Start-ApplicationUpdateApply -Candidate $script:availableApplicationUpdate
            } elseif ($choice -eq "Dismiss") {
                $script:applicationUpdateDismissedForSession = $true
                $script:applicationUpdateReminderPending = $false
                $status.Text = Get-DashboardText "update.dismissed.status"
                $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
                [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.DismissedForSession" -Message $status.Text)
            } else {
                $script:applicationUpdateReminderPending = $true
                $script:applicationUpdateReminderDueUtc = [DateTime]::UtcNow.AddHours(2)
                $script:applicationUpdateTaskObservedAfterDeferral = $false
                $status.Text = Get-DashboardText "update.reminder.scheduled"
                $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
                [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.Deferred" -Message $status.Text -Data ([ordered]@{ ReminderAfterHours=2; ReminderAfterNextTask=$true }))
            }
        } finally {
            $script:applicationUpdateDialogVisible = $false
        }
        return
    }
    if ($script:applicationUpdateCheckPending) { Start-ApplicationUpdateCheck }
}
