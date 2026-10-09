$script:ToolAssetRegistrySchemaVersion = '1.0'
$script:ToolAssetRegistryMaximumStoreBytes = 16777216
$script:ToolAssetRegistryAllowedAssetStatus = @('Active','Repair','Retired','Disposed','Lost')
$script:ToolAssetRegistryAllowedAssignmentAction = @('Assign','Reassign','Release')
$script:ToolAssetRegistryAllowedAssigneeType = @('User','Department','Location','Custodian')
$script:ToolAssetRegistryIdentityWeights = [ordered]@{
    SystemUuid = 100
    SystemSerial = 70
    BiosSerial = 35
    BaseboardSerial = 35
    ChassisSerial = 25
    MachineGuid = 45
}

function ConvertTo-ToolAssetRegistrySafeText {
    param([AllowNull()][object]$Value, [int]$MaximumLength = 300)
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    $text = ($text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '').Trim()
    if ($MaximumLength -gt 0 -and $text.Length -gt $MaximumLength) { $text = $text.Substring(0, $MaximumLength) }
    return $text
}

function ConvertTo-ToolAssetRegistryUtcText {
    param([AllowNull()][object]$Value, [switch]$AllowEmpty)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        if ($AllowEmpty) { return '' }
        return [DateTime]::UtcNow.ToString('o')
    }
    $parsed = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
        throw 'Asset Registry UTC timestamp is invalid.'
    }
    return $parsed.ToUniversalTime().ToString('o')
}

function Get-ToolAssetRegistrySha256Hex {
    param([Parameter(Mandatory=$true)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '').ToUpperInvariant()
    } finally { $sha.Dispose() }
}

function Get-ToolAssetRegistryPropertyValue {
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory=$true)][string[]]$Names)
    if ($null -eq $InputObject) { return '' }
    foreach ($name in $Names) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) { return [string]$property.Value }
    }
    return ''
}

function ConvertTo-ToolAssetRegistryIdentityValue {
    param([AllowNull()][object]$Value, [switch]$Compact)
    $text = (ConvertTo-ToolAssetRegistrySafeText $Value 300).ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $text = ($text -replace '\s+', ' ').Trim()
    if ($Compact) { $text = $text -replace '[\s\{\}\-:]', '' }
    $placeholder = $text -replace '[^A-Z0-9]', ''
    if ($placeholder -match '^(?:0+|F+|X+|1+|1234567890*)$' -or
        $text -in @('UNKNOWN','NONE','N/A','NA','NOT APPLICABLE','DEFAULT STRING','SYSTEM SERIAL NUMBER','TO BE FILLED BY O.E.M.','TO BE FILLED BY OEM','OEM')) {
        return ''
    }
    return $text
}

function Get-ToolAssetRegistryIdentifierDigest {
    param([Parameter(Mandatory=$true)][string]$Type, [Parameter(Mandatory=$true)][string]$NormalizedValue)
    return Get-ToolAssetRegistrySha256Hex ("VLS-ASSET-IDENTIFIER-v1|{0}|{1}" -f $Type, $NormalizedValue)
}

function New-ToolAssetRegistryId {
    param([Parameter(Mandatory=$true)][ValidateSet('Asset','Assignment','Event','Registry')][string]$Kind)
    $prefix = switch ($Kind) { 'Asset' {'VLS-AST'}; 'Assignment' {'VLS-ASN'}; 'Event' {'VLS-AEV'}; default {'VLS-REG'} }
    return $prefix + '-' + [Guid]::NewGuid().ToString('N').ToUpperInvariant()
}

function New-ToolAssetRegistryStore {
    param([AllowNull()][object]$NowUtc)
    $now = ConvertTo-ToolAssetRegistryUtcText $NowUtc
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolAssetRegistrySchemaVersion
        RegistryId = New-ToolAssetRegistryId -Kind Registry
        CreatedAtUtc = $now
        UpdatedAtUtc = $now
        Devices = [object[]]@()
        Assets = [object[]]@()
        Assignments = [object[]]@()
    }
}

