[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/qualification-test-diagnostics.ps1"
$fixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $fixture
[void][IO.Directory]::CreateDirectory($fixture)
$probe=Join-Path $fixture 'controlled-probe.dart'
$report=Join-Path $fixture 'serverdeck_windows-tests.machine.jsonl'
$privateMarker='SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER'
[IO.File]::WriteAllText($probe,@'
import 'dart:io';
import 'package:test/test.dart';
void main() {
  test('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER test name', () {
    Error.throwWithStackTrace(
      const FileSystemException('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER', '', OSError('NT_ATTRIBUTES_STATUS', -1073741790)),
      StackTrace.fromString('package:serverdeck_windows/native_attributes.dart 65:12 function\nfile:///C:/SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER/private.dart 9:2'));
  });
}
'@,[Text.UTF8Encoding]::new($false))
Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_windows')
try {
    & $FoundationDart test $probe --file-reporter "json:$report" *> (Join-Path $fixture 'controlled-probe.private.txt')
    if($LASTEXITCODE -eq 0){throw 'Controlled failure unexpectedly passed.'}
} finally {Pop-Location}
$snapshot=Get-NativeArtifactSourceSnapshot
Write-NativeQualificationTestFailure -Directory $fixture -Phase 'serverdeck_windows-tests' -SourceSnapshot $snapshot -ControlledFixture
$proofPath=Join-Path $fixture 'safe-test-failure-serverdeck_windows-tests.json'
$proof=Read-NativeIsarArtifactJson $proofPath
$safeText=[IO.File]::ReadAllText($proofPath)
$rawText=[IO.File]::ReadAllText($report)
if(-not $rawText.Contains($privateMarker) -or $safeText.Contains($privateMarker) -or
    $safeText.Contains('C:/') -or $safeText.Contains('stackTrace') -or
    $proof.status -cne 'failed-test-details' -or -not $proof.controlledFixture -or
    -not $proof.reporterComplete -or $proof.failures.Count -ne 1 -or
    $proof.failures[0].sourceFrames.Count -ne 1 -or
    $proof.failures[0].sourceFrames[0].file -cne 'packages/serverdeck_windows/lib/native_attributes.dart' -or
    $proof.failures[0].sourceFrames[0].line -ne 65 -or
    $proof.failures[0].nativeErrors[0].kind -cne 'NT_ATTRIBUTES_STATUS' -or
    $proof.failures[0].nativeErrors[0].code -ne -1073741790){throw 'Safe test failure projection mismatch.'}
$invalidFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($invalidFixture)
[IO.File]::WriteAllText((Join-Path $invalidFixture 'serverdeck_windows-tests.machine.jsonl'),$privateMarker)
Write-NativeQualificationTestFailure -Directory $invalidFixture -Phase 'serverdeck_windows-tests' -SourceSnapshot $snapshot -ControlledFixture
$invalid=Read-NativeIsarArtifactJson (Join-Path $invalidFixture 'safe-test-failure-serverdeck_windows-tests.json')
if($invalid.status -cne 'unavailable-reporter' -or $invalid.failures.Count -ne 0 -or $invalid.reporterComplete){throw 'Invalid reporter accepted.'}
'QUALIFICATION_SAFE_TEST_FAILURE_REAL_REPORTER_AND_PRIVATE_MARKER_EXCLUSION_PASSED'
'QUALIFICATION_INVALID_REPORTER_FAILED_CLOSED'
$fixture
$invalidFixture
