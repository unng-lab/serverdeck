[CmdletBinding()]
param([switch]$SkipBuild)
. "$PSScriptRoot/foundation-sdk.ps1"
if (-not $SkipBuild) { & "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly -BootstrapAcceptance }
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $FoundationRoot ('.local/bootstrap-ui-' + [Guid]::NewGuid().ToString('N'))))
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
Push-Location $FoundationRoot
try {
    $env:LOCALAPPDATA = $profile
    Invoke-FoundationCommand $FoundationFlutter @('drive', '--no-pub', '--driver', 'test_driver/integration_test.dart', '--target', 'integration_test/bootstrap_test.dart', '--use-application-binary', (Join-Path $layout 'serverdeck.exe'), '--no-keep-app-running', '-d', 'windows')
} finally {
    $env:LOCALAPPDATA = $taskSavedLocalAppData
    Pop-Location
}
# Preserve this ignored fixture for diagnosis; never delete live runtime files.
