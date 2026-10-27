[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/qualification-test-diagnostics.ps1"

# Controlled owned-fixture cases use decoded real package:test body/both
# reporters. Source mutations remain in memory; native fixtures are not run.

function Invoke-ControlledOwnedDiagnosticProjection {
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][string[]]$Events,
        [Parameter(Mandatory)][string]$Phase,[Parameter(Mandatory)][string]$PrivateMarker,
        [Parameter(Mandatory)][string]$Label)
    $directory=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    [IO.File]::WriteAllLines((Join-Path $directory ($Phase+'.machine.jsonl')),$Events,[Text.UTF8Encoding]::new($false))
    Write-NativeQualificationTestFailure -Directory $directory -Phase $Phase -SourceSnapshot $Snapshot -ControlledFixture
    $path=Join-Path $directory ('safe-test-failure-'+$Phase+'.json')
    $proof=Read-NativeIsarArtifactJson $path;$safe=[IO.File]::ReadAllText($path)
    if($proof.schemaVersion -ne 1 -or $proof.status -cne 'failed-test-details' -or -not $proof.controlledFixture -or
        -not $proof.reporterComplete -or $proof.failures.Count -ne 1 -or $proof.fullAcceptance -or $proof.distributionReady -or $proof.activated -or
        $safe.Contains($PrivateMarker) -or $safe.Contains('TRUSTED_CLIENT_FIXTURE_FAILURE:') -or
        $safe.Contains('OWNED_FIXTURE_CLEANUP_FAILURE:') -or $safe.Contains('actual format3 ') -or
        $safe.Contains('file:///') -or $safe.Contains('C:/') -or $safe.Contains('stackTrace') -or
        $safe.Contains('Expected:') -or $safe.Contains('999999')) {
        throw ('Owned controlled projection privacy/schema mismatch: '+$Label)
    }
    if($proof.failures[0].sourceFrames.Count -gt 3){throw ('Owned primary frame bound exceeded: '+$Label)}
    return $proof.failures[0]
}

function Get-ControlledOwnedDiagnosticSnapshot {
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][string]$Changed,[switch]$Missing)
    if(@($Snapshot.files|Where-Object {$_.file -ceq $Changed}).Count -ne 1){throw ('Expected one source inventory entry: '+$Changed)}
    return @{sha256=$Snapshot.sha256;files=@($Snapshot.files|ForEach-Object {
        if($_.file -ceq $Changed){if(-not $Missing){@{file=$Changed;sha256=('0'*64)}}}else{$_}
    })}
}

function Test-TrustedClientFailureDiagnosticProjection {
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][object[]]$RawOwned,[Parameter(Mandatory)][string]$PrivateMarker)
    $parentSource='packages/serverdeck_windows/test/trusted_client_native_test.dart'
    $actorSource='packages/serverdeck_windows/test/support/trusted_client_actor.dart'
    $fixtureSource='packages/serverdeck_windows/test/support/trusted_client_fixture.dart'
    $completionSource='packages/serverdeck_windows/test/support/trusted_client_completion.dart'
    $parentUri=([Uri](Join-Path $NativeIsarRepository $parentSource)).AbsoluteUri
    $actorUri=([Uri](Join-Path $NativeIsarRepository $actorSource)).AbsoluteUri
    $fixtureUri=([Uri](Join-Path $NativeIsarRepository $fixtureSource)).AbsoluteUri
    $parentLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $parentSource))
    $actorLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $actorSource))
    $fixtureLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $fixtureSource))
    $completionLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $completionSource))
    $modes=@('owner','cleanup2','cleanup3','mcp','grant','grant-bad-proof','grant-repeat','codes','quota','receipts',
        'connection','bad-connection','bad-connect','bad-connect-status','bad-connect-cancel','bad-disconnect','readiness2',
        'bad-receipt','bad-retry','unknown-code','bad-field','wrong-id','wrong-generation','oversize','invalid-json','timeout',
        'eof','duplicate','single-use','wrong-token','bad-proof','hello-role','hello-generation','hello-build','hello-version',
        'hello-shape','bootstrap-timeout')
    $ordinary=@($modes|Where-Object {$_ -cnotin @('cleanup2','cleanup3')})
    $loop=[regex]::Matches(($parentLines -join "`n"),'(?s)for \(final mode in \[(?<cases>.*?)\]\) \{')
    $actualModes=if($loop.Count -eq 1){@([regex]::Matches($loop[0].Groups['cases'].Value,"(?m)^\s*'(?<case>[a-z0-9-]+)',\s*$")|ForEach-Object {$_.Groups['case'].Value})}else{@()}
    $declarations=@(for($i=0;$i+1 -lt $parentLines.Length;$i++) {
        if($parentLines[$i].Trim() -ceq 'test(' -and $parentLines[$i+1].Trim() -ceq "'actual format3 bootstrap and RPC client `$mode',"){$i+1}
    })
    $producers=@(for($i=0;$i+2 -lt $parentLines.Length;$i++) {
        if($parentLines[$i].Trim() -ceq 'expect(' -and $parentLines[$i+1].Trim() -ceq 'childExit,' -and $parentLines[$i+2].Trim() -ceq '0,'){$i+1}
    })
    $bodyLines=@(for($i=0;$i -lt $fixtureLines.Length;$i++){if($fixtureLines[$i].Trim() -ceq 'await body();'){$i+1}})
    if(($actualModes -join '|') -cne ($modes -join '|') -or $ordinary.Count -ne 35 -or $declarations.Count -ne 1 -or $producers.Count -ne 1 -or $bodyLines.Count -ne 1) {
        throw 'Expected exact 37 trusted-client modes, 35 ordinary modes and actual declaration/zero-exit/helper body lines.'
    }
    $declaration=$declarations[0];$producer=$producers[0];$bodyLine=$bodyLines[0]
    $starts=@{};foreach($kind in @('body','both')) {
        $matches=@($RawOwned|Where-Object {$_.type -ceq 'testStart' -and $_.test.name -ceq ($PrivateMarker+' owned '+$kind)})
        if($matches.Count -ne 1){throw ('Expected real owned reporter case: '+$kind)};$starts[$kind]=$matches[0].test.id
    }
    $phases=@('prepare','bootstrap','rpc-read','rpc-write','completion','cleanup-child','cleanup-worker')
    $codes=@('SERVICE_UNAVAILABLE','UNSAFE_ENDPOINT','IDENTITY_UNAVAILABLE','TIMEOUT','RESOURCE_LIMIT','UNAUTHORIZED','INCOMPATIBLE','PREREQUISITE_UNAVAILABLE','-')
    $baselineMarker='TRUSTED_CLIENT_FIXTURE_FAILURE:prepare:SERVICE_UNAVAILABLE'
    $separator="`nOWNED_FIXTURE_CLEANUP_FAILURE:`n"
    $cases=[Collections.Generic.List[hashtable]]::new()
    # Positive cases are deliberately first: an old projector must fail here,
    # before the source-shape getter added by this change is ever called.
    foreach($mode in $ordinary){$cases.Add(@{variant='ordinary-'+$mode;mode=$mode;positive=$true;both=$false})}
    foreach($fixturePhase in $phases){foreach($code in $codes){$cases.Add(@{variant='phase-code-'+$fixturePhase+'-'+$code;fixturePhase=$fixturePhase;code=$code;positive=$true;both=$true})}}
    foreach($mode in $modes){$cases.Add(@{variant='legacy-'+$mode;mode=$mode;legacy=$true})}
    foreach($mode in @('cleanup2','cleanup3')){$cases.Add(@{variant='excluded-'+$mode;mode=$mode})}
    $negatives=@('secondary-duplicate','primary-frames-bound','both-primary','exit-signed','exit-unsigned','exit-minimum','exit-maximum',
        'duplicate-primary','nonfirst-marker','raw-stderr-marker','marker-only-secondary','secondary-producer-only','marker-in-stack-only',
        'unknown-phase','unknown-code','lowercase-code','extra-field','partial-marker','marker-suffix','marker-crlf','marker-nonascii','marker-oversize',
        'exit-zero','exit-too-low','exit-too-high','exit-plus','exit-fractional','exit-nonnumeric','exit-prefix','exit-no-line-end','wrong-expected',
        'without-producer','unrelated-producer','helper-producer','invalid-producer','unknown-producer','error-type','event-id-type',
        'unknown-name','suffixed-name','name-type','wrong-url','unknown-url','missing-url','wrong-suite','missing-suite','wrong-suite-path',
        'wrong-phase','invalid-declaration','unrelated-declaration','null-declaration','declaration-type','fractional-declaration',
        'changed-parent','changed-actor','changed-fixture','changed-completion','missing-actor','missing-fixture','missing-completion')
    foreach($variant in $negatives){$cases.Add(@{variant=$variant})}
    foreach($case in $cases) {
        $variant=$case.variant;$mode=if($case.ContainsKey('mode')){$case.mode}else{'owner'}
        $fixturePhase=if($case.ContainsKey('fixturePhase')){$case.fixturePhase}else{'prepare'}
        $code=if($case.ContainsKey('code')){$case.code}else{'SERVICE_UNAVAILABLE'}
        $both=($case.ContainsKey('both') -and $case.both) -or $variant -in @('secondary-duplicate','primary-frames-bound','both-primary','marker-only-secondary','secondary-producer-only')
        $target=$starts[$(if($both){'both'}else{'body'})]
        $marker='TRUSTED_CLIENT_FIXTURE_FAILURE:'+$fixturePhase+':'+$code
        $events=foreach($raw in $RawOwned) {
            if($raw.type -ceq 'testStart' -and $raw.test.id -ne $target){continue}
            if($raw.type -cin @('print','error','testDone') -and $raw.testID -ne $target){continue}
            $event=$raw|ConvertTo-Json -Depth 30 -Compress|ConvertFrom-Json -AsHashtable
            if($event.type -ceq 'suite') {
                $event.suite.path=$parentUri
                if($variant -ceq 'missing-suite'){continue}
                if($variant -ceq 'wrong-suite-path'){$event.suite.path=$actorUri}
            }
            if($event.type -ceq 'testStart') {
                $event.test.name='actual format3 bootstrap and RPC client '+$mode;$event.test.url=$parentUri;$event.test.line=$declaration
                if($case.ContainsKey('legacy')){$event.test.line=1}
                switch($variant) {
                    'unknown-name' {$event.test.name='actual format3 bootstrap and RPC client '+$PrivateMarker}
                    'suffixed-name' {$event.test.name+=$PrivateMarker}
                    'name-type' {$event.test.name=@{private=$PrivateMarker}}
                    'wrong-url' {$event.test.url=$actorUri}
                    'unknown-url' {$event.test.url='file:///C:/'+$PrivateMarker+'/private.dart'}
                    'missing-url' {$event.test.url=$null}
                    'wrong-suite' {$event.test.suiteID=999999}
                    'invalid-declaration' {$event.test.line=999999}
                    'unrelated-declaration' {$event.test.line=1}
                    'null-declaration' {$event.test.line=$null}
                    'declaration-type' {$event.test.line=[string]$declaration}
                    'fractional-declaration' {$event.test.line=[double]$declaration}
                }
            }
            if($event.type -ceq 'error') {
                if($event.error -cnotmatch '\AExpected: <0>\r?\n[ \t]*Actual: <1>\r?\n' -or
                    -not $event.error.Contains($baselineMarker+"`n"+$PrivateMarker+"`n#0 actor ("+$actorUri+':40:1)') -or
                    ($both -and -not $event.error.Contains($separator))) {throw 'Expected real owned numeric assertion and exact first reason marker/actor/aggregate.'}
                $event.error=$event.error.Replace($baselineMarker,$marker)
                $event.stackTrace="#0 parent (${parentUri}:${producer}:1)"
                if($case.ContainsKey('legacy')){$event.error=$event.error.Replace($marker+"`n",'');$event.stackTrace=$PrivateMarker}
                switch($variant) {
                    'secondary-duplicate' {$event.error+="`n"+$marker+"`n"+$marker}
                    'duplicate-primary' {$event.error=$event.error.Replace($marker+"`n",$marker+"`n"+$marker+"`n")}
                    'nonfirst-marker' {$event.error=$event.error.Replace($marker+"`n",$PrivateMarker+"`n"+$marker+"`n")}
                    'raw-stderr-marker' {$event.error=$event.error.Replace($marker+"`n",'')+"`n"+$marker}
                    'marker-only-secondary' {$event.error=$event.error.Replace($marker+"`n",'')+"`n"+$marker}
                    'marker-in-stack-only' {$event.error=$event.error.Replace($marker+"`n",'');$event.stackTrace+="`n"+$marker}
                    'unknown-phase' {$event.error=$event.error.Replace($marker,'TRUSTED_CLIENT_FIXTURE_FAILURE:'+ $PrivateMarker+':SERVICE_UNAVAILABLE')}
                    'unknown-code' {$event.error=$event.error.Replace($marker,'TRUSTED_CLIENT_FIXTURE_FAILURE:prepare:'+ $PrivateMarker)}
                    'lowercase-code' {$event.error=$event.error.Replace($marker,'TRUSTED_CLIENT_FIXTURE_FAILURE:prepare:service_unavailable')}
                    'extra-field' {$event.error=$event.error.Replace($marker,$marker+':extra')}
                    'partial-marker' {$event.error=$event.error.Replace($marker,'TRUSTED_CLIENT_FIXTURE_FAILURE:prepare')}
                    'marker-suffix' {$event.error=$event.error.Replace($marker,$marker+' ')}
                    'marker-crlf' {$event.error=$event.error.Replace($marker+"`n",$marker+"`r`n")}
                    'marker-nonascii' {$event.error=$event.error.Replace($marker,'TRUSTED_CLIENT_FIXTURE_FAILURE:подготовка:SERVICE_UNAVAILABLE')}
                    'marker-oversize' {$event.error=$event.error.Replace($marker,('TRUSTED_CLIENT_FIXTURE_FAILURE:'+('prepare'*30)+':SERVICE_UNAVAILABLE'))}
                    'exit-signed' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-1073741819>')}
                    'exit-unsigned' {$event.error=$event.error.Replace('Actual: <1>','Actual: <3221225477>')}
                    'exit-minimum' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-2147483648>')}
                    'exit-maximum' {$event.error=$event.error.Replace('Actual: <1>','Actual: <4294967295>')}
                    'exit-zero' {$event.error=$event.error.Replace('Actual: <1>','Actual: <0>')}
                    'exit-too-low' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-2147483649>')}
                    'exit-too-high' {$event.error=$event.error.Replace('Actual: <1>','Actual: <4294967296>')}
                    'exit-plus' {$event.error=$event.error.Replace('Actual: <1>','Actual: <+1>')}
                    'exit-fractional' {$event.error=$event.error.Replace('Actual: <1>','Actual: <1.0>')}
                    'exit-nonnumeric' {$event.error=$event.error.Replace('Actual: <1>',('Actual: <'+$PrivateMarker+'>'))}
                    'exit-prefix' {$event.error=$PrivateMarker+"`n"+$event.error}
                    'exit-no-line-end' {$event.error="Expected: <0>`n  Actual: <1>"}
                    'wrong-expected' {$event.error=$event.error.Replace('Expected: <0>','Expected: <1>')}
                    'without-producer' {$event.stackTrace=$PrivateMarker}
                    'unrelated-producer' {$event.stackTrace="#0 parent (${parentUri}:${declaration}:1)"}
                    'helper-producer' {$event.stackTrace="#0 helper (${fixtureUri}:${bodyLine}:1)"}
                    'invalid-producer' {$event.stackTrace="#0 parent (${parentUri}:999999:1)"}
                    'unknown-producer' {$event.stackTrace="#0 private (file:///C:/${PrivateMarker}/private.dart:${producer}:1)"}
                    'secondary-producer-only' {$event.stackTrace=$PrivateMarker;$event.error+="`n#9 parent (${parentUri}:${producer}:1)"}
                    'event-id-type' {$event.testID=[string]$target}
                    'error-type' {$event.error=@{private=$PrivateMarker}}
                    'primary-frames-bound' {
                        $event.error=$event.error.Replace($separator,"`n#3 actor (${actorUri}:40:1)`n#4 actor (${actorUri}:42:1)`n#5 actor (${actorUri}:43:1)`n#6 invalid (${actorUri}:999999:1)"+$separator)
                        $event.stackTrace+="`n#1 helper (${fixtureUri}:${bodyLine}:1)"
                    }
                }
            }
            $event|ConvertTo-Json -Depth 30 -Compress
        }
        $selected=$Snapshot
        if($variant -cmatch '\A(changed|missing)-(parent|actor|fixture|completion)\z') {
            $changed=switch($Matches[2]){'parent'{$parentSource};'actor'{$actorSource};'fixture'{$fixtureSource};'completion'{$completionSource}}
            $selected=Get-ControlledOwnedDiagnosticSnapshot -Snapshot $Snapshot -Changed $changed -Missing:($Matches[1] -ceq 'missing')
        }
        $phase=if($variant -ceq 'wrong-phase'){'serverdeck_locald-tests'}else{'serverdeck_windows-tests'}
        $failure=Invoke-ControlledOwnedDiagnosticProjection -Snapshot $selected -Events ([string[]]$events) -Phase $phase -PrivateMarker $PrivateMarker -Label ('T114 '+$variant)
        $expectNew=($case.ContainsKey('positive') -and $case.positive) -or $variant -in @('secondary-duplicate','primary-frames-bound','both-primary','exit-signed','exit-unsigned','exit-minimum','exit-maximum')
        $expectCase=$variant -cnotin @('unknown-name','suffixed-name','name-type','wrong-url','invalid-declaration','null-declaration','declaration-type','changed-parent')
        $expectExit=$expectCase -and $variant -cnotin @('exit-zero','exit-too-low','exit-too-high','exit-plus','exit-fractional','exit-nonnumeric','exit-prefix','exit-no-line-end','wrong-expected','error-type')
        $expectedExit=switch($variant){'exit-signed'{-1073741819L};'exit-unsigned'{3221225477L};'exit-minimum'{-2147483648L};'exit-maximum'{4294967295L};default{1L}}
        $expectedCode=if($code -ceq '-'){$null}else{$code}
        if(($expectNew -and ($failure.fixturePhase -cne $fixturePhase -or $failure.safeCode -cne $expectedCode)) -or
            (-not $expectNew -and ($null -ne $failure.fixturePhase -or $null -ne $failure.safeCode)) -or
            ($expectCase -and $failure.fixtureCase -cne ('trusted-client-'+$mode)) -or (-not $expectCase -and $null -ne $failure.fixtureCase) -or
            ($expectExit -and ($failure.fixtureExitCode -ne $expectedExit -or $failure.failureKind -cne 'fixture-exit')) -or
            (-not $expectExit -and ($null -ne $failure.fixtureExitCode -or $null -ne $failure.failureKind)) -or $failure.nativeErrors.Count -ne 0) {
            throw ('T114 marker/new fields versus independent legacy fields mismatch: '+$variant)
        }
        if($both -and $expectNew) {foreach($frame in $failure.sourceFrames){if($frame.file -ceq $actorSource -and $frame.line -eq 41){throw ('T114 secondary cleanup frame escaped: '+$variant)}}}
        if($variant -ceq 'changed-actor' -and @($failure.sourceFrames|Where-Object {$_.file -ceq $actorSource}).Count -ne 0){throw 'T114 stale actor frame escaped.'}
        if($variant -ceq 'primary-frames-bound' -and $failure.sourceFrames.Count -ne 3){throw 'T114 common primary frame cap was not filled.'}
    }
    # Mutation tests use memory only, after all reporter positives/negatives.
    $shape=Get-NativeTrustedClientDiagnosticShape -ParentLines $parentLines -ActorLines $actorLines -FixtureLines $fixtureLines -CompletionLines $completionLines
    if(-not $shape -or $shape.declarationLine -ne $declaration -or $producer -notin $shape.producerLines){throw 'T114 current source shape/declaration/producer rejected.'}
    $changedZero=[string[]]$parentLines.Clone();$changedZero[$producer+1]='              1,'
    if(Get-NativeTrustedClientDiagnosticShape -ParentLines $changedZero -ActorLines $actorLines -FixtureLines $fixtureLines -CompletionLines $completionLines){throw 'T114 altered expected-zero assertion accepted.'}
    $multiline=@($parentLines)+@("const privateExample = '''",$PrivateMarker,"''';")
    if(Get-NativeTrustedClientDiagnosticShape -ParentLines $multiline -ActorLines $actorLines -FixtureLines $fixtureLines -CompletionLines $completionLines){throw 'T114 multiline Dart literal was normalized into a trusted source contract.'}
    $texts=@{ParentLines=($parentLines -join "`n");ActorLines=($actorLines -join "`n");FixtureLines=($fixtureLines -join "`n");CompletionLines=($completionLines -join "`n")}
    $mutations=@(
        @('ParentLines','const Duration(seconds: 35)','const Duration(seconds: 36)'),
        @('ParentLines','final record = readTrustedClientFailure(fixture.path);','final record = null;'),
        @('ParentLines','cleanup: fixture.close,','cleanup: () async {},'),
        @('ActorLines','failures.record(phase, error)',"failures.record('prepare', error)"),
        @('ActorLines','await finishTrustedClientProcess();','finishTrustedClientProcess();'),
        @('FixtureLines','OWNED_FIXTURE_CLEANUP_FAILURE:','PRIVATE_OTHER_CLEANUP:'),
        @('FixtureLines','if (_recorded) return;','if (false) return;'),
        @('FixtureLines','handle.readSync(129)','handle.readSync(130)'),
        @('FixtureLines','byte > 127','byte > 255'),
        @('CompletionLines','TRUSTED_CLIENT_EXIT_ACK','PRIVATE_OTHER_EXIT_ACK'),
        @('CompletionLines','const Duration(seconds: 5)','const Duration(seconds: 6)'),
        @('CompletionLines','await within(received.future);','within(received.future);'))
    foreach($mutation in $mutations) {
        $text=$texts[$mutation[0]];$changed=$text.Replace($mutation[1],$mutation[2]);if($changed -ceq $text){throw ('T114 mutation did not touch source: '+$mutation[1])}
        $arguments=@{ParentLines=$parentLines;ActorLines=$actorLines;FixtureLines=$fixtureLines;CompletionLines=$completionLines};$arguments[$mutation[0]]=$changed -split '\r?\n'
        if(Get-NativeTrustedClientDiagnosticShape @arguments){throw ('T114 altered required source contract accepted: '+$mutation[1])}
    }
    'QUALIFICATION_TRUSTED_CLIENT_35_ORDINARY_7_PHASES_8_CODES_NULL_PRIMARY_AGGREGATE_LEGACY37_SOURCE_HASH_BOUNDS_PRIVACY_PASSED'
}

