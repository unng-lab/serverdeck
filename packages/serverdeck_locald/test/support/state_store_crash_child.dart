import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../models_test.dart' as fixture;
import '../credential_validation_test.dart' as credentials;
import 'state_store_child.dart' show check;
import 'api_crash_boundary.dart';
import 'api_crash_markers.dart';

class SwitchableProtection implements UserProtection {
  SwitchableProtection([this.markers]);
  final ApiCrashMarkers? markers;
  final delegate = DpapiProtection();
  bool denyUnprotect = false;
  Future<void> Function()? beforeProtect;
  @override
  Future<List<int>> protect(List<int> cleartext, List<int> entropy) async {
    markers?.observe(cleartext);
    await beforeProtect?.call();
    return delegate.protect(cleartext, entropy);
  }

  @override
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy) async {
    if (denyUnprotect) throw StateError('PROTECTION_UNAVAILABLE');
    final clear = await delegate.unprotect(ciphertext, entropy);
    try {
      markers?.observe(clear);
      return clear;
    } catch (_) {
      clear.fillRange(0, clear.length, 0);
      rethrow;
    }
  }
}

Future<void> blocked(Future<Object?> Function() operation) async {
  try {
    await operation();
  } on StateError catch (error) {
    check(error.message == 'STORAGE_BLOCKED');
    return;
  }
  throw StateError('EXPECTED_STORAGE_BLOCKED');
}

