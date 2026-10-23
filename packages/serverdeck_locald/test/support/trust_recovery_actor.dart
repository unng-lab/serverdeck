import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/owner_api.dart';
import 'package:serverdeck_locald/api/owner_trust_mutations.dart';
import 'package:serverdeck_locald/api/owner_trust_probes.dart';
import 'package:serverdeck_locald/api/trusted_owner_foundation.dart';
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_locald/bootstrap/trusted_services.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/remote/ssh_transport.dart';
import 'package:serverdeck_locald/remote/trust_probes.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'trusted_auth_actor.dart' as a;
import 'trusted_migration_actor.dart' as migration;

const _foundationCollections = {
  'StoredWorkspace',
  'StoredSettings',
  'StoredProfile',
  'StoredCredential',
  'StoredReceipt',
  'StoredHostTrust',
};
String id(int n) => '60000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Future<String> digest(Object? value) async =>
    (await Sha256().hash(utf8.encode(jsonEncode(value)))).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
List<Object?> rows(StateStore store, String name) => [
  for (final row in store.trustedOperational.rows[name]!)
    [row.nativeId, row.entityId, row.payload],
];
Map<String, Object?> graph(StateStore store) => {
  for (final name in store.trustedOperational.rows.keys)
    if (!_foundationCollections.contains(name)) name: rows(store, name),
};

