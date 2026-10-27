import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_mcp/src/server.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:test/test.dart';

final class Gateway implements McpGateway {
  final calls = <Completer<Map<String, Object?>>>[];
  final cancelled = <int>[];
  bool closed = false;
  @override
  McpInvocation start(String method, Map<String, Object?> params) {
    final index = calls.length;
    final completer = Completer<Map<String, Object?>>();
    calls.add(completer);
    return McpInvocation(completer.future, () async {
      cancelled.add(index);
    });
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

List<int> request(
  String method, {
  Object? id = 1,
  Map<String, Object?>? params,
}) => utf8.encode(
  '${jsonEncode({'jsonrpc': '2.0', if (id != null) 'id': id, 'method': method, if (params != null) 'params': params})}\n',
);

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late StreamController<List<int>> input;
  late Gateway gateway;
  late List<Map<String, Object?>> output;
  late List<String> diagnostics;
  late Future<int> running;
  McpServer start({
    Future<void> Function(List<int>)? write,
    Duration? deadline,
    Duration? initializationDeadline,
  }) {
    final server = McpServer.forTesting(
      input: input.stream,
      gateway: gateway,
      write:
          write ??
          (bytes) async {
            output.add(jsonDecode(utf8.decode(bytes)) as Map<String, Object?>);
          },
      diagnostic: diagnostics.add,
      initializationTimeout:
          initializationDeadline ?? const Duration(seconds: 5),
      writeTimeout: deadline ?? const Duration(seconds: 5),
      callTimeout: deadline ?? const Duration(seconds: 5),
    );
    running = server.run();
    return server;
  }

  Future<void> initialize() async {
    input.add(
      request(
        'initialize',
        params: {
          'protocolVersion': '2025-11-25',
          'capabilities': {},
          'clientInfo': {'name': 'test', 'version': '1'},
        },
      ),
    );
    input.add(request('notifications/initialized', id: null));
    await settle();
  }

  setUp(() {
    input = StreamController<List<int>>();
    gateway = Gateway();
    output = [];
    diagnostics = [];
  });
  tearDown(() async {
    if (!input.isClosed) await input.close();
    await running;
  });

  test(
    'chunked and consecutive frames preserve IDs and serialized output',
    () async {
      start();
      await initialize();
      final bytes = request('ping', id: 'e\u0301');
      for (final byte in bytes) {
        input.add([byte]);
      }
      input.add([...request('ping', id: 2), ...request('ping', id: 3)]);
      await settle();
      expect(output.map((m) => m['id']), [1, 'e\u0301', 2, 3]);
      expect(gateway.calls, isEmpty);
      await input.close();
      expect(await running, 0);
      expect(gateway.closed, isTrue);
    },
  );

  test(
    'initialize result flushes before tool dispatch from same chunk',
    () async {
      final release = Completer<void>();
      start(
        write: (bytes) async {
          output.add(jsonDecode(utf8.decode(bytes)) as Map<String, Object?>);
          if (output.length == 1) await release.future;
        },
      );
      input.add([
        ...request(
          'initialize',
          params: {
            'protocolVersion': '2025-11-25',
            'capabilities': {},
            'clientInfo': {'name': 'test', 'version': '1'},
          },
        ),
        ...request('notifications/initialized', id: null),
        ...request('tools/list', id: 2),
      ]);
      await settle();
      expect(gateway.calls, isEmpty);
      release.complete();
      await settle();
      expect(gateway.calls, hasLength(1));
      gateway.calls.single.complete({'tools': []});
      await settle();
      expect(output.last['id'], 2);
    },
  );

  test('pending IDs,16request limit and reused completed IDs', () async {
    final server = start();
    await initialize();
    for (var i = 0; i < 16; i++) {
      input.add(request('tools/call', id: i, params: {'name': 'test'}));
    }
    input.add(request('tools/call', id: 0));
    input.add(request('tools/call', id: 17));
    input.add(request('ping', id: 18));
    await settle();
    expect(gateway.calls, hasLength(16));
    expect(server.pendingRequests, 16);
    expect((output[1]['error'] as Map)['code'], -32600);
    final overload =
        ((output[2]['result'] as Map)['structuredContent'] as Map)['error']
            as Map;
    expect(overload['code'], 'RESOURCE_LIMIT');
    expect(output[3]['error'], {'code': -32000, 'message': 'RESOURCE_LIMIT'});
    gateway.calls.first.complete({'content': []});
    await settle();
    input.add(request('tools/list', id: 0));
    await settle();
    expect(gateway.calls, hasLength(17));
  });

  test(
    'wire cancellation drops interest and late result cannot claim reused ID',
    () async {
      start();
      await initialize();
      input.add(request('tools/call', id: 'same'));
      await settle();
      input.add(
        request(
          'notifications/cancelled',
          id: null,
          params: {'requestId': 'same', 'reason': 'private-marker'},
        ),
      );
      input.add(request('tools/list', id: 'same'));
      await settle();
      expect(gateway.cancelled, [0]);
      expect(gateway.calls, hasLength(2));
      gateway.calls[0].complete({'private-marker': true});
      gateway.calls[1].complete({'tools': []});
      await settle();
      expect(output, hasLength(2));
      expect((output.last['result'] as Map)['tools'], isEmpty);
      expect(jsonEncode(output), isNot(contains('private-marker')));
    },
  );

  test(
    'malformed syntax recovers but invalid UTF8 and oversized frames close',
    () async {
      start();
      input.add(utf8.encode('{private-marker\n'));
      input.add(request('ping'));
      await settle();
      expect(output, hasLength(2));
      expect((output.first['error'] as Map)['code'], -32700);
      input.add([255, 10]);
      await settle();
      expect(await running, 2);
      expect(gateway.closed, isTrue);
      expect(jsonEncode(output), isNot(contains('private-marker')));
    },
  );

  test(
    'oversized unterminated input has bounded storage and terminates',
    () async {
      final server = start();
      input.add(List.filled(mcpMaxRequestBytes + 1, 97));
      await settle();
      expect(await running, 2);
      expect(server.bufferedBytes, lessThanOrEqualTo(mcpMaxRequestBytes));
      expect((output.single['error'] as Map)['code'], -32700);
    },
  );

  test(
    'EOF with partial frame rejects input; normal EOF drops pending interest',
    () async {
      start();
      await initialize();
      input.add(request('tools/call', id: 2));
      await settle();
      await input.close();
      expect(await running, 0);
      expect(gateway.cancelled, [0]);
      gateway.calls.single.complete({'late': true});
      await settle();
      expect(output, hasLength(1));
    },
  );

  test('EOF partial frame returns safe parse error and exit2', () async {
    start();
    input.add(utf8.encode('{private-marker'));
    await input.close();
    expect(await running, 2);
    expect((output.single['error'] as Map)['code'], -32700);
    expect(jsonEncode(output), isNot(contains('private-marker')));
  });

  test('initialization and blocked-write deadlines close without leaked diagnostics', () async {
    start(initializationDeadline: const Duration(milliseconds: 30));
    expect(await running, 2);
    expect(diagnostics, ['INITIALIZATION_TIMEOUT']);
  });

  test('blocked output times out and prevents any later dispatch', () async {
    final blocked = Completer<void>();
    start(
      deadline: const Duration(milliseconds: 100),
      write: (_) => blocked.future,
    );
    input.add(request('ping'));
    await settle();
    expect(await running, 2);
    expect(diagnostics, contains('WRITE_FAILED'));
    blocked.complete();
  });

  test('call timeout returns fixed failure and drops only interest', () async {
    start(deadline: const Duration(milliseconds: 100));
    await initialize();
    input.add(request('tools/call', id: 2));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(
      (((output.last['result'] as Map)['structuredContent'] as Map)['error']
          as Map)['code'],
      'TIMEOUT',
    );
    expect(gateway.cancelled, [0]);
    gateway.calls.single.completeError(StateError('private-marker'));
    await settle();
    expect(diagnostics.join(), isNot(contains('private-marker')));
  });

  test(
    'bad gateway responses and failures produce safe errors and release IDs',
    () async {
      final server = start();
      await initialize();
      input.add(request('tools/list', id: 2));
      await settle();
      gateway.calls[0].complete({'value': double.nan});
      await settle();
      expect((output.last['error'] as Map)['code'], -32603);
      expect(server.pendingRequests, 0);
      input.add(request('tools/list', id: 2));
      await settle();
      gateway.calls[1].completeError(StateError('private-marker'));
      await settle();
      expect((output.last['error'] as Map)['code'], -32603);
      expect(jsonEncode(output), isNot(contains('private-marker')));
    },
  );

  test(
    'cancel acknowledgement applies backpressure and timeout stays bounded',
    () async {
      final ack = Completer<void>();
      final custom = _SlowCancelGateway(ack);
      final server = McpServer.forTesting(
        input: input.stream,
        gateway: custom,
        write: (bytes) async {
          output.add(jsonDecode(utf8.decode(bytes)) as Map<String, Object?>);
        },
        initializationTimeout: const Duration(seconds: 5),
        writeTimeout: const Duration(milliseconds: 100),
        callTimeout: const Duration(seconds: 5),
        diagnostic: diagnostics.add,
      );
      running = server.run();
      await initialize();
      input.add(request('tools/list', id: 2));
      await settle();
      input.add(
        request('notifications/cancelled', id: null, params: {'requestId': 2}),
      );
      input.add(request('tools/list', id: 3));
      await settle();
      expect(custom.starts, 1);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(custom.starts, 2);
      expect(diagnostics, contains('CANCEL_FAILED'));
      ack.complete();
    },
  );
}

final class _SlowCancelGateway implements McpGateway {
  _SlowCancelGateway(this.ack);
  final Completer<void> ack;
  int starts = 0;
  @override
  McpInvocation start(String method, Map<String, Object?> params) {
    starts++;
    return McpInvocation(
      Completer<Map<String, Object?>>().future,
      () => ack.future,
    );
  }

  @override
  Future<void> close() async {}
}
