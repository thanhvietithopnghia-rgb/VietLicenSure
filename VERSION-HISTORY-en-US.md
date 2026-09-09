# VietLicenSure — System License Inspection and Management Software Version History

This document summarizes the core changes in every recorded version, from the first release through the current v5.0 technical release.

Public product page:
<https://thanhvietithopnghia-rgb.github.io/VietLicenSure/>

## v5.0 — September 8, 2026

- **Name and direction:** the official name changed from **Tool Kiem Tra — Computer and Software License Check Tool** to **VietLicenSure — System License Inspection and Management Software**, with one public version name, **v5.0**, across the application, updater, documentation, and GitHub.
- **Upgrade foundation:** v5.0 is the direct successor to v4.9, retaining its inventory and evidence model while expanding it into a unified system inspection and management workflow.
- **Source policy:** explains controlled access from v4.9 after the software/predecessor was copied, modified, renamed/repackaged, and published without permission or authorization; documents scope, written access requests, and the absence of a committed reopening date.
- **Two-way communication:** adds GitHub Issues for bugs, GitHub Discussions for questions/proposals, and Private Security Advisories for vulnerability reports.
- **Interface and experience:** faster startup, DPI-aware layout, Light/Dark modes, clearer navigation, and direct access to the requested function.
- **Windows, Office, and software inspection:** Quick, Standard, and Deep modes; broader inventory sources; separate activation, licence type, read failures, and insufficient-evidence results.
- **Analysis and management:** High–Medium–Low prioritization, search, filters, previous-scan comparison, and multi-device support.
- **Safe remediation:** separate Windows, Office, and third-party scopes with mandatory preview, Dry Run, backup, confirmation, post-check, and rollback support.
- **Reports, privacy, and release integrity:** HTML/PDF/JSON/XML/CSV exports, redacted support data, Offline-by-default operation, CMS/SHA-256/Authenticode verification, and updates to the latest approved v5.0 build when Online mode is enabled.

`Unverified` does not mean that software violates its licence.

## v4.9.0.0 — August 22, 2026

- **More accurate recognition:** inventories Registry, AppX/MSIX, WinGet, shortcuts, package managers, and bounded portable locations; distinguishes confirmed installations from portable/residual files and merges duplicate records by product family.
- **Adaptive integrity scanning:** vendor host blocks or disabled licensing services trigger broader Authenticode checks within the exact product directory; evidence no longer leaks between products from the same vendor.
- **Diagnosable licensing and safe remediation:** unreadable data is distinct from unactivated status; reports are read-only; remediation removes only the selected bad key/Activation ID, preserves coexisting genuine licences, and verifies the exact selected scope afterward.
- **Controlled complete uninstall:** an application can be fully removed only after explicit selection and validation of a source-bound MSI/AppX identity; preview, backup, execution result, and absence post-check remain mandatory.
- **Protected release chain:** the EXE, provenance, catalog, and update manifest are signed; online comparison accepts declarative data only from pinned official sources and uploads no software inventory or device data.
- **Policy from v4.9:** VietLicenSure remains free and community-oriented; source is no longer published publicly, is not open source, and requires the author's prior written approval for access.

## v4.8.0.1 — August 18, 2026

- Separated Windows and Office activation states; incomplete or unreadable Office data is reported as **Unverified** and blocks automatic remediation.
- Made Office KMS restoration safer, preserving coexisting valid Retail/MAK/Subscription licensing without deleting Office accounts or tokens.
- Always shows the complete scanned-software list; only items backed by direct remediation evidence can be selected.
- Application updates verify version, SHA-256, signature, backup, and rollback; there are no silent updates or telemetry.

## v4.8.0.0 — August 10, 2026

- **Broad inventory and assessment:** expanded Windows, Office, third-party software, and hardware checks while separating licence model, technical state, and confidence.
- **Deep scan and signed catalog:** introduced multi-tier evidence and `Unverified` outcomes to avoid conclusions when data is incomplete.
- **Controlled remediation:** scope selection, preview, confirmation, backup, and post-verification are mandatory; weak evidence never removes software or changes the system automatically.
- **Usability:** completed the Dashboard, HTML/PDF reports, local Assistant, and server–workstation management while keeping Offline as the default.

## v4.6 — August 6, 2026

- Expanded the engineering-software catalog while retaining the vendor-neutral deep scanner for products without a dedicated rule.
- Added remediation **Dry Run**, listing the exact intended actions without changing the system.
- Made Online consent fail closed and reduced information exposed by the unauthenticated Enterprise status endpoint.
- Isolated writable versioned data and added staged migration, SHA-256 verification, rollback, and legacy-data preservation.
- Improved deep-scan performance, synchronized release metadata, and added data-lifecycle verification.