function Test-TrustedAuthDiagnosticProjection {
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][object[]]$RawOwned,[Parameter(Mandatory)][string]$PrivateMarker)
    $parentSource='packages/serverdeck_locald/test/mcp/trusted_auth_native_test.dart'
    $actorSource='packages/serverdeck_locald/test/support/trusted_auth_actor.dart'
    $fixtureSource='packages/serverdeck_windows/test/support/trusted_client_fixture.dart'
    $startupSource='packages/serverdeck_locald/test/support/trusted_auth_fixture.dart'
    $inputActor='packages/serverdeck_windows/test/support/trusted_client_actor.dart'
    $parentUri=([Uri](Join-Path $NativeIsarRepository $parentSource)).AbsoluteUri
    $actorUri=([Uri](Join-Path $NativeIsarRepository $actorSource)).AbsoluteUri
    $fixtureUri=([Uri](Join-Path $NativeIsarRepository $fixtureSource)).AbsoluteUri
    $inputActorUri=([Uri](Join-Path $NativeIsarRepository $inputActor)).AbsoluteUri
    $parentLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $parentSource))
    $actorLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $actorSource))
    $fixtureLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $fixtureSource))
    $startupLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $startupSource))
    $scenarios=@('roles','native-gate','stale-close','proofs','quota','expiry','close','snapshot','deadline','client','framing','tamper',
        'owner-context','owner-context-detach','owner-context-expiry','owner-context-budget','owner-context-native','owner-context-stop',
        'owner-context-physical','owner-connection','owner-connection-budget','owner-connection-detach','owner-connection-native',
        'owner-connection-stop','owner-connection-physical')
    $loop=[regex]::Matches(($parentLines -join "`n"),'(?s)for \(final scenario in \[(?<cases>.*?)\]\) \{')
    $actualScenarios=if($loop.Count -eq 1){@([regex]::Matches($loop[0].Groups['cases'].Value,"(?m)^\s*'(?<case>[a-z0-9-]+)',\s*$")|ForEach-Object {$_.Groups['case'].Value})}else{@()}
    $declarations=@(for($i=0;$i+1 -lt $parentLines.Length;$i++) {
        if($parentLines[$i].Trim() -ceq 'test(' -and $parentLines[$i+1].Trim() -ceq "'actual format3 API1.1 bootstrap and session `$scenario',"){$i+1}
    })
    $producers=@(for($i=0;$i+2 -lt $parentLines.Length;$i++) {
        if($parentLines[$i].Trim() -ceq 'expect(' -and $parentLines[$i+1].Trim() -ceq 'await child.exitCode.timeout(const Duration(seconds: 70)),' -and $parentLines[$i+2].Trim() -ceq '0,'){$i+1}
    })
    $passLines=@(for($i=0;$i -lt $parentLines.Length;$i++){if($parentLines[$i].Trim() -ceq "expect((await output).trim(), 'PASS:`$scenario');"){$i+1}})
    $bodyLines=@(for($i=0;$i -lt $fixtureLines.Length;$i++){if($fixtureLines[$i].Trim() -ceq 'await body();'){$i+1}})
    if(($actualScenarios -join '|') -cne ($scenarios -join '|') -or $scenarios.Count -ne 25 -or $declarations.Count -ne 1 -or $producers.Count -ne 1 -or $passLines.Count -ne 1 -or $bodyLines.Count -ne 1) {
        throw 'Expected exact 25 trusted-auth scenarios and actual declaration/zero-exit/PASS/helper lines.'
    }
    $declaration=$declarations[0];$producer=$producers[0];$passLine=$passLines[0];$bodyLine=$bodyLines[0]
    $starts=@{};foreach($kind in @('body','both')) {
        $matches=@($RawOwned|Where-Object {$_.type -ceq 'testStart' -and $_.test.name -ceq ($PrivateMarker+' owned '+$kind)})
        if($matches.Count -ne 1){throw ('Expected real owned reporter case: '+$kind)};$starts[$kind]=$matches[0].test.id
    }
    $baselineMarker='TRUSTED_CLIENT_FIXTURE_FAILURE:prepare:SERVICE_UNAVAILABLE';$separator="`nOWNED_FIXTURE_CLEANUP_FAILURE:`n"
    $variants=@($scenarios|ForEach-Object {'scenario-'+$_})+@('both-primary','primary-frames-bound','secondary-duplicate','unknown-reason-actor',
        'exit-signed','exit-unsigned','exit-minimum','exit-maximum','cleanup-only','pass-assertion','legacy-bad-state','raw-client-marker',
        'secondary-exit-only','secondary-producer-only','raw-stderr-exit','private-stack-exit','exit-zero','exit-too-low','exit-too-high',
        'exit-plus','exit-fractional','exit-nonnumeric','exit-prefix','exit-no-line-end','wrong-expected','error-type',
        'unknown-name','suffixed-name','child-mode','orphan','name-type','wrong-url','unknown-url','missing-url','wrong-suite','missing-suite',
        'wrong-suite-path','wrong-phase','invalid-declaration','unrelated-declaration','null-declaration','declaration-type','fractional-declaration',
        'without-producer','helper-producer','unrelated-source-line','invalid-source-line','unknown-source-line','event-id-type',
        'changed-parent','changed-actor','changed-fixture','changed-startup','missing-actor','missing-fixture','missing-startup')
    foreach($variant in $variants) {
        $scenario=if($variant.StartsWith('scenario-')){$variant.Substring(9)}else{'quota'}
        $both=$variant -in @('both-primary','primary-frames-bound','secondary-duplicate','secondary-exit-only','secondary-producer-only')
        $target=$starts[$(if($both){'both'}else{'body'})]
        $events=foreach($raw in $RawOwned) {
            if($raw.type -ceq 'testStart' -and $raw.test.id -ne $target){continue}
            if($raw.type -cin @('print','error','testDone') -and $raw.testID -ne $target){continue}
            $event=$raw|ConvertTo-Json -Depth 30 -Compress|ConvertFrom-Json -AsHashtable
            if($event.type -ceq 'suite') {
                $event.suite.path=$parentUri
                if($variant -ceq 'missing-suite'){continue}
                if($variant -ceq 'wrong-suite-path'){$event.suite.path=$actorUri}
            }
            if($event.type -ceq 'testStart') {
                $event.test.name='actual format3 API1.1 bootstrap and session '+$scenario;$event.test.url=$parentUri;$event.test.line=$declaration
                switch($variant) {
                    'unknown-name' {$event.test.name='actual format3 API1.1 bootstrap and session '+$PrivateMarker}
                    'suffixed-name' {$event.test.name+=$PrivateMarker}
                    'child-mode' {$event.test.name='actual format3 API1.1 bootstrap and session client-worker'}
                    'orphan' {$event.test.name='hard-killed fixture owner cannot leave its native client child'}
                    'name-type' {$event.test.name=@{private=$PrivateMarker}}
                    'wrong-url' {$event.test.url=$actorUri}
                    'unknown-url' {$event.test.url='file:///C:/'+$PrivateMarker+'/private.dart'}
                    'missing-url' {$event.test.url=$null}
                    'wrong-suite' {$event.test.suiteID=999999}
                    'invalid-declaration' {$event.test.line=999999}
                    'unrelated-declaration' {$event.test.line=1}
                    'null-declaration' {$event.test.line=$null}
                    'declaration-type' {$event.test.line=[string]$declaration}
                    'fractional-declaration' {$event.test.line=[double]$declaration}
                }
            }
            if($event.type -ceq 'error') {
                if($event.error -cnotmatch '\AExpected: <0>\r?\n[ \t]*Actual: <1>\r?\n' -or -not $event.error.Contains($baselineMarker+"`n") -or
                    -not $event.error.Contains($inputActorUri) -or ($both -and -not $event.error.Contains($separator))) {
                    throw 'Expected real owned numeric assertion and private primary actor/aggregate.'
                }
                $event.error=$event.error.Replace($baselineMarker+"`n",'').Replace($inputActorUri,$actorUri)
                $event.stackTrace="#0 parent (${parentUri}:${producer}:1)"
                switch($variant) {
                    'secondary-duplicate' {$event.error+="`nExpected: <0>`n  Actual: <4294967295>`n"+$baselineMarker}
                    'unknown-reason-actor' {$event.error=$event.error.Replace($actorUri,('file:///C:/'+$PrivateMarker+'/private.dart'))}
                    'exit-signed' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-1073741819>')}
                    'exit-unsigned' {$event.error=$event.error.Replace('Actual: <1>','Actual: <3221225477>')}
                    'exit-minimum' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-2147483648>')}
                    'exit-maximum' {$event.error=$event.error.Replace('Actual: <1>','Actual: <4294967295>')}
                    'exit-zero' {$event.error=$event.error.Replace('Actual: <1>','Actual: <0>')}
                    'exit-too-low' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-2147483649>')}
                    'exit-too-high' {$event.error=$event.error.Replace('Actual: <1>','Actual: <4294967296>')}
                    'exit-plus' {$event.error=$event.error.Replace('Actual: <1>','Actual: <+1>')}
                    'exit-fractional' {$event.error=$event.error.Replace('Actual: <1>','Actual: <1.0>')}
                    'exit-nonnumeric' {$event.error=$event.error.Replace('Actual: <1>',('Actual: <'+$PrivateMarker+'>'))}
                    'exit-prefix' {$event.error=$PrivateMarker+"`n"+$event.error}
                    'exit-no-line-end' {$event.error="Expected: <0>`n  Actual: <1>"}
                    'wrong-expected' {$event.error=$event.error.Replace('Expected: <0>','Expected: <1>')}
                    'cleanup-only' {$event.error='Bad state: '+$PrivateMarker;$event.stackTrace="#0 cleanup (${parentUri}:${passLine}:1)"}
                    'pass-assertion' {$event.error="Expected: 'PASS:$scenario'`n  Actual: '$PrivateMarker'`n";$event.stackTrace="#0 parent (${parentUri}:${passLine}:1)"}
                    'legacy-bad-state' {$event.error='Bad state: SERVICE_UNAVAILABLE';$event.stackTrace="#0 parent (${parentUri}:${passLine}:1)"}
                    'raw-client-marker' {$event.error=$event.error.Replace($PrivateMarker,$baselineMarker+"`n"+$PrivateMarker)}
                    'secondary-exit-only' {$event.error=$PrivateMarker+$separator+$event.error}
                    'raw-stderr-exit' {$event.error=$PrivateMarker+"`n"+$event.error}
                    'private-stack-exit' {$event.stackTrace+="`n"+$event.error;$event.error=$PrivateMarker}
                    'without-producer' {$event.stackTrace=$PrivateMarker}
                    'helper-producer' {$event.stackTrace="#0 helper (${fixtureUri}:${bodyLine}:1)"}
                    'unrelated-source-line' {$event.stackTrace="#0 parent (${parentUri}:1:1)"}
                    'invalid-source-line' {$event.stackTrace="#0 parent (${parentUri}:999999:1)"}
                    'unknown-source-line' {$event.stackTrace="#0 private (file:///C:/${PrivateMarker}/private.dart:${producer}:1)"}
                    'secondary-producer-only' {$event.stackTrace=$PrivateMarker;$event.error+="`n#9 parent (${parentUri}:${producer}:1)"}
                    'event-id-type' {$event.testID=[string]$target}
                    'error-type' {$event.error=@{private=$PrivateMarker}}
                    'primary-frames-bound' {
                        $event.error=$event.error.Replace($separator,"`n#3 actor (${actorUri}:40:1)`n#4 actor (${actorUri}:42:1)`n#5 actor (${actorUri}:43:1)`n#6 invalid (${actorUri}:999999:1)"+$separator)
                        $event.stackTrace+="`n#1 helper (${fixtureUri}:${bodyLine}:1)"
                    }
                }
            }
            $event|ConvertTo-Json -Depth 30 -Compress
        }
        $selected=$Snapshot
        if($variant -cmatch '\A(changed|missing)-(parent|actor|fixture|startup)\z') {
            $changed=switch($Matches[2]){'parent'{$parentSource};'actor'{$actorSource};'fixture'{$fixtureSource};'startup'{$startupSource}}
            $selected=Get-ControlledOwnedDiagnosticSnapshot -Snapshot $Snapshot -Changed $changed -Missing:($Matches[1] -ceq 'missing')
        }
        $phase=if($variant -ceq 'wrong-phase'){'serverdeck_windows-tests'}else{'serverdeck_locald-tests'}
        $failure=Invoke-ControlledOwnedDiagnosticProjection -Snapshot $selected -Events ([string[]]$events) -Phase $phase -PrivateMarker $PrivateMarker -Label ('T115 '+$variant)
        $expectCase=$variant -cnotin @('unknown-name','suffixed-name','child-mode','orphan','name-type','wrong-url','unknown-url','missing-url',
            'wrong-suite','missing-suite','wrong-suite-path','wrong-phase','invalid-declaration','unrelated-declaration','null-declaration',
            'declaration-type','fractional-declaration','without-producer','helper-producer','unrelated-source-line','invalid-source-line',
            'unknown-source-line','secondary-producer-only','event-id-type','changed-parent','changed-actor','changed-fixture','changed-startup',
            'missing-actor','missing-fixture','missing-startup')
        $expectExit=$expectCase -and $variant -cnotin @('cleanup-only','pass-assertion','legacy-bad-state','secondary-exit-only','raw-stderr-exit',
            'private-stack-exit','exit-zero','exit-too-low','exit-too-high','exit-plus','exit-fractional','exit-nonnumeric','exit-prefix',
            'exit-no-line-end','wrong-expected','error-type')
        $expectedExit=switch($variant){'exit-signed'{-1073741819L};'exit-unsigned'{3221225477L};'exit-minimum'{-2147483648L};'exit-maximum'{4294967295L};default{1L}}
        if(($expectCase -and $failure.fixtureCase -cne ('trusted-auth-'+$scenario)) -or (-not $expectCase -and $null -ne $failure.fixtureCase) -or
            ($expectExit -and ($failure.fixtureExitCode -ne $expectedExit -or $failure.failureKind -cne 'fixture-exit')) -or
            (-not $expectExit -and ($null -ne $failure.fixtureExitCode -or $null -ne $failure.failureKind)) -or
            $null -ne $failure.fixturePhase -or $null -ne $failure.safeCode -or $failure.nativeErrors.Count -ne 0) {
            throw ('T115 exact case/primary exit/null phase-code mismatch: '+$variant)
        }
        if($both -and $expectCase) {foreach($frame in $failure.sourceFrames){if($frame.file -ceq $actorSource -and $frame.line -eq 41){throw ('T115 secondary cleanup frame escaped: '+$variant)}}}
        if($variant -ceq 'primary-frames-bound' -and $failure.sourceFrames.Count -ne 3){throw 'T115 common primary frame cap was not filled.'}
        # Refusal of new family metadata must not erase independently valid old
        # source frames. A stale actor loses its own frame, not the parent frame.
        if($variant -cin @('changed-actor','changed-fixture','changed-startup','missing-actor','missing-fixture','missing-startup') -and
            @($failure.sourceFrames|Where-Object {$_.file -ceq $parentSource -and $_.line -eq $producer}).Count -ne 1) {
            throw ('T115 stale dependency erased valid generic parent evidence: '+$variant)
        }
        if($variant -cin @('changed-actor','missing-actor') -and @($failure.sourceFrames|Where-Object {$_.file -ceq $actorSource}).Count -ne 0){throw 'T115 stale actor frame escaped.'}
    }
    $shape=Get-NativeTrustedAuthDiagnosticShape -ParentLines $parentLines -ActorLines $actorLines -FixtureLines $fixtureLines -StartupLines $startupLines
    if(-not $shape -or $shape.declarationLine -ne $declaration -or $producer -notin $shape.producerLines){throw 'T115 current source shape/declaration/producer rejected.'}
    $changedZero=[string[]]$parentLines.Clone();$changedZero[$producer+1]='              1,'
    if(Get-NativeTrustedAuthDiagnosticShape -ParentLines $changedZero -ActorLines $actorLines -FixtureLines $fixtureLines -StartupLines $startupLines){throw 'T115 altered expected-zero assertion accepted.'}
    $multiline=@($parentLines)+@("const privateExample = '''",$PrivateMarker,"''';")
    if(Get-NativeTrustedAuthDiagnosticShape -ParentLines $multiline -ActorLines $actorLines -FixtureLines $fixtureLines -StartupLines $startupLines){throw 'T115 multiline Dart literal was normalized into a trusted source contract.'}
    $texts=@{ParentLines=($parentLines -join "`n");ActorLines=($actorLines -join "`n");FixtureLines=($fixtureLines -join "`n");StartupLines=($startupLines -join "`n")}
    $mutations=@(
        @('ParentLines','const Duration(seconds: 70)','const Duration(seconds: 71)'),
        @('ParentLines','await runOwnedFixtureLifecycle(','runOwnedFixtureLifecycle('),
        @('ParentLines',"expect((await output).trim(), 'PASS:`$scenario');",'expect(await output, isNotEmpty);'),
        @('ActorLines','return runTrustedAuthStartup<Pair>(','return runUntrustedAuthStartup<Pair>('),
        @('ActorLines','registry.stop();',''),
        @('ActorLines','for (final pair in pairs.reversed) await pair.close();','for (final pair in pairs) await pair.close();'),
        @('FixtureLines','OWNED_FIXTURE_CLEANUP_FAILURE:','PRIVATE_OTHER_CLEANUP:'),
        @('FixtureLines','await cleanup();','cleanup();'),
        @('StartupLines','started = true;','started = false;'),
        @('StartupLines','if (!started) await cleanup();','await cleanup();'),
        @('StartupLines','result = await start();','await start();'))
    foreach($mutation in $mutations) {
        $text=$texts[$mutation[0]];$changed=$text.Replace($mutation[1],$mutation[2]);if($changed -ceq $text){throw ('T115 mutation did not touch source: '+$mutation[1])}
        $arguments=@{ParentLines=$parentLines;ActorLines=$actorLines;FixtureLines=$fixtureLines;StartupLines=$startupLines};$arguments[$mutation[0]]=$changed -split '\r?\n'
        if(Get-NativeTrustedAuthDiagnosticShape @arguments){throw ('T115 altered required source contract accepted: '+$mutation[1])}
    }
    'QUALIFICATION_TRUSTED_AUTH_EXACT25_PRIMARY_NUMERIC_EXIT_AGGREGATE_NULL_PHASE_CODE_SOURCE_HASH_BOUNDS_PRIVACY_PASSED'
}

