import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/feature_harness.dart';

void main() {
  test('snapshot restart preserves clock revocation and only explicit rotation restores one client', () async {
    final h = FeatureHarness();
    FeatureHarness? restored;
    try {
      final a = await h.grants.issue(h.actors.ui, 'A', confirmed: true),
          b = await h.grants.issue(h.actors.ui, 'B', confirmed: true);
      final snapshot = h.repository.state.clone();
      restored = FeatureHarness(epoch: 9001)..repository.state = snapshot;
      restored.clock.utc = snapshot.security.minimumClockUtc - 1;
      await restored.grants.initialize();
      await restored.grants.setEnabled(restored.actors.ui, true);
      expect(
        restored.repository.state.security.authorizationEpoch,
        snapshot.security.authorizationEpoch + 1,
      );
      final old = restored.actors.mcp(clientId: b.clientId, grantVersion: 1);
      await expectLater(
        restored.grants.authorize(old, AuthorizationPoint.admission),
        throwsA(featureFailure(FailureCode.accessRevoked)),
      );
      await restored.grants.rotate(
        restored.actors.ui,
        a.clientId,
        confirmed: true,
      );
      expect(
        restored.grants.isAuthorizedNow(
          restored.actors.mcp(clientId: a.clientId, grantVersion: 2),
        ),
        isTrue,
      );
      expect(
        () => restored!.grants.isAuthorizedNow(old),
        throwsA(featureFailure(FailureCode.accessRevoked)),
      );
    } finally {
      await restored?.dispose();
      await h.dispose();
    }
  });
  test('revocation at a common gate effect boundary aborts without a side effect', () async {
    final h = FeatureHarness();
    try {
      final g = await h.grants.issue(h.actors.ui, 'A', confirmed: true);
      await h.grants.setEnabled(h.actors.ui, true);
      final actor = h.actors.mcp(clientId: g.clientId, grantVersion: 1);
      var effects = 0;
      final result = await h.gate.submit(actor, (ctx) {
        // Synthetic canonical record transition stands for a completed durable
        // revocation while the private command was preparing outside its effect.
        h.repository.state.grants[g.clientId]!.revokedAt = h.clock.utc;
        return ctx.linearize(() {
          effects++;
          return const ConnectionView(state: ConnectionState.disconnected);
        });
      });
      expect(result.error?.code, FailureCode.accessRevoked);
      expect(effects, 0);
    } finally {
      await h.dispose();
    }
  });
}
