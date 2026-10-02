param(
    [string]$OutputDir = "",
    [string[]]$ApprovedKmsServers = @(),
    [string]$ApprovedKmsServerFile = "",
    [switch]$TreatUnapprovedKmsAsNonCompliant,
    [switch]$Remediate,
    [switch]$DeepClean,
    [switch]$DryRun,
    [switch]$NoRestorePoint,
    [switch]$RedactSensitive,
    [string]$DecisionFile = "",
    [string]$SelectionFile = "",
    [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")]
    [string]$ScanScope = "All",
    [switch]$SkipDeepSoftwareScan,
    [ValidateRange(15, 900)][int]$DeepSoftwareScanTimeoutSeconds = 180,
    [ValidateRange(20, 10000)][int]$DeepSoftwareScanMaximumSignatureChecks = 1400,
    [ValidateRange(20, 10000)][int]$DeepSoftwareScanMaximumHashChecks = 1000,
    [switch]$RepairScanSources,
    [switch]$BridgeEnvironmentProbe,
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN"
)

if ($BridgeEnvironmentProbe) {
    $bridgeInvocationId = [guid]::Empty
    $bridgeContextValid = $env:TOOL_SECURE_LAUNCH -eq '1' -and
        -not [string]::IsNullOrWhiteSpace($env:TOOL_SECURE_RUNTIME_DIR) -and
        [string]$env:TOOL_MODULE_ID -in @('cleanup.scan','cleanup.repair') -and
        [guid]::TryParse([string]$env:TOOL_MODULE_INVOCATION_ID, [ref]$bridgeInvocationId) -and
        $bridgeInvocationId -ne [guid]::Empty
    if ($bridgeContextValid) { exit 0 }
    exit 23
}

if ($DryRun) {
    $Remediate = $true
    $DeepClean = $true
}

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$reportSchemaHelper = Join-Path $PSScriptRoot "Tool-ReportSchema.ps1"
$safetyPolicyHelper = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
$scanOptimizationHelper = Join-Path $PSScriptRoot "Tool-ScanOptimization.ps1"
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
$softwareInventoryHelper = Join-Path $PSScriptRoot "Tool-SoftwareInventory.ps1"
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { Write-Host "[common.missingDependency] Tool-Localization.ps1"; exit 12 }
. $localizationHelper
$env:TOOL_UI_CULTURE = $Culture
# Load function libraries before executing entrypoint statements. Keep these
# imports explicit so direct CLI use behaves exactly like packaged execution.
. (Join-Path $PSScriptRoot 'Cleanup-Platform.ps1')
. (Join-Path $PSScriptRoot 'Cleanup-Detection.ps1')
. (Join-Path $PSScriptRoot 'Cleanup-Evidence.ps1')
. (Join-Path $PSScriptRoot 'Cleanup-Remediation.ps1')

if ($PSVersionTable.PSVersion.Major -lt 3) { Write-Host (Get-CleanupText "report.bootstrap.powerShellRequired"); exit 10 }
try {
    foreach ($requiredPath in @($runtimeHelper, $reportSchemaHelper, $safetyPolicyHelper, $scanOptimizationHelper, $softwareInventoryHelper)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw (Get-CleanupText "common.missingDependency" @([IO.Path]::GetFileName($requiredPath))) }
    }
    . $runtimeHelper
    . $reportSchemaHelper
    . $safetyPolicyHelper
    . $scanOptimizationHelper
    . $softwareInventoryHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
    $nativeScPath = Get-ToolNativeSystemPath "sc.exe"
    $nativeRegPath = Get-ToolNativeSystemPath "reg.exe"
    $nativeCertutilPath = Get-ToolNativeSystemPath "certutil.exe"
    $nativeSfcPath = Get-ToolNativeSystemPath "sfc.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }

$ErrorActionPreference = "Continue"
$releaseVersion = "5.0"
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "BaoCao-VietLicenSure" }
if ([string]::IsNullOrWhiteSpace($ApprovedKmsServerFile)) { $ApprovedKmsServerFile = Join-Path $PSScriptRoot "approved-kms-servers.txt" }
$script:StrictActivatorPattern = "(?i)(\bkmspico\b|\bkmsauto(?:s|[\s._-]*(?:net|lite|portable|plus|\+\+))?\b|\bauto[\s._-]*kms\b|\bautokms\b|\bkms[\s._-]*38\b|\bkms[\s._-]*vl(?:[\s._-]*all)?\b|\bkms-r\b|\baact(?:[\s._-]*(?:network|portable))?\b|\bsppextcomobj(?:patcher|hook)\b|\bspp[\s._-]*(?:hook|patcher)\b|\bmicrosoft[\s_-]+toolkit\b|\bhwidgen\b|\bmassgrave\b|\bmas[\s._-]*(?:aio|all[\s._-]*in[\s._-]*one|activat(?:ion|or)|hwid|kms|ohook|tsforge)\b|\bpmas(?:[\s._-]*(?:aio|all[\s._-]*in[\s._-]*one|activat(?:ion|or)|hwid|kms|ohook|tsforge))?\b|\bmicrosoft[\s._-]*activation[\s._-]*scripts?\b|\bactivation[\s._-]*program[\s._-]*(?:v(?:ersion)?[\s._-]*)?1(?:\.|\s+|[_-])17\b|\btsforge\b|\bohook\b)"
$script:StrictActivationCommandPattern = '(?i)(?<![a-z0-9.-])(?:https?://)?erturk-dev\.netlify\.app/run(?:[/?#][^\s''"|]*)?(?![a-z0-9._-])'
$script:ThirdPartyAdobeActivatorPattern = "(?i)(\badobe[\s._-]*genp\b|\bccmaker\b|\bamtlib[\s._-]*(?:patch|emulator)\b|\badobe.{0,24}\b(?:patcher|activator|crack)\b|\b(?:patcher|activator|crack).{0,24}\badobe\b)"
$script:ThirdPartyAutodeskActivatorPattern = "(?i)(\bxf[\s._-]*adsk\b|\bx[\s._-]*force.{0,20}\b(?:autodesk|adsk)\b|\b(?:autodesk|adsk).{0,24}\b(?:license[\s._-]*patch|patcher|activator|crack)\b|\b(?:patcher|activator|crack).{0,24}\b(?:autodesk|adsk)\b)"
try { Add-Type -AssemblyName System.Security -ErrorAction Stop }
catch { Write-Host (Get-CleanupText "backupReport.securityAssemblyFailed"); exit 11 }
$script:SensitiveKmsHosts = @()
$script:ScanWarnings = New-Object System.Collections.Generic.List[string]
$script:CimCache = @{}
$script:ScheduledTaskRecordsCache = $null
$script:WindowsLicenseSourceNote = ""
$script:OfficeLicenseProbe = $null

if ($RepairScanSources) {
    Ensure-Dir $OutputDir
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $reportComputer = if ($RedactSensitive) { Get-CleanupText "report.file.redactedToken" } else { $env:COMPUTERNAME }
    $repairReportPath = Join-Path $OutputDir ((Get-CleanupText "cleanupReport.file.repairPrefix") + "_${reportComputer}_$stamp.txt")
    $repair = Invoke-ScanSourceRepair
    $repair.ReportPath = [string]$repairReportPath
    $repairLines = New-Object System.Collections.Generic.List[string]
    $yes = Get-CleanupText "common.yes"
    $no = Get-CleanupText "common.no"
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.title" @($releaseVersion)))
    $repairLines.Add((Get-CleanupText "cleanupReport.report.time" @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))))
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.recheckPassed" @($(if ($repair.RecheckPassed) { $yes } else { $no }))))
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.startupChanged" @($(if ($repair.StartupTypeChanged) { $yes } else { $no }))))
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.rollbackApplied" @($(if ($repair.RollbackApplied) { $yes } else { $no }))))
    $repairLines.Add("")
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.checks"))
    foreach ($check in @($repair.Checks)) { $repairLines.Add("- [$($check.Status)] $($check.Name): $($check.Detail)") }
    $repairLines.Add("")
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.actions"))
    foreach ($action in @($repair.Actions)) { $repairLines.Add("- $action") }
    $repairLines.Add("")
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.serviceStates"))
    foreach ($before in @($repair.ServiceStateBefore)) {
        $after = @($repair.ServiceStateAfter | Where-Object { $_.Name -eq $before.Name } | Select-Object -First 1)
        $afterText = if ($after.Count -gt 0) { "$($after[0].Status), StartupType=$($after[0].StartMode)" } else { Get-CleanupText "cleanupReport.value.unreadable" }
        $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.serviceState" @($before.Name, $before.Status, $before.StartMode, $afterText)))
    }
    $repairLines.Add("")
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.guidance"))
    foreach ($step in @($repair.HandlingGuidance)) { $repairLines.Add("- $step") }
    @($repairLines | ForEach-Object { Protect-CleanupReportText $_ }) | Set-Content -LiteralPath $repairReportPath -Encoding UTF8
    Write-DecisionData -Path $DecisionFile -Data $repair
    Write-Host (Get-CleanupText "cleanupReport.output.repairReport" @($repairReportPath))
    if ($repair.RecheckPassed) { exit 0 }
    exit 3
}

Import-ApprovedKmsServers
$approvedKmsConfig = Get-ApprovedKmsConfiguration
Ensure-Dir $OutputDir
$stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$reportComputer = if ($RedactSensitive) { Get-CleanupText "report.file.redactedToken" } else { $env:COMPUTERNAME }
$reportPath = Join-Path $OutputDir ((Get-CleanupText "cleanupReport.file.cleanupPrefix") + "_${reportComputer}_$stamp.txt")

