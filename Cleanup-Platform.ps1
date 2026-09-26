# VietLicenSure v5.0 - dot-sourced function library
# Extracted mechanically from windows-license-compliance-cleanup.ps1; contains function definitions only.
# Keep this file beside its compatible entrypoint.

function Get-CleanupText {
    param([Parameter(Mandatory = $true)][string]$Key, [object[]]$Arguments = @())
    return Get-ToolText -Key $Key -Culture $Culture -FormatArguments $Arguments
}

function Test-CleanupKnownActivatorText {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return [bool](
        $Text -match $script:StrictActivatorPattern -or
        $Text -match $script:StrictActivationCommandPattern
    )
}

function Add-ScanWarning([string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Message) -and -not $script:ScanWarnings.Contains($Message)) {
        [void]$script:ScanWarnings.Add($Message)
    }
}

function Reset-ScanCaches {
    $script:CimCache = @{}
    $script:ScheduledTaskRecordsCache = $null
    $script:OfficeLicenseProbe = $null
    if (Get-Command Reset-ToolSoftwareInventoryCaches -ErrorAction SilentlyContinue) { Reset-ToolSoftwareInventoryCaches }
}

function Protect-CleanupReportText($Value) {
    if ($null -eq $Value) { return "" }
    # Một số tiện ích native (đặc biệt sfc.exe) có thể trả chuỗi UTF-16 qua
    # console khiến Windows PowerShell chèn NUL giữa từng ký tự. Loại NUL ở
    # ranh giới báo cáo để JSON, hộp thoại và Notepad không hiển thị rác.
    $text = ([string]$Value) -replace "`0", ""
    if (-not $RedactSensitive) { return $text }

    $profilePath = [Environment]::GetFolderPath("UserProfile")
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
        $text = [regex]::Replace($text, [regex]::Escape($profilePath), "%USERPROFILE%", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    foreach ($secret in @($env:COMPUTERNAME, $env:USERNAME)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$secret)) {
            $pattern = '(?<![A-Za-z0-9_.-])' + [regex]::Escape([string]$secret) + '(?![A-Za-z0-9_.-])'
            $text = [regex]::Replace($text, $pattern, (Get-CleanupText "report.redaction.value"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    foreach ($hostName in @($script:SensitiveKmsHosts | Sort-Object Length -Descending -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$hostName)) {
            $text = [regex]::Replace($text, [regex]::Escape([string]$hostName), (Get-CleanupText "cleanupReport.redaction.kms"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $ipv4Part = '(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
    $text = [regex]::Replace($text, "(?<![0-9.])$ipv4Part(?:\.$ipv4Part){3}(?![0-9.])", (Get-CleanupText "report.redaction.ip"))
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', (Get-CleanupText "report.redaction.mac"))
    return $text
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-ToolDataOwnerSid {
    if ([string]$env:TOOL_DATA_SCOPE -ne 'User') { return $null }
    $configuredSid = [string]$env:TOOL_DATA_OWNER_SID
    if (-not [string]::IsNullOrWhiteSpace($configuredSid)) {
        try {
            $sid = New-Object Security.Principal.SecurityIdentifier($configuredSid)
            if ($sid.IsAccountSid()) { return $sid }
        } catch {}
    }
    return [Security.Principal.WindowsIdentity]::GetCurrent().User
}

function Set-ProtectedBackupAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowCurrentUserForUserScope
    )
    $administrators = New-Object Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $system = New-Object Security.Principal.SecurityIdentifier("S-1-5-18")
    $dataOwnerSid = if ($AllowCurrentUserForUserScope) { Get-ToolDataOwnerSid } else { $null }
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($(if ($dataOwnerSid) { $dataOwnerSid } else { $administrators }))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($administrators, "FullControl", $inheritance, "None", "Allow")))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($system, "FullControl", $inheritance, "None", "Allow")))
    if ($dataOwnerSid) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($dataOwnerSid, "FullControl", $inheritance, "None", "Allow")))
    }
    [IO.Directory]::SetAccessControl([IO.Path]::GetFullPath($Path), $acl)
}

function Test-ProtectedDirectoryAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowCurrentUserForUserScope
    )
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $ownerSid = (New-Object Security.Principal.NTAccount($acl.Owner)).Translate([Security.Principal.SecurityIdentifier]).Value
        $allowedOwners = @("S-1-5-32-544", "S-1-5-18")
        $allowedWriters = @("S-1-5-32-544", "S-1-5-18")
        if ($AllowCurrentUserForUserScope -and [string]$env:TOOL_DATA_SCOPE -eq 'User') {
            $dataOwnerSid = Get-ToolDataOwnerSid
            if ($dataOwnerSid) {
                $allowedOwners += $dataOwnerSid.Value
                $allowedWriters += $dataOwnerSid.Value
            }
        }
        if ($ownerSid -notin $allowedOwners -or -not $acl.AreAccessRulesProtected) { return $false }
        $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Modify -bor [Security.AccessControl.FileSystemRights]::FullControl -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and $allowedWriters -notcontains $rule.IdentityReference.Value -and (($rule.FileSystemRights -band $writeMask) -ne 0)) { return $false }
        }
        return $true
    } catch { return $false }
}

