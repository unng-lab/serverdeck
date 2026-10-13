import 'dart:async';
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
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/process.dart';

import '../../../../lib/bootstrap/local_api_client.dart';
import '../../../../lib/bootstrap/native_client_transport.dart';
import '../../../serverdeck_windows/test/support/identity_failure_probe.dart';
import '../auth_test.dart' as auth;
import '../models_test.dart' as fixture;
import 'mutations.dart' show GateProtection;
import 'state_store_child.dart' show check;

/// Real pipes/sessions/DPAPI/Isar; only protection scheduling is controlled.
Future<void> verifyNativeQueue(
  StateStore store,
  KeyCustody custody,
  ReceiptKeyMaterial key,
) async {
  final gate = GateProtection(custody.protection);
  final backend = MutationCoordinator(
    store,
    KeyCustody(gate, custody.ownerSid),
    key,
  );
  final sessions = SessionRegistry(
    generation: auth.generation,
    onDetached: backend.detach,
  );
  final pipes = <PipeWorker>[], channels = <ServerChannel>[];
  final serving = <Future<void>>[], clients = <LocalApiClient>[];
  final transports = <LocalApiClient, NativeClientTransport>{};
  final peerNumbers = <LocalApiClient, int>{}, serverWrites = <int, int>{};
  final writeCalls = <int, int>{},
      postGrantBytes = <int, int>{},
      payloadReads = <int, int>{};
  final peerChecks = <int, int>{};
  final peerAttempts = <int, int>{};
  final nativePeerFailureConfirmed = <int>{};
  final identityFailureConfirmed = <int>{};
  final helloNonces = <int, String>{}, grantedIds = <int, String>{};
  final authProbes = <_AuthProbe>[];
  final replyRelease = Completer<void>(), replyReached = Completer<void>();
  final boundedReplies = <String>[];
  final intents = <MutationIntent>[];
  final profileIds = <MutationIntent, String>{};
  final image = Platform.resolvedExecutable,
      hash = fileSha256(Platform.resolvedExecutable);
  final namespace = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  // Production accepts only slots 0..7. Give every fixture peer its own hash
  // namespace while keeping that slot contract unchanged.
  String pipeName(int number) =>
      '\\\\.\\pipe\\ServerDeckNext.v1.${namespace.substring(0, 56)}'
      '${number.toRadixString(16).padLeft(8, '0')}.${number % 8}';

  Future<LocalApiClient> peer({
    List<int>? bootstrapToken,
    String? clientBuild,
    String? expectedServerHash,
    Set<Capability>? capabilities,
    String? identityFailure,
    _AuthProbe? authProbe,
    String? nativePeerFailure,
    String? incompatibleHello,
    bool holdFirstReply = false,
  }) async {
    final number = pipes.length;
    serverWrites[number] = 0;
    writeCalls[number] = 0;
    peerChecks[number] = 0;
    peerAttempts[number] = 0;
    final name = pipeName(number);
    final pipe = await PipeWorker.createServer(name, custody.ownerSid);
    pipes.add(pipe);
    Future<void> serve() async {
      await pipe.accept();
      final channel = ServerChannel(
        handshake: ServerHandshake(
          token: auth.token,
          generation: auth.generation,
          buildId: auth.buildId,
          channel: '$namespace-$number',
          sessions: sessions,
          verifyPeer: () async {
            peerAttempts[number] = peerAttempts[number]! + 1;
            final rejecting =
                nativePeerFailure != null &&
                peerAttempts[number] ==
                    (nativePeerFailure.endsWith('initial') ? 1 : 2);
            final kind = rejecting ? nativePeerFailure.split('-').first : '';
            final otherSid = custody.ownerSid == 'S-1-5-18'
                ? 'S-1-5-19'
                : 'S-1-5-18';
            try {
              await pipe.verifyPeer(
                kind == 'sid' ? otherSid : custody.ownerSid,
                kind == 'path' ? '$image.unapproved' : image,
                kind == 'hash' ? '0' * 64 : hash,
              );
            } on StateError catch (error) {
              if (rejecting && error.message == 'IDENTITY_UNAVAILABLE') {
                nativePeerFailureConfirmed.add(number);
              }
              rethrow;
            }
            peerChecks[number] = peerChecks[number]! + 1;
            if (identityFailure != null &&
                peerChecks[number] ==
                    (identityFailure.endsWith('initial') ? 1 : 2)) {
              final failure = identityQueryFailure(
                identityFailure.split('-').first,
              );
              identityFailureConfirmed.add(number);
              throw failure;
            }
          },
        ),
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
        read: (count, deadline) async {
          final afterGrant = postGrantBytes.containsKey(number);
          if (afterGrant && postGrantBytes[number]! >= 4) {
            payloadReads[number] = payloadReads[number]! + 1;
          }
          final bytes = await pipe.read(count: count, deadline: deadline);
          if (afterGrant)
            postGrantBytes[number] = postGrantBytes[number]! + bytes.length;
          return bytes;
        },
        write: (bytes, deadline) async {
          Uint8List? substitutedHello;
          serverWrites[number] = serverWrites[number]! + bytes.length;
          writeCalls[number] = writeCalls[number]! + 1;
          if (writeCalls[number]! <= 2) {
            final document = StrictCodec().decode(bytes.sublist(4));
            if (writeCalls[number] == 1) {
              helloNonces[number] =
                  (document['hello'] as Map)['serverNonce'] as String;
              if (incompatibleHello != null) {
                final hello = document['hello'] as Map;
                hello[incompatibleHello] = incompatibleHello == 'apiMajor'
                    ? 2
                    : 1;
                substitutedHello = Uint8List.fromList(
                  frameBytes(StrictCodec().encode(document, maxBytes: 8192)),
                );
              }
            } else {
              grantedIds[number] =
                  (document['authenticated'] as Map)['sessionId'] as String;
            }
          }
          // Handshake sends hello, then grant; observe reads only after grant.
          if (writeCalls[number] == 2) {
            postGrantBytes[number] = 0;
            payloadReads[number] = 0;
          }
          if (holdFirstReply && writeCalls[number] == 3) {
            replyReached.complete();
            await replyRelease.future;
          }
          try {
            await pipe.write(substitutedHello ?? bytes, deadline: deadline);
          } finally {
            substitutedHello?.fillRange(0, substitutedHello.length, 0);
          }
          if (holdFirstReply && writeCalls[number]! > 2) {
            final response = StrictCodec().decode(bytes.sublist(4));
            check(response['error'] == null && response['result'] is Map);
            boundedReplies.add(response['id'] as String);
          }
        },
        drainOutput: (deadline) => pipe.drainOutput(deadline: deadline),
        disconnect: pipe.disconnect,
      );
      channels.add(channel);
      await channel.run();
    }

    final operation = serve();
    operation.ignore();
    serving.add(operation);
    late final LocalApiClient client;
    client = LocalApiClient(
      capabilities: capabilities,
      connect: () async {
        final transport = await NativeClientTransport.open(
          pipeName: name,
          ownerSid: custody.ownerSid,
          imagePath: image,
          imageHash: expectedServerHash ?? hash,
        );
        transports[client] = transport;
        if (authProbe != null) authProbe.bind(transport);
        return ClientEndpoint(
          transport: authProbe ?? transport,
          generation: auth.generation,
          buildId: clientBuild ?? auth.buildId,
          bootstrapToken: List<int>.from(bootstrapToken ?? auth.token),
        );
      },
    );
    clients.add(client);
    peerNumbers[client] = number;
    await client.connect();
    return client;
  }

  Future<void> state(
    LocalApiClient client,
    MutationIntent intent,
    String expected,
  ) async {
    final watch = Stopwatch()..start();
    while (true) {
      if ((await client.mutationStatus(intent)).result['state'] == expected)
        return;
      check(watch.elapsed < const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  MutationIntent create(int index) {
    final intent = MutationIntent(ApiMethod.profilesCreate, {
      'profileId':
          'b2345678-1234-4234-8234-${index.toRadixString(16).padLeft(12, '0')}',
      'name': 'Queued native fixture $index',
      'address': 'queue.example.test',
      'sshUser': 'fixture',
      'credential': {
        'action': 'replace',
        'kind': 'password',
        'password': 'native-queue-synthetic',
      },
    });
    intents.add(intent);
    profileIds[intent] =
        'b2345678-1234-4234-8234-${index.toRadixString(16).padLeft(12, '0')}';
    return intent;
  }

  MutationIntent settings(String revision, String theme) {
    final intent = MutationIntent(ApiMethod.settingsUpdate, {
      'expectedRevision': revision,
      'theme': theme,
      'reduceMotion': false,
      'selectedProfileId': null,
    });
    intents.add(intent);
    return intent;
  }

  Future<ErrorCode?> outcome(Future<ApiReply> future) =>
      future.then<ErrorCode?>(
        (_) => null,
        onError: (Object error) {
          if (error is! LocalApiException) throw error;
          return error.code;
        },
      );
  void arm() {
    gate.reached = Completer<void>();
    gate.release = Completer<void>();
  }

  void release() {
    if (gate.release != null && !gate.release!.isCompleted)
      gate.release!.complete();
  }

  try {
    final authRevision = store.state.storeRevision;
    final beforeCompatibility = StrictCodec().encode(
      store.state.toJson(),
      maxBytes: maxResponseBytes,
    );
    void unchangedCompatibilityState() {
      final actual = StrictCodec().encode(
        store.state.toJson(),
        maxBytes: maxResponseBytes,
      );
      try {
        check(actual.length == beforeCompatibility.length);
        for (var i = 0; i < actual.length; i++) {
          check(actual[i] == beforeCompatibility[i]);
        }
      } finally {
        actual.fillRange(0, actual.length, 0);
      }
    }

    try {
      for (final version in ['apiMajor', 'apiMinor']) {
        final number = pipes.length;
        final probe = _AuthProbe();
        authProbes.add(probe);
        try {
          await peer(incompatibleHello: version, authProbe: probe);
          throw StateError('UNEXPECTED_INCOMPATIBLE_GRANT');
        } on LocalApiException catch (error) {
          check(error.code == ErrorCode.incompatible);
        }
        await serving[number].timeout(const Duration(seconds: 5));
        check(writeCalls[number] == 1 && peerChecks[number] == 1);
        check(probe.writeCount == 0 && probe.authentication == null);
        check(!grantedIds.containsKey(number));
        check(!postGrantBytes.containsKey(number) && sessions.count == 0);
        unchangedCompatibilityState();
        stdout.writeln(
          version == 'apiMajor'
              ? 'NATIVE_INCOMPATIBLE_API_MAJOR_NO_AUTH_OR_EFFECT_PROVED'
              : 'NATIVE_INCOMPATIBLE_API_MINOR_NO_AUTH_OR_EFFECT_PROVED',
        );
      }
      final compatible = await peer();
      check(
        (await compatible.read(ApiMethod.profilesList))
                .result['storeRevision'] ==
            authRevision,
      );
      unchangedCompatibilityState();
      await transports[compatible]!.close();
      await serving[peerNumbers[compatible]!].timeout(
        const Duration(seconds: 5),
      );
      check(sessions.count == 0);
      stdout.writeln('NATIVE_API_COMPATIBILITY_HEALTHY_RECOVERY_PROVED');
    } finally {
      beforeCompatibility.fillRange(0, beforeCompatibility.length, 0);
    }
    for (final mode in ['proof', 'build', 'server-image']) {
      final rejectedNumber = pipes.length;
      try {
        await peer(
          bootstrapToken: mode == 'proof' ? List.filled(32, 0) : null,
          clientBuild: mode == 'build' ? '${'c' * 40}+Debug+${'d' * 64}' : null,
          expectedServerHash: mode == 'server-image' ? '0' * 64 : null,
        );
        throw StateError('UNEXPECTED_UNTRUSTED_GRANT');
      } on LocalApiException catch (error) {
        check(error.code == ErrorCode.serviceUnavailable);
      }
      await serving[rejectedNumber].timeout(const Duration(seconds: 5));
      check(writeCalls[rejectedNumber]! <= 1); // No grant/error after hello.
      check(sessions.count == 0 && store.state.storeRevision == authRevision);
    }
    final readOnly = await peer(
      capabilities: {Capability.profilesRead, Capability.readinessRead},
    );
    check(
      (await readOnly.read(ApiMethod.profilesList)).result['storeRevision'] ==
          authRevision,
    );
    final deniedWrite = create(0);
    check(await outcome(readOnly.mutate(deniedWrite)) == ErrorCode.forbidden);
    check(
      !store.state.receipts.containsKey(deniedWrite.id) &&
          !store.state.profiles.containsKey(profileIds[deniedWrite]) &&
          store.state.storeRevision == authRevision,
    );
    check(
      (await readOnly.read(ApiMethod.profilesList)).result['storeRevision'] ==
          authRevision,
    );
    await transports[readOnly]!.close();
    await serving[peerNumbers[readOnly]!].timeout(const Duration(seconds: 5));
    check(sessions.count == 0);
    stdout.writeln('NATIVE_AUTH_REFUSAL_AND_READ_ONLY_PROVED');
    for (final mode in [
      'process-initial',
      'process-repeated',
      'token-initial',
      'token-repeated',
    ]) {
      final rejectedNumber = pipes.length;
      try {
        await peer(identityFailure: mode);
        throw StateError('UNEXPECTED_IDENTITY_FAILURE_GRANT');
      } on LocalApiException catch (error) {
        check(error.code == ErrorCode.serviceUnavailable);
      }
      await serving[rejectedNumber].timeout(const Duration(seconds: 5));
      final initial = mode.endsWith('initial');
      check(identityFailureConfirmed.contains(rejectedNumber));
      check(peerChecks[rejectedNumber] == (initial ? 1 : 2));
      check(writeCalls[rejectedNumber] == (initial ? 0 : 1));
      check(sessions.count == 0 && store.state.storeRevision == authRevision);
    }
    stdout.writeln('NATIVE_IDENTITY_QUERY_FAILURE_CLOSED_PROVED');
    stdout.writeln('NATIVE_THREAD_TOKEN_QUERY_FAILURE_STABILITY_PROVED');
    final captured = _AuthProbe();
    authProbes.add(captured);
    final trusted = await peer(authProbe: captured);
    final trustedNumber = peerNumbers[trusted]!;
    check(captured.authentication != null && sessions.count == 1);
    check(
      (await trusted.read(ApiMethod.profilesList)).result['storeRevision'] ==
          authRevision,
    );
    final replay = _AuthProbe(replay: captured.authentication);
    authProbes.add(replay);
    final replayNumber = pipes.length;
    try {
      await peer(authProbe: replay);
      throw StateError('UNEXPECTED_REPLAY_GRANT');
    } on LocalApiException catch (error) {
      check(error.code == ErrorCode.serviceUnavailable);
    }
    await serving[replayNumber].timeout(const Duration(seconds: 5));
    check(replay.replayed);
    check(helloNonces[trustedNumber] != helloNonces[replayNumber]);
    check(writeCalls[replayNumber] == 1 && peerChecks[replayNumber] == 1);
    check(sessions.count == 1 && store.state.storeRevision == authRevision);
    final crossChannel = _AuthProbe(foreignSession: grantedIds[trustedNumber]);
    authProbes.add(crossChannel);
    final intruder = await peer(authProbe: crossChannel);
    check(sessions.count == 2);
    final intruderNumber = peerNumbers[intruder]!;
    check(grantedIds[intruderNumber] != grantedIds[trustedNumber]);
    final crossWrite = create(200);
    check(
      await outcome(intruder.mutate(crossWrite)) ==
          ErrorCode.serviceUnavailable,
    );
    await serving[intruderNumber].timeout(const Duration(seconds: 5));
    check(crossChannel.substitutedSession && writeCalls[intruderNumber] == 2);
    check(
      sessions.count == 1 &&
          store.state.storeRevision == authRevision &&
          !store.state.receipts.containsKey(crossWrite.id) &&
          !store.state.profiles.containsKey(profileIds[crossWrite]),
    );
    check(
      (await trusted.read(ApiMethod.profilesList)).result['storeRevision'] ==
          authRevision,
    );
    await transports[trusted]!.close();
    await serving[trustedNumber].timeout(const Duration(seconds: 5));
    check(sessions.count == 0);
    stdout.writeln('NATIVE_AUTH_REPLAY_AND_CHANNEL_BINDING_PROVED');
    for (final kind in ['sid', 'path', 'hash']) {
      for (final stage in ['initial', 'repeated']) {
        final rejectedNumber = pipes.length;
        try {
          await peer(nativePeerFailure: '$kind-$stage');
          throw StateError('UNEXPECTED_NATIVE_PEER_GRANT');
        } on LocalApiException catch (error) {
          check(error.code == ErrorCode.serviceUnavailable);
        }
        await serving[rejectedNumber].timeout(const Duration(seconds: 5));
        final initial = stage == 'initial';
        check(nativePeerFailureConfirmed.contains(rejectedNumber));
        check(peerAttempts[rejectedNumber] == (initial ? 1 : 2));
        check(peerChecks[rejectedNumber] == (initial ? 0 : 1));
        check(writeCalls[rejectedNumber] == (initial ? 0 : 1));
        check(!grantedIds.containsKey(rejectedNumber));
        check(sessions.count == 0 && store.state.storeRevision == authRevision);
      }
    }
    stdout.writeln('NATIVE_PEER_SID_PATH_HASH_REFUSAL_PROVED');
    final first = await peer(), second = await peer();
    final baseline = BigInt.parse(store.state.storeRevision);
    final initialSettings = store.state.settings;
    arm();
    final running = create(1),
        cancelled = settings(initialSettings.revision, 'dark');
    final runningResult = first.mutate(running);
    runningResult.ignore();
    await gate.reached!.future.timeout(const Duration(seconds: 3));
    final cancelledResult = outcome(second.mutate(cancelled));
    await state(first, cancelled, 'queued');
    // Abruptly close the retained native handle, with no session.close RPC.
    await transports[second]!.close();
    check(await cancelledResult == ErrorCode.serviceUnavailable);
    await state(first, cancelled, 'not-found');
    await state(first, running, 'running');
    check(
      store.state.storeRevision == '$baseline' &&
          store.state.settings.revision == initialSettings.revision,
    );
    release();
    check(
      (await runningResult).result['storeRevision'] ==
          '${baseline + BigInt.one}',
    );
    check(
      (await first.mutate(cancelled)).result['storeRevision'] ==
          '${baseline + BigInt.two}',
    );
    await state(first, cancelled, 'committed');
    check(first.generation == auth.generation);
    stdout.writeln('NATIVE_QUEUE_LAST_REQUESTER_CANCEL_RETRY_PROVED');

    final survivor = await peer();
    arm();
    final orphanRunning = create(2),
        duplicate = settings(store.state.settings.revision, 'light');
    final orphanResult = outcome(first.mutate(orphanRunning));
    await gate.reached!.future.timeout(const Duration(seconds: 3));
    final departingResult = outcome(first.mutate(duplicate));
    await state(survivor, duplicate, 'queued');
    final survivingResult = survivor.mutate(duplicate);
    survivingResult.ignore();
    // A status read is sent after the duplicate write on this serialized client.
    await state(survivor, duplicate, 'queued');
    await transports[first]!.close();
    check(await departingResult == ErrorCode.serviceUnavailable);
    check(await orphanResult == ErrorCode.serviceUnavailable);
    await state(survivor, orphanRunning, 'running');
    await state(survivor, duplicate, 'queued');
    release();
    check(
      (await survivingResult).result['storeRevision'] ==
          '${baseline + BigInt.from(4)}',
    );
    await state(survivor, orphanRunning, 'committed');
    await state(survivor, duplicate, 'committed');
    final receipts =
        ((await survivor.read(ApiMethod.mutationsRecent, {
                  'limit': 20,
                })).result['receipts']
                as List)
            .cast<Map>();
    for (final intent in [running, cancelled, orphanRunning, duplicate]) {
      check(
        receipts.where((value) => value['requestId'] == intent.id).length == 1,
      );
    }
    check(survivor.generation == auth.generation && sessions.count == 1);
    stdout.writeln(
      'NATIVE_QUEUE_DUPLICATE_AND_RUNNING_SURVIVE_DISCONNECT_PROVED',
    );
    final framingRevision = store.state.storeRevision;
    for (final mode in ['zero', 'oversize', 'partial-header', 'partial-body']) {
      final malformed = await peer();
      final transport = transports[malformed]!;
      final number = peerNumbers[malformed]!;
      final beforeWrites = serverWrites[number];
      final disconnected = malformed.states.firstWhere(
        (value) => value == ClientConnectionState.disconnected,
      );
      final header = Uint8List(4);
      ByteData.sublistView(header)
          .setUint32(0, mode == 'oversize' ? 256 * 1024 + 1 : 4, Endian.little);
      final watch = Stopwatch()..start();
      if (mode == 'zero') {
        await transport.write(Uint8List(4), const Duration(seconds: 5));
      } else if (mode == 'oversize') {
        await transport.write(header, const Duration(seconds: 5));
      } else {
        await transport.write(
          mode == 'partial-header' ? header.sublist(0, 1) : [...header, 0x7b],
          const Duration(seconds: 5),
        );
        await Future<void>.delayed(const Duration(seconds: 3));
        await transport.write(
          mode == 'partial-header' ? header.sublist(1, 2) : [0x22],
          const Duration(seconds: 5),
        );
      }
      await disconnected.timeout(const Duration(seconds: 9));
      if (mode.startsWith('partial-')) {
        check(watch.elapsed >= const Duration(milliseconds: 4500));
        check(watch.elapsed < const Duration(seconds: 7));
      } else {
        // Timeout after an attempted payload read cannot satisfy this proof.
        check(postGrantBytes[number] == 4 && payloadReads[number] == 0);
      }
      await serving[number];
      check(serverWrites[number] == beforeWrites); // No echo/error write.
      check(
        sessions.count == 1 && store.state.storeRevision == framingRevision,
      );
      final profiles = await survivor.read(ApiMethod.profilesList);
      check(profiles.result['storeRevision'] == framingRevision);
      check(survivor.generation == auth.generation);
    }
    stdout.writeln('NATIVE_FRAME_LENGTH_AND_PARTIAL_DEADLINE_PROVED');
    final sessionRevision = store.state.storeRevision;
    final admitted = <LocalApiClient>[survivor];
    for (var i = 0; i < 7; i++) {
      admitted.add(await peer());
    }
    check(sessions.count == 8);
    final refusedNumber = pipes.length;
    try {
      await peer();
      throw StateError('UNEXPECTED_NINTH_SESSION');
    } on LocalApiException catch (error) {
      check(error.code == ErrorCode.serviceUnavailable);
    }
    await serving[refusedNumber].timeout(const Duration(seconds: 5));
    // Hello is allowed; no grant or error is written for an unadmitted peer.
    check(writeCalls[refusedNumber] == 1 && sessions.count == 8);
    Future<void> verifyAdmitted() async {
      for (final client in admitted) {
        final profiles = await client.read(ApiMethod.profilesList);
        check(profiles.result['storeRevision'] == sessionRevision);
        check(client.generation == auth.generation);
      }
      check(store.state.storeRevision == sessionRevision);
    }

    await verifyAdmitted();
    final departing = admitted.removeLast();
    await transports[departing]!.close();
    await serving[peerNumbers[departing]!].timeout(const Duration(seconds: 5));
    check(sessions.count == 7);
    admitted.add(await peer());
    check(sessions.count == 8);
    await verifyAdmitted();
    for (final client in admitted.skip(1)) {
      await transports[client]!.close();
      await serving[peerNumbers[client]!].timeout(const Duration(seconds: 5));
    }
    check(sessions.count == 1);
    stdout.writeln('NATIVE_EIGHT_SESSION_LIMIT_AND_REUSE_PROVED');
    final workers = <LocalApiClient>[await peer(), await peer(), await peer()];
    final queueRevision = BigInt.parse(store.state.storeRevision);
    final queueRunning = create(100);
    final queueIntents = List.generate(32, (index) => create(101 + index));
    final overflow = create(133);
    arm();
    final queueRunningResult = workers.first.mutate(queueRunning);
    queueRunningResult.ignore();
    await gate.reached!.future.timeout(const Duration(seconds: 3));
    // Only the first protection signals this barrier. Later admitted creates
    // still delegate to real DPAPI after the shared release is completed.
    gate.reached = null;
    final queueResults = <Future<ApiReply>>[];
    for (var i = 0; i < queueIntents.length; i++) {
      final result = workers[i % workers.length].mutate(queueIntents[i]);
      result.ignore();
      queueResults.add(result);
    }
    // Observer remains below its per-session pending limit; each worker has
    // at most twelve outstanding requests, so it cannot mask the global bound.
    for (final intent in queueIntents) {
      await state(survivor, intent, 'queued');
    }
    await state(survivor, queueRunning, 'running');
    check(await outcome(survivor.mutate(overflow)) == ErrorCode.resourceLimit);
    await state(survivor, overflow, 'not-found');
    final beforeDrain = await survivor.read(ApiMethod.profilesList);
    check(beforeDrain.result['storeRevision'] == '$queueRevision');
    check(store.state.storeRevision == '$queueRevision');
    release();
    check(
      (await queueRunningResult).result['storeRevision'] ==
          '${queueRevision + BigInt.one}',
    );
    await Future.wait(queueResults);
    check(store.state.storeRevision == '${queueRevision + BigInt.from(33)}');
    final queueReceipts =
        ((await survivor.read(ApiMethod.mutationsRecent, {
                  'limit': 100,
                })).result['receipts']
                as List)
            .cast<Map>();
    for (final intent in [queueRunning, ...queueIntents]) {
      check(
        queueReceipts
                .where((entry) => entry['requestId'] == intent.id)
                .length ==
            1,
      );
      check(store.state.profiles.containsKey(profileIds[intent]));
    }
    check(!store.state.receipts.containsKey(overflow.id));
    check(!store.state.profiles.containsKey(profileIds[overflow]));
    // Explicit retry of the same rejected request succeeds after capacity frees.
    check(
      (await survivor.mutate(overflow)).result['storeRevision'] ==
          '${queueRevision + BigInt.from(34)}',
    );
    await state(survivor, overflow, 'committed');
    check(survivor.generation == auth.generation && sessions.count == 4);
    for (final worker in workers) {
      await transports[worker]!.close();
      await serving[peerNumbers[worker]!].timeout(const Duration(seconds: 5));
    }
    check(sessions.count == 1);
    stdout.writeln('NATIVE_GLOBAL_QUEUE_LIMIT_AND_RECOVERY_PROVED');
    final bounded = await peer(holdFirstReply: true);
    final boundedNumber = peerNumbers[bounded]!;
    final boundedRevision = store.state.storeRevision;
    // Send valid frames directly so the client-side 16-request limit cannot
    // mask the server's independent read/dispatch/reply-buffer bound.
    final frames = List.generate(
      17,
      (index) => frameBytes(
        StrictCodec().encode({
          'v': 1,
          'id':
              'c2345678-1234-4234-8234-${index.toRadixString(16).padLeft(12, '0')}',
          'sessionId': grantedIds[boundedNumber]!,
          'method': ApiMethod.profilesList.wireName,
          'params': <String, Object?>{},
        }),
        maxBytes: maxRequestBytes,
      ),
    );
    final firstSixteenBytes = frames
        .take(16)
        .fold<int>(0, (n, f) => n + f.length);
    final allBytes = frames.fold<int>(0, (n, f) => n + f.length);
    Future<void> until(bool Function() condition) async {
      final watch = Stopwatch()..start();
      while (!condition()) {
        check(watch.elapsed < const Duration(seconds: 3));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    for (final frame in frames) {
      await transports[bounded]!.write(frame, rpcDeadline);
    }
    await replyReached.future.timeout(const Duration(seconds: 3));
    await until(() => postGrantBytes[boundedNumber] == firstSixteenBytes);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    check(postGrantBytes[boundedNumber] == firstSixteenBytes);
    check(writeCalls[boundedNumber] == 3 && !replyRelease.isCompleted);
    final survivorRead = await survivor.read(ApiMethod.profilesList);
    check(survivorRead.result['storeRevision'] == boundedRevision);
    check(store.state.storeRevision == boundedRevision && sessions.count == 2);
    replyRelease.complete();
    await until(
      () =>
          postGrantBytes[boundedNumber] == allBytes &&
          writeCalls[boundedNumber] == 19 &&
          boundedReplies.length == 17,
    );
    for (var index = 0; index < 17; index++) {
      final id =
          'c2345678-1234-4234-8234-${index.toRadixString(16).padLeft(12, '0')}';
      check(boundedReplies.where((value) => value == id).length == 1);
    }
    final resumed = await bounded.read(ApiMethod.profilesList);
    check(resumed.result['storeRevision'] == boundedRevision);
    check(bounded.generation == auth.generation);
    check(store.state.storeRevision == boundedRevision);
    await transports[bounded]!.close();
    await serving[boundedNumber].timeout(const Duration(seconds: 5));
    check(sessions.count == 1);
    stdout.writeln('NATIVE_SIXTEEN_PENDING_BACKPRESSURE_AND_RECOVERY_PROVED');
    // Exercise cleanup of a native accept with no connected client/channel.
    final idle = await PipeWorker.createServer(
      pipeName(pipes.length),
      custody.ownerSid,
    );
    pipes.add(idle);
    final accepting = idle.accept().then<void>(
      (_) => throw StateError('UNEXPECTED_IDLE_ACCEPT'),
      onError: (Object error) =>
          check(error is StateError && error.message == 'SERVICE_UNAVAILABLE'),
    );
    accepting.ignore();
    serving.add(accepting);
  } finally {
    if (!replyRelease.isCompleted) replyRelease.complete();
    release();
    try {
      await Future.wait(clients.map((client) => client.close()));
    } finally {
      try {
        await Future.wait(channels.map((channel) => channel.close()));
      } finally {
        try {
          // Cancel/drain an unaccepted slot before awaiting its serving future.
          await Future.wait(pipes.map((pipe) => pipe.close()));
        } finally {
          try {
            await Future.wait(serving);
          } finally {
            sessions.stop();
            try {
              await backend.close();
            } finally {
              for (final intent in intents) {
                intent.dispose();
              }
              for (final probe in authProbes) {
                probe.dispose();
              }
            }
          }
        }
      }
    }
  }
  stdout.writeln('NATIVE_QUEUE_PENDING_ACCEPT_CLEANUP_PROVED');
}

/// Acceptance-only frame substitution; native verification/I/O remain real.
class _AuthProbe implements ClientTransport {
  _AuthProbe({this.replay, this.foreignSession});
  final Uint8List? replay;
  final String? foreignSession;
  late final NativeClientTransport _native;
  Uint8List? authentication;
  int writeCount = 0;
  bool replayed = false, substitutedSession = false;
  void bind(NativeClientTransport native) => _native = native;
  @override
  Future<void> verifyPeer() => _native.verifyPeer();
  @override
  Future<Uint8List> read(int count, Duration deadline) =>
      _native.read(count, deadline);
  @override
  Future<void> write(List<int> bytes, Duration deadline) async {
    writeCount++;
    final codec = StrictCodec();
    Uint8List? substitute;
    try {
      if (authentication == null) {
        validateAuthenticate(codec.decode(bytes.sublist(4), maxBytes: 8192));
        authentication = Uint8List.fromList(bytes);
        if (replay != null) substitute = Uint8List.fromList(replay!);
      } else if (foreignSession != null && !substitutedSession) {
        final document = codec.decode(bytes.sublist(4));
        validateRequestEnvelope(document);
        substitute = Uint8List.fromList(
          frameBytes(codec.encode({...document, 'sessionId': foreignSession})),
        );
      }
      await _native.write(substitute ?? bytes, deadline);
      if (substitute != null) {
        if (replay != null) replayed = true;
        if (foreignSession != null) substitutedSession = true;
      }
    } finally {
      substitute?.fillRange(0, substitute.length, 0);
    }
  }

  @override
  Future<void> close() => _native.close();
  void dispose() {
    final owned = authentication;
    owned?.fillRange(0, owned.length, 0);
    authentication = null;
  }
}
