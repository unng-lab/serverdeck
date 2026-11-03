import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';

const epoch = '12345678-1234-4234-8234-123456789abc';
const client = '23456789-2345-4345-8345-23456789abcd';
const profile = '3456789a-3456-4456-8456-3456789abcde';

EntityVersions versionSample({
  String profileId = profile,
  int profileRevision = 1,
  int connection = 1,
  int credential = 1,
  String endpoint = 'endpoint-a',
  int trust = 1,
  int observation = 1,
  int attempt = 1,
  bool quarantined = false,
}) => EntityVersions(
  profileId: profileId,
  profileRevision: profileRevision,
  connectionRevision: connection,
  credentialRevision: credential,
  endpointId: endpoint,
  trustRevision: trust,
  observationRevision: observation,
  attemptGeneration: attempt,
  quarantined: quarantined,
);

class FakeState implements OperationState {
  @override
  String ownerEpoch = epoch;
  @override
  bool running = true;
  int revision = 1;
  bool revoked = false, expired = false, authorizationAllowed = true;
  int canonicalGrantVersion = 1;
  int versionReads = 0, metaReads = 0;
  EntityVersions? entity = versionSample();
  Future<void> Function(AuthorizationPoint)? beforeAuthorization;
  final points = <AuthorizationPoint>[];
  @override
  int get dataRevision {
    metaReads++;
    return revision;
  }

  @override
  Future<void> authorize(CommandActor actor, AuthorizationPoint point) async {
    points.add(point);
    await beforeAuthorization?.call(point);
    isAuthorizedNow(actor);
  }

  @override
  bool isAuthorizedNow(CommandActor actor) {
    if (actor is McpActor) {
      if (revoked || actor.grantVersion != canonicalGrantVersion) {
        throw const OperationFailure(FailureCode.accessRevoked);
      }
      if (expired) throw const OperationFailure(FailureCode.grantExpired);
    }
    return authorizationAllowed;
  }

  @override
  EntityVersions? versions(String profileId) {
    versionReads++;
    return entity;
  }
}

const value = MutationValue(entityId: profile, revision: 1);

