$null = try { Add-Type -AssemblyName System.Security -ErrorAction Stop } catch { $null }

$toolEnterpriseDataLifecyclePath = Join-Path $PSScriptRoot "Tool-DataLifecycle.ps1"
if (-not (Get-Command Get-ToolDataRoot -ErrorAction SilentlyContinue) -and
    (Test-Path -LiteralPath $toolEnterpriseDataLifecyclePath -PathType Leaf)) {
    . $toolEnterpriseDataLifecyclePath
}

$toolEnterpriseLocalizationPath = Join-Path $PSScriptRoot "Tool-Localization.ps1"
$toolEnterpriseLocalizationReady = (
    $null -ne (Get-Command Get-ToolText -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Command Get-ToolCulture -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Command Test-ToolSupportedCulture -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Variable -Name ToolLocalizationDefaultCulture -Scope Script -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Variable -Name ToolLocalizationSupportedCultures -Scope Script -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Variable -Name ToolLocalizationCatalogCache -Scope Script -ErrorAction SilentlyContinue)
)
if (-not $toolEnterpriseLocalizationReady -and
    (Test-Path -LiteralPath $toolEnterpriseLocalizationPath -PathType Leaf)) {
    . $toolEnterpriseLocalizationPath
}

$toolEnterpriseCompliancePath = Join-Path $PSScriptRoot "Tool-LicenseCompliance.ps1"
if (-not (Get-Command Get-ToolLicenseComplianceSnapshot -ErrorAction SilentlyContinue) -and
    (Test-Path -LiteralPath $toolEnterpriseCompliancePath -PathType Leaf)) {
    . $toolEnterpriseCompliancePath
}

$toolEnterpriseAssetRegistryPath = Join-Path $PSScriptRoot "Tool-AssetRegistry.ps1"
if (-not (Get-Command Get-ToolDeviceIdentitySnapshot -ErrorAction SilentlyContinue) -and
    (Test-Path -LiteralPath $toolEnterpriseAssetRegistryPath -PathType Leaf)) {
    . $toolEnterpriseAssetRegistryPath
}

function Get-ToolEnterpriseText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object[]]$Arguments = @()
    )

    $culture = [string]$env:TOOL_UI_CULTURE
    if (Get-Command Test-ToolSupportedCulture -ErrorAction SilentlyContinue) {
        if (-not (Test-ToolSupportedCulture $culture)) { $culture = Get-ToolCulture }
    } elseif ($culture -notin @("vi-VN", "en-US")) {
        $culture = "vi-VN"
    }
    if (Get-Command Get-ToolText -ErrorAction SilentlyContinue) {
        return (Get-ToolText -Key $Key -Culture $culture -FormatArguments $Arguments)
    }
    return "[$Key]"
}

function Get-ToolEnterpriseCultureText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [ValidateSet('vi-VN','en-US')][string]$Culture,
        [AllowNull()][object[]]$Arguments = @()
    )

    if (Get-Command Get-ToolText -ErrorAction SilentlyContinue) {
        return (Get-ToolText -Key $Key -Culture $Culture -FormatArguments $Arguments)
    }
    $previousCulture = [string]$env:TOOL_UI_CULTURE
    try {
        $env:TOOL_UI_CULTURE = $Culture
        return (Get-ToolEnterpriseText -Key $Key -Arguments $Arguments)
    } finally {
        $env:TOOL_UI_CULTURE = $previousCulture
    }
}

$script:ToolEnterpriseSchemaVersion = "1.0"
$script:ToolEnterpriseProtocolVersion = "1.0"
$script:ToolEnterpriseToolVersion = "5.0"
$script:ToolEnterpriseDefaultPort = 49420
$script:ToolEnterpriseMaximumRequestBytes = 1048576
$script:ToolEnterpriseMaximumScanHosts = 1024
$script:ToolEnterpriseInitializedRoot = ""
$script:ToolEnterpriseInitializedPaths = $null

function ConvertTo-ToolEnterpriseSafeText {
    param([AllowNull()][object]$Value, [int]$MaximumLength = 2048)

    if ($null -eq $Value) { return "" }
    $text = ([string]$Value).Replace("`0", "").Replace("`r", " ").Replace("`n", " ").Trim()
    $text = [regex]::Replace($text, '(?i)(?<![A-Z0-9])[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}(?![A-Z0-9])', (Get-ToolEnterpriseText "enterpriseCore.redaction.fullKey"))
    $text = [regex]::Replace($text, '(?i)(?<![A-Z0-9])[A-Z0-9]{25}(?![A-Z0-9])', (Get-ToolEnterpriseText "enterpriseCore.redaction.productKey"))
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}

function ConvertTo-ToolEnterpriseCsvSafeText {
    param([AllowNull()][object]$Value, [int]$MaximumLength = 2048)

    $text = ConvertTo-ToolEnterpriseSafeText -Value $Value -MaximumLength $MaximumLength
    # Spreadsheet applications can treat these leading characters as a
    # formula even when the value is quoted by Export-Csv.  Prefix the cell
    # with a literal apostrophe so fleet exports are safe to open directly.
    if ($text -match '^\s*[=+\-@]') { return ("'" + $text) }
    return $text
}

function Get-ToolEnterpriseStableClientReference {
    param([Parameter(Mandatory = $true)][string]$ClientId)

    $bytes = [Text.Encoding]::UTF8.GetBytes($ClientId.Trim().ToUpperInvariant())
    $hash = Get-ToolEnterpriseSha256Bytes -Bytes $bytes
    return ("CLIENT-" + (([BitConverter]::ToString($hash)).Replace("-", "").Substring(0, 12)))
}

function Get-ToolEnterpriseClientAgeHours {
    param([AllowNull()][object]$LastSeenUtc)

    $lastSeen = [DateTime]::MinValue
    if (-not [DateTime]::TryParse(
        [string]$LastSeenUtc,
        [Globalization.CultureInfo]::InvariantCulture,
        ([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal),
        [ref]$lastSeen)) {
        return [double]::PositiveInfinity
    }
    $age = ([DateTime]::UtcNow - $lastSeen.ToUniversalTime()).TotalHours
    if ($age -lt 0) { return 0.0 }
    return $age
}

function Get-ToolEnterpriseRoot {
    $configured = [string]$env:TOOL_ENTERPRISE_ROOT
    if (-not [string]::IsNullOrWhiteSpace($configured)) { return [IO.Path]::GetFullPath($configured) }
    if (Get-Command Get-ToolDataRoot -ErrorAction SilentlyContinue) {
        return (Join-Path (Get-ToolDataRoot) "enterprise")
    }
    $commonData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    return (Join-Path $commonData "ThanhViet-VietLicenSure\v4.6\enterprise")
}

function Get-ToolEnterprisePaths {
    $root = Get-ToolEnterpriseRoot
    return [pscustomobject][ordered]@{
        Root = $root
        Server = Join-Path $root "server"
        ServerConfig = Join-Path $root "server\server.json"
        ServerMasterSecret = Join-Path $root "server\server-master.bin"
        ServerPairingSecret = Join-Path $root "server\pairing-secret.bin"
        ServerClients = Join-Path $root "server\clients"
        ServerClientSecrets = Join-Path $root "server\client-secrets"
        ServerReports = Join-Path $root "server\reports"
        ServerJobs = Join-Path $root "server\jobs"
        ServerResults = Join-Path $root "server\results"
        ServerAssets = Join-Path $root "server\assets"
        ServerAudit = Join-Path $root "server\enterprise-audit.jsonl"
        ServerPid = Join-Path $root "server\server.pid.json"
        ServerHeartbeat = Join-Path $root "server\server-heartbeat.json"
        ServerStop = Join-Path $root "server\server.stop"
        ServerError = Join-Path $root "server\server-error.json"
        ServerDashboardSession = Join-Path $root "server\dashboard-session.json"
        Client = Join-Path $root "client"
        ClientConfig = Join-Path $root "client\client.json"
        ClientSecret = Join-Path $root "client\client-secret.bin"
        ClientOutbox = Join-Path $root "client\outbox"
        ClientProcessed = Join-Path $root "client\processed"
        ClientAudit = Join-Path $root "client\enterprise-audit.jsonl"
        ClientAgentResult = Join-Path $root "client\agent-result.json"
        ClientAgentError = Join-Path $root "client\agent-error.json"
        Bin = Join-Path $root "bin"
    }
}

function Test-ToolEnterpriseReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool]((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Set-ToolEnterpriseProtectedDirectoryAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    # Test harnesses can point the root at an isolated temporary directory.
    # Never set this variable in a deployed build; the launcher does not set
    # it and therefore always applies the protected ACL.
    if ([string]$env:TOOL_ENTERPRISE_SKIP_ACL -eq "1") { return }

    $administratorsSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $systemSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-18")
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    # Setting the owner requires SeRestorePrivilege on some locked-down
    # Windows images and causes Set-Acl to fail even for an administrator
    # token.  Keep the existing owner and protect the directory with the
    # explicit DACL instead.
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($administratorsSid, "FullControl", $inheritance, "None", "Allow")))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", $inheritance, "None", "Allow")))
    try {
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        if ($currentSid) {
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($currentSid, "FullControl", $inheritance, "None", "Allow")))
        }
    } catch { }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Initialize-ToolEnterpriseStorage {
    if ((Get-Command Initialize-ToolDataLifecycle -ErrorAction SilentlyContinue) -and
        (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_DATA_ROOT) -or
         [string]::IsNullOrWhiteSpace([string]$env:TOOL_ENTERPRISE_ROOT))) {
        [void](Initialize-ToolDataLifecycle)
    }
    $paths = Get-ToolEnterprisePaths
    if ($script:ToolEnterpriseInitializedPaths -and
        [string]::Equals([string]$script:ToolEnterpriseInitializedRoot, [string]$paths.Root, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $paths.Root -PathType Container)) {
        return $script:ToolEnterpriseInitializedPaths
    }
    $rootExisted = Test-Path -LiteralPath $paths.Root -PathType Container
    $directories = @(
        $paths.Root, $paths.Server, $paths.ServerClients, $paths.ServerClientSecrets,
        $paths.ServerReports, $paths.ServerJobs, $paths.ServerResults, $paths.ServerAssets,
        $paths.Client, $paths.ClientOutbox, $paths.ClientProcessed, $paths.Bin
    )
    foreach ($directory in $directories) {
        if (Test-ToolEnterpriseReparsePoint -Path $directory) { throw (Get-ToolEnterpriseText "enterpriseCore.error.directoryReparse" @($directory)) }
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        if (Test-ToolEnterpriseReparsePoint -Path $directory) { throw (Get-ToolEnterpriseText "enterpriseCore.error.directoryReparse" @($directory)) }
    }
    # The one-file launcher has already created and locked the v4.6 root.
    # Avoid re-applying an ACL on every inventory/report call (it is both
    # expensive and can require SeSecurityPrivilege on hardened images).
    # For a newly-created source/standalone root, apply it once; secure launch
    # remains fail-closed if that initial protection cannot be established.
    if (-not $rootExisted -or [string]$env:TOOL_ENTERPRISE_FORCE_ACL -eq "1") {
        try { Set-ToolEnterpriseProtectedDirectoryAcl -Path $paths.Root }
        catch {
            if ([string]$env:TOOL_SECURE_LAUNCH -eq "1") { throw }
        }
    }
    $script:ToolEnterpriseInitializedRoot = [string]$paths.Root
    $script:ToolEnterpriseInitializedPaths = $paths
    return $paths
}

function Assert-ToolEnterprisePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $root = [IO.Path]::GetFullPath((Get-ToolEnterpriseRoot)).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.pathOutsideRoot" @($full))
    }
    return $full
}

function Write-ToolEnterpriseJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Value
    )

    $full = Assert-ToolEnterprisePath -Path $Path
    $directory = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    if (Test-ToolEnterpriseReparsePoint -Path $directory) { throw (Get-ToolEnterpriseText "enterpriseCore.error.writeDirectoryReparse" @($directory)) }
    if ((Test-Path -LiteralPath $full -PathType Leaf) -and (Test-ToolEnterpriseReparsePoint -Path $full)) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.overwriteFileReparse" @($full))
    }
    $temporary = Join-Path $directory (".write-" + [Guid]::NewGuid().ToString("N") + ".tmp")
    $json = $Value | ConvertTo-Json -Depth 14
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
    try {
        Move-Item -LiteralPath $temporary -Destination $full -Force
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Read-ToolEnterpriseJson {
    param([Parameter(Mandatory = $true)][string]$Path, [int]$MaximumBytes = 10485760)

    $full = Assert-ToolEnterprisePath -Path $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Get-ToolEnterpriseText "enterpriseCore.error.readFileReparse" @($full)) }
    if ($item.Length -le 0 -or $item.Length -gt $MaximumBytes) { throw (Get-ToolEnterpriseText "enterpriseCore.error.jsonSize" @($full)) }
    return (Get-Content -LiteralPath $full -Raw -ErrorAction Stop | ConvertFrom-Json)
}

function Get-ToolEnterpriseSha256Bytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return $algorithm.ComputeHash($Bytes) } finally { $algorithm.Dispose() }
}

function Get-ToolEnterpriseSha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace("-", "") }
        finally { $algorithm.Dispose() }
    } finally { $stream.Dispose() }
}

function New-ToolEnterpriseRandomBytes {
    param([ValidateRange(16, 128)][int]$Length = 32)
    $bytes = New-Object byte[] $Length
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return $bytes
}

function ConvertTo-ToolEnterpriseBase64Url {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-ToolEnterpriseBase64Url {
    param([Parameter(Mandatory = $true)][string]$Text)
    if ($Text -notmatch '^[A-Za-z0-9_-]+$') { throw (Get-ToolEnterpriseText "enterpriseCore.error.base64UrlInvalid") }
    $normalized = $Text.Replace('-', '+').Replace('_', '/')
    while (($normalized.Length % 4) -ne 0) { $normalized += '=' }
    return [Convert]::FromBase64String($normalized)
}

function Get-ToolEnterpriseDpapiEntropy {
    # Stable compatibility identifier: migrated v4.4/v4.5 DPAPI material must
    # remain decryptable after moving into the isolated v4.6 data root.
    return (Get-ToolEnterpriseSha256Bytes -Bytes ([Text.Encoding]::UTF8.GetBytes("ThanhViet-VietLicenSure-v4.4-enterprise")))
}

function Protect-ToolEnterpriseBytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [Security.Cryptography.ProtectedData]::Protect(
        $Bytes,
        (Get-ToolEnterpriseDpapiEntropy),
        [Security.Cryptography.DataProtectionScope]::LocalMachine
    )
}

function Unprotect-ToolEnterpriseBytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [Security.Cryptography.ProtectedData]::Unprotect(
        $Bytes,
        (Get-ToolEnterpriseDpapiEntropy),
        [Security.Cryptography.DataProtectionScope]::LocalMachine
    )
}

function Set-ToolEnterpriseSecret {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][byte[]]$Secret)
    $full = Assert-ToolEnterprisePath -Path $Path
    $directory = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    if (Test-ToolEnterpriseReparsePoint -Path $directory) { throw (Get-ToolEnterpriseText "enterpriseCore.error.secretDirectoryReparse") }
    if ((Test-Path -LiteralPath $full -PathType Leaf) -and (Test-ToolEnterpriseReparsePoint -Path $full)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.secretFileReparse") }
    $protected = Protect-ToolEnterpriseBytes -Bytes $Secret
    $temporary = Join-Path $directory (".secret-" + [Guid]::NewGuid().ToString("N") + ".tmp")
    try {
        [IO.File]::WriteAllBytes($temporary, $protected)
        Move-Item -LiteralPath $temporary -Destination $full -Force
    } finally {
        if ($protected) { [Array]::Clear($protected, 0, $protected.Length) }
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Get-ToolEnterpriseSecret {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Assert-ToolEnterprisePath -Path $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Get-ToolEnterpriseText "enterpriseCore.error.secretReadReparse") }
    if ($item.Length -le 0 -or $item.Length -gt 65536) { throw (Get-ToolEnterpriseText "enterpriseCore.error.secretSize") }
    return (Unprotect-ToolEnterpriseBytes -Bytes ([IO.File]::ReadAllBytes($full)))
}

function Get-ToolEnterpriseDerivedKey {
    param([Parameter(Mandatory = $true)][byte[]]$Secret, [Parameter(Mandatory = $true)][string]$Purpose)
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$Secret)
    # Cryptographic domain-separation label, not an active data path or a
    # product-version claim. Keep it stable for migrated enterprise secrets.
    try { return $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("v4.4-enterprise|" + $Purpose)) }
    finally { $hmac.Dispose() }
}

function Test-ToolEnterpriseFixedTimeEquals {
    param([Parameter(Mandatory = $true)][byte[]]$Left, [Parameter(Mandatory = $true)][byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    $difference = 0
    for ($index = 0; $index -lt $Left.Length; $index++) {
        $difference = $difference -bor ($Left[$index] -bxor $Right[$index])
    }
    return [bool]($difference -eq 0)
}

function New-ToolEnterpriseEnvelope {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Secret,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Payload
    )

    $safeContext = ConvertTo-ToolEnterpriseSafeText $Context 180
    if ([string]::IsNullOrWhiteSpace($safeContext)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.encryptionContextInvalid") }
    $plainJson = $Payload | ConvertTo-Json -Depth 14 -Compress
    $plainBytes = [Text.Encoding]::UTF8.GetBytes($plainJson)
    if ($plainBytes.Length -gt $script:ToolEnterpriseMaximumRequestBytes) { throw (Get-ToolEnterpriseText "enterpriseCore.error.payloadTooLarge") }
    $encryptionKey = Get-ToolEnterpriseDerivedKey -Secret $Secret -Purpose "encryption"
    $authenticationKey = Get-ToolEnterpriseDerivedKey -Secret $Secret -Purpose "authentication"
    $aes = New-Object Security.Cryptography.AesManaged
    try {
        $aes.KeySize = 256
        $aes.BlockSize = 128
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $encryptionKey
        $aes.GenerateIV()
        $encryptor = $aes.CreateEncryptor()
        try { $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length) }
        finally { $encryptor.Dispose() }
        $timestamp = [DateTime]::UtcNow.ToString("o")
        $nonce = ConvertTo-ToolEnterpriseBase64Url -Bytes (New-ToolEnterpriseRandomBytes -Length 18)
        $iv = ConvertTo-ToolEnterpriseBase64Url -Bytes $aes.IV
        $cipherText = ConvertTo-ToolEnterpriseBase64Url -Bytes $cipherBytes
        $canonical = "$($script:ToolEnterpriseProtocolVersion)`n$safeContext`n$timestamp`n$nonce`n$iv`n$cipherText"
        $hmac = New-Object Security.Cryptography.HMACSHA256(,$authenticationKey)
        try { $mac = ConvertTo-ToolEnterpriseBase64Url -Bytes ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))) }
        finally { $hmac.Dispose() }
        return [pscustomobject][ordered]@{
            ProtocolVersion = $script:ToolEnterpriseProtocolVersion
            Context = $safeContext
            TimestampUtc = $timestamp
            Nonce = $nonce
            Iv = $iv
            CipherText = $cipherText
            Mac = $mac
        }
    } finally {
        $aes.Dispose()
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
        [Array]::Clear($encryptionKey, 0, $encryptionKey.Length)
        [Array]::Clear($authenticationKey, 0, $authenticationKey.Length)
    }
}

function Open-ToolEnterpriseEnvelope {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Secret,
        [Parameter(Mandatory = $true)][string]$ExpectedContext,
        [Parameter(Mandatory = $true)][object]$Envelope,
        [ValidateRange(1, 10080)][int]$MaximumAgeMinutes = 10
    )

    foreach ($propertyName in @("ProtocolVersion", "Context", "TimestampUtc", "Nonce", "Iv", "CipherText", "Mac")) {
        if ($null -eq $Envelope.PSObject.Properties[$propertyName] -or [string]::IsNullOrWhiteSpace([string]$Envelope.$propertyName)) {
            throw (Get-ToolEnterpriseText "enterpriseCore.error.envelopeFieldMissing" @($propertyName))
        }
    }
    if ([string]$Envelope.ProtocolVersion -ne $script:ToolEnterpriseProtocolVersion) { throw (Get-ToolEnterpriseText "enterpriseCore.error.protocolUnsupported") }
    if (-not [string]::Equals([string]$Envelope.Context, $ExpectedContext, [StringComparison]::Ordinal)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.envelopeContextMismatch") }
    $timestamp = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$Envelope.TimestampUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$timestamp)) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.envelopeTimestampInvalid")
    }
    $age = [DateTime]::UtcNow - $timestamp.ToUniversalTime()
    if ([Math]::Abs($age.TotalMinutes) -gt $MaximumAgeMinutes) { throw (Get-ToolEnterpriseText "enterpriseCore.error.envelopeExpired") }
    $authenticationKey = Get-ToolEnterpriseDerivedKey -Secret $Secret -Purpose "authentication"
    $canonical = "$([string]$Envelope.ProtocolVersion)`n$([string]$Envelope.Context)`n$([string]$Envelope.TimestampUtc)`n$([string]$Envelope.Nonce)`n$([string]$Envelope.Iv)`n$([string]$Envelope.CipherText)"
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$authenticationKey)
    try { $expectedMac = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)) }
    finally { $hmac.Dispose(); [Array]::Clear($authenticationKey, 0, $authenticationKey.Length) }
    $actualMac = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$Envelope.Mac)
    if (-not (Test-ToolEnterpriseFixedTimeEquals -Left $expectedMac -Right $actualMac)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.envelopeHmacInvalid") }
    $encryptionKey = Get-ToolEnterpriseDerivedKey -Secret $Secret -Purpose "encryption"
    $iv = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$Envelope.Iv)
    $cipherBytes = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$Envelope.CipherText)
    $aes = New-Object Security.Cryptography.AesManaged
    try {
        $aes.KeySize = 256
        $aes.BlockSize = 128
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $encryptionKey
        $aes.IV = $iv
        $decryptor = $aes.CreateDecryptor()
        try { $plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length) }
        finally { $decryptor.Dispose() }
        if ($plainBytes.Length -gt $script:ToolEnterpriseMaximumRequestBytes) { throw (Get-ToolEnterpriseText "enterpriseCore.error.decryptedPayloadTooLarge") }
        $plainJson = [Text.Encoding]::UTF8.GetString($plainBytes)
        $payload = $plainJson | ConvertFrom-Json
        return [pscustomobject][ordered]@{
            Payload = $payload
            Nonce = [string]$Envelope.Nonce
            TimestampUtc = $timestamp.ToUniversalTime()
        }
    } finally {
        $aes.Dispose()
        [Array]::Clear($encryptionKey, 0, $encryptionKey.Length)
        if ($plainBytes) { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
    }
}

function New-ToolEnterpriseAdminVerifier {
    param([Parameter(Mandatory = $true)][string]$AdminCode)
    if ($AdminCode.Length -lt 8 -or $AdminCode.Length -gt 128) { throw (Get-ToolEnterpriseText "enterpriseCore.error.adminCodeLength") }
    $salt = New-ToolEnterpriseRandomBytes -Length 24
    $derive = New-Object Security.Cryptography.Rfc2898DeriveBytes($AdminCode, $salt, 120000)
    try { $hash = $derive.GetBytes(32) } finally { $derive.Dispose() }
    return [pscustomobject][ordered]@{
        Algorithm = "PBKDF2-HMAC-SHA1"
        Iterations = 120000
        Salt = ConvertTo-ToolEnterpriseBase64Url -Bytes $salt
        Hash = ConvertTo-ToolEnterpriseBase64Url -Bytes $hash
    }
}

