# Improvements maintenance — release scope 2026-11-04

Authorized by ca: continue implementation through release. Source at e467d37 and subsequent release metadata. Version remains v5.0; Official Self-Signed, not public-CA/EV/Store; independent review NotReviewed.

This maintenance delivers implemented source improvements in recovery preflight, service/job authorization, source quality and conservative evidence independence, labelled inventory merge, bounded traversal/Office/plugin processing, local asset lifecycle/reference/concurrent writes, semantic report export, installation-linked result diffs and grounded read-only Assistant explanations. Detailed fixtures and limits remain in IMPLEMENTATION-ROADMAP-20261104.md.

ALL21 is not fully accepted: actual license/subscription ground truth, physical asset/durable attachment content, GUI cross-process cooperative cancellation, individual RBAC, crash/distributed transactions, production fleet/LAN scale, independent security audit and wide DPI/accessibility remain unestablished. No claim is inferred from a synthetic fixture or predecessor EXE. Public application self-update remains OFF.

Release gates: clean source and signed provenance, official full build, source regressions on exact checkout, disconnected Windows 11 artifact-bound mTLS/fault tests and packaged VI/EN startup/ResultCenter, visual review and restored baseline, closed checksums/private typed handoff, canonical public assets with fresh downloads/full verifier/Pages. Publish only after all applicable gates pass.

---

# Trạng thái phát hành VietLicenSure v5.0

Nguồn điều phối trạng thái; không thay thế bằng chứng gắn đúng artifact. Ngày cập nhật: 03/11/2026.

Ngày phát hành gốc v5.0: 25/10/2026; không phải ngày nghiệm thu artifact hiện hành.

Kênh công khai **Official Self-Signed**, trust mode **OfficialSelfSigned**. Không phải public-CA/EV/Store; SmartScreen có thể cảnh báo. Public self-update EXE vẫn tắt, triển khai có quản trị hoặc tải thủ công có xác minh.

## Danh tính và quy tắc evidence

Đọc EXE SHA-256/size/signer/timestamp từ RELEASE-MANIFEST.json và checksum của chính distribution; source snapshot từ provenance CMS. CURRENT-RELEASE.json và QA-EVIDENCE.json hậu-QA xác định artifact/receipt đang công bố. Metadata trong Archive snapshot ghi Historical không phải danh tính release hiện hành.

Source snapshot mới chưa thể biết hash EXE sau ký. Mọi gate dưới đây chỉ được đóng bởi receipt cùng hash/source, môi trường, ngày và entry point; không tự chuyển kết quả đời trước sang artifact mới. Packaging-only giữ nguyên runtime bytes được giữ evidence cũ đúng phạm vi, không phải lần chạy mới.

| Gate | Trạng thái trong source trước QA | Phạm vi cần chứng minh |
|---|---|---|
| Distribution/CMS/Authenticode/timestamp/SBOM | PendingCurrentArtifact | Verifier của chính distribution và hash tương ứng |
| Source regression/full release | PendingCurrentArtifact | Receipt nguồn/input build đúng snapshot và output hash |
| Windows 11 packaged startup/dashboard | PendingCurrentArtifact | Tài khoản, locale, offline, screenshot, cleanup ghi trong QA-EVIDENCE |
| Result Center/report UI | PendingCurrentArtifact | Chỉ những thao tác và trạng thái thực sự quan sát được, không suy từ source test |
| Windows 10 / Windows 11 phiên bản khác | NotEstablished | Không suy rộng kết quả một OS sang OS khác; lịch sử không đóng gate hiện hành |
| Remediation/backup/rollback/UAC | NotEstablishedBeyondNamedFixtures | Ghi rõ fixture cô lập, fault, phạm vi và giới hạn phục hồi; không hứa phục hồi entitlement |
| DPI/High Contrast/screen reader | NotEstablishedBeyondNamedCases | Cần từng receipt scale/theme/control; không tuyên bố blanket 100–200% |
| Enterprise HTTPS/mTLS | PendingCurrentArtifactLoopbackOnly | Source/live loopback verifier không chứng minh packaged Enterprise E2E hoặc LAN production |
| LAN production / tải300máy | NotEstablished | Cần pilot, workload, SLO, chứng thư và test concurrency/reconnect riêng |
| Đánh giá bảo mật độc lập | NotReviewed | Chưa có reviewer/report gắn đúng artifact; không tuyên bố 0Critical/High |
| Độ chính xác thực tế độc lập | NotEstablished | Cần ground truth và đo theo tập dữ liệu |

## Quyết định kênh

Chủ sở hữu phê duyệt kênh phát hành chính thức Official Self-Signed. Kênh phân phối không biến gate chưa kiểm thành Passed. Báo cáo hậu-QA chỉ nêu các gate đạt thực tế; gate thiếu phải giữ Pending/NotEstablished. Không công bố full source; partial-source theo allowlist hiện hành.

## Lịch sử

Harness4 và ma trận runtime/DPI/UAC đời trước là Historical khi chưa chứng minh cùng artifact. Loại bỏ các tuyên bố tổng quát “đạt gói gần nhất” vì không đủ định danh để chuyển gate. Không đổi trust class hoặc claim audit nếu thiếu evidence thật.

## Hậu-QA — artifact hiện hành 05/11/2026

EXE `93A745EE00113FCB763A2088ECEDC9DE1A129CBA8031DEB4E9419A6B32EB04CD` / 974528bytes; source `aa52e3c73f2544ae9cb26b68be9d0caf3d034b59`; bundle `30a8f2997ca416aff7dd3a7f64b983aba2c0082f`. Đây là overlay metadata hậu-QA, không phải thay source snapshot đã build. Các bảng nguồn phía trên là trạng thái trước QA; bảng sau và QA-EVIDENCE cùng hash xác định kết quả hiện hành.

| Gate thực sự đã quan sát | Kết quả/phạm vi |
|---|---|
| Official build/full release | PASS8/8,0lỗi/3cảnh báo công bố |
| Distribution/CMS/Authenticode/timestamp | PASS; self-issued UntrustedRoot expected, không publicCA |
| Windows11 24H2 packaged startup/dashboard | PASS AdminLimited/Medium,offline; VI/EN |
| ResultCenter qua EXE | PASS Legacy/Verified/Corrupt/Incomplete, VI/EN; report fixtures giả |
| Report generation fault | PASS source regression và ổ đầy NTFS VHD cô lập thật; bộ cũ giữ nguyên |
| Enterprise HTTPS/mTLS | PASS live loopback verifier trên source nguyên bản, ràng buộc đúng EXE |
| Restore/cleanup | PASS theo checkpoint/probe; VMOff,không mạng,VHDvalid |
| Windows10/current khác, scan-to-export/remediation/update/Enterprise UI E2E, LANproduction, toàn bộ DPI/accessibility | NotEstablished; không suy rộng từ các ca trên |
| Independent review / external validity | NotReviewed / NotEstablished |

Official Self-Signed / OfficialSelfSigned; SmartScreen có thể cảnh báo. Xem QA-EVIDENCE.json và chữ ký bàn giao để kiểm receipt đúng artifact. Không có tuyên bố0Critical/High.
