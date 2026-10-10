[CmdletBinding()]
param(
    [string]$SourceDirectory = ''
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
. (Join-Path $SourceDirectory 'VERIFY-COMPOSED-SOURCE.ps1')

function Assert-Enterprise {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-AvailableLoopbackPort {
    $listener = New-Object Net.Sockets.TcpListener -ArgumentList ([Net.IPAddress]::Loopback),0
    try {
        $listener.Start()
        return [int]([Net.IPEndPoint]$listener.LocalEndpoint).Port
    } finally {
        $listener.Stop()
    }
}

function Get-EnterpriseVerifierHttpStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [hashtable]$Headers = @{}
    )
    try {
        $request = @{
            Uri = $Uri
            Method = $Method
            Headers = $Headers
            UseBasicParsing = $true
            TimeoutSec = 10
            ErrorAction = 'Stop'
        }
        if ($Method -eq 'POST') {
            $request.Body = '{}'
            $request.ContentType = 'application/json'
        }
        return [int](Invoke-WebRequest @request).StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        throw
    }
}

$required = @(
    "Tool-Enterprise.ps1",
    "Tool-LicenseCompliance.ps1",
    "Tool-EnterpriseHost.ps1",
    "Tool-EnterpriseAgent.ps1",
    "enterprise-license-manager.ps1",
    "windows-office-license-manager.ps1",
    "Tool-Localization.ps1",
    "Tool-Strings.vi-VN.json",
    "Tool-Strings.en-US.json",
    "Tool-OfflinePolicy.ps1",
    "Tool-UiTheme.ps1",
    "Tool-ReportSchema.ps1",
    "Tool-ModuleContract.ps1",
    "VietLicenSure-v5.0-OneFile.cs"
)
foreach ($name in $required) {
    $path = Join-Path $SourceDirectory $name
    Assert-Enterprise (Test-Path -LiteralPath $path -PathType Leaf) "Thiếu tệp enterprise: $name"
    if ($name.EndsWith(".ps1", [StringComparison]::OrdinalIgnoreCase)) {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
        Assert-Enterprise (@($errors).Count -eq 0) "PowerShell parse lỗi trong ${name}: $(@($errors | ForEach-Object ToString) -join '; ')"
    }
}

$enterpriseUiText = Get-Content -LiteralPath (Join-Path $SourceDirectory 'enterprise-license-manager.ps1') -Raw -Encoding UTF8
Assert-Enterprise ($enterpriseUiText -match '[$]enterpriseVersionFromLauncher\s*=\s*\[string\][$]env:TOOL_TOOL_VERSION') 'Enterprise UI chưa nhận phiên bản từ launcher.'
Assert-Enterprise ($enterpriseUiText -match '"5\.0"') 'Enterprise UI thiếu fallback v5.0.'
Assert-Enterprise ($enterpriseUiText -match 'function\s+Get-EnterpriseLifecycleTaskName' -and
    $enterpriseUiText -match 'enterpriseInfrastructureVersion\) Enterprise \$Role' -and
    $enterpriseUiText -match 'enterpriseInfrastructureVersion.+?Enterprise Server') 'Tên Firewall/Task mới chưa theo phiên bản hiện hành.'
foreach ($legacyTaskVersion in @('v4.8','v4.6')) {
    Assert-Enterprise ($enterpriseUiText -match [regex]::Escape("ThanhViet Tool $legacyTaskVersion Enterprise `$Role")) "Thiếu dọn task tương thích hạ tầng cũ: $legacyTaskVersion"
    Assert-Enterprise ($enterpriseUiText -match [regex]::Escape("ThanhViet Tool $legacyTaskVersion Enterprise Server")) "Thiếu dọn Firewall tương thích hạ tầng cũ: $legacyTaskVersion"
}

