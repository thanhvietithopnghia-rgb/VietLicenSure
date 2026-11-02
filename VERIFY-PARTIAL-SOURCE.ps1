[CmdletBinding()]
param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$rootPath = [System.IO.Path]::GetFullPath($Root)
$manifestPath = Join-Path $rootPath 'PARTIAL-SOURCE-MANIFEST.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Missing PARTIAL-SOURCE-MANIFEST.json.'
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.SchemaVersion -ne '1.0' -or $manifest.DisclosureClass -ne 'ProprietarySourceAvailable') {
    throw 'Unsupported partial-source manifest contract.'
}
if ($manifest.OpenSource -ne $false) {
    throw 'Partial source must not be marked open-source.'
}

$expected = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in @($manifest.Files)) {
    $relative = [string]$entry.Path
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains('..') -or [System.IO.Path]::IsPathRooted($relative)) {
        throw "Unsafe manifest path: $relative"
    }
    $relative = $relative.Replace('/', '\')
    if (-not $relative.StartsWith('partial-source\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest entry is outside partial-source: $relative"
    }
    if ($expected.ContainsKey($relative)) { throw "Duplicate manifest path: $relative" }
    $expected.Add($relative, $entry)

    $full = [System.IO.Path]::GetFullPath((Join-Path $rootPath $relative))
    if (-not $full.StartsWith($rootPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest path escapes root: $relative"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Missing file: $relative" }
    $file = Get-Item -LiteralPath $full
    $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($hash -ne ([string]$entry.Sha256).ToUpperInvariant()) { throw "Hash mismatch: $relative" }
    if ([int64]$file.Length -ne [int64]$entry.Size) { throw "Size mismatch: $relative" }
}

$actual = @(Get-ChildItem -LiteralPath (Join-Path $rootPath 'partial-source') -Recurse -File | ForEach-Object {
    $_.FullName.Substring($rootPath.Length + 1)
})
$extra = @($actual | Where-Object { -not $expected.ContainsKey($_) })
if ($extra.Count -gt 0) { throw ('Unlisted partial-source files: ' + ($extra -join ', ')) }

$forbiddenNames = @('BUILD.ps1','SIGN-RELEASE.ps1','VietLicenSure-v5.0-OneFile.cs','Tool-DetectionEngine.ps1','Cleanup-Remediation.ps1')
foreach ($name in $forbiddenNames) {
    if ($actual | Where-Object { [System.IO.Path]::GetFileName($_) -ieq $name }) {
        throw "Forbidden core/build file disclosed: $name"
    }
}
$privateKeyContainers = @(Get-ChildItem -LiteralPath (Join-Path $rootPath 'partial-source') -Recurse -File |
    Where-Object { $_.Extension -in @('.pfx', '.p12', '.key') })
if ($privateKeyContainers.Count -gt 0) {
    throw 'Private-key container extension found in partial source.'
}

$secretPatterns = @(
    '-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----',
    '\bgh[opusr]_[A-Za-z0-9_]{20,}',
    '(?i)\b(client_secret|private_key|pfx_password)\s*[:=]'
)
foreach ($relative in $actual) {
    if ([System.IO.Path]::GetExtension($relative) -notin @('.ps1','.md','.json','.mjs','.txt')) { continue }
    $text = Get-Content -LiteralPath (Join-Path $rootPath $relative) -Raw -Encoding UTF8
    foreach ($pattern in $secretPatterns) {
        if ($text -match $pattern) { throw "Potential secret marker in $relative" }
    }
}

Write-Host "PARTIAL SOURCE PASS: $($expected.Count) files; proprietary source-available; no extras." -ForegroundColor Green
