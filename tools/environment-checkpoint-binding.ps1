. "$PSScriptRoot/native-artifact.ps1"

function Assert-EnvironmentCheckpointBinding {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)]$Checkpoint,[Parameter(Mandatory)]$Facts)
    Assert-NativeIsarPlainPath $Root
    if ($Checkpoint.schemaVersion -ne 1 -or $Checkpoint.kind -cne 'owned-environment-checkpoint' -or
        $Checkpoint.fixture -cne $Root -or $Checkpoint.fullAcceptance -ne $false -or $Checkpoint.distributionReady -ne $false -or
        $Checkpoint.facts.sid -cne $Facts.sid -or $Checkpoint.facts.machineUuid -cne $Facts.machineUuid -or
        $Checkpoint.sourceSnapshotSha256 -cne (Get-NativeArtifactSourceSnapshot).sha256 -or
        $Checkpoint.actorSha256 -cne (Get-NativeIsarDigest (Join-Path $Root 'checkpoint-actor.exe')) -or
        $Checkpoint.bundleTreeSha256 -cne (Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot (Join-Path $Root 'application bundle'))) -or
        $Checkpoint.durableCheckpointSha256 -cne (Get-NativeIsarDigest (Join-Path $Root 'profile/durable-checkpoint.json')) -or
        $Checkpoint.clientCheckpointSha256 -cne (Get-NativeIsarDigest (Join-Path $Root 'profile/client-checkpoint.json'))) {
        throw 'Checkpoint identity, source or binary binding mismatch.'
    }
}
