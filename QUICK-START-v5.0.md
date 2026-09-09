# Bắt đầu nhanh với VietLicenSure v5.0

**Tên đầy đủ:** VietLicenSure — Phần mềm Kiểm tra và Quản lý Bản quyền Hệ thống
**Phiên bản:** `v5.0`
**Ngày phát hành:** `08/09/2026`
**Kênh:** `ManagedSigned/Pilot` — chưa mang nhãn `Public Stable`

## 1. Xác minh trước khi chạy

Chỉ tải trực tiếp từ <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/releases/download/v5.0/VietLicenSure-v5.0.exe>. Với gói đầy đủ, giữ nguyên toàn bộ tệp rồi nhấp đúp:

```bat
VERIFY-RELEASE.cmd
```

Kết quả phải là `0 lỗi`. Script tự định vị thư mục phát hành và kiểm tra tập tệp đóng, mọi checksum, JSON, bốn chữ ký CMS exact-byte, chứng thư công bố, phiên bản, Build ID, Authenticode, update manifest và SBOM.

Nếu chỉ có EXE, đối chiếu thủ công với `RELEASE-SHA256SUMS.txt`:

```powershell
Get-FileHash .\VietLicenSure-v5.0.exe -Algorithm SHA256
Get-AuthenticodeSignature .\VietLicenSure-v5.0.exe |
  Format-List Status,StatusMessage,SignerCertificate,TimeStamperCertificate
```

Chứng thư hiện tại là chứng thư tự ký được launcher ghim và được công bố dưới tên `CONTENT-SIGNING-CERTIFICATE.cer`. Fingerprint SHA-1 là `ABE70696679B1D8987A2D5B1F6C1C6909D364CEA`; fingerprint SHA-256 là `A42B00D863D4770B47F21FFF756545249D58DD59691AD9E05C02048C104F9FC9`. `Status = Valid` và timestamp không đồng nghĩa Windows sẽ hiển thị nhà phát hành công khai; SmartScreen vẫn có thể cảnh báo.

Không mở/lưu lại hoặc đổi CRLF/LF của bốn tệp JSON trước khi kiểm tra `.p7s`: CMS ký byte thực của tệp. Xem `RELEASE-VERIFICATION-v5.0.md` để có lệnh PowerShell/OpenSSL chính xác.

## 2. Chọn đúng thao tác

1. Mở `VietLicenSure-v5.0.exe`; phần mềm khởi động ở chế độ Offline.
2. Chọn **Kiểm tra toàn bộ** nếu cần bức tranh tổng quan, hoặc mở trực tiếp một trong mười chức năng chính.
3. Dùng Quick cho kiểm tra nhanh, Standard cho kiểm tra thông thường và Deep khi cần bằng chứng sâu hơn.
4. Đọc thẻ tổng quan trước, sau đó mở HTML/PDF hoặc JSON chi tiết nếu cần đối chiếu.
5. Chỉ bật Online khi chủ động cập nhật manifest/catalog hoặc dùng tính năng LAN được cho phép.

## 3. Trước mọi thao tác khắc phục

- Luôn xem trước và chạy **Dry Run** trước.
- Chọn đúng đối tượng; không xử lý toàn máy khi chỉ có một mục cần xem xét.
- Tạo backup và kiểm tra khả năng khôi phục.
- Chỉ chấp nhận UAC khi tên tác vụ đúng với thao tác vừa chọn.
- Đợi hậu kiểm hoàn tất; `VerifiedClean` không phải chứng nhận pháp lý về quyền sử dụng.

## 4. Báo cáo và hỗ trợ

Báo cáo được lưu cục bộ trong `Desktop\BaoCao-VietLicenSure`. Bản chia sẻ mặc định che định danh; vẫn cần đọc lại trước khi gửi ra ngoài. Trợ lý tích hợp tra cứu Offline toàn bộ hướng dẫn, lịch sử từ v1.0.0 đến v5.0 và cách dùng mọi chức năng đã được tài liệu hóa.

- Báo lỗi: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/issues/new/choose>
- Hỏi đáp và đề xuất: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/discussions>
- Báo cáo bảo mật riêng tư: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/security/advisories/new>
- Email và yêu cầu truy cập mã nguồn: `thanhvietit.hopnghia@gmail.com`

Đọc thêm: `HUONG-DAN.txt`, `KNOWN-LIMITATIONS-v5.0.md`, `RELEASE-NOTES-v5.0.md`, `RELEASE-VERIFICATION-v5.0.md`, `DOCUMENTATION-MAP-v5.0.md` và `LICH-SU-PHIEN-BAN.txt`.
