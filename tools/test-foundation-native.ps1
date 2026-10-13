[CmdletBinding()]
param([switch]$DisposableEnvironment, [ValidateSet('All', 'WorkspaceLifecycle', 'CoreStorage', 'CommitRecovery', 'ApiCommitRecovery', 'InitializationRecovery', 'SecretMarkers', 'SecretMarkersUnsafeAcl')][string]$Scenario = 'All')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Scenario -eq 'All') {
    if (-not $DisposableEnvironment) { throw 'Native acceptance requires an explicitly prepared disposable Windows VM/user.' }
    throw 'Full native acceptance is incomplete (T038–T043); select an implemented scenario explicitly.'
}
. "$PSScriptRoot/foundation-sdk.ps1"
if ($Scenario -eq 'SecretMarkersUnsafeAcl' -and -not $DisposableEnvironment) { throw 'Unsafe ACL acceptance requires a prepared disposable environment; the previous denied operation is deferred.' }
. "$PSScriptRoot/native-probe-process.ps1"
function Assert-NativeFixturePath {
    param([string]$Path)
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($FoundationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($resolved))).DriveType -ne [IO.DriveType]::Fixed) { throw 'Unsafe native fixture path.' }
    $component = $resolved
    while ($component) {
        if (Test-Path -LiteralPath $component) {
            if ((Get-Item -LiteralPath $component -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unsafe native fixture path.' }
        }
        $component = [IO.Path]::GetDirectoryName($component)
    }
}
# The retained Process instance owns the child handle, not a PID discovered
# later. All launch/timeout cleanup stays inside this new verified fixture.
function Invoke-NativeFixtureProbe {
    param([string]$Executable, [string[]]$Arguments, [string]$Name, [ValidateSet(180,360)][int]$BudgetSeconds = 180, [switch]$CrashAtBoundary)
    Assert-NativeFixturePath $Executable
    if (-not ([IO.Path]::GetFullPath($Executable)).StartsWith($fixtureRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Probe executable outside owned fixture.' }
    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $fixtureRoot
    $start.Environment['LOCALAPPDATA'] = (Join-Path $fixtureRoot 'normal-flag-profile')
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::new()
    $child.StartInfo = $start
    $started = $false
    try {
        if (-not $child.Start()) { throw 'Native probe start failed.' }
        $started = $true
        $heldHandle = $child.Handle
        $errors = $child.StandardError.ReadToEndAsync()
        if ($CrashAtBoundary) {
            $boundaryWatch = [Diagnostics.Stopwatch]::StartNew()
            $lines = @()
            do {
                $remaining = 30000 - [int]$boundaryWatch.ElapsedMilliseconds
                if ($remaining -le 0 -or $lines.Count -ge 8) { throw 'Crash boundary deadline exceeded.' }
                $lineTask = $child.StandardOutput.ReadLineAsync()
                if (-not $lineTask.Wait($remaining)) { throw 'Crash boundary deadline exceeded.' }
                $line = $lineTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    [IO.File]::WriteAllText((Join-Path $fixtureRoot "$Name.stdout.txt"), ($lines -join "`n"), [Text.UTF8Encoding]::new($false))
                    $captureRemaining = [Math]::Max(1, 30000 - [int]$boundaryWatch.ElapsedMilliseconds)
                    $failureText = if ($errors.Wait($captureRemaining)) { $errors.GetAwaiter().GetResult() } else { 'TEST_DIAGNOSTIC_CAPTURE_INCOMPLETE' }
                    [IO.File]::WriteAllText((Join-Path $fixtureRoot "$Name.stderr.txt"), $failureText, [Text.UTF8Encoding]::new($false))
                    throw 'Crash boundary missing.'
                }
                if ($line.Length -gt 4096) { throw 'Crash boundary oversized.' }
                $lines += $line
            } while ($line -ne 'CRASH_BOUNDARY')
            if ($child.HasExited -or $child.MainModule.FileName -ne $Executable) { throw 'Crash child identity or lifetime mismatch.' }
            $child.Kill()
            if (-not $child.WaitForExit(10000)) { throw 'Crash child termination incomplete.' }
            $tail = $child.StandardOutput.ReadToEndAsync().GetAwaiter().GetResult()
            $text = ($lines -join "`n") + "`n" + $tail
            if ($child.ExitCode -eq 0) { throw 'Crash child exited successfully.' }
        } else {
            $output = $child.StandardOutput.ReadToEndAsync()
            if (-not $child.WaitForExit($BudgetSeconds * 1000)) { throw 'Native probe deadline expired.' }
            $text = $output.GetAwaiter().GetResult()
        }
        $errorText = $errors.GetAwaiter().GetResult()
        if ($text.Length -gt 4096 -or $errorText.Length -gt 4096) { throw 'Native probe output limit exceeded.' }
        [IO.File]::WriteAllText((Join-Path $fixtureRoot "$Name.stdout.txt"), $text, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $fixtureRoot "$Name.stderr.txt"), $errorText, [Text.UTF8Encoding]::new($false))
        return @{ code = $child.ExitCode; output = $text.Trim(); error = $errorText.Trim() }
    } finally {
        Close-NativeFixtureChild $child $started
    }
}
& "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $FoundationRoot ('.local/native-acceptance-' + [Guid]::NewGuid().ToString('N'))))
Assert-NativeFixturePath $fixtureRoot
if (Test-Path -LiteralPath $fixtureRoot) { throw 'Native fixture already exists.' }
# Create with the same exact protected SDDL as the native adapter. Set-Acl
# retains the auto-inherited control bit and is not an equivalent descriptor.
if (-not ('ServerDeckNativeFixtureDirectory' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ServerDeckNativeFixtureDirectory {
    [StructLayout(LayoutKind.Sequential)]
    private struct SecurityAttributes { public uint length; public IntPtr descriptor; public int inherit; }
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string text, uint revision, out IntPtr descriptor, out uint size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateDirectory(string path, ref SecurityAttributes attributes);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);
    public static void Create(string path, string sid) {
        IntPtr descriptor;
        uint size;
        if (!ConvertStringSecurityDescriptorToSecurityDescriptor("O:" + sid + "D:P(A;;FA;;;" + sid + ")(A;;FA;;;SY)", 1, out descriptor, out size))
            throw new InvalidOperationException("Native fixture descriptor unavailable.");
        try {
            var attributes = new SecurityAttributes { length = (uint)Marshal.SizeOf<SecurityAttributes>(), descriptor = descriptor, inherit = 0 };
            if (!CreateDirectory(path, ref attributes)) throw new InvalidOperationException("Native fixture creation unavailable.");
        } finally { LocalFree(descriptor); }
    }
}
"@
}
$fixtureIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
try { $fixtureSid = $fixtureIdentity.User.Value } finally { $fixtureIdentity.Dispose() }
[ServerDeckNativeFixtureDirectory]::Create($fixtureRoot, $fixtureSid)
$normalBundle = Join-Path $fixtureRoot 'normal-bundle'
$testBundle = Join-Path $fixtureRoot 'test-bundle'
Copy-Item -LiteralPath (Join-Path $FoundationRoot 'build/windows/x64/runner/Debug') -Destination $normalBundle -Recurse
$normalManifestPath = Join-Path $normalBundle 'foundation.manifest.json'
$normalManifest = Get-Content -LiteralPath $normalManifestPath -Raw | ConvertFrom-Json
if ($normalManifest.testOnly -ne $false -or $normalManifest.configuration -ne 'Debug') { throw 'Normal bundle required.' }
$normalManifest.appRoot = $normalBundle
[IO.File]::WriteAllText($normalManifestPath, ($normalManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
& "$PSScriptRoot/build-locald.ps1" -OutputDirectory $testBundle -TestBuild -TestFixtureRoot $fixtureRoot
foreach ($name in @('serverdeck.exe', 'libisar.dll')) { Copy-Item -LiteralPath (Join-Path $normalBundle $name) -Destination (Join-Path $testBundle $name) }
$testManifest = $normalManifest | ConvertTo-Json -Depth 5 | ConvertFrom-Json
$testManifest.testOnly = $true
$testManifest.appRoot = $testBundle
foreach ($name in @('serverdeck.exe', 'locald.exe', 'libisar.dll')) { $testManifest.sha256.$name = (Get-FileHash -LiteralPath (Join-Path $testBundle $name) -Algorithm SHA256).Hash.ToLowerInvariant() }
$testManifestPath = Join-Path $testBundle 'foundation.manifest.json'
[IO.File]::WriteAllText($testManifestPath, ($testManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$normalExecutable = Join-Path $normalBundle 'locald.exe'
$testExecutable = Join-Path $testBundle 'locald.exe'
foreach ($testOnly in @($false, $true)) {
    $normalManifest.testOnly = $testOnly
    [IO.File]::WriteAllText($normalManifestPath, ($normalManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    foreach ($flag in @('--scenario', '--test-root', '--failpoint', '--auth', '--test-client')) {
        $probe = Invoke-NativeFixtureProbe $normalExecutable @('--workspace', 'default', '--app-root', $normalBundle, $flag, 'workspace-lifecycle') ("normal-$testOnly-" + $flag.TrimStart('-'))
        if ($probe.code -ne 1 -or $probe.output -or $probe.error -ne 'PREREQUISITE_UNAVAILABLE' -or (Test-Path -LiteralPath (Join-Path $fixtureRoot 'normal-flag-profile'))) { throw 'Normal executable accepted test controls or touched profile.' }
    }
}
$normalManifest.testOnly = $false
[IO.File]::WriteAllText($normalManifestPath, ($normalManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$probe = Invoke-NativeFixtureProbe $testExecutable @('--test-root', $fixtureRoot) 'test-root-override'
if ($probe.code -ne 1 -or $probe.error -ne 'TEST_BUILD_UNBOUND' -or $probe.output) { throw 'Runtime whitelist override accepted.' }
$testManifest.testOnly = $false
[IO.File]::WriteAllText($testManifestPath, ($testManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario', 'workspace-lifecycle') 'test-normal-manifest'
if ($probe.code -ne 1 -or $probe.error -ne 'TEST_SCENARIO_FAILED' -or $probe.output) { throw 'Test executable accepted normal manifest.' }
$testManifest.testOnly = $true
[IO.File]::WriteAllText($testManifestPath, ($testManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$foreignExecutable = Join-Path $testBundle 'foreign-locald.exe'
Copy-Item -LiteralPath $testExecutable -Destination $foreignExecutable
$probe = Invoke-NativeFixtureProbe $foreignExecutable @('--scenario', 'workspace-lifecycle') 'test-foreign-image'
if ($probe.code -ne 1 -or $probe.error -ne 'TEST_SCENARIO_FAILED' -or $probe.output -or (Test-Path -LiteralPath (Join-Path $fixtureRoot 'cases'))) { throw 'Foreign test image accepted or negative probes wrote private state.' }
if ($Scenario -in @('SecretMarkers','SecretMarkersUnsafeAcl')) {
    foreach ($phase in @('secret-markers','verify-secret-markers')) {
        $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario',$phase) $phase
        $proof = if ($phase -eq 'secret-markers') { 'PRIVATE_MARKER_PERSISTENCE_PROVED' } else { 'PRIVATE_MARKER_REOPEN_PROVED' }
        $required = @($proof,('COMPILED_'+$phase.ToUpperInvariant().Replace('-','_')+'_PROVED'))
        $allowed = $required + @('IsarCore using libmdbx: v0.13.8-temp-upstream-fix')
        $lines = @($probe.output -split '\r?\n')
        if ($probe.code -ne 0 -or $probe.error -or @($lines | Where-Object { $_ -notin $allowed }).Count) { throw 'Private marker phase failed.' }
        foreach ($marker in $required) { if (@($lines | Where-Object { $_ -eq $marker }).Count -ne 1) { throw 'Private marker proof absent or repeated.' } }
        $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario',$phase) ("used-$phase")
        if ($probe.code -ne 1 -or $probe.output -or $probe.error -ne 'TEST_FIXTURE_USED') { throw 'Private marker phase reused.' }
    }
    $unsafeAclRejected = $false
    if ($Scenario -eq 'SecretMarkersUnsafeAcl') {
    $unsafeCase = 'secret-markers-unsafe-acl'
    $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario',$unsafeCase) $unsafeCase
    $lines = @($probe.output -split '\r?\n')
    $required = @('PRIVATE_MARKER_PERSISTENCE_PROVED','COMPILED_SECRET_MARKERS_UNSAFE_ACL_PROVED')
    $allowed = $required + @('IsarCore using libmdbx: v0.13.8-temp-upstream-fix')
    if ($probe.code -ne 0 -or $probe.error -or @($lines | Where-Object { $_ -notin $allowed }).Count) { throw 'Unsafe ACL fixture writer failed.' }
    foreach ($marker in $required) { if (@($lines | Where-Object { $_ -eq $marker }).Count -ne 1) { throw 'Unsafe ACL writer marker absent or repeated.' } }
    $unsafeFile = Join-Path $fixtureRoot "cases/$unsafeCase/ServerDeckNext/v1/workspaces/default/workspace.isar"
    Assert-NativeFixturePath $unsafeFile
    $beforeHash = (Get-FileHash -LiteralPath $unsafeFile -Algorithm SHA256).Hash
    $unsafeAcl = Get-Acl -LiteralPath $unsafeFile
    $unsafeAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),[Security.AccessControl.FileSystemRights]::Read,[Security.AccessControl.AccessControlType]::Allow))
    Set-Acl -LiteralPath $unsafeFile -AclObject $unsafeAcl
    $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario',"verify-$unsafeCase") "verify-$unsafeCase"
    if ($probe.code -ne 1 -or $probe.output -or $probe.error -ne 'TEST_SCENARIO_FAILED' -or (Get-FileHash -LiteralPath $unsafeFile -Algorithm SHA256).Hash -ne $beforeHash) { throw 'Unsafe ACL accepted or database bytes changed.' }
    foreach ($used in @($unsafeCase,"verify-$unsafeCase")) {
        $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario',$used) ("used-$used")
        if ($probe.code -ne 1 -or $probe.output -or $probe.error -ne 'TEST_FIXTURE_USED') { throw 'Unsafe ACL phase reused.' }
    }
    $unsafeAclRejected = $true
    }
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'accepted.json'), (@{ format=1; scenario='compiled-secret-markers'; persisted=$true; freshProcessVerified=$true; unsafeAclRejected=$unsafeAclRejected; normalControlsRejected=10; boundTestExecutable=$true } | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Write-Output 'COMPILED_SECRET_MARKERS_ACCEPTED'
    return
}
if ($Scenario -in @('CommitRecovery','ApiCommitRecovery','InitializationRecovery')) {
    $recoveryCases = [ordered]@{
        'commit-before' = 'CRASH_BOUNDARY'
        'commit-after' = 'CRASH_BOUNDARY'
        'native-failure' = 'UNKNOWN_NATIVE_FAILURE_BLOCKED'
        'dpapi-availability' = 'DPAPI_FAILURE_LATCHED_AND_REOPENED'
    }
    if ($Scenario -eq 'InitializationRecovery') {
        $recoveryCases = [ordered]@{
            'init-staging-created' = 'CRASH_BOUNDARY'
            'init-key-flushed' = 'CRASH_BOUNDARY'
            'init-manifest-flushed' = 'CRASH_BOUNDARY'
            'init-native-files-created' = 'CRASH_BOUNDARY'
            'init-uncommitted-initial-rows' = 'CRASH_BOUNDARY'
            'init-initial-transaction-durable' = 'CRASH_BOUNDARY'
            'init-before-promotion' = 'CRASH_BOUNDARY'
            'init-after-promotion' = 'CRASH_BOUNDARY'
            'init-active-opened' = 'CRASH_BOUNDARY'
        }
    }
    if ($Scenario -eq 'ApiCommitRecovery') {
        $recoveryCases = [ordered]@{
            'api-commit-before' = 'CRASH_BOUNDARY'
            'api-commit-after' = 'CRASH_BOUNDARY'
            'api-key-commit-before' = 'CRASH_BOUNDARY'
            'api-key-commit-after' = 'CRASH_BOUNDARY'
        }
    }
    $completedRecovery = @()
    foreach ($recoveryCase in $recoveryCases.Keys) {
        $hardCrash = $Scenario -in @('InitializationRecovery','ApiCommitRecovery') -or $recoveryCase -in @('commit-before','commit-after')
        Write-Output "START recovery-$recoveryCase"
        $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario', $recoveryCase) $recoveryCase -CrashAtBoundary:$hardCrash
        $writerMarker = 'COMPILED_' + $recoveryCase.ToUpperInvariant().Replace('-','_') + '_PROVED'
        $required = @($recoveryCases[$recoveryCase])
        if ($Scenario -eq 'ApiCommitRecovery') {
            $required += $(if ($recoveryCase.EndsWith('-before')) { 'API_BEFORE_COMMIT_PROVED' } else { 'API_AFTER_COMMIT_BEFORE_REPLY_PROVED' })
            $required += 'API_CRASH_PRIVATE_MARKERS_CLEAN_PROVED'
        }
        if ($Scenario -eq 'InitializationRecovery') {
            $required += $(if ($recoveryCase -eq 'init-staging-created') { 'INIT_NO_SECRET_CREATED_PROVED' } elseif ($recoveryCase -eq 'init-uncommitted-initial-rows') { 'INIT_RECEIPT_KEY_LIVE_SCAN_DEFERRED_PROVED' } else { 'INIT_RECEIPT_KEY_MARKERS_CLEAN_PROVED' })
        }
        if (-not $hardCrash) { $required += $writerMarker }
        $allowed = $required + @('IsarCore using libmdbx: v0.13.8-temp-upstream-fix')
        $writerLines = @($probe.output -split '\r?\n')
        if ($probe.error -or @($writerLines | Where-Object { $_ -notin $allowed }).Count -or ($hardCrash -and $probe.code -eq 0) -or (-not $hardCrash -and $probe.code -ne 0)) { throw "Recovery writer failed: $recoveryCase" }
        foreach ($marker in $required) { if (@($writerLines | Where-Object { $_ -eq $marker }).Count -ne 1) { throw 'Recovery writer marker missing or repeated.' } }
        $verifyCase = 'verify-' + $recoveryCase
        $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario', $verifyCase) $verifyCase
        $verifierMarker = 'COMPILED_' + $verifyCase.ToUpperInvariant().Replace('-','_') + '_PROVED'
        $verificationProof = 'CRASH_REOPEN_PROVED'
        if ($Scenario -eq 'InitializationRecovery') {
            $verificationProof = if ($recoveryCase -in @('init-initial-transaction-durable','init-before-promotion','init-after-promotion','init-active-opened')) { 'INIT_READY_PROVED' } else { 'INIT_PARTIAL_PRESERVED_PROVED' }
        }
        $required = @($verificationProof,$verifierMarker)
        if ($Scenario -eq 'ApiCommitRecovery') { $required += @('API_CRASH_REOPEN_PROVED','API_CRASH_PRIVATE_MARKERS_CLEAN_PROVED') }
        if ($Scenario -eq 'InitializationRecovery') {
            $required += $(if ($recoveryCase -eq 'init-staging-created') { 'INIT_NO_SECRET_CREATED_PROVED' } else { 'INIT_RECEIPT_KEY_MARKERS_CLEAN_PROVED' })
        }
        $allowed = $required + @('IsarCore using libmdbx: v0.13.8-temp-upstream-fix')
        $verifyLines = @($probe.output -split '\r?\n')
        if ($probe.code -ne 0 -or $probe.error -or @($verifyLines | Where-Object { $_ -notin $allowed }).Count) { throw "Fresh-process recovery failed: $recoveryCase" }
        foreach ($marker in $required) { if (@($verifyLines | Where-Object { $_ -eq $marker }).Count -ne 1) { throw 'Recovery verification marker missing or repeated.' } }
        foreach ($used in @($recoveryCase,$verifyCase)) {
            $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario', $used) ("used-$used")
            if ($probe.code -ne 1 -or $probe.error -ne 'TEST_FIXTURE_USED' -or $probe.output) { throw 'Recovery phase reset or reused.' }
        }
        $completedRecovery += @{ name=$recoveryCase; hardCrash=$hardCrash; verified=$true }
        Write-Output "PASS recovery-$recoveryCase"
    }
    $recoveryProof = @{ format=1; cases=$completedRecovery; normalControlsRejected=10; boundTestExecutable=$true }
    if ($Scenario -eq 'InitializationRecovery') {
        $recoveryProof.fileSecretScanComplete = $false
        $recoveryProof.deferred = @('live-uncommitted-native-file-read-LOCK_VIOLATION-33')
        $tamperedCase = 'init-native-files-inventory-replaced'
        Write-Output 'START initialization-inventory-negative'
        $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario', $tamperedCase) $tamperedCase -CrashAtBoundary
        $lines = @($probe.output -split '\r?\n')
        if ($probe.code -eq 0 -or $probe.error -or @($lines | Where-Object { $_ -notin @('CRASH_BOUNDARY','INIT_RECEIPT_KEY_MARKERS_CLEAN_PROVED','IsarCore using libmdbx: v0.13.8-temp-upstream-fix') }).Count -or @($lines | Where-Object { $_ -eq 'CRASH_BOUNDARY' }).Count -ne 1 -or @($lines | Where-Object { $_ -eq 'INIT_RECEIPT_KEY_MARKERS_CLEAN_PROVED' }).Count -ne 1) { throw 'Inventory negative writer failed.' }
        $staging = Join-Path $fixtureRoot "cases/$tamperedCase/ServerDeckNext/v1/workspaces/default.creating"
        $original = Join-Path $staging 'workspace.isar'
        $replacement = Join-Path $staging 'unexpected.isar'
        Assert-NativeFixturePath $original
        Assert-NativeFixturePath $replacement
        $beforeHash = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
        Move-Item -LiteralPath $original -Destination $replacement
        $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario', "verify-$tamperedCase") "verify-$tamperedCase"
        if ($probe.code -ne 1 -or $probe.output -or $probe.error -ne 'TEST_SCENARIO_FAILED' -or (Test-Path -LiteralPath $original) -or -not (Test-Path -LiteralPath $replacement) -or (Get-FileHash -LiteralPath $replacement -Algorithm SHA256).Hash -ne $beforeHash) { throw 'Replaced inventory accepted or modified.' }
        foreach ($used in @($tamperedCase,"verify-$tamperedCase")) {
            $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario', $used) ("used-$used")
            if ($probe.code -ne 1 -or $probe.output -or $probe.error -ne 'TEST_FIXTURE_USED') { throw 'Failed inventory phase reused.' }
        }
        $recoveryProof.inventoryReplacementRejected = $true
        Write-Output 'PASS initialization-inventory-negative'
    }
    $proofScenario = if ($Scenario -eq 'InitializationRecovery') { 'compiled-initialization-recovery' } elseif ($Scenario -eq 'ApiCommitRecovery') { 'compiled-api-commit-recovery' } else { 'compiled-commit-recovery' }
    $recoveryProof.scenario = $proofScenario
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'accepted.json'), ($recoveryProof | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    Write-Output ($proofScenario.ToUpperInvariant().Replace('-','_') + '_ACCEPTED')
    return
}
$commonMarkers = @('LEASE_ACQUIRED','BUNDLE_VERIFIED','INITIAL_FIXTURE_DURABLE','REPOSITORY_OPENED')
$caseMarkers = [ordered]@{
    'workspace-lifecycle' = @('WORKSPACE_CREATION_RECOVERY_PROVED','WORKSPACE_IDENTITY_CORRUPTION_CASE_WRONG_VALID_KEY','WORKSPACE_IDENTITY_CORRUPTION_CASE_MANIFEST_WORKSPACE_IDENTITY','WORKSPACE_IDENTITY_CORRUPTION_CASE_MANIFEST_RECEIPT_IDENTITY','WORKSPACE_IDENTITY_CORRUPTION_CASE_DAMAGED_DATABASE','WORKSPACE_WRAPPER_METADATA_CASE_RECEIPT_FORMAT','WORKSPACE_WRAPPER_METADATA_CASE_RECEIPT_PRODUCT','WORKSPACE_WRAPPER_METADATA_CASE_RECEIPT_OWNER','WORKSPACE_WRAPPER_METADATA_CASE_MANIFEST_OWNER','WORKSPACE_REPARSE_CASE_PRODUCT','WORKSPACE_REPARSE_CASE_ACTIVE','WORKSPACE_REPARSE_CASE_STAGING','WORKSPACE_REPARSE_HEALTHY_CONTROL_PROVED','WORKSPACE_PERSISTED_REPARSE_PRODUCT_PRESERVED_PROVED','WORKSPACE_PERSISTED_REPARSE_WORKSPACES_PRESERVED_PROVED','WORKSPACE_PERSISTED_REPARSE_ACTIVE_PRESERVED_PROVED','WORKSPACE_PERSISTED_REPARSE_STAGING_PRESERVED_PROVED','WORKSPACE_PERSISTED_FILE_REPARSE_MANIFEST_PRESERVED_PROVED','WORKSPACE_PERSISTED_FILE_REPARSE_KEY_PRESERVED_PROVED','WORKSPACE_PERSISTED_FILE_REPARSE_DATABASE_PRESERVED_PROVED','WORKSPACE_PERSISTED_FILE_REPARSE_LOCK_PRESERVED_PROVED','WORKSPACE_FOREIGN_NATIVE_SCHEMA_PRESERVED_REFUSAL_PROVED','WORKSPACE_FOREIGN_SCHEMA_ORIGINAL_CREDENTIAL_RECOVERY_PROVED')
    'repository' = $commonMarkers + @('FIRST_COMMIT','SECOND_COMMIT','STARTUP_DAMAGE_FAIL_CLOSED_PROVED','CREDENTIAL_AND_WORKSPACE_STARTUP_MATRIX_PROVED','NATIVE_FIVE_RECORD_BYTE_LIMITS_PRESERVED_PROVED','STATESTORE_MAP_FULL_ROLLBACK_PROVED','NATIVE_ALLOCATOR_ROLLBACK_PROVED','REPOSITORY_NATIVE_CHECKS_PASSED')
    'credential-lifecycle' = $commonMarkers + @('CREDENTIAL_SNAPSHOTS_PASSED')
    'mutations' = $commonMarkers + @('MUTATION_REVISION_MATRIX_PASSED','MUTATIONS_PASSED')
    'api' = $commonMarkers + @('NATIVE_ROUTER_METHODS_PROVED','ROUTER_METHODS_PASSED')
    'channel' = $commonMarkers + @('CHANNEL_CLOSE_REQUEST_WRITTEN','CHANNEL_CLOSE_REPLY_READ','NATIVE_CHANNEL_HANDSHAKE_ROUTER_DPAPI_PROVED','NATIVE_OCCUPIED_POOL_REFUSAL_AND_RECOVERY_PROVED','NATIVE_AUTH_REFUSAL_AND_READ_ONLY_PROVED','NATIVE_INCOMPATIBLE_API_MAJOR_NO_AUTH_OR_EFFECT_PROVED','NATIVE_INCOMPATIBLE_API_MINOR_NO_AUTH_OR_EFFECT_PROVED','NATIVE_API_COMPATIBILITY_HEALTHY_RECOVERY_PROVED','NATIVE_IDENTITY_QUERY_FAILURE_CLOSED_PROVED','NATIVE_THREAD_TOKEN_QUERY_FAILURE_STABILITY_PROVED','NATIVE_AUTH_REPLAY_AND_CHANNEL_BINDING_PROVED','NATIVE_PEER_SID_PATH_HASH_REFUSAL_PROVED','NATIVE_QUEUE_LAST_REQUESTER_CANCEL_RETRY_PROVED','NATIVE_QUEUE_DUPLICATE_AND_RUNNING_SURVIVE_DISCONNECT_PROVED','NATIVE_FRAME_LENGTH_AND_PARTIAL_DEADLINE_PROVED','NATIVE_EIGHT_SESSION_LIMIT_AND_REUSE_PROVED','NATIVE_GLOBAL_QUEUE_LIMIT_AND_RECOVERY_PROVED','NATIVE_SIXTEEN_PENDING_BACKPRESSURE_AND_RECOVERY_PROVED','NATIVE_QUEUE_PENDING_ACCEPT_CLEANUP_PROVED','CHANNEL_PASSED')
    'service-lifecycle' = $commonMarkers + @('NATIVE_LIFECYCLE_DRAIN_REOPEN_PROVED','SERVICE_LIFECYCLE_PASSED')
    'resource-limits' = $commonMarkers + @('COORDINATOR_SHUTDOWN_DRAINED','COORDINATOR_MAP_FULL_ROLLBACK','COORDINATOR_RECEIPT_QUOTA_PRESERVED','MUTATION_BOUNDARIES_PASSED')
}
$selectedCases = if ($Scenario -eq 'CoreStorage') { @($caseMarkers.Keys) } else { @('workspace-lifecycle') }
$acceptedCases = @()
foreach ($nativeCase in $selectedCases) {
    $caseBudget = if ($nativeCase -eq 'resource-limits') { 360 } else { 180 }
    $caseWatch = [Diagnostics.Stopwatch]::StartNew()
    Write-Output "START compiled-$nativeCase"
    $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario', $nativeCase) $nativeCase $caseBudget
    $nativeLines = @($probe.output -split '\r?\n')
    $compiledMarker = 'COMPILED_' + $nativeCase.ToUpperInvariant().Replace('-','_') + '_PROVED'
    $requiredMarkers = $caseMarkers[$nativeCase] + @($compiledMarker)
    $allowedLines = $requiredMarkers + @('IsarCore using libmdbx: v0.13.8-temp-upstream-fix')
    $unexpectedLines = @($nativeLines | Where-Object { $_ -notin $allowedLines -and -not ($nativeCase -eq 'repository' -and $_ -cmatch '^CAPACITY_COMMITS=(?:[1-9]|1[0-2])00$') })
    if ($probe.code -ne 0 -or $probe.error -or $unexpectedLines.Count) { throw "Compiled native case failed: $nativeCase" }
    foreach ($marker in $requiredMarkers) { if (@($nativeLines | Where-Object { $_ -eq $marker }).Count -ne 1) { throw "Compiled native marker missing or repeated: $nativeCase" } }
    $probe = Invoke-NativeFixtureProbe $testExecutable @('--scenario', $nativeCase) ("test-used-$nativeCase")
    if ($probe.code -ne 1 -or $probe.error -ne 'TEST_FIXTURE_USED' -or $probe.output) { throw 'Used case reset or accepted.' }
    $acceptedCases += @{ name = $nativeCase; budgetSeconds = $caseBudget; completed = $true }
    Write-Output ("PASS compiled-$nativeCase seconds=" + [Math]::Round($caseWatch.Elapsed.TotalSeconds, 1))
}
$proofScenario = if ($Scenario -eq 'CoreStorage') { 'compiled-core-storage' } else { 'compiled-workspace-lifecycle' }
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'accepted.json'), (@{ format = 1; scenario = $proofScenario; cases = $acceptedCases; normalControlsRejected = 10; boundTestExecutable = $true } | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Write-Output $(if ($Scenario -eq 'CoreStorage') { 'COMPILED_CORE_STORAGE_ACCEPTED' } else { 'COMPILED_WORKSPACE_LIFECYCLE_ACCEPTED' })
# Preserve all owned synthetic files. Full All acceptance remains incomplete.
