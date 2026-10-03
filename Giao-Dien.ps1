param()

$toolVersion = "5.0"
$script:startupTracePath = [string]$env:TOOL_STARTUP_TRACE_PATH
$script:startupTraceClock = $null
$script:startupTraceEncoding = $null
if (-not [string]::IsNullOrWhiteSpace($script:startupTracePath)) {
    $script:startupTraceClock = [Diagnostics.Stopwatch]::StartNew()
    $script:startupTraceEncoding = New-Object Text.UTF8Encoding($false)
}
# Load function libraries before executing entrypoint statements. Keeping the
# imports explicit makes the runtime dependency graph auditable and lets a
# missing library fail before any UI state is created.
. (Join-Path $PSScriptRoot 'Dashboard-Core.ps1')
. (Join-Path $PSScriptRoot 'Dashboard-Execution.ps1')
. (Join-Path $PSScriptRoot 'Dashboard-OnlineUpdate.ps1')
. (Join-Path $PSScriptRoot 'Dashboard-CleanupWorkflow.ps1')
. (Join-Path $PSScriptRoot 'Dashboard-AssuranceCenter.ps1')

Write-DashboardStartupTrace "Script.Started"
$dashboardSchemaVersion = "2.0"
$releaseVersion = "5.0"
$releaseBuildDate = "2026.09.26"
$toolDisplayVersion = "v$toolVersion"
$releaseDisplayName = "v5.0"
$script:isUnsignedDevelopmentBuild = $false

if ($PSVersionTable.PSVersion.Major -lt 3) {
    exit 10
}

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$dataLifecycleHelper = Join-Path $PSScriptRoot "Tool-DataLifecycle.ps1"
$compatibilityHelper = Join-Path $PSScriptRoot "Tool-Compatibility.ps1"
$capabilityHelper = Join-Path $PSScriptRoot "Tool-Capabilities.ps1"
$scanOptimizationHelper = Join-Path $PSScriptRoot "Tool-ScanOptimization.ps1"
$loggingHelper = Join-Path $PSScriptRoot "Tool-Logging.ps1"
$moduleContractHelper = Join-Path $PSScriptRoot "Tool-ModuleContract.ps1"
$reportSchemaHelper = Join-Path $PSScriptRoot "Tool-ReportSchema.ps1"
$resultCenterHelper = Join-Path $PSScriptRoot "Tool-ResultCenter.ps1"
$reportExportHelper = Join-Path $PSScriptRoot "Tool-ReportExport.ps1"
$pluginEngineHelper = Join-Path $PSScriptRoot "Tool-PluginEngine.ps1"
$timelineHelper = Join-Path $PSScriptRoot "Tool-LicenseTimeline.ps1"
$safetyPolicyHelper = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
$enterpriseHelper = Join-Path $PSScriptRoot "Tool-Enterprise.ps1"
$uiThemeHelper = Join-Path $PSScriptRoot "Tool-UiTheme.ps1"
$dashboardPresentationHelper = Join-Path $PSScriptRoot "Tool-DashboardPresentation.ps1"
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
$offlinePolicyHelper = Join-Path $PSScriptRoot "Tool-OfflinePolicy.ps1"
$provenanceHelper = Join-Path $PSScriptRoot "Tool-Provenance.ps1"
$provenanceManifest = Join-Path $PSScriptRoot "OFFICIAL-PROVENANCE-v1.json"
$provenanceSignature = Join-Path $PSScriptRoot "OFFICIAL-PROVENANCE-v1.json.p7s"
$assistantHelper = Join-Path $PSScriptRoot "Tool-Assistant.ps1"
$softwareInventoryHelper = Join-Path $PSScriptRoot "Tool-SoftwareInventory.ps1"
$softwareCatalogUpdateScript = Join-Path $PSScriptRoot "software-license-online-update.ps1"
$applicationUpdateScript = Join-Path $PSScriptRoot "Tool-UpdateManager.ps1"
$applicationUpdateManifestUrl = "https://raw.githubusercontent.com/thanhvietithopnghia-rgb/VietLicenSure/main/update-manifest-v1.json"
$script:dashboardCulture = "vi-VN"
if (Test-Path -LiteralPath $localizationHelper -PathType Leaf) {
    . $localizationHelper
    $script:dashboardCulture = Get-ToolCulture
    $env:TOOL_UI_CULTURE = $script:dashboardCulture
}
Write-DashboardStartupTrace "Localization.Ready"

