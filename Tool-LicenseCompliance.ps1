$script:ToolLicenseComplianceSchemaVersion = '1.0'
$script:ToolLicenseComplianceMaximumStoreBytes = 4194304
$script:ToolLicenseComplianceMaximumDocumentBytes = 26214400
$script:ToolLicenseComplianceAllowedScopes = @('Windows','Office','Software')
$script:ToolLicenseComplianceAllowedModels = @('OEM','Retail','VolumeMAK','VolumeKMS','Perpetual','Subscription','Commercial','Free','OpenSource','Unknown')
$script:ToolLicenseComplianceAllowedMetrics = @('Device','User','Concurrent','Organization','Unknown')
$script:ToolLicenseComplianceAllowedDocumentKinds = @('Invoice','Agreement','Certificate','LicenseEmail','PortalExport','Other')
$script:ToolLicenseComplianceAllowedDocumentExtensions = @('.pdf','.png','.jpg','.jpeg','.txt','.eml','.msg','.docx','.xlsx')

function ConvertTo-ToolLicenseComplianceSafeText {
    param([AllowNull()][object]$Value, [ValidateRange(1,4096)][int]$MaximumLength = 512)
    if (Get-Command ConvertTo-ToolEnterpriseSafeText -ErrorAction SilentlyContinue) {
        return (ConvertTo-ToolEnterpriseSafeText -Value $Value -MaximumLength $MaximumLength)
    }
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Replace("`0", '').Replace("`r", ' ').Replace("`n", ' ').Trim()
    $text = [regex]::Replace($text, '(?i)(?<![A-Z0-9])[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}(?![A-Z0-9])', '[REDACTED-PRODUCT-KEY]')
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}

function ConvertTo-ToolLicenseComplianceDate {
    param([AllowNull()][object]$Value, [switch]$AllowEmpty)
    $text = ConvertTo-ToolLicenseComplianceSafeText -Value $Value -MaximumLength 40
    if ([string]::IsNullOrWhiteSpace($text)) {
        if ($AllowEmpty) { return '' }
        throw 'A required date is missing.'
    }
    $date = [DateTime]::MinValue
    if (-not [DateTime]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture,
        ([Globalization.DateTimeStyles]::AssumeLocal -bor [Globalization.DateTimeStyles]::AllowWhiteSpaces), [ref]$date)) {
        throw ('Invalid date: ' + $text)
    }
    return $date.ToString('yyyy-MM-dd')
}

function Get-ToolLicenseComplianceIntegerSum {
    param([AllowNull()][object[]]$Items, [Parameter(Mandatory=$true)][string]$PropertyName)
    [int64]$total = 0
    foreach ($item in @($Items)) {
        if ($null -eq $item -or -not $item.PSObject.Properties[$PropertyName]) { continue }
        $total += [int64]$item.$PropertyName
    }
    return $total
}

function Get-ToolLicenseCompliancePaths {
    $enterprisePaths = Initialize-ToolEnterpriseStorage
    $root = Join-Path $enterprisePaths.Server 'compliance'
    return [pscustomobject][ordered]@{
        Root = $root
        Store = Join-Path $root 'entitlements-v1.json'
        Documents = Join-Path $root 'documents'
    }
}

function Initialize-ToolLicenseComplianceStorage {
    $paths = Get-ToolLicenseCompliancePaths
    foreach ($directory in @($paths.Root,$paths.Documents)) {
        if (Get-Command Test-ToolEnterpriseReparsePoint -ErrorAction SilentlyContinue) {
            if (Test-ToolEnterpriseReparsePoint -Path $directory) { throw ('Compliance storage cannot be a reparse point: ' + $directory) }
        }
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        if (Get-Command Test-ToolEnterpriseReparsePoint -ErrorAction SilentlyContinue) {
            if (Test-ToolEnterpriseReparsePoint -Path $directory) { throw ('Compliance storage cannot be a reparse point: ' + $directory) }
        }
    }
    return $paths
}

function New-ToolLicenseComplianceStore {
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolLicenseComplianceSchemaVersion
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
        Entitlements = @()
    }
}

function Test-ToolLicenseComplianceGuid {
    param([AllowNull()][object]$Value, [switch]$AllowEmpty)
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return [bool]$AllowEmpty }
    $parsed = [Guid]::Empty
    return [Guid]::TryParse($text, [ref]$parsed)
}

