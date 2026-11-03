import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/feature_harness.dart';

void main() {
  late FeatureHarness h;
  setUp(() => h = FeatureHarness());
  tearDown(() => h.dispose());
  test(
    'MCP replay remains authorized and UI sees the same canonical profile',
    () async {
      final grant = await h.grants.issue(
        h.actors.ui,
        'Client',
        confirmed: true,
      );
      await h.grants.setEnabled(h.actors.ui, true);
      final actor = h.actors.mcp(clientId: grant.clientId, grantVersion: 1),
          auth = PasswordInput('synthetic-only'),
          mutation = h.newId();
      final draft = ProfileDraft(
        displayName: 'MCP',
        host: 'host.invalid',
        username: 'root',
        authentication: auth,
      );
      ProfileDraft replayDraft() => ProfileDraft(
        displayName: draft.displayName,
        host: draft.host,
        username: draft.username,
        authentication: PasswordInput('synthetic-only'),
      );
      try {
        final created = await h.operations.createProfile(
          actor,
          draft,
          mutationId: mutation,
        );
        expect(created.error, isNull);
        final id = created.value!.entityId;
        expect(
          (await h.operations.getProfile(
            h.actors.ui,
            id,
          )).value!.profile.displayName,
          'MCP',
        );
        final replay = await h.operations.createProfile(
          actor,
          replayDraft(),
          mutationId: mutation,
        );
        expect(replay.value!.replayed, isTrue);
        expect(h.repository.state.profiles.length, 1);
        await h.grants.revoke(h.actors.ui, grant.clientId, confirmed: true);
        expect(
          (await h.operations.createProfile(
            actor,
            replayDraft(),
            mutationId: mutation,
          )).error?.code,
          FailureCode.accessRevoked,
        );
        expect(h.repository.state.profiles.length, 1);
      } finally {
        auth.dispose();
      }
    },
  );
  test('cancelled request actor cannot pass actual effect admission', () async {
    final grant = await h.grants.issue(h.actors.ui, 'Client', confirmed: true);
    await h.grants.setEnabled(h.actors.ui, true);
    var cancelled = false, effects = 0;
    final actor = h.actors
        .mcp(clientId: grant.clientId, grantVersion: 1)
        .cancellable(() => cancelled);
    final result = await h.gate.submit(actor, (ctx) {
      cancelled = true;
      return ctx.linearize(() {
        effects++;
        return const ConnectionView(state: ConnectionState.disconnected);
      });
    });
    expect(result.ok, isFalse);
    expect(effects, 0);
  });
  test(
    'revoking an initiating client keeps its established owner session alive',
    () async {
      final grant = await h.grants.issue(
        h.actors.ui,
        'Client',
        confirmed: true,
      );
      await h.grants.setEnabled(h.actors.ui, true);
      final actor = h.actors.mcp(clientId: grant.clientId, grantVersion: 1),
          id = await h.create();
      final session = await h.connect(id, actor: actor),
          auth = session.authenticate();
      await featureTurns();
      final challenge = (await h.trust.getTrust(
        h.actors.ui,
        id,
      )).value!.challenge!;
      await h.trust.acceptTrust(h.actors.ui, h.decision(id, challenge));
      await auth;
      await featureTurns();
      expect(h.connections.connection(id).state, ConnectionState.connected);
      await h.grants.revoke(h.actors.ui, grant.clientId, confirmed: true);
      expect(session.closed, isFalse);
      expect(h.connections.connection(id).state, ConnectionState.connected);
      await h.connections.disconnect(
        h.actors.ui,
        id,
        sessionId: h.connections.connection(id).sessionId!,
      );
      expect(session.closed, isTrue);
    },
  );
}
