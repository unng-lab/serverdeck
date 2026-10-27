import 'dart:convert';

import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:test/test.dart';

void main() {
  McpInbound parse(String input) => McpInbound.decode(utf8.encode(input));

  test('valid non-object JSON is Invalid Request with null correlation', () {
    for (final raw in ['[]', '[1,2]', '42', 'null', '"text"', 'true']) {
      try {
        parse(raw);
        fail('Expected invalid request');
      } on McpProtocolException catch (error) {
        expect(error.code, -32600, reason: raw);
        expect(error.response(null), {
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32600, 'message': 'Invalid request'},
        });
      }
    }
  });

  test(
    'syntax, UTF8, depth and size failures stay Parse error without input',
    () {
      final documents = <List<int>>[
        utf8.encode('{"private-marker":'),
        utf8.encode('[1,'),
        utf8.encode('${'[' * 18}0${']' * 18}'),
        [0xff],
        List.filled(256 * 1024 + 1, 32),
      ];
      for (final bytes in documents) {
        try {
          McpInbound.decode(bytes);
          fail('Expected parse error');
        } on McpProtocolException catch (error) {
          expect(error.code, -32700);
          expect(error.response(null)['id'], isNull);
          expect(error.toString(), isNot(contains('private-marker')));
        }
      }
    },
  );

  test('external wire preserves exact Unicode IDs and observed text', () {
    const id = 'Cafe\u0301';
    final response = mcpSuccess(id, {'text': 'line\nCafe\u0301', 'cpu': 1.25});
    final bytes = encodeMcpMessage(response);
    final decoded = jsonDecode(utf8.decode(bytes)) as Map;
    expect(decoded['id'], id);
    expect((decoded['result'] as Map)['text'], 'line\nCafe\u0301');
    expect((decoded['result'] as Map)['cpu'], 1.25);
    expect(bytes.contains(10), isFalse);
    for (final invalid in <Object>[double.nan, double.infinity, '\ud800']) {
      expect(
        () => encodeMcpMessage(mcpSuccess(id, {'value': invalid})),
        throwsA(isA<McpProtocolException>()),
      );
    }
    expect(
      () => encodeMcpMessage(response, maxBytes: 8),
      throwsA(isA<McpProtocolException>()),
    );
  });

  test('JSON-RPC preserves string or safe integer correlation IDs', () {
    for (final id in <Object>['a', '😀' * 100, 0, -1, 9007199254740991]) {
      final request = parse(
        jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': 'ping'}),
      );
      expect(request.id, id);
      expect(request.isNotification, isFalse);
      expect(request.params, isEmpty);
    }
    expect(
      parse('{"jsonrpc":"2.0","method":"notifications/initialized"}')
          .isNotification,
      isTrue,
    );
    expect(validMcpId('😀' * 101), isFalse);
  });

  test(
    'invalid JSON, duplicate keys, UTF8, framing size and ID types fail safely',
    () {
      for (final raw in [
        '[]',
        '{',
        '{"jsonrpc":"2.0","jsonrpc":"2.0","method":"ping"}',
        '{"jsonrpc":"2.0","id":null,"method":"ping"}',
        '{"jsonrpc":"2.0","id":9007199254740992,"method":"ping"}',
        '{"jsonrpc":"2.0","id":1.0,"method":"ping"}',
        '{"jsonrpc":"1.0","id":1,"method":"ping"}',
        '{"jsonrpc":"2.0","id":1,"method":"ping","params":[]}',
        '{"jsonrpc":"2.0","id":1,"method":"ping","extra":"private-marker"}',
      ]) {
        expect(() => parse(raw), throwsA(isA<McpProtocolException>()));
      }
      expect(
        () => McpInbound.decode([0xff]),
        throwsA(isA<McpProtocolException>()),
      );
      expect(
        () => McpInbound.decode(List.filled(256 * 1024 + 1, 32)),
        throwsA(isA<McpProtocolException>()),
      );
    },
  );

  test('wire errors and result correlation never include raw input', () {
    try {
      parse('{"private-marker":');
      fail('Expected parse failure');
    } on McpProtocolException catch (error) {
      expect(error.code, -32700);
      expect(error.toString(), isNot(contains('private-marker')));
      expect(error.response(null), {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'Parse error'},
      });
    }
    final result = mcpSuccess('request-1', {'tools': <Object>[]});
    expect(result['id'], 'request-1');
    expect(result['result'], {'tools': <Object>[]});
  });
}
