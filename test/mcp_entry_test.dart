import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/entry_mode.dart';
import 'package:serverdeck/platform/mcp_entry.dart';
import 'package:serverdeck_mcp/stdio_port.dart';

final class Port implements McpStdioPort {
  @override
  Future<void> get ready => Future.value();
  @override
  Stream<List<int>> get input => const Stream.empty();
  @override
  Future<void> write(List<int> bytes) async => throw StateError('UNEXPECTED');
  @override
  void diagnostic(String code) => throw StateError('UNEXPECTED');
  @override
  Future<void> flushDiagnostics() async => throw StateError('UNEXPECTED');
  @override
  Future<void> close() async => throw StateError('MUST_NOT_REJOIN');
}

void main() {
  test(
    'dispatch empty argv only creates app and keeps its event loop',
    () async {
      var app = 0, stdio = 0;
      final code = await dispatchServerDeck(
        [],
        application: () => app++,
        stdio: (_) async {
          stdio++;
          return 1;
        },
      );
      expect(code, isNull);
      expect([app, stdio], [1, 0]);
    },
  );

  test(
    'stdio dispatch forwards grant once without any application side effect',
    () async {
      const grant = '12345678-1234-4234-9234-123456789abc';
      for (final id in [null, grant]) {
        var calls = 0;
        final actual = Completer<int>();
        final pending = dispatchServerDeck(
          [
            '--mcp-stdio',
            if (id != null) ...['--grant-id', id],
          ],
          application: () => fail('UI/Host/diagnostics branch'),
          stdio: (value) {
            calls++;
            expect(value, id);
            return actual.future;
          },
        );
        expect(calls, 1);
        actual.complete(2);
        expect(await pending, 2);
        expect(calls, 1);
      }
    },
  );

  test('invalid argv exits locally before either factory', () async {
    for (final args in [
      ['--locald'],
      ['--mcp-stdio', '--owner'],
      ['--mcp-stdio', '--grant-id', 'private invalid UUID'],
    ]) {
      expect(
        await dispatchServerDeck(
          args,
          application: () => fail('invalid app branch'),
          stdio: (_) async => fail('invalid stdio branch'),
        ),
        64,
      );
    }
  });

  test(
    'owned connector propagates terminal code without joining cleanup again',
    () async {
      final port = Port();
      var creates = 0, runs = 0;
      expect(
        await runOwnedMcp(
          create: () {
            creates++;
            return port;
          },
          run: (value) async {
            runs++;
            expect(identical(value, port), isTrue);
            return 2;
          },
        ),
        2,
      );
      expect([creates, runs], [1, 1]);
    },
  );

  test(
    'factory and runner failures become fixed nonzero exit, never retry',
    () async {
      var creates = 0;
      expect(
        await runOwnedMcp(
          create: () {
            creates++;
            throw StateError('private exception');
          },
          run: (_) async => fail('failed factory'),
        ),
        1,
      );
      expect(creates, 1);
      expect(
        await runOwnedMcp(
          create: Port.new,
          run: (_) async => throw StateError('private exception'),
        ),
        1,
      );
      expect(await runOwnedMcp(create: Port.new, run: (_) async => 256), 1);
    },
  );

  test('zone drops print and uncaught async fault retires connector', () async {
    final prints = <String>[];
    final int? code = await runZoned<Future<int>>(
      () => runOwnedMcp(
        create: Port.new,
        run: (_) {
          // Exercise the actual Zone print interception, not a logging wrapper.
          // ignore: avoid_print
          print('private value');
          scheduleMicrotask(
            () => throw StateError('private asynchronous fault'),
          );
          return Completer<int>().future;
        },
      ),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => prints.add(line),
      ),
    );
    expect(code, 1);
    expect(prints, isEmpty);
  });
}
