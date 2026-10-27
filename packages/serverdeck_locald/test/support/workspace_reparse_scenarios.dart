import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

void _check(bool value) {
  if (!value) throw StateError('PERSISTED_REPARSE_FIXTURE_FAILED');
}

final class _CountingProtection implements UserProtection {
  final UserProtection delegate = DpapiProtection();
  int protects = 0, unprotects = 0;
  int credentialUnprotects = 0;
  @override
  Future<List<int>> protect(List<int> bytes, List<int> entropy) {
    protects++;
    return delegate.protect(bytes, entropy);
  }

  @override
  Future<List<int>> unprotect(List<int> bytes, List<int> entropy) {
    unprotects++;
    const suffix = [10, 99, 114, 101, 100, 101, 110, 116, 105, 97, 108];
    if (entropy.length >= suffix.length &&
        Iterable<int>.generate(suffix.length).every(
          (index) =>
              entropy[entropy.length - suffix.length + index] == suffix[index],
        )) {
      credentialUnprotects++;
    }
    return delegate.unprotect(bytes, entropy);
  }
}

/// Genuine file symbolic links, with existing regular-file targets outside the
/// workspace inventory. Developer Mode or OS symlink privilege is required;
/// an OS refusal is a failed/unproven case, never a skip or an alternate setup.
Future<void> verifyPersistedWorkspaceFileLinks(
  String root,
  String bundle,
  MutexLease lease,
  String sid,
) async {
  const cases = {
    'manifest': 'workspace.manifest.json',
    'key': 'receipt-key.dpapi',
    'database': 'workspace.isar',
    'lock': 'workspace.isar-lck',
  };
  for (final entry in cases.entries) {
    final local = p.join(root, 'persisted-file-reparse-${entry.key}');
    _check(p.isAbsolute(root) && p.isWithin(root, local));
    _check(
      FileSystemEntity.typeSync(local, followLinks: false) ==
          FileSystemEntityType.notFound,
    );
    createProtectedDirectory(root, local, sid);
    final active = p.join(
      local,
      'ServerDeckNext',
      'v1',
      'workspaces',
      'default',
    );
    final source = p.join(active, entry.value);
    final retained = p.join(local, 'retained-file');
    _check(p.isWithin(local, source) && p.isWithin(local, retained));
    final protection = _CountingProtection();
    final custody = KeyCustody(protection, sid);
    Future<Workspace> open() => Workspace.open(
      localAppData: local,
      appRoot: bundle,
      lease: lease,
      custody: custody,
    );
    Workspace? owned;
    try {
      owned = await open();
      final workspaceId = owned.store.state.workspaceId;
      final keyId = owned.receiptKey.receiptKeyId;
      final coordinator = MutationCoordinator(
        owned.store,
        custody,
        owned.receiptKey,
      );
      try {
        await coordinator.submit(
          '82345678-1234-4234-8234-123456789012',
          ApiMethod.profilesCreate,
          {
            'profileId': '92345678-1234-4234-8234-123456789012',
            'name': 'File link fixture',
            'address': 'example.invalid',
            'sshUser': 'synthetic',
            'credential': {
              'action': 'replace',
              'kind': 'password',
              'password': 'synthetic-file-reparse-password',
            },
          },
          requester: 'owned-fixture',
        );
      } finally {
        await coordinator.close();
      }
      await owned.close();
      owned = null;
      final originals = {
        for (final name in cases.values) name: fileSha256(p.join(active, name)),
      };
      requireSafePath(local, source);
      requireSafePath(local, retained);
      await promoteProtectedPath(local, source, retained, sid);
      _check(
        FileSystemEntity.typeSync(retained, followLinks: false) ==
            FileSystemEntityType.file,
      );
      // Dart's Windows Link API creates a true file symlink for this regular
      // existing target. No PowerShell junction or privilege fallback.
      await Link(source).create(retained);
      _check(
        FileSystemEntity.typeSync(source, followLinks: false) ==
            FileSystemEntityType.link,
      );
      final originalFileTarget = Link(source).targetSync();
      _check(
        p.equals(
          File(source).resolveSymbolicLinksSync(),
          File(retained).resolveSymbolicLinksSync(),
        ),
      );
      var unsafePath = false;
      try {
        requireSafePath(local, source);
      } on FileSystemException catch (error) {
        _check(
          error.message == 'UNSAFE_PATH' && error.osError?.errorCode == 0x400,
        );
        unsafePath = true;
      }
      _check(unsafePath);
      final beforeNames =
          Directory(active)
              .listSync(followLinks: false)
              .map((item) => p.basename(item.path))
              .toList()
            ..sort();
      _check(
        beforeNames.length == 4 &&
            beforeNames.toSet().containsAll(cases.values),
      );
      protection.protects = protection.unprotects =
          protection.credentialUnprotects = 0;
      final watch = Stopwatch()..start();
      var refused = false;
      try {
        owned = await open();
      } on StateError catch (error) {
        _check(error.message == 'STORAGE_BLOCKED');
        refused = true;
      }
      _check(refused && watch.elapsed < const Duration(seconds: 30));
      // Database/lock validation follows the original safe receipt-wrapper
      // read. That technical unwrap is allowed; access credentials are not.
      final expectedUnwraps = entry.key == 'database' || entry.key == 'lock'
          ? 1
          : 0;
      _check(
        protection.protects == 0 &&
            protection.unprotects == expectedUnwraps &&
            protection.credentialUnprotects == 0,
      );
      _check(
        FileSystemEntity.typeSync(source, followLinks: false) ==
            FileSystemEntityType.link,
      );
      _check(Link(source).targetSync() == originalFileTarget);
      _check(fileSha256(retained) == originals[entry.value]);
      for (final name in cases.values.where((name) => name != entry.value)) {
        _check(
          FileSystemEntity.typeSync(p.join(active, name), followLinks: false) ==
              FileSystemEntityType.file,
        );
        _check(fileSha256(p.join(active, name)) == originals[name]);
      }
      final afterNames =
          Directory(active)
              .listSync(followLinks: false)
              .map((item) => p.basename(item.path))
              .toList()
            ..sort();
      _check(
        afterNames.length == beforeNames.length &&
            Iterable<int>.generate(beforeNames.length)
                .every((index) => afterNames[index] == beforeNames[index]),
      );
      _check(!Directory('$active.creating').existsSync());
      Link(source).deleteSync();
      _check(
        FileSystemEntity.typeSync(source, followLinks: false) ==
            FileSystemEntityType.notFound,
      );
      requireSafePath(local, source);
      requireSafePath(local, retained);
      await promoteProtectedPath(local, retained, source, sid);
      owned = await open();
      _check(
        owned.store.state.workspaceId == workspaceId &&
            owned.receiptKey.receiptKeyId == keyId &&
            owned.store.state.storeRevision == '1' &&
            owned.store.state.profiles.length == 1 &&
            owned.store.state.credentials.length == 1,
      );
      _check(protection.protects == 0 && protection.credentialUnprotects > 0);
      stdout.writeln(
        'WORKSPACE_PERSISTED_FILE_REPARSE_${entry.key.toUpperCase()}_PRESERVED_PROVED',
      );
    } finally {
      await owned?.close();
      // Retain failed single-use fixtures; no retry, elevation or cleanup of
      // junction/symlink targets, and never turn unavailable setup into pass.
    }
  }
}

