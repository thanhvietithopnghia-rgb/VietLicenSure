[CmdletBinding()]
param(
    [string]$DocsRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($DocsRoot)) { $DocsRoot = Join-Path $PSScriptRoot 'docs' }
$errors = [System.Collections.Generic.List[string]]::new()
$expectedHash = 'A0F6575CC420510E2156696CAC3D236651E41A81405447B4026DDFEA7DA16E4E'
$expectedBuild = '5.0-production-20261001'
$pages = Get-ChildItem -LiteralPath $DocsRoot -Filter '*.html' -File |
    Where-Object { $_.Name -ne 'google4925ca24cda35778.html' }

foreach ($page in $pages) {
    $html = Get-Content -LiteralPath $page.FullName -Raw -Encoding UTF8
    $ids = @([regex]::Matches($html, '\bid=["'']([^"'']+)["'']', 'IgnoreCase') | ForEach-Object { $_.Groups[1].Value })
    foreach ($duplicate in ($ids | Group-Object | Where-Object Count -gt 1)) {
        $errors.Add("$($page.Name): duplicate id '$($duplicate.Name)'")
    }

    if ($html -notmatch '<html\s+lang=["''][a-z-]+["'']') { $errors.Add("$($page.Name): missing html lang") }
    if ($html -notmatch '<meta\s+name=["'']viewport["'']') { $errors.Add("$($page.Name): missing viewport") }
    if ($html -notmatch 'Content-Security-Policy') { $errors.Add("$($page.Name): missing CSP") }
    if ($html -notmatch '<meta\s+name=["'']description["'']') { $errors.Add("$($page.Name): missing description") }
    if ($html -notmatch '<link\s+rel=["'']canonical["'']') { $errors.Add("$($page.Name): missing canonical URL") }
    if ([regex]::Matches($html, '<h1\b', 'IgnoreCase').Count -ne 1) { $errors.Add("$($page.Name): expected exactly one h1") }
    $navTargets = if ($html -match '<html\s+lang=["'']en["'']') {
        @('en.html', 'gallery-en.html', 'documentation-en.html', 'security-privacy-en.html', 'author-en.html')
    } else {
        @('index.html', 'giao-dien.html', 'tai-lieu.html', 'bao-mat-rieng-tu.html', 'tac-gia.html')
    }
    foreach ($navTarget in $navTargets) {
        if ($html -notmatch ('<nav\b[\s\S]*?href=["'']' + [regex]::Escape($navTarget) + '["''][\s\S]*?</nav>')) {
            $errors.Add("$($page.Name): navigation is missing '$navTarget'")
        }
    }
    foreach ($imageTag in [regex]::Matches($html, '<img\b[^>]*>', 'IgnoreCase')) {
        if ($imageTag.Value -notmatch '\balt=["''][^"'']*["'']') { $errors.Add("$($page.Name): image missing alt") }
    }
    foreach ($buttonTag in [regex]::Matches($html, '<button\b[^>]*>', 'IgnoreCase')) {
        if ($buttonTag.Value -notmatch '\btype=["'']button["'']') { $errors.Add("$($page.Name): button missing explicit type") }
    }

    $references = @([regex]::Matches($html, '(?:href|src)=["'']([^"'']+)["'']', 'IgnoreCase') | ForEach-Object { $_.Groups[1].Value })
    foreach ($reference in $references) {
        if ($reference -match '^(https?:|mailto:|tel:|data:)') { continue }
        $parts = $reference -split '#', 2
        $relativePath = $parts[0]
        $anchor = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        $targetPath = if ([string]::IsNullOrWhiteSpace($relativePath)) { $page.FullName } else { Join-Path $page.DirectoryName $relativePath }
        if (-not (Test-Path -LiteralPath $targetPath)) {
            $errors.Add("$($page.Name): missing local target '$reference'")
            continue
        }
        if ($anchor -and ([IO.Path]::GetExtension($targetPath) -eq '.html')) {
            $targetHtml = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8
            $anchorPattern = '\bid=["'']' + [regex]::Escape($anchor) + '["'']'
            if ($targetHtml -notmatch $anchorPattern) { $errors.Add("$($page.Name): missing anchor '$reference'") }
        }
    }
}

$textFiles = Get-ChildItem -LiteralPath $DocsRoot -File -Recurse |
    Where-Object Extension -in '.html', '.css', '.js', '.xml', '.txt'
