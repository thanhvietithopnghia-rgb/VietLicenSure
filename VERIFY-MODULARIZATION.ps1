[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) { [void]$failures.Add($Message) }

$groups = [ordered]@{
    'Giao-Dien.ps1' = [ordered]@{
        MaximumLines = 2000
        TotalFunctions = 177
        Modules = [ordered]@{
            'Dashboard-Core.ps1' = 38
            'Dashboard-Execution.ps1' = 43
            'Dashboard-OnlineUpdate.ps1' = 17
            'Dashboard-CleanupWorkflow.ps1' = 58
            'Dashboard-AssuranceCenter.ps1' = 21
        }
    }
    'windows-license-compliance-cleanup.ps1' = [ordered]@{
        MaximumLines = 1600
        TotalFunctions = 123
        Modules = [ordered]@{
            'Cleanup-Platform.ps1' = 48
            'Cleanup-Detection.ps1' = 26
            'Cleanup-Evidence.ps1' = 32
            'Cleanup-Remediation.ps1' = 17
        }
    }
}

$allModuleNames = New-Object System.Collections.Generic.List[string]
foreach ($entrypointName in $groups.Keys) {
    $contract = $groups[$entrypointName]
    $entrypointPath = Join-Path $root $entrypointName
    if (-not (Test-Path -LiteralPath $entrypointPath -PathType Leaf)) {
        Add-Failure "Missing entrypoint: $entrypointName"
        continue
    }
    $entrypointTokens = $null
    $entrypointErrors = $null
    $entrypointAst = [Management.Automation.Language.Parser]::ParseFile($entrypointPath, [ref]$entrypointTokens, [ref]$entrypointErrors)
    foreach ($parseError in @($entrypointErrors)) { Add-Failure "Parser error in ${entrypointName}: $($parseError.Message)" }
    $entrypointFunctions = @($entrypointAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })
    if ($entrypointFunctions.Count -ne 0) { Add-Failure "$entrypointName still contains $($entrypointFunctions.Count) top-level function(s)." }
    $entrypointLineCount = @(Get-Content -LiteralPath $entrypointPath -Encoding UTF8).Count
    if ($entrypointLineCount -gt [int]$contract.MaximumLines) { Add-Failure "$entrypointName exceeds $($contract.MaximumLines) lines: $entrypointLineCount" }
    $entrypointText = Get-Content -LiteralPath $entrypointPath -Raw -Encoding UTF8

    $functionNames = New-Object System.Collections.Generic.List[string]
    foreach ($moduleName in $contract.Modules.Keys) {
        $allModuleNames.Add($moduleName)
        if ($entrypointText -notmatch [regex]::Escape(". (Join-Path `$PSScriptRoot '$moduleName')")) {
            Add-Failure "$entrypointName does not dot-source $moduleName."
        }
        $modulePath = Join-Path $root $moduleName
        if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            Add-Failure "Missing module: $moduleName"
            continue
        }
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$tokens, [ref]$parseErrors)
        foreach ($parseError in @($parseErrors)) { Add-Failure "Parser error in ${moduleName}: $($parseError.Message)" }
        $nonFunctionStatements = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [Management.Automation.Language.FunctionDefinitionAst] })
        if ($nonFunctionStatements.Count -ne 0) { Add-Failure "$moduleName contains executable top-level statements." }
        $functions = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })
        if ($functions.Count -ne [int]$contract.Modules[$moduleName]) {
            Add-Failure "$moduleName function count is $($functions.Count), expected $($contract.Modules[$moduleName])."
        }
        foreach ($functionAst in $functions) { $functionNames.Add([string]$functionAst.Name) }
    }
    if ($functionNames.Count -ne [int]$contract.TotalFunctions) {
        Add-Failure "$entrypointName module union has $($functionNames.Count) functions, expected $($contract.TotalFunctions)."
    }
    $uniqueFunctionCount = @($functionNames | Sort-Object -Unique).Count
    if ($uniqueFunctionCount -ne $functionNames.Count) { Add-Failure "$entrypointName module union contains duplicate function names." }
}

$buildText = Get-Content -LiteralPath (Join-Path $root 'BUILD.ps1') -Raw -Encoding UTF8
$dashboardText = Get-Content -LiteralPath (Join-Path $root 'Giao-Dien.ps1') -Raw -Encoding UTF8
$manifestText = Get-Content -LiteralPath (Join-Path $root 'TOOL-SHA256SUMS.txt') -Raw -Encoding UTF8
foreach ($moduleName in $allModuleNames) {
    if ($buildText -notmatch [regex]::Escape("'$moduleName'")) { Add-Failure "BUILD.ps1 does not package $moduleName." }
    if ($dashboardText -notmatch [regex]::Escape('"' + $moduleName + '"')) { Add-Failure "Dashboard integrity list omits $moduleName." }
    if ($manifestText -notmatch ('(?m)^[0-9A-F]{64}  ' + [regex]::Escape($moduleName) + '\r?$')) { Add-Failure "TOOL-SHA256SUMS.txt omits $moduleName." }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-MODULARIZATION: FAILED ($($failures.Count) errors)" -ForegroundColor Red
    exit 1
}

Write-Host 'VERIFY-MODULARIZATION: PASS (2 compatible entrypoints; 9 function libraries; 300 top-level functions; no executable module statements)' -ForegroundColor Green
exit 0
