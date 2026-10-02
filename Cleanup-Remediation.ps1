# VietLicenSure v5.0 - dot-sourced function library
# Extracted mechanically from windows-license-compliance-cleanup.ps1; contains function definitions only.
# Keep this file beside its compatible entrypoint.

function Write-DecisionData {
    param([string]$Path, $Data)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $parent = Split-Path -Parent $Path
        if ($parent) { Ensure-Dir $parent }
        $Data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    } catch {
        Write-Warning (Get-CleanupText "cleanupReport.output.decisionWriteFailed" @($_.Exception.Message))
    }
}

function Invoke-ScanSourceRepair {
    $actions = New-Object System.Collections.Generic.List[string]
    $checks = New-Object System.Collections.Generic.List[object]
    $guidance = New-Object System.Collections.Generic.List[string]
    $serviceStateBefore = New-Object System.Collections.Generic.List[object]
    $serviceStateAfter = New-Object System.Collections.Generic.List[object]
    $startedServices = New-Object System.Collections.Generic.List[string]

    function Add-RepairCheck([string]$Name, [string]$StatusCode, [string]$Detail) {
        $checks.Add([pscustomobject]@{
            Name = $Name
            StatusCode = $StatusCode
            Status = Get-CleanupText ("cleanupReport.status." + $StatusCode.ToLowerInvariant())
            Detail = $Detail
        })
    }

    function Get-ServiceStateSnapshot([string]$Name, [string]$DisplayName) {
        $service = Get-Service -Name $Name -ErrorAction Stop
        $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
        $registry = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
        $startValue = [int]$registry.Start
        $startMode = switch ($startValue) {
            0 { "Boot" }
            1 { "System" }
            2 { if ([int]$registry.DelayedAutoStart -eq 1) { "AutomaticDelayed" } else { "Automatic" } }
            3 { "Manual" }
            4 { "Disabled" }
            default { "Unknown:$startValue" }
        }
        return [pscustomobject][ordered]@{
            Name = $Name
            DisplayName = $DisplayName
            Status = [string]$service.Status
            WasRunning = [bool]($service.Status -eq "Running")
            StartValue = $startValue
            StartMode = $startMode
        }
    }

    function Repair-ServiceState($Policy) {
        $name = [string]$Policy.Name
        $displayName = [string]$Policy.DisplayName
        try {
            $before = Get-ServiceStateSnapshot -Name $name -DisplayName $displayName
            $serviceStateBefore.Add($before)
            $svc = Get-Service -Name $name -ErrorAction Stop
            if ($svc.Status -ne "Running") {
                if ($before.StartMode -eq "Disabled") {
                    Add-RepairCheck $displayName "Fail" (Get-CleanupText "cleanupReport.repair.serviceDisabled" @($name))
                    $actions.Add((Get-CleanupText "cleanupReport.repair.action.serviceDisabled" @($name)))
                    return
                }
                if (-not [bool]$Policy.AllowStart) {
                    Add-RepairCheck $displayName "Fail" (Get-CleanupText "cleanupReport.repair.startDisallowed" @($name))
                    return
                }
                Start-Service -Name $name -ErrorAction Stop
                $startedServices.Add($name)
                $actions.Add((Get-CleanupText "cleanupReport.repair.action.serviceStarted" @($name)))
                $svc = Get-Service -Name $name -ErrorAction Stop
            }
            Add-RepairCheck $displayName "Pass" (Get-CleanupText "cleanupReport.repair.serviceState" @($name, $svc.Status, $before.StartMode))
        } catch {
            Add-RepairCheck $displayName "Fail" (Get-CleanupText "cleanupReport.repair.serviceFailed" @($name, $_.Exception.Message))
            $actions.Add((Get-CleanupText "cleanupReport.repair.action.serviceFailed" @($name, $_.Exception.Message)))
        }
    }

    $actions.Add((Get-CleanupText "cleanupReport.repair.action.started"))
    $actions.Add((Get-CleanupText "cleanupReport.repair.action.policy"))
    foreach ($servicePolicy in @(Get-ToolScanSourceServicePolicy)) { Repair-ServiceState -Policy $servicePolicy }

    Reset-ScanCaches
    $script:ScanWarnings.Clear()
    $script:WindowsLicenseSourceNote = ""

    $products = @(Get-WindowsLicenseProducts)
    if ($products.Count -gt 0) {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.windowsLicense") "Pass" (Get-CleanupText "cleanupReport.repair.windowsLicenseRead" @($products.Count))
    } elseif ($script:WindowsLicenseSourceNote) {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.windowsLicense") "Pass" $script:WindowsLicenseSourceNote
    } else {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.windowsLicense") "Fail" (Get-CleanupText "cleanupReport.repair.windowsLicenseUnreadable")
    }

    $tasks = @(Get-CompatibleScheduledTaskRecords -NoCache)
    if ($tasks.Count -gt 0) {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.scheduledTasks") "Pass" (Get-CleanupText "cleanupReport.repair.tasksRead" @($tasks.Count))
    } else {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.scheduledTasks") "Fail" (Get-CleanupText "cleanupReport.repair.tasksUnreadable")
    }

    $services = @(Safe-Cim -ClassName Win32_Service -CriticalLabel (Get-CleanupText "cleanupReport.scan.servicesCritical") -NoCache)
    if ($services.Count -gt 0) {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.windowsServices") "Pass" (Get-CleanupText "cleanupReport.repair.servicesRead" @($services.Count))
    } else {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.windowsServices") "Fail" (Get-CleanupText "cleanupReport.repair.servicesUnreadable")
    }

    foreach ($toolName in @("cscript.exe", "schtasks.exe")) {
        try {
            $toolPath = Get-ToolNativeSystemPath $toolName
            if (Test-Path -LiteralPath $toolPath -PathType Leaf) {
                Add-RepairCheck $toolName "Pass" $toolPath
            } else {
                Add-RepairCheck $toolName "Fail" (Get-CleanupText "cleanupReport.repair.toolMissing")
            }
        } catch {
            Add-RepairCheck $toolName "Fail" $_.Exception.Message
        }
    }

    $warnings = @($script:ScanWarnings | Select-Object -Unique)
    foreach ($warning in $warnings) { $actions.Add((Get-CleanupText "cleanupReport.repair.action.postWarning" @($warning))) }
    $recheckPassed = [bool]($warnings.Count -eq 0 -and @($checks | Where-Object { $_.StatusCode -eq "Fail" }).Count -eq 0)
    $rollbackApplied = $false
    if ($recheckPassed) {
        $guidance.Add((Get-CleanupText "cleanupReport.repair.guidance.pass"))
    } else {
        foreach ($serviceName in @($startedServices)) {
            try {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.repair.action.rollback" @($serviceName)))
                $rollbackApplied = $true
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.repair.action.rollbackFailed" @($serviceName, $_.Exception.Message)))
            }
        }
        $guidance.Add((Get-CleanupText "cleanupReport.repair.guidance.fail"))
        $guidance.Add((Get-CleanupText "cleanupReport.repair.guidance.partialKey"))
    }

    foreach ($servicePolicy in @(Get-ToolScanSourceServicePolicy)) {
        try { $serviceStateAfter.Add((Get-ServiceStateSnapshot -Name ([string]$servicePolicy.Name) -DisplayName ([string]$servicePolicy.DisplayName))) }
        catch { $serviceStateAfter.Add([pscustomobject]@{ Name=[string]$servicePolicy.Name; DisplayName=[string]$servicePolicy.DisplayName; Status=(Get-CleanupText "common.unknown"); StartMode=(Get-CleanupText "common.unknown"); Error=$_.Exception.Message }) }
    }

    return (New-ToolReportEnvelope -ReportKind "ScanSourceRepair" -ToolVersion "5.0" -Data ([ordered]@{
        RepairAttempted = $true
        RecheckPassed = $recheckPassed
        StartupTypeChanged = $false
        RollbackApplied = $rollbackApplied
        ScanWarningCount = [int]$warnings.Count
        ScanWarnings = $warnings
        Checks = @($checks)
        Actions = @($actions)
        HandlingGuidance = @($guidance)
        ServiceStateBefore = $serviceStateBefore.ToArray()
        ServiceStateAfter = $serviceStateAfter.ToArray()
        ReportPath = ""
    }))
}

