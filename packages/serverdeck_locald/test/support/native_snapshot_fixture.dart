import 'dart:convert';
import 'dart:typed_data';

int selectedMeta(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final size = data.getUint32(64, Endian.little);
  var selected = 0;
  for (var i = 1; i < 3; i++) {
    if (data.getUint64(i * size + 28, Endian.little) >
        data.getUint64(selected + 28, Endian.little))
      selected = i * size;
  }
  return selected;
}

int namedDescriptor(Uint8List bytes, String name) {
  final data = ByteData.sublistView(bytes), meta = selectedMeta(bytes);
  final size = data.getUint32(64, Endian.little);
  final root = data.getUint32(meta + 116, Endian.little) * size;
  if (data.getUint16(root + 10, Endian.little) != 2)
    throw StateError('FIXTURE_LEAF');
  for (var i = 0; i < data.getUint16(root + 12, Endian.little) ~/ 2; i++) {
    final node = root + 20 + data.getUint16(root + 20 + i * 2, Endian.little);
    final key = data.getUint16(node + 6, Endian.little);
    if (utf8.decode(bytes.sublist(node + 8, node + 8 + key)) == name)
      return node + 8 + key;
  }
  throw StateError('FIXTURE_DESCRIPTOR');
}

/// Restructures real native leaf entries into a two-leaf branch fixture.
/// This constructs bytes in RAM; it never writes or opens the altered database.
({Uint8List bytes, int separator, int childPointer, int root}) branchFixture(
  Uint8List source, {
  required bool info,
}) {
  final original = ByteData.sublistView(source), meta = selectedMeta(source);
  final size = original.getUint32(64, Endian.little);
  final descriptor = info ? namedDescriptor(source, '_info') : meta + 108;
  final root = original.getUint32(descriptor + 8, Endian.little) * size;
  if (original.getUint16(root + 10, Endian.little) != 2)
    throw StateError('FIXTURE_LEAF');
  final next = original.getUint32(meta + 56, Endian.little);
  final requiredLength = (next + 3) * size;
  final bytes = Uint8List(
    source.length > requiredLength ? source.length : requiredLength,
  )..setAll(0, source);
  final data = ByteData.sublistView(bytes);
  final entries = <Uint8List>[];
  for (var i = 0; i < original.getUint16(root + 12, Endian.little) ~/ 2; i++) {
    final node =
        root + 20 + original.getUint16(root + 20 + i * 2, Endian.little);
    if (source[node + 4] != (info ? 0 : 2)) throw StateError('FIXTURE_INLINE');
    final length =
        8 +
        original.getUint16(node + 6, Endian.little) +
        original.getUint32(node, Endian.little);
    entries.add(Uint8List.fromList(source.sublist(node, node + length)));
  }
  void page(int number, int flags, List<Uint8List> nodes) {
    final base = number * size;
    data.setUint64(
      base,
      original.getUint64(meta + 28, Endian.little),
      Endian.little,
    );
    data.setUint16(base + 10, flags, Endian.little);
    data.setUint32(base + 16, number, Endian.little);
    var upper = size - 20;
    for (var i = 0; i < nodes.length; i++) {
      upper -= (nodes[i].length + 1) & ~1;
      bytes.setRange(
        base + 20 + upper,
        base + 20 + upper + nodes[i].length,
        nodes[i],
      );
      data.setUint16(base + 20 + i * 2, upper, Endian.little);
    }
    data.setUint16(base + 12, nodes.length * 2, Endian.little);
    data.setUint16(base + 14, upper, Endian.little);
  }

  Uint8List child(int number, List<int> key) {
    final node = Uint8List(8 + key.length), d = ByteData(8 + key.length);
    d.setUint32(0, number, Endian.little);
    d.setUint16(6, key.length, Endian.little);
    node.setAll(0, d.buffer.asUint8List());
    node.setAll(8, key);
    return node;
  }

  final split = entries.length ~/ 2;
  page(next, 2, entries.sublist(0, split));
  page(next + 1, 2, entries.sublist(split));
  final keySize = ByteData.sublistView(entries[split])
      .getUint16(6, Endian.little);
  page(next + 2, 1, [
    child(next, []),
    child(next + 1, entries[split].sublist(8, 8 + keySize)),
  ]);
  data.setUint32(meta + 56, next + 3, Endian.little);
  data.setUint16(descriptor + 2, 2, Endian.little);
  data.setUint32(descriptor + 8, next + 2, Endian.little);
  data.setUint32(descriptor + 12, 1, Endian.little);
  data.setUint32(descriptor + 16, 2, Endian.little);
  final branch = (next + 2) * size;
  return (
    bytes: bytes,
    separator: branch + 20 + data.getUint16(branch + 22, Endian.little),
    childPointer: branch + 20 + data.getUint16(branch + 20, Endian.little),
    root: next + 2,
  );
}
