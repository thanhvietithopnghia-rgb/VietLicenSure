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
- Package family name: `ThanhVit.ToolKimTraBnQuyn_9tjmpwr25h78w`
- Package/Properties/PublisherDisplayName: `Thanh Việt`

First build the dedicated StoreSubmission executable. This mode embeds signed
source provenance but leaves the inner EXE unsigned for Partner Center. At
runtime it permits elevated actions only when Windows supplies the exact Store
package family, version, architecture and publisher identity and reports the
package origin as Microsoft Store:

    powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\BUILD.ps1 `
      -OutputDirectory .\dist-v5-store `
      -AllowStoreBuild

Then generate the Store candidate with the tracked identity file:

    powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\packaging\msix\New-ToolKiemTraMsix.ps1 `
      -ExecutablePath .\dist-v5-store\Tool-Kiem-Tra-v5.0.exe `
      -OutputDirectory .\dist-msix-store `
      -Mode Store `
      -StoreIdentityPath .\packaging\msix\STORE-PRODUCT-IDENTITY.json

The script rejects command-line identity overrides, DevelopmentUnsigned launchers and release manifests that differ from the tracked Partner Center values. A StoreSubmission EXE copied out of its installed package, installed from a DeveloperSigned/line-of-business sideload, or invoked with a forged UAC/module payload fails closed for administrative actions. The compiled launcher re-brokers elevation into a protected payload directory and the bridge binds each module ID to an exact argument profile. Do not submit the development package. Do not call the unsigned Store candidate Public Stable. Store certification, restricted-capability approval, three-VM evidence and independent security review remain release gates.
