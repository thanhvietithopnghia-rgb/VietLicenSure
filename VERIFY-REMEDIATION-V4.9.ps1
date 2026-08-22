[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]
$checkCount = 0

function Add-CheckFailure {
    param([Parameter(Mandatory = $true)][string]$Message)
    [void]$script:failures.Add($Message)
}

function Assert-Check {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:checkCount++
    if (-not $Condition) { Add-CheckFailure -Message $Message }
}

function Get-FunctionAstByName {
    param(
        [Parameter(Mandatory = $true)]$Ast,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return @($Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        [string]::Equals($node.Name, $Name, [StringComparison]::OrdinalIgnoreCase)
    }, $true) | Select-Object -First 1)
}

$cleanupPath = Join-Path $root 'windows-license-compliance-cleanup.ps1'
if (-not (Test-Path -LiteralPath $cleanupPath -PathType Leaf)) {
    Add-CheckFailure 'Missing windows-license-compliance-cleanup.ps1.'
    $cleanupText = ''
    $cleanupAst = $null
} else {
    $tokens = $null
    $parseErrors = $null
    $cleanupAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $cleanupPath, [ref]$tokens, [ref]$parseErrors)
    $cleanupText = Get-Content -LiteralPath $cleanupPath -Raw -Encoding UTF8
    foreach ($parseError in @($parseErrors)) {
        Add-CheckFailure ("PowerShell parse error at {0}:{1}: {2}" -f
            $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message)
    }
}

$requiredFunctions = @(
    'Get-OfficeKmsPathKey',
    'Get-OfficeKmsTargetIdentity',
    'Get-OfficeKmsHostOverrideIdentity',
    'New-RemediationStateRecord',
    'Set-RemediationStateRecord',
    'Resolve-RemediationPostCheckState',
    'Get-OfficeLicenseProbeForPathBounded'
)
$functionAsts = @{}
if ($null -ne $cleanupAst) {
    foreach ($functionName in $requiredFunctions) {
        $match = @(Get-FunctionAstByName -Ast $cleanupAst -Name $functionName)
        Assert-Check -Condition ($match.Count -eq 1) -Message ("Missing or duplicate function: {0}." -f $functionName)
        if ($match.Count -eq 1) { $functionAsts[$functionName] = $match[0] }
    }
}

