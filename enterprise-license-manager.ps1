<#
    Trung tâm quản lý license doanh nghiệp của VietLicenSure.
    Giao diện chỉ điều phối các thao tác chính; dữ liệu nhạy cảm được xử lý
    trong Tool-Enterprise.ps1 và không ghi product key đầy đủ vào log.
#>
[CmdletBinding()]
param(
    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$enterpriseVersionFromLauncher = [string]$env:TOOL_TOOL_VERSION
$script:enterpriseReleaseVersion = if ($enterpriseVersionFromLauncher -match '^\d+\.\d+\.\d+\.\d+$') {
    $enterpriseVersionFromLauncher
} else {
    "5.0"
}
$script:enterpriseReleaseDisplayName = "v5.0"
$enterpriseReleaseParts = @($script:enterpriseReleaseVersion -split '\.')
$script:enterpriseInfrastructureVersion = "v$($enterpriseReleaseParts[0]).$($enterpriseReleaseParts[1])"
. (Join-Path $baseDir "Tool-ReportSchema.ps1")
. (Join-Path $baseDir "Tool-Enterprise.ps1")
$localizationHelper = Join-Path $baseDir "Tool-Localization.ps1"
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { throw (Get-ToolEnterpriseText "enterprise.missingComponent" @("Tool-Localization.ps1")) }
. $localizationHelper
$script:enterpriseCulture = Get-ToolCulture
$env:TOOL_UI_CULTURE = $script:enterpriseCulture
$offlinePolicyHelper = Join-Path $baseDir "Tool-OfflinePolicy.ps1"
if (-not (Test-Path -LiteralPath $offlinePolicyHelper -PathType Leaf)) {
    throw (Get-ToolText -Key "enterprise.missingComponent" -Culture $script:enterpriseCulture -FormatArguments @("Tool-OfflinePolicy.ps1"))
}
. $offlinePolicyHelper
$script:enterpriseNetworkAllowed = [bool](Get-ToolEnterpriseNetworkAllowed)
$env:TOOL_ENTERPRISE_NETWORK_ALLOWED = if ($script:enterpriseNetworkAllowed) { "1" } else { "0" }
$uiThemeHelper = Join-Path $baseDir "Tool-UiTheme.ps1"
if (-not (Test-Path -LiteralPath $uiThemeHelper -PathType Leaf)) {
    throw (Get-ToolText -Key "enterprise.missingComponent" -Culture $script:enterpriseCulture -FormatArguments @("Tool-UiTheme.ps1"))
}
. $uiThemeHelper

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:enterpriseTypography = Get-ToolUiTypography
$script:enterpriseFont = New-Object Drawing.Font($script:enterpriseTypography.FontFamily, $script:enterpriseTypography.NormalSize)
$script:enterpriseSmallFont = New-Object Drawing.Font($script:enterpriseTypography.FontFamily, $script:enterpriseTypography.SmallSize)
$script:enterpriseTitleFont = New-Object Drawing.Font($script:enterpriseTypography.FontFamily, $script:enterpriseTypography.DialogTitleSize, [Drawing.FontStyle]::Bold)
$script:enterpriseTheme = Get-ToolUiTheme
$script:baseUiPalette = Get-ToolUiPalette -Mode $script:enterpriseTheme
$script:enterpriseDark = [bool]($script:enterpriseTheme -eq "Dark")
$script:enterprisePalette = @{
    Form             = $script:baseUiPalette.Background
    Surface          = $script:baseUiPalette.Surface
    LocalSurface     = $script:baseUiPalette.Surface
    ServerSurface    = $script:baseUiPalette.Surface
    ClientSurface    = $script:baseUiPalette.Surface
    Header           = $script:baseUiPalette.Primary
    Text             = $script:baseUiPalette.Text
    Muted            = $script:baseUiPalette.Muted
    Success          = $script:baseUiPalette.Success
    Warning          = $script:baseUiPalette.Warning
    DangerText       = $script:baseUiPalette.Danger
    Button           = $script:baseUiPalette.Button
    ButtonHover      = $script:baseUiPalette.ButtonHover
    LocalButton      = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(38, 80, 145) } else { [Drawing.Color]::FromArgb(18, 59, 116) }
    LocalHover       = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(48, 96, 168) } else { [Drawing.Color]::FromArgb(27, 78, 145) }
    ServerButton     = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(38, 80, 145) } else { [Drawing.Color]::FromArgb(18, 59, 116) }
    ServerHover      = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(48, 96, 168) } else { [Drawing.Color]::FromArgb(27, 78, 145) }
    ClientButton     = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(38, 80, 145) } else { [Drawing.Color]::FromArgb(18, 59, 116) }
    ClientHover      = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(48, 96, 168) } else { [Drawing.Color]::FromArgb(27, 78, 145) }
    Navigation      = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(51, 65, 85) } else { [Drawing.Color]::FromArgb(71, 85, 105) }
    NavigationHover = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(39, 49, 65) } else { [Drawing.Color]::FromArgb(51, 65, 85) }
    Danger          = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(153, 27, 27) } else { [Drawing.Color]::FromArgb(185, 28, 28) }
    DangerHover     = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(127, 29, 29) } else { [Drawing.Color]::FromArgb(153, 27, 27) }
    Input            = $script:baseUiPalette.Input
    Border           = $script:baseUiPalette.Border
}
$script:enterpriseStatus = $null
$script:serverClients = @()
$script:serverProcess = $null
$script:agentProcess = $null
$script:config = $null
$script:serverAddressLabel = $null
$script:enterpriseNetworkButton = $null
$script:enterpriseToolTip = New-Object Windows.Forms.ToolTip
$script:enterpriseToolTip.AutoPopDelay = 12000
$script:enterpriseToolTip.InitialDelay = 300
$script:previousTabIndex = 0

function Get-EnterpriseText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )
    return Get-ToolText -Key $Key -Culture $script:enterpriseCulture -FormatArguments $Arguments
}

