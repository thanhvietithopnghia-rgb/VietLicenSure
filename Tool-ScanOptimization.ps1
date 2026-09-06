$script:ToolScanOptimizationVersion = "1.1"
$script:ToolScanOptimizationToolVersion = "5.0"
$script:ToolScanMaximumRootCount = 8

function Get-ToolScanSettingsPath {
    [CmdletBinding()]
    param()

    $override = [string]$env:TOOL_SCAN_SETTINGS_PATH
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($override))
    }
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = [IO.Path]::GetTempPath() }
    return (Join-Path (Join-Path $localAppData "ThanhViet-VietLicenSure") "scan-settings.json")
}

function Test-ToolPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($candidate.Equals($boundary, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidate.StartsWith(($boundary + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-ToolLocalScanRoots {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]]$Roots = @(),
        [ValidateRange(1, 64)][int]$MaximumRoots = $script:ToolScanMaximumRootCount,
        [string]$ParameterName = "Roots"
    )

    $resolved = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($rawRoot in @($Roots)) {
        if ([string]::IsNullOrWhiteSpace([string]$rawRoot)) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables(([string]$rawRoot).Trim())
        $inputPathRoot = [IO.Path]::GetPathRoot($expanded)
        if ($expanded.StartsWith('\\', [StringComparison]::Ordinal) -or
            $expanded.StartsWith('//', [StringComparison]::Ordinal) -or
            -not [IO.Path]::IsPathRooted($expanded) -or
            [string]::IsNullOrWhiteSpace($inputPathRoot) -or
            (-not $inputPathRoot.EndsWith([string][IO.Path]::DirectorySeparatorChar) -and
             -not $inputPathRoot.EndsWith([string][IO.Path]::AltDirectorySeparatorChar))) {
            throw (New-Object ArgumentException("$ParameterName chỉ chấp nhận thư mục cục bộ có đường dẫn tuyệt đối: $rawRoot", $ParameterName))
        }

        try { $fullPath = [IO.Path]::GetFullPath($expanded) }
        catch { throw (New-Object ArgumentException("$ParameterName chứa đường dẫn không hợp lệ: $rawRoot", $ParameterName)) }
        if ($fullPath.StartsWith('\\', [StringComparison]::Ordinal) -or $fullPath.StartsWith('//', [StringComparison]::Ordinal)) {
            throw (New-Object ArgumentException("$ParameterName không cho phép UNC/network root: $rawRoot", $ParameterName))
        }

        $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or [string]$item.PSProvider.Name -ne 'FileSystem') {
            throw (New-Object ArgumentException("$ParameterName phải là thư mục cục bộ đang tồn tại: $rawRoot", $ParameterName))
        }

        $pathRoot = [IO.Path]::GetPathRoot([string]$item.FullName)
        try { $driveInfo = New-Object IO.DriveInfo($pathRoot) }
        catch { throw (New-Object ArgumentException("$ParameterName không nằm trên ổ đĩa cục bộ hợp lệ: $rawRoot", $ParameterName)) }
        if ($driveInfo.DriveType -eq [IO.DriveType]::Network -or $driveInfo.DriveType -eq [IO.DriveType]::NoRootDirectory) {
            throw (New-Object ArgumentException("$ParameterName không cho phép ổ mạng: $rawRoot", $ParameterName))
        }

        # Checking every ancestor also catches C:\junction\child, whose child
        # DirectoryInfo is not itself marked as a reparse point.
        $cursor = $item
        while ($null -ne $cursor) {
            if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw (New-Object ArgumentException("$ParameterName không cho phép junction/symlink/reparse point: $rawRoot", $ParameterName))
            }
            $cursor = $cursor.Parent
        }

        $canonical = [IO.Path]::GetFullPath([string]$item.FullName)
        if (-not $canonical.Equals($pathRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $canonical = $canonical.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        }
        if ($seen.Add($canonical)) {
            if ($resolved.Count -ge $MaximumRoots) {
                throw (New-Object ArgumentException("$ParameterName vượt quá giới hạn $MaximumRoots thư mục.", $ParameterName))
            }
            [void]$resolved.Add($canonical)
        }
    }
    return @($resolved.ToArray())
}

