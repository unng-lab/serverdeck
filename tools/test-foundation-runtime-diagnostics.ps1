[CmdletBinding()]
param()
. "$PSScriptRoot/foundation-sdk.ps1"
& "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly -RuntimeDiagnosticsAcceptance
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $FoundationRoot ('.local/runtime-diagnostics-' + [Guid]::NewGuid().ToString('N'))))
if (-not $fixtureRoot.StartsWith($FoundationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture outside workspace.' }
if (Test-Path -LiteralPath $fixtureRoot) { throw 'Fixture already exists.' }
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$layout = Join-Path $fixtureRoot 'application bundle'
Copy-Item -LiteralPath (Join-Path $FoundationRoot 'build/windows/x64/runner/Debug') -Destination $layout -Recurse
$log = Join-Path $fixtureRoot 'drive.txt'
Push-Location $FoundationRoot
try {
    Invoke-FoundationCommand $FoundationFlutter @('drive', '--no-pub', '--timeout', '120', '--driver', 'test_driver/integration_test.dart', '--target', 'integration_test/runtime_diagnostics_test.dart', '--use-application-binary', (Join-Path $layout 'serverdeck.exe'), '--no-keep-app-running', '-d', 'windows') *> $log
    $lines = Get-Content -LiteralPath $log
    if (@($lines | Where-Object { $_ -ceq 'COMPILED_UI_RUNTIME_DIAGNOSTICS_PRIVACY_PROVED' }).Count -ne 1) { throw 'Runtime diagnostic privacy proof missing.' }
    foreach ($marker in @('synthetic-password-231', 'synthetic-private-key-231', 'synthetic-passphrase-231', 'synthetic-private-path-231')) {
        if ($lines | Select-String -SimpleMatch $marker -Quiet) { throw 'Runtime diagnostic output marker found.' }
    }
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'result.json'), (([ordered]@{ format = 1; scenario = 'ui-runtime-diagnostics'; configuration = 'Debug'; passed = $true; fullAcceptance = $false }) | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    'COMPILED_UI_RUNTIME_DIAGNOSTICS_ACCEPTANCE_PASSED'
} finally { Pop-Location }
# Preserve ignored synthetic evidence; no user profile, ACL or privilege changes.
