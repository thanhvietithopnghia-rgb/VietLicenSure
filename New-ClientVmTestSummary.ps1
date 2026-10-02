[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ResultsDirectory,
    [string]$JsonOutputPath = "",
    [string]$MarkdownOutputPath = "",
    [string]$Repository = "",
    [string]$WorkflowName = "",
    [string]$WorkflowRunId = "",
    [int]$WorkflowRunAttempt = 0,
    [string[]]$ExpectedPlatforms = @("win10-22h2", "win11-previous", "win11-current")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$requiredTestNames = @(
    'VERIFY-FOUNDATION.ps1',
    'VERIFY-COMPATIBILITY.ps1',
    'VERIFY-REPORT-SCHEMA.ps1',
    'VERIFY-DASHBOARD.ps1',
    'VERIFY-OFFLINE-I18N.ps1',
    'VERIFY-LOCALIZATION-COVERAGE.ps1',
    'VERIFY-PERFORMANCE.ps1',
    'VERIFY-CATALOG-PLUGIN-TRUST-V5.ps1',
    'VERIFY-ENTERPRISE.ps1',
    'VERIFY-ENTERPRISE-GOVERNANCE.ps1',
    'VERIFY-NO-SIGNING-SECRETS.ps1'
)
$platformPolicies = @{
    'win10-22h2' = [pscustomobject]@{ DisplayVersion='22H2'; Build='19045' }
    'win11-previous' = [pscustomobject]@{ DisplayVersion='24H2'; Build='26100' }
    'win11-current' = [pscustomobject]@{ DisplayVersion='25H2'; Build='26200' }
}

function ConvertTo-ClientVmMarkdownText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "" }
    return ([string]$Value).Replace("|", "\|").Replace("`r", " ").Replace("`n", " ").Trim()
}

