[CmdletBinding()]
param([switch]$SkipBuild)
. "$PSScriptRoot/foundation-sdk.ps1"
if (-not $SkipBuild) { & "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly -LossAcceptance }
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
    $env:SERVERDECK_UI_SCENARIO = 'loss-recovery'
    $binary = Join-Path $layout 'serverdeck.exe'
    Invoke-FoundationCommand $FoundationFlutter @('drive', '--no-pub', '--driver', 'test_driver/integration_test.dart', '--target', 'integration_test/loss_recovery_test.dart', '--use-application-binary', $binary, '--no-keep-app-running', '-d', 'windows')
    $stagePath = Join-Path $profile 'ui-loss/stage-finished'
    if (-not (Test-Path -LiteralPath $stagePath) -or (Get-Item -LiteralPath $stagePath).Length -gt 4096) { throw 'UI loss stage proof missing.' }
    $stage = Get-Content -LiteralPath $stagePath -Raw | ConvertFrom-Json
    if ($stage.format -ne 1 -or $stage.scenario -ne 'ui-loss-status-retry') { throw 'Unexpected UI loss stage proof.' }
    $env:SERVERDECK_UI_ROLE = 'reopen'
    Invoke-FoundationCommand $FoundationFlutter @('drive', '--no-pub', '--driver', 'test_driver/integration_test.dart', '--target', 'integration_test/loss_recovery_test.dart', '--use-application-binary', $binary, '--no-keep-app-running', '-d', 'windows')
    $proofPath = Join-Path $profile 'ui-loss/accepted'
    if (-not (Test-Path -LiteralPath $proofPath) -or (Get-Item -LiteralPath $proofPath).Length -gt 4096) { throw 'UI loss acceptance proof missing.' }
    $proof = Get-Content -LiteralPath $proofPath -Raw | ConvertFrom-Json
    if ($proof.format -ne 1 -or $proof.scenario -ne 'ui-loss-status-retry-reopen') { throw 'Unexpected UI loss acceptance proof.' }
} finally {
    $env:LOCALAPPDATA = $taskSavedLocalAppData
    $env:SERVERDECK_UI_ROLE = $taskSavedUiRole
    $env:SERVERDECK_UI_SCENARIO = $taskSavedUiScenario
    Pop-Location
}
# Keep ignored synthetic fixtures for diagnosis; no live runtime deletion.
