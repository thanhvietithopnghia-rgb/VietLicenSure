# Microsoft Store restricted-capability justification

## Application

- Product: VietLicenSure Bản Quyền v5.0
- Partner Center product ID: `9NHGPJG831ZH`
- Package identity name: `ThanhVit.ToolKimTraBnQuyn`
- Publisher: `CN=3EB43154-43D8-4A10-BD13-AB0D250530BE`
- Package family: `ThanhVit.ToolKimTraBnQuyn_9tjmpwr25h78w`
- Package type: x64 desktop MSIX
- Main process integrity: medium IL / asInvoker
- Restricted capabilities requested: `runFullTrust` and `allowElevation`

## Why runFullTrust is required

The application is a Win32 desktop compliance and diagnostics tool. It reads Windows and Microsoft Office licensing/configuration evidence, exports reports chosen by the user and invokes existing Windows command-line facilities. These operations are not implemented as an AppContainer application.

## Why allowElevation is required

The dashboard does not start elevated. Administrative access is requested only when the user explicitly selects a remediation or enterprise-management action that Windows restricts to administrators, including selected firewall rules, HTTP URL reservations and scheduled-task management.

For every elevated action, the application is designed to:

1. Display the intended scope before execution.
2. Require explicit user confirmation.
3. Trigger the standard Windows UAC consent flow.
4. Limit arguments and paths to the selected operation.
5. Create and verify backup/rollback information where applicable.
6. Record an audit event without logging secrets.
7. Run post-verification and report partial failure clearly.

If UAC is rejected, the requested change is cancelled and the dashboard continues without elevation. The application does not bypass UAC, install a persistent privileged service or silently modify system configuration.

The StoreSubmission launcher also fails closed before elevation unless Windows reports the exact Microsoft Store package family, version, x64 architecture and publisher ID compiled into the reviewed build and reports `PackageOrigin_Store`. Every UAC request is re-dispatched through that compiled launcher, which re-checks Store trust after elevation, extracts a fresh Administrator/SYSTEM-only payload, verifies the original payload tree by SHA-256, verifies signed provenance, and enforces a per-module argument allowlist before starting PowerShell. A read-only module ID cannot carry remediation switches. Copying the unsigned inner EXE out of the installed package, installing a DeveloperSigned/line-of-business sideload with a matching identity string, modifying a script between checks, or forging the caller's environment cannot enable administrative changes.

## Certification evidence to attach

- Screen recording: normal scan without elevation.
- Screen recording: remediation preview, UAC consent and post-verification.
- Screen recording: UAC rejection with no system change.
- Exact list of elevated commands and their argument validation rules.
- Backup and rollback test results.
- Three-VM results for Windows 10 22H2, Windows 11 24H2 and Windows 11 25H2.
- Independent security-review attestation showing zero unresolved Critical/High findings.

The Partner Center identity above is final for this product. Attach the current evidence identifiers before submission; do not alter the assigned package identity values.
