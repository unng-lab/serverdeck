Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/native-probe-process.ps1"
if (-not ('ServerDeckCleanupFakeProcess' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
public sealed class ServerDeckCleanupFakeProcess {
    public bool HasExited;
    public bool FailKill;
    public bool FailWait;
    public bool WaitResult = true;
    public int Kills;
    public int Waits;
    public int Disposals;
    public void Kill() {
        Kills++;
        if (FailKill) throw new InvalidOperationException("TEST_KILL_FAILED");
    }
    public bool WaitForExit(int milliseconds) {
        Waits++;
        if (milliseconds != 10000) throw new InvalidOperationException("TEST_WAIT_BUDGET_CHANGED");
        if (FailWait) throw new InvalidOperationException("TEST_WAIT_FAILED");
        HasExited = WaitResult;
        return WaitResult;
    }
    public void Dispose() { Disposals++; }
}
'@
}
foreach ($case in @('not-started', 'already-exited', 'running', 'kill-failure', 'wait-failure', 'wait-timeout')) {
    $child = [ServerDeckCleanupFakeProcess]::new()
    $child.HasExited = $case -eq 'already-exited'
    $child.FailKill = $case -eq 'kill-failure'
    $child.FailWait = $case -eq 'wait-failure'
    $child.WaitResult = $case -ne 'wait-timeout'
    $caught = $null
    try { Close-NativeFixtureChild $child ($case -ne 'not-started') } catch { $caught = $_ }
    $expectsFailure = $case -in @('kill-failure', 'wait-failure', 'wait-timeout')
    if (($null -ne $caught) -ne $expectsFailure -or $child.Disposals -ne 1) { throw "Cleanup/disposal assertion failed: $case" }
    $expectedKills = if ($case -in @('not-started', 'already-exited')) { 0 } else { 1 }
    $expectedWaits = if ($case -in @('not-started', 'already-exited', 'kill-failure')) { 0 } else { 1 }
    if ($child.Kills -ne $expectedKills -or $child.Waits -ne $expectedWaits) { throw "Cleanup sequence assertion failed: $case" }
    if ($case -eq 'kill-failure' -and $caught.Exception.Message -notmatch 'TEST_KILL_FAILED') { throw 'Kill failure was hidden.' }
    if ($case -eq 'wait-failure' -and $caught.Exception.Message -notmatch 'TEST_WAIT_FAILED') { throw 'Wait failure was hidden.' }
    if ($case -eq 'wait-timeout' -and $caught.Exception.Message -ne 'Owned native probe cleanup incomplete.') { throw 'Incomplete cleanup was reported as success.' }
    Write-Output "PASS cleanup-$case"
}
# This models control flow. It does not induce a kernel Kill failure or claim
# successful native termination when the real OS refuses cleanup.
Write-Output 'NATIVE_PROBE_CLEANUP_FAILURE_DISPOSAL_PROVED'
