# Bản đồ tài liệu VietLicenSure v5.0

Phiên bản áp dụng: **VietLicenSure v5.0.0.2**  
Kênh áp dụng: **ManagedSigned/Pilot**  
Ngày chốt hồ sơ: **2026-09-08**

Tài liệu này xác định đâu là hồ sơ hiện hành của v5.0.0.2 và giải thích các tên tệp còn mang mốc v4.8/v4.9. Mốc trong tên tệp là phiên bản hình thành hợp đồng kỹ thuật hoặc chính sách, không phải phiên bản của tệp thực thi đang bàn giao.

## Tài liệu nên đọc trước

| Nhu cầu | Tài liệu hiện hành |
|---|---|
| Cài đặt và dùng lần đầu | `QUICK-START-v5.0.md`, `HUONG-DAN.txt`, `USER-GUIDE-en-US.md` |
| Xác minh gói nhận được | `RELEASE-VERIFICATION-v5.0.md`, `VERIFY-RELEASE.cmd`, `VERIFY-DISTRIBUTION.ps1` |
| Thay đổi của phiên bản | `RELEASE-NOTES-v5.0.md`, `LICH-SU-PHIEN-BAN.txt`, `VERSION-HISTORY-en-US.md` |
| Giới hạn đã biết | `KNOWN-LIMITATIONS-v5.0.md` |
| Kiến trúc và hợp đồng mô-đun | `TECHNICAL-ARCHITECTURE-v4.8.md`, `MODULE-CONTRACT-v1.0.md` |
| An toàn và mô hình đe dọa | `THREAT-MODEL-v5.0.md`, `SAFETY-POLICY-v1.0.md`, `SECURITY-HARDENING-v4.8.md` |
| Bằng chứng kiểm thử | `SECURITY-TEST-RESULTS.md`, `AUDIT-SCOPE-v1.md` |
| Nguồn gốc bản dựng | `OFFICIAL-PROVENANCE-v1.json` + `.p7s`, `RELEASE-MANIFEST.json`, `SBOM.cdx.json` |
| Chính sách mã nguồn | `SOURCE-POLICY-v4.9.md`, `README-MA-NGUON.md` |
| Hỗ trợ và báo lỗi | `SUPPORT.md`, `SECURITY.md`, `CONTRIBUTING.md` |

## Ý nghĩa các tài liệu mang tên v4.8/v4.9

Các tệp sau là **baseline lịch sử vẫn còn hiệu lực trong v5.0.0.2**:

- `TECHNICAL-ARCHITECTURE-v4.8.md`: baseline kiến trúc từ v4.8, được mở rộng bởi hợp đồng mô-đun và hồ sơ release v5.0.
- `ENTRY-POINTS-v4.8.md`: baseline điểm vào; danh sách thực tế được kiểm tra lại khi build v5.0.
- `COMPATIBILITY-MATRIX-v4.8.md`: baseline tương thích; kết quả VM của từng release phải đọc riêng trong hồ sơ kiểm thử.
- `OFFLINE-AND-REPORTING-v4.8.md`: baseline Offline/Reporting; các thay đổi về redaction và export trong v5.0 được ghi ở release manifest và release notes.
- `SECURITY-HARDENING-v4.8.md`: baseline hardening PE/runtime; không đồng nghĩa mọi kiểm soát native như CFG đều đã có.
- `SOURCE-POLICY-v4.9.md`: chính sách mã nguồn có kiểm soát bắt đầu từ v4.9 và tiếp tục áp dụng cho v5.0.

Không dùng riêng các baseline trên để tuyên bố một bản v5.0.0.2 đã vượt qua nghiệm thu. Tuyên bố phát hành phải đồng thời khớp `RELEASE-MANIFEST.json`, `SBOM.cdx.json`, provenance có chữ ký và bằng chứng kiểm thử gắn đúng commit/build.

## Thứ tự ưu tiên khi có khác biệt

1. Tệp thực thi và các metadata đã ký/hash trong chính gói phát hành.
2. `RELEASE-MANIFEST.json`, `OFFICIAL-PROVENANCE-v1.json`, `SBOM.cdx.json` của cùng gói.
3. Tài liệu v5.0 và kết quả kiểm thử gắn đúng Build ID.
4. Baseline v4.8/v4.9.
5. Nội dung giới thiệu trên website.

Nếu hai nguồn mâu thuẫn, dừng sử dụng chức năng thay đổi hệ thống và báo lỗi qua kênh chính thức; không tự suy diễn nguồn nào “gần đúng”.

## Trạng thái nghiệm thu

`ManagedSigned/Pilot` không phải `Public Stable`. Kiểm thử cục bộ và kiểm tra tĩnh không thay thế ma trận máy Windows 10/11 sạch. Chỉ nâng trạng thái khi có đủ log độc lập, thông tin hệ điều hành, hash kết quả và người duyệt theo `SECURITY-REVIEW-PROCESS-v1.md`.
