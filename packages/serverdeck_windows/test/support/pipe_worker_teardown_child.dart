import 'dart:io';
import 'dart:math';

import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

Future<bool> canceled(Future<Object?> operation) => operation.then(
  (_) => false,
  onError: (Object error) =>
      error is StateError && error.message == 'SERVICE_UNAVAILABLE',
);

Future<PipeWorker> connectWhenListening(String name, String sid) async {
  final elapsed = Stopwatch()..start();
  var delay = const Duration(milliseconds: 100);
  const budget = Duration(seconds: 5);
  while (true) {
    try {
      return await PipeWorker.openClient(name, sid);
    } on StateError catch (error) {
      if (error.message != 'SERVICE_UNAVAILABLE') rethrow;
      final remaining = budget - elapsed.elapsed;
      if (remaining <= Duration.zero) rethrow;
      await Future<void>.delayed(remaining < delay ? remaining : delay);
      delay = Duration(milliseconds: min(delay.inMilliseconds * 2, 1000));
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
  final server = await PipeWorker.createServer(name, sid);
  PipeWorker? client;
  try {
    final accepting = server.accept(deadline: const Duration(seconds: 5));
    accepting.ignore();
    client = await connectWhenListening(name, sid);
    await accepting;
    final read = canceled(server.read());
    final write = canceled(server.write(List.filled(1024 * 1024, 42)));
    final drain = canceled(server.drainOutput());
    stdout.writeln('WORKER_THREE_IO_ADMITTED');
    var limited = false;
    try {
      await server.read();
    } on StateError catch (error) {
      if (error.message != 'RESOURCE_LIMIT') rethrow;
      limited = true;
    }
    if (!limited) throw StateError('ORDINARY_QUOTA_NOT_ENFORCED');
    final disconnect = server.disconnect();
    if (!identical(disconnect, server.disconnect()))
      throw StateError('DUPLICATE_DISCONNECT');
    var stopping = false;
    try {
      await server.read();
    } on StateError catch (error) {
      if (error.message != 'SERVICE_UNAVAILABLE') rethrow;
      stopping = true;
    }
    if (!stopping) throw StateError('IO_ADMITTED_DURING_DISCONNECT');
    await disconnect;
    stdout.writeln('WORKER_DISCONNECT_COMPLETED');
    if (!await read || !await write || !await drain)
      throw StateError('EXPECTED_CANCELED_IO');
    await client.close();
    stdout.writeln('WORKER_OLD_CLIENT_CLOSED');
    final reused = server.accept(deadline: const Duration(seconds: 5));
    reused.ignore();
    stdout.writeln('WORKER_REACCEPT_REQUESTED');
    client = await connectWhenListening(name, sid);
    stdout.writeln('WORKER_REUSE_CLIENT_OPENED');
    await reused;
    stdout.writeln('WORKER_REACCEPT_COMPLETED');
    final input = server.read();
    await client.write([99]);
    final bytes = await input;
    if (bytes.length != 1 || bytes.single != 99)
      throw StateError('REUSE_FAILED');
    await server.disconnect();
    stdout.writeln('WORKER_FULL_IO_DISCONNECT_REUSE_PROVED');
  } finally {
    await client?.close();
    await server.close();
  }
}
