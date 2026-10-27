[CmdletBinding()]
param([switch]$PrepareOnly,[string]$PreparedFixture)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-artifact.ps1"
if ($PrepareOnly -and $PreparedFixture) { throw 'Choose preparation or an existing prepared fixture.' }
if (-not $PreparedFixture) {
& "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly -OwnerRecoveryAcceptance
$fixtureRoot=[IO.Path]::GetFullPath((Join-Path $FoundationRoot ('.local/foundation-ui-' + [Guid]::NewGuid().ToString('N'))))
if (-not $fixtureRoot.StartsWith($FoundationRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture outside workspace.' }
if (Test-Path -LiteralPath $fixtureRoot) { throw 'Fixture already exists.' }
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$layout=Join-Path $fixtureRoot 'application bundle'
Copy-Item -LiteralPath (Join-Path $FoundationRoot 'build/windows/x64/runner/Debug') -Destination $layout -Recurse
$manifestPath=Join-Path $layout 'foundation.manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.testOnly -isnot [bool] -or $manifest.testOnly -ne $false) { throw 'Normal owner build required.' }
$manifest.appRoot=$layout
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$profile=Join-Path $fixtureRoot 'profile'
[void][IO.Directory]::CreateDirectory($profile)
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
try { $ownerSid=$identity.User.Value } finally { $identity.Dispose() }
Write-NativeIsarJson (Join-Path $fixtureRoot 'owner-ui-prepared.json') ([ordered]@{
    schemaVersion=1;ownerSid=$ownerSid;fixture=$fixtureRoot;sourceSnapshotSha256=(Get-NativeArtifactSourceSnapshot).sha256;
    bundleTreeSha256=Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $layout);fullAcceptance=$false
})
if ($PrepareOnly) { 'OWNER_UI_PREPARED_FIXTURE='+$fixtureRoot; return }
} else {
    $fixtureRoot=[IO.Path]::GetFullPath($PreparedFixture,(Get-Location).ProviderPath)
    if ([IO.Path]::GetDirectoryName($fixtureRoot) -cne (Join-Path $FoundationRoot '.local') -or
        [IO.Path]::GetFileName($fixtureRoot) -cnotmatch '^foundation-ui-[a-f0-9]{32}$') { throw 'Prepared fixture outside owned namespace.' }
    Assert-NativeIsarPlainPath $fixtureRoot
    $layout=Join-Path $fixtureRoot 'application bundle'
    $profile=Join-Path $fixtureRoot 'profile'
    Assert-NativeIsarPlainPath $profile
    $record=Read-NativeIsarArtifactJson (Join-Path $fixtureRoot 'owner-ui-prepared.json')
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try { $sid=$identity.User.Value } finally { $identity.Dispose() }
    if ($record.schemaVersion -ne 1 -or $record.fixture -cne $fixtureRoot -or $record.ownerSid -cne $sid -or
        $record.fullAcceptance -ne $false -or $record.sourceSnapshotSha256 -cne (Get-NativeArtifactSourceSnapshot).sha256 -or
        $record.bundleTreeSha256 -cne (Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $layout))) { throw 'Prepared owner UI bindings changed.' }
    if (-not (Test-Path -LiteralPath $profile -PathType Container) -or @(Get-ChildItem -LiteralPath $profile -Force).Count) { throw 'Fresh prepared profile required.' }
}
Write-NativeIsarJson (Join-Path $fixtureRoot 'owner-ui-run-claim.json') ([ordered]@{schemaVersion=1;status='attempted';fullAcceptance=$false})
$ownerSavedLocalAppData=$env:LOCALAPPDATA
$ownerSavedUiRole=$env:SERVERDECK_UI_ROLE
$ownerSavedUiScenario=$env:SERVERDECK_UI_SCENARIO
Push-Location $FoundationRoot
try {
    $env:LOCALAPPDATA=$profile
    $env:SERVERDECK_UI_ROLE='primary'
    $env:SERVERDECK_UI_SCENARIO='owner-recovery'
    Invoke-FoundationCommand $FoundationFlutter @('drive','--no-pub','--driver','test_driver/integration_test.dart','--target','integration_test/owner_recovery_test.dart','--use-application-binary',(Join-Path $layout 'serverdeck.exe'),'--no-keep-app-running','-d','windows')
    $stagePath=Join-Path $profile 'owner-recovery/stage-finished'
    if (-not (Test-Path -LiteralPath $stagePath) -or (Get-Item -LiteralPath $stagePath).Length -gt 4096) { throw 'Owner recovery stage proof missing.' }
    $stage=Get-Content -LiteralPath $stagePath -Raw | ConvertFrom-Json
    $generationPattern='^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
    if ($stage.format -ne 1 -or $stage.generation -cnotmatch $generationPattern -or $stage.serverPid -le 0 -or $stage.uiPid -le 0) { throw 'Owner recovery stage proof invalid.' }
    $env:SERVERDECK_UI_ROLE='reopen'
    Invoke-FoundationCommand $FoundationFlutter @('drive','--no-pub','--driver','test_driver/integration_test.dart','--target','integration_test/owner_recovery_test.dart','--use-application-binary',(Join-Path $layout 'serverdeck.exe'),'--no-keep-app-running','-d','windows')
    $acceptedPath=Join-Path $profile 'owner-recovery/accepted'
    if (-not (Test-Path -LiteralPath $acceptedPath) -or (Get-Item -LiteralPath $acceptedPath).Length -gt 4096) { throw 'Owner recovery acceptance proof missing.' }
    $accepted=Get-Content -LiteralPath $acceptedPath -Raw | ConvertFrom-Json
    if ($accepted.format -ne 1 -or $accepted.scenario -cne 'normal-owner-ui-loss-recovery-reopen' -or $accepted.storeRevision -cne '3' -or $accepted.receiptCount -ne 3 -or $accepted.generation -cnotmatch $generationPattern -or $accepted.generation -ceq $stage.generation) { throw 'Owner recovery acceptance proof invalid.' }
    'COMPILED_UI_NORMAL_OWNER_LOSS_RECOVERY_ACCEPTED'
    $fixtureRoot
} finally {
    $env:LOCALAPPDATA=$ownerSavedLocalAppData
    $env:SERVERDECK_UI_ROLE=$ownerSavedUiRole
    $env:SERVERDECK_UI_SCENARIO=$ownerSavedUiScenario
    Pop-Location
}
# Retain synthetic data/failure evidence. No arbitrary-PID kill or recursive cleanup.
