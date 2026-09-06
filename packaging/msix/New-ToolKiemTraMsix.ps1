[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [ValidateSet('Development','Store')][string]$Mode = 'Development',
    [string]$PackageName = '',
    [string]$Publisher = '',
    [string]$PublisherDisplayName = '',
    [string]$StoreIdentityPath = '',
    [string]$SigningCertificateThumbprint = '',
    [ValidateSet('CurrentUser','LocalMachine')][string]$SigningCertificateStore = 'CurrentUser',
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [bool]$IncludeAllowElevation = $true
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$version = '5.0.0.1'
$sdkBin = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64'
$makeAppx = Join-Path $sdkBin 'makeappx.exe'
$signTool = Join-Path $sdkBin 'signtool.exe'

function Assert-PlainDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $ancestor = $fullPath
    while (-not (Test-Path -LiteralPath $ancestor)) {
        $parent = Split-Path -Parent $ancestor
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $ancestor) { break }
        $ancestor = $parent
    }
    if (-not (Test-Path -LiteralPath $ancestor -PathType Container)) {
        throw 'OutputDirectory has no existing directory ancestor.'
    }
    $cursor = Get-Item -LiteralPath $ancestor -Force
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "OutputDirectory cannot traverse a reparse point: $($cursor.FullName)"
        }
        $cursor = $cursor.Parent
    }
    return $fullPath
}

function New-LogoPng {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object Drawing.Bitmap($Width, $Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([Drawing.Color]::FromArgb(17, 44, 72))
        $inset = [Math]::Max(2, [int]([Math]::Min($Width, $Height) * 0.12))
        $penWidth = [Math]::Max(2, [single]([Math]::Min($Width, $Height) * 0.075))
        $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(70, 210, 166), $penWidth)
        try {
            $graphics.DrawEllipse($pen, $inset, $inset, $Height - (2 * $inset), $Height - (2 * $inset))
        } finally {
            $pen.Dispose()
        }
        $fontSize = [Math]::Max(8, [single]([Math]::Min($Width, $Height) * 0.28))
        $font = New-Object Drawing.Font('Segoe UI', $fontSize, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
        $brush = New-Object Drawing.SolidBrush([Drawing.Color]::White)
        $format = New-Object Drawing.StringFormat
        try {
            $format.Alignment = [Drawing.StringAlignment]::Center
            $format.LineAlignment = [Drawing.StringAlignment]::Center
            $graphics.DrawString('TK', $font, $brush, (New-Object Drawing.RectangleF(0, 0, $Width, $Height)), $format)
        } finally {
            $format.Dispose()
            $brush.Dispose()
            $font.Dispose()
        }
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-RequiredJsonProperty {
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        throw "Store identity is missing required property: $Name"
    }
    return [string]$property.Value
}

function Get-LauncherTrustProfile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($Path)))
    $type = $assembly.GetType('ThanhViet.ToolKiemTra.Program', $true)
    $flags = [Reflection.BindingFlags]::NonPublic -bor [Reflection.BindingFlags]::Static
    $values = [ordered]@{}
    foreach ($name in @('SignedStableBuildMarker','ManagedSignedBuildMarker','StoreBuildMarker','StorePackageName','StorePackageVersion','StorePackagePublisherId','StorePackageFamilyName')) {
        $field = $type.GetField($name, $flags)
        if (-not $field) { throw "Executable is missing trust marker: $name" }
        $values[$name] = [string]$field.GetRawConstantValue()
    }
    $payloadField = $type.GetField('PayloadFiles', $flags)
    if (-not $payloadField) { throw 'Executable is missing PayloadFiles.' }
    $payloads = @($payloadField.GetValue($null))
    $values['PayloadCount'] = [int]$payloads.Count
    $values['ProvenanceSignatureEmbedded'] = [bool]($payloads -contains 'OFFICIAL-PROVENANCE-v1.json.p7s')
    $values['ResultCenterEmbedded'] = [bool]($payloads -contains 'Tool-ResultCenter.ps1')
    return [pscustomobject]$values
}

if (-not (Test-Path -LiteralPath $makeAppx -PathType Leaf)) { throw "MakeAppx not found: $makeAppx" }
if (-not (Test-Path -LiteralPath $signTool -PathType Leaf)) { throw "SignTool not found: $signTool" }

if ([string]::IsNullOrWhiteSpace($StoreIdentityPath)) {
    $StoreIdentityPath = Join-Path $PSScriptRoot 'STORE-PRODUCT-IDENTITY.json'
}
if (-not (Test-Path -LiteralPath $StoreIdentityPath -PathType Leaf)) {
    throw "Store identity file not found: $StoreIdentityPath"
}
$storeIdentity = [IO.File]::ReadAllText(
    [IO.Path]::GetFullPath($StoreIdentityPath),
    [Text.Encoding]::UTF8
) | ConvertFrom-Json
if ([int]$storeIdentity.SchemaVersion -ne 1) { throw 'Unsupported Store identity schema version.' }

