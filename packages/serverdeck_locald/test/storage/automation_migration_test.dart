import 'package:serverdeck_locald/storage/migration_journal.dart';
import 'package:test/test.dart';

const workspace = '10000000-0000-4000-8000-000000000001';
const key = '10000000-0000-4000-8000-000000000002';
const migration = '10000000-0000-4000-8000-000000000003';
const sid = 'S-1-5-21-123';
final source = 'a' * 64, manifest1 = 'b' * 64, wrapper = 'c' * 64;
final target = 'd' * 64, manifest2 = 'e' * 64, rows = 'f' * 64;

Map<String, Object?> journalJson({bool prepared = false}) => {
  'format': 1,
  'fromSchema': 1,
  'toSchema': 2,
  'migrationId': migration,
  'workspaceId': workspace,
  'receiptKeyId': key,
  'ownerSid': sid,
  'sourceDbDigest': source,
  'sourceManifestDigest': manifest1,
  'sourceKeyWrapperDigest': wrapper,
  'phase': prepared ? 'prepared' : 'preparing',
  if (prepared) ...{
    'targetDbDigest': target,
    'targetManifestDigest': manifest2,
    'sourceRowsDigest': rows,
  },
};
MigrationManifest manifest(int schema) => MigrationManifest.fromJson({
  'product': 'serverdeck-next',
  'schema': schema,
  if (schema == 2) 'format': 2,
  'workspaceId': workspace,
  'receiptKeyId': key,
  'ownerSid': sid,
});

void main() {
  test('strict preparing/prepared journal snapshots cannot gain fields by mutation', () {
    final input = journalJson();
    final original = MigrationJournal.fromJson(input);
    input['targetDbDigest'] = target;
    expect(original.toJson(), journalJson());
    final prepared = original.prepare(
      targetDbDigest: target,
      targetManifestDigest: manifest2,
      sourceRowsDigest: rows,
    );
    expect(prepared.toJson(), journalJson(prepared: true));
    expect(original.phase, MigrationPhase.preparing);
    expect(
      MigrationJournal.fromJson(prepared.toJson()).toJson(),
      prepared.toJson(),
    );
    expect(
      () => prepared.prepare(
        targetDbDigest: target,
        targetManifestDigest: manifest2,
        sourceRowsDigest: rows,
      ),
      throwsStateError,
    );
    for (final patch in <Map<String, Object?>>[
      {'format': 1.0},
      {'fromSchema': 0},
      {'toSchema': 3},
      {'phase': 'committed'},
      {'migrationId': 'private-marker'},
      {'sourceDbDigest': source.toUpperCase()},
      {'ownerSid': 'private-marker'},
      {'targetDbDigest': target},
      {'sourceRowsDigest': rows},
      {'path': 'private-marker'},
    ]) {
      expect(
        () => MigrationJournal.fromJson({...journalJson(), ...patch}),
        throwsStateError,
      );
    }
    final missing = journalJson(prepared: true)..remove('sourceRowsDigest');
    expect(() => MigrationJournal.fromJson(missing), throwsStateError);
  });

  test(
    'manifest versions are exact and unsupported combinations never coerce',
    () {
      expect(manifest(1).toJson().containsKey('format'), isFalse);
      expect(manifest(2).toJson()['format'], 2);
      for (final input in <Map<String, Object?>>[
        {...manifest(1).toJson(), 'format': 1},
        {...manifest(2).toJson(), 'format': 1},
        {...manifest(1).toJson(), 'schema': 1.0},
        {...manifest(1).toJson(), 'schema': 3},
        {...manifest(1).toJson(), 'product': 'foreign'},
      ]) {
        expect(() => MigrationManifest.fromJson(input), throwsStateError);
      }
    },
  );

  MigrationAction assess(
    int db,
    int version,
    StagePresence stage, {
    MigrationJournal? journal,
    String? dbHash,
    String? manifestHash,
    String? keyHash,
    String? backupHash,
  }) => assessMigration(
    dbSchema: db,
    manifest: manifest(version),
    stage: stage,
    journal: journal,
    dbDigest: dbHash ?? (db == 1 ? source : target),
    manifestDigest: manifestHash ?? (version == 1 ? manifest1 : manifest2),
    keyWrapperDigest: keyHash ?? wrapper,
    backupDigest: backupHash,
  );

  test(
    'recovery table selects preparation, rebuild, commit gap and cleanup only',
    () {
      final preparing = MigrationJournal.fromJson(journalJson());
      final prepared = MigrationJournal.fromJson(journalJson(prepared: true));
      for (final stage in [StagePresence.absent, StagePresence.empty]) {
        expect(assess(1, 1, stage), MigrationAction.prepare);
        expect(assess(2, 2, stage), MigrationAction.normalOpen);
      }
      for (final journal in [preparing, prepared]) {
        expect(
          assess(1, 1, StagePresence.journal, journal: journal),
          MigrationAction.rebuildStage,
        );
      }
      expect(
        assess(
          2,
          1,
          StagePresence.journal,
          journal: prepared,
          backupHash: source,
        ),
        MigrationAction.verifyTargetThenPublishManifest,
      );
      expect(
        assess(
          2,
          2,
          StagePresence.journal,
          journal: prepared,
          backupHash: source,
        ),
        MigrationAction.verifyTargetThenCleanup,
      );
      expect(
        assess(2, 2, StagePresence.journal, journal: prepared),
        MigrationAction.verifyTargetThenCleanup,
      );
    },
  );

  test(
    'mismatched hashes, foreign identities and unjournaled commit gap block',
    () {
      final prepared = MigrationJournal.fromJson(journalJson(prepared: true));
      for (final check in <void Function()>[
        () => assess(2, 1, StagePresence.absent),
        () => assess(1, 2, StagePresence.journal, journal: prepared),
        () => assess(2, 1, StagePresence.journal, journal: prepared),
        () => assess(
          2,
          1,
          StagePresence.journal,
          journal: prepared,
          backupHash: target,
        ),
        () => assess(
          2,
          2,
          StagePresence.journal,
          journal: prepared,
          dbHash: source,
        ),
        () => assess(
          2,
          2,
          StagePresence.journal,
          journal: prepared,
          manifestHash: manifest1,
        ),
        () => assess(
          1,
          1,
          StagePresence.journal,
          journal: prepared,
          keyHash: target,
        ),
        () => assess(
          1,
          1,
          StagePresence.journal,
          journal: MigrationJournal.fromJson({
            ...journalJson(),
            'workspaceId': key,
          }),
        ),
        () => assess(1, 1, StagePresence.empty, journal: prepared),
        () => assess(
          2,
          2,
          StagePresence.journal,
          journal: MigrationJournal.fromJson(journalJson()),
        ),
        () => assess(3, 2, StagePresence.absent),
      ]) {
        expect(check, throwsStateError);
      }
    },
  );

  test('journal rejection uses fixed errors without input source', () {
    try {
      MigrationJournal.fromJson({...journalJson(), 'private-marker': true});
      fail('Expected rejection');
    } on StateError catch (error) {
      expect(error.message, 'STORAGE_BLOCKED');
      expect(error.toString(), isNot(contains('private-marker')));
    }
  });
}
