function Read-LifecycleJournal {
    param(
        [string[]]$Lines,
        [ValidateSet('lifecycle', 'recovery', 'shell', 'acl')][string]$Suite = 'lifecycle'
    )
    $expected = @('readonly-executable', 'cold-start-original-pid', 'close-keeps-owner', 'tray-open-menu',
        'system-close-and-double-click', 'concurrent-duplicate-launches', 'minimized-tray-restore',
        'tray-exit', 'warm-reopen-preserves-store')
    if ($Suite -eq 'recovery') {
        $expected += @('owned-crash-reopen-store-identity', 'corrupt-cache-quarantine-and-reopen',
            'interrupted-extraction-and-reopen', 'future-current-block-and-retry',
            'invalid-current-block-and-retry', 'missing-current-block-and-retry')
    }
    if ($Suite -eq 'shell') {
        $expected += @('explorer-restart-preserves-owner', 'session-query-native-shutdown', 'session-confirmed-native-shutdown')
    }
    if ($Suite -eq 'acl') {
        $expected += @('startup-acl-cancel-preserves-data', 'startup-acl-retry-same-pid')
    }
    $known = @('started', 'passed', 'failed', 'owner', 'duplicate-overlap', 'forced-crash',
        'startup-acl-denied', 'interrupted-stage', 'blocked-data-unchanged', 'explorer-before', 'explorer-restarted', 'completed')
    $events = @(); $errorText = ''; $passed = @(); $completed = @(); $failed = @()
    try {
        if (!$Lines -or $Lines.Count -eq 0) { throw 'Journal header is missing' }
        for ($index = 0; $index -lt $Lines.Count; $index++) {
            if (!$Lines[$index].TrimStart().StartsWith('{')) { throw 'Journal entry must be a JSON object' }
            $item = $Lines[$index] | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $item -or $item -isnot [pscustomobject]) { throw 'Journal entry must be an object' }
            if ($index -eq 0) {
                foreach ($property in @('schemaVersion', 'scope', 'recoveryEnabled', 'fullVmAcceptance')) {
                    if (!$item.PSObject.Properties[$property]) { throw "Journal header is missing $property" }
                }
                if ($item.PSObject.Properties['event'] -or
                    ($item.schemaVersion -isnot [int] -and $item.schemaVersion -isnot [long]) -or
                    $item.schemaVersion -ne 1 -or $item.scope -isnot [string] -or
                    [string]::IsNullOrWhiteSpace($item.scope) -or $item.recoveryEnabled -isnot [bool] -or
                    $item.recoveryEnabled -ne ($Suite -eq 'recovery') -or
                    $item.fullVmAcceptance -isnot [bool] -or $item.fullVmAcceptance) {
                    throw 'Journal header does not match the selected suite and limited acceptance scope'
                }
                $shellEnabled = $item.PSObject.Properties['shellEnabled']
                if (($Suite -eq 'shell' -and (!$shellEnabled -or $shellEnabled.Value -ne $true)) -or
                    ($shellEnabled -and ($shellEnabled.Value -isnot [bool] -or $shellEnabled.Value -ne ($Suite -eq 'shell')))) {
                    throw 'Journal shell scope does not match the selected suite'
                }
                $aclEnabled = $item.PSObject.Properties['aclEnabled']
                if (($Suite -eq 'acl' -and (!$aclEnabled -or $aclEnabled.Value -ne $true)) -or
                    ($aclEnabled -and ($aclEnabled.Value -isnot [bool] -or $aclEnabled.Value -ne ($Suite -eq 'acl')))) {
                    throw 'Journal ACL scope does not match the selected suite'
                }
            } else {
                $event = $item.PSObject.Properties['event']
                if (!$event -or $event.Value -isnot [string] -or $event.Value -cnotin $known) {
                    throw 'Journal event type is missing or unsupported'
                }
                if ($event.Value -cin @('started', 'passed', 'failed', 'blocked-data-unchanged', 'startup-acl-denied')) {
                    $scenario = $item.PSObject.Properties['scenario']
                    if (!$scenario -or $scenario.Value -isnot [string] -or $scenario.Value -cnotin $expected) {
                        throw 'Journal event scenario is missing or unsupported'
                    }
                }
                if ($event.Value -ceq 'passed') {
                    $elapsed = $item.PSObject.Properties['elapsedMs']
                    if (!$elapsed -or ($elapsed.Value -isnot [int] -and $elapsed.Value -isnot [long]) -or
                        $elapsed.Value -lt 0) { throw 'Journal passed event has invalid elapsedMs' }
                }
                if ($event.Value -ceq 'failed') {
                    $failure = $item.PSObject.Properties['error']
                    if (!$failure -or $failure.Value -isnot [string] -or
                        [string]::IsNullOrWhiteSpace($failure.Value)) { throw 'Journal failed event has no error' }
                }
                if ($event.Value -ceq 'completed') {
                    $acceptance = $item.PSObject.Properties['fullVmAcceptance']
                    if (!$acceptance -or $acceptance.Value -isnot [bool] -or $acceptance.Value -or
                        $index -ne $Lines.Count - 1) { throw 'Journal completion envelope is invalid' }
                }
            }
            $events += $item
        }
        $passed = @($events | Where-Object { $_.PSObject.Properties['event'] -and $_.event -ceq 'passed' } |
            Select-Object -ExpandProperty scenario)
        $completed = @($events | Where-Object { $_.PSObject.Properties['event'] -and $_.event -ceq 'completed' })
        $failed = @($events | Where-Object { $_.PSObject.Properties['event'] -and $_.event -ceq 'failed' })
    } catch { $errorText = $_.Exception.Message }
    [pscustomobject]@{
        events = @($events); journalError = $errorText
        scenariosMatch = (!$errorText -and $failed.Count -eq 0 -and $completed.Count -eq 1 -and
            $passed.Count -eq $expected.Count -and @(Compare-Object $expected $passed).Count -eq 0)
    }
}
