import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/wire.dart';

const generation = '12345678-1234-4234-8234-123456789abc';
const nextGeneration = '22345678-1234-4234-8234-123456789abc';
const profileId = '32345678-1234-4234-8234-123456789abc';
final buildId = '${'a' * 40}+Debug+${'b' * 64}';
final token = List<int>.generate(32, (i) => i);
final nonce = base64Url.encode(List<int>.filled(32, 9)).replaceAll('=', '');
final sessionId = base64Url.encode(List<int>.filled(32, 8)).replaceAll('=', '');
Matcher failure(ErrorCode value) =>
    throwsA(isA<LocalApiException>().having((e) => e.code, 'safe code', value));

class Clock {
  Duration now = Duration.zero;
  final timers = <({Duration at, void Function() action, List<bool> live})>[];
  CancelDeadline schedule(Duration delay, void Function() action) {
    final live = [true];
    timers.add((at: now + delay, action: action, live: live));
    return () => live[0] = false;
  }

  void advance(Duration time) {
    now += time;
    final due = timers.where((t) => t.live[0] && t.at <= now).toList();
    for (final timer in due) {
      timer.live[0] = false;
      timer.action();
    }
  }
}

class Peer implements ClientTransport {
  Peer({
    this.generation = '12345678-1234-4234-8234-123456789abc',
    this.badProof = false,
    this.extraGrant = false,
    this.failCheck = 0,
  }) {
    send({
      'hello': {
        'product': 'serverdeck-next',
        'apiMajor': 1,
        'apiMinor': 0,
        'workspaceSlot': 'default',
        'generation': generation,
        'serverNonce': nonce,
      },
    });
  }
  final String generation;
  final bool badProof, extraGrant;
  final int failCheck;
  int checks = 0, closes = 0;
  final incoming = <int>[];
  final requests = <Map<String, Object?>>[];
  Completer<Uint8List>? waiting;
  int waitingCount = 0;
  bool closed = false, automatic = true;
  int fragmentSize = 65536;
  void Function()? beforeRead;
  Completer<void>? writingGate;
  Completer<void>? authenticationGate;
  bool failClose = false;
  List<int>? borrowedWrite;
  String revision = '0';
  ErrorCode? readFailure;
  final events = <String>[];
  void send(Map<String, Object?> value) {
    incoming.addAll(frameBytes(StrictCodec().encode(value)));
    flush();
  }

  void flush() {
    if (waiting != null && incoming.isNotEmpty) {
      var count = incoming.length < waitingCount
          ? incoming.length
          : waitingCount;
      if (count > fragmentSize) count = fragmentSize;
      final bytes = Uint8List.fromList(incoming.take(count).toList());
      incoming.removeRange(0, count);
      final result = waiting!;
      waiting = null;
      result.complete(bytes);
    }
  }

  void reply(
    Map<String, Object?> request,
    Map<String, Object?> result, {
    String? epoch,
  }) => send({
    'v': 1,
    'id': request['id'],
    'generation': epoch ?? generation,
    'result': result,
  });
  @override
  Future<void> verifyPeer() async {
    events.add('verify');
    checks++;
    if (checks == failCheck) throw StateError('PRIVATE_NATIVE_DETAILS');
  }

  @override
  Future<Uint8List> read(int count, Duration deadline) {
    beforeRead?.call();
    if (closed) return Future.value(Uint8List(0));
    if (waiting != null) throw StateError('TWO_READERS');
    waiting = Completer<Uint8List>();
    waitingCount = count;
    final result = waiting!.future;
    flush();
    return result;
  }

