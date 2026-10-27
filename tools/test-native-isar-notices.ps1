[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate, [Parameter(Mandatory)][string]$SupplementDirectory, [Parameter(Mandatory)][string]$RustDirectory)
. "$PSScriptRoot/native-isar-inputs.ps1"
$Candidate = [IO.Path]::GetFullPath($Candidate)
$dllHash = Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll')
$buildHash = Get-NativeIsarDigest (Join-Path $Candidate 'native-build.json')
$first = & "$PSScriptRoot/collect-native-isar-notices.ps1" -Candidate $Candidate -SupplementDirectory $SupplementDirectory -RustDirectory $RustDirectory
$pwsh = Join-Path $PSHOME 'pwsh.exe'
$second = & $pwsh -NoProfile -File "$PSScriptRoot/collect-native-isar-notices.ps1" -Candidate $Candidate -SupplementDirectory $SupplementDirectory -RustDirectory $RustDirectory
if ($LASTEXITCODE -ne 0) { throw 'Separate-process aggregate native notice export failed.' }
foreach ($name in @('native-notice-inventory.json','THIRD_PARTY_NATIVE_NOTICES.txt')) {
    if ((Get-NativeIsarDigest (Join-Path $first $name)) -cne (Get-NativeIsarDigest (Join-Path $second $name))) { throw 'Aggregate native notices are nondeterministic.' }
}
$inventory = Get-Content (Join-Path $first 'native-notice-inventory.json') -Raw | ConvertFrom-Json
$noticePath = Join-Path $first 'THIRD_PARTY_NATIVE_NOTICES.txt'
$noticeHash = Get-NativeIsarDigest $noticePath
$notice = [IO.File]::ReadAllText($noticePath)
if ($inventory.state -cne 'notices-collected-unqualified' -or $inventory.distributionReady -ne $false -or
    $inventory.packages.Count -ne 91 -or $inventory.files.Count -ne 183 -or $inventory.buildReceiptSha256 -cne $buildHash) { throw 'Incomplete aggregate native inventory.' }
foreach ($package in $inventory.packages) {
    if (-not $notice.Contains($package.id + ' | declared ' + $package.declaredLicense)) { throw 'Vendor declaration missing from aggregate native notice.' }
}
foreach ($file in $inventory.files) {
    $path = Join-Path $first $file.file
    if ((Get-NativeIsarDigest $path) -cne $file.sha256 -or (Get-Item $path).Length -ne $file.length -or -not $notice.Contains($file.file)) { throw 'Aggregate native copied material mismatch.' }
    if (-not $file.file.EndsWith('.html') -and -not $notice.Contains([IO.File]::ReadAllText($path))) { throw 'Aggregate native full text missing.' }
}
if (-not ($inventory.files | Where-Object file -CEQ 'licenses/vendor/regex-syntax/src/unicode_tables/LICENSE-UNICODE')) { throw 'Nested Unicode notice omitted.' }
if ($notice.Contains($NativeIsarRepository) -or $notice -match 'file:///') { throw 'Machine paths leaked into aggregate native notice.' }
$fixture = Join-Path $Candidate ('rust-material-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $RustDirectory -Recurse -File) {
    $relative = [IO.Path]::GetRelativePath($RustDirectory,$file.FullName)
    $destination = Join-Path $fixture $relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination
}
$manifest = Get-Content (Join-Path $fixture 'rust-license-material.json') -Raw | ConvertFrom-Json
$changed = Join-Path $fixture $manifest.files[0].destination
[IO.File]::AppendAllText($changed,'tampered material')
$failed = $false
try { & "$PSScriptRoot/collect-native-isar-notices.ps1" -Candidate $Candidate -SupplementDirectory $SupplementDirectory -RustDirectory $fixture | Out-Null } catch {
    if ($_.Exception.Message -cne 'Native notice text hash mismatch.') { throw }
    $failed = $true
}
if (-not $failed -or (Get-NativeIsarDigest $noticePath) -cne $noticeHash -or
    (Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll')) -cne $dllHash -or
    (Get-NativeIsarDigest (Join-Path $Candidate 'native-build.json')) -cne $buildHash) { throw 'Aggregate native refusal did not preserve prior output.' }
Write-Output 'NATIVE_NOTICES_91_VENDOR_PACKAGES_183_EXACT_FILES_NESTED_UNICODE_PASSED'
Write-Output 'NATIVE_NOTICES_CROSS_PROCESS_DETERMINISM_AND_TAMPER_REFUSAL_PASSED'
Write-Output $first
