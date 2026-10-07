[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]
function Assert-DetectionEngine([bool]$Condition, [string]$Message) { if (-not $Condition) { [void]$failures.Add($Message) } }

try {
    $schemaPath = Join-Path $root 'detection-finding-schema-v1.0.json'
    $schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-DetectionEngine ([string]$schema.title -eq 'VietLicenSure canonical Finding') 'Canonical Finding JSON schema is missing or invalid.'
    Assert-DetectionEngine (@($schema.required).Count -eq 20) 'Canonical Finding required-property set drifted.'

    . (Join-Path $root 'Tool-LicenseCompliance.ps1')
    . (Join-Path $root 'Tool-SoftwareInventory.ps1')
    foreach ($name in @('New-ToolDetectionFinding','ConvertTo-ToolDetectionFindingFromLicenseAdvisor','ConvertTo-ToolDetectionFindingFromSoftwareAssessment','Test-ToolDetectionLegacyEquivalence')) {
        Assert-DetectionEngine ($null -ne (Get-Command $name -ErrorAction SilentlyContinue)) ('Missing detection-engine function: ' + $name)
    }

    $advisorFixtures = @(
        [pscustomobject]@{ Scope='Windows'; Status='Activated'; Channel='Retail'; Model='Retail'; Entitlement='Compliant'; Rule='VLS-WIN-ACT-001'; Finding='TechnicalActivationPresent'; Confidence='High'; Verdict='NoImmediateIssue' },
        [pscustomobject]@{ Scope='Windows'; Status='Unlicensed'; Channel='Volume:GVLK'; Model='VolumeKMS'; Entitlement='NotVerified'; Rule='VLS-WIN-ACT-002'; Finding='TechnicalActivationNotConfirmed'; Confidence='Medium'; Verdict='ReviewRequired' },
        [pscustomobject]@{ Scope='Office'; Status='Licensed'; Channel='Retail'; Model='Perpetual'; Entitlement='Critical'; Rule='VLS-OFF-ACT-001'; Finding='TechnicalActivationPresent'; Confidence='High'; Verdict='ActionRequired' },
        [pscustomobject]@{ Scope='Software'; Status='InventoryOnly'; Channel=''; Model='OpenSource'; Entitlement='Compliant'; Rule='VLS-SW-CAT-001'; Finding='FreeOrOpenSourceClassification'; Confidence='High'; Verdict='NoImmediateIssue' }
    )
    foreach ($fixture in $advisorFixtures) {
        $legacy = Get-ToolLicenseAdvisorResult -ProductScope $fixture.Scope -TechnicalStatus $fixture.Status -Channel $fixture.Channel -LicenseModel $fixture.Model -EntitlementStatus $fixture.Entitlement
        Assert-DetectionEngine ([string]$legacy.RuleId -eq $fixture.Rule -and [string]$legacy.FindingCode -eq $fixture.Finding -and [string]$legacy.Confidence -eq $fixture.Confidence -and [string]$legacy.OverallVerdict -eq $fixture.Verdict) ('Legacy advisor conclusion drifted: ' + $fixture.Scope + '/' + $fixture.Entitlement)
        Assert-DetectionEngine ($null -ne $legacy.Finding) ('Canonical Finding was not attached: ' + $fixture.Scope)
        Assert-DetectionEngine (Test-ToolDetectionLegacyEquivalence -Legacy $legacy -Finding $legacy.Finding -Kind LicenseAdvisor) ('Legacy/canonical advisor mismatch: ' + $fixture.Scope)
        Assert-DetectionEngine ([string]$legacy.Finding.SchemaVersion -eq '1.0' -and @($legacy.Finding.SourceCoverage).Count -ge 2) ('Advisor schema/coverage is incomplete: ' + $fixture.Scope)
    }

    $softwareFixtures = @(
        [pscustomobject]@{ AssessmentCode='Suspicious'; Confidence='Medium'; LicenseTechnicalState='Suspicious'; LicenseModel='Paid'; AttentionLevel='High'; CleanupFinding=$true; NeedsReview=$true; PresenceState='InstalledConfirmed'; CatalogSource='SignedCatalog'; Evidence=@([pscustomobject]@{ Code='KnownActivatorArtifact'; Source='FileArtifact'; Strength='Strong'; Detail='fixture'; CorrelationLevel='Direct'; Decisive=$true }) },
        [pscustomobject]@{ AssessmentCode='Unverified'; Confidence='Low'; LicenseTechnicalState='Unknown'; LicenseModel='Unknown'; AttentionLevel='Medium'; CleanupFinding=$false; NeedsReview=$true; PresenceState='ResidualOrPortableFiles'; CatalogSource='Unavailable'; Evidence=@() },
        [pscustomobject]@{ AssessmentCode='GenuineVerified'; Confidence='High'; LicenseTechnicalState='GenuineVerified'; LicenseModel='Free'; AttentionLevel='Low'; CleanupFinding=$false; NeedsReview=$false; PresenceState='InstalledConfirmed'; CatalogSource='SignedCatalog'; Evidence=@([pscustomobject]@{ Code='OfficialSignature'; Source='Authenticode'; Strength='Direct'; Detail='Valid'; CorrelationLevel='Direct' }) }
    )
    foreach ($legacy in $softwareFixtures) {
        $before = $legacy | ConvertTo-Json -Depth 8 -Compress
        $finding = ConvertTo-ToolDetectionFindingFromSoftwareAssessment -Assessment $legacy
        $after = $legacy | ConvertTo-Json -Depth 8 -Compress
        Assert-DetectionEngine ($before -eq $after) ('Software adapter mutated the legacy assessment: ' + $legacy.AssessmentCode)
        Assert-DetectionEngine (Test-ToolDetectionLegacyEquivalence -Legacy $legacy -Finding $finding -Kind SoftwareAssessment) ('Legacy/canonical software mismatch: ' + $legacy.AssessmentCode)
        Assert-DetectionEngine ([string]$finding.ProductScope -eq 'Software' -and [string]$finding.RuleId -match '^VLS-SW-DET-[0-9]{3}$') ('Software Finding identity is invalid: ' + $legacy.AssessmentCode)
        if ([string]$legacy.PresenceState -eq 'ResidualOrPortableFiles') { Assert-DetectionEngine ([string]$finding.State -eq 'Residual') 'Residual software state was not preserved.' }
    }

    $badCoverageRejected = $false
    try {
        New-ToolDetectionFinding -RuleId 'VLS-WIN-TST-001' -ProductScope Windows -FindingCode Test -State Active -Confidence High -SourceCoverage @([pscustomobject]@{ SourceCode='Fixture'; Status='MadeUp'; EvidenceCount=0 }) | Out-Null
    } catch { $badCoverageRejected = $true }
    Assert-DetectionEngine $badCoverageRejected 'Invalid source-coverage status was accepted.'
} catch { [void]$failures.Add($_.Exception.Message) }

if ($failures.Count -gt 0) {
    Write-Host ('Detection Engine: FAIL (' + $failures.Count + ')') -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host (' - ' + $failure) -ForegroundColor Red }
    exit 1
}
Write-Host 'Detection Engine: PASS - canonical Finding schema, legacy migration, and old/new equivalence.' -ForegroundColor Green
exit 0
