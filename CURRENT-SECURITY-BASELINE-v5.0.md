# VietLicenSure v5.0 — Current Security Baseline

| Thuộc tính | Giá trị |
|---|---|
| AppliesTo | Mã nguồn VietLicenSure v5.0 hiện hành và các artifact được provenance ghim đúng source snapshot |
| Status | Current |
| LastReviewed | 07/10/2026 |
| Kênh ký | Official Self-Signed; không phải public-CA, EV hoặc Microsoft Store |
| Đánh giá độc lập | `NotReviewed` cho đến khi có báo cáo độc lập gắn đúng artifact/source |

## 1. Phạm vi baseline

Tài liệu này là điểm vào ngắn cho trạng thái bảo mật hiện hành của v5.0. Nó không thay thế manifest, provenance, checksum, chữ ký hoặc evidence gắn đúng artifact. Khi thông tin khác nhau, nguồn ưu tiên là:

1. `RELEASE-MANIFEST.json`, `OFFICIAL-PROVENANCE-v1.json` và chữ ký đi kèm đúng gói.
2. `RELEASE-STATUS-v5.0.md` và `RELEASE-VERIFICATION-v5.0.md`.
3. Policy hiện hành được liệt kê bên dưới.
4. Tài liệu trong `docs/archive/v4.x/` chỉ dùng để truy vết lịch sử.

## 2. Kiểm soát hiện hành

- Offline mặc định; không telemetry và không tự upload inventory, key hoặc token.
- Online là hành động tường minh; catalog/update metadata phải qua HTTPS, giới hạn host/kích thước và xác minh chữ ký theo policy.
- Phát hiện kỹ thuật, dấu hiệu can thiệp, entitlement và kết luận tổng hợp được tách riêng; một tín hiệu KMS hoặc tên file đơn lẻ không tự chứng minh vi phạm.
- Mọi thay đổi hệ thống phải có preview, lựa chọn phạm vi, xác nhận riêng, backup khi áp dụng, hậu kiểm và đường rollback/retry.
- Parser/plugin không được thực thi PowerShell hoặc mã tùy ý từ dữ liệu catalog.
- Release phải fail-closed khi artifact, source, QA evidence, manifest, SBOM hoặc provenance không cùng danh tính.

## 3. Giới hạn phải công bố

- Enterprise transport hiện dùng HTTP với envelope AES-256-CBC + HMAC-SHA256; đây không tương đương TLS/mTLS và không nên được mô tả là transport production đã được assurance độc lập.
- Official Self-Signed xác minh tính nhất quán theo signer/hash/timestamp đã công bố, nhưng không tạo public trust như chứng thư public-CA/EV/Store.
- Independent security review vẫn là `NotReviewed`; không được tuyên bố pentest, chứng nhận bảo mật hoặc “0 Critical/High” nếu không có báo cáo tương ứng.
- Static verifier không thay thế runtime test gắn đúng hash trên Windows.

## 4. Tài liệu hiện hành

- `SECURITY.md` — báo lỗi bảo mật và disclosure.
- `THREAT-MODEL-v5.0.md` — mô hình đe dọa.
- `SAFETY-POLICY-v1.0.md` — nguyên tắc fail-closed và remediation.
- `CODE-SIGNING-POLICY-v1.md` và `OFFICIAL-SELF-SIGNED-POLICY-v1.md` — danh tính ký.
- `RELEASE-STATUS-v5.0.md` — trạng thái từng cổng.
- `RELEASE-VERIFICATION-v5.0.md` — quy trình xác minh.
- `MODULE-CONTRACT-v1.0.md` — hợp đồng module/entry point.
- `REPORT-SCHEMA-v1.6.md` — hợp đồng báo cáo.
- `DOCUMENTATION-MAP-v5.0.md` — bản đồ tài liệu và thứ tự ưu tiên.

## 5. Tài liệu lịch sử

Các baseline và hồ sơ v4.8/v4.9 đã được chuyển nguyên nội dung vào `docs/archive/v4.x/`. Chúng không phải bằng chứng rằng artifact v5.0 hiện hành đã vượt một cổng runtime hoặc security review.
