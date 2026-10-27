import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_mcp/src/server.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

final class Gateway implements McpGateway {
  int starts = 0, guards = 0, cancelled = 0, releases = 0, closes = 0;
  bool allowed = true;
  Future<void> Function()? guard;
  bool failStart = false,
      failResult = false,
      validAtIssue = true,
      failRelease = false;
  @override
  McpInvocation start(String method, Map<String, Object?> params) {
    final number = ++starts;
    if (failStart) throw const McpGatewayFailure(ErrorCode.resourceLimit);
    return McpInvocation(
      failResult
          ? Future<Map<String, Object?>>.error(
              const McpGatewayFailure(ErrorCode.timeout),
            )
          : Future.value(
              method == 'tools/list'
                  ? {'tools': <Object?>[]}
                  : McpToolResult.success({'value': 'owned-private-$number'})
                        .toJson(),
            ),
      () async {
        cancelled++;
      },
      beforePublish: () async {
        guards++;
        await guard?.call();
        if (!allowed) throw const McpGatewayFailure(ErrorCode.forbidden);
      },
      validatePublication: () {
        if (!validAtIssue) throw const McpGatewayFailure(ErrorCode.forbidden);
      },
      afterPublish: () async {
        releases++;
        if (failRelease) throw StateError('OWNED_CLEANUP_SENTINEL');
      },
    );
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

final class Harness {
  Harness({
    Future<void> Function(Map<String, Object?>)? sink,
    Duration writeTimeout = const Duration(seconds: 2),
  }) {
    running = McpServer.forTesting(
      input: input.stream,
      gateway: gateway,
      write: (bytes) async {
        final frame = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
        frames.add(frame);
        await sink?.call(frame);
      },
      diagnostic: diagnostics.add,
      initializationTimeout: const Duration(seconds: 3),
      writeTimeout: writeTimeout,
      callTimeout: const Duration(seconds: 3),
    ).run();
  }
  final input = StreamController<List<int>>();
  final gateway = Gateway();
  final frames = <Map<String, Object?>>[];
  final diagnostics = <String>[];
  late final Future<int> running;
  void send(String method, Object? id, Map<String, Object?> params) {
    input.add(
      utf8.encode(
        '${jsonEncode({'jsonrpc': '2.0', if (id != null) 'id': id, 'method': method, 'params': params})}\n',
      ),
    );
  }

  Future<void> initialize() async {
    send('initialize', 0, {
      'protocolVersion': '2025-11-25',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'fixture', 'version': '1'},
    });
    await until(() => frames.any((frame) => frame['id'] == 0));
    send('notifications/initialized', null, {});
  }

  void call(Object id) => send('tools/call', id, {
    'name': 'fixture',
    'arguments': <String, Object?>{},
  });
  Future<void> stop() async {
    await input.close();
    await running.timeout(const Duration(seconds: 5));
  }
}

Future<void> until(bool Function() check) async {
  final watch = Stopwatch()..start();
  while (!check()) {
    if (watch.elapsed > const Duration(seconds: 3))
      throw StateError('FIXTURE_TIMEOUT');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  test('queued publication checks authority after the issued writer', () async {
    final issued = Completer<void>(), release = Completer<void>();
    final h = Harness(
      sink: (frame) async {
        if (frame['id'] == 1) {
          issued.complete();
          await release.future;
        }
      },
    );
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await h.stop();
    });
    await h.initialize();
    h.call(1);
    await issued.future;
    h.call(2);
    await until(() => h.gateway.starts == 2);
    expect(h.gateway.guards, 1);
    h.gateway.allowed = false;
    release.complete();
    await until(() => h.frames.any((frame) => frame['id'] == 2));
    final first = h.frames.singleWhere((frame) => frame['id'] == 1);
    final second = h.frames.singleWhere((frame) => frame['id'] == 2);
    expect(jsonEncode(first), contains('owned-private-1'));
    expect(jsonEncode(second), isNot(contains('owned-private')));
    expect(
      (((second['result'] as Map)['structuredContent'] as Map)['error']
          as Map)['code'],
      'FORBIDDEN',
    );
    expect(h.gateway.guards, 2);
  });

