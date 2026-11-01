import 'workspace_manifest.dart';

import 'dart:typed_data';

import 'native_schema.dart';

import 'dart:math';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_engine/platform/ports.dart';

import 'package:serverdeck_engine/storage/key_custody.dart';

import 'package:serverdeck_engine/storage/models.dart';

import 'package:serverdeck_engine/storage/records.dart';

import 'state_store.dart';

import 'package:serverdeck_engine/storage/host_trust_records.dart';

import 'package:serverdeck_engine/storage/workspace_snapshot.dart';
import 'package:serverdeck_engine/storage/isar_rows.dart';

part 'workspace_creation.dart';

/// Owns creation/promotion and receipt-key lifetime; the caller owns the lease.
class Workspace {
  Workspace._(this._store, this._receiptKey);
  static bool _reserved = false;

  /// An unsuccessful open can retain this reservation if native close failed.
  /// The resource owner must not release its mutex in that case.
  static bool get hasOpenReservation =>
      _reserved || StateStore.hasOpenReservation;
  static void requireNoOpenReservation() {
    if (hasOpenReservation) throw StateError('STORAGE_BLOCKED');
  }

  final StateStore _store;
  final ReceiptKeyMaterial _receiptKey;
  Future<void>? _closing;

  static Future<Workspace> open({
    required ProtectedFiles files,
    required NativeStoreRuntime runtime,
    required WorkspaceLease lease,
    required KeyCustody custody,
    void Function()? checkStartup,
  }) => _openWorkspace(
    files: files,
    runtime: runtime,
    lease: lease,
    custody: custody,
    checkStartup: checkStartup,
  );

  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 0x40;
    bytes[8] = (bytes[8] & 63) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  StateStore get store => _store;
  ReceiptKeyMaterial get receiptKey => _receiptKey;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    try {
      await _store.close();
      _reserved = false;
    } finally {
      _receiptKey.close();
    }
  }
}
