import 'dart:convert';

import 'package:serverdeck_locald/storage/host_trust_models.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:test/test.dart';

import 'models_test.dart' as fixture;

const confirmId = '12345678-1234-4234-8234-123456789ab1';

Map<String, Object?> trustRow() => {
  'workspaceId': fixture.workspace,
  'profileId': fixture.profileId,
  'revision': '2',
  'connectionRevision': '1',
  'status': 'trusted',
  'key': {
    'format': 'ssh-ed25519',
    'fingerprint':
        'SHA256:${base64.encode(List.filled(32, 0)).replaceAll('=', '')}',
  },
  'createdAt': fixture.time,
  'updatedAt': fixture.time,
};

Map<String, Object?> confirmed() => {
  ...fixture.populated(),
  'schemaVersion': 3,
  'storeRevision': '2',
  'profiles': {
    fixture.profileId: {
      ...fixture.profile(revision: '2'),
      'name': 'Сервер 🐧',
      'trustRevision': '2',
    },
  },
  'receipts': {
    fixture.requestId: fixture.receipt(),
    confirmId: {
      ...fixture.receipt(),
      'requestId': confirmId,
      'operation': 'servers.trust.confirm',
      'result': {
        'entityId': fixture.profileId,
        'entityRevision': '2',
        'storeRevision': '2',
        'deleted': false,
      },
    },
  },
};

WorkspaceState parse(Map<String, Object?> value) =>
    WorkspaceState.fromTrustedJson(
      value,
      workspaceId: fixture.workspace,
      receiptKeyId: fixture.receiptKeyId,
      ownerSid: fixture.sid,
    );

