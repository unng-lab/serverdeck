. "$PSScriptRoot/native-artifact-source-snapshot.ps1"
. "$PSScriptRoot/native-isar-artifact-inputs.ps1"

function Get-NativeBootstrapDiagnosticShape {
    param([string[]]$BootstrapLines,[string[]]$PreparationLines)
    # This is a deliberately fixed source contract, not a parser for arbitrary
    # print statements. Its callers must also check both snapshot file hashes.
    $producer=@'
enum BootstrapFixturePhase {
  prepareStart('prepare-start'),
  compileOwner('compile-owner'),
  compileClient('compile-client'),
  selectNative('select-native'),
  manifest('manifest'),
  prepared('prepared'),
  behaviorStart('behavior-start'),
  namespaceCheck('namespace-check'),
  run0('run-0'),
  run1('run-1'),
  run2('run-2'),
  run3('run-3'),
  run4('run-4'),
  run5('run-5'),
  refusalChecks('refusal-checks'),
  cleanup('cleanup'),
  complete('complete');

  const BootstrapFixturePhase(this.identifier);

  final String identifier;
}

void bootstrapFixturePhase(BootstrapFixturePhase phase) {
  print('BOOTSTRAP_FIXTURE_PHASE:${phase.identifier}');
}
'@
    $checkedProducer=($producer -split '\r?\n'|ForEach-Object {$_.Trim()}) -join "`n"
    $preparation=($PreparationLines|ForEach-Object {$_.Trim()}) -join "`n"
    $preparationCode=($PreparationLines|Where-Object {-not $_.TrimStart().StartsWith('//')}|ForEach-Object {$_.Trim()}) -join "`n"
    if(-not $preparationCode.Contains($checkedProducer) -or
        [regex]::Matches($preparation,'(?m)^enum BootstrapFixturePhase \{\r?$').Count -ne 1 -or
        [regex]::Matches($preparation,'(?m)^void bootstrapFixturePhase\(BootstrapFixturePhase phase\) \{\r?$').Count -ne 1 -or
        [regex]::Matches($preparation,'BOOTSTRAP_FIXTURE_PHASE:').Count -ne 1){return $null}
    $group=@();$hook=@();$body=@()
    for($index=0;$index -lt $BootstrapLines.Length;$index++) {
        $text=$BootstrapLines[$index].Trim()
        if($text -ceq "group('compiled bootstrap', () {"){$group+=$index+1}
        if($text -ceq 'setUpAll(() async {' -and $index+1 -lt $BootstrapLines.Length -and
            $BootstrapLines[$index+1].Trim() -ceq 'prepared = await PreparedBootstrapFixture.prepare();'){$hook+=$index+1}
        if($text -ceq 'test(' -and $index+3 -lt $BootstrapLines.Length -and
            $BootstrapLines[$index+1].Trim() -ceq "'compiled owner authenticates, becomes ready, closes and reopens workspace'," -and
            $BootstrapLines[$index+2].Trim() -ceq '() async {' -and
            $BootstrapLines[$index+3].Trim() -ceq 'bootstrapFixturePhase(BootstrapFixturePhase.behaviorStart);'){$body+=$index+1}
    }
    if($group.Count -ne 1 -or $hook.Count -ne 1 -or $body.Count -ne 1 -or
        $group[0] -ge $hook[0] -or $hook[0] -ge $body[0]){return $null}
    return @{hookLine=$hook[0];bodyLine=$body[0]}
}

