Set-StrictMode -Version 2.0

function Get-ToolSourceManifestSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Manifest source must be a regular file: $Path"
    }
    $stream = [IO.File]::OpenRead($item.FullName)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() }
        finally { $algorithm.Dispose() }
    } finally { $stream.Dispose() }
}

function Resolve-ToolSourceManifestEntry {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $root = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\')
    $relative = $RelativePath.Trim().Replace('/', '\')
    $unsafeSegments = @($relative.Split([char]'\') | Where-Object { $_ -eq '.' -or $_ -eq '..' })
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $unsafeSegments.Count -gt 0) {
        throw "Unsafe source-manifest path: $RelativePath"
    }
    $fullPath = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $fullPath.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Source-manifest path escapes its root: $RelativePath"
    }
    return $fullPath
}

function Test-ToolSourcePackageExcludedPath {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $rootPrefix = [IO.Path]::GetFullPath($RootPath).TrimEnd('\') + '\'
    $normalized = [IO.Path]::GetFullPath($FullPath)
    if (-not $normalized.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $relative = $normalized.Substring($rootPrefix.Length).Replace('\', '/')
    $firstSegment = @($relative.Split('/'))[0]
    return (
        $firstSegment -eq '.git' -or
        $firstSegment -eq 'test' -or
        $firstSegment -match '^dist(?:-[^/]+)?$' -or
        $firstSegment -match '^release-upload(?:-[^/]+)?$' -or
        $firstSegment -match '^verify-archive(?:-[^/]+)?$'
    )
}

function Update-ToolSourceSubsetHashManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$ManifestName
    )

    $root = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\')
    $manifestPath = Join-Path $root $ManifestName
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing source manifest: $ManifestName" }
    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $output = New-Object System.Collections.Generic.List[string]
    $entryCount = 0
    foreach ($line in Get-Content -LiteralPath $manifestPath -Encoding UTF8) {
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?(.+)$') {
            [void]$output.Add($line)
            continue
        }
        $relative = $matches[2].Trim().Replace('\', '/')
        if (-not $seen.Add($relative)) { throw "Duplicate source-manifest path in ${ManifestName}: $relative" }
        $fullPath = Resolve-ToolSourceManifestEntry -SourceDirectory $root -RelativePath $relative
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Missing file pinned by ${ManifestName}: $relative" }
        [void]$output.Add("$(Get-ToolSourceManifestSha256 $fullPath)  $relative")
        $entryCount++
    }
    if ($entryCount -eq 0) { throw "Source manifest has no hash entries: $ManifestName" }
    [IO.File]::WriteAllLines($manifestPath, $output, $utf8NoBom)
    return $entryCount
}

function Update-ToolSourcePackageHashManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [string]$ManifestName = 'SOURCE-PACKAGE-SHA256SUMS.txt'
    )

    $root = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\')
    $rootPrefix = $root + '\'
    $manifestPath = Join-Path $root $ManifestName
    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('# SHA-256 closed set for the source handoff; this manifest does not list itself.')
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
        $_.FullName -ne $manifestPath -and
        -not (Test-ToolSourcePackageExcludedPath -RootPath $root -FullPath $_.FullName)
    } | Sort-Object { $_.FullName.Substring($rootPrefix.Length).Replace('\', '/') })
    foreach ($file in $files) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Source package contains a reparse point: $($file.FullName)" }
        $relative = $file.FullName.Substring($rootPrefix.Length).Replace('\', '/')
        [void]$lines.Add("$(Get-ToolSourceManifestSha256 $file.FullName)  $relative")
    }
    [IO.File]::WriteAllLines($manifestPath, $lines, $utf8NoBom)
    return $files.Count
}

function Test-ToolSourceHashManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$ManifestName,
        [switch]$RequireClosedSet
    )

    $root = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\')
    $rootPrefix = $root + '\'
    $manifestPath = Join-Path $root $ManifestName
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing source manifest: $ManifestName" }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $entryCount = 0
    foreach ($line in Get-Content -LiteralPath $manifestPath -Encoding UTF8) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?(.+)$') { throw "Invalid line in ${ManifestName}: $line" }
        $expected = $matches[1].ToUpperInvariant()
        $relative = $matches[2].Trim().Replace('\', '/')
        if (-not $seen.Add($relative)) { throw "Duplicate source-manifest path in ${ManifestName}: $relative" }
        $fullPath = Resolve-ToolSourceManifestEntry -SourceDirectory $root -RelativePath $relative
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Missing file pinned by ${ManifestName}: $relative" }
        $actual = Get-ToolSourceManifestSha256 $fullPath
        if ($actual -cne $expected) { throw "Hash mismatch in ${ManifestName}: $relative" }
        $entryCount++
    }
    if ($entryCount -eq 0) { throw "Source manifest has no hash entries: $ManifestName" }
    if ($RequireClosedSet) {
        $actualFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
            $_.FullName -ne $manifestPath -and
            -not (Test-ToolSourcePackageExcludedPath -RootPath $root -FullPath $_.FullName)
        })
        foreach ($file in $actualFiles) {
            $relative = $file.FullName.Substring($rootPrefix.Length).Replace('\', '/')
            if (-not $seen.Contains($relative)) { throw "File omitted from closed source manifest ${ManifestName}: $relative" }
        }
        if ($actualFiles.Count -ne $seen.Count) { throw "Closed source-manifest count mismatch in $ManifestName" }
    }
    return [pscustomobject]@{ Manifest = $ManifestName; Entries = $entryCount; ClosedSet = [bool]$RequireClosedSet }
}