function Get-ToolDeviceIdentitySnapshot {
    param([Parameter(Mandatory=$true)][object]$Observation, [AllowNull()][object]$ObservedAtUtc)
    $values = [ordered]@{
        SystemUuid = ConvertTo-ToolAssetRegistryIdentityValue (Get-ToolAssetRegistryPropertyValue $Observation @('SystemUuid','UUID')) -Compact
        SystemSerial = ConvertTo-ToolAssetRegistryIdentityValue (Get-ToolAssetRegistryPropertyValue $Observation @('SystemSerialNumber','SystemSerial','IdentifyingNumber'))
        BiosSerial = ConvertTo-ToolAssetRegistryIdentityValue (Get-ToolAssetRegistryPropertyValue $Observation @('BiosSerialNumber','BiosSerial'))
        BaseboardSerial = ConvertTo-ToolAssetRegistryIdentityValue (Get-ToolAssetRegistryPropertyValue $Observation @('BaseboardSerialNumber','BaseboardSerial'))
        ChassisSerial = ConvertTo-ToolAssetRegistryIdentityValue (Get-ToolAssetRegistryPropertyValue $Observation @('ChassisSerialNumber','ChassisSerial'))
        MachineGuid = ConvertTo-ToolAssetRegistryIdentityValue (Get-ToolAssetRegistryPropertyValue $Observation @('MachineGuid')) -Compact
    }
    $manufacturer = ConvertTo-ToolAssetRegistryIdentityValue (Get-ToolAssetRegistryPropertyValue $Observation @('Manufacturer','SystemManufacturer'))
    $model = ConvertTo-ToolAssetRegistryIdentityValue (Get-ToolAssetRegistryPropertyValue $Observation @('Model','SystemModel'))
    $basis = ''
    $confidence = 'Low'
    if ($values.SystemUuid) {
        $basis = 'UUID|' + $values.SystemUuid
        $confidence = 'High'
    } elseif ($values.SystemSerial -and ($manufacturer -or $model)) {
        $basis = 'SYSTEM|' + $values.SystemSerial + '|' + $manufacturer + '|' + $model
        $confidence = 'High'
    } elseif ($values.BiosSerial -and $values.BaseboardSerial) {
        $basis = 'BOARD|' + $values.BiosSerial + '|' + $values.BaseboardSerial
        $confidence = 'Medium'
    } elseif ($values.MachineGuid) {
        $basis = 'MACHINEGUID|' + $values.MachineGuid
        $confidence = 'Low'
    } else {
        throw 'Insufficient stable device identity: UUID, system serial with manufacturer/model, BIOS+baseboard serial, or MachineGuid is required.'
    }
    $digests = [ordered]@{}
    foreach ($type in $values.Keys) {
        if ($values[$type]) { $digests[$type] = Get-ToolAssetRegistryIdentifierDigest -Type $type -NormalizedValue $values[$type] }
    }
    $deviceDigest = Get-ToolAssetRegistrySha256Hex ('VLS-DEVICE-ID-v1|' + $basis)
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolAssetRegistrySchemaVersion
        DeviceId = 'VLS-DEV-' + $deviceDigest.Substring(0,32)
        IdentityConfidence = $confidence
        IdentifierDigests = [pscustomobject]$digests
        IdentifierTypes = [object[]]@($digests.Keys)
        Manufacturer = ConvertTo-ToolAssetRegistrySafeText (Get-ToolAssetRegistryPropertyValue $Observation @('Manufacturer','SystemManufacturer')) 120
        Model = ConvertTo-ToolAssetRegistrySafeText (Get-ToolAssetRegistryPropertyValue $Observation @('Model','SystemModel')) 120
        ComputerName = ConvertTo-ToolAssetRegistrySafeText (Get-ToolAssetRegistryPropertyValue $Observation @('ComputerName','HostName','MachineName')) 120
        ObservedAtUtc = ConvertTo-ToolAssetRegistryUtcText $ObservedAtUtc
    }
}

