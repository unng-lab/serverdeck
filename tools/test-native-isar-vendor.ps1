[CmdletBinding()]
param([Parameter(Mandatory)][string]$ArchiveCache, [Parameter(Mandatory)][string]$SuccessfulCandidate)
. "$PSScriptRoot/native-isar-inputs.ps1"
. "$PSScriptRoot/native-isar-vendor-inputs.ps1"
$SuccessfulCandidate = [IO.Path]::GetFullPath($SuccessfulCandidate)
if ([IO.Path]::GetDirectoryName($SuccessfulCandidate) -cne (Join-Path $NativeIsarRepository '.local/native-isar') -or
    [IO.Path]::GetFileName($SuccessfulCandidate) -cnotmatch '^candidate-[a-f0-9]{32}$') { throw 'Expected owned native candidate.' }
$receiptPath = Join-Path $SuccessfulCandidate 'native-build.json'
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
$receiptHash = Get-NativeIsarDigest $receiptPath
$dllHash = Get-NativeIsarDigest (Join-Path $SuccessfulCandidate 'libisar.dll')
$vendor = Join-Path $SuccessfulCandidate 'vendor'
$snapshot = Get-NativeIsarVendorSnapshot $vendor $receipt.inputDigests.vendor
if ($snapshot.Count -ne 6966) { throw 'Unexpected real vendor inventory.' }
$fixture = Join-Path $NativeIsarRepository ('.local/native-isar-vendor-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$small = Join-Path $fixture 'small'
[IO.Directory]::CreateDirectory($small) | Out-Null
$inputPath = Join-Path $small 'input.txt'
[IO.File]::WriteAllText($inputPath,'original')
$smallSnapshot = @{'input.txt' = Get-NativeIsarDigest $inputPath}
$smallHash = Get-NativeIsarSnapshotDigest $smallSnapshot
Copy-NativeIsarVendorSnapshot $small (Join-Path $fixture 'copy') $smallHash $smallSnapshot
foreach ($variant in @('changed','added','missing')) {
    [IO.File]::WriteAllText($inputPath,'original')
    $extra = Join-Path $small 'extra.txt'
    if ($variant -eq 'changed') { [IO.File]::WriteAllText($inputPath,'changed') }
    if ($variant -eq 'added') { [IO.File]::WriteAllText($extra,'extra') }
    if ($variant -eq 'missing') { Remove-Item -LiteralPath $inputPath }
    $refused = $false
    try { Get-NativeIsarVendorSnapshot $small $smallHash | Out-Null } catch {
        if ($_.Exception.Message -cne 'Native vendor snapshot digest mismatch.') { throw }
        $refused = $true
    }
    if (-not $refused) { throw 'Vendor tamper not refused.' }
    if (Test-Path -LiteralPath $extra) { Remove-Item -LiteralPath $extra }
}
$refused = $false
try { & "$PSScriptRoot/build-native-isar.ps1" -ArchiveCache $ArchiveCache -VendorSource $vendor -VendorSha256 ('0' * 64) | Out-Null } catch {
    if ($_.Exception.Message -cne 'Native vendor snapshot digest mismatch.') { throw }
    $refused = $true
}
if (-not $refused) { throw 'Bad vendor digest did not refuse build.' }
$relativeVendor = [IO.Path]::GetRelativePath((Get-Location).ProviderPath,$vendor)
if ([IO.Path]::IsPathRooted($relativeVendor)) { throw 'Relative vendor regression requires same-volume caller.' }
$repeat = & "$PSScriptRoot/build-native-isar.ps1" -ArchiveCache $ArchiveCache -VendorSource $relativeVendor -VendorSha256 $receipt.inputDigests.vendor
$repeatReceipt = Get-Content -LiteralPath (Join-Path $repeat 'native-build.json') -Raw | ConvertFrom-Json
if ($repeatReceipt.vendorAcquisition -cne 'verified-local-snapshot' -or -not $repeatReceipt.offlineCompilation -or
    $repeatReceipt.inputDigests.vendor -cne $receipt.inputDigests.vendor -or
    $repeatReceipt.inputDigests.source -cne $receipt.inputDigests.source -or
    $repeatReceipt.state -cne 'built-unqualified' -or $repeatReceipt.distributionReady -ne $false -or
    (Test-Path -LiteralPath (Join-Path $repeat 'vendor.log')) -or
    (Test-Path -LiteralPath (Join-Path $repeat 'vendor-config.original.toml'))) { throw 'Offline repeat build evidence mismatch.' }
if ((Get-NativeIsarDigest $receiptPath) -cne $receiptHash -or
    (Get-NativeIsarDigest (Join-Path $SuccessfulCandidate 'libisar.dll')) -cne $dllHash) { throw 'Prior build changed.' }
Get-NativeIsarVendorSnapshot $vendor $receipt.inputDigests.vendor | Out-Null
'NATIVE_VENDOR_COMPLETE_LOCAL_SNAPSHOT_OFFLINE_REPEAT_AND_TAMPER_REFUSAL_PASSED'
'NATIVE_VENDOR_CALLER_RELATIVE_PATH_REPEAT_PASSED'
$repeat
$fixture
