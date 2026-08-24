$script:ToolPluginSchemaVersion = "1.0"
$script:ToolPluginEngineVersion = "1.2"
$script:ToolPluginToolVersion = "5.0"
$script:ToolPluginMaximumSignatureBytes = 65536
$script:ToolPluginSignatureSuffix = ".p7s"
$script:ToolPluginCatalogSchemaVersion = "1.0"
$script:ToolPluginCatalogMaximumBytes = 524288
$script:ToolPluginCatalogMaximumEntries = 256
$script:ToolPluginCatalogWarningAgeDays = 30
$script:ToolPluginCatalogMaximumAgeDays = 45
$script:ToolPluginCatalogFutureSkewHours = 24

$toolPluginLocalizationPath = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if ((-not (Get-Command Get-ToolTextCurrent -ErrorAction SilentlyContinue) -or
     -not (Get-Variable -Name ToolLocalizationSupportedCultures -Scope Script -ErrorAction SilentlyContinue)) -and
    (Test-Path -LiteralPath $toolPluginLocalizationPath -PathType Leaf)) {
    . $toolPluginLocalizationPath
}

function Get-ToolPluginMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolPluginSchemaVersion
        EngineVersion = $script:ToolPluginEngineVersion
        ToolVersion = $script:ToolPluginToolVersion
        Model = "DeclarativeReadOnlyRules"
        SupportedRuleTypes = @("RegistryValue", "File", "Service")
        MaximumPluginBytes = 524288
        MaximumSignatureBytes = $script:ToolPluginMaximumSignatureBytes
        MaximumRulesPerPlugin = 128
        ArbitraryCodeAllowed = $false
        DetachedCmsSupported = $true
        ThirdPartyCatalogSchemaVersion = $script:ToolPluginCatalogSchemaVersion
        MaximumCatalogBytes = $script:ToolPluginCatalogMaximumBytes
        MaximumCatalogEntries = $script:ToolPluginCatalogMaximumEntries
        CatalogNetworkAccessAllowed = $false
        CatalogAutomaticInstallAllowed = $false
        TrustedSignerSource = "ProtectedAdminPolicyOrCallerProvidedCertificateSha256"
        AutomaticCertificateTrust = $false
    }
}

function Get-ToolPluginDirectory {
    $path = [string]$env:TOOL_PLUGIN_DIR
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $PSScriptRoot "plugins"
    }
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($path))
}

function Get-ToolPluginPublisherTrustPath {
    param([string]$PluginDirectory = (Get-ToolPluginDirectory))
    return Join-Path ([IO.Path]::GetFullPath($PluginDirectory)) 'trusted-plugin-publishers-v1.json'
}

function Get-ToolPluginTrustedSignerCertificateSha256 {
    [CmdletBinding()]
    param([string]$PluginDirectory = (Get-ToolPluginDirectory))

    $directoryState = Test-ToolPluginDirectory -Path $PluginDirectory
    if (-not $directoryState.Valid) { throw ($directoryState.Errors -join '; ') }
    if ($env:TOOL_SECURE_LAUNCH -eq '1' -and -not $directoryState.Protected) {
        throw (Get-ToolTextCurrent 'foundation.plugin.trustPolicyProtected')
    }
    $path = Get-ToolPluginPublisherTrustPath -PluginDirectory $directoryState.Path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    $info = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $info.Length -le 0 -or $info.Length -gt 131072) {
        throw (Get-ToolTextCurrent 'foundation.plugin.trustPolicyUnsafe')
    }
    $document = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    foreach ($property in @($document.PSObject.Properties)) {
        if ([string]$property.Name -notin @('SchemaVersion','Publishers')) { throw (Get-ToolTextCurrent 'foundation.plugin.trustPolicyPropertyUnsupported') }
    }
    if ([string]$document.SchemaVersion -ne '1.0') { throw (Get-ToolTextCurrent 'foundation.plugin.trustPolicySchemaUnsupported') }
    if (@($document.Publishers).Count -gt 64) { throw (Get-ToolTextCurrent 'foundation.plugin.trustPolicyTooManyPublishers') }
    $values = New-Object System.Collections.Generic.List[string]
    $publisherIds = @{}
    foreach ($publisher in @($document.Publishers)) {
        foreach ($property in @($publisher.PSObject.Properties)) {
            if ([string]$property.Name -notin @('PublisherId','CertificateSha256','Enabled','DisplayName')) { throw (Get-ToolTextCurrent 'foundation.plugin.trustPolicyEntryPropertyUnsupported') }
        }
        $publisherId = ([string]$publisher.PublisherId).Trim().ToLowerInvariant()
        if ($publisherId -notmatch '^[a-z0-9][a-z0-9.-]{2,79}$' -or $publisherIds.ContainsKey($publisherId)) {
            throw (Get-ToolTextCurrent 'foundation.plugin.trustPolicyPublisherIdInvalid')
        }
        $publisherIds[$publisherId] = $true
        if ($publisher.PSObject.Properties['Enabled'] -and $publisher.Enabled -isnot [bool]) { throw (Get-ToolTextCurrent 'foundation.plugin.trustPolicyEnabledBoolean') }
        if ($publisher.PSObject.Properties['Enabled'] -and -not [bool]$publisher.Enabled) { continue }
        $fingerprintSet = ConvertTo-ToolPluginTrustedSignerSet -TrustedSignerCertificateSha256 @([string]$publisher.CertificateSha256)
        foreach ($fingerprint in @($fingerprintSet.Keys)) { [void]$values.Add([string]$fingerprint) }
    }
    return @($values.ToArray() | Select-Object -Unique)
}

function Test-ToolPluginDirectory {
    param([string]$Path = (Get-ToolPluginDirectory))

    $errors = New-Object System.Collections.Generic.List[string]
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
            [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.directoryMissing"))
        } else {
            $info = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
            if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.directoryReparse"))
            }
        }
        if ($env:TOOL_SECURE_LAUNCH -eq "1") {
            $dataRoot = if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_DATA_ROOT)) {
                [IO.Path]::GetFullPath([string]$env:TOOL_DATA_ROOT)
            } else {
                Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "ThanhViet-Tool-Kiem-Tra\v4.6"
            }
            $expected = Join-Path $dataRoot "plugins"
            if (-not $fullPath.Equals([IO.Path]::GetFullPath($expected), [StringComparison]::OrdinalIgnoreCase)) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.directoryOutsideRoot"))
            } elseif (Test-Path -LiteralPath $fullPath -PathType Container) {
                $acl = Get-Acl -LiteralPath $fullPath -ErrorAction Stop
                $allowedSids = @("S-1-5-32-544", "S-1-5-18")
                if (-not $acl.AreAccessRulesProtected) {
                    [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.directoryAclInherited"))
                }
                $ownerSid = try {
                    $ownerAccount = New-Object Security.Principal.NTAccount([string]$acl.Owner)
                    $ownerAccount.Translate([Security.Principal.SecurityIdentifier]).Value
                } catch {
                    [string]$acl.Owner
                }
                if ($allowedSids -notcontains $ownerSid) {
                    [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.directoryOwnerInvalid"))
                }
                $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor
                    [Security.AccessControl.FileSystemRights]::Modify -bor
                    [Security.AccessControl.FileSystemRights]::FullControl -bor
                    [Security.AccessControl.FileSystemRights]::CreateFiles -bor
                    [Security.AccessControl.FileSystemRights]::CreateDirectories
                foreach ($rule in @($acl.Access)) {
                    if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { continue }
                    if (($rule.FileSystemRights -band $writeMask) -eq 0) { continue }
                    $sid = try { $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { [string]$rule.IdentityReference }
                    if ($allowedSids -notcontains $sid) {
                        [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.directoryWriterInvalid" @($sid)))
                    }
                }
            }
        }
    } catch {
        [void]$errors.Add($_.Exception.Message)
    }
    return [pscustomobject][ordered]@{
        Valid = [bool]($errors.Count -eq 0)
        Path = if ($fullPath) { $fullPath } else { [string]$Path }
        Protected = [bool]($env:TOOL_SECURE_LAUNCH -eq "1" -and $errors.Count -eq 0)
        Errors = @($errors.ToArray())
    }
}

function ConvertTo-ToolPluginSafeText {
    param([AllowNull()][object]$Value, [int]$MaximumLength = 512)

    if ($null -eq $Value) { return "" }
    $text = ([string]$Value).Replace("`r", " ").Replace("`n", " ").Trim()
    $text = [regex]::Replace($text, '(?i)(?<![A-Z0-9])[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}(?![A-Z0-9])', (Get-ToolTextCurrent "foundation.plugin.redactedProductKey"))
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}

function Get-ToolPluginPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Get-ToolPluginLocalizedPropertyValue {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$TextProperty,
        [Parameter(Mandatory = $true)][string]$KeyProperty,
        [AllowNull()][object]$Default = ""
    )

    $key = [string](Get-ToolPluginPropertyValue $Object $KeyProperty "")
    if (-not [string]::IsNullOrWhiteSpace($key)) {
        return Get-ToolTextCurrent $key
    }
    return [string](Get-ToolPluginPropertyValue $Object $TextProperty $Default)
}

