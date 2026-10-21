import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:serverdeck_windows/pipe.dart';
import 'package:serverdeck_windows/security.dart';

Future<void> main() async {
  if (!const bool.fromEnvironment('serverdeck.test.delay-native-write'))
    throw StateError('PROBE_REQUIRED');
  final hash = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final server = NativePipe.createServer(
    '\\\\.\\pipe\\ServerDeckNext.v1.$hash.0',
    currentUserSid(),
  );
  NativePipe? client;
  try {
    final accepting = server.accept();
    client = NativePipe.openClient(
      '\\\\.\\pipe\\ServerDeckNext.v1.$hash.0',
      currentUserSid(),
    );
    await accepting;
    var drained = false;
    final writing = server.write(List.filled(1024 * 1024, 42));
    writing.ignore();
    final draining = server.drainOutput().then((_) => drained = true);
    draining.ignore();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final premature = drained;
    var received = 0;
    while (received < 1024 * 1024) {
      final bytes = await client.read(count: 65536);
      if (bytes.isEmpty || bytes.any((b) => b != 42))
        throw StateError('BAD_PAYLOAD');
      received += bytes.length;
    }
    await writing;
    await draining;
    if (premature || !drained) throw StateError('PREMATURE_DRAIN');
    stdout.writeln('ACCEPTED_WRITE_DRAIN_PROVED');
  } finally {
    await client?.close();
    await server.close();
  }
}
