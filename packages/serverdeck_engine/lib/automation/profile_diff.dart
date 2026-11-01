import 'package:serverdeck_protocol/codec.dart';

/// Typed, deterministic RFC6901 diff. Callers supply validated public bodies;
/// the codec also bounds standalone use before walking any caller-owned tree.
Map<String, Object?> profileCatalogDiff(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  final codec = StrictCodec();
  before = codec.decode(
    codec.encode(before, maxBytes: 128 * 1024),
    maxBytes: 128 * 1024,
  );
  after = codec.decode(
    codec.encode(after, maxBytes: 128 * 1024),
    maxBytes: 128 * 1024,
  );
  final changes = <Map<String, Object?>>[];
  var truncated = false;
  var bytes = codec.encode({'changes': [], 'truncated': false}).length;
  String pointer(String value) =>
      value.replaceAll('~', '~0').replaceAll('/', '~1');
  void add(String op, String path, Object? old, Object? next) {
    if (truncated) return;
    final change = <String, Object?>{
      'op': op,
      'path': path,
      if (op != 'add') 'before': old,
      if (op != 'remove') 'after': next,
    };
    if (changes.length >= 2048) {
      truncated = true;
      return;
    }
    try {
      final next =
          bytes +
          codec.encode(change, maxBytes: 256 * 1024).length +
          (changes.isEmpty ? 0 : 1);
      if (next > 256 * 1024) {
        truncated = true;
        return;
      }
      bytes = next;
    } on FormatException {
      truncated = true;
      return;
    }
    changes.add(change);
  }

  void walk(Object? old, Object? next, String path) {
    if (truncated) return;
    if (old is Map<String, Object?> && next is Map<String, Object?>) {
      final keys = {...old.keys, ...next.keys}.toList()..sort();
      for (final key in keys) {
        final child = '$path/${pointer(key)}';
        if (!old.containsKey(key)) {
          add('add', child, null, next[key]);
        } else if (!next.containsKey(key)) {
          add('remove', child, old[key], null);
        } else {
          walk(old[key], next[key], child);
        }
        if (truncated) return;
      }
    } else if (old is List && next is List) {
      final length = old.length > next.length ? old.length : next.length;
      for (var n = 0; n < length; n++) {
        if (n >= old.length) {
          add('add', '$path/$n', null, next[n]);
        } else if (n >= next.length) {
          add('remove', '$path/$n', old[n], null);
        } else {
          walk(old[n], next[n], '$path/$n');
        }
        if (truncated) return;
      }
    } else if (old.runtimeType != next.runtimeType || old != next) {
      add('replace', path, old, next);
    }
  }

  walk(before, after, '');
  return {'changes': changes, 'truncated': truncated};
}