function Get-ToolAssetRegistryDigestMap {
    param([AllowNull()][object]$Value)
    $map = @{}
    if ($null -eq $Value) { return $map }
    foreach ($property in @($Value.PSObject.Properties)) {
        $text = ([string]$property.Value).Trim().ToUpperInvariant()
        if ($text -match '^[A-F0-9]{64}$') { $map[[string]$property.Name] = $text }
    }
    return $map
}

function Assert-ToolAssetIdentitySnapshot {
    param([Parameter(Mandatory=$true)][object]$Identity)
    if ([string]$Identity.SchemaVersion -ne $script:ToolAssetRegistrySchemaVersion) { throw 'Asset identity schema is unsupported.' }
    if ([string]$Identity.DeviceId -notmatch '^VLS-DEV-[A-F0-9]{32}$') { throw 'Asset identity DeviceId is invalid.' }
    if ([string]$Identity.IdentityConfidence -notin @('High','Medium','Low')) { throw 'Asset identity confidence is invalid.' }
    $digests = Get-ToolAssetRegistryDigestMap $Identity.IdentifierDigests
    if ($digests.Count -eq 0) { throw 'Asset identity digests are missing.' }
    foreach ($type in $digests.Keys) {
        if (-not $script:ToolAssetRegistryIdentityWeights.Contains($type)) { throw 'Asset identity digest type is unsupported.' }
    }
    return $true
}

function Resolve-ToolAssetIdentityMatch {
    param([Parameter(Mandatory=$true)][object]$Store, [Parameter(Mandatory=$true)][object]$Identity)
    [void](Assert-ToolAssetIdentitySnapshot $Identity)
    $identity = $Identity
    $incoming = Get-ToolAssetRegistryDigestMap $identity.IdentifierDigests
    $valid = New-Object Collections.Generic.List[object]
    $conflicting = New-Object Collections.Generic.List[object]
    foreach ($device in @($Store.Devices)) {
        $existing = Get-ToolAssetRegistryDigestMap $device.IdentifierDigests
        $score = 0
        $matches = New-Object Collections.Generic.List[string]
        $conflicts = New-Object Collections.Generic.List[string]
        foreach ($type in $script:ToolAssetRegistryIdentityWeights.Keys) {
            if (-not $incoming.ContainsKey($type) -or -not $existing.ContainsKey($type)) { continue }
            if ($incoming[$type] -eq $existing[$type]) {
                $score += [int]$script:ToolAssetRegistryIdentityWeights[$type]
                [void]$matches.Add($type)
            } elseif ($type -in @('SystemUuid','SystemSerial')) {
                [void]$conflicts.Add($type)
            }
        }
        # DeviceId is a useful accelerator but must never be accepted without
        # at least one independently matching digest from the authenticated
        # endpoint report.
        if ($matches.Count -gt 0 -and [string]$device.DeviceId -eq [string]$identity.DeviceId) { $score += 120; [void]$matches.Add('DeviceId') }
        if ($score -le 0) { continue }
        $candidate = [pscustomobject][ordered]@{
            DeviceId=[string]$device.DeviceId; Score=$score; MatchedIdentifiers=[object[]]@($matches.ToArray()); ConflictingIdentifiers=[object[]]@($conflicts.ToArray())
        }
        if ($conflicts.Count -gt 0) { [void]$conflicting.Add($candidate) } else { [void]$valid.Add($candidate) }
    }
    if ($conflicting.Count -gt 0) {
        $topConflict = @($conflicting.ToArray() | Sort-Object @{Expression='Score';Descending=$true}, DeviceId | Select-Object -First 1)[0]
        return [pscustomobject][ordered]@{ Status='Conflict'; DeviceId=''; Score=[int]$topConflict.Score; Identity=$identity; Candidates=[object[]]@($conflicting.ToArray()); Reason='StrongIdentifierConflict' }
    }
    $ranked = @($valid.ToArray() | Sort-Object @{Expression='Score';Descending=$true}, DeviceId)
    if ($ranked.Count -eq 0 -or [int]$ranked[0].Score -lt 70) {
        return [pscustomobject][ordered]@{ Status='New'; DeviceId=[string]$identity.DeviceId; Score=0; Identity=$identity; Candidates=[object[]]@(); Reason='NoReliableMatch' }
    }
    if ($ranked.Count -gt 1 -and [int]$ranked[1].Score -ge 70 -and ([int]$ranked[0].Score - [int]$ranked[1].Score) -lt 15) {
        return [pscustomobject][ordered]@{ Status='Ambiguous'; DeviceId=''; Score=[int]$ranked[0].Score; Identity=$identity; Candidates=[object[]]$ranked; Reason='MultipleReliableMatches' }
    }
    return [pscustomobject][ordered]@{ Status='Matched'; DeviceId=[string]$ranked[0].DeviceId; Score=[int]$ranked[0].Score; Identity=$identity; Candidates=[object[]]$ranked; Reason='ReliableIdentityMatch' }
}

