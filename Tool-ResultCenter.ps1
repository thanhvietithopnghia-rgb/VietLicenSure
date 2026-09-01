$script:ToolResultCenterSchemaVersion = '1.0'
$script:ToolResultCenterToolVersion = '5.0'

function Get-ToolResultCenterMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = [string]$script:ToolResultCenterSchemaVersion
        ToolVersion = [string]$script:ToolResultCenterToolVersion
        ComparisonStates = @('New', 'Resolved', 'Unchanged', 'NoBaseline')
        SeverityOrder = @('High', 'Medium', 'Low')
        PrivacyModel = 'RedactedReportAndSanitizedLogOnly'
    }
}

function Get-ToolResultObjectValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string[]]$Names,
        [AllowNull()][object]$DefaultValue = $null
    )
    if ($null -eq $InputObject) { return $DefaultValue }
    foreach ($name in $Names) {
        if ($InputObject -is [Collections.IDictionary]) {
            foreach ($key in @($InputObject.Keys)) {
                if ([string]::Equals([string]$key, $name, [StringComparison]::OrdinalIgnoreCase)) {
                    return $InputObject[$key]
                }
            }
        } elseif ($InputObject.PSObject) {
            $property = $InputObject.PSObject.Properties[$name]
            if ($null -ne $property) { return $property.Value }
        }
    }
    return $DefaultValue
}

function ConvertTo-ToolResultCenterText {
    param([AllowNull()][object]$Value, [int]$MaximumLength = 1024)
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Replace("`r", ' ').Replace("`n", ' ').Trim()
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}

function Get-ToolResultStringSha256 {
    param([AllowNull()][string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Get-ToolResultFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant() }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Test-ToolResultPathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$AllowRoot
    )
    try {
        $rootItem = Get-Item -LiteralPath ([IO.Path]::GetFullPath($Root)) -Force -ErrorAction Stop
        if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
        $rootFull = [IO.Path]::GetFullPath($rootItem.FullName).TrimEnd('\')
        $pathFull = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        if ($AllowRoot -and [string]::Equals($pathFull, $rootFull, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if (-not $pathFull.StartsWith(($rootFull + '\'), [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $cursor = $rootFull
        foreach ($segment in $pathFull.Substring($rootFull.Length).TrimStart('\').Split('\')) {
            if ([string]::IsNullOrWhiteSpace($segment)) { continue }
            $cursor = Join-Path $cursor $segment
            if (-not (Test-Path -LiteralPath $cursor)) { break }
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        }
        return $true
    } catch { return $false }
}

function Read-ToolResultJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateRange(1, 64)][int]$MaximumMegabytes = 24
    )
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'UnsafeJsonPath' }
    if ([int64]$item.Length -gt ([int64]$MaximumMegabytes * 1MB)) { throw 'JsonFileTooLarge' }
    return (Get-Content -LiteralPath $item.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
}

function Test-ToolResultInventoryReportCandidate {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $length = [Math]::Min(65536, [int64]$stream.Length)
            $buffer = New-Object byte[] ([int]$length)
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { return $false }
            $prefix = [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
            return [bool]($prefix -match '"ReportKind"\s*:\s*"InventoryAndLicense"')
        } finally { $stream.Dispose() }
    } catch { return $false }
}

function Get-ToolResultReportCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReportRoot,
        [ValidateRange(1, 720)][int]$MaximumCandidates = 240
    )
    if (-not (Test-Path -LiteralPath $ReportRoot -PathType Container)) { return @() }
    $rootItem = Get-Item -LiteralPath $ReportRoot -Force -ErrorAction Stop
    if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { return @() }
    $rootFull = [IO.Path]::GetFullPath($rootItem.FullName).TrimEnd('\')
    return @(Get-ChildItem -LiteralPath $rootFull -Filter '*.json' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Length -le 24MB -and
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            (Test-ToolResultPathWithinRoot -Path $_.FullName -Root $rootFull) -and
            (Test-ToolResultInventoryReportCandidate -Path $_.FullName)
        } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First $MaximumCandidates)
}

function Get-ToolResultReportHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReportRoot,
        [ValidateRange(2, 240)][int]$MaximumReports = 80
    )
    $candidates = @(Get-ToolResultReportCandidates -ReportRoot $ReportRoot -MaximumCandidates ($MaximumReports * 3))

    $reports = New-Object System.Collections.Generic.List[object]
    foreach ($file in $candidates) {
        if ($reports.Count -ge $MaximumReports) { break }
        try {
            $report = Read-ToolResultJsonFile -Path $file.FullName
            if ([string](Get-ToolResultObjectValue $report @('ReportKind')) -ne 'InventoryAndLicense') { continue }
            $createdAt = $file.LastWriteTime
            $createdText = [string](Get-ToolResultObjectValue $report @('CreatedAt'))
            $parsed = [DateTime]::MinValue
            if (-not [string]::IsNullOrWhiteSpace($createdText) -and [DateTime]::TryParse($createdText, [ref]$parsed)) { $createdAt = $parsed }
            $reports.Add([pscustomobject][ordered]@{
                Path = [string]$file.FullName
                CreatedAt = $createdAt
                Mode = [string](Get-ToolResultObjectValue $report @('Mode') 'Unknown')
                Redacted = [bool](Get-ToolResultObjectValue $report @('Redacted') $false)
                Report = $report
            })
        } catch {}
    }
    return @($reports.ToArray() | Sort-Object CreatedAt -Descending)
}