function Resolve-ToolScanPlan {
    [CmdletBinding()]
    param(
        [ValidateSet("Quick", "Standard", "Deep")][string]$Profile = "Standard",
        [switch]$LowResource,
        [AllowEmptyCollection()][string[]]$IncludedRoots = @(),
        [AllowEmptyCollection()][string[]]$ExcludedRoots = @()
    )

    $safeIncludedRoots = @(Resolve-ToolLocalScanRoots -Roots $IncludedRoots -ParameterName 'IncludedRoots')
    $safeExcludedRoots = @(Resolve-ToolLocalScanRoots -Roots $ExcludedRoots -ParameterName 'ExcludedRoots')
    foreach ($includedRoot in $safeIncludedRoots) {
        foreach ($excludedRoot in $safeExcludedRoots) {
            if (Test-ToolPathWithinRoot -Path $includedRoot -Root $excludedRoot) {
                throw (New-Object ArgumentException("IncludedRoots không thể nằm trong ExcludedRoots: $includedRoot", 'IncludedRoots'))
            }
        }
    }

    $budget = switch ($Profile) {
        "Quick" {
            [ordered]@{
                OfficeMaximumDepth=2; OfficeThrottleLimit=2; OfficeTimeoutSeconds=25
                IncludePortable=$false; IncludePackageManagers=$false; PortableMaximumResults=100; PortableMaximumDepth=2
                FileMaximumResults=20; FileThrottleLimit=2; FileMaximumDepth=2; PerRootTimeoutSeconds=6
                DeepAssessment=$false; DeepScanMaximumDurationSeconds=45; DeepScanMaximumSignatureChecks=100; DeepScanMaximumHashChecks=80
                CoverageComplete=$false; CoverageNote='Quick scan uses reduced depth, result caps, and timeouts; omitted or timed-out areas must not be treated as clean.'
            }
            break
        }
        "Deep" {
            [ordered]@{
                OfficeMaximumDepth=6; OfficeThrottleLimit=4; OfficeTimeoutSeconds=90
                IncludePortable=$true; IncludePackageManagers=$true; PortableMaximumResults=1000; PortableMaximumDepth=5
                FileMaximumResults=250; FileThrottleLimit=6; FileMaximumDepth=8; PerRootTimeoutSeconds=30
                DeepAssessment=$true; DeepScanMaximumDurationSeconds=360; DeepScanMaximumSignatureChecks=3000; DeepScanMaximumHashChecks=2000
                CoverageComplete=$false; CoverageNote='Deep scan uses the broadest profile, but remains bounded by selected roots, depth, result caps, per-root timeouts, and assessment budgets; omitted or timed-out areas must not be treated as clean.'
            }
            break
        }
        default {
            [ordered]@{
                OfficeMaximumDepth=3; OfficeThrottleLimit=3; OfficeTimeoutSeconds=45
                IncludePortable=$true; IncludePackageManagers=$true; PortableMaximumResults=350; PortableMaximumDepth=3
                FileMaximumResults=60; FileThrottleLimit=4; FileMaximumDepth=4; PerRootTimeoutSeconds=12
                DeepAssessment=$false; DeepScanMaximumDurationSeconds=180; DeepScanMaximumSignatureChecks=1400; DeepScanMaximumHashChecks=1000
                CoverageComplete=$false; CoverageNote='Standard scan preserves the v4.9 baseline, but remains bounded by selected roots, depth, result caps, per-root timeouts, and assessment budgets; omitted or timed-out areas must not be treated as clean.'
            }
        }
    }

    if ($LowResource) {
        $budget.OfficeThrottleLimit = 1
        $budget.FileThrottleLimit = 1
        switch ($Profile) {
            "Quick" {
                $budget.PortableMaximumResults=80; $budget.FileMaximumResults=15
                $budget.DeepScanMaximumDurationSeconds=30; $budget.DeepScanMaximumSignatureChecks=60; $budget.DeepScanMaximumHashChecks=40
            }
            "Deep" {
                $budget.PortableMaximumResults=600; $budget.FileMaximumResults=120
                $budget.DeepScanMaximumDurationSeconds=300; $budget.DeepScanMaximumSignatureChecks=1200; $budget.DeepScanMaximumHashChecks=800
            }
            default {
                $budget.PortableMaximumResults=220; $budget.FileMaximumResults=40
                $budget.DeepScanMaximumDurationSeconds=120; $budget.DeepScanMaximumSignatureChecks=600; $budget.DeepScanMaximumHashChecks=400
            }
        }
        $budget.CoverageComplete = $false
        $budget.CoverageNote = [string]$budget.CoverageNote + ' Low-resource mode reduces concurrency and evidence budgets.'
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = "1.0"
        OptimizationVersion = $script:ToolScanOptimizationVersion
        Profile = $Profile
        LowResource = [bool]$LowResource
        IncludedRoots = @($safeIncludedRoots)
        ExcludedRoots = @($safeExcludedRoots)
        OfficeMaximumDepth = [int]$budget.OfficeMaximumDepth
        OfficeThrottleLimit = [int]$budget.OfficeThrottleLimit
        OfficeTimeoutSeconds = [int]$budget.OfficeTimeoutSeconds
        IncludePortable = [bool]$budget.IncludePortable
        IncludePackageManagers = [bool]$budget.IncludePackageManagers
        PortableMaximumResults = [int]$budget.PortableMaximumResults
        PortableMaximumDepth = [int]$budget.PortableMaximumDepth
        FileMaximumResults = [int]$budget.FileMaximumResults
        FileThrottleLimit = [int]$budget.FileThrottleLimit
        FileMaximumDepth = [int]$budget.FileMaximumDepth
        PerRootTimeoutSeconds = [int]$budget.PerRootTimeoutSeconds
        DeepAssessment = [bool]$budget.DeepAssessment
        DeepScanMaximumDurationSeconds = [int]$budget.DeepScanMaximumDurationSeconds
        DeepScanMaximumSignatureChecks = [int]$budget.DeepScanMaximumSignatureChecks
        DeepScanMaximumHashChecks = [int]$budget.DeepScanMaximumHashChecks
        CoverageComplete = [bool]$budget.CoverageComplete
        CoverageNote = [string]$budget.CoverageNote
    }
}