function Test-CapacityPhaseDiagnosticProjection {
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][object[]]$RawCapacity,[Parameter(Mandatory)][string]$PrivateMarker)
    $parentSource='packages/serverdeck_locald/test/mcp/trust_probes_native_test.dart'
    $helperSource='packages/serverdeck_locald/test/support/capacity_fixture.dart'
    $writerSource='packages/serverdeck_locald/test/support/trust_write_scenarios.dart'
    $parentUri=([Uri](Join-Path $NativeIsarRepository $parentSource)).AbsoluteUri
    $parentLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $parentSource))
    $helperLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $helperSource))
    $writerLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $writerSource))
    $declaration=@(for($index=1;$index -lt $parentLines.Length;$index++) {
        if($parentLines[$index].Trim() -ceq "'actual native host trust probes `$mode'," -and $parentLines[$index-1].Trim() -ceq 'test('){$index}
    })
    $producer=@(for($index=0;$index -lt $parentLines.Length;$index++) {
        if($parentLines[$index].Trim() -ceq 'throw TimeoutException('){$index+1}
    })
    $modeLoop=[regex]::Matches(($parentLines -join "`n"),'(?s)for \(final mode in \[(?<cases>.*?)\]\) \{')
    $modes=@([regex]::Matches($modeLoop[0].Groups['cases'].Value,"(?m)^\s*'(?<case>[a-z0-9-]+)',\s*$")|ForEach-Object {$_.Groups['case'].Value})
    if($declaration.Count -ne 1 -or $producer.Count -ne 1 -or $modes.Count -ne 36){throw 'Expected checked capacity parent declaration/producer and 36 modes.'}
    $declaration=$declaration[0];$producer=$producer[0]
    $phases=@('capacity-start','capacity-reader-ready')+@(0..20|ForEach-Object {'capacity-prefill-'+($_*1000)})+@(
        'capacity-full','capacity-confirm-refused','capacity-reader-released','capacity-recovery-confirm','capacity-recovered',
        'capacity-replay-verified','capacity-revoke-verified','capacity-complete','unknown')
    $rawError=@($RawCapacity|Where-Object {$_.type -ceq 'error'})[0];$target=$rawError.testID
    if($rawError.error -cne 'TimeoutException after 0:00:55.000000: TRUST_CAPACITY_FIXTURE_TIMEOUT:capacity-start') {
        throw 'Expected real Dart fixed55s capacity timeout reporter shape.'
    }
    $variants=$phases+@($modes|Where-Object {$_ -cne 'success-write-capacity'}|ForEach-Object {'mode-'+$_})+@(
        'unknown-token','wrong-prefix','wrong-duration','missing-duration','prefixed-error','suffixed-error','multiline-token','partial-token',
        'oversize-token','non-ascii-token','error-type','event-bound','unknown-name','name-type','wrong-source','unknown-source','missing-url',
        'wrong-suite','missing-suite','wrong-package','invalid-line','unrelated-line','null-line','line-type','fractional-line','id-type',
        'changed-parent','changed-helper','changed-writer','missing-helper','missing-writer','without-producer','invalid-producer','foreign-producer')
    foreach($variant in $variants) {
        $mode=if($variant.StartsWith('mode-')){$variant.Substring(5)}else{'success-write-capacity'}
        $token=if($variant -in $phases){$variant}else{'capacity-start'}
        $events=foreach($rawEvent in $RawCapacity) {
            if($rawEvent.type -ceq 'testStart' -and $rawEvent.test.id -ne $target){continue}
            if($rawEvent.type -cin @('print','error','testDone') -and $rawEvent.testID -ne $target){continue}
            $event=$rawEvent|ConvertTo-Json -Depth 30 -Compress|ConvertFrom-Json -AsHashtable
            if($event.type -ceq 'suite'){$event.suite.path=$parentUri;if($variant -ceq 'missing-suite'){continue}}
            if($event.type -ceq 'testStart') {
                $event.test.name='actual native host trust probes '+$mode;$event.test.url=$parentUri;$event.test.line=$declaration
                switch($variant) {
                    'unknown-name' {$event.test.name+=$PrivateMarker}
                    'name-type' {$event.test.name=@{private=$PrivateMarker}}
                    'wrong-source' {$event.test.url=([Uri](Join-Path $NativeIsarRepository 'packages/serverdeck_locald/test/mcp/gateway_native_test.dart')).AbsoluteUri}
                    'unknown-source' {$event.test.url='file:///C:/'+$PrivateMarker+'/private.dart'}
                    'missing-url' {$event.test.url=$null}
                    'wrong-suite' {$event.test.suiteID=999999}
                    'invalid-line' {$event.test.line=999999}
                    'unrelated-line' {$event.test.line=$producer}
                    'null-line' {$event.test.line=$null}
                    'line-type' {$event.test.line=[string]$declaration}
                    'fractional-line' {$event.test.line=[double]$declaration}
                    'id-type' {$event.test.id=[string]$target}
                }
            }
            if($event.type -ceq 'error') {
                $event.error=$event.error.Replace(':capacity-start',(':'+$token))
                $event.stackTrace="#0 capacity (${parentUri}:${producer}:1)`n#1 private (file:///C:/${PrivateMarker}/private.dart:9:2)"
                switch($variant) {
                    'unknown-token' {$event.error=$event.error.Replace(':capacity-start',(':'+$PrivateMarker))}
                    'wrong-prefix' {$event.error=$event.error.Replace('TRUST_CAPACITY_FIXTURE_TIMEOUT:','PRIVATE_CAPACITY_TIMEOUT:')}
                    'wrong-duration' {$event.error=$event.error.Replace('0:00:55.000000','0:00:54.000000')}
                    'missing-duration' {$event.error=$event.error.Replace(' after 0:00:55.000000','')}
                    'prefixed-error' {$event.error=$PrivateMarker+"`n"+$event.error}
                    'suffixed-error' {$event.error+=$PrivateMarker}
                    'multiline-token' {$event.error+="`n"+$PrivateMarker}
                    'partial-token' {$event.error=$event.error.Replace(':capacity-start',':capacity-star')}
                    'oversize-token' {$event.error=$event.error.Replace(':capacity-start',(':'+('capacity-start'*10)))}
                    'non-ascii-token' {$event.error=$event.error.Replace(':capacity-start',':capacity-старт')}
                    'error-type' {$event.error=@{private=$PrivateMarker}}
                    'event-bound' {$event.error=$PrivateMarker+('x'*256KB)}
                    'without-producer' {$event.stackTrace=$PrivateMarker}
                    'invalid-producer' {$event.stackTrace="#0 capacity (${parentUri}:1:1)"}
                    'foreign-producer' {$event.stackTrace='#0 foreign (package:serverdeck_windows/native_attributes.dart:65:1)'}
                }
            }
            $event|ConvertTo-Json -Depth 30 -Compress
        }
        $caseFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($caseFixture)
        $phase=if($variant -ceq 'wrong-package'){'serverdeck_windows-tests'}else{'serverdeck_locald-tests'}
        [IO.File]::WriteAllLines((Join-Path $caseFixture ($phase+'.machine.jsonl')),[string[]]$events,[Text.UTF8Encoding]::new($false))
        $selected=$Snapshot
        if($variant -in @('changed-parent','changed-helper','changed-writer','missing-helper','missing-writer')) {
            $changed=if($variant -ceq 'changed-parent'){$parentSource}elseif($variant.EndsWith('writer')){$writerSource}else{$helperSource}
            $selected=@{sha256=$Snapshot.sha256;files=@($Snapshot.files|ForEach-Object {
                if($_.file -ceq $changed){if(-not $variant.StartsWith('missing-')){@{file=$changed;sha256=('0'*64)}}}else{$_}
            })}
        }
        Write-NativeQualificationTestFailure -Directory $caseFixture -Phase $phase -SourceSnapshot $selected -ControlledFixture
        $casePath=Join-Path $caseFixture ('safe-test-failure-'+$phase+'.json');$proof=Read-NativeIsarArtifactJson $casePath;$safe=[IO.File]::ReadAllText($casePath)
        if($proof.schemaVersion -ne 1 -or -not $proof.controlledFixture -or $proof.fullAcceptance -or $proof.distributionReady -or $proof.activated -or
            $safe.Contains($PrivateMarker) -or $safe.Contains('TRUST_CAPACITY_FIXTURE_TIMEOUT:') -or $safe.Contains('actual native host trust probes ') -or
            $safe.Contains('file:///') -or $safe.Contains('C:/') -or $safe.Contains('stackTrace') -or $safe.Contains('999999') -or $safe.Contains('0:00:55')) {
            throw ('Capacity phase privacy/schema mismatch: '+$variant)
        }
        if($variant -ceq 'event-bound') {
            if($proof.status -cne 'unavailable-reporter' -or $proof.reporterComplete -or $proof.failures.Count -ne 0){throw 'Capacity reporter event bound changed.'}
            continue
        }
        if($proof.status -cne 'failed-test-details' -or -not $proof.reporterComplete -or $proof.failures.Count -ne 1){throw ('Capacity reporter status mismatch: '+$variant)}
        $failure=$proof.failures[0];$expectPhase=$variant -in $phases
        $expectCase=$variant -notin @('unknown-name','name-type','wrong-source','unknown-source','missing-url','wrong-package','invalid-line','unrelated-line','null-line','line-type','fractional-line','changed-parent')
        if(($expectPhase -and $failure.fixturePhase -cne $token) -or (-not $expectPhase -and $null -ne $failure.fixturePhase) -or
            ($expectCase -and $failure.fixtureCase -cne ('trust-probe-'+$mode)) -or (-not $expectCase -and $null -ne $failure.fixtureCase) -or
            $null -ne $failure.fixtureExitCode -or $null -ne $failure.safeCode -or $failure.nativeErrors.Count -ne 0 -or $failure.sourceFrames.Count -gt 3) {
            throw ('Capacity fixed phase/case/source mismatch: '+$variant)
        }
        $expectTimeout=$variant -notin @('prefixed-error','error-type','invalid-line','null-line','line-type','changed-parent')
        if(($expectTimeout -and $failure.failureKind -cne 'timeout') -or (-not $expectTimeout -and $null -ne $failure.failureKind)) {
            throw ('Capacity prior timeout classification changed: '+$variant)
        }
    }
    $parentText=$parentLines -join "`n";$helperText=$helperLines -join "`n";$writerText=$writerLines -join "`n"
    foreach($text in @($parentText.Replace('const Duration(seconds: 55)','const Duration(seconds: 56)'),
        $parentText.Replace("mode == 'success-write-capacity'","mode == 'success-write-basic'"),$parentText.Replace('TRUST_CAPACITY_FIXTURE_TIMEOUT:','PRIVATE_TIMEOUT:'))) {
        if(Get-NativeCapacityDiagnosticShape -ParentLines ($text -split '\r?\n') -HelperLines $helperLines -WriterLines $writerLines){throw 'Altered capacity parent producer accepted.'}
    }
    foreach($text in @($helperText.Replace('> 64','> 65'),$helperText.Replace('allowInvalid: false','allowInvalid: true'),
        $helperText.Replace("value.endsWith('\n')","value.isNotEmpty"),$helperText.Replace("'capacity-prefill-1000'","'capacity-prefill-1001'"))) {
        if(Get-NativeCapacityDiagnosticShape -ParentLines $parentLines -HelperLines ($text -split '\r?\n') -WriterLines $writerLines){throw 'Altered capacity helper bounds/token contract accepted.'}
    }
    foreach($text in @($writerText.Replace("mode == 'probe-success-write-capacity'","mode == 'probe-success-write-basic'"),
        $writerText.Replace("capacityPhase('capacity-prefill-`$completed')","capacityPhase('capacity-prefill-999')"),$writerText.Replace('db.writeTxnSync(()','db.writeTxn(()'))) {
        if(Get-NativeCapacityDiagnosticShape -ParentLines $parentLines -HelperLines $helperLines -WriterLines ($text -split '\r?\n')){throw 'Altered capacity actor writer contract accepted.'}
    }
    'QUALIFICATION_CAPACITY_31_FIXED_PHASES_UNKNOWN_FALLBACK_35_OTHER_MODES_SOURCE_HASH_55S_PRODUCER_BOUNDS_AND_PRIVACY_NEGATIVES_PASSED'
}