function Test-ToolEnterpriseAdminCode {
    param([Parameter(Mandatory = $true)][string]$AdminCode, [Parameter(Mandatory = $true)][object]$Verifier)
    try {
        $salt = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$Verifier.Salt)
        $expected = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$Verifier.Hash)
        $iterations = [int]$Verifier.Iterations
        if ($iterations -lt 100000) { return $false }
        $derive = New-Object Security.Cryptography.Rfc2898DeriveBytes($AdminCode, $salt, $iterations)
        try { $actual = $derive.GetBytes($expected.Length) } finally { $derive.Dispose() }
        return (Test-ToolEnterpriseFixedTimeEquals -Left $expected -Right $actual)
    } catch { return $false }
}

function Write-ToolEnterpriseAudit {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("Server", "Client")][string]$Scope,
        [Parameter(Mandatory = $true)][string]$Event,
        [string]$Message = "",
        [AllowNull()][object]$Data = $null
    )

    $paths = Initialize-ToolEnterpriseStorage
    $auditCandidate = if ($Scope -eq "Server") { $paths.ServerAudit } else { $paths.ClientAudit }
    $path = Assert-ToolEnterprisePath -Path $auditCandidate
    $auditDirectory = Split-Path -Parent $path
    if (Test-ToolEnterpriseReparsePoint -Path $auditDirectory) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.auditDirectoryReparse" @($auditDirectory))
    }
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Test-ToolEnterpriseReparsePoint -Path $path)) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.auditFileReparse" @($path))
    }
    $record = [ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        TimestampUtc = [DateTime]::UtcNow.ToString("o")
        Scope = $Scope
        Event = ConvertTo-ToolEnterpriseSafeText $Event 120
        Message = ConvertTo-ToolEnterpriseSafeText $Message 2048
        Data = $Data
    }
    $line = ($record | ConvertTo-Json -Depth 10 -Compress) + [Environment]::NewLine
    $created = $false
    $mutex = New-Object Threading.Mutex($false, "Global\ThanhViet.VietLicenSure.v5.0.EnterpriseAudit", [ref]$created)
    try {
        if (-not $mutex.WaitOne(5000)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.auditLock") }
        try { [IO.File]::AppendAllText($path, $line, (New-Object Text.UTF8Encoding($false))) }
        finally { $mutex.ReleaseMutex() }
    } finally { $mutex.Dispose() }
}

function ConvertTo-ToolEnterpriseIPv4UInt32 {
    param([Parameter(Mandatory = $true)][string]$Address)
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.ipv4Invalid" @($Address))
    }
    $bytes = $parsed.GetAddressBytes()
    $value = ([uint64]$bytes[0] * 16777216) + ([uint64]$bytes[1] * 65536) + ([uint64]$bytes[2] * 256) + [uint64]$bytes[3]
    return [uint32]$value
}

function ConvertFrom-ToolEnterpriseIPv4UInt32 {
    param([Parameter(Mandatory = $true)][uint32]$Value)
    $bytes = New-Object byte[] 4
    $bytes[0] = [byte](([uint64]$Value -shr 24) -band 255)
    $bytes[1] = [byte](([uint64]$Value -shr 16) -band 255)
    $bytes[2] = [byte](([uint64]$Value -shr 8) -band 255)
    $bytes[3] = [byte]([uint64]$Value -band 255)
    return (New-Object Net.IPAddress(,$bytes)).ToString()
}

function Get-ToolEnterpriseCidrInfo {
    param([Parameter(Mandatory = $true)][string]$Cidr)
    if ($Cidr -notmatch '^([^/]+)/(\d{1,2})$') { throw (Get-ToolEnterpriseText "enterpriseCore.error.cidrInvalid" @($Cidr)) }
    $address = $matches[1]
    $prefixLength = [int]$matches[2]
    if ($prefixLength -lt 0 -or $prefixLength -gt 32) { throw (Get-ToolEnterpriseText "enterpriseCore.error.cidrPrefix") }
    $ipValue = ConvertTo-ToolEnterpriseIPv4UInt32 -Address $address
    $allBits = [uint64]4294967295
    $mask64 = if ($prefixLength -eq 0) { [uint64]0 } else { (($allBits -shl (32 - $prefixLength)) -band $allBits) }
    $network64 = ([uint64]$ipValue) -band $mask64
    $hostMask64 = ($allBits -bxor $mask64) -band $allBits
    $broadcast64 = $network64 -bor $hostMask64
    $hostCount = if ($prefixLength -ge 31) { [uint64]($broadcast64 - $network64 + 1) } else { [uint64][Math]::Max(0, [double]($broadcast64 - $network64 - 1)) }
    return [pscustomobject][ordered]@{
        Cidr = "$(ConvertFrom-ToolEnterpriseIPv4UInt32 -Value ([uint32]$network64))/$prefixLength"
        PrefixLength = $prefixLength
        NetworkValue = [uint32]$network64
        BroadcastValue = [uint32]$broadcast64
        HostCount = $hostCount
    }
}

function Test-ToolEnterpriseIpInCidr {
    param([Parameter(Mandatory = $true)][string]$Address, [Parameter(Mandatory = $true)][string]$Cidr)
    try {
        $info = Get-ToolEnterpriseCidrInfo -Cidr $Cidr
        $value = ConvertTo-ToolEnterpriseIPv4UInt32 -Address $Address
        return [bool](([uint64]$value -ge [uint64]$info.NetworkValue) -and ([uint64]$value -le [uint64]$info.BroadcastValue))
    } catch { return $false }
}

function Get-ToolEnterpriseCidrAddresses {
    param([Parameter(Mandatory = $true)][string]$Cidr, [int]$MaximumHosts = $script:ToolEnterpriseMaximumScanHosts)
    $info = Get-ToolEnterpriseCidrInfo -Cidr $Cidr
    if ([uint64]$info.HostCount -gt [uint64]$MaximumHosts) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.scanRangeTooLarge" @($info.Cidr, $info.HostCount, $MaximumHosts))
    }
    $start = if ($info.PrefixLength -ge 31) { [uint64]$info.NetworkValue } else { [uint64]$info.NetworkValue + 1 }
    $end = if ($info.PrefixLength -ge 31) { [uint64]$info.BroadcastValue } else { [uint64]$info.BroadcastValue - 1 }
    $addresses = New-Object System.Collections.Generic.List[string]
    for ($value = $start; $value -le $end; $value++) {
        [void]$addresses.Add((ConvertFrom-ToolEnterpriseIPv4UInt32 -Value ([uint32]$value)))
    }
    return $addresses.ToArray()
}

function ConvertTo-ToolEnterprisePrefixLength {
    param([Parameter(Mandatory = $true)][string]$SubnetMask)
    $bytes = ([Net.IPAddress]::Parse($SubnetMask)).GetAddressBytes()
    $bits = ([BitConverter]::ToString($bytes)).Replace("-", "")
    $binary = ""
    foreach ($character in $bits.ToCharArray()) {
        $binary += [Convert]::ToString([Convert]::ToInt32([string]$character, 16), 2).PadLeft(4, '0')
    }
    if ($binary -notmatch '^1*0*$') { throw (Get-ToolEnterpriseText "enterpriseCore.error.subnetMaskInvalid" @($SubnetMask)) }
    return ($binary -replace '0', '').Length
}

function Test-ToolEnterprisePrivateIPv4Address {
    param([Parameter(Mandatory = $true)][string]$Address)
    try {
        [void](ConvertTo-ToolEnterpriseIPv4UInt32 -Address $Address)
        $octets = @($Address.Split(".") | ForEach-Object { [int]$_ })
        if ($octets.Count -ne 4) { return $false }
        if ($octets[0] -eq 10) { return $true }
        if ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) { return $true }
        if ($octets[0] -eq 192 -and $octets[1] -eq 168) { return $true }
        if ($octets[0] -eq 100 -and $octets[1] -ge 64 -and $octets[1] -le 127) { return $true }
    } catch {}
    return $false
}

function Get-ToolEnterpriseLocalIPv4Profiles {
    $profiles = New-Object System.Collections.Generic.List[object]
    foreach ($adapter in @(Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue)) {
        $addresses = @($adapter.IPAddress)
        $masks = @($adapter.IPSubnet)
        $gateways = @($adapter.DefaultIPGateway)
        $hasDefaultGateway = [bool](@($gateways | Where-Object {
            [string]$_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' -and [string]$_ -ne "0.0.0.0"
        }).Count -gt 0)
        $metric = 999999
        try {
            if ($null -ne $adapter.IPConnectionMetric) { $metric = [int]$adapter.IPConnectionMetric }
        } catch {}
        $interfaceIndex = 999999
        try {
            if ($null -ne $adapter.InterfaceIndex) { $interfaceIndex = [int]$adapter.InterfaceIndex }
        } catch {}

        for ($index = 0; $index -lt $addresses.Count; $index++) {
            $address = [string]$addresses[$index]
            if ($address -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$' -or $address -match '^(0\.|127\.|169\.254\.)') { continue }
            try {
                $addressValue = ConvertTo-ToolEnterpriseIPv4UInt32 -Address $address
                $firstOctet = [int]($address.Split("."))[0]
                if ($firstOctet -ge 224) { continue }
                $mask = if ($index -lt $masks.Count -and [string]$masks[$index] -match '^\d{1,3}(?:\.\d{1,3}){3}$') {
                    [string]$masks[$index]
                } else { "255.255.255.0" }
                $prefix = ConvertTo-ToolEnterprisePrefixLength -SubnetMask $mask
                $info = Get-ToolEnterpriseCidrInfo -Cidr "$address/$prefix"
                [void]$profiles.Add([pscustomobject][ordered]@{
                    Address = $address
                    AddressValue = [uint32]$addressValue
                    PrefixLength = [int]$prefix
                    Cidr = [string]$info.Cidr
                    SubnetMask = $mask
                    HasDefaultGateway = $hasDefaultGateway
                    DefaultGateway = (@($gateways | Where-Object { [string]$_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' }) -join ",")
                    IsPrivate = (Test-ToolEnterprisePrivateIPv4Address -Address $address)
                    Metric = $metric
                    InterfaceIndex = $interfaceIndex
                    AdapterDescription = ConvertTo-ToolEnterpriseSafeText ([string]$adapter.Description) 200
                })
            } catch {}
        }
    }

    $ordered = @($profiles.ToArray() | Sort-Object -Property @{Expression={ if ([bool]$_.HasDefaultGateway) { 0 } else { 1 } }}, @{Expression={ if ([bool]$_.IsPrivate) { 0 } else { 1 } }}, @{Expression={ [int]$_.Metric }}, @{Expression={ [int]$_.InterfaceIndex }}, @{Expression={ [uint32]$_.AddressValue }})
    $result = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($profile in $ordered) {
        $key = [string]$profile.Address
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$result.Add($profile)
    }
    return $result.ToArray()
}

function Get-ToolEnterpriseLocalIPv4Addresses {
    return @((Get-ToolEnterpriseLocalIPv4Profiles) | ForEach-Object { [string]$_.Address })
}

function Get-ToolEnterprisePreferredServerAddress {
    $profiles = @(Get-ToolEnterpriseLocalIPv4Profiles)
    if ($profiles.Count -eq 0) { return "" }
    return [string]$profiles[0].Address
}

function Get-ToolEnterpriseLocalCidrs {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($profile in @(Get-ToolEnterpriseLocalIPv4Profiles)) {
        $cidr = [string]$profile.Cidr
        if (-not [string]::IsNullOrWhiteSpace($cidr) -and $result -notcontains $cidr) {
            [void]$result.Add($cidr)
        }
    }
    return $result.ToArray()
}

function Get-ToolEnterpriseLocalDiscoveryCidrs {
    param([int]$MaximumHosts = $script:ToolEnterpriseMaximumScanHosts)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($profile in @(Get-ToolEnterpriseLocalIPv4Profiles)) {
        try {
            $info = Get-ToolEnterpriseCidrInfo -Cidr ([string]$profile.Cidr)
            if ([uint64]$info.HostCount -gt [uint64]$MaximumHosts) {
                # Giới hạn dò tự động ở khối /22 chứa chính card mạng. Dải lớn
                # hơn vẫn có thể được quản trị viên nhập tay để tránh quét ồ ạt.
                $info = Get-ToolEnterpriseCidrInfo -Cidr ("{0}/22" -f [string]$profile.Address)
            }
            if ($result -notcontains [string]$info.Cidr) { [void]$result.Add([string]$info.Cidr) }
        } catch {}
    }
    return $result.ToArray()
}

function Test-ToolEnterpriseHostName {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value.Length -lt 1 -or $Value.Length -gt 253) { return $false }
    if ($Value -match '^\d{1,3}(?:\.\d{1,3}){3}$') {
        $parsed = $null
        return [Net.IPAddress]::TryParse($Value, [ref]$parsed)
    }
    return [bool]($Value -match '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')
}

function Resolve-ToolEnterpriseServerEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$ServerAddress,
        [ValidateRange(1024,65535)][int]$Port = $script:ToolEnterpriseDefaultPort
    )
    $value = $ServerAddress.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.serverAddressRequired") }
    if ($value -match '^([^:\s]+):(\d{2,5})$') {
        $value = [string]$matches[1]
        $parsedPort = [int]$matches[2]
        if ($parsedPort -lt 1024 -or $parsedPort -gt 65535) { throw (Get-ToolEnterpriseText "enterpriseCore.error.serverPortInvalid") }
        $Port = $parsedPort
    }
    if (-not (Test-ToolEnterpriseHostName -Value $value)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.serverAddressInvalid") }
    return [pscustomobject][ordered]@{ Address=$value; Port=[int]$Port; DisplayAddress=("{0}:{1}" -f $value,$Port) }
}

function Test-ToolEnterpriseTcpEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$ServerAddress,
        [ValidateRange(1024,65535)][int]$Port,
        [ValidateRange(100,10000)][int]$TimeoutMs = 1200
    )
    $client = New-Object Net.Sockets.TcpClient
    $handle = $null
    try {
        $handle = $client.BeginConnect($ServerAddress, $Port, $null, $null)
        if (-not $handle.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($handle)
        return [bool]$client.Connected
    } catch { return $false }
    finally {
        if ($handle -and $handle.AsyncWaitHandle) { try { $handle.AsyncWaitHandle.Close() } catch {} }
        $client.Close()
    }
}

function Get-ToolEnterpriseServerConfig {
    $paths = Initialize-ToolEnterpriseStorage
    return (Read-ToolEnterpriseJson -Path $paths.ServerConfig)
}

function New-ToolEnterpriseServerConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ServerName,
        [Parameter(Mandatory = $true)][string]$AdminCode,
        [string]$BindAddress = "0.0.0.0",
        [ValidateRange(1024, 65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [string[]]$AllowedCidrs = @()
    )

    $paths = Initialize-ToolEnterpriseStorage
    if (Test-Path -LiteralPath $paths.ServerConfig -PathType Leaf) { throw (Get-ToolEnterpriseText "enterpriseCore.error.serverAlreadyConfigured") }
    $safeName = ConvertTo-ToolEnterpriseSafeText $ServerName 100
    if ([string]::IsNullOrWhiteSpace($safeName)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.serverNameRequired") }
    if ($BindAddress -ne "0.0.0.0") {
        $parsedAddress = $null
        if (-not [Net.IPAddress]::TryParse($BindAddress, [ref]$parsedAddress) -or $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
            throw (Get-ToolEnterpriseText "enterpriseCore.error.bindAddressInvalid")
        }
    }
    $normalizedCidrs = New-Object System.Collections.Generic.List[string]
    foreach ($cidr in @($AllowedCidrs)) {
        if ([string]::IsNullOrWhiteSpace($cidr)) { continue }
        $normalized = (Get-ToolEnterpriseCidrInfo -Cidr $cidr.Trim()).Cidr
        if ($normalizedCidrs -notcontains $normalized) { [void]$normalizedCidrs.Add($normalized) }
    }
    if ($normalizedCidrs.Count -eq 0) {
        foreach ($localCidr in @(Get-ToolEnterpriseLocalCidrs)) { [void]$normalizedCidrs.Add($localCidr) }
    }
    if ($normalizedCidrs.Count -eq 0) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.safeCidrMissing")
    }
    $masterSecret = New-ToolEnterpriseRandomBytes -Length 32
    $pairingSecret = New-ToolEnterpriseRandomBytes -Length 24
    Set-ToolEnterpriseSecret -Path $paths.ServerMasterSecret -Secret $masterSecret
    Set-ToolEnterpriseSecret -Path $paths.ServerPairingSecret -Secret $pairingSecret
    $fingerprint = ([BitConverter]::ToString((Get-ToolEnterpriseSha256Bytes -Bytes $masterSecret))).Replace("-", "").Substring(0, 24)
    $config = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        ProtocolVersion = $script:ToolEnterpriseProtocolVersion
        Role = "Server"
        ServerId = [Guid]::NewGuid().ToString("N")
        ServerName = $safeName
        BindAddress = $BindAddress
        Port = $Port
        AllowedCidrs = $normalizedCidrs.ToArray()
        AuthorityFingerprint = $fingerprint
        AdminVerifier = New-ToolEnterpriseAdminVerifier -AdminCode $AdminCode
        PairingExpiresAtUtc = [DateTime]::UtcNow.AddHours(24).ToString("o")
        CreatedAtUtc = [DateTime]::UtcNow.ToString("o")
        UpdatedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
    Write-ToolEnterpriseJson -Path $paths.ServerConfig -Value $config
    Write-ToolEnterpriseAudit -Scope Server -Event "Server.ConfigurationCreated" -Message (Get-ToolEnterpriseText "enterpriseCore.audit.serverConfigurationCreated") -Data ([ordered]@{
        ServerId=$config.ServerId; ServerName=$config.ServerName; Port=$config.Port; AllowedCidrs=$config.AllowedCidrs; AuthorityFingerprint=$config.AuthorityFingerprint
    })
    [Array]::Clear($masterSecret, 0, $masterSecret.Length)
    return $config
}

function Test-ToolEnterpriseServerHostRunning {
    $paths = Initialize-ToolEnterpriseStorage
    $pidRecord = $null
    try { $pidRecord = Read-ToolEnterpriseJson -Path $paths.ServerPid -MaximumBytes 65536 } catch {}
    if (-not $pidRecord -or [int]$pidRecord.ProcessId -le 0) { return $false }

    $process = $null
    try { $process = Get-Process -Id ([int]$pidRecord.ProcessId) -ErrorAction Stop } catch { return $false }
    try {
        $recordedStart = [DateTime]::Parse(
            [string]$pidRecord.StartedAtUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()
        $actualStart = $process.StartTime.ToUniversalTime()
        if ([Math]::Abs(($actualStart - $recordedStart).TotalSeconds) -gt 30) {
            return $false
        }
    } catch {
        # Nếu bản ghi cũ thiếu thời gian, PID còn tồn tại vẫn được xem là đang
        # chạy để tránh xóa cấu hình dưới một server chưa dừng hẳn.
    }
    return $true
}

function Assert-ToolEnterpriseDirectoryTreeSafe {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $full = Assert-ToolEnterprisePath -Path $Directory
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return }
    if (Test-ToolEnterpriseReparsePoint -Path $full) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.deleteDirectoryReparse" @($full))
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop)) {
        [void](Assert-ToolEnterprisePath -Path $item.FullName)
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw (Get-ToolEnterpriseText "enterpriseCore.error.deleteItemReparse" @($item.FullName))
        }
        if ($item.PSIsContainer) {
            Assert-ToolEnterpriseDirectoryTreeSafe -Directory $item.FullName
        }
    }
}

function Clear-ToolEnterpriseDirectoryContent {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $full = Assert-ToolEnterprisePath -Path $Directory
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return 0 }
    Assert-ToolEnterpriseDirectoryTreeSafe -Directory $full
    $removedFileCount = 0
    foreach ($item in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop)) {
        if ($item.PSIsContainer) {
            $removedFileCount += [int](Clear-ToolEnterpriseDirectoryContent -Directory $item.FullName)
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
        } else {
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
            $removedFileCount++
        }
    }
    return $removedFileCount
}

function Remove-ToolEnterpriseFileSafe {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Assert-ToolEnterprisePath -Path $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
    if (Test-ToolEnterpriseReparsePoint -Path $full) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.deleteFileReparse" @($full))
    }
    Remove-Item -LiteralPath $full -Force -ErrorAction Stop
    return $true
}

function Remove-ToolEnterpriseServerConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$AdminCode,
        [ValidateRange(1, 30)][int]$StopTimeoutSeconds = 12
    )

    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseServerConfig
    if (-not $config) { throw (Get-ToolEnterpriseText "enterpriseCore.error.noServerConfigurationToDelete") }
    if (-not (Test-ToolEnterpriseAdminCode -AdminCode $AdminCode -Verifier $config.AdminVerifier)) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.adminCodeInvalid")
    }

    Write-ToolEnterpriseAudit -Scope Server -Event "Server.ConfigurationResetRequested" -Message (Get-ToolEnterpriseText "enterpriseCore.audit.serverConfigurationResetRequested") -Data ([ordered]@{
        ServerId=[string]$config.ServerId; ServerName=[string]$config.ServerName; Port=[int]$config.Port
    })

    New-Item -ItemType File -Path $paths.ServerStop -Force | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds($StopTimeoutSeconds)
    while ((Test-ToolEnterpriseServerHostRunning) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (Test-ToolEnterpriseServerHostRunning) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.serverStopTimeout" @($StopTimeoutSeconds))
    }

    # Kiểm tra toàn bộ cây trước khi xóa để không bao giờ đi qua
    # junction/symlink do bên ngoài chèn vào vùng dữ liệu.
    foreach ($directory in @($paths.ServerClients, $paths.ServerClientSecrets, $paths.ServerJobs)) {
        Assert-ToolEnterpriseDirectoryTreeSafe -Directory $directory
    }
    foreach ($file in @(
        $paths.ServerMasterSecret, $paths.ServerPairingSecret, $paths.ServerDashboardSession, $paths.ServerError,
        $paths.ServerPid, $paths.ServerHeartbeat, $paths.ServerConfig, $paths.ServerStop
    )) {
        $full = Assert-ToolEnterprisePath -Path $file
        if ((Test-Path -LiteralPath $full -PathType Leaf) -and (Test-ToolEnterpriseReparsePoint -Path $full)) {
            throw (Get-ToolEnterpriseText "enterpriseCore.error.deleteFileReparse" @($full))
        }
    }

    $removedClientRecords = [int](Clear-ToolEnterpriseDirectoryContent -Directory $paths.ServerClients)
    $removedClientSecrets = [int](Clear-ToolEnterpriseDirectoryContent -Directory $paths.ServerClientSecrets)
    $removedPendingJobs = [int](Clear-ToolEnterpriseDirectoryContent -Directory $paths.ServerJobs)

    foreach ($file in @(
        $paths.ServerMasterSecret, $paths.ServerPairingSecret, $paths.ServerDashboardSession, $paths.ServerError,
        $paths.ServerPid, $paths.ServerHeartbeat
    )) {
        [void](Remove-ToolEnterpriseFileSafe -Path $file)
    }

    # Xóa server.json gần cuối. Nếu một bước trước đó thất bại, marker stop
    # vẫn còn và mã quản trị vẫn có thể dùng để thử lại an toàn.
    [void](Remove-ToolEnterpriseFileSafe -Path $paths.ServerConfig)
    [void](Remove-ToolEnterpriseFileSafe -Path $paths.ServerStop)

    $auditWritten = $true
    try {
        Write-ToolEnterpriseAudit -Scope Server -Event "Server.ConfigurationResetCompleted" -Message (Get-ToolEnterpriseText "enterpriseCore.audit.serverConfigurationResetCompleted") -Data ([ordered]@{
            ServerId=[string]$config.ServerId
            ServerName=[string]$config.ServerName
            RemovedClientRecords=$removedClientRecords
            RemovedClientSecrets=$removedClientSecrets
            RemovedPendingJobs=$removedPendingJobs
            PreservedReportsPath=[string]$paths.ServerReports
            PreservedResultsPath=[string]$paths.ServerResults
            PreservedAuditPath=[string]$paths.ServerAudit
        })
    } catch { $auditWritten = $false }

    return [pscustomobject][ordered]@{
        Removed = $true
        ServerId = [string]$config.ServerId
        ServerName = [string]$config.ServerName
        Port = [int]$config.Port
        RemovedClientRecords = $removedClientRecords
        RemovedClientSecrets = $removedClientSecrets
        RemovedPendingJobs = $removedPendingJobs
        PreservedReportsPath = [string]$paths.ServerReports
        PreservedResultsPath = [string]$paths.ServerResults
        PreservedAuditPath = [string]$paths.ServerAudit
        AuditWritten = $auditWritten
    }
}