function Get-ToolScanPreference {
    [CmdletBinding()]
    param()

    try {
        $settingsPath = Get-ToolScanSettingsPath
        if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
            $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $profile = [string]$settings.Profile
            if ($profile -notin @('Quick','Standard','Deep')) { throw 'Invalid saved scan profile.' }
            return (Resolve-ToolScanPlan -Profile $profile -LowResource:([bool]$settings.LowResource) `
                -IncludedRoots @($settings.IncludedRoots) -ExcludedRoots @($settings.ExcludedRoots))
        }
    } catch {}
    return (Resolve-ToolScanPlan -Profile Standard)
}

function Set-ToolScanPreference {
    [CmdletBinding()]
    param(
        [ValidateSet("Quick", "Standard", "Deep")][string]$Profile = "Standard",
        [switch]$LowResource,
        [AllowEmptyCollection()][string[]]$IncludedRoots = @(),
        [AllowEmptyCollection()][string[]]$ExcludedRoots = @()
    )

    # Validate before opening any file so an invalid network/reparse root is
    # never persisted and silently trusted by a later elevated process.
    $plan = Resolve-ToolScanPlan -Profile $Profile -LowResource:$LowResource `
        -IncludedRoots $IncludedRoots -ExcludedRoots $ExcludedRoots
    $settingsPath = ''
    $temporaryPath = ''
    $backupPath = ''
    try {
        $settingsPath = Get-ToolScanSettingsPath
        $settingsDirectory = Split-Path -Parent $settingsPath
        if (-not (Test-Path -LiteralPath $settingsDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
        }
        $temporaryPath = $settingsPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        $json = [pscustomobject][ordered]@{
            SchemaVersion = '1.0'
            Profile = [string]$plan.Profile
            LowResource = [bool]$plan.LowResource
            IncludedRoots = @($plan.IncludedRoots)
            ExcludedRoots = @($plan.ExcludedRoots)
        } | ConvertTo-Json -Depth 4
        [IO.File]::WriteAllText($temporaryPath, $json, (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
            $backupPath = $settingsPath + '.' + [Guid]::NewGuid().ToString('N') + '.bak'
            [IO.File]::Replace($temporaryPath, $settingsPath, $backupPath, $true)
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            $backupPath = ''
        } else {
            [IO.File]::Move($temporaryPath, $settingsPath)
        }
        return $true
    } catch {
        try {
            if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath -PathType Leaf)) {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            }
            if ($backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
                if ($settingsPath -and -not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
                    [IO.File]::Move($backupPath, $settingsPath)
                } else {
                    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {}
        return $false
    }
}

function Get-ToolOptimizedOfficeOsppPaths {
    [CmdletBinding()]
    param([ValidateRange(1, 6)][int]$MaximumDepth = 3)

    $result = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { [IO.Path]::GetFullPath([string]$_) } |
        Select-Object -Unique
    $knownRelativePaths = @(
        "Microsoft Office\Office16\OSPP.VBS",
        "Microsoft Office\root\Office16\OSPP.VBS",
        "Microsoft Office\Office15\OSPP.VBS",
        "Microsoft Office\root\Office15\OSPP.VBS",
        "Microsoft Office\Office14\OSPP.VBS",
        "Microsoft Office\root\Office14\OSPP.VBS"
    )

    foreach ($root in $roots) {
        foreach ($relativePath in $knownRelativePaths) {
            $candidate = Join-Path $root $relativePath
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
            $fullPath = [IO.Path]::GetFullPath($candidate)
            $key = $fullPath.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                [void]$result.Add($fullPath)
            }
        }

        $officeRoot = Join-Path $root "Microsoft Office"
        if (-not (Test-Path -LiteralPath $officeRoot -PathType Container)) { continue }
        $queue = New-Object "System.Collections.Generic.Queue[object]"
        $queue.Enqueue([pscustomobject]@{ Path=[IO.Path]::GetFullPath($officeRoot); Depth=0 })
        while ($queue.Count -gt 0) {
            $entry = $queue.Dequeue()
            try {
                $directoryInfo = New-Object IO.DirectoryInfo([string]$entry.Path)
                if (($directoryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                foreach ($file in @($directoryInfo.GetFiles("OSPP.VBS", [IO.SearchOption]::TopDirectoryOnly))) {
                    $fullPath = $file.FullName
                    $key = $fullPath.ToLowerInvariant()
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        [void]$result.Add($fullPath)
                    }
                }
                if ([int]$entry.Depth -ge $MaximumDepth) { continue }
                foreach ($child in @($directoryInfo.GetDirectories())) {
                    if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                        $queue.Enqueue([pscustomobject]@{ Path=$child.FullName; Depth=([int]$entry.Depth + 1) })
                    }
                }
            } catch {}
        }
    }
    return @($result.ToArray() | Sort-Object)
}

function Invoke-ToolParallelOfficeStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CscriptPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$OsppPaths,
        [ValidateRange(1, 8)][int]$ThrottleLimit = 3,
        [ValidateRange(15, 180)][int]$PerCommandTimeoutSeconds = 45
    )

    $paths = @($OsppPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique)
    if ($paths.Count -eq 0) { return @() }
    $pool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($ThrottleLimit, $paths.Count))
    $workers = New-Object System.Collections.Generic.List[object]
$workerScript = @'
param($NativeCscriptPath,$OsppPath,$CommandTimeoutSeconds)
function Invoke-BoundedCscript([string]$StatusArgument) {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $NativeCscriptPath
    $startInfo.Arguments = '//nologo "' + $OsppPath.Replace('"','') + '" ' + $StatusArgument
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'cscript.exe did not start.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit([int]($CommandTimeoutSeconds * 1000))
        if (-not $completed) {
            try { $process.Kill() } catch {}
            try { [void]$process.WaitForExit(3000) } catch {}
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        return [pscustomobject]@{
            Output = (($stdout + "`n" + $stderr).Trim())
            TimedOut = [bool](-not $completed)
            ExitCode = if ($completed) { [int]$process.ExitCode } else { -1 }
        }
    } finally {
        $process.Dispose()
    }
}

$primary = Invoke-BoundedCscript '/dstatusall'
$output = [string]$primary.Output
$usedFallback = $false
$fallbackExitCode = $null
if (-not $primary.TimedOut -and ([string]::IsNullOrWhiteSpace($output) -or $output -notmatch '(?im)^\s*(?:SKU ID|LICENSE NAME)\s*:')) {
    $fallback = Invoke-BoundedCscript '/dstatus'
    $output = [string]$fallback.Output
    $usedFallback = $true
    $timedOut = [bool]$fallback.TimedOut
    $fallbackExitCode = [int]$fallback.ExitCode
    $effectiveExitCode = [int]$fallback.ExitCode
} else {
    $timedOut = [bool]$primary.TimedOut
    $effectiveExitCode = [int]$primary.ExitCode
}
[pscustomobject][ordered]@{
    Path = $OsppPath
    Output = $output
    UsedFallback = $usedFallback
    TimedOut = $timedOut
    PrimaryExitCode = [int]$primary.ExitCode
    FallbackExitCode = $fallbackExitCode
    ExitCode = $effectiveExitCode
    Readable = [bool](-not $timedOut -and -not [string]::IsNullOrWhiteSpace($output) -and $output -match '(?im)^\s*(?:SKU ID|LICENSE NAME|LICENSE STATUS)\s*:')
}
'@

    try {
        $pool.Open()
        foreach ($path in $paths) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($workerScript).AddArgument($CscriptPath).AddArgument([string]$path).AddArgument($PerCommandTimeoutSeconds)
            $handle = $powerShell.BeginInvoke()
            [void]$workers.Add([pscustomobject]@{ PowerShell=$powerShell; Handle=$handle })
        }
        $result = New-Object System.Collections.Generic.List[object]
        foreach ($worker in $workers) {
            try {
                foreach ($item in @($worker.PowerShell.EndInvoke($worker.Handle))) {
                    if ($null -ne $item) { [void]$result.Add($item) }
                }
            } finally {
                $worker.PowerShell.Dispose()
            }
        }
        return @($result.ToArray() | Sort-Object Path)
    } finally {
        foreach ($worker in $workers) {
            try { $worker.PowerShell.Dispose() } catch {}
        }
        try { $pool.Close() } catch {}
        $pool.Dispose()
    }
}