foreach ($file in $textFiles) {
    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $content = $utf8.GetString([IO.File]::ReadAllBytes($file.FullName))
    } catch {
        $errors.Add("$($file.Name): invalid UTF-8")
        continue
    }
    if ($content.IndexOf([char]0x00C3) -ge 0 -or $content.IndexOf([char]0x00C2) -ge 0 -or $content.IndexOf([char]0xFFFD) -ge 0) {
        $errors.Add("$($file.Name): possible mojibake")
    }
}

$viHome = Get-Content -LiteralPath (Join-Path $DocsRoot 'index.html') -Raw -Encoding UTF8
$enHome = Get-Content -LiteralPath (Join-Path $DocsRoot 'en.html') -Raw -Encoding UTF8
$viGuide = Get-Content -LiteralPath (Join-Path $DocsRoot 'huong-dan.html') -Raw -Encoding UTF8
$enGuide = Get-Content -LiteralPath (Join-Path $DocsRoot 'guide-en.html') -Raw -Encoding UTF8
$sitemap = Get-Content -LiteralPath (Join-Path $DocsRoot 'sitemap.xml') -Raw -Encoding UTF8

foreach ($content in @($viHome, $enHome, $viGuide, $enGuide)) {
    if ($content -notmatch [regex]::Escape($expectedHash)) { $errors.Add('A primary page is missing the current EXE SHA-256') }
}
foreach ($content in @($viHome, $enHome)) {
    if ($content -notmatch [regex]::Escape($expectedBuild)) { $errors.Add('A home page is missing the current Build ID') }
}
if ($viHome -notmatch 'C\u00F3 trong b\u1EA3n c\u1EADp nh\u1EADt 01/10/2026') { $errors.Add('Vietnamese page does not mark Central Dashboard MVP as released') }
if ($enHome -notmatch 'Included in the 1 October 2026 update') { $errors.Add('English page does not mark Central Dashboard MVP as released') }

foreach ($requiredUrl in @(
    'en.html', 'huong-dan.html', 'guide-en.html', 'troubleshooting.html', 'troubleshooting-en.html',
    'giao-dien.html', 'gallery-en.html', 'tai-lieu.html', 'documentation-en.html',
    'bao-mat-rieng-tu.html', 'security-privacy-en.html', 'tac-gia.html', 'author-en.html'
)) {
    if ($sitemap -notmatch [regex]::Escape($requiredUrl)) { $errors.Add("sitemap.xml: missing '$requiredUrl'") }
}

$viPolicy = Get-Content -LiteralPath (Join-Path $DocsRoot 'bao-mat-rieng-tu.html') -Raw -Encoding UTF8
$enPolicy = Get-Content -LiteralPath (Join-Path $DocsRoot 'security-privacy-en.html') -Raw -Encoding UTF8
$viAuthor = Get-Content -LiteralPath (Join-Path $DocsRoot 'tac-gia.html') -Raw -Encoding UTF8
$enAuthor = Get-Content -LiteralPath (Join-Path $DocsRoot 'author-en.html') -Raw -Encoding UTF8
foreach ($content in @($viHome, $enHome, $viPolicy, $enPolicy)) {
    if ($content -notmatch 'Official Self-Signed') { $errors.Add('A trust-status page is missing Official Self-Signed') }
}
foreach ($content in @($viPolicy, $enPolicy)) {
    if ($content -notmatch '(?i)telemetry') { $errors.Add('A privacy page is missing the telemetry disclosure') }
    if ($content -notmatch '(?i)product key') { $errors.Add('A privacy page is missing the full-key protection disclosure') }
    if ($content -match '(?i)ISO 27001 certified|SOC 2 certified|GDPR certified') { $errors.Add('A privacy page contains an unsupported certification claim') }
}
if ($viAuthor -notmatch 'Thanh Vi\u1EC7t' -or $enAuthor -notmatch 'Thanh Viet') { $errors.Add('Author pages are missing the public author identity') }

$galleryAssets = @('assets/vietlicensure-v5-ui.png', 'assets/runtime-dashboard-windows11.png', 'assets/environment-safety-warning.png')
foreach ($asset in $galleryAssets) {
    $assetPath = Join-Path $DocsRoot $asset
    if (-not (Test-Path -LiteralPath $assetPath) -or (Get-Item -LiteralPath $assetPath).Length -le 0) {
        $errors.Add("Gallery asset is missing or empty: '$asset'")
    }
}

if ($errors.Count -gt 0) {
    $errors | Sort-Object -Unique | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Pages verification PASS: $($pages.Count) HTML pages; local links, anchors, IDs, CSP, UTF-8, release identity, bilingual roadmap, and sitemap." -ForegroundColor Green
