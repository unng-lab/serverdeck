import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_engine/mcp/client.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/discovery.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import '../credentials/mcp_artifacts_test.dart' as credentials;
import '../credentials/discovery_custody_test.dart' as discovery;
import '../support/memory_platform.dart' as ram;
import '../hosting/authority_test.dart' show settle;

String nonce(int b) => base64Url.encode(List.filled(32, b)).replaceAll('=', '');
Matcher state(String code) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));
Matcher rpc(String code, McpClientFailureOrigin origin) => throwsA(
  isA<McpClientException>()
      .having((e) => e.code, 'safe code', code)
      .having((e) => e.origin, 'origin', origin),
);
String mac(List<int> token, List<int> bytes) {
  final key = SecretKeyData(List.of(token), overwriteWhenDestroyed: true);
  try {
    return base64Url
        .encode(
          DartHmac.sha256()
              .calculateMacSync(bytes, secretKeyData: key, nonce: [])
              .bytes,
        )
        .replaceAll('=', '');
  } finally {
    key.destroy();
    bytes.fillRange(0, bytes.length, 0);
  }
}

final class Clock implements EngineClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  DateTime get utcNow => DateTime.utc(2026, 10, 30, 12).add(elapsed);
}

/// Deterministic CPU-budget cost during nested immutable capture. This is an
/// input collection, not a runtime hook/alternate client transport or deadline.
final class CostlyMap extends MapBase<String, Object?> {
  CostlyMap(this.clock);
  final Clock clock;
  final valuesByKey = <String, Object?>{'text': 'unchanged'};
  @override
  Iterable<String> get keys => valuesByKey.keys;
  @override
  Object? operator [](Object? key) {
    clock.elapsed = const Duration(seconds: 5);
    return valuesByKey[key];
  }

  @override
  void operator []=(String key, Object? value) {
    valuesByKey[key] = value;
  }

  @override
  void clear() => valuesByKey.clear();
  @override
  Object? remove(Object? key) => valuesByKey.remove(key);
}

final class Files extends ram.Files {
  Completer<void>? blobRead;
  @override
  Future<List<int>> readFile(String path, {required int maxBytes}) async {
    if (path.endsWith('.dpapi')) await blobRead?.future;
    return super.readFile(path, maxBytes: maxBytes);
  }
}

/// One in-memory channel and scripted protocol peer. No OS, stream socket,
/// filesystem, isolate, process, Host, database or remote service is started.
final class Peer implements VerifiedMcpChannel {
  @override
  String ownerIdentity = discovery.sid,
      appRoot = '/unit/app',
      buildId = discovery.build;
  final incoming = <int>[], buffers = <List<int>>[], deadlines = <Duration>[];
  final messages = <Map<String, Object?>>[];
  Future<void> Function(Map<String, Object?>)? onMessage;
  Completer<Uint8List>? waiting;
  int waitingCount = 0, chunk = 65536, disconnects = 0, proofs = 0;
  Completer<void>? proofPause, closing, writeAck;
  Object? proofError;
  bool closed = false, failClose = false;
  Future<void>? closeFuture;
  void feed(Map<String, Object?> value) =>
      feedBytes(frameBytes(encodeMcpMessage(value)));
  void feedBytes(List<int> bytes) {
    incoming.addAll(bytes);
    pump();
  }

  void pump() {
    if (waiting == null || incoming.isEmpty) return;
    final size = [
      waitingCount,
      chunk,
      incoming.length,
    ].reduce((a, b) => a < b ? a : b);
    final value = Uint8List.fromList(incoming.take(size).toList());
    incoming.removeRange(0, size);
    final pending = waiting!;
    waiting = null;
    pending.complete(value);
  }