function New-ToolResultCenterItem {
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][ValidateSet('High','Medium','Low')][string]$Severity,
        [Parameter(Mandatory = $true)][ValidateSet('Hardware','Windows','Office','Software')][string]$Category,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Publisher = '',
        [string]$StatusCode = '',
        [string]$StatusText = '',
        [string]$EvidenceText = '',
        [string]$ActionCode = 'OpenReport',
        [string]$SourceReportPath = ''
    )
    $stableId = Get-ToolResultStringSha256 (($Category + '|' + $Identity).ToLowerInvariant())
    $stateHash = Get-ToolResultStringSha256 ((@($Severity,$Category,$Name,$Publisher,$StatusCode,$StatusText,$EvidenceText) -join '|').ToLowerInvariant())
    return [pscustomobject][ordered]@{
        StableId = $stableId
        Severity = $Severity
        Category = $Category
        Name = (ConvertTo-ToolResultCenterText $Name 240)
        Publisher = (ConvertTo-ToolResultCenterText $Publisher 180)
        StatusCode = (ConvertTo-ToolResultCenterText $StatusCode 100)
        StatusText = (ConvertTo-ToolResultCenterText $StatusText 600)
        EvidenceText = (ConvertTo-ToolResultCenterText $EvidenceText 1000)
        ActionCode = $ActionCode
        SourceReportPath = $SourceReportPath
        StateHash = $stateHash
        ComparisonStatus = 'NoBaseline'
    }
}

