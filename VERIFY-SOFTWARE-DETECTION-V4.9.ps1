[CmdletBinding()]
param([switch]$IncludeLiveInventory)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'Tool-SoftwareInventory.ps1')

$failures = New-Object System.Collections.Generic.List[string]
function Assert-Detection {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$portable = New-ToolSoftwareInventoryRecord -Name 'AutoCAD 2022' -Version '24.1' -Publisher 'Autodesk' `
    -InstallDate '' -InstallLocation 'C:\Program Files\ASUS\Autodesk\AutoCAD 2022' -DisplayIcon '' -UninstallString '' `
    -RegistryPath '' -Scope 'PortableDiscovery' -Architecture '64-bit' -SourceKind 'PortableDiscovery' `
    -RepresentativePath 'C:\Program Files\ASUS\Autodesk\AutoCAD 2022\acad.exe' -SkipSignature -SkipExecutableDiscovery
$portableMerged = @(Merge-ToolSoftwareInventoryRecords -Records @($portable))[0]
Assert-Detection ([string]$portableMerged.PresenceState -eq 'ResidualOrPortableFiles') 'Portable-only tree was presented as an installed product.'
Assert-Detection (-not [bool]$portableMerged.InstalledConfirmed) 'Portable-only tree was marked InstalledConfirmed.'

$registry = New-ToolSoftwareInventoryRecord -Name 'Adobe Acrobat (64-bit)' -Version '25.1' -Publisher 'Adobe Inc.' `
    -InstallDate '' -InstallLocation 'C:\Program Files\Adobe\Acrobat DC\Acrobat' -DisplayIcon '' -UninstallString 'uninstall.exe' `
    -RegistryPath 'HKLM:\Software\Example\Acrobat' -Scope 'Machine64' -Architecture '64-bit' -SourceKind 'Registry' `
    -RepresentativePath 'C:\Program Files\Adobe\Acrobat DC\Acrobat\Acrobat.exe' -SkipSignature -SkipExecutableDiscovery
$package = New-ToolSoftwareInventoryRecord -Name 'Adobe Acrobat (64-bit)' -Version '25.1' -Publisher '' `
    -InstallDate '' -InstallLocation '' -DisplayIcon '' -UninstallString '' -RegistryPath '' -Scope 'PackageManager' `
    -Architecture '' -SourceKind 'PackageManager' -RepresentativePath '' -SourceDetail 'Winget:Adobe.Acrobat.Pro' `
    -PackageId 'Adobe.Acrobat.Pro' -SkipSignature -SkipExecutableDiscovery
$confirmed = @(Merge-ToolSoftwareInventoryRecords -Records @($registry,$package))[0]
Assert-Detection ([string]$confirmed.PresenceState -eq 'InstalledConfirmed') 'Registry + WinGet did not produce InstalledConfirmed.'
Assert-Detection ([bool]$confirmed.InstalledConfirmed) 'InstalledConfirmed boolean was not set.'
Assert-Detection (@($confirmed.DiscoverySources).Count -eq 2) 'Independent discovery sources were not preserved.'

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tool-detection-' + [Guid]::NewGuid().ToString('N'))
try {
    $productRoot = Join-Path $scratch 'Adobe\Acrobat DC\Acrobat'
    [void](New-Item -ItemType Directory -Path $productRoot -Force)
    [IO.File]::WriteAllBytes((Join-Path $productRoot 'Acrobat.exe'), [byte[]](1..32))
    [IO.File]::WriteAllBytes((Join-Path $productRoot 'Acrobat.dll'), [byte[]](1..32))
    $app = New-ToolSoftwareInventoryRecord -Name 'Adobe Acrobat (64-bit)' -Version '25.1' -Publisher 'Adobe Inc.' `
        -InstallDate '' -InstallLocation $productRoot -DisplayIcon '' -UninstallString '' -RegistryPath '' -Scope 'Registry' `
        -Architecture '64-bit' -SourceKind 'Registry' -RepresentativePath (Join-Path $productRoot 'Acrobat.exe') -SkipSignature -SkipExecutableDiscovery
    $state = New-ToolSoftwareDeepScanState -MaximumDurationSeconds 30 -MaximumTotalEntries 1000 `
        -MaximumTotalSignatureChecks 100 -MaximumTotalHashChecks 100 -MaximumFilesPerRoot 100 -MaximumEntriesPerRoot 1000
    $preparation = New-ToolSoftwareDeepScanPreparation -Application $app -CatalogProduct $null -Catalog $null -State $state
    Assert-Detection ([bool]$preparation.FullPeIntegrityCoverage) 'Adobe did not enable full PE integrity coverage.'
    Assert-Detection (@($preparation.SignatureCandidates).Count -ge 2) 'Adobe PE candidate set omitted an EXE or DLL.'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

$cleanupSource = [IO.File]::ReadAllText((Join-Path $root 'windows-license-compliance-cleanup.ps1'))
$rootFunctionStart = $cleanupSource.IndexOf('function Get-ThirdPartyNormalizedInstallRoot', [StringComparison]::Ordinal)
$rootFunctionEnd = $cleanupSource.IndexOf('function Test-ThirdPartyArtifactPath', $rootFunctionStart, [StringComparison]::Ordinal)
$rootFunction = if ($rootFunctionStart -ge 0 -and $rootFunctionEnd -gt $rootFunctionStart) { $cleanupSource.Substring($rootFunctionStart, $rootFunctionEnd - $rootFunctionStart) } else { '' }
$representativeIndex = $rootFunction.IndexOf('$Application.RepresentativePath', [StringComparison]::Ordinal)
$installIndex = $rootFunction.IndexOf('$Application.InstallLocation', [StringComparison]::Ordinal)
Assert-Detection ($representativeIndex -ge 0 -and $installIndex -gt $representativeIndex) 'Evidence correlation does not prefer the representative product path.'
Assert-Detection ($cleanupSource -match 'Measure-Object -Property Specificity -Maximum') 'Overlapping vendor roots are not resolved by path specificity.'

if ($IncludeLiveInventory) {
    $livePackages = @(Get-ToolPackageManagerSoftwareInventory)
    Assert-Detection (@($livePackages | Where-Object { [string]$_.SourceDetail -like 'Winget:*' }).Count -gt 0) 'WinGet returned no parseable local inventory records.'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'VERIFY-SOFTWARE-DETECTION-V4.9: PASS'
