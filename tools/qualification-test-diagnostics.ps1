. "$PSScriptRoot/native-artifact-source-snapshot.ps1"
. "$PSScriptRoot/native-isar-artifact-inputs.ps1"

function Get-NativeDiagnosticCodeFingerprint {
    param([string[]]$Lines)
    # Extra fixed-source contract, in addition to the current inventory byte
    # hashes. Code changes fail closed; comments, indentation and CRLF do not
    # tie the known producer to a particular checkout's line-ending settings.
    # These checked files have no multiline literals. Refuse their addition
    # rather than normalizing potentially meaningful literal whitespace.
    $source=$Lines -join "`n"
    if($source.Contains("'''") -or $source.Contains('"""')){return $null}
    $code=($Lines|Where-Object {$_.Trim() -and -not $_.TrimStart().StartsWith('//')}|ForEach-Object {$_.Trim()}) -join "`n"
    $digest=[Security.Cryptography.SHA256]::Create()
    try {return [BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes($code))).Replace('-','').ToLowerInvariant()}
    finally {$digest.Dispose()}
}

function Get-NativeTrustedClientDiagnosticShape {
    param([string[]]$ParentLines,[string[]]$ActorLines,[string[]]$FixtureLines,[string[]]$CompletionLines)
    if((Get-NativeDiagnosticCodeFingerprint $ParentLines) -cne '80aab3c3b3ecd3fed8944b086aaf02fb45ea9896444132dd8f6a99b9a5f03cef' -or
        (Get-NativeDiagnosticCodeFingerprint $ActorLines) -cne '6c5ddcaeacc9d77405c8104bbb1005492754d1ce8ecb4892818f12fda7900feb' -or
        (Get-NativeDiagnosticCodeFingerprint $FixtureLines) -cne '1a22ecd7326c3856c80a3ff1970da3d89edb566d7e11f2189d03c3356dc9f695' -or
        (Get-NativeDiagnosticCodeFingerprint $CompletionLines) -cne '985e887321bf0e5975095799f0b70b05f9c611e65ba1e8763c2c26b7336d454f'){return $null}
    $declaration=@();$producer=@()
    for($index=0;$index+1 -lt $ParentLines.Length;$index++) {
        if($ParentLines[$index].Trim() -ceq 'test(' -and $ParentLines[$index+1].Trim() -ceq "'actual format3 bootstrap and RPC client `$mode',"){$declaration+=$index+1}
        if($ParentLines[$index].Trim() -ceq 'expect(' -and $ParentLines[$index+1].Trim() -ceq 'childExit,'){$producer+=$index+1}
    }
    if($declaration.Count -ne 1 -or $producer.Count -ne 1 -or $declaration[0] -ge $producer[0]){return $null}
    return @{declarationLine=$declaration[0];producerLines=@($producer[0],($producer[0]+1))}
}

function Get-NativeTrustedAuthDiagnosticShape {
    param([string[]]$ParentLines,[string[]]$ActorLines,[string[]]$FixtureLines,[string[]]$StartupLines)
    if((Get-NativeDiagnosticCodeFingerprint $ParentLines) -cne '1da69613ff61bf2280857b7c5347b90d3beaa7ff6949fd45eed7ce78bbf4a854' -or
        (Get-NativeDiagnosticCodeFingerprint $ActorLines) -cne '928ab1265aa26e955172a31bbba0a1ac947f6220477f5035bf7682978328af2c' -or
        (Get-NativeDiagnosticCodeFingerprint $FixtureLines) -cne '1a22ecd7326c3856c80a3ff1970da3d89edb566d7e11f2189d03c3356dc9f695' -or
        (Get-NativeDiagnosticCodeFingerprint $StartupLines) -cne 'ffca4f75f11cfe1cdf52700b734d1e67ef3e355a1feb1cd2ee1215f0266f4419'){return $null}
    $declaration=@();$producer=@();$end=@()
    for($index=0;$index+1 -lt $ParentLines.Length;$index++) {
        if($ParentLines[$index].Trim() -ceq 'test(' -and $ParentLines[$index+1].Trim() -ceq "'actual format3 API1.1 bootstrap and session `$scenario',"){$declaration+=$index+1}
        if($ParentLines[$index].Trim() -ceq 'expect(' -and $ParentLines[$index+1].Trim() -ceq 'await child.exitCode.timeout(const Duration(seconds: 70)),'){$producer+=$index+1}
        if($ParentLines[$index].Trim() -ceq 'timeout: const Timeout(Duration(seconds: 90)),'){$end+=$index+1}
    }
    if($declaration.Count -ne 1 -or $producer.Count -ne 1 -or $end.Count -ne 1 -or $declaration[0] -ge $producer[0] -or $producer[0] -ge $end[0]){return $null}
    return @{declarationLine=$declaration[0];producerLines=@($producer[0],($producer[0]+1));endLine=$end[0]}
}