function Assert-ToolLicenseEntitlementRecord {
    param([Parameter(Mandatory=$true)][object]$Record)
    if (-not (Test-ToolLicenseComplianceGuid -Value $Record.EntitlementId)) { throw 'EntitlementId is invalid.' }
    if ([string]$Record.ProductScope -notin $script:ToolLicenseComplianceAllowedScopes) { throw 'ProductScope is invalid.' }
    if ([string]::IsNullOrWhiteSpace([string]$Record.ProductName)) { throw 'ProductName is required.' }
    if ([string]$Record.LicenseModel -notin $script:ToolLicenseComplianceAllowedModels) { throw 'LicenseModel is invalid.' }
    if ([string]$Record.Metric -notin $script:ToolLicenseComplianceAllowedMetrics) { throw 'Metric is invalid.' }
    if ([int64]$Record.PurchasedQuantity -lt 0 -or [int64]$Record.PurchasedQuantity -gt 1000000) { throw 'PurchasedQuantity is outside the supported range.' }
    foreach ($assignment in @($Record.Assignments)) {
        if ($null -eq $assignment -or @($assignment.PSObject.Properties).Count -eq 0) { continue }
        if (-not (Test-ToolLicenseComplianceGuid -Value $assignment.ClientId)) { throw 'Assignment ClientId is invalid.' }
        if ([int64]$assignment.Quantity -lt 1 -or [int64]$assignment.Quantity -gt 1000000) { throw 'Assignment quantity is invalid.' }
    }
    foreach ($document in @($Record.Documents)) {
        if ($null -eq $document -or @($document.PSObject.Properties).Count -eq 0) { continue }
        if (-not (Test-ToolLicenseComplianceGuid -Value $document.DocumentId)) { throw 'DocumentId is invalid.' }
        if ([string]$document.Kind -notin $script:ToolLicenseComplianceAllowedDocumentKinds) { throw 'Document kind is invalid.' }
        if ([string]$document.Sha256 -notmatch '^[0-9A-F]{64}$') { throw 'Document SHA-256 is invalid.' }
        if ([int64]$document.Size -lt 1 -or [int64]$document.Size -gt $script:ToolLicenseComplianceMaximumDocumentBytes) { throw 'Document size is invalid.' }
        if ([IO.Path]::GetFileName([string]$document.StoredName) -ne [string]$document.StoredName) { throw 'Stored document name is invalid.' }
        $storedExtension = [IO.Path]::GetExtension([string]$document.StoredName).ToLowerInvariant()
        if ($script:ToolLicenseComplianceAllowedDocumentExtensions -notcontains $storedExtension -or
            -not [string]::Equals(([IO.Path]::GetFileNameWithoutExtension([string]$document.StoredName)), ([string]$document.DocumentId), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Stored document identity is invalid.'
        }
    }
    return $true
}

function Read-ToolLicenseComplianceStore {
    $paths = Initialize-ToolLicenseComplianceStorage
    if (-not (Test-Path -LiteralPath $paths.Store -PathType Leaf)) { return (New-ToolLicenseComplianceStore) }
    $info = Get-Item -LiteralPath $paths.Store -Force
    if ($info.Length -le 0 -or $info.Length -gt $script:ToolLicenseComplianceMaximumStoreBytes) { throw 'Compliance store size is invalid.' }
    $store = Read-ToolEnterpriseJson -Path $paths.Store -MaximumBytes $script:ToolLicenseComplianceMaximumStoreBytes
    if (-not $store -or [string]$store.SchemaVersion -ne $script:ToolLicenseComplianceSchemaVersion) { throw 'Compliance store schema is unsupported.' }
    foreach ($record in @($store.Entitlements)) {
        if (-not $record.PSObject.Properties['Assignments'] -or $null -eq $record.Assignments -or
            ($record.Assignments -is [pscustomobject] -and @($record.Assignments.PSObject.Properties).Count -eq 0)) {
            $record | Add-Member -NotePropertyName Assignments -NotePropertyValue ([object[]]@()) -Force
        } else { $record.Assignments = [object[]]@($record.Assignments) }
        if (-not $record.PSObject.Properties['Documents'] -or $null -eq $record.Documents -or
            ($record.Documents -is [pscustomobject] -and @($record.Documents.PSObject.Properties).Count -eq 0)) {
            $record | Add-Member -NotePropertyName Documents -NotePropertyValue ([object[]]@()) -Force
        } else { $record.Documents = [object[]]@($record.Documents) }
        [void](Assert-ToolLicenseEntitlementRecord -Record $record)
    }
    return $store
}

function Write-ToolLicenseComplianceStore {
    param([Parameter(Mandatory=$true)][object]$Store)
    if ([string]$Store.SchemaVersion -ne $script:ToolLicenseComplianceSchemaVersion) { throw 'Compliance store schema is unsupported.' }
    if (@($Store.Entitlements).Count -gt 1000) { throw 'Compliance store entitlement limit exceeded.' }
    foreach ($record in @($Store.Entitlements)) { [void](Assert-ToolLicenseEntitlementRecord -Record $record) }
    $Store.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $paths = Initialize-ToolLicenseComplianceStorage
    Write-ToolEnterpriseJson -Path $paths.Store -Value $Store
    return $Store
}

function Get-ToolLicenseEntitlements {
    $store = Read-ToolLicenseComplianceStore
    return @($store.Entitlements | Sort-Object ProductScope,ProductName,EntitlementId)
}

function Set-ToolLicenseEntitlement {
    [CmdletBinding()]
    param(
        [string]$EntitlementId = '',
        [Parameter(Mandatory=$true)][ValidateSet('Windows','Office','Software')][string]$ProductScope,
        [string]$CatalogProductId = '',
        [Parameter(Mandatory=$true)][string]$ProductName,
        [string]$Vendor = '',
        [Parameter(Mandatory=$true)][ValidateSet('OEM','Retail','VolumeMAK','VolumeKMS','Perpetual','Subscription','Commercial','Free','OpenSource','Unknown')][string]$LicenseModel,
        [ValidateSet('Device','User','Concurrent','Organization','Unknown')][string]$Metric = 'Device',
        [ValidateRange(0,1000000)][int]$PurchasedQuantity = 0,
        [string]$Provider = '',
        [string]$InvoiceNumber = '',
        [string]$PurchaseDate = '',
        [string]$ValidFrom = '',
        [string]$ExpiresAt = '',
        [string]$Notes = ''
    )
    $store = Read-ToolLicenseComplianceStore
    $now = [DateTime]::UtcNow.ToString('o')
    if ([string]::IsNullOrWhiteSpace($EntitlementId)) { $EntitlementId = [Guid]::NewGuid().ToString('N') }
    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($EntitlementId, [ref]$parsed)) { throw 'EntitlementId is invalid.' }
    $EntitlementId = $parsed.ToString('N')
    $existing = @($store.Entitlements | Where-Object { [string]$_.EntitlementId -eq $EntitlementId } | Select-Object -First 1)
    [object[]]$assignments = @()
    [object[]]$documents = @()
    if ($existing.Count -gt 0) {
        $assignments = [object[]]@($existing[0].Assignments)
        $documents = [object[]]@($existing[0].Documents)
    }
    $record = [pscustomobject][ordered]@{
        EntitlementId = $EntitlementId
        ProductScope = $ProductScope
        CatalogProductId = ConvertTo-ToolLicenseComplianceSafeText $CatalogProductId 100
        ProductName = ConvertTo-ToolLicenseComplianceSafeText $ProductName 300
        Vendor = ConvertTo-ToolLicenseComplianceSafeText $Vendor 160
        LicenseModel = $LicenseModel
        Metric = $Metric
        PurchasedQuantity = [int]$PurchasedQuantity
        Provider = ConvertTo-ToolLicenseComplianceSafeText $Provider 220
        InvoiceNumber = ConvertTo-ToolLicenseComplianceSafeText $InvoiceNumber 120
        PurchaseDate = ConvertTo-ToolLicenseComplianceDate -Value $PurchaseDate -AllowEmpty
        ValidFrom = ConvertTo-ToolLicenseComplianceDate -Value $ValidFrom -AllowEmpty
        ExpiresAt = ConvertTo-ToolLicenseComplianceDate -Value $ExpiresAt -AllowEmpty
        Notes = ConvertTo-ToolLicenseComplianceSafeText $Notes 1500
        Assignments = $assignments
        Documents = $documents
        CreatedAtUtc = if ($existing.Count -gt 0) { [string]$existing[0].CreatedAtUtc } else { $now }
        UpdatedAtUtc = $now
    }
    [void](Assert-ToolLicenseEntitlementRecord -Record $record)
    $remaining = @($store.Entitlements | Where-Object { [string]$_.EntitlementId -ne $EntitlementId })
    $store.Entitlements = @($remaining + $record)
    [void](Write-ToolLicenseComplianceStore -Store $store)
    Write-ToolEnterpriseAudit -Scope Server -Event 'Compliance.EntitlementSaved' -Message 'License entitlement record saved.' -Data ([ordered]@{
        EntitlementId=$EntitlementId; ProductScope=$ProductScope; CatalogProductId=$record.CatalogProductId; PurchasedQuantity=$PurchasedQuantity
    })
    return $record
}

