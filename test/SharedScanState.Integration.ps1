$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
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

    foreach ($index in 1..8) {
        [void](Write-Report -Name ("office-$index") -MachineBinding $binding -BuildId 'build-current' -CreatedAt $now.AddSeconds(-$index) -Mode 'Office')
    }

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

    $officeQuick = Get-ToolSharedScanQuickSummary -Mode Office -Report ([pscustomobject][ordered]@{
        OfficeConclusionCode='KmsUnapprovedHost'; OfficeConclusion='Office KMS host is not approved.'
        OfficeAdvisor=[pscustomobject]@{ EvidenceSourceCount=3; Confidence='High' }
    })
    Check ($officeQuick.Kind -eq 'License' -and $officeQuick.Risk -eq 'High') 'Office KMS risk was not summarized as high'
    Check ($officeQuick.Code -eq 'KmsUnapprovedHost' -and $officeQuick.EvidenceSourceCount -eq 3) 'Office quick evidence summary is incomplete'

    $softwareQuick = Get-ToolSharedScanQuickSummary -Mode Software -Report ([pscustomobject][ordered]@{
        ThirdPartyHighSeverityCount=1
        DetailedInventory=[pscustomobject][ordered]@{ Software=[pscustomobject][ordered]@{
            ThirdPartyApplications=@(
                [pscustomobject]@{ Name='Paid'; LicenseModel='Paid'; AssessmentCode='Unverified'; IsSystemComponent=$false },
                [pscustomobject]@{ Name='Free'; LicenseModel='Free'; AssessmentCode='FreeOrIncluded'; IsSystemComponent=$false },
                [pscustomobject]@{ Name='Freemium'; LicenseModel='Freemium'; AssessmentCode='FreeOrIncluded'; IsSystemComponent=$false },
                [pscustomobject]@{ Name='Unknown'; LicenseModel='Unknown'; AssessmentCode='Suspicious'; IsSystemComponent=$false },
                [pscustomobject]@{ Name='Driver'; LicenseModel='Driver'; AssessmentCode='FreeOrIncluded'; IsSystemComponent=$true }
            )
        }; ActivatorFindings=@([pscustomobject]@{ Indicator='fixture' }) }
    })
    Check ($softwareQuick.Total -eq 4 -and $softwareQuick.Paid -eq 1 -and $softwareQuick.Free -eq 2 -and $softwareQuick.Unknown -eq 1) 'Software quick counts are incorrect'
    Check ($softwareQuick.Intervention -eq 2 -and $softwareQuick.High -eq 1) 'Software intervention summary is incorrect'

    $scopeFixture = [pscustomobject][ordered]@{
        Mode='Windows'; WindowsConclusionCode='Licensed'; WindowsConclusion='Windows licensed'
        OfficeConclusionCode='KmsUnapprovedHost'; OfficeConclusion='Office risk'
        DetailedInventory=[pscustomobject][ordered]@{
            Hardware=[pscustomobject][ordered]@{ Security=[pscustomobject][ordered]@{
                SecureBoot=[pscustomobject]@{ Supported=$true; Enabled=$false; Error='' }
            }}
            Software=[pscustomobject][ordered]@{ ThirdPartyApplications=@(
                [pscustomobject]@{ Name='Paid product'; Publisher='Vendor'; LicenseModel='Paid'; AssessmentCode='Unverified'; IsSystemComponent=$false }
            )}
            ActivatorFindings=@([pscustomobject]@{ Indicator='fixture'; Source='test'; Location='fixture' })
        }
    }
    $windowsItems = @(ConvertTo-ToolResultCenterItems -Report $scopeFixture)
    Check ($windowsItems.Count -eq 1 -and [string]$windowsItems[0].Category -eq 'Windows') 'Windows mode leaked Office, software, or hardware items'
    $scopeFixture.Mode = 'Office'
    $officeItems = @(ConvertTo-ToolResultCenterItems -Report $scopeFixture)
    Check ($officeItems.Count -eq 1 -and [string]$officeItems[0].Category -eq 'Office') 'Office mode leaked Windows, software, or hardware items'
    $scopeFixture.Mode = 'Software'
    $softwareItems = @(ConvertTo-ToolResultCenterItems -Report $scopeFixture)
    Check ($softwareItems.Count -eq 2 -and @($softwareItems | Where-Object Category -ne 'Software').Count -eq 0) 'Software mode leaked another result category'

    $executionSource = Get-Content -LiteralPath (Join-Path $root 'Dashboard-Execution.ps1') -Raw -Encoding UTF8
    $layoutSource = Get-Content -LiteralPath (Join-Path $root 'Dashboard-Core.ps1') -Raw -Encoding UTF8
    $reportSource = Get-Content -LiteralPath (Join-Path $root 'kiem-tra-cau-hinh-ban-quyen.ps1') -Raw -Encoding UTF8
    $guiSource = Get-Content -LiteralPath (Join-Path $root 'Giao-Dien.ps1') -Raw -Encoding UTF8
    $roleSource = Get-Content -LiteralPath (Join-Path $root 'Dashboard-RoleWorkspaces.ps1') -Raw -Encoding UTF8
    Check ($executionSource -match 'activeProcess.+HasExited' -and $executionSource -match 'sharedScan\.duplicateBlocked') 'Duplicate in-flight scan is not blocked'
    Check ($executionSource -match "Profile = 'Quick'" -and $executionSource -match 'IncrementalRefresh') 'Fresh result does not select quick incremental refresh'
    Check ($executionSource -match 'BaselineReportPath') 'Incremental baseline is not passed to the report engine'
    Check ($executionSource -match 'sharedScan\.attemptFailed' -and $executionSource -match 'sharedScan\.lastSuccessStale') 'Failed-attempt and previous-success timestamps are not separated'
    Check ($guiSource -match 'progress\.failed\.elevatedBridge') 'Exit code 87 is still reported as an unexplained generic failure'
    Check ($layoutSource -match 'tileColumnCount = if \(\$personalWorkspace\) \{ 1 \}') 'Personal actions are not a vertical single column'
    Check ($layoutSource -match 'sharedResultCaption' -and $layoutSource -match 'sharedResultDetailButton') 'Inline summary/details layout is missing'
    Check ($layoutSource -match 'sharedResultSummaryLabel\.Height = 68' -and $layoutSource -match 'sharedResultTimeLabel\.Height = 42') 'Inline result labels do not reserve three-line summary space'
    Check ($layoutSource -match '\$activityActionGap = 4' -and
        $layoutSource -match 'closeButton\.Top = \$activityPanel\.ClientSize\.Height - \$closeButton\.Height - 8' -and
        ([regex]::Matches($layoutSource, '- \$activityActionGap').Count -ge 3)) 'Compact activity action spacing is not locked for the 1024x768 viewport'

    # Mirror the fixed vertical stack at the minimum packaged viewport.  The
    # shared caption must start below the 48..90px status band while retaining
    # the full 68px three-line summary and 42px timestamp block.
    $activityPanelHeight = 410
    $closeTop = $activityPanelHeight - 30 - 8
    $copyTop = $closeTop - 32 - 4
    $folderTop = $copyTop - 32 - 4
    $detailTop = $folderTop - 32 - 4
    $timeTop = $detailTop - 42 - 4
    $summaryTop = $timeTop - 68 - 2
    $stateTop = $summaryTop - 26 - 2
    $captionTop = $stateTop - 22 - 4
    Check ($captionTop -ge 94) "Shared result caption overlaps the status band at 1024x768: top=$captionTop"
    Check ($reportSource -match 'MachineBinding = Get-ToolResultMachineBinding') 'Report is not bound to the current machine'
    Check ($reportSource.Contains('BaselineReportSha256') -and $reportSource.Contains("RefreshKind = `$(if (`$IncrementalRefresh)")) 'Report does not record incremental provenance'
    Check ($executionSource -match "mode -in @\('Windows','Office','Software'\).+NoOpen") 'Windows/Office/Software reports still auto-open HTML'
    Check ($guiSource -match 'progress\.completed\.summaryReady') 'Report completion does not announce the inline quick result'
    Check ($roleSource -match 'Set-RoleWorkspaceButtonVisual' -and $roleSource -match 'SuspendLayout' -and $roleSource -match 'ResumeLayout') 'Role emphasis or flicker-controlled switching is missing'
    Check ($roleSource -match 'sharedScanDisplayInitialized' -and $roleSource -notmatch 'Update-SharedScanResultDisplay') 'Role switching still reparses result history synchronously'
    Check ($reportSource -match '(?s)if \(\$wantWindows\).+?summaryCardsHtml\.Append' -and
        $reportSource -match '(?s)if \(\$wantOffice\).+?summaryCardsHtml\.Append' -and
        $reportSource -match '\$summaryCardsClass = ''cards-count-''') 'Report summary cards are not scoped to the selected mode'

    $vi = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'Tool-Strings.vi-VN.json') | ConvertFrom-Json
    $summaryText = [string]::Format([string]$vi.'sharedScan.quick.licenseSummary', @('Đã ghi nhận kích hoạt kỹ thuật', 3, 'CẦN RÀ SOÁT'))
    Check (($summaryText -split "`r?`n").Count -eq 3) 'Quick result is not a three-line observed/verify/conclusion summary'
    $summaryFont = New-Object Drawing.Font('Segoe UI', 8.25)
    try {
        $measured = [Windows.Forms.TextRenderer]::MeasureText(
            $summaryText, $summaryFont, (New-Object Drawing.Size(560, 200)),
            ([Windows.Forms.TextFormatFlags]::WordBreak -bor [Windows.Forms.TextFormatFlags]::NoPrefix))
        Check ($measured.Height -le 68) "Three-line quick result exceeds reserved height: $($measured.Height)"
    } finally { $summaryFont.Dispose() }

    [pscustomobject]@{Passed=$true;Checks=$checks;MachineBinding=$binding;Mode='Shared per-device current result with incremental comparison'} | ConvertTo-Json -Compress
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