## v4.5 — August 6, 2026

- Completed the Light/Dark visual system, action icons, and DPI-aware layout; adopted the product name **Computer Configuration and Software License Check Tool**.
- Inventoried software from Registry, AppX/MSIX, Start Menu, Desktop, and bounded installed/portable locations.
- Added vendor-neutral deep scans, confidence tiers, and explicit reporting of incomplete coverage.
- Added explained, explicit-consent Online comparison without uploading application inventory, paths, keys, or tokens; Offline remained the default.
- Expanded scope selection, backup/restore, timeouts, heartbeat, and HTML/PDF reporting; automatic mode never uninstalls software.

## v4.4 — July 31, 2026

- Added safe automatic remediation for allowlisted, backup-capable items, with preview, confirmation, protected backup, and post-scan verification.
- Completed Vietnamese/English localization across the dashboard, dialogs, reports, and child modules while preserving language-neutral machine status codes.
- Refreshed the Fluent-style dashboard, Inspect/Remediate/Reports filters, Settings dialog, and bundled vector icons for Light/Dark modes.
- Optimized bounded Office/file scanning and added Copy full log, Open report folder, and non-blocking VM/Remote Desktop notices.

## v4.3 — July 30–31, 2026

- Upgraded the dashboard to schema 2.0 with DPI/screen-size adaptation and a safe Stop action for child tasks.
- Standardized Offline-by-default behavior, Vietnamese/English operation, Local/Server/Workstation management, and HTML/PDF/JSON/XML reports.
- Expanded software, signature, autorun, service, task, and installation-source inventory without breaking earlier report contracts.

## v4.2 — July 24–25, 2026

- Added the internal-network licence center with Local, Server, and Workstation modes.
- Added pairing, inventory, offline queues, and authenticated/encrypted fleet reporting.
- Protected URL ACL/firewall configuration with confirmation and prevented competing servers in one scope.

## v4.1 — July 23, 2026

- Added the Report Center, certificate auditing, read-only declarative plugins, and licence timeline.
- Standardized HTML, PDF, JSON, XML, and SHA-256 manifest export; protected timeline records with DPAPI/HMAC/hash chaining.
- Added release-signing checks, the About window, and product capability groups.

## v4.0 — July 23, 2026

- Replaced the traditional menu with a WinForms dashboard containing status cards, ten actions, Light/Dark modes, and DPI-aware layout.
- Added report schemas, safety-policy modules, regression verification, and native x64/x86 Windows-tool resolution.
- Introduced the KMS/Activator remediation center with preview, confirmation, backup, and post-checks.

## v3.9 — July 22, 2026

- Upgraded reports to schema 1.3, added fallback scan sources, and made schema verification a release gate.
- Reduced false positives involving legitimate Windows processes, old PowerShell history, hosts entries, and inactive Office SKUs.
- Optimized per-run caching and refreshed data before post-checks.

## v3.8 — July 22, 2026

- Added deeper Windows/Office scans and confidence-based evidence aggregation.
- Improved detailed reports, remediation guidance, and partial-source failure handling.

## v3.7 — July 22, 2026

- Added integrity, file-signature, and common licensing-tampering checks.
- Standardized detection states shared by the interface and reports.

## v3.6 — July 22, 2026

- Expanded multi-version/multi-SKU Office inspection and unusual KMS configuration detection.
- Added technical logging and post-remediation verification.

## v3.5 — July 21, 2026

- Added integrity-protected Windows/Office licensing backup and restore.
- Required Administrator rights, preview, and confirmation before system changes.

## v3.4 — July 21, 2026

- Improved digital-licence, OEM, and Windows licensing-channel recognition.
- Added safe local-key inspection with only partial key display.

## v3.3 — July 20, 2026

- Validated `approved-kms-servers.txt`, warned on empty or malformed entries, and displayed detected KMS hosts for administrator confirmation.
- Allowed confirmed edits/saves; the one-file build stored its configuration beside the EXE and reported its path, valid-line count, and warnings.

## v3.2 — July 20, 2026

- Upgraded progress display with task name, indeterminate activity, elapsed time, and live logs.
- Added 10-second status heartbeats and clear completed, warning, or error final states from module results.

## v3.1 — July 20, 2026

- Added startup SHA-256 verification as a warning-only check; mutable KMS configuration remained outside the manifest.
- Added JSON plus hashes to the combined report and read-only licensing-service, time, signature, and reboot diagnostics.

## v3.0 — July 20, 2026

