import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import '../../serverdeck_mcp/lib/src/server.dart';
import '../../serverdeck_windows/test/support/trusted_client_fixture.dart';
import 'support/gateway_actor.dart' as actor;
import 'support/gateway_quota_fixture.dart';
import 'support/operational_grant_actor.dart' as grant;

Future<(Object, StackTrace)?> outcome(Future<void> Function() run) async {
  try {
    await run();
    return null;
  } catch (error, stack) {
    return (error, stack);
  }
}

void check(bool value) {
  if (!value) throw StateError('FIXTURE_ASSERTION');
}

final class ControlledRecordHandle implements RandomAccessFile {
  ControlledRecordHandle(this.bytes, this.lengths);
  final List<int> bytes;
  final List<int> lengths;
  var lengthCalls = 0, readCalls = 0, closeCalls = 0;
  int? readLimit;
  @override
  int lengthSync() => lengths[lengthCalls++];
  @override
  Uint8List readSync(int count) {
    readCalls++;
    readLimit = count;
    return Uint8List.fromList(bytes.take(count).toList());
  }

  @override
  void closeSync() => closeCalls++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class ControlledRecordFile implements File {
  ControlledRecordFile(this.handle, this.namedLength);
  final ControlledRecordHandle handle;
  final int namedLength;
  var opens = 0;
  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    opens++;
    return handle;
  }

