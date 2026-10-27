[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate, [string]$ArchiveCache = '')
. "$PSScriptRoot/native-isar-rust-inputs.ps1"
$Candidate = [IO.Path]::GetFullPath($Candidate)
$graphDirectory = & "$PSScriptRoot/collect-native-isar-graph.ps1" -Candidate $Candidate
$receiptPath = Join-Path $Candidate 'native-build.json'
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
# Root distribution notices are not trusted from an earlier mutable extraction.
$prepared = & "$PSScriptRoot/prepare-native-isar.ps1" -ArchiveCache $ArchiveCache
$inputs = Get-NativeIsarRustMaterials $prepared $receipt.inputDigests.rust
$output = Join-Path $Candidate ('rust-material-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($output) | Out-Null
$notice = [Text.StringBuilder]::new()
[void]$notice.AppendLine('Pinned Rust SDK license and copyright material; unqualified, incomplete native notice bundle.')
[void]$notice.AppendLine($inputs.manifest.scope)
foreach ($material in $inputs.materials | Sort-Object { $_.descriptor.id } -CaseSensitive) {
    $file = $material.descriptor
    $destination = Join-Path $output $file.destination
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    Copy-Item -LiteralPath $material.path -Destination $destination
    if ((Get-NativeIsarDigest $destination) -cne $file.sha256) { throw 'Rust copied material mismatch.' }
    [void]$notice.AppendLine().AppendLine($file.id + ': ' + $file.role).AppendLine('File: ' + $file.destination)
    # HTML catalogues remain exact source data, never executed or stripped to lossy text.
    if (-not $file.destination.EndsWith('.html',[StringComparison]::Ordinal)) { [void]$notice.AppendLine([IO.File]::ReadAllText($destination)) }
}
Copy-Item -LiteralPath $inputs.manifestPath -Destination (Join-Path $output 'rust-license-material.json')
if ((Get-NativeIsarDigest (Join-Path $output 'rust-license-material.json')) -cne $inputs.manifestSha256) { throw 'Rust copied manifest mismatch.' }
$noticePath = Join-Path $output 'RUST_NATIVE_NOTICES.txt'
[IO.File]::WriteAllText($noticePath,$notice.ToString(),[Text.UTF8Encoding]::new($false))
Write-NativeIsarJson (Join-Path $output 'rust-material-receipt.json') ([ordered]@{
    schemaVersion=1;product='serverdeck-isar-native';bindingVersion='3.3.2';state='rust-material-collected-unqualified';distributionReady=$false
    buildReceiptSha256=Get-NativeIsarDigest $receiptPath
    graphSha256=Get-NativeIsarDigest (Join-Path $graphDirectory 'native-dependencies.json')
    inputManifestSha256=$inputs.manifestSha256;compiledRustTreeDigest=$inputs.rustDigest
    notice=@{file='RUST_NATIVE_NOTICES.txt';sha256=Get-NativeIsarDigest $noticePath}
    fileCount=$inputs.materials.Count
})
Write-Output $output
Write-Output $prepared