function Get-ClientVmOptionalValue {
    param([AllowNull()][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [AllowNull()][object]$Default = '')
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function ConvertTo-ClientVmSafeScalar {
    param([AllowNull()][object]$Value, [int]$MaximumLength = 256)
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Replace("`0", '').Replace("`r", ' ').Replace("`n", ' ').Trim()
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}

$resultsRoot = [IO.Path]::GetFullPath($ResultsDirectory)
if (-not (Test-Path -LiteralPath $resultsRoot -PathType Container)) { throw "VM result directory does not exist: $resultsRoot" }
if ((Get-Item -LiteralPath $resultsRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "VM result directory cannot be a reparse point." }

$expectedPlatformSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
if (@($ExpectedPlatforms).Count -eq 0) { throw 'At least one expected VM platform is required.' }
foreach ($platform in $ExpectedPlatforms) {
    if (-not $platformPolicies.ContainsKey([string]$platform) -or -not $expectedPlatformSet.Add([string]$platform)) {
        throw "Expected platform list is invalid or contains duplicates: $platform"
    }
}

$records = New-Object System.Collections.Generic.List[object]
$seenPlatforms = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($file in @(Get-ChildItem -LiteralPath $resultsRoot -Filter "*.vm-result.json" -File -Recurse -ErrorAction Stop)) {
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
    if ($file.Length -le 0 -or $file.Length -gt 1048576) { throw "VM result size is invalid: $($file.FullName)" }
    $record = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $platform = [string]$record.Platform
    if ([string]$record.SchemaVersion -ne '1.0' -or -not $expectedPlatformSet.Contains($platform) -or
        -not $seenPlatforms.Add($platform) -or [string]$record.Status -notin @("Passed", "Failed")) {
        throw "VM result schema is invalid: $($file.FullName)"
    }
    $expectedResultFileName = $platform + '.vm-result.json'
    if ([string]$file.Name -cne $expectedResultFileName) {
        throw "VM result filename does not match its platform: $($file.FullName)"
    }
    $policy = $platformPolicies[$platform]
    $commit = (ConvertTo-ClientVmSafeScalar $record.Commit 40).ToLowerInvariant()
    $completedAt = [DateTime]::MinValue
    if ($commit -notmatch '^[0-9a-f]{40}$' -or
        -not [DateTime]::TryParse([string]$record.CompletedAtUtc, [Globalization.CultureInfo]::InvariantCulture,
            ([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal), [ref]$completedAt)) {
        throw "VM result commit or completion time is invalid: $($file.FullName)"
    }
    $osIdentityVerified = (
        $record.OsIdentityVerified -is [bool] -and
        [bool]$record.OsIdentityVerified -and
        [string]$record.OsDisplayVersion -eq [string]$policy.DisplayVersion -and
        [string]$record.OsBuild -eq [string]$policy.Build -and
        [string]$record.ExpectedOsDisplayVersion -eq [string]$policy.DisplayVersion -and
        [string]$record.ExpectedOsBuild -eq [string]$policy.Build -and
        [int]$record.OsUbr -ge 0
    )
    $testsByName = @{}
    $safeTests = New-Object System.Collections.Generic.List[object]
    foreach ($test in @($record.Tests)) {
        $name = ConvertTo-ClientVmSafeScalar $test.Name 128
        $exitCodeValue = $test.ExitCode
        $testStatus = ConvertTo-ClientVmSafeScalar $test.Status 16
        if ($name -notin $requiredTestNames -or $testsByName.ContainsKey($name)) {
            throw "VM result contains an unknown or duplicate test: $name"
        }
        if ($exitCodeValue -isnot [int] -and $exitCodeValue -isnot [long]) {
            throw "VM result contains a non-integer test exit code: $name"
        }
        if ($testStatus -notin @('Passed','Failed')) {
            throw "VM result contains an invalid test status: $name"
        }
        $testsByName[$name] = $true
        [void]$safeTests.Add([pscustomobject][ordered]@{
            Name = $name
            ExitCode = [int]$exitCodeValue
            Status = $testStatus
        })
    }
    $allTestsPassed = $true
    foreach ($requiredName in $requiredTestNames) {
        $safeTest = @($safeTests | Where-Object { [string]$_.Name -eq $requiredName } | Select-Object -First 1)
        if ($safeTest.Count -ne 1 -or [int]$safeTest[0].ExitCode -ne 0 -or [string]$safeTest[0].Status -ne 'Passed') {
            $allTestsPassed = $false
        }
    }
    $computedStatus = if ($osIdentityVerified -and $allTestsPassed) { 'Passed' } else { 'Failed' }
    if ([string]$record.Status -ne $computedStatus) {
        throw "VM result status is inconsistent with OS identity or test exits: $($file.FullName)"
    }
    [void]$records.Add([pscustomobject][ordered]@{
        SchemaVersion = '1.0'
        Platform = $platform
        Status = $computedStatus
        OsCaption = ConvertTo-ClientVmSafeScalar $record.OsCaption 160
        OsBuild = [string]$record.OsBuild
        OsUbr = [int]$record.OsUbr
        OsDisplayVersion = [string]$record.OsDisplayVersion
        ExpectedOsBuild = [string]$policy.Build
        ExpectedOsDisplayVersion = [string]$policy.DisplayVersion
        OsIdentityVerified = [bool]$osIdentityVerified
        PowerShell = ConvertTo-ClientVmSafeScalar $record.PowerShell 40
        Commit = $commit
        CompletedAtUtc = $completedAt.ToUniversalTime().ToString('o')
        ResultFileName = $expectedResultFileName
        ResultSha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
        ResultBytes = [int64]$file.Length
        Tests = @($safeTests.ToArray())
    })
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($platform in $ExpectedPlatforms) {
    $record = @($records | Where-Object { [string]$_.Platform -eq $platform } | Select-Object -Last 1)
    if ($record.Count -eq 0) {
        $policy = $platformPolicies[[string]$platform]
        [void]$rows.Add([pscustomobject][ordered]@{
            SchemaVersion='1.0'; Platform=$platform; Status="Missing"; OsCaption=""; OsBuild=""; OsUbr=0; OsDisplayVersion=""
            ExpectedOsBuild=[string]$policy.Build; ExpectedOsDisplayVersion=[string]$policy.DisplayVersion; OsIdentityVerified=$false
            PowerShell=""; Commit=""; CompletedAtUtc=""; ResultFileName=""; ResultSha256=""; ResultBytes=0; Tests=@()
        })
    } else {
        [void]$rows.Add($record[0])
    }
}

$sourceCommits = @($records | ForEach-Object { [string]$_.Commit } | Select-Object -Unique)
if ($sourceCommits.Count -gt 1) { throw 'VM results do not refer to the same source commit.' }

$passed = @($rows | Where-Object { [string]$_.Status -eq "Passed" }).Count
$failed = @($rows | Where-Object { [string]$_.Status -eq "Failed" }).Count
$missing = @($rows | Where-Object { [string]$_.Status -eq "Missing" }).Count
$summary = [pscustomobject][ordered]@{
    SchemaVersion = "1.0"
    GeneratedAtUtc = [DateTime]::UtcNow.ToString("o")
    Generator = [pscustomobject][ordered]@{
        Name = [IO.Path]::GetFileName($PSCommandPath)
        Sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToUpperInvariant()
        PowerShell = [string]$PSVersionTable.PSVersion
    }
    Automation = [pscustomobject][ordered]@{
        Repository = ConvertTo-ClientVmSafeScalar $Repository 200
        WorkflowName = ConvertTo-ClientVmSafeScalar $WorkflowName 160
        WorkflowRunId = ConvertTo-ClientVmSafeScalar $WorkflowRunId 64
        WorkflowRunAttempt = [Math]::Max(0, $WorkflowRunAttempt)
    }
    TestManifest = @($requiredTestNames | ForEach-Object {
        [pscustomobject][ordered]@{ Name = $_; ExpectedExitCode = 0; ExpectedStatus = 'Passed' }
    })
    PlatformManifest = @($ExpectedPlatforms | ForEach-Object {
        $policy = $platformPolicies[[string]$_]
        [pscustomobject][ordered]@{
            Platform = [string]$_
            ExpectedOsDisplayVersion = [string]$policy.DisplayVersion
            ExpectedOsBuild = [string]$policy.Build
        }
    })
    ExpectedPlatformCount = $ExpectedPlatforms.Count
    ResultCount = $records.Count
    PassedCount = $passed
    FailedCount = $failed
    MissingCount = $missing
    Status = if ($failed -eq 0 -and $missing -eq 0) { "Passed" } else { "IncompleteOrFailed" }
    SourceCommit = if ($sourceCommits.Count -eq 1) { $sourceCommits[0] } else { '' }
    Results = @($rows.ToArray())
}

$markdown = New-Object System.Collections.Generic.List[string]
[void]$markdown.Add("# Windows client VM test summary")
[void]$markdown.Add("")
[void]$markdown.Add("Generated: $($summary.GeneratedAtUtc)")
[void]$markdown.Add("")
[void]$markdown.Add("| Platform | Status | Windows | Display version | Build.UBR | PowerShell | Commit |")
[void]$markdown.Add("|---|---:|---|---|---|---|---|")
foreach ($row in $rows) {
    [void]$markdown.Add(("| {0} | {1} | {2} | {3} | {4}.{5} | {6} | {7} |" -f `
        (ConvertTo-ClientVmMarkdownText $row.Platform),
        (ConvertTo-ClientVmMarkdownText $row.Status),
        (ConvertTo-ClientVmMarkdownText $row.OsCaption),
        (ConvertTo-ClientVmMarkdownText (Get-ClientVmOptionalValue -Object $row -Name 'OsDisplayVersion')),
        (ConvertTo-ClientVmMarkdownText $row.OsBuild),
        (ConvertTo-ClientVmMarkdownText (Get-ClientVmOptionalValue -Object $row -Name 'OsUbr' -Default 0)),
        (ConvertTo-ClientVmMarkdownText $row.PowerShell),
        (ConvertTo-ClientVmMarkdownText $row.Commit)))
}
[void]$markdown.Add("")
[void]$markdown.Add(("Passed: **{0}**; Failed: **{1}**; Missing: **{2}**" -f $passed,$failed,$missing))
[void]$markdown.Add("")
[void]$markdown.Add("This artifact records automated compatibility evidence. It is not a warranty and does not replace review of security findings.")

if ([string]::IsNullOrWhiteSpace($JsonOutputPath)) { $JsonOutputPath = Join-Path $resultsRoot "client-vm-summary.json" }
if ([string]::IsNullOrWhiteSpace($MarkdownOutputPath)) { $MarkdownOutputPath = Join-Path $resultsRoot "client-vm-summary.md" }
$jsonFull = [IO.Path]::GetFullPath($JsonOutputPath)
$markdownFull = [IO.Path]::GetFullPath($MarkdownOutputPath)
foreach ($outputPath in @($jsonFull,$markdownFull)) {
    $parent = Split-Path -Parent $outputPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
}
[IO.File]::WriteAllText($jsonFull, ($summary | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllLines($markdownFull, @($markdown.ToArray()), (New-Object Text.UTF8Encoding($false)))

[pscustomobject][ordered]@{
    JsonPath = $jsonFull
    MarkdownPath = $markdownFull
    Status = $summary.Status
    PassedCount = $passed
    FailedCount = $failed
    MissingCount = $missing
}
