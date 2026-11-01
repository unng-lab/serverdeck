import 'dart:async';

import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_engine/storage/workspace_storage.dart';

/// Only the row/atomicity dependency. Domain writes and successful responses
/// must come from the actual StateStore and services, never this RAM backend.
final class MemoryWorkspaceStorage extends TransactionalWorkspaceStorage {
  static final _viewZone = Object();
  MemoryWorkspaceStorage({
    required this.directory,
    Map<String, List<StoredRow>>? initialRows,
    this.onCommit,
    this.onClosed,
  }) {
    if (initialRows != null) {
      _committed = {
        for (final family in WorkspaceCollection.values)
          family: {
            for (final row in initialRows[family.persistedName]!)
              row.nativeId: row,
          },
      };
    }
  }
  final void Function(Map<String, List<StoredRow>>)? onCommit;
  final void Function()? onClosed;
  void Function()? afterAbort;
  void Function()? beforeWrite;
  @override
  final String directory;
  @override
  String get name => 'workspace';

  Map<WorkspaceCollection, Map<int, StoredRow>> _committed = {
    for (final family in WorkspaceCollection.values) family: {},
  };
  Future<void> _tail = Future.value();
  Object? nextPutFailure;
  Completer<void>? holdPut;
  Object? nextReadFailure;
  Completer<void>? holdRead;
  bool closeResult = true;
  Object? closeFailure;
  int closeCalls = 0;
  int commits = 0;
  int countCalls = 0, rowReads = 0;
  int putCalls = 0;

  Map<String, List<StoredRow>> get committedRows => Map.unmodifiable({
    for (final entry in _committed.entries)
      entry.key.persistedName: List<StoredRow>.unmodifiable(entry.value.values),
  });

  Map<int, StoredRow> _rows(WorkspaceCollection family) {
    final view = Zone.current[_viewZone];
    if (view is! Map<WorkspaceCollection, Map<int, StoredRow>>) {
      throw StateError('STORAGE_BLOCKED');
    }
    return view[family]!;
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final pending = _tail.then((_) => action());
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return pending;
  }

  @override
  Future<T> backendRead<T>(Future<T> Function() read) =>
      runZoned(read, zoneValues: {_viewZone: _committed});

  @override
  Future<T> backendWrite<T>(Future<T> Function() write) => _serialize(() async {
    final scratch = {
      for (final entry in _committed.entries)
        entry.key: Map<int, StoredRow>.of(entry.value),
    };
    final T result;
    try {
      beforeWrite?.call();
      result = await runZoned(write, zoneValues: {_viewZone: scratch});
    } catch (_) {
      afterAbort?.call();
      rethrow;
    }
    _committed = scratch;
    commits++;
    onCommit?.call(committedRows);
    return result;
  });

  @override
  Future<int> backendCount(WorkspaceCollection collection) async {
    countCalls++;
    return _rows(collection).length;
  }

  @override
  Future<List<StoredRow>> backendRows(
    WorkspaceCollection collection,
    int limit,
  ) async {
    rowReads++;
    final hold = holdRead;
    if (hold != null) await hold.future;
    final failure = nextReadFailure;
    nextReadFailure = null;
    if (failure != null) throw failure;
    return _rows(collection).values.take(limit).toList();
  }

  @override
  Future<StoredRow?> backendGet(WorkspaceCollection collection, int id) async =>
      _rows(collection)[id];
  @override
  Future<StoredRow?> backendGetByEntityId(
    WorkspaceCollection collection,
    String entityId,
  ) async {
    for (final row in _rows(collection).values) {
      if (row.entityId == entityId) return row;
    }
    return null;
  }

  @override
  Future<int> backendPut(WorkspaceCollection collection, StoredRow row) async {
    putCalls++;
    final hold = holdPut;
    if (hold != null) await hold.future;
    final failure = nextPutFailure;
    nextPutFailure = null;
    if (failure != null) throw failure;
    final rows = _rows(collection);
    if (!collection.singleton &&
        rows.values.any(
          (existing) =>
              existing.entityId == row.entityId &&
              existing.nativeId != row.nativeId,
        )) {
      throw StateError('STORAGE_BLOCKED');
    }
    rows[row.nativeId] = row;
    return row.nativeId;
  }

  @override
  Future<bool> backendDelete(WorkspaceCollection collection, int id) async =>
      _rows(collection).remove(id) != null;
  @override
  bool isCapacityFailure(Object error) => error is MemoryCapacityFailure;
  @override
  Future<bool> backendClose() async {
    closeCalls++;
    if (closeFailure case final Object failure) throw failure;
    if (closeResult) onClosed?.call();
    return closeResult;
  }
}

final class MemoryCapacityFailure implements Exception {}