function Get-SecureBackupRoot {
    $versionRoot = [string]$env:TOOL_DATA_ROOT
    if ([string]::IsNullOrWhiteSpace($versionRoot)) {
        $commonData = [Environment]::GetFolderPath("CommonApplicationData")
        if ([string]::IsNullOrWhiteSpace($commonData)) { throw (Get-CleanupText "backupReport.programDataUnknown") }
        $versionRoot = Join-Path $commonData "ThanhViet-VietLicenSure\v4.6"
    }
    $versionRoot = [IO.Path]::GetFullPath($versionRoot)
    $productRoot = Split-Path -Parent $versionRoot
    $backupRoot = Join-Path $versionRoot "backups"
    $userScope = [bool]([string]$env:TOOL_DATA_SCOPE -eq 'User')
    foreach ($path in @($productRoot, $versionRoot)) {
        if (Test-Path -LiteralPath $path) {
            $existing = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText "backupReport.invalidRoot" @($path)) }
        } else { Ensure-Dir $path }
        Set-ProtectedBackupAcl -Path $path -AllowCurrentUserForUserScope:$userScope
        if (-not (Test-ProtectedDirectoryAcl -Path $path -AllowCurrentUserForUserScope:$userScope)) { throw (Get-CleanupText "backupReport.invalidAcl" @($path)) }
    }
    if (Test-Path -LiteralPath $backupRoot) {
        $existing = Get-Item -LiteralPath $backupRoot -Force -ErrorAction Stop
        if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText "backupReport.invalidRoot" @($backupRoot)) }
    } else { Ensure-Dir $backupRoot }
    Set-ProtectedBackupAcl -Path $backupRoot
    if (-not (Test-ProtectedDirectoryAcl -Path $backupRoot)) { throw (Get-CleanupText "backupReport.invalidAcl" @($backupRoot)) }
    return $backupRoot
}

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant() }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-PathHash([string]$Path) {
    $rootItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText "restoreReport.reparseRejected" @($Path)) }
    if (-not $rootItem.PSIsContainer) { return Get-Sha256 $Path }
    $root = ([IO.Path]::GetFullPath($Path)).TrimEnd('\')
    $lines = New-Object System.Collections.Generic.List[string]
    $children = @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction Stop | Sort-Object FullName)
    if (@($children | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) { throw (Get-CleanupText "cleanupReport.reparseContained" @($Path)) }
    foreach ($file in @($children | Where-Object { -not $_.PSIsContainer })) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\')
        $lines.Add(($relative + "|" + (Get-Sha256 $file.FullName)))
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Get-MachineBinding {
    $machineGuid = ""
    try { $machineGuid = [string](Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -ErrorAction Stop).MachineGuid } catch {}
    $bytes = [Text.Encoding]::UTF8.GetBytes(($env:COMPUTERNAME + "|" + $machineGuid))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Safe-Cim {
    param([string]$ClassName, [string]$Namespace = "root/cimv2", [string]$CriticalLabel = "", [switch]$NoCache)
    $cacheKey = ($Namespace + "|" + $ClassName).ToLowerInvariant()
    if (-not $NoCache -and $script:CimCache.ContainsKey($cacheKey)) {
        return @($script:CimCache[$cacheKey])
    }
    if ($ClassName -eq 'SoftwareLicensingProduct' -and (Get-Command Invoke-ToolLicenseDataRead -ErrorAction SilentlyContinue)) {
        $readResult = Invoke-ToolLicenseDataRead -Namespace $Namespace -ClassName $ClassName -RepairServices:$RepairScanSources
        $script:WindowsLicenseDataRead = $readResult
        if ($readResult.Succeeded) {
            $result = @($readResult.Items)
            if (-not $NoCache) { $script:CimCache[$cacheKey] = @($result) }
            return $result
        }
        if (-not [string]::IsNullOrWhiteSpace($CriticalLabel)) {
            Add-ScanWarning ("{0}: Status={1}; {2}" -f $CriticalLabel,[string]$readResult.Status,[string]$readResult.ErrorDetail)
        }
        return @()
    }
    $firstError = ""
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $result = @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -OperationTimeoutSec 20 -ErrorAction Stop)
            if (-not $NoCache) { $script:CimCache[$cacheKey] = @($result) }
            return $result
        }
    } catch { $firstError = $_.Exception.Message }
    try {
        $result = @(Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop)
        if (-not $NoCache) { $script:CimCache[$cacheKey] = @($result) }
        return $result
    } catch {
        if (-not [string]::IsNullOrWhiteSpace($CriticalLabel)) {
            $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
            Add-ScanWarning "${CriticalLabel}: $detail"
        }
        return @()
    }
}

function Get-CompatibleScheduledTaskRecords {
    param([switch]$NoCache)
    if (-not $NoCache -and $null -ne $script:ScheduledTaskRecordsCache) {
        return @($script:ScheduledTaskRecordsCache)
    }
    $firstError = ""
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            $records = @(Get-ScheduledTask -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    TaskName = [string]$_.TaskName
                    TaskPath = [string]$_.TaskPath
                    FullName = ([string]$_.TaskPath + [string]$_.TaskName)
                    ActionsText = [string]($_.Actions | Out-String)
                    WasEnabled = [bool]($_.State -ne "Disabled")
                    Source = "ScheduledTasks"
                }
            })
            if (-not $NoCache) { $script:ScheduledTaskRecordsCache = @($records) }
            return $records
        } catch { $firstError = $_.Exception.Message }
    }

    try {
        $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
        if (-not (Test-Path -LiteralPath $schtasks -PathType Leaf)) { throw (Get-CleanupText "cleanupReport.scan.schtasksMissing") }
        $raw = @(& $schtasks /Query /FO CSV /V 2>&1)
        if ($LASTEXITCODE -ne 0) { throw (($raw | ForEach-Object { [string]$_ }) -join " | ") }
        $csvLines = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\s*"' })
        if ($csvLines.Count -lt 2) { throw (Get-CleanupText "cleanupReport.scan.schtasksCsvInvalid") }
        $rows = @($csvLines | ConvertFrom-Csv)
        $records = New-Object System.Collections.Generic.List[object]
        foreach ($row in $rows) {
            $values = @($row.PSObject.Properties | ForEach-Object { [string]$_.Value })
            $fullName = [string]($values | Where-Object { $_ -match '^\\[^\\]+' } | Select-Object -First 1)
            if ([string]::IsNullOrWhiteSpace($fullName)) { continue }
            $lastSlash = $fullName.LastIndexOf('\')
            if ($lastSlash -lt 0 -or $lastSlash -ge ($fullName.Length - 1)) { continue }
            $taskPath = $fullName.Substring(0, $lastSlash + 1)
            $taskName = $fullName.Substring($lastSlash + 1)
            [void]$records.Add([pscustomobject]@{
                TaskName = $taskName
                TaskPath = $taskPath
                FullName = $fullName
                ActionsText = ($values -join " | ")
                WasEnabled = $true
                Source = "Schtasks"
            })
        }
        if ($records.Count -eq 0) { throw (Get-CleanupText "cleanupReport.scan.schtasksNameInvalid") }
        $result = @($records.ToArray())
        if (-not $NoCache) { $script:ScheduledTaskRecordsCache = @($result) }
        return $result
    } catch {
        $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
        Add-ScanWarning (Get-CleanupText "cleanupReport.scan.tasksFailed" @($detail))
        return @()
    }
}

function Write-CompatibleTaskXml([string]$Path, [string]$XmlText) {
    $document = New-Object Xml.XmlDocument
    $document.PreserveWhitespace = $true
    $document.LoadXml($XmlText)
    $settings = New-Object Xml.XmlWriterSettings
    $settings.Encoding = New-Object Text.UTF8Encoding($false)
    $settings.Indent = $true
    $writer = [Xml.XmlWriter]::Create($Path, $settings)
    try { $document.Save($writer) } finally { $writer.Dispose() }
}

function Export-CompatibleScheduledTask($Record, [string]$Path) {
    if ([string]$Record.Source -eq "ScheduledTasks" -and (Get-Command Export-ScheduledTask -ErrorAction SilentlyContinue)) {
        $xmlText = [string](Export-ScheduledTask -TaskName ([string]$Record.TaskName) -TaskPath ([string]$Record.TaskPath) -ErrorAction Stop)
        Write-CompatibleTaskXml -Path $Path -XmlText $xmlText
        return
    }
    $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
    $raw = @(& $schtasks /Query /TN ([string]$Record.FullName) /XML 2>&1)
    if ($LASTEXITCODE -ne 0) { throw (($raw | ForEach-Object { [string]$_ }) -join " | ") }
    Write-CompatibleTaskXml -Path $Path -XmlText (($raw | ForEach-Object { [string]$_ }) -join "`r`n")
}

