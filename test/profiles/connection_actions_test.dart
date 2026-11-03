import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/profile_controller.dart';

import '../fixtures/feature_harness.dart';

void main() {
  late FeatureHarness h;
  late ProfileController c;
  setUp(() {
    h = FeatureHarness();
    c = ProfileController(
      operations: h.operations,
      actor: h.actors.ui,
      newId: h.newId,
      poll: false,
    );
  });
  tearDown(() async {
    c.dispose();
    await h.dispose();
  });
  test('connect and trust use one attempt; rename keeps a session; disconnect is explicit', () async {
    final id = await h.create();
    await c.select(id);
    expect(await c.connect(c.details!.profile), isNull);
    await featureTurns();
    final session = h.sessions.single, auth = session.authenticate();
    await featureTurns();
    await c.refresh();
    expect(c.details!.connection.state, ConnectionState.needTrust);
    final challenge = c.details!.trust.challenge!;
    expect(
      await c.decide(id, challenge, confirmed: true, mutationId: h.newId()),
      isNull,
    );
    await auth;
    await featureTurns();
    await c.refresh();
    expect(c.details!.connection.state, ConnectionState.connected);
    final sessionId = c.details!.connection.sessionId!;
    expect(
      await c.update(
        c.details!.profile,
        const ProfilePatch(displayName: 'Renamed'),
        h.newId(),
      ),
      isNull,
    );
    expect(c.details!.connection.sessionId, sessionId);
    expect(h.sessions.length, 1);
    expect(session.closeCalls, 0);
    expect(await c.disconnect(id, sessionId), isNull);
    expect(c.details!.connection.state, ConnectionState.disconnected);
  });
  test(
    'cancelled attempt cannot be restored by late host acceptance',
    () async {
      final id = await h.create();
      await c.select(id);
      await c.connect(c.details!.profile);
      await featureTurns();
      final session = h.sessions.single, auth = session.authenticate();
      await featureTurns();
      await c.refresh();
      final challenge = c.details!.trust.challenge!;
      expect(await c.cancel(id, challenge.attemptId), isNull);
      await auth;
      expect(
        await c.decide(id, challenge, confirmed: true, mutationId: h.newId()),
        isNotNull,
      );
      expect(c.details!.connection.state, ConnectionState.cancelled);
      expect(
        h.repository.state.endpoints.values.single.acceptedKeyBytes,
        isNull,
      );
    },
  );
}