  @override
  Future<void> write(List<int> bytes, Duration deadline) async {
    events.add('write');
    final value = StrictCodec().decode(bytes.sublist(4));
    if (value.containsKey('authenticate')) {
      if (authenticationGate != null) {
        borrowedWrite = bytes;
        await authenticationGate!.future;
      }
      validateAuthenticate(value);
      final auth = value['authenticate'] as Map<String, Object?>;
      final requested = (auth['requestedCapabilities'] as List).cast<String>();
      final granted = extraGrant
          ? (<String>[...requested, 'settings.write']..sort())
          : requested;
      final base =
          '1\ndefault\n$generation\n$nonce\n${auth['clientNonce']}\n$buildId\n${requested.join(',')}';
      Future<String> mac(String text) async => base64Url
          .encode(
            (await Hmac.sha256().calculateMac(
              utf8.encode(text),
              secretKey: SecretKey(token),
            )).bytes,
          )
          .replaceAll('=', '');
      expect(auth['proof'], await mac('client\n$base'));
      send({
        'authenticated': {
          'sessionId': sessionId,
          'capabilities': granted,
          'idleLeaseSeconds': 60,
          'proof': badProof
              ? nonce
              : await mac('server\n$base\n$sessionId\n${granted.join(',')}'),
        },
      });
      return;
    }
    validateRequestEnvelope(value);
    if (writingGate != null) {
      borrowedWrite = bytes;
      await writingGate!.future;
    }
    requests.add(value);
    if (automatic) {
      if (value['method'] == 'profiles.list' && readFailure != null) {
        send({
          'v': 1,
          'id': value['id'],
          'generation': generation,
          'error': LocalError(readFailure!).toJson(),
        });
        return;
      }
      reply(value, switch (value['method']) {
        'session.ping' => {'leaseSeconds': 60},
        'session.close' => {'closed': true},
        'profiles.list' => {'storeRevision': revision, 'profiles': <Object?>[]},
        'settings.get' => {
          'storeRevision': revision,
          'settings': {
            'revision': '1',
            'theme': 'system',
            'reduceMotion': false,
            'selectedProfileId': null,
          },
        },
        'mutations.get' => {'state': 'not-found', 'result': null},
        _ => mutation,
      });
    }
  }

  @override
  Future<void> close() async {
    if (failClose) throw StateError('PRIVATE_CLOSE_FAILURE');
    if (closed) return;
    closed = true;
    closes++;
    final result = waiting;
    waiting = null;
    result?.complete(Uint8List(0));
  }
}