function ConvertTo-ToolResultCenterItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [string]$SourceReportPath = ''
    )
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($component in @(
        [pscustomobject]@{ Category='Windows'; Name='Windows'; CodeProperty='WindowsConclusionCode'; TextProperty='WindowsConclusion'; Action='OpenWindows' },
        [pscustomobject]@{ Category='Office'; Name='Microsoft Office'; CodeProperty='OfficeConclusionCode'; TextProperty='OfficeConclusion'; Action='OpenOffice' }
    )) {
        $code = [string](Get-ToolResultObjectValue $Report @($component.CodeProperty))
        if ([string]::IsNullOrWhiteSpace($code) -or $code -in @('NotScanned','NotDetected')) { continue }
        $severity = if ($code -in @('NotLicensed','KmsUnapprovedHost','KmsEntitlementUnverified')) { 'High' } else { 'Medium' }
        $statusText = [string](Get-ToolResultObjectValue $Report @($component.TextProperty) $code)
        $items.Add((New-ToolResultCenterItem -Identity $component.Category -Severity $severity -Category $component.Category `
            -Name $component.Name -StatusCode $code -StatusText $statusText -EvidenceText $statusText `
            -ActionCode $component.Action -SourceReportPath $SourceReportPath))
    }

    $detailed = Get-ToolResultObjectValue $Report @('DetailedInventory')
    $hardware = Get-ToolResultObjectValue $detailed @('Hardware')
    $security = Get-ToolResultObjectValue $hardware @('Security')
    if ($null -ne $security) {
        $secureBoot = Get-ToolResultObjectValue $security @('SecureBoot')
        if ($null -ne $secureBoot) {
            $supported = Get-ToolResultObjectValue $secureBoot @('Supported')
            $enabled = Get-ToolResultObjectValue $secureBoot @('Enabled')
            $errorText = [string](Get-ToolResultObjectValue $secureBoot @('Error'))
            if ($supported -eq $true -and $enabled -eq $false) {
                $items.Add((New-ToolResultCenterItem -Identity 'SecureBoot' -Severity Medium -Category Hardware -Name 'Secure Boot' `
                    -StatusCode 'Disabled' -StatusText 'Secure Boot is supported but disabled.' -EvidenceText $errorText `
                    -ActionCode OpenHardware -SourceReportPath $SourceReportPath))
            } elseif (-not [string]::IsNullOrWhiteSpace($errorText)) {
                $items.Add((New-ToolResultCenterItem -Identity 'SecureBoot' -Severity Low -Category Hardware -Name 'Secure Boot' `
                    -StatusCode 'Unverified' -StatusText 'Secure Boot state could not be verified.' -EvidenceText $errorText `
                    -ActionCode OpenHardware -SourceReportPath $SourceReportPath))
            }
        }
        $tpm = Get-ToolResultObjectValue $security @('TPM')
        if ($null -ne $tpm) {
            $present = Get-ToolResultObjectValue $tpm @('Present')
            $ready = Get-ToolResultObjectValue $tpm @('Ready')
            $errorText = [string](Get-ToolResultObjectValue $tpm @('Error'))
            if ($present -eq $false -or ($present -eq $true -and $ready -eq $false)) {
                $items.Add((New-ToolResultCenterItem -Identity 'TPM' -Severity Medium -Category Hardware -Name 'TPM' `
                    -StatusCode $(if ($present -eq $false) { 'NotPresent' } else { 'NotReady' }) -StatusText 'TPM is unavailable or not ready.' `
                    -EvidenceText $errorText -ActionCode OpenHardware -SourceReportPath $SourceReportPath))
            } elseif ($null -eq $present -and -not [string]::IsNullOrWhiteSpace($errorText)) {
                $items.Add((New-ToolResultCenterItem -Identity 'TPM' -Severity Low -Category Hardware -Name 'TPM' `
                    -StatusCode 'Unverified' -StatusText 'TPM state could not be verified.' -EvidenceText $errorText `
                    -ActionCode OpenHardware -SourceReportPath $SourceReportPath))
            }
        }
    }

    $software = Get-ToolResultObjectValue $detailed @('Software')
    $applications = @(Get-ToolResultObjectValue $software @('ThirdPartyApplications') @())
    foreach ($application in $applications) {
        if ([bool](Get-ToolResultObjectValue $application @('IsSystemComponent') $false)) { continue }
        $code = [string](Get-ToolResultObjectValue $application @('AssessmentCode'))
        $licenseModel = [string](Get-ToolResultObjectValue $application @('LicenseModel'))
        $needsReview = [bool](Get-ToolResultObjectValue $application @('NeedsReview') $false)
        $requiresEntitlement = [bool](Get-ToolResultObjectValue $application @('LicenseRequiresEntitlement') $false)
        if ($code -in @('FreeOrIncluded','GenuineVerified') -or
            ([string]::IsNullOrWhiteSpace($code) -and -not $needsReview -and -not $requiresEntitlement)) { continue }

        $severity = if ($code -in @('NonGenuine','Suspicious','IntegrityCompromised')) {
            'High'
        } elseif ($needsReview -or $requiresEntitlement -or $code -in @('Unverified','TrialOrUnverified','Unactivated')) {
            'Medium'
        } else { 'Low' }
        $name = [string](Get-ToolResultObjectValue $application @('Software','Name','Product','Application') 'Unknown software')
        $publisher = [string](Get-ToolResultObjectValue $application @('Publisher','Vendor','Company'))
        $version = [string](Get-ToolResultObjectValue $application @('Version','DisplayVersion','File version','FileVersion'))
        $identity = (@($name,$publisher) -join '|').ToLowerInvariant()
        $evidenceCodes = New-Object System.Collections.Generic.List[string]
        foreach ($evidence in @(Get-ToolResultObjectValue $application @('TechnicalEvidence') @())) {
            $evidenceCode = [string](Get-ToolResultObjectValue $evidence @('Code','Name','Type'))
            if (-not [string]::IsNullOrWhiteSpace($evidenceCode) -and -not $evidenceCodes.Contains($evidenceCode)) { $evidenceCodes.Add($evidenceCode) }
            if ($evidenceCodes.Count -ge 6) { break }
        }
        $statusText = (@($code,$licenseModel,$version) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' | '
        $remediationEvidenceCount = [int](Get-ToolResultObjectValue $application @('RemediationEvidenceCount') 0)
        $cleanupFinding = [bool](Get-ToolResultObjectValue $application @('CleanupFinding') $false)
        $softwareAction = if ($severity -eq 'High' -and ($cleanupFinding -or $remediationEvidenceCount -gt 0)) { 'OpenSoftwareRemediation' } else { 'ReviewSoftware' }
        $items.Add((New-ToolResultCenterItem -Identity $identity -Severity $severity -Category Software -Name $name -Publisher $publisher `
            -StatusCode $code -StatusText $statusText -EvidenceText ($evidenceCodes.ToArray() -join ', ') `
            -ActionCode $softwareAction -SourceReportPath $SourceReportPath))
    }

    foreach ($finding in @(Get-ToolResultObjectValue $detailed @('ActivatorFindings') @())) {
        $findingName = [string](Get-ToolResultObjectValue $finding @('Indicator','Dau hieu','Name','Artifact','Software') 'Technical intervention indicator')
        $source = [string](Get-ToolResultObjectValue $finding @('Source','Nguon','Type'))
        $location = [string](Get-ToolResultObjectValue $finding @('Location','Vi tri','Path'))
        $identity = (@($source,$findingName,$location) -join '|').ToLowerInvariant()
        $items.Add((New-ToolResultCenterItem -Identity $identity -Severity High -Category Software -Name $findingName `
            -StatusCode 'TechnicalInterventionIndicator' -StatusText 'Technical intervention evidence requires review.' `
            -EvidenceText ((@($source,$location) | Where-Object { $_ }) -join ' | ') -ActionCode ReviewSoftware -SourceReportPath $SourceReportPath))
    }

    $severityRank = @{ High=0; Medium=1; Low=2 }
    return @($items.ToArray() |
        Group-Object StableId |
        ForEach-Object { $_.Group | Sort-Object @{Expression={ $severityRank[[string]$_.Severity] }} | Select-Object -First 1 } |
        Sort-Object @{Expression={ $severityRank[[string]$_.Severity] }}, Category, Name)
}

