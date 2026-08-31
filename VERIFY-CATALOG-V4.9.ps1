[CmdletBinding()]
param(
    [string]$SourceDirectory = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$failures = New-Object System.Collections.Generic.List[string]

function Add-CatalogVerificationFailure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:failures.Add($Message)
}

function Assert-CatalogVerification {
    param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    if (-not $Condition) { Add-CatalogVerificationFailure -Message $Message }
}

function Copy-CatalogFixture {
    param([Parameter(Mandatory = $true)][object]$Catalog)
    return ($Catalog | ConvertTo-Json -Depth 64 | ConvertFrom-Json)
}

$root = [IO.Path]::GetFullPath($SourceDirectory)
$inventoryModulePath = Join-Path $root 'Tool-SoftwareInventory.ps1'
$catalogPath = Join-Path $root 'software-license-catalog-v1.0.json'
if (-not (Test-Path -LiteralPath $inventoryModulePath -PathType Leaf)) { throw "Missing inventory module: $inventoryModulePath" }
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { throw "Missing catalog: $catalogPath" }

. $inventoryModulePath
$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-CatalogVerification -Condition (Test-ToolSoftwareCatalogObject -Catalog $catalog) -Message 'The bundled v4.9 catalog failed strict schema validation.'
Assert-CatalogVerification -Condition ([string]$catalog.CatalogVersion -eq '1.6.3.0') -Message 'CatalogVersion must be 1.6.3.0.'
Assert-CatalogVerification -Condition ([string]$catalog.GeneratedAtUtc -eq '2026-08-31T06:05:00Z') -Message 'GeneratedAtUtc must use the current 2026-08-31 maintenance timestamp.'
$catalogIds = @($catalog.Products | ForEach-Object { [string]$_.Id })
Assert-CatalogVerification -Condition ($catalogIds.Count -ge 94) -Message 'The v5.0 catalog must contain at least 94 conservative product rules.'
Assert-CatalogVerification -Condition (@($catalogIds | Select-Object -Unique).Count -eq $catalogIds.Count) -Message 'Catalog product IDs must be unique.'
foreach ($requiredId in @('techsmith-snagit','bandicam-commercial','beyond-compare-commercial','total-commander-commercial',
    'acronis-home-commercial','macrium-reflect-commercial','bluebeam-revu-commercial','capture-one-pro','dxo-photolab-commercial',
    'cyberlink-creative-commercial','lumion-commercial','bricscad-commercial','zwcad-commercial','rhinoceros-3d-commercial',
    'windows-app-platform-component')) {
    Assert-CatalogVerification -Condition ($catalogIds -contains $requiredId) -Message "Missing conservative v4.9 product rule: $requiredId"
}

$rootUnknown = Copy-CatalogFixture -Catalog $catalog
$rootUnknown | Add-Member -NotePropertyName FuturePayload -NotePropertyValue 'not allowed'
Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $rootUnknown)) -Message 'Unknown root fields are not rejected.'

$deepUnknown = Copy-CatalogFixture -Catalog $catalog
$deepUnknown.DeepScan | Add-Member -NotePropertyName FutureRule -NotePropertyValue @('x')
Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $deepUnknown)) -Message 'Unknown DeepScan fields are not rejected.'

$productUnknown = Copy-CatalogFixture -Catalog $catalog
$productUnknown.Products[0] | Add-Member -NotePropertyName FutureRule -NotePropertyValue 'x'
Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $productUnknown)) -Message 'Unknown product fields are not rejected.'

foreach ($dangerousField in @('Command','Script','PowerShell','Executable','Arguments','Action','RemediationAction')) {
    $fixture = Copy-CatalogFixture -Catalog $catalog
    $fixture.Products[0] | Add-Member -NotePropertyName $dangerousField -NotePropertyValue 'calc.exe'
    Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $fixture)) -Message "Executable field was accepted: $dangerousField"
}

