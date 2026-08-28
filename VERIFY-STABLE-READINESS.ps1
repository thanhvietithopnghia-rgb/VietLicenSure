[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ClientVmSummaryPath,
    [Parameter(Mandatory=$true)][string]$IndependentSecurityReviewPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$ExpectedSourceCommit,
    [string]$ExpectedReleaseVersion='5.0.0.0'
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
$summary=Read-SafeJson $ClientVmSummaryPath 262144 'VM summary'
if([string]$summary.SchemaVersion-cne'1.0'-or[string]$summary.Status-cne'Passed'){throw 'VM summary has not Passed.'}
if([int]$summary.ExpectedPlatformCount-ne 3-or[int]$summary.ResultCount-ne 3-or[int]$summary.PassedCount-ne 3-or[int]$summary.FailedCount-ne 0-or[int]$summary.MissingCount-ne 0){throw 'Public Stable requires 3/3 VM Passed, 0 Failed, 0 Missing.'}
if([string]$summary.SourceCommit-cne$commit){throw 'VM summary commit does not match provenance.'}
$platforms=@('win10-22h2','win11-previous','win11-current')
$tests=@('VERIFY-FOUNDATION.ps1','VERIFY-COMPATIBILITY.ps1','VERIFY-REPORT-SCHEMA.ps1','VERIFY-DASHBOARD.ps1','VERIFY-OFFLINE-I18N.ps1','VERIFY-LOCALIZATION-COVERAGE.ps1','VERIFY-PERFORMANCE.ps1','VERIFY-CATALOG-PLUGIN-TRUST-V5.ps1','VERIFY-ENTERPRISE.ps1','VERIFY-ENTERPRISE-GOVERNANCE.ps1','VERIFY-NO-SIGNING-SECRETS.ps1')
foreach($platform in $platforms){
    $match=@($summary.Results|Where-Object{[string]$_.Platform-ceq$platform})
    if($match.Count-ne 1){throw "Missing unique VM result: $platform"}
    $result=$match[0]
    if([string]$result.Status-cne'Passed'-or-not[bool]$result.OsIdentityVerified-or[string]$result.Commit-cne$commit){throw "Invalid VM result: $platform"}
    foreach($name in $tests){
        $test=@($result.Tests|Where-Object{[string]$_.Name-ceq$name})
        if($test.Count-ne 1-or[string]$test[0].Status-cne'Passed'-or[int]$test[0].ExitCode-ne 0){throw "$platform lacks Passed test: $name"}
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