function Compare-ToolResultCenterItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$CurrentItems,
        [AllowNull()][object[]]$PreviousItems,
        [switch]$HasBaseline
    )
    $result = New-Object System.Collections.Generic.List[object]
    $currentById = @{}
    $previousById = @{}
    foreach ($item in @($CurrentItems)) { $currentById[[string]$item.StableId] = $item }
    foreach ($item in @($PreviousItems)) { $previousById[[string]$item.StableId] = $item }

    foreach ($item in @($CurrentItems)) {
        $copy = $item | Select-Object *
        if (-not $HasBaseline) { $copy.ComparisonStatus = 'NoBaseline' }
        elseif (-not $previousById.ContainsKey([string]$item.StableId)) { $copy.ComparisonStatus = 'New' }
        elseif ([string]$previousById[[string]$item.StableId].StateHash -eq [string]$item.StateHash) { $copy.ComparisonStatus = 'Unchanged' }
        else { $copy.ComparisonStatus = 'New' }
        $result.Add($copy)
    }
    if ($HasBaseline) {
        foreach ($item in @($PreviousItems)) {
            if (-not $currentById.ContainsKey([string]$item.StableId) -or
                [string]$currentById[[string]$item.StableId].StateHash -ne [string]$item.StateHash) {
                $copy = $item | Select-Object *
                $copy.ComparisonStatus = 'Resolved'
                $copy.ActionCode = 'OpenReport'
                $result.Add($copy)
            }
        }
    }
    $severityRank = @{ High=0; Medium=1; Low=2 }
    $comparisonRank = @{ New=0; Resolved=1; Unchanged=2; NoBaseline=3 }
    return @($result.ToArray() | Sort-Object `
        @{Expression={ $comparisonRank[[string]$_.ComparisonStatus] }},
        @{Expression={ $severityRank[[string]$_.Severity] }}, Category, Name)
}

function Get-ToolResultCenterState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReportRoot,
        [ValidateRange(2, 240)][int]$MaximumReports = 80
    )
    $history = @(Get-ToolResultReportHistory -ReportRoot $ReportRoot -MaximumReports $MaximumReports)
    if ($history.Count -eq 0) {
        return [pscustomobject][ordered]@{
            SchemaVersion=$script:ToolResultCenterSchemaVersion; HasReport=$false; HasBaseline=$false
            Latest=$null; Previous=$null; Items=@(); HighCount=0; MediumCount=0; LowCount=0
        }
    }
    $latest = $history[0]
    $previous = @($history | Where-Object {
        $_.Path -ne $latest.Path -and [string]::Equals([string]$_.Mode, [string]$latest.Mode, [StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1)
    $currentItems = @(ConvertTo-ToolResultCenterItems -Report $latest.Report -SourceReportPath $latest.Path)
    $previousItems = if ($previous.Count -gt 0) { @(ConvertTo-ToolResultCenterItems -Report $previous[0].Report -SourceReportPath $previous[0].Path) } else { @() }
    $comparison = @(Compare-ToolResultCenterItems -CurrentItems $currentItems -PreviousItems $previousItems -HasBaseline:($previous.Count -gt 0))
    return [pscustomobject][ordered]@{
        SchemaVersion = [string]$script:ToolResultCenterSchemaVersion
        HasReport = $true
        HasBaseline = [bool]($previous.Count -gt 0)
        Latest = $latest
        Previous = if ($previous.Count -gt 0) { $previous[0] } else { $null }
        Items = $comparison
        HighCount = [int]@($currentItems | Where-Object Severity -eq 'High').Count
        MediumCount = [int]@($currentItems | Where-Object Severity -eq 'Medium').Count
        LowCount = [int]@($currentItems | Where-Object Severity -eq 'Low').Count
    }
}

function Select-ToolResultCenterItems {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Items,
        [string]$SearchText = '',
        [ValidateSet('All','High','Medium','Low')][string]$Severity = 'All',
        [ValidateSet('All','New','Resolved','Unchanged','NoBaseline')][string]$ComparisonStatus = 'All'
    )
    $needle = $SearchText.Trim()
    return @($Items | Where-Object {
        $severityMatch = $Severity -eq 'All' -or [string]$_.Severity -eq $Severity
        $statusMatch = $ComparisonStatus -eq 'All' -or [string]$_.ComparisonStatus -eq $ComparisonStatus
        $searchText = (@($_.Name,$_.Publisher,$_.StatusCode,$_.StatusText,$_.EvidenceText,$_.Category) -join ' ')
        $searchMatch = [string]::IsNullOrWhiteSpace($needle) -or
            $searchText.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0
        $severityMatch -and $statusMatch -and $searchMatch
    })
}

function Get-ToolBackupCenterItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [ValidateRange(1, 240)][int]$MaximumBackups = 100
    )
    $backupRoot = Join-Path ([IO.Path]::GetFullPath($DataRoot)) 'backups'
    try {
        if (-not (Test-Path -LiteralPath $backupRoot -PathType Container -ErrorAction Stop)) { return @() }
        $rootItem = Get-Item -LiteralPath $backupRoot -Force -ErrorAction Stop
        if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { return @() }
    } catch { return @() }
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($directory in @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First $MaximumBackups)) {
        $manifestPath = Join-Path $directory.FullName 'RESTORE-MANIFEST.json'
        try {
            $manifest = Read-ToolResultJsonFile -Path $manifestPath -MaximumMegabytes 4
            $created = $directory.CreationTime
            $createdText = [string](Get-ToolResultObjectValue $manifest @('CreatedAt'))
            $parsed = [DateTime]::MinValue
            if (-not [string]::IsNullOrWhiteSpace($createdText) -and [DateTime]::TryParse($createdText, [ref]$parsed)) { $created = $parsed }
            $result.Add([pscustomobject][ordered]@{
                Directory = [string]$directory.FullName
                Name = [string]$directory.Name
                CreatedAt = $created
                Scope = [string](Get-ToolResultObjectValue $manifest @('BackupScope') 'Unknown')
                ItemCount = [int]@(Get-ToolResultObjectValue $manifest @('Items') @()).Count
                IntegrityStatus = 'NotChecked'
                Manifest = $manifest
            })
        } catch {
            $result.Add([pscustomobject][ordered]@{
                Directory=[string]$directory.FullName; Name=[string]$directory.Name; CreatedAt=$directory.CreationTime
                Scope='Unknown'; ItemCount=0; IntegrityStatus='InvalidManifest'; Manifest=$null
            })
        }
    }
    return $result.ToArray()
}

function Get-ToolBackupPathHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'BackupReparsePoint' }
    if (-not $item.PSIsContainer) { return Get-ToolResultFileSha256 -Path $item.FullName }
    $root = [IO.Path]::GetFullPath($item.FullName).TrimEnd('\')
    $children = @(Get-ChildItem -LiteralPath $root -Force -Recurse -ErrorAction Stop)
    if ($children.Count -gt 10000) { throw 'BackupItemLimitExceeded' }
    if (@($children | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) { throw 'BackupReparsePoint' }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($file in @($children | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\')
        $lines.Add(($relative + '|' + (Get-ToolResultFileSha256 -Path $file.FullName)))
    }
    return Get-ToolResultStringSha256 ($lines.ToArray() -join "`n")
}

