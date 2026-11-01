import 'package:serverdeck_engine/storage/workspace_manifest.dart';
import 'package:test/test.dart';

const workspaceId = '12345678-1234-4234-9234-123456789abc';
const receiptKeyId = '12345678-1234-4234-9234-123456789abd';
const ownerSid = 'S-1-5-21-1-2-3-1001';

Map<String, Object?> current() => {
  'product': 'serverdeck-next',
  'schema': 3,
  'format': 3,
  'workspaceId': workspaceId,
  'receiptKeyId': receiptKeyId,
  'ownerSid': ownerSid,
};

Matcher safeFailure(String code) => throwsA(
  isA<StateError>().having((error) => error.message, 'safe code', code),
);

void main() {
  test(
    'target manifest preserves identity without retaining mutable input',
    () {
      final input = current();
      final manifest = WorkspaceManifest.fromJson(input);
      input['workspaceId'] = receiptKeyId;
      expect(manifest.workspaceId, workspaceId);
      expect(manifest.receiptKeyId, receiptKeyId);
      expect(manifest.ownerSid, ownerSid);
      expect(manifest.schema, 3);
      final output = manifest.toJson();
      expect(output, current());
      output['ownerSid'] = 'private-untrusted-value';
      expect(manifest.toJson(), current());
    },
  );

  test('old, unknown and noninteger formats have no compatibility path', () {
    for (final version in <Object?>[null, 0, 1, 2, 4, 3.0, '3', true]) {
      for (final field in ['schema', 'format']) {
        final input = current()..[field] = version;
        final before = Map<String, Object?>.from(input);
        expect(
          () => WorkspaceManifest.fromJson(input),
          // The closed codec rejects doubles before version classification.
          safeFailure(version is double ? 'STORAGE_BLOCKED' : 'INCOMPATIBLE'),
        );
        expect(input, before);
      }
    }
  });

  test('corrupt identity and foreign fields remain blocked without repair', () {
    for (final input in [
      current()..['workspaceId'] = 'private-invalid-id',
      current()..['receiptKeyId'] = 'private-invalid-id',
      current()..['ownerSid'] = 'private-invalid-owner',
      current()..['product'] = 'foreign',
      current()..remove('receiptKeyId'),
      current()..['legacyMigration'] = true,
      current()..['unexpected'] = List.filled(4097, 'x').join(),
    ]) {
      final before = Map<String, Object?>.from(input);
      expect(
        () => WorkspaceManifest.fromJson(input),
        safeFailure('STORAGE_BLOCKED'),
      );
      expect(input, before);
    }
  });
}
