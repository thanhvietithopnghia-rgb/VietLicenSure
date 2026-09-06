[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ClientVmSummaryPath,
    [Parameter(Mandatory=$true)][string]$IndependentSecurityReviewPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$ExpectedSourceCommit,
    [string]$ExpectedReleaseVersion='5.0.0.1'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

function Read-SafeJson([string]$Path,[int64]$Max,[string]$Label) {
    $full=[IO.Path]::GetFullPath($Path)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "$Label is missing."}
    $item=Get-Item -LiteralPath $full -Force
    if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne 0-or$item.Length-le 2-or$item.Length-gt$Max){throw "$Label file is unsafe."}
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $text=$utf8.GetString([IO.File]::ReadAllBytes($full))
    if($text.IndexOf([char]0)-ge 0-or$text[0]-eq[char]0xFEFF){throw "$Label encoding is invalid."}
    try{return($text|ConvertFrom-Json -ErrorAction Stop)}catch{throw "$Label JSON is invalid."}
}

$commit=$ExpectedSourceCommit.ToLowerInvariant()
$summaryFull=[IO.Path]::GetFullPath($ClientVmSummaryPath)
$summaryRoot=Split-Path -Parent $summaryFull
$summary=Read-SafeJson $summaryFull 262144 'VM summary'
if([string]$summary.SchemaVersion-cne'1.0'-or[string]$summary.Status-cne'Passed'){throw 'VM summary has not Passed.'}
if([int]$summary.ExpectedPlatformCount-ne 3-or[int]$summary.ResultCount-ne 3-or[int]$summary.PassedCount-ne 3-or[int]$summary.FailedCount-ne 0-or[int]$summary.MissingCount-ne 0){throw 'Public Stable requires 3/3 VM Passed, 0 Failed, 0 Missing.'}
if([string]$summary.SourceCommit-cne$commit){throw 'VM summary commit does not match provenance.'}
$platforms=@('win10-22h2','win11-previous','win11-current')
$platformPolicies=@{
    'win10-22h2'=@{DisplayVersion='22H2';Build='19045'}
    'win11-previous'=@{DisplayVersion='24H2';Build='26100'}
    'win11-current'=@{DisplayVersion='25H2';Build='26200'}
}
$tests=@('VERIFY-FOUNDATION.ps1','VERIFY-COMPATIBILITY.ps1','VERIFY-REPORT-SCHEMA.ps1','VERIFY-DASHBOARD.ps1','VERIFY-OFFLINE-I18N.ps1','VERIFY-LOCALIZATION-COVERAGE.ps1','VERIFY-PERFORMANCE.ps1','VERIFY-CATALOG-PLUGIN-TRUST-V5.ps1','VERIFY-ENTERPRISE.ps1','VERIFY-ENTERPRISE-GOVERNANCE.ps1','VERIFY-NO-SIGNING-SECRETS.ps1')
$generatorPath=Join-Path $PSScriptRoot 'New-ClientVmTestSummary.ps1'
if([string]$summary.Generator.Name-cne'New-ClientVmTestSummary.ps1'-or[string]$summary.Generator.Sha256-cne(Get-FileHash -LiteralPath $generatorPath -Algorithm SHA256).Hash){throw 'VM summary generator identity does not match this source snapshot.'}
foreach($name in $tests){
    $manifestTest=@($summary.TestManifest|Where-Object{[string]$_.Name-ceq$name})
    if($manifestTest.Count-ne 1-or[int]$manifestTest[0].ExpectedExitCode-ne 0-or[string]$manifestTest[0].ExpectedStatus-cne'Passed'){throw "VM test manifest is invalid: $name"}
}
foreach($platform in $platforms){
    $match=@($summary.Results|Where-Object{[string]$_.Platform-ceq$platform})
    if($match.Count-ne 1){throw "Missing unique VM result: $platform"}
    $result=$match[0]
    if([string]$result.Status-cne'Passed'-or-not[bool]$result.OsIdentityVerified-or[string]$result.Commit-cne$commit){throw "Invalid VM result: $platform"}
    $policy=$platformPolicies[$platform]
    $platformManifest=@($summary.PlatformManifest|Where-Object{[string]$_.Platform-ceq$platform})
    if($platformManifest.Count-ne 1-or[string]$platformManifest[0].ExpectedOsDisplayVersion-cne[string]$policy.DisplayVersion-or[string]$platformManifest[0].ExpectedOsBuild-cne[string]$policy.Build){throw "VM platform manifest is invalid: $platform"}
    $expectedFileName=$platform+'.vm-result.json'
    if([string]$result.ResultFileName-cne$expectedFileName-or[string]$result.ResultSha256-cnotmatch'^[A-F0-9]{64}$'-or[int64]$result.ResultBytes-le 2-or[int64]$result.ResultBytes-gt 1048576){throw "VM raw evidence metadata is invalid: $platform"}
    $rawPath=Join-Path $summaryRoot $expectedFileName
    $rawItem=Get-Item -LiteralPath $rawPath -Force -ErrorAction Stop
    if(($rawItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne 0-or[int64]$rawItem.Length-ne[int64]$result.ResultBytes-or(Get-FileHash -LiteralPath $rawPath -Algorithm SHA256).Hash-cne[string]$result.ResultSha256){throw "VM raw evidence hash or size mismatch: $platform"}
    $raw=Read-SafeJson $rawPath 1048576 "VM raw evidence $platform"
    if([string]$raw.SchemaVersion-cne'1.0'-or[string]$raw.Platform-cne$platform-or[string]$raw.Status-cne'Passed'-or$raw.OsIdentityVerified-isnot[bool]-or-not[bool]$raw.OsIdentityVerified-or[string]$raw.Commit-cne$commit){throw "VM raw evidence identity is invalid: $platform"}
    if([string]$raw.OsDisplayVersion-cne[string]$policy.DisplayVersion-or[string]$raw.OsBuild-cne[string]$policy.Build-or[string]$raw.ExpectedOsDisplayVersion-cne[string]$policy.DisplayVersion-or[string]$raw.ExpectedOsBuild-cne[string]$policy.Build-or[int]$raw.OsUbr-lt 0){throw "VM raw evidence OS identity is invalid: $platform"}
    foreach($name in $tests){
        $test=@($result.Tests|Where-Object{[string]$_.Name-ceq$name})
        if($test.Count-ne 1-or[string]$test[0].Status-cne'Passed'-or[int]$test[0].ExitCode-ne 0){throw "$platform lacks Passed test: $name"}
        $rawTest=@($raw.Tests|Where-Object{[string]$_.Name-ceq$name})
        if($rawTest.Count-ne 1-or[string]$rawTest[0].Status-cne'Passed'-or[int]$rawTest[0].ExitCode-ne 0){throw "$platform raw evidence lacks Passed test: $name"}
    }
}

$review=Read-SafeJson $IndependentSecurityReviewPath 65536 'Independent security review'
if([string]$review.SchemaVersion-cne'1.0'-or[string]$review.ProductId-cne'4B8D93E8-278A-4F9D-A39E-986B0322B65B'){throw 'Security review identity is invalid.'}
if([string]$review.ReleaseVersion-cne$ExpectedReleaseVersion-or[string]$review.SourceCommit-cne$commit-or[string]$review.ReviewStatus-cne'Passed'){throw 'Security review has not Passed for this source snapshot.'}
if([string]::IsNullOrWhiteSpace([string]$review.ReviewerOrganization)-or[string]::IsNullOrWhiteSpace([string]$review.ReviewerName)){throw 'Independent reviewer identity is missing.'}
if([int]$review.OpenCriticalFindings-ne 0-or[int]$review.OpenHighFindings-ne 0){throw 'Critical or High security findings remain open.'}
if([string]$review.ReportSha256-cnotmatch'^[A-F0-9]{64}$'){throw 'Security review report hash is invalid.'}
$scope=@('ThreatModel','PrivilegeBoundary','RemediationRollback','CatalogPluginTrust','UpdateTransport','TamperingDowngrade')
foreach($name in $scope){if(@($review.Scope)-cnotcontains$name){throw "Security review scope is missing: $name"}}
Write-Host 'Stable readiness evidence: Passed.' -ForegroundColor Green
exit 0