function Write-Report {
    param($Path, $Products, $Findings, $Decision, $Actions, $History = @(), $Verification = $null, $ThirdPartyApplications = @(), $ThirdPartyEvidence = @(), $ThirdPartyCandidates = @(), $SoftwareDeepScanMetadata = $null, $CleanupItems = @(), $ScanSnapshot = $null)
    $lines = New-Object System.Collections.Generic.List[string]
    $yes = Get-CleanupText "common.yes"
    $no = Get-CleanupText "common.no"
    $lines.Add((Get-CleanupText "cleanupReport.report.title"))
    $lines.Add((Get-CleanupText "cleanupReport.report.computer" @($env:COMPUTERNAME)))
    $lines.Add((Get-CleanupText "cleanupReport.report.user" @($env:USERNAME)))
    $lines.Add((Get-CleanupText "cleanupReport.report.time" @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))))
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.report.initialDecision" @($Decision.Decision)))
    $lines.Add((Get-CleanupText "cleanupReport.report.initialReason" @($Decision.Reason)))
    if ($script:WindowsLicenseSourceNote) { $lines.Add((Get-CleanupText "cleanupReport.report.windowsSourceNote" @($script:WindowsLicenseSourceNote))) }
    $lines.Add((Get-CleanupText "cleanupReport.report.remediationRequested" @($(if ($Remediate) { $yes } else { $no }))))
    $lines.Add((Get-CleanupText "cleanupReport.report.deepCleanup" @($(if ($DeepClean) { $yes } else { $no }))))
    $lines.Add((Get-CleanupText "cleanupReport.report.unapprovedKmsNoncompliant" @($(if ($TreatUnapprovedKmsAsNonCompliant) { $yes } else { $no }))))
    if ($ApprovedKmsServers.Count -gt 0) {
        $lines.Add((Get-CleanupText "cleanupReport.report.approvedKmsServers" @($ApprovedKmsServers -join ', ')))
    } else {
        $lines.Add((Get-CleanupText "cleanupReport.report.approvedKmsServers" @((Get-CleanupText "cleanupReport.value.notConfigured"))))
    }
    $lines.Add((Get-CleanupText "cleanupReport.report.kmsConfigFile" @($approvedKmsConfig.Path)))
    $lines.Add((Get-CleanupText "cleanupReport.report.kmsLineCounts" @($approvedKmsConfig.Valid.Count, $approvedKmsConfig.Invalid.Count)))
    if ($approvedKmsConfig.Warning) { $lines.Add((Get-CleanupText "cleanupReport.report.kmsConfigWarning" @($approvedKmsConfig.Warning))) }
    $lines.Add("")
    if ($Verification) {
        $lines.Add((Get-CleanupText "cleanupReport.report.verificationHeading"))
        $lines.Add((Get-CleanupText "cleanupReport.report.ready" @($(if ($Verification.ReadyForOfficialActivation) { $yes } else { $no }))))
        $lines.Add((Get-CleanupText "cleanupReport.report.conclusion" @($Verification.Conclusion)))
        $lines.Add((Get-CleanupText "cleanupReport.report.activeActivatorCount" @($Verification.ActiveActivatorFindingCount)))
        $lines.Add((Get-CleanupText "cleanupReport.report.windowsKmsCount" @($Verification.UnapprovedWindowsKmsCount)))
        $lines.Add((Get-CleanupText "cleanupReport.report.officeKmsCount" @($Verification.UnapprovedOfficeKmsCount)))
        $lines.Add((Get-CleanupText "cleanupReport.report.residueCount" @($Verification.ConfigurationResidueCount)))
        $lines.Add((Get-CleanupText "cleanupReport.report.historyCount" @($Verification.HistoryFindingCount)))
        $lines.Add((Get-CleanupText "cleanupReport.report.scanWarningCount" @($Verification.ScanWarningCount)))
        foreach ($scanWarning in @($Verification.ScanWarnings)) {
            $lines.Add((Get-CleanupText "cleanupReport.report.scanWarning" @($scanWarning)))
        }
        $lines.Add((Get-CleanupText "cleanupReport.report.scope" @($Verification.ScopeNote)))
        $lines.Add("")
        $lines.Add((Get-CleanupText "cleanupReport.report.guidanceHeading"))
        foreach ($step in @($Verification.HandlingGuidance)) {
            $lines.Add("- $step")
        }
        if (@($Verification.HandlingGuidance).Count -eq 0) {
            $lines.Add((Get-CleanupText "cleanupReport.report.noAdditionalAction"))
        }
        $lines.Add("")
        $lines.Add((Get-CleanupText "cleanupReport.report.readinessReviewCount" @($Verification.ReadinessReviewCount)))
        foreach ($c in @($Verification.ReadinessChecks)) {
            $lines.Add("- [$($c.Status)] $($c.Name): $($c.Detail)")
        }
        foreach ($r in @($Verification.Residues)) {
            $lines.Add((Get-CleanupText "cleanupReport.report.residue" @($r.Type, $r.Name, $r.Location, $r.Value)))
        }
        $lines.Add("")
    }
    $lines.Add((Get-CleanupText "cleanupReport.report.windowsLicenses"))
    foreach ($p in $Products) {
        $lines.Add((Get-CleanupText "cleanupReport.report.name" @($p.Name)))
        $lines.Add((Get-CleanupText "cleanupReport.report.description" @($p.Description)))
        $lines.Add((Get-CleanupText "cleanupReport.report.status" @((Status-Text $p.LicenseStatus))))
        $lines.Add((Get-CleanupText "cleanupReport.report.channel" @((Get-LicenseChannel $p))))
        $lines.Add((Get-CleanupText "cleanupReport.report.last5" @($p.PartialProductKey)))
        $lines.Add((Get-CleanupText "cleanupReport.report.kmsServer" @($p.KeyManagementServiceMachine)))
    }
    if ($Products.Count -eq 0) {
        $lines.Add("- " + (Get-CleanupText "common.none"))
    }
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.report.activatorFindings"))
    foreach ($f in $Findings) {
        $lines.Add("- [$($f.Type)] $($f.Name)")
        $lines.Add((Get-CleanupText "cleanupReport.report.location" @($f.Location)))
        $lines.Add((Get-CleanupText "cleanupReport.report.plannedAction" @($f.Action)))
    }
    if ($Findings.Count -eq 0) {
        $lines.Add("- " + (Get-CleanupText "common.none"))
    }
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.heading"))
    if ($SoftwareDeepScanMetadata -and [bool]$SoftwareDeepScanMetadata.Enabled) {
        $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.deepSummary" @(
            $(if ([bool]$SoftwareDeepScanMetadata.Complete) { $yes } else { $no }),
            [int]$SoftwareDeepScanMetadata.ApplicationsScanned,
            [int]$SoftwareDeepScanMetadata.ApplicationsSkipped,
            [int]$SoftwareDeepScanMetadata.RelevantFiles,
            [int]$SoftwareDeepScanMetadata.SignatureChecks,
            [int]$SoftwareDeepScanMetadata.HashChecks,
            [int]$SoftwareDeepScanMetadata.AccessWarningCount)))
        $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.deepLimits" @(
            $(if ([bool]$SoftwareDeepScanMetadata.IsAdministrator) { $yes } else { $no }),
            $(if ([bool]$SoftwareDeepScanMetadata.TimeLimitReached) { $yes } else { $no }),
            $(if ([bool]$SoftwareDeepScanMetadata.EntryLimitReached) { $yes } else { $no }),
            $(if ([bool]$SoftwareDeepScanMetadata.SignatureLimitReached) { $yes } else { $no }),
            $(if ([bool]$SoftwareDeepScanMetadata.HashLimitReached) { $yes } else { $no }),
            [int]$SoftwareDeepScanMetadata.DurationMilliseconds)))
    }
    $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.summary" @(@($ThirdPartyApplications).Count, @($ThirdPartyEvidence).Count, @($ThirdPartyCandidates).Count, @($ThirdPartyCandidates | Where-Object { [bool]$_.AutoEligible }).Count)))
    foreach ($app in @($ThirdPartyApplications)) {
        $evidenceSummary = @($app.Evidence | ForEach-Object { [string]$_.Code } | Select-Object -Unique) -join ', '
        if ([string]::IsNullOrWhiteSpace($evidenceSummary)) { $evidenceSummary = Get-CleanupText 'common.none' }
        $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.applicationExtended" @($app.Name, $app.Version, $app.Publisher, $app.LicenseModel, $app.TechnicalStatus, $app.Confidence, $evidenceSummary, $(if ([bool]$app.RemediationSupported) { $yes } else { $no }), [string]$app.PresenceState)))
    }
    if (@($ThirdPartyApplications).Count -eq 0) { $lines.Add("- " + (Get-CleanupText "common.none")) }
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.evidenceHeading"))
    foreach ($item in @($ThirdPartyEvidence)) {
        $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.evidence" @($item.VendorScope, $item.Type, $item.Name, $item.Location, $item.Detail)))
    }
    if (@($ThirdPartyEvidence).Count -eq 0) { $lines.Add("- " + (Get-CleanupText "common.none")) }
    $lines.Add("")
    $lines.Add((Get-CleanupText 'cleanupReport.report.cleanupItemsHeading'))
    $candidateSetHash = if ($ScanSnapshot -and $ScanSnapshot.PSObject.Properties['CandidateSetSha256']) {
        [string]$ScanSnapshot.CandidateSetSha256
    } else { Get-CleanupCandidateSetSha256 -Candidates @($CleanupItems) }
    $lines.Add((Get-CleanupText 'cleanupReport.report.cleanupItemsSummary' @(@($CleanupItems).Count, $candidateSetHash)))
    foreach ($cleanupItem in @($CleanupItems | Sort-Object Id)) {
        $lines.Add((Get-CleanupText 'cleanupReport.report.cleanupItem' @(
            [string]$cleanupItem.Id,
            [string]$cleanupItem.ComponentScope,
            [string]$cleanupItem.Type,
            [string]$cleanupItem.Kind,
            [string]$cleanupItem.Name,
            [string]$cleanupItem.Location,
            [string]$cleanupItem.Detail,
            $(if ($cleanupItem.PSObject.Properties['GuidanceOnly'] -and [bool]$cleanupItem.GuidanceOnly) { $yes } else { $no }),
            [string]$cleanupItem.SnapshotSha256)))
        foreach ($planItem in @($cleanupItem.PlanItems)) {
            $lines.Add((Get-CleanupText 'cleanupReport.report.cleanupPlanItem' @(
                [string]$planItem.Type, [string]$planItem.Kind, [string]$planItem.Name,
                [string]$planItem.Location, [string]$planItem.Detail)))
        }
    }
    if (@($CleanupItems).Count -eq 0) { $lines.Add('- ' + (Get-CleanupText 'common.none')) }
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.report.historyHeading"))
    $lines.Add((Get-CleanupText "cleanupReport.report.historyNote"))
    foreach ($h in @($History)) {
        $lines.Add((Get-CleanupText "cleanupReport.report.historyEvent" @($h.Time, $h.Source, $h.EventId)))
        $lines.Add((Get-CleanupText "cleanupReport.report.redactedEvidence" @($h.Evidence)))
    }
    if (@($History).Count -eq 0) {
        $lines.Add((Get-CleanupText "cleanupReport.report.noHistory"))
    }
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.report.actions"))
    foreach ($a in $Actions) {
        $lines.Add("- $a")
    }
    if ($Actions.Count -eq 0) {
        $lines.Add("- " + (Get-CleanupText "common.none"))
    }
    @($lines | ForEach-Object { Protect-CleanupReportText $_ }) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-OfficeOsppCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$SuccessPattern = ""
    )

    try {
        $output = (& $nativeCscriptPath //nologo $Path @Arguments 2>&1) -join "`n"
        $exitCode = [int]$LASTEXITCODE
        $output = ([string]$output) -replace "`0", ""
        $failurePattern = '(?im)^\s*(?:ERROR CODE|ERROR DESCRIPTION)\s*:|\b(?:failed|failure|cannot|could not)\b'
        $success = [bool]($exitCode -eq 0 -and $output -notmatch $failurePattern -and (
            [string]::IsNullOrWhiteSpace($SuccessPattern) -or $output -match $SuccessPattern
        ))
        $meaningful = @($output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object {
            $_ -and $_ -notmatch '^-{5,}$|^---Processing|^---Exiting'
        })
        $summary = ($meaningful | Select-Object -First 4) -join ' | '
        if ([string]::IsNullOrWhiteSpace($summary)) { $summary = Get-CleanupText "cleanupReport.command.emptyExitCode" @($exitCode) }
        if ($summary.Length -gt 420) { $summary = $summary.Substring(0, 417) + '...' }
        return [pscustomobject]@{ Success=$success; ExitCode=$exitCode; Summary=$summary; Output=$output }
    } catch {
        return [pscustomobject]@{ Success=$false; ExitCode=-1; Summary=$_.Exception.Message; Output="ERROR: $($_.Exception.Message)" }
    }
}

function Get-OfficeLicenseProbeForPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Coverage='Unavailable'; Entries=@(); Path=[string]$Path }
    }
    $result = @(Invoke-ToolParallelOfficeStatus -CscriptPath $nativeCscriptPath -OsppPaths @($Path) -ThrottleLimit 1 | Select-Object -First 1)
    if ($result.Count -ne 1) {
        return [pscustomobject]@{ Coverage='Failed'; Entries=@(); Path=[string]$Path }
    }
    $blockAssessment = Get-OfficeOsppSkuBlockAssessment -StatusText ([string]$result[0].Output) -Path ([string]$Path)
    $entrySet = @($blockAssessment.Entries)
    $complete = [bool](
        -not [bool]$result[0].UsedFallback -and
        -not [bool]$result[0].TimedOut -and
        [bool]$result[0].Readable -and
        [int]$result[0].PrimaryExitCode -eq 0 -and
        $entrySet.Count -gt 0 -and
        [bool]$blockAssessment.Complete
    )
    return [pscustomobject]@{
        Coverage=$(if ($complete) { 'Complete' } else { 'Partial' })
        Entries=@($entrySet); Path=[string]$Path
        SkuBlockCount=[int]$blockAssessment.SkuBlockCount
        FullyParsedSkuBlockCount=[int]$blockAssessment.FullyParsedSkuBlockCount
        IncompleteSkuBlockCount=[int]$blockAssessment.IncompleteSkuBlockCount
    }
}

function Get-OfficeLicenseProbeForPathBounded {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateRange(1,3)][int]$MaximumAttempts = 3,
        [ValidateRange(0,1000)][int]$DelayMilliseconds = 200
    )

    $lastProbe = $null
    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        $lastProbe = Get-OfficeLicenseProbeForPath -Path $Path
        if ([string]$lastProbe.Coverage -eq 'Complete') {
            $lastProbe | Add-Member -NotePropertyName AttemptCount -NotePropertyValue $attempt -Force
            return $lastProbe
        }
        if ($attempt -lt $MaximumAttempts -and $DelayMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
    if ($null -eq $lastProbe) { $lastProbe = [pscustomobject]@{ Coverage='Failed'; Entries=@(); Path=$Path } }
    $lastProbe | Add-Member -NotePropertyName AttemptCount -NotePropertyValue $MaximumAttempts -Force
    return $lastProbe
}

function Invoke-OfficeLicenseServiceRefresh {
    param([ValidateRange(1,2)][int]$MaximumAttempts = 1)

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            $service = Get-Service -Name 'osppsvc' -ErrorAction Stop
            if ($service.Status -eq 'Running') {
                Restart-Service -Name 'osppsvc' -Force -ErrorAction Stop
            } else {
                Start-Service -Name 'osppsvc' -ErrorAction Stop
            }
            return [pscustomobject]@{ Success=$true; AttemptCount=$attempt; Error='' }
        } catch {
            if ($attempt -eq $MaximumAttempts) {
                return [pscustomobject]@{ Success=$false; AttemptCount=$attempt; Error=[string]$_.Exception.Message }
            }
        }
    }
}

