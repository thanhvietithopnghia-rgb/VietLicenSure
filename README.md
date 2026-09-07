# VietLicenSure v5.0 — Phần mềm Kiểm tra và Quản lý Bản quyền Hệ thống

- **Bản phát hành hiện tại:** VietLicenSure v5.0 · phát hành ngày 06/09/2026
- **Tác giả và phát triển:** Thanh Việt
- **Trang phát hành công khai:** <https://thanhvietithopnghia-rgb.github.io/VietLicenSure/>

Ngày 06/09/2026, v5.0 chính thức đổi tên từ **Tool Kiểm Tra Máy Tính — Công cụ kiểm tra cấu hình máy và bản quyền phần mềm** thành **VietLicenSure — Phần mềm Kiểm tra và Quản lý Bản quyền Hệ thống**. Việc đổi tên không loại bỏ chức năng và giữ nguyên dòng phiên bản v5.0.

## Ý nghĩa tên VietLicenSure

- **Viet:** phần mềm do người Việt phát triển và được thiết kế phù hợp với người dùng Việt Nam.
- **Licen:** rút gọn từ `License`, đại diện cho giấy phép và bản quyền phần mềm.
- **Sure:** rõ ràng, có kiểm chứng và đáng tin cậy trong phạm vi bằng chứng kỹ thuật.

Tên VietLicenSure thể hiện mục tiêu giúp người dùng kiểm tra, xác minh, quản lý và khắc phục tình trạng bản quyền hệ thống theo quy trình an toàn. Phần mềm cung cấp bằng chứng kỹ thuật, không thay thế chứng nhận hoặc kết luận pháp lý về quyền sử dụng.

VietLicenSure v5.0 là bản nâng cấp tiếp theo của v4.9, tập trung nâng cấp vào các phần cốt lõi:

- **Trải nghiệm sử dụng:** khởi động nhanh hơn, giao diện rõ ràng và thích ứng tốt hơn, hỗ trợ Light/Dark và mở thẳng đúng chức năng cần dùng.
- **Kiểm tra và nhận diện:** ba mức quét Quick, Standard và Deep; kiểm tra Windows, Microsoft Office và phần mềm khác; sắp xếp việc cần xem theo mức ưu tiên, hỗ trợ tìm kiếm, lọc và so sánh với lần quét trước.
- **Khắc phục an toàn:** tách riêng Windows, Office và phần mềm khác; bắt buộc xem trước, chạy thử, sao lưu, xác nhận và kiểm tra lại; bổ sung trung tâm sao lưu–khôi phục có kiểm tra toàn vẹn.
- **Báo cáo và hỗ trợ:** báo cáo HTML, PDF, JSON, XML; tạo gói hỗ trợ có che thông tin nhạy cảm và hỗ trợ quản lý nhiều máy.
- **Riêng tư và toàn vẹn:** hoạt động Offline theo mặc định, không tự gửi dữ liệu ra Internet; kiểm tra chữ ký và SHA-256 trước các thao tác quan trọng.

Bản hiện tại dùng chứng thư tự ký được launcher ghim nên Windows vẫn có thể hiện `Unknown publisher` hoặc SmartScreen.

## Tải và bắt đầu

