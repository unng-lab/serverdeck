import 'package:serverdeck_mcp/src/local_gateway.dart';
import 'package:serverdeck_mcp/src/server.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

void main() {
  test(
    'unconfigured catalog and default arguments are explicit fixed results',
    () async {
      final gateway = LocalMcpGateway.unconfigured();
      final fixed = gateway.start('tools/list', {});
      expect(identical(fixed.cancelInterest(), fixed.cancelInterest()), true);
      expect(fixed.beforePublish, isNotNull);
      expect(fixed.validatePublication, isNotNull);
      expect(fixed.afterPublish, isNotNull);
      expect(
        await gateway.start('tools/list', {
          '_meta': {'progressToken': 'e\u0301😀'},
        }).result,
        {'tools': <Object?>[]},
      );
      final result = await gateway.start('tools/call', {
        'name': 'state_get',
        '_meta': <String, Object?>{},
      }).result;
      expect((result['structuredContent'] as Map)['error'], {
        'code': 'FORBIDDEN',
        'boundary': 'local',
        'retry': 'none',
      });
      await gateway.close();
      expect(identical(gateway.close(), gateway.close()), true);
      expect(
        () => gateway.start('tools/list', {}),
        throwsA(
          isA<McpGatewayFailure>().having(
            (e) => e.code,
            'code',
            ErrorCode.serviceUnavailable,
          ),
        ),
      );
    },
  );
  for (final entry in <(String, Map<String, Object?>)>[
    ('tools/list', {'cursor': ''}),
    ('tools/list', {'_meta': 1}),
    ('tools/list', {'unknown': true}),
    ('tools/call', {}),
    ('tools/call', {'name': ''}),
    ('tools/call', {'name': 'a', 'arguments': null}),
    ('tools/call', {'name': 'a', 'arguments': []}),
    ('tools/call', {'name': 'a', '_meta': false}),
    ('tools/call', {'name': 'a', 'task': {}}),
    ('tools/call', {'name': 'a', 'extra': 'OWNED_SENTINEL'}),
  ]) {
    test(
      'validates generic params before unconfigured result: $entry',
      () async {
        final gateway = LocalMcpGateway.unconfigured();
        addTearDown(gateway.close);
        expect(
          () => gateway.start(entry.$1, entry.$2),
          throwsA(
            isA<McpProtocolException>().having((e) => e.code, 'code', -32602),
          ),
        );
      },
    );
  }
  test('unknown method is fixed method-not-found', () async {
    final gateway = LocalMcpGateway.unconfigured();
    addTearDown(gateway.close);
    expect(
      () => gateway.start('owner.shell', {}),
      throwsA(
        isA<McpProtocolException>().having((e) => e.code, 'code', -32601),
      ),
    );
  });
  test(
    'name bound counts Unicode scalars and preserves valid metadata',
    () async {
      final gateway = LocalMcpGateway.unconfigured();
      addTearDown(gateway.close);
      final result = await gateway.start('tools/call', {
        'name': '😀' * 256,
        'arguments': <String, Object?>{},
        '_meta': {'untrusted': 'e\u0301😀', 'progressToken': 17},
      }).result;
      expect(result['isError'], true);
      expect(
        () => gateway.start('tools/call', {'name': '😀' * 257}),
        throwsA(
          isA<McpProtocolException>().having((e) => e.code, 'code', -32602),
        ),
      );
    },
  );
  test(
    'bounded metadata and cyclic arguments fail before any admission',
    () async {
      final gateway = LocalMcpGateway.unconfigured();
      addTearDown(gateway.close);
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      for (final params in [
        <String, Object?>{'name': 'fixture', 'arguments': cyclic},
        <String, Object?>{
          'name': 'fixture',
          '_meta': {'large': 'x' * (256 * 1024)},
        },
        <String, Object?>{
          'name': 'fixture',
          'arguments': {'bad': '\uD800'},
        },
      ]) {
        expect(
          () => gateway.start('tools/call', params),
          throwsA(
            isA<McpProtocolException>().having((e) => e.code, 'code', -32602),
          ),
        );
      }
    },
  );
}