$storeProductId = Get-RequiredJsonProperty -InputObject $storeIdentity -Name 'ProductId'
$storeReservedName = Get-RequiredJsonProperty -InputObject $storeIdentity -Name 'ReservedName'
$storePackageName = Get-RequiredJsonProperty -InputObject $storeIdentity -Name 'PackageIdentityName'
$storePublisher = Get-RequiredJsonProperty -InputObject $storeIdentity -Name 'PackageIdentityPublisher'
$storePublisherId = Get-RequiredJsonProperty -InputObject $storeIdentity -Name 'PackagePublisherId'
$storeFamilyName = Get-RequiredJsonProperty -InputObject $storeIdentity -Name 'PackageFamilyName'
$storePublisherDisplayName = Get-RequiredJsonProperty -InputObject $storeIdentity -Name 'PublisherDisplayName'
$storeDescription = Get-RequiredJsonProperty -InputObject $storeIdentity -Name 'Description'
$storeApplicationDescription = Get-RequiredJsonProperty -InputObject $storeIdentity -Name 'ApplicationDescription'

if ($storeProductId -notmatch '^[A-Z0-9]{12}$') { throw 'Store ProductId is not valid.' }
if ($storePackageName -notmatch '^[A-Za-z0-9.-]{3,50}$') { throw 'Store PackageIdentityName is not valid.' }
if ($storePublisher -notmatch '^CN=[A-Za-z0-9-]+$') { throw 'Store PackageIdentityPublisher is not valid.' }
if ($storePublisherId -notmatch '^[0-9a-hjkmnp-tv-z]{13}$' -or $storeFamilyName -cne ($storePackageName + '_' + $storePublisherId)) {
    throw 'Store PackagePublisherId/PackageFamilyName is not valid.'
}

if ($Mode -eq 'Store') {
    if (-not [string]::IsNullOrWhiteSpace($PackageName) -and $PackageName -cne $storePackageName) {
        throw 'PackageName does not match the Partner Center Store identity.'
    }
    if (-not [string]::IsNullOrWhiteSpace($Publisher) -and $Publisher -cne $storePublisher) {
        throw 'Publisher does not match the Partner Center Store identity.'
    }
    if (-not [string]::IsNullOrWhiteSpace($PublisherDisplayName) -and $PublisherDisplayName -cne $storePublisherDisplayName) {
        throw 'PublisherDisplayName does not match the Partner Center Store identity.'
    }
    $PackageName = $storePackageName
    $Publisher = $storePublisher
    $PublisherDisplayName = $storePublisherDisplayName
} else {
    if ([string]::IsNullOrWhiteSpace($PackageName)) { $PackageName = 'ThanhViet.ToolKiemTra.Development' }
    if ([string]::IsNullOrWhiteSpace($PublisherDisplayName)) { $PublisherDisplayName = $storePublisherDisplayName }
}
if ($PackageName -notmatch '^[A-Za-z0-9.-]{3,50}$') { throw 'PackageName is not valid for an MSIX identity.' }