function Remove-CompatibleScheduledTask($Record) {
    if ([string]$Record.Source -eq "ScheduledTasks" -and (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
        Unregister-ScheduledTask -TaskName ([string]$Record.TaskName) -TaskPath ([string]$Record.TaskPath) -Confirm:$false -ErrorAction Stop
        return
    }
    $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
    $output = @(& $schtasks /Delete /TN ([string]$Record.FullName) /F 2>&1)
    if ($LASTEXITCODE -ne 0) { throw (($output | ForEach-Object { [string]$_ }) -join " | ") }
}

function Import-ApprovedKmsServers {
    if ([string]::IsNullOrWhiteSpace($ApprovedKmsServerFile)) {
        return
    }
    if (-not (Test-Path -LiteralPath $ApprovedKmsServerFile)) {
        return
    }
    try {
        $fileServers = Get-Content -LiteralPath $ApprovedKmsServerFile |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith("#") }
        if ($fileServers) {
            $combinedServers = @($script:ApprovedKmsServers) + @($fileServers)
            $script:ApprovedKmsServers = @($combinedServers | Select-Object -Unique)
        }
    } catch {
        Write-Warning (Get-CleanupText "cleanupReport.kms.fileReadWarning" @($_.Exception.Message))
    }
}

function Get-ApprovedKmsConfiguration {
    $valid = New-Object System.Collections.Generic.List[string]
    $invalid = New-Object System.Collections.Generic.List[string]
    $exists = Test-Path -LiteralPath $ApprovedKmsServerFile -PathType Leaf
    if ($exists) {
        try {
            foreach ($line in Get-Content -LiteralPath $ApprovedKmsServerFile -ErrorAction Stop) {
                $value = ([string]$line).Trim()
                if (-not $value -or $value.StartsWith('#')) { continue }
                $candidate = $value -replace '^\[([^\]]+)\](?::\d+)?$', '$1'
                $candidate = $candidate -replace '^([^:]+):\d+$', '$1'
                if ($candidate -match '^[a-zA-Z0-9][a-zA-Z0-9._-]*(?:\.[a-zA-Z0-9][a-zA-Z0-9._-]*)*$' -or
                    $candidate -match '^(?:\d{1,3}\.){3}\d{1,3}$' -or $candidate -match '^[0-9a-fA-F:]+$') {
                    [void]$valid.Add($value)
                } else { [void]$invalid.Add($value) }
            }
        } catch { [void]$invalid.Add((Get-CleanupText "cleanupReport.kms.fileReadFailed" @($_.Exception.Message))) }
    }
    $warning = if (-not $exists -or $valid.Count -eq 0) {
        Get-CleanupText "cleanupReport.kms.emptyWarning"
    } elseif ($invalid.Count -gt 0) {
        Get-CleanupText "cleanupReport.kms.invalidWarning" @($invalid.Count)
    } else { "" }
    return [pscustomobject]@{
        Exists = [bool]$exists
        Valid = @($valid | Select-Object -Unique)
        Invalid = @($invalid)
        Warning = $warning
        Path = $ApprovedKmsServerFile
    }
}

