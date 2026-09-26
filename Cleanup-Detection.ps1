# VietLicenSure v5.0 - dot-sourced function library
# Extracted mechanically from windows-license-compliance-cleanup.ps1; contains function definitions only.
# Keep this file beside its compatible entrypoint.

function Get-CleanupExecutablePathFromCommandLine {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    $match = [regex]::Match($expanded, '^\s*"([^"]+\.exe)"|^\s*([^\s"]+\.exe)\b', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return '' }
    $path = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
    try { return [IO.Path]::GetFullPath($path) } catch { return '' }
}

function Get-ActivatorFindings {
    # Mẫu đặc hiệu; không dùng chuỗi ngắn như "mas" vì dễ trùng tên hợp lệ.
    $findings = New-Object System.Collections.Generic.List[object]

    try {
        Get-CompatibleScheduledTaskRecords | Where-Object {
            Test-CleanupKnownActivatorText ((([string]$_.TaskName) + ' ' + ([string]$_.TaskPath) + ' ' + ([string]$_.ActionsText)).Trim())
        } | ForEach-Object {
            $findings.Add([pscustomobject]@{
                Type = "ScheduledTask"
                Name = [string]$_.FullName
                Location = ([string]$_.ActionsText).Trim()
                Action = Get-CleanupText "cleanupReport.candidate.disableTask"
            })
        }
    } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.scan.tasksEvaluateFailed" @($_.Exception.Message)) }

    try {
        Safe-Cim -ClassName Win32_Service -CriticalLabel (Get-CleanupText "cleanupReport.scan.servicesCritical") | Where-Object {
            Test-CleanupKnownActivatorText ((([string]$_.Name) + ' ' + ([string]$_.DisplayName) + ' ' + ([string]$_.PathName)).Trim())
        } | ForEach-Object {
            $findings.Add([pscustomobject]@{
                Type = "Service"
                Name = $_.Name
                Location = $_.PathName
                Action = Get-CleanupText "cleanupReport.candidate.stopDisableService"
            })
        }
    } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.scan.servicesEvaluateFailed" @($_.Exception.Message)) }

    try {
        Get-Process | Where-Object {
            Test-CleanupKnownActivatorText ((([string]$_.ProcessName) + ' ' + ([string]$_.Path)).Trim())
        } | ForEach-Object {
            $findings.Add([pscustomobject]@{
                Type = "Process"
                Name = $_.ProcessName
                Location = $_.Path
                ProcessId = [int]$_.Id
                Action = Get-CleanupText "cleanupReport.candidate.stopProcess"
            })
        }
    } catch {}

    # Win32_StartupCommand bao phủ các mục Startup Manager/Run phổ biến. Chỉ
    # ghi nhận để xem xét thủ công vì Location của CIM không đủ an toàn để suy
    # diễn rồi xóa một registry value hay shortcut tự động.
    try {
        Safe-Cim -ClassName Win32_StartupCommand | Where-Object {
            Test-CleanupKnownActivatorText ((([string]$_.Name) + ' ' + ([string]$_.Command) + ' ' + ([string]$_.Location)).Trim())
        } | ForEach-Object {
            $findings.Add([pscustomobject]@{
                Type = "Startup"
                Name = [string]$_.Name
                Location = [string]$_.Command
                Action = Get-CleanupText "cleanupReport.candidate.reviewFolder"
                StartupLocation = [string]$_.Location
                ComponentScope = "Shared"
            })
        }
    } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.thirdParty.inventorySourceFailed" @('Win32_StartupCommand', $_.Exception.Message)) }

    foreach ($runPath in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )) {
        try {
            $runItem = Get-ItemProperty -LiteralPath $runPath -ErrorAction Stop
            foreach ($property in @($runItem.PSObject.Properties | Where-Object { [string]$_.Name -notmatch '^PS' })) {
                $value = [string]$property.Value
                if (-not (Test-CleanupKnownActivatorText (([string]$property.Name) + ' ' + $value))) { continue }
                $findings.Add([pscustomobject]@{
                    Type='StartupRegistry'; Name=[string]$property.Name; Location=$runPath
                    Action=(Get-CleanupText 'cleanupReport.candidate.removeStartup')
                    RegistryValueName=[string]$property.Name; ExpectedRegistryValue=$value; ComponentScope='Shared'
                })
            }
        } catch {}
    }

    $scanRoots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramW6432,
        $env:ProgramData,
        (Join-Path $env:SystemDrive "KMS"),
        (Join-Path $env:SystemDrive "KMSAuto"),
        (Join-Path $env:SystemDrive "KMSpico"),
        (Join-Path $env:SystemDrive "AAct")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    foreach ($root in $scanRoots) {
        try {
            $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
            if (Test-CleanupKnownActivatorText ([string]$rootItem.Name)) {
                $findings.Add([pscustomobject]@{
                    Type='Folder'; Name=[string]$rootItem.Name; Location=[string]$rootItem.FullName
                    Action=(Get-CleanupText 'cleanupReport.candidate.reviewFolder')
                })
                continue
            }
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-CleanupKnownActivatorText ([string]$_.Name) } |
                ForEach-Object {
                    $findings.Add([pscustomobject]@{
                        Type = "Folder"
                        Name = $_.Name
                        Location = $_.FullName
                        Action = Get-CleanupText "cleanupReport.candidate.reviewFolder"
                    })
                }
        } catch {}
    }

    return $findings
}

function Invoke-CleanupNativeCommandWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$Arguments = @(),
        [ValidateRange(5, 300)][int]$TimeoutSeconds = 120
    )

    $quotedArguments = @($Arguments | ForEach-Object {
        $argument = [string]$_
        if ($argument -match '[\s"]') { '"' + ($argument -replace '"', '\"') + '"' } else { $argument }
    }) -join ' '
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $quotedArguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw (Get-CleanupText "cleanupReport.native.startFailed" @([IO.Path]::GetFileName($FilePath))) }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit([int]($TimeoutSeconds * 1000))
        if (-not $completed) {
            try { $process.Kill() } catch {}
            try { [void]$process.WaitForExit(3000) } catch {}
        }
        $output = (($stdoutTask.GetAwaiter().GetResult() + " | " + $stderrTask.GetAwaiter().GetResult()) -replace "`0", "").Trim(' ', '|')
        return [pscustomobject]@{
            Completed = [bool]$completed
            TimedOut = [bool](-not $completed)
            ExitCode = if ($completed) { [int]$process.ExitCode } else { -1 }
            Output = $output
        }
    } finally {
        $process.Dispose()
    }
}

function Get-ThirdPartyVendorScope {
    param([string]$Name, [string]$Publisher)
    $text = (([string]$Name) + " " + ([string]$Publisher)).Trim()
    if ($text -match '(?i)\bAdobe\b|\bAcrobat\b|\bPhotoshop\b|\bIllustrator\b|\bInDesign\b|\bLightroom\b|\bPremiere\b|\bAfter Effects\b') { return "Adobe" }
    if ($text -match '(?i)\bAutodesk\b|\bAutoCAD\b|\bRevit\b|\b3ds Max\b|\bCivil 3D\b|\bNavisworks\b|\bInventor\b|\bFusion 360\b') { return "Autodesk" }
    return "Other"
}

function Get-ThirdPartyEvidenceScope {
    param([string]$Text)
    if ([string]$Text -match $script:ThirdPartyAdobeActivatorPattern) { return "Adobe" }
    if ([string]$Text -match $script:ThirdPartyAutodeskActivatorPattern) { return "Autodesk" }
    return ""
}

