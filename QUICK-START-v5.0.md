# Bắt đầu nhanh với VietLicenSure v5.0

**Tên đầy đủ:** VietLicenSure — Phần mềm Kiểm tra và Quản lý Bản quyền Hệ thống
**Phiên bản kỹ thuật:** `5.0.0.1`
**Ngày phát hành:** `06/09/2026`
**Kênh:** `ManagedSigned/Pilot` — chưa mang nhãn `Public Stable`

## 1. Xác minh trước khi chạy

Chỉ tải từ <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/releases/latest>, sau đó đối chiếu với `RELEASE-SHA256SUMS.txt`:

```powershell
Get-FileHash .\VietLicenSure-v5.0.exe -Algorithm SHA256
Get-AuthenticodeSignature .\VietLicenSure-v5.0.exe |
  Format-List Status,StatusMessage,SignerCertificate,TimeStamperCertificate
```

Chứng thư hiện tại là chứng thư tự ký được launcher ghim. `Status = Valid` và timestamp không đồng nghĩa Windows sẽ hiển thị nhà phát hành công khai; SmartScreen vẫn có thể cảnh báo.

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

Báo cáo được lưu cục bộ trong `Desktop\BaoCao-VietLicenSure`. Bản chia sẻ mặc định che định danh; vẫn cần đọc lại trước khi gửi ra ngoài. Trợ lý tích hợp tra cứu Offline toàn bộ hướng dẫn, lịch sử từ v1.0.0 đến v5.0.0.1 và cách dùng mọi chức năng đã được tài liệu hóa.

Đọc thêm: `HUONG-DAN.txt`, `KNOWN-LIMITATIONS-v5.0.md`, `RELEASE-NOTES-v5.0.md` và `LICH-SU-PHIEN-BAN.txt`.
