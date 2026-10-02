# VietLicenSure v5.0 - dot-sourced function library
# Extracted mechanically from windows-license-compliance-cleanup.ps1; contains function definitions only.
# Keep this file beside its compatible entrypoint.

function Test-CleanupScanScopeIncludes {
    param(
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")]
        [string]$Scope,
        [ValidateSet("Windows", "Office", "ThirdParty")]
        [string]$Component
    )

    switch ($Component) {
        "Windows" { return [bool]($Scope -in @("All", "Windows", "WindowsOffice", "WindowsThirdParty")) }
        "Office" { return [bool]($Scope -in @("All", "Office", "WindowsOffice", "OfficeThirdParty")) }
        "ThirdParty" { return [bool]($Scope -in @("All", "ThirdParty", "WindowsThirdParty", "OfficeThirdParty")) }
    }
    return $false
}

function Get-CleanupRecordComponentScope {
    param($Record)

    if ($null -eq $Record) { return "Shared" }
    if ($Record.PSObject.Properties['ComponentScope']) {
        $explicitScope = [string]$Record.ComponentScope
        if ($explicitScope -in @("Windows", "Office", "ThirdParty", "Shared")) { return $explicitScope }
    }

    $type = [string]$Record.Type
    $kind = [string]$Record.Kind
    $text = (([string]$Record.Name) + " " + ([string]$Record.Location) + " " + ([string]$Record.Detail)).Trim()
    if ($type -eq "Application" -or $kind -match '^ThirdParty') { return "ThirdParty" }
    if ($kind -in @('OfficeKmsLicense','OfficeKmsHostOverride') -or $text -match '(?i)OfficeSoftwareProtectionPlatform|\bospp(?:svc|\.vbs)?\b|\bOffice\s+KMS\b') { return "Office" }
    if ($kind -eq "WindowsKmsLicense" -or $kind -eq "ManagedNoGenTicketPolicy" -or
        $text -match '(?i)Windows NT\\CurrentVersion\\SoftwareProtectionPlatform|\bsppsvc\b|\bSppExtComObj\b|\bNoGenTicket\b') { return "Windows" }
    return "Shared"
}

function Test-CleanupRecordMatchesScope {
    param(
        $Record,
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")]
        [string]$Scope
    )

    $componentScope = Get-CleanupRecordComponentScope -Record $Record
    if ($componentScope -eq "Shared") {
        return [bool]((Test-CleanupScanScopeIncludes -Scope $Scope -Component "Windows") -or
            (Test-CleanupScanScopeIncludes -Scope $Scope -Component "Office"))
    }
    return Test-CleanupScanScopeIncludes -Scope $Scope -Component $componentScope
}

function New-CleanupItem {
    param(
        [string]$Type,
        [string]$Kind,
        [string]$Name,
        [string]$Location,
        [string]$Detail,
        [string]$TargetId = "",
        [bool]$DefaultSelected = $false,
        [string]$VendorScope = "",
        [bool]$AutoEligible = $false,
        [string[]]$ApplicationNames = @(),
        [string[]]$ApplicationIds = @(),
        $Evidence = @(),
        $PlanItems = @(),
        [string]$RemediationMode = '',
        [string]$ComponentScope = '',
        [bool]$ArtifactCleanupAllowed = $false,
        [bool]$LicenseStateResetAllowed = $false,
        [string]$RecoveryMode = '',
        [bool]$ManualArtifactQuarantineOnly = $false,
        [bool]$ManualUninstallAllowed = $false,
        [string]$UninstallMethod = '',
        [string]$UninstallIdentity = '',
        [string]$UninstallRegistryPath = '',
        [string]$UninstallPackageId = '',
        [string]$InstallRoot = '',
        [int]$ProcessId = 0,
        [string]$ExpectedExecutablePath = '',
        [string]$ExpectedTaskAction = '',
        [string]$RegistryValueName = '',
        [string]$ExpectedRegistryValue = '',
        [bool]$GuidanceOnly = $false,
        [string]$GuidanceReason = '',
        [string]$RecoveryBlockReason = '',
        [string]$IdentitySeed = '',
        [string]$ExpectedSha256 = '',
        [int64]$ExpectedLength = -1,
        [string]$Provider = '',
        [string]$SkuId = '',
        [string]$Last5 = '',
        [string]$OsppPathInstance = '',
        [ValidateSet('Pending','Running','VerifiedClean','ApprovedInternalKMS','RetryableFailure','BlockedByPolicy','NeedsOfficeRepair')]
        [string]$InitialRemediationState = 'Pending',
        [bool]$RemediationRetryAllowed = $true,
        [string]$RemediationBlockCode = '',
        [string]$RemediationBlockDetail = ''
    )
    $idMaterial = if ([string]::IsNullOrWhiteSpace($IdentitySeed)) {
        $Type + "|" + $Kind + "|" + $Name + "|" + $Location
    } else {
        $Type + "|" + $Kind + "|" + $IdentitySeed
    }
    $id = $idMaterial.ToLowerInvariant()
    $remediationState = New-RemediationStateRecord -CandidateId $id -Kind $Kind -Provider $Provider `
        -SkuId $SkuId -Last5 $Last5 -OsppPathInstance $OsppPathInstance `
        -InitialState $InitialRemediationState -RetryAllowed $RemediationRetryAllowed `
        -BlockCode $RemediationBlockCode -BlockDetail $RemediationBlockDetail
    return [pscustomobject]@{
        Id = $id
        Type = $Type
        Kind = $Kind
        Name = $Name
        Location = $Location
        Detail = $Detail
        TargetId = $TargetId
        TargetIdentity = $IdentitySeed
        DefaultSelected = $DefaultSelected
        VendorScope = $VendorScope
        AutoEligible = $AutoEligible
        ApplicationNames = @($ApplicationNames)
        ApplicationIds = @($ApplicationIds)
        Evidence = @($Evidence)
        PlanItems = @($PlanItems)
        RemediationMode = $RemediationMode
        ComponentScope = $ComponentScope
        ArtifactCleanupAllowed = $ArtifactCleanupAllowed
        LicenseStateResetAllowed = $LicenseStateResetAllowed
        RecoveryMode = $RecoveryMode
        ManualArtifactQuarantineOnly = $ManualArtifactQuarantineOnly
        ManualUninstallAllowed = $ManualUninstallAllowed
        UninstallMethod = $UninstallMethod
        UninstallIdentity = $UninstallIdentity
        UninstallRegistryPath = $UninstallRegistryPath
        UninstallPackageId = $UninstallPackageId
        InstallRoot = $InstallRoot
        ProcessId = $ProcessId
        ExpectedExecutablePath = $ExpectedExecutablePath
        ExpectedTaskAction = $ExpectedTaskAction
        RegistryValueName = $RegistryValueName
        ExpectedRegistryValue = $ExpectedRegistryValue
        GuidanceOnly = $GuidanceOnly
        GuidanceReason = $GuidanceReason
        RecoveryBlockReason = $RecoveryBlockReason
        ExpectedSha256 = $ExpectedSha256
        ExpectedLength = $ExpectedLength
        Provider = $Provider
        SkuId = $SkuId
        Last5 = $Last5
        OsppPathInstance = $OsppPathInstance
        RemediationState = $remediationState
    }
}

function ConvertTo-CleanupCanonicalNode {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [bool] -or $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or
        $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) { return $Value }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('o') }
    if ($Value -is [datetimeoffset]) { return ([datetimeoffset]$Value).ToUniversalTime().ToString('o') }
    if ($Value -is [string] -or $Value -is [char] -or $Value -is [guid]) { return [string]$Value }

    if ($Value -is [Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
            $ordered[$key] = ConvertTo-CleanupCanonicalNode -Value $Value[$key]
        }
        return [pscustomobject]$ordered
    }

    if ($Value -is [Collections.IEnumerable] -and -not ($Value -is [string])) {
        $serialized = @($Value | ForEach-Object {
            (ConvertTo-CleanupCanonicalNode -Value $_) | ConvertTo-Json -Compress -Depth 16
        } | Sort-Object)
        return @($serialized)
    }

    $properties = @($Value.PSObject.Properties | Where-Object {
        $_.MemberType -in @('NoteProperty','Property','AliasProperty','ScriptProperty') -and
        [string]$_.Name -notin @('SnapshotSha256','RemediationState')
    } | Sort-Object Name)
    $object = [ordered]@{}
    foreach ($property in $properties) {
        try { $object[[string]$property.Name] = ConvertTo-CleanupCanonicalNode -Value $property.Value }
        catch { $object[[string]$property.Name] = '<unreadable>' }
    }
    return [pscustomobject]$object
}

function Get-CleanupCandidateSnapshotHash {
    param([Parameter(Mandatory = $true)][object]$Candidate)

    $snapshot = [ordered]@{}
    foreach ($name in @(
        'Id','Type','Kind','Name','Location','Detail','TargetId','TargetIdentity','DefaultSelected',
        'VendorScope','AutoEligible','ApplicationNames','ApplicationIds','Evidence','PlanItems',
        'RemediationMode','ComponentScope','ArtifactCleanupAllowed','LicenseStateResetAllowed',
        'RecoveryMode','ManualArtifactQuarantineOnly','GuidanceOnly','GuidanceReason',
        'RecoveryBlockReason','ExpectedSha256','ExpectedLength','Provider','SkuId','Last5','OsppPathInstance',
        'ProcessId','ExpectedExecutablePath','ExpectedTaskAction','RegistryValueName','ExpectedRegistryValue',
        'ManualUninstallAllowed','UninstallMethod','UninstallIdentity','UninstallCommandPath','UninstallArguments',
        'UninstallRegistryPath','UninstallPackageId','InstallRoot'
    )) {
        $property = $Candidate.PSObject.Properties[$name]
        $snapshot[$name] = if ($property) { ConvertTo-CleanupCanonicalNode -Value $property.Value } else { $null }
    }
    $json = ([pscustomobject]$snapshot | ConvertTo-Json -Compress -Depth 16)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToUpperInvariant()
    } finally { $sha.Dispose() }
}

function Set-CleanupCandidateSnapshotHashes {
    param([AllowNull()][object[]]$Candidates)
    foreach ($candidate in @($Candidates)) {
        $hash = Get-CleanupCandidateSnapshotHash -Candidate $candidate
        if ($candidate.PSObject.Properties['SnapshotSha256']) { $candidate.SnapshotSha256 = $hash }
        else { $candidate | Add-Member -NotePropertyName SnapshotSha256 -NotePropertyValue $hash }
    }
    return @($Candidates)
}

function Get-CleanupCandidateSetSha256 {
    param([AllowNull()][object[]]$Candidates)
    $rows = @($Candidates | ForEach-Object {
        $candidateHash = if ($_.PSObject.Properties['SnapshotSha256'] -and [string]$_.SnapshotSha256 -match '^[0-9A-Fa-f]{64}$') {
            ([string]$_.SnapshotSha256).ToUpperInvariant()
        } else { Get-CleanupCandidateSnapshotHash -Candidate $_ }
        (([string]$_.Id).ToLowerInvariant() + '|' + $candidateHash)
    } | Sort-Object)
    $payload = "cleanup-candidate-set-v1`n" + ($rows -join "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))) -replace '-', '').ToUpperInvariant()
    } finally { $sha.Dispose() }
}

