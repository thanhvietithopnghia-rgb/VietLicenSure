$script:ToolProvenanceSchemaVersion = '1.0'
$script:ToolProvenanceManifestFileName = 'OFFICIAL-PROVENANCE-v1.json'
$script:ToolProvenanceSignatureFileName = 'OFFICIAL-PROVENANCE-v1.json.p7s'
$script:ToolProvenanceMaximumManifestBytes = 32768
$script:ToolProvenanceMaximumSignatureBytes = 65536
$script:ToolProvenanceSourceCommitPlaceholder = 'REPLACE_BEFORE_SIGNING_WITH_40_HEX_GIT_COMMIT'
$script:ToolProvenanceAllowedFields = @(
    'SchemaVersion',
    'ProductId',
    'ProductName',
    'Author',
    'OfficialRepository',
    'ReleaseVersion',
    'BuildId',
    'BuildTime',
    'SourcePolicyId',
    'SourceSnapshotCommit',
    'VerificationUrl',
    'SignerCertificateSha256',
    'SignerThumbprint'
)
$script:ToolProvenanceExpectedValues = [ordered]@{
    SchemaVersion = '1.0'
    ProductId = '4B8D93E8-278A-4F9D-A39E-986B0322B65B'
    ProductName = 'Tool Kiem Tra'
    Author = 'Thanh Viet'
    OfficialRepository = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen'
    ReleaseVersion = '5.0.0.1'
    # Canonical release identity. BUILD.ps1 injects this BuildId into the
    # compiled launcher and the elevated bridge reads it at runtime. Keep the
    # release identity here so a date cannot drift independently in source,
    # payload, provenance, or the final executable.
    BuildId = '5.0.0.1-production-20260906'
    BuildTime = '2026-09-06'
    SourcePolicyId = 'ThanhViet.ToolKiemTra.CommunityControlledSource.v4.9'
    VerificationUrl = 'https://thanhvietithopnghia-rgb.github.io/Tool-Kiem-Tra-Ban-Quyen/#verify-official-build'
    SignerCertificateSha256 = 'A42B00D863D4770B47F21FFF756545249D58DD59691AD9E05C02048C104F9FC9'
    SignerThumbprint = 'ABE70696679B1D8987A2D5B1F6C1C6909D364CEA'
}

function Get-ToolProvenanceExpectedValues {
    return [pscustomobject]$script:ToolProvenanceExpectedValues
}

function Get-ToolProvenanceSha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToUpperInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-ToolProvenanceFileBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedFileName,
        [Parameter(Mandatory = $true)][int64]$MaximumBytes
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not [IO.Path]::GetFileName($fullPath).Equals($ExpectedFileName, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Provenance file name is not allowed: $([IO.Path]::GetFileName($fullPath))"
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Provenance file is missing: $ExpectedFileName"
    }
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Provenance file cannot be a reparse point: $ExpectedFileName"
    }
    if ($item.Length -le 0 -or $item.Length -gt $MaximumBytes) {
        throw "Provenance file size is invalid: $ExpectedFileName"
    }
    return [IO.File]::ReadAllBytes($fullPath)
}

function ConvertTo-ToolProvenanceCanonicalJson {
    param([Parameter(Mandatory = $true)][object]$Document)

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($field in $script:ToolProvenanceAllowedFields) {
        $property = $Document.PSObject.Properties[$field]
        if (-not $property -or $property.Value -isnot [string]) {
            throw "Provenance field must be a JSON string: $field"
        }
        $encodedName = ConvertTo-Json -InputObject ([string]$field) -Compress
        $encodedValue = ConvertTo-Json -InputObject ([string]$property.Value) -Compress
        [void]$parts.Add($encodedName + ':' + $encodedValue)
    }
    return ('{' + ($parts -join ',') + '}' + "`n")
}