function Get-ToolEnterprisePairingCode {
    param([Parameter(Mandatory = $true)][string]$AdminCode)
    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseServerConfig
    if (-not $config) { throw (Get-ToolEnterpriseText "enterpriseCore.error.serverNotInitialized") }
    if (-not (Test-ToolEnterpriseAdminCode -AdminCode $AdminCode -Verifier $config.AdminVerifier)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.adminCodeInvalid") }
    $expires = [DateTime]::Parse([string]$config.PairingExpiresAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    if ($expires.ToUniversalTime() -lt [DateTime]::UtcNow) { throw (Get-ToolEnterpriseText "enterpriseCore.error.pairingCodeExpired") }
    $secret = Get-ToolEnterpriseSecret -Path $paths.ServerPairingSecret
    if (-not $secret) { throw (Get-ToolEnterpriseText "enterpriseCore.error.pairingSecretMissing") }
    try { return (ConvertTo-ToolEnterpriseBase64Url -Bytes $secret) }
    finally { [Array]::Clear($secret, 0, $secret.Length) }
}

function Reset-ToolEnterprisePairingCode {
    param([Parameter(Mandatory = $true)][string]$AdminCode, [ValidateRange(1, 168)][int]$ValidHours = 24)
    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseServerConfig
    if (-not $config) { throw (Get-ToolEnterpriseText "enterpriseCore.error.serverNotInitialized") }
    if (-not (Test-ToolEnterpriseAdminCode -AdminCode $AdminCode -Verifier $config.AdminVerifier)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.adminCodeInvalid") }
    $secret = New-ToolEnterpriseRandomBytes -Length 24
    Set-ToolEnterpriseSecret -Path $paths.ServerPairingSecret -Secret $secret
    $config.PairingExpiresAtUtc = [DateTime]::UtcNow.AddHours($ValidHours).ToString("o")
    $config.UpdatedAtUtc = [DateTime]::UtcNow.ToString("o")
    Write-ToolEnterpriseJson -Path $paths.ServerConfig -Value $config
    Write-ToolEnterpriseAudit -Scope Server -Event "Server.PairingCodeRotated" -Message (Get-ToolEnterpriseText "enterpriseCore.audit.pairingCodeRotated")
    try { return (ConvertTo-ToolEnterpriseBase64Url -Bytes $secret) }
    finally { [Array]::Clear($secret, 0, $secret.Length) }
}

function Get-ToolEnterpriseClientConfig {
    $paths = Initialize-ToolEnterpriseStorage
    return (Read-ToolEnterpriseJson -Path $paths.ClientConfig)
}

function Set-ToolEnterpriseClientConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ServerAddress,
        [ValidateRange(1024, 65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [bool]$AllowRemoteLicenseChanges = $false,
        [bool]$AutoSend = $true
    )

    $endpoint = Resolve-ToolEnterpriseServerEndpoint -ServerAddress $ServerAddress -Port $Port
    $ServerAddress = [string]$endpoint.Address
    $Port = [int]$endpoint.Port
    $paths = Initialize-ToolEnterpriseStorage
    $existing = Get-ToolEnterpriseClientConfig
    # Keep the GUID parsing compatible with Windows PowerShell 3/5.1.  An
    # inline cast inside [ref] is rejected by older parsers and can make a
    # workstation fail before it ever reaches the enrollment screen.
    $existingGuid = [Guid]::Empty
    $hasExistingGuid = $false
    if ($existing -and -not [string]::IsNullOrWhiteSpace([string]$existing.ClientId)) {
        $hasExistingGuid = [Guid]::TryParse([string]$existing.ClientId, [ref]$existingGuid)
    }
    $clientId = if ($hasExistingGuid) {
        $existingGuid.ToString("N")
    } else { [Guid]::NewGuid().ToString("N") }
    $config = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        ProtocolVersion = $script:ToolEnterpriseProtocolVersion
        Role = "Client"
        ClientId = $clientId
        ComputerName = [Environment]::MachineName
        ServerAddress = $ServerAddress.Trim()
        Port = $Port
        ServerId = if ($existing) { [string]$existing.ServerId } else { "" }
        Enrolled = [bool]($existing -and $existing.Enrolled -and (Test-Path -LiteralPath $paths.ClientSecret -PathType Leaf))
        AllowRemoteLicenseChanges = [bool]$AllowRemoteLicenseChanges
        AutoSend = [bool]$AutoSend
        EnrolledAtUtc = if ($existing) { [string]$existing.EnrolledAtUtc } else { "" }
        UpdatedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
    Write-ToolEnterpriseJson -Path $paths.ClientConfig -Value $config
    return $config
}

function Get-ToolEnterpriseLicenseStatusText {
    param([int]$Status)
    switch ($Status) {
        0 { "Unlicensed" }
        1 { "Activated" }
        2 { "OOBGrace" }
        3 { "OOTGrace" }
        4 { "NonGenuineGrace" }
        5 { "Notification" }
        6 { "ExtendedGrace" }
        default { "Unknown" }
    }
}

function Get-ToolEnterpriseLicenseChannel {
    param([string]$Description)
    if ($Description -match '(?i)VOLUME_KMSCLIENT') { return "VOLUME_KMSCLIENT" }
    if ($Description -match '(?i)VOLUME_MAK') { return "VOLUME_MAK" }
    if ($Description -match '(?i)OEM') { return "OEM" }
    if ($Description -match '(?i)RETAIL') { return "RETAIL" }
    if ($Description -match '(?i)SUBSCRIPTION') { return "SUBSCRIPTION" }
    return "UNKNOWN"
}

function Get-ToolEnterpriseLicensingProducts {
    $products = @()
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $products = @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction Stop)
        } else {
            $products = @(Get-WmiObject -Class SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction Stop)
        }
    } catch {
        try { $products = @(Get-WmiObject -Class SoftwareLicensingProduct -ErrorAction Stop | Where-Object PartialProductKey) }
        catch { $products = @() }
    }
    return $products
}

function ConvertTo-ToolEnterpriseLicenseRecord {
    param([Parameter(Mandatory = $true)][object]$Product)
    return [pscustomobject][ordered]@{
        Name = ConvertTo-ToolEnterpriseSafeText $Product.Name 300
        Description = ConvertTo-ToolEnterpriseSafeText $Product.Description 500
        LicenseStatus = [int]$Product.LicenseStatus
        LicenseStatusText = Get-ToolEnterpriseLicenseStatusText -Status ([int]$Product.LicenseStatus)
        Channel = Get-ToolEnterpriseLicenseChannel -Description ([string]$Product.Description)
        PartialProductKey = ConvertTo-ToolEnterpriseSafeText $Product.PartialProductKey 5
        ProductId = ConvertTo-ToolEnterpriseSafeText $Product.ID 80
        ApplicationId = ConvertTo-ToolEnterpriseSafeText $Product.ApplicationID 80
        KmsServer = ConvertTo-ToolEnterpriseSafeText $Product.KeyManagementServiceMachine 255
        GraceMinutes = if ($null -ne $Product.GracePeriodRemaining) { [int64]$Product.GracePeriodRemaining } else { 0 }
    }
}

function Get-ToolEnterpriseAssetIdentitySnapshot {
    if (-not (Get-Command Get-ToolDeviceIdentitySnapshot -ErrorAction SilentlyContinue)) { return $null }
    try {
        $computerProduct = Get-WmiObject -Class Win32_ComputerSystemProduct -ErrorAction SilentlyContinue | Select-Object -First 1
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -First 1
        $bios = Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue | Select-Object -First 1
        $baseboard = Get-WmiObject -Class Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
        $enclosure = Get-WmiObject -Class Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -First 1
        $machineGuid = ''
        try { $machineGuid = [string](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop) } catch {}
        $observation = [pscustomobject][ordered]@{
            SystemUuid = if ($computerProduct) { [string]$computerProduct.UUID } else { '' }
            SystemSerialNumber = if ($computerProduct) { [string]$computerProduct.IdentifyingNumber } else { '' }
            BiosSerialNumber = if ($bios) { [string]$bios.SerialNumber } else { '' }
            BaseboardSerialNumber = if ($baseboard) { [string]$baseboard.SerialNumber } else { '' }
            ChassisSerialNumber = if ($enclosure) { [string](@($enclosure.SerialNumber) | Select-Object -First 1) } else { '' }
            MachineGuid = $machineGuid
            Manufacturer = if ($computerSystem) { [string]$computerSystem.Manufacturer } elseif ($computerProduct) { [string]$computerProduct.Vendor } else { '' }
            Model = if ($computerSystem) { [string]$computerSystem.Model } elseif ($computerProduct) { [string]$computerProduct.Name } else { '' }
            ComputerName = [Environment]::MachineName
        }
        return (Get-ToolDeviceIdentitySnapshot -Observation $observation)
    } catch {
        return $null
    }
}

function Update-ToolEnterpriseAssetRegistryFromReport {
    param([Parameter(Mandatory=$true)][object]$Report)
    if (-not (Get-Command Register-ToolAssetIdentitySnapshot -ErrorAction SilentlyContinue) -or
        -not $Report.PSObject.Properties['AssetIdentity'] -or $null -eq $Report.AssetIdentity) {
        return [pscustomobject][ordered]@{ Status='Missing'; DeviceId=''; AssetId=''; CurrentAssignment=$null; HistoryCount=0 }
    }
    $paths = Initialize-ToolEnterpriseStorage
    $store = Read-ToolAssetRegistryStore -RootPath $paths.ServerAssets -CreateIfMissing
    $result = Register-ToolAssetIdentitySnapshot -Store $store -IdentitySnapshot $Report.AssetIdentity -ObservedAtUtc $Report.CreatedAt
    if ([bool]$result.Changed) { [void](Write-ToolAssetRegistryStore -Store $store -RootPath $paths.ServerAssets) }
    $current = $null
    $historyCount = 0
    if (-not [string]::IsNullOrWhiteSpace([string]$result.AssetId)) {
        $current = Get-ToolCurrentAssetAssignment -Store $store -AssetId ([string]$result.AssetId)
        $historyCount = @(Get-ToolAssetAssignmentHistory -Store $store -AssetId ([string]$result.AssetId)).Count
    }
    return [pscustomobject][ordered]@{
        Status=[string]$result.Status; DeviceId=[string]$result.DeviceId; AssetId=[string]$result.AssetId
        CurrentAssignment=$current; HistoryCount=$historyCount
    }
}

function Get-ToolEnterpriseAssetReference {
    param([AllowNull()][object]$Asset)
    if ($null -eq $Asset) { return '' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Asset.ExternalAssetTag)) { return (ConvertTo-ToolEnterpriseSafeText $Asset.ExternalAssetTag 120) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Asset.InventoryNumber)) { return (ConvertTo-ToolEnterpriseSafeText $Asset.InventoryNumber 120) }
    $assetId = [string]$Asset.AssetId
    if ($assetId.Length -ge 8) { return ('ASSET-' + $assetId.Substring($assetId.Length - 8)) }
    return 'ASSET'
}

function Get-ToolEnterpriseLicenseSnapshot {
    param([string]$ClientId = "")

    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        $config = Get-ToolEnterpriseClientConfig
        $ClientId = if ($config) { [string]$config.ClientId } else { [Guid]::NewGuid().ToString("N") }
    }
    $currentVersion = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
    $productName = if ($currentVersion.ProductName) { [string]$currentVersion.ProductName } else { "Windows" }
    $build = if ($currentVersion.CurrentBuildNumber) { [string]$currentVersion.CurrentBuildNumber } else { [string][Environment]::OSVersion.Version.Build }
    if ([int64]$build -ge 22000 -and $productName -match "Windows 10") { $productName = $productName -replace "Windows 10", "Windows 11" }
    $allProducts = @(Get-ToolEnterpriseLicensingProducts)
    $windowsLicenses = @($allProducts | Where-Object { $_.Name -match "Windows" } | Sort-Object LicenseStatus -Descending | ForEach-Object { ConvertTo-ToolEnterpriseLicenseRecord $_ })
    $officeLicenses = @($allProducts | Where-Object { $_.Name -match "Office" } | Sort-Object LicenseStatus -Descending | ForEach-Object { ConvertTo-ToolEnterpriseLicenseRecord $_ })
    $networkAddresses = New-Object System.Collections.Generic.List[string]
    foreach ($adapter in @(Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue)) {
        foreach ($address in @($adapter.IPAddress)) {
            if ([string]$address -match '^\d{1,3}(?:\.\d{1,3}){3}$' -and $address -notmatch '^(127\.|169\.254\.)') {
                if ($networkAddresses -notcontains [string]$address) { [void]$networkAddresses.Add([string]$address) }
            }
        }
    }
    $officeConfiguration = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
    if (-not $officeConfiguration) {
        $officeConfiguration = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
    }
    $capability = if (Get-Command Get-ToolCapabilityProfile -ErrorAction SilentlyContinue) { Get-ToolCapabilityProfile } else { $null }
    $softwareInventory = if (Get-Command Get-ToolLicenseComplianceSoftwareInventory -ErrorAction SilentlyContinue) {
        @(Get-ToolLicenseComplianceSoftwareInventory -MaximumItems 300)
    } else { @() }
    $assetIdentity = Get-ToolEnterpriseAssetIdentitySnapshot
    $data = [ordered]@{
        CreatedAt = [DateTime]::UtcNow.ToString("o")
        ClientId = $ClientId
        ComputerName = [Environment]::MachineName
        Domain = ConvertTo-ToolEnterpriseSafeText $env:USERDOMAIN 180
        NetworkAddresses = $networkAddresses.ToArray()
        OperatingSystem = [ordered]@{
            ProductName = $productName
            Edition = ConvertTo-ToolEnterpriseSafeText $currentVersion.EditionID 100
            DisplayVersion = ConvertTo-ToolEnterpriseSafeText $(if ($currentVersion.DisplayVersion) { $currentVersion.DisplayVersion } else { $currentVersion.ReleaseId }) 80
            BuildNumber = $build
            Architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
        }
        CompatibilityTier = if ($capability) { [string]$capability.CompatibilityTier } else { "Unknown" }
        WindowsLicenses = $windowsLicenses
        OfficeLicenses = $officeLicenses
        SoftwareInventory = $softwareInventory
        AssetIdentity = $assetIdentity
        OfficeInstallation = [ordered]@{
            ProductReleaseIds = ConvertTo-ToolEnterpriseSafeText $(if ($officeConfiguration -and $officeConfiguration.PSObject.Properties['ProductReleaseIds']) { $officeConfiguration.ProductReleaseIds } else { '' }) 400
            Version = ConvertTo-ToolEnterpriseSafeText $(if ($officeConfiguration -and $officeConfiguration.PSObject.Properties['VersionToReport']) { $officeConfiguration.VersionToReport } else { '' }) 80
            Platform = ConvertTo-ToolEnterpriseSafeText $(if ($officeConfiguration -and $officeConfiguration.PSObject.Properties['Platform']) { $officeConfiguration.Platform } else { '' }) 40
        }
        Privacy = [ordered]@{
            FullProductKeyIncluded = $false
            UserNameIncluded = $false
            MacAddressIncluded = $false
            SoftwarePathsIncluded = $false
            SoftwareLicenseKeysIncluded = $false
            RawHardwareIdentifiersIncluded = $false
            HashedAssetIdentityIncluded = [bool]($null -ne $assetIdentity)
        }
    }
    if (Get-Command New-ToolReportEnvelope -ErrorAction SilentlyContinue) {
        return (New-ToolReportEnvelope -ReportKind "EnterpriseInventory" -ToolVersion $script:ToolEnterpriseToolVersion -Data $data)
    }
    return [pscustomobject]$data
}

function Get-ToolEnterpriseBaseUri {
    param([Parameter(Mandatory = $true)][string]$ServerAddress, [ValidateRange(1024,65535)][int]$Port)
    $endpoint = Resolve-ToolEnterpriseServerEndpoint -ServerAddress $ServerAddress -Port $Port
    return "http://$($endpoint.Address)`:$($endpoint.Port)/tool/v1"
}

function Invoke-ToolEnterpriseHttpRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("GET", "POST")][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [AllowNull()][object]$Body = $null,
        [hashtable]$Headers = @{},
        [ValidateRange(500, 30000)][int]$TimeoutMs = 5000
    )

    if ($Uri -notmatch '^http://[A-Za-z0-9.\-]+:\d{2,5}/tool/v1(?:/[A-Za-z0-9\-]+)?$') { throw (Get-ToolEnterpriseText "enterpriseCore.error.uriInvalid") }
    $request = [Net.HttpWebRequest]::Create($Uri)
    $request.Method = $Method
    $request.Timeout = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $request.AllowAutoRedirect = $false
    $request.Proxy = $null
    $request.UserAgent = "ThanhViet-VietLicenSure/$($script:ToolEnterpriseToolVersion)"
    foreach ($name in $Headers.Keys) { $request.Headers[[string]$name] = [string]$Headers[$name] }
    $response = $null
    try {
        if ($Method -eq "POST") {
            $json = if ($null -eq $Body) { "{}" } else { $Body | ConvertTo-Json -Depth 14 -Compress }
            $bytes = [Text.Encoding]::UTF8.GetBytes($json)
            if ($bytes.Length -gt $script:ToolEnterpriseMaximumRequestBytes) { throw (Get-ToolEnterpriseText "enterpriseCore.error.requestTooLarge") }
            $request.ContentType = "application/json; charset=utf-8"
            $request.ContentLength = $bytes.Length
            $stream = $request.GetRequestStream()
            try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        }
        try {
            $response = [Net.HttpWebResponse]$request.GetResponse()
        } catch [Net.WebException] {
            if ($_.Exception.Response) { $response = [Net.HttpWebResponse]$_.Exception.Response }
            else { throw }
        }
        try {
            $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
            try { $responseText = $reader.ReadToEnd() } finally { $reader.Dispose() }
            if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
                throw (Get-ToolEnterpriseText "enterpriseCore.error.httpResponse" @([int]$response.StatusCode, (ConvertTo-ToolEnterpriseSafeText $responseText 500)))
            }
            if ([string]::IsNullOrWhiteSpace($responseText)) { return $null }
            return ($responseText | ConvertFrom-Json)
        } finally { if ($response) { $response.Close(); $response=$null } }
    } catch [Net.WebException] {
        $messageKey = if ($_.Exception.Status -eq [Net.WebExceptionStatus]::Timeout) { 'enterpriseCore.error.networkTimeout' } else { 'enterpriseCore.error.networkUnavailable' }
        throw (Get-ToolEnterpriseText $messageKey)
    } finally { if ($response) { try { $response.Close() } catch {} } }
}