$badDetectionProfile = Copy-CatalogFixture -Catalog $catalog
$badDetectionProfile.Products[0].DetectionProfileId = 'Downloaded.PowerShellProfile'
Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $badDetectionProfile)) -Message 'An uncompiled DetectionProfileId was accepted.'

$badRemediationProfile = Copy-CatalogFixture -Catalog $catalog
$badRemediationProfile.Products[0] | Add-Member -NotePropertyName RemediationProfileId -NotePropertyValue 'Vendor.RunCommand'
Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $badRemediationProfile)) -Message 'An uncompiled RemediationProfileId was accepted.'

$badLicenseProfile = Copy-CatalogFixture -Catalog $catalog
$badLicenseProfile.Products[0] | Add-Member -NotePropertyName LicenseStateProfileId -NotePropertyValue 'Remote.ScriptProbe'
Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $badLicenseProfile)) -Message 'An uncompiled LicenseStateProfileId was accepted.'

$typedFixture = Copy-CatalogFixture -Catalog $catalog
$typedProduct = $typedFixture.Products[0]
$typedProduct | Add-Member -NotePropertyName ProductCodes -NotePropertyValue @('{12345678-1234-1234-1234-1234567890AB}')
$typedProduct | Add-Member -NotePropertyName RegistryEvidence -NotePropertyValue @([pscustomobject][ordered]@{
    Hive='HKLM'; View='Registry64'; SubKey='SOFTWARE\Vendor\Product'; ValueName='InstallId'; MatchType='Exists'
})
$typedProduct | Add-Member -NotePropertyName ServiceEvidence -NotePropertyValue @([pscustomobject][ordered]@{
    ServiceName='VendorLicenseService'; ExpectedState='Any'
})
$typedProduct | Add-Member -NotePropertyName TaskEvidence -NotePropertyValue @([pscustomobject][ordered]@{
    TaskPath='\Vendor\'; TaskName='License maintenance'
})
Assert-CatalogVerification -Condition (Test-ToolSoftwareCatalogObject -Catalog $typedFixture) -Message 'A bounded declarative ProductCode/Registry/Service/Task fixture was rejected.'

$badProductCode = Copy-CatalogFixture -Catalog $typedFixture
$badProductCode.Products[0].ProductCodes = @('not-a-product-code')
Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $badProductCode)) -Message 'An invalid ProductCode was accepted.'

$badRegistry = Copy-CatalogFixture -Catalog $typedFixture
$badRegistry.Products[0].RegistryEvidence[0].SubKey = 'SOFTWARE\..\Outside'
Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $badRegistry)) -Message 'A registry traversal rule was accepted.'

$badService = Copy-CatalogFixture -Catalog $typedFixture
$badService.Products[0].ServiceEvidence[0].ServiceName = 'service & command'
Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $badService)) -Message 'An unsafe service identity was accepted.'

$badTask = Copy-CatalogFixture -Catalog $typedFixture
$badTask.Products[0].TaskEvidence[0].TaskPath = '\Vendor\..\Outside\'
Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogObject -Catalog $badTask)) -Message 'A task traversal rule was accepted.'

