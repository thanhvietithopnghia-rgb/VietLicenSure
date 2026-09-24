# Bản đồ tài liệu — VietLicenSure v5.0

- **Phiên bản áp dụng:** `v5.0`
- **Kênh:** `Official Self-Signed`
- **Trạng thái:** phát hành chính thức bằng chứng thư tự ký; trust mode kỹ thuật `ManagedSigned`
- **Nguồn sự thật về trạng thái:** `RELEASE-STATUS-v5.0.md`

Trang này là mục lục chuẩn. Tên hiển thị dùng thống nhất trong README, website và gói bàn giao; hậu tố v4.8/v4.9 trên một số tệp chỉ mốc hình thành tài liệu, không phải phiên bản của EXE v5.0.

## Tài liệu hiện hành nên đọc trước

| Nhu cầu | Tên tài liệu chuẩn | Tệp |
|---|---|---|
| Trạng thái phát hành và cổng nghiệm thu | **Trạng thái phát hành v5.0** | `RELEASE-STATUS-v5.0.md` |
| Dùng trong vài phút | **Bắt đầu nhanh với VietLicenSure v5.0** | `QUICK-START-v5.0.md` |
| Câu hỏi lần đầu, SmartScreen và UAC | **Câu hỏi thường gặp cho người dùng lần đầu / First-run FAQ — VietLicenSure v5.0** | `FAQ-NGUOI-DUNG-MOI-v5.0.md`, `FIRST-RUN-FAQ-v5.0.md` |
| Hướng dẫn đầy đủ bằng tiếng Việt | **Hướng dẫn sử dụng VietLicenSure** | `HUONG-DAN.txt` |
| Hướng dẫn đầy đủ bằng tiếng Anh | **VietLicenSure User Guide** | `USER-GUIDE-en-US.md` |
| Xác minh tệp/gói nhận được | **Xác minh bản phát hành v5.0** | `RELEASE-VERIFICATION-v5.0.md` |
| Thay đổi của phiên bản | **Ghi chú phát hành v5.0** | `RELEASE-NOTES-v5.0.md` |
| Giới hạn sản phẩm | **Giới hạn đã biết v5.0** | `KNOWN-LIMITATIONS-v5.0.md` |
| Lịch sử phiên bản Việt/Anh | **Lịch sử phiên bản** | `LICH-SU-PHIEN-BAN.txt`, `VERSION-HISTORY-en-US.md` |
| An toàn và mô hình đe dọa | **Chính sách an toàn**, **Mô hình đe dọa v5.0** | `SAFETY-POLICY-v1.0.md`, `THREAT-MODEL-v5.0.md` |
| Nguồn gốc bản dựng | Metadata có chữ ký và manifest của gói | `OFFICIAL-PROVENANCE-v1.json` + `.p7s`, `RELEASE-MANIFEST.json`, `SBOM.cdx.json` |
| Chính sách mã nguồn | **Chính sách mã nguồn có kiểm soát từ v4.9** | `SOURCE-POLICY-v4.9.md`, `README-MA-NGUON.md` |
| Hỗ trợ và báo lỗi | **Hỗ trợ**, **Báo cáo bảo mật**, **Đóng góp** | `SUPPORT.md`, `SECURITY.md`, `CONTRIBUTING.md` |

## Vòng đời tài liệu

- **Hiện hành:** tài liệu v5.0 trong bảng trên; được cập nhật cho hành vi và trạng thái hiện tại.
- **Baseline hỗ trợ:** hợp đồng kỹ thuật hình thành ở v4.8/v4.9 và vẫn được v5.0 kế thừa; chỉ đọc cùng tài liệu v5.0.
- **Lịch sử:** release notes/lịch sử của bản cũ; giữ để truy vết, không dùng làm hướng dẫn vận hành hiện tại.
- **Thay thế:** nội dung có tài liệu hiện hành mới hơn; tệp cũ chỉ giữ một chỉ dẫn tới tài liệu thay thế nếu không còn giá trị truy vết chi tiết.

