import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/bootstrap_controller.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck_protocol/models.dart';

import 'local_api_client_test.dart' show Clock, settle, generation, profileId;

class Client extends LocalApiClient {
  Client() : super(connect: () => throw StateError('UNUSED'));
  final readinessStates = <String>['ready'];
  int connections = 0, polls = 0, closes = 0, failures = 0;
  final events = StreamController<ClientConnectionState>.broadcast();
  final readErrors = StreamController<ErrorCode>.broadcast(sync: true);
  @override
  Stream<ErrorCode> get snapshotErrors => readErrors.stream;
  @override
  Stream<ClientConnectionState> get states => events.stream;
  @override
  Future<void> connect() async {
    connections++;
    if (failures-- > 0)
      throw const LocalApiException(ErrorCode.serviceUnavailable);
  }

  @override
  Future<ApiReply> read(
    ApiMethod method, [
    Map<String, Object?> params = const {},
  ]) async {
    expect(method, ApiMethod.readinessGet);
    final state = readinessStates.length > 1
        ? readinessStates.removeAt(0)
        : readinessStates.first;
    return ApiReply(generation, {
      'state': state,
      'reason': state == 'storage-blocked' ? 'STORAGE_BLOCKED' : null,
      'workspaceId': state == 'ready' ? profileId : null,
    });
  }

  @override
  void startPolling() => polls++;
  @override
  void stopPolling() {}
  @override
  Future<void> close() async {
    closes++;
    await events.close();
    await readErrors.close();
    await super.close();
  }
}

