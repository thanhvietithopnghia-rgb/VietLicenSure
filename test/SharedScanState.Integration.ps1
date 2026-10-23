$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Tool-ResultCenter.ps1')
$checks = 0
function Check([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message}; $script:checks++ }

$temp = Join-Path ([IO.Path]::GetTempPath()) ('VietLicenSure-SharedScan-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp -Force)
try {
    $binding = Get-ToolResultMachineBinding
    $now = Get-Date
    function Write-Report([string]$Name,[string]$MachineBinding,[string]$BuildId,[datetime]$CreatedAt,[string]$Mode='Windows') {
        $jsonPath = Join-Path $temp ($Name + '.json')
        $htmlPath = Join-Path $temp ($Name + '.html')
        $report = [ordered]@{
            ReportKind='InventoryAndLicense'; ToolVersion='5.0'; BuildId=$BuildId
            MachineBinding=$MachineBinding; ComputerName=[string]$env:COMPUTERNAME
            CreatedAt=$CreatedAt.ToString('o'); Mode=$Mode; Redacted=$true; RefreshKind='Full'
            WindowsConclusionCode='Licensed'; WindowsConclusion='Licensed'; DetailedInventory=[ordered]@{}
        }
        [IO.File]::WriteAllText($jsonPath, ($report|ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($htmlPath, '<!doctype html><title>report</title>', (New-Object Text.UTF8Encoding($false)))
        (Get-Item -LiteralPath $jsonPath).LastWriteTime = $CreatedAt
        (Get-Item -LiteralPath $htmlPath).LastWriteTime = $CreatedAt
        return $jsonPath
    }

    [void](Write-Report -Name 'previous' -MachineBinding $binding -BuildId 'build-current' -CreatedAt $now.AddMinutes(-12))
    [void](Write-Report -Name 'latest' -MachineBinding $binding -BuildId 'build-current' -CreatedAt $now.AddMinutes(-3))
    [void](Write-Report -Name 'foreign' -MachineBinding ('F' * 64) -BuildId 'build-current' -CreatedAt $now.AddMinutes(-1))

    $history = @(Get-ToolResultReportHistory -ReportRoot $temp)
    Check ($history.Count -eq 2) 'Foreign-machine report was not filtered'
    Check ([IO.Path]::GetFileName($history[0].Path) -eq 'latest.json') 'Latest local report was not selected'
    Check ([string]$history[0].MachineBinding -eq $binding) 'Machine binding was not preserved'

    $state = Get-ToolSharedScanState -ReportRoot $temp -Mode Windows -CurrentBuildId 'build-current' -FreshnessMinutes 30
    Check ($state.Status -eq 'Current' -and $state.IsFresh) 'Fresh local report is not current'
    Check ($state.Latest.Path -like '*latest.json') 'Shared state did not return latest report'
    Check ($state.Previous.Path -like '*previous.json') 'Shared state did not retain comparison baseline'
    Check (Test-Path -LiteralPath $state.HtmlPath -PathType Leaf) 'HTML details path is missing'

    $script:workspaceRole = 'personal'; $personalState = Get-ToolSharedScanState -ReportRoot $temp -Mode Windows -CurrentBuildId 'build-current'
    $script:workspaceRole = 'itam'; $itamState = Get-ToolSharedScanState -ReportRoot $temp -Mode Windows -CurrentBuildId 'build-current'
    Check ($personalState.Latest.Path -eq $itamState.Latest.Path) 'Roles do not share the same machine result'

    $stale = Get-ToolSharedScanState -ReportRoot $temp -Mode Windows -CurrentBuildId 'different-build'
    Check (-not $stale.IsFresh -and $stale.Reason -eq 'BuildChanged') 'Build change did not force a full refresh'

    $executionSource = Get-Content -LiteralPath (Join-Path $root 'Dashboard-Execution.ps1') -Raw -Encoding UTF8
    $layoutSource = Get-Content -LiteralPath (Join-Path $root 'Dashboard-Core.ps1') -Raw -Encoding UTF8
    $reportSource = Get-Content -LiteralPath (Join-Path $root 'kiem-tra-cau-hinh-ban-quyen.ps1') -Raw -Encoding UTF8
    Check ($executionSource -match 'activeProcess.+HasExited' -and $executionSource -match 'sharedScan\.duplicateBlocked') 'Duplicate in-flight scan is not blocked'
    Check ($executionSource -match "Profile = 'Quick'" -and $executionSource -match 'IncrementalRefresh') 'Fresh result does not select quick incremental refresh'
    Check ($executionSource -match 'BaselineReportPath') 'Incremental baseline is not passed to the report engine'
    Check ($layoutSource -match 'tileColumnCount = if \(\$personalWorkspace\) \{ 1 \}') 'Personal actions are not a vertical single column'
    Check ($layoutSource -match 'sharedResultCaption' -and $layoutSource -match 'sharedResultDetailButton') 'Inline summary/details layout is missing'
    Check ($reportSource -match 'MachineBinding = Get-ToolResultMachineBinding') 'Report is not bound to the current machine'
    Check ($reportSource.Contains('BaselineReportSha256') -and $reportSource.Contains("RefreshKind = `$(if (`$IncrementalRefresh)")) 'Report does not record incremental provenance'

    [pscustomobject]@{Passed=$true;Checks=$checks;MachineBinding=$binding;Mode='Shared per-device current result with incremental comparison'} | ConvertTo-Json -Compress
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