function Set-EnterpriseStatus {
    param([string]$Message, [bool]$Success = $true)
    if ($script:enterpriseStatus) {
        $script:enterpriseStatus.Text = $Message
        $script:enterpriseStatus.ForeColor = if ($Success) { $script:enterprisePalette.Success } else { $script:enterprisePalette.DangerText }
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-EnterpriseError {
    param([string]$Message)
    # Tránh lặp nguyên văn cùng một lỗi ở cả thanh trạng thái và hộp thoại.
    Set-EnterpriseStatus -Message (Get-EnterpriseText "enterprise.error.statusShort") -Success:$false
    [Windows.Forms.MessageBox]::Show(
        $Message,
        (Get-EnterpriseText "enterprise.error.title" @($script:enterpriseReleaseDisplayName)),
        "OK",
        "Error"
    ) | Out-Null
}

function Confirm-EnterpriseAction {
    param(
        [string]$Message,
        [string]$Title = ""
    )
    if ([string]::IsNullOrWhiteSpace($Title)) { $Title = Get-EnterpriseText "enterprise.confirm.title" }
    return ([Windows.Forms.MessageBox]::Show($Message, $Title, "YesNo", "Warning") -eq [Windows.Forms.DialogResult]::Yes)
}

function Update-EnterpriseNetworkStateUi {
    param([switch]$UpdateStatus)

    if (-not $script:enterpriseNetworkButton) { return }
    if (-not $script:enterpriseNetworkAllowed) {
        $script:enterpriseNetworkButton.Text = Get-EnterpriseText "enterprise.network.stateOffline"
        $script:enterpriseToolTip.SetToolTip($script:enterpriseNetworkButton, (Get-EnterpriseText "enterprise.network.tooltipOffline"))
        Set-EnterpriseButtonStyle $script:enterpriseNetworkButton $script:enterprisePalette.Navigation ([Drawing.Color]::White) $script:enterprisePalette.NavigationHover
        if ($UpdateStatus) {
            Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.blockedStatus") $true
        }
    } else {
        $script:enterpriseNetworkButton.Text = Get-EnterpriseText "enterprise.network.stateOnline"
        $script:enterpriseToolTip.SetToolTip($script:enterpriseNetworkButton, (Get-EnterpriseText "enterprise.network.tooltipOnline"))
        Set-EnterpriseButtonStyle $script:enterpriseNetworkButton $script:enterprisePalette.ServerButton ([Drawing.Color]::White) $script:enterprisePalette.ServerHover
        if ($UpdateStatus) {
            Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.allowedStatus") $true
        }
    }
}

function Enable-EnterpriseNetworkAccess {
    param(
        [string]$Action = "",
        [switch]$SkipConfirmation
    )

    if ($script:enterpriseNetworkAllowed) { return $true }
    if ([string]::IsNullOrWhiteSpace($Action)) { $Action = Get-EnterpriseText "menu.8.title" }
    $message = Get-EnterpriseText "enterprise.network.enablePrompt" @($Action)
    if (-not $SkipConfirmation -and -not (Confirm-EnterpriseAction $message (Get-EnterpriseText "enterprise.network.enableTitle"))) {
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.remainsOff") $true
        return $false
    }

    $saved = Set-ToolEnterpriseNetworkAllowedPreference -Allowed $true
    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = "1"
    $script:enterpriseNetworkAllowed = $true
    Update-EnterpriseNetworkStateUi
    if ($saved) {
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.enableSaved") $true
    } else {
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.enableSession") $false
    }
    return $true
}

function Disable-EnterpriseNetworkAccess {
    param([switch]$SkipConfirmation)

    if (-not $script:enterpriseNetworkAllowed) { return $true }
    if (-not $SkipConfirmation -and -not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.network.disablePrompt") (Get-EnterpriseText "enterprise.network.disableTitle"))) {
        return $false
    }

    $saved = Set-ToolEnterpriseNetworkAllowedPreference -Allowed $false
    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = "0"
    $script:enterpriseNetworkAllowed = $false

    try {
        [void](Remove-EnterpriseLifecycleTasks -Role Server)
        [void](Remove-EnterpriseLifecycleTasks -Role Agent)
        $paths = Get-ToolEnterprisePaths
        if (Test-Path -LiteralPath $paths.ServerConfig -PathType Leaf) {
            New-Item -ItemType File -Path $paths.ServerStop -Force | Out-Null
        }
    } catch {}
    foreach ($process in @($script:agentProcess, $script:serverProcess)) {
        if ($process -and -not $process.HasExited) {
            try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    $script:agentProcess = $null
    $script:serverProcess = $null
    Update-EnterpriseNetworkStateUi
    Set-EnterpriseStatus (Get-EnterpriseText $(if ($saved) { "enterprise.network.disableSaved" } else { "enterprise.network.disableSession" })) $saved
    return $true
}

function Toggle-EnterpriseNetworkAccess {
    param([switch]$SkipConfirmation)
    if ($script:enterpriseNetworkAllowed) {
        return Disable-EnterpriseNetworkAccess -SkipConfirmation:$SkipConfirmation
    }
    return Enable-EnterpriseNetworkAccess -SkipConfirmation:$SkipConfirmation
}

function Confirm-EnterpriseNetworkAccess {
    param([string]$ActionKey)
    $action = if ([string]::IsNullOrWhiteSpace($ActionKey)) {
        Get-EnterpriseText "menu.8.title"
    } else {
        Get-EnterpriseText $ActionKey
    }
    return (Enable-EnterpriseNetworkAccess -Action $action)
}

function Get-EnterpriseLauncherPath {
    $candidate = [string]$env:TOOL_LAUNCHER_PATH
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    return ""
}

function Get-EnterpriseLifecycleTaskName {
    param([ValidateSet("Server", "Agent")][string]$Role)
    return "ThanhViet Tool $($script:enterpriseInfrastructureVersion) Enterprise $Role"
}

function Get-EnterpriseLegacyLifecycleTaskNames {
    param([ValidateSet("Server", "Agent")][string]$Role)
    return @(
        "ThanhViet Tool v4.8 Enterprise $Role",
        "ThanhViet Tool v4.6 Enterprise $Role"
    )
}

function New-EnterpriseLifecycleTaskXml {
    param(
        [ValidateSet("Server", "Agent")][string]$Role,
        [Parameter(Mandatory = $true)][string]$LauncherPath
    )

    $launcherFullPath = [IO.Path]::GetFullPath($LauncherPath)
    $escapedLauncher = [Security.SecurityElement]::Escape($launcherFullPath)
    # The payload directory is temporary for the one-file EXE and is removed
    # when the dashboard closes. Persist the launcher's stable directory.
    $escapedWorkingDirectory = [Security.SecurityElement]::Escape([IO.Path]::GetDirectoryName($launcherFullPath))
    $arguments = if ($Role -eq "Server") { "--enterprise-server" } else { "--enterprise-agent" }
    $description = if ($Role -eq "Server") {
        "VietLicenSure enterprise server: start after Windows boot or logon and restart after a transient failure."
    } else {
        "VietLicenSure enterprise agent: run after boot, logon, resume and every hour."
    }
    $escapedDescription = [Security.SecurityElement]::Escape($description)
    $startBoundary = (Get-Date).AddMinutes(2).ToString("s", [Globalization.CultureInfo]::InvariantCulture)
    $eventSubscription = [Security.SecurityElement]::Escape("<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select></Query></QueryList>")
    $roleTriggers = if ($Role -eq "Agent") {
@"
    <CalendarTrigger>
      <Repetition><Interval>PT1H</Interval><Duration>P1D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
      <StartBoundary>$startBoundary</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
    </CalendarTrigger>
    <EventTrigger><Enabled>true</Enabled><Subscription>$eventSubscription</Subscription><Delay>PT30S</Delay></EventTrigger>
"@
    } else { "" }
    $executionLimit = if ($Role -eq "Server") { "PT0S" } else { "PT10M" }

    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>$escapedDescription</Description></RegistrationInfo>
  <Triggers>
    <BootTrigger><Enabled>true</Enabled><Delay>PT45S</Delay></BootTrigger>
    <LogonTrigger><Enabled>true</Enabled><Delay>PT30S</Delay></LogonTrigger>
$roleTriggers  </Triggers>
  <Principals><Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <WakeToRun>false</WakeToRun>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <ExecutionTimeLimit>$executionLimit</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure><Interval>PT5M</Interval><Count>3</Count></RestartOnFailure>
  </Settings>
  <Actions Context="Author"><Exec><Command>$escapedLauncher</Command><Arguments>$arguments</Arguments><WorkingDirectory>$escapedWorkingDirectory</WorkingDirectory></Exec></Actions>
</Task>
"@
}

function Install-EnterpriseLifecycleTask {
    param(
        [ValidateSet("Server", "Agent")][string]$Role,
        [Parameter(Mandatory = $true)][string]$LauncherPath
    )

    $schtasks = Join-Path $env:SystemRoot "System32\schtasks.exe"
    if (-not (Test-Path -LiteralPath $schtasks -PathType Leaf)) { throw (Get-EnterpriseText "enterprise.error.schtasksMissing") }
    $taskName = Get-EnterpriseLifecycleTaskName -Role $Role
    $temporaryXml = Join-Path ([IO.Path]::GetTempPath()) ("VietLicenSure-{0}-{1}.xml" -f $Role, [Guid]::NewGuid().ToString("N"))
    try {
        $xml = New-EnterpriseLifecycleTaskXml -Role $Role -LauncherPath $LauncherPath
        [IO.File]::WriteAllText($temporaryXml, $xml, [Text.Encoding]::Unicode)
        $arguments = "/Create /TN `"$taskName`" /XML `"$temporaryXml`" /F"
        $process = Start-Process -FilePath $schtasks -ArgumentList $arguments -Verb RunAs -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) { throw (Get-EnterpriseText "enterprise.error.schtasksExit" @($process.ExitCode)) }
    } finally {
        if (Test-Path -LiteralPath $temporaryXml -PathType Leaf) { Remove-Item -LiteralPath $temporaryXml -Force -ErrorAction SilentlyContinue }
    }
    return $taskName
}

function Remove-EnterpriseLifecycleTasks {
    param([ValidateSet("Server", "Agent")][string]$Role)

    $schtasks = Join-Path $env:SystemRoot "System32\schtasks.exe"
    if (-not (Test-Path -LiteralPath $schtasks -PathType Leaf)) { throw (Get-EnterpriseText "enterprise.error.schtasksMissing") }
    $taskNames = @((Get-EnterpriseLifecycleTaskName -Role $Role)) + @(Get-EnterpriseLegacyLifecycleTaskNames -Role $Role)
    $currentTaskExitCode = 0
    foreach ($taskName in @($taskNames | Select-Object -Unique)) {
        $queryArguments = "/Query /TN `"$taskName`""
        $queryProcess = Start-Process -FilePath $schtasks -ArgumentList $queryArguments -Wait -PassThru -WindowStyle Hidden
        if ($queryProcess.ExitCode -ne 0) { continue }
        $arguments = "/Delete /TN `"$taskName`" /F"
        $process = Start-Process -FilePath $schtasks -ArgumentList $arguments -Verb RunAs -Wait -PassThru -WindowStyle Hidden
        if ($taskName -eq (Get-EnterpriseLifecycleTaskName -Role $Role)) { $currentTaskExitCode = [int]$process.ExitCode }
    }
    # schtasks returns 1 when the task does not exist. Disabling an already
    # disabled lifecycle is idempotent and therefore remains successful.
    if ($currentTaskExitCode -notin @(0, 1)) { throw (Get-EnterpriseText "enterprise.error.schtasksExit" @($currentTaskExitCode)) }
    return $currentTaskExitCode
}

function Test-EnterpriseLifecycleTaskInstalled {
    param([ValidateSet("Server", "Agent")][string]$Role)

    $schtasks = Join-Path $env:SystemRoot "System32\schtasks.exe"
    if (-not (Test-Path -LiteralPath $schtasks -PathType Leaf)) { return $false }
    $taskName = Get-EnterpriseLifecycleTaskName -Role $Role
    & $schtasks /Query /TN $taskName 1>$null 2>$null
    return [bool]($LASTEXITCODE -eq 0)
}

function Update-EnterpriseLifecycleStatus {
    if (-not $script:enterpriseNetworkAllowed) { return }
    try {
        $serverConfig = Get-EnterpriseServerConfigurationSafe
        if ($serverConfig) {
            $runningText = Get-EnterpriseText $(if (Test-ToolEnterpriseServerHostRunning) { "common.yes" } else { "common.no" })
            $scheduledText = Get-EnterpriseText $(if (Test-EnterpriseLifecycleTaskInstalled -Role Server) { "common.yes" } else { "common.no" })
            Set-EnterpriseStatus (Get-EnterpriseText "enterprise.lifecycle.serverSummary" @($runningText, $scheduledText)) $true
            return
        }
        $clientConfig = Get-ToolEnterpriseClientConfig
        if ($clientConfig -and [bool]$clientConfig.Enrolled) {
            $scheduledText = Get-EnterpriseText $(if (Test-EnterpriseLifecycleTaskInstalled -Role Agent) { "common.yes" } else { "common.no" })
            $paths = Get-ToolEnterprisePaths
            $lastMessage = Get-EnterpriseText "common.none"
            foreach ($candidate in @($paths.ClientAgentError, $paths.ClientAgentResult)) {
                if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
                $record = Read-ToolEnterpriseJson -Path $candidate -MaximumBytes 65536
                if ($record) {
                    $lastMessage = if (-not [string]::IsNullOrWhiteSpace([string]$record.Message)) {
                        ConvertTo-ToolEnterpriseSafeText $record.Message 180
                    } elseif ($null -ne $record.Success) {
                        Get-EnterpriseText $(if ([bool]$record.Success) { "common.success" } else { "common.failed" })
                    } else { Get-EnterpriseText "common.none" }
                    break
                }
            }
            Set-EnterpriseStatus (Get-EnterpriseText "enterprise.lifecycle.clientSummary" @($scheduledText, $lastMessage)) $true
        }
    } catch {}
}

function Start-EnterpriseChild {
    param([ValidateSet("Server", "Agent")][string]$Role, [bool]$Force = $false)
    Assert-ToolEnterpriseNetworkActionAllowed -Action (Get-EnterpriseText "enterprise.action.childProcess" @($Role))
    $launcher = Get-EnterpriseLauncherPath
    if ($launcher) {
        $arguments = if ($Role -eq "Server") { "--enterprise-server" } elseif ($Force) { "--enterprise-agent-force" } else { "--enterprise-agent" }
        $parameters = @{ FilePath=$launcher; ArgumentList=$arguments; PassThru=$true; WorkingDirectory=$baseDir }
        try { $parameters.Verb = "RunAs" } catch {}
        return (Start-Process @parameters)
    }
    $hostScript = if ($Role -eq "Server") { Join-Path $baseDir "Tool-EnterpriseHost.ps1" } else { Join-Path $baseDir "Tool-EnterpriseAgent.ps1" }
    $ps = if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { (Get-Command powershell.exe).Source } else { "powershell.exe" }
    $fallbackArgs = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$hostScript`""
    if ($Role -eq "Agent" -and $Force) { $fallbackArgs += " -Force" }
    $fallbackParameters = @{ FilePath=$ps; ArgumentList=$fallbackArgs; WorkingDirectory=$baseDir; PassThru=$true }
    if ($Role -eq 'Server') { $fallbackParameters.Verb = 'RunAs' }
    return (Start-Process @fallbackParameters)
}

function Get-EnterpriseServerRuntimeError {
    try {
        $paths = Get-ToolEnterprisePaths
        if (Test-Path -LiteralPath $paths.ServerError -PathType Leaf) {
            $errorRecord = Read-ToolEnterpriseJson -Path $paths.ServerError -MaximumBytes 65536
            if ($errorRecord -and -not [string]::IsNullOrWhiteSpace([string]$errorRecord.Message)) {
                return (ConvertTo-ToolEnterpriseSafeText $errorRecord.Message 1200)
            }
        }
    } catch {}
    return ''
}

function Wait-EnterpriseServerReady {
    param(
        [Parameter(Mandatory = $true)][object]$Configuration,
        [Parameter(Mandatory = $true)][object]$LauncherProcess,
        [ValidateRange(3, 60)][int]$TimeoutSeconds = 18
    )

    $paths = Get-ToolEnterprisePaths
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastDiagnostic = $null
    do {
        [Windows.Forms.Application]::DoEvents()
        try { $LauncherProcess.Refresh() } catch {}
        if ($LauncherProcess.HasExited) {
            $runtimeError = Get-EnterpriseServerRuntimeError
            if ([string]::IsNullOrWhiteSpace($runtimeError)) {
                $runtimeError = Get-EnterpriseText 'enterprise.server.processExited' @($LauncherProcess.ExitCode)
            }
            throw $runtimeError
        }

        $lastDiagnostic = Get-ToolEnterpriseConnectionDiagnostic -ServerAddress '127.0.0.1' -Port ([int]$Configuration.Port) -TimeoutMs 900
        if ($lastDiagnostic.Success -and
            (Test-Path -LiteralPath $paths.ServerPid -PathType Leaf) -and
            (Test-Path -LiteralPath $paths.ServerHeartbeat -PathType Leaf)) {
            $pidRecord = Read-ToolEnterpriseJson -Path $paths.ServerPid -MaximumBytes 65536
            $heartbeat = Read-ToolEnterpriseJson -Path $paths.ServerHeartbeat -MaximumBytes 65536
            if ($pidRecord -and $heartbeat -and [int]$pidRecord.ProcessId -gt 0 -and
                [int]$heartbeat.ProcessId -eq [int]$pidRecord.ProcessId) {
                return [pscustomobject][ordered]@{
                    Success=$true; ProcessId=[int]$pidRecord.ProcessId; Diagnostic=$lastDiagnostic; Heartbeat=$heartbeat
                }
            }
        }
        Start-Sleep -Milliseconds 220
    } while ([DateTime]::UtcNow -lt $deadline)

    $runtimeError = Get-EnterpriseServerRuntimeError
    if ([string]::IsNullOrWhiteSpace($runtimeError)) {
        $diagnosticText = if ($lastDiagnostic) { [string]$lastDiagnostic.Message } else { Get-EnterpriseText 'enterprise.server.noDiagnostic' }
        $runtimeError = Get-EnterpriseText 'enterprise.server.startTimeout' @($TimeoutSeconds, $diagnosticText)
    }
    throw $runtimeError
}

function Wait-EnterpriseAgentResult {
    param(
        [Parameter(Mandatory = $true)][object]$LauncherProcess,
        [ValidateRange(5, 180)][int]$TimeoutSeconds = 90
    )

    $paths = Get-ToolEnterprisePaths
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $LauncherProcess.Refresh() } catch {}
        if ($LauncherProcess.HasExited) { break }
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 180
    }
    if (-not $LauncherProcess.HasExited) {
        throw (Get-EnterpriseText 'enterprise.client.agentTimeout' @($TimeoutSeconds))
    }
    if (Test-Path -LiteralPath $paths.ClientAgentError -PathType Leaf) {
        $errorResult = Read-ToolEnterpriseJson -Path $paths.ClientAgentError -MaximumBytes 65536
        $errorMessage = if ($errorResult -and -not [string]::IsNullOrWhiteSpace([string]$errorResult.Message)) {
            ConvertTo-ToolEnterpriseSafeText $errorResult.Message 1200
        } else {
            Get-EnterpriseText 'enterprise.client.agentFailed' @($LauncherProcess.ExitCode, '')
        }
        throw $errorMessage
    }
    if (-not (Test-Path -LiteralPath $paths.ClientAgentResult -PathType Leaf)) {
        throw (Get-EnterpriseText 'enterprise.client.agentResultMissing' @($LauncherProcess.ExitCode))
    }
    $result = Read-ToolEnterpriseJson -Path $paths.ClientAgentResult -MaximumBytes 65536
    if (-not $result -or -not [bool]$result.Success -or [int]$LauncherProcess.ExitCode -ne 0) {
        throw (Get-EnterpriseText 'enterprise.client.agentFailed' @($LauncherProcess.ExitCode, (ConvertTo-ToolEnterpriseSafeText $result.Message 800)))
    }
    return $result
}

function Stop-EnterpriseServer {
    try {
        [void](Remove-EnterpriseLifecycleTasks -Role Server)
        $paths = Get-ToolEnterprisePaths
        New-Item -ItemType File -Path $paths.ServerStop -Force | Out-Null
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.stopRequestedAutostartDisabled") $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 900) }
}

function Get-EnterpriseServerConfigurationSafe {
    try { return (Get-ToolEnterpriseServerConfig) } catch { return $null }
}

function Update-EnterpriseDetectedServerAddress {
    $address = ""
    try { $address = [string](Get-ToolEnterprisePreferredServerAddress) } catch {}
    if ($script:serverAddressLabel) {
        if ([string]::IsNullOrWhiteSpace($address)) {
            $script:serverAddressLabel.Text = Get-EnterpriseText "enterprise.server.addressMissing"
            $script:serverAddressLabel.ForeColor = $script:enterprisePalette.DangerText
        } else {
            $script:serverAddressLabel.Text = Get-EnterpriseText "enterprise.server.addressFound" @($address)
            $script:serverAddressLabel.ForeColor = $script:enterprisePalette.Success
        }
    }
    return $address
}

function Find-EnterpriseClientServers {
    param([int]$Port)
    Assert-ToolEnterpriseNetworkActionAllowed -Action (Get-EnterpriseText "enterprise.action.discover")
    $discoveryCidrs = @(Get-ToolEnterpriseLocalDiscoveryCidrs)
    if ($discoveryCidrs.Count -eq 0) { throw (Get-EnterpriseText "enterprise.error.noLan") }
    Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.searching" @(($discoveryCidrs -join ', '))) $true
    return @(Find-ToolEnterpriseLocalServers -Port $Port -TimeoutMs 500 -ThrottleLimit 64)
}

function Resolve-EnterpriseClientServerAddress {
    param([switch]$ForceDiscovery)
    $currentAddress = $script:clientAddressBox.Text.Trim()
    if (-not $ForceDiscovery -and -not [string]::IsNullOrWhiteSpace($currentAddress)) {
        $endpoint = Resolve-ToolEnterpriseServerEndpoint -ServerAddress $currentAddress -Port ([int]$script:clientPortBox.Text)
        $script:clientAddressBox.Text = [string]$endpoint.Address
        $script:clientPortBox.Text = [string]$endpoint.Port
        return [string]$endpoint.Address
    }

    $port = [int]$script:clientPortBox.Text
    $servers = @(Find-EnterpriseClientServers -Port $port)
    if ($servers.Count -eq 0) {
        throw (Get-EnterpriseText "enterprise.error.noDiscoveredServer")
    }
    if ($servers.Count -gt 1) {
        $summary = @($servers | ForEach-Object { "$($_.ServerName) [$($_.Address)]" }) -join "; "
        throw (Get-EnterpriseText "enterprise.error.multipleServers" @($summary))
    }
    $address = [string]$servers[0].Address
    $script:clientAddressBox.Text = $address
    Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.discovered" @([string]$servers[0].ServerName, $address, $port)) $true
    return $address
}

function Invoke-ClientDiscover {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.discover")) { return }
        [void](Resolve-EnterpriseClientServerAddress -ForceDiscovery)
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
}

function Update-ServerClientList {
    if (-not $script:serverClientList) { return }
    $script:serverClientList.Items.Clear()
    try { $script:serverClients = @(Get-ToolEnterpriseServerClients) } catch { $script:serverClients = @() }
    $assetStore = $null
    $assetById = @{}
    $assignedAssetIds = @{}
    try {
        if ((Get-Command Read-ToolAssetRegistryStore -ErrorAction SilentlyContinue) -and
            (Get-Command Get-ToolCurrentAssetAssignment -ErrorAction SilentlyContinue)) {
            $assetStore = Read-ToolAssetRegistryStore -RootPath (Initialize-ToolEnterpriseStorage).ServerAssets
            if ($assetStore) {
                foreach ($asset in @($assetStore.Assets)) {
                    $assetId = [string]$asset.AssetId
                    if ([string]::IsNullOrWhiteSpace($assetId)) { continue }
                    $assetById[$assetId] = $asset
                    if ($null -ne (Get-ToolCurrentAssetAssignment -Store $assetStore -AssetId $assetId)) {
                        $assignedAssetIds[$assetId] = $true
                    }
                }
            }
        }
    } catch {
        $assetStore = $null
        $assetById = @{}
        $assignedAssetIds = @{}
    }
    $assetConflictCount = 0
    foreach ($client in $script:serverClients) {
        $item = New-Object Windows.Forms.ListViewItem([string]$client.ComputerName)
        $assetId = if ($client.PSObject.Properties['AssetId']) { [string]$client.AssetId } else { '' }
        $assetRecord = if ($assetId -and $assetById.ContainsKey($assetId)) { $assetById[$assetId] } else { $null }
        $assetReference = if ($assetRecord -and (Get-Command Get-ToolEnterpriseAssetReference -ErrorAction SilentlyContinue)) {
            Get-ToolEnterpriseAssetReference -Asset $assetRecord
        } elseif ($assetId.Length -ge 8) {
            'ASSET-' + $assetId.Substring($assetId.Length - 8)
        } else {
            Get-EnterpriseText 'enterprise.server.assetPending'
        }
        $assignment = if ($assetStore -and $assetId) { Get-ToolCurrentAssetAssignment -Store $assetStore -AssetId $assetId } else { $null }
        $assignmentName = if ($assignment -and -not [string]::IsNullOrWhiteSpace([string]$assignment.DisplayName)) {
            [string]$assignment.DisplayName
        } elseif ($client.PSObject.Properties['AssignmentDisplayName'] -and -not [string]::IsNullOrWhiteSpace([string]$client.AssignmentDisplayName)) {
            [string]$client.AssignmentDisplayName
        } else {
            Get-EnterpriseText 'enterprise.server.assetUnassigned'
        }
        if ($client.PSObject.Properties['AssetMatchStatus'] -and [string]$client.AssetMatchStatus -in @('Conflict','Ambiguous')) {
            $assetConflictCount++
        }
        [void]$item.SubItems.Add($assetReference)
        [void]$item.SubItems.Add($assignmentName)
        [void]$item.SubItems.Add([string]$client.RemoteAddress)
        [void]$item.SubItems.Add([string]$client.LastSeenUtc)
        $activationText = "{0} / {1}" -f [string]$client.WindowsStatus, [string]$client.OfficeStatus
        $windowsIdentityChanged = [bool]($client.PSObject.Properties['WindowsIdentityChanged'] -and $client.WindowsIdentityChanged)
        $officeIdentityChanged = [bool]($client.PSObject.Properties['OfficeIdentityChanged'] -and $client.OfficeIdentityChanged)
        if ($windowsIdentityChanged -or $officeIdentityChanged) {
            $activationText += " | " + (Get-EnterpriseText "enterprise.server.identityChanged")
        }
        [void]$item.SubItems.Add($activationText)
        [void]$item.SubItems.Add([string]$client.ClientId)
        $item.Tag = $client
        [void]$script:serverClientList.Items.Add($item)
    }
    $assetCount = if ($assetStore) { @($assetStore.Assets).Count } else { 0 }
    $script:serverAssetStore = $assetStore
    $unassignedAssetCount = [Math]::Max(0, ($assetCount - $assignedAssetIds.Count))
    $script:clientCountLabel.Text = Get-EnterpriseText 'enterprise.server.assetSummary' @(
        $script:serverClients.Count, $assetCount, $assignedAssetIds.Count, $unassignedAssetCount, $assetConflictCount
    )
    Update-EnterpriseServerAssetDetails
}

function Update-EnterpriseServerAssetDetails {
    if (-not $script:serverAssetDetailLabel) { return }
    $selected = Get-SelectedEnterpriseClient
    if (-not $selected) {
        $script:serverAssetDetailLabel.Text = Get-EnterpriseText 'enterprise.server.assetDetailsEmpty'
        return
    }

    $assetId = if ($selected.PSObject.Properties['AssetId']) { [string]$selected.AssetId } else { '' }
    $deviceId = if ($selected.PSObject.Properties['DeviceId']) { [string]$selected.DeviceId } else { '' }
    $assetReference = if ($assetId.Length -ge 8) { 'ASSET-' + $assetId.Substring($assetId.Length - 8) } else { Get-EnterpriseText 'enterprise.server.assetPending' }
    $deviceReference = if ($deviceId.Length -ge 8) { 'DEVICE-' + $deviceId.Substring($deviceId.Length - 8) } else { '--' }
    $assetStatus = if ($selected.PSObject.Properties['AssetMatchStatus'] -and -not [string]::IsNullOrWhiteSpace([string]$selected.AssetMatchStatus)) { [string]$selected.AssetMatchStatus } else { '--' }
    $assignmentName = Get-EnterpriseText 'enterprise.server.assetUnassigned'
    $historyCount = 0

    try {
        if ($script:serverAssetStore -and $assetId) {
            $assetRecord = @($script:serverAssetStore.Assets | Where-Object { [string]$_.AssetId -eq $assetId } | Select-Object -First 1)
            if ($assetRecord.Count -gt 0 -and (Get-Command Get-ToolEnterpriseAssetReference -ErrorAction SilentlyContinue)) {
                $assetReference = Get-ToolEnterpriseAssetReference -Asset $assetRecord[0]
                if (-not [string]::IsNullOrWhiteSpace([string]$assetRecord[0].Status)) { $assetStatus = [string]$assetRecord[0].Status }
            }
            $assignment = Get-ToolCurrentAssetAssignment -Store $script:serverAssetStore -AssetId $assetId
            if ($assignment -and -not [string]::IsNullOrWhiteSpace([string]$assignment.DisplayName)) { $assignmentName = [string]$assignment.DisplayName }
            $historyCount = @(Get-ToolAssetAssignmentHistory -Store $script:serverAssetStore -AssetId $assetId).Count
        }
    } catch {}

    $script:serverAssetDetailLabel.Text = Get-EnterpriseText 'enterprise.server.assetDetailsLine' @(
        $assetReference, $deviceReference, $assetStatus, $assignmentName, $historyCount
    )
}

function Update-EnterpriseClientAssetSummary {
    if (-not $script:clientAssetSummaryLabel) { return }
    $deviceReference = '--'
    $enrollment = Get-EnterpriseText 'enterprise.client.assetNotEnrolled'
    $serverDisplay = '--'
    $lastSync = Get-EnterpriseText 'enterprise.client.assetNeverSynced'
    try {
        $identity = Get-ToolEnterpriseAssetIdentitySnapshot
        if ($identity -and [string]$identity.DeviceId -and ([string]$identity.DeviceId).Length -ge 8) {
            $deviceReference = 'DEVICE-' + ([string]$identity.DeviceId).Substring(([string]$identity.DeviceId).Length - 8)
        }
        $cfg = Get-ToolEnterpriseClientConfig
        if ($cfg) {
            $enrollment = Get-EnterpriseText $(if ([bool]$cfg.Enrolled) { 'enterprise.client.assetEnrolled' } else { 'enterprise.client.assetNotEnrolled' })
            if (-not [string]::IsNullOrWhiteSpace([string]$cfg.ServerAddress)) { $serverDisplay = '{0}:{1}' -f [string]$cfg.ServerAddress,[int]$cfg.Port }
        }
        $paths = Get-ToolEnterprisePaths
        if (Test-Path -LiteralPath $paths.ClientAgentResult -PathType Leaf) {
            $result = Read-ToolEnterpriseJson -Path $paths.ClientAgentResult -MaximumBytes 65536
            if ($result -and -not [string]::IsNullOrWhiteSpace([string]$result.CompletedAtUtc)) {
                try { $lastSync = ([DateTimeOffset]::Parse([string]$result.CompletedAtUtc)).ToLocalTime().ToString('g') }
                catch { $lastSync = ConvertTo-ToolEnterpriseSafeText $result.CompletedAtUtc 80 }
            }
        }
    } catch {}
    $script:clientAssetSummaryLabel.Text = Get-EnterpriseText 'enterprise.client.assetSummary' @($deviceReference,$enrollment,$serverDisplay,$lastSync)
}

function Show-EnterpriseAssetAssignmentDialog {
    param(
        [Parameter(Mandatory=$true)][object]$Asset,
        [AllowNull()][object]$CurrentAssignment
    )

    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = Get-EnterpriseText 'enterprise.assetManager.assignmentTitle'
    $dialog.StartPosition = 'CenterParent'
    $dialog.Size = New-Object Drawing.Size(610,390)
    $dialog.MinimumSize = New-Object Drawing.Size(610,390)
    $dialog.MaximumSize = New-Object Drawing.Size(610,390)
    $dialog.BackColor = [Drawing.Color]::White
    $dialog.Font = $script:enterpriseUiFont

    $assetReference = Get-ToolEnterpriseAssetReference -Asset $Asset
    $assetLabel = New-EnterpriseLabel (Get-EnterpriseText 'enterprise.assetManager.assetSelected' @($assetReference)) 20 18 550 25
    $dialog.Controls.Add($assetLabel)

    $typeLabel = New-EnterpriseLabel (Get-EnterpriseText 'enterprise.assetManager.assigneeType') 20 62 170 24
    $typeBox = New-Object Windows.Forms.ComboBox
    $typeBox.Location = New-Object Drawing.Point(200,60)
    $typeBox.Size = New-Object Drawing.Size(360,26)
    $typeBox.DropDownStyle = 'DropDownList'
    [void]$typeBox.Items.AddRange([object[]]@('User','Department','Location','Custodian'))
    $typeBox.SelectedItem = if ($CurrentAssignment -and [string]$CurrentAssignment.AssigneeType) { [string]$CurrentAssignment.AssigneeType } else { 'User' }

    $referenceLabel = New-EnterpriseLabel (Get-EnterpriseText 'enterprise.assetManager.assigneeReference') 20 104 170 24
    $referenceBox = New-EnterpriseTextBox 200 102 360
    if ($CurrentAssignment) { $referenceBox.Text = [string]$CurrentAssignment.AssigneeReference }

    $displayLabel = New-EnterpriseLabel (Get-EnterpriseText 'enterprise.assetManager.displayName') 20 146 170 24
    $displayBox = New-EnterpriseTextBox 200 144 360
    if ($CurrentAssignment) { $displayBox.Text = [string]$CurrentAssignment.DisplayName }

    $reasonLabel = New-EnterpriseLabel (Get-EnterpriseText 'enterprise.assetManager.reason') 20 188 170 24
    $reasonBox = New-EnterpriseTextBox 200 186 360 75 $true

    foreach ($control in @($typeLabel,$typeBox,$referenceLabel,$referenceBox,$displayLabel,$displayBox,$reasonLabel,$reasonBox)) {
        $dialog.Controls.Add($control)
    }

    $saveButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.assetManager.save') 330 292 110 34 {}
    $cancelButton = New-EnterpriseButton (Get-EnterpriseText 'report.privacy.cancelButton') 450 292 110 34 { $dialog.DialogResult=[Windows.Forms.DialogResult]::Cancel; $dialog.Close() }
    $saveButton.Add_Click(({
        try {
            if ([string]::IsNullOrWhiteSpace($referenceBox.Text)) { throw (Get-EnterpriseText 'enterprise.assetManager.referenceRequired') }
            $dialog.Tag = [pscustomobject][ordered]@{
                AssigneeType = [string]$typeBox.SelectedItem
                AssigneeReference = $referenceBox.Text.Trim()
                DisplayName = $displayBox.Text.Trim()
                Reason = $reasonBox.Text.Trim()
            }
            $dialog.DialogResult = [Windows.Forms.DialogResult]::OK
            $dialog.Close()
        } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 800) }
    }).GetNewClosure())
    $dialog.Controls.Add($saveButton)
    $dialog.Controls.Add($cancelButton)
    $dialog.AcceptButton = $saveButton
    $dialog.CancelButton = $cancelButton

    if ($dialog.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK) { return $null }
    return $dialog.Tag
}

function Show-EnterpriseAssetHistoryDialog {
    param(
        [Parameter(Mandatory=$true)][object]$Store,
        [Parameter(Mandatory=$true)][object]$Asset
    )

    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = Get-EnterpriseText 'enterprise.assetManager.historyTitle' @((Get-ToolEnterpriseAssetReference -Asset $Asset))
    $dialog.StartPosition = 'CenterParent'
    $dialog.Size = New-Object Drawing.Size(960,520)
    $dialog.MinimumSize = New-Object Drawing.Size(820,460)
    $dialog.BackColor = [Drawing.Color]::White
    $dialog.Font = $script:enterpriseUiFont

    $list = New-Object Windows.Forms.ListView
    $list.Location = New-Object Drawing.Point(14,14)
    $list.Size = New-Object Drawing.Size(915,395)
    $list.Anchor = 'Top,Bottom,Left,Right'
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.GridLines = $true
    foreach ($column in @(
        @((Get-EnterpriseText 'enterprise.assetManager.sequence'),55),
        @((Get-EnterpriseText 'enterprise.assetManager.action'),90),
        @((Get-EnterpriseText 'enterprise.assetManager.assignedTo'),170),
        @((Get-EnterpriseText 'enterprise.assetManager.effectiveAt'),150),
        @((Get-EnterpriseText 'enterprise.assetManager.recordedBy'),115),
        @((Get-EnterpriseText 'enterprise.assetManager.reason'),300)
    )) { [void]$list.Columns.Add($column[0],[int]$column[1]) }

    $history = @(Get-ToolAssetAssignmentHistory -Store $Store -AssetId ([string]$Asset.AssetId))
    foreach ($event in $history) {
        $item = New-Object Windows.Forms.ListViewItem([string]$event.Sequence)
        [void]$item.SubItems.Add([string]$event.Action)
        $assignedTo = if ([string]$event.Action -eq 'Release') { '--' } elseif ([string]::IsNullOrWhiteSpace([string]$event.DisplayName)) { [string]$event.AssigneeReference } else { [string]$event.DisplayName }
        [void]$item.SubItems.Add($assignedTo)
        [void]$item.SubItems.Add([string]$event.EffectiveAtUtc)
        [void]$item.SubItems.Add([string]$event.RecordedBy)
        [void]$item.SubItems.Add([string]$event.Reason)
        [void]$list.Items.Add($item)
    }
    if ($history.Count -eq 0) {
        $item = New-Object Windows.Forms.ListViewItem('--')
        [void]$item.SubItems.Add((Get-EnterpriseText 'enterprise.assetManager.noHistory'))
        [void]$list.Items.Add($item)
    }
    $dialog.Controls.Add($list)
    $closeButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.navigation.close') 780 420 150 34 { $dialog.Close() }
    $closeButton.Anchor = 'Bottom,Right'
    $dialog.Controls.Add($closeButton)
    [void]$dialog.ShowDialog($form)
}

function Show-EnterpriseAssetRegistryManager {
    try {
        foreach ($requiredCommand in @('Read-ToolAssetRegistryStore','Write-ToolAssetRegistryStore','Add-ToolAssetAssignmentEvent','Get-ToolCurrentAssetAssignment','Get-ToolAssetAssignmentHistory')) {
            if (-not (Get-Command $requiredCommand -ErrorAction SilentlyContinue)) { throw (Get-EnterpriseText 'enterprise.assetManager.unavailable') }
        }

        $dialog = New-Object Windows.Forms.Form
        $dialog.Text = Get-EnterpriseText 'enterprise.assetManager.title'
        $dialog.StartPosition = 'CenterParent'
        $dialog.Size = New-Object Drawing.Size(1080,700)
        $dialog.MinimumSize = New-Object Drawing.Size(920,620)
        $dialog.BackColor = [Drawing.Color]::White
        $dialog.Font = $script:enterpriseUiFont

        $filterLabel = New-EnterpriseLabel (Get-EnterpriseText 'enterprise.assetManager.filter') 14 18 110 25
        $filterBox = New-EnterpriseTextBox 125 15 560
        $dialog.Controls.Add($filterLabel)
        $dialog.Controls.Add($filterBox)

        $list = New-Object Windows.Forms.ListView
        $list.Location = New-Object Drawing.Point(14,52)
        $list.Size = New-Object Drawing.Size(700,555)
        $list.Anchor = 'Top,Bottom,Left,Right'
        $list.View = 'Details'
        $list.FullRowSelect = $true
        $list.GridLines = $true
        foreach ($column in @(
            @((Get-EnterpriseText 'enterprise.assetManager.asset'),125),
            @((Get-EnterpriseText 'enterprise.assetManager.device'),125),
            @((Get-EnterpriseText 'enterprise.assetManager.status'),85),
            @((Get-EnterpriseText 'enterprise.assetManager.assignedTo'),150),
            @((Get-EnterpriseText 'enterprise.assetManager.history'),65),
            @((Get-EnterpriseText 'enterprise.assetManager.updatedAt'),135)
        )) { [void]$list.Columns.Add($column[0],[int]$column[1]) }
        $dialog.Controls.Add($list)

        $detailGroup = New-Object Windows.Forms.GroupBox
        $detailGroup.Text = Get-EnterpriseText 'enterprise.assetManager.details'
        $detailGroup.Location = New-Object Drawing.Point(730,52)
        $detailGroup.Size = New-Object Drawing.Size(315,250)
        $detailGroup.Anchor = 'Top,Right'
        $detailLabel = New-EnterpriseLabel (Get-EnterpriseText 'enterprise.assetManager.selectAsset') 12 25 285 205
        $detailGroup.Controls.Add($detailLabel)
        $dialog.Controls.Add($detailGroup)

        $state = [pscustomobject]@{ Store=$null; Assets=@(); SelectedAsset=$null }
        $refresh = {
            try {
                $selectedAssetId = if ($state.SelectedAsset) { [string]$state.SelectedAsset.AssetId } else { '' }
                $state.Store = Read-ToolAssetRegistryStore -RootPath (Initialize-ToolEnterpriseStorage).ServerAssets -CreateIfMissing
                $state.Assets = @($state.Store.Assets | Sort-Object UpdatedAtUtc -Descending)
                $list.Items.Clear()
                $needle = $filterBox.Text.Trim().ToLowerInvariant()
                foreach ($asset in $state.Assets) {
                    $assignment = Get-ToolCurrentAssetAssignment -Store $state.Store -AssetId ([string]$asset.AssetId)
                    $historyCount = @(Get-ToolAssetAssignmentHistory -Store $state.Store -AssetId ([string]$asset.AssetId)).Count
                    $assetReference = Get-ToolEnterpriseAssetReference -Asset $asset
                    $deviceId = [string]$asset.DeviceId
                    $deviceReference = if ($deviceId.Length -ge 8) { 'DEVICE-' + $deviceId.Substring($deviceId.Length - 8) } else { '--' }
                    $assignedTo = if ($assignment -and -not [string]::IsNullOrWhiteSpace([string]$assignment.DisplayName)) { [string]$assignment.DisplayName } elseif ($assignment) { [string]$assignment.AssigneeReference } else { Get-EnterpriseText 'enterprise.server.assetUnassigned' }
                    $haystack = @($assetReference,$deviceReference,[string]$asset.Status,$assignedTo,[string]$asset.InventoryNumber,[string]$asset.ExternalAssetTag) -join ' '
                    if ($needle -and $haystack.ToLowerInvariant().IndexOf($needle) -lt 0) { continue }
                    $item = New-Object Windows.Forms.ListViewItem($assetReference)
                    [void]$item.SubItems.Add($deviceReference)
                    [void]$item.SubItems.Add([string]$asset.Status)
                    [void]$item.SubItems.Add($assignedTo)
                    [void]$item.SubItems.Add([string]$historyCount)
                    [void]$item.SubItems.Add([string]$asset.UpdatedAtUtc)
                    $item.Tag = [string]$asset.AssetId
                    [void]$list.Items.Add($item)
                    if ($selectedAssetId -and [string]$asset.AssetId -eq $selectedAssetId) { $item.Selected=$true; $item.Focused=$true }
                }
                if ($list.Items.Count -eq 0) { $detailLabel.Text = Get-EnterpriseText 'enterprise.assetManager.empty' }
            } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
        }
        $updateDetails = {
            $state.SelectedAsset = $null
            if ($list.SelectedItems.Count -ne 1 -or -not $state.Store) {
                $detailLabel.Text = Get-EnterpriseText 'enterprise.assetManager.selectAsset'
                return
            }
            $assetId = [string]$list.SelectedItems[0].Tag
            $asset = @($state.Store.Assets | Where-Object { [string]$_.AssetId -eq $assetId } | Select-Object -First 1)
            if ($asset.Count -eq 0) { return }
            $state.SelectedAsset = $asset[0]
            $assignment = Get-ToolCurrentAssetAssignment -Store $state.Store -AssetId $assetId
            $historyCount = @(Get-ToolAssetAssignmentHistory -Store $state.Store -AssetId $assetId).Count
            $assignedTo = if ($assignment -and -not [string]::IsNullOrWhiteSpace([string]$assignment.DisplayName)) { [string]$assignment.DisplayName } elseif ($assignment) { [string]$assignment.AssigneeReference } else { Get-EnterpriseText 'enterprise.server.assetUnassigned' }
            $detailLabel.Text = Get-EnterpriseText 'enterprise.assetManager.detailLine' @(
                (Get-ToolEnterpriseAssetReference -Asset $asset[0]),
                [string]$asset[0].DeviceId,
                [string]$asset[0].Status,
                $assignedTo,
                $historyCount,
                [string]$asset[0].UpdatedAtUtc
            )
        }
        $assignAction = {
            try {
                if (-not $state.SelectedAsset) { throw (Get-EnterpriseText 'enterprise.assetManager.selectAsset') }
                $current = Get-ToolCurrentAssetAssignment -Store $state.Store -AssetId ([string]$state.SelectedAsset.AssetId)
                $input = Show-EnterpriseAssetAssignmentDialog -Asset $state.SelectedAsset -CurrentAssignment $current
                if ($null -eq $input) { return }
                $action = if ($current) { 'Reassign' } else { 'Assign' }
                [void](Add-ToolAssetAssignmentEvent -Store $state.Store -AssetId ([string]$state.SelectedAsset.AssetId) -Action $action -AssigneeType ([string]$input.AssigneeType) -AssigneeReference ([string]$input.AssigneeReference) -DisplayName ([string]$input.DisplayName) -Reason ([string]$input.Reason) -RecordedBy ([Environment]::UserName))
                [void](Write-ToolAssetRegistryStore -Store $state.Store -RootPath (Initialize-ToolEnterpriseStorage).ServerAssets)
                Set-EnterpriseStatus (Get-EnterpriseText 'enterprise.assetManager.assignmentSaved') $true
                & $refresh
                Update-ServerClientList
            } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
        }
        $releaseAction = {
            try {
                if (-not $state.SelectedAsset) { throw (Get-EnterpriseText 'enterprise.assetManager.selectAsset') }
                $current = Get-ToolCurrentAssetAssignment -Store $state.Store -AssetId ([string]$state.SelectedAsset.AssetId)
                if (-not $current) { throw (Get-EnterpriseText 'enterprise.assetManager.notAssigned') }
                if (-not (Confirm-EnterpriseAction (Get-EnterpriseText 'enterprise.assetManager.confirmRelease' @((Get-ToolEnterpriseAssetReference -Asset $state.SelectedAsset))))) { return }
                [void](Add-ToolAssetAssignmentEvent -Store $state.Store -AssetId ([string]$state.SelectedAsset.AssetId) -Action Release -Reason (Get-EnterpriseText 'enterprise.assetManager.releaseReason') -RecordedBy ([Environment]::UserName))
                [void](Write-ToolAssetRegistryStore -Store $state.Store -RootPath (Initialize-ToolEnterpriseStorage).ServerAssets)
                Set-EnterpriseStatus (Get-EnterpriseText 'enterprise.assetManager.released') $true
                & $refresh
                Update-ServerClientList
            } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
        }
        $historyAction = {
            try {
                if (-not $state.SelectedAsset) { throw (Get-EnterpriseText 'enterprise.assetManager.selectAsset') }
                Show-EnterpriseAssetHistoryDialog -Store $state.Store -Asset $state.SelectedAsset
            } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
        }

        $list.Add_SelectedIndexChanged(({$updateDetails.Invoke()}).GetNewClosure())
        $filterBox.Add_TextChanged(({$refresh.Invoke()}).GetNewClosure())
        $assignButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.assetManager.assignOrReassign') 730 320 315 36 ($assignAction.GetNewClosure())
        $releaseButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.assetManager.release') 730 366 315 36 ($releaseAction.GetNewClosure())
        $historyButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.assetManager.viewHistory') 730 412 315 36 ($historyAction.GetNewClosure())
        $refreshButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.assetManager.refresh') 730 458 315 36 ($refresh.GetNewClosure())
        $closeButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.navigation.close') 895 610 150 34 { $dialog.Close() }
        $closeButton.Anchor = 'Bottom,Right'
        foreach ($button in @($assignButton,$releaseButton,$historyButton,$refreshButton,$closeButton)) { $dialog.Controls.Add($button) }

        & $refresh
        [void]$dialog.ShowDialog($form)
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1200) }
}

function Get-SelectedEnterpriseClient {
    if (-not $script:serverClientList -or $script:serverClientList.SelectedItems.Count -eq 0) { return $null }
    return $script:serverClientList.SelectedItems[0].Tag
}

function Test-EnterpriseDuplicateServer {
    param([string[]]$Addresses, [int]$Port)
    $localConfig = Get-EnterpriseServerConfigurationSafe
    $localAddresses = @("127.0.0.1") + @(Get-ToolEnterpriseLocalIPv4Addresses)
    foreach ($address in @($Addresses)) {
        if ([string]::IsNullOrWhiteSpace($address)) { continue }
        $status = Test-ToolEnterpriseServerConnection -ServerAddress $address -Port $Port -TimeoutMs 500
        if ($status -and $localConfig -and $address -notin $localAddresses) {
            return $status
        }
    }
    return $null
}

function Invoke-ServerCreate {
    try {
        $serverName = $script:serverNameBox.Text.Trim()
        $adminCode = $script:serverAdminBox.Text
        $port = [int]$script:serverPortBox.Text
        $cidrs = @($script:serverCidrBox.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($adminCode.Length -lt 8) { throw (Get-EnterpriseText "enterprise.error.adminCodeLength") }
        if (Get-EnterpriseServerConfigurationSafe) { throw (Get-EnterpriseText "enterprise.error.serverAlreadyConfigured") }
        $cfg = New-ToolEnterpriseServerConfiguration -ServerName $serverName -AdminCode $adminCode -Port $port -AllowedCidrs $cidrs
        $script:config = $cfg
        $detectedAddress = Update-EnterpriseDetectedServerAddress
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.createdStatus" @($cfg.ServerName, $detectedAddress, $cfg.AuthorityFingerprint)) $true
        [Windows.Forms.MessageBox]::Show(
            (Get-EnterpriseText "enterprise.server.createdMessage"),
            (Get-EnterpriseText "enterprise.server.messageTitle"),
            "OK",
            "Information"
        ) | Out-Null
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
}

function Invoke-ServerPairingCode {
    try {
        $adminCode = $script:serverAdminBox.Text
        $code = Reset-ToolEnterprisePairingCode -AdminCode $adminCode -ValidHours 24
        $script:pairingOutputBox.Text = $code
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.pairCreated") $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 900) }
}

function Enable-EnterpriseServerListenerAccess {
    param([Parameter(Mandatory = $true)][object]$Configuration)

    $netsh = Join-Path $env:SystemRoot "System32\netsh.exe"
    if (-not (Test-Path -LiteralPath $netsh -PathType Leaf)) { throw (Get-EnterpriseText "enterprise.error.netshMissing") }
    $port = [int]$Configuration.Port
    $url = "http://+:$port/tool/v1/"
    $currentUserSid = [string][Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ([string]::IsNullOrWhiteSpace($currentUserSid) -or $currentUserSid -notmatch '^S-1-') {
        throw (Get-EnterpriseText 'enterprise.error.urlAclIdentityMissing')
    }
    $show = & $netsh http show urlacl url=$url 2>$null | Out-String
    $systemSid = 'S-1-5-18'
    $reservationMatchesRequiredPrincipals = [bool](
        $show -match [regex]::Escape($url) -and
        $show -match [regex]::Escape($currentUserSid) -and
        ($show -match [regex]::Escape($systemSid) -or $show -match ';;;SY')
    )
    if (-not $reservationMatchesRequiredPrincipals) {
        # The dashboard and host intentionally run without a permanent elevated
        # token. Reserve the exact strong-wildcard URL for the current account,
        # not merely for the Administrators group (deny-only under filtered UAC).
        if ($show -match [regex]::Escape($url)) {
            $deleteProcess = Start-Process -FilePath $netsh -ArgumentList "http delete urlacl url=$url" -Verb RunAs -Wait -PassThru -WindowStyle Hidden
            if ($deleteProcess.ExitCode -ne 0) { throw (Get-EnterpriseText "enterprise.error.netshExit" @($deleteProcess.ExitCode)) }
        }
        # The dashboard starts the first listener as the current user; the
        # persisted boot task starts it as LocalSystem. Grant only these two
        # principals permission to listen on this exact URL.
        $aclArgs = "http add urlacl url=$url sddl=D:(A;;GX;;;$currentUserSid)(A;;GX;;;SY)"
        $aclProcess = Start-Process -FilePath $netsh -ArgumentList $aclArgs -Verb RunAs -Wait -PassThru -WindowStyle Hidden
        if ($aclProcess.ExitCode -ne 0) { throw (Get-EnterpriseText "enterprise.error.netshExit" @($aclProcess.ExitCode)) }
    }
    $showAfter = & $netsh http show urlacl url=$url 2>$null | Out-String
    if ($showAfter -notmatch [regex]::Escape($url) -or
        $showAfter -notmatch [regex]::Escape($currentUserSid) -or
        ($showAfter -notmatch [regex]::Escape($systemSid) -and $showAfter -notmatch ';;;SY')) {
        throw (Get-EnterpriseText 'enterprise.error.urlAclNotApplied' @($url))
    }

    $firewallName = "ThanhViet Tool $($script:enterpriseInfrastructureVersion) Enterprise Server"
    $firewallReady = $false
    if (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) {
        try {
            $firewallReady = [bool](@(Get-NetFirewallRule -DisplayName $firewallName -ErrorAction SilentlyContinue |
                Where-Object { [string]$_.Enabled -eq 'True' } |
                Get-NetFirewallPortFilter -ErrorAction SilentlyContinue |
                Where-Object { [string]$_.Protocol -eq 'TCP' -and @([string]$_.LocalPort -split ',') -contains [string]$port }).Count -gt 0)
        } catch {}
    }
    if (-not $firewallReady) {
        $firewallArguments = 'advfirewall firewall add rule name="' + $firewallName + '" dir=in action=allow protocol=TCP localport=' + $port + ' profile=domain,private'
        $firewallProcess = Start-Process -FilePath $netsh -ArgumentList $firewallArguments -Verb RunAs -Wait -PassThru -WindowStyle Hidden
        if ($firewallProcess.ExitCode -ne 0) { throw (Get-EnterpriseText "enterprise.error.netshExit" @($firewallProcess.ExitCode)) }
    }
    if (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) {
        $verifiedFirewall = [bool](@(Get-NetFirewallRule -DisplayName $firewallName -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.Enabled -eq 'True' -and [string]$_.Direction -eq 'Inbound' -and [string]$_.Action -eq 'Allow' } |
            Get-NetFirewallPortFilter -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.Protocol -eq 'TCP' -and @([string]$_.LocalPort -split ',') -contains [string]$port }).Count -gt 0)
        if (-not $verifiedFirewall) { throw (Get-EnterpriseText 'enterprise.error.firewallNotApplied' @($port)) }
    }
}

function Remove-EnterpriseServerNetworkAccess {
    param([ValidateRange(1024, 65535)][int]$Port)

    $warnings = New-Object System.Collections.Generic.List[string]
    $netsh = Join-Path $env:SystemRoot "System32\netsh.exe"
    if (-not (Test-Path -LiteralPath $netsh -PathType Leaf)) {
        [void]$warnings.Add((Get-EnterpriseText "enterprise.server.revokeNetshMissing"))
        return $warnings.ToArray()
    }

    $url = "http://+:$Port/tool/v1/"
    try {
        $show = & $netsh http show urlacl 2>$null | Out-String
        if ($show -match [regex]::Escape($url)) {
            $process = Start-Process -FilePath $netsh -ArgumentList "http delete urlacl url=$url" -Wait -PassThru -WindowStyle Hidden
            if ($process.ExitCode -ne 0) { [void]$warnings.Add((Get-EnterpriseText "enterprise.server.revokeUrlExit" @($url, $process.ExitCode))) }
        }
    } catch {
        [void]$warnings.Add((Get-EnterpriseText "enterprise.server.revokeUrlFailed" @($url)))
    }

    try {
        foreach ($firewallName in @("ThanhViet Tool $($script:enterpriseInfrastructureVersion) Enterprise Server",'ThanhViet Tool v4.8 Enterprise Server','ThanhViet Tool v4.6 Enterprise Server') | Select-Object -Unique) {
            $firewallArguments = 'advfirewall firewall delete rule name="' + $firewallName + '" protocol=TCP localport=' + $Port
            $process = Start-Process -FilePath $netsh -ArgumentList $firewallArguments -Wait -PassThru -WindowStyle Hidden
            if ($process.ExitCode -ne 0) { [void]$warnings.Add((Get-EnterpriseText "enterprise.server.revokeFirewallExit" @($Port, $process.ExitCode))) }
        }
    } catch {
        [void]$warnings.Add((Get-EnterpriseText "enterprise.server.revokeFirewallFailed" @($Port)))
    }
    return $warnings.ToArray()
}

function Invoke-ServerDeleteConfiguration {
    try {
        $cfg = Get-EnterpriseServerConfigurationSafe
        if (-not $cfg) { throw (Get-EnterpriseText "enterprise.error.noServerConfiguration") }
        $adminCode = $script:serverAdminBox.Text
        if ([string]::IsNullOrWhiteSpace($adminCode)) { throw (Get-EnterpriseText "enterprise.error.adminCodeRequired") }
        if (-not (Test-ToolEnterpriseAdminCode -AdminCode $adminCode -Verifier $cfg.AdminVerifier)) {
            throw (Get-EnterpriseText "enterprise.error.adminCodeInvalid")
        }

        $message = Get-EnterpriseText "enterprise.server.deletePrompt" @($cfg.ServerName)
        if (-not (Confirm-EnterpriseAction $message)) { return }

        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.deleting") $true
        [void](Remove-EnterpriseLifecycleTasks -Role Server)
        $result = Remove-ToolEnterpriseServerConfiguration -AdminCode $adminCode -StopTimeoutSeconds 12
        $networkWarnings = @(Remove-EnterpriseServerNetworkAccess -Port ([int]$result.Port))

        $script:config = $null
        $script:serverAdminBox.Clear()
        $script:pairingOutputBox.Clear()
        $script:serverNameBox.Text = [Environment]::MachineName
        $script:serverPortBox.Text = [string]$script:ToolEnterpriseDefaultPort
        $localCidrs = @(Get-ToolEnterpriseLocalCidrs)
        $script:serverCidrBox.Text = ""
        $script:scanInputBox.Text = if ($localCidrs.Count -gt 0) { [string]$localCidrs[0] } else { "" }
        Update-ServerClientList
        [void](Update-EnterpriseDetectedServerAddress)

        $summary = Get-EnterpriseText "enterprise.server.deleted"
        if ($networkWarnings.Count -gt 0) {
            $summary += (Get-EnterpriseText "enterprise.server.warningPrefix") + ($networkWarnings -join " ")
        }
        Set-EnterpriseStatus $summary ($networkWarnings.Count -eq 0)
        [Windows.Forms.MessageBox]::Show(
            $summary + [Environment]::NewLine + [Environment]::NewLine +
            (Get-EnterpriseText "enterprise.server.deletedNext"),
            (Get-EnterpriseText "enterprise.server.deletedTitle"),
            "OK",
            $(if ($networkWarnings.Count -eq 0) { "Information" } else { "Warning" })
        ) | Out-Null
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1200) }
}

function Invoke-ServerStart {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.startServer")) { return }
        $cfg = Get-EnterpriseServerConfigurationSafe
        if (-not $cfg) { throw (Get-EnterpriseText "enterprise.error.createServerFirst") }
        $duplicate = $null
        $localAddresses = @("127.0.0.1") + @(Get-ToolEnterpriseLocalIPv4Addresses)
        foreach ($cidr in @($cfg.AllowedCidrs)) {
            $info = Get-ToolEnterpriseCidrInfo -Cidr ([string]$cidr)
            if ([uint64]$info.HostCount -gt 1024) {
                throw (Get-EnterpriseText "enterprise.error.cidrTooLargeDuplicate" @($info.Cidr))
            }
            foreach ($foundServer in @(Find-ToolEnterpriseServers -Cidr $info.Cidr -Port ([int]$cfg.Port) -TimeoutMs 450 -ThrottleLimit 64)) {
                if ([string]$foundServer.Address -notin $localAddresses) { $duplicate = $foundServer; break }
            }
            if ($duplicate) { break }
        }
        if ($duplicate) {
            throw (Get-EnterpriseText "enterprise.error.duplicateServer" @($duplicate.ServerName, $duplicate.Address))
        }
        if (-not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.server.startPrompt" @($cfg.Port)))) { return }
        Enable-EnterpriseServerListenerAccess -Configuration $cfg
        $launcher = Get-EnterpriseLauncherPath
        if (-not $launcher) { throw (Get-EnterpriseText "enterprise.error.oneFileRequired") }
        $paths = Get-ToolEnterprisePaths
        foreach ($stalePath in @($paths.ServerError,$paths.ServerPid,$paths.ServerHeartbeat)) {
            if (Test-Path -LiteralPath $stalePath -PathType Leaf) { Remove-Item -LiteralPath $stalePath -Force -ErrorAction SilentlyContinue }
        }
        Set-EnterpriseStatus (Get-EnterpriseText 'enterprise.server.startingVerified' @($cfg.Port)) $true
        $script:serverProcess = Start-EnterpriseChild -Role Server
        $ready = Wait-EnterpriseServerReady -Configuration $cfg -LauncherProcess $script:serverProcess -TimeoutSeconds 18
        # Persist startup only after the listener has proved ready. A failed
        # interactive start must never leave a broken boot task behind.
        $serverTaskName = Install-EnterpriseLifecycleTask -Role Server -LauncherPath $launcher
        $detectedAddress = Update-EnterpriseDetectedServerAddress
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.startedWithAutostart" @($detectedAddress, $cfg.Port, $ready.ProcessId, $serverTaskName)) $true
    } catch {
        try {
            $paths = Get-ToolEnterprisePaths
            New-Item -ItemType File -Path $paths.ServerStop -Force | Out-Null
            if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
                if (-not $script:serverProcess.WaitForExit(1800)) {
                    Stop-Process -Id $script:serverProcess.Id -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {}
        Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1200)
    }
}

function Invoke-ServerScan {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.scan")) { return }
        $input = $script:scanInputBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($input)) {
            $scanCandidates = New-Object System.Collections.Generic.List[string]
            $cfg = Get-EnterpriseServerConfigurationSafe
            if ($cfg) {
                foreach ($allowedCidr in @($cfg.AllowedCidrs)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$allowedCidr)) {
                        [void]$scanCandidates.Add([string]$allowedCidr)
                    }
                }
            }
            if ($scanCandidates.Count -eq 0) {
                foreach ($localCidr in @(Get-ToolEnterpriseLocalCidrs)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$localCidr)) {
                        [void]$scanCandidates.Add([string]$localCidr)
                    }
                }
            }
            if ($scanCandidates.Count -eq 0) { throw (Get-EnterpriseText "enterprise.error.noCidr") }
            $input = [string]$scanCandidates[0]
            $script:scanInputBox.Text = $input
        }
        $cidr = if ($input -match "/") { $input } else { "$input/32" }
        $info = Get-ToolEnterpriseCidrInfo -Cidr $cidr
        if ([uint64]$info.HostCount -gt 1024) { throw (Get-EnterpriseText "enterprise.error.scanTooLarge") }
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.scanning" @($info.Cidr)) $true
        $probePort = if ($cfg) { [int]$cfg.Port } else { [int]$script:ToolEnterpriseDefaultPort }
        $found = @(Find-ToolEnterpriseNetworkDevices -Cidr $cidr -TimeoutMs 250 -ThrottleLimit 64 -ProbePorts @($probePort,445,3389))
        $script:scanResultBox.Clear()
        foreach ($device in $found) {
            $hostLabel = if ($device.HostName) { [string]$device.HostName } else { Get-EnterpriseText "enterprise.server.scanHostUnknown" }
            $method = if ([string]::IsNullOrWhiteSpace([string]$device.DiscoveryMethod)) { Get-EnterpriseText 'common.unknown' } else { [string]$device.DiscoveryMethod }
            $line = Get-EnterpriseText "enterprise.server.scanResultLine" @($device.Address, $device.LatencyMs, $hostLabel, $method)
            [void]$script:scanResultBox.AppendText($line + [Environment]::NewLine)
        }
        if ($found.Count -eq 0) { [void]$script:scanResultBox.AppendText((Get-EnterpriseText "enterprise.server.noDevice")) }
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.scanDone" @($found.Count)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
}

function Invoke-ServerExport {
    try {
        $reportDirectory = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)) 'BaoCao-VietLicenSure'
        if (-not (Test-Path -LiteralPath $reportDirectory -PathType Container)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
        $result = Export-ToolEnterpriseFleetReport -DestinationDirectory $reportDirectory -IncludePdf
        Start-Process -FilePath $result.HtmlPath | Out-Null
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.exported" @($result.ClientCount, $result.JsonPath)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
}

function Invoke-ServerCompliance {
    try {
        $selectedClient = Get-SelectedEnterpriseClient
        $dialog = New-Object Windows.Forms.Form
        $dialog.Text = Get-EnterpriseText 'enterprise.compliance.title'
        $dialog.StartPosition = 'CenterParent'
        $dialog.Size = New-Object Drawing.Size(980,700)
        $dialog.MinimumSize = New-Object Drawing.Size(860,620)
        $dialog.BackColor = [Drawing.Color]::White
        $dialog.Font = $script:enterpriseUiFont

        $list = New-Object Windows.Forms.ListView
        $list.Location = New-Object Drawing.Point(14,14)
        $list.Size = New-Object Drawing.Size(405,570)
        $list.View = 'Details'; $list.FullRowSelect = $true; $list.GridLines = $true
        foreach ($column in @(@((Get-EnterpriseText 'enterprise.compliance.product'),180),@((Get-EnterpriseText 'enterprise.compliance.scope'),75),@((Get-EnterpriseText 'enterprise.compliance.quantity'),75),@((Get-EnterpriseText 'enterpriseDashboard.ui.assigned'),70))) { [void]$list.Columns.Add($column[0],[int]$column[1]) }
        $dialog.Controls.Add($list)

        $labels = @(
            @('enterprise.compliance.product',440,18),@('enterprise.compliance.vendor',440,58),@('enterprise.compliance.scope',440,98),
            @('enterprise.compliance.model',690,98),@('enterprise.compliance.quantity',440,138),@('enterprise.compliance.metric',690,138),
            @('enterprise.compliance.invoice',440,178),@('enterprise.compliance.purchaseDate',690,178),
            @('enterprise.compliance.startDate',440,218),@('enterprise.compliance.expiryDate',690,218),@('enterprise.compliance.notes',440,258),
            @('enterprise.compliance.documents',440,524)
        )
        foreach($entry in $labels){ $label=New-Object Windows.Forms.Label; $label.Text=Get-EnterpriseText $entry[0]; $label.Location=New-Object Drawing.Point([int]$entry[1],[int]$entry[2]); $label.AutoSize=$true; $dialog.Controls.Add($label) }
        $product = New-EnterpriseTextBox 440 38 490
        $vendor = New-EnterpriseTextBox 440 78 490
        $scope = New-Object Windows.Forms.ComboBox; $scope.Location=New-Object Drawing.Point(440,118); $scope.Size=New-Object Drawing.Size(220,25); $scope.DropDownStyle='DropDownList'; [void]$scope.Items.AddRange([object[]]@('Windows','Office','Software')); $scope.SelectedIndex=0
        $model = New-Object Windows.Forms.ComboBox; $model.Location=New-Object Drawing.Point(690,118); $model.Size=New-Object Drawing.Size(240,25); $model.DropDownStyle='DropDownList'; [void]$model.Items.AddRange([object[]]@('OEM','Retail','VolumeMAK','VolumeKMS','Perpetual','Subscription','Commercial','Free','OpenSource','Unknown')); $model.SelectedItem='Commercial'
        $quantity = New-Object Windows.Forms.NumericUpDown; $quantity.Location=New-Object Drawing.Point(440,158); $quantity.Size=New-Object Drawing.Size(220,25); $quantity.Maximum=1000000
        $metric = New-Object Windows.Forms.ComboBox; $metric.Location=New-Object Drawing.Point(690,158); $metric.Size=New-Object Drawing.Size(240,25); $metric.DropDownStyle='DropDownList'; [void]$metric.Items.AddRange([object[]]@('Device','User','Concurrent','Organization','Unknown')); $metric.SelectedItem='Device'
        $invoice = New-EnterpriseTextBox 440 198 220
        $purchaseDate = New-EnterpriseTextBox 690 198 240
        $startDate = New-EnterpriseTextBox 440 238 220
        $expiryDate = New-EnterpriseTextBox 690 238 240
        $notes = New-EnterpriseTextBox 440 278 490 145 $true
        $documents = New-Object Windows.Forms.ComboBox; $documents.Location=New-Object Drawing.Point(440,544); $documents.Size=New-Object Drawing.Size(300,25); $documents.DropDownStyle='DropDownList'
        foreach($control in @($product,$vendor,$scope,$model,$quantity,$metric,$invoice,$purchaseDate,$startDate,$expiryDate,$notes,$documents)){ $dialog.Controls.Add($control) }

        $state = [pscustomobject]@{ EntitlementId=''; Records=@() }
        $refresh = {
            $state.Records = @(Get-ToolLicenseEntitlements)
            $list.Items.Clear()
            foreach($record in $state.Records){
                $assigned=[int](Get-ToolLicenseComplianceIntegerSum -Items @($record.Assignments) -PropertyName Quantity)
                $item=New-Object Windows.Forms.ListViewItem([string]$record.ProductName)
                [void]$item.SubItems.Add([string]$record.ProductScope); [void]$item.SubItems.Add([string]$record.PurchasedQuantity); [void]$item.SubItems.Add([string]$assigned)
                $item.Tag=[string]$record.EntitlementId; [void]$list.Items.Add($item)
                if([string]$state.EntitlementId -eq [string]$record.EntitlementId){ $item.Selected=$true; $item.Focused=$true }
            }
        }
        $clear = { $state.EntitlementId=''; $product.Clear(); $vendor.Clear(); $scope.SelectedIndex=0; $model.SelectedItem='Commercial'; $metric.SelectedItem='Device'; $quantity.Value=0; $invoice.Clear(); $purchaseDate.Clear(); $startDate.Clear(); $expiryDate.Clear(); $notes.Clear(); $documents.Items.Clear(); $documents.Tag=[object[]]@() }
        $list.Add_SelectedIndexChanged({
            if($list.SelectedItems.Count -ne 1){ return }
            $id=[string]$list.SelectedItems[0].Tag; $record=@($state.Records | Where-Object EntitlementId -eq $id | Select-Object -First 1)
            if($record.Count -eq 0){ return }
            $state.EntitlementId=$id; $product.Text=[string]$record[0].ProductName; $vendor.Text=[string]$record[0].Vendor; $scope.SelectedItem=[string]$record[0].ProductScope; $model.SelectedItem=[string]$record[0].LicenseModel; $metric.SelectedItem=[string]$record[0].Metric; $quantity.Value=[decimal]$record[0].PurchasedQuantity; $invoice.Text=[string]$record[0].InvoiceNumber; $purchaseDate.Text=[string]$record[0].PurchaseDate; $startDate.Text=[string]$record[0].ValidFrom; $expiryDate.Text=[string]$record[0].ExpiresAt; $notes.Text=[string]$record[0].Notes
            $documents.Items.Clear(); $documents.Tag=[object[]]@($record[0].Documents); foreach($document in @($record[0].Documents)){ [void]$documents.Items.Add(([string]$document.OriginalName+' - '+[string]$document.Kind)) }; if($documents.Items.Count -gt 0){ $documents.SelectedIndex=0 }
        })
        $newButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.compliance.new') 440 438 100 32 { & $clear }
        $saveButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.compliance.save') 550 438 100 32 {
            try { $saved=Set-ToolLicenseEntitlement -EntitlementId $state.EntitlementId -ProductScope ([string]$scope.SelectedItem) -ProductName $product.Text -Vendor $vendor.Text -LicenseModel ([string]$model.SelectedItem) -Metric ([string]$metric.SelectedItem) -PurchasedQuantity ([int]$quantity.Value) -Provider $vendor.Text -InvoiceNumber $invoice.Text -PurchaseDate $purchaseDate.Text -ValidFrom $startDate.Text -ExpiresAt $expiryDate.Text -Notes $notes.Text; $state.EntitlementId=[string]$saved.EntitlementId; & $refresh; Set-EnterpriseStatus (Get-EnterpriseText 'enterprise.compliance.saved' @($saved.ProductName)) $true } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
        }
        $deleteButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.compliance.delete') 660 438 100 32 {
            try { if([string]::IsNullOrWhiteSpace($state.EntitlementId)){ throw (Get-EnterpriseText 'enterprise.compliance.selectEntitlement') }; [void](Remove-ToolLicenseEntitlement -EntitlementId $state.EntitlementId); & $clear; & $refresh } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
        }
        $documentButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.compliance.addDocument') 770 438 160 32 {
            try { if([string]::IsNullOrWhiteSpace($state.EntitlementId)){ throw (Get-EnterpriseText 'enterprise.compliance.selectEntitlement') }; $picker=New-Object Windows.Forms.OpenFileDialog; $picker.Filter='Supported evidence|*.pdf;*.png;*.jpg;*.jpeg;*.txt;*.eml;*.msg;*.docx;*.xlsx'; if($picker.ShowDialog($dialog) -eq [Windows.Forms.DialogResult]::OK){ $doc=Add-ToolLicenseEntitlementDocument -EntitlementId $state.EntitlementId -Path $picker.FileName; Set-EnterpriseStatus (Get-EnterpriseText 'enterprise.compliance.documentAdded' @($doc.OriginalName)) $true; & $refresh } } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
        }
        $assignButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.compliance.assign') 440 480 235 34 {
            try { if([string]::IsNullOrWhiteSpace($state.EntitlementId)){ throw (Get-EnterpriseText 'enterprise.compliance.selectEntitlement') }; if(-not $selectedClient){ throw (Get-EnterpriseText 'enterprise.compliance.selectClient') }; [void](Set-ToolLicenseEntitlementAssignment -EntitlementId $state.EntitlementId -ClientId ([string]$selectedClient.ClientId) -Quantity 1); & $refresh } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
        }
        $unassignButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.compliance.unassign') 690 480 240 34 {
            try { if([string]::IsNullOrWhiteSpace($state.EntitlementId)){ throw (Get-EnterpriseText 'enterprise.compliance.selectEntitlement') }; if(-not $selectedClient){ throw (Get-EnterpriseText 'enterprise.compliance.selectClient') }; [void](Set-ToolLicenseEntitlementAssignment -EntitlementId $state.EntitlementId -ClientId ([string]$selectedClient.ClientId) -Quantity 0); & $refresh } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
        }
        $removeDocumentButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.compliance.removeDocument') 750 542 180 30 {
            try { if([string]::IsNullOrWhiteSpace($state.EntitlementId)){ throw (Get-EnterpriseText 'enterprise.compliance.selectEntitlement') }; if($documents.SelectedIndex -lt 0 -or @($documents.Tag).Count -le $documents.SelectedIndex){ throw (Get-EnterpriseText 'enterprise.compliance.selectDocument') }; $selectedDocument=@($documents.Tag)[$documents.SelectedIndex]; [void](Remove-ToolLicenseEntitlementDocument -EntitlementId $state.EntitlementId -DocumentId ([string]$selectedDocument.DocumentId)); Set-EnterpriseStatus (Get-EnterpriseText 'enterprise.compliance.documentRemoved' @($selectedDocument.OriginalName)) $true; & $refresh } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
        }
        foreach($button in @($newButton,$saveButton,$deleteButton,$documentButton,$assignButton,$unassignButton,$removeDocumentButton)){ $dialog.Controls.Add($button) }
        & $refresh
        [void]$dialog.ShowDialog($form)
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1200) }
}

function Invoke-ServerDashboard {
    $session = $null
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.dashboard")) { return }
        $configuration = Get-EnterpriseServerConfigurationSafe
        if (-not $configuration) { throw (Get-EnterpriseText "enterprise.error.noServerConfiguration") }
        $diagnostic = Get-ToolEnterpriseConnectionDiagnostic -ServerAddress "127.0.0.1" -Port ([int]$configuration.Port) -TimeoutMs 1200
        if (-not $diagnostic.Success) { throw (Get-EnterpriseText "enterprise.dashboard.startServerFirst") }
        $adminCode = [string]$script:serverAdminBox.Text
        $session = New-ToolEnterpriseDashboardSession -AdminCode $adminCode -ValidMinutes 30
        $language = if ($script:enterpriseCulture -eq "en-US") { "en" } else { "vi" }
        $dashboardUrl = "http://127.0.0.1:$([int]$configuration.Port)/tool/v1/dashboard/?lang=$language#token=$([Uri]::EscapeDataString([string]$session.AccessToken))"
        Start-Process -FilePath $dashboardUrl | Out-Null
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.dashboard.opened" @([string]$session.ExpiresAtUtc)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
    finally {
        if ($script:serverAdminBox) { $script:serverAdminBox.Clear() }
        $session = $null
    }
}

function Invoke-ServerJob {
    try {
        $client = Get-SelectedEnterpriseClient
        if (-not $client) { throw (Get-EnterpriseText "enterprise.error.selectClient") }
        $operation = [string]$script:jobOperationBox.SelectedItem
        $key = $script:jobKeyBox.Text.Trim()
        if ($operation -ne "InventoryOnly" -and [string]::IsNullOrWhiteSpace($key)) { throw (Get-EnterpriseText "enterprise.error.keyRequired") }
        if (-not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.server.jobPrompt" @($operation, $client.ComputerName)))) { return }
        $job = New-ToolEnterpriseLicenseJob -ClientId ([string]$client.ClientId) -Operation $operation -ProductKey $key -RequestedBy ([Environment]::UserName)
        $script:jobKeyBox.Clear()
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.jobCreated" @($job.JobId, $job.ProductKeyLast5)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1100) }
}

function Invoke-ServerNetworkAccess {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.firewall")) { return }
        $cfg = Get-EnterpriseServerConfigurationSafe
        if (-not $cfg) { throw (Get-EnterpriseText "enterprise.error.noServerConfiguration") }
        if (-not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.server.firewallPrompt" @($cfg.Port)))) { return }
        Enable-EnterpriseServerListenerAccess -Configuration $cfg
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.firewallReady" @($cfg.Port)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1100) }
}

function Invoke-ClientEnroll {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.enroll")) { return }
        $address = Resolve-EnterpriseClientServerAddress
        $port = [int]$script:clientPortBox.Text
        $code = $script:clientPairingBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($code)) { throw (Get-EnterpriseText "enterprise.error.pairingCodeRequired") }
        $diagnostic = Get-ToolEnterpriseConnectionDiagnostic -ServerAddress $address -Port $port -TimeoutMs 1800
        if (-not $diagnostic.Success) { throw [string]$diagnostic.Message }
        $cfg = Register-ToolEnterpriseClient -ServerAddress $address -Port $port -PairingCode $code -AllowRemoteLicenseChanges ([bool]$script:clientRemoteChanges.Checked) -AutoSend ([bool]$script:clientAutoSend.Checked)
        $script:clientPairingBox.Clear()
        Update-EnterpriseClientAssetSummary
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.enrolled" @($cfg.ClientId, $address, $port)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1100) }
}

function Invoke-ClientTest {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.testConnection")) { return }
        $address = Resolve-EnterpriseClientServerAddress
        $diagnostic = Get-ToolEnterpriseConnectionDiagnostic -ServerAddress $address -Port ([int]$script:clientPortBox.Text) -TimeoutMs 1800
        if (-not $diagnostic.Success) { throw [string]$diagnostic.Message }
        Set-EnterpriseStatus ([string]$diagnostic.Message) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 900) }
}

function Invoke-ClientSend {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.sendReport")) { return }
        $paths = Get-ToolEnterprisePaths
        foreach ($stalePath in @($paths.ClientAgentResult,$paths.ClientAgentError)) {
            if (Test-Path -LiteralPath $stalePath -PathType Leaf) { Remove-Item -LiteralPath $stalePath -Force -ErrorAction SilentlyContinue }
        }
        Set-EnterpriseStatus (Get-EnterpriseText 'enterprise.client.agentRunning') $true
        $script:agentProcess = Start-EnterpriseChild -Role Agent -Force:$true
        $agentResult = Wait-EnterpriseAgentResult -LauncherProcess $script:agentProcess -TimeoutSeconds 90
        if ([int]$agentResult.Sent -gt 0) {
            Set-EnterpriseStatus (Get-EnterpriseText 'enterprise.client.agentSent' @($agentResult.Sent, $agentResult.JobStatus)) $true
        } elseif ([int]$agentResult.Queued -gt 0) {
            Set-EnterpriseStatus (Get-EnterpriseText 'enterprise.client.agentQueued' @($agentResult.Queued, $agentResult.Message)) $false
        } else {
            Set-EnterpriseStatus (Get-EnterpriseText 'enterprise.client.agentNoReport' @($agentResult.Message)) $false
        }
        Update-EnterpriseClientAssetSummary
    } catch {
        try {
            if ($script:agentProcess -and -not $script:agentProcess.HasExited) {
                Stop-Process -Id $script:agentProcess.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000)
    }
}

function Invoke-ClientSchedule {
    param([bool]$Enable)
    try {
        if ($Enable -and -not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.scheduleAgent")) { return }
        $launcher = Get-EnterpriseLauncherPath
        if (-not $launcher) { throw (Get-EnterpriseText "enterprise.error.oneFileRequired") }
        if ($Enable) {
            if (-not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.client.enableSchedulePrompt"))) { return }
            $taskName = Install-EnterpriseLifecycleTask -Role Agent -LauncherPath $launcher
            Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.scheduleEnabledLifecycle" @($taskName)) $true
        } else {
            if (-not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.client.disableSchedulePrompt"))) { return }
            $exitCode = Remove-EnterpriseLifecycleTasks -Role Agent
            Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.scheduleDisabled" @($exitCode)) $true
        }
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1100) }
}

function New-EnterpriseLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 180, [int]$H = 24)
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object Drawing.Point($X, $Y)
    $label.Size = New-Object Drawing.Size($W, $H)
    $label.Font = $script:enterpriseFont
    $label.ForeColor = $script:enterprisePalette.Text
    $label.BackColor = [Drawing.Color]::Transparent
    return $label
}

function New-EnterpriseTextBox {
    param([int]$X, [int]$Y, [int]$W = 260, [int]$H = 25, [bool]$MultiLine = $false, [bool]$Password = $false)
    $box = New-Object Windows.Forms.TextBox
    $box.Location = New-Object Drawing.Point($X, $Y)
    $box.Size = New-Object Drawing.Size($W, $H)
    $box.Font = $script:enterpriseFont
    $box.BackColor = $script:enterprisePalette.Input
    $box.ForeColor = $script:enterprisePalette.Text
    $box.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    $box.Multiline = $MultiLine
    if ($MultiLine) { $box.ScrollBars = "Vertical" }
    if ($Password) { $box.UseSystemPasswordChar = $true }
    return $box
}

function New-EnterpriseButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 150, [int]$H = 32, [scriptblock]$Action)
    $button = New-Object Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object Drawing.Point($X, $Y)
    $button.Size = New-Object Drawing.Size($W, $H)
    $button.Font = $script:enterpriseFont
    $button.FlatStyle = "Flat"
    $button.UseVisualStyleBackColor = $false
    $button.BackColor = $script:enterprisePalette.Button
    $button.ForeColor = $script:enterprisePalette.Header
    $button.FlatAppearance.BorderColor = $script:enterprisePalette.Border
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.MouseOverBackColor = $script:enterprisePalette.ButtonHover
    $button.Cursor = [Windows.Forms.Cursors]::Hand
    if ($Action) { $button.Add_Click($Action) }
    Set-ToolUiActionButtonVisual -Button $button -Mode $script:enterpriseTheme -PreserveColors
    $button.AutoEllipsis = $false
    $script:enterpriseToolTip.SetToolTip($button, [string]$button.Text)
    return $button
}

function Set-EnterpriseButtonStyle {
    param(
        [Parameter(Mandatory = $true)]$Button,
        [Parameter(Mandatory = $true)][Drawing.Color]$BackColor,
        [Drawing.Color]$ForeColor = [Drawing.Color]::White,
        [Drawing.Color]$HoverColor = [Drawing.Color]::Empty,
        [Drawing.Color]$BorderColor = [Drawing.Color]::Empty
    )
    if (-not $Button) { return }
    $Button.UseVisualStyleBackColor = $false
    $Button.BackColor = $BackColor
    $Button.ForeColor = $ForeColor
    if ($BorderColor.IsEmpty) { $BorderColor = $BackColor }
    if ($HoverColor.IsEmpty) { $HoverColor = $BackColor }
    $Button.FlatAppearance.BorderColor = $BorderColor
    $Button.FlatAppearance.MouseOverBackColor = $HoverColor
    $Button.FlatAppearance.MouseDownBackColor = $HoverColor
}

function Invoke-EnterpriseBack {
    if ($tabs -and $tabs.SelectedIndex -gt 0) {
        $script:previousTabIndex = $tabs.SelectedIndex
        $tabs.SelectedIndex = $tabs.SelectedIndex - 1
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.navigation.backStatus") $true
    } elseif ($form) {
        # Đóng trung tâm để quay lại cửa sổ/phiên làm việc đã mở mục 8.
        $form.Close()
    }
}

function Invoke-EnterpriseClose {
    if ($form) { $form.Close() }
}

function Find-EnterpriseDirectControl {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Control]$Parent,
        [Parameter(Mandatory = $true)][string]$Text
    )
    foreach ($control in $Parent.Controls) {
        if ([string]$control.Text -eq $Text) { return $control }
    }
    return $null
}

function Set-EnterpriseBounds {
    param(
        [Windows.Forms.Control]$Control,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )
    if (-not $Control) { return }
    $safeWidth = [Math]::Max(1, $Width)
    $safeHeight = [Math]::Max(1, $Height)
    $Control.SetBounds($X, $Y, $safeWidth, $safeHeight)
    if ($Control -is [Windows.Forms.Button] -and -not (Test-ToolUiHighContrast)) {
        # The rounded Region is created at construction time. Rebuild it after
        # every responsive resize or WinForms keeps masking the button at its
        # old width even though Control.Width reports the new value.
        Set-ToolUiRoundedButtonRegion -Button $Control -Radius $(if ($safeHeight -ge 40) { 8 } else { 6 })
    }
}

function Set-EnterpriseAdaptiveButtonRows {
    param(
        [object[]]$Buttons,
        [int]$X,
        [int]$Y,
        [int]$AvailableWidth,
        [int]$Height,
        [int]$Gap = 8,
        [int]$RowGap = 5
    )

    $activeButtons = @($Buttons | Where-Object { $null -ne $_ })
    if ($activeButtons.Count -eq 0) { return 0 }
    $requiredWidths = @($activeButtons | ForEach-Object {
        [Math]::Max(92, (Get-ToolUiButtonRequiredWidth -Button $_ -HorizontalSafety 20))
    })
    $oneRowWidth = [int](($requiredWidths | Measure-Object -Sum).Sum + (($activeButtons.Count - 1) * $Gap))
    $columnCount = if ($oneRowWidth -le $AvailableWidth) { $activeButtons.Count } else { [Math]::Ceiling($activeButtons.Count / 2.0) }
    $rowCount = [int][Math]::Ceiling($activeButtons.Count / [double]$columnCount)

    for ($rowIndex = 0; $rowIndex -lt $rowCount; $rowIndex++) {
        $startIndex = $rowIndex * $columnCount
        $endIndex = [Math]::Min($activeButtons.Count - 1, $startIndex + $columnCount - 1)
        $rowButtons = @($activeButtons[$startIndex..$endIndex])
        $rowRequired = @($requiredWidths[$startIndex..$endIndex])
        $rowGapWidth = ($rowButtons.Count - 1) * $Gap
        $rowMinimumWidth = [int](($rowRequired | Measure-Object -Sum).Sum + $rowGapWidth)
        $extraPerButton = if ($rowMinimumWidth -lt $AvailableWidth) { [Math]::Floor(($AvailableWidth - $rowMinimumWidth) / $rowButtons.Count) } else { 0 }
        $rowX = $X
        for ($columnIndex = 0; $columnIndex -lt $rowButtons.Count; $columnIndex++) {
            $buttonWidth = if ($rowMinimumWidth -le $AvailableWidth) {
                [int]$rowRequired[$columnIndex] + $extraPerButton
            } else {
                [Math]::Floor(($AvailableWidth - $rowGapWidth) / $rowButtons.Count)
            }
            if ($columnIndex -eq ($rowButtons.Count - 1)) {
                $buttonWidth = $X + $AvailableWidth - $rowX
            }
            Set-EnterpriseBounds $rowButtons[$columnIndex] $rowX ($Y + ($rowIndex * ($Height + $RowGap))) $buttonWidth $Height
            $rowX += $buttonWidth + $Gap
        }
    }
    return $rowCount
}

function Get-EnterpriseClippedButtonLabels {
    param([Parameter(Mandatory = $true)][Windows.Forms.Control]$Root)

    foreach ($control in $Root.Controls) {
        if ($control -is [Windows.Forms.Button]) {
            $requiredWidth = Get-ToolUiButtonRequiredWidth -Button $control -HorizontalSafety 20
            $regionClipsRightEdge = [bool]($control.Region -and
                -not $control.Region.IsVisible([Math]::Max(1, $control.ClientSize.Width - 3), [Math]::Floor($control.ClientSize.Height / 2)))
            if ($control.Width -lt $requiredWidth -or $regionClipsRightEdge -or (([string]$control.Text).Contains('&') -and $control.UseMnemonic)) {
                Write-Output ([string]$control.Text)
            }
        }
        Get-EnterpriseClippedButtonLabels -Root $control
    }
}

function Fit-EnterpriseWindowToWorkingArea {
    $workArea = [Windows.Forms.Screen]::FromControl($form).WorkingArea
    $availableWidth = [Math]::Max(560, $workArea.Width - 12)
    $availableHeight = [Math]::Max(460, $workArea.Height - 12)
    $targetWidth = [Math]::Min(1120, $availableWidth)
    $targetHeight = [Math]::Min(780, $availableHeight)
    $form.MinimumSize = New-Object Drawing.Size([Math]::Min(760, $targetWidth), [Math]::Min(560, $targetHeight))
    $targetX = $workArea.Left + [Math]::Max(0, [Math]::Floor(($workArea.Width - $targetWidth) / 2))
    $targetY = $workArea.Top + [Math]::Max(0, [Math]::Floor(($workArea.Height - $targetHeight) / 2))
    $form.StartPosition = [Windows.Forms.FormStartPosition]::Manual
    $form.Bounds = New-Object Drawing.Rectangle($targetX, $targetY, $targetWidth, $targetHeight)
}

function Update-EnterpriseLayout {
    if ($script:updatingEnterpriseLayout -or -not $form -or -not $tabs) { return }
    $script:updatingEnterpriseLayout = $true
    try {
        $formWidth = [Math]::Max(640, $form.ClientSize.Width)
        $formHeight = [Math]::Max(500, $form.ClientSize.Height)
        Set-EnterpriseBounds $title 18 8 ($formWidth - 36) 32
        Set-EnterpriseBounds $script:enterpriseStatus 18 41 ([Math]::Max(300, $formWidth - 294)) 26
        Set-EnterpriseBounds $script:enterpriseNetworkButton ([Math]::Max(382, $formWidth - 258)) 38 240 30
        Set-EnterpriseBounds $tabs 10 72 ($formWidth - 20) ([Math]::Max(330, $formHeight - 124))
        $tabItemWidth = [Math]::Max(180, [Math]::Floor(($tabs.ClientSize.Width - 6) / 3))
        $tabs.ItemSize = New-Object Drawing.Size($tabItemWidth, 32)
        $tabs.PerformLayout()

        if ($localManagerTab) {
            $localWidth = [Math]::Max(620, $localManagerTab.ClientSize.Width)
            $localLabels = @($localManagerTab.Controls | Where-Object { $_ -is [Windows.Forms.Label] })
            if ($localLabels.Count -gt 0) { Set-EnterpriseBounds $localLabels[0] 24 24 ($localWidth - 48) 30 }
            if ($localLabels.Count -gt 1) { Set-EnterpriseBounds $localLabels[1] 24 60 ($localWidth - 48) 42 }
            if ($localLabels.Count -gt 2) { Set-EnterpriseBounds $localLabels[2] 24 106 ($localWidth - 48) 34 }
            $localButtonWidth = [Math]::Min(($localWidth - 48), [Math]::Max(280, (Get-ToolUiButtonRequiredWidth -Button $localManagerButton -HorizontalSafety 20)))
            Set-EnterpriseBounds $localManagerButton 24 154 $localButtonWidth 40
        }

        if ($serverTab) {
            $serverTab.AutoScroll = $false
            $width = [Math]::Max(680, $serverTab.ClientSize.Width)
            $height = [Math]::Max(470, $serverTab.ClientSize.Height)
            $margin = 16
            $gap = 8
            $contentWidth = $width - (2 * $margin)
            $narrow = [bool]($contentWidth -lt 820)

            $serverDescription = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.description")
            $serverNameLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.name")
            $serverAdminLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.adminCode")
            $serverPortLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.port")
            $serverCidrLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.cidrs")
            $pairingLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.pairingCode")
            $scanLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.scanLabel")
            $jobLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.job")
            $createButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.create")
            $pairButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.pair")
            $startButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.start")
            $stopButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.stop")
            $deleteButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.delete")
            $networkButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.firewall")
            $refreshButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.refresh")
            $exportButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.export")
            $complianceButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.compliance")
            $dashboardButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.dashboard")
            $scanButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.scan")
            $createJobButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.createJob")

            Set-EnterpriseBounds $serverDescription $margin 4 $contentWidth 24
            $fieldY = 32
            if (-not $narrow) {
                $nameLabelWidth = 100
                $nameBoxWidth = [Math]::Min(230, [Math]::Max(170, [Math]::Floor($contentWidth * 0.22)))
                $adminLabelWidth = 165
                $adminBoxWidth = [Math]::Min(240, [Math]::Max(175, [Math]::Floor($contentWidth * 0.23)))
                $portLabelWidth = 42
                $portBoxWidth = 80
                $x = $margin
                Set-EnterpriseBounds $serverNameLabel $x $fieldY $nameLabelWidth 26
                $x += $nameLabelWidth
                Set-EnterpriseBounds $script:serverNameBox $x $fieldY $nameBoxWidth 26
                $x += $nameBoxWidth + $gap
                Set-EnterpriseBounds $serverAdminLabel $x $fieldY $adminLabelWidth 26
                $x += $adminLabelWidth
                Set-EnterpriseBounds $script:serverAdminBox $x $fieldY $adminBoxWidth 26
                $x += $adminBoxWidth + $gap
                Set-EnterpriseBounds $serverPortLabel $x $fieldY $portLabelWidth 26
                $x += $portLabelWidth
                Set-EnterpriseBounds $script:serverPortBox $x $fieldY $portBoxWidth 26
                $cidrLabelY = 63
            } else {
                $nameLabelWidth = 100
                $portLabelWidth = 42
                $portBoxWidth = 80
                $nameBoxWidth = $contentWidth - $nameLabelWidth - $portLabelWidth - $portBoxWidth - (2 * $gap)
                Set-EnterpriseBounds $serverNameLabel $margin $fieldY $nameLabelWidth 26
                Set-EnterpriseBounds $script:serverNameBox ($margin + $nameLabelWidth) $fieldY $nameBoxWidth 26
                Set-EnterpriseBounds $serverPortLabel ($margin + $nameLabelWidth + $nameBoxWidth + $gap) $fieldY $portLabelWidth 26
                Set-EnterpriseBounds $script:serverPortBox ($margin + $contentWidth - $portBoxWidth) $fieldY $portBoxWidth 26
                $adminY = $fieldY + 30
                Set-EnterpriseBounds $serverAdminLabel $margin $adminY 165 26
                Set-EnterpriseBounds $script:serverAdminBox ($margin + 165) $adminY ($contentWidth - 165) 26
                $cidrLabelY = 93
            }

            $cidrLabelWidth = [Math]::Floor($contentWidth * 0.58)
            Set-EnterpriseBounds $serverCidrLabel $margin $cidrLabelY $cidrLabelWidth 20
            Set-EnterpriseBounds $script:serverAddressLabel ($margin + $cidrLabelWidth) $cidrLabelY ($contentWidth - $cidrLabelWidth) 20
            $cidrBoxY = $cidrLabelY + 20
            Set-EnterpriseBounds $script:serverCidrBox $margin $cidrBoxY $contentWidth 40

            $actionY = $cidrBoxY + 45
            $actionRowCount = Set-EnterpriseAdaptiveButtonRows -Buttons @($createButton,$pairButton,$startButton,$stopButton,$deleteButton) -X $margin -Y $actionY -AvailableWidth $contentWidth -Height 34 -Gap $gap -RowGap 5

            $pairY = $actionY + ($actionRowCount * 34) + (($actionRowCount - 1) * 5) + 5
            $networkWidth = [Math]::Min(250, [Math]::Max((Get-ToolUiButtonRequiredWidth -Button $networkButton -HorizontalSafety 20), [Math]::Floor($contentWidth * 0.21)))
            $pairLabelWidth = [Math]::Min(245, [Math]::Max(190, [Math]::Floor($contentWidth * 0.25)))
            Set-EnterpriseBounds $networkButton $margin $pairY $networkWidth 32
            Set-EnterpriseBounds $pairingLabel ($margin + $networkWidth + $gap) $pairY $pairLabelWidth 32
            Set-EnterpriseBounds $script:pairingOutputBox ($margin + $networkWidth + $gap + $pairLabelWidth) ($pairY + 3) ($contentWidth - $networkWidth - $gap - $pairLabelWidth) 26

            $scanLabelY = $pairY + 37
            Set-EnterpriseBounds $scanLabel $margin $scanLabelY $contentWidth 20
            $scanInputY = $scanLabelY + 21
            $scanButtonWidth = [Math]::Min(180, [Math]::Max(130, (Get-ToolUiButtonRequiredWidth -Button $scanButton -HorizontalSafety 20)))
            Set-EnterpriseBounds $script:scanInputBox $margin $scanInputY ($contentWidth - $scanButtonWidth - $gap) 28
            Set-EnterpriseBounds $scanButton ($margin + $contentWidth - $scanButtonWidth) $scanInputY $scanButtonWidth 30
            $scanResultY = $scanInputY + 34
            $assetPanelWidth = [Math]::Min(390, [Math]::Max(315, [Math]::Floor($contentWidth * 0.38)))
            $scanResultWidth = $contentWidth - $assetPanelWidth - $gap
            Set-EnterpriseBounds $script:scanResultBox $margin $scanResultY $scanResultWidth 92
            Set-EnterpriseBounds $script:serverAssetGroup ($margin + $scanResultWidth + $gap) $scanResultY $assetPanelWidth 92
            Set-EnterpriseBounds $script:serverAssetDetailLabel 10 19 ($assetPanelWidth - 20) 35
            Set-EnterpriseBounds $script:serverAssetManagerButton 10 55 ($assetPanelWidth - 20) 28

            $clientHeaderY = $scanResultY + 97
            $refreshWidth = [Math]::Min(220, [Math]::Max(155, (Get-ToolUiButtonRequiredWidth -Button $refreshButton -HorizontalSafety 20)))
            $exportWidth = [Math]::Min(220, [Math]::Max(170, (Get-ToolUiButtonRequiredWidth -Button $exportButton -HorizontalSafety 20)))
            $complianceWidth = [Math]::Min(220, [Math]::Max(170, (Get-ToolUiButtonRequiredWidth -Button $complianceButton -HorizontalSafety 20)))
            $dashboardWidth = [Math]::Min(190, [Math]::Max(145, (Get-ToolUiButtonRequiredWidth -Button $dashboardButton -HorizontalSafety 20)))
            $clientCountWidth = [Math]::Max(80, ($contentWidth - $dashboardWidth - $complianceWidth - $refreshWidth - $exportWidth - (4 * $gap)))
            Set-EnterpriseBounds $script:clientCountLabel $margin $clientHeaderY $clientCountWidth 30
            Set-EnterpriseBounds $dashboardButton ($margin + $contentWidth - $dashboardWidth - $complianceWidth - $refreshWidth - $exportWidth - (3 * $gap)) $clientHeaderY $dashboardWidth 30
            Set-EnterpriseBounds $complianceButton ($margin + $contentWidth - $complianceWidth - $refreshWidth - $exportWidth - (2 * $gap)) $clientHeaderY $complianceWidth 30
            Set-EnterpriseBounds $refreshButton ($margin + $contentWidth - $refreshWidth - $exportWidth - $gap) $clientHeaderY $refreshWidth 30
            Set-EnterpriseBounds $exportButton ($margin + $contentWidth - $exportWidth) $clientHeaderY $exportWidth 30

            $jobY = $height - 40
            $listY = $clientHeaderY + 34
            $listHeight = [Math]::Max(54, $jobY - $listY - 6)
            Set-EnterpriseBounds $script:serverClientList $margin $listY $contentWidth $listHeight

            $jobLabelWidth = 105
            $operationWidth = [Math]::Min(230, [Math]::Max(170, [Math]::Floor($contentWidth * 0.23)))
            $jobButtonWidth = [Math]::Min(285, [Math]::Max((Get-ToolUiButtonRequiredWidth -Button $createJobButton -HorizontalSafety 20), [Math]::Floor($contentWidth * 0.24)))
            $jobKeyWidth = $contentWidth - $jobLabelWidth - $operationWidth - $jobButtonWidth - (2 * $gap)
            Set-EnterpriseBounds $jobLabel $margin $jobY $jobLabelWidth 30
            Set-EnterpriseBounds $script:jobOperationBox ($margin + $jobLabelWidth) $jobY $operationWidth 28
            Set-EnterpriseBounds $script:jobKeyBox ($margin + $jobLabelWidth + $operationWidth + $gap) $jobY $jobKeyWidth 28
            Set-EnterpriseBounds $createJobButton ($margin + $contentWidth - $jobButtonWidth) ($jobY - 2) $jobButtonWidth 34
            $serverContentBottom = $jobY + 40
            $serverTab.AutoScroll = [bool]($serverContentBottom -gt $serverTab.ClientSize.Height)
            $serverTab.AutoScrollMinSize = if ($serverTab.AutoScroll) { New-Object Drawing.Size(0, ($serverContentBottom + 8)) } else { New-Object Drawing.Size(0, 0) }
        }

        if ($clientTab) {
            $clientTab.AutoScroll = $false
            $clientWidth = [Math]::Max(680, $clientTab.ClientSize.Width)
            $clientMargin = 18
            $clientContentWidth = $clientWidth - (2 * $clientMargin)
            $clientDescription = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.description" @($script:enterpriseReleaseDisplayName))
            $clientAddressLabel = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.address")
            $clientPortLabel = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.port")
            $clientPairingLabel = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.pairingCode")
            $testButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.test")
            $discoverButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.discover")
            $enrollButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.enroll")
            $sendButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.send")
            $enableAgentButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.enableAgent")
            $disableAgentButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.disableAgent")
            $clientNotes = @($clientTab.Controls | Where-Object { $_ -is [Windows.Forms.Label] -and $_ -ne $clientDescription -and $_ -ne $clientAddressLabel -and $_ -ne $clientPortLabel -and $_ -ne $clientPairingLabel })

            Set-EnterpriseBounds $clientDescription $clientMargin 12 $clientContentWidth 30
            $addressY = 50
            $addressLabelWidth = 210
            $portLabelWidth = 45
            $portBoxWidth = 85
            $addressBoxWidth = $clientContentWidth - $addressLabelWidth - $portLabelWidth - $portBoxWidth - (2 * $gap)
            Set-EnterpriseBounds $clientAddressLabel $clientMargin $addressY $addressLabelWidth 28
            Set-EnterpriseBounds $script:clientAddressBox ($clientMargin + $addressLabelWidth) $addressY $addressBoxWidth 28
            Set-EnterpriseBounds $clientPortLabel ($clientMargin + $addressLabelWidth + $addressBoxWidth + $gap) $addressY $portLabelWidth 28
            Set-EnterpriseBounds $script:clientPortBox ($clientMargin + $clientContentWidth - $portBoxWidth) $addressY $portBoxWidth 28
            $pairingY = 86
            Set-EnterpriseBounds $clientPairingLabel $clientMargin $pairingY $addressLabelWidth 28
            Set-EnterpriseBounds $script:clientPairingBox ($clientMargin + $addressLabelWidth) $pairingY ($clientContentWidth - $addressLabelWidth) 28
            Set-EnterpriseBounds $script:clientRemoteChanges $clientMargin 124 $clientContentWidth 28
            Set-EnterpriseBounds $script:clientAutoSend $clientMargin 154 $clientContentWidth 28

            $buttonY = 194
            $clientButtonGap = 7
            $clientButtonRows = Set-EnterpriseAdaptiveButtonRows -Buttons @($discoverButton,$testButton,$enrollButton,$sendButton,$enableAgentButton,$disableAgentButton) -X $clientMargin -Y $buttonY -AvailableWidth $clientContentWidth -Height 36 -Gap $clientButtonGap -RowGap 6
            $clientAssetY = $buttonY + ($clientButtonRows * 36) + (($clientButtonRows - 1) * 6) + 12
            Set-EnterpriseBounds $script:clientAssetGroup $clientMargin $clientAssetY $clientContentWidth 78
            Set-EnterpriseBounds $script:clientAssetSummaryLabel 12 20 ($clientContentWidth - 24) 52
            $clientNotesY = $clientAssetY + 88
            if ($clientNotes.Count -gt 0) { Set-EnterpriseBounds $clientNotes[0] $clientMargin $clientNotesY $clientContentWidth 42 }
            if ($clientNotes.Count -gt 1) { Set-EnterpriseBounds $clientNotes[1] $clientMargin ($clientNotesY + 44) $clientContentWidth 45 }
            $clientContentBottom = $clientNotesY + 89
            $clientTab.AutoScroll = [bool]($clientContentBottom -gt $clientTab.ClientSize.Height)
            $clientTab.AutoScrollMinSize = if ($clientTab.AutoScroll) { New-Object Drawing.Size(0, ($clientContentBottom + 8)) } else { New-Object Drawing.Size(0, 0) }
        }

        $footerY = [Math]::Max(80, $formHeight - 42)
        Set-EnterpriseBounds $backButton 18 $footerY 205 32
        Set-EnterpriseBounds $closeButton ([Math]::Max(225, $formWidth - 198)) $footerY 180 32
    } finally {
        $script:updatingEnterpriseLayout = $false
    }
}

$form = New-Object Windows.Forms.Form
$form.Text = Get-EnterpriseText "enterprise.form.title" @($script:enterpriseReleaseDisplayName)
$form.StartPosition = "CenterScreen"
$form.Size = New-Object Drawing.Size(1040, 760)
$form.MinimumSize = New-Object Drawing.Size(860, 620)
$form.Font = $script:enterpriseFont
$form.BackColor = $script:enterprisePalette.Form
$form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
$form.AutoScroll = $false

$title = New-EnterpriseLabel (Get-EnterpriseText "enterprise.title" @($script:enterpriseReleaseDisplayName)) 18 8 700 32
$title.Font = $script:enterpriseTitleFont
$title.ForeColor = $script:enterprisePalette.Header
$form.Controls.Add($title)
$script:enterpriseStatus = New-EnterpriseLabel (Get-EnterpriseText "enterprise.status.choose") 18 41 840 26
$form.Controls.Add($script:enterpriseStatus)
$script:enterpriseNetworkButton = New-EnterpriseButton (Get-EnterpriseText $(if ($script:enterpriseNetworkAllowed) { "enterprise.network.stateOnline" } else { "enterprise.network.stateOffline" })) 780 38 240 30 {
    [void](Toggle-EnterpriseNetworkAccess -SkipConfirmation:$SmokeTest)
}
$form.Controls.Add($script:enterpriseNetworkButton)

$tabs = New-Object Windows.Forms.TabControl
$tabs.Location = New-Object Drawing.Point(10, 72)
$tabs.Size = New-Object Drawing.Size(995, 560)
$tabs.Anchor = "Top,Bottom,Left,Right"
$tabs.DrawMode = [Windows.Forms.TabDrawMode]::OwnerDrawFixed
$tabs.SizeMode = [Windows.Forms.TabSizeMode]::Fixed
$tabs.ItemSize = New-Object Drawing.Size(320, 32)
$tabs.Padding = New-Object Drawing.Point(12, 4)
$form.Controls.Add($tabs)

# Chức năng 1: quản lý license cục bộ
$localManagerTab = New-Object Windows.Forms.TabPage
$localManagerTab.Text = Get-EnterpriseText "enterprise.local.tab"
$localManagerTab.BackColor = $script:enterprisePalette.LocalSurface
$localManagerTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.local.description") 24 24 930 30))
$localManagerTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.local.detail") 24 60 930 42))
$localSafetyLabel = New-EnterpriseLabel (Get-EnterpriseText "enterprise.local.safety") 24 106 930 34
$localSafetyLabel.ForeColor = $script:enterprisePalette.DangerText
$localManagerTab.Controls.Add($localSafetyLabel)
$localManagerButton = New-EnterpriseButton (Get-EnterpriseText "enterprise.local.open") 24 154 280 40 {
    try {
        $env:TOOL_UI_THEME = $script:enterpriseTheme
        $local = Join-Path $baseDir "windows-office-license-manager.ps1"
        $launcher = Get-EnterpriseLauncherPath
        if ($launcher) {
            Start-Process -FilePath $launcher -ArgumentList "--local-license-manager" -Verb RunAs | Out-Null
        } else {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -File `"$local`"" -Verb RunAs | Out-Null
        }
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.local.opened") $true
    } catch {
        Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 900)
    }
}
$localManagerTab.Controls.Add($localManagerButton)
$tabs.TabPages.Add($localManagerTab) | Out-Null

