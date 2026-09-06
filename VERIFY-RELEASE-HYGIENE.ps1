[CmdletBinding()]
param([string]$SourceDirectory = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$sourceRoot = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]
$brandName = 'VietLicenSure'
$fullName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('VmlldExpY2VuU3VyZSDigJQgUGjhuqduIG3hu4FtIEtp4buDbSB0cmEgdsOgIFF14bqjbiBsw70gQuG6o24gcXV54buBbiBI4buHIHRo4buRbmc='))
$legacyStoreReservedName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('VG9vbCBLaeG7g20gVHJhIELhuqNuIFF1eeG7gW4='))
$repositoryUrl = 'https://github.com/thanhvietithopnghia-rgb/VietLicenSure'
$legacyRepositoryUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen'
$technicalVersion = '5.0.0.1'
$displayVersion = 'v5.0'
$releaseDateVi = '06/09/2026'
$releaseDateIso = '2026-09-06'

function Read-HygieneText {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $path = Join-Path $sourceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $script:failures.Add("Missing release-hygiene file: $RelativePath")
        return ''
    }
    return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}

function Assert-HygieneContains {
    param([string]$RelativePath, [string]$Text, [string]$Value)
    if (-not $Text.Contains($Value)) { $script:failures.Add("$RelativePath is missing canonical content: $Value") }
}

$requiredCurrentFiles = @(
    '00-VietLicenSure.ico',
    'VietLicenSure-icon.svg',
    'VietLicenSure-v5.0-OneFile.cs',
    'VietLicenSure-v5.0-OneFile.manifest',
    'VietLicenSure.cmd',
    'packaging\msix\New-VietLicenSureMsix.ps1',
    'QUICK-START-v5.0.md',
    'KNOWN-LIMITATIONS-v5.0.md',
    'RELEASE-HYGIENE-v5.0.md'
)
foreach ($relativePath in $requiredCurrentFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $relativePath) -PathType Leaf)) {
        $failures.Add("Missing current VietLicenSure file: $relativePath")
    }
}

foreach ($legacyFileName in @(
    '00-Tool-Kiem-Tra.ico',
    'Tool-Kiem-Tra-icon.svg',
    'Tool-Kiem-Tra-v5.0-OneFile.cs',
    'Tool-Kiem-Tra-v5.0-OneFile.manifest',
    'Tool-Kiem-Tra.cmd',
    'packaging\msix\New-ToolKiemTraMsix.ps1'
)) {
    if (Test-Path -LiteralPath (Join-Path $sourceRoot $legacyFileName)) {
        $failures.Add("Legacy branded file still exists: $legacyFileName")
    }
}

$readme = Read-HygieneText 'README.md'
$releaseNotes = Read-HygieneText 'RELEASE-NOTES-v5.0.md'
$historyVi = Read-HygieneText 'LICH-SU-PHIEN-BAN.txt'
$historyEn = Read-HygieneText 'VERSION-HISTORY-en-US.md'
$quickStart = Read-HygieneText 'QUICK-START-v5.0.md'
$limitations = Read-HygieneText 'KNOWN-LIMITATIONS-v5.0.md'
$hygiene = Read-HygieneText 'RELEASE-HYGIENE-v5.0.md'
$website = Read-HygieneText 'docs\index.html'
$launcher = Read-HygieneText 'VietLicenSure-v5.0-OneFile.cs'
$provenanceHelper = Read-HygieneText 'Tool-Provenance.ps1'
$buildScript = Read-HygieneText 'BUILD.ps1'

