[CmdletBinding(DefaultParameterSetName = 'Store')]
param(
    [string]$ManifestPath = '',
    [Parameter(Mandatory = $true, ParameterSetName = 'Store')][string]$CertificateThumbprint,
    [Parameter(ParameterSetName = 'Store')][ValidateSet('CurrentUser','LocalMachine')][string]$StoreLocation = 'CurrentUser',
    [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')][string]$PfxPath,
    [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')][Security.SecureString]$PfxPassword,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path $PSScriptRoot 'update-manifest-v1.json' }
$expectedThumbprint = 'ABE70696679B1D8987A2D5B1F6C1C6909D364CEA'
$expectedCertificateSha256 = 'A42B00D863D4770B47F21FFF756545249D58DD59691AD9E05C02048C104F9FC9'
$allowedFields = @(
    'SchemaVersion','Channel','LatestVersion','MinimumUpdaterVersion','PublishedAtUtc',
    'Title','Changes','ReleasePageUrl','DownloadUrl','DownloadSha256','DownloadSize',
    'AuthenticodeRequired','SignerThumbprints'
)

function Get-UpdateSigningSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Get-UpdateSigningCertificate {
    if ($PSCmdlet.ParameterSetName -eq 'Store') {
        $normalized = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
        if ($normalized -notmatch '^[A-F0-9]{40}$') { throw 'Certificate thumbprint is invalid.' }
        $certificatePath = "Cert:\$StoreLocation\My\$normalized"
        if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) { throw 'Signing certificate was not found.' }
        return Get-Item -LiteralPath $certificatePath -ErrorAction Stop
    }
    $fullPfxPath = [IO.Path]::GetFullPath($PfxPath)
    if (-not (Test-Path -LiteralPath $fullPfxPath -PathType Leaf) -or [IO.Path]::GetExtension($fullPfxPath) -notin @('.pfx','.p12')) {
        throw 'Signing PFX is missing or has an unsupported extension.'
    }
    $pfxInfo = Get-Item -LiteralPath $fullPfxPath -Force
    if (($pfxInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $pfxInfo.Length -le 0 -or $pfxInfo.Length -gt 10485760) {
        throw 'Signing PFX is unsafe or outside the size limit.'
    }
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PfxPassword)
        $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        return New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(
            $fullPfxPath, $passwordText, [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        $passwordText = $null
    }
}

function Assert-UpdateSigningCertificate {
    param([Parameter(Mandatory = $true)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    if (-not $Certificate.HasPrivateKey -or $Certificate.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1') {
        throw 'Signing certificate must have an RSA private key.'
    }
    $now = Get-Date
    if ($now -lt $Certificate.NotBefore -or $now -gt $Certificate.NotAfter) { throw 'Signing certificate is not currently valid.' }
    $hasCodeSigningEku = $false
    foreach ($extension in @($Certificate.Extensions)) {
        if ($extension.Oid.Value -eq '2.5.29.37') {
            $eku = New-Object Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension -ArgumentList @($extension, [bool]$extension.Critical)
            foreach ($oid in @($eku.EnhancedKeyUsages)) {
                if ($oid.Value -eq '1.3.6.1.5.5.7.3.3') { $hasCodeSigningEku = $true }
            }
        }
    }
    if (-not $hasCodeSigningEku) { throw 'Signing certificate does not contain the Code Signing EKU.' }
    $actualThumbprint = ([string]$Certificate.Thumbprint).Replace(' ', '').ToUpperInvariant()
    $actualCertificateSha256 = Get-UpdateSigningSha256 -Bytes $Certificate.RawData
    if ($actualThumbprint -cne $expectedThumbprint -or $actualCertificateSha256 -cne $expectedCertificateSha256) {
        throw 'Signing certificate does not match the hard-pinned Tool publisher.'
    }
}

function Write-UpdateSignatureAtomically {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][byte[]]$Bytes)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw 'Signature output directory is missing.' }
    if ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Signature output directory cannot be a reparse point.' }
    if (Test-Path -LiteralPath $fullPath) {
        $existing = Get-Item -LiteralPath $fullPath -Force
        if (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Signature output cannot replace a reparse point.' }
        if (-not $Force) { throw "Output already exists: $fullPath" }
    }
    $temporaryPath = Join-Path $directory ('.update-signature-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $Bytes)
        Move-Item -LiteralPath $temporaryPath -Destination $fullPath -Force:$Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}

$fullManifestPath = [IO.Path]::GetFullPath($ManifestPath)
if (-not [IO.Path]::GetFileName($fullManifestPath).Equals('update-manifest-v1.json', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'SIGN-UPDATE-MANIFEST signs only update-manifest-v1.json.'
}
$manifestInfo = Get-Item -LiteralPath $fullManifestPath -Force -ErrorAction Stop
if (($manifestInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $manifestInfo.Length -le 16 -or $manifestInfo.Length -gt 131072) {
    throw 'Update manifest is unsafe or outside the size limit.'
}
$manifestBytes = [IO.File]::ReadAllBytes($fullManifestPath)
$manifestText = (New-Object Text.UTF8Encoding($false, $true)).GetString($manifestBytes)
if ($manifestText.Length -gt 0 -and $manifestText[0] -eq [char]0xFEFF) { throw 'Update manifest must be UTF-8 without BOM.' }
$manifest = $manifestText | ConvertFrom-Json -ErrorAction Stop
$actualFields = @($manifest.PSObject.Properties | ForEach-Object { [string]$_.Name })
if ($actualFields.Count -ne $allowedFields.Count -or @($actualFields | Where-Object { $allowedFields -cnotcontains $_ }).Count -ne 0) {
    throw 'Update manifest contains missing or unknown root fields.'
}
if ([string]$manifest.SchemaVersion -ne '1.0' -or [string]$manifest.Channel -ne 'stable' -or
    [string]$manifest.LatestVersion -ne '5.0.0.0' -or [bool]$manifest.AuthenticodeRequired -ne $true -or
    @($manifest.SignerThumbprints).Count -ne 1 -or
    ([string]$manifest.SignerThumbprints[0]).Replace(' ', '').ToUpperInvariant() -notmatch '^[A-F0-9]{40}$') {
    throw 'Update manifest identity or stable signing policy is invalid.'
}

$certificate = Get-UpdateSigningCertificate
try {
    Assert-UpdateSigningCertificate -Certificate $certificate
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $contentInfo = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$manifestBytes)
    $signedCms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($contentInfo, $true)
    $signer = New-Object Security.Cryptography.Pkcs.CmsSigner -ArgumentList $certificate
    $signer.IncludeOption = [Security.Cryptography.X509Certificates.X509IncludeOption]::EndCertOnly
    $signer.DigestAlgorithm = New-Object Security.Cryptography.Oid('2.16.840.1.101.3.4.2.1')
    $signedCms.ComputeSignature($signer, $false)
    $signatureBytes = $signedCms.Encode()
    if ($signatureBytes.Length -le 64 -or $signatureBytes.Length -gt 65536) { throw 'Generated update signature size is invalid.' }

    $verificationContent = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$manifestBytes)
    $verification = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($verificationContent, $true)
    $verification.Decode($signatureBytes)
    $verification.CheckSignature($true)
    if ($verification.SignerInfos.Count -ne 1 -or
        (Get-UpdateSigningSha256 -Bytes $verification.SignerInfos[0].Certificate.RawData) -ne $expectedCertificateSha256) {
        throw 'Generated update signature did not verify with the pinned publisher.'
    }
    $signaturePath = $fullManifestPath + '.p7s'
    Write-UpdateSignatureAtomically -Path $signaturePath -Bytes $signatureBytes
    Write-Host "SIGNED UPDATE MANIFEST: $fullManifestPath" -ForegroundColor Green
    Write-Host "  Manifest SHA-256: $(Get-UpdateSigningSha256 -Bytes $manifestBytes)"
    Write-Host "  Signature: $signaturePath"
} finally {
    if ($certificate -and $PSCmdlet.ParameterSetName -eq 'Pfx') { $certificate.Dispose() }
}
