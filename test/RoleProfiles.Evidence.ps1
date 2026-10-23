$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('VLS-RoleEvidence-'+[guid]::NewGuid().ToString('N'))
$previousEnterpriseRoot=[string]$env:TOOL_ENTERPRISE_ROOT
$previousOffline=[string]$env:TOOL_OFFLINE_MODE
$checks=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:checks++}
try {
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    $env:TOOL_ENTERPRISE_ROOT=Join-Path $fixture 'enterprise'
    $env:TOOL_OFFLINE_MODE='1'
    . (Join-Path $root 'Tool-Enterprise.ps1')
    . (Join-Path $root 'Tool-LicenseCompliance.ps1')

    $evidence=Join-Path $fixture 'invoice.docx'
    [IO.File]::WriteAllBytes($evidence,[Text.Encoding]::UTF8.GetBytes('offline-evidence-fixture'))
    $entitlement=Set-ToolLicenseEntitlement -ProductScope Windows -ProductName 'Windows 11 Pro' -Vendor 'Microsoft Windows' -LicenseModel Unknown -Metric Device -PurchasedQuantity 0 -Notes 'fixture'
    $document=Add-ToolLicenseEntitlementDocument -EntitlementId $entitlement.EntitlementId -Path $evidence -Kind Other
    $paths=Get-ToolLicenseCompliancePaths
    $stored=Join-Path $paths.Documents $document.StoredName

    Check (Test-Path -LiteralPath $stored -PathType Leaf) 'Evidence copy missing from shared compliance store'
    Check (Test-Path -LiteralPath $evidence -PathType Leaf) 'Source evidence must remain untouched'
    Check ([IO.Path]::GetExtension($stored) -eq '.docx') 'Evidence extension was not preserved'
    Check ((Get-FileHash -LiteralPath $stored -Algorithm SHA256).Hash -eq $document.Sha256) 'Stored evidence hash mismatch'
    Check ([string]$document.VerificationStatus -eq 'Attached') 'Imported evidence must not be auto-verified'
    Check ([IO.Path]::GetFullPath($stored).StartsWith([IO.Path]::GetFullPath($paths.Documents),[StringComparison]::OrdinalIgnoreCase)) 'Evidence escaped local compliance store'

    $updated=Set-ToolLicenseEntitlement -EntitlementId $entitlement.EntitlementId -ProductScope Windows -ProductName 'Windows 11 Pro' -Vendor 'Microsoft Windows' -LicenseModel Unknown -Metric Device -PurchasedQuantity 0 -Notes 'updated'
    Check (@($updated.Documents).Count -eq 1) 'Updating entitlement lost or duplicated evidence'

    $blocked=Join-Path $fixture 'blocked.exe'
    [IO.File]::WriteAllBytes($blocked,[byte[]](1,2,3))
    $blockedRejected=$false
    try {[void](Add-ToolLicenseEntitlementDocument -EntitlementId $entitlement.EntitlementId -Path $blocked -Kind Other)} catch {$blockedRejected=$true}
    Check $blockedRejected 'Unsupported executable evidence was accepted'

    Check (Remove-ToolLicenseEntitlementDocument -EntitlementId $entitlement.EntitlementId -DocumentId $document.DocumentId) 'Evidence removal returned false'
    Check (-not (Test-Path -LiteralPath $stored -PathType Leaf)) 'Removed evidence file reappeared'
    $after=Get-ToolLicenseEntitlements | Where-Object EntitlementId -eq $entitlement.EntitlementId
    Check (@($after.Documents).Count -eq 0) 'Removed evidence remained in current state'
    Check (Remove-ToolLicenseEntitlement -EntitlementId $entitlement.EntitlementId) 'Entitlement cleanup returned false'
    Check (@(Get-ToolLicenseEntitlements | Where-Object EntitlementId -eq $entitlement.EntitlementId).Count -eq 0) 'Removed entitlement reappeared'

    [pscustomobject]@{Passed=$true;Checks=$checks;Scope='Offline shared compliance store lifecycle'} | ConvertTo-Json -Compress
} finally {
    $env:TOOL_ENTERPRISE_ROOT=$previousEnterpriseRoot
    $env:TOOL_OFFLINE_MODE=$previousOffline
    $fullFixture=[IO.Path]::GetFullPath($fixture)
    $fullTemp=[IO.Path]::GetFullPath($env:TEMP)
    if($fullFixture.StartsWith($fullTemp,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $fullFixture)){
        Remove-Item -LiteralPath $fullFixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}