function ConvertFrom-ToolProvenanceBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [switch]$AllowSourceCommitPlaceholder,
        [switch]$RequireCanonical
    )

    if ($Bytes.Length -le 2 -or $Bytes.Length -gt $script:ToolProvenanceMaximumManifestBytes) {
        throw 'Provenance manifest size is outside the allowed range.'
    }
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $text = $utf8.GetString($Bytes)
    if ([string]::IsNullOrWhiteSpace($text) -or $text.IndexOf([char]0) -ge 0 -or $text[0] -eq [char]0xFEFF) {
        throw 'Provenance manifest encoding is invalid.'
    }

    # The schema is intentionally a flat object containing string values only.
    # Counting raw JSON member names prevents duplicate keys from being hidden by
    # ConvertFrom-Json's last-value-wins behavior.
    $memberMatches = [regex]::Matches($text, '"(?<name>(?:\\.|[^"\\])*)"\s*:')
    if ($memberMatches.Count -ne $script:ToolProvenanceAllowedFields.Count) {
        throw 'Provenance manifest member count is invalid.'
    }
    $seen = @{}
    foreach ($match in $memberMatches) {
        $name = [string]$match.Groups['name'].Value
        if ($name.IndexOf('\') -ge 0 -or $script:ToolProvenanceAllowedFields -cnotcontains $name -or $seen.ContainsKey($name)) {
            throw "Provenance manifest contains an unknown, escaped, or duplicate field: $name"
        }
        $seen[$name] = $true
    }

    try {
        $document = $text | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw 'Provenance manifest is not valid JSON.'
    }
    if ($null -eq $document -or $document -is [array]) {
        throw 'Provenance manifest root must be one JSON object.'
    }
    $actualNames = @($document.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($actualNames.Count -ne $script:ToolProvenanceAllowedFields.Count) {
        throw 'Provenance manifest property count is invalid.'
    }
    foreach ($field in $script:ToolProvenanceAllowedFields) {
        $property = $document.PSObject.Properties[$field]
        if (-not $property -or $property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            throw "Provenance manifest field is missing or is not a non-empty string: $field"
        }
    }
    foreach ($property in @($document.PSObject.Properties)) {
        if ($script:ToolProvenanceAllowedFields -cnotcontains [string]$property.Name) {
            throw "Provenance manifest contains an unknown field: $($property.Name)"
        }
    }

    foreach ($entry in $script:ToolProvenanceExpectedValues.GetEnumerator()) {
        if ([string]$document.($entry.Key) -cne [string]$entry.Value) {
            throw "Provenance manifest identity mismatch: $($entry.Key)"
        }
    }
    $sourceCommit = [string]$document.SourceSnapshotCommit
    if ($sourceCommit -notmatch '^[0-9a-f]{40}$') {
        if (-not $AllowSourceCommitPlaceholder -or $sourceCommit -cne $script:ToolProvenanceSourceCommitPlaceholder) {
            throw 'SourceSnapshotCommit must be the exact 40-character lowercase Git commit before signing.'
        }
    }

    $canonicalText = ConvertTo-ToolProvenanceCanonicalJson -Document $document
    if ($RequireCanonical -and $text -cne $canonicalText) {
        throw 'Provenance manifest is not in canonical form.'
    }
    return [pscustomobject][ordered]@{
        Document = $document
        Text = $text
        CanonicalText = $canonicalText
        Bytes = $Bytes
        Sha256 = Get-ToolProvenanceSha256Hex -Bytes $Bytes
        UsesSourceCommitPlaceholder = [bool]($sourceCommit -ceq $script:ToolProvenanceSourceCommitPlaceholder)
    }
}

function Read-ToolOfficialProvenanceManifest {
    param(
        [string]$ManifestPath = (Join-Path $PSScriptRoot $script:ToolProvenanceManifestFileName),
        [switch]$AllowSourceCommitPlaceholder,
        [switch]$RequireCanonical
    )

    $bytes = Get-ToolProvenanceFileBytes -Path $ManifestPath `
        -ExpectedFileName $script:ToolProvenanceManifestFileName `
        -MaximumBytes $script:ToolProvenanceMaximumManifestBytes
    return ConvertFrom-ToolProvenanceBytes -Bytes $bytes `
        -AllowSourceCommitPlaceholder:$AllowSourceCommitPlaceholder `
        -RequireCanonical:$RequireCanonical
}

function Test-ToolProvenanceDetachedSignature {
    param(
        [Parameter(Mandatory = $true)][byte[]]$ContentBytes,
        [Parameter(Mandatory = $true)][byte[]]$SignatureBytes
    )

    try {
        if ($ContentBytes.Length -le 2 -or $ContentBytes.Length -gt $script:ToolProvenanceMaximumManifestBytes -or
            $SignatureBytes.Length -le 64 -or $SignatureBytes.Length -gt $script:ToolProvenanceMaximumSignatureBytes) {
            return [pscustomobject]@{ Valid=$false; Code='SignatureSizeInvalid'; CertificateSha256=''; Thumbprint='' }
        }
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $contentInfo = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$ContentBytes)
        $signedCms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($contentInfo, $true)
        $signedCms.Decode($SignatureBytes)
        if ($signedCms.SignerInfos.Count -ne 1) {
            return [pscustomobject]@{ Valid=$false; Code='SignerCountInvalid'; CertificateSha256=''; Thumbprint='' }
        }
        $signer = $signedCms.SignerInfos[0]
        if ($null -eq $signer.Certificate -or
            $signer.DigestAlgorithm.Value -ne '2.16.840.1.101.3.4.2.1' -or
            $signer.Certificate.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1') {
            return [pscustomobject]@{ Valid=$false; Code='SignerAlgorithmInvalid'; CertificateSha256=''; Thumbprint='' }
        }
        $certificateSha256 = Get-ToolProvenanceSha256Hex -Bytes $signer.Certificate.RawData
        $thumbprint = ([string]$signer.Certificate.Thumbprint).Replace(' ', '').ToUpperInvariant()
        if ($certificateSha256 -cne [string]$script:ToolProvenanceExpectedValues.SignerCertificateSha256 -or
            $thumbprint -cne [string]$script:ToolProvenanceExpectedValues.SignerThumbprint) {
            return [pscustomobject]@{ Valid=$false; Code='SignerPinMismatch'; CertificateSha256=$certificateSha256; Thumbprint=$thumbprint }
        }
        $signedCms.CheckSignature($true)
        return [pscustomobject]@{ Valid=$true; Code='Valid'; CertificateSha256=$certificateSha256; Thumbprint=$thumbprint }
    } catch {
        return [pscustomobject]@{ Valid=$false; Code='SignatureInvalid'; CertificateSha256=''; Thumbprint='' }
    }
}

