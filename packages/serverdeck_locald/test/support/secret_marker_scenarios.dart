import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/server.dart';
import 'package:serverdeck_locald/api/sessions.dart';
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import 'private_marker_scan.dart';
import 'state_store_child.dart' show check;

const markerInput = String.fromEnvironment('SERVERDECK_TEST_MARKERS_BASE64');
const passwordProfile = 'a2345678-1234-4234-8234-123456789ab1';
const keyProfile = 'a2345678-1234-4234-8234-123456789ab2';
const generation = 'c2345678-1234-4234-8234-123456789abc';

class ObservedDpapi implements UserProtection {
  ObservedDpapi(this.scan, this.beforeProtect);
  final PrivateMarkerScan scan;
  final Future<void> Function() beforeProtect;
  final delegate = DpapiProtection();
  var protectedCalls = 0;
  bool receiptObserved = false;
  void observe(List<int> clear) {
    final value = StrictCodec().decode(clear, maxBytes: 256 * 1024);
    if (value['receiptKey'] case final String secret when !receiptObserved) {
      scan.addSecretBytes(base64.decode(secret));
      receiptObserved = true;
    }
  }

  @override
  Future<List<int>> protect(List<int> clear, List<int> entropy) async {
    observe(clear);
    await beforeProtect();
    final protected = await delegate.protect(clear, entropy);
    scan.assertCleanBytes(protected);
    protectedCalls++;
    return protected;
  }

  @override
  Future<List<int>> unprotect(List<int> value, List<int> entropy) async {
    final clear = await delegate.unprotect(value, entropy);
    try {
      observe(clear);
      return clear;
    } catch (_) {
      clear.fillRange(0, clear.length, 0);
      rethrow;
    }
  }
}

