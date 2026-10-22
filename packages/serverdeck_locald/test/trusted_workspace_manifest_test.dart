import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/migration_journal.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

const workspace = '12345678-1234-4234-8234-123456789abc';
const keyId = '12345678-1234-4234-8234-123456789abd';
Map<String, Object?> fixture() => {
  'product': 'serverdeck-next',
  'format': 3,
  'schema': 3,
  'workspaceId': workspace,
  'receiptKeyId': keyId,
  'ownerSid': 'S-1-5-21-1-2-3-1001',
};

void main() {
  test('workspace format3 is strict, immutable and refused by old parser', () {
    final source = fixture(),
        parsed = TrustedWorkspaceManifest.fromJson(fixture());
    expect(parsed.schema, 3);
    expect(parsed.toJson(), source);
    source['workspaceId'] = keyId;
    expect(parsed.workspaceId, workspace);
    parsed.toJson().clear();
    expect(parsed.toJson(), fixture());
    expect(() => MigrationManifest.fromJson(fixture()), throwsStateError);
    for (final field in fixture().keys) {
      expect(
        () => TrustedWorkspaceManifest.fromJson(fixture()..remove(field)),
        throwsStateError,
      );
    }
    for (final change in <Map<String, Object?>>[
      {'format': 2},
      {'schema': 2},
      {'format': 3.0},
      {'schema': 3.0},
      {'product': 'other'},
      {'owner': true},
      {'workspaceId': workspace.toUpperCase()},
      {'receiptKeyId': 'unknown'},
      {'ownerSid': 'unknown'},
      {'extra': 'x' * 4096},
    ]) {
      expect(
        () => TrustedWorkspaceManifest.fromJson({...fixture(), ...change}),
        throwsStateError,
      );
    }
  });

  test(
    'real CurrentUser key custody binds3 and preserves v1 wrapper/digest',
    () async {
      final custody = KeyCustody(DpapiProtection(), currentUserSid());
      final key = await custody.createReceiptKey(workspace, keyId);
      final reopened = await custody.openReceiptKey(
        key.wrapper,
        workspace,
        keyId,
      );
      try {
        final doc = await custody.createTrustedWorkspaceManifest(key);
        expect(doc, {...fixture(), 'ownerSid': currentUserSid()});
        await custody.verifyTrustedWorkspaceManifest(doc, reopened);
        final legacy = await custody.createWorkspaceManifest(key);
        expect(legacy['schema'], 1);
        expect(legacy.containsKey('format'), isFalse);
        await expectLater(
          custody.verifyWorkspaceManifest(doc, key),
          throwsStateError,
        );
        await expectLater(
          custody.verifyTrustedWorkspaceManifest(legacy, key),
          throwsStateError,
        );
        for (final change in <Map<String, Object?>>[
          {'workspaceId': keyId},
          {'receiptKeyId': workspace},
          {'ownerSid': '${currentUserSid()}-1'},
        ]) {
          await expectLater(
            custody.verifyTrustedWorkspaceManifest({...doc, ...change}, key),
            throwsStateError,
          );
        }
        expect(
          custody.receiptDigestSync(key, {'operation': 'synthetic'}),
          custody.receiptDigestSync(reopened, {'operation': 'synthetic'}),
        );
        key.close();
        await expectLater(
          custody.createTrustedWorkspaceManifest(key),
          throwsStateError,
        );
        await expectLater(
          custody.verifyTrustedWorkspaceManifest(doc, key),
          throwsStateError,
        );
      } finally {
        key.close();
        reopened.close();
      }
    },
    testOn: 'windows',
  );
}
