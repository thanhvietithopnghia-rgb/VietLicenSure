$script:ToolReportSchemaVersion = "1.6" # v1.6 adds build identity and explainable evidence fields.
$script:ToolReportSchemaToolVersion = "5.0"
$script:ToolReportKinds = @(
    "InventoryAndLicense",
    "CleanupCompliance",
    "LicenseForensics",
    "DeepScanDecision",
    "ScanSourceRepair",
    "CertificateAudit",
    "PluginEvaluation",
    "LicenseTimeline",
    "EnterpriseInventory"
)
$script:ToolReportRequiredFieldsByKind = [ordered]@{
    InventoryAndLicense = @("ToolName", "BuildId", "CreatedAt", "Mode", "WindowsAdvisor", "OfficeAdvisor", "OfficeVersionAssessment")
    CleanupCompliance = @("ReadyForOfficialActivation", "ScanWarningCount", "HandlingGuidance")
    LicenseForensics = @("Overall", "RiskScore", "HighCount", "ReviewCount")
    DeepScanDecision = @("AccessDenied", "Overall", "HighCount", "ReviewCount", "ReportPath")
    ScanSourceRepair = @("RepairAttempted", "RecheckPassed", "StartupTypeChanged", "RollbackApplied", "ServiceStateBefore", "ServiceStateAfter")
    CertificateAudit = @("CreatedAt", "Overall", "ValidSignatureCount", "InvalidSignatureCount", "Targets")
    PluginEvaluation = @("CreatedAt", "PluginCount", "EvaluatedRuleCount", "TriggeredFindingCount")
    LicenseTimeline = @("CreatedAt", "ChainValid", "EventCount", "ChangeCount")
    EnterpriseInventory = @("CreatedAt", "ClientId", "ComputerName", "NetworkAddresses", "WindowsLicenses", "OfficeLicenses", "Privacy")
}

$toolReportSchemaLocalizationPath = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if ((-not (Get-Command Get-ToolTextCurrent -ErrorAction SilentlyContinue) -or
     -not (Get-Variable -Name ToolLocalizationSupportedCultures -Scope Script -ErrorAction SilentlyContinue)) -and
    (Test-Path -LiteralPath $toolReportSchemaLocalizationPath -PathType Leaf)) {
    . $toolReportSchemaLocalizationPath
}

function Test-ToolReportPackageIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ManifestPath,
        [string[]]$RequiredFiles=@(), [string[]]$AllowedFiles=@(), [switch]$ClosedSet
    )
    $members = New-Object 'Collections.Generic.List[string]'
    $hashes = @{}
    $failureCode = ''
    try {
        $manifest = Get-Item -LiteralPath $ManifestPath -Force -ErrorAction Stop
        $root = $manifest.Directory.FullName
        if ($manifest.PSIsContainer -or $manifest.Length -gt 65536 -or
            ($manifest.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { $failureCode = 'UnsafeManifest'; throw $failureCode }
        $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($line in [IO.File]::ReadAllLines($manifest.FullName,[Text.UTF8Encoding]::new($false,$true))) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
            if ($line -notmatch '^([0-9A-Fa-f]{64})[ \t]+\*?(.+)$') { $failureCode = 'InvalidManifestLine'; throw $failureCode }
            $expected = $matches[1].ToUpperInvariant(); $name = $matches[2]
            if ($name -ne $name.Trim() -or $name -in @('.','..') -or
                $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
                [IO.Path]::GetFileName($name) -cne $name -or $name -ieq $manifest.Name -or -not $seen.Add($name)) { $failureCode = 'UnsafeOrDuplicateMember'; throw $failureCode }
            if ($AllowedFiles.Count -gt 0 -and $name -notin $AllowedFiles) { $failureCode = 'UnexpectedMember'; throw $failureCode }
            if ($seen.Count -gt 16) { $failureCode = 'TooManyMembers'; throw $failureCode }
            $file = Get-Item -LiteralPath (Join-Path $root $name) -Force -ErrorAction Stop
            if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 128MB) { $failureCode = 'UnsafeMember'; throw $failureCode }
            $stream = [IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try {
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') } finally { $sha.Dispose() }
            } finally { $stream.Dispose() }
            if ($actual -cne $expected) { $failureCode = 'MemberHashMismatch'; throw $failureCode }
            if ($file.Extension -ieq '.json') {
                if ($file.Length -gt 24MB) { $failureCode = 'JsonFileTooLarge'; throw $failureCode }
                $value = [IO.File]::ReadAllText($file.FullName,[Text.UTF8Encoding]::new($false,$true)) | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $value) { $failureCode = 'EmptyJson'; throw $failureCode }
            } elseif ($file.Extension -ieq '.xml') {
                $settings = New-Object Xml.XmlReaderSettings
                $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit; $settings.XmlResolver = $null
                $reader = [Xml.XmlReader]::Create($file.FullName,$settings)
                try { while ($reader.Read()) {} } finally { $reader.Dispose() }
            } elseif ($file.Extension -ieq '.pdf') {
                $pdf = [IO.File]::OpenRead($file.FullName)
                try {
                    $header = New-Object byte[] 5
                    if ($pdf.Read($header,0,5) -ne 5 -or [Text.Encoding]::ASCII.GetString($header) -cne '%PDF-') { $failureCode='InvalidPdfHeader'; throw $failureCode }
                    $tail = New-Object byte[] ([int][Math]::Min(1024,$pdf.Length))
                    [void]$pdf.Seek(-$tail.Length,[IO.SeekOrigin]::End)
                    [void]$pdf.Read($tail,0,$tail.Length)
                    if ([Text.Encoding]::ASCII.GetString($tail) -notmatch '%%EOF') { $failureCode='TruncatedPdf'; throw $failureCode }
                } finally { $pdf.Dispose() }
            }
            $members.Add($name)
            $hashes[$name] = $expected
        }
        if ($members.Count -eq 0) { $failureCode = 'EmptyManifest'; throw $failureCode }
        foreach ($name in $RequiredFiles) { if (-not $seen.Contains($name)) { $failureCode = 'RequiredMemberMissing'; throw $failureCode } }
        if ($ClosedSet) {
            foreach ($file in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)) {
                if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                    ($file.Name -ine $manifest.Name -and -not $seen.Contains($file.Name))) { $failureCode = 'UnlistedMember'; throw $failureCode }
            }
        }
        return [pscustomobject]@{Valid=$true;Status='Verified';Reason='ChecksumAndStructureVerified';Files=$members.ToArray();Hashes=$hashes}
    } catch {
        return [pscustomobject]@{Valid=$false;Status='Corrupt';Reason=$(if($failureCode){$failureCode}else{'ReadOrParseFailure'});Files=$members.ToArray()}
    }
}

