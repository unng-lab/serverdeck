import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:xxh3/xxh3.dart';

import 'native_registry_fixture.dart';

// Synthetic byte construction only. No native writer/DB/file/process is used.
// Layout constants are literal pinned Isar/MDBX contracts, not decoder outputs.
const pageSize = 16384;
typedef Entry = ({Uint8List key, Uint8List value});

final class NativeFixture {
  NativeFixture(this.bytes, this.roots);
  final Uint8List bytes;
  final Map<String, int> roots;
  ByteData get data => ByteData.sublistView(bytes);
  int firstNode(String collection) {
    final base = roots[collection]! * pageSize;
    return base + 20 + data.getUint16(base + 20, Endian.little);
  }

  int objectOffset(String collection) {
    final node = firstNode(collection);
    final value = node + 8 + data.getUint16(node + 6, Endian.little);
    return bytes[node + 4] == 1
        ? data.getUint32(value, Endian.little) * pageSize + 20
        : value;
  }
}

NativeFixture nativeFixture(
  Map<String, List<StoredRow>> rows, {
  bool branch = false,
  bool gc = false,
  bool singleChildBranch = false,
  int gcPayloadBytes = 8,
  bool forceGcOverflow = false,
  int gcSparePages = 0,
  int gcFreePages = 1,
}) {
  final pages = List.generate(3, (_) => Uint8List(pageSize));
  final roots = <String, int>{};
  Uint8List descriptor({
    int flags = 0,
    int? root,
    int items = 0,
    int height = 1,
    int leaves = 1,
    int large = 0,
  }) {
    final bytes = Uint8List(48), view = ByteData(48);
    view.setUint16(0, flags, Endian.little);
    view.setUint16(2, root == null ? 0 : height, Endian.little);
    view.setUint32(8, root ?? 0xffffffff, Endian.little);
    view.setUint32(12, root == null || height == 1 ? 0 : 1, Endian.little);
    view.setUint32(16, root == null ? 0 : leaves, Endian.little);
    view.setUint32(20, large, Endian.little);
    view.setUint64(32, items, Endian.little);
    view.setUint64(40, root == null ? 0 : 3, Endian.little);
    bytes.setAll(0, view.buffer.asUint8List());
    return bytes;
  }

  ({int page, int large}) leaf(
    List<Entry> entries, {
    int valueFlag = 0,
    bool branch = false,
    bool forceOverflow = false,
    int sparePages = 0,
  }) {
    final number = pages.length, bytes = Uint8List(pageSize);
    pages.add(bytes);
    final view = ByteData.sublistView(bytes);
    view.setUint64(0, 3, Endian.little);
    view.setUint16(10, branch ? 1 : 2, Endian.little);
    view.setUint16(12, entries.length * 2, Endian.little);
    view.setUint32(16, number, Endian.little);
    var upper = pageSize - 20, large = 0;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      var value = entry.value, flags = valueFlag, size = value.length;
      if (branch) {
        size = ByteData.sublistView(value).getUint32(0, Endian.little);
        value = Uint8List(0);
      } else if (value.length > pageSize ~/ 2 || forceOverflow) {
        final count =
            (value.length + 20 + pageSize - 1) ~/ pageSize + sparePages;
        final first = pages.length, overflow = Uint8List(count * pageSize);
        final header = ByteData.sublistView(overflow);
        header.setUint64(0, 3, Endian.little);
        header.setUint16(10, 4, Endian.little);
        header.setUint32(12, count, Endian.little);
        header.setUint32(16, first, Endian.little);
        overflow.setAll(20, value);
        for (var page = 0; page < count; page++) {
          pages.add(
            Uint8List.sublistView(
              overflow,
              page * pageSize,
              (page + 1) * pageSize,
            ),
          );
        }
        value = (ByteData(
          4,
        )..setUint32(0, first, Endian.little)).buffer.asUint8List();
        flags = 1;
        large += count;
      }
      upper = (upper - 8 - entry.key.length - value.length) & ~1;
      if (upper < entries.length * 2)
        throw StateError('UNIT_FIXTURE_TOO_LARGE');
      view.setUint16(20 + i * 2, upper, Endian.little);
      final node = 20 + upper;
      view.setUint32(node, size, Endian.little);
      bytes[node + 4] = flags;
      view.setUint16(node + 6, entry.key.length, Endian.little);
      bytes.setAll(node + 8, entry.key);
      bytes.setAll(node + 8 + entry.key.length, value);
    }
    view.setUint16(14, upper, Endian.little);
    return (page: number, large: large);
  }

  Uint8List tree(
    String name,
    List<Entry> entries, {
    int flags = 0,
    int valueFlag = 0,
    bool split = false,
    bool forceOverflow = false,
    int sparePages = 0,
  }) {
    if (entries.isEmpty) return descriptor(flags: flags);
    if (split && singleChildBranch && entries.length == 1) {
      final child = leaf(entries);
      final parent = leaf([
        (
          key: Uint8List(0),
          value: (ByteData(
            4,
          )..setUint32(0, child.page, Endian.little)).buffer.asUint8List(),
        ),
      ], branch: true);
      roots[name] = parent.page;
      return descriptor(
        flags: flags,
        root: parent.page,
        items: 1,
        height: 2,
        leaves: 1,
        large: child.large,
      );
    }
    if (!split || entries.length < 2) {
      final node = leaf(
        entries,
        valueFlag: valueFlag,
        forceOverflow: forceOverflow,
        sparePages: sparePages,
      );
      roots[name] = node.page;
      return descriptor(
        flags: flags,
        root: node.page,
        items: entries.length,
        large: node.large,
      );
    }
    final cut = entries.length ~/ 2;
    final left = leaf(entries.sublist(0, cut)),
        right = leaf(entries.sublist(cut));
    Uint8List pointer(int page) =>
        (ByteData(4)..setUint32(0, page, Endian.little)).buffer.asUint8List();
    final parent = leaf([
      (key: Uint8List(0), value: pointer(left.page)),
      (key: entries[cut].key, value: pointer(right.page)),
    ], branch: true);
    roots[name] = parent.page;
    return descriptor(
      flags: flags,
      root: parent.page,
      items: entries.length,
      height: 2,
      leaves: 2,
      large: left.large + right.large,
    );
  }

  Uint8List idBytes(int id) =>
      (ByteData(8)..setInt64(0, id ^ -9223372036854775808, Endian.little))
          .buffer
          .asUint8List();
  Uint8List object(StoredRow row) {
    final strings = [
      if (row.entityId != null) utf8.encode(row.entityId!),
      utf8.encode(row.payload),
    ];
    final size = 2 + strings.length * 3;
    final bytes = Uint8List(
      size + strings.fold(0, (n, value) => n + 3 + value.length),
    );
    ByteData.sublistView(bytes).setUint16(0, size, Endian.little);
    void u24(int at, int value) {
      bytes[at] = value;
      bytes[at + 1] = value >> 8;
      bytes[at + 2] = value >> 16;
    }

    var dynamicOffset = size;
    for (var i = 0; i < strings.length; i++) {
      u24(2 + i * 3, dynamicOffset);
      u24(dynamicOffset, strings[i].length);
      bytes.setAll(dynamicOffset + 3, strings[i]);
      dynamicOffset += 3 + strings[i].length;
    }
    return bytes;
  }

  int compare(Entry left, Entry right) {
    for (var i = 0; i < left.key.length; i++) {
      final order = left.key[i].compareTo(right.key[i]);
      if (order != 0) return order;
    }
    return 0;
  }

  final catalogue = <String, Uint8List>{};
  for (final name in names) {
    final values = List<StoredRow>.of(rows[name] ?? [])
      ..sort((a, b) => a.nativeId.compareTo(b.nativeId));
    catalogue[name] = tree(
      name,
      [
        for (final row in values)
          (key: idBytes(row.nativeId), value: object(row)),
      ],
      flags: 8,
      split: branch,
    );
    if (names.indexOf(name) >= 2) {
      Uint8List hashKey(String id) {
        // Independent known XXH3 vector from upstream xxHash: hello.
        if (id == 'hello')
          return Uint8List.fromList([
            0x95,
            0x55,
            0xe8,
            0x55,
            0x5c,
            0x62,
            0xdc,
            0xfd,
          ]);
        return (ByteData(8)..setInt64(
              0,
              xxh3(Uint8List.fromList(utf8.encode(id))),
              Endian.big,
            ))
            .buffer
            .asUint8List();
      }

      final entries = <Entry>[
        for (final row in values)
          (key: hashKey(row.entityId!), value: idBytes(row.nativeId)),
      ]..sort(compare);
      final index = '_i_${name}_entityId';
      catalogue[index] = tree(index, entries);
    }
  }
  final info = registry();
  final infoNames = info.keys.toList()..sort();
  catalogue['_info'] = tree('_info', [
    for (final name in infoNames)
      (
        key: Uint8List.fromList(utf8.encode(name)),
        value: Uint8List.fromList(info[name]!),
      ),
  ]);
  final catalogueNames = catalogue.keys.toList()..sort();
  final main = tree('main', [
    for (final name in catalogueNames)
      (key: Uint8List.fromList(utf8.encode(name)), value: catalogue[name]!),
  ], valueFlag: 2);
  var gcTree = descriptor(flags: 8);
  if (gc) {
    final free = pages.length;
    if (gcPayloadBytes > 4) {
      for (var i = 0; i < gcFreePages; i++) pages.add(Uint8List(pageSize));
    }
    final key = (ByteData(
      8,
    )..setUint64(0, 2, Endian.little)).buffer.asUint8List();
    final payload = ByteData(gcPayloadBytes)
      ..setUint32(0, gcPayloadBytes > 4 ? gcFreePages : 0, Endian.little);
    if (gcPayloadBytes > 4) {
      for (var i = 0; i < gcFreePages; i++) {
        payload.setUint32(
          (i + 1) * 4,
          free + gcFreePages - i - 1,
          Endian.little,
        );
      }
    }
    gcTree = tree(
      'gc',
      [(key: key, value: payload.buffer.asUint8List())],
      flags: 8,
      forceOverflow: forceGcOverflow,
      sparePages: gcSparePages,
    );
  }
  for (var i = 0; i < 3; i++) {
    final meta = pages[i], view = ByteData.sublistView(pages[i]);
    view.setUint16(10, 8, Endian.little);
    view.setUint32(16, i, Endian.little);
    view.setUint64(20, 0x59659dbdef4c1103, Endian.little);
    view.setUint64(28, i + 3, Endian.little);
    view.setUint32(44, 3, Endian.little);
    view.setUint32(48, pages.length + 16, Endian.little);
    view.setUint32(52, pages.length, Endian.little);
    view.setUint32(56, pages.length, Endian.little);
    meta.setAll(60, gcTree);
    view.setUint32(
      64,
      pageSize,
      Endian.little,
    ); // union overlays GC dupfix-size.
    meta.setAll(108, main);
    view.setUint64(188, -1, Endian.little);
    view.setUint64(196, i + 3, Endian.little);
  }
  final bytes = Uint8List(pages.length * pageSize);
  for (var i = 0; i < pages.length; i++) {
    bytes.setAll(i * pageSize, pages[i]);
  }
  return NativeFixture(bytes, roots);
}
