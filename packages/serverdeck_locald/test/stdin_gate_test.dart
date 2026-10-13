import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/vm_debugger.dart';

void main() {
  test(
    'EOF completes one-command gate without forcing child exit',
    () async {
      for (var attempt = 0; attempt < 12; attempt++) {
        final vm = p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe');
        final child = await Process.start(vm, [
          '--enable-vm-service=0',
          'test/support/stdin_gate_child.dart',
        ]);
        VmDebugger? debugger;
        var exited = false;
        final uri = Completer<Uri>(),
            waiting = Completer<void>(),
            returned = Completer<void>();
        final log = <String>[];
        final output = child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((value) {
              log.add(value);
              final match = RegExp(r'http://127\.0\.0\.1:\d+/[^ ]*/')
                  .firstMatch(value);
              if (match != null && !uri.isCompleted)
                uri.complete(Uri.parse(match.group(0)!));
              if (value == 'WAITING_FOR_DEBUGGER' && !waiting.isCompleted)
                waiting.complete();
              if (value == 'VERIFIER_MAIN_RETURNING' && !returned.isCompleted)
                returned.complete();
            });
        final errors = child.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(log.add);
        try {
          await waiting.future.timeout(const Duration(seconds: 10));
          debugger = await VmDebugger.connect(
            await uri.future.timeout(const Duration(seconds: 10)),
          );
          child.stdin.writeln('start');
          await child.stdin.flush();
          await child.stdin.close();
          await returned.future.timeout(const Duration(seconds: 10));
          try {
            expect(await child.exitCode.timeout(const Duration(seconds: 2)), 0);
            exited = true;
          } on TimeoutException {
            await debugger.reportTimeout(log);
            rethrow;
          }
        } finally {
          await child.stdin.close();
          if (!exited) child.kill();
          await child.exitCode.timeout(const Duration(seconds: 10));
          await debugger?.close();
          await output.cancel();
          await errors.cancel();
        }
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 100)),
  );
}