function Is-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SlmgrCommand {
    param([Parameter(Mandatory = $true)][string[]]$SlmgrArguments)
    $slmgr = Get-ToolNativeSystemPath "slmgr.vbs"
    try {
        $rawOutput = @(& $nativeCscriptPath //nologo $slmgr @SlmgrArguments 2>&1)
        $exitCode = [int]$LASTEXITCODE
        $output = ($rawOutput | ForEach-Object { [string]$_ }) -join "`n"
        $lines = @($output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $isHelpOutput = [bool]($output -match "(?im)^Usage:\s+slmgr\.vbs|^Global Options:|^Advanced Options:")
        $errorLine = $lines | Where-Object {
            $_ -match "(?i)invalid combination of command parameters|(?:^|\s)error(?:\s|:)|0x[0-9a-f]{8}|tham số.+không hợp lệ|(?:^|\s)lỗi(?:\s|:)"
        } | Select-Object -First 1
        $success = [bool]($exitCode -eq 0 -and -not $isHelpOutput -and -not $errorLine)
        if ($success) {
            $summary = ($lines | Select-Object -First 2) -join " | "
            if ([string]::IsNullOrWhiteSpace($summary)) { $summary = Get-CleanupText "cleanupReport.command.noOutput" }
        } else {
            if ($errorLine) { $summary = Get-CleanupText "cleanupReport.command.failed" @($errorLine) }
            elseif ($isHelpOutput) { $summary = Get-CleanupText "cleanupReport.command.slmgrArgumentsInvalid" }
            else { $summary = Get-CleanupText "cleanupReport.command.slmgrExitCode" @($exitCode) }
        }
        if ($summary.Length -gt 320) { $summary = $summary.Substring(0, 317) + "..." }
        return [pscustomobject]@{
            Success = $success
            ExitCode = $exitCode
            Summary = $summary
            Output = $output
        }
    } catch {
        return [pscustomobject]@{
            Success = $false
            ExitCode = -1
            Summary = Get-CleanupText "cleanupReport.command.failed" @($_.Exception.Message)
            Output = "ERROR: $($_.Exception.Message)"
        }
    }
}

function Run-Cscript {
    param([Parameter(Mandatory = $true)][string[]]$SlmgrArguments)
    return [string](Invoke-SlmgrCommand -SlmgrArguments $SlmgrArguments).Output
}

function Run-SlmgrActionText {
    param([Parameter(Mandatory = $true)][string[]]$SlmgrArguments)
    return [string](Invoke-SlmgrCommand -SlmgrArguments $SlmgrArguments).Summary
}

function ConvertFrom-OfficeLicenseStatus {
    param(
        [Parameter(Mandatory = $true)][string]$StatusText,
        [Parameter(Mandatory = $true)][string]$Path
    )

    return @(ConvertFrom-OfficeOfficialLicenseStatus -StatusText $StatusText -Path $Path | Where-Object {
        [string]$_.Channel -eq 'KMS' -and ($_.Last5 -or $_.Server)
    })
}

function ConvertFrom-OfficeOfficialLicenseStatus {
    param(
        [Parameter(Mandatory = $true)][string]$StatusText,
        [Parameter(Mandatory = $true)][string]$Path
    )

    # OSPP is the vendor probe; application launch or a key file is not proof.
    $entries = New-Object System.Collections.Generic.List[object]
    $normalized = ([string]$StatusText) -replace "`0", "" -replace "`r", ""
    $blocks = [regex]::Split($normalized, '(?m)^\s*-{20,}\s*$')
    foreach ($block in $blocks) {
        if ([string]::IsNullOrWhiteSpace($block)) { continue }
        $skuMatch = [regex]::Match($block, '(?im)^\s*SKU ID\s*:\s*(?<Value>[^\r\n]+)')
        $nameMatch = [regex]::Match($block, '(?im)^\s*LICENSE NAME\s*:\s*(?<Value>[^\r\n]+)')
        $descriptionMatch = [regex]::Match($block, '(?im)^\s*LICENSE DESCRIPTION\s*:\s*(?<Value>[^\r\n]+)')
        $statusMatch = [regex]::Match($block, '(?im)^\s*LICENSE STATUS\s*:\s*(?<Value>[^\r\n]+)')
        if (-not $nameMatch.Success -and -not $descriptionMatch.Success -and -not $statusMatch.Success) { continue }

        $keyMatch = [regex]::Match($block, '(?im)^\s*(?:Last 5 characters of installed product key|5 .{0,24} cu.i[^:]*)\s*:[ \t]*(?<Value>[A-Z0-9]{5})\s*$')
        $serverMatch = [regex]::Match($block, '(?im)^\s*(?:KMS machine name(?: from DNS)?|KMS machine registry override defined|Key Management Service machine name)\s*:[ \t]*(?<Value>[^\r\n]+)')
        $description = if ($descriptionMatch.Success) { $descriptionMatch.Groups['Value'].Value.Trim() } else { '' }
        $rawStatus = if ($statusMatch.Success) { $statusMatch.Groups['Value'].Value.Trim(' ', '-') } else { '' }
        $normalizedStatus = ($rawStatus -replace '[^A-Za-z]', '').ToUpperInvariant()
        $statusCode = if ($normalizedStatus -eq 'LICENSED') { 'Licensed' }
            elseif ($normalizedStatus -eq 'UNLICENSED') { 'Unlicensed' }
            elseif ($normalizedStatus -match 'GRACE') { 'Grace' }
            elseif ($normalizedStatus -match 'NOTIFICATION|NONGENUINE') { 'Notification' }
            else { 'Unknown' }
        $channel = if ($description -match '(?i)VOLUME_KMSCLIENT|KMSCLIENT|_KMS_Client') { 'KMS' }
            elseif ($description -match '(?i)VOLUME_MAK|\bMAK\b') { 'MAK' }
            elseif ($description -match '(?i)RETAIL') { 'Retail' }
            elseif ($description -match '(?i)SUBSCRIPTION|TIMEBASED') { 'Subscription' }
            else { 'Unknown' }
        $server = if ($serverMatch.Success) { $serverMatch.Groups['Value'].Value.Trim() } else { '' }
        if ($server -match '(?i)not available|không (?:có|khả dụng)') { $server = '' }

        $entries.Add([pscustomobject][ordered]@{
            Path = $Path
            SkuId = if ($skuMatch.Success) { $skuMatch.Groups['Value'].Value.Trim() } else { '' }
            LicenseName = if ($nameMatch.Success) { $nameMatch.Groups['Value'].Value.Trim() } else { 'Microsoft Office' }
            Description = $description
            LicenseStatus = $rawStatus
            LicenseStatusCode = $statusCode
            Channel = $channel
            Last5 = if ($keyMatch.Success) { $keyMatch.Groups['Value'].Value.Trim().ToUpperInvariant() } else { '' }
            Server = $server
        })
    }
    return @($entries.ToArray())
}

function Get-OfficeOsppSkuBlockAssessment {
    param(
        [Parameter(Mandatory = $true)][string]$StatusText,
        [Parameter(Mandatory = $true)][string]$Path
    )

    # ConvertFrom-OfficeOfficialLicenseStatus is intentionally tolerant so that
    # reports can preserve what OSPP returned.  Remediation and the official
    # outcome need a stricter contract: every SKU-shaped /dstatusall block must
    # have a stable identity and the fields needed to interpret it.
    $normalized = ([string]$StatusText) -replace "`0", "" -replace "`r", ""
    $blocks = @([regex]::Split($normalized, '(?m)^\s*-{20,}\s*$'))
    $blockResults = New-Object System.Collections.Generic.List[object]
    foreach ($block in $blocks) {
        if ([string]::IsNullOrWhiteSpace($block)) { continue }
        if ($block -notmatch '(?im)^\s*(?:SKU ID|LICENSE NAME|LICENSE DESCRIPTION|LICENSE STATUS)\s*:') { continue }

        $skuMatch = [regex]::Match($block, '(?im)^\s*SKU ID\s*:[ \t]*(?<Value>[^\r\n]+)')
        $nameMatch = [regex]::Match($block, '(?im)^\s*LICENSE NAME\s*:[ \t]*(?<Value>[^\r\n]+)')
        $descriptionMatch = [regex]::Match($block, '(?im)^\s*LICENSE DESCRIPTION\s*:[ \t]*(?<Value>[^\r\n]+)')
        $statusMatch = [regex]::Match($block, '(?im)^\s*LICENSE STATUS\s*:[ \t]*(?<Value>[^\r\n]+)')
        $skuId = if ($skuMatch.Success) { $skuMatch.Groups['Value'].Value.Trim() } else { '' }
        $licenseName = if ($nameMatch.Success) { $nameMatch.Groups['Value'].Value.Trim() } else { '' }
        $description = if ($descriptionMatch.Success) { $descriptionMatch.Groups['Value'].Value.Trim() } else { '' }
        $licenseStatus = if ($statusMatch.Success) { $statusMatch.Groups['Value'].Value.Trim() } else { '' }
        $complete = [bool](
            -not [string]::IsNullOrWhiteSpace($skuId) -and
            -not [string]::IsNullOrWhiteSpace($licenseName) -and
            -not [string]::IsNullOrWhiteSpace($description) -and
            -not [string]::IsNullOrWhiteSpace($licenseStatus)
        )
        $blockResults.Add([pscustomobject][ordered]@{
            SkuId=$skuId; LicenseName=$licenseName; Description=$description
            LicenseStatus=$licenseStatus; Complete=$complete
        })
    }

    $parsed = @(ConvertFrom-OfficeOfficialLicenseStatus -StatusText $StatusText -Path $Path)
    $completeBlocks = @($blockResults | Where-Object { [bool]$_.Complete })
    $parsedWithIdentity = @($parsed | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.SkuId) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.LicenseName) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.Description) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.LicenseStatus)
    })
    $allBlocksComplete = [bool](
        $blockResults.Count -gt 0 -and
        $completeBlocks.Count -eq $blockResults.Count -and
        $parsed.Count -eq $blockResults.Count -and
        $parsedWithIdentity.Count -eq $blockResults.Count
    )
    return [pscustomobject][ordered]@{
        Entries=@($parsed); SkuBlockCount=[int]$blockResults.Count
        FullyParsedSkuBlockCount=[int]$completeBlocks.Count
        IncompleteSkuBlockCount=[int]($blockResults.Count - $completeBlocks.Count)
        Complete=$allBlocksComplete
    }
}

function Get-OfficeVNextDiagPaths {
    param([string[]]$OsppPaths = @())

    $result = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($osppPath in @($OsppPaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        $directory = Split-Path -Parent ([string]$osppPath)
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            [void]$candidates.Add((Join-Path $directory 'vNextDiag.ps1'))
        }
    }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    }) {
        [void]$candidates.Add((Join-Path ([string]$root) 'Microsoft Office\root\Office16\vNextDiag.ps1'))
    }
    foreach ($candidate in @($candidates)) {
        try {
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
            $fullPath = [IO.Path]::GetFullPath([string]$candidate)
            if ($seen.Add($fullPath)) { [void]$result.Add($fullPath) }
        } catch {}
    }
    return @($result.ToArray() | Sort-Object)
}

function Test-OfficeVNextDiagTrustedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        $expectedPaths = New-Object System.Collections.Generic.List[string]
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        }) {
            [void]$expectedPaths.Add([IO.Path]::GetFullPath((Join-Path ([string]$root) 'Microsoft Office\root\Office16\vNextDiag.ps1')))
        }
        if (@($expectedPaths | Where-Object {
            [string]::Equals($_, $fullPath, [StringComparison]::OrdinalIgnoreCase)
        }).Count -eq 0) { return $false }
        $signature = Get-AuthenticodeSignature -LiteralPath $fullPath -ErrorAction Stop
        $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        $issuer = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Issuer } else { '' }
        return [bool](
            [string]$signature.Status -eq 'Valid' -and
            $subject -match '(?i)(?:^|,\s*)CN=Microsoft Corporation(?:,|$)' -and
            $issuer -match '(?i)Microsoft'
        )
    } catch {
        return $false
    }
}

