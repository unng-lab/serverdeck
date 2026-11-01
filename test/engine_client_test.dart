import 'package:serverdeck_engine/hosting/capability_snapshot.dart';
import 'package:serverdeck_engine/platform/ports.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck_engine/hosting/in_process_gateway.dart';
import 'package:serverdeck_engine/hosting/worker_controller.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';

import '../lib/bootstrap/engine_client.dart';
import '../lib/bootstrap/bootstrap_controller.dart';

Map<String, Object?> caps(String phase) =>
    (phase == 'ready'
            ? EngineCapabilities(
                platform: EnginePlatformKind.windows,
                storageReady: true,
                vaultStatus: VaultAccess.available,
                directSsh: false,
                localMcpBridge: false,
                trayAvailable: false,
                backgroundPolicy: EngineBackgroundPolicy.desktopWhileRunning,
                reasonCodes: const [],
              )
            : EngineCapabilities.unavailable(EnginePlatformKind.windows))
        .toJson();

const generation = '12345678-1234-4234-9234-123456789abc';
const workspace = '12345678-1234-4234-9234-123456789abd';
const request = '12345678-1234-4234-9234-123456789abe';
Map<String, Object?> readiness() => TrustedReadiness(
  state: ReadinessState.ready,
  generation: generation,
  workspaceId: workspace,
  features: const OperationalFeatures(profiles: true),
).toJson();
Map<String, Object?> settings(String rev) => {
  'storeRevision': rev,
  'settings': {
    'revision': rev,
    'theme': 'system',
    'reduceMotion': false,
    'selectedProfileId': null,
  },
};
Map<String, Object?> mutation() => {
  'entityId': null,
  'entityRevision': '2',
  'storeRevision': '2',
  'deleted': false,
};
Matcher failure(ErrorCode code) =>
    throwsA(isA<EngineApiException>().having((e) => e.code, 'safe code', code));
Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class Gateway implements EngineGateway {
  @override
  String get generation {
    onGeneration?.call();
    return '12345678-1234-4234-9234-123456789abc';
  }

  void Function()? onGeneration;
  @override
  bool isClosed = false;
  final retiring = Completer<void>();
  final calls = <({String method, String id, Map<String, Object?> params})>[];
  String revision = '1';
  Future<Map<String, Object?>> Function(String, Map<String, Object?>)? effect;
  Completer<void>? closePause;
  @override
  Future<void> get retired => retiring.future;
  @override
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    calls.add((method: method, id: requestId, params: Map.of(params)));
    if (isClosed) return Future.error(EngineCallFailure('SERVICE_UNAVAILABLE'));
    return effect?.call(method, params) ??
        Future.value(switch (method) {
          'profiles.list' => {
            'storeRevision': revision,
            'profiles': <Object?>[],
          },
          'settings.get' => settings(revision),
          'settings.update' => mutation(),
          'mutations.get' => {'state': 'not-found', 'result': null},
          'readiness.get' => readiness(),
          'session.ping' => {'leaseSeconds': 60},
          _ => throw EngineCallFailure('VALIDATION'),
        });
  }

  @override
  Future<void> close() {
    isClosed = true;
    if (!retiring.isCompleted) retiring.complete();
    return closePause?.future ?? Future.value();
  }
}

final class Setup {
  final gateway = Gateway();
  int attachments = 0, detaches = 0;
  Completer<void>? opening;
  final timers = <({Duration delay, void Function() fire})>[];
  late final client = EngineApiClient(
    attach: () async {
      attachments++;
      await opening?.future;
      return gateway;
    },
    detach: () async {
      detaches++;
      await gateway.close();
    },
    schedule: schedule,
  );
  CancelDeadline schedule(Duration delay, void Function() action) {
    timers.add((delay: delay, fire: action));
    return () {};
  }
}

