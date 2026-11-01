import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/mcp/client.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_mcp/src/local_gateway.dart';
import 'package:serverdeck_mcp/src/server.dart';
import 'package:test/test.dart';

// Shared RAM peer/cryptographic fixture only; imported main is never invoked.
import '../../serverdeck_engine/test/mcp/client_test.dart' as ram;
import '../../serverdeck_engine/test/credentials/mcp_artifacts_test.dart'
    as credentials;
import '../../serverdeck_engine/test/hosting/authority_test.dart' show settle;

final class Lease implements PublicationLease {
  Lease(this.gate);
  final Gate gate;
  final completed = Completer<void>();
  @override
  Future<void> get done => completed.future;
  @override
  Future<void> close() async {
    if (completed.isCompleted) return;
    gate.held--;
    completed.complete();
    gate.settle();
  }
}

final class Gate implements PublicationGate {
  Gate(this.generation);
  @override
  final String generation;
  int held = 0, acquisitions = 0;
  @override
  int get activeAcquisitions => 0;
  @override
  int get activeLeases => held;
  @override
  bool isClosed = false;
  final closed = Completer<void>();
  @override
  PublicationAcquisition beginAcquire({
    Duration deadline = const Duration(seconds: 5),
  }) => throw StateError('NO_UNUSED_PORT');
  @override
  Future<PublicationLease> acquire({
    Duration deadline = const Duration(seconds: 5),
  }) async {
    if (isClosed) throw StateError('SERVICE_UNAVAILABLE');
    if (held != 0) throw StateError('UNIT_GATE_STILL_HELD');
    acquisitions++;
    held++;
    return Lease(this);
  }

  void settle() {
    if (isClosed && held == 0 && !closed.isCompleted) closed.complete();
  }

  @override
  Future<void> close() {
    isClosed = true;
    settle();
    return closed.future;
  }
}

final class PublicationClock implements EngineClock {
  PublicationClock(this.base);
  final EngineClock base;
  DateTime? wall;
  @override
  Duration get elapsed => base.elapsed;
  @override
  DateTime get utcNow => wall ?? base.utcNow;
}

final class Setup {
  Setup(this.core) : gate = Gate(core.descriptor.generation);
  final ram.Setup core;
  final Gate gate;
  late final clock = PublicationClock(core.clock);
  late final gateway = LocalMcpGateway.attach(core.client, gate, clock: clock);
  static Future<Setup> create({bool configured = false}) async {
    final s = Setup(await ram.Setup.create());
    await s.core.client.authenticate();
    if (configured) {
      await s.core.stage();
      await s.core.client.openGrant(s.core.artifacts, credentials.grant);
    }
    return s;
  }

  Future<void> close() async {
    await gateway.close();
    await core.close();
  }
}

Map<String, Object?> init() => {
  'jsonrpc': '2.0',
  'id': 1,
  'method': 'initialize',
  'params': {
    'protocolVersion': '2025-06-18',
    'capabilities': <String, Object?>{},
    'clientInfo': {'name': 'unit', 'version': '1'},
  },
};
List<int> line(Map<String, Object?> value) => [...encodeMcpMessage(value), 10];
Matcher unavailable() => throwsA(
  isA<McpGatewayFailure>().having(
    (e) => e.code,
    'safe code',
    ErrorCode.serviceUnavailable,
  ),
);

