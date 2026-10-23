[CmdletBinding()]
param([Parameter(Mandatory)][string]$FixtureRoot)
. "$PSScriptRoot/mcp-fixture.ps1"
$FixtureRoot = Resolve-McpFixtureRoot $FixtureRoot
[void](Read-McpFixtureIdentity $FixtureRoot)
if ($env:LOCALAPPDATA -ine (Join-Path $FixtureRoot 'profile')) { throw 'Owned driver profile required.' }
. "$PSScriptRoot/foundation-sdk.ps1"
Push-Location $McpFixtureRepository
try {
    Invoke-FoundationCommand $FoundationFlutter @('drive','--no-pub',
        '--driver','test_driver/integration_test.dart',
        '--target','integration_test/mcp_test.dart',
        '--use-application-binary',(Join-Path $FixtureRoot 'application bundle/serverdeck.exe'),
        '--no-keep-app-running','-d','windows')
} finally { Pop-Location }
