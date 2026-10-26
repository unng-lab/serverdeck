import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mcp_build_bundle_test.dart' as b;
import 'support/owned_fixture_cleanup.dart';

void main() {
  group(
    'compiled disconnected pipe',
    () {
      late Directory root;
      late String executable;
      setUpAll(() async {
        root = Directory.systemTemp.createTempSync(
          'serverdeck-mcp-bundle-disconnect-',
        );
        b.ownRoot(root.path);
        executable = p.join(root.path, 'disconnect.exe');
        // Compile before the behavioral watchdog. Source startup and cold JIT
        // must not consume the budget for the actual native regression scenario.
        await b.compilePeer(
          executable,
          source: 'test/support/pipe_disconnected_child.dart',
        );
      });
      tearDownAll(() async {
        await deleteOwnedFixtureDirectory(root);
      });
      test('read after native disconnect fails promptly without waiting on an unissued event', () async {
        final child = await Process.start(executable, []);
        var phase = 'started';
        final output = child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .map((line) {
              phase = switch (line) {
                'DISCONNECT_FIXTURE_CONNECTED' => 'connected',
                'DISCONNECT_FIXTURE_DISCONNECTED' => 'disconnected',
                'DISCONNECTED_READ_TERMINATED' => 'read-terminated',
                'PIPE_DRAIN_TIMEOUT_REUSE_CANCEL_PROVED' =>
                  'reuse-cancel-proved',
                _ => phase,
              };
              return '$line\n';
            })
            .join();
        final errors = b.boundedOutput(child.stderr);
        try {
          expect(
            await child.exitCode.timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw TimeoutException(
                'DISCONNECT_FIXTURE_TIMEOUT:$phase',
                const Duration(seconds: 15),
              ),
            ),
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
      }, timeout: const Timeout(Duration(seconds: 30)));
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
