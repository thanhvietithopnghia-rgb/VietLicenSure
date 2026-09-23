# Trạng thái phát hành VietLicenSure v5.0

> **Nguồn sự thật duy nhất (SSOT) về mức sẵn sàng phát hành.** Khi tài liệu khác mô tả khác với trang này, dùng trạng thái tại đây. Đối với tính nguyên vẹn của từng tệp, metadata có chữ ký, manifest và checksum của chính gói vẫn là căn cứ kỹ thuật bắt buộc.

- **Cập nhật trạng thái:** 23/09/2026
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
| Build ID | `5.0-production-20260923` | `OFFICIAL-PROVENANCE-v1.json` |
| SHA-256 của EXE | Xem `RELEASE-MANIFEST.json` và `RELEASE-SHA256SUMS.txt` của chính gói nhận được | Hash thay đổi khi build/ký/timestamp; không sao chép giá trị từ gói khác |
| Source snapshot được provenance khai báo | Xem `OFFICIAL-PROVENANCE-v1.json` của chính gói nhận được | Provenance có chữ ký CMS tách rời và phải khớp manifest |
| Chứng thư ký | Chứng thư tự ký được launcher ghim; SHA-256 `A42B00D863D4770B47F21FFF756545249D58DD59691AD9E05C02048C104F9FC9` | `CONTENT-SIGNING-CERTIFICATE.cer` và provenance |

Các giá trị trên mô tả artifact đang công bố; chúng không tự chứng minh source snapshot và EXE đã được chạy cùng nhau trong Harness4. Nếu bất kỳ giá trị nào thay đổi, phải cập nhật metadata/chữ ký/checksum của gói trước, rồi mới cập nhật bảng này.

## Bằng chứng và cổng nghiệm thu

| Cổng | Trạng thái | Phạm vi và việc còn lại |
|---|---|---|
| Toàn vẹn gói, CMS, Authenticode, manifest, SBOM | Theo hồ sơ phát hành hiện hành | Chạy `VERIFY-RELEASE.cmd` trên chính gói nhận được; kết quả cục bộ của người dùng mới là căn cứ cho bản sao họ đang có. |
| Harness4 ngày 13/09/2026 | **Historical / không dùng để đóng cổng artifact hiện hành** | Kết quả `3/3` nền tảng chỉ gắn với source snapshot lịch sử `291ed82db5f99a36aaf6962a41f09ecdec851320`; Harness4 đó không trực tiếp khởi chạy EXE/UI đóng gói và không được chuyển sang artifact khác. |
| Harness4 đúng source snapshot của EXE | **CONDITIONAL — chỉ đóng khi evidence hiện hành đạt 3/3** | Cổng chỉ có hiệu lực khi `SourceCommit` trong ma trận Harness4 bằng `SourceSnapshotCommit` của provenance đã ký, artifact hash/size/signer/timestamp khớp manifest và cả Windows 10 22H2, Windows 11 24H2, Windows 11 25H2 đều `Passed`. Mọi source/EXE mới đặt lại cổng về PENDING. |
| Runtime EXE/UI trên Windows 10/11 sạch | **Đạt cho gói bàn giao gần nhất; phụ thuộc hash** | Đã kiểm tra EXE đóng gói trên ma trận Windows 10/11, tài khoản giới hạn, Offline và UI thật; mọi build/ký lại phải chạy lại. |
| Audit KMS/Activator và thao tác thay đổi hệ thống | **Đạt ở phạm vi fixture cô lập; Public Stable vẫn HOLD** | Read-only không đổi máy; backup/restore, scope-lock, tamper rejection, hậu kiểm và rollback được kiểm trên VM checkpoint. |
| Rollback, UAC, quyền hạn, hủy và lỗi gián đoạn | **Đạt cho gói bàn giao gần nhất; phụ thuộc hash** | UAC secure desktop được gọi bằng `RunAs`, Esc hủy với mã `1223`, policy không đổi và checkpoint sạch được phục hồi. |
| Accessibility, DPI, High Contrast và screen reader | **Đạt ở phạm vi VM lab; review độc lập vẫn PENDING** | Bàn phím-only, MSAA, DPI 100–200%, High Contrast và ảnh trực quan đã đạt; cần review độc lập trước Public Stable. |
| Đánh giá bảo mật độc lập đúng artifact | **PENDING** | Chưa có biên bản hoàn tất gắn với hash EXE hiện hành. |
| Chứng thư code-signing do CA công cộng cấp | **PENDING** | Artifact hiện dùng chứng thư tự ký được ghim; SmartScreen/Windows có thể vẫn cảnh báo. |

## Quyết định hiện hành

**Tiếp tục `ManagedSigned / Internal Pilot`; giữ `Public Stable` ở trạng thái HOLD.** Harness4 + provenance chỉ đóng cổng snapshot/artifact tương ứng sau khi evidence 3/3 được công bố. Chứng thư miễn phí vẫn là self-signed và đánh giá bảo mật độc lập đúng artifact chưa hoàn tất; hai blocker này không được Harness4 thay thế, nên không quảng bá v5.0 là Public Stable hoặc bật public self-update.

Chỉ gỡ HOLD khi tối thiểu các cổng Harness4 đúng snapshot, runtime artifact, thao tác thay đổi hệ thống/rollback, accessibility và review độc lập có bằng chứng đạt cho cùng artifact; quy trình ký Public Stable cũng phải đáp ứng chính sách code-signing hiện hành.

## Cách cập nhật trang này

1. Cập nhật **Cập nhật trạng thái** và đúng một dòng trong bảng cổng.
2. Ghi rõ artifact SHA-256, source snapshot, ngày chạy, môi trường và đường dẫn bằng chứng; không chỉ ghi “đã test”.
3. Nếu source hoặc EXE thay đổi, đặt lại mọi cổng phụ thuộc về `PENDING` cho tới khi chạy lại.
4. Chỉ đổi `Public Stable: HOLD` sau quyết định phê duyệt có thể truy vết.
5. Các README, website, release notes và roadmap chỉ tóm tắt rồi liên kết về trang này; không sao chép các kết quả QA dễ lỗi thời.
