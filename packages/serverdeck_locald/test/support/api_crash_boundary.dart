import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:serverdeck_locald/api/auth.dart';
import 'package:serverdeck_locald/api/channel.dart';
import 'package:serverdeck_locald/api/server.dart';
import 'package:serverdeck_locald/api/sessions.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/process.dart';

import '../../../../lib/bootstrap/local_api_client.dart';
import '../../../../lib/bootstrap/native_client_transport.dart';
import '../auth_test.dart' as auth;
import '../models_test.dart' as fixture;
import 'state_store_child.dart' show check;
import 'api_crash_markers.dart';

/// Test target only. Production coordinator, router and transport are unchanged.
Future<void> stopAtApiBoundary(
  StateStore store,
  KeyCustody custody,
  ReceiptKeyMaterial key, {
  required bool beforeCommit,
  required bool privateKey,
  required ApiCrashMarkers markers,
  required void Function(Future<void> Function()) armProtection,
}) async {
  final namespace = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final name = '\\\\.\\pipe\\ServerDeckNext.v1.$namespace.0';
  final pipe = await PipeWorker.createServer(name, custody.ownerSid);
  final backend = MutationCoordinator(store, custody, key);
  final sessions = SessionRegistry(
    generation: auth.generation,
    onDetached: backend.detach,
  );
  final image = Platform.resolvedExecutable,
      hash = fileSha256(Platform.resolvedExecutable);
  ServerChannel? channel;
  Future<void>? serving;
  var writes = 0, completed = false;
  final mutationWatch = Stopwatch();
  Future<void> boundary() async {
    check(sessions.count == 1 && writes == 2 && !completed);
    check(mutationWatch.isRunning && mutationWatch.elapsed < rpcDeadline);
    check(store.state.storeRevision == (beforeCommit ? '0' : '1'));
    check(store.state.profiles.length == (beforeCommit ? 0 : 1));
    check(store.state.credentials.length == (beforeCommit ? 0 : 1));
    check(store.state.receipts.length == (beforeCommit ? 0 : 1));
    check(store.state.receipts.containsKey(fixture.requestId) == !beforeCommit);
    await markers.assertCleanTree();
    check(mutationWatch.elapsed < rpcDeadline && !completed);
    stdout.writeln('API_CRASH_PRIVATE_MARKERS_CLEAN_PROVED');
    stdout.writeln(
      beforeCommit
          ? 'API_BEFORE_COMMIT_PROVED'
          : 'API_AFTER_COMMIT_BEFORE_REPLY_PROVED',
    );
    stdout.writeln('CRASH_BOUNDARY');
    await stdout.flush();
    await Completer<void>().future;
  }

  final intent = MutationIntent(ApiMethod.profilesCreate, {
    'profileId': fixture.profileId,
    'name': 'API crash fixture',
    'address': 'api-crash.example.invalid',
    'sshUser': 'synthetic',
    'credential': privateKey
        ? {
            'action': 'replace',
            'kind': 'privateKey',
            'privateKey': crashKey,
            'passphrase': crashPassphrase,
          }
        : {'action': 'replace', 'kind': 'password', 'password': crashPassword},
  }, requestId: fixture.requestId);
  final client = LocalApiClient(
    connect: () async => ClientEndpoint(
      transport: await NativeClientTransport.open(
        pipeName: name,
        ownerSid: custody.ownerSid,
        imagePath: image,
        imageHash: hash,
      ),
      generation: auth.generation,
      buildId: auth.buildId,
      bootstrapToken: List<int>.from(auth.token),
    ),
  );
  try {
    Future<void> serve() async {
      await pipe.accept();
      channel = ServerChannel(
        handshake: ServerHandshake(
          token: auth.token,
          generation: auth.generation,
          buildId: auth.buildId,
          channel: namespace,
          sessions: sessions,
          verifyPeer: () => pipe.verifyPeer(custody.ownerSid, image, hash),
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
        read: (count, deadline) => pipe.read(count: count, deadline: deadline),
        write: (bytes, deadline) async {
          if (!beforeCommit && writes == 2) {
            final reply = StrictCodec().decode(bytes.sublist(4));
            check(reply['id'] == fixture.requestId && reply['error'] == null);
            check((reply['result'] as Map)['storeRevision'] == '1');
            await boundary();
          }
          await pipe.write(bytes, deadline: deadline);
          writes++;
        },
        drainOutput: (deadline) => pipe.drainOutput(deadline: deadline),
        disconnect: pipe.disconnect,
      );
      await channel!.run();
    }

    serving = serve();
    serving.ignore();
    await client.connect();
    if (beforeCommit) armProtection(boundary);
    mutationWatch.start();
    await client.mutate(intent).whenComplete(() => completed = true);
    throw StateError('EXPECTED_PARENT_CRASH');
  } finally {
    intent.dispose();
    await client.close();
    await channel?.close();
    await serving;
    sessions.stop();
    await backend.close();
    await pipe.close();
  }
}
