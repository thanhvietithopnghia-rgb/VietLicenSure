# Kết quả kiểm thử bảo mật và tương thích

Trạng thái: tài liệu sống cho nhánh phát triển v5. Không dùng tài liệu này để tuyên bố một bản phát hành đã được chứng nhận.

## Cổng tự động trong kho mã

- `VERIFY-ENTERPRISE.ps1`: protocol, DPAPI/envelope, pairing, report schema, UI smoke và giới hạn endpoint;
- `VERIFY-ENTERPRISE-GOVERNANCE.ps1`: redaction mặc định, freshness/filter, CSV formula protection, export staging và script MDM/CLI;
- `VERIFY-SAFETY-REGRESSIONS.ps1`: catalog ký số, quyết định fail-closed và broker UAC qua launcher đã biên dịch; fixture xác nhận payload gốc bị sửa sẽ bị chặn trước tiến trình quản trị;
- `VERIFY-AUTHENTICODE.ps1`: Authenticode, EKU, signer/timestamp theo tham số release;
- `.github/workflows/client-vm-matrix.yml`: Windows 10 22H2, Windows 11 nhánh trước và Windows 11 nhánh hiện hành trên runner tự quản được bảo vệ; workflow ghi lại DisplayVersion/build/UBR thực tế.

## Cách đọc kết quả VM

Workflow tạo `client-vm-summary.json`, `client-vm-summary.md` và ba tệp `*.vm-result.json` thô. Summary ghi commit, Windows build, PowerShell, trạng thái từng verifier, test/platform manifest, hash generator, SHA-256 và kích thước từng kết quả VM. `Missing` không phải là `Passed`. Workflow lịch chỉ chạy khi biến kho `ENABLE_CLIENT_VM_MATRIX=true`; chạy thủ công phải bật input và có thể yêu cầu phê duyệt environment `client-vm-validation`.

## Bằng chứng lịch sử của v5.0 — đã được thay thế

Bản v5.0 từng công bố gói kiểm thử ngày 28/08/2026. Tóm tắt bên dưới được đọc từ `client-vm-summary.json` trong gói evidence, không suy diễn từ việc workflow tồn tại. Bằng chứng gắn với commit metadata release `1ed0e46069a5d04522552031263d6ceaa184f354`; source snapshot của provenance là `7fe893963206fa7c1ec01d9e1ee129b33fd154b4`.

| Commit/artifact | Win10 22H2 | Win11 previous | Win11 current | Ngày UTC |
|---|---|---|---|---|
| `1ed0e460...` / Bằng chứng v5.0 | Missing | Missing | Passed — Windows 11 25H2, build 26200.9168, 11 verifier | 28/08/2026 |

Tổng trạng thái của **riêng gói lịch sử ngày 28/08/2026**: `Passed=1`, `Failed=0`, `Missing=2`, `Status=IncompleteOrFailed`. Kết quả này được giữ để truy vết và không còn là trạng thái QA hiện hành. Mọi source snapshot mới phải tạo evidence mới; không được tái sử dụng kết quả của source snapshot khác.

## Bằng chứng Harness4 hiện hành ngày 13/09/2026

Ma trận dưới đây gắn với source snapshot `291ed82db5f99a36aaf6962a41f09ecdec851320`. Summary được tạo lúc `2026-09-13T08:34:51.4970862Z`; ba kết quả thô đã được đối chiếu SHA-256 và kích thước trước khi tổng hợp.

| Platform | Windows thực tế | PowerShell | Canonical | Updater bổ sung | Trạng thái |
|---|---|---|---:|---:|---:|
| `win10-22h2` | Windows 10 Pro 22H2, build 19045.2965 | 5.1.19041.2673 | 11/11 | 1/1 | Passed |
| `win11-previous` | Windows 11 Enterprise LTSC Evaluation 24H2, build 26100.1742 | 5.1.26100.1591 | 11/11 | 1/1 | Passed |
| `win11-current` | Windows 11 Enterprise Evaluation 25H2, build 26200.6584 | 5.1.26100.6584 | 11/11 | 1/1 | Passed |

Tổng trạng thái hiện hành: `Passed=3`, `Failed=0`, `Missing=0`, `Status=Passed`. SHA-256 của ba kết quả thô lần lượt là:

