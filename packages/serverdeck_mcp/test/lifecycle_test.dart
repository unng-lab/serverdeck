import 'dart:convert';

import 'package:serverdeck_mcp/src/lifecycle.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:test/test.dart';

McpInbound message(
  String method, {
  Object? id = 1,
  Map<String, Object?>? params,
}) => McpInbound.decode(
  utf8.encode(
    jsonEncode({
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'method': method,
      if (params != null) 'params': params,
    }),
  ),
);

Map<String, Object?> initParams(String version) => {
  'protocolVersion': version,
  'capabilities': <String, Object?>{},
  'clientInfo': {'name': 'independent-test', 'version': '1.0'},
};

void main() {
  test(
    'negotiate both versions, initialize result then notification gates tools',
    () {
      for (final version in ['2025-11-25', '2025-06-18', 'future-version']) {
        final lifecycle = McpLifecycle();
        expect(lifecycle.accept(message('ping')), isA<McpBuiltin>());
        expect(
          () => lifecycle.accept(message('tools/list')),
          throwsA(
            isA<McpProtocolException>().having((e) => e.code, 'code', -32600),
          ),
        );
        final init = lifecycle.accept(
          message('initialize', params: initParams(version)),
        ) as McpBuiltin;
        expect(
          init.result['protocolVersion'],
          version == 'future-version' ? '2025-11-25' : version,
        );
        expect(init.result['serverInfo'], {
          'name': 'serverdeck',
          'version': '0.1.0',
        });
        expect(init.result['capabilities'], {
          'tools': {'listChanged': false},
        });
        expect(lifecycle.phase, McpPhase.awaitingInitialized);
        expect(
          () => lifecycle.accept(message('tools/call')),
          throwsA(isA<McpProtocolException>()),
        );
        expect(
          lifecycle.accept(message('notifications/initialized', id: null)),
          isA<McpIgnored>(),
        );
        expect(lifecycle.phase, McpPhase.ready);
        expect(lifecycle.accept(message('tools/list')), isA<McpForward>());
        expect(
          lifecycle.accept(
            message('tools/call', params: {'name': 'serverdeck_profiles_list'}),
          ),
          isA<McpForward>(),
        );
      }
    },
  );

  test(
    'malformed initialization does not advance or retain private client text',
    () {
      final lifecycle = McpLifecycle();
      for (final params in <Map<String, Object?>>[
        {},
        {...initParams('2025-11-25'), 'capabilities': []},
        {
          ...initParams('2025-11-25'),
          'clientInfo': {'name': 'private-marker'},
        },
        {...initParams('2025-11-25'), 'protocolVersion': 1},
      ]) {
        expect(
          () => lifecycle.accept(message('initialize', params: params)),
          throwsA(
            isA<McpProtocolException>()
                .having((e) => e.code, 'code', -32602)
                .having(
                  (e) => e.toString(),
                  'privacy',
                  isNot(contains('private-marker')),
                ),
          ),
        );
        expect(lifecycle.phase, McpPhase.fresh);
      }
      final init = lifecycle.accept(
        message(
          'initialize',
          params: {
            ...initParams('2025-11-25'),
            '_meta': {'optional': true},
            'clientInfo': {'name': 'test', 'version': '1', 'title': 'optional'},
          },
        ),
      );
      expect(init, isA<McpBuiltin>());
    },
  );

  test('notifications never start requests or mutations', () {
    final lifecycle = McpLifecycle();
    expect(
      lifecycle.accept(message('notifications/initialized', id: null)),
      isA<McpIgnored>(),
    );
    expect(lifecycle.phase, McpPhase.fresh);
    expect(
      lifecycle.accept(
        message('initialize', id: null, params: initParams('2025-11-25')),
      ),
      isA<McpIgnored>(),
    );
    expect(lifecycle.phase, McpPhase.fresh);
    lifecycle.accept(message('initialize', params: initParams('2025-11-25')));
    lifecycle.accept(message('notifications/initialized', id: null));
    for (final method in [
      'tools/call',
      'tools/list',
      'initialize',
      'unknown',
    ]) {
      expect(lifecycle.accept(message(method, id: null)), isA<McpIgnored>());
    }
  });

  test('cancel contains only exact wire identity and is not a job cancel', () {
    final lifecycle = McpLifecycle();
    expect(
      lifecycle.accept(
        message('notifications/cancelled', id: null, params: {'requestId': 7}),
      ),
      isA<McpIgnored>(),
    );
    lifecycle.accept(message('initialize', params: initParams('2025-11-25')));
    lifecycle.accept(message('notifications/initialized', id: null));
    final cancel = lifecycle.accept(
      message(
        'notifications/cancelled',
        id: null,
        params: {'requestId': 'e\u0301', 'reason': 'private-marker'},
      ),
    ) as McpCancelInterest;
    expect(cancel.requestId, 'e\u0301');
    for (final invalid in [null, '', 1.5, true, 9007199254740992]) {
      expect(
        lifecycle.accept(
          message(
            'notifications/cancelled',
            id: null,
            params: {'requestId': invalid},
          ),
        ),
        isA<McpIgnored>(),
      );
    }
  });

  test(
    'repeat initialize and unsupported ready methods fail with fixed codes',
    () {
      final lifecycle = McpLifecycle();
      lifecycle.accept(message('initialize', params: initParams('2025-11-25')));
      expect(
        () => lifecycle.accept(
          message('initialize', params: initParams('2025-11-25')),
        ),
        throwsA(
          isA<McpProtocolException>().having((e) => e.code, 'code', -32600),
        ),
      );
      lifecycle.accept(message('notifications/initialized', id: null));
      for (final method in [
        'resources/list',
        'prompts/list',
        'sampling/createMessage',
        'notifications/initialized',
      ]) {
        expect(
          () => lifecycle.accept(message(method)),
          throwsA(
            isA<McpProtocolException>().having((e) => e.code, 'code', -32601),
          ),
        );
      }
    },
  );

  test('initialization deadline closes only unfinished handshake, EOF always closes', () {
    final lifecycle = McpLifecycle();
    lifecycle.expireInitialization();
    expect(lifecycle.phase, McpPhase.closed);
    expect(
      () => lifecycle.accept(message('ping')),
      throwsA(isA<McpProtocolException>()),
    );
    expect(
      lifecycle.accept(message('notifications/initialized', id: null)),
      isA<McpIgnored>(),
    );
    final ready = McpLifecycle();
    ready.accept(message('initialize', params: initParams('2025-11-25')));
    ready.accept(message('notifications/initialized', id: null));
    ready.expireInitialization();
    expect(ready.phase, McpPhase.ready);
    ready.close();
    expect(ready.phase, McpPhase.closed);
  });
}