$baselineFixture = [pscustomobject][ordered]@{
    CatalogVersion='1.6.3.0'; CatalogSha256=('A' * 64); Products=@($catalog.Products)
}
Assert-CatalogVerification -Condition ((Get-ToolSoftwareCatalogUpdateDisposition `
    -CandidateVersion ([version]'1.6.1.0') -CandidateSha256 ('B' * 64) -TrustedBaseline $baselineFixture) -eq 'LocalNewer') `
    -Message 'An older signed online catalog was not retained as a no-downgrade LocalNewer result.'
Assert-CatalogVerification -Condition ((Get-ToolSoftwareCatalogUpdateDisposition `
    -CandidateVersion ([version]'1.6.3.0') -CandidateSha256 ('A' * 64) -TrustedBaseline $baselineFixture) -eq 'AlreadyCurrent') `
    -Message 'An identical online catalog was not recognized as AlreadyCurrent.'
Assert-CatalogVerification -Condition ((Get-ToolSoftwareCatalogUpdateDisposition `
    -CandidateVersion ([version]'1.6.4.0') -CandidateSha256 ('B' * 64) -TrustedBaseline $baselineFixture) -eq 'Update') `
    -Message 'A newer online catalog was not accepted for update.'
$equalVersionConflictBlocked = $false
try {
    [void](Get-ToolSoftwareCatalogUpdateDisposition `
        -CandidateVersion ([version]'1.6.3.0') -CandidateSha256 ('B' * 64) -TrustedBaseline $baselineFixture)
} catch { $equalVersionConflictBlocked = ([string]$_.Exception.Message -match 'different content') }
Assert-CatalogVerification -Condition $equalVersionConflictBlocked -Message 'Equal-version different catalog content was not blocked.'

$watermarkRoot = Join-Path ([IO.Path]::GetTempPath()) ('Tool-Catalog-V49-' + [guid]::NewGuid().ToString('N'))
$previousOverride = [string]$script:ToolSoftwareCatalogDataRootOverride
try {
    [void][IO.Directory]::CreateDirectory($watermarkRoot)
    $script:ToolSoftwareCatalogDataRootOverride = $watermarkRoot
    $acceptedSha = ('A' * 64)
    $differentSha = ('B' * 64)
    [void](Set-ToolSoftwareCatalogWatermark -CatalogVersion ([version]'9.9.9.9') -CatalogSha256 $acceptedSha)
    $storedWatermark = Get-ToolSoftwareCatalogWatermark
    Assert-CatalogVerification -Condition ([string]$storedWatermark.CatalogVersion -eq '9.9.9.9' -and [string]$storedWatermark.CatalogSha256 -eq $acceptedSha) -Message 'The DPAPI last-seen watermark did not persist.'

    $cachePath = Get-ToolSoftwareCatalogCachePath
    $cacheDirectory = Split-Path -Parent $cachePath
    [void][IO.Directory]::CreateDirectory($cacheDirectory)
    [IO.File]::WriteAllText($cachePath, 'cache fixture')
    [IO.File]::WriteAllText((Get-ToolSoftwareCatalogCacheSignaturePath), 'signature fixture')
    Remove-Item -LiteralPath $cachePath -Force
    Remove-Item -LiteralPath (Get-ToolSoftwareCatalogCacheSignaturePath) -Force

    Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogAllowedByWatermark -CatalogVersion ([version]'9.9.9.8') -CatalogSha256 $differentSha)) -Message 'Rollback was accepted after cache deletion.'
    Assert-CatalogVerification -Condition (-not (Test-ToolSoftwareCatalogAllowedByWatermark -CatalogVersion ([version]'9.9.9.9') -CatalogSha256 $differentSha)) -Message 'Equal-version different content was accepted after cache deletion.'
    Assert-CatalogVerification -Condition (Test-ToolSoftwareCatalogAllowedByWatermark -CatalogVersion ([version]'9.9.9.9') -CatalogSha256 $acceptedSha) -Message 'The exact last-seen catalog was rejected.'
    Assert-CatalogVerification -Condition (Test-ToolSoftwareCatalogAllowedByWatermark -CatalogVersion ([version]'9.9.10.0') -CatalogSha256 $differentSha) -Message 'A newer catalog was rejected by the watermark.'
} catch {
    Add-CatalogVerificationFailure -Message ('Watermark verification could not run: ' + [string]$_.Exception.Message)
} finally {
    $script:ToolSoftwareCatalogDataRootOverride = $previousOverride
    if ((Test-Path -LiteralPath $watermarkRoot -PathType Container) -and [IO.Path]::GetFileName($watermarkRoot) -match '^Tool-Catalog-V49-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $watermarkRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ('VERIFY-CATALOG-V4.9: FAIL - ' + $failure) -ForegroundColor Red }
    exit 1
}

Write-Host ('VERIFY-CATALOG-V4.9: OK (strict fields + compiled profiles + declarative evidence + no-downgrade online handling + DPAPI anti-rollback + ' + $catalogIds.Count + ' products)') -ForegroundColor Green
exit 0
