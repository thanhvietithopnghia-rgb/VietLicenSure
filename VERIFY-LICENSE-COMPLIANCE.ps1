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
    foreach($name in @('Get-ToolLicenseEntitlements','Set-ToolLicenseEntitlement','Set-ToolLicenseEntitlementAssignment','Add-ToolLicenseEntitlementDocument','Set-ToolLicenseEntitlementDocumentVerification','Get-ToolLicenseComplianceSoftwareInventory','Get-ToolLicenseComplianceReconciliation','Get-ToolLicenseAdvisorResult','Get-ToolLicenseComplianceSnapshot')) {
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
    Assert-Compliance ([string]$document.VerificationStatus -eq 'Attached' -and [string]::IsNullOrWhiteSpace([string]$document.VerifiedAtUtc)) 'New evidence was implicitly treated as verified.'
    $storedDocumentPath = Join-Path $compliancePaths.Documents ([string]$document.StoredName)
    Assert-Compliance (Test-Path -LiteralPath $storedDocumentPath -PathType Leaf) 'Stored evidence document is missing.'

    $script:complianceFixtureObservations = @(
            [pscustomobject][ordered]@{ ClientId=$clientId; ClientReference='CLIENT-TEST'; ComputerName='TEST-PC'; ProductScope='Software'; CatalogProductId='commercial-suite'; ProductName='Commercial Suite'; LicenseModel='Paid'; TechnicalStatus='InventoryOnly' },
            [pscustomobject][ordered]@{ ClientId=$clientId; ClientReference='CLIENT-TEST'; ComputerName='TEST-PC'; ProductScope='Software'; CatalogProductId='uncovered-suite'; ProductName='Uncovered Suite'; LicenseModel='Subscription'; TechnicalStatus='InventoryOnly' }
    )
    function Get-ToolEnterpriseServerClients {
        return @([pscustomobject][ordered]@{ ClientId=$clientId; ComputerName='TEST-PC'; WindowsStatus='NotDetected'; OfficeStatus='NotDetected' })
    }
    $enterprisePaths = Initialize-ToolEnterpriseStorage
    $coverageReportDirectory = Join-Path $enterprisePaths.ServerReports $clientId
    New-Item -ItemType Directory -Path $coverageReportDirectory -Force | Out-Null
    Write-ToolEnterpriseJson -Path (Join-Path $coverageReportDirectory 'latest.json') -Value ([ordered]@{
        SoftwareInventory=@(); SoftwareInventoryCoverage=[ordered]@{ CoverageStatus='Partial'; CoverageReason='MaximumItemsReached'; IncludedCount=300; OmittedCount=7 }
    })
    $productionCoverage = @(Get-ToolLicenseComplianceFleetCoverage)
    Assert-Compliance ($productionCoverage.Count -eq 1 -and [string]$productionCoverage[0].CoverageStatus -eq 'Partial' -and [int]$productionCoverage[0].OmittedCount -eq 7) 'Fleet report inventory coverage metadata was not preserved.'
    function Get-ToolLicenseComplianceFleetObservations {
        return @($script:complianceFixtureObservations)
    }
    $script:complianceFixtureCoverageStatus = 'Complete'
    function Get-ToolLicenseComplianceFleetCoverage {
        return @([pscustomobject][ordered]@{ ClientReference='CLIENT-TEST'; CoverageStatus=$script:complianceFixtureCoverageStatus; CoverageReason='Fixture'; IncludedCount=@($script:complianceFixtureObservations).Count; OmittedCount=$(if($script:complianceFixtureCoverageStatus -eq 'Partial'){1}else{0}) })
    }
    $attachedOnly = Get-ToolLicenseComplianceReconciliation
    $attachedOnlyRow = @($attachedOnly.Rows | Where-Object EntitlementId -eq $record.EntitlementId | Select-Object -First 1)
    Assert-Compliance ($attachedOnlyRow.Count -eq 1 -and [string]$attachedOnlyRow[0].ComplianceState -eq 'NeedsReview' -and [string]$attachedOnlyRow[0].ComplianceReason -eq 'DocumentEvidenceUnverified' -and [int]$attachedOnlyRow[0].VerifiedDocumentCount -eq 0) 'Attached evidence was treated as verified entitlement proof.'
    $missingVerificationMetadataBlocked = $false
    try { [void](Set-ToolLicenseEntitlementDocumentVerification -EntitlementId $record.EntitlementId -DocumentId $document.DocumentId -Status Verified) } catch { $missingVerificationMetadataBlocked = $true }
    Assert-Compliance $missingVerificationMetadataBlocked 'Evidence verification accepted missing verifier/source/scope metadata.'
    $verifiedDocument = Set-ToolLicenseEntitlementDocumentVerification -EntitlementId $record.EntitlementId -DocumentId $document.DocumentId -Status Verified -VerifiedBy 'Compliance Reviewer' -VerificationSource 'Vendor portal and signed agreement' -VerificationScope 'Commercial Suite; Example Organization; two devices' -VerificationNotes 'Fixture verification'
    Assert-Compliance ([string]$verifiedDocument.VerificationStatus -eq 'Verified' -and [string]$verifiedDocument.VerifiedAtUtc -match '^\d{4}-\d{2}-\d{2}T') 'Verified evidence metadata was not recorded.'
    $reconciliation = Get-ToolLicenseComplianceReconciliation
    $row = @($reconciliation.Rows | Select-Object -First 1)
    Assert-Compliance ($row.Count -eq 1) 'Reconciliation row is missing.'
    Assert-Compliance ([int]$row[0].Purchased -eq 2 -and [int]$row[0].Assigned -eq 1 -and [int]$row[0].Installed -eq 1 -and [int]$row[0].Available -eq 1) 'Purchased/Assigned/Installed reconciliation is incorrect.'
    Assert-Compliance ([string]$row[0].ComplianceState -eq 'Compliant') 'Expected a compliant entitlement.'
    Assert-Compliance (@($reconciliation.Uncovered).Count -eq 1 -and [string]$reconciliation.Uncovered[0].ProductName -eq 'Uncovered Suite') 'Uncovered commercial software was not reported.'

    [void](Set-ToolLicenseEntitlementAssignment -EntitlementId $record.EntitlementId -ClientId $clientId -Quantity 3)
    $critical = @(Get-ToolLicenseComplianceReconciliation).Rows | Select-Object -First 1
    Assert-Compliance ([string]$critical.ComplianceState -eq 'Critical') 'Over-allocation was not marked Critical.'

    $secondClientId = [Guid]::NewGuid().ToString('N')
    $userRecord = Set-ToolLicenseEntitlement -ProductScope Software -CatalogProductId 'user-suite' -ProductName 'User Suite' -Vendor 'Example Vendor' -LicenseModel Subscription -Metric User -PurchasedQuantity 1
    $concurrentRecord = Set-ToolLicenseEntitlement -ProductScope Software -CatalogProductId 'concurrent-suite' -ProductName 'Concurrent Suite' -Vendor 'Example Vendor' -LicenseModel Subscription -Metric Concurrent -PurchasedQuantity 1
    $windowsRecord = Set-ToolLicenseEntitlement -ProductScope Windows -CatalogProductId 'windows-11-home' -ProductName 'Windows 11 Home' -Vendor Microsoft -LicenseModel Retail -Metric Device -PurchasedQuantity 1
    $script:complianceFixtureObservations = @($script:complianceFixtureObservations) + @(
        [pscustomobject][ordered]@{ ClientId=$clientId; ClientReference='CLIENT-TEST'; ComputerName='TEST-PC'; ProductScope='Software'; CatalogProductId='user-suite'; ProductName='User Suite'; LicenseModel='Subscription'; TechnicalStatus='InventoryOnly' },
        [pscustomobject][ordered]@{ ClientId=$secondClientId; ClientReference='CLIENT-TEST-2'; ComputerName='TEST-PC-2'; ProductScope='Software'; CatalogProductId='user-suite'; ProductName='User Suite'; LicenseModel='Subscription'; TechnicalStatus='InventoryOnly' },
        [pscustomobject][ordered]@{ ClientId=$clientId; ClientReference='CLIENT-TEST'; ComputerName='TEST-PC'; ProductScope='Software'; CatalogProductId='concurrent-suite'; ProductName='Concurrent Suite'; LicenseModel='Subscription'; TechnicalStatus='InventoryOnly' },
        [pscustomobject][ordered]@{ ClientId=$secondClientId; ClientReference='CLIENT-TEST-2'; ComputerName='TEST-PC-2'; ProductScope='Software'; CatalogProductId='concurrent-suite'; ProductName='Concurrent Suite'; LicenseModel='Subscription'; TechnicalStatus='InventoryOnly' },
        [pscustomobject][ordered]@{ ClientId=$clientId; ClientReference='CLIENT-TEST'; ComputerName='TEST-PC'; ProductScope='Windows'; CatalogProductId='windows-11-pro'; ProductName='Windows 11 Pro'; LicenseModel='Retail'; TechnicalStatus='Activated' }
    )
    $failClosed = Get-ToolLicenseComplianceReconciliation
    $userRow = @($failClosed.Rows | Where-Object EntitlementId -eq $userRecord.EntitlementId | Select-Object -First 1)
    $concurrentRow = @($failClosed.Rows | Where-Object EntitlementId -eq $concurrentRecord.EntitlementId | Select-Object -First 1)
    $windowsRow = @($failClosed.Rows | Where-Object EntitlementId -eq $windowsRecord.EntitlementId | Select-Object -First 1)
    Assert-Compliance ($userRow.Count -eq 1 -and [int]$userRow[0].ObservedDevices -eq 2 -and $null -eq $userRow[0].ConsumptionCount -and
        [string]$userRow[0].ConsumptionEvidenceStatus -eq 'InsufficientEvidence' -and [string]$userRow[0].ComplianceState -eq 'NeedsReview' -and
        [string]$userRow[0].ComplianceReason -eq 'MetricEvidenceMissing') 'User metric was inferred from device installations.'
    Assert-Compliance ($concurrentRow.Count -eq 1 -and [int]$concurrentRow[0].ObservedDevices -eq 2 -and $null -eq $concurrentRow[0].ConsumptionCount -and
        [string]$concurrentRow[0].ConsumptionEvidenceStatus -eq 'InsufficientEvidence' -and [string]$concurrentRow[0].ComplianceState -eq 'NeedsReview' -and
        [string]$concurrentRow[0].ComplianceReason -eq 'MetricEvidenceMissing') 'Concurrent metric was inferred from device installations.'
    Assert-Compliance ($windowsRow.Count -eq 1 -and [int]$windowsRow[0].ObservedDevices -eq 1 -and
        [string]$windowsRow[0].IdentityEvidenceStatus -eq 'InsufficientEvidence' -and [string]$windowsRow[0].ComplianceState -eq 'NeedsReview' -and
        [string]$windowsRow[0].ComplianceReason -eq 'ProductIdentityEvidenceMissing') 'A mismatched Windows SKU was treated as compliant.'
    Assert-Compliance (-not (Test-ToolLicenseEntitlementMatchesObservation -Entitlement $windowsRecord -Observation $script:complianceFixtureObservations[-1])) 'A Windows Home entitlement matched a Windows Pro observation.'
    $matchingWindowsObservation = [pscustomobject][ordered]@{ ClientId=$clientId; ProductScope='Windows'; CatalogProductId='windows-11-home'; ProductName='Windows 11 Home' }
    Assert-Compliance (Test-ToolLicenseEntitlementMatchesObservation -Entitlement $windowsRecord -Observation $matchingWindowsObservation) 'An exact Windows catalog product identity did not match.'
    $officeEntitlement = [pscustomobject][ordered]@{ ProductScope='Office'; CatalogProductId='office-2024-home'; ProductName='Office 2024 Home' }
    $officeObservation = [pscustomobject][ordered]@{ ClientId=$clientId; ProductScope='Office'; CatalogProductId='office-2024-pro'; ProductName='Office 2024 Pro' }
    Assert-Compliance (-not (Test-ToolLicenseEntitlementMatchesObservation -Entitlement $officeEntitlement -Observation $officeObservation)) 'A mismatched Office SKU was treated as the same product.'

    $previousPoolingObservations = @($script:complianceFixtureObservations)
    $poolRecordOne = Set-ToolLicenseEntitlement -ProductScope Software -CatalogProductId 'pooled-device-suite' -ProductName 'Pooled Device Suite' -Vendor 'Example Vendor' -LicenseModel Commercial -Metric Device -PurchasedQuantity 5
    $poolRecordTwo = Set-ToolLicenseEntitlement -ProductScope Software -CatalogProductId 'pooled-device-suite' -ProductName 'Pooled Device Suite' -Vendor 'Example Vendor' -LicenseModel Commercial -Metric Device -PurchasedQuantity 5
    [void](Set-ToolLicenseEntitlementAssignment -EntitlementId $poolRecordOne.EntitlementId -ClientId ([Guid]::NewGuid().ToString('N')) -Quantity 5)
    [void](Set-ToolLicenseEntitlementAssignment -EntitlementId $poolRecordTwo.EntitlementId -ClientId ([Guid]::NewGuid().ToString('N')) -Quantity 5)
    $poolDocumentOne = Add-ToolLicenseEntitlementDocument -EntitlementId $poolRecordOne.EntitlementId -Path $documentPath -Kind Agreement
    $poolDocumentTwo = Add-ToolLicenseEntitlementDocument -EntitlementId $poolRecordTwo.EntitlementId -Path $documentPath -Kind Agreement
    [void](Set-ToolLicenseEntitlementDocumentVerification -EntitlementId $poolRecordOne.EntitlementId -DocumentId $poolDocumentOne.DocumentId -Status Verified -VerifiedBy 'Pool Reviewer' -VerificationSource 'Agreement register' -VerificationScope 'Pooled Device Suite; five devices')
    [void](Set-ToolLicenseEntitlementDocumentVerification -EntitlementId $poolRecordTwo.EntitlementId -DocumentId $poolDocumentTwo.DocumentId -Status Verified -VerifiedBy 'Pool Reviewer' -VerificationSource 'Agreement register' -VerificationScope 'Pooled Device Suite; five devices')
    $poolObservations = New-Object System.Collections.Generic.List[object]
    foreach($poolClientIndex in 1..10) {
        [void]$poolObservations.Add([pscustomobject][ordered]@{
            ClientId=[Guid]::NewGuid().ToString('N'); ClientReference=('POOL-' + $poolClientIndex); ComputerName=('POOL-PC-' + $poolClientIndex)
            ProductScope='Software'; CatalogProductId='pooled-device-suite'; ProductName='Pooled Device Suite'; LicenseModel='Paid'; TechnicalStatus='InventoryOnly'
        })
    }
    $script:complianceFixtureObservations = @($poolObservations.ToArray())
    $pooledRows = @((Get-ToolLicenseComplianceReconciliation).Rows | Where-Object { [string]$_.EntitlementId -in @([string]$poolRecordOne.EntitlementId,[string]$poolRecordTwo.EntitlementId) })
    Assert-Compliance ($pooledRows.Count -eq 2 -and [int](($pooledRows | Measure-Object ConsumptionCount -Sum).Sum) -eq 10 -and
        [int](($pooledRows | Measure-Object Installed -Sum).Sum) -eq 10 -and @($pooledRows | Where-Object ObservedDevices -ne 10).Count -eq 0) 'Device consumption was counted more than once across compatible entitlements.'
    Assert-Compliance (@($pooledRows | Where-Object ComplianceState -ne 'Compliant').Count -eq 0) 'A 5+5 entitlement pool did not reconcile a 10-device fleet.'
    $script:complianceFixtureCoverageStatus = 'Partial'
    $partialCoverage = Get-ToolLicenseComplianceReconciliation
    $partialPoolRows = @($partialCoverage.Rows | Where-Object { [string]$_.EntitlementId -in @([string]$poolRecordOne.EntitlementId,[string]$poolRecordTwo.EntitlementId) })
    Assert-Compliance (@($partialPoolRows | Where-Object { [string]$_.ComplianceState -eq 'NeedsReview' -and [string]$_.ComplianceReason -eq 'SoftwareInventoryCoverageIncomplete' }).Count -eq 2 -and [string]$partialCoverage.SoftwareInventoryCoverageStatus -eq 'Partial') 'Partial inventory coverage produced a clean compliance result.'
    $script:complianceFixtureCoverageStatus = 'Complete'
    [void]$poolObservations.Add([pscustomobject][ordered]@{
        ClientId=[Guid]::NewGuid().ToString('N'); ClientReference='POOL-11'; ComputerName='POOL-PC-11'
        ProductScope='Software'; CatalogProductId='pooled-device-suite'; ProductName='Pooled Device Suite'; LicenseModel='Paid'; TechnicalStatus='InventoryOnly'
    })
    $script:complianceFixtureObservations = @($poolObservations.ToArray())
    $overPoolRows = @((Get-ToolLicenseComplianceReconciliation).Rows | Where-Object { [string]$_.EntitlementId -in @([string]$poolRecordOne.EntitlementId,[string]$poolRecordTwo.EntitlementId) })
    Assert-Compliance ([int](($overPoolRows | Measure-Object ConsumptionCount -Sum).Sum) -eq 11 -and
        @($overPoolRows | Where-Object { [string]$_.ComplianceState -eq 'Critical' -and [string]$_.ComplianceReason -eq 'ConsumptionExceedsPurchased' }).Count -eq 1) 'An 11-device fleet was not reported once against a 10-device entitlement pool.'
    foreach($poolRecord in @($poolRecordOne,$poolRecordTwo)) { [void](Remove-ToolLicenseEntitlement -EntitlementId $poolRecord.EntitlementId) }
    $script:complianceFixtureObservations = $previousPoolingObservations

    $inventoryApplications = @(
        [pscustomobject]@{Name='Fixture A';Publisher='Example';IsSystemComponent=$false},
        [pscustomobject]@{Name='Fixture B';Publisher='Example';IsSystemComponent=$false},
        [pscustomobject]@{Name='Fixture C';Publisher='Example';IsSystemComponent=$false}
    )
    $partialInventory = ConvertTo-ToolLicenseComplianceInventoryResult -Applications $inventoryApplications -MaximumItems 2 -CollectionMetadata ([pscustomobject]@{CompleteMachineRead=$true}) -Catalog $null
    Assert-Compliance ([string]$partialInventory.CoverageStatus -eq 'Partial' -and [int]$partialInventory.IncludedCount -eq 2 -and [int]$partialInventory.OmittedCount -eq 1) 'Inventory truncation was not disclosed as Partial.'
    $privilegeLimitedInventory = ConvertTo-ToolLicenseComplianceInventoryResult -Applications $inventoryApplications -MaximumItems 3 -CollectionMetadata ([pscustomobject]@{CompleteMachineRead=$false}) -Catalog $null
    Assert-Compliance ([string]$privilegeLimitedInventory.CoverageStatus -eq 'Partial' -and [string]$privilegeLimitedInventory.CoverageReason -eq 'PrivilegeLimited') 'Privilege-limited inventory was reported as complete.'

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
    Assert-Compliance (@(Get-ToolLicenseEntitlements | Where-Object EntitlementId -eq $record.EntitlementId).Count -eq 0) 'Entitlement removal failed.'
    Assert-Compliance (-not (Test-Path -LiteralPath $documentForEntitlementRemovalPath -PathType Leaf)) 'Entitlement removal left an evidence document on disk.'
    Assert-Compliance (@(Get-ChildItem -LiteralPath $compliancePaths.Documents -File -Filter '*.deleting-*' -ErrorAction SilentlyContinue).Count -eq 0) 'Entitlement removal left a staged document on disk.'
    foreach($fixtureRecord in @($userRecord,$concurrentRecord,$windowsRecord)) { [void](Remove-ToolLicenseEntitlement -EntitlementId $fixtureRecord.EntitlementId) }
    Assert-Compliance (@(Get-ToolLicenseEntitlements).Count -eq 0) 'Compliance fixture cleanup left entitlement records.'
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
