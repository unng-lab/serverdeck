[CmdletBinding()]
param([switch]$SkipBuild, [switch]$ThreeWindows, [switch]$CrashObserver)
if ($ThreeWindows -and $CrashObserver) { throw 'Choose one UI acceptance scenario.' }
. "$PSScriptRoot/foundation-sdk.ps1"
if (-not $SkipBuild) { & "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly -FoundationAcceptance }
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $FoundationRoot ('.local/foundation-ui-' + [Guid]::NewGuid().ToString('N'))))
if (-not $fixtureRoot.StartsWith($FoundationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture outside workspace.' }
if (Test-Path -LiteralPath $fixtureRoot) { throw 'Fixture already exists.' }
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$layout = Join-Path $fixtureRoot 'application bundle'
Copy-Item -LiteralPath (Join-Path $FoundationRoot 'build/windows/x64/runner/Debug') -Destination $layout -Recurse
$manifestPath = Join-Path $layout 'foundation.manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest.appRoot = $layout
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$profile = Join-Path $fixtureRoot 'profile'
New-Item -ItemType Directory -Path $profile | Out-Null
$taskSavedLocalAppData = $env:LOCALAPPDATA
$taskSavedUiRole = $env:SERVERDECK_UI_ROLE
$taskSavedUiScenario = $env:SERVERDECK_UI_SCENARIO
Push-Location $FoundationRoot
try {
    $env:LOCALAPPDATA = $profile
    $env:SERVERDECK_UI_ROLE = 'primary'
    $env:SERVERDECK_UI_SCENARIO = if ($CrashObserver) { 'crash-observer' } elseif ($ThreeWindows) { 'concurrent-three' } else { 'two-window' }
    Invoke-FoundationCommand $FoundationFlutter @('drive', '--no-pub', '--driver', 'test_driver/integration_test.dart', '--target', 'integration_test/foundation_test.dart', '--use-application-binary', (Join-Path $layout 'serverdeck.exe'), '--no-keep-app-running', '-d', 'windows')
    $stagePath = Join-Path $profile 'two-window/stage-finished'
    if (-not (Test-Path -LiteralPath $stagePath) -or (Get-Item -LiteralPath $stagePath).Length -gt 4096) { throw 'Two-window stage proof missing.' }
    $env:SERVERDECK_UI_ROLE = 'reopen'
    Invoke-FoundationCommand $FoundationFlutter @('drive', '--no-pub', '--driver', 'test_driver/integration_test.dart', '--target', 'integration_test/foundation_test.dart', '--use-application-binary', (Join-Path $layout 'serverdeck.exe'), '--no-keep-app-running', '-d', 'windows')
    $proofPath = Join-Path $profile 'two-window/primary-accepted'
    if (-not (Test-Path -LiteralPath $proofPath) -or (Get-Item -LiteralPath $proofPath).Length -gt 4096) { throw 'Two-window acceptance proof missing.' }
    $proof = Get-Content -LiteralPath $proofPath -Raw | ConvertFrom-Json
    $expectedScenario = if ($CrashObserver) { 'crash-observer-recover-reopen' } elseif ($ThreeWindows) { 'concurrent-three-cas-close-reopen' } else { 'two-window-cas-close-reopen' }
    if ($proof.format -ne 1 -or $proof.scenario -ne $expectedScenario) { throw 'Unexpected acceptance proof.' }
} finally {
    $env:LOCALAPPDATA = $taskSavedLocalAppData
    $env:SERVERDECK_UI_ROLE = $taskSavedUiRole
    $env:SERVERDECK_UI_SCENARIO = $taskSavedUiScenario
    Pop-Location
}
# Preserve this ignored fixture for diagnosis; never delete live runtime files.
