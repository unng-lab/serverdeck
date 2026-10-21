import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'mcp_runtime_actor.dart' as r;
import 'operational_auth_actor.dart' as a;

const grantId = '12345678-1234-4234-8234-123456789abe';
const requestId = '12345678-1234-4234-8234-123456789abf';
const workspaceId = '12345678-1234-4234-8234-123456789abc';
const keyId = '12345678-1234-4234-8234-123456789abd';

final class PausedProtection implements UserProtection {
  final native = DpapiProtection();
  int pauseNext = 0;
  final waiting = <Completer<void>>[];
  final cleartexts = <List<int>>[];
  @override
  Future<List<int>> protect(List<int> bytes, List<int> entropy) =>
      native.protect(bytes, entropy);
  @override
  Future<List<int>> unprotect(List<int> bytes, List<int> entropy) async {
    final isClient = utf8
        .decode(entropy)
        .contains('serverdeck-next-mcp-client-v1');
    if (pauseNext > 0 && isClient) {
      pauseNext--;
      final gate = Completer<void>();
      waiting.add(gate);
      await gate.future;
    }
    final result = await native.unprotect(bytes, entropy);
    if (isClient) cleartexts.add(result);
    return result;
  }

  void release() {
    pauseNext = 0;
    for (final gate in waiting) if (!gate.isCompleted) gate.complete();
  }

