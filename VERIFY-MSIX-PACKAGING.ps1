[CmdletBinding()]
param(
    [string]$SourceDirectory = $PSScriptRoot,
    [string]$DevelopmentPackagePath = '',
    [string]$StorePackagePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$failures = New-Object System.Collections.Generic.List[string]
$sourceRoot = [IO.Path]::GetFullPath($SourceDirectory)
$packagingScript = Join-Path $sourceRoot 'packaging\msix\New-ToolKiemTraMsix.ps1'
$packagingReadme = Join-Path $sourceRoot 'packaging\msix\README.md'
$capabilityJustification = Join-Path $sourceRoot 'packaging\msix\STORE-CAPABILITY-JUSTIFICATION.md'
$applicationManifest = Join-Path $sourceRoot 'Tool-Kiem-Tra-v5.0-OneFile.manifest'

function Read-RequiredText {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $failures.Add("Missing required MSIX file: $Path")
        return ''
    }
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Text -notmatch $Pattern) { $failures.Add($Message) }
}

function Test-Package {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('Development','Store')][string]$Mode
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $failures.Add("Missing $Mode MSIX package: $Path")
        return
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($Mode -eq 'Development') {
        if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
            $failures.Add("Development MSIX signature is not valid: $($signature.Status)")
        }
        if ($null -eq $signature.TimeStamperCertificate) {
            $failures.Add('Development MSIX has no timestamp countersignature.')
        }
    } elseif ($signature.Status -ne [Management.Automation.SignatureStatus]::NotSigned) {
        $failures.Add('Store candidate must remain unsigned before Partner Center processing.')
    }

    $makeAppx = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\makeappx.exe'
    if (-not (Test-Path -LiteralPath $makeAppx -PathType Leaf)) {
        $failures.Add('MakeAppx is unavailable for package structure verification.')
        return
    }
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('tool-msix-verify-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        & $makeAppx unpack /p ([IO.Path]::GetFullPath($Path)) /d $tempRoot /o | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $failures.Add("MakeAppx could not unpack $Mode package.")
            return
        }
        $manifestPath = Join-Path $tempRoot 'AppxManifest.xml'
        $manifestText = Read-RequiredText -Path $manifestPath
        Assert-Contains $manifestText 'EntryPoint="Windows\.FullTrustApplication"' "$Mode package is not a full-trust desktop package."
        Assert-Contains $manifestText '<rescap:Capability\s+Name="runFullTrust"\s*/>' "$Mode package does not declare runFullTrust."
        Assert-Contains $manifestText '<rescap:Capability\s+Name="allowElevation"\s*/>' "$Mode package does not declare allowElevation."
        $packagedExe = Join-Path $tempRoot 'Tool-Kiem-Tra-v5.0.exe'
        if (-not (Test-Path -LiteralPath $packagedExe -PathType Leaf)) {
            $failures.Add("$Mode package is missing Tool-Kiem-Tra-v5.0.exe.")
        }
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
            if (-not $resolvedTemp.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Refusing to remove MSIX verification directory outside the system temp directory.'
            }
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
    }
}

$scriptText = Read-RequiredText -Path $packagingScript
$readmeText = Read-RequiredText -Path $packagingReadme
$capabilityText = Read-RequiredText -Path $capabilityJustification
$appManifestText = Read-RequiredText -Path $applicationManifest

$tokens = $null
$parseErrors = $null
if ($scriptText.Length -gt 0) {
    [void][Management.Automation.Language.Parser]::ParseFile($packagingScript, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        $failures.Add("MSIX packaging script parse error at line $($parseError.Extent.StartLineNumber): $($parseError.Message)")
    }
}

Assert-Contains $scriptText "ValidateSet\('Development','Store'\)" 'MSIX script does not separate Development and Store modes.'
Assert-Contains $scriptText 'SigningCertificateThumbprint' 'MSIX development signing does not require an explicit certificate thumbprint.'
Assert-Contains $scriptText 'Development signing certificate has no private key' 'MSIX script does not reject certificates without a private key.'
Assert-Contains $scriptText '1\.3\.6\.1\.5\.5\.7\.3\.3' 'MSIX script does not enforce Code Signing EKU.'
Assert-Contains $scriptText '/fd SHA256' 'MSIX script does not use SHA-256 file digest signing.'
Assert-Contains $scriptText '/tr \$TimestampServer /td SHA256' 'MSIX script does not use an RFC3161 SHA-256 timestamp.'
Assert-Contains $scriptText 'Store mode requires the exact Publisher value assigned by Partner Center' 'Store mode does not require the Partner Center Publisher value.'
Assert-Contains $scriptText 'PackageName.*not valid for an MSIX identity' 'MSIX package identity validation is missing.'
Assert-Contains $scriptText 'Packaged executable hash does not match source executable' 'MSIX script does not compare the packaged executable hash.'
Assert-Contains $scriptText '<rescap:Capability Name="runFullTrust" />' 'MSIX manifest template does not declare runFullTrust.'
Assert-Contains $scriptText '<rescap:Capability Name="allowElevation" />' 'MSIX manifest template does not declare allowElevation.'
Assert-Contains $appManifestText 'requestedExecutionLevel\s+level="asInvoker"' 'Main executable manifest is not asInvoker.'
if ($appManifestText -match 'requestedExecutionLevel\s+level="requireAdministrator"') {
    $failures.Add('Main executable manifest forces administrator elevation at launch.')
}
Assert-Contains $capabilityText 'UAC is rejected' 'Store capability justification does not document UAC rejection behavior.'
Assert-Contains $capabilityText 'backup/rollback' 'Store capability justification does not document backup/rollback evidence.'
Assert-Contains $readmeText 'Do not submit the development package' 'MSIX README does not separate the development package from Store submission.'

foreach ($textFile in @($packagingReadme, $capabilityJustification)) {
    if ((Read-RequiredText -Path $textFile).IndexOf([char]27) -ge 0) {
        $failures.Add("Documentation contains terminal escape characters: $textFile")
    }
}

if (-not [string]::IsNullOrWhiteSpace($DevelopmentPackagePath)) {
    Test-Package -Path $DevelopmentPackagePath -Mode Development
}
if (-not [string]::IsNullOrWhiteSpace($StorePackagePath)) {
    Test-Package -Path $StorePackagePath -Mode Store
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure }
    Write-Host "VERIFY-MSIX-PACKAGING: Failed=$($failures.Count)"
    exit 1
}

Write-Host 'VERIFY-MSIX-PACKAGING: Passed'
exit 0

