import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('worker disconnect cancels read/write/drain at full capacity and reuses the slot', () async {
    final child = await Process.start(
      p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe'),
      ['test/support/pipe_worker_teardown_child.dart'],
    );
    final output = child.stdout.transform(utf8.decoder).join();
    final errors = child.stderr.transform(utf8.decoder).join();
    try {
      expect(
        await child.exitCode.timeout(const Duration(seconds: 20)),
        0,
        reason: await errors,
      );
      expect(await output, contains('WORKER_FULL_IO_DISCONNECT_REUSE_PROVED'));
    } finally {
      child.kill();
      await child.exitCode.timeout(const Duration(seconds: 5));
    }
  }, testOn: 'windows');
}