function Get-NativeCapacityDiagnosticShape {
    param([string[]]$ParentLines,[string[]]$HelperLines,[string[]]$WriterLines)
    $phases=@('capacity-start','capacity-reader-ready')+@(0..20|ForEach-Object {'capacity-prefill-'+($_*1000)})+@(
        'capacity-full','capacity-confirm-refused','capacity-reader-released','capacity-recovery-confirm','capacity-recovered',
        'capacity-replay-verified','capacity-revoke-verified','capacity-complete')
    $parent=($ParentLines|Where-Object {$_.Trim() -and -not $_.TrimStart().StartsWith('//')}|ForEach-Object {$_.Trim()}) -join "`n"
    $helper=($HelperLines|Where-Object {$_.Trim() -and -not $_.TrimStart().StartsWith('//')}|ForEach-Object {$_.Trim()}) -join "`n"
    $writer=($WriterLines|Where-Object {$_.Trim() -and -not $_.TrimStart().StartsWith('//')}|ForEach-Object {$_.Trim()}) -join "`n"
    $producer=@'
await child.exitCode.timeout(
  const Duration(seconds: 55),
  onTimeout: mode == 'success-write-capacity'
      ? () {
          final phase = readCapacityFixturePhase(fixture.path);
          throw TimeoutException(
            'TRUST_CAPACITY_FIXTURE_TIMEOUT:$phase',
            const Duration(seconds: 55),
          );
        }
      : null,
),
'@
    $checkedProducer=($producer -split '\r?\n'|ForEach-Object {$_.Trim()}) -join "`n"
    $fileContract=@'
File _phaseFile(String root) =>
    File('$root${Platform.pathSeparator}$capacityFixturePhaseFileName');
void writeCapacityFixturePhase(String root, String phase) {
  final checked = capacityFixturePhaseTokens.contains(phase)
      ? phase
      : capacityFixtureUnknownPhase;
  try {
    _phaseFile(root)
        .writeAsStringSync('$checked\n', encoding: ascii, flush: true);
  } catch (_) {
  }
}
String readCapacityFixturePhase(String root) {
  try {
    final input = _phaseFile(root).openSync();
    try {
      if (input.lengthSync() > 64) return capacityFixtureUnknownPhase;
      final bytes = input.readSync(65);
      if (bytes.isEmpty || bytes.length > 64 || input.lengthSync() > 64) {
        return capacityFixtureUnknownPhase;
      }
      final value = ascii.decode(bytes, allowInvalid: false);
      if (!value.endsWith('\n')) return capacityFixtureUnknownPhase;
      final phase = value.substring(0, value.length - 1);
      return capacityFixturePhaseTokens.contains(phase)
          ? phase
          : capacityFixtureUnknownPhase;
    } finally {
      input.closeSync();
    }
  } catch (_) {
    return capacityFixtureUnknownPhase;
  }
}
'@
    $checkedFile=($fileContract -split '\r?\n'|ForEach-Object {$_.Trim()}) -join "`n"
    $writerGuard=@'
void capacityPhase(String phase) {
  if (mode == 'probe-success-write-capacity') {
    writeCapacityFixturePhase(root, phase);
  }
}
'@
    $checkedGuard=($writerGuard -split '\r?\n'|ForEach-Object {$_.Trim()}) -join "`n"
    $commit=@'
final full = await prefillCapacityFixture(
  commitSync: () => db.writeTxnSync(() {
    db.storedSettings.putSync(
      StoredSettings()
        ..id = 1
        ..payload = alternate,
    );
    db.storedSettings.putSync(
      StoredSettings()
        ..id = 1
        ..payload = original,
    );
  }),
  isCapacityFailure: isNativeCapacityFailure,
  onBucket: (completed) => capacityPhase('capacity-prefill-$completed'),
);
'@
    $checkedCommit=($commit -split '\r?\n'|ForEach-Object {$_.Trim()}) -join "`n"
    $tokens=[regex]::Matches($helper,'(?s)const capacityFixturePhaseTokens = <String>\{(?<tokens>.*?)\};')
    $expectedTokens=($phases|ForEach-Object {"'"+$_+"',"}) -join "`n"
    if($tokens.Count -ne 1 -or $tokens[0].Groups['tokens'].Value.Trim() -cne $expectedTokens -or
        -not $helper.Contains("const capacityFixturePhaseFileName = 'trust-capacity-fixture-phase';") -or
        -not $helper.Contains("const capacityFixtureUnknownPhase = 'unknown';") -or -not $helper.Contains($checkedFile) -or
        -not $parent.Contains("import '../support/capacity_fixture.dart';") -or -not $parent.Contains($checkedProducer) -or
        -not $writer.Contains("import 'capacity_fixture.dart';") -or -not $writer.Contains($checkedGuard) -or
        -not $writer.Contains($checkedCommit) -or [regex]::Matches($writer,'capacityPhase\(').Count -ne 12){return $null}
    foreach($phase in $phases) {
        if($phase.StartsWith('capacity-prefill-')){continue}
        if(-not $writer.Contains("capacityPhase('"+$phase+"');")){return $null}
    }
    $declaration=@();$awaitLine=@();$throwLine=@()
    for($index=0;$index+1 -lt $ParentLines.Length;$index++) {
        if($ParentLines[$index].Trim() -ceq 'test(' -and $ParentLines[$index+1].Trim() -ceq "'actual native host trust probes `$mode',"){$declaration+=$index+1}
        if($ParentLines[$index].Trim() -ceq 'await child.exitCode.timeout(' -and $ParentLines[$index+1].Trim() -ceq 'const Duration(seconds: 55),'){$awaitLine+=$index+1}
        if($ParentLines[$index].Trim() -ceq 'throw TimeoutException(' -and $ParentLines[$index+1].Trim() -ceq "'TRUST_CAPACITY_FIXTURE_TIMEOUT:`$phase',"){$throwLine+=$index+1}
    }
    if($declaration.Count -ne 1 -or $awaitLine.Count -ne 1 -or $throwLine.Count -ne 1 -or $declaration[0] -ge $awaitLine[0] -or $awaitLine[0] -ge $throwLine[0]){return $null}
    return @{declarationLine=$declaration[0];producerLines=@($awaitLine[0],$throwLine[0],($throwLine[0]+1),($throwLine[0]+2));
        errorPattern=('\ATimeoutException after 0:00:55\.000000: TRUST_CAPACITY_FIXTURE_TIMEOUT:('+((@($phases)+@('unknown')|ForEach-Object {[regex]::Escape($_)}) -join '|')+')\z')}
}