function Resolve-ToolAssetDeviceMatch {
    param([Parameter(Mandatory=$true)][object]$Store, [Parameter(Mandatory=$true)][object]$Observation)
    $identity = Get-ToolDeviceIdentitySnapshot -Observation $Observation
    return (Resolve-ToolAssetIdentityMatch -Store $Store -Identity $identity)
}

function Assert-ToolAssetRegistryStore {
    param([Parameter(Mandatory=$true)][object]$Store)
    if ([string]$Store.SchemaVersion -ne $script:ToolAssetRegistrySchemaVersion) { throw 'Asset Registry schema is unsupported.' }
    if ([string]$Store.RegistryId -notmatch '^VLS-REG-[A-F0-9]{32}$') { throw 'RegistryId is invalid.' }
    $deviceIds = @{}
    foreach ($device in @($Store.Devices)) {
        $id = [string]$device.DeviceId
        if ($id -notmatch '^VLS-DEV-[A-F0-9]{32}$' -or $deviceIds.ContainsKey($id)) { throw 'DeviceId is invalid or duplicated.' }
        $deviceIds[$id] = $true
        if (@((Get-ToolAssetRegistryDigestMap $device.IdentifierDigests).Keys).Count -eq 0) { throw 'Device identity digests are missing.' }
    }
    $assetIds = @{}
    $assetDevices = @{}
    $assetTags = @{}
    foreach ($asset in @($Store.Assets)) {
        $assetId = [string]$asset.AssetId
        if ($assetId -notmatch '^VLS-AST-[A-F0-9]{32}$' -or $assetIds.ContainsKey($assetId)) { throw 'AssetId is invalid or duplicated.' }
        if (-not $deviceIds.ContainsKey([string]$asset.DeviceId)) { throw 'Asset references an unknown DeviceId.' }
        if ([string]$asset.Status -notin $script:ToolAssetRegistryAllowedAssetStatus) { throw 'Asset status is invalid.' }
        $assetIds[$assetId] = $true
        $assetDevices[$assetId] = [string]$asset.DeviceId
        $tag = (ConvertTo-ToolAssetRegistrySafeText $asset.ExternalAssetTag 120).ToUpperInvariant()
        if ($tag) {
            if ($assetTags.ContainsKey($tag)) { throw 'ExternalAssetTag is duplicated.' }
            $assetTags[$tag] = $assetId
        }
    }
    $events = @($Store.Assignments | Sort-Object AssetId, Sequence)
    $lastSequence = @{}
    $active = @{}
    $eventIds = @{}
    foreach ($event in $events) {
        $assetId = [string]$event.AssetId
        if (-not $assetIds.ContainsKey($assetId)) { throw 'Assignment references an unknown AssetId.' }
        $eventId = [string]$event.EventId
        if ($eventId -notmatch '^VLS-AEV-[A-F0-9]{32}$' -or $eventIds.ContainsKey($eventId)) { throw 'Assignment EventId is invalid or duplicated.' }
        $eventIds[$eventId] = $true
        if ([string]$event.DeviceId -ne [string]$assetDevices[$assetId]) { throw 'Assignment DeviceId does not match the asset binding.' }
        if ([string]$event.AssignmentId -notmatch '^VLS-ASN-[A-F0-9]{32}$') { throw 'AssignmentId is invalid.' }
        $expected = if ($lastSequence.ContainsKey($assetId)) { [int]$lastSequence[$assetId] + 1 } else { 1 }
        if ([int]$event.Sequence -ne $expected) { throw 'Assignment sequence is not append-only.' }
        $lastSequence[$assetId] = [int]$event.Sequence
        $action = [string]$event.Action
        if ($action -notin $script:ToolAssetRegistryAllowedAssignmentAction) { throw 'Assignment action is invalid.' }
        if ($action -eq 'Assign') {
            if ($active.ContainsKey($assetId)) { throw 'Assign cannot replace an active assignment.' }
            if ([string]$event.AssigneeType -notin $script:ToolAssetRegistryAllowedAssigneeType -or [string]::IsNullOrWhiteSpace([string]$event.AssigneeReference)) { throw 'Assign target is invalid.' }
            $active[$assetId] = [string]$event.AssignmentId
        } elseif ($action -eq 'Reassign') {
            if (-not $active.ContainsKey($assetId) -or [string]$event.PreviousAssignmentId -ne [string]$active[$assetId]) { throw 'Reassign does not reference the active assignment.' }
            if ([string]$event.AssigneeType -notin $script:ToolAssetRegistryAllowedAssigneeType -or [string]::IsNullOrWhiteSpace([string]$event.AssigneeReference)) { throw 'Reassign target is invalid.' }
            $active[$assetId] = [string]$event.AssignmentId
        } else {
            if (-not $active.ContainsKey($assetId) -or [string]$event.AssignmentId -ne [string]$active[$assetId]) { throw 'Release does not reference the active assignment.' }
            [void]$active.Remove($assetId)
        }
    }
    return $true
}

