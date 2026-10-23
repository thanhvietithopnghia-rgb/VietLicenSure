$script:ToolLicenseComplianceSchemaVersion = '1.0'
$script:ToolLicenseComplianceMaximumStoreBytes = 4194304
$script:ToolLicenseComplianceMaximumDocumentBytes = 26214400
$script:ToolLicenseComplianceAllowedScopes = @('Windows','Office','Software')
$script:ToolLicenseComplianceAllowedModels = @('OEM','Retail','VolumeMAK','VolumeKMS','Perpetual','Subscription','Commercial','Free','OpenSource','Unknown')
$script:ToolLicenseComplianceAllowedMetrics = @('Device','User','Concurrent','Organization','Unknown')
$script:ToolLicenseComplianceAllowedDocumentKinds = @('Invoice','Agreement','Certificate','LicenseEmail','PortalExport','Other')
$script:ToolLicenseComplianceAllowedDocumentExtensions = @('.pdf','.png','.jpg','.jpeg','.txt','.eml','.msg','.doc','.docx','.xls','.xlsx','.json')
$script:ToolLicenseComplianceAllowedDocumentVerificationStatuses = @('Attached','Verified')
$script:ToolLicenseAdvisorSchemaVersion = '1.0'
$script:ToolLicenseAdvisorAllowedConfidence = @('Confirmed','High','Medium','Low','Informational')
$toolDetectionEnginePath = Join-Path $PSScriptRoot 'Tool-DetectionEngine.ps1'
if (-not (Get-Command New-ToolDetectionFinding -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path -LiteralPath $toolDetectionEnginePath -PathType Leaf)) { throw 'Missing Tool-DetectionEngine.ps1.' }
    . $toolDetectionEnginePath
}

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
        $verificationStatus = [string]$document.VerificationStatus
        if ($verificationStatus -notin $script:ToolLicenseComplianceAllowedDocumentVerificationStatuses) { throw 'Document verification status is invalid.' }
        if ($verificationStatus -eq 'Verified') {
            if ([string]::IsNullOrWhiteSpace([string]$document.VerifiedBy) -or
                [string]::IsNullOrWhiteSpace([string]$document.VerificationSource) -or
                [string]::IsNullOrWhiteSpace([string]$document.VerificationScope)) {
                throw 'Verified document metadata is incomplete.'
            }
            $verifiedAt = [DateTime]::MinValue
            if (-not [DateTime]::TryParse([string]$document.VerifiedAtUtc, [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind, [ref]$verifiedAt)) {
                throw 'Verified document timestamp is invalid.'
            }
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
        } else {
            $record.Documents = [object[]]@($record.Documents)
            foreach ($document in @($record.Documents)) {
                if (-not $document.PSObject.Properties['VerificationStatus']) { $document | Add-Member -NotePropertyName VerificationStatus -NotePropertyValue 'Attached' -Force }
                foreach ($name in @('VerifiedBy','VerifiedAtUtc','VerificationSource','VerificationScope','VerificationNotes')) {
                    if (-not $document.PSObject.Properties[$name]) { $document | Add-Member -NotePropertyName $name -NotePropertyValue '' -Force }
                }
            }
        }
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
            VerificationStatus='Attached'; VerifiedBy=''; VerifiedAtUtc=''
            VerificationSource=''; VerificationScope=''; VerificationNotes=''
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

function Set-ToolLicenseEntitlementDocumentVerification {
    param(
        [Parameter(Mandatory=$true)][string]$EntitlementId,
        [Parameter(Mandatory=$true)][string]$DocumentId,
        [Parameter(Mandatory=$true)][ValidateSet('Attached','Verified')][string]$Status,
        [string]$VerifiedBy = '',
        [string]$VerificationSource = '',
        [string]$VerificationScope = '',
        [string]$VerificationNotes = ''
    )
    $store = Read-ToolLicenseComplianceStore
    $record = @($store.Entitlements | Where-Object { [string]$_.EntitlementId -eq $EntitlementId } | Select-Object -First 1)
    if ($record.Count -eq 0) { throw 'Entitlement record was not found.' }
    $document = @($record[0].Documents | Where-Object { [string]$_.DocumentId -eq $DocumentId } | Select-Object -First 1)
    if ($document.Count -eq 0) { throw 'Evidence document was not found.' }
    if ($Status -eq 'Verified') {
        $safeVerifier = ConvertTo-ToolLicenseComplianceSafeText $VerifiedBy 200
        $safeSource = ConvertTo-ToolLicenseComplianceSafeText $VerificationSource 300
        $safeScope = ConvertTo-ToolLicenseComplianceSafeText $VerificationScope 600
        if ([string]::IsNullOrWhiteSpace($safeVerifier) -or [string]::IsNullOrWhiteSpace($safeSource) -or [string]::IsNullOrWhiteSpace($safeScope)) {
            throw 'Verifier, verification source and entitlement scope are required.'
        }
        $document[0].VerificationStatus = 'Verified'
        $document[0].VerifiedBy = $safeVerifier
        $document[0].VerifiedAtUtc = [DateTime]::UtcNow.ToString('o')
        $document[0].VerificationSource = $safeSource
        $document[0].VerificationScope = $safeScope
        $document[0].VerificationNotes = ConvertTo-ToolLicenseComplianceSafeText $VerificationNotes 1500
    } else {
        $document[0].VerificationStatus = 'Attached'
        $document[0].VerifiedBy = ''
        $document[0].VerifiedAtUtc = ''
        $document[0].VerificationSource = ''
        $document[0].VerificationScope = ''
        $document[0].VerificationNotes = ''
    }
    $record[0].UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    [void](Write-ToolLicenseComplianceStore -Store $store)
    Write-ToolEnterpriseAudit -Scope Server -Event 'Compliance.DocumentVerificationChanged' -Message 'License evidence verification status changed.' -Data ([ordered]@{
        EntitlementId=$EntitlementId; DocumentId=$DocumentId; VerificationStatus=$Status
    })
    return $document[0]
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

function ConvertTo-ToolLicenseComplianceInventoryResult {
    param(
        [AllowNull()][object[]]$Applications,
        [ValidateRange(1,500)][int]$MaximumItems = 300,
        [AllowNull()][object]$CollectionMetadata,
        [AllowNull()][object]$Catalog
    )
    $eligible = New-Object System.Collections.Generic.List[object]
    foreach ($application in @($Applications | Sort-Object Name,Publisher)) {
        if ($null -eq $application) { continue }
        if ($application.PSObject.Properties['IsSystemComponent'] -and [bool]$application.IsSystemComponent) { continue }
        $name = ConvertTo-ToolLicenseComplianceSafeText $application.Name 260
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $match = if (Get-Command Find-ToolSoftwareCatalogMatch -ErrorAction SilentlyContinue) { Find-ToolSoftwareCatalogMatch -Application $application -Catalog $Catalog } else { $null }
        $product = if ($match) { $match.Product } else { $null }
        $rawModel = if ($product -and $product.PSObject.Properties['LicenseModel']) { [string]$product.LicenseModel } else { 'Unknown' }
        $model = if (Get-Command ConvertTo-ToolSoftwareLicenseModel -ErrorAction SilentlyContinue) { ConvertTo-ToolSoftwareLicenseModel $rawModel } else { 'Unknown' }
        $productId = if ($product -and $product.PSObject.Properties['Id']) { ConvertTo-ToolLicenseComplianceSafeText $product.Id 100 } else { '' }
        [void]$eligible.Add([pscustomobject][ordered]@{
            CatalogProductId=$productId; Name=$name
            Publisher=ConvertTo-ToolLicenseComplianceSafeText $application.Publisher 160
            LicenseModel=$model
            ClassificationConfidence=$(if ($product) {'CatalogMatched'} elseif ($match -and [string]$match.Reason -eq 'CatalogUntrusted') {'CatalogRejected'} else {'Unknown'})
            NeedsReview=[bool]($model -in @('Paid','Subscription','Trial','Unknown'))
        })
    }
    $included = @($eligible.ToArray() | Select-Object -First $MaximumItems)
    $omitted = [Math]::Max(0, ($eligible.Count - $included.Count))
    $completeMachineRead = [bool]($CollectionMetadata -and $CollectionMetadata.PSObject.Properties['CompleteMachineRead'] -and [bool]$CollectionMetadata.CompleteMachineRead)
    $coverageStatus = if ($omitted -gt 0 -or -not $completeMachineRead) { 'Partial' } else { 'Complete' }
    $reason = if ($omitted -gt 0) { 'MaximumItemsReached' } elseif (-not $completeMachineRead) { 'PrivilegeLimited' } else { '' }
    return [pscustomobject][ordered]@{
        SchemaVersion='1.0'; CoverageStatus=$coverageStatus; CoverageReason=$reason
        DiscoveredCount=[int]$eligible.Count; IncludedCount=[int]$included.Count; OmittedCount=[int]$omitted
        MaximumItems=[int]$MaximumItems; CompleteMachineRead=$completeMachineRead
        CollectedAtUtc=[DateTime]::UtcNow.ToString('o'); Items=[object[]]$included
    }
}

function Get-ToolLicenseComplianceSoftwareInventory {
    param([ValidateRange(1,500)][int]$MaximumItems = 300, [switch]$IncludeMetadata)
    $result = $null
    try {
        if (-not (Get-Command Get-ToolInstalledSoftwareInventory -ErrorAction SilentlyContinue)) {
            $inventoryPath = Join-Path $PSScriptRoot 'Tool-SoftwareInventory.ps1'
            if (Test-Path -LiteralPath $inventoryPath -PathType Leaf) { . $inventoryPath }
        }
        if (-not (Get-Command Get-ToolInstalledSoftwareInventory -ErrorAction SilentlyContinue)) { throw 'SoftwareInventoryCommandUnavailable' }
        $applications = @(Get-ToolInstalledSoftwareInventory)
        $metadata = if (Get-Command Get-ToolSoftwareInventoryCollectionMetadata -ErrorAction SilentlyContinue) { Get-ToolSoftwareInventoryCollectionMetadata } else { $null }
        $catalog = if (Get-Command Get-ToolSoftwareLicenseCatalog -ErrorAction SilentlyContinue) { Get-ToolSoftwareLicenseCatalog } else { $null }
        $result = ConvertTo-ToolLicenseComplianceInventoryResult -Applications $applications -MaximumItems $MaximumItems -CollectionMetadata $metadata -Catalog $catalog
    } catch {
        $result = [pscustomobject][ordered]@{
            SchemaVersion='1.0'; CoverageStatus='Failed'; CoverageReason='InventoryCollectionFailed'
            DiscoveredCount=0; IncludedCount=0; OmittedCount=0; MaximumItems=[int]$MaximumItems
            CompleteMachineRead=$false; CollectedAtUtc=[DateTime]::UtcNow.ToString('o'); Items=[object[]]@()
        }
    }
    if ($IncludeMetadata) { return $result }
    return @($result.Items)
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

function Get-ToolLicenseComplianceFleetCoverage {
    $coverage = New-Object System.Collections.Generic.List[object]
    $paths = Initialize-ToolEnterpriseStorage
    foreach ($client in @(Get-ToolEnterpriseServerClients)) {
        $clientId = [string]$client.ClientId
        if (-not (Test-ToolLicenseComplianceGuid -Value $clientId)) { continue }
        $clientReference = Get-ToolEnterpriseStableClientReference -ClientId $clientId
        $reportPath = Join-Path (Join-Path $paths.ServerReports $clientId) 'latest.json'
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
            [void]$coverage.Add([pscustomobject][ordered]@{ ClientReference=$clientReference; CoverageStatus='Failed'; CoverageReason='ReportMissing'; IncludedCount=0; OmittedCount=0 })
            continue
        }
        try {
            $report = Read-ToolEnterpriseJson -Path $reportPath -MaximumBytes $script:ToolEnterpriseMaximumRequestBytes
            $metadata = if ($report.PSObject.Properties['SoftwareInventoryCoverage']) { $report.SoftwareInventoryCoverage } else { $null }
            $status = if ($metadata -and [string]$metadata.CoverageStatus -in @('Complete','Partial','Failed')) { [string]$metadata.CoverageStatus } else { 'Partial' }
            $reason = if (-not $metadata) {
                'CoverageMetadataMissing'
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$metadata.CoverageReason)) {
                ConvertTo-ToolLicenseComplianceSafeText $metadata.CoverageReason 120
            } else {
                ''
            }
            [void]$coverage.Add([pscustomobject][ordered]@{
                ClientReference=$clientReference; CoverageStatus=$status; CoverageReason=$reason
                IncludedCount=$(if ($metadata -and $metadata.PSObject.Properties['IncludedCount']) { [int]$metadata.IncludedCount } else { [int]@($report.SoftwareInventory).Count })
                OmittedCount=$(if ($metadata -and $metadata.PSObject.Properties['OmittedCount']) { [int]$metadata.OmittedCount } else { 0 })
            })
        } catch {
            [void]$coverage.Add([pscustomobject][ordered]@{ ClientReference=$clientReference; CoverageStatus='Failed'; CoverageReason='ReportReadFailed'; IncludedCount=0; OmittedCount=0 })
        }
    }
    return $coverage.ToArray()
}

function Test-ToolLicenseEntitlementMatchesObservation {
    param([Parameter(Mandatory=$true)][object]$Entitlement,[Parameter(Mandatory=$true)][object]$Observation)
    if ([string]$Entitlement.ProductScope -ne [string]$Observation.ProductScope) { return $false }
    if ([string]$Entitlement.ProductScope -ne 'Software') {
        $entitlementProductId = ([string]$Entitlement.CatalogProductId).Trim()
        $observationProductId = ([string]$Observation.CatalogProductId).Trim()
        if ([string]::IsNullOrWhiteSpace($entitlementProductId) -or [string]::IsNullOrWhiteSpace($observationProductId)) { return $false }
        return [string]::Equals($entitlementProductId, $observationProductId, [StringComparison]::OrdinalIgnoreCase)
    }
    $catalogId = ([string]$Entitlement.CatalogProductId).Trim()
    if (-not [string]::IsNullOrWhiteSpace($catalogId)) {
        return [string]::Equals($catalogId, [string]$Observation.CatalogProductId, [StringComparison]::OrdinalIgnoreCase)
    }
    return [string]::Equals(([string]$Entitlement.ProductName).Trim(), ([string]$Observation.ProductName).Trim(), [StringComparison]::OrdinalIgnoreCase)
}

function Get-ToolLicenseComplianceEntitlementPoolKey {
    param([Parameter(Mandatory=$true)][object]$Entitlement)
    $scope = ([string]$Entitlement.ProductScope).Trim().ToLowerInvariant()
    $metric = ([string]$Entitlement.Metric).Trim().ToLowerInvariant()
    $model = ([string]$Entitlement.LicenseModel).Trim().ToLowerInvariant()
    $catalogId = ([string]$Entitlement.CatalogProductId).Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($catalogId)) { $identity = 'catalog:' + $catalogId }
    elseif ($scope -eq 'software') { $identity = 'name:' + ([string]$Entitlement.ProductName).Trim().ToLowerInvariant() }
    else { $identity = 'entitlement:' + ([string]$Entitlement.EntitlementId).Trim().ToLowerInvariant() }
    return ($scope + '|' + $identity + '|' + $metric + '|' + $model)
}

