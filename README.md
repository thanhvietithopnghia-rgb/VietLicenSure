# VietLicenSure v5.0

Kho công khai chính thức cho bản phát hành, tài liệu và **một phần mã nguồn không chứa lõi** của VietLicenSure.

## Bản phát hành hiện tại

- Kênh: **Official Self-Signed** (`ManagedSigned`)
- EXE SHA-256: `45AE52FF0BC68D1EA783DC5C4E4C64666DC02C1FA584658773CB162A82898AFC`
- Source snapshot kiểm thử: `58981b21c56df2f2abb320dd4a7d82f0786277a0`
- Provenance bundle: `f813e872779aec15fc419c6aa845e02e106f8ae2`
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

## Maintenance correction — 2026-11-03

Report export failures preserve previous packages; Windows/Office reconciliation now carries exact structured product identities. Missing/unsupported identities remain NeedsReview. Version remains v5.0; OEM changes are out of scope.