function New-CleanupScanSnapshot {
    param(
        [AllowNull()][object[]]$Candidates,
        [Parameter(Mandatory = $true)][string]$Scope
    )
    return [pscustomobject][ordered]@{
        SchemaVersion='1.0'
        SnapshotId=[guid]::NewGuid().ToString('D')
        CreatedAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
        ScanScope=$Scope
        CandidateCount=[int]@($Candidates).Count
        CandidateSetSha256=Get-CleanupCandidateSetSha256 -Candidates $Candidates
    }
}

function Get-ThirdPartyCandidateSafePlan {
    param([AllowNull()][object]$Candidate)
    if ($null -eq $Candidate -or [string]$Candidate.Type -ne 'Application') { return @() }
    $guidanceOnly = [bool]($Candidate.PSObject.Properties['GuidanceOnly'] -and [bool]$Candidate.GuidanceOnly)
    if ($guidanceOnly) {
        # A guidance-only candidate may cross the elevated boundary only as a
        # displayable instruction.  It cannot be expanded into any system
        # operation even if a stale or forged plan contains other item types.
        return @($Candidate.PlanItems | Where-Object {
            [string]$_.Type -eq 'Guidance' -and
            [string]$_.Kind -in @('ThirdPartyOfficialSource','ThirdPartyManualReview')
        })
    }
    # Candidate IDs, not plan content, cross the elevation boundary.  Still
    # enforce the recovery gate here so an older/forged plan cannot reset a
    # license store merely by reaching the Administrator process.
    if (-not ($Candidate.PSObject.Properties['ArtifactCleanupAllowed'] -and [bool]$Candidate.ArtifactCleanupAllowed)) { return @() }
    $manualArtifactQuarantineOnly = [bool]($Candidate.PSObject.Properties['ManualArtifactQuarantineOnly'] -and [bool]$Candidate.ManualArtifactQuarantineOnly)
    $manualUninstallAllowed = [bool]($Candidate.PSObject.Properties['ManualUninstallAllowed'] -and [bool]$Candidate.ManualUninstallAllowed -and
        [string]$Candidate.Kind -eq 'ThirdPartyCompleteUninstall')
    $allowLicenseStateReset = [bool]($Candidate.PSObject.Properties['LicenseStateResetAllowed'] -and [bool]$Candidate.LicenseStateResetAllowed)
    $safe = New-Object System.Collections.Generic.List[object]
    foreach ($planItem in @($Candidate.PlanItems)) {
        $type = [string]$planItem.Type
        $kind = [string]$planItem.Kind
        if ($manualArtifactQuarantineOnly) {
            # A manually selected Suspicious row is never allowed to broaden
            # into a vendor action.  It can only quarantine an exact file whose
            # identity will be checked again by the elevated executor.
            if ($type -ne 'File' -or $kind -ne 'ThirdPartyUnauthorizedArtifact') { continue }
            $expectedSha256 = if ($planItem.PSObject.Properties['ExpectedSha256']) { [string]$planItem.ExpectedSha256 } else { '' }
            $expectedLength = if ($planItem.PSObject.Properties['ExpectedLength']) { [int64]$planItem.ExpectedLength } else { -1 }
            if ($expectedSha256 -notmatch '^[0-9A-F]{64}$' -or $expectedLength -lt 0) { continue }
            $safe.Add($planItem)
            continue
        }
        if ($type -eq 'Uninstall') {
            if (-not $manualUninstallAllowed -or $kind -ne 'ThirdPartyCompleteUninstall' -or
                -not ($planItem.PSObject.Properties['ManualUninstallAllowed'] -and [bool]$planItem.ManualUninstallAllowed)) { continue }
            $method = [string]$planItem.UninstallMethod
            $identity = [string]$planItem.UninstallIdentity
            if ($method -eq 'MSI' -and $identity -match '^\{[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}\}$' -and
                -not [string]::IsNullOrWhiteSpace([string]$planItem.UninstallRegistryPath)) {
                $safe.Add($planItem)
            } elseif ($method -eq 'Appx' -and $identity -match '^[A-Za-z0-9._-]+$' -and
                [string]$planItem.UninstallPackageId -eq $identity) {
                $safe.Add($planItem)
            }
            continue
        }
        if ($type -eq 'Firewall' -or $kind -notmatch '^ThirdParty') { continue }
        if ($kind -eq 'ThirdPartyLicenseState' -and -not $allowLicenseStateReset) { continue }
        if ($type -eq 'Process') {
            $processId = if ($planItem.PSObject.Properties['ProcessId']) { [int]$planItem.ProcessId } else { 0 }
            $expectedPath = if ($planItem.PSObject.Properties['ExpectedExecutablePath']) { [string]$planItem.ExpectedExecutablePath } else { '' }
            $expectedSha256 = if ($planItem.PSObject.Properties['ExpectedSha256']) { [string]$planItem.ExpectedSha256 } else { '' }
            $expectedLength = if ($planItem.PSObject.Properties['ExpectedLength']) { [int64]$planItem.ExpectedLength } else { -1 }
            $fullExpectedPath = ''
            try { $fullExpectedPath = [IO.Path]::GetFullPath($expectedPath) } catch {}
            if ($kind -eq 'ThirdPartyUnauthorizedArtifact' -and $processId -gt 0 -and
                $fullExpectedPath -and [string]::Equals($fullExpectedPath, [string]$planItem.Location, [StringComparison]::OrdinalIgnoreCase) -and
                ([IO.Path]::GetExtension($fullExpectedPath)).ToLowerInvariant() -in @('.exe','.com') -and
                $expectedSha256 -match '^[0-9A-F]{64}$' -and $expectedLength -ge 0) {
                $safe.Add($planItem)
            }
            continue
        }
        # The elevated executor can revalidate an exact file path or a bounded
        # hosts entry.  Process/service/task/registry/folder operations are
        # vulnerable to target replacement between scan and execution, so they
        # remain visible as guidance.  The process branch above is the narrow
        # exception: PID, path, length and SHA-256 are all bound and rechecked.
        if ($type -notin @('File','Hosts','Guidance')) { continue }
        if ($type -eq 'File' -and $kind -ne 'ThirdPartyUnauthorizedArtifact') { continue }
        if ($type -eq 'Hosts' -and $kind -ne 'ThirdPartyHostsEntry') { continue }
        $safe.Add($planItem)
    }
    return $safe.ToArray()
}

