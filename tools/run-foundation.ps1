[CmdletBinding()]
param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug', [switch]$BuildOnly, [switch]$BootstrapAcceptance, [switch]$FoundationAcceptance, [switch]$LossAcceptance, [switch]$CredentialAcceptance, [switch]$UnknownInflightAcceptance, [switch]$RuntimeDiagnosticsAcceptance, [switch]$OwnerRecoveryAcceptance, [switch]$ForeignUserAcceptance)
$targets = @()
if ($BootstrapAcceptance) { $targets += 'integration_test/bootstrap_test.dart' }
if ($FoundationAcceptance) { $targets += 'integration_test/foundation_test.dart' }
if ($LossAcceptance) { $targets += 'integration_test/loss_recovery_test.dart' }
if ($CredentialAcceptance) { $targets += 'integration_test/credential_journey_test.dart' }
if ($UnknownInflightAcceptance) { $targets += 'integration_test/unknown_inflight_test.dart' }
if ($RuntimeDiagnosticsAcceptance) { $targets += 'integration_test/runtime_diagnostics_test.dart' }
if ($OwnerRecoveryAcceptance) { $targets += 'integration_test/owner_recovery_test.dart' }
if ($ForeignUserAcceptance) { $targets += 'integration_test/foreign_user_test.dart' }
if ($targets.Count -gt 1) { throw 'Choose one acceptance target.' }
$target = ''
if ($targets.Count) { $target = $targets[0] }
# Every explicit fixture uses the same production format3 assembly and source
# selection. The integration entry changes UI behavior, never native role proof.
& "$PSScriptRoot/run-serverdeck.ps1" -Configuration $Configuration -BuildOnly:$BuildOnly -IntegrationTarget $target