function Get-ToolResultMachineBinding {
    $machineGuid = ''
    try { $machineGuid = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid } catch {}
    return Get-ToolResultStringSha256 ($env:COMPUTERNAME + '|' + $machineGuid)
}

function Test-ToolBackupCenterItemIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupDirectory,
        [Parameter(Mandatory = $true)][string]$DataRoot
    )
    $errors = New-Object System.Collections.Generic.List[string]
    $checkedFiles = 0
    $backupRoot = Join-Path ([IO.Path]::GetFullPath($DataRoot)) 'backups'
    if (-not (Test-ToolResultPathWithinRoot -Path $BackupDirectory -Root $backupRoot)) { $errors.Add('OutsideProtectedBackupRoot') }
    if ($errors.Count -eq 0) {
        try {
            $directory = Get-Item -LiteralPath $BackupDirectory -Force -ErrorAction Stop
            if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'UnsafeBackupDirectory' }
            $manifestPath = Join-Path $directory.FullName 'RESTORE-MANIFEST.json'
            $hmacPath = Join-Path $directory.FullName 'RESTORE-MANIFEST.hmac'
            $authPath = Join-Path $directory.FullName 'RESTORE-AUTH.bin'
            foreach ($required in @($manifestPath,$hmacPath,$authPath)) {
                $requiredItem = Get-Item -LiteralPath $required -Force -ErrorAction Stop
                if ($requiredItem.PSIsContainer -or ($requiredItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'UnsafeAuthenticationComponent' }
            }
            Add-Type -AssemblyName System.Security -ErrorAction Stop
            $protectedKey = [IO.File]::ReadAllBytes($authPath)
            $hmacKey = [Security.Cryptography.ProtectedData]::Unprotect($protectedKey, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
            try {
                $expected = ([IO.File]::ReadAllText($hmacPath)).Trim().ToUpperInvariant()
                if ($expected -notmatch '^[0-9A-F]{64}$') { throw 'InvalidManifestHmac' }
                $hmac = New-Object Security.Cryptography.HMACSHA256(,$hmacKey)
                try { $actual = ([BitConverter]::ToString($hmac.ComputeHash([IO.File]::ReadAllBytes($manifestPath))) -replace '-', '').ToUpperInvariant() }
                finally { $hmac.Dispose() }
                if ($actual -ne $expected) { throw 'ManifestHmacMismatch' }
            } finally { if ($hmacKey) { [Array]::Clear($hmacKey, 0, $hmacKey.Length) } }

            $manifest = Read-ToolResultJsonFile -Path $manifestPath -MaximumMegabytes 4
            if ([string](Get-ToolResultObjectValue $manifest @('SchemaVersion')) -ne '2.0') { throw 'UnsupportedBackupSchema' }
            if ([string](Get-ToolResultObjectValue $manifest @('MachineBinding')) -ne (Get-ToolResultMachineBinding)) { throw 'MachineBindingMismatch' }
            $items = @(Get-ToolResultObjectValue $manifest @('Items') @())
            if ($items.Count -gt 5000) { throw 'BackupItemLimitExceeded' }
            foreach ($item in $items) {
                $relative = [string](Get-ToolResultObjectValue $item @('BackupPath'))
                $expectedHash = [string](Get-ToolResultObjectValue $item @('BackupSha256'))
                if ([string]::IsNullOrWhiteSpace($relative)) { continue }
                if ([IO.Path]::IsPathRooted($relative) -or $relative -match ':' -or
                    $relative -match '(^|[\\/])\.\.?([\\/]|$)') { throw 'UnsafeBackupItemPath' }
                $path = Join-Path $directory.FullName $relative
                if (-not (Test-ToolResultPathWithinRoot -Path $path -Root $directory.FullName)) { throw 'UnsafeBackupItemPath' }
                if (-not (Test-Path -LiteralPath $path)) { throw ('BackupItemMissing:' + $relative) }
                $actualHash = Get-ToolBackupPathHash -Path $path
                if ($expectedHash -notmatch '^[0-9A-Fa-f]{64}$' -or $actualHash -ne $expectedHash.ToUpperInvariant()) { throw ('BackupItemHashMismatch:' + $relative) }
                $checkedFiles++
            }
            foreach ($dependency in @(
                @('windows-license-restore.ps1','RestoreScriptSha256'),
                @('Tool-Runtime.ps1','RuntimeHelperSha256'),
                @('Tool-SafetyPolicy.ps1','SafetyPolicySha256'),
                @('Tool-Localization.ps1','LocalizationHelperSha256'),
                @('Tool-Strings.vi-VN.json','ViCatalogSha256'),
                @('Tool-Strings.en-US.json','EnCatalogSha256')
            )) {
                $expectedHash = [string](Get-ToolResultObjectValue $manifest @($dependency[1]))
                if ([string]::IsNullOrWhiteSpace($expectedHash)) { continue }
                $path = Join-Path $directory.FullName $dependency[0]
                if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-ToolResultFileSha256 -Path $path) -ne $expectedHash.ToUpperInvariant()) {
                    throw ('BackupDependencyHashMismatch:' + $dependency[0])
                }
                $checkedFiles++
            }
        } catch { $errors.Add((ConvertTo-ToolResultCenterText $_.Exception.Message 500)) }
    }
    return [pscustomobject][ordered]@{
        Valid = [bool]($errors.Count -eq 0)
        StatusCode = if ($errors.Count -eq 0) { 'Valid' } else { 'Invalid' }
        CheckedFileCount = [int]$checkedFiles
        Errors = $errors.ToArray()
    }
}

