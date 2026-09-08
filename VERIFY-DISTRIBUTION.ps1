[CmdletBinding()]
param(
    [string]$DistributionDirectory = '',
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($DistributionDirectory)) { $DistributionDirectory = $PSScriptRoot }
$distributionRoot = [IO.Path]::GetFullPath($DistributionDirectory).TrimEnd('\')
$expectedReleaseVersion = '5.0.0.2'
$expectedBuildId = '5.0.0.2-production-20260908'
$expectedCertificateThumbprint = 'ABE70696679B1D8987A2D5B1F6C1C6909D364CEA'
$expectedCertificateSha256 = 'A42B00D863D4770B47F21FFF756545249D58DD59691AD9E05C02048C104F9FC9'
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) { $failures.Add($Message); Write-Host "[FAIL] $Message" -ForegroundColor Red }
function Add-Warning([string]$Message) { $warnings.Add($Message); Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Add-Pass([string]$Message) { $notes.Add($Message); Write-Host "[PASS] $Message" -ForegroundColor Green }

function Get-Sha256Hex([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-Sha256HexFromBytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Get-PropertyValue($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-JsonFile([string]$Path) {
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { Add-Failure "JSON không hợp lệ: $([IO.Path]::GetFileName($Path)) ($($_.Exception.Message))"; return $null }
}

function Test-SafeFlatFileName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name) -or [IO.Path]::IsPathRooted($Name)) { return $false }
    if ([IO.Path]::GetFileName($Name) -cne $Name) { return $false }
    if ($Name -in @('.', '..') -or $Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $false }
    return $true
}

function Test-ReleaseHashManifest([string]$ManifestPath) {
    $allowed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    [void]$allowed.Add([IO.Path]::GetFileName($ManifestPath))
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        Add-Failure 'Thiếu RELEASE-SHA256SUMS.txt.'
        return $allowed
    }
    foreach ($line in Get-Content -LiteralPath $ManifestPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?(.+)$') {
            Add-Failure "Dòng checksum không hợp lệ: $line"
            continue
        }
        $expectedHash = $matches[1].ToUpperInvariant()
        $name = $matches[2].Trim()
        if (-not (Test-SafeFlatFileName $name) -or -not $allowed.Add($name)) {
            Add-Failure "Tên tệp checksum không an toàn hoặc bị lặp: $name"
            continue
        }
        $path = Join-Path $distributionRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-Failure "Checksum tham chiếu tệp bị thiếu: $name"
            continue
        }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Failure "Tệp checksum không được là reparse point: $name"
            continue
        }
        $actualHash = Get-Sha256Hex $path
        if ($actualHash -cne $expectedHash) { Add-Failure "Sai SHA-256: $name" }
    }
    foreach ($entry in Get-ChildItem -LiteralPath $distributionRoot -Force) {
        if ($entry.PSIsContainer) { Add-Failure "Gói phát hành không được chứa thư mục con: $($entry.Name)"; continue }
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Add-Failure "Gói phát hành chứa reparse point: $($entry.Name)"; continue }
        if (-not $allowed.Contains($entry.Name)) { Add-Failure "Tệp ngoài checksum manifest: $($entry.Name)" }
    }
    if ($allowed.Count -le 2) { Add-Failure 'RELEASE-SHA256SUMS.txt không có đủ mục kiểm tra.' }
    elseif ($failures.Count -eq 0) { Add-Pass "Checksum và tập tệp đóng: $($allowed.Count - 1) tệp" }
    return $allowed
}