function Remove-ToolLicenseEntitlement {
    param([Parameter(Mandatory=$true)][string]$EntitlementId)
    $store = Read-ToolLicenseComplianceStore
    $record = @($store.Entitlements | Where-Object { [string]$_.EntitlementId -eq $EntitlementId } | Select-Object -First 1)
    if ($record.Count -eq 0) { return $false }
    $paths = Initialize-ToolLicenseComplianceStorage
    $documentPaths = @($record[0].Documents | ForEach-Object { Join-Path $paths.Documents ([string]$_.StoredName) })
    $stagedDocuments = @()
    try {
        foreach ($documentPath in $documentPaths) {
            if (-not (Test-Path -LiteralPath $documentPath -PathType Leaf)) { continue }
            $stagedPath = $documentPath + '.deleting-' + [Guid]::NewGuid().ToString('N')
            Move-Item -LiteralPath $documentPath -Destination $stagedPath -ErrorAction Stop
            $stagedDocuments += [pscustomobject]@{ Original=$documentPath; Staged=$stagedPath }
        }
    } catch {
        foreach ($item in @($stagedDocuments)) {
            if (Test-Path -LiteralPath $item.Staged -PathType Leaf) { Move-Item -LiteralPath $item.Staged -Destination $item.Original -Force -ErrorAction SilentlyContinue }
        }
        throw
    }
    $store.Entitlements = @($store.Entitlements | Where-Object { [string]$_.EntitlementId -ne $EntitlementId })
    try { [void](Write-ToolLicenseComplianceStore -Store $store) }
    catch {
        foreach ($item in @($stagedDocuments)) {
            if (Test-Path -LiteralPath $item.Staged -PathType Leaf) { Move-Item -LiteralPath $item.Staged -Destination $item.Original -Force -ErrorAction SilentlyContinue }
        }
        throw
    }
    foreach ($item in @($stagedDocuments)) {
        if (Test-Path -LiteralPath $item.Staged -PathType Leaf) { Remove-Item -LiteralPath $item.Staged -Force -ErrorAction Stop }
    }
    Write-ToolEnterpriseAudit -Scope Server -Event 'Compliance.EntitlementRemoved' -Message 'License entitlement record removed.' -Data ([ordered]@{ EntitlementId=$EntitlementId })
    return $true
}

