# VietLicenSure v5.0 - dot-sourced function library
# Extracted mechanically from Giao-Dien.ps1; contains function definitions only.
# Keep this file beside its compatible entrypoint.

function Write-DashboardStartupTrace {
    param([Parameter(Mandatory = $true)][string]$Stage)
    if (-not $script:startupTraceClock) { return }
    try {
        $traceDirectory = Split-Path -Parent $script:startupTracePath
        if ($traceDirectory -and -not (Test-Path -LiteralPath $traceDirectory -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $traceDirectory -Force)
        }
        $traceLine = "{0:o}`t{1:N3}`t{2}`r`n" -f [DateTime]::UtcNow, $script:startupTraceClock.Elapsed.TotalSeconds, $Stage
        [IO.File]::AppendAllText($script:startupTracePath, $traceLine, $script:startupTraceEncoding)
    } catch {}
}

function Get-DashboardText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )
    if (Get-Command Get-ToolText -ErrorAction SilentlyContinue) {
        return Get-ToolText -Key $Key -Culture $script:dashboardCulture -FormatArguments $Arguments
    }
    return "[$Key]"
}

function New-DashboardRoundedPath {
    param(
        [single]$X,
        [single]$Y,
        [single]$Width,
        [single]$Height,
        [single]$Radius
    )
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = [single]([Math]::Max(2, $Radius * 2))
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc(($X + $Width - $diameter), $Y, $diameter, $diameter, 270, 90)
    $path.AddArc(($X + $Width - $diameter), ($Y + $Height - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc($X, ($Y + $Height - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-DashboardIconBitmap {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            "Windows", "Office", "Shield", "Check", "Search", "Hardware", "Software",
            "Repair", "Key", "License", "DeepScan", "Report", "NavOverview", "NavScan",
            "NavRepair", "NavReport", "NavSettings", "Chat"
        )]
        [string]$Kind,
        [ValidateRange(16, 96)][int]$Size = 40
    )

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $blueBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 212))
    $lightBlueBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30, 126, 229))
    $officeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(242, 80, 34))
    $officeDarkBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(205, 51, 20))
    $greenBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 158, 96))
    $cyanBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 150, 170))
    $purpleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(126, 75, 214))
    $amberBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 138, 0))
    $tealBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 132, 112))
    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $transparentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Transparent)
    $whitePen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3.2)
    $whiteThinPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.2)
    $mintPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 227, 176), 2.1)
    $navPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.8)
    foreach ($pen in @($whitePen, $whiteThinPen, $mintPen, $navPen)) {
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    }

    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $scale = [single]($Size / 48.0)
        $graphics.ScaleTransform($scale, $scale)

        switch ($Kind) {
            "Windows" {
                $graphics.FillPolygon($blueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(5, 9)), (New-Object System.Drawing.PointF(22, 7)),
                    (New-Object System.Drawing.PointF(22, 22)), (New-Object System.Drawing.PointF(5, 22))))
                $graphics.FillPolygon($lightBlueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(25, 6)), (New-Object System.Drawing.PointF(43, 4)),
                    (New-Object System.Drawing.PointF(43, 22)), (New-Object System.Drawing.PointF(25, 22))))
                $graphics.FillPolygon($blueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(5, 25)), (New-Object System.Drawing.PointF(22, 25)),
                    (New-Object System.Drawing.PointF(22, 41)), (New-Object System.Drawing.PointF(5, 39))))
                $graphics.FillPolygon($lightBlueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(25, 25)), (New-Object System.Drawing.PointF(43, 25)),
                    (New-Object System.Drawing.PointF(43, 44)), (New-Object System.Drawing.PointF(25, 42))))
            }
            "Office" {
                $graphics.FillPolygon($officeBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(9, 8)), (New-Object System.Drawing.PointF(28, 2)),
                    (New-Object System.Drawing.PointF(41, 8)), (New-Object System.Drawing.PointF(41, 40)),
                    (New-Object System.Drawing.PointF(28, 46)), (New-Object System.Drawing.PointF(9, 40))))
                $graphics.FillPolygon($officeDarkBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(9, 8)), (New-Object System.Drawing.PointF(29, 13)),
                    (New-Object System.Drawing.PointF(29, 37)), (New-Object System.Drawing.PointF(9, 40))))
                $graphics.FillPolygon($whiteBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(16, 14)), (New-Object System.Drawing.PointF(25, 16)),
                    (New-Object System.Drawing.PointF(25, 34)), (New-Object System.Drawing.PointF(16, 35))))
            }
            "Shield" {
                $graphics.FillPolygon($lightBlueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(24, 3)), (New-Object System.Drawing.PointF(41, 10)),
                    (New-Object System.Drawing.PointF(38, 31)), (New-Object System.Drawing.PointF(24, 45)),
                    (New-Object System.Drawing.PointF(10, 31)), (New-Object System.Drawing.PointF(7, 10))))
                $graphics.FillPolygon($blueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(24, 8)), (New-Object System.Drawing.PointF(36, 13)),
                    (New-Object System.Drawing.PointF(34, 29)), (New-Object System.Drawing.PointF(24, 39)),
                    (New-Object System.Drawing.PointF(14, 29)), (New-Object System.Drawing.PointF(12, 13))))
                $graphics.DrawLines($whitePen, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(14, 23)), (New-Object System.Drawing.PointF(22, 32)),
                    (New-Object System.Drawing.PointF(36, 14))))
                $graphics.DrawLine($mintPen, 22, 32, 36, 14)
            }
            "Check" {
                $graphics.FillPolygon($greenBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(24, 3)), (New-Object System.Drawing.PointF(41, 10)),
                    (New-Object System.Drawing.PointF(38, 31)), (New-Object System.Drawing.PointF(24, 45)),
                    (New-Object System.Drawing.PointF(10, 31)), (New-Object System.Drawing.PointF(7, 10))))
                $graphics.DrawLines($whitePen, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(14, 24)), (New-Object System.Drawing.PointF(21, 31)),
                    (New-Object System.Drawing.PointF(34, 17))))
            }
            "Search" {
                $graphics.FillEllipse($blueBrush, 3, 3, 42, 42)
                $graphics.DrawEllipse($whitePen, 11, 10, 19, 19)
                $graphics.DrawLine($whitePen, 28, 28, 38, 38)
            }
            "Hardware" {
                $backgroundPath = New-DashboardRoundedPath -X 3 -Y 3 -Width 42 -Height 42 -Radius 8
                try { $graphics.FillPath($cyanBrush, $backgroundPath) } finally { $backgroundPath.Dispose() }
                $graphics.DrawRectangle($whiteThinPen, 14, 14, 20, 20)
                $graphics.DrawRectangle($whiteThinPen, 18, 18, 12, 12)
                foreach ($offset in @(17, 23, 29)) {
                    $graphics.DrawLine($whiteThinPen, $offset, 9, $offset, 14)
                    $graphics.DrawLine($whiteThinPen, $offset, 34, $offset, 39)
                    $graphics.DrawLine($whiteThinPen, 9, $offset, 14, $offset)
                    $graphics.DrawLine($whiteThinPen, 34, $offset, 39, $offset)
                }
            }
            "Software" {
                $backgroundPath = New-DashboardRoundedPath -X 3 -Y 3 -Width 42 -Height 42 -Radius 8
                try { $graphics.FillPath($purpleBrush, $backgroundPath) } finally { $backgroundPath.Dispose() }
                foreach ($x in @(13, 25)) {
                    foreach ($y in @(13, 25)) { $graphics.FillRectangle($whiteBrush, $x, $y, 9, 9) }
                }
            }
            "Repair" {
                $graphics.FillEllipse($amberBrush, 3, 3, 42, 42)
                $graphics.DrawLine($whitePen, 16, 33, 32, 17)
                $graphics.DrawArc($whitePen, 27, 10, 11, 11, 25, 245)
                $graphics.DrawEllipse($whiteThinPen, 11, 31, 7, 7)
            }
            "Key" {
                $graphics.FillEllipse($amberBrush, 3, 3, 42, 42)
                $graphics.DrawEllipse($whitePen, 11, 11, 13, 13)
                $graphics.DrawLine($whitePen, 22, 22, 37, 37)
                $graphics.DrawLine($whitePen, 31, 31, 35, 27)
                $graphics.DrawLine($whitePen, 35, 35, 39, 31)
            }
            "License" {
                $backgroundPath = New-DashboardRoundedPath -X 3 -Y 3 -Width 42 -Height 42 -Radius 8
                try { $graphics.FillPath($greenBrush, $backgroundPath) } finally { $backgroundPath.Dispose() }
                $graphics.DrawRectangle($whiteThinPen, 12, 9, 24, 30)
                $graphics.DrawLine($whiteThinPen, 17, 16, 31, 16)
                $graphics.DrawLine($whiteThinPen, 17, 21, 27, 21)
                $graphics.DrawLines($whiteThinPen, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(18, 30)), (New-Object System.Drawing.PointF(22, 34)),
                    (New-Object System.Drawing.PointF(31, 25))))
            }
            "DeepScan" {
                $graphics.FillEllipse($purpleBrush, 3, 3, 42, 42)
                $graphics.DrawEllipse($whiteThinPen, 9, 9, 27, 27)
                $graphics.DrawLine($whitePen, 34, 34, 40, 40)
                $graphics.DrawLines($whiteThinPen, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(13, 25)), (New-Object System.Drawing.PointF(18, 25)),
                    (New-Object System.Drawing.PointF(21, 18)), (New-Object System.Drawing.PointF(25, 30)),
                    (New-Object System.Drawing.PointF(29, 22)), (New-Object System.Drawing.PointF(33, 22))))
            }
            "Report" {
                $backgroundPath = New-DashboardRoundedPath -X 3 -Y 3 -Width 42 -Height 42 -Radius 8
                try { $graphics.FillPath($tealBrush, $backgroundPath) } finally { $backgroundPath.Dispose() }
                $graphics.DrawRectangle($whiteThinPen, 12, 8, 24, 32)
                $graphics.DrawLine($whiteThinPen, 17, 17, 31, 17)
                $graphics.DrawLine($whiteThinPen, 17, 23, 31, 23)
                $graphics.DrawLine($whiteThinPen, 17, 29, 28, 29)
                $graphics.DrawLine($whiteThinPen, 17, 35, 25, 35)
            }
            "NavOverview" {
                $graphics.DrawLines($navPen, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(7, 22)), (New-Object System.Drawing.PointF(24, 7)),
                    (New-Object System.Drawing.PointF(41, 22))))
                $graphics.DrawRectangle($navPen, 12, 21, 24, 20)
                $graphics.DrawRectangle($navPen, 21, 28, 7, 13)
            }
            "NavScan" {
                $graphics.DrawEllipse($navPen, 8, 7, 25, 25)
                $graphics.DrawLine($navPen, 31, 30, 41, 40)
            }
            "NavRepair" {
                $graphics.DrawLine($navPen, 14, 36, 34, 16)
                $graphics.DrawArc($navPen, 28, 8, 12, 12, 25, 245)
                $graphics.DrawEllipse($navPen, 9, 34, 7, 7)
            }
            "NavReport" {
                $graphics.DrawRectangle($navPen, 11, 6, 26, 36)
                $graphics.DrawLine($navPen, 17, 16, 31, 16)
                $graphics.DrawLine($navPen, 17, 23, 31, 23)
                $graphics.DrawLine($navPen, 17, 30, 27, 30)
            }
            "NavSettings" {
                $graphics.DrawEllipse($navPen, 14, 14, 20, 20)
                $graphics.DrawEllipse($navPen, 20, 20, 8, 8)
                foreach ($angle in 0, 45, 90, 135, 180, 225, 270, 315) {
                    $radians = $angle * [Math]::PI / 180
                    $x1 = 24 + ([Math]::Cos($radians) * 11)
                    $y1 = 24 + ([Math]::Sin($radians) * 11)
                    $x2 = 24 + ([Math]::Cos($radians) * 17)
                    $y2 = 24 + ([Math]::Sin($radians) * 17)
                    $graphics.DrawLine($navPen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
                }
            }
            "Chat" {
                $bubble = New-Object System.Drawing.Drawing2D.GraphicsPath
                $bubble.AddArc(5, 7, 38, 31, 180, 90)
                $bubble.AddArc(5, 7, 38, 31, 270, 90)
                $bubble.AddArc(5, 7, 38, 31, 0, 90)
                $bubble.AddLine(31, 38, 22, 44)
                $bubble.AddLine(23, 38, 12, 38)
                $bubble.AddArc(5, 7, 38, 31, 90, 90)
                $bubble.CloseFigure()
                try { $graphics.FillPath($blueBrush, $bubble) } finally { $bubble.Dispose() }
                $graphics.DrawLine($whiteThinPen, 13, 18, 35, 18)
                $graphics.DrawLine($whiteThinPen, 13, 26, 30, 26)
            }
        }
    } catch {
        $bitmap.Dispose()
        throw
    } finally {
        foreach ($resource in @(
            $graphics, $blueBrush, $lightBlueBrush, $officeBrush, $officeDarkBrush, $greenBrush,
            $cyanBrush, $purpleBrush, $amberBrush, $tealBrush, $whiteBrush, $transparentBrush,
            $whitePen, $whiteThinPen, $mintPen, $navPen
        )) {
            if ($resource) { $resource.Dispose() }
        }
    }
    return $bitmap
}

