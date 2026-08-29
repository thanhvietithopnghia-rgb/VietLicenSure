[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateLength(1, 24000)]
    [string]$PayloadBase64
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$bridgeFailureExitCode = 87

function Get-BridgeAccountSid {
    param([string]$Account)
    try {
        return (New-Object Security.Principal.NTAccount($Account)).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch {
        return ''
    }
}

function Test-BridgeProtectedDirectoryAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('User','Machine')][string]$DataScope,
        [string]$AllowedUserSid = ''
    )
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $ownerSid = Get-BridgeAccountSid ([string]$acl.Owner)
        $allowedOwners = @('S-1-5-32-544','S-1-5-18')
        $allowedWriters = @('S-1-5-32-544','S-1-5-18')
        if ($DataScope -eq 'User') {
            if ($AllowedUserSid -notmatch '^S-1-5-21-(?:\d+-){2}\d+-\d+$') { return $false }
            $allowedOwners += $AllowedUserSid
            $allowedWriters += $AllowedUserSid
        }
        if ($ownerSid -notin $allowedOwners -or -not $acl.AreAccessRulesProtected) { return $false }
        $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor
            [Security.AccessControl.FileSystemRights]::Modify -bor
            [Security.AccessControl.FileSystemRights]::FullControl -bor
            [Security.AccessControl.FileSystemRights]::Delete -bor
            [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
            [Security.AccessControl.FileSystemRights]::TakeOwnership
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
                $allowedWriters -notcontains $rule.IdentityReference.Value -and
                (($rule.FileSystemRights -band $writeMask) -ne 0)) { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

function Get-BridgeSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant() }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-BridgeIntegrityManifest {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    $entries = @{}
    foreach ($line in Get-Content -LiteralPath $ManifestPath -ErrorAction Stop) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?([^\\/]+)$') { throw 'ElevatedBrokerIntegrityManifestInvalid' }
        $name = [string]$matches[2]
        if ([IO.Path]::GetFileName($name) -cne $name -or $entries.ContainsKey($name)) { throw 'ElevatedBrokerIntegrityManifestInvalid' }
        $entries[$name] = ([string]$matches[1]).ToUpperInvariant()
    }
    if ($entries.Count -lt 50) { throw 'ElevatedBrokerIntegrityManifestIncomplete' }
    return $entries
}

function Assert-BridgeOriginalPayloadIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$TrustedRoot,
        [Parameter(Mandatory = $true)][string]$OriginalRoot
    )
    $trustedManifestPath = Join-Path $TrustedRoot 'TOOL-SHA256SUMS.txt'
    $originalManifestPath = Join-Path $OriginalRoot 'TOOL-SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $trustedManifestPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $originalManifestPath -PathType Leaf) -or
        (Get-BridgeSha256 $trustedManifestPath) -cne (Get-BridgeSha256 $originalManifestPath)) {
        throw 'ElevatedBrokerOriginalManifestMismatch'
    }
    $entries = Get-BridgeIntegrityManifest -ManifestPath $trustedManifestPath
    foreach ($name in $entries.Keys) {
        $trustedPath = Join-Path $TrustedRoot $name
        $originalPath = Join-Path $OriginalRoot $name
        foreach ($path in @($trustedPath,$originalPath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'ElevatedBrokerPayloadMissing' }
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ElevatedBrokerPayloadReparsePointRejected' }
        }
        $expected = [string]$entries[$name]
        if ((Get-BridgeSha256 $trustedPath) -cne $expected -or (Get-BridgeSha256 $originalPath) -cne $expected) {
            throw 'ElevatedBrokerPayloadHashMismatch'
        }
    }
    return $entries
}