/// Every phase is an independent OS process over the same protected workspace.
/// The preparer supplies the already-qualified, nonempty historical graph.
Future<void> exercise(String root, String phase, String mode) async {
  a.ownRoot(root);
  containCurrentFixtureTree();
  await initializeTrustedNativeRuntime(root);
  final sid = currentUserSid();
  final custody = KeyCustody(DpapiProtection(), sid);
  final expected = jsonDecode(
    File(p.join(root, 'fixture-expected.json')).readAsStringSync(),
  ) as Map;
  final directory = p.join(
    root,
    'ServerDeckNext',
    'v1',
    'workspaces',
    'default',
  );
  final key = await custody.openReceiptKey(
    await readProtectedFile(
      root,
      p.join(directory, 'receipt-key.dpapi'),
      sid,
      maxBytes: 16384,
    ),
    expected['workspaceId'] as String,
    expected['receiptKeyId'] as String,
  );
  final namespace = (await Sha256().hash(utf8.encode(root))).bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.$namespace',
    sid,
  );
  StateStore? store;
  a.Pair? owner;
  final plain = TrustedSessions(generation: a.generation);
  final pool = SshTransportPool();
  TrustedFoundationOwnerApi? foundation;
  HostTrustProbeService? probes;
  TrustMutationOwnerApi? writes;
  TrustedControlServices? control;
  TrustedOwnerApi? api;
  Process? ssh;
  StreamIterator<String>? sshLines;
  Future<String>? sshErrors;
  Object? firstError;
  StackTrace? firstStack;
  Future<StateStore> open() => StateStore.openTrustedOperational(
    localAppData: root,
    appRoot: root,
    custody: custody,
    receiptKey: key,
    lease: lease,
  );
  Future<void> closeServices() async {
    Object? failure;
    StackTrace? stack;
    for (final close in <Future<void> Function()>[
      () async => control?.close(),
      () async => writes?.close(),
      () async => foundation?.close(),
      () async => probes?.close(),
    ]) {
      try {
        await close();
      } catch (error, trace) {
        failure ??= error;
        stack ??= trace;
      }
    }
    writes = null;
    control = null;
    foundation = null;
    probes = null;
    api = null;
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }

  Future<void> makeServices() async {
    final state = store!, sessions = owner!.registry;
    if (phase == 'verify') {
      api = control = await TrustedControlServices.create(
        store: state,
        custody: custody,
        receiptKey: key,
        sessions: sessions,
      );
      return;
    }
    final queue = TrustedMutationCoordinator(state, custody, key);
    foundation = TrustedFoundationOwnerApi(
      store: state,
      coordinator: queue,
      sessions: sessions,
    );
    final service = probes = HostTrustProbeService(
      store: state,
      sessions: sessions,
      transports: pool,
    );
    writes = TrustMutationOwnerApi(service: service, coordinator: queue);
    api = TrustedOwnerApiGroup([
      foundation!,
      TrustProbeOwnerApi(service),
      writes!,
    ]);
  }

  var requestCounter = 1000;
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final pair = owner!;
    final request = await pair.registry.begin(
      pair.channel,
      pair.response!.sessionId,
      method,
    );
    try {
      return await api!.dispatch(
        request,
        method,
        body,
        requestId: requestId ?? id(requestCounter++),
      );
    } finally {
      request.complete();
    }
  }

  Future<Map<String, Object?>> challenge(
    String server,
    String operation,
  ) async {
    final profile = store!.state.profiles[server]!;
    await call('servers.trust.probe', {
      'profileId': server,
      'expectedRevision': profile.revision,
    }, requestId: operation);
    final watch = Stopwatch()..start();
    Map<String, Object?> result;
    do {
      a.check(watch.elapsed < const Duration(seconds: 5));
      result = await call('servers.trust.probeStatus', {
        'operationId': operation,
      });
      if (result['state'] == 'running')
        await Future<void>.delayed(const Duration(milliseconds: 5));
    } while (result['state'] == 'running');
    a.check(result['state'] == 'succeeded' && pool.activeTransports == 0);
    final value = result['challenge'] as Map;
    return {
      'profileId': server,
      'expectedRevision': profile.revision,
      'challengeId': value['challengeId'],
      'key': value['key'],
    };
  }

  Map<String, Object?> update(String server) {
    final profile = store!.state.profiles[server]!.toJson();
    return {
      'profileId': server,
      'expectedRevision': profile['revision'],
      for (final field in ['name', 'address', 'port', 'sshUser', 'tags'])
        field: profile[field],
      'credential': {'action': 'keep'},
    };
  }

  try {
    store = await open();
    owner = await a.Pair.start(root, 'serverdeck.exe', plain, nativeGate: true);
    await owner.exchange();
    a.check(await owner.next() == 'AUTH:owner');
    await makeServices();
    if (phase == 'verify') {
      final saved = jsonDecode(
        File(p.join(root, 'trust-recovery.fixture.json')).readAsStringSync(),
      ) as Map;
      final body = Map<String, Object?>.from(saved['body'] as Map);
      final server = body['profileId'] as String;
      final before = store.state.toJson();
      final beforeRows = store.trustedOperational.preservationDigest();
      final pin = store.trustedOperational.foundation.trust[server]!.toJson();
      a.check(control != null);
      await a.fails(
        call('servers.trust.probeStatus', {'operationId': saved['probeId']}),
        'NOT_FOUND',
      );
      final result = await call(
        'servers.trust.confirm',
        body,
        requestId: saved['requestId'] as String,
      );
      a.check(
        base64Encode(StrictCodec().canonical(result)) ==
            base64Encode(StrictCodec().canonical(saved['result'])),
      );
      a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
      a.check(store.trustedOperational.preservationDigest() == beforeRows);
      a.check(
        jsonEncode(
              store.trustedOperational.foundation.trust[server]!.toJson(),
            ) ==
            jsonEncode(pin),
      );
      a.check(await digest(graph(store)) == saved['graphDigest']);
      a.check(
        jsonEncode(rows(store, 'StoredCredential')) == saved['credentials'],
      );
      a.check(jsonEncode(rows(store, 'StoredSettings')) == saved['settings']);
      a.check(
        store.trustedOperational.rows['StoredProfile']!.single.nativeId ==
            saved['profileNativeId'],
      );
      for (final old in (saved['receipts'] as List)) {
        final row = store.trustedOperational.rows['StoredReceipt']!.singleWhere(
          (r) => r.entityId == (old as List)[1],
        );
        a.check(
          jsonEncode([row.nativeId, row.entityId, row.payload]) ==
              jsonEncode(old),
        );
      }
      await a.fails(
        call('servers.trust.confirm', {
          ...body,
          'expectedRevision': store.state.profiles[server]!.revision,
        }),
        'TRUST_REQUIRED',
      );
      final revokeBody = <String, Object?>{
        'profileId': server,
        'expectedRevision': store.state.profiles[server]!.revision,
      };
      final revoked = await call(
        'servers.trust.revoke',
        revokeBody,
        requestId: id(31),
      );
      await call('profiles.delete', {
        'profileId': server,
        'expectedRevision': revoked['entityRevision'],
      });
      final revision = store.state.storeRevision;
      a.check(
        jsonEncode(
              await call(
                'servers.trust.confirm',
                body,
                requestId: saved['requestId'] as String,
              ),
            ) ==
            jsonEncode(result),
      );
      a.check(
        jsonEncode(
              await call('servers.trust.revoke', revokeBody, requestId: id(31)),
            ) ==
            jsonEncode(revoked),
      );
      a.check(
        store.state.storeRevision == revision &&
            !store.state.profiles.containsKey(server) &&
            store.trustedOperational.foundation.trust.isEmpty,
      );
      a.check(await digest(graph(store)) == saved['graphDigest']);
      a.check(pool.activeTransports == 0);
      return;
    }
    final originalGraph = graph(store);
    a.check(
      originalGraph.length == 10 &&
          originalGraph.values.every((rows) => (rows as List).isNotEmpty),
    );
    final preserved = <String, Object?>{
      'graphDigest': await digest(originalGraph),
      'credentials': jsonEncode(rows(store, 'StoredCredential')),
      'settings': jsonEncode(rows(store, 'StoredSettings')),
      'receipts': rows(store, 'StoredReceipt'),
      'profileNativeId':
          store.trustedOperational.rows['StoredProfile']!.single.nativeId,
    };
    final python = Platform.environment['SERVERDECK_TRUST_FIXTURE_PYTHON'];
    if (python == null) throw StateError('TRUST_FIXTURE_PREREQUISITE');
    ssh = await Process.start(python, [
      '-I',
      p.absolute('test/support/ssh_key_probe_server.py'),
    ]);
    sshErrors = ssh.stderr.transform(utf8.decoder).join();
    sshLines = StreamIterator(
      ssh.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    a.check(await sshLines.moveNext().timeout(const Duration(seconds: 8)));
    final metadata = jsonDecode(sshLines.current) as Map;
    final server = store.state.profiles.keys.single;
    await call('profiles.update', {
      ...update(server),
      'address': '127.0.0.1',
      'port': metadata['port'],
    });
    var body = await challenge(server, id(11));
    a.check(jsonEncode(body['key']) == jsonEncode(metadata['key']));
    final committedId = id(10);
    Map<String, Object?>? result;
    if (mode == 'uncertain') {
      final db = Isar.getInstance('workspace')!;
      final bad = StoredAutomationEvent()
        ..entityId = '${id(90)}:1'
        ..payload = '{}';
      final nativeId = await db.writeTxn(
        () => db.storedAutomationEvents.put(bad),
      );
      try {
        await a.fails(
          call('servers.trust.confirm', body, requestId: committedId),
          'STORAGE_BLOCKED',
        );
        a.check(!store.isTrustedSnapshotLoaded);
        final receipts = await db.storedReceipts.where().findAll();
        result = Map<String, Object?>.from(
          (jsonDecode(
                receipts.singleWhere((r) => r.entityId == committedId).payload,
              ) as Map)['result']
              as Map,
        );
        a.check(result['entityRevision'] != body['expectedRevision']);
        final rawRevision = (await db.storedWorkspaces.get(1))!.payload;
        await a.fails(
          call('servers.trust.confirm', body, requestId: committedId),
          'STORAGE_BLOCKED',
        );
        a.check((await db.storedWorkspaces.get(1))!.payload == rawRevision);
        a.check((await db.storedHostTrusts.where().findAll()).length == 1);
      } finally {
        a.check(
          await db.writeTxn(() => db.storedAutomationEvents.delete(nativeId)),
        );
      }
      // Repairing the owned corrupt fixture row cannot unblock this instance.
      await a.fails(
        call('servers.trust.confirm', body, requestId: committedId),
        'STORAGE_BLOCKED',
      );
    } else {
      result = await call(
        'servers.trust.confirm',
        body,
        requestId: committedId,
      );
      a.check(
        (await call('servers.trust.probeCancel', {
              'operationId': id(11),
            }))['cancelled'] ==
            false,
      );
    }
    if (mode.startsWith('busy-')) {
      final originalBody = body, originalResult = result;
      await closeServices();
      await store.close();
      store = null;
      final db = await Isar.open(
        trustedWorkspaceSchemas,
        directory: directory,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      try {
        await db.writeTxn(() async {
          final row = (await db.storedAutomationJobs.where().findAll()).single;
          final value = jsonDecode(row.payload) as Map;
          value['state'] = mode.substring('busy-'.length);
          value['cancelRequested'] = false;
          value['nextSequence'] = 1;
          value['outcome'] = mode == 'busy-unknown'
              ? {
                  'effects': 'uncertain',
                  'checks': <Object?>[],
                  'safeCode': 'UNKNOWN_OUTCOME',
                }
              : null;
          row.payload = jsonEncode(value);
          await db.storedAutomationJobs.put(row);
          await db.storedDesiredStates.clear();
          await db.storedAutomationEvents.clear();
        });
      } finally {
        a.check(await db.close());
      }
      store = await open();
      await makeServices();
      final before = store.trustedOperational.preservationDigest();
      body = await challenge(server, id(21));
      for (var n = 0; n < 2; n++) {
        await a.fails(
          call('servers.trust.confirm', body, requestId: id(22)),
          'HOST_BUSY',
        );
      }
      await a.fails(
        call('servers.trust.revoke', {
          'profileId': server,
          'expectedRevision': store.state.profiles[server]!.revision,
        }),
        'HOST_BUSY',
      );
      a.check(store.trustedOperational.preservationDigest() == before);
      a.check(
        jsonEncode(
              await call(
                'servers.trust.confirm',
                originalBody,
                requestId: committedId,
              ),
            ) ==
            jsonEncode(originalResult),
      );
      a.check(
        (await call('servers.trust.probeCancel', {
              'operationId': id(21),
            }))['cancelled'] ==
            true,
      );
      await a.fails(call('servers.trust.confirm', body), 'TRUST_REQUIRED');
      final busyGraph = await digest(graph(store));
      final oldTrust = store.trustedOperational.foundation.trust[server]!
          .toJson();
      await call('profiles.update', {
        ...update(server),
        'name': 'Metadata while occupied',
      });
      a.check(await digest(graph(store)) == busyGraph);
      a.check(
        jsonEncode(
              store.trustedOperational.foundation.trust[server]!.toJson(),
            ) ==
            jsonEncode(oldTrust),
      );
      return;
    }
    if (mode == 'normal') {
      await call('servers.trust.revoke', {
        'profileId': server,
        'expectedRevision': result['entityRevision'],
      });
    }
    final settled = Stopwatch()..start();
    while (true) {
      ssh.stdin.writeln('stats');
      a.check(await sshLines.moveNext().timeout(const Duration(seconds: 3)));
      final stats = jsonDecode(sshLines.current) as Map;
      a.check(stats['authentication'] == 0 && stats['accepted'] >= 1);
      if (stats['active'] == 0) break;
      a.check(settled.elapsed < const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    File(p.join(root, 'trust-recovery.fixture.json')).writeAsStringSync(
      jsonEncode({
        ...preserved,
        'body': body,
        'requestId': committedId,
        'probeId': id(11),
        'result': result,
      }),
      flush: true,
    );
    if (mode == 'crash') {
      stdout.writeln('BOUNDARY:trust-committed');
      await stdout.flush();
      await Completer<void>().future;
    }
  } catch (error, stack) {
    firstError = error;
    firstStack = stack;
  } finally {
    for (final cleanup in <Future<void> Function()>[
      closeServices,
      pool.close,
      () async => owner?.registry.close(),
      () async => owner?.close(),
      () async => store?.close(),
      () async {
        plain.stop();
      },
      () async {
        key.close();
      },
      lease.close,
      () async {
        final process = ssh, lines = sshLines;
        if (process == null || lines == null) return;
        process.stdin.writeln('stats');
        try {
          a.check(await lines.moveNext().timeout(const Duration(seconds: 3)));
          final stats = jsonDecode(lines.current) as Map;
          a.check(stats['authentication'] == 0 && stats['accepted'] >= 1);
        } finally {
          process.stdin.writeln('close');
          await process.stdin.close();
          try {
            await process.exitCode.timeout(const Duration(seconds: 5));
          } on TimeoutException {
            process.kill();
            await process.exitCode;
          }
          await lines.cancel();
          a.check((await sshErrors!).isEmpty);
        }
      },
    ]) {
      try {
        await cleanup();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}

Future<void> main(List<String> args) async {
  if (args.first != 'client' &&
      (args[1] == 'prepare2' || args[1] == 'upgrade')) {
    await migration.main([args[0], args[1] == 'upgrade' ? 'verify' : args[1]]);
    if (exitCode == 0) stdout.writeln('PASS:${args[1]}');
    return;
  }
  try {
    if (args.first == 'client') {
      containCurrentFixtureTree();
      await a.client(args);
      return;
    }
    await exercise(args[0], args[1], args[2]);
    stdout.writeln('PASS:${args[1]}:${args[2]}');
  } catch (error, stack) {
    stderr.writeln('TRUST_RECOVERY_FAILED:${error.runtimeType}');
    stderr.writeln(stack.toString().split('\n').take(8).join('\n'));
    exitCode = 1;
  }
}
