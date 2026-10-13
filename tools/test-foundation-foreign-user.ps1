[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Prepare','VerifyForeign','VerifyOwner')][string]$Phase,
    [string]$Artifact,[string]$Fixture,[string]$ForeignProof,[switch]$DisposableEnvironment)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-artifact.ps1"
. "$PSScriptRoot/foundation-environment-facts.ps1"
. "$PSScriptRoot/foundation-user-ui.ps1"
. "$PSScriptRoot/environment-acceptance-claim.ps1"
if (-not $DisposableEnvironment) { throw 'Prepared disposable Windows11 users required; no accounts or sessions are changed automatically.' }
if ($Phase -eq 'Prepare') {
    if (-not $Artifact -or $Fixture -or $ForeignProof) { throw 'Prepare requires a complete artifact only.' }
    & "$PSScriptRoot/test-foundation-environment.ps1" -Phase Prepare -Artifact $Artifact -DisposableEnvironment -ForeignUserTarget
    return
}
if (-not $Fixture -or $Artifact) { throw 'Existing prepared fixture required.' }
$root=[IO.Path]::GetFullPath($Fixture,(Get-Location).ProviderPath)
if ([IO.Path]::GetDirectoryName($root) -cne (Join-Path $FoundationRoot '.local') -or
    [IO.Path]::GetFileName($root) -cnotmatch '^environment-acceptance-[a-f0-9]{32}$') { throw 'Owned foreign-user fixture required.' }
Assert-NativeIsarPlainPath $root
$recordPath=Join-Path $root 'environment-checkpoint.json'
$checkpoint=Read-NativeIsarArtifactJson $recordPath
$digest=Get-NativeIsarDigest $recordPath
$facts=Get-EnvironmentFacts
if ($checkpoint.schemaVersion -ne 1 -or $checkpoint.foreignUserTarget -isnot [bool] -or -not $checkpoint.foreignUserTarget -or
    $checkpoint.fixture -cne $root -or $checkpoint.facts.machineUuid -cne $facts.machineUuid -or
    $checkpoint.sourceSnapshotSha256 -cne (Get-NativeArtifactSourceSnapshot).sha256 -or
    $checkpoint.bundleTreeSha256 -cne (Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot (Join-Path $root 'application bundle')))) {
    throw 'Prepared foreign-user bindings changed.'
}
if ($Phase -eq 'VerifyForeign') {
    if ($ForeignProof) { throw 'Foreign proof is produced, not supplied.' }
    if ($facts.sid -ceq $checkpoint.facts.sid) { 'FOREIGN_USER_UNPROVEN_SAME_ACTUAL_SID'; exit 2 }
    # The foreign caller never writes into the owner's fixture. Its retained
    # attempt is unique per checkpoint under its own actual OS profile.
    $local=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData))
    Assert-NativeIsarPlainPath $local
    $output=Join-Path $local ('ServerDeckAcceptance/foreign-'+$digest)
    Assert-NativeIsarPlainPath $output
    if (Test-Path -LiteralPath $output) { throw 'Foreign-user checkpoint attempt already used.' }
    [void][IO.Directory]::CreateDirectory($output)
    Write-NativeIsarJson (Join-Path $output 'attempt.json') ([ordered]@{schemaVersion=1;status='attempted';checkpointSha256=$digest;facts=$facts;fullAcceptance=$false})
    Invoke-FoundationUserUi -Fixture $root -Role foreign -OwnerSid $checkpoint.facts.sid -OutputRoot $output
    $proof=Join-Path $output 'foreign-result.json'
    Write-NativeIsarJson $proof ([ordered]@{schemaVersion=1;status='passed';checkpointSha256=$digest;facts=$facts;
        sourceSnapshotSha256=$checkpoint.sourceSnapshotSha256;bundleTreeSha256=$checkpoint.bundleTreeSha256;
        marker='COMPILED_ACTUAL_FOREIGN_USER_ACCESS_REFUSAL_PROVED';fullAcceptance=$false})
    'ACTUAL_FOREIGN_USER_CLIENT_REFUSAL_PROOF='+$proof
    return
}
if ($facts.sid -cne $checkpoint.facts.sid -or -not $ForeignProof) { throw 'Original owner and the copied metadata-only foreign proof required.' }
$proofPath=[IO.Path]::GetFullPath($ForeignProof,(Get-Location).ProviderPath)
Assert-NativeIsarPlainPath $proofPath
if (-not $proofPath.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Copy only the foreign metadata result into this owned fixture first.' }
$proof=Read-NativeIsarArtifactJson $proofPath
if ($proof.schemaVersion -ne 1 -or $proof.status -cne 'passed' -or $proof.fullAcceptance -ne $false -or
    $proof.marker -cne 'COMPILED_ACTUAL_FOREIGN_USER_ACCESS_REFUSAL_PROVED' -or $proof.facts.sid -ceq $facts.sid -or
    $proof.facts.machineUuid -cne $facts.machineUuid -or $proof.checkpointSha256 -cne $digest -or
    $proof.sourceSnapshotSha256 -cne $checkpoint.sourceSnapshotSha256 -or $proof.bundleTreeSha256 -cne $checkpoint.bundleTreeSha256) { throw 'Foreign metadata proof does not match this case.' }
# Existing shared checkpoint claim prevents replay and cross-phase reuse.
& "$PSScriptRoot/test-foundation-environment.ps1" -Phase Baseline -Fixture $root -DisposableEnvironment
$after=Join-Path $root 'owner-after-foreign'
if (Test-Path -LiteralPath $after) { throw 'Owner recovery output already exists.' }
[void][IO.Directory]::CreateDirectory($after)
Invoke-FoundationUserUi -Fixture $root -Role owner -OwnerSid $facts.sid -OutputRoot $after
Write-NativeIsarJson (Join-Path $root 'foreign-owner-result.json') ([ordered]@{schemaVersion=1;status='passed';checkpointSha256=$digest;foreignProofSha256=Get-NativeIsarDigest $proofPath;fullAcceptance=$false;distributionReady=$false})
'ACTUAL_FOREIGN_USER_REFUSAL_AND_ORIGINAL_OWNER_RECOVERY_ACCEPTED'
