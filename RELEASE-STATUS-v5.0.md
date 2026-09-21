# Trạng thái phát hành VietLicenSure v5.0

> **Nguồn sự thật duy nhất (SSOT) về mức sẵn sàng phát hành.** Khi tài liệu khác mô tả khác với trang này, dùng trạng thái tại đây. Đối với tính nguyên vẹn của từng tệp, metadata có chữ ký, manifest và checksum của chính gói vẫn là căn cứ kỹ thuật bắt buộc.

- **Cập nhật trạng thái:** 15/09/2026
- **Phiên bản:** `v5.0`
- **Kênh kỹ thuật:** `ManagedSigned`
- **Giai đoạn triển khai:** `Internal Pilot`
- **Tên gọi rút gọn cũ trong một số màn hình/tài liệu:** `ManagedSigned/Pilot`
- **Public Stable:** **HOLD — chưa được phê duyệt**

`ManagedSigned / Internal Pilot` không đồng nghĩa với `Public Stable`. Không suy ra trạng thái phát hành rộng chỉ từ việc checksum, chữ ký hoặc một bộ verifier đạt.

## Danh tính artifact đang công bố

| Trường | Giá trị đang được hồ sơ phát hành khai báo | Căn cứ |
|---|---|---|
| Tệp thực thi | `VietLicenSure-v5.0.exe` | Release v5.0 |
| Build ID | `5.0-production-20260908` | `OFFICIAL-PROVENANCE-v1.json` |
| SHA-256 của EXE | `ED48460205656A4BBCF2DE2E66F4E567F4EF2AAC4A040E4EB9CFDC988917D5C7` | `update-manifest-v1.json` và hồ sơ checksum của gói |
| Source snapshot được provenance khai báo | `4a4ceaf5ce4dac52a8169f23777ed58339d3a8d4` | `OFFICIAL-PROVENANCE-v1.json` có chữ ký tách rời |
| Chứng thư ký | Chứng thư tự ký được launcher ghim; SHA-256 `A42B00D863D4770B47F21FFF756545249D58DD59691AD9E05C02048C104F9FC9` | `CONTENT-SIGNING-CERTIFICATE.cer` và provenance |

Các giá trị trên mô tả artifact đang công bố; chúng không tự chứng minh source snapshot và EXE đã được chạy cùng nhau trong Harness4. Nếu bất kỳ giá trị nào thay đổi, phải cập nhật metadata/chữ ký/checksum của gói trước, rồi mới cập nhật bảng này.

## Bằng chứng và cổng nghiệm thu

| Cổng | Trạng thái | Phạm vi và việc còn lại |
|---|---|---|
| Toàn vẹn gói, CMS, Authenticode, manifest, SBOM | Theo hồ sơ phát hành hiện hành | Chạy `VERIFY-RELEASE.cmd` trên chính gói nhận được; kết quả cục bộ của người dùng mới là căn cứ cho bản sao họ đang có. |
| Harness4 ngày 13/09/2026 | **Historical / không dùng để đóng cổng artifact hiện hành** | Kết quả đã ghi nhận `3/3` nền tảng ở cấp verifier nhưng gắn với source snapshot `291ed82db5f99a36aaf6962a41f09ecdec851320`, khác snapshot `4a4ceaf5…` mà provenance của EXE đang khai báo; Harness4 đó cũng không trực tiếp khởi chạy EXE/UI đóng gói. |
| Harness4 đúng source snapshot của EXE | **PENDING** | Chạy lại từ snapshot được xác nhận là nguồn của EXE, lưu OS/build, hash artifact, lệnh chạy, log và người duyệt. Chỉ chuyển sang `PASS` sau khi bằng chứng được đưa vào hồ sơ. |
| Runtime EXE/UI trên Windows 10/11 sạch | **PENDING** | Cần chạy chính artifact đóng gói ở tài khoản thường và Administrator, Offline/Online, có/không Office. |
| Audit KMS/Activator và thao tác thay đổi hệ thống | **PENDING** | Cần chứng minh read-only không thay đổi máy; mọi thay đổi có preview, scope-lock, backup, xác nhận, UAC theo nhu cầu và hậu kiểm. |
| Rollback, UAC, quyền hạn, hủy và lỗi gián đoạn | **PENDING** | Cần bằng chứng khôi phục được hoặc fail-safe khi bị từ chối quyền, file lock, mất nguồn, dừng tác vụ hay crash. |
| Accessibility, DPI, High Contrast và screen reader | **PENDING** | Cần ma trận bàn phím-only, 100–200% DPI, nhiều màn hình, High Contrast và screen reader trên máy thật. |
| Đánh giá bảo mật độc lập đúng artifact | **PENDING** | Chưa có biên bản hoàn tất gắn với hash EXE hiện hành. |
| Chứng thư code-signing do CA công cộng cấp | **PENDING** | Artifact hiện dùng chứng thư tự ký được ghim; SmartScreen/Windows có thể vẫn cảnh báo. |

## Quyết định hiện hành

**Tiếp tục `ManagedSigned / Internal Pilot`; giữ `Public Stable` ở trạng thái HOLD.** Chưa quảng bá v5.0 là Public Stable, chưa bật public self-update và chưa dùng kết quả Harness4 của snapshot `291ed82d…` để khẳng định EXE khai báo snapshot `4a4ceaf5…` đã vượt qua Harness4.

Chỉ gỡ HOLD khi tối thiểu các cổng Harness4 đúng snapshot, runtime artifact, thao tác thay đổi hệ thống/rollback, accessibility và review độc lập có bằng chứng đạt cho cùng artifact; quy trình ký Public Stable cũng phải đáp ứng chính sách code-signing hiện hành.

## Cách cập nhật trang này

1. Cập nhật **Cập nhật trạng thái** và đúng một dòng trong bảng cổng.
2. Ghi rõ artifact SHA-256, source snapshot, ngày chạy, môi trường và đường dẫn bằng chứng; không chỉ ghi “đã test”.
3. Nếu source hoặc EXE thay đổi, đặt lại mọi cổng phụ thuộc về `PENDING` cho tới khi chạy lại.
4. Chỉ đổi `Public Stable: HOLD` sau quyết định phê duyệt có thể truy vết.
5. Các README, website, release notes và roadmap chỉ tóm tắt rồi liên kết về trang này; không sao chép các kết quả QA dễ lỗi thời.
