import 'package:serverdeck_engine/automation/direct_dispatch_binding.dart';
import 'package:serverdeck_protocol/automation/direct_ssh_dispatch.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../support/schema3_fixture.dart' as fixture;
import '../storage/actual_state_store_test.dart' as actual;

void main() {
  final start = actual.now();
  String time(int milliseconds) =>
      start.add(Duration(milliseconds: milliseconds)).toIso8601String();
  AutomationMutationReceiptRecord receipt(
    String operation,
    int revision,
    int at,
  ) => AutomationMutationReceiptRecord.fromJson({
    'workspaceId': fixture.workspace,
    'requestId': actual.id(revision),
    'originGrantId': null,
    'objectGrantId': null,
    'canonicalDigest': 'a' * 64,
    'operation': operation,
    'result': {'grantId': fixture.grant, 'revision': revision},
    'createdAt': time(at),
  });
  final history = [
    receipt('grant.create', 1, 0),
    receipt('grant.replace', 2, 10000),
    receipt('grant.revoke', 3, 20000),
  ];
  final grant = ClientGrantRecord.fromJson({
    ...fixture.grantDocument(),
    'revision': 3,
    'scopes': ['read', 'plan', 'apply'],
    'createdAt': time(0),
    'issuedAt': time(10000),
    'expiresAt': time(3610000),
    'revokedAt': time(20000),
  });
  DirectSshDispatch dispatch(int revision, int at, {String? expiry}) =>
      DirectSshDispatch.fromJson({
        'format': 1,
        'stepId': 'e1',
        'stepDigest': 'a' * 64,
        'token': actual.id(50),
        'bootIdHash': 'b' * 64,
        'issuedUptimeMs': 0,
        'expiresUptimeMs': 5000,
        'authorityBindingDigest': 'c' * 64,
        'targetBindingDigest': 'd' * 64,
        'authorizedAt': time(at),
        'grantRevision': revision,
        'grantExpiresAt':
            expiry ?? (revision == 1 ? time(3600000) : time(3610000)),
        'state': 'authorized',
      });
  void validate(DirectSshDispatch value, {ClientGrantRecord? current}) =>
      validateDirectGrantDispatch(
        dispatch: value,
        grant: current ?? grant,
        serverId: fixture.profile,
        history: history,
      );

  test(
    'exact issuance bounds include equality but reject neighboring instants',
    () {
      for (final at in [0, 9999, 10000]) {
        validate(dispatch(1, at));
      }
      for (final at in [10000, 10001, 20000]) {
        validate(dispatch(2, at));
      }
      for (final value in [
        dispatch(1, -1),
        dispatch(1, 10001),
        dispatch(2, 9999),
        dispatch(2, 20001),
        dispatch(3, 20000),
        dispatch(4, 20000),
      ]) {
        expect(() => validate(value), fixture.blocked());
      }
      // Historical issuance expiry cannot be substituted with today's value.
      validate(dispatch(1, 5000));
      expect(
        () => validate(dispatch(2, 15000, expiry: time(3600000))),
        fixture.blocked(),
      );
    },
  );

  test('latest issuance policy remains verifiable after revoke increments revision', () {
    final withoutApply = ClientGrantRecord.fromJson({
      ...grant.toJson(),
      'scopes': ['read'],
    });
    expect(
      () => validate(dispatch(2, 15000), current: withoutApply),
      fixture.blocked(),
    );
    validate(dispatch(1, 5000), current: withoutApply);
  });
}