function Get-DeepCleanupCandidates {
    param($Findings)
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($finding in @($Findings)) {
        $type = [string]$finding.Type
        if ($type -in @("Process", "Service", "ScheduledTask", "Folder")) {
            $kind = if ($type -eq "ScheduledTask") { "ActivatorTask" } else { "Activator$type" }
            $expectedExecutablePath = if ($type -in @('Process','Service')) {
                Get-CleanupExecutablePathFromCommandLine ([string]$finding.Location)
            } else { '' }
            $items.Add((New-CleanupItem -Type $type -Kind $kind -Name ([string]$finding.Name) `
                -Location ([string]$finding.Location) -Detail ([string]$finding.Action) `
                -ComponentScope (Get-CleanupRecordComponentScope -Record $finding) `
                -ProcessId $(if ($finding.PSObject.Properties['ProcessId']) { [int]$finding.ProcessId } else { 0 }) `
                -ExpectedExecutablePath $expectedExecutablePath `
                -ExpectedTaskAction $(if ($type -eq 'ScheduledTask') { [string]$finding.Location } else { '' })))
            if ($expectedExecutablePath -and (Test-Path -LiteralPath $expectedExecutablePath -PathType Leaf) -and
                (Test-CleanupKnownActivatorText (([string]$finding.Name) + ' ' + $expectedExecutablePath))) {
                $items.Add((New-CleanupItem -Type 'File' -Kind 'ActivatorBoundExecutable' `
                    -Name ([IO.Path]::GetFileName($expectedExecutablePath)) -Location $expectedExecutablePath `
                    -Detail (Get-CleanupText 'cleanupReport.candidate.boundExecutable') `
                    -ComponentScope (Get-CleanupRecordComponentScope -Record $finding)))
            }
        } elseif ($type -eq 'StartupRegistry') {
            $items.Add((New-CleanupItem -Type 'Registry' -Kind 'ActivatorStartupValue' -Name ([string]$finding.Name) `
                -Location ([string]$finding.Location) -Detail ([string]$finding.Action) `
                -ComponentScope (Get-CleanupRecordComponentScope -Record $finding) `
                -RegistryValueName ([string]$finding.RegistryValueName) -ExpectedRegistryValue ([string]$finding.ExpectedRegistryValue)))
        }
    }

    # Windows has a machine-wide /ckms operation.  Office host overrides are
    # handled separately through the exact OSPP instance so they remain
    # retryable even when OSPP does not report a Last5 key suffix.
    foreach ($path in @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
    )) {
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $server = [string]$item.KeyManagementServiceName
            if ($server -and -not (Test-ApprovedKms $server)) {
                $items.Add((New-CleanupItem -Type "Registry" -Kind "KmsOverride" `
                    -Name (Get-CleanupText "cleanupReport.candidate.unapprovedKms") -Location $path `
                    -Detail (Get-CleanupText "cleanupReport.candidate.unapprovedKmsDetail" @($server)) `
                    -ComponentScope 'Windows' -Provider 'WindowsSPP' `
                    -RegistryValueName 'KeyManagementServiceName' -ExpectedRegistryValue $server))
            }
        } catch {}
    }

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
    try {
        $policy = Get-ItemProperty -LiteralPath $policyPath -ErrorAction Stop
        if ([int]$policy.NoGenTicket -eq 1) {
            # Anything under HKLM\SOFTWARE\Policies is managed state.  It may
            # come from local/domain GPO or an MDM CSP and must never be deleted
            # by this tool; report the source and let the administrator change
            # the owning policy.
            $items.Add((New-CleanupItem -Type "Guidance" -Kind "ManagedNoGenTicketPolicy" `
                -Name "Policy SPP NoGenTicket=1" -Location $policyPath `
                -Detail (Get-CleanupText "cleanupReport.candidate.noGenTicketDetail") -ComponentScope 'Windows' `
                -GuidanceOnly $true -GuidanceReason (Get-CleanupText 'cleanupReport.remediation.blockedByPolicy') `
                -Provider 'WindowsSPP' -InitialRemediationState 'BlockedByPolicy' -RemediationRetryAllowed $false `
                -RemediationBlockCode 'ManagedNoGenTicketPolicy' `
                -RemediationBlockDetail 'HKLM\SOFTWARE\Policies; GroupPolicyOrMDM'))
        }
    } catch {}

    foreach ($imageName in @("SppExtComObj.exe", "sppsvc.exe", "osppsvc.exe")) {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$imageName"
        try {
            $ifeoItem = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            foreach ($property in @($ifeoItem.PSObject.Properties | Where-Object { [string]$_.Name -notmatch '^PS' })) {
                $valueText = [string]$property.Value
                if ((([string]$property.Name) + ' ' + $valueText) -notmatch "(?i)(\bdebugger\b|\bverifierdlls\b|kms|activator|hook\.dll|sppextcomobj(?:hook|patcher))") { continue }
                $items.Add((New-CleanupItem -Type "Registry" -Kind "IfeoHookValue" `
                    -Name ("IFEO hook: " + $imageName + ' / ' + [string]$property.Name) -Location $path `
                    -Detail (Get-CleanupText "cleanupReport.candidate.ifeoDetail") `
                    -ComponentScope $(if ($imageName -eq 'osppsvc.exe') { 'Office' } else { 'Windows' }) `
                    -RegistryValueName ([string]$property.Name) -ExpectedRegistryValue $valueText))
            }
        } catch {}
    }

    foreach ($hookPath in @(
        (Get-ToolNativeSystemPath "SppExtComObjHook.dll"),
        (Join-Path $env:windir "SysWOW64\SppExtComObjHook.dll")
    )) {
        if (Test-Path -LiteralPath $hookPath -PathType Leaf) {
            $items.Add((New-CleanupItem -Type "File" -Kind "HookFile" `
                -Name (Split-Path $hookPath -Leaf) -Location $hookPath `
                -Detail (Get-CleanupText "cleanupReport.candidate.hookFileDetail") -ComponentScope 'Windows'))
        }
    }

    try {
        $preference = Get-MpPreference -ErrorAction Stop
        foreach ($excludedPath in @($preference.ExclusionPath)) {
            if (Test-CleanupKnownActivatorText -Text ([string]$excludedPath)) {
                $items.Add((New-CleanupItem -Type "Defender" -Kind "ExclusionPath" `
                    -Name (Get-CleanupText "cleanupReport.candidate.defenderExclusion") -Location ([string]$excludedPath) `
                    -Detail (Get-CleanupText "cleanupReport.candidate.defenderExclusionDetail") -ComponentScope 'Shared'))
            }
        }
    } catch {}

    return @($items | Group-Object Id | ForEach-Object { $_.Group[0] } | Sort-Object Type, Name, Location)
}

function Get-AllCleanupCandidates {
    param($Products, $Findings, $OfficeEntries, $ThirdPartyCandidates = @())

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-DeepCleanupCandidates -Findings $Findings)) { $items.Add($item) }

    foreach ($product in @($Products | Where-Object {
        ((Get-LicenseChannel $_) -eq 'KMS' -and -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine))) -or
        ([int]$_.LicenseStatus -eq 4 -and -not [string]::IsNullOrWhiteSpace([string]$_.PartialProductKey))
    })) {
        $channel = Get-LicenseChannel $product
        $kind = if ([int]$product.LicenseStatus -eq 4 -and $channel -ne 'KMS') { 'WindowsNonGenuineLicense' } else { 'WindowsKmsLicense' }
        $items.Add((New-CleanupItem -Type "License" -Kind $kind `
            -Name ([string]$product.Name) `
            -Location ("KMS=" + [string]$product.KeyManagementServiceMachine + "; PartialKey=" + [string]$product.PartialProductKey) `
            -TargetId ([string]$product.ID) `
            -Detail (Get-CleanupText $(if ($kind -eq 'WindowsNonGenuineLicense') { 'cleanupReport.candidate.windowsNonGenuineDetail' } else { 'cleanupReport.candidate.windowsKmsDetail' })) -ComponentScope 'Windows'))
    }

    $unapprovedOfficeEntries = @($OfficeEntries | Where-Object { -not (Test-ApprovedKms ([string]$_.Server)) })

    # A shared host override is one retryable candidate per concrete OSPP
    # instance.  It intentionally does not require SKU/Last5, because /remhst
    # is path-wide and OSPP can legitimately omit Last5 after a key was removed.
    foreach ($hostGroup in @($unapprovedOfficeEntries | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.Server) -and
        -not [string]::IsNullOrWhiteSpace((Get-OfficeKmsPathKey -Path ([string]$_.Path)))
    } | Group-Object { Get-OfficeKmsPathKey -Path ([string]$_.Path) })) {
        $hostEntry = @($hostGroup.Group | Select-Object -First 1)[0]
        $hostIdentity = Get-OfficeKmsHostOverrideIdentity -Path ([string]$hostEntry.Path)
        $servers = @($hostGroup.Group | ForEach-Object { [string]$_.Server } | Where-Object { $_ } | Select-Object -Unique)
        $items.Add((New-CleanupItem -Type 'License' -Kind 'OfficeKmsHostOverride' `
            -Name (Get-CleanupText 'cleanupReport.candidate.officeKmsHostOverride') `
            -Location ([string]$hostEntry.Path) -TargetId $hostIdentity `
            -Detail (Get-CleanupText 'cleanupReport.candidate.officeKmsHostOverrideDetail' @($servers -join ', ')) `
            -ComponentScope 'Office' -IdentitySeed $hostIdentity -Provider 'OfficeOSPP' `
            -OsppPathInstance ([string]$hostEntry.Path)))
    }

    foreach ($entry in $unapprovedOfficeEntries) {
        $last5Label = if ([string]::IsNullOrWhiteSpace([string]$entry.Last5)) { Get-CleanupText "cleanupReport.value.noKey" } else { [string]$entry.Last5 }
        $serverLabel = if ([string]::IsNullOrWhiteSpace([string]$entry.Server)) { Get-CleanupText "cleanupReport.value.dnsNoOverride" } else { [string]$entry.Server }
        $targetId = Get-OfficeKmsTargetIdentity -Entry $entry
        # A KMS override without a stable path/SKU/key identity is not safe to
        # remove automatically.  It still becomes a visible guidance-only
        # row so post-check can name the exact residue instead of reporting an
        # unexplained remaining count.
        if ([string]::IsNullOrWhiteSpace($targetId)) {
            # Missing Last5 blocks key removal, but never blocks the independent
            # host-override candidate created above.
            $items.Add((New-CleanupItem -Type 'Guidance' -Kind 'OfficeKmsManualReview' `
                -Name ('Office KMS ' + $last5Label + ' - ' + [string]$entry.LicenseName) `
                -Location ([string]$entry.Path) `
                -Detail (Get-CleanupText 'cleanupReport.candidate.officeKmsManualReview' @([string]$entry.SkuId, [string]$entry.LicenseStatus, $serverLabel)) `
                -ComponentScope 'Office' -GuidanceOnly $true -GuidanceReason (Get-CleanupText 'cleanupReport.candidate.officeKmsManualReviewReason') `
                -IdentitySeed ('office-kms-guidance|' + [string]$entry.Path + '|' + [string]$entry.SkuId + '|' + [string]$entry.Last5) `
                -Provider 'OfficeOSPP' -SkuId ([string]$entry.SkuId) -Last5 ([string]$entry.Last5) `
                -OsppPathInstance ([string]$entry.Path) -InitialRemediationState 'NeedsOfficeRepair' `
                -RemediationRetryAllowed $false -RemediationBlockCode 'MissingStableKeyIdentity'))
            continue
        }
        $items.Add((New-CleanupItem -Type "License" -Kind "OfficeKmsLicense" `
            -Name ("Office KMS $last5Label - " + [string]$entry.LicenseName) `
            -Location ([string]$entry.Path) `
            -TargetId $targetId `
            -Detail (Get-CleanupText "cleanupReport.candidate.officeKmsDetail" @([string]$entry.SkuId, [string]$entry.LicenseStatus, $serverLabel)) `
            -ComponentScope 'Office' -IdentitySeed $targetId -Provider 'OfficeOSPP' `
            -SkuId ([string]$entry.SkuId) -Last5 ([string]$entry.Last5) -OsppPathInstance ([string]$entry.Path)))
    }

    foreach ($thirdPartyCandidate in @($ThirdPartyCandidates)) { $items.Add($thirdPartyCandidate) }

    $uniqueItems = @($items.ToArray() | Group-Object Id | ForEach-Object { $_.Group[0] } | Sort-Object Type, Name, Location)
    return @(Set-CleanupCandidateSnapshotHashes -Candidates $uniqueItems)
}

function Get-ScopedCleanupCandidates {
    param(
        $CleanupItems,
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")]
        [string]$Scope = "All"
    )

    return @($CleanupItems | Where-Object { Test-CleanupRecordMatchesScope -Record $_ -Scope $Scope })
}

function Test-CleanupScopeReady {
    param(
        $Verification,
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")]
        [string]$Scope = "All"
    )

    if ([int]$Verification.ScanWarningCount -gt 0) { return $false }
    $includesWindows = Test-CleanupScanScopeIncludes -Scope $Scope -Component "Windows"
    $includesOffice = Test-CleanupScanScopeIncludes -Scope $Scope -Component "Office"
    $includesThirdParty = Test-CleanupScanScopeIncludes -Scope $Scope -Component "ThirdParty"
    if (($includesWindows -or $includesOffice) -and (
        [int]$Verification.ActiveActivatorFindingCount -ne 0 -or
        [int]$Verification.ConfigurationResidueCount -ne 0)) { return $false }
    if ($includesWindows -and [int]$Verification.UnapprovedWindowsKmsCount -ne 0) { return $false }
    if ($includesOffice -and [int]$Verification.UnapprovedOfficeKmsCount -ne 0) { return $false }
    if ($includesThirdParty) {
        $findingCount = if ($Verification.PSObject.Properties['ThirdPartyRemediationFindingCount']) {
            [int]$Verification.ThirdPartyRemediationFindingCount
        } elseif ($Verification.PSObject.Properties['ThirdPartyNeedsReviewCount']) {
            [int]$Verification.ThirdPartyNeedsReviewCount
        } else {
            [int]$Verification.ThirdPartyCandidateCount
        }
        if ($findingCount -ne 0) { return $false }
    }
    return $true
}

function Add-ThirdPartyVerification {
    param($Verification, $ThirdPartyCandidates, $ThirdPartyApplications = @(), [switch]$Included)
    $candidateCount = [int]@($ThirdPartyCandidates).Count
    $autoEligibleCount = [int]@($ThirdPartyCandidates | Where-Object { [bool]$_.AutoEligible }).Count
    $reviewCount = [int]@($ThirdPartyApplications | Where-Object { [bool]$_.NeedsReview }).Count
    $applicationFindingCount = [int]@($ThirdPartyApplications | Where-Object {
        if ($_.PSObject.Properties['CleanupFinding']) { return [bool]$_.CleanupFinding }
        return [bool]([string]$_.AssessmentCode -in @('NonGenuine','Suspicious','IntegrityCompromised'))
    }).Count
    $standaloneFindingCount = [int]@($ThirdPartyCandidates | Where-Object {
        @($_.ApplicationIds).Count -eq 0 -and @($_.PlanItems | Where-Object { [string]$_.Type -eq 'File' }).Count -gt 0
    }).Count
    $remediationFindingCount = [int]($applicationFindingCount + $standaloneFindingCount)
    $unsupportedReviewCount = [int]@($ThirdPartyApplications | Where-Object {
        $isCleanupFinding = if ($_.PSObject.Properties['CleanupFinding']) { [bool]$_.CleanupFinding } else { [string]$_.AssessmentCode -in @('NonGenuine','Suspicious','IntegrityCompromised') }
        $isCleanupFinding -and -not [bool]$_.RemediationSupported
    }).Count
    $Verification | Add-Member -NotePropertyName ThirdPartyCandidateCount -NotePropertyValue $candidateCount -Force
    $Verification | Add-Member -NotePropertyName ThirdPartyAutoEligibleCount -NotePropertyValue $autoEligibleCount -Force
    $Verification | Add-Member -NotePropertyName ThirdPartyNeedsReviewCount -NotePropertyValue $reviewCount -Force
    $Verification | Add-Member -NotePropertyName ThirdPartyRemediationFindingCount -NotePropertyValue $remediationFindingCount -Force
    $Verification | Add-Member -NotePropertyName ThirdPartyUnsupportedReviewCount -NotePropertyValue $unsupportedReviewCount -Force
    if (-not $Included) { return $Verification }
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($check in @($Verification.ReadinessChecks)) { $checks.Add($check) }
    if ($remediationFindingCount -gt 0) {
        $baseScopeWasReady = [bool]$Verification.ReadyForOfficialActivation
        $thirdPartyBlockedConclusion = Get-CleanupText "cleanupReport.thirdParty.verification.blocked" @($remediationFindingCount, $candidateCount)
        $Verification.ReadyForOfficialActivation = $false
        $Verification.Conclusion = if ($baseScopeWasReady) {
            [string]$thirdPartyBlockedConclusion
        } else {
            ([string]$Verification.Conclusion + ' ' + [string]$thirdPartyBlockedConclusion).Trim()
        }
        $guidance = New-Object System.Collections.Generic.List[string]
        foreach ($step in @($Verification.HandlingGuidance | Where-Object { [string]$_ -ne (Get-CleanupText "cleanupReport.guidance.ready") })) { $guidance.Add([string]$step) }
        $guidance.Add((Get-CleanupText "cleanupReport.thirdParty.guidance" @($remediationFindingCount, $candidateCount, $autoEligibleCount, $unsupportedReviewCount)))
        $Verification.HandlingGuidance = $guidance.ToArray()
        $checks.Add([pscustomobject]@{
            Name=(Get-CleanupText "cleanupReport.thirdParty.readiness.name")
            StatusCode='Fail'; Status=(Get-CleanupText "cleanupReport.status.fail")
            Detail=(Get-CleanupText "cleanupReport.thirdParty.readiness.blocked" @($remediationFindingCount, $candidateCount, $autoEligibleCount, $unsupportedReviewCount))
        })
    } else {
        $checks.Add([pscustomobject]@{
            Name=(Get-CleanupText "cleanupReport.thirdParty.readiness.name")
            StatusCode='Pass'; Status=(Get-CleanupText "cleanupReport.status.pass")
            Detail=(Get-CleanupText "cleanupReport.thirdParty.readiness.pass")
        })
    }
    $Verification.ReadinessChecks = $checks.ToArray()
    $Verification.ScopeNote = ([string]$Verification.ScopeNote + ' ' + (Get-CleanupText "cleanupReport.thirdParty.scope")).Trim()
    return $Verification
}

