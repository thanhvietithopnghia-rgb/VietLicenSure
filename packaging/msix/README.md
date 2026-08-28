# MSIX packaging for Tool Kiểm Tra v5.0

This directory creates two deliberately separate package types:

- Development: locally signed with a private/self-signed certificate for packaging and installation tests only.
- Store: unsigned submission candidate using the exact identity assigned by Microsoft Partner Center.

The main executable remains `asInvoker`. The package declares `runFullTrust` and, by default, `allowElevation` because administrative remediation is launched only after explicit user action and a UAC prompt.

## Development package

Run from the repository root:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\packaging\msix\New-ToolKiemTraMsix.ps1 `
      -ExecutablePath .\dist-v5-evidence-final-20260828\Tool-Kiem-Tra-v5.0.exe `
      -OutputDirectory .\dist-msix-development `
      -Mode Development `
      -SigningCertificateThumbprint '<development certificate thumbprint>'

Install only on an isolated test machine. Open an elevated PowerShell window, trust the exported public certificate for package testing, then install the package:

    Import-Certificate `
      -FilePath .\dist-msix-development\Tool-Kiem-Tra-v5.0-development.cer `
      -CertStoreLocation Cert:\LocalMachine\TrustedPeople

    Add-AppxPackage `
      -Path .\dist-msix-development\Tool-Kiem-Tra-v5.0-development.msix

After the test, uninstall the development package and remove only the imported development certificate from LocalMachine TrustedPeople. Never distribute or call this certificate publicly trusted.

## Store candidate

First reserve the app name in Partner Center and copy the exact package identity values. Then run:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\packaging\msix\New-ToolKiemTraMsix.ps1 `
      -ExecutablePath .\dist-v5-evidence-final-20260828\Tool-Kiem-Tra-v5.0.exe `
      -OutputDirectory .\dist-msix-store `
      -Mode Store `
      -PackageName '<Partner Center Package/Identity/Name>' `
      -Publisher '<Partner Center Package/Identity/Publisher>'

Do not submit the development package. Do not call the unsigned Store candidate Public Stable. Store certification, restricted-capability approval, three-VM evidence and independent security review remain release gates.
