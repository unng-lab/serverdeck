import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_windows/dpapi.dart';

/// Test-only IO fault immediately after the six opener liveness boundaries
/// (initial/runtime/manifest/wrapper/snapshot/preopen). Every custody check still
/// delegates to the real implementation. No product validation callback exists.
/// A separate owned process retains a genuine Windows share-none DB handle so
/// native Isar.open throws before returning an instance; no DB bytes are changed.
final class LockedOperationalOpen extends KeyCustody {
  LockedOperationalOpen(super.protection, super.ownerSid, this.database);
  final String database;
  int checks = 0;
  Process? child;
  Future<String>? errors;
  bool triggered = false;

  @override
  Future<Map<String, Object?>> createWorkspaceManifest(
    ReceiptKeyMaterial material,
  ) async {
    final result = await super.createWorkspaceManifest(material);
    if (++checks == 6) {
      if (Isar.getInstance('workspace') != null)
        throw StateError('UNEXPECTED_NATIVE_INSTANCE');
      child = await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"$fixtureHandle = [IO.File]::Open($env:SERVERDECK_TEST_LOCK_DB, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None); try { [Console]::Out.WriteLine('NATIVE_DB_SHARE_NONE_HELD'); [Console]::Out.Flush(); Start-Sleep -Seconds 45 } finally { $fixtureHandle.Dispose() }",
        ],
        environment: {'SERVERDECK_TEST_LOCK_DB': database},
      );
      errors = child!.stderr.transform(utf8.decoder).join();
      final marker = await child!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 10));
      if (marker != 'NATIVE_DB_SHARE_NONE_HELD')
        throw StateError('NATIVE_DB_LOCK_FAILED');
      triggered = true;
    }
    return result;
  }

  Future<void>? _closing;
  Future<void> closeFixture() => _closing ??= _closeFixture();
  Future<void> _closeFixture() async {
    final process = child;
    if (process == null) return;
    try {
      // Deliberately end only our owned lock holder. Windows releases its share-
      // none handle on termination; reaping is bounded even on fixture failure.
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 10));
      if ((await errors!.timeout(const Duration(seconds: 5))).isNotEmpty)
        throw StateError('NATIVE_DB_LOCK_HELPER_FAILED');
    } finally {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 10));
    }
  }
}

LockedOperationalOpen lockedOpener(String sid, String database) =>
    LockedOperationalOpen(DpapiProtection(), sid, database);
