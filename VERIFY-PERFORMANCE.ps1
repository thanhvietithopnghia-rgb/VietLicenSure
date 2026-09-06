[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("VietLicenSure-v5.0-performance-" + [Guid]::NewGuid().ToString('N'))
$previousScanSettingsPath = [string]$env:TOOL_SCAN_SETTINGS_PATH

function Add-Failure([string]$Message) { [void]$failures.Add($Message) }

try {
    $helperPath = Join-Path $root 'Tool-ScanOptimization.ps1'
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'Missing Tool-ScanOptimization.ps1.' }
    . $helperPath
    $softwareInventoryPath = Join-Path $root 'Tool-SoftwareInventory.ps1'
    if (-not (Test-Path -LiteralPath $softwareInventoryPath -PathType Leaf)) { throw 'Missing Tool-SoftwareInventory.ps1.' }
    . $softwareInventoryPath

    $metadata = Get-ToolScanOptimizationMetadata
    if ([string]$metadata.Version -ne '1.1' -or [string]$metadata.ToolVersion -ne '5.0' -or
        -not [bool]$metadata.PreservesExistingScanRoots -or [int]$metadata.OfficeStatusThrottle -gt 3 -or
        [int]$metadata.FileScanThrottle -gt 4 -or [int]$metadata.FileScanMaximumDepth -ne 4 -or
        [int]$metadata.FileScanPerRootTimeoutSeconds -ne 12 -or [int]$metadata.MaximumRootCount -ne 8 -or
        @($metadata.SupportedProfiles).Count -ne 3 -or -not [bool]$metadata.SupportsLowResourceMode -or
        -not [bool]$metadata.SupportsExcludedRoots) {
        Add-Failure 'Scan optimization metadata does not match the v5 profile contract.'
    }

    $quickPlan = Resolve-ToolScanPlan -Profile Quick
    $standardPlan = Resolve-ToolScanPlan -Profile Standard
    $deepPlan = Resolve-ToolScanPlan -Profile Deep
    $lowResourcePlan = Resolve-ToolScanPlan -Profile Deep -LowResource
    $requiredPlanProperties = @(
        'Profile','LowResource','IncludedRoots','ExcludedRoots','OfficeMaximumDepth','OfficeThrottleLimit',
        'OfficeTimeoutSeconds','IncludePortable','IncludePackageManagers','PortableMaximumResults',
        'PortableMaximumDepth','FileMaximumResults','FileThrottleLimit','FileMaximumDepth',
        'PerRootTimeoutSeconds','DeepAssessment','DeepScanMaximumDurationSeconds',
        'DeepScanMaximumSignatureChecks','DeepScanMaximumHashChecks','CoverageComplete','CoverageNote'
    )
    foreach ($propertyName in $requiredPlanProperties) {
        if ($null -eq $standardPlan.PSObject.Properties[$propertyName]) {
            Add-Failure "Scan plan is missing required metadata: $propertyName"
        }
    }
    if ($quickPlan.IncludePortable -or $quickPlan.DeepAssessment -or $quickPlan.CoverageComplete -or
        $standardPlan.CoverageComplete -or $standardPlan.FileMaximumDepth -ne 4 -or $standardPlan.FileMaximumResults -ne 60 -or
        $deepPlan.CoverageComplete -or -not $deepPlan.DeepAssessment -or $deepPlan.FileMaximumDepth -le $standardPlan.FileMaximumDepth -or
        $lowResourcePlan.FileThrottleLimit -ne 1 -or $lowResourcePlan.DeepScanMaximumSignatureChecks -ge $deepPlan.DeepScanMaximumSignatureChecks -or
        $lowResourcePlan.CoverageComplete) {
        Add-Failure 'Quick/Standard/Deep or low-resource scan budgets violate their boundaries.'
    }
    foreach ($boundedPlan in @($quickPlan, $standardPlan, $deepPlan, $lowResourcePlan)) {
        if ([string]::IsNullOrWhiteSpace([string]$boundedPlan.CoverageNote) -or
            [string]$boundedPlan.CoverageNote -notmatch '(?i)(bounded|caps|timeouts)' -or
            [string]$boundedPlan.CoverageNote -notmatch '(?i)must not be treated as clean') {
            Add-Failure "Scan profile $($boundedPlan.Profile) does not explain its incomplete bounded coverage conservatively."
        }
    }

    $rootOne = Join-Path $tempRoot 'disk-one'
    $rootTwo = Join-Path $tempRoot 'disk-two'
    [void](New-Item -ItemType Directory -Path (Join-Path $rootOne 'nested') -Force)
    [void](New-Item -ItemType Directory -Path $rootTwo -Force)
    [IO.File]::WriteAllText((Join-Path $rootOne 'nested\kms-tool.exe'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $rootTwo 'activator-readme.txt'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $rootTwo 'normal.txt'), 'fixture')
    $excludedFolder = Join-Path $rootTwo 'excluded'
    [void](New-Item -ItemType Directory -Path $excludedFolder -Force)
    [IO.File]::WriteAllText((Join-Path $excludedFolder 'kms-excluded.txt'), 'fixture')
    $tooDeep = Join-Path $rootOne 'd1\d2\d3\d4\d5'
    [void](New-Item -ItemType Directory -Path $tooDeep -Force)
    [IO.File]::WriteAllText((Join-Path $tooDeep 'activator-too-deep.txt'), 'fixture')

    $matches = @(Find-ToolPatternFilesParallel -Roots @($rootOne, $rootTwo) -ExcludedRoots @($excludedFolder) -Pattern '(?i)(kms|activator)' -MaximumResults 10 -ThrottleLimit 2)
    $unexpectedMatches = @($matches | Where-Object { $_ -notmatch '(kms-tool|activator-readme)' })
    if ($matches.Count -ne 2 -or $unexpectedMatches.Count -ne 0) {
        Add-Failure 'Parallel file scan did not return the expected multi-root fixtures.'
    }

    $resolvedPlan = Resolve-ToolScanPlan -Profile Deep -LowResource -IncludedRoots @($rootOne, $rootTwo) -ExcludedRoots @($excludedFolder)
    if ($resolvedPlan.IncludedRoots.Count -ne 2 -or $resolvedPlan.ExcludedRoots.Count -ne 1) {
        Add-Failure 'Validated include/exclude roots were not preserved in the scan plan.'
    }
    foreach ($invalidRoots in @(
        @('relative-folder'),
        @('C:drive-relative'),
        @('\\server\share')
    )) {
        $rejected = $false
        try { [void](Resolve-ToolLocalScanRoots -Roots $invalidRoots) } catch { $rejected = $true }
        if (-not $rejected) { Add-Failure "Unsafe scan root was accepted: $($invalidRoots -join ', ')" }
    }
    $nineRoots = New-Object System.Collections.Generic.List[string]
    foreach ($rootIndex in 1..9) {
        $boundaryRoot = Join-Path $tempRoot ("boundary-root-$rootIndex")
        [void](New-Item -ItemType Directory -Path $boundaryRoot -Force)
        [void]$nineRoots.Add($boundaryRoot)
    }
    $tooManyRejected = $false
    try { [void](Resolve-ToolLocalScanRoots -Roots $nineRoots.ToArray()) } catch { $tooManyRejected = $true }
    if (-not $tooManyRejected) { Add-Failure 'More than eight scan roots were accepted.' }

    $junctionPath = Join-Path $tempRoot 'reparse-root'
    $junctionCreated = $false
    try {
        [void](New-Item -ItemType Junction -Path $junctionPath -Target $rootOne -ErrorAction Stop)
        $junctionCreated = $true
    } catch {}
    if ($junctionCreated) {
        $reparseRejected = $false
        try { [void](Resolve-ToolLocalScanRoots -Roots @($junctionPath)) } catch { $reparseRejected = $true }
        if (-not $reparseRejected) { Add-Failure 'A junction/reparse scan root was accepted.' }

        # Automatic discovery can encounter Windows compatibility junctions
        # such as C:\Users\All Users\Desktop. The traversal helper must skip
        # that root and continue with the remaining real roots instead of
        # turning the whole software result into read-only mode.
        $junctionSafeMatches = @()
        try {
            $junctionSafeMatches = @(Find-ToolPatternFilesParallel -Roots @($junctionPath, $rootTwo) `
                -ExcludedRoots @($excludedFolder) -Pattern '(?i)(kms|activator)' -MaximumResults 10 -ThrottleLimit 2)
        } catch {
            Add-Failure "Automatic reparse root stopped the remaining scan roots: $($_.Exception.Message)"
        }
        if ($junctionSafeMatches.Count -ne 1 -or [IO.Path]::GetFileName([string]$junctionSafeMatches[0]) -ne 'activator-readme.txt') {
            Add-Failure 'Automatic reparse root was not skipped while the remaining local root continued.'
        }
    }

    $env:TOOL_SCAN_SETTINGS_PATH = Join-Path $tempRoot 'settings\scan-settings.json'
    if (-not (Set-ToolScanPreference -Profile Deep -LowResource -IncludedRoots @($rootOne) -ExcludedRoots @($excludedFolder))) {
        Add-Failure 'Scan preference could not be persisted atomically.'
    } else {
        $savedPlan = Get-ToolScanPreference
        if ($savedPlan.Profile -ne 'Deep' -or -not $savedPlan.LowResource -or $savedPlan.IncludedRoots.Count -ne 1 -or
            $savedPlan.ExcludedRoots.Count -ne 1) {
            Add-Failure 'Persisted scan preference did not round-trip safely.'
        }
    }
    $officeResults = @(Invoke-ToolParallelOfficeStatus -CscriptPath "$env:SystemRoot\System32\cscript.exe" -OsppPaths @() -ThrottleLimit 2)
    if ($officeResults.Count -ne 0) {
        Add-Failure 'Parallel Office scan did not handle an empty input list.'
    }

    $signatureRoot = Join-Path $tempRoot 'signature-batch'
    [void](New-Item -ItemType Directory -Path $signatureRoot -Force)
    $signaturePaths = New-Object System.Collections.Generic.List[string]
    foreach ($index in 1..6) {
        $signaturePath = Join-Path $signatureRoot ("fixture-$index.exe")
        [IO.File]::WriteAllText($signaturePath, ("unsigned-fixture-$index"), (New-Object Text.UTF8Encoding($false)))
        $signaturePaths.Add($signaturePath)
    }
    $script:ToolSoftwareSignatureCache = @{}
    $signatureResults = Get-ToolSoftwareSignatureStatesParallel -Paths $signaturePaths.ToArray() -ThrottleLimit 2
    $signatureCacheCount = $script:ToolSoftwareSignatureCache.Count
    $cachedSignatureResults = Get-ToolSoftwareSignatureStatesParallel -Paths $signaturePaths.ToArray() -ThrottleLimit 2
    if ($signatureResults.Count -ne $signaturePaths.Count -or $cachedSignatureResults.Count -ne $signaturePaths.Count -or
        $signatureCacheCount -ne $signaturePaths.Count -or $script:ToolSoftwareSignatureCache.Count -ne $signatureCacheCount) {
        Add-Failure 'Parallel Authenticode batching or its stable file cache is not working.'
    }
    $deepMetadata = Get-ToolSoftwareLastDeepScanMetadata
    foreach ($propertyName in @('UniqueDirectoriesScanned','DirectoryCacheHits')) {
        if ($null -eq $deepMetadata.PSObject.Properties[$propertyName]) {
            Add-Failure "Deep-scan performance metadata is missing: $propertyName"
        }
    }

    # Regression for the v4.8 inventory merge hot path: every synthetic product
    # is discovered twice but must keep one identical logical result.
    $syntheticRecords = New-Object System.Collections.Generic.List[object]
    foreach ($index in 1..240) {
        # A distinct leading token exercises the indexed name-bucket path while
        # the duplicate Registry/Shortcut pair still validates merge parity.
        $name = 'PerformanceFixture{0:d3} Product' -f $index
        $location = 'C:\Program Files\PerformanceFixture\{0:d3}' -f $index
        foreach ($source in @('Registry','Shortcut')) {
            $syntheticRecords.Add([pscustomobject][ordered]@{
                Id=('{0}-{1}' -f $index,$source); Name=$name; Version=('1.0.{0}' -f $index); Publisher='VIETIT Fixture'
                InstallDate=''; InstallLocation=$location; DisplayIcon=''; UninstallString=''; RegistryPath=''
                Scope='Machine64'; Architecture='64-bit'; SourceKind=$source; RepresentativePath=(Join-Path $location 'fixture.exe')
                SourceDetail=$source; PackageId=''; SignaturePublisher=''; FileVersion=''; DiscoverySources=@($source)
                IsSystemComponent=$false; SystemComponentReason=''; ReleaseType=''; NonRemovable=$false
            })
        }
    }
    $mergeWatch = [Diagnostics.Stopwatch]::StartNew()
    $syntheticMerged = @(Merge-ToolSoftwareInventoryRecords -Records $syntheticRecords.ToArray())
    $mergeWatch.Stop()
    if ($syntheticMerged.Count -ne 240 -or @($syntheticMerged | Where-Object { [int]$_.MergedRecordCount -ne 2 }).Count -gt 0) {
        Add-Failure 'Optimized software merge changed the logical deduplication result.'
    }
    if ($mergeWatch.Elapsed.TotalSeconds -gt 12) {
        Add-Failure ('Optimized software merge exceeded the bounded regression budget: {0:N2}s.' -f $mergeWatch.Elapsed.TotalSeconds)
    }

    $inventoryText = Get-Content -LiteralPath (Join-Path $root 'kiem-tra-cau-hinh-ban-quyen.ps1') -Raw -Encoding UTF8
    $cleanupText = Get-Content -LiteralPath (Join-Path $root 'windows-license-compliance-cleanup.ps1') -Raw -Encoding UTF8
    $softwareInventoryText = Get-Content -LiteralPath $softwareInventoryPath -Raw -Encoding UTF8
    foreach ($pattern in @('Get-ToolOptimizedOfficeOsppPaths','Invoke-ToolParallelOfficeStatus')) {
        if ($inventoryText -notmatch $pattern -or $cleanupText -notmatch $pattern) {
            Add-Failure "Office flow does not use optimization helper: $pattern"
        }
    }
    if ($inventoryText -notmatch 'Find-ToolPatternFilesParallel') {
        Add-Failure 'Inventory flow does not use parallel per-root file scanning.'
    }
    if ($inventoryText -notmatch 'Text\.StringBuilder' -or $inventoryText -notmatch 'reportPresentationCache' -or
        $inventoryText -notmatch 'reportLiteralTranslationMaps' -or $inventoryText -notmatch 'scheduledTaskObjectsAll') {
        Add-Failure 'Large software reports do not use bounded table construction and presentation-text caching.'
    }
    foreach ($requiredToken in @(
        'Get-ToolSoftwareSignatureStatesParallel','ToolSoftwareDeepDirectoryCache','EnumerateFileSystemInfos',
        'CreateRunspacePool(1, [Math]::Min(8','ProcessorCount','New-ToolSoftwareMergeDescriptor','quickSignatureResults',
        'NameBucket','clustersByNameBucket','externalEvidenceByApplication','externalEvidenceByVendor','resultData'
    )) {
        if ($softwareInventoryText -notmatch [regex]::Escape($requiredToken)) {
            Add-Failure "Universal deep scan is missing the speed contract: $requiredToken"
        }
    }
    if ($softwareInventoryText -notmatch 'desiredSignatureLimit\s*=\s*if\s*\([^\r\n]+\)\s*\{\s*350\s*\}\s*elseif\s*\([^\r\n]+\)\s*\{\s*18\s*\}\s*elseif\s*\([^\r\n]+\)\s*\{\s*4\s*\}\s*else\s*\{\s*1\s*\}') {
        Add-Failure 'Adaptive per-application signature profile is not 350/18/4/1.'
    }
} catch {
    $failureDetail = $_.Exception.Message
    if (-not [string]::IsNullOrWhiteSpace([string]$_.ScriptStackTrace)) {
        $failureDetail += "`n" + [string]$_.ScriptStackTrace
    }
    Add-Failure $failureDetail
} finally {
    if ([string]::IsNullOrWhiteSpace($previousScanSettingsPath)) {
        Remove-Item Env:TOOL_SCAN_SETTINGS_PATH -ErrorAction SilentlyContinue
    } else {
        $env:TOOL_SCAN_SETTINGS_PATH = $previousScanSettingsPath
    }
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolvedTemp).StartsWith('VietLicenSure-v5.0-performance-', [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-PERFORMANCE: FAILED ($($failures.Count) errors)"
    exit 1
}

Write-Host 'VERIFY-PERFORMANCE: PASSED' -ForegroundColor Green
exit 0
