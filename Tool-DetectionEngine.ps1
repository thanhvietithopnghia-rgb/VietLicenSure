$script:ToolDetectionFindingSchemaVersion = '1.0'
$script:ToolDetectionAllowedScopes = @('Windows','Office','Software')
$script:ToolDetectionAllowedConfidence = @('Confirmed','High','Medium','Low','Informational')
$script:ToolDetectionAllowedStates = @('Active','Residual','Historical','Informational','Unknown','NotApplicable')
$script:ToolDetectionAllowedCoverageStatus = @('Collected','Denied','Unavailable','NotApplicable','Error','Timeout','Rejected')

function ConvertTo-ToolDetectionSafeText {
    param([AllowNull()][object]$Value, [ValidateRange(1,4096)][int]$MaximumLength = 512)
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Replace("`0", '').Replace("`r", ' ').Replace("`n", ' ').Trim()
    $text = [regex]::Replace($text, '(?i)(?<![A-Z0-9])[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}(?![A-Z0-9])', '[REDACTED-PRODUCT-KEY]')
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}

function Get-ToolDetectionPropertyValue {
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory=$true)][string]$Name, [AllowNull()][object]$Default = $null)
    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties[$Name]) { return $Default }
    return $InputObject.$Name
}

function ConvertTo-ToolDetectionEvidence {
    param([AllowNull()][object[]]$Evidence)
    $normalized = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Evidence)) {
        if ($null -eq $item) { continue }
        $code = ConvertTo-ToolDetectionSafeText (Get-ToolDetectionPropertyValue $item 'Code' (Get-ToolDetectionPropertyValue $item 'EvidenceId' 'Evidence')) 80
        $source = ConvertTo-ToolDetectionSafeText (Get-ToolDetectionPropertyValue $item 'Source' (Get-ToolDetectionPropertyValue $item 'SourceCode' 'Unknown')) 80
        $scope = ConvertTo-ToolDetectionSafeText (Get-ToolDetectionPropertyValue $item 'Scope' (Get-ToolDetectionPropertyValue $item 'EvidenceGroup' 'General')) 80
        $strength = ConvertTo-ToolDetectionSafeText (Get-ToolDetectionPropertyValue $item 'Strength' 'Informational') 40
        $value = ConvertTo-ToolDetectionSafeText (Get-ToolDetectionPropertyValue $item 'Value' (Get-ToolDetectionPropertyValue $item 'Detail' '')) 512
        $correlation = ConvertTo-ToolDetectionSafeText (Get-ToolDetectionPropertyValue $item 'CorrelationLevel' 'Uncorrelated') 40
        $normalized.Add([pscustomobject][ordered]@{
            EvidenceId=$(if ($code -match '^VLS-EV-') { $code } else { 'VLS-EV-' + ([regex]::Replace($code.ToUpperInvariant(), '[^A-Z0-9]+', '-').Trim('-')) })
            SourceCode=$source; Scope=$scope; Strength=$strength; Value=$value
            CorrelationLevel=$correlation
            Decisive=[bool](Get-ToolDetectionPropertyValue $item 'Decisive' $false)
        })
    }
    return @($normalized.ToArray())
}

function New-ToolDetectionSourceCoverage {
    param([string[]]$RequestedSources = @(), [AllowNull()][object[]]$Evidence = @(), [hashtable]$StatusOverrides = @{})
    $sources = @($RequestedSources + @($Evidence | ForEach-Object { [string]$_.SourceCode }) | Where-Object { $_ } | Sort-Object -Unique)
    $coverage = New-Object System.Collections.Generic.List[object]
    foreach ($source in $sources) {
        $count = [int]@($Evidence | Where-Object { [string]$_.SourceCode -eq $source }).Count
        $status = if ($StatusOverrides.ContainsKey($source)) { [string]$StatusOverrides[$source] } elseif ($count -gt 0) { 'Collected' } else { 'Unavailable' }
        if ($script:ToolDetectionAllowedCoverageStatus -notcontains $status) { throw ('Invalid source coverage status: ' + $status) }
        $coverage.Add([pscustomobject][ordered]@{ SourceCode=$source; Status=$status; EvidenceCount=$count })
    }
    return @($coverage.ToArray())
}

