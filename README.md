# VietLicenSure v5.0

Kho công khai chính thức cho bản phát hành, tài liệu và **một phần mã nguồn không chứa lõi** của VietLicenSure.

## Bản phát hành hiện tại

- Kênh: **Official Self-Signed** (`ManagedSigned`)
- EXE SHA-256: `DBBED41A4FDC10AC9C31A85DEAE9E40DB6860D2D19CC41536C9BB9558862DEFF`
- Source snapshot kiểm thử: `bb64a353f372c67c72c06c250479e761db7208c8`
- Provenance bundle: `73c0fc4775210ec10b3ebb172a29e9067b3f34dc`
- Independent review: `NotReviewed`

Tải bản chính thức tại [GitHub Release v5.0](../../releases/tag/v5.0). Chứng thư tự ký có thể làm Windows SmartScreen cảnh báo trên máy chưa cài trust anchor.

## Partial source

Thư mục [`partial-source`](partial-source/) công bố chọn lọc các thành phần không chứa lõi để cộng đồng kiểm tra:

- chính sách offline và report schema;
- schema dữ liệu công khai;
- verifier report, Pages và quét signing-secret;
- công cụ đồng bộ tài liệu.

Đây là **proprietary source-available**, không phải phần mềm mã nguồn mở. Quyền xem không tự cấp quyền sao chép, sửa đổi, phân phối, tạo sản phẩm phái sinh, thương mại hóa hoặc dùng làm dữ liệu huấn luyện. Xem [chính sách mã nguồn](SOURCE-POLICY-v5.0.md) và [giấy phép partial source](PARTIAL-SOURCE-LICENSE.txt).

Toàn bộ tập công bố được khóa bởi [`PARTIAL-SOURCE-MANIFEST.json`](PARTIAL-SOURCE-MANIFEST.json) và kiểm bằng:

```powershell
pwsh -NoProfile -File .\VERIFY-PARTIAL-SOURCE.ps1
```

## Không được công bố

UI, business logic, detection/remediation, elevated broker, plugin/update internals, build/sign/release pipeline, catalog nội bộ và test harness đầy đủ vẫn thuộc repo riêng tư có kiểm soát.

## Hỗ trợ và bảo mật

- Issues: báo lỗi và đề xuất không chứa dữ liệu nhạy cảm.
- Security advisory: báo lỗ hổng riêng tư qua GitHub Security Advisories.
- Email: `thanhvietit.hopnghia@gmail.com`

Copyright © 2026 Thanh Việt. All rights reserved.
