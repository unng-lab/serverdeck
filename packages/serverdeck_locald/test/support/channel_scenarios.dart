import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:serverdeck_locald/api/auth.dart';
import 'package:serverdeck_locald/api/channel.dart';
import 'package:serverdeck_locald/api/server.dart';
import 'package:serverdeck_locald/api/sessions.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/pipe.dart';
import 'package:serverdeck_windows/process.dart';

import '../auth_test.dart' as auth;
import '../models_test.dart' as fixture;
import 'state_store_child.dart' show check, rejects;
import 'native_queue_scenarios.dart';

Future<void> verifyOccupiedPool(String sid) async {
  for (final occupied in [0, 3, 7]) {
    final hash = List.generate(
      32,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final name = '\\\\.\\pipe\\ServerDeckNext.v1.$hash.$occupied';
    final retained = await PipeWorker.createServer(name, sid);
    PipeWorker? client;
    PipeServerPool? recovered;
    try {
      var nativeRefused = false;
      try {
        final unexpected = NativePipe.createServer(name, sid);
        await unexpected.close();
      } on StateError catch (error) {
        check(error.message == 'UNSAFE_ENDPOINT');
        nativeRefused = true;
      }
      check(nativeRefused);
      final deadline = Stopwatch()..start();
      // Worker startup intentionally exposes only the generic safe code.
      await rejects(PipeServerPool.create(hash, sid), 'SERVICE_UNAVAILABLE');
      check(deadline.elapsed < const Duration(seconds: 30));
      final accepting = retained.accept(deadline: const Duration(seconds: 5));
      client = await PipeWorker.openClient(name, sid);
      await accepting;
      await client.verifyPeer(
        sid,
        Platform.resolvedExecutable,
        fileSha256(Platform.resolvedExecutable),
      );
      final read = retained.read(count: 1);
      await client.write([occupied + 1]);
      check((await read).single == occupied + 1);
      final reply = client.read(count: 1);
      await retained.write([occupied + 11]);
      check((await reply).single == occupied + 11);
      await client.close();
      client = null;
      await retained.close();
      recovered = await PipeServerPool.create(hash, sid);
      check(recovered.names.length == 8 && recovered.slots.length == 8);
      check(recovered.names.toSet().length == 8);
      for (var slot = 0; slot < 8; slot++) {
        check(
          recovered.names[slot] == '\\\\.\\pipe\\ServerDeckNext.v1.$hash.$slot',
        );
      }
      await recovered.close();
      recovered = null;
    } finally {
      await client?.close();
      await recovered?.close();
      await retained.close();
    }
  }
  stdout.writeln('NATIVE_OCCUPIED_POOL_REFUSAL_AND_RECOVERY_PROVED');
}

Future<void> verifyChannel(
  StateStore store,
  KeyCustody custody,
  ReceiptKeyMaterial key,
) async {
  final before = StrictCodec().canonical(store.state.toJson());
  await verifyOccupiedPool(custody.ownerSid);
  check(
    base64.encode(StrictCodec().canonical(store.state.toJson())) ==
        base64.encode(before),
  );
  final namespace = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final name = '\\\\.\\pipe\\ServerDeckNext.v1.$namespace.0';
  final pipe = await PipeWorker.createServer(name, custody.ownerSid);
  PipeWorker? client;
  ServerChannel? connection;
  Future<void>? serving;
  final backend = MutationCoordinator(store, custody, key);
  final sessions = SessionRegistry(
    generation: auth.generation,
    onDetached: backend.detach,
  );
  final image = Platform.resolvedExecutable,
      hash = fileSha256(Platform.resolvedExecutable);
  final codec = StrictCodec();
  var number = 0;
  String id() =>
      '92345678-1234-4234-8234-${(++number).toRadixString(16).padLeft(12, '0')}';
  Future<Map<String, Object?>> receive() async {
    Future<Uint8List> exact(int count) async {
      final result = Uint8List(count);
      var offset = 0;
      while (offset < count) {
        final bytes = await client!.read(
          count: (count - offset).clamp(1, 65536),
        );
        check(bytes.isNotEmpty);
        result.setRange(offset, offset + bytes.length, bytes);
        offset += bytes.length;
      }
      return result;
    }

    final header = await exact(4);
    final length = ByteData.sublistView(header).getUint32(0, Endian.little);
    check(length > 0 && length <= 8 * 1024 * 1024);
    return codec.decode(await exact(length), maxBytes: 8 * 1024 * 1024);
  }

  try {
    final accepting = pipe.accept();
    client = await PipeWorker.openClient(name, custody.ownerSid);
    await accepting;
    // Both workers retain/query real kernel process identities, not supplied PID.
    await client.verifyPeer(custody.ownerSid, image, hash);
    final handshake = ServerHandshake(
      token: auth.token,
      generation: auth.generation,
      buildId: auth.buildId,
      channel: namespace,
      sessions: sessions,
      verifyPeer: () => pipe.verifyPeer(custody.ownerSid, image, hash),
    );
    connection = ServerChannel(
      handshake: handshake,
      server: ApiServer(
        sessions: sessions,
        readiness: () => const ReadinessView(
          state: ReadinessState.ready,
          reason: null,
          workspaceId: fixture.workspace,
          generation: auth.generation,
        ),
        coordinator: () => backend,
      ),
      read: (count, deadline) => pipe.read(count: count, deadline: deadline),
      write: (bytes, deadline) => pipe.write(bytes, deadline: deadline),
      drainOutput: (deadline) => pipe.drainOutput(deadline: deadline),
      disconnect: pipe.disconnect,
    );
    serving = connection.run();
    serving.ignore();
    final hello = await receive();
    validateHello(hello);
    final helloModel = ServerHello(
      generation: auth.generation,
      serverNonce: (hello['hello'] as Map)['serverNonce'] as String,
    );
    final caps = Capability.values.map((c) => c.wireName).toList()..sort();
    final authentication = frameBytes(await auth.frame(helloModel, caps));
    // Actual fragmented byte-mode I/O through separate native worker isolates.
    await client.write(authentication.sublist(0, 1));
    await client.write(authentication.sublist(1, 3));
    await client.write(authentication.sublist(3));
    final grant = await receive();
    validateAuthenticated(grant);
    final session = (grant['authenticated'] as Map)['sessionId'] as String;
    check(
      (grant['authenticated'] as Map)['proof'] ==
          await auth.proof(
            auth.transcript(
              helloModel,
              caps,
              role: 'server',
              sessionId: session,
            ),
          ),
    );
    List<int> request(
      String method,
      Map<String, Object?> params,
      String requestId,
    ) => frameBytes(
      codec.encode(
        ApiRequest(
          id: requestId,
          sessionId: session,
          method: method,
          params: params,
        ).toJson(),
      ),
    );
    final pingId = id(), readyId = id();
    await client.write([
      ...request('session.ping', {}, pingId),
      ...request('readiness.get', {}, readyId),
    ]);
    final coalesced = [await receive(), await receive()];
    check(coalesced.map((r) => r['id']).toSet().containsAll([pingId, readyId]));
    check(coalesced.every((r) => r['error'] == null));
    final createId = id();
    final create = <String, Object?>{
      'profileId': fixture.profileId,
      'name': 'Native channel',
      'address': 'example.invalid',
      'sshUser': 'synthetic',
      'credential': {
        'action': 'replace',
        'kind': 'password',
        'password': 'synthetic-channel-secret',
      },
    };
    await client.write(request('profiles.create', create, createId));
    final saved = await receive();
    check(saved['id'] == createId && saved['error'] == null);
    check((saved['result'] as Map)['storeRevision'] == '1');
    await client.write(request('profiles.create', create, createId));
    check(
      base64.encode(codec.canonical((await receive())['result'])) ==
          base64.encode(codec.canonical(saved['result'])),
    );
    await client.write(request('profiles.list', {}, id()));
    final profiles = await receive();
    check(((profiles['result'] as Map)['profiles'] as List).length == 1);
    check(
      !utf8.decode(codec.encode(profiles)).contains('synthetic-channel-secret'),
    );
    await client.write(request('mutations.get', {'requestId': createId}, id()));
    check(((await receive())['result'] as Map)['state'] == 'committed');
    await client.write(request('session.close', {}, id()));
    stdout.writeln('CHANNEL_CLOSE_REQUEST_WRITTEN');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    check(((await receive())['result'] as Map)['closed'] == true);
    stdout.writeln('CHANNEL_CLOSE_REPLY_READ');
    await serving;
    check(sessions.count == 0);
    stdout.writeln('NATIVE_CHANNEL_HANDSHAKE_ROUTER_DPAPI_PROVED');
    await backend.close();
    await verifyNativeQueue(store, custody, key);
  } finally {
    await connection?.close();
    await serving;
    sessions.stop();
    await client?.close();
    await pipe.close();
    await backend.close();
    await store.close();
  }
}