function Set-ToolLicenseEntitlementAssignment {
    param(
        [Parameter(Mandatory=$true)][string]$EntitlementId,
        [Parameter(Mandatory=$true)][string]$ClientId,
        [ValidateRange(0,1000000)][int]$Quantity = 1,
        [string]$Notes = ''
    )
    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($ClientId, [ref]$parsed)) { throw 'ClientId is invalid.' }
    $clientIdNormalized = $parsed.ToString('N')
    $store = Read-ToolLicenseComplianceStore
    $record = @($store.Entitlements | Where-Object { [string]$_.EntitlementId -eq $EntitlementId } | Select-Object -First 1)
    if ($record.Count -eq 0) { throw 'Entitlement record was not found.' }
    $assignments = @($record[0].Assignments | Where-Object { [string]$_.ClientId -ne $clientIdNormalized })
    if ($Quantity -gt 0) {
        $assignments += [pscustomobject][ordered]@{
            ClientId=$clientIdNormalized; Quantity=[int]$Quantity; Notes=ConvertTo-ToolLicenseComplianceSafeText $Notes 500
            AssignedAtUtc=[DateTime]::UtcNow.ToString('o')
        }
    }
    $record[0].Assignments = [object[]]@($assignments)
    $record[0].UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    [void](Write-ToolLicenseComplianceStore -Store $store)
    Write-ToolEnterpriseAudit -Scope Server -Event 'Compliance.AssignmentChanged' -Message 'License entitlement assignment changed.' -Data ([ordered]@{
        EntitlementId=$EntitlementId; ClientReference=(Get-ToolEnterpriseStableClientReference -ClientId $clientIdNormalized); Quantity=$Quantity
    })
    return $record[0]
}