if ($failures.Count -eq 0) {
    foreach ($functionName in $requiredFunctions) {
        Invoke-Expression ([string]$functionAsts[$functionName].Extent.Text)
    }

    try {
        $osppPath = 'C:\Program Files\Microsoft Office\Office16\OSPP.VBS'
        $entryA = [pscustomobject]@{ Path=$osppPath; SkuId='SKU-A'; Last5='x4vq2' }
        $entryB = [pscustomobject]@{ Path=$osppPath; SkuId='SKU-A'; Last5='xqbr2' }
        $identityA = Get-OfficeKmsTargetIdentity -Entry $entryA
        $identityB = Get-OfficeKmsTargetIdentity -Entry $entryB
        Assert-Check -Condition ($identityA -match '^Provider=OfficeOSPP\|SKU=sku-a\|Last5=X4VQ2\|OSPP=') `
            -Message 'Office key identity is not Provider + SKU + Last5 + OSPP path.'
        Assert-Check -Condition (-not [string]::Equals($identityA, $identityB, [StringComparison]::OrdinalIgnoreCase)) `
            -Message 'Two Last5 values on one SKU were merged into one remediation target.'
        Assert-Check -Condition ([string]::IsNullOrWhiteSpace((Get-OfficeKmsTargetIdentity -Entry ([pscustomobject]@{
            Path=$osppPath; SkuId='SKU-A'; Last5=''
        })))) -Message 'Missing Last5 did not fail closed for exact Office key removal.'

        $hostIdentity = Get-OfficeKmsHostOverrideIdentity -Path $osppPath
        Assert-Check -Condition ($hostIdentity -match '^Provider=OfficeOSPP\|HostOverride\|OSPP=' -and
            $hostIdentity -notmatch '(?i)Last5|SKU=') `
            -Message 'Office host override identity still depends on SKU/Last5.'

        $requiredStates = @('Pending','Running','VerifiedClean','ApprovedInternalKMS','RetryableFailure','BlockedByPolicy','NeedsOfficeRepair')
        $record = New-RemediationStateRecord -CandidateId 'office-a' -Kind 'OfficeKmsLicense' `
            -Provider 'OfficeOSPP' -SkuId 'sku-a' -Last5 'X4VQ2' -OsppPathInstance $osppPath
        Assert-Check -Condition ([string]$record.State -eq 'Pending' -and [int]$record.AttemptCount -eq 0 -and
            [bool]$record.RetryAllowed -and $record.PSObject.Properties['LastErrorCode'] -and
            $record.PSObject.Properties['BlockCode']) -Message 'Initial remediation state lacks retry/error/block fields.'
        $record = Set-RemediationStateRecord -Record $record -State Running
        Assert-Check -Condition ([string]$record.State -eq 'Running' -and [int]$record.AttemptCount -eq 1) `
            -Message 'Pending -> Running did not record the first attempt.'
        $record = Resolve-RemediationPostCheckState -Record $record -DirectCrackEvidenceRemaining:$false `
            -ApplicationPresent:$true -OfficialLicenseState 'Unactivated' -ArtifactCleanupCompleted:$true
        Assert-Check -Condition ([string]$record.State -eq 'VerifiedClean' -and -not [bool]$record.RetryAllowed) `
            -Message 'Strict clean fixture did not become VerifiedClean.'

        $trial = New-RemediationStateRecord -CandidateId 'trial'
        $trial = Set-RemediationStateRecord -Record $trial -State Running
        $trial = Resolve-RemediationPostCheckState -Record $trial -DirectCrackEvidenceRemaining:$false `
            -ApplicationPresent:$true -OfficialLicenseState 'Trial'
        Assert-Check -Condition ([string]$trial.State -eq 'VerifiedClean') `
            -Message 'Official Trial state was not accepted by the strict clean gate.'

        $licensed = New-RemediationStateRecord -CandidateId 'licensed-unverified'
        $licensed = Set-RemediationStateRecord -Record $licensed -State Running
        $licensed = Resolve-RemediationPostCheckState -Record $licensed -DirectCrackEvidenceRemaining:$false `
            -ApplicationPresent:$true -OfficialLicenseState 'Licensed' -ArtifactCleanupCompleted:$true -AllowLicensedState:$true
        Assert-Check -Condition ([string]$licensed.State -eq 'VerifiedClean' -and -not [bool]$licensed.RetryAllowed) `
            -Message 'A preserved genuine Licensed state was not accepted after scoped cleanup.'

        $evidence = New-RemediationStateRecord -CandidateId 'evidence-remains'
        $evidence = Set-RemediationStateRecord -Record $evidence -State Running
        $evidence = Resolve-RemediationPostCheckState -Record $evidence -DirectCrackEvidenceRemaining:$true `
            -ApplicationPresent:$true -OfficialLicenseState 'Unactivated'
        Assert-Check -Condition ([string]$evidence.State -eq 'RetryableFailure' -and
            [string]$evidence.LastErrorCode -eq 'DirectEvidenceStillPresent') `
            -Message 'Direct crack evidence remaining was incorrectly marked clean.'

        $missingApp = New-RemediationStateRecord -CandidateId 'missing-app'
        $missingApp = Set-RemediationStateRecord -Record $missingApp -State Running
        $missingApp = Resolve-RemediationPostCheckState -Record $missingApp -DirectCrackEvidenceRemaining:$false `
            -ApplicationPresent:$false -OfficialLicenseState 'Unactivated'
        Assert-Check -Condition ([string]$missingApp.State -eq 'RetryableFailure' -and
            [string]$missingApp.LastErrorCode -eq 'ApplicationNotPresentAfterCleanup') `
            -Message 'An absent application was incorrectly marked VerifiedClean.'

        $uninstalledApp = New-RemediationStateRecord -CandidateId 'explicit-uninstall'
        $uninstalledApp = Set-RemediationStateRecord -Record $uninstalledApp -State Running
        $uninstalledApp = Resolve-RemediationPostCheckState -Record $uninstalledApp -DirectCrackEvidenceRemaining:$false `
            -ApplicationPresent:$false -OfficialLicenseState 'Removed' -ExpectedApplicationAbsent:$true -ArtifactCleanupCompleted:$true
        Assert-Check -Condition ([string]$uninstalledApp.State -eq 'VerifiedClean') `
            -Message 'Explicit complete-uninstall absence was not accepted as VerifiedClean.'

        $policy = New-RemediationStateRecord -CandidateId 'managed-policy'
        $policy = Set-RemediationStateRecord -Record $policy -State Running
        $policy = Resolve-RemediationPostCheckState -Record $policy -DirectCrackEvidenceRemaining:$true `
            -ApplicationPresent:$true -OfficialLicenseState 'Unverified' `
            -PolicyBlockCode 'ManagedNoGenTicketPolicy' -PolicyBlockDetail 'GroupPolicyOrMDM'
        Assert-Check -Condition ([string]$policy.State -eq 'BlockedByPolicy' -and -not [bool]$policy.RetryAllowed -and
            [string]$policy.BlockCode -eq 'ManagedNoGenTicketPolicy' -and [string]$policy.BlockDetail -eq 'GroupPolicyOrMDM') `
            -Message 'Managed policy fixture lacks the BlockedByPolicy diagnostic.'

        $volume = New-RemediationStateRecord -CandidateId 'volume-mondo'
        $volume = Set-RemediationStateRecord -Record $volume -State Running
        $volume = Resolve-RemediationPostCheckState -Record $volume -DirectCrackEvidenceRemaining:$true `
            -ApplicationPresent:$true -OfficialLicenseState 'Unverified' -VolumeRepairRequired:$true
        Assert-Check -Condition ([string]$volume.State -eq 'NeedsOfficeRepair' -and -not [bool]$volume.RetryAllowed -and
            [string]$volume.BlockCode -eq 'VolumeOrMondoRequiresOfficialRepair') `
            -Message 'Unresolved Volume/Mondo fixture did not require official Office repair.'

        $approved = New-RemediationStateRecord -CandidateId 'approved-kms'
        $approved = Set-RemediationStateRecord -Record $approved -State Running
        $approved = Resolve-RemediationPostCheckState -Record $approved -DirectCrackEvidenceRemaining:$true `
            -ApplicationPresent:$true -OfficialLicenseState 'Licensed' -ApprovedInternalKms:$true
        Assert-Check -Condition ([string]$approved.State -eq 'ApprovedInternalKMS' -and -not [bool]$approved.RetryAllowed) `
            -Message 'Approved internal KMS fixture was not preserved.'

        $observedStates = @($record.State, $trial.State, $licensed.State, $evidence.State,
            $missingApp.State, $policy.State, $volume.State, $approved.State, 'Pending', 'Running') | Select-Object -Unique
        Assert-Check -Condition (@($requiredStates | Where-Object { $observedStates -notcontains $_ }).Count -eq 0) `
            -Message 'The deterministic fixtures do not cover every required remediation state.'

        $script:probeAttemptCount = 0
        function Get-OfficeLicenseProbeForPath {
            param([string]$Path)
            $script:probeAttemptCount++
            return [pscustomobject]@{ Coverage='Partial'; Entries=@(); Path=$Path }
        }
        $boundedFailure = Get-OfficeLicenseProbeForPathBounded -Path $osppPath -MaximumAttempts 3 -DelayMilliseconds 0
        Assert-Check -Condition ([int]$boundedFailure.AttemptCount -eq 3 -and [int]$script:probeAttemptCount -eq 3) `
            -Message 'Bounded Office reprobe exceeded or skipped the three-attempt limit.'

        $script:probeAttemptCount = 0
        function Get-OfficeLicenseProbeForPath {
            param([string]$Path)
            $script:probeAttemptCount++
            $coverage = if ($script:probeAttemptCount -eq 2) { 'Complete' } else { 'Partial' }
            return [pscustomobject]@{ Coverage=$coverage; Entries=@([pscustomobject]@{ SkuId='sku-a' }); Path=$Path }
        }
        $boundedSuccess = Get-OfficeLicenseProbeForPathBounded -Path $osppPath -MaximumAttempts 3 -DelayMilliseconds 0
        Assert-Check -Condition ([string]$boundedSuccess.Coverage -eq 'Complete' -and
            [int]$boundedSuccess.AttemptCount -eq 2 -and [int]$script:probeAttemptCount -eq 2) `
            -Message 'Bounded Office reprobe did not stop at the first complete result.'
    } catch {
        Add-CheckFailure ('Behavioral remediation checks raised an exception: ' + $_.Exception.Message)
    }
}

if ($null -ne $cleanupAst) {
    $allCandidatesAst = @(Get-FunctionAstByName -Ast $cleanupAst -Name 'Get-AllCleanupCandidates')
    $deepCandidatesAst = @(Get-FunctionAstByName -Ast $cleanupAst -Name 'Get-DeepCleanupCandidates')
    $deepCleanupAst = @(Get-FunctionAstByName -Ast $cleanupAst -Name 'Invoke-DeepCleanupV35')
    $invokeAst = @(Get-FunctionAstByName -Ast $cleanupAst -Name 'Invoke-Remediation')

    Assert-Check -Condition ($allCandidatesAst.Count -eq 1 -and
        $allCandidatesAst[0].Extent.Text -match "Kind 'OfficeKmsHostOverride'" -and
        $allCandidatesAst[0].Extent.Text -match 'Get-OfficeKmsHostOverrideIdentity') `
        -Message 'No independent Office KMS host-override candidate is generated.'

    Assert-Check -Condition ($deepCandidatesAst.Count -eq 1 -and
        $deepCandidatesAst[0].Extent.Text -match 'ManagedNoGenTicketPolicy' -and
        $deepCandidatesAst[0].Extent.Text -match 'Type "Guidance"' -and
        $deepCandidatesAst[0].Extent.Text -match "InitialRemediationState 'BlockedByPolicy'" -and
        $deepCandidatesAst[0].Extent.Text -match 'GroupPolicyOrMDM') `
        -Message 'NoGenTicket is not represented as a managed GPO/MDM diagnostic.'
    Assert-Check -Condition ($deepCleanupAst.Count -eq 1 -and
        $deepCleanupAst[0].Extent.Text -notmatch 'SppNoGenTicketPolicy') `
        -Message 'Deep cleanup still contains an automatic NoGenTicket policy-removal branch.'

    if ($invokeAst.Count -eq 1) {
        $argumentStrings = @($invokeAst[0].FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
        }, $true))
        $unpkeyNodes = @($argumentStrings | Where-Object { [string]$_.Value -like '/unpkey:*' })
        $remhstNodes = @($argumentStrings | Where-Object { [string]$_.Value -eq '/remhst' })
        Assert-Check -Condition ($unpkeyNodes.Count -gt 0 -and $remhstNodes.Count -gt 0 -and
            [int]$unpkeyNodes[0].Extent.StartOffset -lt [int]$remhstNodes[0].Extent.StartOffset) `
            -Message 'Office host cleanup is not ordered after exact /unpkey removal attempts.'
        Assert-Check -Condition ($invokeAst[0].Extent.Text -match 'Get-OfficeLicenseProbeForPathBounded.+MaximumAttempts 3') `
            -Message 'Office remediation lacks a bounded three-attempt post-probe.'
    } else {
        Add-CheckFailure 'Missing or duplicate Invoke-Remediation function.'
    }

    $destructiveCommands = @($cleanupAst.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
        $name = [string]$node.GetCommandName()
        return $name -in @('Remove-Item','Remove-ItemProperty','Clear-Content','Set-Content')
    }, $true))
    foreach ($command in $destructiveCommands) {
        if ($command.Extent.Text -match '(?i)NoGenTicket|tokens\.dat|TokenStore') {
            Add-CheckFailure ('Forbidden policy/token-store mutation: ' + $command.Extent.Text)
        }
    }
    $checkCount++

    Assert-Check -Condition ($cleanupText -match 'remediationPostCheckPassed' -and
        $cleanupText -match 'ExpectedApplicationAbsent' -and
        $cleanupText -match 'AllowLicensedState' -and
        $cleanupText -match '-not \$DirectCrackEvidenceRemaining' -and
        $cleanupText -match '\$ApplicationPresent') `
        -Message 'Final readiness is not gated by the strict remediation post-check.'
}

$requiredLocalizationKeys = @(
    'cleanupReport.action.officeRefreshFailed',
    'cleanupReport.candidate.officeKmsHostOverride',
    'cleanupReport.candidate.officeKmsHostOverrideDetail',
    'cleanupReport.remediation.pending',
    'cleanupReport.remediation.running',
    'cleanupReport.remediation.verifiedClean',
    'cleanupReport.remediation.approvedInternalKms',
    'cleanupReport.remediation.retryableFailure',
    'cleanupReport.remediation.blockedByPolicy',
    'cleanupReport.remediation.needsOfficeRepair',
    'cleanupReport.remediation.artifactsRemovedLicenseUnverified',
    'cleanupReport.dryRun.action.removeOfficeKmsHost'
)
foreach ($jsonName in @('Tool-Strings.vi-VN.json','Tool-Strings.en-US.json')) {
    $jsonPath = Join-Path $root $jsonName
    if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf)) {
        Add-CheckFailure ("Missing localization file: {0}." -f $jsonName)
        continue
    }
    try {
        $json = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in $requiredLocalizationKeys) {
            $property = $json.PSObject.Properties[$key]
            Assert-Check -Condition ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) `
                -Message ("Missing localization key {0} in {1}." -f $key, $jsonName)
        }
    } catch {
        Add-CheckFailure ("Invalid localization JSON {0}: {1}" -f $jsonName, $_.Exception.Message)
    }
}

if ($failures.Count -gt 0) {
    Write-Host ("VERIFY-REMEDIATION-V4.9: FAIL ({0} issue(s), {1} checks)" -f $failures.Count, $checkCount) -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host (' - ' + $failure) -ForegroundColor Red }
    exit 1
}

Write-Host ("VERIFY-REMEDIATION-V4.9: OK ({0} checks)" -f $checkCount) -ForegroundColor Green
exit 0