# Chức năng 2: máy chủ
$serverTab = New-Object Windows.Forms.TabPage
$serverTab.Text = Get-EnterpriseText "enterprise.server.tab"
$serverTab.BackColor = $script:enterprisePalette.ServerSurface
$serverTab.AutoScroll = $false
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.description") 18 12 930 28))
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.name") 18 52))
$script:serverNameBox = New-EnterpriseTextBox 145 49 220
$script:serverNameBox.Text = [Environment]::MachineName
$serverTab.Controls.Add($script:serverNameBox)
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.adminCode") 390 52 170))
$script:serverAdminBox = New-EnterpriseTextBox 565 49 210 25 $false $true
$serverTab.Controls.Add($script:serverAdminBox)
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.port") 795 52 40))
$script:serverPortBox = New-EnterpriseTextBox 835 49 80
$script:serverPortBox.Text = [string]$script:ToolEnterpriseDefaultPort
$serverTab.Controls.Add($script:serverPortBox)
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.cidrs") 18 88 470))
$script:serverAddressLabel = New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.addressChecking") 510 88 405
$script:serverAddressLabel.TextAlign = [Drawing.ContentAlignment]::TopRight
$serverTab.Controls.Add($script:serverAddressLabel)
$script:serverCidrBox = New-EnterpriseTextBox 18 115 350 70 $true
$serverTab.Controls.Add($script:serverCidrBox)
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.create") 390 112 180 34 { Invoke-ServerCreate }))
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.pair") 580 112 160 34 { Invoke-ServerPairingCode }))
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.start") 750 112 165 34 { Invoke-ServerStart }))
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.stop") 750 150 165 34 { Stop-EnterpriseServer }))
$deleteServerButton = New-EnterpriseButton (Get-EnterpriseText "enterprise.server.delete") 750 188 165 34 { Invoke-ServerDeleteConfiguration }
$deleteServerButton.ForeColor = $script:enterprisePalette.DangerText
$serverTab.Controls.Add($deleteServerButton)
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.pairingCode") 390 157 250))
$script:pairingOutputBox = New-EnterpriseTextBox 390 182 350
$script:pairingOutputBox.ReadOnly = $true
$serverTab.Controls.Add($script:pairingOutputBox)
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.firewall") 18 195 190 32 { Invoke-ServerNetworkAccess }))
$script:clientCountLabel = New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.pairedCount" @(0)) 195 201 300
$serverTab.Controls.Add($script:clientCountLabel)
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.refresh") 510 195 160 32 { Update-ServerClientList }))
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.export") 680 195 170 32 { Invoke-ServerExport }))
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.compliance") 680 230 170 32 { Invoke-ServerCompliance }))
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.dashboard") 850 195 145 32 { Invoke-ServerDashboard }))
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.scanLabel") 18 242 250))
$script:scanInputBox = New-EnterpriseTextBox 18 270 270
$script:scanInputBox.Text = ""
$serverTab.Controls.Add($script:scanInputBox)
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.scan") 300 268 130 32 { Invoke-ServerScan }))
$script:scanResultBox = New-EnterpriseTextBox 18 307 900 92 $true
$script:scanResultBox.ReadOnly = $true
$script:scanResultBox.Font = $script:enterpriseSmallFont
$serverTab.Controls.Add($script:scanResultBox)
$script:serverAssetGroup = New-Object Windows.Forms.GroupBox
$script:serverAssetGroup.Text = Get-EnterpriseText 'enterprise.server.assetDetailsTitle'
$script:serverAssetGroup.Font = $script:enterpriseFont
$script:serverAssetGroup.ForeColor = $script:enterprisePalette.Text
$script:serverAssetGroup.BackColor = $script:enterprisePalette.ServerSurface
$script:serverAssetGroup.Location = New-Object Drawing.Point(560, 307)
$script:serverAssetGroup.Size = New-Object Drawing.Size(358, 92)
$script:serverAssetDetailLabel = New-EnterpriseLabel (Get-EnterpriseText 'enterprise.server.assetDetailsEmpty') 10 22 330 62
$script:serverAssetGroup.Controls.Add($script:serverAssetDetailLabel)
$script:serverAssetManagerButton = New-EnterpriseButton (Get-EnterpriseText 'enterprise.assetManager.open') 10 56 330 28 { Show-EnterpriseAssetRegistryManager }
$script:serverAssetGroup.Controls.Add($script:serverAssetManagerButton)
$serverTab.Controls.Add($script:serverAssetGroup)
$script:serverClientList = New-Object Windows.Forms.ListView
$script:serverClientList.Location = New-Object Drawing.Point(18, 400)
$script:serverClientList.Size = New-Object Drawing.Size(900, 112)
$script:serverClientList.View = "Details"
$script:serverClientList.FullRowSelect = $true
$script:serverClientList.GridLines = $true
$script:serverClientList.Anchor = "Top,Left,Right"
foreach ($column in @(
    @((Get-EnterpriseText "enterprise.server.clientColumn"),120),
    @((Get-EnterpriseText "enterprise.server.assetColumn"),110),
    @((Get-EnterpriseText "enterprise.server.assignmentColumn"),130),
    @("IP",95),
    @((Get-EnterpriseText "enterprise.server.lastSeenColumn"),140),
    @((Get-EnterpriseText "enterprise.server.activationColumn"),155),
    @("ClientId",190)
)) {
    [void]$script:serverClientList.Columns.Add($column[0], [int]$column[1])
}
$script:serverClientList.Add_SelectedIndexChanged({ Update-EnterpriseServerAssetDetails })
$serverTab.Controls.Add($script:serverClientList)
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.activationNote") 18 516 900 24))
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.job") 18 548 140))
$script:jobOperationBox = New-Object Windows.Forms.ComboBox
$script:jobOperationBox.Location = New-Object Drawing.Point(145, 545)
$script:jobOperationBox.Size = New-Object Drawing.Size(230, 25)
$script:jobOperationBox.DropDownStyle = "DropDownList"
[void]$script:jobOperationBox.Items.Add("InventoryOnly")
[void]$script:jobOperationBox.Items.Add("WindowsInstallAndActivate")
[void]$script:jobOperationBox.Items.Add("OfficeInstallAndActivate")
$script:jobOperationBox.SelectedIndex = 0
$serverTab.Controls.Add($script:jobOperationBox)
$script:jobKeyBox = New-EnterpriseTextBox 390 545 250
$script:jobKeyBox.UseSystemPasswordChar = $true
$serverTab.Controls.Add($script:jobKeyBox)
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.createJob") 655 542 230 34 { Invoke-ServerJob }))
$tabs.TabPages.Add($serverTab) | Out-Null