function Get-SelectedCleanupIds {
    $script:SelectionAccepted = $false
    $script:SelectionErrorCode = 'SelectionFileMissing'
    $script:SelectionErrorDetail = ''
    $script:SelectedCleanupSnapshots = @{}
    $script:SelectedSourceSnapshotId = ''
    $script:SelectedSourceCandidateSetSha256 = ''
    if ([string]::IsNullOrWhiteSpace($SelectionFile) -or -not (Test-Path -LiteralPath $SelectionFile -PathType Leaf)) { return @() }
    try {
        $allowedRoot = if (-not [string]::IsNullOrWhiteSpace($env:TOOL_SECURE_RUNTIME_DIR)) { $env:TOOL_SECURE_RUNTIME_DIR } else { Join-Path $PSScriptRoot "runtime" }
        if ($env:TOOL_SECURE_LAUNCH -ne "1") { throw 'SecureLaunchRequired' }
        if (-not (Test-ProtectedDirectoryAcl -Path $PSScriptRoot -AllowCurrentUserForUserScope)) { throw 'ToolDirectoryAclInvalid' }
        if (-not (Test-ProtectedDirectoryAcl -Path $allowedRoot -AllowCurrentUserForUserScope)) { throw 'RuntimeDirectoryAclInvalid' }
        $rootFull = ([IO.Path]::GetFullPath($allowedRoot)).TrimEnd('\') + '\'
        $selectionFull = [IO.Path]::GetFullPath($SelectionFile)
        if (-not $selectionFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'SelectionFileOutsideRuntime' }
        if (-not [string]::Equals(([IO.Path]::GetDirectoryName($selectionFull).TrimEnd('\') + '\'), $rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'SelectionFileMustBeDirectChild' }
        $selectionItem = Get-Item -LiteralPath $selectionFull -Force -ErrorAction Stop
        if (($selectionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'SelectionFileReparsePointRejected' }
        if ([int64]$selectionItem.Length -le 0 -or [int64]$selectionItem.Length -gt 262144) { throw 'SelectionFileSizeInvalid' }
        $selection = Get-Content -LiteralPath $selectionFull -Raw -ErrorAction Stop | ConvertFrom-Json
        if ([string]$selection.SchemaVersion -ne '1.1') { throw 'SelectionSchemaInvalid' }
        $requestId = [guid]::Empty
        if (-not [guid]::TryParse([string]$selection.RequestId, [ref]$requestId) -or $requestId -eq [guid]::Empty) { throw 'SelectionRequestIdInvalid' }
        if (-not [string]::Equals([string]$selection.ScanScope, [string]$ScanScope, [StringComparison]::OrdinalIgnoreCase)) { throw 'SelectionScopeMismatch' }
        $sourceSnapshotId = [guid]::Empty
        if (-not [guid]::TryParse([string]$selection.SourceSnapshotId, [ref]$sourceSnapshotId) -or $sourceSnapshotId -eq [guid]::Empty) { throw 'SelectionSourceSnapshotInvalid' }
        $sourceSetHash = ([string]$selection.SourceCandidateSetSha256).Trim().ToUpperInvariant()
        if ($sourceSetHash -notmatch '^[0-9A-F]{64}$') { throw 'SelectionSourceSnapshotInvalid' }
        $script:SelectedSourceSnapshotId = $sourceSnapshotId.ToString('D')
        $script:SelectedSourceCandidateSetSha256 = $sourceSetHash
        $createdAtUtc = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$selection.CreatedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$createdAtUtc)) { throw 'SelectionTimestampInvalid' }
        $selectionAge = [DateTimeOffset]::UtcNow - $createdAtUtc.ToUniversalTime()
        if ($selectionAge.TotalMinutes -lt -5 -or $selectionAge.TotalHours -gt 2) { throw 'SelectionExpired' }
        $selectedCandidates = @($selection.SelectedCandidates)
        if ($selectedCandidates.Count -eq 0 -or $selectedCandidates.Count -gt 2048) { throw 'SelectionSnapshotsInvalid' }
        foreach ($selectedCandidate in $selectedCandidates) {
            $selectedId = ([string]$selectedCandidate.Id).Trim().ToLowerInvariant()
            $selectedHash = ([string]$selectedCandidate.SnapshotSha256).Trim().ToUpperInvariant()
            if ([string]::IsNullOrWhiteSpace($selectedId) -or $selectedId.Length -gt 4096 -or $selectedHash -notmatch '^[0-9A-F]{64}$') {
                throw 'SelectionSnapshotsInvalid'
            }
            if ($script:SelectedCleanupSnapshots.ContainsKey($selectedId)) { throw 'SelectionSnapshotsInvalid' }
            $script:SelectedCleanupSnapshots[$selectedId] = $selectedHash
        }
        $ids = @($script:SelectedCleanupSnapshots.Keys | Sort-Object)
        if ($ids.Count -eq 0 -or $ids.Count -gt 2048 -or @($ids | Where-Object { $_.Length -gt 4096 }).Count -gt 0) { throw 'SelectionIdsInvalid' }
        $script:SelectionAccepted = $true
        $script:SelectionErrorCode = ''
        $script:SelectionErrorDetail = ''
        return $ids
    } catch {
        $selectionError = [string]$_.Exception.Message
        $knownSelectionErrors = @(
            'SecureLaunchRequired','ToolDirectoryAclInvalid','RuntimeDirectoryAclInvalid','SelectionFileOutsideRuntime',
            'SelectionFileMustBeDirectChild','SelectionFileReparsePointRejected','SelectionFileSizeInvalid','SelectionSchemaInvalid',
            'SelectionRequestIdInvalid','SelectionScopeMismatch','SelectionTimestampInvalid','SelectionExpired','SelectionIdsInvalid',
            'SelectionSnapshotsInvalid','SelectionSourceSnapshotInvalid'
        )
        $script:SelectionErrorCode = if ($knownSelectionErrors -contains $selectionError) { $selectionError } else { 'SelectionReadFailed' }
        $script:SelectionErrorDetail = [string]$_.Exception.GetType().Name
        return @()
    }
}

function Protect-HistoryText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $safe = $Text -replace "(?i)\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}\b", (Get-CleanupText "cleanupReport.redaction.productKey")
    $safe = $safe -replace '(?i)https?://[^\s"'']+', (Get-CleanupText "cleanupReport.redaction.url")
    $safe = ($safe -replace "\s+", " ").Trim()
    if ($safe.Length -gt 240) { $safe = $safe.Substring(0, 240) + "..." }
    return $safe
}

function Get-InvalidActivationHistory {
    # Lịch sử chỉ là bằng chứng quá khứ, không được dùng một mình để kết luận
    # crack vẫn đang hoạt động hoặc để tự động gỡ product key.
    $history = New-Object System.Collections.Generic.List[object]
    $strictPattern = "(?i)(kmspico|kmsauto(?:s|[\s._-]*(?:net|lite|portable|plus|\+\+))?|auto[\s._-]*kms|kms[\s._-]*(?:38|vl(?:[\s._-]*all)?)|kms-r|aact(?:[\s._-]*(?:network|portable))?|sppextcomobj(?:hook|patcher)|spp[\s._-]*(?:hook|patcher)|microsoft[\s_-]+toolkit|hwidgen|massgrave|\bmas[\s._-]*(?:aio|all[\s._-]*in[\s._-]*one|activat(?:ion|or)|hwid|kms|ohook|tsforge)\b|\bpmas(?:[\s._-]*(?:aio|all[\s._-]*in[\s._-]*one|activat(?:ion|or)|hwid|kms|ohook|tsforge))?\b|\bmicrosoft[\s._-]*activation[\s._-]*scripts?\b|\bactivation[\s._-]*program[\s._-]*(?:v(?:ersion)?[\s._-]*)?1(?:\.|\s+|[_-])17\b|(?<![a-z0-9.-])erturk-dev\.netlify\.app/run(?![a-z0-9._-])|tsforge|ohook|digital license activation|\bactivator\b|0xC004F074|VOLUME_KMSCLIENT)"
    $since = (Get-Date).AddDays(-180)

    $eventQueries = @(
        [pscustomobject]@{ LogName="Application"; ProviderName="Microsoft-Windows-Security-SPP"; Source=(Get-CleanupText "cleanupReport.history.softwareProtection") },
        [pscustomobject]@{ LogName="Microsoft-Windows-Windows Defender/Operational"; ProviderName="Microsoft-Windows-Windows Defender"; Source=(Get-CleanupText "cleanupReport.history.defender") },
        [pscustomobject]@{ LogName="Microsoft-Windows-TaskScheduler/Operational"; ProviderName="Microsoft-Windows-TaskScheduler"; Source=(Get-CleanupText "cleanupReport.history.taskScheduler") }
    )
    foreach ($query in $eventQueries) {
        try {
            Get-WinEvent -FilterHashtable @{ LogName=$query.LogName; StartTime=$since } -MaxEvents 500 -ErrorAction Stop |
                Where-Object { ([string]$_.Message) -match $strictPattern } |
                Select-Object -First 50 | ForEach-Object {
                    $history.Add([pscustomobject]@{
                        Time = if ($_.TimeCreated) { $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss") } else { Get-CleanupText "common.unknown" }
                        Source = $query.Source
                        EventId = [string]$_.Id
                        Evidence = Protect-HistoryText ([string]$_.Message)
                    })
                }
        } catch {}
    }

    # PSReadLine không lưu thời gian từng lệnh. Chỉ lấy dòng khớp mẫu đặc hiệu,
    # che product key/URL và không sao chép các dòng lịch sử khác.
    try {
        $userRoot = Join-Path $env:SystemDrive "Users"
        Get-ChildItem -LiteralPath $userRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $historyFile = Join-Path $_.FullName "AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
            if (Test-Path -LiteralPath $historyFile) {
                $lastWrite = (Get-Item -LiteralPath $historyFile -ErrorAction SilentlyContinue).LastWriteTime
                Get-Content -LiteralPath $historyFile -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match $strictPattern } |
                    Select-Object -Last 25 | ForEach-Object {
                        $history.Add([pscustomobject]@{
                            Time = if ($lastWrite) { Get-CleanupText "cleanupReport.history.fileUpdated" @($lastWrite.ToString("yyyy-MM-dd HH:mm:ss")) } else { Get-CleanupText "cleanupReport.history.noCommandTime" }
                            Source = Get-CleanupText "cleanupReport.history.powerShell"
                            EventId = "PSReadLine"
                            Evidence = Protect-HistoryText ([string]$_)
                        })
                    }
            }
        }
    } catch {}

    return @($history | Sort-Object Time -Descending | Select-Object -First 150)
}

function Get-ActivationConfigurationResidues {
    $residues = New-Object System.Collections.Generic.List[object]
    $sppPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform",
        "HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform"
    )
    foreach ($path in $sppPaths) {
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $server = [string]$item.KeyManagementServiceName
            if ($server -and -not (Test-ApprovedKms $server)) {
                $residues.Add([pscustomobject]@{
                    Type="KMSConfig"; Name=(Get-CleanupText "cleanupReport.residue.unapprovedKms"); Location=$path; Value=$server
                    ComponentScope=$(if ($path -match 'OfficeSoftwareProtectionPlatform') { 'Office' } else { 'Windows' })
                })
            }
        } catch {}
    }

    foreach ($imageName in @("SppExtComObj.exe", "sppsvc.exe", "osppsvc.exe")) {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$imageName"
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $valueText = ($item | Out-String)
            if ($valueText -match "(?i)(\bdebugger\b|\bverifierdlls\b|kms|activator|hook\.dll|sppextcomobj(?:hook|patcher))") {
                $residues.Add([pscustomobject]@{
                    Type="IFEO"; Name=$imageName; Location=$path; Value=(Protect-HistoryText $valueText)
                    ComponentScope=$(if ($imageName -eq 'osppsvc.exe') { 'Office' } else { 'Windows' })
                })
            }
        } catch {}
    }

    foreach ($dllPath in @(
        (Get-ToolNativeSystemPath "SppExtComObjHook.dll"),
        (Join-Path $env:windir "SysWOW64\SppExtComObjHook.dll")
    )) {
        if (Test-Path -LiteralPath $dllPath) {
            $residues.Add([pscustomobject]@{ Type="HookFile"; Name="SppExtComObjHook.dll"; Location=$dllPath; Value=(Get-CleanupText "cleanupReport.residue.hookFile"); ComponentScope='Windows' })
        }
    }

    try {
        $preference = Get-MpPreference -ErrorAction Stop
        foreach ($excludedPath in @($preference.ExclusionPath)) {
            if (Test-CleanupKnownActivatorText -Text ([string]$excludedPath)) {
                $residues.Add([pscustomobject]@{ Type="DefenderExclusion"; Name=(Get-CleanupText "cleanupReport.residue.defenderExclusion"); Location=[string]$excludedPath; Value=(Get-CleanupText "cleanupReport.residue.removeExclusion"); ComponentScope='Shared' })
            }
        }
    } catch {}

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
    try {
        $policy = Get-ItemProperty -LiteralPath $policyPath -ErrorAction Stop
        if ([int]$policy.NoGenTicket -eq 1) {
            $residues.Add([pscustomobject]@{ Type="SPPPolicy"; Name="NoGenTicket=1"; Location=$policyPath; Value=(Get-CleanupText "cleanupReport.residue.noGenTicket"); ComponentScope='Windows' })
        }
    } catch {}
    return $residues
}

