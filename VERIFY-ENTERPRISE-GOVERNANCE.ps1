[CmdletBinding()]
param([string]$SourceDirectory = "")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }

function Assert-EnterpriseGovernance {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$requiredFiles = @(
    "Tool-Enterprise.ps1",
    "Tool-EnterpriseCli.ps1",
    "Manage-ToolEnterpriseDeployment.ps1",
    "New-ClientVmTestSummary.ps1",
    ".github\workflows\client-vm-matrix.yml",
    "SECURITY.md",
    "AUDIT-SCOPE-v1.md",
    "SECURITY-REVIEW-PROCESS-v1.md",
    "SECURITY-TEST-RESULTS.md",
    "CODE-SIGNING-POLICY-v1.md"
)
foreach ($name in $requiredFiles) {
    Assert-EnterpriseGovernance (Test-Path -LiteralPath (Join-Path $SourceDirectory $name) -PathType Leaf) "Missing enterprise governance file: $name"
}
foreach ($name in @("Tool-Enterprise.ps1", "Tool-EnterpriseCli.ps1", "Manage-ToolEnterpriseDeployment.ps1", "New-ClientVmTestSummary.ps1")) {
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceDirectory $name), [ref]$null, [ref]$errors)
    Assert-EnterpriseGovernance (@($errors).Count -eq 0) "PowerShell parse failed for ${name}: $(@($errors | ForEach-Object ToString) -join '; ')"
}

