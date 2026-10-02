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