function Test-WindowsLicenseRemediationTarget {
    param(
        [Parameter(Mandatory = $true)]$TargetProduct,
        $CurrentProducts = @()
    )

    $activationId = ([string]$TargetProduct.ID).Trim()
    if ([string]::IsNullOrWhiteSpace($activationId)) {
        return [pscustomobject]@{ Allowed=$false; Reason='MissingActivationId'; CurrentProduct=$null }
    }

    $matches = @($CurrentProducts | Where-Object {
        [string]::Equals(([string]$_.ID).Trim(), $activationId, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -ne 1) {
        return [pscustomobject]@{ Allowed=$false; Reason='ActivationIdMissingOrAmbiguous'; CurrentProduct=$null }
    }

    $current = $matches[0]
    $expectedChannel = Get-LicenseChannel $TargetProduct
    $currentChannel = Get-LicenseChannel $current
    $expectedPartialKey = ([string]$TargetProduct.PartialProductKey).Trim().ToUpperInvariant()
    $currentPartialKey = ([string]$current.PartialProductKey).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($expectedPartialKey)) {
        return [pscustomobject]@{ Allowed=$false; Reason='MissingExpectedPartialProductKey'; CurrentProduct=$current }
    }
    if (-not [string]::Equals($expectedPartialKey, $currentPartialKey, [StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Allowed=$false; Reason='PartialProductKeyChanged'; CurrentProduct=$current }
    }

    if ($expectedChannel -eq 'KMS') {
        $expectedServer = ([string]$TargetProduct.KeyManagementServiceMachine).Trim()
        $currentServer = ([string]$current.KeyManagementServiceMachine).Trim()
        if ($currentChannel -ne 'KMS' -or (Test-ApprovedKms -Server $currentServer)) {
            return [pscustomobject]@{ Allowed=$false; Reason='TargetNoLongerUnapprovedKms'; CurrentProduct=$current }
        }
        if (-not [string]::Equals($expectedServer, $currentServer, [StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ Allowed=$false; Reason='KmsServerChanged'; CurrentProduct=$current }
        }
    } elseif ([int]$TargetProduct.LicenseStatus -eq 4 -and -not [string]::IsNullOrWhiteSpace($expectedPartialKey)) {
        if ([int]$current.LicenseStatus -ne 4 -or $currentChannel -eq 'KMS') {
            return [pscustomobject]@{ Allowed=$false; Reason='TargetNoLongerNonGenuine'; CurrentProduct=$current }
        }
    } else {
        return [pscustomobject]@{ Allowed=$false; Reason='TargetWasNotRemediationEligible'; CurrentProduct=$current }
    }

    return [pscustomobject]@{ Allowed=$true; Reason=''; CurrentProduct=$current }
}

function Test-WindowsKmsOverrideRemediationTarget {
    param([Parameter(Mandatory = $true)]$Candidate)

    $expectedPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
    $path = ([string]$Candidate.Location).Trim()
    $expectedServer = ([string]$Candidate.ExpectedRegistryValue).Trim()
    if ([string]$Candidate.Kind -ne 'KmsOverride' -or
        [string]$Candidate.Provider -ne 'WindowsSPP' -or
        [string]$Candidate.RegistryValueName -ne 'KeyManagementServiceName' -or
        -not [string]::Equals($path, $expectedPath, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::IsNullOrWhiteSpace($expectedServer)) {
        return [pscustomobject]@{ Allowed=$false; AlreadyClean=$false; Reason='InvalidKmsOverrideIdentity'; CurrentServer='' }
    }

    try {
        $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        $currentServer = ([string]$item.KeyManagementServiceName).Trim()
    } catch {
        return [pscustomobject]@{ Allowed=$false; AlreadyClean=$false; Reason='KmsOverrideProbeFailed'; CurrentServer='' }
    }
    if ([string]::IsNullOrWhiteSpace($currentServer)) {
        return [pscustomobject]@{ Allowed=$false; AlreadyClean=$true; Reason='KmsOverrideAlreadyAbsent'; CurrentServer='' }
    }
    if (-not [string]::Equals($currentServer, $expectedServer, [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ Allowed=$false; AlreadyClean=$false; Reason='KmsOverrideChanged'; CurrentServer=$currentServer }
    }
    if (Test-ApprovedKms -Server $currentServer) {
        return [pscustomobject]@{ Allowed=$false; AlreadyClean=$false; Reason='ApprovedInternalKms'; CurrentServer=$currentServer }
    }
    return [pscustomobject]@{ Allowed=$true; AlreadyClean=$false; Reason=''; CurrentServer=$currentServer }
}

function Test-OfficeKmsHostOverrideTarget {
    param([Parameter(Mandatory = $true)][string]$Path)

    $hostIdentity = Get-OfficeKmsHostOverrideIdentity -Path $Path
    if ([string]::IsNullOrWhiteSpace($hostIdentity)) {
        return [pscustomobject]@{ Allowed=$false; AlreadyClean=$false; Reason='MissingOsppPath'; HostIdentity=''; Entries=@() }
    }
    $probe = Get-OfficeLicenseProbeForPathBounded -Path $Path
    if ([string]$probe.Coverage -ne 'Complete') {
        return [pscustomobject]@{ Allowed=$false; AlreadyClean=$false; Reason=('Probe' + [string]$probe.Coverage); HostIdentity=$hostIdentity; Entries=@($probe.Entries) }
    }
    $approvedHostEntries = @($probe.Entries | Where-Object {
        [string]$_.Channel -eq 'KMS' -and -not [string]::IsNullOrWhiteSpace([string]$_.Server) -and
        (Test-ApprovedKms -Server ([string]$_.Server))
    })
    if ($approvedHostEntries.Count -gt 0) {
        return [pscustomobject]@{ Allowed=$false; AlreadyClean=$false; Reason='ApprovedInternalKmsSharesOsppPath'; HostIdentity=$hostIdentity; Entries=@($probe.Entries) }
    }
    $unapprovedHostEntries = @($probe.Entries | Where-Object {
        [string]$_.Channel -eq 'KMS' -and -not [string]::IsNullOrWhiteSpace([string]$_.Server) -and
        -not (Test-ApprovedKms -Server ([string]$_.Server))
    })
    if ($unapprovedHostEntries.Count -eq 0) {
        return [pscustomobject]@{ Allowed=$false; AlreadyClean=$true; Reason='HostOverrideAlreadyAbsent'; HostIdentity=$hostIdentity; Entries=@($probe.Entries) }
    }
    return [pscustomobject]@{ Allowed=$true; AlreadyClean=$false; Reason=''; HostIdentity=$hostIdentity; Entries=@($probe.Entries) }
}

function Test-OfficeVolumeOrMondoRepairRequired {
    param(
        $LicenseEntries = @(),
        [string]$OfficialLicenseState = 'Unverified',
        [bool]$DirectCrackEvidenceRemaining = $false
    )

    $volumeOrMondo = [bool](@($LicenseEntries | Where-Object {
        (([string]$_.LicenseName) + ' ' + ([string]$_.Description) + ' ' + ([string]$_.Channel)) -match '(?i)\b(?:VOLUME|Mondo)\b|VOLUME_KMSCLIENT'
    }).Count -gt 0)
    return [bool]($volumeOrMondo -and ($DirectCrackEvidenceRemaining -or $OfficialLicenseState -notin @('Unactivated','Trial')))
}

function Test-OfficeKmsRemediationTarget {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [string[]]$SelectedTargetIds = @()
    )

    $targetIdentity = Get-OfficeKmsTargetIdentity -Entry $Entry
    $path = [string]$Entry.Path
    $pathKey = Get-OfficeKmsPathKey -Path $path
    if ([string]::IsNullOrWhiteSpace($targetIdentity) -or [string]::IsNullOrWhiteSpace($pathKey)) {
        return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='MissingPathSkuOrLast5'; TargetIdentity=''; Entries=@() }
    }

    $selectedTargetSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($selectedTargetId in @($SelectedTargetIds)) {
        $value = ([string]$selectedTargetId).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$selectedTargetSet.Add($value) }
    }
    # Legacy selections that contain only SKU ID intentionally do not match.
    # They are rejected rather than guessing which OSPP/key instance was meant.
    if (-not $selectedTargetSet.Contains($targetIdentity)) {
        return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='TargetNotSelectedByCompositeIdentity'; TargetIdentity=$targetIdentity; Entries=@() }
    }

    $probe = Get-OfficeLicenseProbeForPath -Path $path
    if ([string]$probe.Coverage -ne 'Complete') {
        return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason=('Probe' + [string]$probe.Coverage); TargetIdentity=$targetIdentity; Entries=@($probe.Entries) }
    }
    $matches = @($probe.Entries | Where-Object {
        [string]::Equals((Get-OfficeKmsTargetIdentity -Entry $_), $targetIdentity, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -ne 1) {
        return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='SkuOrKeyChanged'; TargetIdentity=$targetIdentity; Entries=@($probe.Entries) }
    }
    $target = $matches[0]
    if ([string]$target.Channel -ne 'KMS' -or (Test-ApprovedKms -Server ([string]$target.Server))) {
        return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='TargetNoLongerUnapprovedKms'; TargetIdentity=$targetIdentity; Entries=@($probe.Entries) }
    }
    # /unpkey:last5 is key-scoped. A genuine SKU sharing this OSPP instance is
    # preserved and does not block removal of a different uniquely identified
    # unwanted key. Path-wide /remhst remains protected separately.
    if (@($probe.Entries | Where-Object {
        [string]$_.Channel -eq 'KMS' -and
        [string]::Equals(([string]$_.Last5).Trim(), ([string]$target.Last5).Trim(), [StringComparison]::OrdinalIgnoreCase)
    }).Count -ne 1) {
        return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='Last5NotUniqueOnOsppPath'; TargetIdentity=$targetIdentity; Entries=@($probe.Entries) }
    }

    # A single validated target is never sufficient to alter a path-wide KMS
    # override.  Invoke-Remediation validates every current KMS target first.
    return [pscustomobject]@{ Allowed=$true; RemhstSafe=$false; Reason=''; TargetIdentity=$targetIdentity; Entries=@($probe.Entries) }
}

function Test-OfficeKmsRemediationPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$SelectedTargetIds = @(),
        [string[]]$AllowedTargetIds = @()
    )

    $pathKey = Get-OfficeKmsPathKey -Path $Path
    if ([string]::IsNullOrWhiteSpace($pathKey)) {
        return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='MissingOsppPath'; Entries=@() }
    }

    $selectedTargetSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($selectedTargetId in @($SelectedTargetIds)) {
        $value = ([string]$selectedTargetId).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$selectedTargetSet.Add($value) }
    }
    $allowedTargetSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($allowedTargetId in @($AllowedTargetIds)) {
        $value = ([string]$allowedTargetId).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$allowedTargetSet.Add($value) }
    }

    $probe = Get-OfficeLicenseProbeForPath -Path $Path
    if ([string]$probe.Coverage -ne 'Complete') {
        return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason=('Probe' + [string]$probe.Coverage); Entries=@($probe.Entries) }
    }
    $currentKmsEntries = @($probe.Entries | Where-Object {
        [string]$_.Channel -eq 'KMS' -and
        [string]::Equals((Get-OfficeKmsPathKey -Path ([string]$_.Path)), $pathKey, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($currentKmsEntries.Count -eq 0) {
        return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='NoKmsOnOsppPath'; Entries=@($probe.Entries) }
    }

    $currentTargetSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($currentEntry in $currentKmsEntries) {
        $identity = Get-OfficeKmsTargetIdentity -Entry $currentEntry
        if ([string]::IsNullOrWhiteSpace($identity)) {
            return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='KmsTargetIdentityMissing'; Entries=@($probe.Entries) }
        }
        if (-not $currentTargetSet.Add($identity)) {
            return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='DuplicateKmsTargetIdentityOnOsppPath'; Entries=@($probe.Entries) }
        }
        if (-not $selectedTargetSet.Contains($identity)) {
            return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='UnselectedKmsOnSameOsppPath'; Entries=@($probe.Entries) }
        }
        if (-not $allowedTargetSet.Contains($identity)) {
            return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason='UnvalidatedKmsOnSameOsppPath'; Entries=@($probe.Entries) }
        }
        $revalidated = Test-OfficeKmsRemediationTarget -Entry $currentEntry -SelectedTargetIds $SelectedTargetIds
        if (-not [bool]$revalidated.Allowed) {
            return [pscustomobject]@{ Allowed=$false; RemhstSafe=$false; Reason=('CurrentKmsValidationFailed:' + [string]$revalidated.Reason); Entries=@($probe.Entries) }
        }
    }

    return [pscustomobject]@{ Allowed=$true; RemhstSafe=$true; Reason=''; Entries=@($probe.Entries) }
}