$missingFoundationFiles = @($runtimeHelper, $dataLifecycleHelper, $compatibilityHelper, $capabilityHelper, $scanOptimizationHelper, $loggingHelper, $moduleContractHelper, $reportSchemaHelper, $resultCenterHelper, $reportExportHelper, $pluginEngineHelper, $timelineHelper, $safetyPolicyHelper, $enterpriseHelper, $uiThemeHelper, $dashboardPresentationHelper, $localizationHelper, $offlinePolicyHelper, $provenanceHelper, $provenanceManifest, $assistantHelper, $softwareInventoryHelper, $softwareCatalogUpdateScript, $applicationUpdateScript) | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
if ($missingFoundationFiles.Count -gt 0) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        (Get-DashboardText "startup.missingFoundation" @((@($missingFoundationFiles | ForEach-Object { [IO.Path]::GetFileName($_) })) -join ', ')),
        (Get-DashboardText "startup.incompleteTitle"), "OK", "Error") | Out-Null
    exit 12
}
try {
    . $runtimeHelper
    Write-DashboardStartupTrace "Module.Runtime"
    . $dataLifecycleHelper
    $dataLifecycleState = Initialize-ToolDataLifecycle
    Write-DashboardStartupTrace "Module.DataLifecycle"
    . $compatibilityHelper
    Write-DashboardStartupTrace "Module.Compatibility"
    . $capabilityHelper
    Write-DashboardStartupTrace "Module.Capabilities"
    . $scanOptimizationHelper
    Write-DashboardStartupTrace "Module.ScanOptimization"
    . $loggingHelper
    Write-DashboardStartupTrace "Module.Logging"
    . $moduleContractHelper
    Write-DashboardStartupTrace "Module.Contract"
    . $reportSchemaHelper
    Write-DashboardStartupTrace "Module.ReportSchema"
    . $resultCenterHelper
    Write-DashboardStartupTrace "Module.ResultCenter"
    . $reportExportHelper
    Write-DashboardStartupTrace "Module.ReportExport"
    . $pluginEngineHelper
    Write-DashboardStartupTrace "Module.PluginEngine"
    . $timelineHelper
    Write-DashboardStartupTrace "Module.Timeline"
    . $safetyPolicyHelper
    Write-DashboardStartupTrace "Module.SafetyPolicy"
    . $enterpriseHelper
    Write-DashboardStartupTrace "Module.Enterprise"
    . $uiThemeHelper
    Write-DashboardStartupTrace "Module.UiTheme"
    if (-not (Get-Command Get-ToolText -ErrorAction SilentlyContinue)) { . $localizationHelper }
    . $offlinePolicyHelper
    Write-DashboardStartupTrace "Module.OfflinePolicy"
    . $provenanceHelper
    Write-DashboardStartupTrace "Module.Provenance"
    . $assistantHelper
    Write-DashboardStartupTrace "Module.Assistant"
    . $softwareInventoryHelper
    Write-DashboardStartupTrace "Module.SoftwareInventory"
    $script:softwareCatalogFreshnessState = $null
    Write-DashboardStartupTrace "Catalog.Deferred"
    $provenanceState = Get-ToolOfficialBuildState -ManifestPath $provenanceManifest -SignaturePath $provenanceSignature
    $launcherOfficialState = if ([string]::IsNullOrWhiteSpace([string]$env:TOOL_OFFICIAL_BUILD_STATE)) { 'Unverified' } else { [string]$env:TOOL_OFFICIAL_BUILD_STATE }
    $launcherOfficialFailure = if ([string]::IsNullOrWhiteSpace([string]$env:TOOL_OFFICIAL_BUILD_FAILURE)) { 'NotChecked' } else { [string]$env:TOOL_OFFICIAL_BUILD_FAILURE }
    if ($launcherOfficialState -in @('Official','OfficialSelfSigned','Store') -and [string]$provenanceState.State -eq 'Official') {
        $env:TOOL_OFFICIAL_BUILD_STATE = $launcherOfficialState
        $env:TOOL_OFFICIAL_BUILD_FAILURE = ''
    } elseif ($launcherOfficialState -eq 'Modified' -or [string]$provenanceState.State -eq 'Modified') {
        $env:TOOL_OFFICIAL_BUILD_STATE = 'Modified'
        $env:TOOL_OFFICIAL_BUILD_FAILURE = 'Provenance:' + [string]$provenanceState.Code
        $env:TOOL_SELF_UPDATE_ALLOWED = '0'
    } else {
        $env:TOOL_OFFICIAL_BUILD_STATE = 'Unverified'
        $script:isUnsignedDevelopmentBuild = [bool]($launcherOfficialFailure -eq 'DevelopmentBuild')
        $env:TOOL_OFFICIAL_BUILD_FAILURE = if ($script:isUnsignedDevelopmentBuild) { 'DevelopmentBuild' } else { 'Provenance:' + [string]$provenanceState.Code }
        $env:TOOL_SELF_UPDATE_ALLOWED = '0'
    }
    Write-DashboardStartupTrace "Trust.Ready"
    $architectureState = Assert-ToolNativeArchitecture
    Write-DashboardStartupTrace "Metadata.Architecture"
    $toolPowerShellPath = Get-ToolNativePowerShellPath
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
    Write-DashboardStartupTrace "Metadata.NativePaths"
    $capabilityState = Get-ToolCapabilityProfile -StartupFast
    Write-DashboardStartupTrace "Metadata.Capabilities"
    if (-not $capabilityState.SupportedOperatingSystem) { throw (Get-DashboardText "startup.unsupportedOs") }
    $moduleContractState = Get-ToolModuleContractMetadata
    Write-DashboardStartupTrace "Metadata.Contract"
    $reportSchemaState = Get-ToolReportSchemaMetadata
    Write-DashboardStartupTrace "Metadata.ReportSchema"
    $safetyPolicyState = Get-ToolSafetyPolicyMetadata
    Write-DashboardStartupTrace "Metadata.SafetyPolicy"
    $enterpriseState = Get-ToolEnterpriseMetadata
    Write-DashboardStartupTrace "Metadata.Enterprise"
    $compatibilityState = Get-ToolCompatibilityMetadata
    Write-DashboardStartupTrace "Metadata.Compatibility"
    $localizationState = Get-ToolLocalizationMetadata
    Write-DashboardStartupTrace "Metadata.Localization"
    $offlinePolicyState = Get-ToolOfflinePolicyMetadata
    Write-DashboardStartupTrace "Metadata.Ready"
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_CAPABILITY_SCHEMA -ne [string]$capabilityState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("capability")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_MODULE_CONTRACT_SCHEMA -ne [string]$moduleContractState.ContractSchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("module contract")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_REPORT_SCHEMA -ne [string]$reportSchemaState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("report")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_SAFETY_POLICY_SCHEMA -ne [string]$safetyPolicyState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("safety policy")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_DASHBOARD_SCHEMA -ne [string]$dashboardSchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("dashboard")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_ENTERPRISE_SCHEMA -ne [string]$enterpriseState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("enterprise")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_COMPATIBILITY_SCHEMA -ne [string]$compatibilityState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("compatibility")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_LOCALIZATION_SCHEMA -ne [string]$localizationState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("localization")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_OFFLINE_POLICY_SCHEMA -ne [string]$offlinePolicyState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("offline policy")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_DATA_SCHEMA_VERSION -ne [string]$dataLifecycleState.DataSchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("data lifecycle")) }
    $loggingState = Initialize-ToolLogging -Component "GUI" -ToolVersion $toolVersion
    $timelineState = Initialize-ToolLicenseTimeline -ToolVersion $toolVersion
    Write-DashboardStartupTrace "Services.Ready"
    $nativeNotepadPath = Get-ToolNativeSystemPath "notepad.exe"
    $nativeExplorerPath = Get-ToolWindowsPath "explorer.exe"
    if (-not (Test-Path -LiteralPath $nativeExplorerPath -PathType Leaf)) {
        throw (Get-DashboardText "startup.explorerMissing" @($nativeExplorerPath))
    }
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        (Get-DashboardText "startup.runtimeTitle"), "OK", "Warning") | Out-Null
    exit 12
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. $dashboardPresentationHelper
Write-DashboardStartupTrace "Module.DashboardPresentation"
$script:dpiAwarenessState = Initialize-ToolDpiAwareness
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
[System.Windows.Forms.Application]::EnableVisualStyles()
Write-DashboardStartupTrace "WinForms.Ready"

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$reportScript = Join-Path $baseDir "kiem-tra-cau-hinh-ban-quyen.ps1"
$elevatedBridgeScript = Join-Path $baseDir "Tool-ElevatedBridge.ps1"
$cleanupScript = Join-Path $baseDir "windows-license-compliance-cleanup.ps1"
$backupScript = Join-Path $baseDir "windows-license-backup.ps1"
$restoreScript = Join-Path $baseDir "windows-license-restore.ps1"
$oemScript = Join-Path $baseDir "windows-oem-license-assistant.ps1"
$deepScanScript = Join-Path $baseDir "windows-license-deep-scan.ps1"
$forensicsScript = Join-Path $baseDir "windows-license-forensics.ps1"
$licenseManagerScript = Join-Path $baseDir "enterprise-license-manager.ps1"
$localLicenseManagerScript = Join-Path $baseDir "windows-office-license-manager.ps1"
$assuranceScript = Join-Path $baseDir "windows-license-assurance.ps1"
$guideFile = Join-Path $baseDir "HUONG-DAN.txt"
$englishGuideFile = Join-Path $baseDir "USER-GUIDE-en-US.md"
$firstRunFaqFile = Join-Path $baseDir "FAQ-NGUOI-DUNG-MOI-v5.0.md"
$englishFirstRunFaqFile = Join-Path $baseDir "FIRST-RUN-FAQ-v5.0.md"
$historyFile = Join-Path $baseDir "LICH-SU-PHIEN-BAN.txt"
$englishHistoryFile = Join-Path $baseDir "VERSION-HISTORY-en-US.md"
$integrityManifest = Join-Path $baseDir "TOOL-SHA256SUMS.txt"
$requiredIntegrityFiles = @(
    "HUONG-DAN.txt", "USER-GUIDE-en-US.md", "FAQ-NGUOI-DUNG-MOI-v5.0.md", "FIRST-RUN-FAQ-v5.0.md", "LICH-SU-PHIEN-BAN.txt", "VERSION-HISTORY-en-US.md", "LICENSE-NOTICE.txt",
    "SOURCE-POLICY-v5.0.md", "Tool-Provenance.ps1", "OFFICIAL-PROVENANCE-v1.json",
    "Giao-Dien.ps1", "Dashboard-Core.ps1", "Dashboard-Execution.ps1", "Dashboard-OnlineUpdate.ps1", "Dashboard-CleanupWorkflow.ps1", "Dashboard-AssuranceCenter.ps1", "kiem-tra-cau-hinh-ban-quyen.ps1", "VietLicenSure-icon.svg",
    "VietLicenSure.cmd", "Tool-Runtime.ps1", "Tool-ElevatedBridge.ps1", "Tool-DataLifecycle.ps1", "Tool-Compatibility.ps1", "compatibility-catalog-v1.0.json", "Tool-Capabilities.ps1", "Tool-ScanOptimization.ps1", "Tool-Logging.ps1", "Tool-ModuleContract.ps1", "Tool-UiTheme.ps1", "Tool-DashboardPresentation.ps1", "Tool-Localization.ps1", "Tool-Strings.vi-VN.json", "Tool-Strings.en-US.json", "Tool-OfflinePolicy.ps1", "Tool-Assistant.ps1", "tool-assistant-knowledge-v1.1.json", "Tool-SoftwareInventory.ps1", "Tool-LicenseCompliance.ps1", "software-license-catalog-v1.0.json", "software-license-catalog-v1.0.json.p7s", "software-license-online-update.ps1", "Tool-UpdateManager.ps1", "windows-license-backup.ps1",
    "Tool-ReportSchema.ps1", "Tool-ResultCenter.ps1", "Tool-ReportExport.ps1", "Tool-PluginEngine.ps1", "Tool-LicenseTimeline.ps1", "Tool-SafetyPolicy.ps1",
    "Tool-Enterprise.ps1", "Tool-EnterpriseCli.ps1", "Tool-EnterpriseHost.ps1", "Tool-EnterpriseAgent.ps1", "enterprise-license-manager.ps1",
    "windows-license-compliance-cleanup.ps1", "Cleanup-Platform.ps1", "Cleanup-Detection.ps1", "Cleanup-Evidence.ps1", "Cleanup-Remediation.ps1", "windows-license-restore.ps1",
    "windows-license-deep-scan.ps1", "windows-license-forensics.ps1",
    "windows-oem-license-assistant.ps1", "windows-office-license-manager.ps1",
    "windows-license-assurance.ps1", "builtin-windows-office-trust.plugin.json"
)
if (Test-Path -LiteralPath $provenanceSignature -PathType Leaf) {
    $requiredIntegrityFiles += "OFFICIAL-PROVENANCE-v1.json.p7s"
}
$runtimeDir = if (-not [string]::IsNullOrWhiteSpace($env:TOOL_SECURE_RUNTIME_DIR)) { $env:TOOL_SECURE_RUNTIME_DIR } else { Join-Path $baseDir "runtime" }
if (-not (Test-Path -LiteralPath $runtimeDir -PathType Container)) { New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null }
$env:TOOL_SECURE_RUNTIME_FAILED = "0"
$script:secureRuntimeAclInitError = ""
if (-not (Test-ProtectedToolDirectoryAcl $runtimeDir)) {
    try {
        $administratorsSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $systemSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-18")
        $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $userScopedData = [string]$env:TOOL_DATA_SCOPE -ne "Machine"
        $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
        $runtimeAcl = New-Object Security.AccessControl.DirectorySecurity
        $runtimeAcl.SetAccessRuleProtection($true, $false)
        $runtimeAcl.SetOwner($(if ($userScopedData) { $currentUserSid } else { $administratorsSid }))
        $runtimeAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($administratorsSid, "FullControl", $inheritance, "None", "Allow")))
        $runtimeAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", $inheritance, "None", "Allow")))
        if ($userScopedData) {
            $runtimeAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($currentUserSid, "FullControl", $inheritance, "None", "Allow")))
        }
        Set-Acl -LiteralPath $runtimeDir -AclObject $runtimeAcl -ErrorAction Stop
    } catch {
        $script:secureRuntimeAclInitError = $_.Exception.Message
    }
}
if (-not (Test-ProtectedToolDirectoryAcl $runtimeDir)) {
    $env:TOOL_SECURE_RUNTIME_FAILED = "1"
    if (Get-Command Write-ToolLog -ErrorAction SilentlyContinue) {
        [void](Write-ToolLog -Level "ERROR" -Event "Security.RuntimeAclInvalid" -Message $script:secureRuntimeAclInitError -Data ([ordered]@{ RuntimeDirectory=$runtimeDir }))
    }
}
$approvedKmsFile = if (-not [string]::IsNullOrWhiteSpace($env:TOOL_APPROVED_KMS_FILE)) { $env:TOOL_APPROVED_KMS_FILE } else { Join-Path $baseDir "approved-kms-servers.txt" }
$bundledApprovedKmsFile = Join-Path $baseDir "approved-kms-servers.txt"
$desktop = [Environment]::GetFolderPath("Desktop")
$reportRoot = Join-Path $desktop "BaoCao-VietLicenSure"
$uiTypography = Get-ToolUiTypography
$fontNormal = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.NormalSize, [System.Drawing.FontStyle]::Regular)
$fontSmall = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.SmallSize, [System.Drawing.FontStyle]::Regular)
$fontSupportSmall = New-Object System.Drawing.Font($uiTypography.FontFamily, [Math]::Max(7.5, ($uiTypography.SmallSize - 1.0)), [System.Drawing.FontStyle]::Regular)
$fontBold = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.NormalSize, [System.Drawing.FontStyle]::Bold)
$fontTitle = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.DashboardTitleSize, [System.Drawing.FontStyle]::Bold)
$fontTitleCompact = New-Object System.Drawing.Font($uiTypography.FontFamily, 16.0, [System.Drawing.FontStyle]::Bold)
$fontTitleMedium = New-Object System.Drawing.Font($uiTypography.FontFamily, 14.0, [System.Drawing.FontStyle]::Bold)
$fontTitleSmall = New-Object System.Drawing.Font($uiTypography.FontFamily, 12.0, [System.Drawing.FontStyle]::Bold)
$fontTitleTiny = New-Object System.Drawing.Font($uiTypography.FontFamily, 10.5, [System.Drawing.FontStyle]::Bold)
$fontTitleMicro = New-Object System.Drawing.Font($uiTypography.FontFamily, 9.0, [System.Drawing.FontStyle]::Bold)
$fontTitleMinimum = New-Object System.Drawing.Font($uiTypography.FontFamily, 8.0, [System.Drawing.FontStyle]::Bold)
$fontCardValue = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.CardValueSize, [System.Drawing.FontStyle]::Bold)
$fontIntroTitle = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.IntroTitleSize, [System.Drawing.FontStyle]::Bold)
$fontTile = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.TileSize, [System.Drawing.FontStyle]::Regular)
$fontSidebarTitle = New-Object System.Drawing.Font($uiTypography.FontFamily, 11.5, [System.Drawing.FontStyle]::Bold)
$fontSidebarTitleCompact = New-Object System.Drawing.Font($uiTypography.FontFamily, 10.0, [System.Drawing.FontStyle]::Bold)
$fontSidebarTitleMinimum = New-Object System.Drawing.Font($uiTypography.FontFamily, 9.0, [System.Drawing.FontStyle]::Bold)
$fontSidebar = New-Object System.Drawing.Font($uiTypography.FontFamily, 10.0, [System.Drawing.FontStyle]::Regular)

