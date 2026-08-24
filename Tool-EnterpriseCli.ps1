[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("FleetExport", "ServerStatus", "ClientSnapshot")]
    [string]$Action,

    [string]$EnterpriseRoot = "",
    [string]$OutputDirectory = "",
    [ValidateSet("Json", "Csv", "Html", "Pdf")][string[]]$Formats = @("Json", "Csv", "Html"),
    [string[]]$ClientId = @(),
    [ValidateRange(0, 876000)][int]$MaximumClientAgeHours = 0,
    [ValidateRange(1, 876000)][int]$StaleAfterHours = 72,
    [switch]$IncludeSensitive
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Write-ToolEnterpriseCliResult {
    param([Parameter(Mandatory = $true)][object]$Value)
    [Console]::Out.WriteLine(($Value | ConvertTo-Json -Depth 12 -Compress))
}

$previousRoot = [string]$env:TOOL_ENTERPRISE_ROOT
try {
    if (-not [string]::IsNullOrWhiteSpace($EnterpriseRoot)) {
        $env:TOOL_ENTERPRISE_ROOT = [IO.Path]::GetFullPath($EnterpriseRoot)
    }

    $enterpriseModule = Join-Path $PSScriptRoot "Tool-Enterprise.ps1"
    if (-not (Test-Path -LiteralPath $enterpriseModule -PathType Leaf)) { throw "Tool-Enterprise.ps1 is missing." }
    . $enterpriseModule

    switch ($Action) {
        "FleetExport" {
            if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
                $OutputDirectory = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "ThanhViet-Tool-Kiem-Tra\enterprise-exports"
            }
            $result = Export-ToolEnterpriseFleetReport `
                -DestinationDirectory $OutputDirectory `
                -Formats $Formats `
                -RedactSensitive:(-not $IncludeSensitive) `
                -ClientId $ClientId `
                -MaximumClientAgeHours $MaximumClientAgeHours `
                -StaleAfterHours $StaleAfterHours
            Write-ToolEnterpriseCliResult ([pscustomobject][ordered]@{
                Success = $true
                Action = $Action
                Result = $result
            })
        }
        "ServerStatus" {
            $clients = @(Get-ToolEnterpriseServerClients)
            $stale = @($clients | Where-Object { (Get-ToolEnterpriseClientAgeHours -LastSeenUtc $_.LastSeenUtc) -gt $StaleAfterHours }).Count
            Write-ToolEnterpriseCliResult ([pscustomobject][ordered]@{
                Success = $true
                Action = $Action
                Metadata = Get-ToolEnterpriseMetadata
                ClientCount = $clients.Count
                StaleClientCount = $stale
                StaleAfterHours = $StaleAfterHours
                SensitiveDataIncluded = $false
            })
        }
        "ClientSnapshot" {
            $config = Get-ToolEnterpriseClientConfig
            if (-not $config -or [string]::IsNullOrWhiteSpace([string]$config.ClientId)) {
                throw "Enterprise client is not configured. Pair it through the administrative UI first."
            }
            $snapshot = Get-ToolEnterpriseLicenseSnapshot -ClientId ([string]$config.ClientId)
            if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
                $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) "ThanhViet-Enterprise-Snapshots"
            }
            $fullOutput = [IO.Path]::GetFullPath($OutputDirectory)
            if (-not (Test-Path -LiteralPath $fullOutput -PathType Container)) { New-Item -ItemType Directory -Path $fullOutput -Force | Out-Null }
            if (Test-ToolEnterpriseReparsePoint -Path $fullOutput) { throw "Snapshot output directory cannot be a reparse point." }
            $snapshotPath = Join-Path $fullOutput ("enterprise-snapshot-" + [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmssfff") + ".json")
            [IO.File]::WriteAllText($snapshotPath, ($snapshot | ConvertTo-Json -Depth 14), (New-Object Text.UTF8Encoding($false)))
            Write-ToolEnterpriseCliResult ([pscustomobject][ordered]@{
                Success = $true
                Action = $Action
                SnapshotPath = $snapshotPath
                FullProductKeysIncluded = $false
            })
        }
    }
    exit 0
} catch {
    Write-ToolEnterpriseCliResult ([pscustomobject][ordered]@{
        Success = $false
        Action = $Action
        Error = [string]$_.Exception.Message
    })
    exit 1
} finally {
    $env:TOOL_ENTERPRISE_ROOT = $previousRoot
}