$exe = Get-Item -LiteralPath $ExecutablePath
$launcherTrustProfile = Get-LauncherTrustProfile -Path $exe.FullName
if ($Mode -eq 'Store') {
    if ([string]$launcherTrustProfile.SignedStableBuildMarker -ne '0' -or
        [string]$launcherTrustProfile.ManagedSignedBuildMarker -ne '0' -or
        [string]$launcherTrustProfile.StoreBuildMarker -ne '1' -or
        [string]$launcherTrustProfile.StorePackageName -cne $storePackageName -or
        [string]$launcherTrustProfile.StorePackageVersion -cne $version -or
        [string]$launcherTrustProfile.StorePackagePublisherId -cne $storePublisherId -or
        [string]$launcherTrustProfile.StorePackageFamilyName -cne $storeFamilyName -or
        [int]$launcherTrustProfile.PayloadCount -ne 56 -or
        -not [bool]$launcherTrustProfile.ProvenanceSignatureEmbedded -or
        -not [bool]$launcherTrustProfile.ResultCenterEmbedded) {
        throw 'Store mode requires a fail-closed StoreSubmission executable with exact Partner Center identity and signed provenance.'
    }
    $exeSignature = Get-AuthenticodeSignature -LiteralPath $exe.FullName
    if ($exeSignature.Status -ne [Management.Automation.SignatureStatus]::NotSigned) {
        throw "StoreSubmission executable must remain unsigned before Partner Center packaging: $($exeSignature.Status)"
    }
    $releaseManifestPath = Join-Path $exe.DirectoryName 'RELEASE-MANIFEST.json'
    if (-not (Test-Path -LiteralPath $releaseManifestPath -PathType Leaf)) {
        throw 'StoreSubmission executable is missing its RELEASE-MANIFEST.json.'
    }
    $releaseManifest = Get-Content -LiteralPath $releaseManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $releaseArtifact = @($releaseManifest.Artifacts | Where-Object { [string]$_.FileName -ceq $exe.Name })
    if ([string]$releaseManifest.ReleaseStatus -cne 'StoreSubmission' -or
        [string]$releaseManifest.AuthenticodeTrustScope -cne 'MicrosoftStorePackageIdentity' -or
        [string]$releaseManifest.OfficialBuildProvenance.State -cne 'Official' -or
        $releaseArtifact.Count -ne 1 -or
        [string]$releaseArtifact[0].Sha256 -cne (Get-FileHash -LiteralPath $exe.FullName -Algorithm SHA256).Hash) {
        throw 'StoreSubmission release manifest does not bind the executable, package trust scope, and official provenance.'
    }
}
$output = Assert-PlainDirectory -Path $OutputDirectory
if (Test-Path -LiteralPath $output) {
    if (@(Get-ChildItem -LiteralPath $output -Force).Count -ne 0) {
        throw 'OutputDirectory must be new or empty.'
    }
} else {
    New-Item -ItemType Directory -Path $output | Out-Null
}