function Get-ActivationReadinessDiagnostics {
    # Chẩn đoán bổ sung, chỉ đọc. Các kết quả này không thay đổi quyết định
    # ReadyForOfficialActivation hiện có để giữ tương thích v3.0.
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($serviceName in @("sppsvc", "osppsvc", "w32time")) {
        try {
            $svc = Safe-Cim Win32_Service | Where-Object { $_.Name -eq $serviceName } | Select-Object -First 1
            if (-not $svc) {
                $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.service" @($serviceName)); StatusCode="NotApplicable"; Status=(Get-CleanupText "cleanupReport.status.notApplicable"); Detail=(Get-CleanupText "cleanupReport.readiness.serviceMissing") })
            } elseif ([string]$svc.StartMode -eq "Disabled") {
                $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.service" @($serviceName)); StatusCode="Review"; Status=(Get-CleanupText "cleanupReport.status.review"); Detail=(Get-CleanupText "cleanupReport.readiness.serviceDisabled") })
            } else {
                $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.service" @($serviceName)); StatusCode="Pass"; Status=(Get-CleanupText "cleanupReport.status.pass"); Detail=(Get-CleanupText "cleanupReport.readiness.serviceState" @($svc.StartMode, $svc.State)) })
            }
        } catch {
            $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.service" @($serviceName)); StatusCode="Unverified"; Status=(Get-CleanupText "cleanupReport.status.unverified"); Detail=(Get-CleanupText "cleanupReport.readiness.serviceUnreadable") })
        }
    }

    foreach ($filePath in @(
        (Get-ToolNativeSystemPath "sppsvc.exe"),
        (Get-ToolNativeSystemPath "SppExtComObj.exe"),
        (Get-ToolNativeSystemPath "sppwinob.dll")
    )) {
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.licenseFile"); StatusCode="Review"; Status=(Get-CleanupText "cleanupReport.status.review"); Detail=(Get-CleanupText "cleanupReport.readiness.fileMissing" @($filePath)) })
            continue
        }
        $signature = Get-CleanupText "cleanupReport.value.notChecked"
        try {
            $sig = Get-AuthenticodeSignature -LiteralPath $filePath -ErrorAction Stop
            $signature = [string]$sig.Status
        } catch {}
        $statusCode = if ($signature -eq "Valid") { "Pass" } elseif ($signature -eq "NotSigned") { "Review" } else { "Unverified" }
        $status = Get-CleanupText ("cleanupReport.status." + $statusCode.ToLowerInvariant())
        $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.licenseFileSignature"); StatusCode=$statusCode; Status=$status; Detail="$filePath | Authenticode=$signature" })
    }

    $pending = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    ) | Where-Object { Test-Path -LiteralPath $_ }
    if ($pending.Count -gt 0) {
        $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.pendingRestart"); StatusCode="Review"; Status=(Get-CleanupText "cleanupReport.status.review"); Detail=(Get-CleanupText "cleanupReport.readiness.restartRequired") })
    } else {
        $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.pendingRestart"); StatusCode="Pass"; Status=(Get-CleanupText "cleanupReport.status.pass"); Detail=(Get-CleanupText "cleanupReport.readiness.noRestartFlag") })
    }
    return $checks.ToArray()
}

function Get-CleanupVerification {
    param(
        $Products, $Findings, $OfficeEntries, $History,
        [ValidateSet('All','Windows','Office','ThirdParty','WindowsOffice','WindowsThirdParty','OfficeThirdParty')]
        [string]$Scope = 'All'
    )
    $includeWindows = Test-CleanupScanScopeIncludes -Scope $Scope -Component 'Windows'
    $includeOffice = Test-CleanupScanScopeIncludes -Scope $Scope -Component 'Office'
    $includeWindowsOffice = [bool]($includeWindows -or $includeOffice)
    $unapprovedWindows = @($Products | Where-Object { $includeWindows -and
        (Get-LicenseChannel $_) -eq "KMS" -and -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine))
    })
    $unapprovedOffice = @($OfficeEntries | Where-Object { $includeOffice -and -not (Test-ApprovedKms ([string]$_.Server)) })
    $scopedFindings = @($Findings | Where-Object { Test-CleanupRecordMatchesScope -Record $_ -Scope $Scope })
    $residues = @($(if ($includeWindowsOffice) {
        Get-ActivationConfigurationResidues | Where-Object { Test-CleanupRecordMatchesScope -Record $_ -Scope $Scope }
    }))
    $blockerCount = [int]($unapprovedWindows.Count + $unapprovedOffice.Count + $scopedFindings.Count + $residues.Count)
    $scanWarnings = @($script:ScanWarnings | Select-Object -Unique)
    $ready = [bool]($blockerCount -eq 0 -and $scanWarnings.Count -eq 0)
    $protected = if ($includeWindows) { Get-ProtectedLicenseInfo -Products $Products } else {
        [pscustomobject]@{ Protected=$false; Channel=(Get-CleanupText 'common.unknown'); Reason=(Get-CleanupText 'cleanupReport.protected.none') }
    }
    $readiness = @($(if ($includeWindows) { Get-ActivationReadinessDiagnostics }))
    $readinessReviewCount = @($readiness | Where-Object { $_.StatusCode -in @("Review", "Unverified") }).Count
    $conclusion = if ($scanWarnings.Count -gt 0) {
        Get-CleanupText "cleanupReport.verification.inconclusive"
    } elseif (-not $ready) {
        Get-CleanupText "cleanupReport.verification.notClean"
    } elseif ([bool]$protected.Protected) {
        Get-CleanupText "cleanupReport.verification.passProtected" @($protected.Channel)
    } else {
        Get-CleanupText "cleanupReport.verification.passReady"
    }
    $handlingGuidance = New-Object System.Collections.Generic.List[string]
    if ($scanWarnings.Count -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.scanFailure"))
    }
    if ($unapprovedWindows.Count -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.windowsKms"))
    }
    if ($unapprovedOffice.Count -gt 0) {
        $officeLabels = @($unapprovedOffice | ForEach-Object {
            $keyLabel = if ([string]::IsNullOrWhiteSpace([string]$_.Last5)) { Get-CleanupText "cleanupReport.value.noKey" } else { [string]$_.Last5 }
            "$([string]$_.LicenseName) [$keyLabel]"
        })
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.officeKms" @($officeLabels -join '; ')))
    }
    if ($scopedFindings.Count -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.activeActivator"))
    }
    if ($residues.Count -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.residues"))
    }
    if ($ready) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.ready"))
    }
    if ($readinessReviewCount -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.readinessReview"))
    }
    if (@($History).Count -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.history"))
    }
    return [pscustomobject]@{
        ReadyForOfficialActivation = $ready
        ActiveActivatorFindingCount = [int]$scopedFindings.Count
        UnapprovedWindowsKmsCount = [int]$unapprovedWindows.Count
        UnapprovedOfficeKmsCount = [int]$unapprovedOffice.Count
        ConfigurationResidueCount = [int]$residues.Count
        HistoryFindingCount = [int]@($History).Count
        ReadinessReviewCount = [int]$readinessReviewCount
        ScanWarningCount = [int]$scanWarnings.Count
        ScanWarnings = $scanWarnings
        ReadinessChecks = $readiness
        Residues = $residues
        ApprovedKmsServerFile = [string]$approvedKmsConfig.Path
        ApprovedKmsServerCount = [int]$approvedKmsConfig.Valid.Count
        InvalidApprovedKmsCount = [int]$approvedKmsConfig.Invalid.Count
        ApprovedKmsConfigWarning = [string]$approvedKmsConfig.Warning
        Conclusion = $conclusion
        HandlingGuidance = $handlingGuidance.ToArray()
        ScopeNote = Get-CleanupText "cleanupReport.verification.scope"
    }
}

