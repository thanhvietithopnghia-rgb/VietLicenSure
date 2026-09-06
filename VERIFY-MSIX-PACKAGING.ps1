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
$storeIdentityPath = Join-Path $sourceRoot 'packaging\msix\STORE-PRODUCT-IDENTITY.json'
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

function Test-StoreLauncherTrustProfile {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($Path))
        $type = $assembly.GetType('ThanhViet.ToolKiemTra.Program', $true)
        $flags = [Reflection.BindingFlags]::NonPublic -bor [Reflection.BindingFlags]::Static
        $expected = [ordered]@{
            SignedStableBuildMarker = '0'
            ManagedSignedBuildMarker = '0'
            StoreBuildMarker = '1'
            StorePackageName = 'ThanhVit.ToolKimTraBnQuyn'
            StorePackageVersion = '5.0.0.1'
            StorePackagePublisherId = '9tjmpwr25h78w'
            StorePackageFamilyName = 'ThanhVit.ToolKimTraBnQuyn_9tjmpwr25h78w'
        }
        foreach ($entry in $expected.GetEnumerator()) {
            $field = $type.GetField([string]$entry.Key, $flags)
            if (-not $field -or [string]$field.GetRawConstantValue() -cne [string]$entry.Value) { return $false }
        }
        $payloadField = $type.GetField('PayloadFiles', $flags)
        if (-not $payloadField) { return $false }
        $payloads = @($payloadField.GetValue($null))
        return [bool]($payloads.Count -eq 56 -and
            $payloads -contains 'OFFICIAL-PROVENANCE-v1.json.p7s' -and
            $payloads -contains 'Tool-ResultCenter.ps1')
    } catch {
        return $false
    }
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
        [xml]$manifestXml = $manifestText
        Assert-Contains $manifestText 'EntryPoint="Windows\.FullTrustApplication"' "$Mode package is not a full-trust desktop package."
        Assert-Contains $manifestText '<rescap:Capability\s+Name="runFullTrust"\s*/>' "$Mode package does not declare runFullTrust."
        Assert-Contains $manifestText '<rescap:Capability\s+Name="allowElevation"\s*/>' "$Mode package does not declare allowElevation."
        $identity = $manifestXml.Package.Identity
        $properties = $manifestXml.Package.Properties
        if ([string]$properties.DisplayName -cne [string]$storeIdentity.ReservedName) {
            $failures.Add("$Mode package DisplayName does not match the reserved Store name.")
        }
        if ([string]$properties.PublisherDisplayName -cne [string]$storeIdentity.PublisherDisplayName) {
            $failures.Add("$Mode package PublisherDisplayName does not match Partner Center.")
        }
        if ([string]$properties.Description -cne [string]$storeIdentity.Description) {
            $failures.Add("$Mode package Description is not the expected UTF-8 text.")
        }
        if ($Mode -eq 'Store') {
            if ([string]$identity.Name -cne [string]$storeIdentity.PackageIdentityName) {
                $failures.Add('Store package identity Name does not match Partner Center.')
            }
            if ([string]$identity.Publisher -cne [string]$storeIdentity.PackageIdentityPublisher) {
                $failures.Add('Store package identity Publisher does not match Partner Center.')
            }
        }
        $packagedExe = Join-Path $tempRoot 'Tool-Kiem-Tra-v5.0.exe'
        if (-not (Test-Path -LiteralPath $packagedExe -PathType Leaf)) {
            $failures.Add("$Mode package is missing Tool-Kiem-Tra-v5.0.exe.")
        } elseif ($Mode -eq 'Store' -and -not (Test-StoreLauncherTrustProfile -Path $packagedExe)) {
            $failures.Add('Store package contains a DevelopmentUnsigned or mismatched launcher instead of the exact StoreSubmission trust profile.')
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
$storeIdentityText = Read-RequiredText -Path $storeIdentityPath
$appManifestText = Read-RequiredText -Path $applicationManifest

$storeIdentity = $null
if ($storeIdentityText.Length -gt 0) {
    try { $storeIdentity = $storeIdentityText | ConvertFrom-Json }
    catch { $failures.Add("Store identity JSON is invalid: $($_.Exception.Message)") }
}
if ($null -ne $storeIdentity) {
    if ([int]$storeIdentity.SchemaVersion -ne 1) { $failures.Add('Store identity schema version is unsupported.') }
    if ([string]$storeIdentity.ProductId -notmatch '^[A-Z0-9]{12}$') { $failures.Add('Store ProductId is invalid.') }
    if ([string]$storeIdentity.PackageIdentityName -notmatch '^[A-Za-z0-9.-]{3,50}$') { $failures.Add('Store PackageIdentityName is invalid.') }
    if ([string]$storeIdentity.PackageIdentityPublisher -notmatch '^CN=[A-Za-z0-9-]+$') { $failures.Add('Store PackageIdentityPublisher is invalid.') }
    if ([string]$storeIdentity.PackagePublisherId -ne '9tjmpwr25h78w' -or
        [string]$storeIdentity.PackageFamilyName -ne 'ThanhVit.ToolKimTraBnQuyn_9tjmpwr25h78w') {
        $failures.Add('Store PackagePublisherId/PackageFamilyName is invalid.')
    }
    foreach ($name in @('ReservedName','PublisherDisplayName','Description','ApplicationDescription')) {
        $property = $storeIdentity.PSObject.Properties[$name]
        if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $failures.Add("Store identity property is missing: $name")
        }
    }
}

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
Assert-Contains $scriptText 'STORE-PRODUCT-IDENTITY\.json' 'MSIX script is not bound to the Partner Center identity file.'
Assert-Contains $scriptText 'does not match the Partner Center Store identity' 'Store mode does not reject mismatched Partner Center identity values.'
Assert-Contains $scriptText 'StoreSubmission executable with exact Partner Center identity and signed provenance' 'Store mode does not reject DevelopmentUnsigned launchers.'
Assert-Contains $scriptText 'MicrosoftStorePackageIdentity' 'Store mode does not require the Store-specific release trust scope.'
Assert-Contains $scriptText '\[Text\.Encoding\]::UTF8' 'MSIX script does not read Store display text explicitly as UTF-8.'
Assert-Contains $scriptText 'ReadAllText\(\$unpackedManifestPath, \[Text\.Encoding\]::UTF8\)' 'MSIX script does not verify the unpacked manifest explicitly as UTF-8.'
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