$form = New-Object System.Windows.Forms.Form
$script:dashboardStartupLayoutPending = $true
$form.SuspendLayout()
$form.Text = "[$releaseDisplayName]"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1480, 900)
$form.MinimumSize = New-Object System.Drawing.Size(900, 620)
$form.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
$form.Font = $fontNormal
$form.AutoScroll = $false
$form.AutoScrollMargin = New-Object System.Drawing.Size(0, 0)
# The main dashboard is positioned by Update-MainLayout in the current
# per-monitor physical coordinate space.  Letting WinForms auto-scale these
# manually positioned children a second time at 150-200% DPI causes clipped
# labels and overlapping tiles.  Modal dialogs keep their own Dpi mode below.
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$script:dashboardDialogStack = New-Object System.Collections.Stack
$script:dashboardWorkflowCloseRequested = $false

$script:dashboardThemePreference = Get-ToolUiThemePreference
$script:dashboardTheme = Get-ToolUiTheme
$script:toolUiPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
$script:dashboardCulture = Get-ToolCulture
$script:offlineMode = [bool](Get-ToolOfflineMode)
$env:TOOL_UI_CULTURE = $script:dashboardCulture
$env:TOOL_OFFLINE_MODE = if ($script:offlineMode) { "1" } else { "0" }
$form.Text = "$(Get-ToolText -Key "app.title" -Culture $script:dashboardCulture) - $releaseDisplayName"
$dashboardCards = @{}
$dashboardCardPanels = New-Object System.Collections.ArrayList
$menuButtonMetadata = @{}
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 12000
$toolTip.InitialDelay = 350
$toolTip.ReshowDelay = 100
$dashboardIconImages = New-Object System.Collections.ArrayList

$sidebarPanel = New-Object System.Windows.Forms.Panel
$sidebarPanel.BackColor = [System.Drawing.Color]::FromArgb(11, 55, 105)
$sidebarPanel.Location = New-Object System.Drawing.Point(0, 0)
$sidebarPanel.Size = New-Object System.Drawing.Size(196, $form.ClientSize.Height)
$form.Controls.Add($sidebarPanel)

$sidebarBrandIcon = New-Object System.Windows.Forms.PictureBox
$sidebarBrandIcon.BackColor = [System.Drawing.Color]::Transparent
$sidebarBrandIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$sidebarBrandIcon.Location = New-Object System.Drawing.Point(18, 20)
$sidebarBrandIcon.Size = New-Object System.Drawing.Size(42, 48)
$sidebarBrandImage = New-DashboardIconBitmap -Kind "Shield" -Size 42
[void]$dashboardIconImages.Add($sidebarBrandImage)
$sidebarBrandIcon.Image = $sidebarBrandImage
$sidebarPanel.Controls.Add($sidebarBrandIcon)

$sidebarBrand = New-Object System.Windows.Forms.Label
$sidebarBrand.Text = Get-DashboardText "dashboard.sidebar.brand"
$sidebarBrand.Font = $fontSidebarTitle
$sidebarBrand.ForeColor = [System.Drawing.Color]::White
$sidebarBrand.TextAlign = "MiddleLeft"
$sidebarBrand.UseCompatibleTextRendering = $false
$sidebarBrand.UseMnemonic = $false
$sidebarBrand.AutoEllipsis = $false
$sidebarBrand.Location = New-Object System.Drawing.Point(64, 24)
$sidebarBrand.Size = New-Object System.Drawing.Size(128, 38)
$sidebarPanel.Controls.Add($sidebarBrand)

