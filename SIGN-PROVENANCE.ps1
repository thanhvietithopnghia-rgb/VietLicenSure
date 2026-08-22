[CmdletBinding(DefaultParameterSetName = 'Store')]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'OFFICIAL-PROVENANCE-v1.json'),
    [Parameter(Mandatory = $true, ParameterSetName = 'Store')][string]$CertificateThumbprint,
    [Parameter(ParameterSetName = 'Store')][ValidateSet('CurrentUser','LocalMachine')][string]$StoreLocation = 'CurrentUser',
    [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')][string]$PfxPath,
    [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')][Security.SecureString]$PfxPassword,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$helperPath = Join-Path $PSScriptRoot 'Tool-Provenance.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'Tool-Provenance.ps1 is missing.' }
. $helperPath
Add-Type -AssemblyName System.Security -ErrorAction Stop

function Get-ProvenanceSigningCertificate {
    if ($PSCmdlet.ParameterSetName -eq 'Store') {
        $normalized = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
        if ($normalized -notmatch '^[A-F0-9]{40,64}$') { throw 'Certificate thumbprint is invalid.' }
        $certificatePath = "Cert:\$StoreLocation\My\$normalized"
        if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) { throw "Signing certificate was not found in $StoreLocation\My." }
        return Get-Item -LiteralPath $certificatePath -ErrorAction Stop
    }

    $fullPfxPath = [IO.Path]::GetFullPath($PfxPath)
    if (-not (Test-Path -LiteralPath $fullPfxPath -PathType Leaf)) { throw 'Signing PFX was not found.' }
    if ([IO.Path]::GetExtension($fullPfxPath) -notin @('.pfx','.p12')) { throw 'Only PFX/P12 certificate files are allowed.' }
    $pfxInfo = Get-Item -LiteralPath $fullPfxPath -Force
    if (($pfxInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $pfxInfo.Length -le 0 -or $pfxInfo.Length -gt 10485760) {
        throw 'Signing PFX is unsafe or outside the size limit.'
    }
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PfxPassword)
        $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        return New-Object Security.Cryptography.X509Certificates.X509Certificate2 `
            -ArgumentList @($fullPfxPath, $passwordText, [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        $passwordText = $null
    }
}

function Assert-ProvenanceSigningCertificate {
    param([Parameter(Mandatory = $true)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    if (-not $Certificate.HasPrivateKey) { throw 'Signing certificate has no private key.' }
    if ($Certificate.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1') { throw 'Signing certificate must use an RSA key.' }
    $now = Get-Date
    if ($now -lt $Certificate.NotBefore -or $now -gt $Certificate.NotAfter) { throw 'Signing certificate is not currently valid.' }
    $hasCodeSigningEku = $false
    foreach ($extension in @($Certificate.Extensions)) {
        if ($extension.Oid.Value -eq '2.5.29.37') {
            $eku = New-Object Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension `
                -ArgumentList @($extension, [bool]$extension.Critical)
            foreach ($oid in @($eku.EnhancedKeyUsages)) {
                if ($oid.Value -eq '1.3.6.1.5.5.7.3.3') { $hasCodeSigningEku = $true }
            }
        }
    }
    if (-not $hasCodeSigningEku) { throw 'Signing certificate does not contain the Code Signing EKU.' }

    $expected = Get-ToolProvenanceExpectedValues
    $certificateSha256 = Get-ToolProvenanceSha256Hex -Bytes $Certificate.RawData
    $thumbprint = ([string]$Certificate.Thumbprint).Replace(' ', '').ToUpperInvariant()
    if ($certificateSha256 -cne [string]$expected.SignerCertificateSha256 -or
        $thumbprint -cne [string]$expected.SignerThumbprint) {
        throw 'Signing certificate does not match the hard-pinned provenance identity.'
    }
}

function Write-ProvenanceBytesAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [switch]$AllowReplace
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw 'Provenance output directory does not exist.' }
    $directoryInfo = Get-Item -LiteralPath $directory -Force
    if (($directoryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Provenance output directory cannot be a reparse point.' }
    if ((Test-Path -LiteralPath $fullPath) -and -not $AllowReplace) { throw "Output already exists: $fullPath" }
    if (Test-Path -LiteralPath $fullPath) {
        $existing = Get-Item -LiteralPath $fullPath -Force
        if (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Provenance output cannot replace a reparse point.' }
    }
    $temporaryPath = Join-Path $directory ('.provenance-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $Bytes)
        Move-Item -LiteralPath $temporaryPath -Destination $fullPath -Force:$AllowReplace
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}

$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
if (-not [IO.Path]::GetFileName($manifestFullPath).Equals('OFFICIAL-PROVENANCE-v1.json', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'SIGN-PROVENANCE signs only OFFICIAL-PROVENANCE-v1.json.'
}
$manifestInfo = Get-Item -LiteralPath $manifestFullPath -Force -ErrorAction Stop
if (($manifestInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Provenance manifest cannot be a reparse point.' }
$signaturePath = Join-Path (Split-Path -Parent $manifestFullPath) 'OFFICIAL-PROVENANCE-v1.json.p7s'
if (Test-Path -LiteralPath $signaturePath) {
    $signatureInfo = Get-Item -LiteralPath $signaturePath -Force
    if (($signatureInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Provenance signature cannot be a reparse point.'
    }
    if (-not $Force) { throw "Output already exists: $signaturePath" }
}

# Strict parsing rejects unknown/duplicate fields and the source-commit
# placeholder. The signer then rewrites the exact fixed-order UTF-8 bytes before
# producing the detached CMS signature.
$manifest = Read-ToolOfficialProvenanceManifest -ManifestPath $manifestFullPath
$canonicalBytes = (New-Object Text.UTF8Encoding($false)).GetBytes([string]$manifest.CanonicalText)

$certificate = Get-ProvenanceSigningCertificate
try {
    Assert-ProvenanceSigningCertificate -Certificate $certificate
    Write-ProvenanceBytesAtomically -Path $manifestFullPath -Bytes $canonicalBytes -AllowReplace
    $signedBytes = [IO.File]::ReadAllBytes($manifestFullPath)
    $contentInfo = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$signedBytes)
    $signedCms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($contentInfo, $true)
    $signer = New-Object Security.Cryptography.Pkcs.CmsSigner -ArgumentList $certificate
    $signer.IncludeOption = [Security.Cryptography.X509Certificates.X509IncludeOption]::EndCertOnly
    $signer.DigestAlgorithm = New-Object Security.Cryptography.Oid('2.16.840.1.101.3.4.2.1')
    $signedCms.ComputeSignature($signer, $false)
    $signatureBytes = $signedCms.Encode()
    if ($signatureBytes.Length -le 64 -or $signatureBytes.Length -gt 65536) { throw 'Generated provenance signature size is invalid.' }

    $verification = Test-ToolProvenanceDetachedSignature -ContentBytes $signedBytes -SignatureBytes $signatureBytes
    if (-not [bool]$verification.Valid) { throw "Generated provenance signature did not verify: $($verification.Code)" }

    Write-ProvenanceBytesAtomically -Path $signaturePath -Bytes $signatureBytes -AllowReplace:$Force
    Write-Host "SIGNED PROVENANCE: $manifestFullPath" -ForegroundColor Green
    Write-Host "  Manifest SHA-256: $(Get-ToolProvenanceSha256Hex -Bytes $signedBytes)"
    Write-Host "  Signature: $signaturePath"
    Write-Host "  Signer thumbprint: $($certificate.Thumbprint)"
} finally {
    if ($certificate -and $PSCmdlet.ParameterSetName -eq 'Pfx') { $certificate.Dispose() }
}
