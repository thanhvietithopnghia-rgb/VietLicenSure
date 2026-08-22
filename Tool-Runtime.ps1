function Get-ToolArchitectureState {
    $is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
    $is64BitProcess = [Environment]::Is64BitProcess
    $processArchitecture = if ($is64BitProcess) { "x64" } else { "x86" }
    $operatingSystemArchitecture = if ($is64BitOperatingSystem) { "x64" } else { "x86" }
    $expectedArchitecture = ([string]$env:TOOL_EXPECTED_PROCESS_ARCHITECTURE).Trim().ToLowerInvariant()
    $supported = $true
    $message = Get-ToolTextCurrent "foundation.runtime.architectureNative" @($processArchitecture)

    if ($is64BitOperatingSystem -and -not $is64BitProcess) {
        $supported = $false
        $message = Get-ToolTextCurrent "foundation.runtime.architectureWow64"
    } elseif ($expectedArchitecture -eq "x64" -and -not $is64BitProcess) {
        $supported = $false
        $message = Get-ToolTextCurrent "foundation.runtime.x64In32Bit"
    } elseif ($expectedArchitecture -eq "x86" -and ($is64BitOperatingSystem -or $is64BitProcess)) {
        $supported = $false
        $message = Get-ToolTextCurrent "foundation.runtime.x86LabelInvalid"
    } elseif ($expectedArchitecture -and $expectedArchitecture -notin @("x64", "x86")) {
        $supported = $false
        $message = Get-ToolTextCurrent "foundation.runtime.architectureLabelInvalid" @($expectedArchitecture)
    }

    return [pscustomobject]@{
        Supported = [bool]$supported
        ProcessArchitecture = $processArchitecture
        OperatingSystemArchitecture = $operatingSystemArchitecture
        ExpectedArchitecture = $expectedArchitecture
        Message = $message
    }
}

$toolRuntimeLocalizationPath = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if ((-not (Get-Command Get-ToolTextCurrent -ErrorAction SilentlyContinue) -or
     -not (Get-Variable -Name ToolLocalizationSupportedCultures -Scope Script -ErrorAction SilentlyContinue)) -and
    (Test-Path -LiteralPath $toolRuntimeLocalizationPath -PathType Leaf)) {
    . $toolRuntimeLocalizationPath
}

function Assert-ToolNativeArchitecture {
    $state = Get-ToolArchitectureState
    if (-not $state.Supported) { throw $state.Message }
    return $state
}

function Get-ToolWindowsDirectory {
    $windowsDirectory = [string]$env:SystemRoot
    if ([string]::IsNullOrWhiteSpace($windowsDirectory)) {
        $windowsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    }
    if ([string]::IsNullOrWhiteSpace($windowsDirectory)) { throw (Get-ToolTextCurrent "foundation.runtime.windowsDirectoryMissing") }
    return $windowsDirectory
}

function Get-ToolWindowsPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        throw (Get-ToolTextCurrent "foundation.runtime.windowsPathUnsafe" @($RelativePath))
    }
    return (Join-Path (Get-ToolWindowsDirectory) $RelativePath)
}

function Get-ToolNativeSystemDirectory {
    $windowsDirectory = Get-ToolWindowsDirectory

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $sysnative = Join-Path $windowsDirectory "Sysnative"
        if (Test-Path -LiteralPath $sysnative -PathType Container) { return $sysnative }
    }
    return (Join-Path $windowsDirectory "System32")
}

function Get-ToolNativeSystemPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        throw (Get-ToolTextCurrent "foundation.runtime.systemPathUnsafe" @($RelativePath))
    }
    return (Join-Path (Get-ToolNativeSystemDirectory) $RelativePath)
}

function Get-ToolNativePowerShellPath {
    $expectedPath = Get-ToolNativeSystemPath "WindowsPowerShell\v1.0\powershell.exe"
    $launcherPath = [string]$env:TOOL_POWERSHELL_PATH

    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and -not [string]::IsNullOrWhiteSpace($launcherPath)) {
        $launcherFull = [IO.Path]::GetFullPath($launcherPath)
        $expectedFull = [IO.Path]::GetFullPath($expectedPath)
        if (-not [string]::Equals($launcherFull, $expectedFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw (Get-ToolTextCurrent "foundation.runtime.powerShellPathMismatch")
        }
    }

    if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
        throw (Get-ToolTextCurrent "foundation.runtime.powerShellMissing" @($expectedPath))
    }
    return $expectedPath
}