function Test-ToolPluginLocalizationKey {
    param(
        [AllowNull()][string]$Key,
        [Parameter(Mandatory = $true)][string]$Field,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.List[string]]$Errors
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return $true }
    if ($Key.Length -gt 160 -or $Key -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,159}$') {
        [void]$Errors.Add((Get-ToolTextCurrent "foundation.plugin.localizationKeyInvalid" @($Field, $Key)))
        return $false
    }
    $resolved = Get-ToolTextCurrent $Key
    if ([string]::Equals($resolved, "[$Key]", [StringComparison]::Ordinal)) {
        [void]$Errors.Add((Get-ToolTextCurrent "foundation.plugin.localizationKeyMissing" @($Field, $Key)))
        return $false
    }
    return $true
}

function Test-ToolPluginObjectProperties {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.List[string]]$Errors
    )

    foreach ($property in @($Object.PSObject.Properties)) {
        if ($Allowed -notcontains [string]$property.Name) {
            [void]$Errors.Add((Get-ToolTextCurrent "foundation.plugin.propertyUnsupported" @($Context, $property.Name)))
        }
    }
}

function ConvertTo-ToolPluginTrustedSignerSet {
    param([AllowEmptyCollection()][string[]]$TrustedSignerCertificateSha256 = @())

    $trusted = @{}
    foreach ($value in @($TrustedSignerCertificateSha256)) {
        $rawValue = ([string]$value).Trim()
        if ($rawValue -notmatch '^[0-9A-Fa-f:\-\s]+$') {
            throw (Get-ToolTextCurrent 'foundation.plugin.signerFingerprintCharacters')
        }
        $normalized = ($rawValue -replace '[:\-\s]', '').ToUpperInvariant()
        if ($normalized -notmatch '^[0-9A-F]{64}$') {
            throw (Get-ToolTextCurrent 'foundation.plugin.signerFingerprintInvalid')
        }
        $trusted[$normalized] = $true
    }
    return $trusted
}

function Get-ToolPluginCertificateSha256 {
    param([Parameter(Mandatory = $true)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Certificate.RawData))).Replace('-', '').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Test-ToolPluginDetachedSignature {
    param(
        [Parameter(Mandatory = $true)][byte[]]$ContentBytes,
        [Parameter(Mandatory = $true)][byte[]]$SignatureBytes,
        [AllowEmptyCollection()][string[]]$TrustedSignerCertificateSha256 = @()
    )

    $status = 'InvalidSignature'
    $signerCertificateSha256 = ''
    try {
        $trustedSigners = ConvertTo-ToolPluginTrustedSignerSet -TrustedSignerCertificateSha256 $TrustedSignerCertificateSha256
        if ($trustedSigners.Count -eq 0) {
            return [pscustomobject][ordered]@{ Valid=$false; Status='TrustedSignerRequired'; SignerCertificateSha256='' }
        }
        if ($ContentBytes.Length -le 0 -or $ContentBytes.Length -gt 524288 -or
            $SignatureBytes.Length -le 64 -or $SignatureBytes.Length -gt $script:ToolPluginMaximumSignatureBytes) {
            return [pscustomobject][ordered]@{ Valid=$false; Status='SignatureSizeInvalid'; SignerCertificateSha256='' }
        }
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $contentInfo = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$ContentBytes)
        $signedCms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($contentInfo, $true)
        $signedCms.Decode($SignatureBytes)
        if ($signedCms.SignerInfos.Count -ne 1) {
            return [pscustomobject][ordered]@{ Valid=$false; Status='SignerCountInvalid'; SignerCertificateSha256='' }
        }
        $signer = $signedCms.SignerInfos[0]
        if ($null -eq $signer.Certificate -or $signer.DigestAlgorithm.Value -ne '2.16.840.1.101.3.4.2.1') {
            return [pscustomobject][ordered]@{ Valid=$false; Status='SignerAlgorithmInvalid'; SignerCertificateSha256='' }
        }
        $signerCertificateSha256 = Get-ToolPluginCertificateSha256 -Certificate $signer.Certificate
        if (-not $trustedSigners.ContainsKey($signerCertificateSha256)) {
            return [pscustomobject][ordered]@{ Valid=$false; Status='SignerNotTrusted'; SignerCertificateSha256=$signerCertificateSha256 }
        }
        $signedCms.CheckSignature($true)
        $status = 'Valid'
        return [pscustomobject][ordered]@{ Valid=$true; Status=$status; SignerCertificateSha256=$signerCertificateSha256 }
    } catch {
        return [pscustomobject][ordered]@{ Valid=$false; Status=$status; SignerCertificateSha256=$signerCertificateSha256 }
    }
}

function Get-ToolPluginCatalogFreshness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Catalog,
        [DateTimeOffset]$NowUtc = [DateTimeOffset]::UtcNow
    )

    $generatedAtText = [string](Get-ToolPluginPropertyValue -Object $Catalog -Name 'GeneratedAtUtc' -Default '')
    $generatedAtUtc = [DateTimeOffset]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $timestampValid = [bool]($generatedAtText -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$' -and
        [DateTimeOffset]::TryParse($generatedAtText, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$generatedAtUtc))
    if (-not $timestampValid) {
        return [pscustomobject][ordered]@{
            Status = 'Invalid'
            GeneratedAtUtc = ''
            AgeDays = $null
            WarningAgeDays = $script:ToolPluginCatalogWarningAgeDays
            MaximumAgeDays = $script:ToolPluginCatalogMaximumAgeDays
            FutureSkewHours = $script:ToolPluginCatalogFutureSkewHours
            InstallationAllowed = $false
        }
    }

    $now = $NowUtc.ToUniversalTime()
    $generated = $generatedAtUtc.ToUniversalTime()
    $age = $now - $generated
    $status = if ($generated -gt $now.AddHours($script:ToolPluginCatalogFutureSkewHours)) {
        'Future'
    } elseif ($age.TotalDays -ge $script:ToolPluginCatalogMaximumAgeDays) {
        'Stale'
    } elseif ($age.TotalDays -ge $script:ToolPluginCatalogWarningAgeDays) {
        'Warning'
    } else {
        'Fresh'
    }
    return [pscustomobject][ordered]@{
        Status = $status
        GeneratedAtUtc = $generated.ToString('o')
        AgeDays = [Math]::Round($age.TotalDays, 3)
        WarningAgeDays = $script:ToolPluginCatalogWarningAgeDays
        MaximumAgeDays = $script:ToolPluginCatalogMaximumAgeDays
        FutureSkewHours = $script:ToolPluginCatalogFutureSkewHours
        InstallationAllowed = [bool]($status -in @('Fresh','Warning'))
    }
}