function Get-CleanupNextActions {
    param(
        $Verification,
        $CleanupItems,
        [bool]$ProtectedLicense,
        [string]$BackupDirectory = "",
        [AllowNull()][object]$OfficialLicensePostCheck,
        [ValidateSet('All','Windows','Office','ThirdParty','WindowsOffice','WindowsThirdParty','OfficeThirdParty')]
        [string]$Scope = 'All'
    )

    $next = New-Object System.Collections.Generic.List[object]
    $remaining = @($CleanupItems)
    $vendorActionsForNext = @()
    if ($null -ne $OfficialLicensePostCheck -and $OfficialLicensePostCheck.PSObject.Properties['OfficialActions']) {
        $vendorActionsForNext = @($OfficialLicensePostCheck.OfficialActions | Where-Object {
            [string]$_.Code -in @('OpenVendorActivation','OpenVendorRepair') -and
            [string]$_.Target -match '^https://[^\s]+$'
        } | Group-Object { ([string]$_.Target).ToLowerInvariant() } | ForEach-Object { $_.Group[0] } | Select-Object -First 25)
    }
    if ([int]$Verification.ScanWarningCount -gt 0) {
        $next.Add([pscustomobject]@{ Code="RepairScanSources"; Label=(Get-CleanupText "cleanupReport.next.repairScan"); Detail=(Get-CleanupText "cleanupReport.next.repairScanDetail"); CandidateCount=0 })
        $next.Add([pscustomobject]@{ Code="Recheck"; Label=(Get-CleanupText "cleanupReport.next.recheck"); Detail=(Get-CleanupText "cleanupReport.next.recheckBeforeChange"); CandidateCount=0 })
    } elseif ([bool]$Verification.ReadyForOfficialActivation) {
        $officialActions = @()
        if ($null -ne $OfficialLicensePostCheck -and $OfficialLicensePostCheck.PSObject.Properties['OfficialActions']) {
            $officialActions = @($OfficialLicensePostCheck.OfficialActions)
        }
        $needsWindowsOrOffice = [bool](@($officialActions | Where-Object { [string]$_.Code -in @('OpenWindowsActivation','OpenOfficeActivation') }).Count -gt 0)
        if ($needsWindowsOrOffice -or ($null -eq $OfficialLicensePostCheck -and
            (Test-CleanupScanScopeIncludes -Scope $Scope -Component 'Windows') -and -not $ProtectedLicense)) {
            $components = @($officialActions | Where-Object { [string]$_.Code -in @('OpenWindowsActivation','OpenOfficeActivation') } |
                ForEach-Object { [string]$_.Component } | Select-Object -Unique)
            $next.Add([pscustomobject]@{
                Code="OpenLicenseManager"; Label=(Get-CleanupText "cleanupReport.next.officialActivation")
                Detail=(Get-CleanupText "cleanupReport.next.officialActivationDetail"); CandidateCount=0
                Components=$components; Target='LocalLicenseManager'
            })
        }
        $vendorActions = @($officialActions | Where-Object {
            [string]$_.Code -in @('OpenVendorActivation','OpenVendorRepair') -and
            [string]$_.Target -match '^https://[^\s]+$'
        } | Group-Object { ([string]$_.Target).ToLowerInvariant() } | ForEach-Object { $_.Group[0] } | Select-Object -First 25)
        if ($vendorActions.Count -gt 0) {
            $next.Add([pscustomobject]@{
                Code='ReviewVendorActivation'; Label=(Get-CleanupText "cleanupReport.next.officialActivation")
                Detail=(Get-CleanupText "cleanupReport.next.officialActivationDetail"); CandidateCount=0
                Components=@('ThirdParty'); Name='ThirdParty'; Target=''; Targets=@($vendorActions)
            })
        }
        $next.Add([pscustomobject]@{ Code="Recheck"; Label=(Get-CleanupText "cleanupReport.next.postCheck"); Detail=(Get-CleanupText "cleanupReport.next.postCheckDetail"); CandidateCount=0 })
    } else {
        if ($remaining.Count -gt 0) {
            $next.Add([pscustomobject]@{ Code="RemediateRemaining"; Label=(Get-CleanupText "cleanupReport.next.remaining"); Detail=(Get-CleanupText "cleanupReport.next.remainingDetail"); CandidateCount=[int]$remaining.Count })
        }
        if ([int]$Verification.UnapprovedWindowsKmsCount -gt 0 -or [int]$Verification.UnapprovedOfficeKmsCount -gt 0) {
            $next.Add([pscustomobject]@{ Code="ConfigureApprovedKms"; Label=(Get-CleanupText "cleanupReport.next.approveKms"); Detail=(Get-CleanupText "cleanupReport.next.approveKmsDetail"); CandidateCount=[int]($Verification.UnapprovedWindowsKmsCount + $Verification.UnapprovedOfficeKmsCount) })
        }
        $next.Add([pscustomobject]@{ Code="Recheck"; Label=(Get-CleanupText "cleanupReport.next.recheck"); Detail=(Get-CleanupText "cleanupReport.next.recheckReadOnly"); CandidateCount=0 })
    }
    if ($vendorActionsForNext.Count -gt 0 -and @($next.ToArray() | Where-Object { [string]$_.Code -eq 'ReviewVendorActivation' }).Count -eq 0) {
        $next.Add([pscustomobject]@{
            Code='ReviewVendorActivation'; Label=(Get-CleanupText "cleanupReport.next.officialActivation")
            Detail=(Get-CleanupText "cleanupReport.next.officialActivationDetail"); CandidateCount=0
            Components=@('ThirdParty'); Name='ThirdParty'; Target=''; Targets=@($vendorActionsForNext)
        })
    }
    if (-not [string]::IsNullOrWhiteSpace($BackupDirectory)) {
        $next.Add([pscustomobject]@{ Code="RestoreBackup"; Label=(Get-CleanupText "cleanupReport.next.restore"); Detail=(Get-CleanupText "cleanupReport.next.restoreDetail"); CandidateCount=0 })
    }
    $next.Add([pscustomobject]@{ Code="OpenReport"; Label=(Get-CleanupText "cleanupReport.next.openReport"); Detail=(Get-CleanupText "cleanupReport.next.openReportDetail"); CandidateCount=0 })
    return @($next.ToArray())
}

