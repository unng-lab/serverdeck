[CmdletBinding()]
param([string]$SourceDirectory='', [string]$Candidate='', [string]$ArchiveCache='', [switch]$Repack, [string]$Fixture='')
. "$PSScriptRoot/native-isar-inputs.ps1"
. "$PSScriptRoot/native-isar-source-archive.ps1"
if ($Repack) {
    $Fixture = [IO.Path]::GetFullPath($Fixture)
    if ([IO.Path]::GetDirectoryName($Fixture) -cne (Join-Path $NativeIsarRepository '.local') -or
        [IO.Path]::GetFileName($Fixture) -cnotmatch '^native-source-package-tests-[a-f0-9]{32}$') { throw 'Expected owned source test fixture.' }
    $indexPath = Join-Path $Fixture 'repack-files.json'
    if ((Get-Item -LiteralPath $indexPath).Length -gt 4MB) { throw 'Repack input inventory exceeds limit.' }
    $extracted = (Get-Content -LiteralPath (Join-Path $Fixture 'extracted-root.txt') -Raw).Trim()
    if ([IO.Path]::GetDirectoryName($extracted) -cne (Join-Path $NativeIsarRepository '.local') -or
        [IO.Path]::GetFileName($extracted) -cnotmatch '^src space-[a-f0-9]{8}$') { throw 'Expected owned spaced extraction root.' }
    $files = @(Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json | ForEach-Object {
        [ordered]@{file=$_.file;path=Join-Path $extracted $_.file;sha256=$_.sha256}
    })
    [Array]::Reverse($files)
    Write-NativeIsarSourceArchive (Join-Path $Fixture 'repacked.zip') $files
    'NATIVE_FULL_SOURCE_REPACK_CHILD_PASSED'
    return
}
if (-not $SourceDirectory -or -not $Candidate -or -not $ArchiveCache) { throw 'SourceDirectory/Candidate/ArchiveCache required.' }
$Candidate = [IO.Path]::GetFullPath($Candidate)
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)
$ArchiveCache = [IO.Path]::GetFullPath($ArchiveCache)
if ([IO.Path]::GetDirectoryName($Candidate) -cne (Join-Path $NativeIsarRepository '.local/native-isar') -or
    [IO.Path]::GetFileName($Candidate) -cnotmatch '^candidate-[a-f0-9]{32}$' -or
    [IO.Path]::GetDirectoryName($SourceDirectory) -cne $Candidate -or
    [IO.Path]::GetFileName($SourceDirectory) -cnotmatch '^sources-[a-f0-9]{32}$') { throw 'Expected owned source package and candidate.' }
$receiptPath = Join-Path $Candidate 'native-build.json'
$build = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
$buildHash = Get-NativeIsarDigest $receiptPath
$dllHash = Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll')
$sourceReceiptPath = Join-Path $SourceDirectory 'native-source-receipt.json'
$sourceReceiptHash = Get-NativeIsarDigest $sourceReceiptPath
$sourceReceipt = Get-Content -LiteralPath $sourceReceiptPath -Raw | ConvertFrom-Json
$zip = Join-Path $SourceDirectory 'NATIVE_SOURCES.zip'
$zipHash = Get-NativeIsarDigest $zip
if ($sourceReceipt.schemaVersion -ne 1 -or $sourceReceipt.state -cne 'sources-collected-unqualified' -or
    $sourceReceipt.distributionReady -ne $false -or $sourceReceipt.buildReceiptSha256 -cne $buildHash -or
    $sourceReceipt.sourceArchive.file -cne 'NATIVE_SOURCES.zip' -or $sourceReceipt.sourceArchive.sha256 -cne $zipHash -or
    $sourceReceipt.sourceArchive.length -ne (Get-Item -LiteralPath $zip).Length) { throw 'Source test receipt mismatch.' }