  Future<void> reached(int n) async {
    final watch = Stopwatch()..start();
    while (waiting.length < n) {
      a.check(watch.elapsed < const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

Future<Map<String, Object?>> signedParams(String root, a.Pair pair) async {
  final credential = await files(root).readForBridge(grantId);
  final interest = await pair.registry.begin(
    pair.channel,
    pair.response!.sessionId,
    'session.ping',
  );
  try {
    final nonce = base64Url
        .encode(List<int>.filled(32, 29))
        .replaceAll('=', '');
    final bytes = McpOpenTranscript(
      hello: interest.hello,
      workspaceId: workspaceId,
      sessionId: pair.response!.sessionId,
      clientNonce: nonce,
      grantId: grantId,
      secretRef: credential.binding.secretRef,
    ).clientBytes();
    try {
      return McpOpenRequest(
        grantId: grantId,
        clientNonce: nonce,
        proof: base64Url
            .encode(await credential.key.mac(bytes))
            .replaceAll('=', ''),
      ).toJson();
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  } finally {
    interest.complete();
    credential.key.close();
  }
}

Future<void> controlled(
  String root,
  String mode,
  StateStore store,
  OperationalMcpAuthority authority,
  OperationalSessions registry,
  PausedProtection protection,
  Future<void> Function(String) write,
) async {
  final pairs = <a.Pair>[];
  final requests = <OperationalSessionRequest>[];
  final outcomes = <Future<String>>[];
  Future<void> start() async {
    final pair = await a.Pair.start(root, 'mcp.exe', registry);
    pairs.add(pair);
    await pair.exchange();
    a.check(await pair.next() == 'AUTH:mcp');
    final params = await signedParams(root, pair);
    final request = await registry.begin(
      pair.channel,
      pair.response!.sessionId,
      'mcp.open',
    );
    requests.add(request);
    outcomes.add(
      request
          .openGrant(authority, params)
          .then(
            (_) => 'OPEN',
            onError: (Object error) => (error as StateError).message,
          ),
    );
    // The caller's mutable payload cannot change the snapshotted proof.
    params['grantId'] = requestId;
  }

  try {
    if (mode == 'replay') {
      final first = await a.Pair.start(root, 'mcp.exe', registry);
      pairs.add(first);
      await first.exchange();
      a.check(await first.next() == 'AUTH:mcp');
      final params = await signedParams(root, first);
      final second = await a.Pair.start(root, 'mcp.exe', registry);
      pairs.add(second);
      await second.exchange();
      a.check(await second.next() == 'AUTH:mcp');
      final request = await registry.begin(
        second.channel,
        second.response!.sessionId,
        'mcp.open',
      );
      requests.add(request);
      await a.fails(request.openGrant(authority, params), 'UNAUTHORIZED');
      a.check(
        registry.count == 1 &&
            authority.pendingOpens == 0 &&
            store.isAutomationReady,
      );
      return;
    }
    final count = mode == 'pool' ? 4 : 1;
    protection.pauseNext = count;
    for (var n = 0; n < count; n++) {
      await start();
      await protection.reached(n + 1);
      if (mode == 'pool') {
        registry.disconnect(pairs.last.channel);
        a.check(await outcomes.last == 'UNAUTHORIZED');
        requests.last.complete();
      }
    }
    a.check(authority.pendingOpens == count);
    if (mode == 'pool') {
      await start();
      a.check(await outcomes.last == 'RESOURCE_LIMIT');
      a.check(authority.pendingOpens == 4 && protection.waiting.length == 4);
    } else if (mode == 'late-replace') {
      await write('grant.replace');
      protection.release();
      a.check(await outcomes.single == 'UNAUTHORIZED');
    } else if (mode == 'late-close') {
      authority.close();
      a.check(await outcomes.single == 'UNAUTHORIZED');
      a.check(authority.pendingOpens == 1);
    } else if (mode == 'late-repeat') {
      await a.fails(
        requests.single.openGrant(authority, {'bad': 'payload'}),
        'UNAUTHORIZED',
      );
      a.check(await outcomes.single == 'UNAUTHORIZED');
      a.check(authority.pendingOpens == 1);
    } else if (mode == 'late-timeout') {
      a.check(await outcomes.single == 'TIMEOUT');
      a.check(authority.pendingOpens == 1 && registry.count == 0);
    }
    protection.release();
    final watch = Stopwatch()..start();
    while (authority.pendingOpens != 0) {
      a.check(watch.elapsed < const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    a.check(store.isAutomationReady);
    a.check(protection.cleartexts.every((b) => b.every((v) => v == 0)));
  } finally {
    protection.release();
    for (final request in requests) request.complete();
    for (final pair in pairs) await pair.close();
  }
}

McpCredentialFiles files(String root) => McpCredentialFiles(
  localAppData: p.join(root, 'private'),
  workspaceId: workspaceId,
  ownerSid: currentUserSid(),
  custody: McpCredentialCustody(DpapiProtection()),
);

Future<void> client(List<String> args) async {
  final name = args[1], root = args[2], mode = args[3];
  r.ownRoot(root);
  final pipe = await PipeWorker.openOperationalClient(
    name,
    currentUserSid(),
    root,
  );
  McpLoadedCredential? old;
  try {
    final session = await OperationalBootstrapClient(
      pipe: pipe,
      generation: a.generation,
      token: a.token,
    ).authenticate();
    if (mode.startsWith('retired'))
      old = await files(root).readForBridge(grantId);
    stdout.writeln('AUTH:mcp');
    final commands = StreamIterator(
      stdin.transform(utf8.decoder).transform(const LineSplitter()),
    );
    try {
      a.check(await commands.moveNext() && commands.current == 'open');
      if (old != null) {
        final nonce = base64Url
            .encode(List<int>.filled(32, 17))
            .replaceAll('=', '');
        final context = McpOpenTranscript(
          hello: session.hello,
          workspaceId: workspaceId,
          sessionId: session.id,
          clientNonce: nonce,
          grantId: grantId,
          secretRef: old.binding.secretRef,
        );
        final bytes = context.clientBytes();
        late final List<int> mac;
        try {
          mac = await old.key.mac(bytes);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
        final io = OperationalHandshakeIo(session.peer);
        final watch = Stopwatch()..start();
        Duration remaining() => const Duration(seconds: 5) - watch.elapsed;
        await io.write({
          'v': 1,
          'id': requestId,
          'sessionId': session.id,
          'method': 'mcp.open',
          'params': McpOpenRequest(
            grantId: grantId,
            clientNonce: nonce,
            proof: base64Url.encode(mac).replaceAll('=', ''),
          ).toJson(),
        }, remaining);
        final response = StrictCodec().decode(await io.read(remaining));
        validateResponseEnvelope(response);
        a.check((response['error'] as Map)['code'] == 'UNAUTHORIZED');
        stdout.writeln('ERROR:UNAUTHORIZED');
      } else {
        try {
          final result = await session.openGrant(files(root), grantId);
          a.check(session.grant == result && result.revision == 4);
          stdout.writeln('OPEN:${result.revision}');
          if (mode == 'repeat') {
            await a.fails(
              session.openGrant(files(root), grantId),
              'UNAUTHORIZED',
            );
            stdout.writeln('REPEAT_REFUSED');
          }
        } on StateError catch (error) {
          stdout.writeln('ERROR:${error.message}');
        }
      }
      // Explicit input EOF releases the Windows stdin reader in this fixture.
      while (await commands.moveNext()) {}
    } finally {
      await commands.cancel();
    }
    await session.close();
  } finally {
    old?.key.close();
    await pipe.close();
  }
}

Future<void> scenario(
  String root,
  String mode, {
  Future<void> Function(
    String,
    StateStore,
    OperationalMcpAuthority,
    OperationalSessions,
    a.Pair,
    Future<void> Function(String),
    void Function(Duration),
  )?
  routerRun,
}) async {
  await initializeMcpNativeRuntime(root);
  await r.existingStore(root, withTarget: mode == 'router-targets');
  final local = p.join(root, 'private'), sid = currentUserSid();
  final protection = PausedProtection();
  final custody = KeyCustody(protection, sid);
  final key = await custody.openReceiptKey(
    await readProtectedFile(
      local,
      p.join(
        local,
        'ServerDeckNext',
        'v1',
        'workspaces',
        'default',
        'receipt-key.dpapi',
      ),
      sid,
      maxBytes: 16384,
    ),
    workspaceId,
    keyId,
  );
  final namespace = (await Sha256().hash(utf8.encode('mcp-grant-$root'))).bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.$namespace',
    sid,
  );
  StateStore? store;
  a.Pair? pair;
  OperationalMcpAuthority? authority;
  final registry = OperationalSessions(generation: a.generation);
  try {
    final state = store = await StateStore.openMcpOperational(
      localAppData: local,
      appRoot: root,
      lease: lease,
      custody: custody,
      receiptKey: key,
    );
    var wall = DateTime.now().toUtc();
    final service = OwnerGrantService(state, clock: () => wall);
    var revision = 0;
    Future<void> write(String op) async {
      final input = <String, Object?>{
        'requestId':
            '22345678-1234-4234-8234-${(revision + 1).toString().padLeft(12, '0')}',
        'grantId': grantId,
        if (revision > 0) 'expectedRevision': revision,
        if (op != 'grant.revoke') ...{
          'label': 'native fixture',
          'scopes': [if (mode == 'router-targets') 'read', 'author'],
          'serverIds': [
            if (mode == 'router-targets')
              '32345678-1234-4234-8234-123456789abc',
          ],
          'lifetimeSeconds': 300,
        },
      };
      await service.submitOwner(op, input);
      revision++;
    }

    await write('grant.create');
    if (mode == 'retired2') await write('grant.replace');
    if (mode == 'retired3') {
      await write('grant.replace');
      await write('grant.replace');
    }
    if (!mode.startsWith('retired')) {
      for (var i = 0; i < 3; i++) await write('grant.replace');
    }
    final auth = authority = OperationalMcpAuthority(state, clock: () => wall);
    if (mode == 'pool' || mode == 'replay' || mode.startsWith('late-')) {
      await controlled(root, mode, state, auth, registry, protection, write);
      return;
    }
    final live = pair = await a.Pair.start(
      root,
      'mcp.exe',
      registry,
      mode: mode,
    );
    await live.exchange();
    a.check(await live.next() == 'AUTH:mcp');
    await a.fails(
      registry.begin(live.channel, live.response!.sessionId, 'mcp.invoke'),
      'FORBIDDEN',
    );
    if (mode.startsWith('retired'))
      while (revision < 4) await write('grant.replace');
    live.child.stdin.writeln('open');
    final io = OperationalHandshakeIo(live.peer!);
    final watch = Stopwatch()..start();
    Duration remaining() => const Duration(seconds: 5) - watch.elapsed;
    final envelope = StrictCodec().decode(await io.read(remaining));
    validateRequestEnvelope(envelope);
    final request = await registry.begin(
      live.channel,
      envelope['sessionId'] as String,
      envelope['method'] as String,
    );
    final params = Map<String, Object?>.of(
      envelope['params'] as Map<String, Object?>,
    );
    if (mode == 'badproof')
      params['proof'] = base64Url
          .encode(List<int>.filled(32, 0))
          .replaceAll('=', '');
    if (mode == 'missing') params['grantId'] = requestId;
    if (mode == 'expired') wall = wall.add(const Duration(seconds: 300));
    if (mode == 'revoked') await write('grant.revoke');
    if (mode == 'keyloss') key.close();
    if (mode == 'closed') auth.close();
    String? failure;
    McpOpenResult? result;
    try {
      result = await request.openGrant(auth, params);
    } on StateError catch (error) {
      failure = error.message;
    } finally {
      request.complete();
    }
    if (mode == 'current' ||
        mode.startsWith('router-') ||
        mode == 'grant-expiry' ||
        mode == 'serverrepeat' ||
        mode == 'replace' ||
        mode == 'revoke' ||
        mode == 'repeat' ||
        mode.startsWith('client')) {
      a.check(result?.revision == 4 && auth.pendingOpens == 0);
    } else {
      a.check(
        failure == (mode == 'keyloss' ? 'STORAGE_BLOCKED' : 'UNAUTHORIZED'),
      );
      a.check(registry.count == 0 && auth.pendingOpens == 0);
      a.check(state.isAutomationReady == (mode != 'keyloss'));
    }
    var response = <String, Object?>{
      'v': 1,
      'id': envelope['id'],
      'generation': a.generation,
      if (result != null)
        'result': result.toJson()
      else
        'error': LocalError(
          failure == 'STORAGE_BLOCKED'
              ? ErrorCode.storageBlocked
              : ErrorCode.unauthorized,
        ).toJson(),
    };
    if (mode == 'clientproof')
      (response['result'] as Map)['proof'] = base64Url
          .encode(List<int>.filled(32, 0))
          .replaceAll('=', '');
    if (mode == 'clientcorrelation') response['id'] = requestId;
    await io.write(response, remaining);
    a.check(
      await live.next() ==
          (result == null
              ? 'ERROR:$failure'
              : mode.startsWith('client')
              ? 'ERROR:UNAUTHORIZED'
              : 'OPEN:4'),
    );
    if (routerRun != null) {
      await routerRun(
        root,
        state,
        auth,
        registry,
        live,
        write,
        (duration) => wall = wall.add(duration),
      );
      await a.finishClient(live.child);
      a.check(await live.child.exitCode == 0);
      return;
    }
    if (result != null && !mode.startsWith('client') && mode != 'repeat') {
      final interest = await registry.begin(
        live.channel,
        live.response!.sessionId,
        'mcp.invoke',
      );
      a.check(interest.authorizeMcp(scope: McpScope.author).revision == 4);
      await a.fails(
        Future.sync(() => interest.authorizeMcp(scope: McpScope.read)),
        'FORBIDDEN',
      );
      await a.fails(
        Future.sync(() => interest.authorizeMcp(serverId: requestId)),
        'FORBIDDEN',
      );
      if (mode == 'replace' || mode == 'revoke') {
        await write(mode == 'replace' ? 'grant.replace' : 'grant.revoke');
        await a.fails(interest.revalidate(), 'UNAUTHORIZED');
        a.check(registry.count == 0);
      }
      if (mode == 'grant-expiry') {
        wall = wall.add(const Duration(seconds: 300));
        await a.fails(interest.revalidate(), 'UNAUTHORIZED');
        a.check(registry.count == 0);
      }
      interest.complete();
      if (mode == 'serverrepeat') {
        final repeat = await registry.begin(
          live.channel,
          live.response!.sessionId,
          'mcp.open',
        );
        await a.fails(
          repeat.openGrant(auth, {'invalid': 'payload'}),
          'UNAUTHORIZED',
        );
        repeat.complete();
        a.check(registry.count == 0);
      }
    }
    if (mode == 'repeat') a.check(await live.next() == 'REPEAT_REFUSED');
    await a.finishClient(live.child);
    a.check(await live.child.exitCode == 0);
  } finally {
    authority?.close();
    registry.stop();
    await pair?.close();
    await store?.close();
    key.close();
    await lease.close();
  }
}

Future<void> main(List<String> args) async {
  try {
    containCurrentFixtureTree();
    if (args.first == 'client') {
      if (args[3] == 'normal') {
        await a.client(args);
        return;
      }
      await client(args);
      return;
    }
    r.ownRoot(args[0]);
    await scenario(args[0], args[1]);
    stdout.writeln('PASS:${args[1]}');
  } catch (_) {
    stderr.writeln('GRANT_FIXTURE_FAILED');
    exitCode = 1;
  }
}
