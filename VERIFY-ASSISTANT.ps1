[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$errors = New-Object System.Collections.Generic.List[string]

function Add-AssistantVerificationError([string]$Message) {
    $script:errors.Add($Message)
}

foreach ($name in @('Tool-Assistant.ps1','tool-assistant-knowledge-v1.1.json','tool-assistant-knowledge-v1.1.json.p7s','SIGN-ASSISTANT-KNOWLEDGE.ps1','Tool-OfflinePolicy.ps1','Giao-Dien.ps1','Tool-Strings.vi-VN.json','Tool-Strings.en-US.json','HUONG-DAN.txt','USER-GUIDE-en-US.md','LICH-SU-PHIEN-BAN.txt','VERSION-HISTORY-en-US.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory $name) -PathType Leaf)) {
        Add-AssistantVerificationError "Missing required assistant file: $name"
    }
}
if ($errors.Count -eq 0) {
    . (Join-Path $SourceDirectory 'Tool-Assistant.ps1')
    $knowledge = Get-ToolAssistantKnowledge
    if (-not (Test-ToolAssistantKnowledge -Knowledge $knowledge)) { Add-AssistantVerificationError 'Knowledge validation failed.' }
    $knowledgePath = Join-Path $SourceDirectory 'tool-assistant-knowledge-v1.1.json'
    $signaturePath = Join-Path $SourceDirectory 'tool-assistant-knowledge-v1.1.json.p7s'
    $knowledgeBytes = [IO.File]::ReadAllBytes($knowledgePath)
    $signatureBytes = [IO.File]::ReadAllBytes($signaturePath)
    if (-not (Test-ToolAssistantKnowledgeSignature -ContentBytes $knowledgeBytes -SignatureBytes $signatureBytes)) {
        Add-AssistantVerificationError 'Bundled knowledge detached signature validation failed.'
    }
    if (-not (Read-ToolAssistantKnowledgeFile -Path $knowledgePath -SignaturePath $signaturePath -RequireSignature)) {
        Add-AssistantVerificationError 'Signed knowledge reader rejected the published package.'
    }
    $tamperedBytes = New-Object byte[] $knowledgeBytes.Length
    [Array]::Copy($knowledgeBytes, $tamperedBytes, $knowledgeBytes.Length)
    $tamperedBytes[[Math]::Max(0, $tamperedBytes.Length - 2)] = $tamperedBytes[[Math]::Max(0, $tamperedBytes.Length - 2)] -bxor 1
    if (Test-ToolAssistantKnowledgeSignature -ContentBytes $tamperedBytes -SignatureBytes $signatureBytes) {
        Add-AssistantVerificationError 'Detached signature accepted tampered knowledge bytes.'
    }
    $legacyKnowledge = (Get-Content -LiteralPath $knowledgePath -Raw -Encoding UTF8) | ConvertFrom-Json
    $legacyKnowledge.KnowledgeVersion = '1.3.2'
    if (Test-ToolAssistantKnowledge -Knowledge $legacyKnowledge) { Add-AssistantVerificationError 'An obsolete cached knowledge file was not rejected.' }
    $compatibleFutureKnowledge = (Get-Content -LiteralPath $knowledgePath -Raw -Encoding UTF8) | ConvertFrom-Json
    $compatibleFutureKnowledge.KnowledgeVersion = '1.9.1'
    $compatibleFutureKnowledge.UpdatedAtUtc = '2026-09-06T11:14:26Z'
    $compatibleFutureKnowledge.ReleasedWithToolVersion = '5.0.0.1'
    if (-not (Test-ToolAssistantKnowledge -Knowledge $compatibleFutureKnowledge)) {
        Add-AssistantVerificationError 'A newer signed-compatible knowledge version cannot evolve independently of the EXE.'
    }
    if (@($knowledge.Entries).Count -lt 20) { Add-AssistantVerificationError 'Knowledge coverage is below 20 entries.' }
    $metadata = Get-ToolAssistantMetadata
    if ([bool]$metadata.PaidApiRequired) { Add-AssistantVerificationError 'Assistant must not require a paid API.' }
    if ([bool]$metadata.CodexRequired) { Add-AssistantVerificationError 'Assistant must not depend on Codex.' }
    if ([bool]$metadata.ReportUpload) { Add-AssistantVerificationError 'Assistant must not upload reports.' }
    if ([bool]$metadata.AutomaticRemediation) { Add-AssistantVerificationError 'Assistant must not remediate automatically.' }
    if (-not [bool]$metadata.PortableEveryMachine -or [bool]$metadata.CentralServerRequired) {
        Add-AssistantVerificationError 'Assistant must run independently on every device without a central server.'
    }
    if ([string]$metadata.KnowledgeStorage -ne 'BundledAndSignedPerUserLocalCache' -or
        [string]$metadata.ReportContextSource -ne 'CurrentDeviceLocalReportOnly') {
        Add-AssistantVerificationError 'Assistant local knowledge/report scope metadata is invalid.'
    }
    if ([string]$metadata.OnlineTransfer -ne 'DownloadOnlySignedKnowledgePackage' -or
        [string]$metadata.KnowledgeUpdateVerification -ne 'DetachedCmsSha256PinnedCertificate' -or
        -not [bool]$metadata.KnowledgeRollbackProtection -or [bool]$metadata.QuestionUpload -or
        [bool]$metadata.UnboundedSelfTraining -or [bool]$metadata.ExternalTopicLearning) {
        Add-AssistantVerificationError 'Signed knowledge, privacy, rollback, or bounded-learning metadata is invalid.'
    }
    if ([string]$metadata.CoverageMode -ne 'KnowledgePlusBundledDocumentation' -or
        -not [bool]$metadata.ContextAwareFollowUp -or -not [bool]$metadata.ContextualOutOfScope) {
        Add-AssistantVerificationError 'Assistant broad coverage, follow-up context, or contextual boundary metadata is invalid.'
    }
    if (-not [bool]$metadata.CompleteBundledGuideIndexed -or
        -not [bool]$metadata.CompleteVersionHistoryIndexed -or
        -not [bool]$metadata.CurrentTechnicalVersionIndexed -or
        -not [bool]$metadata.CompleteFeatureGuideCoverage -or
        [int]$metadata.MainFeatureCount -ne 10 -or
        [int]$metadata.RemediationWorkflowCount -ne 4 -or
        [int]$metadata.AssuranceActionCount -ne 8 -or
        -not [bool]$metadata.VersionComparisonUsesRecordedHistoryOnly -or
        @($metadata.BundledDocumentFiles).Count -ne 4) {
        Add-AssistantVerificationError 'Complete guide/current-history/function indexing or evidence-only comparison metadata is invalid.'
    }

    foreach ($culture in @('vi-VN','en-US')) {
        $documentSections = @(Get-ToolAssistantDocumentSections -Culture $culture)
        foreach ($definition in @(Get-ToolAssistantDocumentDefinitions -Culture $culture)) {
            $documentPath = Join-Path $SourceDirectory ([string]$definition.FileName)
            $documentRaw = Get-Content -LiteralPath $documentPath -Raw -Encoding UTF8
            $headingCount = [regex]::Matches($documentRaw, '(?m)^#{1,4}[ \t]+[^\r\n]+').Count
            $indexedCount = @($documentSections | Where-Object { [string]$_.SourceFile -eq [string]$definition.FileName }).Count
            if ($headingCount -le 0 -or $indexedCount -ne $headingCount) {
                Add-AssistantVerificationError "Complete document indexing failed for $([string]$definition.FileName): headings=$headingCount indexed=$indexedCount."
            }
        }
        $guideSections = @($documentSections | Where-Object { [string]$_.SourceKind -eq 'Guide' })
        if ($guideSections.Count -lt 30) {
            Add-AssistantVerificationError "Complete named-function guide coverage is unexpectedly small for ${culture}: $($guideSections.Count)."
        }
        foreach ($section in $guideSections) {
            $question = if ($culture -eq 'en-US') { "$([string]$section.Heading) — how does this work?" } else { "$([string]$section.Heading) hoạt động ra sao?" }
            $answer = Get-ToolAssistantAnswer -Question $question -Culture $culture -Knowledge $knowledge
            $expectedHeading = "$([string]$section.SourceLabel) — $([string]$section.Heading):"
            if ($answer -notlike ('*' + $expectedHeading + '*')) {
                Add-AssistantVerificationError "Named guide section did not route end-to-end for '$([string]$section.Heading)' (${culture})."
            }
        }
    }

    $keywordOwners = @{}
    $keywordCount = 0
    foreach ($entry in @($knowledge.Entries)) {
        foreach ($keywordValue in @($entry.Keywords)) {
            $keyword = ConvertTo-ToolAssistantSearchKey -Value ([string]$keywordValue)
            $keywordCount++
            if ($keywordOwners.ContainsKey($keyword)) {
                Add-AssistantVerificationError "Duplicate normalized keyword '$keyword' in '$($keywordOwners[$keyword])' and '$($entry.Id)'."
                continue
            }
            $keywordOwners[$keyword] = [string]$entry.Id
            $resolvedKeyword = Resolve-ToolAssistantEntry -QueryKey $keyword -Knowledge $knowledge
            if ($null -eq $resolvedKeyword.Entry -or [string]$resolvedKeyword.Entry.Id -ne [string]$entry.Id) {
                Add-AssistantVerificationError "Cross-routed keyword '$keyword': expected '$($entry.Id)'."
            }
        }
    }
    if ($keywordCount -lt 390) { Add-AssistantVerificationError "Knowledge keyword coverage is below 390: actual $keywordCount." }

    $routeTests = @(
        @{ Question='đọc báo cáo'; Entry='report-evidence' },
        @{ Question='báo cáo lưu ở đâu'; Entry='report-center' },
        @{ Question='chưa đủ bằng chứng'; Entry='manual-review' },
        @{ Question='mã lỗi 0xC004D302'; Entry='unverifiable' },
        @{ Question='cách dùng chức năng số 8'; Entry='enterprise' }
        @{ Question='báo cáo có khẳng định đk k'; Entry='report-legal-limit' }
        @{ Question='pdf bị khuyết dòng và cắt chữ'; Entry='report-pdf' }
        @{ Question='ẩn pm hệ thống trong pdf'; Entry='software-system-filter' }
        @{ Question='tự tìm máy chủ khi ô ip trống'; Entry='enterprise-discovery' }
        @{ Question='hash mismatch có phải bản quyền lậu không'; Entry='integrity-compromised' }
        @{ Question='ý nghĩa tên VietLicenSure là gì'; Entry='brand-name' }
        @{ Question='why is it named VietLicenSure'; Entry='brand-name' }
        @{ Question='phiên bản hiện tại của tool'; Entry='tool-version' }
        @{ Question='phiên bản đầu tiên ngày mấy'; Entry='first-release' }
        @{ Question='phien ban dau tien ngay may tool'; Entry='first-release' }
        @{ Question='v1.0 phát hành ngày nào'; Entry='first-release' }
        @{ Question='v1 ngày nào'; Entry='first-release' }
        @{ Question='bản đầu tiên'; Entry='first-release' }
        @{ Question='tool miễn phí hay trả phí'; Entry='tool-pricing' }
        @{ Question='tool mien phi hay tra phi'; Entry='tool-pricing' }
        @{ Question='có tốn tiền ko'; Entry='tool-pricing' }
        @{ Question='mã nguồn công khai ở đâu'; Entry='source-code-license' }
        @{ Question='ma nguon cong khaio dau'; Entry='source-code-license' }
        @{ Question='ma ngun cong khai o dau'; Entry='source-code-license' }
        @{ Question='repo công khai có được sửa không'; Entry='source-code-license' }
        @{ Question='code công khai có phải open source k'; Entry='source-code-license' }
        @{ Question='chưa xác định nghĩa là gì'; Entry='status-terms' }
        @{ Question='chua xac minh la sao'; Entry='status-terms' }
        @{ Question='chua xac mnih la sao'; Entry='status-terms' }
        @{ Question='unknown là gì'; Entry='status-terms' }
        @{ Question='unverifed la gi'; Entry='status-terms' }
        @{ Question='suspicous la gi'; Entry='status-terms' }
        @{ Question='crak la gi'; Entry='status-terms' }
        @{ Question='crack là gì'; Entry='status-terms' }
        @{ Question='Unknown Unverified Suspicious Crack khác nhau thế nào'; Entry='status-terms' }
        @{ Question='chưa xác định khác chưa xác minh sao'; Entry='status-terms' }
        @{ Question='tool do ai phát triển'; Entry='tool-author' }
        @{ Question='tóm tắt nội dung chính của tool'; Entry='tool-overview' }
        @{ Question='nguyên tắc hoạt động của công cụ'; Entry='tool-principles' }
        @{ Question='liệt kê tất cả chức năng'; Entry='feature-overview' }
        @{ Question='cách dùng chức năng số 7'; Entry='oem' }
        @{ Question='cách sao lưu trước khi sửa'; Entry='backup-restore' }
        @{ Question='không thấy phần mềm cần kiểm tra'; Entry='software-not-found' }
        @{ Question='pdf không tạo được'; Entry='report-pdf-failure' }
        @{ Question='cách xóa cấu hình máy chủ'; Entry='enterprise-server-management' }
        @{ Question='cách ghép nối máy trạm'; Entry='enterprise-client-management' }
        @{ Question='tạo gói hỗ trợ đã che định danh'; Entry='support-bundle' }
        @{ Question='chưa có chính sách nhà phát hành plugin'; Entry='plugin-management' }
        @{ Question='tool không mở được file exe'; Entry='launch-troubleshooting' }
        @{ Question='online không đồng bộ được'; Entry='online-troubleshooting' }
        @{ Question='phần mềm miễn phí mà cũng cần hóa đơn license à'; Entry='license-model-evidence' }
        @{ Question='đối chiếu mô hình và trạng thái bản quyền phần mềm'; Entry='license-model-evidence' }
        @{ Question='độ tin cậy Low đủ để xóa bloat hay app thừa không'; Entry='software-finding-confidence' }
        @{ Question='có dấu hiệu nghi vấn thì điều kiện khắc phục là gì'; Entry='software-finding-remediation' }
        @{ Question='Windows yên nhưng Office có activator thì sao'; Entry='license-scope-separation' }
        @{ Question='WinRAR không có crack thì xử lý sao'; Entry='commercial-software-review' }
        @{ Question='MAS trong Startup nghĩa là gì'; Entry='kms-activator' }
    )
    foreach ($test in $routeTests) {
        $queryKey = ConvertTo-ToolAssistantSearchKey -Value $test.Question
        $route = Resolve-ToolAssistantEntry -QueryKey $queryKey -Knowledge $knowledge
        if ($null -eq $route.Entry -or [string]$route.Entry.Id -ne [string]$test.Entry) {
            Add-AssistantVerificationError "Specific intent '$($test.Question)' routed to '$([string]$route.Entry.Id)' instead of '$($test.Entry)'."
        }
    }

    $focusedCollisionKnowledge = (Get-Content -LiteralPath $knowledgePath -Raw -Encoding UTF8) | ConvertFrom-Json
    @($focusedCollisionKnowledge.Entries | Where-Object { [string]$_.Id -eq 'scope' })[0].Keywords += @(
        'tool mien phi hay tra phi', 'ma nguon cong khai o dau', 'chua xac dinh khac chua xac minh sao'
    )
    @($focusedCollisionKnowledge.Entries | Where-Object { [string]$_.Id -eq 'tool-version' })[0].Keywords += @('phien ban dau tien ngay may')
    $focusedCollisionTests = @(
        @{ Question='tool mien phi hay tra phi'; Entry='tool-pricing' },
        @{ Question='ma nguon cong khai o dau'; Entry='source-code-license' },
        @{ Question='chua xac dinh khac chua xac minh sao'; Entry='status-terms' },
        @{ Question='phien ban dau tien ngay may'; Entry='first-release' }
    )
    foreach ($test in $focusedCollisionTests) {
        $route = Resolve-ToolAssistantEntry -QueryKey (ConvertTo-ToolAssistantSearchKey -Value $test.Question) -Knowledge $focusedCollisionKnowledge
        if ($null -eq $route.Entry -or [string]$route.Entry.Id -ne [string]$test.Entry -or [string]$route.Route -ne 'FocusedIntent') {
            Add-AssistantVerificationError "Focused intent '$($test.Question)' did not outrank an exact generic keyword."
        }
    }

    $answerTests = @(
        @{ Question='khong the xac minh ban quyen la gi'; Expected='CHƯA XÁC ĐỊNH' },
        @{ Question='che do ofline hoat dong sao'; Expected='Offline' },
        @{ Question='tool co can api codex khong'; Expected='tri thức cục bộ' },
        @{ Question='bao cao luu o dau'; Expected='BaoCao-VietLicenSure' },
        @{ Question='doc bao cao'; Expected='bốn lớp' },
        @{ Question='chua du bang chung'; Expected='kiểm tra thủ công' },
        @{ Question='cach dung chuc nang so 8'; Expected='Doanh nghiệp' },
        @{ Question='tạo gói hỗ trợ đã che định danh'; Expected='xem trước' },
        @{ Question='chưa có chính sách nhà phát hành plugin'; Expected='không phải lỗi ứng dụng' },
        @{ Question='tool co sua crack tu dong khong'; Expected='người dùng chủ động' },
        @{ Question='cach nau bun bo hue'; Expected='ngoài phạm vi' }
        @{ Question='báo cáo có khẳng định đk k'; Expected='mô hình' }
        @{ Question='mỗi lần quét có tạo thư mục riêng k'; Expected='không tạo thư mục con' }
        @{ Question='pm hệ thống trong pdf quá dài'; Expected='phụ lục' }
        @{ Question='cách luna cập nhật'; Expected='manifest' }
        @{ Question='phiên bản hiện tại của tool'; Expected='v5.0' }
        @{ Question='ngày build hiện tại của tool'; Expected='06/09/2026' }
        @{ Question='phiên bản đầu tiên ngày mấy'; Expected='v1.0, phát hành ngày 17/07/2026' }
        @{ Question='v1 ngày nào'; Expected='v1.0.0 — 17/07/2026' }
        @{ Question='bản đầu tiên'; Expected='v1.0, phát hành ngày 17/07/2026' }
        @{ Question='tool mien phi hay tra phi'; Expected='cung cấp miễn phí' }
        @{ Question='có tốn tiền ko'; Expected='cung cấp miễn phí' }
        @{ Question='ma nguon cong khaio dau'; Expected='truy cập có kiểm soát' }
        @{ Question='ma ngun cong khai o dau'; Expected='truy cập có kiểm soát' }
        @{ Question='repo công khai có được sửa không'; Expected='không tự cấp quyền sao chép, trích xuất, sửa đổi' }
        @{ Question='code công khai có phải open source k'; Expected='không được phát hành theo giấy phép mã nguồn mở' }
        @{ Question='muốn học hỏi mã nguồn'; Expected='nhận chấp thuận trước bằng văn bản' }
        @{ Question='tool có phát triển cộng đồng không'; Expected='phát triển cùng cộng đồng' }
        @{ Question='chưa xác định nghĩa là gì'; Expected='CHƯA XÁC ĐỊNH/Unknown' }
        @{ Question='chua xac minh la sao'; Expected='bằng chứng hiện tại chưa đủ xác nhận' }
        @{ Question='chua xac mnih la sao'; Expected='bằng chứng hiện tại chưa đủ xác nhận' }
        @{ Question='unknown là gì'; Expected='CHƯA XÁC ĐỊNH/Unknown' }
        @{ Question='unverifed la gi'; Expected='CHƯA XÁC MINH/Unverified' }
        @{ Question='suspicous la gi'; Expected='NGHI VẤN/Suspicious' }
        @{ Question='crak la gi'; Expected='CRACK ĐÃ XÁC NHẬN/CrackConfirmed' }
        @{ Question='crack là gì'; Expected='CRACK ĐÃ XÁC NHẬN/CrackConfirmed' }
        @{ Question='do ai phát triển'; Expected='Thanh Việt' }
        @{ Question='tóm tắt nội dung chính'; Expected='một-EXE' }
        @{ Question='nguyên tắc của tool'; Expected='Offline' }
        @{ Question='tool có những chức năng nào'; Expected='10 chức năng' }
        @{ Question='hdsd chức năng 1'; Expected='chọn mức riêng tư' }
        @{ Question='cách dùng chức năng 7'; Expected='Khôi phục key OEM' }
        @{ Question='cách sao lưu'; Expected='không phải chức năng số 7' }
        @{ Question='không thấy phần mềm cần kiểm tra'; Expected='quyền Administrator' }
        @{ Question='pdf không tạo được'; Expected='dùng HTML' }
        @{ Question='cách xóa cấu hình máy chủ'; Expected='giữ báo cáo' }
        @{ Question='cách ghép nối máy trạm'; Expected='mã ghép nối' }
        @{ Question='tool không mở được file exe'; Expected='không chạy trong ZIP' }
        @{ Question='online không đồng bộ được'; Expected='DNS' }
        @{ Question='yêu cầu hệ thống của tool'; Expected='Windows 7 SP1' }
        @{ Question='tool viết bằng gì'; Expected='C#' }
        @{ Question='cách chuyển giao diện tối'; Expected='Sáng/Tối' }
        @{ Question='phần mềm miễn phí mà cũng cần hóa đơn license à'; Expected='không bị yêu cầu hóa đơn mua hàng chung chung' }
        @{ Question='độ tin cậy Low đủ để xóa bloat hay app thừa không'; Expected='không được dùng để xóa bloatware' }
        @{ Question='có dấu hiệu nghi vấn thì điều kiện khắc phục là gì'; Expected='chỉ cô lập đúng hiện vật' }
        @{ Question='Windows yên nhưng Office có activator thì sao'; Expected='Ba phạm vi phải được kết luận và xử lý riêng' }
        @{ Question='WinRAR không có crack thì xử lý sao'; Expected='giữ nguyên ứng dụng' }
        @{ Question='MAS trong Startup nghĩa là gì'; Expected='lệnh Startup' }
    )
    foreach ($test in $answerTests) {
        $answer = Get-ToolAssistantAnswer -Question $test.Question -Culture 'vi-VN' -Knowledge $knowledge
        if ($answer -notlike ('*' + $test.Expected + '*')) {
            Add-AssistantVerificationError "Unexpected answer for '$($test.Question)'."
        }
    }

    $missingV20Vi = Get-ToolAssistantAnswer -Question 'v2.0 cập nhật những gì' -Culture 'vi-VN' -Knowledge $knowledge
    $missingV20CompareVi = Get-ToolAssistantAnswer -Question 'v2.0 cải tiến gì so với v1' -Culture 'vi-VN' -Knowledge $knowledge
    $v24Vi = Get-ToolAssistantAnswer -Question 'phiên bản v2.4 cập nhật gì' -Culture 'vi-VN' -Knowledge $knowledge
    $versionCompareVi = Get-ToolAssistantAnswer -Question 'v4.8 khác v4.6 như thế nào' -Culture 'vi-VN' -Knowledge $knowledge
    $versionListVi = Get-ToolAssistantAnswer -Question 'liệt kê toàn bộ lịch sử phiên bản' -Culture 'vi-VN' -Knowledge $knowledge
    $manualGuideVi = Get-ToolAssistantAnswer -Question 'lựa chọn 2 kiểm tra và khắc phục thủ công gồm những bước gì' -Culture 'vi-VN' -Knowledge $knowledge
    $oemFlowVi = Get-ToolAssistantAnswer -Question 'chức năng khôi phục OEM hoạt động ra sao' -Culture 'vi-VN' -Knowledge $knowledge
    $missingV20En = Get-ToolAssistantAnswer -Question 'what changed in version v2.0' -Culture 'en-US' -Knowledge $knowledge
    $oemFlowEn = Get-ToolAssistantAnswer -Question 'how does OEM key recovery work' -Culture 'en-US' -Knowledge $knowledge
    if ($missingV20Vi -notmatch 'không có mục được ghi nhận cho v2\.0' -or $missingV20Vi -notmatch 'v2\.4' -or
        $missingV20CompareVi -notmatch 'không tự suy diễn.*so sánh' -or
        $missingV20En -notmatch 'no recorded entry for v2\.0' -or $missingV20En -notmatch 'v2\.4') {
        Add-AssistantVerificationError 'Missing-version questions were invented or did not identify the first recorded v2.x milestone.'
    }
    if ($v24Vi -notmatch 'Đổi nhãn phiên bản từ v1\.3\.0 thành v2\.4' -or
        $v24Vi -notmatch 'Giữ nguyên chức năng.*UAC/quét chuyên sâu') {
        Add-AssistantVerificationError 'The v2.4 answer does not preserve the evidenced v1.3.0 relabel history.'
    }
    if ($versionCompareVi -notmatch 'không suy diễn' -or $versionCompareVi -notmatch 'v4\.8\.0\.0' -or $versionCompareVi -notmatch 'v4\.6') {
        Add-AssistantVerificationError 'Two-version comparison does not return both published history entries.'
    }
    if ($versionListVi -notmatch 'v5\.0' -or $versionListVi -notmatch 'v1\.0' -or
        $versionListVi -match '(?:^|, )v2\.0(?:,|\.)') {
        Add-AssistantVerificationError 'Complete version-history listing is incomplete or includes an undocumented v2.0 milestone.'
    }
    if ($manualGuideVi -notmatch 'Lựa chọn 2.*Kiểm tra và khắc phục thủ công' -or
        $manualGuideVi -notmatch 'Xử lý mục còn lại') {
        Add-AssistantVerificationError 'A long bundled-guide section was not retrieved through its final documented actions.'
    }
    if ($oemFlowVi -notmatch 'hai giai đoạn' -or $oemFlowVi -notmatch 'OA3xOriginalProductKey' -or
        $oemFlowVi -notmatch 'giữ nguyên key hiện tại' -or $oemFlowVi -notmatch 'tối đa ba lần' -or
        $oemFlowEn -notmatch 'two separate stages' -or $oemFlowEn -notmatch 'OA3xOriginalProductKey' -or
        $oemFlowEn -notmatch 'preserve the current key') {
        Add-AssistantVerificationError 'OEM recovery explanation is incomplete or does not preserve the safe two-stage workflow.'
    }
    foreach ($choiceTest in @(
        @{ Culture='vi-VN'; Question='làm sao dùng lựa chọn 1'; Expected='Lựa chọn 1 – Backup trước khi thực hiện' },
        @{ Culture='vi-VN'; Question='làm sao dùng lựa chọn 2'; Expected='Lựa chọn 2 – Kiểm tra và khắc phục thủ công' },
        @{ Culture='vi-VN'; Question='làm sao dùng lựa chọn 3'; Expected='Lựa chọn 3 – Khôi phục từ backup' },
        @{ Culture='vi-VN'; Question='làm sao dùng lựa chọn 4'; Expected='Lựa chọn 4 – Tự động làm sạch an toàn' },
        @{ Culture='en-US'; Question='how do I use choice 1'; Expected='Choice 1 – Backup' },
        @{ Culture='en-US'; Question='how do I use choice 2'; Expected='Choice 2 – Manual inspection and remediation' },
        @{ Culture='en-US'; Question='how do I use choice 3'; Expected='Choice 3 – Restore from backup' },
        @{ Culture='en-US'; Question='how do I use choice 4'; Expected='Choice 4 – Automatic safe cleanup' }
    )) {
        $choiceAnswer = Get-ToolAssistantAnswer -Question $choiceTest.Question -Culture $choiceTest.Culture -Knowledge $knowledge
        if ($choiceAnswer -notlike ('*' + $choiceTest.Expected + '*')) {
            Add-AssistantVerificationError "Bundled-guide choice routing failed for '$($choiceTest.Question)'."
        }
    }
    foreach ($foreignVersionQuestion in @('.NET v4.8 khác v4.7 thế nào','v4.8 .NET framework có đủ không','PowerShell v5.1 có được Tool hỗ trợ không','Windows v11 có chạy được Tool không')) {
        $foreignVersionAnswer = Get-ToolAssistantAnswer -Question $foreignVersionQuestion -Culture 'vi-VN' -Knowledge $knowledge
        if ($foreignVersionAnswer -match 'Lịch sử phiên bản|Đối chiếu trực tiếp|v4\.8\.0\.0 —') {
            Add-AssistantVerificationError "A non-Tool product version was hijacked by release-history routing: '$foreignVersionQuestion'."
        }
    }
    $mixedOrderCompare = Get-ToolAssistantAnswer -Question 'compare version 4.6 with v4.8' -Culture 'en-US' -Knowledge $knowledge
    if ($mixedOrderCompare.IndexOf('v4.6 —', [StringComparison]::Ordinal) -lt 0 -or
        $mixedOrderCompare.IndexOf('v4.8.0.0 —', [StringComparison]::Ordinal) -le $mixedOrderCompare.IndexOf('v4.6 —', [StringComparison]::Ordinal)) {
        Add-AssistantVerificationError 'Mixed version notation did not preserve question order during comparison.'
    }

    $expectedHistoryVersions = @(
        '5.0','4.9.0.0','4.8.0.1','4.8.0.0','4.6','4.5','4.4','4.3','4.2','4.1','4.0',
        '3.9','3.8','3.7','3.6','3.5','3.4','3.3','3.2','3.1','3.0','2.9','2.8','2.7','2.6','2.5','2.4',
        '1.3.0','1.2.0','1.1.0','1.0.9','1.0.8','1.0.7','1.0.6','1.0.5','1.0.4','1.0.3','1.0.2','1.0.1','1.0.0'
    )
    foreach ($culture in @('vi-VN','en-US')) {
        $actualHistoryVersions = @(Get-ToolAssistantDocumentSections -Culture $culture | Where-Object {
            [string]$_.SourceKind -eq 'History' -and -not [string]::IsNullOrWhiteSpace([string]$_.VersionRaw)
        } | ForEach-Object { [string]$_.VersionRaw })
        if (($actualHistoryVersions -join '|') -ne ($expectedHistoryVersions -join '|')) {
            Add-AssistantVerificationError "Recorded version set/order is incomplete for ${culture}: $($actualHistoryVersions -join ', ')."
        }
        foreach ($version in $expectedHistoryVersions) {
            $question = if ($culture -eq 'en-US') { "what changed in v$version" } else { "v$version cập nhật những gì" }
            $answer = Get-ToolAssistantHistoryAnswer -Question $question -Culture $culture
            if ($answer -notlike ('*v' + $version + '*') -or $answer -match 'no recorded entry|không có mục được ghi nhận') {
                Add-AssistantVerificationError "Recorded history lookup failed for v$version (${culture})."
            }
        }
    }

    $currentVi = Get-ToolAssistantAnswer -Question 'v5.0.0.1 cập nhật những gì' -Culture 'vi-VN' -Knowledge $knowledge
    $currentEn = Get-ToolAssistantAnswer -Question 'what changed in v5.0.0.1' -Culture 'en-US' -Knowledge $knowledge
    $currentAliasVi = Get-ToolAssistantAnswer -Question 'phiên bản hiện tại cập nhật gì' -Culture 'vi-VN' -Knowledge $knowledge
    $currentAliasEn = Get-ToolAssistantAnswer -Question 'current version changes' -Culture 'en-US' -Knowledge $knowledge
    $latestAliasVi = Get-ToolAssistantAnswer -Question 'mới nhất cập nhật gì' -Culture 'vi-VN' -Knowledge $knowledge
    $latestAliasEn = Get-ToolAssistantAnswer -Question "what's new in the latest version" -Culture 'en-US' -Knowledge $knowledge
    $bareLatestEn = Get-ToolAssistantAnswer -Question 'latest changes' -Culture 'en-US' -Knowledge $knowledge
    $currentCompareVi = Get-ToolAssistantAnswer -Question 'bản hiện tại so với v4.9' -Culture 'vi-VN' -Knowledge $knowledge
    $currentCompareEn = Get-ToolAssistantAnswer -Question 'compare v4.9 with the current version' -Culture 'en-US' -Knowledge $knowledge
    $futureMissing = Get-ToolAssistantAnswer -Question 'v5.0.0.2 cập nhật gì' -Culture 'vi-VN' -Knowledge $knowledge
    if ($currentVi -notmatch 'v5\.0' -or $currentVi -notmatch 'Trải nghiệm sử dụng' -or $currentVi -notmatch 'Riêng tư và toàn vẹn' -or
        $currentEn -notmatch 'v5\.0' -or $currentEn -notmatch 'User experience' -or $currentEn -notmatch 'Privacy and integrity' -or
        $currentAliasVi -notmatch 'v5\.0' -or $currentAliasEn -notmatch 'v5\.0' -or
        $latestAliasVi -notmatch 'v5\.0' -or $latestAliasEn -notmatch 'v5\.0' -or
        $bareLatestEn -notmatch 'v5\.0' -or
        $futureMissing -notmatch 'không có mục được ghi nhận cho v5\.0\.0\.2') {
        Add-AssistantVerificationError 'Current technical version lookup/alias or future-version rejection is incomplete.'
    }
    if ($currentCompareVi.IndexOf('v5.0 —', [StringComparison]::Ordinal) -lt 0 -or
        $currentCompareVi.IndexOf('v4.9.0.0 —', [StringComparison]::Ordinal) -le $currentCompareVi.IndexOf('v5.0 —', [StringComparison]::Ordinal) -or
        $currentCompareEn.IndexOf('v4.9.0.0 —', [StringComparison]::Ordinal) -lt 0 -or
        $currentCompareEn.IndexOf('v5.0 —', [StringComparison]::Ordinal) -le $currentCompareEn.IndexOf('v4.9.0.0 —', [StringComparison]::Ordinal)) {
        Add-AssistantVerificationError 'Current/latest comparison did not resolve v5.0 or preserve question order.'
    }

    $catalogUpdateEn = Get-ToolAssistantAnswer -Question 'latest catalog update failed' -Culture 'en-US' -Knowledge $knowledge
    $catalogUpdateVi = Get-ToolAssistantAnswer -Question 'cập nhật danh mục mới nhất bị lỗi' -Culture 'vi-VN' -Knowledge $knowledge
    $installUpdateEn = Get-ToolAssistantAnswer -Question 'how do I install the latest update' -Culture 'en-US' -Knowledge $knowledge
    $downloadUpdateVi = Get-ToolAssistantAnswer -Question 'làm sao tải bản cập nhật mới nhất' -Culture 'vi-VN' -Knowledge $knowledge
    if ($catalogUpdateEn -notmatch 'remains usable Offline' -or $catalogUpdateVi -notmatch 'vẫn dùng được Offline' -or
        $installUpdateEn -notmatch 'Update checks work' -or $downloadUpdateVi -notmatch 'Kiểm tra cập nhật' -or
        $catalogUpdateEn -match 'Version history.*v5\.0\.0\.1' -or $catalogUpdateVi -match 'Lịch sử phiên bản.*v5\.0\.0\.1') {
        Add-AssistantVerificationError 'Current/latest aliases hijacked catalog or application-update workflows.'
    }

    $windowsCurrentVersion = Get-ToolAssistantAnswer -Question 'phiên bản Windows hiện tại là gì' -Culture 'vi-VN' -Knowledge $knowledge
    $powershellSupportedVersion = Get-ToolAssistantAnswer -Question 'what is the latest PowerShell version supported by the Tool' -Culture 'en-US' -Knowledge $knowledge
    if ($windowsCurrentVersion -notmatch 'Chức năng 3 đọc edition' -or $powershellSupportedVersion -notmatch 'PowerShell 3 or later' -or
        $windowsCurrentVersion -match 'v5\.0\.0\.1' -or $powershellSupportedVersion -match 'technical version v5\.0\.0\.1') {
        Add-AssistantVerificationError 'Current/latest foreign-product version wording was confused with Tool version history.'
    }

    foreach ($capabilityTest in @(
        @{ Culture='vi-VN'; Question='v5.0.0.1 có tất cả chức năng gì'; Expected='Toàn bộ 10 chức năng chính' },
        @{ Culture='vi-VN'; Question='tất cả chức năng của phiên bản hiện tại'; Expected='Toàn bộ 10 chức năng chính' },
        @{ Culture='en-US'; Question='what features does v5.0.0.1 have'; Expected='All ten main functions' },
        @{ Culture='en-US'; Question='list all functions in the current version'; Expected='All ten main functions' }
    )) {
        $capabilityAnswer = Get-ToolAssistantAnswer -Question $capabilityTest.Question -Culture $capabilityTest.Culture -Knowledge $knowledge
        if ($capabilityAnswer -notlike ('*' + $capabilityTest.Expected + '*') -or $capabilityAnswer -match 'no recorded entry|không có mục được ghi nhận') {
            Add-AssistantVerificationError "Current-version feature inventory was hijacked by history routing: '$($capabilityTest.Question)'."
        }
    }

    $completeFunctionTests = @(
        @{ Culture='vi-VN'; Question='kiểm tra toàn bộ hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Kiểm tra toàn bộ:' },
        @{ Culture='vi-VN'; Question='cấu hình phần cứng hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Cấu hình phần cứng:' },
        @{ Culture='vi-VN'; Question='bản quyền Windows hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Bản quyền Windows:' },
        @{ Culture='vi-VN'; Question='bản quyền Microsoft Office hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Bản quyền Microsoft Office:' },
        @{ Culture='vi-VN'; Question='phần mềm và dấu hiệu can thiệp hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Phần mềm & dấu hiệu can thiệp:' },
        @{ Culture='vi-VN'; Question='năm chức năng trong mục khắc phục hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Năm chức năng trong mục Khắc phục:' },
        @{ Culture='vi-VN'; Question='khôi phục key OEM hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Khôi phục key OEM:' },
        @{ Culture='vi-VN'; Question='quản lý giấy phép hợp lệ hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Quản lý giấy phép hợp lệ:' },
        @{ Culture='vi-VN'; Question='kiểm tra chuyên sâu hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Kiểm tra chuyên sâu:' },
        @{ Culture='vi-VN'; Question='quét chuyên sâu 7 nhóm hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Kiểm tra chuyên sâu 7 nhóm:' },
        @{ Culture='vi-VN'; Question='điều tra 12 nhóm và chấm điểm hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Điều tra 12 nhóm và chấm điểm:' },
        @{ Culture='vi-VN'; Question='trung tâm báo cáo và bảo đảm hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Trung tâm báo cáo & bảo đảm:' },
        @{ Culture='vi-VN'; Question='khắc phục Windows hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Khắc phục Windows:' },
        @{ Culture='vi-VN'; Question='khắc phục Microsoft Office hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Khắc phục Microsoft Office:' },
        @{ Culture='vi-VN'; Question='khắc phục phần mềm khác hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Khắc phục phần mềm khác:' },
        @{ Culture='vi-VN'; Question='khắc phục phần mềm khác làm gì'; Expected='Hướng dẫn sử dụng — Khắc phục phần mềm khác:' },
        @{ Culture='vi-VN'; Question='chạy thử không thay đổi hệ thống hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Chạy thử – không thay đổi hệ thống:' },
        @{ Culture='vi-VN'; Question='thực hiện thật sau chạy thử hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Thực hiện thật sau Chạy thử:' },
        @{ Culture='vi-VN'; Question='kiểm tra và đưa về trạng thái gốc hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Kiểm tra và đưa về trạng thái gốc:' },
        @{ Culture='vi-VN'; Question='sửa nhanh nguồn quét hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Sửa nhanh nguồn quét:' },
        @{ Culture='vi-VN'; Question='xử lý mục còn lại hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Xử lý mục còn lại:' },
        @{ Culture='vi-VN'; Question='xác nhận KMS nội bộ hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Xác nhận KMS nội bộ:' },
        @{ Culture='vi-VN'; Question='quét lại hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Quét lại:' },
        @{ Culture='vi-VN'; Question='kích hoạt hợp lệ hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Kích hoạt hợp lệ:' },
        @{ Culture='vi-VN'; Question='quản lý cục bộ hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Quản lý cục bộ:' },
        @{ Culture='vi-VN'; Question='máy chủ và máy trạm doanh nghiệp hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Máy chủ và máy trạm doanh nghiệp:' },
        @{ Culture='vi-VN'; Question='kiểm tra chứng chỉ số Windows Office hoạt động thế nào'; Expected='chuỗi tin cậy Offline' },
        @{ Culture='vi-VN'; Question='đánh giá plugin hoạt động thế nào'; Expected='plugin JSON chỉ đọc' },
        @{ Culture='vi-VN'; Question='xác minh và xuất timeline hoạt động ra sao'; Expected='chuỗi nhật ký' },
        @{ Culture='vi-VN'; Question='cài plugin đã ký hoạt động ra sao'; Expected='chính sách nhà phát hành' },
        @{ Culture='vi-VN'; Question='mở thư mục plugin bảo vệ ở đâu'; Expected='trusted-plugin-publishers-v1.json' },
        @{ Culture='vi-VN'; Question='mở hướng dẫn sử dụng ở đâu'; Expected='HDSD HTML/PDF' },
        @{ Culture='vi-VN'; Question='xem phiên bản và cập nhật ở đâu'; Expected='Phiên bản và cập nhật' },
        @{ Culture='vi-VN'; Question='tạo gói hỗ trợ đã che định danh ra sao'; Expected='bản xem trước' },
        @{ Culture='vi-VN'; Question='kết nối online để cập nhật nhận diện hoạt động ra sao'; Expected='chỉ tải danh mục nhận diện' },
        @{ Culture='vi-VN'; Question='đồng bộ tri thức hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Đồng bộ tri thức:' },
        @{ Culture='vi-VN'; Question='nút Gửi và Enter hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Nút Gửi và Enter:' },
        @{ Culture='vi-VN'; Question='quyền riêng tư báo cáo hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Quyền riêng tư báo cáo:' },
        @{ Culture='vi-VN'; Question='nút Dừng hoạt động ra sao'; Expected='Hướng dẫn sử dụng — Nút Dừng:' },
        @{ Culture='en-US'; Question='how does Complete audit work'; Expected='User guide — Complete audit:' },
        @{ Culture='en-US'; Question='how does Hardware configuration work'; Expected='User guide — Hardware configuration:' },
        @{ Culture='en-US'; Question='how does Windows licensing work'; Expected='User guide — Windows licensing:' },
        @{ Culture='en-US'; Question='how does Microsoft Office licensing work'; Expected='User guide — Microsoft Office licensing:' },
        @{ Culture='en-US'; Question='how do Software and tampering indicators work'; Expected='User guide — Software & tampering indicators:' },
        @{ Culture='en-US'; Question='how does Windows Office and other software remediation work'; Expected='User guide — Windows, Microsoft Office, and other-software remediation:' },
        @{ Culture='en-US'; Question='how does Dry Run work'; Expected='User guide — Dry Run — no system changes:' },
        @{ Culture='en-US'; Question='how does Execute for real after Dry Run work'; Expected='User guide — Execute for real after Dry Run:' },
        @{ Culture='en-US'; Question='how does Inspect and return to original state work'; Expected='User guide — Inspect and return to original state:' },
        @{ Culture='en-US'; Question='how does Quick repair scan sources work'; Expected='User guide — Quick repair scan sources:' },
        @{ Culture='en-US'; Question='how does Handle remaining items work'; Expected='User guide — Handle remaining items:' },
        @{ Culture='en-US'; Question='how does Confirm internal KMS work'; Expected='User guide — Confirm internal KMS:' },
        @{ Culture='en-US'; Question='how does Recheck work'; Expected='User guide — Recheck:' },
        @{ Culture='en-US'; Question='how does Activate legitimately work'; Expected='User guide — Activate legitimately:' },
        @{ Culture='en-US'; Question='how does Restore the OEM key work'; Expected='User guide — Restore the OEM key:' },
        @{ Culture='en-US'; Question='how does Manage valid licenses work'; Expected='User guide — Manage valid licenses:' },
        @{ Culture='en-US'; Question='how does local license management work'; Expected='User guide — Local management:' },
        @{ Culture='en-US'; Question='how does enterprise server and workstation work'; Expected='User guide — Enterprise server and workstation:' },
        @{ Culture='en-US'; Question='how does Advanced inspection work'; Expected='User guide — Advanced inspection:' },
        @{ Culture='en-US'; Question='how does seven-group deep scan work'; Expected='User guide — Seven-group deep scan:' },
        @{ Culture='en-US'; Question='how does twelve-group forensics and scoring work'; Expected='User guide — Twelve-group forensics and scoring:' },
        @{ Culture='en-US'; Question='how does Reports and assurance center work'; Expected='User guide — Reports & assurance center:' },
        @{ Culture='en-US'; Question='how does certificate audit work'; Expected='Offline trust chain' },
        @{ Culture='en-US'; Question='how do I evaluate a plugin'; Expected='read-only JSON plugin' },
        @{ Culture='en-US'; Question='how does license timeline export work'; Expected='local chained log' },
        @{ Culture='en-US'; Question='how do I create a redacted support bundle'; Expected='preview' },
        @{ Culture='en-US'; Question='how do I open the user guide'; Expected='open Reports & Assurance' },
        @{ Culture='en-US'; Question='where can I see version and updates'; Expected='open Reports & Assurance' },
        @{ Culture='en-US'; Question='how does Sync knowledge work'; Expected='User guide — Sync knowledge:' },
        @{ Culture='en-US'; Question='how do Send and Enter work'; Expected='User guide — Send and Enter:' },
        @{ Culture='en-US'; Question='how does report privacy work'; Expected='User guide — Report privacy:' },
        @{ Culture='en-US'; Question='how does the Stop task button work'; Expected='User guide — Stop task:' }
    )
    foreach ($test in $completeFunctionTests) {
        $answer = Get-ToolAssistantAnswer -Question $test.Question -Culture $test.Culture -Knowledge $knowledge
        if ($answer -notlike ('*' + $test.Expected + '*')) {
            Add-AssistantVerificationError "Complete function coverage failed for '$($test.Question)' ($($test.Culture))."
        }
    }

    $firstReleaseEn = Get-ToolAssistantAnswer -Question 'when was v1 relased' -Culture 'en-US' -Knowledge $knowledge
    $releaseDateVi = Get-ToolAssistantAnswer -Question 'ngày build hiện tại của tool' -Culture 'vi-VN' -Knowledge $knowledge
    $releaseDateEn = Get-ToolAssistantAnswer -Question 'current in-place build date' -Culture 'en-US' -Knowledge $knowledge
    $pricingEn = Get-ToolAssistantAnswer -Question 'is it free' -Culture 'en-US' -Knowledge $knowledge
    $sourceEn = Get-ToolAssistantAnswer -Question 'where is the public srouce code' -Culture 'en-US' -Knowledge $knowledge
    $statusTermsEn = Get-ToolAssistantAnswer -Question 'what do Unknown, Unverified, Suspicious, and CrackConfirmed mean' -Culture 'en-US' -Knowledge $knowledge
    $statusTermsVi = Get-ToolAssistantAnswer -Question 'Unknown Unverified Suspicious Crack khác nhau thế nào' -Culture 'vi-VN' -Knowledge $knowledge
    if ($firstReleaseEn -notmatch 'v1\.0\.0.*July 17, 2026' -or
        $releaseDateVi -notmatch 'v5\.0.*06/09/2026' -or
        $releaseDateEn -notmatch 'v5\.0.*6 September 2026' -or
        $pricingEn -notmatch 'provided free of charge' -or
        $sourceEn -notmatch 'controlled access' -or
        $sourceEn -notmatch "author's written approval" -or
        $statusTermsEn -notmatch 'UNDETERMINED/Unknown' -or $statusTermsEn -notmatch 'UNVERIFIED' -or
        $statusTermsEn -notmatch 'SUSPICIOUS' -or $statusTermsEn -notmatch 'CRACKCONFIRMED' -or
        $statusTermsEn -notmatch 'no remediation yet' -or $statusTermsEn -notmatch 'not a legal verdict') {
        Add-AssistantVerificationError 'Bilingual product facts or contextual status definitions are incomplete.'
    }
    if ($statusTermsVi -notmatch 'CHƯA XÁC ĐỊNH/Unknown' -or $statusTermsVi -notmatch 'CHƯA XÁC MINH/Unverified' -or
        $statusTermsVi -notmatch 'NGHI VẤN/Suspicious' -or $statusTermsVi -notmatch 'CRACK ĐÃ XÁC NHẬN/CrackConfirmed' -or
        $statusTermsVi -notmatch 'chưa cho khắc phục' -or $statusTermsVi -notmatch 'không tự gỡ ứng dụng chính') {
        Add-AssistantVerificationError 'Vietnamese four-state answer is incomplete or not fail-closed.'
    }

    $licenseModelVi = Get-ToolAssistantAnswer -Question 'phần mềm nguồn mở có phải nộp hóa đơn bản quyền không' -Culture 'vi-VN' -Knowledge $knowledge
    $licenseModelEn = Get-ToolAssistantAnswer -Question 'does open source software require a purchase invoice' -Culture 'en-US' -Knowledge $knowledge
    if ($licenseModelVi -notmatch 'điều khoản.*LICENSE/notice.*nguồn cài' -or $licenseModelVi -match 'phải.*hóa đơn') {
        Add-AssistantVerificationError 'Vietnamese license-model answer applies generic commercial evidence to free/open-source software.'
    }
    if ($licenseModelEn -notmatch 'should not receive a generic purchase-invoice demand' -or $licenseModelEn -notmatch 'license model from technical evidence') {
        Add-AssistantVerificationError 'English license-model answer does not separate model from technical evidence.'
    }

    $lowConfidenceVi = Get-ToolAssistantAnswer -Question 'Tin cậy Low có đủ để xóa bloatware hay app thừa không' -Culture 'vi-VN' -Knowledge $knowledge
    $lowConfidenceEn = Get-ToolAssistantAnswer -Question 'can Low confidence remove a suspicious app' -Culture 'en-US' -Knowledge $knowledge
    if ($lowConfidenceVi -notmatch 'giữ nguyên ứng dụng' -or $lowConfidenceVi -notmatch 'không được dùng để xóa bloatware') {
        Add-AssistantVerificationError 'Vietnamese Low-confidence answer is not safely action-oriented.'
    }
    if ($lowConfidenceEn -notmatch 'Keep the app' -or $lowConfidenceEn -notmatch 'must not be used to remove bloatware') {
        Add-AssistantVerificationError 'English Low-confidence answer is not safely action-oriented.'
    }

    $remediationVi = Get-ToolAssistantAnswer -Question 'dấu hiệu nghi vấn thì điều kiện khắc phục phần mềm là gì' -Culture 'vi-VN' -Knowledge $knowledge
    $remediationEn = Get-ToolAssistantAnswer -Question 'remediation condition for suspicious software' -Culture 'en-US' -Knowledge $knowledge
    if ($remediationVi -notmatch 'Chưa xác minh hoặc Low.*giữ nguyên ứng dụng' -or
        $remediationVi -notmatch 'Nghi vấn chưa có hiện vật trực tiếp.*chưa cho khắc phục' -or
        $remediationVi -notmatch 'Trợ lý không tự chạy khắc phục') {
        Add-AssistantVerificationError 'Vietnamese remediation answer does not vary by evidence strength.'
    }
    if ($remediationEn -notmatch 'Unverified or Low confidence.*keep the app' -or
        $remediationEn -notmatch 'Suspicious without a direct artifact.*no remediation' -or
        $remediationEn -notmatch 'never runs remediation automatically') {
        Add-AssistantVerificationError 'English remediation answer does not vary by evidence strength.'
    }

    $scopeVi = Get-ToolAssistantAnswer -Question 'Windows yên nhưng Office có activator thì sao' -Culture 'vi-VN' -Knowledge $knowledge
    $scopeEn = Get-ToolAssistantAnswer -Question 'separate Windows Office and third party remediation scopes' -Culture 'en-US' -Knowledge $knowledge
    if ($scopeVi -notmatch 'Windows:' -or $scopeVi -notmatch 'Office:' -or $scopeVi -notmatch 'Phần mềm bên thứ ba:' -or
        $scopeEn -notmatch 'Windows:' -or $scopeEn -notmatch 'Office:' -or $scopeEn -notmatch 'Third-party software:') {
        Add-AssistantVerificationError 'Assistant does not keep Windows, Office, and third-party license scopes distinct.'
    }

    $commercialVi = Get-ToolAssistantAnswer -Question 'WinRAR không có crack thì xử lý sao' -Culture 'vi-VN' -Knowledge $knowledge
    $commercialEn = Get-ToolAssistantAnswer -Question 'what should I do with MathType when no activator is found' -Culture 'en-US' -Knowledge $knowledge
    if ($commercialVi -notmatch 'giữ nguyên ứng dụng' -or $commercialVi -notmatch 'mua giấy phép, gỡ ứng dụng hoặc chọn phần mềm thay thế hợp pháp' -or
        $commercialEn -notmatch 'keep the app' -or $commercialEn -notmatch 'lawful alternative') {
        Add-AssistantVerificationError 'Commercial-software answer removes or condemns an app without direct evidence.'
    }

    $windowsFollowUp = Get-ToolAssistantAnswer -Question 'cách dùng nó' -PreviousQuestion 'chức năng 3 là gì' -Culture 'vi-VN' -Knowledge $knowledge
    $oemFollowUp = Get-ToolAssistantAnswer -Question 'thế còn chức năng 7' -PreviousQuestion 'cách dùng chức năng 6' -Culture 'vi-VN' -Knowledge $knowledge
    $sourceFollowUp = Get-ToolAssistantAnswer -Question 'ở đâu' -PreviousQuestion 'mã nguồn công khai ở đâu' -Culture 'vi-VN' -Knowledge $knowledge
    $sourceFollowUpEn = Get-ToolAssistantAnswer -Question 'where' -PreviousQuestion 'where is the public source code' -Culture 'en-US' -Knowledge $knowledge
    if ($windowsFollowUp -notmatch 'Chức năng 3.*Bản quyền Windows|Chức năng 3.*trạng thái kích hoạt') {
        Add-AssistantVerificationError 'Context follow-up did not retain the Windows feature topic.'
    }
    if ($oemFollowUp -notmatch 'Chức năng 7.*OEM' -or $oemFollowUp -match 'không phải chức năng số 7') {
        Add-AssistantVerificationError 'Context follow-up cross-routed feature 7 away from OEM recovery.'
    }
    if ($sourceFollowUp -notmatch 'truy cập có kiểm soát' -or
        $sourceFollowUpEn -notmatch 'controlled access') {
        Add-AssistantVerificationError 'Short where/o dau follow-up did not retain the source-access topic.'
    }

    $offlineNow = Get-ToolAssistantAnswer -Question 'tool đang online hay offline hiện tại' -Culture 'vi-VN' -Knowledge $knowledge -OnlineMode $false
    $onlineNow = Get-ToolAssistantAnswer -Question 'trạng thái online của tool lúc này' -Culture 'vi-VN' -Knowledge $knowledge -OnlineMode $true
    if ($offlineNow -notmatch 'hiện đang Offline' -or $onlineNow -notmatch 'đang Online trong phiên hiện tại') {
        Add-AssistantVerificationError 'Assistant did not use the actual current Online/Offline state.'
    }

    $cookingOutside = Get-ToolAssistantAnswer -Question 'cách nấu bún bò huế' -Culture 'vi-VN' -Knowledge $knowledge
    $weatherOutside = Get-ToolAssistantAnswer -Question 'thời tiết hôm nay' -Culture 'vi-VN' -Knowledge $knowledge
    $relatedUnknown = Get-ToolAssistantAnswer -Question 'tool quản lý một định dạng nội bộ chưa được tài liệu hóa thế nào' -Culture 'vi-VN' -Knowledge $knowledge
    if ($cookingOutside -notmatch 'nấu ăn.*ngoài phạm vi' -or $weatherOutside -notmatch 'Thời tiết.*ngoài phạm vi' -or $cookingOutside -eq $weatherOutside) {
        Add-AssistantVerificationError 'Out-of-scope replies are not adapted to their question context.'
    }
    if ($relatedUnknown -match 'không liên quan đến Tool|không thuộc VietLicenSure|ngoài phạm vi Tool') {
        Add-AssistantVerificationError 'A Tool-related question was incorrectly rejected as out of scope.'
    }
    $scopeInjectionKnowledge = (Get-Content -LiteralPath $knowledgePath -Raw -Encoding UTF8) | ConvertFrom-Json
    $scopeInjectionKnowledge.Entries[0].Keywords = @($scopeInjectionKnowledge.Entries[0].Keywords) + @('cach nau bun bo hue')
    $scopeGuardedAnswer = Get-ToolAssistantAnswer -Question 'cách nấu bún bò huế' -Culture 'vi-VN' -Knowledge $scopeInjectionKnowledge
    if ($scopeGuardedAnswer -notmatch 'ngoài phạm vi VietLicenSure') {
        Add-AssistantVerificationError 'A high-scoring injected keyword bypassed the Tool-only scope gate.'
    }

    $learningAnswer = Get-ToolAssistantAnswer -Question 'trợ lý học hỏi liên tục mà không tăng dung lượng exe như thế nào' -Culture 'vi-VN' -Knowledge $knowledge
    if ($learningAnswer -notmatch 'cache rời' -or $learningAnswer -notmatch 'không làm tăng EXE' -or $learningAnswer -notmatch 'không được gửi đi') {
        Add-AssistantVerificationError 'The signed external-knowledge architecture is not explained accurately.'
    }

    $pluginAnswer = Get-ToolAssistantAnswer -Question 'cách cài plugin json chỉ đọc' -Culture 'vi-VN' -Knowledge $knowledge
    $formatAnswer = Get-ToolAssistantAnswer -Question 'tool có xuất báo cáo docx không' -Culture 'vi-VN' -Knowledge $knowledge
    if ($pluginAnswer -notmatch 'nguồn tin cậy' -or $formatAnswer -notmatch 'không xuất DOCX') {
        Add-AssistantVerificationError 'Feature 10 subfeatures or report-format questions are not answered specifically.'
    }

    if (-not [string]::IsNullOrEmpty((Resolve-ToolAssistantReportJsonPath -Path '\\server\share\report.json'))) {
        Add-AssistantVerificationError 'Assistant accepted a network/UNC report path.'
    }
    $reportFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('tool-assistant-report-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $reportFixtureRoot | Out-Null
        $invalidReportPath = Join-Path $reportFixtureRoot 'unrelated.json'
        [IO.File]::WriteAllText($invalidReportPath, '{"Name":"not-a-tool-report"}', (New-Object Text.UTF8Encoding($false)))
        if ($null -ne (Get-ToolAssistantReportContext -ReportPath $invalidReportPath)) {
            Add-AssistantVerificationError 'Assistant accepted JSON that was not generated as a Tool report.'
        }
        $validReportPath = Join-Path $reportFixtureRoot 'report.json'
        $validReportJson = '{"SchemaVersion":"1.5","ReportKind":"InventoryAndLicense","CreatedAt":"2026-08-08T00:00:00Z","Mode":"Windows","OfflineMode":true,"WindowsStatus":"Unknown","WindowsChannel":"Unknown","WindowsConclusionCode":"Undetermined","WindowsConclusion":"Test Windows","OfficeDetected":false,"OfficeStatus":"NotDetected","OfficeConclusionCode":"NotDetected","OfficeConclusion":"Test Office","SuspiciousFindingCount":1,"ManualReviewFindingCount":2,"ThirdPartyApplicationCount":3,"ThirdPartyHighSeverityCount":0}'
        [IO.File]::WriteAllText($validReportPath, $validReportJson, (New-Object Text.UTF8Encoding($false)))
        $validReportContext = Get-ToolAssistantReportContext -ReportPath $validReportPath
        if ($null -eq $validReportContext -or [string]$validReportContext.WindowsConclusion -ne 'Test Windows') {
            Add-AssistantVerificationError 'Assistant could not read a valid local Tool report fixture.'
        }
        $englishReportAnswer = Format-ToolAssistantReportContext -Context $validReportContext -Culture 'en-US'
        $vietnameseReportAnswer = Format-ToolAssistantReportContext -Context $validReportContext -Culture 'vi-VN'
        if ($englishReportAnswer -notmatch 'Windows:\s+Undetermined' -or $englishReportAnswer -match 'Chưa|Không phát hiện|Test Windows') {
            Add-AssistantVerificationError 'English report context contains an unsynchronized conclusion.'
        }
        if ($vietnameseReportAnswer -notmatch 'Windows:\s+Chưa xác định' -or $vietnameseReportAnswer -match 'No conclusion|Not scanned') {
            Add-AssistantVerificationError 'Vietnamese report context contains an unsynchronized conclusion.'
        }
    } finally {
        if (Test-Path -LiteralPath $reportFixtureRoot -PathType Container) { Remove-Item -LiteralPath $reportFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $testInput = New-Object Windows.Forms.TextBox
    $testInputFrame = New-Object Windows.Forms.Panel
    $testSend = New-Object Windows.Forms.Button
    $testChat = New-Object Windows.Forms.FlowLayoutPanel
    $testHost = New-Object Windows.Forms.Form
    $testLayout = New-Object Windows.Forms.TableLayoutPanel
    $testComposer = New-Object Windows.Forms.Panel
    $testHost.ShowInTaskbar = $false
    $testHost.StartPosition = 'Manual'
    $testHost.Location = New-Object Drawing.Point(-32000, -32000)
    $testHost.Size = New-Object Drawing.Size(720, 270)
    $testLayout.Dock = 'Fill'
    $testLayout.ColumnCount = 1
    $testLayout.RowCount = 2
    [void]$testLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 100)))
    [void]$testLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 100)))
    [void]$testLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 64)))
    $testHost.Controls.Add($testLayout)
    $testChat.Dock = 'Fill'
    $testChat.FlowDirection = [Windows.Forms.FlowDirection]::TopDown
    $testChat.WrapContents = $false
    $testChat.AutoScroll = $true
    $testChat.Padding = New-Object Windows.Forms.Padding(12)
    $testComposer.Dock = 'Fill'
    $testComposer.BackColor = [Drawing.Color]::WhiteSmoke
    $testLayout.Controls.Add($testChat, 0, 0)
    $testLayout.Controls.Add($testComposer, 0, 1)
    $testHost.Show()
    [Windows.Forms.Application]::DoEvents()
    $testSpeakerFont = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    $testMessageFont = New-Object Drawing.Font('Segoe UI', 10)
    $testRenderTimer = New-Object Windows.Forms.Timer
    $testRenderTimer.Interval = 15
    try {
        $testState = [pscustomobject]@{
            Input=$testInput; Chat=$testChat; SendButton=$testSend; Culture='vi-VN'; Knowledge=$knowledge; ReportContext=$null
            SpeakerFont=$testSpeakerFont; MessageFont=$testMessageFont; Transcript=(New-Object Text.StringBuilder); IsSubmitting=$false
            PendingRevealControl=$null; RevealQueued=$false; RenderTimer=$testRenderTimer
            LastQuestionKey=''; LastQuestionText=''; LastAnswer=''; OnlineMode=$false
            UserBubbleColor=[Drawing.Color]::FromArgb(0,98,218); UserTextColor=[Drawing.Color]::White
            UserBubbleBorderColor=[Drawing.Color]::FromArgb(0,72,164)
            AssistantBubbleColor=[Drawing.Color]::FromArgb(232,241,252); AssistantTextColor=[Drawing.Color]::Black
            AssistantBubbleBorderColor=[Drawing.Color]::FromArgb(143,174,211); AssistantHeaderColor=[Drawing.Color]::FromArgb(0,98,218)
            InputFrame=$testInputFrame; InputIdleBorderColor=[Drawing.Color]::FromArgb(118,136,162)
            InputFocusBorderColor=[Drawing.Color]::FromArgb(0,98,218)
        }
        $testRenderTimer.Tag = $testState
        $testRenderTimer.Add_Tick({
            param($sender, $eventArgs)
            $sender.Stop()
            $state = $sender.Tag
            $latest = $state.PendingRevealControl
            $state.PendingRevealControl = $null
            Complete-ToolAssistantConversationLayout -State $state -LatestControl $latest
        })
        $testInput.Text = 'kms là gì'
        $submittedAnswer = Invoke-ToolAssistantQuestion -State $testState
        if ([string]::IsNullOrWhiteSpace([string]$submittedAnswer) -or
            $testChat.Controls.Count -ne 2 -or
            [string]$testChat.Controls[0].Tag.Role -ne 'User' -or
            [string]$testChat.Controls[1].Tag.Role -ne 'Assistant' -or
            $testChat.Controls[0].Tag.Bubble.Left -le $testChat.Controls[1].Tag.Bubble.Left -or
            $testChat.Controls[0].Tag.Bubble.BackColor.ToArgb() -eq $testChat.Controls[1].Tag.Bubble.BackColor.ToArgb() -or
            $testChat.Controls[0].Tag.Bubble.Tag.ToArgb() -eq $testChat.Controls[1].Tag.Bubble.Tag.ToArgb() -or
            $testState.Transcript.ToString() -notmatch 'Bạn\s+kms là gì\s+Trợ lý VietLicenSure') {
            Add-AssistantVerificationError 'The shared Send/Enter submission path did not append a question and answer.'
        }
        Set-ToolAssistantInputFrameState -State $testState -Focused $false
        $idleInputBorder = $testInputFrame.BackColor.ToArgb()
        Set-ToolAssistantInputFrameState -State $testState -Focused $true
        if ($idleInputBorder -eq $testInputFrame.BackColor.ToArgb() -or
            $testInputFrame.BackColor.ToArgb() -ne $testState.InputFocusBorderColor.ToArgb()) {
            Add-AssistantVerificationError 'The chat input frame does not expose a distinct focus border.'
        }

        foreach ($headerCulture in @('vi-VN','en-US')) {
            foreach ($dpiScale in @(1.0, 1.25, 1.5)) {
                $testHeader = New-Object Windows.Forms.Panel
                $testHeader.Size = New-Object Drawing.Size([int](660 * $dpiScale), [int](112 * $dpiScale))
                $testHeaderTitleFont = New-Object Drawing.Font('Segoe UI Semibold', ([single](17 * $dpiScale)))
                $testHeaderScopeFont = New-Object Drawing.Font('Segoe UI', ([single](9 * $dpiScale)))
                $testHeaderTitle = New-Object Windows.Forms.Label
                $testHeaderTitle.Text = Get-ToolAssistantUiText 'Title' $headerCulture
                $testHeaderTitle.Font = $testHeaderTitleFont
                $testHeaderTitle.Location = New-Object Drawing.Point([int](18 * $dpiScale), [int](10 * $dpiScale))
                $testHeaderScope = New-Object Windows.Forms.Label
                $testHeaderScope.Text = Get-ToolAssistantUiText 'Scope' $headerCulture
                $testHeaderScope.Font = $testHeaderScopeFont
                $testHeaderMode = New-Object Windows.Forms.Label
                $testHeaderMode.Text = Get-ToolAssistantUiText 'Offline' $headerCulture
                $testHeader.Controls.Add($testHeaderTitle)
                $testHeader.Controls.Add($testHeaderScope)
                $testHeader.Controls.Add($testHeaderMode)
                Set-ToolAssistantHeaderBounds -Header $testHeader -TitleLabel $testHeaderTitle -ScopeLabel $testHeaderScope -ModeLabel $testHeaderMode -DpiScale $dpiScale
                $singleLineFlags = [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::NoPrefix -bor [Windows.Forms.TextFormatFlags]::NoPadding
                $wrappedFlags = [Windows.Forms.TextFormatFlags]::WordBreak -bor [Windows.Forms.TextFormatFlags]::NoPrefix -bor [Windows.Forms.TextFormatFlags]::NoPadding
                $requiredTitle = [Windows.Forms.TextRenderer]::MeasureText([string]$testHeaderTitle.Text, $testHeaderTitle.Font, [Drawing.Size]::Empty, $singleLineFlags)
                $requiredScope = [Windows.Forms.TextRenderer]::MeasureText([string]$testHeaderScope.Text, $testHeaderScope.Font, (New-Object Drawing.Size($testHeaderScope.Width, 500)), $wrappedFlags)
                if ($testHeaderMode.Right -gt ($testHeader.ClientSize.Width - [int](16 * $dpiScale)) -or
                    $testHeaderTitle.Right -ge $testHeaderMode.Left -or
                    $testHeaderScope.Top -lt $testHeaderTitle.Bottom -or
                    $testHeaderTitle.Width -lt $requiredTitle.Width -or $testHeaderTitle.Height -lt $requiredTitle.Height -or
                    $testHeaderScope.Height -lt $requiredScope.Height) {
                    Add-AssistantVerificationError "Assistant header is clipped for $headerCulture at $([int]($dpiScale * 100))% DPI."
                }
                $testHeader.Dispose(); $testHeaderTitleFont.Dispose(); $testHeaderScopeFont.Dispose()
            }
        }
        $controlCountBeforeDuplicate = $testChat.Controls.Count
        $testInput.Text = 'office là gì'
        $testState.IsSubmitting = $true
        $duplicateAnswer = Invoke-ToolAssistantQuestion -State $testState
        if (-not [string]::IsNullOrEmpty([string]$duplicateAnswer) -or
            $testChat.Controls.Count -ne $controlCountBeforeDuplicate -or
            $testInput.Text -ne 'office là gì') {
            Add-AssistantVerificationError 'Duplicate submission was not blocked while an answer was being processed.'
        }
        $testState.IsSubmitting = $false

        Clear-ToolAssistantConversation -State $testState
        foreach ($index in 1..8) {
            [void](Add-ToolAssistantChatMessage -State $testState -Role Assistant -Message ("Dòng kiểm thử hiển thị $index. Nội dung đủ dài để tạo vùng cuộn trong hội thoại."))
        }
        $testInput.Text = 'office là gì'
        $immediateAnswer = Invoke-ToolAssistantQuestion -State $testState
        for ($pump = 0; $pump -lt 5 -and $testRenderTimer.Enabled; $pump++) {
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 20
        }
        $answerControl = $testChat.Controls[$testChat.Controls.Count - 1]
        $chatScreen = $testChat.RectangleToScreen($testChat.ClientRectangle)
        $answerScreen = $answerControl.RectangleToScreen($answerControl.ClientRectangle)
        $composerScreen = $testComposer.RectangleToScreen($testComposer.ClientRectangle)
        $visibleAnswer = [Drawing.Rectangle]::Intersect($chatScreen, $answerScreen)
        $answerMetadata = $answerControl.Tag
        $answerIsComplete = [bool](
            $visibleAnswer.Width -eq $answerScreen.Width -and
            $visibleAnswer.Height -eq $answerScreen.Height -and
            $answerMetadata.MessageLabel.Bottom -le $answerMetadata.Bubble.ClientSize.Height
        )
        if ([string]::IsNullOrWhiteSpace([string]$immediateAnswer) -or $visibleAnswer.Width -le 0 -or $visibleAnswer.Height -le 0 -or
            -not $answerIsComplete -or $chatScreen.Bottom -gt $composerScreen.Top -or
            $testRenderTimer.Enabled -or [bool]$testState.RevealQueued -or $null -ne $testState.PendingRevealControl) {
            Add-AssistantVerificationError ("The complete answer was not laid out above the composer, scrolled into view, and painted during the same submission. chat={0}; answer={1}; visible={2}; composer={3}; labelBottom={4}; bubbleHeight={5}; timer={6}; queued={7}; pending={8}" -f $chatScreen,$answerScreen,$visibleAnswer,$composerScreen,$answerMetadata.MessageLabel.Bottom,$answerMetadata.Bubble.ClientSize.Height,$testRenderTimer.Enabled,$testState.RevealQueued,($null -ne $testState.PendingRevealControl))
        }

        Clear-ToolAssistantConversation -State $testState
        if ($testChat.Controls.Count -ne 0 -or $testState.Transcript.Length -ne 0 -or
            -not [string]::IsNullOrEmpty([string]$testState.LastQuestionText)) {
            Add-AssistantVerificationError 'Clearing the bubble conversation did not clear both UI and transcript.'
        }
    } finally {
        $testRenderTimer.Stop(); $testRenderTimer.Dispose(); $testHost.Close(); $testHost.Dispose(); $testInput.Dispose(); $testInputFrame.Dispose(); $testSend.Dispose(); $testChat.Dispose(); $testComposer.Dispose(); $testLayout.Dispose(); $testSpeakerFont.Dispose(); $testMessageFont.Dispose()
    }

    $oldOfflineMode = [string]$env:TOOL_OFFLINE_MODE
    $oldSettingsPath = [string]$env:TOOL_OFFLINE_SETTINGS_PATH
    $temporarySettings = Join-Path ([IO.Path]::GetTempPath()) ('tool-offline-verifier-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllText($temporarySettings, '{"OfflineMode":false}', (New-Object Text.UTF8Encoding($false)))
        Remove-Item Env:TOOL_OFFLINE_MODE -ErrorAction SilentlyContinue
        $env:TOOL_OFFLINE_SETTINGS_PATH = $temporarySettings
        . (Join-Path $SourceDirectory 'Tool-OfflinePolicy.ps1')
        if (-not (Get-ToolOfflineMode)) { Add-AssistantVerificationError 'Fresh process did not fail closed to Offline.' }
    } finally {
        if ($oldOfflineMode) { $env:TOOL_OFFLINE_MODE = $oldOfflineMode } else { Remove-Item Env:TOOL_OFFLINE_MODE -ErrorAction SilentlyContinue }
        if ($oldSettingsPath) { $env:TOOL_OFFLINE_SETTINGS_PATH = $oldSettingsPath } else { Remove-Item Env:TOOL_OFFLINE_SETTINGS_PATH -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $temporarySettings -Force -ErrorAction SilentlyContinue
    }

    $guiSource = Get-Content -LiteralPath (Join-Path $SourceDirectory 'Giao-Dien.ps1') -Raw -Encoding UTF8
    foreach ($requiredToken in @('$introAssistantButton','Show-ToolAssistantWindow','TitleLabel','DescriptionLabel','TitleColor')) {
        if (-not $guiSource.Contains($requiredToken)) { Add-AssistantVerificationError "Dashboard integration token missing: $requiredToken" }
    }
    if ($guiSource -notmatch 'RequestOnline\s+\$requestAssistantOnline') {
        Add-AssistantVerificationError 'Dashboard does not pass the current-session Online callback to Tool Assistant.'
    }
    $assistantSource = Get-Content -LiteralPath (Join-Path $SourceDirectory 'Tool-Assistant.ps1') -Raw -Encoding UTF8
    foreach ($requiredToken in @('$send.Tag = $assistantState','Queue-ToolAssistantQuestion -State $sender.Tag','$eventArgs.Handled = $true','BeginInvoke','SubmissionQueued','ConnectOnline','ConnectOnlineTip','Update-ToolAssistantConnectionUi','Update-ToolAssistantConversationUi','Complete-ToolAssistantConversationLayout','Set-ToolAssistantHeaderBounds','Set-ToolAssistantInputFrameState','InputIdleBorderColor','UserBubbleBorderColor','AssistantBubbleBorderColor','RenderTimer','PendingRevealControl','RevealQueued','[Windows.Forms.Application]::DoEvents()','Windows.Forms.FlowLayoutPanel','Windows.Forms.TableLayoutPanel','Role User','Role Assistant','IsSubmitting','SendButton.Enabled','Expand-ToolAssistantContextQuery','Test-ToolAssistantRelatedQuery','Get-ToolAssistantDocumentAnswer','Get-ToolAssistantHistoryAnswer','CompleteBundledGuideIndexed','CompleteVersionHistoryIndexed','LastQuestionText','KnowledgePlusBundledDocumentation','Test-ToolAssistantKnowledgeSignature','DetachedCmsSha256PinnedCertificate','Save-ToolAssistantSignedKnowledgeCache','remoteVersion -lt $currentVersion','Invoke-ToolAssistantKnowledgeSyncUi')) {
        if (-not $assistantSource.Contains($requiredToken)) { Add-AssistantVerificationError "Assistant UI interaction token missing: $requiredToken" }
    }
    if ($assistantSource.Contains('New-Object Windows.Forms.RichTextBox')) {
        Add-AssistantVerificationError 'Assistant conversation still uses a shared RichTextBox instead of separate bubbles.'
    }
    if ($assistantSource -match '"Scope"[^\r\n]+(?:paid API|API trả phí|Codex)') {
        Add-AssistantVerificationError 'Assistant scope line still contains API/Codex promotional text.'
    }
    $expectedScopeVi = 'Giải đáp về VietLicenSure bằng tri thức cục bộ, HDSD, lịch sử phiên bản và dữ liệu báo cáo hiện có.'
    $expectedScopeEn = 'Answers questions about VietLicenSure using local knowledge, guides, version history, and available report data.'
    $expectedWelcomeVi = 'Trợ lý VietLicenSure hỗ trợ tra cứu, giải đáp và hướng dẫn dựa trên kho tri thức, HDSD, lịch sử phiên bản và dữ liệu báo cáo hiện có.'
    $expectedWelcomeEn = 'The VietLicenSure Assistant supports lookup, answers, and guidance based on its knowledge base, user guides, version history, and available report data.'
    if ((Get-ToolAssistantUiText -Key Scope -Culture 'vi-VN') -ne $expectedScopeVi -or
        (Get-ToolAssistantUiText -Key Scope -Culture 'en-US') -ne $expectedScopeEn -or
        (Get-ToolAssistantUiText -Key Welcome -Culture 'vi-VN') -ne $expectedWelcomeVi -or
        (Get-ToolAssistantUiText -Key Welcome -Culture 'en-US') -ne $expectedWelcomeEn) {
        Add-AssistantVerificationError 'Assistant scope/welcome wording does not match the approved professional copy.'
    }
    if ((Get-ToolAssistantUiText -Key Welcome -Culture 'vi-VN') -match 'Bạn (?:có thể|cứ) (?:đặt câu hỏi|hỏi)' -or
        (Get-ToolAssistantUiText -Key Welcome -Culture 'en-US') -match 'Ask in your own words') {
        Add-AssistantVerificationError 'Assistant welcome still contains the removed invitation-to-ask sentence.'
    }
    foreach ($culture in @('vi-VN','en-US')) {
        foreach ($theme in @('Light','Dark')) {
            try { Show-ToolAssistantWindow -Culture $culture -Theme $theme -SmokeTest | Out-Null }
            catch { Add-AssistantVerificationError ('Assistant UI smoke failed for {0}/{1}: {2}' -f $culture,$theme,$_.Exception.Message) }
        }
    }
    $knowledgePublishedText = [string]::Join("`n", @($knowledge.Entries | ForEach-Object {
        [string]$_.TitleVi; [string]$_.TitleEn; [string]$_.AnswerVi; [string]$_.AnswerEn
    }))
    if ($knowledgePublishedText -match '(?i)API trả phí|paid API|Codex') {
        Add-AssistantVerificationError 'Published assistant knowledge still contains the removed API/Codex sentence.'
    }
    foreach ($neutralityPattern in @('(?i)(?<![\p{L}\p{N}])luna(?![\p{L}\p{N}])','(?i)(?<![\p{L}\p{N}])caca(?![\p{L}\p{N}])')) {
        if ($assistantSource -match $neutralityPattern -or $knowledgePublishedText -match $neutralityPattern) {
            Add-AssistantVerificationError "Published assistant contains a personal form of address matching '$neutralityPattern'."
        }
    }
    $vi = Get-Content -LiteralPath (Join-Path $SourceDirectory 'Tool-Strings.vi-VN.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $en = Get-Content -LiteralPath (Join-Path $SourceDirectory 'Tool-Strings.en-US.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$vi.'about.technology.body' -match '(?i)API trả phí|Codex' -or [string]$en.'about.technology.body' -match '(?i)paid API|Codex') {
        Add-AssistantVerificationError 'Product information still contains the removed API/Codex sentence.'
    }
    if ([string]$vi.'about.technology.body' -notlike "*$expectedWelcomeVi*" -or
        [string]$en.'about.technology.body' -notlike "*$expectedWelcomeEn*") {
        Add-AssistantVerificationError 'Product information does not use the approved professional Assistant wording.'
    }
    $englishOfflineSync = Sync-ToolAssistantKnowledge -OnlineMode $false -Culture 'en-US'
    if ([string]$englishOfflineSync.Message -notmatch '^VietLicenSure Assistant is Offline' -or [string]$englishOfflineSync.Message -match 'Trợ lý|tri thức') {
        Add-AssistantVerificationError 'Assistant synchronization status is not fully localized in English.'
    }
    if ([string]$vi.'report.license.windows.unverifiableShort' -notlike 'CHƯA XÁC ĐỊNH*') {
        Add-AssistantVerificationError 'Short Windows conclusion is not CHUA XAC DINH.'
    }
    if ([string]$vi.'report.license.windows.unverifiable' -notlike '*không chứng minh giấy phép hợp lệ hoặc không hợp lệ*') {
        Add-AssistantVerificationError 'Detailed Windows conclusion is not evidence-neutral.'
    }
}

if ($errors.Count -gt 0) {
    Write-Host "VERIFY-ASSISTANT: $($errors.Count) error(s)." -ForegroundColor Red
    $errors | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'VERIFY-ASSISTANT: 0 errors (complete VI/EN version and function matrices + signed external knowledge + rollback protection + Tool-only scope + local privacy + context follow-up + immediate bubbles + Send/Enter + live Online state).' -ForegroundColor Green
exit 0