function Protect-ToolSupportText {
    param([AllowNull()][string]$Value)
    $text = ConvertTo-ToolResultCenterText $Value 4096
    foreach ($sensitive in @($env:USERNAME,$env:COMPUTERNAME,[Environment]::GetFolderPath('UserProfile'))) {
        if (-not [string]::IsNullOrWhiteSpace([string]$sensitive)) { $text = [regex]::Replace($text, [regex]::Escape([string]$sensitive), '[REDACTED]', 'IgnoreCase') }
    }
    $text = [regex]::Replace($text, '(?i)\b[A-Z]:\\[^\r\n\|;,\"]+', '[REDACTED_PATH]')
    $text = [regex]::Replace($text, '(?i)\\\\[^\\\s]+\\[^\r\n\|;,\"]+', '[REDACTED_UNC]')
    $text = [regex]::Replace($text, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[REDACTED_EMAIL]')
    $text = [regex]::Replace($text, '(?<![0-9.])(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])(?:\.(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])){3}(?![0-9.])', '[REDACTED_IP]')
    $ipv6Evaluator = [Text.RegularExpressions.MatchEvaluator]{
        param([Text.RegularExpressions.Match]$match)
        $candidate = [string]$match.Groups['Address'].Value
        $scopeIndex = $candidate.IndexOf('%')
        $addressForParsing = if ($scopeIndex -ge 0) { $candidate.Substring(0, $scopeIndex) } else { $candidate }
        $parsedAddress = $null
        if ([Net.IPAddress]::TryParse($addressForParsing, [ref]$parsedAddress) -and
            $parsedAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) { return '[REDACTED_IP]' }
        return $match.Value
    }
    $text = [regex]::Replace($text, '(?i)\[(?<Address>[0-9A-F:.]+(?:%[0-9A-Z_.~-]+)?)\](?::[0-9]{1,5})?', $ipv6Evaluator)
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-Z_.:%-])(?<Address>(?=[0-9A-F:.%_-]*:)[0-9A-F:.]+(?:%[0-9A-Z_.~-]+)?)(?![0-9A-Z_:%~-])', $ipv6Evaluator)
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', '[REDACTED_MAC]')
    $text = [regex]::Replace($text, '(?i)\bS-\d-(?:\d+-){1,14}\d+\b', '[REDACTED_ID]')
    $text = [regex]::Replace($text, '(?i)\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b', '[REDACTED_ID]')
    $text = [regex]::Replace($text, '(?i)\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}\b', '[REDACTED_KEY]')
    return $text
}