function Test-CleanupCandidateMatchesSelectedSnapshot {
    param(
        [AllowNull()][object]$Candidate,
        [AllowNull()][object[]]$SelectedCandidateSnapshots = @()
    )

    if ($null -eq $Candidate) { return $false }
    $snapshots = @($SelectedCandidateSnapshots | Where-Object { $null -ne $_ })
    if ($snapshots.Count -eq 0) { return $true }
    $candidateComponent = Get-CleanupRecordComponentScope -Record $Candidate
    foreach ($snapshot in $snapshots) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Candidate.Id) -and
            [string]::Equals([string]$Candidate.Id, [string]$snapshot.Id, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        $snapshotComponent = Get-CleanupRecordComponentScope -Record $snapshot
        if ($candidateComponent -ne $snapshotComponent) { continue }
        if ($candidateComponent -eq 'ThirdParty') {
            # Keep the action family exact.  A guidance choice must not turn
            # into Complete uninstall (or vice versa) merely because both rows
            # point at the same installed application.
            if (-not [string]::Equals([string]$Candidate.Kind, [string]$snapshot.Kind, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $snapshotApplicationIds = @($snapshot.ApplicationIds | ForEach-Object { [string]$_ } | Where-Object { $_ })
            if ($snapshotApplicationIds.Count -gt 0 -and
                @($Candidate.ApplicationIds | Where-Object { $snapshotApplicationIds -contains [string]$_ }).Count -gt 0) {
                return $true
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$snapshot.TargetId) -and
                [string]::Equals([string]$Candidate.TargetId, [string]$snapshot.TargetId, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$snapshot.VendorScope) -and
                -not [string]::IsNullOrWhiteSpace([string]$snapshot.Location) -and
                [string]::Equals([string]$Candidate.VendorScope, [string]$snapshot.VendorScope, [StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$Candidate.Location, [string]$snapshot.Location, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$snapshot.TargetId) -and
            [string]::Equals([string]$Candidate.TargetId, [string]$snapshot.TargetId, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        if ([string]$snapshot.Kind -eq 'OfficeKmsHostOverride' -and [string]$Candidate.Kind -eq 'OfficeKmsHostOverride' -and
            -not [string]::IsNullOrWhiteSpace([string]$snapshot.Location) -and
            [string]::Equals([string]$Candidate.Location, [string]$snapshot.Location, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-CleanupPostVerificationItems {
    param(
        $CleanupItems = @(),
        [string[]]$SelectedIds = @(),
        [AllowNull()][object[]]$SelectedCandidateSnapshots = @(),
        $ThirdPartyExecutionResults = @(),
        $Verification = $null
    )

    $selectedLookup = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($selectedId in @($SelectedIds)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$selectedId)) { [void]$selectedLookup.Add([string]$selectedId) }
    }
    $items = New-Object System.Collections.Generic.List[object]
    $seenCandidateIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in @($CleanupItems)) {
        # After a remediation, report only the lineage of the exact candidates
        # approved by the user.  A fresh full-machine scan is still retained in
        # the report, but unrelated candidates must not become suggested work
        # or look as if they had been selected automatically.
        if (-not (Test-CleanupCandidateMatchesSelectedSnapshot -Candidate $candidate `
            -SelectedCandidateSnapshots $SelectedCandidateSnapshots)) { continue }
        $candidateId = [string]$candidate.Id
        if (-not [string]::IsNullOrWhiteSpace($candidateId)) { [void]$seenCandidateIds.Add($candidateId) }
        $wasSelected = [bool]$selectedLookup.Contains($candidateId)
        $guidanceOnly = [bool](
            ([string]$candidate.Type -eq 'Guidance') -or
            ($candidate.PSObject.Properties['GuidanceOnly'] -and [bool]$candidate.GuidanceOnly)
        )
        $hasLocalAction = if ([string]$candidate.Type -eq 'Application') {
            [bool](@(Get-ThirdPartyCandidateSafePlan -Candidate $candidate | Where-Object { [string]$_.Type -ne 'Guidance' }).Count -gt 0)
        } else {
            [bool](-not $guidanceOnly)
        }
        $execution = @($ThirdPartyExecutionResults | Where-Object {
            [string]::Equals([string]$_.ParentCandidateId, $candidateId, [StringComparison]::OrdinalIgnoreCase)
        })
        $failedExecution = @($execution | Where-Object { [string]$_.Status -in @('Failed','PolicyBlocked') } | Select-Object -First 1)
        $executionFailed = [bool]($failedExecution.Count -gt 0)
        $disposition = if ($executionFailed) { 'ActionFailed' }
            elseif ($guidanceOnly -and $wasSelected) { 'OfficialActionRequired' }
            elseif ($guidanceOnly) { 'OfficialGuidanceAvailable' }
            elseif ($wasSelected) { 'ResidualAfterSelectedAction' }
            elseif ($hasLocalAction) { 'RemainingActionable' }
            else { 'CannotAutoHandle' }
        $reason = if ($executionFailed -and $failedExecution[0].Message) { [string]$failedExecution[0].Message }
            elseif ($candidate.PSObject.Properties['GuidanceReason'] -and -not [string]::IsNullOrWhiteSpace([string]$candidate.GuidanceReason)) { [string]$candidate.GuidanceReason }
            else { [string]$candidate.Detail }
        $items.Add([pscustomobject][ordered]@{
            CandidateId=$candidateId; Type=[string]$candidate.Type; Kind=[string]$candidate.Kind
            ComponentScope=(Get-CleanupRecordComponentScope -Record $candidate)
            Name=[string]$candidate.Name; Location=[string]$candidate.Location; Detail=[string]$candidate.Detail
            Disposition=$disposition; Reason=$reason; WasSelected=$wasSelected
            GuidanceOnly=$guidanceOnly; LocalActionAvailable=$hasLocalAction
            SelectableForNextStep=[bool]($hasLocalAction -or $guidanceOnly)
            SuggestedForNextStep=[bool]($hasLocalAction -and -not $executionFailed)
            ExecutionStatus=$(if ($failedExecution.Count -gt 0) { [string]$failedExecution[0].Status } elseif ($execution.Count -gt 0) { [string]$execution[-1].Status } else { '' })
        })
    }

    # A failed third-party child can disappear before the fresh scan.  Keep it
    # visible rather than silently treating a missing post-scan row as success.
    foreach ($execution in @($ThirdPartyExecutionResults | Where-Object { [string]$_.Status -in @('Failed','PolicyBlocked') })) {
        $parentId = [string]$execution.ParentCandidateId
        if ($parentId -and $seenCandidateIds.Contains($parentId)) { continue }
        $executionStatus = [string]$execution.Status
        $items.Add([pscustomobject][ordered]@{
            CandidateId=$parentId; Type=[string]$execution.Type; Kind=[string]$execution.Kind
            ComponentScope='ThirdParty'; Name=[string]$execution.Name; Location=[string]$execution.Target
            Detail=[string]$execution.Message; Disposition='ActionFailed'; Reason=[string]$execution.Message
            WasSelected=$true; GuidanceOnly=$false; LocalActionAvailable=$false; SelectableForNextStep=$false
            SuggestedForNextStep=$false; ExecutionStatus=$executionStatus
        })
    }
    if ($null -ne $Verification -and [int]$Verification.ScanWarningCount -gt 0) {
        $items.Add([pscustomobject][ordered]@{
            CandidateId=''; Type='Scan'; Kind='IncompleteScan'; ComponentScope='Shared'; Name=(Get-CleanupText 'cleanupReport.postVerification.scanIncompleteName')
            Location=''; Detail=(@($Verification.ScanWarnings) -join '; '); Disposition='ScanIncomplete'
            Reason=(Get-CleanupText 'cleanupReport.postVerification.scanIncompleteReason'); WasSelected=$false
            GuidanceOnly=$true; LocalActionAvailable=$false; SelectableForNextStep=$false; SuggestedForNextStep=$false; ExecutionStatus=''
        })
    }
    return @($items.ToArray())
}

function Get-CleanupPostVerificationOutcome {
    param(
        $PostVerificationItems = @(),
        [bool]$ScopeReady = $false,
        [bool]$OfficiallyLicensed = $false
    )

    if ($ScopeReady -and $OfficiallyLicensed) { return 'VerifiedValid' }
    if ($ScopeReady) { return 'FullyHandled' }
    if (@($PostVerificationItems | Where-Object { [bool]$_.LocalActionAvailable }).Count -gt 0) { return 'RemainingActionable' }
    return 'CannotAutoHandle'
}

function Get-ComplianceDecision {
    param($Products, $Findings)
    $oa3 = Get-Oa3KeyPresent
    $licensed = $Products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
    $current = if ($licensed) { $licensed } else { $Products | Sort-Object LicenseStatus -Descending | Select-Object -First 1 }
    if (-not $current) {
        return [pscustomobject]@{
            DecisionCode = "NoLicense"
            Decision = Get-CleanupText "cleanupReport.decision.noLicense"
            Reason = Get-CleanupText "cleanupReport.decision.noProductKey"
            ShouldRemediate = $false
        }
    }

    $channel = Get-LicenseChannel $current
    $kmsServer = [string]$current.KeyManagementServiceMachine
    $hasActivator = ($Findings.Count -gt 0)

    if ($hasActivator) {
        return [pscustomobject]@{
                DecisionCode = "Suspicious"
                Decision = Get-CleanupText "cleanupReport.decision.suspicious"
                Reason = Get-CleanupText "cleanupReport.decision.activatorDetected"
            ShouldRemediate = $true
        }
    }
    if ($channel -eq "KMS") {
        if (Test-ApprovedKms $kmsServer) {
            return [pscustomobject]@{
                DecisionCode = "KeepActivation"
                Decision = Get-CleanupText "cleanupReport.decision.keepActivation"
                Reason = Get-CleanupText "cleanupReport.decision.approvedKms" @($kmsServer)
                ShouldRemediate = $false
            }
        }
        if ($TreatUnapprovedKmsAsNonCompliant) {
            return [pscustomobject]@{
                DecisionCode = "Suspicious"
                Decision = Get-CleanupText "cleanupReport.decision.suspicious"
                Reason = Get-CleanupText "cleanupReport.decision.unapprovedKms"
                ShouldRemediate = $true
            }
        }
        return [pscustomobject]@{
            DecisionCode = "ManualReview"
            Decision = Get-CleanupText "cleanupReport.decision.manualReview"
            Reason = Get-CleanupText "cleanupReport.decision.kmsManualReview"
            ShouldRemediate = $false
        }
    }
    if ($licensed -and $channel -in @("OEM", "Retail", "MAK")) {
        return [pscustomobject]@{
            DecisionCode = "KeepActivation"
            Decision = Get-CleanupText "cleanupReport.decision.keepActivation"
            Reason = Get-CleanupText "cleanupReport.decision.validChannel" @($channel)
            ShouldRemediate = $false
        }
    }
    if ([int]$current.LicenseStatus -ne 1) {
        return [pscustomobject]@{
            DecisionCode = "LicenseReview"
            Decision = Get-CleanupText "cleanupReport.decision.licenseReview"
            Reason = Get-CleanupText "cleanupReport.decision.statusReview" @($channel, (Status-Text $current.LicenseStatus))
            ShouldRemediate = $false
        }
    }
    if ($oa3) {
        return [pscustomobject]@{
            DecisionCode = "KeepActivation"
            Decision = Get-CleanupText "cleanupReport.decision.keepActivation"
            Reason = Get-CleanupText "cleanupReport.decision.oa3Present"
            ShouldRemediate = $false
        }
    }
    return [pscustomobject]@{
        DecisionCode = "ManualReview"
        Decision = Get-CleanupText "cleanupReport.decision.manualReview"
        Reason = Get-CleanupText "cleanupReport.decision.channelUnknown"
        ShouldRemediate = $false
    }
}

function Get-ProtectedLicenseInfo {
    param($Products)
    $licensed = $Products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
    if ($licensed) {
        $channel = Get-LicenseChannel $licensed
        if ($channel -in @("OEM", "Retail", "MAK")) {
            return [pscustomobject]@{
                Protected = $true
                Channel = $channel
                Reason = Get-CleanupText "cleanupReport.protected.channel" @($channel)
            }
        }
        if ($channel -eq "KMS" -and (Test-ApprovedKms ([string]$licensed.KeyManagementServiceMachine))) {
            return [pscustomobject]@{
                Protected = $true
                Channel = Get-CleanupText "cleanupReport.protected.approvedKmsChannel"
                Reason = Get-CleanupText "cleanupReport.protected.approvedKms"
            }
        }
    }
    if (Get-Oa3KeyPresent) {
        return [pscustomobject]@{
            Protected = $true
            Channel = "OEM OA3"
            Reason = Get-CleanupText "cleanupReport.protected.oa3"
        }
    }
    return [pscustomobject]@{
        Protected = $false
        Channel = if ($licensed) { Get-LicenseChannel $licensed } else { Get-CleanupText "common.unknown" }
        Reason = Get-CleanupText "cleanupReport.protected.none"
    }
}

function Get-WindowsOfficialLicenseOutcome {
    param(
        $Products = @(),
        $Verification,
        [bool]$Included = $true
    )

    if (-not $Included) {
        return [pscustomobject][ordered]@{
            Component='Windows'; Applicable=$false; StateCode='NotScanned'
            OfficiallyLicensed=$false; VendorConfirmed=$false; CrackFree=$false
            RequiresOfficialActivation=$false; NeedsRepair=$false; Channel=''; Source='NotScanned'
            OfficialActionCode=''; OfficialActionTarget=''
        }
    }

    $crackFree = [bool](Test-CleanupScopeReady -Verification $Verification -Scope 'Windows')
    $licensedProduct = @($Products | Where-Object {
        if ([int]$_.LicenseStatus -ne 1) { return $false }
        $channel = Get-LicenseChannel $_
        return [bool]($channel -in @('OEM','Retail','MAK') -or
            ($channel -eq 'KMS' -and (Test-ApprovedKms -Server ([string]$_.KeyManagementServiceMachine))))
    } | Select-Object -First 1)
    $readinessNeedsReview = [bool](@($Verification.ReadinessChecks | Where-Object {
        [string]$_.StatusCode -in @('Review','Unverified')
    }).Count -gt 0)
    $stateCode = if (-not $crackFree) { 'CrackEvidencePresent' }
        elseif ($licensedProduct.Count -gt 0) { 'Licensed' }
        elseif ($readinessNeedsReview) { 'NeedsRepair' }
        else { 'Unactivated' }
    $channel = if ($licensedProduct.Count -gt 0) { Get-LicenseChannel $licensedProduct[0] }
        else {
            $firstProduct = @($Products | Sort-Object LicenseStatus -Descending | Select-Object -First 1)
            if ($firstProduct.Count -gt 0) { Get-LicenseChannel $firstProduct[0] } else { '' }
        }
    $confirmed = [bool]($crackFree -and $stateCode -eq 'Licensed')
    return [pscustomobject][ordered]@{
        Component='Windows'; Applicable=$true; StateCode=$stateCode
        OfficiallyLicensed=$confirmed; VendorConfirmed=$confirmed; CrackFree=$crackFree
        RequiresOfficialActivation=[bool]($crackFree -and $stateCode -eq 'Unactivated')
        NeedsRepair=[bool]($stateCode -eq 'NeedsRepair'); Channel=[string]$channel
        Source='SoftwareLicensingProduct'; FirmwareEntitlementMarkerPresent=[bool](Get-Oa3KeyPresent)
        OfficialActionCode=$(if ($crackFree -and $stateCode -in @('Unactivated','NeedsRepair')) { 'OpenWindowsActivation' } else { '' })
        OfficialActionTarget=$(if ($crackFree -and $stateCode -in @('Unactivated','NeedsRepair')) { 'ms-settings:activation' } else { '' })
    }
}

function Test-OfficeProductInstalled {
    param($LicenseEntries = @())
    if (@($LicenseEntries).Count -gt 0) { return $true }
    foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
    )) {
        if (Test-Path -LiteralPath $path) { return $true }
    }
    return [bool](@(Get-ToolOptimizedOfficeOsppPaths).Count -gt 0)
}

function Get-OfficeOfficialLicenseOutcome {
    param(
        $LicenseEntries = @(),
        $Verification,
        [bool]$Included = $true,
        [bool]$Installed = $true,
        [AllowNull()][object]$OfficeProbe = $null
    )

    if (-not $Included) {
        return [pscustomobject][ordered]@{
            Component='Office'; Applicable=$false; StateCode='NotScanned'
            OfficiallyLicensed=$false; VendorConfirmed=$false; CrackFree=$false
            RequiresOfficialActivation=$false; NeedsRepair=$false; Channel=''; Source='NotScanned'
            OfficialActionCode=''; OfficialActionTarget=''
        }
    }
    if (-not $Installed) {
        return [pscustomobject][ordered]@{
            Component='Office'; Applicable=$false; StateCode='NotDetected'
            OfficiallyLicensed=$false; VendorConfirmed=$false; CrackFree=$true
            RequiresOfficialActivation=$false; NeedsRepair=$false; Channel=''; Source='OSPP'
            OfficialActionCode=''; OfficialActionTarget=''
        }
    }
    if ($null -ne $OfficeProbe -and [string]$OfficeProbe.Coverage -ne 'Complete') {
        return [pscustomobject][ordered]@{
            Component='Office'; Applicable=$true; StateCode='Unverified'
            OfficiallyLicensed=$false; VendorConfirmed=$false; CrackFree=$false
            RequiresOfficialActivation=$false; NeedsRepair=$true; Channel=''
            Source=('OSPP:' + [string]$OfficeProbe.Coverage); OfficialActionCode=''; OfficialActionTarget=''
        }
    }

    $subscriptionDeployment = [bool](@($LicenseEntries | Where-Object {
        $entryDescription = if ($_.PSObject.Properties['Description']) { [string]$_.Description } else { '' }
        [string]$_.Channel -eq 'Subscription' -or
        ((([string]$_.LicenseName) + ' ' + $entryDescription) -match '(?i)\b(?:O365|M365|Office\s*365|Microsoft\s*365|ProPlus|TIMEBASED_SUB)')
    }).Count -gt 0)
    if ($null -ne $OfficeProbe -and $OfficeProbe.PSObject.Properties['RequiresVNextEntitlement']) {
        $subscriptionDeployment = [bool]$OfficeProbe.RequiresVNextEntitlement
    }
    $vNextProbe = if ($null -ne $OfficeProbe -and $OfficeProbe.PSObject.Properties['VNextEntitlementProbe']) {
        $OfficeProbe.VNextEntitlementProbe
    } else { $null }
    $vNextCoverage = if ($null -ne $vNextProbe -and $vNextProbe.PSObject.Properties['Coverage']) { [string]$vNextProbe.Coverage } else { 'Unavailable' }
    if ($subscriptionDeployment -and $vNextCoverage -ne 'Complete') {
        return [pscustomobject][ordered]@{
            Component='Office'; Applicable=$true; StateCode='Unverified'
            OfficiallyLicensed=$false; VendorConfirmed=$false; CrackFree=$false
            RequiresOfficialActivation=$false; NeedsRepair=$true; Channel='Subscription'
            Source=('OSPP+vNextDiag:' + $vNextCoverage); OfficialActionCode=''; OfficialActionTarget=''
        }
    }

    $crackFree = [bool](Test-CleanupScopeReady -Verification $Verification -Scope 'Office')
    $officialLicensedEntry = @($LicenseEntries | Where-Object {
        if ([string]$_.LicenseStatusCode -ne 'Licensed') { return $false }
        if ([string]$_.Channel -eq 'Subscription') { return $false }
        if ([string]$_.Channel -ne 'KMS') { return $true }
        return [bool](Test-ApprovedKms -Server ([string]$_.Server))
    } | Select-Object -First 1)
    $vNextLicensedCount = if ($null -ne $vNextProbe -and $vNextProbe.PSObject.Properties['LicensedCount']) { [int]$vNextProbe.LicensedCount } else { 0 }
    $vNextGraceCount = if ($null -ne $vNextProbe -and $vNextProbe.PSObject.Properties['GraceCount']) { [int]$vNextProbe.GraceCount } else { 0 }
    $vNextRestrictedFunctionalityCount = if ($null -ne $vNextProbe -and $vNextProbe.PSObject.Properties['RestrictedFunctionalityCount']) { [int]$vNextProbe.RestrictedFunctionalityCount } else { 0 }
    $stateCode = if (-not $crackFree) { 'CrackEvidencePresent' }
        elseif ($subscriptionDeployment -and $vNextLicensedCount -gt 0) { 'Licensed' }
        elseif ($officialLicensedEntry.Count -gt 0) { 'Licensed' }
        elseif ($subscriptionDeployment -and ($vNextGraceCount -gt 0 -or $vNextRestrictedFunctionalityCount -gt 0)) { 'NeedsRepair' }
        elseif (@($LicenseEntries).Count -gt 0) { 'Unactivated' }
        else { 'Unverified' }
    $confirmed = [bool]($crackFree -and $stateCode -eq 'Licensed')
    return [pscustomobject][ordered]@{
        Component='Office'; Applicable=$true; StateCode=$stateCode
        OfficiallyLicensed=$confirmed; VendorConfirmed=$confirmed; CrackFree=$crackFree
        RequiresOfficialActivation=[bool]($crackFree -and $stateCode -in @('Unactivated','Unverified','NeedsRepair'))
        NeedsRepair=[bool]($crackFree -and $stateCode -in @('Unverified','NeedsRepair'))
        Channel=$(if ($subscriptionDeployment) { 'Subscription' } elseif ($officialLicensedEntry.Count -gt 0) { [string]$officialLicensedEntry[0].Channel } else { '' })
        Source=$(if ($subscriptionDeployment) { 'OSPP+vNextDiag' } else { 'OSPP' })
        OfficialActionCode=$(if ($crackFree -and $stateCode -in @('Unactivated','Unverified','NeedsRepair')) { 'OpenOfficeActivation' } else { '' })
        OfficialActionTarget=$(if ($crackFree -and $stateCode -in @('Unactivated','Unverified','NeedsRepair')) { 'LocalLicenseManager:Office' } else { '' })
    }
}

function Get-ThirdPartyOfficialLicenseOutcomes {
    param($Applications = @(), [bool]$Included = $true)
    if (-not $Included) { return @() }
    $outcomes = New-Object System.Collections.Generic.List[object]
    foreach ($application in @($Applications)) {
        $licenseModel = [string]$application.LicenseModel
        $assessment = [string]$application.AssessmentCode
        $technicalState = [string]$application.LicenseTechnicalState
        $cleanupFinding = [bool]($application.PSObject.Properties['CleanupFinding'] -and [bool]$application.CleanupFinding)
        $stateCode = if ($cleanupFinding -or $assessment -in @('NonGenuine','Suspicious')) { 'CrackEvidencePresent' }
            elseif ($assessment -eq 'IntegrityCompromised') { 'NeedsRepair' }
            elseif ($assessment -eq 'GenuineVerified' -and $technicalState -eq 'LocalLicenseVerified') { 'Licensed' }
            elseif ($assessment -eq 'Unactivated' -or $technicalState -eq 'Unactivated') { 'Unactivated' }
            elseif ($licenseModel -in @('Free','OpenSource')) { 'NotApplicable' }
            else { 'Unverified' }
        $applicable = [bool]($stateCode -ne 'NotApplicable')
        $confirmed = [bool]($stateCode -eq 'Licensed' -and -not $cleanupFinding)
        $officialUrl = if ($application.PSObject.Properties['OfficialReferenceUrl']) { [string]$application.OfficialReferenceUrl } else { '' }
        $hasOfficialHttpsTarget = [bool]($officialUrl -match '^https://[^\s]+$')
        $actionCode = if ($hasOfficialHttpsTarget -and $stateCode -in @('CrackEvidencePresent','NeedsRepair')) { 'OpenVendorRepair' }
            elseif ($hasOfficialHttpsTarget -and $stateCode -in @('Unactivated','Unverified')) { 'OpenVendorActivation' }
            else { '' }
        $outcomes.Add([pscustomobject][ordered]@{
            Component='ThirdParty'; ApplicationId=[string]$application.Id; Name=[string]$application.Name
            Vendor=$(if ($application.PSObject.Properties['VendorScope']) { [string]$application.VendorScope } else { [string]$application.Publisher })
            LicenseModel=$licenseModel; Applicable=$applicable; StateCode=$stateCode
            OfficiallyLicensed=$confirmed; VendorConfirmed=$confirmed; CrackFree=[bool]($stateCode -ne 'CrackEvidencePresent')
            RequiresOfficialActivation=[bool]($stateCode -in @('Unactivated','Unverified'))
            NeedsRepair=[bool]($stateCode -eq 'NeedsRepair'); Source='DerivedLocalAssessment'
            OfficialActionCode=$actionCode; OfficialActionTarget=$officialUrl
        })
    }
    return $outcomes.ToArray()
}

function Get-OfficialLicensePostCheck {
    param(
        $Verification,
        $Products = @(),
        $OfficeLicenseEntries = @(),
        [AllowNull()][object]$OfficeProbe = $null,
        $ThirdPartyApplications = @(),
        [ValidateSet('All','Windows','Office','ThirdParty','WindowsOffice','WindowsThirdParty','OfficeThirdParty')]
        [string]$Scope = 'All'
    )

    $includeWindows = Test-CleanupScanScopeIncludes -Scope $Scope -Component 'Windows'
    $includeOffice = Test-CleanupScanScopeIncludes -Scope $Scope -Component 'Office'
    $includeThirdParty = Test-CleanupScanScopeIncludes -Scope $Scope -Component 'ThirdParty'
    $windows = Get-WindowsOfficialLicenseOutcome -Products $Products -Verification $Verification -Included:$includeWindows
    $officeInstalled = if ($includeOffice) { Test-OfficeProductInstalled -LicenseEntries $OfficeLicenseEntries } else { $false }
    $office = Get-OfficeOfficialLicenseOutcome -LicenseEntries $OfficeLicenseEntries -Verification $Verification -Included:$includeOffice -Installed:$officeInstalled -OfficeProbe $OfficeProbe
    $thirdParty = @(Get-ThirdPartyOfficialLicenseOutcomes -Applications $ThirdPartyApplications -Included:$includeThirdParty)
    $outcomes = @($windows, $office) + @($thirdParty)
    $applicable = @($outcomes | Where-Object { [bool]$_.Applicable })
    $crackFree = [bool](Test-CleanupScopeReady -Verification $Verification -Scope $Scope)
    $allConfirmed = [bool]($crackFree -and $applicable.Count -gt 0 -and
        @($applicable | Where-Object { -not [bool]$_.OfficiallyLicensed }).Count -eq 0)
    $stateCode = if (-not $crackFree) { 'CrackEvidencePresent' }
        elseif ($allConfirmed) { 'Licensed' }
        elseif (@($applicable | Where-Object { [bool]$_.NeedsRepair }).Count -gt 0) { 'NeedsRepair' }
        else { 'ActivationRequired' }
    $actions = @($outcomes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.OfficialActionCode) } | ForEach-Object {
        [pscustomobject][ordered]@{
            Code=[string]$_.OfficialActionCode; Component=[string]$_.Component
            Name=$(if ($_.PSObject.Properties['Name']) { [string]$_.Name } else { [string]$_.Component })
            Target=[string]$_.OfficialActionTarget
        }
    })
    return [pscustomobject][ordered]@{
        StateCode=$stateCode; OfficiallyLicensed=$allConfirmed; VendorConfirmed=$allConfirmed
        CrackFree=$crackFree; ApplicableOutcomeCount=[int]$applicable.Count
        ConfirmedOutcomeCount=[int]@($applicable | Where-Object { [bool]$_.OfficiallyLicensed }).Count
        Windows=$windows; Office=$office; ThirdParty=@($thirdParty); OfficialActions=$actions
    }
}
