import 'package:path/path.dart' as p;

import '../support/native_registry_fixture.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_engine/storage/models.dart';
import 'package:serverdeck_engine/storage/native_registry.dart';
import 'package:serverdeck_engine/storage/native_schema.dart';
import 'package:serverdeck_engine/storage/records.dart';
import 'package:test/test.dart';

String inspect(Uint8List bytes) => NativeWorkspaceRows.fromSnapshot(
  bytes,
  directory: p.absolute('unit-native-memory'),
).name;

Matcher failure(String code) => throwsA(
  isA<StateError>().having((error) => error.message, 'safe code', code),
);

// Five in-memory pages only. Empty user trees intentionally provide no semantic
// row proof; this fixture exercises metadata and structural preflight only.
Uint8List snapshot() {
  const pageSize = 16384;
  final bytes = Uint8List(5 * pageSize);
  final data = ByteData.sublistView(bytes);
  void u16(int at, int value) => data.setUint16(at, value, Endian.little);
  void u32(int at, int value) => data.setUint32(at, value, Endian.little);
  void u64(int at, int value) => data.setUint64(at, value, Endian.little);
  Uint8List tree({int flags = 0, int? root, int items = 0}) {
    final result = Uint8List(48);
    final view = ByteData.sublistView(result);
    view.setUint16(0, flags, Endian.little);
    view.setUint16(2, root == null ? 0 : 1, Endian.little);
    view.setUint32(8, root ?? 0xffffffff, Endian.little);
    view.setUint32(16, root == null ? 0 : 1, Endian.little);
    view.setUint64(32, items, Endian.little);
    view.setUint64(40, root == null ? 0 : 3, Endian.little);
    return result;
  }

  final documents = registry();
  final catalogue = <String, List<int>>{
    '_info': tree(root: 4, items: names.length),
    for (final name in names) name: tree(flags: 8),
    for (final name in names.skip(2)) '_i_${name}_entityId': tree(),
  };
  for (var page = 0; page < 3; page++) {
    final base = page * pageSize;
    u16(base + 10, 8);
    u32(base + 16, page);
    u64(base + 20, 0x59659dbdef4c1103);
    u64(base + 28, page + 3);
    u32(base + 44, 3);
    u32(base + 48, 21);
    u32(base + 52, 5);
    u32(base + 56, 5);
    u16(base + 60, 8);
    u32(base + 64, pageSize);
    u32(base + 68, 0xffffffff);
    bytes.setRange(
      base + 108,
      base + 156,
      tree(root: 3, items: catalogue.length),
    );
    u64(base + 188, -1);
    u64(base + 196, page + 3);
  }
  void leaf(int page, Map<String, List<int>> values, int flags) {
    final base = page * pageSize;
    u64(base, 3);
    u16(base + 10, 2);
    u32(base + 16, page);
    u16(base + 12, 2 * values.length);
    var upper = pageSize - 20;
    final keys = values.keys.toList()..sort();
    for (var i = 0; i < keys.length; i++) {
      final key = utf8.encode(keys[i]);
      final value = values[keys[i]]!;
      upper = (upper - 8 - key.length - value.length) & ~1;
      u16(base + 20 + i * 2, upper);
      final node = base + 20 + upper;
      u32(node, value.length);
      bytes[node + 4] = flags;
      u16(node + 6, key.length);
      bytes.setRange(node + 8, node + 8 + key.length, key);
      bytes.setRange(
        node + 8 + key.length,
        node + 8 + key.length + value.length,
        value,
      );
    }
    u16(base + 14, upper);
  }

  leaf(3, catalogue, 2);
  leaf(4, documents, 0);
  return bytes;
}

void main() {
  test('exact target registry accepted; prior registries refused', () {
    expect(inspectNativeRegistry(registry()), 3);
    for (final count in [5, 15]) {
      final old = registry()
        ..removeWhere((name, _) => names.indexOf(name) >= count);
      expect(() => inspectNativeRegistry(old), failure('INCOMPATIBLE'));
    }
  });

  test('metadata properties, index semantics and exact fields are closed', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (value) => value['extra'] = true,
      (value) => value['version'] = 3,
      (value) =>
          value['properties'] = (value['properties'] as List).reversed.toList(),
      (value) => (value['indexes'] as List).first['replace'] = true,
      (value) =>
          (value['indexes'] as List).first['properties'][0]['caseSensitive'] =
              false,
    ]) {
      final input = registry();
      final value = jsonDecode(
        utf8.decode(input['StoredProfile']!),
      ) as Map<String, dynamic>;
      change(value);
      input['StoredProfile'] = utf8.encode(jsonEncode(value));
      expect(() => inspectNativeRegistry(input), failure('INCOMPATIBLE'));
    }
  });

  test('corrupt metadata takes precedence over unknown collection', () {
    final input = registry()..['untrusted-secret-name'] = utf8.encode('{');
    expect(() => inspectNativeRegistry(input), failure('STORAGE_BLOCKED'));
  });

  test('target structure accepted without mutating input or opening a DB', () {
    final input = snapshot();
    final before = Uint8List.fromList(input);
    expect(inspect(input), 'workspace');
    expect(input, before);
  });

  test('unsupported native format refused; malformed geometry blocked', () {
    final unsupported = snapshot()..[20] ^= 1;
    expect(() => inspect(unsupported), failure('INCOMPATIBLE'));
    final malformed = snapshot();
    ByteData.sublistView(malformed).setUint16(3 * 16384 + 12, 1, Endian.little);
    expect(() => inspect(malformed), failure('STORAGE_BLOCKED'));
    expect(() => inspect(Uint8List(243)), failure('STORAGE_BLOCKED'));
  });

  test('incomplete newest meta ignored; no complete transaction blocked', () {
    final input = snapshot();
    final data = ByteData.sublistView(input);
    data.setUint64(2 * 16384 + 28, 6, Endian.little);
    expect(inspect(input), 'workspace');
    for (var page = 0; page < 2; page++) {
      data.setUint64(page * 16384 + 28, 6, Endian.little);
    }
    expect(() => inspect(input), failure('STORAGE_BLOCKED'));
  });

  test('reused catalogue page fails closed without native access', () {
    final input = snapshot();
    final data = ByteData.sublistView(input);
    final first = data.getUint16(3 * 16384 + 20, Endian.little);
    data.setUint16(3 * 16384 + 22, first, Endian.little);
    expect(() => inspect(input), failure('STORAGE_BLOCKED'));
  });

  test(
    'new workspace rows preserve schema3 identity and singleton native IDs',
    () {
      const id = '12345678-1234-4234-9234-123456789abc';
      const key = '12345678-1234-4234-9234-123456789abd';
      const sid = 'S-1-5-21-1-2-3-1001';
      final state = WorkspaceState.empty(
        workspaceId: id,
        receiptKeyId: key,
        ownerSid: sid,
      );
      final rows = WorkspaceRecords.fromState(state);
      expect(rows.workspace.id, 1);
      expect(rows.settings.id, 1);
      expect(jsonDecode(rows.workspace.payload), {
        'schemaVersion': 3,
        'workspaceId': id,
        'receiptKeyId': key,
        'ownerSid': sid,
        'storeRevision': '0',
      });
      expect(jsonDecode(rows.settings.payload), state.settings.toJson());
      expect(rows.profiles, isEmpty);
      expect(rows.credentials, isEmpty);
      expect(rows.receipts, isEmpty);
    },
  );
}
