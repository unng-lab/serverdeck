[CmdletBinding()]
param([switch]$SkipBuild)
. "$PSScriptRoot/foundation-sdk.ps1"
if (-not $SkipBuild) { & "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly -UnknownInflightAcceptance }
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $FoundationRoot ('.local/foundation-ui-' + [Guid]::NewGuid().ToString('N'))))
if (-not $fixtureRoot.StartsWith($FoundationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $fixtureRoot)) { throw 'Invalid new owned fixture.' }
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$layout = Join-Path $fixtureRoot 'application bundle'
Copy-Item -LiteralPath (Join-Path $FoundationRoot 'build/windows/x64/runner/Debug') -Destination $layout -Recurse
$manifestPath = Join-Path $layout 'foundation.manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest.appRoot = $layout
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$profile = Join-Path $fixtureRoot 'profile'
New-Item -ItemType Directory -Path $profile | Out-Null
$savedProfile = $env:LOCALAPPDATA
$savedRole = $env:SERVERDECK_UI_ROLE
$savedScenario = $env:SERVERDECK_UI_SCENARIO
Push-Location $FoundationRoot
try {
    $env:LOCALAPPDATA = $profile
    $env:SERVERDECK_UI_ROLE = 'primary'
    $env:SERVERDECK_UI_SCENARIO = 'unknown-inflight'
    $binary = Join-Path $layout 'serverdeck.exe'
    Invoke-FoundationCommand $FoundationFlutter @('drive', '--no-pub', '--driver', 'test_driver/integration_test.dart', '--target', 'integration_test/unknown_inflight_test.dart', '--use-application-binary', $binary, '--no-keep-app-running', '-d', 'windows')
    $stagePath = Join-Path $profile 'ui-inflight/stage-finished'
    if (-not (Test-Path -LiteralPath $stagePath) -or (Get-Item -LiteralPath $stagePath).Length -gt 4096) { throw 'Unknown inflight stage proof missing.' }
    $stage = Get-Content -LiteralPath $stagePath -Raw | ConvertFrom-Json
    if ($stage.format -ne 1 -or $stage.scenario -ne 'unknown-inflight-crash' -or $stage.storeRevision -ne '3') { throw 'Unexpected unknown inflight stage.' }
    $env:SERVERDECK_UI_ROLE = 'reopen'
    Invoke-FoundationCommand $FoundationFlutter @('drive', '--no-pub', '--driver', 'test_driver/integration_test.dart', '--target', 'integration_test/unknown_inflight_test.dart', '--use-application-binary', $binary, '--no-keep-app-running', '-d', 'windows')
    $proofPath = Join-Path $profile 'ui-inflight/accepted'
    if (-not (Test-Path -LiteralPath $proofPath) -or (Get-Item -LiteralPath $proofPath).Length -gt 4096) { throw 'Unknown inflight final proof missing.' }
    $proof = Get-Content -LiteralPath $proofPath -Raw | ConvertFrom-Json
    if ($proof.format -ne 1 -or $proof.scenario -ne 'unknown-inflight-crash-reopen' -or $proof.storeRevision -ne '3') { throw 'Unexpected unknown inflight proof.' }
} finally {
    $env:LOCALAPPDATA = $savedProfile
    $env:SERVERDECK_UI_ROLE = $savedRole
    $env:SERVERDECK_UI_SCENARIO = $savedScenario
    Pop-Location
}
# Preserve all owned synthetic data and diagnostics; no runtime deletion.