function ConvertFrom-BridgeTargetArguments {
    param([Parameter(Mandatory = $true)][string]$Arguments)

    $syntheticPrefix = 'powershell.exe '
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($syntheticPrefix + $Arguments, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -ne 0) { throw 'ElevatedBridgeArgumentsParseInvalid' }
    $commands = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst]
    }, $true))
    if ($commands.Count -ne 1) { throw 'ElevatedBridgeArgumentsCommandCountInvalid' }
    $command = $commands[0]
    if ($command.InvocationOperator -ne [Management.Automation.Language.TokenKind]::Unknown -or @($command.Redirections).Count -ne 0) {
        throw 'ElevatedBridgeArgumentsSyntaxRejected'
    }
    $elements = @($command.CommandElements)
    if ($elements.Count -lt 6 -or
        -not ($elements[0] -is [Management.Automation.Language.StringConstantExpressionAst]) -or
        [string]$elements[0].Value -cne 'powershell.exe' -or
        -not ($elements[1] -is [Management.Automation.Language.CommandParameterAst]) -or
        [string]$elements[1].ParameterName -cne 'NoProfile' -or $elements[1].Extent.Text -cne '-NoProfile' -or
        -not ($elements[2] -is [Management.Automation.Language.CommandParameterAst]) -or
        [string]$elements[2].ParameterName -cne 'ExecutionPolicy' -or $elements[2].Extent.Text -cne '-ExecutionPolicy' -or
        -not ($elements[3] -is [Management.Automation.Language.StringConstantExpressionAst]) -or
        [string]$elements[3].Value -cne 'RemoteSigned' -or
        -not ($elements[4] -is [Management.Automation.Language.CommandParameterAst]) -or
        [string]$elements[4].ParameterName -cne 'File' -or $elements[4].Extent.Text -cne '-File' -or
        -not ($elements[5] -is [Management.Automation.Language.StringConstantExpressionAst])) {
        throw 'ElevatedBridgeHostArgumentsInvalid'
    }

    $parameters = @{}
    for ($index = 6; $index -lt $elements.Count; $index++) {
        $element = $elements[$index]
        if (-not ($element -is [Management.Automation.Language.CommandParameterAst]) -or
            $element.Extent.Text -notmatch '^-[A-Za-z][A-Za-z0-9]*$') {
            throw 'ElevatedBridgeScriptArgumentSyntaxInvalid'
        }
        $name = ([string]$element.ParameterName).ToLowerInvariant()
        if ($parameters.ContainsKey($name)) { throw 'ElevatedBridgeScriptArgumentDuplicate' }
        $hasValue = $false
        $value = ''
        if (($index + 1) -lt $elements.Count -and -not ($elements[$index + 1] -is [Management.Automation.Language.CommandParameterAst])) {
            $valueElement = $elements[$index + 1]
            if ($valueElement -is [Management.Automation.Language.StringConstantExpressionAst]) {
                $value = [string]$valueElement.Value
            } elseif ($valueElement -is [Management.Automation.Language.ConstantExpressionAst]) {
                $value = [string]$valueElement.Value
            } else {
                throw 'ElevatedBridgeScriptArgumentValueInvalid'
            }
            if ([string]::IsNullOrWhiteSpace($value) -or $value.Length -gt 4096 -or $value -match "[`0`r`n]") {
                throw 'ElevatedBridgeScriptArgumentValueInvalid'
            }
            $hasValue = $true
            $index++
        }
        $parameters[$name] = [pscustomobject]@{ HasValue=$hasValue; Value=$value }
    }
    return [pscustomobject]@{
        ScriptPath = [string]$elements[5].Value
        Parameters = $parameters
    }
}

function Get-BridgeArgumentValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $key = $Name.ToLowerInvariant()
    if (-not $Parameters.ContainsKey($key) -or -not [bool]$Parameters[$key].HasValue) { return '' }
    return [string]$Parameters[$key].Value
}

