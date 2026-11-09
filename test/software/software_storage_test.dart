import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/storage/records.dart';
import 'package:serverdeck/storage/store_manifest.dart';

import '../fixtures/domain_repository.dart';
import '../fixtures/feature_harness.dart' show featureId;

void main() {
  SoftwareCardRecord card(int n, String profile, {int time = 1}) =>
      SoftwareCardRecord()
        ..softwareId = featureId(n)
        ..profileId = profile
        ..name = 'Redis'
        ..createdAt = time
        ..dataPaths = ['/var/lib/redis'];
  SoftwareEventRecord event(
    int n,
    String profile,
    String software, {
    int time = 1,
  }) => SoftwareEventRecord()
    ..eventId = featureId(n)
    ..profileId = profile
    ..softwareId = software
    ..softwareName = 'Redis'
    ..kind = 'created'
    ..summary = 'Created'
    ..createdAt = time;
  test('additive software schemas preserve format and current collections', () {
    expect(currentStorageFormat, 2);
    expect(
      workspaceSchemas.map((s) => s.name),
      containsAll([
        'AppSettings',
        'Profile',
        'Credential',
        'EndpointTrust',
        'McpGrant',
        'MutationReceipt',
        'SecurityState',
        'MonitoringHistoryRecord',
        'JournalSource',
        'SoftwareCardRecord',
        'SoftwareEventRecord',
      ]),
    );
  });
  test(
    'detached sorted pages, card-scoped history and profile cascade',
    () async {
      final repo = MemoryDomainRepository();
      final profile = featureId(1),
          other = featureId(2),
          software = featureId(3);
      await repo.write((r) {
        r.putSoftwareCard(card(3, profile, time: 2));
        r.putSoftwareCard(card(4, profile));
        r.putSoftwareCard(card(5, other));
        r.putSoftwareEvent(event(7, profile, software));
        r.putSoftwareEvent(event(8, profile, software));
        r.putSoftwareEvent(event(9, other, software));
      });
      expect(
        repo.read((r) => r.softwareCards(profile, limit: 1).single.softwareId),
        featureId(4),
      );
      expect(
        repo.read((r) => r.softwareCards(profile, offset: 1).single.softwareId),
        software,
      );
      expect(
        repo
            .read((r) => r.softwareEvents(profile, softwareId: software))
            .map((e) => e.eventId),
        [featureId(8), featureId(7)],
      );
      repo.read((r) => r.softwareCard(software))!.dataPaths.add('/other');
      expect(repo.read((r) => r.softwareCard(software))!.dataPaths, [
        '/var/lib/redis',
      ]);
      await repo.write((r) => r.deleteSoftwareCard(software));
      expect(
        repo
            .read((r) => r.softwareEvents(profile, softwareId: software))
            .length,
        2,
      );
      await repo.write((r) => r.deleteProfile(profile));
      expect(repo.read((r) => r.softwareCardCount()), 1);
      expect(repo.read((r) => r.softwareEventCount()), 1);
    },
  );
  test('eviction uses timestamp and UUID, across the store', () async {
    final repo = MemoryDomainRepository();
    await repo.write((r) {
      for (var i = 4; i < 8; i++) {
        r.putSoftwareEvent(
          event(i, featureId(i), featureId(3), time: i == 4 ? 0 : 1),
        );
      }
      r.pruneSoftwareEvents(2);
    });
    expect(repo.state.softwareEvents.keys, [featureId(6), featureId(7)]);
  });
  for (final fault in ['mid-write', 'commit']) {
    test('$fault rolls back cards, events, receipts and revision', () async {
      final repo = MemoryDomainRepository();
      if (fault == 'mid-write') {
        repo.failAfterWrite = 3;
      } else {
        repo.failCommit = true;
      }
      await expectLater(
        repo.write((r) {
          r.putSoftwareCard(card(3, featureId(1)));
          r.putSoftwareEvent(event(4, featureId(1), featureId(3)));
          r.putReceipt(
            MutationReceipt()
              ..clientId = 'ui'
              ..mutationId = 'one',
          );
          r.putSettings(r.settings..dataRevision = 2);
        }),
        throwsStateError,
      );
      expect(repo.state.softwareCards, isEmpty);
      expect(repo.state.softwareEvents, isEmpty);
      expect(repo.state.receipts, isEmpty);
      expect(repo.state.settings.dataRevision, 1);
    });
  }
}