void main() {
  late ActorAuthority actors;
  late FakeState state;
  late DomainCommandGate gate;
  late McpActor mcp;
  setUp(() {
    actors = ActorAuthority(epoch);
    state = FakeState();
    gate = DomainCommandGate(actors: actors, state: state);
    mcp = actors.mcp(clientId: client, grantVersion: 1);
  });
  tearDown(() => gate.drain());

  test(
    'private preparation returns nullable values with both auth checks',
    () async {
      final intent = await gate.prepare<(String, int)>(
        actors.ui,
        (context) => context.read(() => (profile, 1)),
      );
      expect(intent, (profile, 1));
      expect(state.points, [
        AuthorizationPoint.admission,
        AuthorizationPoint.response,
      ]);
      expect(await gate.prepare<String?>(actors.ui, (_) => null), isNull);
    },
  );

  test(
    'private preparation and public commands share the same bounded FIFO',
    () async {
      final wait = Completer<void>();
      final entered = Completer<void>();
      final order = <String>[];
      final prepared = gate.prepare<String>(actors.ui, (_) async {
        entered.complete();
        await wait.future;
        order.add('prepare');
        return 'private';
      });
      await entered.future;
      final command = gate.submit(actors.ui, (_) {
        order.add('command');
        return value;
      });
      expect(gate.queuedCommands, 1);
      wait.complete();
      expect(await prepared, 'private');
      expect((await command).ok, isTrue);
      expect(order, ['prepare', 'command']);
    },
  );

  test('preparation cannot return private intent after revoke or retain effect context', () async {
    state.beforeAuthorization = (point) async {
      if (point == AuthorizationPoint.response) state.revoked = true;
    };
    late CommandContext retained;
    await expectLater(
      gate.prepare<String>(mcp, (context) {
        retained = context;
        return 'SYNTHETIC_PRIVATE_INTENT';
      }),
      throwsA(
        isA<OperationFailure>().having(
          (e) => e.code,
          'code',
          FailureCode.accessRevoked,
        ),
      ),
    );
    expect(
      () => retained.linearize(() => value),
      throwsA(
        isA<OperationFailure>().having(
          (e) => e.code,
          'code',
          FailureCode.conflict,
        ),
      ),
    );
  });

  test(
    'final command rechecks fences after outside-gate preparation work',
    () async {
      final fence = await gate.prepare<VersionFence>(
        actors.ui,
        (context) => context.read(
          () => VersionFence(
            profileId: profile,
            profileRevision: state.entity!.profileRevision,
          ),
        ),
      );
      state.entity = versionSample(profileRevision: 2);
      var committed = false;
      final result = await gate.submit(
        actors.ui,
        (context) => context.linearize(() {
          committed = true;
          return value;
        }, fence: fence),
      );
      expect(result.error!.code, FailureCode.conflict);
      expect(committed, isFalse);
    },
  );

  test(
    'failed private preparation is sanitized and does not poison the queue',
    () async {
      await expectLater(
        gate.prepare<String>(
          actors.ui,
          (_) => throw StateError('SYNTHETIC_SECRET'),
        ),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.storageUnavailable,
          ),
        ),
      );
      expect((await gate.submit(actors.ui, (_) => value)).ok, isTrue);
      state.authorizationAllowed = false;
      var calls = 0;
      await expectLater(
        gate.prepare<String>(actors.ui, (_) {
          calls++;
          return 'private';
        }),
        throwsA(isA<OperationFailure>()),
      );
      expect(calls, 0);
    },
  );

  test('same epoch from a foreign authority cannot read or mutate', () async {
    var calls = 0;
    final result = await gate.submit(ActorAuthority(epoch).ui, (context) {
      calls++;
      return context.linearize(() => value);
    });
    expect(result.error!.code, FailureCode.authRequired);
    expect(calls, 0);
    expect(state.points, isEmpty);
    expect(state.versionReads, 0);
    expect(state.metaReads, 0);
  });

  test('JSON fields cannot form actor authority', () {
    dynamic forged = {'source': 'ui', 'ownerEpoch': epoch};
    expect(() => gate.submit(forged, (_) => value), throwsA(isA<TypeError>()));
  });

  for (final denied in ['revoke', 'expiry', 'rotate']) {
    test('$denied denies before receipt or profile lookup', () async {
      state.revoked = denied == 'revoke';
      state.expired = denied == 'expiry';
      state.canonicalGrantVersion = denied == 'rotate' ? 2 : 1;
      var reads = 0;
      final result = await gate.submit(
        mcp,
        (ctx) => ctx.read(() {
          reads++;
          return value;
        }),
      );
      expect(result.ok, isFalse);
      expect(reads, 0);
      expect(state.versionReads, 0);
      expect(state.metaReads, 0);
    });
  }

  test('owner change during asynchronous admission prevents body', () async {
    state.beforeAuthorization = (point) async {
      state.ownerEpoch = 'new-owner';
    };
    var calls = 0;
    final result = await gate.submit(mcp, (_) {
      calls++;
      return value;
    });
    expect(result.error!.code, FailureCode.authRequired);
    expect(calls, 0);
  });

  test('queue is FIFO with 64 waiting slots and explicit overflow', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final order = <int>[];
    final first = gate.submit(actors.ui, (ctx) async {
      entered.complete();
      await release.future;
      return ctx.linearize(() {
        order.add(0);
        return value;
      });
    });
    await entered.future;
    final queued = [
      for (var i = 1; i <= 64; i++)
        gate.submit(
          actors.ui,
          (ctx) => ctx.linearize(() {
            order.add(i);
            return value;
          }),
        ),
    ];
    final overflow = await gate.submit(actors.ui, (_) {
      throw StateError('Overflow callback executed');
    });
    expect(overflow.error!.code, FailureCode.resourceExhausted);
    expect(gate.queuedCommands, 64);
    release.complete();
    expect((await first).ok, isTrue);
    expect((await Future.wait(queued)).every((r) => r.ok), isTrue);
    expect(order, List.generate(65, (i) => i));
    expect(gate.queuedCommands, 0);
  });

  test('authorization is checked at actual effect and no late effect survives revoke', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var effects = 0;
    final result = gate.submit(mcp, (ctx) async {
      entered.complete();
      await release.future;
      return ctx.linearize(() {
        effects++;
        return value;
      });
    });
    await entered.future;
    state.revoked = true;
    release.complete();
    expect((await result).error!.code, FailureCode.accessRevoked);
    expect(effects, 0);
  });

  test(
    'committed effect is not rolled back but response is denied after revoke',
    () async {
      var effects = 0;
      final result = await gate.submit(mcp, (ctx) {
        final committed = ctx.linearize(() {
          effects++;
          return value;
        });
        state.revoked = true;
        return committed;
      });
      expect(effects, 1);
      expect(result.error!.code, FailureCode.accessRevoked);
      expect(result.value, isNull);
      expect(result.meta, isNull);
    },
  );

  test(
    'even domain errors are withheld after response authorization is lost',
    () async {
      state.beforeAuthorization = (point) async {
        if (point == AuthorizationPoint.response) state.revoked = true;
      };
      final result = await gate.submit<MutationValue>(
        mcp,
        (_) => throw const OperationFailure(FailureCode.profileNotFound),
      );
      expect(result.error!.code, FailureCode.accessRevoked);
      expect(jsonEncode(result.toJson()), isNot(contains('PROFILE_NOT_FOUND')));
    },
  );

  test(
    'command lease expires before asynchronous response authorization',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      state.beforeAuthorization = (point) async {
        if (point == AuthorizationPoint.response) {
          entered.complete();
          await release.future;
        }
      };
      late CommandContext retained;
      var effects = 0;
      final response = gate.submit(mcp, (ctx) {
        retained = ctx;
        return value;
      });
      await entered.future;
      expect(
        () => retained.linearize(() {
          effects++;
          return value;
        }),
        throwsA(isA<OperationFailure>()),
      );
      release.complete();
      expect((await response).ok, isTrue);
      expect(effects, 0);
    },
  );

  test(
    'receipt replay is authorized but never requires stale entity fences',
    () async {
      state.entity = null;
      var cacheReads = 0;
      final result = await gate.submit(
        mcp,
        (ctx) => ctx.read(() {
          cacheReads++;
          return const MutationValue(
            entityId: profile,
            revision: 1,
            replayed: true,
          );
        }),
      );
      expect(result.value!.replayed, isTrue);
      expect(cacheReads, 1);
      expect(state.versionReads, 0);
      expect(state.points, [
        AuthorizationPoint.admission,
        AuthorizationPoint.response,
      ]);
    },
  );

  final changed = <String, EntityVersions>{
    'profile': versionSample(profileRevision: 2),
    'connection': versionSample(connection: 2),
    'credential': versionSample(credential: 2),
    'endpoint': versionSample(endpoint: 'endpoint-b'),
    'trust': versionSample(trust: 2),
    'observation': versionSample(observation: 2),
    'generation': versionSample(attempt: 2),
    'identity': versionSample(profileId: client),
  };
  for (final entry in changed.entries) {
    test('stale ${entry.key} fence prevents mutation', () async {
      state.entity = entry.value;
      var effects = 0;
      final result = await gate.submit(
        mcp,
        (ctx) => ctx.linearize(
          () {
            effects++;
            return value;
          },
          fence: VersionFence(
            profileId: profile,
            profileRevision: 1,
            connectionRevision: 1,
            credentialRevision: 1,
            endpointId: 'endpoint-a',
            trustRevision: 1,
            observationRevision: 1,
            attemptGeneration: 1,
          ),
        ),
      );
      expect(result.error!.code, FailureCode.conflict);
      expect(effects, 0);
    });
  }

  test(
    'connection fence survives rename while captured consent does not',
    () async {
      state.entity = versionSample(profileRevision: 2);
      final session = await gate.submit(
        mcp,
        (ctx) => ctx.linearize(
          () => value,
          fence: VersionFence(
            profileId: profile,
            connectionRevision: 1,
            attemptGeneration: 1,
          ),
        ),
      );
      final consent = await gate.submit(
        mcp,
        (ctx) => ctx.linearize(
          () => value,
          fence: VersionFence(profileId: profile, profileRevision: 1),
        ),
      );
      expect(session.ok, isTrue);
      expect(consent.error!.code, FailureCode.conflict);
    },
  );

  test(
    'quarantine blocks new effects but allows reads and exact cleanup retry',
    () async {
      state.entity = versionSample(quarantined: true);
      final blocked = await gate.submit(
        mcp,
        (ctx) =>
            ctx.linearize(() => value, fence: VersionFence(profileId: profile)),
      );
      expect(blocked.error!.code, FailureCode.cleanupRequired);
      final read = await gate.submit(
        mcp,
        (ctx) => ctx.read(
          () => const ConnectionView(
            state: ConnectionState.failed,
            failureCode: FailureCode.cleanupRequired,
          ),
        ),
      );
      expect(read.ok, isTrue);
      final cleanup = await gate.submit(
        mcp,
        (ctx) => ctx.linearize(
          () => value,
          fence: VersionFence(
            profileId: profile,
            attemptGeneration: 1,
            requiresUsableEndpoint: false,
          ),
        ),
      );
      expect(cleanup.ok, isTrue);
    },
  );

  test(
    'shutdown blocks new/queued effects and drain waits for active command',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var effects = 0;
      final active = gate.submit(actors.ui, (ctx) async {
        entered.complete();
        await release.future;
        return ctx.linearize(() {
          effects++;
          return value;
        });
      });
      await entered.future;
      final queued = gate.submit(actors.ui, (_) {
        effects++;
        return value;
      });
      gate.stopAdmission();
      final rejected = await gate.submit(actors.ui, (_) => value);
      expect(rejected.error!.code, FailureCode.shuttingDown);
      release.complete();
      expect((await active).error!.code, FailureCode.shuttingDown);
      expect((await queued).error!.code, FailureCode.shuttingDown);
      await gate.drain();
      expect(effects, 0);
    },
  );

  test(
    'unexpected exception is sanitized and does not poison next command',
    () async {
      final failed = await gate.submit<MutationValue>(
        actors.ui,
        (_) => throw StateError('SYNTHETIC_SECRET'),
      );
      expect(failed.error!.code, FailureCode.storageUnavailable);
      expect(jsonEncode(failed.toJson()), isNot(contains('SYNTHETIC_SECRET')));
      state.revision = 3;
      final next = await gate.submit(actors.ui, (_) => value);
      expect(next.ok, isTrue);
      expect(next.meta!.dataRevision, 3);
      expect(next.meta!.ownerEpoch, epoch);
    },
  );

  test(
    'invalid canonical data revision blocks before command effects',
    () async {
      state.revision = 0;
      var effects = 0;
      final result = await gate.submit(
        actors.ui,
        (ctx) => ctx.linearize(() {
          effects++;
          return value;
        }),
      );
      expect(result.error!.code, FailureCode.storageUnavailable);
      expect(effects, 0);
    },
  );

  test('missing profile fence returns not-found without effect', () async {
    state.entity = null;
    var effects = 0;
    final result = await gate.submit(
      actors.ui,
      (ctx) => ctx.linearize(() {
        effects++;
        return value;
      }, fence: VersionFence(profileId: profile, profileRevision: 1)),
    );
    expect(result.error!.code, FailureCode.profileNotFound);
    expect(effects, 0);
  });

  test('app-owned work survives MCP revocation without inheriting client authority', () async {
    state.revoked = true;
    var ownerEffects = 0;
    final clientResult = await gate.submit(mcp, (_) => value);
    final ownerResult = await gate.submit(
      actors.owner,
      (ctx) => ctx.linearize(() {
        ownerEffects++;
        return value;
      }),
    );
    expect(clientResult.error!.code, FailureCode.accessRevoked);
    expect(ownerResult.ok, isTrue);
    expect(ownerEffects, 1);
    expect(actors.owner, isNot(isA<Actor>()));
  });

  test(
    'actor contexts and fences reject noncanonical IDs and invalid versions',
    () {
      expect(() => ActorAuthority('ui'), throwsArgumentError);
      expect(
        () => actors.mcp(clientId: 'client', grantVersion: 1),
        throwsArgumentError,
      );
      expect(
        () => actors.mcp(clientId: client, grantVersion: 0),
        throwsArgumentError,
      );
      expect(
        () => VersionFence(profileId: 'profile'),
        throwsA(isA<OperationFailure>()),
      );
      expect(
        () => VersionFence(profileId: profile, profileRevision: 0),
        throwsA(isA<OperationFailure>()),
      );
      expect(
        () => VersionFence(profileId: profile, attemptGeneration: -1),
        throwsA(isA<OperationFailure>()),
      );
    },
  );

  test(
    'a false synchronous authorization result denies without relying on throw',
    () async {
      state.authorizationAllowed = false;
      var effects = 0;
      final result = await gate.submit(
        actors.ui,
        (ctx) => ctx.linearize(() {
          effects++;
          return value;
        }),
      );
      expect(result.error!.code, FailureCode.authRequired);
      expect(effects, 0);
    },
  );
}
