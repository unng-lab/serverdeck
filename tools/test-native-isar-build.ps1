[CmdletBinding()]
param([Parameter(Mandatory)][string]$ArchiveCache, [Parameter(Mandatory)][string]$SuccessfulCandidate)
. "$PSScriptRoot/native-isar-inputs.ps1"
$SuccessfulCandidate = [IO.Path]::GetFullPath($SuccessfulCandidate)
$candidateParent = Join-Path $NativeIsarRepository '.local/native-isar'
if ([IO.Path]::GetDirectoryName($SuccessfulCandidate) -cne $candidateParent -or
    [IO.Path]::GetFileName($SuccessfulCandidate) -cnotmatch '^candidate-[a-f0-9]{32}$') { throw 'Expected an owned native candidate.' }
$receiptPath = Join-Path $SuccessfulCandidate 'native-build.json'
$dllPath = Join-Path $SuccessfulCandidate 'libisar.dll'
$receiptDigest = Get-NativeIsarDigest $receiptPath
$dllDigest = Get-NativeIsarDigest $dllPath
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
if ($receipt.state -cne 'built-unqualified' -or $receipt.distributionReady -ne $false -or $receipt.dll.sha256 -cne $dllDigest) { throw 'Invalid prior build receipt.' }
$fixture = Join-Path $NativeIsarRepository ('.local/native-isar-build-tests-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $fixture
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$badCache = Join-Path $fixture 'bad-cache'
[IO.Directory]::CreateDirectory($badCache) | Out-Null
$badArchive = Join-Path $badCache 'isar-3.3.2-source.zip'
[IO.File]::WriteAllText($badArchive,'deliberately invalid archive')
$badDigest = Get-NativeIsarDigest $badArchive
$failed = $false
try { & "$PSScriptRoot/build-native-isar.ps1" -ArchiveCache $badCache | Out-Null } catch {
    if ($_.Exception.Message -cne 'Cached native archive digest mismatch.') { throw }
    $failed = $true
}
if (-not $failed -or (Get-NativeIsarDigest $badArchive) -cne $badDigest) { throw 'Archive refusal failed.' }
# Child-only environment fault: do not modify the OS installation or parent environment.
$pwsh = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $pwsh -PathType Leaf)) { throw 'Current PowerShell executable missing.' }
$start = [Diagnostics.ProcessStartInfo]::new($pwsh)
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.ArgumentList.Add('-NoProfile')
$start.ArgumentList.Add('-File')
$start.ArgumentList.Add((Join-Path $PSScriptRoot 'build-native-isar.ps1'))
$start.ArgumentList.Add('-ArchiveCache')
$start.ArgumentList.Add([IO.Path]::GetFullPath($ArchiveCache))
$start.Environment['ProgramFiles(x86)'] = Join-Path $fixture 'missing-msvc-installation'
$child = [Diagnostics.Process]::new()
$child.StartInfo = $start
$started = $false
try {
    $started = $child.Start()
    if (-not $started) { throw 'Cannot start owned compiler-refusal child.' }
    $stdoutTask = $child.StandardOutput.ReadToEndAsync()
    $stderrTask = $child.StandardError.ReadToEndAsync()
    if (-not $child.WaitForExit(180000)) {
        $child.Kill($true)
        if (-not $child.WaitForExit(10000)) { throw 'Compiler-refusal child termination unconfirmed.' }
        throw 'Compiler-refusal child timed out.'
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $fixture 'compiler.stdout.txt'),$stdout)
    [IO.File]::WriteAllText((Join-Path $fixture 'compiler.stderr.txt'),$stderr)
    if ($child.ExitCode -eq 0 -or $stderr -notmatch 'MSVC discovery prerequisite missing' -or $stdout.Trim()) {
        throw 'Missing compiler did not refuse without publishing a candidate.'
    }
} finally {
    try {
        if ($started -and -not $child.HasExited) {
            $child.Kill($true)
            if (-not $child.WaitForExit(10000)) { throw 'Owned compiler-refusal child termination unconfirmed.' }
        }
    } finally { $child.Dispose() }
}
if ((Get-NativeIsarDigest $receiptPath) -cne $receiptDigest -or (Get-NativeIsarDigest $dllPath) -cne $dllDigest) {
    throw 'Failure changed the prior native build.'
}
$poison = [ordered]@{
    BINDGEN_EXTRA_CLANG_ARGS='--serverdeck-invalid-clang-flag'
    BINDGEN_EXTRA_CLANG_ARGS_x86_64_pc_windows_msvc='--serverdeck-invalid-target-clang-flag'
    HOST_CC='serverdeck-nonexistent-host-compiler'
    TARGET_CC='serverdeck-nonexistent-target-compiler'
    TARGET_CFLAGS='/serverdeck-invalid-target-flag'
    HOST_CFLAGS='/serverdeck-invalid-host-flag'
    ARFLAGS='--serverdeck-invalid-archiver-flag'
    AR_x86_64_pc_windows_msvc='serverdeck-nonexistent-archiver'
    CL='/serverdeck-invalid-cl-flag'
    _CL_='/serverdeck-invalid-trailing-cl-flag'
    LINK='/serverdeck-invalid-link-flag'
    _LINK_='/serverdeck-invalid-trailing-link-flag'
    CRATE_CC_NO_DEFAULTS='1'
    CC_FORCE_DISABLE='1'
    CXXSTDLIB='serverdeck-nonexistent-runtime'
    CARGO_ENCODED_RUSTFLAGS='--serverdeck-invalid-rust-flag'
}
$originalEnvironment = @{}
foreach ($key in @($poison.Keys) + @('ComSpec')) { $originalEnvironment[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
try {
    foreach ($key in $poison.Keys) { [Environment]::SetEnvironmentVariable($key,$poison[$key],'Process') }
    $isolatedCandidate = & "$PSScriptRoot/build-native-isar.ps1" -ArchiveCache $ArchiveCache
    $isolatedReceipt = Get-Content -LiteralPath (Join-Path $isolatedCandidate 'native-build.json') -Raw | ConvertFrom-Json
    if ($isolatedReceipt.state -cne 'built-unqualified' -or -not $isolatedReceipt.immutableInputsVerified) { throw 'Poisoned environment build did not complete.' }
    foreach ($key in $poison.Keys) {
        if ([Environment]::GetEnvironmentVariable($key,'Process') -cne $poison[$key]) { throw 'Compiler override was not restored after success.' }
    }
    [Environment]::SetEnvironmentVariable('ComSpec',(Join-Path $fixture 'missing-command-interpreter.exe'),'Process')
    $scopedFailure = $false
    try { & "$PSScriptRoot/build-native-isar.ps1" -ArchiveCache $ArchiveCache | Out-Null } catch {
        if ($_.Exception.Message -cne 'Native command interpreter prerequisite missing.') { throw }
        $scopedFailure = $true
    }
    if (-not $scopedFailure) { throw 'Expected controlled scoped build refusal.' }
    foreach ($key in $poison.Keys) {
        if ([Environment]::GetEnvironmentVariable($key,'Process') -cne $poison[$key]) { throw 'Compiler override was not restored after refusal.' }
    }
} finally {
    foreach ($key in $originalEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key,$originalEnvironment[$key],'Process') }
}
if ((Get-NativeIsarDigest $receiptPath) -cne $receiptDigest -or (Get-NativeIsarDigest $dllPath) -cne $dllDigest) { throw 'Environment regression changed prior output.' }
Write-Output 'NATIVE_BUILD_HASH_AND_CONTROLLED_MISSING_COMPILER_REFUSALS_PASSED'
Write-Output 'NATIVE_PRIOR_UNQUALIFIED_OUTPUT_PRESERVED'
Write-Output 'NATIVE_BUILD_POISONED_OVERRIDES_CLEARED_AND_RESTORED_ON_SUCCESS_AND_REFUSAL'
Write-Output $isolatedCandidate
Write-Output $fixture
