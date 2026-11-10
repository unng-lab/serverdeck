import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/mcp/pipe_adapter.dart';
import 'package:serverdeck/mcp/router.dart';
import 'package:serverdeck/mcp/tool_schemas.dart';
import 'package:serverdeck/runtime/native_platform.dart';

import '../fixtures/feature_harness.dart';

final class PipePort implements McpPipePort {
  final controller = StreamController<PlatformEvent>.broadcast();
  final output = <String, List<Map<String, dynamic>>>{}, closed = <String>[];
  Completer<void>? holdClose;
  bool published = false;
  int sequence = 0;
  @override
  Stream<PlatformEvent> get events => controller.stream;
  void event(
    String epoch,
    String type,
    String id, [
    Map<String, Object?> extra = const {},
  ]) => controller.add(
    PlatformEvent(epoch, ++sequence, type, {'channelId': id, ...extra}),
  );
  @override
  Future<void> publish() async {
    published = true;
  }

  @override
  Future<void> remove() async {
    published = false;
  }

  @override
  Future<void> send(String id, String frame) async {
    output
        .putIfAbsent(id, () => [])
        .add(jsonDecode(frame) as Map<String, dynamic>);
  }

  @override
  Future<void> close(String id) async {
    closed.add(id);
    await holdClose?.future;
  }

  @override
  Future<void> acknowledge(String id) async {}

  @override
  Future<void> writeGrant(String id, int version, Uint8List bytes) async {}
  @override
  Future<void> deleteGrant(String id) async {}
}