function Test-GatewayExitDiagnosticProjection {
    param([Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][object[]]$RawGateway,
        [Parameter(Mandatory)][string]$PrivateMarker)
    $gatewaySource='packages/serverdeck_locald/test/mcp/gateway_native_test.dart'
    $helperSource='packages/serverdeck_locald/test/support/gateway_fixture_cleanup.dart'
    $actorSource='packages/serverdeck_locald/test/support/gateway_actor.dart'
    $gatewayUri=([Uri](Join-Path $NativeIsarRepository $gatewaySource)).AbsoluteUri
    $helperUri=([Uri](Join-Path $NativeIsarRepository $helperSource)).AbsoluteUri
    $actorUri=([Uri](Join-Path $NativeIsarRepository $actorSource)).AbsoluteUri
    $gatewayLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $gatewaySource))
    $helperLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $helperSource))
    $modeLoop=[regex]::Matches(($gatewayLines -join "`n"),'(?s)for \(final mode in \[(?<cases>.*?)\]\) \{')
    if($modeLoop.Count -ne 1){throw 'Expected one checked gateway mode loop.'}
    $modes=@([regex]::Matches($modeLoop[0].Groups['cases'].Value,"(?m)^\s*'(?<case>[a-z0-9-]+)',\s*$")|ForEach-Object {$_.Groups['case'].Value})
    $declaration=@(for($index=1;$index -lt $gatewayLines.Length;$index++) {
        if($gatewayLines[$index].Trim() -ceq "'actual native MCP gateway `$mode'," -and $gatewayLines[$index-1].Trim() -ceq 'test('){$index}
    })
    $producer=@(for($index=1;$index -lt $gatewayLines.Length;$index++) {
        if($gatewayLines[$index].Trim() -ceq 'await child.exitCode.timeout(' -and $gatewayLines[$index-1].Trim() -ceq 'expect('){$index}
    })
    $bodyLine=@(for($index=0;$index -lt $helperLines.Length;$index++) {
        if($helperLines[$index].Trim() -ceq 'await body();'){$index+1}
    })
    if($modes.Count -ne 27 -or $declaration.Count -ne 1 -or $producer.Count -ne 1 -or $bodyLine.Count -ne 1) {
        throw 'Expected 27 gateway modes and checked declaration, zero-exit producer and helper body.'
    }
    $declaration=$declaration[0];$producer=$producer[0];$bodyLine=$bodyLine[0]
    $bodyStart=@($RawGateway|Where-Object {$_.type -ceq 'testStart' -and $_.test.name -ceq ($PrivateMarker+' gateway body')})
    $bothStart=@($RawGateway|Where-Object {$_.type -ceq 'testStart' -and $_.test.name -ceq ($PrivateMarker+' gateway both')})
    if($bodyStart.Count -ne 1 -or $bothStart.Count -ne 1){throw 'Expected real body-only and aggregate gateway reporter cases.'}
    $variants=$modes+@('exit-signed','exit-unsigned','exit-minimum','exit-maximum','both-primary-actor-before-wrappers','primary-frames-bound',
        'changed-actor','unknown-actor','unknown-mode','suffixed-name','name-type','wrong-source','unknown-source','missing-url','wrong-phase',
        'invalid-declaration','unrelated-declaration','null-declaration','declaration-type','fractional-declaration',
        'changed-gateway','changed-helper','missing-helper','exit-zero','exit-too-low','exit-too-high','exit-plus','exit-fractional',
        'exit-nonnumeric','exit-prefixed','exit-no-line-end','wrong-expected','error-type','without-producer','helper-producer',
        'secondary-producer-only','secondary-exit-only')
    foreach($variant in $variants) {
        $both=$variant -in @('both-primary-actor-before-wrappers','primary-frames-bound','secondary-producer-only','secondary-exit-only')
        $target=if($both){$bothStart[0].test.id}else{$bodyStart[0].test.id}
        $mode=if($variant -in $modes){$variant}else{'quota'}
        $events=foreach($rawEvent in $RawGateway) {
            if($rawEvent.type -ceq 'testStart' -and $rawEvent.test.id -ne $target){continue}
            if($rawEvent.type -cin @('print','error','testDone') -and $rawEvent.testID -ne $target){continue}
            $event=$rawEvent|ConvertTo-Json -Depth 30 -Compress|ConvertFrom-Json -AsHashtable
            if($event.type -ceq 'suite'){$event.suite.path=$gatewayUri}
            if($event.type -ceq 'testStart') {
                $event.test.name='actual native MCP gateway '+$mode;$event.test.url=$gatewayUri;$event.test.line=$declaration
                switch($variant) {
                    'unknown-mode' {$event.test.name='actual native MCP gateway '+$PrivateMarker}
                    'suffixed-name' {$event.test.name+=$PrivateMarker}
                    'name-type' {$event.test.name=@{private=$PrivateMarker}}
                    'wrong-source' {$event.test.url=([Uri](Join-Path $NativeIsarRepository 'packages/serverdeck_locald/test/mcp/trust_probes_native_test.dart')).AbsoluteUri}
                    'unknown-source' {$event.test.url='file:///C:/'+$PrivateMarker+'/private.dart'}
                    'missing-url' {$event.test.url=$null}
                    'invalid-declaration' {$event.test.line=999999}
                    'unrelated-declaration' {$event.test.line=1}
                    'null-declaration' {$event.test.line=$null}
                    'declaration-type' {$event.test.line=[string]$declaration}
                    'fractional-declaration' {$event.test.line=[double]$declaration}
                }
            }
            if($event.type -ceq 'error') {
                if($event.error -cnotmatch '\AExpected: <0>\r?\n[ \t]*Actual: <1>\r?\n' -or
                    -not $event.error.Contains($PrivateMarker) -or -not $event.error.Contains($actorUri) -or
                    ($both -and -not $event.error.Contains("`nGATEWAY_FIXTURE_CLEANUP_FAILURE: "))) {
                    throw 'Expected actual body/aggregate reporter numeric assertion prefix and private nested reason.'
                }
                $event.stackTrace="#0 gateway (${gatewayUri}:${producer}:1)"
                switch($variant) {
                    'exit-signed' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-1073741819>')}
                    'exit-unsigned' {$event.error=$event.error.Replace('Actual: <1>','Actual: <3221225477>')}
                    'exit-minimum' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-2147483648>')}
                    'exit-maximum' {$event.error=$event.error.Replace('Actual: <1>','Actual: <4294967295>')}
                    'exit-zero' {$event.error=$event.error.Replace('Actual: <1>','Actual: <0>')}
                    'exit-too-low' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-2147483649>')}
                    'exit-too-high' {$event.error=$event.error.Replace('Actual: <1>','Actual: <4294967296>')}
                    'exit-plus' {$event.error=$event.error.Replace('Actual: <1>','Actual: <+1>')}
                    'exit-fractional' {$event.error=$event.error.Replace('Actual: <1>','Actual: <1.0>')}
                    'exit-nonnumeric' {$event.error=$event.error.Replace('Actual: <1>',('Actual: <'+$PrivateMarker+'>'))}
                    'exit-prefixed' {$event.error=$PrivateMarker+"`n"+$event.error}
                    'exit-no-line-end' {$event.error="Expected: <0>`n  Actual: <1>"}
                    'wrong-expected' {$event.error=$event.error.Replace('Expected: <0>','Expected: <1>')}
                    'error-type' {$event.error=@{private=$PrivateMarker}}
                    'without-producer' {$event.stackTrace=$PrivateMarker}
                    'helper-producer' {$event.stackTrace="#0 helper (${helperUri}:${bodyLine}:1)"}
                    'secondary-producer-only' {
                        $event.stackTrace="#0 helper (${helperUri}:${bodyLine}:1)"
                        $event.error+="`n#9 secondary (${gatewayUri}:${producer}:1)"
                    }
                    'secondary-exit-only' {$event.error=$PrivateMarker+"`nGATEWAY_FIXTURE_CLEANUP_FAILURE: "+$event.error}
                    'unknown-actor' {$event.error=$event.error.Replace($actorUri,('file:///C:/'+$PrivateMarker+'/private.dart'))}
                }
                if($variant -in @('both-primary-actor-before-wrappers','primary-frames-bound')) {
                    $event.stackTrace="#0 gateway (${gatewayUri}:${producer}:1)`n#1 helper (${helperUri}:${bodyLine}:1)`n#2 wrapper (${gatewayUri}:${declaration}:1)"
                }
                if($variant -ceq 'primary-frames-bound') {
                    $event.error=$event.error.Replace("`nGATEWAY_FIXTURE_CLEANUP_FAILURE: ",
                        "`n#3 actor (${actorUri}:40:1)`n#4 actor (${actorUri}:42:1)`n#5 actor (${actorUri}:43:1)`n#6 invalid (${actorUri}:999999:1)`nGATEWAY_FIXTURE_CLEANUP_FAILURE: ")
                }
            }
            $event|ConvertTo-Json -Depth 30 -Compress
        }
        $caseFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($caseFixture)
        $phase=if($variant -ceq 'wrong-phase'){'serverdeck_windows-tests'}else{'serverdeck_locald-tests'}
        [IO.File]::WriteAllLines((Join-Path $caseFixture ($phase+'.machine.jsonl')),[string[]]$events,[Text.UTF8Encoding]::new($false))
        $selected=$Snapshot
        if($variant -in @('changed-gateway','changed-helper','missing-helper','changed-actor')) {
            $changed=if($variant -ceq 'changed-gateway'){$gatewaySource}elseif($variant -ceq 'changed-actor'){$actorSource}else{$helperSource}
            $selected=@{sha256=$Snapshot.sha256;files=@($Snapshot.files|ForEach-Object {
                if($_.file -ceq $changed) {if($variant -cne 'missing-helper'){@{file=$changed;sha256=('0'*64)}}}else{$_}
            })}
        }
        Write-NativeQualificationTestFailure -Directory $caseFixture -Phase $phase -SourceSnapshot $selected -ControlledFixture
        $casePath=Join-Path $caseFixture ('safe-test-failure-'+$phase+'.json');$caseProof=Read-NativeIsarArtifactJson $casePath
        $safe=[IO.File]::ReadAllText($casePath)
        if($caseProof.schemaVersion -ne 1 -or $caseProof.status -cne 'failed-test-details' -or -not $caseProof.controlledFixture -or
            -not $caseProof.reporterComplete -or $caseProof.failures.Count -ne 1 -or $caseProof.fullAcceptance -or $caseProof.distributionReady -or $caseProof.activated -or
            $safe.Contains($PrivateMarker) -or $safe.Contains('actual native MCP gateway ') -or $safe.Contains('GATEWAY_FIXTURE_CLEANUP_FAILURE:') -or
            $safe.Contains('file:///') -or $safe.Contains('C:/') -or $safe.Contains('stackTrace') -or $safe.Contains('Expected:') -or $safe.Contains('999999')) {
            throw ('Gateway controlled projection privacy/schema mismatch: '+$variant)
        }
        $failure=$caseProof.failures[0]
        $expectCase=$variant -notin @('unknown-mode','suffixed-name','name-type','wrong-source','invalid-declaration','null-declaration','declaration-type','changed-gateway')
        $expectExit=$variant -in $modes -or $variant -in @('exit-signed','exit-unsigned','exit-minimum','exit-maximum',
            'both-primary-actor-before-wrappers','primary-frames-bound','changed-actor','unknown-actor')
        $expectedExit=switch($variant){'exit-signed'{-1073741819L};'exit-unsigned'{3221225477L};'exit-minimum'{-2147483648L};'exit-maximum'{4294967295L};default{1L}}
        if(($expectCase -and $failure.fixtureCase -cne ('gateway-'+$mode)) -or (-not $expectCase -and $null -ne $failure.fixtureCase) -or
            ($expectExit -and ($failure.failureKind -cne 'fixture-exit' -or $failure.fixtureExitCode -ne $expectedExit)) -or
            (-not $expectExit -and ($null -ne $failure.failureKind -or $null -ne $failure.fixtureExitCode)) -or
            $null -ne $failure.fixturePhase -or $null -ne $failure.safeCode -or $failure.nativeErrors.Count -ne 0 -or $failure.sourceFrames.Count -gt 3) {
            throw ('Gateway checked numeric exit/case projection mismatch: '+$variant)
        }
        if($expectExit -and $variant -notin @('changed-actor','unknown-actor') -and
            ($failure.sourceFrames.Count -lt 1 -or $failure.sourceFrames[0].file -cne $actorSource -or $failure.sourceFrames[0].line -ne 40)) {
            throw ('Gateway primary actor frame was lost behind wrapper frames: '+$variant)
        }
        if($variant -ceq 'both-primary-actor-before-wrappers' -and
            ($failure.sourceFrames.Count -ne 3 -or $failure.sourceFrames[1].file -cne $gatewaySource -or $failure.sourceFrames[1].line -ne $producer -or
                $failure.sourceFrames[2].file -cne $helperSource -or $failure.sourceFrames[2].line -ne $bodyLine)) {
            throw 'Gateway aggregate primary frame priority/order changed.'
        }
        if($variant -ceq 'primary-frames-bound' -and
            ($failure.sourceFrames.Count -ne 3 -or $failure.sourceFrames[1].line -ne 42 -or $failure.sourceFrames[2].line -ne 43)) {
            throw 'Gateway primary actor frame cap or dedup changed.'
        }
        if($expectExit) {
            foreach($frame in $failure.sourceFrames) {
                if($frame.file -ceq $actorSource -and $frame.line -eq 41){throw 'Secondary cleanup actor frame became primary evidence.'}
                if($variant -ceq 'changed-actor' -and $frame.file -ceq $actorSource){throw 'Stale gateway actor frame was exported.'}
            }
        }
    }
    $gatewayText=$gatewayLines -join "`n";$helperText=$helperLines -join "`n"
    foreach($mutation in @($gatewayText.Replace('const Duration(seconds: 70)','const Duration(seconds: 71)'),
        $gatewayText.Replace("              0,`n              reason:","              1,`n              reason:"),
        $gatewayText.Replace('cleanup: fixture.close,','cleanup: () async {},'))) {
        if(Get-NativeGatewayDiagnosticShape -GatewayLines ($mutation -split '\r?\n') -HelperLines $helperLines) {
            throw 'Gateway altered zero-exit producer or cleanup binding was accepted.'
        }
    }
    foreach($mutation in @($helperText.Replace("GATEWAY_FIXTURE_CLEANUP_FAILURE:","PRIVATE_OTHER_CLEANUP:"),
        $helperText.Replace('await cleanup();','cleanup();'),$helperText.Replace('primary.stackTrace,','stackTrace,'))) {
        if(Get-NativeGatewayDiagnosticShape -GatewayLines $gatewayLines -HelperLines ($mutation -split '\r?\n')) {
            throw 'Gateway altered primary/cleanup helper contract was accepted.'
        }
    }
    'QUALIFICATION_GATEWAY_CHECKED_NUMERIC_EXIT_SIGNED_UNSIGNED_PRIMARY_ACTOR_PRIORITY_AGGREGATE_HASH_BOUNDS_AND_PRIVACY_NEGATIVES_PASSED'
}