$sidebarNavButtons = New-Object System.Collections.ArrayList
$sidebarNavDefinitions = @(
    @{ Section="Overview"; TextKey="dashboard.nav.overview"; IconKind="NavOverview" },
    @{ Section="Scan"; TextKey="dashboard.nav.scan"; IconKind="NavScan" },
    @{ Section="Remediation"; TextKey="dashboard.nav.remediation"; IconKind="NavRepair" },
    @{ Section="Reports"; TextKey="dashboard.nav.reports"; IconKind="NavReport" },
    @{ Section="Settings"; TextKey="dashboard.nav.settings"; IconKind="NavSettings" }
)
for ($navIndex = 0; $navIndex -lt $sidebarNavDefinitions.Count; $navIndex++) {
    $navDefinition = $sidebarNavDefinitions[$navIndex]
    $navButton = New-Object System.Windows.Forms.Button
    $navButton.Text = Get-DashboardText ([string]$navDefinition.TextKey)
    $navButton.Font = $fontSidebar
    $navButton.ForeColor = [System.Drawing.Color]::White
    $navButton.BackColor = [System.Drawing.Color]::FromArgb(11, 55, 105)
    $navButton.TextAlign = "MiddleLeft"
    $navButton.ImageAlign = "MiddleLeft"
    $navButton.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageBeforeText
    $navButton.Padding = New-Object System.Windows.Forms.Padding(12, 0, 8, 0)
    $navButton.FlatStyle = "Flat"
    $navButton.FlatAppearance.BorderSize = 0
    $navButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $navButton.Location = New-Object System.Drawing.Point(10, (102 + ($navIndex * 54)))
    $navButton.Size = New-Object System.Drawing.Size(176, 44)
    $navIconImage = New-DashboardIconBitmap -Kind ([string]$navDefinition.IconKind) -Size 22
    [void]$dashboardIconImages.Add($navIconImage)
    $navButton.Image = $navIconImage
    $navButton.Tag = [pscustomobject]@{
        Section = [string]$navDefinition.Section
        TextKey = [string]$navDefinition.TextKey
        IconKind = [string]$navDefinition.IconKind
    }
    $navButton.Add_Click({
        param($sender, $eventArgs)
        $selectedSection = [string]$sender.Tag.Section
        if ($selectedSection -eq "Settings") {
            Show-DashboardPreferences
        } else {
            Set-DashboardSection -Section $selectedSection
        }
    })
    [void]$sidebarNavButtons.Add($navButton)
    $sidebarPanel.Controls.Add($navButton)
}

$sidebarFooter = New-Object System.Windows.Forms.Label
$sidebarFooter.Text = Get-DashboardText "dashboard.sidebar.footer"
$sidebarFooter.Font = $fontSmall
$sidebarFooter.ForeColor = [System.Drawing.Color]::FromArgb(182, 214, 248)
$sidebarFooter.TextAlign = "MiddleLeft"
$sidebarFooter.UseCompatibleTextRendering = $false
$sidebarFooter.Location = New-Object System.Drawing.Point(20, 700)
$sidebarFooter.Size = New-Object System.Drawing.Size(160, 52)
$sidebarPanel.Controls.Add($sidebarFooter)

$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.BackColor = [System.Drawing.Color]::White
$headerPanel.Location = New-Object System.Drawing.Point(196, 0)
$headerPanel.Size = New-Object System.Drawing.Size(($form.ClientSize.Width - 196), 78)
$form.Controls.Add($headerPanel)

$headerBrandIcon = New-Object System.Windows.Forms.PictureBox
$headerBrandIcon.BackColor = [System.Drawing.Color]::Transparent
$headerBrandIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$headerBrandIcon.Location = New-Object System.Drawing.Point(20, 14)
$headerBrandIcon.Size = New-Object System.Drawing.Size(42, 48)
$headerBrandImage = New-DashboardIconBitmap -Kind "Shield" -Size 42
[void]$dashboardIconImages.Add($headerBrandImage)
$headerBrandIcon.Image = $headerBrandImage
$headerPanel.Controls.Add($headerBrandIcon)

$title = New-Object System.Windows.Forms.Label
$title.Text = Get-ToolText -Key "app.title" -Culture $script:dashboardCulture
$title.Font = $fontTitle
$title.UseCompatibleTextRendering = $false
$title.UseMnemonic = $false
$title.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$title.TextAlign = "MiddleLeft"
$title.Location = New-Object System.Drawing.Point(74, 10)
$title.Size = New-Object System.Drawing.Size(700, 38)
$headerPanel.Controls.Add($title)

$themeButton = New-Object System.Windows.Forms.Button
$themeButton.Text = Get-ToolText -Key "app.theme.dark" -Culture $script:dashboardCulture
$themeButton.Font = $fontBold
$themeButton.FlatStyle = "Flat"
$themeButton.Size = New-Object System.Drawing.Size(152, 32)
$themeButton.Location = New-Object System.Drawing.Point(820, 12)
$themeButton.Add_Click({
    $script:dashboardTheme = if ($script:dashboardTheme -eq "Light") { "Dark" } else { "Light" }
    $script:dashboardThemePreference = $script:dashboardTheme
    $script:toolUiPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
    [void](Set-ToolUiThemePreference -Mode $script:dashboardTheme)
    Set-DashboardTheme -Mode $script:dashboardTheme
})
$headerPanel.Controls.Add($themeButton)

$offlineButton = New-Object System.Windows.Forms.Button
$offlineButton.Font = $fontBold
$offlineButton.FlatStyle = "Flat"
$offlineButton.FlatAppearance.BorderSize = 1
$offlineButton.Size = New-Object System.Drawing.Size(156, 32)
$offlineButton.Location = New-Object System.Drawing.Point(650, 12)
$offlineButton.Add_Click({ Toggle-DashboardOfflineMode })
$headerPanel.Controls.Add($offlineButton)

$languageCombo = New-Object System.Windows.Forms.ComboBox
$languageCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$languageCombo.Font = $fontNormal
$languageCombo.Size = New-Object System.Drawing.Size(116, 32)
[void]$languageCombo.Items.Add((Get-DashboardText "app.language.vi"))
[void]$languageCombo.Items.Add((Get-DashboardText "app.language.en"))
$languageCombo.SelectedIndex = if ($script:dashboardCulture -eq "en-US") { 1 } else { 0 }
$languageCombo.Add_SelectedIndexChanged({
    $selectedCulture = if ($languageCombo.SelectedIndex -eq 1) { "en-US" } else { "vi-VN" }
    if ($selectedCulture -ne $script:dashboardCulture) { Set-DashboardLanguage -Culture $selectedCulture }
})
$headerPanel.Controls.Add($languageCombo)

$script:syncingCompactNavigation = $false
$compactNavigation = New-Object System.Windows.Forms.ComboBox
$compactNavigation.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$compactNavigation.Font = $fontBold
$compactNavigation.Size = New-Object System.Drawing.Size(190, 30)
$compactNavigation.Visible = $false
$compactNavigation.Tag = @('Overview', 'Scan', 'Remediation', 'Reports', 'Settings')
foreach ($definition in $sidebarNavDefinitions) {
    [void]$compactNavigation.Items.Add((Get-DashboardText ([string]$definition.TextKey)))
}
$compactNavigation.SelectedIndex = 0
$compactNavigation.Add_SelectedIndexChanged({
    if ($script:syncingCompactNavigation -or $compactNavigation.SelectedIndex -lt 0) { return }
    $selectedCompactSection = [string]$compactNavigation.Tag[$compactNavigation.SelectedIndex]
    if ($selectedCompactSection -eq 'Settings') {
        Show-DashboardPreferences
        $script:syncingCompactNavigation = $true
        try {
            $sectionIndex = @('Overview', 'Scan', 'Remediation', 'Reports').IndexOf([string]$script:dashboardSection)
            $compactNavigation.SelectedIndex = [Math]::Max(0, $sectionIndex)
        } finally {
            $script:syncingCompactNavigation = $false
        }
    } else {
        Set-DashboardSection -Section $selectedCompactSection
    }
})
$headerPanel.Controls.Add($compactNavigation)

$developer = New-Object System.Windows.Forms.Label
$developer.Text = Get-ToolText -Key "app.developer" -Culture $script:dashboardCulture
$developer.Font = $fontSupportSmall
$developer.UseCompatibleTextRendering = $false
$developer.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$developer.TextAlign = "MiddleLeft"
$developer.Location = New-Object System.Drawing.Point(74, 46)
$developer.Size = New-Object System.Drawing.Size(700, 22)
$headerPanel.Controls.Add($developer)

$version = New-Object System.Windows.Forms.Label
$version.Text = Get-DashboardText "dashboard.versionSummary" @($releaseDisplayName, $capabilityState.WindowsReleaseName, $capabilityState.FullBuildNumber, $capabilityState.OperatingSystemArchitecture, $reportSchemaState.SchemaVersion)
$version.Font = $fontSmall
$version.UseCompatibleTextRendering = $false
$version.ForeColor = [System.Drawing.Color]::FromArgb(102, 112, 133)
$version.TextAlign = "MiddleLeft"
$version.Location = New-Object System.Drawing.Point(74, 62)
$version.Size = New-Object System.Drawing.Size(860, 20)
$headerPanel.Controls.Add($version)

