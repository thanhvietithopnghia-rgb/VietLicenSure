[CmdletBinding()]
param([string]$SourceDirectory = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($SourceDirectory)
$forbiddenExtensions = @('.pfx','.p12','.pvk','.snk','.key')
$forbiddenNames = @('signing-secrets','private-key','private_key')
$privateKeyMarkerPattern = '-----BEGIN ' + '(?:ENCRYPTED |RSA |EC )?' + 'PRIVATE KEY-----'
$violations = New-Object System.Collections.Generic.List[string]

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git) { $git = Get-Command git -ErrorAction SilentlyContinue }
$relativeFiles = if ($git) {
    $visibleFiles = @(& $git.Source -C $root ls-files --cached --others --exclude-standard)
    $ignoredFiles = @(& $git.Source -C $root ls-files --others --ignored --exclude-standard)
    @($visibleFiles + $ignoredFiles | Where-Object {
        ([string]$_).Replace('\','/') -notmatch '^(?:dist(?:-[^/]+)?|test|release-upload(?:-[^/]+)?|verify-archive(?:-[^/]+)?|\.vm-test-results)(?:/|$)'
    } | Select-Object -Unique)
} else {
    @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object {
        $_.FullName -notmatch '\\(?:\.git|dist(?:-[^\\]+)?|test|release-upload(?:-[^\\]+)?|verify-archive(?:-[^\\]+)?|\.vm-test-results)(?:\\|$)'
    } | ForEach-Object { $_.FullName.Substring($root.Length).TrimStart('\') })
}

foreach ($relativePath in $relativeFiles) {
    if ([string]::IsNullOrWhiteSpace([string]$relativePath)) { continue }
    $extension = [IO.Path]::GetExtension([string]$relativePath).ToLowerInvariant()
    if ($forbiddenExtensions -contains $extension) { $violations.Add("Forbidden signing-secret file: $relativePath") }
    $normalizedPath = ([string]$relativePath).Replace('\','/').ToLowerInvariant()
    foreach ($name in $forbiddenNames) {
        if ($normalizedPath -match ('(^|/)' + [regex]::Escape($name) + '($|/|[._-])')) {
            $violations.Add("Forbidden signing-secret path: $relativePath")
            break
        }
    }
    $fullPath = Join-Path $root ([string]$relativePath)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
    $info = Get-Item -LiteralPath $fullPath -Force
    if ($info.Length -gt 2097152) { continue }
    $text = [IO.File]::ReadAllText($fullPath)
    if ($text -match $privateKeyMarkerPattern) {
        $violations.Add("Embedded private key marker: $relativePath")
    }
}

if ($violations.Count -gt 0) { throw ($violations.ToArray() -join "`r`n") }
Write-Host "VERIFY-NO-SIGNING-SECRETS: PASS ($($relativeFiles.Count) source files)"
