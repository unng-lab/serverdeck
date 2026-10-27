import 'dart:math';

import 'package:serverdeck_protocol/framing.dart';
import 'package:serverdeck_windows/pipe.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

void main() {
  test(
    'partial frame deadline reaches native cancellation before channel close',
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
      final deadlines = <Duration>[];
      try {
        final accept = server.accept();
        client = NativePipe.openClient(name, sid);
        await accept;
        final reader = FramedReader((deadline) {
          deadlines.add(deadline);
          return server.read(deadline: deadline);
        }, partialDeadline: const Duration(milliseconds: 120));
        final pending = reader.readFrame();
        final failed = expectLater(pending, throwsA(isA<StateError>()));
        await client.write([5]);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await client.write([0]);
        await failed;
        expect(deadlines.length, greaterThanOrEqualTo(3));
        expect(
          deadlines[1],
          lessThanOrEqualTo(const Duration(milliseconds: 120)),
        );
        expect(deadlines[2], lessThan(deadlines[1]));
        await server.close();
        await server.close();
        expect(currentUserSid(), sid);
      } finally {
        await client?.close();
        await server.close();
      }
    },
    testOn: 'windows',
  );
}