function Find-ToolPatternFilesParallel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Roots,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [ValidateRange(1, 1000)][int]$MaximumResults = 60,
        [ValidateRange(1, 8)][int]$ThrottleLimit = 4,
        [ValidateRange(1, 8)][int]$MaximumDepth = 4,
        [ValidateRange(3, 60)][int]$PerRootTimeoutSeconds = 12,
        [AllowEmptyCollection()][string[]]$ExcludedRoots = @()
    )

    # Preserve the historic behavior of ignoring missing optional roots, while
    # validating every root that would actually be traversed.
    $existingRoots = @($Roots | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and
        -not ([string]$_).StartsWith('\\', [StringComparison]::Ordinal) -and
        -not ([string]$_).StartsWith('//', [StringComparison]::Ordinal) -and
        (Test-Path -LiteralPath $_ -PathType Container)
    })
    $existingExcludedRoots = @($ExcludedRoots | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and
        -not ([string]$_).StartsWith('\\', [StringComparison]::Ordinal) -and
        -not ([string]$_).StartsWith('//', [StringComparison]::Ordinal) -and
        (Test-Path -LiteralPath $_ -PathType Container)
    })
    # Internal default discovery may fan out to more than the eight roots a
    # user can explicitly select. The UI/request boundary remains capped at 8.
    # Windows keeps compatibility links such as C:\Users\All Users\Desktop.
    # They point back into locations that are already scanned.  Treating one of
    # these automatic discovery roots as a fatal input error made the whole
    # software result read-only even though no user-selected source was unsafe.
    # Validate roots one by one and silently skip only reparse-point roots; all
    # other invalid local paths still fail closed.
    $validatedRoots = New-Object System.Collections.Generic.List[string]
    foreach ($existingRoot in @($existingRoots)) {
        try {
            foreach ($resolvedRoot in @(Resolve-ToolLocalScanRoots -Roots @([string]$existingRoot) -MaximumRoots 64 -ParameterName 'Roots')) {
                if (-not $validatedRoots.Contains([string]$resolvedRoot)) { [void]$validatedRoots.Add([string]$resolvedRoot) }
            }
        } catch [ArgumentException] {
            if ([string]$_.Exception.Message -match '(?i)junction/symlink/reparse point') { continue }
            throw
        }
    }
    if ($validatedRoots.Count -gt 64) { throw (New-Object ArgumentException('Roots vượt quá giới hạn 64 thư mục.', 'Roots')) }
    $scanRoots = @($validatedRoots.ToArray())

    $validatedExcludedRoots = New-Object System.Collections.Generic.List[string]
    foreach ($existingExcludedRoot in @($existingExcludedRoots)) {
        try {
            foreach ($resolvedRoot in @(Resolve-ToolLocalScanRoots -Roots @([string]$existingExcludedRoot) -ParameterName 'ExcludedRoots')) {
                if (-not $validatedExcludedRoots.Contains([string]$resolvedRoot)) { [void]$validatedExcludedRoots.Add([string]$resolvedRoot) }
            }
        } catch [ArgumentException] {
            if ([string]$_.Exception.Message -match '(?i)junction/symlink/reparse point') { continue }
            throw
        }
    }
    $safeExcludedRoots = @($validatedExcludedRoots.ToArray())
    $scanRoots = @($scanRoots | Where-Object {
        $candidateRoot = $_
        @($safeExcludedRoots | Where-Object { Test-ToolPathWithinRoot -Path $candidateRoot -Root $_ }).Count -eq 0
    })
    if ($scanRoots.Count -eq 0) { return @() }
    [void](New-Object Text.RegularExpressions.Regex($Pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromMilliseconds(500)))
    $pool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($ThrottleLimit, $scanRoots.Count))
    $workers = New-Object System.Collections.Generic.List[object]
