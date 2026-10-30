[CmdletBinding()]
param(
    [string]$SourceDirectory = '',
    [string]$DistributionDirectory = '',
    [string]$QaEvidencePath = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($DistributionDirectory)) { $DistributionDirectory = $SourceDirectory }
$sourceRoot = [IO.Path]::GetFullPath($SourceDirectory)
$distributionRoot = [IO.Path]::GetFullPath($DistributionDirectory)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-EvidenceFailure([string]$Message) { [void]$failures.Add($Message) }
function Get-EvidenceJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing evidence input: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Get-EvidenceSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Test-EligibleCurrentRecord($Record, [string]$ExpectedHash, [string]$ExpectedBuildId, [string]$ExpectedSourceCommit) {
    return [bool](
        [string]$Record.SchemaVersion -eq '1.0' -and
        [string]$Record.EvidenceClass -eq 'Current' -and
        [bool]$Record.EligibleForCurrentRelease -and
        [string]$Record.Artifact.Sha256 -eq $ExpectedHash -and
        [string]$Record.BuildId -eq $ExpectedBuildId -and
        [string]$Record.Source.SourceCommit -eq $ExpectedSourceCommit -and
        [string]$Record.Artifact.AuthenticodeThumbprintSha1 -match '^[0-9A-F]{40}$' -and
        [string]$Record.IndependentSecurityReview.Status -eq 'NotReviewed' -and
        -not [bool]$Record.IndependentSecurityReview.CriticalHighClaimAllowed
    )
}

try {
    $current = Get-EvidenceJson (Join-Path $sourceRoot 'CURRENT-RELEASE.json')
    $historical = Get-EvidenceJson (Join-Path $sourceRoot 'historical-evidence\SECURITY-TEST-RESULTS-20260908.json')
    $manifest = Get-EvidenceJson (Join-Path $distributionRoot 'RELEASE-MANIFEST.json')
    $provenance = Get-EvidenceJson (Join-Path $sourceRoot 'OFFICIAL-PROVENANCE-v1.json')
    $update = Get-EvidenceJson (Join-Path $sourceRoot 'update-manifest-v1.json')
    $artifact = @($manifest.Artifacts)[0]

    $expectedHash = ([string]$artifact.Sha256).ToUpperInvariant()
    $expectedBuildId = [string]$provenance.BuildId
    $expectedSourceCommit = [string]$provenance.SourceSnapshotCommit
    if (-not (Test-EligibleCurrentRecord $current $expectedHash $expectedBuildId $expectedSourceCommit)) {
        Add-EvidenceFailure 'CURRENT-RELEASE.json does not match the signed manifest/provenance identity or review boundary.'
    }
    if ([string]$current.Artifact.FileName -ne [string]$artifact.FileName -or
        [string]$current.Artifact.AuthenticodeSigner -ne [string]$artifact.AuthenticodeSigner -or
        [string]$current.Artifact.AuthenticodeThumbprintSha1 -ne [string]$artifact.AuthenticodeThumbprint -or
        [string]$current.Artifact.AuthenticodeCertificateSha256 -ne [string]$provenance.AuthenticodeSignerCertificateSha256 -or
        [string]$current.ContentCmsSigner.ThumbprintSha1 -ne [string]$provenance.SignerThumbprint -or
        [string]$current.ContentCmsSigner.CertificateSha256 -ne [string]$provenance.SignerCertificateSha256) {
        Add-EvidenceFailure 'Current evidence conflates or mismatches the Authenticode and content-CMS signers.'
    }
    if ([string]$update.DownloadSha256 -ne $expectedHash -or
        [int64]$update.DownloadSize -ne [int64]$current.Artifact.SizeBytes -or
        @($update.SignerThumbprints).Count -ne 1 -or
        [string]@($update.SignerThumbprints)[0] -ne [string]$current.Artifact.AuthenticodeThumbprintSha1) {
        Add-EvidenceFailure 'Update manifest does not match the canonical current artifact identity.'
    }
    $releaseHashLine = @(Get-Content -LiteralPath (Join-Path $distributionRoot 'RELEASE-SHA256SUMS.txt') -Encoding UTF8 | Where-Object {
        $_ -match ('^([0-9A-Fa-f]{64})\s+\*?' + [regex]::Escape([string]$current.Artifact.FileName) + '$')
    })
    if ($releaseHashLine.Count -ne 1 -or $releaseHashLine[0].Substring(0, 64).ToUpperInvariant() -ne $expectedHash) {
        Add-EvidenceFailure 'RELEASE-SHA256SUMS.txt does not uniquely bind the canonical current EXE.'
    }

    if ([string]$historical.EvidenceClass -ne 'Historical' -or [bool]$historical.EligibleForCurrentRelease -or
        [string]$historical.SignerType -ne 'ContentCMS' -or [string]$historical.ArtifactHashStatus -ne 'NotRecordedInHistoricalDocument') {
        Add-EvidenceFailure 'Historical security evidence is not explicitly ineligible for current release use.'
    }
    $negative = $historical | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $negative.EvidenceClass = 'Current'
    $negative.EligibleForCurrentRelease = $true
    if (Test-EligibleCurrentRecord $negative $expectedHash $expectedBuildId $expectedSourceCommit) {
        Add-EvidenceFailure 'Negative test failed: historical evidence was accepted as the current release.'
    }

    if (-not [string]::IsNullOrWhiteSpace($QaEvidencePath)) {
        $qa = Get-EvidenceJson $QaEvidencePath
        if ((Get-EvidenceSha256 $QaEvidencePath) -ne [string]$current.QualityAssurance.EvidenceSha256 -or
            [string]$qa.artifactSha256 -ne $expectedHash -or [string]$qa.buildId -ne $expectedBuildId -or
            [string]$qa.sourceSnapshot -ne $expectedSourceCommit -or [string]$qa.result -ne 'PASS' -or
            [string]$qa.independentReview -ne 'NotReviewed') {
            Add-EvidenceFailure 'QA evidence does not match CURRENT-RELEASE.json or its NotReviewed boundary.'
        }
    }
} catch {
    Add-EvidenceFailure $_.Exception.Message
}

if ($failures.Count -gt 0) {
    Write-Host "VERIFY-RELEASE-EVIDENCE: $($failures.Count) error(s)." -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'VERIFY-RELEASE-EVIDENCE: PASS (current identity, signer separation, update manifest, historical negative test).' -ForegroundColor Green
exit 0
