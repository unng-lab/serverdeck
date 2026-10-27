import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  for (final kind in ['read', 'write', 'connect']) {
    test(
      '4000 $kind workloads finish deadline cancellation in an owned VM',
      () async {
        final child = await Process.start(
          p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe'),
          ['test/support/pipe_pending_child.dart', kind],
        );
        final output = child.stdout.transform(utf8.decoder).join();
        final errors = child.stderr.transform(utf8.decoder).join();
        try {
          expect(
            await child.exitCode.timeout(const Duration(seconds: 150)),
            0,
            reason: await errors.timeout(const Duration(seconds: 5)),
          );
          expect(
            await output.timeout(const Duration(seconds: 5)),
            contains('PENDING_IO_CANCELLED_AND_DRAINED'),
          );
        } finally {
          child.kill();
          await child.exitCode.timeout(const Duration(seconds: 10));
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 170)),
    );
  }
}
