[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [switch]$SkipVerification,
    [string]$SigningCertificateThumbprint = '',
    [ValidateSet('CurrentUser','LocalMachine')][string]$SigningCertificateStore = 'CurrentUser',
    [string]$SigningPfxPath = '',
    [Security.SecureString]$SigningPfxPassword,
    [string]$UpdateManifestCertificateThumbprint = 'ABE70696679B1D8987A2D5B1F6C1C6909D364CEA',
    [ValidateSet('CurrentUser','LocalMachine')][string]$UpdateManifestCertificateStore = 'CurrentUser',
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [string]$ClientVmSummaryPath = '',
    [string]$IndependentSecurityReviewPath = '',
    [switch]$RequireAuthenticode,
    [switch]$AllowManagedSignedBuild,
    [switch]$AllowStoreBuild,
    [switch]$AllowUnsignedDevelopmentBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'Tool-Provenance.ps1')
$releaseIdentity = Get-ToolProvenanceExpectedValues
$releaseVersion = [string]$releaseIdentity.ReleaseVersion
$releaseBuildTime = [string]$releaseIdentity.BuildTime
$officialBuildId = [string]$releaseIdentity.BuildId
$releaseVersionMatch = [regex]::Match($releaseVersion, '^(?<major>\d+)\.(?<minor>\d+)\.\d+\.\d+$')
if (-not $releaseVersionMatch.Success -or
    $releaseBuildTime -notmatch '^\d{4}-\d{2}-\d{2}$' -or
    $officialBuildId -cne ($releaseVersion + '-production-' + $releaseBuildTime.Replace('-', ''))) {
    throw 'Tool-Provenance.ps1 chứa release identity không nhất quán.'
}
$productVersion = $releaseVersionMatch.Groups['major'].Value + '.' + $releaseVersionMatch.Groups['minor'].Value
$releaseBuildDate = $releaseBuildTime.Replace('-', '.')
$releaseDateToken = $releaseBuildTime.Replace('-', '')
$managedBuildId = "$releaseVersion-managed-signed-$releaseDateToken"
$publishedAtUtc = $releaseBuildTime + 'T00:00:00Z'
$requiresSignedArtifact = [bool]($RequireAuthenticode -or $AllowManagedSignedBuild)
$requiresVerifiedProvenance = [bool]($requiresSignedArtifact -or $AllowStoreBuild)
$bundledUpdateManifestChannel = if ($AllowStoreBuild) { 'store' } elseif ($requiresSignedArtifact) { 'stable' } else { 'development' }
$applicationSelfUpdateAllowed = [bool]$RequireAuthenticode
$applicationUpdateAuthority = if ($AllowStoreBuild) {
    'MicrosoftStore'
} elseif ($AllowManagedSignedBuild) {
    'ManagedDeployment'
} elseif ($AllowUnsignedDevelopmentBuild) {
    'None'
} else {
    'PublicStableManifest'
}
$releaseLabel = if ($AllowUnsignedDevelopmentBuild) {
    "$releaseVersion-development-unsigned"
} elseif ($AllowStoreBuild) {
    "$releaseVersion-store-submission"
} elseif ($AllowManagedSignedBuild) {
    $managedBuildId
} else {
    $officialBuildId
}
# Keep a hard payload-size budget for in-place updates.  The added safety UI,
# localized evidence explanations, and post-verification data are intentional;
# 911,024 bytes keeps a narrow cap while leaving one KiB of signing/timestamp headroom.
$maximumInPlaceExecutableBytes = 911024
$sourceDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $sourceDirectory 'dist' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$sourceName = "Tool-Kiem-Tra-v$productVersion-OneFile.cs"
$applicationManifestName = "Tool-Kiem-Tra-v$productVersion-OneFile.manifest"
$embeddedVerifierName = 'VERIFY-EMBEDDED-PAYLOAD.ps1'
$peHardeningName = 'PE-HARDENING.ps1'

function Assert-BuildOutputDirectoryReady {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $existingAncestor = $fullPath
    if (Test-Path -LiteralPath $fullPath) {
        if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
            throw 'OutputDirectory exists but is not a directory.'
        }
        if (@(Get-ChildItem -LiteralPath $fullPath -Force -ErrorAction Stop).Count -ne 0) {
            throw 'OutputDirectory must be new or empty; refusing to mix a release with stale or unmanifested files.'
        }
    } else {
        while (-not (Test-Path -LiteralPath $existingAncestor)) {
            $parent = Split-Path -Parent $existingAncestor
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $existingAncestor) { break }
            $existingAncestor = $parent
        }
    }
    if (-not (Test-Path -LiteralPath $existingAncestor)) {
        throw 'OutputDirectory has no resolvable existing ancestor.'
    }
    $cursor = Get-Item -LiteralPath $existingAncestor -Force -ErrorAction Stop
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "OutputDirectory cannot traverse a reparse point: $($cursor.FullName)"
        }
        $cursor = $cursor.Parent
    }
}

if (([int][bool]$RequireAuthenticode + [int][bool]$AllowManagedSignedBuild + [int][bool]$AllowStoreBuild + [int][bool]$AllowUnsignedDevelopmentBuild) -ne 1) {
    throw 'Chọn đúng một chế độ build: RequireAuthenticode (public Stable), AllowManagedSignedBuild, AllowStoreBuild hoặc AllowUnsignedDevelopmentBuild.'
}
if ($requiresVerifiedProvenance -and $SkipVerification) {
    throw 'Build production/Store không cho phép SkipVerification; mọi verifier và provenance bắt buộc phải chạy.'
}
if ($requiresSignedArtifact -and -not [string]::IsNullOrWhiteSpace($SigningPfxPath)) {
    throw 'Build có chữ ký không nhận PFX dạng tệp. Hãy dùng khóa trong certificate store/HSM bằng SigningCertificateThumbprint.'
}
if ($requiresSignedArtifact) {
    $normalizedStableSignerThumbprint = ($SigningCertificateThumbprint -replace '\s', '').ToUpperInvariant()
    if ($normalizedStableSignerThumbprint -notmatch '^[A-F0-9]{40}$') {
        throw 'Build có chữ ký cần thumbprint SHA-1 40 ký tự của chứng thư code-signing trong certificate store/HSM.'
    }
    $normalizedUpdateManifestSignerThumbprint = ($UpdateManifestCertificateThumbprint -replace '\s', '').ToUpperInvariant()
    if ($normalizedUpdateManifestSignerThumbprint -notmatch '^[A-F0-9]{40}$') {
        throw 'Build stable cần thumbprint SHA-1 40 ký tự riêng cho chứng thư ký detached CMS của update manifest.'
    }
}
Assert-BuildOutputDirectoryReady -Path $OutputDirectory

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    throw 'BUILD.ps1 phải chạy bằng Windows PowerShell 64-bit để build AnyCPU và kiểm tra trên cả CLR x64/x86.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Máy build phải là Windows 64-bit để kiểm tra cùng một EXE AnyCPU trên cả CLR x64/x86.'
}

$payloadFiles = @(
    'approved-kms-servers.txt',
    'HUONG-DAN.txt',
    'USER-GUIDE-en-US.md',
    'LICH-SU-PHIEN-BAN.txt',
    'VERSION-HISTORY-en-US.md',
    'LICENSE-NOTICE.txt',
    'SOURCE-POLICY-v4.9.md',
    'Tool-Provenance.ps1',
    'OFFICIAL-PROVENANCE-v1.json',
    'OFFICIAL-PROVENANCE-v1.json.p7s',
    'Giao-Dien.ps1',
    'kiem-tra-cau-hinh-ban-quyen.ps1',
    'Tool-Kiem-Tra-icon.svg',
    'Tool-Kiem-Tra.cmd',
    'Tool-Runtime.ps1',
    'Tool-ElevatedBridge.ps1',
    'Tool-DataLifecycle.ps1',
    'Tool-Compatibility.ps1',
    'compatibility-catalog-v1.0.json',
    'Tool-Capabilities.ps1',
    'Tool-ScanOptimization.ps1',
    'Tool-Logging.ps1',
    'Tool-ModuleContract.ps1',
    'Tool-UiTheme.ps1',
    'Tool-Localization.ps1',
    'Tool-Strings.vi-VN.json',
    'Tool-Strings.en-US.json',
    'Tool-OfflinePolicy.ps1',
    'Tool-Assistant.ps1',
    'tool-assistant-knowledge-v1.1.json',
    'Tool-SoftwareInventory.ps1',
    'software-license-catalog-v1.0.json',
    'software-license-catalog-v1.0.json.p7s',
    'software-license-online-update.ps1',
    'Tool-UpdateManager.ps1',
    'Tool-ReportSchema.ps1',
    'Tool-ResultCenter.ps1',
    'Tool-ReportExport.ps1',
    'Tool-PluginEngine.ps1',
    'Tool-LicenseTimeline.ps1',
    'Tool-SafetyPolicy.ps1',
    'Tool-Enterprise.ps1',
    'Tool-EnterpriseCli.ps1',
    'Tool-EnterpriseHost.ps1',
    'Tool-EnterpriseAgent.ps1',
    'enterprise-license-manager.ps1',
    'TOOL-SHA256SUMS.txt',
    'windows-license-backup.ps1',
    'windows-license-compliance-cleanup.ps1',
    'windows-license-restore.ps1',
    'windows-license-deep-scan.ps1',
    'windows-license-forensics.ps1',
    'windows-oem-license-assistant.ps1',
    'windows-office-license-manager.ps1',
    'windows-license-assurance.ps1',
    'builtin-windows-office-trust.plugin.json'
)

$integrityFiles = @(
    'HUONG-DAN.txt',
    'USER-GUIDE-en-US.md',
    'LICH-SU-PHIEN-BAN.txt',
    'VERSION-HISTORY-en-US.md',
    'LICENSE-NOTICE.txt',
    'SOURCE-POLICY-v4.9.md',
    'Tool-Provenance.ps1',
    'OFFICIAL-PROVENANCE-v1.json',
    'OFFICIAL-PROVENANCE-v1.json.p7s',
    'Giao-Dien.ps1',
    'kiem-tra-cau-hinh-ban-quyen.ps1',
    'Tool-Kiem-Tra-icon.svg',
    'Tool-Kiem-Tra.cmd',
    'Tool-Runtime.ps1',
    'Tool-ElevatedBridge.ps1',
    'Tool-DataLifecycle.ps1',
    'Tool-Compatibility.ps1',
    'compatibility-catalog-v1.0.json',
    'Tool-Capabilities.ps1',
    'Tool-ScanOptimization.ps1',
    'Tool-Logging.ps1',
    'Tool-ModuleContract.ps1',
    'Tool-UiTheme.ps1',
    'Tool-Localization.ps1',
    'Tool-Strings.vi-VN.json',
    'Tool-Strings.en-US.json',
    'Tool-OfflinePolicy.ps1',
    'Tool-Assistant.ps1',
    'tool-assistant-knowledge-v1.1.json',
    'Tool-SoftwareInventory.ps1',
    'software-license-catalog-v1.0.json',
    'software-license-catalog-v1.0.json.p7s',
    'software-license-online-update.ps1',
    'Tool-UpdateManager.ps1',
    'Tool-ReportSchema.ps1',
    'Tool-ResultCenter.ps1',
    'Tool-ReportExport.ps1',
    'Tool-PluginEngine.ps1',
    'Tool-LicenseTimeline.ps1',
    'Tool-SafetyPolicy.ps1',
    'Tool-Enterprise.ps1',
    'Tool-EnterpriseCli.ps1',
    'Tool-EnterpriseHost.ps1',
    'Tool-EnterpriseAgent.ps1',
    'enterprise-license-manager.ps1',
    'windows-license-backup.ps1',
    'windows-license-compliance-cleanup.ps1',
    'windows-license-restore.ps1',
    'windows-license-deep-scan.ps1',
    'windows-license-forensics.ps1',
    'windows-oem-license-assistant.ps1',
    'windows-office-license-manager.ps1',
    'windows-license-assurance.ps1',
    'builtin-windows-office-trust.plugin.json'
)

$provenanceSignatureName = 'OFFICIAL-PROVENANCE-v1.json.p7s'
$provenanceSignaturePath = Join-Path $sourceDirectory $provenanceSignatureName
if ($AllowUnsignedDevelopmentBuild) {
    # Development launchers deliberately omit the stable-build compile marker,
    # so their embedded payload list must also omit the official provenance
    # signature even when that production signature exists in the source tree.
    $payloadFiles = @($payloadFiles | Where-Object { $_ -ne $provenanceSignatureName })
    $integrityFiles = @($integrityFiles | Where-Object { $_ -ne $provenanceSignatureName })
} elseif (-not (Test-Path -LiteralPath $provenanceSignaturePath -PathType Leaf)) {
    throw 'Build production bắt buộc chữ ký OFFICIAL-PROVENANCE-v1.json.p7s.'
}

