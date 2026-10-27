import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('actual stdio subprocess negotiates, denies unconfigured calls and closes cleanly', () async {
    final child = await Process.start(Platform.resolvedExecutable, [
      File('test/support/stdio_child.dart').absolute.path,
    ]);
    final errors = child.stderr.transform(utf8.decoder).join();
    final responses = StreamIterator(
      child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    Future<Map<String, Object?>> next() async {
      expect(
        await responses.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      return jsonDecode(responses.current) as Map<String, Object?>;
    }

    void send(String method, {Object? id = 1, Map<String, Object?>? params}) {
      child.stdin.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          if (id != null) 'id': id,
          'method': method,
          if (params != null) 'params': params,
        }),
      );
    }

    try {
      send(
        'initialize',
        params: {
          'protocolVersion': '2025-06-18',
          'capabilities': {},
          'clientInfo': {'name': 'os-pipe-test', 'version': '1'},
        },
      );
      expect(
        ((await next())['result'] as Map)['protocolVersion'],
        '2025-06-18',
      );
      send('notifications/initialized', id: null);
      send('tools/list', id: 'list');
      expect((await next())['result'], {'tools': []});
      send(
        'tools/call',
        id: 'deny',
        params: {'name': 'serverdeck_servers_list', 'arguments': {}},
      );
      final denied = (await next())['result'] as Map;
      expect(denied['isError'], isTrue);
      expect(
        ((denied['structuredContent'] as Map)['error'] as Map)['code'],
        'FORBIDDEN',
      );
      send('ping', id: 'e\u0301');
      expect((await next())['id'], 'e\u0301');
      await child.stdin.close();
      expect(await child.exitCode.timeout(const Duration(seconds: 10)), 0);
      expect(await errors, isEmpty);
      expect(await responses.moveNext(), isFalse);
    } finally {
      await responses.cancel();
      // The process belongs exclusively to this test; cleanup never targets UI/locald.
      child.kill();
    }
  });
}