Future<void> main(List<String> arguments) async {
  final root = arguments[0], bundle = arguments[1], mode = arguments[2];
  final sid = currentUserSid(), directory = p.join(root, 'workspace');
  final digest = await Sha256().hash(utf8.encode('synthetic-crash-$root'));
  final name =
      'Global\\ServerDeckNext.v1.${digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  final lease = await MutexLease.acquire(name, sid);
  check(lease.isHeld);
  final apiMode = mode.contains('api-');
  final keyMode = mode.contains('api-key-');
  final markers = apiMode ? ApiCrashMarkers(root, sid) : null;
  final protection = SwitchableProtection(markers);
  final custody = KeyCustody(protection, sid);
  ReceiptKeyMaterial? key;
  StateStore? store;
  Isar? native;
  try {
    await initializeNativeRuntime(bundle);
    if (mode.startsWith('verify-')) {
      key = await custody.openReceiptKey(
        await readProtectedFile(
          root,
          p.join(directory, 'receipt-key.dpapi'),
          sid,
          maxBytes: 16384,
        ),
        fixture.workspace,
        fixture.receiptKeyId,
      );
    } else {
      key = await custody.createReceiptKey(
        fixture.workspace,
        fixture.receiptKeyId,
      );
      createProtectedDirectory(root, directory, sid);
      await writeNewProtectedFile(
        root,
        p.join(directory, 'workspace.manifest.json'),
        sid,
        utf8.encode(jsonEncode(await custody.createWorkspaceManifest(key))),
      );
      await writeNewProtectedFile(
        root,
        p.join(directory, 'receipt-key.dpapi'),
        sid,
        key.wrapper,
      );
      for (final file in ['workspace.isar', 'workspace.isar-lck']) {
        await createProtectedEmptyFile(root, p.join(directory, file), sid);
      }
      native = await Isar.open(
        workspaceSchemas,
        directory: directory,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      final rows = WorkspaceRecords.fromState(
        WorkspaceState.empty(
          workspaceId: fixture.workspace,
          receiptKeyId: fixture.receiptKeyId,
          ownerSid: sid,
        ),
      );
      final initial = native;
      await initial.writeTxn(() async {
        await initial.storedWorkspaces.put(rows.workspace);
        await initial.storedSettings.put(rows.settings);
      });
      check(await native.close());
      native = null;
    }
    store = await StateStore.open(
      localAppData: root,
      directory: directory,
      appRoot: bundle,
      lease: lease,
      custody: custody,
      receiptKey: key,
    );
    if (mode.startsWith('verify-')) {
      final after = mode.endsWith('-after');
      check(store.state.storeRevision == (after ? '1' : '0'));
      check(store.state.profiles.length == (after ? 1 : 0));
      check(store.state.credentials.length == (after ? 1 : 0));
      check(store.state.receipts.length == (after ? 1 : 0));
      if (after) {
        if (apiMode) {
          check(store.state.receipts.containsKey(fixture.requestId));
          check(
            store.state.profiles[fixture.profileId]!.toJson()['name'] ==
                'API crash fixture',
          );
        }
        final credential =
            store.state.credentials[store
                .state
                .profiles[fixture.profileId]!
                .credentialRef]!;
        final clear = await custody.openCredential(
          credential.protectedBlob,
          fixture.workspace,
          fixture.profileId,
          credential.id,
        );
        try {
          if (keyMode) {
            check(
              clear['privateKey'] == crashKey &&
                  clear['passphrase'] == crashPassphrase,
            );
          } else {
            check(clear['password'] == crashPassword);
          }
        } finally {
          clear.clear();
        }
      }
      if (markers != null) {
        await markers.assertCleanTree();
        stdout.writeln('API_CRASH_PRIVATE_MARKERS_CLEAN_PROVED');
      }
      stdout.writeln('CRASH_REOPEN_PROVED');
      if (mode.startsWith('verify-api-'))
        stdout.writeln('API_CRASH_REOPEN_PROVED');
      return;
    }
    if (apiMode) {
      await stopAtApiBoundary(
        store,
        custody,
        key,
        beforeCommit: mode.endsWith('-before'),
        privateKey: keyMode,
        markers: markers!,
        armProtection: (callback) => protection.beforeProtect = callback,
      );
      throw StateError('EXPECTED_PARENT_CRASH');
    }
    final blob = await custody.wrapCredential(
      fixture.workspace,
      fixture.profileId,
      fixture.credentialId,
      {
        'action': 'replace',
        'kind': 'password',
        'password': 'synthetic-crash-secret',
      },
    );
    final next = credentials.state(sid, blob);
    if (mode == 'dpapi') {
      await store.commit(next);
      final value = next.toJson()..['storeRevision'] = '2';
      (value['profiles'] as Map)[fixture.profileId] = {
        ...next.profiles[fixture.profileId]!.toJson(),
        'revision': '2',
        'name': 'After DPAPI availability loss',
      };
      const request2 = '12345678-1234-4234-8234-123456789ac3';
      (value['receipts'] as Map)[request2] = {
        ...fixture.receipt(),
        'requestId': request2,
        'operation': 'profiles.update',
        'result': {
          'entityId': fixture.profileId,
          'entityRevision': '2',
          'storeRevision': '2',
          'deleted': false,
        },
      };
      final candidate = WorkspaceState.fromJson(
        value,
        workspaceId: fixture.workspace,
        receiptKeyId: fixture.receiptKeyId,
        ownerSid: sid,
      );
      final file = File(p.join(directory, 'workspace.isar'));
      final before = file.readAsBytesSync();
      protection.denyUnprotect = true;
      await blocked(() => store!.commit(candidate));
      check(base64.encode(file.readAsBytesSync()) == base64.encode(before));
      await blocked(() async => store!.state);
      protection.denyUnprotect = false;
      await blocked(() => store!.commit(candidate));
      await blocked(() async => store!.state);
      await store.close();
      store = null;
      store = await StateStore.open(
        localAppData: root,
        directory: directory,
        appRoot: bundle,
        lease: lease,
        custody: custody,
        receiptKey: key,
      );
      check(store.state.storeRevision == '1');
      check(!store.state.receipts.containsKey(request2));
      check(store.state.profiles[fixture.profileId]!.name == 'Synthetic');
      stdout.writeln('DPAPI_FAILURE_LATCHED_AND_REOPENED');
      return;
    }
    if (mode == 'failure') {
      // Fixture-only native handle invalidation: an uncertain storage failure
      // must block both the failed request and all subsequent repository use.
      check(await Isar.getInstance('workspace')!.close());

      await blocked(() => store!.commit(next));
      await blocked(() async => store!.state);
      await blocked(() => store!.commit(next));
      await blocked(() => store!.close());
      store = null; // Native instance was already closed by this fault fixture.
      stdout.writeln('UNKNOWN_NATIVE_FAILURE_BLOCKED');
      return;
    }
    Future<void> boundary() async {
      stdout.writeln('CRASH_BOUNDARY');
      await stdout.flush();
      await Completer<void>().future;
    }

    if (mode == 'before') {
      final rows = WorkspaceRecords.fromState(next);
      final active = Isar.getInstance('workspace')!;
      await active.writeTxn(() async {
        await active.storedWorkspaces.put(rows.workspace);
        await active.storedProfiles.putAll(rows.profiles);
        await active.storedCredentials.putAll(rows.credentials);
        await active.storedReceipts.putAll(rows.receipts);
        await boundary();
      });
    } else {
      check(mode == 'after');
      await store.commit(next);
      await boundary();
    }
  } finally {
    await store?.close();
    await native?.close();
    key?.close();
    markers?.close();
    await lease.close();
  }
}