function Test-ToolPluginCatalogHttpsUri {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [ValidateSet('Package','Signature')][string]$Kind = 'Package'
    )

    $raw = [string]$Value
    $uri = $null
    $expectedSuffix = if ($Kind -eq 'Signature') { '.plugin.json.p7s' } else { '.plugin.json' }
    $valid = [bool](-not [string]::IsNullOrWhiteSpace($raw) -and $raw.Length -le 2048 -and
        $raw -notmatch '[\x00-\x20\x7f\\]' -and
        $raw -notmatch '(?i)%00|%2f|%5c|%2e' -and
        [Uri]::TryCreate($raw, [UriKind]::Absolute, [ref]$uri))
    if ($valid) {
        $valid = [bool]($uri.Scheme.Equals('https', [StringComparison]::OrdinalIgnoreCase) -and
            -not $uri.IsLoopback -and
            $uri.HostNameType -eq [UriHostNameType]::Dns -and
            -not [string]::IsNullOrWhiteSpace($uri.DnsSafeHost) -and
            [string]::IsNullOrEmpty($uri.UserInfo) -and
            [string]::IsNullOrEmpty($uri.Query) -and
            [string]::IsNullOrEmpty($uri.Fragment) -and
            $uri.AbsolutePath.EndsWith($expectedSuffix, [StringComparison]::OrdinalIgnoreCase))
    }
    return [pscustomobject][ordered]@{
        Valid = $valid
        Value = $raw
        Normalized = if ($valid) { $uri.AbsoluteUri } else { '' }
        Kind = $Kind
    }
}