function Add-ToolLicenseEntitlementDocument {
    param(
        [Parameter(Mandatory=$true)][string]$EntitlementId,
        [Parameter(Mandatory=$true)][string]$Path,
        [ValidateSet('Invoice','Agreement','Certificate','LicenseEmail','PortalExport','Other')][string]$Kind = 'Other'
    )
    $sourcePath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw 'Document file was not found.' }
    $source = Get-Item -LiteralPath $sourcePath -Force
    if (($source.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Document file cannot be a reparse point.' }
    if ($source.Length -le 0 -or $source.Length -gt $script:ToolLicenseComplianceMaximumDocumentBytes) { throw 'Document file size is outside the supported range.' }
    $extension = $source.Extension.ToLowerInvariant()
    if ($script:ToolLicenseComplianceAllowedDocumentExtensions -notcontains $extension) { throw 'Document file type is not allowed.' }
    $store = Read-ToolLicenseComplianceStore
    $record = @($store.Entitlements | Where-Object { [string]$_.EntitlementId -eq $EntitlementId } | Select-Object -First 1)
    if ($record.Count -eq 0) { throw 'Entitlement record was not found.' }
    if (@($record[0].Documents).Count -ge 20) { throw 'Document limit for this entitlement was reached.' }
    $paths = Initialize-ToolLicenseComplianceStorage
    $documentId = [Guid]::NewGuid().ToString('N')
    $storedName = $documentId + $extension
    $destination = Join-Path $paths.Documents $storedName
    try {
        Copy-Item -LiteralPath $sourcePath -Destination $destination -Force -ErrorAction Stop
        $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        $document = [pscustomobject][ordered]@{
            DocumentId=$documentId; Kind=$Kind
            OriginalName=ConvertTo-ToolLicenseComplianceSafeText $source.Name 260
            StoredName=$storedName; Sha256=$hash; Size=[int64]$source.Length
            AddedAtUtc=[DateTime]::UtcNow.ToString('o')
        }
        $record[0].Documents = @($record[0].Documents) + $document
        $record[0].UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
        [void](Write-ToolLicenseComplianceStore -Store $store)
    } catch {
        if (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue }
        throw
    }
    Write-ToolEnterpriseAudit -Scope Server -Event 'Compliance.DocumentAdded' -Message 'License evidence document added.' -Data ([ordered]@{
        EntitlementId=$EntitlementId; DocumentId=$documentId; Kind=$Kind; Sha256=$hash; Size=[int64]$source.Length
    })
    return $document
}

function Remove-ToolLicenseEntitlementDocument {
    param([Parameter(Mandatory=$true)][string]$EntitlementId,[Parameter(Mandatory=$true)][string]$DocumentId)
    $store = Read-ToolLicenseComplianceStore
    $record = @($store.Entitlements | Where-Object { [string]$_.EntitlementId -eq $EntitlementId } | Select-Object -First 1)
    if ($record.Count -eq 0) { return $false }
    $document = @($record[0].Documents | Where-Object { [string]$_.DocumentId -eq $DocumentId } | Select-Object -First 1)
    if ($document.Count -eq 0) { return $false }
    $paths = Initialize-ToolLicenseComplianceStorage
    $documentPath = Join-Path $paths.Documents ([string]$document[0].StoredName)
    $stagedPath = ''
    if (Test-Path -LiteralPath $documentPath -PathType Leaf) {
        $stagedPath = $documentPath + '.deleting-' + [Guid]::NewGuid().ToString('N')
        Move-Item -LiteralPath $documentPath -Destination $stagedPath -ErrorAction Stop
    }
    $record[0].Documents = [object[]]@($record[0].Documents | Where-Object { [string]$_.DocumentId -ne $DocumentId })
    $record[0].UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    try { [void](Write-ToolLicenseComplianceStore -Store $store) }
    catch {
        if ($stagedPath -and (Test-Path -LiteralPath $stagedPath -PathType Leaf)) { Move-Item -LiteralPath $stagedPath -Destination $documentPath -Force -ErrorAction SilentlyContinue }
        throw
    }
    if ($stagedPath -and (Test-Path -LiteralPath $stagedPath -PathType Leaf)) { Remove-Item -LiteralPath $stagedPath -Force -ErrorAction Stop }
    Write-ToolEnterpriseAudit -Scope Server -Event 'Compliance.DocumentRemoved' -Message 'License evidence document removed.' -Data ([ordered]@{
        EntitlementId=$EntitlementId; DocumentId=$DocumentId
    })
    return $true
}

function Get-ToolLicenseComplianceSoftwareInventory {
    param([ValidateRange(1,500)][int]$MaximumItems = 300)
    try {
        if (-not (Get-Command Get-ToolInstalledSoftwareInventory -ErrorAction SilentlyContinue)) {
            $inventoryPath = Join-Path $PSScriptRoot 'Tool-SoftwareInventory.ps1'
            if (Test-Path -LiteralPath $inventoryPath -PathType Leaf) { . $inventoryPath }
        }
        if (-not (Get-Command Get-ToolInstalledSoftwareInventory -ErrorAction SilentlyContinue)) { return @() }
        $catalog = if (Get-Command Get-ToolSoftwareLicenseCatalog -ErrorAction SilentlyContinue) { Get-ToolSoftwareLicenseCatalog } else { $null }
        $output = New-Object System.Collections.Generic.List[object]
        foreach ($application in @(Get-ToolInstalledSoftwareInventory | Sort-Object Name,Publisher)) {
            if ($output.Count -ge $MaximumItems) { break }
            if ($application.PSObject.Properties['IsSystemComponent'] -and [bool]$application.IsSystemComponent) { continue }
            $match = if (Get-Command Find-ToolSoftwareCatalogMatch -ErrorAction SilentlyContinue) { Find-ToolSoftwareCatalogMatch -Application $application -Catalog $catalog } else { $null }
            $product = if ($match) { $match.Product } else { $null }
            $rawModel = if ($product -and $product.PSObject.Properties['LicenseModel']) { [string]$product.LicenseModel } else { 'Unknown' }
            $model = if (Get-Command ConvertTo-ToolSoftwareLicenseModel -ErrorAction SilentlyContinue) { ConvertTo-ToolSoftwareLicenseModel $rawModel } else { 'Unknown' }
            $productId = if ($product -and $product.PSObject.Properties['Id']) { ConvertTo-ToolLicenseComplianceSafeText $product.Id 100 } else { '' }
            $name = ConvertTo-ToolLicenseComplianceSafeText $application.Name 260
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            [void]$output.Add([pscustomobject][ordered]@{
                CatalogProductId=$productId; Name=$name
                Publisher=ConvertTo-ToolLicenseComplianceSafeText $application.Publisher 160
                LicenseModel=$model
                ClassificationConfidence=$(if ($product) {'CatalogMatched'} elseif ($match -and [string]$match.Reason -eq 'CatalogUntrusted') {'CatalogRejected'} else {'Unknown'})
                NeedsReview=[bool]($model -in @('Paid','Subscription','Trial','Unknown'))
            })
        }
        return $output.ToArray()
    } catch { return @() }
}

function Get-ToolLicenseComplianceFleetObservations {
    $observations = New-Object System.Collections.Generic.List[object]
    $paths = Initialize-ToolEnterpriseStorage
    foreach ($client in @(Get-ToolEnterpriseServerClients)) {
        $clientId = [string]$client.ClientId
        if (-not (Test-ToolLicenseComplianceGuid -Value $clientId)) { continue }
        $clientRef = Get-ToolEnterpriseStableClientReference -ClientId $clientId
        $computer = ConvertTo-ToolLicenseComplianceSafeText $client.ComputerName 100
        if ([string]$client.WindowsStatus -ne 'NotDetected') {
            [void]$observations.Add([pscustomobject][ordered]@{ ClientId=$clientId; ClientReference=$clientRef; ComputerName=$computer; ProductScope='Windows'; CatalogProductId=''; ProductName='Microsoft Windows'; LicenseModel=ConvertTo-ToolLicenseComplianceSafeText $client.WindowsChannel 80; TechnicalStatus=ConvertTo-ToolLicenseComplianceSafeText $client.WindowsStatus 80 })
        }
        if ([string]$client.OfficeStatus -ne 'NotDetected') {
            [void]$observations.Add([pscustomobject][ordered]@{ ClientId=$clientId; ClientReference=$clientRef; ComputerName=$computer; ProductScope='Office'; CatalogProductId=''; ProductName='Microsoft Office'; LicenseModel=ConvertTo-ToolLicenseComplianceSafeText $client.OfficeChannel 80; TechnicalStatus=ConvertTo-ToolLicenseComplianceSafeText $client.OfficeStatus 80 })
        }
        $reportPath = Join-Path (Join-Path $paths.ServerReports $clientId) 'latest.json'
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { continue }
        try {
            $report = Read-ToolEnterpriseJson -Path $reportPath -MaximumBytes $script:ToolEnterpriseMaximumRequestBytes
            foreach ($software in @($report.SoftwareInventory)) {
                [void]$observations.Add([pscustomobject][ordered]@{
                    ClientId=$clientId; ClientReference=$clientRef; ComputerName=$computer; ProductScope='Software'
                    CatalogProductId=ConvertTo-ToolLicenseComplianceSafeText $software.CatalogProductId 100
                    ProductName=ConvertTo-ToolLicenseComplianceSafeText $software.Name 260
                    LicenseModel=ConvertTo-ToolLicenseComplianceSafeText $software.LicenseModel 80
                    TechnicalStatus='InventoryOnly'
                })
            }
        } catch {}
    }
    return $observations.ToArray()
}

function Test-ToolLicenseEntitlementMatchesObservation {
    param([Parameter(Mandatory=$true)][object]$Entitlement,[Parameter(Mandatory=$true)][object]$Observation)
    if ([string]$Entitlement.ProductScope -ne [string]$Observation.ProductScope) { return $false }
    if ([string]$Entitlement.ProductScope -ne 'Software') { return $true }
    $catalogId = ([string]$Entitlement.CatalogProductId).Trim()
    if (-not [string]::IsNullOrWhiteSpace($catalogId)) {
        return [string]::Equals($catalogId, [string]$Observation.CatalogProductId, [StringComparison]::OrdinalIgnoreCase)
    }
    return [string]::Equals(([string]$Entitlement.ProductName).Trim(), ([string]$Observation.ProductName).Trim(), [StringComparison]::OrdinalIgnoreCase)
}

function Get-ToolLicenseComplianceReconciliation {
    $entitlements = @(Get-ToolLicenseEntitlements)
    $observations = @(Get-ToolLicenseComplianceFleetObservations)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($entitlement in $entitlements) {
        $matches = @($observations | Where-Object { Test-ToolLicenseEntitlementMatchesObservation -Entitlement $entitlement -Observation $_ })
        $installedClients = @($matches | ForEach-Object { [string]$_.ClientId } | Where-Object { $_ } | Select-Object -Unique)
        $installed = [int]$installedClients.Count
        $assigned = [int](Get-ToolLicenseComplianceIntegerSum -Items @($entitlement.Assignments) -PropertyName Quantity)
        $purchased = [int]$entitlement.PurchasedQuantity
        $available = [int]($purchased - $assigned)
        $documents = @($entitlement.Documents).Count
        $expired = $false
        if (-not [string]::IsNullOrWhiteSpace([string]$entitlement.ExpiresAt)) {
            $expiry = [DateTime]::MinValue
            if ([DateTime]::TryParse([string]$entitlement.ExpiresAt, [ref]$expiry)) { $expired = $expiry.Date -lt [DateTime]::Today }
        }
        $state = if ($expired -or $installed -gt $purchased -or $assigned -gt $purchased) { 'Critical' }
            elseif ($documents -eq 0 -or $installed -gt $assigned) { 'NeedsReview' }
            else { 'Compliant' }
        [void]$rows.Add([pscustomobject][ordered]@{
            EntitlementId=[string]$entitlement.EntitlementId; ProductScope=[string]$entitlement.ProductScope
            CatalogProductId=[string]$entitlement.CatalogProductId; ProductName=[string]$entitlement.ProductName
            LicenseModel=[string]$entitlement.LicenseModel; Metric=[string]$entitlement.Metric
            Purchased=$purchased; Assigned=$assigned; Installed=$installed; Available=$available
            DocumentCount=$documents; ExpiresAt=[string]$entitlement.ExpiresAt; ComplianceState=$state
        })
    }
    $coveredKeys = @{}
    foreach ($row in $rows) {
        $key = ([string]$row.ProductScope + '|' + [string]$row.CatalogProductId + '|' + [string]$row.ProductName).ToLowerInvariant()
        $coveredKeys[$key] = $true
    }
    $uncovered = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($observations | Where-Object { $_.ProductScope -eq 'Software' -and $_.LicenseModel -in @('Paid','Subscription','Trial','Unknown') } | Group-Object CatalogProductId,ProductName)) {
        $first = @($group.Group)[0]
        $matched = @($entitlements | Where-Object { Test-ToolLicenseEntitlementMatchesObservation -Entitlement $_ -Observation $first }).Count -gt 0
        if (-not $matched) {
            [void]$uncovered.Add([pscustomobject][ordered]@{
                CatalogProductId=[string]$first.CatalogProductId; ProductName=[string]$first.ProductName
                LicenseModel=[string]$first.LicenseModel
                InstalledClients=@($group.Group | ForEach-Object ClientId | Select-Object -Unique).Count
                ComplianceState='NeedsReview'
            })
        }
    }
    return [pscustomobject][ordered]@{ Rows=$rows.ToArray(); Uncovered=$uncovered.ToArray(); Observations=$observations }
}