final mutation = <String, Object?>{
  'entityId': profileId,
  'entityRevision': '1',
  'storeRevision': '1',
  'deleted': false,
};
Map<String, Object?> create() => {
  'profileId': profileId,
  'name': 'Synthetic',
  'address': 'example.invalid',
  'sshUser': 'fixture',
  'credential': <String, Object?>{
    'action': 'replace',
    'kind': 'password',
    'password': ' e\u0301 password ',
  },
};
LocalApiClient clientFor(Peer peer, Clock clock, {Set<Capability>? caps}) =>
    LocalApiClient(
      connect: () async => ClientEndpoint(
        transport: peer,
        generation: peer.generation,
        buildId: buildId,
        bootstrapToken: token,
      ),
      elapsed: () => clock.now,
      schedule: clock.schedule,
      capabilities: caps,
    );
Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'a late read error after stopPolling is not projected into a new epoch',
    () async {
      final peer = Peer(), client = clientFor(peer, Clock());
      await client.connect();
      peer.automatic = false;
      final errors = <ErrorCode>[];
      final subscription = client.snapshotErrors.listen(errors.add);
      client.startPolling();
      await settle();
      final pending = peer.requests.last;
      client.stopPolling();
      peer.send({
        'v': 1,
        'id': pending['id'],
        'generation': generation,
        'error': const LocalError(ErrorCode.timeout).toJson(),
      });
      await settle();
      expect(errors, isEmpty);
      peer.automatic = true;
      await client.close();
      await subscription.cancel();
    },
  );
  test('same generation unchanged snapshot is republished after polling epoch or read failure', () async {
    final peer = Peer(), clock = Clock(), client = clientFor(peer, clock);
    final snapshots = <ClientSnapshot>[], errors = <ErrorCode>[];
    final listener = client.snapshots.listen(snapshots.add);
    final failures = client.snapshotErrors.listen(errors.add);
    client.startPolling();
    await settle();
    expect(snapshots, hasLength(1));
    client.stopPolling();
    client.startPolling();
    await settle();
    expect(snapshots, hasLength(2));
    peer.readFailure = ErrorCode.storageBlocked;
    clock.advance(const Duration(seconds: 2));
    await settle();
    expect(errors, [ErrorCode.storageBlocked]);
    expect(snapshots, hasLength(2));
    peer.readFailure = null;
    clock.advance(const Duration(seconds: 2));
    await settle();
    expect(snapshots, hasLength(3));
    expect(snapshots.last.storeRevision, '0');
    peer.readFailure = ErrorCode.timeout;
    clock.advance(const Duration(seconds: 2));
    await settle();
    expect(errors.last, ErrorCode.timeout);
    peer.readFailure = null;
    clock.advance(const Duration(seconds: 2));
    await settle();
    expect(snapshots, hasLength(4));
    await client.close();
    await listener.cancel();
    await failures.cancel();
  });
  test(
    'stale descriptor generation closes before proof and permits reread',
    () async {
      final peer = Peer(generation: nextGeneration);
      final client = LocalApiClient(
        connect: () async => ClientEndpoint(
          transport: peer,
          generation: generation,
          buildId: buildId,
          bootstrapToken: token,
        ),
      );
      await expectLater(
        client.connect(),
        failure(ErrorCode.serviceUnavailable),
      );
      expect(peer.events, ['verify']);
      expect(peer.closed, true);
      expect(peer.requests, isEmpty);
      await client.close();
    },
  );
  test(
    'heartbeat close failure is observed and retains failed retirement',
    () async {
      final peer = Peer(), clock = Clock(), client = clientFor(peer, clock);
      final states = <ClientConnectionState>[];
      final listener = client.states.listen(states.add);
      await client.connect();
      peer.automatic = false;
      peer.failClose = true;
      // Flutter's test zone fails this test for any uncaught timer Future.
      clock.advance(const Duration(seconds: 20));
      await settle();
      final ping = peer.requests.last;
      expect(ping['method'], 'session.ping');
      peer.send({
        'v': 1,
        'id': ping['id'],
        'generation': generation,
        'error': {
          'code': 'INTERNAL',
          'boundary': 'local',
          'retry': 'manual-recovery',
        },
      });
      await settle();
      expect(states.last, ClientConnectionState.disconnected);
      await expectLater(
        client.connect(),
        failure(ErrorCode.serviceUnavailable),
      );
      await expectLater(client.close(), failure(ErrorCode.serviceUnavailable));
      await listener.cancel();
      peer.failClose = false;
      await peer.close();
    },
  );
  for (final authentication in [true, false]) {
    test(
      'failed close retains pending ${authentication ? 'auth' : 'RPC'} write',
      () async {
        final peer = Peer(), client = clientFor(peer, Clock());
        final states = <ClientConnectionState>[];
        final listener = client.states.listen(states.add);
        final gate = Completer<void>();
        if (!authentication) await client.connect();
        peer.failClose = true;
        if (authentication) {
          peer.authenticationGate = gate;
        } else {
          peer.writingGate = gate;
        }
        final operation = authentication
            ? client.connect()
            : client.read(ApiMethod.profilesList);
        final rejected = expectLater(
          operation,
          failure(ErrorCode.serviceUnavailable),
        );
        await settle();
        final original = List<int>.of(peer.borrowedWrite!);
        await Future<void>.delayed(const Duration(milliseconds: 5200));
        expect(peer.borrowedWrite, original);
        gate.completeError(StateError('WRITE_TERMINAL'));
        await rejected;
        await settle();
        expect(peer.borrowedWrite!.every((b) => b == 0), true);
        expect(states.last, ClientConnectionState.disconnected);
        await expectLater(
          client.connect(),
          failure(ErrorCode.serviceUnavailable),
        );
        await expectLater(
          client.close(),
          failure(ErrorCode.serviceUnavailable),
        );
        await listener.cancel();
        peer.failClose = false;
        await peer.close();
      },
    );
  }
  for (final conflict in [false, true]) {
    test(
      'mutation ${conflict ? 'conflict' : 'commit'} queues immediate reread during polling',
      () async {
        final peer = Peer(), client = clientFor(peer, Clock());
        await client.connect();
        peer.automatic = false;
        client.startPolling();
        await settle();
        final oldList = peer.requests.last;
        final intent = MutationIntent(ApiMethod.profilesCreate, create());
        final changing = client.mutate(intent);
        final completed = conflict
            ? expectLater(changing, failure(ErrorCode.revisionConflict))
            : changing;
        await settle();
        final request = peer.requests.last;
        if (conflict) {
          peer.send({
            'v': 1,
            'id': request['id'],
            'generation': generation,
            'error': {
              'code': 'REVISION_CONFLICT',
              'boundary': 'local',
              'retry': 'reload',
            },
          });
        } else {
          peer.reply(request, mutation);
        }
        await completed;
        peer.reply(oldList, {'storeRevision': '0', 'profiles': <Object?>[]});
        await settle();
        peer.revision = '1';
        peer.automatic = true;
        peer.reply(peer.requests.last, {
          'storeRevision': '1',
          'settings': {
            'revision': '1',
            'theme': 'system',
            'reduceMotion': false,
            'selectedProfileId': null,
          },
        });
        await settle();
        expect(
          peer.requests.where((r) => r['method'] == 'profiles.list').length,
          2,
        );
        client.stopPolling();
        intent.dispose();
        await client.close();
      },
    );
  }
  test(
    'paused event consumers do not retain the transport during client close',
    () async {
      final peer = Peer(), client = clientFor(peer, Clock());
      final listener = client.states.listen((_) {});
      listener.pause();
      await client.connect();
      try {
        await client.close().timeout(const Duration(milliseconds: 100));
        expect(peer.closed, true);
      } finally {
        await listener.cancel();
        await client.close();
      }
    },
  );
  test('partial frame deadline is absolute and closes before accepting its payload', () async {
    final peer = Peer(), clock = Clock(), client = clientFor(peer, clock);
    await client.connect();
    peer.fragmentSize = 1;
    peer.beforeRead = () {
      clock.now += const Duration(seconds: 6);
    };
    await expectLater(
      client.read(ApiMethod.profilesList),
      failure(ErrorCode.serviceUnavailable),
    );
    expect(peer.closed, true);
    await client.close();
  });
  test(
    'timed-out request retains borrowed write bytes until actual completion',
    () async {
      final peer = Peer(), clock = Clock(), client = clientFor(peer, clock);
      await client.connect();
      peer.writingGate = Completer<void>();
      final intent = MutationIntent(ApiMethod.profilesCreate, create());
      final pending = client.mutate(intent),
          rejected = expectLater(pending, failure(ErrorCode.timeout));
      await settle();
      final original = List<int>.of(peer.borrowedWrite!);
      clock.advance(const Duration(seconds: 5));
      await rejected;
      expect(peer.borrowedWrite, original);
      peer.writingGate!.complete();
      await settle();
      expect(peer.borrowedWrite!.every((b) => b == 0), true);
      peer.writingGate = null;
      intent.dispose();
      await client.close();
    },
  );
  test('stop polling discards a late snapshot and mixed revisions are never emitted', () async {
    final peer = Peer(), client = clientFor(peer, Clock());
    await client.connect();
    peer.automatic = false;
    final snapshots = <ClientSnapshot>[];
    final listener = client.snapshots.listen(snapshots.add);
    client.startPolling();
    await settle();
    peer.reply(peer.requests.last, {
      'storeRevision': '1',
      'profiles': <Object?>[],
    });
    await settle();
    peer.reply(peer.requests.last, {
      'storeRevision': '2',
      'settings': {
        'revision': '1',
        'theme': 'system',
        'reduceMotion': false,
        'selectedProfileId': null,
      },
    });
    await settle();
    expect(snapshots, isEmpty);
    final refreshing = client.refreshSnapshot();
    await settle();
    peer.reply(peer.requests.last, {
      'storeRevision': '2',
      'profiles': <Object?>[],
    });
    await settle();
    client.stopPolling();
    peer.reply(peer.requests.last, {
      'storeRevision': '2',
      'settings': {
        'revision': '1',
        'theme': 'system',
        'reduceMotion': false,
        'selectedProfileId': null,
      },
    });
    await refreshing;
    await settle();
    expect(snapshots, isEmpty);
    peer.automatic = true;
    await client.close();
    await listener.cancel();
  });
  test(
    'exact client/server proofs, repeated native checks and immutable results',
    () async {
      final peer = Peer(), clock = Clock(), client = clientFor(peer, clock);
      final response = await client.read(ApiMethod.profilesList);
      expect(peer.events.take(3), ['verify', 'write', 'verify']);
      expect(peer.checks, 2);
      expect(response.generation, generation);
      expect(
        () => response.result['storeRevision'] = '99',
        throwsUnsupportedError,
      );
      await client.close();
      expect(peer.closes, 1);
    },
  );
  test('bad server proof, excessive grant and failed repeated peer query fail closed', () async {
    for (final peer in [
      Peer(badProof: true),
      Peer(extraGrant: true),
      Peer(failCheck: 2),
    ]) {
      final client = clientFor(peer, Clock(), caps: {Capability.profilesRead});
      await expectLater(client.connect(), throwsA(isA<LocalApiException>()));
      expect(peer.closed, true);
      expect(peer.requests, isEmpty);
      await client.close();
    }
  });
  test('immutable mutation survives input edits and status has separate correlation', () async {
    final peer = Peer(), client = clientFor(peer, Clock());
    final params = create(),
        intent = MutationIntent(ApiMethod.profilesCreate, params);
    (params['credential'] as Map)['password'] = 'changed';
    params['name'] = 'changed';
    await client.mutate(intent);
    await client.mutationStatus(intent);
    final sent = peer.requests[0], status = peer.requests[1];
    expect((sent['params'] as Map)['name'], 'Synthetic');
    expect(
      ((sent['params'] as Map)['credential'] as Map)['password'],
      ' e\u0301 password ',
    );
    expect(status['id'], isNot(intent.id));
    expect((status['params'] as Map)['requestId'], intent.id);
    intent.dispose();
    await expectLater(client.mutate(intent), failure(ErrorCode.validation));
    await client.close();
  });
  test(
    'RPC timeout ignores late reply and permits explicit same immutable retry',
    () async {
      final peer = Peer(), clock = Clock(), client = clientFor(peer, clock);
      await client.connect();
      peer.automatic = false;
      final intent = MutationIntent(ApiMethod.profilesCreate, create());
      final original = client.mutate(intent);
      final rejected = expectLater(original, failure(ErrorCode.timeout));
      await settle();
      clock.advance(const Duration(seconds: 5));
      await rejected;
      peer.reply(peer.requests.single, mutation);
      await settle();
      final retry = client.mutate(intent);
      await settle();
      expect(peer.requests.last['id'], intent.id);
      peer.reply(peer.requests.last, mutation);
      expect((await retry).result, mutation);
      intent.dispose();
      peer.automatic = true;
      await client.close();
    },
  );
  test(
    'foreign generation and unknown correlation never satisfy a current read',
    () async {
      final peer = Peer(), client = clientFor(peer, Clock());
      await client.connect();
      peer.automatic = false;
      var done = false;
      final request = client.read(ApiMethod.profilesList);
      unawaited(request.then((_) => done = true));
      await settle();
      final original = peer.requests.single;
      final list = <String, Object?>{
        'storeRevision': '0',
        'profiles': <Object?>[],
      };
      peer.reply(original, list, epoch: nextGeneration);
      peer.reply({...original, 'id': newRequestId()}, list);
      await settle();
      expect(done, false);
      peer.reply(original, list);
      await request;
      peer.automatic = true;
      await client.close();
    },
  );
  test(
    'disconnect joins one fresh handshake and never resends a mutation',
    () async {
      final peers = [Peer(), Peer(generation: nextGeneration)];
      final clock = Clock();
      var connects = 0;
      final client = LocalApiClient(
        connect: () async {
          final peer = peers[connects++];
          return ClientEndpoint(
            transport: peer,
            generation: peer.generation,
            buildId: buildId,
            bootstrapToken: token,
          );
        },
        elapsed: () => clock.now,
        schedule: clock.schedule,
      );
      await client.connect();
      peers.first.automatic = false;
      final intent = MutationIntent(ApiMethod.profilesCreate, create());
      final pending = client.mutate(intent),
          rejected = expectLater(
            pending,
            failure(ErrorCode.serviceUnavailable),
          );
      await settle();
      await peers.first.close();
      await rejected;
      await settle();
      final reads = await Future.wait([
        client.read(ApiMethod.profilesList),
        client.read(ApiMethod.settingsGet),
      ]);
      expect(connects, 2);
      expect(reads.map((r) => r.generation), everyElement(nextGeneration));
      expect(
        peers.last.requests.any((r) => r['method'] == 'profiles.create'),
        false,
      );
      intent.dispose();
      await client.close();
    },
  );
  test(
    'pending quota is bounded, duplicate intent joins, changed input conflicts',
    () async {
      final peer = Peer(), clock = Clock(), client = clientFor(peer, clock);
      await client.connect();
      peer.automatic = false;
      final intent = MutationIntent(ApiMethod.profilesCreate, create());
      final a = client.mutate(intent), b = client.mutate(intent);
      final other = MutationIntent(ApiMethod.profilesCreate, {
        ...create(),
        'name': 'Other',
      }, requestId: intent.id);
      await expectLater(
        client.mutate(other),
        failure(ErrorCode.idempotencyConflict),
      );
      final reads = List.generate(
        15,
        (_) => client.read(ApiMethod.profilesList),
      );
      await settle();
      expect(peer.requests, hasLength(16));
      await expectLater(
        client.read(ApiMethod.profilesList),
        failure(ErrorCode.resourceLimit),
      );
      for (final request in peer.requests) {
        peer.reply(
          request,
          request['method'] == 'profiles.create'
              ? mutation
              : {'storeRevision': '1', 'profiles': <Object?>[]},
        );
      }
      await Future.wait([a, b, ...reads]);
      other.dispose();
      intent.dispose();
      peer.automatic = true;
      await client.close();
    },
  );
  test(
    'heartbeat20s, polling2s, monotonic snapshots and no writes from polling',
    () async {
      final peer = Peer(), clock = Clock(), client = clientFor(peer, clock);
      final snapshots = <ClientSnapshot>[];
      final listener = client.snapshots.listen(snapshots.add);
      client.startPolling();
      await settle();
      expect(snapshots.single.storeRevision, '0');
      peer.revision = '2';
      clock.advance(const Duration(seconds: 2));
      await settle();
      expect(snapshots.last.storeRevision, '2');
      peer.revision = '1';
      clock.advance(const Duration(seconds: 2));
      await settle();
      expect(snapshots, hasLength(2));
      clock.advance(const Duration(seconds: 16));
      await settle();
      expect(
        peer.requests.where((r) => r['method'] == 'session.ping'),
        hasLength(1),
      );
      expect(
        peer.requests.every(
          (r) => !ApiMethod.values
              .singleWhere((m) => m.wireName == r['method'])
              .isMutation,
        ),
        true,
      );
      client.stopPolling();
      await client.close();
      await listener.cancel();
    },
  );
  test(
    'malformed result closes channel with safe errors, never private source',
    () async {
      final peer = Peer(), client = clientFor(peer, Clock());
      await client.connect();
      peer.automatic = false;
      final pending = client.read(ApiMethod.profilesList),
          rejected = expectLater(
            pending,
            failure(ErrorCode.serviceUnavailable),
          );
      await settle();
      peer.reply(peer.requests.single, {'PRIVATE_SECRET': 'private'});
      await rejected;
      expect(peer.closed, true);
      await client.close();
    },
  );
}
