import 'dart:io';
import 'dart:math';

import 'package:serverdeck_windows/pipe.dart';
import 'package:serverdeck_windows/security.dart';

Future<NativePipe> connect(String name, String sid) async {
  final watch = Stopwatch()..start();
  while (true) {
    try {
      return NativePipe.openClient(name, sid);
    } on StateError catch (error) {
      if (error.message != 'SERVICE_UNAVAILABLE' ||
          watch.elapsed >= const Duration(seconds: 5))
        rethrow;
      // A reused slot becomes available when async native accept is issued.
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}

Future<void> main() async {
  final hash = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final name = '\\\\.\\pipe\\ServerDeckNext.v1.$hash.0';
  final sid = currentUserSid();
  final server = NativePipe.createServer(name, sid);
  NativePipe? client;
  try {
    final accepting = server.accept();
    client = await connect(name, sid);
    await accepting;
    stdout.writeln('DISCONNECT_FIXTURE_CONNECTED');
    await server.write([42]);
    var timedOut = false;
    try {
      await server.drainOutput(deadline: const Duration(milliseconds: 50));
    } on StateError catch (error) {
      if (error.message != 'TIMEOUT') rethrow;
      timedOut = true;
    }
    if (!timedOut) throw StateError('EXPECTED_DRAIN_TIMEOUT');
    final retained = await client.read();
    if (retained.length != 1 || retained.single != 42)
      throw StateError('OUTPUT_LOST');
    await server.drainOutput();
    await server.disconnect();
    stdout.writeln('DISCONNECT_FIXTURE_DISCONNECTED');
    var failed = false;
    try {
      await client.read();
    } on StateError catch (_) {
      failed = true;
    }
    if (!failed) throw StateError('EXPECTED_SAFE_IO_FAILURE');
    stdout.writeln('DISCONNECTED_READ_TERMINATED');
    await client.close();
    final nextAccept = server.accept();
    client = await connect(name, sid);
    await nextAccept;
    await server.write([43]);
    final drained = server.drainOutput();
    var limited = false;
    try {
      await server.drainOutput();
    } on StateError catch (error) {
      if (error.message != 'RESOURCE_LIMIT') rethrow;
      limited = true;
    }
    if (!limited) throw StateError('EXPECTED_DRAIN_LIMIT');
    final reused = await client.read();
    if (reused.length != 1 || reused.single != 43)
      throw StateError('REUSE_OUTPUT_LOST');
    await drained;
    await server.write([44]);
    final canceled = server.drainOutput().then(
      (_) => false,
      onError: (Object error) =>
          error is StateError && error.message == 'SERVICE_UNAVAILABLE',
    );
    await server.close();
    if (!await canceled) throw StateError('EXPECTED_CLOSE_CANCELLATION');
    stdout.writeln('PIPE_DRAIN_TIMEOUT_REUSE_CANCEL_PROVED');
  } finally {
    await client?.close();
    await server.close();
  }
}
