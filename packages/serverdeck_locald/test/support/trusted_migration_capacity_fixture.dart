import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/migration_probe.dart';
import 'package:serverdeck_locald/storage/native_failure.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/workspace_migration.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/process.dart';

import 'mcp_runtime_actor.dart' show check;
import 'trusted_schema_child.dart' as raw;

/// Actual target-copy MapFull, with existing compiler-gated migration probes.
/// Production errors/limits/transaction/close paths are unchanged.
final class TrustedMigrationCapacityFixture {
  TrustedMigrationCapacityFixture(this.active, this.lease);
  final String active;
  final MutexLease lease;
  final baseline = <String, String>{};
  Completer<void>? _release;
  Future<void>? _reader;
  String? _rows;
  bool full = false, rollback = false, closed = false;
  int nativeFailures = 0;
  void install() => MigrationProbe.install(_at, closeNative: _close);

  Future<void> _at(MigrationBoundary boundary) async {
    check(lease.isHeld && WorkspaceMigration.hasOpenReservation);
    if (boundary == MigrationBoundary.nativeCapacityFailure) {
      check(full && _reader != null);
      nativeFailures++;
    }
    if (boundary == MigrationBoundary.sourceValidated) {
      for (final name in [
        'workspace.isar',
        'workspace.manifest.json',
        'receipt-key.dpapi',
      ]) {
        baseline[name] = fileSha256(p.join(active, name));
      }
    }
    if (boundary != MigrationBoundary.nativeSchemaOpened) return;
    check(!full && _reader == null && baseline.length == 3);
    final db = Isar.getInstance('workspace')!;
    check(p.equals(db.directory!, '$active.upgrading-2-3'));
    check(await db.storedHostTrusts.count() == 0);
    _rows = await raw.capture(db);
    final original = (await db.storedSettings.get(1))!.payload;
    final doc = jsonDecode(original) as Map;
    final alternate = jsonEncode({
      ...doc,
      'reduceMotion': !(doc['reduceMotion'] as bool),
    });
    final ready = Completer<void>(), release = Completer<void>();
    _release = release;
    _reader = db.txn(() async {
      check(await db.storedSettings.get(1) != null);
      ready.complete();
      await release.future;
    });
    await ready.future;
    // The 64MiB production map and all application row quotas stay unchanged.
    // Every successful maintenance commit restores byte-identical raw rows.
    for (var n = 0; n < 20000; n++) {
      try {
        await db.writeTxn(() async {
          await db.storedSettings.put(StoredSettings()..payload = alternate);
          await db.storedSettings.put(StoredSettings()..payload = original);
        });
      } catch (error) {
        if (!isNativeCapacityFailure(error)) rethrow;
        full = true;
        break;
      }
    }
    check(full && await raw.capture(db) == _rows);
    // Return to the actual migration's marker transaction while pages remain
    // pinned. The existing native close callback releases only after its abort.
  }

  Future<bool> _close(Future<bool> Function() actual) async {
    if (_reader == null) return actual();
    final db = Isar.getInstance('workspace')!;
    try {
      check(
        full &&
            nativeFailures == 1 &&
            db.isOpen &&
            lease.isHeld &&
            WorkspaceMigration.hasOpenReservation,
      );
      check(
        jsonDecode(
              (await db.storedWorkspaces.get(1))!.payload,
            )['schemaVersion'] ==
            2,
      );
      check(
        await raw.capture(db) == _rows &&
            await db.storedHostTrusts.count() == 0,
      );
      rollback = true;
    } finally {
      _release!.complete();
      await _reader;
      _reader = null;
    }
    final result = await actual();
    check(result);
    closed = true;
    return result;
  }

  void verify() {
    check(full && nativeFailures == 1 && rollback && closed && _reader == null);
    check(
      !WorkspaceMigration.hasOpenReservation &&
          Isar.getInstance('workspace') == null &&
          lease.isHeld,
    );
    for (final entry in baseline.entries) {
      check(fileSha256(p.join(active, entry.key)) == entry.value);
    }
    check(
      fileSha256(p.join('$active.upgrading-2-3', 'original.isar')) ==
          baseline['workspace.isar'],
    );
    check(File(p.join('$active.upgrading-2-3', 'migration.json')).existsSync());
  }
}