function Register-ToolAssetIdentitySnapshot {
    param(
        [Parameter(Mandatory=$true)][object]$Store,
        [Parameter(Mandatory=$true)][object]$IdentitySnapshot,
        [string]$ExternalAssetTag = '',
        [string]$InventoryNumber = '',
        [AllowNull()][object]$ObservedAtUtc
    )
    [void](Assert-ToolAssetRegistryStore $Store)
    $now = ConvertTo-ToolAssetRegistryUtcText $ObservedAtUtc
    [void](Assert-ToolAssetIdentitySnapshot $IdentitySnapshot)
    $match = Resolve-ToolAssetIdentityMatch -Store $Store -Identity $IdentitySnapshot
    $normalizedTag = (ConvertTo-ToolAssetRegistrySafeText $ExternalAssetTag 120).ToUpperInvariant()
    $tagAsset = @($Store.Assets | Where-Object { $normalizedTag -and ([string]$_.ExternalAssetTag).ToUpperInvariant() -eq $normalizedTag } | Select-Object -First 1)
    if ($match.Status -in @('Conflict','Ambiguous')) {
        return [pscustomobject][ordered]@{ Status=[string]$match.Status; Changed=$false; DeviceId=''; AssetId=''; Match=$match; Store=$Store }
    }
    if ($tagAsset.Count -gt 0 -and $match.Status -eq 'New') {
        return [pscustomobject][ordered]@{ Status='Conflict'; Changed=$false; DeviceId=''; AssetId=[string]$tagAsset[0].AssetId; Match=$match; Store=$Store; Reason='AssetTagBoundToDifferentDevice' }
    }
    if ($tagAsset.Count -gt 0 -and $match.Status -eq 'Matched' -and [string]$tagAsset[0].DeviceId -ne [string]$match.DeviceId) {
        return [pscustomobject][ordered]@{ Status='Conflict'; Changed=$false; DeviceId=[string]$match.DeviceId; AssetId=[string]$tagAsset[0].AssetId; Match=$match; Store=$Store; Reason='DuplicateAssetTag' }
    }
    $identity = $match.Identity
    $device = $null
    $created = $false
    if ($match.Status -eq 'Matched') {
        $device = @($Store.Devices | Where-Object { [string]$_.DeviceId -eq [string]$match.DeviceId } | Select-Object -First 1)[0]
        $existingDigests = Get-ToolAssetRegistryDigestMap $device.IdentifierDigests
        $incomingDigests = Get-ToolAssetRegistryDigestMap $identity.IdentifierDigests
        foreach ($type in $incomingDigests.Keys) {
            if (-not $existingDigests.ContainsKey($type)) { $device.IdentifierDigests | Add-Member -NotePropertyName $type -NotePropertyValue $incomingDigests[$type] -Force }
        }
        $device.LastSeenUtc = $now
        $device.ObservationCount = [int]$device.ObservationCount + 1
        if ($identity.ComputerName) { $device.LastKnownComputerName = $identity.ComputerName }
        if ($identity.Manufacturer) { $device.Manufacturer = $identity.Manufacturer }
        if ($identity.Model) { $device.Model = $identity.Model }
    } else {
        $device = [pscustomobject][ordered]@{
            DeviceId=[string]$identity.DeviceId; IdentityConfidence=[string]$identity.IdentityConfidence
            IdentifierDigests=$identity.IdentifierDigests; CreatedAtUtc=$now; LastSeenUtc=$now; ObservationCount=1
            LastKnownComputerName=[string]$identity.ComputerName; Manufacturer=[string]$identity.Manufacturer; Model=[string]$identity.Model
        }
        $Store.Devices = [object[]](@($Store.Devices) + $device)
        $created = $true
    }
    $asset = @($Store.Assets | Where-Object { [string]$_.DeviceId -eq [string]$device.DeviceId } | Select-Object -First 1)
    if ($asset.Count -eq 0) {
        $assetRecord = [pscustomobject][ordered]@{
            AssetId=New-ToolAssetRegistryId -Kind Asset; DeviceId=[string]$device.DeviceId; ExternalAssetTag=ConvertTo-ToolAssetRegistrySafeText $ExternalAssetTag 120
            InventoryNumber=ConvertTo-ToolAssetRegistrySafeText $InventoryNumber 120; Status='Active'; CreatedAtUtc=$now; UpdatedAtUtc=$now
        }
        $Store.Assets = [object[]](@($Store.Assets) + $assetRecord)
        $asset = @($assetRecord)
    } else {
        if ($tagAsset.Count -gt 0 -and [string]$tagAsset[0].AssetId -ne [string]$asset[0].AssetId) {
            return [pscustomobject][ordered]@{ Status='Conflict'; Changed=$false; DeviceId=[string]$device.DeviceId; AssetId=[string]$asset[0].AssetId; Match=$match; Store=$Store; Reason='DuplicateAssetTag' }
        }
        if ($ExternalAssetTag -and -not $asset[0].ExternalAssetTag) { $asset[0].ExternalAssetTag = ConvertTo-ToolAssetRegistrySafeText $ExternalAssetTag 120 }
        if ($InventoryNumber -and -not $asset[0].InventoryNumber) { $asset[0].InventoryNumber = ConvertTo-ToolAssetRegistrySafeText $InventoryNumber 120 }
        $asset[0].UpdatedAtUtc = $now
    }
    $Store.UpdatedAtUtc = $now
    [void](Assert-ToolAssetRegistryStore $Store)
    return [pscustomobject][ordered]@{
        Status=if($created){'Created'}else{'Matched'}; Changed=$true; DeviceId=[string]$device.DeviceId; AssetId=[string]$asset[0].AssetId; Match=$match; Store=$Store
    }
}