function New-ToolDetectionFinding {
    param(
        [Parameter(Mandatory=$true)][ValidatePattern('^VLS-(?:WIN|OFF|SW)-[A-Z0-9]+-[0-9]{3}$')][string]$RuleId,
        [ValidateRange(1,9999)][int]$RuleRevision = 1,
        [Parameter(Mandatory=$true)][ValidateSet('Windows','Office','Software')][string]$ProductScope,
        [Parameter(Mandatory=$true)][string]$FindingCode,
        [Parameter(Mandatory=$true)][ValidateSet('Active','Residual','Historical','Informational','Unknown','NotApplicable')][string]$State,
        [Parameter(Mandatory=$true)][ValidateSet('Confirmed','High','Medium','Low','Informational')][string]$Confidence,
        [string]$Risk = 'Review', [string]$TechnicalConclusion = 'NotAssessed', [string]$TamperingConclusion = 'NotAssessed',
        [string]$EntitlementConclusion = 'NotAssessed', [string]$OverallVerdict = 'ReviewRequired', [string]$CorrelationCode = 'SingleSource',
        [AllowNull()][object[]]$Evidence = @(), [AllowNull()][object[]]$SourceCoverage = @(),
        [string]$Explanation = '', [string]$Recommendation = '', [string]$Limitation = ''
    )
    $normalizedEvidence = @(ConvertTo-ToolDetectionEvidence -Evidence $Evidence)
    $coverage = @($SourceCoverage)
    foreach ($item in $coverage) {
        if ($null -eq $item -or [string]::IsNullOrWhiteSpace([string]$item.SourceCode) -or $script:ToolDetectionAllowedCoverageStatus -notcontains [string]$item.Status) {
            throw 'Finding source coverage is invalid.'
        }
    }
    return [pscustomobject][ordered]@{
        SchemaVersion=$script:ToolDetectionFindingSchemaVersion; RuleId=$RuleId; RuleRevision=$RuleRevision
        ProductScope=$ProductScope; FindingCode=(ConvertTo-ToolDetectionSafeText $FindingCode 100); State=$State
        Confidence=$Confidence; ConfidenceScope='FindingOnly'; Risk=(ConvertTo-ToolDetectionSafeText $Risk 40)
        TechnicalConclusion=(ConvertTo-ToolDetectionSafeText $TechnicalConclusion 100)
        TamperingConclusion=(ConvertTo-ToolDetectionSafeText $TamperingConclusion 100)
        EntitlementConclusion=(ConvertTo-ToolDetectionSafeText $EntitlementConclusion 100)
        OverallVerdict=(ConvertTo-ToolDetectionSafeText $OverallVerdict 80)
        CorrelationCode=(ConvertTo-ToolDetectionSafeText $CorrelationCode 40)
        EvidenceSourceCount=[int]@($normalizedEvidence | ForEach-Object SourceCode | Sort-Object -Unique).Count
        Evidence=$normalizedEvidence; SourceCoverage=$coverage
        Explanation=(ConvertTo-ToolDetectionSafeText $Explanation 1200)
        Recommendation=(ConvertTo-ToolDetectionSafeText $Recommendation 1200)
        Limitation=(ConvertTo-ToolDetectionSafeText $Limitation 1200)
    }
}

function ConvertTo-ToolDetectionFindingFromLicenseAdvisor {
    param([Parameter(Mandatory=$true)][object]$Advisor)
    $scope = [string]$Advisor.ProductScope
    $evidence = @(ConvertTo-ToolDetectionEvidence -Evidence @($Advisor.Evidence))
    $requested = if ($scope -eq 'Software') { @('SoftwareInventory','SignedCatalog','ComplianceStore') } else { @('EndpointReport','ComplianceStore') }
    $coverage = New-ToolDetectionSourceCoverage -RequestedSources $requested -Evidence $evidence
    $state = if ([string]$Advisor.OverallVerdict -eq 'NoImmediateIssue') { 'Informational' } else { 'Active' }
    return New-ToolDetectionFinding -RuleId ([string]$Advisor.RuleId) -RuleRevision ([int]$Advisor.RuleRevision) `
        -ProductScope $scope -FindingCode ([string]$Advisor.FindingCode) -State $state -Confidence ([string]$Advisor.Confidence) `
        -Risk ([string]$Advisor.Risk) -TechnicalConclusion ([string]$Advisor.TechnicalConclusion) `
        -TamperingConclusion ([string]$Advisor.TamperingConclusion) -EntitlementConclusion ([string]$Advisor.EntitlementConclusion) `
        -OverallVerdict ([string]$Advisor.OverallVerdict) -CorrelationCode ([string]$Advisor.CorrelationCode) `
        -Evidence $evidence -SourceCoverage $coverage -Explanation ([string]$Advisor.Explanation) `
        -Recommendation ([string]$Advisor.Recommendation) -Limitation ([string]$Advisor.Limitation)
}

