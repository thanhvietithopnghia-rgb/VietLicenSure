function Set-ModernRoundedRegion {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Control,
        [int]$Radius = 12
    )
    if ($Control.Width -le 2 -or $Control.Height -le 2) { return }
    $diameter = [Math]::Max(2, [Math]::Min($Radius * 2, [Math]::Min($Control.Width - 1, $Control.Height - 1)))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    try {
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc($Control.Width - $diameter - 1, 0, $diameter, $diameter, 270, 90)
        $path.AddArc($Control.Width - $diameter - 1, $Control.Height - $diameter - 1, $diameter, $diameter, 0, 90)
        $path.AddArc(0, $Control.Height - $diameter - 1, $diameter, $diameter, 90, 90)
        $path.CloseFigure()
        $newRegion = New-Object System.Drawing.Region($path)
        $oldRegion = $Control.Region
        $Control.Region = $newRegion
        if ($oldRegion) { $oldRegion.Dispose() }
    } finally {
        $path.Dispose()
    }
}

function Set-DashboardHeaderTitleFont {
    param([bool]$PreferLarge = $true)

    $candidateFonts = if ($PreferLarge) {
        @($fontTitle, $fontTitleCompact, $fontTitleMedium, $fontTitleSmall, $fontTitleTiny, $fontTitleMicro, $fontTitleMinimum)
    } else {
        @($fontTitleCompact, $fontTitleMedium, $fontTitleSmall, $fontTitleTiny, $fontTitleMicro, $fontTitleMinimum)
    }
    $availableWidth = [Math]::Max(1, $title.ClientSize.Width - 4)
    $selectedFont = $candidateFonts[$candidateFonts.Count - 1]
    foreach ($candidateFont in $candidateFonts) {
        $measuredWidth = [System.Windows.Forms.TextRenderer]::MeasureText([string]$title.Text, $candidateFont).Width
        if ($measuredWidth -le $availableWidth) {
            $selectedFont = $candidateFont
            break
        }
    }
    $title.Font = $selectedFont
}

function Set-DashboardSidebarBrandFont {
    $availableWidth = [Math]::Max(1, $sidebarBrand.ClientSize.Width - 4)
    $textFlags = [System.Windows.Forms.TextFormatFlags]::NoPadding -bor
        [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
        [System.Windows.Forms.TextFormatFlags]::NoPrefix
    $candidateFonts = @($fontSidebarTitle, $fontSidebarTitleCompact, $fontSidebarTitleMinimum)
    $selectedFont = $candidateFonts[$candidateFonts.Count - 1]
    foreach ($candidateFont in $candidateFonts) {
        $requiredWidth = [System.Windows.Forms.TextRenderer]::MeasureText(
            [string]$sidebarBrand.Text,
            $candidateFont,
            [System.Drawing.Size]::Empty,
            $textFlags).Width + 6
        if ($requiredWidth -le $availableWidth) {
            $selectedFont = $candidateFont
            break
        }
    }
    $sidebarBrand.Font = $selectedFont
}

function Get-DashboardComboRequiredWidth {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.ComboBox]$ComboBox,
        [ValidateRange(4, 40)][int]$HorizontalSafety = 18
    )

    $textFlags = [System.Windows.Forms.TextFormatFlags]::NoPadding -bor
        [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
        [System.Windows.Forms.TextFormatFlags]::NoPrefix
    $maximumTextWidth = 0
    foreach ($item in $ComboBox.Items) {
        $itemWidth = [System.Windows.Forms.TextRenderer]::MeasureText(
            [string]$item,
            $ComboBox.Font,
            [System.Drawing.Size]::Empty,
            $textFlags).Width
        if ($itemWidth -gt $maximumTextWidth) { $maximumTextWidth = $itemWidth }
    }
    return [int]($maximumTextWidth + [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth + $HorizontalSafety)
}

function Get-DashboardWrappedTextHeight {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][System.Drawing.Font]$Font,
        [ValidateRange(1, 4096)][int]$Width,
        [ValidateRange(1, 512)][int]$MinimumHeight = 18,
        [ValidateRange(1, 512)][int]$MaximumHeight = 72
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $MinimumHeight }
    $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor
        [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor
        [System.Windows.Forms.TextFormatFlags]::NoPadding -bor
        [System.Windows.Forms.TextFormatFlags]::TextBoxControl
    $measured = [System.Windows.Forms.TextRenderer]::MeasureText(
        $Text,
        $Font,
        (New-Object System.Drawing.Size([Math]::Max(1, $Width), 1024)),
        $flags)
    return [int][Math]::Max($MinimumHeight, [Math]::Min($MaximumHeight, ($measured.Height + 2)))
}
