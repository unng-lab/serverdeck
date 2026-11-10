import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/sha256.dart';

import 'dart:typed_data';

import 'package:serverdeck/domain/receipt_book.dart';
import 'package:serverdeck/mcp/router.dart';
import 'package:serverdeck/mcp/tool_schemas.dart';
import 'package:serverdeck/software/software_owner.dart';
import 'package:serverdeck/console/console_owner.dart';
import 'package:serverdeck/console/console_models.dart';

import '../console/fakes.dart';

import '../fixtures/feature_harness.dart';
import '../mcp/router_contract_test.dart' show rpc;

void main() {
  late FeatureHarness h;
  late SoftwareOwner owner;
  late ConsoleOwner consoles;
  late FakeConsolePort port;
  late String clientId;
  late McpSession session;
  late String profile;
  var sequence = 0;
  final registry = jsonDecode(
    File('assets/mcp/tools.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final schemas = ToolSchemas(registry);
  Future<Map> call(String name, Map<String, dynamic> args) async {
    final response = await session.handle(
      rpc(++sequence, 'tools/call', {'name': name, 'arguments': args}),
    );
    expect(response!.containsKey('error'), false, reason: jsonEncode(response));
    expect(
      utf8.encode(jsonEncode(response)).length,
      lessThanOrEqualTo(1048576),
    );
    return (response['result'] as Map)['structuredContent'] as Map;
  }

  Map<String, dynamic> card({String name = 'Redis'}) => {
    'name': name,
    'version': null,
    'service': null,
    'dataPaths': <String>[],
    'configPaths': <String>[],
  };
  setUp(() async {
    h = FeatureHarness();
    profile = await h.create();
    sequence = 0;
    owner = SoftwareOwner(
      gate: h.gate,
      repository: h.repository,
      receipts: ReceiptBook(h.signer, h.clock.now),
      newId: h.newId,
      utcNow: h.clock.now,
    );
    final grant = await h.grants.issue(h.actors.ui, 'AI', confirmed: true);
    clientId = grant.clientId;
    port = FakeConsolePort(h.state.versions);
    consoles = ConsoleOwner(
      actors: h.actors,
      gate: h.gate,
      state: h.state,
      repository: h.repository,
      connections: port,
      configuration: () => const ConsoleConfiguration(),
      newId: h.newId,
      monotonicNow: h.clock.monotonic,
      schedule: h.clock.schedule,
    );
    await h.grants.setEnabled(h.actors.ui, true);
    session = McpRouter(
      operations: h.operations,
      software: owner,
      consoles: consoles,
      grants: h.grants,
      schemas: schemas,
      release: 'unit',
    ).session(h.actors.mcp(clientId: grant.clientId, grantVersion: 1));
    await session.handle(
      rpc(0, 'initialize', {
        'protocolVersion': '2025-11-25',
        'capabilities': {},
        'clientInfo': {},
      }),
    );
    await session.handle({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
  });
  for (final name in ToolSchemas.names.where(
    (n) => n.startsWith('software.'),
  )) {
    test('$name rejects unknown keys before any local effect', () async {
      final args = <String, dynamic>{'profileId': profile};
      if (name == 'software.get') {
        args.remove('profileId');
      }
      if (!['software.list', 'software.history.list'].contains(name))
        args['softwareId'] = h.newId();
      if (name == 'software.save') {
        args.remove('softwareId');
        args['card'] = card();
        args['mutationId'] = h.newId();
      }
      if (name == 'software.delete') {
        args['expectedRevision'] = 1;
        args['mutationId'] = h.newId();
      }
      if (name == 'software.history.add') {
        args['mutationId'] = h.newId();
        args['action'] = 'other';
        args['summary'] = 'Observed';
        args['outcome'] = 'unknown';
      }
      final response = await session.handle(
        rpc(++sequence, 'tools/call', {
          'name': name,
          'arguments': {...args, 'unexpected': 'private-do-not-echo'},
        }),
      );
      expect((response!['error'] as Map)['code'], -32602);
      expect(jsonEncode(response), isNot(contains('private-do-not-echo')));
      expect(h.repository.state.softwareCards, isEmpty);
      expect(h.repository.state.softwareEvents, isEmpty);
    });
  }
  tearDown(() async {
    session.closed = true;
    await consoles.dispose();
    await port.events.close();
    await owner.dispose();
    await h.dispose();
  });
  test('discovery and config commands use shared console; retry never resends input', () async {
    final opened = await call('console.open', {
      'profileId': profile,
      'ownerEpoch': h.actors.ownerEpoch,
      'operationSequence': 1,
    });
    expect(opened['ok'], true);
    await featureTurns();
    final shell = opened['value'] as Map;
    final write = {
      'profileId': profile,
      'sessionId': shell['sessionId'],
      'generation': shell['generation'],
      'leaseToken': shell['leaseToken'],
      'ownerEpoch': h.actors.ownerEpoch,
      'operationSequence': 2,
      'text': "cat /etc/redis/redis.conf\nprintf '%s' 'test' > /tmp/serverdeck-example.conf",
      'confirmedMultiline': true,
    };
    final sent = await call('console.write', write);
    expect(sent['ok'], true);
    expect((sent['value'] as Map).containsKey('exitCode'), false);
    final writes = port.openings.single.channel.writes.length;
    expect((await call('console.write', write))['ok'], true);
    expect(port.openings.single.channel.writes.length, writes);
    port.openings.single.channel.emit(
      utf8.encode('Redis instance A\r\nRedis instance B\r\n'),
    );
    await featureTurns();
    final output = await call('console.read', {
      'profileId': profile,
      'sessionId': shell['sessionId'],
      'generation': shell['generation'],
    });
    expect(jsonEncode(output), contains('Redis instance A'));
    expect(
      consoles
          .engine(shell['sessionId'] as String)!
          .screen
          .map((r) => r.text)
          .join(),
      contains('Redis instance B'),
    );
    for (var i = 0; i < 2; i++) {
      expect(
        (await call('software.save', {
          'profileId': profile,
          'mutationId': h.newId(),
          'card': card(),
        }))['ok'],
        true,
      );
    }
    expect(h.repository.state.softwareCards.length, 2);
    expect(
      h.repository.state.softwareCards.values.every(
        (c) => c.version == null && c.configPaths.isEmpty,
      ),
      true,
    );
    await h.grants.revoke(h.actors.ui, clientId, confirmed: true);
    final denied = await session.handle(
      rpc(++sequence, 'tools/call', {
        'name': 'console.read',
        'arguments': {
          'profileId': profile,
          'sessionId': shell['sessionId'],
          'generation': shell['generation'],
        },
      }),
    );
    expect(denied!.containsKey('error'), true);
    expect(jsonEncode(denied), isNot(contains('Redis instance')));
    expect(port.openings.single.channel.writes.length, writes);
  });
  test(
    'six software routes share metadata owner and preserve deletion history',
    () async {
      final created = await call('software.save', {
        'profileId': profile,
        'mutationId': h.newId(),
        'card': card(),
      });
      expect(created['ok'], true);
      final id = (created['value'] as Map)['entityId'];
      final read = await call('software.get', {'softwareId': id});
      expect((read['value'] as Map)['version'], isNull);
      expect((read['value'] as Map)['dataPaths'], isEmpty);
      expect((await call('software.list', {'profileId': profile}))['ok'], true);
      final note = await call('software.history.add', {
        'profileId': profile,
        'softwareId': id,
        'mutationId': h.newId(),
        'action': 'configure',
        'summary': 'Observed change',
        'outcome': 'unknown',
      });
      expect(note['ok'], true);
      final update = await call('software.save', {
        'profileId': profile,
        'softwareId': id,
        'expectedRevision': 1,
        'mutationId': h.newId(),
        'card': card(name: 'Redis instance'),
      });
      expect((update['value'] as Map)['revision'], 2);
      expect(
        (await call('software.delete', {
          'profileId': profile,
          'softwareId': id,
          'expectedRevision': 2,
          'mutationId': h.newId(),
        }))['ok'],
        true,
      );
      final history = await call('software.history.list', {
        'profileId': profile,
        'softwareId': id,
      });
      final events = ((history['value'] as Map)['items'] as List).cast<Map>();
      expect(events.length, 4);
      expect(
        events.singleWhere((e) => e['kind'] == 'note')['actorKind'],
        'mcp',
      );
      expect(h.repository.state.softwareCards, isEmpty);
    },
  );
  test(
    'strict schema rejects unexpected keys, missing fields and coerced numbers',
    () async {
      for (final args in [
        {
          'profileId': profile,
          'mutationId': h.newId(),
          'card': {...card(), 'command': 'hidden'},
        },
        {
          'profileId': profile,
          'mutationId': h.newId(),
          'card': {'name': 'Redis'},
        },
        {
          'profileId': profile,
          'softwareId': h.newId(),
          'mutationId': h.newId(),
          'card': card(),
        },
        {
          'profileId': profile,
          'expectedRevision': 1,
          'mutationId': h.newId(),
          'card': card(),
        },
        {
          'profileId': profile,
          'softwareId': h.newId(),
          'expectedRevision': 1.0,
          'mutationId': h.newId(),
          'card': card(),
        },
        {
          'profileId': profile,
          'mutationId': h.newId(),
          'card': card(),
          'actorKind': 'ui',
        },
      ]) {
        expect(
          () => schemas.arguments('software.save', args),
          throwsA(isA<SchemaFailure>()),
        );
      }
      expect(
        () => schemas.arguments('software.list', {
          'profileId': profile,
          'limit': '25',
        }),
        throwsA(isA<SchemaFailure>()),
      );
      expect(
        () => schemas.arguments('software.list', {
          'profileId': profile,
          'limit': 25.0,
        }),
        throwsA(isA<SchemaFailure>()),
      );
      expect(h.repository.state.softwareCards, isEmpty);
    },
  );
  test(
    'owner validation remains a domain failure and never echoes invalid input',
    () async {
      final result = await call('software.save', {
        'profileId': profile,
        'mutationId': h.newId(),
        'card': card(name: '   '),
      });
      expect(result['ok'], false);
      expect((result['error'] as Map)['code'], 'INVALID_ARGUMENT');
      expect(h.repository.state.softwareCards, isEmpty);
    },
  );
  test('large card pages respect full duplicated response budget without losing fields', () async {
    final paths = List.generate(16, (i) => '/$i/${'"' * 480}');
    for (var i = 0; i < 30; i++) {
      final created = await call('software.save', {
        'profileId': profile,
        'mutationId': h.newId(),
        'card': {
          ...card(name: 'Large$i'),
          'dataPaths': paths,
          'configPaths': paths,
        },
      });
      expect(created['ok'], true);
    }
    final seen = <String>{};
    String? cursor;
    var pages = 0;
    do {
      final result = await call('software.list', {
        'profileId': profile,
        'limit': 100,
        if (cursor != null) 'cursor': cursor,
      });
      expect(result['ok'], true, reason: jsonEncode(result));
      final value = result['value'] as Map,
          items = (value['items'] as List).cast<Map>();
      if (pages == 0) expect(items.length, lessThan(30));
      for (final item in items) {
        expect(item['dataPaths'], paths);
        expect(item['configPaths'], paths);
        expect(seen.add(item['softwareId'] as String), true);
      }
      cursor = value['nextCursor'] as String?;
      pages++;
    } while (cursor != null && pages < 10);
    expect(cursor, isNull);
    expect(seen.length, 30);
  });
  test('registry version3 retains original21 definitions except additive reconnect status', () {
    expect(registry['contractVersion'], 3);
    expect(schemas.tools.length, 27);
    final original =
        jsonDecode(jsonEncode(schemas.tools.take(21).toList())) as List;
    for (final tool in original) {
      final definition =
          (tool['outputSchema'][r'$defs'] as Map)['ConnectionView'];
      if (definition == null) continue;
      final properties = definition['properties'] as Map;
      expect(properties.remove('reconnectAttempt'), {
        'type': 'integer',
        'minimum': 1,
        'maximum': 9007199254740991,
      });
    }
    final digest = SHA256Digest()
        .process(Uint8List.fromList(utf8.encode(jsonEncode(original))))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(
      digest,
      '806aad3ff37cc6430f184f48639e9f99bd87e0531137798b90f0d58527339080',
    );
    expect(
      File('specs/003-ssh-mcp/contracts/mcp-tools.json').readAsStringSync(),
      File('assets/mcp/tools.json').readAsStringSync(),
    );
  });
}
