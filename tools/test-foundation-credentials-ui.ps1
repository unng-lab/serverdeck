[CmdletBinding()]
param([switch]$SkipBuild)
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-isar-inputs.ps1"
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
Assert-NativeIsarPlainPath $fixtureRoot
$scanner = Join-Path $layout 'credential-output-scanner.exe'
Push-Location (Join-Path $FoundationRoot 'packages/serverdeck_locald')
try {
    Invoke-FoundationCommand $FoundationDart @('compile', 'exe', 'test/support/credential_output_scan_child.dart', '-o', $scanner) *> (Join-Path $fixtureRoot 'scanner-compilation.private.txt')
} finally { Pop-Location }
function Invoke-CredentialOutputScanner {
    param([string]$Mode, [string]$Expected)
    $scannerLog = Join-Path $fixtureRoot ('scanner-' + $Mode + '.private.txt')
    Invoke-FoundationCommand $scanner @($profile, $Mode) *> $scannerLog
    $scannerLines = @(Get-Content -LiteralPath $scannerLog)
    if ($scannerLines.Count -ne 1 -or $scannerLines[0] -cne $Expected) { throw 'Credential output scanner proof missing.' }
}
Invoke-CredentialOutputScanner 'prepare' 'CREDENTIAL_OUTPUT_CAPTURE_PREPARED'
$taskSavedLocalAppData = $env:LOCALAPPDATA
$taskSavedCredentialStep = $env:SERVERDECK_CREDENTIAL_STEP
Push-Location $FoundationRoot
try {
    $env:LOCALAPPDATA = $profile
    foreach ($step in 0..9) {
        $env:SERVERDECK_CREDENTIAL_STEP = [string]$step
        $driveLog = Join-Path $fixtureRoot "credential-output/step-$step.private.txt"
        Invoke-FoundationCommand $FoundationFlutter @('drive', '--no-pub', '--driver', 'test_driver/integration_test.dart', '--target', 'integration_test/credential_journey_test.dart', '--use-application-binary', (Join-Path $layout 'serverdeck.exe'), '--no-keep-app-running', '-d', 'windows') *> $driveLog
        $proofPath = Join-Path $profile "ui-credentials/step-$step.json"
        if (-not (Test-Path -LiteralPath $proofPath) -or (Get-Item -LiteralPath $proofPath).Length -gt 4096) { throw 'UI credential stage proof missing.' }
        $proof = Get-Content -LiteralPath $proofPath -Raw | ConvertFrom-Json
        $expectedRevision = if ($step -ge 8) { '257' } elseif ($step -eq 7) { '7' } else { [string]($step + 1) }
        if ($proof.format -ne 1 -or $proof.scenario -ne 'ui-credential-reopen' -or $proof.step -ne $step -or $proof.storeRevision -ne $expectedRevision) { throw 'Unexpected UI credential stage proof.' }
        $expectedProfiles = if ($step -ge 8) { 250 } elseif ($step -ge 6) { 0 } else { 1 }
        if ($proof.profileCount -ne $expectedProfiles -or $proof.profilesDigest -notmatch '^[a-f0-9]{64}$') { throw 'UI profile inventory proof mismatch.' }
        if ($proof.privateFilesScanned -lt 4 -or $proof.privateBytesScanned -le 0 -or $proof.receiptKeyScan -ne $true -or $proof.scanAfterDiscoveryRemoval -ne $true) { throw 'UI private file scan proof missing.' }
        Invoke-CredentialOutputScanner ([string]$step) ('CREDENTIAL_OUTPUT_STEP_' + $step + '_CLEAN_PROVED')
        $outputProofPath = Join-Path $fixtureRoot "credential-output/output-step-$step.json"
        $outputProof = Get-Content -LiteralPath $outputProofPath -Raw | ConvertFrom-Json
        if ($outputProof.format -ne 1 -or $outputProof.scenario -cne 'credential-output-scan' -or $outputProof.step -ne $step -or
            $outputProof.stageProofSha256 -cne (Get-NativeIsarDigest $proofPath) -or $outputProof.diagnosticFilesScanned -ne 1 -or
            $outputProof.diagnosticBytesScanned -le 0 -or $outputProof.diagnosticScanAfterClose -ne $true -or
            $outputProof.receiptKeyScan -ne $true -or $outputProof.fullAcceptance -ne $false) { throw 'Credential diagnostic output proof mismatch.' }
        if ($step -eq 9) {
            $quotaProof = Get-Content -LiteralPath (Join-Path $profile 'ui-credentials/step-8.json') -Raw | ConvertFrom-Json
            if ($proof.profilesDigest -ne $quotaProof.profilesDigest -or $proof.generation -eq $quotaProof.generation -or $null -ne $proof.selected) { throw 'UI quota reopen proof mismatch.' }
        }
    }
    Invoke-CredentialOutputScanner 'negative' 'CREDENTIAL_OUTPUT_SYNTHETIC_LEAK_REJECTED'
    Write-NativeIsarJson (Join-Path $fixtureRoot 'output-privacy-result.json') ([ordered]@{
        schemaVersion=1;scenario='credential-ui-completed-output';status='passed';steps=10;
        syntheticLeakRejected=$true;fullAcceptance=$false;distributionReady=$false;
        scanned=@('postclose-product-files','completed-flutter-drive-all-streams');
        excluded=@('embedded-synthetic-inputs','live-uncommitted-native-files','foreign-temp','full-Q05')
    })
    'CREDENTIAL_UI_COMPLETED_OUTPUT_PRIVACY_PASSED'
} finally {
    $env:LOCALAPPDATA = $taskSavedLocalAppData
    $env:SERVERDECK_CREDENTIAL_STEP = $taskSavedCredentialStep
    Pop-Location
}
# Preserve ignored synthetic fixtures; never delete live runtime or user data.
