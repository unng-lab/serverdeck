import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/discovery.dart';
import 'package:serverdeck_locald/bootstrap/discovery_file.dart';
import 'package:serverdeck_windows/mcp_build_bundle.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart' show ApiMethod, ErrorCode;
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../../lib/bootstrap/local_api_client.dart';
import 'owner_result_client.dart';

const _crashProfileId = '82345678-1234-4234-8234-123456789012';

void check(bool condition) {
  if (!condition) throw StateError('FIXTURE_FAILED');
}

Future<void> main(List<String> args) async {
  final root = args[0], bundle = args[1];
  final mode = args.length > 2 ? args[2] : 'close';
  final blocked = mode == 'blocked-storage' || mode == 'blocked-incompatible';
  final rejectedAuth = mode.startsWith('reject-');
  final manifest = await verifyTrustedBuildBundle(bundle);
  final sid = currentUserSid();
  final discovery = DiscoveryFile(
    localAppData: root,
    runtimeDirectory: p.join(root, 'ServerDeckNext', 'v1', 'runtime'),
    ownerSid: sid,
    custody: DiscoveryCustody(DpapiProtection(), sid),
  );
  if (mode == 'client-native' ||
      mode == 'client-loss' ||
      mode == 'client-owner-loss' ||
      mode == 'client-sessions') {
    OwnerResultFaults? loss;
    final endpointNames = <LocalApiClient, String>{};
    LocalApiClient makeClient() {
      late final LocalApiClient client;
      final inner = LocalApiClient.trusted(
        connect: () async {
          final descriptor = await discovery.read(manifest.manifest.buildId);
          final token = descriptor.bootstrapToken;
          try {
            for (final name in descriptor.pipeNames) {
              PipeWorker transport;
              try {
                transport = await PipeWorker.openTrustedClient(
                  name,
                  sid,
                  bundle,
                );
              } on StateError catch (error) {
                if (error.message != 'SERVICE_UNAVAILABLE') rethrow;
                continue;
              }
              final bootstrap = TrustedBootstrapClient(
                pipe: transport,
                generation: descriptor.generation,
                token: token,
              );
              try {
                final session = await bootstrap.authenticate();
                endpointNames[client] = name;
                return (TrustedApiClient(session), descriptor.generation);
              } on Object {
                await bootstrap.close();
                rethrow;
              }
            }
            throw const LocalApiException(ErrorCode.serviceUnavailable);
          } finally {
            token.fillRange(0, token.length, 0);
            descriptor.close();
          }
        },
      );
      if (mode == 'client-loss' || mode == 'client-owner-loss') {
        loss = OwnerResultFaults();
        client = OwnerResultFaultClient(inner, loss!);
      } else {
        client = inner;
      }
      return client;
    }

    final client = makeClient();
    final create = MutationIntent(ApiMethod.profilesCreate, {
      'profileId': '62345678-1234-4234-8234-123456789012',
      'name': 'Client fixture',
      'address': 'client.example.test',
      'sshUser': 'fixture',
      'credential': {
        'action': 'replace',
        'kind': 'password',
        'password': ' e\u0301 native-client ',
      },
    });
    MutationIntent? delete;
    try {
      if (mode == 'client-owner-loss') {
        final watch = Stopwatch()..start();
        while (true) {
          try {
            await client.connect();
            final ready = await client.read(ApiMethod.readinessGet);
            if (ready.result['state'] == 'ready') break;
          } on LocalApiException catch (error) {
            check(
              error.code == ErrorCode.serviceUnavailable ||
                  error.code == ErrorCode.timeout,
            );
          }
          check(watch.elapsed < const Duration(seconds: 25));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await verifyOwnerLoss(client, loss!);
        return;
      }
      await client.connect();
      if (mode == 'client-sessions') {
        await verifySessionSlots(
          client,
          makeClient,
          (connected) =>
              endpointNames[connected] ?? (throw StateError('FIXTURE_FAILED')),
        );
        return;
      }
      if (mode == 'client-loss') {
        await verifyLoss(client, loss!);
        return;
      }
      final created = await client.mutate(create);
      check(created.result['entityRevision'] == '1');
      check(
        (await client.mutationStatus(create)).result['state'] == 'committed',
      );
      final profile =
          (await client.read(ApiMethod.profilesGet, {
                'profileId': '62345678-1234-4234-8234-123456789012',
              })).result['profile']
              as Map;
      check(
        profile['name'] == 'Client fixture' &&
            (profile['credential'] as Map)['kind'] == 'password',
      );
      check(!jsonEncode(profile).contains('native-client'));
      final snapshot = client.snapshots.first;
      client.startPolling();
      final observed = await snapshot.timeout(const Duration(seconds: 5));
      check(
        observed.generation == created.generation &&
            observed.storeRevision == created.result['storeRevision'],
      );
      client.stopPolling();
      delete = MutationIntent(ApiMethod.profilesDelete, {
        'profileId': '62345678-1234-4234-8234-123456789012',
        'expectedRevision': '1',
      });
      check((await client.mutate(delete)).result['deleted'] == true);
      stdout.writeln('COMPILED_PRODUCTION_CLIENT_ROUNDTRIP_PROVED');
    } finally {
      create.dispose();
      delete?.dispose();
      await client.close();
    }
    return;
  }
  final watch = Stopwatch()..start();
  DiscoveryDescriptor? descriptor;
  PipeWorker? pipe;
  try {
    while (pipe == null && watch.elapsed < const Duration(seconds: 25)) {
      try {
        descriptor?.close();
        descriptor = await discovery.read(manifest.manifest.buildId);
        for (final name in descriptor.pipeNames) {
          try {
            pipe = await PipeWorker.openTrustedClient(name, sid, bundle);
            break;
          } on StateError catch (error) {
            check(error.message == 'SERVICE_UNAVAILABLE');
          }
        }
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    check(pipe != null && descriptor != null);
    final connected = pipe!;
    final owned = descriptor!;
    final nativePeer = await connected.verifyTrustedPeer();
    await nativePeer.revalidate();
    Future<Uint8List> exact(int count) async {
      final bytes = Uint8List(count);
      var offset = 0;
      while (offset < count) {
        final part = await nativePeer.read(
          count: (count - offset).clamp(1, 65536),
        );
        check(part.isNotEmpty);
        bytes.setRange(offset, offset + part.length, part);
        offset += part.length;
      }
      return bytes;
    }

    final codec = StrictCodec();
    Future<Map<String, Object?>> receive() async {
      final header = await exact(4);
      final count = ByteData.sublistView(header).getUint32(0, Endian.little);
      check(count > 0 && count <= 8 * 1024 * 1024);
      return codec.decode(await exact(count), maxBytes: 8 * 1024 * 1024);
    }

    final hello = OperationalHello.fromJson(await receive());
    check(hello.generation == owned.generation);
    check(
      hello.clientRole ==
          (mode == 'read-only' ? OperationalRole.mcp : OperationalRole.owner),
    );
    final nonce = base64Url.encode(List.filled(32, 7)).replaceAll('=', '');
    final caps = [hello.clientRole.name];
    final transcript = OperationalBootstrapTranscript(
      hello: hello,
      clientNonce: nonce,
      requestedCapabilities: caps,
    );
    final token = owned.bootstrapToken;
    Future<String> proof(List<int> bytes) async {
      final key = SecretKeyData(
        List<int>.of(token),
        overwriteWhenDestroyed: true,
      );
      try {
        final mac = await Hmac.sha256().calculateMac(bytes, secretKey: key);
        return base64Url.encode(mac.bytes).replaceAll('=', '');
      } finally {
        key.destroy();
      }
    }

    await nativePeer.write(
      frameBytes(
        codec.encode({
          'authenticate': {
            'clientNonce': nonce,
            'clientBuildId': mode == 'reject-build'
                ? manifest.manifest.buildId.replaceFirst('Debug', 'Release')
                : manifest.manifest.buildId,
            'requestedCapabilities': mode == 'reject-capability'
                ? ['executor.run']
                : caps,
            'proof': mode == 'reject-proof'
                ? nonce
                : await proof(transcript.clientBytes()),
          },
        }),
      ),
    );
    if (rejectedAuth) {
      token.fillRange(0, token.length, 0);
      // No error envelope or grant may disclose unauthenticated input.
      try {
        check((await nativePeer.read(count: 1)).isEmpty);
      } on StateError catch (error) {
        check(error.message == 'SERVICE_UNAVAILABLE');
      }
      stdout.writeln('COMPILED_BOOTSTRAP_AUTH_REJECTED_PROVED');
      return;
    }
    final grant = OperationalAuthenticated.fromJson(await receive());
    final session = grant.sessionId;
    check(grant.proof == await proof(transcript.serverBytes(grant)));
    token.fillRange(0, token.length, 0);
    var counter = 0;
    Future<Map<String, Object?>> request(
      String method, [
      Map<String, Object?> params = const {},
      String? requestId,
    ]) async {
      final id =
          requestId ??
          '92345678-1234-4234-8234-${(++counter).toString().padLeft(12, '0')}';
      await nativePeer.write(
        frameBytes(
          codec.encode({
            'v': 1,
            'id': id,
            'sessionId': session,
            'method': method,
            'params': params,
          }),
        ),
      );
      final response = await receive();
      check(response['id'] == id && response['generation'] == owned.generation);
      return response;
    }

    Future<Map<String, Object?>> rpc(
      String method, [
      Map<String, Object?> params = const {},
      String? requestId,
    ]) async {
      final response = await request(method, params, requestId);
      check(response['error'] == null);
      return response['result'] as Map<String, Object?>;
    }

    Map<String, Object?> ready;
    do {
      ready = await rpc('readiness.get');
      check(ready['generation'] == owned.generation);
      if (blocked) {
        check(ready['state'] != 'ready');
        if (ready['state'] == 'storage-blocked' ||
            ready['state'] == 'incompatible')
          break;
      }
      if (ready['state'] != 'ready')
        await Future<void>.delayed(const Duration(milliseconds: 250));
      check(watch.elapsed < const Duration(seconds: 25));
    } while (ready['state'] != 'ready');
    if (blocked) {
      final expectedCode = mode == 'blocked-storage'
          ? 'STORAGE_BLOCKED'
          : 'INCOMPATIBLE';
      check(
        ready['state'] ==
                (mode == 'blocked-storage'
                    ? 'storage-blocked'
                    : 'incompatible') &&
            ready['reason'] == expectedCode &&
            ready['workspaceId'] == null,
      );
      final refreshed = await discovery.read(manifest.manifest.buildId);
      try {
        check(
          refreshed.workspaceId == null &&
              refreshed.generation == owned.generation,
        );
      } finally {
        refreshed.close();
      }
      check((await rpc('session.ping'))['leaseSeconds'] == 60);
      for (final method in [
        'profiles.list',
        'profiles.get',
        'profiles.create',
        'profiles.update',
        'profiles.delete',
        'settings.get',
        'settings.update',
        'mutations.get',
        'mutations.recent',
      ]) {
        final response = await request(method);
        check(response['result'] == null);
        final error = response['error'] as Map;
        check(
          error.length == 3 &&
              error['code'] == expectedCode &&
              error['boundary'] == 'local' &&
              error['retry'] ==
                  (expectedCode == 'STORAGE_BLOCKED'
                      ? 'manual-recovery'
                      : 'none'),
        );
      }
      // Readiness and close remain usable after rejected ordinary requests.
      check((await rpc('readiness.get'))['reason'] == expectedCode);
      check((await rpc('session.close'))['closed'] == true);
      stdout.writeln('COMPILED_BOOTSTRAP_BLOCKED_OPERATIONS_PROVED');
      return;
    }
    check(ready['workspaceId'] is String);
    final refreshed = await discovery.read(manifest.manifest.buildId);
    try {
      check(
        refreshed.workspaceId == ready['workspaceId'] &&
            refreshed.generation == owned.generation,
      );
    } finally {
      refreshed.close();
    }
    final idleWatch = Stopwatch()..start();
    if (mode == 'read-only') {
      // Native mcp.exe has no owner access, even before a grant is opened.
      // Role comes from the verified executable path, never requested caps.
      for (final method in [
        'profiles.list',
        'profiles.get',
        'profiles.create',
        'profiles.update',
        'profiles.delete',
        'settings.update',
      ]) {
        // Missing business params deliberately prove cap-before-validation.
        final response = await request(method);
        final error = response['error'] as Map;
        check(
          response['result'] == null &&
              error.length == 3 &&
              error['code'] == 'FORBIDDEN' &&
              error['boundary'] == 'local' &&
              error['retry'] == 'none',
        );
      }
      check((await rpc('readiness.get'))['state'] == 'ready');
      stdout.writeln('COMPILED_BOOTSTRAP_READ_ONLY_PROVED');
    }
    const profileId = _crashProfileId;
    const mutationId = 'a2345678-1234-4234-8234-123456789012';
    if (mode == 'crash') {
      final created = await rpc('profiles.create', {
        'profileId': profileId,
        'name': 'Crash fixture',
        'address': 'crash.example.test',
        'port': 22,
        'sshUser': 'fixture',
        'tags': ['owned'],
        'credential': {'action': 'remove'},
      }, mutationId);
      check(
        created['entityId'] == profileId && created['entityRevision'] == '1',
      );
    }
    if (mode == 'recover' || mode == 'verify-recovered') {
      final result = await rpc('profiles.get', {'profileId': profileId});
      final profile = result['profile'] as Map;
      check(
        profile['name'] == 'Crash fixture' &&
            profile['address'] == 'crash.example.test' &&
            profile['sshUser'] == 'fixture' &&
            profile['port'] == 22 &&
            profile['revision'] == '1',
      );
      final receipt = await rpc('mutations.get', {'requestId': mutationId});
      check(
        receipt['state'] == 'committed' &&
            (receipt['result'] as Map)['entityId'] == profileId,
      );
      final recent = await rpc('mutations.recent', {'limit': 20});
      check(
        (recent['receipts'] as List)
                .cast<Map>()
                .where((value) => value['requestId'] == mutationId)
                .length ==
            1,
      );
      stdout.writeln('COMPILED_BOOTSTRAP_RECOVERY_DATA_PROVED');
    }
    if (mode == 'hold' || mode == 'crash' || mode == 'recover') {
      stdout.writeln('COMPILED_BOOTSTRAP_HELD_READY');
      await stdout.flush();
      check(
        await stdin
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .single
                .timeout(const Duration(seconds: 40)) ==
            (mode == 'crash' ? 'crash' : 'close'),
      );
      if (mode == 'hold') {
        // The losing contender must not invalidate the surviving session.
        check((await rpc('readiness.get'))['generation'] == owned.generation);
        await rpc('profiles.list');
      }
    }
    if (mode == 'crash') {
      try {
        final eof = await nativePeer.read(count: 1);
        check(eof.isEmpty);
      } on StateError catch (error) {
        check(error.message == 'SERVICE_UNAVAILABLE');
      }
      stdout.writeln('COMPILED_BOOTSTRAP_OWNER_CRASH_PROVED');
    } else if (mode == 'expire') {
      try {
        final eof = await nativePeer.read(
          count: 1,
          deadline: const Duration(seconds: 70),
        );
        check(eof.isEmpty);
      } on StateError catch (error) {
        check(error.message == 'SERVICE_UNAVAILABLE');
      }
      check(idleWatch.elapsed >= const Duration(seconds: 59));
      check(idleWatch.elapsed < const Duration(seconds: 68));
      stdout.writeln('COMPILED_BOOTSTRAP_LEASE_EXPIRED_PROVED');
    } else {
      check((await rpc('session.close'))['closed'] == true);
      stdout.writeln('COMPILED_BOOTSTRAP_READY_CLOSE_PROVED');
    }
    stdout.writeln('WORKSPACE_ID=${ready['workspaceId']}');
    stdout.writeln('GENERATION=${owned.generation}');
  } finally {
    await pipe?.close();
    descriptor?.close();
    watch.stop();
  }
}

/// The driver kills only its own verified locald, after this real reply drops.
Future<void> verifyOwnerLoss(
  LocalApiClient client,
  OwnerResultFaults transport,
) async {
  final ready = await client.read(ApiMethod.readinessGet);
  final intent = MutationIntent(ApiMethod.profilesCreate, {
    'profileId': _crashProfileId,
    'name': 'Crash fixture',
    'address': 'crash.example.test',
    'port': 22,
    'sshUser': 'fixture',
    'tags': ['owned'],
    'credential': {'action': 'remove'},
  }, requestId: 'a2345678-1234-4234-8234-123456789012');
  var finished = false;
  final input = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  try {
    transport.dropReplyId = intent.id;
    // Parent starts its conservative four-second bound before actual send.
    stdout.writeln('COMPILED_OWNER_LOSS_SEND');
    await stdout.flush();
    check(
      await input.moveNext().timeout(const Duration(seconds: 10)) &&
          input.current == 'send',
    );
    final pending = client
        .mutate(intent)
        .then<ErrorCode?>(
          (_) {
            finished = true;
            return null;
          },
          onError: (Object error) {
            finished = true;
            if (error is! LocalApiException) throw error;
            return error.code;
          },
        );
    final watch = Stopwatch()..start();
    while (!transport.replyDropped &&
        !finished &&
        watch.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (!transport.replyDropped || finished) {
      final outcome = finished ? await pending : null;
      throw StateError('OWNER_LOSS_NOT_PENDING:${outcome?.wireName}');
    }
    stdout.writeln('COMPILED_BOOTSTRAP_HELD_READY');
    await stdout.flush();
    // No status, retry or graceful session.close while outcome is unknown.
    final failure = await pending.timeout(const Duration(seconds: 6));
    check(failure == ErrorCode.serviceUnavailable);
    check(
      await input.moveNext().timeout(const Duration(seconds: 10)) &&
          input.current == 'crash',
    );
    stdout.writeln('COMPILED_BOOTSTRAP_OWNER_CRASH_PROVED');
    stdout.writeln('COMPILED_OWNER_LOSS_PENDING_FAILURE_PROVED');
    stdout.writeln('WORKSPACE_ID=${ready.result['workspaceId']}');
    stdout.writeln('GENERATION=${ready.generation}');
  } finally {
    await input.cancel();
    intent.dispose();
  }
}

/// The parent keeps one authenticated peer alive: these seven clients fill
/// the other normal slots, without an alternate namespace or service hook.
Future<void> verifySessionSlots(
  LocalApiClient first,
  LocalApiClient Function() makeClient,
  String Function(LocalApiClient) endpointName,
) async {
  final clients = <LocalApiClient>[first];
  final retired = <LocalApiClient>[];
  final generation = first.generation;
  final baseline = (await first.read(ApiMethod.profilesList)).result;
  final codec = StrictCodec();
  final expected = base64.encode(codec.canonical(baseline));
  try {
    for (var i = 0; i < 6; i++) {
      final client = makeClient();
      clients.add(client); // Own before a potentially failing connect.
      await client.connect();
      check(client.generation == generation);
    }
    final ninth = makeClient();
    retired.add(ninth);
    var rejected = false;
    try {
      await ninth.connect();
    } on LocalApiException catch (error) {
      check(error.code == ErrorCode.serviceUnavailable);
      rejected = true;
    }
    check(rejected);
    for (final client in clients) {
      check(client.generation == generation);
      check(
        base64.encode(
              codec.canonical(
                (await client.read(ApiMethod.profilesList)).result,
              ),
            ) ==
            expected,
      );
    }
    check(clients.map(endpointName).toSet().length == clients.length);
    final released = clients.removeLast();
    final releasedEndpoint = endpointName(released);
    retired.add(released);
    await released.close();
    // Listener reuse is asynchronous. Bounded fixture reconnect attempts do
    // not change the production RPC deadline or automatically retry effects.
    final watch = Stopwatch()..start();
    LocalApiClient? replacement;
    while (replacement == null && watch.elapsed < const Duration(seconds: 5)) {
      final candidate = makeClient();
      retired.add(candidate);
      try {
        await candidate.connect();
        replacement = candidate;
      } on LocalApiException catch (error) {
        check(error.code == ErrorCode.serviceUnavailable);
        await candidate.close();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    // A handshake has its own production deadline. Do not accept a late
    // success merely because this attempt began inside the fixture window.
    check(
      replacement != null &&
          replacement.generation == generation &&
          watch.elapsed < const Duration(seconds: 5),
    );
    clients.add(replacement!);
    check(endpointName(replacement) == releasedEndpoint);
    for (final client in clients) {
      check(
        base64.encode(
              codec.canonical(
                (await client.read(ApiMethod.profilesList)).result,
              ),
            ) ==
            expected,
      );
    }
    stdout.writeln('COMPILED_PRODUCTION_EIGHT_SESSIONS_REUSE_PROVED');
    stdout.writeln('COMPILED_PRODUCTION_SAME_ENDPOINT_REUSE_PROVED');
  } finally {
    await Future.wait({...clients, ...retired}.map((client) => client.close()));
  }
}

Future<void> verifyLoss(
  LocalApiClient client,
  OwnerResultFaults transport,
) async {
  final before = await client.read(ApiMethod.profilesList);
  final baseline = BigInt.parse(before.result['storeRevision'] as String);
  final create = MutationIntent(ApiMethod.profilesCreate, {
    'profileId': '72345678-1234-4234-8234-123456789012',
    'name': 'Lost reply fixture',
    'address': 'loss.example.test',
    'sshUser': 'fixture',
    'credential': {'action': 'remove'},
  });
  final update = MutationIntent(ApiMethod.profilesUpdate, {
    'profileId': '72345678-1234-4234-8234-123456789012',
    'expectedRevision': '1',
    'name': 'Late original fixture',
    'address': 'loss.example.test',
    'port': 22,
    'sshUser': 'fixture',
    'tags': <String>[],
    'credential': {'action': 'keep'},
  });
  MutationIntent? changed, delete;
  Future<void> timeout(MutationIntent intent) async {
    try {
      await client.mutate(intent);
      throw StateError('FIXTURE_EXPECTED_TIMEOUT');
    } on LocalApiException catch (error) {
      check(error.code == ErrorCode.timeout);
    }
  }

  try {
    transport.dropReplyId = create.id;
    await timeout(create);
    check(transport.replyDropped && client.generation == before.generation);
    final status = await client.mutationStatus(create);
    check(status.result['state'] == 'committed');
    final original = status.result['result'];
    final replay = await client.mutate(create);
    check(jsonEncode(replay.result) == jsonEncode(original));
    check(replay.result['storeRevision'] == '${baseline + BigInt.one}');
    stdout.writeln('COMPILED_CLIENT_LOST_REPLY_COMMITTED_STATUS_REPLAY_PROVED');

    transport.holdRequestId = update.id;
    await timeout(update);
    check(transport.requestHeld && client.generation == before.generation);
    check((await client.mutationStatus(update)).result['state'] == 'not-found');
    final updated = await client.mutate(update);
    check(transport.lateOriginalDelivered);
    check(updated.result['storeRevision'] == '${baseline + BigInt.two}');
    check(updated.result['entityRevision'] == '2');
    final current = await client.read(ApiMethod.profilesGet, {
      'profileId': '72345678-1234-4234-8234-123456789012',
    });
    check(
      (current.result['profile'] as Map)['name'] == 'Late original fixture',
    );
    check(current.result['storeRevision'] == '${baseline + BigInt.two}');
    check((await client.mutationStatus(update)).result['state'] == 'committed');
    changed = MutationIntent(ApiMethod.profilesUpdate, {
      'profileId': '72345678-1234-4234-8234-123456789012',
      'expectedRevision': '1',
      'name': 'Changed input rejected',
      'address': 'loss.example.test',
      'port': 22,
      'sshUser': 'fixture',
      'tags': <String>[],
      'credential': {'action': 'keep'},
    }, requestId: update.id);
    try {
      await client.mutate(changed);
      throw StateError('FIXTURE_EXPECTED_CONFLICT');
    } on LocalApiException catch (error) {
      check(error.code == ErrorCode.idempotencyConflict);
    }
    final recent = await client.read(ApiMethod.mutationsRecent, {'limit': 20});
    final receipts = (recent.result['receipts'] as List).cast<Map>();
    check(receipts.where((r) => r['requestId'] == create.id).length == 1);
    check(receipts.where((r) => r['requestId'] == update.id).length == 1);
    check(client.generation == before.generation);
    stdout.writeln(
      'COMPILED_CLIENT_LOST_REQUEST_LATE_ORIGINAL_SINGLE_EFFECT_PROVED',
    );
    delete = MutationIntent(ApiMethod.profilesDelete, {
      'profileId': '72345678-1234-4234-8234-123456789012',
      'expectedRevision': '2',
    });
    check((await client.mutate(delete)).result['deleted'] == true);
    stdout.writeln('COMPILED_PRODUCTION_CLIENT_LOSS_RECOVERY_PROVED');
  } finally {
    create.dispose();
    update.dispose();
    changed?.dispose();
    delete?.dispose();
  }
}
