Set-StrictMode -Version 2.0

function Get-VietLicenSureSourcePartNames {
    param([Parameter(Mandatory = $true)][string]$EntrypointName)

    switch ($EntrypointName) {
        'Giao-Dien.ps1' {
            return @(
                'Giao-Dien.ps1',
                'Dashboard-Core.ps1',
                'Dashboard-Execution.ps1',
                'Dashboard-OnlineUpdate.ps1',
                'Dashboard-CleanupWorkflow.ps1',
                'Dashboard-AssuranceCenter.ps1'
            )
        }
        'windows-license-compliance-cleanup.ps1' {
            return @(
                'windows-license-compliance-cleanup.ps1',
                'Cleanup-Platform.ps1',
                'Cleanup-Detection.ps1',
                'Cleanup-Evidence.ps1',
                'Cleanup-Remediation.ps1'
            )
        }
        default { return @($EntrypointName) }
    }
}

function Get-VietLicenSureComposedSourceText {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$EntrypointName
    )

    $segments = New-Object System.Collections.Generic.List[string]
    foreach ($name in @(Get-VietLicenSureSourcePartNames -EntrypointName $EntrypointName)) {
        $path = Join-Path $SourceDirectory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing composed source part: $name"
        }
        $segments.Add([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8))
    }
    return ($segments -join "`r`n")
}

function Get-VietLicenSureComposedSourceAst {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$EntrypointName,
        [ref]$Tokens,
        [ref]$ParseErrors
    )

    $text = Get-VietLicenSureComposedSourceText -SourceDirectory $SourceDirectory -EntrypointName $EntrypointName
    return [System.Management.Automation.Language.Parser]::ParseInput(
        $text,
        (Join-Path $SourceDirectory $EntrypointName),
        $Tokens,
        $ParseErrors
    )
}