function Register-ToolAssetObservation {
    param(
        [Parameter(Mandatory=$true)][object]$Store,
        [Parameter(Mandatory=$true)][object]$Observation,
        [string]$ExternalAssetTag = '',
        [string]$InventoryNumber = '',
        [AllowNull()][object]$ObservedAtUtc
    )
    $identity = Get-ToolDeviceIdentitySnapshot -Observation $Observation -ObservedAtUtc $ObservedAtUtc
    return (Register-ToolAssetIdentitySnapshot -Store $Store -IdentitySnapshot $identity -ExternalAssetTag $ExternalAssetTag -InventoryNumber $InventoryNumber -ObservedAtUtc $ObservedAtUtc)
}

function Get-ToolCurrentAssetAssignment {
    param([Parameter(Mandatory=$true)][object]$Store, [Parameter(Mandatory=$true)][string]$AssetId)
    $current = $null
    foreach ($event in @($Store.Assignments | Where-Object { [string]$_.AssetId -eq $AssetId } | Sort-Object Sequence)) {
        if ([string]$event.Action -in @('Assign','Reassign')) { $current = $event }
        elseif ([string]$event.Action -eq 'Release') { $current = $null }
    }
    return $current
}

function Add-ToolAssetAssignmentEvent {
    param(
        [Parameter(Mandatory=$true)][object]$Store,
        [Parameter(Mandatory=$true)][string]$AssetId,
        [Parameter(Mandatory=$true)][ValidateSet('Assign','Reassign','Release')][string]$Action,
        [ValidateSet('User','Department','Location','Custodian')][string]$AssigneeType = 'User',
        [string]$AssigneeReference = '',
        [string]$DisplayName = '',
        [string]$Reason = '',
        [string]$RecordedBy = 'LocalAdministrator',
        [AllowNull()][object]$EffectiveAtUtc,
        [AllowNull()][object]$RecordedAtUtc
    )
    [void](Assert-ToolAssetRegistryStore $Store)
    $asset = @($Store.Assets | Where-Object { [string]$_.AssetId -eq $AssetId } | Select-Object -First 1)
    if ($asset.Count -eq 0) { throw 'AssetId does not exist.' }
    $current = Get-ToolCurrentAssetAssignment -Store $Store -AssetId $AssetId
    if ($Action -eq 'Assign' -and $null -ne $current) { throw 'Asset already has an active assignment; use Reassign.' }
    if ($Action -in @('Reassign','Release') -and $null -eq $current) { throw "$Action requires an active assignment." }
    if ($Action -ne 'Release' -and [string]::IsNullOrWhiteSpace((ConvertTo-ToolAssetRegistrySafeText $AssigneeReference 200))) { throw 'AssigneeReference is required.' }
    $history = @($Store.Assignments | Where-Object { [string]$_.AssetId -eq $AssetId })
    $sequence = $history.Count + 1
    $assignmentId = if ($Action -eq 'Release') { [string]$current.AssignmentId } else { New-ToolAssetRegistryId -Kind Assignment }
    $previousId = if ($null -eq $current) { '' } else { [string]$current.AssignmentId }
    $recorded = ConvertTo-ToolAssetRegistryUtcText $RecordedAtUtc
    $event = [pscustomobject][ordered]@{
        EventId=New-ToolAssetRegistryId -Kind Event; AssetId=$AssetId; DeviceId=[string]$asset[0].DeviceId; Sequence=$sequence; Action=$Action
        AssignmentId=$assignmentId; PreviousAssignmentId=if($Action -eq 'Reassign'){$previousId}else{''}
        AssigneeType=if($Action -eq 'Release'){''}else{$AssigneeType}
        AssigneeReference=if($Action -eq 'Release'){''}else{ConvertTo-ToolAssetRegistrySafeText $AssigneeReference 200}
        DisplayName=if($Action -eq 'Release'){''}else{ConvertTo-ToolAssetRegistrySafeText $DisplayName 200}
        EffectiveAtUtc=ConvertTo-ToolAssetRegistryUtcText $EffectiveAtUtc; RecordedAtUtc=$recorded
        RecordedBy=ConvertTo-ToolAssetRegistrySafeText $RecordedBy 120; Reason=ConvertTo-ToolAssetRegistrySafeText $Reason 500
    }
    $Store.Assignments = [object[]](@($Store.Assignments) + $event)
    $Store.UpdatedAtUtc = $recorded
    [void](Assert-ToolAssetRegistryStore $Store)
    return $event
}