function Test-BridgePathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    try {
        if (-not [IO.Path]::IsPathRooted($Path)) { return $false }
        $fullPath = [IO.Path]::GetFullPath($Path)
        $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        return $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Assert-BridgeModuleArgumentProfile {
    param(
        [Parameter(Mandatory = $true)][string]$ModuleId,
        [Parameter(Mandatory = $true)][object]$ParsedArguments,
        [Parameter(Mandatory = $true)][string]$OriginalRuntimeRoot,
        [Parameter(Mandatory = $true)][string]$TrustedLauncherPath
    )

    $parameters = [hashtable]$ParsedArguments.Parameters
    $allowed = @()
    $required = @()
    $switches = @()
    switch ($ModuleId) {
        { $_ -in @('report.all','report.hardware','report.windows','report.office','report.software') } {
            $allowed = @('outputdir','mode','culture','approvedkmsserverfile','scansettingspath','pdf','redactsensitive','fullinternal')
            $required = @('outputdir','mode','culture','approvedkmsserverfile','scansettingspath','pdf')
            $switches = @('pdf','redactsensitive','fullinternal')
        }
        'cleanup.scan' {
            $allowed = @('outputdir','approvedkmsserverfile','treatunapprovedkmsasnoncompliant','decisionfile','scanscope','culture','redactsensitive')
            $required = @('outputdir','approvedkmsserverfile','treatunapprovedkmsasnoncompliant','decisionfile','scanscope','culture')
            $switches = @('treatunapprovedkmsasnoncompliant','redactsensitive')
        }
        'cleanup.deep' {
            $allowed = @('outputdir','remediate','deepclean','dryrun','approvedkmsserverfile','treatunapprovedkmsasnoncompliant','decisionfile','selectionfile','scanscope','culture','redactsensitive')
            $required = @('outputdir','remediate','deepclean','approvedkmsserverfile','treatunapprovedkmsasnoncompliant','decisionfile','selectionfile','scanscope','culture')
            $switches = @('remediate','deepclean','dryrun','treatunapprovedkmsasnoncompliant','redactsensitive')
        }
        'cleanup.repair' {
            $allowed = @('outputdir','repairscansources','decisionfile','culture','redactsensitive')
            $required = @('outputdir','repairscansources','decisionfile','culture')
            $switches = @('repairscansources','redactsensitive')
        }
        'application.update.apply' {
            $allowed = @('mode','consentgranted','culture','currentversion','expectedversion','manifesturl','launcherpath','launcherprocessid','expectedcurrentsha256','norestart','noui')
            $required = @('mode','consentgranted','culture','currentversion','expectedversion','manifesturl','launcherpath','launcherprocessid','expectedcurrentsha256')
            $switches = @('consentgranted','norestart','noui')
        }
        'oem.apply' {
            $allowed = @('mode','outputdir','decisionfile','culture')
            $required = @('mode','outputdir','decisionfile','culture')
        }
        'license.deep-scan' {
            $allowed = @('outputdir','approvedkmsserverfile','decisionfile','culture','redactsensitive','noopen')
            $required = @('outputdir','approvedkmsserverfile','decisionfile','culture','noopen')
            $switches = @('redactsensitive','noopen')
        }
        'forensics.scan' {
            $allowed = @('outputdir','approvedkmsserverfile','decisionfile','culture','redactsensitive','noopen')
            $required = @('outputdir','approvedkmsserverfile','decisionfile','culture','noopen')
            $switches = @('redactsensitive','noopen')
        }
        'license.manager' {
            $allowed = @()
            $required = @()
        }
        'backup.create' {
            $allowed = @('outputdir','decisionfile','scope','culture')
            $required = @('outputdir','decisionfile','scope','culture')
        }
        'restore.apply' {
            $allowed = @('backupdir','decisionfile','scope','culture')
            $required = @('backupdir','decisionfile','scope','culture')
        }
        default { throw 'ElevatedBridgeModuleArgumentProfileMissing' }
    }

    foreach ($name in $parameters.Keys) {
        if ($allowed -notcontains $name) { throw 'ElevatedBridgeModuleArgumentNotAllowed' }
        if ($switches -contains $name) {
            if ([bool]$parameters[$name].HasValue) { throw 'ElevatedBridgeModuleSwitchValueRejected' }
        } elseif (-not [bool]$parameters[$name].HasValue) {
            throw 'ElevatedBridgeModuleArgumentValueRequired'
        }
    }
    foreach ($name in $required) {
        if (-not $parameters.ContainsKey($name)) { throw 'ElevatedBridgeModuleArgumentRequired' }
    }

    $culture = Get-BridgeArgumentValue -Parameters $parameters -Name 'culture'
    if ($parameters.ContainsKey('culture') -and $culture -notin @('vi-VN','en-US')) { throw 'ElevatedBridgeCultureInvalid' }
    $scope = Get-BridgeArgumentValue -Parameters $parameters -Name 'scope'
    if ($parameters.ContainsKey('scope') -and $scope -notin @('All','Windows','Office','ThirdParty')) { throw 'ElevatedBridgeScopeInvalid' }
    $scanScope = Get-BridgeArgumentValue -Parameters $parameters -Name 'scanscope'
    if ($parameters.ContainsKey('scanscope') -and $scanScope -notin @('All','Windows','Office','ThirdParty','WindowsOffice','WindowsThirdParty','OfficeThirdParty')) {
        throw 'ElevatedBridgeScanScopeInvalid'
    }
    foreach ($pathName in @('outputdir','approvedkmsserverfile','scansettingspath','decisionfile','selectionfile','launcherpath','backupdir')) {
        if ($parameters.ContainsKey($pathName) -and -not [IO.Path]::IsPathRooted((Get-BridgeArgumentValue -Parameters $parameters -Name $pathName))) {
            throw 'ElevatedBridgePathArgumentInvalid'
        }
    }
    foreach ($runtimePathName in @('decisionfile','selectionfile')) {
        if ($parameters.ContainsKey($runtimePathName) -and
            -not (Test-BridgePathWithin -Path (Get-BridgeArgumentValue -Parameters $parameters -Name $runtimePathName) -Root $OriginalRuntimeRoot)) {
            throw 'ElevatedBridgeRuntimeArgumentOutsideSession'
        }
    }

    if ($ModuleId -like 'report.*') {
        $expectedMode = switch ($ModuleId) {
            'report.hardware' { 'Hardware' }
            'report.windows' { 'Windows' }
            'report.office' { 'Office' }
            'report.software' { 'Software' }
            default { 'All' }
        }
        if ((Get-BridgeArgumentValue -Parameters $parameters -Name 'mode') -cne $expectedMode -or
            ([int]$parameters.ContainsKey('redactsensitive') + [int]$parameters.ContainsKey('fullinternal')) -ne 1) {
            throw 'ElevatedBridgeReportArgumentProfileInvalid'
        }
    }
    if ($ModuleId -eq 'application.update.apply') {
        $manifestUrl = Get-BridgeArgumentValue -Parameters $parameters -Name 'manifesturl'
        $launcherPath = Get-BridgeArgumentValue -Parameters $parameters -Name 'launcherpath'
        $launcherProcessId = Get-BridgeArgumentValue -Parameters $parameters -Name 'launcherprocessid'
        if ((Get-BridgeArgumentValue -Parameters $parameters -Name 'mode') -cne 'Apply' -or
            -not [string]::Equals([IO.Path]::GetFullPath($launcherPath), [IO.Path]::GetFullPath($TrustedLauncherPath), [StringComparison]::OrdinalIgnoreCase) -or
            $manifestUrl -notmatch '^https://[^\s]+$' -or
            $launcherProcessId -notmatch '^[1-9][0-9]{0,9}$' -or
            (Get-BridgeArgumentValue -Parameters $parameters -Name 'currentversion') -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
            (Get-BridgeArgumentValue -Parameters $parameters -Name 'expectedversion') -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
            (Get-BridgeArgumentValue -Parameters $parameters -Name 'expectedcurrentsha256') -notmatch '^[A-Fa-f0-9]{64}$') {
            throw 'ElevatedBridgeUpdateArgumentProfileInvalid'
        }
    }
    if ($ModuleId -eq 'oem.apply' -and (Get-BridgeArgumentValue -Parameters $parameters -Name 'mode') -cne 'Apply') {
        throw 'ElevatedBridgeOemArgumentProfileInvalid'
    }
}

try {
    if ([string]$env:TOOL_ELEVATION_BROKER -ne '1') { throw 'ElevatedBrokerCompiledLauncherRequired' }
    $brokerBuildState = [string]$env:TOOL_OFFICIAL_BUILD_STATE
    $brokerBuildFailure = [string]$env:TOOL_OFFICIAL_BUILD_FAILURE
    $brokerBuildId = [string]$env:TOOL_OFFICIAL_BUILD_ID
    $brokerVerificationUrl = [string]$env:TOOL_OFFICIAL_VERIFICATION_URL
    $brokerSelfUpdateAllowed = [string]$env:TOOL_SELF_UPDATE_ALLOWED
    $brokerLauncherPath = [IO.Path]::GetFullPath([string]$env:TOOL_LAUNCHER_PATH)
    $brokerDataRoot = [IO.Path]::GetFullPath([string]$env:TOOL_DATA_ROOT).TrimEnd('\')
    $brokerSecureRuntimeRoot = [IO.Path]::GetFullPath([string]$env:TOOL_SECURE_RUNTIME_DIR).TrimEnd('\')
    if ([string]$env:TOOL_DATA_SCOPE -ne 'Machine') { throw 'ElevatedBrokerMachineScopeRequired' }
    $brokerLauncherPid = 0
    if (-not [int]::TryParse([string]$env:TOOL_LAUNCHER_PID, [ref]$brokerLauncherPid) -or $brokerLauncherPid -le 0 -or
        -not (Test-Path -LiteralPath $brokerLauncherPath -PathType Leaf)) { throw 'ElevatedBrokerLauncherIdentityInvalid' }
    $brokerLauncherItem = Get-Item -LiteralPath $brokerLauncherPath -Force -ErrorAction Stop
    if (($brokerLauncherItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ElevatedBrokerLauncherReparsePointRejected' }
    $brokerProcess = Get-Process -Id $brokerLauncherPid -ErrorAction Stop
    if (-not [string]::Equals([IO.Path]::GetFullPath($brokerProcess.Path), $brokerLauncherPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ElevatedBrokerLauncherProcessMismatch'
    }

    $provenanceHelperPath = Join-Path $PSScriptRoot 'Tool-Provenance.ps1'
    if (-not (Test-Path -LiteralPath $provenanceHelperPath -PathType Leaf)) { throw 'ElevatedBridgeProvenanceMissing' }
    . $provenanceHelperPath
    $bridgeReleaseIdentity = Get-ToolProvenanceExpectedValues
    $expectedOfficialBuildId = [string]$bridgeReleaseIdentity.BuildId
    if ([string]::IsNullOrWhiteSpace($expectedOfficialBuildId)) { throw 'ElevatedBridgeBuildIdMissing' }
    $protectedProvenancePath = Join-Path $PSScriptRoot 'OFFICIAL-PROVENANCE-v1.json'
    $protectedProvenanceSignaturePath = Join-Path $PSScriptRoot 'OFFICIAL-PROVENANCE-v1.json.p7s'
    $protectedProvenance = Get-ToolOfficialBuildState -ManifestPath $protectedProvenancePath -SignaturePath $protectedProvenanceSignaturePath
    $brokerProvenanceOfficial = [bool]$protectedProvenance.IsOfficial

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'ElevatedBridgeArchitectureMismatch' }
    $payloadBytes = [Convert]::FromBase64String($PayloadBase64)
    if ($payloadBytes.Length -le 0 -or $payloadBytes.Length -gt 18000) { throw 'ElevatedBridgePayloadSizeInvalid' }
    $payload = [Text.Encoding]::UTF8.GetString($payloadBytes) | ConvertFrom-Json
    if ([string]$payload.SchemaVersion -ne '2.0') { throw 'ElevatedBridgeSchemaInvalid' }

    $createdAtUtc = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$payload.CreatedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$createdAtUtc)) {
        throw 'ElevatedBridgeTimestampInvalid'
    }
    $age = [DateTimeOffset]::UtcNow - $createdAtUtc.ToUniversalTime()
    if ($age.TotalMinutes -lt -5 -or $age.TotalMinutes -gt 15) { throw 'ElevatedBridgeExpired' }

    $allowedEnvironmentNames = @(
        'TOOL_APPROVED_KMS_FILE','TOOL_BUILD_ARCHITECTURE','TOOL_CAPABILITY_SCHEMA',
        'TOOL_COMPATIBILITY_CATALOG','TOOL_COMPATIBILITY_SCHEMA','TOOL_CORRELATION_ID',
        'TOOL_DASHBOARD_SCHEMA','TOOL_DATA_OWNER_SID','TOOL_DATA_ROOT','TOOL_DATA_SCHEMA_VERSION','TOOL_DATA_SCOPE',
        'TOOL_ENTERPRISE_NETWORK_ALLOWED','TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH','TOOL_ENTERPRISE_ROOT',
        'TOOL_ENTERPRISE_SCHEMA','TOOL_EXPECTED_PROCESS_ARCHITECTURE','TOOL_LAUNCHER_PATH',
        'TOOL_LAUNCHER_PID','TOOL_LAUNCH_MODE','TOOL_LEGACY_DATA_ROOT','TOOL_LOCALIZATION_SCHEMA',
        'TOOL_LOG_PATH','TOOL_MODULE_CONTRACT_SCHEMA','TOOL_MODULE_ID','TOOL_MODULE_INVOCATION_ID',
        'TOOL_OFFLINE_MODE','TOOL_OFFLINE_POLICY_SCHEMA','TOOL_OFFLINE_SETTINGS_PATH','TOOL_PLUGIN_DIR',
        'TOOL_OFFICIAL_BUILD_STATE','TOOL_OFFICIAL_BUILD_FAILURE','TOOL_OFFICIAL_BUILD_ID','TOOL_OFFICIAL_VERIFICATION_URL',
        'TOOL_POWERSHELL_PATH','TOOL_REPORT_SCHEMA','TOOL_SAFETY_POLICY_SCHEMA','TOOL_SECURE_LAUNCH',
        'TOOL_SELF_UPDATE_ALLOWED',
        'TOOL_SECURE_RUNTIME_DIR','TOOL_SECURE_RUNTIME_FAILED','TOOL_TIMELINE_KEY_PATH','TOOL_TIMELINE_PATH',
        'TOOL_TOOL_VERSION','TOOL_UI_CULTURE','TOOL_UI_CULTURE_SETTINGS_PATH','TOOL_UI_THEME',
        'TOOL_UI_THEME_SETTINGS_PATH','TOOL_UPDATE_CACHE_ROOT'
    )
    $environmentValues = @{}
    foreach ($property in @($payload.Environment.PSObject.Properties)) {
        $name = [string]$property.Name
        if ($allowedEnvironmentNames -notcontains $name) { throw 'ElevatedBridgeEnvironmentNameInvalid' }
        $environmentValues[$name] = if ($null -eq $property.Value) { $null } else { [string]$property.Value }
    }
    if ($brokerBuildState -notin @('Official','Managed','Store','Modified','Unverified')) { throw 'ElevatedBrokerBuildStateInvalid' }
    if ($brokerBuildState -in @('Official','Managed','Store') -and (
        -not $brokerProvenanceOfficial -or
        $brokerBuildId -ne $expectedOfficialBuildId -or
        $brokerVerificationUrl -ne 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest')) {
        throw 'ElevatedBrokerTrustedBuildVerificationFailed'
    }
    # Security-sensitive values come only from the compiled launcher after it
    # has crossed UAC and re-evaluated Authenticode or Store package origin.
    # The user-process JSON is never authoritative for these fields.
    $environmentValues['TOOL_SECURE_LAUNCH'] = '1'
    $environmentValues['TOOL_OFFICIAL_BUILD_STATE'] = $brokerBuildState
    $environmentValues['TOOL_OFFICIAL_BUILD_FAILURE'] = $brokerBuildFailure
    $environmentValues['TOOL_OFFICIAL_BUILD_ID'] = $brokerBuildId
    $environmentValues['TOOL_OFFICIAL_VERIFICATION_URL'] = $brokerVerificationUrl
    $environmentValues['TOOL_SELF_UPDATE_ALLOWED'] = $brokerSelfUpdateAllowed
    $environmentValues['TOOL_LAUNCHER_PATH'] = $brokerLauncherPath
    $environmentValues['TOOL_LAUNCHER_PID'] = [string]$brokerLauncherPid
    $environmentValues['TOOL_BUILD_ARCHITECTURE'] = [string]$env:TOOL_BUILD_ARCHITECTURE
    $environmentValues['TOOL_EXPECTED_PROCESS_ARCHITECTURE'] = [string]$env:TOOL_EXPECTED_PROCESS_ARCHITECTURE
    $environmentValues['TOOL_POWERSHELL_PATH'] = [string]$env:TOOL_POWERSHELL_PATH
    $environmentValues['TOOL_TOOL_VERSION'] = [string]$env:TOOL_TOOL_VERSION
    if ([string]$environmentValues['TOOL_SECURE_LAUNCH'] -ne '1') { throw 'ElevatedBridgeSecureLaunchRequired' }
    $dataScope = [string]$environmentValues['TOOL_DATA_SCOPE']
    if ($dataScope -notin @('User','Machine')) { throw 'ElevatedBridgeDataScopeInvalid' }
    $dataOwnerSidValue = ''
    if ($dataScope -eq 'User') {
        try {
            $dataOwnerSid = New-Object Security.Principal.SecurityIdentifier([string]$environmentValues['TOOL_DATA_OWNER_SID'])
            if (-not $dataOwnerSid.IsAccountSid()) { throw 'ElevatedBridgeDataOwnerSidInvalid' }
            $dataOwnerSidValue = $dataOwnerSid.Value
        } catch { throw 'ElevatedBridgeDataOwnerSidInvalid' }
    }
    $moduleId = [string]$environmentValues['TOOL_MODULE_ID']
    $invocationId = [guid]::Empty
    if (-not [guid]::TryParse([string]$environmentValues['TOOL_MODULE_INVOCATION_ID'], [ref]$invocationId) -or $invocationId -eq [guid]::Empty) {
        throw 'ElevatedBridgeInvocationIdInvalid'
    }

    $moduleScripts = @{
        'report.all' = 'kiem-tra-cau-hinh-ban-quyen.ps1'
        'report.hardware' = 'kiem-tra-cau-hinh-ban-quyen.ps1'
        'report.windows' = 'kiem-tra-cau-hinh-ban-quyen.ps1'
        'report.office' = 'kiem-tra-cau-hinh-ban-quyen.ps1'
        'report.software' = 'kiem-tra-cau-hinh-ban-quyen.ps1'
        'cleanup.scan' = 'windows-license-compliance-cleanup.ps1'
        'cleanup.deep' = 'windows-license-compliance-cleanup.ps1'
        'cleanup.repair' = 'windows-license-compliance-cleanup.ps1'
        'application.update.apply' = 'Tool-UpdateManager.ps1'
        'oem.apply' = 'windows-oem-license-assistant.ps1'
        'license.deep-scan' = 'windows-license-deep-scan.ps1'
        'forensics.scan' = 'windows-license-forensics.ps1'
        'license.manager' = 'enterprise-license-manager.ps1'
        'backup.create' = 'windows-license-backup.ps1'
        'restore.apply' = 'windows-license-restore.ps1'
    }
    if (-not $moduleScripts.ContainsKey($moduleId)) { throw 'ElevatedBridgeModuleIdInvalid' }
    $systemChangeModules = @('cleanup.deep','cleanup.repair','application.update.apply','oem.apply','license.manager','backup.create','restore.apply')
    if ($systemChangeModules -contains $moduleId -and (
        -not $brokerProvenanceOfficial -or
        [string]$environmentValues['TOOL_OFFICIAL_BUILD_STATE'] -notin @('Official','Managed','Store') -or
        [string]$environmentValues['TOOL_OFFICIAL_BUILD_ID'] -ne $expectedOfficialBuildId -or
        [string]$environmentValues['TOOL_OFFICIAL_VERIFICATION_URL'] -ne 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest'
    )) {
        throw 'ElevatedBridgeTrustedBuildRequired'
    }

    $bridgeRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
    if (-not [string]::Equals((Split-Path -Parent $bridgeRoot), $brokerDataRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $bridgeRoot) -notmatch '^session-[0-9a-f]{32}$' -or
        -not [string]::Equals($brokerSecureRuntimeRoot, (Join-Path $bridgeRoot 'runtime'), [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-BridgeProtectedDirectoryAcl -Path $brokerDataRoot -DataScope Machine) -or
        -not (Test-BridgeProtectedDirectoryAcl -Path $bridgeRoot -DataScope Machine) -or
        -not (Test-BridgeProtectedDirectoryAcl -Path $brokerSecureRuntimeRoot -DataScope Machine)) {
        throw 'ElevatedBrokerProtectedRootInvalid'
    }
    $declaredRuntimeRoot = [IO.Path]::GetFullPath([string]$environmentValues['TOOL_SECURE_RUNTIME_DIR']).TrimEnd('\')
    $originalRoot = [IO.Path]::GetFullPath((Split-Path -Parent $declaredRuntimeRoot)).TrimEnd('\')
    $declaredDataRoot = [IO.Path]::GetFullPath([string]$environmentValues['TOOL_DATA_ROOT']).TrimEnd('\')
    if (-not [string]::Equals($declaredRuntimeRoot, (Join-Path $originalRoot 'runtime'), [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals((Split-Path -Parent $originalRoot), $declaredDataRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $originalRoot) -notmatch '^session-[0-9a-f]{32}$') { throw 'ElevatedBridgeRuntimeMismatch' }
    if (-not (Test-BridgeProtectedDirectoryAcl -Path $originalRoot -DataScope $dataScope -AllowedUserSid $dataOwnerSidValue)) { throw 'ElevatedBridgeOriginalDirectoryAclInvalid' }
    if (-not (Test-BridgeProtectedDirectoryAcl -Path $declaredRuntimeRoot -DataScope $dataScope -AllowedUserSid $dataOwnerSidValue)) { throw 'ElevatedBridgeRuntimeDirectoryAclInvalid' }
    $trustedIntegrityEntries = Assert-BridgeOriginalPayloadIntegrity -TrustedRoot $bridgeRoot -OriginalRoot $originalRoot

    $targetFilePath = [IO.Path]::GetFullPath([string]$payload.TargetFilePath)
    $expectedPowerShellPath = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'))
    if (-not [string]::Equals($targetFilePath, $expectedPowerShellPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $targetFilePath -PathType Leaf)) { throw 'ElevatedBridgeTargetInvalid' }

    $targetArguments = [string]$payload.TargetArguments
    if ([string]::IsNullOrWhiteSpace($targetArguments) -or $targetArguments.Length -gt 16000 -or $targetArguments -match "[`0`r`n]") {
        throw 'ElevatedBridgeArgumentsInvalid'
    }
    $parsedTargetArguments = ConvertFrom-BridgeTargetArguments -Arguments $targetArguments
    Assert-BridgeModuleArgumentProfile -ModuleId $moduleId -ParsedArguments $parsedTargetArguments `
        -OriginalRuntimeRoot $declaredRuntimeRoot -TrustedLauncherPath $brokerLauncherPath
    if ($targetArguments -notmatch '(?i)^\s*-NoProfile\s+-ExecutionPolicy\s+RemoteSigned\s+-File\s+"' -or
        $targetArguments -match '(?i)(?:^|\s)-(?:[A-Za-z]*Command|EncodedArguments)\b') {
        throw 'ElevatedBridgeArgumentsInvalid'
    }
    $fileMatches = [regex]::Matches($targetArguments, '(?i)(?:^|\s)-File\s+"([^"]+)"')
    if ($fileMatches.Count -ne 1) { throw 'ElevatedBridgeScriptBindingInvalid' }
    $actualScriptPath = [IO.Path]::GetFullPath([string]$parsedTargetArguments.ScriptPath)
    $scriptName = [string]$moduleScripts[$moduleId]
    $expectedOriginalScriptPath = [IO.Path]::GetFullPath((Join-Path $originalRoot $scriptName))
    $protectedScriptPath = [IO.Path]::GetFullPath((Join-Path $bridgeRoot $scriptName))
    if (-not [string]::Equals($actualScriptPath, $expectedOriginalScriptPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $protectedScriptPath -PathType Leaf) -or
        -not $trustedIntegrityEntries.ContainsKey($scriptName) -or
        (Get-BridgeSha256 $protectedScriptPath) -cne [string]$trustedIntegrityEntries[$scriptName]) { throw 'ElevatedBridgeScriptBindingInvalid' }
    $scriptItem = Get-Item -LiteralPath $protectedScriptPath -Force -ErrorAction Stop
    if (($scriptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ElevatedBridgeScriptReparsePointRejected' }
    $fileMatch = $fileMatches[0]
    $targetArguments = $targetArguments.Substring(0, $fileMatch.Index) +
        ' -File "' + $protectedScriptPath + '"' +
        $targetArguments.Substring($fileMatch.Index + $fileMatch.Length)

    # Do not use Start-Process/ShellExecute for this second hop.  On a real
    # RunAs boundary Windows can ask the shell broker to create the child;
    # that broker then supplies its own environment instead of the values
    # restored in this elevated bridge.  The cleanup process consequently
    # sees TOOL_SECURE_LAUNCH as empty and rejects the signed selection file.
    #
    # UseShellExecute=false makes this process create the child directly and
    # lets us attach the reviewed TOOL_* contract as an explicit environment
    # block.  All other ordinary Windows variables remain inherited from the
    # already-elevated bridge.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $targetFilePath
    $startInfo.Arguments = $targetArguments
    $startInfo.WorkingDirectory = $bridgeRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = [bool]$payload.HiddenWindow
    if ([bool]$payload.HiddenWindow) {
        $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    }
    foreach ($name in $allowedEnvironmentNames) {
        if ($environmentValues.ContainsKey($name) -and $null -ne $environmentValues[$name]) {
            $startInfo.EnvironmentVariables[$name] = [string]$environmentValues[$name]
        } else {
            [void]$startInfo.EnvironmentVariables.Remove($name)
        }
    }

    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $startInfo
    if (-not $child.Start()) { throw 'ElevatedBridgeChildMissing' }
    try {
        $child.WaitForExit()
        $childExitCode = [int]$child.ExitCode
    } finally {
        $child.Dispose()
    }
    exit $childExitCode
} catch {
    [Console]::Error.WriteLine('Tool elevated bridge failed: ' + [string]$_.Exception.Message)
    exit $bridgeFailureExitCode
}