void main() {
  test('policy-error fallback releases original lease before reacquiring fixed gate', () async {
    final s = await Setup.create(configured: true);
    final original = s.core.peer.onMessage!;
    s.core.peer.onMessage = (value) async {
      if (value['method'] == 'mcp.invoke') {
        s.core.peer.feed(
          s.core.result(
            value,
            McpInvokeReply.done(McpToolResult.success({'private': 'discard'}))
                .toJson(),
          ),
        );
      } else if (value['method'] == 'session.ping') {
        s.core.peer.feed({
          'v': 1,
          'id': value['id'],
          'generation': s.core.descriptor.generation,
          'error': TrustedLocalError('FORBIDDEN').toJson(),
        });
      } else {
        await original(value);
      }
    };
    final input = StreamController<List<int>>(),
        output = <Map<String, Object?>>[];
    final run = McpServer(
      input: input.stream,
      gateway: s.gateway,
      write: (bytes) async {
        output.add(jsonDecode(utf8.decode(bytes)) as Map<String, Object?>);
      },
    ).run();
    input.add(line(init()));
    await settle();
    input.add(line({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));
    input.add(
      line({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {'name': 'unit.unknown', 'arguments': <String, Object?>{}},
      }),
    );
    await settle();
    expect(output.length, 2);
    expect(jsonEncode(output.last), isNot(contains('discard')));
    expect(
      (((output.last['result'] as Map)['structuredContent'] as Map)['error']
          as Map)['code'],
      'FORBIDDEN',
    );
    expect(s.gate.acquisitions, 3);
    expect(s.gate.held, 0);
    expect(s.gateway.isClosed, isFalse);
    await input.close();
    expect(await run, 0);
    await s.close();
  });
  test(
    'queued grant expiry fallback requires fresh fixed proof before output',
    () async {
      for (final failedProof in [false, true]) {
        final s = await Setup.create(configured: true);
        final original = s.core.peer.onMessage!;
        var invokes = 0;
        s.core.peer.onMessage = (value) async {
          if (value['method'] != 'mcp.invoke') {
            await original(value);
            return;
          }
          invokes++;
          s.core.peer.feed(
            s.core.result(
              value,
              McpInvokeReply.done(
                McpToolResult.success({
                  'marker': invokes == 1 ? 'first' : 'second-private',
                }),
              ).toJson(),
            ),
          );
        };
        final input = StreamController<List<int>>(),
            output = <Map<String, Object?>>[];
        final flush = Completer<void>(), issued = Completer<void>();
        final run = McpServer(
          input: input.stream,
          gateway: s.gateway,
          write: (bytes) {
            final message =
                jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
            output.add(message);
            if (message['id'] == 2) {
              issued.complete();
              return flush.future;
            }
            return Future<void>.value();
          },
        ).run();
        input.add(line(init()));
        await settle();
        input.add(
          line({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
        );
        input.add(
          line({
            'jsonrpc': '2.0',
            'id': 2,
            'method': 'tools/call',
            'params': {
              'name': 'unit.unknown',
              'arguments': <String, Object?>{},
            },
          }),
        );
        await issued.future;
        input.add(
          line({
            'jsonrpc': '2.0',
            'id': 3,
            'method': 'tools/call',
            'params': {
              'name': 'unit.unknown',
              'arguments': <String, Object?>{},
            },
          }),
        );
        await settle();
        expect(invokes, 2);
        expect(output.length, 2);
        s.clock.wall = DateTime.parse(s.core.client.grant!.expiresAt);
        final proofs = s.core.peer.proofs;
        if (failedProof) s.core.peer.proofError = StateError('UNAUTHORIZED');
        flush.complete();
        await settle();
        expect(
          s.gate.acquisitions,
          3,
        ); // init, first domain, fixed expiry fallback
        expect(s.core.peer.proofs, greaterThan(proofs));
        expect(s.gate.held, 0);
        if (failedProof) {
          expect(await run, 2);
          expect(output.length, 2);
          await input.close();
        } else {
          expect(output.length, 3);
          final fallback = output.last['result'] as Map;
          expect(
            ((fallback['structuredContent'] as Map)['error'] as Map)['code'],
            'FORBIDDEN',
          );
          expect(jsonEncode(output.last), isNot(contains('second-private')));
          await input.close();
          expect(await run, 0);
        }
        expect(
          s.core.peer.messages
              .where((m) => m['method'] == 'session.ping')
              .length,
          1,
        );
        await s.close();
      }
    },
  );
  test(
    'unconfigured tools still own native binding and publication lease',
    () async {
      final s = await Setup.create();
      final invocation = s.gateway.start('tools/list', {});
      expect(await invocation.result, {'tools': <Object?>[]});
      final proofs = s.core.peer.proofs;
      await invocation.beforePublish!();
      expect(s.gate.held, 1);
      expect(s.core.peer.proofs, greaterThan(proofs));
      expect(
        s.core.peer.messages.length,
        1,
      ); // bootstrap only, no mcp.invoke/open
      invocation.validatePublication!();
      await invocation.afterPublish!();
      expect(s.gate.held, 0);
      await s.close();
    },
  );
  test('unconfigured call is forbidden without grant, guarded by same live channel', () async {
    final s = await Setup.create();
    final invocation = s.gateway.start('tools/call', {
      'name': 'unit.unknown',
      'arguments': <String, Object?>{},
    });
    final result = McpToolResult.fromJson(await invocation.result).toJson();
    expect(
      ((result['structuredContent'] as Map)['error'] as Map)['code'],
      'FORBIDDEN',
    );
    await invocation.beforePublish!();
    await invocation.afterPublish!();
    expect(s.core.peer.messages.length, 1);
    await s.close();
  });
  test('logical client loss retires gateway before physical drain', () async {
    final s = await Setup.create();
    s.gateway;
    s.core.peer.closing = Completer();
    var closed = false;
    unawaited(s.core.client.close().then((_) => closed = true));
    await s.gateway.retired;
    expect(closed, isFalse);
    expect(s.gateway.isClosed, isTrue);
    expect(() => s.gateway.start('tools/list', {}), unavailable());
    s.core.peer.closing!.complete();
    await s.close();
  });
  test(
    'configured catalog uses current-policy ping under native publication gate',
    () async {
      final s = await Setup.create(configured: true);
      final original = s.core.peer.onMessage!;
      s.core.peer.onMessage = (value) async {
        if (value['method'] == 'mcp.invoke')
          s.core.peer.feed(
            s.core.result(value, McpInvokeReply.catalog([]).toJson()),
          );
        else
          await original(value);
      };
      final invocation = s.gateway.start('tools/list', {});
      expect(await invocation.result, {'tools': <Object?>[]});
      await invocation.beforePublish!();
      expect(s.gate.held, 1);
      expect(s.core.peer.messages.last['method'], 'session.ping');
      await invocation.afterPublish!();
      await s.close();
    },
  );
  test(
    'cancellation drops only pending invocation interest, never durable jobs',
    () async {
      final s = await Setup.create(configured: true);
      final original = s.core.peer.onMessage!;
      s.core.peer.onMessage = (value) async {
        if (value['method'] != 'mcp.invoke') {
          await original(value);
          return;
        }
        final params = value['params'] as Map;
        s.core.peer.feed(
          s.core.result(
            value,
            params.containsKey('cancel')
                ? McpInvokeReply.cancelled().toJson()
                : McpInvokeReply.pending(credentials.firstSecret).toJson(),
          ),
        );
      };
      final invocation = s.gateway.start('tools/call', {
        'name': 'unit.unknown',
        'arguments': <String, Object?>{},
      });
      invocation.result.ignore();
      await settle();
      await invocation.cancelInterest();
      await expectLater(
        invocation.result,
        throwsA(
          isA<McpGatewayFailure>().having(
            (e) => e.code,
            'safe code',
            ErrorCode.forbidden,
          ),
        ),
      );
      final invokes = s.core.peer.messages
          .where((m) => m['method'] == 'mcp.invoke')
          .toList();
      expect(invokes.length, 2);
      expect(invokes.last['params'], {
        'cancel': {'operationId': credentials.firstSecret},
      });
      expect(
        s.core.peer.messages.any((m) => m['method'] == 'jobs_cancel'),
        isFalse,
      );
      await s.close();
    },
  );
  test(
    'validated remote unavailable error remains nonterminal with no replay',
    () async {
      final s = await Setup.create(configured: true);
      final original = s.core.peer.onMessage!;
      var invokes = 0;
      s.core.peer.onMessage = (value) async {
        if (value['method'] != 'mcp.invoke') {
          await original(value);
          return;
        }
        invokes++;
        s.core.peer.feed(
          invokes == 1
              ? {
                  'v': 1,
                  'id': value['id'],
                  'generation': s.core.descriptor.generation,
                  'error': TrustedLocalError('SERVICE_UNAVAILABLE').toJson(),
                }
              : s.core.result(value, McpInvokeReply.catalog([]).toJson()),
        );
      };
      final failed = s.gateway.start('tools/call', {
        'name': 'unit.unknown',
        'arguments': <String, Object?>{},
      });
      final result = await failed.result;
      expect(
        (((result['structuredContent'] as Map)['error']) as Map)['code'],
        'SERVICE_UNAVAILABLE',
      );
      final proofs = s.core.peer.proofs, acquisitions = s.gate.acquisitions;
      await failed.beforePublish!();
      expect(s.core.peer.proofs, greaterThan(proofs));
      expect(s.gate.acquisitions, acquisitions + 1);
      expect(s.gate.held, 1);
      await failed.afterPublish!();
      expect(s.gateway.isClosed, isFalse);
      final next = s.gateway.start('tools/list', {});
      expect(await next.result, {'tools': <Object?>[]});
      await next.beforePublish!();
      await next.afterPublish!();
      expect(invokes, 2);
      await s.close();
    },
  );
  test(
    'fixed remote RPC error cannot publish after fresh native proof fails',
    () async {
      final s = await Setup.create(configured: true);
      final original = s.core.peer.onMessage!;
      s.core.peer.onMessage = (value) async {
        if (value['method'] != 'mcp.invoke') {
          await original(value);
          return;
        }
        s.core.peer.feed({
          'v': 1,
          'id': value['id'],
          'generation': s.core.descriptor.generation,
          'error': TrustedLocalError('SERVICE_UNAVAILABLE').toJson(),
        });
      };
      final failed = s.gateway.start('tools/call', {
        'name': 'unit.unknown',
        'arguments': <String, Object?>{},
      });
      await failed.result;
      expect(s.gateway.isClosed, isFalse);
      s.core.peer.proofError = StateError('UNAUTHORIZED');
      await expectLater(failed.beforePublish!(), unavailable());
      await failed.afterPublish!();
      expect(s.gate.acquisitions, 1);
      expect(s.gate.held, 0);
      expect(s.gateway.isClosed, isTrue);
      await s.close();
    },
  );
  test('overload fixed reply still requires gate and live proof with full RPC slots', () async {
    for (final failProof in [false, true]) {
      final s = await Setup.create(configured: true);
      for (var i = 0; i < 16; i++) {
        s.gateway
            .start('tools/call', {
              'name': 'unit.unknown',
              'arguments': <String, Object?>{},
            })
            .result
            .ignore();
      }
      await settle();
      expect(s.core.client.pendingRequests, 16);
      final extra = s.gateway.start('tools/call', {
        'name': 'unit.unknown',
        'arguments': <String, Object?>{},
      });
      final result = await extra.result;
      expect(
        (((result['structuredContent'] as Map)['error']) as Map)['code'],
        'RESOURCE_LIMIT',
      );
      final proofs = s.core.peer.proofs;
      if (failProof) s.core.peer.proofError = StateError('UNAUTHORIZED');
      if (failProof) {
        await expectLater(extra.beforePublish!(), unavailable());
      } else {
        await extra.beforePublish!();
        extra.validatePublication!();
      }
      expect(s.core.peer.proofs, greaterThan(proofs));
      expect(s.gate.acquisitions, 1);
      await extra.afterPublish!();
      await s.close();
    }
  });
  test(
    'initialize, ping and empty tool list all use live publication guards',
    () async {
      final s = await Setup.create();
      final input = StreamController<List<int>>(),
          output = <Map<String, Object?>>[];
      final run = McpServer(
        input: input.stream,
        gateway: s.gateway,
        write: (bytes) async {
          output.add(jsonDecode(utf8.decode(bytes)) as Map<String, Object?>);
        },
      ).run();
      input.add(line(init()));
      await settle();
      expect(output.single['id'], 1);
      input.add(
        line({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      );
      input.add(line({'jsonrpc': '2.0', 'id': 2, 'method': 'ping'}));
      input.add(line({'jsonrpc': '2.0', 'id': 3, 'method': 'tools/list'}));
      await settle();
      expect(output.map((v) => v['id']), [1, 2, 3]);
      expect(output.last['result'], {'tools': <Object?>[]});
      expect(s.gate.acquisitions, 3);
      await input.close();
      expect(await run, 0);
      await s.close();
    },
  );
  test('lost app stops idle stdio without another stdin message', () async {
    final s = await Setup.create();
    final input = StreamController<List<int>>(), output = <List<int>>[];
    final run = McpServer(
      input: input.stream,
      gateway: s.gateway,
      write: (b) async {
        output.add(b);
      },
    ).run();
    await s.core.peer.disconnect();
    expect(await run, 2);
    expect(output, isEmpty);
    await input.close();
    await s.close();
  });
  test('failed fresh native proof prevents builtin response', () async {
    final s = await Setup.create();
    final input = StreamController<List<int>>(), output = <List<int>>[];
    final run = McpServer(
      input: input.stream,
      gateway: s.gateway,
      write: (b) async {
        output.add(b);
      },
    ).run();
    s.core.peer.proofError = StateError('UNAUTHORIZED');
    input.add(line(init()));
    expect(await run, 2);
    expect(output, isEmpty);
    expect(s.gate.held, 0);
    await input.close();
    await s.close();
  });
  test(
    'publication lease remains held until actual stdout flush after retirement',
    () async {
      final s = await Setup.create();
      final input = StreamController<List<int>>(),
          flush = Completer<void>(),
          issued = Completer<void>();
      final run = McpServer(
        input: input.stream,
        gateway: s.gateway,
        write: (_) {
          issued.complete();
          return flush.future;
        },
      ).run();
      input.add(line(init()));
      await issued.future;
      expect(s.gate.held, 1);
      await s.core.client.close();
      await settle();
      expect(s.gate.isClosed, isTrue);
      expect(s.gate.held, 1);
      flush.complete();
      expect(await run, 2);
      expect(s.gate.held, 0);
      await input.close();
      await s.close();
    },
  );
  test(
    'physical gateway close failure after EOF yields terminal stdio status',
    () async {
      final s = await Setup.create();
      final input = StreamController<List<int>>();
      final run = McpServer(
        input: input.stream,
        gateway: s.gateway,
        write: (_) async {},
      ).run();
      s.core.peer.failClose = true;
      await input.close();
      expect(await run, 2);
      await expectLater(s.core.client.close(), throwsA(isA<Exception>()));
      s.core.descriptor.close();
      s.core.serverToken.fillRange(0, s.core.serverToken.length, 0);
      s.core.protection.dispose();
    },
  );
}
