import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_locald/storage/migration_rows.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:test/test.dart';

const workspaceId = '10000000-0000-4000-8000-000000000001';
const receiptKeyId = '10000000-0000-4000-8000-000000000002';
const profileId = '10000000-0000-4000-8000-000000000003';
String metadata(int schema) => jsonEncode({
  'schemaVersion': schema,
  'workspaceId': workspaceId,
  'receiptKeyId': receiptKeyId,
  'ownerSid': 'S-1-5-21-123',
  'storeRevision': '0',
});
MigrationRows capture({
  int schema = 1,
  List<MigrationRow>? profiles,
  String? settings,
}) => MigrationRows.capture(
  schema: schema,
  workspace: MigrationRow(1, metadata(schema)),
  settings: MigrationRow(1, settings ?? '{"theme":"system"}'),
  profiles:
      profiles ??
      [MigrationRow(7, '{"id":"$profileId","name":"é"}', entityId: profileId)],
  credentials: [],
  receipts: [],
);
String sha(Object? value) => const DartSha256()
    .hashSync(StrictCodec().canonical(value))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

void main() {
  test('streamed preservation digest equals canonical reference and ignores only version', () {
    final snapshot = capture();
    final work = jsonDecode(metadata(1)) as Map<String, Object?>
      ..remove('schemaVersion');
    final reference = {
      'workspace': {'nativeId': 1, 'payload': work},
      'settings': {
        'nativeId': 1,
        'payloadBase64': base64.encode(utf8.encode('{"theme":"system"}')),
      },
      'profiles': [
        {
          'nativeId': 7,
          'entityId': profileId,
          'payloadBase64': base64.encode(
            utf8.encode('{"id":"$profileId","name":"é"}'),
          ),
        },
      ],
      'credentials': [],
      'receipts': [],
    };
    expect(snapshot.digest(), sha(reference));
    expect(snapshot.digest(), capture(schema: 2).digest());
  });

  test(
    'IDs, exact payload bytes, Unicode spelling and escaping remain bound',
    () {
      final original = capture().digest();
      for (final row in [
        MigrationRow(8, '{"id":"$profileId","name":"é"}', entityId: profileId),
        MigrationRow(7, '{"name":"é","id":"$profileId"}', entityId: profileId),
        MigrationRow(
          7,
          '{"id":"$profileId","name":"e\u0301"}',
          entityId: profileId,
        ),
        MigrationRow(
          7,
          '{"id":"$profileId","name":"\\u00e9"}',
          entityId: profileId,
        ),
      ]) {
        expect(capture(profiles: [row]).digest(), isNot(original));
      }
      expect(
        capture(settings: '{ "theme": "system" }').digest(),
        isNot(original),
      );
    },
  );

  test(
    'row ordering canonicalizes by native ID and capture isolates caller lists',
    () {
      const otherId = '10000000-0000-4000-8000-000000000004';
      final first = MigrationRow(7, '{"id":"$profileId"}', entityId: profileId);
      final second = MigrationRow(2, '{"id":"$otherId"}', entityId: otherId);
      final rows = [first, second];
      final snapshot = capture(profiles: rows);
      expect(snapshot.digest(), capture(profiles: [second, first]).digest());
      rows.clear();
      expect(snapshot.digest(), capture(profiles: [first, second]).digest());
    },
  );

  test('duplicate, malformed and excessive native snapshots fail closed', () {
    final valid = MigrationRow(7, '{"id":"$profileId"}', entityId: profileId);
    for (final rows in <List<MigrationRow>>[
      [valid, valid],
      [MigrationRow(0, '{}', entityId: profileId)],
      [MigrationRow(7, '{"id":"$receiptKeyId"}', entityId: profileId)],
      [MigrationRow(7, '{private-marker', entityId: profileId)],
      [MigrationRow(7, '{}')],
      List.filled(251, valid),
    ]) {
      expect(() => capture(profiles: rows), throwsStateError);
    }
    expect(() => capture(schema: 3), throwsStateError);
    expect(() => capture(settings: '{"x":"${'a' * 4096}"}'), throwsStateError);
  });
}