function Test-TrustProbeDiagnosticProjection {
    param([Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][object[]]$RawTimeout,
        [Parameter(Mandatory)][string]$PrivateMarker)
    $trustSource='packages/serverdeck_locald/test/mcp/trust_probes_native_test.dart'
    $trustUri=([Uri](Join-Path $NativeIsarRepository $trustSource)).AbsoluteUri
    $trustLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $trustSource))
    $modeLoop=[regex]::Matches(($trustLines -join "`n"),'(?s)for \(final mode in \[(?<cases>.*?)\]\) \{')
    if($modeLoop.Count -ne 1){throw 'Expected one checked native trust probe mode loop.'}
    $trustModes=@([regex]::Matches($modeLoop[0].Groups['cases'].Value,"(?m)^\s*'(?<case>[a-z0-9-]+)',\s*$")|ForEach-Object {$_.Groups['case'].Value})
    $declaration=@(for($index=1;$index -lt $trustLines.Length;$index++) {
        if($trustLines[$index].Trim() -ceq "'actual native host trust probes `$mode'," -and
            $trustLines[$index-1].Trim() -ceq 'test('){$index}
    })
    $exitLine=@(for($index=0;$index+1 -lt $trustLines.Length;$index++) {
        if($trustLines[$index].Trim() -ceq 'await child.exitCode.timeout(' -and
            $trustLines[$index+1].Trim() -ceq 'const Duration(seconds: 55),'){$index+1}
    })
    if($trustModes.Count -ne 36 -or $declaration.Count -ne 1 -or $exitLine.Count -ne 1) {
        throw 'Expected 36 fixed trust probe modes, one checked declaration and unchanged child deadline.'
    }
    $declaration=$declaration[0];$exitLine=$exitLine[0]
    $rawError=@($RawTimeout|Where-Object {$_.type -ceq 'error'})[0]
    $target=$rawError.testID
    if($rawError.error -cne 'TimeoutException after 0:00:00.001000: Future not completed') {
        throw 'Expected actual Dart controlled timeout reporter shape.'
    }
    foreach($variant in ($trustModes+@('unknown-mode','suffixed-name','prefixed-name','name-type','wrong-source','unknown-source',
        'missing-url','url-type','invalid-declaration','unrelated-declaration','non-test-line','null-declaration','declaration-type',
        'fractional-declaration','changed-source','wrong-phase','plain-assertion','safe-code','without-frame','unknown-frame','invalid-frame'))) {
        $mode=if($variant -in $trustModes){$variant}else{'basic'}
        $events=foreach($rawEvent in $RawTimeout) {
            if($rawEvent.type -ceq 'testStart' -and $rawEvent.test.id -ne $target){continue}
            if($rawEvent.type -cin @('print','error','testDone') -and $rawEvent.testID -ne $target){continue}
            $event=$rawEvent|ConvertTo-Json -Depth 30 -Compress|ConvertFrom-Json -AsHashtable
            if($event.type -ceq 'suite'){$event.suite.path=$trustUri}
            if($event.type -ceq 'testStart') {
                $event.test.name='actual native host trust probes '+$mode
                $event.test.url=$trustUri
                $event.test.line=$declaration
                switch($variant) {
                    'unknown-mode' {$event.test.name='actual native host trust probes '+$PrivateMarker}
                    'suffixed-name' {$event.test.name+=$PrivateMarker}
                    'prefixed-name' {$event.test.name=$PrivateMarker+$event.test.name}
                    'name-type' {$event.test.name=@{private=$PrivateMarker}}
                    'wrong-source' {$event.test.url=([Uri](Join-Path $NativeIsarRepository 'packages/serverdeck_locald/test/storage/operational_open_native_test.dart')).AbsoluteUri}
                    'unknown-source' {$event.test.url='file:///C:/'+$PrivateMarker+'/private.dart'}
                    'missing-url' {$event.test.url=$null}
                    'url-type' {$event.test.url=@{private=$PrivateMarker}}
                    'invalid-declaration' {$event.test.line=999999}
                    'unrelated-declaration' {$event.test.line=1}
                    'non-test-line' {$event.test.line=$exitLine}
                    'null-declaration' {$event.test.line=$null}
                    'declaration-type' {$event.test.line=[string]$declaration}
                    'fractional-declaration' {$event.test.line=[double]$declaration}
                }
            }
            if($event.type -ceq 'error') {
                $event.stackTrace="#0 controlled (${trustUri}:${exitLine}:1)`n#1 private (file:///C:/${PrivateMarker}/private.dart:9:2)"
                switch($variant) {
                    'plain-assertion' {$event.error="Expected: <0>`n  Actual: <1>`n"+$PrivateMarker}
                    'safe-code' {$event.error='Bad state: WORKSPACE_CHILD_TIMEOUT'}
                    'without-frame' {$event.stackTrace=$PrivateMarker}
                    'unknown-frame' {$event.stackTrace="#0 private (file:///C:/${PrivateMarker}/private.dart:${exitLine}:1)"}
                    'invalid-frame' {$event.stackTrace="#0 controlled (${trustUri}:999999:1)"}
                }
            }
            $event|ConvertTo-Json -Depth 30 -Compress
        }
        $caseFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($caseFixture)
        $phase=if($variant -ceq 'wrong-phase'){'serverdeck_windows-tests'}else{'serverdeck_locald-tests'}
        [IO.File]::WriteAllLines((Join-Path $caseFixture ($phase+'.machine.jsonl')),[string[]]$events,[Text.UTF8Encoding]::new($false))
        $selected=$Snapshot
        if($variant -ceq 'changed-source') {
            $selected=@{sha256=$Snapshot.sha256;files=@($Snapshot.files|ForEach-Object {
                if($_.file -ceq $trustSource){@{file=$trustSource;sha256=('0'*64)}}else{$_}
            })}
        }
        Write-NativeQualificationTestFailure -Directory $caseFixture -Phase $phase -SourceSnapshot $selected -ControlledFixture
        $casePath=Join-Path $caseFixture ('safe-test-failure-'+$phase+'.json')
        $caseProof=Read-NativeIsarArtifactJson $casePath
        $safe=[IO.File]::ReadAllText($casePath)
        if($caseProof.schemaVersion -ne 1 -or $caseProof.status -cne 'failed-test-details' -or -not $caseProof.controlledFixture -or
            -not $caseProof.reporterComplete -or $caseProof.failures.Count -ne 1 -or
            $safe.Contains($PrivateMarker) -or $safe.Contains('actual native host trust probes ') -or
            $safe.Contains('file:///') -or $safe.Contains('C:/') -or $safe.Contains('stackTrace') -or
            $safe.Contains('Future not completed') -or $safe.Contains('Expected:') -or $safe.Contains('999999') -or
            $caseProof.fullAcceptance -or $caseProof.distributionReady -or $caseProof.activated) {
            throw ('Trust probe controlled projection privacy/schema mismatch: '+$variant)
        }
        $failure=$caseProof.failures[0]
        $expectCase=$variant -in $trustModes -or $variant -in @('plain-assertion','safe-code','without-frame','unknown-frame','invalid-frame')
        if(($expectCase -and $failure.fixtureCase -cne ('trust-probe-'+$mode)) -or
            (-not $expectCase -and $null -ne $failure.fixtureCase) -or
            $null -ne $failure.fixtureExitCode -or $null -ne $failure.fixturePhase -or $failure.nativeErrors.Count -ne 0) {
            throw ('Trust probe fixed case/source projection mismatch: '+$variant)
        }
        if(($variant -in $trustModes -and $failure.failureKind -cne 'timeout') -or
            ($variant -in @('plain-assertion','safe-code') -and $null -ne $failure.failureKind) -or
            ($variant -ceq 'safe-code' -and $failure.safeCode -cne 'WORKSPACE_CHILD_TIMEOUT') -or
            ($variant -cne 'safe-code' -and $null -ne $failure.safeCode)) {
            throw ('Trust probe prior error classification changed: '+$variant)
        }
        $expectedFrames=if($variant -in @('changed-source','without-frame','unknown-frame','invalid-frame')){0}else{1}
        if($failure.sourceFrames.Count -ne $expectedFrames -or
            ($expectedFrames -eq 1 -and ($failure.sourceFrames[0].file -cne $trustSource -or $failure.sourceFrames[0].line -ne $exitLine))) {
            throw ('Trust probe checked frame projection changed: '+$variant)
        }
    }
    'QUALIFICATION_REAL_TIMEOUT_TRUST_PROBE_36_FIXED_MODES_SOURCE_HASH_DECLARATION_SHAPE_AND_PRIVACY_NEGATIVES_PASSED'
}