$introPanel = New-Object System.Windows.Forms.Panel
$introPanel.Location = New-Object System.Drawing.Point(38, 100)
$introPanel.Size = New-Object System.Drawing.Size(860, 58)
$introPanel.BackColor = [System.Drawing.Color]::FromArgb(235, 244, 255)
$introPanel.BorderStyle = "None"
$introPanel.Tag = [pscustomobject]@{
    Kind = "OverviewCard"
    BorderColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
}
$introPanel.Add_Paint({
    param($sender, $eventArgs)
    if (-not $sender -or -not $eventArgs -or $sender.ClientSize.Width -lt 2 -or $sender.ClientSize.Height -lt 2) { return }
    $borderColor = if ($sender.Tag -and $sender.Tag.PSObject.Properties["BorderColor"]) {
        [System.Drawing.Color]$sender.Tag.BorderColor
    } else {
        [System.Drawing.SystemColors]::ControlDark
    }
    $borderPen = New-Object System.Drawing.Pen($borderColor, 2)
    try {
        $eventArgs.Graphics.DrawRectangle($borderPen, 1, 1, ($sender.ClientSize.Width - 3), ($sender.ClientSize.Height - 3))
    } finally {
        $borderPen.Dispose()
    }
})
$form.Controls.Add($introPanel)

$description = New-Object System.Windows.Forms.Label
$description.Text = Get-ToolText -Key "dashboard.overview.title" -Culture $script:dashboardCulture
$description.Font = $fontIntroTitle
$description.UseCompatibleTextRendering = $false
$description.UseMnemonic = $false
$description.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$description.AutoEllipsis = $true
$description.Location = New-Object System.Drawing.Point(15, 6)
$description.Size = New-Object System.Drawing.Size(650, 22)
$introPanel.Controls.Add($description)

$introSummary = New-Object System.Windows.Forms.Label
$introSummary.Text = Get-ToolText -Key "dashboard.overview.subtitle" -Culture $script:dashboardCulture
$introSummary.Font = $fontSupportSmall
$introSummary.UseCompatibleTextRendering = $false
$introSummary.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$introSummary.AutoEllipsis = $true
$introSummary.Location = New-Object System.Drawing.Point(15, 30)
$introSummary.Size = New-Object System.Drawing.Size(650, 20)
$introPanel.Controls.Add($introSummary)

$script:officialBuildState = if ([string]::IsNullOrWhiteSpace([string]$env:TOOL_OFFICIAL_BUILD_STATE)) { 'Unverified' } else { [string]$env:TOOL_OFFICIAL_BUILD_STATE }
if ($script:officialBuildState -eq 'OfficialSelfSigned') {
    $introPanel.BackColor = [System.Drawing.Color]::FromArgb(232, 245, 255)
    Set-DashboardIntroBorderColor -Color ([System.Drawing.Color]::FromArgb(2, 132, 199))
    $description.ForeColor = [System.Drawing.Color]::FromArgb(3, 105, 161)
    $description.Text = Get-DashboardText 'officialBuild.banner.selfSignedTitle'
    $introSummary.ForeColor = [System.Drawing.Color]::FromArgb(7, 89, 133)
    $introSummary.Text = Get-DashboardText 'officialBuild.banner.selfSignedBody'
} elseif ($script:officialBuildState -notin @('Official','Store')) {
    if ($script:isUnsignedDevelopmentBuild) {
        $introPanel.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 225)
        Set-DashboardIntroBorderColor -Color ([System.Drawing.Color]::FromArgb(217, 119, 6))
        $description.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
        $description.Text = Get-DashboardText 'officialBuild.banner.developmentTitle'
        $introSummary.ForeColor = [System.Drawing.Color]::FromArgb(120, 53, 15)
        $introSummary.Text = Get-DashboardText 'officialBuild.banner.developmentBody'
    } elseif ($script:officialBuildState -eq 'Modified') {
        $introPanel.BackColor = [System.Drawing.Color]::FromArgb(255, 235, 238)
        Set-DashboardIntroBorderColor -Color ([System.Drawing.Color]::FromArgb(185, 28, 28))
        $description.ForeColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
        $description.Text = Get-DashboardText 'officialBuild.banner.modifiedTitle'
        $introSummary.ForeColor = [System.Drawing.Color]::FromArgb(127, 29, 29)
        $introSummary.Text = Get-DashboardText 'officialBuild.banner.modifiedBody' @([string]$env:TOOL_OFFICIAL_VERIFICATION_URL)
    } else {
        $introPanel.BackColor = [System.Drawing.Color]::FromArgb(255, 235, 238)
        Set-DashboardIntroBorderColor -Color ([System.Drawing.Color]::FromArgb(185, 28, 28))
        $description.ForeColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
        $description.Text = Get-DashboardText 'officialBuild.banner.unverifiedTitle'
        $introSummary.ForeColor = [System.Drawing.Color]::FromArgb(127, 29, 29)
        $introSummary.Text = Get-DashboardText 'officialBuild.banner.unverifiedBody' @([string]$env:TOOL_OFFICIAL_VERIFICATION_URL)
    }
}

$introAssistantButton = New-Object System.Windows.Forms.Button
$introAssistantButton.Text = Get-ToolText -Key "app.assistant" -Culture $script:dashboardCulture
$introAssistantButton.Font = $fontBold
$introAssistantButton.FlatStyle = "Flat"
$introAssistantButton.FlatAppearance.BorderSize = 0
$introAssistantButton.BackColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$introAssistantButton.ForeColor = [System.Drawing.Color]::White
$introAssistantButton.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageBeforeText
$introAssistantButton.ImageAlign = "MiddleLeft"
$introAssistantButton.TextAlign = "MiddleCenter"
$introAssistantButton.UseMnemonic = $false
$introAssistantButton.AutoEllipsis = $false
$introAssistantButton.AutoSize = $false
$introAssistantButton.Padding = New-Object System.Windows.Forms.Padding(10, 0, 9, 0)
$introAssistantIcon = New-DashboardIconBitmap -Kind "Chat" -Size 18
[void]$dashboardIconImages.Add($introAssistantIcon)
$introAssistantButton.Image = $introAssistantIcon
$introAssistantButton.Size = New-Object System.Drawing.Size(154, 32)
$introAssistantButton.Location = New-Object System.Drawing.Point(526, 12)
$introAssistantButton.Add_Click({
    $requestAssistantOnline = {
        if ($script:offlineMode) { [void](Toggle-DashboardOfflineMode) }
        return (-not [bool]$script:offlineMode)
    }
    Show-ToolAssistantWindow -Owner $form -Culture $script:dashboardCulture -OnlineMode (-not $script:offlineMode) -CurrentReportPath ([string]$script:lastReportPath) -Theme $script:dashboardTheme -RequestOnline $requestAssistantOnline
})
$toolTip.SetToolTip($introAssistantButton, (Get-ToolText -Key "assistant.tooltip" -Culture $script:dashboardCulture))
$introPanel.Controls.Add($introAssistantButton)

$introDetailButton = New-Object System.Windows.Forms.Button
$introDetailButton.Text = Get-ToolText -Key "app.about" -Culture $script:dashboardCulture
$introDetailButton.Font = $fontBold
$introDetailButton.FlatStyle = "Flat"
$introDetailButton.FlatAppearance.BorderSize = 0
$introDetailButton.BackColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$introDetailButton.ForeColor = [System.Drawing.Color]::White
$introDetailButton.Size = New-Object System.Drawing.Size(154, 32)
$introDetailButton.Location = New-Object System.Drawing.Point(690, 12)
$introDetailButton.Add_Click({ Show-ProductIntroduction })
$introPanel.Controls.Add($introDetailButton)
$dashboardPanel = New-Object System.Windows.Forms.Panel
$dashboardPanel.Location = New-Object System.Drawing.Point(38, ($introPanel.Bottom + 8))
$dashboardPanel.Size = New-Object System.Drawing.Size(860, 92)
$dashboardPanel.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($dashboardPanel)