$sourceFiles = @(
    $payloadFiles
    '.gitattributes'
    '.gitignore'
    '00-Tool-Kiem-Tra.ico'
    'AUDIT-SCOPE-v1.md'
    'BUILD.ps1'
    'CODE-SIGNING-POLICY-v1.md'
    'DANH-GIA-VA-NANG-CAP-v4.8.md'
    'LICENSE-NOTICE.txt'
    'SOURCE-POLICY-v4.9.md'
    'RELEASE-NOTES-v4.9.md'
    'RELEASE-NOTES-v5.0.md'
    'README.md'
    'README-MA-NGUON.md'
    'MODULE-CONTRACT-v1.0.md'
    'REPORT-SCHEMA-v1.5.md'
    'ROADMAP-v5.0.md'
    'SECURITY-HARDENING-v4.8.md'
    'TECHNICAL-ARCHITECTURE-v4.8.md'
    'ENTRY-POINTS-v4.8.md'
    'COMPATIBILITY-MATRIX-v4.8.md'
    'OFFLINE-AND-REPORTING-v4.8.md'
    'LOCALIZATION-v1.0.md'
    'Manage-ToolEnterpriseDeployment.ps1'
    'New-ClientVmTestSummary.ps1'
    'PLUGIN-PUBLISHER-TRUST-v1.md'
    'REPORT-VIEWER-POLICY-v1.md'
    'SAFETY-POLICY-v1.0.md'
    'SECURITY.md'
    'SECURITY-REVIEW-PROCESS-v1.md'
    'SECURITY-REVIEW-ATTESTATION-TEMPLATE-v1.json'
    'SECURITY-TEST-RESULTS.md'
    $sourceName
    $applicationManifestName
    $embeddedVerifierName
    'VERIFY-FOUNDATION.ps1'
    'VERIFY-MODULE-CONTRACT.ps1'
    'VERIFY-REPORT-SCHEMA.ps1'
    'VERIFY-SAFETY-REGRESSIONS.ps1'
    'VERIFY-DASHBOARD.ps1'
    'VERIFY-RESULT-CENTER.ps1'
    'VERIFY-EXTENSIONS.ps1'
    'VERIFY-ENTERPRISE.ps1'
    'VERIFY-COMPATIBILITY.ps1'
    'VERIFY-MICROSOFT-CATALOG-SOURCES.ps1'
    'VERIFY-OFFLINE-I18N.ps1'
    'VERIFY-LOCALIZATION-COVERAGE.ps1'
    'VERIFY-PERFORMANCE.ps1'
    'VERIFY-DATA-LIFECYCLE.ps1'
    'VERIFY-APPLICATION-UPDATE.ps1'
    'VERIFY-ASSISTANT.ps1'
    'VERIFY-CATALOG-V4.9.ps1'
    'VERIFY-CATALOG-PLUGIN-TRUST-V5.ps1'
    'VERIFY-CODE-SIGNING-READINESS.ps1'
    'VERIFY-MSIX-PACKAGING.ps1'
    'VERIFY-ENTERPRISE-GOVERNANCE.ps1'
    'VERIFY-NO-SIGNING-SECRETS.ps1'
    'VERIFY-REMEDIATION-V4.9.ps1'
    'VERIFY-SOFTWARE-DETECTION-V4.9.ps1'
    'VERIFY-PROVENANCE.ps1'
    'SIGN-ASSISTANT-KNOWLEDGE.ps1'
    'tool-assistant-knowledge-v1.1.json.p7s'
    'SIGN-SOFTWARE-CATALOG.ps1'
    'SIGN-PROVENANCE.ps1'
    'SIGN-UPDATE-MANIFEST.ps1'
    'SIGN-RELEASE.ps1'
    'VERIFY-AUTHENTICODE.ps1'
    $peHardeningName
    'VERIFY-RELEASE.ps1'
    'VERIFY-STABLE-READINESS.ps1'
) | Select-Object -Unique

# SOURCE-SHA256SUMS.txt deliberately stays a flat-file manifest for backward
# compatibility with VERIFY-RELEASE.ps1. The nested GitHub workflow is still a
# required build input below and is covered by the recursive
# SOURCE-PACKAGE-SHA256SUMS.txt manifest.

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '') }
        finally { $algorithm.Dispose() }
    } finally { $stream.Dispose() }
}

function Write-SourcePackageHashManifest {
    $sourcePackageManifestPath = Join-Path $sourceDirectory 'SOURCE-PACKAGE-SHA256SUMS.txt'
    $sourcePackageRootPrefix = [IO.Path]::GetFullPath($sourceDirectory).TrimEnd('\') + '\'
    $outputRootPrefix = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\') + '\'
    $sourcePackageFiles = @(Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File -Force | Where-Object {
        $_.FullName -ne $sourcePackageManifestPath -and
        -not $_.FullName.StartsWith($outputRootPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (-not $AllowUnsignedDevelopmentBuild -or
            [IO.Path]::GetFileName($_.FullName) -notin @('OFFICIAL-PROVENANCE-v1.json.p7s','update-manifest-v1.json.p7s')) -and
        # Keep all generated build/release verification directories out of the
        # source package.  They are local artifacts, may contain a complete
        # prior source archive, and must never change the fixed source-manifest
        # count or be published accidentally.
        $_.FullName -notmatch '\\(?:\.git|dist(?:-[^\\]+)?|test|release-upload(?:-[^\\]+)?|verify-archive(?:-[^\\]+)?)(?:\\|$)'
    } | Sort-Object { $_.FullName.Substring($sourcePackageRootPrefix.Length) })
    $sourcePackageManifestLines = @(
        "# SHA-256 cua toan bo goi ma nguon v$productVersion.0; khong tu liet ke tep manifest nay."
    )
    foreach ($file in $sourcePackageFiles) {
        $relativePath = $file.FullName.Substring($sourcePackageRootPrefix.Length)
        $sourcePackageManifestLines += "$(Get-Sha256Hex $file.FullName)  $relativePath"
    }
    [IO.File]::WriteAllLines(
        $sourcePackageManifestPath,
        $sourcePackageManifestLines,
        (New-Object Text.UTF8Encoding($false))
    )
}

function New-SolidPayloadBundle {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string[]]$PayloadFiles,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    [byte[]]$magic = [Text.Encoding]::ASCII.GetBytes('TVPBNDL1')
    [uint32]$formatVersion = 1
    [int64]$maximumPayloadBytes = 8MB
    [int64]$maximumBundlePayloadBytes = 16MB
    $payloadEntries = New-Object System.Collections.Generic.List[object]
    [int64]$payloadSourceBytes = 0
    foreach ($name in $PayloadFiles) {
        $path = Join-Path $SourceDirectory $name
        $length = [int64](Get-Item -LiteralPath $path).Length
        if ($length -lt 0 -or $length -gt $maximumPayloadBytes) {
            throw "Payload vượt giới hạn solid bundle: $name ($length / $maximumPayloadBytes byte)."
        }
        if ($payloadSourceBytes -gt ($maximumBundlePayloadBytes - $length)) {
            throw "Tổng payload vượt giới hạn solid bundle $maximumBundlePayloadBytes byte."
        }
        $payloadSourceBytes += $length
        [void]$payloadEntries.Add([pscustomobject]@{ Name=$name; Path=$path; Length=$length })
    }

    [int64]$headerBytes = $magic.Length + 4 + 4 + 8 + (8 * $payloadEntries.Count)
    $output = New-Object IO.FileStream($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = $null
    try {
        $writer = New-Object IO.BinaryWriter($output)
        $writer.Write($magic)
        $writer.Write([uint32]$formatVersion)
        $writer.Write([uint32]$payloadEntries.Count)
        $writer.Write([uint64]$payloadSourceBytes)
        foreach ($entry in $payloadEntries) { $writer.Write([uint64]$entry.Length) }
        $writer.Flush()

        foreach ($entry in $payloadEntries) {
            $input = [IO.File]::OpenRead($entry.Path)
            try { $input.CopyTo($output) }
            finally { $input.Dispose() }
        }
        $output.Flush()
    } finally {
        if ($writer) { $writer.Dispose() }
        else { $output.Dispose() }
    }

    return [pscustomobject]@{
        FormatVersion = [int]$formatVersion
        PayloadCount = [int]$payloadEntries.Count
        HeaderBytes = [int64]$headerBytes
        SourceBytes = [int64]$payloadSourceBytes
        BundleBytes = [int64]($headerBytes + $payloadSourceBytes)
        MaximumPayloadBytes = [int64]$maximumPayloadBytes
        MaximumPayloadDataBytes = [int64]$maximumBundlePayloadBytes
        MaximumCompressedBytes = [int64](16MB)
        MaximumDecodedBytes = [int64](32MB)
    }
}

function New-DeflatedPayloadFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $input = [IO.File]::OpenRead($SourcePath)
    try {
        $output = New-Object IO.FileStream($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $deflate = New-Object IO.Compression.DeflateStream($output, [IO.Compression.CompressionLevel]::Optimal, $true)
            try { $input.CopyTo($deflate) }
            finally { $deflate.Dispose() }
        } finally { $output.Dispose() }
    } finally { $input.Dispose() }
}

function Find-CSharpCompiler {
    $candidates = New-Object System.Collections.Generic.List[object]
    $visualStudioRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio'
    if (Test-Path -LiteralPath $visualStudioRoot -PathType Container) {
        foreach ($candidate in Get-ChildItem -LiteralPath $visualStudioRoot -Filter 'csc.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\MSBuild\\Current\\Bin\\Roslyn\\csc\.exe$' }) {
            [void]$candidates.Add($candidate)
        }
    }
    $nugetRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.nuget\packages\microsoft.net.compilers.toolset'
    if (Test-Path -LiteralPath $nugetRoot -PathType Container) {
        foreach ($candidate in Get-ChildItem -LiteralPath $nugetRoot -Filter 'csc.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\tasks\\net472\\csc\.exe$' }) {
            [void]$candidates.Add($candidate)
        }
    }
    $selected = @($candidates.ToArray() | Sort-Object { [Version]$_.VersionInfo.FileVersion } -Descending | Select-Object -First 1)
    if ($selected.Count -eq 1) { return $selected[0].FullName }
    throw 'Không tìm thấy Roslyn csc.exe. Hãy cài Visual Studio Build Tools (MSBuild/Roslyn); bản hiện tại không dùng compiler legacy vì cần deterministic build.'
}

