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
    'Get-LicenseChannel',
    'Test-ApprovedKms',
    'Test-WindowsLicenseRemediationTarget',
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
        $script:ApprovedKmsServers = @('kms.corp.example')
        $expectedWindowsKms = [pscustomobject]@{
            ID='activation-a'; Name='Windows'; Description='VOLUME_KMSCLIENT';
            LicenseStatus=5; PartialProductKey='ABCDE'; KeyManagementServiceMachine='kms.bad.example'
        }
        $currentWindowsKms = [pscustomobject]@{
            ID='activation-a'; Name='Windows'; Description='VOLUME_KMSCLIENT';
            LicenseStatus=5; PartialProductKey='ABCDE'; KeyManagementServiceMachine='kms.bad.example'
        }
        $windowsTargetPass = Test-WindowsLicenseRemediationTarget `
            -TargetProduct $expectedWindowsKms -CurrentProducts @($currentWindowsKms)
        Assert-Check -Condition ([bool]$windowsTargetPass.Allowed) `
            -Message 'Unchanged selected Windows KMS target did not pass immediate revalidation.'

        $approvedWindowsKms = $currentWindowsKms.PSObject.Copy()
        $approvedWindowsKms.KeyManagementServiceMachine = 'kms.corp.example'
        $windowsApprovedBlocked = Test-WindowsLicenseRemediationTarget `
            -TargetProduct $expectedWindowsKms -CurrentProducts @($approvedWindowsKms)
        Assert-Check -Condition (-not [bool]$windowsApprovedBlocked.Allowed -and
            [string]$windowsApprovedBlocked.Reason -eq 'TargetNoLongerUnapprovedKms') `
            -Message 'A Windows target that became approved internal KMS was not blocked.'

        $changedWindowsKey = $currentWindowsKms.PSObject.Copy()
        $changedWindowsKey.PartialProductKey = 'VWXYZ'
        $windowsKeyChangedBlocked = Test-WindowsLicenseRemediationTarget `
            -TargetProduct $expectedWindowsKms -CurrentProducts @($changedWindowsKey)
        Assert-Check -Condition (-not [bool]$windowsKeyChangedBlocked.Allowed -and
            [string]$windowsKeyChangedBlocked.Reason -eq 'PartialProductKeyChanged') `
            -Message 'A Windows target whose partial key changed after consent was not blocked.'

        foreach ($missingExpectedPartialKey in @($null, '', '   ')) {
            $missingExpectedWindowsKey = $expectedWindowsKms.PSObject.Copy()
            $missingExpectedWindowsKey.PartialProductKey = $missingExpectedPartialKey
            $missingExpectedKeyBlocked = Test-WindowsLicenseRemediationTarget `
                -TargetProduct $missingExpectedWindowsKey -CurrentProducts @($currentWindowsKms)
            Assert-Check -Condition (-not [bool]$missingExpectedKeyBlocked.Allowed -and
                [string]$missingExpectedKeyBlocked.Reason -eq 'MissingExpectedPartialProductKey') `
                -Message 'A Windows target without a consent-time partial key allowed removal of a newly observed key.'
        }

        $missingCurrentWindowsKey = $currentWindowsKms.PSObject.Copy()
        $missingCurrentWindowsKey.PartialProductKey = ''
        $missingBothKeysBlocked = Test-WindowsLicenseRemediationTarget `
            -TargetProduct $missingExpectedWindowsKey -CurrentProducts @($missingCurrentWindowsKey)
        Assert-Check -Condition (-not [bool]$missingBothKeysBlocked.Allowed -and
            [string]$missingBothKeysBlocked.Reason -eq 'MissingExpectedPartialProductKey') `
            -Message 'A Windows target with no partial key in either snapshot remained eligible for key removal.'

        $missingCurrentKeyBlocked = Test-WindowsLicenseRemediationTarget `
            -TargetProduct $expectedWindowsKms -CurrentProducts @($missingCurrentWindowsKey)
        Assert-Check -Condition (-not [bool]$missingCurrentKeyBlocked.Allowed -and
            [string]$missingCurrentKeyBlocked.Reason -eq 'PartialProductKeyChanged') `
            -Message 'A Windows target whose key disappeared after consent remained eligible for key removal.'

        $normalizedWindowsKey = $expectedWindowsKms.PSObject.Copy()
        $normalizedWindowsKey.PartialProductKey = ' abcde '
        $normalizedKeyAllowed = Test-WindowsLicenseRemediationTarget `
            -TargetProduct $normalizedWindowsKey -CurrentProducts @($currentWindowsKms)
        Assert-Check -Condition ([bool]$normalizedKeyAllowed.Allowed) `
            -Message 'Partial-key revalidation rejected an unchanged key after case and whitespace normalization.'

        $expectedNonGenuine = [pscustomobject]@{
            ID='activation-b'; Name='Windows'; Description='RETAIL'; LicenseStatus=4;
            PartialProductKey='12345'; KeyManagementServiceMachine=''
        }
        $currentGenuine = $expectedNonGenuine.PSObject.Copy()
        $currentGenuine.LicenseStatus = 1
        $windowsGenuineBlocked = Test-WindowsLicenseRemediationTarget `
            -TargetProduct $expectedNonGenuine -CurrentProducts @($currentGenuine)
        Assert-Check -Condition (-not [bool]$windowsGenuineBlocked.Allowed -and
            [string]$windowsGenuineBlocked.Reason -eq 'TargetNoLongerNonGenuine') `
            -Message 'A Windows target that became genuine after consent was not blocked.'

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

        # Simulate a process/UAC interruption without invoking any operating-system
        # mutation.  An interrupted attempt must remain explicitly retryable, the
        # retry must increment the attempt counter, and a terminal success must not
        # be reopenable by stale UI or broker output.
        $interrupted = New-RemediationStateRecord -CandidateId 'interrupted-attempt'
        $interrupted = Set-RemediationStateRecord -Record $interrupted -State Running
        $interrupted = Set-RemediationStateRecord -Record $interrupted -State RetryableFailure `
            -ErrorCode 'OperationInterrupted' -ErrorDetail 'Fixture process ended before post-check.'
        Assert-Check -Condition ([string]$interrupted.State -eq 'RetryableFailure' -and
            [bool]$interrupted.RetryAllowed -and [int]$interrupted.AttemptCount -eq 1 -and
            [string]$interrupted.LastErrorCode -eq 'OperationInterrupted') `
            -Message 'Interrupted remediation was not preserved as an explicit retryable failure.'
        $interrupted = Set-RemediationStateRecord -Record $interrupted -State Running
        Assert-Check -Condition ([string]$interrupted.State -eq 'Running' -and
            [int]$interrupted.AttemptCount -eq 2 -and
            [string]::IsNullOrWhiteSpace([string]$interrupted.LastErrorCode)) `
            -Message 'Retry after interruption did not start a new cleanly recorded attempt.'
        $interrupted = Resolve-RemediationPostCheckState -Record $interrupted `
            -DirectCrackEvidenceRemaining:$false -ApplicationPresent:$true `
            -OfficialLicenseState 'Unactivated' -ArtifactCleanupCompleted:$true
        $terminalTransitionBlocked = $false
        try {
            [void](Set-RemediationStateRecord -Record $interrupted -State Running)
        } catch {
            $terminalTransitionBlocked = ([string]$_.Exception.Message -match 'Invalid remediation state transition')
        }
        Assert-Check -Condition ([string]$interrupted.State -eq 'VerifiedClean' -and
            -not [bool]$interrupted.RetryAllowed -and [int]$interrupted.AttemptCount -eq 2 -and
            $terminalTransitionBlocked) `
            -Message 'A completed retry could be reopened or did not retain its attempt history.'

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
    $windowsKmsOverrideTargetAst = @(Get-FunctionAstByName -Ast $cleanupAst -Name 'Test-WindowsKmsOverrideRemediationTarget')

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
    Assert-Check -Condition ($deepCandidatesAst.Count -eq 1 -and
        $deepCandidatesAst[0].Extent.Text -match "RegistryValueName 'KeyManagementServiceName'" -and
        $deepCandidatesAst[0].Extent.Text -match 'ExpectedRegistryValue\s+[$]server') `
        -Message 'Windows KMS override candidate does not bind the server value observed at selection time.'
    Assert-Check -Condition ($windowsKmsOverrideTargetAst.Count -eq 1 -and
        $windowsKmsOverrideTargetAst[0].Extent.Text -match 'KmsOverrideChanged' -and
        $windowsKmsOverrideTargetAst[0].Extent.Text -match 'ApprovedInternalKms' -and
        $windowsKmsOverrideTargetAst[0].Extent.Text -match 'Get-ItemProperty') `
        -Message 'Windows KMS override lacks an immediate identity/approved-server revalidation helper.'
    Assert-Check -Condition ($deepCleanupAst.Count -eq 1 -and
        $deepCleanupAst[0].Extent.Text -notmatch 'SppNoGenTicketPolicy') `
        -Message 'Deep cleanup still contains an automatic NoGenTicket policy-removal branch.'

    if ($deepCleanupAst.Count -eq 1) {
        $deepCleanupText = [string]$deepCleanupAst[0].Extent.Text
        Assert-Check -Condition ($deepCleanupText -match '(?s)if\s*\(\s*-not\s*\(Is-Admin\)\s*\).+?SystemChangeCount=0.+?SystemChangeApplied=\$false.+?return') `
            -Message 'Deep cleanup does not fail closed before work when elevation is unavailable.'
        Assert-Check -Condition ($deepCleanupText -match '(?s)if\s*\(\s*-not\s+\$restoreBundleReady\s*\).+?backupRequiredBlocked.+?SystemChangeCount=0.+?SystemChangeApplied=\$false.+?return') `
            -Message 'Deep cleanup can continue when the authenticated restore bundle is incomplete.'

        $backupGateRelativeOffset = $deepCleanupText.IndexOf('if (-not $restoreBundleReady)', [StringComparison]::Ordinal)
        $systemMutationNames = @(
            'Stop-Process','Stop-Service','Set-Service','Start-Service',
            'Remove-ItemProperty','Remove-MpPreference','Remove-CompatibleScheduledTask',
            'Remove-AppxPackage','Start-Process','Run-SlmgrActionText'
        )
        $preBackupSystemMutations = @($deepCleanupAst[0].FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            [string]$node.GetCommandName() -in $systemMutationNames
        }, $true) | Where-Object {
            ([int]$_.Extent.StartOffset - [int]$deepCleanupAst[0].Extent.StartOffset) -lt $backupGateRelativeOffset
        })
        Assert-Check -Condition ($backupGateRelativeOffset -ge 0 -and $preBackupSystemMutations.Count -eq 0) `
            -Message 'A system mutator can run before the authenticated restore-bundle gate.'

        $kmsRevalidationCalls = @($deepCleanupAst[0].FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            [string]$node.GetCommandName() -eq 'Test-WindowsKmsOverrideRemediationTarget'
        }, $true))
        $kmsBackupCalls = @($deepCleanupAst[0].FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            [string]$node.GetCommandName() -eq 'Backup-RegKeyV35'
        }, $true))
        $kmsRemovalCalls = @($deepCleanupAst[0].FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            [string]$node.GetCommandName() -eq 'Remove-ItemProperty'
        }, $true))
        Assert-Check -Condition ($kmsRevalidationCalls.Count -ge 2 -and
            $kmsBackupCalls.Count -ge 1 -and $kmsRemovalCalls.Count -ge 1 -and
            [int]$kmsRevalidationCalls[0].Extent.StartOffset -lt [int]$kmsBackupCalls[0].Extent.StartOffset -and
            [int]$kmsRevalidationCalls[-1].Extent.StartOffset -lt [int]$kmsRemovalCalls[0].Extent.StartOffset) `
            -Message 'Windows KMS override is not revalidated both before backup and immediately before mutation.'

        if ($windowsKmsOverrideTargetAst.Count -eq 1) {
            try {
                $kmsGuardResults = & {
                    param([string]$GuardBody)
                    $script:fixtureKmsServer = 'kms.bad.example'
                    function Get-ItemProperty {
                        param($LiteralPath,$ErrorAction)
                        return [pscustomobject]@{ KeyManagementServiceName=$script:fixtureKmsServer }
                    }
                    function Test-ApprovedKms { param([string]$Server) return [bool]($Server -eq 'kms.corp.example') }
                    Invoke-Expression ('function Test-WindowsKmsOverrideRemediationTarget ' + $GuardBody)
                    $candidate = [pscustomobject]@{
                        Kind='KmsOverride'; Provider='WindowsSPP';
                        RegistryValueName='KeyManagementServiceName';
                        Location='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform';
                        ExpectedRegistryValue='kms.bad.example'
                    }
                    $unchanged = Test-WindowsKmsOverrideRemediationTarget -Candidate $candidate
                    $script:fixtureKmsServer = 'kms.changed.example'
                    $changed = Test-WindowsKmsOverrideRemediationTarget -Candidate $candidate
                    $script:fixtureKmsServer = 'kms.corp.example'
                    $candidate.ExpectedRegistryValue = 'kms.corp.example'
                    $approved = Test-WindowsKmsOverrideRemediationTarget -Candidate $candidate
                    $script:fixtureKmsServer = ''
                    $absent = Test-WindowsKmsOverrideRemediationTarget -Candidate $candidate
                    return [pscustomobject]@{ Unchanged=$unchanged; Changed=$changed; Approved=$approved; Absent=$absent }
                } $windowsKmsOverrideTargetAst[0].Body.Extent.Text

                Assert-Check -Condition ([bool]$kmsGuardResults.Unchanged.Allowed -and
                    -not [bool]$kmsGuardResults.Changed.Allowed -and
                    [string]$kmsGuardResults.Changed.Reason -eq 'KmsOverrideChanged' -and
                    -not [bool]$kmsGuardResults.Approved.Allowed -and
                    [string]$kmsGuardResults.Approved.Reason -eq 'ApprovedInternalKms' -and
                    [bool]$kmsGuardResults.Absent.AlreadyClean) `
                    -Message 'Windows KMS override revalidation does not fail closed for changed/approved/absent fixtures.'
            } catch {
                Add-CheckFailure ('Windows KMS override guard fixture raised an exception: ' + $_.Exception.Message)
            }
        }

        try {
            $nonAdminDeepResult = & {
                param([string]$DeepCleanupBody)
                $script:fixtureMutationCount = 0
                function Register-FixtureMutation {
                    $script:fixtureMutationCount++
                    throw 'A deep-cleanup mutator was reached by the non-admin fixture.'
                }
                function Is-Admin { return $false }
                function Get-CleanupText { param([string]$Key, [object[]]$Arguments = @()) return $Key }
                function Ensure-Dir { param($Path) Register-FixtureMutation }
                function Set-ProtectedBackupAcl { param($Path) Register-FixtureMutation }
                function Copy-Item { param($LiteralPath,$Destination,$Force,$Recurse,$ErrorAction) Register-FixtureMutation }
                function Move-Item { param($LiteralPath,$Destination,$Force) Register-FixtureMutation }
                function Remove-Item { param($LiteralPath,$Force,$Recurse,$ErrorAction) Register-FixtureMutation }
                function Remove-ItemProperty { param($LiteralPath,$Name,$Force,$ErrorAction) Register-FixtureMutation }
                function Stop-Process { param($Id,$Name,$Force,$ErrorAction) Register-FixtureMutation }
                function Stop-Service { param($Name,$Force,$ErrorAction) Register-FixtureMutation }
                function Set-Service { param($Name,$StartupType,$ErrorAction) Register-FixtureMutation }
                function Disable-ScheduledTask { param($TaskName,$TaskPath,$ErrorAction) Register-FixtureMutation }
                function Remove-MpPreference { param($ExclusionPath,$ErrorAction) Register-FixtureMutation }
                function Start-Process { param($FilePath,$ArgumentList,$Wait,$PassThru,$WindowStyle,$ErrorAction) Register-FixtureMutation }
                function Remove-AppxPackage { param($Package,$AllUsers,$ErrorAction) Register-FixtureMutation }

                Invoke-Expression ('function Invoke-DeepCleanupV35 ' + $DeepCleanupBody)
                $fixtureCandidate = [pscustomobject]@{ Id='fixture'; Type='File'; Kind='HookFile'; Name='fixture'; Location='C:\Fixture\hook.dll' }
                $result = Invoke-DeepCleanupV35 -Candidates @($fixtureCandidate) -SelectedIds @('fixture')
                return [pscustomobject]@{
                    MutationCount = [int]$script:fixtureMutationCount
                    Result = $result
                }
            } $deepCleanupAst[0].Body.Extent.Text

            Assert-Check -Condition ([int]$nonAdminDeepResult.MutationCount -eq 0 -and
                -not [bool]$nonAdminDeepResult.Result.SystemChangeApplied -and
                [int]$nonAdminDeepResult.Result.SystemChangeCount -eq 0 -and
                [int]$nonAdminDeepResult.Result.SelectedCount -eq 0 -and
                [string]::IsNullOrWhiteSpace([string]$nonAdminDeepResult.Result.BackupDirectory)) `
                -Message 'Non-admin/UAC-denied deep cleanup reached a mutator or reported a partial change.'
        } catch {
            Add-CheckFailure ('Non-admin/UAC-denied deep-cleanup fixture raised an exception: ' + $_.Exception.Message)
        }
    }

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
        $windowsKeyMutationLoops = @($invokeAst[0].FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.ForEachStatementAst] -and
            $node.Body.Extent.Text -match "Invoke-SlmgrCommand\s+-SlmgrArguments\s+@\('/upk',\s*[$]activationId\)"
        }, $true))
        Assert-Check -Condition ($windowsKeyMutationLoops.Count -eq 1 -and
            $windowsKeyMutationLoops[0].Body.Extent.Text -match '(?s)Get-WindowsLicenseProducts.+?Test-WindowsLicenseRemediationTarget.+?Invoke-SlmgrCommand\s+-SlmgrArguments\s+@\(''/upk'',\s*[$]activationId\)') `
            -Message 'Windows /upk does not immediately re-probe and revalidate the exact selected target.'

        # Exercise the non-admin branch with every mutating command shadowed by a
        # throwing fixture.  This is deliberately behavioral: even if a future
        # refactor moves code around, loss/denial of UAC must still return before
        # touching services, tasks, keys, Office, or restore points.
        try {
            $nonAdminResult = & {
                param(
                    [string]$InvokeBody,
                    [string]$PathKeyBody,
                    [string]$TargetIdentityBody,
                    [string]$HostIdentityBody,
                    [string]$NewStateBody,
                    [string]$SetStateBody
                )
                $script:fixtureMutationCount = 0
                function Register-FixtureMutation {
                    $script:fixtureMutationCount++
                    throw 'A mutating command was reached by the non-admin fixture.'
                }
                function Is-Admin { return $false }
                function Get-CleanupText {
                    param([string]$Key, [object[]]$Arguments = @())
                    return $Key
                }
                function Checkpoint-Computer { param($Description,$RestorePointType) Register-FixtureMutation }
                function Stop-Process { param($Name,$Force,$ErrorAction) Register-FixtureMutation }
                function Stop-Service { param($Name,$Force,$ErrorAction) Register-FixtureMutation }
                function Set-Service { param($Name,$StartupType,$ErrorAction) Register-FixtureMutation }
                function Disable-ScheduledTask { param($TaskName,$TaskPath,$ErrorAction) Register-FixtureMutation }
                function Invoke-SlmgrCommand { param($SlmgrArguments) Register-FixtureMutation }
                function Invoke-OfficeOsppCommand { param($Path,$Arguments,$SuccessPattern) Register-FixtureMutation }

                Invoke-Expression ('function Get-OfficeKmsPathKey ' + $PathKeyBody)
                Invoke-Expression ('function Get-OfficeKmsTargetIdentity ' + $TargetIdentityBody)
                Invoke-Expression ('function Get-OfficeKmsHostOverrideIdentity ' + $HostIdentityBody)
                Invoke-Expression ('function New-RemediationStateRecord ' + $NewStateBody)
                Invoke-Expression ('function Set-RemediationStateRecord ' + $SetStateBody)
                Invoke-Expression ('function Invoke-Remediation ' + $InvokeBody)

                $officeFixture = [pscustomobject]@{
                    Path='C:\Fixture\OSPP.VBS'; SkuId='fixture-sku'; Last5='ABCDE'
                }
                $result = Invoke-Remediation -Products @() `
                    -Findings @([pscustomobject]@{ Type='Process'; Name='fixture-activator' }) `
                    -CleanupActivator -CleanupKmsConfiguration `
                    -WindowsProductsToRemove @([pscustomobject]@{ ID='fixture-activation-id' }) `
                    -OfficeEntries @($officeFixture) -OfficeHostOverridePaths @($officeFixture.Path)
                return [pscustomobject]@{
                    MutationCount = [int]$script:fixtureMutationCount
                    Result = $result
                }
            } $invokeAst[0].Body.Extent.Text `
                $functionAsts['Get-OfficeKmsPathKey'].Body.Extent.Text `
                $functionAsts['Get-OfficeKmsTargetIdentity'].Body.Extent.Text `
                $functionAsts['Get-OfficeKmsHostOverrideIdentity'].Body.Extent.Text `
                $functionAsts['New-RemediationStateRecord'].Body.Extent.Text `
                $functionAsts['Set-RemediationStateRecord'].Body.Extent.Text

            Assert-Check -Condition ([int]$nonAdminResult.MutationCount -eq 0 -and
                -not [bool]$nonAdminResult.Result.SystemChangeApplied -and
                [int]$nonAdminResult.Result.SystemChangeCount -eq 0 -and
                @($nonAdminResult.Result.RemediationStates).Count -eq 2 -and
                @($nonAdminResult.Result.RemediationStates | Where-Object {
                    [string]$_.State -ne 'RetryableFailure' -or
                    [string]$_.LastErrorCode -ne 'AdministratorRequired' -or
                    -not [bool]$_.RetryAllowed
                }).Count -eq 0) `
                -Message 'Non-admin/UAC-denied remediation reached a mutator or returned a non-retryable result.'
        } catch {
            Add-CheckFailure ('Non-admin/UAC-denied behavioral fixture raised an exception: ' + $_.Exception.Message)
        }
    } else {
        Add-CheckFailure 'Missing or duplicate Invoke-Remediation function.'
    }

    # The normal selected-item flow must never opt into the legacy broad
    # activator/KMS switches, and it must call the exact-key remediation only
    # after a protected backup directory has been produced.
    Assert-Check -Condition ($cleanupText -match '(?s)if\s*\(\$backupDirectory\)\s*\{.+?Invoke-Remediation.+?-CleanupActivator:\$false.+?-CleanupKmsConfiguration:\$false') `
        -Message 'Main remediation flow can enable broad activator/KMS cleanup or bypass the signed-backup gate.'

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
