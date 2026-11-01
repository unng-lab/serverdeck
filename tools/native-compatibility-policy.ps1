# Pure metadata policy only. A successful check is never native qualification.
function Get-NativeCompatibilityPhases {
    return @('abi','root-format','root-analyze','root-tests',
        'serverdeck_protocol-analyze','serverdeck_protocol-tests',
        'serverdeck_windows-analyze','serverdeck_windows-tests',
        'serverdeck_engine-analyze','serverdeck_engine-tests',
        'serverdeck_mcp-analyze','serverdeck_mcp-tests',
        'bundle-Debug','bundle-Release','available-native-ui','runtime-diagnostics')
}

function Assert-NativeCompatibilityPhases {
    param([Parameter(Mandatory)][object[]]$Phases)
    $expected = @(Get-NativeCompatibilityPhases)
    $invalid = 'INVALID_NATIVE_COMPATIBILITY_PHASES'
    try {
        if ($Phases.Count -ne $expected.Count) { throw $invalid }
        for ($i = 0; $i -lt $expected.Count; $i++) {
            $phase = $Phases[$i]
            if ($phase.name -isnot [string] -or $phase.name -cne $expected[$i] -or $phase.passed -isnot [bool] -or $phase.passed -ne $true -or
                $phase.log -isnot [string] -or $phase.log -cne ($expected[$i] + '.txt') -or $phase.logSha256 -isnot [string] -or
                $phase.logSha256 -cnotmatch '^[a-f0-9]{64}$') { throw $invalid }
        }
    } catch { throw $invalid }
}
