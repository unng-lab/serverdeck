import 'package:serverdeck_locald/storage/migration_journal.dart';
import 'package:test/test.dart';

const wid = '10000000-0000-4000-8000-000000000001';
Map<String, Object?> journal() => {
  'format': 1,
  'fromSchema': 2,
  'toSchema': 3,
  'migrationId': wid,
  'workspaceId': wid,
  'receiptKeyId': '10000000-0000-4000-8000-000000000002',
  'ownerSid': 'S-1-5-21-1-2-3-1001',
  'sourceDbDigest': 'a' * 64,
  'sourceManifestDigest': 'b' * 64,
  'sourceKeyWrapperDigest': 'c' * 64,
  'phase': 'preparing',
};
Map<String, Object?> manifest(int schema) => {
  'product': 'serverdeck-next',
  'format': schema,
  'schema': schema,
  'workspaceId': wid,
  'receiptKeyId': '10000000-0000-4000-8000-000000000002',
  'ownerSid': 'S-1-5-21-1-2-3-1001',
};

void main() {
  test(
    'trusted migration codecs are explicitly closed and preserve old steps',
    () {
      final value = journal(), j = MigrationJournal.fromTrustedJson(value);
      expect(j.toJson(), value);
      expect(() => MigrationJournal.fromJson(value), throwsStateError);
      expect(
        () => MigrationJournal.fromTrustedJson({
          ...value,
          'fromSchema': 1,
          'toSchema': 2,
        }),
        throwsStateError,
      );
      final prepared = j.prepare(
        targetDbDigest: 'd' * 64,
        targetManifestDigest: 'e' * 64,
        sourceRowsDigest: 'f' * 64,
      );
      expect(prepared.toJson()['fromSchema'], 2);
      expect(prepared.phase, MigrationPhase.prepared);
      expect(
        () => MigrationJournal.fromJson(prepared.toJson()),
        throwsStateError,
      );
      expect(
        () => prepared.prepare(
          targetDbDigest: 'd' * 64,
          targetManifestDigest: 'e' * 64,
          sourceRowsDigest: 'f' * 64,
        ),
        throwsStateError,
      );
      for (final s in [2, 3])
        expect(MigrationManifest.fromTrustedJson(manifest(s)).schema, s);
      expect(() => MigrationManifest.fromJson(manifest(3)), throwsStateError);
      expect(
        () => MigrationManifest.fromTrustedJson({...manifest(2), 'schema': 1}),
        throwsStateError,
      );
    },
  );
  test(
    'trusted recovery selects only source rebuild and bound target gaps',
    () {
      final src = MigrationManifest.fromTrustedJson(manifest(2)),
          dst = MigrationManifest.fromTrustedJson(manifest(3));
      final prep = MigrationJournal.fromTrustedJson(journal());
      final ready = prep.prepare(
        targetDbDigest: 'd' * 64,
        targetManifestDigest: 'e' * 64,
        sourceRowsDigest: 'f' * 64,
      );
      MigrationAction assess(
        int schema,
        MigrationManifest m,
        MigrationJournal? j,
        String db,
        String mf, {
        String? backup,
      }) => assessTrustedMigration(
        dbSchema: schema,
        manifest: m,
        stage: j == null ? StagePresence.absent : StagePresence.journal,
        journal: j,
        dbDigest: db,
        manifestDigest: mf,
        keyWrapperDigest: 'c' * 64,
        backupDigest: backup,
      );
      expect(assess(2, src, null, 'a' * 64, 'b' * 64), MigrationAction.prepare);
      expect(
        assess(2, src, prep, 'a' * 64, 'b' * 64),
        MigrationAction.rebuildStage,
      );
      expect(
        assess(3, src, ready, 'd' * 64, 'b' * 64, backup: 'a' * 64),
        MigrationAction.verifyTargetThenPublishManifest,
      );
      expect(
        assess(3, dst, ready, 'd' * 64, 'e' * 64),
        MigrationAction.verifyTargetThenCleanup,
      );
      expect(
        assess(3, dst, null, 'd' * 64, 'e' * 64),
        MigrationAction.normalOpen,
      );
      expect(() => assess(3, src, null, 'd' * 64, 'b' * 64), throwsStateError);
      expect(() => assess(2, dst, null, 'a' * 64, 'e' * 64), throwsStateError);
      expect(() => assess(3, src, ready, 'd' * 64, 'b' * 64), throwsStateError);
      expect(() => assess(3, dst, ready, 'a' * 64, 'e' * 64), throwsStateError);
      expect(
        () => assessMigration(
          dbSchema: 2,
          manifest: dst,
          stage: StagePresence.absent,
          journal: null,
          dbDigest: 'd' * 64,
          manifestDigest: 'e' * 64,
          keyWrapperDigest: 'c' * 64,
        ),
        throwsStateError,
      );
      expect(
        () => assessTrustedMigration(
          dbSchema: 2,
          manifest: src,
          stage: StagePresence.journal,
          journal: MigrationJournal.fromJson({
            ...journal(),
            'fromSchema': 1,
            'toSchema': 2,
          }),
          dbDigest: 'a' * 64,
          manifestDigest: 'b' * 64,
          keyWrapperDigest: 'c' * 64,
        ),
        throwsStateError,
      );
    },
  );
}
