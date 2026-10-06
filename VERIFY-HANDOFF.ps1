[CmdletBinding()]
param(
    [string]$PackageRoot = '',
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($PackageRoot)) { $PackageRoot = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')
$rootPrefix = $root + '\'
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$passes = New-Object System.Collections.Generic.List[string]

function Add-HandoffFailure([string]$Message) { $failures.Add($Message); Write-Host "[FAIL] $Message" -ForegroundColor Red }
function Add-HandoffWarning([string]$Message) { $warnings.Add($Message); Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Add-HandoffPass([string]$Message) { $passes.Add($Message); Write-Host "[PASS] $Message" -ForegroundColor Green }

function Get-HandoffSha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Read-HandoffJson([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-HandoffFailure "Thiếu ${Label}: $Path"
        return $null
    }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Add-HandoffFailure "${Label} không phải JSON hợp lệ: $($_.Exception.Message)"
        return $null
    }
}

function Test-ExactFilePair([string]$Left, [string]$Right, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Left -PathType Leaf) -or -not (Test-Path -LiteralPath $Right -PathType Leaf)) {
        Add-HandoffFailure "Thiếu tệp để đối chiếu exact-byte: $Label"
        return
    }
    $leftItem = Get-Item -LiteralPath $Left
    $rightItem = Get-Item -LiteralPath $Right
    if ($leftItem.Length -ne $rightItem.Length -or (Get-HandoffSha256 $Left) -cne (Get-HandoffSha256 $Right)) {
        Add-HandoffFailure "Metadata nguồn/phát hành không khớp exact-byte: $Label"
    } else { Add-HandoffPass "Metadata exact-byte: $Label" }
}

function Test-NestedSourceManifest([string]$SourceRoot, [string]$ManifestName, [switch]$ClosedSet) {
    $manifestPath = Join-Path $SourceRoot $ManifestName
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { Add-HandoffFailure "Thiếu manifest nguồn: $ManifestName"; return }
    $sourcePrefix = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\') + '\'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in Get-Content -LiteralPath $manifestPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?(.+)$') { Add-HandoffFailure "Dòng không hợp lệ trong ${ManifestName}: $line"; continue }
        $expected = $matches[1].ToUpperInvariant()
        $relative = $matches[2].Trim().Replace('/', '\')
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.?(\\|$)' -or -not $seen.Add($relative)) { Add-HandoffFailure "Đường dẫn không an toàn/lặp trong ${ManifestName}: $relative"; continue }
        $path = [IO.Path]::GetFullPath((Join-Path $SourceRoot $relative))
        if (-not $path.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-HandoffFailure "Thiếu tệp trong ${ManifestName}: $relative"; continue }
        if ((Get-HandoffSha256 $path) -cne $expected) { Add-HandoffFailure "Sai SHA-256 trong ${ManifestName}: $relative" }
    }
    if ($ClosedSet) {
        foreach ($file in Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force) {
            if ($file.FullName -eq $manifestPath) { continue }
            $relative = $file.FullName.Substring($sourcePrefix.Length)
            if (-not $seen.Contains($relative)) { Add-HandoffFailure "Tệp ngoài ${ManifestName}: $relative" }
        }
    }
    if ($seen.Count -eq 0) { Add-HandoffFailure "Manifest nguồn rỗng: $ManifestName" }
    else { Add-HandoffPass "${ManifestName}: $($seen.Count) tệp" }
}

