[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/foundation-user-ui.ps1"
. "$PSScriptRoot/foundation-environment-actor.ps1"
. "$PSScriptRoot/environment-checkpoint-binding.ps1"

# An owned synthetic profile baseline, not a disposable OS/reboot certification.
$checkpointBaselineRoot=Join-Path $FoundationRoot ('.local/environment-acceptance-'+[Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $checkpointBaselineRoot
[void][IO.Directory]::CreateDirectory($checkpointBaselineRoot)
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
try {$sid=$identity.User.Value} finally {$identity.Dispose()}
$uuid=[string](Get-CimInstance Win32_ComputerSystemProduct).UUID
if($uuid -notmatch '^[a-fA-F0-9-]{36}$' -or $uuid -match '^(0|-)+$'){throw 'Actual machine identity unavailable.'}
$facts=[ordered]@{sid=$sid;machineUuid=$uuid}
Invoke-NativeArtifactCandidateScope -Artifact $Artifact -PreserveNormalBundles -Action {
    & "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly -ForeignUserAcceptance *> (Join-Path $checkpointBaselineRoot 'build.private.txt')
    $bundle=Join-Path $checkpointBaselineRoot 'application bundle'
    Copy-Item -LiteralPath (Join-Path $FoundationRoot 'build/windows/x64/runner/Debug') -Destination $bundle -Recurse
    $manifestPath=Join-Path $bundle 'foundation.manifest.json'
    $manifest=Read-NativeIsarArtifactJson $manifestPath
    if($manifest.testOnly -ne $false){throw 'Production-entry bundle required.'}
    $manifest.appRoot=$bundle
    [IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    Push-Location (Join-Path $FoundationRoot 'packages/serverdeck_locald')
    try {Invoke-FoundationCommand $FoundationDart @('compile','exe','test/support/environment_checkpoint_child.dart','-o',(Join-Path $checkpointBaselineRoot 'checkpoint-actor.exe')) *> (Join-Path $checkpointBaselineRoot 'actor-build.private.txt')}
    finally {Pop-Location}
    Invoke-FoundationEnvironmentActor -Root $checkpointBaselineRoot -Mode seed -Marker 'ENVIRONMENT_DURABLE_CHECKPOINT_CREATED'
    Invoke-FoundationUserUi -Fixture $checkpointBaselineRoot -Role owner -OwnerSid $sid -OutputRoot $checkpointBaselineRoot -CheckpointMode capture
    Invoke-FoundationEnvironmentActor -Root $checkpointBaselineRoot -Mode verify -Marker 'ENVIRONMENT_DURABLE_STATE_AND_CREDENTIAL_VERIFIED'
    $record=[ordered]@{
        schemaVersion=1;kind='owned-environment-checkpoint';fixture=$checkpointBaselineRoot;facts=$facts;
        sourceSnapshotSha256=(Get-NativeArtifactSourceSnapshot).sha256;
        bundleTreeSha256=Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $bundle);
        actorSha256=Get-NativeIsarDigest (Join-Path $checkpointBaselineRoot 'checkpoint-actor.exe');
        durableCheckpointSha256=Get-NativeIsarDigest (Join-Path $checkpointBaselineRoot 'profile/durable-checkpoint.json');
        clientCheckpointSha256=Get-NativeIsarDigest (Join-Path $checkpointBaselineRoot 'profile/client-checkpoint.json');
        fullAcceptance=$false;distributionReady=$false
    }
    Write-NativeIsarJson (Join-Path $checkpointBaselineRoot 'client-baseline-checkpoint.json') $record
    $record=Read-NativeIsarArtifactJson (Join-Path $checkpointBaselineRoot 'client-baseline-checkpoint.json')
    Assert-EnvironmentCheckpointBinding -Root $checkpointBaselineRoot -Checkpoint $record -Facts $facts
    $rejected=@()
    foreach($field in @('sourceSnapshotSha256','bundleTreeSha256','durableCheckpointSha256','clientCheckpointSha256')) {
        $bad=$record|ConvertTo-Json -Depth 10|ConvertFrom-Json
        $bad.$field='0'*64
        $refused=$false
        try {Assert-EnvironmentCheckpointBinding -Root $checkpointBaselineRoot -Checkpoint $bad -Facts $facts}
        catch {if($_.Exception.Message -cne 'Checkpoint identity, source or binary binding mismatch.'){throw};$refused=$true}
        if(!$refused){throw 'Changed checkpoint binding was accepted.'}
        $rejected+=$field
    }
    Invoke-FoundationUserUi -Fixture $checkpointBaselineRoot -Role owner -OwnerSid $sid -OutputRoot $checkpointBaselineRoot -CheckpointMode verify
    Invoke-FoundationEnvironmentActor -Root $checkpointBaselineRoot -Mode verify -Marker 'ENVIRONMENT_DURABLE_STATE_AND_CREDENTIAL_VERIFIED'
    $proof=Read-NativeIsarArtifactJson (Join-Path $checkpointBaselineRoot 'profile/client-verification.json')
    if($proof.format -ne 1 -or $proof.scenario -cne 'production-client-durable-checkpoint' -or
        $proof.checkpointSha256 -cne $record.clientCheckpointSha256 -or $proof.fullAcceptance -ne $false -or $proof.rebootProven -ne $false){throw 'Baseline client proof mismatch.'}
    Write-NativeIsarJson (Join-Path $checkpointBaselineRoot 'client-baseline-result.json') ([ordered]@{
        schemaVersion=1;status='passed';scope='compiled-production-client-api-synthetic-profile-baseline';
        checkpointSha256=Get-NativeIsarDigest (Join-Path $checkpointBaselineRoot 'client-baseline-checkpoint.json');
        clientProofSha256=Get-NativeIsarDigest (Join-Path $checkpointBaselineRoot 'profile/client-verification.json');
        rejectedBindings=$rejected;fullAcceptance=$false;distributionReady=$false;rebootProven=$false;
        excluded=@('disposable-Windows11-certification','real-reboot','other-user','runtime-offline','physical-Q12')
    })
}
'CLIENT_CHECKPOINT_BASELINE_PASSED_REBOOT_UNPROVEN'
$checkpointBaselineRoot
