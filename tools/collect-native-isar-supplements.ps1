[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate)
. "$PSScriptRoot/native-isar-supplement-inputs.ps1"
$Candidate = [IO.Path]::GetFullPath($Candidate)
# The existing collector verifies the bound candidate, all source trees and metadata.
$graphDirectory = & "$PSScriptRoot/collect-native-isar-graph.ps1" -Candidate $Candidate
$directory = Join-Path $NativeIsarRepository 'native/isar-3.3.2'
$inputs = Get-NativeIsarSupplementInputs $directory (Join-Path $Candidate 'vendor')
$output = Join-Path $Candidate ('supplements-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($output) | Out-Null
$notice = [Text.StringBuilder]::new()
[void]$notice.AppendLine('Supplemental vendor-source license texts; unqualified, incomplete full native notice bundle.')
[void]$notice.AppendLine($inputs.manifest.canonicalTemplatePolicy)
foreach ($package in $inputs.manifest.packages | Sort-Object name -CaseSensitive) {
    [void]$notice.AppendLine().AppendLine($package.name + '@' + $package.version)
    [void]$notice.AppendLine('Declared license: ' + $package.declaredLicense)
    [void]$notice.AppendLine('Published authors metadata (not an invented copyright notice): ' + ($package.declaredAuthors -join ', '))
    [void]$notice.AppendLine('Text origin: ' + $package.licenseTextOrigin)
    [void]$notice.AppendLine('Text references: ' + ($package.textIds -join ', '))
}
foreach ($text in $inputs.texts | Sort-Object { $_.descriptor.id } -CaseSensitive) {
    $destination = Join-Path $output $text.descriptor.file
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    Copy-Item -LiteralPath $text.path -Destination $destination
    if ((Get-NativeIsarDigest $destination) -cne $text.descriptor.sha256) { throw 'Supplemental copied text mismatch.' }
    [void]$notice.AppendLine().AppendLine('--- ' + $text.descriptor.id + ' ---').AppendLine('Source: ' + $text.descriptor.source)
    [void]$notice.AppendLine([IO.File]::ReadAllText($destination))
}
Copy-Item -LiteralPath $inputs.manifestPath -Destination (Join-Path $output 'supplemental-licenses.json')
$noticePath = Join-Path $output 'SUPPLEMENTAL_NATIVE_NOTICES.txt'
[IO.File]::WriteAllText($noticePath,$notice.ToString(),[Text.UTF8Encoding]::new($false))
Write-NativeIsarJson (Join-Path $output 'supplemental-receipt.json') ([ordered]@{
    schemaVersion=1;product='serverdeck-isar-native';bindingVersion='3.3.2';state='supplements-collected-unqualified';distributionReady=$false
    buildReceiptSha256=Get-NativeIsarDigest (Join-Path $Candidate 'native-build.json')
    graphSha256=Get-NativeIsarDigest (Join-Path $graphDirectory 'native-dependencies.json')
    supplementalManifestSha256=$inputs.manifestSha256
    notice=@{file='SUPPLEMENTAL_NATIVE_NOTICES.txt';sha256=Get-NativeIsarDigest $noticePath}
    packageCount=$inputs.manifest.packages.Count;textCount=$inputs.texts.Count
})
Write-Output $output
