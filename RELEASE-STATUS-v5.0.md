## November 14 XML export fix candidate - new artifact acceptance pending

Build ID 5.0-production-20261114-r1. Fix the real packaged main-report XML failure on NUL/control characters using lossless marked base64-utf16le only when XML 1.0 cannot represent the original UTF-16 code units. Ordinary text and JSON values remain intact; CR/LF XML parsing preserves original line endings. Source regression must reproduce the previous failure and round-trip the fixed output. Previous A72F98BD artifact remains a failed normal-report acceptance candidate; its runtime evidence does not transfer to the new EXE. Official Self-Signed/ManagedSigned, independent NotReviewed, broader acceptance Partial.

## Active review maintenance candidate — 2026-11-13

BuildId `5.0-production-20261113-r1`, v5.0 unchanged. Status: source candidate pending build and artifact-bound QA. Main report cancellation, mutation-stop guard, restore item journals and report-document consistency are in scope. No claim of all-function/fleet/physical OEM acceptance or independent review. New artifact must pass the affected source regressions, signed build, exact-hash packaged QA, fresh public download verification and atomic handoff before publication completion is reported. Older entries below are historical.

---

# Historical source records (not current artifact acceptance)

## Reliability maintenance candidate — 2026-11-08

BuildId `5.0-production-20261108-r1`, public version v5.0, channel Official Self-Signed / technical mode OfficialSelfSigned. This file is a source preparation record, not artifact acceptance. The new EXE and its runtime/distribution/full-release receipts are pending until the closed post-QA evidence is generated.

Source regressions cover restore/service failures, Windows SID boundaries, asset documents and plugin-worker deadline/trust. Mainline source is `d2ca6a13e7985780079ba36050f7ffc16035dc4f`; the final tested snapshot and signed provenance are recorded separately by the release pipeline. No privileged delegated-user broker is enabled. General Enterprise fleet, broad DPI/OS matrices, real license ground truth and independent review remain unestablished. Earlier failed source/VM fixtures are retained rather than relabeled as product PASS.

## Historical: Assistant startup hotfix candidate - 2026-11-06

Fixes the real Shown-event crash caused by using the PowerShell automatic variable input as a captured TextBox reference. Uses a dedicated control variable. Real modal open/send/suggestion/clear/resize/close regressions pass in VI/EN and Light/Dark. Candidate only: new executable, packaged UI acceptance and publication are pending; predecessor QA is not reused for changed bytes.

# UI/Assistant maintenance — 2026-11-05; exact-artifact release gates apply

Nội dung hiện hành: **05/11/2026**.



Authorized by ca: continue implementation through release. Source identity is bound by signed provenance and the exact-artifact release record. Version remains v5.0; Official Self-Signed, not public-CA/EV/Store; independent review NotReviewed.



This maintenance delivers implemented source improvements in recovery preflight, service/job authorization, source quality and conservative evidence independence, labelled inventory merge, bounded traversal/Office/plugin processing, local asset lifecycle/reference/concurrent writes, semantic report export, installation-linked result diffs and grounded read-only Assistant explanations. Detailed fixtures and limits remain in IMPLEMENTATION-ROADMAP-20261104.md.



ALL21 is not fully accepted: actual license/subscription ground truth, physical asset/durable attachment content, GUI cross-process cooperative cancellation, individual RBAC, crash/distributed transactions, production fleet/LAN scale, independent security audit and wide DPI/accessibility remain unestablished. No claim is inferred from a synthetic fixture or predecessor EXE. Public application self-update remains OFF.



Release gates: clean source and signed provenance, official full build, source regressions on exact checkout, disconnected Windows 11 artifact-bound mTLS/fault tests and packaged VI/EN startup/ResultCenter, visual review and restored baseline, closed checksums/private typed handoff, canonical public assets with fresh downloads/full verifier/Pages. Publish only after all applicable gates pass.



---



# Trạng thái phát hành VietLicenSure v5.0



Nguồn điều phối trạng thái; không thay thế bằng chứng gắn đúng artifact. Ngày cập nhật tài liệu: 05/11/2026. Candidate UI/Trợ lý hiện tại chưa build/phát hành; không kế thừa nghiệm thu của EXE đã công bố.



Ngày phát hành lần đầu v5.0: 08/09/2026; không phải ngày nghiệm thu artifact hiện hành.



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

## Current exact-artifact acceptance — 2026-11-14

EXE E4E29829939125F40043897070149C44D3F60758464CA9D22DC5C25F85C8D8EE / 998080 bytes; source 9d52d246356576ad3860d4e6a25531481dc33728; signed bundle 53c995b2526c858f7f8c055aaca1772321c457a2.
Official Self-Signed, build8/8, full verifier0errors/3disclosed warnings and distribution0errors/1self-signed warning. Host Authenticode UnknownError/UntrustedRoot is retained; pinned signer and timestamp verified. Not public-CA/EV/Store; SmartScreen may warn.
Current Windows11 24H2 offline VI/EN AdminElevated packaged startup, Assistant and ResultCenter integrity cases; actual GUI report Stop and unchanged embedded main-report normal completion, followed by fresh checkpoint restoration. Read QA-EVIDENCE for exact results. No current-hash managed-document/protected-worker UI, full GUI normal-completion, production mTLS, or independent review claim.
Roles are Personal, Technical Support and Business Inventory. Workspace choice grants no authority; maintenance scope remains elevated-admin. No general non-admin broker, deployed delegated RBAC, all21, physical fleet, broad DPI/Windows10, licensing ground truth or independent security review claim. Review NotReviewed; external accuracy NotEstablished.
Worker isolation bounds execution time under the same Windows token; it is not a security sandbox. Managed document copies remain ReferencedUnverified, not authenticated legal evidence. Recovery39 and real token/ACL source fixtures keep their original source scope, not a full-machine/power-loss/disk-full rollback claim.
