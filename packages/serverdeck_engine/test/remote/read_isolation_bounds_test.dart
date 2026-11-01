import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:test/test.dart';

import '../support/remote_read_graph.dart';
import '../support/remote_read_setup.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'read_clock_test.dart' show sections, observed;
import 'shared_reads_test.dart' show failure;
import 'ssh_io_policy_test.dart' as bytes;
import 'ssh_pool_lifecycle_test.dart' show settle;

void emit(bytes.Session session, String text) {
  session.output.add(Uint8List.fromList(utf8.encode(text)));
  session.finish().ignore();
}

String system(String marker) => sections({
  'osRelease': 'ID=debian\nVERSION_ID=12\nPRETTY_NAME="unit"',
  'kernel': 'unit',
  'architecture': 'x86_64',
  'hostname': marker,
  'uptime': '3600 1800',
  'bootId': 'unit-boot',
  'observedAt': observed,
});

String journal(int count, {int start = 0}) => [
  for (var i = start; i < start + count; i++)
    jsonEncode({
      '__CURSOR': 'cursor-$i',
      '__REALTIME_TIMESTAMP':
          '${DateTime.parse(observed).microsecondsSinceEpoch + i}',
      'MESSAGE': 'unit message $i',
      'PRIORITY': '6',
      '_SYSTEMD_UNIT': 'unit.service',
    }),
].join('\n');
Future<Map<String, Object?>> read(
  Setup s,
  String tool,
  Map<String, Object?> args, {
  Mcp? client,
}) async {
  final work = client == null
      ? s.reads.startOwner(await s.ownerContext(), tool, args)
      : s.reads.startMcp(client.context, tool, args);
  try {
    return await work.result;
  } finally {
    await work.done;
  }
}

Future<Map<String, Object?>> state(
  Setup s, {
  String profile = fixture.profile,
  bool refresh = false,
}) =>
    read(s, 'serverdeck_state_get', {'serverId': profile, 'refresh': refresh});

