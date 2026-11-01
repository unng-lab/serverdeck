import 'dart:convert';

import 'package:serverdeck_protocol/codec.dart';

import 'workspace_rows.dart';

/// Plans ordinary target3 rows after the caller validates graph/CAS/custody.
/// Retains native IDs and exact persisted bytes for unchanged JSON documents.
/// Proposed native IDs are placeholders; new IDs follow the retained maximum.
/// This neither authorizes a mutation nor commits or validates a full snapshot.
List<StoredRow> retainRowIdentities(
  List<StoredRow> before,
  List<StoredRow> proposed,
) {
  const maxId = 9223372036854775807;
  final codec = StrictCodec();
  final retained = <String?, StoredRow>{}, ids = <int>{};
  var maximum = 0;
  for (final row in before) {
    if (row.nativeId < 1 ||
        row.nativeId > maxId ||
        !ids.add(row.nativeId) ||
        retained.containsKey(row.entityId)) {
      throw StateError('STORAGE_BLOCKED');
    }
    retained[row.entityId] = row;
    if (row.nativeId > maximum) maximum = row.nativeId;
  }
  List<int> document(String payload) =>
      codec.canonical(codec.decode(utf8.encode(payload), maxBytes: 512 * 1024));
  final result = <StoredRow>[], entities = <String?>{};
  for (final row in proposed) {
    if (!entities.add(row.entityId)) throw StateError('STORAGE_BLOCKED');
    final old = retained[row.entityId];
    final replacement = document(row.payload);
    final previous = old == null ? null : document(old.payload);
    var equal = previous != null && previous.length == replacement.length;
    if (equal) {
      for (var i = 0; i < replacement.length; i++) {
        if (previous[i] != replacement[i]) {
          equal = false;
          break;
        }
      }
    }
    if (equal) {
      result.add(old!);
    } else {
      if (old == null && maximum >= maxId) throw StateError('RESOURCE_LIMIT');
      result.add(
        StoredRow(
          old?.nativeId ?? ++maximum,
          row.payload,
          entityId: row.entityId,
        ),
      );
    }
  }
  result.sort((a, b) => a.nativeId.compareTo(b.nativeId));
  return List.unmodifiable(result);
}