void main() {
  test(
    'bootstrap retains busy explanation and never connects or retries',
    () async {
      var starts = 0, connections = 0;
      final client = EngineApiClient(
        attach: () async {
          connections++;
          throw StateError('NO_OWNER_FOR_CONTENDER');
        },
        detach: () async {},
      );
      final bootstrap = BootstrapController(
        client: client,
        start: () async {
          starts++;
          return WorkerStatus.fromJson({
            'phase': 'busy',
            'capabilities': caps('busy'),
            'reason': 'STORAGE_BLOCKED',
            'readiness': TrustedReadiness(
              state: ReadinessState.storageBlocked,
              generation: generation,
              features: const OperationalFeatures(),
            ).toJson(),
          });
        },
      );
      await bootstrap.retry();
      expect(bootstrap.workspaceBusy, isTrue);
      expect(bootstrap.state, ReadinessState.storageBlocked);
      expect(bootstrap.workspaceId, isNull);
      await bootstrap.retry();
      expect(starts, 1);
      expect(connections, 0);
      await bootstrap.close();
    },
  );

  test(
    'read/mutate cannot create attachment without explicit connect',
    () async {
      final s = Setup();
      await expectLater(
        s.client.read(ApiMethod.settingsGet),
        failure(ErrorCode.serviceUnavailable),
      );
      final intent = MutationIntent(ApiMethod.settingsUpdate, {
        'theme': 'dark',
      });
      await expectLater(
        s.client.mutate(intent),
        failure(ErrorCode.serviceUnavailable),
      );
      expect(s.attachments, 0);
      intent.dispose();
      await s.client.close();
    },
  );
  test('retired snapshot never reattaches; explicit retry alone opens one next owner', () async {
    final first = Gateway(), second = Gateway(), draining = Completer<void>();
    first.closePause = draining;
    var attachments = 0, generationReads = 0;
    Gateway? active;
    final client = EngineApiClient(
      attach: () async {
        attachments++;
        return active = attachments == 1 ? first : second;
      },
      detach: () async {
        await active?.close();
      },
      schedule: (_, __) => () {},
    );
    await client.connect();
    // Simulate a retirement delivered exactly as the first typed read hands
    // its generation back; no native/isolate scheduling is needed.
    first.onGeneration = () {
      if (++generationReads == 3) first.close().ignore();
    };
    await client.refreshSnapshot();
    await settle();
    expect(first.isClosed, isTrue);
    expect(first.calls.where((c) => c.method == 'settings.get'), isEmpty);
    expect(attachments, 1);
    draining.complete();
    await settle();
    expect(attachments, 1);
    await client.connect();
    expect(attachments, 2);
    await client.refreshSnapshot();
    expect(second.calls.where((c) => c.method == 'settings.get').length, 1);
    await client.close();
  });

  test(
    'proved terminal session.close result survives logical retirement',
    () async {
      final gateway = Gateway();
      gateway.effect = (method, params) async {
        await gateway.close();
        return {'closed': true};
      };
      final client = EngineClient(gateway);
      expect(await client.call('session.close', {}), {'closed': true});
      await client.done;
    },
  );

  test(
    'one window attachment, frozen typed snapshots, matching revisions only',
    () async {
      final s = Setup(), snapshots = <ClientSnapshot>[];
      s.client.snapshots.listen(snapshots.add);
      await Future.wait([s.client.connect(), s.client.connect()]);
      expect(s.attachments, 1);
      await s.client.refreshSnapshot();
      await settle();
      expect(snapshots.length, 1);
      expect(snapshots.single.storeRevision, '1');
      expect(
        () => snapshots.single.settings.result['storeRevision'] = '9',
        throwsUnsupportedError,
      );
      expect(
        () => ((snapshots.single.settings.result['settings']) as Map)['theme'] =
            'dark',
        throwsUnsupportedError,
      );
      await s.client.refreshSnapshot();
      await settle();
      expect(snapshots.length, 1);
      s.gateway.revision = '2';
      await s.client.refreshSnapshot();
      await settle();
      expect(snapshots.length, 2);
      s.gateway.revision = '1';
      await s.client.refreshSnapshot();
      await settle();
      expect(snapshots.length, 2);
      await s.client.close();
    },
  );
  test('mismatched profile/settings revisions never publish an incoherent snapshot', () async {
    final s = Setup(), snapshots = <ClientSnapshot>[];
    s.client.snapshots.listen(snapshots.add);
    s.gateway.effect = (method, params) async => method == 'profiles.list'
        ? {'storeRevision': '1', 'profiles': <Object?>[]}
        : settings('2');
    await s.client.connect();
    await s.client.refreshSnapshot();
    await settle();
    expect(snapshots, isEmpty);
    await s.client.close();
  });
  test('input captured before pending attachment and explicit mutation identity retained', () async {
    final s = Setup();
    s.opening = Completer();
    final params = <String, Object?>{'requestId': request};
    final connecting = s.client.connect();
    final read = s.client.read(ApiMethod.mutationsGet, params);
    params['requestId'] = workspace;
    s.opening!.complete();
    await connecting;
    await read;
    expect(s.gateway.calls.single.params['requestId'], request);
    final input = <String, Object?>{'expectedRevision': '1', 'theme': 'dark'};
    final intent = MutationIntent(
      ApiMethod.settingsUpdate,
      input,
      requestId: request,
    );
    input['theme'] = 'light';
    await s.client.mutate(intent);
    expect(s.gateway.calls.last.id, request);
    expect(s.gateway.calls.last.params['theme'], 'dark');
    intent.dispose();
    await expectLater(s.client.mutate(intent), failure(ErrorCode.validation));
    await s.client.close();
  });
  test('lost mutation reply is unknown: no retry; explicit receipt query uses original UUID', () async {
    final s = Setup();
    s.gateway.effect = (method, params) async {
      if (method == 'settings.update') throw EngineCallFailure('TIMEOUT');
      return {'state': 'not-found', 'result': null};
    };
    await s.client.connect();
    final intent = MutationIntent(ApiMethod.settingsUpdate, {
      'theme': 'dark',
    }, requestId: request);
    await expectLater(s.client.mutate(intent), failure(ErrorCode.timeout));
    expect(
      s.gateway.calls.where((c) => c.method == 'settings.update').length,
      1,
    );
    await s.client.mutationStatus(intent);
    expect(s.gateway.calls.last.method, 'mutations.get');
    expect(s.gateway.calls.last.params['requestId'], request);
    intent.dispose();
    await s.client.close();
  });
  test('logical retirement notifies immediately while physical detach remains pending', () async {
    final s = Setup(), states = <ClientConnectionState>[];
    s.client.states.listen(states.add);
    await s.client.connect();
    final control = s.client.controlClient!;
    s.gateway.closePause = Completer();
    var drained = false;
    final close = s.client.close().then((_) => drained = true);
    await control.done;
    expect(control.isClosed, isTrue);
    expect(drained, isFalse);
    await expectLater(
      s.client.read(ApiMethod.settingsGet),
      failure(ErrorCode.serviceUnavailable),
    );
    s.gateway.closePause!.complete();
    await close;
    expect(states.last, ClientConnectionState.closed);
  });
  test(
    'late response after retirement is not presented as a current read',
    () async {
      final s = Setup(), result = Completer<Map<String, Object?>>();
      s.gateway.effect = (_, __) => result.future;
      await s.client.connect();
      final read = s.client.read(ApiMethod.settingsGet);
      read.ignore();
      await settle();
      await s.gateway.close();
      await settle();
      result.complete(settings('1'));
      await expectLater(read, failure(ErrorCode.serviceUnavailable));
      await s.client.close();
    },
  );
  test(
    'poll uses2s and heartbeat uses20s without OS endpoint or mutation replay',
    () async {
      final s = Setup();
      await s.client.connect();
      s.client.startPolling();
      await settle();
      expect(
        s.timers.map((t) => t.delay),
        contains(const Duration(seconds: 2)),
      );
      // Existing session heartbeat interval remains the protocol constant.
      expect(
        s.timers.map((t) => t.delay),
        contains(const Duration(seconds: 20)),
      );
      s.client.stopPolling();
      await s.client.close();
    },
  );
  test('detached poll epoch discards late snapshot and its errors', () async {
    final s = Setup(),
        result = Completer<Map<String, Object?>>(),
        snapshots = <ClientSnapshot>[],
        errors = <ErrorCode>[];
    s.client.snapshots.listen(snapshots.add);
    s.client.snapshotErrors.listen(errors.add);
    s.gateway.effect = (_, __) => result.future;
    await s.client.connect();
    final refresh = s.client.refreshSnapshot();
    refresh.ignore();
    await settle();
    s.client.stopPolling();
    result.completeError(EngineCallFailure('TIMEOUT'));
    await expectLater(refresh, failure(ErrorCode.timeout));
    expect(errors, isEmpty);
    expect(snapshots, isEmpty);
    await s.client.connect();
    await s.client.close();
  });
  test(
    'Bootstrap uses worker Ready and format3 readiness before polling',
    () async {
      final s = Setup();
      var starts = 0;
      final bootstrap = BootstrapController(
        client: s.client,
        start: () async {
          starts++;
          return WorkerStatus.fromJson({
            'phase': 'ready',
            'capabilities': caps('ready'),
            'reason': null,
            'readiness': readiness(),
          });
        },
        schedule: s.schedule,
      );
      final running = bootstrap.retry();
      expect(identical(running, bootstrap.retry()), isTrue);
      await running;
      expect(bootstrap.state, ReadinessState.ready);
      expect(bootstrap.workspaceId, workspace);
      expect(starts, 1);
      expect(s.gateway.calls.first.method, 'readiness.get');
      await bootstrap.close();
    },
  );
  test('failed worker readiness does not attach or run domain calls', () async {
    final s = Setup();
    final bootstrap = BootstrapController(
      client: s.client,
      start: () async => WorkerStatus.fromJson({
        'phase': 'failed',
        'capabilities': caps('failed'),
        'reason': 'STORAGE_BLOCKED',
        'readiness': null,
      }),
      schedule: s.schedule,
    );
    await bootstrap.retry();
    expect(bootstrap.state, ReadinessState.storageBlocked);
    expect(s.attachments, 0);
    expect(s.gateway.calls, isEmpty);
    await bootstrap.close();
  });
  test(
    'loss retires readiness without automatic retry or replacement',
    () async {
      final s = Setup();
      var starts = 0;
      final bootstrap = BootstrapController(
        client: s.client,
        start: () async {
          starts++;
          return WorkerStatus.fromJson({
            'phase': 'ready',
            'capabilities': caps('ready'),
            'reason': null,
            'readiness': readiness(),
          });
        },
        schedule: s.schedule,
      );
      await bootstrap.retry();
      await s.gateway.close();
      await settle();
      expect(bootstrap.state, ReadinessState.unavailable);
      expect(starts, 1);
      expect(s.attachments, 1);
      await bootstrap.close();
    },
  );
  test(
    'late startup cannot revive UI Ready beyond original30s budget',
    () async {
      final s = Setup(), start = Completer<WorkerStatus>();
      var now = 0;
      final bootstrap = BootstrapController(
        client: s.client,
        start: () => start.future,
        nowMicros: () => now,
        schedule: s.schedule,
      );
      final running = bootstrap.retry();
      now = 31000000;
      start.complete(
        WorkerStatus.fromJson({
          'phase': 'ready',
          'capabilities': caps('ready'),
          'reason': null,
          'readiness': readiness(),
        }),
      );
      await running;
      expect(bootstrap.state, ReadinessState.unavailable);
      expect(bootstrap.reason, ErrorCode.timeout);
      expect(s.attachments, 0);
      await bootstrap.close();
    },
  );
}