function Get-ToolEnterpriseConnectionDiagnostic {
    param(
        [Parameter(Mandatory = $true)][string]$ServerAddress,
        [ValidateRange(1024,65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [ValidateRange(200,10000)][int]$TimeoutMs = 1500
    )
    try { $endpoint = Resolve-ToolEnterpriseServerEndpoint -ServerAddress $ServerAddress -Port $Port }
    catch { return [pscustomobject][ordered]@{ Success=$false; Code='InvalidEndpoint'; Message=[string]$_.Exception.Message; Address=''; Port=$Port; Status=$null } }
    if (-not (Test-ToolEnterpriseTcpEndpoint -ServerAddress $endpoint.Address -Port $endpoint.Port -TimeoutMs $TimeoutMs)) {
        return [pscustomobject][ordered]@{ Success=$false; Code='TcpUnavailable'; Message=(Get-ToolEnterpriseText 'enterpriseCore.connection.tcpUnavailable' @($endpoint.DisplayAddress)); Address=$endpoint.Address; Port=$endpoint.Port; Status=$null }
    }
    try {
        $status = Invoke-ToolEnterpriseHttpRequest -Method GET -Uri "$(Get-ToolEnterpriseBaseUri -ServerAddress $endpoint.Address -Port $endpoint.Port)/status" -TimeoutMs $TimeoutMs
    } catch {
        return [pscustomobject][ordered]@{ Success=$false; Code='ServiceUnavailable'; Message=(Get-ToolEnterpriseText 'enterpriseCore.connection.serviceUnavailable' @($endpoint.DisplayAddress)); Address=$endpoint.Address; Port=$endpoint.Port; Status=$null }
    }
    if (-not $status -or -not [bool]$status.Accepted) {
        return [pscustomobject][ordered]@{ Success=$false; Code='ServiceRejected'; Message=(Get-ToolEnterpriseText 'enterpriseCore.connection.serviceRejected' @($endpoint.DisplayAddress)); Address=$endpoint.Address; Port=$endpoint.Port; Status=$status }
    }
    if ([string]$status.ProtocolVersion -ne $script:ToolEnterpriseProtocolVersion) {
        return [pscustomobject][ordered]@{ Success=$false; Code='ProtocolMismatch'; Message=(Get-ToolEnterpriseText 'enterpriseCore.connection.protocolMismatch' @([string]$status.ProtocolVersion,$script:ToolEnterpriseProtocolVersion)); Address=$endpoint.Address; Port=$endpoint.Port; Status=$status }
    }
    if ([string]$status.ToolVersion -ne $script:ToolEnterpriseToolVersion) {
        return [pscustomobject][ordered]@{ Success=$false; Code='VersionMismatch'; Message=(Get-ToolEnterpriseText 'enterpriseCore.connection.versionMismatch' @([string]$status.ToolVersion,$script:ToolEnterpriseToolVersion)); Address=$endpoint.Address; Port=$endpoint.Port; Status=$status }
    }
    return [pscustomobject][ordered]@{ Success=$true; Code='Connected'; Message=(Get-ToolEnterpriseText 'enterpriseCore.connection.connected' @($endpoint.DisplayAddress,$status.ProtocolVersion)); Address=$endpoint.Address; Port=$endpoint.Port; Status=$status }
}

function Test-ToolEnterpriseServerConnection {
    param(
        [Parameter(Mandatory = $true)][string]$ServerAddress,
        [ValidateRange(1024,65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [int]$TimeoutMs = 1200
    )
    $diagnostic = Get-ToolEnterpriseConnectionDiagnostic -ServerAddress $ServerAddress -Port $Port -TimeoutMs $TimeoutMs
    if (-not $diagnostic.Success) { return $null }
    return $diagnostic.Status
}

function Register-ToolEnterpriseClient {
    param(
        [Parameter(Mandatory = $true)][string]$ServerAddress,
        [ValidateRange(1024,65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [Parameter(Mandatory = $true)][string]$PairingCode,
        [bool]$AllowRemoteLicenseChanges = $false,
        [bool]$AutoSend = $true
    )

    $pairingSecret = ConvertFrom-ToolEnterpriseBase64Url -Text $PairingCode.Trim()
    if ($pairingSecret.Length -lt 20) { throw (Get-ToolEnterpriseText "enterpriseCore.error.pairingCodeInvalid") }
    $paths = Initialize-ToolEnterpriseStorage
    $config = Set-ToolEnterpriseClientConfiguration -ServerAddress $ServerAddress -Port $Port -AllowRemoteLicenseChanges:$AllowRemoteLicenseChanges -AutoSend:$AutoSend
    $requestPayload = [ordered]@{
        ClientId = $config.ClientId
        ComputerName = $config.ComputerName
        ToolVersion = $script:ToolEnterpriseToolVersion
        ProtocolVersion = $script:ToolEnterpriseProtocolVersion
        AllowRemoteLicenseChanges = [bool]$AllowRemoteLicenseChanges
        NetworkAddresses = @((Get-ToolEnterpriseLicenseSnapshot -ClientId $config.ClientId).NetworkAddresses)
    }
    $envelope = New-ToolEnterpriseEnvelope -Secret $pairingSecret -Context "enroll" -Payload $requestPayload
    $baseUri = Get-ToolEnterpriseBaseUri -ServerAddress $ServerAddress -Port $Port
    $responseEnvelope = Invoke-ToolEnterpriseHttpRequest -Method POST -Uri "$baseUri/enroll" -Body $envelope -TimeoutMs 8000
    $opened = Open-ToolEnterpriseEnvelope -Secret $pairingSecret -ExpectedContext "enroll-response:$($config.ClientId)" -Envelope $responseEnvelope -MaximumAgeMinutes 10
    $response = $opened.Payload
    if (-not [bool]$response.Accepted) { throw (Get-ToolEnterpriseText "enterpriseCore.error.enrollmentRejected" @((ConvertTo-ToolEnterpriseSafeText $response.Message 500))) }
    $clientSecret = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$response.ClientSecret)
    if ($clientSecret.Length -ne 32) { throw (Get-ToolEnterpriseText "enterpriseCore.error.clientSecretInvalid") }
    Set-ToolEnterpriseSecret -Path $paths.ClientSecret -Secret $clientSecret
    $config.ServerId = [string]$response.ServerId
    $config.Enrolled = $true
    $config.EnrolledAtUtc = [DateTime]::UtcNow.ToString("o")
    $config.UpdatedAtUtc = [DateTime]::UtcNow.ToString("o")
    Write-ToolEnterpriseJson -Path $paths.ClientConfig -Value $config
    Write-ToolEnterpriseAudit -Scope Client -Event "Client.Enrolled" -Message (Get-ToolEnterpriseText "enterpriseCore.audit.clientEnrolled") -Data ([ordered]@{
        ClientId=$config.ClientId; ServerId=$config.ServerId; ServerAddress=$config.ServerAddress; Port=$config.Port; RemoteChanges=[bool]$config.AllowRemoteLicenseChanges
    })
    [Array]::Clear($clientSecret, 0, $clientSecret.Length)
    [Array]::Clear($pairingSecret, 0, $pairingSecret.Length)
    return $config
}

function Add-ToolEnterpriseOutboxReport {
    param([Parameter(Mandatory = $true)][object]$Report)
    $paths = Initialize-ToolEnterpriseStorage
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Report | ConvertTo-Json -Depth 14 -Compress))
    $protected = Protect-ToolEnterpriseBytes -Bytes $bytes
    $path = Join-Path $paths.ClientOutbox (([DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")) + "-" + [Guid]::NewGuid().ToString("N") + ".queue")
    [IO.File]::WriteAllBytes($path, $protected)
    [Array]::Clear($bytes, 0, $bytes.Length)
    return $path
}

function Send-ToolEnterpriseReport {
    param([Parameter(Mandatory = $true)][object]$Report, [switch]$QueueOnFailure)
    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseClientConfig
    if (-not $config -or -not [bool]$config.Enrolled) { throw (Get-ToolEnterpriseText "enterpriseCore.error.clientNotEnrolled") }
    $clientSecret = Get-ToolEnterpriseSecret -Path $paths.ClientSecret
    if (-not $clientSecret) { throw (Get-ToolEnterpriseText "enterpriseCore.error.clientSecretMissing") }
    try {
        $context = "report:$([string]$config.ClientId)"
        $envelope = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context $context -Payload $Report
        $baseUri = Get-ToolEnterpriseBaseUri -ServerAddress ([string]$config.ServerAddress) -Port ([int]$config.Port)
        $responseEnvelope = Invoke-ToolEnterpriseHttpRequest -Method POST -Uri "$baseUri/report" -Body $envelope -Headers @{ "X-Tool-ClientId"=[string]$config.ClientId } -TimeoutMs 8000
        $opened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext "report-response:$([string]$config.ClientId)" -Envelope $responseEnvelope
        if (-not [bool]$opened.Payload.Accepted) { throw (Get-ToolEnterpriseText "enterpriseCore.error.reportRejected") }
        return $opened.Payload
    } catch {
        if ($QueueOnFailure) {
            [void](Add-ToolEnterpriseOutboxReport -Report $Report)
            Write-ToolEnterpriseAudit -Scope Client -Event "Report.Queued" -Message $_.Exception.Message
        }
        throw
    } finally { [Array]::Clear($clientSecret, 0, $clientSecret.Length) }
}

function Get-ToolEnterpriseClientJob {
    <#
      Ask the server for the oldest pending job.  The server returns the job
      envelope (already encrypted with the per-client secret) inside a second
      response envelope, so a network observer cannot learn either the
      operation or a product key.
    #>
    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseClientConfig
    if (-not $config -or -not [bool]$config.Enrolled) { throw (Get-ToolEnterpriseText "enterpriseCore.error.clientNotEnrolled") }
    $clientSecret = Get-ToolEnterpriseSecret -Path $paths.ClientSecret
    if (-not $clientSecret) { throw (Get-ToolEnterpriseText "enterpriseCore.error.clientSecretMissing") }
    try {
        $clientId = [string]$config.ClientId
        $request = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context "poll:$clientId" -Payload ([ordered]@{
            ClientId = $clientId
            ComputerName = [Environment]::MachineName
            ToolVersion = $script:ToolEnterpriseToolVersion
        })
        $baseUri = Get-ToolEnterpriseBaseUri -ServerAddress ([string]$config.ServerAddress) -Port ([int]$config.Port)
        $responseEnvelope = Invoke-ToolEnterpriseHttpRequest -Method POST -Uri "$baseUri/poll" -Body $request -Headers @{ "X-Tool-ClientId"=$clientId } -TimeoutMs 8000
        $opened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext "poll-response:$clientId" -Envelope $responseEnvelope
        return $opened.Payload
    } finally { [Array]::Clear($clientSecret, 0, $clientSecret.Length) }
}

function Send-ToolEnterpriseJobResult {
    param([Parameter(Mandatory = $true)][object]$Result)

    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseClientConfig
    if (-not $config -or -not [bool]$config.Enrolled) { throw (Get-ToolEnterpriseText "enterpriseCore.error.clientNotEnrolled") }
    $clientSecret = Get-ToolEnterpriseSecret -Path $paths.ClientSecret
    if (-not $clientSecret) { throw (Get-ToolEnterpriseText "enterpriseCore.error.clientSecretMissing") }
    try {
        $clientId = [string]$config.ClientId
        $request = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context "result:$clientId" -Payload $Result
        $baseUri = Get-ToolEnterpriseBaseUri -ServerAddress ([string]$config.ServerAddress) -Port ([int]$config.Port)
        $responseEnvelope = Invoke-ToolEnterpriseHttpRequest -Method POST -Uri "$baseUri/result" -Body $request -Headers @{ "X-Tool-ClientId"=$clientId } -TimeoutMs 8000
        $opened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext "result-response:$clientId" -Envelope $responseEnvelope
        if (-not [bool]$opened.Payload.Accepted) { throw (Get-ToolEnterpriseText "enterpriseCore.error.jobResultRejected") }
        return $opened.Payload
    } finally { [Array]::Clear($clientSecret, 0, $clientSecret.Length) }
}

function Flush-ToolEnterpriseOutbox {
    $paths = Initialize-ToolEnterpriseStorage
    $sent = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $paths.ClientOutbox -Filter "*.queue" -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 100)) {
        try {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint -or $file.Length -gt 2097152) { throw (Get-ToolEnterpriseText "enterpriseCore.error.queueFileUnsafe") }
            $plain = Unprotect-ToolEnterpriseBytes -Bytes ([IO.File]::ReadAllBytes($file.FullName))
            $report = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
            [void](Send-ToolEnterpriseReport -Report $report)
            Remove-Item -LiteralPath $file.FullName -Force
            $sent++
        } catch { break }
        finally { if ($plain) { [Array]::Clear($plain, 0, $plain.Length) } }
    }
    return $sent
}

function Get-ToolEnterpriseServerClientSecretPath {
    param([Parameter(Mandatory = $true)][string]$ClientId)
    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($ClientId, [ref]$parsed)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.clientIdInvalid") }
    $paths = Initialize-ToolEnterpriseStorage
    return (Join-Path $paths.ServerClientSecrets ($parsed.ToString("N") + ".bin"))
}

function Set-ToolEnterpriseServerClientSecret {
    param([Parameter(Mandatory = $true)][string]$ClientId, [Parameter(Mandatory = $true)][byte[]]$Secret)
    Set-ToolEnterpriseSecret -Path (Get-ToolEnterpriseServerClientSecretPath -ClientId $ClientId) -Secret $Secret
}

function Get-ToolEnterpriseServerClientSecret {
    param([Parameter(Mandatory = $true)][string]$ClientId)
    return (Get-ToolEnterpriseSecret -Path (Get-ToolEnterpriseServerClientSecretPath -ClientId $ClientId))
}

function Get-ToolEnterpriseServerClientRecordPath {
    param([Parameter(Mandatory = $true)][string]$ClientId)
    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($ClientId, [ref]$parsed)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.clientIdInvalid") }
    $paths = Initialize-ToolEnterpriseStorage
    return (Join-Path $paths.ServerClients ($parsed.ToString("N") + ".json"))
}

function Save-ToolEnterpriseServerReport {
    param(
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][object]$Report,
        [string]$RemoteAddress = ""
    )

    $paths = Initialize-ToolEnterpriseStorage
    if (Get-Command Test-ToolReportEnvelope -ErrorAction SilentlyContinue) {
        $validation = Test-ToolReportEnvelope -Report $Report -ExpectedReportKind "EnterpriseInventory" -ExpectedToolVersion $script:ToolEnterpriseToolVersion
        if (-not $validation.Valid) { throw (Get-ToolEnterpriseText "enterpriseCore.error.reportInvalid" @(($validation.Errors -join '; '))) }
    }
    if ([string]$Report.ClientId -ne $ClientId) { throw (Get-ToolEnterpriseText "enterpriseCore.error.reportClientIdMismatch") }
    $clientDirectory = Join-Path $paths.ServerReports $ClientId
    if (-not (Test-Path -LiteralPath $clientDirectory -PathType Container)) { New-Item -ItemType Directory -Path $clientDirectory -Force | Out-Null }
    $timestampName = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmssfff")
    $historyPath = Join-Path $clientDirectory ($timestampName + ".json")
    $latestPath = Join-Path $clientDirectory "latest.json"
    Write-ToolEnterpriseJson -Path $historyPath -Value $Report
    Write-ToolEnterpriseJson -Path $latestPath -Value $Report
    [IO.File]::WriteAllText($latestPath + ".sha256", (Get-ToolEnterpriseSha256Hex -Path $latestPath), (New-Object Text.UTF8Encoding($false)))
    $windows = @($Report.WindowsLicenses | Select-Object -First 1)
    $office = @($Report.OfficeLicenses | Select-Object -First 1)
    $existingRecord = Read-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $ClientId)
    $windowsLast5 = if ($windows.Count -gt 0) { [string]$windows[0].PartialProductKey } else { "" }
    $officeLast5 = if ($office.Count -gt 0) { [string]$office[0].PartialProductKey } else { "" }
    $windowsIdentityChanged = [bool]($existingRecord -and -not [string]::IsNullOrWhiteSpace([string]$existingRecord.WindowsLast5) -and
        -not [string]::IsNullOrWhiteSpace($windowsLast5) -and [string]$existingRecord.WindowsLast5 -ne $windowsLast5)
    $officeIdentityChanged = [bool]($existingRecord -and -not [string]::IsNullOrWhiteSpace([string]$existingRecord.OfficeLast5) -and
        -not [string]::IsNullOrWhiteSpace($officeLast5) -and [string]$existingRecord.OfficeLast5 -ne $officeLast5)
    $assetRegistration = Update-ToolEnterpriseAssetRegistryFromReport -Report $Report
    $assetAssignment = $assetRegistration.CurrentAssignment
    $identityChangedAtUtc = if ($windowsIdentityChanged -or $officeIdentityChanged) {
        [DateTime]::UtcNow.ToString("o")
    } elseif ($existingRecord -and $existingRecord.PSObject.Properties['LicenseIdentityChangedAtUtc']) {
        [string]$existingRecord.LicenseIdentityChangedAtUtc
    } else { "" }
    $record = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ClientId = $ClientId
        ComputerName = ConvertTo-ToolEnterpriseSafeText $Report.ComputerName 100
        RemoteAddress = ConvertTo-ToolEnterpriseSafeText $RemoteAddress 80
        NetworkAddresses = @($Report.NetworkAddresses)
        LastSeenUtc = [DateTime]::UtcNow.ToString("o")
        FirstSeenUtc = if ($existingRecord) { [string]$existingRecord.FirstSeenUtc } else { [DateTime]::UtcNow.ToString("o") }
        AllowRemoteLicenseChanges = if ($existingRecord) { [bool]$existingRecord.AllowRemoteLicenseChanges } else { $false }
        WindowsStatus = if ($windows.Count -gt 0) { [string]$windows[0].LicenseStatusText } else { "NotDetected" }
        WindowsChannel = if ($windows.Count -gt 0) { [string]$windows[0].Channel } else { "" }
        WindowsLast5 = $windowsLast5
        WindowsEntitlementStatus = "NotVerified"
        WindowsIdentityChanged = $windowsIdentityChanged
        OfficeStatus = if ($office.Count -gt 0) { [string]$office[0].LicenseStatusText } else { "NotDetected" }
        OfficeChannel = if ($office.Count -gt 0) { [string]$office[0].Channel } else { "" }
        OfficeLast5 = $officeLast5
        OfficeEntitlementStatus = "NotVerified"
        OfficeIdentityChanged = $officeIdentityChanged
        LicenseIdentityChangedAtUtc = $identityChangedAtUtc
        AssetMatchStatus = ConvertTo-ToolEnterpriseSafeText $assetRegistration.Status 40
        DeviceId = ConvertTo-ToolEnterpriseSafeText $assetRegistration.DeviceId 80
        AssetId = ConvertTo-ToolEnterpriseSafeText $assetRegistration.AssetId 80
        AssignmentType = if ($assetAssignment) { ConvertTo-ToolEnterpriseSafeText $assetAssignment.AssigneeType 40 } else { '' }
        AssignmentDisplayName = if ($assetAssignment) { ConvertTo-ToolEnterpriseSafeText $assetAssignment.DisplayName 200 } else { '' }
        AssignmentHistoryCount = [int]$assetRegistration.HistoryCount
        LatestReportPath = $latestPath
    }
    Write-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $ClientId) -Value $record
    return $record
}

function Get-ToolEnterpriseServerClients {
    $paths = Initialize-ToolEnterpriseStorage
    $clients = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $paths.ServerClients -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        try {
            $record = Read-ToolEnterpriseJson -Path $file.FullName
            if ($record) { [void]$clients.Add($record) }
        } catch {}
    }
    return @($clients.ToArray() | Sort-Object ComputerName, ClientId)
}

function New-ToolEnterpriseDashboardSession {
    param(
        [Parameter(Mandatory = $true)][string]$AdminCode,
        [ValidateRange(5, 120)][int]$ValidMinutes = 30
    )

    $paths = Initialize-ToolEnterpriseStorage
    $configuration = Get-ToolEnterpriseServerConfig
    if (-not $configuration -or [string]$configuration.Role -ne "Server") {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.serverNotInitialized")
    }
    if (-not (Test-ToolEnterpriseAdminCode -AdminCode $AdminCode -Verifier $configuration.AdminVerifier)) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.adminCodeInvalid")
    }

    $tokenBytes = New-ToolEnterpriseRandomBytes -Length 32
    try {
        $token = ConvertTo-ToolEnterpriseBase64Url -Bytes $tokenBytes
        $tokenTextBytes = [Text.Encoding]::UTF8.GetBytes($token)
        try { $tokenHash = Get-ToolEnterpriseSha256Bytes -Bytes $tokenTextBytes }
        finally { [Array]::Clear($tokenTextBytes, 0, $tokenTextBytes.Length) }
        try {
            $now = [DateTime]::UtcNow
            $record = [pscustomobject][ordered]@{
                SchemaVersion = $script:ToolEnterpriseSchemaVersion
                ToolVersion = $script:ToolEnterpriseToolVersion
                SessionId = [Guid]::NewGuid().ToString("N")
                TokenHash = ConvertTo-ToolEnterpriseBase64Url -Bytes $tokenHash
                CreatedAtUtc = $now.ToString("o")
                ExpiresAtUtc = $now.AddMinutes($ValidMinutes).ToString("o")
                BoundAddress = ""
            }
            Write-ToolEnterpriseJson -Path $paths.ServerDashboardSession -Value $record
            Write-ToolEnterpriseAudit -Scope Server -Event "Dashboard.SessionCreated" -Message (Get-ToolEnterpriseText "enterpriseDashboard.audit.sessionCreated") -Data ([ordered]@{
                SessionId=$record.SessionId; ExpiresAtUtc=$record.ExpiresAtUtc
            })
            return [pscustomobject][ordered]@{
                AccessToken = $token
                ExpiresAtUtc = $record.ExpiresAtUtc
                DashboardPath = "/tool/v1/dashboard/"
            }
        } finally { [Array]::Clear($tokenHash, 0, $tokenHash.Length) }
    } finally { [Array]::Clear($tokenBytes, 0, $tokenBytes.Length) }
}