function Test-BootstrapDiagnosticProjection {
    param([Parameter(Mandatory)][string]$Fixture,
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][object[]]$RawBootstrap,
        [Parameter(Mandatory)][string]$PrivateMarker)
    $bootstrapSource='packages/serverdeck_locald/test/bootstrap_native_test.dart'
    $preparationSource='packages/serverdeck_locald/test/support/bootstrap_preparation.dart'
    $bootstrapUri=([Uri](Join-Path $NativeIsarRepository $bootstrapSource)).AbsoluteUri
    $bootstrapLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $bootstrapSource))
    $bodyLine=@(for($index=1;$index -lt $bootstrapLines.Length;$index++) {
        if($bootstrapLines[$index].Trim() -ceq "'compiled owner authenticates, becomes ready, closes and reopens workspace'," -and
            $bootstrapLines[$index-1].Trim() -ceq 'test('){$index}
    })
    $hookLine=@(for($index=0;$index -lt $bootstrapLines.Length;$index++) {
        if($bootstrapLines[$index].Trim() -ceq 'setUpAll(() async {'){$index+1}
    })
    if($bodyLine.Count -ne 1 -or $hookLine.Count -ne 1){throw 'Expected one checked bootstrap body and preparation hook declaration.'}
    $bodyLine=$bodyLine[0];$hookLine=$hookLine[0]
    $preparationLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $preparationSource))
    $preparationText=$preparationLines -join "`n"
    if(-not (Get-NativeBootstrapDiagnosticShape -BootstrapLines $bootstrapLines -PreparationLines $preparationLines)) {
        throw 'Expected checked bootstrap producer source shape.'
    }
    foreach($mutation in @(
        $preparationText.Replace('print(''BOOTSTRAP_FIXTURE_PHASE:${phase.identifier}'');','print(phase.identifier);'),
        $preparationText.Replace("compileOwner('compile-owner')","compileOwner('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER')"),
        $preparationText.Replace('final String identifier;','String identifier;'),
        ($preparationText+"`n// BOOTSTRAP_FIXTURE_PHASE:SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER"))) {
        if(Get-NativeBootstrapDiagnosticShape -BootstrapLines $bootstrapLines -PreparationLines ($mutation -split '\r?\n')) {
            throw 'Bootstrap invalid producer or unknown enum source was accepted.'
        }
    }
    $bodyName='compiled bootstrap compiled owner authenticates, becomes ready, closes and reopens workspace'
    $hookName='compiled bootstrap (setUpAll)'
    $rawHook=@($RawBootstrap|Where-Object {$_.type -ceq 'testStart' -and $_.test.name -ceq ($PrivateMarker+' preparation (setUpAll)')})
    $rawBody=@($RawBootstrap|Where-Object {$_.type -ceq 'testStart' -and $_.test.name -ceq ($PrivateMarker+' behavior body')})
    if($rawHook.Count -ne 1 -or $rawBody.Count -ne 1 -or $rawHook[0].test.line -ne 5 -or
        $rawBody[0].test.line -ne 12 -or $rawHook[0].test.url -isnot [string]) {
        throw 'Expected actual Dart preparation hook/body reporter metadata.'
    }
    $bootstrapPhases=@('prepare-start','compile-owner','compile-client','select-native','manifest','prepared',
        'behavior-start','namespace-check','run-0','run-1','run-2','run-3','run-4','run-5','refusal-checks','cleanup','complete')
    $variants=@($bootstrapPhases|ForEach-Object {'body-'+$_; 'hook-'+$_})+@(
        'hook-null-line','body-without-marker','hook-without-marker','last-fixed-phase','different-test-id','string-test-id','string-start-id','string-suite-id',
        'unknown-name','name-type','unknown-source','missing-source','wrong-suite','missing-suite','unrelated-source',
        'invalid-body-line','unrelated-body-line','null-body-line','invalid-hook-line','unrelated-hook-line',
        'changed-bootstrap','changed-preparation','missing-preparation','wrong-package',
        'unknown-phase','prefixed-marker','suffixed-marker','multiline-marker','arbitrary-print','wrong-message-type','wrong-event-type','wrong-event-case',
        'marker-before-start','marker-after-error','cross-test-marker','reused-test-id','id-bound-32','id-bound-33')
    foreach($variant in $variants) {
        $hook=$variant.StartsWith('hook-') -or $variant -in @('invalid-hook-line','unrelated-hook-line')
        $target=if($hook){$rawHook[0].test.id}else{$rawBody[0].test.id}
        $events=[Collections.Generic.List[object]]::new()
        foreach($rawEvent in $RawBootstrap) {
            if($rawEvent.type -cnotin @('suite','testStart','print','error','done')){continue}
            if($rawEvent.type -ceq 'testStart' -and $rawEvent.test.id -ne $target){continue}
            if($rawEvent.type -cin @('print','error') -and $rawEvent.testID -ne $target){continue}
            $event=$rawEvent|ConvertTo-Json -Depth 30 -Compress|ConvertFrom-Json -AsHashtable
            if($event.type -ceq 'suite'){$event.suite.path=$bootstrapUri}
            if($event.type -ceq 'testStart') {
                $event.test.name=if($hook){$hookName}else{$bodyName}
                $event.test.url=$bootstrapUri
                $event.test.line=if($hook){$hookLine}else{$bodyLine}
                switch($variant) {
                    'hook-null-line' {$event.test.line=$null}
                    'unknown-name' {$event.test.name+=$PrivateMarker}
                    'name-type' {$event.test.name=@{private=$PrivateMarker}}
                    'unknown-source' {$event.test.url='file:///C:/'+$PrivateMarker+'/private.dart'}
                    'missing-source' {$event.test.url=$null}
                    'unrelated-source' {$event.test.url=([Uri](Join-Path $NativeIsarRepository 'packages/serverdeck_locald/test/storage/operational_open_native_test.dart')).AbsoluteUri}
                    'wrong-suite' {$event.test.suiteID=999999}
                    'string-start-id' {$event.test.id=[string]$event.test.id}
                    'string-suite-id' {$event.test.suiteID=[string]$event.test.suiteID}
                    'invalid-body-line' {$event.test.line=999999}
                    'unrelated-body-line' {$event.test.line=1}
                    'null-body-line' {$event.test.line=$null}
                    'invalid-hook-line' {$event.test.line=999999}
                    'unrelated-hook-line' {$event.test.line=1}
                }
                if($variant -ceq 'marker-before-start') {
                    $events.Add(@{type='print';messageType='print';message='BOOTSTRAP_FIXTURE_PHASE:run-2';testID=$target})
                }
                if($variant -in @('id-bound-32','id-bound-33')) {
                    $extra=if($variant -ceq 'id-bound-32'){31}else{32}
                    for($index=0;$index -lt $extra;$index++) {
                        $copy=$event|ConvertTo-Json -Depth 30 -Compress|ConvertFrom-Json -AsHashtable
                        $copy.test.id=100+$index
                        $events.Add($copy)
                    }
                }
                $events.Add($event)
                if($variant -ceq 'reused-test-id'){$events.Add($event)}
                continue
            }
            if($event.type -ceq 'suite' -and $variant -ceq 'missing-suite'){continue}
            if($event.type -ceq 'print') {
                if($variant -in @('body-without-marker','hook-without-marker','marker-before-start','marker-after-error')){continue}
                if($variant -cmatch '^(body|hook)-(.+)$' -and $Matches[2] -in $bootstrapPhases) {
                    $event.message='BOOTSTRAP_FIXTURE_PHASE:'+$Matches[2]
                }
                switch($variant) {
                    'different-test-id' {$event.testID=999999}
                    'string-test-id' {$event.testID=[string]$target}
                    'unknown-phase' {$event.message='BOOTSTRAP_FIXTURE_PHASE:'+ $PrivateMarker}
                    'prefixed-marker' {$event.message=$PrivateMarker+$event.message}
                    'suffixed-marker' {$event.message+=$PrivateMarker}
                    'multiline-marker' {$event.message+="`n"+$PrivateMarker}
                    'arbitrary-print' {$event.message=$PrivateMarker}
                    'wrong-message-type' {$event.messageType='error'}
                    'wrong-event-type' {$event.type='stdout'}
                    'wrong-event-case' {$event.type='PRINT'}
                    'cross-test-marker' {
                        $copy=$rawBody[0]|ConvertTo-Json -Depth 30 -Compress|ConvertFrom-Json -AsHashtable
                        $copy.test.id=100;$copy.test.name=$bodyName;$copy.test.url=$bootstrapUri;$copy.test.line=$bodyLine
                        $events.Add($copy)
                        $event.testID=100
                    }
                }
                $events.Add($event)
                if($variant -ceq 'last-fixed-phase') {
                    $events.Add(@{type='print';messageType='print';message='BOOTSTRAP_FIXTURE_PHASE:cleanup';testID=$target})
                    $events.Add(@{type='print';messageType='print';message=$PrivateMarker;testID=$target})
                }
                continue
            }
            if($event.type -ceq 'error') {
                if($event.error -cne 'TimeoutException after 0:00:00.001000: Future not completed') {
                    throw 'Expected actual Dart bootstrap probe timeout shape.'
                }
                $event.stackTrace=$PrivateMarker
                $events.Add($event)
                if($variant -ceq 'marker-after-error') {
                    $events.Add(@{type='print';messageType='print';message='BOOTSTRAP_FIXTURE_PHASE:run-2';testID=$target})
                }
                continue
            }
            $events.Add($event)
        }
        $caseFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($caseFixture)
        $phase=if($variant -ceq 'wrong-package'){'serverdeck_windows-tests'}else{'serverdeck_locald-tests'}
        [IO.File]::WriteAllLines((Join-Path $caseFixture ($phase+'.machine.jsonl')),
            [string[]]@($events|ForEach-Object {$_|ConvertTo-Json -Depth 30 -Compress}),[Text.UTF8Encoding]::new($false))
        $selected=$Snapshot
        if($variant -in @('changed-bootstrap','changed-preparation','missing-preparation')) {
            $changed=if($variant -ceq 'changed-bootstrap'){$bootstrapSource}else{$preparationSource}
            $selected=@{sha256=$Snapshot.sha256;files=@($Snapshot.files|ForEach-Object {
                if($_.file -ceq $changed) {
                    if($variant -cne 'missing-preparation'){@{file=$changed;sha256=('0'*64)}}
                } else {$_}
            })}
        }
        Write-NativeQualificationTestFailure -Directory $caseFixture -Phase $phase -SourceSnapshot $selected -ControlledFixture
        $casePath=Join-Path $caseFixture ('safe-test-failure-'+$phase+'.json')
        $caseProof=Read-NativeIsarArtifactJson $casePath
        $safe=[IO.File]::ReadAllText($casePath)
        if($safe.Contains($PrivateMarker) -or $safe.Contains('BOOTSTRAP_FIXTURE_PHASE:') -or $safe.Contains('file:///') -or
            $safe.Contains('C:/') -or $safe.Contains('stackTrace') -or $safe.Contains('Future not completed') -or
            $safe.Contains($bodyName) -or $safe.Contains($hookName) -or $safe.Contains('999999') -or
            $caseProof.schemaVersion -ne 1 -or -not $caseProof.controlledFixture -or
            $caseProof.fullAcceptance -or $caseProof.distributionReady -or $caseProof.activated) {
            throw ('Bootstrap controlled projection privacy/schema mismatch: '+$variant)
        }
        if($variant -ceq 'id-bound-33') {
            if($caseProof.status -cne 'unavailable-reporter' -or $caseProof.reporterComplete -or $caseProof.failures.Count -ne 0) {
                throw 'Bootstrap test ID replay bound did not fail closed.'
            }
            continue
        }
        if($caseProof.status -cne 'failed-test-details' -or -not $caseProof.reporterComplete -or $caseProof.failures.Count -ne 1) {
            throw ('Bootstrap controlled projection status mismatch: '+$variant)
        }
        $failure=$caseProof.failures[0]
        $expectCase=$variant -notin @('unknown-name','name-type','unknown-source','missing-source','unrelated-source','wrong-suite','missing-suite','string-start-id','string-suite-id',
            'invalid-body-line','unrelated-body-line','null-body-line','invalid-hook-line','unrelated-hook-line',
            'changed-bootstrap','changed-preparation','missing-preparation','wrong-package','reused-test-id')
        $expectPhase=$expectCase -and ($variant -cmatch '^(body|hook)-(.+)$' -and $Matches[2] -in $bootstrapPhases -or
            $variant -in @('hook-null-line','last-fixed-phase','id-bound-32'))
        $expectedPhase=if($variant -ceq 'last-fixed-phase'){'cleanup'}elseif($variant -ceq 'hook-null-line'){'compile-owner'}elseif($variant -ceq 'id-bound-32'){'run-2'}elseif($expectPhase){$variant.Substring(5)}else{$null}
        $expectedCase=if($hook){'bootstrap-prepare'}else{'bootstrap-body'}
        if(($expectCase -and $failure.fixtureCase -cne $expectedCase) -or
            (-not $expectCase -and $null -ne $failure.fixtureCase) -or
            ($expectPhase -and $failure.fixturePhase -cne $expectedPhase) -or
            (-not $expectPhase -and $null -ne $failure.fixturePhase) -or
            $null -ne $failure.fixtureExitCode -or $null -ne $failure.safeCode -or
            $failure.nativeErrors.Count -ne 0 -or $failure.sourceFrames.Count -ne 0) {
            throw ('Bootstrap fixed case/phase/source projection mismatch: '+$variant)
        }
        if($variant -ceq 'hook-null-line' -and ($null -ne $failure.declarationLine -or $null -ne $failure.failureKind)) {
            throw 'Bootstrap synthetic preparation declaration was invented.'
        }
    }
    'QUALIFICATION_REAL_BOOTSTRAP_REPORTER_BODY_PREPARATION_17_FIXED_PHASES_SOURCE_HASH_DECLARATION_ID_BOUND_AND_PRIVACY_NEGATIVES_PASSED'
}
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
Test-TrustProbeDiagnosticProjection -Snapshot $snapshot -RawTimeout @($rawTimeout|ForEach-Object {$_|ConvertFrom-Json -AsHashtable}) -PrivateMarker $privateMarker
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

# A real failing expect carries the child's stack in its reason rather than
# the reporter stackTrace. Aliases below are controlled diagnostics, never
# evidence that the native client scenarios themselves ran or passed.
$clientModes=@('owner','cleanup2','cleanup3','mcp','grant','grant-bad-proof','grant-repeat','codes','quota','receipts',
    'connection','bad-connection','bad-connect','bad-connect-status','bad-connect-cancel','bad-disconnect',
    'readiness2','bad-receipt','bad-retry','unknown-code','bad-field','wrong-id','wrong-generation','oversize',
    'invalid-json','timeout','eof','duplicate','single-use','wrong-token','bad-proof','hello-role','hello-generation',
    'hello-build','hello-version','hello-shape','bootstrap-timeout')
