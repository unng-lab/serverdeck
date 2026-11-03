import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/feature_harness.dart';

Future<String> connected(FeatureHarness h) async {
  final id = await h.create(),
      session = await h.connect(id),
      auth = session.authenticate();
  await featureTurns();
  final challenge = (await h.trust.getTrust(h.actors.ui, id)).value!.challenge!;
  expect(
    (await h.trust.acceptTrust(h.actors.ui, h.decision(id, challenge))).ok,
    isTrue,
  );
  await auth;
  await featureTurns();
  return id;
}

ReplacementDecision replacement(
  FeatureHarness h,
  String id,
  TrustChallenge c,
) => ReplacementDecision(
  profileId: id,
  attemptId: c.attemptId,
  nonce: c.nonce,
  expectedProfileRevision: c.profileRevision,
  expectedTrustRevision: c.trustRevision,
  expectedObservationRevision: c.observationRevision,
  fingerprint: c.fingerprint,
  oldFingerprint: c.oldFingerprint!,
  newFingerprint: c.fingerprint,
  mutationId: h.newId(),
  confirmed: true,
);
void main() {
  late FeatureHarness h;
  setUp(() => h = FeatureHarness());
  tearDown(() => h.dispose());
  test(
    'changed rekey persists warning before closing established session',
    () async {
      final id = await connected(h), session = h.sessions.single;
      await session.rekey(featureKey(2));
      await featureTurns();
      expect(session.closed, isTrue);
      final view = (await h.profiles.getProfile(h.actors.ui, id)).value!;
      expect(view.connection.state, ConnectionState.disconnected);
      expect(view.connection.failureCode, FailureCode.hostKeyChanged);
      expect(view.trust.changed, isTrue);
      expect(view.trust.observedFingerprint, featureKey(2).fingerprint);
      expect(view.trust.acceptedFingerprint, featureKey().fingerprint);
      expect(h.repository.state.endpoints.values.single.changed, isTrue);
    },
  );
  test('verified mismatch survives failed persistence in memory and next valid observation persists it', () async {
    final id = await connected(h);
    h.repository.failCommit = true;
    await expectLater(
      h.sessions.single.rekey(featureKey(2)),
      throwsA(anything),
    );
    await featureTurns();
    final failed = (await h.profiles.getProfile(h.actors.ui, id)).value!;
    expect(failed.connection.failureCode, FailureCode.storageUnavailable);
    expect(failed.trust.changed, isTrue);
    expect(h.repository.state.endpoints.values.single.changed, isFalse);
    final retry = await h.connect(id);
    await retry.authenticate();
    await featureTurns();
    expect(h.repository.state.endpoints.values.single.changed, isTrue);
    expect(
      h.repository.state.endpoints.values.single.observedFingerprint,
      featureKey(2).fingerprint,
    );
  });
  test('B then C invalidates the old replacement nonce', () async {
    final id = await connected(h);
    await h.connections.disconnect(
      h.actors.ui,
      id,
      sessionId: h.connections.connection(id).sessionId!,
    );
    final b = await h.connect(id);
    await b.authenticate(featureKey(2));
    await featureTurns();
    final old = (await h.trust.getTrust(h.actors.ui, id)).value!.challenge!;
    final c = await h.connect(id);
    await c.authenticate(featureKey(3));
    await featureTurns();
    final current = (await h.trust.getTrust(h.actors.ui, id)).value!.challenge!;
    expect(current.observationRevision, greaterThan(old.observationRevision));
    expect(
      (await h.trust.replaceTrust(
        h.actors.ui,
        replacement(h, id, old),
      )).error?.code,
      FailureCode.conflict,
    );
    expect(
      h.repository.state.endpoints.values.single.acceptedFingerprint,
      featureKey().fingerprint,
    );
    expect(
      (await h.trust.replaceTrust(h.actors.ui, replacement(h, id, current))).ok,
      isTrue,
    );
    expect(
      h.repository.state.endpoints.values.single.acceptedFingerprint,
      featureKey(3).fingerprint,
    );
  });
  test(
    'matching A retains the warning until explicit retain closes the attempt',
    () async {
      final id = await connected(h);
      await h.connections.disconnect(
        h.actors.ui,
        id,
        sessionId: h.connections.connection(id).sessionId!,
      );
      final b = await h.connect(id);
      await b.authenticate(featureKey(2));
      await featureTurns();
      final a = await h.connect(id);
      await a.authenticate();
      await featureTurns();
      final c = (await h.trust.getTrust(h.actors.ui, id)).value!.challenge!;
      expect(c.kind, TrustKind.retain);
      expect((await h.trust.getTrust(h.actors.ui, id)).value!.changed, isTrue);
      final result = await h.trust.retainTrust(
        h.actors.ui,
        RetentionDecision(
          profileId: id,
          attemptId: c.attemptId,
          nonce: c.nonce,
          expectedProfileRevision: c.profileRevision,
          expectedTrustRevision: c.trustRevision,
          expectedObservationRevision: c.observationRevision,
          fingerprint: c.fingerprint,
          acceptedFingerprint: c.fingerprint,
          mutationId: h.newId(),
          confirmed: true,
        ),
      );
      expect(result.error, isNull);
      expect(h.repository.state.endpoints.values.single.changed, isFalse);
      expect(
        h.repository.state.endpoints.values.single.acceptedFingerprint,
        featureKey().fingerprint,
      );
      expect(a.closed, isTrue);
    },
  );
}