# Chức năng 3: máy trạm
$clientTab = New-Object Windows.Forms.TabPage
$clientTab.Text = Get-EnterpriseText "enterprise.client.tab"
$clientTab.BackColor = $script:enterprisePalette.ClientSurface
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.description" @($script:enterpriseReleaseDisplayName)) 20 18 920 30))
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.address") 20 65 210))
$script:clientAddressBox = New-EnterpriseTextBox 180 62 260
$clientTab.Controls.Add($script:clientAddressBox)
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.port") 460 65 45))
$script:clientPortBox = New-EnterpriseTextBox 510 62 85
$script:clientPortBox.Text = [string]$script:ToolEnterpriseDefaultPort
$clientTab.Controls.Add($script:clientPortBox)
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.pairingCode") 20 105))
$script:clientPairingBox = New-EnterpriseTextBox 180 102 415
$script:clientPairingBox.UseSystemPasswordChar = $true
$clientTab.Controls.Add($script:clientPairingBox)
$script:clientRemoteChanges = New-Object Windows.Forms.CheckBox
$script:clientRemoteChanges.Text = Get-EnterpriseText "enterprise.client.remoteChanges"
$script:clientRemoteChanges.Location = New-Object Drawing.Point(20, 145)
$script:clientRemoteChanges.Size = New-Object Drawing.Size(520, 28)
$clientTab.Controls.Add($script:clientRemoteChanges)
$script:clientAutoSend = New-Object Windows.Forms.CheckBox
$script:clientAutoSend.Text = Get-EnterpriseText "enterprise.client.autoSend"
$script:clientAutoSend.Checked = $true
$script:clientAutoSend.Location = New-Object Drawing.Point(20, 177)
$script:clientAutoSend.Size = New-Object Drawing.Size(420, 28)
$clientTab.Controls.Add($script:clientAutoSend)
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.discover") 20 220 135 34 { Invoke-ClientDiscover }))
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.test") 165 220 145 34 { Invoke-ClientTest }))
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.enroll") 320 220 160 34 { Invoke-ClientEnroll }))
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.send") 490 220 145 34 { Invoke-ClientSend }))
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.enableAgent") 645 220 145 34 { Invoke-ClientSchedule $true }))
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.disableAgent") 800 220 145 34 { Invoke-ClientSchedule $false }))
$script:clientAssetGroup = New-Object Windows.Forms.GroupBox
$script:clientAssetGroup.Text = Get-EnterpriseText 'enterprise.client.assetSummaryTitle'
$script:clientAssetGroup.Font = $script:enterpriseFont
$script:clientAssetGroup.ForeColor = $script:enterprisePalette.Text
$script:clientAssetGroup.BackColor = $script:enterprisePalette.ClientSurface
$script:clientAssetGroup.Location = New-Object Drawing.Point(20, 268)
$script:clientAssetGroup.Size = New-Object Drawing.Size(925, 78)
$script:clientAssetSummaryLabel = New-EnterpriseLabel '' 10 22 850 58
$script:clientAssetGroup.Controls.Add($script:clientAssetSummaryLabel)
$clientTab.Controls.Add($script:clientAssetGroup)
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.queueNote") 20 285 850 45))
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.keyNote") 20 335 850 45))
$tabs.TabPages.Add($clientTab) | Out-Null