function Test-ToolEnterpriseDashboardSession {
    param(
        [Parameter(Mandatory = $true)][string]$AccessToken,
        [Parameter(Mandatory = $true)][string]$RemoteAddress
    )

    if ($AccessToken -notmatch '^[A-Za-z0-9_-]{43}$') { return $false }
    $paths = Initialize-ToolEnterpriseStorage
    $record = Read-ToolEnterpriseJson -Path $paths.ServerDashboardSession -MaximumBytes 65536
    if (-not $record) { return $false }

    $expires = [DateTime]::MinValue
    if (-not [DateTime]::TryParse(
        [string]$record.ExpiresAtUtc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$expires)) { return $false }
    if ($expires.ToUniversalTime() -le [DateTime]::UtcNow) { return $false }

    try { $expectedHash = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$record.TokenHash) }
    catch { return $false }
    $tokenTextBytes = [Text.Encoding]::UTF8.GetBytes($AccessToken)
    try { $actualHash = Get-ToolEnterpriseSha256Bytes -Bytes $tokenTextBytes }
    finally { [Array]::Clear($tokenTextBytes, 0, $tokenTextBytes.Length) }
    try {
        if (-not (Test-ToolEnterpriseFixedTimeEquals -Left $expectedHash -Right $actualHash)) { return $false }
    } finally {
        [Array]::Clear($expectedHash, 0, $expectedHash.Length)
        [Array]::Clear($actualHash, 0, $actualHash.Length)
    }

    $safeAddress = ConvertTo-ToolEnterpriseSafeText $RemoteAddress 80
    if ([string]::IsNullOrWhiteSpace($safeAddress)) { return $false }
    $boundAddress = [string]$record.BoundAddress
    if ([string]::IsNullOrWhiteSpace($boundAddress)) {
        $record.BoundAddress = $safeAddress
        Write-ToolEnterpriseJson -Path $paths.ServerDashboardSession -Value $record
        Write-ToolEnterpriseAudit -Scope Server -Event "Dashboard.SessionBound" -Message (Get-ToolEnterpriseText "enterpriseDashboard.audit.sessionBound") -Data ([ordered]@{
            SessionId=ConvertTo-ToolEnterpriseSafeText $record.SessionId 80; RemoteAddress=$safeAddress
        })
    } elseif (-not [string]::Equals($boundAddress, $safeAddress, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    return $true
}

function Get-ToolEnterpriseDashboardSnapshot {
    param(
        [ValidateRange(5, 1440)][int]$OnlineAfterMinutes = 90,
        [ValidateRange(2, 720)][int]$OfflineAfterHours = 24
    )

    $configuration = Get-ToolEnterpriseServerConfig
    if (-not $configuration) { throw (Get-ToolEnterpriseText "enterpriseCore.error.serverNotInitialized") }
    $clients = New-Object System.Collections.Generic.List[object]
    $onlineCount = 0
    $staleCount = 0
    $offlineCount = 0
    $reviewCount = 0
    $compliance = if (Get-Command Get-ToolLicenseComplianceSnapshot -ErrorAction SilentlyContinue) {
        Get-ToolLicenseComplianceSnapshot
    } else {
        [pscustomobject][ordered]@{ Summary=[ordered]@{ AssuranceScore=0; Compliant=0; NeedsReview=0; Critical=0; Purchased=0; Assigned=0; Installed=0; Available=0; EntitlementRecords=0; UncoveredCommercialProducts=0 }; Entitlements=@(); Uncovered=@(); Disclaimer='' }
    }
    $complianceEntitlements = if (Get-Command Get-ToolLicenseEntitlements -ErrorAction SilentlyContinue) { @(Get-ToolLicenseEntitlements) } else { @() }
    $complianceObservations = if (Get-Command Get-ToolLicenseComplianceFleetObservations -ErrorAction SilentlyContinue) { @(Get-ToolLicenseComplianceFleetObservations) } else { @() }
    $assetStore = $null
    try {
        if (Get-Command Read-ToolAssetRegistryStore -ErrorAction SilentlyContinue) {
            $assetStore = Read-ToolAssetRegistryStore -RootPath (Initialize-ToolEnterpriseStorage).ServerAssets
        }
    } catch { $assetStore = $null }
    $assetById = @{}
    $assignedAssetIds = @{}
    if ($assetStore) {
        foreach ($assetItem in @($assetStore.Assets)) { $assetById[[string]$assetItem.AssetId] = $assetItem }
        foreach ($assetItem in @($assetStore.Assets)) {
            if ($null -ne (Get-ToolCurrentAssetAssignment -Store $assetStore -AssetId ([string]$assetItem.AssetId))) { $assignedAssetIds[[string]$assetItem.AssetId] = $true }
        }
    }
    $assetConflictCount = 0

    foreach ($source in @(Get-ToolEnterpriseServerClients)) {
        $ageHours = Get-ToolEnterpriseClientAgeHours -LastSeenUtc $source.LastSeenUtc
        $presence = if ([double]::IsPositiveInfinity([double]$ageHours) -or $ageHours -gt $OfflineAfterHours) {
            "Offline"
        } elseif (($ageHours * 60) -le $OnlineAfterMinutes) {
            "Online"
        } else {
            "Stale"
        }
        switch ($presence) {
            "Online" { $onlineCount++ }
            "Stale" { $staleCount++ }
            default { $offlineCount++ }
        }

        $alerts = New-Object System.Collections.Generic.List[string]
        if ($presence -eq "Stale") { [void]$alerts.Add("Stale") }
        if ($presence -eq "Offline") { [void]$alerts.Add("Offline") }
        $windowsStatus = ConvertTo-ToolEnterpriseSafeText $source.WindowsStatus 80
        $officeStatus = ConvertTo-ToolEnterpriseSafeText $source.OfficeStatus 80
        if ($windowsStatus -notin @("Activated", "Licensed") -and $windowsStatus -ne "NotDetected") { [void]$alerts.Add("WindowsNeedsReview") }
        if ($officeStatus -notin @("Activated", "Licensed") -and $officeStatus -ne "NotDetected") { [void]$alerts.Add("OfficeNeedsReview") }
        $identityChangedAtUtc = ConvertTo-ToolEnterpriseSafeText $(if ($source.PSObject.Properties['LicenseIdentityChangedAtUtc']) { $source.LicenseIdentityChangedAtUtc } else { '' }) 80
        $windowsChanged = [bool]($source.PSObject.Properties['WindowsIdentityChanged'] -and $source.WindowsIdentityChanged)
        $officeChanged = [bool]($source.PSObject.Properties['OfficeIdentityChanged'] -and $source.OfficeIdentityChanged)
        if ($windowsChanged -or $officeChanged -or -not [string]::IsNullOrWhiteSpace($identityChangedAtUtc)) { [void]$alerts.Add("LicenseIdentityChanged") }
        $assetMatchStatus = ConvertTo-ToolEnterpriseSafeText $(if ($source.PSObject.Properties['AssetMatchStatus']) { $source.AssetMatchStatus } else { 'Missing' }) 40
        if ($assetMatchStatus -in @('Conflict','Ambiguous')) { [void]$alerts.Add('AssetIdentityConflict'); $assetConflictCount++ }
        $assetId = ConvertTo-ToolEnterpriseSafeText $(if ($source.PSObject.Properties['AssetId']) { $source.AssetId } else { '' }) 80
        $assetRecord = if ($assetId -and $assetById.ContainsKey($assetId)) { $assetById[$assetId] } else { $null }
        $currentAssignment = if ($assetStore -and $assetRecord) { Get-ToolCurrentAssetAssignment -Store $assetStore -AssetId $assetId } else { $null }
        $assetReference = Get-ToolEnterpriseAssetReference -Asset $assetRecord
        $assignmentHistoryCount = if ($assetStore -and $assetRecord) { @(Get-ToolAssetAssignmentHistory -Store $assetStore -AssetId $assetId).Count } else { 0 }
        $rawClientId = [string]$source.ClientId
        $clientReference = if ([string]::IsNullOrWhiteSpace($rawClientId)) { "CLIENT-UNKNOWN" } else { Get-ToolEnterpriseStableClientReference -ClientId $rawClientId }
        $assignedEntitlements = @($complianceEntitlements | Where-Object {
            @($_.Assignments | Where-Object { [string]$_.ClientId -eq $rawClientId -and [int]$_.Quantity -gt 0 }).Count -gt 0
        })
        $getAssignedScopeState = {
            param([string]$Scope)
            $scopeRecords = @($assignedEntitlements | Where-Object { [string]$_.ProductScope -eq $Scope })
            if ($scopeRecords.Count -eq 0) { return 'NotVerified' }
            $scopeRows = @($compliance.Entitlements | Where-Object { $scopeRecords.EntitlementId -contains [string]$_.EntitlementId })
            if (@($scopeRows | Where-Object ComplianceState -eq 'Critical').Count -gt 0) { return 'Critical' }
            if (@($scopeRows | Where-Object ComplianceState -eq 'NeedsReview').Count -gt 0) { return 'NeedsReview' }
            if (@($scopeRows | Where-Object ComplianceState -eq 'Compliant').Count -gt 0) { return 'Compliant' }
            return 'NotVerified'
        }
        $windowsEntitlementStatus = & $getAssignedScopeState 'Windows'
        $officeEntitlementStatus = & $getAssignedScopeState 'Office'
        $softwareEntitlementStatus = & $getAssignedScopeState 'Software'
        $clientSoftware = @($complianceObservations | Where-Object { [string]$_.ClientId -eq $rawClientId -and [string]$_.ProductScope -eq 'Software' })
        $softwareCommercial = @($clientSoftware | Where-Object { [string]$_.LicenseModel -in @('Paid','Subscription','Trial','Unknown') }).Count
        $softwareFree = @($clientSoftware | Where-Object { [string]$_.LicenseModel -in @('Free','OpenSource','Freemium') }).Count
        $softwareUnknown = @($clientSoftware | Where-Object { [string]$_.LicenseModel -eq 'Unknown' }).Count
        $overallComplianceStatus = if ($windowsEntitlementStatus -eq 'Critical' -or $officeEntitlementStatus -eq 'Critical' -or $softwareEntitlementStatus -eq 'Critical') { 'Critical' }
            elseif ($windowsEntitlementStatus -in @('NeedsReview','NotVerified') -or $officeEntitlementStatus -in @('NeedsReview','NotVerified') -or ($softwareCommercial -gt 0 -and $softwareEntitlementStatus -in @('NeedsReview','NotVerified'))) { 'NeedsReview' }
            else { 'Compliant' }
        if ($overallComplianceStatus -ne 'Compliant' -and $alerts -notcontains 'EntitlementNeedsReview') { [void]$alerts.Add('EntitlementNeedsReview') }
        if ($alerts.Count -gt 0) { $reviewCount++ }
        $windowsAdvisor = if (Get-Command Get-ToolLicenseAdvisorResult -ErrorAction SilentlyContinue) {
            Get-ToolLicenseAdvisorResult -ProductScope Windows -TechnicalStatus $windowsStatus -Channel ([string]$source.WindowsChannel) -LicenseModel ([string]$source.WindowsChannel) -EntitlementStatus $windowsEntitlementStatus
        } else { $null }
        $officeAdvisor = if (Get-Command Get-ToolLicenseAdvisorResult -ErrorAction SilentlyContinue) {
            Get-ToolLicenseAdvisorResult -ProductScope Office -TechnicalStatus $officeStatus -Channel ([string]$source.OfficeChannel) -LicenseModel ([string]$source.OfficeChannel) -EntitlementStatus $officeEntitlementStatus
        } else { $null }
        [void]$clients.Add([pscustomobject][ordered]@{
            ClientReference = $clientReference
            ComputerName = ConvertTo-ToolEnterpriseSafeText $source.ComputerName 100
            AssetReference = $assetReference
            AssetStatus = if ($assetRecord) { ConvertTo-ToolEnterpriseSafeText $assetRecord.Status 40 } else { '' }
            AssetMatchStatus = $assetMatchStatus
            AssignmentType = if ($currentAssignment) { ConvertTo-ToolEnterpriseSafeText $currentAssignment.AssigneeType 40 } else { '' }
            AssignmentDisplayName = if ($currentAssignment) { ConvertTo-ToolEnterpriseSafeText $currentAssignment.DisplayName 200 } else { '' }
            AssignmentHistoryCount = [int]$assignmentHistoryCount
            RemoteAddress = ConvertTo-ToolEnterpriseSafeText $source.RemoteAddress 80
            LastSeenUtc = ConvertTo-ToolEnterpriseSafeText $source.LastSeenUtc 80
            AgeMinutes = if ([double]::IsPositiveInfinity([double]$ageHours)) { $null } else { [Math]::Round(($ageHours * 60), 1) }
            Presence = $presence
            WindowsStatus = $windowsStatus
            WindowsChannel = ConvertTo-ToolEnterpriseSafeText $source.WindowsChannel 120
            WindowsEntitlementStatus = $windowsEntitlementStatus
            OfficeStatus = $officeStatus
            OfficeChannel = ConvertTo-ToolEnterpriseSafeText $source.OfficeChannel 120
            OfficeEntitlementStatus = $officeEntitlementStatus
            LicenseIdentityChangedAtUtc = $identityChangedAtUtc
            ComplianceStatus = $overallComplianceStatus
            WindowsAdvisor = $windowsAdvisor
            OfficeAdvisor = $officeAdvisor
            SoftwareSummary = [ordered]@{ Total=$clientSoftware.Count; Commercial=$softwareCommercial; FreeOrOpenSource=$softwareFree; Unknown=$softwareUnknown; EntitlementStatus=$softwareEntitlementStatus }
            Alerts = $alerts.ToArray()
        })
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = "1.0"
        GeneratedAtUtc = [DateTime]::UtcNow.ToString("o")
        RefreshSeconds = 60
        Thresholds = [ordered]@{ OnlineAfterMinutes=$OnlineAfterMinutes; OfflineAfterHours=$OfflineAfterHours }
        Server = [ordered]@{
            Name = ConvertTo-ToolEnterpriseSafeText $configuration.ServerName 100
            ToolVersion = $script:ToolEnterpriseToolVersion
            ProtocolVersion = $script:ToolEnterpriseProtocolVersion
        }
        Summary = [ordered]@{
            Total = $clients.Count
            Online = $onlineCount
            Stale = $staleCount
            Offline = $offlineCount
            NeedsReview = $reviewCount
            AssuranceScore = [int]$compliance.Summary.AssuranceScore
            Compliant = [int]$compliance.Summary.Compliant
            Critical = [int]$compliance.Summary.Critical
            Assets = if ($assetStore) { @($assetStore.Assets).Count } else { 0 }
            AssignedAssets = $assignedAssetIds.Count
            UnassignedAssets = if ($assetStore) { @($assetStore.Assets).Count - $assignedAssetIds.Count } else { 0 }
            AssetConflicts = $assetConflictCount
        }
        Compliance = $compliance
        Clients = @($clients.ToArray() | Sort-Object @{Expression={ switch ($_.Presence) { 'Online' {0}; 'Stale' {1}; default {2} } }}, ComputerName, ClientReference)
        TechnicalStatusDisclaimer = "Activation status is technical only; entitlement remains NotVerified until invoices, agreements, accounts, or licensing portals are checked."
    }
}

function Get-ToolEnterpriseDashboardHtml {
    param([ValidateSet('vi-VN','en-US')][string]$Culture = 'vi-VN')

    $languageCode = if ($Culture -eq 'en-US') { 'en' } else { 'vi' }
    $tokens = [ordered]@{
        '{{LANG}}' = $languageCode
        '{{SKIP}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.skip' -Culture $Culture
        '{{REFRESH}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.refresh' -Culture $Culture
        '{{LANGUAGE_BUTTON}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.languageButton' -Culture $Culture
        '{{EYEBROW}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.eyebrow' -Culture $Culture
        '{{TITLE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.title' -Culture $Culture
        '{{INTRO}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.intro' -Culture $Culture
        '{{CONNECTING}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.connecting' -Culture $Culture
        '{{CONNECTED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.connected' -Culture $Culture
        '{{FAILED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.failed' -Culture $Culture
        '{{ACCESS_TITLE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.accessTitle' -Culture $Culture
        '{{ACCESS_BODY}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.accessBody' -Culture $Culture
        '{{SUMMARY_ARIA}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.summaryAria' -Culture $Culture
        '{{TOTAL}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.total' -Culture $Culture
        '{{ONLINE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.online' -Culture $Culture
        '{{STALE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.stale' -Culture $Culture
        '{{OFFLINE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.offline' -Culture $Culture
        '{{REVIEW}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.review' -Culture $Culture
        '{{ASSURANCE_SCORE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.assuranceScore' -Culture $Culture
        '{{COMPLIANT}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.compliant' -Culture $Culture
        '{{CRITICAL}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.critical' -Culture $Culture
        '{{PURCHASED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.purchased' -Culture $Culture
        '{{ASSIGNED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.assigned' -Culture $Culture
        '{{INSTALLED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.installed' -Culture $Culture
        '{{AVAILABLE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.available' -Culture $Culture
        '{{PORTFOLIO}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.portfolio' -Culture $Culture
        '{{PORTFOLIO_HELP}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.portfolioHelp' -Culture $Culture
        '{{PRODUCT}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.product' -Culture $Culture
        '{{MODEL}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.model' -Culture $Culture
        '{{COMPLIANCE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.compliance' -Culture $Culture
        '{{FLEET}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.fleet' -Culture $Culture
        '{{FLEET_CAPTION}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.fleetCaption' -Culture $Culture
        '{{FLEET_HELP}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.fleetHelp' -Culture $Culture
        '{{FILTER}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.filter' -Culture $Culture
        '{{FILTER_PLACEHOLDER}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.filterPlaceholder' -Culture $Culture
        '{{DEVICE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.device' -Culture $Culture
        '{{ASSETS}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.assets' -Culture $Culture
        '{{ASSET_ASSIGNED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.assetAssigned' -Culture $Culture
        '{{ASSET_UNASSIGNED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.assetUnassigned' -Culture $Culture
        '{{ASSET_CONFLICTS}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.assetConflicts' -Culture $Culture
        '{{ASSET_LABEL}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.assetLabel' -Culture $Culture
        '{{ASSIGNED_TO}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.assignedTo' -Culture $Culture
        '{{UNASSIGNED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.unassigned' -Culture $Culture
        '{{PRESENCE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.presence' -Culture $Culture
        '{{LAST_SEEN}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.lastSeen' -Culture $Culture
        '{{ALERTS}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.alerts' -Culture $Culture
        '{{IMPORTANT}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.important' -Culture $Culture
        '{{DISCLAIMER}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.disclaimer' -Culture $Culture
        '{{FOOTER}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.footer' -Culture $Culture
        '{{EMPTY}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.empty' -Culture $Culture
        '{{NONE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.none' -Culture $Culture
        '{{NOT_DETECTED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.notDetected' -Culture $Culture
        '{{ENTITLEMENT}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.entitlement' -Culture $Culture
        '{{ALERT_STALE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.alert.stale' -Culture $Culture
        '{{ALERT_OFFLINE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.alert.offline' -Culture $Culture
        '{{ALERT_WINDOWS}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.alert.windows' -Culture $Culture
        '{{ALERT_OFFICE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.alert.office' -Culture $Culture
        '{{ALERT_IDENTITY}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.alert.identityChanged' -Culture $Culture
        '{{ALERT_ENTITLEMENT}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.alert.entitlement' -Culture $Culture
        '{{ALERT_ASSET_CONFLICT}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.alert.assetConflict' -Culture $Culture
        '{{STATUS_NOT_VERIFIED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.status.notVerified' -Culture $Culture
        '{{STATUS_NEEDS_REVIEW}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.status.needsReview' -Culture $Culture
        '{{STATUS_COMPLIANT}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.status.compliant' -Culture $Culture
        '{{STATUS_CRITICAL}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.status.critical' -Culture $Culture
        '{{ADVISOR_RISK_HIGH}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.risk.high' -Culture $Culture
        '{{ADVISOR_RISK_REVIEW}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.risk.review' -Culture $Culture
        '{{ADVISOR_RISK_LOW}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.risk.low' -Culture $Culture
        '{{ADVISOR_FINDING_ACTIVE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.finding.technicalActivationPresent' -Culture $Culture
        '{{ADVISOR_FINDING_INACTIVE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.finding.technicalActivationNotConfirmed' -Culture $Culture
        '{{ADVISOR_FINDING_FREE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.finding.freeOrOpenSource' -Culture $Culture
        '{{ADVISOR_FINDING_COMMERCIAL}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.finding.commercialEntitlementRequired' -Culture $Culture
        '{{ADVISOR_RECOMMEND_RECONCILE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.recommendation.reconcileImmediately' -Culture $Culture
        '{{ADVISOR_RECOMMEND_ATTACH}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.recommendation.attachEvidenceAndAssign' -Culture $Culture
        '{{ADVISOR_RECOMMEND_ACTIVATE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.recommendation.useOfficialActivation' -Culture $Culture
        '{{ADVISOR_RECOMMEND_RETAIN}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.recommendation.retainEvidence' -Culture $Culture
        '{{ADVISOR_LIMITATION}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.limitation' -Culture $Culture
        '{{ADVISOR_EXPLAIN}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.explain' -Culture $Culture
        '{{ADVISOR_RULE_ID}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.ruleId' -Culture $Culture
        '{{ADVISOR_CONFIDENCE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.confidence' -Culture $Culture
        '{{ADVISOR_FINDING_LABEL}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.findingLabel' -Culture $Culture
        '{{ADVISOR_EVIDENCE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.evidence' -Culture $Culture
        '{{ADVISOR_RECOMMENDATION}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.recommendation' -Culture $Culture
        '{{ADVISOR_LIMITATION_HEADING}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.limitationHeading' -Culture $Culture
        '{{ADVISOR_CONFIRMED}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.confidence.confirmed' -Culture $Culture
        '{{ADVISOR_CONFIDENCE_HIGH}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.confidence.high' -Culture $Culture
        '{{ADVISOR_CONFIDENCE_MEDIUM}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.confidence.medium' -Culture $Culture
        '{{ADVISOR_CONFIDENCE_LOW}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.confidence.low' -Culture $Culture
        '{{ADVISOR_INFORMATIONAL}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.confidence.informational' -Culture $Culture
        '{{ADVISOR_SOURCE_ENDPOINT}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.source.endpointReport' -Culture $Culture
        '{{ADVISOR_SOURCE_COMPLIANCE}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.source.complianceStore' -Culture $Culture
        '{{ADVISOR_SOURCE_CATALOG}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.source.signedCatalog' -Culture $Culture
        '{{ADVISOR_SOURCE_INVENTORY}}' = Get-ToolEnterpriseCultureText -Key 'enterpriseDashboard.ui.advisor.source.softwareInventory' -Culture $Culture
    }
    $html = @'
<!doctype html>
<html lang="{{LANG}}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'">
  <meta name="referrer" content="no-referrer">
  <title>VietLicenSure Central Dashboard</title>
  <link rel="stylesheet" href="app.css">
  <script src="app.js" defer></script>
</head>
<body data-connecting="{{CONNECTING}}" data-connected="{{CONNECTED}}" data-failed="{{FAILED}}" data-empty="{{EMPTY}}" data-none="{{NONE}}" data-not-detected="{{NOT_DETECTED}}" data-entitlement="{{ENTITLEMENT}}" data-asset-label="{{ASSET_LABEL}}" data-assigned-to="{{ASSIGNED_TO}}" data-unassigned="{{UNASSIGNED}}" data-alert-stale="{{ALERT_STALE}}" data-alert-offline="{{ALERT_OFFLINE}}" data-alert-windows="{{ALERT_WINDOWS}}" data-alert-office="{{ALERT_OFFICE}}" data-alert-identity="{{ALERT_IDENTITY}}" data-alert-entitlement="{{ALERT_ENTITLEMENT}}" data-alert-asset-conflict="{{ALERT_ASSET_CONFLICT}}" data-status-not-verified="{{STATUS_NOT_VERIFIED}}" data-status-needs-review="{{STATUS_NEEDS_REVIEW}}" data-status-compliant="{{STATUS_COMPLIANT}}" data-status-critical="{{STATUS_CRITICAL}}" data-advisor-risk-high="{{ADVISOR_RISK_HIGH}}" data-advisor-risk-review="{{ADVISOR_RISK_REVIEW}}" data-advisor-risk-low="{{ADVISOR_RISK_LOW}}" data-advisor-finding-active="{{ADVISOR_FINDING_ACTIVE}}" data-advisor-finding-inactive="{{ADVISOR_FINDING_INACTIVE}}" data-advisor-finding-free="{{ADVISOR_FINDING_FREE}}" data-advisor-finding-commercial="{{ADVISOR_FINDING_COMMERCIAL}}" data-advisor-recommend-reconcile="{{ADVISOR_RECOMMEND_RECONCILE}}" data-advisor-recommend-attach="{{ADVISOR_RECOMMEND_ATTACH}}" data-advisor-recommend-activate="{{ADVISOR_RECOMMEND_ACTIVATE}}" data-advisor-recommend-retain="{{ADVISOR_RECOMMEND_RETAIN}}" data-advisor-limitation="{{ADVISOR_LIMITATION}}" data-advisor-explain="{{ADVISOR_EXPLAIN}}" data-advisor-rule-id="{{ADVISOR_RULE_ID}}" data-advisor-confidence="{{ADVISOR_CONFIDENCE}}" data-advisor-finding-label="{{ADVISOR_FINDING_LABEL}}" data-advisor-evidence="{{ADVISOR_EVIDENCE}}" data-advisor-recommendation="{{ADVISOR_RECOMMENDATION}}" data-advisor-limitation-heading="{{ADVISOR_LIMITATION_HEADING}}" data-advisor-confirmed="{{ADVISOR_CONFIRMED}}" data-advisor-confidence-high="{{ADVISOR_CONFIDENCE_HIGH}}" data-advisor-confidence-medium="{{ADVISOR_CONFIDENCE_MEDIUM}}" data-advisor-confidence-low="{{ADVISOR_CONFIDENCE_LOW}}" data-advisor-informational="{{ADVISOR_INFORMATIONAL}}" data-advisor-source-endpoint="{{ADVISOR_SOURCE_ENDPOINT}}" data-advisor-source-compliance="{{ADVISOR_SOURCE_COMPLIANCE}}" data-advisor-source-catalog="{{ADVISOR_SOURCE_CATALOG}}" data-advisor-source-inventory="{{ADVISOR_SOURCE_INVENTORY}}">
  <a class="skip" href="#main">{{SKIP}}</a>
  <header class="topbar">
    <div><strong>VietLicenSure Central</strong><span class="release-badge">v5.0</span></div>
    <div class="toolbar"><span id="server-name">--</span><button id="language" type="button">{{LANGUAGE_BUTTON}}</button><button id="refresh" type="button">{{REFRESH}}</button></div>
  </header>
  <main id="main" class="wrap">
    <section class="hero">
      <div><p class="eyebrow">{{EYEBROW}}</p><h1>{{TITLE}}</h1><p>{{INTRO}}</p></div>
      <div class="connection" role="status" aria-live="polite"><span id="connection-dot" class="dot waiting"></span><span id="connection-text">{{CONNECTING}}</span><small id="generated-at"></small></div>
    </section>
    <section id="access-warning" class="notice" hidden><strong>{{ACCESS_TITLE}}</strong><p>{{ACCESS_BODY}}</p></section>
    <div id="dashboard" hidden>
      <section class="cards" aria-label="{{SUMMARY_ARIA}}">
        <article><span>{{TOTAL}}</span><strong id="count-total">0</strong></article>
        <article class="ok"><span>{{ONLINE}}</span><strong id="count-online">0</strong></article>
        <article class="warn"><span>{{STALE}}</span><strong id="count-stale">0</strong></article>
        <article class="muted"><span>{{OFFLINE}}</span><strong id="count-offline">0</strong></article>
        <article class="danger"><span>{{REVIEW}}</span><strong id="count-review">0</strong></article>
      </section>
      <section class="cards asset-cards" aria-label="{{ASSETS}}">
        <article><span>{{ASSETS}}</span><strong id="count-assets">0</strong></article>
        <article class="ok"><span>{{ASSET_ASSIGNED}}</span><strong id="count-assets-assigned">0</strong></article>
        <article class="muted"><span>{{ASSET_UNASSIGNED}}</span><strong id="count-assets-unassigned">0</strong></article>
        <article class="danger"><span>{{ASSET_CONFLICTS}}</span><strong id="count-assets-conflicts">0</strong></article>
      </section>
      <section class="cards compliance-cards" aria-label="{{COMPLIANCE}}">
        <article class="score"><span>{{ASSURANCE_SCORE}}</span><strong id="count-score">0</strong></article>
        <article class="ok"><span>{{COMPLIANT}}</span><strong id="count-compliant">0</strong></article>
        <article class="danger"><span>{{CRITICAL}}</span><strong id="count-critical">0</strong></article>
        <article><span>{{PURCHASED}}</span><strong id="count-purchased">0</strong></article>
        <article><span>{{ASSIGNED}}</span><strong id="count-assigned">0</strong></article>
        <article><span>{{INSTALLED}}</span><strong id="count-installed">0</strong></article>
        <article class="ok"><span>{{AVAILABLE}}</span><strong id="count-available">0</strong></article>
      </section>
      <section class="panel portfolio-panel">
        <div class="panel-head"><div><h2>{{PORTFOLIO}}</h2><p>{{PORTFOLIO_HELP}}</p></div></div>
        <div class="table-wrap"><table><caption class="sr-only">{{PORTFOLIO}}</caption><thead><tr><th scope="col">{{PRODUCT}}</th><th scope="col">{{MODEL}}</th><th scope="col">{{PURCHASED}}</th><th scope="col">{{ASSIGNED}}</th><th scope="col">{{INSTALLED}}</th><th scope="col">{{AVAILABLE}}</th><th scope="col">{{COMPLIANCE}}</th></tr></thead><tbody id="entitlement-rows"></tbody></table></div>
      </section>
      <section class="panel">
        <div class="panel-head"><div><h2>{{FLEET}}</h2><p>{{FLEET_HELP}}</p></div><label><span>{{FILTER}}</span><input id="filter" type="search" autocomplete="off" placeholder="{{FILTER_PLACEHOLDER}}"></label></div>
        <div class="table-wrap"><table><caption class="sr-only">{{FLEET_CAPTION}}</caption><thead><tr><th scope="col">{{DEVICE}}</th><th scope="col">{{PRESENCE}}</th><th scope="col">{{LAST_SEEN}}</th><th scope="col">Windows</th><th scope="col">Office</th><th scope="col">{{COMPLIANCE}}</th><th scope="col">{{ALERTS}}</th></tr></thead><tbody id="client-rows"></tbody></table></div>
      </section>
      <section class="disclaimer"><strong>{{IMPORTANT}}</strong> <span>{{DISCLAIMER}}</span></section>
    </div>
  </main>
  <footer>{{FOOTER}}</footer>
</body>
</html>
'@
    foreach ($token in $tokens.Keys) {
        $html = $html.Replace([string]$token, [Net.WebUtility]::HtmlEncode([string]$tokens[$token]))
    }
    return $html
}

function Get-ToolEnterpriseDashboardCss {
    return @'
:root{color-scheme:light;--ink:#172033;--muted:#667085;--line:#d6dee8;--paper:#fff;--canvas:#edf3f8;--brand:#123b74;--brand2:#2563a7;--ok:#147a4b;--warn:#a35b00;--bad:#b42318;--shadow:0 8px 24px rgba(16,24,40,.08)}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:linear-gradient(180deg,#e8f0f8,var(--canvas) 360px);color:var(--ink);font-family:"Segoe UI",Arial,sans-serif;line-height:1.45}.sr-only{height:1px;margin:-1px;overflow:hidden;padding:0;position:absolute;width:1px;clip:rect(0 0 0 0);white-space:nowrap}.skip{position:absolute;left:-9999px;top:0}.skip:focus{left:12px;top:12px;background:#fff;padding:8px;z-index:10}.topbar{align-items:center;background:#0f315e;color:#fff;display:flex;justify-content:space-between;padding:13px max(18px,calc((100vw - 1240px)/2));position:sticky;top:0;z-index:5}.topbar>div{align-items:center;display:flex;gap:10px}.release-badge{background:#dff8e9;border:1px solid #7ed7a5;border-radius:999px;color:#0d633d;font-size:11px;font-weight:800;padding:3px 8px}.toolbar{flex-wrap:wrap;justify-content:flex-end}.toolbar button{background:#fff;border:0;border-radius:7px;color:#123b74;cursor:pointer;font-weight:700;padding:8px 11px}.wrap{margin:0 auto;max-width:1240px;padding:22px}.hero{align-items:center;background:linear-gradient(135deg,#0d2e5c,#2563a7);border-radius:17px;color:#fff;display:flex;gap:28px;justify-content:space-between;padding:27px 30px;box-shadow:var(--shadow)}h1{font-size:30px;line-height:1.18;margin:6px 0}.eyebrow{font-size:12px;font-weight:800;letter-spacing:.09em;margin:0;opacity:.82;text-transform:uppercase}.hero p:not(.eyebrow){margin:8px 0;max-width:760px}.connection{align-items:center;background:rgba(255,255,255,.13);border:1px solid rgba(255,255,255,.25);border-radius:12px;display:grid;grid-template-columns:auto 1fr;min-width:220px;padding:12px 14px}.connection small{grid-column:2;color:#dbeafe;margin-top:3px}.dot{background:#98a2b3;border-radius:50%;display:inline-block;height:10px;margin-right:8px;width:10px}.dot.online{background:#54d68b}.dot.stale{background:#f3ad45}.dot.offline{background:#98a2b3}.dot.waiting{background:#89b4ea}.notice,.disclaimer{background:#fff7e8;border:2px solid var(--warn);border-radius:9px;margin-top:16px;padding:13px 15px}.cards{display:grid;gap:10px;grid-template-columns:repeat(5,minmax(0,1fr));margin:16px 0}.cards article{background:var(--paper);border:2px solid var(--brand2);border-radius:12px;padding:13px 14px;box-shadow:var(--shadow)}.cards article.ok{border-color:var(--ok)}.cards article.warn{border-color:var(--warn)}.cards article.danger{border-color:var(--bad)}.cards article.muted{border-color:#8292a8}.cards span{color:var(--muted);display:block;font-size:12px;font-weight:700;text-transform:uppercase}.cards strong{display:block;font-size:28px;margin-top:5px}.panel{background:var(--paper);border:1px solid var(--line);border-radius:14px;box-shadow:var(--shadow);padding:17px}.panel-head{align-items:end;display:flex;gap:16px;justify-content:space-between;margin-bottom:12px}.panel-head h2{color:var(--brand);margin:0}.panel-head p{color:var(--muted);margin:4px 0 0}.panel-head label{color:var(--muted);font-size:12px;font-weight:700}.panel-head input{border:1px solid #b8c4d2;border-radius:7px;display:block;margin-top:4px;min-width:260px;padding:8px 9px}.table-wrap{overflow-x:auto}table{border-collapse:collapse;font-size:13px;width:100%}th,td{border:1px solid #dfe6ee;padding:8px 9px;text-align:left;vertical-align:top}th{background:#e8f0f8;color:#183b66}tbody tr:nth-child(even) td{background:#f8fafc}.device strong,.device small,.status-main,.status-sub{display:block}.device small,.status-sub{color:var(--muted);font-size:11px;margin-top:2px}.pill{border-radius:999px;display:inline-block;font-size:11px;font-weight:800;padding:3px 8px}.pill.online,.pill.good{background:#eaf8f0;color:var(--ok)}.pill.stale,.pill.review{background:#fff3df;color:var(--warn)}.pill.offline{background:#eef1f4;color:#475467}.alert-list{display:flex;flex-wrap:wrap;gap:4px}.alert{background:#feeceb;border-radius:999px;color:var(--bad);font-size:10px;font-weight:800;padding:3px 7px}.alert.neutral{background:#eef1f4;color:#475467}.empty{color:var(--muted);padding:24px;text-align:center}.disclaimer{font-size:13px}.disclaimer strong{color:#6b4300}footer{color:var(--muted);font-size:12px;padding:20px;text-align:center}@media(max-width:850px){.cards{grid-template-columns:repeat(2,minmax(0,1fr))}.hero,.panel-head{align-items:stretch;flex-direction:column}.connection{min-width:0}.panel-head input{min-width:0;width:100%}}@media(max-width:520px){.topbar{align-items:flex-start;flex-direction:column}.toolbar{justify-content:flex-start}.wrap{padding:12px}.hero{border-radius:12px;padding:20px}h1{font-size:24px}.cards{grid-template-columns:1fr 1fr}.panel{padding:10px}.panel-head input{width:100%}}
.asset-cards{grid-template-columns:repeat(4,minmax(0,1fr))}.compliance-cards{grid-template-columns:repeat(7,minmax(0,1fr))}.compliance-cards article.score{border-color:#6b46c1}.portfolio-panel{margin-bottom:16px}.pill.critical{background:#feeceb;color:var(--bad)}.pill.needsreview,.pill.notverified{background:#fff3df;color:var(--warn)}.pill.compliant{background:#eaf8f0;color:var(--ok)}
.advisor-details{border:1px solid #c7d5e5;border-radius:7px;margin-top:5px;max-width:330px;padding:4px 6px}.advisor-details summary{color:var(--brand);cursor:pointer;font-size:11px;font-weight:700}.advisor-explain{display:grid;gap:5px;margin-top:7px}.advisor-explain p{font-size:11px;margin:0;overflow-wrap:anywhere}.advisor-explain strong{color:#334155}.advisor-evidence{margin:0;padding-left:17px}.advisor-evidence li{font-size:11px;margin:2px 0;overflow-wrap:anywhere}
@media(max-width:1050px){.compliance-cards{grid-template-columns:repeat(4,minmax(0,1fr))}}@media(max-width:620px){.asset-cards,.compliance-cards{grid-template-columns:repeat(2,minmax(0,1fr))}}
'@
}

function Get-ToolEnterpriseDashboardJs {
    return @'
(function(){
  'use strict';
  var query=new URLSearchParams(window.location.search);var lang=query.get('lang')==='en'?'en':'vi';document.documentElement.lang=lang;
  var body=document.body;var strings={connecting:body.getAttribute('data-connecting')||'Connecting',connected:body.getAttribute('data-connected')||'Connected',failed:body.getAttribute('data-failed')||'Unable to load data',empty:body.getAttribute('data-empty')||'No matching endpoints',none:body.getAttribute('data-none')||'None',notDetected:body.getAttribute('data-not-detected')||'Not detected',entitlement:body.getAttribute('data-entitlement')||'Entitlement: not verified',AssetLabel:body.getAttribute('data-asset-label')||'Asset',AssignedTo:body.getAttribute('data-assigned-to')||'Assigned to',Unassigned:body.getAttribute('data-unassigned')||'Unassigned',NotVerified:body.getAttribute('data-status-not-verified')||'Not verified',NeedsReview:body.getAttribute('data-status-needs-review')||'Needs review',Compliant:body.getAttribute('data-status-compliant')||'Compliant',Critical:body.getAttribute('data-status-critical')||'Critical',Stale:body.getAttribute('data-alert-stale')||'Stale',Offline:body.getAttribute('data-alert-offline')||'Offline',WindowsNeedsReview:body.getAttribute('data-alert-windows')||'Windows needs review',OfficeNeedsReview:body.getAttribute('data-alert-office')||'Office needs review',LicenseIdentityChanged:body.getAttribute('data-alert-identity')||'Last5 changed',EntitlementNeedsReview:body.getAttribute('data-alert-entitlement')||'Entitlement needs review',AssetIdentityConflict:body.getAttribute('data-alert-asset-conflict')||'Asset identity needs review'};
  strings.High=body.getAttribute('data-advisor-risk-high')||'High risk';strings.Review=body.getAttribute('data-advisor-risk-review')||'Review';strings.Low=body.getAttribute('data-advisor-risk-low')||'Low risk';strings.TechnicalActivationPresent=body.getAttribute('data-advisor-finding-active')||'Technical activation is present';strings.TechnicalActivationNotConfirmed=body.getAttribute('data-advisor-finding-inactive')||'Technical activation is not confirmed';strings.FreeOrOpenSourceClassification=body.getAttribute('data-advisor-finding-free')||'Free or open-source classification';strings.CommercialEntitlementRequired=body.getAttribute('data-advisor-finding-commercial')||'Commercial entitlement may be required';strings.ReconcileImmediately=body.getAttribute('data-advisor-recommend-reconcile')||'Reconcile immediately';strings.AttachEvidenceAndAssign=body.getAttribute('data-advisor-recommend-attach')||'Attach evidence and assign entitlement';strings.UseOfficialActivation=body.getAttribute('data-advisor-recommend-activate')||'Use the official activation workflow';strings.RetainEvidence=body.getAttribute('data-advisor-recommend-retain')||'Retain supporting evidence';strings.LegalEntitlementNotProven=body.getAttribute('data-advisor-limitation')||'Technical status does not independently prove legal entitlement';
  strings.AdvisorExplain=body.getAttribute('data-advisor-explain')||'Explain this finding';strings.AdvisorRuleId=body.getAttribute('data-advisor-rule-id')||'Rule ID';strings.AdvisorConfidence=body.getAttribute('data-advisor-confidence')||'Confidence';strings.AdvisorFinding=body.getAttribute('data-advisor-finding-label')||'Finding';strings.AdvisorEvidence=body.getAttribute('data-advisor-evidence')||'Evidence';strings.AdvisorRecommendation=body.getAttribute('data-advisor-recommendation')||'Recommendation';strings.AdvisorLimitation=body.getAttribute('data-advisor-limitation-heading')||'Conclusion limit';strings.ConfidenceConfirmed=body.getAttribute('data-advisor-confirmed')||'Confirmed';strings.ConfidenceHigh=body.getAttribute('data-advisor-confidence-high')||'High';strings.ConfidenceMedium=body.getAttribute('data-advisor-confidence-medium')||'Medium';strings.ConfidenceLow=body.getAttribute('data-advisor-confidence-low')||'Low';strings.ConfidenceInformational=body.getAttribute('data-advisor-informational')||'Informational';strings.SourceEndpointReport=body.getAttribute('data-advisor-source-endpoint')||'Endpoint report';strings.SourceComplianceStore=body.getAttribute('data-advisor-source-compliance')||'Entitlement records';strings.SourceSignedCatalog=body.getAttribute('data-advisor-source-catalog')||'Signed catalog';strings.SourceSoftwareInventory=body.getAttribute('data-advisor-source-inventory')||'Software inventory';
  function t(key){return Object.prototype.hasOwnProperty.call(strings,key)?strings[key]:key;}
  function confidenceText(code){return strings['Confidence'+String(code||'Informational')]||String(code||'Informational');}
  function sourceText(code){return strings['Source'+String(code||'')]||String(code||'');}
  var languageButton=document.getElementById('language');
  languageButton.addEventListener('click',function(){query.set('lang',lang==='vi'?'en':'vi');window.location.search=query.toString();});
  var fragment=new URLSearchParams(window.location.hash.replace(/^#/,''));var fragmentToken=fragment.get('token');if(fragmentToken){sessionStorage.setItem('vls-dashboard-token',fragmentToken);history.replaceState(null,'',window.location.pathname+window.location.search);}var token=sessionStorage.getItem('vls-dashboard-token')||'';
  var dashboard=document.getElementById('dashboard');var warning=document.getElementById('access-warning');var rows=document.getElementById('client-rows');var entitlementRows=document.getElementById('entitlement-rows');var latestClients=[];
  function setConnection(kind,label){var dot=document.getElementById('connection-dot');dot.className='dot '+kind;document.getElementById('connection-text').textContent=label;}
  function cell(row,text,className){var td=document.createElement('td');if(className){td.className=className;}td.textContent=text;row.appendChild(td);return td;}
  function complianceBadge(state){var span=document.createElement('span');var normalized=String(state||'NotVerified');span.className='pill '+normalized.toLowerCase();span.textContent=t(normalized);return span;}
  function statusCell(row,status,channel,entitlementStatus){var td=document.createElement('td');var main=document.createElement('span');main.className='status-main';main.textContent=status||t('notDetected');var sub=document.createElement('span');sub.className='status-sub';sub.textContent=(channel||'--')+' / '+t(entitlementStatus||'NotVerified');td.appendChild(main);td.appendChild(sub);row.appendChild(td);}
  function renderEntitlements(compliance){entitlementRows.textContent='';var entries=compliance&&Array.isArray(compliance.Entitlements)?compliance.Entitlements.slice():[];var uncovered=compliance&&Array.isArray(compliance.Uncovered)?compliance.Uncovered:[];uncovered.forEach(function(item){entries.push({ProductName:item.ProductName,LicenseModel:item.LicenseModel,Purchased:0,Assigned:0,Installed:item.InstalledClients||0,Available:0,ComplianceState:item.ComplianceState||'NeedsReview'});});if(!entries.length){var emptyRow=document.createElement('tr');var emptyCell=cell(emptyRow,t('empty'),'empty');emptyCell.colSpan=7;entitlementRows.appendChild(emptyRow);return;}entries.forEach(function(item){var row=document.createElement('tr');cell(row,item.ProductName||item.ProductScope||'--');cell(row,item.LicenseModel||'--');cell(row,String(item.Purchased||0));cell(row,String(item.Assigned||0));cell(row,String(item.Installed||0));cell(row,String(item.Available||0));var state=document.createElement('td');state.appendChild(complianceBadge(item.ComplianceState));row.appendChild(state);entitlementRows.appendChild(row);});}
  function appendAdvisor(parent,label,advisor){if(!advisor){return;}var details=document.createElement('details');details.className='advisor-details';var summary=document.createElement('summary');summary.textContent=label+': '+t(advisor.Risk||'Review')+' - '+strings.AdvisorExplain;details.appendChild(summary);var box=document.createElement('div');box.className='advisor-explain';function addLine(caption,value){var line=document.createElement('p');var strong=document.createElement('strong');strong.textContent=caption+': ';line.appendChild(strong);line.appendChild(document.createTextNode(String(value||'--')));box.appendChild(line);}addLine(strings.AdvisorRuleId,advisor.RuleId);addLine(strings.AdvisorConfidence,confidenceText(advisor.Confidence));addLine(strings.AdvisorFinding,t(advisor.FindingCode||'CommercialEntitlementRequired'));var items=document.createElement('ul');items.className='advisor-evidence';var evidence=Array.isArray(advisor.Evidence)?advisor.Evidence:[];evidence.forEach(function(item){var li=document.createElement('li');li.textContent=sourceText(item.SourceCode)+': '+String(item.Value||'--');items.appendChild(li);});if(!evidence.length){var li=document.createElement('li');li.textContent=t('none');items.appendChild(li);}var evidenceLine=document.createElement('p');var evidenceStrong=document.createElement('strong');evidenceStrong.textContent=strings.AdvisorEvidence+':';evidenceLine.appendChild(evidenceStrong);box.appendChild(evidenceLine);box.appendChild(items);addLine(strings.AdvisorRecommendation,t(advisor.RecommendationCode||'AttachEvidenceAndAssign'));addLine(strings.AdvisorLimitation,t(advisor.LimitationCode||'LegalEntitlementNotProven'));details.appendChild(box);parent.appendChild(details);}
  function renderClients(){var needle=document.getElementById('filter').value.trim().toLowerCase();rows.textContent='';var shown=0;latestClients.forEach(function(client){var hay=[client.ComputerName,client.RemoteAddress,client.ClientReference,client.AssetReference,client.AssignmentDisplayName,client.Presence,client.WindowsStatus,client.OfficeStatus,client.ComplianceStatus].join(' ').toLowerCase();if(needle&&hay.indexOf(needle)<0){return;}shown++;var row=document.createElement('tr');var device=document.createElement('td');device.className='device';var name=document.createElement('strong');name.textContent=client.ComputerName||client.ClientReference;var ref=document.createElement('small');ref.textContent=client.ClientReference+(client.RemoteAddress?' / '+client.RemoteAddress:'');var asset=document.createElement('small');asset.textContent=strings.AssetLabel+': '+(client.AssetReference||'--');var assignment=document.createElement('small');assignment.textContent=strings.AssignedTo+': '+(client.AssignmentDisplayName||strings.Unassigned);device.appendChild(name);device.appendChild(ref);device.appendChild(asset);device.appendChild(assignment);row.appendChild(device);var presence=document.createElement('td');var badge=document.createElement('span');badge.className='pill '+String(client.Presence||'offline').toLowerCase();badge.textContent=client.Presence||'Offline';presence.appendChild(badge);row.appendChild(presence);var seen=client.LastSeenUtc?new Date(client.LastSeenUtc):null;var seenText=seen&&!isNaN(seen.getTime())?new Intl.DateTimeFormat(lang==='vi'?'vi-VN':'en-US',{dateStyle:'short',timeStyle:'short'}).format(seen):'--';var last=cell(row,seenText);last.title=client.AgeMinutes===null?'':String(client.AgeMinutes)+' min';statusCell(row,client.WindowsStatus,client.WindowsChannel,client.WindowsEntitlementStatus);statusCell(row,client.OfficeStatus,client.OfficeChannel,client.OfficeEntitlementStatus);var complianceCell=document.createElement('td');complianceCell.appendChild(complianceBadge(client.ComplianceStatus));appendAdvisor(complianceCell,'Windows',client.WindowsAdvisor);appendAdvisor(complianceCell,'Office',client.OfficeAdvisor);row.appendChild(complianceCell);var alertCell=document.createElement('td');var list=document.createElement('div');list.className='alert-list';var alerts=Array.isArray(client.Alerts)?client.Alerts:[];if(!alerts.length){var none=document.createElement('span');none.className='alert neutral';none.textContent=t('none');list.appendChild(none);}else{alerts.forEach(function(code){var alert=document.createElement('span');alert.className='alert';alert.textContent=t(code);list.appendChild(alert);});}alertCell.appendChild(list);row.appendChild(alertCell);rows.appendChild(row);});if(!shown){var row=document.createElement('tr');var td=cell(row,t('empty'),'empty');td.colSpan=7;rows.appendChild(row);}}
  function render(data){var summary=data.Summary||{};var compliance=data.Compliance||{};var complianceSummary=compliance.Summary||{};document.getElementById('server-name').textContent=data.Server&&data.Server.Name?data.Server.Name:'VietLicenSure';document.getElementById('count-total').textContent=summary.Total||0;document.getElementById('count-online').textContent=summary.Online||0;document.getElementById('count-stale').textContent=summary.Stale||0;document.getElementById('count-offline').textContent=summary.Offline||0;document.getElementById('count-review').textContent=summary.NeedsReview||0;document.getElementById('count-assets').textContent=summary.Assets||0;document.getElementById('count-assets-assigned').textContent=summary.AssignedAssets||0;document.getElementById('count-assets-unassigned').textContent=summary.UnassignedAssets||0;document.getElementById('count-assets-conflicts').textContent=summary.AssetConflicts||0;document.getElementById('count-score').textContent=summary.AssuranceScore||0;document.getElementById('count-compliant').textContent=summary.Compliant||0;document.getElementById('count-critical').textContent=summary.Critical||0;document.getElementById('count-purchased').textContent=complianceSummary.Purchased||0;document.getElementById('count-assigned').textContent=complianceSummary.Assigned||0;document.getElementById('count-installed').textContent=complianceSummary.Installed||0;document.getElementById('count-available').textContent=complianceSummary.Available||0;document.getElementById('generated-at').textContent=new Intl.DateTimeFormat(lang==='vi'?'vi-VN':'en-US',{dateStyle:'short',timeStyle:'medium'}).format(new Date(data.GeneratedAtUtc));latestClients=Array.isArray(data.Clients)?data.Clients:[];renderEntitlements(compliance);renderClients();warning.hidden=true;dashboard.hidden=false;setConnection('online',t('connected'));}
  async function load(){if(!token){warning.hidden=false;dashboard.hidden=true;setConnection('offline',t('failed'));return;}setConnection('waiting',t('connecting'));try{var response=await fetch('api/snapshot',{method:'GET',headers:{Authorization:'Bearer '+token},cache:'no-store',credentials:'omit'});if(response.status===401){sessionStorage.removeItem('vls-dashboard-token');token='';throw new Error('unauthorized');}if(!response.ok){throw new Error('http '+response.status);}render(await response.json());}catch(error){warning.hidden=false;dashboard.hidden=true;setConnection('offline',t('failed'));}}
  document.getElementById('refresh').addEventListener('click',load);document.getElementById('filter').addEventListener('input',renderClients);load();window.setInterval(load,60000);
}());
'@
}

function Normalize-ToolEnterpriseProductKey {
    param([Parameter(Mandatory = $true)][string]$ProductKey)
    $clean = ($ProductKey -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
    if ($clean.Length -ne 25) { throw (Get-ToolEnterpriseText "enterpriseCore.error.productKeyLength") }
    return (($clean -split '(.{5})' | Where-Object { $_ }) -join '-')
}

function New-ToolEnterpriseLicenseJob {
    param(
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][ValidateSet("InventoryOnly", "WindowsInstallAndActivate", "OfficeInstallAndActivate")][string]$Operation,
        [string]$ProductKey = "",
        [string]$RequestedBy = ""
    )

    $paths = Initialize-ToolEnterpriseStorage
    $clientRecord = Read-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $ClientId)
    if (-not $clientRecord) { throw (Get-ToolEnterpriseText "enterpriseCore.error.clientRecordMissing") }
    if ($Operation -ne "InventoryOnly" -and -not [bool]$clientRecord.AllowRemoteLicenseChanges) {
        throw (Get-ToolEnterpriseText "enterpriseCore.error.remoteLicenseChangesDisabled")
    }
    $normalizedKey = ""
    if ($Operation -ne "InventoryOnly") { $normalizedKey = Normalize-ToolEnterpriseProductKey -ProductKey $ProductKey }
    $clientSecret = Get-ToolEnterpriseServerClientSecret -ClientId $ClientId
    if (-not $clientSecret) { throw (Get-ToolEnterpriseText "enterpriseCore.error.serverClientSecretMissing") }
    $jobId = [Guid]::NewGuid().ToString("N")
    $job = [ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        JobId = $jobId
        ClientId = $ClientId
        Operation = $Operation
        ProductKey = $normalizedKey
        ProductKeyLast5 = if ($normalizedKey) { $normalizedKey.Substring($normalizedKey.Length - 5) } else { "" }
        RequestedBy = ConvertTo-ToolEnterpriseSafeText $RequestedBy 180
        RequestedAtUtc = [DateTime]::UtcNow.ToString("o")
        ExpiresAtUtc = [DateTime]::UtcNow.AddHours(24).ToString("o")
    }
    $envelope = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context "job:$ClientId`:$jobId" -Payload $job
    $clientJobDirectory = Join-Path $paths.ServerJobs $ClientId
    if (-not (Test-Path -LiteralPath $clientJobDirectory -PathType Container)) { New-Item -ItemType Directory -Path $clientJobDirectory -Force | Out-Null }
    Write-ToolEnterpriseJson -Path (Join-Path $clientJobDirectory ($jobId + ".job")) -Value ([ordered]@{ JobId=$jobId; Envelope=$envelope })
    Write-ToolEnterpriseAudit -Scope Server -Event "Job.Created" -Message (Get-ToolEnterpriseText "enterpriseCore.audit.jobCreated" @($Operation)) -Data ([ordered]@{
        JobId=$jobId; ClientId=$ClientId; Operation=$Operation; ProductKeyLast5=$job.ProductKeyLast5; RequestedBy=$job.RequestedBy
    })
    [Array]::Clear($clientSecret, 0, $clientSecret.Length)
    $normalizedKey = $null
    return [pscustomobject]@{ JobId=$jobId; ClientId=$ClientId; Operation=$Operation; ProductKeyLast5=$job.ProductKeyLast5 }
}

function Get-ToolEnterprisePendingJobPackage {
    param([Parameter(Mandatory = $true)][string]$ClientId)
    $paths = Initialize-ToolEnterpriseStorage
    $directory = Join-Path $paths.ServerJobs $ClientId
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return $null }
    $file = Get-ChildItem -LiteralPath $directory -Filter "*.job" -File -ErrorAction SilentlyContinue | Sort-Object CreationTimeUtc | Select-Object -First 1
    if (-not $file) { return $null }
    return (Read-ToolEnterpriseJson -Path $file.FullName)
}

function Save-ToolEnterpriseJobResult {
    param([Parameter(Mandatory = $true)][string]$ClientId, [Parameter(Mandatory = $true)][object]$Result)
    $paths = Initialize-ToolEnterpriseStorage
    $jobId = [string]$Result.JobId
    $parsedJobId = [Guid]::Empty
    if (-not [Guid]::TryParse($jobId, [ref]$parsedJobId)) { throw (Get-ToolEnterpriseText "enterpriseCore.error.jobResultIdInvalid") }
    $safeResult = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        JobId = $parsedJobId.ToString("N")
        ClientId = $ClientId
        Operation = ConvertTo-ToolEnterpriseSafeText $Result.Operation 80
        Status = ConvertTo-ToolEnterpriseSafeText $Result.Status 60
        ExitCode = [int]$Result.ExitCode
        Message = ConvertTo-ToolEnterpriseSafeText $Result.Message 4000
        ProductKeyLast5 = ConvertTo-ToolEnterpriseSafeText $Result.ProductKeyLast5 5
        StartedAtUtc = ConvertTo-ToolEnterpriseSafeText $Result.StartedAtUtc 60
        CompletedAtUtc = ConvertTo-ToolEnterpriseSafeText $Result.CompletedAtUtc 60
    }
    $resultDirectory = Join-Path $paths.ServerResults $ClientId
    if (-not (Test-Path -LiteralPath $resultDirectory -PathType Container)) { New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null }
    Write-ToolEnterpriseJson -Path (Join-Path $resultDirectory ($safeResult.JobId + ".json")) -Value $safeResult
    $pendingPath = Join-Path (Join-Path $paths.ServerJobs $ClientId) ($safeResult.JobId + ".job")
    if (Test-Path -LiteralPath $pendingPath -PathType Leaf) { Remove-Item -LiteralPath $pendingPath -Force }
    Write-ToolEnterpriseAudit -Scope Server -Event "Job.Completed" -Message $safeResult.Message -Data ([ordered]@{
        JobId=$safeResult.JobId; ClientId=$ClientId; Operation=$safeResult.Operation; Status=$safeResult.Status; ExitCode=$safeResult.ExitCode; ProductKeyLast5=$safeResult.ProductKeyLast5
    })
    return $safeResult
}

function Invoke-ToolEnterpriseCapturedProcess {
    param([Parameter(Mandatory = $true)][string]$FilePath, [Parameter(Mandatory = $true)][string]$Arguments, [int]$TimeoutSeconds = 120)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $asyncReaderAvailable = $null -ne ([IO.TextReader].GetMethod("ReadToEndAsync"))
    $psi.RedirectStandardError = $asyncReaderAvailable
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = if ($asyncReaderAvailable) { $process.StandardOutput.ReadToEndAsync() } else { $null }
    $stderrTask = if ($asyncReaderAvailable) { $process.StandardError.ReadToEndAsync() } else { $null }
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch {}
        throw (Get-ToolEnterpriseText "enterpriseCore.error.processTimeout" @($TimeoutSeconds))
    }
    if ($asyncReaderAvailable) {
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
    } else {
        # .NET 4.0/PowerShell 3 does not expose the async TextReader API.
        # The official slmgr/OSPP commands emit a small bounded response, so
        # the synchronous fallback is safe on the legacy target.
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = ""
    }
    return [pscustomobject]@{
        ExitCode = [int]$process.ExitCode
        Output = ConvertTo-ToolEnterpriseSafeText (($stdout, $stderr) -join [Environment]::NewLine) 8000
    }
}

function Get-ToolEnterpriseOfficeOsppPaths {
    $result = New-Object System.Collections.Generic.List[string]
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) | Where-Object { $_ } | Select-Object -Unique
    $known = @(
        "Microsoft Office\Office16\OSPP.VBS",
        "Microsoft Office\root\Office16\OSPP.VBS",
        "Microsoft Office\Office15\OSPP.VBS"
    )
    foreach ($root in $roots) {
        foreach ($relative in $known) {
            $path = Join-Path $root $relative
            if ((Test-Path -LiteralPath $path -PathType Leaf) -and $result -notcontains $path) { [void]$result.Add($path) }
        }
    }
    if ($result.Count -eq 0) {
        foreach ($root in $roots) {
            $officeRoot = Join-Path $root "Microsoft Office"
            if (-not (Test-Path -LiteralPath $officeRoot -PathType Container)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $officeRoot -Filter "OSPP.VBS" -File -Recurse -ErrorAction SilentlyContinue)) {
                if ($result -notcontains $file.FullName) { [void]$result.Add($file.FullName) }
            }
        }
    }
    return $result.ToArray()
}

