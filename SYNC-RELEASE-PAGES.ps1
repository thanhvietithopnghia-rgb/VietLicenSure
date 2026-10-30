[CmdletBinding()]
param(
    [string]$ReleaseMetadataPath = '',
    [string]$DocsRoot = '',
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ReleaseMetadataPath)) { $ReleaseMetadataPath = Join-Path $PSScriptRoot 'CURRENT-RELEASE.json' }
if ([string]::IsNullOrWhiteSpace($DocsRoot)) { $DocsRoot = Join-Path $PSScriptRoot 'docs' }

$release = Get-Content -LiteralPath $ReleaseMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$release.SchemaVersion -ne '1.0' -or [string]$release.EvidenceClass -ne 'Current' -or -not [bool]$release.EligibleForCurrentRelease) {
    throw 'CURRENT-RELEASE.json is not an eligible current-release record.'
}

$values = [ordered]@{
    releaseEyebrowVi = "v$($release.ReleaseVersion) | $([datetime]::ParseExact([string]$release.PublicUpdateDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).ToString('dd/MM/yyyy')) | $($release.PublicChannel)"
    releaseEyebrowEn = "v$($release.ReleaseVersion) | updated $($release.PublicUpdateDate) | $($release.PublicChannel)"
    releaseVersion = "v$($release.ReleaseVersion)"
    buildId = [string]$release.BuildId
    publicChannel = [string]$release.PublicChannel
    publisher = [string]$release.Artifact.AuthenticodePublisher
    artifactSha256 = [string]$release.Artifact.Sha256
    sourceCommit = [string]$release.Source.SourceCommit
    bundleCommit = [string]$release.Source.BundleCommit
    exactHashQaStatusVi = "Exact-hash PASS | independent review: $($release.IndependentSecurityReview.Status)"
    exactHashQaStatusEn = "Exact-hash PASS | independent review: $($release.IndependentSecurityReview.Status)"
    independentReviewStatus = [string]$release.IndependentSecurityReview.Status
}

$coverage = @{}
foreach ($key in $values.Keys) { $coverage[$key] = 0 }
$drift = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = New-Object Text.UTF8Encoding($false)

foreach ($page in @(Get-ChildItem -LiteralPath $DocsRoot -Filter '*.html' -File)) {
    $html = Get-Content -LiteralPath $page.FullName -Raw -Encoding UTF8
    $updated = $html
    foreach ($key in $values.Keys) {
        $pattern = '(?is)(?<open><(?<tag>[a-z][a-z0-9]*)\b[^>]*\bdata-release-field=["'']' + [regex]::Escape($key) + '["''][^>]*>)(?<value>.*?)(?<close></\k<tag>>)'
        $matches = [regex]::Matches($updated, $pattern)
        if ($matches.Count -eq 0) { continue }
        $coverage[$key] += $matches.Count
        $expected = [Security.SecurityElement]::Escape([string]$values[$key])
        $updated = [regex]::Replace($updated, $pattern, {
            param($match)
            return $match.Groups['open'].Value + $expected + $match.Groups['close'].Value
        })
    }
    if ($updated -cne $html) {
        if ($Check) { [void]$drift.Add($page.Name) }
        else { [IO.File]::WriteAllText($page.FullName, $updated, $utf8NoBom) }
    }
}

foreach ($required in @('releaseEyebrowVi','releaseEyebrowEn','buildId','publisher','artifactSha256','sourceCommit','bundleCommit','exactHashQaStatusVi','exactHashQaStatusEn','independentReviewStatus')) {
    if ([int]$coverage[$required] -lt 1) { throw "Website has no render target for canonical field: $required" }
}
if ($drift.Count -gt 0) { throw "Website release metadata drift: $($drift -join ', ')" }

$mode = if ($Check) { 'CHECK' } else { 'WRITE' }
Write-Host "Release page sync $mode PASS: $($values.Count) canonical fields." -ForegroundColor Green
