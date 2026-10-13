[CmdletBinding()]
param([switch]$ListOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Fixed executable scope. The deferred unsafe ACL and full All/manual gates
# are deliberately absent; callers cannot add or override child arguments.
$phases = @(
    @{ Name = 'compiled-core-storage'; Script = 'test-foundation-native.ps1'; Arguments = @{ Scenario = 'CoreStorage' } },
    @{ Name = 'compiled-commit-recovery'; Script = 'test-foundation-native.ps1'; Arguments = @{ Scenario = 'CommitRecovery' } },
    @{ Name = 'compiled-api-commit-recovery'; Script = 'test-foundation-native.ps1'; Arguments = @{ Scenario = 'ApiCommitRecovery' } },
    @{ Name = 'compiled-initialization-recovery'; Script = 'test-foundation-native.ps1'; Arguments = @{ Scenario = 'InitializationRecovery' } },
    @{ Name = 'compiled-secret-markers'; Script = 'test-foundation-native.ps1'; Arguments = @{ Scenario = 'SecretMarkers' } },
    @{ Name = 'normal-prerequisites'; Script = 'test-foundation-prerequisites.ps1'; Arguments = @{} },
    @{ Name = 'compiled-bootstrap-owner-loss'; Script = $null; Arguments = @{} },
    @{ Name = 'ui-two-window'; Script = 'test-foundation-ui.ps1'; Arguments = @{} },
    @{ Name = 'ui-three-window'; Script = 'test-foundation-ui.ps1'; Arguments = @{ ThreeWindows = $true } },
    @{ Name = 'ui-observer-crash'; Script = 'test-foundation-ui.ps1'; Arguments = @{ CrashObserver = $true } },
    @{ Name = 'ui-loss-recovery'; Script = 'test-foundation-loss-ui.ps1'; Arguments = @{} },
    @{ Name = 'ui-credential-lifecycle'; Script = 'test-foundation-credentials-ui.ps1'; Arguments = @{} },
    @{ Name = 'ui-unknown-inflight'; Script = 'test-foundation-inflight-ui.ps1'; Arguments = @{} },
    @{ Name = 'ui-normal-owner-recovery'; Script = 'test-foundation-owner-ui.ps1'; Arguments = @{} }
)
if ($ListOnly) {
    $phases | ForEach-Object { Write-Output $_.Name }
    return
}
. "$PSScriptRoot/foundation-sdk.ps1"
$suiteRoot = [IO.Path]::GetFullPath((Join-Path $FoundationRoot ('.local/available-acceptance-' + [Guid]::NewGuid().ToString('N'))))
if (-not $suiteRoot.StartsWith($FoundationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $suiteRoot)) {
    throw 'Invalid new available-acceptance fixture.'
}
New-Item -ItemType Directory -Path $suiteRoot | Out-Null
$completed = @()
$current = 'setup'
$resultPath = Join-Path $suiteRoot 'result.json'
function Write-AvailableResult {
    param([ValidateSet('passed','failed')][string]$Status)
    $result = [ordered]@{
        format = 1
        scenario = 'available-automated-foundation'
        status = $Status
        fullAcceptance = $false
        requiredPhaseCount = $phases.Count
        completed = $completed
        failedPhase = if ($Status -eq 'failed') { $current } else { $null }
        excluded = @('SecretMarkersUnsafeAcl', 'live-uncommitted-native-file-read-LOCK_VIOLATION-33', 'full-Q01-Q12', 'reboot', 'other-user', 'physical-offline', 'CI-execution')
    }
    [IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
}
Push-Location $FoundationRoot
try {
    foreach ($phase in $phases) {
        $current = $phase.Name
        Write-Output "START available-$current"
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $log = Join-Path $suiteRoot ($current + '.txt')
        if ($null -eq $phase.Script) {
            Push-Location (Join-Path $FoundationRoot 'packages/serverdeck_locald')
            try {
                Invoke-FoundationCommand $FoundationDart @('test', 'test/bootstrap_native_test.dart', '--concurrency=1') *> $log
            } finally { Pop-Location }
        } else {
            $arguments = $phase.Arguments
            & (Join-Path $PSScriptRoot $phase.Script) @arguments *> $log
        }
        $completed += @{ name = $current; completed = $true; elapsedSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 1) }
        Write-Output "PASS available-$current"
    }
    Write-AvailableResult 'passed'
    Write-Output "AVAILABLE_ACCEPTANCE_PASSED phases=$($completed.Count)"
    Write-Output "AVAILABLE_ACCEPTANCE_RESULT=$resultPath"
} catch {
    Write-AvailableResult 'failed'
    # result.json records the failed phase; preserve the original exception and
    # invocation location so a build/preflight failure remains diagnosable.
    throw
} finally {
    Pop-Location
}
# Preserve synthetic fixtures/logs; no cleanup, upload or privilege changes.