function Test-ToolAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return [bool]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-ToolServiceReadinessState {
    param([Parameter(Mandatory = $true)][string[]]$Names)

    $states = New-Object System.Collections.Generic.List[object]
    foreach ($name in $Names) {
        try {
            $service = Get-WmiObject -Class Win32_Service -Filter ("Name='{0}'" -f $name.Replace("'", "''")) -ErrorAction Stop
            $states.Add([pscustomobject][ordered]@{
                Name=$name; Found=[bool]($null -ne $service); State=[string]$service.State
                StartMode=[string]$service.StartMode; Started=[bool]$service.Started; Error=''
            })
        } catch {
            $wmiError = $_.Exception.Message
            try {
                # The Service Control Manager remains available when WMI itself
                # is stopped, so it can diagnose and safely start Winmgmt.
                $service = Get-Service -Name $name -ErrorAction Stop
                $startValue = [int](Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $name) -Name Start -ErrorAction Stop).Start
                $startMode = switch ($startValue) { 2 {'Auto'}; 3 {'Manual'}; 4 {'Disabled'}; default {'Unknown'} }
                $states.Add([pscustomobject][ordered]@{
                    Name=$name; Found=$true; State=[string]$service.Status; StartMode=$startMode
                    Started=[bool]([string]$service.Status -eq 'Running'); Error=$wmiError
                })
            } catch {
                $states.Add([pscustomobject][ordered]@{
                    Name=$name; Found=$false; State='Unknown'; StartMode='Unknown'; Started=$false; Error=($wmiError + ' | ' + $_.Exception.Message)
                })
            }
        }
    }
    return $states.ToArray()
}

function Invoke-ToolLicenseDataRead {
    param(
        [string]$Namespace = 'root/cimv2',
        [string]$ClassName = 'SoftwareLicensingProduct',
        [switch]$RepairServices,
        [scriptblock]$QueryScript
    )

    $requiredServices = @('Winmgmt','sppsvc')
    $isAdministrator = Test-ToolAdministrator
    $before = @(Get-ToolServiceReadinessState -Names $requiredServices)
    $repairs = New-Object System.Collections.Generic.List[string]
    if ($RepairServices -and $isAdministrator) {
        foreach ($serviceState in $before) {
            if (-not $serviceState.Found -or $serviceState.Started -or $serviceState.StartMode -eq 'Disabled') { continue }
            try {
                Start-Service -Name ([string]$serviceState.Name) -ErrorAction Stop
                $repairs.Add(('Started:{0}' -f [string]$serviceState.Name))
            } catch {
                $repairs.Add(('StartFailed:{0}:{1}' -f [string]$serviceState.Name,$_.Exception.Message))
            }
        }
    }

    $attempts = New-Object System.Collections.Generic.List[object]
    $items = @()
    $source = ''
    $succeeded = $false
    foreach ($method in @('CIM','WMI')) {
        try {
            if ($QueryScript) {
                $items = @(& $QueryScript $method $Namespace $ClassName)
            } elseif ($method -eq 'CIM' -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
                $items = @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -OperationTimeoutSec 20 -ErrorAction Stop)
            } elseif ($method -eq 'WMI') {
                $items = @(Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop)
            } else { continue }
            $source = $method
            $succeeded = $true
            $attempts.Add([pscustomobject][ordered]@{ Method=$method; Succeeded=$true; Error='' })
            break
        } catch {
            $attempts.Add([pscustomobject][ordered]@{ Method=$method; Succeeded=$false; Error=$_.Exception.Message })
        }
    }

    $after = @(Get-ToolServiceReadinessState -Names $requiredServices)
    $errors = @($attempts | Where-Object { -not $_.Succeeded } | ForEach-Object { [string]$_.Error })
    $errorText = ($errors -join ' | ')
    $status = if ($succeeded) {
        'Readable'
    } elseif (-not $isAdministrator -and $errorText -match '(?i)access|denied|0x80070005') {
        'ElevationRequired'
    } elseif (@($after | Where-Object { $_.Found -and -not $_.Started }).Count -gt 0) {
        'ServiceUnavailable'
    } elseif ($errorText -match '(?i)invalid class|0x80041010') {
        'ClassUnavailable'
    } else {
        'Unavailable'
    }

    return [pscustomobject][ordered]@{
        Succeeded=[bool]$succeeded; Status=$status; Source=$source; Items=@($items)
        IsAdministrator=[bool]$isAdministrator; RepairRequested=[bool]$RepairServices
        Repairs=$repairs.ToArray(); ServicesBefore=$before; ServicesAfter=$after
        Attempts=$attempts.ToArray(); ErrorDetail=$errorText
    }
}