function Get-OfficeVNextEntitlementProbe {
    param([string[]]$OsppPaths = @())

    # vNextDiag's explicit `list` action is Microsoft-supplied and read-only.
    # Keep its raw output in memory only: it can include account identifiers,
    # while the report needs only aggregate technical state.
    $paths = @(Get-OfficeVNextDiagPaths -OsppPaths $OsppPaths)
    if ($paths.Count -eq 0) {
        return [pscustomobject][ordered]@{
            Coverage='Unavailable'; VNextDiagPaths=@(); PathResults=@(); RecordCount=0
            LicensedCount=0; GraceCount=0; RestrictedFunctionalityCount=0
            NoActiveEntitlement=$false
        }
    }

    $pathResults = New-Object System.Collections.Generic.List[object]
    $trustedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($path in $paths) {
        if (Test-OfficeVNextDiagTrustedPath -Path $path) {
            [void]$trustedPaths.Add($path)
        } else {
            $pathResults.Add([pscustomobject][ordered]@{
                Path=[string]$path; Trusted=$false; TimedOut=$false; ExitCode=-1
                UserSectionComplete=$false; DeviceSectionComplete=$false; RecordCount=0; Complete=$false
            })
        }
    }
    if ($trustedPaths.Count -eq 0) {
        return [pscustomobject][ordered]@{
            Coverage='Unavailable'; VNextDiagPaths=@($paths); PathResults=@($pathResults.ToArray()); RecordCount=0
            LicensedCount=0; GraceCount=0; RestrictedFunctionalityCount=0
            NoActiveEntitlement=$false
        }
    }

    $nativePowerShell = try { Get-ToolNativePowerShellPath } catch { '' }
    if ([string]::IsNullOrWhiteSpace($nativePowerShell)) {
        return [pscustomobject][ordered]@{
            Coverage='Failed'; VNextDiagPaths=@($paths); PathResults=@($pathResults.ToArray()); RecordCount=0
            LicensedCount=0; GraceCount=0; RestrictedFunctionalityCount=0
            NoActiveEntitlement=$false
        }
    }

    [int]$recordCount = 0
    [int]$licensedCount = 0
    [int]$graceCount = 0
    [int]$restrictedFunctionalityCount = 0
    foreach ($path in $trustedPaths) {
        $result = Invoke-CleanupNativeCommandWithTimeout -FilePath $nativePowerShell -Arguments @(
            '-NoLogo','-NoProfile','-NonInteractive','-File',$path,'-action','list'
        ) -TimeoutSeconds 45
        $output = [string]$result.Output
        $userSection = [regex]::Match($output, '(?is)={3,}\s*vNext licenses found\s*={3,}(?<Body>.*?)(?=={3,}\s*Device licenses found\s*={3,}|$)')
        $deviceSection = [regex]::Match($output, '(?is)={3,}\s*Device licenses found\s*={3,}(?<Body>.*)$')
        # Materialize MatchCollection through a pipeline.  Wrapping a
        # MatchCollection directly in @() keeps the collection itself as an
        # item on some Windows PowerShell builds; with no licenses that item
        # has no Groups['Value'] and causes a non-terminating null-array
        # error.  Keep only normalized state strings from this point onward.
        [string[]]$userStates = @()
        [string[]]$deviceStates = @()
        if ($userSection.Success) {
            $userStates = @(
                [regex]::Matches($userSection.Groups['Body'].Value, '(?im)^\s*"LicenseState"\s*:\s*"(?<Value>[^"]+)"') |
                    ForEach-Object { $_.Groups['Value'].Value.Trim() } | Where-Object { $_ }
            )
        }
        if ($deviceSection.Success) {
            $deviceStates = @(
                [regex]::Matches($deviceSection.Groups['Body'].Value, '(?im)^\s*"LicenseState"\s*:\s*"(?<Value>[^"]+)"') |
                    ForEach-Object { $_.Groups['Value'].Value.Trim() } | Where-Object { $_ }
            )
        }
        $userNoLicenses = [bool]($userSection.Success -and $userSection.Groups['Body'].Value -match '(?im)^\s*No licenses found\.\s*$')
        $deviceNoLicenses = [bool]($deviceSection.Success -and $deviceSection.Groups['Body'].Value -match '(?im)^\s*No licenses found\.\s*$')
        $userComplete = [bool]($userSection.Success -and ($userStates.Count -gt 0 -or $userNoLicenses))
        $deviceComplete = [bool]($deviceSection.Success -and ($deviceStates.Count -gt 0 -or $deviceNoLicenses))
        $states = @($userStates) + @($deviceStates)
        $recordCount += [int]$states.Count
        $licensedCount += [int]@($states | Where-Object { $_ -match '(?i)^Licensed$' }).Count
        $graceCount += [int]@($states | Where-Object { $_ -match '(?i)^Grace$' }).Count
        $restrictedFunctionalityCount += [int]@($states | Where-Object { $_ -match '(?i)^(?:RFM|RestrictedFunctionality)$' }).Count
        $complete = [bool]($result.Completed -and -not $result.TimedOut -and [int]$result.ExitCode -eq 0 -and $userComplete -and $deviceComplete)
        $pathResults.Add([pscustomobject][ordered]@{
            Path=[string]$path; Trusted=$true; TimedOut=[bool]$result.TimedOut; ExitCode=[int]$result.ExitCode
            UserSectionComplete=$userComplete; DeviceSectionComplete=$deviceComplete
            RecordCount=[int]$states.Count; Complete=$complete
        })
    }

    $coverage = if ($pathResults.Count -ne $paths.Count -or $pathResults.Count -eq 0) { 'Failed' }
        elseif (@($pathResults | Where-Object { -not [bool]$_.Complete }).Count -eq 0) { 'Complete' }
        elseif (@($pathResults | Where-Object { [bool]$_.Complete }).Count -gt 0) { 'Partial' }
        else { 'Failed' }
    return [pscustomobject][ordered]@{
        Coverage=$coverage; VNextDiagPaths=@($paths); PathResults=@($pathResults.ToArray())
        RecordCount=[int]$recordCount; LicensedCount=[int]$licensedCount; GraceCount=[int]$graceCount
        RestrictedFunctionalityCount=[int]$restrictedFunctionalityCount
        NoActiveEntitlement=[bool]($coverage -eq 'Complete' -and $recordCount -eq 0)
    }
}

function Test-OfficeSubscriptionDeployment {
    param($LicenseEntries = @())

    foreach ($entry in @($LicenseEntries)) {
        $entryText = (([string]$entry.LicenseName) + ' ' + ([string]$entry.Description)).Trim()
        if ([string]$entry.Channel -eq 'Subscription' -or $entryText -match '(?i)\b(?:O365|M365|Office\s*365|Microsoft\s*365|ProPlus|TIMEBASED_SUB)') {
            return $true
        }
    }
    foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
    )) {
        try {
            $configuration = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            foreach ($propertyName in @('ProductReleaseIds','ProductReleaseIDs','ProductReleaseId','ProductReleaseID')) {
                $value = if ($configuration.PSObject.Properties[$propertyName]) { [string]$configuration.$propertyName } else { '' }
                if ($value -match '(?i)\b(?:O365|M365|Office\s*365|Microsoft\s*365|ProPlus)') { return $true }
            }
        } catch {}
    }
    return $false
}