$clientSource='packages/serverdeck_windows/test/trusted_client_native_test.dart'
$actorSource='packages/serverdeck_windows/test/support/trusted_client_actor.dart'
$clientUri=([Uri](Join-Path $NativeIsarRepository $clientSource)).AbsoluteUri
$actorUri=([Uri](Join-Path $NativeIsarRepository $actorSource)).AbsoluteUri
$assertProbe=Join-Path $fixture 'controlled-client-assert.dart'
$assertReport=Join-Path $fixture 'controlled-client-assert.machine.jsonl'
$assertDart=@'
import 'package:test/test.dart';
void main() {
  test('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER nested client', () {
    expect(1, 0, reason: 'SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER\n'
      '#0 check (FIXTURE_ACTOR_URI:40:1)\n'
      '#1 private (file:///C:/SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER/private.dart:9:2)');
  });
}
'@
[IO.File]::WriteAllText($assertProbe,$assertDart.Replace('FIXTURE_ACTOR_URI',$actorUri),[Text.UTF8Encoding]::new($false))
Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_windows')
try {
    & $FoundationDart test $assertProbe --file-reporter "json:$assertReport" *> (Join-Path $fixture 'controlled-client-assert.private.txt')
    if($LASTEXITCODE -eq 0){throw 'Controlled assertion unexpectedly passed.'}
} finally {Pop-Location}
$rawAssert=[IO.File]::ReadAllLines($assertReport)
foreach($variant in ($clientModes+@('unknown-client','unknown-name','name-type','invalid-line','changed-source','unknown-source','actor-changed','frames-bound','joint-frames','plain-assertion','exit-signed','exit-unsigned','exit-zero','exit-too-low','exit-too-high','exit-prefixed','exit-nonnumeric','exit-no-line-end'))) {
    $caseFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($caseFixture)
    $mode=if($variant -in $clientModes){$variant}else{'owner'}
    $events=foreach($line in $rawAssert) {
        $event=$line|ConvertFrom-Json -AsHashtable
        if($event.type -ceq 'testStart' -and $event.test.name -ceq ($privateMarker+' nested client')) {
            $event.test.name='actual format3 bootstrap and RPC client '+$mode
            $event.test.url=$clientUri
            $event.test.line=65
            switch($variant) {
                'unknown-client' {$event.test.name='actual format3 bootstrap and RPC client '+$privateMarker}
                'unknown-name' {$event.test.name+=$privateMarker}
                'name-type' {$event.test.name=@{private=$privateMarker}}
                'invalid-line' {$event.test.line=999999}
                'unknown-source' {$event.test.url='file:///C:/'+$privateMarker+'/private.dart'}
            }
        }
        if($event.type -ceq 'error') {
            if(-not $event.error.Contains('Expected: <0>') -or -not $event.error.Contains($actorUri)) {
                throw 'Expected real Dart assertion with nested reason.'
            }
            if($variant -ceq 'plain-assertion') {$event.error='Expected: <0>\nActual: <1>\n'+$privateMarker}
            switch($variant) {
                'exit-signed' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-1073741819>')}
                'exit-unsigned' {$event.error=$event.error.Replace('Actual: <1>','Actual: <3221225477>')}
                'exit-zero' {$event.error=$event.error.Replace('Actual: <1>','Actual: <0>')}
                'exit-too-low' {$event.error=$event.error.Replace('Actual: <1>','Actual: <-2147483649>')}
                'exit-too-high' {$event.error=$event.error.Replace('Actual: <1>','Actual: <4294967296>')}
                'exit-prefixed' {$event.error=$privateMarker+"`n"+$event.error}
                'exit-nonnumeric' {$event.error=$event.error.Replace('Actual: <1>',('Actual: <'+$privateMarker+'>'))}
                'exit-no-line-end' {$event.error="Expected: <0>`n  Actual: <1>"}
            }
            if($variant -ceq 'frames-bound') {
                $event.error+="`n"+((@(40,40,41,42,43,999999)|ForEach-Object{"#0 check (${actorUri}:$($_):1)"}) -join "`n")
            }
            if($variant -ceq 'joint-frames') {
                $event.stackTrace="#0 parent (${clientUri}:84:1)`n#1 child (${actorUri}:40:1)"
                $event.error+="`n#2 child (${actorUri}:41:1)`n#3 child (${actorUri}:42:1)"
            }
        }
        $event|ConvertTo-Json -Depth 30 -Compress
    }
    [IO.File]::WriteAllLines((Join-Path $caseFixture 'serverdeck_windows-tests.machine.jsonl'),[string[]]$events,[Text.UTF8Encoding]::new($false))
    $selected=$snapshot
    if($variant -in @('changed-source','actor-changed')) {
        $changed=if($variant -ceq 'changed-source'){$clientSource}else{$actorSource}
        $selected=@{sha256=$snapshot.sha256;files=@($snapshot.files|ForEach-Object{
            if($_.file -ceq $changed){@{file=$changed;sha256=('0'*64)}}else{$_}
        })}
    }
    Write-NativeQualificationTestFailure -Directory $caseFixture -Phase 'serverdeck_windows-tests' -SourceSnapshot $selected -ControlledFixture
    $casePath=Join-Path $caseFixture 'safe-test-failure-serverdeck_windows-tests.json'
    $caseProof=Read-NativeIsarArtifactJson $casePath
    $safe=[IO.File]::ReadAllText($casePath)
    if($caseProof.status -cne 'failed-test-details' -or -not $caseProof.controlledFixture -or
        -not $caseProof.reporterComplete -or $caseProof.failures.Count -ne 1 -or
        $safe.Contains($privateMarker) -or $safe.Contains('file:///') -or $safe.Contains('stackTrace') -or
        $safe.Contains('Expected:') -or $safe.Contains('999999')){throw 'Client projection privacy/report mismatch.'}
    $failure=$caseProof.failures[0]
    $expectCase=$variant -notin @('unknown-client','unknown-name','name-type','invalid-line','changed-source','unknown-source')
    if(($expectCase -and $failure.fixtureCase -cne ('trusted-client-'+$mode)) -or
        (-not $expectCase -and $null -ne $failure.fixtureCase)){throw ('Client fixed case mismatch: '+$variant)}
    $frameCount=if($variant -in @('actor-changed','plain-assertion','exit-no-line-end')){0}elseif($variant -in @('frames-bound','joint-frames')){3}else{1}
    $expectExit=$expectCase -and $variant -notin @('plain-assertion','exit-zero','exit-too-low','exit-too-high','exit-prefixed','exit-nonnumeric','exit-no-line-end')
    $exitCode=if($variant -ceq 'exit-signed'){-1073741819L}elseif($variant -ceq 'exit-unsigned'){3221225477L}else{1L}
    if(($expectExit -and ($failure.failureKind -cne 'fixture-exit' -or $failure.fixtureExitCode -ne $exitCode)) -or
        (-not $expectExit -and ($null -ne $failure.failureKind -or $null -ne $failure.fixtureExitCode))) {throw ('Client fixed exit projection mismatch: '+$variant)}
    if($failure.sourceFrames.Count -ne $frameCount -or $null -ne $failure.safeCode -or $null -ne $failure.fixturePhase){throw ('Client nested frame bounds mismatch: '+$variant)}
    foreach($frame in $failure.sourceFrames){
        if($variant -ceq 'joint-frames' -and $frame.file -ceq $clientSource -and $frame.line -eq 84){continue}
        if($frame.file -cne $actorSource -or $frame.line -notin @(40,41,42)){throw 'Client nested source mismatch.'}
    }
    if($variant -ceq 'joint-frames' -and ($failure.sourceFrames[0].file -cne $clientSource -or
        $failure.sourceFrames[1].line -ne 40 -or $failure.sourceFrames[2].line -ne 41)){throw 'Joint frame total cap/order/dedup mismatch.'}
    if($caseProof.fullAcceptance -or $caseProof.distributionReady -or $caseProof.activated){throw 'Controlled projection claimed qualification.'}
}
'QUALIFICATION_REAL_ASSERTION_TRUSTED_CLIENT_37_FIXED_CASES_NESTED_SOURCE_HASH_BOUNDS_PRIVACY_NEGATIVES_PASSED'
'QUALIFICATION_TRUSTED_CLIENT_FIXED_EXIT_SIGNED_UNSIGNED_RANGE_SHAPE_SOURCE_PRIVACY_NEGATIVES_PASSED'

# Use a real Dart FileSystemException reporter, then alias only its metadata
# and checked source frames. These controlled errors do not identify the OS
# error from a native qualification run or claim that a fixture ran.
$cleanupSource='packages/serverdeck_windows/test/support/owned_fixture_cleanup.dart'
$cleanupUri=([Uri](Join-Path $NativeIsarRepository $cleanupSource)).AbsoluteUri
$cleanupLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $cleanupSource))
$cleanupLine=@(for($index=0;$index -lt $cleanupLines.Length;$index++) {
    if($cleanupLines[$index].Trim() -ceq 'checkedDirectory.deleteSync(recursive: true);'){$index+1}
})
if($cleanupLine.Count -ne 1){throw 'Expected exactly one checked owned fixture delete statement.'}
$cleanupLine=$cleanupLine[0]
$cleanupProbe=Join-Path $fixture 'controlled-cleanup.dart'
$cleanupReport=Join-Path $fixture 'controlled-cleanup.machine.jsonl'
$cleanupDart=@'
import 'dart:io';
import 'package:test/test.dart';
void main() {
  test('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER cleanup', () {
    Error.throwWithStackTrace(
      const FileSystemException('Deletion failed', 'C:/SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER/private', OSError('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER', 32)),
      StackTrace.fromString('#0 cleanup (FIXTURE_CLEANUP_URI:FIXTURE_CLEANUP_LINE:1)\n#1 private (file:///C:/SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER/private.dart:9:2)'));
  });
}
'@
[IO.File]::WriteAllText($cleanupProbe,$cleanupDart.Replace('FIXTURE_CLEANUP_URI',$cleanupUri).Replace('FIXTURE_CLEANUP_LINE',[string]$cleanupLine),[Text.UTF8Encoding]::new($false))
Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_windows')
try {
    & $FoundationDart test $cleanupProbe --file-reporter "json:$cleanupReport" *> (Join-Path $fixture 'controlled-cleanup.private.txt')
    if($LASTEXITCODE -eq 0){throw 'Controlled cleanup failure unexpectedly passed.'}
} finally {Pop-Location}
$rawCleanup=[IO.File]::ReadAllLines($cleanupReport)
foreach($variant in @('delete-5','delete-32','delete-33','delete-145','duplicate-frame',
    'unknown-code','zero-code','negative-code','oversize-code','wrong-operation','wrong-exception','prefixed-error','suffixed-error','nested-error',
    'unknown-name','name-type','invalid-declaration','changed-client','unknown-client-source','changed-cleanup',
    'unknown-cleanup-source','invalid-cleanup-line','unrelated-cleanup-line','unrelated-frame','wrong-phase')) {
    $caseFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($caseFixture)
    $events=foreach($line in $rawCleanup) {
        $event=$line|ConvertFrom-Json -AsHashtable
        if($event.type -ceq 'testStart' -and $event.test.name -ceq ($privateMarker+' cleanup')) {
            $event.test.name='actual format3 bootstrap and RPC client receipts'
            $event.test.url=$clientUri
            $event.test.line=65
            switch($variant) {
                'unknown-name' {$event.test.name+=$privateMarker}
                'name-type' {$event.test.name=@{private=$privateMarker}}
                'invalid-declaration' {$event.test.line=999999}
                'unknown-client-source' {$event.test.url='file:///C:/'+$privateMarker+'/private.dart'}
            }
        }
        if($event.type -ceq 'error') {
            if($event.error -cnotmatch "\AFileSystemException: Deletion failed, path = '[\s\S]*' \(OS Error: [\s\S]*, errno = 32\)\z") {
                throw 'Expected actual Dart deletion exception reporter shape.'
            }
            switch($variant) {
                'delete-5' {$event.error=$event.error.Replace('errno = 32)','errno = 5)')}
                'delete-33' {$event.error=$event.error.Replace('errno = 32)','errno = 33)')}
                'delete-145' {$event.error=$event.error.Replace('errno = 32)','errno = 145)')}
                'unknown-code' {$event.error=$event.error.Replace('errno = 32)','errno = 2)')}
                'zero-code' {$event.error=$event.error.Replace('errno = 32)','errno = 0)')}
                'negative-code' {$event.error=$event.error.Replace('errno = 32)','errno = -1)')}
                'oversize-code' {$event.error=$event.error.Replace('errno = 32)','errno = 4294967296)')}
                'wrong-operation' {$event.error=$event.error.Replace('Deletion failed','Cannot open file')}
                'wrong-exception' {$event.error=$event.error.Replace('FileSystemException','StateError')}
                'prefixed-error' {$event.error=$privateMarker+"`n"+$event.error}
                'suffixed-error' {$event.error+="`n"+$privateMarker}
                'nested-error' {$event.error="Expected: <0>`n  Actual: <1>`n"+$event.error}
                'duplicate-frame' {$event.stackTrace+="`n#2 cleanup (${cleanupUri}:${cleanupLine}:1)"}
                'unknown-cleanup-source' {$event.stackTrace="#0 private (file:///C:/${privateMarker}/private.dart:${cleanupLine}:1)"}
                'invalid-cleanup-line' {$event.stackTrace="#0 cleanup (${cleanupUri}:999999:1)"}
                'unrelated-cleanup-line' {$event.stackTrace="#0 cleanup (${cleanupUri}:1:1)"}
                'unrelated-frame' {$event.stackTrace="#0 unrelated (package:serverdeck_windows/native_attributes.dart:65:1)"}
            }
        }
        $event|ConvertTo-Json -Depth 30 -Compress
    }
    $phase=if($variant -ceq 'wrong-phase'){'serverdeck_locald-tests'}else{'serverdeck_windows-tests'}
    [IO.File]::WriteAllLines((Join-Path $caseFixture ($phase+'.machine.jsonl')),[string[]]$events,[Text.UTF8Encoding]::new($false))
    $selected=$snapshot
    if($variant -in @('changed-client','changed-cleanup')) {
        $changed=if($variant -ceq 'changed-client'){$clientSource}else{$cleanupSource}
        $selected=@{sha256=$snapshot.sha256;files=@($snapshot.files|ForEach-Object{
            if($_.file -ceq $changed){@{file=$changed;sha256=('0'*64)}}else{$_}
        })}
    }
    Write-NativeQualificationTestFailure -Directory $caseFixture -Phase $phase -SourceSnapshot $selected -ControlledFixture
    $casePath=Join-Path $caseFixture ('safe-test-failure-'+$phase+'.json')
    $caseProof=Read-NativeIsarArtifactJson $casePath
    $safe=[IO.File]::ReadAllText($casePath)
    if($caseProof.schemaVersion -ne 1 -or $caseProof.status -cne 'failed-test-details' -or -not $caseProof.controlledFixture -or
        -not $caseProof.reporterComplete -or $caseProof.failures.Count -ne 1 -or
        $safe.Contains($privateMarker) -or $safe.Contains('file:///') -or $safe.Contains('C:/') -or
        $safe.Contains('stackTrace') -or $safe.Contains('Deletion failed') -or $safe.Contains('OS Error:') -or
        $safe.Contains('999999') -or $safe.Contains('Expected:')) {throw 'Cleanup projection privacy/report mismatch.'}
    $failure=$caseProof.failures[0]
    $expectCleanup=$variant -in @('delete-5','delete-32','delete-33','delete-145','duplicate-frame')
    $expectExit=$variant -ceq 'nested-error'
    $expectCase=$variant -notin @('unknown-name','name-type','invalid-declaration','changed-client','unknown-client-source')
    if(($expectCase -and $failure.fixtureCase -cne 'trusted-client-receipts') -or
        (-not $expectCase -and $null -ne $failure.fixtureCase) -or
        ($expectExit -and $failure.fixtureExitCode -ne 1) -or
        (-not $expectExit -and $null -ne $failure.fixtureExitCode) -or
        $null -ne $failure.safeCode -or $null -ne $failure.fixturePhase) {throw ('Cleanup fixed metadata mismatch: '+$variant)}
    if($expectCleanup) {
        $expectedCode=switch($variant){'delete-5'{5L};'delete-33'{33L};'delete-145'{145L};default{32L}}
        if($failure.failureKind -cne 'fixture-cleanup' -or $failure.nativeErrors.Count -ne 1 -or
            $failure.nativeErrors[0].kind -cne 'WIN32_FIXTURE_DELETE' -or $failure.nativeErrors[0].code -ne $expectedCode) {
            throw ('Known fixture cleanup projection mismatch: '+$variant)
        }
    } elseif(($expectExit -and $failure.failureKind -cne 'fixture-exit') -or
        (-not $expectExit -and $null -ne $failure.failureKind) -or $failure.nativeErrors.Count -ne 0) {
        throw ('Unrelated cleanup exception was exported: '+$variant)
    }
    if($caseProof.fullAcceptance -or $caseProof.distributionReady -or $caseProof.activated){throw 'Controlled cleanup projection claimed qualification.'}
}
'QUALIFICATION_REAL_DELETE_EXCEPTION_KNOWN_WINDOWS_CODES_SOURCE_HASH_LINE_PHASE_CASE_AND_PRIVACY_NEGATIVES_PASSED'