function ConvertTo-ToolRegistryPath {
    param([string]$NativeRegistryPath)
    if ([string]::IsNullOrWhiteSpace($NativeRegistryPath)) { return "" }
    if ($NativeRegistryPath.StartsWith('HKEY_LOCAL_MACHINE\', [StringComparison]::OrdinalIgnoreCase)) {
        return 'HKLM:\' + $NativeRegistryPath.Substring('HKEY_LOCAL_MACHINE\'.Length)
    }
    if ($NativeRegistryPath.StartsWith('HKEY_CURRENT_USER\', [StringComparison]::OrdinalIgnoreCase)) {
        return 'HKCU:\' + $NativeRegistryPath.Substring('HKEY_CURRENT_USER\'.Length)
    }
    return $NativeRegistryPath
}

function Get-InstalledSoftwareInventory {
    try {
        return @(Get-ToolInstalledSoftwareInventory -IncludeAppx -IncludeShortcuts -IncludePortable -IncludePackageManagers -PortableMaximumResults 350 -PortableMaximumDepth 3)
    } catch {
        Add-ScanWarning (Get-CleanupText "cleanupReport.thirdParty.inventorySourceFailed" @('AllSoftwareSources', $_.Exception.Message))
        return @()
    }
}

function Get-ThirdPartyAssessmentStatusLabel {
    param([string]$StatusCode)
    $key = switch ($StatusCode) {
        'FreeOrIncluded' { 'cleanupReport.thirdParty.status.freeOrIncluded' }
        'GenuineVerified' { 'cleanupReport.thirdParty.status.genuineVerified' }
        'Unactivated' { 'cleanupReport.thirdParty.status.unactivated' }
        'NonGenuine' { 'cleanupReport.thirdParty.status.nonGenuine' }
        'IntegrityCompromised' { 'cleanupReport.thirdParty.status.integrityCompromised' }
        'Suspicious' { 'cleanupReport.thirdParty.status.suspicious' }
        'TrialOrUnverified' { 'cleanupReport.thirdParty.status.trialOrUnverified' }
        default { 'cleanupReport.thirdParty.status.unverified' }
    }
    return Get-CleanupText $key
}

function Get-ThirdPartyCorrelationTokens {
    param([string]$Text)
    $ignored = @('software','application','applications','program','professional','enterprise','edition','desktop','studio','editor','viewer','reader','update','helper','service','services','windows','microsoft','corporation','company','limited','inc','ltd','the','and','for','with','x64','x86','bit')
    return @(([regex]::Split(([string]$Text).ToLowerInvariant(), '[^a-z0-9]+') |
        Where-Object { $_.Length -ge 4 -and $_ -notmatch '^\d+$' -and $ignored -notcontains $_ } |
        Sort-Object Length -Descending -Unique | Select-Object -First 8))
}

function Get-ThirdPartyEvidenceTargets {
    param([string]$Text, $ApplicationRecords, [string]$SpecificVendorScope = '')
    # A token such as "pro" or a shared vendor label is only a hint.  Preserve
    # the match kind and prefer an exact install/representative path over a
    # vendor-wide fallback, so remediation can only use direct evidence.
    $exactTargets = New-Object System.Collections.Generic.List[object]
    $vendorTargets = New-Object System.Collections.Generic.List[object]
    $tokenTargets = New-Object System.Collections.Generic.List[object]
    foreach ($record in @($ApplicationRecords)) {
        $matchKind = ''
        if ($record.InstallRoot -and $Text.IndexOf([string]$record.InstallRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $matchKind = 'ExactPath'
        } elseif ($record.RepresentativePath -and $Text.IndexOf([string]$record.RepresentativePath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $matchKind = 'ExactPath'
        } elseif ($SpecificVendorScope -and [string]$record.VendorScope -eq $SpecificVendorScope) {
            $matchKind = 'VendorScope'
        } else {
            foreach ($token in @($record.Tokens)) {
                if ($Text -match ('(?i)(?<![a-z0-9])' + [regex]::Escape([string]$token) + '(?![a-z0-9])')) { $matchKind='Token'; break }
            }
        }
        if ([string]::IsNullOrWhiteSpace($matchKind)) { continue }
        $match = [pscustomobject][ordered]@{
            Record=$record; MatchKind=$matchKind
            Specificity=$(if ($matchKind -eq 'ExactPath') { [Math]::Max(([string]$record.InstallRoot).Length, ([string]$record.RepresentativePath).Length) } else { 0 })
        }
        if ($matchKind -eq 'ExactPath') { $exactTargets.Add($match) }
        elseif ($matchKind -eq 'VendorScope') { $vendorTargets.Add($match) }
        else { $tokenTargets.Add($match) }
    }
    if ($exactTargets.Count -gt 0) {
        # When product roots overlap, use only the deepest exact match. This
        # prevents a file under Adobe\Acrobat from also being attached to every
        # Adobe product whose registration exposes the shared Adobe directory.
        $maximumSpecificity = [int](($exactTargets.ToArray() | Measure-Object -Property Specificity -Maximum).Maximum)
        return @($exactTargets.ToArray() | Where-Object { [int]$_.Specificity -eq $maximumSpecificity })
    }
    if ($vendorTargets.Count -gt 0) { return $vendorTargets.ToArray() }
    return $tokenTargets.ToArray()
}

function Get-ThirdPartyStrongEvidence {
    param($Applications, [AllowNull()][object]$Catalog)
    $evidence = New-Object System.Collections.Generic.List[object]
    $applicationRecords = New-Object System.Collections.Generic.List[object]
    foreach ($app in @($Applications | Where-Object { -not [bool]$_.IsMicrosoft })) {
        $catalogProduct = Find-ToolSoftwareCatalogProduct -Application $app -Catalog $Catalog
        $vendorScope = Get-ToolSoftwareVendorScope -Application $app -CatalogProduct $catalogProduct
        $applicationRecords.Add([pscustomobject][ordered]@{
            Application=$app; ApplicationId=[string]$app.Id; VendorScope=$vendorScope
            InstallRoot=(Get-ThirdPartyNormalizedInstallRoot -Application $app)
            RepresentativePath=[string]$app.RepresentativePath
            Tokens=@(Get-ThirdPartyCorrelationTokens (([string]$app.Name) + ' ' + ([string]$app.Publisher)))
        })
    }
    $addEvidence = {
        param(
            [string]$Type,[string]$Name,[string]$Location,[string]$RegistryPath,[string]$Detail,
            [string]$SpecificScope,[bool]$KnownSpecific,[bool]$Active,[bool]$FolderOnly,$Targets,
            [int]$ProcessId=0,[string]$ExpectedExecutablePath='',[string]$ExpectedSha256='',[int64]$ExpectedLength=-1
        )
        $resolvedTargets = @($Targets)
        if ($resolvedTargets.Count -eq 0) {
            $evidence.Add([pscustomobject][ordered]@{
                Code=('Uncorrelated' + $Type); Type=$Type; Source=$Type; Name=$Name; Location=$Location; RegistryPath=$RegistryPath
                VendorScope='Uncorrelated'; ApplicationId=''; Strength=$(if ($KnownSpecific) {'Strong'} else {'Moderate'})
                EvidenceGroup=$(if ($Active) {'ActivatorPersistence'} else {'ActivatorArtifact'}); Decisive=$false; Detail=$Detail
                CorrelationLevel='Uncorrelated'
                ProcessId=$ProcessId; ExpectedExecutablePath=$ExpectedExecutablePath
                ExpectedSha256=$ExpectedSha256; ExpectedLength=$ExpectedLength
            })
            return
        }
        foreach ($target in $resolvedTargets) {
            $targetRecord = if ($target.PSObject.Properties['Record']) { $target.Record } else { $target }
            $matchKind = if ($target.PSObject.Properties['MatchKind']) { [string]$target.MatchKind } else { 'Token' }
            $decisive = [bool](-not $FolderOnly -and $KnownSpecific -and $Active)
            $strength = if ($decisive) { 'Strong' } else { 'Moderate' }
            $correlationLevel = if ($matchKind -eq 'ExactPath' -and $resolvedTargets.Count -eq 1) { 'Direct' } elseif ($matchKind -eq 'VendorScope') { 'VendorShared' } else { 'Heuristic' }
            $evidence.Add([pscustomobject][ordered]@{
                Code=$(if ($KnownSpecific) {'KnownActivator' + $Type} else {'SuspiciousActivator' + $Type})
                Type=$Type; Source=$Type; Name=$Name; Location=$Location; RegistryPath=$RegistryPath
                VendorScope=[string]$targetRecord.VendorScope; ApplicationId=[string]$targetRecord.ApplicationId; Strength=$strength
                EvidenceGroup=$(if ($Active) {'ActivatorPersistence'} else {'ActivatorArtifact'}); Decisive=$decisive; Detail=$Detail
                CorrelationLevel=$correlationLevel
                ProcessId=$ProcessId; ExpectedExecutablePath=$ExpectedExecutablePath
                ExpectedSha256=$ExpectedSha256; ExpectedLength=$ExpectedLength
            })
        }
    }

    foreach ($record in @($applicationRecords.ToArray())) {
        $app = $record.Application
        $text = (([string]$app.Name) + ' ' + ([string]$app.Publisher) + ' ' + ([string]$app.InstallLocation))
        $specificScope = Get-ThirdPartyEvidenceScope $text
        $knownSpecific = [bool]($specificScope -or (Test-ToolSoftwareKnownActivatorText -Text $text))
        $generic = [bool]($knownSpecific -or $text -match $script:ToolSoftwareSuspiciousArtifactPattern)
        if (-not $generic) { continue }
        $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
        & $addEvidence 'InstalledActivator' ([string]$app.Name) ([string]$app.InstallLocation) ([string]$app.RegistryPath) `
            (Get-CleanupText "cleanupReport.thirdParty.evidence.installedActivator") $specificScope $knownSpecific $true $false $targets
    }

    try {
        foreach ($task in @(Get-CompatibleScheduledTaskRecords)) {
            $text = (([string]$task.FullName) + ' ' + ([string]$task.ActionsText))
            $specificScope = Get-ThirdPartyEvidenceScope $text
            $knownSpecific = [bool]($specificScope -or (Test-ToolSoftwareKnownActivatorText -Text $text))
            if (-not $knownSpecific -and $text -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) { continue }
            $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
            & $addEvidence 'ScheduledTask' ([string]$task.FullName) ([string]$task.ActionsText) '' `
                (Get-CleanupText "cleanupReport.thirdParty.evidence.task") $specificScope $knownSpecific $true $false $targets
        }
    } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.thirdParty.tasksFailed" @($_.Exception.Message)) }

    try {
        foreach ($service in @(Safe-Cim -ClassName Win32_Service -CriticalLabel (Get-CleanupText "cleanupReport.scan.servicesCritical"))) {
            $text = (([string]$service.Name) + ' ' + ([string]$service.DisplayName) + ' ' + ([string]$service.PathName))
            $specificScope = Get-ThirdPartyEvidenceScope $text
            $knownSpecific = [bool]($specificScope -or (Test-ToolSoftwareKnownActivatorText -Text $text))
            if (-not $knownSpecific -and $text -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) { continue }
            $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
            & $addEvidence 'Service' ([string]$service.Name) ([string]$service.PathName) '' `
                (Get-CleanupText "cleanupReport.thirdParty.evidence.service") $specificScope $knownSpecific $true $false $targets
        }
    } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.thirdParty.servicesFailed" @($_.Exception.Message)) }

    try {
        foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
            $processPath = ''
            try { $processPath = [string]$process.Path } catch {}
            $text = (([string]$process.ProcessName) + ' ' + $processPath)
            $specificScope = Get-ThirdPartyEvidenceScope $text
            $knownSpecific = [bool]($specificScope -or (Test-ToolSoftwareKnownActivatorText -Text $text))
            if (-not $knownSpecific -and $text -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) { continue }
            $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
            $processIdentity = $null
            if ($processPath -and (Test-ThirdPartyArtifactPath -Path $processPath -Applications $Applications -AllowUserArtifactRoots)) {
                $processIdentity = Get-ThirdPartyArtifactExecutionIdentity -Path $processPath
            }
            & $addEvidence 'Process' ([string]$process.ProcessName) $processPath '' `
                (Get-CleanupText "cleanupReport.thirdParty.evidence.process") $specificScope $knownSpecific $true $false $targets `
                $(if ($processIdentity) { [int]$process.Id } else { 0 }) `
                $(if ($processIdentity) { [string]$processIdentity.Path } else { '' }) `
                $(if ($processIdentity) { [string]$processIdentity.Sha256 } else { '' }) `
                $(if ($processIdentity) { [int64]$processIdentity.Length } else { -1 })
        }
    } catch {}

    $scanRoots = @($env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    foreach ($root in $scanRoots) {
        try {
            $levelOne = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 800)
            $bounded = New-Object System.Collections.Generic.List[object]
            foreach ($directory in $levelOne) { $bounded.Add($directory) }
            foreach ($directory in $levelOne) {
                try { foreach ($child in @(Get-ChildItem -LiteralPath $directory.FullName -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 200)) { $bounded.Add($child) } } catch {}
                if ($bounded.Count -ge 3000) { break }
            }
            foreach ($directory in @($bounded.ToArray() | Select-Object -First 3000)) {
                $text = [string]$directory.FullName
                $specificScope = Get-ThirdPartyEvidenceScope $text
                $knownSpecific = [bool]($specificScope -or (Test-ToolSoftwareKnownActivatorText -Text $text))
                if (-not $knownSpecific -and $text -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) { continue }
                $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
                & $addEvidence 'Folder' ([string]$directory.Name) $text '' `
                    (Get-CleanupText "cleanupReport.thirdParty.evidence.folder") $specificScope $knownSpecific $false $true $targets
            }
        } catch {}
    }

    if (Get-Command Find-ToolPatternFilesParallel -ErrorAction SilentlyContinue) {
        $artifactRoots = New-Object System.Collections.Generic.List[string]
        foreach ($root in @($env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA, $env:TEMP, $env:TMP,
            [Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'))) {
            if ($root -and (Test-Path -LiteralPath $root -PathType Container) -and -not $artifactRoots.Contains([string]$root)) { $artifactRoots.Add([string]$root) }
        }
        try {
            $usersRoot = Join-Path $env:SystemDrive 'Users'
            foreach ($userDirectory in @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 40)) {
                foreach ($relative in @('AppData\Local','AppData\Roaming','Downloads','Desktop')) {
                    $candidate = Join-Path $userDirectory.FullName $relative
                    if (Test-Path -LiteralPath $candidate -PathType Container -ErrorAction SilentlyContinue) { $artifactRoots.Add($candidate) }
                }
            }
        } catch {}
        $knownPattern = $script:ToolSoftwareKnownActivatorPattern -replace '^\(\?i\)', ''
        $suspiciousPattern = $script:ToolSoftwareSuspiciousArtifactPattern -replace '^\(\?i\)', ''
        $artifactPattern = '(?i)(?:' + $knownPattern + ')|(?:' + $suspiciousPattern + ')'
        try {
            foreach ($path in @(Find-ToolPatternFilesParallel -Roots @($artifactRoots.ToArray() | Select-Object -Unique | Select-Object -First 24) -Pattern $artifactPattern `
                -MaximumResults 240 -ThrottleLimit 4 -MaximumDepth 4 -PerRootTimeoutSeconds 5)) {
                $text = [string]$path
                if (([IO.Path]::GetExtension($text)).ToLowerInvariant() -notin @('.exe','.dll','.com','.scr','.cmd','.bat','.ps1','.vbs','.js','.msi','.zip','.rar','.7z','.jar')) { continue }
                $specificScope = Get-ThirdPartyEvidenceScope $text
                $knownSpecific = [bool]($specificScope -or (Test-ToolSoftwareKnownActivatorText -Text $text))
                $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
                & $addEvidence 'FileArtifact' ([IO.Path]::GetFileName($text)) $text '' `
                    (Get-CleanupText "cleanupReport.thirdParty.evidence.folder") $specificScope $knownSpecific $false $true $targets
            }
        } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.thirdParty.inventorySourceFailed" @('DeepArtifactSearch', $_.Exception.Message)) }
    }

    return @($evidence.ToArray() |
        Group-Object { "$($_.Code)|$($_.Type)|$($_.Name)|$($_.Location)|$($_.VendorScope)|$($_.ApplicationId)" } |
        ForEach-Object { $_.Group[0] } |
        Sort-Object VendorScope, ApplicationId, Type, Name)
}

function Get-ThirdPartyLicenseStatePaths {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Adobe','Autodesk','WinRAR')][string]$RemediationAdapter,
        $Applications = @()
    )
    # A vendor licence store or local entitlement file may be legitimate.
    # There is currently no vendor adapter that proves a precise
    # local record is invalid, so never add it to an automatic plan.  Keep this
    # function as an explicit fail-closed seam for a future verified adapter.
    return @()
}

function Get-ThirdPartyRemediationPlan {
    param(
        [string]$RemediationAdapter,
        [string]$EvidenceScope,
        $Evidence,
        $Applications = @(),
        [switch]$PreserveVendorLicenseState
    )
    $plan = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Evidence | Where-Object { [string]$_.VendorScope -eq $EvidenceScope })) {
        switch ([string]$item.Type) {
            'InstalledActivator' {
                if (-not [string]::IsNullOrWhiteSpace([string]$item.RegistryPath)) {
                    $plan.Add([pscustomobject][ordered]@{ Type='Registry'; Kind='ThirdPartyUninstallEntry'; Name=[string]$item.Name; Location=[string]$item.RegistryPath; Detail=[string]$item.Detail; Restorable=$false })
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$item.Location) -and (Test-Path -LiteralPath ([string]$item.Location) -PathType Container)) {
                    $plan.Add([pscustomobject][ordered]@{ Type='Folder'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$item.Location; Detail=[string]$item.Detail; Restorable=$false })
                }
            }
            'ScheduledTask' { $plan.Add([pscustomobject][ordered]@{ Type='ScheduledTask'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$item.Location; Detail=[string]$item.Detail; Restorable=$false }) }
            'Service' { $plan.Add([pscustomobject][ordered]@{ Type='Service'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$item.Location; Detail=[string]$item.Detail; Restorable=$false }) }
            'Process' {
                $processId = if ($item.PSObject.Properties['ProcessId']) { [int]$item.ProcessId } else { 0 }
                $expectedPath = if ($item.PSObject.Properties['ExpectedExecutablePath']) { [string]$item.ExpectedExecutablePath } else { '' }
                $expectedSha256 = if ($item.PSObject.Properties['ExpectedSha256']) { [string]$item.ExpectedSha256 } else { '' }
                $expectedLength = if ($item.PSObject.Properties['ExpectedLength']) { [int64]$item.ExpectedLength } else { -1 }
                if ($processId -gt 0 -and $expectedSha256 -match '^[0-9A-F]{64}$' -and $expectedLength -ge 0 -and
                    [string]::Equals([string]$item.Location, $expectedPath, [StringComparison]::OrdinalIgnoreCase) -and
                    (Test-ThirdPartyArtifactPath -Path $expectedPath -Applications $Applications -AllowUserArtifactRoots)) {
                    $currentIdentity = Get-ThirdPartyArtifactExecutionIdentity -Path $expectedPath
                    if ($currentIdentity -and [string]$currentIdentity.Sha256 -eq $expectedSha256 -and [int64]$currentIdentity.Length -eq $expectedLength) {
                        # Stop only the exact scanned PID/path/hash, then move
                        # that same executable into the signed quarantine.
                        $plan.Add([pscustomobject][ordered]@{
                            Type='Process'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=$expectedPath
                            Detail=[string]$item.Detail; Restorable=$false; ProcessId=$processId
                            ExpectedExecutablePath=$expectedPath; ExpectedSha256=$expectedSha256; ExpectedLength=$expectedLength
                        })
                        $plan.Add([pscustomobject][ordered]@{
                            Type='File'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[IO.Path]::GetFileName($expectedPath); Location=$expectedPath
                            Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.quarantineArtifact'); Restorable=$false
                            ExpectedSha256=$expectedSha256; ExpectedLength=$expectedLength
                        })
                    }
                }
            }
            'Folder' { $plan.Add([pscustomobject][ordered]@{ Type='Folder'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$item.Location; Detail=[string]$item.Detail; Restorable=$false }) }
            'FileArtifact' {
                if (Test-ThirdPartyArtifactPath -Path ([string]$item.Location) -Applications $Applications -AllowUserArtifactRoots) {
                    $artifactIdentity = Get-ThirdPartyArtifactExecutionIdentity -Path ([string]$item.Location)
                    if ($artifactIdentity) {
                        $plan.Add([pscustomobject][ordered]@{
                            Type='File'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$artifactIdentity.Path
                            Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.quarantineArtifact'); Restorable=$false
                            ExpectedSha256=[string]$artifactIdentity.Sha256; ExpectedLength=[int64]$artifactIdentity.Length
                        })
                    }
                }
            }
        }
    }
    # Shared Adobe/Autodesk stores can belong to several products or accounts.
    # Keep them intact; remediation is limited to direct artifacts and hosts
    # entries belonging to a confirmed application.
    foreach ($supportingItem in @(Get-ThirdPartyGenericRemediationPlan -Applications $Applications | Where-Object {
        [string]$_.Type -in @('File','Hosts')
    })) { $plan.Add($supportingItem) }
    # State stores are deliberately never reset.  Proven artifacts are handled
    # above; the product's actual entitlement remains for the vendor to verify.
    return @($plan.ToArray() |
        Group-Object { "$($_.Type)|$($_.Kind)|$($_.Name)|$($_.Location)" } |
        ForEach-Object { $_.Group[0] })
}

function Get-ThirdPartyNormalizedInstallRoot {
    param($Application)
    # Prefer the executable's product directory over an installer-supplied
    # vendor root such as C:\Program Files\Adobe. Shared vendor roots cause
    # evidence from Acrobat, Lightroom and Premiere to contaminate each other.
    foreach ($candidate in @($(if ($Application.RepresentativePath) { Split-Path -Parent ([string]$Application.RepresentativePath) }), [string]$Application.InstallLocation)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
            $full = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
            $root = ([IO.Path]::GetPathRoot($full)).TrimEnd('\')
            if ([string]::Equals($full, $root, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $isBroadRoot = $false
            foreach ($broadCandidate in @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
                    [Environment]::GetFolderPath('UserProfile'), $env:LOCALAPPDATA, $env:APPDATA)) {
                if ([string]::IsNullOrWhiteSpace([string]$broadCandidate)) { continue }
                $broadRoot = ([IO.Path]::GetFullPath([string]$broadCandidate)).TrimEnd('\')
                if ([string]::Equals($full, $broadRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    $isBroadRoot = $true
                    break
                }
            }
            if (-not $isBroadRoot -and $full.Length -ge 8) { return $full }
        } catch {}
    }
    return ''
}

function Test-ThirdPartyArtifactPath {
    param([string]$Path, $Applications, [switch]$AllowUserArtifactRoots)
    $allowedExtensions = @('.exe','.dll','.com','.scr','.cmd','.bat','.ps1','.vbs','.js','.msi','.zip','.rar','.7z','.jar')
    if ([string]::IsNullOrWhiteSpace($Path) -or
        $allowedExtensions -notcontains ([IO.Path]::GetExtension($Path)).ToLowerInvariant()) { return $false }
    $artifactName = [IO.Path]::GetFileName($Path)
    $nameMatched = [bool]($artifactName -match '(?i)(crack(?:ed)?|keygen|activator|activation[._ -]*(?:bypass|patch(?:er)?)|licen[cs]e[._ -]*(?:bypass|patch(?:er)?)|serial[._ -]*generator|genp|ccmaker|xf[._ -]*adsk|x[._ -]*force|amtlib[._ -]*(?:patch|emulator)|kms(?:pico|auto(?:s|[._ -]*(?:net|lite|portable|plus|\+\+))?|[._ -]*(?:38|vl))|auto[._ -]*kms|aact(?:[._ -]*(?:network|portable))?|massgrave|mas[._ -]*aio|tsforge|ohook|microsoft[._ -]+toolkit)')
    $knownPatternVariable = Get-Variable -Name ToolSoftwareKnownActivatorPattern -Scope Script -ErrorAction SilentlyContinue
    $suspiciousPatternVariable = Get-Variable -Name ToolSoftwareSuspiciousArtifactPattern -Scope Script -ErrorAction SilentlyContinue
    if ($knownPatternVariable -and [string]$knownPatternVariable.Value -and $artifactName -match [string]$knownPatternVariable.Value) { $nameMatched = $true }
    if ($suspiciousPatternVariable -and [string]$suspiciousPatternVariable.Value -and $artifactName -match [string]$suspiciousPatternVariable.Value) { $nameMatched = $true }
    if (-not $nameMatched) { return $false }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $false }
        $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    } catch { return $false }

    $backupRoot = if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_DATA_ROOT)) {
        Join-Path ([string]$env:TOOL_DATA_ROOT) 'backups'
    } else {
        $commonData = [Environment]::GetFolderPath('CommonApplicationData')
        if ($commonData) { Join-Path $commonData 'ThanhViet-VietLicenSure\v4.6\backups' } else { '' }
    }
    if ($backupRoot) {
        try {
            $backupPrefix = ([IO.Path]::GetFullPath($backupRoot)).TrimEnd('\') + '\'
            if ($fullPath.StartsWith($backupPrefix, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        } catch {}
    }
    foreach ($application in @($Applications)) {
        $root = Get-ThirdPartyNormalizedInstallRoot -Application $application
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $prefix = $root.TrimEnd('\') + '\'
        if ($fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    if ($AllowUserArtifactRoots) {
        $userArtifactRoots = @(
            $env:TEMP, $env:TMP, $env:LOCALAPPDATA, $env:APPDATA,
            [Environment]::GetFolderPath('Desktop'),
            $(if ([Environment]::GetFolderPath('UserProfile')) { Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads' })
        ) | Where-Object { $_ } | Select-Object -Unique
        foreach ($root in $userArtifactRoots) {
            try {
                $prefix = ([IO.Path]::GetFullPath([string]$root)).TrimEnd('\') + '\'
                if ($fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
            } catch {}
        }
        try {
            $usersRoot = (Join-Path $env:SystemDrive 'Users').TrimEnd('\') + '\'
            if ($fullPath.StartsWith($usersRoot, [StringComparison]::OrdinalIgnoreCase) -and
                $fullPath -match '(?i)\\Users\\[^\\]+\\(?:Downloads|Desktop|AppData\\Local|AppData\\Roaming)\\') { return $true }
        } catch {}
    }
    return $false
}

function Get-ThirdPartyArtifactExecutionIdentity {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $null }
        $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
        $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        if ($hash -notmatch '^[0-9A-F]{64}$') { return $null }
        return [pscustomobject][ordered]@{
            Path=$fullPath; Length=[int64]$item.Length; Sha256=$hash
        }
    } catch { return $null }
}

function Test-ThirdPartyArtifactExecutionIdentity {
    param([AllowNull()][object]$Candidate)
    if ($null -eq $Candidate -or [string]$Candidate.Type -ne 'File' -or [string]$Candidate.Kind -ne 'ThirdPartyUnauthorizedArtifact') { return $false }
    if (-not ($Candidate.PSObject.Properties['ExpectedSha256'] -and $Candidate.PSObject.Properties['ExpectedLength'])) { return $false }
    $expectedHash = [string]$Candidate.ExpectedSha256
    $expectedLength = [int64]$Candidate.ExpectedLength
    if ($expectedHash -notmatch '^[0-9A-F]{64}$' -or $expectedLength -lt 0) { return $false }
    $current = Get-ThirdPartyArtifactExecutionIdentity -Path ([string]$Candidate.Location)
    if ($null -eq $current) { return $false }
    return [bool]($current.Sha256 -eq $expectedHash -and [int64]$current.Length -eq $expectedLength)
}

function Test-ThirdPartyApplicationPathScope {
    param([string]$Path, $Applications)
    if ([string]::IsNullOrWhiteSpace($Path) -or ([IO.Path]::GetExtension($Path)).ToLowerInvariant() -notin @('.exe','.com')) { return $false }
    try {
        $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $false }
        $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    } catch { return $false }
    foreach ($application in @($Applications)) {
        $representativePath = [string]$application.RepresentativePath
        if ($representativePath) {
            try {
            if ([string]::Equals($fullPath, [IO.Path]::GetFullPath($representativePath), [StringComparison]::OrdinalIgnoreCase)) { return $true }
            } catch {}
        }
        $root = Get-ThirdPartyNormalizedInstallRoot -Application $application
        if ($root -and $fullPath.StartsWith(($root.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-ThirdPartyHostsUpdate {
    param([string[]]$Lines, [string[]]$Targets)
    $targetSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($target in @($Targets)) {
        $normalized = ([string]$target).Trim().TrimEnd('.')
        if ($normalized -match '^[A-Za-z0-9.-]{1,253}$') { [void]$targetSet.Add($normalized) }
    }
    $updatedLines = New-Object System.Collections.Generic.List[string]
    $removedCount = 0
    foreach ($line in @($Lines)) {
        $commentIndex = ([string]$line).IndexOf('#')
        $comment = if ($commentIndex -ge 0) { ([string]$line).Substring($commentIndex) } else { '' }
        $mappings = @(Get-ToolSoftwareHostsLineMappings -Line ([string]$line))
        if ($mappings.Count -eq 0) {
            $updatedLines.Add([string]$line)
            continue
        }
        $rebuiltMappings = New-Object System.Collections.Generic.List[string]
        $lineRemovedCount = 0
        foreach ($mapping in $mappings) {
            $kept = New-Object System.Collections.Generic.List[string]
            foreach ($name in @($mapping.Targets)) {
                if ($targetSet.Contains(([string]$name).TrimEnd('.'))) {
                    $lineRemovedCount++
                } else {
                    $kept.Add([string]$name)
                }
            }
            if ($kept.Count -gt 0) { $rebuiltMappings.Add(([string]$mapping.Address + "`t" + ($kept.ToArray() -join ' '))) }
        }
        if ($lineRemovedCount -eq 0) {
            $updatedLines.Add([string]$line)
            continue
        }
        $removedCount += $lineRemovedCount
        if ($rebuiltMappings.Count -gt 0) {
            for ($mappingIndex = 0; $mappingIndex -lt $rebuiltMappings.Count; $mappingIndex++) {
                $rebuilt = [string]$rebuiltMappings[$mappingIndex]
                if ($comment -and $mappingIndex -eq ($rebuiltMappings.Count - 1)) { $rebuilt += ' ' + $comment }
                $updatedLines.Add($rebuilt)
            }
        } elseif ($comment) {
            $updatedLines.Add([string]$comment)
        }
    }
    return [pscustomobject][ordered]@{
        Lines=$updatedLines.ToArray(); RemovedCount=[int]$removedCount; TargetCount=[int]$targetSet.Count
    }
}

function Get-ThirdPartyGenericRemediationPlan {
    param($Applications, [switch]$ManualArtifactQuarantineOnly)
    $plan = New-Object System.Collections.Generic.List[object]
    $allEvidence = @($Applications | ForEach-Object { @($_.Evidence) } | Where-Object {
        (Get-ToolSoftwareEvidenceCorrelationLevel -Evidence $_) -eq 'Direct'
    } |
        Group-Object {
            $evidenceLocation = if ($_.PSObject.Properties['Location'] -and -not [string]::IsNullOrWhiteSpace([string]$_.Location)) {
                [string]$_.Location
            } else {
                [string]$_.Detail
            }
            "$($_.Code)|$($_.Source)|$evidenceLocation"
        } | ForEach-Object { $_.Group[0] })

    foreach ($item in $allEvidence) {
        $code = [string]$item.Code
        $detail = if ($item.PSObject.Properties['Location'] -and -not [string]::IsNullOrWhiteSpace([string]$item.Location)) {
            [string]$item.Location
        } else {
            [string]$item.Detail
        }
        if ($code -in @('UnauthorizedArtifactName','KnownActivatorArtifact','SuspiciousArtifactName','KnownActivatorFileArtifact','SuspiciousActivatorFileArtifact') -and
            (Test-ThirdPartyArtifactPath -Path $detail -Applications $Applications -AllowUserArtifactRoots)) {
            $artifactIdentity = Get-ThirdPartyArtifactExecutionIdentity -Path $detail
            if ($artifactIdentity) {
                $plan.Add([pscustomobject][ordered]@{
                    Type='File'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[IO.Path]::GetFileName([string]$artifactIdentity.Path)
                    Location=[string]$artifactIdentity.Path; Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.quarantineArtifact'); Restorable=$false
                    ExpectedSha256=[string]$artifactIdentity.Sha256; ExpectedLength=[int64]$artifactIdentity.Length
                })
            }
        } elseif (-not $ManualArtifactQuarantineOnly -and $code -eq 'LicenseDomainBlocked' -and $detail -match '^[A-Za-z0-9.-]{1,253}$') {
            $plan.Add([pscustomobject][ordered]@{
                Type='Hosts'; Kind='ThirdPartyHostsEntry'; Name=$detail; Location=$detail
                Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.restoreHosts'); Restorable=$true
            })
        } elseif (-not $ManualArtifactQuarantineOnly -and $code -eq 'ApplicationOutboundBlocked' -and $detail -match '^(.+?)\s+\|\s+(.+)$') {
            $ruleName = ([string]$matches[1]).Trim()
            $applicationPath = ([string]$matches[2]).Trim()
            if ($ruleName.Length -le 256 -and (Test-ThirdPartyApplicationPathScope -Path $applicationPath -Applications $Applications)) {
                $plan.Add([pscustomobject][ordered]@{
                    Type='Guidance'; Kind='ThirdPartyFirewallManualReview'; Name=$ruleName; Location=$applicationPath
                    Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.removeFirewallBlock'); Restorable=$false
                })
            }
        }
    }

    if ($ManualArtifactQuarantineOnly) {
        # This mode is deliberately file-only.  It is used for a Suspicious
        # application with a direct exact artifact, never for its license
        # store, hosts entries, services, tasks, registry, or installer.
        return @($plan.ToArray() |
            Group-Object { "$($_.Type)|$($_.Kind)|$($_.Name)|$($_.Location)" } |
            ForEach-Object { $_.Group[0] })
    }

    $hasUnauthorizedDistribution = [bool](@($allEvidence | Where-Object { [string]$_.Code -in @('KnownUnauthorizedName','CatalogUnauthorizedName') }).Count -gt 0)
    $displayName = @($Applications | Sort-Object @{Expression={ if ([string]$_.SourceKind -eq 'Registry') { 0 } else { 1 } }} | ForEach-Object { [string]$_.Name } | Where-Object { $_ } | Select-Object -First 1)
    if ($displayName.Count -eq 0) { $displayName = @((Get-CleanupText 'common.unknown')) }
    # Không chạy MSI Repair tự động cho phần mềm bên thứ ba. Nguồn cài đặt đã
    # đăng ký có thể đã bị thay thế hoặc không còn cùng bản với lúc quét, nên
    # việc sửa chỉ được hướng dẫn thủ công từ nguồn chính thức của hãng.

    $officialUrl = @($Applications | ForEach-Object { [string]$_.OfficialReferenceUrl } | Where-Object { $_ } | Select-Object -First 1)
    $plan.Add([pscustomobject][ordered]@{
        Type='Guidance'; Kind='ThirdPartyOfficialSource'; Name=[string]$displayName[0]
        Location=$(if ($officialUrl.Count -gt 0) { [string]$officialUrl[0] } else { '' })
        Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.officialSource'); Restorable=$false
    })
    return @($plan.ToArray() |
        Group-Object { "$($_.Type)|$($_.Kind)|$($_.Name)|$($_.Location)" } |
        ForEach-Object { $_.Group[0] })
}

function Test-ThirdPartyApplicationManualArtifactQuarantineEligible {
    param([AllowNull()][object]$Application)
    if ($null -eq $Application) { return $false }
    if ([bool]($Application.PSObject.Properties['IsSystemComponent'] -and [bool]$Application.IsSystemComponent)) { return $false }
    if ($Application.PSObject.Properties['Confidence'] -and [string]$Application.Confidence -eq 'Low') { return $false }
    if (-not ($Application.PSObject.Properties['ManualArtifactQuarantineAllowed'] -and [bool]$Application.ManualArtifactQuarantineAllowed)) { return $false }
    if (-not ($Application.PSObject.Properties['AssessmentCode'] -and [string]$Application.AssessmentCode -eq 'Suspicious')) { return $false }
    if (-not ($Application.PSObject.Properties['LicenseTechnicalState'] -and [string]$Application.LicenseTechnicalState -eq 'Suspicious')) { return $false }
    if ($Application.PSObject.Properties['ArtifactCleanupAllowed'] -and [bool]$Application.ArtifactCleanupAllowed) { return $false }

    $artifactCodes = @(
        'UnauthorizedArtifactName','KnownActivatorArtifact','SuspiciousArtifactName',
        'KnownActivatorFileArtifact','SuspiciousActivatorFileArtifact'
    )
    $directArtifactEvidence = @($Application.Evidence | Where-Object {
        (Get-ToolSoftwareEvidenceCorrelationLevel -Evidence $_) -eq 'Direct' -and
        [string]$_.Code -in $artifactCodes -and
        [string]$_.Strength -in @('Conclusive','Strong','Moderate') -and
        -not [string]::IsNullOrWhiteSpace($(if ($_.PSObject.Properties['Location']) { [string]$_.Location } else { [string]$_.Detail }))
    })
    return [bool]($directArtifactEvidence.Count -gt 0)
}

function Test-ThirdPartyApplicationCleanupEligible {
    param([AllowNull()][object]$Application)
    if ($null -eq $Application) { return $false }
    if ([bool]($Application.PSObject.Properties['IsSystemComponent'] -and [bool]$Application.IsSystemComponent)) { return $false }
    if ($Application.PSObject.Properties['Confidence'] -and [string]$Application.Confidence -eq 'Low') { return $false }
    if (Test-ThirdPartyApplicationManualArtifactQuarantineEligible -Application $Application) { return $true }
    if ($Application.PSObject.Properties['ArtifactCleanupAllowed'] -and [bool]$Application.ArtifactCleanupAllowed) { return $true }
    if ($Application.PSObject.Properties['RecoveryGate'] -and $Application.RecoveryGate) {
        return [bool]$Application.RecoveryGate.ArtifactCleanupAllowed
    }
    $adapter = if ($Application.PSObject.Properties['RemediationAdapter']) { [string]$Application.RemediationAdapter } else { '' }
    $technicalState = if ($Application.PSObject.Properties['LicenseTechnicalState']) { [string]$Application.LicenseTechnicalState } else { '' }
    $applicationEvidence = if ($Application.PSObject.Properties['Evidence']) { @($Application.Evidence) } else { @() }
    $isSystemComponent = [bool]($Application.PSObject.Properties['IsSystemComponent'] -and [bool]$Application.IsSystemComponent)
    $gate = Get-ToolSoftwareRecoveryGate -TechnicalState $technicalState -Evidence $applicationEvidence `
        -IsSystemComponent:$isSystemComponent -RemediationAdapter $adapter
    return [bool]$gate.ArtifactCleanupAllowed
}

function Test-ThirdPartyApplicationGuidedRemediationEligible {
    param([AllowNull()][object]$Application)

    # Guidance selection is deliberately separate from a local remediation
    # gate.  It can never authorize file, registry, task, service, licence, or
    # uninstall work; it only persists the exact official/manual next step in
    # the reviewed plan.
    if ($null -eq $Application) { return $false }
    if ([bool]($Application.PSObject.Properties['IsSystemComponent'] -and [bool]$Application.IsSystemComponent)) { return $false }
    if (-not ($Application.PSObject.Properties['GuidedRemediationSupported'] -and [bool]$Application.GuidedRemediationSupported)) { return $false }
    $licenseModel = if ($Application.PSObject.Properties['LicenseModel']) { [string]$Application.LicenseModel } else { 'Unknown' }
    if ($licenseModel -in @('Paid','Subscription','Trial','Unknown')) { return $true }
    $assessmentCode = [string]$Application.AssessmentCode
    if ($assessmentCode -in @('NonGenuine','Suspicious')) { return $true }
    # Defense in depth for callers that pass a deserialized assessment rather
    # than an in-process inventory row: an integrity-only result may be guided
    # only when the inventory explicitly preserved a separate remediation
    # evidence count.  A signature issue by itself never authorizes even the
    # guided-cleanup queue.
    return [bool]($assessmentCode -eq 'IntegrityCompromised' -and
        $Application.PSObject.Properties['RemediationEvidenceCount'] -and
        [int]$Application.RemediationEvidenceCount -gt 0)
}

function Get-ThirdPartyManualUninstallPlan {
    param([AllowNull()][object]$Application)
    $plan = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Application -or [bool]($Application.PSObject.Properties['IsSystemComponent'] -and [bool]$Application.IsSystemComponent)) {
        return $plan.ToArray()
    }
    $sourceBoundIdentities = if ($Application.PSObject.Properties['SourceBoundUninstallIdentities']) {
        @($Application.SourceBoundUninstallIdentities)
    } else { @() }
    foreach ($identity in $sourceBoundIdentities) {
        $sourceKind = [string]$identity.SourceKind
        if ($sourceKind -eq 'Registry') {
            $registryPath = [string]$identity.RegistryPath
            $uninstallString = [string]$identity.UninstallString
            $match = [regex]::Match($uninstallString, '(?i)(?:^|[\\\s"])(?:msiexec(?:\.exe)?)\s+(?:/i|/x)\s*"?(\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\})"?')
            if (-not $match.Success -or [string]::IsNullOrWhiteSpace($registryPath)) { continue }
            $productCode = $match.Groups[1].Value.ToUpperInvariant()
            $plan.Add([pscustomobject][ordered]@{
                Type='Uninstall'; Kind='ThirdPartyCompleteUninstall'; Name=[string]$Application.Name
                Location=$registryPath; Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.completeUninstall')
                Restorable=$false; ManualUninstallAllowed=$true; UninstallMethod='MSI'
                UninstallIdentity=$productCode; UninstallRegistryPath=$registryPath; UninstallPackageId=''
                ExpectedName=[string]$identity.Name; ExpectedVersion=[string]$identity.Version
                ExpectedPublisher=[string]$identity.Publisher; InstallRoot=[string]$identity.InstallLocation
            })
        } elseif ($sourceKind -eq 'Appx') {
            $packageFullName = [string]$identity.PackageFullName
            if ([string]::IsNullOrWhiteSpace($packageFullName) -or $packageFullName -notmatch '^[A-Za-z0-9._-]+$') { continue }
            $plan.Add([pscustomobject][ordered]@{
                Type='Uninstall'; Kind='ThirdPartyCompleteUninstall'; Name=[string]$Application.Name
                Location=$packageFullName; Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.completeUninstall')
                Restorable=$false; ManualUninstallAllowed=$true; UninstallMethod='Appx'
                UninstallIdentity=$packageFullName; UninstallRegistryPath=''; UninstallPackageId=$packageFullName
                ExpectedName=[string]$identity.Name; ExpectedVersion=[string]$identity.Version
                ExpectedPublisher=[string]$identity.Publisher; InstallRoot=[string]$identity.InstallLocation
            })
        }
    }
    return @($plan.ToArray() | Group-Object { ([string]$_.UninstallMethod + '|' + [string]$_.UninstallIdentity).ToLowerInvariant() } | ForEach-Object { $_.Group[0] })
}

function Get-ThirdPartyLicenseCandidates {
    param($Applications, $Evidence)
    $candidates = New-Object System.Collections.Generic.List[object]
    $adapterDefinitions = @(
        [pscustomobject]@{ Adapter='Adobe'; EvidenceScope='Adobe'; Mode='ArtifactCleanupOnly' },
        [pscustomobject]@{ Adapter='Autodesk'; EvidenceScope='Autodesk'; Mode='ArtifactCleanupOnly' },
        [pscustomobject]@{ Adapter='WinRAR'; EvidenceScope='RARLAB'; Mode='ArtifactCleanupOnly' }
    )
    foreach ($adapterDefinition in $adapterDefinitions) {
        $adapter = [string]$adapterDefinition.Adapter
        $vendorScope = [string]$adapterDefinition.EvidenceScope
        $vendorFamilyApps = @($Applications | Where-Object { [string]$_.RemediationAdapter -eq $adapter })
        $vendorApps = @($vendorFamilyApps | Where-Object {
            [string]$_.RemediationAdapter -eq $adapter -and
            (Test-ThirdPartyApplicationCleanupEligible -Application $_) -and
            -not (Test-ThirdPartyApplicationManualArtifactQuarantineEligible -Application $_)
        })
        if ($vendorApps.Count -eq 0) { continue }
        $vendorApplicationIds = @($vendorApps | ForEach-Object { [string]$_.Id } | Where-Object { $_ } | Select-Object -Unique)
        $vendorEvidence = @($Evidence | Where-Object {
            [string]$_.VendorScope -eq $vendorScope -and
            (Get-ToolSoftwareEvidenceCorrelationLevel -Evidence $_) -eq 'Direct' -and
            $vendorApplicationIds -contains [string]$_.ApplicationId
        })
        $licenseStateResetAllowed = $false
        $preserveVendorLicenseState = $true
        $plan = @(Get-ThirdPartyRemediationPlan -RemediationAdapter $adapter -EvidenceScope $vendorScope -Evidence $vendorEvidence -Applications $vendorApps -PreserveVendorLicenseState:$preserveVendorLicenseState)
        if ($plan.Count -eq 0) { continue }
        if (@($plan | Where-Object { [string]$_.Type -ne 'Guidance' }).Count -eq 0) { continue }
        $licenseStateCount = @($plan | Where-Object { [string]$_.Kind -eq 'ThirdPartyLicenseState' }).Count
        $applicationNames = @($vendorApps | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
        $familyName = if ($adapter -in @('Adobe','Autodesk')) {
            Get-CleanupText ("cleanupReport.thirdParty.family." + $adapter.ToLowerInvariant())
        } else {
            [string]($applicationNames | Select-Object -First 1)
        }
        $strongEvidenceCount = [int](($vendorApps | Measure-Object -Property StrongEvidenceCount -Sum).Sum)
        $manualOnlyCount = [int]@($vendorApps | Where-Object { -not [bool]$_.AutoEligible }).Count
        $remediationMode = 'ArtifactCleanupOnly'
        $candidate = New-CleanupItem -Type 'Application' -Kind 'ThirdPartyLicenseReset' -Name $familyName `
            -Location ($applicationNames -join '; ') -TargetId $adapter `
            -Detail (Get-CleanupText "cleanupReport.thirdParty.candidateDetailExtended" @($vendorApps.Count, $strongEvidenceCount, $manualOnlyCount, $licenseStateCount)) `
            -DefaultSelected $false -VendorScope $vendorScope -AutoEligible:$false `
            -ApplicationNames $applicationNames -ApplicationIds @($vendorApps | ForEach-Object { [string]$_.Id }) `
            -Evidence $vendorEvidence -PlanItems $plan -RemediationMode $remediationMode -ComponentScope 'ThirdParty' `
            -ArtifactCleanupAllowed $true -LicenseStateResetAllowed $licenseStateResetAllowed -RecoveryMode $remediationMode
        $candidates.Add($candidate)
    }

    $genericApplications = @($Applications | Where-Object {
        $manualArtifactOnly = Test-ThirdPartyApplicationManualArtifactQuarantineEligible -Application $_
        (Test-ThirdPartyApplicationCleanupEligible -Application $_) -and
        ($manualArtifactOnly -or [string]$_.RemediationAdapter -notin @('Adobe','Autodesk','WinRAR'))
    })
    $genericGroups = @($genericApplications | Group-Object {
        if (Test-ThirdPartyApplicationManualArtifactQuarantineEligible -Application $_) {
            # A manual suspicious artifact is deliberately one application at a
            # time, even when multiple products share a vendor or install root.
            return ('manual-artifact|' + [string]$_.Id).ToLowerInvariant()
        }
        $root = Get-ThirdPartyNormalizedInstallRoot -Application $_
        if ($root) { return (([string]$_.VendorScope) + '|' + $root).ToLowerInvariant() }
        return (([string]$_.VendorScope) + '|' + ([string]$_.Id)).ToLowerInvariant()
    })
    foreach ($group in $genericGroups) {
        $groupApplications = @($group.Group)
        $manualArtifactQuarantineOnly = [bool]($groupApplications.Count -gt 0 -and
            @($groupApplications | Where-Object { Test-ThirdPartyApplicationManualArtifactQuarantineEligible -Application $_ }).Count -eq $groupApplications.Count)
        $plan = @(Get-ThirdPartyGenericRemediationPlan -Applications $groupApplications -ManualArtifactQuarantineOnly:$manualArtifactQuarantineOnly)
        $manualFilePlan = @($plan | Where-Object { [string]$_.Type -eq 'File' -and [string]$_.Kind -eq 'ThirdPartyUnauthorizedArtifact' })
        if ($manualArtifactQuarantineOnly -and $manualFilePlan.Count -eq 0) {
            # The assessment may be based on a file that disappeared or moved
            # after scan.  Do not create a selectable candidate in that case.
            continue
        }
        $applicationNames = @($groupApplications | ForEach-Object { [string]$_.Name } | Where-Object { $_ } | Sort-Object -Unique)
        $applicationIds = @($groupApplications | ForEach-Object { [string]$_.Id } | Where-Object { $_ } | Select-Object -Unique)
        $allEvidence = @($groupApplications | ForEach-Object { @($_.Evidence) } | Where-Object {
            (Get-ToolSoftwareEvidenceCorrelationLevel -Evidence $_) -eq 'Direct'
        } |
            Group-Object { "$($_.Code)|$($_.Source)|$($_.Detail)" } | ForEach-Object { $_.Group[0] })
        $strongEvidenceCount = [int]@($allEvidence | Where-Object { [string]$_.Strength -in @('Conclusive','Strong') }).Count
        $decisiveEvidenceCount = [int]@($allEvidence | Where-Object {
            if ($_.PSObject.Properties['Decisive']) { return [bool]$_.Decisive -or [string]$_.Strength -eq 'Conclusive' }
            return [bool]([string]$_.Strength -eq 'Conclusive' -or
                [string]$_.Code -in @('SignatureHashMismatch','DeepSignatureHashMismatch','KnownBadFileHash','KnownActivatorArtifact'))
        }).Count
        $hasSafeAutomaticAction = [bool](@($plan | Where-Object { [string]$_.Type -in @('File','Hosts') }).Count -gt 0)
        if (-not $hasSafeAutomaticAction) {
            # The app is added below as a single guidance-only candidate.  Do
            # not retain a second, misleading Application candidate that has
            # no permitted local action.
            continue
        }
        $hasUnauthorizedDistribution = [bool](@($allEvidence | Where-Object { [string]$_.Code -in @('KnownUnauthorizedName','CatalogUnauthorizedName') }).Count -gt 0)
        $mode = if ($manualArtifactQuarantineOnly) { 'ManualArtifactQuarantine' } elseif ($hasUnauthorizedDistribution) { 'ManualOfficialReinstall' } elseif ($hasSafeAutomaticAction) { 'ArtifactCleanup' } else { 'GuidedOfficialRepair' }
        $displayName = if ($applicationNames.Count -le 1) { [string]$applicationNames[0] } else { ([string]$applicationNames[0] + ' (+' + ($applicationNames.Count - 1) + ')') }
        $location = @($groupApplications | ForEach-Object { Get-ThirdPartyNormalizedInstallRoot -Application $_ } | Where-Object { $_ } | Select-Object -First 1)
        $candidate = New-CleanupItem -Type 'Application' -Kind 'ThirdPartyLicenseReset' -Name $displayName `
            -Location $(if ($location.Count -gt 0) { [string]$location[0] } else { $applicationNames -join '; ' }) `
            -TargetId $(if ($applicationIds.Count -gt 0) { [string]$applicationIds[0] } else { [guid]::NewGuid().ToString('N') }) `
            -Detail (Get-CleanupText 'cleanupReport.thirdParty.candidateDetailGeneric' @($applicationNames.Count, $strongEvidenceCount, @($plan).Count, $mode)) `
            -DefaultSelected $false -VendorScope ([string]$groupApplications[0].VendorScope) `
            -AutoEligible:$false `
            -ApplicationNames $applicationNames -ApplicationIds $applicationIds -Evidence $allEvidence -PlanItems $plan -RemediationMode $mode -ComponentScope 'ThirdParty' `
            -ArtifactCleanupAllowed $(if ($manualArtifactQuarantineOnly) { $manualFilePlan.Count -gt 0 } else { $true }) `
            -LicenseStateResetAllowed $false -RecoveryMode $(if ($manualArtifactQuarantineOnly) { 'ManualArtifactQuarantine' } else { 'ArtifactCleanupOnly' }) `
            -ManualArtifactQuarantineOnly:$manualArtifactQuarantineOnly
        $candidates.Add($candidate)
    }

    # Keep suspicious rows selectable even when no exact artifact survived
    # revalidation.  The candidate is guidance-only: it records an official
    # repair/reinstall route and is intentionally incapable of changing the
    # machine.  A direct candidate wins whenever one exists for the app.
    foreach ($application in @($Applications | Where-Object {
        Test-ThirdPartyApplicationGuidedRemediationEligible -Application $_
    })) {
        $applicationId = [string]$application.Id
        $hasDirectCandidate = [bool](@($candidates.ToArray() | Where-Object {
            -not ([bool]($_.PSObject.Properties['GuidanceOnly'] -and [bool]$_.GuidanceOnly)) -and
            @($_.ApplicationIds) -contains $applicationId -and
            @((Get-ThirdPartyCandidateSafePlan -Candidate $_) | Where-Object { [string]$_.Type -ne 'Guidance' }).Count -gt 0
        }).Count -gt 0)
        if ($hasDirectCandidate) { continue }

        $officialUrl = if ($application.PSObject.Properties['OfficialReferenceUrl']) { [string]$application.OfficialReferenceUrl } else { '' }
        $officialUri = $null
        $hasOfficialSource = [Uri]::TryCreate($officialUrl, [UriKind]::Absolute, [ref]$officialUri) -and
            $officialUri.Scheme -eq [Uri]::UriSchemeHttps
        if (-not $hasOfficialSource) { $officialUrl = '' }
        $guidanceKind = if ($hasOfficialSource) { 'ThirdPartyOfficialSource' } else { 'ThirdPartyManualReview' }
        $guidanceMode = if ($hasOfficialSource) { 'GuidedOfficialRepair' } else { 'GuidedManualReview' }
        $displayName = if ([string]::IsNullOrWhiteSpace([string]$application.Name)) { Get-CleanupText 'common.unknown' } else { [string]$application.Name }
        $planItem = [pscustomobject][ordered]@{
            Type='Guidance'; Kind=$guidanceKind; Name=$displayName; Location=$officialUrl
            Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.officialSource'); Restorable=$false
        }
        $candidate = New-CleanupItem -Type 'Application' -Kind 'ThirdPartyGuidedRemediation' -Name $displayName `
            -Location $(if ($application.InstallLocation) { [string]$application.InstallLocation } else { [string]$application.Publisher }) `
            -TargetId $applicationId -Detail (Get-CleanupText 'cleanupReport.thirdParty.candidateDetailGuidance' @($guidanceMode)) `
            -DefaultSelected $false -VendorScope ([string]$application.VendorScope) -AutoEligible:$false `
            -ApplicationNames @($displayName) -ApplicationIds @($applicationId) -Evidence @($application.Evidence) `
            -PlanItems @($planItem) -RemediationMode $guidanceMode -ComponentScope 'ThirdParty' `
            -ArtifactCleanupAllowed $false -LicenseStateResetAllowed $false -RecoveryMode $guidanceMode `
            -GuidanceOnly $true -GuidanceReason (Get-CleanupText 'cleanupReport.thirdParty.guidanceOnlyReason') `
            -IdentitySeed ('guided|' + $applicationId)
        $candidates.Add($candidate)
    }

    # Complete removal is a separate, never-preselected operation. It is
    # offered only when inventory retained an exact source-bound MSI or Appx
    # identity; the elevated executor re-reads that identity before mutation.
    foreach ($application in @($Applications | Where-Object {
        Test-ThirdPartyApplicationGuidedRemediationEligible -Application $_
    })) {
        $uninstallPlan = @(Get-ThirdPartyManualUninstallPlan -Application $application)
        if ($uninstallPlan.Count -eq 0) { continue }
        $applicationId = [string]$application.Id
        $displayName = [string]$application.Name
        $methodText = @($uninstallPlan | ForEach-Object { [string]$_.UninstallMethod } | Select-Object -Unique) -join ', '
        $candidate = New-CleanupItem -Type 'Application' -Kind 'ThirdPartyCompleteUninstall' -Name $displayName `
            -Location $(if ($application.InstallLocation) { [string]$application.InstallLocation } else { [string]$application.Publisher }) `
            -TargetId $applicationId -Detail (Get-CleanupText 'cleanupReport.thirdParty.candidateCompleteUninstall' @($methodText)) `
            -DefaultSelected $false -VendorScope ([string]$application.VendorScope) -AutoEligible:$false `
            -ApplicationNames @($displayName) -ApplicationIds @($applicationId) -Evidence @($application.Evidence) `
            -PlanItems $uninstallPlan -RemediationMode 'ManualCompleteUninstall' -ComponentScope 'ThirdParty' `
            -ArtifactCleanupAllowed $true -LicenseStateResetAllowed $false -RecoveryMode 'ManualCompleteUninstall' `
            -ManualUninstallAllowed $true -InstallRoot ([string]$application.InstallLocation) `
            -IdentitySeed ('complete-uninstall|' + $applicationId)
        $candidates.Add($candidate)
    }

    # Tệp activator trong Downloads/Desktop/TEMP có thể không tương quan được
    # với một ứng dụng đã cài. Trước đây chúng xuất hiện trong kết quả quét
    # nhưng không có candidate, nên người dùng không thể chọn cách ly và lần
    # quét sau luôn thấy lại. Chỉ tạo candidate thủ công cho đúng một tệp đã
    # qua kiểm tra tên, phần mở rộng, đường dẫn chuẩn và vùng người dùng.
    $standaloneArtifactGroups = @($Evidence | Where-Object {
        [string]$_.Type -eq 'FileArtifact' -and
        [string]::IsNullOrWhiteSpace([string]$_.ApplicationId) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.Location)
    } | Group-Object { ([string]$_.Location).ToLowerInvariant() })
    foreach ($artifactGroup in $standaloneArtifactGroups) {
        $artifactEvidence = @($artifactGroup.Group)[0]
        $artifactPath = [string]$artifactEvidence.Location
        if (-not (Test-ThirdPartyArtifactPath -Path $artifactPath -Applications $Applications -AllowUserArtifactRoots)) { continue }
        $artifactIdentity = Get-ThirdPartyArtifactExecutionIdentity -Path $artifactPath
        if (-not $artifactIdentity) { continue }
        $artifactPath = [string]$artifactIdentity.Path
        $artifactName = [IO.Path]::GetFileName($artifactPath)
        $planItem = [pscustomobject][ordered]@{
            Type='File'; Kind='ThirdPartyUnauthorizedArtifact'; Name=$artifactName; Location=$artifactPath
            Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.quarantineArtifact'); Restorable=$false
            ExpectedSha256=[string]$artifactIdentity.Sha256; ExpectedLength=[int64]$artifactIdentity.Length
        }
        $candidate = New-CleanupItem -Type 'Application' -Kind 'ThirdPartyLicenseReset' -Name $artifactName `
            -Location $artifactPath -TargetId $artifactPath `
            -Detail (Get-CleanupText 'cleanupReport.thirdParty.candidateDetailStandalone' @($artifactName)) `
            -DefaultSelected $false -VendorScope 'Uncorrelated' -AutoEligible:$false `
            -ApplicationNames @($artifactName) -ApplicationIds @() -Evidence @($artifactGroup.Group) `
            -PlanItems @($planItem) -RemediationMode 'ArtifactCleanupOnly' -ComponentScope 'ThirdParty' `
            -ArtifactCleanupAllowed $true -LicenseStateResetAllowed $false -RecoveryMode 'ArtifactCleanupOnly'
        $candidates.Add($candidate)
    }
    return $candidates.ToArray()
}

function Connect-ThirdPartyApplicationsToCandidates {
    param($Applications, $Candidates)
    foreach ($application in @($Applications)) {
        $applicationId = [string]$application.Id
        $matchingCandidates = @($Candidates | Where-Object { @($_.ApplicationIds) -contains $applicationId })
        $applicationGateAllowed = [bool]($application.PSObject.Properties['ArtifactCleanupAllowed'] -and [bool]$application.ArtifactCleanupAllowed)
        $manualArtifactQuarantineAllowed = Test-ThirdPartyApplicationManualArtifactQuarantineEligible -Application $application
        $directCandidate = @($matchingCandidates | Where-Object {
            -not ([bool]($_.PSObject.Properties['GuidanceOnly'] -and [bool]$_.GuidanceOnly)) -and
            [string]$_.Kind -ne 'ThirdPartyCompleteUninstall' -and
            @((Get-ThirdPartyCandidateSafePlan -Candidate $_) | Where-Object { [string]$_.Type -ne 'Guidance' }).Count -gt 0 -and
            $_.PSObject.Properties['ArtifactCleanupAllowed'] -and [bool]$_.ArtifactCleanupAllowed -and
            $(if ($_.PSObject.Properties['ManualArtifactQuarantineOnly'] -and [bool]$_.ManualArtifactQuarantineOnly) {
                $manualArtifactQuarantineAllowed
            } else {
                $applicationGateAllowed
            })
        } | Select-Object -First 1)
        $guidanceCandidate = @($matchingCandidates | Where-Object {
            [bool]($_.PSObject.Properties['GuidanceOnly'] -and [bool]$_.GuidanceOnly)
        } | Select-Object -First 1)
        $completeUninstallCandidate = @($matchingCandidates | Where-Object {
            [string]$_.Kind -eq 'ThirdPartyCompleteUninstall' -and
            [bool]($_.PSObject.Properties['ManualUninstallAllowed'] -and [bool]$_.ManualUninstallAllowed)
        } | Select-Object -First 1)
        # Complete uninstall is an independent, explicit choice in the final
        # review.  It must not shadow the harmless guidance candidate attached
        # to a Paid/Subscription/Trial inventory row; doing so made those rows
        # grey and impossible to select whenever an MSI/Appx identity existed.
        # Keep the selected candidate wrapped as an array.  Without the outer
        # array PowerShell unwraps a single PSCustomObject here, making
        # `.Count` null below and silently disconnecting every otherwise valid
        # direct/manual candidate from the inventory row.
        $candidate = @(
            if ($directCandidate.Count -gt 0) { $directCandidate[0] }
            elseif ($guidanceCandidate.Count -gt 0) { $guidanceCandidate[0] }
        )
        $application.TechnicalStatus = Get-ThirdPartyAssessmentStatusLabel -StatusCode ([string]$application.AssessmentCode)
        $safePlan = if ($candidate.Count -gt 0) { @(Get-ThirdPartyCandidateSafePlan -Candidate $candidate[0]) } else { @() }
        $hasExecutablePlan = [bool](@($safePlan | Where-Object { [string]$_.Type -ne 'Guidance' }).Count -gt 0)
        $candidateGateAllowed = [bool]($candidate.Count -gt 0 -and $candidate[0].PSObject.Properties['ArtifactCleanupAllowed'] -and [bool]$candidate[0].ArtifactCleanupAllowed)
        $candidateManualArtifactQuarantineOnly = [bool]($candidate.Count -gt 0 -and $candidate[0].PSObject.Properties['ManualArtifactQuarantineOnly'] -and [bool]$candidate[0].ManualArtifactQuarantineOnly)
        $matchingGate = [bool](($applicationGateAllowed -and -not $candidateManualArtifactQuarantineOnly) -or
            ($manualArtifactQuarantineAllowed -and $candidateManualArtifactQuarantineOnly))
        $supported = [bool]($candidate.Count -gt 0 -and $matchingGate -and $candidateGateAllowed -and $hasExecutablePlan)
        $assessmentAutoEligible = [bool]$application.AutoEligible
        $application.RemediationSupported = $supported
        $application | Add-Member -NotePropertyName AssessmentAutoEligible -NotePropertyValue $assessmentAutoEligible -Force
        $application.AutoEligible = [bool]($candidate.Count -gt 0 -and [bool]$candidate[0].AutoEligible)
        $application | Add-Member -NotePropertyName CleanupCandidateId -NotePropertyValue $(if ($candidate.Count -gt 0) { [string]$candidate[0].Id } else { '' }) -Force
        $application | Add-Member -NotePropertyName CleanupGuidanceCandidateId -NotePropertyValue $(if ($guidanceCandidate.Count -gt 0) { [string]$guidanceCandidate[0].Id } else { '' }) -Force
        $application | Add-Member -NotePropertyName CleanupCompleteUninstallCandidateId -NotePropertyValue $(if ($completeUninstallCandidate.Count -gt 0) { [string]$completeUninstallCandidate[0].Id } else { '' }) -Force
        $application | Add-Member -NotePropertyName CleanupRemediationMode -NotePropertyValue $(if ($candidate.Count -gt 0) { [string]$candidate[0].RemediationMode } else { '' }) -Force
        $application | Add-Member -NotePropertyName CleanupArtifactCleanupAllowed -NotePropertyValue $candidateGateAllowed -Force
        $application | Add-Member -NotePropertyName CleanupLicenseStateResetAllowed -NotePropertyValue $(if ($candidate.Count -gt 0) {[bool]$candidate[0].LicenseStateResetAllowed} else {$false}) -Force
        $application | Add-Member -NotePropertyName CleanupManualArtifactQuarantineOnly -NotePropertyValue $candidateManualArtifactQuarantineOnly -Force
        $application | Add-Member -NotePropertyName GuidedRemediationSupported -NotePropertyValue ([bool]($guidanceCandidate.Count -gt 0)) -Force
        $application | Add-Member -NotePropertyName CleanupGuidanceOnly -NotePropertyValue ([bool]($candidate.Count -gt 0 -and $candidate[0].PSObject.Properties['GuidanceOnly'] -and [bool]$candidate[0].GuidanceOnly)) -Force
        $application | Add-Member -NotePropertyName CleanupGuidanceReason -NotePropertyValue $(if ($guidanceCandidate.Count -gt 0 -and $guidanceCandidate[0].PSObject.Properties['GuidanceReason']) {[string]$guidanceCandidate[0].GuidanceReason} else {''}) -Force
    }
}