function Get-PackageRelativePath([string]$FullPath) {
    $normalized = [IO.Path]::GetFullPath($FullPath)
    if (-not $normalized.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Đường dẫn nằm ngoài gói: $FullPath" }
    return $normalized.Substring($rootPrefix.Length).Replace('\', '/')
}

function Test-SafePackagePath([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name) -or [IO.Path]::IsPathRooted($Name)) { return $false }
    $normalized = $Name.Replace('/', '\')
    if ($normalized -match '(^|\\)\.\.?($|\\)') { return $false }
    try {
        $full = [IO.Path]::GetFullPath((Join-Path $root $normalized))
        return $full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Test-PackageManifest(
    [string]$ManifestName,
    [string]$RequiredPrefix,
    [string]$ClosedDirectory,
    [switch]$PackageWide
) {
    $manifestPath = Join-Path $root $ManifestName
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-HandoffFailure "Thiếu manifest: $ManifestName"
        return $seen
    }
    foreach ($line in Get-Content -LiteralPath $manifestPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?(.+)$') {
            Add-HandoffFailure "Dòng không hợp lệ trong ${ManifestName}: $line"
            continue
        }
        $expected = $matches[1].ToUpperInvariant()
        $name = $matches[2].Trim().Replace('\', '/')
        if (-not (Test-SafePackagePath $name) -or -not $seen.Add($name)) {
            Add-HandoffFailure "Đường dẫn không an toàn hoặc bị lặp trong ${ManifestName}: $name"
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($RequiredPrefix) -and -not $name.StartsWith($RequiredPrefix.TrimEnd('/') + '/', [StringComparison]::OrdinalIgnoreCase)) {
            Add-HandoffFailure "Đường dẫn nằm ngoài $RequiredPrefix trong ${ManifestName}: $name"
            continue
        }
        if ($PackageWide -and $name.Equals('package-files.sha256', [StringComparison]::OrdinalIgnoreCase)) {
            Add-HandoffFailure 'package-files.sha256 không được tự liệt kê chính nó.'
            continue
        }
        $path = [IO.Path]::GetFullPath((Join-Path $root $name.Replace('/', '\')))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-HandoffFailure "Thiếu tệp: $name"; continue }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Add-HandoffFailure "Không chấp nhận reparse point: $name"; continue }
        if ((Get-HandoffSha256 $path) -cne $expected) { Add-HandoffFailure "Sai SHA-256: $name" }
    }

    $scanRoot = if ($PackageWide) { $root } else { Join-Path $root $ClosedDirectory }
    if (-not (Test-Path -LiteralPath $scanRoot -PathType Container)) {
        Add-HandoffFailure "Thiếu thư mục: $ClosedDirectory"
        return $seen
    }
    foreach ($file in Get-ChildItem -LiteralPath $scanRoot -Recurse -File -Force) {
        $relative = Get-PackageRelativePath $file.FullName
        if ($PackageWide -and $relative.Equals('package-files.sha256', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Add-HandoffFailure "Không chấp nhận reparse point: $relative" }
        elseif (-not $seen.Contains($relative)) { Add-HandoffFailure "Tệp ngoài ${ManifestName}: $relative" }
    }
    foreach ($directory in Get-ChildItem -LiteralPath $scanRoot -Recurse -Directory -Force) {
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Add-HandoffFailure "Không chấp nhận thư mục reparse point: $(Get-PackageRelativePath $directory.FullName)" }
    }
    if ($seen.Count -eq 0) { Add-HandoffFailure "Manifest rỗng: $ManifestName" }
    else { Add-HandoffPass "${ManifestName}: $($seen.Count) tệp" }
    return $seen
}

Write-Host 'VietLicenSure - xác minh gói bàn giao' -ForegroundColor Cyan
Write-Host "Thư mục gốc: $root"

if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    Add-HandoffFailure "Không tìm thấy thư mục gói: $root"
} else {
    [void](Test-PackageManifest 'release-files.sha256' 'phát hành' 'phát hành')
    [void](Test-PackageManifest 'source-files.sha256' 'mã nguồn' 'mã nguồn')
    [void](Test-PackageManifest 'package-files.sha256' '' '' -PackageWide)
}

$distributionVerifier = Join-Path $root 'phát hành\VERIFY-DISTRIBUTION.ps1'
if (-not (Test-Path -LiteralPath $distributionVerifier -PathType Leaf)) {
    Add-HandoffFailure 'Thiếu bộ xác minh độc lập trong thư mục phát hành.'
} elseif ($failures.Count -eq 0) {
    Write-Host ''
    & $distributionVerifier -DistributionDirectory (Join-Path $root 'phát hành')
    if ($LASTEXITCODE -ne 0) { Add-HandoffFailure "Bộ xác minh phát hành thất bại, mã thoát $LASTEXITCODE." }
    else { Add-HandoffPass 'Chuỗi xác minh nội bộ của thư mục phát hành đạt.' }
}

if ($failures.Count -eq 0) {
    $identityPath = Join-Path $root 'RELEASE-IDENTITY.json'
    $qaPath = Join-Path $root 'QA-EVIDENCE.json'
    $releaseRoot = Join-Path $root 'phát hành'
    $sourceRoot = Join-Path $root 'mã nguồn'
    $identity = Read-HandoffJson $identityPath 'RELEASE-IDENTITY.json'
    $qa = Read-HandoffJson $qaPath 'QA-EVIDENCE.json'
    $releaseManifest = Read-HandoffJson (Join-Path $releaseRoot 'RELEASE-MANIFEST.json') 'RELEASE-MANIFEST.json'
    $updateManifest = Read-HandoffJson (Join-Path $releaseRoot 'update-manifest-v1.json') 'update-manifest-v1.json'
    $provenance = Read-HandoffJson (Join-Path $releaseRoot 'OFFICIAL-PROVENANCE-v1.json') 'OFFICIAL-PROVENANCE-v1.json'
    if ($null -ne $identity -and $null -ne $qa -and $null -ne $releaseManifest -and $null -ne $updateManifest -and $null -ne $provenance) {
        try {
            $artifactName = [string]$releaseManifest.PrimaryFileName
            $artifactPath = Join-Path $releaseRoot $artifactName
            if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { throw "Thiếu artifact canonical: $artifactName" }
            $artifactItem = Get-Item -LiteralPath $artifactPath
            $artifactHash = Get-HandoffSha256 $artifactPath
            $artifactRows = @($releaseManifest.Artifacts | Where-Object { [string]$_.FileName -ceq $artifactName })
            if ($artifactRows.Count -ne 1) { throw 'RELEASE-MANIFEST phải có đúng một artifact canonical.' }
            $artifactRow = $artifactRows[0]

            $checks = [ordered]@{
                'identity schema' = ([string]$identity.SchemaVersion -ceq '1.0')
                'identity state' = ([string]$identity.State -ceq 'ReadyForPromotion')
                'identity product/version' = ([string]$identity.Product -ceq 'VietLicenSure' -and [string]$identity.Version -ceq [string]$releaseManifest.ReleaseVersion)
                'identity build/date' = ([string]$identity.BuildId -ceq [string]$provenance.BuildId -and [string]$identity.BuildDate -ceq [string]$provenance.BuildTime)
                'identity release status' = ([string]$identity.ReleaseStatus -ceq [string]$releaseManifest.ReleaseStatus)
                'identity trust mode' = ([string]$identity.TechnicalTrustMode -ceq 'ManagedSigned')
                'artifact filename/hash/size' = ([string]$identity.ArtifactFile -ceq $artifactName -and [string]$identity.ArtifactSha256 -ceq $artifactHash -and [int64]$identity.ArtifactSize -eq $artifactItem.Length)
                'release artifact hash' = ([string]$artifactRow.Sha256 -ceq $artifactHash)
                'update artifact hash/size' = ([string]$updateManifest.DownloadSha256 -ceq $artifactHash -and [int64]$updateManifest.DownloadSize -eq $artifactItem.Length)
                'signer identity' = ([string]$identity.SignerThumbprint -ceq ([string]$artifactRow.AuthenticodeThumbprint).Replace(' ', '').ToUpperInvariant())
                'source snapshot' = ([string]$identity.SourceSnapshotCommit -ceq ([string]$provenance.SourceSnapshotCommit).ToLowerInvariant() -and [string]$qa.sourceSnapshot -ceq [string]$identity.SourceSnapshotCommit)
                'bundle commit' = ([string]$identity.BundleCommit -ceq ([string]$qa.bundleCommit).ToLowerInvariant())
                'QA PASS' = ([string]$qa.result -ceq 'PASS' -and [int]$qa.exitCode -eq 0 -and [int]$qa.errors -eq 0)
                'QA artifact/build' = ([string]$qa.artifactSha256 -ceq $artifactHash -and [string]$qa.buildId -ceq [string]$identity.BuildId)
                'VM artifact-bound evidence' = ([string]$identity.VmArtifactBound -ceq [string]$qa.vmArtifactBound -and [string]$qa.vmArtifactBound -ceq 'PASS')
                'independent review disclosure' = ([string]$identity.IndependentReview -ceq [string]$qa.independentReview)
                'QA evidence hash' = ([string]$identity.QaEvidenceFile -ceq 'QA-EVIDENCE.json' -and [string]$identity.QaEvidenceSha256 -ceq (Get-HandoffSha256 $qaPath))
                'release manifest hash' = ([string]$identity.ReleaseManifestSha256 -ceq (Get-HandoffSha256 (Join-Path $releaseRoot 'RELEASE-MANIFEST.json')))
                'SBOM hash' = ([string]$identity.SbomSha256 -ceq (Get-HandoffSha256 (Join-Path $releaseRoot 'SBOM.cdx.json')))
                'update manifest hash' = ([string]$identity.UpdateManifestSha256 -ceq (Get-HandoffSha256 (Join-Path $releaseRoot 'update-manifest-v1.json')))
                'provenance hash' = ([string]$identity.ProvenanceSha256 -ceq (Get-HandoffSha256 (Join-Path $releaseRoot 'OFFICIAL-PROVENANCE-v1.json')))
            }
            foreach ($entry in $checks.GetEnumerator()) {
                if (-not $entry.Value) { Add-HandoffFailure "Danh tính phát hành không khớp: $($entry.Key)" }
            }
            if ($failures.Count -eq 0) { Add-HandoffPass 'Danh tính artifact/QA/source/bundle khớp canonical.' }

            foreach ($name in @('RELEASE-MANIFEST.json','SBOM.cdx.json','update-manifest-v1.json','update-manifest-v1.json.p7s','OFFICIAL-PROVENANCE-v1.json','OFFICIAL-PROVENANCE-v1.json.p7s')) {
                Test-ExactFilePair (Join-Path $releaseRoot $name) (Join-Path $sourceRoot $name) $name
            }
            Test-NestedSourceManifest $sourceRoot 'SOURCE-SHA256SUMS.txt'
            Test-NestedSourceManifest $sourceRoot 'SOURCE-PACKAGE-SHA256SUMS.txt' -ClosedSet
            if (Test-Path -LiteralPath (Join-Path $sourceRoot '.git')) { Add-HandoffFailure 'Gói mã nguồn không được chứa .git.' }
            else { Add-HandoffPass 'Gói mã nguồn không chứa .git.' }
        } catch { Add-HandoffFailure "Không xác minh được danh tính phát hành: $($_.Exception.Message)" }
    }
}

$summary = "KẾT QUẢ BÀN GIAO: $($failures.Count) lỗi / $($warnings.Count) cảnh báo / $($passes.Count) mục đạt"
Write-Host ''
if ($failures.Count -eq 0) { Write-Host $summary -ForegroundColor Green }
else { Write-Host $summary -ForegroundColor Red }

if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    try {
        $logFullPath = [IO.Path]::GetFullPath($LogPath)
        $lines = @(
            'VietLicenSure handoff verification',
            "CheckedAt: $([DateTime]::UtcNow.ToString('o'))",
            "PackageRoot: $root",
            $summary
        )
        $lines += @($passes | ForEach-Object { "PASS: $_" })
        $lines += @($warnings | ForEach-Object { "WARN: $_" })
        $lines += @($failures | ForEach-Object { "FAIL: $_" })
        [IO.File]::WriteAllLines($logFullPath, $lines, (New-Object Text.UTF8Encoding($false)))
        Write-Host "Log: $logFullPath"
    } catch { Add-HandoffWarning "Không ghi được log: $($_.Exception.Message)" }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