function New-DashboardTileIconBitmap {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [ValidateRange(16, 64)][int]$IconSize = 32,
        [ValidateRange(4, 24)][int]$RightGap = 12
    )

    $source = New-DashboardIconBitmap -Kind $Kind -Size $IconSize
    $canvas = New-Object System.Drawing.Bitmap(($IconSize + $RightGap), $IconSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.DrawImageUnscaled($source, 0, 0)
    } finally {
        $graphics.Dispose()
        $source.Dispose()
    }
    return $canvas
}

function Get-AccountSid([string]$accountName) {
    try {
        return (New-Object Security.Principal.NTAccount($accountName)).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch { return "" }
}

function Test-ProtectedToolDirectoryAcl([string]$path) {
    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
        $ownerSid = Get-AccountSid ([string]$acl.Owner)
        $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $userScopedData = [string]$env:TOOL_DATA_SCOPE -ne "Machine"
        $allowedOwners = @("S-1-5-32-544", "S-1-5-18")
        $allowedWriters = @("S-1-5-32-544", "S-1-5-18")
        if ($userScopedData) {
            $allowedOwners += $currentUserSid
            $allowedWriters += $currentUserSid
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
    } catch { return $false }
}

function Get-DashboardDialogOwner {
    while ($script:dashboardDialogStack.Count -gt 0) {
        $candidate = $script:dashboardDialogStack.Peek()
        if ($candidate -and -not $candidate.IsDisposed -and $candidate.Visible) {
            return $candidate
        }
        [void]$script:dashboardDialogStack.Pop()
    }
    return $form
}

function Show-DashboardModalDialog {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Dialog
    )

    $owner = Get-DashboardDialogOwner
    $script:dashboardDialogStack.Push($Dialog)
    try {
        return $Dialog.ShowDialog($owner)
    } finally {
        if ($script:dashboardDialogStack.Count -gt 0 -and
            [object]::ReferenceEquals($script:dashboardDialogStack.Peek(), $Dialog)) {
            [void]$script:dashboardDialogStack.Pop()
        }
    }
}

function Reset-DashboardWorkflowNavigation {
    $script:dashboardWorkflowCloseRequested = $false
}

function Test-DashboardWorkflowCloseRequested {
    return [bool]$script:dashboardWorkflowCloseRequested
}

function Close-DashboardWorkflowSession {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Dialog
    )

    # A root dialog is the complete workflow by itself.  A nested dialog is
    # one step in a workflow, so Close must dismiss every dialog in the stack
    # and return to the dashboard instead of exposing the parent again.
    if ($script:dashboardDialogStack.Count -le 1) {
        $Dialog.Close()
        return
    }

    $script:dashboardWorkflowCloseRequested = $true
    foreach ($openDialog in @($script:dashboardDialogStack.ToArray())) {
        if ($openDialog -and -not $openDialog.IsDisposed) {
            $openDialog.Close()
        }
    }
}

function Invoke-DashboardRootAction {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Reset-DashboardWorkflowNavigation
    try {
        & $Action
    } catch {
        $message = $_.Exception.Message
        Write-ProgressLog $message
        [System.Windows.Forms.MessageBox]::Show(
            $message,
            (Get-DashboardText 'common.errorTitle'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        Reset-DashboardWorkflowNavigation
    }
}

function Set-DashboardIntroBorderColor {
    param([Parameter(Mandatory = $true)][System.Drawing.Color]$Color)
    if ($introPanel.Tag -and $introPanel.Tag.PSObject.Properties["BorderColor"]) {
        $introPanel.Tag.BorderColor = $Color
    }
    $introPanel.Invalidate()
}

function Sync-DashboardCardAccessibility {
    param(
        [Parameter(Mandatory = $true)][string]$CardKey,
        [AllowEmptyString()][string]$Detail = ""
    )
    if (-not $dashboardCards.ContainsKey($CardKey)) { return }
    $cardRecord = $dashboardCards[$CardKey]
    $captionText = ([string]$cardRecord.Caption.Text).Trim()
    $valueText = ([string]$cardRecord.Value.Text).Trim()
    $summary = ((@($captionText, $valueText) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ": ")
    $descriptionText = if ([string]::IsNullOrWhiteSpace($Detail)) { $summary } else { $Detail }
    $cardRecord.Panel.AccessibleName = $summary
    $cardRecord.Panel.AccessibleDescription = $descriptionText
    $cardRecord.Caption.AccessibleName = $captionText
    $cardRecord.Caption.AccessibleDescription = $captionText
    $cardRecord.Value.AccessibleName = $summary
    $cardRecord.Value.AccessibleDescription = $descriptionText
    $toolTip.SetToolTip($cardRecord.Caption, $descriptionText)
    $toolTip.SetToolTip($cardRecord.Value, $descriptionText)
    $toolTip.SetToolTip($cardRecord.Panel, $descriptionText)
}

function New-ToolReportRunDirectory {
    param([AllowNull()][string]$Category = "BaoCao")

    if (-not (Test-Path -LiteralPath $reportRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
    }
    $script:lastReportDirectory = $reportRoot
    return $reportRoot
}

function Register-ToolReportPath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) { $script:lastReportPath = $fullPath }
        $directory = if (Test-Path -LiteralPath $fullPath -PathType Container) { $fullPath } else { Split-Path -Parent $fullPath }
        if (-not [string]::IsNullOrWhiteSpace($directory) -and (Test-Path -LiteralPath $directory -PathType Container)) {
            $script:lastReportDirectory = $directory
        }
    } catch {}
}

function Open-ToolHtmlReport {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $extension = [IO.Path]::GetExtension([string]$Path).ToLowerInvariant()
    if ($extension -notin @('.html', '.htm')) {
        Write-ProgressLog (Get-DashboardText "report.htmlOnly" @([IO.Path]::GetFileName([string]$Path)))
        return $false
    }
    if ((Get-Command Test-ToolHtmlOfflineSafe -ErrorAction SilentlyContinue) -and -not (Test-ToolHtmlOfflineSafe -HtmlPath $Path)) {
        Write-ProgressLog (Get-DashboardText 'report.viewer.unsafeBlocked' @([IO.Path]::GetFileName([string]$Path)))
        return $false
    }
    Register-ToolReportPath -Path $Path
    Start-Process -FilePath $Path
    return $true
}

function Copy-AllToolLog {
    $text = [string]$progressLog.Text
    if ([string]::IsNullOrWhiteSpace($text) -and $loggingState.Enabled -and (Test-Path -LiteralPath $loggingState.Path -PathType Leaf)) {
        try { $text = [IO.File]::ReadAllText($loggingState.Path, [Text.Encoding]::UTF8) } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "progress.copyNoLog" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "progress.copyAllLog" -Culture $script:dashboardCulture), "OK", "Information") | Out-Null
        return
    }
    try {
        [System.Windows.Forms.Clipboard]::SetText($text)
        $status.Text = Get-ToolText -Key "progress.copySuccess" -Culture $script:dashboardCulture
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "progress.copyFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)),
            (Get-ToolText -Key "progress.copyAllLog" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
    }
}

