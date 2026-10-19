param([string]$SourceDirectory = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot 'EnterpriseSync.Freshness.ps1') -SourceDirectory $SourceDirectory
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceDirectory 'Tool-Enterprise.ps1'),[ref]$null,[ref]$null)
$wanted=@('New-ToolEnterpriseLicenseJob','New-ToolEnterpriseLicenseJobCore','Get-ToolEnterpriseDeviceJobState','Restart-ToolEnterpriseReadOnlyJob','Invoke-ToolEnterpriseLicenseJobOnce','Test-ToolEnterpriseJobChangesLicenseState')
foreach($f in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    if($f.Name -in $wanted){. ([scriptblock]::Create($f.Extent.Text))}
}
$paths | Add-Member ClientProcessed (Join-Path $fixture 'processed')
function Get-ToolEnterpriseServerClientSecret { param($ClientId); return ,([byte[]](1..32)) }
function New-ToolEnterpriseEnvelope { param($Secret,$Context,$Payload); return [pscustomobject]@{Fixture=$true} }
$r=Get-Record
$r | Add-Member AllowRemoteLicenseChanges $false -Force
Write-ToolEnterpriseJson (Get-ToolEnterpriseServerClientRecordPath $id) $r
$j=New-ToolEnterpriseLicenseJob -ClientId $id -Operation InventoryOnly
$blocked=$false
try { [void](New-ToolEnterpriseLicenseJob -ClientId $id -Operation LicenseForensics) } catch { $blocked=$true }
Assert-Sync $blocked 'Duplicate submission was accepted.'
Assert-Sync (@(Get-ChildItem (Join-Path $paths.ServerJobs $id) -Filter '*.job').Count -eq 1) 'More than one pending job.'
$running=New-Result $j.JobId 21
$running.Status='Running'
[void](Save-ToolEnterpriseJobResult $id $running)
$state=Get-ToolEnterpriseDeviceJobState $id
Assert-Sync ($state.Status -eq 'Running' -and $state.Pending -and -not $state.CanRetry) 'Running receipt cleared the pending job.'
$failed=New-Result $j.JobId 22 '' 'Failed'
[void](Save-ToolEnterpriseJobResult $id $failed)
$state=Get-ToolEnterpriseDeviceJobState $id
Assert-Sync ($state.CanRetry -and -not $state.Pending) 'Failed read-only job cannot be retried.'
$retry=Restart-ToolEnterpriseReadOnlyJob $id
Assert-Sync ($retry.JobId -ne $j.JobId -and $retry.Operation -eq 'InventoryOnly') 'Retry identity/operation invalid.'
$done=New-Result $retry.JobId 23 '' 'ActionRequired'
$done.Operation='WindowsInstallAndActivate'
[void](Save-ToolEnterpriseJobResult $id $done)
Assert-Sync (-not (Get-ToolEnterpriseDeviceJobState $id).CanRetry) 'License changes may be retried without reconfirmation.'
$script:executions=0; $script:acks=0
function Send-ToolEnterpriseJobResult { param($Result); $script:acks++ }
function Invoke-ToolEnterpriseLicenseJob {
    param($Job,$AllowRemoteLicenseChanges)
    $script:executions++
    return (New-Result $Job.JobId 24)
}
$job=[pscustomobject]@{JobId=[guid]::NewGuid().ToString('N');ClientId=$id;Operation='InventoryOnly';ProductKeyLast5=''}
$first=Invoke-ToolEnterpriseLicenseJobOnce $job $false
$second=Invoke-ToolEnterpriseLicenseJobOnce $job $false
Assert-Sync ($executions -eq 1 -and $acks -eq 1 -and $second.Status -eq $first.Status) 'Result redelivery re-executed the job.'
$job.JobId=[guid]::NewGuid().ToString('N')
$receipt=New-Result $job.JobId 25 '' 'Running'
Write-ToolEnterpriseJson (Join-Path (Join-Path $paths.ClientProcessed $id) ($job.JobId+'.json')) $receipt
$uncertain=Invoke-ToolEnterpriseLicenseJobOnce $job $false
Assert-Sync ($executions -eq 1 -and $uncertain.Status -eq 'ActionRequired') 'Interrupted execution was automatically repeated.'
$job.JobId=[guid]::NewGuid().ToString('N')
function Send-ToolEnterpriseJobResult { param($Result); throw 'Synthetic disconnect' }
try { [void](Invoke-ToolEnterpriseLicenseJobOnce $job $false) } catch {}
Assert-Sync ($executions -eq 1) 'Job ran without a server acknowledgement.'
$recovered=Invoke-ToolEnterpriseLicenseJobOnce $job $false
Assert-Sync ($executions -eq 1 -and $recovered.Status -eq 'ActionRequired') 'Unacknowledged receipt replay executed work.'
[pscustomobject]@{Status='PASS';Checks=$checks;EvidenceDirectory=$fixture} | ConvertTo-Json -Compress