function Get-ToolLicenseComplianceReconciliation {
    $entitlements = @(Get-ToolLicenseEntitlements)
    $observations = @(Get-ToolLicenseComplianceFleetObservations)
    $coverageRecords = @(Get-ToolLicenseComplianceFleetCoverage)
    $softwareInventoryCoverageStatus = if ($coverageRecords.Count -eq 0 -or @($coverageRecords | Where-Object CoverageStatus -eq 'Failed').Count -gt 0) { 'Failed' }
        elseif (@($coverageRecords | Where-Object CoverageStatus -eq 'Partial').Count -gt 0) { 'Partial' }
        else { 'Complete' }
    $softwareInventoryOmittedCount = [int](Get-ToolLicenseComplianceIntegerSum -Items $coverageRecords -PropertyName OmittedCount)
    $devicePoolState = @{}
    foreach ($pool in @($entitlements | Where-Object { [string]$_.Metric -eq 'Device' } | Group-Object { Get-ToolLicenseComplianceEntitlementPoolKey -Entitlement $_ })) {
        $poolEntitlements = @($pool.Group | Sort-Object CreatedAtUtc,EntitlementId)
        if ($poolEntitlements.Count -eq 0) { continue }
        $prototype = $poolEntitlements[0]
        $scopeObservations = @($observations | Where-Object { [string]$_.ProductScope -eq [string]$prototype.ProductScope })
        $matches = @($observations | Where-Object { Test-ToolLicenseEntitlementMatchesObservation -Entitlement $prototype -Observation $_ })
        $identityEvidenceStatus = if ([string]$prototype.ProductScope -eq 'Software' -or $matches.Count -gt 0) { 'Complete' } else { 'InsufficientEvidence' }
        $observedSource = if ([string]$prototype.ProductScope -ne 'Software' -and $identityEvidenceStatus -ne 'Complete') { $scopeObservations } else { $matches }
        $observedDevices = @($observedSource | ForEach-Object { [string]$_.ClientId } | Where-Object { $_ } | Select-Object -Unique).Count
        $remainingConsumption = [int]$observedDevices
        for ($poolIndex = 0; $poolIndex -lt $poolEntitlements.Count; $poolIndex++) {
            $poolEntitlement = $poolEntitlements[$poolIndex]
            $purchased = [int]$poolEntitlement.PurchasedQuantity
            $allocated = [Math]::Min($remainingConsumption, $purchased)
            if ($poolIndex -eq ($poolEntitlements.Count - 1) -and $remainingConsumption -gt $purchased) { $allocated = $remainingConsumption }
            $devicePoolState[[string]$poolEntitlement.EntitlementId] = [pscustomobject][ordered]@{
                ObservedDevices=[int]$observedDevices
                ConsumptionCount=[int]$allocated
                IdentityEvidenceStatus=$identityEvidenceStatus
                ConsumptionEvidenceStatus=$(if ($identityEvidenceStatus -eq 'Complete') { 'Complete' } else { 'InsufficientEvidence' })
            }
            $remainingConsumption = [Math]::Max(0, ($remainingConsumption - $allocated))
        }
    }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($entitlement in $entitlements) {
        $scopeObservations = @($observations | Where-Object { [string]$_.ProductScope -eq [string]$entitlement.ProductScope })
        $matches = @($observations | Where-Object { Test-ToolLicenseEntitlementMatchesObservation -Entitlement $entitlement -Observation $_ })
        $identityEvidenceStatus = if ([string]$entitlement.ProductScope -eq 'Software' -or $matches.Count -gt 0) { 'Complete' } else { 'InsufficientEvidence' }
        $observedSource = if ([string]$entitlement.ProductScope -ne 'Software' -and $identityEvidenceStatus -ne 'Complete') { $scopeObservations } else { $matches }
        $installedClients = @($observedSource | ForEach-Object { [string]$_.ClientId } | Where-Object { $_ } | Select-Object -Unique)
        $installed = [int]$installedClients.Count
        $metric = [string]$entitlement.Metric
        $consumptionEvidenceStatus = if ($metric -eq 'Device' -and $identityEvidenceStatus -eq 'Complete') { 'Complete' } else { 'InsufficientEvidence' }
        $consumptionCount = if ($consumptionEvidenceStatus -eq 'Complete') { [int]$installed } else { $null }
        if ($metric -eq 'Device' -and $devicePoolState.ContainsKey([string]$entitlement.EntitlementId)) {
            $poolState = $devicePoolState[[string]$entitlement.EntitlementId]
            $installed = [int]$poolState.ConsumptionCount
            $consumptionCount = if ([string]$poolState.ConsumptionEvidenceStatus -eq 'Complete') { [int]$poolState.ConsumptionCount } else { $null }
            $identityEvidenceStatus = [string]$poolState.IdentityEvidenceStatus
            $consumptionEvidenceStatus = [string]$poolState.ConsumptionEvidenceStatus
            $observedDevices = [int]$poolState.ObservedDevices
        } else {
            $observedDevices = [int]$installed
        }
        $assigned = [int](Get-ToolLicenseComplianceIntegerSum -Items @($entitlement.Assignments) -PropertyName Quantity)
        $purchased = [int]$entitlement.PurchasedQuantity
        $available = [int]($purchased - $assigned)
        $documents = @($entitlement.Documents).Count
        $verifiedDocuments = @($entitlement.Documents | Where-Object { [string]$_.VerificationStatus -eq 'Verified' }).Count
        $documentEvidenceStatus = if ($verifiedDocuments -gt 0) { 'Verified' } elseif ($documents -gt 0) { 'AttachedOnly' } else { 'Missing' }
        $inventoryCoverageStatus = if ([string]$entitlement.ProductScope -eq 'Software') { $softwareInventoryCoverageStatus } else { 'Complete' }
        $expired = $false
        if (-not [string]::IsNullOrWhiteSpace([string]$entitlement.ExpiresAt)) {
            $expiry = [DateTime]::MinValue
            if ([DateTime]::TryParse([string]$entitlement.ExpiresAt, [ref]$expiry)) { $expired = $expiry.Date -lt [DateTime]::Today }
        }
        $consumptionExceeded = [bool]($consumptionEvidenceStatus -eq 'Complete' -and [int]$consumptionCount -gt $purchased)
        $assignmentExceeded = [bool]($metric -eq 'Device' -and $assigned -gt $purchased)
        $state = if ($expired -or $consumptionExceeded -or $assignmentExceeded) { 'Critical' }
            elseif ($identityEvidenceStatus -ne 'Complete' -or $consumptionEvidenceStatus -ne 'Complete' -or
                $inventoryCoverageStatus -ne 'Complete' -or $verifiedDocuments -eq 0 -or [int]$consumptionCount -gt $assigned) { 'NeedsReview' }
            else { 'Compliant' }
        $reason = if ($expired) { 'Expired' }
            elseif ($consumptionExceeded) { 'ConsumptionExceedsPurchased' }
            elseif ($assignmentExceeded) { 'AssignmentExceedsPurchased' }
            elseif ($identityEvidenceStatus -ne 'Complete') { 'ProductIdentityEvidenceMissing' }
            elseif ($consumptionEvidenceStatus -ne 'Complete') { 'MetricEvidenceMissing' }
            elseif ($inventoryCoverageStatus -ne 'Complete') { 'SoftwareInventoryCoverageIncomplete' }
            elseif ($documents -eq 0) { 'DocumentEvidenceMissing' }
            elseif ($verifiedDocuments -eq 0) { 'DocumentEvidenceUnverified' }
            elseif ([int]$consumptionCount -gt $assigned) { 'ConsumptionExceedsAssignment' }
            else { 'Reconciled' }
        [void]$rows.Add([pscustomobject][ordered]@{
            EntitlementId=[string]$entitlement.EntitlementId; ProductScope=[string]$entitlement.ProductScope
            CatalogProductId=[string]$entitlement.CatalogProductId; ProductName=[string]$entitlement.ProductName
            LicenseModel=[string]$entitlement.LicenseModel; Metric=$metric
            Purchased=$purchased; Assigned=$assigned; Installed=$installed; ObservedDevices=$observedDevices
            ConsumptionCount=$consumptionCount; Available=$available
            IdentityEvidenceStatus=$identityEvidenceStatus; ConsumptionEvidenceStatus=$consumptionEvidenceStatus; InventoryCoverageStatus=$inventoryCoverageStatus
            DocumentCount=$documents; VerifiedDocumentCount=$verifiedDocuments; DocumentEvidenceStatus=$documentEvidenceStatus
            ExpiresAt=[string]$entitlement.ExpiresAt; ComplianceState=$state; ComplianceReason=$reason
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
    return [pscustomobject][ordered]@{
        Rows=$rows.ToArray(); Uncovered=$uncovered.ToArray(); Observations=$observations
        SoftwareInventoryCoverageStatus=$softwareInventoryCoverageStatus
        SoftwareInventoryOmittedCount=$softwareInventoryOmittedCount
        SoftwareInventoryCoverage=$coverageRecords
    }
}

function New-ToolLicenseAdvisorEvidence {
    param(
        [Parameter(Mandatory=$true)][string]$EvidenceId,
        [Parameter(Mandatory=$true)][ValidateSet('EndpointReport','ComplianceStore','SignedCatalog','SoftwareInventory')][string]$SourceCode,
        [Parameter(Mandatory=$true)][ValidateSet('TechnicalActivation','ActivationChannel','CatalogClassification','CommercialEntitlement')][string]$Scope,
        [Parameter(Mandatory=$true)][ValidateSet('Direct','Corroborating','Informational')][string]$Strength,
        [AllowNull()][object]$Value
    )
    return [pscustomobject][ordered]@{
        EvidenceId = ConvertTo-ToolLicenseComplianceSafeText $EvidenceId 80
        SourceCode = $SourceCode
        Scope = $Scope
        Strength = $Strength
        Value = ConvertTo-ToolLicenseComplianceSafeText $Value 160
    }
}

function Get-ToolLicenseAdvisorResult {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Windows','Office','Software')][string]$ProductScope,
        [string]$TechnicalStatus = '', [string]$Channel = '', [string]$LicenseModel = 'Unknown',
        [ValidateSet('Compliant','NeedsReview','Critical','NotVerified')][string]$EntitlementStatus = 'NotVerified'
    )
    $safeTechnicalStatus = ConvertTo-ToolLicenseComplianceSafeText $TechnicalStatus 80
    $safeChannel = ConvertTo-ToolLicenseComplianceSafeText $Channel 100
    $safeLicenseModel = ConvertTo-ToolLicenseComplianceSafeText $LicenseModel 80
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
    $findingCode = if ($ProductScope -in @('Windows','Office')) {
        if ($technicalGood) { 'TechnicalActivationPresent' } else { 'TechnicalActivationNotConfirmed' }
    } elseif ($LicenseModel -in @('Free','OpenSource')) { 'FreeOrOpenSourceClassification' } else { 'CommercialEntitlementRequired' }
    $recommendationCode = if ($EntitlementStatus -eq 'Critical') { 'ReconcileImmediately' }
        elseif ($EntitlementStatus -in @('NeedsReview','NotVerified')) { 'AttachEvidenceAndAssign' }
        elseif (-not $technicalGood -and $ProductScope -in @('Windows','Office')) { 'UseOfficialActivation' }
        else { 'RetainEvidence' }
    $ruleId = switch ($findingCode) {
        'TechnicalActivationPresent' { if ($ProductScope -eq 'Windows') { 'VLS-WIN-ACT-001' } else { 'VLS-OFF-ACT-001' } }
        'TechnicalActivationNotConfirmed' { if ($ProductScope -eq 'Windows') { 'VLS-WIN-ACT-002' } else { 'VLS-OFF-ACT-002' } }
        'FreeOrOpenSourceClassification' { 'VLS-SW-CAT-001' }
        default { 'VLS-SW-ENT-001' }
    }

    $evidence = New-Object System.Collections.Generic.List[object]
    if (-not [string]::IsNullOrWhiteSpace($safeTechnicalStatus)) {
        [void]$evidence.Add((New-ToolLicenseAdvisorEvidence -EvidenceId 'VLS-EV-TECH-STATUS' -SourceCode EndpointReport -Scope TechnicalActivation -Strength Direct -Value $safeTechnicalStatus))
    }
    if (-not [string]::IsNullOrWhiteSpace($safeChannel)) {
        [void]$evidence.Add((New-ToolLicenseAdvisorEvidence -EvidenceId 'VLS-EV-ACT-CHANNEL' -SourceCode EndpointReport -Scope ActivationChannel -Strength Corroborating -Value $safeChannel))
    }
    if ($ProductScope -eq 'Software' -and -not [string]::IsNullOrWhiteSpace($safeLicenseModel)) {
        $modelSource = if ($LicenseModel -ne 'Unknown') { 'SignedCatalog' } else { 'SoftwareInventory' }
        [void]$evidence.Add((New-ToolLicenseAdvisorEvidence -EvidenceId 'VLS-EV-LICENSE-MODEL' -SourceCode $modelSource -Scope CatalogClassification -Strength $(if ($modelSource -eq 'SignedCatalog') { 'Direct' } else { 'Informational' }) -Value $safeLicenseModel))
    }
    [void]$evidence.Add((New-ToolLicenseAdvisorEvidence -EvidenceId 'VLS-EV-ENTITLEMENT' -SourceCode ComplianceStore -Scope CommercialEntitlement -Strength $(if ($EntitlementStatus -eq 'NotVerified') { 'Informational' } else { 'Direct' }) -Value $EntitlementStatus))

    $sourceCount = @($evidence | ForEach-Object SourceCode | Select-Object -Unique).Count
    $correlationCode = if ($sourceCount -ge 2) { 'CrossSource' } else { 'SingleSource' }
    $confidence = if ($EntitlementStatus -eq 'Critical') { 'High' }
        elseif ($findingCode -eq 'FreeOrOpenSourceClassification') { 'High' }
        elseif ($technicalGood -and -not [string]::IsNullOrWhiteSpace($safeChannel)) { 'High' }
        elseif ($evidence.Count -ge 2) { 'Medium' }
        else { 'Informational' }
    if ($script:ToolLicenseAdvisorAllowedConfidence -notcontains $confidence) { throw 'Advisor confidence is invalid.' }

    $technicalConclusion = if ($ProductScope -in @('Windows','Office')) {
        if ($technicalGood) { 'TechnicalActivationPresent' } else { 'TechnicalActivationNotConfirmed' }
    } else { 'InventoryOnly' }
    $overallVerdict = if ($EntitlementStatus -eq 'Critical') { 'ActionRequired' }
        elseif ($EntitlementStatus -in @('NeedsReview','NotVerified')) { 'ReviewRequired' }
        elseif (-not $technicalGood -and $ProductScope -in @('Windows','Office')) { 'ReviewRequired' }
        else { 'NoImmediateIssue' }

    $legacyResult = [pscustomobject][ordered]@{
        SchemaVersion=$script:ToolLicenseAdvisorSchemaVersion; RuleId=$ruleId; RuleRevision=1
        ProductScope=$ProductScope; TechnicalStatus=$safeTechnicalStatus; Channel=$safeChannel; LicenseModel=$safeLicenseModel
        EntitlementStatus=$EntitlementStatus; Risk=$risk; Confidence=$confidence; ConfidenceScope='FindingOnly'
        FindingCode=$findingCode; RecommendationCode=$recommendationCode; LimitationCode='LegalEntitlementNotProven'
        TechnicalConclusion=$technicalConclusion; TamperingConclusion='NotAssessed'; EntitlementConclusion=$EntitlementStatus; OverallVerdict=$overallVerdict
        CorrelationCode=$correlationCode; EvidenceSourceCount=$sourceCount; Evidence=[object[]]@($evidence.ToArray())
        Explanation=$explanation; Recommendation=$recommendation
        Limitation='No result in this advisor independently proves legal ownership or authenticity.'
    }
    $legacyResult | Add-Member -NotePropertyName Finding -NotePropertyValue (ConvertTo-ToolDetectionFindingFromLicenseAdvisor -Advisor $legacyResult)
    return $legacyResult
}

function Get-ToolLicenseComplianceSnapshot {
    $reconciliation = Get-ToolLicenseComplianceReconciliation
    $rows = @($reconciliation.Rows)
    $uncovered = @($reconciliation.Uncovered)
    $critical = @($rows | Where-Object ComplianceState -eq 'Critical').Count
    $coverageReview = if ([string]$reconciliation.SoftwareInventoryCoverageStatus -eq 'Complete') { 0 } else { 1 }
    $review = @($rows | Where-Object ComplianceState -eq 'NeedsReview').Count + $uncovered.Count + $coverageReview
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
            SoftwareInventoryCoverageStatus=[string]$reconciliation.SoftwareInventoryCoverageStatus
            SoftwareInventoryOmittedCount=[int]$reconciliation.SoftwareInventoryOmittedCount
        }
        Entitlements=$rows; Uncovered=$uncovered; SoftwareInventoryCoverage=@($reconciliation.SoftwareInventoryCoverage)
        Disclaimer='Technical activation and catalog classification do not independently prove legal entitlement. Authoritative documents and licensing portals remain required.'
    }
}