$cardDefinitions = @(
    @{ Key="Compatibility"; IconKind="Windows"; Tone="Windows"; Caption=(Get-ToolText -Key "dashboard.windows" -Culture $script:dashboardCulture); Value=[string]$capabilityState.WindowsReleaseName },
    @{ Key="Architecture"; IconKind="Office"; Tone="Office"; Caption=(Get-ToolText -Key "dashboard.office" -Culture $script:dashboardCulture); Value=[string]$capabilityState.OfficeSummary },
    @{ Key="SecureLaunch"; IconKind="Shield"; Tone="Secure"; Caption=(Get-ToolText -Key "dashboard.runMode" -Culture $script:dashboardCulture); Value=$(if ($script:officialBuildState -eq 'Official') { Get-DashboardText 'officialBuild.state.official' } elseif ($script:officialBuildState -eq 'OfficialSelfSigned') { Get-DashboardText 'officialBuild.state.selfSigned' } elseif ($script:officialBuildState -eq 'Store') { Get-DashboardText 'officialBuild.state.store' } elseif ($script:officialBuildState -eq 'Modified') { Get-DashboardText 'officialBuild.state.modified' } else { Get-DashboardText 'officialBuild.state.unverified' }) },
    @{ Key="Integrity"; IconKind="Check"; Tone="Integrity"; Caption=(Get-ToolText -Key "dashboard.integrity" -Culture $script:dashboardCulture); Value=(Get-ToolText -Key "dashboard.checking" -Culture $script:dashboardCulture) },
    @{ Key="ActionCenter"; IconKind="Report"; Tone="Action"; Caption=(Get-DashboardText "resultCenter.card.caption"); Value=(Get-DashboardText "resultCenter.card.noReport") }
)
for ($cardIndex = 0; $cardIndex -lt $cardDefinitions.Count; $cardIndex++) {
    $definition = $cardDefinitions[$cardIndex]
    $card = New-Object System.Windows.Forms.Panel
    $card.BorderStyle = "None"
    $card.BackColor = [System.Drawing.Color]::White
    $card.Size = New-Object System.Drawing.Size(202, 80)
    $card.Location = New-Object System.Drawing.Point(($cardIndex * 216), 6)
    $card.Tag = [pscustomobject]@{
        Kind = "DashboardCard"
        Tone = [string]$definition.Tone
        BorderColor = [System.Drawing.SystemColors]::ControlDark
    }
    $card.Add_Paint({
        param($sender, $eventArgs)
        if (-not $sender -or -not $eventArgs -or $sender.ClientSize.Width -lt 2 -or $sender.ClientSize.Height -lt 2) { return }
        $borderColor = if ($sender.Tag -and $sender.Tag.PSObject.Properties["BorderColor"]) {
            [System.Drawing.Color]$sender.Tag.BorderColor
        } else {
            [System.Drawing.SystemColors]::ControlDark
        }
        $borderPen = New-Object System.Drawing.Pen($borderColor, 2)
        try {
            $eventArgs.Graphics.DrawRectangle($borderPen, 1, 1, ($sender.ClientSize.Width - 3), ($sender.ClientSize.Height - 3))
        } finally {
            $borderPen.Dispose()
        }
    })

    $cardCaption = New-Object System.Windows.Forms.Label
    $cardCaption.Text = [string]$definition.Caption
    $cardCaption.Font = $fontSmall
    $cardCaption.ForeColor = [System.Drawing.Color]::FromArgb(102, 112, 133)
    $cardCaption.AutoEllipsis = $true
    $cardCaption.Location = New-Object System.Drawing.Point(58, 10)
    $cardCaption.Size = New-Object System.Drawing.Size(134, 18)
    $card.Controls.Add($cardCaption)

    $cardValue = New-Object System.Windows.Forms.Label
    $cardValue.Text = [string]$definition.Value
    $cardValue.Font = $fontCardValue
    $cardValue.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $cardValue.AutoEllipsis = $true
    $cardValue.TextAlign = "MiddleLeft"
    $cardValue.UseCompatibleTextRendering = $false
    $cardValue.Location = New-Object System.Drawing.Point(58, 32)
    $cardValue.Size = New-Object System.Drawing.Size(134, 34)
    $card.Controls.Add($cardValue)

    $cardGlyph = New-Object System.Windows.Forms.PictureBox
    $cardGlyph.BackColor = [System.Drawing.Color]::Transparent
    $cardGlyph.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $cardGlyph.Location = New-Object System.Drawing.Point(11, 23)
    $cardGlyph.Size = New-Object System.Drawing.Size(34, 34)
    $cardGlyph.Tag = "CardGlyph"
    $cardIconImage = New-DashboardIconBitmap -Kind ([string]$definition.IconKind) -Size 34
    [void]$dashboardIconImages.Add($cardIconImage)
    $cardGlyph.Image = $cardIconImage
    $card.Controls.Add($cardGlyph)

    $dashboardCards[[string]$definition.Key] = [pscustomobject]@{
        Panel=$card
        Caption=$cardCaption
        Value=$cardValue
        Glyph=$cardGlyph
        Tone=[string]$definition.Tone
        IconKind=[string]$definition.IconKind
    }
    [void]$dashboardCardPanels.Add($card)
    $dashboardPanel.Controls.Add($card)
    Sync-DashboardCardAccessibility -CardKey ([string]$definition.Key)
    if ([string]$definition.Key -eq "ActionCenter") {
        $card.Cursor = [System.Windows.Forms.Cursors]::Hand
        $card.AccessibleName = Get-DashboardText "resultCenter.card.caption"
        $card.AccessibleDescription = Get-DashboardText "resultCenter.card.tooltip"
        $card.Add_Click({ Invoke-DashboardRootAction -Action { Show-ResultActionCenter } })
        foreach ($clickableChild in @($card.Controls)) {
            $clickableChild.Cursor = [System.Windows.Forms.Cursors]::Hand
            $clickableChild.Add_Click({ Invoke-DashboardRootAction -Action { Show-ResultActionCenter } })
        }
    }
}

$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Location = New-Object System.Drawing.Point(38, ($dashboardPanel.Bottom + 10))
$buttonPanel.Size = New-Object System.Drawing.Size(860, 334)
$buttonPanel.BackColor = [System.Drawing.Color]::White
$buttonPanel.BorderStyle = "None"
$buttonPanel.AutoScroll = $true
$form.Controls.Add($buttonPanel)

$menuCaption = New-Object System.Windows.Forms.Label
$menuCaption.Text = Get-ToolText -Key "dashboard.functions" -Culture $script:dashboardCulture
$menuCaption.Font = $fontBold
$menuCaption.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$menuCaption.Location = New-Object System.Drawing.Point(16, 8)
$menuCaption.Size = New-Object System.Drawing.Size(300, 22)
$buttonPanel.Controls.Add($menuCaption)

$activityPanel = New-Object System.Windows.Forms.Panel
$activityPanel.BackColor = [System.Drawing.Color]::White
$activityPanel.BorderStyle = "None"
$activityPanel.Location = New-Object System.Drawing.Point(($buttonPanel.Right + 12), $buttonPanel.Top)
$activityPanel.Size = New-Object System.Drawing.Size(300, $buttonPanel.Height)
$form.Controls.Add($activityPanel)

$activityPanelCaption = New-Object System.Windows.Forms.Label
$activityPanelCaption.Text = Get-DashboardText "dashboard.activity"
$activityPanelCaption.Font = $fontBold
$activityPanelCaption.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$activityPanelCaption.Location = New-Object System.Drawing.Point(16, 14)
$activityPanelCaption.Size = New-Object System.Drawing.Size(250, 24)
$activityPanel.Controls.Add($activityPanelCaption)

