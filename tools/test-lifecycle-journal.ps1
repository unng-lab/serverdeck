[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vm-lifecycle-journal.ps1')
function Assert-JournalFailure([string[]]$Lines, [string]$Suite = 'lifecycle') {
    $result = Read-LifecycleJournal -Lines $Lines -Suite $Suite
    if ($result.scenariosMatch -or !$result.journalError) { throw 'Malformed journal was not captured as failed evidence' }
}
$base = @('readonly-executable', 'cold-start-original-pid', 'close-keeps-owner', 'tray-open-menu',
    'system-close-and-double-click', 'concurrent-duplicate-launches', 'minimized-tray-restore',
    'tray-exit', 'warm-reopen-preserves-store')
foreach ($suite in @('lifecycle', 'recovery', 'shell', 'acl')) {
    $names = @($base)
    if ($suite -eq 'recovery') {
        $names += @('owned-crash-reopen-store-identity', 'corrupt-cache-quarantine-and-reopen',
            'interrupted-extraction-and-reopen', 'future-current-block-and-retry',
            'invalid-current-block-and-retry', 'missing-current-block-and-retry')
    }
    if ($suite -eq 'shell') { $names += @('explorer-restart-preserves-owner', 'session-query-native-shutdown', 'session-confirmed-native-shutdown') }
    if ($suite -eq 'acl') { $names += @('startup-acl-cancel-preserves-data', 'startup-acl-retry-same-pid') }
    $header = @{schemaVersion = 1; scope = 'Synthetic journal parser test'; recoveryEnabled = ($suite -eq 'recovery'); shellEnabled = ($suite -eq 'shell'); aclEnabled = ($suite -eq 'acl'); fullVmAcceptance = $false} |
        ConvertTo-Json -Compress
    $lines = @($header)
    foreach ($name in $names) {
        $lines += (@{event = 'started'; scenario = $name} | ConvertTo-Json -Compress)
        $lines += (@{event = 'passed'; scenario = $name; elapsedMs = 1} | ConvertTo-Json -Compress)
    }
    $lines += '{"event":"completed","fullVmAcceptance":false}'
    $valid = Read-LifecycleJournal -Lines $lines -Suite $suite
    if (!$valid.scenariosMatch -or $valid.journalError) { throw "Valid $suite journal rejected: $($valid.journalError)" }
    if ($suite -eq 'shell') {
        $wrongScope = $header | ConvertFrom-Json
        $wrongScope.shellEnabled = $false
        Assert-JournalFailure @(($wrongScope | ConvertTo-Json -Compress)) $suite
    }
    if ($suite -eq 'acl') {
        $wrongScope = $header | ConvertFrom-Json
        $wrongScope.aclEnabled = $false
        Assert-JournalFailure @(($wrongScope | ConvertTo-Json -Compress)) $suite
    }
    foreach ($bad in @('{"event":', '{"event":"passed"}', '{"event":"passed","scenario":42}',
        '{"event":"passed","scenario":"readonly-executable","elapsedMs":-1}',
        '{"event":"failed","scenario":"readonly-executable"}',
        '[{"event":"passed","scenario":"readonly-executable","elapsedMs":1}]', 'null', '42',
        '{"event":"completed","fullVmAcceptance":true}', '{"event":"unknown"}')) {
        Assert-JournalFailure @($header, $bad) $suite
    }
    Assert-JournalFailure @($header, '{"event":"completed","fullVmAcceptance":false}', '{"event":"owner"}') $suite
    $wrongHeader = @{schemaVersion = 1; scope = 'test'; recoveryEnabled = ($suite -eq 'recovery'); shellEnabled = ($suite -eq 'shell'); aclEnabled = ($suite -eq 'acl'); fullVmAcceptance = $true} |
        ConvertTo-Json -Compress
    Assert-JournalFailure @($wrongHeader) $suite
    $incomplete = Read-LifecycleJournal -Lines @($header, '{"event":"completed","fullVmAcceptance":false}') -Suite $suite
    if ($incomplete.scenariosMatch) { throw 'Incomplete scenarios accepted' }
    $failed = Read-LifecycleJournal -Lines @($header, '{"event":"failed","scenario":"readonly-executable","error":"synthetic failure"}') -Suite $suite
    if ($failed.scenariosMatch -or $failed.journalError) { throw 'Valid failed scenario misclassified' }
}
Assert-JournalFailure @()
Write-Output 'Lifecycle journal checks passed: lifecycle/recovery/shell/ACL complete, incomplete, failed, JSON syntax, malformed event schema and limited scope.'
exit 0