Không xóa tài liệu legacy chỉ để làm gọn kho. Gắn thông báo vòng đời ở đầu tệp và trỏ về bản đồ này; tránh sao chép lại trạng thái QA, checksum hoặc hướng dẫn vận hành dễ lỗi thời.

## Tài liệu legacy và điểm thay thế

| Tệp legacy | Vòng đời | Dùng thế nào trong v5.0 |
|---|---|---|
| `TECHNICAL-ARCHITECTURE-v4.8.md` | Baseline hỗ trợ | Kiến trúc nền; đọc thêm `MODULE-CONTRACT-v1.0.md` và hồ sơ v5.0. |
| `ENTRY-POINTS-v4.8.md` | Baseline hỗ trợ | Điểm vào lịch sử; danh sách thực tế phải lấy từ gói/build hiện hành. |
| `COMPATIBILITY-MATRIX-v4.8.md` | Baseline hỗ trợ | Tiêu chí tương thích nền; kết quả nghiệm thu hiện tại chỉ xem trong `RELEASE-STATUS-v5.0.md`. |
| `OFFLINE-AND-REPORTING-v4.8.md` | Baseline hỗ trợ | Nguyên tắc Offline/reporting; hành vi người dùng xem `HUONG-DAN.txt`. |
| `SECURITY-HARDENING-v4.8.md` | Baseline hỗ trợ | Hardening nền; không dùng riêng để tuyên bố v5.0 đã đạt. |
| `DANH-GIA-VA-NANG-CAP-v4.8.md` | Lịch sử | Đánh giá tại mốc v4.8; roadmap hiện hành nằm trong `RELEASE-STATUS-v5.0.md` và `ROADMAP-v5.0.md`. |
| `RELEASE-NOTES-v4.9.md` | Lịch sử | Chỉ dùng truy vết thay đổi v4.9; xem `RELEASE-NOTES-v5.0.md` cho bản hiện tại. |
| `SOURCE-POLICY-v4.9.md` | Baseline hỗ trợ | Chính sách bắt đầu từ v4.9 và tiếp tục áp dụng cho v5.0 cho tới thông báo chính thức mới. |

Thông báo chuẩn ở đầu tài liệu legacy:

> **Trạng thái tài liệu:** Baseline/lịch sử, không phải hồ sơ nghiệm thu v5.0. Xem `DOCUMENTATION-MAP-v5.0.md` để tìm tài liệu hiện hành và `RELEASE-STATUS-v5.0.md` để xem trạng thái phát hành.

## Thứ tự ưu tiên khi có khác biệt

1. Byte thực của artifact và metadata/chữ ký/checksum trong chính gói phát hành.
2. `RELEASE-MANIFEST.json`, provenance và SBOM của cùng gói.
3. `RELEASE-STATUS-v5.0.md` cho trạng thái nghiệm thu và cổng phát hành.
4. Tài liệu vận hành v5.0 gắn đúng Build ID/artifact.
5. Baseline v4.8/v4.9.
6. Nội dung giới thiệu trên website và hồ sơ lịch sử.

Nếu các nguồn mâu thuẫn, dừng chức năng thay đổi hệ thống và báo lỗi qua kênh chính thức. Không chọn nguồn “gần đúng” và không tự suy diễn Official Self-Signed thành public-CA/EV/Store-signed.

## Quy tắc duy trì

1. Mỗi chủ đề chỉ có một tài liệu hiện hành chính; tài liệu khác tóm tắt và liên kết.
2. Mọi kết quả QA mới cập nhật trước vào `RELEASE-STATUS-v5.0.md` rồi mới thay phần tóm tắt trên website/release notes.
3. Không ghi kết quả Harness4 mới nếu chưa có log gắn đúng source snapshot và hash EXE.
4. Khi đổi tên hiển thị, cập nhật bảng **Tài liệu hiện hành nên đọc trước** và các liên kết; không đổi tên tệp legacy nếu việc đó làm mất truy vết.
