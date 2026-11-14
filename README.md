# VietLicenSure v5.0

Kho công khai chính thức cho bản phát hành, tài liệu và **một phần mã nguồn không chứa lõi** của VietLicenSure.

## Bản phát hành hiện tại

- Kênh: **Official Self-Signed** (`OfficialSelfSigned`)
- EXE SHA-256: `E4E29829939125F40043897070149C44D3F60758464CA9D22DC5C25F85C8D8EE`
- Source snapshot kiểm thử: `9d52d246356576ad3860d4e6a25531481dc33728`
- Provenance bundle: `53c995b2526c858f7f8c055aaca1772321c457a2`
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

## Report integrity maintenance — 2026-11-03

Report publication and Result Center now verify output integrity. Corrupt/incomplete reports are excluded without deleting files; checksum-unverified legacy reports remain viewable but not fresh. Predecessor source metadata is explicitly Historical, separate from the current distribution SSOT and post-QA handoff.

## Packaging correction — 2026-11-03 (20261103-r3)

Executable, implementation snapshot and existing QA are unchanged. The official ZIP adds a pinned-CMS packaging context and VERIFY-PACKAGING.ps1. The private source handoff now opens with current metadata/checksums and VERIFY-HANDOFF; immutable predecessor metadata is isolated under Archive, not the default release-check path. See [packaging instructions](README-PACKAGING-v5.0.md). No Windows 10, packaged Enterprise/report end-to-end, production-LAN or independent-audit claim is added.

## Report integrity maintenance — 2026-11-03

Report publication and Result Center now verify output integrity. Corrupt/incomplete reports are excluded without deleting files; checksum-unverified legacy reports remain viewable but not fresh. Predecessor source metadata is explicitly Historical, separate from the current distribution SSOT and post-QA handoff.

## Functional QA maintenance — 2026-11-04

Artifact-scoped RELEASE-STATUS replaces inherited acceptance claims. ResultCenter has visible integrity status and verified readability; compliance inputs expose bounded reason codes. Packaged ResultCenter synthetic-state cases and isolated disk-full source tests are distinct from scan/export/remediation end-to-end acceptance. See current QA-EVIDENCE and packaging context.