  test('late guard cannot publish a cancelled reused external id', () async {
    final release = Completer<void>();
    final h = Harness();
    h.gateway.guard = () async {
      if (h.gateway.guards == 1) await release.future;
    };
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await h.stop();
    });
    await h.initialize();
    const id = 'e\u0301😀';
    h.call(id);
    await until(() => h.gateway.guards == 1);
    h.send('notifications/cancelled', null, {'requestId': id});
    await until(() => h.gateway.cancelled == 1);
    h.call(id);
    await until(() => h.gateway.starts == 2);
    release.complete();
    await until(() => h.frames.any((frame) => frame['id'] == id));
    final outputs = h.frames.where((frame) => frame['id'] == id).toList();
    expect(outputs, hasLength(1));
    expect(jsonEncode(outputs.single), contains('owned-private-2'));
    expect(jsonEncode(outputs.single), isNot(contains('owned-private-1')));
  });

  for (final typed in [true, false]) {
    test(
      'guard failure replaces catalog with fixed error typed=$typed',
      () async {
        final h = Harness();
        h.gateway.guard = () async {
          if (typed) throw const McpGatewayFailure(ErrorCode.storageBlocked);
          throw StateError('OWNED_SENTINEL_NEVER_PUBLIC');
        };
        addTearDown(h.stop);
        await h.initialize();
        h.send('tools/list', 1, {});
        await until(() => h.frames.any((frame) => frame['id'] == 1));
        final frame = h.frames.singleWhere((frame) => frame['id'] == 1);
        expect(frame['error'], {
          'code': -32000,
          'message': typed ? 'STORAGE_BLOCKED' : 'INTERNAL',
        });
        expect(jsonEncode(frame), isNot(contains('OWNED_SENTINEL')));
        expect(frame.containsKey('result'), false);
      },
    );
  }

  for (final atStart in [true, false]) {
    for (final method in ['tools/list', 'tools/call']) {
      test(
        'typed gateway failure method=$method synchronous=$atStart',
        () async {
          final h = Harness();
          h.gateway.failStart = atStart;
          h.gateway.failResult = !atStart;
          addTearDown(h.stop);
          await h.initialize();
          h.send(method, 1, method == 'tools/list' ? {} : {'name': 'fixture'});
          await until(() => h.frames.any((frame) => frame['id'] == 1));
          final frame = h.frames.singleWhere((frame) => frame['id'] == 1);
          final code = atStart ? 'RESOURCE_LIMIT' : 'TIMEOUT';
          if (method == 'tools/list') {
            expect(frame['error'], {'code': -32000, 'message': code});
          } else {
            expect(
              (((frame['result'] as Map)['structuredContent'] as Map)['error']
                  as Map)['code'],
              code,
            );
          }
          expect(h.gateway.guards, 0);
        },
      );
    }
  }

  test(
    'synchronous final validation retires guarded data and releases',
    () async {
      final h = Harness();
      h.gateway.guard = () async {
        h.gateway.validAtIssue = false;
      };
      addTearDown(h.stop);
      await h.initialize();
      h.call(1);
      await until(() => h.frames.any((frame) => frame['id'] == 1));
      expect(jsonEncode(h.frames.last), isNot(contains('owned-private')));
      expect(jsonEncode(h.frames.last), contains('FORBIDDEN'));
      await until(() => h.gateway.releases == 1);
    },
  );

  test('cancel during guard releases once without stale publication', () async {
    final release = Completer<void>();
    final h = Harness();
    h.gateway.guard = () => release.future;
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await h.stop();
    });
    await h.initialize();
    h.call(1);
    await until(() => h.gateway.guards == 1);
    h.send('notifications/cancelled', null, {'requestId': 1});
    await until(() => h.gateway.cancelled == 1);
    release.complete();
    await until(() => h.gateway.releases == 1);
    expect(h.frames.where((frame) => frame['id'] == 1), isEmpty);
  });

  test('late guard completion releases after the writer times out', () async {
    final release = Completer<void>();
    final h = Harness(writeTimeout: const Duration(milliseconds: 50));
    h.gateway.guard = () => release.future;
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await h.stop();
    });
    await h.initialize();
    h.call(1);
    expect(await h.running, 2);
    expect(h.gateway.releases, 0);
    release.complete();
    await until(() => h.gateway.releases == 1);
    expect(h.frames.where((frame) => frame['id'] == 1), isEmpty);
  });

  test('failed publication cleanup closes with fixed diagnostics', () async {
    final h = Harness();
    h.gateway.failRelease = true;
    addTearDown(h.stop);
    await h.initialize();
    h.call(1);
    expect(await h.running.timeout(const Duration(seconds: 3)), 2);
    expect(h.gateway.releases, 1);
    expect(h.diagnostics, contains('WRITE_FAILED'));
    expect(h.diagnostics.join(), isNot(contains('SENTINEL')));
  });

  test(
    'late failed flush releases once without leaking its exception',
    () async {
      final blocked = Completer<void>();
      final h = Harness(
        writeTimeout: const Duration(milliseconds: 50),
        sink: (frame) async {
          if (frame['id'] == 1) await blocked.future;
        },
      );
      addTearDown(() async {
        if (!blocked.isCompleted) blocked.complete();
        await h.stop();
      });
      await h.initialize();
      h.call(1);
      expect(await h.running.timeout(const Duration(seconds: 2)), 2);
      expect(h.gateway.releases, 0);
      blocked.completeError(StateError('OWNED_LATE_FLUSH_SENTINEL'));
      await until(() => h.gateway.releases == 1);
      expect(h.diagnostics.join(), isNot(contains('SENTINEL')));
      expect(jsonEncode(h.frames), isNot(contains('SENTINEL')));
    },
  );

  test('guard and blocked flush share one writer budget', () async {
    final blocked = Completer<void>();
    final h = Harness(
      writeTimeout: const Duration(milliseconds: 600),
      sink: (frame) async {
        if (frame['id'] == 1) await blocked.future;
      },
    );
    addTearDown(() async {
      if (!blocked.isCompleted) blocked.complete();
      await h.stop();
    });
    h.gateway.guard = () =>
        Future<void>.delayed(const Duration(milliseconds: 400));
    await h.initialize();
    final watch = Stopwatch()..start();
    h.call(1);
    expect(await h.running.timeout(const Duration(seconds: 3)), 2);
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 900)));
    expect(h.diagnostics, contains('WRITE_FAILED'));
    expect(
      h.gateway.releases,
      0,
      reason: 'actual flush still owns publication',
    );
    blocked.complete();
    await until(() => h.gateway.releases == 1);
  });
}
