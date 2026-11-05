# VietLicenSure v5.0 — implemented improvements maintenance / packaging 20261105-ui-r7

EXE hiện hành E72D50FD67B4972D2AF65219D7B3A3A5388A6A57E4B1F50F80DD0EA952943FC3 / 985280bytes. Đây là build bảo trì mới; không tái dùng QA của EXE30B95AB6 đời trước. Riêng bước thêm metadata đóng gói không đổi EXE vừa build/ký.

Chạy: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\VERIFY-PACKAGING.ps1

Trong bộ source riêng: bắt đầu từ VERIFY-HANDOFF.ps1 ở gốc. CURRENT-RELEASE và RELEASE-SHA256SUMS ở gốc trỏ Release hiện hành; Archive/SourceSnapshot và Archive/SourceAsBuilt là source/input bất biến, không lấy checksum predecessor trong Archive làm chuẩn EXE mới. Chữ ký CMS ngoài ghim đúng cặp source/release/evidence. Full source giữ riêng, không phải public asset.

Phạm vi nghiệm thu theo QA-EVIDENCE gắn đúng hash: chỉ những ca thực sự PASS. Source verifier/disk-full không đồng nghĩa scan-to-export qua UI. Windows10current-artifact, packaged remediation/update/Enterprise E2E, LANproduction và audit độc lập chưa được tự đóng. RELEASE-STATUS điều phối gate theo receipt, không kế thừa tuyên bố đời trước.

Official Self-Signed / OfficialSelfSigned không phải publicCA/EV/Store; SmartScreen có thể cảnh báo. Independent review NotReviewed; external validity NotEstablished.
