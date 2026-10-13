import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('read after native disconnect fails promptly without waiting on an unissued event', () async {
    final child = await Process.start(
      p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe'),
      ['test/support/pipe_disconnected_child.dart'],
    );
    final output = child.stdout.transform(utf8.decoder).join();
    final errors = child.stderr.transform(utf8.decoder).join();
    try {
      expect(
        await child.exitCode.timeout(const Duration(seconds: 15)),
        0,
        reason: await errors,
      );
      final captured = await output.timeout(const Duration(seconds: 5));
      stdout.write(captured);
      expect(captured, contains('DISCONNECTED_READ_TERMINATED'));
      expect(captured, contains('PIPE_DRAIN_TIMEOUT_REUSE_CANCEL_PROVED'));
    } finally {
      child.kill();
      await child.exitCode.timeout(const Duration(seconds: 5));
      await output.timeout(const Duration(seconds: 5));
    }
  }, testOn: 'windows');
}