$script:backButton = New-EnterpriseButton (Get-EnterpriseText "enterprise.navigation.back") 18 0 205 32 { Invoke-EnterpriseBack }
$script:closeButton = New-EnterpriseButton (Get-EnterpriseText "enterprise.navigation.close") 0 0 180 32 { Invoke-EnterpriseClose }
$form.Controls.Add($script:backButton)
$form.Controls.Add($script:closeButton)

$tabs.Add_DrawItem({
    param($sender, $e)
    $page = $sender.TabPages[$e.Index]
    $selected = ($sender.SelectedIndex -eq $e.Index)
    $tabColor = $script:enterprisePalette.ServerButton
    $backColor = if ($selected) { $tabColor } else { $script:enterprisePalette.Button }
    $foreColor = if ($selected) { [Drawing.Color]::White } else { $script:enterprisePalette.Text }
    $brush = New-Object Drawing.SolidBrush($backColor)
    $textBrush = New-Object Drawing.SolidBrush($foreColor)
    try {
        $e.Graphics.FillRectangle($brush, $e.Bounds)
        $format = New-Object Drawing.StringFormat
        $format.Alignment = [Drawing.StringAlignment]::Center
        $format.LineAlignment = [Drawing.StringAlignment]::Center
        # PowerShell có thể chọn nhầm overload PointF nếu truyền trực tiếp Rectangle.
        # Tạo RectangleF tường minh để tương thích Windows PowerShell 5.1/WinForms.
        $boundsF = New-Object Drawing.RectangleF
        $boundsF.X = [float]$e.Bounds.X
        $boundsF.Y = [float]$e.Bounds.Y
        $boundsF.Width = [float]$e.Bounds.Width
        $boundsF.Height = [float]$e.Bounds.Height
        $e.Graphics.DrawString($page.Text, $sender.Font, $textBrush, $boundsF, $format)
        $format.Dispose()
    } finally {
        $brush.Dispose()
        $textBrush.Dispose()
    }
})

