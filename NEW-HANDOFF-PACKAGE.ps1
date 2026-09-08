[CmdletBinding()]
param(
    [string]$SourceDirectory = '',
    [Parameter(Mandatory = $true)][string]$DistributionDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$sourceRoot = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\')
$distributionRoot = [IO.Path]::GetFullPath($DistributionDirectory).TrimEnd('\')
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
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
$trackedFiles = @(& $git.Source -C $sourceRoot -c core.quotepath=false ls-files)
if ($LASTEXITCODE -ne 0 -or $trackedFiles.Count -eq 0) { throw 'Không lấy được danh sách tệp Git tracked.' }

foreach ($entry in Get-ChildItem -LiteralPath $distributionRoot -Force) {
    if ($entry.PSIsContainer) { throw "Thư mục phát hành phải phẳng, phát hiện thư mục con: $($entry.Name)" }
    Copy-RegularFile $entry.FullName (Join-Path $releaseRoot $entry.Name)
}

foreach ($relativeGitPath in $trackedFiles) {
    if ([string]::IsNullOrWhiteSpace($relativeGitPath)) { continue }
    $relativeWindowsPath = $relativeGitPath.Replace('/', '\')
    $from = Join-Path $sourceRoot $relativeWindowsPath
    $to = Join-Path $sourceOutputRoot $relativeWindowsPath
    Copy-RegularFile $from $to
}

foreach ($rootVerifier in @('VERIFY-HANDOFF.ps1', 'VERIFY-HANDOFF.cmd')) {
    Copy-RegularFile (Join-Path $sourceRoot $rootVerifier) (Join-Path $outputRoot $rootVerifier)
}

$readmeLines = @(
    'VIETLICENSURE v5.0.0.2 - GÓI BÀN GIAO',
    '',
    '1. Nhấp đúp VERIFY-HANDOFF.cmd để kiểm tra toàn bộ gói.',
    '2. Bản chạy nằm trong thư mục: phát hành',
    '3. Mã nguồn được kiểm soát nằm trong thư mục: mã nguồn',
    '4. Không đổi nội dung hoặc tên tệp trước khi xác minh.',
    '',
    'Các manifest:',
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
