<#
.SYNOPSIS
    Idempotent Intune/MDM deployment helper for the Tool Enterprise scripts.

.DESCRIPTION
    Installs only program files. Pairing codes, client secrets, server secrets,
    reports, and network policy are never copied into the deployment package.
    Use Intune/MDM to run this script as SYSTEM for Install/Repair/Uninstall and
    use Detect as the custom detection command.

    Production Install/Repair requires the SHA-256 of TOOL-SHA256SUMS.txt from
    the trusted release channel through ExpectedSourceManifestSha256. The
    development bypass is explicit and must not be used for managed rollout.

    Connectivity remains an administrator decision: open the Enterprise port
    only on Domain/Private profiles and restrict it to approved LAN or VPN CIDR
    ranges. Do not expose the listener directly to the public Internet.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Detect", "Repair", "Uninstall")]
    [string]$Action,

    [string]$SourceDirectory = $PSScriptRoot,
    [string]$TargetDirectory = "",
    [string]$SourceManifestPath = "",
    [string]$ExpectedSourceManifestSha256 = "",
    [switch]$AllowUnverifiedDevelopmentSource,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$deploymentSchemaVersion = "1.0"
$payloadNames = @(
    "Tool-Enterprise.ps1",
    "Tool-EnterpriseAgent.ps1",
    "Tool-EnterpriseHost.ps1",
    "Tool-EnterpriseCli.ps1",
    "Tool-Runtime.ps1",
    "Tool-ReportSchema.ps1",
    "Tool-ReportExport.ps1",
    "Tool-Localization.ps1",
    "Tool-Strings.vi-VN.json",
    "Tool-Strings.en-US.json",
    "Tool-DataLifecycle.ps1",
    "Tool-OfflinePolicy.ps1"
)

function Get-ManagedDeploymentSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-ManagedDeploymentSubPath {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root)
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return [bool](-not $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -and
        $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase))
}

function Assert-ManagedDeploymentNoReparseAncestor {
    param([Parameter(Mandatory = $true)][string]$Path)

    $candidate = [IO.Path]::GetFullPath($Path)
    while (-not (Test-Path -LiteralPath $candidate)) {
        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) { break }
        $candidate = $parent
    }
    if (-not (Test-Path -LiteralPath $candidate)) { throw "Cannot resolve an existing ancestor for deployment path: $Path" }
    $cursor = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Deployment paths cannot traverse a reparse point: $($cursor.FullName)"
        }
        $cursor = if ($cursor -is [IO.FileInfo]) { $cursor.Directory } elseif ($cursor -is [IO.DirectoryInfo]) { $cursor.Parent } else { $null }
    }
}

function Get-ManagedDeploymentSourceTrust {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [string]$ManifestPath,
        [string]$ExpectedManifestSha256,
        [switch]$AllowDevelopment
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedManifestSha256)) {
        if (-not $AllowDevelopment) {
            throw "Install/Repair requires ExpectedSourceManifestSha256 from the trusted release channel. Use AllowUnverifiedDevelopmentSource only for isolated development tests."
        }
        return [pscustomobject][ordered]@{ Mode="DevelopmentUnverified"; ManifestPath=""; ManifestSha256="" }
    }
    $expected = ($ExpectedManifestSha256 -replace '\s', '').ToUpperInvariant()
    if ($expected -notmatch '^[0-9A-F]{64}$') { throw "ExpectedSourceManifestSha256 must contain exactly 64 hexadecimal characters." }
    $resolvedManifest = if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        Join-Path $Source "TOOL-SHA256SUMS.txt"
    } else {
        [IO.Path]::GetFullPath($ManifestPath)
    }
    if (-not (Test-Path -LiteralPath $resolvedManifest -PathType Leaf)) { throw "Trusted source manifest is missing." }
    Assert-ManagedDeploymentNoReparseAncestor -Path $resolvedManifest
    $manifestInfo = Get-Item -LiteralPath $resolvedManifest -Force
    if ($manifestInfo.Length -le 0 -or $manifestInfo.Length -gt 1048576) { throw "Trusted source manifest size is invalid." }
    $actualManifestSha256 = Get-ManagedDeploymentSha256 -Path $resolvedManifest
    if (-not $actualManifestSha256.Equals($expected, [StringComparison]::Ordinal)) { throw "Trusted source manifest SHA-256 mismatch." }

    $declaredHashes = @{}
    foreach ($line in Get-Content -LiteralPath $resolvedManifest -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?([^\\/]+)$') { throw "Trusted source manifest contains an invalid or nested entry." }
        $name = [string]$matches[2]
        if ($declaredHashes.ContainsKey($name)) { throw "Trusted source manifest contains a duplicate entry: $name" }
        $declaredHashes[$name] = ([string]$matches[1]).ToUpperInvariant()
    }
    foreach ($name in $payloadNames) {
        if (-not $declaredHashes.ContainsKey($name)) { throw "Trusted source manifest is missing deployment payload: $name" }
        $payloadPath = Join-Path $Source $name
        if ((Get-ManagedDeploymentSha256 -Path $payloadPath) -ne [string]$declaredHashes[$name]) {
            throw "Deployment payload does not match the trusted source manifest: $name"
        }
    }
    return [pscustomobject][ordered]@{ Mode="PinnedReleaseManifest"; ManifestPath=$resolvedManifest; ManifestSha256=$actualManifestSha256 }
}

