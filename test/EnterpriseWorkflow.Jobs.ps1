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
$blocked=$false
try { [void](New-ToolEnterpriseLicenseJob -ClientId ([guid]$id).ToString('D').ToUpperInvariant() -Operation InventoryOnly) } catch { $blocked=$true }
Assert-Sync $blocked 'Alternate GUID spelling bypassed single pending job.'
Assert-Sync ((Get-ToolEnterprisePendingJobPackage ([guid]$id).ToString('D')).JobId -eq $j.JobId) 'Alternate GUID spelling lost pending job.'
Assert-Sync ((Get-ToolEnterpriseDeviceJobState ([guid]$id).ToString('D')).Pending) 'Alternate GUID spelling lost device state.'
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
# Exercise the real AgentOnce orchestration and durable receipt, using synthetic
# transport/execution boundaries only; no host scan, listener or license change.
$agentAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceDirectory 'Tool-EnterpriseAgent.ps1'),[ref]$null,[ref]$null)
$agentFunction=$agentAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ToolEnterpriseAgentOnce'},$false)
. ([scriptblock]::Create($agentFunction.Extent.Text))
$paths | Add-Member ClientSecret 'synthetic'
$NoReport=$false; $Force=$false; $NoJob=$false
$script:deliveries=0; $script:postReports=0; $script:dropResult=$true
$script:agentJob=New-ToolEnterpriseLicenseJob $id InventoryOnly
function Get-ToolEnterpriseClientConfig { return [pscustomobject]@{Enrolled=$true;ClientId=$id;AutoSend=$false;AllowRemoteLicenseChanges=$false} }
function Flush-ToolEnterpriseOutbox { return 0 }
function Get-ToolEnterpriseClientJob { return [pscustomobject]@{HasJob=$true;JobId=$script:agentJob.JobId;JobEnvelope='fixture'} }
function Get-ToolEnterpriseSecret { param($Path); return ,([byte[]](1..32)) }
function Open-ToolEnterpriseEnvelope { param($Secret,$ExpectedContext,$Envelope); return [pscustomobject]@{Payload=$script:agentJob} }
function Write-ToolEnterpriseAgentEvent { param($Event,$Message,$Data) }
function Get-ToolEnterpriseAgentReport { param($ClientId); return [pscustomobject]@{ClientId=$ClientId} }
function Send-ToolEnterpriseReport { param($Report,[switch]$QueueOnFailure); $script:postReports++ }
function Send-ToolEnterpriseJobResult {
    param($Result)
    if($Result.Status -eq 'Running'){ [void](Save-ToolEnterpriseJobResult ([guid]$script:id).ToString('D') $Result); return }
    if($script:dropResult){$script:dropResult=$false; throw 'Synthetic result disconnect'}
    [void](Save-ToolEnterpriseJobResult $script:id $Result); $script:deliveries++
}
$before=$executions
$run1=Invoke-ToolEnterpriseAgentOnce
Assert-Sync ($executions -eq $before+1 -and (Get-ToolEnterpriseDeviceJobState $id).Status -eq 'Running') 'Lost result did not retain Running.'
$run2=Invoke-ToolEnterpriseAgentOnce
Assert-Sync ($executions -eq $before+1 -and $deliveries -eq 1 -and -not (Get-ToolEnterpriseDeviceJobState $id).Pending) 'Agent result redelivery executed twice or failed to clear pending.'
Assert-Sync ($postReports -eq 2 -and $run1.Sent -eq 1 -and $run2.Sent -eq 1) 'AutoSend=false suppressed post-job inventory.'
$NoReport=$true
[void](Invoke-ToolEnterpriseAgentOnce)
Assert-Sync ($postReports -eq 2 -and $executions -eq $before+1) 'Explicit NoReport ignored or job reexecuted.'
[pscustomobject]@{Status='PASS';Checks=$checks;EvidenceDirectory=$fixture} | ConvertTo-Json -Compress
