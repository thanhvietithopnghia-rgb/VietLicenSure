[CmdletBinding()]
param(
    [string]$SourceDirectory = '',
    [switch]$AllowUnsignedDevelopmentTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }

function Assert-ProvenanceTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Write-ProvenanceFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Text
    )
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { New-Item -ItemType Directory -Path $Directory | Out-Null }
    $path = Join-Path $Directory 'OFFICIAL-PROVENANCE-v1.json'
    [IO.File]::WriteAllText($path, $Text, (New-Object Text.UTF8Encoding($false)))
    return $path
}

try {
    $sourceFull = [IO.Path]::GetFullPath($SourceDirectory)
    $helperPath = Join-Path $sourceFull 'Tool-Provenance.ps1'
    $manifestPath = Join-Path $sourceFull 'OFFICIAL-PROVENANCE-v1.json'
    $signaturePath = Join-Path $sourceFull 'OFFICIAL-PROVENANCE-v1.json.p7s'
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'Tool-Provenance.ps1 is missing.' }
    . $helperPath

    $base = Read-ToolOfficialProvenanceManifest -ManifestPath $manifestPath -AllowSourceCommitPlaceholder -RequireCanonical
    Assert-ProvenanceTest ($base.Document.ReleaseVersion -ceq '4.9.0.0') 'ReleaseVersion is not v4.9.0.0.'
    Assert-ProvenanceTest ($base.Document.BuildId -ceq '4.9.0.0-production-20260822') 'BuildId is invalid.'

    $strictUnsigned = Test-ToolOfficialProvenance -ManifestPath $manifestPath -SignaturePath $signaturePath
    if (Test-Path -LiteralPath $signaturePath -PathType Leaf) {
        if ([bool]$base.UsesSourceCommitPlaceholder) {
            Assert-ProvenanceTest ($strictUnsigned.State -eq 'Modified' -and -not $strictUnsigned.IsOfficial) `
                'A signed production path accepted the source-commit placeholder.'
        } else {
            Assert-ProvenanceTest ($strictUnsigned.State -eq 'Official' -and $strictUnsigned.IsOfficial -and $strictUnsigned.SignatureChecked) `
                'A production provenance manifest with a detached signature was not verified as Official.'
        }
    } else {
        if ([bool]$base.UsesSourceCommitPlaceholder) {
            Assert-ProvenanceTest ($strictUnsigned.State -eq 'Modified' -and $strictUnsigned.Code -eq 'ManifestInvalid') `
                'Strict runtime verification accepted a source-commit placeholder or failed with the wrong state.'
        } else {
            Assert-ProvenanceTest ($strictUnsigned.State -eq 'Unverified' -and $strictUnsigned.Code -eq 'SignatureMissing') `
                'Strict runtime verification accepted an unsigned production manifest or failed with the wrong state.'
        }
        if (-not $AllowUnsignedDevelopmentTest) {
            throw 'Detached provenance signature is missing. Use -AllowUnsignedDevelopmentTest only for the pre-signing development verifier.'
        }
        $development = Test-ToolOfficialProvenance -ManifestPath $manifestPath -SignaturePath $signaturePath -AllowUnsignedDevelopmentTest
        Assert-ProvenanceTest ($development.State -eq 'Unverified' -and -not $development.IsOfficial -and
            $development.AcceptedForDevelopmentTest -and $development.Code -eq 'UnsignedDevelopmentAccepted') `
            'Explicit unsigned development mode did not remain visibly Unverified.'
    }

    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('Tool-Provenance-Verify-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
        $canonical = [string]$base.CanonicalText

        $tamperedDirectory = Join-Path $fixtureRoot 'tampered'
        $tamperedText = $canonical.Replace('"Author":"Thanh Viet"', '"Author":"Another Author"')
        $tamperedPath = Write-ProvenanceFixture -Directory $tamperedDirectory -Text $tamperedText
        $tamperedResult = Test-ToolOfficialProvenance -ManifestPath $tamperedPath `
            -SignaturePath (Join-Path $tamperedDirectory 'OFFICIAL-PROVENANCE-v1.json.p7s') -AllowUnsignedDevelopmentTest
        Assert-ProvenanceTest ($tamperedResult.State -eq 'Modified' -and $tamperedResult.Code -eq 'ManifestInvalid') `
            'Identity tampering did not fail closed.'

        $unknownDirectory = Join-Path $fixtureRoot 'unknown-field'
        $unknownText = $canonical.TrimEnd([char]13, [char]10)
        $unknownText = $unknownText.Substring(0, $unknownText.Length - 1) + ',"UnexpectedField":"blocked"}' + "`n"
        $unknownPath = Write-ProvenanceFixture -Directory $unknownDirectory -Text $unknownText
        $unknownResult = Test-ToolOfficialProvenance -ManifestPath $unknownPath `
            -SignaturePath (Join-Path $unknownDirectory 'OFFICIAL-PROVENANCE-v1.json.p7s') -AllowUnsignedDevelopmentTest
        Assert-ProvenanceTest ($unknownResult.State -eq 'Modified' -and $unknownResult.Code -eq 'ManifestInvalid') `
            'Unknown provenance fields did not fail closed.'

        $duplicateDirectory = Join-Path $fixtureRoot 'duplicate-field'
        $duplicateText = $canonical.Replace('{"SchemaVersion":"1.0",', '{"SchemaVersion":"1.0","SchemaVersion":"1.0",')
        $duplicatePath = Write-ProvenanceFixture -Directory $duplicateDirectory -Text $duplicateText
        $duplicateResult = Test-ToolOfficialProvenance -ManifestPath $duplicatePath `
            -SignaturePath (Join-Path $duplicateDirectory 'OFFICIAL-PROVENANCE-v1.json.p7s') -AllowUnsignedDevelopmentTest
        Assert-ProvenanceTest ($duplicateResult.State -eq 'Modified' -and $duplicateResult.Code -eq 'ManifestInvalid') `
            'Duplicate provenance fields did not fail closed.'

        if (Test-Path -LiteralPath $signaturePath -PathType Leaf) {
            $signedDirectory = Join-Path $fixtureRoot 'signature-tamper'
            $signedManifestPath = Write-ProvenanceFixture -Directory $signedDirectory -Text $canonical
            $badSignaturePath = Join-Path $signedDirectory 'OFFICIAL-PROVENANCE-v1.json.p7s'
            $signatureBytes = [IO.File]::ReadAllBytes($signaturePath)
            $signatureBytes[[Math]::Floor($signatureBytes.Length / 2)] = $signatureBytes[[Math]::Floor($signatureBytes.Length / 2)] -bxor 1
            [IO.File]::WriteAllBytes($badSignaturePath, $signatureBytes)
            $badSignature = Test-ToolOfficialProvenance -ManifestPath $signedManifestPath -SignaturePath $badSignaturePath
            Assert-ProvenanceTest ($badSignature.State -eq 'Modified' -and -not $badSignature.IsOfficial) `
                'Detached-signature tampering did not fail closed.'
        }
    } finally {
        if ($fixtureRoot -and (Test-Path -LiteralPath $fixtureRoot -PathType Container)) {
            $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92) + [IO.Path]::DirectorySeparatorChar
            $fixtureFull = [IO.Path]::GetFullPath($fixtureRoot)
            if ($fixtureFull.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
                [IO.Path]::GetFileName($fixtureFull).StartsWith('Tool-Provenance-Verify-', [StringComparison]::Ordinal)) {
                Remove-Item -LiteralPath $fixtureFull -Recurse -Force
            }
        }
    }

    Write-Host 'PROVENANCE: PASS (strict schema, canonical form, identity pinning, unknown/duplicate/tamper fail-closed).' -ForegroundColor Green
    if (-not (Test-Path -LiteralPath $signaturePath -PathType Leaf)) {
        Write-Host 'PROVENANCE: development-only unsigned manifest remains Unverified; replace SourceSnapshotCommit and sign before release.' -ForegroundColor Yellow
    }
    exit 0
} catch {
    Write-Error ("PROVENANCE: FAIL - " + [string]$_.Exception.Message)
    exit 1
}