1. Tải trực tiếp [VietLicenSure v5.0.0.1](https://github.com/thanhvietithopnghia-rgb/VietLicenSure/releases/download/v5.0.0.1/VietLicenSure-v5.0.exe) từ tài sản phát hành chính thức.
2. Người đang dùng ProductVersion/FileVersion `5.0.0.0` có thể tải `VietLicenSure-v5.0.exe` và thay tệp cũ; dữ liệu cũ được giữ làm nguồn tương thích/migration.
3. Đối chiếu SHA-256 và chữ ký trước khi chạy. Không tắt Defender hoặc SmartScreen để ép chạy tệp không xác minh được.
4. Giữ Offline nếu chỉ kiểm tra máy cục bộ. Chỉ bật Online khi muốn cập nhật Tool/catalog hoặc dùng chức năng LAN được cho phép.
5. Chỉ chấp nhận UAC khi tên tác vụ đúng với thao tác khắc phục, cập nhật hoặc quản trị mà bạn vừa chọn.

```powershell
Get-FileHash .\VietLicenSure-v5.0.exe -Algorithm SHA256
Get-AuthenticodeSignature .\VietLicenSure-v5.0.exe |
  Format-List Status,StatusMessage,SignerCertificate
```

## Mười chức năng chính

1. Kiểm tra toàn bộ.
2. Cấu hình phần cứng, TPM, Secure Boot và BitLocker.
3. Bản quyền Windows.
4. Bản quyền Microsoft Office.
5. Phần mềm và dấu hiệu can thiệp.
6. Khắc phục KMS/Activator có Dry Run, backup và hậu kiểm; mục Khắc phục có năm chức năng riêng gồm Windows, Microsoft Office, phần mềm khác, Khôi phục key OEM và Quản lý giấy phép hợp lệ. Ba chức năng đầu mở thẳng đúng màn hình, không qua menu chung.
7. Khôi phục key OEM khi edition phù hợp.
8. Quản lý giấy phép hợp lệ cục bộ hoặc trong LAN được cho phép.
9. Kiểm tra chuyên sâu dành cho quản trị viên.
10. Trung tâm báo cáo bảo đảm, timeline, plugin và tài liệu.

## Cách hiểu kết quả khắc phục

- `Pending` / `Running`: đang chờ hoặc đang xử lý.
- `VerifiedClean`: hậu kiểm đã xác nhận điều kiện làm sạch của quy tắc; không đồng nghĩa đã có giấy phép hợp lệ.
- `ApprovedInternalKMS`: KMS tổ chức đã được người quản trị xác nhận và được giữ nguyên.
- `RetryableFailure`: lần xử lý chưa đạt; có thể sửa nguyên nhân và thử lại.
- `BlockedByPolicy`: chính sách quản trị đang áp dụng; Tool không âm thầm xóa policy của tổ chức.
- `NeedsOfficeRepair`: edition/tệp/trạng thái Office cần Repair, cấu hình lại hoặc cài từ nguồn chính thức.

Nếu catalog chưa đủ bằng chứng, Tool giữ trạng thái `Chưa xác minh`. Nếu bản cài Volume, file đã bị thay đổi hoặc policy tái áp dụng cấu hình, Tool có thể yêu cầu Repair/cài lại thay vì cố xử lý nguy hiểm.

## Báo cáo và quyền riêng tư

Báo cáo HTML/PDF/JSON/XML được tạo cục bộ. Bản chia sẻ mặc định che định danh phần cứng; bản `FullInternal` chỉ dùng trong phạm vi quản trị có trách nhiệm. Tool không xuất product key đầy đủ, mật khẩu hoặc dữ liệu đăng nhập. Trước khi gửi báo cáo ra ngoài, vẫn cần đọc lại nội dung và giới hạn người nhận.

## Phát triển cộng đồng và mã nguồn có kiểm soát từ v4.9

Bản thực thi chính thức của Tool tiếp tục **miễn phí cho cộng đồng** cho các mục đích hợp pháp theo điều khoản đi kèm. Dự án tiếp nhận báo lỗi, đề xuất, tài liệu, bản dịch, kiểm thử và đóng góp kỹ thuật của cộng đồng. Kể từ v4.9, mã nguồn không còn được công khai miễn phí, không được phát hành theo giấy phép mã nguồn mở và được quản lý theo cơ chế truy cập có kiểm soát.

Thay đổi này được đưa ra sau khi tác giả ghi nhận nội dung, giao diện, mô tả và thành quả phát triển của Tool bị sao chép gần như nguyên trạng, đổi tên/đổi thương hiệu thành sản phẩm cá nhân mà không xin phép hoặc ghi nhận tác giả. Nội dung này **không khẳng định mã nguồn hoặc backend đã bị lấy** khi chưa có bằng chứng kỹ thuật xác nhận.

Người muốn tham khảo, học tập, nghiên cứu, đánh giá bảo mật hoặc đóng góp mã phải xin ý kiến và nhận chấp thuận bằng văn bản của tác giả trước khi truy cập. Quyền xem không tự cấp quyền sao chép, chia sẻ, sửa đổi, tạo sản phẩm phái sinh, đóng gói, thương mại hóa, dùng làm dữ liệu huấn luyện, đổi thương hiệu hoặc xóa ghi nhận tác giả. Chính sách áp dụng cho mã nguồn từ v4.9 trở đi và không thay đổi hồi tố điều khoản của các phiên bản cũ.

Đọc [Chính sách phát triển cộng đồng và mã nguồn có kiểm soát](SOURCE-POLICY-v4.9.md), [Thông báo bản quyền và điều khoản sử dụng](LICENSE-NOTICE.txt) và [Hướng dẫn tiếp cận mã nguồn](README-MA-NGUON.md).

## Tài liệu

- [Bắt đầu nhanh v5.0](QUICK-START-v5.0.md)
- [Giới hạn đã biết v5.0](KNOWN-LIMITATIONS-v5.0.md)
- [Vệ sinh phát hành và tài liệu v5.0](RELEASE-HYGIENE-v5.0.md)
- [Hướng dẫn sử dụng tiếng Việt](HUONG-DAN.txt)
- [English user guide](USER-GUIDE-en-US.md)
- [Lịch sử phiên bản](LICH-SU-PHIEN-BAN.txt)
- [English version history](VERSION-HISTORY-en-US.md)
- [Release notes v5.0](RELEASE-NOTES-v5.0.md)
- [Release notes v4.9](RELEASE-NOTES-v4.9.md)
- [Chính sách an toàn](SAFETY-POLICY-v1.0.md)
- [Report schema và artifact quản trị](REPORT-SCHEMA-v1.5.md)
- [Chính sách trình xem báo cáo/fallback](REPORT-VIEWER-POLICY-v1.md)
- [Chính sách báo cáo bảo mật](SECURITY.md)
- [Phạm vi audit và quy trình review](AUDIT-SCOPE-v1.md)
- [Chính sách code-signing](CODE-SIGNING-POLICY-v1.md)
- [Lộ trình/tiến độ nhánh v5.0](ROADMAP-v5.0.md)
- [Kết quả kiểm thử bảo mật và tương thích](SECURITY-TEST-RESULTS.md)

## Nguồn chính thức và hỗ trợ

- Kho phát hành: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure>
- Tải EXE v5.0.0.1: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/releases/download/v5.0.0.1/VietLicenSure-v5.0.exe>
- Zalo: `0978 005 017`
- Email: `thanhvietit.hopnghia@gmail.com`

Chỉ chia sẻ đường dẫn tải chính thức; không đăng lại, đóng gói, thu phí, đổi thương hiệu hoặc tuyên bố Tool là sản phẩm của người khác khi chưa có chấp thuận bằng văn bản.

© 2026 Thanh Việt. Mọi quyền được bảo lưu.