foreach ($document in @(
    @{ Name='README.md'; Text=$readme },
    @{ Name='RELEASE-NOTES-v5.0.md'; Text=$releaseNotes },
    @{ Name='LICH-SU-PHIEN-BAN.txt'; Text=$historyVi },
    @{ Name='QUICK-START-v5.0.md'; Text=$quickStart },
    @{ Name='RELEASE-HYGIENE-v5.0.md'; Text=$hygiene }
)) {
    Assert-HygieneContains $document.Name $document.Text $brandName
    Assert-HygieneContains $document.Name $document.Text $displayVersion
    Assert-HygieneContains $document.Name $document.Text $releaseDateVi
}
foreach ($document in @(
    @{ Name='RELEASE-NOTES-v5.0.md'; Text=$releaseNotes },
    @{ Name='QUICK-START-v5.0.md'; Text=$quickStart },
    @{ Name='RELEASE-HYGIENE-v5.0.md'; Text=$hygiene }
)) {
    Assert-HygieneContains $document.Name $document.Text $technicalVersion
}
Assert-HygieneContains 'README.md' $readme $fullName
Assert-HygieneContains 'README.md' $readme ($repositoryUrl + '/releases/latest')
Assert-HygieneContains 'RELEASE-NOTES-v5.0.md' $releaseNotes 'Viet'
Assert-HygieneContains 'RELEASE-NOTES-v5.0.md' $releaseNotes 'Licen'
Assert-HygieneContains 'RELEASE-NOTES-v5.0.md' $releaseNotes 'Sure'
Assert-HygieneContains 'VERSION-HISTORY-en-US.md' $historyEn 'officially renamed'
Assert-HygieneContains 'KNOWN-LIMITATIONS-v5.0.md' $limitations 'ManagedSigned/Pilot'
Assert-HygieneContains 'KNOWN-LIMITATIONS-v5.0.md' $limitations 'Public Stable'
Assert-HygieneContains 'docs\index.html' $website '<a class="brand" href="#top">VIETLICENSURE'
Assert-HygieneContains 'docs\index.html' $website 'ManagedSigned / Pilot'
Assert-HygieneContains 'VietLicenSure-v5.0-OneFile.cs' $launcher 'namespace ThanhViet.VietLicenSure'
Assert-HygieneContains 'Tool-Provenance.ps1' $provenanceHelper "SourcePolicyId = 'ThanhViet.VietLicenSure.CommunityControlledSource.v5.0'"
Assert-HygieneContains 'BUILD.ps1' $buildScript 'VietLicenSure-v$productVersion.exe'

if (($readme + $releaseNotes + $historyVi + $historyEn + $website + $buildScript) -match [regex]::Escape($legacyRepositoryUrl)) {
    $failures.Add('The legacy repository URL remains in current release content.')
}

foreach ($jsonName in @(
    'Tool-Strings.vi-VN.json',
    'Tool-Strings.en-US.json',
    'tool-assistant-knowledge-v1.1.json',
    'OFFICIAL-PROVENANCE-v1.json',
    'update-manifest-v1.json',
    'packaging\msix\STORE-PRODUCT-IDENTITY.json'
)) {
    $jsonText = Read-HygieneText $jsonName
    if ($jsonText.Length -eq 0) { continue }
    try { $null = $jsonText | ConvertFrom-Json }
    catch { $failures.Add("Invalid JSON in $jsonName`: $($_.Exception.Message)") }
}

$stringsVi = (Read-HygieneText 'Tool-Strings.vi-VN.json') | ConvertFrom-Json
$stringsEn = (Read-HygieneText 'Tool-Strings.en-US.json') | ConvertFrom-Json
if ([string]$stringsVi.'app.assistant' -match 'Tool' -or
    [string]$stringsVi.'dashboard.sidebar.brand' -cne $brandName -or
    [string]$stringsVi.'dashboard.sidebar.edition' -match 'TOOL' -or
    [string]$stringsVi.'enterprise.form.title' -notlike 'VietLicenSure*') {
    $failures.Add('Vietnamese user-facing brand labels are not synchronized.')
}
if ([string]$stringsEn.'app.assistant' -cne 'Assistant' -or
    [string]$stringsEn.'dashboard.sidebar.brand' -cne $brandName -or
    [string]$stringsEn.'dashboard.sidebar.edition' -cne 'LICENSE SOFTWARE' -or
    [string]$stringsEn.'enterprise.form.title' -notlike 'VietLicenSure*') {
    $failures.Add('English user-facing brand labels are not synchronized.')
}
$assistantSource = Read-HygieneText 'Tool-Assistant.ps1'
$enterpriseSource = Read-HygieneText 'enterprise-license-manager.ps1'
$dashboardSource = Read-HygieneText 'Giao-Dien.ps1'
if ($assistantSource.Contains('Tool Assistant') -or
    -not $assistantSource.Contains('RowStyle([Windows.Forms.SizeType]::Absolute, 92)') -or
    -not $assistantSource.Contains('$scope.Size = New-Object Drawing.Size(570, 42)')) {
    $failures.Add('Assistant branding or anti-clipping layout contract drifted.')
}
if (-not $dashboardSource.Contains('$releaseDisplayName = "v5.0"') -or
    -not $enterpriseSource.Contains('$script:enterpriseReleaseDisplayName = "v5.0"')) {
    $failures.Add('User-facing display version is not synchronized to v5.0.')
}

