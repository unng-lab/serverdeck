import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/mcp/router.dart';
import 'package:serverdeck/mcp/tool_schemas.dart';

import '../fixtures/feature_harness.dart';

final class RouterOperations extends Fake implements AppOperations {
  final calls = <Invocation>[];
  Completer<void>? hold;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return () async {
      await hold?.future;
      return const OperationResult<Never>.failure(
        OperationFailure(FailureCode.profileNotFound),
      );
    }();
  }
}

Map<String, dynamic> rpc(
  Object? id,
  String method, [
  Map<String, dynamic>? params,
]) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': method,
  if (params != null) 'params': params,
};
Map<String, dynamic> arguments(String name) {
  final profile = featureId(1),
      attempt = featureId(2),
      nonce = featureId(3),
      mutation = featureId(4),
      fingerprint = featureKey().fingerprint;
  final base = <String, dynamic>{'profileId': profile};
  final consent = <String, dynamic>{
    ...base,
    'attemptId': attempt,
    'nonce': nonce,
    'expectedProfileRevision': 1,
    'expectedTrustRevision': 1,
    'expectedObservationRevision': 1,
    'mutationId': mutation,
    'confirmed': true,
  };
  return switch (name) {
    'profiles.list' => {'limit': 50},
    'profiles.get' || 'connections.get' || 'trust.get' => base,
    'profiles.create' => {
      'mutationId': mutation,
      'profile': {
        'displayName': 'Fixture',
        'host': 'host.invalid',
        'username': 'root',
        'authentication': {'kind': 'password', 'password': 'synthetic-only'},
      },
    },
    'profiles.update' => {
      ...base,
      'expectedRevision': 1,
      'mutationId': mutation,
      'patch': {'displayName': 'Renamed'},
    },
    'connections.connect' => {...base, 'expectedRevision': 1},
    'connections.cancel' => {...base, 'attemptId': attempt},
    'connections.disconnect' => {...base, 'sessionId': attempt},
    'connections.provide_passphrase' => {
      ...base,
      'attemptId': attempt,
      'nonce': nonce,
      'passphrase': 'synthetic-only',
    },
    'trust.accept' => {...consent, 'fingerprint': fingerprint},
    'trust.replace' => {
      ...consent,
      'oldFingerprint': fingerprint,
      'newFingerprint': featureKey(2).fingerprint,
    },
    'trust.retain' => {...consent, 'acceptedFingerprint': fingerprint},
    _ => throw StateError('Unknown fixture tool'),
  };
}