/// Reject real persisted directory junctions before any key protection/unwrap.
/// Targets and moves remain in a fresh caller-owned synthetic case root. This
/// does not claim file-symlink/foreign-user/ACL-negative or normal-UI coverage.
Future<void> verifyPersistedWorkspaceReparse(
  String root,
  String bundle,
  MutexLease lease,
  String sid,
) async {
  for (final position in ['product', 'workspaces', 'active', 'staging']) {
    final local = p.join(root, 'persisted-reparse-$position');
    _check(p.isAbsolute(root) && p.isWithin(root, local));
    _check(
      FileSystemEntity.typeSync(local, followLinks: false) ==
          FileSystemEntityType.notFound,
    );
    createProtectedDirectory(root, local, sid);
    final protection = _CountingProtection();
    final custody = KeyCustody(protection, sid);
    final product = p.join(local, 'ServerDeckNext');
    final workspaces = p.join(product, 'v1', 'workspaces');
    final active = p.join(workspaces, 'default');
    final staging = '$active.creating';
    final retained = p.join(local, 'retained');
    final source = switch (position) {
      'product' => product,
      'workspaces' => workspaces,
      'active' => active,
      _ => staging,
    };
    _check(p.isWithin(local, source) && p.isWithin(local, retained));
    Future<Workspace> open() => Workspace.open(
      localAppData: local,
      appRoot: bundle,
      lease: lease,
      custody: custody,
    );
    Workspace? owned;
    late String workspaceId, keyId;
    try {
      owned = await open();
      workspaceId = owned.store.state.workspaceId;
      keyId = owned.receiptKey.receiptKeyId;
      if (position != 'staging') {
        final coordinator = MutationCoordinator(
          owned.store,
          custody,
          owned.receiptKey,
        );
        try {
          await coordinator.submit(
            '82345678-1234-4234-8234-123456789012',
            ApiMethod.profilesCreate,
            {
              'profileId': '92345678-1234-4234-8234-123456789012',
              'name': 'Persisted fixture',
              'address': 'example.invalid',
              'sshUser': 'synthetic',
              'credential': {
                'action': 'replace',
                'kind': 'password',
                'password': 'synthetic-persisted-reparse-password',
              },
            },
            requester: 'owned-fixture',
          );
        } finally {
          await coordinator.close();
        }
      }
      await owned.close();
      owned = null;
      // A complete empty staging is normally promotable; unlike nonempty
      // staging, its refusal here cannot be attributed to application rows.
      if (position == 'staging') {
        requireSafePath(local, active);
        requireSafePath(local, staging);
        await promoteProtectedPath(local, active, staging, sid);
      }
      requireSafePath(local, source);
      requireSafePath(local, retained);
      await promoteProtectedPath(local, source, retained, sid);
      Map<String, String> inventory() {
        requireSafePath(local, retained);
        final entries = Directory(retained).listSync(
          recursive: true,
          followLinks: false,
        )..sort((a, b) => a.path.compareTo(b.path));
        return {
          for (final entry in entries)
            p.relative(
              entry.path,
              from: retained,
            ): switch (FileSystemEntity.typeSync(
              entry.path,
              followLinks: false,
            )) {
              FileSystemEntityType.file => fileSha256(entry.path),
              FileSystemEntityType.directory => 'directory',
              _ => throw StateError('PERSISTED_REPARSE_INVENTORY_UNSAFE'),
            },
        };
      }

      final before = inventory();
      _check(
        before.keys.any((path) => p.basename(path) == 'receipt-key.dpapi'),
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
          'SERVERDECK_TEST_JUNCTION': source,
          'SERVERDECK_TEST_TARGET': retained,
        },
      );
      _check(setup.exitCode == 0);
      _check(
        FileSystemEntity.typeSync(source, followLinks: false) ==
            FileSystemEntityType.link,
      );
      final originalJunctionTarget = Link(source).targetSync();
      _check(
        p.equals(
          Directory(source).resolveSymbolicLinksSync(),
          Directory(retained).resolveSymbolicLinksSync(),
        ),
      );
      final parentEntries =
          Directory(p.dirname(source))
              .listSync(followLinks: false)
              .map((entry) => p.basename(entry.path))
              .toList()
            ..sort();
      protection.protects = protection.unprotects = 0;
      final watch = Stopwatch()..start();
      var refused = false;
      try {
        owned = await open();
      } on StateError catch (error) {
        _check(error.message == 'STORAGE_BLOCKED');
        refused = true;
      }
      _check(refused && watch.elapsed < const Duration(seconds: 30));
      _check(protection.protects == 0 && protection.unprotects == 0);
      _check(
        FileSystemEntity.typeSync(source, followLinks: false) ==
            FileSystemEntityType.link,
      );
      _check(Link(source).targetSync() == originalJunctionTarget);
      final after = inventory();
      _check(
        before.length == after.length &&
            before.entries.every((entry) => after[entry.key] == entry.value),
      );
      final currentParent =
          Directory(p.dirname(source))
              .listSync(followLinks: false)
              .map((entry) => p.basename(entry.path))
              .toList()
            ..sort();
      _check(
        parentEntries.length == currentParent.length &&
            Iterable<int>.generate(parentEntries.length)
                .every((index) => parentEntries[index] == currentParent[index]),
      );
      // Remove only the verified junction itself, never recursively its target.
      Link(source).deleteSync();
      _check(
        FileSystemEntity.typeSync(source, followLinks: false) ==
            FileSystemEntityType.notFound,
      );
      requireSafePath(local, source);
      requireSafePath(local, retained);
      await promoteProtectedPath(local, retained, source, sid);
      owned = await open();
      _check(
        owned.store.state.workspaceId == workspaceId &&
            owned.receiptKey.receiptKeyId == keyId,
      );
      _check(protection.unprotects > 0 && protection.protects == 0);
      _check(
        position == 'staging'
            ? owned.store.state.isInitialEmpty
            : owned.store.state.profiles.length == 1 &&
                  owned.store.state.credentials.length == 1 &&
                  owned.store.state.storeRevision == '1',
      );
      _check(!Directory(staging).existsSync());
      stdout.writeln(
        'WORKSPACE_PERSISTED_REPARSE_${position.toUpperCase()}_PRESERVED_PROVED',
      );
    } finally {
      await owned?.close();
      // Preserve failed single-use cases, including junctions and original
      // targets, instead of deleting data or retrying setup after a failure.
    }
  }
}