$storeIdentityText = Read-HygieneText 'packaging\msix\STORE-PRODUCT-IDENTITY.json'
if ($storeIdentityText.Length -gt 0) {
    $storeIdentity = $storeIdentityText | ConvertFrom-Json
    if ([string]$storeIdentity.BrandDisplayName -cne $brandName -or
        [string]$storeIdentity.PackageIdentityName -cne 'ThanhVit.ToolKimTraBnQuyn' -or
        [string]$storeIdentity.ReservedName -cne $legacyStoreReservedName) {
        $failures.Add('MSIX does not separate the VietLicenSure display name from the legacy Partner Center identity.')
    }
}

$legacyIdentifierAllowList = @(
    'BUILD.ps1',
    'VietLicenSure-v5.0-OneFile.cs',
    'Tool-DataLifecycle.ps1',
    'Tool-LicenseTimeline.ps1',
    'Tool-SoftwareInventory.ps1',
    'packaging\msix\STORE-PRODUCT-IDENTITY.json',
    'packaging\msix\README.md',
    'VERIFY-MSIX-PACKAGING.ps1',
    'VERIFY-RELEASE-HYGIENE.ps1',
    'RELEASE-HYGIENE-v5.0.md'
)
foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force | Where-Object {
    $_.FullName -notmatch '\\(?:\.git|dist(?:-[^\\]+)?|test|release-upload(?:-[^\\]+)?)(?:\\|$)' -and
    $_.Extension -in @('.ps1','.cs','.json','.md','.txt','.html','.cmd','.yml','.yaml','.xml')
})) {
    $relative = $file.FullName.Substring($sourceRoot.TrimEnd('\').Length + 1)
    $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    if ($text -match 'ThanhViet\.ToolKiemTra|ThanhViet-Tool-Kiem-Tra') {
        if ($legacyIdentifierAllowList -notcontains $relative) {
            $failures.Add("Legacy internal brand identifier is outside the compatibility allowlist: $relative")
        }
    }
}

foreach ($legacyDocument in @(
    'ENTRY-POINTS-v4.8.md',
    'OFFLINE-AND-REPORTING-v4.8.md',
    'SECURITY-HARDENING-v4.8.md',
    'TECHNICAL-ARCHITECTURE-v4.8.md',
    'COMPATIBILITY-MATRIX-v4.8.md',
    'DANH-GIA-VA-NANG-CAP-v4.8.md',
    'SOURCE-POLICY-v4.9.md'
)) {
    $legacyText = Read-HygieneText $legacyDocument
    if ($legacyText -notmatch 'VietLicenSure v5\.0(?:[^0-9]|$)') {
        $failures.Add("Legacy-suffixed document lacks current applicability notice: $legacyDocument")
    }
}

if ($releaseDateIso -ne '2026-09-06') { $failures.Add('Internal ISO release date drifted.') }

if ($failures.Count -gt 0) {
    Write-Host "VERIFY-RELEASE-HYGIENE: $($failures.Count) error(s)." -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'VERIFY-RELEASE-HYGIENE: 0 errors (brand, version, date, documentation, legacy compatibility allowlist and release labels are synchronized).' -ForegroundColor Green
exit 0