function Write-NativeQualificationTestFailure {
    param([Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][ValidateSet('root-tests','serverdeck_protocol-tests','serverdeck_windows-tests','serverdeck_locald-tests')][string]$Phase,
        [Parameter(Mandatory)]$SourceSnapshot,
        [switch]$ControlledFixture)
    $Directory=[IO.Path]::GetFullPath($Directory)
    if([IO.Path]::GetDirectoryName($Directory) -cne (Join-Path $NativeIsarRepository '.local') -or
        [IO.Path]::GetFileName($Directory) -cnotmatch '^native-qualification-[a-f0-9]{32}$'){
        throw 'Expected owned qualification diagnostics directory.'
    }
    Assert-NativeIsarPlainPath $Directory
    $artifactHash=$null
    if(-not $ControlledFixture){
        $context=Read-NativeIsarArtifactJson (Join-Path $Directory 'context.json')
        if($context.sourceSnapshotSha256 -cne $SourceSnapshot.sha256 -or
            $context.artifactManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'Qualification diagnostics context mismatch.'
        }
        $artifactHash=$context.artifactManifestSha256
    }
    $known=@{}
    foreach($file in $SourceSnapshot.files){if($file.file.EndsWith('.dart')){$known[$file.file]=@{hash=$file.sha256;file=$file.file}}}
    $packageRoot=if($Phase -ceq 'root-tests'){$NativeIsarRepository}else{Join-Path $NativeIsarRepository ('packages/'+$Phase.Replace('-tests',''))}
    function Resolve-DiagnosticSource([string]$Location){
        if(-not $Location){return $null}
        $relative=$null
        if($Location -cmatch '^package:(serverdeck(?:_protocol|_windows|_locald)?)/(.+)$'){
            $relative=if($Matches[1] -ceq 'serverdeck'){'lib/'+$Matches[2]}else{'packages/'+$Matches[1]+'/lib/'+$Matches[2]}
        } else {
            try {
                $uri=$null
                if([Uri]::TryCreate($Location,[UriKind]::Absolute,[ref]$uri) -and $uri.IsFile){$absolute=$uri.LocalPath}
                elseif($Location.Contains('://')){return $null}
                else {$absolute=[IO.Path]::GetFullPath($Location,$packageRoot)}
                $relative=[IO.Path]::GetRelativePath($NativeIsarRepository,$absolute).Replace('\','/')
            } catch {return $null}
        }
        if($known.ContainsKey($relative)){return $known[$relative].file}
        return $null
    }
    function Get-DiagnosticLine([string]$File,$Line){
        if(-not $File -or $Line -isnot [ValueType]){return $null}
        $number=[long]$Line
        $path=Join-Path $NativeIsarRepository $File
        if((Get-NativeIsarDigest $path) -cne $known[$File].hash){return $null}
        $lineCount=[IO.File]::ReadAllLines($path).Length
        if($number -lt 1 -or $number -gt $lineCount){return $null}
        return $number
    }
    $report=Join-Path $Directory ($Phase+'.machine.jsonl')
    # Fixed public fixture identifiers only; never export arbitrary test names.
    $operationalCases=@(
        'good','empty','stale','revoked','reservation','reservation-race','grant-basic',
        'foundation-settings','foundation-delete','foundation-active','foundation-unknown','foundation-queue','foundation-capacity',
        'coordinator-basic','coordinator-reservation','coordinator-running','coordinator-active','coordinator-unknown',
        'grant-empty','grant-count','grant-receipts','grant-id-limit','grant-receipt-id-limit',
        'grant-key-closed-admission','grant-key-closed-queued','grant-capacity','grant-corrupt-afterCommit','grant-probe-disabled',
        'grant-pointer-disabled','grant-pointer-corrupt-readback',
        'manifest-malformed','manifest-foreign','manifest-schema1','native-schema1','bundle','wrapper','creating','upgrading',
        'acl-product','acl-version','acl-parent','acl-active','acl-database','acl-lock','junction','link-database','link-lock',
        'closed-key','closed-lease','close-false','open-throw','wrong-schema','bad-graph','bad-native-id','second-corrupt','second-lookup'
    )
    foreach($point in @('beforeStage','afterStage','beforeTransaction','afterGrantWrite','afterReceiptWrite','afterCommit','beforePublication','afterPublication','beforeAcknowledgement')) {
        $operationalCases+='grant-fault-'+$point
    }
    foreach($operation in @('create','replace','revoke')) {
        foreach($point in @('afterPending','afterRename','afterReadback')) {
            $operationalCases+='grant-pointer-throw-'+$operation+'-'+$point
        }
    }
    $gatewayCases=@('basic','quota','queued-cancel','heartbeat','heartbeat-remote-limit','wrong-catalog','wrong-poll','wrong-cancel',
        'rpc-timeout','rpc-remote','overall','cancel-timeout','missing-grant','owner-deny','pending','cancel-ack','native-loss',
        'expiry','revoke','stdout-revoke','stdout-target-change','stdout-target-failure','stdout-stop','writer-cancel','publish-order','publish-expiry','eof')
    $trustedClientCases=@('owner','cleanup2','cleanup3','mcp','grant','grant-bad-proof','grant-repeat','codes','quota','receipts',
        'connection','bad-connection','bad-connect','bad-connect-status','bad-connect-cancel','bad-disconnect',
        'readiness2','bad-receipt','bad-retry','unknown-code','bad-field','wrong-id','wrong-generation','oversize',
        'invalid-json','timeout','eof','duplicate','single-use','wrong-token','bad-proof','hello-role','hello-generation',
        'hello-build','hello-version','hello-shape','bootstrap-timeout')
    $trustProbeCases=@('basic','reservation','quota','role','foreign','cancel','close','retention','gate','success',
        'success-cancel','success-ttl','success-other','success-write-basic','success-write-replay','success-write-cancel',
        'success-write-ttl','success-write-cas','success-write-foreign','success-write-duplicate','success-write-reservation',
        'success-write-role','success-write-quota','success-write-capacity','success-write-blocked','success-write-retired',
        'success-write-drain','success-write-clock','success-write-retired-admission','success-stale','success-deadline',
        'admission-clock','reserved-cancel','physical-cancel','physical-detach','physical-stale')
    $bootstrapSource='packages/serverdeck_locald/test/bootstrap_native_test.dart'
    $bootstrapPreparation='packages/serverdeck_locald/test/support/bootstrap_preparation.dart'
    $bootstrapShape=$null;$bootstrapStarts=0;$bootstrapStates=@{}
    function Get-BootstrapDiagnosticCase($Test) {
        if(-not $bootstrapShape -or -not $Test -or $Test['name'] -isnot [string] -or
            $Test['url'] -isnot [string] -or
            ($Test['id'] -isnot [int] -and $Test['id'] -isnot [long]) -or $Test['id'] -lt 0 -or
            ($Test['suiteID'] -isnot [int] -and $Test['suiteID'] -isnot [long]) -or
            (Resolve-DiagnosticSource $Test['url']) -cne $bootstrapSource -or
            $suites[[string]$Test['suiteID']] -cne $bootstrapSource){return $null}
        if($Test['name'] -ceq 'compiled bootstrap compiled owner authenticates, becomes ready, closes and reopens workspace' -and
            ($Test['line'] -is [int] -or $Test['line'] -is [long]) -and $Test['line'] -eq $bootstrapShape.bodyLine) {
            return 'bootstrap-body'
        }
        # Some runners synthesize this hook without a declaration line. Keep
        # that null; the checked hook, producer, URL and suite supply identity.
        if($Test['name'] -ceq 'compiled bootstrap (setUpAll)' -and
            ($null -eq $Test['line'] -or
                (($Test['line'] -is [int] -or $Test['line'] -is [long]) -and $Test['line'] -eq $bootstrapShape.hookLine))) {
            return 'bootstrap-prepare'
        }
        return $null
    }
    $tests=@{};$suites=@{};$failures=[Collections.Generic.List[object]]::new()
    $complete=$false;$status='missing-reporter'
    try {
        if($Phase -ceq 'serverdeck_locald-tests' -and $known.ContainsKey($bootstrapSource) -and $known.ContainsKey($bootstrapPreparation) -and
            (Get-NativeIsarDigest (Join-Path $NativeIsarRepository $bootstrapSource)) -ceq $known[$bootstrapSource].hash -and
            (Get-NativeIsarDigest (Join-Path $NativeIsarRepository $bootstrapPreparation)) -ceq $known[$bootstrapPreparation].hash) {
            $bootstrapShape=Get-NativeBootstrapDiagnosticShape -BootstrapLines ([IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $bootstrapSource))) `
                -PreparationLines ([IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $bootstrapPreparation)))
        }
        Assert-NativeIsarPlainPath $report
        $stream=[IO.File]::Open($report,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        try {
            if($stream.Length -gt 16MB){throw 'Reporter exceeds bound.'}
            $reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$true,1024,$true)
            try {
                while($null -ne ($line=$reader.ReadLine())){
                    if($line.Length -gt 256KB){throw 'Reporter event exceeds bound.'}
                    $event=$line|ConvertFrom-Json -AsHashtable -ErrorAction Stop
                    switch($event.type){
                        'suite' {$suites[[string]$event.suite.id]=Resolve-DiagnosticSource $event.suite.path}
                        'testStart' {
                            $key=[string]$event.test.id
                            $tests[$key]=$event.test
                            if($bootstrapStates.ContainsKey($key)){$bootstrapStates[$key].valid=$false}
                            $bootstrapCase=Get-BootstrapDiagnosticCase $event.test
                            if($bootstrapCase) {
                                # Two IDs are expected. A small explicit replay cap
                                # prevents print-derived state from growing freely.
                                $bootstrapStarts++
                                if($bootstrapStarts -gt 32){throw 'Bootstrap reporter test IDs exceed bound.'}
                                if(-not $bootstrapStates.ContainsKey($key)) {
                                    $bootstrapStates[$key]=@{case=$bootstrapCase;phase=$null;valid=$true}
                                }
                            }
                        }
                        'print' {
                            if($event.type -is [string] -and $event.type -ceq 'print' -and
                                ($event.testID -is [int] -or $event.testID -is [long]) -and
                                $event.messageType -is [string] -and $event.messageType -ceq 'print' -and
                                $event.message -is [string] -and
                                $event.message -cmatch '\ABOOTSTRAP_FIXTURE_PHASE:(prepare-start|compile-owner|compile-client|select-native|manifest|prepared|behavior-start|namespace-check|run-0|run-1|run-2|run-3|run-4|run-5|refusal-checks|cleanup|complete)\z') {
                                $key=[string]$event.testID
                                if($bootstrapStates.ContainsKey($key) -and $bootstrapStates[$key].valid) {
                                    $bootstrapStates[$key].phase=$Matches[1]
                                }
                            }
                        }
                        'error' {
                            if($failures.Count -ge 128){throw 'Reporter failures exceed bound.'}
                            $test=$tests[[string]$event.testID]
                            $file=$null;$declarationLine=$null
                            if($test){
                                $file=Resolve-DiagnosticSource $test['url']
                                if(-not $file){$file=$suites[[string]$test['suiteID']]}
                                $declarationLine=Get-DiagnosticLine $file $test['line']
                            }
                            $frames=[Collections.Generic.List[object]]::new()
                            $frameKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                            # Child stacks may be nested in expect's reason. Apply the
                            # same source/hash/line checks and one total bound to both.
                            foreach($trace in @($event.stackTrace,$event.error)) {
                                foreach($frame in [regex]::Matches([string]$trace,'(?m)(?<uri>package:[A-Za-z0-9_]+/[^\s():]+|file:///[^\s()]+?|^[^\s():]+\.dart)(?::|\s+)(?<line>[0-9]+):(?<column>[0-9]+)')){
                                    $frameFile=Resolve-DiagnosticSource $frame.Groups['uri'].Value
                                    $frameLine=Get-DiagnosticLine $frameFile ([long]$frame.Groups['line'].Value)
                                    if($frameFile -and $frameLine -and $frameKeys.Add($frameFile+':'+$frameLine)){
                                        $frames.Add(@{file=$frameFile;line=$frameLine})
                                        if($frames.Count -eq 3){break}
                                    }
                                }
                                if($frames.Count -eq 3){break}
                            }
                            $native=[Collections.Generic.List[object]]::new()
                            foreach($match in [regex]::Matches([string]$event.error,'OS Error: (?<kind>NT_ATTRIBUTES_STATUS|WIN32_DRIVE_TYPE|WIN32_REPARSE_POINT), errno = (?<code>-?[0-9]{1,10})')){
                                $code=[long]$match.Groups['code'].Value
                                if($code -ge -2147483648 -and $code -le 4294967295){$native.Add(@{kind=$match.Groups['kind'].Value;code=$code});if($native.Count -eq 3){break}}
                            }
                            $safeCode=$null
                            if([string]$event.error -cmatch '^Bad state: (IDENTITY_UNAVAILABLE|PROTECTION_UNAVAILABLE|SECURITY_UNAVAILABLE|UNSAFE_PATH|RESOURCE_LIMIT|SERVICE_UNAVAILABLE|INTERNAL|WORKSPACE_CHILD_FAILED|WORKSPACE_CHILD_TIMEOUT)$'){$safeCode=$Matches[1]}
                            $fixtureCase=$null;$failureKind=$null;$fixtureExitCode=$null;$fixturePhase=$null
                            $bootstrapCase=Get-BootstrapDiagnosticCase $test
                            $key=[string]$event.testID
                            if(($event.testID -is [int] -or $event.testID -is [long]) -and $bootstrapCase -and
                                $bootstrapStates.ContainsKey($key) -and $bootstrapStates[$key].valid -and
                                $bootstrapStates[$key].case -ceq $bootstrapCase) {
                                $fixtureCase=$bootstrapCase
                                $fixturePhase=$bootstrapStates[$key].phase
                            }
                            if($declarationLine) {
                                if([string]$event.error -cmatch '^TimeoutException(?: after [0-9]{1,3}:[0-5][0-9]:[0-5][0-9]\.[0-9]{6})?:') {
                                    $failureKind='timeout'
                                }
                                if($file -ceq 'packages/serverdeck_locald/test/storage/operational_open_native_test.dart') {
                                    foreach($case in $operationalCases) {
                                        if($test['name'] -is [string] -and
                                            $test['name'] -ceq ('compiled operational snapshot actual owned operational native open '+$case)) {
                                            $fixtureCase=$case
                                            break
                                        }
                                    }
                                }
                                if($file -ceq 'packages/serverdeck_locald/test/storage/native_commit_capacity_test.dart') {
                                    foreach($case in @('async','sync')) {
                                        if($test['name'] -is [string] -and $test['name'] -ceq ('actual native commit-time capacity preserves process and recovery '+$case)) {
                                            $fixtureCase='commit-capacity-'+$case
                                            break
                                        }
                                    }
                                }
                                if($file -ceq 'packages/serverdeck_locald/test/mcp/gateway_native_test.dart') {
                                    foreach($case in $gatewayCases) {
                                        if($test['name'] -is [string] -and $test['name'] -ceq ('actual native MCP gateway '+$case)) {
                                            $fixtureCase='gateway-'+$case
                                            break
                                        }
                                    }
                                }
                                if($file -ceq 'packages/serverdeck_windows/test/trusted_client_native_test.dart') {
                                    foreach($case in $trustedClientCases) {
                                        if($test['name'] -is [string] -and $test['name'] -ceq ('actual format3 bootstrap and RPC client '+$case)) {
                                            $fixtureCase='trusted-client-'+$case
                                            break
                                        }
                                    }
                                }
                                if($Phase -ceq 'serverdeck_locald-tests' -and
                                    $file -ceq 'packages/serverdeck_locald/test/mcp/trust_probes_native_test.dart' -and
                                    $test['url'] -is [string] -and (Resolve-DiagnosticSource $test['url']) -ceq $file -and
                                    ($test['line'] -is [int] -or $test['line'] -is [long])) {
                                    $trustLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $file))
                                    $index=[int]$declarationLine-1
                                    if($index+1 -lt $trustLines.Length -and $trustLines[$index].Trim() -ceq 'test(' -and
                                        $trustLines[$index+1].Trim() -ceq "'actual native host trust probes `$mode',") {
                                        foreach($case in $trustProbeCases) {
                                            if($test['name'] -is [string] -and $test['name'] -ceq ('actual native host trust probes '+$case)) {
                                                $fixtureCase='trust-probe-'+$case
                                                break
                                            }
                                        }
                                    }
                                }
                                if($Phase -ceq 'serverdeck_windows-tests' -and
                                    $file -ceq 'packages/serverdeck_windows/test/pipe_disconnected_test.dart' -and
                                    $test['name'] -is [string] -and
                                    $test['name'] -ceq 'compiled disconnected pipe read after native disconnect fails promptly without waiting on an unissued event') {
                                    foreach($frame in $frames) {
                                        if($frame.file -cne $file){continue}
                                        $pipeLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $file))
                                        if($pipeLines[[int]$frame.line-1].Trim() -ceq 'onTimeout: () => throw TimeoutException(') {
                                            $fixtureCase='pipe-disconnected'
                                            if([string]$event.error -cmatch '\ATimeoutException after 0:00:15\.000000: DISCONNECT_FIXTURE_TIMEOUT:(started|connected|disconnected|read-terminated|reuse-cancel-proved)\z') {
                                                $fixturePhase=$Matches[1]
                                            }
                                            break
                                        }
                                    }
                                }
                            }
                            # Only the known client's first numeric exit assertion is
                            # projected. A nonzero exit is evidence, not a crash cause.
                            if($fixtureCase -clike 'trusted-client-*' -and
                                [string]$event.error -cmatch '\AExpected: <0>\r?\n[ \t]*Actual: <(?<exit>-?[0-9]{1,10})>\r?\n') {
                                $candidateExit=[long]$Matches['exit']
                                if($candidateExit -ne 0 -and $candidateExit -ge -2147483648 -and $candidateExit -le 4294967295) {
                                    $fixtureExitCode=$candidateExit
                                    $failureKind='fixture-exit'
                                }
                            }
                            # A cleanup exception can mask the actor outcome. Export
                            # only fixed Windows delete codes from the known owned
                            # fixture's checked delete statement, never its path or
                            # OS message. Other FileSystemExceptions stay private.
                            if($Phase -ceq 'serverdeck_windows-tests' -and $fixtureCase -clike 'trusted-client-*' -and
                                [string]$event.error -cmatch "\AFileSystemException: Deletion failed, path = '[\s\S]*' \(OS Error: [\s\S]*, errno = (?<errno>[0-9]{1,3})\)\z") {
                                $deleteCode=[long]$Matches['errno']
                                if($deleteCode -in @(5L,32L,33L,145L)) {
                                    foreach($frame in $frames) {
                                        $oldCleanup=$frame.file -ceq 'packages/serverdeck_windows/test/mcp_build_bundle_test.dart'
                                        $ownedCleanup=$frame.file -ceq 'packages/serverdeck_windows/test/support/owned_fixture_cleanup.dart'
                                        if(-not $oldCleanup -and -not $ownedCleanup){continue}
                                        $cleanupLines=[IO.File]::ReadAllLines((Join-Path $NativeIsarRepository $frame.file))
                                        $index=[int]$frame.line-1
                                        $checkedOldDelete=$oldCleanup -and $index -gt 0 -and
                                            $cleanupLines[$index].Trim() -ceq 'root.deleteSync(recursive: true);' -and
                                            $cleanupLines[$index-1].Trim() -ceq 'ownRoot(path);'
                                        $checkedOwnedDelete=$ownedCleanup -and $index -gt 1 -and
                                            $cleanupLines[$index].Trim() -ceq 'checkedDirectory.deleteSync(recursive: true);' -and
                                            $cleanupLines[$index-1].Trim() -ceq 'try {' -and
                                            $cleanupLines[$index-2].Trim() -ceq 'final checkedDirectory = _checkedOwnedFixtureDirectory(directory);'
                                        if($checkedOldDelete -or $checkedOwnedDelete) {
                                            if($native.Count -lt 3) {
                                                $native.Add(@{kind='WIN32_FIXTURE_DELETE';code=$deleteCode})
                                                $failureKind='fixture-cleanup'
                                            }
                                            break
                                        }
                                    }
                                }
                            }
                            # Names, messages, raw stack, stdout and private paths never enter proof.
                            $failures.Add(@{testFile=$file;declarationLine=$declarationLine;sourceFrames=@($frames.ToArray());nativeErrors=@($native.ToArray());safeCode=$safeCode;fixtureCase=$fixtureCase;failureKind=$failureKind;fixtureExitCode=$fixtureExitCode;fixturePhase=$fixturePhase})
                        }
                        'done' {$complete=$event.success -eq $false}
                    }
                }
            } finally {$reader.Dispose()}
        } finally {$stream.Dispose()}
        $status=if($complete){'failed-test-details'}else{'incomplete-reporter'}
    } catch {
        # Parser/IO details can contain private data. Export only the fixed status.
        $status='unavailable-reporter';$complete=$false;$failures.Clear()
    }
    Write-NativeIsarJson (Join-Path $Directory ('safe-test-failure-'+$Phase+'.json')) ([ordered]@{
        schemaVersion=1;kind='qualification-test-failure';phase=$Phase;status=$status
        sourceSnapshotSha256=$SourceSnapshot.sha256;artifactManifestSha256=$artifactHash
        controlledFixture=[bool]$ControlledFixture;reporterComplete=$complete
        failures=@($failures.ToArray());fullAcceptance=$false;distributionReady=$false;activated=$false
    })
}
