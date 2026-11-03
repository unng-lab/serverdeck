import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/feature_harness.dart';

void main() {
  late FeatureHarness h;
  setUp(() => h = FeatureHarness());
  tearDown(() => h.dispose());
  test('grant is disabled by default and export contains no plaintext configuration secret', () async {
    expect(h.grants.enabled, isFalse);
    final g = await h.grants.issue(h.actors.ui, ' Client ', confirmed: true);
    expect(g.name, 'Client');
    expect(g.version, 1);
    expect(g.expiresAt, h.clock.utc + 90 * 24 * 60 * 60 * 1000);
    final config = await h.grants.configuration(h.actors.ui, g.clientId);
    expect(config.command, r'C:\fixture\ServerDeck.exe');
    expect(config.args, ['--mcp-stdio', '--client', g.clientId]);
    expect(config.toJson().toString(), isNot(contains('secret')));
    expect(g.exportPending, isFalse);
    final actor = h.actors.mcp(clientId: g.clientId, grantVersion: 1);
    expect(
      () => h.grants.isAuthorizedNow(actor),
      throwsA(featureFailure(FailureCode.accessRevoked)),
    );
  });
  test('proof and actual peer identity are both required', () async {
    final g = await h.grants.issue(h.actors.ui, 'Client', confirmed: true);
    await h.grants.setEnabled(h.actors.ui, true);
    Future<Object> auth(
      Uint8List proof, {
      String user = 'synthetic-user',
      String logon = 'synthetic-logon',
    }) => h.grants.authenticate(
      g.clientId,
      1,
      proof,
      peerUserSid: user,
      peerLogonSid: logon,
    );
    final secret = Uint8List.fromList(List.filled(32, 7));
    expect((await auth(secret)).toString(), isNot(contains('synthetic')));
    await expectLater(
      auth(Uint8List(32)),
      throwsA(featureFailure(FailureCode.authRequired)),
    );
    await expectLater(
      auth(secret, user: 'foreign'),
      throwsA(featureFailure(FailureCode.authRequired)),
    );
    await expectLater(
      auth(secret, logon: 'other-logon'),
      throwsA(featureFailure(FailureCode.authRequired)),
    );
  });
  test(
    'rotation revokes old actor, advances version and restarts ninety days',
    () async {
      final g = await h.grants.issue(h.actors.ui, 'Client', confirmed: true);
      await h.grants.setEnabled(h.actors.ui, true);
      final old = h.actors.mcp(clientId: g.clientId, grantVersion: 1);
      expect(h.grants.isAuthorizedNow(old), isTrue);
      h.clock.advance(const Duration(days: 1));
      final rotated = await h.grants.rotate(
        h.actors.ui,
        g.clientId,
        confirmed: true,
      );
      expect(rotated.version, 2);
      expect(rotated.expiresAt, h.clock.utc + 90 * 24 * 60 * 60 * 1000);
      expect(
        () => h.grants.isAuthorizedNow(old),
        throwsA(featureFailure(FailureCode.accessRevoked)),
      );
      final current = h.actors.mcp(clientId: g.clientId, grantVersion: 2);
      expect(h.grants.isAuthorizedNow(current), isTrue);
      await h.grants.revoke(h.actors.ui, g.clientId, confirmed: true);
      expect(
        () => h.grants.isAuthorizedNow(current),
        throwsA(featureFailure(FailureCode.accessRevoked)),
      );
      final version = h.repository.state.grants[g.clientId]!.grantVersion;
      await h.grants.revoke(h.actors.ui, g.clientId, confirmed: true);
      expect(h.repository.state.grants[g.clientId]!.grantVersion, version);
      expect(h.transport.files.containsKey(g.clientId), isFalse);
    },
  );
  test(
    'expiry is denied at the exact boundary without a delivered timer',
    () async {
      final g = await h.grants.issue(h.actors.ui, 'Client', confirmed: true);
      await h.grants.setEnabled(h.actors.ui, true);
      final actor = h.actors.mcp(clientId: g.clientId, grantVersion: 1);
      h.clock.utc = g.expiresAt;
      await expectLater(
        h.grants.authorize(actor, AuthorizationPoint.admission),
        throwsA(featureFailure(FailureCode.grantExpired)),
      );
    },
  );
  test(
    'failed export stays pending; retry uses the same committed version',
    () async {
      h.transport.failWrite = true;
      await expectLater(
        h.grants.issue(h.actors.ui, 'Client', confirmed: true),
        throwsA(featureFailure(FailureCode.storageUnavailable)),
      );
      final record = h.repository.state.grants.values.single;
      expect(record.exportPending, isTrue);
      expect(record.grantVersion, 1);
      await expectLater(
        h.grants.configuration(h.actors.ui, record.clientId),
        throwsA(featureFailure(FailureCode.cleanupRequired)),
      );
      h.transport.failWrite = false;
      await h.grants.retry(h.actors.ui, record.clientId);
      final after = h.repository.state.grants.values.single;
      expect(after.grantVersion, 1);
      expect(after.protectedSecret, record.protectedSecret);
      expect(after.exportPending, isFalse);
    },
  );
  test('cleanup timeout retains exact pending close and never rotates again on retry', () async {
    final g = await h.grants.issue(h.actors.ui, 'Client', confirmed: true);
    h.transport.holdClose = Completer<void>();
    final rotate = h.grants.rotate(h.actors.ui, g.clientId, confirmed: true);
    final failed = expectLater(
      rotate,
      throwsA(featureFailure(FailureCode.cleanupRequired)),
    );
    await featureTurns();
    h.clock.advance(const Duration(seconds: 5));
    await failed;
    final record = h.repository.state.grants[g.clientId]!;
    expect(record.grantVersion, 2);
    expect(record.exportPending, isTrue);
    final count = h.transport.closes;
    final retry = h.grants.retry(h.actors.ui, g.clientId);
    await featureTurns();
    expect(h.transport.closes, count);
    h.transport.holdClose!.complete();
    await retry;
    expect(h.repository.state.grants[g.clientId]!.grantVersion, 2);
    expect(h.repository.state.grants[g.clientId]!.exportPending, isFalse);
  });
  test(
    'rollback invalidates both grants; rotating A cannot revive B',
    () async {
      final a = await h.grants.issue(h.actors.ui, 'A', confirmed: true),
          b = await h.grants.issue(h.actors.ui, 'B', confirmed: true);
      await h.grants.setEnabled(h.actors.ui, true);
      final oldEpoch = h.repository.state.security.authorizationEpoch;
      h.clock.utc -= 1000;
      await h.grants.list(h.actors.ui);
      await featureTurns();
      expect(h.repository.state.security.authorizationEpoch, oldEpoch + 1);
      await h.grants.rotate(h.actors.ui, a.clientId, confirmed: true);
      expect(
        h.grants.isAuthorizedNow(
          h.actors.mcp(clientId: a.clientId, grantVersion: 2),
        ),
        isTrue,
      );
      expect(
        () => h.grants.isAuthorizedNow(
          h.actors.mcp(clientId: b.clientId, grantVersion: 1),
        ),
        throwsA(featureFailure(FailureCode.accessRevoked)),
      );
      h.clock.utc -= 1;
      await h.grants.list(h.actors.ui);
      expect(h.repository.state.security.authorizationEpoch, oldEpoch + 2);
      expect(
        () => h.grants.isAuthorizedNow(
          h.actors.mcp(clientId: a.clientId, grantVersion: 2),
        ),
        throwsA(featureFailure(FailureCode.accessRevoked)),
      );
    },
  );
  test('clock persistence failure blocks authorization until a durable guard succeeds', () async {
    final g = await h.grants.issue(h.actors.ui, 'A', confirmed: true);
    await h.grants.setEnabled(h.actors.ui, true);
    final actor = h.actors.mcp(clientId: g.clientId, grantVersion: 1);
    h.repository.failCommit = true;
    await expectLater(
      h.grants.authorize(actor, AuthorizationPoint.admission),
      throwsA(featureFailure(FailureCode.storageUnavailable)),
    );
    expect(
      () => h.grants.isAuthorizedNow(actor),
      throwsA(featureFailure(FailureCode.storageUnavailable)),
    );
    await h.grants.authorize(actor, AuthorizationPoint.admission);
    expect(h.grants.isAuthorizedNow(actor), isTrue);
  });
}