function Test-DetachedCmsSignature(
    [string]$ContentName,
    [string]$SignatureName,
    [Security.Cryptography.X509Certificates.X509Certificate2]$PinnedCertificate
) {
    $contentPath = Join-Path $distributionRoot $ContentName
    $signaturePath = Join-Path $distributionRoot $SignatureName
    if (-not (Test-Path -LiteralPath $contentPath -PathType Leaf)) { Add-Failure "Thiếu nội dung CMS: $ContentName"; return }
    if (-not (Test-Path -LiteralPath $signaturePath -PathType Leaf)) { Add-Failure "Thiếu chữ ký CMS: $SignatureName"; return }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $contentBytes = [IO.File]::ReadAllBytes($contentPath)
        $signatureBytes = [IO.File]::ReadAllBytes($signaturePath)
        $contentInfo = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$contentBytes)
        $signedCms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($contentInfo, $true)
        $signedCms.Decode($signatureBytes)
        if ($signedCms.SignerInfos.Count -ne 1) { throw "Số signer không bằng 1: $($signedCms.SignerInfos.Count)" }
        $signer = $signedCms.SignerInfos[0]
        if ($null -eq $signer.Certificate) { throw 'CMS không nhúng chứng thư signer.' }
        if ([string]$signer.DigestAlgorithm.Value -ne '2.16.840.1.101.3.4.2.1') { throw 'CMS không dùng SHA-256.' }
        if ([string]$signer.Certificate.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1') { throw 'Signer CMS không dùng RSA.' }
        $signedCms.CheckSignature($true)
        $actualCertificateHash = Get-Sha256HexFromBytes $signer.Certificate.RawData
        $pinnedCertificateHash = Get-Sha256HexFromBytes $PinnedCertificate.RawData
        if ($actualCertificateHash -cne $pinnedCertificateHash) { throw "Signer CMS không khớp chứng thư công bố ($actualCertificateHash)." }
        Add-Pass "CMS exact-byte: $ContentName"
    } catch { Add-Failure "Chữ ký CMS không hợp lệ cho $ContentName ($($_.Exception.Message))" }
}

function Test-ManagedSignerTrustException([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate) {
    if ($null -eq $Certificate -or $Certificate.Subject -cne $Certificate.Issuer) { return $false }
    $now = Get-Date
    if ($now -lt $Certificate.NotBefore -or $now -gt $Certificate.NotAfter) { return $false }
    $chain = New-Object Security.Cryptography.X509Certificates.X509Chain
    try {
        $chain.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        $chain.ChainPolicy.VerificationFlags = [Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag
        $built = $chain.Build($Certificate)
        if ($built) { return $true }
        $statuses = @($chain.ChainStatus | ForEach-Object { $_.Status })
        return [bool]($statuses.Count -gt 0 -and @($statuses | Where-Object {
            $_ -ne [Security.Cryptography.X509Certificates.X509ChainStatusFlags]::UntrustedRoot
        }).Count -eq 0)
    } finally { $chain.Dispose() }
}

Write-Host "VietLicenSure - xác minh độc lập gói phát hành" -ForegroundColor Cyan
Write-Host "Thư mục: $distributionRoot"

if (-not (Test-Path -LiteralPath $distributionRoot -PathType Container)) {
    Add-Failure "Không tìm thấy thư mục phát hành: $distributionRoot"
} else {
    try { [void](Test-ReleaseHashManifest (Join-Path $distributionRoot 'RELEASE-SHA256SUMS.txt')) }
    catch { Add-Failure "Không thể kiểm tra checksum ($($_.Exception.Message))" }
}

$requiredNames = @(
    'RELEASE-MANIFEST.json', 'SBOM.cdx.json', 'update-manifest-v1.json', 'update-manifest-v1.json.p7s',
    'OFFICIAL-PROVENANCE-v1.json', 'OFFICIAL-PROVENANCE-v1.json.p7s',
    'software-license-catalog-v1.0.json', 'software-license-catalog-v1.0.json.p7s',
    'tool-assistant-knowledge-v1.1.json', 'tool-assistant-knowledge-v1.1.json.p7s',
    'CONTENT-SIGNING-CERTIFICATE.cer', 'VERIFY-DISTRIBUTION.ps1', 'VERIFY-RELEASE.cmd'
)
foreach ($name in $requiredNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $distributionRoot $name) -PathType Leaf)) { Add-Failure "Thiếu tệp bắt buộc: $name" }
}