void main() {
  late FeatureHarness h;
  late RouterOperations operations;
  late McpRouter router;
  late McpSession session;
  final registry = jsonDecode(
    File('assets/mcp/tools.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  setUp(() async {
    h = FeatureHarness();
    operations = RouterOperations();
    final grant = await h.grants.issue(h.actors.ui, 'Fixture', confirmed: true);
    await h.grants.setEnabled(h.actors.ui, true);
    router = McpRouter(
      operations: operations,
      grants: h.grants,
      schemas: ToolSchemas(registry),
      release: 'fixture',
    );
    session = router.session(
      h.actors.mcp(clientId: grant.clientId, grantVersion: 1),
    );
  });
  tearDown(() => h.dispose());
  Future<void> initialize({Map<String, dynamic>? metadata}) async {
    final result = await session.handle(
      rpc(0, 'initialize', {
        'protocolVersion': '2025-11-25',
        'capabilities': {},
        'clientInfo': {'name': 'fixture', 'version': '1'},
        if (metadata != null) '_meta': metadata,
      }),
    );
    expect((result!['result'] as Map)['protocolVersion'], '2025-11-25');
    await session.handle({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
  }

  test(
    'runtime registry is byte-identical to the authoritative twenty-one tools',
    () {
      expect(
        File('assets/mcp/tools.json').readAsBytesSync(),
        File('specs/003-ssh-mcp/contracts/mcp-tools.json').readAsBytesSync(),
      );
      expect(
        router.schemas.tools.map((t) => t['name']).toSet(),
        ToolSchemas.names,
      );
    },
  );
  test(
    'connection output schema accepts only bounded optional reconnect status',
    () {
      for (final attempt in [null, 1, 8]) {
        router.schemas.output('connections.get', {
          'ok': true,
          'value': {
            'state': 'disconnected',
            if (attempt != null) 'reconnectAttempt': attempt,
          },
          'meta': {'dataRevision': 1, 'ownerEpoch': h.actors.ownerEpoch},
        });
      }
      for (final attempt in [0, 9, '1']) {
        expect(
          () => router.schemas.output('connections.get', {
            'ok': true,
            'value': {'state': 'disconnected', 'reconnectAttempt': attempt},
            'meta': {'dataRevision': 1, 'ownerEpoch': h.actors.ownerEpoch},
          }),
          throwsA(isA<SchemaFailure>()),
        );
      }
    },
  );
  test(
    'tools require initialization, and discovery exposes only the allowlist',
    () async {
      final denied = await session.handle(rpc(1, 'tools/list', {}));
      expect((denied!['error'] as Map)['code'], -32002);
      await initialize();
      final result = await session.handle(rpc(2, 'tools/list', {}));
      expect(((result!['result'] as Map)['tools'] as List).length, 27);
      expect(operations.calls, isEmpty);
    },
  );
  test(
    'request metadata is accepted without changing tool arguments',
    () async {
      await initialize(metadata: {'vendor/example': true});
      var id = 1;
      for (final token in [0, 'catalog', -9007199254740991, 9007199254740991]) {
        for (final method in ['tools/list', 'ping', 'tools/call']) {
          final params = <String, dynamic>{
            '_meta': {
              'progressToken': token,
              'vendor/example': {
                'actor': 'synthetic-untrusted',
                'nested': [null],
              },
            },
            if (method == 'tools/call') ...{
              'name': 'profiles.list',
              'arguments': <String, dynamic>{},
            },
          };
          final response = await session.handle(rpc(id++, method, params));
          expect(response!.containsKey('result'), isTrue, reason: '$response');
          expect(params.containsKey('_meta'), isTrue);
          expect(response.toString(), isNot(contains('synthetic-untrusted')));
        }
      }
      expect(operations.calls.length, 4);
      expect(
        operations.calls.every((c) => c.namedArguments[#limit] == 50),
        isTrue,
      );
    },
  );
  test(
    'empty and vendor-only metadata are valid on catalogue requests',
    () async {
      await initialize(metadata: {});
      var id = 1;
      for (final metadata in <Map<String, dynamic>>[
        {},
        {'vendor/example': null},
      ]) {
        final result = await session.handle(
          rpc(id++, 'tools/list', {'_meta': metadata}),
        );
        expect(((result!['result'] as Map)['tools'] as List).length, 27);
      }
      for (final params in [
        {'cursor': 'unknown'},
        {'cursor': null},
        {'unknown': true},
      ]) {
        final result = await session.handle(rpc(id++, 'tools/list', params));
        expect((result!['error'] as Map)['code'], -32602);
      }
    },
  );
  test('invalid initialization metadata leaves handshake available', () async {
    final invalid = await session.handle(
      rpc(1, 'initialize', {
        'protocolVersion': '2025-11-25',
        'capabilities': {},
        'clientInfo': {'name': 'fixture', 'version': '1'},
        '_meta': null,
      }),
    );
    expect((invalid!['error'] as Map)['code'], -32602);
    await initialize();
  });
  test('malformed metadata is rejected before tool dispatch', () async {
    await initialize();
    var id = 1;
    for (final metadata in <Object?>[
      null,
      true,
      [],
      'invalid',
      {'progressToken': null},
      {'progressToken': true},
      {'progressToken': 1.5},
      {'progressToken': []},
      {'progressToken': 9007199254740992},
      {'progressToken': -9223372036854775808},
    ]) {
      for (final method in ['tools/list', 'ping', 'tools/call']) {
        final response = await session.handle(
          rpc(id++, method, {
            '_meta': metadata,
            if (method == 'tools/call') ...{
              'name': 'profiles.list',
              'arguments': <String, dynamic>{},
            },
          }),
        );
        expect((response!['error'] as Map)['code'], -32602);
      }
    }
    expect(operations.calls, isEmpty);
  });
  test(
    'metadata grants no authority and does not relax argument validation',
    () async {
      await initialize();
      final invalid = await session.handle(
        rpc(1, 'tools/call', {
          '_meta': {'actor': 'ui'},
          'name': 'profiles.list',
          'arguments': {'_meta': {}},
        }),
      );
      expect((invalid!['error'] as Map)['code'], -32602);
      await h.grants.setEnabled(h.actors.ui, false);
      final denied = await session.handle(
        rpc(2, 'tools/list', {
          '_meta': {'actor': 'ui', 'progressToken': 0},
        }),
      );
      expect((denied!['error'] as Map)['code'], -32001);
      expect(operations.calls, isEmpty);
    },
  );
  for (final name in ToolSchemas.names.where(
    (name) => !name.startsWith('console.') && !name.startsWith('software.'),
  )) {
    test(
      '$name validates, invokes the typed method once and returns structured domain failure',
      () async {
        await initialize();
        final response = await session.handle(
          rpc(1, 'tools/call', {'name': name, 'arguments': arguments(name)}),
        );
        expect(
          response!.containsKey('error'),
          isFalse,
          reason: response.toString(),
        );
        final result = response['result'] as Map,
            structured = result['structuredContent'] as Map;
        expect(result['isError'], isTrue);
        expect(structured['ok'], isFalse);
        expect((structured['error'] as Map)['code'], 'PROFILE_NOT_FOUND');
        expect(
          jsonDecode(
            ((result['content'] as List).single as Map)['text'] as String,
          ),
          structured,
        );
        expect(operations.calls.length, 1);
      },
    );
    test(
      '$name rejects unknown arguments before invoking any operation',
      () async {
        await initialize();
        final response = await session.handle(
          rpc(1, 'tools/call', {
            'name': name,
            'arguments': {
              ...arguments(name),
              'unexpected': 'synthetic-secret-never-echo',
            },
          }),
        );
        expect((response!['error'] as Map)['code'], -32602);
        expect(operations.calls, isEmpty);
        expect(
          response.toString(),
          isNot(contains('synthetic-secret-never-echo')),
        );
      },
    );
  }
  test('invented deletion and generic execution never dispatch', () async {
    await initialize();
    for (final name in ['profiles.delete', 'execute', 'token.rotate']) {
      final response = await session.handle(
        rpc(name, 'tools/call', {
          'name': name,
          'arguments': <String, dynamic>{},
        }),
      );
      expect((response!['error'] as Map)['code'], -32602);
    }
    expect(operations.calls, isEmpty);
  });
  test(
    'null fractional boolean and duplicate IDs have no second effect',
    () async {
      await initialize();
      for (final id in [null, 1.5, true]) {
        final result = await session.handle(
          rpc(id, 'tools/call', {
            'name': 'profiles.list',
            'arguments': <String, dynamic>{},
          }),
        );
        expect((result!['error'] as Map)['code'], -32600);
      }
      await session.handle(
        rpc(1, 'tools/call', {
          'name': 'profiles.list',
          'arguments': <String, dynamic>{},
        }),
      );
      final duplicate = await session.handle(
        rpc(1.0, 'tools/call', {
          'name': 'profiles.list',
          'arguments': <String, dynamic>{},
        }),
      );
      expect((duplicate!['error'] as Map)['code'], -32600);
      await session.handle(
        rpc('1', 'tools/call', {
          'name': 'profiles.list',
          'arguments': <String, dynamic>{},
        }),
      );
      expect(operations.calls.length, 2);
    },
  );
  test('cancel notification belongs to its active channel request', () async {
    await initialize();
    operations.hold = Completer<void>();
    final pending = session.handle(
      rpc(1, 'tools/call', {
        'name': 'profiles.list',
        'arguments': <String, dynamic>{},
      }),
    );
    await featureTurns();
    await session.handle({
      'jsonrpc': '2.0',
      'method': 'notifications/cancelled',
      'params': {'requestId': 1},
    });
    operations.hold!.complete();
    final response = await pending;
    expect((response!['error'] as Map)['code'], -32800);
  });
  test('request limit closes before dispatching request 10001', () async {
    await initialize();
    for (var i = 1; i < 10000; i++) {
      expect(
        (await session.handle(rpc(i, 'ping', {})))!.containsKey('result'),
        isTrue,
      );
    }
    final result = await session.handle(rpc(10000, 'ping', {}));
    expect((result!['error'] as Map)['code'], -32000);
    expect(session.closed, isTrue);
    expect(operations.calls, isEmpty);
  });
}