void main() {
  test(
    'schema3 roundtrip preserves independent epochs and historical receipts',
    () {
      final state = parse(confirmed());
      expect(state.schemaVersion, 3);
      expect(state.toJson(), confirmed());
      final profile = state.profiles[fixture.profileId]!;
      expect(profile.connectionRevision, '1');
      expect(profile.trustRevision, '2');
      final trust = HostTrustState.fromRecords(state, {
        fixture.profileId: HostTrustRecord.fromJson(trustRow()),
      });
      expect(
        trust.foundation.profiles[fixture.profileId]!.view(null).name,
        'Сервер 🐧',
      );
      expect(() => trust.trust.clear(), throwsUnsupportedError);
      final exported = state.toJson();
      (exported['profiles'] as Map).clear();
      expect(state.profiles.length, 1);
      expect(state.receipts[fixture.requestId]!.toJson(), fixture.receipt());
    },
  );

  test('old readers and writers refuse schema3 instead of relabelling it', () {
    final state = parse(confirmed());
    expect(() => fixture.parse(state.toJson()), throwsStateError);
    expect(
      () => ProfileRecord.fromJson(state.profiles[fixture.profileId]!.toJson()),
      throwsStateError,
    );
    expect(
      () => MutationReceipt.fromJson(state.receipts[confirmId]!.toJson()),
      throwsStateError,
    );
    expect(() => WorkspaceRecords.fromState(state), throwsStateError);
    expect(
      () => WorkspaceRecords.fromOperationalState(state),
      throwsStateError,
    );
    expect(
      () => WorkspaceRecords.fromTrustedState(fixture.parse(fixture.empty())),
      throwsStateError,
    );
    for (final schema in [1, 2, '3', 4]) {
      expect(
        () => parse({...confirmed(), 'schemaVersion': schema}),
        throwsStateError,
      );
    }
  });

  test('schema3 foundation rows and sixteenth schema preserve exact shape', () {
    final state = parse(confirmed());
    final rows = WorkspaceRecords.fromTrustedState(state);
    expect(jsonDecode(rows.workspace.payload)['schemaVersion'], 3);
    expect(
      jsonDecode(rows.profiles.single.payload),
      state.profiles[fixture.profileId]!.toJson(),
    );
    expect(
      rows.receipts.map((r) => jsonDecode(r.payload)),
      state.receipts.values.map((r) => r.toJson()),
    );
    expect(trustedWorkspaceSchemas.length, 16);
    expect(trustedWorkspaceSchemas.map((s) => s.name).toSet().length, 16);
    expect(StoredHostTrustSchema.properties.keys, ['entityId', 'payload']);
    expect(StoredHostTrustSchema.indexes['entityId']!.unique, isTrue);
    expect(StoredHostTrustSchema.indexes['entityId']!.replace, isFalse);
  });

  test('schema3 epochs retain uint63 bounds and old equality stays strict', () {
    for (final values in [
      {'connectionRevision': '3', 'trustRevision': '2'},
      {'trustRevision': '3'},
      {'connectionRevision': '0'},
      {'trustRevision': '9223372036854775808'},
      {'credentialRevision': '3'},
    ]) {
      expect(
        () => ProfileRecord.fromTrustedJson({
          ...fixture.profile(revision: '2'),
          ...values,
        }),
        throwsA(anything),
      );
    }
    final maximum = {
      ...fixture.profile(revision: '9223372036854775807'),
      'trustRevision': '9223372036854775807',
    };
    expect(
      ProfileRecord.fromTrustedJson(maximum).trustRevision,
      '9223372036854775807',
    );
    expect(() => ProfileRecord.fromJson(maximum), throwsStateError);
  });

  test(
    'trust references reject orphans, wrong epochs, future time and workspace',
    () {
      final state = parse(confirmed());
      for (final changes in [
        {'workspaceId': fixture.receiptKeyId},
        {'profileId': fixture.receiptKeyId},
        {'revision': '3'},
        {'updatedAt': '2026-10-12T01:00:00.000Z'},
        {'connectionRevision': '2'},
      ]) {
        expect(
          () => HostTrustState.fromRecords(state, {
            fixture.profileId: HostTrustRecord.fromJson({
              ...trustRow(),
              ...changes,
            }),
          }),
          throwsStateError,
        );
      }
      expect(() => HostTrustState.fromRecords(state, {}), throwsStateError);
      expect(
        () => HostTrustState.fromRecords(state, {
          fixture.receiptKeyId: HostTrustRecord.fromJson(trustRow()),
        }),
        throwsStateError,
      );
      expect(
        () => HostTrustState.fromRecords(fixture.parse(fixture.empty()), {}),
        throwsStateError,
      );
    },
  );

  test(
    'migrated never-confirmed and revoked old connection have distinct rules',
    () {
      final migrated = parse({...fixture.populated(), 'schemaVersion': 3});
      expect(HostTrustState.fromRecords(migrated, {}).trust, isEmpty);
      // Connection changed after confirmation: both current epochs are2, while
      // the revoked row retains the originally confirmed connection1.
      final data = confirmed();
      data['profiles'] = {
        fixture.profileId: {
          ...fixture.profile(revision: '2'),
          'connectionRevision': '2',
          'trustRevision': '2',
        },
      };
      final state = parse(data);
      expect(
        HostTrustState.fromRecords(state, {
          fixture.profileId: HostTrustRecord.fromJson({
            ...trustRow(),
            'status': 'revoked',
          }),
        }).trust[fixture.profileId]!.connectionRevision,
        '1',
      );
      expect(
        () => HostTrustState.fromRecords(state, {
          fixture.profileId: HostTrustRecord.fromJson(trustRow()),
        }),
        throwsStateError,
      );
    },
  );

  test(
    'new receipts preserve strict update result and gapless permanent history',
    () {
      final receipt = ((confirmed()['receipts'] as Map)[confirmId] as Map)
          .cast<String, Object?>();
      for (final operation in [
        'servers.trust.confirm',
        'servers.trust.revoke',
      ]) {
        final valid = {...receipt, 'operation': operation};
        expect(MutationReceipt.fromTrustedJson(valid).operation, operation);
        for (final change in [
          {'entityId': null},
          {'entityRevision': '1'},
          {'entityRevision': '3'},
          {'deleted': true},
          {'unexpected': 'field'},
        ]) {
          expect(
            () => MutationReceipt.fromTrustedJson({
              ...valid,
              'result': {...(valid['result'] as Map), ...change},
            }),
            throwsA(anything),
          );
        }
      }
      expect(
        () => MutationReceipt.fromTrustedJson({
          ...receipt,
          'operation': 'servers.trust.reset',
        }),
        throwsStateError,
      );
      expect(
        () => parse({
          ...confirmed(),
          'receipts': {confirmId: receipt},
        }),
        throwsStateError,
      );
      // Historical trust receipts remain valid after deletion of the target.
      expect(
        parse({...confirmed(), 'profiles': <String, Object?>{}})
            .receipts
            .length,
        2,
      );
    },
  );
}
