# Xác minh bản phát hành VietLicenSure v5.0

Áp dụng cho: **v5.0 ManagedSigned/Pilot**
Ngày hồ sơ: **2026-09-08**

## Cách nhanh nhất

Giữ nguyên mọi tệp trong thư mục `phát hành`, sau đó chạy:

```bat
VERIFY-RELEASE.cmd
```

Hoặc từ Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\VERIFY-DISTRIBUTION.ps1
```

Script tự định vị theo thư mục chứa nó, nên có thể chạy từ Desktop, USB hoặc một thư mục làm việc khác. Nó kiểm tra tập tệp đóng, mọi checksum, JSON, bốn chữ ký CMS exact-byte, chứng thư công bố, phiên bản/Build ID, EXE, Authenticode, update manifest và SBOM. Mã thoát `0` là đạt; mã khác `0` là không đạt.

Tham số `-ExecutionPolicy RemoteSigned` chỉ áp dụng cho tiến trình PowerShell kiểm tra đang chạy, không thay đổi execution policy của máy.

## Fingerprint được công bố

Tệp công khai: `CONTENT-SIGNING-CERTIFICATE.cer`

- Subject: `CN=Thanh Viet - Tool Kiem Tra v4.9 (Self-Signed Code Signing)`
- SHA-1 thumbprint: `ABE70696679B1D8987A2D5B1F6C1C6909D364CEA`
- SHA-256 certificate fingerprint: `A42B00D863D4770B47F21FFF756545249D58DD59691AD9E05C02048C104F9FC9`
- Thuật toán khóa: RSA; mục đích: Code Signing.

Hai fingerprint phải đồng thời khớp `OFFICIAL-PROVENANCE-v1.json`. Không cài chứng thư vào Trusted Root chỉ để làm mất cảnh báo; việc cài trust root là quyết định quản trị riêng.

## Bốn nội dung CMS bắt buộc

1. `OFFICIAL-PROVENANCE-v1.json` + `.p7s`
2. `software-license-catalog-v1.0.json` + `.p7s`
3. `tool-assistant-knowledge-v1.1.json` + `.p7s`
4. `update-manifest-v1.json` + `.p7s`

CMS ký **byte thực của tệp**, không ký đối tượng JSON sau khi parse. Không mở rồi lưu lại, đổi encoding, thêm BOM hoặc chuyển CRLF/LF trước khi kiểm tra.

Windows PowerShell kiểm tra bằng `System.Security.Cryptography.Pkcs.SignedCms` trong `VERIFY-DISTRIBUTION.ps1`. Nếu dùng OpenSSL, phải giữ chế độ binary:

```text
openssl cms -verify -binary -inform DER -in OFFICIAL-PROVENANCE-v1.json.p7s -content OFFICIAL-PROVENANCE-v1.json -noverify -out NUL
```

Thay cặp tệp cho ba chữ ký còn lại. `-noverify` chỉ bỏ xây dựng trust chain; nó **không** bỏ kiểm tra chữ ký mật mã. Sau đó vẫn phải đối chiếu signer với `CONTENT-SIGNING-CERTIFICATE.cer` và fingerprint đã công bố.

Một lỗi `bad signature` đồng thời với việc checksum tệp đúng thường cho thấy công cụ đã đổi line ending/chế độ text. Bộ xác minh chính thức luôn đọc `ReadAllBytes` và không chuẩn hóa nội dung.

## Kiểm tra thủ công EXE

```powershell
$exe = '.\VietLicenSure-v5.0.exe'
Get-FileHash -LiteralPath $exe -Algorithm SHA256
Get-AuthenticodeSignature -FilePath $exe |
  Format-List Status,StatusMessage,SignerCertificate,TimeStamperCertificate
```

Hash phải khớp đồng thời `RELEASE-SHA256SUMS.txt`, artifact trong `RELEASE-MANIFEST.json`, component trong `SBOM.cdx.json` và `DownloadSha256` trong `update-manifest-v1.json`.

## Quy tắc quyết định Authenticode

| Kết quả | Xử lý |
|---|---|
| `Valid`, signer và timestamp đúng | Đạt |
| `UnknownError`/không xây được trust chain trên máy mới | Chỉ là cảnh báo ở kênh ManagedSigned khi EXE không `HashMismatch`, signer khớp cả SHA-1/SHA-256 đã ghim và timestamp tồn tại |
| `HashMismatch`, `NotSigned`, sai signer hoặc thiếu timestamp | Không đạt |
| Revocation/chain không xác định khi Offline | Không tự coi là Valid; ghi cảnh báo và kiểm tra lại trên máy/kênh mạng quản trị |
| Chứng thư CMS hết hạn | Vẫn kiểm tra được tính nguyên vẹn mật mã, nhưng phải đối chiếu ngày build; không dùng để ký bản mới |

Authenticode của EXE có RFC3161 timestamp. Bốn detached CMS hiện không có timestamp authority riêng; chúng dựa vào exact-byte signature, pinning và hồ sơ Build ID/source snapshot.

## Kiểm tra gói bàn giao hai thư mục

Tại thư mục gốc chứa `phát hành` và `mã nguồn`, chạy:

```bat
VERIFY-HANDOFF.cmd
```

Ba manifest chuẩn hóa có vai trò:

- `release-files.sha256`: toàn bộ tệp dưới `phát hành`;
- `source-files.sha256`: toàn bộ tệp dưới `mã nguồn`;
- `package-files.sha256`: toàn bộ gói, trừ chính manifest để tránh tham chiếu vòng.

Đường dẫn trong ba manifest là tương đối với thư mục gốc. Không cần đổi thư mục hiện hành trước khi chạy.

## Phạm vi khẳng định

Kết quả đạt chứng minh các tệp nhận được khớp nhau và đúng signer/pin trong hồ sơ. Nó không chứng minh quyền sở hữu giấy phép phần mềm, không thay thế kiểm thử runtime Windows 10/11 sạch và không tự nâng `ManagedSigned/Pilot` thành `Public Stable`.
