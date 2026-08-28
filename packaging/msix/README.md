# MSIX packaging for Tool Kiểm Tra Bản Quyền v5.0

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

The Partner Center identity assigned on 2026-08-28 is stored in `STORE-PRODUCT-IDENTITY.json`:

- Product ID: `9NHGPJG831ZH`
- Reserved name: `Tool Kiểm Tra Bản Quyền`
- Package/Identity/Name: `ThanhVit.ToolKimTraBnQuyn`
- Package/Identity/Publisher: `CN=3EB43154-43D8-4A10-BD13-AB0D250530BE`
- Package/Properties/PublisherDisplayName: `Thanh Việt`

Generate the Store candidate with the tracked identity file:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\packaging\msix\New-ToolKiemTraMsix.ps1 `
      -ExecutablePath .\dist-v5-evidence-final-20260828\Tool-Kiem-Tra-v5.0.exe `
      -OutputDirectory .\dist-msix-store `
      -Mode Store `
      -StoreIdentityPath .\packaging\msix\STORE-PRODUCT-IDENTITY.json

The script rejects command-line identity overrides that differ from the tracked Partner Center values. Do not submit the development package. Do not call the unsigned Store candidate Public Stable. Store certification, restricted-capability approval, three-VM evidence and independent security review remain release gates.