void main() {
  test(
    'two connected profiles use distinct collectors and identity-bound caches',
    () async {
      final s = await Setup.create(profiles: 2);
      await s.ownerCall('servers.connect', {
        'profileId': profileId(1),
      }, id: fixture.request2);
      await settle();
      var marker = 'first';
      s.response = (session, source) {
        if (source != SshReadSource.system) return false;
        emit(session, system(marker));
        return true;
      };
      final first = await state(s, refresh: true);
      marker = 'second';
      final second = await state(s, profile: profileId(1), refresh: true);
      expect(((first['system'] as Map)['value'] as Map)['hostname'], 'first');
      expect(((second['system'] as Map)['value'] as Map)['hostname'], 'second');
      expect((first['identity'] as Map)['profileId'], fixture.profile);
      expect((second['identity'] as Map)['profileId'], profileId(1));
      expect(
        ((await state(s))['system'] as Map)['value'],
        (first['system'] as Map)['value'],
      );
      expect(s.io.attempts, hasLength(2));
      expect(s.io.attempts.every((a) => a.client.commands.length == 4), isTrue);
    },
  );

  test('reconciled connection revision retires cursor and discards late old source', () async {
    final s = await Setup.create();
    var marker = 'warm';
    s.response = (session, source) {
      if (source == SshReadSource.system) {
        emit(session, system(marker));
        return true;
      }
      if (source == SshReadSource.journal) {
        emit(session, journal(1));
        return true;
      }
      return false;
    };
    await state(s, refresh: true);
    final logs = await read(s, 'serverdeck_logs_read', {
      'serverId': fixture.profile,
      'limit': 1,
    });
    final cursor = logs['nextCursor'];
    expect(cursor, isA<String>());
    s.clock.elapsed = const Duration(seconds: 5);
    s.holdSystem = true;
    final pending = s.reads.startOwner(
      await s.ownerContext(),
      'serverdeck_state_get',
      {'serverId': fixture.profile, 'refresh': true},
    );
    final refused = expectLater(pending.result, failure('TRUST_CHANGED'));
    await settle();
    final old = s.held.single;
    final lease = await s.sessions.beginReconciledTargetChange();
    addTearDown(lease.close);
    final before = s.store.snapshot.foundation;
    final source = s.data.source;
    final oldProfile = source.data['StoredProfile']!.single;
    source.data['StoredProfile'] = [
      StoredRow(
        oldProfile.nativeId,
        jsonEncode({
          ...jsonDecode(oldProfile.payload) as Map<String, dynamic>,
          'revision': '3',
          'connectionRevision': '2',
          'trustRevision': '3',
          'updatedAt': '2026-10-30T10:00:02.000Z',
        }),
        entityId: fixture.profile,
      ),
    ];
    final oldTrust = source.data['StoredHostTrust']!.single;
    source.data['StoredHostTrust'] = [
      StoredRow(
        oldTrust.nativeId,
        jsonEncode({
          ...jsonDecode(oldTrust.payload) as Map<String, dynamic>,
          'revision': '3',
          'connectionRevision': '2',
          'updatedAt': '2026-10-30T10:00:02.000Z',
        }),
        entityId: fixture.profile,
      ),
    ];
    final workspace = source.data['StoredWorkspace']!.single;
    source.data['StoredWorkspace'] = [
      StoredRow(
        workspace.nativeId,
        jsonEncode({
          ...jsonDecode(workspace.payload) as Map<String, dynamic>,
          'storeRevision': '3',
        }),
      ),
    ];
    source.data['StoredReceipt']!.add(
      StoredRow(
        103,
        jsonEncode({
          ...fixture.receipt(fixture.grantRequest, 'profiles.update', '3'),
          'committedAt': '2026-10-30T10:00:02.000Z',
        }),
        entityId: fixture.grantRequest,
      ),
    );
    s.store.value = await s.data.load();
    final reconciling = s.connections.reconcile(before, lease);
    await refused;
    marker = 'late-old';
    s.holdSystem = false;
    s.respond(old, SshReadSource.system);
    await reconciling;
    await pending.done;
    await lease.close();
    final stale = await state(s);
    expect(((stale['system'] as Map)['value'] as Map)['hostname'], 'warm');
    expect((stale['system'] as Map)['quality'], 'stale');
    await s.ownerCall('servers.connect', {
      'profileId': fixture.profile,
    }, id: fixture.request2);
    await settle();
    marker = 'current';
    final current = await state(s, refresh: true);
    expect((current['identity'] as Map)['connectionRevision'], '2');
    expect(((current['system'] as Map)['value'] as Map)['hostname'], 'current');
    final count = s.io.attempts.last.client.commands.length;
    await expectLater(
      read(s, 'serverdeck_logs_read', {
        'serverId': fixture.profile,
        'limit': 1,
        'cursor': cursor,
      }),
      failure('CURSOR_EXPIRED'),
    );
    expect(s.io.attempts.last.client.commands, hasLength(count));
  });

  test('partial source errors stay unknown or stale and never publish provider diagnostics', () async {
    final s = await Setup.create();
    var fail = true;
    s.response = (session, source) {
      if (source != SshReadSource.metrics || !fail) return false;
      session.output.addError(StateError('PRIVATE_PROVIDER_DIAGNOSTIC'));
      session.finish().ignore();
      return true;
    };
    final unknown = await state(s, refresh: true);
    expect((unknown['metrics'] as Map)['quality'], 'unknown');
    expect((unknown['system'] as Map)['quality'], 'known');
    expect(jsonEncode(unknown), isNot(contains('PRIVATE_PROVIDER_DIAGNOSTIC')));
    s.clock.elapsed = const Duration(seconds: 5);
    fail = false;
    final known = await state(s, refresh: true);
    expect((known['metrics'] as Map)['quality'], 'known');
    s.clock.elapsed = const Duration(seconds: 10);
    fail = true;
    final stale = await state(s, refresh: true);
    expect((stale['metrics'] as Map)['quality'], 'stale');
    expect(
      (stale['metrics'] as Map)['value'],
      (known['metrics'] as Map)['value'],
    );
    expect(
      (stale['metrics'] as Map)['receivedAt'],
      (known['metrics'] as Map)['receivedAt'],
    );
    expect(jsonEncode(stale), isNot(contains('PRIVATE_PROVIDER_DIAGNOSTIC')));
    expect(s.io.attempts.single.client.commands, hasLength(8)); //4 +2 +2
  });

  test('128 cursor bound is independent of bytes; tamper, filter, principal and read-kind reuse fail', () async {
    final s = await Setup.create(scopes: ['read', 'logs']),
        client = await s.mcp();
    await s.attach(client);
    s.response = (session, source) {
      if (source != SshReadSource.journal) return false;
      emit(session, journal(1));
      return true;
    };
    final args = {'serverId': fixture.profile, 'limit': 1};
    final tokens = <String>[];
    for (var i = 0; i < 128; i++)
      tokens.add(
        (await read(
              s,
              'serverdeck_logs_read',
              args,
              client: client,
            ))['nextCursor']
            as String,
      );
    await expectLater(
      read(s, 'serverdeck_logs_read', args, client: client),
      failure('RESOURCE_LIMIT'),
    );
    final token = tokens.first, other = await s.mcp('other-mcp');
    // The same ID/session/filter accepts the original signature.
    expect(
      (await read(s, 'serverdeck_logs_read', {
        ...args,
        'cursor': token,
      }, client: client))['records'],
      isEmpty,
    );
    final parts = token.split('.'), mac = parts[1];
    final badMac = '${mac[0] == 'A' ? 'B' : 'A'}${mac.substring(1)}';
    expect(base64Url.decode('$badMac='), hasLength(32));
    final signedId = '${parts[0]}.$badMac';
    expect(signedId.split('.').first, parts.first);
    for (final arguments in [
      {...args, 'cursor': signedId},
      {...args, 'cursor': token, 'unit': 'unit.service'},
      {
        ...args,
        'cursor': '${token[0] == 'A' ? 'B' : 'A'}${token.substring(1)}',
      },
    ])
      await expectLater(
        read(s, 'serverdeck_logs_read', arguments, client: client),
        failure('CURSOR_EXPIRED'),
      );
    await expectLater(
      read(s, 'serverdeck_logs_read', {
        ...args,
        'cursor': token,
      }, client: other),
      failure('CURSOR_EXPIRED'),
    );
    await expectLater(
      read(s, 'serverdeck_servers_list', {
        'limit': 1,
        'cursor': token,
      }, client: client),
      failure('CURSOR_EXPIRED'),
    );
    expect(
      s.io.attempts.single.client.commands,
      hasLength(130),
    ); //129 captures including failed allocation, then one positive control.
    s.clock.elapsed = const Duration(minutes: 5);
    expect(
      (await read(
        s,
        'serverdeck_logs_read',
        args,
        client: client,
      ))['nextCursor'],
      isA<String>(),
    );
  });

  test(
    '8MiB cursor byte budget refuses below128 retained wide profile snapshots',
    () async {
      final s = await Setup.create(profiles: 250, wide: true),
          client = await s.mcp();
      final foundation = s.store.snapshot.foundation.foundation;
      final items = [
        for (final p in foundation.profiles.values)
          p.view(foundation.credentials[p.credentialRef]).toJson(),
      ];
      final bytes = utf8.encode(jsonEncode(items)).length;
      final capacity = 8 * 1024 * 1024 ~/ bytes;
      expect(capacity, inInclusiveRange(1, 127));
      for (var i = 0; i < capacity; i++)
        expect(
          (await read(s, 'serverdeck_servers_list', {
            'limit': 1,
          }, client: client))['nextCursor'],
          isA<String>(),
        );
      await expectLater(
        read(s, 'serverdeck_servers_list', {'limit': 1}, client: client),
        failure('RESOURCE_LIMIT'),
      );
      expect(s.io.attempts.single.client.commands, isEmpty);
      s.clock.elapsed = const Duration(minutes: 5);
      expect(
        (await read(s, 'serverdeck_servers_list', {
          'limit': 1,
        }, client: client))['nextCursor'],
        isA<String>(),
      );
    },
  );

  test('history keeps120 points even while121 samples fit ten minutes; inventory refreshes at five minutes', () async {
    final s = await Setup.create();
    Map<String, Object?> latest = {};
    for (var i = 0; i <= 120; i++) {
      s.clock.elapsed = Duration(seconds: i * 5);
      latest = await state(s, refresh: true);
    }
    final history = latest['history'] as List;
    expect(history, hasLength(120));
    expect(
      (history.first as Map)['receivedAt'],
      DateTime.utc(2026, 10, 30, 12, 0, 5).toIso8601String(),
    );
    expect(
      (history.last as Map)['receivedAt'],
      s.clock.utcNow.toIso8601String(),
    );
    final commands = s.io.attempts.single.client.commands;
    expect(
      commands.where((c) => c.read!.source == SshReadSource.packages),
      hasLength(3),
    );
    expect(
      commands.where((c) => c.read!.source == SshReadSource.units),
      hasLength(3),
    );
    expect(
      commands.where((c) => c.read!.source == SshReadSource.metrics),
      hasLength(121),
    );
  });

  test(
    'journal ring drops oldest records at500 and counts a retained duplicate',
    () async {
      final s = await Setup.create();
      var first = true;
      s.response = (session, source) {
        if (source != SshReadSource.journal) return false;
        emit(session, first ? journal(600) : journal(1, start: 599));
        first = false;
        return true;
      };
      final initial = await read(s, 'serverdeck_logs_read', {
        'serverId': fixture.profile,
        'limit': 1000,
      });
      expect(initial['records'], hasLength(600));
      expect(initial['dropped'], 100);
      expect(initial['gaps'], isTrue);
      final duplicate = await read(s, 'serverdeck_logs_read', {
        'serverId': fixture.profile,
        'limit': 1000,
      });
      expect(duplicate['duplicates'], 1);
      expect(duplicate['dropped'], 100);
      expect(s.io.attempts.single.client.commands, hasLength(2));
    },
  );

  test('owner handle16 bound is independent of active work and expires for a different owner', () async {
    final s = await Setup.create(), other = await s.newOwner();
    String id(int i) =>
        '53456789-1234-4234-9234-${i.toString().padLeft(12, '0')}';
    for (var i = 0; i < 16; i++) {
      await s.ownerCall('servers.state', {
        'profileId': fixture.profile,
      }, id: id(i));
      await settle();
      expect(
        (await s.ownerCall('servers.readStatus', {
          'operationId': id(i),
        }))['state'],
        'succeeded',
      );
    }
    await expectLater(
      s.ownerCall(
        'servers.state',
        {'profileId': fixture.profile},
        id: id(16),
        asOwner: other,
      ),
      failure('RESOURCE_LIMIT'),
    );
    s.clock.elapsed = const Duration(seconds: 60);
    expect(
      (await s.ownerCall(
        'servers.state',
        {'profileId': fixture.profile},
        id: id(16),
        asOwner: other,
      ))['state'],
      'running',
    );
    await settle();
    expect(
      (await s.ownerCall('servers.readStatus', {
        'operationId': id(16),
      }, asOwner: other))['state'],
      'succeeded',
    );
    expect(s.io.attempts.single.client.commands, isEmpty);
  });

  test(
    'stderr permission denial stays typed and never publishes raw diagnostics',
    () async {
      final s = await Setup.create();
      s.response = (session, source) {
        if (source != SshReadSource.units) return false;
        session.exitCode = 1;
        session.errors.add(
          Uint8List.fromList(
            utf8.encode('permission denied PRIVATE_STDERR_DIAGNOSTIC'),
          ),
        );
        emit(session, '');
        return true;
      };
      final view = await state(s, refresh: true);
      expect((view['units'] as Map)['quality'], 'denied');
      expect((view['system'] as Map)['quality'], 'known');
      expect(jsonEncode(view), isNot(contains('PRIVATE_STDERR_DIAGNOSTIC')));
    },
  );

  for (final entry in <SshReadRequest, int>{
    const SshReadRequest.system(): 256 * 1024,
    const SshReadRequest.metrics(): 256 * 1024,
    const SshReadRequest.packages(): 4 * 1024 * 1024,
    const SshReadRequest.units(): 2 * 1024 * 1024,
    SshReadRequest.journal(): 8 * 1024 * 1024,
  }.entries) {
    test(
      'actual connection capture keeps exact ${entry.key.source.name} byte bound and flags one-byte overflow',
      () async {
        final s = await Setup.create();
        for (final over in [false, true]) {
          s.response = (session, source) {
            emit(session, 'x' * (entry.value + (over ? 1 : 0)));
            return true;
          };
          final work = s.connections.readOwner(
            await s.ownerContext(),
            fixture.profile,
            entry.key,
          );
          final result = await work.result;
          await work.done;
          expect(result.output.bytes, hasLength(entry.value));
          expect(result.output.truncated, over);
          expect(result.output.bytes.first, 120);
          expect(result.output.bytes.last, 120);
        }
        expect(s.io.attempts.single.client.commands, hasLength(2));
        expect(s.pool.activeTransports, 1);
      },
    );
  }
}
