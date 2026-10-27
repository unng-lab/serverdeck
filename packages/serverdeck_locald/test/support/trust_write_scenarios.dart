import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/native_failure.dart';
import 'package:serverdeck_locald/remote/trust_probes.dart';
import 'package:serverdeck_locald/api/owner_api.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/models.dart';

import 'capacity_fixture.dart';
import 'trusted_auth_actor.dart' as a;
import 'trusted_schema_child.dart' as raw;

Future<void> exerciseTrustWrites({
  required String root,
  required String mode,
  required String profile,
  required String operation,
  required Map challenge,
  required TrustedOwnerApi api,
  required TrustedMutationCoordinator coordinator,
  required HostTrustProbeService service,
  required StateStore store,
  required a.Pair owner,
  required String Function() id,
  required void Function(Duration) advance,
  required void Function(bool) armClock,
}) async {
  void capacityPhase(String phase) {
    if (mode == 'probe-success-write-capacity') {
      writeCapacityFixturePhase(root, phase);
    }
  }

  capacityPhase('capacity-start');
  const method = 'servers.trust.confirm';
  final body = <String, Object?>{
    'profileId': profile,
    'expectedRevision': '1',
    'challengeId': challenge['challengeId'],
    'key': Map<String, Object?>.from(challenge['key'] as Map),
  };
  Future<Map<String, Object?>> call(
    String operation,
    Map<String, Object?> input, {
    String? requestId,
    a.Pair? actor,
  }) async {
    final pair = actor ?? owner;
    final request = await owner.registry.begin(
      pair.channel,
      pair.response!.sessionId,
      operation,
    );
    try {
      return await api.dispatch(
        request,
        operation,
        input,
        requestId: requestId ?? id(),
      );
    } finally {
      request.complete();
    }
  }

  final before = store.state.toJson();
  Future<Object?> observedOwnerFailure(
    Future<Object?> value,
    String marker,
  ) async {
    try {
      return await value;
    } on StateError catch (error) {
      if (error.message == 'STORAGE_BLOCKED') stdout.writeln(marker);
      rethrow;
    }
  }

  if (mode == 'probe-success-write-clock') {
    armClock(true);
    try {
      await a.fails(
        observedOwnerFailure(
          call(method, body),
          'OWNER_TIMEOUT_REWRITTEN_STORAGE_BLOCKED',
        ),
        'TIMEOUT',
      );
    } finally {
      armClock(false);
    }
    a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
  }
  if (mode == 'probe-success-write-retired-admission') {
    final request = await owner.registry.begin(
      owner.channel,
      owner.response!.sessionId,
      method,
    );
    final reservation = coordinator.reserveTrust(
      id(),
      method,
      body,
      requester: 'fixture-retired-admission',
    );
    try {
      request.complete();
      await a.fails(
        observedOwnerFailure(
          coordinator.activateTrust(reservation, service, request),
          'OWNER_UNAUTHORIZED_REWRITTEN_STORAGE_BLOCKED',
        ),
        'UNAUTHORIZED',
      );
      a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
    } finally {
      coordinator.detach('fixture-retired-admission');
    }
  }
  if (mode == 'probe-success-write-role') {
    final mcp = await a.Pair.start(root, 'mcp.exe', owner.registry);
    try {
      await mcp.exchange();
      a.check(await mcp.next() == 'AUTH:mcp');
      for (final name in ['servers.trust.confirm', 'servers.trust.revoke']) {
        await a.fails(
          owner.registry.begin(mcp.channel, mcp.response!.sessionId, name),
          'FORBIDDEN',
        );
      }
      final request = await owner.registry.begin(
        mcp.channel,
        mcp.response!.sessionId,
        'session.ping',
      );
      try {
        await a.fails(
          Future.sync(
            () => api.prepare(request, request.method, {
              'bad': true,
            }, requestId: 'bad'),
          ),
          'FORBIDDEN',
        );
      } finally {
        request.complete();
      }
    } finally {
      await mcp.close();
    }
    a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
    return;
  }
  if (mode == 'probe-success-write-quota') {
    final tokens = [
      for (var n = 0; n < 32; n++)
        coordinator.reserveTrust(
          id(),
          method,
          body,
          requester: 'fixture-quota',
        ),
    ];
    try {
      await a.fails(call(method, body), 'RESOURCE_LIMIT');
      a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
    } finally {
      coordinator.detach('fixture-quota');
      for (final token in tokens) {
        await a.fails(token.result, 'SERVICE_UNAVAILABLE');
      }
    }
  }
  if (mode == 'probe-success-write-capacity') {
    final db = Isar.getInstance('workspace')!;
    Future<String> capture() async {
      final trust = await db.storedHostTrusts.where().findAll();
      trust.sort((a, b) => a.id.compareTo(b.id));
      return '${await raw.capture(db)}\n${jsonEncode([
        for (final row in trust) [row.id, row.entityId, row.payload],
      ])}';
    }

    final rawBefore = await capture();
    final pinned = Completer<void>(), release = Completer<void>();
    final reader = db.txn(() async {
      a.check(await db.storedSettings.get(1) != null);
      pinned.complete();
      await release.future;
    });
    await pinned.future;
    capacityPhase('capacity-reader-ready');
    try {
      final original = (await db.storedSettings.get(1))!.payload;
      final parsed = jsonDecode(original) as Map;
      final alternate = jsonEncode({
        ...parsed,
        'reduceMotion': !(parsed['reduceMotion'] as bool),
      });
      final full = await prefillCapacityFixture(
        commitSync: () => db.writeTxnSync(() {
          db.storedSettings.putSync(
            StoredSettings()
              ..id = 1
              ..payload = alternate,
          );
          db.storedSettings.putSync(
            StoredSettings()
              ..id = 1
              ..payload = original,
          );
        }),
        isCapacityFailure: isNativeCapacityFailure,
        onBucket: (completed) => capacityPhase('capacity-prefill-$completed'),
      );
      a.check(full);
      capacityPhase('capacity-full');
      await a.fails(call(method, body), 'RESOURCE_LIMIT');
      a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
      a.check(await db.storedHostTrusts.count() == 0);
      a.check(await capture() == rawBefore);
      capacityPhase('capacity-confirm-refused');
    } finally {
      release.complete();
      await reader;
      capacityPhase('capacity-reader-released');
    }
  }
  if (mode == 'probe-success-write-cancel' ||
      mode == 'probe-success-write-ttl') {
    if (mode.endsWith('cancel')) {
      await call('servers.trust.probeCancel', {'operationId': operation});
    } else {
      advance(const Duration(seconds: 300));
    }
    await a.fails(call(method, body), 'TRUST_REQUIRED');
    a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
    return;
  }
  if (mode == 'probe-success-write-cas') {
    await a.fails(
      call(method, {...body, 'expectedRevision': '2'}),
      'REVISION_CONFLICT',
    );
    await a.fails(
      call(method, {...body, 'challengeId': id()}),
      'TRUST_REQUIRED',
    );
    a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
  }
  a.Pair? other;
  try {
    if (mode == 'probe-success-write-drain') {
      final db = Isar.getInstance('workspace')!;
      final reached = Completer<void>(), release = Completer<void>();
      final held = db.writeTxn(() async {
        reached.complete();
        await release.future;
      });
      await reached.future;
      final mutation = id();
      final work = call(method, body, requestId: mutation);
      work.ignore();
      try {
        final wait = Stopwatch()..start();
        while (coordinator.status(mutation).toJson()['state'] != 'running') {
          a.check(wait.elapsed < const Duration(seconds: 3));
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        var drained = false;
        final closing = service.close().then<void>((_) {
          drained = true;
        });
        owner.handshake!.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        a.check(!drained && service.retainedProbes == 1);
        release.complete();
        await held;
        await work;
        await closing;
        a.check(drained && service.retainedProbes == 0);
        a.check(store.state.receipts[mutation]!.result.entityRevision == '2');
      } finally {
        if (!release.isCompleted) release.complete();
        await held;
        await work;
      }
      return;
    }
    if (mode == 'probe-success-write-foreign' ||
        mode == 'probe-success-write-duplicate') {
      other = await a.Pair.start(root, 'serverdeck.exe', owner.registry);
      await other.exchange();
      a.check(await other.next() == 'AUTH:owner');
      if (mode.endsWith('foreign')) {
        await a.fails(call(method, body, actor: other), 'TRUST_REQUIRED');
      } else {
        final mutation = id();
        final request = owner.registry.reserve(
          owner.channel,
          owner.response!.sessionId,
          method,
        );
        final prepared = api.prepare(
          request,
          method,
          body,
          requestId: mutation,
        );
        try {
          a.check(coordinator.status(mutation).toJson()['state'] == 'queued');
          await a.fails(
            call(method, body, requestId: mutation, actor: other),
            'TRUST_REQUIRED',
          );
          a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
          await owner.registry.completeAdmission(request);
          final result = await prepared.execute();
          a.check(result['entityRevision'] == '2');
          a.check(
            jsonEncode(
                  await call(method, body, requestId: mutation, actor: other),
                ) ==
                jsonEncode(result),
          );
        } finally {
          prepared.close();
          request.complete();
        }
        return;
      }
    }
    final mutation = id();
    late Map<String, Object?> result;
    if (mode == 'probe-success-write-blocked' ||
        mode == 'probe-success-write-retired') {
      final gate = await owner.peer!.publicationGate(a.generation);
      final held = await gate.acquire();
      final request = await owner.registry.begin(
        owner.channel,
        owner.response!.sessionId,
        method,
      );
      final prepared = api.prepare(request, method, body, requestId: mutation);
      final work = prepared.execute();
      work.ignore();
      try {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
        a.check(coordinator.status(mutation).toJson()['state'] == 'queued');
        if (mode.endsWith('retired')) request.complete();
        await held.close();
        if (mode.endsWith('retired')) {
          await a.fails(
            work.timeout(const Duration(seconds: 5)),
            'UNAUTHORIZED',
          );
          a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
          prepared.close();
        } else {
          result = await work;
        }
      } finally {
        prepared.close();
        request.complete();
        await held.close();
        await gate.close();
      }
      if (mode.endsWith('retired'))
        result = await call(
          method,
          body,
          requestId: mutation,
        ).timeout(const Duration(seconds: 5));
    } else if (mode == 'probe-success-write-reservation') {
      final request = owner.registry.reserve(
        owner.channel,
        owner.response!.sessionId,
        method,
      );
      final mutable = <String, Object?>{
        ...body,
        'key': Map<String, Object?>.from(body['key'] as Map),
      };
      final prepared = api.prepare(
        request,
        method,
        mutable,
        requestId: mutation,
      );
      try {
        a.check(jsonEncode(store.state.toJson()) == jsonEncode(before));
        (mutable['key'] as Map)['fingerprint'] = 'invalid-after-capture';
        mutable['expectedRevision'] = '99';
        await owner.registry.completeAdmission(request);
        final work = prepared.execute();
        a.check(identical(work, prepared.execute()));
        result = await work;
      } finally {
        prepared.close();
        request.complete();
      }
    } else {
      capacityPhase('capacity-recovery-confirm');
      result = await call(method, body, requestId: mutation);
    }
    a.check(result['entityRevision'] == '2');
    final trusted = store.trustedOperational.foundation.trust[profile]!;
    a.check(trusted.revision == '2' && trusted.connectionRevision == '1');
    a.check(jsonEncode(trusted.key.toJson()) == jsonEncode(body['key']));
    a.check(store.state.profiles[profile]!.credentialRevision == '1');
    capacityPhase('capacity-recovered');
    a.check(
      (await call('servers.trust.probeCancel', {
            'operationId': operation,
          }))['cancelled'] ==
          false,
    );
    a.check(
      jsonEncode(await call(method, body, requestId: mutation)) ==
          jsonEncode(result),
    );
    capacityPhase('capacity-replay-verified');
    final revoked = await call('servers.trust.revoke', {
      'profileId': profile,
      'expectedRevision': '2',
    });
    a.check(revoked['entityRevision'] == '3');
    final revokedAgain = await call('servers.trust.revoke', {
      'profileId': profile,
      'expectedRevision': '3',
    });
    a.check(revokedAgain['entityRevision'] == '4');
    final row = store.trustedOperational.foundation.trust[profile]!;
    a.check(row.createdAt == trusted.createdAt && row.revision == '4');
    a.check(jsonEncode(row.key.toJson()) == jsonEncode(body['key']));
    await a.fails(call(method, body), 'REVISION_CONFLICT');
    await a.fails(
      call(method, {...body, 'expectedRevision': '4'}),
      'TRUST_REQUIRED',
    );
    capacityPhase('capacity-revoke-verified');
    if (mode == 'probe-success-write-replay') {
      advance(const Duration(seconds: 301));
      await coordinator.submit(id(), ApiMethod.profilesDelete, {
        'profileId': profile,
        'expectedRevision': '4',
      }, requester: 'fixture-delete');
      a.check(!store.state.profiles.containsKey(profile));
      final revision = store.state.storeRevision;
      a.check(
        jsonEncode(await call(method, body, requestId: mutation)) ==
            jsonEncode(result),
      );
      a.check(
        store.state.storeRevision == revision &&
            !store.state.profiles.containsKey(profile),
      );
      await a.fails(
        call(method, {...body, 'challengeId': id()}, requestId: mutation),
        'IDEMPOTENCY_CONFLICT',
      );
    }
  } finally {
    await other?.close();
  }
  capacityPhase('capacity-complete');
}
