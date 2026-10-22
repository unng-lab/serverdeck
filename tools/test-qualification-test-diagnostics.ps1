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
foreach($code in @('WORKSPACE_CHILD_FAILED','WORKSPACE_CHILD_TIMEOUT')) {
    $childFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($childFixture)
    $childProbe=Join-Path $childFixture 'controlled-child-code.dart'
    $childReport=Join-Path $childFixture 'serverdeck_windows-tests.machine.jsonl'
    $template=[IO.File]::ReadAllText($probe).Replace("const FileSystemException('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER', '', OSError('NT_ATTRIBUTES_STATUS', -1073741790))","StateError('$code')")
    [IO.File]::WriteAllText($childProbe,$template,[Text.UTF8Encoding]::new($false))
    Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_windows')
    try {
        & $FoundationDart test $childProbe --file-reporter "json:$childReport" *> (Join-Path $childFixture 'controlled-child-code.private.txt')
        if($LASTEXITCODE -eq 0){throw 'Controlled child failure unexpectedly passed.'}
    } finally {Pop-Location}
    Write-NativeQualificationTestFailure -Directory $childFixture -Phase 'serverdeck_windows-tests' -SourceSnapshot $snapshot -ControlledFixture
    $childProofPath=Join-Path $childFixture 'safe-test-failure-serverdeck_windows-tests.json'
    $childProof=Read-NativeIsarArtifactJson $childProofPath
    $childSafe=[IO.File]::ReadAllText($childProofPath)
    if($childProof.status -cne 'failed-test-details' -or -not $childProof.controlledFixture -or
        -not $childProof.reporterComplete -or $childProof.failures.Count -ne 1 -or
        $childProof.failures[0].safeCode -cne $code -or $childProof.failures[0].sourceFrames.Count -ne 1 -or
        $childSafe.Contains($privateMarker) -or $childSafe.Contains('C:/') -or $childSafe.Contains('stackTrace')) {
        throw 'Controlled child code projection mismatch.'
    }
    'QUALIFICATION_SAFE_'+$code+'_AND_PRIVATE_MARKER_EXCLUSION_PASSED'
}
foreach($separator in @('/','\')) {
    $relativeFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($relativeFixture)
    $relativeProbe=Join-Path $relativeFixture 'controlled-relative-frame.dart'
    $relativeReport=Join-Path $relativeFixture 'serverdeck_locald-tests.machine.jsonl'
    $relativeSource='test/support/workspace_child.dart'.Replace('/',$separator)
    $dartSource=$relativeSource.Replace('\','\\')
    $template=[IO.File]::ReadAllText($probe).Replace(
        "package:serverdeck_windows/native_attributes.dart 65:12 function\nfile:///C:/SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER/private.dart 9:2",
        "$dartSource 385:7 main\n$dartSource 999999:1 invalid\n../../SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER/private.dart 9:2 private")
    [IO.File]::WriteAllText($relativeProbe,$template,[Text.UTF8Encoding]::new($false))
    Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_locald')
    try {
        & $FoundationDart test $relativeProbe --file-reporter "json:$relativeReport" *> (Join-Path $relativeFixture 'controlled-relative.private.txt')
        if($LASTEXITCODE -eq 0){throw 'Controlled relative-frame failure unexpectedly passed.'}
    } finally {Pop-Location}
    Write-NativeQualificationTestFailure -Directory $relativeFixture -Phase 'serverdeck_locald-tests' -SourceSnapshot $snapshot -ControlledFixture
    $relativeProofPath=Join-Path $relativeFixture 'safe-test-failure-serverdeck_locald-tests.json'
    $relativeProof=Read-NativeIsarArtifactJson $relativeProofPath
    $relativeSafe=[IO.File]::ReadAllText($relativeProofPath)
    if($relativeProof.status -cne 'failed-test-details' -or -not $relativeProof.controlledFixture -or
        -not $relativeProof.reporterComplete -or $relativeProof.failures.Count -ne 1 -or
        $relativeProof.failures[0].sourceFrames.Count -ne 1 -or
        $relativeProof.failures[0].sourceFrames[0].file -cne 'packages/serverdeck_locald/test/support/workspace_child.dart' -or
        $relativeProof.failures[0].sourceFrames[0].line -ne 385 -or
        $relativeSafe.Contains($privateMarker) -or $relativeSafe.Contains('999999') -or $relativeSafe.Contains('stackTrace')) {
        throw 'Controlled relative source projection mismatch.'
    }
}
'QUALIFICATION_RELATIVE_DART_FRAMES_BOTH_SEPARATORS_AND_PRIVATE_UNKNOWN_INVALID_EXCLUSION_PASSED'

# A real Dart timeout reporter supplies the error shape. Controlled variants
# alias only test metadata to a checked source; they are never qualification.
$timeoutProbe=Join-Path $fixture 'controlled-timeout.dart'
$timeoutReport=Join-Path $fixture 'controlled-timeout.machine.jsonl'
[IO.File]::WriteAllText($timeoutProbe,@'
import 'dart:async';
import 'package:test/test.dart';
void main() {
  test('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER timeout', () async {
    await Completer<void>().future.timeout(const Duration(milliseconds: 1));
  });
}
'@,[Text.UTF8Encoding]::new($false))
Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_locald')
try {
    & $FoundationDart test $timeoutProbe --file-reporter "json:$timeoutReport" *> (Join-Path $fixture 'controlled-timeout.private.txt')
    if($LASTEXITCODE -eq 0){throw 'Controlled timeout unexpectedly passed.'}
} finally {Pop-Location}
$rawTimeout=[IO.File]::ReadAllLines($timeoutReport)
$source='packages/serverdeck_locald/test/storage/operational_open_native_test.dart'
$sourceUri=([Uri](Join-Path $NativeIsarRepository $source)).AbsoluteUri
$casePrefix='compiled operational snapshot actual owned operational native open '
foreach($variant in @('known','known-pointer','known-commit','known-gateway','unknown-name','name-type','unknown-source','invalid-line','changed-source','wrong-error','invalid-timeout')) {
    $caseFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($caseFixture)
    $events=foreach($line in $rawTimeout) {
        $event=$line|ConvertFrom-Json -AsHashtable
        if($event.type -ceq 'testStart' -and $event.test.name -ceq ($privateMarker+' timeout')) {
            $event.test.name=$casePrefix+'grant-capacity'
            $event.test.url=$sourceUri
            $event.test.line=109
            switch($variant) {
                'known-pointer' {$event.test.name=$casePrefix+'grant-pointer-throw-replace-afterPending'}
                'known-commit' {
                    $event.test.name='actual native commit-time capacity preserves process and recovery sync'
                    $event.test.url=([Uri](Join-Path $NativeIsarRepository 'packages/serverdeck_locald/test/storage/native_commit_capacity_test.dart')).AbsoluteUri
                    $event.test.line=29
                }
                'known-gateway' {
                    $event.test.name='actual native MCP gateway stdout-revoke'
                    $event.test.url=([Uri](Join-Path $NativeIsarRepository 'packages/serverdeck_locald/test/mcp/gateway_native_test.dart')).AbsoluteUri
                    $event.test.line=55
                }
                'unknown-name' {$event.test.name+=$privateMarker}
                'name-type' {$event.test.name=@{private=$privateMarker}}
                'unknown-source' {$event.test.url='file:///C:/'+$privateMarker+'/private.dart'}
                'invalid-line' {$event.test.line=999999}
            }
        }
        if($event.type -ceq 'error') {
            if($event.error -cnotmatch '^TimeoutException after 0:00:00\.001000:') {
                throw 'Expected actual Dart timeout reporter shape.'
            }
            if($variant -ceq 'wrong-error') {$event.error='Bad state: '+$privateMarker}
            if($variant -ceq 'invalid-timeout') {$event.error='TimeoutException after '+$privateMarker+': private'}
        }
        $event|ConvertTo-Json -Depth 30 -Compress
    }
    [IO.File]::WriteAllLines((Join-Path $caseFixture 'serverdeck_locald-tests.machine.jsonl'),[string[]]$events,[Text.UTF8Encoding]::new($false))
    $selected=$snapshot
    if($variant -ceq 'changed-source') {
        $selected=@{sha256=$snapshot.sha256;files=@($snapshot.files|ForEach-Object{
            if($_.file -ceq $source){@{file=$source;sha256=('0'*64)}}else{$_}
        })}
    }
    Write-NativeQualificationTestFailure -Directory $caseFixture -Phase 'serverdeck_locald-tests' -SourceSnapshot $selected -ControlledFixture
    $casePath=Join-Path $caseFixture 'safe-test-failure-serverdeck_locald-tests.json'
    $caseProof=Read-NativeIsarArtifactJson $casePath
    $safe=[IO.File]::ReadAllText($casePath)
    if($caseProof.status -cne 'failed-test-details' -or -not $caseProof.controlledFixture -or
        -not $caseProof.reporterComplete -or $caseProof.failures.Count -ne 1 -or
        $safe.Contains($privateMarker) -or $safe.Contains('C:/') -or $safe.Contains('stackTrace') -or
        $safe.Contains('Future not completed')) {throw 'Timeout projection privacy/report mismatch.'}
    $failure=$caseProof.failures[0]
    $expectCase=$variant -in @('known','known-pointer','known-commit','known-gateway','wrong-error','invalid-timeout')
    $expectTimeout=$variant -in @('known','known-pointer','known-commit','known-gateway','unknown-name','name-type')
    $expectedCase=switch($variant){
        'known-pointer' {'grant-pointer-throw-replace-afterPending'}
        'known-commit' {'commit-capacity-sync'}
        'known-gateway' {'gateway-stdout-revoke'}
        default {'grant-capacity'}
    }
    if(($expectCase -and $failure.fixtureCase -cne $expectedCase) -or
        (-not $expectCase -and $null -ne $failure.fixtureCase) -or
        ($expectTimeout -and $failure.failureKind -cne 'timeout') -or
        (-not $expectTimeout -and $null -ne $failure.failureKind)) {throw ('Controlled timeout projection mismatch: '+$variant)}
}
'QUALIFICATION_REAL_TIMEOUT_FIXED_CASE_SOURCE_HASH_AND_PRIVACY_NEGATIVES_PASSED'
$fixture
$invalidFixture
exit 0
