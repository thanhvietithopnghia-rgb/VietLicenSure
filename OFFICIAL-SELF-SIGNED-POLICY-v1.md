# Chính sách phát hành Official Self-Signed v1

Áp dụng từ ngày **24/09/2026** cho VietLicenSure v5.0 và các bản cập nhật cùng kênh cho đến khi chủ sở hữu công bố thay đổi.

## Quyết định kênh

- Tên kênh công khai: **Official Self-Signed**.
- Trạng thái phân phối: **phát hành chính thức**; không dùng nhãn Pilot hoặc pre-release cho artifact đã vượt đủ cổng của chính sách này.
- Trust mode kỹ thuật trong launcher/manifest: `ManagedSigned`.
- Signer Authenticode là chứng thư tự ký đã ghim; chữ ký phải có RFC 3161 timestamp.
- Bản phát hành không được mô tả là public-CA, EV hoặc Microsoft Store-signed.

## Điều kiện phát hành

1. EXE, source snapshot, provenance CMS, release manifest, SBOM và checksum phải khóa cùng một chuỗi phát hành.
2. SHA-256 của EXE, source snapshot commit, bundle head commit, signer SHA-1/SHA-256 và timestamp phải được công bố.
3. `VERIFY-DISTRIBUTION.ps1`, `VERIFY-RELEASE.ps1` và các bài kiểm thử artifact-bound bắt buộc fail-closed.
4. Trên máy chưa cài trust anchor, SmartScreen hoặc Windows có thể cảnh báo. Người dùng phải đối chiếu SHA-256, signer, timestamp và kết quả verifier trước khi tự quyết định chạy.
5. Không yêu cầu người dùng tắt SmartScreen/Defender, hạ policy hoặc cài chứng thư vào Trusted Root chỉ để làm mất cảnh báo.
6. Khi chuyển sang public-CA, EV hoặc Store-signed, phải tạo snapshot/provenance/artifact mới và cập nhật đồng thời toàn bộ bề mặt công khai.
7. GitHub Release chính thức phải công bố EXE SHA-256, source snapshot commit, bundle head commit, signer tự ký và trạng thái review hiện hành; tag lịch sử không được di chuyển để che chuỗi cũ.

## Review và tuyên bố bảo mật

`Official Self-Signed` là quyết định kênh phân phối của chủ sở hữu; nó không tự biến review chưa thực hiện thành `Passed`. Trạng thái review, Code Scanning, dependency alerts và số finding Critical/High phải được công bố theo bằng chứng thật của từng artifact.
