# Câu hỏi thường gặp cho người dùng lần đầu — VietLicenSure v5.0

Tài liệu này dành cho người lần đầu tải và chạy VietLicenSure. Trạng thái phát hành hiện hành được duy trì tại `RELEASE-STATUS-v5.0.md`; hướng dẫn xác minh chi tiết nằm trong `RELEASE-VERIFICATION-v5.0.md`.

## SmartScreen hiện cảnh báo thì làm gì?

Không tắt SmartScreen, Microsoft Defender hoặc thêm ngoại lệ chỉ để ép chạy tệp.

1. Kiểm tra tệp được tải từ trang Releases chính thức: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/releases/tag/v5.0>.
2. So sánh SHA-256 của EXE với `RELEASE-STATUS-v5.0.md` và checksum trong chính gói:

   ```powershell
   Get-FileHash .\VietLicenSure-v5.0.exe -Algorithm SHA256
   ```

3. Kiểm tra Authenticode, signer và timestamp:

   ```powershell
   Get-AuthenticodeSignature .\VietLicenSure-v5.0.exe |
     Format-List Status,StatusMessage,SignerCertificate,TimeStamperCertificate
   ```

4. Nếu có gói đầy đủ, chạy `VERIFY-RELEASE.cmd`; yêu cầu kết quả `0 lỗi`. Quét tệp bằng Microsoft Defender.
5. **Dừng lại và tải lại/báo lỗi** nếu hash sai, `HashMismatch`, `NotSigned`, signer không khớp, thiếu timestamp hoặc CMS lỗi.

Bản v5.0 hiện ở kênh `ManagedSigned / Internal Pilot` và dùng chứng thư tự ký được launcher ghim, nên một máy mới vẫn có thể hiện `Unknown publisher` hoặc SmartScreen dù tệp không bị sửa. Chỉ sau khi mọi bước xác minh đều đạt, trên máy cá nhân không bị quản trị, việc chọn **More info → Run anyway** là quyết định có chủ đích của người dùng. Nếu không có tùy chọn đó hoặc máy thuộc cơ quan/doanh nghiệp, hãy dừng và liên hệ quản trị viên; không thay đổi policy hay cài chứng thư vào Trusted Root chỉ để bỏ cảnh báo.

## Lần đầu nên chọn chức năng nào?

Giữ **Offline**, mở bằng tài khoản thường và chọn **Kiểm tra toàn bộ**. Đọc thẻ tổng quan trước, sau đó mở bằng chứng chi tiết. Chỉ bật Online khi chủ động cập nhật catalog/tri thức hoặc dùng chức năng LAN đã được tổ chức cho phép.

## Vì sao ứng dụng hỏi UAC?

Kiểm tra thông thường không cần quyền Administrator. UAC chỉ nên xuất hiện khi bạn vừa chọn tác vụ cần đọc toàn máy, khắc phục, cập nhật hoặc quản trị. Hủy UAC nếu tên tác vụ không khớp thao tác vừa chọn; không chạy toàn bộ ứng dụng bằng Administrator theo thói quen.

## Một cảnh báo có nghĩa phần mềm là crack không?

Không. VietLicenSure dùng thuật toán đối chiếu nhiều nguồn và quy tắc bằng chứng. `Chưa xác minh`, `Nghi vấn` và `Crack đã xác nhận` là các mức khác nhau. Dấu vết còn sót, phần mềm portable, dữ liệu Registry thiếu, KMS nội bộ hoặc nguồn quét bị giới hạn có thể cần kiểm tra thủ công; không gỡ phần mềm chỉ vì một tên tệp hay một cảnh báo đơn lẻ.

## Vì sao UniKey hoặc ứng dụng portable không xuất hiện?

Ứng dụng portable thường không có bản ghi cài đặt trong Registry và có thể nằm ngoài vùng quét. Hãy kiểm tra đường dẫn thực tế, shortcut và chọn vùng quét phù hợp. Việc không xuất hiện không chứng minh ứng dụng đã bị gỡ hoặc không tồn tại.

## Cảnh báo KMS có luôn là vi phạm không?

Không. KMS nội bộ được tổ chức ủy quyền có thể hợp lệ. Không xác nhận một máy chủ KMS chỉ dựa trên tên hoặc địa chỉ; hãy đối chiếu với quản trị viên, hợp đồng cấp phép và danh sách máy chủ được tổ chức phê duyệt. KMS công cộng/không rõ nguồn gốc cần được giữ ở trạng thái cần xem xét.

## Lỗi PowerShell hoặc thiếu quyền nên xử lý thế nào?

Đọc tên nguồn dữ liệu bị lỗi và thử lại bằng quyền phù hợp. Execution Policy, AppLocker/WDAC, dịch vụ Windows, file lock hoặc policy doanh nghiệp có thể làm kết quả chưa đầy đủ. Không hạ chính sách bảo mật toàn máy; trên máy được quản trị, gửi support bundle đã che định danh cho quản trị viên.

## Có nên bấm Khắc phục ngay không?

Không nên. Hãy đọc bằng chứng, chạy **Preview/Dry Run**, tạo và kiểm tra backup, xác nhận đúng mục tiêu rồi mới thực hiện. Chỉ coi hoàn tất khi hậu kiểm đạt. `VerifiedClean` là kết quả kỹ thuật trong phạm vi đã quét, không phải chứng nhận quyền sở hữu giấy phép.

## Cần gửi gì khi báo lỗi?

Gửi phiên bản, bước tái hiện, ảnh chụp cảnh báo và support bundle **Redacted**. Không đăng product key đầy đủ, serial/UUID chưa che, dữ liệu đăng nhập hoặc thông tin nội bộ. Dùng [GitHub Issues](https://github.com/thanhvietithopnghia-rgb/VietLicenSure/issues/new/choose) cho lỗi thông thường và [Private Security Advisory](https://github.com/thanhvietithopnghia-rgb/VietLicenSure/security/advisories/new) cho vấn đề bảo mật.
