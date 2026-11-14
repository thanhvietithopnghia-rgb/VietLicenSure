param([string]$DistributionDirectory=$PSScriptRoot)
$ErrorActionPreference='Stop'
try {
 $root=[IO.Path]::GetFullPath($DistributionDirectory).TrimEnd('\')
 Add-Type -AssemblyName System.Security
 $path=Join-Path $root 'PACKAGING-CONTEXT.json'
 $cms=[Security.Cryptography.Pkcs.SignedCms]::new([Security.Cryptography.Pkcs.ContentInfo]::new([IO.File]::ReadAllBytes($path)),$true)
 $cms.Decode([IO.File]::ReadAllBytes(($path+'.p7s')))
 if($cms.SignerInfos.Count -ne 1){throw 'Packaging signer count invalid'}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$pin=([BitConverter]::ToString($sha.ComputeHash($cms.SignerInfos[0].Certificate.RawData))).Replace('-','')}finally{$sha.Dispose()}
 if($pin -cne 'A42B00D863D4770B47F21FFF756545249D58DD59691AD9E05C02048C104F9FC9'){throw 'Packaging signer pin mismatch'}
 if($cms.SignerInfos[0].DigestAlgorithm.Value -cne '2.16.840.1.101.3.4.2.1'){throw 'Packaging signature must use SHA256'}
 $cms.CheckSignature($true)
 $record=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
 if($record.PackagingRevision -cne '20261114-xml-r3' -or -not $record.ExecutableUnchanged){throw 'Unexpected packaging revision'}
 $listed=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 foreach($row in @($record.StableDistributionFiles)+@($record.PackagingFiles)){
  $name=[string]$row.Path
  if([IO.Path]::GetFileName($name) -cne $name -or $name -match '[:/\\]' -or $name -in @('.','..') -or -not $listed.Add($name)){throw 'Unsafe/duplicate packaging member'}
  $file=Get-Item -LiteralPath (Join-Path $root $name) -Force
  if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -ne $row.Size -or (Get-FileHash -LiteralPath $file.FullName).Hash -cne $row.Sha256){throw ('Packaging member mismatch: '+$name)}
 }
 foreach($name in @('PACKAGING-CONTEXT.json','PACKAGING-CONTEXT.json.p7s','RELEASE-SHA256SUMS.txt')){if(-not $listed.Add($name)){throw 'Reserved packaging member duplicated'}}
 foreach($file in Get-ChildItem -LiteralPath $root -Force){if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not $listed.Contains($file.Name)){throw ('Unexpected packaging member: '+$file.Name)}}
 if(@(Get-ChildItem -LiteralPath $root -Force).Count -ne $listed.Count){throw 'Packaging member count mismatch'}
 $release=Get-Content -LiteralPath (Join-Path $root 'RELEASE-MANIFEST.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $provenance=Get-Content -LiteralPath (Join-Path $root 'OFFICIAL-PROVENANCE-v1.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($release.Artifacts[0].Sha256 -cne $record.ArtifactSha256 -or $provenance.SourceSnapshotCommit -cne $record.SourceSnapshot){throw 'Packaging artifact/source identity mismatch'}
 if((Get-FileHash -LiteralPath (Join-Path $root 'VietLicenSure-v5.0.exe')).Hash -cne $record.ArtifactSha256){throw 'Executable changed'}
 & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $root 'VERIFY-DISTRIBUTION.ps1') -DistributionDirectory $root
 if($LASTEXITCODE -ne 0){throw 'Distribution verification failed'}
 'PACKAGING: PASS (pinned CMS, unchanged executable/source, current closed distribution)'
 exit 0
}catch{Write-Error $_;exit 1}