function Get-OfficeLicenseProbe {
    # Office may contain several SKUs under one OSPP.VBS.  A fallback
    # /dstatus result is useful for display, but is deliberately not enough to
    # authorize a key-removal action: it can omit other licensed SKUs.
    $osppPaths = @(Get-ToolOptimizedOfficeOsppPaths)
    $installed = Test-OfficeProductInstalled -LicenseEntries @()
    $entries = New-Object System.Collections.Generic.List[object]
    $pathResults = New-Object System.Collections.Generic.List[object]
    $rawResults = @()
    if ($osppPaths.Count -gt 0) {
        $rawResults = @(Invoke-ToolParallelOfficeStatus -CscriptPath $nativeCscriptPath -OsppPaths $osppPaths)
    }

    foreach ($result in $rawResults) {
        $path = [string]$result.Path
        $blockAssessment = Get-OfficeOsppSkuBlockAssessment -StatusText ([string]$result.Output) -Path $path
        $parsed = @($blockAssessment.Entries)
        foreach ($entry in $parsed) { $entries.Add($entry) }
        $complete = [bool](
            -not [bool]$result.UsedFallback -and
            -not [bool]$result.TimedOut -and
            [bool]$result.Readable -and
            [int]$result.PrimaryExitCode -eq 0 -and
            $parsed.Count -gt 0 -and
            [bool]$blockAssessment.Complete
        )
        $pathResults.Add([pscustomobject][ordered]@{
            Path=$path; UsedFallback=[bool]$result.UsedFallback; TimedOut=[bool]$result.TimedOut
            PrimaryExitCode=[int]$result.PrimaryExitCode; ExitCode=[int]$result.ExitCode
            Readable=[bool]$result.Readable; ParsedSkuCount=[int]$parsed.Count
            SkuBlockCount=[int]$blockAssessment.SkuBlockCount
            FullyParsedSkuBlockCount=[int]$blockAssessment.FullyParsedSkuBlockCount
            IncompleteSkuBlockCount=[int]$blockAssessment.IncompleteSkuBlockCount
            Complete=$complete
        })
    }

    $coverage = if (-not $installed) { 'NotDetected' }
        elseif ($osppPaths.Count -eq 0) { 'Unavailable' }
        elseif ($rawResults.Count -ne $osppPaths.Count) { 'Failed' }
        elseif ($pathResults.Count -gt 0 -and @($pathResults | Where-Object { -not [bool]$_.Complete }).Count -eq 0) { 'Complete' }
        else { 'Partial' }
    $requiresVNextEntitlement = [bool]($installed -and (Test-OfficeSubscriptionDeployment -LicenseEntries @($entries.ToArray())))
    $vNextEntitlementProbe = if ($requiresVNextEntitlement) {
        Get-OfficeVNextEntitlementProbe -OsppPaths $osppPaths
    } else {
        [pscustomobject][ordered]@{
            Coverage='NotRequired'; VNextDiagPaths=@(); PathResults=@(); RecordCount=0
            LicensedCount=0; GraceCount=0; RestrictedFunctionalityCount=0; NoActiveEntitlement=$false
        }
    }
    $probe = [pscustomobject][ordered]@{
        Installed=[bool]$installed; Coverage=$coverage; OsppPaths=@($osppPaths)
        PathResults=@($pathResults.ToArray()); Entries=@($entries.ToArray())
        ParsedSkuCount=[int]$entries.Count
        RequiresVNextEntitlement=$requiresVNextEntitlement
        EntitlementCoverage=[string]$vNextEntitlementProbe.Coverage
        VNextEntitlementProbe=$vNextEntitlementProbe
    }
    if ($probe.Installed -and $probe.Coverage -ne 'Complete') {
        Add-ScanWarning (Get-CleanupText 'cleanupReport.scan.officeProbeIncomplete' @($probe.Coverage))
    }
    if ($probe.RequiresVNextEntitlement -and $probe.EntitlementCoverage -ne 'Complete') {
        Add-ScanWarning (Get-CleanupText 'cleanupReport.scan.officeEntitlementProbeIncomplete' @($probe.EntitlementCoverage))
    }
    return $probe
}

function Get-OfficeLicenseEntries {
    $script:OfficeLicenseProbe = Get-OfficeLicenseProbe
    return @($script:OfficeLicenseProbe.Entries | Group-Object { "$($_.Path)|$($_.SkuId)|$($_.Last5)|$($_.Channel)" } | ForEach-Object { $_.Group[0] })
}

function Get-OfficeKmsEntries {
    param([AllowNull()][object[]]$LicenseEntries)
    # Chỉ trả về từng SKU Office KMS có key hoặc KMS override đang hoạt động.
    # Không đụng tới Retail/OEM/MAK và không báo nhầm license definition KMS
    # đã Unlicensed nhưng không còn product key.
    if (-not $PSBoundParameters.ContainsKey('LicenseEntries') -or $null -eq $LicenseEntries) {
        $LicenseEntries = @(Get-OfficeLicenseEntries)
    }
    return @($LicenseEntries | Where-Object {
        [string]$_.Channel -eq 'KMS' -and (
            -not [string]::IsNullOrWhiteSpace([string]$_.Last5) -or
            -not [string]::IsNullOrWhiteSpace([string]$_.Server)
        )
    } | Group-Object { "$($_.Path)|$($_.SkuId)|$($_.Last5)" } | ForEach-Object { $_.Group[0] })
}

function Get-OfficeKmsPathKey {
    param([AllowEmptyString()][string]$Path)

    $candidate = ([string]$Path).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) { return '' }
    try { $candidate = [IO.Path]::GetFullPath($candidate) } catch {}
    return $candidate.Trim().ToLowerInvariant()
}

function Get-OfficeKmsTargetIdentity {
    param([Parameter(Mandatory = $true)]$Entry)

    $pathKey = Get-OfficeKmsPathKey -Path ([string]$Entry.Path)
    $skuId = ([string]$Entry.SkuId).Trim().ToLowerInvariant()
    $last5 = ([string]$Entry.Last5).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($pathKey) -or
        [string]::IsNullOrWhiteSpace($skuId) -or
        [string]::IsNullOrWhiteSpace($last5)) {
        return ''
    }
    # Provider + SKU + Last5 is the stable product-key identity.  The concrete
    # OSPP path remains part of the identity as the installation instance, so
    # two Office installations can never authorize one another by accident.
    return "Provider=OfficeOSPP|SKU=$skuId|Last5=$last5|OSPP=$pathKey"
}

function Get-OfficeKmsHostOverrideIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    $pathKey = Get-OfficeKmsPathKey -Path $Path
    if ([string]::IsNullOrWhiteSpace($pathKey)) { return '' }
    # Host cleanup is deliberately path-scoped and must not depend on Last5.
    return "Provider=OfficeOSPP|HostOverride|OSPP=$pathKey"
}

