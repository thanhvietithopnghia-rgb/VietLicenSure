[CmdletBinding()]
param(
    [string]$SourceDirectory = '',
    [Parameter(Mandatory = $true)][string]$DistributionDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$QaEvidencePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$sourceRoot = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\')
$distributionRoot = [IO.Path]::GetFullPath($DistributionDirectory).TrimEnd('\')
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$qaEvidenceFullPath = [IO.Path]::GetFullPath($QaEvidencePath)
$releaseRoot = Join-Path $outputRoot 'phát hành'
$sourceOutputRoot = Join-Path $outputRoot 'mã nguồn'
$utf8NoBom = New-Object Text.UTF8Encoding($false)

function Get-PackageSha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Read-PackageJson([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Thiếu ${Label}: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "${Label} không phải JSON hợp lệ: $($_.Exception.Message)" }
}

function Assert-RegularDirectory([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Không tìm thấy ${Label}: $Path" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "${Label} không được là reparse point: $Path" }
}

function Copy-RegularFile([string]$From, [string]$To) {
    $item = Get-Item -LiteralPath $From -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Không sao chép tệp không an toàn: $From" }
    $parent = Split-Path -Parent $To
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $From -Destination $To -Force
}

function Get-RelativePathFromRoot([string]$RootPath, [string]$FullPath) {
    $prefix = [IO.Path]::GetFullPath($RootPath).TrimEnd('\') + '\'
    $normalized = [IO.Path]::GetFullPath($FullPath)
    if (-not $normalized.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Đường dẫn nằm ngoài gốc: $FullPath" }
    return $normalized.Substring($prefix.Length).Replace('\', '/')
}

function Write-HashManifest([string]$Path, [IO.FileInfo[]]$Files, [string]$Comment) {
    $lines = @("# $Comment")
    foreach ($file in @($Files | Sort-Object { Get-RelativePathFromRoot $outputRoot $_.FullName })) {
        $relative = Get-RelativePathFromRoot $outputRoot $file.FullName
        $lines += "$(Get-PackageSha256 $file.FullName)  $relative"
    }
    [IO.File]::WriteAllLines($Path, $lines, $utf8NoBom)
}

Assert-RegularDirectory $sourceRoot 'thư mục mã nguồn'
Assert-RegularDirectory $distributionRoot 'thư mục phát hành'
if (-not (Test-Path -LiteralPath $qaEvidenceFullPath -PathType Leaf)) { throw "Không tìm thấy QA evidence: $qaEvidenceFullPath" }
if ($outputRoot.Equals($sourceRoot, [StringComparison]::OrdinalIgnoreCase) -or $outputRoot.Equals($distributionRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputDirectory phải khác thư mục nguồn và phát hành.' }
if (Test-Path -LiteralPath $outputRoot) {
    $outputItem = Get-Item -LiteralPath $outputRoot -Force
    if (-not $outputItem.PSIsContainer -or ($outputItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'OutputDirectory không phải thư mục thường.' }
    if (@(Get-ChildItem -LiteralPath $outputRoot -Force).Count -gt 0) { throw "OutputDirectory phải mới hoặc rỗng: $outputRoot" }
} else { New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null }
New-Item -ItemType Directory -Path $releaseRoot, $sourceOutputRoot -Force | Out-Null

$git = Get-Command git -ErrorAction Stop
$insideWorkTree = (& $git.Source -C $sourceRoot rev-parse --is-inside-work-tree 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]$insideWorkTree -ne 'true') { throw 'SourceDirectory không phải Git worktree.' }
$status = @(& $git.Source -C $sourceRoot status --porcelain --untracked-files=normal)
if ($LASTEXITCODE -ne 0) { throw 'Không đọc được trạng thái Git.' }
if ($status.Count -gt 0) { throw "Mã nguồn phải sạch trước khi đóng gói. Tệp thay đổi: $($status -join '; ')" }

$distributionVerifier = Join-Path $sourceRoot 'VERIFY-DISTRIBUTION.ps1'
if (-not (Test-Path -LiteralPath $distributionVerifier -PathType Leaf)) { throw 'Thiếu VERIFY-DISTRIBUTION.ps1 trong mã nguồn.' }
& $distributionVerifier -DistributionDirectory $distributionRoot
if ($LASTEXITCODE -ne 0) { throw "Distribution canonical không đạt kiểm tra, mã thoát $LASTEXITCODE." }

$releaseManifest = Read-PackageJson (Join-Path $distributionRoot 'RELEASE-MANIFEST.json') 'RELEASE-MANIFEST.json'
$updateManifest = Read-PackageJson (Join-Path $distributionRoot 'update-manifest-v1.json') 'update-manifest-v1.json'
$provenance = Read-PackageJson (Join-Path $distributionRoot 'OFFICIAL-PROVENANCE-v1.json') 'OFFICIAL-PROVENANCE-v1.json'
$qaEvidence = Read-PackageJson $qaEvidenceFullPath 'QA evidence'
$primaryName = [string]$releaseManifest.PrimaryFileName
$primaryPath = Join-Path $distributionRoot $primaryName
if (-not (Test-Path -LiteralPath $primaryPath -PathType Leaf)) { throw "Thiếu artifact canonical: $primaryName" }
$primaryHash = Get-PackageSha256 $primaryPath
$primaryArtifact = @($releaseManifest.Artifacts | Where-Object { [string]$_.FileName -ceq $primaryName })
if ($primaryArtifact.Count -ne 1 -or [string]$primaryArtifact[0].Sha256 -cne $primaryHash) { throw 'RELEASE-MANIFEST không ghim đúng artifact canonical.' }
if ([string]$updateManifest.DownloadSha256 -cne $primaryHash -or [int64]$updateManifest.DownloadSize -ne [int64](Get-Item -LiteralPath $primaryPath).Length) { throw 'Update manifest không khớp artifact canonical.' }

$sourceSnapshotCommit = ([string]$provenance.SourceSnapshotCommit).Trim().ToLowerInvariant()
$bundleCommit = ([string]$qaEvidence.bundleCommit).Trim().ToLowerInvariant()
if ($sourceSnapshotCommit -notmatch '^[0-9a-f]{40}$' -or $bundleCommit -notmatch '^[0-9a-f]{40}$') { throw 'Source snapshot hoặc bundle commit trong evidence không hợp lệ.' }
if (([string]$qaEvidence.artifactSha256).ToUpperInvariant() -cne $primaryHash -or
    [string]$qaEvidence.buildId -cne [string]$provenance.BuildId -or
    ([string]$qaEvidence.sourceSnapshot).ToLowerInvariant() -cne $sourceSnapshotCommit -or
    [string]$qaEvidence.result -cne 'PASS' -or [int]$qaEvidence.exitCode -ne 0 -or [int]$qaEvidence.errors -ne 0) {
    throw 'QA evidence không PASS hoặc không gắn đúng artifact/build/source canonical.'
}
$resolvedBundleCommit = (& $git.Source -C $sourceRoot rev-parse "$bundleCommit^{commit}" 2>$null | Select-Object -First 1).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $resolvedBundleCommit -cne $bundleCommit) { throw "Không tìm thấy bundle commit trong Git: $bundleCommit" }
& $git.Source -C $sourceRoot merge-base --is-ancestor $sourceSnapshotCommit $bundleCommit 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Source snapshot đã ký không phải tổ tiên của bundle commit.' }

foreach ($entry in Get-ChildItem -LiteralPath $distributionRoot -Force) {
    if ($entry.PSIsContainer) { throw "Thư mục phát hành phải phẳng, phát hiện thư mục con: $($entry.Name)" }
    Copy-RegularFile $entry.FullName (Join-Path $releaseRoot $entry.Name)
}

$sourceArchivePath = Join-Path $outputRoot '.source-archive.zip'
& $git.Source -C $sourceRoot archive --format=zip "--output=$sourceArchivePath" $bundleCommit
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sourceArchivePath -PathType Leaf)) { throw 'Không tạo được source archive từ bundle commit.' }
Expand-Archive -LiteralPath $sourceArchivePath -DestinationPath $sourceOutputRoot -Force
Remove-Item -LiteralPath $sourceArchivePath -Force

# Metadata sinh sau build phải lấy exact-byte từ distribution canonical. Không
# được tái sử dụng bản tracked cũ trong bundle commit.
$canonicalMetadataNames = @(
    'RELEASE-MANIFEST.json', 'SBOM.cdx.json',
    'update-manifest-v1.json', 'update-manifest-v1.json.p7s',
    'OFFICIAL-PROVENANCE-v1.json', 'OFFICIAL-PROVENANCE-v1.json.p7s'
)
foreach ($name in $canonicalMetadataNames) {
    Copy-RegularFile (Join-Path $distributionRoot $name) (Join-Path $sourceOutputRoot $name)
}

# Git archive emits canonical Git bytes. Refresh the legacy subset manifest so
# it describes those staged bytes instead of a CRLF working-tree checkout.
$sourceHashManifestPath = Join-Path $sourceOutputRoot 'SOURCE-SHA256SUMS.txt'
$sourceHashLines = New-Object System.Collections.Generic.List[string]
$sourceHashSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($line in Get-Content -LiteralPath $sourceHashManifestPath -Encoding UTF8) {
    if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?(.+)$') { $sourceHashLines.Add($line); continue }
    $relative = $matches[2].Trim().Replace('/', '\')
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.?(\\|$)' -or -not $sourceHashSeen.Add($relative)) { throw "Đường dẫn không an toàn/lặp trong SOURCE-SHA256SUMS.txt: $relative" }
    $stagedPath = [IO.Path]::GetFullPath((Join-Path $sourceOutputRoot $relative))
    if (-not $stagedPath.StartsWith($sourceOutputRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $stagedPath -PathType Leaf)) { throw "Thiếu tệp nguồn đã ghim: $relative" }
    $sourceHashLines.Add("$(Get-PackageSha256 $stagedPath)  $($relative.Replace('\','/'))")
}
[IO.File]::WriteAllLines($sourceHashManifestPath, $sourceHashLines, $utf8NoBom)

$sourcePackageManifestPath = Join-Path $sourceOutputRoot 'SOURCE-PACKAGE-SHA256SUMS.txt'
$sourcePackageLines = @('# SHA-256 của gói mã nguồn bàn giao; manifest này không tự liệt kê.')
foreach ($file in @(Get-ChildItem -LiteralPath $sourceOutputRoot -Recurse -File -Force | Where-Object { $_.FullName -ne $sourcePackageManifestPath } | Sort-Object FullName)) {
    $relative = Get-RelativePathFromRoot $sourceOutputRoot $file.FullName
    $sourcePackageLines += "$(Get-PackageSha256 $file.FullName)  $relative"
}
[IO.File]::WriteAllLines($sourcePackageManifestPath, $sourcePackageLines, $utf8NoBom)

foreach ($rootVerifier in @('VERIFY-HANDOFF.ps1', 'VERIFY-HANDOFF.cmd')) {
    Copy-RegularFile (Join-Path $sourceRoot $rootVerifier) (Join-Path $outputRoot $rootVerifier)
}
Copy-RegularFile $qaEvidenceFullPath (Join-Path $outputRoot 'QA-EVIDENCE.json')

$authenticode = Get-AuthenticodeSignature -LiteralPath $primaryPath
$timestampThumbprint = if ($authenticode.TimeStamperCertificate) { ([string]$authenticode.TimeStamperCertificate.Thumbprint).Replace(' ', '').ToUpperInvariant() } else { '' }
$holdReasons = New-Object System.Collections.Generic.List[string]
if ([string]$qaEvidence.vmArtifactBound -cne 'PASS') { $holdReasons.Add('ExactHashVmQaMissing') }
$releaseState = if ($holdReasons.Count -eq 0) { 'ReadyForPromotion' } else { 'HOLD' }
$releaseIdentity = [ordered]@{
    SchemaVersion = '1.0'
    State = $releaseState
    HoldReasons = @($holdReasons)
    Product = 'VietLicenSure'
    Version = [string]$releaseManifest.ReleaseVersion
    BuildId = [string]$provenance.BuildId
    BuildDate = [string]$provenance.BuildTime
    Channel = [string]$qaEvidence.channel
    ReleaseStatus = [string]$releaseManifest.ReleaseStatus
    TechnicalTrustMode = 'ManagedSigned'
    ArtifactFile = $primaryName
    ArtifactSha256 = $primaryHash
    ArtifactSize = [int64](Get-Item -LiteralPath $primaryPath).Length
    SignerThumbprint = ([string]$primaryArtifact[0].AuthenticodeThumbprint).Replace(' ', '').ToUpperInvariant()
    TimestampThumbprint = $timestampThumbprint
    SourceSnapshotCommit = $sourceSnapshotCommit
    BundleCommit = $bundleCommit
    ReleaseManifestSha256 = Get-PackageSha256 (Join-Path $distributionRoot 'RELEASE-MANIFEST.json')
    SbomSha256 = Get-PackageSha256 (Join-Path $distributionRoot 'SBOM.cdx.json')
    UpdateManifestSha256 = Get-PackageSha256 (Join-Path $distributionRoot 'update-manifest-v1.json')
    ProvenanceSha256 = Get-PackageSha256 (Join-Path $distributionRoot 'OFFICIAL-PROVENANCE-v1.json')
    QaEvidenceFile = 'QA-EVIDENCE.json'
    QaEvidenceSha256 = Get-PackageSha256 $qaEvidenceFullPath
    QaWarnings = [int]$qaEvidence.warnings
    VmArtifactBound = [string]$qaEvidence.vmArtifactBound
    IndependentReview = [string]$qaEvidence.independentReview
}
[IO.File]::WriteAllText((Join-Path $outputRoot 'RELEASE-IDENTITY.json'), ($releaseIdentity | ConvertTo-Json -Depth 6), $utf8NoBom)

$readmeLines = @(
    'VIETLICENSURE v5.0 - GÓI BÀN GIAO',
    '',
    '1. Nhấp đúp VERIFY-HANDOFF.cmd để kiểm tra toàn bộ gói.',
    '2. Bản chạy nằm trong thư mục: phát hành',
    '3. Mã nguồn được kiểm soát nằm trong thư mục: mã nguồn',
    '4. Không đổi nội dung hoặc tên tệp trước khi xác minh.',
    '',
    'Các manifest:',
    '- RELEASE-IDENTITY.json: danh tính canonical và trạng thái Ready/HOLD',
    '- QA-EVIDENCE.json: kết quả QA gắn với đúng SHA-256 của EXE',
    '- release-files.sha256: toàn bộ thư mục phát hành',
    '- source-files.sha256: toàn bộ thư mục mã nguồn',
    '- package-files.sha256: toàn bộ gói, trừ chính manifest này'
)
[IO.File]::WriteAllLines((Join-Path $outputRoot 'README-BAN-GIAO.txt'), $readmeLines, (New-Object Text.UTF8Encoding($true)))

$releaseFiles = @(Get-ChildItem -LiteralPath $releaseRoot -Recurse -File -Force)
$sourceFiles = @(Get-ChildItem -LiteralPath $sourceOutputRoot -Recurse -File -Force)
Write-HashManifest (Join-Path $outputRoot 'release-files.sha256') $releaseFiles 'SHA-256 của toàn bộ tệp trong thư mục phát hành.'
Write-HashManifest (Join-Path $outputRoot 'source-files.sha256') $sourceFiles 'SHA-256 của toàn bộ tệp trong thư mục mã nguồn.'
$packageManifestPath = Join-Path $outputRoot 'package-files.sha256'
$packageFiles = @(Get-ChildItem -LiteralPath $outputRoot -Recurse -File -Force | Where-Object { $_.FullName -ne $packageManifestPath })
Write-HashManifest $packageManifestPath $packageFiles 'SHA-256 của toàn bộ gói; manifest này không tự liệt kê.'

Write-Host "Đã tạo gói: $outputRoot" -ForegroundColor Cyan
& (Join-Path $outputRoot 'VERIFY-HANDOFF.ps1') -PackageRoot $outputRoot
if ($LASTEXITCODE -ne 0) { throw "Gói vừa tạo không vượt qua hậu kiểm, mã thoát $LASTEXITCODE." }
Write-Host 'GÓI BÀN GIAO ĐẠT HẬU KIỂM.' -ForegroundColor Green
