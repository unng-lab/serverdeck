[CmdletBinding()]
param([switch]$SkipBuild)
. "$PSScriptRoot/foundation-sdk.ps1"
if (-not $SkipBuild) { & "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly -CredentialAcceptance }
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
$taskSavedCredentialStep = $env:SERVERDECK_CREDENTIAL_STEP
Push-Location $FoundationRoot
try {
    $env:LOCALAPPDATA = $profile
    foreach ($step in 0..9) {
        $env:SERVERDECK_CREDENTIAL_STEP = [string]$step
        Invoke-FoundationCommand $FoundationFlutter @('drive', '--no-pub', '--driver', 'test_driver/integration_test.dart', '--target', 'integration_test/credential_journey_test.dart', '--use-application-binary', (Join-Path $layout 'serverdeck.exe'), '--no-keep-app-running', '-d', 'windows')
        $proofPath = Join-Path $profile "ui-credentials/step-$step.json"
        if (-not (Test-Path -LiteralPath $proofPath) -or (Get-Item -LiteralPath $proofPath).Length -gt 4096) { throw 'UI credential stage proof missing.' }
        $proof = Get-Content -LiteralPath $proofPath -Raw | ConvertFrom-Json
        $expectedRevision = if ($step -ge 8) { '257' } elseif ($step -eq 7) { '7' } else { [string]($step + 1) }
        if ($proof.format -ne 1 -or $proof.scenario -ne 'ui-credential-reopen' -or $proof.step -ne $step -or $proof.storeRevision -ne $expectedRevision) { throw 'Unexpected UI credential stage proof.' }
        $expectedProfiles = if ($step -ge 8) { 250 } elseif ($step -ge 6) { 0 } else { 1 }
        if ($proof.profileCount -ne $expectedProfiles -or $proof.profilesDigest -notmatch '^[a-f0-9]{64}$') { throw 'UI profile inventory proof mismatch.' }
        if ($proof.privateFilesScanned -lt 4 -or $proof.privateBytesScanned -le 0 -or $proof.receiptKeyScan -ne $true -or $proof.scanAfterDiscoveryRemoval -ne $true) { throw 'UI private file scan proof missing.' }
        if ($step -eq 9) {
            $quotaProof = Get-Content -LiteralPath (Join-Path $profile 'ui-credentials/step-8.json') -Raw | ConvertFrom-Json
            if ($proof.profilesDigest -ne $quotaProof.profilesDigest -or $proof.generation -eq $quotaProof.generation -or $null -ne $proof.selected) { throw 'UI quota reopen proof mismatch.' }
        }
    }
} finally {
    $env:LOCALAPPDATA = $taskSavedLocalAppData
    $env:SERVERDECK_CREDENTIAL_STEP = $taskSavedCredentialStep
    Pop-Location
}
# Preserve ignored synthetic fixtures; never delete live runtime or user data.
