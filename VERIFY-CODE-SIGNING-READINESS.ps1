[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CertificateThumbprint,
    [ValidateSet('CurrentUser','LocalMachine')][string]$StoreLocation = 'CurrentUser',
    [string]$ArtifactPath = '',
    [switch]$AllowManagedSelfSigned,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$normalized = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
if ($normalized -notmatch '^[A-F0-9]{40}$') { throw 'CertificateThumbprint must be a 40-character SHA-1 thumbprint.' }
$certificatePath = "Cert:\$StoreLocation\My\$normalized"
if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) { throw "Certificate not found in $StoreLocation\My." }
$certificate = Get-Item -LiteralPath $certificatePath -ErrorAction Stop

$hasCodeSigningEku = $false
foreach ($extension in @($certificate.Extensions)) {
    if ($extension.Oid.Value -ne '2.5.29.37') { continue }
    $eku = New-Object Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension -ArgumentList @($extension, [bool]$extension.Critical)
    foreach ($oid in @($eku.EnhancedKeyUsages)) {
        if ($oid.Value -eq '1.3.6.1.5.5.7.3.3') { $hasCodeSigningEku = $true }
    }
}

$chain = New-Object Security.Cryptography.X509Certificates.X509Chain
try {
    $chain.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::Online
    $chain.ChainPolicy.RevocationFlag = [Security.Cryptography.X509Certificates.X509RevocationFlag]::ExcludeRoot
    $chain.ChainPolicy.VerificationFlags = [Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag
    $chain.ChainPolicy.UrlRetrievalTimeout = [TimeSpan]::FromSeconds(20)
    $chainValid = [bool]$chain.Build($certificate)
    $chainErrors = @($chain.ChainStatus | ForEach-Object { ([string]$_.Status).Trim() })
} finally {
    $chain.Dispose()
}

$artifactStatus = ''
$artifactTimestamped = $false
$artifactSignerThumbprint = ''
$artifactSignerMatches = $false
if (-not [string]::IsNullOrWhiteSpace($ArtifactPath)) {
    $artifactFullPath = [IO.Path]::GetFullPath($ArtifactPath)
    if (-not (Test-Path -LiteralPath $artifactFullPath -PathType Leaf)) { throw 'ArtifactPath does not exist.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $artifactFullPath
    $artifactStatus = [string]$signature.Status
    $artifactTimestamped = [bool]($null -ne $signature.TimeStamperCertificate)
    if ($signature.SignerCertificate) {
        $artifactSignerThumbprint = ([string]$signature.SignerCertificate.Thumbprint -replace '\s', '').ToUpperInvariant()
        $artifactSignerMatches = $artifactSignerThumbprint.Equals($normalized, [StringComparison]::OrdinalIgnoreCase)
    }
}

$ready = [bool](
    $certificate.HasPrivateKey -and
    $hasCodeSigningEku -and
    ($AllowManagedSelfSigned -or [string]$certificate.Subject -ne [string]$certificate.Issuer) -and
    (Get-Date) -ge $certificate.NotBefore -and
    (Get-Date) -le $certificate.NotAfter -and
    $chainValid -and
    ([string]::IsNullOrWhiteSpace($ArtifactPath) -or ($artifactStatus -eq 'Valid' -and $artifactTimestamped -and $artifactSignerMatches))
)

$result = [pscustomobject][ordered]@{
    SchemaVersion = '1.0'
    Ready = $ready
    Subject = [string]$certificate.Subject
    Issuer = [string]$certificate.Issuer
    Thumbprint = $normalized
    NotBeforeUtc = $certificate.NotBefore.ToUniversalTime().ToString('o')
    NotAfterUtc = $certificate.NotAfter.ToUniversalTime().ToString('o')
    HasPrivateKey = [bool]$certificate.HasPrivateKey
    CodeSigningEku = $hasCodeSigningEku
    SelfSigned = [bool]([string]$certificate.Subject -eq [string]$certificate.Issuer)
    WindowsChainValid = $chainValid
    TrustScope = if ($AllowManagedSelfSigned) { 'Managed current-user trust; not public-CA identity.' } else { 'Windows trust chain on this build host; public-CA/EV eligibility requires release-owner certificate procurement review.' }
    ChainErrors = @($chainErrors)
    ArtifactStatus = $artifactStatus
    ArtifactTimestamped = $artifactTimestamped
    ArtifactSignerThumbprint = $artifactSignerThumbprint
    ArtifactSignerMatchesCertificate = $artifactSignerMatches
}

if ($AsJson) { $result | ConvertTo-Json -Depth 4 } else { $result | Format-List | Out-String | Write-Host }
if (-not $ready) { exit 1 }
exit 0