$script:WindowsLicenseSourceNote = ""
$includeWindowsScan = Test-CleanupScanScopeIncludes -Scope $ScanScope -Component 'Windows'
$includeOfficeScan = Test-CleanupScanScopeIncludes -Scope $ScanScope -Component 'Office'
$includeWindowsOfficeScan = [bool]($includeWindowsScan -or $includeOfficeScan)
$includeThirdPartyScan = Test-CleanupScanScopeIncludes -Scope $ScanScope -Component 'ThirdParty'
$deepSoftwareScanEnabled = [bool]($includeThirdPartyScan -and -not $SkipDeepSoftwareScan)
$products = @($(if ($includeWindowsScan) { Get-WindowsLicenseProducts }))
$findings = @($(if ($includeWindowsOfficeScan) { Get-ActivatorFindings }))
$officeLicenseEntries = @($(if ($includeOfficeScan) { Get-OfficeLicenseEntries }))
$officeKmsEntries = @($(if ($includeOfficeScan) { Get-OfficeKmsEntries -LicenseEntries $officeLicenseEntries }))
$installedApplications = @($(if ($includeThirdPartyScan) { Get-InstalledSoftwareInventory }))
$softwareCatalog = if ($includeThirdPartyScan) { Get-ToolSoftwareLicenseCatalog -PreferCache } else { $null }
$thirdPartyEvidence = @($(if ($includeThirdPartyScan) { Get-ThirdPartyStrongEvidence -Applications $installedApplications -Catalog $softwareCatalog }))
$thirdPartyApplications = @($(if ($includeThirdPartyScan) {
    Get-ToolSoftwareAssessments `
        -Applications @($installedApplications | Where-Object {
            -not ([bool]$_.IsMicrosoft -and [string]$_.Name -match '(?i)\bWindows\b|\bOffice\b|\bMicrosoft\s*365\b')
        }) `
        -Catalog $softwareCatalog -ExternalEvidence $thirdPartyEvidence -DeepScan:$deepSoftwareScanEnabled `
        -DeepScanMaximumDurationSeconds $DeepSoftwareScanTimeoutSeconds `
        -DeepScanMaximumSignatureChecks $DeepSoftwareScanMaximumSignatureChecks `
        -DeepScanMaximumHashChecks $DeepSoftwareScanMaximumHashChecks
}))
$softwareDeepScanMetadata = Get-ToolSoftwareLastDeepScanMetadata
$thirdPartyCandidates = @(Get-ThirdPartyLicenseCandidates -Applications $thirdPartyApplications -Evidence $thirdPartyEvidence)
Connect-ThirdPartyApplicationsToCandidates -Applications $thirdPartyApplications -Candidates $thirdPartyCandidates
$script:SensitiveKmsHosts = @(
    @($ApprovedKmsServers)
    @($approvedKmsConfig.Valid)
    @($products | ForEach-Object { [string]$_.KeyManagementServiceMachine })
    @($officeKmsEntries | ForEach-Object { [string]$_.Server })
) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique
$history = @($(if ($includeWindowsOfficeScan) { Get-InvalidActivationHistory }))
$configurationResidues = @($(if ($includeWindowsOfficeScan) {
    Get-ActivationConfigurationResidues | Where-Object { Test-CleanupRecordMatchesScope -Record $_ -Scope $ScanScope }
}))
$unapprovedOfficeKmsEntries = @($officeKmsEntries | Where-Object { -not (Test-ApprovedKms ([string]$_.Server)) })
$decision = if ($includeWindowsOfficeScan) { Get-ComplianceDecision -Products $products -Findings $findings } else {
    [pscustomobject]@{
        DecisionCode='ThirdPartyInventory'; Decision=(Get-CleanupText 'cleanupReport.thirdParty.decision')
        Reason=(Get-CleanupText 'cleanupReport.thirdParty.reason' @(0)); ShouldRemediate=$false
    }
}

$thirdPartyCandidateCount = [int]$thirdPartyCandidates.Count
$thirdPartyStandaloneFindingCount = [int]@($thirdPartyCandidates | Where-Object {
    @($_.ApplicationIds).Count -eq 0 -and
    @($_.PlanItems | Where-Object { [string]$_.Type -eq 'File' -and [string]$_.Kind -eq 'ThirdPartyUnauthorizedArtifact' }).Count -gt 0
}).Count
$thirdPartyRemediationFindingCount = [int](@($thirdPartyApplications | Where-Object {
    $_.PSObject.Properties['CleanupFinding'] -and [bool]$_.CleanupFinding
}).Count + $thirdPartyStandaloneFindingCount)
if ($thirdPartyRemediationFindingCount -gt 0 -and -not [bool]$decision.ShouldRemediate) {
    $decision.ShouldRemediate = $true
    $decision.DecisionCode = 'ThirdPartyTechnicalEvidence'
    $decision.Decision = Get-CleanupText "cleanupReport.thirdParty.decision"
    $decision.Reason = Get-CleanupText "cleanupReport.thirdParty.reason" @($thirdPartyRemediationFindingCount)
}
$protectedLicense = if ($includeWindowsScan) { Get-ProtectedLicenseInfo -Products $products } else {
    [pscustomobject]@{ Protected=$false; Channel=(Get-CleanupText 'common.unknown'); Reason=(Get-CleanupText 'cleanupReport.protected.none') }
}
$activeLicensedProduct = $products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
$activeWindowsChannel = if ($activeLicensedProduct) { Get-LicenseChannel $activeLicensedProduct } else { Get-CleanupText "common.unknown" }
$activeApprovedKms = [bool]($activeWindowsChannel -eq "KMS" -and (Test-ApprovedKms ([string]$activeLicensedProduct.KeyManagementServiceMachine)))
$protectedActiveChannel = [bool]($activeWindowsChannel -in @("OEM", "Retail", "MAK") -or $activeApprovedKms)
$unapprovedWindowsKmsProducts = @($products | Where-Object {
    (Get-LicenseChannel $_) -eq "KMS" -and -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine))
})
$unapprovedWindowsKms = [bool]($unapprovedWindowsKmsProducts.Count -gt 0)
$allCleanupItems = @(Get-AllCleanupCandidates -Products $products -Findings $findings -OfficeEntries $officeKmsEntries -ThirdPartyCandidates $thirdPartyCandidates)
$cleanupItems = @(Get-ScopedCleanupCandidates -CleanupItems $allCleanupItems -Scope $ScanScope)
$scanSnapshot = New-CleanupScanSnapshot -Candidates $cleanupItems -Scope $ScanScope
$windowsOfficeCleanupCount = [int]@($cleanupItems | Where-Object { [string]$_.Type -ne 'Application' }).Count
$crackDetected = [bool]($windowsOfficeCleanupCount -gt 0 -or $thirdPartyRemediationFindingCount -gt 0)
$removeWindowsLicense = [bool](@($cleanupItems | Where-Object { [string]$_.Kind -in @('WindowsKmsLicense','WindowsNonGenuineLicense') }).Count -gt 0)
$unapprovedWindowsConfigResidues = @($configurationResidues | Where-Object {
    $_.Type -eq "KMSConfig" -and $_.Location -match "Windows NT\\CurrentVersion\\SoftwareProtectionPlatform"
})
$cleanupWindowsKmsConfiguration = [bool]($unapprovedWindowsKms -or $unapprovedWindowsConfigResidues.Count -gt 0)
$verification = Get-CleanupVerification -Products $products -Findings $findings -OfficeEntries $officeKmsEntries -History $history -Scope $ScanScope
$verification = Add-ThirdPartyVerification -Verification $verification -ThirdPartyCandidates $thirdPartyCandidates -ThirdPartyApplications $thirdPartyApplications -Included:$includeThirdPartyScan
$scopeReadyForOriginalState = Test-CleanupScopeReady -Verification $verification -Scope $ScanScope
$officialLicensePostCheck = Get-OfficialLicensePostCheck -Verification $verification -Products $products `
    -OfficeLicenseEntries $officeLicenseEntries -OfficeProbe $script:OfficeLicenseProbe `
    -ThirdPartyApplications $thirdPartyApplications -Scope $ScanScope
$initialPostVerificationItems = @(Get-CleanupPostVerificationItems -CleanupItems $cleanupItems -Verification $verification)
$initialPostVerificationSuggestedIds = @($initialPostVerificationItems | Where-Object {
    [bool]$_.SuggestedForNextStep -and -not [string]::IsNullOrWhiteSpace([string]$_.CandidateId)
} | ForEach-Object { [string]$_.CandidateId } | Select-Object -Unique)
$initialPostVerificationOutcome = Get-CleanupPostVerificationOutcome -PostVerificationItems $initialPostVerificationItems `
    -ScopeReady:$scopeReadyForOriginalState -OfficiallyLicensed:([bool]$officialLicensePostCheck.OfficiallyLicensed)
$decisionData = New-ToolReportEnvelope -ReportKind "CleanupCompliance" -ToolVersion "5.0" -Data ([ordered]@{
    ScanScope = $ScanScope
    CrackDetected = $crackDetected
    ProtectedLicense = [bool]$protectedLicense.Protected
    ProtectedChannel = [string]$protectedLicense.Channel
    ProtectedReason = [string]$protectedLicense.Reason
    ActiveWindowsChannel = [string]$activeWindowsChannel
    RemoveWindowsLicense = $removeWindowsLicense
    ActivatorFindingCount = [int]$findings.Count
    HistoryFindingCount = [int]$history.Count
    ConfigurationResidueCount = [int]$configurationResidues.Count
    WindowsKmsCount = [int]$unapprovedWindowsKmsProducts.Count
    OfficeKmsCount = [int]$unapprovedOfficeKmsEntries.Count
    OfficeProbe = $script:OfficeLicenseProbe
    InstalledApplicationCount = [int]$installedApplications.Count
    ThirdPartyApplicationCount = [int]$thirdPartyApplications.Count
    ThirdPartyEvidenceCount = [int]$thirdPartyEvidence.Count
    ThirdPartyCandidateCount = [int]$thirdPartyCandidateCount
    ThirdPartyAutoEligibleCount = [int]@($thirdPartyCandidates | Where-Object { [bool]$_.AutoEligible }).Count
    ThirdPartyNeedsReviewCount = [int]@($thirdPartyApplications | Where-Object { [bool]$_.NeedsReview }).Count
    ThirdPartyRemediationFindingCount = [int]$verification.ThirdPartyRemediationFindingCount
    ThirdPartyNonGenuineCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'NonGenuine' }).Count
    ThirdPartySuspiciousCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'Suspicious' }).Count
    ThirdPartyUnverifiedCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -in @('Unverified','TrialOrUnverified') }).Count
    SoftwareCatalogSource = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogSource } else { 'Unavailable' })
    SoftwareCatalogVersion = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogVersion } else { '' })
    SoftwareCatalogRuleCount = $(if ($softwareCatalog) { [int]@($softwareCatalog.Products).Count } else { 0 })
    DeepSoftwareScanEnabled = [bool]$softwareDeepScanMetadata.Enabled
    DeepSoftwareScanComplete = [bool]$softwareDeepScanMetadata.Complete
    DeepSoftwareScanAdministrator = [bool]$softwareDeepScanMetadata.IsAdministrator
    DeepSoftwareScanApplicationsScanned = [int]$softwareDeepScanMetadata.ApplicationsScanned
    DeepSoftwareScanApplicationsSkipped = [int]$softwareDeepScanMetadata.ApplicationsSkipped
    DeepSoftwareScanUniqueRoots = [int]$softwareDeepScanMetadata.UniqueRootsScanned
    DeepSoftwareScanRootCacheHits = [int]$softwareDeepScanMetadata.RootCacheHits
    DeepSoftwareScanTotalEntries = [int]$softwareDeepScanMetadata.TotalEntries
    DeepSoftwareScanRelevantFiles = [int]$softwareDeepScanMetadata.RelevantFiles
    DeepSoftwareScanSignatureChecks = [int]$softwareDeepScanMetadata.SignatureChecks
    DeepSoftwareScanHashChecks = [int]$softwareDeepScanMetadata.HashChecks
    DeepSoftwareScanEvidenceCount = [int]$softwareDeepScanMetadata.EvidenceCount
    DeepSoftwareScanDurationMilliseconds = [int]$softwareDeepScanMetadata.DurationMilliseconds
    DeepSoftwareScanTimeLimitReached = [bool]$softwareDeepScanMetadata.TimeLimitReached
    DeepSoftwareScanEntryLimitReached = [bool]$softwareDeepScanMetadata.EntryLimitReached
    DeepSoftwareScanSignatureLimitReached = [bool]$softwareDeepScanMetadata.SignatureLimitReached
    DeepSoftwareScanHashLimitReached = [bool]$softwareDeepScanMetadata.HashLimitReached
    DeepSoftwareScanAccessWarningCount = [int]$softwareDeepScanMetadata.AccessWarningCount
    ThirdPartyApplications = @($thirdPartyApplications)
    ThirdPartyEvidence = @($thirdPartyEvidence)
    ThirdPartyCandidates = @($thirdPartyCandidates)
    ApprovedOfficeKmsCount = [int]($officeKmsEntries.Count - $unapprovedOfficeKmsEntries.Count)
    ApprovedKmsServerFile = [string]$approvedKmsConfig.Path
    ApprovedKmsServerCount = [int]$approvedKmsConfig.Valid.Count
    InvalidApprovedKmsCount = [int]$approvedKmsConfig.Invalid.Count
    ApprovedKmsConfigWarning = [string]$approvedKmsConfig.Warning
    DecisionCode = [string]$decision.DecisionCode
    Decision = [string]$decision.Decision
    Reason = [string]$decision.Reason
    ReadyForOfficialActivation = [bool]$verification.ReadyForOfficialActivation
    ScopeReadyForOriginalState = [bool]$scopeReadyForOriginalState
    OfficiallyLicensed = [bool]$officialLicensePostCheck.OfficiallyLicensed
    OfficialLicenseStateCode = [string]$officialLicensePostCheck.StateCode
    OfficialLicensePostCheck = $officialLicensePostCheck
    ReadinessReviewCount = [int]$verification.ReadinessReviewCount
    ScanWarningCount = [int]$verification.ScanWarningCount
    ScanWarnings = $verification.ScanWarnings
    ReadinessChecks = $verification.ReadinessChecks
    DeepCleanupApplied = $false
    SystemChangeApplied = $false
    SystemChangeCount = 0
    ThirdPartyExecutionResults = @()
    RemediationStates = @($cleanupItems | ForEach-Object { $_.RemediationState })
    DryRunRequested = [bool]$DryRun
    SimulationOnly = [bool]$DryRun
    NoSystemChangesApplied = $true
    PlannedActionCount = 0
    PlannedActions = @()
    SelectedCleanupIds = @()
    SelectionAccepted = $false
    SelectionErrorCode = 'NotRequested'
    SelectionErrorDetail = ''
    UnknownSelectedCleanupIdCount = 0
    BackupWouldBeCreated = $false
    CleanupItems = $cleanupItems
    ScanSnapshot = $scanSnapshot
    SelectionRequired = [bool]($cleanupItems.Count -gt 0)
    SelectedCleanupItemCount = 0
    BackupDirectory = ""
    CleanupConclusion = [string]$verification.Conclusion
    PostVerification = [pscustomobject][ordered]@{ FreshScan=$true; PerformedAtUtc=[DateTime]::UtcNow.ToString('o'); Outcome=$initialPostVerificationOutcome; RemainingItemCount=[int]$initialPostVerificationItems.Count; ScanWarningCount=[int]$verification.ScanWarningCount }
    PostVerificationItems = @($initialPostVerificationItems)
    PostVerificationSuggestedIds = @($initialPostVerificationSuggestedIds)
    PostVerificationOutcome = $initialPostVerificationOutcome
    HandlingGuidance = $verification.HandlingGuidance
    NextActions = @(Get-CleanupNextActions -Verification $verification -CleanupItems $cleanupItems -ProtectedLicense ([bool]$protectedLicense.Protected) -OfficialLicensePostCheck $officialLicensePostCheck -Scope $ScanScope)
    ScopeNote = [string]$verification.ScopeNote
    ReportPath = [string]$reportPath
})
Write-DecisionData -Path $DecisionFile -Data $decisionData
$actions = New-Object System.Collections.Generic.List[string]
$script:SelectionAccepted = $false
$script:SelectionErrorCode = $(if ($Remediate -and $DeepClean) { 'SelectionNotRead' } else { 'NotRequested' })
$script:SelectionErrorDetail = ''
$selectedCleanupIds = @($(if ($Remediate -and $DeepClean) { Get-SelectedCleanupIds }))
$knownCleanupIdSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($cleanupItem in @($cleanupItems)) { [void]$knownCleanupIdSet.Add(([string]$cleanupItem.Id).ToLowerInvariant()) }
$unknownSelectedCleanupIds = @($selectedCleanupIds | Where-Object { -not $knownCleanupIdSet.Contains([string]$_) })
if ($script:SelectionAccepted -and $unknownSelectedCleanupIds.Count -gt 0) {
    $script:SelectionAccepted = $false
    $script:SelectionErrorCode = 'SelectionContainsUnknownIds'
    $script:SelectionErrorDetail = [string]$unknownSelectedCleanupIds.Count
    $selectedCleanupIds = @()
}
$changedSelectedCleanupIds = @()
if ($script:SelectionAccepted) {
    $changedSelectedCleanupIds = @($selectedCleanupIds | Where-Object {
        $selectedId = [string]$_
        $currentCandidate = @($cleanupItems | Where-Object { [string]::Equals([string]$_.Id, $selectedId, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        $currentCandidate.Count -ne 1 -or
        -not $currentCandidate[0].PSObject.Properties['SnapshotSha256'] -or
        -not [string]::Equals(
            [string]$currentCandidate[0].SnapshotSha256,
            [string]$script:SelectedCleanupSnapshots[$selectedId],
            [StringComparison]::OrdinalIgnoreCase)
    })
    if ($changedSelectedCleanupIds.Count -gt 0) {
        $script:SelectionAccepted = $false
        $script:SelectionErrorCode = 'SelectionSnapshotMismatch'
        $script:SelectionErrorDetail = [string]$changedSelectedCleanupIds.Count
        $selectedCleanupIds = @()
    }
}
$backupDirectory = ""
$plannedActions = @()
$thirdPartyExecutionResults = @()
$remediationStates = @()
$selectedCandidates = @()
$selectedThirdPartySnapshots = @()
$selectedThirdPartyResolvedCount = 0
$selectedThirdPartyRemainingCount = 0
$postVerificationItems = @($initialPostVerificationItems)
$postVerificationSuggestedIds = @($initialPostVerificationSuggestedIds)
$postVerificationOutcome = [string]$initialPostVerificationOutcome
$postVerificationTargetCandidateCount = [int]$initialPostVerificationItems.Count
$targetedThirdPartyCandidateCount = 0
$unselectedThirdPartyCandidateCount = [int]$verification.ThirdPartyCandidateCount
$postNextActions = @($decisionData.NextActions)
$fullScopeCleanupConclusion = [string]$verification.Conclusion
[int]$systemChangeCount = 0
$finalDecisionCode = [string]$decision.DecisionCode
$finalDecisionText = [string]$decision.Decision
$finalCleanupConclusion = [string]$verification.Conclusion
$finalReadyForOfficialActivation = [bool]$verification.ReadyForOfficialActivation
$finalScopeReadyForOriginalState = [bool]$scopeReadyForOriginalState

if ($Remediate) {
    if ($env:TOOL_SECURE_LAUNCH -ne "1" -or -not (Test-ProtectedDirectoryAcl -Path $PSScriptRoot -AllowCurrentUserForUserScope)) {
        $actions.Add((Get-CleanupText "cleanupReport.action.secureLaunchBlocked"))
    } elseif ([int]$verification.ScanWarningCount -gt 0) {
        $actions.Add((Get-CleanupText "cleanupReport.action.scanWarningBlocked"))
    } elseif (-not $DeepClean) {
        $actions.Add((Get-CleanupText "cleanupReport.action.selectionRequired" @($releaseVersion)))
    } elseif (-not $script:SelectionAccepted -or $selectedCleanupIds.Count -eq 0) {
        $actions.Add((Get-CleanupText "cleanupReport.action.selectionMissing"))
        if (-not [string]::IsNullOrWhiteSpace([string]$script:SelectionErrorCode)) {
            $actions.Add((Get-CleanupText 'cleanupReport.action.selectionRejectedDetail' @([string]$script:SelectionErrorCode)))
        }
    } elseif ($crackDetected -or ($script:SelectionAccepted -and $selectedCleanupIds.Count -gt 0)) {
        $selectedCandidates = @($cleanupItems | Where-Object { $selectedCleanupIds -contains ([string]$_.Id).ToLowerInvariant() })
        $remediationStates = @($selectedCandidates | Where-Object { $_.PSObject.Properties['RemediationState'] } | ForEach-Object {
            $_.RemediationState.PSObject.Copy()
        })
        $selectedThirdPartySnapshots = @($selectedCandidates | Where-Object {
            [string]$_.Type -eq 'Application' -and (Get-CleanupRecordComponentScope -Record $_) -eq 'ThirdParty'
        } | ForEach-Object {
            [pscustomobject][ordered]@{
                Id=[string]$_.Id; Type=[string]$_.Type; Kind=[string]$_.Kind; ComponentScope='ThirdParty'
                TargetId=[string]$_.TargetId; VendorScope=[string]$_.VendorScope
                Location=[string]$_.Location; Name=[string]$_.Name; ApplicationIds=@($_.ApplicationIds)
            }
        })
        $selectedWindowsActivationIds = @($selectedCandidates | Where-Object {
            [string]$_.Kind -in @('WindowsKmsLicense','WindowsNonGenuineLicense') -and -not [string]::IsNullOrWhiteSpace([string]$_.TargetId)
        } | ForEach-Object { [string]$_.TargetId })
        $windowsProductsToRemove = @($products | Where-Object {
            $selectedWindowsActivationIds -contains [string]$_.ID
        })
        $selectedOfficeTargetIds = @($selectedCandidates | Where-Object { $_.Kind -eq "OfficeKmsLicense" } | ForEach-Object { [string]$_.TargetId } | Where-Object { $_ } | Select-Object -Unique)
        $selectedOfficeHostPaths = @($selectedCandidates | Where-Object { $_.Kind -eq 'OfficeKmsHostOverride' } | ForEach-Object { [string]$_.Location } | Where-Object { $_ } | Select-Object -Unique)
        $officeEntriesToClean = @($unapprovedOfficeKmsEntries | Where-Object {
            $entryTargetId = Get-OfficeKmsTargetIdentity -Entry $_
            $selectedOfficeTargetIds -contains $entryTargetId
        })

        if ($DryRun) {
            $plannedActions = @(Get-DryRunRemediationPlan -Candidates $cleanupItems -SelectedIds $selectedCleanupIds -SkipRestorePoint:$NoRestorePoint)
            $actions.Add((Get-CleanupText 'cleanupReport.dryRun.noChanges'))
            foreach ($plannedAction in $plannedActions) {
                $actions.Add((Get-CleanupText 'cleanupReport.dryRun.planLine' @($plannedAction.Order, $plannedAction.Action, $plannedAction.Target)))
            }
        } else {
        if (-not $NoRestorePoint) {
            try {
                Checkpoint-Computer -Description (Get-CleanupText "cleanupReport.restorePoint.selectedDescription" @($releaseVersion)) -RestorePointType "MODIFY_SETTINGS" | Out-Null
                $actions.Add((Get-CleanupText "cleanupReport.action.selectedRestorePointCreated"))
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.action.selectedRestorePointFailed" @($_.Exception.Message)))
            }
        }

        # Sao lưu/cách ly và ký manifest trước. Chỉ sau khi bước này thành công
        # mới cho phép thay đổi product key đã được người dùng chọn.
        $deepResult = Invoke-DeepCleanupV35 -Candidates $cleanupItems -SelectedIds $selectedCleanupIds
        $backupDirectory = [string]$deepResult.BackupDirectory
        if ($deepResult.PSObject.Properties['SystemChangeCount']) { $systemChangeCount += [int]$deepResult.SystemChangeCount }
        if ($deepResult.PSObject.Properties['ThirdPartyExecutionResults']) { $thirdPartyExecutionResults = @($deepResult.ThirdPartyExecutionResults) }
        foreach ($deepAction in @($deepResult.Actions)) { $actions.Add([string]$deepAction) }
        if ($backupDirectory) {
            $basicResult = Invoke-Remediation -Products $products -Findings $findings `
                -CleanupActivator:$false `
                -CleanupKmsConfiguration:$false `
                -WindowsProductsToRemove $windowsProductsToRemove `
                -SkipRestorePoint `
                -OfficeEntries $officeEntriesToClean `
                -OfficeHostOverridePaths $selectedOfficeHostPaths
            $basicActions = @($basicResult.Actions)
            foreach ($basicAction in $basicActions) { $actions.Add([string]$basicAction) }
            $systemChangeCount += [int]$basicResult.SystemChangeCount
            if ($basicResult.PSObject.Properties['RemediationStates']) {
                $stateLookup = @{}
                foreach ($state in @($remediationStates)) { $stateLookup[[string]$state.CandidateId] = $state }
                foreach ($state in @($basicResult.RemediationStates)) { $stateLookup[[string]$state.CandidateId] = $state }
                $remediationStates = @($stateLookup.Values)
            }
        } else {
            $actions.Add((Get-CleanupText "cleanupReport.action.productKeyBlocked"))
        }
        }
    } else {
        $actions.Add((Get-CleanupText "cleanupReport.action.noThreatNoChange"))
    }

    # Luôn quét lại sau xử lý. Chỉ kết luận sẵn sàng kích hoạt chính thức khi
    # không còn dấu hiệu đang hoạt động hoặc cấu hình KMS chưa phê duyệt.
    Reset-ScanCaches
    $script:ScanWarnings.Clear()
    $script:WindowsLicenseSourceNote = ""
    $products = @($(if ($includeWindowsScan) { Get-WindowsLicenseProducts }))
    $findings = @($(if ($includeWindowsOfficeScan) { Get-ActivatorFindings }))
    $officeLicenseEntries = @($(if ($includeOfficeScan) { Get-OfficeLicenseEntries }))
    $officeKmsEntries = @($(if ($includeOfficeScan) { Get-OfficeKmsEntries -LicenseEntries $officeLicenseEntries }))
    $installedApplications = @($(if ($includeThirdPartyScan) { Get-InstalledSoftwareInventory }))
    $softwareCatalog = if ($includeThirdPartyScan) { Get-ToolSoftwareLicenseCatalog -PreferCache } else { $null }
    $thirdPartyEvidence = @($(if ($includeThirdPartyScan) { Get-ThirdPartyStrongEvidence -Applications $installedApplications -Catalog $softwareCatalog }))
    $thirdPartyApplications = @($(if ($includeThirdPartyScan) {
        Get-ToolSoftwareAssessments `
            -Applications @($installedApplications | Where-Object {
                -not ([bool]$_.IsMicrosoft -and [string]$_.Name -match '(?i)\bWindows\b|\bOffice\b|\bMicrosoft\s*365\b')
            }) `
            -Catalog $softwareCatalog -ExternalEvidence $thirdPartyEvidence -DeepScan:$deepSoftwareScanEnabled `
            -DeepScanMaximumDurationSeconds $DeepSoftwareScanTimeoutSeconds `
            -DeepScanMaximumSignatureChecks $DeepSoftwareScanMaximumSignatureChecks `
            -DeepScanMaximumHashChecks $DeepSoftwareScanMaximumHashChecks
    }))
    $softwareDeepScanMetadata = Get-ToolSoftwareLastDeepScanMetadata
    $thirdPartyCandidates = @(Get-ThirdPartyLicenseCandidates -Applications $thirdPartyApplications -Evidence $thirdPartyEvidence)
    Connect-ThirdPartyApplicationsToCandidates -Applications $thirdPartyApplications -Candidates $thirdPartyCandidates
    $allCleanupItems = @(Get-AllCleanupCandidates -Products $products -Findings $findings -OfficeEntries $officeKmsEntries -ThirdPartyCandidates $thirdPartyCandidates)
    $cleanupItems = @(Get-ScopedCleanupCandidates -CleanupItems $allCleanupItems -Scope $ScanScope)
    $scanSnapshot = New-CleanupScanSnapshot -Candidates $cleanupItems -Scope $ScanScope
    $history = @($(if ($includeWindowsOfficeScan) { Get-InvalidActivationHistory }))
    $verification = Get-CleanupVerification -Products $products -Findings $findings -OfficeEntries $officeKmsEntries -History $history -Scope $ScanScope
    $verification = Add-ThirdPartyVerification -Verification $verification -ThirdPartyCandidates $thirdPartyCandidates -ThirdPartyApplications $thirdPartyApplications -Included:$includeThirdPartyScan
    $scopeReadyForOriginalState = Test-CleanupScopeReady -Verification $verification -Scope $ScanScope
    $officialLicensePostCheck = Get-OfficialLicensePostCheck -Verification $verification -Products $products `
        -OfficeLicenseEntries $officeLicenseEntries -OfficeProbe $script:OfficeLicenseProbe `
        -ThirdPartyApplications $thirdPartyApplications -Scope $ScanScope
    $postProtectedLicense = if ($includeWindowsScan) { Get-ProtectedLicenseInfo -Products $products } else {
        [pscustomobject]@{ Protected=$false; Channel=(Get-CleanupText 'common.unknown'); Reason=(Get-CleanupText 'cleanupReport.protected.none') }
    }
    $postActiveProduct = $products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
    $postActiveChannel = if ($postActiveProduct) { Get-LicenseChannel $postActiveProduct } else { Get-CleanupText "common.unknown" }
    $postCrackDetected = [bool]([int]$verification.ActiveActivatorFindingCount -gt 0 -or [int]$verification.UnapprovedWindowsKmsCount -gt 0 -or [int]$verification.UnapprovedOfficeKmsCount -gt 0 -or [int]$verification.ThirdPartyRemediationFindingCount -gt 0)

    # Resolve every selected item from a fresh scan.  A successful command or
    # removed artifact is not success by itself: VerifiedClean additionally
    # requires that the application still exists and its official local state
    # is Unactivated/Trial with no direct crack evidence remaining.
    if (-not $DryRun) {
        foreach ($state in @($remediationStates)) {
            if ([string]$state.State -in @('BlockedByPolicy','ApprovedInternalKMS','NeedsOfficeRepair')) { continue }
            if ([string]$state.State -eq 'Pending') { [void](Set-RemediationStateRecord -Record $state -State Running) }
            $originalCandidate = @($selectedCandidates | Where-Object {
                [string]::Equals([string]$_.Id, [string]$state.CandidateId, [StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1)
            $component = if ($originalCandidate.Count -gt 0) { Get-CleanupRecordComponentScope -Record $originalCandidate[0] }
                elseif ([string]$state.Provider -eq 'OfficeOSPP') { 'Office' }
                elseif ([string]$state.Provider -eq 'WindowsSPP') { 'Windows' }
                else { 'Shared' }
            $original = if ($originalCandidate.Count -gt 0) { $originalCandidate[0] } else { $null }
            $originalApplicationIds = if ($original) { @($original.ApplicationIds | ForEach-Object { [string]$_ } | Where-Object { $_ }) } else { @() }
            $remainingDirectCandidates = @($cleanupItems | Where-Object {
                if ([string]$_.Type -eq 'Guidance' -or
                    ($_.PSObject.Properties['GuidanceOnly'] -and [bool]$_.GuidanceOnly) -or
                    [string]$_.Kind -eq 'ThirdPartyCompleteUninstall' -or
                    (Get-CleanupRecordComponentScope -Record $_) -ne $component) { return $false }
                if ($null -eq $original) { return $true }
                if ($component -eq 'ThirdParty') {
                    return [bool](@($_.ApplicationIds | Where-Object { $originalApplicationIds -contains [string]$_ }).Count -gt 0)
                }
                if ($component -eq 'Windows') {
                    return [bool]([string]::Equals([string]$_.TargetId, [string]$original.TargetId, [StringComparison]::OrdinalIgnoreCase))
                }
                if ($component -eq 'Office') {
                    if ([string]$original.Kind -eq 'OfficeKmsHostOverride') {
                        return [bool]([string]$_.Kind -eq 'OfficeKmsHostOverride' -and
                            [string]::Equals([string]$_.Location, [string]$original.Location, [StringComparison]::OrdinalIgnoreCase))
                    }
                    return [bool]([string]::Equals([string]$_.TargetId, [string]$original.TargetId, [StringComparison]::OrdinalIgnoreCase))
                }
                return [bool]([string]::Equals([string]$_.Id, [string]$original.Id, [StringComparison]::OrdinalIgnoreCase))
            })
            $directRemaining = [bool]($remainingDirectCandidates.Count -gt 0)
            $applicationPresent = $false
            $officialState = 'Unverified'
            if ($component -eq 'Office') {
                $applicationPresent = [bool](Test-OfficeProductInstalled -LicenseEntries $officeLicenseEntries)
                $officialState = [string]$officialLicensePostCheck.Office.StateCode
            } elseif ($component -eq 'Windows') {
                $nativeSystemDirectory = Split-Path -Parent (Get-ToolNativeSystemPath 'kernel32.dll')
                $applicationPresent = [bool](Test-Path -LiteralPath $nativeSystemDirectory -PathType Container)
                $officialState = [string]$officialLicensePostCheck.Windows.StateCode
            } elseif ($component -eq 'ThirdParty' -and $originalCandidate.Count -gt 0) {
                $applicationIds = @($originalCandidate[0].ApplicationIds | ForEach-Object { [string]$_ } | Where-Object { $_ })
                $matchedApps = @($thirdPartyApplications | Where-Object { $applicationIds -contains [string]$_.Id })
                $matchedOutcomes = @($officialLicensePostCheck.ThirdParty | Where-Object { $applicationIds -contains [string]$_.ApplicationId })
                $applicationPresent = [bool]($matchedApps.Count -gt 0)
                if ($matchedOutcomes.Count -gt 0 -and @($matchedOutcomes | Where-Object { [string]$_.StateCode -notin @('Unactivated','Trial') }).Count -eq 0) {
                    $officialState = 'Unactivated'
                } elseif ($matchedOutcomes.Count -gt 0) {
                    $officialState = [string]$matchedOutcomes[0].StateCode
                } elseif (-not $applicationPresent -and [string]$originalCandidate[0].Kind -eq 'ThirdPartyCompleteUninstall') {
                    $officialState = 'Removed'
                }
            }
            $artifactCleanupCompleted = [bool]$state.ArtifactCleanupCompleted
            if (-not $artifactCleanupCompleted -and $originalCandidate.Count -gt 0) {
                $executionMatch = @($thirdPartyExecutionResults | Where-Object {
                    [string]::Equals([string]$_.ParentCandidateId, [string]$state.CandidateId, [StringComparison]::OrdinalIgnoreCase) -and [bool]$_.Changed
                })
                $artifactCleanupCompleted = [bool]($executionMatch.Count -gt 0)
            }
            $volumeRepairRequired = [bool]($component -eq 'Office' -and
                (Test-OfficeVolumeOrMondoRepairRequired -LicenseEntries $officeLicenseEntries `
                    -OfficialLicenseState $officialState -DirectCrackEvidenceRemaining:$directRemaining))
            [void](Resolve-RemediationPostCheckState -Record $state `
                -DirectCrackEvidenceRemaining:$directRemaining -ApplicationPresent:$applicationPresent `
                -OfficialLicenseState $officialState -ArtifactCleanupCompleted:$artifactCleanupCompleted `
                -VolumeRepairRequired:$volumeRepairRequired `
                -ExpectedApplicationAbsent:([bool]($originalCandidate.Count -gt 0 -and [string]$originalCandidate[0].Kind -eq 'ThirdPartyCompleteUninstall')) `
                -AllowLicensedState:([bool]($officialState -eq 'Licensed')))
            if (-not [string]::IsNullOrWhiteSpace([string]$state.OutcomeMessageKey)) {
                $actions.Add((Get-CleanupText ([string]$state.OutcomeMessageKey) @([string]$state.CandidateId, [string]$state.OfficialLicenseState)))
            }
        }
    }
    $remediationPostCheckPassed = [bool](@($remediationStates | Where-Object {
        [string]$_.State -notin @('VerifiedClean','ApprovedInternalKMS')
    }).Count -eq 0)
    $thirdPartyChangedCount = [int]@($thirdPartyExecutionResults | Where-Object { [bool]$_.Changed }).Count
    $thirdPartyFailedCount = [int]@($thirdPartyExecutionResults | Where-Object { [string]$_.Status -eq 'Failed' }).Count
    $thirdPartyGuidanceOnlyCount = [int]@($thirdPartyExecutionResults | Where-Object { [string]$_.Status -eq 'GuidanceOnly' }).Count
    $remainingSelectedThirdPartyIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($snapshot in @($selectedThirdPartySnapshots)) {
        $matchedPostCandidate = @($thirdPartyCandidates | Where-Object {
            Test-CleanupCandidateMatchesSelectedSnapshot -Candidate $_ -SelectedCandidateSnapshots @($snapshot)
        } | Select-Object -First 1)
        if ($matchedPostCandidate.Count -gt 0) { [void]$remainingSelectedThirdPartyIds.Add([string]$snapshot.Id) }
    }
    $selectedThirdPartyRemainingCount = [int]$remainingSelectedThirdPartyIds.Count
    $selectedThirdPartyResolvedCount = [int]([Math]::Max(0, @($selectedThirdPartySnapshots).Count - $selectedThirdPartyRemainingCount))
    foreach ($execution in @($thirdPartyExecutionResults)) {
        $parentId = [string]$execution.ParentCandidateId
        $postCheckStatus = if ([string]$execution.Status -eq 'GuidanceOnly') { 'OfficialActionRequired' }
            elseif (-not [string]::IsNullOrWhiteSpace($parentId) -and $remainingSelectedThirdPartyIds.Contains($parentId)) { 'ResidualRemaining' }
            elseif ([string]$execution.Status -eq 'Failed') { 'ActionFailed' }
            else { 'Resolved' }
        $execution | Add-Member -NotePropertyName PostCheckStatus -NotePropertyValue $postCheckStatus -Force
    }
    # With an explicit selection, this result window represents that reviewed
    # subset.  Unselected findings remain in the full report but cannot make a
    # successfully verified selected item look like a failed "process all".
    $postReadyForCurrentScope = if ($selectedCleanupIds.Count -gt 0) {
        [bool]$remediationPostCheckPassed
    } else {
        [bool]($scopeReadyForOriginalState -and $remediationPostCheckPassed)
    }
    $postVerificationItems = @(Get-CleanupPostVerificationItems -CleanupItems $cleanupItems -SelectedIds $selectedCleanupIds `
        -SelectedCandidateSnapshots $selectedCandidates `
        -ThirdPartyExecutionResults $thirdPartyExecutionResults -Verification $verification)
    $postVerificationSuggestedIds = @($postVerificationItems | Where-Object {
        [bool]$_.SuggestedForNextStep -and -not [string]::IsNullOrWhiteSpace([string]$_.CandidateId)
    } | ForEach-Object { [string]$_.CandidateId } | Select-Object -Unique)
    $postVerificationTargetCandidateCount = [int]$postVerificationItems.Count
    $targetedThirdPartyCandidateCount = [int]@($selectedThirdPartySnapshots).Count
    $unselectedThirdPartyCandidateCount = [int][Math]::Max(0, [int]$verification.ThirdPartyCandidateCount - $targetedThirdPartyCandidateCount)
    $postVerificationOutcome = Get-CleanupPostVerificationOutcome -PostVerificationItems $postVerificationItems `
        -ScopeReady:$postReadyForCurrentScope -OfficiallyLicensed:([bool]$officialLicensePostCheck.OfficiallyLicensed)
    $postDecisionCode = if (-not $DeepClean -or -not $script:SelectionAccepted) {
        'SelectionRejected'
    } elseif ($DryRun) {
        'DryRunCompleted'
    } elseif ($thirdPartyFailedCount -gt 0) {
        'RemediationFailed'
    } elseif ($selectedCleanupIds.Count -gt 0 -and $systemChangeCount -eq 0 -and $thirdPartyGuidanceOnlyCount -gt 0) {
        'GuidedActionRequired'
    } elseif ($postReadyForCurrentScope) {
        'PostCheckPassed'
    } elseif ($postVerificationOutcome -eq 'CannotAutoHandle') {
        'CannotAutoHandle'
    } else {
        'ResidueRemaining'
    }
    $postDecisionText = switch ($postDecisionCode) {
        'SelectionRejected' { Get-CleanupText 'cleanupReport.decision.selectionRejected' }
        'DryRunCompleted' { Get-CleanupText 'cleanupReport.dryRun.completed' }
        'RemediationFailed' { Get-CleanupText 'cleanupReport.decision.remediationFailed' }
        'GuidedActionRequired' { Get-CleanupText 'cleanupReport.decision.guidedActionRequired' }
        'PostCheckPassed' { Get-CleanupText 'cleanupReport.decision.postCheckPassed' }
        'CannotAutoHandle' { Get-CleanupText 'cleanupReport.decision.cannotAutoHandle' }
        default { Get-CleanupText 'cleanupReport.decision.residueRemaining' }
    }
    $postConclusion = switch ($postDecisionCode) {
        'SelectionRejected' { Get-CleanupText 'cleanupReport.action.selectionRejectedDetail' @([string]$script:SelectionErrorCode) }
        'DryRunCompleted' { Get-CleanupText 'cleanupReport.dryRun.completed' }
        'RemediationFailed' { Get-CleanupText 'cleanupReport.decision.remediationFailedDetail' @($thirdPartyFailedCount) }
        'GuidedActionRequired' { Get-CleanupText 'cleanupReport.selectedScope.guidance' @($selectedCleanupIds.Count) }
        'PostCheckPassed' { Get-CleanupText 'cleanupReport.selectedScope.clean' @($selectedCleanupIds.Count) }
        'CannotAutoHandle' { Get-CleanupText 'cleanupReport.selectedScope.cannotAutoHandle' @($postVerificationItems.Count) }
        default { Get-CleanupText 'cleanupReport.selectedScope.remaining' @($postVerificationItems.Count) }
    }
    $finalDecisionCode = [string]$postDecisionCode
    $finalDecisionText = [string]$postDecisionText
    $finalCleanupConclusion = [string]$postConclusion
    $postExecutionAccepted = [bool]($postDecisionCode -notin @('SelectionRejected','RemediationFailed'))
    $finalReadyForOfficialActivation = [bool]($verification.ReadyForOfficialActivation -and $postExecutionAccepted -and $remediationPostCheckPassed)
    $finalScopeReadyForOriginalState = [bool]($scopeReadyForOriginalState -and $postExecutionAccepted -and $remediationPostCheckPassed)
    $nextActionCleanupItems = if ($selectedCleanupIds.Count -gt 0) {
        @($postVerificationItems | Where-Object { [bool]$_.SuggestedForNextStep })
    } else {
        @($cleanupItems)
    }
    $postNextActions = @(Get-CleanupNextActions -Verification $verification -CleanupItems $nextActionCleanupItems `
        -ProtectedLicense ([bool]$postProtectedLicense.Protected) -BackupDirectory $backupDirectory `
        -OfficialLicensePostCheck $officialLicensePostCheck -Scope $ScanScope)
    if ($selectedCleanupIds.Count -gt 0) {
        # Never expose a global/default remediation route from the result of a
        # manual subset.  With no exact target ID, the GUI must not reopen the
        # chooser and silently fall back to its default selections.
        $postNextActions = @($postNextActions | Where-Object {
            [string]$_.Code -ne 'RemediateRemaining' -or $postVerificationSuggestedIds.Count -gt 0
        })
        foreach ($nextAction in @($postNextActions | Where-Object { [string]$_.Code -eq 'RemediateRemaining' })) {
            $nextAction.CandidateCount = [int]$postVerificationSuggestedIds.Count
        }
    }
    if (-not $DryRun) { $actions.Add((Get-CleanupText "cleanupReport.action.postCheck" @($verification.Conclusion))) }
    $decisionData = New-ToolReportEnvelope -ReportKind "CleanupCompliance" -ToolVersion "5.0" -Data ([ordered]@{
        ScanScope = $ScanScope
        CrackDetected = $postCrackDetected
        ProtectedLicense = [bool]$postProtectedLicense.Protected
        ProtectedChannel = [string]$postProtectedLicense.Channel
        ProtectedReason = [string]$postProtectedLicense.Reason
        ActiveWindowsChannel = [string]$postActiveChannel
        RemoveWindowsLicense = $removeWindowsLicense
        ActivatorFindingCount = [int]$verification.ActiveActivatorFindingCount
        HistoryFindingCount = [int]$verification.HistoryFindingCount
        ConfigurationResidueCount = [int]$verification.ConfigurationResidueCount
        WindowsKmsCount = [int]$verification.UnapprovedWindowsKmsCount
        OfficeKmsCount = [int]$verification.UnapprovedOfficeKmsCount
        OfficeProbe = $script:OfficeLicenseProbe
        InstalledApplicationCount = [int]$installedApplications.Count
        ThirdPartyApplicationCount = [int]$thirdPartyApplications.Count
        ThirdPartyEvidenceCount = [int]$thirdPartyEvidence.Count
        ThirdPartyCandidateCount = [int]$verification.ThirdPartyCandidateCount
        ThirdPartyAutoEligibleCount = [int]$verification.ThirdPartyAutoEligibleCount
        ThirdPartyNeedsReviewCount = [int]@($thirdPartyApplications | Where-Object { [bool]$_.NeedsReview }).Count
        ThirdPartyRemediationFindingCount = [int]$verification.ThirdPartyRemediationFindingCount
        ThirdPartyNonGenuineCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'NonGenuine' }).Count
        ThirdPartySuspiciousCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'Suspicious' }).Count
        ThirdPartyUnverifiedCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -in @('Unverified','TrialOrUnverified') }).Count
        SoftwareCatalogSource = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogSource } else { 'Unavailable' })
        SoftwareCatalogVersion = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogVersion } else { '' })
        SoftwareCatalogRuleCount = $(if ($softwareCatalog) { [int]@($softwareCatalog.Products).Count } else { 0 })
        DeepSoftwareScanEnabled = [bool]$softwareDeepScanMetadata.Enabled
        DeepSoftwareScanComplete = [bool]$softwareDeepScanMetadata.Complete
        DeepSoftwareScanAdministrator = [bool]$softwareDeepScanMetadata.IsAdministrator
        DeepSoftwareScanApplicationsScanned = [int]$softwareDeepScanMetadata.ApplicationsScanned
        DeepSoftwareScanApplicationsSkipped = [int]$softwareDeepScanMetadata.ApplicationsSkipped
        DeepSoftwareScanUniqueRoots = [int]$softwareDeepScanMetadata.UniqueRootsScanned
        DeepSoftwareScanRootCacheHits = [int]$softwareDeepScanMetadata.RootCacheHits
        DeepSoftwareScanTotalEntries = [int]$softwareDeepScanMetadata.TotalEntries
        DeepSoftwareScanRelevantFiles = [int]$softwareDeepScanMetadata.RelevantFiles
        DeepSoftwareScanSignatureChecks = [int]$softwareDeepScanMetadata.SignatureChecks
        DeepSoftwareScanHashChecks = [int]$softwareDeepScanMetadata.HashChecks
        DeepSoftwareScanEvidenceCount = [int]$softwareDeepScanMetadata.EvidenceCount
        DeepSoftwareScanDurationMilliseconds = [int]$softwareDeepScanMetadata.DurationMilliseconds
        DeepSoftwareScanTimeLimitReached = [bool]$softwareDeepScanMetadata.TimeLimitReached
        DeepSoftwareScanEntryLimitReached = [bool]$softwareDeepScanMetadata.EntryLimitReached
        DeepSoftwareScanSignatureLimitReached = [bool]$softwareDeepScanMetadata.SignatureLimitReached
        DeepSoftwareScanHashLimitReached = [bool]$softwareDeepScanMetadata.HashLimitReached
        DeepSoftwareScanAccessWarningCount = [int]$softwareDeepScanMetadata.AccessWarningCount
        ThirdPartyApplications = @($thirdPartyApplications)
        ThirdPartyEvidence = @($thirdPartyEvidence)
        ThirdPartyCandidates = @($thirdPartyCandidates)
        ThirdPartyChangedCount = $thirdPartyChangedCount
        ThirdPartyFailedCount = $thirdPartyFailedCount
        ThirdPartyGuidanceOnlyCount = $thirdPartyGuidanceOnlyCount
        SelectedThirdPartyCandidateCount = [int]@($selectedThirdPartySnapshots).Count
        SelectedThirdPartyResolvedCount = [int]$selectedThirdPartyResolvedCount
        SelectedThirdPartyRemainingCount = [int]$selectedThirdPartyRemainingCount
        TargetedThirdPartyCandidateCount = [int]$targetedThirdPartyCandidateCount
        UnselectedThirdPartyCandidateCount = [int]$unselectedThirdPartyCandidateCount
        ApprovedOfficeKmsCount = [int]($officeKmsEntries.Count - $verification.UnapprovedOfficeKmsCount)
        ApprovedKmsServerFile = [string]$approvedKmsConfig.Path
        ApprovedKmsServerCount = [int]$approvedKmsConfig.Valid.Count
        InvalidApprovedKmsCount = [int]$approvedKmsConfig.Invalid.Count
        ApprovedKmsConfigWarning = [string]$approvedKmsConfig.Warning
        DecisionCode = $postDecisionCode
        Decision = $postDecisionText
        Reason = [string]$postConclusion
        ReadyForOfficialActivation = [bool]$finalReadyForOfficialActivation
        ScopeReadyForOriginalState = [bool]$finalScopeReadyForOriginalState
        OfficiallyLicensed = [bool]$officialLicensePostCheck.OfficiallyLicensed
        OfficialLicenseStateCode = [string]$officialLicensePostCheck.StateCode
        OfficialLicensePostCheck = $officialLicensePostCheck
        ReadinessReviewCount = [int]$verification.ReadinessReviewCount
        ScanWarningCount = [int]$verification.ScanWarningCount
        ScanWarnings = $verification.ScanWarnings
        ReadinessChecks = $verification.ReadinessChecks
        DeepCleanupApplied = [bool](-not $DryRun -and $systemChangeCount -gt 0)
        SystemChangeApplied = [bool](-not $DryRun -and $systemChangeCount -gt 0)
        SystemChangeCount = [int]$systemChangeCount
        ThirdPartyExecutionResults = @($thirdPartyExecutionResults)
        RemediationStates = @($remediationStates)
        RemediationPostCheckPassed = [bool]$remediationPostCheckPassed
        DryRunRequested = [bool]$DryRun
        SimulationOnly = [bool]$DryRun
        NoSystemChangesApplied = [bool]($DryRun -or $systemChangeCount -eq 0)
        PlannedActionCount = [int]@($plannedActions).Count
        PlannedActions = @($plannedActions)
        SelectedCleanupIds = @($selectedCleanupIds)
        SelectionAccepted = [bool]$script:SelectionAccepted
        SelectionErrorCode = [string]$script:SelectionErrorCode
        SelectionErrorDetail = [string]$script:SelectionErrorDetail
        UnknownSelectedCleanupIdCount = [int]$unknownSelectedCleanupIds.Count
        BackupWouldBeCreated = [bool](@($plannedActions | Where-Object { [bool]$_.BackupPlanned }).Count -gt 0)
        CleanupItems = $cleanupItems
        ScanSnapshot = $scanSnapshot
        SelectionRequired = [bool]($cleanupItems.Count -gt 0)
        SelectedCleanupItemCount = [int]$selectedCleanupIds.Count
        BackupDirectory = [string]$backupDirectory
        CleanupConclusion = [string]$postConclusion
        FullScopeCleanupConclusion = [string]$fullScopeCleanupConclusion
        PostVerification = [pscustomobject][ordered]@{ FreshScan=$true; PerformedAtUtc=[DateTime]::UtcNow.ToString('o'); Outcome=$postVerificationOutcome; RemainingItemCount=[int]$postVerificationItems.Count; ScanWarningCount=[int]$verification.ScanWarningCount }
        PostVerificationItems = @($postVerificationItems)
        PostVerificationSuggestedIds = @($postVerificationSuggestedIds)
        PostVerificationTargetCandidateCount = [int]$postVerificationTargetCandidateCount
        PostVerificationOutcome = $postVerificationOutcome
        HandlingGuidance = $verification.HandlingGuidance
        NextActions = @($postNextActions)
        ScopeNote = [string]$verification.ScopeNote
        ReportPath = [string]$reportPath
        Actions = @($actions)
    })
    Write-DecisionData -Path $DecisionFile -Data $decisionData
}