function Invoke-Remediation {
    param(
        $Products,
        $Findings,
        [switch]$CleanupActivator,
        [switch]$CleanupKmsConfiguration,
        $WindowsProductsToRemove = @(),
        [switch]$SkipRestorePoint,
        $OfficeEntries = @(),
        [string[]]$OfficeHostOverridePaths = @()
    )
    $actions = New-Object System.Collections.Generic.List[string]
    $remediationStates = New-Object System.Collections.Generic.List[object]
    [int]$systemChangeCount = 0
    if (-not (Is-Admin)) {
        $actions.Add((Get-CleanupText "cleanupReport.action.adminRequired"))
        foreach ($entry in @($OfficeEntries)) {
            $identity = Get-OfficeKmsTargetIdentity -Entry $entry
            if ([string]::IsNullOrWhiteSpace($identity)) { continue }
            $state = New-RemediationStateRecord -CandidateId (('License|OfficeKmsLicense|' + $identity).ToLowerInvariant()) `
                -Kind 'OfficeKmsLicense' -Provider 'OfficeOSPP' -SkuId ([string]$entry.SkuId) `
                -Last5 ([string]$entry.Last5) -OsppPathInstance ([string]$entry.Path)
            [void](Set-RemediationStateRecord -Record $state -State Running)
            [void](Set-RemediationStateRecord -Record $state -State RetryableFailure -ErrorCode 'AdministratorRequired' `
                -ErrorDetail (Get-CleanupText 'cleanupReport.action.adminRequired'))
            [void]$remediationStates.Add($state)
        }
        foreach ($path in @($OfficeHostOverridePaths | Select-Object -Unique)) {
            $identity = Get-OfficeKmsHostOverrideIdentity -Path $path
            if ([string]::IsNullOrWhiteSpace($identity)) { continue }
            $state = New-RemediationStateRecord -CandidateId (('License|OfficeKmsHostOverride|' + $identity).ToLowerInvariant()) `
                -Kind 'OfficeKmsHostOverride' -Provider 'OfficeOSPP' -OsppPathInstance $path
            [void](Set-RemediationStateRecord -Record $state -State Running)
            [void](Set-RemediationStateRecord -Record $state -State RetryableFailure -ErrorCode 'AdministratorRequired' `
                -ErrorDetail (Get-CleanupText 'cleanupReport.action.adminRequired'))
            [void]$remediationStates.Add($state)
        }
        return [pscustomobject]@{ Actions=@($actions); SystemChangeCount=0; SystemChangeApplied=$false; RemediationStates=@($remediationStates.ToArray()) }
    }

    if (-not $NoRestorePoint -and -not $SkipRestorePoint) {
        try {
            Checkpoint-Computer -Description (Get-CleanupText "cleanupReport.restorePoint.description") -RestorePointType "MODIFY_SETTINGS" | Out-Null
            $actions.Add((Get-CleanupText "cleanupReport.action.restorePointCreated"))
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.restorePointFailed" @($_.Exception.Message)))
        }
    }

    if ($CleanupActivator) {
    foreach ($f in $Findings) {
        if ($f.Type -eq "Process") {
            try {
                Stop-Process -Name $f.Name -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.action.processStopped" @($f.Name)))
                $systemChangeCount++
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.action.processStopFailed" @($f.Name, $_.Exception.Message)))
            }
        }
        if ($f.Type -eq "Service") {
            try {
                Stop-Service -Name $f.Name -Force -ErrorAction SilentlyContinue
                Set-Service -Name $f.Name -StartupType Disabled -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.action.serviceDisabled" @($f.Name)))
                $systemChangeCount++
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.action.serviceDisableFailed" @($f.Name, $_.Exception.Message)))
            }
        }
        if ($f.Type -eq "ScheduledTask") {
            try {
                $taskPath = "\"
                $taskName = $f.Name
                if ($f.Name -match "^(.*\\)([^\\]+)$") {
                    $taskPath = $matches[1]
                    $taskName = $matches[2]
                }
                Disable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop | Out-Null
                $actions.Add((Get-CleanupText "cleanupReport.action.taskDisabled" @($f.Name)))
                $systemChangeCount++
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.action.taskDisableFailed" @($f.Name, $_.Exception.Message)))
            }
        }
    }
    } else {
        $actions.Add((Get-CleanupText "cleanupReport.action.noActivatorItem"))
    }

    if ($CleanupKmsConfiguration) {
        $ckmsResult = Invoke-SlmgrCommand -SlmgrArguments @('/ckms')
        $actions.Add("slmgr /ckms: $($ckmsResult.Summary)")
        if ([bool]$ckmsResult.Success) { $systemChangeCount++ }
    }

    $windowsTargets = @($WindowsProductsToRemove)
    if ($windowsTargets.Count -gt 0) {
        $removedWindowsKeyCount = 0
        foreach ($targetProduct in $windowsTargets) {
            $activationId = [string]$targetProduct.ID
            if ([string]::IsNullOrWhiteSpace($activationId)) {
                $actions.Add((Get-CleanupText "cleanupReport.action.upkBlocked"))
                continue
            }
            # Re-query immediately before every key mutation. A later target
            # must not inherit the snapshot captured for an earlier /upk.
            $currentWindowsProducts = @(Get-WindowsLicenseProducts)
            $targetValidation = Test-WindowsLicenseRemediationTarget `
                -TargetProduct $targetProduct -CurrentProducts $currentWindowsProducts
            if (-not [bool]$targetValidation.Allowed) {
                $actions.Add((Get-CleanupText 'cleanupReport.action.windowsTargetChanged' @($activationId, [string]$targetValidation.Reason)))
                continue
            }
            $upkResult = Invoke-SlmgrCommand -SlmgrArguments @('/upk', $activationId)
            $actions.Add((Get-CleanupText "cleanupReport.action.upkSelected" @($upkResult.Summary)))
            if ([bool]$upkResult.Success) {
                $removedWindowsKeyCount++
                $systemChangeCount++
            }
        }
        # Keep the mutation scoped to the selected Activation ID. Broad /cpky
        # and /rilc may alter genuine licenses that the user did not select.
        if ($removedWindowsKeyCount -eq 0) { $actions.Add((Get-CleanupText "cleanupReport.action.skipCpkyRilc")) }
    } else {
        $actions.Add((Get-CleanupText "cleanupReport.action.keepWindowsKey"))
    }

    # Key removal is exact and always precedes path-wide host cleanup.  Key
    # identity is Provider=OfficeOSPP + SKU + Last5 + OSPP instance; /remhst is
    # a separate retryable path candidate and therefore works without Last5.
    $requestedOfficeEntries = @($OfficeEntries | Group-Object { Get-OfficeKmsTargetIdentity -Entry $_ } | ForEach-Object { $_.Group[0] })
    $selectedOfficeTargetIds = @($requestedOfficeEntries | ForEach-Object { Get-OfficeKmsTargetIdentity -Entry $_ } | Where-Object { $_ })
    $stateByTarget = @{}
    $successfulKeyPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $officeRemoved = 0

    foreach ($entry in $requestedOfficeEntries) {
        $targetIdentity = Get-OfficeKmsTargetIdentity -Entry $entry
        $candidateId = ('License|OfficeKmsLicense|' + $targetIdentity).ToLowerInvariant()
        $state = New-RemediationStateRecord -CandidateId $candidateId -Kind 'OfficeKmsLicense' `
            -Provider 'OfficeOSPP' -SkuId ([string]$entry.SkuId) -Last5 ([string]$entry.Last5) `
            -OsppPathInstance ([string]$entry.Path)
        [void](Set-RemediationStateRecord -Record $state -State Running)
        [void]$remediationStates.Add($state)
        $stateByTarget[$targetIdentity] = $state

        if ([string]::IsNullOrWhiteSpace($targetIdentity)) {
            [void](Set-RemediationStateRecord -Record $state -State RetryableFailure `
                -ErrorCode 'MissingPathSkuOrLast5' -ErrorDetail ([string]$entry.Path))
            $actions.Add((Get-CleanupText 'cleanupReport.action.officeTargetBlocked' @('MissingPathSkuOrLast5')))
            continue
        }
        $validation = Test-OfficeKmsRemediationTarget -Entry $entry -SelectedTargetIds $selectedOfficeTargetIds
        if (-not [bool]$validation.Allowed -or
            -not [string]::Equals([string]$validation.TargetIdentity, $targetIdentity, [StringComparison]::OrdinalIgnoreCase)) {
            $reason = if ([string]::IsNullOrWhiteSpace([string]$validation.Reason)) { 'TargetIdentityChangedBeforeUnpkey' } else { [string]$validation.Reason }
            [void](Set-RemediationStateRecord -Record $state -State RetryableFailure -ErrorCode $reason `
                -ErrorDetail ("SKU={0}; Last5={1}" -f [string]$entry.SkuId, [string]$entry.Last5))
            $actions.Add((Get-CleanupText 'cleanupReport.action.officeTargetBlocked' @(
                ("SKU={0}; Last5={1}; {2}" -f [string]$entry.SkuId, [string]$entry.Last5, $reason))))
            continue
        }

        $unpkey = Invoke-OfficeOsppCommand -Path ([string]$entry.Path) `
            -Arguments @("/unpkey:$($entry.Last5)") `
            -SuccessPattern '(?i)product key uninstall successful|gỡ.+khóa.+thành công'
        if ([bool]$unpkey.Success) {
            $officeRemoved++
            $systemChangeCount++
            $state.ArtifactCleanupCompleted = $true
            [void]$successfulKeyPaths.Add((Get-OfficeKmsPathKey -Path ([string]$entry.Path)))
            $actions.Add((Get-CleanupText 'cleanupReport.action.officeUnpkeyPass' @($entry.Last5, $entry.SkuId, $entry.LicenseName, $unpkey.Summary)))
        } else {
            [void](Set-RemediationStateRecord -Record $state -State RetryableFailure `
                -ErrorCode ('OSPPUnpkeyExit' + [string]$unpkey.ExitCode) -ErrorDetail ([string]$unpkey.Summary))
            $actions.Add((Get-CleanupText 'cleanupReport.action.officeUnpkeyFail' @($entry.Last5, $entry.SkuId, $entry.LicenseName, $unpkey.ExitCode, $unpkey.Summary)))
        }
    }

    # Refresh at most once per affected OSPP path, then re-probe at most three
    # times.  A command exit code alone never becomes success.
    foreach ($pathGroup in @($requestedOfficeEntries | Where-Object {
        $successfulKeyPaths.Contains((Get-OfficeKmsPathKey -Path ([string]$_.Path)))
    } | Group-Object { Get-OfficeKmsPathKey -Path ([string]$_.Path) })) {
        $pathEntry = @($pathGroup.Group | Select-Object -First 1)[0]
        $path = [string]$pathEntry.Path
        $refresh = Invoke-OfficeLicenseServiceRefresh -MaximumAttempts 1
        if (-not [bool]$refresh.Success) {
            $actions.Add((Get-CleanupText 'cleanupReport.action.officeRefreshFailed' @($path, $refresh.Error)))
        }
        $probe = Get-OfficeLicenseProbeForPathBounded -Path $path -MaximumAttempts 3
        foreach ($entry in @($pathGroup.Group)) {
            $identity = Get-OfficeKmsTargetIdentity -Entry $entry
            $state = $stateByTarget[$identity]
            if ($null -eq $state -or [string]$state.State -ne 'Running') { continue }
            if ([string]$probe.Coverage -ne 'Complete') {
                [void](Set-RemediationStateRecord -Record $state -State RetryableFailure `
                    -ErrorCode ('PostKeyProbe' + [string]$probe.Coverage) -ErrorDetail ([string]$path))
                continue
            }
            $stillPresent = [bool](@($probe.Entries | Where-Object {
                [string]::Equals((Get-OfficeKmsTargetIdentity -Entry $_), $identity, [StringComparison]::OrdinalIgnoreCase)
            }).Count -gt 0)
            if ($stillPresent) {
                [void](Set-RemediationStateRecord -Record $state -State RetryableFailure `
                    -ErrorCode 'OfficeKmsKeyStillPresent' -ErrorDetail $identity)
            }
        }
    }

    # Shared host cleanup runs only after all exact key attempts above.  It is
    # independent of Last5 and remains retryable when the post-probe still sees
    # an unapproved server.
    foreach ($path in @($OfficeHostOverridePaths | Where-Object { $_ } | Select-Object -Unique)) {
        $hostIdentity = Get-OfficeKmsHostOverrideIdentity -Path $path
        if ([string]::IsNullOrWhiteSpace($hostIdentity)) { continue }
        $state = New-RemediationStateRecord `
            -CandidateId (('License|OfficeKmsHostOverride|' + $hostIdentity).ToLowerInvariant()) `
            -Kind 'OfficeKmsHostOverride' -Provider 'OfficeOSPP' -OsppPathInstance $path
        [void](Set-RemediationStateRecord -Record $state -State Running)
        [void]$remediationStates.Add($state)
        $hostValidation = Test-OfficeKmsHostOverrideTarget -Path $path
        if ([bool]$hostValidation.AlreadyClean) {
            $state.ArtifactCleanupCompleted = $true
            continue
        }
        if (-not [bool]$hostValidation.Allowed) {
            if ([string]$hostValidation.Reason -eq 'ApprovedInternalKmsSharesOsppPath') {
                [void](Set-RemediationStateRecord -Record $state -State ApprovedInternalKMS `
                    -OutcomeMessageKey 'cleanupReport.remediation.approvedInternalKms')
            } else {
                [void](Set-RemediationStateRecord -Record $state -State RetryableFailure `
                    -ErrorCode ([string]$hostValidation.Reason) -ErrorDetail $path)
            }
            $actions.Add((Get-CleanupText 'cleanupReport.action.officeTargetBlocked' @(
                ("KMS host override at {0}; {1}" -f $path, [string]$hostValidation.Reason))))
            continue
        }

        $remhst = Invoke-OfficeOsppCommand -Path $path -Arguments @('/remhst') `
            -SuccessPattern '(?i)Successfully applied setting|thành công'
        if (-not [bool]$remhst.Success) {
            [void](Set-RemediationStateRecord -Record $state -State RetryableFailure `
                -ErrorCode ('OSPPRemhstExit' + [string]$remhst.ExitCode) -ErrorDetail ([string]$remhst.Summary))
            $actions.Add((Get-CleanupText 'cleanupReport.action.officeRemhstFail' @($path, $remhst.ExitCode, $remhst.Summary)))
            continue
        }
        $systemChangeCount++
        $actions.Add((Get-CleanupText 'cleanupReport.action.officeRemhstPass' @($path, $remhst.Summary)))
        $refresh = Invoke-OfficeLicenseServiceRefresh -MaximumAttempts 1
        if (-not [bool]$refresh.Success) {
            $actions.Add((Get-CleanupText 'cleanupReport.action.officeRefreshFailed' @($path, $refresh.Error)))
        }
        $postHostProbe = Get-OfficeLicenseProbeForPathBounded -Path $path -MaximumAttempts 3
        $hostStillPresent = [bool]([string]$postHostProbe.Coverage -ne 'Complete' -or @($postHostProbe.Entries | Where-Object {
            [string]$_.Channel -eq 'KMS' -and -not [string]::IsNullOrWhiteSpace([string]$_.Server) -and
            -not (Test-ApprovedKms -Server ([string]$_.Server))
        }).Count -gt 0)
        if ($hostStillPresent) {
            [void](Set-RemediationStateRecord -Record $state -State RetryableFailure `
                -ErrorCode 'OfficeKmsHostStillPresent' -ErrorDetail $path)
        } else {
            $state.ArtifactCleanupCompleted = $true
        }
    }

    if ($requestedOfficeEntries.Count -eq 0 -and @($OfficeHostOverridePaths).Count -eq 0) {
        $actions.Add((Get-CleanupText 'cleanupReport.action.noOfficeKms'))
    } else {
        $actions.Add((Get-CleanupText 'cleanupReport.action.officeRemovalSummary' @($officeRemoved, $requestedOfficeEntries.Count)))
    }
    return [pscustomobject]@{
        Actions = @($actions)
        SystemChangeCount = $systemChangeCount
        SystemChangeApplied = [bool]($systemChangeCount -gt 0)
        RemediationStates = @($remediationStates.ToArray())
    }
}

function Invoke-DeepCleanupV35 {
    param($Candidates, [string[]]$SelectedIds)
    $actions = New-Object System.Collections.Generic.List[string]
    $restoreItems = New-Object System.Collections.Generic.List[object]
    $thirdPartyExecutionResults = New-Object System.Collections.Generic.List[object]
    [int]$systemChangeCount = 0

    function Add-ThirdPartyExecutionResult {
        param($Candidate, [string]$Status, [bool]$Changed, [string]$Message = '')
        if (-not $Candidate -or ([string]$Candidate.Kind -notmatch '^ThirdParty' -and [string]$Candidate.Type -ne 'Guidance')) { return }
        $thirdPartyExecutionResults.Add([pscustomobject][ordered]@{
            ParentCandidateId = $(if ($Candidate.PSObject.Properties['ParentCandidateId']) { [string]$Candidate.ParentCandidateId } else { '' })
            TargetId = [string]$Candidate.TargetId
            VendorScope = [string]$Candidate.VendorScope
            Type = [string]$Candidate.Type
            Kind = [string]$Candidate.Kind
            Name = [string]$Candidate.Name
            Target = [string]$Candidate.Location
            Status = $Status
            Changed = [bool]$Changed
            Message = $Message
        })
    }
    if (-not (Is-Admin)) {
        $actions.Add((Get-CleanupText "cleanupReport.action.deepAdminRequired"))
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0; SystemChangeCount=0; SystemChangeApplied=$false; ThirdPartyExecutionResults=@() }
    }

    $selectedLookup = @{}
    foreach ($selectedId in @($SelectedIds)) {
        if (-not [string]::IsNullOrWhiteSpace($selectedId)) {
            $selectedLookup[([string]$selectedId).ToLowerInvariant()] = $true
        }
    }
    $selectedTopLevel = @($Candidates | Where-Object { $selectedLookup.ContainsKey(([string]$_.Id).ToLowerInvariant()) })
    if ($selectedTopLevel.Count -eq 0) {
        $actions.Add((Get-CleanupText "cleanupReport.action.deepNothingSelected"))
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0; SystemChangeCount=0; SystemChangeApplied=$false; ThirdPartyExecutionResults=@() }
    }

    # Only an explicitly permitted license-state operation could ever require a
    # vendor licensing service to be stopped.  Artifact-only and manual
    # suspicious-file quarantine plans must never touch vendor services.
    $selectedVendorScopes = @($selectedTopLevel | Where-Object {
        $_.Type -eq 'Application' -and $_.PSObject.Properties['LicenseStateResetAllowed'] -and
        [bool]$_.LicenseStateResetAllowed -and
        -not ([bool]($_.PSObject.Properties['ManualArtifactQuarantineOnly'] -and [bool]$_.ManualArtifactQuarantineOnly))
    } | ForEach-Object { [string]$_.VendorScope } | Where-Object { $_ } | Select-Object -Unique)
    $expanded = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($selectedTopLevel | Where-Object { $_.Type -ne 'Application' })) { $expanded.Add($candidate) }
    foreach ($applicationCandidate in @($selectedTopLevel | Where-Object { $_.Type -eq 'Application' })) {
        $safePlan = @(Get-ThirdPartyCandidateSafePlan -Candidate $applicationCandidate)
        foreach ($planItem in $safePlan) {
            $child = New-CleanupItem -Type ([string]$planItem.Type) -Kind ([string]$planItem.Kind) `
                -Name ([string]$planItem.Name) -Location ([string]$planItem.Location) -Detail ([string]$planItem.Detail) `
                -TargetId ([string]$applicationCandidate.TargetId) -VendorScope ([string]$applicationCandidate.VendorScope) -ComponentScope 'ThirdParty' `
                -ProcessId $(if ($planItem.PSObject.Properties['ProcessId']) { [int]$planItem.ProcessId } else { 0 }) `
                -ExpectedExecutablePath $(if ($planItem.PSObject.Properties['ExpectedExecutablePath']) { [string]$planItem.ExpectedExecutablePath } else { '' }) `
                -ExpectedTaskAction $(if ($planItem.PSObject.Properties['ExpectedTaskAction']) { [string]$planItem.ExpectedTaskAction } else { '' }) `
                -RegistryValueName $(if ($planItem.PSObject.Properties['RegistryValueName']) { [string]$planItem.RegistryValueName } else { '' }) `
                -ExpectedRegistryValue $(if ($planItem.PSObject.Properties['ExpectedRegistryValue']) { [string]$planItem.ExpectedRegistryValue } else { '' }) `
                -ExpectedSha256 $(if ($planItem.PSObject.Properties['ExpectedSha256']) { [string]$planItem.ExpectedSha256 } else { '' }) `
                -ExpectedLength $(if ($planItem.PSObject.Properties['ExpectedLength']) { [int64]$planItem.ExpectedLength } else { -1 }) `
                -ManualUninstallAllowed:([bool]($planItem.PSObject.Properties['ManualUninstallAllowed'] -and [bool]$planItem.ManualUninstallAllowed)) `
                -UninstallMethod $(if ($planItem.PSObject.Properties['UninstallMethod']) { [string]$planItem.UninstallMethod } else { '' }) `
                -UninstallIdentity $(if ($planItem.PSObject.Properties['UninstallIdentity']) { [string]$planItem.UninstallIdentity } else { '' }) `
                -UninstallRegistryPath $(if ($planItem.PSObject.Properties['UninstallRegistryPath']) { [string]$planItem.UninstallRegistryPath } else { '' }) `
                -UninstallPackageId $(if ($planItem.PSObject.Properties['UninstallPackageId']) { [string]$planItem.UninstallPackageId } else { '' }) `
                -InstallRoot $(if ($planItem.PSObject.Properties['InstallRoot']) { [string]$planItem.InstallRoot } else { '' })
            foreach ($propertyName in @('ExpectedName','ExpectedVersion','ExpectedPublisher')) {
                if ($planItem.PSObject.Properties[$propertyName]) {
                    $child | Add-Member -NotePropertyName $propertyName -NotePropertyValue ([string]$planItem.$propertyName) -Force
                }
            }
            $restorable = $true
            if ($planItem.PSObject.Properties['Restorable']) { $restorable = [bool]$planItem.Restorable }
            $child | Add-Member -NotePropertyName Restorable -NotePropertyValue $restorable -Force
            $child | Add-Member -NotePropertyName ParentCandidateId -NotePropertyValue ([string]$applicationCandidate.Id) -Force
            $expanded.Add($child)
        }
        $actions.Add((Get-CleanupText "cleanupReport.thirdParty.action.planExpanded" @($applicationCandidate.Name, $safePlan.Count)))
    }
    $selected = @($expanded.ToArray() | Group-Object Id | ForEach-Object { $_.Group[0] })

    $deepStamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $quarantine = ""
    try {
        $secureBackupRoot = Get-SecureBackupRoot
        $quarantine = Join-Path $secureBackupRoot ("quarantine_$($env:COMPUTERNAME)_${deepStamp}_" + [guid]::NewGuid().ToString("N"))
        Ensure-Dir $quarantine
        Set-ProtectedBackupAcl $quarantine
        if (-not (Test-ProtectedDirectoryAcl $quarantine)) { throw (Get-CleanupText "cleanupReport.deep.invalidAcl") }
    } catch {
        $actions.Add((Get-CleanupText "cleanupReport.action.deepBackupBlocked" @($_.Exception.Message)))
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0; SystemChangeCount=0; SystemChangeApplied=$false; ThirdPartyExecutionResults=@() }
    }
    $manifestPath = Join-Path $quarantine "RESTORE-MANIFEST.json"
    $hmacPath = Join-Path $quarantine "RESTORE-MANIFEST.hmac"
    $authPath = Join-Path $quarantine "RESTORE-AUTH.bin"
    $restoreScriptSha256 = ""
    $runtimeHelperSha256 = ""
    $safetyPolicySha256 = ""
    $localizationHelperSha256 = ""
    $viCatalogSha256 = ""
    $enCatalogSha256 = ""
    $hmacKey = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($hmacKey) } finally { $rng.Dispose() }
    $protectedKey = [Security.Cryptography.ProtectedData]::Protect($hmacKey, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    [IO.File]::WriteAllBytes($authPath, $protectedKey)
    $actions.Add((Get-CleanupText "cleanupReport.action.deepConfirmed" @($releaseVersion)))
    $actions.Add((Get-CleanupText "cleanupReport.action.selectedCount" @($selectedTopLevel.Count, @($Candidates).Count)))
    $actions.Add((Get-CleanupText "cleanupReport.action.quarantineDirectory" @($quarantine)))

    function Save-RestoreManifest {
        $manifest = [ordered]@{
            SchemaVersion = "2.0"
        ToolVersion = "5.0"
            BackupMode = "DeepCleanup"
            RemediationScope = $ScanScope
            ComputerName = $env:COMPUTERNAME
            MachineBinding = Get-MachineBinding
            CreatedAt = (Get-Date).ToString("o")
            RestoreScriptSha256 = $restoreScriptSha256
            RuntimeHelperSha256 = $runtimeHelperSha256
            SafetyPolicySha256 = $safetyPolicySha256
            LocalizationHelperSha256 = $localizationHelperSha256
            ViCatalogSha256 = $viCatalogSha256
            EnCatalogSha256 = $enCatalogSha256
            # Tránh lỗi Windows PowerShell 5.1 "Argument types do not match"
            # khi bọc trực tiếp List[object] bằng @().
            Items = $restoreItems.ToArray()
        }
        $tempManifest = Join-Path $quarantine (".manifest-" + [guid]::NewGuid().ToString("N") + ".tmp")
        $tempHmac = $tempManifest + ".hmac"
        [IO.File]::WriteAllText($tempManifest, ($manifest | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        $hmac = New-Object Security.Cryptography.HMACSHA256(,$hmacKey)
        try { $signature = ([BitConverter]::ToString($hmac.ComputeHash([IO.File]::ReadAllBytes($tempManifest))) -replace '-', '').ToUpperInvariant() }
        finally { $hmac.Dispose() }
        [IO.File]::WriteAllText($tempHmac, $signature, [Text.Encoding]::ASCII)
        Move-Item -LiteralPath $tempManifest -Destination $manifestPath -Force
        Move-Item -LiteralPath $tempHmac -Destination $hmacPath -Force
    }

    function Add-RestoreItem {
        param($Item)
        if (-not $Item.PSObject.Properties['Restorable']) {
            $Item | Add-Member -NotePropertyName Restorable -NotePropertyValue $true -Force
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Item.BackupPath)) {
            $fullBackupPath = [string]$Item.BackupPath
            $Item.BackupPath = [IO.Path]::GetFileName($fullBackupPath)
            $Item | Add-Member -NotePropertyName BackupSha256 -NotePropertyValue (Get-PathHash $fullBackupPath) -Force
        } else {
            $Item | Add-Member -NotePropertyName BackupSha256 -NotePropertyValue "" -Force
        }
        $restoreItems.Add($Item)
        Save-RestoreManifest
    }

    function Backup-RegKeyV35 {
        param($Candidate)
        try {
            $psPath = [string]$Candidate.Location
            if (-not (Test-Path -LiteralPath $psPath)) { return $false }
            if ([string]$Candidate.Kind -eq "KmsOverride") {
                $key = Get-Item -LiteralPath $psPath -ErrorAction Stop
                $values = New-Object System.Collections.Generic.List[object]
                $valueNames = @(Get-ToolAllowedRegistryValueNames -Path $psPath)
                foreach ($name in $valueNames) {
                    try {
                        $kind = [string]$key.GetValueKind($name)
                        $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                        if ($kind -eq "Binary") { $value = [Convert]::ToBase64String([byte[]]$value) }
                        $values.Add([pscustomobject]@{ Name=$name; Kind=$kind; Value=$value })
                    } catch {}
                }
                if ($values.Count -eq 0) { return $false }
                $backupPath = Join-Path $quarantine (((( [string]$Candidate.Name) -replace '[\\/:*?"<>| ]', '_')) + "_" + [guid]::NewGuid().ToString("N") + ".json")
                [pscustomobject]@{ RegistryPath=$psPath; Values=$values.ToArray() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $backupPath -Encoding UTF8
                Add-RestoreItem ([pscustomobject]@{ Type="RegistryValues"; Name=[string]$Candidate.Name; OriginalPath=$psPath; BackupPath=$backupPath; Kind=[string]$Candidate.Kind })
            } else {
                $nativePath = $psPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
                $nativePath = $nativePath -replace '^HKCU:\\', 'HKEY_CURRENT_USER\'
                $backupPath = Join-Path $quarantine (((( [string]$Candidate.Name) -replace '[\\/:*?"<>| ]', '_')) + "_" + [guid]::NewGuid().ToString("N") + ".reg")
                $output = (& $nativeRegPath export $nativePath $backupPath /y 2>&1) -join " | "
                if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw $output }
                $restorable = [bool]([string]$Candidate.Kind -notmatch '^(Activator|ThirdParty)')
                if ($Candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$Candidate.Restorable }
                Add-RestoreItem ([pscustomobject]@{ Type="Registry"; Name=[string]$Candidate.Name; OriginalPath=$psPath; BackupPath=$backupPath; Kind=[string]$Candidate.Kind; Restorable=$restorable })
            }
            $actions.Add((Get-CleanupText "cleanupReport.action.registryBackedUp" @($Candidate.Name, $backupPath)))
            return $true
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.registryBackupFailed" @($Candidate.Name, $_.Exception.Message)))
            return $false
        }
    }

    Save-RestoreManifest
    $restoreBundleReady = $false
    try {
        $restoreSource = Join-Path $PSScriptRoot "windows-license-restore.ps1"
        if (Test-Path -LiteralPath $restoreSource -PathType Leaf) {
            $restoreDestination = Join-Path $quarantine "windows-license-restore.ps1"
            Copy-Item -LiteralPath $restoreSource -Destination $restoreDestination -Force
            $restoreScriptSha256 = Get-Sha256 $restoreDestination
            $runtimeSource = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
            if (-not (Test-Path -LiteralPath $runtimeSource -PathType Leaf)) { throw (Get-CleanupText "cleanupReport.deep.runtimeMissing") }
            $runtimeDestination = Join-Path $quarantine "Tool-Runtime.ps1"
            Copy-Item -LiteralPath $runtimeSource -Destination $runtimeDestination -Force
            $runtimeHelperSha256 = Get-Sha256 $runtimeDestination
            $safetyPolicySource = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
            if (-not (Test-Path -LiteralPath $safetyPolicySource -PathType Leaf)) { throw (Get-CleanupText "cleanupReport.deep.safetyPolicyMissing") }
            $safetyPolicyDestination = Join-Path $quarantine "Tool-SafetyPolicy.ps1"
            Copy-Item -LiteralPath $safetyPolicySource -Destination $safetyPolicyDestination -Force
            $safetyPolicySha256 = Get-Sha256 $safetyPolicyDestination
            $localizationSource = Join-Path $PSScriptRoot "Tool-Localization.ps1"
            if (-not (Test-Path -LiteralPath $localizationSource -PathType Leaf)) { throw (Get-CleanupText "common.missingDependency" @("Tool-Localization.ps1")) }
            $localizationDestination = Join-Path $quarantine "Tool-Localization.ps1"
            Copy-Item -LiteralPath $localizationSource -Destination $localizationDestination -Force
            $localizationHelperSha256 = Get-Sha256 $localizationDestination
            $viCatalogSource = Join-Path $PSScriptRoot "Tool-Strings.vi-VN.json"
            $enCatalogSource = Join-Path $PSScriptRoot "Tool-Strings.en-US.json"
            foreach ($catalogSource in @($viCatalogSource, $enCatalogSource)) {
                if (-not (Test-Path -LiteralPath $catalogSource -PathType Leaf)) { throw (Get-CleanupText "common.missingDependency" @([IO.Path]::GetFileName($catalogSource))) }
                Copy-Item -LiteralPath $catalogSource -Destination (Join-Path $quarantine ([IO.Path]::GetFileName($catalogSource))) -Force
            }
            $viCatalogSha256 = Get-Sha256 (Join-Path $quarantine "Tool-Strings.vi-VN.json")
            $enCatalogSha256 = Get-Sha256 (Join-Path $quarantine "Tool-Strings.en-US.json")
            @(
                '@echo off',
                'set "TOOL_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"',
                'if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "TOOL_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"',
                ('"%TOOL_PS%" -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0windows-license-restore.ps1" -BackupDir "%~dp0" -Culture "' + $Culture + '"'),
                'pause'
            ) | Set-Content -LiteralPath (Join-Path $quarantine "KHOI-PHUC-TU-DONG.cmd") -Encoding ASCII
            Save-RestoreManifest
            foreach ($requiredBackupComponent in @($manifestPath, $hmacPath, $authPath, $restoreDestination, $runtimeDestination, $safetyPolicyDestination, $localizationDestination)) {
                if (-not (Test-Path -LiteralPath $requiredBackupComponent -PathType Leaf)) {
                    throw (Get-CleanupText "cleanupReport.action.restoreBundleComponentMissing" @([IO.Path]::GetFileName($requiredBackupComponent)))
                }
            }
            $restoreBundleReady = $true
        } else {
            throw (Get-CleanupText "cleanupReport.action.restoreBundleComponentMissing" @("windows-license-restore.ps1"))
        }
    } catch {
        $actions.Add((Get-CleanupText "cleanupReport.action.restoreBundleFailed" @($_.Exception.Message)))
    }
    if (-not $restoreBundleReady) {
        $actions.Add((Get-CleanupText "cleanupReport.action.backupRequiredBlocked"))
        if ($hmacKey) { [Array]::Clear($hmacKey, 0, $hmacKey.Length) }
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0; SystemChangeCount=0; SystemChangeApplied=$false; ThirdPartyExecutionResults=@() }
    }

    # Thay đổi product key không thể tự rollback nếu không lưu key đầy đủ.
    # Manifest chỉ ghi thông tin đã che để người dùng biết rõ giới hạn này.
    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "License" })) {
        Add-RestoreItem ([pscustomobject]@{
            Type="LicenseNotice"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
            BackupPath=""; Kind=[string]$candidate.Kind; Restorable=$false
        })
        $actions.Add((Get-CleanupText "cleanupReport.action.licenseNotRestorable" @($candidate.Name)))
    }

    # Only a future, explicitly approved vendor-state reset may reach this
    # block. File-only plans, including manual suspicious artifact quarantine,
    # leave all vendor services untouched.
    $vendorLicenseServiceState = @{}
    $vendorServices = New-Object System.Collections.Generic.List[string]
    if ($selectedVendorScopes -contains 'Adobe') { foreach ($name in @('AGSService','AdobeARMservice')) { $vendorServices.Add($name) } }
    if ($selectedVendorScopes -contains 'Autodesk') { $vendorServices.Add('AdskLicensingService') }
    foreach ($serviceName in @($vendorServices.ToArray() | Select-Object -Unique)) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            $vendorLicenseServiceState[$serviceName] = [bool]($service.Status -eq 'Running')
            if ($service.Status -eq 'Running') {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.thirdParty.action.serviceTemporarilyStopped" @($serviceName)))
            }
        } catch {}
    }

    # Dừng các tiến trình được chọn trước để giải phóng tệp/dịch vụ liên quan.
    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Process" })) {
        try {
            if ([int]$candidate.ProcessId -le 0 -or [string]::IsNullOrWhiteSpace([string]$candidate.ExpectedExecutablePath)) {
                throw (Get-CleanupText 'cleanupReport.thirdParty.execution.identityChanged')
            }
            $process = Get-Process -Id ([int]$candidate.ProcessId) -ErrorAction Stop
            $currentPath = [string]$process.Path
            if (-not [string]::Equals([string]$process.ProcessName, [string]$candidate.Name, [StringComparison]::OrdinalIgnoreCase) -or
                -not [string]::Equals($currentPath, [string]$candidate.ExpectedExecutablePath, [StringComparison]::OrdinalIgnoreCase)) {
                throw (Get-CleanupText 'cleanupReport.thirdParty.execution.identityChanged')
            }
            $currentIdentity = Get-ThirdPartyArtifactExecutionIdentity -Path $currentPath
            if ($null -eq $currentIdentity -or
                [string]$candidate.ExpectedSha256 -notmatch '^[0-9A-F]{64}$' -or [int64]$candidate.ExpectedLength -lt 0 -or
                -not [string]::Equals([string]$currentIdentity.Sha256, [string]$candidate.ExpectedSha256, [StringComparison]::OrdinalIgnoreCase) -or
                [int64]$currentIdentity.Length -ne [int64]$candidate.ExpectedLength) {
                throw (Get-CleanupText 'cleanupReport.thirdParty.execution.identityChanged')
            }
            Stop-Process -Id ([int]$candidate.ProcessId) -Force -ErrorAction Stop
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedProcessStopped" @($candidate.Name)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedProcessStopFailed" @($candidate.Name, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    $licenseServiceState = @{}
    if (@($selected | Where-Object { $_.Type -eq "File" -and [string]$_.Kind -notmatch '^ThirdParty' }).Count -gt 0) {
        foreach ($serviceName in @("sppsvc", "osppsvc")) {
            try {
                $svc = Get-Service -Name $serviceName -ErrorAction Stop
                $licenseServiceState[$serviceName] = ($svc.Status -eq "Running")
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Registry" })) {
        if ($candidate.Kind -eq 'KmsOverride') {
            $kmsPrecheck = Test-WindowsKmsOverrideRemediationTarget -Candidate $candidate
            if ([bool]$kmsPrecheck.AlreadyClean) {
                $actions.Add((Get-CleanupText 'cleanupReport.action.windowsKmsTargetChanged' @([string]$kmsPrecheck.Reason)))
                continue
            }
            if (-not [bool]$kmsPrecheck.Allowed) {
                $actions.Add((Get-CleanupText 'cleanupReport.action.windowsKmsTargetChanged' @([string]$kmsPrecheck.Reason)))
                continue
            }
        }
        if (-not (Backup-RegKeyV35 $candidate)) {
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message (Get-CleanupText 'cleanupReport.thirdParty.execution.backupFailed')
            continue
        }
        try {
            if ($candidate.Kind -eq "KmsOverride") {
                # Revalidate after backup as well, narrowing the race between the
                # authenticated snapshot and the actual registry/slmgr mutation.
                $kmsValidation = Test-WindowsKmsOverrideRemediationTarget -Candidate $candidate
                if (-not [bool]$kmsValidation.Allowed) {
                    throw (Get-CleanupText 'cleanupReport.action.windowsKmsTargetChanged' @([string]$kmsValidation.Reason))
                }
                foreach ($name in @(
                    "KeyManagementServiceName", "KeyManagementServicePort",
                    "KeyManagementServiceLookupDomain", "DiscoveredKeyManagementServiceName",
                    "DiscoveredKeyManagementServicePort"
                )) {
                    Remove-ItemProperty -LiteralPath $candidate.Location -Name $name -Force -ErrorAction SilentlyContinue
                }
                if ($candidate.Location -match "Windows NT\\CurrentVersion\\SoftwareProtectionPlatform") {
                    $actions.Add("Windows /ckms: $(Run-SlmgrActionText -SlmgrArguments @('/ckms'))")
                }
                $actions.Add((Get-CleanupText "cleanupReport.action.selectedKmsRemoved" @($candidate.Location)))
                $systemChangeCount++
            } elseif ($candidate.Kind -in @('IfeoHookValue','ActivatorStartupValue')) {
                $valueName = [string]$candidate.RegistryValueName
                if ([string]::IsNullOrWhiteSpace($valueName)) { throw (Get-CleanupText 'cleanupReport.thirdParty.execution.identityChanged') }
                $currentItem = Get-ItemProperty -LiteralPath $candidate.Location -Name $valueName -ErrorAction Stop
                $currentValue = [string]$currentItem.$valueName
                if (-not [string]::Equals($currentValue, [string]$candidate.ExpectedRegistryValue, [StringComparison]::Ordinal)) {
                    throw (Get-CleanupText 'cleanupReport.thirdParty.execution.identityChanged')
                }
                Remove-ItemProperty -LiteralPath $candidate.Location -Name $valueName -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.action.selectedIfeoRemoved" @($candidate.Name)))
                $systemChangeCount++
            } elseif ($candidate.Kind -eq 'ThirdPartyUninstallEntry') {
                $safeUninstallPath = [bool]([string]$candidate.Location -match '(?i)^(HKLM|HKCU):\\SOFTWARE\\(?:WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Uninstall\\[^\\]+$')
                $strongName = [bool]((Get-ThirdPartyEvidenceScope (([string]$candidate.Name) + ' ' + ([string]$candidate.Location))) -ne '')
                if (-not $safeUninstallPath -or -not $strongName) { throw (Get-CleanupText "cleanupReport.thirdParty.action.registryScopeRejected") }
                Remove-Item -LiteralPath $candidate.Location -Recurse -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.thirdParty.action.uninstallEntryRemoved" @($candidate.Name)))
                $systemChangeCount++
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
            }
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.registryProcessFailed" @($candidate.Location, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Defender" })) {
        try {
            Add-RestoreItem ([pscustomobject]@{
                Type="Defender"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
                BackupPath=""; Kind=[string]$candidate.Kind
            })
            Remove-MpPreference -ExclusionPath ([string]$candidate.Location) -ErrorAction Stop
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedDefenderRemoved" @($candidate.Location)))
            $systemChangeCount++
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.defenderRemoveFailed" @($candidate.Location, $_.Exception.Message)))
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "File" })) {
        try {
            if ([string]$candidate.Kind -eq 'ThirdPartyUnauthorizedArtifact' -and -not (Test-ThirdPartyArtifactExecutionIdentity -Candidate $candidate)) {
                $message = Get-CleanupText 'cleanupReport.thirdParty.execution.identityChanged'
                $actions.Add($message)
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'PolicyBlocked' -Changed $false -Message $message
                continue
            }
            if (-not (Test-Path -LiteralPath $candidate.Location -PathType Leaf)) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'NoChange' -Changed $false -Message (Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing')
                continue
            }
            if ((((Get-Item -LiteralPath $candidate.Location -Force).Attributes) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText "cleanupReport.deep.reparseRejected") }
            $destination = Join-Path $quarantine ((Split-Path $candidate.Location -Leaf) + "_" + [guid]::NewGuid().ToString("N") + ".quarantine")
            Copy-Item -LiteralPath $candidate.Location -Destination $destination -Force -ErrorAction Stop
            $restorable = [bool]([string]$candidate.Kind -notmatch '^(Activator|ThirdParty)')
            if ($candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$candidate.Restorable }
            Add-RestoreItem ([pscustomobject]@{
                Type="File"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
                BackupPath=$destination; Kind=[string]$candidate.Kind; Restorable=$restorable
            })
            Remove-Item -LiteralPath $candidate.Location -Force -ErrorAction Stop
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedFileQuarantined" @($candidate.Location)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.fileQuarantineFailed" @($candidate.Location, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "ScheduledTask" })) {
        try {
            $task = Get-CompatibleScheduledTaskRecords | Where-Object {
                [string]::Equals([string]$_.FullName, [string]$candidate.Name, [StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1
            if (-not $task) { throw (Get-CleanupText "cleanupReport.deep.selectedTaskMissing") }
            if ([string]::IsNullOrWhiteSpace([string]$candidate.ExpectedTaskAction) -or
                -not [string]::Equals(([string]$task.ActionsText).Trim(), ([string]$candidate.ExpectedTaskAction).Trim(), [StringComparison]::OrdinalIgnoreCase)) {
                throw (Get-CleanupText 'cleanupReport.thirdParty.execution.identityChanged')
            }
            $taskPath = [string]$task.TaskPath
            $taskName = [string]$task.TaskName
            $backupPath = Join-Path $quarantine ("Task_" + ($taskName -replace '[\\/:*?"<>| ]','_') + "_" + [guid]::NewGuid().ToString("N") + ".xml")
            Export-CompatibleScheduledTask -Record $task -Path $backupPath
            $restorable = [bool]([string]$candidate.Kind -notmatch '^(Activator|ThirdParty)')
            if ($candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$candidate.Restorable }
            Add-RestoreItem ([pscustomobject]@{
                Type="ScheduledTask"; Name=$taskName; OriginalPath=$taskPath; BackupPath=$backupPath
                Kind=[string]$candidate.Kind; WasEnabled=[bool]$task.WasEnabled; Restorable=$restorable
            })
            Remove-CompatibleScheduledTask -Record $task
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedTaskRemoved" @($candidate.Name)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.taskRemoveFailed" @($candidate.Name, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Service" })) {
        try {
            $serviceInfo = Safe-Cim Win32_Service | Where-Object { $_.Name -eq $candidate.Name } | Select-Object -First 1
            if (-not $serviceInfo) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'NoChange' -Changed $false -Message (Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing')
                continue
            }
            $currentExecutablePath = Get-CleanupExecutablePathFromCommandLine ([string]$serviceInfo.PathName)
            if ([string]::IsNullOrWhiteSpace([string]$candidate.ExpectedExecutablePath) -or
                -not [string]::Equals($currentExecutablePath, [string]$candidate.ExpectedExecutablePath, [StringComparison]::OrdinalIgnoreCase)) {
                throw (Get-CleanupText 'cleanupReport.thirdParty.execution.identityChanged')
            }
            $nativeServicePath = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$($serviceInfo.Name)"
            $serviceBackupPath = Join-Path $quarantine ("Service_" + ($serviceInfo.Name -replace '[\\/:*?"<>| ]','_') + "_" + [guid]::NewGuid().ToString("N") + ".reg")
            $serviceExport = (& $nativeRegPath export $nativeServicePath $serviceBackupPath /y 2>&1) -join " | "
            if (-not (Test-Path -LiteralPath $serviceBackupPath -PathType Leaf)) { throw $serviceExport }
            $dependencies = @()
            try { $dependencies = @(Get-Service -Name $serviceInfo.Name -ErrorAction Stop | Select-Object -ExpandProperty ServicesDependedOn | Select-Object -ExpandProperty Name) } catch {}
            $sddl = ""
            try { $sddl = ((& $nativeScPath sdshow $serviceInfo.Name 2>$null) | Where-Object { $_ -match '^D:' } | Select-Object -First 1) } catch {}
            $restorable = [bool]([string]$candidate.Kind -notmatch '^(Activator|ThirdParty)')
            if ($candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$candidate.Restorable }
            Add-RestoreItem ([pscustomobject]@{
                Type="Service"; Name=[string]$serviceInfo.Name; OriginalPath=("HKLM:\SYSTEM\CurrentControlSet\Services\" + [string]$serviceInfo.Name); BackupPath=$serviceBackupPath
                Kind=[string]$candidate.Kind; DisplayName=[string]$serviceInfo.DisplayName
                PathName=[string]$serviceInfo.PathName; StartMode=[string]$serviceInfo.StartMode
                StartName=[string]$serviceInfo.StartName; Description=[string]$serviceInfo.Description
                WasRunning=[bool]($serviceInfo.State -eq "Running"); Dependencies=@($dependencies); SecurityDescriptor=[string]$sddl; Restorable=$restorable
            })
            Stop-Service -Name $serviceInfo.Name -Force -ErrorAction SilentlyContinue
            $deleteOutput = (& $nativeScPath delete $serviceInfo.Name 2>&1) -join " | "
            if ($LASTEXITCODE -ne 0) { throw $deleteOutput }
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedServiceRemoved" @($serviceInfo.Name)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.serviceRemoveFailed" @($candidate.Name, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Folder" })) {
        try {
            if (-not (Test-Path -LiteralPath $candidate.Location -PathType Container)) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'NoChange' -Changed $false -Message (Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing')
                continue
            }
            if ((((Get-Item -LiteralPath $candidate.Location -Force).Attributes) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText "cleanupReport.deep.reparseRejected") }
            $destination = Join-Path $quarantine (($candidate.Name -replace '[\\/:*?"<>| ]','_') + "_" + [guid]::NewGuid().ToString("N"))
            Copy-Item -LiteralPath $candidate.Location -Destination $destination -Recurse -Force -ErrorAction Stop
            $restorable = [bool]([string]$candidate.Kind -notmatch '^(Activator|ThirdParty)')
            if ($candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$candidate.Restorable }
            Add-RestoreItem ([pscustomobject]@{
                Type="Folder"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
                BackupPath=$destination; Kind=[string]$candidate.Kind; Restorable=$restorable
            })
            Remove-Item -LiteralPath $candidate.Location -Recurse -Force -ErrorAction Stop
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedFolderQuarantined" @($candidate.Location)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.folderQuarantineFailed" @($candidate.Location, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    if (@($selected | Where-Object { $_.Type -in @("File", "Registry") -and [string]$_.Kind -notmatch '^ThirdParty' }).Count -gt 0) {
        foreach ($systemFile in @(
            (Get-ToolNativeSystemPath "sppsvc.exe"),
            (Get-ToolNativeSystemPath "SppExtComObj.exe")
        )) {
            if (Test-Path -LiteralPath $systemFile) {
                try {
                    $sfcResult = Invoke-CleanupNativeCommandWithTimeout -FilePath $nativeSfcPath -Arguments @("/scanfile=$systemFile") -TimeoutSeconds 120
                    if ($sfcResult.TimedOut) {
                        $actions.Add((Get-CleanupText "cleanupReport.action.sfcTimedOut" @($systemFile, 120)))
                    } else {
                        $actions.Add("SFC ${systemFile}: $($sfcResult.Output)")
                    }
                } catch {
                    $actions.Add((Get-CleanupText "cleanupReport.action.sfcFailed" @($systemFile, $_.Exception.Message)))
                }
            }
        }
        $actions.Add("Windows /rilc: $(Run-SlmgrActionText -SlmgrArguments @('/rilc'))")
    }

    foreach ($serviceName in $licenseServiceState.Keys) {
        if ([bool]$licenseServiceState[$serviceName]) {
            Start-Service -Name $serviceName -ErrorAction SilentlyContinue
        }
    }

    $hostsCandidates = @($selected | Where-Object { [string]$_.Type -eq 'Hosts' -and [string]$_.Kind -eq 'ThirdPartyHostsEntry' })
    if ($hostsCandidates.Count -gt 0) {
        $hostsPath = Join-Path ([Environment]::ExpandEnvironmentVariables('%WINDIR%')) 'System32\drivers\etc\hosts'
        try {
            if (-not (Test-Path -LiteralPath $hostsPath -PathType Leaf)) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.hostsMissing') }
            $hostsUpdate = Get-ThirdPartyHostsUpdate -Lines ([IO.File]::ReadAllLines($hostsPath)) -Targets @($hostsCandidates | ForEach-Object { [string]$_.Location })
            if ([int]$hostsUpdate.TargetCount -eq 0) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.hostsScopeRejected') }
            $hostsBackup = Join-Path $quarantine ('hosts_' + [guid]::NewGuid().ToString('N') + '.backup')
            Copy-Item -LiteralPath $hostsPath -Destination $hostsBackup -Force -ErrorAction Stop
            Add-RestoreItem ([pscustomobject]@{
                Type='File'; Name='hosts'; OriginalPath=$hostsPath; BackupPath=$hostsBackup
                Kind='ThirdPartyHostsEntry'; Restorable=$true
            })
            if ([int]$hostsUpdate.RemovedCount -gt 0) {
                $hostsTemp = Join-Path (Split-Path -Parent $hostsPath) ('.hosts-' + [guid]::NewGuid().ToString('N') + '.tmp')
                try {
                    [IO.File]::WriteAllLines($hostsTemp, [string[]]$hostsUpdate.Lines, (New-Object Text.UTF8Encoding($false)))
                    Move-Item -LiteralPath $hostsTemp -Destination $hostsPath -Force
                } finally {
                    if ($hostsTemp -and (Test-Path -LiteralPath $hostsTemp -PathType Leaf)) { Remove-Item -LiteralPath $hostsTemp -Force -ErrorAction SilentlyContinue }
                }
                $systemChangeCount++
            }
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.hostsRestored' @($hostsUpdate.RemovedCount, $hostsUpdate.TargetCount)))
            foreach ($candidate in $hostsCandidates) {
                Add-ThirdPartyExecutionResult -Candidate $candidate `
                    -Status $(if ([int]$hostsUpdate.RemovedCount -gt 0) { 'Succeeded' } else { 'NoChange' }) `
                    -Changed:([bool]([int]$hostsUpdate.RemovedCount -gt 0)) `
                    -Message $(if ([int]$hostsUpdate.RemovedCount -gt 0) { [string]$candidate.Detail } else { Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing' })
            }
        } catch {
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.hostsFailed' @($_.Exception.Message)))
            foreach ($candidate in $hostsCandidates) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
            }
        }
    }
    $firewallCandidates = @($selected | Where-Object { [string]$_.Type -eq 'Firewall' -and [string]$_.Kind -eq 'ThirdPartyFirewallBlock' })
    foreach ($firewallGroup in @($firewallCandidates | Group-Object { ([string]$_.Name).ToLowerInvariant() })) {
        $groupCandidates = @($firewallGroup.Group)
        $ruleName = [string]$groupCandidates[0].Name
        $policy = $null
        try {
            if ([string]::IsNullOrWhiteSpace($ruleName) -or $ruleName.Length -gt 256) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.firewallScopeRejected') }
            $allowedPrograms = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($candidate in $groupCandidates) {
                $programPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$candidate.Location))
                if (-not (Test-Path -LiteralPath $programPath -PathType Leaf)) { throw (Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing') }
                $programItem = Get-Item -LiteralPath $programPath -Force -ErrorAction Stop
                if (($programItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText 'cleanupReport.deep.reparseRejected') }
                [void]$allowedPrograms.Add($programPath)
            }
            if ($allowedPrograms.Count -eq 0) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.firewallScopeRejected') }

            $policy = New-Object -ComObject HNetCfg.FwPolicy2
            $matchingRules = New-Object System.Collections.Generic.List[object]
            foreach ($rule in $policy.Rules) {
                if (-not [string]::Equals([string]$rule.Name, $ruleName, [StringComparison]::OrdinalIgnoreCase)) { continue }
                $ruleProgram = ''
                try { $ruleProgram = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$rule.ApplicationName)) } catch {}
                if (-not [bool]$rule.Enabled -or [int]$rule.Action -ne 0 -or [int]$rule.Direction -ne 2 -or
                    -not $ruleProgram -or -not $allowedPrograms.Contains($ruleProgram)) {
                    throw (Get-CleanupText 'cleanupReport.thirdParty.action.firewallScopeRejected')
                }
                $matchingRules.Add([pscustomobject]@{
                    Name=[string]$rule.Name; ApplicationName=$ruleProgram; Description=[string]$rule.Description
                    Enabled=[bool]$rule.Enabled; Direction=[int]$rule.Direction; Action=[int]$rule.Action
                })
            }
            if ($matchingRules.Count -eq 0 -or $matchingRules.Count -ne $allowedPrograms.Count) {
                throw (Get-CleanupText 'cleanupReport.thirdParty.action.firewallScopeRejected')
            }
            Add-RestoreItem ([pscustomobject]@{
                Type='FirewallNotice'; Name=$ruleName; OriginalPath=(@($matchingRules.ToArray() | ForEach-Object { [string]$_.ApplicationName }) -join '; ')
                BackupPath=''; Kind='ThirdPartyFirewallBlock'; Restorable=$false; RuleSnapshots=$matchingRules.ToArray()
            })

            # FwPolicy2 identifies removals by rule name. Multiple same-name
            # entries are accepted only when every one is an exact selected
            # outbound block; remove/recheck is bounded to the observed count.
            for ($attempt = 0; $attempt -lt $matchingRules.Count; $attempt++) {
                $remainingSameName = 0
                foreach ($rule in $policy.Rules) {
                    if ([string]::Equals([string]$rule.Name, $ruleName, [StringComparison]::OrdinalIgnoreCase)) { $remainingSameName++ }
                }
                if ($remainingSameName -eq 0) { break }
                $policy.Rules.Remove($ruleName)
            }
            $remainingSameName = 0
            foreach ($rule in $policy.Rules) {
                if ([string]::Equals([string]$rule.Name, $ruleName, [StringComparison]::OrdinalIgnoreCase)) { $remainingSameName++ }
            }
            if ($remainingSameName -ne 0) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.firewallRemoveIncomplete' @($remainingSameName)) }
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.firewallRemoved' @($ruleName, $matchingRules.Count)))
            $systemChangeCount += [int]$matchingRules.Count
            foreach ($candidate in $groupCandidates) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
            }
        } catch {
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.firewallFailed' @($ruleName, $_.Exception.Message)))
            foreach ($candidate in $groupCandidates) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
            }
        } finally {
            if ($policy) { try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($policy) } catch {} }
        }
    }

    foreach ($candidate in @($selected | Where-Object {
        [string]$_.Type -eq 'Uninstall' -and [string]$_.Kind -eq 'ThirdPartyCompleteUninstall'
    })) {
        try {
            if (-not ($candidate.PSObject.Properties['ManualUninstallAllowed'] -and [bool]$candidate.ManualUninstallAllowed)) {
                throw (Get-CleanupText 'cleanupReport.thirdParty.execution.uninstallIdentityRejected')
            }
            $method = [string]$candidate.UninstallMethod
            $identity = [string]$candidate.UninstallIdentity
            $exitCode = 0
            if ($method -eq 'MSI') {
                if ($identity -notmatch '^\{[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}\}$') {
                    throw (Get-CleanupText 'cleanupReport.thirdParty.execution.uninstallIdentityRejected')
                }
                $registryPath = ConvertTo-ToolRegistryPath ([string]$candidate.UninstallRegistryPath)
                if (-not (Test-Path -LiteralPath $registryPath -PathType Container)) {
                    Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'NoChange' -Changed $false -Message (Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing')
                    continue
                }
                $entry = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
                $currentName = [string]$entry.DisplayName
                $currentVersion = [string]$entry.DisplayVersion
                $currentPublisher = [string]$entry.Publisher
                $currentUninstall = [string]$entry.UninstallString
                $currentMatch = [regex]::Match($currentUninstall, '(?i)(?:^|[\\\s"])(?:msiexec(?:\.exe)?)\s+(?:/i|/x)\s*"?(\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\})"?')
                if (-not $currentMatch.Success -or $currentMatch.Groups[1].Value.ToUpperInvariant() -ne $identity -or
                    ($candidate.ExpectedName -and -not [string]::Equals($currentName, [string]$candidate.ExpectedName, [StringComparison]::OrdinalIgnoreCase)) -or
                    ($candidate.ExpectedVersion -and -not [string]::Equals($currentVersion, [string]$candidate.ExpectedVersion, [StringComparison]::OrdinalIgnoreCase)) -or
                    ($candidate.ExpectedPublisher -and -not [string]::Equals($currentPublisher, [string]$candidate.ExpectedPublisher, [StringComparison]::OrdinalIgnoreCase))) {
                    throw (Get-CleanupText 'cleanupReport.thirdParty.execution.identityChanged')
                }
                Add-RestoreItem ([pscustomobject]@{
                    Type='UninstallNotice'; Name=$currentName; OriginalPath=$registryPath; BackupPath=''
                    Kind='ThirdPartyCompleteUninstall'; Restorable=$false; Method='MSI'; Identity=$identity
                })
                $process = Start-Process -FilePath (Get-ToolNativeSystemPath 'msiexec.exe') `
                    -ArgumentList @('/x', $identity, '/qn', '/norestart') -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
                $exitCode = [int]$process.ExitCode
                if ($exitCode -notin @(0,1641,3010)) { throw (Get-CleanupText 'cleanupReport.thirdParty.execution.uninstallExitCode' @($exitCode)) }
                if (Test-Path -LiteralPath $registryPath -PathType Container) {
                    throw (Get-CleanupText 'cleanupReport.thirdParty.execution.uninstallStillPresent')
                }
            } elseif ($method -eq 'Appx') {
                if ($identity -notmatch '^[A-Za-z0-9._-]+$' -or [string]$candidate.UninstallPackageId -ne $identity) {
                    throw (Get-CleanupText 'cleanupReport.thirdParty.execution.uninstallIdentityRejected')
                }
                $package = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object {
                    [string]::Equals([string]$_.PackageFullName, $identity, [StringComparison]::OrdinalIgnoreCase)
                })
                if ($package.Count -ne 1) {
                    if ($package.Count -eq 0) {
                        Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'NoChange' -Changed $false -Message (Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing')
                        continue
                    }
                    throw (Get-CleanupText 'cleanupReport.thirdParty.execution.uninstallIdentityRejected')
                }
                if ($candidate.ExpectedVersion -and -not [string]::Equals([string]$package[0].Version, [string]$candidate.ExpectedVersion, [StringComparison]::OrdinalIgnoreCase)) {
                    throw (Get-CleanupText 'cleanupReport.thirdParty.execution.identityChanged')
                }
                Add-RestoreItem ([pscustomobject]@{
                    Type='UninstallNotice'; Name=[string]$candidate.Name; OriginalPath=$identity; BackupPath=''
                    Kind='ThirdPartyCompleteUninstall'; Restorable=$false; Method='Appx'; Identity=$identity
                })
                $removeCommand = Get-Command Remove-AppxPackage -ErrorAction Stop
                if ($removeCommand.Parameters.ContainsKey('AllUsers')) {
                    Remove-AppxPackage -Package $identity -AllUsers -ErrorAction Stop
                } else {
                    Remove-AppxPackage -Package $identity -ErrorAction Stop
                }
                $remaining = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
                    [string]::Equals([string]$_.PackageFullName, $identity, [StringComparison]::OrdinalIgnoreCase)
                })
                if ($remaining.Count -ne 0) { throw (Get-CleanupText 'cleanupReport.thirdParty.execution.uninstallStillPresent') }
            } else {
                throw (Get-CleanupText 'cleanupReport.thirdParty.execution.uninstallIdentityRejected')
            }
            $systemChangeCount++
            $status = if ($exitCode -in @(1641,3010)) { 'RebootRequired' } else { 'Succeeded' }
            $message = if ($status -eq 'RebootRequired') {
                Get-CleanupText 'cleanupReport.thirdParty.action.uninstallRebootRequired' @($candidate.Name, $exitCode)
            } else {
                Get-CleanupText 'cleanupReport.thirdParty.action.uninstallSucceeded' @($candidate.Name)
            }
            $actions.Add($message)
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status $status -Changed $true -Message $message
        } catch {
            $message = Get-CleanupText 'cleanupReport.thirdParty.action.uninstallFailed' @($candidate.Name, $_.Exception.Message)
            $actions.Add($message)
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message $message
        }
    }
    foreach ($serviceName in $vendorLicenseServiceState.Keys) {
        if ([bool]$vendorLicenseServiceState[$serviceName]) {
            try {
                Start-Service -Name $serviceName -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.thirdParty.action.serviceRestarted" @($serviceName)))
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.thirdParty.action.serviceRestartFailed" @($serviceName, $_.Exception.Message)))
            }
        }
    }

    foreach ($candidate in @($selected | Where-Object {
        [string]$_.Type -eq 'Guidance' -and
        [string]$_.Kind -in @('ThirdPartyOfficialSource','ThirdPartyManualReview')
    })) {
        $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.officialSourceRequired' @($candidate.Name, $(if ($candidate.Location) { [string]$candidate.Location } else { Get-CleanupText 'common.unknown' }))))
        Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'GuidanceOnly' -Changed $false -Message ([string]$candidate.Detail)
    }
    foreach ($candidate in @($selected | Where-Object {
        [string]$_.Type -eq 'Guidance' -and [string]$_.Kind -eq 'OfficeKmsManualReview'
    })) {
        $actions.Add((Get-CleanupText 'cleanupReport.action.guidanceOnlyRecorded' @($candidate.Name, $candidate.Detail)))
    }

    try {
        Save-RestoreManifest
        $actions | Set-Content -LiteralPath (Join-Path $quarantine "QUARANTINE-MANIFEST.txt") -Encoding UTF8
        @(
            Get-CleanupText "cleanupReport.restoreGuide.title" @($releaseVersion)
            Get-CleanupText "cleanupReport.restoreGuide.step1"
            Get-CleanupText "cleanupReport.restoreGuide.step2"
            Get-CleanupText "cleanupReport.restoreGuide.step3"
            Get-CleanupText "cleanupReport.restoreGuide.step4"
            Get-CleanupText "cleanupReport.restoreGuide.step5"
        ) | Set-Content -LiteralPath (Join-Path $quarantine (Get-CleanupText "cleanupReport.restoreGuide.fileName")) -Encoding UTF8
        $actions.Add((Get-CleanupText "cleanupReport.action.restoreBundleCreated"))
    } catch {
        $actions.Add((Get-CleanupText "cleanupReport.action.restoreBundleFinalizeFailed" @($_.Exception.Message)))
    }

    if ($hmacKey) { [Array]::Clear($hmacKey, 0, $hmacKey.Length) }

    return [pscustomobject]@{
        Actions=@($actions)
        BackupDirectory=$quarantine
        SelectedCount=[int]$selectedTopLevel.Count
        SystemChangeCount=[int]$systemChangeCount
        SystemChangeApplied=[bool]($systemChangeCount -gt 0)
        ThirdPartyExecutionResults=@($thirdPartyExecutionResults.ToArray())
    }
}

function Expand-SelectedCleanupCandidates {
    param($Candidates, [string[]]$SelectedIds)

    $selectedLookup = @{}
    foreach ($selectedId in @($SelectedIds)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$selectedId)) {
            $selectedLookup[([string]$selectedId).ToLowerInvariant()] = $true
        }
    }
    $expanded = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($Candidates | Where-Object { $selectedLookup.ContainsKey(([string]$_.Id).ToLowerInvariant()) })) {
        if ([string]$candidate.Type -ne 'Application') {
            $candidate | Add-Member -NotePropertyName ParentCandidateId -NotePropertyValue ([string]$candidate.Id) -Force
            $expanded.Add($candidate)
            continue
        }
        foreach ($planItem in @(Get-ThirdPartyCandidateSafePlan -Candidate $candidate)) {
            $child = New-CleanupItem -Type ([string]$planItem.Type) -Kind ([string]$planItem.Kind) `
                -Name ([string]$planItem.Name) -Location ([string]$planItem.Location) -Detail ([string]$planItem.Detail) `
                -TargetId ([string]$candidate.TargetId) -VendorScope ([string]$candidate.VendorScope) -ComponentScope 'ThirdParty' `
                -ProcessId $(if ($planItem.PSObject.Properties['ProcessId']) { [int]$planItem.ProcessId } else { 0 }) `
                -ExpectedExecutablePath $(if ($planItem.PSObject.Properties['ExpectedExecutablePath']) { [string]$planItem.ExpectedExecutablePath } else { '' }) `
                -ExpectedTaskAction $(if ($planItem.PSObject.Properties['ExpectedTaskAction']) { [string]$planItem.ExpectedTaskAction } else { '' }) `
                -RegistryValueName $(if ($planItem.PSObject.Properties['RegistryValueName']) { [string]$planItem.RegistryValueName } else { '' }) `
                -ExpectedRegistryValue $(if ($planItem.PSObject.Properties['ExpectedRegistryValue']) { [string]$planItem.ExpectedRegistryValue } else { '' }) `
                -ExpectedSha256 $(if ($planItem.PSObject.Properties['ExpectedSha256']) { [string]$planItem.ExpectedSha256 } else { '' }) `
                -ExpectedLength $(if ($planItem.PSObject.Properties['ExpectedLength']) { [int64]$planItem.ExpectedLength } else { -1 }) `
                -ManualUninstallAllowed:([bool]($planItem.PSObject.Properties['ManualUninstallAllowed'] -and [bool]$planItem.ManualUninstallAllowed)) `
                -UninstallMethod $(if ($planItem.PSObject.Properties['UninstallMethod']) { [string]$planItem.UninstallMethod } else { '' }) `
                -UninstallIdentity $(if ($planItem.PSObject.Properties['UninstallIdentity']) { [string]$planItem.UninstallIdentity } else { '' }) `
                -UninstallRegistryPath $(if ($planItem.PSObject.Properties['UninstallRegistryPath']) { [string]$planItem.UninstallRegistryPath } else { '' }) `
                -UninstallPackageId $(if ($planItem.PSObject.Properties['UninstallPackageId']) { [string]$planItem.UninstallPackageId } else { '' }) `
                -InstallRoot $(if ($planItem.PSObject.Properties['InstallRoot']) { [string]$planItem.InstallRoot } else { '' })
            foreach ($propertyName in @('ExpectedName','ExpectedVersion','ExpectedPublisher')) {
                if ($planItem.PSObject.Properties[$propertyName]) {
                    $child | Add-Member -NotePropertyName $propertyName -NotePropertyValue ([string]$planItem.$propertyName) -Force
                }
            }
            $restorable = $true
            if ($planItem.PSObject.Properties['Restorable']) { $restorable = [bool]$planItem.Restorable }
            $child | Add-Member -NotePropertyName Restorable -NotePropertyValue $restorable -Force
            $child | Add-Member -NotePropertyName ParentCandidateId -NotePropertyValue ([string]$candidate.Id) -Force
            $expanded.Add($child)
        }
    }
    return @($expanded.ToArray() | Group-Object Id | ForEach-Object { $_.Group[0] })
}

function Get-DryRunRemediationPlan {
    param($Candidates, [string[]]$SelectedIds, [switch]$SkipRestorePoint)

    $plan = New-Object System.Collections.Generic.List[object]
    $expanded = @(Expand-SelectedCleanupCandidates -Candidates $Candidates -SelectedIds $SelectedIds)
    [int]$order = 0

    if (-not $SkipRestorePoint) {
        $order++
        $plan.Add([pscustomobject][ordered]@{
            Order=$order; CandidateId='system-restore-point'; ParentCandidateId=''; Type='Safety'; Kind='RestorePoint'
            ActionCode='CreateRestorePoint'; Action=(Get-CleanupText 'cleanupReport.dryRun.action.createRestorePoint')
            Name='System Restore'; Target='Windows'; Detail=(Get-CleanupText 'cleanupReport.restorePoint.selectedDescription' @($releaseVersion))
            RequiresAdministrator=$true; BackupPlanned=$false; Restorable=$true; ChangesSystem=$true
        })
    }
    if ($expanded.Count -gt 0) {
        $plannedDataRoot = [string]$env:TOOL_DATA_ROOT
        if ([string]::IsNullOrWhiteSpace($plannedDataRoot)) {
            $plannedDataRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'ThanhViet-VietLicenSure\v4.6'
        }
        $order++
        $plan.Add([pscustomobject][ordered]@{
            Order=$order; CandidateId='signed-backup-bundle'; ParentCandidateId=''; Type='Safety'; Kind='BackupBundle'
            ActionCode='CreateSignedBackup'; Action=(Get-CleanupText 'cleanupReport.dryRun.action.createBackup')
            Name='RESTORE-MANIFEST'; Target=(Join-Path $plannedDataRoot 'backups'); Detail=(Get-CleanupText 'cleanupReport.dryRun.detail.backup')
            RequiresAdministrator=$true; BackupPlanned=$true; Restorable=$true; ChangesSystem=$true
        })
    }

    foreach ($candidate in $expanded) {
        $order++
        $type = [string]$candidate.Type
        $kind = [string]$candidate.Kind
        $actionCode = 'ManualGuidance'
        $action = Get-CleanupText 'cleanupReport.dryRun.action.guidance'
        $changesSystem = $false
        $backupPlanned = $false
        $restorable = $false
        switch ($type) {
            'Process' { $actionCode='StopProcess'; $action=Get-CleanupText 'cleanupReport.dryRun.action.stopProcess'; $changesSystem=$true }
            'Service' { $actionCode='BackupAndDeleteService'; $action=Get-CleanupText 'cleanupReport.dryRun.action.deleteService'; $changesSystem=$true; $backupPlanned=$true; $restorable=$true }
            'ScheduledTask' { $actionCode='BackupAndDeleteTask'; $action=Get-CleanupText 'cleanupReport.dryRun.action.deleteTask'; $changesSystem=$true; $backupPlanned=$true; $restorable=$true }
            'Registry' { $actionCode='BackupAndRemoveRegistry'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeRegistry'; $changesSystem=$true; $backupPlanned=$true; $restorable=[bool]([string]$kind -notmatch '^(Activator|ThirdParty)') }
            'Defender' { $actionCode='RemoveDefenderExclusion'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeDefender'; $changesSystem=$true; $backupPlanned=$true; $restorable=$true }
            'File' { $actionCode='QuarantineFile'; $action=Get-CleanupText 'cleanupReport.dryRun.action.quarantineFile'; $changesSystem=$true; $backupPlanned=$true; $restorable=[bool]([string]$kind -notmatch '^(Activator|ThirdParty)') }
            'Folder' { $actionCode='QuarantineFolder'; $action=Get-CleanupText 'cleanupReport.dryRun.action.quarantineFolder'; $changesSystem=$true; $backupPlanned=$true; $restorable=[bool]([string]$kind -notmatch '^(Activator|ThirdParty)') }
            'Hosts' { $actionCode='BackupAndRemoveHostsEntry'; $action=Get-CleanupText 'cleanupReport.dryRun.action.cleanHosts'; $changesSystem=$true; $backupPlanned=$true; $restorable=$true }
            'Firewall' { $actionCode='RemoveScopedFirewallBlock'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeFirewallBlock'; $changesSystem=$true; $backupPlanned=$true; $restorable=$false }
            'Uninstall' { $actionCode='CompleteApplicationUninstall'; $action=Get-CleanupText 'cleanupReport.dryRun.action.completeUninstall' @($candidate.Name); $changesSystem=$true; $backupPlanned=$true; $restorable=$false }
            'License' {
                if ($kind -eq 'WindowsKmsLicense') { $actionCode='RemoveWindowsKmsLicense'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeWindowsKms' }
                elseif ($kind -eq 'OfficeKmsLicense') { $actionCode='RemoveOfficeKmsLicense'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeOfficeKms' }
                elseif ($kind -eq 'OfficeKmsHostOverride') { $actionCode='RemoveOfficeKmsHostOverride'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeOfficeKmsHost' }
                $changesSystem=$true
            }
        }
        if ($candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$candidate.Restorable }
        $plan.Add([pscustomobject][ordered]@{
            Order=$order; CandidateId=[string]$candidate.Id; ParentCandidateId=[string]$candidate.ParentCandidateId
            Type=$type; Kind=$kind; ActionCode=$actionCode; Action=$action; Name=[string]$candidate.Name
            Target=$(if ($type -eq 'Uninstall' -and $candidate.UninstallIdentity) { [string]$candidate.UninstallIdentity } else { [string]$candidate.Location })
            Detail=[string]$candidate.Detail; RequiresAdministrator=[bool]$changesSystem
            BackupPlanned=[bool]$backupPlanned; Restorable=[bool]$restorable; ChangesSystem=[bool]$changesSystem
            ApplicationVersion=$(if ($candidate.PSObject.Properties['ExpectedVersion']) { [string]$candidate.ExpectedVersion } else { '' })
            UninstallMethod=$(if ($candidate.PSObject.Properties['UninstallMethod']) { [string]$candidate.UninstallMethod } else { '' })
            InstallRoot=$(if ($candidate.PSObject.Properties['InstallRoot']) { [string]$candidate.InstallRoot } else { '' })
            RebootBehavior=$(if ($type -eq 'Uninstall') { 'MayRequireRestart:1641,3010' } else { '' })
            NonRestorable=[bool]($type -eq 'Uninstall')
        })
    }
    return $plan.ToArray()
}
