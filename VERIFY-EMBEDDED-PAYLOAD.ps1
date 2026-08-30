[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$PayloadList,
    [Parameter(Mandatory = $true)][ValidateSet("x64", "x86")][string]$ExpectedArchitecture,
    [ValidateSet('Production','ManagedSigned','StoreSubmission','DevelopmentUnsigned')][string]$ExpectedTrustMode = 'DevelopmentUnsigned'
)

$ErrorActionPreference = "Stop"

function Get-Sha256HexFromFile([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-Sha256HexFromStream([IO.Stream]$Stream) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace("-", "") }
    finally { $sha.Dispose() }
}

try {
    $actualArchitecture = if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }
    if ($actualArchitecture -ne $ExpectedArchitecture) {
        throw "Trình kiểm tra đang chạy $actualArchitecture, cần $ExpectedArchitecture."
    }

    $payloadFiles = @($PayloadList -split '\|' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($payloadFiles.Count -eq 0) { throw "Danh sách payload trống." }
    foreach ($name in $payloadFiles) {
        if ([IO.Path]::GetFileName($name) -ne $name) { throw "Tên payload không an toàn: $name" }
    }

    $assembly = [Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($ExePath))
    $launcherType = $assembly.GetType("ThanhViet.ToolKiemTra.Program", $true)
    $bindingFlags = [Reflection.BindingFlags]::NonPublic -bor [Reflection.BindingFlags]::Static
    $provenanceHelperPath = Join-Path $SourceDirectory 'Tool-Provenance.ps1'
    if (-not (Test-Path -LiteralPath $provenanceHelperPath -PathType Leaf)) {
        throw 'Thiếu Tool-Provenance.ps1 để xác minh BuildId đã biên dịch.'
    }
    . $provenanceHelperPath
    $expectedBuildId = [string](Get-ToolProvenanceExpectedValues).BuildId
    $buildIdField = $launcherType.GetField('OfficialBuildId', $bindingFlags)
    if (-not $buildIdField -or -not $buildIdField.IsLiteral) {
        throw 'Không đọc được hằng OfficialBuildId từ launcher đã biên dịch.'
    }
    $compiledBuildId = [string]$buildIdField.GetRawConstantValue()
    if ($compiledBuildId -cne $expectedBuildId) {
        throw "BuildId trong EXE không khớp nguồn chuẩn: $compiledBuildId / $expectedBuildId"
    }
    $payloadField = $launcherType.GetField("PayloadFiles", $bindingFlags)
    $integrityField = $launcherType.GetField("RequiredIntegrityFiles", $bindingFlags)
    if (-not $payloadField -or -not $integrityField) {
        throw "Không đọc được danh sách payload/toàn vẹn nội bộ của launcher."
    }

    $launcherPayloadFiles = @($payloadField.GetValue($null))
    $stableMarkerField = $launcherType.GetField('SignedStableBuildMarker', $bindingFlags)
    $managedMarkerField = $launcherType.GetField('ManagedSignedBuildMarker', $bindingFlags)
    $storeMarkerField = $launcherType.GetField('StoreBuildMarker', $bindingFlags)
    if (-not $stableMarkerField -or -not $managedMarkerField -or -not $storeMarkerField) {
        throw 'Launcher thiếu marker trust tách biệt cho Stable/ManagedSigned/Microsoft Store.'
    }
    $actualMarkers = @(
        [string]$stableMarkerField.GetRawConstantValue(),
        [string]$managedMarkerField.GetRawConstantValue(),
        [string]$storeMarkerField.GetRawConstantValue()) -join ''
    $expectedMarkers = switch ($ExpectedTrustMode) {
        'Production' { '100' }
        'ManagedSigned' { '010' }
        'StoreSubmission' { '001' }
        default { '000' }
    }
    if ($actualMarkers -cne $expectedMarkers) {
        throw "Marker trust không khớp chế độ ${ExpectedTrustMode}: $actualMarkers / $expectedMarkers."
    }
    $parseLaunchMode = $launcherType.GetMethod('ParseLaunchMode', $bindingFlags)
    $requiresTrustedBuild = $launcherType.GetMethod('RequiresTrustedBuild', $bindingFlags)
    $getScriptName = $launcherType.GetMethod('GetScriptName', $bindingFlags)
    if (-not $parseLaunchMode -or -not $requiresTrustedBuild -or -not $getScriptName) {
        throw 'Launcher thiếu broker nâng quyền đã biên dịch.'
    }
    $brokerFixtureJson = '{"SchemaVersion":"2.0"}'
    $brokerFixtureBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($brokerFixtureJson))
    $brokerMode = $parseLaunchMode.Invoke($null, [object[]]@(,[string[]]@('--elevated-module-broker',$brokerFixtureBase64)))
    if ([string]$brokerMode -cne 'ElevatedModuleBroker' -or
        [bool]$requiresTrustedBuild.Invoke($null, @($brokerMode)) -or
        [string]$getScriptName.Invoke($null, @($brokerMode)) -cne 'Tool-ElevatedBridge.ps1') {
        throw 'Broker nâng quyền không dispatch qua Bridge nhúng hoặc không tách trust read-only/system-change.'
    }
    $invalidBrokerBlocked = $false
    try { [void]$parseLaunchMode.Invoke($null, [object[]]@(,[string[]]@('--elevated-module-broker','bm90LWpzb24='))) }
    catch { $invalidBrokerBlocked = $true }
    if (-not $invalidBrokerBlocked) { throw 'Broker nâng quyền không từ chối payload không phải JSON.' }
    $containsProvenanceSignature = [bool]($launcherPayloadFiles -contains 'OFFICIAL-PROVENANCE-v1.json.p7s')
    if ($ExpectedTrustMode -eq 'DevelopmentUnsigned' -and $containsProvenanceSignature) {
        throw 'Build development không được nhúng provenance signature production.'
    }
    if ($ExpectedTrustMode -ne 'DevelopmentUnsigned' -and -not $containsProvenanceSignature) {
        throw "Build $ExpectedTrustMode thiếu provenance signature production."
    }
    if ($ExpectedTrustMode -eq 'StoreSubmission') {
        $storeConstants = [ordered]@{
            StorePackageName = 'ThanhVit.ToolKimTraBnQuyn'
            StorePackageVersion = '5.0.0.0'
            StorePackagePublisherId = '9tjmpwr25h78w'
            StorePackageFamilyName = 'ThanhVit.ToolKimTraBnQuyn_9tjmpwr25h78w'
        }
        foreach ($entry in $storeConstants.GetEnumerator()) {
            $field = $launcherType.GetField([string]$entry.Key, $bindingFlags)
            if (-not $field -or [string]$field.GetRawConstantValue() -cne [string]$entry.Value) {
                throw "Store identity constant không khớp: $($entry.Key)."
            }
        }
        $identityValidator = $launcherType.GetMethod('IsExpectedStorePackageIdentity', $bindingFlags)
        if (-not $identityValidator) { throw 'Launcher thiếu Store package identity validator.' }
        $trustValidator = $launcherType.GetMethod('IsExpectedStorePackageTrust', $bindingFlags)
        if (-not $trustValidator) { throw 'Launcher thiếu Store package origin validator.' }
        $validFullName = 'ThanhVit.ToolKimTraBnQuyn_5.0.0.0_x64__9tjmpwr25h78w'
        $validFamilyName = 'ThanhVit.ToolKimTraBnQuyn_9tjmpwr25h78w'
        if (-not [bool]$identityValidator.Invoke($null, @($validFullName, $validFamilyName)) -or
            [bool]$identityValidator.Invoke($null, @($validFullName.Replace('5.0.0.0','5.0.0.1'), $validFamilyName)) -or
            [bool]$identityValidator.Invoke($null, @($validFullName, $validFamilyName.Replace('9tjmpwr25h78w','8wekyb3d8bbwe'))) -or
            [bool]$identityValidator.Invoke($null, @($validFullName.Replace('ThanhVit.ToolKimTraBnQuyn','Other.Product'), $validFamilyName))) {
            throw 'Store package identity validator không fail-closed với name/version/publisher sai.'
        }
        if (-not [bool]$trustValidator.Invoke($null, @($validFullName, $validFamilyName, 3)) -or
            [bool]$trustValidator.Invoke($null, @($validFullName, $validFamilyName, 5)) -or
            [bool]$trustValidator.Invoke($null, @($validFullName, $validFamilyName, 6))) {
            throw 'Store package origin validator không khóa DeveloperSigned/LineOfBusiness sideload.'
        }
        $stateEvaluator = $launcherType.GetMethod('EvaluateOfficialBuildState', $bindingFlags)
        if (-not $stateEvaluator) { throw 'Launcher thiếu runtime Store trust evaluator.' }
        $stateArguments = @('')
        $unpackagedState = [string]$stateEvaluator.Invoke($null, $stateArguments)
        if ($unpackagedState -cne 'Modified' -or [string]$stateArguments[0] -cne 'StorePackageIdentityMissing') {
            throw "Store EXE chạy ngoài package không bị khóa đúng cách: $unpackagedState / $($stateArguments[0])."
        }
    }
    if ($launcherPayloadFiles.Count -ne $payloadFiles.Count) {
        throw "Danh sách payload nội bộ lệch số lượng so với build: $($launcherPayloadFiles.Count)/$($payloadFiles.Count)."
    }
    for ($index = 0; $index -lt $payloadFiles.Count; $index++) {
        if ([string]$launcherPayloadFiles[$index] -cne [string]$payloadFiles[$index]) {
            throw "Ánh xạ payload nội bộ lệch tại vị trí $index`: $($launcherPayloadFiles[$index]) / $($payloadFiles[$index])."
        }
    }

    $integrityManifestPath = Join-Path $SourceDirectory "TOOL-SHA256SUMS.txt"
    if (-not (Test-Path -LiteralPath $integrityManifestPath -PathType Leaf)) {
        throw "Thiếu TOOL-SHA256SUMS.txt để đối chiếu danh sách toàn vẹn nội bộ."
    }
    $manifestIntegrityFiles = New-Object System.Collections.Generic.List[string]
    foreach ($rawLine in [IO.File]::ReadAllLines($integrityManifestPath)) {
        $line = ([string]$rawLine).Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) { continue }
        $match = [regex]::Match($line, "^[0-9A-Fa-f]{64}[ `t]+\*?(.+)$")
        if (-not $match.Success) {
            throw "TOOL-SHA256SUMS.txt có dòng không hợp lệ khi kiểm tra launcher."
        }
        [void]$manifestIntegrityFiles.Add($match.Groups[1].Value.Trim())
    }

    $launcherIntegrityFiles = @($integrityField.GetValue($null))
    if ($launcherIntegrityFiles.Count -ne $manifestIntegrityFiles.Count) {
        throw "Danh sách toàn vẹn nội bộ lệch số lượng so với manifest: $($launcherIntegrityFiles.Count)/$($manifestIntegrityFiles.Count)."
    }
    for ($index = 0; $index -lt $manifestIntegrityFiles.Count; $index++) {
        if ([string]$launcherIntegrityFiles[$index] -cne [string]$manifestIntegrityFiles[$index]) {
            throw "Danh sách toàn vẹn nội bộ lệch tại vị trí $index`: $($launcherIntegrityFiles[$index]) / $($manifestIntegrityFiles[$index])."
        }
    }

    $resourceName = "payload.bundle.deflate.v1"
    $resourceNames = @($assembly.GetManifestResourceNames())
    if ($resourceNames.Count -ne 1 -or [string]$resourceNames[0] -cne $resourceName) {
        throw "EXE phải chứa đúng một solid payload resource: $resourceName."
    }

    [int64]$maximumCompressedBytes = 16MB
    [int64]$maximumDecodedBytes = 32MB
    [int64]$maximumPayloadDataBytes = 16MB
    [int64]$maximumSinglePayloadBytes = 8MB
    $compressed = $assembly.GetManifestResourceStream($resourceName)
    if (-not $compressed) { throw "Không đọc được $resourceName." }
    try {
        if ($compressed.CanSeek -and ($compressed.Length -le 0 -or $compressed.Length -gt $maximumCompressedBytes)) {
            throw "Kích thước solid payload resource không hợp lệ."
        }
        $deflate = New-Object IO.Compression.DeflateStream($compressed, [IO.Compression.CompressionMode]::Decompress, $false)
        try {
            $decoded = New-Object IO.MemoryStream
            try {
                $buffer = New-Object byte[] 81920
                while (($bytesRead = $deflate.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    if ($decoded.Length -gt ($maximumDecodedBytes - $bytesRead)) {
                        throw "Solid payload bundle giải nén vượt giới hạn."
                    }
                    $decoded.Write($buffer, 0, $bytesRead)
                }
                [byte[]]$decodedBytes = $decoded.ToArray()
            } finally { $decoded.Dispose() }
        } finally { $deflate.Dispose() }
    } finally { $compressed.Dispose() }

    [byte[]]$expectedMagic = [Text.Encoding]::ASCII.GetBytes('TVPBNDL1')
    $lengths = New-Object System.Collections.Generic.List[int]
    $bundleStream = New-Object IO.MemoryStream(,$decodedBytes)
    try {
        $reader = New-Object IO.BinaryReader($bundleStream)
        try {
            [byte[]]$actualMagic = $reader.ReadBytes($expectedMagic.Length)
            if ($actualMagic.Length -ne $expectedMagic.Length) { throw "Header solid payload bundle bị cắt ngắn." }
            for ($index = 0; $index -lt $expectedMagic.Length; $index++) {
                if ($actualMagic[$index] -ne $expectedMagic[$index]) { throw "Magic solid payload bundle không hợp lệ." }
            }
            [uint32]$formatVersion = $reader.ReadUInt32()
            [uint32]$payloadCount = $reader.ReadUInt32()
            [uint64]$declaredPayloadBytes = $reader.ReadUInt64()
            if ($formatVersion -ne 1 -or $payloadCount -ne $payloadFiles.Count) {
                throw "Version/count solid payload bundle không hợp lệ."
            }
            if ($declaredPayloadBytes -gt [uint64]$maximumPayloadDataBytes) {
                throw "Solid payload bundle khai báo quá nhiều dữ liệu."
            }

            [uint64]$measuredPayloadBytes = 0
            for ($index = 0; $index -lt $payloadFiles.Count; $index++) {
                [uint64]$payloadLength = $reader.ReadUInt64()
                if ($payloadLength -gt [uint64]$maximumSinglePayloadBytes -or
                    $measuredPayloadBytes -gt ([uint64]$maximumPayloadDataBytes - $payloadLength)) {
                    throw "Độ dài segment solid payload bundle không hợp lệ."
                }
                [void]$lengths.Add([int]$payloadLength)
                $measuredPayloadBytes += $payloadLength
            }
            if ($measuredPayloadBytes -ne $declaredPayloadBytes) {
                throw "Bảng độ dài solid payload bundle không nhất quán."
            }
            [int64]$payloadDataOffset = $bundleStream.Position
            if (($payloadDataOffset + [int64]$declaredPayloadBytes) -ne $bundleStream.Length) {
                throw "Kích thước giải nén solid payload bundle không khớp header."
            }
        } finally { $reader.Dispose() }
    } finally { $bundleStream.Dispose() }

    $openPayloadMethod = $launcherType.GetMethod("OpenPayloadStream", $bindingFlags)
    if (-not $openPayloadMethod) { throw "Launcher thiếu bộ đọc segment solid payload bundle." }
    for ($index = 0; $index -lt $payloadFiles.Count; $index++) {
        $sourcePath = Join-Path $SourceDirectory $payloadFiles[$index]
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Thiếu payload nguồn: $($payloadFiles[$index])" }
        if ([int64](Get-Item -LiteralPath $sourcePath).Length -ne [int64]$lengths[$index]) {
            throw "Độ dài payload nhúng không khớp: $($payloadFiles[$index])"
        }
        try {
            $segment = [IO.Stream]$openPayloadMethod.Invoke($null, @($assembly, [int]$index))
        } catch {
            $detail = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
            throw "Launcher từ chối payload $($payloadFiles[$index]): $detail"
        }
        if (-not $segment) { throw "Launcher không trả về payload: $($payloadFiles[$index])" }
        try {
            if ($segment.Length -ne [int64]$lengths[$index]) { throw "Segment payload sai độ dài: $($payloadFiles[$index])" }
            $embeddedHash = Get-Sha256HexFromStream $segment
        } finally { $segment.Dispose() }
        if ($embeddedHash -ne (Get-Sha256HexFromFile $sourcePath)) {
            throw "Payload nhúng không khớp: $($payloadFiles[$index])"
        }
    }

    $bridgeIndex = [Array]::IndexOf([string[]]$payloadFiles, 'Tool-ElevatedBridge.ps1')
    if ($bridgeIndex -lt 0) { throw 'Danh sách payload không chứa Tool-ElevatedBridge.ps1.' }
    try {
        $bridgeSegment = [IO.Stream]$openPayloadMethod.Invoke($null, @($assembly, [int]$bridgeIndex))
    } catch {
        $detail = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        throw "Không đọc được Bridge nhúng để kiểm tra BuildId: $detail"
    }
    if (-not $bridgeSegment) { throw 'Launcher không trả về Bridge nhúng.' }
    try {
        $bridgeReader = New-Object IO.StreamReader($bridgeSegment, (New-Object Text.UTF8Encoding($false, $true)), $true, 4096, $true)
        try { $embeddedBridgeText = $bridgeReader.ReadToEnd() }
        finally { $bridgeReader.Dispose() }
    } finally { $bridgeSegment.Dispose() }
    if ($embeddedBridgeText -notmatch "Tool-Provenance\.ps1" -or
        $embeddedBridgeText -notmatch 'Get-ToolProvenanceExpectedValues' -or
        $embeddedBridgeText -notmatch 'Get-ToolOfficialBuildState' -or
        $embeddedBridgeText -notmatch 'ElevatedBrokerCompiledLauncherRequired' -or
        $embeddedBridgeText -notmatch 'Assert-BridgeOriginalPayloadIntegrity' -or
        $embeddedBridgeText -notmatch 'ConvertFrom-BridgeTargetArguments' -or
        $embeddedBridgeText -notmatch 'Test-BridgeLocalAbsolutePath' -or
        $embeddedBridgeText -notmatch 'Assert-BridgeModuleArgumentProfile' -or
        $embeddedBridgeText -notmatch "'cleanup\.scan'" -or
        $embeddedBridgeText -notmatch 'ElevatedBridgeModuleArgumentNotAllowed' -or
        $embeddedBridgeText -notmatch 'ElevatedBridgeEnvironmentPathInvalid' -or
        $embeddedBridgeText -notmatch 'DataScope Machine' -or
        $embeddedBridgeText -notmatch '\$protectedScriptPath' -or
        $embeddedBridgeText -notmatch 'TOOL_OFFICIAL_BUILD_ID''\]\s*-ne\s+\$expectedOfficialBuildId') {
        throw 'Bridge nhúng chưa ràng buộc broker/provenance/BuildId, đường dẫn cục bộ và payload bảo vệ sau UAC.'
    }
    if ($embeddedBridgeText -match '\d+\.\d+\.\d+\.\d+-production-\d{8}') {
        throw 'Bridge nhúng vẫn chứa BuildId hard-code độc lập.'
    }

    Write-Host "EMBEDDED-PAYLOAD $ExpectedArchitecture`: ĐẠT ($($payloadFiles.Count)/$($payloadFiles.Count); Trust=$ExpectedTrustMode; BuildId=$compiledBuildId; Bridge=canonical; solid-deflate=1; format=1)" -ForegroundColor Green
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
