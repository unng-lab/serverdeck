import 'dart:convert';

import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:test/test.dart';

const id = '12345678-1234-4234-8234-123456789abc';
void main() {
  test('tool result reserves depth for both transport wrappers', () {
    var data = <String, Object?>{'v': 0};
    var accepted = 0;
    for (var i = 0; i < 14; i++) {
      final current = data;
      if (i <= 11) {
        final result = McpToolResult.success(current);
        final reply = McpInvokeReply.done(result);
        encodeMcpMessage({
          'v': 1,
          'id': id,
          'generation': id,
          'result': reply.toJson(),
        });
        encodeMcpMessage(mcpSuccess(1, result.toJson()));
        accepted++;
      } else {
        expect(() => McpToolResult.success(current), throwsFormatException);
      }
      data = {'v': current};
    }
    expect(accepted, 12);
  });
  test(
    'all24 tool argument contracts admit their examples and close extra fields',
    () {
      final body = <String, Object?>{
        'format': 1,
        'environment': 'ubuntu24.04-amd64-systemd',
        'parameters': <String, Object?>{},
        'steps': <Object?>[],
      };
      final target = <String, Object?>{'serverId': id};
      final job = <String, Object?>{'jobId': id};
      final plan = <String, Object?>{'planId': id};
      final examples = <String, Map<String, Object?>>{
        'servers_list': {},
        'server_get': target,
        'server_connect': target,
        'server_disconnect': target,
        'state_get': target,
        'configuration_get': {...target, 'resourceId': 'system.motd'},
        'logs_read': target,
        'profiles_list': {},
        'profiles_get': {'profileId': id},
        'profiles_create': {'requestId': id, 'name': 'Example', 'body': body},
        'profiles_update': {
          'requestId': id,
          'profileId': id,
          'expectedRevision': 1,
          'body': body,
        },
        'profiles_compare': {
          'profileId': id,
          'fromRevision': 1,
          'toRevision': 2,
        },
        'profiles_validate': {'body': body},
        'profiles_archive': {
          'requestId': id,
          'profileId': id,
          'expectedRevision': 1,
        },
        'recipes_list': target,
        'plan_create': {
          'requestId': id,
          ...target,
          'profileId': id,
          'revision': 1,
          'parameters': <String, Object?>{},
        },
        'plans_get': plan,
        'approval_request': {'requestId': id, ...plan},
        'apply': {'requestId': id, ...plan},
        'jobs_list': {},
        'jobs_get': job,
        'jobs_events': job,
        'jobs_cancel': {'requestId': id, ...job},
        'jobs_reconcile': {'requestId': id, ...job},
      };
      expect(
        examples.keys.map((n) => 'serverdeck_$n').toSet(),
        mcpTools.map((t) => t.name).toSet(),
      );
      for (final entry in examples.entries) {
        final tool = mcpTool('serverdeck_${entry.key}')!;
        validateMcpArguments(tool, entry.value);
        expect(
          () => validateMcpArguments(tool, {...entry.value, 'unknown': true}),
          throwsFormatException,
          reason: tool.name,
        );
        for (final required in tool.inputSchema['required'] as List) {
          final missing = Map<String, Object?>.of(entry.value)
            ..remove(required);
          expect(
            () => validateMcpArguments(tool, missing),
            throwsFormatException,
            reason: '${tool.name}:$required',
          );
        }
      }
    },
  );
  test(
    'complete catalog survives the actual bounded internal and external wire',
    () {
      final catalog = McpInvokeReply.catalog(mcpTools).toJson();
      expect(McpInvokeReply.fromJson(catalog).toJson(), catalog);
      final message = encodeMcpMessage(mcpSuccess(1, catalog));
      expect(jsonDecode(utf8.decode(message))['result'], catalog);
    },
  );
  test(
    'four closed invocation variants and immutable original JSON snapshot',
    () {
      final args = <String, Object?>{
        'text': 'e\u0301',
        'limit': 1.0,
        'nested': <Object?>[
          {'a': true},
        ],
      };
      final input = McpInvokeInput.fromJson({
        'request': {'name': 'serverdeck_x', 'arguments': args},
      });
      args['text'] = 'changed';
      expect(input.arguments!['text'], 'e\u0301');
      expect(input.arguments!['limit'], isA<double>());
      expect(
        () => (input.arguments!['nested'] as List).clear(),
        throwsUnsupportedError,
      );
      expect(
        () => ((input.arguments!['nested'] as List).single as Map)['a'] = false,
        throwsUnsupportedError,
      );
      final fresh = input.toJson();
      (fresh['request'] as Map)['name'] = 'changed';
      expect(input.name, 'serverdeck_x');
      for (final value in <Map<String, Object?>>[
        {'catalog': {}},
        {
          'poll': {'operationId': id},
        },
        {
          'cancel': {'operationId': id},
        },
      ]) {
        expect(
          McpInvokeInput.decode(utf8.encode(jsonEncode(value))).toJson(),
          value,
        );
      }
      for (final value in <Object?>[
        null,
        [],
        {},
        {'catalog': null},
        {
          'catalog': {'extra': 0},
        },
        {
          'catalog': {},
          'poll': {'operationId': id},
        },
        {
          'poll': {'operationId': 'bad'},
        },
        {
          'request': {'name': 'x', 'arguments': null},
        },
        {
          'request': {'name': '', 'arguments': {}},
        },
        {
          'request': {'name': 'x', 'arguments': {}, 'extra': true},
        },
      ]) {
        expect(() => McpInvokeInput.fromJson(value), throwsFormatException);
      }
      expect(
        () => McpInvokeInput.decode(utf8.encode('{"catalog":{},"catalog":{}}')),
        throwsFormatException,
      );
      expect(
        () => McpInvokeInput.fromJson({
          'request': {
            'name': 'x',
            'arguments': {'x': 'a' * (256 * 1024)},
          },
        }),
        throwsFormatException,
      );
    },
  );

  test('catalog input schemas validate literal integers, bounds, nested unions and keys', () {
    for (final tool in mcpTools) {
      expect(
        () => validateMcpArguments(tool, {'unexpected': true}),
        throwsFormatException,
      );
    }
    final list = mcpTool('serverdeck_servers_list')!;
    validateMcpArguments(list, {});
    validateMcpArguments(list, {'limit': 100});
    for (final args in [
      {'limit': 0},
      {'limit': 101},
      {'limit': 1.0},
      {'cursor': ''},
    ]) {
      expect(() => validateMcpArguments(list, args), throwsFormatException);
    }
    final logs = mcpTool('serverdeck_logs_read')!;
    validateMcpArguments(logs, {
      'serverId': id,
      'priority': 0,
      'since': '2026-10-21T10:00:00.000Z',
    });
    for (final patch in [
      {'priority': 8},
      {'since': '2026-02-30T10:00:00.000Z'},
      {'serverId': id.toUpperCase()},
    ]) {
      expect(
        () => validateMcpArguments(logs, {'serverId': id, ...patch}),
        throwsFormatException,
      );
    }
    final body = <String, Object?>{
      'format': 1,
      'environment': 'ubuntu24.04-amd64-systemd',
      'parameters': {
        'message': {'type': 'string', 'maxLength': 4096, 'default': 'hello'},
      },
      'steps': [
        {
          'id': 'motd',
          'kind': 'config_file',
          'resourceId': 'system.motd',
          'values': {
            'text': {'param': 'message'},
          },
        },
      ],
    };
    validateMcpArguments(mcpTool('serverdeck_profiles_validate')!, {
      'body': body,
    });
    (body['parameters'] as Map)['message'] = {
      'type': 'enum',
      'values': ['same', 'same'],
      'default': 'same',
    };
    expect(
      () => validateMcpArguments(mcpTool('serverdeck_profiles_validate')!, {
        'body': body,
      }),
      throwsFormatException,
    );
  });

  test('public tool result has matching content, immutable bytes and safe failures', () {
    final source = <String, Object?>{
      'log': 'e\u0301\n😀',
      'count': 9223372036854775807,
    };
    final result = McpToolResult.success(source);
    source['log'] = 'changed';
    final doc = result.toJson();
    expect((doc['structuredContent'] as Map)['data'], {
      'log': 'e\u0301\n😀',
      'count': 9223372036854775807,
    });
    expect(
      jsonDecode(((doc['content'] as List).single as Map)['text'] as String),
      doc['structuredContent'],
    );
    expect(McpToolResult.fromJson(doc).toJson(), doc);
    ((doc['structuredContent'] as Map)['data'] as Map)['log'] = 'changed';
    expect(result.toJson(), isNot(doc));
    for (final code in mcpDomainCodes) {
      final failed = McpToolResult.failure(code, requestId: id);
      expect(failed.toJson()['isError'], true);
      expect(McpToolResult.fromJson(failed.toJson()).toJson(), failed.toJson());
    }
    expect(
      () => McpToolResult.failure('PRIVATE_EXCEPTION'),
      throwsFormatException,
    );
    expect(
      () => McpToolResult.failure('TIMEOUT', boundary: 'shell'),
      throwsFormatException,
    );
    expect(
      () => McpToolResult.failure('TIMEOUT', retry: 'run-again'),
      throwsFormatException,
    );
    final bad = result.toJson();
    ((bad['content'] as List).single as Map)['text'] = '{}';
    expect(() => McpToolResult.fromJson(bad), throwsFormatException);
    expect(
      () => McpToolResult.success({'huge': 'x' * (8 * 1024 * 1024)}),
      throwsFormatException,
    );
    final cyclic = <String, Object?>{};
    cyclic['self'] = cyclic;
    expect(() => McpToolResult.success(cyclic), throwsFormatException);
    expect(
      () => McpToolResult.success({'private': Object()}),
      throwsFormatException,
    );
  });

  test('closed bounded replies reject unknown schemas and protocol codes', () {
    final definitions = mcpTools.take(2).toList();
    final catalog = McpInvokeReply.catalog(definitions).toJson();
    expect(McpInvokeReply.fromJson(catalog).toJson(), catalog);
    ((catalog['tools'] as List).first as Map)['name'] = 'serverdeck_shell';
    expect(() => McpInvokeReply.fromJson(catalog), throwsFormatException);
    final altered = McpInvokeReply.catalog(definitions).toJson();
    (((altered['tools'] as List).first as Map)['inputSchema']
            as Map)['additionalProperties'] =
        true;
    expect(() => McpInvokeReply.fromJson(altered), throwsFormatException);
    for (final reply in [
      McpInvokeReply.pending(id),
      McpInvokeReply.done(McpToolResult.success({})),
      McpInvokeReply.invalidParams(),
      McpInvokeReply.cancelled(),
    ]) {
      expect(McpInvokeReply.fromJson(reply.toJson()).toJson(), reply.toJson());
    }
    for (final doc in <Map<String, Object?>>[
      {'done': false, 'operationId': id, 'result': {}},
      {
        'done': true,
        'protocolError': {'code': -32603},
      },
      {'cancelled': false},
      {
        'done': true,
        'result': {},
        'protocolError': {'code': -32602},
      },
    ]) {
      expect(() => McpInvokeReply.fromJson(doc), throwsFormatException);
    }
  });
}