function Get-ToolSupportBundlePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReportRoot,
        [string]$LogPath = '',
        [string]$SourceExecutablePath = ''
    )
    $history = @(Get-ToolResultReportHistory -ReportRoot $ReportRoot -MaximumReports 80)
    $reportEntry = @($history | Where-Object { $_.Redacted } | Select-Object -First 1)
    $files = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    if ($reportEntry.Count -gt 0) {
        $files.Add([pscustomobject]@{ Kind='RedactedJsonReport'; Source=$reportEntry[0].Path; Target='REPORT.json' })
        $htmlPath = [IO.Path]::ChangeExtension([string]$reportEntry[0].Path, '.html')
        if ((Test-Path -LiteralPath $htmlPath -PathType Leaf) -and (Test-ToolResultPathWithinRoot -Path $htmlPath -Root $ReportRoot)) {
            $htmlItem = Get-Item -LiteralPath $htmlPath -Force
            if (-not ($htmlItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $htmlItem.Length -le 32MB) {
                $files.Add([pscustomobject]@{ Kind='RedactedHtmlReport'; Source=$htmlPath; Target='REPORT.html' })
            }
        }
    } else { $warnings.Add('NoRedactedReport') }
    if (-not [string]::IsNullOrWhiteSpace($LogPath) -and (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        $logItem = Get-Item -LiteralPath $LogPath -Force
        if (-not ($logItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $logItem.Extension -eq '.jsonl' -and $logItem.Length -le 32MB) {
            $files.Add([pscustomobject]@{ Kind='SanitizedLog'; Source=$logItem.FullName; Target='LOG-SAFE.jsonl' })
        }
    }
    $executableHash = ''
    $signatureStatus = 'NotAvailable'
    if (-not [string]::IsNullOrWhiteSpace($SourceExecutablePath) -and (Test-Path -LiteralPath $SourceExecutablePath -PathType Leaf)) {
        try { $executableHash = Get-ToolResultFileSha256 -Path $SourceExecutablePath } catch {}
        try { $signatureStatus = [string](Get-AuthenticodeSignature -FilePath $SourceExecutablePath -ErrorAction Stop).Status } catch {}
    }
    return [pscustomobject][ordered]@{
        Ready = [bool]($reportEntry.Count -gt 0)
        Report = if ($reportEntry.Count -gt 0) { $reportEntry[0] } else { $null }
        Files = $files.ToArray()
        Warnings = $warnings.ToArray()
        ExecutableSha256 = $executableHash
        SignatureStatus = $signatureStatus
        PrivacyNotice = 'Only a report already marked Redacted and a newly sanitized log are included. Raw log Data fields are excluded.'
    }
}

function Write-ToolSanitizedSupportLog {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )
    $records = New-Object System.Collections.Generic.List[string]
    foreach ($line in @(Get-Content -LiteralPath $SourcePath -Tail 1200 -ErrorAction Stop)) {
        if ([string]::IsNullOrWhiteSpace([string]$line) -or ([string]$line).Length -gt 32768) { continue }
        try {
            $raw = [string]$line | ConvertFrom-Json -ErrorAction Stop
            $level = [string](Get-ToolResultObjectValue $raw @('Level'))
            if ($level -notin @('WARN','ERROR')) { continue }
            $safe = [pscustomobject][ordered]@{
                SchemaVersion = '1.0'
                TimestampUtc = [string](Get-ToolResultObjectValue $raw @('TimestampUtc'))
                ToolVersion = [string](Get-ToolResultObjectValue $raw @('ToolVersion'))
                Component = Protect-ToolSupportText ([string](Get-ToolResultObjectValue $raw @('Component')))
                Level = $level
                Event = Protect-ToolSupportText ([string](Get-ToolResultObjectValue $raw @('Event')))
                Message = Protect-ToolSupportText ([string](Get-ToolResultObjectValue $raw @('Message')))
                DurationMs = Get-ToolResultObjectValue $raw @('DurationMs')
            }
            $records.Add(($safe | ConvertTo-Json -Compress -Depth 4))
        } catch {}
    }
    [IO.File]::WriteAllLines($DestinationPath, $records.ToArray(), (New-Object Text.UTF8Encoding($false)))
    return $records.Count
}

function New-ToolSupportBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReportRoot,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [string]$LogPath = '',
        [string]$SourceExecutablePath = '',
        [switch]$AllowOverwrite
    )
    $plan = Get-ToolSupportBundlePlan -ReportRoot $ReportRoot -LogPath $LogPath -SourceExecutablePath $SourceExecutablePath
    if (-not $plan.Ready) { throw 'RedactedReportRequired' }
    $destinationFull = [IO.Path]::GetFullPath($DestinationPath)
    if ([IO.Path]::GetExtension($destinationFull) -ne '.zip') { throw 'SupportBundleExtensionInvalid' }
    $destinationDirectory = Split-Path -Parent $destinationFull
    $destinationDirectoryItem = Get-Item -LiteralPath $destinationDirectory -Force -ErrorAction Stop
    if (-not $destinationDirectoryItem.PSIsContainer -or ($destinationDirectoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'SupportBundleDestinationUnsafe' }
    if ((Test-Path -LiteralPath $destinationFull) -and -not $AllowOverwrite) { throw 'SupportBundleAlreadyExists' }

    $stage = Join-Path ([IO.Path]::GetTempPath()) ('ToolKiemTra-Support-' + [Guid]::NewGuid().ToString('N'))
    $temporaryZip = Join-Path ([IO.Path]::GetTempPath()) ('ToolKiemTra-Support-' + [Guid]::NewGuid().ToString('N') + '.zip')
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
    try {
        $manifestFiles = New-Object System.Collections.Generic.List[object]
        foreach ($file in @($plan.Files)) {
            $target = Join-Path $stage ([string]$file.Target)
            if ([string]$file.Kind -eq 'SanitizedLog') {
                $recordCount = Write-ToolSanitizedSupportLog -SourcePath ([string]$file.Source) -DestinationPath $target
                if ($recordCount -eq 0) { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue; continue }
            } else {
                [IO.File]::Copy([string]$file.Source, $target, $true)
            }
            $manifestFiles.Add([pscustomobject][ordered]@{
                Name=[string]$file.Target; Kind=[string]$file.Kind; Sha256=(Get-ToolResultFileSha256 -Path $target); Length=[int64](Get-Item -LiteralPath $target).Length
            })
        }
        $identityLines = @(
            'Tool Kiem Tra v5.0',
            ('Executable SHA-256: ' + $(if ($plan.ExecutableSha256) { $plan.ExecutableSha256 } else { 'Not available' })),
            ('Authenticode status: ' + $plan.SignatureStatus)
        )
        [IO.File]::WriteAllLines((Join-Path $stage 'BUILD-IDENTITY.txt'), $identityLines, (New-Object Text.UTF8Encoding($false)))
        $manifestFiles.Add([pscustomobject][ordered]@{
            Name='BUILD-IDENTITY.txt'; Kind='BuildIdentity'; Sha256=(Get-ToolResultFileSha256 -Path (Join-Path $stage 'BUILD-IDENTITY.txt')); Length=[int64](Get-Item -LiteralPath (Join-Path $stage 'BUILD-IDENTITY.txt')).Length
        })
        $readme = @(
            'GOI HO TRO TOOL KIEM TRA v5.0',
            'Goi nay chi chua bao cao da duoc danh dau che dinh danh va nhat ky WARN/ERROR da loc lai.',
            'Khong chua truong Data, ma tuong quan, ten may/nguoi dung, duong dan day du, IP, MAC, email hoac khoa san pham nhan dien duoc.',
            '',
            'TOOL KIEM TRA v5.0 SUPPORT BUNDLE',
            'This bundle contains only an already-redacted report and a newly sanitized WARN/ERROR log.',
            'Raw Data fields and recognizable identifiers are excluded.'
        )
        [IO.File]::WriteAllLines((Join-Path $stage 'README.txt'), $readme, (New-Object Text.UTF8Encoding($false)))
        $manifestFiles.Add([pscustomobject][ordered]@{
            Name='README.txt'; Kind='Readme'; Sha256=(Get-ToolResultFileSha256 -Path (Join-Path $stage 'README.txt')); Length=[int64](Get-Item -LiteralPath (Join-Path $stage 'README.txt')).Length
        })
        $manifest = [pscustomobject][ordered]@{
            SchemaVersion='1.0'; ToolVersion='5.0'; CreatedAtUtc=[DateTime]::UtcNow.ToString('o')
            PrivacyModel='RedactedReportAndSanitizedLogOnly'; Files=$manifestFiles.ToArray()
        }
        [IO.File]::WriteAllText((Join-Path $stage 'SUPPORT-MANIFEST.json'), ($manifest | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        [IO.Compression.ZipFile]::CreateFromDirectory($stage, $temporaryZip, [IO.Compression.CompressionLevel]::Optimal, $false)
        if (Test-Path -LiteralPath $destinationFull) { Remove-Item -LiteralPath $destinationFull -Force -ErrorAction Stop }
        Move-Item -LiteralPath $temporaryZip -Destination $destinationFull -Force -ErrorAction Stop
        return [pscustomobject][ordered]@{
            Success=$true; Path=$destinationFull; Sha256=(Get-ToolResultFileSha256 -Path $destinationFull)
            FileCount=[int]$manifestFiles.Count + 1; PrivacyModel='RedactedReportAndSanitizedLogOnly'
        }
    } finally {
        if (Test-Path -LiteralPath $stage -PathType Container) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $temporaryZip -PathType Leaf) { Remove-Item -LiteralPath $temporaryZip -Force -ErrorAction SilentlyContinue }
    }
}
