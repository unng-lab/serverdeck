[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/embedded-bundle.ps1"
. "$PSScriptRoot/native-compatibility-policy.ps1"
$script:bundleCases = 0
function Assert-BundleUnit { param([bool]$Value) if (-not $Value) { throw 'BUNDLE_UNIT_ASSERTION_FAILED' } }
function Expect-InvalidBundle {
    param([scriptblock]$Action)
    $failed = $false
    try { & $Action | Out-Null }
    catch { $failed = $true; Assert-BundleUnit ($_.Exception.Message -ceq 'INVALID_EMBEDDED_BUNDLE_INPUT') }
    Assert-BundleUnit $failed
}
function Test-BundleCase {
    param([scriptblock]$Action)
    & $Action
    $script:bundleCases++
}
function Get-UnitLocks {
    return [ordered]@{
        'pubspec.lock' = '1' * 64
        'packages/serverdeck_engine/pubspec.lock' = '2' * 64
        'packages/serverdeck_mcp/pubspec.lock' = '3' * 64
        'packages/serverdeck_protocol/pubspec.lock' = '4' * 64
        'packages/serverdeck_windows/pubspec.lock' = '5' * 64
    }
}
function New-UnitBundle {
    param([Collections.IDictionary]$Locks = (Get-UnitLocks),
        [Collections.IDictionary]$Files = @{'serverdeck.exe' = ('a' * 64); 'libisar.dll' = ('b' * 64)},
        [string]$Root = 'C:\ServerDeck', [string]$Configuration = 'Debug', [string]$Commit = ('c' * 40))
    New-EmbeddedBundleManifest -Commit $Commit -Configuration $Configuration -AppRoot $Root -LockHashes $Locks -Hashes $Files
}
Test-BundleCase {
    Assert-BundleUnit (((Get-CurrentPackageNames) -join ',') -ceq 'serverdeck_engine,serverdeck_mcp,serverdeck_protocol,serverdeck_windows')
    Assert-BundleUnit (((Get-CurrentBundleLockPaths) -join ',') -ceq ((Get-UnitLocks).Keys -join ','))
    $m = New-UnitBundle
    Assert-BundleUnit ($m.format -eq 4 -and $m.product -ceq 'serverdeck-next' -and $m.apiMajor -eq 1 -and
        $m.apiMinor -eq 1 -and $m.workspaceSchema -eq 3 -and $m.testOnly -ceq $false -and $m.Count -eq 10)
    Assert-BundleUnit ($m.buildId -cmatch '^[a-f0-9]{40}\+Debug\+[a-f0-9]{64}$')
}
Test-BundleCase {
    $m = New-UnitBundle -Configuration Release
    Assert-BundleUnit ($m.configuration -ceq 'Release' -and $m.buildId.Contains('+Release+'))
    $files = @{'serverdeck.exe' = ('a' * 64); 'libisar.dll' = ('b' * 64); 'executor-release.json' = ('d' * 64)}
    Assert-BundleUnit ((New-UnitBundle -Files $files).sha256.Count -eq 3)
}
Test-BundleCase {
    $locks = Get-UnitLocks
    $reverse = [ordered]@{}
    foreach ($name in @($locks.Keys)[4..0]) { $reverse[$name] = $locks[$name] }
    Assert-BundleUnit ((New-UnitBundle -Locks $locks).buildId -ceq (New-UnitBundle -Locks $reverse).buildId)
    $locks['pubspec.lock'] = 'f' * 64
    Assert-BundleUnit ((New-UnitBundle -Locks $locks).buildId -cne (New-UnitBundle -Locks $reverse).buildId)
}
Test-BundleCase {
    $locks = Get-UnitLocks
    $locks.Remove('packages/serverdeck_engine/pubspec.lock')
    $locks['packages/serverdeck_locald/pubspec.lock'] = '2' * 64
    Expect-InvalidBundle { New-UnitBundle -Locks $locks }
    $locks = Get-UnitLocks
    $locks.Remove('packages/serverdeck_mcp/pubspec.lock')
    Expect-InvalidBundle { New-UnitBundle -Locks $locks }
}
Test-BundleCase {
    foreach ($name in @('locald.exe', 'mcp.exe', 'unknown.dll', 'ServerDeck.exe')) {
        $files = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        $files['serverdeck.exe'] = 'a' * 64
        $files['libisar.dll'] = 'b' * 64
        $files[$name] = 'c' * 64
        Expect-InvalidBundle { New-UnitBundle -Files $files }
    }
}
Test-BundleCase {
    foreach ($value in @(('A' * 64), 'not-a-digest', ('a' * 63))) {
        Expect-InvalidBundle { New-UnitBundle -Files @{'serverdeck.exe' = $value; 'libisar.dll' = ('b' * 64)} }
        $locks = Get-UnitLocks
        $locks['pubspec.lock'] = $value
        Expect-InvalidBundle { New-UnitBundle -Locks $locks }
    }
}
Test-BundleCase {
    Expect-InvalidBundle { New-UnitBundle -Configuration debug }
    Expect-InvalidBundle { New-UnitBundle -Commit ('C' * 40) }
    Expect-InvalidBundle { New-UnitBundle -Root 'relative/root' }
    Expect-InvalidBundle { New-UnitBundle -Root ("C:\a" + [char]0 + 'b') }
    Expect-InvalidBundle { New-UnitBundle -Root ('C:\' + ('x' * 17000)) }
    Expect-InvalidBundle { New-UnitBundle -Root ('C:\' + ([string][char]0x6c49 * 6000)) }
}
Test-BundleCase {
    $files = @{'serverdeck.exe' = ('a' * 64); 'libisar.dll' = ('b' * 64)}
    $m = New-UnitBundle -Files $files
    $files['serverdeck.exe'] = 'e' * 64
    Assert-BundleUnit ($m.sha256['serverdeck.exe'] -ceq ('a' * 64))
    Assert-BundleUnit (($m | ConvertTo-Json -Depth 5 -Compress | ConvertFrom-Json).format -eq 4)
}
function Convert-UnitBundle {
    param([object]$Value = (New-UnitBundle), [string]$Configuration = 'Debug',
        [Collections.IDictionary]$Locks = (Get-UnitLocks), [string]$Dll = ('b' * 64), [string]$Root = 'C:\ServerDeck')
    ConvertTo-EmbeddedBundleManifest -InputObject $Value -Configuration $Configuration -AppRoot $Root -DllSha256 $Dll -LockHashes $Locks
}
Test-BundleCase {
    foreach ($configuration in @('Debug','Release')) {
        $value = New-UnitBundle -Configuration $configuration
        $decoded = $value | ConvertTo-Json -Depth 5 -Compress | ConvertFrom-Json
        $checked = Convert-UnitBundle -Value $decoded -Configuration $configuration
        Assert-BundleUnit ($checked.buildId -ceq $value.buildId -and $checked.sha256.Count -eq 2)
    }
}
Test-BundleCase {
    foreach ($format in @(1,2,3,4.0,'4')) {
        $m = New-UnitBundle
        $m['format'] = $format
        Expect-InvalidBundle { Convert-UnitBundle -Value $m }
    }
    $m = New-UnitBundle
    $m['roles'] = @{}
    Expect-InvalidBundle { Convert-UnitBundle -Value $m }
}
Test-BundleCase {
    foreach ($field in @('apiMajor','apiMinor','workspaceSchema')) {
        $m = New-UnitBundle
        $m[$field] = [double]$m[$field]
        Expect-InvalidBundle { Convert-UnitBundle -Value $m }
    }
    foreach ($flag in @($true,'false',0)) {
        $m = New-UnitBundle
        $m['testOnly'] = $flag
        Expect-InvalidBundle { Convert-UnitBundle -Value $m }
    }
}
Test-BundleCase {
    $locks = Get-UnitLocks
    $locks['packages/serverdeck_engine/pubspec.lock'] = 'e' * 64
    Expect-InvalidBundle { Convert-UnitBundle -Locks $locks }
    Expect-InvalidBundle { Convert-UnitBundle -Dll ('c' * 64) }
    Expect-InvalidBundle { Convert-UnitBundle -Root 'C:\AnotherBundle' }
}
Test-BundleCase {
    $m = New-UnitBundle
    $hashes = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $hashes['serverdeck.exe'] = 'a' * 64
    $hashes['ServerDeck.exe'] = 'a' * 64
    $hashes['libisar.dll'] = 'b' * 64
    $m['sha256'] = $hashes
    Expect-InvalidBundle { Convert-UnitBundle -Value $m }
    Expect-InvalidBundle { New-UnitBundle -Root ('C:\' + [char]0xd800) }
}
Test-BundleCase {
    $m = New-UnitBundle
    $checked = Convert-UnitBundle -Value $m
    $m.sha256['serverdeck.exe'] = 'e' * 64
    Assert-BundleUnit ($checked.sha256['serverdeck.exe'] -ceq ('a' * 64))
}
function Get-UnitNativePhases {
    return @(foreach ($name in Get-NativeCompatibilityPhases) {
        [pscustomobject]@{name=$name;passed=$true;log=$name+'.txt';logSha256=('a'*64)}
    })
}
function Expect-InvalidNativePhases {
    param([object[]]$Phases)
    $failed = $false
    try { Assert-NativeCompatibilityPhases -Phases $Phases }
    catch { $failed = $true; Assert-BundleUnit ($_.Exception.Message -ceq 'INVALID_NATIVE_COMPATIBILITY_PHASES') }
    Assert-BundleUnit $failed
}
Test-BundleCase {
    Assert-NativeCompatibilityPhases -Phases (Get-UnitNativePhases)
    $phases = Get-UnitNativePhases
    $phases[8].name = 'serverdeck_locald-analyze'
    Expect-InvalidNativePhases $phases
    Expect-InvalidNativePhases @((Get-UnitNativePhases) | Where-Object name -NotLike 'serverdeck_mcp-*')
}
Test-BundleCase {
    foreach ($field in @('passed','log','logSha256')) {
        $phases = Get-UnitNativePhases
        $phases[0].$field = $(if ($field -eq 'passed') { $false } else { 'private-invalid-value' })
        Expect-InvalidNativePhases $phases
    }
    $phases = Get-UnitNativePhases
    $phases[1] = $phases[0]
    Expect-InvalidNativePhases $phases
    $phases = Get-UnitNativePhases
    $phases[0].passed = 'true'
    Expect-InvalidNativePhases $phases
    $phases = Get-UnitNativePhases
    $phases[0].name = @('abi')
    Expect-InvalidNativePhases $phases
}
Write-Output "Embedded bundle RAM unit cases: $script:bundleCases passed."
