import 'dart:typed_data';

import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_engine/storage/workspace_storage.dart';
import 'package:serverdeck_protocol/codec.dart';

import 'memory_workspace_storage.dart';

/// Synthetic bytes over RAM files only. Production cannot select this format.
final class MemoryWorkspaceProvider implements WorkspaceStorageProvider {
  MemoryWorkspaceProvider({
    required this.readBytes,
    required this.persistBytes,
  });
  final List<int> Function() readBytes;
  final void Function(List<int>) persistBytes;
  MemoryWorkspaceStorage? lastOpened;
  bool _owned = false;
  int preflights = 0, opens = 0, cleanups = 0;
  void Function()? beforeOpen;
  void Function()? afterCommit;
  Object? openFailure;
  bool openFailureUncertain = false;

  static List<int> encode(Map<String, List<StoredRow>> rows) =>
      StrictCodec().encode({
        'format': 'unit-ram-rows-v1',
        'rows': {
          for (final family in WorkspaceCollection.values)
            family.persistedName: [
              for (final row in rows[family.persistedName]!)
                {
                  'nativeId': row.nativeId,
                  'payload': row.payload,
                  'entityId': row.entityId,
                },
            ],
        },
      }, maxBytes: 64 << 20);

  static Map<String, List<StoredRow>> decode(List<int> bytes) {
    final document = StrictCodec().decode(bytes, maxBytes: 64 << 20);
    if (document.length != 2 || document['format'] != 'unit-ram-rows-v1') {
      throw StateError('STORAGE_BLOCKED');
    }
    final rows = document['rows'];
    if (rows is! Map<String, Object?> ||
        rows.length != WorkspaceCollection.values.length) {
      throw StateError('STORAGE_BLOCKED');
    }
    return Map.unmodifiable({
      for (final family in WorkspaceCollection.values)
        family.persistedName: _decodeRows(rows[family.persistedName]),
    });
  }

  static List<StoredRow> _decodeRows(Object? value) {
    if (value is! List || value.length > 51251) {
      throw StateError('STORAGE_BLOCKED');
    }
    return List.unmodifiable([
      for (final row in value)
        if (row is Map<String, Object?> &&
            row.length == 3 &&
            row['nativeId'] is int &&
            row['payload'] is String &&
            row.containsKey('entityId') &&
            (row['entityId'] == null || row['entityId'] is String))
          StoredRow(
            row['nativeId'] as int,
            row['payload'] as String,
            entityId: row['entityId'] as String?,
          )
        else
          throw StateError('STORAGE_BLOCKED'),
    ]);
  }

  @override
  bool get hasOpenInstance => _owned;
  @override
  WorkspaceRowSource preflightRows(
    Uint8List bytes, {
    required String directory,
  }) {
    preflights++;
    return _Rows(directory, decode(bytes));
  }

  @override
  WorkspaceStorageOpen createOpenAttempt({required String directory}) =>
      _Open(this, directory);
}

final class _Rows implements WorkspaceRowSource {
  _Rows(this.directory, this.rows);
  final Map<String, List<StoredRow>> rows;
  @override
  final String directory;
  @override
  String get name => 'workspace';
  @override
  Future<T> readTransaction<T>(Future<T> Function() read) => Future.sync(read);
  @override
  Future<int> count(String collection) async => rows[collection]!.length;
  @override
  Future<List<StoredRow>> read(String collection, {required int limit}) async {
    if (limit < 1 || limit > 51251) throw StateError('STORAGE_BLOCKED');
    return List.unmodifiable(rows[collection]!.take(limit));
  }
}

final class _Open implements WorkspaceStorageOpen {
  _Open(this.provider, this.directory);
  final MemoryWorkspaceProvider provider;
  final String directory;
  MemoryWorkspaceStorage? _storage;
  bool _uncertain = false;
  Future<WorkspaceStorage>? _opening;
  Future<bool>? _cleanup;
  @override
  Future<WorkspaceStorage> open() {
    if (_cleanup != null) return Future.error(StateError('STORAGE_BLOCKED'));
    return _opening ??= _open();
  }

  Future<WorkspaceStorage> _open() async {
    if (provider.hasOpenInstance) throw StateError('STORAGE_BLOCKED');
    provider.beforeOpen?.call();
    if (provider.openFailure case final Object failure) {
      _uncertain = provider.openFailureUncertain;
      throw failure;
    }
    final rows = MemoryWorkspaceProvider.decode(provider.readBytes());
    final storage = MemoryWorkspaceStorage(
      directory: directory,
      initialRows: rows,
      onCommit: (rows) {
        provider.persistBytes(MemoryWorkspaceProvider.encode(rows));
        provider.afterCommit?.call();
      },
      onClosed: () => provider._owned = false,
    );
    _storage = provider.lastOpened = storage;
    provider._owned = true;
    provider.opens++;
    return storage;
  }

  @override
  Future<bool> cleanupAfterFailedOpen() => _cleanup ??= _close();
  Future<bool> _close() async {
    provider.cleanups++;
    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {}
    }
    if (_uncertain) return false;
    return _storage == null || await _storage!.close();
  }
}
