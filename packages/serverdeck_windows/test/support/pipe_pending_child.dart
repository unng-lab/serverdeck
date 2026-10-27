import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:serverdeck_windows/pipe.dart';
import 'package:serverdeck_windows/security.dart';

String _name() =>
    '\\\\.\\pipe\\ServerDeckNext.v1.${List.generate(32, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}.0';

Future<void> _exercise(String kind) async {
  final sid = currentUserSid();
  for (var index = 0; index < 1000; index++) {
    final name = _name();
    final server = NativePipe.createServer(name, sid);
    NativePipe? client;
    try {
      if (kind != 'connect') {
        final accepted = server.accept();
        client = NativePipe.openClient(name, sid);
        await accepted;
      }
      try {
        const deadline = Duration(milliseconds: 2);
        // With async issuance, these workloads cover cancellation both before
        // and after native queueing; the count is not a queued-IRP count.
        if (kind == 'read') {
          await server.read(deadline: deadline);
        } else if (kind == 'write') {
          await server.write(Uint8List(1024 * 1024), deadline: deadline);
        } else {
          await server.accept(deadline: deadline);
        }
        stderr.writeln('UNEXPECTED_COMPLETION_$kind');
        exit(3);
      } on StateError catch (error) {
        if (error.message != 'TIMEOUT') {
          stderr.writeln('UNEXPECTED_IO_STATUS_$kind');
          // This is an owned disposable VM; abort instead of continuing after
          // an unsafe old implementation might have freed pending IO memory.
          exit(3);
        }
      }
    } finally {
      await client?.close();
      await server.close();
    }
  }
}

Future<void> main(List<String> arguments) async {
  await Future.wait(
    List.generate(4, (_) => Isolate.run(() => _exercise(arguments.single))),
  );
  stdout.writeln('PENDING_IO_CANCELLED_AND_DRAINED');
}
