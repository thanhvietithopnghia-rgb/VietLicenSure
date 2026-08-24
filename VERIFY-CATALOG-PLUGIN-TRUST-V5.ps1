$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Tool-SoftwareInventory.ps1')
. (Join-Path $PSScriptRoot 'Tool-PluginEngine.ps1')

function Assert-TrustVerification {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-DetachedCmsSignature {
    param(
        [Parameter(Mandatory = $true)][byte[]]$ContentBytes,
        [Parameter(Mandatory = $true)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $contentInfo = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$ContentBytes)
    $signedCms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($contentInfo, $true)
    $cmsSigner = New-Object Security.Cryptography.Pkcs.CmsSigner -ArgumentList (,$Certificate)
    $cmsSigner.DigestAlgorithm = New-Object Security.Cryptography.Oid -ArgumentList '2.16.840.1.101.3.4.2.1'
    $cmsSigner.IncludeOption = [Security.Cryptography.X509Certificates.X509IncludeOption]::EndCertOnly
    $signedCms.ComputeSignature($cmsSigner)
    return ,$signedCms.Encode()
}

function ConvertTo-VerificationUtcText {
    param([Parameter(Mandatory = $true)][DateTimeOffset]$Value)
    return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [Globalization.CultureInfo]::InvariantCulture)
}

function Write-SignedPluginCatalogFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Catalog,
        [Parameter(Mandatory = $true)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    $encoding = New-Object Text.UTF8Encoding -ArgumentList @($false)
    [IO.File]::WriteAllText($Path, ($Catalog | ConvertTo-Json -Depth 16), $encoding)
    [IO.File]::WriteAllBytes(($Path + '.p7s'), (New-DetachedCmsSignature -ContentBytes ([IO.File]::ReadAllBytes($Path)) -Certificate $Certificate))
}

function Assert-TrustVerificationThrows {
    param([Parameter(Mandatory = $true)][scriptblock]$Action, [Parameter(Mandatory = $true)][string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert-TrustVerification $threw $Message
}

$now = [DateTimeOffset]::Parse('2026-08-24T00:00:00Z', [Globalization.CultureInfo]::InvariantCulture)
$freshnessCases = @(
    @{ Generated=$now.AddDays(-29.999); Status='Fresh'; Allowed=$true },
    @{ Generated=$now.AddDays(-30); Status='Warning'; Allowed=$true },
    @{ Generated=$now.AddDays(-44.999); Status='Warning'; Allowed=$true },
    @{ Generated=$now.AddDays(-45); Status='Stale'; Allowed=$false },
    @{ Generated=$now.AddHours(24); Status='Fresh'; Allowed=$true },
    @{ Generated=$now.AddHours(24).AddSeconds(1); Status='Future'; Allowed=$false }
)
foreach ($case in $freshnessCases) {
    $catalogFixture = [pscustomobject]@{ GeneratedAtUtc=$case.Generated.ToString('o') }
    $freshness = Get-ToolSoftwareCatalogFreshness -Catalog $catalogFixture -NowUtc $now
    Assert-TrustVerification ($freshness.Status -eq $case.Status) "Unexpected freshness status at boundary: $($freshness.Status), expected $($case.Status)."
    Assert-TrustVerification ([bool]$freshness.DecisiveEvidenceAllowed -eq [bool]$case.Allowed) 'Unexpected decisive-evidence freshness policy.'
    Assert-TrustVerification ($freshness.WarningAgeDays -eq 30 -and $freshness.MaximumAgeDays -eq 45 -and $freshness.FutureSkewHours -eq 24) 'Freshness policy metadata changed unexpectedly.'

    $pluginCatalogFreshness = Get-ToolPluginCatalogFreshness -Catalog ([pscustomobject]@{
        GeneratedAtUtc = ConvertTo-VerificationUtcText $case.Generated
    }) -NowUtc $now
    Assert-TrustVerification ($pluginCatalogFreshness.Status -eq $case.Status) "Unexpected plugin catalog freshness status: $($pluginCatalogFreshness.Status), expected $($case.Status)."
    Assert-TrustVerification ([bool]$pluginCatalogFreshness.InstallationAllowed -eq [bool]$case.Allowed) 'Unexpected plugin catalog installation freshness policy.'
}
$invalidFreshness = Get-ToolSoftwareCatalogFreshness -Catalog ([pscustomobject]@{ GeneratedAtUtc='invalid' }) -NowUtc $now
Assert-TrustVerification ($invalidFreshness.Status -eq 'Invalid' -and -not $invalidFreshness.DecisiveEvidenceAllowed) 'An invalid catalog timestamp was not forced to read-only.'
$invalidPluginCatalogFreshness = Get-ToolPluginCatalogFreshness -Catalog ([pscustomobject]@{ GeneratedAtUtc='invalid' }) -NowUtc $now
Assert-TrustVerification ($invalidPluginCatalogFreshness.Status -eq 'Invalid' -and -not $invalidPluginCatalogFreshness.InstallationAllowed) 'An invalid plugin catalog timestamp was not forced to read-only.'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('tool-catalog-plugin-trust-' + [guid]::NewGuid().ToString('N'))
$certificates = New-Object System.Collections.Generic.List[object]
try {
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)

    $catalogObject = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'software-license-catalog-v1.0.json') -Raw | ConvertFrom-Json
    $catalogObject.GeneratedAtUtc = $now.AddDays(-45).ToString('o')
    $staleCatalogPath = Join-Path $tempRoot 'stale-catalog.json'
    [IO.File]::WriteAllText($staleCatalogPath, ($catalogObject | ConvertTo-Json -Depth 64), (New-Object Text.UTF8Encoding -ArgumentList @($false)))
    $staleCatalog = Import-ToolSoftwareCatalogFile -Path $staleCatalogPath -Source 'UserProvidedReadOnly'
    Assert-TrustVerification ($null -ne $staleCatalog) 'A structurally valid stale catalog was rejected instead of loading read-only.'
    Assert-TrustVerification ($staleCatalog.CatalogFreshnessStatus -eq 'Stale' -and -not $staleCatalog.CatalogFreshForDecisiveEvidence) 'Stale import metadata is not fail-closed.'
    Assert-TrustVerification (-not (Test-ToolSoftwareCatalogTrustedForDecisiveEvidence -Catalog $staleCatalog)) 'A stale catalog was trusted for decisive evidence.'

    $plugin = [ordered]@{
        SchemaVersion='1.0'; PluginId='verification.signed-plugin'; Name='Signed verification plugin'
        Version='1.0.0'; Publisher='Verification'; Description='Read-only signature fixture'
        MinimumToolVersion='4.9'; Enabled=$true
        Rules=@([ordered]@{
            RuleId='verification.registry'; Type='RegistryValue'; Condition='Exists'; Hive='HKCU'
            Path='Software\Verification'; ValueName='Enabled'; Severity='Info'
            Message='Verification fixture'; Remediation='No action'; Enabled=$true
        })
    }
    $pluginPath = Join-Path $tempRoot 'verification.signed-plugin.plugin.json'
    $legacyPluginPath = Join-Path $tempRoot 'verification.legacy-plugin.plugin.json'
    $utf8 = New-Object Text.UTF8Encoding -ArgumentList @($false)
    $pluginJson = [pscustomobject]$plugin | ConvertTo-Json -Depth 16
    [IO.File]::WriteAllText($pluginPath, $pluginJson, $utf8)
    $legacyPlugin = $pluginJson.Replace('verification.signed-plugin', 'verification.legacy-plugin')
    [IO.File]::WriteAllText($legacyPluginPath, $legacyPlugin, $utf8)
    $pluginBytes = [IO.File]::ReadAllBytes($pluginPath)

    $certificateA = New-SelfSignedCertificate -Type CodeSigningCert -Subject ('CN=Tool Plugin Verification A ' + [guid]::NewGuid().ToString('N')) `
        -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
        -NotBefore (Get-Date).AddMinutes(-5) -NotAfter (Get-Date).AddDays(1)
    $certificateB = New-SelfSignedCertificate -Type CodeSigningCert -Subject ('CN=Tool Plugin Verification B ' + [guid]::NewGuid().ToString('N')) `
        -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
        -NotBefore (Get-Date).AddMinutes(-5) -NotAfter (Get-Date).AddDays(1)
    $certificates.Add($certificateA)
    $certificates.Add($certificateB)
    $fingerprintA = Get-ToolPluginCertificateSha256 -Certificate $certificateA
    $signatureA = New-DetachedCmsSignature -ContentBytes $pluginBytes -Certificate $certificateA
    $signatureB = New-DetachedCmsSignature -ContentBytes $pluginBytes -Certificate $certificateB
    $signaturePath = $pluginPath + '.p7s'
    $wrongSignerPath = Join-Path $tempRoot 'wrong-signer.p7s'
    $corruptSignaturePath = Join-Path $tempRoot 'corrupt.p7s'
    [IO.File]::WriteAllBytes($signaturePath, $signatureA)
    [IO.File]::WriteAllBytes($wrongSignerPath, $signatureB)
    $corruptSignature = [byte[]]$signatureA.Clone()
    $corruptSignature[$corruptSignature.Length - 1] = $corruptSignature[$corruptSignature.Length - 1] -bxor 1
    [IO.File]::WriteAllBytes($corruptSignaturePath, $corruptSignature)

    $packageSha256 = (Get-ToolPluginSha256 -Path $pluginPath).ToUpperInvariant()
    $pluginCatalog = [ordered]@{
        SchemaVersion = '1.0'
        CatalogId = 'verification.vendor.stable'
        PublisherId = 'verification.vendor'
        GeneratedAtUtc = ConvertTo-VerificationUtcText $now
        Plugins = @([ordered]@{
            PluginId = 'verification.signed-plugin'
            Version = '1.0.0'
            PackageUri = 'https://downloads.example.test/plugins/verification.signed-plugin.plugin.json'
            SignatureUri = 'https://downloads.example.test/plugins/verification.signed-plugin.plugin.json.p7s'
            PackageSha256 = $packageSha256
        })
    }
    $pluginCatalogPath = Join-Path $tempRoot 'verification.vendor.plugin-catalog.json'
    Write-SignedPluginCatalogFixture -Path $pluginCatalogPath -Catalog $pluginCatalog -Certificate $certificateA

    $validCatalog = Read-ToolPluginCatalog -Path $pluginCatalogPath `
        -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now
    Assert-TrustVerification ($validCatalog.Valid -and $validCatalog.SignatureValid -and
        $validCatalog.SignatureStatus -eq 'Valid' -and $validCatalog.SignerCertificateSha256 -eq $fingerprintA) `
        ('A correctly pinned signed third-party plugin catalog was rejected: ' + ($validCatalog.Errors -join '; '))
    Assert-TrustVerification ($validCatalog.FreshnessStatus -eq 'Fresh' -and $validCatalog.InstallationAllowed -and
        $validCatalog.EntryCount -eq 1) 'Fresh signed catalog metadata is incorrect.'
    Assert-TrustVerification ($validCatalog.ReadOnly -and -not $validCatalog.AutomaticDownloadAllowed -and
        -not $validCatalog.NetworkAccessPerformed -and -not $validCatalog.CodeExecutionAllowed) `
        'Catalog inspection did not preserve the read-only/no-network/no-code contract.'

    foreach ($unsafeUri in @(
        'http://downloads.example.test/plugin.plugin.json',
        'https://user:pass@downloads.example.test/plugin.plugin.json',
        'https://downloads.example.test/plugin.plugin.json?token=secret',
        'https://downloads.example.test/plugin.plugin.json#fragment',
        'https://127.0.0.1/plugin.plugin.json',
        'https://localhost/plugin.plugin.json',
        'https://downloads.example.test/a%2fplugin.plugin.json'
    )) {
        Assert-TrustVerification (-not (Test-ToolPluginCatalogHttpsUri -Value $unsafeUri -Kind Package).Valid) `
            "An unsafe plugin catalog URI was accepted: $unsafeUri"
    }
    Assert-TrustVerification ((Test-ToolPluginCatalogHttpsUri `
        -Value 'https://downloads.example.test/plugin.plugin.json' -Kind Package).Valid) `
        'A safe HTTPS plugin package URI was rejected.'

    $catalogInstallRoot = Join-Path $tempRoot 'catalog-installed-plugins'
    [void](New-Item -ItemType Directory -Path $catalogInstallRoot -Force)
    $catalogInstall = Install-ToolPluginPackageFromCatalog -CatalogPath $pluginCatalogPath `
        -PluginId 'verification.signed-plugin' -SourcePath $pluginPath `
        -PluginDirectory $catalogInstallRoot -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now
    Assert-TrustVerification ($catalogInstall.Installed -and
        $catalogInstall.CatalogId -eq 'verification.vendor.stable' -and
        $catalogInstall.CatalogSignerCertificateSha256 -eq $fingerprintA -and
        -not $catalogInstall.NetworkAccessPerformed) 'A valid local package could not be installed from its signed catalog declaration.'

    $wrongCatalogSignerPath = Join-Path $tempRoot 'wrong-signer.plugin-catalog.json'
    Write-SignedPluginCatalogFixture -Path $wrongCatalogSignerPath -Catalog $pluginCatalog -Certificate $certificateB
    $wrongCatalogSigner = Read-ToolPluginCatalog -Path $wrongCatalogSignerPath `
        -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now
    Assert-TrustVerification (-not $wrongCatalogSigner.Valid -and $wrongCatalogSigner.SignatureStatus -eq 'SignerNotTrusted') `
        'A plugin catalog signed by an unpinned publisher was accepted.'

    $missingCatalogSignaturePath = Join-Path $tempRoot 'missing-signature.plugin-catalog.json'
    [IO.File]::Copy($pluginCatalogPath, $missingCatalogSignaturePath)
    $missingCatalogSignature = Read-ToolPluginCatalog -Path $missingCatalogSignaturePath `
        -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now
    Assert-TrustVerification (-not $missingCatalogSignature.Valid -and $missingCatalogSignature.SignatureStatus -eq 'Missing') `
        'An unsigned third-party plugin catalog was accepted.'
    $unconfiguredCatalogTrust = Read-ToolPluginCatalog -Path $pluginCatalogPath -NowUtc $now
    Assert-TrustVerification (-not $unconfiguredCatalogTrust.Valid -and
        $unconfiguredCatalogTrust.SignatureStatus -eq 'TrustedSignerRequired') `
        'A plugin catalog signer was auto-trusted without an explicit SHA-256 pin.'

    $corruptCatalogSignaturePath = Join-Path $tempRoot 'corrupt-signature.plugin-catalog.json'
    [IO.File]::Copy($pluginCatalogPath, $corruptCatalogSignaturePath)
    $catalogSignatureBytes = [IO.File]::ReadAllBytes($pluginCatalogPath + '.p7s')
    $catalogSignatureBytes[$catalogSignatureBytes.Length - 1] = $catalogSignatureBytes[$catalogSignatureBytes.Length - 1] -bxor 1
    [IO.File]::WriteAllBytes(($corruptCatalogSignaturePath + '.p7s'), $catalogSignatureBytes)
    $corruptCatalogSignature = Read-ToolPluginCatalog -Path $corruptCatalogSignaturePath `
        -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now
    Assert-TrustVerification (-not $corruptCatalogSignature.Valid -and $corruptCatalogSignature.SignatureStatus -eq 'InvalidSignature') `
        'A corrupt plugin catalog signature was accepted.'

    $strictCatalog = $pluginCatalog | ConvertTo-Json -Depth 16 | ConvertFrom-Json
    $strictCatalog | Add-Member -NotePropertyName UnsupportedRootField -NotePropertyValue 'rejected'
    $strictCatalogPath = Join-Path $tempRoot 'strict-schema.plugin-catalog.json'
    Write-SignedPluginCatalogFixture -Path $strictCatalogPath -Catalog $strictCatalog -Certificate $certificateA
    $strictCatalogResult = Read-ToolPluginCatalog -Path $strictCatalogPath `
        -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now
    Assert-TrustVerification (-not $strictCatalogResult.Valid) 'A signed catalog with an unknown root field bypassed strict schema validation.'

    $unsafeCatalog = $pluginCatalog | ConvertTo-Json -Depth 16 | ConvertFrom-Json
    $unsafeCatalog.Plugins[0].PackageUri = 'http://downloads.example.test/plugins/verification.signed-plugin.plugin.json'
    $unsafeCatalogPath = Join-Path $tempRoot 'unsafe-uri.plugin-catalog.json'
    Write-SignedPluginCatalogFixture -Path $unsafeCatalogPath -Catalog $unsafeCatalog -Certificate $certificateA
    Assert-TrustVerification (-not (Read-ToolPluginCatalog -Path $unsafeCatalogPath `
        -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now).Valid) `
        'A signed catalog with an unsafe package URI was accepted.'

    $stalePluginCatalog = $pluginCatalog | ConvertTo-Json -Depth 16 | ConvertFrom-Json
    $stalePluginCatalog.GeneratedAtUtc = ConvertTo-VerificationUtcText $now.AddDays(-45)
    $stalePluginCatalogPath = Join-Path $tempRoot 'stale-plugin.plugin-catalog.json'
    Write-SignedPluginCatalogFixture -Path $stalePluginCatalogPath -Catalog $stalePluginCatalog -Certificate $certificateA
    $stalePluginCatalogResult = Read-ToolPluginCatalog -Path $stalePluginCatalogPath `
        -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now
    Assert-TrustVerification ($stalePluginCatalogResult.Valid -and $stalePluginCatalogResult.FreshnessStatus -eq 'Stale' -and
        -not $stalePluginCatalogResult.InstallationAllowed) 'A stale signed plugin catalog was not forced to read-only.'
    Assert-TrustVerificationThrows -Message 'A stale signed catalog authorized installation.' -Action {
        Install-ToolPluginPackageFromCatalog -CatalogPath $stalePluginCatalogPath `
            -PluginId 'verification.signed-plugin' -SourcePath $pluginPath `
            -PluginDirectory $catalogInstallRoot -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now -Force
    }

    $futurePluginCatalog = $pluginCatalog | ConvertTo-Json -Depth 16 | ConvertFrom-Json
    $futurePluginCatalog.GeneratedAtUtc = ConvertTo-VerificationUtcText $now.AddHours(24).AddSeconds(1)
    $futurePluginCatalogPath = Join-Path $tempRoot 'future-plugin.plugin-catalog.json'
    Write-SignedPluginCatalogFixture -Path $futurePluginCatalogPath -Catalog $futurePluginCatalog -Certificate $certificateA
    $futurePluginCatalogResult = Read-ToolPluginCatalog -Path $futurePluginCatalogPath `
        -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now
    Assert-TrustVerification ($futurePluginCatalogResult.Valid -and $futurePluginCatalogResult.FreshnessStatus -eq 'Future' -and
        -not $futurePluginCatalogResult.InstallationAllowed) 'A future-dated signed plugin catalog was not forced to read-only.'

    $hashMismatchCatalog = $pluginCatalog | ConvertTo-Json -Depth 16 | ConvertFrom-Json
    $hashMismatchCatalog.Plugins[0].PackageSha256 = ('0' * 64)
    $hashMismatchCatalogPath = Join-Path $tempRoot 'hash-mismatch.plugin-catalog.json'
    Write-SignedPluginCatalogFixture -Path $hashMismatchCatalogPath -Catalog $hashMismatchCatalog -Certificate $certificateA
    Assert-TrustVerificationThrows -Message 'A local package hash mismatch was accepted during catalog installation.' -Action {
        Install-ToolPluginPackageFromCatalog -CatalogPath $hashMismatchCatalogPath `
            -PluginId 'verification.signed-plugin' -SourcePath $pluginPath `
            -PluginDirectory $catalogInstallRoot -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now -Force
    }

    Assert-TrustVerificationThrows -Message 'A package signed by a different certificate than its catalog was accepted.' -Action {
        Install-ToolPluginPackageFromCatalog -CatalogPath $pluginCatalogPath `
            -PluginId 'verification.signed-plugin' -SourcePath $pluginPath -PluginSignaturePath $wrongSignerPath `
            -PluginDirectory $catalogInstallRoot -TrustedSignerCertificateSha256 @($fingerprintA, (Get-ToolPluginCertificateSha256 $certificateB)) `
            -NowUtc $now -Force
    }

    $tooManyEntriesCatalog = $pluginCatalog | ConvertTo-Json -Depth 16 | ConvertFrom-Json
    $tooManyEntries = New-Object System.Collections.Generic.List[object]
    foreach ($index in 1..257) {
        $entryId = "verification.catalog-$index"
        [void]$tooManyEntries.Add([pscustomobject][ordered]@{
            PluginId=$entryId; Version='1.0.0'
            PackageUri="https://downloads.example.test/plugins/$entryId.plugin.json"
            SignatureUri="https://downloads.example.test/plugins/$entryId.plugin.json.p7s"
            PackageSha256=$packageSha256
        })
    }
    $tooManyEntriesCatalog.Plugins = @($tooManyEntries.ToArray())
    $tooManyEntriesPath = Join-Path $tempRoot 'too-many.plugin-catalog.json'
    Write-SignedPluginCatalogFixture -Path $tooManyEntriesPath -Catalog $tooManyEntriesCatalog -Certificate $certificateA
    Assert-TrustVerification (-not (Read-ToolPluginCatalog -Path $tooManyEntriesPath `
        -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now).Valid) `
        'A plugin catalog exceeding the 256-entry limit was accepted.'

    $oversizedCatalogPath = Join-Path $tempRoot 'oversized.plugin-catalog.json'
    [IO.File]::WriteAllText($oversizedCatalogPath, (' ' * 524289), $utf8)
    Assert-TrustVerification (-not (Read-ToolPluginCatalog -Path $oversizedCatalogPath `
        -TrustedSignerCertificateSha256 $fingerprintA -NowUtc $now).Valid) `
        'A plugin catalog exceeding the 512-KiB limit was accepted.'

    $catalogReadDefinition = (Get-Command Read-ToolPluginCatalog -CommandType Function).Definition
    $catalogInstallDefinition = (Get-Command Install-ToolPluginPackageFromCatalog -CommandType Function).Definition
    Assert-TrustVerification (($catalogReadDefinition + $catalogInstallDefinition) -notmatch
        '(?i)Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|WebClient|HttpClient') `
        'Plugin catalog support introduced an automatic network client.'
    Assert-TrustVerification ($catalogReadDefinition -notmatch '(?i)Invoke-Expression|ScriptBlock::Create|Start-Process') `
        'Plugin catalog inspection introduced a code-execution path.'

    $validPackage = Read-ToolPluginPackage -Path $pluginPath -AllowOutsideProtectedDirectory `
        -TrustedSignerCertificateSha256 $fingerprintA -RequireTrustedSignature
    Assert-TrustVerification ($validPackage.Valid -and $validPackage.SignatureValid -and $validPackage.SignatureStatus -eq 'Valid') 'A correctly pinned detached plugin signature was rejected.'
    Assert-TrustVerification ($validPackage.SignerCertificateSha256 -eq $fingerprintA) 'The verified plugin signer fingerprint was not reported.'

    $installRoot = Join-Path $tempRoot 'installed-plugins'
    [void](New-Item -ItemType Directory -Path $installRoot -Force)
    $installResult = Install-ToolPluginPackage -SourcePath $pluginPath -PluginDirectory $installRoot `
        -TrustedSignerCertificateSha256 $fingerprintA -RequireTrustedSignature
    Assert-TrustVerification ($installResult.Installed -and $installResult.Trust -eq 'SignedTrustedPublisher' -and
        (Test-Path -LiteralPath ($installResult.Path + '.p7s') -PathType Leaf)) 'Signed plugin installation did not preserve its verified detached signature.'
    $auditResult = Invoke-ToolPluginAudit -PluginDirectory $installRoot `
        -TrustedSignerCertificateSha256 $fingerprintA -RequireTrustedSignature
    Assert-TrustVerification ($auditResult.InvalidPluginCount -eq 0 -and $auditResult.PluginCount -eq 1 -and
        $auditResult.Plugins[0].Trust -eq 'SignedTrustedPublisher') 'The audit path did not enforce the configured plugin signer pin.'

    $missingPackage = Read-ToolPluginPackage -Path $pluginPath -AllowOutsideProtectedDirectory `
        -SignaturePath (Join-Path $tempRoot 'missing.p7s') -TrustedSignerCertificateSha256 $fingerprintA -RequireTrustedSignature
    Assert-TrustVerification (-not $missingPackage.Valid -and $missingPackage.SignatureStatus -eq 'Missing') 'A missing required plugin signature was accepted.'

    $corruptPackage = Read-ToolPluginPackage -Path $pluginPath -AllowOutsideProtectedDirectory `
        -SignaturePath $corruptSignaturePath -TrustedSignerCertificateSha256 $fingerprintA -RequireTrustedSignature
    Assert-TrustVerification (-not $corruptPackage.Valid -and $corruptPackage.SignatureStatus -eq 'InvalidSignature') 'A corrupt plugin signature was accepted.'

    $wrongSignerPackage = Read-ToolPluginPackage -Path $pluginPath -AllowOutsideProtectedDirectory `
        -SignaturePath $wrongSignerPath -TrustedSignerCertificateSha256 $fingerprintA -RequireTrustedSignature
    Assert-TrustVerification (-not $wrongSignerPackage.Valid -and $wrongSignerPackage.SignatureStatus -eq 'SignerNotTrusted') 'A valid signature from an unpinned signer was accepted.'

    $unconfiguredTrust = Read-ToolPluginPackage -Path $pluginPath -AllowOutsideProtectedDirectory -RequireTrustedSignature
    Assert-TrustVerification (-not $unconfiguredTrust.Valid -and $unconfiguredTrust.SignatureStatus -eq 'TrustedSignerRequired') 'A plugin signer was auto-trusted without an explicit SHA-256 allowlist.'

    $legacyPackage = Read-ToolPluginPackage -Path $legacyPluginPath -AllowOutsideProtectedDirectory `
        -TrustedSignerCertificateSha256 $fingerprintA
    Assert-TrustVerification ($legacyPackage.Valid -and -not $legacyPackage.SignaturePresent) 'Unsigned built-in compatibility was broken when signature enforcement was not requested.'
} finally {
    foreach ($certificate in $certificates) {
        if ($certificate -and $certificate.Thumbprint) {
            Remove-Item -LiteralPath ('Cert:\CurrentUser\My\' + [string]$certificate.Thumbprint) -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'VERIFY-CATALOG-PLUGIN-TRUST-V5: OK (software/plugin freshness + signed read-only third-party catalog + strict schema/URI/limits + fail-closed local install)'