if (Test-Path -LiteralPath $distributionRoot -PathType Container) {
    foreach ($jsonFile in Get-ChildItem -LiteralPath $distributionRoot -Filter '*.json' -File -Force) {
        try { $null = Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
        catch { Add-Failure "JSON không đọc được: $($jsonFile.Name) ($($_.Exception.Message))" }
    }
}

$certificate = $null
$certificatePath = Join-Path $distributionRoot 'CONTENT-SIGNING-CERTIFICATE.cer'
if (Test-Path -LiteralPath $certificatePath -PathType Leaf) {
    try {
        $certificateBytes = [IO.File]::ReadAllBytes($certificatePath)
        $certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$certificateBytes)
        if ($certificate.HasPrivateKey) { Add-Failure 'Tệp CER công bố không được chứa private key.' }
        if ([string]$certificate.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1') { Add-Failure 'Chứng thư công bố không dùng RSA.' }
        $hasCodeSigningEku = $false
        foreach ($extension in @($certificate.Extensions)) {
            if ($extension.Oid.Value -eq '2.5.29.37') {
                $eku = New-Object Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension -ArgumentList @($extension, [bool]$extension.Critical)
                foreach ($oid in @($eku.EnhancedKeyUsages)) { if ($oid.Value -eq '1.3.6.1.5.5.7.3.3') { $hasCodeSigningEku = $true } }
            }
        }
        if (-not $hasCodeSigningEku) { Add-Failure 'Chứng thư công bố thiếu EKU Code Signing.' }
        if ((Get-Date) -lt $certificate.NotBefore) { Add-Failure 'Chứng thư công bố chưa có hiệu lực.' }
        elseif ((Get-Date) -gt $certificate.NotAfter) { Add-Warning 'Chứng thư công bố đã hết hạn; chữ ký CMS vẫn được kiểm tra mật mã nhưng cần đối chiếu thời điểm phát hành.' }
        $publishedCertificateSha256 = Get-Sha256HexFromBytes $certificate.RawData
        $publishedCertificateThumbprint = ([string]$certificate.Thumbprint).Replace(' ', '').ToUpperInvariant()
        if ($publishedCertificateSha256 -cne $expectedCertificateSha256 -or $publishedCertificateThumbprint -cne $expectedCertificateThumbprint) {
            Add-Failure 'Chứng thư công bố không khớp trust anchor được ghim cứng trong verifier.'
        } else { Add-Pass "Chứng thư công bố khớp trust anchor: SHA-256 $publishedCertificateSha256" }
    } catch { Add-Failure "Không đọc được CONTENT-SIGNING-CERTIFICATE.cer ($($_.Exception.Message))" }
}

$releaseManifest = Read-JsonFile (Join-Path $distributionRoot 'RELEASE-MANIFEST.json')
$provenance = Read-JsonFile (Join-Path $distributionRoot 'OFFICIAL-PROVENANCE-v1.json')
$updateManifest = Read-JsonFile (Join-Path $distributionRoot 'update-manifest-v1.json')
$sbom = Read-JsonFile (Join-Path $distributionRoot 'SBOM.cdx.json')

if ($null -ne $certificate -and $null -ne $provenance) {
    $certificateSha256 = Get-Sha256HexFromBytes $certificate.RawData
    $certificateThumbprint = ([string]$certificate.Thumbprint).Replace(' ', '').ToUpperInvariant()
    if ([string](Get-PropertyValue $provenance 'SignerCertificateSha256') -cne $certificateSha256) { Add-Failure 'SHA-256 chứng thư không khớp provenance.' }
    if (([string](Get-PropertyValue $provenance 'SignerThumbprint')).Replace(' ', '').ToUpperInvariant() -cne $certificateThumbprint) { Add-Failure 'Thumbprint chứng thư không khớp provenance.' }
    if ($failures.Count -eq 0) { Add-Pass 'Chứng thư công bố khớp hai fingerprint trong provenance.' }

    Test-DetachedCmsSignature 'OFFICIAL-PROVENANCE-v1.json' 'OFFICIAL-PROVENANCE-v1.json.p7s' $certificate
    Test-DetachedCmsSignature 'software-license-catalog-v1.0.json' 'software-license-catalog-v1.0.json.p7s' $certificate
    Test-DetachedCmsSignature 'tool-assistant-knowledge-v1.1.json' 'tool-assistant-knowledge-v1.1.json.p7s' $certificate
    Test-DetachedCmsSignature 'update-manifest-v1.json' 'update-manifest-v1.json.p7s' $certificate
}

$primaryPath = $null
$primaryHash = ''
if ($null -ne $releaseManifest) {
    $releaseVersion = [string](Get-PropertyValue $releaseManifest 'ReleaseVersion')
    $primaryName = [string](Get-PropertyValue $releaseManifest 'PrimaryFileName')
    if ($releaseVersion -cne $expectedReleaseVersion) { Add-Failure "ReleaseVersion không đúng bản verifier yêu cầu: $releaseVersion" }
    if (-not (Test-SafeFlatFileName $primaryName)) { Add-Failure "PrimaryFileName không an toàn: $primaryName" }
    else {
        $primaryPath = Join-Path $distributionRoot $primaryName
        if (-not (Test-Path -LiteralPath $primaryPath -PathType Leaf)) { Add-Failure "Thiếu EXE chính: $primaryName" }
        else { $primaryHash = Get-Sha256Hex $primaryPath }
    }

    $artifacts = @(Get-PropertyValue $releaseManifest 'Artifacts')
    $primaryArtifact = @($artifacts | Where-Object { [string](Get-PropertyValue $_ 'FileName') -ceq $primaryName })
    if ($primaryArtifact.Count -ne 1) { Add-Failure 'RELEASE-MANIFEST phải có đúng một artifact cho EXE chính.' }
    elseif ($primaryHash -and [string](Get-PropertyValue $primaryArtifact[0] 'Sha256') -cne $primaryHash) { Add-Failure 'Hash EXE không khớp RELEASE-MANIFEST.' }
    elseif ($null -ne $certificate) {
        if (([string](Get-PropertyValue $primaryArtifact[0] 'AuthenticodeThumbprint')).Replace(' ', '').ToUpperInvariant() -cne $expectedCertificateThumbprint) { Add-Failure 'Artifact metadata ghi sai signer Authenticode.' }
        if ([bool](Get-PropertyValue $primaryArtifact[0] 'AuthenticodeTimestamped') -ne $true) { Add-Failure 'Artifact metadata không xác nhận timestamp Authenticode.' }
    }

    $sbomMetadata = Get-PropertyValue $releaseManifest 'Sbom'
    $sbomName = [string](Get-PropertyValue $sbomMetadata 'FileName')
    if ($sbomName -cne 'SBOM.cdx.json') { Add-Failure 'RELEASE-MANIFEST trỏ sai tệp SBOM.' }
    elseif ((Get-Sha256Hex (Join-Path $distributionRoot $sbomName)) -cne [string](Get-PropertyValue $sbomMetadata 'Sha256')) { Add-Failure 'Hash SBOM không khớp RELEASE-MANIFEST.' }

    if ($null -ne $provenance) {
        if ([string](Get-PropertyValue $provenance 'ReleaseVersion') -cne $releaseVersion) { Add-Failure 'Phiên bản provenance không khớp release manifest.' }
        if ([string](Get-PropertyValue $provenance 'BuildId') -cne $expectedBuildId) { Add-Failure 'BuildId provenance không đúng bản verifier yêu cầu.' }
        $official = Get-PropertyValue $releaseManifest 'OfficialBuildProvenance'
        if ([string](Get-PropertyValue $official 'BuildId') -cne [string](Get-PropertyValue $provenance 'BuildId')) { Add-Failure 'BuildId provenance không khớp release manifest.' }
        if ([string](Get-PropertyValue $official 'ManifestFile') -cne 'OFFICIAL-PROVENANCE-v1.json' -or [string](Get-PropertyValue $official 'SignatureFile') -cne 'OFFICIAL-PROVENANCE-v1.json.p7s') { Add-Failure 'RELEASE-MANIFEST trỏ sai cặp provenance/CMS.' }
    }

    if ($null -ne $updateManifest) {
        if ([string](Get-PropertyValue $updateManifest 'LatestVersion') -cne $releaseVersion) { Add-Failure 'Phiên bản update manifest không khớp release manifest.' }
        if ([string](Get-PropertyValue $updateManifest 'DownloadSha256') -cne $primaryHash) { Add-Failure 'Hash tải xuống trong update manifest không khớp EXE.' }
        if ($null -ne $primaryPath -and [long](Get-PropertyValue $updateManifest 'DownloadSize') -ne (Get-Item -LiteralPath $primaryPath).Length) { Add-Failure 'Kích thước tải xuống trong update manifest không khớp EXE.' }
        if ([bool](Get-PropertyValue $updateManifest 'AuthenticodeRequired') -ne $true) { Add-Failure 'Update manifest phải yêu cầu Authenticode.' }
        if ($null -ne $certificate) {
            $pins = @((Get-PropertyValue $updateManifest 'SignerThumbprints') | ForEach-Object { ([string]$_).Replace(' ', '').ToUpperInvariant() })
            if ($pins -notcontains ([string]$certificate.Thumbprint).Replace(' ', '').ToUpperInvariant()) { Add-Failure 'Update manifest không ghim signer Authenticode đã công bố.' }
        }
    }

    if ($null -ne $sbom) {
        if ([string](Get-PropertyValue $sbom 'bomFormat') -cne 'CycloneDX' -or [string](Get-PropertyValue $sbom 'specVersion') -cne '1.5') { Add-Failure 'SBOM không phải CycloneDX 1.5.' }
        $metadata = Get-PropertyValue $sbom 'metadata'
        $component = Get-PropertyValue $metadata 'component'
        if ([string](Get-PropertyValue $component 'version') -cne $releaseVersion) { Add-Failure 'Phiên bản component trong SBOM không khớp.' }
        $sbomHashes = @(Get-PropertyValue $component 'hashes')
        $sbomPrimaryHash = @($sbomHashes | Where-Object { [string](Get-PropertyValue $_ 'alg') -ceq 'SHA-256' } | ForEach-Object { [string](Get-PropertyValue $_ 'content') })
        if ($sbomPrimaryHash.Count -ne 1 -or $sbomPrimaryHash[0] -cne $primaryHash) { Add-Failure 'SBOM không ghim đúng SHA-256 của EXE.' }
        if ($null -ne $provenance) {
            $properties = @(Get-PropertyValue $component 'properties')
            $sourceCommit = @($properties | Where-Object { [string](Get-PropertyValue $_ 'name') -ceq 'tool:sourceSnapshotCommit' } | ForEach-Object { [string](Get-PropertyValue $_ 'value') })
            if ($sourceCommit.Count -ne 1 -or $sourceCommit[0] -cne [string](Get-PropertyValue $provenance 'SourceSnapshotCommit')) { Add-Failure 'SBOM không khớp source snapshot trong provenance.' }
        }
    }

    if ($null -ne $primaryPath -and $null -ne $certificate) {
        try {
            $signature = Get-AuthenticodeSignature -FilePath $primaryPath
            $status = [string]$signature.Status
            if ($null -eq $signature.SignerCertificate) { Add-Failure 'EXE không có signer Authenticode.' }
            else {
                $signerSha256 = Get-Sha256HexFromBytes $signature.SignerCertificate.RawData
                $signerThumbprint = ([string]$signature.SignerCertificate.Thumbprint).Replace(' ', '').ToUpperInvariant()
                if ($signerSha256 -cne (Get-Sha256HexFromBytes $certificate.RawData) -or $signerThumbprint -cne ([string]$certificate.Thumbprint).Replace(' ', '').ToUpperInvariant()) { Add-Failure 'Signer Authenticode không khớp chứng thư công bố.' }
            }
            $releaseStatus = [string](Get-PropertyValue $releaseManifest 'ReleaseStatus')
            if ($status -ceq 'Valid') { Add-Pass 'Authenticode hợp lệ trên máy kiểm tra.' }
            elseif ($status -ceq 'UnknownError' -and $releaseStatus -ceq 'ManagedSigned' -and $null -ne $signature.SignerCertificate -and (Test-ManagedSignerTrustException $signature.SignerCertificate)) { Add-Warning 'Authenticode có chữ ký ghim đúng; kiểm tra chain chỉ còn lỗi UntrustedRoot của chứng thư tự ký ManagedSigned.' }
            else { Add-Failure "Trạng thái Authenticode không chấp nhận: $status ($($signature.StatusMessage))" }
            if ($null -eq $signature.TimeStamperCertificate) { Add-Failure 'Authenticode không có timestamp certificate.' }
            else { Add-Pass "Timestamp Authenticode: $($signature.TimeStamperCertificate.Subject)" }
        } catch { Add-Failure "Không kiểm tra được Authenticode ($($_.Exception.Message))" }
    }
}

if ($null -ne $certificate) { $certificate.Dispose() }

$summary = "KẾT QUẢ: $($failures.Count) lỗi / $($warnings.Count) cảnh báo / $($notes.Count) mục đạt"
Write-Host ''
if ($failures.Count -eq 0) { Write-Host $summary -ForegroundColor Green }
else { Write-Host $summary -ForegroundColor Red }
if ($warnings.Count -gt 0) { Write-Host 'Cảnh báo không làm thay đổi tính toàn vẹn mật mã; xem chính sách ManagedSigned trong RELEASE-VERIFICATION-v5.0.md.' -ForegroundColor Yellow }

if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    try {
        $logFullPath = [IO.Path]::GetFullPath($LogPath)
        $logLines = @(
            "VietLicenSure distribution verification",
            "CheckedAt: $([DateTime]::UtcNow.ToString('o'))",
            "Directory: $distributionRoot",
            $summary
        )
        $logLines += @($notes | ForEach-Object { "PASS: $_" })
        $logLines += @($warnings | ForEach-Object { "WARN: $_" })
        $logLines += @($failures | ForEach-Object { "FAIL: $_" })
        [IO.File]::WriteAllLines($logFullPath, $logLines, (New-Object Text.UTF8Encoding($false)))
        Write-Host "Log: $logFullPath"
    } catch { Write-Host "Không ghi được log: $($_.Exception.Message)" -ForegroundColor Yellow }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
