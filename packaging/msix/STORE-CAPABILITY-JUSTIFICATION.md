# Microsoft Store restricted-capability justification

## Application

- Product: Tool Kiểm Tra v5.0
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

## Certification evidence to attach

- Screen recording: normal scan without elevation.
- Screen recording: remediation preview, UAC consent and post-verification.
- Screen recording: UAC rejection with no system change.
- Exact list of elevated commands and their argument validation rules.
- Backup and rollback test results.
- Three-VM results for Windows 10 22H2, Windows 11 24H2 and Windows 11 25H2.
- Independent security-review attestation showing zero unresolved Critical/High findings.

This document is a submission draft. Replace placeholders with the Partner Center product identity and current evidence identifiers before submission.

