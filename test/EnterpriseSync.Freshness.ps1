param([string]$SourceDirectory = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
# Focused state-machine regression: actual production functions, isolated disk
# storage and synthetic agent observations; no host inventory, service or network.
$script:fixture = Join-Path ([IO.Path]::GetTempPath()) ('VLS-sync-' + [guid]::NewGuid().ToString('N'))
$script:paths = [pscustomobject]@{ServerClients="$fixture\clients";ServerReports="$fixture\reports";ServerJobs="$fixture\jobs";ServerResults="$fixture\results"}
foreach ($p in $paths.PSObject.Properties) { [void](New-Item -ItemType Directory -Path $p.Value -Force) }
$script:ToolEnterpriseSchemaVersion = '1.6'
$script:ToolEnterpriseToolVersion = '5.0'
$script:assetWrites = 0
function Initialize-ToolEnterpriseStorage { return $script:paths }
function ConvertTo-ToolEnterpriseSafeText($Value, [int]$MaximumLength) { return [string]$Value }
function Read-ToolEnterpriseJson([string]$Path) { if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }; return $null }
function Write-ToolEnterpriseJson([string]$Path, $Value) { [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false))) }
function Get-ToolEnterpriseSha256Hex([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-ToolEnterpriseSha256Bytes([byte[]]$Bytes) { $h=[Security.Cryptography.SHA256]::Create(); try { return ,$h.ComputeHash($Bytes) } finally { $h.Dispose() } }
function Write-ToolEnterpriseAudit { param($Scope,$Event,$Message,$Data) }
function Update-ToolEnterpriseAssetRegistryFromReport { param($Report); $script:assetWrites++; return [pscustomobject]@{Status='Missing';DeviceId='';AssetId='';CurrentAssignment=$null;HistoryCount=0} }
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceDirectory 'Tool-Enterprise.ps1'),[ref]$null,[ref]$errors)
if ($errors.Count) { throw ($errors -join '; ') }
$wanted=@('Get-ToolEnterpriseServerClientRecordPath','Get-ToolEnterpriseLicenseStateHash','Save-ToolEnterpriseServerReport','Get-ToolEnterpriseAssessmentStatus','Get-ToolEnterprisePendingJobPackage','ConvertTo-ToolEnterpriseAssessmentSummary','Save-ToolEnterpriseJobResult','Invoke-ToolEnterpriseReadOnlyAssessment','Invoke-ToolEnterpriseLicenseJob')
foreach($f in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    if($f.Name -in $wanted) { . ([scriptblock]::Create($f.Extent.Text)) }
}
$script:checks=0
function Assert-Sync([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message}; $script:checks++ }
$id=[guid]::NewGuid().ToString('N')
function New-Observation([int]$Minute,[string]$Key='AAAAA') {
    return [pscustomobject]@{ClientId=$id;CreatedAt=('2026-10-16T00:{0:00}:00Z' -f $Minute);ComputerName='SYNTHETIC';NetworkAddresses=@();WindowsLicenses=@([pscustomobject]@{ProductId='p';ApplicationId='a';Channel='Retail';PartialProductKey=$Key;LicenseStatusText='Licensed'});OfficeLicenses=@()}
}
function New-Result([string]$JobId,[int]$Minute,[string]$Hash='',[string]$Status='Completed') {
    $time='2026-10-16T00:{0:00}:00Z' -f $Minute
    return [pscustomobject]@{JobId=$JobId;Operation='InventoryOnly';Status=$Status;ExitCode=0;Message='fixture';ProductKeyLast5='';StartedAtUtc=$time;CompletedAtUtc=$time;ReportKind='';ReportSummary=$null;ReportGeneratedAtUtc=$time;ReportLicenseStateHash=$Hash}
}
function Get-Record { Read-ToolEnterpriseJson (Get-ToolEnterpriseServerClientRecordPath $id) }
function Set-Assessment($Result) {
    $Result.Operation='LicenseForensics'; $Result.ReportKind='LicenseForensics'
    $Result.ReportSummary=[pscustomobject]@{AccessDenied=$false;Overall='Review';RiskScore=1;RiskLevel='Low';HighCount=0;ReviewCount=1;NewFindingCount=0;ResolvedFindingCount=0}
    return $Result
}
$r=Save-ToolEnterpriseServerReport $id (New-Observation 10)
$latestHash=Get-ToolEnterpriseSha256Hex $r.LatestReportPath
$stateHash=$r.CurrentLicenseStateHash
[void](Save-ToolEnterpriseServerReport $id (New-Observation 9 'BBBBB'))
[void](Save-ToolEnterpriseServerReport $id (New-Observation 10 'BBBBB'))
$r=Get-Record
Assert-Sync ($r.InventoryRevision -eq 1 -and $r.WindowsLast5 -eq 'AAAAA') 'Delayed/duplicate inventory overwrote current state.'
Assert-Sync ((Get-ToolEnterpriseSha256Hex $r.LatestReportPath) -eq $latestHash -and $assetWrites -eq 1) 'Delayed report rewrote latest bytes or assets.'
Assert-Sync (@(Get-ChildItem -LiteralPath (Split-Path $r.LatestReportPath) -Filter '*.json').Count -eq 4) 'History observations were lost.'
$job=[guid]::NewGuid().ToString('N')
$jobDir=Join-Path $paths.ServerJobs $id
[void](New-Item -ItemType Directory -Path $jobDir)
Write-ToolEnterpriseJson (Join-Path $jobDir "$job.job") ([pscustomobject]@{JobId=$job})
$r.LastJobId=$job; $r.LastJobStatus='Queued'
Write-ToolEnterpriseJson (Get-ToolEnterpriseServerClientRecordPath $id) $r
$r=Save-ToolEnterpriseServerReport $id (New-Observation 11)
Assert-Sync ($r.SynchronizationStatus -eq 'PendingInventoryRefresh') 'Queued job was cleared by a pre-job report.'
$result=New-Result $job 12
[void](Save-ToolEnterpriseJobResult $id $result)
$r=Save-ToolEnterpriseServerReport $id (New-Observation 12)
Assert-Sync ($r.SynchronizationStatus -eq 'PendingInventoryRefresh') 'Equal-time inventory prematurely cleared Pending.'
$r=Save-ToolEnterpriseServerReport $id (New-Observation 13)
Assert-Sync ($r.SynchronizationStatus -eq 'Current') 'Post-job inventory did not become Current.'
[void](Save-ToolEnterpriseJobResult $id (New-Result ([guid]::NewGuid().ToString('N')) 11))
[void](Save-ToolEnterpriseJobResult $id $result)
$r=Get-Record
Assert-Sync ($r.SynchronizationStatus -eq 'Current' -and $r.LastJobId -eq $job -and ([datetimeoffset]$r.LastJobCompletedAtUtc).Minute -eq 12) 'Delayed/duplicate result regressed job state or watermark.'
$assessment=Set-Assessment (New-Result ([guid]::NewGuid().ToString('N')) 14 $stateHash 'ActionRequired')
[void](Save-ToolEnterpriseJobResult $id $assessment)
$r=Save-ToolEnterpriseServerReport $id (New-Observation 15)
Assert-Sync ((Get-ToolEnterpriseAssessmentStatus $r) -eq 'ActionRequired') 'Matching assessment binding was not preserved.'
[void](Save-ToolEnterpriseJobResult $id (New-Result ([guid]::NewGuid().ToString('N')) 16))
$r=Save-ToolEnterpriseServerReport $id (New-Observation 17)
Assert-Sync ((Get-ToolEnterpriseAssessmentStatus $r) -eq 'ActionRequired' -and $r.LastJobStatus -eq 'Completed') 'Unrelated job replaced assessment status.'
$r=Save-ToolEnterpriseServerReport $id (New-Observation 18 'BBBBB')
Assert-Sync ((Get-ToolEnterpriseAssessmentStatus $r) -eq 'Stale') 'Changed inventory did not invalidate assessment.'
$delayed=Set-Assessment (New-Result ([guid]::NewGuid().ToString('N')) 17 $stateHash)
[void](Save-ToolEnterpriseJobResult $id $delayed)
$r=Get-Record
Assert-Sync ((Get-ToolEnterpriseAssessmentStatus $r) -eq 'Stale' -and $r.LastAssessmentStateHash -eq $stateHash) 'Delayed assessment was rebound to server inventory.'
[void](Save-ToolEnterpriseJobResult $id $assessment)
$r=Get-Record
Assert-Sync (([datetimeoffset]$r.LastAssessmentGeneratedAtUtc).Minute -eq 17) 'Older assessment replaced newer assessment.'
$legacy=Set-Assessment (New-Result ([guid]::NewGuid().ToString('N')) 19)
[void](Save-ToolEnterpriseJobResult $id $legacy)
$r=Save-ToolEnterpriseServerReport $id (New-Observation 20 'BBBBB')
Assert-Sync ((Get-ToolEnterpriseAssessmentStatus $r) -eq 'Stale') 'Legacy assessment without binding was marked current.'
# Verify the job executor carries the agent binding unchanged, without launching scanners.
function Invoke-ToolEnterpriseReadOnlyAssessment { param($Operation,$JobId); return [pscustomobject]@{ReportKind=$Operation;ReportSummary=$assessment.ReportSummary;ReportGeneratedAtUtc='2026-10-16T00:14:00Z';ReportLicenseStateHash=$stateHash;AssessmentExitCode=0} }
function Get-ToolEnterpriseText { param($Key,$Arguments); return $Key }
$j=[pscustomobject]@{Operation='LicenseForensics';ProductKeyLast5='';ProductKey='';ExpiresAtUtc=[datetime]::UtcNow.AddHours(1).ToString('o');JobId=[guid]::NewGuid().ToString('N');ClientId=$id}
$out=Invoke-ToolEnterpriseLicenseJob -Job $j -AllowRemoteLicenseChanges $false
Assert-Sync ($out.ReportLicenseStateHash -eq $stateHash -and $out.Status -eq 'Completed') 'Agent job lost the assessment binding.'
[pscustomobject]@{Status='PASS';Checks=$checks;EvidenceDirectory=$fixture} | ConvertTo-Json -Compress