function Get-NativeGatewayDiagnosticShape {
    param([string[]]$GatewayLines,[string[]]$HelperLines)
    # A fixed test-only source contract. Callers also require current hashes
    # for both files; arbitrary Expected/Actual assertions are insufficient.
    $helper=@'
class GatewayFixtureFailure implements Exception {
  const GatewayFixtureFailure({
    required this.primaryError,
    required this.primaryStackTrace,
    required this.cleanupError,
    required this.cleanupStackTrace,
  });

  final Object primaryError;
  final StackTrace primaryStackTrace;
  final Object cleanupError;
  final StackTrace cleanupStackTrace;

  @override
  String toString() =>
      '$primaryError\nGATEWAY_FIXTURE_CLEANUP_FAILURE: $cleanupError\n'
      '$cleanupStackTrace';
}

Future<void> runGatewayFixture({
  required Future<void> Function() body,
  required Future<void> Function() cleanup,
}) async {
  ({Object error, StackTrace stackTrace})? primaryFailure;
  try {
    await body();
  } catch (error, stackTrace) {
    primaryFailure = (error: error, stackTrace: stackTrace);
  }

  try {
    await cleanup();
  } catch (error, stackTrace) {
    final primary = primaryFailure;
    if (primary != null) {
      Error.throwWithStackTrace(
        GatewayFixtureFailure(
          primaryError: primary.error,
          primaryStackTrace: primary.stackTrace,
          cleanupError: error,
          cleanupStackTrace: stackTrace,
        ),
        primary.stackTrace,
      );
    }
    Error.throwWithStackTrace(error, stackTrace);
  }

  final primary = primaryFailure;
  if (primary != null) {
    Error.throwWithStackTrace(primary.error, primary.stackTrace);
  }
}
'@
    $producer=@'
expect(
  await child.exitCode.timeout(
    const Duration(seconds: 70),
    onTimeout: () {
      final phase = File(
        p.join(fixture.path, 'gateway-fixture-phase'),
      );
      final value = phase.existsSync()
          ? phase.readAsStringSync()
          : '';
      final safe = RegExp(r'^[a-z-]{1,40}$').hasMatch(value)
          ? value
          : 'unknown';
      throw StateError('GATEWAY_NATIVE_TIMEOUT:$safe');
    },
  ),
  0,
  reason:
      '${mode == 'quota' ? gatewayQuotaReasonPrefix(fixture.path) : ''}${await output}\n${await errors}',
);
'@
    $helperCode=($HelperLines|Where-Object {-not $_.TrimStart().StartsWith('//')}|ForEach-Object {$_.Trim()}) -join "`n"
    $checkedHelper=($helper -split '\r?\n'|ForEach-Object {$_.Trim()}) -join "`n"
    $gatewayCode=($GatewayLines|ForEach-Object {$_.Trim()}) -join "`n"
    $checkedProducer=($producer -split '\r?\n'|ForEach-Object {$_.Trim()}) -join "`n"
    if($helperCode.Trim() -cne $checkedHelper -or -not $gatewayCode.Contains($checkedProducer) -or
        -not $gatewayCode.Contains("import '../support/gateway_fixture_cleanup.dart';")){return $null}
    $declaration=@();$exit=@();$wrapper=@();$cleanup=@()
    for($index=0;$index -lt $GatewayLines.Length;$index++) {
        $text=$GatewayLines[$index].Trim()
        if($text -ceq 'test(' -and $index+1 -lt $GatewayLines.Length -and
            $GatewayLines[$index+1].Trim() -ceq "'actual native MCP gateway `$mode',"){$declaration+=$index+1}
        if($text -ceq 'expect(' -and $index+1 -lt $GatewayLines.Length -and
            $GatewayLines[$index+1].Trim() -ceq 'await child.exitCode.timeout('){$exit+=$index+1}
        if($text -ceq 'await runGatewayFixture(' -and $index+1 -lt $GatewayLines.Length -and
            $GatewayLines[$index+1].Trim() -ceq 'body: () async {'){$wrapper+=$index+1}
        if($text -ceq 'cleanup: fixture.close,'){$cleanup+=$index+1}
    }
    if($declaration.Count -ne 1 -or $exit.Count -ne 1 -or $wrapper.Count -ne 1 -or $cleanup.Count -ne 1 -or
        $declaration[0] -ge $wrapper[0] -or $wrapper[0] -ge $exit[0] -or $exit[0] -ge $cleanup[0]){return $null}
    return @{declarationLine=$declaration[0];producerLines=@($exit[0],($exit[0]+1));cleanupSeparator="`nGATEWAY_FIXTURE_CLEANUP_FAILURE: "}
}