$status = New-Object System.Windows.Forms.Label
$status.Text = ""
$status.Font = $fontNormal
$status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$status.TextAlign = "MiddleLeft"
$status.Location = New-Object System.Drawing.Point(38, ($buttonPanel.Bottom + 13))
$status.Size = New-Object System.Drawing.Size(550, 24)
$activityPanel.Controls.Add($status)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = Get-ToolText -Key "app.close" -Culture $script:dashboardCulture
$closeButton.Font = $fontBold
$closeButton.Location = New-Object System.Drawing.Point(600, ($buttonPanel.Bottom + 10))
$closeButton.Size = New-Object System.Drawing.Size(108, 30)
$closeButton.Add_Click({ $form.Close() })
$activityPanel.Controls.Add($closeButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = Get-ToolText -Key "progress.stop" -Culture $script:dashboardCulture
$stopButton.Font = $fontBold
$stopButton.Location = New-Object System.Drawing.Point(484, ($buttonPanel.Bottom + 10))
$stopButton.Size = New-Object System.Drawing.Size(108, 30)
$stopButton.Visible = $false
$stopButton.Enabled = $false
$stopButton.Add_Click({ Stop-ActiveTask })
$activityPanel.Controls.Add($stopButton)

$copyLogButton = New-Object System.Windows.Forms.Button
$copyLogButton.Text = Get-ToolText -Key "progress.copyAllLog" -Culture $script:dashboardCulture
$copyLogButton.Font = $fontSmall
$copyLogButton.Size = New-Object System.Drawing.Size(142, 26)
$copyLogButton.Add_Click({ Copy-AllToolLog })
$activityPanel.Controls.Add($copyLogButton)

$openReportFolderButton = New-Object System.Windows.Forms.Button
$openReportFolderButton.Text = Get-ToolText -Key "report.openFolder" -Culture $script:dashboardCulture
$openReportFolderButton.Font = $fontSmall
$openReportFolderButton.Size = New-Object System.Drawing.Size(166, 26)
$openReportFolderButton.Add_Click({ Open-ReportDirectory })
$activityPanel.Controls.Add($openReportFolderButton)

$progressCaption = New-Object System.Windows.Forms.Label
$progressCaption.Text = Get-ToolText -Key "progress.caption" -Culture $script:dashboardCulture
$progressCaption.Font = $fontBold
$progressCaption.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$progressCaption.Location = New-Object System.Drawing.Point(38, ($closeButton.Bottom + 5))
$progressCaption.Size = New-Object System.Drawing.Size(670, 18)
$activityPanel.Controls.Add($progressCaption)

$activityLabel = New-Object System.Windows.Forms.Label
$activityLabel.Text = ""
$activityLabel.Font = $fontSmall
$activityLabel.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$activityLabel.TextAlign = "MiddleLeft"
$activityLabel.AutoEllipsis = $true
$activityLabel.Location = New-Object System.Drawing.Point(38, ($progressCaption.Bottom + 2))
$activityLabel.Size = New-Object System.Drawing.Size(585, 20)
$activityPanel.Controls.Add($activityLabel)

$elapsedLabel = New-Object System.Windows.Forms.Label
$elapsedLabel.Text = ""
$elapsedLabel.Font = $fontSmall
$elapsedLabel.ForeColor = [System.Drawing.Color]::FromArgb(102, 112, 133)
$elapsedLabel.TextAlign = "MiddleRight"
$elapsedLabel.Location = New-Object System.Drawing.Point(623, ($progressCaption.Bottom + 2))
$elapsedLabel.Size = New-Object System.Drawing.Size(85, 20)
$activityPanel.Controls.Add($elapsedLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$progressBar.Location = New-Object System.Drawing.Point(38, ($activityLabel.Bottom + 1))
$progressBar.Size = New-Object System.Drawing.Size(670, 15)
$activityPanel.Controls.Add($progressBar)

$progressLog = New-Object System.Windows.Forms.TextBox
$progressLog.Multiline = $true
$progressLog.ReadOnly = $true
$progressLog.ScrollBars = "Vertical"
$progressLog.WordWrap = $true
$progressLog.Font = $fontSmall
$progressLog.BackColor = [System.Drawing.Color]::White
$progressLog.Location = New-Object System.Drawing.Point(38, ($progressBar.Bottom + 4))
$progressLog.Size = New-Object System.Drawing.Size(670, 62)
$activityPanel.Controls.Add($progressLog)

$activityLabel.Visible = $false
$elapsedLabel.Visible = $false
$progressBar.Visible = $false
$progressLog.Visible = $false

$form.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($progressLog.Bottom + 16))

$activeProcess = $null
$activeAction = ""
$activeTaskKind = ""
$activeModuleId = ""
$activeModuleInvocation = $null
$lastModuleResult = $null
$cleanupDecisionFile = ""
$cleanupResultFile = ""
$cleanupSelectionFile = ""
$cleanupRepairDecisionFile = ""
$cleanupRedactSensitive = $true
$cleanupAutoSafeMode = $false
$cleanupDryRunMode = $false
$cleanupScanScope = "All"
$cleanupScanSnapshot = $null
$cleanupPreviousSession = $null
$softwareCatalogUpdateResultFile = ""
$softwareCatalogRefreshPending = $false
$softwareCatalogBackgroundSync = $false
$applicationUpdateResultFile = ""
$availableApplicationUpdate = $null
$applicationUpdateProcess = $null
$applicationUpdateInvocation = $null
$applicationUpdateCheckPending = $false
$applicationUpdatePromptPending = $false
$applicationUpdateReminderPending = $false
$applicationUpdateReminderDueUtc = [DateTime]::MinValue
$applicationUpdateTaskObservedAfterDeferral = $false
$applicationUpdateDismissedForSession = $false
$applicationUpdateCancelledForOffline = $false
$applicationUpdateDialogVisible = $false
$applicationUpdateApplyStarted = $false
$backupScope = "All"
$restoreScope = "All"
$backupResultFile = ""
$restoreResultFile = ""
$oemDecisionFile = ""
$deepScanDecisionFile = ""
$forensicsDecisionFile = ""
$progressTick = 0
$progressPhase = 0
$taskStartedAt = $null
$lastProgressHeartbeat = 0
$taskStallWarningShown = $false
$taskProgressPhaseIndex = -1
$taskProgressTargetSeconds = 120
$script:processingTimelineForm = $null
$script:processingTimelineList = $null
$script:processingTimelineStatus = $null
$script:processingTimelineProgressBar = $null
$script:processingTimelineElapsed = $null
$script:processingTimelineStopButton = $null
$script:processingTimelineCloseButton = $null
$script:processingTimelineHeading = $null
$script:processingTimelineCapturing = $false
$script:currentTaskProgressEntries = New-Object System.Collections.Generic.List[object]
$buttons = New-Object System.Collections.ArrayList
$script:reportPresentationCache = @{}
$script:updatingMainLayout = $false
$script:hasTaskActivity = $false
$script:dashboardSection = "Overview"
$script:taskCancellationRequested = $false
$script:lastReportDirectory = $reportRoot
$script:lastReportPath = ""
$script:resultCenterState = $null
$script:executionEnvironmentWarningShown = $false
Write-DashboardStartupTrace "ShellControls.Ready"

$script:dashboardMenusInitialized = $false

$form.ResumeLayout($false)
Write-DashboardStartupTrace "Layout.Resumed"
Fit-MainWindowToWorkingArea
Write-DashboardStartupTrace "Window.Fitted"
Set-DashboardSection -Section "Overview"
Write-DashboardStartupTrace "Section.Ready"
Set-DashboardTheme -Mode $script:dashboardTheme -StartupFast
Write-DashboardStartupTrace "Theme.Ready"
$script:dashboardStartupLayoutPending = $false
Update-MainLayout
Write-DashboardStartupTrace "Layout.Ready"
$startupValidationTimer = New-Object System.Windows.Forms.Timer
$startupValidationTimer.Interval = 150
$script:dashboardStartupPhase = 0
$startupValidationTimer.Add_Tick({
    $startupValidationTimer.Stop()
    if ($script:dashboardStartupPhase -eq 0) {
        Initialize-DashboardMenus
        $script:dashboardStartupPhase = 1
        $startupValidationTimer.Interval = 75
        $startupValidationTimer.Start()
        return
    }
    Complete-DashboardStartupValidation
})
foreach ($button in $buttons) { $button.Enabled = $false }
$form.Add_Shown({
    Write-DashboardStartupTrace "Window.Shown"
    # DeviceDpi is authoritative only after the native window handle is shown.
    # Refit once on the message pump before the responsive layout pass so the
    # 150-200% canvas receives the physical pixels calculated above.
    [void]$form.BeginInvoke([System.Action]{ Fit-MainWindowToWorkingArea; Update-MainLayout })
    $startupValidationTimer.Start()
    Show-ExecutionEnvironmentWarning
    $updateTimer.Start()
    if (-not $script:offlineMode) { Request-OnlineSessionRefresh }
})
$form.Add_Resize({ Update-MainLayout })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    $script:progressTick++
    if ($script:activeProcess -and $script:taskStartedAt) {
        $elapsed = (Get-Date) - $script:taskStartedAt
        $elapsedSeconds = [int][Math]::Floor($elapsed.TotalSeconds)
        $elapsedLabel.Text = "{0:00}:{1:00}" -f [Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
        Update-TaskProgressDisplay -Elapsed $elapsed
        if ($elapsedSeconds -ge 120 -and -not $script:taskStallWarningShown) {
            $script:taskStallWarningShown = $true
            $slowMessage = Get-ToolText -Key "progress.slowTask" -Culture $script:dashboardCulture
            Write-ProgressLog $slowMessage
            [void](Write-ToolLog -Level "WARN" -Event "Action.Slow" -Message $slowMessage -Data ([ordered]@{
                TaskKind = $script:activeTaskKind
                ModuleId = $script:activeModuleId
                ElapsedSeconds = $elapsedSeconds
            }))
        }
    }
    if ($script:activeProcess -and $script:activeProcess.HasExited) {
        $timer.Stop()
        $exitCode = $script:activeProcess.ExitCode
        $finishedTaskKind = $script:activeTaskKind
        $finishedAction = $script:activeAction
        $finishedModuleId = $script:activeModuleId
        $finishedModuleInvocation = $script:activeModuleInvocation
        $wasCancellationRequested = [bool]$script:taskCancellationRequested
        $processDurationMs = if ($script:taskStartedAt) { [long][Math]::Round(((Get-Date) - $script:taskStartedAt).TotalMilliseconds) } else { $null }
        if ($finishedModuleInvocation) {
            $moduleResult = Complete-ToolModuleInvocation -Invocation $finishedModuleInvocation -ExitCode $exitCode -Summary $finishedAction
            $moduleValidation = Test-ToolModuleResult -Result $moduleResult
            if (-not $moduleValidation.Valid) {
                [void](Write-ToolLog -Level "ERROR" -Event "Module.ResultInvalid" -Message ($moduleValidation.Errors -join "; ") -Data ([ordered]@{ ModuleId=$finishedModuleId; ExitCode=[int]$exitCode }))
            } else {
                $script:lastModuleResult = $moduleResult
                [void](Write-ToolLog -Level $(if ($moduleResult.Status -eq "Completed") { "AUDIT" } else { "WARN" }) -Event "Module.Complete" -Message $finishedAction -DurationMs $moduleResult.DurationMs -Data ([ordered]@{
                    ModuleId = $moduleResult.ModuleId
                    InvocationId = $moduleResult.InvocationId
                    Status = $moduleResult.Status
                    ExitCode = [int]$moduleResult.ExitCode
                }))
                $completedDescriptor = Get-ToolModuleDescriptor -ModuleId $moduleResult.ModuleId
                [void](Write-LicenseTimelineEventSafe -EventType "ModuleCompleted" -Source "GUI" -IsChange:$false -Data ([ordered]@{
                    ModuleId=$moduleResult.ModuleId; InvocationId=$moduleResult.InvocationId; Status=$moduleResult.Status
                    ExitCode=[int]$moduleResult.ExitCode; DurationMs=[long]$moduleResult.DurationMs
                    ChangeCapable=[bool]($completedDescriptor -and $completedDescriptor.AccessMode -eq "SystemChange")
                }))
            }
        }
        [void](Write-ToolLog -Level $(if ($exitCode -eq 0) { "INFO" } else { "WARN" }) -Event "ChildProcess.Exit" -Message $finishedAction -DurationMs $processDurationMs -Data ([ordered]@{
            TaskKind = $finishedTaskKind
            ModuleId = $finishedModuleId
            ExitCode = [int]$exitCode
        }))
        $script:activeProcess = $null
        $script:activeTaskKind = ""
        $script:activeModuleId = ""
        $script:activeModuleInvocation = $null
        if ($script:applicationUpdateReminderPending -and -not [string]::IsNullOrWhiteSpace($finishedTaskKind)) {
            $script:applicationUpdateTaskObservedAfterDeferral = $true
        }
        if ($wasCancellationRequested) {
            $script:taskCancellationRequested = $false
            Set-ButtonsEnabled $true
            $status.Text = Get-ToolText -Key "progress.cancelled" -Culture $script:dashboardCulture -FormatArguments @($finishedAction)
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog $status.Text
            [void](Write-ToolLog -Level "WARN" -Event "Action.Cancelled" -Message $finishedAction -DurationMs $processDurationMs -Data ([ordered]@{
                TaskKind = $finishedTaskKind
                ModuleId = $finishedModuleId
                ExitCode = [int]$exitCode
            }))
            Stop-ProgressDisplay $status.Text
            return
        }
        if ($finishedTaskKind -eq "SoftwareCatalogUpdate") {
            Complete-SoftwareCatalogOnlineUpdate
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupScan") {
            Complete-CleanupScan
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupRemediate") {
            Complete-CleanupRemediation $false
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupDeep") {
            Complete-CleanupRemediation $true
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupScanRepair") {
            Complete-ScanSourceRepair
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupBackup") {
            Complete-CleanupBackup
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupRestore") {
            Complete-CleanupRestore
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "OemInspect") {
            Complete-OemInspect
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "OemApply") {
            Set-ButtonsEnabled $true
            if ($script:oemDecisionFile -and (Test-Path -LiteralPath $script:oemDecisionFile -PathType Leaf)) {
                try {
                    $oemApplyResult = Get-Content -LiteralPath $script:oemDecisionFile -Raw | ConvertFrom-Json
                    if ($oemApplyResult.ReportPath -and (Test-Path -LiteralPath $oemApplyResult.ReportPath -PathType Leaf)) {
                        [void](Open-ToolReportPresentation -SourcePath ([string]$oemApplyResult.ReportPath) -Title (Get-DashboardText "oem.report.applyTitle") -FilePrefix "BaoCao_KhoiPhuc_Key_OEM")
                    }
                } catch {
                    Write-ProgressLog (Get-DashboardText "oem.apply.reportOpenFailed" @($_.Exception.Message))
                } finally {
                    Remove-Item -LiteralPath $script:oemDecisionFile -Force -ErrorAction SilentlyContinue
                    $script:oemDecisionFile = ""
                }
            }
            [void](Write-LicenseTimelineEventSafe -EventType "OemLicenseApplyCompleted" -Source "GUI" -IsChange:([bool]($exitCode -in @(0, 23))) -Data ([ordered]@{
                ExitCode=[int]$exitCode
                KeyAccepted=[bool]($exitCode -in @(0, 23))
                ActivationConfirmed=[bool]($exitCode -eq 0)
                ProductKeyStoredInTimeline=$false
            }))
            if ($exitCode -eq 0) {
                [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "oem.apply.successMessage"), (Get-DashboardText "oem.apply.successTitle"), "OK", "Information") | Out-Null
                $status.Text = Get-DashboardText "oem.apply.successStatus"
                Write-ProgressLog (Get-DashboardText "oem.apply.successLog")
                $status.ForeColor = [System.Drawing.Color]::DarkGreen
            } elseif ($exitCode -eq 22) {
                [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "oem.apply.mismatchMessage"), (Get-DashboardText "oem.apply.mismatchTitle"), "OK", "Warning") | Out-Null
                $status.Text = Get-DashboardText "oem.apply.mismatchStatus"
                Write-ProgressLog (Get-DashboardText "oem.apply.mismatchLog")
                $status.ForeColor = [System.Drawing.Color]::DarkOrange
            } elseif ($exitCode -eq 23) {
                [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "oem.apply.pendingMessage"), (Get-DashboardText "oem.apply.pendingTitle"), "OK", "Warning") | Out-Null
                $status.Text = Get-DashboardText "oem.apply.pendingStatus"
                Write-ProgressLog (Get-DashboardText "oem.apply.pendingLog")
                $status.ForeColor = [System.Drawing.Color]::DarkOrange
            } else {
                $status.Text = Get-DashboardText "oem.apply.failedStatus" @($exitCode)
                Write-ProgressLog (Get-DashboardText "oem.apply.failedLog" @($exitCode))
                $status.ForeColor = [System.Drawing.Color]::DarkRed
            }
            Stop-ProgressDisplay $status.Text
            return
        }
        if ($finishedTaskKind -eq "DeepLicenseScan") {
            Complete-DeepLicenseScan
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "ForensicsScan") {
            Complete-ForensicsScan
            Stop-ProgressIfIdle
            return
        }
        Set-ButtonsEnabled $true
        if ($exitCode -eq 0) {
            $status.Text = Get-ToolText -Key "progress.completed" -Culture $script:dashboardCulture -FormatArguments @($finishedAction)
            Write-ProgressLog $status.Text
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
            if ($finishedTaskKind -eq "Report") {
                [void]$form.BeginInvoke([System.Action]{ $script:resultCenterState = $null; Update-ResultActionCard -HeaderOnly })
            }
        } else {
            $status.Text = Get-ToolText -Key "progress.failed" -Culture $script:dashboardCulture -FormatArguments @($finishedAction, $exitCode)
            Write-ProgressLog $status.Text
            $status.ForeColor = [System.Drawing.Color]::DarkRed
        }
        Stop-ProgressDisplay $status.Text
    }
})

