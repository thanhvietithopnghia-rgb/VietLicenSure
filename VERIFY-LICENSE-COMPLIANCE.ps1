[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }

function Assert-Compliance { param([bool]$Condition,[string]$Message) if(-not $Condition){ throw $Message } }

$root = Join-Path ([IO.Path]::GetTempPath()) ('VietLicenSure-Compliance-' + [Guid]::NewGuid().ToString('N'))
$previousRoot = [string]$env:TOOL_ENTERPRISE_ROOT
$previousSkipAcl = [string]$env:TOOL_ENTERPRISE_SKIP_ACL
try {
    $env:TOOL_ENTERPRISE_ROOT = $root
    $env:TOOL_ENTERPRISE_SKIP_ACL = '1'
    . (Join-Path $SourceDirectory 'Tool-Enterprise.ps1')
    foreach($name in @('Get-ToolLicenseEntitlements','Set-ToolLicenseEntitlement','Set-ToolLicenseEntitlementAssignment','Add-ToolLicenseEntitlementDocument','Get-ToolLicenseComplianceReconciliation','Get-ToolLicenseAdvisorResult','Get-ToolLicenseComplianceSnapshot')) {
        Assert-Compliance ($null -ne (Get-Command $name -ErrorAction SilentlyContinue)) "Missing command: $name"
    }

    $clientId = [Guid]::NewGuid().ToString('N')
    $record = Set-ToolLicenseEntitlement -ProductScope Software -CatalogProductId 'commercial-suite' -ProductName 'Commercial Suite' -Vendor 'Example Vendor' -LicenseModel Commercial -PurchasedQuantity 2 -InvoiceNumber 'INV-001'
    Assert-Compliance ([Guid]::Parse([string]$record.EntitlementId) -ne [Guid]::Empty) 'Entitlement ID is invalid.'
    $compliancePaths = Get-ToolLicenseCompliancePaths
    $initialStoreJson = Get-Content -LiteralPath $compliancePaths.Store -Raw -Encoding UTF8
    Assert-Compliance ($initialStoreJson -match '"Assignments"\s*:\s*\[' -and $initialStoreJson -match '"Documents"\s*:\s*\[') 'Empty assignment/document collections were not serialized as arrays.'
    [void](Set-ToolLicenseEntitlementAssignment -EntitlementId $record.EntitlementId -ClientId $clientId -Quantity 1)

    $documentPath = Join-Path $root 'invoice.txt'
    [IO.File]::WriteAllText($documentPath,'evidence fixture',[Text.UTF8Encoding]::new($false))
    $document = Add-ToolLicenseEntitlementDocument -EntitlementId $record.EntitlementId -Path $documentPath -Kind Invoice
    Assert-Compliance ([string]$document.Sha256 -match '^[0-9A-F]{64}$') 'Document SHA-256 was not recorded.'
    Assert-Compliance ([string]$document.OriginalName -eq 'invoice.txt') 'Original document name was not preserved.'
    $storedDocumentPath = Join-Path $compliancePaths.Documents ([string]$document.StoredName)
    Assert-Compliance (Test-Path -LiteralPath $storedDocumentPath -PathType Leaf) 'Stored evidence document is missing.'

    function Get-ToolLicenseComplianceFleetObservations {
        return @(
            [pscustomobject][ordered]@{ ClientId=$clientId; ClientReference='CLIENT-TEST'; ComputerName='TEST-PC'; ProductScope='Software'; CatalogProductId='commercial-suite'; ProductName='Commercial Suite'; LicenseModel='Paid'; TechnicalStatus='InventoryOnly' },
            [pscustomobject][ordered]@{ ClientId=$clientId; ClientReference='CLIENT-TEST'; ComputerName='TEST-PC'; ProductScope='Software'; CatalogProductId='uncovered-suite'; ProductName='Uncovered Suite'; LicenseModel='Subscription'; TechnicalStatus='InventoryOnly' }
        )
    }
    $reconciliation = Get-ToolLicenseComplianceReconciliation
    $row = @($reconciliation.Rows | Select-Object -First 1)
    Assert-Compliance ($row.Count -eq 1) 'Reconciliation row is missing.'
    Assert-Compliance ([int]$row[0].Purchased -eq 2 -and [int]$row[0].Assigned -eq 1 -and [int]$row[0].Installed -eq 1 -and [int]$row[0].Available -eq 1) 'Purchased/Assigned/Installed reconciliation is incorrect.'
    Assert-Compliance ([string]$row[0].ComplianceState -eq 'Compliant') 'Expected a compliant entitlement.'
    Assert-Compliance (@($reconciliation.Uncovered).Count -eq 1 -and [string]$reconciliation.Uncovered[0].ProductName -eq 'Uncovered Suite') 'Uncovered commercial software was not reported.'

    [void](Set-ToolLicenseEntitlementAssignment -EntitlementId $record.EntitlementId -ClientId $clientId -Quantity 3)
    $critical = @(Get-ToolLicenseComplianceReconciliation).Rows | Select-Object -First 1
    Assert-Compliance ([string]$critical.ComplianceState -eq 'Critical') 'Over-allocation was not marked Critical.'

    $advisor = Get-ToolLicenseAdvisorResult -ProductScope Windows -TechnicalStatus Activated -Channel Retail -LicenseModel Retail -EntitlementStatus NotVerified
    Assert-Compliance ([string]$advisor.Risk -eq 'Review') 'Advisor risk is incorrect.'
    Assert-Compliance ([string]$advisor.Explanation -match 'Technical activation' -and [string]$advisor.Limitation -match 'legal ownership') 'Advisor did not separate technical activation from legal entitlement.'
    Assert-Compliance ([string]$advisor.FindingCode -eq 'TechnicalActivationPresent' -and [string]$advisor.RecommendationCode -eq 'AttachEvidenceAndAssign' -and [string]$advisor.LimitationCode -eq 'LegalEntitlementNotProven') 'Advisor stable codes are incomplete.'
    Assert-Compliance ([string]$advisor.SchemaVersion -eq '1.0' -and [string]$advisor.RuleId -eq 'VLS-WIN-ACT-001' -and [int]$advisor.RuleRevision -eq 1) 'Advisor rule identity is incomplete.'
    Assert-Compliance ([string]$advisor.Confidence -eq 'High' -and [string]$advisor.ConfidenceScope -eq 'FindingOnly') 'Advisor confidence is incorrect or over-broad.'
    Assert-Compliance ([string]$advisor.TechnicalConclusion -eq 'TechnicalActivationPresent' -and [string]$advisor.TamperingConclusion -eq 'NotAssessed' -and [string]$advisor.EntitlementConclusion -eq 'NotVerified' -and [string]$advisor.OverallVerdict -eq 'ReviewRequired') 'Advisor did not separate technical, tampering, entitlement and verdict layers.'
    Assert-Compliance ([string]$advisor.CorrelationCode -eq 'CrossSource' -and [int]$advisor.EvidenceSourceCount -eq 2 -and @($advisor.Evidence).Count -eq 3) 'Advisor evidence correlation is incomplete.'
    foreach($item in @($advisor.Evidence)) {
        Assert-Compliance ([string]$item.EvidenceId -match '^VLS-EV-[A-Z-]+$' -and [string]$item.SourceCode -in @('EndpointReport','ComplianceStore','SignedCatalog','SoftwareInventory')) 'Advisor evidence identity or source is invalid.'
        Assert-Compliance ([string]$item.Value -notmatch '(?i)[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}') 'Advisor evidence leaked a full product key.'
    }

    $kmsAdvisor = Get-ToolLicenseAdvisorResult -ProductScope Windows -TechnicalStatus Activated -Channel VolumeKMS -LicenseModel VolumeKMS -EntitlementStatus NotVerified
    Assert-Compliance ([string]$kmsAdvisor.Risk -eq 'Review' -and [string]$kmsAdvisor.TamperingConclusion -eq 'NotAssessed' -and [string]$kmsAdvisor.OverallVerdict -eq 'ReviewRequired') 'KMS alone was incorrectly treated as tampering or an illegal entitlement.'
    $unknownAdvisor = Get-ToolLicenseAdvisorResult -ProductScope Windows -TechnicalStatus '' -Channel '' -LicenseModel Unknown -EntitlementStatus NotVerified
    Assert-Compliance ([string]$unknownAdvisor.Confidence -eq 'Informational' -and [string]$unknownAdvisor.CorrelationCode -eq 'SingleSource') 'Insufficient evidence did not remain informational.'
    $criticalAdvisor = Get-ToolLicenseAdvisorResult -ProductScope Office -TechnicalStatus Licensed -Channel Retail -LicenseModel Retail -EntitlementStatus Critical
    Assert-Compliance ([string]$criticalAdvisor.RuleId -eq 'VLS-OFF-ACT-001' -and [string]$criticalAdvisor.Confidence -eq 'High' -and [string]$criticalAdvisor.OverallVerdict -eq 'ActionRequired') 'Critical entitlement evidence was not classified correctly.'
    $freeAdvisor = Get-ToolLicenseAdvisorResult -ProductScope Software -TechnicalStatus InventoryOnly -LicenseModel OpenSource -EntitlementStatus Compliant
    Assert-Compliance ([string]$freeAdvisor.RuleId -eq 'VLS-SW-CAT-001' -and @($freeAdvisor.Evidence | Where-Object SourceCode -eq 'SignedCatalog').Count -eq 1) 'Signed catalog evidence was not normalized.'

    $snapshot = Get-ToolLicenseComplianceSnapshot | ConvertTo-Json -Depth 12 -Compress
    Assert-Compliance ($snapshot -notmatch '(?i)ClientId|StoredName|documents\\|[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}') 'Dashboard snapshot leaked restricted data.'
    Assert-Compliance ($snapshot -match 'AssuranceScore' -and $snapshot -match 'Critical') 'Compliance summary is incomplete.'

    $badPath = Join-Path $root 'blocked.exe'; [IO.File]::WriteAllText($badPath,'blocked')
    $blocked = $false
    try { [void](Add-ToolLicenseEntitlementDocument -EntitlementId $record.EntitlementId -Path $badPath) } catch { $blocked = $true }
    Assert-Compliance $blocked 'Unsupported evidence extension was accepted.'

    Assert-Compliance (Remove-ToolLicenseEntitlementDocument -EntitlementId $record.EntitlementId -DocumentId $document.DocumentId) 'Evidence document removal failed.'
    Assert-Compliance (-not (Test-Path -LiteralPath $storedDocumentPath -PathType Leaf)) 'Removed evidence document remains on disk.'
    $needsReview = @(Get-ToolLicenseComplianceReconciliation).Rows | Select-Object -First 1
    Assert-Compliance ([string]$needsReview.ComplianceState -eq 'Critical') 'Over-allocation was unexpectedly cleared after evidence removal.'

    $dashboardJs = Get-ToolEnterpriseDashboardJs
    Assert-Compliance ($dashboardJs -match 'item\.Purchased' -and $dashboardJs -match 'item\.Assigned' -and $dashboardJs -match 'RecommendationCode') 'Dashboard does not render reconciliation or advisor fields.'
    Assert-Compliance ($dashboardJs -match "createElement\('details'\)" -and $dashboardJs -match 'advisor\.RuleId' -and $dashboardJs -match 'advisor\.Confidence' -and $dashboardJs -match 'advisor\.Evidence') 'Dashboard does not provide the Explain this finding view.'
    Assert-Compliance ($dashboardJs -notmatch 'innerHTML|document\.write|eval\(') 'Dashboard uses an unsafe DOM sink.'

    $documentForEntitlementRemoval = Add-ToolLicenseEntitlementDocument -EntitlementId $record.EntitlementId -Path $documentPath -Kind Agreement
    $documentForEntitlementRemovalPath = Join-Path $compliancePaths.Documents ([string]$documentForEntitlementRemoval.StoredName)
    [void](Remove-ToolLicenseEntitlement -EntitlementId $record.EntitlementId)
    Assert-Compliance (@(Get-ToolLicenseEntitlements).Count -eq 0) 'Entitlement removal failed.'
    Assert-Compliance (-not (Test-Path -LiteralPath $documentForEntitlementRemovalPath -PathType Leaf)) 'Entitlement removal left an evidence document on disk.'
    Assert-Compliance (@(Get-ChildItem -LiteralPath $compliancePaths.Documents -File -Filter '*.deleting-*' -ErrorAction SilentlyContinue).Count -eq 0) 'Entitlement removal left a staged document on disk.'
    Write-Host 'LICENSE-COMPLIANCE PASS: evidence, reconciliation, advisor, privacy and validation.' -ForegroundColor Green
    exit 0
} catch {
    Write-Error ('LICENSE-COMPLIANCE FAIL: ' + $_.Exception.Message + [Environment]::NewLine + $_.ScriptStackTrace)
    exit 1
} finally {
    $env:TOOL_ENTERPRISE_ROOT = $previousRoot
    $env:TOOL_ENTERPRISE_SKIP_ACL = $previousSkipAcl
    if(Test-Path -LiteralPath $root){ Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
