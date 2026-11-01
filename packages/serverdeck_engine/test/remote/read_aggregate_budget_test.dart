import 'dart:convert';

import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:test/test.dart';

import '../support/remote_read_graph.dart';
import '../support/remote_read_setup.dart';
import 'read_isolation_bounds_test.dart' show read, emit;

const budget = 64 * 1024 * 1024;
Future<void> connect(Setup s, Mcp client, int profile) async {
  await s.invoke(client, {
    'catalog': <String, Object?>{},
  }); // actual lease renewal, not cache time
  final work = s.connections.connectMcp(client.context, profileId(profile));
  await work.result;
  await work.done;
}

Future<void> disconnect(Setup s, Mcp client, int profile) async {
  final work = s.connections.disconnectMcp(client.context, profileId(profile));
  await work.result;
  await work.done;
}

Future<Map<String, Object?>> current(
  Setup s,
  Mcp client,
  int profile,
  String tool, {
  bool refresh = false,
}) async {
  await s.invoke(client, {'catalog': <String, Object?>{}});
  return read(s, tool, {
    'serverId': profileId(profile),
    if (tool == 'serverdeck_state_get') 'refresh': refresh,
    if (tool == 'serverdeck_logs_read') 'limit': 1000,
  }, client: client);
}

void main() {
  test('fitted1536KiB target caches evict oldest parts at the real64MiB aggregate budget', () async {
    const count = 72;
    final s = await Setup.create(profiles: count), client = await s.mcp();
    final packages = [
      for (var i = 0; i < 2048; i++)
        'p${i.toString().padLeft(4, '0')}${'p' * 170}\t${'v' * 220}\tii \n',
    ].join();
    final units = [
      for (var i = 0; i < 2048; i++)
        'u$i.service loaded active running ${'d' * 1000}\n',
    ].join();
    s.response = (session, source) {
      if (source == SshReadSource.packages) {
        emit(session, packages);
        return true;
      }
      if (source == SshReadSource.units) {
        emit(session, units);
        return true;
      }
      return false;
    };
    final sizes = <int>[];
    for (var i = 0; i < count; i++) {
      s.clock.elapsed = Duration(seconds: i);
      await connect(s, client, i);
      final view = await current(
        s,
        client,
        i,
        'serverdeck_state_get',
        refresh: true,
      );
      final parts = {
        for (final key in ['system', 'metrics', 'packages', 'units'])
          key: Map<String, Object?>.from(view[key] as Map)..remove('stale'),
      };
      final size = utf8.encode(jsonEncode(parts)).length;
      expect(size, inInclusiveRange(1024 * 1024, 1536 * 1024));
      expect((view['units'] as Map)['truncated'], isTrue);
      sizes.add(size);
      await disconnect(s, client, i);
      expect(s.pool.activeTransports, lessThanOrEqualTo(2));
    }
    expect(sizes.reduce((a, b) => a + b), greaterThan(budget));
    var retained = 0, evicted = 0;
    for (var i = 0; i < count; i++) {
      final view = await current(s, client, i, 'serverdeck_state_get');
      if (view['cacheDropped'] == true) {
        evicted++;
        expect((view['system'] as Map)['quality'], 'unknown');
        expect((view['system'] as Map)['code'], 'RESOURCE_LIMIT');
        expect(view['history'], isEmpty);
      } else {
        retained += sizes[i];
      }
      if (i == 0) expect(view['cacheDropped'], isTrue);
      if (i == count - 1) expect(view['cacheDropped'], isFalse);
    }
    expect(evicted, greaterThan(0));
    expect(retained, lessThanOrEqualTo(budget));
    expect(
      retained,
      greaterThan(budget - sizes.reduce((a, b) => a > b ? a : b)),
    );
    expect(
      s.io.attempts.expand((a) => a.client.commands),
      hasLength(count * 4),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('journal aggregate64MiB is independent of each target500 record ring', () async {
    final s = await Setup.create(profiles: 3, scopes: ['read', 'logs']),
        client = await s.mcp();
    var sequence = 0, empty = false;
    final message = 'z' * (52 * 1024);
    s.response = (session, source) {
      if (source != SshReadSource.journal) return false;
      final text = empty
          ? ''
          : [
              for (var j = 0; j < 39; j++)
                jsonEncode({
                  '__CURSOR': 'budget-${sequence++}',
                  '__REALTIME_TIMESTAMP':
                      '${DateTime.utc(2026, 10, 29).microsecondsSinceEpoch + sequence}',
                  'MESSAGE': message,
                  'PRIORITY': '6',
                  '_SYSTEMD_UNIT': 'unit.service',
                }),
            ].join('\n');
      emit(session, text);
      return true;
    };
    final sizes = <List<int>>[];
    for (var i = 0; i < 3; i++) {
      await connect(s, client, i);
      final rows = <int>[];
      for (var batch = 0; batch < 13; batch++) {
        final view = await current(s, client, i, 'serverdeck_logs_read');
        expect(view['records'], hasLength(39));
        rows.addAll(
          (view['records'] as List).map(
            (row) => utf8.encode(jsonEncode(row)).length,
          ),
        );
      }
      sizes.add(rows);
      expect(rows, hasLength(507));
      await disconnect(s, client, i);
    }
    empty = true;
    var retained = 0, dropped = 0;
    for (var i = 0; i < 3; i++) {
      await connect(s, client, i);
      final view = await current(s, client, i, 'serverdeck_logs_read');
      final lost = view['dropped'] as int;
      expect(lost, inInclusiveRange(7, 507));
      final rows = sizes[i].skip(lost).toList();
      expect(rows.length, lessThanOrEqualTo(500));
      retained +=
          2 +
          rows.fold<int>(0, (a, b) => a + b) +
          (rows.isEmpty ? 0 : rows.length - 1);
      dropped += lost;
      await disconnect(s, client, i);
    }
    expect(
      dropped,
      greaterThan(3 * 7),
    ); // Per-target500 alone cannot explain this.
    expect(retained, lessThanOrEqualTo(budget));
    final largest = sizes
        .expand((rows) => rows)
        .reduce((a, b) => a > b ? a : b);
    expect(retained, greaterThan(budget - 2 * largest));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