$previousRoot = [string]$env:TOOL_ENTERPRISE_ROOT
$previousSkipAcl = [string]$env:TOOL_ENTERPRISE_SKIP_ACL
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$testRoot = Join-Path $tempBase ("enterprise-governance-state-" + [Guid]::NewGuid().ToString("N"))
$exportRoot = Join-Path $tempBase ("enterprise-governance-export-" + [Guid]::NewGuid().ToString("N"))
$summaryRoot = Join-Path $tempBase ("enterprise-governance-summary-" + [Guid]::NewGuid().ToString("N"))
try {
    $env:TOOL_ENTERPRISE_ROOT = $testRoot
    $env:TOOL_ENTERPRISE_SKIP_ACL = "1"
    . (Join-Path $SourceDirectory "Tool-Enterprise.ps1")

    $localizationCultures = Get-Variable -Name ToolLocalizationSupportedCultures -Scope Script -ErrorAction SilentlyContinue
    Assert-EnterpriseGovernance ($null -ne $localizationCultures -and @($localizationCultures.Value).Count -ge 2) "Enterprise localization bootstrap did not initialize script-scoped state."

    Assert-EnterpriseGovernance ((ConvertTo-ToolEnterpriseCsvSafeText "=1+1") -eq "'=1+1") "CSV formula beginning with = was not neutralized."
    Assert-EnterpriseGovernance ((ConvertTo-ToolEnterpriseCsvSafeText "  @SUM(A1:A2)") -eq "'@SUM(A1:A2)") "CSV formula beginning with whitespace/@ was not neutralized."
    Assert-EnterpriseGovernance ((ConvertTo-ToolEnterpriseCsvSafeText "normal") -eq "normal") "Normal CSV value was unexpectedly modified."

    $freshId = [Guid]::NewGuid().ToString("D")
    $staleId = [Guid]::NewGuid().ToString("D")
    $freshRecord = [pscustomobject][ordered]@{
        SchemaVersion="1.0"; ClientId=$freshId; ComputerName='=WEBSERVICE("https://invalid.example")'; RemoteAddress="10.20.30.40";
        NetworkAddresses=@("10.20.30.40"); LastSeenUtc=[DateTime]::UtcNow.AddHours(-2).ToString("o"); FirstSeenUtc=[DateTime]::UtcNow.AddDays(-2).ToString("o");
        AllowRemoteLicenseChanges=$false; WindowsStatus="Licensed"; WindowsChannel="Retail"; WindowsLast5="ABCDE";
        OfficeStatus="Licensed"; OfficeChannel="Volume"; OfficeLast5="FGHIJ"; LatestReportPath="C:\private\latest.json"
    }
    $staleRecord = [pscustomobject][ordered]@{
        SchemaVersion="1.0"; ClientId=$staleId; ComputerName="STALE-PC"; RemoteAddress="10.20.30.50";
        NetworkAddresses=@("10.20.30.50"); LastSeenUtc=[DateTime]::UtcNow.AddHours(-100).ToString("o"); FirstSeenUtc=[DateTime]::UtcNow.AddDays(-10).ToString("o");
        AllowRemoteLicenseChanges=$true; WindowsStatus="Unknown"; WindowsChannel=""; WindowsLast5="KLMNO";
        OfficeStatus="NotDetected"; OfficeChannel=""; OfficeLast5=""; LatestReportPath="C:\private\stale.json"
    }
    Write-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $freshId) -Value $freshRecord
    Write-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $staleId) -Value $staleRecord

    $redacted = Export-ToolEnterpriseFleetReport -DestinationDirectory $exportRoot -Formats Json,Csv -StaleAfterHours 24
    Assert-EnterpriseGovernance ($redacted.ClientCount -eq 2 -and $redacted.StaleClientCount -eq 1) "Fleet freshness metadata is incorrect."
    Assert-EnterpriseGovernance (Test-Path -LiteralPath $redacted.ExportDirectory -PathType Container) "Fleet bundle was not atomically published as a directory."
    Assert-EnterpriseGovernance (@(Get-ChildItem -LiteralPath $exportRoot -Directory -Filter "*.staging" -Force -ErrorAction SilentlyContinue).Count -eq 0) "Fleet staging directory remained after publish."
    $redactedJsonText = Get-Content -LiteralPath $redacted.JsonPath -Raw -Encoding UTF8
    $redactedJson = $redactedJsonText | ConvertFrom-Json
    Assert-EnterpriseGovernance ([bool]$redactedJson.Privacy.RedactSensitive) "Fleet export did not redact sensitive values by default."
    Assert-EnterpriseGovernance (-not [bool]$redactedJson.Privacy.FullProductKeysIncluded -and -not [bool]$redactedJson.Privacy.InternalSourcePathsIncluded) "Fleet privacy metadata is unsafe."
    foreach ($secretText in @($freshId,$staleId,'=WEBSERVICE','10.20.30.40','10.20.30.50','ABCDE','FGHIJ','KLMNO','C:\private')) {
        Assert-EnterpriseGovernance ($redactedJsonText -notlike "*$secretText*") "Default fleet export leaked sensitive value: $secretText"
    }

    $filtered = Export-ToolEnterpriseFleetReport -DestinationDirectory $exportRoot -Formats Json,Csv -RedactSensitive:$false -ClientId $freshId -MaximumClientAgeHours 48 -StaleAfterHours 24
    Assert-EnterpriseGovernance ($filtered.ClientCount -eq 1 -and $filtered.SourceClientCount -eq 2) "ClientId/age fleet filter did not return one client."
    $filteredJson = Get-Content -LiteralPath $filtered.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-EnterpriseGovernance ([string]$filteredJson.Clients[0].ClientId -eq $freshId) "Explicit unredacted fleet export did not preserve selected ClientId."
    $filteredCsv = Get-Content -LiteralPath $filtered.CsvPath -Raw -Encoding UTF8
    Assert-EnterpriseGovernance ($filteredCsv -match "'=WEBSERVICE") "Unredacted CSV did not neutralize a formula-like computer name."
    Assert-EnterpriseGovernance ($filteredCsv -notmatch 'C:\\private') "Fleet CSV leaked an internal source path."
    foreach ($line in @(Get-Content -LiteralPath $filtered.ManifestPath -Encoding UTF8 | Select-Object -Skip 1)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\s{2,}', 2
        Assert-EnterpriseGovernance ($parts.Count -eq 2) "Fleet checksum manifest line is invalid."
        $artifactPath = Join-Path $filtered.ExportDirectory $parts[1]
        Assert-EnterpriseGovernance ((Get-ToolEnterpriseSha256Hex -Path $artifactPath) -eq $parts[0]) "Fleet checksum does not match: $($parts[1])"
    }

    $reportExportHelper = Join-Path $SourceDirectory "Tool-ReportExport.ps1"
    . $reportExportHelper
    $originalPdfConverter = (Get-Item -LiteralPath Function:\Convert-ToolHtmlToPdf -ErrorAction Stop).ScriptBlock
    $publishedDirectoriesBeforePdfFailure = @(Get-ChildItem -LiteralPath $exportRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object Name)
    $pdfFailureObserved = $false
    try {
        Set-Item -LiteralPath Function:\Convert-ToolHtmlToPdf -Value {
            param(
                [Parameter(Mandatory = $true)][string]$HtmlPath,
                [Parameter(Mandatory = $true)][string]$PdfPath,
                [int]$TimeoutSeconds = 45
            )
            return [pscustomobject][ordered]@{ Success=$false; Engine='Fixture'; Path=''; Error='fixture converter failure' }
        }
        try {
            Export-ToolEnterpriseFleetReport -DestinationDirectory $exportRoot -Formats Pdf -StaleAfterHours 24 | Out-Null
        } catch {
            $pdfFailureObserved = ([string]$_.Exception.Message -like '*fixture converter failure*')
        }
    } finally {
        Set-Item -LiteralPath Function:\Convert-ToolHtmlToPdf -Value $originalPdfConverter
    }
    Assert-EnterpriseGovernance $pdfFailureObserved "A PDF-only fleet export did not fail when the PDF converter failed."
    $publishedDirectoriesAfterPdfFailure = @(Get-ChildItem -LiteralPath $exportRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object Name)
    Assert-EnterpriseGovernance (@(Compare-Object $publishedDirectoriesBeforePdfFailure $publishedDirectoriesAfterPdfFailure).Count -eq 0) "A failed PDF-only fleet export published a partial directory."
    Assert-EnterpriseGovernance (@(Get-ChildItem -LiteralPath $exportRoot -Directory -Filter "*.staging" -Force -ErrorAction SilentlyContinue).Count -eq 0) "A failed PDF-only fleet export left a staging directory."

    New-Item -ItemType Directory -Path $summaryRoot -Force | Out-Null
    $requiredVmTests = @(
        'VERIFY-FOUNDATION.ps1',
        'VERIFY-COMPATIBILITY.ps1',
        'VERIFY-REPORT-SCHEMA.ps1',
        'VERIFY-DASHBOARD.ps1',
        'VERIFY-OFFLINE-I18N.ps1',
        'VERIFY-LOCALIZATION-COVERAGE.ps1',
        'VERIFY-PERFORMANCE.ps1',
        'VERIFY-CATALOG-PLUGIN-TRUST-V5.ps1',
        'VERIFY-ENTERPRISE.ps1',
        'VERIFY-ENTERPRISE-GOVERNANCE.ps1',
        'VERIFY-NO-SIGNING-SECRETS.ps1'
    )
    $platformFixtures = @(
        [pscustomobject]@{ Platform='win10-22h2'; DisplayVersion='22H2'; Build='19045' },
        [pscustomobject]@{ Platform='win11-previous'; DisplayVersion='24H2'; Build='26100' },
        [pscustomobject]@{ Platform='win11-current'; DisplayVersion='25H2'; Build='26200' }
    )
    $fixtureCommit = 'a' * 40
    foreach ($platformFixture in $platformFixtures) {
        $vmResult = [pscustomobject][ordered]@{
            SchemaVersion='1.0'
            Platform=[string]$platformFixture.Platform
            Status='Passed'
            OsCaption='Windows fixture'
            OsBuild=[string]$platformFixture.Build
            OsUbr=1234
            OsDisplayVersion=[string]$platformFixture.DisplayVersion
            ExpectedOsBuild=[string]$platformFixture.Build
            ExpectedOsDisplayVersion=[string]$platformFixture.DisplayVersion
            OsIdentityVerified=$true
            PowerShell='5.1'
            Commit=$fixtureCommit
            CompletedAtUtc=[DateTime]::UtcNow.ToString('o')
            Tests=@($requiredVmTests | ForEach-Object { [pscustomobject][ordered]@{ Name=$_; ExitCode=0; Status='Passed' } })
            OutputTail='PRIVATE-FIXTURE-OUTPUT-MUST-NOT-BE-PUBLISHED'
        }
        [IO.File]::WriteAllText((Join-Path $summaryRoot ([string]$platformFixture.Platform + ".vm-result.json")), ($vmResult | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    }
    $expectedVmPlatforms = @('win10-22h2','win11-previous','win11-current')
    $summaryResult = & (Join-Path $SourceDirectory "New-ClientVmTestSummary.ps1") -ResultsDirectory $summaryRoot -ExpectedPlatforms $expectedVmPlatforms
    Assert-EnterpriseGovernance ([string]$summaryResult.Status -eq "Passed" -and $summaryResult.PassedCount -eq 3 -and $summaryResult.MissingCount -eq 0) "VM summary did not aggregate all strict fixture results."
    Assert-EnterpriseGovernance (Test-Path -LiteralPath $summaryResult.JsonPath -PathType Leaf) "VM JSON summary is missing."
    Assert-EnterpriseGovernance ((Get-Content -LiteralPath $summaryResult.MarkdownPath -Raw -Encoding UTF8) -match 'win10-22h2') "VM Markdown summary is missing a platform."
    $summaryJsonText = Get-Content -LiteralPath $summaryResult.JsonPath -Raw -Encoding UTF8
    $summaryJson = $summaryJsonText | ConvertFrom-Json
    Assert-EnterpriseGovernance ([string]$summaryJson.SourceCommit -eq $fixtureCommit -and @($summaryJson.Results).Count -eq 3) "VM summary did not preserve a single verified source commit and all platforms."
    Assert-EnterpriseGovernance ($summaryJsonText -notmatch 'OutputTail|PRIVATE-FIXTURE-OUTPUT') "Public VM JSON summary leaked private verifier output."
    foreach ($summaryRow in @($summaryJson.Results)) {
        Assert-EnterpriseGovernance ([bool]$summaryRow.OsIdentityVerified -and @($summaryRow.Tests).Count -eq $requiredVmTests.Count) "VM summary contains an unverified OS identity or an incomplete test set."
    }

    $mismatchPath = Join-Path $summaryRoot 'win11-current.vm-result.json'
    $mismatchOriginal = Get-Content -LiteralPath $mismatchPath -Raw -Encoding UTF8
    $osMismatchRejected = $false
    try {
        $mismatchRecord = $mismatchOriginal | ConvertFrom-Json
        $mismatchRecord.OsBuild = '99999'
        [IO.File]::WriteAllText($mismatchPath, ($mismatchRecord | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        try {
            & (Join-Path $SourceDirectory "New-ClientVmTestSummary.ps1") -ResultsDirectory $summaryRoot -ExpectedPlatforms $expectedVmPlatforms | Out-Null
        } catch {
            $osMismatchRejected = ([string]$_.Exception.Message -like '*status is inconsistent with OS identity*')
        }
    } finally {
        [IO.File]::WriteAllText($mismatchPath, $mismatchOriginal, (New-Object Text.UTF8Encoding($false)))
    }
    Assert-EnterpriseGovernance $osMismatchRejected "VM summary accepted a runner whose Windows build did not match its platform policy."

    $booleanTypeRejected = $false
    try {
        $typeMismatchRecord = $mismatchOriginal | ConvertFrom-Json
        $typeMismatchRecord.OsIdentityVerified = 'true'
        [IO.File]::WriteAllText($mismatchPath, ($typeMismatchRecord | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        try {
            & (Join-Path $SourceDirectory "New-ClientVmTestSummary.ps1") -ResultsDirectory $summaryRoot -ExpectedPlatforms $expectedVmPlatforms | Out-Null
        } catch {
            $booleanTypeRejected = ([string]$_.Exception.Message -like '*status is inconsistent with OS identity*')
        }
    } finally {
        [IO.File]::WriteAllText($mismatchPath, $mismatchOriginal, (New-Object Text.UTF8Encoding($false)))
    }
    Assert-EnterpriseGovernance $booleanTypeRejected "VM summary accepted a string in place of the OS identity verification boolean."

    $deploymentPath = Join-Path $SourceDirectory "Manage-ToolEnterpriseDeployment.ps1"
    $deploymentText = Get-Content -LiteralPath $deploymentPath -Raw -Encoding UTF8
    Assert-EnterpriseGovernance ($deploymentText -match 'ValidateSet\("Install",\s*"Detect",\s*"Repair",\s*"Uninstall"\)' -and
        $deploymentText -match 'ContainsSecrets\s*=\s*\$false' -and
        $deploymentText -match 'ExpectedSourceManifestSha256' -and
        $deploymentText -match 'AllowUnverifiedDevelopmentSource' -and
        $deploymentText -match 'PinnedReleaseManifest' -and
        $deploymentText -match 'Assert-ManagedDeploymentNoReparseAncestor' -and
        $deploymentText -match '\$cursor\s+-is\s+\[IO\.FileInfo\]' -and
        $deploymentText -match '\$cursor\s+-is\s+\[IO\.DirectoryInfo\]' -and
        $deploymentText -match 'function\s+Test-ManagedDeploymentMatchesSource' -and
        $deploymentText -match 'DesiredSourceManifestMismatch') "MDM deployment helper is missing idempotent actions, desired-source freshness, pinned source trust, reparse protection, or no-secret metadata."
    $embeddedSecretPattern = '(?i)(password|pairingcode)\s*='
    Assert-EnterpriseGovernance ($deploymentText -notmatch $embeddedSecretPattern) "MDM deployment helper appears to embed a secret."

    $deploymentTokens = $null
    $deploymentParseErrors = $null
    $deploymentAst = [Management.Automation.Language.Parser]::ParseFile($deploymentPath, [ref]$deploymentTokens, [ref]$deploymentParseErrors)
    Assert-EnterpriseGovernance (@($deploymentParseErrors).Count -eq 0) "MDM deployment helper cannot be parsed for the reparse-ancestor regression."
    $reparseFunctionAst = @($deploymentAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Assert-ManagedDeploymentNoReparseAncestor'
    }, $true) | Select-Object -First 1)
    Assert-EnterpriseGovernance ($reparseFunctionAst.Count -eq 1) "MDM deployment helper is missing its reparse-ancestor function definition."
    try {
        . ([scriptblock]::Create($reparseFunctionAst[0].Extent.Text))
        Assert-ManagedDeploymentNoReparseAncestor -Path $deploymentPath
        Assert-ManagedDeploymentNoReparseAncestor -Path $SourceDirectory
        Assert-ManagedDeploymentNoReparseAncestor -Path (Join-Path $SourceDirectory ("missing-mdm-target-" + [Guid]::NewGuid().ToString("N")))
    } finally {
        Remove-Item -LiteralPath Function:\Assert-ManagedDeploymentNoReparseAncestor -Force -ErrorAction SilentlyContinue
    }

    $workflowText = Get-Content -LiteralPath (Join-Path $SourceDirectory ".github\workflows\client-vm-matrix.yml") -Raw -Encoding UTF8
    foreach ($requiredWorkflowText in @(
        "workflow_dispatch", "schedule:", "ENABLE_CLIENT_VM_MATRIX", "client-vm-validation", "self-hosted",
        "win10-22h2", "win11-previous", "win11-current", "expected_display_version: 22H2", "expected_build: '19045'",
        "expected_display_version: 24H2", "expected_build: '26100'", "expected_display_version: 25H2", "expected_build: '26200'", "VERIFY-LOCALIZATION-COVERAGE.ps1",
        "VERIFY-PERFORMANCE.ps1", "VERIFY-CATALOG-PLUGIN-TRUST-V5.ps1", "VERIFY-NO-SIGNING-SECRETS.ps1",
        "TOOL_VM_EXPECTED_DISPLAY_VERSION", "TOOL_VM_EXPECTED_BUILD", "OsIdentityVerified", "Enforce complete passing matrix"
    )) {
        Assert-EnterpriseGovernance ($workflowText -like "*$requiredWorkflowText*") "Protected VM workflow is missing: $requiredWorkflowText"
    }
    Assert-EnterpriseGovernance ($workflowText -like "*Path='.\VERIFY-FOUNDATION.ps1'; Arguments=@('-SourceDirectory','.', '-ExpectedArchitecture','x64')*" ) "Protected VM workflow does not provide the foundation verifier's required architecture argument."
    Assert-EnterpriseGovernance ($workflowText -like "*Path='.\VERIFY-CATALOG-PLUGIN-TRUST-V5.ps1'; Arguments=@()*") "Protected VM workflow incorrectly supplies parameters to the catalog/plugin verifier."
    foreach ($sourceDirectoryVerifier in @(
        'VERIFY-COMPATIBILITY.ps1','VERIFY-REPORT-SCHEMA.ps1','VERIFY-DASHBOARD.ps1','VERIFY-OFFLINE-I18N.ps1',
        'VERIFY-LOCALIZATION-COVERAGE.ps1','VERIFY-PERFORMANCE.ps1','VERIFY-ENTERPRISE.ps1',
        'VERIFY-ENTERPRISE-GOVERNANCE.ps1','VERIFY-NO-SIGNING-SECRETS.ps1'
    )) {
        $expectedInvocation = "Path='.\$sourceDirectoryVerifier'; Arguments=@('-SourceDirectory','.')"
        Assert-EnterpriseGovernance ($workflowText -like "*$expectedInvocation*") "Protected VM workflow has incorrect arguments for: $sourceDirectoryVerifier"
    }
    Assert-EnterpriseGovernance ($workflowText -like '*$testArguments = @($test.Arguments)*' -and $workflowText -like '*@testArguments 2>&1*') "Protected VM workflow does not safely splat each verifier's own arguments."
    Assert-EnterpriseGovernance ($workflowText -match '\$actualDisplayVersion\s*-eq\s*\[string\]\$env:TOOL_VM_EXPECTED_DISPLAY_VERSION' -and
        $workflowText -match '\$actualBuild\s*-eq\s*\[string\]\$env:TOOL_VM_EXPECTED_BUILD' -and
        $workflowText -match 'if\s*\(-not\s+\$osIdentityVerified\)\s*\{\s*\$overall\s*=\s*''Failed''') "Protected VM workflow does not fail closed on an unexpected Windows version/build."
    Assert-EnterpriseGovernance ($workflowText -notmatch 'OutputTail') "Protected VM workflow exposes verifier output in the public result record."
    Assert-EnterpriseGovernance ($workflowText -notmatch '\$output\s*\|\s*ForEach-Object' -and
        $workflowText -like '*exit={1}; status={2}*') "Protected VM workflow writes raw verifier output instead of an allowlisted status tuple."
    foreach ($timeout in @('timeout-minutes: 10','timeout-minutes: 90','timeout-minutes: 15')) {
        Assert-EnterpriseGovernance ($workflowText -like "*$timeout*") "Protected VM workflow is missing a bounded job timeout: $timeout"
    }
    $expectedActionPins = [ordered]@{
        "actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0" = 3
        "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2" = 2
        "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093 # v4.3.0" = 1
    }
    foreach ($pin in $expectedActionPins.Keys) {
        $count = [regex]::Matches($workflowText, [regex]::Escape([string]$pin)).Count
        Assert-EnterpriseGovernance ($count -eq [int]$expectedActionPins[$pin]) "Protected VM workflow action pin is missing or has an unexpected count: $pin"
    }
    Assert-EnterpriseGovernance ($workflowText -notmatch 'actions/(checkout|upload-artifact|download-artifact)@v\d+') "Protected VM workflow contains a mutable major-version action reference."
    $signingPolicy = Get-Content -LiteralPath (Join-Path $SourceDirectory "CODE-SIGNING-POLICY-v1.md") -Raw -Encoding UTF8
    Assert-EnterpriseGovernance ($signingPolicy -match '(?is)EV.{1,300}SmartScreen') "Code-signing policy is missing the EV/SmartScreen limitation."

    Write-Host "VERIFY-ENTERPRISE-GOVERNANCE: PASS" -ForegroundColor Green
    Write-Host "  Redaction, freshness/filtering, CSV safety, atomic bundle, MDM/CLI and VM evidence passed."
} catch {
    throw "VERIFY-ENTERPRISE-GOVERNANCE: FAIL - $($_.Exception.Message)`n$($_.ScriptStackTrace)"
} finally {
    $env:TOOL_ENTERPRISE_ROOT = $previousRoot
    $env:TOOL_ENTERPRISE_SKIP_ACL = $previousSkipAcl
    foreach ($target in @($testRoot,$exportRoot,$summaryRoot)) {
        try {
            $full = [IO.Path]::GetFullPath($target)
            if ($full.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full)) {
                Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}
