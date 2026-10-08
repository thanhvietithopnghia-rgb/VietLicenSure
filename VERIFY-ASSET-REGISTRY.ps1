param([string]$SourceDirectory = '')
$ErrorActionPreference = 'Stop'
$root = if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $PSScriptRoot } else { [IO.Path]::GetFullPath($SourceDirectory) }
. (Join-Path $root 'Tool-AssetRegistry.ps1')

function Assert-AssetRegistry {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$schemaPath = Join-Path $root 'asset-registry-schema-v1.0.json'
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AssetRegistry ([string]$schema.title -eq 'VietLicenSure Asset Registry') 'Asset Registry JSON schema is missing or invalid.'
Assert-AssetRegistry ([string]$schema.properties.SchemaVersion.const -eq '1.0') 'Asset Registry JSON schema version is invalid.'

$metadata = Get-ToolAssetRegistryMetadata
Assert-AssetRegistry ([string]$metadata.SchemaVersion -eq '1.0') 'Asset Registry module schema version is invalid.'
Assert-AssetRegistry ([string]$metadata.AssignmentHistoryMode -eq 'AppendOnly') 'Assignment history is not append-only.'
Assert-AssetRegistry (@($metadata.VolatileIdentityExcluded) -contains 'IpAddress' -and @($metadata.VolatileIdentityExcluded) -contains 'ComputerName' -and @($metadata.VolatileIdentityExcluded) -contains 'UserName') 'Volatile identity fields are not explicitly excluded.'

$time1 = '2026-10-08T01:00:00.0000000Z'
$time2 = '2026-10-08T02:00:00.0000000Z'
$time3 = '2026-10-08T03:00:00.0000000Z'
$observation1 = [pscustomobject]@{
    SystemUuid='5f8d7701-6f5f-4f5e-8d10-123456789abc'; SystemSerialNumber='SYS-001'; BiosSerialNumber='BIOS-001'
    BaseboardSerialNumber='BOARD-001'; ChassisSerialNumber='CHASSIS-001'; MachineGuid='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    Manufacturer='Contoso'; Model='Workstation'; ComputerName='PC-OLD'; IpAddress='10.1.1.10'; UserName='old.user'
}
$observationRenamed = [pscustomobject]@{
    SystemUuid='5F8D7701-6F5F-4F5E-8D10-123456789ABC'; SystemSerialNumber='SYS-001'; BiosSerialNumber='BIOS-001'
    BaseboardSerialNumber='BOARD-001'; ChassisSerialNumber='CHASSIS-001'; MachineGuid='AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
    Manufacturer='Contoso'; Model='Workstation'; ComputerName='PC-RENAMED'; IpAddress='192.168.50.25'; UserName='new.user'; Department='Finance'
}
$identity1 = Get-ToolDeviceIdentitySnapshot -Observation $observation1 -ObservedAtUtc $time1
$identity2 = Get-ToolDeviceIdentitySnapshot -Observation $observationRenamed -ObservedAtUtc $time2
Assert-AssetRegistry ([string]$identity1.DeviceId -eq [string]$identity2.DeviceId) 'DeviceId changed after hostname/IP/user changes.'
Assert-AssetRegistry ([string]$identity1.DeviceId -match '^VLS-DEV-[A-F0-9]{32}$') 'DeviceId format is invalid.'
$identityJson = $identity1 | ConvertTo-Json -Depth 8 -Compress
Assert-AssetRegistry ($identityJson -notmatch 'SYS-001|BIOS-001|5f8d7701|aaaaaaaa') 'Raw hardware identifiers leaked into the identity snapshot.'

$placeholderObservation = [pscustomobject]@{ UUID='00000000-0000-0000-0000-000000000000'; SystemSerialNumber='To be filled by O.E.M.'; MachineGuid='11111111-2222-3333-4444-555555555555'; ComputerName='PLACEHOLDER-PC' }
$placeholderIdentity = Get-ToolDeviceIdentitySnapshot -Observation $placeholderObservation -ObservedAtUtc $time1
Assert-AssetRegistry ([string]$placeholderIdentity.IdentityConfidence -eq 'Low') 'Placeholder identifiers were not rejected in favour of the fallback identity.'
Assert-AssetRegistry (@($placeholderIdentity.IdentifierTypes) -notcontains 'SystemUuid' -and @($placeholderIdentity.IdentifierTypes) -notcontains 'SystemSerial') 'Placeholder identifiers were retained.'

$store = New-ToolAssetRegistryStore -NowUtc $time1
$created = Register-ToolAssetObservation -Store $store -Observation $observation1 -ExternalAssetTag 'ASSET-001' -InventoryNumber 'INV-001' -ObservedAtUtc $time1
Assert-AssetRegistry ([string]$created.Status -eq 'Created' -and [bool]$created.Changed) 'Initial asset registration failed.'
Assert-AssetRegistry (@($store.Devices).Count -eq 1 -and @($store.Assets).Count -eq 1) 'Initial registration did not create exactly one device and one asset.'
$deviceId = [string]$created.DeviceId
$assetId = [string]$created.AssetId

$matched = Register-ToolAssetObservation -Store $store -Observation $observationRenamed -ExternalAssetTag 'ASSET-001' -ObservedAtUtc $time2
Assert-AssetRegistry ([string]$matched.Status -eq 'Matched' -and [string]$matched.DeviceId -eq $deviceId -and [string]$matched.AssetId -eq $assetId) 'Stable device/asset identity was not retained.'
Assert-AssetRegistry (@($store.Devices).Count -eq 1 -and @($store.Assets).Count -eq 1 -and [int]$store.Devices[0].ObservationCount -eq 2) 'Duplicate device or asset was created during a repeat observation.'
Assert-AssetRegistry ([string]$store.Devices[0].LastKnownComputerName -eq 'PC-RENAMED') 'Volatile display metadata was not refreshed without changing identity.'

$differentDevice = [pscustomobject]@{ UUID='6f8d7701-6f5f-4f5e-8d10-123456789abc'; SystemSerialNumber='SYS-002'; MachineGuid='bbbbbbbb-cccc-dddd-eeee-ffffffffffff'; Manufacturer='Contoso'; Model='Workstation'; ComputerName='PC-OLD'; IpAddress='10.1.1.10'; UserName='old.user' }
$differentResult = Register-ToolAssetObservation -Store $store -Observation $differentDevice -ObservedAtUtc $time2
Assert-AssetRegistry ([string]$differentResult.Status -eq 'Created' -and [string]$differentResult.DeviceId -ne $deviceId) 'Hostname/IP/user incorrectly merged two different devices.'

$conflictObservation = [pscustomobject]@{ UUID='7f8d7701-6f5f-4f5e-8d10-123456789abc'; MachineGuid='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; Manufacturer='Contoso'; Model='Workstation' }
$beforeConflict = $store | ConvertTo-Json -Depth 16 -Compress
$conflict = Register-ToolAssetObservation -Store $store -Observation $conflictObservation -ObservedAtUtc $time3
$afterConflict = $store | ConvertTo-Json -Depth 16 -Compress
Assert-AssetRegistry ([string]$conflict.Status -eq 'Conflict' -and -not [bool]$conflict.Changed) 'Strong identifier conflict did not fail closed.'
Assert-AssetRegistry ($beforeConflict -eq $afterConflict) 'Conflict handling mutated the registry.'

$duplicateTagObservation = [pscustomobject]@{ UUID='8f8d7701-6f5f-4f5e-8d10-123456789abc'; MachineGuid='cccccccc-dddd-eeee-ffff-000000000001'; Manufacturer='Fabrikam'; Model='Notebook' }
$duplicateTag = Register-ToolAssetObservation -Store $store -Observation $duplicateTagObservation -ExternalAssetTag 'asset-001' -ObservedAtUtc $time3
Assert-AssetRegistry ([string]$duplicateTag.Status -eq 'Conflict' -and [string]$duplicateTag.Reason -eq 'AssetTagBoundToDifferentDevice') 'Duplicate external asset tag did not fail closed.'

$ambiguousStore = New-ToolAssetRegistryStore -NowUtc $time1
$ambiguousObservation = [pscustomobject]@{ SystemSerialNumber='SHARED-SERIAL'; Manufacturer='Contoso'; Model='Desktop'; ComputerName='AMBIGUOUS' }
$ambiguousCreated = Register-ToolAssetObservation -Store $ambiguousStore -Observation $ambiguousObservation -ObservedAtUtc $time1
$ambiguousStore.Devices[0].DeviceId = 'VLS-DEV-' + ('B' * 32)
$ambiguousStore.Assets[0].DeviceId = $ambiguousStore.Devices[0].DeviceId
$clone = $ambiguousStore.Devices[0] | Select-Object *
$clone.DeviceId = 'VLS-DEV-' + ('A' * 32)
$ambiguousStore.Devices = [object[]](@($ambiguousStore.Devices) + $clone)
[void](Assert-ToolAssetRegistryStore $ambiguousStore)
$ambiguous = Resolve-ToolAssetDeviceMatch -Store $ambiguousStore -Observation $ambiguousObservation
Assert-AssetRegistry ([string]$ambiguous.Status -eq 'Ambiguous' -and @($ambiguous.Candidates).Count -eq 2) 'Ambiguous matching did not fail closed.'

$assignment1 = Add-ToolAssetAssignmentEvent -Store $store -AssetId $assetId -Action Assign -AssigneeType User -AssigneeReference 'user:1001' -DisplayName 'User One' -Reason 'Initial handoff' -RecordedBy 'admin' -EffectiveAtUtc $time1 -RecordedAtUtc $time1
$assignment1Frozen = $assignment1 | ConvertTo-Json -Depth 8 -Compress
$assignment2 = Add-ToolAssetAssignmentEvent -Store $store -AssetId $assetId -Action Reassign -AssigneeType Department -AssigneeReference 'department:finance' -DisplayName 'Finance' -Reason 'Department transfer' -RecordedBy 'admin' -EffectiveAtUtc $time2 -RecordedAtUtc $time2
$current = Get-ToolCurrentAssetAssignment -Store $store -AssetId $assetId
Assert-AssetRegistry ([string]$current.AssignmentId -eq [string]$assignment2.AssignmentId -and [string]$assignment2.PreviousAssignmentId -eq [string]$assignment1.AssignmentId) 'Reassignment chain is invalid.'
[void](Add-ToolAssetAssignmentEvent -Store $store -AssetId $assetId -Action Release -Reason 'Returned to stock' -RecordedBy 'admin' -EffectiveAtUtc $time3 -RecordedAtUtc $time3)
Assert-AssetRegistry ($null -eq (Get-ToolCurrentAssetAssignment -Store $store -AssetId $assetId)) 'Release did not clear the current assignment.'
$history = @(Get-ToolAssetAssignmentHistory -Store $store -AssetId $assetId)
Assert-AssetRegistry ($history.Count -eq 3 -and [int]$history[0].Sequence -eq 1 -and [int]$history[2].Sequence -eq 3) 'Assignment history sequence is invalid.'
Assert-AssetRegistry (($history[0] | ConvertTo-Json -Depth 8 -Compress) -eq $assignment1Frozen) 'Append-only history mutated an earlier event.'

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('VLS-AssetRegistry-' + [Guid]::NewGuid().ToString('N'))
try {
    $storePath = Write-ToolAssetRegistryStore -Store $store -RootPath $temporaryRoot
    Assert-AssetRegistry (Test-Path -LiteralPath $storePath -PathType Leaf) 'Atomic store write did not create the registry file.'
    $roundTrip = Read-ToolAssetRegistryStore -RootPath $temporaryRoot
    Assert-AssetRegistry (@($roundTrip.Devices).Count -eq @($store.Devices).Count -and @($roundTrip.Assets).Count -eq @($store.Assets).Count -and @($roundTrip.Assignments).Count -eq 3) 'Registry round-trip lost records.'
    [void](Assert-ToolAssetRegistryStore $roundTrip)
} finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host 'Asset Registry v1.0 regression: PASS'
Write-Host ('DeviceId: {0}' -f $deviceId)
Write-Host ('AssetId: {0}' -f $assetId)
Write-Host 'Matching: rename/IP/user stable; conflicts and ambiguity fail closed'
Write-Host 'Assignments: append-only Assign -> Reassign -> Release'
exit 0