$Fixture = Join-Path $NativeIsarRepository ('.local/native-source-package-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Fixture) | Out-Null
$extracted = Join-Path $NativeIsarRepository ('.local/src space-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
if ($extracted.Length -gt 80 -or (Test-Path -LiteralPath $extracted)) { throw 'No fresh supported source extraction root.' }
[IO.File]::WriteAllText((Join-Path $Fixture 'extracted-root.txt'),$extracted)
Expand-NativeIsarArchive $zip $extracted zip
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
$index = @{}
try {
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName -cnotmatch '^(source|mdbx|vendor|native|licenses|archives|tools)/|^(source\.materialized-links\.json|mdbx-patch\.json|THIRD_PARTY_NATIVE_NOTICES\.txt|native-notice-inventory\.json|native-dependencies\.json|source-reproduction\.json|REPRODUCE\.txt)$' -or
            $entry.FullName -match '(^|/)\.git(/|$)' -or $entry.FullName.EndsWith('.private.json')) { throw 'Unexpected/private source archive entry.' }
        $stream = $entry.Open()
        try { $index[$entry.FullName] = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() } finally { $stream.Dispose() }
    }
} finally { $archive.Dispose() }
if ($index.Count -ne $sourceReceipt.sourceArchive.fileCount -or $index.Count -ne 8107) { throw 'Source ZIP full inventory mismatch.' }
$recipe = Get-NativeIsarRecipe
foreach ($tree in @(
    @{prefix='source/isar-community-' + $recipe.isar.commit + '/';sha256=$build.inputDigests.source;count=738},
    @{prefix='mdbx/libmdbx-' + $recipe.mdbx.commit + '/';sha256=$build.inputDigests.mdbx;count=192},
    @{prefix='vendor/';sha256=$build.inputDigests.vendor;count=6966}
)) {
    $snapshot = @{}
    foreach ($name in $index.Keys) {
        if ($name.StartsWith($tree.prefix,[StringComparison]::Ordinal)) { $snapshot[$name.Substring($tree.prefix.Length)] = $index[$name] }
    }
    if ($snapshot.Count -ne $tree.count -or (Get-NativeIsarSnapshotDigest $snapshot) -cne $tree.sha256) { throw 'Source ZIP compiled-input tree mismatch.' }
}
if ($index.ContainsKey('mdbx/libmdbx-' + $recipe.mdbx.commit + '/src/version.c') -or
    $index['archives/isar-3.3.2-source.zip'] -cne $recipe.isar.sha256 -or
    $index['archives/libmdbx-source.zip'] -cne $recipe.mdbx.sha256 -or $index['mdbx-patch.json'] -cne $build.patch.sha256 -or
    $index['source-reproduction.json'] -cne $sourceReceipt.reproductionManifestSha256 -or
    $index['native-notice-inventory.json'] -cne $sourceReceipt.noticeInventorySha256 -or
    $index['native-dependencies.json'] -cne $sourceReceipt.graphSha256) { throw 'Source ZIP provenance mismatch.' }
$notices = Get-Content -LiteralPath (Join-Path $extracted 'native-notice-inventory.json') -Raw | ConvertFrom-Json
if ($notices.files.Count -ne 183 -or $notices.packages.Count -ne 91 -or
    $index[$notices.notice.file] -cne $notices.notice.sha256) { throw 'Source ZIP full notice inventory mismatch.' }