function Get-ToolLicenseAdvisorResult {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Windows','Office','Software')][string]$ProductScope,
        [string]$TechnicalStatus = '', [string]$Channel = '', [string]$LicenseModel = 'Unknown',
        [ValidateSet('Compliant','NeedsReview','Critical','NotVerified')][string]$EntitlementStatus = 'NotVerified'
    )
    $technicalGood = [bool]($TechnicalStatus -in @('Activated','Licensed','FreeOrIncluded','GenuineVerified'))
    $risk = if ($EntitlementStatus -eq 'Critical') { 'High' }
        elseif (-not $technicalGood -and $TechnicalStatus -notin @('InventoryOnly','NotDetected','')) { 'High' }
        elseif ($EntitlementStatus -in @('NeedsReview','NotVerified') -or $LicenseModel -in @('Paid','Subscription','Trial','Unknown')) { 'Review' }
        else { 'Low' }
    $explanation = if ($ProductScope -in @('Windows','Office')) {
        if ($technicalGood) { 'Technical activation is present. Legal entitlement depends on purchase records, agreement, account, or licensing portal evidence.' }
        else { 'Technical activation is not confirmed. Review the licensing channel and official activation source before making a compliance conclusion.' }
    } elseif ($LicenseModel -in @('Free','OpenSource')) {
        'The signed catalog classifies this product as free or open source; its specific license terms still apply.'
    } else {
        'The product may require a commercial entitlement. Installation or activation alone does not prove the right to use it.'
    }
    $recommendation = if ($EntitlementStatus -eq 'Critical') { 'Reconcile purchased quantity, assignments, expiry, and supporting documents immediately.' }
        elseif ($EntitlementStatus -eq 'NeedsReview' -or $EntitlementStatus -eq 'NotVerified') { 'Attach authoritative purchase evidence and assign the entitlement to the correct device or user.' }
        elseif (-not $technicalGood -and $ProductScope -in @('Windows','Office')) { 'Use the official vendor activation workflow and then collect a fresh report.' }
        else { 'Retain the supporting evidence and review it at renewal or when the device assignment changes.' }
    return [pscustomobject][ordered]@{
        ProductScope=$ProductScope; TechnicalStatus=ConvertTo-ToolLicenseComplianceSafeText $TechnicalStatus 80
        Channel=ConvertTo-ToolLicenseComplianceSafeText $Channel 100; LicenseModel=ConvertTo-ToolLicenseComplianceSafeText $LicenseModel 80
        EntitlementStatus=$EntitlementStatus; Risk=$risk
        FindingCode=$(if ($ProductScope -in @('Windows','Office')) { if ($technicalGood) {'TechnicalActivationPresent'} else {'TechnicalActivationNotConfirmed'} } elseif ($LicenseModel -in @('Free','OpenSource')) {'FreeOrOpenSourceClassification'} else {'CommercialEntitlementRequired'})
        RecommendationCode=$(if ($EntitlementStatus -eq 'Critical') {'ReconcileImmediately'} elseif ($EntitlementStatus -in @('NeedsReview','NotVerified')) {'AttachEvidenceAndAssign'} elseif (-not $technicalGood -and $ProductScope -in @('Windows','Office')) {'UseOfficialActivation'} else {'RetainEvidence'})
        LimitationCode='LegalEntitlementNotProven'
        Explanation=$explanation; Recommendation=$recommendation
        Limitation='No result in this advisor independently proves legal ownership or authenticity.'
    }
}