$certificate = $null
if ($Mode -eq 'Development') {
    if ([string]::IsNullOrWhiteSpace($SigningCertificateThumbprint)) {
        throw 'Development mode requires SigningCertificateThumbprint.'
    }
    $certPath = "Cert:\$SigningCertificateStore\My\$SigningCertificateThumbprint"
    $certificate = Get-Item -LiteralPath $certPath -ErrorAction Stop
    if (-not $certificate.HasPrivateKey) { throw 'Development signing certificate has no private key.' }
    if (-not ($certificate.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.3')) {
        throw 'Development signing certificate does not contain Code Signing EKU.'
    }
    if ($certificate.NotAfter.ToUniversalTime() -le [DateTime]::UtcNow) { throw 'Development signing certificate is expired.' }
    $Publisher = $certificate.Subject
}

$staging = Join-Path $output 'staging'
$assets = Join-Path $staging 'Assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $staging 'Tool-Kiem-Tra-v5.0.exe')

New-LogoPng -Path (Join-Path $assets 'StoreLogo.png') -Width 50 -Height 50
New-LogoPng -Path (Join-Path $assets 'Square44x44Logo.png') -Width 44 -Height 44
New-LogoPng -Path (Join-Path $assets 'Square150x150Logo.png') -Width 150 -Height 150
New-LogoPng -Path (Join-Path $assets 'Wide310x150Logo.png') -Width 310 -Height 150

$escapedPackageName = [Security.SecurityElement]::Escape($PackageName)
$escapedPublisher = [Security.SecurityElement]::Escape($Publisher)
$escapedPublisherDisplayName = [Security.SecurityElement]::Escape($PublisherDisplayName)
$escapedProductDisplayName = [Security.SecurityElement]::Escape($storeReservedName)
$escapedDescription = [Security.SecurityElement]::Escape($storeDescription)
$escapedApplicationDescription = [Security.SecurityElement]::Escape($storeApplicationDescription)
$elevationCapability = if ($IncludeAllowElevation) { '    <rescap:Capability Name="allowElevation" />' } else { '' }
$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap rescap">
  <Identity Name="$escapedPackageName" Publisher="$escapedPublisher" Version="$version" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$escapedProductDisplayName</DisplayName>
    <PublisherDisplayName>$escapedPublisherDisplayName</PublisherDisplayName>
    <Description>$escapedDescription</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="vi-vn" />
    <Resource Language="en-us" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26200.0" />
  </Dependencies>
  <Applications>
    <Application Id="ToolKiemTra" Executable="Tool-Kiem-Tra-v5.0.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="$escapedProductDisplayName"
        Description="$escapedApplicationDescription"
        BackgroundColor="#112C48"
        Square44x44Logo="Assets\Square44x44Logo.png"
        Square150x150Logo="Assets\Square150x150Logo.png">
        <uap:DefaultTile Wide310x150Logo="Assets\Wide310x150Logo.png" />
      </uap:VisualElements>
    </Application>
  </Applications>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
$elevationCapability
  </Capabilities>
</Package>
"@
$manifestPath = Join-Path $staging 'AppxManifest.xml'
[IO.File]::WriteAllText($manifestPath, $manifest, (New-Object Text.UTF8Encoding($false)))

$packageFileName = if ($Mode -eq 'Development') { 'Tool-Kiem-Tra-v5.0-development.msix' } else { 'Tool-Kiem-Tra-v5.0-store-unsigned.msix' }
$packagePath = Join-Path $output $packageFileName
& $makeAppx pack /d $staging /p $packagePath /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx pack failed with exit code $LASTEXITCODE." }

$signed = $false
$developmentCertificatePath = $null
if ($Mode -eq 'Development') {
    & $signTool sign /sha1 $certificate.Thumbprint /s My /fd SHA256 /tr $TimestampServer /td SHA256 $packagePath
    if ($LASTEXITCODE -ne 0) { throw "SignTool sign failed with exit code $LASTEXITCODE." }
    & $signTool verify /pa /v $packagePath
    if ($LASTEXITCODE -ne 0) { throw "SignTool verify failed with exit code $LASTEXITCODE." }
    $signed = $true
    $developmentCertificatePath = Join-Path $output 'Tool-Kiem-Tra-v5.0-development.cer'
    Export-Certificate -Cert $certificate -FilePath $developmentCertificatePath -Type CERT -Force | Out-Null
}

$unpack = Join-Path $output 'verification-unpacked'
& $makeAppx unpack /p $packagePath /d $unpack /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx unpack failed with exit code $LASTEXITCODE." }

$unpackedManifestPath = Join-Path $unpack 'AppxManifest.xml'
[xml]$unpackedManifest = [IO.File]::ReadAllText($unpackedManifestPath, [Text.Encoding]::UTF8)
$unpackedIdentity = $unpackedManifest.Package.Identity
$unpackedProperties = $unpackedManifest.Package.Properties
if ([string]$unpackedIdentity.Name -cne $PackageName) { throw 'Packaged identity Name does not match the requested identity.' }
if ([string]$unpackedIdentity.Publisher -cne $Publisher) { throw 'Packaged identity Publisher does not match the requested identity.' }
if ([string]$unpackedProperties.DisplayName -cne $storeReservedName) { throw 'Packaged DisplayName does not match the reserved Store name.' }
if ([string]$unpackedProperties.PublisherDisplayName -cne $PublisherDisplayName) { throw 'Packaged PublisherDisplayName does not match the requested value.' }
if ([string]$unpackedProperties.Description -cne $storeDescription) { throw 'Packaged Description is not valid UTF-8 Store text.' }
$packagedExe = Join-Path $unpack 'Tool-Kiem-Tra-v5.0.exe'
$sourceExeHash = (Get-FileHash -LiteralPath $exe.FullName -Algorithm SHA256).Hash
$packagedExeHash = (Get-FileHash -LiteralPath $packagedExe -Algorithm SHA256).Hash
if ($sourceExeHash -cne $packagedExeHash) { throw 'Packaged executable hash does not match source executable.' }

$report = [ordered]@{
    SchemaVersion = 1
    CreatedAtUtc = [DateTime]::UtcNow.ToString('o')
    Mode = $Mode
    StoreProductId = $storeProductId
    StoreIdentityPath = [IO.Path]::GetFullPath($StoreIdentityPath)
    ProductDisplayName = $storeReservedName
    PackageName = $PackageName
    Publisher = $Publisher
    PackagePublisherId = $storePublisherId
    PackageFamilyName = $storeFamilyName
    PublisherDisplayName = $PublisherDisplayName
    Version = $version
    Architecture = 'x64'
    IncludeRunFullTrust = $true
    IncludeAllowElevation = $IncludeAllowElevation
    LauncherTrustProfile = $launcherTrustProfile
    Signed = $signed
    SigningCertificateThumbprint = if ($certificate) { $certificate.Thumbprint } else { $null }
    DevelopmentCertificatePath = $developmentCertificatePath
    SourceExecutable = $exe.FullName
    SourceExecutableSha256 = $sourceExeHash
    PackagePath = $packagePath
    PackageSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
    PackagedExecutableSha256 = $packagedExeHash
    StructureVerification = 'Passed'
}
$reportPath = Join-Path $output 'MSIX-BUILD-REPORT.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))

Write-Host "MSIX package: $packagePath"
Write-Host "MSIX SHA-256: $($report.PackageSha256)"
Write-Host 'Structure verification: Passed'
if ($Mode -eq 'Development') {
    Write-Warning 'This package uses a private development certificate. It is not a Public Stable or Store signature.'
} else {
    Write-Warning 'This is an unsigned Store candidate. Partner Center identity and certification are still required.'
}
