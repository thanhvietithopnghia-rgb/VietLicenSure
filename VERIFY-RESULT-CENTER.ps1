param(
    [string]$SourceDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath($SourceDirectory)
$helperPath = Join-Path $sourceRoot 'Tool-ResultCenter.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'Missing Tool-ResultCenter.ps1.' }
. $helperPath

function Assert-ResultCenterTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Write-TestJson {
    param([string]$Path, [object]$Value)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ToolResultCenter-Test-' + [Guid]::NewGuid().ToString('N'))
$reportRoot = Join-Path $testRoot 'reports'
$dataRoot = Join-Path $testRoot 'data'
$backupRoot = Join-Path $dataRoot 'backups'
$backupDirectory = Join-Path $backupRoot 'backup_pre_cleanup_test'
$extractRoot = Join-Path $testRoot 'extract'
New-Item -ItemType Directory -Path $reportRoot,$backupDirectory,$extractRoot -Force | Out-Null

try {
    $previousReport = [pscustomobject][ordered]@{
        SchemaVersion='1.5'; ReportSchemaVersion='1.5'; ReportKind='InventoryAndLicense'; ToolVersion='5.0'
        ToolName='Tool Kiem Tra'; CreatedAt='2026-08-31T10:00:00+07:00'; Mode='All'; Redacted=$true
        WindowsConclusionCode='ActivatedEntitlementUnverified'; WindowsConclusion='Activated; entitlement not verified.'
        OfficeConclusionCode='NotDetected'; OfficeConclusion='Office not detected.'
        DetailedInventory=[pscustomobject][ordered]@{
            ActivatorFindings=@()
            Software=[pscustomobject][ordered]@{
                ThirdPartyApplications=@(
                    [pscustomobject][ordered]@{ Software='App A'; Version='1.0'; Publisher='Vendor A'; AssessmentCode='Unverified'; LicenseModel='Paid'; LicenseRequiresEntitlement=$true; NeedsReview=$true; IsSystemComponent=$false; CleanupFinding=$false; RemediationEvidenceCount=0; TechnicalEvidence=@() },
                    [pscustomobject][ordered]@{ Software='App B'; Version='2.0'; Publisher='Vendor B'; AssessmentCode='Suspicious'; LicenseModel='Paid'; LicenseRequiresEntitlement=$true; NeedsReview=$true; IsSystemComponent=$false; CleanupFinding=$true; RemediationEvidenceCount=1; TechnicalEvidence=@([pscustomobject]@{Code='KnownArtifact'}) }
                )
            }
        }
    }
    $latestReport = [pscustomobject][ordered]@{
        SchemaVersion='1.5'; ReportSchemaVersion='1.5'; ReportKind='InventoryAndLicense'; ToolVersion='5.0'
        ToolName='Tool Kiem Tra'; CreatedAt='2026-09-01T10:00:00+07:00'; Mode='All'; Redacted=$true
        WindowsConclusionCode='NotLicensed'; WindowsConclusion='Windows is not licensed.'
        OfficeConclusionCode='NotDetected'; OfficeConclusion='Office not detected.'
        DetailedInventory=[pscustomobject][ordered]@{
            ActivatorFindings=@()
            Software=[pscustomobject][ordered]@{
                ThirdPartyApplications=@(
                    [pscustomobject][ordered]@{ Software='App A'; Version='1.0'; Publisher='Vendor A'; AssessmentCode='Unverified'; LicenseModel='Paid'; LicenseRequiresEntitlement=$true; NeedsReview=$true; IsSystemComponent=$false; CleanupFinding=$false; RemediationEvidenceCount=0; TechnicalEvidence=@() },
                    [pscustomobject][ordered]@{ Software='App C'; Version='3.0'; Publisher='Vendor C'; AssessmentCode='IntegrityCompromised'; LicenseModel='Paid'; LicenseRequiresEntitlement=$true; NeedsReview=$true; IsSystemComponent=$false; CleanupFinding=$true; RemediationEvidenceCount=1; TechnicalEvidence=@([pscustomobject]@{Code='SignatureHashMismatch'}) }
                )
            }
        }
    }
    Write-TestJson -Path (Join-Path $reportRoot 'report-previous.json') -Value $previousReport
    Write-TestJson -Path (Join-Path $reportRoot 'report-latest.json') -Value $latestReport

    $state = Get-ToolResultCenterState -ReportRoot $reportRoot -MaximumReports 10
    Assert-ResultCenterTest ([bool]$state.HasReport) 'Latest report was not discovered.'
    Assert-ResultCenterTest ([bool]$state.HasBaseline) 'Same-mode baseline was not discovered.'
    Assert-ResultCenterTest (@($state.Items | Where-Object ComparisonStatus -eq 'New').Count -ge 2) 'New comparison state is missing.'
    Assert-ResultCenterTest (@($state.Items | Where-Object ComparisonStatus -eq 'Resolved').Count -ge 2) 'Resolved comparison state is missing.'
    Assert-ResultCenterTest (@($state.Items | Where-Object ComparisonStatus -eq 'Unchanged').Count -ge 1) 'Unchanged comparison state is missing.'
    $filtered = @(Select-ToolResultCenterItems -Items $state.Items -SearchText 'App C' -Severity High -ComparisonStatus New)
    Assert-ResultCenterTest ($filtered.Count -eq 1 -and [string]$filtered[0].Name -eq 'App C') 'Search/severity/comparison filtering failed.'
    $literalWildcardSearch = @(Select-ToolResultCenterItems -Items $state.Items -SearchText '[')
    Assert-ResultCenterTest ($literalWildcardSearch.Count -eq 0) 'Search text was interpreted as a wildcard pattern.'
    Assert-ResultCenterTest ([string]$filtered[0].ActionCode -eq 'OpenSoftwareRemediation') 'Strong-evidence software action was not routed to controlled remediation.'
    $unverified = @($state.Items | Where-Object { [string]$_.Name -eq 'App A' -and [string]$_.ComparisonStatus -eq 'Unchanged' } | Select-Object -First 1)
    Assert-ResultCenterTest ($unverified.Count -eq 1 -and [string]$unverified[0].ActionCode -eq 'ReviewSoftware') 'Unverified software was incorrectly routed to remediation.'

    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $backupDataPath = Join-Path $backupDirectory 'data.bin'
    [IO.File]::WriteAllBytes($backupDataPath, [Text.Encoding]::UTF8.GetBytes('verified backup data'))
    $manifestPath = Join-Path $backupDirectory 'RESTORE-MANIFEST.json'
    $hmacPath = Join-Path $backupDirectory 'RESTORE-MANIFEST.hmac'
    $authPath = Join-Path $backupDirectory 'RESTORE-AUTH.bin'
    $manifest = [pscustomobject][ordered]@{
        SchemaVersion='2.0'; ToolVersion='5.0'; BackupMode='PreCleanup'; BackupScope='Windows'
        ComputerName=$env:COMPUTERNAME; MachineBinding=(Get-ToolResultMachineBinding); CreatedAt=[DateTime]::Now.ToString('o')
        RestoreScriptSha256=''; RuntimeHelperSha256=''; SafetyPolicySha256=''; LocalizationHelperSha256=''; ViCatalogSha256=''; EnCatalogSha256=''
        Items=@([pscustomobject][ordered]@{ Type='File'; Name='Fixture'; OriginalPath=''; BackupPath='data.bin'; BackupSha256=(Get-ToolResultFileSha256 $backupDataPath); Kind='WindowsFixture' })
    }
    Write-TestJson -Path $manifestPath -Value $manifest
    $hmacKey = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($hmacKey) } finally { $rng.Dispose() }
    $protectedKey = [Security.Cryptography.ProtectedData]::Protect($hmacKey, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    [IO.File]::WriteAllBytes($authPath, $protectedKey)
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$hmacKey)
    try { $signature = ([BitConverter]::ToString($hmac.ComputeHash([IO.File]::ReadAllBytes($manifestPath))) -replace '-', '').ToUpperInvariant() }
    finally { $hmac.Dispose(); [Array]::Clear($hmacKey, 0, $hmacKey.Length) }
    [IO.File]::WriteAllText($hmacPath, $signature, [Text.Encoding]::ASCII)

    $backups = @(Get-ToolBackupCenterItems -DataRoot $dataRoot -MaximumBackups 10)
    Assert-ResultCenterTest ($backups.Count -eq 1 -and [string]$backups[0].Scope -eq 'Windows') 'Backup Center listing failed.'
    $validBackup = Test-ToolBackupCenterItemIntegrity -BackupDirectory $backupDirectory -DataRoot $dataRoot
    Assert-ResultCenterTest ([bool]$validBackup.Valid) ('Valid backup was rejected: ' + ($validBackup.Errors -join '; '))
    [IO.File]::AppendAllText($backupDataPath, 'tampered')
    $tamperedBackup = Test-ToolBackupCenterItemIntegrity -BackupDirectory $backupDirectory -DataRoot $dataRoot
    Assert-ResultCenterTest (-not [bool]$tamperedBackup.Valid) 'Tampered backup was accepted.'

    $logPath = Join-Path $testRoot 'tool.jsonl'
    $sensitiveGuid = '11111111-2222-3333-4444-555555555555'
    $logRecord = [pscustomobject][ordered]@{
        SchemaVersion='1.0'; TimestampUtc=[DateTime]::UtcNow.ToString('o'); ToolVersion='5.0'; Component='GUI'
        CorrelationId='secret-correlation'; ModuleId='report.all'; ModuleInvocationId='secret-invocation'; ProcessId=123; ProcessArchitecture='x64'
        Level='ERROR'; Event='Fixture.Error'; Message=('Failure at C:\Users\' + $env:USERNAME + '\Secret\file.txt from 192.168.1.25 and 2001:db8::25, SID S-1-5-21-123456789-234567890-345678901-1001, user@example.com ' + $sensitiveGuid)
        Data=[pscustomobject]@{ Secret='must-not-be-exported'; ProductKey='AAAAA-BBBBB-CCCCC-DDDDD-EEEEE' }
    }
    [IO.File]::WriteAllText($logPath, (($logRecord | ConvertTo-Json -Depth 6 -Compress) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
    $bundlePath = Join-Path $testRoot 'support.zip'
    $bundle = New-ToolSupportBundle -ReportRoot $reportRoot -DestinationPath $bundlePath -LogPath $logPath
    Assert-ResultCenterTest ([bool]$bundle.Success -and (Test-Path -LiteralPath $bundlePath -PathType Leaf)) 'Support bundle was not created.'
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    [IO.Compression.ZipFile]::ExtractToDirectory($bundlePath, $extractRoot)
    $entryNames = @(Get-ChildItem -LiteralPath $extractRoot -File | Select-Object -ExpandProperty Name)
    foreach ($requiredEntry in @('REPORT.json','LOG-SAFE.jsonl','BUILD-IDENTITY.txt','README.txt','SUPPORT-MANIFEST.json')) {
        Assert-ResultCenterTest ($entryNames -contains $requiredEntry) ("Support bundle is missing $requiredEntry.")
    }
    $safeLog = [IO.File]::ReadAllText((Join-Path $extractRoot 'LOG-SAFE.jsonl'), [Text.Encoding]::UTF8)
    foreach ($forbidden in @('secret-correlation','secret-invocation','must-not-be-exported','AAAAA-BBBBB-CCCCC-DDDDD-EEEEE','192.168.1.25','2001:db8::25','S-1-5-21-123456789-234567890-345678901-1001','user@example.com',$sensitiveGuid,('C:\Users\' + $env:USERNAME))) {
        Assert-ResultCenterTest (-not $safeLog.Contains($forbidden)) ("Sanitized support log leaked: $forbidden")
    }
    $safeLogObject = $safeLog.Trim() | ConvertFrom-Json
    Assert-ResultCenterTest ($null -eq $safeLogObject.PSObject.Properties['Data']) 'Raw log Data field was exported.'
    Assert-ResultCenterTest ($null -eq $safeLogObject.PSObject.Properties['CorrelationId']) 'CorrelationId was exported.'

    Write-Host 'RESULT CENTER: PASS' -ForegroundColor Green
    Write-Host '  Action ordering/search/filter: PASS'
    Write-Host '  Same-mode previous scan comparison: PASS'
    Write-Host '  Backup HMAC/SHA-256 validation and tamper rejection: PASS'
    Write-Host '  Privacy-safe support ZIP: PASS'
    exit 0
} catch {
    Write-Host ('RESULT CENTER: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
