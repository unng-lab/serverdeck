import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/console_models.dart';
import 'package:serverdeck/console/console_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/mcp/router.dart';
import 'package:serverdeck/mcp/tool_schemas.dart';

import '../fixtures/feature_harness.dart';
import 'router_contract_test.dart' show RouterOperations, rpc;

final class FakeConsoleOperations extends Fake implements ConsoleOperations {
  final calls = <Invocation>[];
  ConsoleMcpBinding? closedBinding;
  OperationResult<ConsoleValue>? response;
  @override
  void disconnectBinding(ConsoleMcpBinding binding) => closedBinding = binding;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return Future.value(
      response ??
          const OperationResult<ConsoleValue>.failure(
            OperationFailure(FailureCode.consoleInactive),
          ),
    );
  }
}

Map<String, dynamic> consoleArguments(String name) {
  final target = {
    'profileId': featureId(1),
    'sessionId': featureId(2),
    'generation': 1,
  };
  final mutation = {'ownerEpoch': featureId(3), 'operationSequence': 1};
  return switch (name) {
    'console.profiles' => {},
    'console.list' => {'profileId': featureId(1)},
    'console.open' => {'profileId': featureId(1), ...mutation},
    'console.read' => target,
    'console.acquire' => {...target, ...mutation},
    'console.release' => {...target, ...mutation, 'leaseToken': featureId(4)},
    'console.write' => {
      ...target,
      ...mutation,
      'leaseToken': featureId(4),
      'key': 'Ctrl+C',
    },
    'console.close' => {
      ...target,
      ...mutation,
      'confirmed': true,
      'leaseToken': featureId(4),
    },
    _ => throw StateError(name),
  };
}

void main() {
  late FeatureHarness h;
  late FakeConsoleOperations console;
  late McpSession session;
  final schemas = ToolSchemas(
    jsonDecode(File('assets/mcp/tools.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  setUp(() async {
    h = FeatureHarness();
    console = FakeConsoleOperations();
    final grant = await h.grants.issue(
      h.actors.ui,
      'Console fixture',
      confirmed: true,
    );
    await h.grants.setEnabled(h.actors.ui, true);
    session = McpRouter(
      operations: RouterOperations(),
      consoles: console,
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
  tearDown(() async {
    session.closed = true;
    await h.dispose();
  });
  for (final name in ToolSchemas.names.where((n) => n.startsWith('console.'))) {
    test(
      '$name dispatches typed operation with trusted connection binding',
      () async {
        final reply = await session.handle(
          rpc(1, 'tools/call', {
            'name': name,
            'arguments': consoleArguments(name),
          }),
        );
        expect(console.calls.length, 1);
        final caller =
            console.calls.single.positionalArguments.first as ConsoleCaller;
        expect(caller.binding, isNotNull);
        expect(
          ((reply!['result'] as Map)['structuredContent'] as Map)['ok'],
          false,
        );
        expect(
          utf8.encode(jsonEncode(reply)).length,
          lessThanOrEqualTo(1048576),
        );
        session.closed = true;
        expect(caller.binding!.disconnected.isCancelled, true);
        expect(identical(console.closedBinding, caller.binding), true);
        expect(
          await session.handle(
            rpc(2, 'tools/call', {
              'name': name,
              'arguments': consoleArguments(name),
            }),
          ),
          isNull,
        );
      },
    );
    test('$name rejects unrecognized keys before owner', () async {
      final reply = await session.handle(
        rpc(1, 'tools/call', {
          'name': name,
          'arguments': {...consoleArguments(name), 'extra': 'input'},
        }),
      );
      expect((reply!['error'] as Map)['code'], -32602);
      expect(console.calls, isEmpty);
    });
  }
  test('write schema requires exactly text or known key', () {
    final input = consoleArguments('console.write');
    expect(
      () => schemas.arguments('console.write', {...input, 'text': 'x'}),
      throwsA(isA<SchemaFailure>()),
    );
    expect(
      () =>
          schemas.arguments('console.write', {...input, 'key': 'Ctrl+UNKNOWN'}),
      throwsA(isA<SchemaFailure>()),
    );
    expect(
      () => schemas.arguments('console.write', {
        ...input,
        'confirmedMultiline': 'true',
      }),
      throwsA(isA<SchemaFailure>()),
    );
  });
  test(
    'complete duplicated MCP envelope is bounded, not just inner JSON',
    () async {
      console.response = OperationResult.success(
        ConsoleValue(
          ConsoleHistoryValue(
            session: ConsoleSessionView(
              sessionId: featureId(2),
              profileId: featureId(1),
              generation: 1,
              shellProfileId: 'login',
              shellName: 'Shell',
              state: 'active',
              partial: false,
              historyVersion: 1,
              inputOwner: const ConsoleInputView('free'),
            ),
            activeBuffer: 'main',
            cursorX: 0,
            cursorY: 0,
            historyVersion: 1,
            historyGap: false,
            truncated: false,
            partial: false,
            rows: [
              ConsoleHistoryRow(
                section: 'screen',
                row: 0,
                offset: 0,
                text: '\\' * 280000,
                wrapped: false,
              ),
            ],
          ),
        ),
        OperationMeta(dataRevision: 1, ownerEpoch: h.actors.ownerEpoch),
      );
      expect(
        utf8.encode(jsonEncode(console.response!.toJson())).length,
        lessThan(1048576),
      );
      final reply = await session.handle(
        rpc(1, 'tools/call', {
          'name': 'console.read',
          'arguments': consoleArguments('console.read'),
        }),
      );
      expect(utf8.encode(jsonEncode(reply)).length, lessThanOrEqualTo(1048576));
      expect(
        ((reply!['result'] as Map)['structuredContent']
            as Map)['error']['code'],
        'RESOURCE_EXHAUSTED',
      );
    },
  );
}
