import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/console_models.dart';
import 'package:serverdeck/console/console_owner.dart';
import 'package:serverdeck/console/console_port.dart';
import 'package:serverdeck/mcp/router.dart';
import 'package:serverdeck/mcp/tool_schemas.dart';

import '../console/fakes.dart';
import '../fixtures/feature_harness.dart';
import 'router_contract_test.dart' show rpc;

void main() {
  late FeatureHarness h;
  late FakeConsolePort port;
  late ConsoleOwner owner;
  late McpRouter router;
  late McpSession session;
  late String profile, client;
  var request = 0, sequence = 0;
  Future<void> initialize(McpSession target) async {
    await target.handle(
      rpc(0, 'initialize', {
        'protocolVersion': '2025-11-25',
        'capabilities': {},
        'clientInfo': {},
      }),
    );
    await target.handle({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
  }

  setUp(() async {
    h = FeatureHarness(onClientInvalidated: (id) => owner.invalidateClient(id));
    profile = await h.create();
    port = FakeConsolePort(h.state.versions);
    owner = ConsoleOwner(
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
    final grant = await h.grants.issue(h.actors.ui, 'Agent', confirmed: true);
    client = grant.clientId;
    await h.grants.setEnabled(h.actors.ui, true);
    router = McpRouter(
      operations: h.operations,
      consoles: owner,
      grants: h.grants,
      schemas: ToolSchemas(
        jsonDecode(File('assets/mcp/tools.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
      release: 'unit',
    );
    session = router.session(h.actors.mcp(clientId: client, grantVersion: 1));
    await initialize(session);
    request = 0;
    sequence = 0;
  });
  tearDown(() async {
    session.closed = true;
    await owner.dispose();
    await port.events.close();
    await h.dispose();
  });
  Future<Map> call(
    String name,
    Map<String, dynamic> input, {
    bool mutate = false,
  }) async {
    final reply = await session.handle(
      rpc(++request, 'tools/call', {
        'name': 'console.$name',
        'arguments': {
          ...input,
          if (mutate) ...{
            'ownerEpoch': h.actors.ownerEpoch,
            'operationSequence': ++sequence,
          },
        },
      }),
    );
    expect(reply!['error'], isNull, reason: jsonEncode(reply));
    final result = reply['result'] as Map;
    expect(
      jsonDecode((result['content'] as List).single['text'] as String),
      result['structuredContent'],
    );
    return result['structuredContent'] as Map;
  }

  Future<Map<String, dynamic>> open() async {
    final value =
        (await call('open', {'profileId': profile}, mutate: true))['value']
            as Map;
    await featureTurns();
    return {
      'profileId': profile,
      'sessionId': value['sessionId'],
      'generation': value['generation'],
      'leaseToken': value['leaseToken'],
    };
  }

  test('router reads the same visible engine and writes corrections on one channel', () async {
    expect((await call('profiles', {}))['ok'], true);
    expect(
      (await call('list', {'profileId': profile}))['value']['sessions'],
      isEmpty,
    );
    expect(port.openings, isEmpty);
    final target = await open();
    final readTarget = {...target}..remove('leaseToken');
    port.openings.single.channel.emit(utf8.encode('shared-output\r\n'));
    await featureTurns();
    final page =
        (await call('read', {...readTarget, 'limit': 1}))['value'] as Map;
    expect(jsonEncode(page), contains('shared-output'));
    expect(
      owner.engine(target['sessionId'] as String)!.screen.first.text,
      contains('shared-output'),
    );
    for (final key in ['Ctrl+U', 'Backspace', 'Ctrl+C', 'Enter']) {
      expect(
        (await call('write', {...target, 'key': key}, mutate: true))['ok'],
        true,
      );
    }
    expect(port.openings.length, 1);
    expect(
      port.openings.single.channel.writes.map(utf8.decode).join(),
      '\x15\x7f\x03\r',
    );
    expect((await call('release', target, mutate: true))['ok'], true);
    final acquired = await call('acquire', readTarget, mutate: true);
    target['leaseToken'] = acquired['value']['leaseToken'];
    port.openings.single.channel.emit(utf8.encode('new-output'));
    await featureTurns();
    final gap =
        (await call('read', {
              ...readTarget,
              'cursor': page['nextCursor'],
            }))['value']
            as Map;
    expect(gap['historyGap'], true);
    expect(gap['rows'], isEmpty);
    expect(gap['nextCursor'], isNull);
    expect(
      (await call('close', {...target, 'confirmed': true}, mutate: true))['ok'],
      true,
    );
    expect(owner.sessionsFor(profile), isEmpty);
    expect(port.connected, true);
  });
  test('unknown outcome cached across reconnect never writes twice; old lease not restored', () async {
    final target = await open();
    port.openings.single.channel.outcome = const ConsoleWriteOutcome(
      2,
      'outcomeUnknown',
    );
    final input = {
      ...target,
      'text': 'abc',
      'ownerEpoch': h.actors.ownerEpoch,
      'operationSequence': ++sequence,
    };
    final first = await call('write', input);
    expect((first['value'] as Map)['status'], 'outcomeUnknown');
    session.closed = true;
    session = router.session(h.actors.mcp(clientId: client, grantVersion: 1));
    await initialize(session);
    request = 0;
    final replay = await call('write', input);
    expect((replay['value'] as Map)['replayed'], true);
    expect(port.openings.single.channel.writes.length, 1);
    expect(owner.sessionsFor(profile).single.inputOwner.kind, 'free');
    expect(
      (await call('write', {
        ...target,
        'key': 'Enter',
      }, mutate: true))['error']['code'],
      'CONSOLE_INPUT_BUSY',
    );
  });
  test(
    'target, Unicode, byte and multiline validation have no input effects',
    () async {
      final target = await open();
      final other = await h.create(host: 'other.invalid');
      final wrong = {...target, 'profileId': other}..remove('leaseToken');
      expect((await call('read', wrong))['error']['code'], 'CONSOLE_NOT_FOUND');
      expect(
        (await call('read', {
          ...wrong,
          'profileId': profile,
          'generation': 2,
        }))['error']['code'],
        'CONFLICT',
      );
      for (final text in ['echo one\necho two', '\ud800', '😀' * 20000]) {
        expect(
          (await call('write', {
            ...target,
            'text': text,
          }, mutate: true))['error']['code'],
          'INVALID_ARGUMENT',
        );
      }
      expect(port.openings.single.channel.writes, isEmpty);
    },
  );
  test(
    'evicted operation returns exact replay error and never reopens',
    () async {
      final target = await open();
      final acquire = {...target}..remove('leaseToken');
      for (var i = 0; i < 64; i++) {
        expect((await call('acquire', acquire, mutate: true))['ok'], true);
      }
      final old = await call('open', {
        'profileId': profile,
        'ownerEpoch': h.actors.ownerEpoch,
        'operationSequence': 1,
      });
      expect(old['error']['code'], 'CONSOLE_REPLAY_EXPIRED');
      expect(port.openings.length, 1);
    },
  );
  test('revoke cancels queued input and denies cached results without closing terminal', () async {
    final target = await open();
    final channel = port.openings.single.channel;
    channel.hold = Completer<void>();
    final pending = session.handle(
      rpc(++request, 'tools/call', {
        'name': 'console.write',
        'arguments': {
          ...target,
          'text': 'private',
          'ownerEpoch': h.actors.ownerEpoch,
          'operationSequence': ++sequence,
        },
      }),
    );
    await featureTurns();
    await h.grants.revoke(h.actors.ui, client, confirmed: true);
    expect(owner.sessionsFor(profile).single.inputOwner.kind, 'free');
    channel.hold!.complete();
    expect((await pending)!['error'], isNotNull);
    expect(channel.writes, isEmpty);
    expect(channel.closed, false);
    final denied = await session.handle(
      rpc(++request, 'tools/call', {
        'name': 'console.open',
        'arguments': {
          'profileId': profile,
          'ownerEpoch': h.actors.ownerEpoch,
          'operationSequence': 1,
        },
      }),
    );
    expect(denied!['error'], isNotNull);
  });
  test(
    'EOF cancels pending opening before late channel can become active',
    () async {
      port.autoOpen = false;
      await open();
      session.closed = true;
      port.openings.single.complete();
      await featureTurns();
      expect(owner.sessionsFor(profile).single.state, 'error');
      expect(port.openings.single.cancelled, true);
    },
  );
  for (final change in ['rotate', 'disable', 'expiry']) {
    test(
      '$change denies history and cached mutations and releases lease',
      () async {
        final target = await open();
        switch (change) {
          case 'rotate':
            await h.grants.rotate(h.actors.ui, client, confirmed: true);
          case 'disable':
            await h.grants.setEnabled(h.actors.ui, false);
          case 'expiry':
            h.clock.advance(const Duration(days: 90));
            await featureTurns();
        }
        expect(owner.sessionsFor(profile).single.inputOwner.kind, 'free');
        expect(port.openings.single.channel.closed, false);
        final read = {...target}..remove('leaseToken');
        final denied = await session.handle(
          rpc(++request, 'tools/call', {
            'name': 'console.read',
            'arguments': read,
          }),
        );
        expect(denied!['error'], isNotNull);
        final cached = await session.handle(
          rpc(++request, 'tools/call', {
            'name': 'console.open',
            'arguments': {
              'profileId': profile,
              'ownerEpoch': h.actors.ownerEpoch,
              'operationSequence': 1,
            },
          }),
        );
        expect(cached!['error'], isNotNull);
        expect(port.openings.length, 1);
      },
    );
  }
}
