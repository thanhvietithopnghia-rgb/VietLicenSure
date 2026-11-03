# VietLicenSure v5.0 — đóng gói 20261103-r3 / packaging revision

Đây là bản sửa **đóng gói**, không thay EXE hay mã chạy. EXE hiện hành:
`30B95AB631D4D6E0B6206011BBC24636E6B1824FEFAE1AA52C20A8320516C276` — 940736 bytes.

Chạy trong thư mục Release:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\VERIFY-PACKAGING.ps1

Manifest PACKAGING-CONTEXT.json ký CMS ghim chứng thư, ràng buộc tất cả tệp distribution giữ nguyên và phần bổ sung đóng gói. RELEASE-SHA256SUMS.txt tại Release kiểm chính distribution hiện hành. Khi nhận bộ source riêng, bắt đầu ở README và VERIFY-HANDOFF.ps1 tại gốc bộ bàn giao.

## Bộ source riêng / private source handoff

- `Release/`: bản chạy hiện hành, có verifier và checksum đúng thư mục.
- `CURRENT-RELEASE.json`: danh tính hiện hành, chỉ rõ đường dẫn EXE trong Release.
- `RELEASE-SHA256SUMS.txt` ở gốc: cùng các hash hiện hành, đường dẫn có tiền tố Release/; không phải danh sách hash predecessor.
- `Archive/SourceSnapshot/`: snapshot/bundle nguồn nguyên trạng đã ký; metadata artifact predecessor chỉ là lịch sử, không phải checksum của gói hiện hành.
- `Archive/SourceAsBuilt/`: view input đã dùng cho full verifier, chỉ khác snapshot ở 5 tệp generated được công bố; không phải source commit sản phẩm mới.
- `Evidence/`: QA đúng hash hiện hành. HANDOFF-MANIFEST và chữ ký CMS kiểm cặp release/source/evidence và tập tệp đóng.

Không trộn EXE vào snapshot hoặc lấy RELEASE-SHA256SUMS trong Archive làm lệnh kiểm mặc định. Full source là tài liệu riêng được kiểm soát, không có trong asset công khai.

## Phạm vi xác minh / evidence boundary

Executable, timestamp, provenance and tested implementation are unchanged. Packaging revision is not a new functional build or a new Windows test claim. Windows 11 24H2 startup/dashboard and source regression/live loopback mTLS evidence remain bound to that exact EXE. Windows 10 current-artifact acceptance, packaged report/Enterprise end-to-end, production LAN and independent security review are not established by this packaging correction.

Official Self-Signed, not public-CA/EV/Store trust; SmartScreen may warn. Independent review remains NotReviewed; external validity NotEstablished.