$previousRoot = [string]$env:TOOL_ENTERPRISE_ROOT
$previousSkipAcl = [string]$env:TOOL_ENTERPRISE_SKIP_ACL
$previousOfflineMode = [string]$env:TOOL_OFFLINE_MODE
$previousEnterpriseNetworkAllowed = [string]$env:TOOL_ENTERPRISE_NETWORK_ALLOWED
$previousEnterpriseNetworkSettings = [string]$env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH
$previousUiCulture = [string]$env:TOOL_UI_CULTURE
$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd("\") + "\"
$testRoot = Join-Path $temporaryBase ("ThanhViet-v48-enterprise-test-" + [Guid]::NewGuid().ToString("N"))
$exportRoot = Join-Path $temporaryBase ("ThanhViet-v48-enterprise-export-" + [Guid]::NewGuid().ToString("N"))
$separateClientRoot = Join-Path $temporaryBase ("ThanhViet-v48-enterprise-client-test-" + [Guid]::NewGuid().ToString("N"))
$dashboardFixtureRoot = Join-Path $temporaryBase ("ThanhViet-v50-dashboard-test-" + [Guid]::NewGuid().ToString("N"))
$hostProcess = $null
$enterprisePort = Get-AvailableLoopbackPort
try {
    $env:TOOL_ENTERPRISE_ROOT = $testRoot
    $env:TOOL_ENTERPRISE_SKIP_ACL = "1"
    $env:TOOL_OFFLINE_MODE = "0"
    $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = Join-Path $testRoot "enterprise-network-settings.json"
    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = "0"
    . (Join-Path $SourceDirectory "Tool-ReportSchema.ps1")
    . (Join-Path $SourceDirectory "Tool-ModuleContract.ps1")
    . (Join-Path $SourceDirectory "Tool-Enterprise.ps1")

    $metadata = Get-ToolEnterpriseMetadata
    Assert-Enterprise ([string]$metadata.ToolVersion -eq "5.0") "Enterprise ToolVersion không phải 5.0."
    Assert-Enterprise ([string]$metadata.ProtocolVersion -eq "1.0") "Enterprise protocol không phải 1.0."
    Assert-Enterprise (-not [bool]$metadata.FullProductKeysInReports) "Metadata không được cho phép full product key trong báo cáo."

    $resolvedEndpoint = Resolve-ToolEnterpriseServerEndpoint -ServerAddress "192.168.2.5:49421" -Port 49420
    Assert-Enterprise ([string]$resolvedEndpoint.Address -eq "192.168.2.5" -and [int]$resolvedEndpoint.Port -eq 49421) "Không tách đúng địa chỉ IP:cổng của máy chủ."
    $invalidEndpoint = Get-ToolEnterpriseConnectionDiagnostic -ServerAddress "địa chỉ không hợp lệ" -Port 49420 -TimeoutMs 200
    Assert-Enterprise (-not [bool]$invalidEndpoint.Success -and [string]$invalidEndpoint.Code -eq "InvalidEndpoint") "Chẩn đoán không phân biệt địa chỉ máy chủ không hợp lệ."

    $server = New-ToolEnterpriseServerConfiguration -ServerName "EnterpriseVerification" -AdminCode "Verify-Admin-4826" -BindAddress "127.0.0.1" -Port $enterprisePort -AllowedCidrs @("127.0.0.0/8")
    Assert-Enterprise (Test-ToolEnterpriseAdminCode -AdminCode "Verify-Admin-4826" -Verifier $server.AdminVerifier) "Không xác minh được mã quản trị đúng."
    Assert-Enterprise (-not (Test-ToolEnterpriseAdminCode -AdminCode "Wrong-Admin" -Verifier $server.AdminVerifier)) "Mã quản trị sai lại được chấp nhận."
    $pairing = Get-ToolEnterprisePairingCode -AdminCode "Verify-Admin-4826"
    Assert-Enterprise ($pairing.Length -ge 20) "Mã ghép nối quá ngắn."
    $rotatedPairing = Reset-ToolEnterprisePairingCode -AdminCode "Verify-Admin-4826" -ValidHours 24
    Assert-Enterprise ($rotatedPairing.Length -ge 20 -and $rotatedPairing -ne $pairing) "Luân chuyển không tạo mã ghép nối mới."
    $pairing = $rotatedPairing

    $client = Set-ToolEnterpriseClientConfiguration -ServerAddress "127.0.0.1" -Port $enterprisePort -AllowRemoteLicenseChanges:$false
    $clientAgain = Set-ToolEnterpriseClientConfiguration -ServerAddress "127.0.0.1" -Port $enterprisePort -AllowRemoteLicenseChanges:$false
    Assert-Enterprise ([string]$client.ClientId -eq [string]$clientAgain.ClientId) "ClientId bị đổi khi cập nhật cấu hình."

    $paths = Get-ToolEnterprisePaths
    Assert-Enterprise ([string]$paths.ClientAgentResult -match 'agent-result\.json$' -and [string]$paths.ClientAgentError -match 'agent-error\.json$') "Lõi enterprise thiếu tệp xác nhận kết quả agent."
    $secret = Get-ToolEnterpriseSecret -Path $paths.ServerMasterSecret
    $envelope = New-ToolEnterpriseEnvelope -Secret $secret -Context "verify" -Payload ([ordered]@{ Value="round-trip"; Number=42 })
    $opened = Open-ToolEnterpriseEnvelope -Secret $secret -ExpectedContext "verify" -Envelope $envelope
    Assert-Enterprise ([string]$opened.Payload.Value -eq "round-trip") "Mã hóa enterprise không round-trip."
    $tampered = $envelope | Select-Object *
    $macText = [string]$tampered.Mac
    $tampered.Mac = $(if ($macText.Substring(0, 1) -eq "A") { "B" + $macText.Substring(1) } else { "A" + $macText.Substring(1) })
    $tamperRejected = $false
    try { [void](Open-ToolEnterpriseEnvelope -Secret $secret -ExpectedContext "verify" -Envelope $tampered) } catch { $tamperRejected = $true }
    Assert-Enterprise $tamperRejected "Envelope bị sửa HMAC không bị từ chối."

    $report = Get-ToolEnterpriseLicenseSnapshot -ClientId $client.ClientId
    $assetRawUuid = 'F38D7701-6F5F-4F5E-8D10-123456789ABC'
    $assetRawSerial = 'VERIFY-ASSET-SERIAL-001'
    $assetIdentity = Get-ToolDeviceIdentitySnapshot -Observation ([pscustomobject]@{
        UUID=$assetRawUuid; SystemSerialNumber=$assetRawSerial; MachineGuid='11111111-2222-3333-4444-555555555555'
        Manufacturer='Contoso'; Model='Enterprise Test Device'; ComputerName='VERIFY-ASSET-CLIENT'
    })
    $report.AssetIdentity = $assetIdentity
    $report.Privacy.RawHardwareIdentifiersIncluded = $false
    $report.Privacy.HashedAssetIdentityIncluded = $true
    $queuedReportPath = Add-ToolEnterpriseOutboxReport -Report $report
    Assert-Enterprise (Test-Path -LiteralPath $queuedReportPath -PathType Leaf) "Mất kết nối không tạo được hàng đợi báo cáo."
    Assert-Enterprise ((Get-Content -LiteralPath $queuedReportPath -Raw) -notmatch 'EnterpriseInventory') "Hàng đợi báo cáo lưu dữ liệu rõ thay vì bảo vệ bằng DPAPI."
    $validation = Test-ToolReportEnvelope -Report $report -ExpectedReportKind "EnterpriseInventory" -ExpectedToolVersion "5.0"
    Assert-Enterprise ([bool]$validation.Valid) "Báo cáo EnterpriseInventory không đạt schema: $($validation.Errors -join '; ')"
    Assert-Enterprise (-not [bool]$report.Privacy.FullProductKeyIncluded) "Báo cáo khai báo chứa full product key."
    $reportJson = $report | ConvertTo-Json -Depth 14
    Assert-Enterprise ($reportJson -notmatch '(?i)[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}') "Báo cáo chứa chuỗi giống full product key."
    Assert-Enterprise ([string]$report.AssetIdentity.DeviceId -match '^VLS-DEV-[A-F0-9]{32}$' -and
        -not [bool]$report.Privacy.RawHardwareIdentifiersIncluded -and [bool]$report.Privacy.HashedAssetIdentityIncluded) 'Báo cáo Enterprise thiếu định danh tài sản đã băm.'
    Assert-Enterprise ($reportJson -notmatch [regex]::Escape($assetRawUuid) -and $reportJson -notmatch [regex]::Escape($assetRawSerial)) 'Báo cáo Enterprise làm lộ định danh phần cứng thô.'

    # Chạy listener thật trên loopback để kiểm tra toàn bộ đường đi từng bị lỗi
    # GetRequestStream: chẩn đoán TCP/dịch vụ, ghép nối và gửi báo cáo.
    $nativePowerShell = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-Path -LiteralPath $nativePowerShell -PathType Leaf)) {
        $nativePowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
    }
    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = "1"
    $hostOutput = Join-Path $testRoot "host.stdout.log"
    $hostError = Join-Path $testRoot "host.stderr.log"
    $hostScript = Join-Path $SourceDirectory "Tool-EnterpriseHost.ps1"
    $hostArguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$hostScript`""
    $hostProcess = Start-Process -FilePath $nativePowerShell -ArgumentList $hostArguments -WorkingDirectory $SourceDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $hostOutput -RedirectStandardError $hostError
    $liveDiagnostic = $null
    # Cold, memory-constrained validation VMs can register the HTTP.sys
    # listener before the PowerShell host has completed service startup. Keep
    # the same protocol/version gate, but allow the service up to 30 seconds to
    # return its first valid status response.
    $liveDeadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 150
        if ($hostProcess.HasExited) { break }
        $liveDiagnostic = Get-ToolEnterpriseConnectionDiagnostic -ServerAddress "127.0.0.1:$enterprisePort" -Port 49420 -TimeoutMs 1500
    } while (($null -eq $liveDiagnostic -or -not [bool]$liveDiagnostic.Success) -and [DateTime]::UtcNow -lt $liveDeadline)
    $hostFailure = ""
    if (Test-Path -LiteralPath $hostError -PathType Leaf) {
        $hostFailure = [string](Get-Content -LiteralPath $hostError -Raw -ErrorAction SilentlyContinue)
        if ($null -eq $hostFailure) { $hostFailure = "" } else { $hostFailure = $hostFailure.Trim() }
    }
    $diagnosticSummary = if ($null -ne $liveDiagnostic) { "$([string]$liveDiagnostic.Code) $([string]$liveDiagnostic.Message)" } else { "không tạo được kết quả chẩn đoán" }
    Assert-Enterprise ($null -ne $liveDiagnostic -and [bool]$liveDiagnostic.Success) "Listener loopback không sẵn sàng: $diagnosticSummary $hostFailure"
    $registeredClient = Register-ToolEnterpriseClient -ServerAddress "127.0.0.1:$enterprisePort" -Port 49420 -PairingCode $pairing -AllowRemoteLicenseChanges:$false -AutoSend:$true
    Assert-Enterprise ([bool]$registeredClient.Enrolled -and [string]$registeredClient.ClientId -eq [string]$client.ClientId) "Máy trạm không ghép nối được với listener thật."
    $pairingAfterEnrollment = Reset-ToolEnterprisePairingCode -AdminCode "Verify-Admin-4826" -ValidHours 24
    Assert-Enterprise ($pairingAfterEnrollment -ne $pairing) "Mã ghép nối không đổi sau yêu cầu tạo mã mới."
    $sendResponse = Send-ToolEnterpriseReport -Report $report
    Assert-Enterprise ([bool]$sendResponse.Accepted) "Máy trạm đã ghép nối bị ảnh hưởng khi luân chuyển mã ghép nối."
    $pairing = $pairingAfterEnrollment
    $receivedReports = @(Get-ChildItem -LiteralPath (Join-Path $paths.ServerReports $client.ClientId) -Filter "*.json" -File -ErrorAction SilentlyContinue)
    Assert-Enterprise ($receivedReports.Count -ge 1) "Máy chủ không lưu báo cáo nhận qua HTTP."
    $assetStore = Read-ToolAssetRegistryStore -RootPath $paths.ServerAssets
    Assert-Enterprise ($null -ne $assetStore -and @($assetStore.Devices).Count -eq 1 -and @($assetStore.Assets).Count -eq 1) 'Máy chủ không đăng ký đúng một Device/Asset từ báo cáo Agent.'
    $serverClientRecord = Read-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $client.ClientId) -MaximumBytes 1048576
    Assert-Enterprise ([string]$serverClientRecord.AssetMatchStatus -eq 'Created' -and
        [string]$serverClientRecord.DeviceId -eq [string]$assetIdentity.DeviceId -and
        -not [string]::IsNullOrWhiteSpace([string]$serverClientRecord.AssetId)) 'Bản ghi máy trạm không liên kết Asset Registry.'
    [void](Add-ToolAssetAssignmentEvent -Store $assetStore -AssetId ([string]$serverClientRecord.AssetId) -Action Assign -AssigneeType Department -AssigneeReference 'department:finance' -DisplayName 'Finance' -Reason 'Enterprise regression' -RecordedBy 'verifier')
    [void](Write-ToolAssetRegistryStore -Store $assetStore -RootPath $paths.ServerAssets)

    # Central Dashboard: static assets are public but contain no fleet
    # data; the read-only API requires a short-lived bearer token created by
    # an administrator and bound to the first source address.
    $wrongDashboardAdminRejected = $false
    try { [void](New-ToolEnterpriseDashboardSession -AdminCode 'Wrong-Admin' -ValidMinutes 30) }
    catch { $wrongDashboardAdminRejected = $true }
    Assert-Enterprise $wrongDashboardAdminRejected 'Mã quản trị sai lại tạo được phiên Dashboard.'

    $dashboardSession = New-ToolEnterpriseDashboardSession -AdminCode 'Verify-Admin-4826' -ValidMinutes 30
    Assert-Enterprise ([string]$dashboardSession.AccessToken -match '^[A-Za-z0-9_-]{43}$') 'Token Dashboard không đủ 256 bit/base64url.'
    $dashboardSessionText = Get-Content -LiteralPath $paths.ServerDashboardSession -Raw -Encoding UTF8
    Assert-Enterprise ($dashboardSessionText -notmatch [regex]::Escape([string]$dashboardSession.AccessToken)) 'Dashboard lưu access token rõ trên đĩa.'
    Assert-Enterprise ($dashboardSessionText -notmatch 'AdminVerifier|Pairing|ClientSecret') 'Bản ghi phiên Dashboard chứa dữ liệu xác thực ngoài allow-list.'

    $dashboardBaseUri = "http://127.0.0.1:$enterprisePort/tool/v1/dashboard"
    $dashboardStatic = Invoke-WebRequest -Uri ($dashboardBaseUri + '/') -Method Get -UseBasicParsing -TimeoutSec 10
    Assert-Enterprise ([int]$dashboardStatic.StatusCode -eq 200 -and $dashboardStatic.Content -match 'VietLicenSure Central') 'Trang Dashboard tĩnh không được listener phục vụ.'
    Assert-Enterprise ([string]$dashboardStatic.Headers['Content-Security-Policy'] -match "default-src 'none'" -and
        [string]$dashboardStatic.Headers['X-Frame-Options'] -eq 'DENY' -and
        [string]$dashboardStatic.Headers['Cache-Control'] -eq 'no-store') 'Dashboard thiếu CSP/frame/cache header fail-closed.'
    Assert-Enterprise ($dashboardStatic.Content -notmatch '(?i)https?://|innerHTML|document\.write|eval\(') 'Dashboard tĩnh tải tài nguyên ngoài hoặc dùng DOM sink không an toàn.'
    Assert-Enterprise ($dashboardStatic.Content -notmatch '(?i)>\s*(?:MVP|Pilot|Preview)\s*<') 'Dashboard chính thức vẫn hiển thị nhãn pilot/preview.'
    $dashboardCssResponse = Invoke-WebRequest -Uri ($dashboardBaseUri + '/app.css') -Method Get -UseBasicParsing -TimeoutSec 10
    Assert-Enterprise ([int]$dashboardCssResponse.StatusCode -eq 200 -and
        $dashboardCssResponse.Content -match '(?s)\.cards article\{[^}]*border:2px solid var\(--brand2\)' -and
        $dashboardCssResponse.Content -match '(?s)\.notice,\.disclaimer\{[^}]*border:2px solid var\(--warn\)' -and
        $dashboardCssResponse.Content -notmatch 'border-(?:left|top):(?:4|5)px') 'Dashboard chưa dùng viền màu bao quanh đầy đủ.'

    Assert-Enterprise ((Get-EnterpriseVerifierHttpStatus -Uri ($dashboardBaseUri + '/api/snapshot')) -eq 401) 'API Dashboard không token không trả 401.'
    Assert-Enterprise ((Get-EnterpriseVerifierHttpStatus -Uri ($dashboardBaseUri + '/api/snapshot') -Headers @{ Authorization=('Bearer ' + 'A'.PadRight(43, 'A')) }) -eq 401) 'API Dashboard chấp nhận token sai.'
    Assert-Enterprise ((Get-EnterpriseVerifierHttpStatus -Uri ($dashboardBaseUri + '/api/snapshot') -Method POST -Headers @{ Authorization=('Bearer ' + [string]$dashboardSession.AccessToken) }) -eq 404) 'Dashboard có endpoint POST hoặc thay đổi trạng thái ngoài phạm vi chỉ đọc.'

    $dashboardHeaders = @{ Authorization=('Bearer ' + [string]$dashboardSession.AccessToken) }
    $dashboardApi = Invoke-WebRequest -Uri ($dashboardBaseUri + '/api/snapshot') -Method Get -Headers $dashboardHeaders -UseBasicParsing -TimeoutSec 10
    Assert-Enterprise ([int]$dashboardApi.StatusCode -eq 200) 'API Dashboard không trả dữ liệu với token đúng.'
    $dashboardSnapshot = $dashboardApi.Content | ConvertFrom-Json
    Assert-Enterprise ([int]$dashboardSnapshot.Summary.Total -ge 1 -and @($dashboardSnapshot.Clients).Count -ge 1) 'API Dashboard không trả fleet hiện có.'
    $expectedDashboardServerFields = @('Name','ProtocolVersion','ToolVersion')
    $actualDashboardServerFields = @($dashboardSnapshot.Server.PSObject.Properties.Name | Sort-Object)
    Assert-Enterprise (@(Compare-Object ($expectedDashboardServerFields | Sort-Object) $actualDashboardServerFields).Count -eq 0) 'API Dashboard trả thêm trường Server ngoài allow-list.'
    $expectedDashboardClientFields = @(
        'AgeMinutes','Alerts','AssetMatchStatus','AssetReference','AssetStatus','AssignmentDisplayName','AssignmentHistoryCount','AssignmentType','ClientReference','ComplianceStatus','ComputerName','LastSeenUtc','LicenseIdentityChangedAtUtc',
        'OfficeAdvisor','OfficeChannel','OfficeEntitlementStatus','OfficeStatus','Presence','RemoteAddress','SoftwareSummary',
        'WindowsAdvisor','WindowsChannel','WindowsEntitlementStatus','WindowsStatus'
    )
    $actualDashboardClientFields = @($dashboardSnapshot.Clients[0].PSObject.Properties.Name | Sort-Object)
    Assert-Enterprise (@(Compare-Object ($expectedDashboardClientFields | Sort-Object) $actualDashboardClientFields).Count -eq 0) 'API Dashboard trả thêm trường máy trạm ngoài allow-list.'
    $expectedAdvisorFields = @(
        'Channel','Confidence','ConfidenceScope','CorrelationCode','EntitlementConclusion','EntitlementStatus','Evidence','EvidenceSourceCount',
        'Explanation','Finding','FindingCode','LicenseModel','Limitation','LimitationCode','OverallVerdict','ProductScope','Recommendation','RecommendationCode',
        'Risk','RuleId','RuleRevision','SchemaVersion','TamperingConclusion','TechnicalConclusion','TechnicalStatus'
    )
    foreach($advisorName in @('WindowsAdvisor','OfficeAdvisor')) {
        $advisorFields = @($dashboardSnapshot.Clients[0].$advisorName.PSObject.Properties.Name | Sort-Object)
        Assert-Enterprise (@(Compare-Object ($expectedAdvisorFields | Sort-Object) $advisorFields).Count -eq 0) "API Dashboard advisor ngoài schema chuẩn hóa: $advisorName"
        $findingFields = @($dashboardSnapshot.Clients[0].$advisorName.Finding.PSObject.Properties.Name | Sort-Object)
        $expectedFindingFields = @(
            'Confidence','ConfidenceScope','CorrelationCode','EntitlementConclusion','Evidence','EvidenceSourceCount','Explanation','FindingCode',
            'Limitation','OverallVerdict','ProductScope','Recommendation','Risk','RuleId','RuleRevision','SchemaVersion','SourceCoverage','State',
            'TamperingConclusion','TechnicalConclusion'
        )
        Assert-Enterprise (@(Compare-Object ($expectedFindingFields | Sort-Object) $findingFields).Count -eq 0) "API Dashboard Finding ngoài schema canonical: $advisorName"
        Assert-Enterprise ([string]$dashboardSnapshot.Clients[0].$advisorName.Finding.RuleId -eq [string]$dashboardSnapshot.Clients[0].$advisorName.RuleId) "API Dashboard Finding lệch Rule ID legacy: $advisorName"
        Assert-Enterprise ([string]$dashboardSnapshot.Clients[0].$advisorName.RuleId -match '^VLS-(?:WIN|OFF)-ACT-00[12]$') "API Dashboard advisor thiếu Rule ID ổn định: $advisorName"
        Assert-Enterprise ([string]$dashboardSnapshot.Clients[0].$advisorName.TamperingConclusion -eq 'NotAssessed') "API Dashboard advisor suy diễn dấu hiệu can thiệp khi chưa đánh giá: $advisorName"
    }
    Assert-Enterprise ([string]$dashboardSnapshot.Clients[0].WindowsEntitlementStatus -eq 'NotVerified' -and
        [string]$dashboardSnapshot.Clients[0].OfficeEntitlementStatus -eq 'NotVerified') 'Dashboard trộn trạng thái kỹ thuật với quyền sở hữu.'
    Assert-Enterprise ($null -ne $dashboardSnapshot.Compliance -and $null -ne $dashboardSnapshot.Compliance.Summary -and $null -ne $dashboardSnapshot.Summary.AssuranceScore) 'API Dashboard thiếu compliance summary.'
    Assert-Enterprise ([int]$dashboardSnapshot.Summary.Assets -eq 1 -and [int]$dashboardSnapshot.Summary.AssignedAssets -eq 1 -and
        [int]$dashboardSnapshot.Summary.UnassignedAssets -eq 0 -and [string]$dashboardSnapshot.Clients[0].AssignmentDisplayName -eq 'Finance' -and
        [int]$dashboardSnapshot.Clients[0].AssignmentHistoryCount -eq 1) 'Dashboard read-only không phản ánh đúng Asset/Assignment.'
    foreach ($forbiddenDashboardField in @('ClientId','DeviceId','AssetId','IdentifierDigests','WindowsLast5','OfficeLast5','LatestReportPath','AdminVerifier','AccessToken','TokenHash','StoredName','DocumentId')) {
        Assert-Enterprise ($dashboardApi.Content -notmatch ('"' + [regex]::Escape($forbiddenDashboardField) + '"')) "API Dashboard làm lộ trường cấm: $forbiddenDashboardField"
    }
    Assert-Enterprise ($dashboardApi.Content -notmatch [regex]::Escape([string]$client.ClientId)) 'API Dashboard làm lộ ClientId đầy đủ.'
    Assert-Enterprise ($dashboardApi.Content -notmatch '(?i)[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}') 'API Dashboard làm lộ chuỗi giống full product key.'
    Assert-Enterprise (-not (Test-ToolEnterpriseDashboardSession -AccessToken ([string]$dashboardSession.AccessToken) -RemoteAddress '127.0.0.2')) 'Token Dashboard dùng được từ IP khác sau khi đã khóa địa chỉ.'

    $expiredDashboardSession = New-ToolEnterpriseDashboardSession -AdminCode 'Verify-Admin-4826' -ValidMinutes 5
    $expiredDashboardRecord = Read-ToolEnterpriseJson -Path $paths.ServerDashboardSession -MaximumBytes 65536
    $expiredDashboardRecord.ExpiresAtUtc = [DateTime]::UtcNow.AddMinutes(-1).ToString('o')
    Write-ToolEnterpriseJson -Path $paths.ServerDashboardSession -Value $expiredDashboardRecord
    Assert-Enterprise (-not (Test-ToolEnterpriseDashboardSession -AccessToken ([string]$expiredDashboardSession.AccessToken) -RemoteAddress '127.0.0.1')) 'Token Dashboard hết hạn vẫn được chấp nhận.'

    # Status classification uses a dedicated fixture root so exact counts are
    # deterministic and cannot interfere with the live listener test above.
    try {
        $env:TOOL_ENTERPRISE_ROOT = $dashboardFixtureRoot
        $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = Join-Path $dashboardFixtureRoot 'enterprise-network-settings.json'
        [void](New-ToolEnterpriseServerConfiguration -ServerName 'DashboardFixture' -AdminCode 'Dashboard-Fixture-4826' -BindAddress '127.0.0.1' -Port (Get-AvailableLoopbackPort) -AllowedCidrs @('127.0.0.0/8'))
        $dashboardPaths = Get-ToolEnterprisePaths
        $dashboardNow = [DateTime]::UtcNow
        $dashboardRecords = @(
            [ordered]@{ ClientId=[Guid]::NewGuid().ToString('N'); ComputerName='DASH-ONLINE AAAAA-BBBBB-CCCCC-DDDDD-EEEEE'; RemoteAddress='10.0.0.10'; LastSeenUtc=$dashboardNow.AddMinutes(-20).ToString('o'); WindowsStatus='Licensed'; WindowsChannel='Retail'; OfficeStatus='Licensed'; OfficeChannel='MAK'; WindowsIdentityChanged=$false; OfficeIdentityChanged=$false; LicenseIdentityChangedAtUtc=$dashboardNow.AddDays(-1).ToString('o') },
            [ordered]@{ ClientId=[Guid]::NewGuid().ToString('N'); ComputerName='DASH-STALE'; RemoteAddress='10.0.0.11'; LastSeenUtc=$dashboardNow.AddHours(-2).ToString('o'); WindowsStatus='Notification'; WindowsChannel='Retail'; OfficeStatus='NotDetected'; OfficeChannel=''; WindowsIdentityChanged=$false; OfficeIdentityChanged=$false; LicenseIdentityChangedAtUtc='' },
            [ordered]@{ ClientId=[Guid]::NewGuid().ToString('N'); ComputerName='DASH-OFFLINE'; RemoteAddress='10.0.0.12'; LastSeenUtc=$dashboardNow.AddHours(-25).ToString('o'); WindowsStatus='Licensed'; WindowsChannel='OEM'; OfficeStatus='Licensed'; OfficeChannel='Retail'; WindowsIdentityChanged=$false; OfficeIdentityChanged=$false; LicenseIdentityChangedAtUtc='' }
        )
        foreach ($dashboardRecord in $dashboardRecords) {
            Write-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId ([string]$dashboardRecord.ClientId)) -Value $dashboardRecord
        }
        $classifiedDashboard = Get-ToolEnterpriseDashboardSnapshot
        Assert-Enterprise ([int]$classifiedDashboard.Summary.Total -eq 3 -and [int]$classifiedDashboard.Summary.Online -eq 1 -and
            [int]$classifiedDashboard.Summary.Stale -eq 1 -and [int]$classifiedDashboard.Summary.Offline -eq 1 -and
            [int]$classifiedDashboard.Summary.NeedsReview -eq 3) 'Dashboard phân loại Online/Stale/Offline/Cần xem lại sai.'
        Assert-Enterprise ((@($classifiedDashboard.Clients)[0].Alerts -contains 'LicenseIdentityChanged')) 'Dashboard làm mất cảnh báo đổi Last5 đã lưu.'
        $classifiedDashboardJson = $classifiedDashboard | ConvertTo-Json -Depth 12 -Compress
        Assert-Enterprise ($classifiedDashboardJson -notmatch '(?i)[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}' -and
            $classifiedDashboardJson -notmatch 'LatestReportPath|WindowsLast5|OfficeLast5|"ClientId"') 'Dashboard fixture làm lộ dữ liệu ngoài allow-list.'
    } finally {
        $env:TOOL_ENTERPRISE_ROOT = $testRoot
        $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = Join-Path $testRoot 'enterprise-network-settings.json'
    }
    $paths = Get-ToolEnterprisePaths

    # Mô phỏng đúng hai máy: tiến trình máy chủ vẫn dùng $testRoot, còn mọi
    # cấu hình/secret/outbox của máy trạm nằm ở một root hoàn toàn độc lập.
    $separateClientId = ''
    try {
        $env:TOOL_ENTERPRISE_ROOT = $separateClientRoot
        $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = Join-Path $separateClientRoot 'enterprise-network-settings.json'
        $separateClient = Register-ToolEnterpriseClient -ServerAddress "127.0.0.1:$enterprisePort" -Port 49420 -PairingCode $pairing -AllowRemoteLicenseChanges:$false -AutoSend:$true
        $separateClientId = [string]$separateClient.ClientId
        $separatePaths = Get-ToolEnterprisePaths
        Assert-Enterprise ([bool]$separateClient.Enrolled -and (Test-Path -LiteralPath $separatePaths.ClientSecret -PathType Leaf)) 'Máy trạm ở kho dữ liệu độc lập không ghép nối/ghi secret được.'
        Assert-Enterprise ([string]$separatePaths.Root -ne [string]$paths.Root -and
            [string]$separatePaths.ClientConfig -like (([string]$separatePaths.Root).TrimEnd('\') + '\*')) 'Fixture máy trạm còn vô tình dùng chung kho dữ liệu với máy chủ.'
        $separateReport = Get-ToolEnterpriseLicenseSnapshot -ClientId $separateClientId
        $separateSendResponse = Send-ToolEnterpriseReport -Report $separateReport
        Assert-Enterprise ([bool]$separateSendResponse.Accepted) 'Máy trạm có kho dữ liệu độc lập không gửi được báo cáo.'
    } finally {
        $env:TOOL_ENTERPRISE_ROOT = $testRoot
        $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = Join-Path $testRoot 'enterprise-network-settings.json'
    }
    $paths = Get-ToolEnterprisePaths
    $separateReceivedReports = @(Get-ChildItem -LiteralPath (Join-Path $paths.ServerReports $separateClientId) -Filter '*.json' -File -ErrorAction SilentlyContinue)
    Assert-Enterprise ($separateReceivedReports.Count -ge 1) 'Máy chủ không lưu báo cáo gửi từ máy trạm có kho dữ liệu độc lập.'

    $clientSecret = New-ToolEnterpriseRandomBytes -Length 32
    Set-ToolEnterpriseServerClientSecret -ClientId $client.ClientId -Secret $clientSecret
    $record = [pscustomobject][ordered]@{
    SchemaVersion="1.0"; ToolVersion="5.0"; ClientId=$client.ClientId; ComputerName="VERIFY-CLIENT"
        RemoteAddress="127.0.0.1"; NetworkAddresses=@("127.0.0.1"); LastSeenUtc=[DateTime]::UtcNow.ToString("o")
        FirstSeenUtc=[DateTime]::UtcNow.ToString("o"); AllowRemoteLicenseChanges=$true
        WindowsStatus="NotReported"; WindowsChannel=""; WindowsLast5=""
        OfficeStatus="NotReported"; OfficeChannel=""; OfficeLast5=""; LatestReportPath=""
    }
    Write-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $client.ClientId) -Value $record
    $testKey = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE"
    $job = New-ToolEnterpriseLicenseJob -ClientId $client.ClientId -Operation "WindowsInstallAndActivate" -ProductKey $testKey -RequestedBy "Verifier"
    $jobPath = Join-Path (Join-Path $paths.ServerJobs $client.ClientId) ($job.JobId + ".job")
    $jobText = Get-Content -LiteralPath $jobPath -Raw
    Assert-Enterprise ($jobText -notmatch [regex]::Escape($testKey)) "Job trên đĩa làm lộ full product key."
    $jobPackage = Get-ToolEnterprisePendingJobPackage -ClientId $client.ClientId
    $jobOpened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext ("job:{0}:{1}" -f $client.ClientId, $job.JobId) -Envelope $jobPackage.Envelope -MaximumAgeMinutes 10
    Assert-Enterprise ([string]$jobOpened.Payload.ProductKey -eq $testKey) "Máy trạm không giải mã đúng payload tác vụ."
    Assert-Enterprise ([string]$job.ProductKeyLast5 -eq "EEEEE") "Tác vụ không trả đúng last5."
    $auditText = Get-Content -LiteralPath $paths.ServerAudit -Raw
    Assert-Enterprise ($auditText -notmatch [regex]::Escape($testKey)) "Audit làm lộ full product key."

    $cidr = Get-ToolEnterpriseCidrInfo -Cidr "10.20.41.24/22"
    Assert-Enterprise ([string]$cidr.Cidr -eq "10.20.40.0/22") "Chuẩn hóa CIDR /22 sai."
    Assert-Enterprise ([uint64]$cidr.HostCount -eq 1022) "Số host CIDR /22 sai."
    Assert-Enterprise (Test-ToolEnterpriseIpInCidr -Address "10.20.43.254" -Cidr $cidr.Cidr) "Kiểm tra IP trong CIDR sai."
    $tooLargeRejected = $false
    try { [void](Get-ToolEnterpriseCidrAddresses -Cidr "10.0.0.0/16") } catch { $tooLargeRejected = $true }
    Assert-Enterprise $tooLargeRejected "Quét vượt 1024 host không bị chặn."
    $localProfiles = @(Get-ToolEnterpriseLocalIPv4Profiles)
    foreach ($profile in $localProfiles) {
        Assert-Enterprise (Test-ToolEnterpriseHostName -Value ([string]$profile.Address)) "Nhận diện card mạng trả IPv4 không hợp lệ."
        Assert-Enterprise (Test-ToolEnterpriseIpInCidr -Address ([string]$profile.Address) -Cidr ([string]$profile.Cidr)) "IPv4 tự nhận không thuộc CIDR tương ứng."
    }
    if ($localProfiles.Count -gt 0) {
        Assert-Enterprise ([string](Get-ToolEnterprisePreferredServerAddress) -eq [string]$localProfiles[0].Address) "IP máy chủ ưu tiên không khớp thứ tự card mạng."
    }
    foreach ($discoveryCidr in @(Get-ToolEnterpriseLocalDiscoveryCidrs)) {
        Assert-Enterprise ([uint64](Get-ToolEnterpriseCidrInfo -Cidr $discoveryCidr).HostCount -le 1024) "CIDR tự dò máy chủ vượt giới hạn 1024 host."
    }

    New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
    $export = Export-ToolEnterpriseFleetReport -DestinationDirectory $exportRoot
    foreach ($path in @($export.JsonPath,$export.CsvPath,$export.HtmlPath,$export.ManifestPath)) {
        Assert-Enterprise (Test-Path -LiteralPath $path -PathType Leaf) "Thiếu artefact fleet: $path"
    }

    $preservedReportPath = Join-Path (Join-Path $paths.ServerReports $client.ClientId) "preserve-after-reset.json"
    $preservedResultPath = Join-Path (Join-Path $paths.ServerResults $client.ClientId) "preserve-after-reset.json"
    Write-ToolEnterpriseJson -Path $preservedReportPath -Value ([ordered]@{ Kind="PreservedReport"; ClientId=$client.ClientId })
    Write-ToolEnterpriseJson -Path $preservedResultPath -Value ([ordered]@{ Kind="PreservedResult"; ClientId=$client.ClientId })

    $wrongResetRejected = $false
    try { [void](Remove-ToolEnterpriseServerConfiguration -AdminCode "Wrong-Admin" -StopTimeoutSeconds 1) }
    catch { $wrongResetRejected = $true }
    Assert-Enterprise $wrongResetRejected "Mã quản trị sai lại xóa được cấu hình máy chủ."
    Assert-Enterprise (Test-Path -LiteralPath $paths.ServerConfig -PathType Leaf) "Lần xóa bằng mã sai đã làm mất server.json."
    Assert-Enterprise (Test-Path -LiteralPath $paths.ServerMasterSecret -PathType Leaf) "Lần xóa bằng mã sai đã làm mất master secret."

    $reset = Remove-ToolEnterpriseServerConfiguration -AdminCode "Verify-Admin-4826" -StopTimeoutSeconds 1
    Assert-Enterprise ([bool]$reset.Removed) "Hàm xóa cấu hình không trả trạng thái thành công."
    Assert-Enterprise ([bool]$reset.AuditWritten) "Xóa cấu hình không ghi được audit hoàn tất."
    foreach ($removedPath in @($paths.ServerConfig,$paths.ServerMasterSecret,$paths.ServerPairingSecret,$paths.ServerDashboardSession,$paths.ServerPid,$paths.ServerHeartbeat,$paths.ServerStop,$paths.ServerError)) {
        Assert-Enterprise (-not (Test-Path -LiteralPath $removedPath -PathType Leaf)) "Xóa cấu hình còn sót tệp: $removedPath"
    }
    foreach ($clearedDirectory in @($paths.ServerClients,$paths.ServerClientSecrets,$paths.ServerJobs)) {
        Assert-Enterprise (@(Get-ChildItem -LiteralPath $clearedDirectory -Force -Recurse -ErrorAction SilentlyContinue).Count -eq 0) "Xóa cấu hình còn trạng thái hoạt động trong: $clearedDirectory"
    }
    Assert-Enterprise (Test-Path -LiteralPath $preservedReportPath -PathType Leaf) "Xóa cấu hình làm mất báo cáo lịch sử."
    Assert-Enterprise (Test-Path -LiteralPath $preservedResultPath -PathType Leaf) "Xóa cấu hình làm mất kết quả lịch sử."
    Assert-Enterprise (Test-Path -LiteralPath $paths.ServerAudit -PathType Leaf) "Xóa cấu hình làm mất audit."
    Assert-Enterprise ($null -eq (Get-ToolEnterpriseServerConfig)) "Cấu hình máy chủ vẫn còn sau khi xóa."
    $resetAuditText = Get-Content -LiteralPath $paths.ServerAudit -Raw
    Assert-Enterprise ($resetAuditText -match 'Server\.ConfigurationResetRequested' -and $resetAuditText -match 'Server\.ConfigurationResetCompleted') "Audit thiếu sự kiện yêu cầu/hoàn tất xóa cấu hình."
    $serverAfterReset = New-ToolEnterpriseServerConfiguration -ServerName "EnterpriseVerificationAfterReset" -AdminCode "Verify-Admin-After-Reset" -BindAddress "127.0.0.1" -Port $enterprisePort -AllowedCidrs @("127.0.0.0/8")
    Assert-Enterprise ([string]$serverAfterReset.ServerName -eq "EnterpriseVerificationAfterReset") "Không tạo lại được máy chủ sau khi xóa cấu hình."

    $catalog = Get-ToolModuleCatalog
    foreach ($moduleId in @("license.manager","license.manager.local","enterprise.server","enterprise.agent")) {
        Assert-Enterprise (@($catalog | Where-Object ModuleId -eq $moduleId).Count -eq 1) "Module contract thiếu $moduleId."
    }
    $managerContract = @($catalog | Where-Object ModuleId -eq "license.manager")[0]
    Assert-Enterprise ([string]$managerContract.NetworkScope -eq "LocalOnly") "Mở Mục 8 phải hoạt động Offline; chỉ tiến trình server/agent mới dùng LAN."
    $launcherText = Get-Content -LiteralPath (Join-Path $SourceDirectory "VietLicenSure-v5.0-OneFile.cs") -Raw
    foreach ($mode in @("--enterprise-ui","--enterprise-server","--enterprise-agent","--enterprise-agent-force","--local-license-manager")) {
        Assert-Enterprise ($launcherText.Contains($mode)) "Launcher thiếu mode $mode."
    }
    Assert-Enterprise ($launcherText -notmatch 'mode\s*==\s*LaunchMode\.EnterpriseUi\s*\|\|\s*mode\s*==\s*LaunchMode\.EnterpriseServer') "Launcher vẫn chặn giao diện Mục 8 khi Offline."
    Assert-Enterprise ($launcherText -match 'ResolveEnterpriseNetworkAllowed' -and
        $launcherText -match 'TOOL_ENTERPRISE_NETWORK_ALLOWED' -and
        $launcherText -match 'mode\s*==\s*LaunchMode\.EnterpriseServer\s*\|\|\s*mode\s*==\s*LaunchMode\.EnterpriseAgent') "Launcher không còn chặn riêng tiến trình mạng server/agent theo công tắc Mục 8."
    $dashboardText = Get-VietLicenSureComposedSourceText -SourceDirectory $SourceDirectory -EntrypointName 'Giao-Dien.ps1'
    Assert-Enterprise ($dashboardText -match 'Start-Process\s+-FilePath\s+\$launcherPath\s+-ArgumentList\s+"--enterprise-ui"' -and
        $dashboardText -match '-File\s+`"\$licenseManagerScript`"' -and
        $dashboardText -notmatch '\$licenseLaunchMode\s*=\s*if\s*\(\$script:offlineMode\)' -and
        $dashboardText -notmatch 'máy chủ/máy trạm bị ẩn') "Dashboard chưa luôn mở đủ trung tâm Mục 8 như v4.2.0.8."
    $enterpriseUiPath = Join-Path $SourceDirectory "enterprise-license-manager.ps1"
    $enterpriseUiText = Get-Content -LiteralPath $enterpriseUiPath -Raw -Encoding UTF8
    $enterpriseUiTokens = $null
    $enterpriseUiParseErrors = $null
    $enterpriseUiAst = [Management.Automation.Language.Parser]::ParseFile($enterpriseUiPath, [ref]$enterpriseUiTokens, [ref]$enterpriseUiParseErrors)
    Assert-Enterprise (@($enterpriseUiParseErrors).Count -eq 0) 'Giao diện enterprise lỗi cú pháp.'
    $lifecycleXmlFunction = $enterpriseUiAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-EnterpriseLifecycleTaskXml'
    }, $true)
    Assert-Enterprise ($null -ne $lifecycleXmlFunction) 'Thiếu trình tạo task vòng đời server/agent.'
    if ($lifecycleXmlFunction) {
        $lifecycleDefinition = $lifecycleXmlFunction.Extent.Text -replace '^function\s+New-EnterpriseLifecycleTaskXml', 'function script:New-EnterpriseLifecycleTaskXml'
        Invoke-Expression $lifecycleDefinition
        $launcherFixture = Join-Path $SourceDirectory 'VietLicenSure-v5.0.exe'
        $serverTaskXml = [xml](New-EnterpriseLifecycleTaskXml -Role Server -LauncherPath $launcherFixture)
        $agentTaskXml = [xml](New-EnterpriseLifecycleTaskXml -Role Agent -LauncherPath $launcherFixture)
        Assert-Enterprise ($serverTaskXml.FirstChild.Encoding -eq 'UTF-16' -and
            $agentTaskXml.FirstChild.Encoding -eq 'UTF-16') 'Task XML phải khai báo UTF-16 để khớp byte ghi cho schtasks.exe.'
        $taskNamespace = New-Object Xml.XmlNamespaceManager($serverTaskXml.NameTable)
        $taskNamespace.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
        Assert-Enterprise ($null -ne $serverTaskXml.SelectSingleNode('//t:BootTrigger', $taskNamespace) -and
            $null -ne $serverTaskXml.SelectSingleNode('//t:LogonTrigger', $taskNamespace) -and
            $null -eq $serverTaskXml.SelectSingleNode('//t:CalendarTrigger', $taskNamespace) -and
            [string]$serverTaskXml.SelectSingleNode('//t:Arguments', $taskNamespace).InnerText -eq '--enterprise-server' -and
            [string]$serverTaskXml.SelectSingleNode('//t:UserId', $taskNamespace).InnerText -eq 'S-1-5-18' -and
            $null -eq $serverTaskXml.SelectSingleNode('//t:LogonType', $taskNamespace) -and
            [string]$serverTaskXml.SelectSingleNode('//t:ExecutionTimeLimit', $taskNamespace).InnerText -eq 'PT0S') 'Task máy chủ không chạy đúng lúc boot/logon dưới SYSTEM hoặc còn giới hạn thời gian.'
        $agentNamespace = New-Object Xml.XmlNamespaceManager($agentTaskXml.NameTable)
        $agentNamespace.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
        $agentSubscription = [string]$agentTaskXml.SelectSingleNode('//t:EventTrigger/t:Subscription', $agentNamespace).InnerText
        Assert-Enterprise ($null -ne $agentTaskXml.SelectSingleNode('//t:BootTrigger', $agentNamespace) -and
            $null -ne $agentTaskXml.SelectSingleNode('//t:LogonTrigger', $agentNamespace) -and
            $null -ne $agentTaskXml.SelectSingleNode('//t:CalendarTrigger', $agentNamespace) -and
            [string]$agentTaskXml.SelectSingleNode('//t:CalendarTrigger/t:Repetition/t:Interval', $agentNamespace).InnerText -eq 'PT1H' -and
            $agentSubscription -match 'Power-Troubleshooter' -and $agentSubscription -match 'EventID=1' -and
            [string]$agentTaskXml.SelectSingleNode('//t:Arguments', $agentNamespace).InnerText -eq '--enterprise-agent') 'Task agent thiếu trigger boot/logon/resume/mỗi giờ.'
        $expectedWorkingDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($launcherFixture))
        Assert-Enterprise ([string]$serverTaskXml.SelectSingleNode('//t:WorkingDirectory', $taskNamespace).InnerText -eq $expectedWorkingDirectory -and
            [string]$agentTaskXml.SelectSingleNode('//t:WorkingDirectory', $agentNamespace).InnerText -eq $expectedWorkingDirectory) 'Task vòng đời còn ghim thư mục payload tạm thay vì thư mục EXE.'
    }
    Assert-Enterprise ($enterpriseUiText -match '\[Text\.Encoding\]::Unicode' -and
        $enterpriseUiText -notmatch 'Text\.UTF8Encoding\(\$true\)' -and
        $enterpriseUiText -notmatch '<LogonType>ServiceAccount</LogonType>') 'Trình cài task chưa ghi XML UTF-16 hợp lệ cho Task Scheduler hoặc còn LogonType không hợp lệ.'
    Assert-Enterprise ($enterpriseUiText -notmatch '[“”‘’]') "Giao diện enterprise chứa dấu ngoặc kép cong có thể làm PowerShell tách sai tham số."
    Assert-Enterprise ($enterpriseUiText -notmatch '(?<!\$)\(if\s*\(') "Giao diện enterprise chứa biểu thức ngoặc-if không hợp lệ khi chạy; hãy dùng biến trung gian hoặc subexpression PowerShell."
    Assert-Enterprise ($enterpriseUiText -match 'function\s+Fit-EnterpriseWindowToWorkingArea' -and
        $enterpriseUiText -match 'function\s+Update-EnterpriseLayout' -and
        $enterpriseUiText -match 'function\s+Set-EnterpriseAdaptiveButtonRows' -and
        $enterpriseUiText -match 'function\s+Get-EnterpriseClippedButtonLabels' -and
        $enterpriseUiText -match 'AutoScaleMode\]::Dpi' -and
        $enterpriseUiText -match 'HorizontalScroll\.Visible') "Giao diện enterprise thiếu layout thích ứng DPI hoặc kiểm tra chống tràn ngang."
    Assert-Enterprise ($enterpriseUiText -match 'Get-ToolEnterpriseLocalCidrs' -and
        $enterpriseUiText -match '\$script:scanInputBox\.Text\s*=\s*\$input' -and
        $enterpriseUiText -match '\$hostLabel\s*=\s*if\s*\(\$device\.HostName\)' -and
        $enterpriseUiText -match 'enterprise\.server\.scanResultLine' -and
        $enterpriseUiText -match 'enterprise\.server\.scanHostUnknown') "Quét nhanh chưa tự nhận CIDR hoặc hiển thị rõ IP/độ trễ/tên máy."
    Assert-Enterprise ($enterpriseUiText -match 'Get-ToolEnterprisePreferredServerAddress' -and
        $enterpriseUiText -match 'Find-ToolEnterpriseLocalServers' -and
        $enterpriseUiText -match 'enterprise\.client\.discover') "Giao diện chưa tự nhận IP LAN hoặc tự dò máy chủ."
    Assert-Enterprise ($enterpriseUiText -match 'Invoke-ServerDeleteConfiguration' -and
        $enterpriseUiText -match 'enterprise\.server\.delete' -and
        $enterpriseUiText -match 'enterprise\.server\.deletePrompt') "Giao diện thiếu luồng xóa cấu hình có xác nhận."
    Assert-Enterprise ($enterpriseUiText -match 'Reset-ToolEnterprisePairingCode.+?-ValidHours\s+24' -and
        $enterpriseUiText -match 'function\s+Install-EnterpriseLifecycleTask' -and
        $enterpriseUiText -match 'function\s+Remove-EnterpriseLifecycleTasks' -and
        $enterpriseUiText -match 'sddl=D:\(A;;GX;;;\$currentUserSid\)\(A;;GX;;;SY\)' -and
        $enterpriseUiText.IndexOf('Wait-EnterpriseServerReady', [StringComparison]::Ordinal) -lt $enterpriseUiText.IndexOf('Install-EnterpriseLifecycleTask -Role Server', [StringComparison]::Ordinal) -and
        $enterpriseUiText -match 'Stop-EnterpriseServer[\s\S]+?Remove-EnterpriseLifecycleTasks\s+-Role\s+Server') 'Vòng đời LAN chưa khóa mã mới, URL ACL SYSTEM hoặc tự khởi động/dừng fail-closed.'
    Assert-Enterprise ($enterpriseUiText -notmatch 'Mục "Trên máy này"|\$localTab' -and
        $enterpriseUiText -match 'enterprise\.status\.choose' -and
        $enterpriseUiText -match 'enterprise\.local\.tab' -and
        $enterpriseUiText -match '--local-license-manager' -and
        $enterpriseUiText -match 'enterprise\.navigation\.close' -and
        $enterpriseUiText -match 'Invoke-EnterpriseBack' -and
        $enterpriseUiText -match 'RectangleF') "Giao diện mục 8 chưa chuyển sang chọn chức năng hoặc thiếu điều hướng phiên."
    $viCatalog = Get-Content -LiteralPath (Join-Path $SourceDirectory "Tool-Strings.vi-VN.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $enCatalog = Get-Content -LiteralPath (Join-Path $SourceDirectory "Tool-Strings.en-US.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($preservedKey in @(
        "enterprise.local.tab",
        "enterprise.server.tab",
        "enterprise.client.tab",
        "enterprise.server.create",
        "enterprise.server.pair",
        "enterprise.server.start",
        "enterprise.server.stop",
        "enterprise.server.delete",
        "enterprise.server.firewall",
        "enterprise.server.assetSummary",
        "enterprise.server.assetColumn",
        "enterprise.server.assignmentColumn",
        "enterprise.server.assetPending",
        "enterprise.server.assetUnassigned",
        "enterprise.server.assetDetailsTitle",
        "enterprise.server.assetDetailsEmpty",
        "enterprise.server.assetDetailsLine",
        "enterprise.server.refresh",
        "enterprise.server.export",
        "enterprise.server.dashboard",
        "enterprise.server.scan",
        "enterprise.server.scanResultLine",
        "enterprise.server.scanHostUnknown",
        "enterprise.server.createJob",
        "enterprise.client.discover",
        "enterprise.client.test",
        "enterprise.client.enroll",
        "enterprise.client.send",
        "enterprise.client.enableAgent",
        "enterprise.client.disableAgent",
        "enterprise.client.assetSummaryTitle",
        "enterprise.client.assetSummary",
        "enterprise.client.assetEnrolled",
        "enterprise.client.assetNotEnrolled",
        "enterprise.client.assetNeverSynced",
        "enterprise.server.startedWithAutostart",
        "enterprise.server.stopRequestedAutostartDisabled",
        "enterprise.client.scheduleEnabledLifecycle",
        "enterprise.lifecycle.serverSummary",
        "enterprise.lifecycle.clientSummary"
    )) {
        Assert-Enterprise ($enterpriseUiText.Contains($preservedKey) -and
            $null -ne $viCatalog.PSObject.Properties[$preservedKey] -and
            $null -ne $enCatalog.PSObject.Properties[$preservedKey]) "Mục 8 làm mất hoặc chưa dịch chức năng: $preservedKey"
    }
    foreach ($assetDashboardKey in @(
        'enterpriseDashboard.ui.assets','enterpriseDashboard.ui.assetAssigned','enterpriseDashboard.ui.assetUnassigned',
        'enterpriseDashboard.ui.assetConflicts','enterpriseDashboard.ui.assetLabel','enterpriseDashboard.ui.assignedTo',
        'enterpriseDashboard.ui.unassigned','enterpriseDashboard.ui.alert.assetConflict'
    )) {
        Assert-Enterprise ($null -ne $viCatalog.PSObject.Properties[$assetDashboardKey] -and
            $null -ne $enCatalog.PSObject.Properties[$assetDashboardKey]) "Dashboard Asset Registry thiếu bản dịch: $assetDashboardKey"
    }
    Assert-Enterprise ($enterpriseUiText -match 'Get-ToolEnterpriseAssetReference' -and
        $enterpriseUiText -match 'Get-ToolCurrentAssetAssignment' -and
        $enterpriseUiText -match 'enterprise\.server\.assetSummary' -and
        $enterpriseUiText -match 'enterprise\.server\.assetColumn' -and
        $enterpriseUiText -match 'enterprise\.server\.assignmentColumn' -and
        $enterpriseUiText -match 'function\s+Update-EnterpriseServerAssetDetails' -and
        $enterpriseUiText -match 'enterprise\.server\.assetDetailsLine' -and
        $enterpriseUiText -match 'function\s+Update-EnterpriseClientAssetSummary' -and
        $enterpriseUiText -match 'enterprise\.client\.assetSummary') 'UI máy chủ/máy trạm chưa hiển thị trực tiếp Asset Registry và trạng thái bàn giao.'
    foreach ($assetManagerKey in @(
        'enterprise.assetManager.open','enterprise.assetManager.title','enterprise.assetManager.filter',
        'enterprise.assetManager.assignOrReassign','enterprise.assetManager.release',
        'enterprise.assetManager.viewHistory','enterprise.assetManager.assignmentTitle',
        'enterprise.assetManager.referenceRequired','enterprise.assetManager.confirmRelease',
        'enterprise.assetManager.historyTitle','enterprise.assetManager.unavailable'
    )) {
        Assert-Enterprise ($enterpriseUiText.Contains($assetManagerKey) -and
            $null -ne $viCatalog.PSObject.Properties[$assetManagerKey] -and
            $null -ne $enCatalog.PSObject.Properties[$assetManagerKey]) "Giao diện quản lý Asset Registry thiếu hoặc chưa dịch: $assetManagerKey"
    }
    Assert-Enterprise ($enterpriseUiText -match 'function\s+Show-EnterpriseAssetRegistryManager' -and
        $enterpriseUiText -match 'function\s+Show-EnterpriseAssetAssignmentDialog' -and
        $enterpriseUiText -match 'function\s+Show-EnterpriseAssetHistoryDialog' -and
        $enterpriseUiText -match 'Add-ToolAssetAssignmentEvent' -and
        $enterpriseUiText -match 'Write-ToolAssetRegistryStore' -and
        $enterpriseUiText -match "-Action\s+Release") 'UI Asset Registry chưa nối đủ tìm/lọc, gán/chuyển giao, thu hồi và lịch sử.'
    Assert-Enterprise ($enterpriseUiText -match 'function\s+Enable-EnterpriseNetworkAccess' -and
        $enterpriseUiText -match 'function\s+Disable-EnterpriseNetworkAccess' -and
        $enterpriseUiText -match 'function\s+Toggle-EnterpriseNetworkAccess' -and
        $enterpriseUiText -match 'function\s+Confirm-EnterpriseNetworkAccess' -and
        $enterpriseUiText -match 'Set-ToolEnterpriseNetworkAllowedPreference' -and
        $enterpriseUiText -notmatch 'Mục 8 vẫn giữ nguyên đủ 3 chức năng.+v4\.2\.0\.8') "Mục 8 chưa có công tắc mạng bật/tắt riêng hoặc vẫn còn câu cảnh báo cũ."
    Assert-Enterprise ($enterpriseUiText -match 'Tool-UiTheme\.ps1' -and
        $enterpriseUiText -match 'Get-ToolUiTheme' -and
        $enterpriseUiText -match '\$script:enterpriseDark' -and
        $enterpriseUiText -match '\$env:TOOL_UI_THEME\s*=\s*\$script:enterpriseTheme' -and
        $enterpriseUiText -match 'Get-ToolUiContrastRatio') "Chức năng 8 chưa nhận dark mode chung, truyền theme qua UAC hoặc kiểm tra tương phản."
    $localManagerPath = Join-Path $SourceDirectory "windows-office-license-manager.ps1"
    $localManagerText = Get-Content -LiteralPath $localManagerPath -Raw -Encoding UTF8
    Assert-Enterprise ($localManagerText -match 'Tool-UiTheme\.ps1' -and
        $localManagerText -match 'Get-ToolUiTheme' -and
        $localManagerText -match 'Set-ToolWindowTheme\s+-Root\s+\$form' -and
        $localManagerText -match 'Get-LocalLicenseText' -and
        $localManagerText -match 'Test-ToolEnterpriseNetworkActionAllowed') "Trình quản lý cục bộ Windows/Office chưa nhận theme, ngôn ngữ hoặc công tắc mạng Mục 8."
    $localManagerTokens = $null
    $localManagerParseErrors = $null
    $localManagerAst = [Management.Automation.Language.Parser]::ParseFile($localManagerPath, [ref]$localManagerTokens, [ref]$localManagerParseErrors)
    Assert-Enterprise (@($localManagerParseErrors).Count -eq 0) 'Trình quản lý cục bộ Windows/Office lỗi cú pháp.'
    foreach ($functionName in @(
        'ConvertTo-LocalLicenseStateCode','Get-WindowsActivationState','Get-OfficeLicenseRecordsFromStatus',
        'Get-OfficeActivationState','Test-LocalLicenseActivationConfirmed','Wait-LocalLicensePostCheck'
    )) {
        $functionAst = $localManagerAst.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
        }, $true)
        Assert-Enterprise ($null -ne $functionAst) "Trình quản lý cục bộ thiếu hậu kiểm: $functionName"
        if ($functionAst) {
            $functionDefinition = $functionAst.Extent.Text -replace ('^function\s+' + [regex]::Escape($functionName)), ('function script:' + $functionName)
            Invoke-Expression $functionDefinition
        }
    }
    Assert-Enterprise ($localManagerText -match '/dstatusall' -and
        $localManagerText -match 'LICENSE STATUS' -and
        $localManagerText -match 'RequestedKeyActivationConfirmed' -and
        $localManagerText -match 'ms-settings:activation') 'Trình quản lý cục bộ chưa hậu kiểm Windows/Office hoặc chưa mở Activation chính thức.'
    Assert-Enterprise ($localManagerText -notmatch 'Write-(?:ToolLog|LicenseTimelineEvent)' -and
        $localManagerText -notmatch 'TOOL_(?:LOG|TIMELINE)') 'Trình quản lý cục bộ không được ghi product key vào log/timeline.'

    $windowsLicensedFixture = Get-WindowsActivationState -ExpectedLast5 'ABCDE' -LicenseQuery {
        [pscustomobject]@{ Name='Windows(R), Professional edition'; LicenseStatus=1; PartialProductKey='ABCDE' }
    }
    $windowsWrongKeyFixture = Get-WindowsActivationState -ExpectedLast5 'ZZZZZ' -LicenseQuery {
        [pscustomobject]@{ Name='Windows(R), Professional edition'; LicenseStatus=1; PartialProductKey='ABCDE' }
    }
    $windowsNotificationFixture = Get-WindowsActivationState -ExpectedLast5 'ABCDE' -LicenseQuery {
        [pscustomobject]@{ Name='Windows(R), Professional edition'; LicenseStatus=5; PartialProductKey='ABCDE' }
    }
    Assert-Enterprise ((Test-LocalLicenseActivationConfirmed $windowsLicensedFixture) -and
        -not (Test-LocalLicenseActivationConfirmed $windowsWrongKeyFixture) -and
        -not (Test-LocalLicenseActivationConfirmed $windowsNotificationFixture) -and
        [string]$windowsNotificationFixture.StateCode -eq 'Notification') 'Windows đang coi exit code/key khác/Notification là ActivationConfirmed=True.'

    $officeStatusFixture = @'
