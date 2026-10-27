[CmdletBinding()]
param([string]$OutputDirectory = '', [switch]$TestBuild, [string]$TestFixtureRoot = '')
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-artifact.ps1"
if ($env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT) { Get-NativeArtifactBuildSelection | Out-Null }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $FoundationRoot 'build/foundation/locald' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $OutputDirectory.StartsWith($FoundationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Build output must remain inside the workspace.' }
$testDefines = @()
if ($TestBuild) {
    if (-not $TestFixtureRoot) { throw 'Test build requires a build-time fixture whitelist.' }
    $TestFixtureRoot = [IO.Path]::GetFullPath($TestFixtureRoot)
    $testParent = [IO.Path]::GetFullPath((Join-Path $FoundationRoot '.local'))
    if ([IO.Path]::GetDirectoryName($TestFixtureRoot) -ne $testParent -or [IO.Path]::GetFileName($TestFixtureRoot) -cnotmatch '^native-acceptance-[a-f0-9]{32}$' -or $OutputDirectory -ne (Join-Path $TestFixtureRoot 'test-bundle') -or -not (Test-Path -LiteralPath $TestFixtureRoot -PathType Container)) { throw 'Invalid test build whitelist.' }
    $testComponent = $OutputDirectory
    while ($testComponent) {
        if (Test-Path -LiteralPath $testComponent) {
            if ((Get-Item -LiteralPath $testComponent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unsafe test build path.' }
        }
        $testComponent = [IO.Path]::GetDirectoryName($testComponent)
    }
    $testIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $testSid = $testIdentity.User.Value } finally { $testIdentity.Dispose() }
    $testDefines = @("--define=SERVERDECK_TEST_FIXTURE_ROOT=$TestFixtureRoot", "--define=SERVERDECK_TEST_OWNER_SID=$testSid", '--define=SERVERDECK_TEST_INITIALIZATION_PROBES=true')
    $markerBytes = [IO.File]::ReadAllBytes((Join-Path $FoundationRoot 'test/fixtures/foundation/markers.json'))
    if ($markerBytes.Length -gt 4096) { throw 'Marker fixture too large.' }
    $testDefines += '--define=SERVERDECK_TEST_MARKERS_BASE64=' + [Convert]::ToBase64String($markerBytes)
} elseif ($TestFixtureRoot) { throw 'Fixture whitelist is only valid for a test build.' }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
Push-Location (Join-Path $FoundationRoot 'packages/serverdeck_locald')
try {
    Invoke-FoundationCommand $FoundationDart @('pub', 'get', '--enforce-lockfile')
    Invoke-FoundationCommand $FoundationDart @('run', 'build_runner', 'build', '--delete-conflicting-outputs')
    $entry = 'bin/locald.dart'
    if ($TestBuild) { $entry = 'test/support/test_entry.dart' }
    Invoke-FoundationCommand $FoundationDart (@('compile', 'exe') + $testDefines + @($entry, '-o', (Join-Path $OutputDirectory 'locald.exe')))
} finally { Pop-Location }