function Invoke-ToolEnterpriseLicenseJob {
    param([Parameter(Mandatory = $true)][object]$Job, [bool]$AllowRemoteLicenseChanges)
    $started = [DateTime]::UtcNow
    $operation = [string]$Job.Operation
    $last5 = ConvertTo-ToolEnterpriseSafeText $Job.ProductKeyLast5 5
    $status = "Completed"
    $exitCode = 0
    $message = ""
    $key = [string]$Job.ProductKey
    try {
        $expires = [DateTime]::Parse([string]$Job.ExpiresAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        if ($expires.ToUniversalTime() -lt [DateTime]::UtcNow) { throw (Get-ToolEnterpriseText "enterpriseCore.error.jobExpired") }
        if ($operation -eq "InventoryOnly") {
            $message = Get-ToolEnterpriseText "enterpriseCore.job.inventoryRefreshed"
        } elseif (-not $AllowRemoteLicenseChanges) {
            $status = "Blocked"
            $exitCode = 20
            $message = Get-ToolEnterpriseText "enterpriseCore.job.remoteChangesBlocked"
        } elseif ($operation -eq "WindowsInstallAndActivate") {
            $key = Normalize-ToolEnterpriseProductKey -ProductKey $key
            $service = Get-WmiObject -Class SoftwareLicensingService -ErrorAction Stop | Select-Object -First 1
            if (-not $service) { throw (Get-ToolEnterpriseText "enterpriseCore.error.softwareLicensingServiceUnavailable") }
            $installResult = $service.InstallProductKey($key)
            if ($null -ne $installResult -and [int64]$installResult -ne 0) { throw (Get-ToolEnterpriseText "enterpriseCore.error.windowsInstallRejected" @($installResult)) }
            try { [void]$service.RefreshLicenseStatus() } catch {}
            $cscript = if (Get-Command Get-ToolNativeSystemPath -ErrorAction SilentlyContinue) { Get-ToolNativeSystemPath "cscript.exe" } else { Join-Path $env:SystemRoot "System32\cscript.exe" }
            $slmgr = if (Get-Command Get-ToolNativeSystemPath -ErrorAction SilentlyContinue) { Get-ToolNativeSystemPath "slmgr.vbs" } else { Join-Path $env:SystemRoot "System32\slmgr.vbs" }
            $activation = Invoke-ToolEnterpriseCapturedProcess -FilePath $cscript -Arguments ('//nologo "{0}" /ato' -f $slmgr) -TimeoutSeconds 180
            if ($activation.ExitCode -ne 0 -or $activation.Output -match '(?i)error|0xC[0-9A-F]+') {
                $status = "ActionRequired"
                $exitCode = 23
                $message = Get-ToolEnterpriseText "enterpriseCore.job.windowsActivationUnconfirmed" @($last5, $activation.Output)
            } else {
                $message = Get-ToolEnterpriseText "enterpriseCore.job.windowsActivationCompleted" @($last5)
            }
        } elseif ($operation -eq "OfficeInstallAndActivate") {
            $key = Normalize-ToolEnterpriseProductKey -ProductKey $key
            $osppPaths = @(Get-ToolEnterpriseOfficeOsppPaths)
            if ($osppPaths.Count -eq 0) { throw (Get-ToolEnterpriseText "enterpriseCore.error.osppMissing") }
            $cscript = if (Get-Command Get-ToolNativeSystemPath -ErrorAction SilentlyContinue) { Get-ToolNativeSystemPath "cscript.exe" } else { Join-Path $env:SystemRoot "System32\cscript.exe" }
            $ospp = [string]$osppPaths[0]
            $install = Invoke-ToolEnterpriseCapturedProcess -FilePath $cscript -Arguments ('//nologo "{0}" /inpkey:{1}' -f $ospp, $key) -TimeoutSeconds 180
            if ($install.ExitCode -ne 0 -or $install.Output -match '(?i)error|0xC[0-9A-F]+') { throw (Get-ToolEnterpriseText "enterpriseCore.error.officeInstallRejected" @($last5, $install.Output)) }
            $activation = Invoke-ToolEnterpriseCapturedProcess -FilePath $cscript -Arguments ('//nologo "{0}" /act' -f $ospp) -TimeoutSeconds 180
            if ($activation.ExitCode -ne 0 -or $activation.Output -match '(?i)error|0xC[0-9A-F]+') {
                $status = "ActionRequired"
                $exitCode = 23
                $message = Get-ToolEnterpriseText "enterpriseCore.job.officeActivationUnconfirmed" @($last5, $activation.Output)
            } else {
                $message = Get-ToolEnterpriseText "enterpriseCore.job.officeActivationCompleted" @($last5)
            }
        } else { throw (Get-ToolEnterpriseText "enterpriseCore.error.operationUnsupported") }
    } catch {
        if ($status -ne "Blocked") {
            $status = "Failed"
            $exitCode = 1
            $message = ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 4000
        }
    } finally { $key = $null }
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        JobId = [string]$Job.JobId
        ClientId = [string]$Job.ClientId
        Operation = $operation
        Status = $status
        ExitCode = $exitCode
        Message = $message
        ProductKeyLast5 = $last5
        StartedAtUtc = $started.ToString("o")
        CompletedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
}

function Export-ToolEnterpriseFleetReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DestinationDirectory,
        [ValidateSet("Json", "Csv", "Html", "Pdf")][string[]]$Formats = @("Json", "Csv", "Html"),
        [switch]$IncludePdf,
        [bool]$RedactSensitive = $true,
        [string[]]$ClientId = @(),
        [ValidateRange(0, 876000)][int]$MaximumClientAgeHours = 0,
        [ValidateRange(1, 876000)][int]$StaleAfterHours = 72
    )

    $requestedFormats = New-Object System.Collections.Generic.List[string]
    foreach ($format in @($Formats)) {
        $canonical = switch ([string]$format) {
            { $_ -ieq "Json" } { "Json"; break }
            { $_ -ieq "Csv" } { "Csv"; break }
            { $_ -ieq "Html" } { "Html"; break }
            { $_ -ieq "Pdf" } { "Pdf"; break }
        }
        if ($canonical -and -not $requestedFormats.Contains($canonical)) { [void]$requestedFormats.Add($canonical) }
    }
    if ($IncludePdf -and -not $requestedFormats.Contains("Pdf")) { [void]$requestedFormats.Add("Pdf") }
    if ($requestedFormats.Count -eq 0) { throw (Get-ToolEnterpriseText 'enterpriseReport.error.formatRequired') }

    $needsHtmlEngine = $requestedFormats.Contains("Html") -or $requestedFormats.Contains("Pdf")
    if ($needsHtmlEngine -and -not (Get-Command New-ToolProfessionalHtmlDocument -ErrorAction SilentlyContinue)) {
        $reportExportHelper = Join-Path $PSScriptRoot "Tool-ReportExport.ps1"
        if (-not (Test-Path -LiteralPath $reportExportHelper -PathType Leaf)) { throw (Get-ToolEnterpriseText "enterpriseReport.error.helperMissing") }
        . $reportExportHelper
    }

    $fullDestination = [IO.Path]::GetFullPath($DestinationDirectory)
    if (-not (Test-Path -LiteralPath $fullDestination -PathType Container)) { New-Item -ItemType Directory -Path $fullDestination -Force | Out-Null }
    if (Test-ToolEnterpriseReparsePoint -Path $fullDestination) {
        throw (Get-ToolEnterpriseText "enterpriseReport.error.destinationReparse" @($fullDestination))
    }

    $clientIdFilter = @{}
    foreach ($requestedClientId in @($ClientId)) {
        if ([string]::IsNullOrWhiteSpace([string]$requestedClientId)) { continue }
        $parsedClientId = [Guid]::Empty
        if (-not [Guid]::TryParse([string]$requestedClientId, [ref]$parsedClientId)) {
            throw (Get-ToolEnterpriseText 'enterpriseReport.error.clientIdInvalid' @($requestedClientId))
        }
        $clientIdFilter[$parsedClientId.ToString("D")] = $true
    }

    $allClients = @(Get-ToolEnterpriseServerClients)
    $filteredClients = New-Object System.Collections.Generic.List[object]
    $excludedById = 0
    $excludedByAge = 0
    foreach ($client in $allClients) {
        $rawClientId = [string]$client.ClientId
        $parsedRecordClientId = [Guid]::Empty
        $normalizedClientId = if ([Guid]::TryParse($rawClientId, [ref]$parsedRecordClientId)) { $parsedRecordClientId.ToString("D") } else { $rawClientId }
        if ($clientIdFilter.Count -gt 0 -and -not $clientIdFilter.ContainsKey($normalizedClientId)) {
            $excludedById++
            continue
        }
        $clientAgeHours = Get-ToolEnterpriseClientAgeHours -LastSeenUtc $client.LastSeenUtc
        if ($MaximumClientAgeHours -gt 0 -and $clientAgeHours -gt $MaximumClientAgeHours) {
            $excludedByAge++
            continue
        }
        [void]$filteredClients.Add([pscustomobject][ordered]@{
            Source = $client
            AgeHours = $clientAgeHours
            Freshness = if ($clientAgeHours -le $StaleAfterHours) { "Current" } else { "Stale" }
        })
    }

    $clients = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $filteredClients) {
        $source = $entry.Source
        $rawId = [string]$source.ClientId
        $clientReference = if ([string]::IsNullOrWhiteSpace($rawId)) { "CLIENT-UNKNOWN" } else { Get-ToolEnterpriseStableClientReference -ClientId $rawId }
        $redactionMarker = "[REDACTED]"
        $exportNetworkAddresses = @()
        if (-not $RedactSensitive) {
            $exportNetworkAddresses = @($source.NetworkAddresses | ForEach-Object { ConvertTo-ToolEnterpriseSafeText $_ 80 })
        }
        [void]$clients.Add([pscustomobject][ordered]@{
            ClientId = if ($RedactSensitive) { $clientReference } else { ConvertTo-ToolEnterpriseSafeText $rawId 80 }
            ComputerName = if ($RedactSensitive) { $clientReference } else { ConvertTo-ToolEnterpriseSafeText $source.ComputerName 100 }
            RemoteAddress = if ($RedactSensitive) { $redactionMarker } else { ConvertTo-ToolEnterpriseSafeText $source.RemoteAddress 80 }
            NetworkAddresses = $exportNetworkAddresses
            LastSeenUtc = ConvertTo-ToolEnterpriseSafeText $source.LastSeenUtc 80
            AgeHours = if ([double]::IsPositiveInfinity([double]$entry.AgeHours)) { $null } else { [Math]::Round([double]$entry.AgeHours, 2) }
            Freshness = [string]$entry.Freshness
            WindowsStatus = ConvertTo-ToolEnterpriseSafeText $source.WindowsStatus 100
            WindowsChannel = ConvertTo-ToolEnterpriseSafeText $source.WindowsChannel 120
            WindowsLast5 = if ($RedactSensitive -and -not [string]::IsNullOrWhiteSpace([string]$source.WindowsLast5)) { $redactionMarker } else { ConvertTo-ToolEnterpriseSafeText $source.WindowsLast5 10 }
            WindowsEntitlementStatus = "NotVerified"
            WindowsIdentityChanged = [bool]($source.PSObject.Properties['WindowsIdentityChanged'] -and $source.WindowsIdentityChanged)
            OfficeStatus = ConvertTo-ToolEnterpriseSafeText $source.OfficeStatus 100
            OfficeChannel = ConvertTo-ToolEnterpriseSafeText $source.OfficeChannel 120
            OfficeLast5 = if ($RedactSensitive -and -not [string]::IsNullOrWhiteSpace([string]$source.OfficeLast5)) { $redactionMarker } else { ConvertTo-ToolEnterpriseSafeText $source.OfficeLast5 10 }
            OfficeEntitlementStatus = "NotVerified"
            OfficeIdentityChanged = [bool]($source.PSObject.Properties['OfficeIdentityChanged'] -and $source.OfficeIdentityChanged)
            LicenseIdentityChangedAtUtc = ConvertTo-ToolEnterpriseSafeText $(if ($source.PSObject.Properties['LicenseIdentityChangedAtUtc']) { $source.LicenseIdentityChangedAtUtc } else { '' }) 80
            AllowRemoteLicenseChanges = [bool]$source.AllowRemoteLicenseChanges
        })
    }

    $stamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss-fff")
    $baseName = ([string](Get-ToolEnterpriseText "enterpriseReport.fileBase" @($stamp))) -replace '[<>:"/\\|?*]', '-'
    $finalDirectory = Join-Path $fullDestination $baseName
    if (Test-Path -LiteralPath $finalDirectory) { $finalDirectory = Join-Path $fullDestination ($baseName + "-" + [Guid]::NewGuid().ToString("N").Substring(0, 8)) }
    $stagingDirectory = Join-Path $fullDestination (".enterprise-export-" + [Guid]::NewGuid().ToString("N") + ".staging")
    New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
    $jsonStagePath = Join-Path $stagingDirectory ($baseName + ".json")
    $csvStagePath = Join-Path $stagingDirectory ($baseName + ".csv")
    $htmlStagePath = Join-Path $stagingDirectory ($baseName + ".html")
    $pdfStagePath = Join-Path $stagingDirectory ($baseName + ".pdf")
    $manifestStagePath = Join-Path $stagingDirectory ($baseName + "-SHA256SUMS.txt")
    $staleCount = @($clients | Where-Object { [string]$_.Freshness -eq "Stale" }).Count
    $redactedFields = @()
    if ($RedactSensitive) {
        $redactedFields = @("ClientId", "ComputerName", "RemoteAddress", "NetworkAddresses", "WindowsLast5", "OfficeLast5")
    }
    $fleet = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        CreatedAtUtc = [DateTime]::UtcNow.ToString("o")
        ClientCount = $clients.Count
        Selection = [pscustomobject][ordered]@{
            SourceClientCount = $allClients.Count
            IncludedClientCount = $clients.Count
            ExcludedByClientId = $excludedById
            ExcludedByMaximumAge = $excludedByAge
            MaximumClientAgeHours = $MaximumClientAgeHours
            ClientIdFilterCount = $clientIdFilter.Count
        }
        Freshness = [pscustomobject][ordered]@{
            StaleAfterHours = $StaleAfterHours
            CurrentClientCount = $clients.Count - $staleCount
            StaleClientCount = $staleCount
            InvalidOrMissingLastSeenCountsAsStale = $true
        }
        Privacy = [pscustomobject][ordered]@{
            RedactSensitive = $RedactSensitive
            FullProductKeysIncluded = $false
            InternalSourcePathsIncluded = $false
            RedactedFields = $redactedFields
            CsvFormulaProtection = $true
        }
        Formats = @($requestedFormats.ToArray())
        Clients = @($clients.ToArray())
    }

    $columnComputer = Get-ToolEnterpriseText "enterpriseReport.column.computer"
    $columnIp = Get-ToolEnterpriseText "enterpriseReport.column.ip"
    $columnLastSeen = Get-ToolEnterpriseText "enterpriseReport.column.lastSeen"
    $columnAgeHours = "AgeHours"
    $columnFreshness = "Freshness"
    $columnWindows = Get-ToolEnterpriseText "enterpriseReport.column.windows"
    $columnWindowsChannel = Get-ToolEnterpriseText "enterpriseReport.column.windowsChannel"
    $columnWindowsLast5 = Get-ToolEnterpriseText "enterpriseReport.column.windowsLast5"
    $columnOffice = Get-ToolEnterpriseText "enterpriseReport.column.office"
    $columnOfficeChannel = Get-ToolEnterpriseText "enterpriseReport.column.officeChannel"
    $columnOfficeLast5 = Get-ToolEnterpriseText "enterpriseReport.column.officeLast5"
    $columnIdentityChange = Get-ToolEnterpriseText "enterpriseReport.column.identityChange"
    $columnRemoteChanges = Get-ToolEnterpriseText "enterpriseReport.column.remoteChanges"
    $valueYes = Get-ToolEnterpriseText "enterpriseReport.value.yes"
    $valueNo = Get-ToolEnterpriseText "enterpriseReport.value.no"
    $fleetRows = @($clients | ForEach-Object {
        $row = [ordered]@{}
        $row[$columnComputer] = [string]$_.ComputerName
        $row[$columnIp] = [string]$_.RemoteAddress
        $row[$columnLastSeen] = [string]$_.LastSeenUtc
        $row[$columnAgeHours] = if ($null -eq $_.AgeHours) { "" } else { [string]$_.AgeHours }
        $row[$columnFreshness] = [string]$_.Freshness
        $row[$columnWindows] = [string]$_.WindowsStatus
        $row[$columnWindowsChannel] = [string]$_.WindowsChannel
        $row[$columnWindowsLast5] = [string]$_.WindowsLast5
        $row[$columnOffice] = [string]$_.OfficeStatus
        $row[$columnOfficeChannel] = [string]$_.OfficeChannel
        $row[$columnOfficeLast5] = [string]$_.OfficeLast5
        $row[$columnIdentityChange] = if ([bool]$_.WindowsIdentityChanged -or [bool]$_.OfficeIdentityChanged) {
            Get-ToolEnterpriseText "enterpriseReport.value.changed"
        } else { Get-ToolEnterpriseText "enterpriseReport.value.unchanged" }
        $row[$columnRemoteChanges] = if ([bool]$_.AllowRemoteLicenseChanges) { $valueYes } else { $valueNo }
        [pscustomobject]$row
    })

    $pdfResult = [pscustomobject][ordered]@{ Success=$false; Engine=""; Path=""; Error=(Get-ToolEnterpriseText "enterpriseReport.pdf.notRequested") }
    $published = $false
    try {
        if ($requestedFormats.Contains("Json")) {
            [IO.File]::WriteAllText($jsonStagePath, ($fleet | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        }
        if ($requestedFormats.Contains("Csv")) {
            $csvRows = @($fleetRows | ForEach-Object {
                $safeRow = [ordered]@{}
                foreach ($property in $_.PSObject.Properties) { $safeRow[$property.Name] = ConvertTo-ToolEnterpriseCsvSafeText $property.Value 2048 }
                [pscustomobject]$safeRow
            })
            if ($csvRows.Count -gt 0) {
                $csvRows | Export-Csv -LiteralPath $csvStagePath -NoTypeInformation -Encoding UTF8
            } else {
                $emptyRow = [ordered]@{}
                foreach ($columnName in @($columnComputer,$columnIp,$columnLastSeen,$columnAgeHours,$columnFreshness,$columnWindows,$columnWindowsChannel,$columnWindowsLast5,$columnOffice,$columnOfficeChannel,$columnOfficeLast5,$columnIdentityChange,$columnRemoteChanges)) {
                    $emptyRow[$columnName] = ""
                }
                $header = @([pscustomobject]$emptyRow | ConvertTo-Csv -NoTypeInformation)[0]
                [IO.File]::WriteAllText($csvStagePath, ($header + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
            }
        }
        if ($needsHtmlEngine) {
            $createdAt = [DateTime]::Now
            $activeWindows = @($clients | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.WindowsStatus) -and [string]$_.WindowsStatus -notin @("NotReported","Unknown") }).Count
            $activeOffice = @($clients | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.OfficeStatus) -and [string]$_.OfficeStatus -notin @("NotReported","Unknown") }).Count
            $reportCulture = if (Get-Command Get-ToolCulture -ErrorAction SilentlyContinue) {
                Get-ToolCulture
            } elseif ([string]$env:TOOL_UI_CULTURE -in @("vi-VN", "en-US")) {
                [string]$env:TOOL_UI_CULTURE
            } else { "vi-VN" }
            $html = New-ToolProfessionalHtmlDocument `
                -Title (Get-ToolEnterpriseText "enterpriseReport.title") `
                -Subtitle (Get-ToolEnterpriseText "enterpriseReport.subtitle") `
                -Eyebrow (Get-ToolEnterpriseText "enterpriseReport.eyebrow") `
                -Metadata @(
                    [pscustomobject]@{Label=(Get-ToolEnterpriseText "enterpriseReport.meta.server");Value=if ($RedactSensitive) { "[REDACTED]" } else { [string]$env:COMPUTERNAME }},
                    [pscustomobject]@{Label=(Get-ToolEnterpriseText "enterpriseReport.meta.time");Value=$createdAt.ToString("yyyy-MM-dd HH:mm:ss")},
                    [pscustomobject]@{Label=(Get-ToolEnterpriseText "enterpriseReport.meta.scope");Value=("Included {0}/{1}; stale {2}; age limit {3}h" -f $clients.Count,$allClients.Count,$staleCount,$MaximumClientAgeHours)},
                    [pscustomobject]@{Label=(Get-ToolEnterpriseText "enterpriseReport.meta.privacy");Value=("Redacted={0}; full keys=false; CSV formula protection=true" -f $RedactSensitive)}
                ) `
                -Cards @(
                    [pscustomobject]@{Label=(Get-ToolEnterpriseText "enterpriseReport.card.clients");Value=[string]$clients.Count;Tone="info"},
                    [pscustomobject]@{Label=(Get-ToolEnterpriseText "enterpriseReport.card.windowsStatus");Value=[string]$activeWindows;Tone=$(if ($activeWindows -eq $clients.Count) {"ok"} else {"warning"})},
                    [pscustomobject]@{Label=(Get-ToolEnterpriseText "enterpriseReport.card.officeStatus");Value=[string]$activeOffice;Tone=$(if ($activeOffice -eq $clients.Count) {"ok"} else {"warning"})},
                    [pscustomobject]@{Label=(Get-ToolEnterpriseText "enterpriseReport.card.formats");Value=(@($requestedFormats.ToArray()) -join " / ").ToUpperInvariant();Tone="info"}
                ) `
                -Sections @(
                    [pscustomobject]@{ Title=(Get-ToolEnterpriseText "enterpriseReport.section.clientList"); BodyHtml=(ConvertTo-ToolHtmlTable -Rows $fleetRows -Columns @($columnComputer,$columnIp,$columnLastSeen,$columnAgeHours,$columnFreshness,$columnWindows,$columnOffice,$columnIdentityChange)) },
                    [pscustomobject]@{ Title=(Get-ToolEnterpriseText "enterpriseReport.section.windowsDetails"); BodyHtml=(ConvertTo-ToolHtmlTable -Rows $fleetRows -Columns @($columnComputer,$columnWindows,$columnWindowsChannel,$columnWindowsLast5)) },
                    [pscustomobject]@{ Title=(Get-ToolEnterpriseText "enterpriseReport.section.officeDetails"); BodyHtml=(ConvertTo-ToolHtmlTable -Rows $fleetRows -Columns @($columnComputer,$columnOffice,$columnOfficeChannel,$columnOfficeLast5,$columnRemoteChanges)) },
                    [pscustomobject]@{ Title=(Get-ToolEnterpriseText "enterpriseReport.section.limitations"); BodyHtml="<p class='note'>$(ConvertTo-ToolHtmlText (Get-ToolEnterpriseText "enterpriseReport.limitationsNote"))</p>" }
                ) `
                -Footer (Get-ToolEnterpriseText "enterpriseReport.footer" @($script:ToolEnterpriseToolVersion)) -Culture $reportCulture -OfflineMode $true
            [IO.File]::WriteAllText($htmlStagePath, $html, (New-Object Text.UTF8Encoding($false)))
            if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $htmlStagePath)) { throw (Get-ToolEnterpriseText "enterpriseReport.error.htmlUnsafe") }
            if ($requestedFormats.Contains("Pdf")) {
                $pdfResult = Convert-ToolHtmlToPdf -HtmlPath $htmlStagePath -PdfPath $pdfStagePath
                if (-not $pdfResult.Success -or -not (Test-Path -LiteralPath $pdfStagePath -PathType Leaf)) {
                    $pdfError = if (-not [string]::IsNullOrWhiteSpace([string]$pdfResult.Error)) { [string]$pdfResult.Error } else { 'Unknown PDF conversion failure.' }
                    throw (Get-ToolEnterpriseText 'enterpriseReport.error.pdfFailed' @($pdfError))
                }
                $pdfGuide = New-ToolReportPdfGuideHtml -PdfRequested $true -PdfCreated $true -PdfFileName ([IO.Path]::GetFileName($pdfStagePath)) -Culture $reportCulture
                $html = $html.Replace('</main>', ($pdfGuide + '</main>'))
                [IO.File]::WriteAllText($htmlStagePath, $html, (New-Object Text.UTF8Encoding($false)))
            }
            if (-not $requestedFormats.Contains("Html") -and (Test-Path -LiteralPath $htmlStagePath -PathType Leaf)) {
                Remove-Item -LiteralPath $htmlStagePath -Force
            }
        }

        $manifestLines = @((Get-ToolEnterpriseText "enterpriseReport.manifestHeader" @($script:ToolEnterpriseToolVersion)))
        foreach ($path in @($jsonStagePath,$csvStagePath,$htmlStagePath,$pdfStagePath)) {
            if (Test-Path -LiteralPath $path -PathType Leaf) { $manifestLines += "$(Get-ToolEnterpriseSha256Hex -Path $path)  $([IO.Path]::GetFileName($path))" }
        }
        [IO.File]::WriteAllLines($manifestStagePath, $manifestLines, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $stagingDirectory -Destination $finalDirectory
        $published = $true
    } finally {
        if (-not $published -and (Test-Path -LiteralPath $stagingDirectory -PathType Container)) {
            $expectedPrefix = $fullDestination.TrimEnd('\') + '\.enterprise-export-'
            $resolvedStage = [IO.Path]::GetFullPath($stagingDirectory)
            if ($resolvedStage.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and $resolvedStage.EndsWith('.staging', [StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $jsonPath = if ($requestedFormats.Contains("Json")) { Join-Path $finalDirectory ([IO.Path]::GetFileName($jsonStagePath)) } else { "" }
    $csvPath = if ($requestedFormats.Contains("Csv")) { Join-Path $finalDirectory ([IO.Path]::GetFileName($csvStagePath)) } else { "" }
    $htmlPath = if ($requestedFormats.Contains("Html")) { Join-Path $finalDirectory ([IO.Path]::GetFileName($htmlStagePath)) } else { "" }
    $pdfPath = if ($pdfResult.Success) { Join-Path $finalDirectory ([IO.Path]::GetFileName($pdfStagePath)) } else { "" }
    if ($pdfResult.Success -and $pdfResult.PSObject.Properties["Path"]) { $pdfResult.Path = $pdfPath }
    $manifestPath = Join-Path $finalDirectory ([IO.Path]::GetFileName($manifestStagePath))
    return [pscustomobject][ordered]@{
        ExportDirectory = $finalDirectory
        JsonPath = $jsonPath
        CsvPath = $csvPath
        HtmlPath = $htmlPath
        PdfPath = $pdfPath
        Pdf = $pdfResult
        ManifestPath = $manifestPath
        ClientCount = $clients.Count
        SourceClientCount = $allClients.Count
        StaleClientCount = $staleCount
        RedactSensitive = $RedactSensitive
        Formats = @($requestedFormats.ToArray())
    }
}

function Find-ToolEnterpriseNetworkDevices {
    param(
        [Parameter(Mandatory = $true)][string]$Cidr,
        [ValidateRange(50, 3000)][int]$TimeoutMs = 350,
        [ValidateRange(1, 128)][int]$ThrottleLimit = 48,
        [int[]]$ProbePorts = @($script:ToolEnterpriseDefaultPort,445,3389)
    )

    $addresses = @(Get-ToolEnterpriseCidrAddresses -Cidr $Cidr)
    $knownNeighbors = @{}
    try {
        if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
            foreach ($neighbor in @(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { [string]$_.State -notin @('Unreachable','Incomplete') })) {
                if ([string]$neighbor.IPAddress -match '^\d{1,3}(?:\.\d{1,3}){3}$') { $knownNeighbors[[string]$neighbor.IPAddress] = $true }
            }
        }
    } catch {}
    try {
        foreach ($line in @(& (Join-Path $env:SystemRoot 'System32\arp.exe') -a 2>$null)) {
            if ([string]$line -match '(?<![0-9.])(\d{1,3}(?:\.\d{1,3}){3})(?![0-9.])\s+[0-9a-f-]{17}\s+(?:dynamic|static)') {
                $knownNeighbors[[string]$matches[1]] = $true
            }
        }
    } catch {}
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit)
    $pool.Open()
    $workers = New-Object System.Collections.Generic.List[object]
    $scriptText = @'
param($Address,$TimeoutMs,$KnownNeighbor,$ProbePorts)
$reachable = [bool]$KnownNeighbor
$latency = -1
$hostName = ""
$methods = New-Object System.Collections.Generic.List[string]
$openPorts = New-Object System.Collections.Generic.List[int]
if ($KnownNeighbor) { [void]$methods.Add('NeighborCache') }
$ping = New-Object Net.NetworkInformation.Ping
try {
    $reply = $ping.Send($Address, $TimeoutMs)
    if ($reply -and $reply.Status -eq [Net.NetworkInformation.IPStatus]::Success) {
        $reachable = $true
        $latency = [long]$reply.RoundtripTime
        [void]$methods.Add('ICMP')
    }
} catch {} finally { $ping.Dispose() }
foreach ($probePort in @($ProbePorts | Select-Object -Unique)) {
    if ([int]$probePort -lt 1 -or [int]$probePort -gt 65535) { continue }
    $client = New-Object Net.Sockets.TcpClient
    $handle = $null
    try {
        $handle = $client.BeginConnect($Address, [int]$probePort, $null, $null)
        if ($handle.AsyncWaitHandle.WaitOne([Math]::Max(80,$TimeoutMs), $false)) {
            $client.EndConnect($handle)
            if ($client.Connected) {
                $reachable = $true
                [void]$openPorts.Add([int]$probePort)
                [void]$methods.Add("TCP:$probePort")
            }
        }
    } catch {} finally {
        if ($handle -and $handle.AsyncWaitHandle) { try { $handle.AsyncWaitHandle.Close() } catch {} }
        $client.Close()
    }
}
if ($reachable) { try { $hostName = [Net.Dns]::GetHostEntry($Address).HostName } catch {} }
[pscustomobject]@{ Address=$Address; Reachable=$reachable; LatencyMs=$latency; HostName=$hostName; DiscoveryMethod=(@($methods|Select-Object -Unique)-join ','); OpenPorts=@($openPorts|Select-Object -Unique) }
'@
    try {
        foreach ($address in $addresses) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($scriptText).AddArgument($address).AddArgument($TimeoutMs).AddArgument([bool]$knownNeighbors.ContainsKey($address)).AddArgument(@($ProbePorts))
            $handle = $powerShell.BeginInvoke()
            [void]$workers.Add([pscustomobject]@{ PowerShell=$powerShell; Handle=$handle })
        }
        $results = New-Object System.Collections.Generic.List[object]
        foreach ($worker in $workers) {
            try {
                foreach ($item in @($worker.PowerShell.EndInvoke($worker.Handle))) {
                    if ($item.Reachable) { [void]$results.Add($item) }
                }
            } finally { $worker.PowerShell.Dispose() }
        }
        return @($results.ToArray() | Sort-Object { ConvertTo-ToolEnterpriseIPv4UInt32 -Address $_.Address })
    } finally { $pool.Close(); $pool.Dispose() }
}

function Find-ToolEnterpriseServers {
    param(
        [Parameter(Mandatory = $true)][string]$Cidr,
        [ValidateRange(1024,65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [ValidateRange(100,3000)][int]$TimeoutMs = 450,
        [ValidateRange(1,128)][int]$ThrottleLimit = 64
    )

    $addresses = @(Get-ToolEnterpriseCidrAddresses -Cidr $Cidr)
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit)
    $pool.Open()
    $workers = New-Object System.Collections.Generic.List[object]
$scriptText = @'
param($Address,$Port,$TimeoutMs,$ExpectedProtocolVersion,$ExpectedToolVersion)
$response = $null
try {
    $uri = "http://$Address`:$Port/tool/v1/status"
    $request = [Net.HttpWebRequest]::Create($uri)
    $request.Method = "GET"
    $request.Timeout = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $request.AllowAutoRedirect = $false
    $request.Proxy = $null
    $response = [Net.HttpWebResponse]$request.GetResponse()
    if ([int]$response.StatusCode -eq 200) {
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $status = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        if ([bool]$status.Accepted -and
            [string]$status.ProtocolVersion -eq [string]$ExpectedProtocolVersion -and
            [string]$status.ToolVersion -eq [string]$ExpectedToolVersion) {
            [pscustomobject]@{
                Address=$Address
                Port=$Port
                ServerId=""
                ServerName=$Address
                ToolVersion=[string]$status.ToolVersion
                ProtocolVersion=[string]$status.ProtocolVersion
            }
        }
    }
} catch {} finally { if ($response) { $response.Close() } }
'@
    try {
        foreach ($address in $addresses) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($scriptText).AddArgument($address).AddArgument($Port).AddArgument($TimeoutMs).AddArgument($script:ToolEnterpriseProtocolVersion).AddArgument($script:ToolEnterpriseToolVersion)
            $handle = $powerShell.BeginInvoke()
            [void]$workers.Add([pscustomobject]@{ PowerShell=$powerShell; Handle=$handle })
        }
        $results = New-Object System.Collections.Generic.List[object]
        foreach ($worker in $workers) {
            try {
                foreach ($item in @($worker.PowerShell.EndInvoke($worker.Handle))) {
                    if ($item) { [void]$results.Add($item) }
                }
            } finally { $worker.PowerShell.Dispose() }
        }
        return @($results.ToArray() | Sort-Object { ConvertTo-ToolEnterpriseIPv4UInt32 -Address $_.Address })
    } finally { $pool.Close(); $pool.Dispose() }
}

