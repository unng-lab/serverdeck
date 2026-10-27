[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/qualification-available-diagnostics.ps1"
$snapshot=Get-NativeArtifactSourceSnapshot
$privateMarker='SYNTHETIC_PRIVATE_AVAILABLE_DIAGNOSTIC_MARKER'
$failure=$null
try {throw $privateMarker} catch {$failure=$_}
$failure.Exception.Data['ServerDeckAvailablePhase']='compiled-core-storage'
$projection=New-NativeAvailableFailureProjection -SourceSnapshot $snapshot -Failure $failure -ArtifactManifestSha256 ('a'*64) -ControlledFixture
$safe=$projection|ConvertTo-Json -Depth 8
if($projection.status -cne 'failed-phase-details' -or $projection.failedPhase -cne 'compiled-core-storage' -or
    -not $projection.controlledFixture -or $projection.sourceFrames.Count -ne 1 -or
    $projection.sourceFrames[0].file -cne 'tools/test-qualification-available-diagnostics.ps1' -or
    $projection.sourceFrames[0].line -ne 9 -or $safe.Contains($privateMarker) -or
    $safe.Contains($NativeIsarRepository) -or $safe.Contains('ScriptStackTrace') -or
    $projection.fullAcceptance -or $projection.distributionReady -or $projection.activated){throw 'Controlled available projection mismatch.'}
foreach($phase in @($null,$privateMarker)){
    $failure.Exception.Data['ServerDeckAvailablePhase']=$phase
    $invalid=New-NativeAvailableFailureProjection -SourceSnapshot $snapshot -Failure $failure -ArtifactManifestSha256 ('a'*64) -ControlledFixture
    if($invalid.status -cne 'unavailable-phase-details' -or $null -ne $invalid.failedPhase -or $invalid.sourceFrames.Count -ne 0 -or
        ($invalid|ConvertTo-Json -Depth 8).Contains($privateMarker)){throw 'Unknown available phase accepted.'}
}
$failure.Exception.Data['ServerDeckAvailablePhase']='compiled-core-storage'
$tampered=$snapshot|ConvertTo-Json -Depth 8|ConvertFrom-Json
foreach($file in $tampered.files){if($file.file -ceq 'tools/test-qualification-available-diagnostics.ps1'){$file.sha256='0'*64}}
$invalid=New-NativeAvailableFailureProjection -SourceSnapshot $tampered -Failure $failure -ArtifactManifestSha256 ('a'*64) -ControlledFixture
if($invalid.sourceFrames.Count -ne 0){throw 'Changed source accepted.'}
'AVAILABLE_FAILURE_REAL_ERROR_RECORD_KNOWN_SOURCE_AND_PRIVATE_MARKER_EXCLUSION_PASSED'
'AVAILABLE_FAILURE_UNKNOWN_MISSING_PHASE_AND_CHANGED_SOURCE_FAILED_CLOSED'
