[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate)
. "$PSScriptRoot/native-isar-supplement-inputs.ps1"
$Candidate = [IO.Path]::GetFullPath($Candidate)
$originalDll = Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll')
$originalReceipt = Get-NativeIsarDigest (Join-Path $Candidate 'native-build.json')
$base = Join-Path $NativeIsarRepository 'native/isar-3.3.2'
$vendor = Join-Path $Candidate 'vendor'
$inputs = Get-NativeIsarSupplementInputs $base $vendor
if ($inputs.manifest.packages.Count -ne 8 -or $inputs.texts.Count -ne 9) { throw 'Unexpected source supplement inventory.' }
$standard = @($inputs.texts | Where-Object { $_.descriptor.id -ceq 'standard-MIT' })[0]
if (-not [IO.File]::ReadAllText($standard.path).Contains('Copyright (c) <year> <copyright holders>')) { throw 'Canonical template placeholder was replaced.' }
$output = & "$PSScriptRoot/collect-native-isar-supplements.ps1" -Candidate $Candidate
$noticePath = Join-Path $output 'SUPPLEMENTAL_NATIVE_NOTICES.txt'
$noticeHash = Get-NativeIsarDigest $noticePath
$notice = [IO.File]::ReadAllText($noticePath)
foreach ($package in $inputs.manifest.packages) {
    if (-not $notice.Contains($package.name + '@' + $package.version) -or -not $notice.Contains($package.declaredLicense)) { throw 'Source supplement declaration missing.' }
}
foreach ($text in $inputs.texts) {
    if ((Get-NativeIsarDigest (Join-Path $output $text.descriptor.file)) -cne $text.descriptor.sha256 -or
        -not $notice.Contains([IO.File]::ReadAllText($text.path))) { throw 'Source supplement text incomplete.' }
}
$fixture = Join-Path $NativeIsarRepository ('.local/native-license-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
Copy-Item -LiteralPath $inputs.manifestPath -Destination (Join-Path $fixture 'supplemental-licenses.json')
foreach ($text in $inputs.texts) {
    $destination = Join-Path $fixture $text.descriptor.file
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    Copy-Item -LiteralPath $text.path -Destination $destination
}
$changedPath = Join-Path $fixture $standard.descriptor.file
[IO.File]::AppendAllText($changedPath,'tampered text')
$failed = $false
try { Get-NativeIsarSupplementInputs $fixture $vendor | Out-Null } catch {
    if ($_.Exception.Message -cne 'Supplemental license text hash mismatch.') { throw }
    $failed = $true
}
if (-not $failed) { throw 'Changed license text accepted.' }
Copy-Item -LiteralPath $standard.path -Destination $changedPath -Force
$manifestPath = Join-Path $fixture 'supplemental-licenses.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest.packages[0].registryChecksum = '0' * 64
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
$failed = $false
try { Get-NativeIsarSupplementInputs $fixture $vendor | Out-Null } catch {
    if ($_.Exception.Message -cne 'Supplemental registry checksum mismatch.') { throw }
    $failed = $true
}
if (-not $failed -or (Get-NativeIsarDigest $noticePath) -cne $noticeHash -or
    (Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll')) -cne $originalDll -or
    (Get-NativeIsarDigest (Join-Path $Candidate 'native-build.json')) -cne $originalReceipt) { throw 'Supplement refusal or prior output preservation failed.' }
Write-Output 'NATIVE_SOURCE_SUPPLEMENTS_8_PACKAGES_9_FULL_TEXTS_PASSED'
Write-Output 'NATIVE_SOURCE_SUPPLEMENT_HASH_AND_IDENTITY_REFUSALS_PASSED'
Write-Output $output