  @override
  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  }) {
    proofs++;
    final actual = proofPause?.future ?? Future<void>.value();
    observeNativeCompletion?.call(actual);
    if (proofError != null) return Future.error(proofError!);
    return actual;
  }

  @override
  Future<Uint8List> read({required int count, required Duration deadline}) {
    if (closed) return Future.error(StateError('SERVICE_UNAVAILABLE'));
    expect(waiting, isNull);
    deadlines.add(deadline);
    waiting = Completer<Uint8List>();
    final result = waiting!.future;
    result.ignore();
    waitingCount = count;
    pump();
    return result;
  }

  @override
  Future<void> write(List<int> bytes, {required Duration deadline}) async {
    if (closed) throw StateError('SERVICE_UNAVAILABLE');
    buffers.add(bytes);
    final document = StrictCodec().decode(
      bytes.sublist(4),
      maxBytes: 256 * 1024,
    );
    messages.add(document);
    await onMessage?.call(document);
    await writeAck?.future;
  }

  @override
  Future<void> drainOutput({required Duration deadline}) => Future.value();
  @override
  Future<void> disconnect() {
    if (closeFuture != null) return closeFuture!;
    final done = Completer<void>();
    closeFuture = done.future;
    done.future.ignore();
    disconnects++;
    closed = true;
    waiting?.completeError(StateError('SERVICE_UNAVAILABLE'));
    waiting = null;
    () async {
      await closing?.future;
      if (failClose) throw StateError('private native close');
    }().then<void>(done.complete, onError: done.completeError);
    return done.future;
  }
}

final class Setup {
  Setup(this.descriptor) : serverToken = descriptor.bootstrapToken;
  final DiscoveryDescriptor descriptor;
  final List<int> serverToken;
  final peer = Peer(),
      clock = Clock(),
      files = Files(),
      protection = ram.Protection();
  late final artifacts = credentials.artifacts(files, protection);
  late final client = McpClient(
    peer: peer,
    descriptor: descriptor,
    clock: clock,
  );
  late OperationalHello hello;
  bool badServerProof = false, holdReplies = false, badGrantProof = false;
  Map<String, Object?>? lastRequest;
  static Future<Setup> create({
    OperationalRole role = OperationalRole.mcp,
  }) async {
    final descriptor = await DiscoveryDescriptor.create(
      ownerSid: discovery.sid,
      buildId: discovery.build,
      serverPid: 42,
      generation: discovery.generation,
      workspaceId: credentials.workspace,
    );
    final s = Setup(descriptor);
    s.hello = OperationalHello(
      generation: descriptor.generation,
      serverNonce: nonce(9),
      buildId: descriptor.buildId,
      clientRole: role,
    );
    s.peer.onMessage = s.reply;
    s.peer.feed(s.hello.toJson());
    return s;
  }

  Future<void> stage() async {
    await artifacts.stage(credentials.binding());
    await artifacts.publish(credentials.binding(), revoked: false);
  }

  Map<String, Object?> result(
    Map<String, Object?> request,
    Map<String, Object?> value,
  ) => {
    'v': 1,
    'id': request['id'],
    'generation': descriptor.generation,
    'result': value,
  };
  Future<void> reply(Map<String, Object?> value) async {
    if (value.containsKey('authenticate')) {
      final request = OperationalAuthenticate.fromJson(value);
      final transcript = OperationalBootstrapTranscript(
        hello: hello,
        clientNonce: request.clientNonce,
        requestedCapabilities: request.requestedCapabilities,
      );
      final token = List<int>.of(serverToken);
      expect(request.proof, mac(token, transcript.clientBytes()));
      final placeholder = OperationalAuthenticated(
        sessionId: nonce(7),
        clientRole: hello.clientRole,
        capabilities: [hello.clientRole.name],
        proof: nonce(0),
      );
      final proof = mac(token, transcript.serverBytes(placeholder));
      token.fillRange(0, token.length, 0);
      peer.feed(
        OperationalAuthenticated(
          sessionId: placeholder.sessionId,
          clientRole: hello.clientRole,
          capabilities: [hello.clientRole.name],
          proof: badServerProof ? nonce(1) : proof,
        ).toJson(),
      );
      return;
    }
    lastRequest = value;
    if (holdReplies) return;
    switch (value['method']) {
      case 'session.ping':
        peer.feed(result(value, {'leaseSeconds': 60}));
      case 'readiness.get':
        peer.feed(
          result(
            value,
            TrustedReadiness(
              state: ReadinessState.ready,
              generation: descriptor.generation,
              workspaceId: credentials.workspace,
              features: const OperationalFeatures(mcp: true),
            ).toJson(),
          ),
        );
      case 'mcp.open':
        final request = McpOpenRequest.fromJson(value['params']);
        final loaded = await artifacts.readForBridge(request.grantId);
        try {
          final transcript = McpOpenTranscript(
            hello: hello,
            workspaceId: credentials.workspace,
            sessionId: value['sessionId'] as String,
            clientNonce: request.clientNonce,
            grantId: request.grantId,
            secretRef: loaded.binding.secretRef,
          );
          expect(
            await loaded.key.verify(
              transcript.clientBytes(),
              base64Url.decode('${request.proof}='),
            ),
            isTrue,
          );
          final placeholder = McpOpenResult(
            workspaceId: credentials.workspace,
            grantId: request.grantId,
            revision: 1,
            expiresAt: clock.utcNow
                .add(const Duration(hours: 1))
                .toIso8601String(),
            proof: nonce(0),
          );
          final signature = await loaded.key.mac(
            transcript.serverBytes(placeholder),
          );
          peer.feed(
            result(
              value,
              McpOpenResult(
                workspaceId: placeholder.workspaceId,
                grantId: placeholder.grantId,
                revision: 1,
                expiresAt: placeholder.expiresAt,
                proof: badGrantProof
                    ? nonce(3)
                    : base64Url.encode(signature).replaceAll('=', ''),
              ).toJson(),
            ),
          );
        } finally {
          loaded.key.close();
        }
      case 'mcp.invoke':
      // The test supplies its own correlated reply to exercise queue capture.
    }
  }