void main() {
  test(
    'readiness epoch changes before listeners and survives nested recovery',
    () async {
      final client = Client();
      final controller = BootstrapController(
        client: client,
        prepare: () async {},
        ensureService: () async {},
      );
      expect(controller.readinessEpoch, 0);
      var recovering = false;
      Future<void>? recovery;
      controller.addListener(() {
        if (controller.state == ReadinessState.storageBlocked && !recovering) {
          expect(controller.readinessEpoch, 3);
          recovering = true;
          recovery = controller.retry();
        }
      });
      final observed = <int>[];
      controller.addListener(() => observed.add(controller.readinessEpoch));
      await controller.retry();
      expect(controller.readinessEpoch, 2);
      client.readErrors.add(ErrorCode.storageBlocked);
      expect(controller.state, ReadinessState.starting);
      expect(controller.readinessEpoch, 4);
      await recovery;
      expect(controller.state, ReadinessState.ready);
      expect(controller.readinessEpoch, 5);
      expect(observed, orderedEquals([...observed]..sort()));
      expect(observed, containsAll([1, 2, 4, 5]));
      await controller.close();
    },
  );
  for (final entry in {
    ErrorCode.storageBlocked: ReadinessState.storageBlocked,
    ErrorCode.incompatible: ReadinessState.incompatible,
    ErrorCode.notReady: ReadinessState.unavailable,
  }.entries) {
    test(
      'background ${entry.key} stops ready; manual retry can restore it',
      () async {
        final client = Client();
        final controller = BootstrapController(
          client: client,
          prepare: () async {},
          ensureService: () async {},
        );
        await controller.retry();
        client.readErrors.add(entry.key);
        expect(controller.state, entry.value);
        expect(controller.reason, entry.key);
        expect(controller.workspaceId, isNull);
        await controller.retry();
        expect(controller.state, ReadinessState.ready);
        client.readErrors.add(ErrorCode.timeout);
        expect(controller.state, ReadinessState.ready);
        await controller.close();
      },
    );
  }
  test('ready disconnect performs a fresh verified bootstrap', () async {
    final client = Client();
    var preparations = 0;
    final controller = BootstrapController(
      client: client,
      prepare: () async {
        preparations++;
      },
      ensureService: () async {},
    );
    await controller.retry();
    client.events.add(ClientConnectionState.disconnected);
    await settle();
    expect(preparations, 2);
    expect(client.polls, 2);
    expect(controller.state, ReadinessState.ready);
    await controller.close();
  });
  test(
    'transient loss invokes recovery without repeating preparation',
    () async {
      final client = Client()..failures = 1;
      var preparations = 0, recoveries = 0;
      final controller = BootstrapController(
        client: client,
        prepare: () async {
          preparations++;
        },
        ensureService: () async {},
        recoverService: () async {
          recoveries++;
        },
        delay: (_) async {},
      );
      await controller.retry();
      expect(preparations, 1);
      expect(recoveries, 1);
      expect(controller.state, ReadinessState.ready);
      await controller.close();
    },
  );
  for (final state in [ReadinessState.starting, ReadinessState.ready]) {
    test('dispose during $state notification prevents later effects', () async {
      final client = Client();
      var prepared = 0;
      final controller = BootstrapController(
        client: client,
        prepare: () async {
          prepared++;
        },
        ensureService: () async {},
      );
      controller.addListener(() {
        if (controller.state == state) controller.dispose();
      });
      await controller.retry();
      expect(prepared, state == ReadinessState.starting ? 0 : 1);
      expect(client.polls, 0);
      await controller.close();
      expect(client.closes, 1);
    });
  }
  test(
    'verified preparation precedes launch; recovering polls until ready',
    () async {
      final clock = Clock(),
          client = Client()
            ..readinessStates.insertAll(0, ['starting', 'recovering']);
      final events = <String>[];
      final waits = <Duration>[];
      final controller = BootstrapController(
        client: client,
        prepare: () async {
          events.add('verify');
        },
        ensureService: () async {
          events.add('ensure');
        },
        elapsed: () => clock.now,
        schedule: clock.schedule,
        delay: (duration) async {
          waits.add(duration);
          clock.now += duration;
        },
      );
      await controller.retry();
      expect(events, ['verify', 'ensure']);
      expect(waits, List.filled(2, const Duration(milliseconds: 250)));
      expect(controller.state, ReadinessState.ready);
      expect(controller.workspaceId, profileId);
      expect(client.polls, 1);
      await controller.close();
    },
  );
  test(
    'connect retries use bounded backoff and never relaunch within attempt',
    () async {
      final clock = Clock(), client = Client()..failures = 5;
      final waits = <int>[];
      var launches = 0;
      final controller = BootstrapController(
        client: client,
        prepare: () async {},
        ensureService: () async {
          launches++;
        },
        elapsed: () => clock.now,
        schedule: clock.schedule,
        delay: (duration) async {
          waits.add(duration.inMilliseconds);
          clock.now += duration;
        },
      );
      await controller.retry();
      expect(waits, [100, 200, 400, 800, 1000]);
      expect(launches, 1);
      expect(controller.state, ReadinessState.ready);
      await controller.close();
    },
  );
  test(
    'deadline is visible during pending native work and retry joins it',
    () async {
      final clock = Clock(), client = Client(), pending = Completer<void>();
      var launches = 0;
      final controller = BootstrapController(
        client: client,
        prepare: () => pending.future,
        ensureService: () async {
          launches++;
        },
        elapsed: () => clock.now,
        schedule: clock.schedule,
      );
      final first = controller.retry();
      expect(identical(first, controller.retry()), true);
      clock.advance(const Duration(seconds: 30));
      expect(controller.state, ReadinessState.unavailable);
      expect(controller.reason, ErrorCode.timeout);
      expect(controller.retryInProgress, true);
      expect(identical(first, controller.retry()), true);
      pending.complete();
      await first;
      expect(launches, 0);
      expect(client.polls, 0);
      await controller.close();
    },
  );
  test(
    'blocked readiness preserves safe reason and never reads private data',
    () async {
      final client = Client()..readinessStates[0] = 'storage-blocked';
      final controller = BootstrapController(
        client: client,
        prepare: () async {},
        ensureService: () async {},
      );
      await controller.retry();
      expect(controller.state, ReadinessState.storageBlocked);
      expect(controller.reason, ErrorCode.storageBlocked);
      expect(controller.workspaceId, isNull);
      expect(client.polls, 0);
      await controller.close();
    },
  );
  test(
    'dispose suppresses pending preparation and reentrant retry joins attempt',
    () async {
      final client = Client(), pending = Completer<void>();
      var launches = 0;
      final controller = BootstrapController(
        client: client,
        prepare: () => pending.future,
        ensureService: () async {
          launches++;
        },
      );
      Future<void>? joined;
      controller.addListener(() {
        joined = controller.retry();
      });
      final first = controller.retry();
      expect(identical(joined, first), true);
      controller.dispose();
      pending.complete();
      await first;
      await settle();
      expect(launches, 0);
      await controller.close();
      expect(client.closes, 1);
    },
  );
}