function Assert-ManagedDeploymentTarget {
    param([Parameter(Mandatory = $true)][string]$Path)
    $programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    $programData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    $allowedRoots = @(
        (Join-Path $programFiles "ThanhViet"),
        (Join-Path $programData "ThanhViet-VietLicenSure\managed")
    )
    foreach ($root in $allowedRoots) {
        if (Test-ManagedDeploymentSubPath -Path $Path -Root $root) { return [IO.Path]::GetFullPath($Path) }
    }
    throw "TargetDirectory must remain under an approved ThanhViet Program Files or ProgramData deployment root."
}

function Read-ManagedDeploymentManifest {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Deployment manifest cannot be a reparse point." }
    if ($item.Length -le 0 -or $item.Length -gt 1048576) { throw "Deployment manifest size is invalid." }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Test-ManagedDeploymentState {
    param([Parameter(Mandatory = $true)][string]$Target)
    $manifestPath = Join-Path $Target "enterprise-deployment-manifest.json"
    $manifest = Read-ManagedDeploymentManifest -Path $manifestPath
    if (-not $manifest -or [string]$manifest.SchemaVersion -ne $deploymentSchemaVersion) {
        return [pscustomobject][ordered]@{ Compliant=$false; Reason="ManifestMissingOrInvalid"; TargetDirectory=$Target }
    }
    $manifestEntries = @($manifest.Files)
    if ($manifestEntries.Count -ne $payloadNames.Count -or
        [string]$manifest.SourceTrustMode -notin @('PinnedReleaseManifest','DevelopmentUnverified') -or
        ([string]$manifest.SourceTrustMode -eq 'PinnedReleaseManifest' -and [string]$manifest.SourceManifestSha256 -notmatch '^[0-9A-F]{64}$')) {
        return [pscustomobject][ordered]@{ Compliant=$false; Reason="ManifestPayloadSetInvalid"; TargetDirectory=$Target }
    }
    $seenPayloads = @{}
    foreach ($entry in $manifestEntries) {
        $name = [string]$entry.Name
        if ($name -notin $payloadNames -or $name -match '[\\/]' -or $seenPayloads.ContainsKey($name)) {
            return [pscustomobject][ordered]@{ Compliant=$false; Reason="ManifestPayloadInvalid"; TargetDirectory=$Target }
        }
        $seenPayloads[$name] = $true
        $path = Join-Path $Target $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return [pscustomobject][ordered]@{ Compliant=$false; Reason="PayloadMissing:$name"; TargetDirectory=$Target }
        }
        if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            return [pscustomobject][ordered]@{ Compliant=$false; Reason="PayloadReparsePoint:$name"; TargetDirectory=$Target }
        }
        if ((Get-ManagedDeploymentSha256 -Path $path) -ne ([string]$entry.Sha256).ToUpperInvariant()) {
            return [pscustomobject][ordered]@{ Compliant=$false; Reason="PayloadHashMismatch:$name"; TargetDirectory=$Target }
        }
    }
    return [pscustomobject][ordered]@{ Compliant=$true; Reason="Compliant"; TargetDirectory=$Target; FileCount=@($manifest.Files).Count }
}

