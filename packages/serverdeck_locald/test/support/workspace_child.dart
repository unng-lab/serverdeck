import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:serverdeck_protocol/codec.dart';

import 'state_store_child.dart' show check, rejects;
import 'workspace_reparse_scenarios.dart';
import 'workspace_schema_scenarios.dart';

Future<void> main(List<String> arguments) async {
  final root = arguments[0], bundle = arguments[1], sid = currentUserSid();
  final digest = await Sha256().hash(utf8.encode('synthetic-workspace-$root'));
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.${digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
    sid,
  );
  final custody = KeyCustody(DpapiProtection(), sid);
  Workspace? owned;
  final local = p.join(root, 'creation');
  Directory(local).createSync();
  final active = p.join(local, 'ServerDeckNext', 'v1', 'workspaces', 'default');
  final pending = '$active.creating';
  Future<Workspace> open() => Workspace.open(
    localAppData: local,
    appRoot: bundle,
    lease: lease,
    custody: custody,
  );
  try {
    check(lease.isHeld);
    final first = open(), second = open();
    await rejects(second, 'STORAGE_BLOCKED');
    owned = await first;
    check(owned.store.state.isInitialEmpty);
    check(Directory(active).existsSync());
    check(!Directory(pending).existsSync());
    final identity = owned.store.state.workspaceId;
    final receiptIdentity = owned.receiptKey.receiptKeyId;
    check(
      RegExp(
        r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
      ).hasMatch(identity),
    );
    check(identity != receiptIdentity);
    for (final file in [
      'workspace.manifest.json',
      'receipt-key.dpapi',
      'workspace.isar',
      'workspace.isar-lck',
    ]) {
      requireOwnerOnlyFileAcl(p.join(active, file), sid);
    }
    final keyBytes = File(p.join(active, 'receipt-key.dpapi'))
        .readAsBytesSync();
    await Future.wait([owned.close(), owned.close()]);
    owned = null;
    owned = await open();
    check(owned.store.state.workspaceId == identity);
    check(base64.encode(owned.receiptKey.wrapper) == base64.encode(keyBytes));
    await owned.close();
    owned = null;

    // This fixture moves a complete empty active directory back into staging,
    // reproducing the persisted pre-promotion state without production hooks.
    await promoteProtectedPath(local, active, pending, sid);
    owned = await open();
    check(owned.store.state.workspaceId == identity);
    check(!Directory(pending).existsSync());
    await owned.close();
    owned = null;
    createProtectedDirectory(local, pending, sid);
    await rejects(open(), 'STORAGE_BLOCKED');
    check(Directory(active).existsSync() && Directory(pending).existsSync());
    check(
      base64.encode(
            File(p.join(active, 'receipt-key.dpapi')).readAsBytesSync(),
          ) ==
          base64.encode(keyBytes),
    );

    for (final mode in [
      'partial-stage',
      'missing-manifest',
      'missing-key',
      'missing-database',
      'missing-lock',
      'unknown-schema',
      'damaged-key',
      'wrong-valid-key',
      'manifest-workspace-identity',
      'manifest-receipt-identity',
      'damaged-database',
      'receipt-format',
      'receipt-product',
      'receipt-owner',
      'manifest-owner',
      'nonempty-stage',
    ]) {
      final caseRoot = p.join(root, mode);
      Directory(caseRoot).createSync();
      final directory = p.join(
        caseRoot,
        'ServerDeckNext',
        'v1',
        'workspaces',
        'default',
      );
      Future<Workspace> caseOpen() => Workspace.open(
        localAppData: caseRoot,
        appRoot: bundle,
        lease: lease,
        custody: custody,
      );
      if (mode == 'partial-stage') {
        for (final path in [
          p.dirname(p.dirname(p.dirname(directory))),
          p.dirname(p.dirname(directory)),
          p.dirname(directory),
          '$directory.creating',
        ]) {
          createProtectedDirectory(caseRoot, path, sid);
        }
        final marker = p.join('$directory.creating', 'receipt-key.dpapi');
        await writeNewProtectedFile(caseRoot, marker, sid, [1, 2, 3]);
        await rejects(caseOpen(), 'STORAGE_BLOCKED');
        check(!Directory(directory).existsSync());
        check(base64.encode(File(marker).readAsBytesSync()) == 'AQID');
        continue;
      }
      owned = await caseOpen();
      final settings = owned.store.state.settings.toJson();
      await owned.close();
      owned = null;
      const missing = {
        'missing-manifest': 'workspace.manifest.json',
        'missing-key': 'receipt-key.dpapi',
        'missing-database': 'workspace.isar',
        'missing-lock': 'workspace.isar-lck',
      };
      if (missing.containsKey(mode)) {
        await promoteProtectedPath(
          caseRoot,
          p.join(directory, missing[mode]!),
          p.join(p.dirname(directory), 'preserved-${missing[mode]}'),
          sid,
        );
      } else if (mode == 'unknown-schema') {
        final path = p.join(directory, 'workspace.manifest.json');
        final value = StrictCodec().decode(File(path).readAsBytesSync());
        value['schema'] = 2;
        await replaceProtectedFile(
          caseRoot,
          path,
          sid,
          StrictCodec().encode(value),
        );
      } else if (mode.startsWith('manifest-')) {
        final path = p.join(directory, 'workspace.manifest.json');
        final value = StrictCodec().decode(File(path).readAsBytesSync());
        final field = mode == 'manifest-owner'
            ? 'ownerSid'
            : mode == 'manifest-workspace-identity'
            ? 'workspaceId'
            : 'receiptKeyId';
        final replacement = mode == 'manifest-owner'
            ? (sid == 'S-1-5-18' ? 'S-1-5-19' : 'S-1-5-18')
            : 'f2345678-1234-4234-8234-123456789abc';
        check(value[field] != replacement);
        value[field] = replacement;
        await replaceProtectedFile(
          caseRoot,
          path,
          sid,
          StrictCodec().encode(value),
        );
      } else if (mode.startsWith('receipt-')) {
        final path = p.join(directory, 'receipt-key.dpapi');
        final protection = DpapiProtection();
        final entropy = utf8.encode(
          'ServerDeckNext\nv1\ndefault\n$sid\nreceipt',
        );
        final cleartext = await protection.unprotect(
          File(path).readAsBytesSync(),
          entropy,
        );
        List<int>? modified;
        try {
          final value = StrictCodec().decode(cleartext, maxBytes: 8192);
          final field = mode == 'receipt-format'
              ? 'format'
              : mode == 'receipt-product'
              ? 'product'
              : 'ownerSid';
          value[field] = mode == 'receipt-format'
              ? 2
              : mode == 'receipt-product'
              ? 'synthetic-other-product'
              : (sid == 'S-1-5-18' ? 'S-1-5-19' : 'S-1-5-18');
          modified = StrictCodec().encode(value, maxBytes: 8192);
          final wrapper = await protection.protect(modified, entropy);
          final reopened = await protection.unprotect(wrapper, entropy);
          try {
            check(base64.encode(reopened) == base64.encode(modified));
          } finally {
            reopened.fillRange(0, reopened.length, 0);
          }
          await replaceProtectedFile(caseRoot, path, sid, wrapper);
        } finally {
          cleartext.fillRange(0, cleartext.length, 0);
          modified?.fillRange(0, modified.length, 0);
        }
      } else if (mode == 'wrong-valid-key') {
        const foreignWorkspace = 'e2345678-1234-4234-8234-123456789abc';
        const foreignReceipt = 'd2345678-1234-4234-8234-123456789abc';
        final foreign = await custody.createReceiptKey(
          foreignWorkspace,
          foreignReceipt,
        );
        try {
          // Prove the wrapper is valid real DPAPI material for its own IDs,
          // rather than another malformed-ciphertext negative.
          final validated = await custody.openReceiptKey(
            foreign.wrapper,
            foreignWorkspace,
            foreignReceipt,
          );
          validated.close();
          await replaceProtectedFile(
            caseRoot,
            p.join(directory, 'receipt-key.dpapi'),
            sid,
            foreign.wrapper,
          );
        } finally {
          foreign.close();
        }
      } else if (mode == 'damaged-database') {
        await replaceProtectedFile(
          caseRoot,
          p.join(directory, 'workspace.isar'),
          sid,
          [1, 2, 3],
        );
      } else if (mode == 'nonempty-stage') {
        // A structurally valid workspace with non-default settings cannot be
        // promoted as an initial-empty staging directory.
        final native = await Isar.open(
          workspaceSchemas,
          directory: directory,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        settings['theme'] = 'dark';
        await native.writeTxn(() async {
          await native.storedSettings.put(
            StoredSettings()
              ..payload = utf8.decode(StrictCodec().encode(settings)),
          );
        });
        check(await native.close());
        await promoteProtectedPath(
          caseRoot,
          directory,
          '$directory.creating',
          sid,
        );
      } else {
        await replaceProtectedFile(
          caseRoot,
          p.join(directory, 'receipt-key.dpapi'),
          sid,
          [1, 2, 3],
        );
      }
      final inspected = mode == 'nonempty-stage'
          ? '$directory.creating'
          : directory;
      Map<String, String> snapshot() => {
        for (final file in Directory(inspected).listSync().whereType<File>())
          if (mode != 'nonempty-stage' ||
              p.basename(file.path) != 'workspace.isar')
            p.basename(file.path): base64.encode(file.readAsBytesSync()),
      };
      final before = snapshot();
      await rejects(
        caseOpen(),
        mode == 'unknown-schema' || mode == 'receipt-format'
            ? 'INCOMPATIBLE'
            : 'STORAGE_BLOCKED',
      );
      final after = snapshot();
      check(
        before.length == after.length &&
            before.entries.every((e) => after[e.key] == e.value),
      );
      check(
        Directory('$directory.creating').existsSync() ==
            (mode == 'nonempty-stage'),
      );
      if (mode == 'wrong-valid-key' ||
          mode == 'manifest-workspace-identity' ||
          mode == 'manifest-receipt-identity' ||
          mode == 'damaged-database') {
        stdout.writeln(
          'WORKSPACE_IDENTITY_CORRUPTION_CASE_${mode.toUpperCase().replaceAll('-', '_')}',
        );
      }
      if (mode.startsWith('receipt-') || mode == 'manifest-owner') {
        stdout.writeln(
          'WORKSPACE_WRAPPER_METADATA_CASE_${mode.toUpperCase().replaceAll('-', '_')}',
        );
      }
      if (mode == 'nonempty-stage') {
        // Native open/close may update MDBX meta pages. The rejected staging
        // must retain its application rows, files, manifest and DPAPI wrapper.
        check(!Directory(directory).existsSync());
        final native = await Isar.open(
          workspaceSchemas,
          directory: inspected,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        check((await native.storedSettings.count()) == 1);
        check((await native.storedWorkspaces.count()) == 1);
        check((await native.storedProfiles.count()) == 0);
        check((await native.storedCredentials.count()) == 0);
        check((await native.storedReceipts.count()) == 0);
        check(
          StrictCodec().decode(
                utf8.encode((await native.storedSettings.get(1))!.payload),
              )['theme'] ==
              'dark',
        );
        check(await native.close());
      }
    }
    for (final position in ['product', 'active', 'staging']) {
      final caseRoot = p.join(root, 'junction-$position');
      final target = p.join(root, 'junction-target-$position');
      check(p.isWithin(root, caseRoot) && p.isWithin(root, target));
      Directory(caseRoot).createSync();
      Directory(target).createSync();
      final marker = File(p.join(target, 'preserved.marker'));
      marker.writeAsBytesSync([31, 41, 59]);
      final product = p.join(caseRoot, 'ServerDeckNext');
      final parent = p.join(product, 'v1', 'workspaces');
      if (position != 'product') {
        for (final path in [product, p.dirname(parent), parent]) {
          createProtectedDirectory(caseRoot, path, sid);
        }
      }
      final junction = position == 'product'
          ? product
          : p.join(
              parent,
              position == 'active' ? 'default' : 'default.creating',
            );
      final setup = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'New-Item -ItemType Junction -Path \$env:SERVERDECK_TEST_JUNCTION -Target \$env:SERVERDECK_TEST_TARGET -ErrorAction Stop | Out-Null',
        ],
        environment: {
          'SERVERDECK_TEST_JUNCTION': junction,
          'SERVERDECK_TEST_TARGET': target,
        },
      );
      check(setup.exitCode == 0);
      check(
        FileSystemEntity.typeSync(junction, followLinks: false) ==
            FileSystemEntityType.link,
      );
      final deadline = Stopwatch()..start();
      await rejects(
        Workspace.open(
          localAppData: caseRoot,
          appRoot: bundle,
          lease: lease,
          custody: custody,
        ),
        'STORAGE_BLOCKED',
      );
      check(deadline.elapsed < const Duration(seconds: 30));
      check(
        FileSystemEntity.typeSync(junction, followLinks: false) ==
            FileSystemEntityType.link,
      );
      check(Link(junction).targetSync() == target);
      check(Directory(target).listSync().length == 1);
      check(base64.encode(marker.readAsBytesSync()) == 'Hyk7');
      if (position != 'product') {
        check(Directory(parent).listSync().length == 1);
      } else {
        check(Directory(caseRoot).listSync().length == 1);
      }
      stdout.writeln('WORKSPACE_REPARSE_CASE_${position.toUpperCase()}');
    }
    await verifyPersistedWorkspaceReparse(root, bundle, lease, sid);
    await verifyPersistedWorkspaceFileLinks(root, bundle, lease, sid);
    await verifyForeignWorkspaceSchema(root, bundle, lease, sid);
    final controlRoot = p.join(root, 'junction-control');
    Directory(controlRoot).createSync();
    Future<Workspace> controlOpen() => Workspace.open(
      localAppData: controlRoot,
      appRoot: bundle,
      lease: lease,
      custody: custody,
    );
    owned = await controlOpen();
    final controlIdentity = owned.store.state.workspaceId;
    check(owned.store.state.isInitialEmpty);
    await owned.close();
    owned = null;
    owned = await controlOpen();
    check(owned.store.state.workspaceId == controlIdentity);
    check(owned.store.state.isInitialEmpty);
    await owned.close();
    owned = null;
    stdout.writeln('WORKSPACE_REPARSE_HEALTHY_CONTROL_PROVED');
    final prerequisiteRoot = p.join(root, 'missing-runtime');
    Directory(prerequisiteRoot).createSync();
    await rejects(
      Workspace.open(
        localAppData: prerequisiteRoot,
        appRoot: p.join(root, 'absent-bundle'),
        lease: lease,
        custody: custody,
      ),
      'PREREQUISITE_UNAVAILABLE',
    );
    check(Directory(prerequisiteRoot).listSync().isEmpty);
    await lease.close();
    final noOwner = p.join(root, 'no-owner');
    Directory(noOwner).createSync();
    await rejects(
      Workspace.open(
        localAppData: noOwner,
        appRoot: bundle,
        lease: lease,
        custody: custody,
      ),
      'STORAGE_BLOCKED',
    );
    check(Directory(noOwner).listSync().isEmpty);
    stdout.writeln('WORKSPACE_CREATION_RECOVERY_PROVED');
  } finally {
    await owned?.close();
    await lease.close();
  }
}