function Get-ToolAssetAssignmentHistory {
    param([Parameter(Mandatory=$true)][object]$Store, [Parameter(Mandatory=$true)][string]$AssetId)
    return @($Store.Assignments | Where-Object { [string]$_.AssetId -eq $AssetId } | Sort-Object Sequence)
}

function Get-ToolAssetRegistryPaths {
    param([string]$RootPath = '')
    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $base = if ($env:ProgramData) { $env:ProgramData } else { [Environment]::GetFolderPath('CommonApplicationData') }
        $RootPath = Join-Path $base 'VietLicenSure\AssetRegistry'
    }
    $full = [IO.Path]::GetFullPath($RootPath)
    return [pscustomobject]@{ Root=$full; Store=Join-Path $full 'asset-registry-v1.json' }
}

function Write-ToolAssetRegistryStore {
    param([Parameter(Mandatory=$true)][object]$Store, [string]$RootPath = '')
    [void](Assert-ToolAssetRegistryStore $Store)
    $paths = Get-ToolAssetRegistryPaths -RootPath $RootPath
    if (-not (Test-Path -LiteralPath $paths.Root -PathType Container)) { [void](New-Item -ItemType Directory -Path $paths.Root -Force) }
    $Store.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $json = $Store | ConvertTo-Json -Depth 16
    $bytes = [Text.Encoding]::UTF8.GetByteCount($json)
    if ($bytes -gt $script:ToolAssetRegistryMaximumStoreBytes) { throw 'Asset Registry store exceeds the maximum size.' }
    $temporary = $paths.Store + '.tmp-' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $paths.Store -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
    return $paths.Store
}