foreach ($button in @($localManagerTab.Controls | Where-Object { $_ -is [Windows.Forms.Button] })) {
    Set-EnterpriseButtonStyle $button $script:enterprisePalette.LocalButton ([Drawing.Color]::White) $script:enterprisePalette.LocalHover
}
foreach ($button in @($serverTab.Controls | Where-Object { $_ -is [Windows.Forms.Button] })) {
    Set-EnterpriseButtonStyle $button $script:enterprisePalette.ServerButton ([Drawing.Color]::White) $script:enterprisePalette.ServerHover
}
foreach ($button in @($clientTab.Controls | Where-Object { $_ -is [Windows.Forms.Button] })) {
    Set-EnterpriseButtonStyle $button $script:enterprisePalette.ClientButton ([Drawing.Color]::White) $script:enterprisePalette.ClientHover
}
$deleteServerButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.delete")
Set-EnterpriseButtonStyle $deleteServerButton $script:enterprisePalette.Danger ([Drawing.Color]::White) $script:enterprisePalette.DangerHover
Set-EnterpriseButtonStyle $script:backButton $script:enterprisePalette.Navigation ([Drawing.Color]::White) $script:enterprisePalette.NavigationHover
Set-EnterpriseButtonStyle $script:closeButton $script:enterprisePalette.Danger ([Drawing.Color]::White) $script:enterprisePalette.DangerHover
Update-EnterpriseNetworkStateUi -UpdateStatus
$script:serverClientList.BackColor = $script:enterprisePalette.Surface
$script:serverClientList.ForeColor = $script:enterprisePalette.Text
$script:jobOperationBox.BackColor = $script:enterprisePalette.Input
$script:jobOperationBox.ForeColor = $script:enterprisePalette.Text
$script:clientRemoteChanges.ForeColor = $script:enterprisePalette.Text
$script:clientAutoSend.ForeColor = $script:enterprisePalette.Text
Register-ToolUiDynamicContrast -Root $form -Mode $script:enterpriseTheme

