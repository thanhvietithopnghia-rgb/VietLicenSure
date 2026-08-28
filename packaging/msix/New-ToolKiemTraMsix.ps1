[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [ValidateSet('Development','Store')][string]$Mode = 'Development',
    [string]$PackageName = 'ThanhViet.ToolKiemTra',
    [string]$Publisher = '',
    [string]$PublisherDisplayName = 'Thanh Viet',
    [string]$SigningCertificateThumbprint = '',
    [ValidateSet('CurrentUser','LocalMachine')][string]$SigningCertificateStore = 'CurrentUser',
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [bool]$IncludeAllowElevation = $true
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$version = '5.0.0.0'
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

if (-not (Test-Path -LiteralPath $makeAppx -PathType Leaf)) { throw "MakeAppx not found: $makeAppx" }
if (-not (Test-Path -LiteralPath $signTool -PathType Leaf)) { throw "SignTool not found: $signTool" }
if ($PackageName -notmatch '^[A-Za-z0-9.-]{3,50}$') { throw 'PackageName is not valid for an MSIX identity.' }

$exe = Get-Item -LiteralPath $ExecutablePath
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
} elseif ([string]::IsNullOrWhiteSpace($Publisher)) {
    throw 'Store mode requires the exact Publisher value assigned by Partner Center.'
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
    <DisplayName>Tool Kiểm Tra</DisplayName>
    <PublisherDisplayName>$escapedPublisherDisplayName</PublisherDisplayName>
    <Description>Kiểm tra cấu hình, bằng chứng và trạng thái tuân thủ bản quyền Windows/Office.</Description>
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
        DisplayName="Tool Kiểm Tra"
        Description="Kiểm tra cấu hình và tuân thủ bản quyền"
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

[xml]$unpackedManifest = Get-Content -LiteralPath (Join-Path $unpack 'AppxManifest.xml') -Raw
$packagedExe = Join-Path $unpack 'Tool-Kiem-Tra-v5.0.exe'
$sourceExeHash = (Get-FileHash -LiteralPath $exe.FullName -Algorithm SHA256).Hash
$packagedExeHash = (Get-FileHash -LiteralPath $packagedExe -Algorithm SHA256).Hash
if ($sourceExeHash -cne $packagedExeHash) { throw 'Packaged executable hash does not match source executable.' }

$report = [ordered]@{
    SchemaVersion = 1
    CreatedAtUtc = [DateTime]::UtcNow.ToString('o')
    Mode = $Mode
    PackageName = $PackageName
    Publisher = $Publisher
    Version = $version
    Architecture = 'x64'
    IncludeRunFullTrust = $true
    IncludeAllowElevation = $IncludeAllowElevation
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
