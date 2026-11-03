import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/feature_harness.dart';

ReplacementDecision replaceDecision(
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
    'first acceptance is durable before the same handshake authenticates',
    () async {
      final id = await h.create(), session = await h.connect(id);
      final auth = session.authenticate();
      await featureTurns();
      expect(session.auth.isCompleted, isFalse);
      final details = (await h.profiles.getProfile(h.actors.ui, id)).value!;
      expect(details.connection.state, ConnectionState.needTrust);
      expect(details.trust.acceptedFingerprint, isNull);
      final c = details.trust.challenge!, decision = h.decision(id, c);
      final result = await h.trust.acceptTrust(h.actors.ui, decision);
      expect(result.error, isNull);
      await auth;
      await featureTurns();
      expect(h.connections.connection(id).state, ConnectionState.connected);
      final endpoint = h.repository.state.endpoints.values.single;
      expect(endpoint.acceptedFingerprint, featureKey().fingerprint);
      expect(endpoint.acceptedKeyBytes, featureKey().blob);
      expect(result.value!.entityId, id);
      expect(result.value!.revision, endpoint.trustRevision);
      final replay = await h.trust.acceptTrust(h.actors.ui, decision);
      expect(replay.value!.replayed, isTrue);
      expect(session.closeCalls, 0);
    },
  );
  test('expired consent does not accept a late key', () async {
    final id = await h.create(), session = await h.connect(id);
    final auth = session.authenticate();
    await featureTurns();
    final c = (await h.trust.getTrust(h.actors.ui, id)).value!.challenge!;
    h.clock.advance(const Duration(minutes: 5));
    await featureTurns();
    final result = await h.trust.acceptTrust(h.actors.ui, h.decision(id, c));
    expect(result.ok, isFalse);
    expect(h.repository.state.endpoints.values.single.acceptedKeyBytes, isNull);
    await auth;
    expect(
      h.connections.connection(id).state,
      isNot(ConnectionState.connected),
    );
  });
  test(
    'rename invalidates full-profile consent without changing saved trust',
    () async {
      final id = await h.create(), session = await h.connect(id);
      final auth = session.authenticate();
      await featureTurns();
      final c = (await h.trust.getTrust(h.actors.ui, id)).value!.challenge!;
      expect(
        (await h.profiles.updateProfile(
          h.actors.ui,
          id,
          const ProfilePatch(displayName: 'Renamed'),
          expectedRevision: 1,
          mutationId: h.newId(),
        )).ok,
        isTrue,
      );
      final result = await h.trust.acceptTrust(h.actors.ui, h.decision(id, c));
      expect(result.error?.code, FailureCode.conflict);
      expect(
        h.repository.state.endpoints.values.single.acceptedKeyBytes,
        isNull,
      );
      await h.connections.cancelConnection(
        h.actors.ui,
        id,
        attemptId: c.attemptId,
      );
      await auth;
    },
  );
  test('mismatch warning persists across failed attempt and shares endpoint profiles', () async {
    final a = await h.create(), b = await h.create();
    final first = await h.connect(a);
    final initial = first.authenticate();
    await featureTurns();
    final c = (await h.trust.getTrust(h.actors.ui, a)).value!.challenge!;
    expect(
      (await h.trust.acceptTrust(h.actors.ui, h.decision(a, c))).ok,
      isTrue,
    );
    await initial;
    await featureTurns();
    await h.connections.disconnect(
      h.actors.ui,
      a,
      sessionId: h.connections.connection(a).sessionId!,
    );
    final second = await h.connect(b);
    await second.authenticate(featureKey(2));
    await featureTurns();
    final warning = (await h.trust.getTrust(h.actors.ui, a)).value!;
    expect(warning.changed, isTrue);
    expect(warning.observedFingerprint, featureKey(2).fingerprint);
    expect(warning.acceptedFingerprint, featureKey().fingerprint);
    expect(h.connections.connection(b).state, isNot(ConnectionState.connected));
    final snapshot = h.repository.state.clone();
    expect(snapshot.endpoints.values.single.changed, isTrue);
  });
  test('replacement closes all endpoint resources and never reconnects automatically', () async {
    final id = await h.create(), first = await h.connect(id);
    final auth = first.authenticate();
    await featureTurns();
    var c = (await h.trust.getTrust(h.actors.ui, id)).value!.challenge!;
    await h.trust.acceptTrust(h.actors.ui, h.decision(id, c));
    await auth;
    await featureTurns();
    await h.connections.disconnect(
      h.actors.ui,
      id,
      sessionId: h.connections.connection(id).sessionId!,
    );
    final changed = await h.connect(id);
    await changed.authenticate(featureKey(2));
    await featureTurns();
    c = (await h.trust.getTrust(h.actors.ui, id)).value!.challenge!;
    final before = h.sessions.length,
        result = await h.trust.replaceTrust(
          h.actors.ui,
          replaceDecision(h, id, c),
        );
    expect(result.error, isNull);
    expect(h.sessions.length, before);
    expect(h.repository.state.endpoints.values.single.changed, isFalse);
    expect(
      h.repository.state.endpoints.values.single.acceptedFingerprint,
      featureKey(2).fingerprint,
    );
    expect(
      h.connections.connection(id).state,
      isNot(ConnectionState.connected),
    );
  });
  test('failed acceptance transaction resumes no authentication and can be retried', () async {
    final id = await h.create(), session = await h.connect(id);
    final auth = session.authenticate();
    await featureTurns();
    final c = (await h.trust.getTrust(h.actors.ui, id)).value!.challenge!,
        decision = h.decision(id, c);
    h.repository.failCommit = true;
    final failed = await h.trust.acceptTrust(h.actors.ui, decision);
    expect(failed.ok, isFalse);
    expect(h.repository.state.endpoints.values.single.acceptedKeyBytes, isNull);
    expect(session.auth.isCompleted, isFalse);
    expect((await h.trust.acceptTrust(h.actors.ui, decision)).ok, isTrue);
    await auth;
  });
}
