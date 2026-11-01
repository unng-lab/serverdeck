import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_engine/api/owner_reads.dart';
import 'package:serverdeck_engine/remote/reads.dart';
import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:test/test.dart';

import '../support/schema3_fixture.dart' as fixture;
import 'connection_drain_test.dart' as connection;
import 'ssh_pool_lifecycle_test.dart' show settle;

final class Clock implements EngineClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  DateTime get utcNow => DateTime.utc(2026, 10, 30, 12).add(elapsed);
}

const observed = '2026-10-29T10:00:00.000Z';
String sections(Map<String, String> values) => values.entries
    .map((e) => '${e.key}\t0\t${base64.encode(utf8.encode(e.value))}\n')
    .join();

// Synthetic byte input to the actual SSH capture and observation parsers.
// No prebuilt SshReadOutput/cache/result and no socket, file, process or UI.
void respond(connection.Setup s) {
  var samples = 0;
  s.io.attempts.single.client.onExecute = (session, command) {
    final text = switch (command.read!.source) {
      SshReadSource.system => sections({
        'osRelease': 'ID=debian\nVERSION_ID=12\nPRETTY_NAME="unit"',
        'kernel': 'unit-kernel',
        'architecture': 'x86_64',
        'hostname': 'unit-host',
        'uptime': '3600.0 1800.0',
        'bootId': 'unit-boot',
        'observedAt': observed,
      }),
      SshReadSource.metrics => sections({
        'cpu': 'cpu ${100 + 10 * samples++} 0 10 100 0 0 0 0',
        'memory': 'MemTotal: 1000 kB\nMemAvailable: 500 kB',
        'disk': 'Filesystem 1K-blocks Used Available Use% Mounted on\nunit 1000 500 500 50% /',
        'network': 'lo: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0',
        'observedAt': observed,
      }),
      SshReadSource.packages => 'unit-package\t1.0\tii \n',
      SshReadSource.units =>
        'unit.service loaded active running unit service\n',
      SshReadSource.journal => [
        for (var i = 1; i <= 2; i++)
          jsonEncode({
            '__CURSOR': 'unit-$i',
            '__REALTIME_TIMESTAMP':
                '${DateTime.parse(observed).microsecondsSinceEpoch + i}',
            'MESSAGE': 'unit message $i',
            'PRIORITY': '6',
            '_SYSTEMD_UNIT': 'unit.service',
          }),
      ].join('\n'),
    };
    session.output.add(Uint8List.fromList(utf8.encode(text)));
    session.finish().ignore();
  };
}

Future<Map<String, Object?>> state(
  connection.Setup s,
  RemoteReadService reads, {
  bool refresh = false,
}) async {
  final work = reads.startOwner(await s.context(), 'serverdeck_state_get', {
    'serverId': fixture.profile,
    'refresh': refresh,
  });
  final result = await work.result;
  await work.done;
  return result;
}

void main() {
  test(
    'cache clock controls five-second reuse, not remote observation time',
    () async {
      final s = await connection.Setup.create();
      respond(s);
      final clock = Clock();
      final actual = RemoteReadService(s.connections, clock: clock);
      addTearDown(actual.close);
      final first = await state(s, actual, refresh: true);
      final client = s.io.attempts.single.client;
      expect(client.commands, hasLength(4));
      expect((first['system'] as Map)['observedAt'], observed);
      expect((first['metrics'] as Map)['observedAt'], observed);
      expect(
        (first['system'] as Map)['receivedAt'],
        clock.utcNow.toIso8601String(),
      );
      expect(
        (first['packages'] as Map)['observedAt'],
        clock.utcNow.toIso8601String(),
      );
      clock.elapsed =
          const Duration(seconds: 5) - const Duration(microseconds: 1);
      await state(s, actual, refresh: true);
      expect(client.commands, hasLength(4));
      clock.elapsed = const Duration(seconds: 5);
      final second = await state(s, actual, refresh: true);
      expect(
        client.commands,
        hasLength(6),
      ); // inventory still fresh for five minutes
      expect((second['metrics'] as Map)['observedAt'], observed);
      expect(
        (second['metrics'] as Map)['receivedAt'],
        clock.utcNow.toIso8601String(),
      );
      expect(((second['metrics'] as Map)['value'] as Map)['cpuPercent'], 100);
      clock.elapsed = const Duration(seconds: 20);
      final stale = await state(s, actual);
      expect((stale['metrics'] as Map)['quality'], 'stale');
      expect((stale['packages'] as Map)['quality'], 'known');
    },
  );

  test(
    'history expiry follows receipt clock while owner authority stays current',
    () async {
      final s = await connection.Setup.create();
      respond(s);
      final clock = Clock(),
          reads = RemoteReadService(s.connections, clock: clock);
      addTearDown(reads.close);
      await state(s, reads, refresh: true);
      clock.elapsed = const Duration(minutes: 10);
      expect((await state(s, reads))['history'], hasLength(1));
      clock.elapsed += const Duration(microseconds: 1);
      expect((await state(s, reads))['history'], isEmpty);
      expect(s.io.attempts.single.client.commands, hasLength(4));
    },
  );

  test('cursor expires at five minutes on cache clock, independent of session clock', () async {
    final s = await connection.Setup.create();
    respond(s);
    final clock = Clock(),
        reads = RemoteReadService(s.connections, clock: clock);
    addTearDown(reads.close);
    Future<Map<String, Object?>> logs([Object? cursor]) async {
      final work = reads.startOwner(await s.context(), 'serverdeck_logs_read', {
        'serverId': fixture.profile,
        'limit': 1,
        if (cursor != null) 'cursor': cursor,
      });
      try {
        return await work.result;
      } finally {
        await work.done;
      }
    }

    final first = await logs(), cursor = first['nextCursor'];
    expect(cursor, isA<String>());
    clock.elapsed =
        const Duration(minutes: 5) - const Duration(microseconds: 1);
    final next = await logs(cursor);
    expect(next['records'], hasLength(1));
    clock.elapsed = const Duration(minutes: 5);
    await expectLater(
      logs(cursor),
      throwsA(
        isA<StateError>().having((e) => e.message, 'code', 'CURSOR_EXPIRED'),
      ),
    );
    expect(s.io.attempts.single.client.commands, hasLength(2));
  });

  test('owner handle sixty-second retention uses the service clock', () async {
    final s = await connection.Setup.create();
    final clock = Clock(),
        reads = RemoteReadService(s.connections, clock: clock);
    final api = RemoteReadOwnerApi(reads);
    addTearDown(() async {
      await api.close();
      await reads.close();
    });
    Future<Map<String, Object?>> call(
      String method,
      Map<String, Object?> args,
    ) async {
      final request = s.owner.reserve(method);
      final invocation = api.prepare(
        request,
        method,
        args,
        requestId: fixture.request1,
      );
      try {
        await s.owner.admit(request);
        return await invocation.execute();
      } finally {
        invocation.close();
        request.complete();
      }
    }

    await call('servers.state', {'profileId': fixture.profile});
    await settle();
    clock.elapsed =
        const Duration(seconds: 60) - const Duration(microseconds: 1);
    expect(
      (await call('servers.readStatus', {
        'operationId': fixture.request1,
      }))['state'],
      'succeeded',
    );
    clock.elapsed = const Duration(seconds: 60);
    await expectLater(
      call('servers.readStatus', {'operationId': fixture.request1}),
      throwsA(isA<StateError>().having((e) => e.message, 'code', 'NOT_FOUND')),
    );
    expect(s.io.attempts.single.client.commands, isEmpty);
  });
}