function Get-VerificationPowerShell([string]$Architecture) {
    $windowsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $path = if ($Architecture -eq 'x64') {
        Join-Path $windowsDirectory 'System32\WindowsPowerShell\v1.0\powershell.exe'
    } else {
        Join-Path $windowsDirectory 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Thiếu PowerShell $Architecture để kiểm tra build: $path" }
    return $path
}

$requiredFiles = @($payloadFiles | Where-Object { $_ -ne 'TOOL-SHA256SUMS.txt' }) + @(
    '.gitignore',
    '.github\workflows\client-vm-matrix.yml',
    '00-Tool-Kiem-Tra.ico',
    'AUDIT-SCOPE-v1.md',
    'BUILD.ps1',
    'CODE-SIGNING-POLICY-v1.md',
    'DANH-GIA-VA-NANG-CAP-v4.8.md',
    'LICENSE-NOTICE.txt',
    'SOURCE-POLICY-v4.9.md',
    'RELEASE-NOTES-v4.9.md',
    'RELEASE-NOTES-v5.0.md',
    'README.md',
    'README-MA-NGUON.md',
    'MODULE-CONTRACT-v1.0.md',
    'REPORT-SCHEMA-v1.5.md',
    'ROADMAP-v5.0.md',
    'SECURITY-HARDENING-v4.8.md',
    'TECHNICAL-ARCHITECTURE-v4.8.md',
    'ENTRY-POINTS-v4.8.md',
    'COMPATIBILITY-MATRIX-v4.8.md',
    'OFFLINE-AND-REPORTING-v4.8.md',
    'LOCALIZATION-v1.0.md',
    'Manage-ToolEnterpriseDeployment.ps1',
    'New-ClientVmTestSummary.ps1',
    'PLUGIN-PUBLISHER-TRUST-v1.md',
    'REPORT-VIEWER-POLICY-v1.md',
    'SAFETY-POLICY-v1.0.md',
    'SECURITY.md',
    'SECURITY-REVIEW-PROCESS-v1.md',
    'SECURITY-REVIEW-ATTESTATION-TEMPLATE-v1.json',
    'SECURITY-TEST-RESULTS.md',
    $sourceName,
    $applicationManifestName,
    $embeddedVerifierName,
    'VERIFY-FOUNDATION.ps1',
    'VERIFY-MODULE-CONTRACT.ps1',
    'VERIFY-REPORT-SCHEMA.ps1',
    'VERIFY-SAFETY-REGRESSIONS.ps1',
    'VERIFY-DASHBOARD.ps1',
    'VERIFY-RESULT-CENTER.ps1',
    'VERIFY-EXTENSIONS.ps1',
    'VERIFY-ENTERPRISE.ps1',
    'VERIFY-COMPATIBILITY.ps1',
    'VERIFY-OFFLINE-I18N.ps1',
    'VERIFY-LOCALIZATION-COVERAGE.ps1',
    'VERIFY-PERFORMANCE.ps1',
    'VERIFY-DATA-LIFECYCLE.ps1',
    'VERIFY-APPLICATION-UPDATE.ps1',
    'VERIFY-ASSISTANT.ps1',
    'VERIFY-CATALOG-V4.9.ps1',
    'VERIFY-CATALOG-PLUGIN-TRUST-V5.ps1',
    'VERIFY-CODE-SIGNING-READINESS.ps1',
    'VERIFY-MSIX-PACKAGING.ps1',
    'VERIFY-ENTERPRISE-GOVERNANCE.ps1',
    'VERIFY-NO-SIGNING-SECRETS.ps1',
    'VERIFY-REMEDIATION-V4.9.ps1',
    'VERIFY-SOFTWARE-DETECTION-V4.9.ps1',
    'VERIFY-PROVENANCE.ps1',
    'SIGN-ASSISTANT-KNOWLEDGE.ps1',
    'tool-assistant-knowledge-v1.1.json.p7s',
    'SIGN-SOFTWARE-CATALOG.ps1',
    'SIGN-PROVENANCE.ps1',
    'SIGN-UPDATE-MANIFEST.ps1',
    'SIGN-RELEASE.ps1',
    'VERIFY-AUTHENTICODE.ps1',
    $peHardeningName,
    'VERIFY-RELEASE.ps1',
    'VERIFY-STABLE-READINESS.ps1'
)
foreach ($name in ($requiredFiles | Select-Object -Unique)) {
    $path = Join-Path $sourceDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Thiếu tệp nguồn bắt buộc: $name" }
}

# Third-party workflow code is executable supply-chain input. Refuse a release
# if an official GitHub Action is referenced by a mutable tag or branch.
$workflowDirectory = Join-Path $sourceDirectory '.github\workflows'
if (Test-Path -LiteralPath $workflowDirectory -PathType Container) {
    foreach ($workflowFile in @(Get-ChildItem -LiteralPath $workflowDirectory -File | Where-Object { $_.Extension -in @('.yml','.yaml') })) {
        $workflowText = [IO.File]::ReadAllText($workflowFile.FullName, [Text.Encoding]::UTF8)
        $mutableAction = [regex]::Match($workflowText, '(?im)^\s*(?:-\s*)?uses:\s*actions/[A-Za-z0-9_.-]+@(?![0-9a-f]{40}(?:\s|#|$))\S+')
        if ($mutableAction.Success) {
            throw "GitHub Action phải khóa theo full commit SHA: $($workflowFile.Name): $($mutableAction.Value.Trim())"
        }
    }
}

& (Join-Path $sourceDirectory 'VERIFY-NO-SIGNING-SECRETS.ps1') -SourceDirectory $sourceDirectory
if ($LASTEXITCODE -ne 0) { throw "Phát hiện hoặc không thể loại trừ bí mật code-signing trong cây nguồn, mã thoát: $LASTEXITCODE" }

if ($RequireAuthenticode) {
    if ([string]::IsNullOrWhiteSpace($ClientVmSummaryPath) -or [string]::IsNullOrWhiteSpace($IndependentSecurityReviewPath)) {
        throw 'Public Stable build requires ClientVmSummaryPath and IndependentSecurityReviewPath.'
    }
    $stableProvenance = Get-Content -LiteralPath (Join-Path $sourceDirectory 'OFFICIAL-PROVENANCE-v1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    & (Join-Path $sourceDirectory 'VERIFY-STABLE-READINESS.ps1') -ClientVmSummaryPath $ClientVmSummaryPath -IndependentSecurityReviewPath $IndependentSecurityReviewPath -ExpectedSourceCommit ([string]$stableProvenance.SourceSnapshotCommit) -ExpectedReleaseVersion $releaseVersion
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-STABLE-READINESS.ps1 failed with exit code: $LASTEXITCODE" }
}

. (Join-Path $sourceDirectory $peHardeningName)
. (Join-Path $sourceDirectory 'Tool-ModuleContract.ps1')
. (Join-Path $sourceDirectory 'Tool-ReportSchema.ps1')
. (Join-Path $sourceDirectory 'Tool-ReportExport.ps1')
. (Join-Path $sourceDirectory 'Tool-SafetyPolicy.ps1')
. (Join-Path $sourceDirectory 'Tool-Compatibility.ps1')
. (Join-Path $sourceDirectory 'Tool-Localization.ps1')
. (Join-Path $sourceDirectory 'Tool-OfflinePolicy.ps1')
. (Join-Path $sourceDirectory 'Tool-Provenance.ps1')
. (Join-Path $sourceDirectory 'Tool-Assistant.ps1')
. (Join-Path $sourceDirectory 'Tool-SoftwareInventory.ps1')
. (Join-Path $sourceDirectory 'Tool-PluginEngine.ps1')
$moduleContractMetadata = Get-ToolModuleContractMetadata
$reportSchemaMetadata = Get-ToolReportSchemaMetadata
$reportExportMetadata = Get-ToolReportExportMetadata
$safetyPolicyMetadata = Get-ToolSafetyPolicyMetadata
$compatibilityMetadata = Get-ToolCompatibilityMetadata
$localizationMetadata = Get-ToolLocalizationMetadata
$offlinePolicyMetadata = Get-ToolOfflinePolicyMetadata
$provenanceManifestPath = Join-Path $sourceDirectory 'OFFICIAL-PROVENANCE-v1.json'
$provenanceSignaturePath = Join-Path $sourceDirectory 'OFFICIAL-PROVENANCE-v1.json.p7s'
if ($AllowUnsignedDevelopmentBuild) {
    $provenanceMetadata = Test-ToolOfficialProvenance `
        -ManifestPath $provenanceManifestPath `
        -SignaturePath (Join-Path $sourceDirectory '.development-unsigned-provenance.p7s') `
        -AllowUnsignedDevelopmentTest
} else {
    $provenanceMetadata = Get-ToolOfficialBuildState `
        -ManifestPath $provenanceManifestPath `
        -SignaturePath $provenanceSignaturePath
    if (-not [bool]$provenanceMetadata.IsOfficial) {
        throw "Provenance v5.0 chưa đạt Official: $($provenanceMetadata.Code)"
    }
}
$releaseProvenanceState = if ($AllowUnsignedDevelopmentBuild) { 'Unverified' } else { [string]$provenanceMetadata.State }
if ($requiresVerifiedProvenance) {
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $gitCommand) { $gitCommand = Get-Command git -ErrorAction SilentlyContinue }
    if (-not $gitCommand) { throw 'Build stable cần Git để ràng buộc provenance với source commit.' }
    $headCommit = (& $gitCommand.Source -C $sourceDirectory rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
    $provenanceDocument = Get-Content -LiteralPath (Join-Path $sourceDirectory 'OFFICIAL-PROVENANCE-v1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $declaredCommit = ([string]$provenanceDocument.SourceSnapshotCommit).Trim().ToLowerInvariant()
    if ($declaredCommit -notmatch '^[0-9a-f]{40}$') { throw 'Provenance SourceSnapshotCommit không phải commit SHA-1 đầy đủ.' }
    & $gitCommand.Source -C $sourceDirectory merge-base --is-ancestor $declaredCommit $headCommit 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Provenance source snapshot không phải tổ tiên của HEAD: manifest=$declaredCommit, HEAD=$headCommit"
    }
    $releaseMetadataAllowList = @(
        'OFFICIAL-PROVENANCE-v1.json',
        'OFFICIAL-PROVENANCE-v1.json.p7s',
        'SOURCE-PACKAGE-SHA256SUMS.txt',
        'SOURCE-SHA256SUMS.txt',
        'TOOL-SHA256SUMS.txt',
        'update-manifest-v1.json',
        'update-manifest-v1.json.p7s'
    )
    $postSnapshotChanges = @(& $gitCommand.Source -C $sourceDirectory diff --name-only $declaredCommit $headCommit -- | ForEach-Object { ([string]$_).Replace('\','/') })
    $unexpectedPostSnapshotChanges = @($postSnapshotChanges | Where-Object { $releaseMetadataAllowList -notcontains $_ })
    if ($unexpectedPostSnapshotChanges.Count -gt 0) {
        throw "Có mã nguồn thay đổi sau SourceSnapshotCommit ngoài allowlist metadata phát hành: $($unexpectedPostSnapshotChanges -join ', ')"
    }
    $worktreeChanges = @(& $gitCommand.Source -C $sourceDirectory status --porcelain --untracked-files=all)
    if ($worktreeChanges.Count -gt 0) { throw 'Build stable yêu cầu worktree sạch và mọi tệp nguồn đều đã được Git theo dõi trước khi tạo artefact.' }
}
$assistantMetadata = Get-ToolAssistantMetadata
$pluginMetadata = Get-ToolPluginMetadata
$softwareCatalogMetadata = Import-ToolSoftwareCatalogFile `
    -Path (Join-Path $sourceDirectory 'software-license-catalog-v1.0.json') `
    -SignaturePath (Join-Path $sourceDirectory 'software-license-catalog-v1.0.json.p7s') `
    -Source 'Bundled' -RequireSignature
if (-not $softwareCatalogMetadata -or -not [bool]$softwareCatalogMetadata.CatalogSignatureValid) {
    throw 'Catalog phần mềm tích hợp thiếu chữ ký CMS hợp lệ từ signer đã ghim.'
}
$engineeringCatalogRules = @($softwareCatalogMetadata.Products | Where-Object {
    $_.PSObject.Properties['Category'] -and -not [string]::IsNullOrWhiteSpace([string]$_.Category)
})
if ([string]$softwareCatalogMetadata.CatalogVersion -ne '1.6.3.0' -or
    [string]$softwareCatalogMetadata.GeneratedAtUtc -ne '2026-08-31T06:05:00Z' -or
    @($softwareCatalogMetadata.Products).Count -lt 94 -or $engineeringCatalogRules.Count -lt 16) {
    throw 'Catalog phần mềm tích hợp cho v5.0 chưa đạt phiên bản 1.6.3.0 / ngày bảo trì 2026-08-31T06:05:00Z / 94 quy tắc / 16 quy tắc kỹ thuật.'
}

Write-Host '[1/8] Tạo TOOL-SHA256SUMS.txt...'
$toolManifestLines = @(
    "# Manifest kiem tra toan ven bo Tool-Kiem-Tra v$productVersion.",
    '# approved-kms-servers.txt duoc loai tru vi la tep cau hinh duoc phep tuy chinh.'
)
foreach ($name in $integrityFiles) {
    $toolManifestLines += "$(Get-Sha256Hex (Join-Path $sourceDirectory $name))  $name"
}
[IO.File]::WriteAllLines(
    (Join-Path $sourceDirectory 'TOOL-SHA256SUMS.txt'),
    $toolManifestLines,
    (New-Object Text.UTF8Encoding($false))
)

Write-Host '[2/8] Tạo SOURCE-SHA256SUMS.txt...'
$sourceManifestLines = @(
    "# SHA-256 cua goi ma nguon Tool-Kiem-Tra v$productVersion.",
    '# SOURCE-SHA256SUMS.txt va tep build dau ra khong tu liet ke de tranh tham chieu vong.'
)
foreach ($name in $sourceFiles) {
    $path = Join-Path $sourceDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Không thể tạo source manifest; thiếu: $name" }
    $sourceManifestLines += "$(Get-Sha256Hex $path)  $name"
}
[IO.File]::WriteAllLines(
    (Join-Path $sourceDirectory 'SOURCE-SHA256SUMS.txt'),
    $sourceManifestLines,
    (New-Object Text.UTF8Encoding($false))
)

# Manifest này bao phủ toàn bộ gói mã nguồn bàn giao, kể cả tài liệu và workflow
# nằm trong thư mục con. Nó được tạo lại sau khi manifest cập nhật cuối cùng đã
# được đồng bộ về nguồn để không giữ hash của bản cũ.
Write-SourcePackageHashManifest

Write-Host '[3/8] Chuẩn bị thư mục đầu ra...'
if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
$compiler = Find-CSharpCompiler
$compilerVersion = (Get-Item -LiteralPath $compiler).VersionInfo.FileVersion
$payloadListArgument = $payloadFiles -join '|'
$targets = @(
    [pscustomobject]@{ Architecture='AnyCPU'; Platform='anycpu'; OutputName="Tool-Kiem-Tra-v$productVersion.exe"; HighEntropy=$true }
)
$artifactResults = New-Object System.Collections.Generic.List[object]
$embeddedPayloadResources = New-Object System.Collections.Generic.List[object]
$payloadCompressionStats = $null

foreach ($staleName in @("Tool-Kiem-Tra-v$productVersion-x64.exe", "Tool-Kiem-Tra-v$productVersion-x86.exe")) {
    $stalePath = Join-Path $OutputDirectory $staleName
    if (Test-Path -LiteralPath $stalePath -PathType Leaf) { Remove-Item -LiteralPath $stalePath -Force }
}

$payloadBuildDirectory = Join-Path $OutputDirectory ('.payload-build-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $payloadBuildDirectory | Out-Null
    $compilerSourcePath = Join-Path $sourceDirectory $sourceName
    $compilerSourceText = [IO.File]::ReadAllText($compilerSourcePath, [Text.Encoding]::UTF8)
    $buildIdConstantPattern = 'private const string OfficialBuildId = "REPLACE_AT_BUILD_FROM_TOOL_PROVENANCE";'
    if ([regex]::Matches($compilerSourceText, $buildIdConstantPattern).Count -ne 1) {
        throw 'Launcher source phải chứa đúng một placeholder OfficialBuildId do BUILD.ps1 quản lý.'
    }
    $compilerSourceText = [regex]::Replace(
        $compilerSourceText,
        $buildIdConstantPattern,
        ('private const string OfficialBuildId = "' + $officialBuildId + '";'),
        1)
    if ($requiresSignedArtifact) {
        $signerConstantPattern = 'private const string OfficialSignerThumbprint = "[A-Fa-f0-9]{40}";'
        if (-not [regex]::IsMatch($compilerSourceText, $signerConstantPattern)) {
            throw 'Không tìm thấy OfficialSignerThumbprint hợp lệ trong launcher source.'
        }
        $compilerSourceText = [regex]::Replace(
            $compilerSourceText,
            $signerConstantPattern,
            ('private const string OfficialSignerThumbprint = "' + $normalizedStableSignerThumbprint + '";'),
            1)
        $signerCertificateSha256 = ([string]$releaseIdentity.SignerCertificateSha256).Replace(' ', '').ToUpperInvariant()
        if ($signerCertificateSha256 -notmatch '^[A-F0-9]{64}$') {
            throw 'Tool-Provenance.ps1 thiếu SHA-256 chứng thư signer hợp lệ.'
        }
        $signerCertificateSha256Pattern = 'private const string OfficialSignerCertificateSha256 = "[A-Fa-f0-9]{64}";'
        if (-not [regex]::IsMatch($compilerSourceText, $signerCertificateSha256Pattern)) {
            throw 'Không tìm thấy OfficialSignerCertificateSha256 hợp lệ trong launcher source.'
        }
        $compilerSourceText = [regex]::Replace(
            $compilerSourceText,
            $signerCertificateSha256Pattern,
            ('private const string OfficialSignerCertificateSha256 = "' + $signerCertificateSha256 + '";'),
            1)
    }
    $compilerSourcePath = Join-Path $payloadBuildDirectory $sourceName
    [IO.File]::WriteAllText($compilerSourcePath, $compilerSourceText, (New-Object Text.UTF8Encoding($false)))
    $payloadBundlePath = Join-Path $payloadBuildDirectory 'payload.bundle.v1'
    $compressedPayloadPath = Join-Path $payloadBuildDirectory 'payload.bundle.v1.deflate'
    $bundleStats = New-SolidPayloadBundle -SourceDirectory $sourceDirectory -PayloadFiles $payloadFiles -DestinationPath $payloadBundlePath
    New-DeflatedPayloadFile -SourcePath $payloadBundlePath -DestinationPath $compressedPayloadPath
    [int64]$payloadEmbeddedBytes = (Get-Item -LiteralPath $compressedPayloadPath).Length
    if ($payloadEmbeddedBytes -le 0 -or $payloadEmbeddedBytes -ge [int64]$bundleStats.BundleBytes) {
        throw "Solid payload bundle không được nén hợp lệ: $payloadEmbeddedBytes / $($bundleStats.BundleBytes) byte."
    }
    [void]$embeddedPayloadResources.Add([pscustomobject]@{
        Path = $compressedPayloadPath
        ResourceName = 'payload.bundle.deflate.v1'
        SourceBytes = [int64]$bundleStats.SourceBytes
        EmbeddedBytes = [int64]$payloadEmbeddedBytes
    })
    $payloadCompressionStats = [pscustomobject]@{
        Scheme = 'SolidDeflateBundle-v1'
        ResourceName = 'payload.bundle.deflate.v1'
        FormatVersion = [int]$bundleStats.FormatVersion
        ResourceCount = 1
        PayloadCount = [int]$bundleStats.PayloadCount
        HeaderBytes = [int64]$bundleStats.HeaderBytes
        SourceBytes = [int64]$bundleStats.SourceBytes
        BundleBytes = [int64]$bundleStats.BundleBytes
        EmbeddedBytes = [int64]$payloadEmbeddedBytes
        SavedBytes = [int64]$bundleStats.SourceBytes - $payloadEmbeddedBytes
        SavingsPercent = [math]::Round((1.0 - ($payloadEmbeddedBytes / [double]$bundleStats.SourceBytes)) * 100.0, 2)
        MaximumPayloadBytes = [int64]$bundleStats.MaximumPayloadBytes
        MaximumPayloadDataBytes = [int64]$bundleStats.MaximumPayloadDataBytes
        MaximumCompressedBytes = [int64]$bundleStats.MaximumCompressedBytes
        MaximumDecodedBytes = [int64]$bundleStats.MaximumDecodedBytes
    }
    Write-Host "[4/8] Nhúng $($payloadFiles.Count) payload vào một solid Deflate bundle; giảm $($payloadCompressionStats.SavingsPercent)%..."

    foreach ($target in $targets) {
    $outputPath = Join-Path $OutputDirectory $target.OutputName
    Write-Host "  - Build $($target.Architecture): $($target.OutputName)"
    $compilerArguments = @(
        '/nologo',
        '/target:winexe',
        "/platform:$($target.Platform)",
        '/deterministic+',
        "/pathmap:$sourceDirectory=C:\_src\Tool-Kiem-Tra-v5.0",
        '/langversion:5',
        '/debug-',
        '/optimize+',
        '/warn:4',
        '/codepage:65001',
        '/reference:System.dll',
        '/reference:System.Windows.Forms.dll',
        '/reference:System.Drawing.dll',
        "/win32icon:$(Join-Path $sourceDirectory '00-Tool-Kiem-Tra.ico')",
        "/win32manifest:$(Join-Path $sourceDirectory $applicationManifestName)",
        "/out:$outputPath"
    )
    if ($RequireAuthenticode) {
        # This compile-time marker is deliberately absent from unsigned
        # development builds, even when they have the same version number as
        # the public stable release.
        $compilerArguments += '/define:TOOL_SIGNED_STABLE_BUILD'
    } elseif ($AllowManagedSignedBuild) {
        # Managed builds are signed, timestamped and provenance-verified, but
        # they must never inherit the public Stable self-update marker.
        $compilerArguments += '/define:TOOL_MANAGED_SIGNED_BUILD'
    } elseif ($AllowStoreBuild) {
        # Partner Center signs the MSIX package, not this pre-submission EXE.
        # Runtime trust is therefore bound to the exact Windows package
        # identity instead of an Authenticode marker on the inner executable.
        $compilerArguments += '/define:TOOL_STORE_BUILD'
    }
    if ($target.HighEntropy) { $compilerArguments += '/highentropyva+' }
    foreach ($resource in $embeddedPayloadResources) {
        $compilerArguments += "/resource:$($resource.Path),$($resource.ResourceName)"
    }
    $compilerArguments += $compilerSourcePath

    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Biên dịch $($target.Architecture) thất bại, mã thoát: $LASTEXITCODE"
    }

    $profile = Get-PeSecurityProfile -Path $outputPath
    if ($profile.ManagedPlatform -ne 'AnyCPU') { throw "CLR flags không phải AnyCPU: $($profile.ManagedPlatform)." }
    foreach ($requiredFlag in @('DynamicBase', 'NxCompat', 'NoSeh', 'TerminalServerAware')) {
        if (-not [bool]$profile.$requiredFlag) { throw "Bản $($target.Architecture) thiếu cờ $requiredFlag." }
    }
    if ($profile.PeFormat -ne 'PE32' -or $profile.Machine -ne '0x014C' -or
        -not $profile.Managed -or -not $profile.ClrIlOnly -or
        $profile.Clr32BitRequired -or $profile.Clr32BitPreferred -or
        -not $profile.HighEntropyVa) {
        throw 'EXE chưa đúng AnyCPU: cần PE32/I386, ILONLY, không 32BITREQUIRED/32BITPREFERRED và bật HIGH_ENTROPY_VA.'
    }

    foreach ($runtimeArchitecture in @('x64', 'x86')) {
        $verificationPowerShell = Get-VerificationPowerShell $runtimeArchitecture
        $expectedTrustMode = if ($RequireAuthenticode) { 'Production' } elseif ($AllowManagedSignedBuild) { 'ManagedSigned' } elseif ($AllowStoreBuild) { 'StoreSubmission' } else { 'DevelopmentUnsigned' }
        & $verificationPowerShell -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $sourceDirectory $embeddedVerifierName) `
            -ExePath $outputPath -SourceDirectory $sourceDirectory -PayloadList $payloadListArgument -ExpectedArchitecture $runtimeArchitecture -ExpectedTrustMode $expectedTrustMode
        if ($LASTEXITCODE -ne 0) { throw "Đối chiếu cùng EXE AnyCPU trên CLR $runtimeArchitecture thất bại, mã thoát: $LASTEXITCODE" }
    }

    $signingRequested = -not [string]::IsNullOrWhiteSpace($SigningCertificateThumbprint) -or -not [string]::IsNullOrWhiteSpace($SigningPfxPath)
    if ($signingRequested) {
        Write-Host "  - Ký Authenticode SHA-256: $($target.OutputName)"
        $signingScript = Join-Path $sourceDirectory 'SIGN-RELEASE.ps1'
        if (-not [string]::IsNullOrWhiteSpace($SigningCertificateThumbprint)) {
            & $signingScript -FilePath $outputPath -CertificateThumbprint $SigningCertificateThumbprint `
                -StoreLocation $SigningCertificateStore -TimestampServer $TimestampServer -RequireTrustedSignature:$requiresSignedArtifact `
                -RequireWindowsTrustedCaCertificate:$RequireAuthenticode
        } else {
            if ($null -eq $SigningPfxPassword) { throw 'SigningPfxPassword là bắt buộc khi dùng SigningPfxPath.' }
            & $signingScript -FilePath $outputPath -PfxPath $SigningPfxPath -PfxPassword $SigningPfxPassword `
                -TimestampServer $TimestampServer -RequireTrustedSignature:$requiresSignedArtifact
        }
        if ($LASTEXITCODE -ne 0) { throw "Ký Authenticode thất bại, mã thoát: $LASTEXITCODE" }
    } elseif ($requiresSignedArtifact) {
        throw 'Chế độ build có chữ ký được bật nhưng chưa cung cấp chứng thư code-signing.'
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $outputPath
    if ($requiresSignedArtifact -and $signature.Status -ne 'Valid') {
        throw "Artefact chưa có chữ ký Authenticode hợp lệ: $($signature.Status)"
    }
    if ($requiresSignedArtifact -and $null -eq $signature.TimeStamperCertificate) {
        throw 'Artefact có chữ ký nhưng chưa có RFC 3161 timestamp.'
    }
    $artifactLength = [int64](Get-Item -LiteralPath $outputPath).Length
    if ($artifactLength -gt $maximumInPlaceExecutableBytes) {
        throw "EXE vượt ngân sách dung lượng bản v5.0: $artifactLength / $maximumInPlaceExecutableBytes byte."
    }
    [void]$artifactResults.Add([pscustomobject]@{
        FileName = $target.OutputName
        Architecture = 'AnyCPU'
        RuntimeArchitecture = 'Auto: x64 on Windows 64-bit; x86 on Windows 32-bit'
        Sha256 = Get-Sha256Hex $outputPath
        AuthenticodeStatus = [string]$signature.Status
        AuthenticodeSigner = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        AuthenticodeThumbprint = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Thumbprint } else { '' }
        AuthenticodeTimestamped = [bool]($null -ne $signature.TimeStamperCertificate)
        PeProfile = $profile
    })
    }
} finally {
    if (Test-Path -LiteralPath $payloadBuildDirectory -PathType Container) {
        Remove-Item -LiteralPath $payloadBuildDirectory -Recurse -Force
    }
}

