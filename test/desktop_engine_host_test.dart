import 'package:serverdeck_engine/hosting/capability_snapshot.dart';

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck_engine/hosting/worker_connection.dart';
import 'package:serverdeck_engine/hosting/worker_controller.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';

import '../lib/bootstrap/desktop_engine_host.dart';
import 'desktop_lifecycle_test.dart' show status, settle;

Map<String, Object?> frame(WorkerStatus value) => {
  'phase': value.phase,
  'reason': value.reason,
  'readiness': value.readiness?.toJson(),
  'capabilities': value.capabilities.toJson(),
};

// RAM control transport only. Any attempted window/native attachment fails.
final class Connection implements WorkerConnection {
  Connection(this.initial);
  final WorkerStatus initial;
  final stream = StreamController<Object?>(sync: true);
  int starts = 0;
  @override
  Stream<Object?> get messages => stream.stream;
  @override
  Future<void> start(int expiresAt) async {
    starts++;
    stream.add({'kind': 'started', 'status': frame(initial)});
  }

  @override
  void send(Map<String, Object?> value) {
    if (value['kind'] == 'power') return;
    if (value['kind'] != 'shutdown') throw StateError('UNEXPECTED_CONTROL');
    stream.add({
      'kind': 'reply',
      'sequence': value['sequence'],
      'operation': 'shutdown',
      'result': 'closed',
    });
  }

  @override
  void acknowledgeClosed(int sequence) {}
  @override
  WorkerWindowLink openWindow(Capability binding) =>
      throw StateError('NO_ATTACHMENT_IN_UNIT');
}

void main() {
  test(
    'fresh desktop client observes restore rather than cached initial phase',
    () async {
      final connection = Connection(status('resuming'));
      final engine = EngineWorkerController(
        platformKind: EnginePlatformKind.windows,
        connection: connection,
      );
      engine.setSuspended(false);
      expect((await engine.start()).phase, 'resuming');
      connection.stream.add({
        'kind': 'power',
        'epoch': 1,
        'status': frame(status()),
      });
      await settle();
      final host = DesktopEngineHost(engine: engine);
      expect((await host.start()).phase, 'ready');
      engine.setSuspended(true);
      expect((await host.start()).phase, 'suspending');
      expect(connection.starts, 1);
      await host.close();
      await engine.shutdown();
      await connection.stream.close();
    },
  );
  test('desktop startup continuation masks a newer power intent', () async {
    final connection = Connection(status());
    final engine = EngineWorkerController(
      platformKind: EnginePlatformKind.windows,
      connection: connection,
    );
    final host = DesktopEngineHost(engine: engine);
    final starting = host.start();
    engine.setSuspended(true);
    expect((await starting).phase, 'suspending');
    expect(connection.starts, 1);
    await host.close();
    await engine.shutdown();
    await connection.stream.close();
  });
  test(
    'desktop busy explanation survives automatic contender cleanup',
    () async {
      final connection = Connection(
        WorkerStatus.fromJson({
          'phase': 'busy',
          'capabilities': EngineCapabilities.unavailable(
            EnginePlatformKind.windows,
          ).toJson(),
          'reason': 'STORAGE_BLOCKED',
          'readiness': TrustedReadiness(
            state: ReadinessState.storageBlocked,
            generation: '12345678-1234-4234-9234-123456789abc',
          ).toJson(),
        }),
      );
      final engine = EngineWorkerController(
        platformKind: EnginePlatformKind.windows,
        connection: connection,
      );
      final host = DesktopEngineHost(engine: engine);
      expect((await host.start()).phase, 'busy');
      await settle();
      expect(engine.isClosed, isTrue);
      expect((await host.start()).phase, 'busy');
      expect(connection.starts, 1);
      await host.close();
      await connection.stream.close();
    },
  );
}