- Added confirmation before basic handling; when residues remained after verification, the user could choose advanced cleanup or retain the state for reporting.
- Advanced cleanup backed up/quarantined data and targeted exact KMS, IFEO, or Defender-exclusion artifacts; it used SFC where needed and then ran a final scan.

## v2.9 — July 20, 2026

- Added up to 180 days of activation traces and separated historical records from active indicators to avoid incorrect handling.
- Added automatic post-action rescanning and synchronized the summary and guide with the ten-feature order.

## v2.8 — July 20, 2026

- Moved the user guide to feature 10 and deep inspection to feature 9.
- Retained the chooser between the seven-group scan and 12-group investigation/risk scoring.

## v2.7 — July 20, 2026

- Merged the 12-group investigation into the same chooser as the seven-group scan to simplify the menu.
- Preserved v2.6 UAC, read-only operation, SHA-256 reporting, and safety boundaries.

## v2.6 — July 20, 2026

- Added read-only 12-group forensics, a 0–100 risk score, Authenticode/SHA-256, and security/log-state inspection.
- Exported HTML/JSON/CSV plus checksums with baseline comparison; no data upload or system change.

## v2.5 — July 18, 2026

- Added valid Windows edition/product-key changes through `changepk.exe` and DISM, plus valid Office-key installation through `OSPP.VBS`.
- Opened official Microsoft pages; stored no full keys, supplied no public keys/KMS, and never removed old Office keys automatically.

## v2.4 — July 18, 2026

- Relabeled v1.3.0 as v2.4 for the requested release naming.
- Moved Close onto the status row for short/high-DPI displays while retaining the v1.3.0 feature set, UAC/deep-scan behavior, and safety boundaries.

## v1.3.0 — July 18, 2026

- Required Administrator/UAC for complete WMI/licensing, service, process, task, Registry-policy, hosts, and signature/system-file sources.
- Declining UAC stopped safely; elevated scanning remained read-only, avoided personal documents, and downloaded/executed no remote code.

## v1.2.0 — July 18, 2026

- Added a seven-group Windows licensing scan with evidence levels and read-only checks of approved KMS, activator/MAS/HWID, KMS38, generic keys, folders, tasks, Registry, and hosts.
- Notification or unactivated state no longer led automatically to key removal; PowerShell history and full product keys were not stored.

## v1.1.0 — July 18, 2026

- Integrated selected safe checks; added masked OEM OA3 inspection and confirmed/UAC-gated OEM restore without first removing the current key.
- Added the official Windows key-entry UI and excluded risky public/generic keys, broad history deletion, and machine-wide firewall/hosts edits.

## v1.0.9 — July 17, 2026

- Introduced a single portable EXE for direct use on another computer.
- The EXE extracted modules to a temporary directory, waited for the UI to close, and then cleaned up.

## v1.0.8 — July 17, 2026

- Added the `00-Tool-Kiem-Tra.ico` identity icon and bundled the complete guide/history.

## v1.0.7 — July 17, 2026

- Compacted the UI so the title, notes, menu, progress area, and Close button fit together on normal displays.

## v1.0.6 — July 17, 2026

- Improved short-screen/high-DPI layout with tighter spacing, a smaller log, dynamic height, and fallback scrolling.

## v1.0.5 — July 17, 2026

- Renamed the displayed product to “Computer configuration and software license check tool” and added execution-progress plus clear completion/error states.

## v1.0.4 — July 17, 2026

- Fixed note wrapping, dynamic layout, and scrolling on short displays.

## v1.0.3 — July 17, 2026

- Confirmed PowerShell 3.0+ support and clarified that passwords and full product keys are never extracted.

## v1.0.2 — July 17, 2026

- Made feature 6 inspect and confirm first while protecting OEM/Retail/MAK and approved internal KMS.
- Limited handling to unapproved KMS/crack evidence; an activator trace alone never caused product-key removal.

## v1.0.1 — July 17, 2026

- Fixed title/font presentation, updated support details, confirmed Windows 7 SP1+, and established version increments for each release.

## v1.0.0 — July 17, 2026

- First Windows GUI release for configuration and software-licensing inspection.

---

The bundled release records and available archive contain no v2.0–v2.3 entry. v2.4 is the first recorded 2.x release and directly follows v1.3.0; the Assistant does not invent changes for an undocumented version.

There was no public v4.7 release; v4.8 was the direct public successor to v4.6.

Consistent safety principle: inspection is read-only by default; no telemetry; no unrequested licensing change; remediation requires selection, confirmation, backup, and post-verification.

A new history entry is added only when the official public release name or version number changes. Patches, technical updates, and internal builds within the same version stay in the release notes and do not create separate history entries.