function Get-ToolReportRequiredFields {
    param([Parameter(Mandatory = $true)][string]$ReportKind)
    if (-not $script:ToolReportRequiredFieldsByKind.Contains($ReportKind)) { return @() }
    return @($script:ToolReportRequiredFieldsByKind[$ReportKind])
}

function Get-ToolReportSchemaMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = [string]$script:ToolReportSchemaVersion
        ToolVersion = [string]$script:ToolReportSchemaToolVersion
        ReportKinds = @($script:ToolReportKinds)
        RequiredFields = @("SchemaVersion", "ReportSchemaVersion", "ReportKind", "ToolVersion")
        RequiredFieldsByKind = $script:ToolReportRequiredFieldsByKind
    }
}

function New-ToolReportEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReportKind,
        [Parameter(Mandatory = $true)][string]$ToolVersion,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Data
    )

    if ($script:ToolReportKinds -notcontains $ReportKind) {
        throw (Get-ToolTextCurrent "foundation.reportSchema.kindUnsupportedForSchema" @($script:ToolReportSchemaVersion, $ReportKind))
    }
    if ([string]::IsNullOrWhiteSpace($ToolVersion)) {
        throw (Get-ToolTextCurrent "foundation.reportSchema.toolVersionRequired")
    }

    $result = [ordered]@{
        SchemaVersion = [string]$script:ToolReportSchemaVersion
        ReportSchemaVersion = [string]$script:ToolReportSchemaVersion
        ReportKind = [string]$ReportKind
        ToolVersion = [string]$ToolVersion
    }

    if ($null -ne $Data) {
        if ($Data -is [System.Collections.IDictionary]) {
            foreach ($key in @($Data.Keys)) {
                $name = [string]$key
                if ($result.Contains($name)) { continue }
                $result[$name] = $Data[$key]
            }
        } else {
            foreach ($property in @($Data.PSObject.Properties)) {
                $name = [string]$property.Name
                if ($result.Contains($name)) { continue }
                $result[$name] = $property.Value
            }
        }
    }

    return [pscustomobject]$result
}

function Test-ToolReportEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object]$Report,
        [string]$ExpectedReportKind = "",
        [string]$ExpectedToolVersion = ""
    )

    $errors = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Report) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.reportNull"))
        return [pscustomobject]@{ Valid=$false; Errors=$errors.ToArray() }
    }

    foreach ($field in @("SchemaVersion", "ReportSchemaVersion", "ReportKind", "ToolVersion")) {
        $property = $Report.PSObject.Properties[$field]
        if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.requiredFieldMissing" @($field)))
        }
    }

    $schemaVersionProperty = $Report.PSObject.Properties['SchemaVersion']
    $reportSchemaVersionProperty = $Report.PSObject.Properties['ReportSchemaVersion']
    $reportKindProperty = $Report.PSObject.Properties['ReportKind']
    $toolVersionProperty = $Report.PSObject.Properties['ToolVersion']
    $schemaVersion = if ($null -ne $schemaVersionProperty) { [string]$schemaVersionProperty.Value } else { '' }
    $reportSchemaVersion = if ($null -ne $reportSchemaVersionProperty) { [string]$reportSchemaVersionProperty.Value } else { '' }
    $reportKind = if ($null -ne $reportKindProperty) { [string]$reportKindProperty.Value } else { '' }
    $toolVersion = if ($null -ne $toolVersionProperty) { [string]$toolVersionProperty.Value } else { '' }

    if ($schemaVersion -ne [string]$script:ToolReportSchemaVersion) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.schemaUnsupported" @($schemaVersion)))
    }
    if ($reportSchemaVersion -ne [string]$script:ToolReportSchemaVersion) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.reportSchemaMismatch" @($reportSchemaVersion)))
    }
    if ($script:ToolReportKinds -notcontains $reportKind) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.kindUnsupported" @($reportKind)))
    } else {
        foreach ($field in @(Get-ToolReportRequiredFields -ReportKind $reportKind)) {
            if ($null -eq $Report.PSObject.Properties[$field]) {
                $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.kindFieldMissing" @($reportKind, $field)))
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedReportKind) -and $reportKind -ne $ExpectedReportKind) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.kindMismatch" @($ExpectedReportKind, $reportKind)))
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedToolVersion) -and $toolVersion -ne $ExpectedToolVersion) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.toolVersionMismatch" @($ExpectedToolVersion, $toolVersion)))
    }

    return [pscustomobject]@{
        Valid = [bool]($errors.Count -eq 0)
        Errors = $errors.ToArray()
    }
}
