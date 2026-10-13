import 'dart:convert';
import 'dart:typed_data';

import 'native_registry.dart';
import 'records.dart';

/// Read-only schema preflight, not a complete database integrity check.
void validateNativeSnapshot(Uint8List snapshot) {
  try {
    _Snapshot(snapshot).validate();
  } on RangeError {
    throw StateError('STORAGE_BLOCKED');
  } on FormatException {
    throw StateError('STORAGE_BLOCKED');
  }
}

Never _blocked() => throw StateError('STORAGE_BLOCKED');
Never _incompatible() => throw StateError('INCOMPATIBLE');

// Pinned MDBX v0.13.8-temp-upstream-fix layout-dxb.h, little endian.
// No native call, file access, schema migration or writable open occurs here.
class _Snapshot {
  _Snapshot(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  late int pageSize;
  late int nextPage;
  late int transaction;
  final visited = <int>{};

  int u16(int offset) => data.getUint16(offset, Endian.little);
  int u32(int offset) => data.getUint32(offset, Endian.little);
  int u64(int offset) => data.getUint64(offset, Endian.little);

  void validate() {
    if (bytes.length < 244 || bytes.length > 64 * 1024 * 1024) _blocked();
    pageSize = u32(64);
    if (pageSize < 512 ||
        pageSize > 65536 ||
        (pageSize & (pageSize - 1)) != 0 ||
        bytes.length < 3 * pageSize ||
        bytes.length % pageSize != 0)
      _blocked();
    var selected = -1;
    transaction = 0;
    for (var i = 0; i < 3; i++) {
      final base = i * pageSize;
      if (u16(base + 10) != 8 || u32(base + 16) != i) _blocked();
      if (u64(base + 20) != 0x59659dbdef4c1103) _incompatible();
      if (u32(base + 64) != pageSize || u32(base + 36) != 0) _blocked();
      final first = u64(base + 28), second = u64(base + 196);
      // Incomplete two-phase meta is never used as a committed snapshot.
      if (first <= 0 || first != second) continue;
      if (first > transaction) {
        transaction = first;
        selected = base;
      }
    }
    if (selected < 0) _blocked();
    final sign = u64(selected + 188);
    // Uint64 all-one is represented as -1 by Dart VM: do not compare signed >1.
    if (sign == 0 || sign == 1) _blocked();
    nextPage = u32(selected + 56);
    if (nextPage < 3 || nextPage * pageSize > bytes.length) _blocked();
    final main = _tree(selected + 108);
    if (main.flags != 0 || main.duplicateSize != 0) _blocked();
    final catalogue = _entries(main, namedTrees: true);
    // Structural failure takes precedence over names/schema compatibility.
    final trees = <String, _Tree>{};
    for (final entry in catalogue.entries) {
      final tree = _descriptor(entry.value);
      _validateTree(tree);
      trees[entry.key] = tree;
    }
    final info = trees['_info'];
    if (info == null) _incompatible();
    if (info.flags != 0 || info.duplicateSize != 0) _blocked();
    final documents = _entries(info, namedTrees: false);
    validateNativeRegistry(documents);
    final expected = <String, int>{'_info': 0};
    for (final schema in workspaceSchemas) {
      expected[schema.name] = 8; // MDBX_INTEGERKEY for native Id.
      for (final index in schema.indexes.values) {
        expected['_i_${schema.name}_${index.name}'] = 0;
      }
    }
    if (catalogue.length != expected.length ||
        expected.keys.any((key) => !catalogue.containsKey(key)))
      _incompatible();
    for (final entry in trees.entries) {
      final tree = entry.value;
      if (tree.flags != expected[entry.key] || tree.duplicateSize != 0)
        _incompatible();
    }
  }

  _Tree _tree(int offset) => _Tree(
    u16(offset),
    u16(offset + 2),
    u32(offset + 4),
    u32(offset + 8),
    u32(offset + 12),
    u32(offset + 16),
    u32(offset + 20),
    u64(offset + 32),
    u64(offset + 40),
  );

  _Tree _descriptor(Uint8List bytes) {
    if (bytes.length != 48) _blocked();
    final d = ByteData.sublistView(bytes);
    return _Tree(
      d.getUint16(0, Endian.little),
      d.getUint16(2, Endian.little),
      d.getUint32(4, Endian.little),
      d.getUint32(8, Endian.little),
      d.getUint32(12, Endian.little),
      d.getUint32(16, Endian.little),
      d.getUint32(20, Endian.little),
      d.getUint64(32, Endian.little),
      d.getUint64(40, Endian.little),
    );
  }

  void _validateTree(_Tree tree) {
    if (tree.modified < 0 ||
        tree.modified > transaction ||
        tree.items < 0 ||
        tree.items > bytes.length ~/ 8 ||
        tree.height > 32)
      _blocked();
    if (tree.height == 0) {
      if (tree.root != 0xffffffff ||
          tree.items != 0 ||
          tree.branches != 0 ||
          tree.leaves != 0 ||
          tree.large != 0)
        _blocked();
    } else {
      if (tree.root < 3 ||
          tree.root >= nextPage ||
          tree.items == 0 ||
          tree.leaves == 0 ||
          tree.branches + tree.leaves + tree.large > nextPage - 3)
        _blocked();
    }
  }

  int _page(int number, int flags) {
    if (number < 3 || number >= nextPage || !visited.add(number)) _blocked();
    final base = number * pageSize;
    if (u32(base + 16) != number ||
        u16(base + 10) != flags ||
        u16(base + 8) != 0 ||
        u64(base) < 0 ||
        u64(base) > transaction)
      _blocked();
    return base;
  }

  Map<String, Uint8List> _entries(_Tree tree, {required bool namedTrees}) {
    _validateTree(tree);
    final result = <String, Uint8List>{};
    if (tree.height == 0) return result;
    var branches = 0, leaves = 0, large = 0;
    List<int>? previousKey;
    ({List<int> first, List<int> last}) walk(int page, int height) {
      final branch = height > 1;
      final base = _page(page, branch ? 1 : 2);
      if (branch) {
        branches++;
      } else {
        leaves++;
      }
      final lower = u16(base + 12), upper = u16(base + 14);
      if (lower == 0 || lower.isOdd || lower > upper || upper > pageSize - 20)
        _blocked();
      final spans = <(int, int)>[];
      List<int>? firstKey, lastKey, previousChildLast;
      for (var i = 0; i < lower ~/ 2; i++) {
        final relative = u16(base + 20 + i * 2);
        if (relative < upper || relative.isOdd || relative + 8 > pageSize - 20)
          _blocked();
        final node = base + 20 + relative;
        final keySize = u16(node + 6),
            size = u32(node),
            flags = bytes[node + 4];
        if (bytes[node + 5] != 0 || node + 8 + keySize > base + pageSize)
          _blocked();
        final keyBytes = Uint8List.sublistView(
          bytes,
          node + 8,
          node + 8 + keySize,
        );
        if (branch) {
          if (flags != 0 || (i == 0 && keySize != 0)) _blocked();
          spans.add((relative, relative + 8 + keySize));
          final child = walk(size, height - 1);
          if (i > 0 &&
              (keySize == 0 ||
                  _compare(previousChildLast!, keyBytes) >= 0 ||
                  _compare(keyBytes, child.first) > 0))
            _blocked();
          firstKey ??= child.first;
          lastKey = child.last;
          previousChildLast = child.last;
          continue;
        }
        if (keySize == 0 ||
            (previousKey != null && _compare(previousKey!, keyBytes) >= 0))
          _blocked();
        previousKey = keyBytes;
        firstKey ??= keyBytes;
        lastKey = keyBytes;
        final key = utf8.decode(keyBytes, allowMalformed: false);
        if (result.containsKey(key)) _blocked();
        if (namedTrees ? flags != 2 : (flags != 0 && flags != 1)) _blocked();
        final valueStart = node + 8 + keySize;
        final storedSize = flags == 1 ? 4 : size;
        if (valueStart + storedSize > base + pageSize) _blocked();
        spans.add((relative, relative + 8 + keySize + storedSize));
        if (flags == 1) {
          final overflow = u32(valueStart), overflowBase = _page(overflow, 4);
          final count = u32(overflowBase + 12);
          if (size > 16 * 1024 ||
              count < 1 ||
              overflow + count > nextPage ||
              size + 20 > count * pageSize ||
              count != (size + 20 + pageSize - 1) ~/ pageSize)
            _blocked();
          for (var j = 1; j < count; j++) {
            if (!visited.add(overflow + j)) _blocked();
          }
          large += count;
          result[key] = Uint8List.sublistView(
            bytes,
            overflowBase + 20,
            overflowBase + 20 + size,
          );
        } else {
          if (namedTrees ? size != 48 : size > 16 * 1024) _blocked();
          result[key] = Uint8List.sublistView(
            bytes,
            valueStart,
            valueStart + size,
          );
        }
      }
      spans.sort((a, b) => a.$1.compareTo(b.$1));
      for (var i = 1; i < spans.length; i++) {
        if (spans[i].$1 < spans[i - 1].$2) _blocked();
      }
      return (first: firstKey!, last: lastKey!);
    }

    walk(tree.root, tree.height);
    if (result.length != tree.items ||
        branches != tree.branches ||
        leaves != tree.leaves ||
        large != tree.large)
      _blocked();
    return result;
  }
}

int _compare(List<int> left, List<int> right) {
  for (var i = 0; i < left.length && i < right.length; i++) {
    if (left[i] != right[i]) return left[i].compareTo(right[i]);
  }
  return left.length.compareTo(right.length);
}

class _Tree {
  const _Tree(
    this.flags,
    this.height,
    this.duplicateSize,
    this.root,
    this.branches,
    this.leaves,
    this.large,
    this.items,
    this.modified,
  );
  final int flags,
      height,
      duplicateSize,
      root,
      branches,
      leaves,
      large,
      items,
      modified;
}