$form.Add_Shown({
    try {
        Fit-EnterpriseWindowToWorkingArea
        Update-EnterpriseLayout
        [void](Update-EnterpriseDetectedServerAddress)
        $cfg = Get-EnterpriseServerConfigurationSafe
        if ($cfg) {
            $script:serverNameBox.Text = [string]$cfg.ServerName
            $script:serverPortBox.Text = [string]$cfg.Port
            $script:serverCidrBox.Text = (@($cfg.AllowedCidrs) -join [Environment]::NewLine)
        }
        if ([string]::IsNullOrWhiteSpace($script:scanInputBox.Text)) {
            $defaultCidrs = if ($cfg) { @($cfg.AllowedCidrs) } else { @(Get-ToolEnterpriseLocalCidrs) }
            if ($defaultCidrs.Count -gt 0) { $script:scanInputBox.Text = [string]$defaultCidrs[0] }
        }
        $clientCfg = Get-ToolEnterpriseClientConfig
        if ($clientCfg) {
            $script:clientAddressBox.Text = [string]$clientCfg.ServerAddress
            $script:clientPortBox.Text = [string]$clientCfg.Port
            $script:clientRemoteChanges.Checked = [bool]$clientCfg.AllowRemoteLicenseChanges
            $script:clientAutoSend.Checked = [bool]$clientCfg.AutoSend
        }
        Update-ServerClientList
        Update-EnterpriseClientAssetSummary
        Update-EnterpriseLayout
        Update-EnterpriseLifecycleStatus
    } catch {}
})
$form.Add_Resize({ Update-EnterpriseLayout })
$tabs.Add_SelectedIndexChanged({
    $script:previousTabIndex = $tabs.SelectedIndex
    $tabs.Invalidate()
    if (-not $script:enterpriseNetworkAllowed -and $tabs.SelectedIndex -gt 0) {
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.blockedStatus") $true
    }
    Update-EnterpriseLayout
})
$form.Add_Activated({ [void](Update-EnterpriseDetectedServerAddress) })
$form.Add_FormClosed({
    foreach ($font in @($script:enterpriseFont,$script:enterpriseSmallFont,$script:enterpriseTitleFont)) { try { $font.Dispose() } catch {} }
    try { $script:enterpriseToolTip.Dispose() } catch {}
})
if ($SmokeTest) {
    if ($tabs.TabPages.Count -ne 3) { throw (Get-EnterpriseText "enterpriseSmoke.tabCount") }
    if ($tabs.TabPages[0].Text -ne (Get-EnterpriseText "enterprise.local.tab") -or
        $tabs.TabPages[1].Text -ne (Get-EnterpriseText "enterprise.server.tab") -or
        $tabs.TabPages[2].Text -ne (Get-EnterpriseText "enterprise.client.tab")) {
        throw (Get-EnterpriseText "enterpriseSmoke.tabNames")
    }
    if (-not $localManagerButton -or $localManagerButton.Text -ne (Get-EnterpriseText "enterprise.local.open")) {
        throw (Get-EnterpriseText "enterpriseSmoke.localManagerMissing")
    }
    if (-not $backButton -or -not $closeButton) { throw (Get-EnterpriseText "enterpriseSmoke.navigationMissing") }
    if (-not $script:enterpriseNetworkButton -or -not $form.Controls.Contains($script:enterpriseNetworkButton)) {
        throw (Get-EnterpriseText "enterpriseSmoke.networkControlMissing")
    }
    if (-not $script:enterpriseNetworkAllowed -and (-not $serverTab.Enabled -or -not $clientTab.Enabled)) {
        throw (Get-EnterpriseText "enterpriseSmoke.offlineTabsUnavailable")
    }
    if ($form.BackColor.ToArgb() -ne $script:enterprisePalette.Form.ToArgb() -or
        $localManagerTab.BackColor.ToArgb() -ne $script:enterprisePalette.LocalSurface.ToArgb() -or
        $serverTab.BackColor.ToArgb() -ne $script:enterprisePalette.ServerSurface.ToArgb() -or
        $clientTab.BackColor.ToArgb() -ne $script:enterprisePalette.ClientSurface.ToArgb()) {
        throw (Get-EnterpriseText "enterpriseSmoke.themeCoverage" @($script:enterpriseTheme))
    }
    if ($script:serverNameBox.BackColor.ToArgb() -ne $script:enterprisePalette.Input.ToArgb() -or
        $script:serverClientList.BackColor.ToArgb() -ne $script:enterprisePalette.Surface.ToArgb()) {
        throw (Get-EnterpriseText "enterpriseSmoke.themeInputs" @($script:enterpriseTheme))
    }
    if ((Get-ToolUiContrastRatio -Foreground $script:enterprisePalette.Text -Background $script:enterprisePalette.Form) -lt 4.5 -or
        (Get-ToolUiContrastRatio -Foreground $script:enterprisePalette.Text -Background $script:enterprisePalette.Input) -lt 4.5) {
        throw (Get-EnterpriseText "enterpriseSmoke.themeContrast" @($script:enterpriseTheme))
    }
    $form.Opacity = 0
    $form.ShowInTaskbar = $false
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    $form.ClientSize = New-Object Drawing.Size(980, 620)
    Update-EnterpriseLayout
    $tabs.Refresh()
    [Windows.Forms.Application]::DoEvents()
    if ([string]::IsNullOrWhiteSpace($script:scanInputBox.Text)) {
        throw (Get-EnterpriseText "enterpriseSmoke.defaultCidrMissing")
    }
    if ($serverTab.AutoScroll -or $serverTab.HorizontalScroll.Visible) { throw (Get-EnterpriseText "enterpriseSmoke.horizontalScroll") }
    foreach ($buttonText in @(
        (Get-EnterpriseText "enterprise.server.create"),
        (Get-EnterpriseText "enterprise.server.pair"),
        (Get-EnterpriseText "enterprise.server.start"),
        (Get-EnterpriseText "enterprise.server.stop"),
        (Get-EnterpriseText "enterprise.server.delete"),
        (Get-EnterpriseText "enterprise.server.firewall"),
        (Get-EnterpriseText "enterprise.server.scan"),
        (Get-EnterpriseText "enterprise.server.refresh"),
        (Get-EnterpriseText "enterprise.server.export"),
        (Get-EnterpriseText "enterprise.server.dashboard"),
        (Get-EnterpriseText "enterprise.server.createJob")
    )) {
        $button = Find-EnterpriseDirectControl $serverTab $buttonText
        if (-not $button -or $button.Width -lt 60 -or $button.Right -gt ($serverTab.ClientSize.Width + 1)) {
            throw (Get-EnterpriseText "enterpriseSmoke.buttonClipped" @($buttonText))
        }
    }
    if ($script:serverClientList.Bottom -gt ($serverTab.ClientSize.Height + 1) -or $script:jobKeyBox.Right -gt ($serverTab.ClientSize.Width + 1)) {
        throw (Get-EnterpriseText "enterpriseSmoke.serverLayoutClipped")
    }
    if (-not $serverTab.Controls.Contains($script:serverAssetGroup) -or $script:serverAssetGroup.Right -gt ($serverTab.ClientSize.Width + 1) -or
        -not $clientTab.Controls.Contains($script:clientAssetGroup) -or $script:clientAssetGroup.Right -gt ($clientTab.ClientSize.Width + 1)) {
        throw (Get-EnterpriseText "enterpriseSmoke.serverLayoutClipped")
    }
    if (-not $script:serverAssetManagerButton -or
        -not $script:serverAssetGroup.Controls.Contains($script:serverAssetManagerButton) -or
        $script:serverAssetManagerButton.Text -ne (Get-EnterpriseText 'enterprise.assetManager.open') -or
        $script:serverAssetManagerButton.Right -gt ($script:serverAssetGroup.ClientSize.Width + 1) -or
        $script:serverAssetManagerButton.Bottom -gt ($script:serverAssetGroup.ClientSize.Height + 1)) {
        throw (Get-EnterpriseText "enterpriseSmoke.serverLayoutClipped")
    }
    $discoverButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.discover")
    if (-not $discoverButton -or $discoverButton.Right -gt ($clientTab.ClientSize.Width + 1)) {
        throw (Get-EnterpriseText "enterpriseSmoke.discoverClipped")
    }
    foreach ($tabIndex in 0..2) {
        $tabs.SelectedIndex = $tabIndex
        Update-EnterpriseLayout
        [Windows.Forms.Application]::DoEvents()
    }
    $clippedButtonLabels = @(Get-EnterpriseClippedButtonLabels -Root $form | Select-Object -Unique)
    if ($clippedButtonLabels.Count -gt 0) {
        throw (Get-EnterpriseText "enterpriseSmoke.buttonClipped" @(($clippedButtonLabels -join ', ')))
    }
    $tabs.SelectedIndex = 2
    $backButton.PerformClick()
    [Windows.Forms.Application]::DoEvents()
    if ($tabs.SelectedIndex -ne 1) { throw (Get-EnterpriseText "enterpriseSmoke.backNavigation") }
    if ($closeButton.Text -ne (Get-EnterpriseText "enterprise.navigation.close")) { throw (Get-EnterpriseText "enterpriseSmoke.closeLabel") }
    $networkStateBefore = [bool]$script:enterpriseNetworkAllowed
    $script:enterpriseNetworkButton.PerformClick()
    [Windows.Forms.Application]::DoEvents()
    if ([bool]$script:enterpriseNetworkAllowed -eq $networkStateBefore) { throw (Get-EnterpriseText "enterpriseSmoke.networkDidNotToggle") }
    $script:enterpriseNetworkButton.PerformClick()
    [Windows.Forms.Application]::DoEvents()
    if ([bool]$script:enterpriseNetworkAllowed -ne $networkStateBefore) { throw (Get-EnterpriseText "enterpriseSmoke.networkDidNotRestore") }
    if ($script:enterpriseCulture -eq "en-US") {
        $visibleText = New-Object System.Collections.Generic.List[string]
        $controlQueue = New-Object System.Collections.Queue
        $controlQueue.Enqueue($form)
        while ($controlQueue.Count -gt 0) {
            $currentControl = $controlQueue.Dequeue()
            if (-not [string]::IsNullOrWhiteSpace([string]$currentControl.Text)) {
                [void]$visibleText.Add([string]$currentControl.Text)
            }
            foreach ($childControl in $currentControl.Controls) { $controlQueue.Enqueue($childControl) }
        }
        foreach ($column in $script:serverClientList.Columns) {
            if (-not [string]::IsNullOrWhiteSpace([string]$column.Text)) { [void]$visibleText.Add([string]$column.Text) }
        }
        $englishSurface = $visibleText -join "`n"
        if ($englishSurface -cmatch '[À-ỹ]') {
            throw (Get-EnterpriseText "enterpriseSmoke.englishLeak" @($englishSurface))
        }
    }
    Write-Output (Get-EnterpriseText "enterpriseSmoke.pass" @($script:enterpriseCulture, $script:enterpriseNetworkAllowed, $script:enterpriseTheme))
    $closeButton.PerformClick()
    [Windows.Forms.Application]::DoEvents()
    if (-not $form.IsDisposed -and $form.Visible) { throw (Get-EnterpriseText "enterpriseSmoke.closeFailed") }
    foreach ($font in @($script:enterpriseFont,$script:enterpriseSmallFont,$script:enterpriseTitleFont)) { try { $font.Dispose() } catch {} }
    $form.Dispose()
    exit 0
}
[void]$form.ShowDialog()