---------------------------------------
LICENSE NAME: Office 24, Office24ProPlus2024VL_MAK_AE edition
LICENSE STATUS:  ---LICENSED---
Last 5 characters of installed product key: ABCDE
---------------------------------------
LICENSE NAME: Office 24, Office24Visio2024VL_MAK_AE edition
LICENSE STATUS:  ---NOTIFICATIONS---
Last 5 characters of installed product key: ZZZZZ
---------------------------------------
'@
    $officeLicensedFixture = Get-OfficeActivationState -OsppPaths @('fixture-ospp.vbs') -ExpectedLast5 'ABCDE' -StatusInvoker {
        param($Path)
        [pscustomobject]@{ ExitCode=0; Output=$officeStatusFixture }
    }
    $officeWrongKeyFixture = Get-OfficeActivationState -OsppPaths @('fixture-ospp.vbs') -ExpectedLast5 'ZZZZZ' -StatusInvoker {
        param($Path)
        [pscustomobject]@{ ExitCode=0; Output=$officeStatusFixture }
    }
    Assert-Enterprise ((Test-LocalLicenseActivationConfirmed $officeLicensedFixture) -and
        -not (Test-LocalLicenseActivationConfirmed $officeWrongKeyFixture) -and
        [string]$officeLicensedFixture.ProductKeyLast5 -eq 'ABCDE') 'Office chưa buộc /dstatusall báo ---LICENSED--- cho đúng Last5/SKU sau /act.'
    foreach ($activationKey in @(
        'localLicense.windows.status.activated','localLicense.windows.status.notActivated','localLicense.windows.activationConfirmed','localLicense.windows.activationPending',
        'localLicense.office.status.activated','localLicense.office.status.notActivated','localLicense.office.activationConfirmed','localLicense.office.activationPending'
    )) {
        Assert-Enterprise ($null -ne $viCatalog.PSObject.Properties[$activationKey] -and
            $null -ne $enCatalog.PSObject.Properties[$activationKey]) "Thiếu chuỗi hậu kiểm kích hoạt vi/en: $activationKey"
    }
    $enterpriseCoreText = Get-Content -LiteralPath (Join-Path $SourceDirectory "Tool-Enterprise.ps1") -Raw -Encoding UTF8
    Assert-Enterprise ($enterpriseCoreText -match 'function\s+Remove-ToolEnterpriseServerConfiguration' -and
        $enterpriseCoreText -match 'Test-ToolEnterpriseAdminCode' -and
        $enterpriseCoreText -match 'PreservedReportsPath') "Lõi enterprise thiếu xóa cấu hình có xác thực/giữ báo cáo."
    Assert-Enterprise ($enterpriseCoreText -match 'function\s+Resolve-ToolEnterpriseServerEndpoint' -and
        $enterpriseCoreText -match 'function\s+Get-ToolEnterpriseConnectionDiagnostic' -and
        $enterpriseCoreText -match 'DiscoveryMethod' -and
        $enterpriseCoreText -match 'ProbePorts' -and
        $enterpriseCoreText -notmatch 'ToolVersionPattern') "Lõi enterprise thiếu IP:cổng, chẩn đoán từng lớp hoặc quét không phụ thuộc ICMP."
    Assert-Enterprise ($enterpriseUiText -match 'ThanhViet Tool v4\.8 Enterprise \$Role' -and
        $enterpriseUiText -match 'Enable-EnterpriseServerListenerAccess' -and
        $enterpriseUiText -match 'Resolve-EnterpriseClientServerAddress') "Giao diện enterprise chưa đồng bộ tác vụ v4.8, URLACL/Firewall hoặc tự dò máy chủ."
    Assert-Enterprise ($enterpriseUiText -match 'function\s+Wait-EnterpriseServerReady' -and
        $enterpriseUiText -match 'function\s+Wait-EnterpriseAgentResult' -and
        $enterpriseUiText -match 'ClientAgentResult' -and
        $enterpriseUiText -match 'enterprise\.server\.startingVerified' -and
        $enterpriseUiText -match 'enterprise\.client\.agentSent') 'Giao diện enterprise còn báo thành công trước khi máy chủ/agent có kết quả xác nhận.'
    Assert-Enterprise ($enterpriseUiText -match 'http://\+:\$port/tool/v1/' -and
        $enterpriseUiText -match 'WindowsIdentity.*?User\.Value' -and
        $enterpriseUiText -match 'sddl=D:\(A;;GX;;;\$currentUserSid\)' -and
        $enterpriseUiText -match 'enterprise\.error\.urlAclNotApplied' -and
        $enterpriseUiText -match 'enterprise\.error\.firewallNotApplied') 'URL ACL/Firewall chưa dùng đúng prefix hoặc chưa hậu kiểm quyền listener.'
    $hostPath = Join-Path $SourceDirectory "Tool-EnterpriseHost.ps1"
    $hostText = Get-Content -LiteralPath $hostPath -Raw -Encoding UTF8
    $hostTokens = $null
    $hostParseErrors = $null
    $hostAst = [Management.Automation.Language.Parser]::ParseFile($hostPath, [ref]$hostTokens, [ref]$hostParseErrors)
    Assert-Enterprise (@($hostParseErrors).Count -eq 0) "Tool-EnterpriseHost.ps1 lỗi cú pháp."
    $statusFunction = $hostAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ToolEnterpriseHostStatus' }, $true)
    Assert-Enterprise ($null -ne $statusFunction) "Thiếu endpoint status tối giản."
    $statusFunctionText = [string]$statusFunction.Extent.Text
    foreach ($requiredField in @('Accepted','ProtocolVersion','ToolVersion')) {
        Assert-Enterprise ($statusFunctionText -match ("(?m)^\s*" + [regex]::Escape($requiredField) + "\s*=")) "Status tối giản thiếu trường $requiredField."
    }
    foreach ($sensitiveField in @('ServerId','ServerName','PreferredAddress','NetworkAddresses','BindAddress','AllowedCidrs','ClientCount','Uptime')) {
        Assert-Enterprise ($statusFunctionText -notmatch ("(?m)^\s*" + [regex]::Escape($sensitiveField) + "\s*=")) "Status không xác thực còn lộ $sensitiveField."
    }
    Assert-Enterprise ($hostText -match 'rate\.Count\+\+' -and $hostText -match 'StatusCode\s+429') "Endpoint Enterprise thiếu rate limit."
    Assert-Enterprise ($hostText -match '\$prefixAddress\s*=\s*if.+?\{\s*"\+"\s*\}' -and $hostText -match 'http://\$prefixAddress') 'Listener không dùng cùng strong-wildcard prefix với URL ACL.'
    $agentText = Get-Content -LiteralPath (Join-Path $SourceDirectory 'Tool-EnterpriseAgent.ps1') -Raw -Encoding UTF8
    Assert-Enterprise ($agentText -match 'function\s+Write-ToolEnterpriseAgentResultFile' -and
        $agentText -match 'ClientAgentResult' -and $agentText -match 'ClientAgentError' -and
        $agentText -match 'Success=\$true; ExitCode=0' -and $agentText -match 'Success=\$false; ExitCode=1') 'Agent chưa ghi kết quả thành công/thất bại có cấu trúc cho giao diện.'
    $previousUiTheme = [string]$env:TOOL_UI_THEME
    try {
        foreach ($networkState in @("0", "1")) {
            $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = $networkState
            foreach ($uiCulture in @("vi-VN", "en-US")) {
                $env:TOOL_UI_CULTURE = $uiCulture
                foreach ($uiTheme in @("Light", "Dark")) {
                    $env:TOOL_UI_THEME = $uiTheme
                    $uiSmokeOutput = @(& $nativePowerShell -NoProfile -ExecutionPolicy RemoteSigned -STA -File $enterpriseUiPath -SmokeTest 2>&1)
                    $uiSmokeExitCode = $LASTEXITCODE
                    Assert-Enterprise ($uiSmokeExitCode -eq 0) "Enterprise UI runtime smoke theme=$uiTheme culture=$uiCulture network=$networkState trả mã ${uiSmokeExitCode}: $($uiSmokeOutput -join '; ')"
                    $expectedNetwork = if ($networkState -eq "1") { "True" } else { "False" }
                    Assert-Enterprise (($uiSmokeOutput -join "`n") -match "ENTERPRISE-UI-SMOKE: PASS \(culture=$uiCulture .*Section8Network=$expectedNetwork.*theme $uiTheme\)") "Enterprise UI smoke không xác nhận theme=$uiTheme, culture=$uiCulture và trạng thái mạng Mục 8."
                }
            }
        }
    } finally {
        $env:TOOL_UI_THEME = $previousUiTheme
    }

    Write-Host "VERIFY-ENTERPRISE: PASS" -ForegroundColor Green
    Write-Host "  Protocol: $($metadata.ProtocolVersion), report schema: $($report.SchemaVersion), module count: $(@($catalog).Count)"
    exit 0
} catch {
    Write-Error "VERIFY-ENTERPRISE: FAIL - $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    exit 1
} finally {
    if ($hostProcess -and -not $hostProcess.HasExited) {
        try {
            $stopPath = Join-Path $testRoot "server\server.stop"
            New-Item -ItemType File -Path $stopPath -Force | Out-Null
            if (-not $hostProcess.WaitForExit(5000)) {
                Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    if ($hostProcess) { try { $hostProcess.Dispose() } catch {} }
    $env:TOOL_ENTERPRISE_ROOT = $previousRoot
    $env:TOOL_ENTERPRISE_SKIP_ACL = $previousSkipAcl
    $env:TOOL_OFFLINE_MODE = $previousOfflineMode
    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = $previousEnterpriseNetworkAllowed
    $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = $previousEnterpriseNetworkSettings
    $env:TOOL_UI_CULTURE = $previousUiCulture
    foreach ($target in @($testRoot,$exportRoot,$separateClientRoot,$dashboardFixtureRoot)) {
        try {
            $full = [IO.Path]::GetFullPath($target)
            if ($full.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full)) {
                Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}