foreach ($file in $notices.files) {
    if ($index[$file.file] -cne $file.sha256) { throw 'Source ZIP full notice text mismatch.' }
}
# Cheap actual assembler source-cache negatives run before graph/notice output.
$badCache = Join-Path $Fixture 'bad-cache'
[IO.Directory]::CreateDirectory($badCache) | Out-Null
[IO.File]::WriteAllText((Join-Path $badCache 'isar-3.3.2-source.zip'),'corrupted source archive')
$refused = $false
try { & "$PSScriptRoot/collect-native-isar-sources.ps1" -Candidate $Candidate -SupplementDirectory 'unused' -RustDirectory 'unused' -ArchiveCache $badCache | Out-Null } catch {
    if ($_.Exception.Message -cne 'Native corresponding source archive mismatch.') { throw }
    $refused = $true
}
if (-not $refused) { throw 'Assembler source-cache corruption not refused.' }
$emptyCache = Join-Path $Fixture 'empty-cache'
[IO.Directory]::CreateDirectory($emptyCache) | Out-Null
$refused = $false
try { & "$PSScriptRoot/collect-native-isar-sources.ps1" -Candidate $Candidate -SupplementDirectory 'unused' -RustDirectory 'unused' -ArchiveCache $emptyCache | Out-Null } catch {
    if ($_.Exception.Message -cne 'Missing native input file.') { throw }
    $refused = $true
}
if (-not $refused) { throw 'Assembler missing source not refused.' }
# Mutate only extracted synthetic inputs, restore before concurrent readers.
$manifestPath = Join-Path $extracted 'source-reproduction.json'
$manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
# Validate the documented root budget without invoking compiler/global changes.
$longRoot = Join-Path $Fixture ('long-root-' + ('x' * 40))
$longTools = Join-Path $longRoot 'tools'
[IO.Directory]::CreateDirectory($longTools) | Out-Null
foreach ($name in @('native-isar-inputs.ps1','native-isar-vendor-inputs.ps1','reproduce-native-isar.ps1','build-native-isar.ps1')) {
    Copy-Item -LiteralPath (Join-Path $extracted ('tools/' + $name)) -Destination (Join-Path $longTools $name)
}
foreach ($name in @('reproduce-native-isar.ps1','build-native-isar.ps1')) {
    $refused = $false
    try {
        if ($name -eq 'reproduce-native-isar.ps1') { & (Join-Path $longTools $name) -ToolchainArchiveCache $ArchiveCache | Out-Null }
        else { & (Join-Path $longTools $name) -ArchiveCache $ArchiveCache | Out-Null }
    } catch {
        if ($_.Exception.Message -cne 'Native build repository root exceeds 80 characters.') { throw }
        $refused = $true
    }
    if (-not $refused -or (Test-Path -LiteralPath (Join-Path $longRoot '.local'))) { throw 'Long-root preflight did not refuse before preparation.' }
}
foreach ($variant in @('identity','tool')) {
    $manifest = [Text.UTF8Encoding]::new($false).GetString($manifestBytes) | ConvertFrom-Json
    if ($variant -eq 'identity') { $manifest.product = 'wrong-product' } else { $manifest.tools[0].sha256 = '0' * 64 }
    [IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    $refused = $false
    try { & (Join-Path $extracted 'tools/reproduce-native-isar.ps1') -ToolchainArchiveCache $ArchiveCache | Out-Null } catch {
        $expected = if ($variant -eq 'identity') { 'Native source reproduction identity mismatch.' } else { 'Native source reproduction tool mismatch.' }
        if ($_.Exception.Message -cne $expected) { throw }
        $refused = $true
    } finally { [IO.File]::WriteAllBytes($manifestPath,$manifestBytes) }
    if (-not $refused) { throw 'Reproduction manifest tampering not refused.' }
}
$sourceArchivePath = Join-Path $extracted 'archives/isar-3.3.2-source.zip'
$sourceArchiveBytes = [IO.File]::ReadAllBytes($sourceArchivePath)
$refused = $false
try {
    [IO.File]::WriteAllText($sourceArchivePath,'tampered extracted source archive')
    & (Join-Path $extracted 'tools/reproduce-native-isar.ps1') -ToolchainArchiveCache $ArchiveCache | Out-Null
} catch {
    if ($_.Exception.Message -cne 'Native source reproduction archive mismatch.') { throw }
    $refused = $true
} finally { [IO.File]::WriteAllBytes($sourceArchivePath,$sourceArchiveBytes) }
if (-not $refused) { throw 'Reproduction source archive tampering not refused.' }
$orderedNames = [string[]]@($index.Keys)
[Array]::Sort($orderedNames,[StringComparer]::Ordinal)
$repackFiles = @($orderedNames | ForEach-Object { [ordered]@{file=$_;sha256=$index[$_]} })
[IO.File]::WriteAllText((Join-Path $Fixture 'repack-files.json'),($repackFiles | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
$start = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
$start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
foreach ($argument in @('-NoProfile','-File',$PSCommandPath,'-Repack','-Fixture',$Fixture)) { $start.ArgumentList.Add($argument) }
$child = [Diagnostics.Process]::new(); $child.StartInfo=$start; $started=$false
try {
    $started=$child.Start()
    if (-not $started) { throw 'Cannot start source repack child.' }
    $stdout=$child.StandardOutput.ReadToEndAsync(); $stderr=$child.StandardError.ReadToEndAsync()
    $encodedBefore = [Environment]::GetEnvironmentVariable('CARGO_ENCODED_RUSTFLAGS','Process')
    try {
        $env:CARGO_ENCODED_RUSTFLAGS = '--serverdeck-invalid-inherited-encoded-flag'
        $repeat = & (Join-Path $extracted 'tools/reproduce-native-isar.ps1') -ToolchainArchiveCache $ArchiveCache
        if ($env:CARGO_ENCODED_RUSTFLAGS -cne '--serverdeck-invalid-inherited-encoded-flag') { throw 'Encoded compiler flags were not restored.' }
    } finally { [Environment]::SetEnvironmentVariable('CARGO_ENCODED_RUSTFLAGS',$encodedBefore,'Process') }
    $repeatReceipt = Get-Content -LiteralPath (Join-Path $repeat 'native-build.json') -Raw | ConvertFrom-Json
    if ($repeatReceipt.vendorAcquisition -cne 'verified-local-snapshot' -or -not $repeatReceipt.offlineCompilation -or
        $repeatReceipt.compilerFlagTransport -cne 'CARGO_ENCODED_RUSTFLAGS-U001F' -or
        $repeatReceipt.state -cne 'built-unqualified' -or $repeatReceipt.distributionReady -ne $false -or
        $repeatReceipt.inputDigests.source -cne $build.inputDigests.source -or $repeatReceipt.inputDigests.vendor -cne $build.inputDigests.vendor -or
        $repeatReceipt.inputDigests.mdbx -cne $build.inputDigests.mdbx -or $repeatReceipt.patch.sha256 -cne $build.patch.sha256 -or
        (Test-Path -LiteralPath (Join-Path $repeat 'vendor.log'))) { throw 'Standalone source reproduction evidence mismatch.' }
    if (-not $child.WaitForExit(60000)) { throw 'Full source repack child did not complete.' }
    [IO.File]::WriteAllText((Join-Path $Fixture 'repack.stdout.txt'),$stdout.GetAwaiter().GetResult())
    [IO.File]::WriteAllText((Join-Path $Fixture 'repack.stderr.txt'),$stderr.GetAwaiter().GetResult())
    if ($child.ExitCode -ne 0 -or (Get-NativeIsarDigest (Join-Path $Fixture 'repacked.zip')) -cne $zipHash) { throw 'Full source ZIP cross-process repack mismatch.' }
} finally {
    try { if ($started -and -not $child.HasExited) { $child.Kill($true); if (-not $child.WaitForExit(10000)) { throw 'Owned repack child termination unconfirmed.' } } } finally { $child.Dispose() }
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ServerDeckSourceVersionProbe {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
  public delegate IntPtr Version();
}
'@
$library = [ServerDeckSourceVersionProbe]::LoadLibraryExW((Join-Path $repeat 'libisar.dll'),[IntPtr]::Zero,0x900)
if ($library -eq [IntPtr]::Zero) { throw 'Reproduced native library failed to load.' }
try {
    foreach ($item in @(@{name='isar_version';expected='3.3.2'},@{name='isar_mdbx_version';expected='v0.13.8-temp-upstream-fix'})) {
        $pointer = [Runtime.InteropServices.NativeLibrary]::GetExport($library,$item.name)
        $function = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($pointer,[ServerDeckSourceVersionProbe+Version])
        $version = [Runtime.InteropServices.Marshal]::PtrToStringUTF8($function.Invoke())
        if ($version -cne $item.expected) { throw 'Reproduced native library version mismatch.' }
    }
} finally { [Runtime.InteropServices.NativeLibrary]::Free($library) }
if ((Get-NativeIsarDigest $receiptPath) -cne $buildHash -or (Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll')) -cne $dllHash -or
    (Get-NativeIsarDigest $sourceReceiptPath) -cne $sourceReceiptHash -or (Get-NativeIsarDigest $zip) -cne $zipHash) { throw 'Source test changed prior artifacts.' }
'NATIVE_COMPLETE_SOURCE_8107_FILES_183_NOTICES_FULL_REPACK_AND_STANDALONE_OFFLINE_BUILD_PASSED'
'NATIVE_SOURCE_SPACED_ROOT_ENCODED_FLAG_RESTORATION_AND_LONG_ROOT_PREFLIGHT_PASSED'
$repeat
$Fixture