function Read-ToolPluginCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$SignaturePath = '',
        [AllowEmptyCollection()][string[]]$TrustedSignerCertificateSha256 = @(),
        [DateTimeOffset]$NowUtc = [DateTimeOffset]::UtcNow
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $catalog = $null
    $entries = New-Object System.Collections.Generic.List[object]
    $fullPath = ''
    $catalogSha256 = ''
    $resolvedSignaturePath = ''
    $signaturePresent = $false
    $signatureValid = $false
    $signatureStatus = 'NotPresent'
    $signerCertificateSha256 = ''
    $freshness = [pscustomobject][ordered]@{
        Status='Invalid'; GeneratedAtUtc=''; AgeDays=$null
        WarningAgeDays=$script:ToolPluginCatalogWarningAgeDays
        MaximumAgeDays=$script:ToolPluginCatalogMaximumAgeDays
        FutureSkewHours=$script:ToolPluginCatalogFutureSkewHours
        InstallationAllowed=$false
    }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        if (-not $fullPath.EndsWith('.plugin-catalog.json', [StringComparison]::OrdinalIgnoreCase)) {
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogExtensionInvalid')
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogFileMissing')
        }
        $info = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogFileReparse')
        }
        if ($info.Length -le 0 -or $info.Length -gt $script:ToolPluginCatalogMaximumBytes) {
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogFileSize')
        }
        $contentBytes = [IO.File]::ReadAllBytes($fullPath)
        $catalogSha256 = Get-ToolPluginSha256 -Path $fullPath

        $candidateSignaturePath = if (-not [string]::IsNullOrWhiteSpace($SignaturePath)) {
            [IO.Path]::GetFullPath($SignaturePath)
        } else {
            $fullPath + $script:ToolPluginSignatureSuffix
        }
        if (@($TrustedSignerCertificateSha256).Count -eq 0) {
            $signatureStatus = 'TrustedSignerRequired'
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogSignatureTrustRequired')
        }
        $signaturePresent = Test-Path -LiteralPath $candidateSignaturePath -PathType Leaf
        if (-not $signaturePresent) {
            $signatureStatus = 'Missing'
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogSignatureMissing')
        }
        $signatureInfo = Get-Item -LiteralPath $candidateSignaturePath -Force -ErrorAction Stop
        if (($signatureInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $signatureStatus = 'SignatureReparsePoint'
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogSignatureReparse')
        }
        if ($signatureInfo.Length -le 64 -or $signatureInfo.Length -gt $script:ToolPluginMaximumSignatureBytes) {
            $signatureStatus = 'SignatureSizeInvalid'
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogSignatureSizeInvalid')
        }
        $resolvedSignaturePath = [string]$signatureInfo.FullName
        $signatureResult = Test-ToolPluginDetachedSignature -ContentBytes $contentBytes `
            -SignatureBytes ([IO.File]::ReadAllBytes($resolvedSignaturePath)) `
            -TrustedSignerCertificateSha256 $TrustedSignerCertificateSha256
        $signatureValid = [bool]$signatureResult.Valid
        $signatureStatus = [string]$signatureResult.Status
        $signerCertificateSha256 = [string]$signatureResult.SignerCertificateSha256
        if (-not $signatureValid) {
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogSignatureInvalid' @($signatureStatus))
        }

        $utf8 = New-Object Text.UTF8Encoding -ArgumentList @($false, $true)
        $raw = $utf8.GetString($contentBytes)
        if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
        $document = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $document -or $document -isnot [pscustomobject]) {
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogJsonObjectRequired')
        }

        $rootFields = @('SchemaVersion','CatalogId','PublisherId','GeneratedAtUtc','Plugins')
        Test-ToolPluginObjectProperties -Object $document -Allowed $rootFields -Context 'PluginCatalog' -Errors $errors
        foreach ($field in @('SchemaVersion','CatalogId','PublisherId','GeneratedAtUtc')) {
            $property = $document.PSObject.Properties[$field]
            if (-not $property) {
                [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogFieldMissing' @($field)))
            } elseif ($property.Value -isnot [string]) {
                [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogFieldTypeInvalid' @($field)))
            }
        }
        if (-not $document.PSObject.Properties['Plugins']) {
            [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogFieldMissing' @('Plugins')))
        } elseif ($document.Plugins -isnot [Array]) {
            [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntriesArrayRequired'))
        }
        if ([string](Get-ToolPluginPropertyValue $document 'SchemaVersion' '') -ne $script:ToolPluginCatalogSchemaVersion) {
            [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogSchemaVersionInvalid' @($script:ToolPluginCatalogSchemaVersion)))
        }
        $catalogId = [string](Get-ToolPluginPropertyValue $document 'CatalogId' '')
        $publisherId = [string](Get-ToolPluginPropertyValue $document 'PublisherId' '')
        if ($catalogId -notmatch '^[a-z0-9][a-z0-9.-]{2,119}$') {
            [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogIdInvalid'))
        }
        if ($publisherId -notmatch '^[a-z0-9][a-z0-9.-]{2,79}$') {
            [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogPublisherIdInvalid'))
        }
        $freshness = Get-ToolPluginCatalogFreshness -Catalog $document -NowUtc $NowUtc
        if ($freshness.Status -eq 'Invalid') {
            [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogGeneratedAtInvalid'))
        }

        $pluginValues = @(if ($document.PSObject.Properties['Plugins'] -and $document.Plugins -is [Array]) { @($document.Plugins) })
        if ($pluginValues.Count -lt 1 -or $pluginValues.Count -gt $script:ToolPluginCatalogMaximumEntries) {
            [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntriesCount' @($script:ToolPluginCatalogMaximumEntries)))
        }
        $pluginIds = @{}
        $entryNumber = 0
        foreach ($entry in $pluginValues) {
            $entryNumber++
            if ($null -eq $entry -or $entry -isnot [pscustomobject]) {
                [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntryObjectInvalid' @($entryNumber)))
                continue
            }
            $entryFields = @('PluginId','Version','PackageUri','SignatureUri','PackageSha256')
            Test-ToolPluginObjectProperties -Object $entry -Allowed $entryFields -Context "PluginCatalogEntry#$entryNumber" -Errors $errors
            foreach ($field in $entryFields) {
                $property = $entry.PSObject.Properties[$field]
                if (-not $property) {
                    [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntryFieldMissing' @($entryNumber, $field)))
                } elseif ($property.Value -isnot [string]) {
                    [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntryFieldTypeInvalid' @($entryNumber, $field)))
                }
            }

            $pluginId = [string](Get-ToolPluginPropertyValue $entry 'PluginId' '')
            $versionText = [string](Get-ToolPluginPropertyValue $entry 'Version' '')
            $packageSha256 = ([string](Get-ToolPluginPropertyValue $entry 'PackageSha256' '')).ToUpperInvariant()
            if ($pluginId -notmatch '^[a-z0-9][a-z0-9.-]{2,79}$' -or $pluginIds.ContainsKey($pluginId)) {
                [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntryIdInvalid' @($entryNumber)))
            } else {
                $pluginIds[$pluginId] = $true
            }
            $parsedVersion = $null
            if ($versionText.Length -gt 32 -or $versionText -notmatch '^\d+(?:\.\d+){1,3}$' -or
                -not [Version]::TryParse($versionText, [ref]$parsedVersion)) {
                [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntryVersionInvalid' @($entryNumber)))
            }
            if ($packageSha256 -notmatch '^[0-9A-F]{64}$') {
                [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntrySha256Invalid' @($entryNumber)))
            }
            $packageUri = Test-ToolPluginCatalogHttpsUri -Value (Get-ToolPluginPropertyValue $entry 'PackageUri' '') -Kind Package
            $signatureUri = Test-ToolPluginCatalogHttpsUri -Value (Get-ToolPluginPropertyValue $entry 'SignatureUri' '') -Kind Signature
            if (-not $packageUri.Valid) {
                [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntryUriInvalid' @($entryNumber, 'PackageUri')))
            }
            if (-not $signatureUri.Valid) {
                [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntryUriInvalid' @($entryNumber, 'SignatureUri')))
            }
            if ($packageUri.Valid -and $signatureUri.Valid -and
                -not $signatureUri.Normalized.Equals(($packageUri.Normalized + '.p7s'), [StringComparison]::Ordinal)) {
                [void]$errors.Add((Get-ToolTextCurrent 'foundation.plugin.catalogEntrySignatureUriMismatch' @($entryNumber)))
            }
            [void]$entries.Add([pscustomobject][ordered]@{
                PluginId = $pluginId
                Version = $versionText
                PackageUri = [string]$packageUri.Normalized
                SignatureUri = [string]$signatureUri.Normalized
                PackageSha256 = $packageSha256
            })
        }
        $catalog = [pscustomobject][ordered]@{
            SchemaVersion = [string](Get-ToolPluginPropertyValue $document 'SchemaVersion' '')
            CatalogId = $catalogId
            PublisherId = $publisherId
            GeneratedAtUtc = [string]$freshness.GeneratedAtUtc
            Plugins = @($entries.ToArray())
        }
    } catch {
        [void]$errors.Add($_.Exception.Message)
    }

    $valid = [bool]($errors.Count -eq 0 -and $signatureValid)
    return [pscustomobject][ordered]@{
        Valid = $valid
        Path = $fullPath
        Sha256 = $catalogSha256
        Catalog = $catalog
        Entries = @($entries.ToArray())
        EntryCount = $entries.Count
        SignatureRequired = $true
        SignaturePresent = [bool]$signaturePresent
        SignatureValid = [bool]$signatureValid
        SignatureStatus = $signatureStatus
        SignaturePath = $resolvedSignaturePath
        SignerCertificateSha256 = $signerCertificateSha256
        Freshness = $freshness
        FreshnessStatus = [string]$freshness.Status
        InstallationAllowed = [bool]($valid -and $freshness.InstallationAllowed)
        ReadOnly = $true
        AutomaticDownloadAllowed = $false
        NetworkAccessPerformed = $false
        CodeExecutionAllowed = $false
        Errors = @($errors.ToArray())
    }
}

function Read-ToolPluginPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowOutsideProtectedDirectory,
        [string]$SignaturePath = '',
        [AllowEmptyCollection()][string[]]$TrustedSignerCertificateSha256 = @(),
        [switch]$RequireTrustedSignature
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $plugin = $null
    $hash = ""
    $fullPath = ""
    $resolvedSignaturePath = ""
    $signaturePresent = $false
    $signatureValid = $false
    $signatureStatus = 'NotPresent'
    $signerCertificateSha256 = ''
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        if (-not $fullPath.EndsWith(".plugin.json", [StringComparison]::OrdinalIgnoreCase)) {
            throw (Get-ToolTextCurrent "foundation.plugin.extensionInvalid")
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw (Get-ToolTextCurrent "foundation.plugin.fileMissing") }
        $info = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-ToolTextCurrent "foundation.plugin.fileReparse") }
        if ($info.Length -le 0 -or $info.Length -gt 524288) { throw (Get-ToolTextCurrent "foundation.plugin.fileSize") }
        if (-not $AllowOutsideProtectedDirectory) {
            $directoryState = Test-ToolPluginDirectory
            if (-not $directoryState.Valid) { throw ($directoryState.Errors -join "; ") }
            $expectedPrefix = $directoryState.Path.TrimEnd([char]92) + [char]92
            if (-not $fullPath.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw (Get-ToolTextCurrent "foundation.plugin.fileOutsideDirectory")
            }
        }
        $contentBytes = [IO.File]::ReadAllBytes($fullPath)
        $candidateSignaturePath = if (-not [string]::IsNullOrWhiteSpace($SignaturePath)) {
            [IO.Path]::GetFullPath($SignaturePath)
        } else {
            $fullPath + $script:ToolPluginSignatureSuffix
        }
        $signaturePresent = Test-Path -LiteralPath $candidateSignaturePath -PathType Leaf
        $signatureRequested = [bool]($RequireTrustedSignature -or $signaturePresent -or
            -not [string]::IsNullOrWhiteSpace($SignaturePath))
        if ($signatureRequested) {
            if (@($TrustedSignerCertificateSha256).Count -eq 0) {
                $signatureStatus = 'TrustedSignerRequired'
                throw (Get-ToolTextCurrent 'foundation.plugin.signatureTrustRequired')
            }
            if (-not $signaturePresent) {
                $signatureStatus = 'Missing'
                throw (Get-ToolTextCurrent 'foundation.plugin.signatureMissing')
            }
            $signatureInfo = Get-Item -LiteralPath $candidateSignaturePath -Force -ErrorAction Stop
            if (($signatureInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $signatureStatus = 'SignatureReparsePoint'
                throw (Get-ToolTextCurrent 'foundation.plugin.signatureReparse')
            }
            if ($signatureInfo.Length -le 64 -or $signatureInfo.Length -gt $script:ToolPluginMaximumSignatureBytes) {
                $signatureStatus = 'SignatureSizeInvalid'
                throw (Get-ToolTextCurrent 'foundation.plugin.signatureSizeInvalid')
            }
            $resolvedSignaturePath = [string]$signatureInfo.FullName
            $signatureResult = Test-ToolPluginDetachedSignature -ContentBytes $contentBytes `
                -SignatureBytes ([IO.File]::ReadAllBytes($resolvedSignaturePath)) `
                -TrustedSignerCertificateSha256 $TrustedSignerCertificateSha256
            $signatureValid = [bool]$signatureResult.Valid
            $signatureStatus = [string]$signatureResult.Status
            $signerCertificateSha256 = [string]$signatureResult.SignerCertificateSha256
            if (-not $signatureValid) { throw ('Detached plugin signature verification failed: ' + $signatureStatus) }
        }
        $utf8 = New-Object Text.UTF8Encoding -ArgumentList @($false, $true)
        $raw = $utf8.GetString($contentBytes)
        if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
        $plugin = $raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $plugin) { throw (Get-ToolTextCurrent "foundation.plugin.jsonEmpty") }
        Test-ToolPluginObjectProperties -Object $plugin -Allowed @(
            "SchemaVersion", "PluginId", "Name", "NameKey", "Version", "Publisher",
            "Description", "DescriptionKey", "MinimumToolVersion", "Enabled", "Rules"
        ) -Context "Plugin" -Errors $errors
        if ([string](Get-ToolPluginPropertyValue $plugin "SchemaVersion" "") -ne $script:ToolPluginSchemaVersion) {
            [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.schemaVersionInvalid" @($script:ToolPluginSchemaVersion)))
        }
        $pluginEnabledProperty = $plugin.PSObject.Properties["Enabled"]
        if ($pluginEnabledProperty -and $pluginEnabledProperty.Value -isnot [bool]) {
            [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.enabledBoolean"))
        }
        if ([string](Get-ToolPluginPropertyValue $plugin "PluginId" "") -notmatch '^[a-z0-9][a-z0-9.-]{2,79}$') {
            [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.idInvalid"))
        }
        foreach ($field in @("Version", "Publisher")) {
            $value = [string](Get-ToolPluginPropertyValue $plugin $field "")
            if ([string]::IsNullOrWhiteSpace($value) -or $value.Length -gt 160) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.fieldInvalid" @($field)))
            }
        }
        $pluginNameKey = [string](Get-ToolPluginPropertyValue $plugin "NameKey" "")
        $pluginNameKeyValid = Test-ToolPluginLocalizationKey -Key $pluginNameKey -Field "NameKey" -Errors $errors
        $pluginName = [string](Get-ToolPluginLocalizedPropertyValue -Object $plugin -TextProperty "Name" -KeyProperty "NameKey")
        if ([string]::IsNullOrWhiteSpace($pluginName) -or $pluginName.Length -gt 160) {
            [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.fieldInvalid" @("Name/NameKey")))
        } elseif ($pluginNameKeyValid) {
            $plugin | Add-Member -NotePropertyName Name -NotePropertyValue $pluginName -Force
        }
        $pluginDescriptionKey = [string](Get-ToolPluginPropertyValue $plugin "DescriptionKey" "")
        $pluginDescriptionKeyValid = Test-ToolPluginLocalizationKey -Key $pluginDescriptionKey -Field "DescriptionKey" -Errors $errors
        $pluginDescription = [string](Get-ToolPluginLocalizedPropertyValue -Object $plugin -TextProperty "Description" -KeyProperty "DescriptionKey")
        if ($pluginDescription.Length -gt 1200) {
            [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.fieldInvalid" @("Description/DescriptionKey")))
        } elseif ($pluginDescriptionKeyValid -and -not [string]::IsNullOrWhiteSpace($pluginDescriptionKey)) {
            $plugin | Add-Member -NotePropertyName Description -NotePropertyValue $pluginDescription -Force
        }
        $pluginVersion = $null
        if (-not [Version]::TryParse([string](Get-ToolPluginPropertyValue $plugin "Version" ""), [ref]$pluginVersion)) {
            [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.versionInvalid"))
        }
        $minimumVersion = $null
        $minimumToolVersionText = [string](Get-ToolPluginPropertyValue $plugin "MinimumToolVersion" "")
        if (-not [string]::IsNullOrWhiteSpace($minimumToolVersionText)) {
            if (-not [Version]::TryParse($minimumToolVersionText, [ref]$minimumVersion)) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.minimumVersionInvalid"))
            } elseif ($minimumVersion -gt [Version]$script:ToolPluginToolVersion) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.minimumVersionRequired" @($minimumVersion)))
            }
        }
        $rules = @(Get-ToolPluginPropertyValue $plugin "Rules" @())
        if ($rules.Count -lt 1 -or $rules.Count -gt 128) {
            [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.rulesCount"))
        }
        $ruleIds = @{}
        $ruleIndex = 0
        foreach ($rule in $rules) {
            $ruleIndex++
            Test-ToolPluginObjectProperties -Object $rule -Allowed @(
                "RuleId", "Type", "Condition", "Hive", "Path", "ValueName",
                "Expected", "Name", "Severity", "Message", "MessageKey",
                "Remediation", "RemediationKey", "Enabled"
            ) -Context "Rule #$ruleIndex" -Errors $errors
            $ruleId = [string](Get-ToolPluginPropertyValue $rule "RuleId" "")
            $ruleEnabledProperty = $rule.PSObject.Properties["Enabled"]
            if ($ruleEnabledProperty -and $ruleEnabledProperty.Value -isnot [bool]) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleEnabledBoolean" @($ruleIndex)))
            }
            if ($ruleId -notmatch '^[a-z0-9][a-z0-9._-]{2,79}$') {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleIdInvalid" @($ruleIndex)))
            } elseif ($ruleIds.ContainsKey($ruleId)) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleIdDuplicate" @($ruleId)))
            } else {
                $ruleIds[$ruleId] = $true
            }
            $type = [string](Get-ToolPluginPropertyValue $rule "Type" "")
            $condition = [string](Get-ToolPluginPropertyValue $rule "Condition" "")
            $allowedConditions = switch ($type) {
                "RegistryValue" { @("Exists", "Missing", "Equals", "NotEquals", "Contains", "Regex") }
                "File" { @("Exists", "Missing", "Sha256NotEquals", "AuthenticodeNotValid") }
                "Service" { @("Exists", "Missing", "StatusEquals", "StartModeEquals") }
                default { @() }
            }
            if ($type -notin @("RegistryValue", "File", "Service")) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleTypeUnsupported" @($ruleId, $type)))
            } elseif ($allowedConditions -notcontains $condition) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleConditionInvalid" @($ruleId, $type)))
            }
            if ([string](Get-ToolPluginPropertyValue $rule "Severity" "") -notin @("Info", "Low", "Medium", "High", "Critical")) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleSeverityInvalid" @($ruleId)))
            }
            $messageKey = [string](Get-ToolPluginPropertyValue $rule "MessageKey" "")
            $remediationKey = [string](Get-ToolPluginPropertyValue $rule "RemediationKey" "")
            $messageKeyValid = Test-ToolPluginLocalizationKey -Key $messageKey -Field "MessageKey" -Errors $errors
            $remediationKeyValid = Test-ToolPluginLocalizationKey -Key $remediationKey -Field "RemediationKey" -Errors $errors
            $messageText = [string](Get-ToolPluginLocalizedPropertyValue -Object $rule -TextProperty "Message" -KeyProperty "MessageKey")
            $remediationText = [string](Get-ToolPluginLocalizedPropertyValue -Object $rule -TextProperty "Remediation" -KeyProperty "RemediationKey")
            $expectedText = [string](Get-ToolPluginPropertyValue $rule "Expected" "")
            $pathText = [string](Get-ToolPluginPropertyValue $rule "Path" "")
            $nameText = [string](Get-ToolPluginPropertyValue $rule "Name" "")
            if ([string]::IsNullOrWhiteSpace($messageText) -or $messageText.Length -gt 800) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleMessageInvalid" @($ruleId)))
            }
            if ($remediationText.Length -gt 1200 -or $expectedText.Length -gt 512 -or
                $pathText.Length -gt 1024 -or $nameText.Length -gt 256) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleFieldTooLarge" @($ruleId)))
            }
            if ($messageKeyValid -and -not [string]::IsNullOrWhiteSpace($messageText)) {
                $rule | Add-Member -NotePropertyName Message -NotePropertyValue $messageText -Force
            }
            if ($remediationKeyValid -and -not [string]::IsNullOrWhiteSpace($remediationKey)) {
                $rule | Add-Member -NotePropertyName Remediation -NotePropertyValue $remediationText -Force
            }
            if ($type -eq "RegistryValue") {
                $hiveText = [string](Get-ToolPluginPropertyValue $rule "Hive" "")
                if ($hiveText -notin @("HKLM", "HKCU") -or [string]::IsNullOrWhiteSpace($pathText) -or
                    $pathText -notmatch '^[^\\/:*?"<>|\x00-\x1F]+(?:\\[^\\/:*?"<>|\x00-\x1F]+)*$' -or
                    @($pathText -split '\\' | Where-Object { $_ -in @(".", "..") }).Count -gt 0 -or
                    [string]::IsNullOrWhiteSpace([string](Get-ToolPluginPropertyValue $rule "ValueName" ""))) {
                    [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleRegistryUnsafe" @($ruleId)))
                }
            }
            if ($type -eq "File" -and [string]::IsNullOrWhiteSpace($pathText)) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.rulePathMissing" @($ruleId)))
            }
            if ($type -eq "Service" -and $nameText -notmatch '^[A-Za-z0-9_.-]{1,256}$') {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleServiceNameInvalid" @($ruleId)))
            }
            if ($condition -eq "Sha256NotEquals" -and $expectedText -notmatch '^[A-Fa-f0-9]{64}$') {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleSha256Invalid" @($ruleId)))
            }
            if ($condition -eq "Contains" -and [string]::IsNullOrWhiteSpace($expectedText)) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleContainsExpectedMissing" @($ruleId)))
            }
            if ($condition -eq "StatusEquals" -and $expectedText -notin @("Running", "Stopped", "Paused", "Start Pending", "Stop Pending", "Continue Pending", "Pause Pending")) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleServiceStatusInvalid" @($ruleId)))
            }
            if ($condition -eq "StartModeEquals" -and $expectedText -notin @("Auto", "Manual", "Disabled")) {
                [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleStartModeInvalid" @($ruleId)))
            }
            if ($condition -eq "Regex") {
                try {
                    if ($expectedText.Length -gt 256) { throw (Get-ToolTextCurrent "foundation.plugin.regexTooLong") }
                    [void](New-Object Text.RegularExpressions.Regex(
                        $expectedText,
                        [Text.RegularExpressions.RegexOptions]::IgnoreCase,
                        [TimeSpan]::FromMilliseconds(250)))
                } catch {
                    [void]$errors.Add((Get-ToolTextCurrent "foundation.plugin.ruleRegexInvalid" @($ruleId, $_.Exception.Message)))
                }
            }
        }
        $hash = Get-ToolPluginSha256 -Path $fullPath
    } catch {
        [void]$errors.Add($_.Exception.Message)
    }
    return [pscustomobject][ordered]@{
        Valid = [bool]($errors.Count -eq 0)
        Path = $fullPath
        Sha256 = $hash
        Plugin = $plugin
        SignatureRequired = [bool]$RequireTrustedSignature
        SignaturePresent = [bool]$signaturePresent
        SignatureValid = [bool]$signatureValid
        SignatureStatus = $signatureStatus
        SignaturePath = $resolvedSignaturePath
        SignerCertificateSha256 = $signerCertificateSha256
        Errors = @($errors.ToArray())
    }
}

function Get-ToolPluginSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Assert-ToolPluginPathWithoutReparsePoint {
    param(
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )

    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([char]92)
    $rootPrefix = $root + [char]92
    $cursor = [IO.Path]::GetFullPath($FullPath).TrimEnd([char]92)
    while ($true) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw (Get-ToolTextCurrent "foundation.plugin.pathReparse" @($cursor))
            }
        }
        if ($cursor.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ([string]::IsNullOrWhiteSpace($parent) -or
            (-not $parent.Equals($root, [StringComparison]::OrdinalIgnoreCase) -and
             -not $parent.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase))) {
            throw (Get-ToolTextCurrent "foundation.plugin.pathChainInvalid")
        }
        $cursor = $parent.TrimEnd([char]92)
    }
}

function Resolve-ToolPluginSystemFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not [IO.Path]::IsPathRooted($expanded) -or $expanded.StartsWith("\\", [StringComparison]::Ordinal)) {
        throw (Get-ToolTextCurrent "foundation.plugin.absoluteLocalPathRequired")
    }
    $fullPath = [IO.Path]::GetFullPath($expanded)
    $allowedRoots = @(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows),
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramW6432,
        [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
        [IO.Path]::GetFullPath([string]$_).TrimEnd([char]92) + [char]92
    } | Select-Object -Unique
    foreach ($root in $allowedRoots) {
        if ($fullPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            Assert-ToolPluginPathWithoutReparsePoint -FullPath $fullPath -AllowedRoot $root
            return $fullPath
        }
    }
    throw (Get-ToolTextCurrent "foundation.plugin.pathOutsideAllowedRoots")
}

function Test-ToolPluginTextCondition {
    param(
        [AllowNull()][object]$Observed,
        [Parameter(Mandatory = $true)][string]$Condition,
        [string]$Expected = ""
    )

    $text = if ($null -eq $Observed) { "" } else { [string]$Observed }
    switch ($Condition) {
        "Equals" { return $text.Equals($Expected, [StringComparison]::OrdinalIgnoreCase) }
        "NotEquals" { return -not $text.Equals($Expected, [StringComparison]::OrdinalIgnoreCase) }
        "Contains" { return ($text.IndexOf($Expected, [StringComparison]::OrdinalIgnoreCase) -ge 0) }
        "Regex" {
            $regex = New-Object Text.RegularExpressions.Regex(
                $Expected,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase,
                [TimeSpan]::FromMilliseconds(250))
            return $regex.IsMatch($text)
        }
        default { return $false }
    }
}

function Invoke-ToolPluginRule {
    param(
        [Parameter(Mandatory = $true)][object]$Plugin,
        [Parameter(Mandatory = $true)][object]$Rule
    )

    $triggered = $false
    $observed = ""
    $errorText = ""
    try {
        $condition = [string](Get-ToolPluginPropertyValue $Rule "Condition" "")
        switch ([string](Get-ToolPluginPropertyValue $Rule "Type" "")) {
            "RegistryValue" {
                $root = if ([string](Get-ToolPluginPropertyValue $Rule "Hive" "") -eq "HKLM") { "Registry::HKEY_LOCAL_MACHINE" } else { "Registry::HKEY_CURRENT_USER" }
                $registrySubPath = [string](Get-ToolPluginPropertyValue $Rule "Path" "")
                $registryPath = $root + [char]92 + $registrySubPath
                $valueName = [string](Get-ToolPluginPropertyValue $Rule "ValueName" "")
                $keyExists = Test-Path -LiteralPath $registryPath -PathType Container
                $property = $null
                if ($keyExists) {
                    try { $property = Get-ItemProperty -LiteralPath $registryPath -Name $valueName -ErrorAction Stop } catch {}
                }
                $propertyValue = if ($property -and $property.PSObject.Properties[$valueName]) { $property.PSObject.Properties[$valueName].Value } else { $null }
                $valueExists = [bool]($null -ne $propertyValue)
                $observed = if ($valueExists) { ConvertTo-ToolPluginSafeText $propertyValue } else { "<missing>" }
                if ($condition -eq "Exists") { $triggered = $valueExists }
                elseif ($condition -eq "Missing") { $triggered = -not $valueExists }
                else { $triggered = $valueExists -and (Test-ToolPluginTextCondition -Observed $propertyValue -Condition $condition -Expected ([string](Get-ToolPluginPropertyValue $Rule "Expected" ""))) }
            }
            "File" {
                $filePath = Resolve-ToolPluginSystemFile -Path ([string](Get-ToolPluginPropertyValue $Rule "Path" ""))
                $exists = Test-Path -LiteralPath $filePath -PathType Leaf
                $observed = if ($exists) { "Present: $filePath" } else { "Missing: $filePath" }
                if ($condition -eq "Exists") { $triggered = $exists }
                elseif ($condition -eq "Missing") { $triggered = -not $exists }
                elseif ($condition -eq "Sha256NotEquals") {
                    $actualHash = if ($exists) { Get-ToolPluginSha256 -Path $filePath } else { "" }
                    $observed = if ($exists) { "SHA256=$actualHash" } else { "<missing>" }
                    $triggered = $exists -and -not $actualHash.Equals(([string](Get-ToolPluginPropertyValue $Rule "Expected" "")).Trim(), [StringComparison]::OrdinalIgnoreCase)
                } elseif ($condition -eq "AuthenticodeNotValid") {
                    $signature = if ($exists) { Get-AuthenticodeSignature -LiteralPath $filePath } else { $null }
                    $signer = if ($signature -and $signature.SignerCertificate) { ConvertTo-ToolPluginSafeText $signature.SignerCertificate.Subject } else { "<none>" }
                    $observed = if ($signature) { "Authenticode=$([string]$signature.Status); Signer=$signer" } else { "<missing>" }
                    $triggered = $exists -and [string]$signature.Status -ne "Valid"
                }
            }
            "Service" {
                $serviceName = [string](Get-ToolPluginPropertyValue $Rule "Name" "")
                $service = Get-WmiObject -Class Win32_Service -Filter ("Name='" + $serviceName.Replace("'", "''") + "'") -ErrorAction SilentlyContinue | Select-Object -First 1
                $exists = [bool]($null -ne $service)
                $observed = if ($service) { "State=$($service.State); StartMode=$($service.StartMode)" } else { "<missing>" }
                if ($condition -eq "Exists") { $triggered = $exists }
                elseif ($condition -eq "Missing") { $triggered = -not $exists }
                elseif ($condition -eq "StatusEquals") { $triggered = $exists -and ([string]$service.State).Equals([string](Get-ToolPluginPropertyValue $Rule "Expected" ""), [StringComparison]::OrdinalIgnoreCase) }
                elseif ($condition -eq "StartModeEquals") { $triggered = $exists -and ([string]$service.StartMode).Equals([string](Get-ToolPluginPropertyValue $Rule "Expected" ""), [StringComparison]::OrdinalIgnoreCase) }
            }
        }
    } catch {
        $errorText = ConvertTo-ToolPluginSafeText $_.Exception.Message 800
    }
    return [pscustomobject][ordered]@{
        PluginId = [string](Get-ToolPluginPropertyValue $Plugin "PluginId" "")
        PluginName = [string](Get-ToolPluginPropertyValue $Plugin "Name" "")
        RuleId = [string](Get-ToolPluginPropertyValue $Rule "RuleId" "")
        RuleType = [string](Get-ToolPluginPropertyValue $Rule "Type" "")
        Triggered = [bool]$triggered
        Severity = [string](Get-ToolPluginPropertyValue $Rule "Severity" "")
        Message = ConvertTo-ToolPluginSafeText (Get-ToolPluginPropertyValue $Rule "Message" "") 800
        Remediation = ConvertTo-ToolPluginSafeText (Get-ToolPluginPropertyValue $Rule "Remediation" "") 1200
        Observed = ConvertTo-ToolPluginSafeText $observed 800
        Error = $errorText
    }
}

function Invoke-ToolPluginAudit {
    param(
        [string]$PluginDirectory = (Get-ToolPluginDirectory),
        [AllowEmptyCollection()][string[]]$TrustedSignerCertificateSha256 = @(),
        [switch]$RequireTrustedSignature
    )

    $directoryState = Test-ToolPluginDirectory -Path $PluginDirectory
    $plugins = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]
    $invalid = New-Object System.Collections.Generic.List[object]
    if (-not $directoryState.Valid) {
        return [pscustomobject][ordered]@{
            SchemaVersion = $script:ToolPluginSchemaVersion
            EngineVersion = $script:ToolPluginEngineVersion
            Directory = $directoryState
            PluginCount = 0
            EnabledPluginCount = 0
            InvalidPluginCount = 0
            EvaluatedRuleCount = 0
            TriggeredFindingCount = 0
            HighOrCriticalCount = 0
            Plugins = @()
            Findings = @()
            InvalidPlugins = @()
            Error = ($directoryState.Errors -join "; ")
        }
    }
    $files = @(Get-ChildItem -LiteralPath $directoryState.Path -Filter "*.plugin.json" -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 32)
    $evaluatedRuleCount = 0
    $enabledCount = 0
    foreach ($file in $files) {
        $isEmbeddedBuiltIn = [bool]($directoryState.Protected -and
            [string]$file.Name -eq 'thanhviet.builtin.windows-office-trust.plugin.json')
        $package = Read-ToolPluginPackage -Path $file.FullName -AllowOutsideProtectedDirectory `
            -TrustedSignerCertificateSha256 $TrustedSignerCertificateSha256 `
            -RequireTrustedSignature:([bool]($RequireTrustedSignature -and -not $isEmbeddedBuiltIn))
        if (-not $package.Valid) {
            [void]$invalid.Add([pscustomobject][ordered]@{
                File=$file.Name; SignatureStatus=[string]$package.SignatureStatus; Errors=@($package.Errors)
            })
            continue
        }
        $plugin = $package.Plugin
        $enabled = [bool]($null -eq $plugin.PSObject.Properties["Enabled"] -or [bool]$plugin.Enabled)
        [void]$plugins.Add([pscustomobject][ordered]@{
            PluginId = [string]$plugin.PluginId
            Name = [string]$plugin.Name
            Version = [string]$plugin.Version
            Publisher = [string]$plugin.Publisher
            Enabled = $enabled
            RuleCount = @($plugin.Rules).Count
            Sha256 = $package.Sha256
            SignatureStatus = [string]$package.SignatureStatus
            SignerCertificateSha256 = [string]$package.SignerCertificateSha256
            Trust = if ($package.SignatureValid) { "SignedTrustedPublisher" } elseif ($directoryState.Protected) { "ProtectedAdminDirectory" } else { "SourceMode" }
        })
        if (-not $enabled) { continue }
        $enabledCount++
        foreach ($rule in @($plugin.Rules)) {
            if ($rule.PSObject.Properties["Enabled"] -and -not [bool]$rule.Enabled) { continue }
            $evaluatedRuleCount++
            $result = Invoke-ToolPluginRule -Plugin $plugin -Rule $rule
            if ($result.Triggered -or -not [string]::IsNullOrWhiteSpace($result.Error)) { [void]$findings.Add($result) }
        }
    }
    $findingArray = @($findings.ToArray())
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolPluginSchemaVersion
        EngineVersion = $script:ToolPluginEngineVersion
        Directory = $directoryState
        PluginCount = $plugins.Count
        EnabledPluginCount = $enabledCount
        InvalidPluginCount = $invalid.Count
        EvaluatedRuleCount = $evaluatedRuleCount
        TriggeredFindingCount = @($findingArray | Where-Object Triggered).Count
        HighOrCriticalCount = @($findingArray | Where-Object { $_.Triggered -and $_.Severity -in @("High", "Critical") }).Count
        Plugins = @($plugins.ToArray())
        Findings = $findingArray
        InvalidPlugins = @($invalid.ToArray())
        Error = ""
    }
}

