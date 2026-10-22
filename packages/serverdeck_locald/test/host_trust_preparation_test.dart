import 'dart:convert';

import 'package:serverdeck_locald/profiles/host_trust.dart';
import 'package:serverdeck_locald/storage/host_trust_models.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:test/test.dart';

import 'host_trust_models_test.dart' as trusted;
import 'models_test.dart' as fixture;

const stamp = '2026-10-12T01:00:00.000Z';
Map<String, Object?> body({String revision = '1'}) => {
  'profileId': fixture.profileId,
  'expectedRevision': revision,
};
Map<String, Object?> confirm({String revision = '1'}) => {
  ...body(revision: revision),
  'challengeId': trusted.confirmId,
  'key': (trusted.trustRow()['key'] as Map).cast<String, Object?>(),
};
HostTrustState unknown() => HostTrustState.fromRecords(
  trusted.parse({...fixture.populated(), 'schemaVersion': 3}),
  {},
);
HostTrustState known() => HostTrustState.fromRecords(
  trusted.parse(trusted.confirmed()),
  {fixture.profileId: HostTrustRecord.fromJson(trusted.trustRow())},
);
Matcher code(String value) =>
    throwsA(isA<StateError>().having((e) => e.message, 'code', value));

void main() {
  test(
    'confirm prepares independent epochs and preserves the input snapshot',
    () {
      final snapshot = unknown(), before = snapshot.foundation.toJson();
      final prepared = prepareHostTrustMutation(
        snapshot,
        'servers.trust.confirm',
        confirm(),
        stamp,
      );
      final profile =
          (prepared.value['profiles'] as Map)[fixture.profileId] as Map;
      expect(profile['revision'], '2');
      expect(profile['trustRevision'], '2');
      expect(profile['connectionRevision'], '1');
      expect(profile['credentialRevision'], '1');
      expect(profile['updatedAt'], stamp);
      expect(prepared.value['storeRevision'], '2');
      expect(prepared.result.toJson(), {
        'entityId': fixture.profileId,
        'entityRevision': '2',
        'storeRevision': '2',
        'deleted': false,
      });
      expect(prepared.trust[fixture.profileId]!.toJson(), {
        ...trusted.trustRow(),
        'createdAt': stamp,
        'updatedAt': stamp,
      });
      for (final field in ['credentials', 'receipts', 'settings']) {
        expect(prepared.value[field], before[field]);
      }
      expect(snapshot.foundation.toJson(), before);
      expect(snapshot.trust, isEmpty);
    },
  );

  test('reconfirmation preserves original creation and replaces exact key', () {
    final snapshot = known();
    final key = {
      'format': 'ssh-rsa',
      'fingerprint':
          'SHA256:${base64Encode(List.filled(32, 9)).replaceAll('=', '')}',
    };
    final prepared = prepareHostTrustMutation(
      snapshot,
      'servers.trust.confirm',
      {...confirm(revision: '2'), 'key': key},
      stamp,
    );
    final row = prepared.trust[fixture.profileId]!;
    expect(row.toJson(), {
      ...trusted.trustRow(),
      'revision': '3',
      'key': key,
      'updatedAt': stamp,
    });
    expect(snapshot.trust[fixture.profileId]!.revision, '2');
    expect(() => prepared.trust.clear(), throwsUnsupportedError);
  });

  test('revoke preserves key, connection epoch and original creation', () {
    final prepared = prepareHostTrustMutation(
      known(),
      'servers.trust.revoke',
      body(revision: '2'),
      stamp,
    );
    expect(prepared.trust[fixture.profileId]!.toJson(), {
      ...trusted.trustRow(),
      'revision': '3',
      'status': 'revoked',
      'updatedAt': stamp,
    });
    final value = prepared.value;
    // The coordinator, rather than this preparation, owns receipt creation.
    (value['receipts'] as Map)[fixture.credentialId] = {
      ...fixture.receipt(),
      'requestId': fixture.credentialId,
      'operation': 'servers.trust.revoke',
      'result': prepared.result.toJson(),
      'committedAt': stamp,
    };
    final state = WorkspaceState.fromTrustedJson(
      value,
      workspaceId: fixture.workspace,
      receiptKeyId: fixture.receiptKeyId,
      ownerSid: fixture.sid,
    );
    final snapshot = HostTrustState.fromRecords(state, prepared.trust);
    final repeated = prepareHostTrustMutation(
      snapshot,
      'servers.trust.revoke',
      body(revision: '3'),
      stamp,
    );
    expect(repeated.trust[fixture.profileId]!.revision, '4');
    expect(repeated.trust[fixture.profileId]!.status, HostTrustStatus.revoked);
  });

  test('CAS precedes unknown trust and neither refusal changes state', () {
    final snapshot = unknown(), before = snapshot.foundation.toJson();
    expect(
      () => prepareHostTrustMutation(
        snapshot,
        'servers.trust.revoke',
        body(revision: '2'),
        stamp,
      ),
      code('REVISION_CONFLICT'),
    );
    expect(
      () => prepareHostTrustMutation(
        snapshot,
        'servers.trust.revoke',
        body(),
        stamp,
      ),
      code('TRUST_REQUIRED'),
    );
    expect(snapshot.foundation.toJson(), before);
    expect(
      () => prepareHostTrustMutation(snapshot, 'servers.trust.confirm', {
        ...confirm(),
        'profileId': fixture.credentialId,
      }, stamp),
      code('NOT_FOUND'),
    );
  });

  test('only exact trust mutation shapes are accepted', () {
    for (final method in ['profiles.update', 'servers.trust.probe']) {
      expect(
        () => prepareHostTrustMutation(unknown(), method, confirm(), stamp),
        throwsA(anything),
      );
    }
    for (final input in [
      {...confirm(), 'role': 'owner'},
      {...confirm(), 'expectedRevision': 1},
      {
        ...confirm(),
        'key': {'format': 'ssh-rsa', 'fingerprint': 'invalid'},
      },
    ]) {
      expect(
        () => prepareHostTrustMutation(
          unknown(),
          'servers.trust.confirm',
          input,
          stamp,
        ),
        throwsA(anything),
      );
    }
  });

  test('reconfirm after connection change replaces the confirmed epoch', () {
    final document = trusted.confirmed();
    document['storeRevision'] = '3';
    (document['profiles'] as Map)[fixture.profileId] = <String, Object?>{
      ...((document['profiles'] as Map)[fixture.profileId] as Map),
      'revision': '3',
      'connectionRevision': '2',
      'trustRevision': '3',
    };
    (document['receipts'] as Map)[fixture.credentialId] = {
      ...fixture.receipt(),
      'requestId': fixture.credentialId,
      'operation': 'profiles.update',
      'result': {
        'entityId': fixture.profileId,
        'entityRevision': '3',
        'storeRevision': '3',
        'deleted': false,
      },
    };
    final snapshot = HostTrustState.fromRecords(trusted.parse(document), {
      fixture.profileId: HostTrustRecord.fromJson({
        ...trusted.trustRow(),
        'revision': '3',
        'status': 'revoked',
      }),
    });
    final revoked = prepareHostTrustMutation(
      snapshot,
      'servers.trust.revoke',
      body(revision: '3'),
      stamp,
    );
    expect(revoked.trust[fixture.profileId]!.connectionRevision, '1');
    final confirmed = prepareHostTrustMutation(
      snapshot,
      'servers.trust.confirm',
      confirm(revision: '3'),
      stamp,
    );
    expect(confirmed.trust[fixture.profileId]!.connectionRevision, '2');
    expect(confirmed.trust[fixture.profileId]!.revision, '4');
    expect(confirmed.trust[fixture.profileId]!.createdAt, fixture.time);
  });

  test(
    'permanent receipt quota refuses both transitions without state changes',
    () {
      final document = fixture.populated();
      document['schemaVersion'] = 3;
      document['storeRevision'] = '10000';
      (document['profiles'] as Map)[fixture.profileId] = fixture.profile(
        revision: '10000',
      );
      document['receipts'] = {
        for (var n = 1; n <= 10000; n++)
          '12345678-1234-4234-8234-${n.toString().padLeft(12, '0')}': {
            ...fixture.receipt(),
            'requestId':
                '12345678-1234-4234-8234-${n.toString().padLeft(12, '0')}',
            'operation': n == 1 ? 'profiles.create' : 'profiles.update',
            'result': {
              'entityId': fixture.profileId,
              'entityRevision': '$n',
              'storeRevision': '$n',
              'deleted': false,
            },
          },
      };
      final snapshot = HostTrustState.fromRecords(trusted.parse(document), {
        fixture.profileId: HostTrustRecord.fromJson({
          ...trusted.trustRow(),
          'revision': '1',
        }),
      });
      for (final method in ['servers.trust.confirm', 'servers.trust.revoke']) {
        expect(
          () => prepareHostTrustMutation(
            snapshot,
            method,
            method == 'servers.trust.confirm'
                ? confirm(revision: '10000')
                : body(revision: '10000'),
            stamp,
          ),
          code('RESOURCE_LIMIT'),
        );
      }
      expect(snapshot.foundation.storeRevision, '10000');
      expect(snapshot.foundation.receipts.length, 10000);
      expect(snapshot.trust[fixture.profileId]!.revision, '1');
    },
  );
}