function Get-NativeGatewayQuotaDiagnosticShape {
    param([string[]]$GatewayLines,[string[]]$ActorLines,[string[]]$QuotaLines,
        [string[]]$GrantLines,[string[]]$FixtureLines,[string[]]$HelperLines)
    # In addition to current inventory byte hashes, bind the complete fixed
    # causal producer: role/one-attempt reader+writer, typed nullable mapper,
    # early server observer, opt-in/default lifecycle and primary formatter.
    # An unrelated Expected/Actual or a private output prefix is insufficient.
    if((Get-NativeDiagnosticCodeFingerprint $GatewayLines) -cne 'c571e7f0ebf961038b73f734c88e51c376375eeb921ddd9053d73748ce6a3a78' -or
        (Get-NativeDiagnosticCodeFingerprint $ActorLines) -cne 'e15aec24a2816a640b6d12bc8d1fa82d382e70065e72092619a178b8c45003d9' -or
        (Get-NativeDiagnosticCodeFingerprint $QuotaLines) -cne '5208ff1f418f5fe93a905f64e79fc986680e856ccabd2fbfa21275b705f8f527' -or
        (Get-NativeDiagnosticCodeFingerprint $GrantLines) -cne '28bb8f5084569c049b8bd8c1de7996783c1825fe69e5798497466b3bd2f3fc73' -or
        (Get-NativeDiagnosticCodeFingerprint $FixtureLines) -cne '1a22ecd7326c3856c80a3ff1970da3d89edb566d7e11f2189d03c3356dc9f695' -or
        (Get-NativeDiagnosticCodeFingerprint $HelperLines) -cne 'bc4bc7ea27723f265b521947e36070dfb0afc60ad0c3bfa8edd320cfeccd9b0f'){return $null}
    return Get-NativeGatewayDiagnosticShape -GatewayLines $GatewayLines -HelperLines $HelperLines
}

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
        $lines=Get-CurrentDiagnosticLines $File
        if($null -eq $lines -or $number -lt 1 -or $number -gt @($lines).Count){return $null}
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
    $trustedAuthCases=@('roles','native-gate','stale-close','proofs','quota','expiry','close','snapshot','deadline','client','framing','tamper',
        'owner-context','owner-context-detach','owner-context-expiry','owner-context-budget','owner-context-native','owner-context-stop','owner-context-physical',
        'owner-connection','owner-connection-budget','owner-connection-detach','owner-connection-native','owner-connection-stop','owner-connection-physical')
    $clientFailurePhases=@('prepare','bootstrap','rpc-read','rpc-write','completion','cleanup-child','cleanup-worker')
    $clientFailureCodes=@('SERVICE_UNAVAILABLE','UNSAFE_ENDPOINT','IDENTITY_UNAVAILABLE','TIMEOUT','RESOURCE_LIMIT','UNAUTHORIZED','INCOMPATIBLE','PREREQUISITE_UNAVAILABLE')
    $ownedSeparator="`nOWNED_FIXTURE_CLEANUP_FAILURE:`n"
    $clientParent='packages/serverdeck_windows/test/trusted_client_native_test.dart'
    $clientActor='packages/serverdeck_windows/test/support/trusted_client_actor.dart'
    $ownedFixture='packages/serverdeck_windows/test/support/trusted_client_fixture.dart'
    $clientCompletion='packages/serverdeck_windows/test/support/trusted_client_completion.dart'
    $authParent='packages/serverdeck_locald/test/mcp/trusted_auth_native_test.dart'
    $authActor='packages/serverdeck_locald/test/support/trusted_auth_actor.dart'
    $authStartup='packages/serverdeck_locald/test/support/trusted_auth_fixture.dart'
    $clientShape=$null;$authShape=$null
    function Get-CheckedOwnedCase($Test,[string]$File,$DeclarationLine,$Shape,[string]$ExpectedFile,[string]$Prefix,[string[]]$Cases) {
        if(-not $Shape -or -not $Test -or $File -cne $ExpectedFile -or $Test['name'] -isnot [string] -or
            $Test['url'] -isnot [string] -or (Resolve-DiagnosticSource $Test['url']) -cne $ExpectedFile -or
            ($Test['id'] -isnot [int] -and $Test['id'] -isnot [long]) -or $Test['id'] -lt 0 -or
            ($Test['suiteID'] -isnot [int] -and $Test['suiteID'] -isnot [long]) -or $suites[[string]$Test['suiteID']] -cne $ExpectedFile -or
            ($Test['line'] -isnot [int] -and $Test['line'] -isnot [long]) -or $Test['line'] -ne $Shape.declarationLine -or $DeclarationLine -ne $Shape.declarationLine){return $null}
        foreach($case in $Cases){if($Test['name'] -ceq ($Prefix+$case)){return $case}}
        return $null
    }
    function Test-OwnedReporterLine($Trace,[string]$ExpectedFile,[long[]]$Lines,[long]$Start=0,[long]$End=0) {
        foreach($frame in [regex]::Matches([string]$Trace,$framePattern)) {
            $frameFile=Resolve-DiagnosticSource $frame.Groups['uri'].Value
            if($frameFile -cne $ExpectedFile){continue}
            $frameLine=Get-DiagnosticLine $frameFile ([long]$frame.Groups['line'].Value)
            if($frameLine -and ($frameLine -in $Lines -or ($Start -gt 0 -and $frameLine -ge $Start -and $frameLine -le $End))){return $true}
        }
        return $false
    }
    function Get-CurrentDiagnosticLines([string]$File) {
        if(-not $known.ContainsKey($File)){return $null}
        try {
            $path=Join-Path $NativeIsarRepository $File
            if((Get-NativeIsarDigest $path) -cne $known[$File].hash){return $null}
            # Preserve String[] even for one line; indexed consumers must
            # never receive a scalar string and index individual characters.
            return ,([IO.File]::ReadAllLines($path))
        } catch {
            # An unavailable source refuses only facts requiring that proof.
            # It cannot invalidate an independently readable reporter. Keep
            # this separate from the reporter parser's fail-closed boundary.
            return $null
        }
    }
    $trustProbeCases=@('basic','reservation','quota','role','foreign','cancel','close','retention','gate','success',
        'success-cancel','success-ttl','success-other','success-write-basic','success-write-replay','success-write-cancel',
        'success-write-ttl','success-write-cas','success-write-foreign','success-write-duplicate','success-write-reservation',
        'success-write-role','success-write-quota','success-write-capacity','success-write-blocked','success-write-retired',
        'success-write-drain','success-write-clock','success-write-retired-admission','success-stale','success-deadline',
        'admission-clock','reserved-cancel','physical-cancel','physical-detach','physical-stale')
    $bootstrapSource='packages/serverdeck_locald/test/bootstrap_native_test.dart'
    $bootstrapPreparation='packages/serverdeck_locald/test/support/bootstrap_preparation.dart'
    $capacityParent='packages/serverdeck_locald/test/mcp/trust_probes_native_test.dart'
    $capacityHelper='packages/serverdeck_locald/test/support/capacity_fixture.dart'
    $capacityWriter='packages/serverdeck_locald/test/support/trust_write_scenarios.dart'
    $capacityShape=$null
    function Get-CapacityDiagnosticPhase($Test,[string]$File,$DeclarationLine,$DiagnosticError,$DiagnosticTrace) {
        if(-not $capacityShape -or -not $Test -or $File -cne $capacityParent -or $DiagnosticError -isnot [string] -or
            $Test['name'] -isnot [string] -or $Test['name'] -cne 'actual native host trust probes success-write-capacity' -or
            $Test['url'] -isnot [string] -or (Resolve-DiagnosticSource $Test['url']) -cne $capacityParent -or
            ($Test['id'] -isnot [int] -and $Test['id'] -isnot [long]) -or $Test['id'] -lt 0 -or
            ($Test['suiteID'] -isnot [int] -and $Test['suiteID'] -isnot [long]) -or $suites[[string]$Test['suiteID']] -cne $capacityParent -or
            ($Test['line'] -isnot [int] -and $Test['line'] -isnot [long]) -or $DeclarationLine -ne $capacityShape.declarationLine -or
            $Test['line'] -ne $capacityShape.declarationLine -or $DiagnosticError -cnotmatch $capacityShape.errorPattern){return $null}
        $candidatePhase=$Matches[1]
        foreach($frame in [regex]::Matches([string]$DiagnosticTrace,$framePattern)) {
            $frameFile=Resolve-DiagnosticSource $frame.Groups['uri'].Value
            if($frameFile -cne $capacityParent){continue}
            $frameLine=Get-DiagnosticLine $frameFile ([long]$frame.Groups['line'].Value)
            if($frameLine -in $capacityShape.producerLines){return $candidatePhase}
        }
        return $null
    }
    $gatewaySource='packages/serverdeck_locald/test/mcp/gateway_native_test.dart'
    $gatewayHelper='packages/serverdeck_locald/test/support/gateway_fixture_cleanup.dart'
    $gatewayActor='packages/serverdeck_locald/test/support/gateway_actor.dart'
    $gatewayQuotaHelper='packages/serverdeck_locald/test/support/gateway_quota_fixture.dart'
    $gatewayGrantActor='packages/serverdeck_locald/test/support/operational_grant_actor.dart'
    $gatewayQuotaPhases=@('scenario-prepare','server-prepare','server-bootstrap','server-admitted16','server-quota-oracle','server-cancelled16',
        'server-cancel-oracle','server-child-exit','server-stderr','server-serving','server-cleanup','scenario-cleanup',
        'bridge-bootstrap','bridge-admission','bridge-cancellation','bridge-completion','bridge-cleanup')
    $gatewayQuotaCodes=@('SERVICE_UNAVAILABLE','UNSAFE_ENDPOINT','IDENTITY_UNAVAILABLE','TIMEOUT','RESOURCE_LIMIT','UNAUTHORIZED',
        'INCOMPATIBLE','PREREQUISITE_UNAVAILABLE','FORBIDDEN','FIXTURE_ASSERTION')
    $gatewayShape=$null;$gatewayQuotaShape=$null
    function Get-GatewayDiagnosticCase($Test,[string]$File,$DeclarationLine) {
        if(-not $gatewayShape -or -not $Test -or $File -cne $gatewaySource -or
            $Test['name'] -isnot [string] -or $Test['url'] -isnot [string] -or
            ($Test['id'] -isnot [int] -and $Test['id'] -isnot [long]) -or
            ($Test['line'] -isnot [int] -and $Test['line'] -isnot [long]) -or
            (Resolve-DiagnosticSource $Test['url']) -cne $gatewaySource -or
            $DeclarationLine -ne $gatewayShape.declarationLine -or $Test['line'] -ne $gatewayShape.declarationLine){return $null}
        foreach($case in $gatewayCases) {
            if($Test['name'] -ceq ('actual native MCP gateway '+$case)){return 'gateway-'+$case}
        }
        return $null
    }
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
        if($Phase -ceq 'serverdeck_windows-tests') {
            $parentLines=Get-CurrentDiagnosticLines $clientParent;$actorLines=Get-CurrentDiagnosticLines $clientActor
            $fixtureLines=Get-CurrentDiagnosticLines $ownedFixture;$completionLines=Get-CurrentDiagnosticLines $clientCompletion
            if($parentLines -and $actorLines -and $fixtureLines -and $completionLines) {
                $clientShape=Get-NativeTrustedClientDiagnosticShape $parentLines $actorLines $fixtureLines $completionLines
            }
        }
        if($Phase -ceq 'serverdeck_locald-tests') {
            $parentLines=Get-CurrentDiagnosticLines $authParent;$actorLines=Get-CurrentDiagnosticLines $authActor
            $fixtureLines=Get-CurrentDiagnosticLines $ownedFixture;$startupLines=Get-CurrentDiagnosticLines $authStartup
            if($parentLines -and $actorLines -and $fixtureLines -and $startupLines) {
                $authShape=Get-NativeTrustedAuthDiagnosticShape $parentLines $actorLines $fixtureLines $startupLines
            }
        }
        if($Phase -ceq 'serverdeck_locald-tests') {
            $parentLines=Get-CurrentDiagnosticLines $capacityParent;$helperLines=Get-CurrentDiagnosticLines $capacityHelper
            $writerLines=Get-CurrentDiagnosticLines $capacityWriter
            if($parentLines -and $helperLines -and $writerLines) {
                $capacityShape=Get-NativeCapacityDiagnosticShape -ParentLines $parentLines -HelperLines $helperLines -WriterLines $writerLines
            }
            $parentLines=Get-CurrentDiagnosticLines $gatewaySource;$helperLines=Get-CurrentDiagnosticLines $gatewayHelper
            if($parentLines -and $helperLines) {
                $gatewayShape=Get-NativeGatewayDiagnosticShape -GatewayLines $parentLines -HelperLines $helperLines
            }
            $quotaSources=@{GatewayLines=$gatewaySource;ActorLines=$gatewayActor;QuotaLines=$gatewayQuotaHelper;
                GrantLines=$gatewayGrantActor;FixtureLines=$ownedFixture;HelperLines=$gatewayHelper}
            $quotaLines=@{}
            foreach($key in $quotaSources.Keys) {
                $current=Get-CurrentDiagnosticLines $quotaSources[$key]
                if($current){$quotaLines[$key]=$current}
            }
            if($quotaLines.Count -eq 6){$gatewayQuotaShape=Get-NativeGatewayQuotaDiagnosticShape @quotaLines}
        }
        if($Phase -ceq 'serverdeck_locald-tests') {
            $parentLines=Get-CurrentDiagnosticLines $bootstrapSource;$preparationLines=Get-CurrentDiagnosticLines $bootstrapPreparation
            if($parentLines -and $preparationLines) {
                $bootstrapShape=Get-NativeBootstrapDiagnosticShape -BootstrapLines $parentLines -PreparationLines $preparationLines
            }
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
                            $framePattern='(?m)(?<uri>package:[A-Za-z0-9_]+/[^\s():]+|file:///[^\s()]+?|^[^\s():]+\.dart)(?::|\s+)(?<line>[0-9]+):(?<column>[0-9]+)'
                            $clientMode=Get-CheckedOwnedCase $test $file $declarationLine $clientShape $clientParent 'actual format3 bootstrap and RPC client ' $trustedClientCases
                            $authScenario=Get-CheckedOwnedCase $test $file $declarationLine $authShape $authParent 'actual format3 API1.1 bootstrap and session ' $trustedAuthCases
                            if($event.testID -isnot [int] -and $event.testID -isnot [long]){$authScenario=$null}
                            if($authScenario -and -not (Test-OwnedReporterLine $event.stackTrace $authParent @() $authShape.declarationLine $authShape.endLine)){$authScenario=$null}
                            $ownedPrimaryError=[string]$event.error
                            if($clientMode -or $authScenario) {
                                $secondary=$ownedPrimaryError.IndexOf($ownedSeparator,[StringComparison]::Ordinal)
                                if($secondary -ge 0){$ownedPrimaryError=$ownedPrimaryError.Substring(0,$secondary)}
                            }
                            $authExitCode=$null
                            if($authScenario -and $event.error -is [string] -and ($event.testID -is [int] -or $event.testID -is [long]) -and
                                $ownedPrimaryError -cmatch '\AExpected: <0>\r?\n[ \t]*Actual: <(?<exit>-?[0-9]{1,10})>\r?\n') {
                                $candidateExit=[long]$Matches['exit']
                                if($candidateExit -ne 0 -and $candidateExit -ge -2147483648 -and $candidateExit -le 4294967295 -and
                                    (Test-OwnedReporterLine $event.stackTrace $authParent $authShape.producerLines)){$authExitCode=$candidateExit}
                            }
                            $gatewayDiagnosticCase=Get-GatewayDiagnosticCase $test $file $declarationLine
                            $gatewayQuotaCase=Get-CheckedOwnedCase $test $file $declarationLine $gatewayQuotaShape $gatewaySource 'actual native MCP gateway ' @('quota')
                            $gatewayExitCode=$null;$gatewayPrimaryError=$null
                            if($gatewayDiagnosticCase -and $event.error -is [string] -and
                                ($event.testID -is [int] -or $event.testID -is [long])) {
                                $gatewayPrimaryError=$event.error
                                $separator=$gatewayPrimaryError.IndexOf($gatewayShape.cleanupSeparator,[StringComparison]::Ordinal)
                                if($gatewayDiagnosticCase -ceq 'gateway-quota') {
                                    $quotaSecondary=$gatewayPrimaryError.IndexOf("`nGATEWAY_QUOTA_SECONDARY_FAILURE:`n",[StringComparison]::Ordinal)
                                    if($quotaSecondary -ge 0 -and ($separator -lt 0 -or $quotaSecondary -lt $separator)){$separator=$quotaSecondary}
                                }
                                if($separator -ge 0){$gatewayPrimaryError=$gatewayPrimaryError.Substring(0,$separator)}
                                if($gatewayPrimaryError -cmatch '\AExpected: <0>\r?\n[ \t]*Actual: <(?<exit>-?[0-9]{1,10})>\r?\n') {
                                    $candidateExit=[long]$Matches['exit']
                                    if($candidateExit -ne 0 -and $candidateExit -ge -2147483648 -and $candidateExit -le 4294967295) {
                                        # Check the producer before applying the shared frame
                                        # cap. A secondary cleanup stack cannot prove it.
                                        foreach($trace in @($event.stackTrace,$gatewayPrimaryError)) {
                                            foreach($frame in [regex]::Matches([string]$trace,$framePattern)) {
                                                $frameFile=Resolve-DiagnosticSource $frame.Groups['uri'].Value
                                                if($frameFile -cne $gatewaySource){continue}
                                                $frameLine=Get-DiagnosticLine $frameFile ([long]$frame.Groups['line'].Value)
                                                if($frameLine -in $gatewayShape.producerLines){$gatewayExitCode=$candidateExit;break}
                                            }
                                            if($null -ne $gatewayExitCode){break}
                                        }
                                    }
                                }
                            }
                            $frames=[Collections.Generic.List[object]]::new()
                            $frameKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                            # In a checked gateway exit, primary actor reason frames
                            # precede wrapper frames. Secondary aggregate text stays
                            # private and never supplies primary source evidence.
                            if($null -ne $gatewayExitCode) {
                                foreach($frame in [regex]::Matches($gatewayPrimaryError,$framePattern)) {
                                    $frameFile=Resolve-DiagnosticSource $frame.Groups['uri'].Value
                                    if($frameFile -cne $gatewayActor){continue}
                                    $frameLine=Get-DiagnosticLine $frameFile ([long]$frame.Groups['line'].Value)
                                    if($frameLine -and $frameKeys.Add($frameFile+':'+$frameLine)) {
                                        $frames.Add(@{file=$frameFile;line=$frameLine})
                                        if($frames.Count -eq 3){break}
                                    }
                                }
                            }
                            $traces=if($null -ne $gatewayExitCode -or $gatewayDiagnosticCase -ceq 'gateway-quota'){@($event.stackTrace,$gatewayPrimaryError)}elseif($authScenario -or $clientMode){@($event.stackTrace,$ownedPrimaryError)}else{@($event.stackTrace,$event.error)}
                            # Other failures retain their previous ordering. Child
                            # stacks and reporter stacks share hash/line checks and
                            # one total cap, including the prioritized frames above.
                            if($frames.Count -lt 3) {
                                foreach($trace in $traces) {
                                    foreach($frame in [regex]::Matches([string]$trace,$framePattern)){
                                        $frameFile=Resolve-DiagnosticSource $frame.Groups['uri'].Value
                                        $frameLine=Get-DiagnosticLine $frameFile ([long]$frame.Groups['line'].Value)
                                        if($frameFile -and $frameLine -and $frameKeys.Add($frameFile+':'+$frameLine)){
                                            $frames.Add(@{file=$frameFile;line=$frameLine})
                                            if($frames.Count -eq 3){break}
                                        }
                                    }
                                    if($frames.Count -eq 3){break}
                                }
                            }
                            $native=[Collections.Generic.List[object]]::new()
                            $nativeErrorText=if($gatewayDiagnosticCase -ceq 'gateway-quota'){[string]$gatewayPrimaryError}elseif($authScenario -or $clientMode){$ownedPrimaryError}else{[string]$event.error}
                            foreach($match in [regex]::Matches($nativeErrorText,'OS Error: (?<kind>NT_ATTRIBUTES_STATUS|WIN32_DRIVE_TYPE|WIN32_REPARSE_POINT), errno = (?<code>-?[0-9]{1,10})')){
                                $code=[long]$match.Groups['code'].Value
                                if($code -ge -2147483648 -and $code -le 4294967295){$native.Add(@{kind=$match.Groups['kind'].Value;code=$code});if($native.Count -eq 3){break}}
                            }
                            $safeCode=$null
                            if([string]$event.error -cmatch '^Bad state: (IDENTITY_UNAVAILABLE|PROTECTION_UNAVAILABLE|SECURITY_UNAVAILABLE|UNSAFE_PATH|RESOURCE_LIMIT|SERVICE_UNAVAILABLE|INTERNAL|WORKSPACE_CHILD_FAILED|WORKSPACE_CHILD_TIMEOUT)$'){$safeCode=$Matches[1]}
                            $fixtureCase=$null;$failureKind=$null;$fixtureExitCode=$null;$fixturePhase=$null
                            if($authScenario){$fixtureCase='trusted-auth-'+$authScenario}
                            $bootstrapCase=Get-BootstrapDiagnosticCase $test
                            $key=[string]$event.testID
                            if(($event.testID -is [int] -or $event.testID -is [long]) -and $bootstrapCase -and
                                $bootstrapStates.ContainsKey($key) -and $bootstrapStates[$key].valid -and
                                $bootstrapStates[$key].case -ceq $bootstrapCase) {
                                $fixtureCase=$bootstrapCase
                                $fixturePhase=$bootstrapStates[$key].phase
                            }
                            if($event.testID -is [int] -or $event.testID -is [long]) {
                                $capacityPhase=Get-CapacityDiagnosticPhase $test $file $declarationLine $event.error $event.stackTrace
                                if($capacityPhase){$fixturePhase=$capacityPhase}
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
                                    $trustLines=Get-CurrentDiagnosticLines $file
                                    $index=[int]$declarationLine-1
                                    if($trustLines -and $index+1 -lt $trustLines.Length -and $trustLines[$index].Trim() -ceq 'test(' -and
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
                                        $pipeLines=Get-CurrentDiagnosticLines $file
                                        if(-not $pipeLines){continue}
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
                            if($null -ne $gatewayExitCode -and $fixtureCase -ceq $gatewayDiagnosticCase) {
                                $fixtureExitCode=$gatewayExitCode
                                $failureKind='fixture-exit'
                            }
                            if($gatewayQuotaCase -ceq 'quota' -and $fixtureCase -ceq 'gateway-quota' -and $null -ne $gatewayExitCode -and
                                ($event.testID -is [int] -or $event.testID -is [long]) -and $event.error -is [string] -and
                                (Test-OwnedReporterLine $event.stackTrace $gatewaySource $gatewayQuotaShape.producerLines) -and
                                [regex]::Matches($gatewayPrimaryError,'GATEWAY_QUOTA_FIXTURE_FAILURE:').Count -eq 1) {
                                $quotaPattern='\AExpected: <0>\r?\n[ \t]*Actual: <-?[0-9]{1,10}>\r?\nGATEWAY_QUOTA_FIXTURE_FAILURE:('+($gatewayQuotaPhases -join '|')+'):('+($gatewayQuotaCodes -join '|')+'|-)\nGATEWAY_QUOTA_PRIVATE_OUTPUT:\n'
                                if($gatewayPrimaryError -cmatch $quotaPattern) {
                                    $fixturePhase=$Matches[1]
                                    $safeCode=if($Matches[2] -ceq '-'){$null}else{$Matches[2]}
                                }
                            }
                            if($clientMode -and $clientMode -cnotin @('cleanup2','cleanup3') -and $null -ne $fixtureExitCode -and
                                ($event.testID -is [int] -or $event.testID -is [long]) -and
                                $event.error -is [string] -and (Test-OwnedReporterLine $event.stackTrace $clientParent $clientShape.producerLines) -and
                                [regex]::Matches($ownedPrimaryError,'TRUSTED_CLIENT_FIXTURE_FAILURE:').Count -eq 1 -and
                                [regex]::Matches($ownedPrimaryError,'TRUSTED_CLIENT_PRIVATE_OUTPUT:').Count -eq 1) {
                                $markerPattern='\AExpected: <0>\r?\n[ \t]*Actual: <-?[0-9]{1,10}>\r?\nTRUSTED_CLIENT_FIXTURE_FAILURE:('+($clientFailurePhases -join '|')+'):('+($clientFailureCodes -join '|')+'|-)\nTRUSTED_CLIENT_PRIVATE_OUTPUT:\n'
                                if($ownedPrimaryError -cmatch $markerPattern) {
                                    $fixturePhase=$Matches[1]
                                    $safeCode=if($Matches[2] -ceq '-'){$null}else{$Matches[2]}
                                }
                            }
                            if($authScenario) {
                                $fixturePhase=$null;$safeCode=$null
                                if($null -ne $authExitCode){$fixtureExitCode=$authExitCode;$failureKind='fixture-exit'}
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
                                        $cleanupLines=Get-CurrentDiagnosticLines $frame.file
                                        if(-not $cleanupLines){continue}
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
