import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:xxh3/xxh3.dart';

import 'package:serverdeck_engine/storage/native_registry.dart';
import 'package:serverdeck_engine/storage/host_trust_records.dart';

import 'workspace_rows.dart';

/// Detached committed rows from the pinned schema3/MDBX snapshot. No native
/// call, file access, writable open, lookup publication or authority is involved.
/// Logical graph/credential checks remain the workspace snapshot loader's job.
final class NativeWorkspaceRows implements WorkspaceRowSource {
  NativeWorkspaceRows._(this.directory, Map<String, List<StoredRow>> rows)
    : _rows = Map.unmodifiable({
        for (final entry in rows.entries)
          entry.key: List<StoredRow>.unmodifiable(entry.value),
      });
  factory NativeWorkspaceRows.fromSnapshot(
    Uint8List bytes, {
    required String directory,
  }) {
    if (bytes.length < 244 ||
        bytes.length > 64 * 1024 * 1024 ||
        !p.isAbsolute(directory) ||
        p.normalize(directory) != directory ||
        directory.contains('\u0000') ||
        directory.length > 32767)
      _blocked();
    try {
      final source = _Snapshot(Uint8List.fromList(bytes));
      source.validate();
      return NativeWorkspaceRows._(directory, source.readRows());
    } on RangeError {
      _blocked();
    } on FormatException {
      _blocked();
    }
  }
  @override
  final String directory;
  @override
  String get name => 'workspace';
  final Map<String, List<StoredRow>> _rows;
  List<StoredRow> _collection(String name) =>
      _rows[name] ?? (throw StateError('STORAGE_BLOCKED'));
  @override
  Future<T> readTransaction<T>(Future<T> Function() read) =>
      Future<T>.sync(read);
  @override
  Future<int> count(String collection) async => _collection(collection).length;
  @override
  Future<List<StoredRow>> read(String collection, {required int limit}) async {
    if (limit < 1 || limit > 51251) _blocked();
    return List.unmodifiable(_collection(collection).take(limit));
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
  late int metaBase;
  final trees = <String, _Tree>{};
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
    final completeTransactions = <int>{};
    for (var i = 0; i < 3; i++) {
      final base = i * pageSize;
      if (u16(base + 10) != 8 || u32(base + 16) != i) _blocked();
      if (u64(base + 20) != 0x59659dbdef4c1103) _incompatible();
      if (u32(base + 64) != pageSize || u32(base + 36) != 0) _blocked();
      final first = u64(base + 28), second = u64(base + 196);
      if (first == second && first < 0) _blocked();
      // Incomplete two-phase meta is never used as a committed snapshot.
      if (first <= 0 || first != second) continue;
      // Normal pinned MDBX open rejects same-transaction steady meta clashes,
      // even when the referenced trees are identical. Refuse any complete tie.
      if (!completeTransactions.add(first)) _blocked();
      if (first > transaction) {
        transaction = first;
        selected = base;
      }
    }
    if (selected < 0) _blocked();
    metaBase = selected;
    final sign = u64(selected + 188);
    // meta_sign_calculate in the pinned source returns exactly UINT64_MAX.
    // ByteData exposes those all-one bits as -1 on the Dart VM.
    if (sign != -1) _blocked();
    nextPage = u32(selected + 56);
    if (nextPage < 3 || nextPage * pageSize > bytes.length) _blocked();
    // Pinned x64 geometry: no correction of lower/upper/now on native open.
    // Capacity is not physical file length: upper may exceed the used bytes.
    final lower = u32(selected + 44),
        upper = u32(selected + 48),
        now = u32(selected + 52);
    if (lower < 3 ||
        upper > 0x80000000 ||
        upper < lower ||
        now < lower ||
        now > upper ||
        nextPage > now)
      _blocked();
    final main = _tree(selected + 108);
    if (main.flags != 0 || main.duplicateSize != 0) _blocked();
    final catalogue = _entries(main, namedTrees: true);
    // Structural failure takes precedence over names/schema compatibility.
    for (final entry in catalogue.entries) {
      final tree = _descriptor(entry.value);
      _validateTree(tree);
      trees[entry.key] = tree;
    }
    final info = trees['_info'];
    if (info == null) _incompatible();
    if (info.flags != 0 || info.duplicateSize != 0) _blocked();
    final documents = _entries(info, namedTrees: false);
    inspectNativeRegistry(documents);
    final expected = <String, int>{'_info': 0};
    const schemas = workspaceSchemas;
    for (final collection in schemas) {
      expected[collection.name] = 8; // MDBX_INTEGERKEY for native Id.
      for (final index in collection.indexes.values) {
        expected['_i_${collection.name}_${index.name}'] = 0;
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

  int _page(int number, int flags, int front) {
    if (number < 3 || number >= nextPage || !visited.add(number)) _blocked();
    final base = number * pageSize;
    if (u32(base + 16) != number ||
        u16(base + 10) != flags ||
        u16(base + 8) != 0 ||
        u64(base) < 0 ||
        u64(base) > transaction ||
        u64(base) > front)
      _blocked();
    return base;
  }

  Map<String, Uint8List> _entries(_Tree tree, {required bool namedTrees}) =>
      Map<String, Uint8List>.from(_records(tree, namedTrees: namedTrees));

  Map<Object, Uint8List> _records(
    _Tree tree, {
    bool namedTrees = false,
    _KeyKind keys = _KeyKind.text,
    int maxValueBytes = 16 * 1024,
    int maxItems = 1024,
    int minOverflowValueBytes = 0,
    int spareOverflowPages = 0,
  }) {
    _validateTree(tree);
    if (tree.items > maxItems) _blocked();
    final result = <Object, Uint8List>{};
    if (tree.height == 0) return result;
    var branches = 0, leaves = 0, large = 0;
    Uint8List? previousKey;
    ({Uint8List first, Uint8List last}) walk(int page, int height, int front) {
      final branch = height > 1;
      final base = _page(page, branch ? 1 : 2, front);
      final pageTransaction = u64(base);
      if (branch) {
        branches++;
        if (branches > tree.branches) _blocked();
      } else {
        leaves++;
        if (leaves > tree.leaves) _blocked();
      }
      final lower = u16(base + 12), upper = u16(base + 14);
      if (lower < (branch ? 4 : 2) ||
          lower.isOdd ||
          upper.isOdd ||
          lower > upper ||
          upper > pageSize - 20)
        _blocked();
      final spans = <(int, int)>[];
      Uint8List? firstKey, lastKey, previousChildLast;
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
          final child = walk(size, height - 1, pageTransaction);
          if (i > 0 &&
              (keySize == 0 ||
                  _compareKey(previousChildLast!, keyBytes, keys) >= 0 ||
                  _compareKey(keyBytes, child.first, keys) > 0))
            _blocked();
          firstKey ??= child.first;
          lastKey = child.last;
          previousChildLast = child.last;
          continue;
        }
        if (keySize == 0 ||
            (previousKey != null &&
                _compareKey(previousKey!, keyBytes, keys) >= 0))
          _blocked();
        previousKey = keyBytes;
        firstKey ??= keyBytes;
        lastKey = keyBytes;
        final Object key = switch (keys) {
          _KeyKind.text => utf8.decode(keyBytes, allowMalformed: false),
          _KeyKind.nativeId => _nativeId(keyBytes),
          _KeyKind.transaction => _transactionId(keyBytes),
          _KeyKind.hash => _hashKey(keyBytes),
        };
        if (result.length >= tree.items ||
            result.length >= maxItems ||
            result.containsKey(key))
          _blocked();
        if (namedTrees ? flags != 2 : (flags != 0 && flags != 1)) _blocked();
        final valueStart = node + 8 + keySize;
        final storedSize = flags == 1 ? 4 : size;
        if (valueStart + storedSize > base + pageSize) _blocked();
        spans.add((relative, relative + 8 + keySize + storedSize));
        if (flags == 1) {
          final overflow = u32(valueStart),
              overflowBase = _page(overflow, 4, pageTransaction);
          final count = u32(overflowBase + 12);
          final needed = (size + 20 + pageSize - 1) ~/ pageSize;
          if (size <= minOverflowValueBytes ||
              size > maxValueBytes ||
              count < 1 ||
              overflow + count > nextPage ||
              size + 20 > count * pageSize ||
              count < needed ||
              count > needed + spareOverflowPages)
            _blocked();
          for (var j = 1; j < count; j++) {
            if (!visited.add(overflow + j)) _blocked();
          }
          large += count;
          if (large > tree.large) _blocked();
          result[key] = Uint8List.sublistView(
            bytes,
            overflowBase + 20,
            overflowBase + 20 + size,
          );
        } else {
          if (namedTrees ? size != 48 : size > maxValueBytes) _blocked();
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

    walk(
      tree.root,
      tree.height,
      tree.modified == 0 ? transaction : tree.modified,
    );
    if (result.length != tree.items ||
        branches != tree.branches ||
        leaves != tree.leaves ||
        large != tree.large)
      _blocked();
    return result;
  }

  Map<String, List<StoredRow>> readRows() {
    final result = <String, List<StoredRow>>{};
    for (final schema in workspaceSchemas) {
      final (cap, bound) =
          _rowBounds[schema.name] ?? (throw StateError('INCOMPATIBLE'));
      final singleton =
          schema.name == 'StoredWorkspace' || schema.name == 'StoredSettings';
      final entries = _records(
        trees[schema.name]!,
        keys: _KeyKind.nativeId,
        maxItems: cap,
        maxValueBytes: bound + 270,
      );
      final rows = <StoredRow>[];
      final expectedIndex = <String, int>{};
      for (final entry in entries.entries) {
        final row = _objectRow(
          entry.key as int,
          entry.value,
          singleton: singleton,
          payloadBound: bound,
        );
        rows.add(row);
        if (!singleton) {
          final key = ByteData(8)
            ..setInt64(
              0,
              xxh3(Uint8List.fromList(utf8.encode(row.entityId!))),
              Endian.big,
            );
          final encoded = base64.encode(key.buffer.asUint8List());
          if (expectedIndex.containsKey(encoded)) _blocked();
          expectedIndex[encoded] = row.nativeId;
        }
      }
      if (!singleton) {
        final actual = _records(
          trees['_i_${schema.name}_entityId']!,
          keys: _KeyKind.hash,
          maxItems: cap,
          maxValueBytes: 8,
        );
        if (actual.length != expectedIndex.length) _blocked();
        for (final entry in actual.entries) {
          if (expectedIndex[entry.key] != _nativeId(entry.value)) _blocked();
        }
      }
      result[schema.name] = rows;
    }
    _checkGc();
    return result;
  }

  void _checkGc() {
    final gc = _tree(metaBase + 60);
    if (gc.flags != 8 || gc.duplicateSize != pageSize) _blocked();
    final entries = _records(
      gc,
      keys: _KeyKind.transaction,
      maxItems: nextPage,
      maxValueBytes: (nextPage + 1) * 4,
      minOverflowValueBytes: 4,
      spareOverflowPages: 1,
    );
    final free = <int>{};
    for (final entry in entries.entries) {
      if ((entry.key as int) > transaction) _blocked();
      final value = entry.value;
      if (value.length < 4 || value.length % 4 != 0) _blocked();
      final data = ByteData.sublistView(value);
      final count = data.getUint32(0, Endian.little);
      if (count > nextPage - 3 || value.length < (count + 1) * 4) _blocked();
      var previous = nextPage;
      for (var i = 1; i <= count; i++) {
        final page = data.getUint32(i * 4, Endian.little);
        if (page < 3 ||
            page >= previous ||
            visited.contains(page) ||
            !free.add(page))
          _blocked();
        previous = page;
      }
    }
  }
}

enum _KeyKind { text, nativeId, hash, transaction }

int _nativeId(Uint8List key) {
  if (key.length != 8) _blocked();
  // Isar3.3.2 object/id.rs: native unsigned little-endian key flips sign bit.
  final id =
      ByteData.sublistView(key).getInt64(0, Endian.little) ^
      -9223372036854775808;
  if (id < 1) _blocked();
  return id;
}

int _transactionId(Uint8List key) {
  if (key.length != 8) _blocked();
  final id = ByteData.sublistView(key).getInt64(0, Endian.little);
  if (id < 1) _blocked();
  return id;
}

String _hashKey(Uint8List key) {
  if (key.length != 8) _blocked();
  return base64.encode(key);
}

int _compareKey(Uint8List left, Uint8List right, _KeyKind kind) =>
    switch (kind) {
      _KeyKind.nativeId => _nativeId(left).compareTo(_nativeId(right)),
      _KeyKind.transaction => _transactionId(
        left,
      ).compareTo(_transactionId(right)),
      _ => _compare(left, right),
    };

StoredRow _objectRow(
  int id,
  Uint8List bytes, {
  required bool singleton,
  required int payloadBound,
}) {
  final staticSize = singleton ? 5 : 8;
  if (bytes.length < staticSize ||
      ByteData.sublistView(bytes).getUint16(0, Endian.little) != staticSize)
    _blocked();
  int u24(int at) {
    if (at < 0 || at + 3 > bytes.length) _blocked();
    return bytes[at] | bytes[at + 1] << 8 | bytes[at + 2] << 16;
  }

  final spans = <(int, int)>[];
  String text(int offset, int bound) {
    final start = u24(offset), length = u24(u24(offset));
    if (start < staticSize ||
        length > bound ||
        start + 3 + length > bytes.length)
      _blocked();
    final end = start + 3 + length;
    for (final span in spans) {
      if (start < span.$2 && end > span.$1) _blocked();
    }
    spans.add((start, end));
    return utf8.decode(
      Uint8List.sublistView(bytes, start + 3, end),
      allowMalformed: false,
    );
  }

  final entityId = singleton ? null : text(2, 256);
  final payload = text(singleton ? 2 : 5, payloadBound);
  return StoredRow(id, payload, entityId: entityId);
}

const _rowBounds = <String, (int, int)>{
  'StoredWorkspace': (1, 4096),
  'StoredSettings': (1, 4096),
  'StoredProfile': (250, 16 * 1024),
  'StoredCredential': (250, 512 * 1024),
  'StoredReceipt': (10000, 4096),
  'StoredHostTrust': (250, 4096),
  'StoredMcpGrant': (32, 256 * 1024),
  'StoredDelegation': (1000, 256 * 1024),
  'StoredAutomationProfile': (250, 256 * 1024),
  'StoredAutomationRevision': (5000, 256 * 1024),
  'StoredAutomationPlan': (1000, 256 * 1024),
  'StoredAutomationApproval': (100, 256 * 1024),
  'StoredAutomationJob': (1250, 256 * 1024),
  'StoredDesiredState': (51250, 256 * 1024),
  'StoredAutomationEvent': (10000, 4096),
  'StoredAutomationReceipt': (10000, 8192),
};

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