$reportVerification = $verification.PSObject.Copy()
$reportVerification.ReadyForOfficialActivation = [bool]$finalReadyForOfficialActivation
$reportVerification.Conclusion = [string]$finalCleanupConclusion
Write-Report -Path $reportPath -Products $products -Findings $findings -Decision $decision -Actions $actions -History $history -Verification $reportVerification -ThirdPartyApplications $thirdPartyApplications -ThirdPartyEvidence $thirdPartyEvidence -ThirdPartyCandidates $thirdPartyCandidates -SoftwareDeepScanMetadata $softwareDeepScanMetadata -CleanupItems $cleanupItems -ScanSnapshot $scanSnapshot

# Bộ tóm tắt máy đọc được và hash đi kèm giúp đối chiếu hậu kiểm mà không
# thay đổi luồng xử lý v3.0. Không ghi product key đầy đủ vào JSON.
$jsonReportPath = [IO.Path]::ChangeExtension($reportPath, ".json")
$hashReportPath = [IO.Path]::ChangeExtension($reportPath, ".sha256")
$cleanupSummary = New-ToolReportEnvelope -ReportKind "CleanupCompliance" -ToolVersion "5.0" -Data ([ordered]@{
    ScanScope = $ScanScope
    ComputerName = $reportComputer
    CreatedAt = (Get-Date).ToString("o")
    Redacted = [bool]$RedactSensitive
    Remediate = [bool]$Remediate
    DeepClean = [bool]$DeepClean
    DryRunRequested = [bool]$DryRun
    SimulationOnly = [bool]$DryRun
    NoSystemChangesApplied = [bool]($DryRun -or $systemChangeCount -eq 0)
    SystemChangeApplied = [bool](-not $DryRun -and $systemChangeCount -gt 0)
    SystemChangeCount = [int]$systemChangeCount
    ThirdPartyExecutionResults = @($thirdPartyExecutionResults)
    RemediationStates = @($remediationStates)
    RemediationPostCheckPassed = [bool](@($remediationStates | Where-Object { [string]$_.State -notin @('VerifiedClean','ApprovedInternalKMS') }).Count -eq 0)
    ThirdPartyChangedCount = [int]@($thirdPartyExecutionResults | Where-Object { [bool]$_.Changed }).Count
    ThirdPartyFailedCount = [int]@($thirdPartyExecutionResults | Where-Object { [string]$_.Status -eq 'Failed' }).Count
    ThirdPartyGuidanceOnlyCount = [int]@($thirdPartyExecutionResults | Where-Object { [string]$_.Status -eq 'GuidanceOnly' }).Count
    SelectedThirdPartyCandidateCount = [int]@($selectedThirdPartySnapshots).Count
    SelectedThirdPartyResolvedCount = [int]$selectedThirdPartyResolvedCount
    SelectedThirdPartyRemainingCount = [int]$selectedThirdPartyRemainingCount
    TargetedThirdPartyCandidateCount = [int]$targetedThirdPartyCandidateCount
    UnselectedThirdPartyCandidateCount = [int]$unselectedThirdPartyCandidateCount
    PlannedActionCount = [int]@($plannedActions).Count
    PlannedActions = @($plannedActions)
    SelectedCleanupIds = @($selectedCleanupIds)
    SelectionAccepted = [bool]$script:SelectionAccepted
    SelectionErrorCode = [string]$script:SelectionErrorCode
    SelectionErrorDetail = [string]$script:SelectionErrorDetail
    UnknownSelectedCleanupIdCount = [int]$unknownSelectedCleanupIds.Count
    BackupWouldBeCreated = [bool](@($plannedActions | Where-Object { [bool]$_.BackupPlanned }).Count -gt 0)
    DecisionCode = [string]$finalDecisionCode
    Decision = [string]$finalDecisionText
    ReadyForOfficialActivation = [bool]$finalReadyForOfficialActivation
    ScopeReadyForOriginalState = [bool]$finalScopeReadyForOriginalState
    OfficiallyLicensed = [bool]$officialLicensePostCheck.OfficiallyLicensed
    OfficialLicenseStateCode = [string]$officialLicensePostCheck.StateCode
    OfficialLicensePostCheck = $officialLicensePostCheck
    CleanupConclusion = [string]$finalCleanupConclusion
    FullScopeCleanupConclusion = [string]$fullScopeCleanupConclusion
    PostVerification = [pscustomobject][ordered]@{ FreshScan=$true; PerformedAtUtc=[DateTime]::UtcNow.ToString('o'); Outcome=$postVerificationOutcome; RemainingItemCount=[int]$postVerificationItems.Count; ScanWarningCount=[int]$verification.ScanWarningCount }
    PostVerificationItems = @($postVerificationItems)
    PostVerificationSuggestedIds = @($postVerificationSuggestedIds)
    PostVerificationTargetCandidateCount = [int]$postVerificationTargetCandidateCount
    PostVerificationOutcome = $postVerificationOutcome
    HandlingGuidance = $verification.HandlingGuidance
    ReadinessReviewCount = [int]$verification.ReadinessReviewCount
    ScanWarningCount = [int]$verification.ScanWarningCount
    ScanWarnings = $verification.ScanWarnings
    WindowsLicenseSourceNote = [string]$script:WindowsLicenseSourceNote
    ReadinessChecks = $verification.ReadinessChecks
    ActivatorFindingCount = [int]$verification.ActiveActivatorFindingCount
    ConfigurationResidueCount = [int]$verification.ConfigurationResidueCount
    WindowsKmsCount = [int]$verification.UnapprovedWindowsKmsCount
    OfficeKmsCount = [int]$verification.UnapprovedOfficeKmsCount
    OfficeProbe = $script:OfficeLicenseProbe
    InstalledApplicationCount = [int]$installedApplications.Count
    ThirdPartyApplicationCount = [int]$thirdPartyApplications.Count
    ThirdPartyEvidenceCount = [int]$thirdPartyEvidence.Count
    ThirdPartyCandidateCount = [int]$verification.ThirdPartyCandidateCount
    ThirdPartyAutoEligibleCount = [int]$verification.ThirdPartyAutoEligibleCount
    ThirdPartyNeedsReviewCount = [int]@($thirdPartyApplications | Where-Object { [bool]$_.NeedsReview }).Count
    ThirdPartyRemediationFindingCount = [int]$verification.ThirdPartyRemediationFindingCount
    ThirdPartyNonGenuineCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'NonGenuine' }).Count
    ThirdPartySuspiciousCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'Suspicious' }).Count
    ThirdPartyUnverifiedCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -in @('Unverified','TrialOrUnverified') }).Count
    SoftwareCatalogSource = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogSource } else { 'Unavailable' })
    SoftwareCatalogVersion = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogVersion } else { '' })
    SoftwareCatalogRuleCount = $(if ($softwareCatalog) { [int]@($softwareCatalog.Products).Count } else { 0 })
    DeepSoftwareScanEnabled = [bool]$softwareDeepScanMetadata.Enabled
    DeepSoftwareScanComplete = [bool]$softwareDeepScanMetadata.Complete
    DeepSoftwareScanAdministrator = [bool]$softwareDeepScanMetadata.IsAdministrator
    DeepSoftwareScanApplicationsScanned = [int]$softwareDeepScanMetadata.ApplicationsScanned
    DeepSoftwareScanApplicationsSkipped = [int]$softwareDeepScanMetadata.ApplicationsSkipped
    DeepSoftwareScanUniqueRoots = [int]$softwareDeepScanMetadata.UniqueRootsScanned
    DeepSoftwareScanRootCacheHits = [int]$softwareDeepScanMetadata.RootCacheHits
    DeepSoftwareScanTotalEntries = [int]$softwareDeepScanMetadata.TotalEntries
    DeepSoftwareScanRelevantFiles = [int]$softwareDeepScanMetadata.RelevantFiles
    DeepSoftwareScanSignatureChecks = [int]$softwareDeepScanMetadata.SignatureChecks
    DeepSoftwareScanHashChecks = [int]$softwareDeepScanMetadata.HashChecks
    DeepSoftwareScanEvidenceCount = [int]$softwareDeepScanMetadata.EvidenceCount
    DeepSoftwareScanDurationMilliseconds = [int]$softwareDeepScanMetadata.DurationMilliseconds
    DeepSoftwareScanTimeLimitReached = [bool]$softwareDeepScanMetadata.TimeLimitReached
    DeepSoftwareScanEntryLimitReached = [bool]$softwareDeepScanMetadata.EntryLimitReached
    DeepSoftwareScanSignatureLimitReached = [bool]$softwareDeepScanMetadata.SignatureLimitReached
    DeepSoftwareScanHashLimitReached = [bool]$softwareDeepScanMetadata.HashLimitReached
    DeepSoftwareScanAccessWarningCount = [int]$softwareDeepScanMetadata.AccessWarningCount
    ThirdPartyApplications = @($thirdPartyApplications)
    ThirdPartyEvidence = @($thirdPartyEvidence)
    HistoryFindingCount = [int]$verification.HistoryFindingCount
    CleanupItems = @($cleanupItems)
    ScanSnapshot = $scanSnapshot
    NextActions = @($postNextActions)
    ApprovedKmsServerFile = Protect-CleanupReportText ([string]$approvedKmsConfig.Path)
    ApprovedKmsServerCount = [int]$approvedKmsConfig.Valid.Count
    InvalidApprovedKmsCount = [int]$approvedKmsConfig.Invalid.Count
    ApprovedKmsConfigWarning = [string]$approvedKmsConfig.Warning
    ReportPath = Protect-CleanupReportText $reportPath
    ScopeNote = Protect-CleanupReportText ([string]$verification.ScopeNote)
    Actions = @($actions | ForEach-Object { Protect-CleanupReportText $_ })
})
$cleanupSummaryValidation = Test-ToolReportEnvelope -Report $cleanupSummary -ExpectedReportKind "CleanupCompliance" -ExpectedToolVersion "5.0"
if (-not $cleanupSummaryValidation.Valid) { throw (Get-CleanupText "cleanupReport.output.schemaInvalid" @($cleanupSummaryValidation.Errors -join '; ')) }
$cleanupJson = $cleanupSummary | ConvertTo-Json -Depth 8
Protect-CleanupReportText $cleanupJson | Set-Content -LiteralPath $jsonReportPath -Encoding UTF8
$reportHash = ""
try {
    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        $reportHash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
    } else {
        $stream = [IO.File]::OpenRead($reportPath)
        try { $sha = [Security.Cryptography.SHA256]::Create(); $reportHash = ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant() } finally { $stream.Dispose() }
    }
} catch {}
"$reportHash  $([IO.Path]::GetFileName($reportPath))" | Set-Content -LiteralPath $hashReportPath -Encoding ASCII

