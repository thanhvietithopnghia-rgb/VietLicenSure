# First-run FAQ — VietLicenSure v5.0

This document is for people downloading and running VietLicenSure for the first time. The current release decision is maintained in `RELEASE-STATUS-v5.0.md`; detailed verification instructions are in `RELEASE-VERIFICATION-v5.0.md`.

## What should I do when SmartScreen shows a warning?

Do not disable SmartScreen or Microsoft Defender, and do not add an exclusion merely to force the file to run.

1. Confirm that the file came from the official Releases page: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/releases/tag/v5.0>.
2. Compare the EXE's SHA-256 with `RELEASE-STATUS-v5.0.md` and the checksum included in the same package:

   ```powershell
   Get-FileHash .\VietLicenSure-v5.0.exe -Algorithm SHA256
   ```

3. Check Authenticode, the signer, and the timestamp:

   ```powershell
   Get-AuthenticodeSignature .\VietLicenSure-v5.0.exe |
     Format-List Status,StatusMessage,SignerCertificate,TimeStamperCertificate
   ```

4. If you have the full package, run `VERIFY-RELEASE.cmd` and require `0 errors`. Scan the file with Microsoft Defender.
5. **Stop and download again or report the problem** if the hash differs, the status is `HashMismatch` or `NotSigned`, the signer differs, the timestamp is missing, or CMS verification fails.

VietLicenSure v5.0 is currently distributed as `ManagedSigned / Internal Pilot` and uses a pinned self-signed certificate. A new computer can therefore still show `Unknown publisher` or a SmartScreen warning even when the file has not been modified. Only after every verification step passes, on a personal unmanaged computer, may you deliberately choose **More info → Run anyway**. If that option is unavailable or the device is managed by an organization, stop and contact the administrator. Do not change device policy or install the certificate into Trusted Root merely to suppress the warning.

## Which function should I choose first?

Keep **Offline** enabled, run under a standard user account, and choose **Check everything**. Read the summary cards first, then open the detailed evidence. Enable Online only when you intentionally update a catalog or knowledge file, or use an authorized LAN function.

## Why does the application ask for UAC?

Routine inspection should not require Administrator rights. UAC should appear only after you select a task that needs machine-wide access, remediation, updating, or administration. Cancel the prompt if its operation name does not match the action you just selected. Do not routinely run the entire application as Administrator.

## Does one warning mean the software is cracked?

No. VietLicenSure correlates multiple sources and evidence rules. `Unverified`, `Suspicious`, and `Confirmed crack` are different states. Leftover files, portable software, missing Registry data, an authorized internal KMS, or a limited scan source may require manual review. Never uninstall software solely because of one file name or one isolated warning.

## Why might UniKey or another portable application be missing?

Portable software often has no Registry installation record and may be stored outside the selected scan roots. Check its actual path and shortcuts, then select an appropriate scan scope. Absence from the report does not prove that the application was removed or is not present.

## Is every KMS finding unauthorized?

No. An organization may legitimately operate an authorized internal KMS. Do not approve a KMS server from its name or address alone; verify it with the administrator, licensing agreement, and the organization's approved-server list. A public or unexplained KMS endpoint must remain subject to review.

## What should I do about a PowerShell or permission error?

Read which data source failed and retry only with the rights appropriate to that task. Execution Policy, AppLocker/WDAC, Windows services, file locks, or organizational policy can make a result incomplete. Do not lower machine-wide security policy. On a managed device, provide the administrator with a redacted support bundle.

## Should I select Remediate immediately?

No. Review the evidence, run **Preview/Dry Run**, create and verify a backup, confirm the exact target, and only then perform the action. Treat the task as complete only after post-verification passes. `VerifiedClean` is a technical result for the inspected scope, not proof of license ownership.

## What should I include in a bug report?

Include the version, reproduction steps, a screenshot of the warning, and a **Redacted** support bundle. Do not publish complete product keys, unredacted serial numbers or UUIDs, credentials, or internal organizational data. Use [GitHub Issues](https://github.com/thanhvietithopnghia-rgb/VietLicenSure/issues/new/choose) for ordinary bugs and a [Private Security Advisory](https://github.com/thanhvietithopnghia-rgb/VietLicenSure/security/advisories/new) for security issues.
