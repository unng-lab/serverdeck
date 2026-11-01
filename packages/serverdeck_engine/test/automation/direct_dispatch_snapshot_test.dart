import 'dart:convert';

import 'package:serverdeck_engine/automation/direct_dispatch_binding.dart';
import 'package:serverdeck_engine/automation/snapshot.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../storage/actual_plan_job_store_test.dart' show job;
import '../storage/actual_state_store_test.dart' as actual;
import '../support/actual_plan_fixture.dart';
import '../support/schema3_fixture.dart' as fixture;

Map<String, List<AutomationSnapshotRow>> capture(AutomationSnapshot graph) {
  List<AutomationSnapshotRow> rows(Map<String, dynamic> values) => [
    for (final entry in values.entries)
      AutomationSnapshotRow(
        values.keys.toList().indexOf(entry.key) + 1,
        entry.key,
        jsonEncode(entry.value.toJson()),
      ),
  ];
  return {
    'grants': rows(graph.grants),
    'delegations': rows(graph.delegations),
    'profiles': rows(graph.profiles),
    'revisions': rows(graph.revisions),
    'plans': rows(graph.plans),
    'approvals': rows(graph.approvals),
    'jobs': rows(graph.jobs),
    'desired': rows(graph.desired),
    'events': rows(graph.events),
    'receipts': rows(graph.receipts),
  };
}

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));

  for (final direct in [false, true]) {
    test(
      'dispatch binding validates exact retained plan, direct=$direct',
      () async {
        final setup = await actual.Setup.create(), store = await setup.open();
        final built = await planFixture(store, 40, directSsh: direct);
        await persist(store, built);
        await approve(store, built.$2, 50);
        final saved = await job(
          store,
          'job.apply',
          60,
          built.$2.id,
          verifiedDigest: built.$2.toJson()['digest'] as String,
        );
        final original = store.snapshot.automation.jobs[saved['jobId']]!;
        final approval =
            store.snapshot.automation.approvals[original.authority.id]!;
        final effect =
            (built.$2.toJson()['effects'] as List).first
                as Map<String, Object?>;
        final dispatch = <String, Object?>{
          'format': 1,
          'stepId': effect['id'],
          'stepDigest': directBindingDigest(effect),
          'token': actual.id(70),
          'bootIdHash': built.$2.preflight!.toJson()['bootIdHash'],
          'issuedUptimeMs': 1000,
          'expiresUptimeMs': 6000,
          'authorityBindingDigest': directAuthorityBinding(
            plan: built.$2,
            authority: original.authority,
            grantId: null,
            grantRevision: null,
            grantExpiresAt: null,
            authorityExpiresAt: approval.expiresAt,
          ),
          'targetBindingDigest': directTargetBinding(built.$2),
          'authorizedAt': actual.now().toIso8601String(),
          'grantRevision': null,
          'grantExpiresAt': null,
          'state': 'authorized',
        };
        Future<AutomationSnapshot> load(
          Map<String, Object?>? value, {
          bool omit = false,
        }) {
          final collections = capture(store.snapshot.automation);
          collections['jobs'] = [
            AutomationSnapshotRow(
              1,
              original.id,
              jsonEncode({
                ...original.toJson(),
                'state': 'running',
                if (!omit) 'sshDispatch': value,
              }),
            ),
          ];
          return AutomationSnapshot.load(
            foundation: fixture.trusted(),
            collections: collections,
          );
        }

        // Historical rows retain their exact absent-field shape.
        final historical = await load(null, omit: true);
        expect(historical.jobs[original.id]!.hasSshDispatchField, isFalse);
        if (!direct) {
          await expectLater(load(dispatch), fixture.blocked());
          await expectLater(load(null), fixture.blocked());
        } else {
          final loaded = await load(dispatch);
          expect(loaded.jobs[original.id]!.sshDispatch!.toJson(), dispatch);
          for (final patch in <Map<String, Object?>>[
            {'stepId': 'uncompiled'},
            {'stepDigest': 'a' * 64},
            {'bootIdHash': 'a' * 64},
            {'targetBindingDigest': 'a' * 64},
            {'authorityBindingDigest': 'a' * 64},
            {
              'authorizedAt': actual
                  .now()
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
            },
            {
              'authorizedAt': actual
                  .now()
                  .add(const Duration(seconds: 1))
                  .toIso8601String(),
            },
            {'grantRevision': 1, 'grantExpiresAt': '2026-10-30T11:00:00.000Z'},
          ]) {
            await expectLater(load({...dispatch, ...patch}), fixture.blocked());
          }
          final next = AutomationJobRecord.fromJson({
            ...original.toJson(),
            'state': 'running',
            'sshDispatch': dispatch,
          });
          original.validateTransitionTo(next);
          expect(
            () => next.validateTransitionTo(original),
            throwsFormatException,
          );
        }
      },
    );
  }
}
