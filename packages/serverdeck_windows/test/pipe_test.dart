import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:serverdeck_windows/pipe.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

void main() {
  test('drain waits across delayed native write issuance', () async {
    final child = await Process.start(
      p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe'),
      [
        '-Dserverdeck.test.delay-native-write=true',
        'test/support/pipe_drain_issuance_child.dart',
      ],
    );
    final output = child.stdout.transform(utf8.decoder).join();
    final errors = child.stderr.transform(utf8.decoder).join();
    try {
      expect(
        await child.exitCode.timeout(const Duration(seconds: 15)),
        0,
        reason: await errors,
      );
      expect(await output, contains('ACCEPTED_WRITE_DRAIN_PROVED'));
    } finally {
      child.kill();
      await child.exitCode.timeout(const Duration(seconds: 5));
    }
  }, testOn: 'windows');
  test('drain includes an accepted write before its native issuance', () async {
    final hash = List.generate(
      32,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final name = '\\\\.\\pipe\\ServerDeckNext.v1.$hash.0';
    final sid = currentUserSid(), server = NativePipe.createServer(name, sid);
    NativePipe? client;
    try {
      final accepting = server.accept();
      client = NativePipe.openClient(name, sid);
      await accepting;
      var drained = false;
      final write = server.write(List.filled(1024 * 1024, 42));
      write.ignore();
      final drain = server.drainOutput().then((_) => drained = true);
      drain.ignore();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final premature = drained;
      var received = 0;
      while (received < 1024 * 1024) {
        final bytes = await client.read(count: 65536);
        expect(bytes, everyElement(42));
        received += bytes.length;
      }
      await write;
      await drain;
      expect(
        premature,
        false,
        reason: 'No peer consumed the accepted write yet',
      );
      expect(drained, true);
    } finally {
      await client?.close();
      await server.close();
    }
  }, testOn: 'windows');
  test(
    'actually queued reads complete cancellation before pipe reuse',
    () async {
      final hash = List.generate(
        32,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final name = '\\\\.\\pipe\\ServerDeckNext.v1.$hash.0';
      final sid = currentUserSid();
      final server = NativePipe.createServer(name, sid);
      NativePipe? client;
      try {
        final accepted = server.accept(deadline: const Duration(seconds: 5));
        client = NativePipe.openClient(name, sid);
        await accepted;
        for (var iteration = 0; iteration < 100; iteration++) {
          final pending = server.read(deadline: const Duration(seconds: 10));
          final assertion = expectLater(pending, throwsStateError);
          final issuanceBudget = Stopwatch()..start();
          // No peer writes: require successful cancellation of the queued read,
          // unlike a short Dart timer that can expire before native issuance.
          // A false BOOL can precede issuance; do not classify its TLS error
          // obtained by a separate FFI call. Persistent failure hits the budget.
          while (true) {
            final cancelled = CancelIoEx(server.handle, null);
            if (cancelled.value) break;
            expect(
              issuanceBudget.elapsed,
              lessThan(const Duration(seconds: 5)),
            );
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          await assertion.timeout(const Duration(seconds: 5));
          final reused = server.read(deadline: const Duration(seconds: 5));
          await client.write([iteration]);
          expect(await reused, [iteration]);
        }
      } finally {
        await client?.close();
        await server.close();
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'single instance duplex pipe, kernel identity and cancellation completion',
    () async {
      final random = Random.secure();
      final hash = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final name = '\\\\.\\pipe\\ServerDeckNext.v1.$hash.0';
      final sid = currentUserSid();
      final server = NativePipe.createServer(name, sid);
      NativePipe? client;
      try {
        expect(
          () => NativePipe.createServer(name, sid),
          throwsA(isA<StateError>()),
        );
        final accepted = server.accept(deadline: const Duration(seconds: 5));
        client = NativePipe.openClient(name, sid);
        await accepted;
        expect(server.peerIdentity().pid, pid);
        expect(client.peerIdentity().sid, sid);
        final read = server.read();
        await client.write([1, 2, 3]);
        expect(await read, [1, 2, 3]);
        final response = client.read();
        await server.write([4, 5]);
        expect(await response, [4, 5]);
        await expectLater(
          server.read(deadline: const Duration(milliseconds: 20)),
          throwsA(isA<StateError>()),
        );
        final pending = server.read();
        final asserted = expectLater(pending, throwsA(isA<StateError>()));
        await server.close();
        await asserted;
        await server.close();
      } finally {
        await client?.close();
        await server.close();
      }
    },
    testOn: 'windows',
  );
}