$workerScript = @'
param($Root,$RegexPattern,$MaximumPerRoot,$MaximumDepth,$TimeoutMilliseconds,$ExcludedRoots)
$regex = New-Object Text.RegularExpressions.Regex($RegexPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromMilliseconds(500))
$matches = New-Object System.Collections.Generic.List[string]
$pending = New-Object "System.Collections.Generic.Stack[object]"
$pending.Push([pscustomobject]@{ Path=$Root; Depth=0 })
$watch = [Diagnostics.Stopwatch]::StartNew()
function Test-ExcludedPath([string]$CandidatePath) {
    $candidate = [IO.Path]::GetFullPath($CandidatePath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    foreach ($excludedRoot in @($ExcludedRoots)) {
        $boundary = [IO.Path]::GetFullPath([string]$excludedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        if ($candidate.Equals($boundary, [StringComparison]::OrdinalIgnoreCase) -or
            $candidate.StartsWith(($boundary + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}
while ($pending.Count -gt 0 -and $matches.Count -lt $MaximumPerRoot -and $watch.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
    $current = $pending.Pop()
    try {
        if (Test-ExcludedPath -CandidatePath ([string]$current.Path)) { continue }
        $directory = New-Object IO.DirectoryInfo([string]$current.Path)
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        foreach ($file in $directory.EnumerateFiles()) {
            if ($watch.ElapsedMilliseconds -ge $TimeoutMilliseconds) { break }
            if (Test-ExcludedPath -CandidatePath $file.FullName) { continue }
            if ($regex.IsMatch($file.Name) -or $regex.IsMatch($file.FullName)) {
                [void]$matches.Add($file.FullName)
                if ($matches.Count -ge $MaximumPerRoot) { break }
            }
        }
        if ($matches.Count -ge $MaximumPerRoot -or $watch.ElapsedMilliseconds -ge $TimeoutMilliseconds -or [int]$current.Depth -ge $MaximumDepth) { continue }
        foreach ($child in $directory.EnumerateDirectories()) {
            if ($watch.ElapsedMilliseconds -ge $TimeoutMilliseconds) { break }
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                -not (Test-ExcludedPath -CandidatePath $child.FullName)) {
                $pending.Push([pscustomobject]@{ Path=$child.FullName; Depth=([int]$current.Depth + 1) })
            }
        }
    } catch {}
}
$watch.Stop()
$matches.ToArray()
'@

    try {
        $pool.Open()
        foreach ($root in $scanRoots) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($workerScript).AddArgument([string]$root).AddArgument($Pattern).AddArgument($MaximumResults).AddArgument($MaximumDepth).AddArgument([int]($PerRootTimeoutSeconds * 1000)).AddArgument([string[]]$safeExcludedRoots)
            $handle = $powerShell.BeginInvoke()
            [void]$workers.Add([pscustomobject]@{ PowerShell=$powerShell; Handle=$handle })
        }
        $paths = New-Object System.Collections.Generic.List[string]
        foreach ($worker in $workers) {
            try {
                foreach ($path in @($worker.PowerShell.EndInvoke($worker.Handle))) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$path)) { [void]$paths.Add([string]$path) }
                }
            } finally {
                $worker.PowerShell.Dispose()
            }
        }
        return @($paths.ToArray() | Select-Object -Unique | Sort-Object | Select-Object -First $MaximumResults)
    } finally {
        foreach ($worker in $workers) {
            try { $worker.PowerShell.Dispose() } catch {}
        }
        try { $pool.Close() } catch {}
        $pool.Dispose()
    }
}

function Get-ToolScanOptimizationMetadata {
    return [pscustomobject][ordered]@{
        Version = $script:ToolScanOptimizationVersion
        ToolVersion = $script:ToolScanOptimizationToolVersion
        DefaultProfile = "Standard"
        SupportedProfiles = @("Quick", "Standard", "Deep")
        SupportsLowResourceMode = $true
        SupportsIncludedRoots = $true
        SupportsExcludedRoots = $true
        MaximumRootCount = $script:ToolScanMaximumRootCount
        OfficeDiscovery = "BoundedDepth"
        OfficeStatusThrottle = 3
        OfficeCommandTimeoutSeconds = 45
        FileScanThrottle = 4
        FileScanMaximumDepth = 4
        FileScanPerRootTimeoutSeconds = 12
        PreservesExistingScanRoots = $true
        StandardPlan = Resolve-ToolScanPlan -Profile Standard
    }
}
