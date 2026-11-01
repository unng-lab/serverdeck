/// Immutable ordinary persisted row, retaining native ID and exact JSON bytes.
final class StoredRow {
  const StoredRow(this.nativeId, this.payload, {this.entityId});
  final int nativeId;
  final String payload;
  final String? entityId;
}

/// Borrowed, already opened data source. It never opens/closes a DB, acquires a
/// lease, publishes credentials or grants authority. All reads in a transaction
/// must observe one committed view. Returned lists/rows are detached snapshots.
abstract interface class WorkspaceRowSource {
  String get name;
  String get directory;
  Future<T> readTransaction<T>(Future<T> Function() read);
  Future<int> count(String collection);
  Future<List<StoredRow>> read(String collection, {required int limit});
}
