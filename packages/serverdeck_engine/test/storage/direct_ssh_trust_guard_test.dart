import 'dart:convert';

import 'package:serverdeck_engine/profiles/host_trust.dart';
import 'package:serverdeck_engine/storage/host_trust_models.dart';
import 'package:serverdeck_engine/storage/models.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:test/test.dart';

import '../support/actual_plan_fixture.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'actual_plan_job_store_test.dart' as commands;
import 'actual_state_store_test.dart' as actual;

/// Structural storage boundary only. Fresh owner/probe/native authorization is
/// covered by the actual MCP/owner trust recovery test, not minted by this data.
HostTrustState proposed(StateStore store, String fault, int request) {
  final before = store.snapshot.foundation;
  final profile = before.foundation.profiles[fixture.profile]!;
  final prepared = prepareHostTrustMutation(before, 'servers.trust.revoke', {
    'profileId': fixture.profile,
    'expectedRevision': profile.revision,
  }, actual.now().toIso8601String());
  final value = prepared.value;
  (value['receipts'] as Map)[actual.id(request)] = {
    'requestId': actual.id(request),
    'inputDigest': fixture.digest,
    'operation': fault == 'receipt'
        ? 'profiles.update'
        : 'servers.trust.revoke',
    'profileId': fixture.profile,
    'result': prepared.result.toJson(),
    'committedAt': actual.now().toIso8601String(),
  };
  final nextProfile = (value['profiles'] as Map)[fixture.profile] as Map;
  if (fault == 'endpoint') {
    nextProfile['address'] = 'another.invalid';
    nextProfile['connectionRevision'] = '2';
  }
  if (fault == 'credential') {
    ((value['credentials'] as Map)[profile.credentialRef]
        as Map)['protectedBlob'] = base64.encode(
      List.filled(32, 9),
    );
  }
  final rows = {...prepared.trust};
  if (fault == 'key' || fault == 'createdAt') {
    final changed = rows[fixture.profile]!.toJson();
    if (fault == 'key')
      changed['key'] = {
        'format': 'ssh-ed25519',
        'fingerprint':
            'SHA256:' + base64.encode(List.filled(32, 3)).replaceAll('=', ''),
      };
    if (fault == 'createdAt')
      changed['createdAt'] = actual.now().toIso8601String();
    rows[fixture.profile] = HostTrustRecord.fromJson(changed);
  }
  return HostTrustState.fromRecords(
    WorkspaceState.fromJson(
      value,
      workspaceId: before.foundation.workspaceId,
      receiptKeyId: before.foundation.receiptKeyId,
      ownerSid: before.foundation.ownerSid,
    ),
    rows,
  );
}

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));
  for (final fault in [
    'none',
    'key',
    'endpoint',
    'credential',
    'receipt',
    'format1',
    'createdAt',
  ]) {
    test(
      'admitted direct trust guard preserves history and rejects $fault identity change',
      () async {
        final setup = await actual.Setup.create(), store = await setup.open();
        final built = await planFixture(
          store,
          40,
          directSsh: fault != 'format1',
        );
        await persist(store, built);
        await approve(store, built.$2, 50);
        final admitted = await commands.job(
          store,
          'job.apply',
          60,
          built.$2.id,
          verifiedDigest: built.$2.toJson()['digest'] as String,
        );
        final id = admitted['jobId'] as String;
        final job = store.snapshot.automation.jobs[id]!.toJson();
        final before = actual.rawRows(store),
            commits = setup.provider.lastOpened!.commits;
        final next = proposed(store, fault, 70);
        if (fault == 'none') {
          await store.commitFoundation(next);
          expect(
            store.snapshot.foundation.trust[fixture.profile]!
                .toJson()['status'],
            'revoked',
          );
          expect(store.snapshot.automation.jobs[id]!.toJson(), job);
          expect(
            store.snapshot.automation.plans[built.$2.id]!.toJson(),
            built.$2.toJson(),
          );
          // Same-key repeated revoke remains legal without resetting the attempt.
          await store.commitFoundation(proposed(store, 'none', 71));
          expect(store.snapshot.automation.jobs[id]!.toJson(), job);
          expect(
            () => store.validateTrustedJobStep(
              id,
              originGrantId: null,
              expectedGrantRevision: null,
              at: actual.now(),
            ),
            actual.failure('PLAN_STALE'),
          );
        } else {
          await expectLater(
            store.commitFoundation(next),
            actual.failure('HOST_BUSY'),
          );
          expect(actual.rawRows(store), before);
          expect(setup.provider.lastOpened!.commits, commits);
        }
        expect(store.isReady, isTrue);
      },
    );
  }
}