  Future<void> close() async {
    await client.close();
    descriptor.close();
    serverToken.fillRange(0, serverToken.length, 0);
    protection.dispose();
  }
}

void main() {
  test(
    'response capture charges nested copying before final original deadline',
    () {
      final clock = Clock()..elapsed = const Duration(milliseconds: 4999);
      final result = <String, Object?>{
        'items': [CostlyMap(clock)],
      };
      expect(
        () => captureMcpResult(
          result,
          clock: clock,
          deadline: const Duration(seconds: 5),
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'safe code', 'TIMEOUT'),
        ),
      );
      expect(clock.elapsed, const Duration(seconds: 5));
      final current = Clock();
      final captured = captureMcpResult(
        {
          'items': [
            {'text': 'unchanged'},
          ],
        },
        clock: current,
        deadline: const Duration(seconds: 5),
      );
      expect(
        () => ((captured['items'] as List).single as Map)['text'] = 'changed',
        throwsUnsupportedError,
      );
    },
  );
  test('MCP-only bootstrap proves both transcripts; pre-grant liveness uses same connection', () async {
    final s = await Setup.create();
    s.peer.chunk = 3;
    await s.client.authenticate();
    expect(s.peer.messages.single['authenticate'], isNotNull);
    expect((await s.client.readiness()).workspaceId, credentials.workspace);
    final ping = await s.client.call('session.ping', {});
    expect(ping, {'leaseSeconds': 60});
    expect(() => ping['leaseSeconds'] = 1, throwsUnsupportedError);
    expect(s.peer.buffers.every((b) => b.every((v) => v == 0)), isTrue);
    expect(s.peer.deadlines, contains(const Duration(seconds: 60)));
    await s.close();
    expect(s.peer.disconnects, 1);
  });
  test('owner hello and a bad server MAC cannot authenticate', () async {
    final owner = await Setup.create(role: OperationalRole.owner);
    await expectLater(owner.client.authenticate(), state('UNAUTHORIZED'));
    expect(owner.peer.messages, isEmpty);
    await owner.close();
    final wrong = await Setup.create();
    wrong.badServerProof = true;
    await expectLater(wrong.client.authenticate(), state('UNAUTHORIZED'));
    await wrong.close();
  });
  test(
    'authentication captures its token independently of descriptor disposal',
    () async {
      final s = await Setup.create();
      final client =
          s.client; // capture, then wipe caller-owned descriptor token
      s.descriptor.close();
      await client.authenticate();
      expect(await client.call('session.ping', {}), {'leaseSeconds': 60});
      await s.close();
    },
  );
  test('only MCP methods are callable; denied owner/open/invoke makes no wire write', () async {
    final s = await Setup.create();
    await s.client.authenticate();
    final before = s.peer.messages.length;
    for (final method in [
      'profile.list',
      'settings.set',
      'mcp.open',
      'mcp.invoke',
    ]) {
      await expectLater(
        s.client.call(method, {}),
        rpc('FORBIDDEN', McpClientFailureOrigin.local),
      );
    }
    expect(s.peer.messages.length, before);
    expect(s.client.isClosed, isFalse);
    await s.close();
  });
  test('live native proof failure retains observed physical completion after logical rejection', () async {
    final s = await Setup.create();
    s.peer.proofPause = Completer();
    s.peer.proofError = StateError('UNAUTHORIZED');
    await expectLater(s.client.authenticate(), state('UNAUTHORIZED'));
    var closed = false;
    unawaited(s.client.close().then((_) => closed = true));
    await settle();
    expect(closed, isFalse);
    s.peer.proofPause!.complete();
    await s.close();
    expect(closed, isTrue);
    expect(s.peer.messages, isEmpty);
  });
  test('original bootstrap budget cannot be renewed by a late proof', () async {
    final s = await Setup.create();
    s.peer.proofPause = Completer();
    final start = s.client.authenticate();
    s.clock.elapsed = const Duration(seconds: 6);
    s.peer.proofPause!.complete();
    await expectLater(start, state('TIMEOUT'));
    expect(s.peer.messages, isEmpty);
    await s.close();
  });
  test(
    'sixteen pending requests retain charge until physical write ACK and reply',
    () async {
      final s = await Setup.create();
      await s.client.authenticate();
      s.peer.writeAck = Completer();
      final calls = List.generate(16, (_) => s.client.call('session.ping', {}));
      await settle();
      expect(s.client.pendingRequests, 16);
      await expectLater(
        s.client.call('session.ping', {}),
        rpc('RESOURCE_LIMIT', McpClientFailureOrigin.local),
      );
      expect(s.peer.messages.length, 2); // bootstrap plus first serialized ping
      s.peer.writeAck!.complete();
      expect(await Future.wait(calls), everyElement({'leaseSeconds': 60}));
      expect(s.client.pendingRequests, 0);
      await s.close();
    },
  );
  test(
    'unknown correlation or generation is terminal, never replayed',
    () async {
      for (final wrongGeneration in [false, true]) {
        final s = await Setup.create();
        await s.client.authenticate();
        s.holdReplies = true;
        final request = s.client.call('session.ping', {});
        await settle();
        final response = s.result(s.lastRequest!, {'leaseSeconds': 60});
        if (wrongGeneration) {
          response['generation'] = credentials.grant;
        } else {
          response['id'] = credentials.grant;
        }
        s.peer.feed(response);
        await expectLater(
          request,
          rpc('UNAUTHORIZED', McpClientFailureOrigin.transport),
        );
        expect(s.peer.messages.length, 2);
        await s.close();
      }
    },
  );
  test('foreign ready workspace is terminal even with matching envelope generation', () async {
    final s = await Setup.create();
    await s.client.authenticate();
    s.holdReplies = true;
    final request = s.client.readiness();
    await settle();
    s.peer.feed(
      s.result(
        s.lastRequest!,
        TrustedReadiness(
          state: ReadinessState.ready,
          generation: s.descriptor.generation,
          workspaceId: credentials.grant,
        ).toJson(),
      ),
    );
    await expectLater(
      request,
      rpc('INCOMPATIBLE', McpClientFailureOrigin.transport),
    );
    await s.close();
  });
  test(
    'native identity metadata change cannot issue another request',
    () async {
      final s = await Setup.create();
      await s.client.authenticate();
      s.peer.appRoot = '/different/app';
      await expectLater(
        s.client.call('session.ping', {}),
        rpc('UNAUTHORIZED', McpClientFailureOrigin.transport),
      );
      expect(s.peer.messages.length, 1);
      await s.close();
    },
  );
  test('protected grant proof opens once; queued invoke inputs are captured and frozen', () async {
    final s = await Setup.create();
    await s.stage();
    await s.client.authenticate();
    final writes = s.files.writes;
    await s.client.openGrant(s.artifacts, credentials.grant);
    expect(s.client.grant!.grantId, credentials.grant);
    final count = s.peer.messages.length;
    await expectLater(
      s.client.openGrant(s.artifacts, credentials.grant),
      state('SERVICE_UNAVAILABLE'),
    );
    expect(s.peer.messages.length, count);
    expect(
      s.files.writes,
      writes,
    ); // bridge reads never create/repair credentials
    final params = <String, Object?>{
      'request': {
        'name': 'unit.unknown',
        'arguments': {'text': '原文'},
      },
    };
    final request = s.client.call('mcp.invoke', params);
    (params['request'] as Map)['name'] = 'changed';
    await settle();
    expect((s.lastRequest!['params'] as Map)['request'], {
      'name': 'unit.unknown',
      'arguments': {'text': '原文'},
    });
    s.peer.feed(s.result(s.lastRequest!, {'kind': 'invalid-params'}));
    // A structurally malformed operation result must retire the connection.
    await expectLater(
      request,
      rpc('UNAUTHORIZED', McpClientFailureOrigin.transport),
    );
    await s.close();
  });
  test(
    'bad grant server proof never enables invoke and closes connection',
    () async {
      final s = await Setup.create();
      await s.stage();
      await s.client.authenticate();
      s.badGrantProof = true;
      await expectLater(
        s.client.openGrant(s.artifacts, credentials.grant),
        state('UNAUTHORIZED'),
      );
      expect(s.client.grant, isNull);
      await expectLater(
        s.client.call('mcp.invoke', {'catalog': {}}),
        rpc('SERVICE_UNAVAILABLE', McpClientFailureOrigin.transport),
      );
      await s.close();
    },
  );
  test('close owns late protected credential read and never sends open after retirement', () async {
    final s = await Setup.create();
    await s.stage();
    await s.client.authenticate();
    s.files.blobRead = Completer();
    final opening = s.client.openGrant(s.artifacts, credentials.grant);
    opening.ignore();
    await settle();
    var closed = false;
    unawaited(s.client.close().then((_) => closed = true));
    await settle();
    expect(closed, isFalse);
    s.files.blobRead!.complete();
    await expectLater(opening, state('SERVICE_UNAVAILABLE'));
    await s.close();
    expect(s.peer.messages.length, 1);
    expect(s.client.grant, isNull);
  });
  test(
    'oversized handshake and ordinary frame headers reject before body read',
    () async {
      final bootstrap = await Setup.create();
      bootstrap.peer.incoming.clear();
      final largeHello = ByteData(4)..setUint32(0, 8193, Endian.little);
      bootstrap.peer.feedBytes(largeHello.buffer.asUint8List());
      await expectLater(bootstrap.client.authenticate(), state('UNAUTHORIZED'));
      expect(bootstrap.peer.messages, isEmpty);
      await bootstrap.close();
      final s = await Setup.create();
      await s.client.authenticate();
      s.holdReplies = true;
      final call = s.client.call('session.ping', {});
      await settle();
      final largeReply = ByteData(4)
        ..setUint32(0, 8 * 1024 * 1024 + 1, Endian.little);
      s.peer.feedBytes(largeReply.buffer.asUint8List());
      await expectLater(
        call,
        rpc('UNAUTHORIZED', McpClientFailureOrigin.transport),
      );
      await expectLater(
        s.client.call('session.ping', {}),
        rpc('SERVICE_UNAVAILABLE', McpClientFailureOrigin.transport),
      );
      expect(s.peer.messages.length, 2);
      await s.close();
    },
  );
  test(
    'whole request envelope limit rejects parameters that fit their own bound',
    () async {
      final s = await Setup.create();
      await s.stage();
      await s.client.authenticate();
      await s.client.openGrant(s.artifacts, credentials.grant);
      final params = <String, Object?>{
        'request': {
          'name': 'unit.unknown',
          'arguments': {'text': 'x' * (256 * 1024 - 100)},
        },
      };
      expect(
        encodeMcpMessage(params, maxBytes: 256 * 1024).length,
        lessThan(256 * 1024),
      );
      final count = s.peer.messages.length;
      await expectLater(
        s.client.call('mcp.invoke', params),
        rpc('VALIDATION', McpClientFailureOrigin.local),
      );
      expect(s.peer.messages.length, count);
      expect(s.client.pendingRequests, 0);
      expect(s.client.isClosed, isFalse);
      await s.close();
    },
  );
  test('physical disconnect failure stays failed on repeated close', () async {
    final s = await Setup.create();
    await s.client.authenticate();
    s.peer.failClose = true;
    final first = s.client.close();
    await expectLater(
      first,
      rpc('SERVICE_UNAVAILABLE', McpClientFailureOrigin.transport),
    );
    expect(identical(first, s.client.close()), isTrue);
    s.peer.failClose = false;
    await expectLater(
      s.client.close(),
      rpc('SERVICE_UNAVAILABLE', McpClientFailureOrigin.transport),
    );
    s.descriptor.close();
    s.serverToken.fillRange(0, s.serverToken.length, 0);
    s.protection.dispose();
  });
}