  @override
  int lengthSync() => namedLength;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('quota-pure-'));
  tearDown(() => root.deleteSync(recursive: true));
  GatewayQuotaFailureRecorder recorder([GatewayQuotaFailureRole? role]) =>
      GatewayQuotaFailureRecorder(
        root.path,
        role ?? GatewayQuotaFailureRole.server,
      );
  File recordFile(GatewayQuotaFailureRole role) =>
      File.fromUri(root.uri.resolve(gatewayQuotaFailureBasename(role)));
  GatewayQuotaFailureRecord? read([GatewayQuotaFailureRole? role]) =>
      readGatewayQuotaFailure(
        root.path,
        role ?? GatewayQuotaFailureRole.server,
      );

  test(
    'opt-in actual dispatch preserves first failure before cleanup',
    () async {
      final first = StateError('FIXTURE_ASSERTION');
      final firstStack = StackTrace.fromString('PRIMARY_THROW');
      final secondary = StateError('TIMEOUT');
      final lifecycle = GatewayQuotaLifecycle(recorder(), 'server-admitted16');
      final result = await outcome(
        () => grant.runScenarioFixtureLifecycle(
          body: () async => Error.throwWithStackTrace(first, firstStack),
          cleanup: () async {
            expect(read()?.phase, 'server-admitted16');
            expect(read()?.code, 'FIXTURE_ASSERTION');
            throw secondary;
          },
          lifecycle: ({required body, required cleanup}) => lifecycle.run(
            body: body,
            cleanup: cleanup,
            cleanupPhase: 'scenario-cleanup',
          ),
        ),
      );
      expect(result!.$1, isA<OwnedFixtureFailure>());
      final aggregate = result.$1 as OwnedFixtureFailure;
      expect(aggregate.primary, same(first));
      expect(aggregate.primaryStack, same(firstStack));
      expect(aggregate.secondary, same(secondary));
      expect(result.$2, same(firstStack));
    },
  );

  test('default and explicit null preserve legacy cleanup masking', () async {
    for (final explicitNull in [false, true]) {
      final first = StateError('body');
      final cleanup = StateError('cleanup');
      final stack = StackTrace.fromString('LEGACY_CLEANUP');
      final order = <String>[];
      Future<void> body() async {
        order.add('body');
        throw first;
      }

      Future<void> close() async {
        order.add('cleanup');
        Error.throwWithStackTrace(cleanup, stack);
      }

      final result = await outcome(
        () => explicitNull
            ? grant.runScenarioFixtureLifecycle(
                body: body,
                cleanup: close,
                lifecycle: null,
              )
            : grant.runScenarioFixtureLifecycle(body: body, cleanup: close),
      );
      expect(result!.$1, same(cleanup));
      expect(result.$2, same(stack));
      expect(order, ['body', 'cleanup']);
    }
  });

  test('callback failure has no body cleanup or fallback', () async {
    final failure = Object();
    var calls = 0;
    final result = await outcome(
      () => grant.runScenarioFixtureLifecycle(
        body: () async => fail('unexpected body'),
        cleanup: () async => fail('unexpected cleanup'),
        lifecycle: ({required body, required cleanup}) async {
          calls++;
          throw failure;
        },
      ),
    );
    expect(result!.$1, same(failure));
    expect(calls, 1);
  });

  for (final bodyFails in [false, true]) {
    for (final cleanupFails in [false, true]) {
      test('actual lifecycle body=$bodyFails cleanup=$cleanupFails', () async {
        final bodyFailure = Object(), cleanupFailure = Object();
        final bodyStack = StackTrace.fromString('BODY');
        final cleanupStack = StackTrace.fromString('CLEANUP');
        final bodySettled = Completer<void>(),
            cleanupSettled = Completer<void>();
        final bodyStarted = Completer<void>(),
            cleanupStarted = Completer<void>();
        var bodies = 0, cleanups = 0, settled = false;
        final lifecycle = GatewayQuotaLifecycle(recorder(), 'server-bootstrap');
        final pending = outcome(
          () => lifecycle.run(
            body: () async {
              bodies++;
              bodyStarted.complete();
              await bodySettled.future;
              if (bodyFails) Error.throwWithStackTrace(bodyFailure, bodyStack);
            },
            cleanup: () async {
              cleanups++;
              expect(bodySettled.isCompleted, true);
              if (bodyFails) expect(read()?.phase, 'server-bootstrap');
              cleanupStarted.complete();
              await cleanupSettled.future;
              if (cleanupFails) {
                Error.throwWithStackTrace(cleanupFailure, cleanupStack);
              }
            },
            cleanupPhase: 'server-cleanup',
          ),
        );
        unawaited(pending.then((_) => settled = true));
        await bodyStarted.future;
        expect(cleanups, 0);
        bodySettled.complete();
        await cleanupStarted.future;
        expect(settled, false);
        cleanupSettled.complete();
        final result = await pending;
        expect(bodies, 1);
        expect(cleanups, 1);
        if (!bodyFails && !cleanupFails) {
          expect(result, null);
          expect(read(), null);
        } else if (bodyFails && cleanupFails) {
          final failure = result!.$1 as OwnedFixtureFailure;
          expect(failure.primary, same(bodyFailure));
          expect(failure.primaryStack, same(bodyStack));
          expect(failure.secondary, same(cleanupFailure));
          expect(failure.secondaryStack, same(cleanupStack));
          expect(result.$2, same(bodyStack));
        } else {
          expect(result!.$1, same(bodyFails ? bodyFailure : cleanupFailure));
          expect(result.$2, same(bodyFails ? bodyStack : cleanupStack));
          expect(
            read()?.phase,
            bodyFails ? 'server-bootstrap' : 'server-cleanup',
          );
        }
      });
    }
  }

  test(
    'nested boundaries observe before every original finally and fail fast',
    () async {
      final first = StateError('FIXTURE_ASSERTION');
      final lifecycle = GatewayQuotaLifecycle(recorder(), 'server-admitted16');
      final order = <String>[];
      Future<void> close(String name) async {
        order.add(name);
        expect(read()?.phase, 'server-admitted16');
        throw StateError(name);
      }

      final result = await outcome(
        () => lifecycle.run(
          body: () => lifecycle.run(
            body: () async => throw first,
            cleanup: () => lifecycle.run(
              body: () => close('channel'),
              cleanup: () async {
                await close('router');
                order.add('must-not-run');
              },
              cleanupPhase: 'server-cleanup',
            ),
            cleanupPhase: 'server-cleanup',
          ),
          cleanup: () => close('scenario'),
          cleanupPhase: 'scenario-cleanup',
        ),
      );
      expect(
        (result!.$1 as OwnedFixtureFailure).primary,
        isA<OwnedFixtureFailure>(),
      );
      expect(order, ['channel', 'router', 'scenario']);
      expect(
        formatGatewayQuotaFailure(result.$1, result.$2),
        startsWith('$first\n'),
      );
    },
  );

  test('actual aggregate formatter puts primary throw stack before all secondaries', () async {
    final first = StateError('PRIMARY_PRIVATE');
    final stack = StackTrace.fromString(
      List.generate(10, (i) => 'PRIMARY_FRAME_$i').join('\n'),
    );
    final result = await outcome(
      () => runOwnedFixtureLifecycle(
        body: () => runOwnedFixtureLifecycle(
          body: () async => Error.throwWithStackTrace(first, stack),
          cleanup: () async => Error.throwWithStackTrace(
            StateError('INNER_PRIVATE'),
            StackTrace.fromString('INNER_FRAME'),
          ),
        ),
        cleanup: () async => Error.throwWithStackTrace(
          StateError('OUTER_PRIVATE'),
          StackTrace.fromString('OUTER_FRAME'),
        ),
      ),
    );
    final formatted = formatGatewayQuotaFailure(result!.$1, result.$2);
    final split = formatted.split('\nGATEWAY_QUOTA_SECONDARY_FAILURE:\n');
    expect(split.length, 2);
    expect(
      split.first,
      '$first\n${stack.toString().split('\n').take(8).join('\n')}',
    );
    expect(split.last, contains('INNER_PRIVATE'));
    expect(split.last, contains('INNER_FRAME'));
    expect(split.last, contains('OUTER_PRIVATE'));
    expect(split.last, contains('OUTER_FRAME'));
    expect(split.first, isNot(contains('PRIMARY_FRAME_8')));
    expect(formatGatewayQuotaFailure(first, stack), split.first);
  });

  for (final aggregate in [false, true]) {
    test(
      'causal formatter caps original boundary stack aggregate=$aggregate',
      () async {
        recorder(GatewayQuotaFailureRole.bridge)
            .record('bridge-admission', StateError('RESOURCE_LIMIT'));
        final boundaryError = StateError('CAUSAL_BOUNDARY_PRIVATE');
        final frames = List.generate(12, (i) => 'CAUSAL_FRAME_$i');
        final boundaryStack = StackTrace.fromString(frames.join('\n'));
        final promotion = await outcome(() async {
          checkGatewayQuotaBridgeBoundary(
            root.path,
            causal: true,
            check: () =>
                Error.throwWithStackTrace(boundaryError, boundaryStack),
          );
        });
        final promoted = promotion!.$1 as GatewayQuotaBridgeFailure;
        expect(promoted.record.phase, 'bridge-admission');
        expect(promoted.record.code, 'RESOURCE_LIMIT');
        expect(promoted.boundaryError, same(boundaryError));
        expect(promoted.boundaryStack, same(boundaryStack));
        expect(promotion.$2, same(boundaryStack));

        final innerError = StateError('CAUSAL_INNER_SECONDARY');
        final innerStack = StackTrace.fromString(
          'CAUSAL_INNER_SECONDARY_STACK',
        );
        final outerError = StateError('CAUSAL_OUTER_SECONDARY');
        final outerStack = StackTrace.fromString(
          'CAUSAL_OUTER_SECONDARY_STACK',
        );
        final actual = aggregate
            ? (await outcome(
                () => runOwnedFixtureLifecycle(
                  body: () => runOwnedFixtureLifecycle(
                    body: () async =>
                        Error.throwWithStackTrace(promoted, boundaryStack),
                    cleanup: () async =>
                        Error.throwWithStackTrace(innerError, innerStack),
                  ),
                  cleanup: () async =>
                      Error.throwWithStackTrace(outerError, outerStack),
                ),
              ))!
            : promotion;
        if (aggregate) {
          final outer = actual.$1 as OwnedFixtureFailure;
          final inner = outer.primary as OwnedFixtureFailure;
          expect(inner.primary, same(promoted));
          expect(inner.primaryStack, same(boundaryStack));
          expect(inner.secondary, same(innerError));
          expect(inner.secondaryStack, same(innerStack));
          expect(outer.secondary, same(outerError));
          expect(outer.secondaryStack, same(outerStack));
        }
        final formatted = formatGatewayQuotaFailure(actual.$1, actual.$2);
        final parts = formatted.split('\nGATEWAY_QUOTA_SECONDARY_FAILURE:\n');
        expect(parts.length, aggregate ? 2 : 1);
        expect(parts.first.split('\n'), [
          '$boundaryError',
          'CAUSAL_FRAME_0',
          'CAUSAL_FRAME_1',
          'CAUSAL_FRAME_2',
          'CAUSAL_FRAME_3',
          'CAUSAL_FRAME_4',
          'CAUSAL_FRAME_5',
          'CAUSAL_FRAME_6',
          'CAUSAL_FRAME_7',
        ]);
        expect(RegExp('CAUSAL_FRAME_0').allMatches(parts.first).length, 1);
        for (final frame in frames.skip(8)) {
          expect(parts.first, isNot(contains(frame)));
        }
        if (aggregate) {
          expect(
            parts.last,
            '$innerError\n$innerStack\n$outerError\n$outerStack',
          );
        }
        // Formatting does not consume or rewrite the retained causal evidence.
        expect(promoted.boundaryError, same(boundaryError));
        expect(promoted.boundaryStack, same(boundaryStack));
        expect(promoted.boundaryStack.toString(), frames.join('\n'));
      },
    );
  }

  test('every role phase and safe code round trips exactly', () {
    expect(
      gatewayQuotaServerPhases.length + gatewayQuotaBridgePhases.length,
      17,
    );
    expect(gatewayQuotaFailureCodes.length, 10);
    for (final role in GatewayQuotaFailureRole.values) {
      final phases = role == GatewayQuotaFailureRole.server
          ? gatewayQuotaServerPhases
          : gatewayQuotaBridgePhases;
      for (final phase in phases) {
        for (final code in [...gatewayQuotaFailureCodes, null]) {
          recorder(role).record(phase, StateError(code ?? 'PRIVATE_UNKNOWN'));
          expect(read(role)?.phase, phase);
          expect(read(role)?.code, code);
          expect(
            recordFile(role).readAsBytesSync(),
            ascii.encode('1|$phase|${code ?? '-'}\n'),
          );
        }
      }
    }
  });

  test(
    'classification only accepts exact SDK or validated actor callback codes',
    () {
      final cases = <(Object, String?)>[
        (TimeoutException('PRIVATE'), 'TIMEOUT'),
        (StateError('TIMEOUT extra'), null),
        (StateError('EXPECTED_LIMIT'), null),
        (Object(), null),
      ];
      for (final entry in cases) {
        recorder().record('scenario-prepare', entry.$1);
        expect(read()?.code, entry.$2);
      }
      for (final entry in <(String? Function(Object), String?)>[
        ((_) => null, null),
        ((_) => 'PRIVATE', null),
        ((_) => throw StateError('private'), null),
        ((_) => 'FORBIDDEN', 'FORBIDDEN'),
      ]) {
        var invocations = 0;
        final writer = GatewayQuotaFailureRecorder(
          root.path,
          GatewayQuotaFailureRole.server,
          gatewayCodeOf: (error) {
            invocations++;
            return entry.$1(error);
          },
        );
        writer.record('scenario-prepare', Object());
        writer.record('server-cleanup', Object());
        expect(invocations, 1);
        expect(read()?.code, entry.$2);
      }
      final writer = GatewayQuotaFailureRecorder(
        root.path,
        GatewayQuotaFailureRole.server,
        gatewayCodeOf: (_) =>
            fail('unknown StateError must not call classifier'),
      );
      writer.record('scenario-prepare', StateError('private'));
      expect(read()?.code, null);
      // The actor owns production type mapping; pure helper has no such import.
      expect(
        actor.gatewayQuotaMcpCode(const McpGatewayFailure(ErrorCode.forbidden)),
        'FORBIDDEN',
      );
      expect(actor.gatewayQuotaMcpCode(StateError('FORBIDDEN')), null);
      for (final code in ErrorCode.values) {
        final writer = GatewayQuotaFailureRecorder(
          root.path,
          GatewayQuotaFailureRole.server,
          gatewayCodeOf: actor.gatewayQuotaMcpCode,
        );
        writer.record('server-bootstrap', McpGatewayFailure(code));
        expect(
          read()?.code,
          gatewayQuotaFailureCodes.contains(code.wireName)
              ? code.wireName
              : null,
        );
      }
    },
  );

  test('one attempt includes role refusal and failed writes', () {
    for (final role in GatewayQuotaFailureRole.values) {
      final file = recordFile(role);
      final writer = recorder(role);
      writer.record(
        role == GatewayQuotaFailureRole.server
            ? 'bridge-admission'
            : 'server-prepare',
        StateError('TIMEOUT'),
      );
      writer.record(
        role == GatewayQuotaFailureRole.server
            ? 'server-prepare'
            : 'bridge-bootstrap',
        StateError('TIMEOUT'),
      );
      expect(file.existsSync(), false);
      Directory(file.path).createSync();
      final failed = recorder(role);
      failed.record(
        role == GatewayQuotaFailureRole.server
            ? 'server-prepare'
            : 'bridge-bootstrap',
        StateError('TIMEOUT'),
      );
      Directory(file.path).deleteSync();
      failed.record(
        role == GatewayQuotaFailureRole.server
            ? 'server-prepare'
            : 'bridge-bootstrap',
        StateError('TIMEOUT'),
      );
      expect(file.existsSync(), false);
    }
  });

  test(
    'reader refuses malformed partial ASCII version role and size inputs',
    () {
      final invalid = <List<int>>[
        [],
        ascii.encode('1|server-prepare|-'),
        ascii.encode('1|server-prepare|-\r\n'),
        ascii.encode('2|server-prepare|-\n'),
        ascii.encode('1|unknown|-\n'),
        ascii.encode('1|server-prepare|INTERNAL\n'),
        ascii.encode('1|server-prepare|TIMEOUT\nextra'),
        ascii.encode('1|server-prepare|TIMEOUT\n\n'),
        [239, 187, 191, ...ascii.encode('1|server-prepare|-\n')],
        [...ascii.encode('1|server-prepare|-'), 255, 10],
        List.filled(128, 65),
        List.filled(129, 65),
        List.filled(1024, 65),
      ];
      expect(read(), null);
      final file = recordFile(GatewayQuotaFailureRole.server);
      for (final bytes in invalid) {
        file.writeAsBytesSync(bytes);
        expect(read(), null, reason: 'invalid bytes length ${bytes.length}');
      }
      file.deleteSync();
      Directory(file.path).createSync();
      expect(read(), null);
      recordFile(GatewayQuotaFailureRole.bridge)
          .writeAsStringSync('1|server-prepare|-\n');
      expect(read(GatewayQuotaFailureRole.bridge), null);
    },
  );

  test('causal EOF boundary promotes valid bridge and retains boundary object stack', () async {
    recorder(GatewayQuotaFailureRole.bridge)
        .record('bridge-admission', StateError('RESOURCE_LIMIT'));
    final stream = StreamController<String>();
    final lines = StreamIterator(stream.stream);
    final moved = lines.moveNext();
    await stream.close();
    final hasLine = await moved;
    final error = StateError('FIXTURE_ASSERTION');
    final stack = StackTrace.fromString('EOF_BOUNDARY');
    final result = await outcome(() async {
      checkGatewayQuotaBridgeBoundary(
        root.path,
        causal: !hasLine,
        check: () => Error.throwWithStackTrace(error, stack),
      );
    });
    final promoted = result!.$1 as GatewayQuotaBridgeFailure;
    expect(promoted.record.phase, 'bridge-admission');
    expect(promoted.record.code, 'RESOURCE_LIMIT');
    expect(promoted.boundaryError, same(error));
    expect(promoted.boundaryStack, same(stack));
    expect(result.$2, same(stack));
    recorder().record('server-admitted16', promoted);
    expect(read()?.phase, 'bridge-admission');
    expect(read()?.code, 'RESOURCE_LIMIT');
    await lines.cancel();
  });

  test(
    'only already observed EOF nonzero exit and nonempty stderr promote',
    () async {
      for (final failed in [false, true]) {
        recorder(GatewayQuotaFailureRole.bridge)
            .record('bridge-cancellation', StateError('TIMEOUT'));
        final actualExit = Completer<int>();
        final result = outcome(() async {
          final code = await actualExit.future;
          checkGatewayQuotaBridgeBoundary(
            root.path,
            causal: code != 0,
            check: () => check(code == 0),
          );
        });
        actualExit.complete(failed ? 1 : 0);
        expect(
          (await result)?.$1,
          failed ? isA<GatewayQuotaBridgeFailure>() : null,
        );
        final alreadyAwaitedErrors = Completer<String>();
        final stderrResult = outcome(() async {
          final diagnostics = await alreadyAwaitedErrors.future;
          checkGatewayQuotaBridgeBoundary(
            root.path,
            causal: diagnostics.isNotEmpty,
            check: () => check(diagnostics.isEmpty),
          );
        });
        alreadyAwaitedErrors.complete(failed ? 'PRIVATE_BRIDGE_STDERR' : '');
        expect(
          (await stderrResult)?.$1,
          failed ? isA<GatewayQuotaBridgeFailure>() : null,
        );
      }
      final error = StateError('FIXTURE_ASSERTION');
      final stack = StackTrace.fromString('INDEPENDENT');
      final result = await outcome(
        () async => checkGatewayQuotaBridgeBoundary(
          root.path,
          causal: false,
          check: () => Error.throwWithStackTrace(error, stack),
        ),
      );
      expect(result!.$1, same(error));
      expect(result.$2, same(stack));
      recordFile(GatewayQuotaFailureRole.bridge).deleteSync();
      final absent = await outcome(
        () async => checkGatewayQuotaBridgeBoundary(
          root.path,
          causal: true,
          check: () => Error.throwWithStackTrace(error, stack),
        ),
      );
      expect(absent!.$1, same(error));
      expect(absent.$2, same(stack));
      recorder(GatewayQuotaFailureRole.bridge)
          .record('bridge-cleanup', StateError('TIMEOUT'));
      recorder().record('server-quota-oracle', error);
      expect(read()?.phase, 'server-quota-oracle');
      expect(read()?.code, 'FIXTURE_ASSERTION');
    },
  );

  test('wrong line stream error timeout and late file keep independent first failure', () async {
    for (final error in [
      StateError('FIXTURE_ASSERTION'),
      StateError('STREAM'),
      TimeoutException('private'),
    ]) {
      final writer = recorder();
      final lifecycle = GatewayQuotaLifecycle(writer, 'server-admitted16');
      final result = await outcome(
        () => lifecycle.run(
          body: () async {
            if (error is StateError && error.message == 'FIXTURE_ASSERTION') {
              final lines = StreamIterator(Stream.value('WRONG'));
              final moved = await lines.moveNext();
              try {
                checkGatewayQuotaBridgeBoundary(
                  root.path,
                  causal: !moved,
                  check: () => check(moved && lines.current == 'ADMITTED16'),
                );
              } finally {
                await lines.cancel();
              }
            } else {
              final lines = StreamIterator<String>(Stream.error(error));
              try {
                await lines.moveNext();
              } finally {
                await lines.cancel();
              }
            }
          },
          cleanup: () async {
            expect(read()?.phase, 'server-admitted16');
            recorder(GatewayQuotaFailureRole.bridge)
                .record('bridge-cleanup', StateError('TIMEOUT'));
            throw StateError('LATE_CLEANUP');
          },
          cleanupPhase: 'server-cleanup',
        ),
      );
      expect(result!.$1, isA<OwnedFixtureFailure>());
      expect(read()?.phase, 'server-admitted16');
      expect(
        read()?.code,
        error is TimeoutException
            ? 'TIMEOUT'
            : (error as StateError).message == 'FIXTURE_ASSERTION'
            ? 'FIXTURE_ASSERTION'
            : null,
      );
    }
  });

  test('outer early observer records setup and cannot overwrite body or refused attempt', () async {
    final lifecycle = GatewayQuotaLifecycle(recorder(), 'scenario-prepare');
    lifecycle.observe(StateError('TIMEOUT'), StackTrace.current);
    expect(read()?.phase, 'scenario-prepare');
    lifecycle.phase = 'scenario-cleanup';
    lifecycle.observe(StateError('FIXTURE_ASSERTION'), StackTrace.current);
    expect(read()?.code, 'TIMEOUT');
    final file = recordFile(GatewayQuotaFailureRole.server)..deleteSync();
    Directory(file.path).createSync();
    final refused = GatewayQuotaLifecycle(recorder(), 'scenario-prepare');
    refused.observe(StateError('TIMEOUT'), StackTrace.current);
    Directory(file.path).deleteSync();
    refused.observe(StateError('FORBIDDEN'), StackTrace.current);
    expect(read(), null);
    expect(
      gatewayQuotaReasonPrefix(root.path),
      'GATEWAY_QUOTA_PRIVATE_OUTPUT:\n',
    );
  });

  test(
    'parent prefix only trusts server record and always delimits raw output',
    () {
      recorder(GatewayQuotaFailureRole.bridge)
          .record('bridge-admission', StateError('TIMEOUT'));
      expect(
        gatewayQuotaReasonPrefix(root.path),
        'GATEWAY_QUOTA_PRIVATE_OUTPUT:\n',
      );
      recorder().record('server-admitted16', StateError('FIXTURE_ASSERTION'));
      expect(
        gatewayQuotaReasonPrefix(root.path),
        'GATEWAY_QUOTA_FIXTURE_FAILURE:server-admitted16:FIXTURE_ASSERTION\nGATEWAY_QUOTA_PRIVATE_OUTPUT:\n',
      );
    },
  );
  test(
    'reader uses one handle 129 byte cap length rereads and always closes',
    () {
      final valid = ascii.encode('1|server-prepare|TIMEOUT\n');
      for (final variant in [
        'valid',
        'handle-growth',
        'named-growth',
        'partial',
        '128',
        '129',
      ]) {
        final bytes = variant == '128'
            ? List.filled(128, 65)
            : variant == '129'
            ? List.filled(129, 65)
            : valid;
        final before = variant == 'partial' ? valid.length + 1 : bytes.length;
        final handle = ControlledRecordHandle(bytes, [
          before,
          variant == 'handle-growth' ? before + 1 : before,
        ]);
        final file = ControlledRecordFile(
          handle,
          variant == 'named-growth' ? before + 1 : before,
        );
        final result = IOOverrides.runZoned(
          () => read(),
          createFile: (_) => file,
        );
        expect(
          result?.code,
          variant == 'valid' ? 'TIMEOUT' : null,
          reason: variant,
        );
        expect(file.opens, 1);
        expect(handle.closeCalls, 1);
        expect(handle.readCalls, variant == '129' ? 0 : 1);
        expect(handle.readLimit, variant == '129' ? null : 129);
        if (variant == 'valid' || variant == 'named-growth')
          expect(handle.lengthCalls, 2);
      }
    },
  );
  for (final names in [
    ['gate', 'registry', 'worker'],
    ['commands', 'pipe', 'outer'],
  ]) {
    test(
      'nested ${names.join('/')} preserves first cleanup before later boundaries',
      () async {
        final bridge = names.first == 'commands';
        final role = bridge
            ? GatewayQuotaFailureRole.bridge
            : GatewayQuotaFailureRole.server;
        final phase = bridge ? 'bridge-cleanup' : 'server-cleanup';
        final lifecycle = GatewayQuotaLifecycle(recorder(role), phase);
        final first = StateError('TIMEOUT');
        final stack = StackTrace.fromString('FIRST_CLEANUP');
        final order = <String>[];
        Future<void> close(int index) async {
          order.add(names[index]);
          if (index == 0) Error.throwWithStackTrace(first, stack);
          expect(read(role)?.phase, phase);
          expect(read(role)?.code, 'TIMEOUT');
          throw StateError('SECONDARY_${names[index]}');
        }

        final result = await outcome(
          () => lifecycle.run(
            body: () => lifecycle.run(
              body: () => close(0),
              cleanup: () => close(1),
              cleanupPhase: phase,
            ),
            cleanup: () => close(2),
            cleanupPhase: phase,
          ),
        );
        final outer = result!.$1 as OwnedFixtureFailure;
        final inner = outer.primary as OwnedFixtureFailure;
        expect(inner.primary, same(first));
        expect(inner.primaryStack, same(stack));
        expect(result.$2, same(stack));
        expect(order, names);
      },
    );
  }

  test(
    'diagnostic write and classifier refusal preserve actual lifecycle outcome',
    () async {
      final file = recordFile(GatewayQuotaFailureRole.server);
      Directory(file.path).createSync();
      var classifiers = 0;
      final writer = GatewayQuotaFailureRecorder(
        root.path,
        GatewayQuotaFailureRole.server,
        gatewayCodeOf: (_) {
          classifiers++;
          throw StateError('CLASSIFIER_PRIVATE');
        },
      );
      final lifecycle = GatewayQuotaLifecycle(writer, 'scenario-prepare');
      final original = Object();
      final originalStack = StackTrace.fromString('ORIGINAL_THROW');
      var cleanups = 0;
      final result = await outcome(
        () => lifecycle.run(
          body: () async => Error.throwWithStackTrace(original, originalStack),
          cleanup: () async {
            cleanups++;
          },
          cleanupPhase: 'scenario-cleanup',
        ),
      );
      expect(result!.$1, same(original));
      expect(result.$2, same(originalStack));
      expect(cleanups, 1);
      expect(classifiers, 1);
      expect(read(), null);
    },
  );
}