Write-Host (Get-CleanupText "cleanupReport.output.report" @($reportPath))
Write-Host (Get-CleanupText "cleanupReport.output.json" @($jsonReportPath))
Write-Host (Get-CleanupText "cleanupReport.output.sha256" @($hashReportPath))
if ($approvedKmsConfig.Warning) { Write-Warning $approvedKmsConfig.Warning }
Write-Host (Get-CleanupText "cleanupReport.output.decision" @($decision.Decision))
Write-Host (Get-CleanupText "cleanupReport.output.reason" @($decision.Reason))
if ($Remediate) {
    $yes = Get-CleanupText "common.yes"
    $no = Get-CleanupText "common.no"
    Write-Host (Get-CleanupText "cleanupReport.output.actionCount" @($actions.Count))
    Write-Host (Get-CleanupText "cleanupReport.output.ready" @($(if ($verification.ReadyForOfficialActivation) { $yes } else { $no })))
    Write-Host (Get-CleanupText "cleanupReport.output.deepRequested" @($(if ($DeepClean) { $yes } else { $no })))
    Write-Host (Get-CleanupText "cleanupReport.output.backupApplied" @($(if ($decisionData.DeepCleanupApplied) { $yes } else { $no })))
    Write-Host (Get-CleanupText "cleanupReport.output.conclusion" @($verification.Conclusion))
    if (-not $DryRun -and -not $verification.ReadyForOfficialActivation) {
        exit 4
    }
}
if ($DryRun) { exit 0 }
if ($decision.DecisionCode -eq "ManualReview") {
    exit 2
}
if ($decision.ShouldRemediate -and -not $Remediate) {
    exit 3
}
exit 0