function Read-ToolAssetRegistryStore {
    param([string]$RootPath = '', [switch]$CreateIfMissing)
    $paths = Get-ToolAssetRegistryPaths -RootPath $RootPath
    if (-not (Test-Path -LiteralPath $paths.Store -PathType Leaf)) {
        if (-not $CreateIfMissing) { return $null }
        $store = New-ToolAssetRegistryStore
        [void](Write-ToolAssetRegistryStore -Store $store -RootPath $paths.Root)
        return $store
    }
    $item = Get-Item -LiteralPath $paths.Store -ErrorAction Stop
    if ($item.Length -le 0 -or $item.Length -gt $script:ToolAssetRegistryMaximumStoreBytes) { throw 'Asset Registry store size is invalid.' }
    $store = Get-Content -LiteralPath $paths.Store -Raw -Encoding UTF8 | ConvertFrom-Json
    $store.Devices = [object[]]@($store.Devices)
    $store.Assets = [object[]]@($store.Assets)
    $store.Assignments = [object[]]@($store.Assignments)
    [void](Assert-ToolAssetRegistryStore $store)
    return $store
}

function Get-ToolAssetRegistryMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion=$script:ToolAssetRegistrySchemaVersion; DeviceIdVersion='1'; MatchingPolicyVersion='1'; AssignmentHistoryMode='AppendOnly'
        VolatileIdentityExcluded=[object[]]@('IpAddress','MacAddress','ComputerName','UserName','Department')
    }
}
