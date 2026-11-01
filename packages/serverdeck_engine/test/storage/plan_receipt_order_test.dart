import 'dart:convert';

import 'package:serverdeck_engine/automation/snapshot.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:test/test.dart';

import '../support/actual_plan_fixture.dart';
import 'actual_state_store_test.dart' as actual;

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));

  test(
    'plan receipt admits later persistence and survives checked reopen',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final fixture = await planFixture(store, 950);
      final later = actual.now().add(const Duration(seconds: 1));
      final result = await persist(store, fixture, clock: () => later);
      expect(
        store.snapshot.automation.receipts[fixture.$1.requestId]!.createdAt,
        later,
      );
      expect(fixture.$2.createdAt.isBefore(later), isTrue);
      await store.close();
      final reopened = await setup.open();
      expect(
        reopened.snapshot.automation.plans[fixture.$2.id]!.toJson(),
        fixture.$2.toJson(),
      );
      expect(await persist(reopened, fixture, clock: () => later), result);
    },
  );

  for (final fault in ['earlier', 'request', 'digest', 'duplicate']) {
    test('later plan receipt still rejects $fault evidence', () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final fixture = await planFixture(store, 951);
      await persist(store, fixture);
      const families = {
        'grants': 'StoredMcpGrant',
        'delegations': 'StoredDelegation',
        'profiles': 'StoredAutomationProfile',
        'revisions': 'StoredAutomationRevision',
        'plans': 'StoredAutomationPlan',
        'approvals': 'StoredAutomationApproval',
        'jobs': 'StoredAutomationJob',
        'desired': 'StoredDesiredState',
        'events': 'StoredAutomationEvent',
        'receipts': 'StoredAutomationReceipt',
      };
      final rows = {
        for (final group in families.entries)
          group.key: [
            for (final row in store.snapshot.rows[group.value]!)
              AutomationSnapshotRow(row.nativeId, row.entityId!, row.payload),
          ],
      };
      final receipts = rows['receipts']!;
      final index = receipts.indexWhere(
        (r) => r.entityId == fixture.$1.requestId,
      );
      final row = receipts[index];
      final document = jsonDecode(row.payload) as Map<String, dynamic>;
      switch (fault) {
        case 'earlier':
          document['createdAt'] = fixture.$2.createdAt
              .subtract(const Duration(milliseconds: 1))
              .toIso8601String();
        case 'request':
          document['requestId'] = actual.id(952);
        case 'digest':
          (document['result'] as Map)['planDigest'] = '0' * 64;
        case 'duplicate':
          receipts.add(
            AutomationSnapshotRow(
              9999,
              actual.id(953),
              jsonEncode({...document, 'requestId': actual.id(953)}),
            ),
          );
      }
      receipts[index] = AutomationSnapshotRow(
        row.nativeId,
        fault == 'request' ? actual.id(952) : row.entityId,
        jsonEncode(document),
      );
      await expectLater(
        AutomationSnapshot.load(
          foundation: store.snapshot.foundation,
          collections: rows,
        ),
        actual.failure('STORAGE_BLOCKED'),
      );
      expect(store.isReady, isTrue);
    });
  }
}