void main() {
  late FeatureHarness h;
  late PipePort port;
  late McpPipeAdapter adapter;
  late String client;
  final registry = jsonDecode(
    File('assets/mcp/tools.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  setUp(() async {
    h = FeatureHarness();
    port = PipePort();
    client = (await h.grants.issue(
      h.actors.ui,
      'Fixture',
      confirmed: true,
    )).clientId;
    await h.grants.setEnabled(h.actors.ui, true);
    final router = McpRouter(
      operations: h.operations,
      grants: h.grants,
      schemas: ToolSchemas(registry),
      release: 'fixture',
    );
    adapter = McpPipeAdapter(
      port: port,
      ownerEpoch: h.actors.ownerEpoch,
      getGrants: () => h.grants,
      getRouter: () => router,
      utcNow: h.clock.now,
      schedule: h.clock.schedule,
    );
    await adapter.initialize();
    await adapter.setEnabled(true);
  });
  tearDown(() async {
    if (port.holdClose != null && !port.holdClose!.isCompleted)
      port.holdClose!.complete();
    await adapter.dispose();
    await port.controller.close();
    await h.dispose();
  });
  String getEpoch() => h.actors.ownerEpoch;
  void frame(String id, Map<String, Object?> value) =>
      port.event(getEpoch(), 'mcpFrame', id, {'frame': jsonEncode(value)});
  Future<void> authenticate(String id, {String user = 'synthetic-user'}) async {
    port.event(getEpoch(), 'mcpChannelOpened', id, {
      'userSid': user,
      'logonSid': 'synthetic-logon',
    });
    frame(id, {
      'kind': 'auth',
      'version': 1,
      'clientId': client,
      'grantVersion': 1,
      'ownerEpoch': getEpoch(),
      'secret': base64Url.encode(List.filled(32, 7)).replaceAll('=', ''),
    });
    await featureTurns(30);
  }

  Future<void> initialize(String id) async {
    frame(id, {
      'kind': 'mcp',
      'payload': {
        'jsonrpc': '2.0',
        'id': 0,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-11-25',
          'capabilities': {},
          'clientInfo': {'name': 'fixture', 'version': '1'},
        },
      },
    });
    await featureTurns(30);
    frame(id, {
      'kind': 'mcp',
      'payload': {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
    });
    await featureTurns();
  }

  test('verified peer and grant proof precede domain dispatch; response has no secret', () async {
    final id = featureId(700);
    await authenticate(id);
    expect(port.output[id]!.first['kind'], 'authorized');
    await initialize(id);
    frame(id, {
      'kind': 'mcp',
      'payload': {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'profiles.create',
          'arguments': {
            'mutationId': featureId(720),
            'profile': {
              'displayName': 'Via MCP',
              'host': 'host.invalid',
              'username': 'root',
              'authentication': {
                'kind': 'password',
                'password': 'never-echo-this-fixture',
              },
            },
          },
        },
      },
    });
    await featureTurns(70);
    expect(h.repository.state.profiles.values.single.displayName, 'Via MCP');
    expect(
      port.output[id].toString(),
      isNot(contains('never-echo-this-fixture')),
    );
    final last = port.output[id]!.last;
    expect(last['kind'], 'mcp');
    expect(((last['payload'] as Map)['result'] as Map)['isError'], isFalse);
  });
  test(
    'foreign actual token is denied generically even with a correct proof',
    () async {
      final id = featureId(701);
      await authenticate(id, user: 'foreign-user');
      expect(port.output[id]!.last, {'kind': 'error', 'code': 'AUTH_REQUIRED'});
      expect(port.closed, contains(id));
      expect(h.repository.state.profiles, isEmpty);
    },
  );
  test('one grant supports eight independent MCP sessions', () async {
    for (var i = 701; i <= 708; i++) {
      final id = featureId(i);
      await authenticate(id);
      expect(port.output[id]!.first['kind'], 'authorized');
      await initialize(id);
      frame(id, {
        'kind': 'mcp',
        'payload': {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/list',
          'params': {},
        },
      });
    }
    await featureTurns(70);
    expect(port.closed, isEmpty);
    for (var i = 701; i <= 708; i++) {
      final response = port.output[featureId(i)]!.last['payload'] as Map;
      expect(response['id'], 1);
      expect((response['result'] as Map)['tools'], isNotEmpty);
      expect(response.containsKey('error'), isFalse);
    }
    await adapter.closeClient(client);
    expect(port.closed.toSet(), {
      for (var i = 701; i <= 708; i++) featureId(i),
    });
  });
  test(
    'global channel limit preserves sessions and a released slot is reusable',
    () async {
      for (var i = 701; i <= 708; i++) {
        await authenticate(featureId(i));
      }
      final rejected = featureId(709);
      await authenticate(rejected);
      expect(port.closed, [rejected]);
      expect(port.output[rejected], isNull);

      port.event(getEpoch(), 'mcpChannelClosed', featureId(701));
      await featureTurns();
      final replacement = featureId(710);
      await authenticate(replacement);
      expect(port.output[replacement]!.first['kind'], 'authorized');
      await initialize(featureId(702));
      expect(port.closed, [rejected]);
      expect(
        (port.output[featureId(702)]!.last['payload'] as Map)['result'],
        contains('serverInfo'),
      );
    },
  );
  test('first-frame deadline and grant expiry close idle channels', () async {
    final pending = featureId(701);
    port.event(getEpoch(), 'mcpChannelOpened', pending, {
      'userSid': 'synthetic-user',
      'logonSid': 'synthetic-logon',
    });
    await featureTurns();
    h.clock.advance(const Duration(seconds: 5));
    await featureTurns();
    expect(port.closed, contains(pending));
    final active = featureId(702);
    await authenticate(active);
    h.clock.advance(const Duration(days: 90));
    await featureTurns();
    expect(port.closed, contains(active));
  });
  test('closing a client retains and reuses the exact physical close until acknowledgment', () async {
    final id = featureId(701);
    await authenticate(id);
    port.holdClose = Completer<void>();
    var done = false;
    final close = adapter.closeClient(client).then((_) => done = true);
    await featureTurns();
    expect(done, isFalse);
    expect(port.closed.where((v) => v == id).length, 1);
    final retry = adapter.closeClient(client);
    await featureTurns();
    expect(port.closed.where((v) => v == id).length, 1);
    port.holdClose!.complete();
    await close;
    await retry;
    expect(done, isTrue);
  });
  test('raw MCP before auth and stale epoch metadata never dispatch', () async {
    final id = featureId(701);
    port.event(getEpoch(), 'mcpChannelOpened', id, {
      'userSid': 'synthetic-user',
      'logonSid': 'synthetic-logon',
    });
    frame(id, {
      'kind': 'mcp',
      'payload': {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
    });
    await featureTurns();
    expect(port.closed, contains(id));
    port.event(featureId(999), 'mcpChannelOpened', featureId(702), {
      'userSid': 'synthetic-user',
      'logonSid': 'synthetic-logon',
    });
    await featureTurns();
    expect(port.output.containsKey(featureId(702)), isFalse);
    expect(h.repository.state.profiles, isEmpty);
  });
}