$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 1000
$updateTimer.Add_Tick({
    if ($script:applicationUpdateProcess -and $script:applicationUpdateProcess.HasExited) {
        Complete-ApplicationUpdateCheck
    }
    Invoke-PendingOnlineSessionWork
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:activeProcess -and -not $script:activeProcess.HasExited) {
        [void](Write-ToolLog -Level "WARN" -Event "Application.CloseBlocked" -Message (Get-DashboardText "app.closeBlockedLog") -Data ([ordered]@{ TaskKind=$script:activeTaskKind; ModuleId=$script:activeModuleId; Action=$script:activeAction }))
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "app.closeBlocked" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "app.closeBlockedTitle" -Culture $script:dashboardCulture), "OK", "Warning") | Out-Null
        $eventArgs.Cancel = $true
    } else {
        [void](Write-ToolLog -Level "INFO" -Event "Application.Stop" -Message (Get-DashboardText "app.closedLog"))
    }
})

$form.Add_FormClosed({
    if ($startupValidationTimer) {
        $startupValidationTimer.Stop()
        $startupValidationTimer.Dispose()
    }
    if ($updateTimer) {
        $updateTimer.Stop()
        $updateTimer.Dispose()
    }
    if ($script:applicationUpdateProcess -and -not $script:applicationUpdateProcess.HasExited) {
        try { $script:applicationUpdateProcess.Kill() } catch {}
    }
    Remove-ApplicationUpdateResultFile
    foreach ($iconImage in @($dashboardIconImages)) {
        if ($iconImage) { $iconImage.Dispose() }
    }
    $dashboardIconImages.Clear()
})

Write-DashboardStartupTrace "ShowDialog.Starting"
[void]$form.ShowDialog()