Future<void> run(String root, String bundle, {required bool verify}) async {
  check(markerInput.isNotEmpty);
  final inputs = StrictCodec().decode(
    base64.decode(markerInput),
    maxBytes: 4096,
  );
  final scan = PrivateMarkerScan();
  MutexLease? lease;
  Workspace? workspace;
  MutationCoordinator? backend;
  SessionRegistry? sessions;
  var metadataCloseConfirmed = true;
  try {
    check(inputs.keys.toSet().length == 7);
    for (final name in [
      'name',
      'address',
      'sshUser',
      'tag',
      'password',
      'privateKey',
      'passphrase',
    ]) {
      check(inputs[name] is String && (inputs[name] as String).isNotEmpty);
    }
    for (final name in ['password', 'privateKey', 'passphrase']) {
      scan.addSecretText(inputs[name] as String);
    }
    final keyBody = (inputs['privateKey'] as String)
        .split('\n')
        .where((line) => line.isNotEmpty && !line.startsWith('-----'))
        .join();
    scan.addSecretText(keyBody);
    scan.addSecretBytes(base64.decode(keyBody));
    final sid = currentUserSid();
    final digest = await Sha256().hash(utf8.encode('secret-marker-$root'));
    final acquiredLease = await MutexLease.acquire(
      'Global\\ServerDeckNext.v1.${digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
      sid,
    );
    lease = acquiredLease;
    check(acquiredLease.isHeld);
    final active = p.join(
      root,
      'ServerDeckNext',
      'v1',
      'workspaces',
      'default',
    );
    Future<void> scanTree() async {
      requireSafePath(root, root);
      for (final entry in Directory(
        root,
      ).listSync(recursive: true, followLinks: false)) {
        requireSafePath(root, entry.path);
        requireOwnerOnlyFileAcl(entry.path, sid);
        final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
        check(
          type == FileSystemEntityType.file ||
              type == FileSystemEntityType.directory,
        );
        if (type == FileSystemEntityType.file) {
          await scan.assertCleanFile(File(entry.path));
        }
      }
    }

    final protection = ObservedDpapi(scan, scanTree);
    final custody = KeyCustody(protection, sid);
    if (verify) {
      // Never let a missing persisted workspace become a new empty fixture.
      requireSafePath(root, active);
      requireOwnerOnlyFileAcl(active, sid);
      for (final name in [
        'workspace.isar',
        'workspace.isar-lck',
        'receipt-key.dpapi',
        'workspace.manifest.json',
      ]) {
        requireSafePath(root, p.join(active, name));
        requireOwnerOnlyFileAcl(p.join(active, name), sid);
        check(
          FileSystemEntity.typeSync(p.join(active, name), followLinks: false) ==
              FileSystemEntityType.file,
        );
      }
      await initializeNativeRuntime(bundle);
      metadataCloseConfirmed = false;
      final native = await Isar.open(
        workspaceSchemas,
        directory: active,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      try {
        final profiles = await native.storedProfiles.where().findAll();
        check(profiles.length == 2);
        for (final row in profiles) {
          final payload = StrictCodec().decode(utf8.encode(row.payload));
          for (final name in ['name', 'address', 'sshUser']) {
            check(payload[name] == inputs[name]);
          }
          check((payload['tags'] as List).single == inputs['tag']);
          scan.assertCleanBytes(utf8.encode(row.payload));
        }
        final settings = StrictCodec().decode(
          utf8.encode((await native.storedSettings.get(1))!.payload),
        );
        check(
          settings['theme'] == 'dark' &&
              settings['reduceMotion'] == true &&
              settings['selectedProfileId'] == keyProfile,
        );
      } finally {
        metadataCloseConfirmed = await native.close();
        check(metadataCloseConfirmed);
      }
    }
    workspace = await Workspace.open(
      localAppData: root,
      appRoot: bundle,
      lease: acquiredLease,
      custody: custody,
    );
    final store = workspace.store;
    backend = MutationCoordinator(store, custody, workspace.receiptKey);
    final currentBackend = backend;
    final session = base64Url.encode(List.filled(32, 42)).replaceAll('=', '');
    sessions = SessionRegistry(
      generation: generation,
      onDetached: currentBackend.detach,
    )..register('owned', session, Capability.values.toSet());
    final server = ApiServer(
      sessions: sessions,
      readiness: () => ReadinessView(
        state: ReadinessState.ready,
        reason: null,
        workspaceId: store.state.workspaceId,
        generation: generation,
      ),
      coordinator: () => currentBackend,
    );
    var number = 0;
    void publicShape(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          check(
            !{
              'password',
              'privateKey',
              'passphrase',
              'protectedBlob',
              'credentialRef',
              'receiptKey',
            }.contains(entry.key),
          );
          publicShape(entry.value);
        }
      } else if (value is List) {
        for (final item in value) {
          publicShape(item);
        }
      }
    }

    Future<Map<String, Object?>> call(
      String method,
      Map<String, Object?> params, {
      String? error,
    }) async {
      final id =
          'b2345678-1234-4234-8234-${(++number).toRadixString(16).padLeft(12, '0')}';
      final response = await server.handle(
        'owned',
        StrictCodec().encode(
          ApiRequest(
            id: id,
            sessionId: session,
            method: method,
            params: params,
          ).toJson(),
        ),
      );
      scan.assertCleanBytes(response.bytes);
      final envelope = StrictCodec().decode(response.bytes);
      publicShape(envelope);
      if (error != null) {
        check((envelope['error'] as Map)['code'] == error);
        return envelope;
      }
      check(envelope['error'] == null);
      final result = envelope['result'] as Map<String, Object?>;
      validateMethodResult(method, result);
      return result;
    }

    if (!verify) {
      for (final id in [passwordProfile, keyProfile]) {
        await call('profiles.create', {
          'profileId': id,
          'name': inputs['name'],
          'address': inputs['address'],
          'sshUser': inputs['sshUser'],
          'tags': [inputs['tag']],
          'credential': id == passwordProfile
              ? {
                  'action': 'replace',
                  'kind': 'password',
                  'password': inputs['password'],
                }
              : {
                  'action': 'replace',
                  'kind': 'privateKey',
                  'privateKey': inputs['privateKey'],
                  'passphrase': inputs['passphrase'],
                },
        });
        await scanTree();
      }
      await call('settings.update', {
        'expectedRevision': '1',
        'theme': 'dark',
        'reduceMotion': true,
        'selectedProfileId': keyProfile,
      });
      await scanTree();
      check(protection.protectedCalls == 3 && protection.receiptObserved);
    }
    check(
      store.state.storeRevision == '3' &&
          store.state.profiles.length == 2 &&
          store.state.credentials.length == 2 &&
          store.state.receipts.length == 3,
    );
    await call('profiles.list', {});
    for (final id in [passwordProfile, keyProfile]) {
      await call('profiles.get', {'profileId': id});
      final profile = store.state.profiles[id]!;
      final credential = store.state.credentials[profile.credentialRef]!;
      final secret = await custody.openCredential(
        credential.protectedBlob,
        store.state.workspaceId,
        id,
        credential.id,
      );
      try {
        if (id == passwordProfile) {
          check(secret['password'] == inputs['password']);
        } else {
          check(
            secret['privateKey'] == inputs['privateKey'] &&
                secret['passphrase'] == inputs['passphrase'],
          );
        }
      } finally {
        secret.clear();
      }
    }
    await call('settings.get', {});
    await call('mutations.recent', {'limit': 20});
    await call('jobs.start', {
      'password': inputs['password'],
      'privateKey': inputs['privateKey'],
      'passphrase': inputs['passphrase'],
    }, error: 'UNSUPPORTED');
    sessions.stop();
    sessions = null;
    await backend.close();
    backend = null;
    await workspace.close();
    workspace = null;
    check(protection.receiptObserved);
    await scanTree();
    stdout.writeln(
      verify
          ? 'PRIVATE_MARKER_REOPEN_PROVED'
          : 'PRIVATE_MARKER_PERSISTENCE_PROVED',
    );
  } finally {
    try {
      sessions?.stop();
      await backend?.close();
      await workspace?.close();
    } finally {
      try {
        if (lease?.isHeld == true &&
            (!metadataCloseConfirmed || Workspace.hasOpenReservation)) {
          throw StateError('STORAGE_BLOCKED');
        }
        await lease?.close();
      } finally {
        scan.close();
        inputs.clear();
      }
    }
  }
}