function Install-ToolPluginPackage {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [string]$PluginDirectory = (Get-ToolPluginDirectory),
        [switch]$Force,
        [string]$SignaturePath = '',
        [AllowEmptyCollection()][string[]]$TrustedSignerCertificateSha256 = @(),
        [switch]$RequireTrustedSignature,
        [string]$ExpectedSha256 = ''
    )

    $directoryState = Test-ToolPluginDirectory -Path $PluginDirectory
    if (-not $directoryState.Valid) { throw ($directoryState.Errors -join "; ") }
    $package = Read-ToolPluginPackage -Path $SourcePath -AllowOutsideProtectedDirectory `
        -SignaturePath $SignaturePath -TrustedSignerCertificateSha256 $TrustedSignerCertificateSha256 `
        -RequireTrustedSignature:$RequireTrustedSignature
    if (-not $package.Valid) { throw ($package.Errors -join "; ") }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        $expectedHash = ([string]$ExpectedSha256).Trim().ToUpperInvariant()
        if ($expectedHash -notmatch '^[0-9A-F]{64}$' -or
            -not $expectedHash.Equals(([string]$package.Sha256).ToUpperInvariant(), [StringComparison]::Ordinal)) {
            throw (Get-ToolTextCurrent 'foundation.plugin.catalogPackageHashMismatch')
        }
    }
    $plugin = $package.Plugin
    $destinationName = "$([string]$plugin.PluginId).plugin.json"
    $destination = Join-Path $directoryState.Path $destinationName
    $destinationSignature = $destination + $script:ToolPluginSignatureSuffix
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        if (-not $Force) { throw (Get-ToolTextCurrent "foundation.plugin.alreadyExists" @($plugin.PluginId)) }
        $existing = Get-Item -LiteralPath $destination -Force
        if (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-ToolTextCurrent "foundation.plugin.destinationReparse") }
    }
    if (Test-Path -LiteralPath $destinationSignature -PathType Leaf) {
        $existingSignature = Get-Item -LiteralPath $destinationSignature -Force
        if (($existingSignature.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-ToolTextCurrent 'foundation.plugin.destinationSignatureReparse') }
    }
    $transactionId = [Guid]::NewGuid().ToString("N")
    $temporary = Join-Path $directoryState.Path "$([string]$plugin.PluginId).install-$transactionId.plugin.json"
    $backup = Join-Path $directoryState.Path "$([string]$plugin.PluginId).backup-$transactionId.plugin.json"
    $temporarySignature = $temporary + $script:ToolPluginSignatureSuffix
    $backupSignature = $backup + $script:ToolPluginSignatureSuffix
    $destinationCreated = $false
    $destinationSignatureCreated = $false
    try {
        [IO.File]::Copy($package.Path, $temporary, $false)
        if ($package.SignatureValid) { [IO.File]::Copy($package.SignaturePath, $temporarySignature, $false) }
        $staged = Read-ToolPluginPackage -Path $temporary -AllowOutsideProtectedDirectory `
            -SignaturePath $(if ($package.SignatureValid) {$temporarySignature} else {''}) `
            -TrustedSignerCertificateSha256 $TrustedSignerCertificateSha256 `
            -RequireTrustedSignature:$RequireTrustedSignature
        if (-not $staged.Valid -or -not $staged.Sha256.Equals($package.Sha256, [StringComparison]::OrdinalIgnoreCase)) {
            throw (Get-ToolTextCurrent "foundation.plugin.stagedVerificationFailed")
        }
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            [IO.File]::Replace($temporary, $destination, $backup, $true)
        } else {
            [IO.File]::Move($temporary, $destination)
            $destinationCreated = $true
        }
        if ($package.SignatureValid) {
            if (Test-Path -LiteralPath $destinationSignature -PathType Leaf) {
                [IO.File]::Replace($temporarySignature, $destinationSignature, $backupSignature, $true)
            } else {
                [IO.File]::Move($temporarySignature, $destinationSignature)
                $destinationSignatureCreated = $true
            }
        } elseif (Test-Path -LiteralPath $destinationSignature -PathType Leaf) {
            [IO.File]::Move($destinationSignature, $backupSignature)
        }
        $installed = Read-ToolPluginPackage -Path $destination -AllowOutsideProtectedDirectory `
            -SignaturePath $(if ($package.SignatureValid) {$destinationSignature} else {''}) `
            -TrustedSignerCertificateSha256 $TrustedSignerCertificateSha256 `
            -RequireTrustedSignature:$RequireTrustedSignature
        if (-not $installed.Valid -or -not $installed.Sha256.Equals($package.Sha256, [StringComparison]::OrdinalIgnoreCase)) {
            throw (Get-ToolTextCurrent "foundation.plugin.installedVerificationFailed")
        }
    } catch {
        if (Test-Path -LiteralPath $backupSignature -PathType Leaf) {
            if (Test-Path -LiteralPath $destinationSignature -PathType Leaf) {
                [IO.File]::Replace($backupSignature, $destinationSignature, $null, $true)
            } else {
                [IO.File]::Move($backupSignature, $destinationSignature)
            }
        } elseif ($destinationSignatureCreated -and (Test-Path -LiteralPath $destinationSignature -PathType Leaf)) {
            Remove-Item -LiteralPath $destinationSignature -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                [IO.File]::Replace($backup, $destination, $null, $true)
            } else {
                [IO.File]::Move($backup, $destination)
            }
        } elseif ($destinationCreated -and (Test-Path -LiteralPath $destination -PathType Leaf)) {
            Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        }
        throw
    } finally {
        foreach ($cleanupPath in @($temporary, $backup,$temporarySignature,$backupSignature)) {
            if (Test-Path -LiteralPath $cleanupPath -PathType Leaf) {
                Remove-Item -LiteralPath $cleanupPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    return [pscustomobject][ordered]@{
        Installed = $true
        PluginId = [string]$plugin.PluginId
        Name = [string]$plugin.Name
        Version = [string]$plugin.Version
        Publisher = [string]$plugin.Publisher
        Path = $destination
        Sha256 = $installed.Sha256
        SignatureStatus = [string]$installed.SignatureStatus
        SignaturePath = [string]$installed.SignaturePath
        SignerCertificateSha256 = [string]$installed.SignerCertificateSha256
        Trust = if ($installed.SignatureValid) { "SignedTrustedPublisher" } elseif ($directoryState.Protected) { "ProtectedAdminDirectory" } else { "SourceMode" }
    }
}

function Install-ToolPluginPackageFromCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [string]$CatalogSignaturePath = '',
        [Parameter(Mandatory = $true)][string]$PluginId,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [string]$PluginSignaturePath = '',
        [string]$PluginDirectory = (Get-ToolPluginDirectory),
        [AllowEmptyCollection()][string[]]$TrustedSignerCertificateSha256 = @(),
        [switch]$Force,
        [DateTimeOffset]$NowUtc = [DateTimeOffset]::UtcNow
    )

    $catalogResult = Read-ToolPluginCatalog -Path $CatalogPath -SignaturePath $CatalogSignaturePath `
        -TrustedSignerCertificateSha256 $TrustedSignerCertificateSha256 -NowUtc $NowUtc
    if (-not $catalogResult.Valid) {
        throw (Get-ToolTextCurrent 'foundation.plugin.catalogInstallInvalid' @(($catalogResult.Errors -join '; ')))
    }
    if (-not $catalogResult.InstallationAllowed) {
        throw (Get-ToolTextCurrent 'foundation.plugin.catalogInstallBlocked' @($catalogResult.FreshnessStatus))
    }
    $normalizedPluginId = ([string]$PluginId).Trim().ToLowerInvariant()
    $matchingEntries = @($catalogResult.Entries | Where-Object {
        [string]::Equals([string]$_.PluginId, $normalizedPluginId, [StringComparison]::Ordinal)
    })
    if ($matchingEntries.Count -ne 1) {
        throw (Get-ToolTextCurrent 'foundation.plugin.catalogEntryNotFound' @($normalizedPluginId))
    }
    $entry = $matchingEntries[0]
    $sourceFullPath = [IO.Path]::GetFullPath($SourcePath)
    if (-not (Test-Path -LiteralPath $sourceFullPath -PathType Leaf)) {
        throw (Get-ToolTextCurrent 'foundation.plugin.fileMissing')
    }
    $actualSha256 = (Get-ToolPluginSha256 -Path $sourceFullPath).ToUpperInvariant()
    if (-not $actualSha256.Equals([string]$entry.PackageSha256, [StringComparison]::Ordinal)) {
        throw (Get-ToolTextCurrent 'foundation.plugin.catalogPackageHashMismatch')
    }

    # A catalog install is deliberately stricter than a direct source-mode install:
    # the same explicitly pinned certificate must sign both the catalog and package.
    $catalogSigner = [string]$catalogResult.SignerCertificateSha256
    $package = Read-ToolPluginPackage -Path $sourceFullPath -AllowOutsideProtectedDirectory `
        -SignaturePath $PluginSignaturePath -TrustedSignerCertificateSha256 @($catalogSigner) `
        -RequireTrustedSignature
    if (-not $package.Valid) { throw ($package.Errors -join '; ') }
    if (-not ([string]$package.Sha256).ToUpperInvariant().Equals([string]$entry.PackageSha256, [StringComparison]::Ordinal)) {
        throw (Get-ToolTextCurrent 'foundation.plugin.catalogPackageHashMismatch')
    }
    if (-not [string]::Equals([string]$package.Plugin.PluginId, [string]$entry.PluginId, [StringComparison]::Ordinal) -or
        -not [string]::Equals([string]$package.Plugin.Version, [string]$entry.Version, [StringComparison]::Ordinal)) {
        throw (Get-ToolTextCurrent 'foundation.plugin.catalogPackageIdentityMismatch')
    }

    $result = Install-ToolPluginPackage -SourcePath $sourceFullPath -PluginDirectory $PluginDirectory `
        -Force:$Force -SignaturePath $PluginSignaturePath `
        -TrustedSignerCertificateSha256 @($catalogSigner) -RequireTrustedSignature `
        -ExpectedSha256 ([string]$entry.PackageSha256)
    $result | Add-Member -NotePropertyName CatalogId -NotePropertyValue ([string]$catalogResult.Catalog.CatalogId) -Force
    $result | Add-Member -NotePropertyName CatalogSha256 -NotePropertyValue ([string]$catalogResult.Sha256) -Force
    $result | Add-Member -NotePropertyName CatalogFreshnessStatus -NotePropertyValue ([string]$catalogResult.FreshnessStatus) -Force
    $result | Add-Member -NotePropertyName CatalogSignerCertificateSha256 -NotePropertyValue $catalogSigner -Force
    $result | Add-Member -NotePropertyName NetworkAccessPerformed -NotePropertyValue $false -Force
    return $result
}