function Get-ToolLicenseComplianceSnapshot {
    $reconciliation = Get-ToolLicenseComplianceReconciliation
    $rows = @($reconciliation.Rows)
    $uncovered = @($reconciliation.Uncovered)
    $critical = @($rows | Where-Object ComplianceState -eq 'Critical').Count
    $review = @($rows | Where-Object ComplianceState -eq 'NeedsReview').Count + $uncovered.Count
    $compliant = @($rows | Where-Object ComplianceState -eq 'Compliant').Count
    $purchased = [int](Get-ToolLicenseComplianceIntegerSum -Items $rows -PropertyName Purchased)
    $assigned = [int](Get-ToolLicenseComplianceIntegerSum -Items $rows -PropertyName Assigned)
    $installed = [int](Get-ToolLicenseComplianceIntegerSum -Items $rows -PropertyName Installed)
    $available = [int](Get-ToolLicenseComplianceIntegerSum -Items $rows -PropertyName Available)
    $denominator = [Math]::Max(1, ($compliant + $review + ($critical * 2)))
    $score = [int][Math]::Max(0, [Math]::Min(100, [Math]::Round((100.0 * $compliant) / $denominator)))
    return [pscustomobject][ordered]@{
        SchemaVersion=$script:ToolLicenseComplianceSchemaVersion; GeneratedAtUtc=[DateTime]::UtcNow.ToString('o')
        Summary=[ordered]@{
            AssuranceScore=$score; Compliant=$compliant; NeedsReview=$review; Critical=$critical
            Purchased=$purchased; Assigned=$assigned; Installed=$installed; Available=$available
            EntitlementRecords=$rows.Count; UncoveredCommercialProducts=$uncovered.Count
        }
        Entitlements=$rows; Uncovered=$uncovered
        Disclaimer='Technical activation and catalog classification do not independently prove legal entitlement. Authoritative documents and licensing portals remain required.'
    }
}