function ConvertTo-ToolDetectionFindingFromSoftwareAssessment {
    param([Parameter(Mandatory=$true)][object]$Assessment)
    $code = [string](Get-ToolDetectionPropertyValue $Assessment 'AssessmentCode' 'Unverified')
    $ruleId = switch ($code) {
        'NonGenuine' { 'VLS-SW-DET-001' }; 'Suspicious' { 'VLS-SW-DET-002' }; 'IntegrityCompromised' { 'VLS-SW-DET-003' }
        'FreeOrIncluded' { 'VLS-SW-DET-004' }; 'GenuineVerified' { 'VLS-SW-DET-005' }; 'Unactivated' { 'VLS-SW-DET-006' }
        default { 'VLS-SW-DET-099' }
    }
    $presence = [string](Get-ToolDetectionPropertyValue $Assessment 'PresenceState' 'Unknown')
    $state = if ($presence -in @('ResidualOrPortableFiles','LaunchReferenceOnly')) { 'Residual' }
        elseif ($presence -in @('InstalledConfirmed','RegisteredInstallation','VendorRegisteredProduct','PackagePresent','PortableApplication')) { 'Active' }
        elseif ($code -in @('FreeOrIncluded','GenuineVerified')) { 'Informational' } else { 'Unknown' }
    $confidence = [string](Get-ToolDetectionPropertyValue $Assessment 'Confidence' 'Informational')
    if ($script:ToolDetectionAllowedConfidence -notcontains $confidence) { $confidence = 'Informational' }
    $attention = [string](Get-ToolDetectionPropertyValue $Assessment 'AttentionLevel' 'Medium')
    $risk = if ($attention -eq 'High') { 'High' } elseif ($attention -eq 'Low') { 'Low' } else { 'Review' }
    $evidence = @(ConvertTo-ToolDetectionEvidence -Evidence @(Get-ToolDetectionPropertyValue $Assessment 'Evidence' @()))
    $catalogSource = [string](Get-ToolDetectionPropertyValue $Assessment 'CatalogSource' 'Unavailable')
    $coverageOverrides = @{ SignedCatalog=$(if ($catalogSource -eq 'UntrustedRejected') {'Rejected'} elseif ($catalogSource -eq 'Unavailable') {'Unavailable'} else {'Collected'}) }
    $requestedSources = @('SoftwareInventory','SignedCatalog') + @($evidence | ForEach-Object SourceCode)
    $coverage = New-ToolDetectionSourceCoverage -RequestedSources $requestedSources -Evidence $evidence -StatusOverrides $coverageOverrides
    $cleanup = [bool](Get-ToolDetectionPropertyValue $Assessment 'CleanupFinding' $false)
    $review = [bool](Get-ToolDetectionPropertyValue $Assessment 'NeedsReview' $false)
    $verdict = if ($cleanup) { 'ActionRequired' } elseif ($review) { 'ReviewRequired' } else { 'NoImmediateIssue' }
    $correlation = if (@($evidence | ForEach-Object SourceCode | Sort-Object -Unique).Count -ge 2) { 'CrossSource' } else { 'SingleSource' }
    return New-ToolDetectionFinding -RuleId $ruleId -ProductScope Software -FindingCode $code -State $state -Confidence $confidence `
        -Risk $risk -TechnicalConclusion ([string](Get-ToolDetectionPropertyValue $Assessment 'LicenseTechnicalState' $code)) `
        -TamperingConclusion $(if ($code -in @('NonGenuine','Suspicious','IntegrityCompromised')) {$code} else {'NotDetected'}) `
        -EntitlementConclusion ([string](Get-ToolDetectionPropertyValue $Assessment 'LicenseModel' 'Unknown')) `
        -OverallVerdict $verdict -CorrelationCode $correlation -Evidence $evidence -SourceCoverage $coverage `
        -Explanation ([string](Get-ToolDetectionPropertyValue $Assessment 'LicenseModelReason' '')) `
        -Recommendation ([string](Get-ToolDetectionPropertyValue $Assessment 'RemediationImpact' 'NoChangeProposed')) `
        -Limitation 'A software finding is technical evidence only and does not independently prove legal entitlement or unauthorized use.'
}

function Test-ToolDetectionLegacyEquivalence {
    param([Parameter(Mandatory=$true)][object]$Legacy, [Parameter(Mandatory=$true)][object]$Finding, [ValidateSet('LicenseAdvisor','SoftwareAssessment')][string]$Kind)
    if ($Kind -eq 'LicenseAdvisor') {
        return [bool]([string]$Legacy.RuleId -eq [string]$Finding.RuleId -and [string]$Legacy.ProductScope -eq [string]$Finding.ProductScope -and
            [string]$Legacy.FindingCode -eq [string]$Finding.FindingCode -and [string]$Legacy.Confidence -eq [string]$Finding.Confidence -and
            [string]$Legacy.TechnicalConclusion -eq [string]$Finding.TechnicalConclusion -and [string]$Legacy.TamperingConclusion -eq [string]$Finding.TamperingConclusion -and
            [string]$Legacy.EntitlementConclusion -eq [string]$Finding.EntitlementConclusion -and [string]$Legacy.OverallVerdict -eq [string]$Finding.OverallVerdict)
    }
    $expectedVerdict = if ([bool](Get-ToolDetectionPropertyValue $Legacy 'CleanupFinding' $false)) { 'ActionRequired' }
        elseif ([bool](Get-ToolDetectionPropertyValue $Legacy 'NeedsReview' $false)) { 'ReviewRequired' } else { 'NoImmediateIssue' }
    return [bool]([string]$Legacy.AssessmentCode -eq [string]$Finding.FindingCode -and [string]$Legacy.Confidence -eq [string]$Finding.Confidence -and
        [string]$Legacy.LicenseTechnicalState -eq [string]$Finding.TechnicalConclusion -and $expectedVerdict -eq [string]$Finding.OverallVerdict)
}
