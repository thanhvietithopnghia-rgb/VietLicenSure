# Giới hạn đã biết — VietLicenSure v5.0

Tài liệu này áp dụng cho bản kỹ thuật `5.0.0.1`, phát hành ngày `06/09/2026` theo kênh `ManagedSigned/Pilot`.

## Tin cậy phát hành

- EXE được ký và có timestamp, nhưng dùng chứng thư tự ký được launcher ghim; Windows có thể hiển thị `Unknown publisher` hoặc cảnh báo SmartScreen.
- Bản này chưa được gọi là `Public Stable`: còn thiếu ma trận máy thật/VM đầy đủ, chứng thư code-signing do CA công cộng cấp và biên bản đánh giá bảo mật độc lập hoàn tất cho đúng artifact.
- Verifier tĩnh và checksum không thay thế kiểm thử runtime, WinVerifyTrust trên máy sạch hoặc pentest độc lập.

## Tương thích và giao diện

- Windows 10/11 là phạm vi pilot ưu tiên. Fallback Windows cũ, nhiều màn hình/DPI, High Contrast, bàn phím-only, screen reader và đổi theme khi đang chạy vẫn cần thêm bằng chứng máy thật.
- EXE là AnyCPU managed; hiệu năng Quick/Standard/Deep phụ thuộc phần cứng, số hồ sơ người dùng, số phần mềm và quyền truy cập.

## Nhận diện và kết luận

- Windows không có một API duy nhất liệt kê 100% phần mềm; ứng dụng portable ngoài vùng quét hoặc metadata bị ẩn có thể cần chỉ đường/quét sâu thủ công.
- `Chưa xác định`, `Chưa xác minh`, `Nghi vấn` và `Crack đã xác nhận` là các mức khác nhau. Kết quả là bằng chứng kỹ thuật, không thay thế hóa đơn, hợp đồng hay kết luận pháp lý.
- Phần mềm không tự suy diễn mốc phiên bản, quyền sử dụng hoặc trạng thái hợp lệ khi thiếu dữ liệu.

## Khắc phục, cập nhật và Enterprise

- Không nên khắc phục trên máy production chưa có backup hoặc snapshot. Hãy kiểm tra Dry Run, cancel, file lock, mất quyền, crash/gián đoạn, rollback và hậu kiểm trên môi trường thử trước khi triển khai rộng.
- Các luồng Cleanup, Update, plugin/catalog và Enterprise pairing có bề mặt rủi ro lớn hơn chế độ quét chỉ đọc; chỉ dùng trong phạm vi quản trị được ủy quyền.
- Gói Microsoft Store vẫn dùng một số định danh legacy do Partner Center cấp. Đây là ngoại lệ tương thích, không phải tên hiển thị hiện hành.

Danh sách cổng còn thiếu trước Public Stable được theo dõi trong `ROADMAP-v5.0.md` và `RELEASE-HYGIENE-v5.0.md`.