Write-Host '[5/8] Tạo metadata phát hành...'
$releaseSidecars = @(
    'approved-kms-servers.txt', 'HUONG-DAN.txt', 'USER-GUIDE-en-US.md', 'LICH-SU-PHIEN-BAN.txt', 'VERSION-HISTORY-en-US.md', 'LICENSE-NOTICE.txt',
    'SOURCE-POLICY-v4.9.md', 'RELEASE-NOTES-v5.0.md', 'OFFICIAL-PROVENANCE-v1.json', 'OFFICIAL-PROVENANCE-v1.json.p7s',
    'MODULE-CONTRACT-v1.0.md', 'REPORT-SCHEMA-v1.5.md', 'SAFETY-POLICY-v1.0.md',
    'SECURITY.md', 'AUDIT-SCOPE-v1.md', 'SECURITY-REVIEW-PROCESS-v1.md', 'SECURITY-REVIEW-ATTESTATION-TEMPLATE-v1.json', 'SECURITY-TEST-RESULTS.md', 'CODE-SIGNING-POLICY-v1.md',
    'PLUGIN-PUBLISHER-TRUST-v1.md', 'REPORT-VIEWER-POLICY-v1.md',
    'TECHNICAL-ARCHITECTURE-v4.8.md', 'ENTRY-POINTS-v4.8.md', 'COMPATIBILITY-MATRIX-v4.8.md',
    'OFFLINE-AND-REPORTING-v4.8.md', 'LOCALIZATION-v1.0.md', 'SECURITY-HARDENING-v4.8.md',
    'compatibility-catalog-v1.0.json', 'software-license-catalog-v1.0.json', 'software-license-catalog-v1.0.json.p7s', 'builtin-windows-office-trust.plugin.json', 'tool-assistant-knowledge-v1.1.json', 'tool-assistant-knowledge-v1.1.json.p7s'
)
if ($AllowUnsignedDevelopmentBuild) {
    $releaseSidecars = @($releaseSidecars | Where-Object { $_ -ne $provenanceSignatureName })
    $staleDevelopmentProvenanceSignature = Join-Path $OutputDirectory $provenanceSignatureName
    if (Test-Path -LiteralPath $staleDevelopmentProvenanceSignature -PathType Leaf) {
        Remove-Item -LiteralPath $staleDevelopmentProvenanceSignature -Force
    }
}
foreach ($sidecar in $releaseSidecars) {
    Copy-Item -LiteralPath (Join-Path $sourceDirectory $sidecar) -Destination (Join-Path $OutputDirectory $sidecar) -Force
}