function Open-ReportDirectory {
    $directory = [string]$script:lastReportDirectory
    if ([string]::IsNullOrWhiteSpace($directory) -or -not (Test-Path -LiteralPath $directory -PathType Container)) {
        $directory = if (Test-Path -LiteralPath $reportRoot -PathType Container) { $reportRoot } else { $desktop }
    }
    try {
        Start-Process -FilePath $nativeExplorerPath -ArgumentList ('"' + $directory + '"')
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "report.openFolderFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)),
            (Get-ToolText -Key "report.openFolder" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
    }
}

function Show-ExecutionEnvironmentWarning {
    if ($script:executionEnvironmentWarningShown) { return }
    $environmentProfile = $capabilityState.ExecutionEnvironment
    if (-not $environmentProfile -or (-not $environmentProfile.VirtualMachineDetected -and -not $environmentProfile.RemoteDesktopDetected)) { return }
    $script:executionEnvironmentWarningShown = $true
    $details = New-Object System.Collections.Generic.List[string]
    if ($environmentProfile.VirtualMachineDetected) {
        [void]$details.Add((Get-ToolText -Key "environment.virtualMachine" -Culture $script:dashboardCulture -FormatArguments @([string]$environmentProfile.VirtualizationProvider)))
    }
    if ($environmentProfile.RemoteDesktopDetected) {
        [void]$details.Add((Get-ToolText -Key "environment.remoteDesktop" -Culture $script:dashboardCulture -FormatArguments @([string]$environmentProfile.SessionName)))
    }
    $message = (Get-ToolText -Key "environment.warning" -Culture $script:dashboardCulture -FormatArguments @(($details -join [Environment]::NewLine)))
    $status.Text = Get-ToolText -Key "environment.status" -Culture $script:dashboardCulture
    $status.ForeColor = [System.Drawing.Color]::DarkOrange
    Write-ProgressLog $message
    [void](Write-ToolLog -Level "WARN" -Event "ExecutionEnvironment.Warning" -Message $message -Data $environmentProfile)
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        (Get-ToolText -Key "environment.warningTitle" -Culture $script:dashboardCulture),
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

function Open-ToolReportPresentation {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$FilePrefix
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return $null
    }
    $sourceFull = [IO.Path]::GetFullPath($SourcePath)
    $cacheKey = $sourceFull.ToLowerInvariant()
    if ($script:reportPresentationCache.ContainsKey($cacheKey)) {
        $cached = $script:reportPresentationCache[$cacheKey]
        if ($cached -and (Test-Path -LiteralPath $cached.HtmlPath -PathType Leaf)) {
            [void](Open-ToolHtmlReport -Path $cached.HtmlPath)
            return $cached
        }
        $script:reportPresentationCache.Remove($cacheKey)
    }

    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss_fff")
    $safePrefix = ([string]$FilePrefix -replace '[^A-Za-z0-9_-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safePrefix)) { $safePrefix = "BaoCao" }
    $presentationDirectory = New-ToolReportRunDirectory -Category "TaiLieu"
    $basePath = Join-Path $presentationDirectory "${safePrefix}_$($env:COMPUTERNAME)_$stamp"
    $extension = [IO.Path]::GetExtension($sourceFull).ToLowerInvariant()
    if ($extension -in @(".html", ".htm")) {
        $desktopFull = [IO.Path]::GetFullPath($presentationDirectory).TrimEnd([char]92)
        $sourceDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $sourceFull)).TrimEnd([char]92)
        if ([string]::Equals($desktopFull, $sourceDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            $htmlPath = $sourceFull
            $pdfPath = [IO.Path]::ChangeExtension($htmlPath, ".pdf")
        } else {
            $htmlPath = "$basePath.html"
            $pdfPath = "$basePath.pdf"
            $htmlContent = [IO.File]::ReadAllText($sourceFull, [Text.Encoding]::UTF8)
            [IO.File]::WriteAllText($htmlPath, $htmlContent, (New-Object Text.UTF8Encoding($false)))
        }
        if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $htmlPath)) {
            throw (Get-DashboardText "report.offlineSafetyFailed")
        }
        $pdfResult = if ((Test-Path -LiteralPath $pdfPath -PathType Leaf) -and (Get-Item -LiteralPath $pdfPath).Length -gt 1024) {
            [pscustomobject][ordered]@{ Success=$true; Engine="Existing"; Path=$pdfPath; Error="" }
        } else {
            Convert-ToolHtmlToPdf -HtmlPath $htmlPath -PdfPath $pdfPath
        }
        $package = [pscustomobject][ordered]@{
            Success = $true
            HtmlPath = $htmlPath
            PdfPath = if ($pdfResult.Success) { $pdfPath } else { "" }
            ManifestPath = ""
            Pdf = $pdfResult
        }
    } else {
        $sourceLines = [IO.File]::ReadAllLines($sourceFull, [Text.Encoding]::UTF8)
        $package = Export-ToolTextReportPresentation `
            -Lines $sourceLines -Title $Title -BasePath $basePath `
            -Subtitle (Get-ToolText -Key "report.description" -Culture $script:dashboardCulture) `
            -Eyebrow (Get-ToolText -Key "report.eyebrow" -Culture $script:dashboardCulture) `
            -Footer "$(Get-ToolText -Key "report.footer" -Culture $script:dashboardCulture) · $releaseDisplayName" `
            -Culture $script:dashboardCulture -IncludePdf
    }
    $script:reportPresentationCache[$cacheKey] = $package
    Register-ToolReportPath -Path $package.HtmlPath
    [void](Open-ToolHtmlReport -Path $package.HtmlPath)
    Write-ProgressLog (Get-DashboardText "report.savedOpened" @([IO.Path]::GetFileName($package.HtmlPath)))
    return $package
}

function Update-MainLayout {
    if ($script:dashboardStartupLayoutPending) { return }
    if ($script:updatingMainLayout) { return }
    $script:updatingMainLayout = $true
    try {
        $form.AutoScroll = $false
        $form.AutoScrollMinSize = New-Object System.Drawing.Size(0, 0)
        $clientWidth = [Math]::Max(1, $form.ClientSize.Width)
        $clientHeight = [Math]::Max(1, $form.ClientSize.Height)
        $sidebarWidth = if ($clientWidth -ge 940) { 196 } else { 0 }
        $outerGap = if ($clientWidth -lt 900) { 12 } else { 18 }
        $left = $sidebarWidth + $outerGap
        $right = $outerGap
        $contentWidth = [Math]::Max(360, $clientWidth - $left - $right)
        $compactHeight = [bool]($form.ClientSize.Height -lt 760)
        $ultraCompactHeight = [bool]($form.ClientSize.Height -lt 640)
        $progressExpanded = [bool]$script:hasTaskActivity

        $sidebarPanel.Visible = [bool]($sidebarWidth -gt 0)
        if ($sidebarPanel.Visible) {
            $sidebarPanel.Left = 0
            $sidebarPanel.Top = 0
            $sidebarPanel.Width = $sidebarWidth
            $sidebarPanel.Height = $clientHeight
            $sidebarBrandIcon.Left = 18
            $sidebarBrandIcon.Top = 20
            $sidebarBrand.Left = 64
            $sidebarBrand.Top = 24
            $sidebarBrand.Width = [Math]::Max(92, $sidebarWidth - $sidebarBrand.Left - 4)
            $sidebarBrand.Height = 38
            Set-DashboardSidebarBrandFont
            for ($navIndex = 0; $navIndex -lt $sidebarNavButtons.Count; $navIndex++) {
                $navButton = $sidebarNavButtons[$navIndex]
                $navButton.Left = 10
                $navButton.Top = 102 + ($navIndex * 54)
                $navButton.Width = $sidebarWidth - 20
                $navButton.Height = 44
                Set-ModernRoundedRegion -Control $navButton -Radius 9
            }
            $sidebarFooter.Left = 20
            $sidebarFooter.Top = [Math]::Max(420, $sidebarPanel.ClientSize.Height - 72)
            $sidebarFooter.Width = $sidebarWidth - 36
        }

        $headerPanel.Left = $sidebarWidth
        $headerPanel.Top = 0
        $headerPanel.Width = $clientWidth - $sidebarWidth
        $headerPanel.Height = if ($ultraCompactHeight) { 70 } else { 86 }

        $compactNavigation.Visible = [bool]($sidebarWidth -eq 0)
        if ($compactNavigation.Visible) {
            $compactNavigation.Left = 24
            $compactNavigation.Top = if ($ultraCompactHeight) { 39 } else { 48 }
            $compactNavigation.Width = [Math]::Min(220, [Math]::Max(160, $headerPanel.ClientSize.Width - 48))
        }

        $showHeaderBrand = [bool]($headerPanel.ClientSize.Width -ge 1000)
        $headerBrandIcon.Visible = $showHeaderBrand
        $headerBrandIcon.Left = 20
        $headerBrandIcon.Top = [Math]::Max(8, [Math]::Floor(($headerPanel.ClientSize.Height - $headerBrandIcon.Height) / 2))
        $headerTextLeft = if ($showHeaderBrand) { 74 } else { 24 }
        $title.Left = $headerTextLeft
        $title.Top = 7

        $compactHeaderToolbar = -not $showHeaderBrand
        $buttonSafety = if ($compactHeaderToolbar) { 10 } else { 14 }
        $themeButton.Width = [Math]::Max(
            $(if ($compactHeaderToolbar) { 136 } else { 152 }),
            (Get-ToolUiButtonRequiredWidth -Button $themeButton -HorizontalSafety $buttonSafety))
        $offlineButton.Width = [Math]::Max(
            $(if ($compactHeaderToolbar) { 112 } else { 156 }),
            (Get-ToolUiButtonRequiredWidth -Button $offlineButton -HorizontalSafety $buttonSafety))
        $languageCombo.Width = [Math]::Max(
            $(if ($compactHeaderToolbar) { 104 } else { 116 }),
            (Get-DashboardComboRequiredWidth -ComboBox $languageCombo -HorizontalSafety $(if ($compactHeaderToolbar) { 14 } else { 18 })))

        $commandGap = if ($compactHeaderToolbar) { 6 } else { 8 }
        $toolbarRight = if ($compactHeaderToolbar) { 14 } else { 22 }
        $titleCommandGap = if ($compactHeaderToolbar) { 8 } else { 12 }
        $themeButton.Top = 8
        $themeButton.Left = $headerPanel.ClientSize.Width - $themeButton.Width - $toolbarRight
        $languageCombo.Top = 10
        $languageCombo.Left = $themeButton.Left - $commandGap - $languageCombo.Width
        $offlineButton.Top = 8
        $offlineButton.Left = $languageCombo.Left - $commandGap - $offlineButton.Width
        $title.Width = [Math]::Max(260, $offlineButton.Left - $title.Left - $titleCommandGap)
        Set-DashboardHeaderTitleFont -PreferLarge:$showHeaderBrand
        $title.Height = [Math]::Max(34, $title.PreferredHeight + 4)

        $developer.Left = $headerTextLeft
        $developer.Top = 40
        $developer.Height = [Math]::Max(20, $developer.PreferredHeight)
        $developer.Width = [Math]::Max(220, $headerPanel.ClientSize.Width - $developer.Left - 24)
        $developer.Visible = [bool]($sidebarWidth -gt 0)
        $version.Left = $headerTextLeft
        $version.Top = 61
        $version.Height = [Math]::Max(18, $version.PreferredHeight)
        $version.Width = [Math]::Max(220, $headerPanel.ClientSize.Width - $version.Left - 24)
        $version.Visible = [bool]($sidebarWidth -gt 0 -and -not $ultraCompactHeight)

        $introPanel.Left = $left
        $introPanel.Top = $headerPanel.Bottom + $(if ($ultraCompactHeight) { 8 } else { 14 })
        $introPanel.Width = $contentWidth
        $introButtonTextHeight = [Math]::Max($introAssistantButton.Font.Height, $introDetailButton.Font.Height)
        $introButtonImageHeight = if ($introAssistantButton.Image) { [int]$introAssistantButton.Image.Height } else { 0 }
        $introActionHeight = [Math]::Max(30, [Math]::Max(($introButtonTextHeight + 12), ($introButtonImageHeight + 10)))
        $introPanelBaseHeight = if ($ultraCompactHeight) { 44 } elseif ($compactHeight) { 50 } else { 58 }
        $introPanel.Height = [Math]::Max($introPanelBaseHeight, ($introActionHeight + 8))
        $introDetailButton.Width = [Math]::Max(
            $(if ($ultraCompactHeight) { 142 } else { 154 }),
            (Get-ToolUiButtonRequiredWidth -Button $introDetailButton -HorizontalSafety 20))
        $introDetailButton.Height = $introActionHeight
        $introDetailButton.Left = $introPanel.ClientSize.Width - $introDetailButton.Width - 10
        $introDetailButton.Top = [Math]::Max(4, [Math]::Floor(($introPanel.ClientSize.Height - $introDetailButton.Height) / 2))
        $introAssistantButton.Width = [Math]::Max(
            $(if ($ultraCompactHeight) { 176 } else { 188 }),
            (Get-ToolUiButtonRequiredWidth -Button $introAssistantButton -HorizontalSafety 26))
        $introAssistantButton.Height = $introActionHeight
        $introAssistantButton.Left = $introDetailButton.Left - $introAssistantButton.Width - 8
        $introAssistantButton.Top = $introDetailButton.Top
        $description.Left = 15
        $description.Top = if ($ultraCompactHeight) { 9 } else { 5 }
        $description.Width = [Math]::Max(180, $introAssistantButton.Left - $description.Left - 10)
        $description.Height = 22
        $description.Visible = $true
        $introSummary.Left = 15
        $introSummary.Top = 29
        $introSummary.Width = $description.Width
        $introSummary.Height = 19
        $introSummary.Visible = -not $ultraCompactHeight

        $dashboardPanel.Left = $left
        $dashboardPanel.Top = $introPanel.Bottom + 8
        $dashboardPanel.Width = $contentWidth
        $dashboardPanel.Height = if ($ultraCompactHeight) { 66 } elseif ($compactHeight) { 72 } else { 88 }
        $cardGap = 10
        $cardCount = [Math]::Max(1, $dashboardCardPanels.Count)
        $cardWidth = [Math]::Max(108, [Math]::Floor(($dashboardPanel.ClientSize.Width - ($cardGap * ($cardCount - 1))) / $cardCount))
        for ($cardIndex = 0; $cardIndex -lt $dashboardCardPanels.Count; $cardIndex++) {
            $card = $dashboardCardPanels[$cardIndex]
            $card.Left = $cardIndex * ($cardWidth + $cardGap)
            $card.Top = 3
            $card.Width = $cardWidth
            $card.Height = if ($ultraCompactHeight) { 60 } elseif ($compactHeight) { 66 } else { 82 }
            if ($card.Controls.Count -ge 2) {
                $card.Controls[0].Top = if ($ultraCompactHeight) { 4 } elseif ($compactHeight) { 5 } else { 8 }
                $card.Controls[0].Left = 58
                $card.Controls[0].Width = [Math]::Max(40, $cardWidth - 68)
                $card.Controls[1].Top = if ($ultraCompactHeight) { 23 } elseif ($compactHeight) { 25 } else { 30 }
                $card.Controls[1].Left = 58
                $card.Controls[1].Width = [Math]::Max(40, $cardWidth - 68)
                $card.Controls[1].Height = if ($ultraCompactHeight) { 32 } elseif ($compactHeight) { 35 } else { 42 }
            }
            foreach ($child in $card.Controls) {
                if ([string]$child.Tag -eq "CardGlyph") {
                    $iconSize = if ($ultraCompactHeight) { 30 } elseif ($compactHeight) { 32 } else { 34 }
                    $child.Left = 11
                    $child.Top = [Math]::Max(7, [Math]::Floor(($card.ClientSize.Height - $iconSize) / 2))
                    $child.Width = $iconSize
                    $child.Height = $iconSize
                }
            }
            Set-ModernRoundedRegion -Control $card -Radius 13
        }

        $mainTop = $dashboardPanel.Bottom + 10
        $mainBottom = $clientHeight - $(if ($ultraCompactHeight) { 8 } else { 16 })
        $mainHeight = [Math]::Max(250, $mainBottom - $mainTop)
        $paneGap = if ($clientWidth -lt 900) { 8 } else { 12 }
        $activityWidth = if ($contentWidth -ge 980) { 302 } elseif ($contentWidth -ge 780) { 272 } else { 220 }

        $buttonPanel.Left = $left
        $buttonPanel.Top = $mainTop
        $buttonPanel.Width = [Math]::Max(470, $contentWidth - $activityWidth - $paneGap)
        $buttonPanel.Height = $mainHeight
        $activityPanel.Left = $buttonPanel.Right + $paneGap
        $activityPanel.Top = $mainTop
        $activityPanel.Width = [Math]::Max(200, $left + $contentWidth - $activityPanel.Left)
        $activityPanel.Height = $mainHeight
        $menuCaption.Width = [Math]::Max(300, $buttonPanel.ClientSize.Width - 28)
        $menuCaption.Left = 16
        $menuCaption.Top = 12
        $menuCaption.Height = 24

        $tileGap = 10
        $rowGap = if ($ultraCompactHeight) { 3 } elseif ($compactHeight) { 5 } else { 8 }
        $tileMargin = 13
        $scrollbarReserve = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth + 2
        $tileLayoutWidth = [Math]::Max(470, $buttonPanel.ClientSize.Width - $scrollbarReserve)
        $tileWidth = [Math]::Max(220, [Math]::Floor(($tileLayoutWidth - ($tileMargin * 2) - $tileGap) / 2))
        $buttonPanelBottomPadding = if ($ultraCompactHeight) { 5 } else { 10 }
        $visibleButtons = @($buttons | Where-Object { $_.Visible })
        $visibleRowCount = [Math]::Max(1, [Math]::Ceiling($visibleButtons.Count / 2.0))
        $availableButtonHeight = $buttonPanel.ClientSize.Height - 42 - (($visibleRowCount - 1) * $rowGap) - $buttonPanelBottomPadding
        $calculatedTileHeight = [Math]::Floor($availableButtonHeight / $visibleRowCount)
        $minimumTileHeight = if ($ultraCompactHeight) { 64 } elseif ($compactHeight) { 68 } else { 72 }
        $requiredTileHeight = $minimumTileHeight
        foreach ($candidateButton in $visibleButtons) {
            if (-not $candidateButton.Tag -or [string]$candidateButton.Tag.Kind -notin @('QuickAction', 'ReportAction')) { continue }
            $candidateTextLeft = if ($tileWidth -lt 280) { 54 } else { 60 }
            $candidateTextWidth = [Math]::Max(80, $tileWidth - $candidateTextLeft - 10)
            $candidateTitleHeight = Get-DashboardWrappedTextHeight -Text ([string]$candidateButton.Tag.TitleLabel.Text) -Font $candidateButton.Tag.TitleLabel.Font -Width $candidateTextWidth -MinimumHeight 18 -MaximumHeight 38
            $candidateDescriptionHeight = Get-DashboardWrappedTextHeight -Text ([string]$candidateButton.Tag.DescriptionLabel.Text) -Font $candidateButton.Tag.DescriptionLabel.Font -Width $candidateTextWidth -MinimumHeight 17 -MaximumHeight 44
            $requiredTileHeight = [Math]::Max($requiredTileHeight, ($candidateTitleHeight + $candidateDescriptionHeight + 12))
        }
        $requiredTileHeight = [Math]::Min(98, $requiredTileHeight)
        $tileHeight = if ($calculatedTileHeight -ge $requiredTileHeight) {
            [Math]::Min(98, $calculatedTileHeight)
        } else {
            $requiredTileHeight
        }
        $requiredButtonPanelHeight = 42 + ($visibleRowCount * $tileHeight) + (($visibleRowCount - 1) * $rowGap) + $buttonPanelBottomPadding
        $buttonPanel.AutoScrollMinSize = New-Object System.Drawing.Size(0, $requiredButtonPanelHeight)
        for ($buttonIndex = 0; $buttonIndex -lt $visibleButtons.Count; $buttonIndex++) {
            $button = $visibleButtons[$buttonIndex]
            $row = [Math]::Floor($buttonIndex / 2)
            $column = $buttonIndex % 2
            $button.Left = $tileMargin + ($column * ($tileWidth + $tileGap))
            $button.Top = 42 + ($row * ($tileHeight + $rowGap))
            $button.Width = $tileWidth
            $button.Height = $tileHeight
            if ($button.Tag -and [string]$button.Tag.Kind -in @("QuickAction", "ReportAction")) {
                $textLeft = if ($tileWidth -lt 280) { 54 } else { 60 }
                $textWidth = [Math]::Max(80, $tileWidth - $textLeft - 10)
                $requiredTitleHeight = Get-DashboardWrappedTextHeight -Text ([string]$button.Tag.TitleLabel.Text) -Font $button.Tag.TitleLabel.Font -Width $textWidth -MinimumHeight 18 -MaximumHeight 38
                $titleHeight = [Math]::Min($requiredTitleHeight, [Math]::Max(18, $tileHeight - 31))
                $requiredDescriptionHeight = Get-DashboardWrappedTextHeight -Text ([string]$button.Tag.DescriptionLabel.Text) -Font $button.Tag.DescriptionLabel.Font -Width $textWidth -MinimumHeight 17 -MaximumHeight 44
                $descriptionHeight = [Math]::Min($requiredDescriptionHeight, [Math]::Max(17, $tileHeight - $titleHeight - 8))
                $contentHeight = $titleHeight + $descriptionHeight + 2
                $contentTop = [Math]::Max(3, [Math]::Floor(($tileHeight - $contentHeight) / 2))
                $button.Tag.TitleLabel.Left = $textLeft
                $button.Tag.TitleLabel.Top = $contentTop
                $button.Tag.TitleLabel.Width = $textWidth
                $button.Tag.TitleLabel.Height = $titleHeight
                $button.Tag.TitleLabel.AutoEllipsis = [bool]($requiredTitleHeight -gt $titleHeight)
                $button.Tag.DescriptionLabel.Left = $textLeft
                $button.Tag.DescriptionLabel.Top = $contentTop + $titleHeight + 2
                $button.Tag.DescriptionLabel.Width = $textWidth
                $button.Tag.DescriptionLabel.Height = $descriptionHeight
                $button.Tag.DescriptionLabel.AutoEllipsis = [bool]($requiredDescriptionHeight -gt $descriptionHeight)
            }
            if ($script:dashboardSection -eq "Reports" -and
                $visibleButtons.Count % 2 -eq 1 -and $buttonIndex -eq ($visibleButtons.Count - 1)) {
                $button.Left = [Math]::Floor(($buttonPanel.ClientSize.Width - $tileWidth) / 2)
            }
            Set-ModernRoundedRegion -Control $button -Radius 10
        }

        $activityPanelCaption.Left = 16
        $activityPanelCaption.Top = 14
        $activityPanelCaption.Width = $activityPanel.ClientSize.Width - 32
        $status.Left = 16
        $status.Top = 48
        $status.Width = $activityPanel.ClientSize.Width - 32
        $status.Height = 42
        $progressCaption.Left = 16
        $progressCaption.Top = 96
        $progressCaption.Width = $activityPanel.ClientSize.Width - 32
        $progressCaption.Height = 22
        $progressCaption.Visible = $progressExpanded

        $closeButton.Height = 30
        $closeButton.Width = 108
        $closeButton.Left = $activityPanel.ClientSize.Width - $closeButton.Width - 16
        $closeButton.Top = $activityPanel.ClientSize.Height - $closeButton.Height - 12
        $stopButton.Height = $closeButton.Height
        $stopButton.Width = 108
        $stopButton.Left = $closeButton.Left - $stopButton.Width - 8
        $stopButton.Top = $closeButton.Top

        $copyLogButton.Left = 16
        $copyLogButton.Width = $activityPanel.ClientSize.Width - 32
        $copyLogButton.Height = 32
        $copyLogButton.Top = $closeButton.Top - $copyLogButton.Height - 8
        $openReportFolderButton.Left = 16
        $openReportFolderButton.Width = $activityPanel.ClientSize.Width - 32
        $openReportFolderButton.Height = 32
        $openReportFolderButton.Top = $copyLogButton.Top - $openReportFolderButton.Height - 8

        if ($progressExpanded) {
            $activityLabel.Visible = $true
            $elapsedLabel.Visible = $true
            $progressBar.Visible = $true
            $progressLog.Visible = $true
            $activityLabel.Left = 16
            $activityLabel.Top = $progressCaption.Bottom + 2
            $activityLabel.Height = 20
            $activityLabel.Width = [Math]::Max(80, $activityPanel.ClientSize.Width - $elapsedLabel.Width - 40)
            $elapsedLabel.Left = $activityPanel.ClientSize.Width - $elapsedLabel.Width - 16
            $elapsedLabel.Top = $activityLabel.Top
            $progressBar.Left = 16
            $progressBar.Top = $activityLabel.Bottom + 1
            $progressBar.Height = 14
            $progressBar.Width = $activityPanel.ClientSize.Width - 32
            $progressLog.Left = 16
            $progressLog.Top = $progressBar.Bottom + 4
            $progressLog.Width = $activityPanel.ClientSize.Width - 32
            $availableLogHeight = $openReportFolderButton.Top - $progressLog.Top - 8
            $progressLog.Height = [Math]::Max(30, $availableLogHeight)
        } else {
            $activityLabel.Visible = $false
            $elapsedLabel.Visible = $false
            $progressBar.Visible = $false
            $progressLog.Visible = $false
        }
        Set-ModernRoundedRegion -Control $introPanel -Radius 14
        Set-ModernRoundedRegion -Control $buttonPanel -Radius 14
        Set-ModernRoundedRegion -Control $activityPanel -Radius 14
        Set-ModernRoundedRegion -Control $themeButton -Radius 9
        Set-ModernRoundedRegion -Control $offlineButton -Radius 9
        Set-ModernRoundedRegion -Control $introAssistantButton -Radius 9
        Set-ModernRoundedRegion -Control $introDetailButton -Radius 9
        Set-ModernRoundedRegion -Control $stopButton -Radius 9
        Set-ModernRoundedRegion -Control $closeButton -Radius 9
        Set-ModernRoundedRegion -Control $copyLogButton -Radius 8
        Set-ModernRoundedRegion -Control $openReportFolderButton -Radius 8
    } finally {
        $script:updatingMainLayout = $false
    }
}

function Fit-MainWindowToWorkingArea {
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $availableWidth = [Math]::Max(640, $workArea.Width - 16)
    $availableHeight = [Math]::Max(520, $workArea.Height - 12)
    # Bounds and manually positioned child controls are expressed in physical
    # pixels.  Fonts still grow with per-monitor DPI, so retaining a fixed
    # 1480x900 outer window at 150-200% starves the responsive layout and clips
    # otherwise valid labels.  Scale the desired canvas with the window DPI,
    # then cap it to the current monitor's working area.
    $dpiScale = 1.0
    $dpiProbe = $null
    try {
        if ($form.IsHandleCreated) {
            $dpiProbe = $form.CreateGraphics()
            $dpiScale = [Math]::Max(1.0, ([double]$dpiProbe.DpiX / 96.0))
        } elseif ($form.DeviceDpi) {
            $dpiScale = [Math]::Max(1.0, ([double]$form.DeviceDpi / 96.0))
        }
    } catch {
        try { $dpiScale = [Math]::Max(1.0, ([double]$form.DeviceDpi / 96.0)) } catch { $dpiScale = 1.0 }
    } finally {
        if ($dpiProbe) { $dpiProbe.Dispose() }
    }
    $desiredWidth = [int][Math]::Round(1480 * $dpiScale)
    $desiredHeight = [int][Math]::Round(900 * $dpiScale)
    $targetWidth = [Math]::Min($desiredWidth, $availableWidth)
    $targetHeight = [Math]::Min($desiredHeight, $availableHeight)
    $minimumWidth = [int][Math]::Round(860 * $dpiScale)
    $minimumHeight = [int][Math]::Round(560 * $dpiScale)
    $form.MinimumSize = New-Object System.Drawing.Size([Math]::Min($minimumWidth, $targetWidth), [Math]::Min($minimumHeight, $targetHeight))
    $targetX = $workArea.Left + [Math]::Max(0, [Math]::Floor(($workArea.Width - $targetWidth) / 2))
    $targetY = $workArea.Top + [Math]::Max(0, [Math]::Floor(($workArea.Height - $targetHeight) / 2))
    $form.StartPosition = "Manual"
    $form.Bounds = New-Object System.Drawing.Rectangle($targetX, $targetY, $targetWidth, $targetHeight)
}

function Show-ProductIntroduction {
    $dark = [bool]($script:dashboardTheme -eq "Dark")
    $surface = if ($dark) { [System.Drawing.Color]::FromArgb(31, 36, 48) } else { [System.Drawing.Color]::White }
    $background = if ($dark) { [System.Drawing.Color]::FromArgb(20, 24, 33) } else { [System.Drawing.Color]::FromArgb(244, 246, 249) }
    $primary = if ($dark) { [System.Drawing.Color]::FromArgb(126, 174, 255) } else { [System.Drawing.Color]::FromArgb(18, 59, 116) }
    $text = if ($dark) { [System.Drawing.Color]::FromArgb(226, 231, 239) } else { [System.Drawing.Color]::FromArgb(52, 64, 84) }
    $muted = if ($dark) { [System.Drawing.Color]::FromArgb(164, 174, 192) } else { [System.Drawing.Color]::FromArgb(102, 112, 133) }
    $introSurface = if ($dark) { [System.Drawing.Color]::FromArgb(30, 44, 65) } else { [System.Drawing.Color]::FromArgb(235, 244, 255) }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-ToolText -Key "about.form.title" -Culture $script:dashboardCulture -FormatArguments @($releaseDisplayName)
    $dialog.StartPosition = "CenterParent"
    $dialog.ShowInTaskbar = $false
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $false
    $dialog.BackColor = $background
    $dialog.Font = $fontNormal
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(620, [Math]::Min(840, $workArea.Width - 40))
    $dialogHeight = [Math]::Max(480, [Math]::Min(620, $workArea.Height - 40))
    $dialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(620, $dialogWidth), [Math]::Min(480, $dialogHeight))
    $dialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(14)
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 112)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52)))
    $dialog.Controls.Add($layout)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Fill"
    $header.BackColor = $introSurface
    $header.BorderStyle = "FixedSingle"
    $layout.Controls.Add($header, 0, 0)

    $headerAccent = New-Object System.Windows.Forms.Panel
    $headerAccent.Dock = "Left"
    $headerAccent.Width = 6
    $headerAccent.BackColor = $primary
    $header.Controls.Add($headerAccent)

    $productHeadingFont = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ToolText -Key "about.heading" -Culture $script:dashboardCulture
    $heading.Font = $productHeadingFont
    $heading.ForeColor = $primary
    $heading.Location = New-Object System.Drawing.Point(20, 8)
    $heading.Size = New-Object System.Drawing.Size(730, 56)
    $heading.Anchor = "Top, Left, Right"
    $heading.UseMnemonic = $false
    $heading.UseCompatibleTextRendering = $false
    $heading.AutoEllipsis = $false
    $heading.TextAlign = "TopLeft"
    $header.Controls.Add($heading)

    $tagline = New-Object System.Windows.Forms.Label
    $tagline.Text = Get-ToolText -Key "about.byline" -Culture $script:dashboardCulture -FormatArguments @($releaseDisplayName, $releaseBuildDate)
    $tagline.Font = $fontBold
    $tagline.ForeColor = $text
    $tagline.Location = New-Object System.Drawing.Point(20, 72)
    $tagline.Size = New-Object System.Drawing.Size(730, 30)
    $tagline.Anchor = "Top, Left, Right"
    $tagline.UseMnemonic = $false
    $tagline.UseCompatibleTextRendering = $false
    $header.Controls.Add($tagline)

    $aboutHeaderLayout = {
        param($sender, $eventArgs)
        $dpiScale = try { [Math]::Max(1.0, ([double]$sender.DeviceDpi / 96.0)) } catch { 1.0 }
        $sideMargin = [int][Math]::Round(20 * $dpiScale)
        $topMargin = [int][Math]::Round(8 * $dpiScale)
        $contentGap = [int][Math]::Round(3 * $dpiScale)
        $bottomMargin = [int][Math]::Round(5 * $dpiScale)
        $contentWidth = [Math]::Max([int][Math]::Round(220 * $dpiScale), [int]$sender.ClientSize.Width - (2 * $sideMargin))
        $heading.Left = $sideMargin
        $heading.Top = $topMargin
        $heading.Width = $contentWidth
        $heading.Height = Get-DashboardWrappedTextHeight -Text ([string]$heading.Text) -Font $heading.Font -Width $contentWidth -MinimumHeight ([int][Math]::Round(34 * $dpiScale)) -MaximumHeight ([int][Math]::Round(58 * $dpiScale))
        $tagline.Left = $sideMargin
        $tagline.Top = [int]$heading.Bottom + $contentGap
        $tagline.Width = $contentWidth
        $tagline.Height = [Math]::Max([int][Math]::Round(24 * $dpiScale), [int]$sender.ClientSize.Height - $tagline.Top - $bottomMargin)
    }.GetNewClosure()
    $header.Add_SizeChanged($aboutHeaderLayout)

    $detailTabs = New-Object System.Windows.Forms.TabControl
    $detailTabs.Dock = "Fill"
    $detailTabs.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 4)
    $detailTabs.Font = $fontBold
    $layout.Controls.Add($detailTabs, 0, 1)

    $aboutPage = New-Object System.Windows.Forms.TabPage
    $aboutPage.Text = Get-ToolText -Key "about.productTab" -Culture $script:dashboardCulture
    $aboutPage.BackColor = $surface
    $aboutPage.Padding = New-Object System.Windows.Forms.Padding(10)
    [void]$detailTabs.TabPages.Add($aboutPage)

    $overviewPage = New-Object System.Windows.Forms.TabPage
    $overviewPage.Text = Get-ToolText -Key "about.capabilitiesTab" -Culture $script:dashboardCulture
    $overviewPage.BackColor = $background
    $overviewPage.Padding = New-Object System.Windows.Forms.Padding(4)
    [void]$detailTabs.TabPages.Add($overviewPage)

    $officialReleaseUrl = "https://thanhvietithopnghia-rgb.github.io/VietLicenSure/"
    $officialIssuesUrl = "https://github.com/thanhvietithopnghia-rgb/VietLicenSure/issues/new/choose"
    $officialDiscussionsUrl = "https://github.com/thanhvietithopnghia-rgb/VietLicenSure/discussions"
    $officialSecurityUrl = "https://github.com/thanhvietithopnghia-rgb/VietLicenSure/security/advisories/new"
    $approvedAboutUrls = @(
        $officialReleaseUrl,
        $officialIssuesUrl,
        $officialDiscussionsUrl,
        $officialSecurityUrl
    )
    $communitySupportBody = @(
        (Get-ToolText -Key "about.support.body" -Culture $script:dashboardCulture),
        "GitHub Issues: $officialIssuesUrl",
        "GitHub Discussions: $officialDiscussionsUrl",
        "Security advisory: $officialSecurityUrl"
    ) -join "`r`n"
    $aboutBox = New-Object System.Windows.Forms.RichTextBox
    $aboutBox.Dock = "Fill"
    $aboutBox.ReadOnly = $true
    $aboutBox.DetectUrls = $true
    $aboutBox.WordWrap = $true
    $aboutBox.ScrollBars = "Vertical"
    $aboutBox.BorderStyle = "None"
    $aboutBox.BackColor = $surface
    $aboutBox.ForeColor = $text
    $aboutBox.Font = $fontNormal
    $aboutBox.Tag = $approvedAboutUrls
    $aboutPage.Controls.Add($aboutBox)

    $aboutSections = @(
        @{
            Title = Get-ToolText -Key "about.product.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.product.body" -Culture $script:dashboardCulture -FormatArguments @($releaseDisplayName, $releaseBuildDate)
        },
        @{
            Title = Get-ToolText -Key "about.author.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.author.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.purpose.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.purpose.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.model.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.model.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.technology.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.technology.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.support.title" -Culture $script:dashboardCulture
            Body = $communitySupportBody
        },
        @{
            Title = Get-ToolText -Key "about.release.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.release.body" -Culture $script:dashboardCulture -FormatArguments @($officialReleaseUrl)
        },
        @{
            Title = Get-ToolText -Key "about.smartscreen.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.smartscreen.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.terms.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.terms.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.safety.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.safety.body" -Culture $script:dashboardCulture
        }
    )
    foreach ($aboutSection in $aboutSections) {
        $aboutBox.SelectionStart = $aboutBox.TextLength
        $aboutBox.SelectionLength = 0
        $aboutBox.SelectionFont = $fontBold
        $aboutBox.SelectionColor = $primary
        $aboutBox.AppendText(([string]$aboutSection.Title) + "`r`n")
        $aboutBox.SelectionStart = $aboutBox.TextLength
        $aboutBox.SelectionLength = 0
        $aboutBox.SelectionFont = $fontNormal
        $aboutBox.SelectionColor = $text
        $aboutBox.AppendText(([string]$aboutSection.Body) + "`r`n`r`n")
    }
    $aboutBox.SelectionStart = 0
    $aboutBox.SelectionLength = 0
    $aboutBox.Add_LinkClicked({
        param($sender, $eventArgs)
        $requestedUrl = [string]$eventArgs.LinkText
        $approvedUrl = @($sender.Tag) | Where-Object {
            [string]::Equals([string]$_, $requestedUrl, [StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace([string]$approvedUrl)) {
            if ($script:offlineMode) {
                [System.Windows.Forms.MessageBox]::Show(
                    (Get-ToolText -Key "app.offline.blocked" -Culture $script:dashboardCulture),
                    (Get-ToolText -Key "app.offline.blockedTitle" -Culture $script:dashboardCulture),
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                return
            }
            try {
                [void][Diagnostics.Process]::Start([string]$approvedUrl)
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    (Get-ToolText -Key "about.openReleaseFailed" -Culture $script:dashboardCulture -FormatArguments @($approvedUrl)),
                    (Get-ToolText -Key "about.openReleaseFailedTitle" -Culture $script:dashboardCulture),
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
        }
    })

    $featureGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $featureGrid.Dock = "Fill"
    $featureGrid.Margin = New-Object System.Windows.Forms.Padding(0)
    $featureGrid.ColumnCount = 2
    $featureGrid.RowCount = 3
    [void]$featureGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$featureGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$featureGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 45)))
    [void]$featureGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 45)))
    [void]$featureGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 10)))
    $overviewPage.Controls.Add($featureGrid)

    $featureDefinitions = @(
        @{ Title=(Get-ToolText -Key "about.card.config.title" -Culture $script:dashboardCulture); Body=(Get-ToolText -Key "about.card.config.body" -Culture $script:dashboardCulture); Light=[Drawing.Color]::FromArgb(238,246,255); Dark=[Drawing.Color]::FromArgb(28,43,63); Accent=[Drawing.Color]::FromArgb(37,99,235) },
        @{ Title=(Get-ToolText -Key "about.card.remediation.title" -Culture $script:dashboardCulture); Body=(Get-ToolText -Key "about.card.remediation.body" -Culture $script:dashboardCulture); Light=[Drawing.Color]::FromArgb(255,248,232); Dark=[Drawing.Color]::FromArgb(58,43,25); Accent=[Drawing.Color]::FromArgb(217,119,6) },
        @{ Title=(Get-ToolText -Key "about.card.report.title" -Culture $script:dashboardCulture); Body=(Get-ToolText -Key "about.card.report.body" -Culture $script:dashboardCulture); Light=[Drawing.Color]::FromArgb(237,250,244); Dark=[Drawing.Color]::FromArgb(25,51,43); Accent=[Drawing.Color]::FromArgb(5,150,105) },
        @{ Title=(Get-ToolText -Key "about.card.assurance.title" -Culture $script:dashboardCulture); Body=(Get-ToolText -Key "about.card.assurance.body" -Culture $script:dashboardCulture); Light=[Drawing.Color]::FromArgb(247,241,255); Dark=[Drawing.Color]::FromArgb(48,37,64); Accent=[Drawing.Color]::FromArgb(124,58,237) }
    )
    for ($featureIndex = 0; $featureIndex -lt $featureDefinitions.Count; $featureIndex++) {
        $feature = $featureDefinitions[$featureIndex]
        $card = New-Object System.Windows.Forms.Panel
        $card.Dock = "Fill"
        $card.Margin = New-Object System.Windows.Forms.Padding(5)
        $featureSurface = if ($dark) { $feature.Dark } else { $feature.Light }
        $card.BackColor = $featureSurface
        $card.BorderStyle = "FixedSingle"

        $cardLayout = New-Object System.Windows.Forms.TableLayoutPanel
        $cardLayout.Dock = "Fill"
        $cardLayout.BackColor = $featureSurface
        $cardLayout.Padding = New-Object System.Windows.Forms.Padding(17, 9, 12, 8)
        $cardLayout.ColumnCount = 1
        $cardLayout.RowCount = 2
        [void]$cardLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$cardLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 26)))
        [void]$cardLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $card.Controls.Add($cardLayout)

        $cardTitle = New-Object System.Windows.Forms.Label
        $cardTitle.Text = [string]$feature.Title
        $cardTitle.Font = $fontBold
        $cardTitle.ForeColor = $primary
        $cardTitle.UseMnemonic = $false
        $cardTitle.Dock = "Fill"
        $cardTitle.TextAlign = "MiddleLeft"
        $cardLayout.Controls.Add($cardTitle, 0, 0)

        $cardBody = New-Object System.Windows.Forms.Label
        $cardBody.Text = [string]$feature.Body
        $cardBody.Font = $fontNormal
        $cardBody.ForeColor = $text
        $cardBody.Dock = "Fill"
        $cardBody.TextAlign = "TopLeft"
        $cardBody.UseCompatibleTextRendering = $false
        $cardLayout.Controls.Add($cardBody, 0, 1)

        $featureAccent = New-Object System.Windows.Forms.Panel
        $featureAccent.Dock = "Left"
        $featureAccent.Width = 5
        $featureAccent.BackColor = $feature.Accent
        $card.Controls.Add($featureAccent)
        $featureAccent.BringToFront()

        $featureGrid.Controls.Add($card, ($featureIndex % 2), [Math]::Floor($featureIndex / 2))
    }

    $note = New-Object System.Windows.Forms.Label
    $note.Text = Get-ToolText -Key "about.note" -Culture $script:dashboardCulture
    $note.Font = $fontSmall
    $note.ForeColor = $muted
    $note.Dock = "Fill"
    $note.TextAlign = "MiddleLeft"
    $note.AutoEllipsis = $true
    $note.Margin = New-Object System.Windows.Forms.Padding(6, 1, 6, 1)
    $featureGrid.Controls.Add($note, 0, 2)
    $featureGrid.SetColumnSpan($note, 2)

    $buttonBar = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonBar.Dock = "Fill"
    $buttonBar.FlowDirection = "RightToLeft"
    $buttonBar.WrapContents = $false
    $buttonBar.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $layout.Controls.Add($buttonBar, 0, 2)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-ToolText -Key "common.close" -Culture $script:dashboardCulture
    $close.Font = $fontBold
    $close.Size = New-Object System.Drawing.Size(94, 30)
    $close.BackColor = $primary
    $close.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    $close.FlatStyle = "Flat"
    $close.FlatAppearance.BorderSize = 0
    $close.AccessibleName = $close.Text
    $close.AccessibleDescription = $close.Text
    $close.TabIndex = 3
    $toolTip.SetToolTip($close, $close.AccessibleDescription)
    $close.Add_Click({ Close-DashboardWorkflowSession -Dialog $dialog })
    $buttonBar.Controls.Add($close)

    $guide = New-Object System.Windows.Forms.Button
    $guide.Text = Get-ToolText -Key "about.openGuide" -Culture $script:dashboardCulture
    $guide.Font = $fontBold
    $guide.Size = New-Object System.Drawing.Size(128, 30)
    $guide.BackColor = $surface
    $guide.ForeColor = $text
    $guide.FlatStyle = "Flat"
    $guide.AccessibleName = $guide.Text
    $guide.AccessibleDescription = Get-ToolText -Key "about.openGuideDescription" -Culture $script:dashboardCulture
    $guide.TabIndex = 2
    $toolTip.SetToolTip($guide, $guide.AccessibleDescription)
    $guide.Add_Click({ Open-Guide })
    $buttonBar.Controls.Add($guide)

    $faq = New-Object System.Windows.Forms.Button
    $faq.Text = Get-ToolText -Key "about.openFaq" -Culture $script:dashboardCulture
    $faq.Font = $fontBold
    $faq.Size = New-Object System.Drawing.Size(144, 30)
    $faq.BackColor = $surface
    $faq.ForeColor = $text
    $faq.FlatStyle = "Flat"
    $faq.AccessibleName = $faq.Text
    $faq.AccessibleDescription = Get-ToolText -Key "about.openFaqDescription" -Culture $script:dashboardCulture
    $faq.TabIndex = 1
    $toolTip.SetToolTip($faq, $faq.AccessibleDescription)
    $faq.Add_Click({ Open-FirstRunFaq })
    $buttonBar.Controls.Add($faq)

    $history = New-Object System.Windows.Forms.Button
    $history.Text = Get-ToolText -Key "about.openHistory" -Culture $script:dashboardCulture
    $history.Font = $fontBold
    $history.Size = New-Object System.Drawing.Size(168, 30)
    $history.BackColor = $surface
    $history.ForeColor = $text
    $history.FlatStyle = "Flat"
    $history.AccessibleName = $history.Text
    $history.AccessibleDescription = Get-ToolText -Key "about.openHistoryDescription" -Culture $script:dashboardCulture
    $history.TabIndex = 0
    $toolTip.SetToolTip($history, $history.AccessibleDescription)
    $history.Add_Click({ Open-VersionHistory })
    $buttonBar.Controls.Add($history)

    $dialog.AcceptButton = $close
    $dialog.CancelButton = $close
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    & $aboutHeaderLayout $header ([EventArgs]::Empty)
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $dialog.Dispose()
    $productHeadingFont.Dispose()
}

function Get-DashboardMenuText {
    param([Parameter(Mandatory = $true)]$Metadata)
    $titleText = Get-ToolText -Key ([string]$Metadata.TitleKey) -Culture $script:dashboardCulture
    $descriptionText = Get-ToolText -Key ([string]$Metadata.DescriptionKey) -Culture $script:dashboardCulture
    return "$titleText`r`n$descriptionText"
}

function Get-DashboardSectionTitleKey {
    param([ValidateSet("Overview", "Scan", "Remediation", "Reports")][string]$Section)
    switch ($Section) {
        "Scan" { return "dashboard.section.scan" }
        "Remediation" { return "dashboard.section.remediation" }
        "Reports" { return "dashboard.section.reports" }
        default { return "dashboard.section.overview" }
    }
}

function Set-DashboardSection {
    param([ValidateSet("Overview", "Scan", "Remediation", "Reports")][string]$Section = "Overview")

    $script:dashboardSection = $Section
    $buttonPanel.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    $allowedNumbers = switch ($Section) {
        "Scan" { @(1, 2, 3, 4, 5, 9) }
        "Remediation" { @(11, 12, 13, 14, 7, 8) }
        "Reports" { @() }
        default { @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10) }
    }
    foreach ($button in $buttons) {
        $metadata = $button.Tag
        $kind = if ($metadata -and $metadata.PSObject.Properties["Kind"]) { [string]$metadata.Kind } else { "QuickAction" }
        if ($kind -eq "ReportAction") {
            $button.Visible = [bool]($Section -eq "Reports")
        } else {
            $number = if ($metadata -and $metadata.PSObject.Properties["Number"]) { [int]$metadata.Number } else { 0 }
            $button.Visible = [bool]($number -in $allowedNumbers)
        }
    }
    $menuCaption.Text = Get-ToolText -Key (Get-DashboardSectionTitleKey -Section $Section) -Culture $script:dashboardCulture

    foreach ($navButton in $sidebarNavButtons) {
        $selected = [bool]([string]$navButton.Tag.Section -eq $Section)
        $navButton.BackColor = if ($selected) {
            if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(34, 104, 196) } else { [System.Drawing.Color]::FromArgb(24, 124, 238) }
        } else {
            if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(7, 31, 61) } else { [System.Drawing.Color]::FromArgb(6, 61, 125) }
        }
        $navButton.Font = if ($selected) { $fontBold } else { $fontSidebar }
    }
    $script:syncingCompactNavigation = $true
    try {
        $compactIndex = @('Overview', 'Scan', 'Remediation', 'Reports').IndexOf($Section)
        if ($compactIndex -ge 0 -and $compactNavigation.SelectedIndex -ne $compactIndex) {
            $compactNavigation.SelectedIndex = $compactIndex
        }
    } finally {
        $script:syncingCompactNavigation = $false
    }
    Update-MainLayout
}

function Show-DashboardPreferences {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "dashboard.settings.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(520, 370)
    $dialog.MinimumSize = New-Object System.Drawing.Size(470, 340)
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.Font = $fontNormal

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "dashboard.settings.heading"
    $heading.Font = $fontIntroTitle
    $heading.Location = New-Object System.Drawing.Point(24, 20)
    $heading.Size = New-Object System.Drawing.Size(410, 30)
    $dialog.Controls.Add($heading)

    $settingsSummary = New-Object System.Windows.Forms.Label
    $settingsSummary.Text = Get-DashboardText "dashboard.settings.summary"
    $settingsSummary.Location = New-Object System.Drawing.Point(24, 52)
    $settingsSummary.Size = New-Object System.Drawing.Size(410, 38)
    $dialog.Controls.Add($settingsSummary)

    $languageLabel = New-Object System.Windows.Forms.Label
    $languageLabel.Text = Get-DashboardText "app.language"
    $languageLabel.Location = New-Object System.Drawing.Point(24, 108)
    $languageLabel.Size = New-Object System.Drawing.Size(150, 24)
    $dialog.Controls.Add($languageLabel)

    $settingsLanguage = New-Object System.Windows.Forms.ComboBox
    $settingsLanguage.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$settingsLanguage.Items.Add((Get-DashboardText "app.language.vi"))
    [void]$settingsLanguage.Items.Add((Get-DashboardText "app.language.en"))
    $settingsLanguage.SelectedIndex = if ($script:dashboardCulture -eq "en-US") { 1 } else { 0 }
    $settingsLanguage.Location = New-Object System.Drawing.Point(190, 104)
    $settingsLanguage.Size = New-Object System.Drawing.Size(244, 30)
    $dialog.Controls.Add($settingsLanguage)

    $themeLabel = New-Object System.Windows.Forms.Label
    $themeLabel.Text = Get-DashboardText "dashboard.settings.theme"
    $themeLabel.Location = New-Object System.Drawing.Point(24, 151)
    $themeLabel.Size = New-Object System.Drawing.Size(150, 24)
    $dialog.Controls.Add($themeLabel)

    $settingsTheme = New-Object System.Windows.Forms.ComboBox
    $settingsTheme.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$settingsTheme.Items.Add((Get-DashboardText "app.theme.system"))
    [void]$settingsTheme.Items.Add((Get-DashboardText "app.theme.light"))
    [void]$settingsTheme.Items.Add((Get-DashboardText "app.theme.dark"))
    $settingsTheme.SelectedIndex = switch ([string]$script:dashboardThemePreference) {
        'Light' { 1 }
        'Dark' { 2 }
        default { 0 }
    }
    $settingsTheme.Location = New-Object System.Drawing.Point(190, 147)
    $settingsTheme.Size = New-Object System.Drawing.Size(244, 30)
    $dialog.Controls.Add($settingsTheme)

    $settingsOffline = New-Object System.Windows.Forms.CheckBox
    $settingsOffline.Text = Get-DashboardText "dashboard.settings.offline"
    $settingsOffline.Checked = [bool]$script:offlineMode
    $settingsOffline.Location = New-Object System.Drawing.Point(190, 188)
    $settingsOffline.Size = New-Object System.Drawing.Size(244, 30)
    $dialog.Controls.Add($settingsOffline)

    $applyButton = New-Object System.Windows.Forms.Button
    $applyButton.Text = Get-DashboardText "dashboard.settings.apply"
    $applyButton.Font = $fontBold
    $applyButton.FlatStyle = "Flat"
    $applyButton.FlatAppearance.BorderSize = 0
    $applyButton.UseCompatibleTextRendering = $false
    $applyButton.UseVisualStyleBackColor = $false
    $applyButton.TextAlign = "MiddleCenter"
    $applyButton.Size = New-Object System.Drawing.Size(136, 38)
    $applyButton.Location = New-Object System.Drawing.Point(218, 248)
    $applyButton.Add_Click({
        $selectedCulture = if ($settingsLanguage.SelectedIndex -eq 1) { "en-US" } else { "vi-VN" }
        if ($selectedCulture -ne $script:dashboardCulture) { Set-DashboardLanguage -Culture $selectedCulture }

        $selectedThemePreference = switch ($settingsTheme.SelectedIndex) {
            1 { 'Light' }
            2 { 'Dark' }
            default { 'System' }
        }
        if ($selectedThemePreference -ne [string]$script:dashboardThemePreference) {
            [void](Set-ToolUiThemePreference -Mode $selectedThemePreference)
            $script:dashboardThemePreference = $selectedThemePreference
            $script:dashboardTheme = Get-ToolUiTheme
            $script:toolUiPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
            Set-DashboardTheme -Mode $script:dashboardTheme
        }

        $requestedOffline = [bool]$settingsOffline.Checked
        if ($requestedOffline -ne [bool]$script:offlineMode) {
            if ($requestedOffline) {
                $script:offlineMode = $true
                [void](Set-ToolOfflineModePreference -OfflineMode $true)
                $env:TOOL_OFFLINE_MODE = "1"
                Reset-ApplicationUpdateForOffline
                Update-DashboardOfflineUi
                Set-DashboardTheme -Mode $script:dashboardTheme
            } else {
                Toggle-DashboardOfflineMode
            }
        }
        $dialog.Close()
    })
    $dialog.Controls.Add($applyButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-DashboardText "common.close"
    $cancelButton.Size = New-Object System.Drawing.Size(126, 38)
    $cancelButton.Location = New-Object System.Drawing.Point(364, 248)
    $cancelButton.Add_Click({ Close-DashboardWorkflowSession -Dialog $dialog })
    $dialog.CancelButton = $cancelButton
    $dialog.Controls.Add($cancelButton)
    $dialog.AcceptButton = $applyButton

    Set-ModernRoundedRegion -Control $applyButton -Radius 9
    Set-ModernRoundedRegion -Control $cancelButton -Radius 9
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    $settingsPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
    $applyButton.BackColor = $settingsPalette.Primary
    $applyButton.ForeColor = if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    [void](Show-DashboardModalDialog -Dialog $dialog)
    $dialog.Dispose()
}

function Update-DashboardOfflineUi {
    $offlineKey = if ($script:offlineMode) { "app.offline.enabled" } else { "app.offline.disabled" }
    $offlineButton.Text = Get-ToolText -Key $offlineKey -Culture $script:dashboardCulture
    $toolTip.SetToolTip($offlineButton, (Get-ToolText -Key $(if ($script:offlineMode) { "app.offline.disable" } else { "app.offline.enable" }) -Culture $script:dashboardCulture))
}

function Toggle-DashboardOfflineMode {
    if ($script:offlineMode) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "app.offline.confirm" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "app.offline.confirmTitle" -Culture $script:dashboardCulture),
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $script:offlineMode = $false
    } else {
        $script:offlineMode = $true
    }
    [void](Set-ToolOfflineModePreference -OfflineMode $script:offlineMode)
    $env:TOOL_OFFLINE_MODE = if ($script:offlineMode) { "1" } else { "0" }
    Update-DashboardOfflineUi
    Set-DashboardTheme -Mode $script:dashboardTheme
    Refresh-DashboardLocalizedActivity
    [void](Write-ToolLog -Level "AUDIT" -Event "OfflineMode.Changed" -Message $(if ($script:offlineMode) { Get-DashboardText "offline.enabledLog" } else { Get-DashboardText "offline.networkAllowedLog" }) -Data ([ordered]@{ OfflineMode=[bool]$script:offlineMode }))
    if ($script:offlineMode) {
        $script:softwareCatalogRefreshPending = $false
        $script:softwareCatalogBackgroundSync = $false
        Reset-ApplicationUpdateForOffline
    } else {
        Request-OnlineSessionRefresh
    }
}

function Set-DashboardLanguage {
    param([Parameter(Mandatory = $true)][ValidateSet("vi-VN", "en-US")][string]$Culture)

    $script:dashboardCulture = $Culture
    $env:TOOL_UI_CULTURE = $Culture
    [void](Set-ToolCulturePreference -Culture $Culture)
    $form.Text = "$(Get-ToolText -Key "app.title" -Culture $Culture) - $releaseDisplayName"
    $title.Text = Get-ToolText -Key "app.title" -Culture $Culture
    $developer.Text = Get-ToolText -Key "app.developer" -Culture $Culture
    $version.Text = Get-DashboardText "dashboard.versionSummary" @($releaseDisplayName, $capabilityState.WindowsReleaseName, $capabilityState.FullBuildNumber, $capabilityState.OperatingSystemArchitecture, $reportSchemaState.SchemaVersion)
    $sidebarFooter.Text = Get-DashboardText "dashboard.sidebar.footer"
    if ($script:officialBuildState -in @('Official','Store')) {
        $description.Text = Get-ToolText -Key "dashboard.overview.title" -Culture $Culture
        $introSummary.Text = Get-ToolText -Key "dashboard.overview.subtitle" -Culture $Culture
    } elseif ($script:officialBuildState -eq 'Managed') {
        $description.Text = Get-DashboardText 'officialBuild.banner.managedTitle'
        $introSummary.Text = Get-DashboardText 'officialBuild.banner.managedBody'
    } elseif ($script:isUnsignedDevelopmentBuild) {
        $description.Text = Get-DashboardText 'officialBuild.banner.developmentTitle'
        $introSummary.Text = Get-DashboardText 'officialBuild.banner.developmentBody'
    } elseif ($script:officialBuildState -eq 'Modified') {
        $description.Text = Get-DashboardText 'officialBuild.banner.modifiedTitle'
        $introSummary.Text = Get-DashboardText 'officialBuild.banner.modifiedBody' @([string]$env:TOOL_OFFICIAL_VERIFICATION_URL)
    } else {
        $description.Text = Get-DashboardText 'officialBuild.banner.unverifiedTitle'
        $introSummary.Text = Get-DashboardText 'officialBuild.banner.unverifiedBody' @([string]$env:TOOL_OFFICIAL_VERIFICATION_URL)
    }
    $toolTip.SetToolTip($description, [string]$description.Text)
    $toolTip.SetToolTip($introSummary, [string]$introSummary.Text)
    $description.AccessibleName = [string]$description.Text
    $introSummary.AccessibleName = [string]$introSummary.Text
    $introSummary.AccessibleDescription = [string]$introSummary.Text
    $introAssistantButton.Text = Get-ToolText -Key "app.assistant" -Culture $Culture
    $toolTip.SetToolTip($introAssistantButton, (Get-ToolText -Key "assistant.tooltip" -Culture $Culture))
    $introDetailButton.Text = Get-ToolText -Key "app.about" -Culture $Culture
    $activityPanelCaption.Text = Get-ToolText -Key "dashboard.activity" -Culture $Culture
    $sidebarBrand.Text = Get-ToolText -Key "dashboard.sidebar.brand" -Culture $Culture
    Set-DashboardSidebarBrandFont
    foreach ($navButton in $sidebarNavButtons) {
        $navButton.Text = Get-ToolText -Key ([string]$navButton.Tag.TextKey) -Culture $Culture
    }
    $compactSelectedIndex = [Math]::Max(0, $compactNavigation.SelectedIndex)
    $script:syncingCompactNavigation = $true
    try {
        $compactNavigation.Items.Clear()
        foreach ($definition in $sidebarNavDefinitions) {
            [void]$compactNavigation.Items.Add((Get-ToolText -Key ([string]$definition.TextKey) -Culture $Culture))
        }
        $compactNavigation.SelectedIndex = [Math]::Min($compactSelectedIndex, ($compactNavigation.Items.Count - 1))
    } finally {
        $script:syncingCompactNavigation = $false
    }
    $closeButton.Text = Get-ToolText -Key "app.close" -Culture $Culture
    $stopButton.Text = Get-ToolText -Key "progress.stop" -Culture $Culture
    $copyLogButton.Text = Get-ToolText -Key "progress.copyAllLog" -Culture $Culture
    $openReportFolderButton.Text = Get-ToolText -Key "report.openFolder" -Culture $Culture
    $progressCaption.Text = Get-ToolText -Key "progress.caption" -Culture $Culture
    Refresh-ProcessingTimelineLocalization

    $dashboardCards["Compatibility"].Caption.Text = Get-ToolText -Key "dashboard.windows" -Culture $Culture
    $dashboardCards["Architecture"].Caption.Text = Get-ToolText -Key "dashboard.office" -Culture $Culture
    $dashboardCards["SecureLaunch"].Caption.Text = Get-ToolText -Key "dashboard.runMode" -Culture $Culture
    $dashboardCards["Integrity"].Caption.Text = Get-ToolText -Key "dashboard.integrity" -Culture $Culture
    $dashboardCards["ActionCenter"].Caption.Text = Get-DashboardText "resultCenter.card.caption"
    $dashboardCards["ActionCenter"].Panel.AccessibleName = Get-DashboardText "resultCenter.card.caption"
    $dashboardCards["ActionCenter"].Panel.AccessibleDescription = Get-DashboardText "resultCenter.card.tooltip"
    $dashboardCards["SecureLaunch"].Value.Text = if ($script:officialBuildState -eq 'Official') {
        Get-DashboardText 'officialBuild.state.official'
    } elseif ($script:officialBuildState -eq 'Managed') {
        Get-DashboardText 'officialBuild.state.managed'
    } elseif ($script:officialBuildState -eq 'Store') {
        Get-DashboardText 'officialBuild.state.store'
    } elseif ($script:officialBuildState -eq 'Modified') {
        Get-DashboardText 'officialBuild.state.modified'
    } else {
        Get-DashboardText 'officialBuild.state.unverified'
    }
    if ($script:lastIntegrityResult) {
        $dashboardCards["Integrity"].Value.Text = if ($script:lastIntegrityResult.Valid) {
            Get-ToolText -Key "dashboard.integrity.ok" -Culture $Culture -FormatArguments @($safetyPolicyState.RegistryValuePolicyCount)
        } else {
            Get-ToolText -Key "dashboard.integrity.failed" -Culture $Culture
        }
    }
    foreach ($dashboardCardKey in @($dashboardCards.Keys)) {
        Sync-DashboardCardAccessibility -CardKey ([string]$dashboardCardKey)
    }
    Update-ResultActionCard -UseCachedState -HeaderOnly
    foreach ($button in $buttons) {
        $metadata = $button.Tag
        if ($metadata -and $metadata.PSObject.Properties["TitleKey"]) {
            if ([string]$metadata.Kind -in @("QuickAction", "ReportAction") -and $metadata.TitleLabel -and $metadata.DescriptionLabel) {
                $metadata.TitleLabel.Text = Get-ToolText -Key ([string]$metadata.TitleKey) -Culture $Culture
                $metadata.DescriptionLabel.Text = Get-ToolText -Key ([string]$metadata.DescriptionKey) -Culture $Culture
                $button.Text = [string]$metadata.TitleLabel.Text
            } else {
                $button.Text = Get-DashboardMenuText -Metadata $metadata
            }
            $button.AccessibleName = Get-ToolText -Key ([string]$metadata.TitleKey) -Culture $Culture
            $button.AccessibleDescription = Get-ToolText -Key ([string]$metadata.DescriptionKey) -Culture $Culture
            $toolTip.SetToolTip($button, (Get-ToolText -Key ([string]$metadata.DescriptionKey) -Culture $Culture))
        }
    }
    Set-DashboardSection -Section $script:dashboardSection
    Update-DashboardOfflineUi
    Set-DashboardTheme -Mode $script:dashboardTheme
    Update-MainLayout
    Refresh-DashboardLocalizedActivity -ResetRenderedHistory
    [void](Write-ToolLog -Level "INFO" -Event "Culture.Changed" -Message "Dashboard culture: $Culture." -Data ([ordered]@{ Culture=$Culture }))
}

function Get-DashboardTilePalette {
    param(
        [ValidateSet("Normal", "Warning", "Enterprise")][string]$Tone = "Normal",
        [ValidateSet("Light", "Dark")][string]$Mode = "Light",
        [switch]$Hover
    )

    if (Test-ToolUiHighContrast) {
        return [pscustomobject]@{
            BackColor = [System.Drawing.SystemColors]::Control
            ForeColor = [System.Drawing.SystemColors]::ControlText
            TitleColor = [System.Drawing.SystemColors]::ControlText
            DescriptionColor = [System.Drawing.SystemColors]::ControlText
        }
    }
    $dark = [bool]($Mode -eq "Dark")
    return [pscustomobject]@{
        BackColor = if ($dark) {
            if ($Hover) { [System.Drawing.Color]::FromArgb(43, 53, 69) } else { [System.Drawing.Color]::FromArgb(34, 42, 55) }
        } else {
            if ($Hover) { [System.Drawing.Color]::FromArgb(231, 238, 247) } else { [System.Drawing.Color]::FromArgb(244, 247, 251) }
        }
        ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(220, 228, 239) } else { [System.Drawing.Color]::FromArgb(30, 64, 105) }
        TitleColor = if ($dark) { [System.Drawing.Color]::FromArgb(137, 190, 255) } else { [System.Drawing.Color]::FromArgb(0, 98, 218) }
        DescriptionColor = if ($dark) { [System.Drawing.Color]::FromArgb(174, 184, 200) } else { [System.Drawing.Color]::FromArgb(88, 101, 121) }
    }
}

function Get-DashboardStatusPalette {
    param(
        [ValidateSet("Windows", "Office", "Secure", "Integrity", "Action")][string]$Tone,
        [ValidateSet("Light", "Dark")][string]$Mode = "Light"
    )
    if (Test-ToolUiHighContrast) {
        return [pscustomobject]@{
            BackColor = [System.Drawing.SystemColors]::Window
            AccentColor = [System.Drawing.SystemColors]::WindowFrame
            ValueColor = [System.Drawing.SystemColors]::WindowText
        }
    }
    $dark = [bool]($Mode -eq "Dark")
    switch ($Tone) {
        "Windows" {
            return [pscustomobject]@{
                BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(35, 48, 66) } else { [System.Drawing.Color]::FromArgb(242, 248, 255) }
                AccentColor = if ($dark) { [System.Drawing.Color]::FromArgb(93, 151, 231) } else { [System.Drawing.Color]::FromArgb(45, 111, 203) }
                ValueColor = if ($dark) { [System.Drawing.Color]::FromArgb(190, 216, 250) } else { [System.Drawing.Color]::FromArgb(18, 76, 137) }
            }
        }
        "Office" {
            return [pscustomobject]@{
                BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(65, 42, 35) } else { [System.Drawing.Color]::FromArgb(255, 246, 242) }
                AccentColor = if ($dark) { [System.Drawing.Color]::FromArgb(242, 117, 78) } else { [System.Drawing.Color]::FromArgb(234, 88, 35) }
                ValueColor = if ($dark) { [System.Drawing.Color]::FromArgb(255, 205, 185) } else { [System.Drawing.Color]::FromArgb(177, 59, 25) }
            }
        }
        "Secure" {
            return [pscustomobject]@{
                BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(31, 54, 70) } else { [System.Drawing.Color]::FromArgb(241, 248, 255) }
                AccentColor = if ($dark) { [System.Drawing.Color]::FromArgb(83, 171, 225) } else { [System.Drawing.Color]::FromArgb(28, 132, 201) }
                ValueColor = if ($dark) { [System.Drawing.Color]::FromArgb(190, 230, 250) } else { [System.Drawing.Color]::FromArgb(12, 91, 146) }
            }
        }
        "Integrity" {
            return [pscustomobject]@{
                BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(30, 62, 49) } else { [System.Drawing.Color]::FromArgb(240, 251, 246) }
                AccentColor = if ($dark) { [System.Drawing.Color]::FromArgb(67, 190, 142) } else { [System.Drawing.Color]::FromArgb(20, 157, 102) }
                ValueColor = if ($dark) { [System.Drawing.Color]::FromArgb(184, 240, 211) } else { [System.Drawing.Color]::FromArgb(8, 116, 73) }
            }
        }
        "Action" {
            return [pscustomobject]@{
                BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(54, 42, 74) } else { [System.Drawing.Color]::FromArgb(247, 243, 255) }
                AccentColor = if ($dark) { [System.Drawing.Color]::FromArgb(157, 125, 230) } else { [System.Drawing.Color]::FromArgb(122, 77, 216) }
                ValueColor = if ($dark) { [System.Drawing.Color]::FromArgb(226, 211, 255) } else { [System.Drawing.Color]::FromArgb(91, 47, 169) }
            }
        }
        default {
            return [pscustomobject]@{
                BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(31, 38, 50) } else { [System.Drawing.Color]::FromArgb(247, 249, 252) }
                AccentColor = if ($dark) { [System.Drawing.Color]::FromArgb(105, 153, 222) } else { [System.Drawing.Color]::FromArgb(70, 112, 166) }
                ValueColor = if ($dark) { [System.Drawing.Color]::FromArgb(220, 228, 239) } else { [System.Drawing.Color]::FromArgb(34, 61, 94) }
            }
        }
    }
}

function Set-DashboardTheme {
    param(
        [ValidateSet("Light", "Dark")][string]$Mode,
        [switch]$StartupFast
    )
    $env:TOOL_UI_THEME = $Mode
    $script:toolUiPalette = Get-ToolUiPalette -Mode $Mode
    $dark = [bool]($Mode -eq "Dark")
    $surface = if ($dark) { [System.Drawing.Color]::FromArgb(29, 34, 45) } else { [System.Drawing.Color]::White }
    $background = if ($dark) { [System.Drawing.Color]::FromArgb(15, 19, 27) } else { [System.Drawing.Color]::FromArgb(246, 249, 253) }
    $primary = if ($dark) { [System.Drawing.Color]::FromArgb(137, 190, 255) } else { [System.Drawing.Color]::FromArgb(0, 98, 218) }
    $text = if ($dark) { [System.Drawing.Color]::FromArgb(226, 231, 239) } else { [System.Drawing.Color]::FromArgb(52, 64, 84) }
    $muted = if ($dark) { [System.Drawing.Color]::FromArgb(164, 174, 192) } else { [System.Drawing.Color]::FromArgb(102, 112, 133) }
    $introSurface = if ($dark) { [System.Drawing.Color]::FromArgb(30, 44, 65) } else { [System.Drawing.Color]::FromArgb(232, 243, 255) }

    $form.BackColor = $background
    $headerPanel.BackColor = $surface
    $sidebarPanel.BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(7, 31, 61) } else { [System.Drawing.Color]::FromArgb(6, 61, 125) }
    $sidebarBrand.ForeColor = [System.Drawing.Color]::White
    $sidebarFooter.ForeColor = [System.Drawing.Color]::FromArgb(182, 214, 248)
    $title.ForeColor = $primary
    $developer.ForeColor = $primary
    $version.ForeColor = $muted
    if ($script:officialBuildState -in @('Official','Store')) {
        $introPanel.BackColor = $introSurface
        Set-DashboardIntroBorderColor -Color $primary
        $description.ForeColor = $primary
        $introSummary.ForeColor = $text
    } elseif ($script:officialBuildState -eq 'Managed') {
        $introPanel.BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(8, 47, 73) } else { [System.Drawing.Color]::FromArgb(232, 245, 255) }
        Set-DashboardIntroBorderColor -Color $(if ($dark) { [System.Drawing.Color]::FromArgb(56, 189, 248) } else { [System.Drawing.Color]::FromArgb(2, 132, 199) })
        $description.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(186, 230, 253) } else { [System.Drawing.Color]::FromArgb(3, 105, 161) }
        $introSummary.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(224, 242, 254) } else { [System.Drawing.Color]::FromArgb(7, 89, 133) }
    } elseif ($script:isUnsignedDevelopmentBuild) {
        $introPanel.BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(69, 45, 15) } else { [System.Drawing.Color]::FromArgb(255, 248, 225) }
        Set-DashboardIntroBorderColor -Color $(if ($dark) { [System.Drawing.Color]::FromArgb(251, 191, 36) } else { [System.Drawing.Color]::FromArgb(217, 119, 6) })
        $description.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(254, 240, 138) } else { [System.Drawing.Color]::FromArgb(146, 64, 14) }
        $introSummary.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(254, 243, 199) } else { [System.Drawing.Color]::FromArgb(120, 53, 15) }
    } else {
        $introPanel.BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(67, 28, 33) } else { [System.Drawing.Color]::FromArgb(255, 235, 238) }
        Set-DashboardIntroBorderColor -Color $(if ($dark) { [System.Drawing.Color]::FromArgb(248, 113, 113) } else { [System.Drawing.Color]::FromArgb(185, 28, 28) })
        $description.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(254, 202, 202) } else { [System.Drawing.Color]::FromArgb(153, 27, 27) }
        $introSummary.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(254, 226, 226) } else { [System.Drawing.Color]::FromArgb(127, 29, 29) }
    }
    if (Test-ToolUiHighContrast) {
        Set-DashboardIntroBorderColor -Color ([System.Drawing.SystemColors]::Highlight)
    }
    $introAssistantButton.BackColor = $primary
    $introAssistantButton.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    $introDetailButton.BackColor = $primary
    $introDetailButton.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    $dashboardPanel.BackColor = $background
    $buttonPanel.BackColor = $surface
    $activityPanel.BackColor = $surface
    $activityPanelCaption.ForeColor = $primary
    $menuCaption.ForeColor = $primary
    $progressCaption.ForeColor = $primary
    $elapsedLabel.ForeColor = $muted
    $progressLog.BackColor = $surface
    $progressLog.ForeColor = $text
    $closeButton.BackColor = $surface
    $closeButton.ForeColor = $text
    $stopButton.BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(139, 43, 52) } else { [System.Drawing.Color]::FromArgb(185, 28, 28) }
    $stopButton.ForeColor = [System.Drawing.Color]::White
    $copyLogButton.BackColor = $surface
    $copyLogButton.ForeColor = $text
    $openReportFolderButton.BackColor = $surface
    $openReportFolderButton.ForeColor = $text
    $themeButton.BackColor = $surface
    $themeButton.ForeColor = $text
    $themeButton.Text = Get-ToolText -Key $(if ($dark) { "app.theme.light" } else { "app.theme.dark" }) -Culture $script:dashboardCulture
    $languageCombo.BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(38, 44, 57) } else { [System.Drawing.Color]::White }
    $languageCombo.ForeColor = $text
    $offlineButton.BackColor = if ($script:offlineMode) {
        if ($dark) { [System.Drawing.Color]::FromArgb(24, 91, 66) } else { [System.Drawing.Color]::FromArgb(222, 246, 235) }
    } else {
        if ($dark) { [System.Drawing.Color]::FromArgb(94, 62, 23) } else { [System.Drawing.Color]::FromArgb(255, 241, 218) }
    }
    $offlineButton.ForeColor = if ($script:offlineMode) {
        if ($dark) { [System.Drawing.Color]::FromArgb(139, 233, 190) } else { [System.Drawing.Color]::FromArgb(15, 111, 74) }
    } else {
        if ($dark) { [System.Drawing.Color]::FromArgb(255, 200, 122) } else { [System.Drawing.Color]::FromArgb(135, 76, 0) }
    }

    foreach ($cardKey in @($dashboardCards.Keys)) {
        $cardRecord = $dashboardCards[$cardKey]
        $statusPalette = Get-DashboardStatusPalette -Tone ([string]$cardRecord.Tone) -Mode $Mode
        $cardRecord.Panel.BackColor = $statusPalette.BackColor
        if ($cardRecord.Panel.Tag -and $cardRecord.Panel.Tag.PSObject.Properties["BorderColor"]) {
            $cardRecord.Panel.Tag.BorderColor = $statusPalette.AccentColor
        }
        $cardRecord.Panel.Invalidate()
        $cardRecord.Caption.ForeColor = $muted
        if ($cardRecord.Value.Tag -ne "StatusColor") { $cardRecord.Value.ForeColor = $statusPalette.ValueColor }
        foreach ($child in $cardRecord.Panel.Controls) {
            if ([string]$child.Tag -eq "CardGlyph") { $child.BackColor = [System.Drawing.Color]::Transparent }
        }
    }
    if ($script:lastIntegrityResult) { Update-DashboardStatus -IntegrityResult $script:lastIntegrityResult }
    foreach ($button in $buttons) {
        $tone = if ($button.Tag -and $button.Tag.PSObject.Properties["Tone"]) { [string]$button.Tag.Tone } else { "Normal" }
        $tilePalette = Get-DashboardTilePalette -Tone $tone -Mode $Mode
        $button.BackColor = $tilePalette.BackColor
        $button.ForeColor = $tilePalette.ForeColor
        if ($button.Tag -and [string]$button.Tag.Kind -in @("QuickAction", "ReportAction")) {
            if ($button.Tag.TitleLabel) { $button.Tag.TitleLabel.ForeColor = $tilePalette.TitleColor }
            if ($button.Tag.DescriptionLabel) { $button.Tag.DescriptionLabel.ForeColor = $tilePalette.DescriptionColor }
        }
    }
    foreach ($navButton in $sidebarNavButtons) {
        $selected = [bool]([string]$navButton.Tag.Section -eq $script:dashboardSection)
        $navButton.BackColor = if ($selected) {
            if ($dark) { [System.Drawing.Color]::FromArgb(34, 104, 196) } else { [System.Drawing.Color]::FromArgb(24, 124, 238) }
        } else {
            if ($dark) { [System.Drawing.Color]::FromArgb(7, 31, 61) } else { [System.Drawing.Color]::FromArgb(6, 61, 125) }
        }
        $navButton.ForeColor = [System.Drawing.Color]::White
    }

    $neutralLightArgb = [System.Drawing.Color]::FromArgb(52, 64, 84).ToArgb()
    $neutralDarkArgb = [System.Drawing.Color]::FromArgb(226, 231, 239).ToArgb()
    if ($status.ForeColor.ToArgb() -in @($neutralLightArgb, $neutralDarkArgb)) { $status.ForeColor = $text }
    if ($activityLabel.ForeColor.ToArgb() -in @($neutralLightArgb, $neutralDarkArgb, [System.Drawing.Color]::FromArgb(18, 59, 116).ToArgb(), [System.Drawing.Color]::FromArgb(126, 174, 255).ToArgb())) { $activityLabel.ForeColor = $text }
    if (-not $StartupFast) { Complete-DashboardThemeInitialization -Mode $Mode }
    $form.Invalidate($true)
}

function Set-DashboardAssistantButtonHighlight {
    param([ValidateSet("Light", "Dark")][string]$Mode)

    # High Contrast must retain native system colors and focus rendering.
    if (Test-ToolUiHighContrast) { return }

    $dark = [bool]($Mode -eq "Dark")
    $introAssistantButton.UseVisualStyleBackColor = $false
    $introAssistantButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $introAssistantButton.Font = $fontBold
    $introAssistantButton.BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(29, 78, 216) } else { [System.Drawing.Color]::FromArgb(0, 95, 184) }
    $introAssistantButton.ForeColor = [System.Drawing.Color]::White
    $introAssistantButton.FlatAppearance.BorderColor = if ($dark) { [System.Drawing.Color]::FromArgb(147, 197, 253) } else { [System.Drawing.Color]::FromArgb(0, 57, 120) }
    $introAssistantButton.FlatAppearance.BorderSize = 2
    $introAssistantButton.FlatAppearance.MouseOverBackColor = if ($dark) { [System.Drawing.Color]::FromArgb(30, 64, 175) } else { [System.Drawing.Color]::FromArgb(0, 120, 212) }
    $introAssistantButton.FlatAppearance.MouseDownBackColor = if ($dark) { [System.Drawing.Color]::FromArgb(30, 58, 138) } else { [System.Drawing.Color]::FromArgb(0, 76, 145) }
    Set-ToolUiRoundedButtonRegion -Button $introAssistantButton -Radius 9
}

function Complete-DashboardThemeInitialization {
    param([ValidateSet("Light", "Dark")][string]$Mode)
    foreach ($actionButton in @($introAssistantButton, $introDetailButton, $themeButton, $offlineButton, $openReportFolderButton, $copyLogButton, $stopButton, $closeButton)) {
        Set-ToolUiActionButtonVisual -Button $actionButton -Mode $Mode
    }
    Set-DashboardAssistantButtonHighlight -Mode $Mode
    Write-DashboardStartupTrace "Theme.ControlsStyled"
    Set-ToolUiLiteralText -Root $form
    Write-DashboardStartupTrace "Theme.TextNormalized"
    if (Test-ToolUiHighContrast) {
        Set-ToolWindowTheme -Root $form -Mode $Mode
        Write-DashboardStartupTrace "Theme.HighContrastReady"
        return
    }
    Register-ToolUiDynamicContrast -Root $form -Mode $Mode
    Write-DashboardStartupTrace "Theme.ContrastReady"
}

function Update-DashboardStatus {
    param($IntegrityResult)
    $script:lastIntegrityResult = $IntegrityResult
    $successColor = if (Test-ToolUiHighContrast) { [System.Drawing.SystemColors]::WindowText } elseif ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(86, 230, 156) } else { [System.Drawing.Color]::FromArgb(0, 125, 69) }
    $warningColor = if (Test-ToolUiHighContrast) { [System.Drawing.SystemColors]::WindowText } elseif ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(255, 193, 82) } else { [System.Drawing.Color]::FromArgb(217, 119, 0) }
    $compatibilityCard = $dashboardCards["Compatibility"]
    $compatibilityCard.Value.AutoEllipsis = $true
    $catalogHealth = [string]$compatibilityState.CatalogHealth
    $catalogAgeDays = [int]$compatibilityState.CatalogAgeDays
    $catalogMaximumAgeDays = [int]$compatibilityState.MaximumReviewAgeDays
    $catalogTooltip = if ($catalogHealth -eq "Stale") {
        Get-DashboardText "dashboard.compatibility.catalogStale" @($catalogAgeDays, $catalogMaximumAgeDays)
    } elseif ($catalogHealth -eq "Warning") {
        Get-DashboardText "dashboard.compatibility.catalogWarning" @($catalogAgeDays, $catalogMaximumAgeDays)
    } else {
        Get-DashboardText "dashboard.compatibility.catalogFresh" @($compatibilityState.ReviewedAtUtc, $catalogAgeDays, $catalogMaximumAgeDays)
    }
    $softwareCatalogHealth = if ($script:softwareCatalogFreshnessState) { [string]$script:softwareCatalogFreshnessState.Status } else { 'Deferred' }
    if ($softwareCatalogHealth -notin @('Fresh','Warning','Stale','Future','Invalid','Unavailable','Deferred')) {
        $softwareCatalogHealth = 'Unavailable'
    }
    $softwareCatalogStatusKey = $softwareCatalogHealth.ToLowerInvariant()
    $softwareCatalogTooltip = if ($script:softwareCatalogFreshnessState) {
        Get-DashboardText ("dashboard.softwareCatalog." + $softwareCatalogStatusKey) @(
            [int]$script:softwareCatalogFreshnessState.AgeDays,
            [int]$script:softwareCatalogFreshnessState.MaximumAgeDays)
    } else { $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$softwareCatalogTooltip)) {
        $catalogTooltip = $catalogTooltip + "`r`n`r`n" + $softwareCatalogTooltip
    }
    $compatibilityValue = if ($catalogHealth -eq "Stale") {
        Get-DashboardText "dashboard.compatibility.valueStale" @($capabilityState.WindowsReleaseName)
    } elseif ($catalogHealth -eq "Warning") {
        Get-DashboardText "dashboard.compatibility.valueWarning" @($capabilityState.WindowsReleaseName, $catalogAgeDays)
    } else {
        [string]$capabilityState.WindowsReleaseName
    }
    # Keep software-catalog freshness enforcement and its tooltip, but do not
    # add a second "Catalog phần mềm: mới" line to the compact status card.
    $compatibilityCard.Value.Text = $compatibilityValue
    $toolTip.SetToolTip($compatibilityCard.Panel, $catalogTooltip)
    $toolTip.SetToolTip($compatibilityCard.Value, $catalogTooltip)
    if ($catalogHealth -in @("Warning", "Stale") -or $softwareCatalogHealth -in @('Warning','Stale','Future','Invalid','Unavailable')) {
        $compatibilityCard.Value.ForeColor = $warningColor
        $compatibilityCard.Value.Tag = "StatusColor"
    } else {
        $compatibilityPalette = Get-DashboardStatusPalette -Tone ([string]$compatibilityCard.Tone) -Mode $script:dashboardTheme
        $compatibilityCard.Value.ForeColor = $compatibilityPalette.ValueColor
        $compatibilityCard.Value.Tag = $null
    }
    $dashboardCards["Architecture"].Value.Text = [string]$capabilityState.OfficeSummary
    $dashboardCards["SecureLaunch"].Value.Text = if ($script:officialBuildState -eq 'Official') {
        Get-DashboardText 'officialBuild.state.official'
    } elseif ($script:officialBuildState -eq 'Managed') {
        Get-DashboardText 'officialBuild.state.managed'
    } elseif ($script:officialBuildState -eq 'Store') {
        Get-DashboardText 'officialBuild.state.store'
    } elseif ($script:officialBuildState -eq 'Modified') {
        Get-DashboardText 'officialBuild.state.modified'
    } else {
        Get-DashboardText 'officialBuild.state.unverified'
    }
    $dashboardCards["Integrity"].Value.Text = if ($IntegrityResult.Valid) {
        Get-ToolText -Key "dashboard.integrity.ok" -Culture $script:dashboardCulture -FormatArguments @($safetyPolicyState.RegistryValuePolicyCount)
    } else {
        Get-ToolText -Key "dashboard.integrity.failed" -Culture $script:dashboardCulture
    }
    $dashboardCards["Integrity"].Value.ForeColor = if ($IntegrityResult.Valid) { $successColor } else { $warningColor }
    $dashboardCards["Integrity"].Value.Tag = "StatusColor"
    $dashboardCards["SecureLaunch"].Value.ForeColor = if ($script:officialBuildState -in @('Official','Managed','Store')) { $successColor } else { $warningColor }
    $dashboardCards["SecureLaunch"].Value.Tag = "StatusColor"
    Sync-DashboardCardAccessibility -CardKey "Compatibility" -Detail $catalogTooltip
    Sync-DashboardCardAccessibility -CardKey "Architecture"
    Sync-DashboardCardAccessibility -CardKey "SecureLaunch"
    Sync-DashboardCardAccessibility -CardKey "Integrity"
    Update-DashboardOfflineUi
}