function New-RemediationStateRecord {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateId,
        [string]$Kind = '',
        [string]$Provider = '',
        [string]$SkuId = '',
        [string]$Last5 = '',
        [string]$OsppPathInstance = '',
        [ValidateSet('Pending','Running','VerifiedClean','ApprovedInternalKMS','RetryableFailure','BlockedByPolicy','NeedsOfficeRepair')]
        [string]$InitialState = 'Pending',
        [bool]$RetryAllowed = $true,
        [string]$BlockCode = '',
        [string]$BlockDetail = ''
    )

    $terminal = $InitialState -in @('VerifiedClean','ApprovedInternalKMS','BlockedByPolicy','NeedsOfficeRepair')
    return [pscustomobject][ordered]@{
        SchemaVersion = '1.0'
        CandidateId = $CandidateId
        Kind = $Kind
        Provider = $Provider
        SkuId = $SkuId
        Last5 = $Last5
        OsppPathInstance = $OsppPathInstance
        State = $InitialState
        AttemptCount = 0
        RetryAllowed = [bool]($RetryAllowed -and -not $terminal)
        LastAttemptAtUtc = ''
        LastTransitionAtUtc = [DateTime]::UtcNow.ToString('o')
        LastErrorCode = ''
        LastErrorDetail = ''
        BlockCode = $BlockCode
        BlockDetail = $BlockDetail
        ArtifactCleanupCompleted = $false
        DirectCrackEvidenceRemaining = $true
        ApplicationPresent = $false
        OfficialLicenseState = 'Unverified'
        PostCheckAtUtc = ''
        OutcomeMessageKey = ''
    }
}

function Set-RemediationStateRecord {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Pending','Running','VerifiedClean','ApprovedInternalKMS','RetryableFailure','BlockedByPolicy','NeedsOfficeRepair')]
        [string]$State,
        [string]$ErrorCode = '',
        [string]$ErrorDetail = '',
        [string]$BlockCode = '',
        [string]$BlockDetail = '',
        [string]$OutcomeMessageKey = '',
        [switch]$IncrementAttempt
    )

    $current = [string]$Record.State
    $allowed = @{
        Pending=@('Pending','Running','ApprovedInternalKMS','BlockedByPolicy','NeedsOfficeRepair','RetryableFailure')
        Running=@('Running','VerifiedClean','ApprovedInternalKMS','RetryableFailure','BlockedByPolicy','NeedsOfficeRepair')
        RetryableFailure=@('RetryableFailure','Running','VerifiedClean','ApprovedInternalKMS','BlockedByPolicy','NeedsOfficeRepair')
        VerifiedClean=@('VerifiedClean')
        ApprovedInternalKMS=@('ApprovedInternalKMS')
        BlockedByPolicy=@('BlockedByPolicy')
        NeedsOfficeRepair=@('NeedsOfficeRepair','VerifiedClean')
    }
    if (-not $allowed.ContainsKey($current) -or $allowed[$current] -notcontains $State) {
        throw "Invalid remediation state transition: $current -> $State"
    }
    if ($IncrementAttempt -or ($State -eq 'Running' -and $current -ne 'Running')) {
        $Record.AttemptCount = [int]$Record.AttemptCount + 1
        $Record.LastAttemptAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $Record.State = $State
    $Record.RetryAllowed = [bool]($State -in @('Pending','RetryableFailure'))
    $Record.LastTransitionAtUtc = [DateTime]::UtcNow.ToString('o')
    $Record.LastErrorCode = $ErrorCode
    $Record.LastErrorDetail = $ErrorDetail
    $Record.BlockCode = $BlockCode
    $Record.BlockDetail = $BlockDetail
    $Record.OutcomeMessageKey = $OutcomeMessageKey
    return $Record
}