$manifestArtifacts = @($artifactResults.ToArray() | ForEach-Object {
    [ordered]@{
        FileName = $_.FileName
        Architecture = $_.Architecture
        RuntimeArchitecture = $_.RuntimeArchitecture
        Sha256 = $_.Sha256
        AuthenticodeStatus = $_.AuthenticodeStatus
        AuthenticodeSigner = $_.AuthenticodeSigner
        AuthenticodeThumbprint = $_.AuthenticodeThumbprint
        AuthenticodeTimestamped = $_.AuthenticodeTimestamped
        Pe = [ordered]@{
            Format = $_.PeProfile.PeFormat
            Machine = $_.PeProfile.Machine
            ManagedPlatform = $_.PeProfile.ManagedPlatform
            Managed = $_.PeProfile.Managed
            IlOnly = $_.PeProfile.ClrIlOnly
            Required32Bit = $_.PeProfile.Clr32BitRequired
            Preferred32Bit = $_.PeProfile.Clr32BitPreferred
            LargeAddressAware = $_.PeProfile.LargeAddressAware
            HighEntropyVa = $_.PeProfile.HighEntropyVa
            DynamicBase = $_.PeProfile.DynamicBase
            NxCompat = $_.PeProfile.NxCompat
            NoSeh = $_.PeProfile.NoSeh
            TerminalServerAware = $_.PeProfile.TerminalServerAware
            ControlFlowGuardHeader = $_.PeProfile.ControlFlowGuardHeader
            LoadConfigurationDirectoryPresent = $_.PeProfile.LoadConfigurationDirectoryPresent
        }
    }
})
$releaseManifestPath = Join-Path $OutputDirectory 'RELEASE-MANIFEST.json'
$releaseStatus = if ($AllowUnsignedDevelopmentBuild) {
    'DevelopmentUnsigned'
} elseif ($AllowStoreBuild) {
    'StoreSubmission'
} elseif ($AllowManagedSignedBuild) {
    'ManagedSigned'
} else {
    'Production'
}
$primaryArtifact = @($artifactResults.ToArray())[0]
$primaryArtifactPath = Join-Path $OutputDirectory $primaryArtifact.FileName
$sbomPath = Join-Path $OutputDirectory 'SBOM.cdx.json'
$sbomSourceCommit = [string](Get-Content -LiteralPath $provenanceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).SourceSnapshotCommit
$sbomActionComponents = @(
    [ordered]@{
        type = 'library'; 'bom-ref' = 'github-actions:actions/checkout@11d5960a326750d5838078e36cf38b85af677262'
        name = 'actions/checkout'; version = '4.4.0'; licenses = @([ordered]@{ license = [ordered]@{ id = 'MIT' } })
        properties = @([ordered]@{ name = 'tool:gitCommit'; value = '11d5960a326750d5838078e36cf38b85af677262' })
    },
    [ordered]@{
        type = 'library'; 'bom-ref' = 'github-actions:actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02'
        name = 'actions/upload-artifact'; version = '4.6.2'; licenses = @([ordered]@{ license = [ordered]@{ id = 'MIT' } })
        properties = @([ordered]@{ name = 'tool:gitCommit'; value = 'ea165f8d65b6e75b540449e92b4886f43607fa02' })
    },
    [ordered]@{
        type = 'library'; 'bom-ref' = 'github-actions:actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093'
        name = 'actions/download-artifact'; version = '4.3.0'; licenses = @([ordered]@{ license = [ordered]@{ id = 'MIT' } })
        properties = @([ordered]@{ name = 'tool:gitCommit'; value = 'd3f86a106a0bac45b974a628896c90dbdf5c8093' })
    }
)
$sbomRuntimeComponents = @(
    [ordered]@{ type = 'framework'; 'bom-ref' = 'runtime:dotnet-framework-4'; name = '.NET Framework'; version = '4 / CLR v4' },
    [ordered]@{ type = 'framework'; 'bom-ref' = 'runtime:windows-powershell-3'; name = 'Windows PowerShell'; version = '3+' },
    [ordered]@{ type = 'application'; 'bom-ref' = 'build:compiler-csc'; name = 'Microsoft C# Compiler'; version = [string]$compilerVersion }
)
$sbomComponentRefs = @($sbomRuntimeComponents + $sbomActionComponents | ForEach-Object { [string]$_['bom-ref'] })
$sbomDocument = [ordered]@{
    bomFormat = 'CycloneDX'
    specVersion = '1.5'
    version = 1
    metadata = [ordered]@{
        timestamp = $publishedAtUtc
        tools = @([ordered]@{ vendor = 'Thanh Viet'; name = 'BUILD.ps1'; version = $releaseVersion })
        component = [ordered]@{
            type = 'application'; 'bom-ref' = 'application:tool-kiem-tra'
            name = 'Tool Kiem Tra'; version = $releaseVersion
            hashes = @([ordered]@{ alg = 'SHA-256'; content = [string]$primaryArtifact.Sha256 })
            licenses = @([ordered]@{ license = [ordered]@{ name = 'Proprietary' } })
            properties = @(
                [ordered]@{ name = 'tool:buildId'; value = $officialBuildId },
                [ordered]@{ name = 'tool:sourceSnapshotCommit'; value = $sbomSourceCommit },
                [ordered]@{ name = 'tool:releaseStatus'; value = $releaseStatus }
            )
        }
    }
    components = @($sbomRuntimeComponents + $sbomActionComponents)
    dependencies = @([ordered]@{ ref = 'application:tool-kiem-tra'; dependsOn = $sbomComponentRefs })
}
[IO.File]::WriteAllText($sbomPath, ($sbomDocument | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
$sbomSha256 = Get-Sha256Hex $sbomPath
$releaseManifest = [ordered]@{
    SchemaVersion = '2.0'
    ToolVersion = $productVersion
    ReleaseVersion = $releaseVersion
    ReleaseBuildDate = $releaseBuildDate
    ReleaseLabel = $releaseLabel
    ReleaseStatus = $releaseStatus
    PrimaryFileName = "Tool-Kiem-Tra-v$productVersion.exe"
    RuntimeArchitecture = 'Auto: x64 on Windows 64-bit; x86 on Windows 32-bit'
    Artifacts = $manifestArtifacts
    Sbom = [ordered]@{
        FileName = 'SBOM.cdx.json'
        Format = 'CycloneDX'
        SpecVersion = '1.5'
        Sha256 = $sbomSha256
    }
    PayloadCount = [int]$payloadFiles.Count
    IntegrityFileCount = [int]$integrityFiles.Count
    PayloadCompression = [ordered]@{
        Scheme = [string]$payloadCompressionStats.Scheme
        ResourceName = [string]$payloadCompressionStats.ResourceName
        FormatVersion = [int]$payloadCompressionStats.FormatVersion
        ResourceCount = [int]$payloadCompressionStats.ResourceCount
        PayloadCount = [int]$payloadCompressionStats.PayloadCount
        HeaderBytes = [int64]$payloadCompressionStats.HeaderBytes
        SourceBytes = [int64]$payloadCompressionStats.SourceBytes
        BundleBytes = [int64]$payloadCompressionStats.BundleBytes
        EmbeddedBytes = [int64]$payloadCompressionStats.EmbeddedBytes
        SavedBytes = [int64]$payloadCompressionStats.SavedBytes
        SavingsPercent = [double]$payloadCompressionStats.SavingsPercent
        MaximumPayloadBytes = [int64]$payloadCompressionStats.MaximumPayloadBytes
        MaximumPayloadDataBytes = [int64]$payloadCompressionStats.MaximumPayloadDataBytes
        MaximumCompressedBytes = [int64]$payloadCompressionStats.MaximumCompressedBytes
        MaximumDecodedBytes = [int64]$payloadCompressionStats.MaximumDecodedBytes
    }
    FrameworkTarget = '.NET Framework 4 / CLR v4'
    PowerShellTarget = 'Windows PowerShell 3+'
    CapabilitySchemaVersion = '1.1'
    LogSchemaVersion = '1.0-jsonl'
    DashboardSchemaVersion = '2.0'
    DashboardMode = 'Modern adaptive WinForms dashboard'
    StartupExecutionLevel = 'asInvoker'
    ElevationPolicy = 'On demand for system changes, application update and enterprise administration'
    DefaultDataRoot = '%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra\v4.6'
    ElevatedDataRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6'
    StartupTheme = 'System'
    DarkMode = 'System-aware Light/Dark preference with persisted explicit override and WCAG-aware palette'
    DpiAwareness = 'PerMonitorV2 -> PerMonitor -> System-aware fallback; Win7 remains supported'
    QuickActionNumberLabels = $false
    DirectReportActionCount = 8
    ResultActionCenter = $true
    ResultSearchAndFilters = $true
    PreviousScanComparison = $true
    BackupRestoreCenter = $true
    PrivacySafeSupportBundle = $true
    OfflinePolicySchemaVersion = [string]$offlinePolicyMetadata.SchemaVersion
    OfflineDefault = [string]$offlinePolicyMetadata.DefaultMode
    OfflineResetOnEveryLaunch = $true
    OfflineBlockedScopes = @($offlinePolicyMetadata.BlockedScopes)
    RuntimeTelemetry = [string]$offlinePolicyMetadata.Telemetry
    AutomaticUpdateCheck = [bool]$offlinePolicyMetadata.AutomaticUpdateCheck
    AutomaticUpdateCheckTrigger = [string]$offlinePolicyMetadata.AutomaticUpdateCheckTrigger
    BackgroundUpdateService = [bool]$offlinePolicyMetadata.BackgroundUpdateService
    SilentUpdate = [bool]$offlinePolicyMetadata.SilentUpdate
    ApplicationUpdateSchemaVersion = '1.0'
    ApplicationSelfUpdateAllowed = $applicationSelfUpdateAllowed
    ApplicationUpdateAuthority = $applicationUpdateAuthority
    BundledUpdateManifestChannel = $bundledUpdateManifestChannel
    ApplicationUpdateManifestUrl = 'https://raw.githubusercontent.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/main/update-manifest-v1.json'
    ApplicationUpdateManifestSignatureUrl = 'https://raw.githubusercontent.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/main/update-manifest-v1.json.p7s'
    ApplicationUpdateChoices = @('UpdateNow','Later','DismissForSession')
    ApplicationUpdateDeferral = 'After next completed task or 2 hours; next launch rechecks only when Online is allowed'
    ApplicationUpdateVerification = 'Pinned detached-CMS manifest + fixed GitHub HTTPS allowlist + declared size + SHA-256 + mandatory pinned Authenticode signer for stable + rollback'
    OfficialBuildProvenance = [ordered]@{
        State = $releaseProvenanceState
        BuildId = $officialBuildId
        ManifestFile = 'OFFICIAL-PROVENANCE-v1.json'
        SignatureFile = 'OFFICIAL-PROVENANCE-v1.json.p7s'
        VerificationUrl = 'https://thanhvietithopnghia-rgb.github.io/Tool-Kiem-Tra-Ban-Quyen/#verify-official-build'
        SourcePolicyId = 'ThanhViet.ToolKiemTra.CommunityControlledSource.v4.9'
        SourceDistribution = 'CommunityControlledSource'
        RuntimeSystemChangePolicy = $(if ($AllowStoreBuild) { 'Microsoft Store package identity and pinned provenance must both verify before system-change actions' } else { 'Official launcher and pinned provenance must both verify before system-change actions' })
    }
    LocalizationSchemaVersion = [string]$localizationMetadata.SchemaVersion
    DefaultCulture = [string]$localizationMetadata.DefaultCulture
    SupportedCultures = @($localizationMetadata.SupportedCultures)
    CompatibilitySchemaVersion = [string]$compatibilityMetadata.SchemaVersion
    CompatibilityCatalogSchemaVersion = [string]$compatibilityMetadata.CatalogSchemaVersion
    CompatibilityCatalogVersion = [string]$compatibilityMetadata.CatalogVersion
    CompatibilityCatalogReviewedAtUtc = [string]$compatibilityMetadata.ReviewedAtUtc
    CompatibilityCatalogAgeDays = [int]$compatibilityMetadata.CatalogAgeDays
    CompatibilityCatalogHealth = [string]$compatibilityMetadata.CatalogHealth
    CompatibilityCatalogFresh = [bool]$compatibilityMetadata.CatalogFresh
    CompatibilityCatalogReviewWarningAgeDays = [int]$compatibilityMetadata.ReviewWarningAgeDays
    CompatibilityCatalogMaximumReviewAgeDays = [int]$compatibilityMetadata.MaximumReviewAgeDays
    FutureCompatibilityMode = [string]$compatibilityMetadata.FutureCompatibilityMode
    SupportedWindowsReleases = @($compatibilityMetadata.WindowsReleaseNames)
    SupportedOfficeFamilies = @($compatibilityMetadata.OfficeFamilyNames)
    CleanupActionCenter = $true
    AutomaticSafeCleanup = 'Registry allowlist plus decisive-evidence third-party scopes with a scope-locked safe plan; preview + confirmation + HMAC backup + UAC + post-verification'
    ElevatedModuleEnvironmentBridge = 'Encoded allowlisted TOOL_* contract + schema/age/module/invocation validation + protected runtime restoration + child exit-code propagation'
    AssuranceCenter = $true
    Function5Compatibility = 'v4.3.0.3 title, primary tables, assessment and summary-card layout preserved'
    ThirdPartySoftwareInspection = 'All-source installed-software inventory + vendor-neutral bounded deep scan + conservative evidence scoring'
    NormalReportActivatorInspection = 'Windows/Office-only reports inspect current process/service/startup/task and bounded file evidence for MAS/PMAS, Activation Program 1.17, exact erturk-dev.netlify.app/run commands, TSforge, OHook, KMS tools and Microsoft Toolkit'
    NormalSoftwareInstalledArtifactInspection = 'Bounded scan of priority paid/trial/review application install roots plus user and shared data roots'
    WindowsKmsLifecyclePresentation = 'KMS channel remains visible in Notification state; grace minutes/days/expiry and approved-host trust are reported separately from entitlement'
    InstallDateNormalization = 'Registry yyyyMMdd, CIM datetime and plausible Unix epoch values normalize to yyyy-MM-dd'
    MonitorNameSources = @('WmiMonitorID EDID','Win32_DesktopMonitor','Win32_PnPEntity')
    ReportPrivacyChoice = @('Redacted copy','Full internal copy','Cancel')
    TimelineCurrentStatePolicy = 'Latest observed state is separated from retained historical events; removed evidence is not presented as current'
    UniversalDeepSoftwareScan = $true
    SoftwareLicenseCatalogVersion = [string]$softwareCatalogMetadata.CatalogVersion
    SoftwareLicenseCatalogGeneratedAtUtc = [string]$softwareCatalogMetadata.GeneratedAtUtc
    SoftwareLicenseCatalogFreshnessStatus = [string]$softwareCatalogMetadata.CatalogFreshnessStatus
    SoftwareLicenseCatalogFreshForDecisiveEvidence = [bool]$softwareCatalogMetadata.CatalogFreshForDecisiveEvidence
    SoftwareLicenseCatalogAgeDays = [double]$softwareCatalogMetadata.CatalogAgeDays
    SoftwareLicenseCatalogFreshnessWarningAgeDays = [int]$softwareCatalogMetadata.CatalogFreshnessWarningAgeDays
    SoftwareLicenseCatalogFreshnessMaximumAgeDays = [int]$softwareCatalogMetadata.CatalogFreshnessMaximumAgeDays
    SoftwareLicenseCatalogProductRules = [int]@($softwareCatalogMetadata.Products).Count
    SoftwareLicenseCatalogSignatureFile = 'software-license-catalog-v1.0.json.p7s'
    SoftwareLicenseCatalogSignatureRequired = $true
    SoftwareLicenseCatalogSignerCertificateSha256 = $script:ToolSoftwareCatalogSignerCertificateSha256
    EngineeringSoftwareCatalogRules = [int]$engineeringCatalogRules.Count
    EngineeringSoftwareCategories = @($engineeringCatalogRules | ForEach-Object { [string]$_.Category } | Sort-Object -Unique)
    SoftwareInventoryDeduplication = 'Compatible name/version/publisher/location records are merged while retaining all discovery sources'
    SystemSoftwarePresentation = 'Hidden from main application tables; available through HTML internal link and a full PDF/JSON appendix'
    FileIntegrityAssessment = 'HashMismatch maps to IntegrityCompromised and does not alone prove non-genuine entitlement'
    DeepSoftwareScanEvidence = @('Multiple EXE/DLL Authenticode','Trusted known-bad SHA-256','Activator/artifact identity','IFEO','Firewall','Disabled licensing service','Autorun','Task/service/process/folder correlation','Blocked licensing domains')
    DeepSoftwareScanScoring = 'CrackConfirmed requires direct known hash, active activator, or a direct artifact with independent corroboration; generic/moderate evidence remains Suspicious; incomplete coverage remains Unverified'
    DeepSoftwareScanBudgetPolicy = 'Bounded time/depth/files/signatures/hashes; weighted budgeting prioritizes paid/trial/evidence-bearing software while reserving coverage for unknown/free applications'
    DeepSoftwareScanCatalogTrust = 'Only bundled or pinned-signer, schema-validated online-cache rules may contribute to decisive evidence; raw or forged catalog objects are rejected'
    ThirdPartyLicenseRemediationAdapters = @('Adobe shared licensing stores are never reset','Autodesk/AutoCAD shared licensing stores are never reset','WinRAR local license files are observed only and never automatically reset','Generic direct-artifact quarantine + bounded hosts repair; firewall/process/service/task/registry/folder/reinstall stay manual-only')
    ThirdPartyAutomaticResetPolicy = 'No third-party license store is reset automatically; verified decisive direct evidence permits only exact artifact quarantine with hash/size revalidation or bounded hosts repair, and all other actions are manual-only'
    ThirdPartyBackupPolicy = 'HMAC-protected inventory and quarantine; unauthorized activators and licensing tokens are non-restorable'
    ThirdPartyPostCleanupQueuePolicy = 'Post-verification requeues only current activator/tampering evidence; inventory-only Unverified state remains reportable but is not remediation residue'
    ThirdPartyStandaloneArtifactPolicy = 'Exact-path activator files in user Downloads/Desktop/TEMP are manual-only quarantine candidates; protected backup/quarantine roots are excluded'
    RemediationDryRun = $true
    RemediationDryRunPolicy = 'Simulation lists exact targets/actions/backup/restorability and performs no system changes; real execution requires a new item confirmation'
    DetailedInventoryExport = $true
    UserGuideExport = 'Embedded vi-VN/en-US source to self-contained HTML/PDF; HTML opens by default'
    DocumentationCache = 'Stable version/culture filename + source SHA-256'
    DocumentationRendererRevision = '2'
    DefaultDocumentationOpenFormat = 'HTMLBeforePdf'
    VersionHistoryCenter = $true
    GuideStyle = 'Function-oriented; chronological changes kept in separate version history'
    SharedUiTypography = 'Segoe UI / GDI+'
    CapabilityFunctionMapping = $true
    EnterpriseLicenseCenter = $true
    EnterpriseNetworkDefault = [string]$offlinePolicyMetadata.EnterpriseNetworkDefault
    EnterpriseNetworkToggle = $true
    EnterpriseNetworkIndependentFromGlobalOffline = $true
    EnterpriseProtocolVersion = '1.0'
    EnterpriseDefaultPort = 49420
    EnterpriseTransport = 'HTTP with AES-256-CBC + HMAC-SHA256 application envelopes'
    EnterpriseRoles = @('Server','Client')
    EnterpriseEndpointDiagnostics = @('InvalidEndpoint','TcpUnavailable','ServiceUnavailable','ServiceRejected','ProtocolMismatch','VersionMismatch','Connected')
    EnterpriseDiscovery = 'Neighbor/ARP + ICMP + TCP probes; blank workstation address invokes local server discovery'
    EnterpriseReportRetry = 'DPAPI-protected local outbox retried by the workstation agent'
    EnterpriseBatchExportFormats = @('JSON','CSV','HTML','PDF')
    EnterpriseBatchExportPrivacy = 'Redacted by default; explicit sensitive export only in a controlled administrative environment'
    EnterpriseCentralAdministration = 'Headless CLI plus idempotent Install/Detect/Repair/Uninstall helper for Intune/MDM or central scripts'
    ClientVmMatrix = @('Windows 10 22H2','Windows 11 previous supported release','Windows 11 current supported release')
    OfficeLicenseEnumeration = 'OSPP /dstatusall per SKU'
    OfficialActivationPostCheck = 'Windows LicenseStatus=1 plus submitted-key Last5; Office OSPP LICENSED plus submitted-key Last5; process exit code alone never confirms activation'
    GenuineLicensePreservation = 'Verified OEM/Retail/MAK or approved organization KMS remains unchanged; readiness for activation is separate from licensed=True'
    OfficeScanExecution = 'Parallel runspace pool with bounded throttle'
    FileScanExecution = 'Parallel per-root enumeration with bounded depth and reparse-point exclusion'
    ScanProfiles = @('Quick','Standard','Deep')
    ScanMaximumExplicitRoots = 8
    ScanLowResourceMode = $true
    ScanRootPolicy = 'Existing absolute local directories only; UNC and reparse-point roots rejected; include/exclude scope is recorded in reports'
    UserPreferencePersistence = @('Culture','Theme','ScanProfileAndScope')
    EnvironmentWarnings = @('VirtualMachine','RemoteDesktop')
    ProgressUtilities = @('CopyAllLog','OpenReportFolder')
    VersionHistoryPresentation = 'InToolModal'
    ReportFormats = @('HTML','PDF','JSON','XML')
    ReportOutputRoot = '%USERPROFILE%\Desktop\BaoCao-Tool-Kiem-Tra'
    ReportPackageLayout = 'One shared Desktop report folder; unique timestamped files stay together without per-scan subfolders'
    ReportAutoOpenPolicy = 'Open HTML only after a completed export'
    LicenseConclusionPolicy = 'Activation is separated from entitlement; KMS and intervention conclusions require direct evidence'
    LicenseUndeterminedPolicy = 'Unreadable licensing data is reported as Undetermined and does not prove valid or invalid entitlement'
    ToolAssistant = [ordered]@{
        SchemaVersion = [string]$assistantMetadata.SchemaVersion
        Scope = [string]$assistantMetadata.Scope
        Engine = [string]$assistantMetadata.Engine
        PaidApiRequired = [bool]$assistantMetadata.PaidApiRequired
        CodexRequired = [bool]$assistantMetadata.CodexRequired
        OnlineTransfer = [string]$assistantMetadata.OnlineTransfer
        ReportUpload = [bool]$assistantMetadata.ReportUpload
        QuestionUpload = [bool]$assistantMetadata.QuestionUpload
        AutomaticRemediation = [bool]$assistantMetadata.AutomaticRemediation
        PortableEveryMachine = [bool]$assistantMetadata.PortableEveryMachine
        CentralServerRequired = [bool]$assistantMetadata.CentralServerRequired
        KnowledgeStorage = [string]$assistantMetadata.KnowledgeStorage
        ReportContextSource = [string]$assistantMetadata.ReportContextSource
        KnowledgeCompatibilityEnforced = [bool]$assistantMetadata.KnowledgeCompatibilityEnforced
        KnowledgeUpdateVerification = [string]$assistantMetadata.KnowledgeUpdateVerification
        KnowledgeRollbackProtection = [bool]$assistantMetadata.KnowledgeRollbackProtection
        UnboundedSelfTraining = [bool]$assistantMetadata.UnboundedSelfTraining
        ExternalTopicLearning = [bool]$assistantMetadata.ExternalTopicLearning
        KnowledgeFileName = [string]$assistantMetadata.KnowledgeFileName
        KnowledgeSignatureFileName = [string]$assistantMetadata.KnowledgeSignatureFileName
        ImmediateResponseRender = $true
    }
    ReportExportSchemaVersion = [string]$reportExportMetadata.SchemaVersion
    ReportHtmlPresentation = [string]$reportExportMetadata.HtmlPresentation
    ReportPdfPresentation = [string]$reportExportMetadata.PdfPresentation
    ReportPdfTheme = [string]$reportExportMetadata.PdfTheme
    ReportContentSplit = 'HTML summary for quick review; PDF contains the complete technical report'
    ReportSummaryWideCardCount = 5
    ReportConclusionPanels = @('VerificationLevel','RecommendedAction')
    PdfFooterLineCount = 2
    DefaultReportOpenFormat = 'HTML'
    DesktopHtmlPdfExport = $true
    UnifiedProfessionalReportUi = $true
    PdfSafePageBreaks = $true
    PdfHeaderFooter = 'Disabled'
    HtmlAssets = 'Embedded local CSS only; CSP default-src none'
    PdfNetworkPolicy = 'Background networking disabled; host resolver mapped to 0.0.0.0'
    PdfEngines = @('Microsoft Edge','Google Chrome','Microsoft Word')
    OptionalReportViewerPolicy = 'WebView2 is not mandatory or bundled; supported Windows may add a signed optional viewer while Win7 and the default-browser/PDF fallback remain functional'
    PdfProfileRoot = [string]$reportExportMetadata.PdfProfileRoot
    PdfProfileAcl = [string]$reportExportMetadata.PdfProfileAcl
    PdfProfileCleanup = [string]$reportExportMetadata.PdfProfileCleanup
    PluginSchemaVersion = [string]$pluginMetadata.SchemaVersion
    PluginModel = [string]$pluginMetadata.Model
    PluginSignaturePolicy = 'Detached CMS SHA-256; administrator-pinned publisher certificate SHA-256; external plugins fail closed in secure launch'
    ThirdPartyPluginCatalogSchemaVersion = [string]$pluginMetadata.ThirdPartyCatalogSchemaVersion
    ThirdPartyPluginCatalogMaximumEntries = [int]$pluginMetadata.MaximumCatalogEntries
    ThirdPartyPluginCatalogFreshness = 'Fresh/Warning remains installable; Stale/Future/Invalid is read-only and blocked from installation'
    ThirdPartyPluginCatalogNetworkPolicy = 'Signed metadata is parsed offline; no automatic download or code execution'
    TimelineSchemaVersion = '1.0'
    TimelineIntegrity = 'DPAPI LocalMachine + HMAC-SHA256 + hash chain'
    CertificateAudit = 'Windows/Office Authenticode + offline chain'
    ReportSchemaVersion = [string]$reportSchemaMetadata.SchemaVersion
    ReportKinds = [int]@($reportSchemaMetadata.ReportKinds).Count
    SafetyPolicySchemaVersion = [string]$safetyPolicyMetadata.SchemaVersion
    ScanRepairChangesStartupType = [bool]$safetyPolicyMetadata.StartupTypeChangesAllowedByQuickRepair
    ModuleContractSchemaVersion = [string]$moduleContractMetadata.ContractSchemaVersion
    ModuleResultSchemaVersion = [string]$moduleContractMetadata.ResultSchemaVersion
    ModuleCount = [int]$moduleContractMetadata.ModuleCount
    ModuleEntryPointCount = [int]$moduleContractMetadata.EntryPointCount
    DataSchemaVersion = '2.0'
    DataProducerVersion = $releaseVersion
    DataStorageGeneration = 'v4.6'
    LegacyDataStorageGeneration = 'v4.4'
    DataMigrationPolicy = 'Verified staging copy + transactional commit + rollback'
    DataConcurrencyPolicy = 'Separate v4.6 write root; launcher blocks detected v4.4/v4.5 mutexes before migration'
    LegacyReadOnlyRoots = @('%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.4\logs','%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.4\backups')
    PersistentLogRoot = '%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra\v4.6\logs (standard UI); %ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\logs (elevated modes)'
    PersistentPluginRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\plugins'
    PersistentTimelineRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\timeline'
    PersistentEnterpriseRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\enterprise'
    CompilerFileVersion = [string]$compilerVersion
    DeterministicManagedBuild = $true
    DeterministicScope = 'Unsigned managed image; Authenticode intentionally changes final bytes when enabled.'
    AuthenticodeRequired = $requiresSignedArtifact
    AuthenticodeTrustScope = $(if ($AllowUnsignedDevelopmentBuild) { 'None' } elseif ($AllowStoreBuild) { 'MicrosoftStorePackageIdentity' } elseif ($AllowManagedSignedBuild) { 'PinnedSelfSignedPortable' } else { 'PublicWindowsTrust' })
    ControlFlowGuard = [ordered]@{
        Status = 'NotClaimed'
        Reason = 'Launcher la managed IL; CSC khong tao CFG instrumentation/load-config native. Khong gan co GUARD_CF gia.'
    }
    BuiltAtUtc = [DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($releaseManifestPath, ($releaseManifest | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))

$updateSignerThumbprints = @()
$updateAuthenticodeRequired = $requiresSignedArtifact
if ($updateAuthenticodeRequired) {
    if ($primaryArtifact.AuthenticodeStatus -ne 'Valid' -or
        [string]::IsNullOrWhiteSpace([string]$primaryArtifact.AuthenticodeThumbprint)) {
        throw 'Stable update manifest requires a valid Authenticode signature and signer thumbprint.'
    }
    $updateSignerThumbprints = @(([string]$primaryArtifact.AuthenticodeThumbprint).Replace(' ', '').ToUpperInvariant())
}
$applicationUpdateManifest = [ordered]@{
    SchemaVersion = '1.0'
    Channel = $bundledUpdateManifestChannel
    LatestVersion = $releaseVersion
    MinimumUpdaterVersion = '4.6.1.0'
    PublishedAtUtc = $publishedAtUtc
    Title = [ordered]@{
        'vi-VN' = 'v5.0.0.1 - Trợ lý đọc đầy đủ HDSD và lịch sử phiên bản'
        'en-US' = 'v5.0.0.1 - Complete guide and version-history support in Tool Assistant'
    }
    Changes = [ordered]@{
        'vi-VN' = @(
            'Trợ lý lập chỉ mục toàn bộ HDSD và lịch sử Việt-Anh theo từng mục, trả đầy đủ thay đổi của một phiên bản và đối chiếu trực tiếp hai phiên bản mà không suy diễn ngoài hồ sơ.',
            'Khôi phục các mốc phát hành v1 bị lược bỏ, sửa nội dung v1.1-v3.3 theo hồ sơ gốc và nói rõ không có hồ sơ v2.0-v2.3 thay vì tự tạo câu trả lời.',
            'Giải thích đầy đủ quy trình OEM hai giai đoạn: kiểm tra OA3 chỉ đọc, che key, xác nhận edition/quyền sử dụng, áp dụng bằng cơ chế Windows chính thức và hậu kiểm.',
            'v5.0 siết danh sách phần mềm: trình cài đặt, add-in, runtime con, gói hỗ trợ và trình gỡ driver chỉ còn trong kiểm kê/báo cáo, không xuất hiện trong màn hình xử lý.',
            'Bản ManagedSigned chạy trên máy mới: chỉ chấp nhận gốc tự ký chưa được Windows tin cậy khi signer khớp cả SHA-1/SHA-256 đã ghim; tệp bị sửa và mọi lỗi chữ ký khác vẫn bị khóa.',
            'Build Stable chuyển sang fail-closed: bắt buộc chứng thư code-signing CA-issued/HSM, chuỗi tin cậy Windows, RFC3161 timestamp, source commit sạch và provenance CMS hợp lệ.',
            'Catalog có trạng thái Fresh/Warning/Stale/Future/Invalid; plugin bên thứ ba chỉ nhận metadata khai báo đã ký CMS và fingerprint nhà phát hành do quản trị viên ghim.',
            'Bổ sung ba mức Quick/Standard/Deep, giới hạn include/exclude/root an toàn và kiểm soát ngân sách quét.',
            'Giao diện hỗ trợ theme theo hệ thống, dark/light override và PerMonitorV2 DPI.',
            'Bổ sung xuất fleet JSON/CSV/HTML/PDF có redaction, chống CSV injection; CLI headless, script Intune/MDM và ma trận VM Windows 10/11.',
            'Xác thực nguồn gốc bằng Authenticode và manifest provenance ký số; bản bị sửa hoặc đóng gói lại bị khóa cập nhật và thao tác thay đổi hệ thống.',
            'Catalog online 1.6.3.0 bao phủ 94 nhóm, loại thêm gói cài đặt/thành phần hỗ trợ khỏi danh sách xử lý và chỉ chấp nhận dữ liệu khai báo đã ký, field/profile nằm trong allowlist.',
            'Quy trình làm sạch dùng trạng thái rõ ràng, cho phép thử lại và chỉ báo Đã làm sạch khi hậu kiểm xác nhận bằng chứng can thiệp đã hết cùng trạng thái license mục tiêu.',
            'Các chế độ Quét/Báo cáo chỉ đọc; Khắc phục gỡ đúng khóa hoặc Activation ID xấu, bảo toàn bản quyền hợp lệ cùng tồn tại và chỉ cho phép gỡ hoàn chỉnh ứng dụng được chọn khi danh tính MSI/AppX gắn với nguồn đã được xác minh.',
            'Báo cáo mặc định che serial, UUID, Processor ID và Asset Tag; chỉ bản FullInternal do người dùng chủ động chọn mới giữ đầy đủ.',
            'Quét toàn máy yêu cầu UAC, kiểm tra Winmgmt/sppsvc, thử CIM rồi WMI và phân biệt lỗi nguồn dữ liệu với trạng thái chưa kích hoạt.',
            'Kiểm kê bổ sung AppX/MSIX, Winget, shortcut, trình quản lý gói và adapter Autodesk chỉ-đọc; phân biệt bản cài đã xác nhận với portable/tệp còn sót và gộp Adobe Acrobat theo họ sản phẩm.',
            'Quét toàn vẹn thích ứng mở rộng Authenticode trong đúng thư mục sản phẩm khi hosts, firewall hoặc dịch vụ hãng bất thường; bằng chứng không còn lan giữa các sản phẩm Adobe.',
            'Kể từ v4.9, Tool tiếp tục miễn phí nhưng mã nguồn không còn được công khai miễn phí, không phải mã nguồn mở và chỉ được tiếp cận khi tác giả chấp thuận trước bằng văn bản.',
            'Mặc định Offline, không telemetry; manifest cập nhật online phải có chữ ký tách rời từ chứng thư tác giả đã ghim cứng.'
        )
        'en-US' = @(
            'Tool Assistant indexes every section in the bundled Vietnamese/English guides and histories, returns a recorded version''s full change entry, and compares two versions without inferring undocumented changes.',
            'Restores omitted v1 release milestones, corrects v1.1-v3.3 from the original release records, and explicitly reports that no v2.0-v2.3 record exists instead of inventing an answer.',
            'Explains the complete two-stage OEM workflow: read-only OA3 inspection, masked keys, edition/entitlement confirmation, official Windows application, and post-verification.',
            'v5.0 further refines the software list: installers, add-ins, runtime subfeatures, support packages, and driver uninstallers remain in inventory/reports but are omitted from the action screen.',
            'The ManagedSigned build runs on a new PC: an untrusted self-signed root is accepted only when both pinned signer SHA-1/SHA-256 values match; modified files and every other signature error remain blocked.',
            'Stable builds now fail closed and require a CA-issued/HSM code-signing certificate, a valid Windows chain, an RFC3161 timestamp, a clean source commit, and valid CMS provenance.',
            'Catalogs expose Fresh/Warning/Stale/Future/Invalid states; third-party plugins accept only signed declarative metadata from administrator-pinned publisher fingerprints.',
            'Quick, Standard, and Deep scan levels add safe include/exclude/root limits and explicit scan budgets.',
            'The UI follows the system theme, supports dark/light overrides, and declares PerMonitorV2 DPI awareness.',
            'Fleet JSON/CSV/HTML/PDF export adds redaction and CSV-injection guards, with a headless CLI, Intune/MDM scripts, and a Windows 10/11 VM matrix.',
            'Authenticode and a signed provenance manifest verify origin; modified or repackaged builds cannot self-update or perform system-changing actions.',
            'Online catalog 1.6.3.0 covers 94 families, excludes additional installers/support components from the action list, and accepts only signed declarative data with allowlisted fields and profiles.',
            'Cleanup uses explicit states, remains retryable, and reports VerifiedClean only after post-checks confirm that intervention evidence is gone and the target license state is reached.',
            'Scan and report modes are read-only; remediation removes only the selected bad key or Activation ID, preserves coexisting genuine licences, and permits complete removal of an explicitly selected application only through a validated source-bound MSI/AppX identity.',
            'Reports redact serials, UUIDs, Processor IDs, and asset tags by default; only a user-selected FullInternal copy retains them.',
            'Whole-machine scans request UAC, check Winmgmt/sppsvc, try CIM then WMI, and distinguish data-source failures from an unactivated state.',
            'Inventory adds AppX/MSIX, WinGet, shortcuts, package managers, and a read-only Autodesk adapter; it distinguishes confirmed installs from portable/residual files and merges Adobe Acrobat by product family.',
            'Adaptive integrity scanning expands Authenticode checks inside the exact product directory when vendor hosts, firewall rules, or licensing services are abnormal; Adobe evidence no longer leaks across products.',
            'Starting with v4.9, the Tool remains free, but source is no longer published free of charge, is not open source, and requires the author''s prior written approval for access.',
            'Offline remains the default with no telemetry; online update metadata now requires a detached signature from the hard-pinned author certificate.'
        )
    }
    ReleasePageUrl = "https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v$releaseVersion"
    DownloadUrl = "https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/download/v$releaseVersion/$($primaryArtifact.FileName)"
    DownloadSha256 = [string]$primaryArtifact.Sha256
    DownloadSize = [int64](Get-Item -LiteralPath $primaryArtifactPath).Length
    AuthenticodeRequired = $updateAuthenticodeRequired
    SignerThumbprints = @($updateSignerThumbprints)
}
$applicationUpdateManifestJson = $applicationUpdateManifest | ConvertTo-Json -Depth 8
$sourceUpdateManifestPath = Join-Path $sourceDirectory 'update-manifest-v1.json'
$outputUpdateManifestPath = Join-Path $OutputDirectory 'update-manifest-v1.json'
$sourceUpdateSignaturePath = $sourceUpdateManifestPath + '.p7s'
$outputUpdateSignaturePath = $outputUpdateManifestPath + '.p7s'
if ($AllowUnsignedDevelopmentBuild -or $AllowStoreBuild) {
    # Build development/Store không được làm hỏng manifest stable đang dùng để
    # cập nhật từ nguồn. Manifest riêng chỉ tồn tại trong thư mục artefact cục bộ.
    if (Test-Path -LiteralPath $outputUpdateSignaturePath -PathType Leaf) {
        Remove-Item -LiteralPath $outputUpdateSignaturePath -Force
    }
    [IO.File]::WriteAllText($outputUpdateManifestPath, $applicationUpdateManifestJson, (New-Object Text.UTF8Encoding($false)))
} else {
    [IO.File]::WriteAllText($sourceUpdateManifestPath, $applicationUpdateManifestJson, (New-Object Text.UTF8Encoding($false)))
    $updateSigningScript = Join-Path $sourceDirectory 'SIGN-UPDATE-MANIFEST.ps1'
    & $updateSigningScript -ManifestPath $sourceUpdateManifestPath `
        -CertificateThumbprint $normalizedUpdateManifestSignerThumbprint `
        -StoreLocation $UpdateManifestCertificateStore -Force
    if (-not (Test-Path -LiteralPath $sourceUpdateSignaturePath -PathType Leaf)) { throw 'Thiếu chữ ký tách rời của manifest cập nhật.' }
    if (-not $sourceUpdateManifestPath.Equals($outputUpdateManifestPath, [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $sourceUpdateManifestPath -Destination $outputUpdateManifestPath -Force
        Copy-Item -LiteralPath $sourceUpdateSignaturePath -Destination $outputUpdateSignaturePath -Force
    }
    if ((Get-Sha256Hex $sourceUpdateManifestPath) -ne (Get-Sha256Hex $outputUpdateManifestPath)) {
        throw 'Manifest cập nhật trong mã nguồn và thư mục phát hành không giống hệt từng byte.'
    }
    if ((Get-Sha256Hex $sourceUpdateSignaturePath) -ne (Get-Sha256Hex $outputUpdateSignaturePath)) {
        throw 'Chữ ký manifest cập nhật trong mã nguồn và thư mục phát hành không giống hệt từng byte.'
    }
}
Write-SourcePackageHashManifest

$infoName = 'THONG-TIN-PHAT-HANH-v5.0.txt'
$authenticodeInfo = if (-not [string]::IsNullOrWhiteSpace([string]$primaryArtifact.AuthenticodeThumbprint)) {
    "Authenticode signer: $($primaryArtifact.AuthenticodeSigner); thumbprint $($primaryArtifact.AuthenticodeThumbprint); status $($primaryArtifact.AuthenticodeStatus)."
} else {
    'Authenticode: NotSigned.'
}
$authenticodeTrustInfo = if ([string]$primaryArtifact.AuthenticodeStatus -eq 'Valid' -and [string]$primaryArtifact.AuthenticodeSigner -match 'Self-Signed') {
    'Chu ky Authenticode tu ky duoc ghim bang SHA-1 va SHA-256. Ban v5.0 chay tren may moi ma khong can cai chung thu truoc; Windows van co the bao Unknown publisher/SmartScreen.'
} elseif ([string]$primaryArtifact.AuthenticodeStatus -eq 'Valid') {
    'Chu ky Authenticode duoc Windows tren may build xac minh Valid; SmartScreen van co the can danh tieng cho tep moi.'
} elseif (-not [string]::IsNullOrWhiteSpace([string]$primaryArtifact.AuthenticodeThumbprint)) {
    'Chu ky tu ky mien phi chi giup nhan biet tep bi sua; khong duoc Windows tin cay cong khai va khong loai bo canh bao SmartScreen tren may la.'
} else {
    'Tep chua co chu ky Authenticode; chi tai tu GitHub chinh thuc va doi chieu SHA-256.'
}
$infoLines = @(
    "PHAN MEM KIEM TRA BAN QUYEN v$releaseVersion - HO TRO CA NHAN VA DOANH NGHIEP",
    "Release version: $releaseVersion",
    "Release build date: $releaseBuildDate",
    "Release label: $releaseLabel",
    "Release status: $releaseStatus.",
    "Tep chay duy nhat: Tool-Kiem-Tra-v$productVersion.exe",
    "SHA-256: $($primaryArtifact.Sha256)",
    'AnyCPU: CLR tu chay x64 tren Windows 64-bit va x86 tren Windows 32-bit; khong bat Prefer 32-bit.',
    'Fail-closed neu phat hien tien trinh 32-bit tren Windows 64-bit de tranh WOW64 redirection.',
    'PowerShell duoc khoi dong voi ExecutionPolicy RemoteSigned; khong dung Bypass.',
    'Dashboard mo bang quyen nguoi dung hien tai; UAC chi duoc yeu cau theo nhu cau khi thay doi he thong, cap nhat ung dung hoac quan tri doanh nghiep.',
    'Cau noi UAC ma hoa chi truyen allowlist bien TOOL_* da xac thuc, khoi phuc secure runtime va tra ma thoat tien trinh con; khong tat fail-closed de ne loi.',
    "Payload nhung duoc toi uu $($payloadCompressionStats.Scheme): $($payloadFiles.Count) tep trong mot resource Deflate co header fail-closed; giam $($payloadCompressionStats.SavingsPercent)% va van doi chieu SHA-256 tung tep sau giai nen.",
    'Capability detection chon CIM/WMI, ScheduledTasks/schtasks va cac tinh nang theo he dieu hanh.',
    'Dashboard schema 2.0: WinForms hien dai, theo Light/Dark cua he thong, cho phep ghi nho tuy chon va co fallback DPI tu PerMonitorV2 den Win7.',
    'Typography dong bo Segoe UI/GDI+ voi co chu gon hon; icon co khoang dem, tile va tab can deu, noi dung dai co tooltip day du.',
    'Da ngon ngu: vi-VN va en-US dung catalog JSON dong bo cho dashboard, log trang thai, bao cao, trung tam doanh nghiep va trinh quan ly Windows/Office cuc bo; lua chon duoc ghi nho theo tai khoan.',
    'Ghi nho ngon ngu, giao dien System/Light/Dark va profile quet; moi lan mo van bat dau Offline, khong khoi phuc Online tu phien truoc.',
    'Canh bao khi phat hien may ao hoac Remote Desktop; khong khoa cac chuc nang hien co.',
    'Them nut Sao chep toan bo log va Mo thu muc bao cao; lich su phien ban hien thi ngay trong Tool.',
    'Bo nhan danh so cu tren cua so chuc nang; toan bo nut WinForms dung mau va icon vector hanh dong chung o Light/Dark.',
    'Quet Office va tep chi bao duoc song song co gioi han, bo qua reparse point va giu nguyen pham vi quet cu.',
    'Quet sau pho quat moi phan mem phat hien duoc: nhieu EXE/DLL, Authenticode, hash xau da biet, artifact va dau vet he thong tuong quan; ngan sach chu ky duoc chia deu va do phu duoc ghi trong JSON/report.',
    'Toi uu hieu nang v4.8: descriptor inventory tinh mot lan, chi muc nhom ten/bang chung ngoai, dung property bag thay Add-Member lap lai, tai su dung snapshot Scheduled Tasks, bang dich nguoc cho report va Authenticode theo lo toi da 4 worker; doi chung cung du lieu cho 0 khac biet, giu nguyen nguon, do sau, artifact va dau vet he thong.',
    'Chi ket luan NonGenuine khi co bang chung quyet dinh hoac hai nhom bang chung manh doc lap; dau hieu chung giu Suspicious, thieu do phu giu Unverified.',
    'Bao cao phan mem va dau hieu can thiep giu nguyen hop dong v4.3.0.3; kiem ke ung dung va trang thai ky thuat ben thu ba duoc noi them o cuoi bao cao va DetailedInventory JSON.',
    'Khac phuc ben thu ba: chi bang chung CrackConfirmed truc tiep moi mo quyen chon; tu dong chi co the cach ly artifact da xac nhan hoac khoi phuc dong hosts chinh xac, sau khi kiem tra lai hash/kich thuoc. Khong reset kho license cua hang, khong chay MSI Repair, go/cai lai luon la thu cong.',
    'Backup HMAC luu kiem ke va cach ly truoc thay doi; activator va token cap phep da loai bo khong duoc khoi phuc.',
    'Offline toan ung dung mac dinh; trung tam doanh nghiep co cong tac mang rieng mac dinh tat, co the bat/tat lai ma khong an chuc nang hoac xoa cau hinh.',
    'Ket noi online chi chay sau khi nguoi dung xac nhan, tai catalog JSON HTTPS tu host allowlist; khong gui inventory, duong dan, khoa hoac token va khong doi preference Offline.',
    'Tu dong kiem tra phien ban moi chi khi Online da duoc cho phep; khong co service nen, telemetry hay cap nhat im lang.',
    'Khi co ban moi, Tool hoi 3 lua chon: Cap nhat ngay, De sau, Bo qua lan nay. De sau hoi lai sau tac vu ke tiep hoac 2 gio.',
    'Cap nhat ngay chi tai EXE tu GitHub HTTPS co dinh, doi chieu dung luong/SHA-256/chu ky neu bat buoc, backup ban cu va rollback neu ban moi loi.',
    "Compatibility catalog $($compatibilityMetadata.CatalogVersion), schema $($compatibilityMetadata.CatalogSchemaVersion), ra soat $($compatibilityMetadata.ReviewedAtUtc); canh bao $($compatibilityMetadata.ReviewWarningAgeDays) ngay va het han $($compatibilityMetadata.MaximumReviewAgeDays) ngay.",
    "Nhan dien theo catalog: $(@($compatibilityMetadata.WindowsReleaseNames) -join ', '); build moi/chua biet chuyen sang ReadOnlyManualReview.",
    "Nhan dien Office theo catalog: $(@($compatibilityMetadata.OfficeFamilyNames) -join ', '); Product ID/kenh moi chua biet khong duoc tu suy dien tuong thich.",
    'Enterprise: may chu quet CIDR/IP, ghep noi bang ma tam thoi, quan ly fleet, xuat JSON/CSV/HTML/PDF va gui tac vu license da ma hoa.',
    'Enterprise UI hotfix: co-fit theo WorkingArea/DPI, khong tran ngang; Quet nhanh tu nhan CIDR cuc bo khi o nhap trong.',
    'Enterprise IP auto: may chu tu chon IPv4 LAN uu tien theo card co gateway; may tram tu do server duy nhat khi de trong dia chi.',
    'Enterprise server reset: nut Xoa cau hinh may chu bat buoc ma quan tri va xac nhan cuoi; giu bao cao, ket qua va audit.',
    'Enterprise UI refresh: bo muc Tren may nay; doi thanh Chon chuc nang; them mau theo chuc nang, nut Tro ve phien truoc va nut Dong trung tam doanh nghiep.',
    'Enterprise network toggle: nut hien trang thai Online/Offline hien tai; tooltip noi ro thao tac chuyen che do va ba chuc nang luon hien thi.',
    'Enterprise UI close hotfix: ve tab dung RectangleF de tranh loi overload DrawString va dam bao nut Dong trung tam doanh nghiep hoat dong.',
    'Enterprise local manager restore: khoi phuc quan ly license cuc bo duoi ten chuc nang moi, khong dung lai ten tab Tren may nay.',
    'Enterprise quick scan hotfix: sua loi hien thi ket qua khi IP phan hoi va them kiem thu hoi quy PowerShell 5.1.',
    'Dark mode theo he thong hoac tuy chon ghi nho, phu dashboard, cua so con, chuc nang 8 va quan ly cuc bo Windows/Office.',
    'May tram tu dong gui bao cao hoac xep hang DPAPI khi mat route; thay doi license tu xa mac dinh tat va phai duoc may tram cho phep.',
    'Cleanup Action Center co vung cuon/nut xu ly tiep; Office KMS dung OSPP /dstatusall va rang buoc lua chon theo tung SKU/Last5.',
    'Kich hoat chinh hang tach sach crack khoi da cap phep: Windows chi TRUE khi LicenseStatus=1 dung Last5; Office chi TRUE khi OSPP /dstatusall bao LICENSED dung Last5; neu chua dat thi FALSE va mo luong chinh thuc.',
    "Report schema $($reportSchemaMetadata.SchemaVersion): $(@($reportSchemaMetadata.ReportKinds).Count) loai bao cao; safety policy schema $($safetyPolicyMetadata.SchemaVersion); quick repair khong doi StartupType.",
    'Bao cao HTML la ban tong quan gon, khong con bang dai; chi giu cau hinh chinh, ket luan, canh bao va nut mo PDF day du.',
    'PDF la ban chi tiet A4 gom toan bo bang cau hinh, phan mem, bang chung va du lieu ky thuat; moi lan xuat van gom HTML/PDF/JSON/XML/checksum trong mot thu muc va chi tu mo HTML.',
    'Ket luan ban quyen tach ro trang thai kich hoat voi quyen su dung; du lieu cap phep khong doc duoc ghi CHUA XAC DINH va khong tu chung minh hop le/khong hop le.',
    'Tro ly Tool dung tri thuc cuc bo, khong tu khac phuc va khong tai cau hoi/bao cao/du lieu may len mang; Online chi tai JSON va chu ky CMS tu hai path GitHub co dinh.',
    'Tro ly bo tri truc tiep va co them luot ve bu sau su kien Gui/Enter; cau tra loi hien ngay sau khi xu ly, khong cho cau hoi tiep theo; nhan Offline co le an toan, khung nhap co vien focus va bong bong hoi-dap co mau/vien rieng.',
    'HTML, PDF va cac bao cao dung chung giu du nam o ket qua tren cung mot hang khi du rong; Muc xac minh/Huong xu ly tach thanh o con va chan trang PDF chia hai hang.',
    'Tro ly dong bo day du vi-VN/en-US cho nut, trang thai dong bo va dien giai bao cao hien tai theo ma ket qua.',
    'Tro ly schema 1.1 / knowledge 1.5.1 co tri thuc cuc bo ky CMS SHA-256, ghim chung thu, chong ha phien ban va khong tai cau hoi/bao cao len mang.',
    'Catalogue phan mem 1.6.3.0 co it nhat 94 quy tac khai bao ky CMS; runtime/installer/thanh phan ho tro bi loai khoi danh sach xu ly; du lieu online khong duoc mang lenh/script tuy y.',
    'Bao cao Windows/Office thuong van ra kenh KMS khi license o Notification, hien chu ky KMS toi da 180 ngay va ra MAS/PMAS, Activation Program 1.17, lenh erturk-dev.netlify.app/run, TSforge, OHook, KMS toolkit/Microsoft Toolkit con hien huu.',
    'Quet phan mem thuong ra them artifact trong thu muc cai dat thuong mai co gioi han, khong chi du lieu Download; ngay cai duoc chuan hoa yyyy-MM-dd.',
    'Ten man hinh co fallback EDID/DesktopMonitor/PNP; hop chon rieng tu co nut Ban da che, Ban day du noi bo va Huy; timeline tach trang thai hien tai khoi su kien lich su.',
    'WinRAR khong coi rarreg.key don le la bang chung vi pham hay dieu kien khac phuc; neu het thu dung thi mua giay phep hoac dung phan mem thay the hop phap.',
    'Khac phuc phan mem ben thu ba ghi ket qua tung hanh dong va chi bao thanh cong khi he thong thuc su thay doi; huong dan don thuan khong con bi tinh la da sua.',
    'Sau hau kiem, hang doi phan mem khac chi con bang chung activator/can thiep; Unverified don thuan khong quay lai, tep activator doc lap co candidate cach ly thu cong va kho backup bi loai tru.',
    'HashMismatch duoc tach thanh IntegrityCompromised: tep bi sua/hong nhung khong tu ket luan quyen su dung khong chinh hang.',
    'Phan mem he thong/mac dinh an khoi bang chinh, co link mo phu luc trong HTML va hien day du trong PDF/JSON chi tiet.',
    'Moi bao cao nam truc tiep trong Desktop\BaoCao-Tool-Kiem-Tra, khong tao thu muc con; ten tep co mili-giay va HTML link dung PDF.',
    'PDF tach bang rong thanh tong quan/bang chung, mo chi tiet khi in, lap header va tranh cat dong/hang qua trang.',
    'Enterprise nhan IP:port, tu do khi de trong, chan doan endpoint/TCP/service/protocol/version va quet Neighbor-ARP/ICMP/TCP.',
    'Enterprise server cau hinh va hau kiem URLACL/Firewall qua UAC; chi bao da khoi dong sau heartbeat/diagnostic, agent chi bao da gui sau tep ket qua xac nhan.',
    'Muc Bao cao hien thi truc tiep du bay chuc nang con; huong dan vi-VN/en-US duoc nhung trong EXE va mo bang HTML/PDF A4.',
    'HTML/PDF chi dung asset cuc bo, CSP default-src none; browser PDF tat background networking va map DNS ve 0.0.0.0.',
    'Profile Edge/Chrome tam nam trong %LOCALAPPDATA%\Temp, ACL chi cho nguoi dung hien tai va SYSTEM; profile duoc don sau moi lan xuat.',
    'Plugin chi dung JSON khai bao, khong chay script/command; thu muc plugin co ACL Administrators/SYSTEM.',
    'Timeline dung DPAPI LocalMachine, HMAC-SHA256 va hash chain; neu chuoi hong tool tu choi noi them.',
    'Certificate audit kiem tra Authenticode va chuoi tin cay offline cua tep Windows/Office quan trong.',
    "Module contract schema $($moduleContractMetadata.ContractSchemaVersion): $($moduleContractMetadata.EntryPointCount) entry point / $($moduleContractMetadata.ModuleCount) module; co capability gate va ModuleResult thong nhat.",
    'Log JSON Lines cua dashboard nam trong LocalAppData theo tai khoan; che do nang quyen va doanh nghiep dung ProgramData co ACL Administrators/SYSTEM; khong ghi product key day du.',
    'PE: HIGH_ENTROPY_VA, ASLR, NX, NO_SEH, Terminal Server Aware.',
    'CFG/load configuration native chua duoc tuyen bo; xem SECURITY-HARDENING-v4.8.md.',
    'Pham vi runtime: Windows 7 SP1 den Windows 11 desktop x64/x86; catalog hien tai theo doi Windows 10 22H2 va Windows 11 23H2/24H2/25H2/26H1.',
    $authenticodeInfo,
    $authenticodeTrustInfo,
    'Khong the vuot AppLocker, WDAC, SmartScreen, antivirus hoac chinh sach doanh nghiep.'
)
[IO.File]::WriteAllLines((Join-Path $OutputDirectory $infoName), $infoLines, (New-Object Text.UTF8Encoding($false)))

$releaseHashFiles = @($targets.OutputName) + @(
    'approved-kms-servers.txt', 'HUONG-DAN.txt', 'USER-GUIDE-en-US.md', 'LICH-SU-PHIEN-BAN.txt', 'VERSION-HISTORY-en-US.md', 'LICENSE-NOTICE.txt',
    'SOURCE-POLICY-v4.9.md', 'RELEASE-NOTES-v5.0.md', 'OFFICIAL-PROVENANCE-v1.json',
    'MODULE-CONTRACT-v1.0.md', 'REPORT-SCHEMA-v1.5.md', 'SAFETY-POLICY-v1.0.md',
    'SECURITY.md', 'AUDIT-SCOPE-v1.md', 'SECURITY-REVIEW-PROCESS-v1.md', 'SECURITY-REVIEW-ATTESTATION-TEMPLATE-v1.json', 'SECURITY-TEST-RESULTS.md', 'CODE-SIGNING-POLICY-v1.md',
    'PLUGIN-PUBLISHER-TRUST-v1.md', 'REPORT-VIEWER-POLICY-v1.md',
    'TECHNICAL-ARCHITECTURE-v4.8.md', 'ENTRY-POINTS-v4.8.md', 'COMPATIBILITY-MATRIX-v4.8.md',
    'OFFLINE-AND-REPORTING-v4.8.md', 'LOCALIZATION-v1.0.md', 'SECURITY-HARDENING-v4.8.md',
    'compatibility-catalog-v1.0.json', 'software-license-catalog-v1.0.json', 'software-license-catalog-v1.0.json.p7s', 'builtin-windows-office-trust.plugin.json', 'tool-assistant-knowledge-v1.1.json', 'tool-assistant-knowledge-v1.1.json.p7s', 'RELEASE-MANIFEST.json', 'SBOM.cdx.json', 'update-manifest-v1.json', $infoName
)
if (Test-Path -LiteralPath (Join-Path $OutputDirectory $provenanceSignatureName) -PathType Leaf) {
    $releaseHashFiles += $provenanceSignatureName
}
if (Test-Path -LiteralPath $outputUpdateSignaturePath -PathType Leaf) {
    $releaseHashFiles += 'update-manifest-v1.json.p7s'
}
$releaseHashLines = @("# SHA-256 goi phat hanh Tool-Kiem-Tra v$productVersion.")
foreach ($name in $releaseHashFiles) {
    $releaseHashLines += "$(Get-Sha256Hex (Join-Path $OutputDirectory $name))  $name"
}
[IO.File]::WriteAllLines((Join-Path $OutputDirectory 'RELEASE-SHA256SUMS.txt'), $releaseHashLines, (New-Object Text.UTF8Encoding($false)))

Write-Host '[6/8] Kiểm tra extension/report/plugin/timeline...'
if (-not $SkipVerification) {
    & (Join-Path $sourceDirectory 'VERIFY-SAFETY-REGRESSIONS.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-SAFETY-REGRESSIONS.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-DASHBOARD.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-DASHBOARD.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-RESULT-CENTER.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-RESULT-CENTER.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-REPORT-SCHEMA.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-REPORT-SCHEMA.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-EXTENSIONS.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-EXTENSIONS.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-COMPATIBILITY.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-COMPATIBILITY.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-OFFLINE-I18N.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-OFFLINE-I18N.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-LOCALIZATION-COVERAGE.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-LOCALIZATION-COVERAGE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-ENTERPRISE.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-ENTERPRISE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-PERFORMANCE.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-PERFORMANCE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-APPLICATION-UPDATE.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-APPLICATION-UPDATE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-ASSISTANT.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-ASSISTANT.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-SOFTWARE-DETECTION-V4.9.ps1')
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-SOFTWARE-DETECTION-V4.9.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-MSIX-PACKAGING.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-MSIX-PACKAGING.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    Write-Host '[7/8] Kiểm tra phát hành tổng thể...'
    & (Join-Path $sourceDirectory 'VERIFY-RELEASE.ps1') -SourceDirectory $sourceDirectory -DistributionDirectory $OutputDirectory `
        -AllowDevelopmentManifest:$AllowUnsignedDevelopmentBuild -AllowManagedSignedManifest:$AllowManagedSignedBuild -AllowStoreManifest:$AllowStoreBuild
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-RELEASE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    if ($requiresSignedArtifact) {
        & (Join-Path $sourceDirectory 'VERIFY-AUTHENTICODE.ps1') -FilePath (Join-Path $OutputDirectory "Tool-Kiem-Tra-v$productVersion.exe") -RequireTimestamp
        if ($LASTEXITCODE -ne 0) { throw "VERIFY-AUTHENTICODE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
        & (Join-Path $sourceDirectory 'VERIFY-CODE-SIGNING-READINESS.ps1') `
            -CertificateThumbprint $normalizedStableSignerThumbprint `
            -StoreLocation $SigningCertificateStore `
            -ArtifactPath (Join-Path $OutputDirectory "Tool-Kiem-Tra-v$productVersion.exe") `
            -AllowManagedSelfSigned:$AllowManagedSignedBuild
        if ($LASTEXITCODE -ne 0) { throw "VERIFY-CODE-SIGNING-READINESS.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    }
}

Write-Host '[8/8] Hoàn tất.'
foreach ($artifact in $artifactResults) {
    Write-Host "  $($artifact.Architecture), tự nhận diện runtime: $(Join-Path $OutputDirectory $artifact.FileName)" -ForegroundColor Green
    Write-Host "  SHA-256: $($artifact.Sha256)"
    Write-Host "  Authenticode: $($artifact.AuthenticodeStatus)"
}
