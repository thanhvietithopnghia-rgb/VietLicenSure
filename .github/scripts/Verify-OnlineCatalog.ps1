$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$name = 'software-license-catalog-v1.0.json'
$content = [IO.File]::ReadAllBytes((Join-Path $root $name))
$signature = [IO.File]::ReadAllBytes((Join-Path $root ($name + '.p7s')))
if ($content.Length -le 16 -or $content.Length -gt 2097152 -or $signature.Length -le 64 -or $signature.Length -gt 65536) {
    throw 'Online catalog assets are missing or outside runtime size limits.'
}
try { Add-Type -AssemblyName System.Security.Cryptography.Pkcs } catch { Add-Type -AssemblyName System.Security }
$info = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$content)
$cms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($info, $true)
$cms.Decode($signature)
if ($cms.SignerInfos.Count -ne 1) { throw 'Expected exactly one catalog signer.' }
$signer = $cms.SignerInfos[0]
$sha = [Security.Cryptography.SHA256]::Create()
try { $pin = [BitConverter]::ToString($sha.ComputeHash($signer.Certificate.RawData)).Replace('-', '') } finally { $sha.Dispose() }
if ($pin -cne 'A42B00D863D4770B47F21FFF756545249D58DD59691AD9E05C02048C104F9FC9' -or
    $signer.DigestAlgorithm.Value -ne '2.16.840.1.101.3.4.2.1' -or
    $signer.Certificate.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1') {
    throw 'Online catalog signer differs from the production pin/algorithm.'
}
$cms.CheckSignature($true)
$catalog = [Text.Encoding]::UTF8.GetString($content) | ConvertFrom-Json
if ($catalog.SchemaVersion -cne '1.0' -or @($catalog.Products).Count -eq 0 -or
    $catalog.SignatureAsset -cne ($name + '.p7s') -or
    $catalog.UpdateUrl -cne ('https://raw.githubusercontent.com/thanhvietithopnghia-rgb/VietLicenSure/main/' + $name)) {
    throw 'Online catalog schema or fixed endpoint metadata is invalid.'
}
Write-Output ('Signed Online catalog assets verified: version {0}, {1} rules.' -f $catalog.CatalogVersion, @($catalog.Products).Count)