function Resolve-RemediationPostCheckState {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][bool]$DirectCrackEvidenceRemaining,
        [Parameter(Mandatory = $true)][bool]$ApplicationPresent,
        [Parameter(Mandatory = $true)][string]$OfficialLicenseState,
        [bool]$ArtifactCleanupCompleted = $false,
        [bool]$ApprovedInternalKms = $false,
        [string]$PolicyBlockCode = '',
        [string]$PolicyBlockDetail = '',
        [bool]$VolumeRepairRequired = $false,
        [bool]$ExpectedApplicationAbsent = $false,
        [bool]$AllowLicensedState = $false
    )

    $Record.DirectCrackEvidenceRemaining = $DirectCrackEvidenceRemaining
    $Record.ApplicationPresent = $ApplicationPresent
    $Record.OfficialLicenseState = $OfficialLicenseState
    $Record.ArtifactCleanupCompleted = $ArtifactCleanupCompleted
    $Record.PostCheckAtUtc = [DateTime]::UtcNow.ToString('o')

    if ($ApprovedInternalKms) {
        return Set-RemediationStateRecord -Record $Record -State ApprovedInternalKMS `
            -OutcomeMessageKey 'cleanupReport.remediation.approvedInternalKms'
    }
    if (-not [string]::IsNullOrWhiteSpace($PolicyBlockCode)) {
        return Set-RemediationStateRecord -Record $Record -State BlockedByPolicy `
            -BlockCode $PolicyBlockCode -BlockDetail $PolicyBlockDetail `
            -OutcomeMessageKey 'cleanupReport.remediation.blockedByPolicy'
    }
    if ($VolumeRepairRequired) {
        return Set-RemediationStateRecord -Record $Record -State NeedsOfficeRepair `
            -BlockCode 'VolumeOrMondoRequiresOfficialRepair' `
            -BlockDetail $PolicyBlockDetail -OutcomeMessageKey 'cleanupReport.remediation.needsOfficeRepair'
    }
    $acceptedPresentStates = @('Unactivated','Trial')
    if ($AllowLicensedState) { $acceptedPresentStates += 'Licensed' }
    $applicationOutcomeAccepted = if ($ExpectedApplicationAbsent) {
        -not $ApplicationPresent
    } else {
        $ApplicationPresent -and $OfficialLicenseState -in $acceptedPresentStates
    }
    if (-not $DirectCrackEvidenceRemaining -and $applicationOutcomeAccepted) {
        return Set-RemediationStateRecord -Record $Record -State VerifiedClean `
            -OutcomeMessageKey 'cleanupReport.remediation.verifiedClean'
    }

    $errorCode = if ($ArtifactCleanupCompleted -and -not $DirectCrackEvidenceRemaining) {
        'ArtifactsRemovedLicenseUnverified'
    } elseif ($ExpectedApplicationAbsent -and $ApplicationPresent) {
        'ApplicationStillPresentAfterUninstall'
    } elseif (-not $ExpectedApplicationAbsent -and -not $ApplicationPresent) {
        'ApplicationNotPresentAfterCleanup'
    } elseif ($DirectCrackEvidenceRemaining) {
        'DirectEvidenceStillPresent'
    } else {
        'OfficialStateNotAcceptedAfterCleanup'
    }
    $messageKey = if ($errorCode -eq 'ArtifactsRemovedLicenseUnverified') {
        'cleanupReport.remediation.artifactsRemovedLicenseUnverified'
    } else {
        'cleanupReport.remediation.retryableFailure'
    }
    return Set-RemediationStateRecord -Record $Record -State RetryableFailure `
        -ErrorCode $errorCode -ErrorDetail $OfficialLicenseState -OutcomeMessageKey $messageKey
}

function Status-Text {
    param($Code)
    switch ([int]$Code) {
        0 { Get-CleanupText "cleanupReport.status.unlicensed" }
        1 { Get-CleanupText "cleanupReport.status.licensed" }
        2 { Get-CleanupText "cleanupReport.status.oobGrace" }
        3 { Get-CleanupText "cleanupReport.status.ootGrace" }
        4 { Get-CleanupText "cleanupReport.status.nonGenuineGrace" }
        5 { Get-CleanupText "cleanupReport.status.notification" }
        6 { Get-CleanupText "cleanupReport.status.extendedGrace" }
        default { "$Code" }
    }
}

function Get-LicenseChannel {
    param($Product)
    $desc = [string]$Product.Description
    if ($desc -match "VOLUME_KMSCLIENT|KMSCLIENT") { return "KMS" }
    if ($desc -match "VOLUME_MAK|MAK") { return "MAK" }
    if ($desc -match "OEM") { return "OEM" }
    if ($desc -match "RETAIL") { return "Retail" }
    return (Get-CleanupText "common.unknown")
}

function Get-Oa3KeyPresent {
    try {
        $svc = Safe-Cim SoftwareLicensingService
        return -not [string]::IsNullOrWhiteSpace($svc.OA3xOriginalProductKey)
    } catch {
        return $false
    }
}

function Get-WindowsLicenseProducts {
    $queryError = ""
    $allProducts = @()
    $windowsProductsAny = @()
    $querySucceeded = $false
    try {
        $allProducts = if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            @(Get-CimInstance -ClassName SoftwareLicensingProduct -OperationTimeoutSec 25 -ErrorAction Stop)
        } else {
            @(Get-WmiObject -Class SoftwareLicensingProduct -ErrorAction Stop)
        }
        $querySucceeded = $true
        $windowsProductsAny = @($allProducts | Where-Object { $_.Name -match "Windows" })
        $windowsProductsWithKey = @($allProducts |
            Where-Object { $_.Name -match "Windows" -and $_.PartialProductKey } |
            Sort-Object LicenseStatus -Descending)
        if ($windowsProductsWithKey.Count -gt 0) { return $windowsProductsWithKey }

        $windowsProductsWithoutKey = @($allProducts |
            Where-Object {
                $_.Name -match "Windows" -and (
                    [int]$_.LicenseStatus -ne 0 -or
                    -not [string]::IsNullOrWhiteSpace([string]$_.KeyManagementServiceMachine)
                )
            } |
            Sort-Object LicenseStatus -Descending)
        if ($windowsProductsWithoutKey.Count -gt 0) {
            $script:WindowsLicenseSourceNote = Get-CleanupText "cleanupReport.scan.partialKeyMissingContinue"
            return $windowsProductsWithoutKey
        }

        $queryError = Get-CleanupText "cleanupReport.scan.partialKeyMissing"
    } catch { $queryError = $_.Exception.Message }

    $fallback = @(Get-WindowsLicenseProductsFromSlmgr)
    if ($fallback.Count -gt 0) { return $fallback }
    if ($querySucceeded -and $windowsProductsAny.Count -gt 0) {
        $script:WindowsLicenseSourceNote = Get-CleanupText "cleanupReport.scan.noReadableKey"
        return @()
    }
    if ($querySucceeded -and $allProducts.Count -gt 0 -and $windowsProductsAny.Count -eq 0) {
        $queryError = Get-CleanupText "cleanupReport.scan.noWindowsProduct"
    }
    Add-ScanWarning (Get-CleanupText "cleanupReport.scan.windowsLicenseFailed" @($queryError))
    return @()
}

function Get-WindowsLicenseProductsFromSlmgr {
    $dlv = Run-Cscript -SlmgrArguments @("/dlv")
    if ([string]::IsNullOrWhiteSpace($dlv) -or $dlv -match "^ERROR:") {
        return @()
    }

    $name = Get-RegexValue $dlv "(?im)^(?:Name|Tên)\s*:\s*(.+)$"
    if ($name -notmatch "Windows" -and $dlv -notmatch "(?i)Windows") {
        return @()
    }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "Windows (slmgr)" }

    $kmsServer = Get-RegexValue $dlv "(?im)^    KMS machine name from DNS:\s*(.+)$"
    if ([string]::IsNullOrWhiteSpace($kmsServer)) {
        $kmsServer = Get-RegexValue $dlv "(?im)^Key Management Service machine name:\s*(.+)$"
    }
    if ([string]::IsNullOrWhiteSpace($kmsServer)) {
        $kmsServer = Get-RegexValue $dlv "(?im)^(?:Tên máy Dịch vụ Quản lý Khóa|Tên máy KMS|Máy chủ KMS)\s*:\s*(.+)$"
    }
    if ([string]::IsNullOrWhiteSpace($kmsServer)) {
        $kmsServer = Get-RegexValue $dlv "(?im)^    KMS machine IP address:\s*(.+)$"
    }
    if ($kmsServer -match "not available") {
        $kmsServer = ""
    }

    return @([pscustomobject]@{
        ID = Get-RegexValue $dlv "(?im)^(?:Activation ID|ID kích hoạt|ID Kích hoạt)\s*:\s*(.+)$"
        Name = $name
        Description = Get-RegexValue $dlv "(?im)^(?:Description|Mô tả)\s*:\s*(.+)$"
        LicenseStatus = Get-LicenseStatusCodeFromText $dlv
        PartialProductKey = Get-RegexValue $dlv "(?im)^(?:Partial Product Key|Khóa sản phẩm một phần|5 ký tự cuối)\s*:\s*(.+)$"
        KeyManagementServiceMachine = $kmsServer
    })
}

function Get-RegexValue {
    param([string]$Text, [string]$Pattern)
    if ($Text -match $Pattern) {
        return $matches[1].Trim()
    }
    return ""
}

function Get-LicenseStatusCodeFromText {
    param([string]$Text)
    if ($Text -match "(?im)^License Status:\s*Licensed\b") { return 1 }
    if ($Text -match "(?im)^License Status:\s*Unlicensed\b") { return 0 }
    if ($Text -match "(?im)^License Status:\s*Notification\b") { return 5 }
    if ($Text -match "(?im)^License Status:\s*Non-genuine") { return 4 }
    if ($Text -match "(?im)^Trạng thái giấy phép\s*:\s*.*(đã cấp phép|được cấp phép|licensed)") { return 1 }
    if ($Text -match "(?im)^Trạng thái giấy phép\s*:\s*.*(chưa cấp phép|unlicensed)") { return 0 }
    if ($Text -match "(?im)^Trạng thái giấy phép\s*:\s*.*(thông báo|notification)") { return 5 }
    return 0
}

function Test-ApprovedKms {
    param([string]$Server)
    if ([string]::IsNullOrWhiteSpace($Server)) { return $false }
    $candidate = $Server.Trim().ToLowerInvariant()
    if ($candidate -match "^([^:]+):\d+$") { $candidate = $matches[1] }
    if ($candidate -match "^\[([^\]]+)\]:\d+$") { $candidate = $matches[1] }
    foreach ($approved in $ApprovedKmsServers) {
        $approvedCandidate = $approved.Trim().ToLowerInvariant()
        if ($approvedCandidate -match "^([^:]+):\d+$") { $approvedCandidate = $matches[1] }
        if ($approvedCandidate -match "^\[([^\]]+)\]:\d+$") { $approvedCandidate = $matches[1] }
        if ($candidate -eq $approvedCandidate) {
            return $true
        }
    }
    return $false
}
