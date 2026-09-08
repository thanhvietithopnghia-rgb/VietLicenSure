# Mô hình đe dọa VietLicenSure v5.0

Phiên bản áp dụng: **v5.0.0.2 ManagedSigned/Pilot**  
Ngày rà soát: **2026-09-08**

## Mục tiêu bảo vệ

VietLicenSure phải bảo vệ bốn nhóm tài sản:

1. tính nguyên vẹn và nguồn gốc của EXE, payload, catalog, tri thức trợ lý và manifest cập nhật;
2. giấy phép hợp lệ, cấu hình Windows/Office, registry, dịch vụ, tác vụ và tệp hệ thống của người dùng;
3. backup, lịch sử hậu kiểm và dữ liệu dùng để rollback;
4. báo cáo, log và các định danh nhạy cảm của máy/tổ chức.

Mục tiêu an toàn quan trọng nhất là **không biến bằng chứng thiếu hoặc lỗi đọc dữ liệu thành hành động phá hủy**.

## Biên tin cậy

- **Không tin cậy:** Internet, bản tải lại từ bên thứ ba, catalog/plugin ngoài, đường dẫn do người dùng nhập, dữ liệu registry/WMI/CIM có thể thiếu hoặc bị sửa, tệp được phát hiện khi quét.
- **Tin cậy có điều kiện:** gói phát hành chỉ sau khi checksum, CMS exact-byte, chứng thư ghim, provenance, SBOM và Authenticode cùng khớp.
- **Đặc quyền cao:** tiến trình/broker được nâng quyền, ProgramData, registry máy, dịch vụ, Scheduled Tasks, hosts/firewall và vùng backup được bảo vệ.
- **Ranh giới tổ chức:** endpoint quản trị doanh nghiệp/LAN chỉ được dùng sau lựa chọn chủ động và kiểm tra protocol/envelope; Offline vẫn là mặc định.

## Tác nhân và tình huống đe dọa

| Đe dọa | Tác động chính | Kiểm soát hiện có |
|---|---|---|
| EXE hoặc sidecar bị sửa/đóng gói lại | chạy mã giả, kết luận sai, thao tác hệ thống trái phép | SHA-256 tập tệp đóng, Authenticode, CMS tách rời, chứng thư ghim, provenance fail-closed |
| Chuyển đổi CRLF/LF trên JSON đã ký | chữ ký CMS báo sai hoặc bị kiểm tra nhầm | ký và kiểm tra đúng byte; `.p7s`/update manifest được giữ binary; verifier không chuẩn hóa trước khi xác minh |
| Catalog/tri thức/plugin giả | tăng điểm bằng chứng giả, hướng dẫn nguy hiểm | schema/allowlist, detached CMS, fingerprint publisher, dữ liệu khai báo, không thực thi script plugin |
| DLL/command/path hijacking | thực thi thành phần ngoài ý muốn | launcher một tệp, đường dẫn tuyệt đối/allowlist, validation kích thước/hash, thư mục bảo vệ và kiểm tra reparse point |
| Nâng quyền quá rộng | mất quyền kiểm soát registry/tệp/dịch vụ | dashboard chạy `asInvoker`; chỉ broker hành động cụ thể yêu cầu UAC; hợp đồng môi trường có schema/tuổi/invocation |
| Xóa nhầm license hoặc phần mềm hợp lệ | mất kích hoạt hoặc ứng dụng | preview + xác nhận theo mục, evidence threshold, allowlist, backup trước thay đổi, hậu kiểm và trạng thái retry/repair |
| Backup/rollback bị giả mạo | khôi phục trạng thái độc hại | DPAPI/HMAC, hash chain, ACL Administrators/SYSTEM; artifact kích hoạt trái phép không được đánh dấu có thể khôi phục |
| Log/báo cáo làm lộ định danh hoặc key | rò rỉ dữ liệu cá nhân/tổ chức | che serial/UUID/Processor ID/Asset Tag theo mặc định, không ghi full product key, FullInternal cần lựa chọn rõ |
| Formula injection trong CSV | thực thi công thức khi mở bảng tính | escape ký tự công thức ở đầu ô và redaction mặc định |
| Kết nối mạng ngoài ý muốn | rò dữ liệu hoặc nhận cập nhật giả | Offline mặc định, không telemetry, người dùng bật Online, HTTPS/host allowlist, manifest cập nhật CMS + hash + signer |
| Dữ liệu WMI/CIM/dịch vụ lỗi | kết luận “không có license” sai | phân biệt lỗi nguồn dữ liệu với trạng thái chưa kích hoạt; thử CIM/WMI có giới hạn; không tự khắc phục khi bằng chứng thiếu |
| Symlink/junction/reparse point | thoát khỏi thư mục dự kiến | bộ build/verifier/đóng gói từ chối reparse point và canonicalize đường dẫn |
| Resource exhaustion khi deep scan | treo máy hoặc bỏ dở không rõ | ngân sách thời gian/depth/files/signatures/hashes; Quick/Standard/Deep; kết quả Unverified khi không đủ phủ |