function Test-ManagedDeploymentMatchesSource {
    param(
        [Parameter(Mandatory = $true)][object]$InstalledManifest,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][object]$SourceTrust
    )

    if ([string]$InstalledManifest.SourceTrustMode -ne [string]$SourceTrust.Mode) { return $false }
    if ([string]$SourceTrust.Mode -eq 'PinnedReleaseManifest' -and
        -not ([string]$InstalledManifest.SourceManifestSha256).Equals([string]$SourceTrust.ManifestSha256, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    $installedEntries = @{}
    foreach ($entry in @($InstalledManifest.Files)) {
        $name = [string]$entry.Name
        if ([string]::IsNullOrWhiteSpace($name) -or $installedEntries.ContainsKey($name)) { return $false }
        $installedEntries[$name] = ([string]$entry.Sha256).ToUpperInvariant()
    }
    foreach ($name in $payloadNames) {
        if (-not $installedEntries.ContainsKey($name)) { return $false }
        if ((Get-ManagedDeploymentSha256 -Path (Join-Path $Source $name)) -ne [string]$installedEntries[$name]) { return $false }
    }
    return $true
}

if ([string]::IsNullOrWhiteSpace($TargetDirectory)) {
    $TargetDirectory = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) "ThanhViet\VietLicenSure\Enterprise"
}
$target = Assert-ManagedDeploymentTarget -Path $TargetDirectory
Assert-ManagedDeploymentNoReparseAncestor -Path $target
$manifestPath = Join-Path $target "enterprise-deployment-manifest.json"

