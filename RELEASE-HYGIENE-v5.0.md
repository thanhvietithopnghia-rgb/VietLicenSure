# Vệ sinh phát hành và tài liệu — VietLicenSure v5.0

## Danh tính chuẩn

- Tên ngắn: `VietLicenSure`.
- Tên đầy đủ: `VietLicenSure — Phần mềm Kiểm tra và Quản lý Bản quyền Hệ thống`.
- Phiên bản sản phẩm và phát hành: `v5.0`; ngày phát hành: `08/09/2026`.
- Tệp chạy: `VietLicenSure-v5.0.exe`.
- Kho phát hành: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure>.

Ngày 06/09/2026, v5.0 chính thức đổi tên từ **Tool Kiểm Tra Máy Tính — Công cụ kiểm tra cấu hình máy và bản quyền phần mềm** thành **VietLicenSure — Phần mềm Kiểm tra và Quản lý Bản quyền Hệ thống**. `Viet` thể hiện phần mềm do người Việt phát triển, `Licen` rút gọn từ `License`, còn `Sure` thể hiện mục tiêu kết quả rõ ràng và có kiểm chứng trong phạm vi bằng chứng kỹ thuật.

## Việc đã làm trong gói vệ sinh

- Đồng bộ tên sản phẩm trong launcher, giao diện, báo cáo, tài liệu Việt/Anh, website, manifest cập nhật, provenance, SBOM và script đóng gói.
- Đổi tên các artifact mang thương hiệu hiện hành: EXE, launcher source/manifest, icon, CMD và script đóng gói MSIX.
- Bổ sung Bắt đầu nhanh, Giới hạn đã biết và verifier chống version/date/name drift.
- Giữ riêng gói người dùng với mã nguồn/maintainer; mọi tệp phát hành phải nằm trong `RELEASE-SHA256SUMS.txt`.
- Nhãn phát hành là `ManagedSigned/Pilot`, không dùng `Public Stable` khi các cổng bằng chứng chưa đạt.

## Ngoại lệ legacy bắt buộc

Một số chuỗi tên cũ được giữ có chủ đích và chỉ được phép ở phạm vi sau:

- Đoạn lịch sử mô tả lần đổi tên và tên artifact cũ trong các mốc trước v5.0.
- Đường dẫn dữ liệu, entropy và mutex legacy dùng để đọc/migrate dữ liệu cũ mà không làm mất backup, timeline hoặc cấu hình.
- `PackageIdentityName`, package family và reserved name do Microsoft Partner Center đã cấp. MSIX hiển thị `VietLicenSure`, còn các giá trị identity legacy chỉ phục vụ tương thích Store.
- `RELEASE-NOTES-v4.9.md` là hồ sơ lịch sử nguyên bản, không phải tên sản phẩm hiện hành.

Không được mở rộng ngoại lệ này sang tiêu đề giao diện, báo cáo mới, URL tải, tên EXE hoặc mô tả phát hành hiện tại.

## Tài liệu mang hậu tố cũ

Các tệp `*-v4.8.md` và `SOURCE-POLICY-v4.9.md` giữ tên theo mốc hình thành để truy vết lịch sử. Mỗi tệp có thông báo trạng thái ở đầu trang; nội dung nền vẫn áp dụng cho VietLicenSure v5.0 trừ khi một mục ghi rõ chỉ dành cho phiên bản cũ. Tài liệu phát hành hiện hành là `README.md`, `QUICK-START-v5.0.md`, `KNOWN-LIMITATIONS-v5.0.md`, `RELEASE-NOTES-v5.0.md` và hai tệp lịch sử phiên bản.

## Cổng kiểm tra

Chạy trước mọi build và đóng gói:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\VERIFY-RELEASE-HYGIENE.ps1
```

Verifier phải dừng phát hành nếu tên, URL, phiên bản, ngày, file chính, tài liệu bắt buộc hoặc phạm vi ngoại lệ legacy bị lệch.