## Luồng thay đổi hệ thống

Mọi thay đổi registry, service, Scheduled Task, firewall, hosts, tệp license hoặc gỡ ứng dụng phải đi theo chuỗi:

`Nguồn gốc hợp lệ → bằng chứng đủ → kế hoạch chỉ rõ mục tiêu → preview → xác nhận người dùng → backup → UAC theo nhu cầu → thay đổi giới hạn → hậu kiểm → rollback/retry khi cần`

Nếu nguồn gốc bản dựng, signer, schema, backup hoặc mục tiêu thay đổi giữa preview và thực thi, luồng phải dừng. Mã thoát của tiến trình không được dùng một mình để kết luận kích hoạt hay làm sạch thành công.

## Backup, log và dữ liệu đầu ra

- Backup phải ghi loại mục tiêu, hash/kích thước, khả năng khôi phục và chính sách giữ dữ liệu.
- Dữ liệu không được khôi phục (ví dụ artifact kích hoạt trái phép) phải được đánh dấu rõ, không ngụy trang thành bản sao an toàn.
- Timeline tách trạng thái hiện tại khỏi bằng chứng lịch sử; bằng chứng đã biến mất không còn được trình bày là đang hoạt động.
- Log dưới `%LOCALAPPDATA%` thuộc tài khoản hiện tại; dữ liệu nâng quyền/doanh nghiệp dưới `%ProgramData%` cần ACL Administrators/SYSTEM.
- Support bundle mặc định phải redacted; người dùng chịu trách nhiệm khi chủ động tạo bản FullInternal.

## Cập nhật và chuỗi cung ứng

- Metadata cập nhật phải đến từ URL GitHub HTTPS cố định, đúng kích thước/hash và có chữ ký CMS của chứng thư ghim.
- EXE tải về phải có Authenticode đúng signer; bản ManagedSigned chấp nhận root tự ký chưa được máy tin cậy chỉ khi cả SHA-1/SHA-256 đều khớp hồ sơ.
- SBOM CycloneDX và provenance phải gắn đúng EXE, Build ID, source snapshot và release status.
- Bản không xác minh được không được tự cập nhật hoặc thực hiện hành động thay đổi hệ thống.

## Rủi ro còn lại và giới hạn

- Chứng thư ManagedSigned là tự ký: pinning bảo vệ tính liên tục danh tính, nhưng không thay thế xác thực tổ chức bởi CA công cộng.
- Kiểm tra revocation có thể không xác định khi máy Offline; không được đổi trạng thái này thành “Valid” nếu signer/hash không khớp.
- VietLicenSure không vượt AppLocker, WDAC, SmartScreen, antivirus hoặc chính sách doanh nghiệp.
- Công cụ đánh giá trạng thái kỹ thuật, không chứng minh quyền sở hữu pháp lý của giấy phép.
- Ma trận Windows 10/11 sạch và các tình huống có/không Office, user/admin, Offline/Online phải có bằng chứng độc lập theo từng build; kiểm thử cục bộ không thay thế yêu cầu này.

## Tiêu chí xem xét lại

Rà soát mô hình này khi thay signer/cert, định dạng manifest, nguồn cập nhật, broker nâng quyền, adapter phần mềm, vị trí lưu backup/log, protocol doanh nghiệp hoặc trước khi nâng kênh thành Public Stable.
