import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/profile_controller.dart';

import '../fixtures/feature_harness.dart';

void main() {
  test(
    'warning remains visible until an explicit current-key decision',
    () async {
      final h = FeatureHarness();
      final c = ProfileController(
        operations: h.operations,
        actor: h.actors.ui,
        newId: h.newId,
        poll: false,
      );
      try {
        final id = await h.create();
        await c.select(id);
        await c.connect(c.details!.profile);
        await featureTurns();
        var session = h.sessions.last;
        var auth = session.authenticate();
        await featureTurns();
        await c.refresh();
        await c.decide(
          id,
          c.details!.trust.challenge!,
          confirmed: true,
          mutationId: h.newId(),
        );
        await auth;
        await featureTurns();
        await c.refresh();
        await c.disconnect(id, c.details!.connection.sessionId!);
        await c.connect(c.details!.profile);
        await featureTurns();
        session = h.sessions.last;
        await session.authenticate(featureKey(2));
        await featureTurns();
        await c.refresh();
        expect(c.trusts[id]!.changed, isTrue);
        expect(c.details!.trust.acceptedFingerprint, featureKey().fingerprint);
        final challenge = c.details!.trust.challenge!;
        expect(challenge.fingerprint, featureKey(2).fingerprint);
        expect(
          await c.decide(
            id,
            challenge,
            confirmed: false,
            mutationId: h.newId(),
          ),
          isNotNull,
        );
        expect(c.details!.trust.changed, isTrue);
        expect(
          await c.decide(id, challenge, confirmed: true, mutationId: h.newId()),
          isNull,
        );
        expect(c.trusts[id]!.changed, isFalse);
        expect(c.details!.connection.state, isNot(ConnectionState.connected));
      } finally {
        c.dispose();
        await h.dispose();
      }
    },
  );
}