function Find-ToolEnterpriseLocalServers {
    param(
        [ValidateRange(1024,65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [ValidateRange(100,3000)][int]$TimeoutMs = 450,
        [ValidateRange(1,128)][int]$ThrottleLimit = 64
    )

    $results = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($cidr in @(Get-ToolEnterpriseLocalDiscoveryCidrs)) {
        foreach ($server in @(Find-ToolEnterpriseServers -Cidr $cidr -Port $Port -TimeoutMs $TimeoutMs -ThrottleLimit $ThrottleLimit)) {
            $key = if (-not [string]::IsNullOrWhiteSpace([string]$server.ServerId)) {
                [string]$server.ServerId
            } else { "{0}:{1}" -f [string]$server.Address, [int]$server.Port }
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            [void]$results.Add($server)
        }
    }
    return @($results.ToArray() | Sort-Object -Property @{Expression={ ConvertTo-ToolEnterpriseIPv4UInt32 -Address ([string]$_.Address) }})
}

function Get-ToolEnterpriseMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ProtocolVersion = $script:ToolEnterpriseProtocolVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        DefaultPort = $script:ToolEnterpriseDefaultPort
        MaximumRequestBytes = $script:ToolEnterpriseMaximumRequestBytes
        MaximumScanHosts = $script:ToolEnterpriseMaximumScanHosts
        Encryption = "AES-256-CBC + HMAC-SHA256; DPAPI LocalMachine at rest"
        FullProductKeysInReports = $false
        RemoteLicenseChangesRequireClientOptIn = $true
    }
}