- `win10-22h2`: `05E2640B67E521F7AC784044C35D66422F8CE8C114FD54E3B1F65B7BF7058E4E`;
- `win11-previous`: `ECA7AE174D20D93A5D0311628E21DEDAAE9A348370422155057FDFFD6D1065F0`;
- `win11-current`: `234057E44952E6A1E1A03EF71E126E2F970039A9F488F715DDEA1B773EBE39C5`.

Phạm vi Harness4 là hồi quy mã nguồn, cổng hardening updater và ràng buộc danh tính giữa source, metadata đã ký với EXE đóng gói. Harness4 **không khởi chạy EXE đóng gói**; vì vậy kết quả 3/3 không thay thế kiểm thử có chủ đích đối với EXE/UI, tài khoản thường/admin, có/không Office, accessibility, thiết bị/driver khác biệt hoặc security review độc lập.

Giới hạn: VM tự động không chứng minh không có lỗ hổng; nó chỉ cho bằng chứng hồi quy trên cấu hình đã nêu. Kiểm thử máy thật, accessibility, driver/vendor khác biệt và review thủ công vẫn cần thiết.

## Cổng Public Stable

`BUILD.ps1 -RequireAuthenticode` bắt buộc nhận cả `ClientVmSummaryPath` và `IndependentSecurityReviewPath`. Ba tệp VM thô phải nằm cạnh summary; verifier tính lại SHA-256/kích thước, kiểm tra OS/test trong dữ liệu thô và buộc hash generator khớp source snapshot hiện tại. Cổng từ chối build nếu ma trận không đủ 3/3 Passed, commit không khớp provenance, raw evidence bị sửa, hoặc security review độc lập còn finding Critical/High mở. Tệp attestation mẫu mang trạng thái `NotReviewed` và không thể vượt cổng.

## Bằng chứng cục bộ lịch sử cho gói sửa ngày 08/09/2026

- Source snapshot được provenance ràng buộc: `580f68579e50f09f67ae10db330a316262325c3b`.
- Môi trường chạy: Microsoft Windows 11 Pro 64-bit, phiên bản `10.0.26200`, PowerShell `5.1.26100.9168`.
- Chế độ bản dựng: `ManagedSigned`; Build ID `5.0-production-20260908`.
- Tệp thực thi: `VietLicenSure-v5.0.exe`; SHA-256 được tạo theo từng build ký số và công bố trong `RELEASE-SHA256SUMS.txt`, `RELEASE-MANIFEST.json` cùng `update-manifest-v1.json` của chính gói đó.
- Authenticode: `Valid`; signer thumbprint `ABE70696679B1D8987A2D5B1F6C1C6909D364CEA`; có timestamp DigiCert.
- `VERIFY-DISTRIBUTION.ps1`: `0 lỗi / 0 cảnh báo / 9 mục đạt`; tập đóng gồm 50 tệp; bốn chữ ký CMS được xác minh trên đúng byte tệp JSON.
- Ca âm tính: đổi một ký tự trong `OFFICIAL-PROVENANCE-v1.json` rồi tạo lại checksum; verifier vẫn từ chối với mã thoát `1`, báo CMS không hợp lệ và source snapshot trong SBOM không khớp.
- `VERIFY-RELEASE.ps1`: `0 lỗi / 3 cảnh báo đã biết`; x64/x86, 57 payload, 28 module, schema báo cáo, rollback, cập nhật, catalog, plugin, offline/i18n, enterprise và trợ lý đều đạt.
- Ba cảnh báo đã biết: chứng thư tự ký có thể hiện Unknown publisher trên máy mới; launcher managed IL chưa tuyên bố CFG/load configuration native; máy kiểm tra chưa cài PSScriptAnalyzer nên dùng parser PowerShell tích hợp.

Kết quả ngày 08/09 được giữ làm lịch sử. Ma trận Harness4 ngày 13/09 đã bổ sung đủ ba nền tảng Windows ở cấp verifier, nhưng vẫn **không phải** bằng chứng chạy đầy đủ EXE/UI. Kiểm thử artifact đóng gói với tài khoản thường/admin, có/không Office, Offline/Online, accessibility, UAC, report, update, backup/rollback cùng security review độc lập vẫn phải có evidence riêng trước khi gắn nhãn `Public Stable`.
