import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/canonical_state.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/profile_harness.dart';

final class GrantPort implements CanonicalGrantAuthorization {
  bool allowed = true;
  final points = <AuthorizationPoint>[];
  Future<void> Function()? hook;
  @override
  Future<void> authorize(McpActor actor, AuthorizationPoint point) async {
    points.add(point);
    await hook?.call();
  }

  @override
  bool isAuthorizedNow(McpActor actor) => allowed;
}

void main() {
  late ProfileHarness h;
  late GrantPort grants;
  late CanonicalOperationState state;
  var running = true;
  setUp(() {
    h = ProfileHarness();
    grants = GrantPort();
    running = true;
    state = CanonicalOperationState(
      actors: h.actors,
      repository: h.repository,
      isRunning: () => running,
      grants: grants,
      connections: h.connections,
    );
  });
  tearDown(() => h.dispose());
  test('reads current profile/credential/trust and live generation without snapshots', () async {
    final id = (await h.create()).value!.entityId;
    final initial = state.versions(id)!;
    expect(initial.profileRevision, 1);
    expect(initial.credentialRevision, 1);
    h.connections.generations[id] = 9;
    h.connections.quarantine.add(initial.endpointId);
    h.repository.state.endpoints[initial.endpointId]!.observationRevision = 4;
    final current = state.versions(id)!;
    expect(current.attemptGeneration, 9);
    expect(current.quarantined, isTrue);
    expect(current.observationRevision, 4);
    expect(state.versions(fixtureId(90)), isNull);
  });
  test(
    'current transaction supplies fresh metadata and versions to effect checks',
    () async {
      final id = (await h.create()).value!.entityId;
      await h.repository.write((r) {
        r.putSettings(r.settings..dataRevision = 8);
        r.putProfile(r.profile(id)!..profileRevision = 2);
        expect(state.dataRevision, 8);
        expect(state.versions(id)!.profileRevision, 2);
      });
      expect(state.dataRevision, 8);
    },
  );
  test('missing/inconsistent canonical records fail closed rather than a permissive fence', () async {
    final id = (await h.create()).value!.entityId;
    final p = h.repository.state.profiles[id]!;
    final credential = h.repository.state.credentials.remove(p.credentialId)!;
    expect(
      () => state.versions(id),
      throwsA(
        isA<OperationFailure>().having(
          (e) => e.code,
          'code',
          FailureCode.storageUnavailable,
        ),
      ),
    );
    h.repository.state.credentials[p.credentialId] = credential;
    h.repository.state.endpoints[p.endpointId]!.port = 99;
    expect(() => state.versions(id), throwsA(isA<OperationFailure>()));
    h.repository.state.endpoints[p.endpointId]!.port = p.port;
    h.connections.generations[id] = -1;
    expect(() => state.versions(id), throwsA(isA<OperationFailure>()));
  });
  test(
    'UI and established owner checks have no initiating grant dependency',
    () async {
      grants.allowed = false;
      expect(state.isAuthorizedNow(h.actors.ui), isTrue);
      expect(state.isAuthorizedNow(h.actors.owner), isTrue);
      await state.authorize(h.actors.ui, AuthorizationPoint.admission);
      await state.authorize(h.actors.owner, AuthorizationPoint.response);
      expect(grants.points, isEmpty);
    },
  );
  test(
    'foreign issuer and stopped runtime deny before grant port use',
    () async {
      expect(
        () => state.isAuthorizedNow(ActorAuthority(h.actors.ownerEpoch).ui),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.authRequired,
          ),
        ),
      );
      running = false;
      await expectLater(
        state.authorize(h.mcp, AuthorizationPoint.admission),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.shuttingDown,
          ),
        ),
      );
      expect(grants.points, isEmpty);
    },
  );
  test(
    'MCP requires current synchronous permission after async authorization',
    () async {
      final gate = DomainCommandGate(actors: h.actors, state: state);
      final result = await gate.submit(
        h.mcp,
        (_) => MutationValue(entityId: fixtureId(9), revision: 1),
      );
      expect(result.ok, isTrue);
      expect(grants.points, [
        AuthorizationPoint.admission,
        AuthorizationPoint.response,
      ]);
      grants.allowed = false;
      await expectLater(
        state.authorize(h.mcp, AuthorizationPoint.admission),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.authRequired,
          ),
        ),
      );
      expect(
        (await gate.submit(
          h.mcp,
          (_) => MutationValue(entityId: fixtureId(9), revision: 1),
        )).error!.code,
        FailureCode.authRequired,
      );
      await gate.drain();
    },
  );
  test(
    'runtime stop during asynchronous grant check cannot admit an effect',
    () async {
      grants.hook = () async {
        running = false;
      };
      await expectLater(
        state.authorize(h.mcp, AuthorizationPoint.admission),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.shuttingDown,
          ),
        ),
      );
    },
  );
}