function New-ToolProvenanceStateResult {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Official','Modified','Unverified')][string]$State,
        [Parameter(Mandatory = $true)][string]$Code,
        [string]$Message = '',
        [AllowNull()][object]$Manifest = $null,
        [string]$ManifestSha256 = '',
        [bool]$SignatureChecked = $false,
        [bool]$AcceptedForDevelopmentTest = $false
    )

    return [pscustomobject][ordered]@{
        State = $State
        IsOfficial = [bool]($State -eq 'Official')
        IsModified = [bool]($State -eq 'Modified')
        IsUnverified = [bool]($State -eq 'Unverified')
        Code = $Code
        Message = $Message
        Manifest = $Manifest
        ManifestSha256 = $ManifestSha256
        SignatureChecked = $SignatureChecked
        AcceptedForDevelopmentTest = $AcceptedForDevelopmentTest
        CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Test-ToolOfficialProvenance {
    param(
        [string]$ManifestPath = (Join-Path $PSScriptRoot $script:ToolProvenanceManifestFileName),
        [string]$SignaturePath = '',
        [switch]$AllowUnsignedDevelopmentTest
    )

    if ([string]::IsNullOrWhiteSpace($SignaturePath)) {
        $SignaturePath = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($ManifestPath))) $script:ToolProvenanceSignatureFileName
    }
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        return New-ToolProvenanceStateResult -State Unverified -Code 'ManifestMissing' -Message 'Official provenance manifest is missing.'
    }

    $manifest = $null
    try {
        $manifest = Read-ToolOfficialProvenanceManifest -ManifestPath $ManifestPath `
            -AllowSourceCommitPlaceholder:$AllowUnsignedDevelopmentTest -RequireCanonical
    } catch {
        return New-ToolProvenanceStateResult -State Modified -Code 'ManifestInvalid' -Message ([string]$_.Exception.Message)
    }

    if (-not (Test-Path -LiteralPath $SignaturePath -PathType Leaf)) {
        if ($AllowUnsignedDevelopmentTest) {
            return New-ToolProvenanceStateResult -State Unverified -Code 'UnsignedDevelopmentAccepted' `
                -Message 'Unsigned provenance is accepted only for this explicit development test.' `
                -Manifest $manifest.Document -ManifestSha256 $manifest.Sha256 -AcceptedForDevelopmentTest $true
        }
        return New-ToolProvenanceStateResult -State Unverified -Code 'SignatureMissing' `
            -Message 'Detached official provenance signature is missing.' `
            -Manifest $manifest.Document -ManifestSha256 $manifest.Sha256
    }

    if ($manifest.UsesSourceCommitPlaceholder) {
        return New-ToolProvenanceStateResult -State Modified -Code 'SourceCommitPlaceholder' `
            -Message 'The source snapshot placeholder must be replaced before signing.' `
            -Manifest $manifest.Document -ManifestSha256 $manifest.Sha256
    }
    try {
        $signatureBytes = Get-ToolProvenanceFileBytes -Path $SignaturePath `
            -ExpectedFileName $script:ToolProvenanceSignatureFileName `
            -MaximumBytes $script:ToolProvenanceMaximumSignatureBytes
    } catch {
        return New-ToolProvenanceStateResult -State Modified -Code 'SignatureFileInvalid' `
            -Message ([string]$_.Exception.Message) -Manifest $manifest.Document -ManifestSha256 $manifest.Sha256
    }
    $signature = Test-ToolProvenanceDetachedSignature -ContentBytes $manifest.Bytes -SignatureBytes $signatureBytes
    if (-not [bool]$signature.Valid) {
        return New-ToolProvenanceStateResult -State Modified -Code ([string]$signature.Code) `
            -Message 'Detached provenance signature is invalid or is not from the pinned author certificate.' `
            -Manifest $manifest.Document -ManifestSha256 $manifest.Sha256 -SignatureChecked $true
    }
    return New-ToolProvenanceStateResult -State Official -Code 'Official' `
        -Message 'The provenance manifest and pinned detached signature are valid.' `
        -Manifest $manifest.Document -ManifestSha256 $manifest.Sha256 -SignatureChecked $true
}

function Get-ToolOfficialBuildState {
    param(
        [string]$ManifestPath = (Join-Path $PSScriptRoot $script:ToolProvenanceManifestFileName),
        [string]$SignaturePath = ''
    )

    # Runtime callers intentionally cannot opt into development acceptance.
    return Test-ToolOfficialProvenance -ManifestPath $ManifestPath -SignaturePath $SignaturePath
}