try {
    if ($Action -eq "Detect") {
        $state = Test-ManagedDeploymentState -Target $target
        if ($state.Compliant -and -not [string]::IsNullOrWhiteSpace($ExpectedSourceManifestSha256)) {
            $expectedDesiredHash = ($ExpectedSourceManifestSha256 -replace '\s', '').ToUpperInvariant()
            $installedManifest = Read-ManagedDeploymentManifest -Path $manifestPath
            if ($expectedDesiredHash -notmatch '^[0-9A-F]{64}$' -or
                [string]$installedManifest.SourceTrustMode -ne 'PinnedReleaseManifest' -or
                -not ([string]$installedManifest.SourceManifestSha256).Equals($expectedDesiredHash, [StringComparison]::Ordinal)) {
                $state = [pscustomobject][ordered]@{
                    Compliant = $false
                    Reason = "DesiredSourceManifestMismatch"
                    TargetDirectory = $target
                }
            }
        }
        if (-not $Quiet) { [Console]::Out.WriteLine(($state | ConvertTo-Json -Compress)) }
        if ($state.Compliant) { exit 0 }
        exit 1
    }

    if ($Action -eq "Uninstall") {
        $manifest = Read-ManagedDeploymentManifest -Path $manifestPath
        $preserved = New-Object System.Collections.Generic.List[string]
        if ($manifest) {
            foreach ($entry in @($manifest.Files)) {
                $name = [string]$entry.Name
                if ($name -notin $payloadNames -or $name -match '[\\/]') { continue }
                $path = Join-Path $target $name
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
                if ((Get-ManagedDeploymentSha256 -Path $path) -eq ([string]$entry.Sha256).ToUpperInvariant()) {
                    Remove-Item -LiteralPath $path -Force
                } else {
                    [void]$preserved.Add($name)
                }
            }
            Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue
        }
        if ((Test-Path -LiteralPath $target -PathType Container) -and @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $target -Force
        }
        $result = [pscustomobject][ordered]@{ Success=$true; Action=$Action; TargetDirectory=$target; PreservedModifiedFiles=@($preserved.ToArray()); SecretsRemoved=$false }
        if (-not $Quiet) { [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress)) }
        exit 0
    }

    $source = [IO.Path]::GetFullPath($SourceDirectory)
    Assert-ManagedDeploymentNoReparseAncestor -Path $source
    foreach ($name in $payloadNames) {
        $sourcePath = Join-Path $source $name
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Required deployment payload is missing: $name" }
        if ((Get-Item -LiteralPath $sourcePath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Deployment payload cannot be a reparse point: $name" }
    }
    $sourceTrust = Get-ManagedDeploymentSourceTrust -Source $source -ManifestPath $SourceManifestPath `
        -ExpectedManifestSha256 $ExpectedSourceManifestSha256 -AllowDevelopment:$AllowUnverifiedDevelopmentSource

    if ($Action -eq "Install" -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        $existingState = Test-ManagedDeploymentState -Target $target
        $existingManifest = if ($existingState.Compliant) { Read-ManagedDeploymentManifest -Path $manifestPath } else { $null }
        if ($existingState.Compliant -and
            (Test-ManagedDeploymentMatchesSource -InstalledManifest $existingManifest -Source $source -SourceTrust $sourceTrust)) {
            $currentResult = [pscustomobject][ordered]@{
                Success = $true
                Action = $Action
                AlreadyCurrent = $true
                TargetDirectory = $target
                FileCount = $existingState.FileCount
                SourceTrustMode = [string]$sourceTrust.Mode
                SourceManifestSha256 = [string]$sourceTrust.ManifestSha256
            }
            if (-not $Quiet) { [Console]::Out.WriteLine(($currentResult | ConvertTo-Json -Compress)) }
            exit 0
        }
    }

    $targetParent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) { New-Item -ItemType Directory -Path $targetParent -Force | Out-Null }
    if ((Get-Item -LiteralPath $targetParent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Deployment parent cannot be a reparse point." }
    $staging = Join-Path $targetParent (".enterprise-deploy-" + [Guid]::NewGuid().ToString("N") + ".staging")
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
        $manifestFiles = New-Object System.Collections.Generic.List[object]
        foreach ($name in $payloadNames) {
            $sourcePath = Join-Path $source $name
            $stagePath = Join-Path $staging $name
            Copy-Item -LiteralPath $sourcePath -Destination $stagePath -Force
            [void]$manifestFiles.Add([pscustomobject][ordered]@{ Name=$name; Sha256=Get-ManagedDeploymentSha256 -Path $stagePath })
        }
        $newManifest = [pscustomobject][ordered]@{
            SchemaVersion = $deploymentSchemaVersion
            InstalledAtUtc = [DateTime]::UtcNow.ToString("o")
            Files = @($manifestFiles.ToArray())
            ContainsSecrets = $false
            NetworkConfigurationManaged = $false
            SourceTrustMode = [string]$sourceTrust.Mode
            SourceManifestSha256 = [string]$sourceTrust.ManifestSha256
        }
        [IO.File]::WriteAllText((Join-Path $staging "enterprise-deployment-manifest.json"), ($newManifest | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
        if (-not (Test-Path -LiteralPath $target -PathType Container)) {
            Move-Item -LiteralPath $staging -Destination $target
            $staging = ""
        } else {
            if ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Deployment target cannot be a reparse point." }
            foreach ($name in $payloadNames) { Move-Item -LiteralPath (Join-Path $staging $name) -Destination (Join-Path $target $name) -Force }
            Move-Item -LiteralPath (Join-Path $staging "enterprise-deployment-manifest.json") -Destination $manifestPath -Force
        }
    } finally {
        if (-not [string]::IsNullOrWhiteSpace($staging) -and (Test-Path -LiteralPath $staging -PathType Container)) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $state = Test-ManagedDeploymentState -Target $target
    if (-not $state.Compliant) { throw "Deployment verification failed: $($state.Reason)" }
    $result = [pscustomobject][ordered]@{
        Success=$true; Action=$Action; TargetDirectory=$target; FileCount=$state.FileCount
        ContainsSecrets=$false; NetworkConfigurationManaged=$false
        SourceTrustMode=[string]$sourceTrust.Mode; SourceManifestSha256=[string]$sourceTrust.ManifestSha256
    }
    if (-not $Quiet) { [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress)) }
    exit 0
} catch {
    if (-not $Quiet) { [Console]::Error.WriteLine(([pscustomobject][ordered]@{ Success=$false; Action=$Action; Error=[string]$_.Exception.Message } | ConvertTo-Json -Compress)) }
    exit 2
}