# The native pipe watchdog emits one fixed phase. It is safe only at the
# checked test declaration and timeout callback, with an exact error shape.
$pipeSource='packages/serverdeck_windows/test/pipe_disconnected_test.dart'
$pipeUri=([Uri](Join-Path $NativeIsarRepository $pipeSource)).AbsoluteUri
$pipeLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $pipeSource))
$pipeTimeoutLine=@(for($index=0;$index -lt $pipeLines.Length;$index++) {
    if($pipeLines[$index].Trim() -ceq 'onTimeout: () => throw TimeoutException('){$index+1}
})
$pipeDeclaration=@(for($index=0;$index -lt $pipeLines.Length;$index++) {
    if($pipeLines[$index].TrimStart().StartsWith('test(')){$index+1}
})
if($pipeTimeoutLine.Count -ne 1 -or $pipeDeclaration.Count -ne 1){throw 'Expected one checked disconnected pipe timeout and test declaration.'}
$pipeTimeoutLine=$pipeTimeoutLine[0];$pipeDeclaration=$pipeDeclaration[0]
$pipeName='compiled disconnected pipe read after native disconnect fails promptly without waiting on an unissued event'
$pipeProbe=Join-Path $fixture 'controlled-pipe-timeout.dart'
$pipeReport=Join-Path $fixture 'controlled-pipe-timeout.machine.jsonl'
$pipeDart=@'
import 'dart:async';
import 'package:test/test.dart';
void main() {
  test('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER pipe timeout', () {
    Error.throwWithStackTrace(
      TimeoutException('DISCONNECT_FIXTURE_TIMEOUT:connected', const Duration(seconds: 15)),
      StackTrace.fromString('#0 timeout (FIXTURE_PIPE_URI:FIXTURE_PIPE_LINE:1)\n#1 private (file:///C:/SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER/private.dart:9:2)'));
  });
}
'@
[IO.File]::WriteAllText($pipeProbe,$pipeDart.Replace('FIXTURE_PIPE_URI',$pipeUri).Replace('FIXTURE_PIPE_LINE',[string]$pipeTimeoutLine),[Text.UTF8Encoding]::new($false))
Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_windows')
try {
    & $FoundationDart test $pipeProbe --file-reporter "json:$pipeReport" *> (Join-Path $fixture 'controlled-pipe-timeout.private.txt')
    if($LASTEXITCODE -eq 0){throw 'Controlled pipe timeout unexpectedly passed.'}
} finally {Pop-Location}
$rawPipe=[IO.File]::ReadAllLines($pipeReport)
$pipePhases=@('started','connected','disconnected','read-terminated','reuse-cancel-proved')
foreach($variant in ($pipePhases+@('unknown-phase','prefixed-error','suffixed-error','wrong-duration','wrong-error',
    'unknown-name','name-type','invalid-declaration','changed-source','unknown-source','unrelated-source',
    'invalid-frame','unrelated-frame','unknown-frame','missing-frame','wrong-phase'))) {
    $caseFixture=Join-Path $NativeIsarRepository ('.local/native-qualification-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($caseFixture)
    $events=foreach($line in $rawPipe) {
        $event=$line|ConvertFrom-Json -AsHashtable
        if($event.type -ceq 'testStart' -and $event.test.name -ceq ($privateMarker+' pipe timeout')) {
            $event.test.name=$pipeName
            $event.test.url=$pipeUri
            $event.test.line=$pipeDeclaration
            switch($variant) {
                'unknown-name' {$event.test.name+=$privateMarker}
                'name-type' {$event.test.name=@{private=$privateMarker}}
                'invalid-declaration' {$event.test.line=999999}
                'unknown-source' {$event.test.url='file:///C:/'+$privateMarker+'/private.dart'}
                'unrelated-source' {$event.test.url=$clientUri}
            }
        }
        if($event.type -ceq 'error') {
            if($event.error -cne 'TimeoutException after 0:00:15.000000: DISCONNECT_FIXTURE_TIMEOUT:connected') {
                throw 'Expected actual Dart pipe timeout reporter shape.'
            }
            if($variant -in $pipePhases){$event.error=$event.error.Replace(':connected',(':'+$variant))}
            switch($variant) {
                'unknown-phase' {$event.error=$event.error.Replace(':connected',(':'+$privateMarker))}
                'prefixed-error' {$event.error=$privateMarker+"`n"+$event.error}
                'suffixed-error' {$event.error+="`n"+$privateMarker}
                'wrong-duration' {$event.error=$event.error.Replace('0:00:15.000000','0:00:30.000000')}
                'wrong-error' {$event.error='Bad state: '+$event.error}
                'invalid-frame' {$event.stackTrace="#0 timeout (${pipeUri}:999999:1)"}
                'unrelated-frame' {$event.stackTrace="#0 timeout (${pipeUri}:1:1)"}
                'unknown-frame' {$event.stackTrace="#0 private (file:///C:/${privateMarker}/private.dart:${pipeTimeoutLine}:1)"}
                'missing-frame' {$event.stackTrace=$privateMarker}
            }
        }
        $event|ConvertTo-Json -Depth 30 -Compress
    }
    $phase=if($variant -ceq 'wrong-phase'){'serverdeck_locald-tests'}else{'serverdeck_windows-tests'}
    [IO.File]::WriteAllLines((Join-Path $caseFixture ($phase+'.machine.jsonl')),[string[]]$events,[Text.UTF8Encoding]::new($false))
    $selected=$snapshot
    if($variant -ceq 'changed-source') {
        $selected=@{sha256=$snapshot.sha256;files=@($snapshot.files|ForEach-Object{
            if($_.file -ceq $pipeSource){@{file=$pipeSource;sha256=('0'*64)}}else{$_}
        })}
    }
    Write-NativeQualificationTestFailure -Directory $caseFixture -Phase $phase -SourceSnapshot $selected -ControlledFixture
    $casePath=Join-Path $caseFixture ('safe-test-failure-'+$phase+'.json')
    $caseProof=Read-NativeIsarArtifactJson $casePath
    $safe=[IO.File]::ReadAllText($casePath)
    if($caseProof.schemaVersion -ne 1 -or $caseProof.status -cne 'failed-test-details' -or -not $caseProof.controlledFixture -or
        -not $caseProof.reporterComplete -or $caseProof.failures.Count -ne 1 -or
        $safe.Contains($privateMarker) -or $safe.Contains('file:///') -or $safe.Contains('C:/') -or
        $safe.Contains('stackTrace') -or $safe.Contains('DISCONNECT_FIXTURE_TIMEOUT:') -or $safe.Contains('999999')) {
        throw 'Pipe timeout projection privacy/report mismatch.'
    }
    $failure=$caseProof.failures[0]
    $expectPhase=$variant -in $pipePhases
    $expectCase=$variant -notin @('unknown-name','name-type','invalid-declaration','changed-source','unknown-source','unrelated-source',
        'invalid-frame','unrelated-frame','unknown-frame','missing-frame','wrong-phase')
    $expectTimeout=$variant -notin @('prefixed-error','wrong-error','invalid-declaration','changed-source','unknown-source')
    if(($expectPhase -and $failure.fixturePhase -cne $variant) -or
        (-not $expectPhase -and $null -ne $failure.fixturePhase) -or
        ($expectCase -and $failure.fixtureCase -cne 'pipe-disconnected') -or
        (-not $expectCase -and $null -ne $failure.fixtureCase) -or
        ($expectTimeout -and $failure.failureKind -cne 'timeout') -or
        (-not $expectTimeout -and $null -ne $failure.failureKind) -or
        $null -ne $failure.fixtureExitCode -or $null -ne $failure.safeCode -or $failure.nativeErrors.Count -ne 0) {
        throw ('Pipe fixed phase/source projection mismatch: '+$variant)
    }
    if($caseProof.fullAcceptance -or $caseProof.distributionReady -or $caseProof.activated){throw 'Controlled pipe projection claimed qualification.'}
}
'QUALIFICATION_REAL_PIPE_TIMEOUT_FIVE_FIXED_PHASES_SOURCE_HASH_LINE_CASE_SHAPE_AND_PRIVACY_NEGATIVES_PASSED'

# The generated groups are non-native failures. They confirm the actual
# reporter's hook name, declaration/URL and per-test print event association.
# Only their metadata is aliased to the checked bootstrap source contract.
$bootstrapProbe=Join-Path $fixture 'controlled-bootstrap.dart'
$bootstrapReport=Join-Path $fixture 'controlled-bootstrap.machine.jsonl'
[IO.File]::WriteAllText($bootstrapProbe,@'
import 'dart:async';
import 'package:test/test.dart';
void main() {
  group('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER preparation', () {
    setUpAll(() async {
      print('BOOTSTRAP_FIXTURE_PHASE:compile-owner');
      await Completer<void>().future.timeout(const Duration(milliseconds: 1));
    });
    test('body', () {});
  });
  group('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER behavior', () {
    test('body', () async {
      print('BOOTSTRAP_FIXTURE_PHASE:run-2');
      await Completer<void>().future.timeout(const Duration(milliseconds: 1));
    });
  });
}
'@,[Text.UTF8Encoding]::new($false))
Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_locald')
try {
    & $FoundationDart test $bootstrapProbe --file-reporter "json:$bootstrapReport" *> (Join-Path $fixture 'controlled-bootstrap.private.txt')
    if($LASTEXITCODE -eq 0){throw 'Controlled bootstrap failures unexpectedly passed.'}
} finally {Pop-Location}
$rawBootstrap=@([IO.File]::ReadAllLines($bootstrapReport)|ForEach-Object {$_|ConvertFrom-Json -AsHashtable})
Test-BootstrapDiagnosticProjection -Fixture $fixture -Snapshot $snapshot -RawBootstrap $rawBootstrap -PrivateMarker $privateMarker

# The real helper must preserve the assertion prefix for both a single error
# and a body/cleanup aggregate. The generated fixture has no native imports.
$gatewayProbe=Join-Path $fixture 'controlled-gateway-exit.dart'
$gatewayReport=Join-Path $fixture 'controlled-gateway-exit.machine.jsonl'
$gatewayHelperUri=([Uri](Join-Path $NativeIsarRepository 'packages/serverdeck_locald/test/support/gateway_fixture_cleanup.dart')).AbsoluteUri
$gatewayActorUri=([Uri](Join-Path $NativeIsarRepository 'packages/serverdeck_locald/test/support/gateway_actor.dart')).AbsoluteUri
$gatewayDart=@'
import 'package:test/test.dart';
import 'FIXTURE_GATEWAY_HELPER_URI';
Future<void> body() async {
  expect(1, 0, reason: 'SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER primary\n'
    '#0 actor (FIXTURE_GATEWAY_ACTOR_URI:40:1)\n'
    '#1 private (file:///C:/SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER/private.dart:9:2)');
}
void main() {
  test('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER gateway body', () async {
    await runGatewayFixture(body: body, cleanup: () async {});
  });
  test('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER gateway both', () async {
    await runGatewayFixture(body: body, cleanup: () async {
      Error.throwWithStackTrace(StateError('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER cleanup'),
        StackTrace.fromString('#0 secondary (FIXTURE_GATEWAY_ACTOR_URI:41:1)'));
    });
  });
}
'@
[IO.File]::WriteAllText($gatewayProbe,$gatewayDart.Replace('FIXTURE_GATEWAY_HELPER_URI',$gatewayHelperUri).Replace('FIXTURE_GATEWAY_ACTOR_URI',$gatewayActorUri),[Text.UTF8Encoding]::new($false))
Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_locald')
try {
    & $FoundationDart test $gatewayProbe --file-reporter "json:$gatewayReport" *> (Join-Path $fixture 'controlled-gateway-exit.private.txt')
    if($LASTEXITCODE -eq 0){throw 'Controlled gateway body/aggregate assertions unexpectedly passed.'}
} finally {Pop-Location}
$rawGateway=@([IO.File]::ReadAllLines($gatewayReport)|ForEach-Object {$_|ConvertFrom-Json -AsHashtable})
Test-GatewayExitDiagnosticProjection -Snapshot $snapshot -RawGateway $rawGateway -PrivateMarker $privateMarker

# Throw directly with the real Dart Duration55s shape; this generated probe
# does not wait55s, use native APIs or claim a capacity fixture execution.
$capacityProbe=Join-Path $fixture 'controlled-capacity-timeout.dart'
$capacityReport=Join-Path $fixture 'controlled-capacity-timeout.machine.jsonl'
[IO.File]::WriteAllText($capacityProbe,@'
import 'dart:async';
import 'package:test/test.dart';
void main() {
  test('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER capacity timeout', () {
    throw TimeoutException('TRUST_CAPACITY_FIXTURE_TIMEOUT:capacity-start', const Duration(seconds: 55));
  });
}
'@,[Text.UTF8Encoding]::new($false))
Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_locald')
try {
    & $FoundationDart test $capacityProbe --file-reporter "json:$capacityReport" *> (Join-Path $fixture 'controlled-capacity-timeout.private.txt')
    if($LASTEXITCODE -eq 0){throw 'Controlled capacity timeout unexpectedly passed.'}
} finally {Pop-Location}
$rawCapacity=@([IO.File]::ReadAllLines($capacityReport)|ForEach-Object {$_|ConvertFrom-Json -AsHashtable})
Test-CapacityPhaseDiagnosticProjection -Snapshot $snapshot -RawCapacity $rawCapacity -PrivateMarker $privateMarker

# Real generic lifecycle reporter shapes, with synthetic private reasons only.
# No pipe/native/process fixture is imported by this generated probe.
$ownedProbe=Join-Path $fixture 'controlled-owned-fixture.dart'
$ownedReport=Join-Path $fixture 'controlled-owned-fixture.machine.jsonl'
$ownedHelperUri=([Uri](Join-Path $NativeIsarRepository 'packages/serverdeck_windows/test/support/trusted_client_fixture.dart')).AbsoluteUri
$ownedActorUri=([Uri](Join-Path $NativeIsarRepository 'packages/serverdeck_windows/test/support/trusted_client_actor.dart')).AbsoluteUri
$ownedDart=@'
import 'package:test/test.dart';
import 'FIXTURE_OWNED_HELPER_URI';
Future<void> body() async {
  expect(1, 0, reason: 'TRUSTED_CLIENT_FIXTURE_FAILURE:prepare:SERVICE_UNAVAILABLE\n'
    'SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER\n#0 actor (FIXTURE_OWNED_ACTOR_URI:40:1)');
}
void main() {
  test('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER owned body', () async {
    await runOwnedFixtureLifecycle(body: body, cleanup: () async {});
  });
  test('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER owned both', () async {
    await runOwnedFixtureLifecycle(body: body, cleanup: () async {
      Error.throwWithStackTrace(StateError('SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER cleanup'),
        StackTrace.fromString('#0 secondary (FIXTURE_OWNED_ACTOR_URI:41:1)'));
    });
  });
}
'@
[IO.File]::WriteAllText($ownedProbe,$ownedDart.Replace('FIXTURE_OWNED_HELPER_URI',$ownedHelperUri).Replace('FIXTURE_OWNED_ACTOR_URI',$ownedActorUri),[Text.UTF8Encoding]::new($false))
Push-Location (Join-Path $NativeIsarRepository 'packages/serverdeck_windows')
try {
    & $FoundationDart test $ownedProbe --file-reporter "json:$ownedReport" *> (Join-Path $fixture 'controlled-owned-fixture.private.txt')
    if($LASTEXITCODE -eq 0){throw 'Controlled owned fixture assertions unexpectedly passed.'}
} finally {Pop-Location}
$rawOwned=@([IO.File]::ReadAllLines($ownedReport)|ForEach-Object {$_|ConvertFrom-Json -AsHashtable})
Test-TrustedClientFailureDiagnosticProjection -Snapshot $snapshot -RawOwned $rawOwned -PrivateMarker $privateMarker
Test-TrustedAuthDiagnosticProjection -Snapshot $snapshot -RawOwned $rawOwned -PrivateMarker $privateMarker
$fixture
$invalidFixture
exit 0
