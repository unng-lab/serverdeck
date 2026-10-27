import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import 'support/trusted_client_completion.dart';
import 'support/trusted_client_fixture.dart';

/// Real stdin/EOF/process tests. This is not an I/O-postverify hook or a
/// reproduction of the historical CI failure.
Future<void> withChild(
  String mode,
  Future<void> Function(
    Process child,
    TrustedClientCompletion completion,
    Future<void> ready,
  )
  body,
) async {
  final root = Directory.systemTemp.createTempSync(
    'trusted-client-completion-',
  );
  Process? owned;
  TrustedClientCompletion? capture;
  await runOwnedFixtureLifecycle(
    body: () async {
      final helper = File('test/support/trusted_client_completion.dart')
          .absolute
          .uri;
      final source = File(p.join(root.path, 'child.dart'));
      source.writeAsStringSync('''
import 'dart:io';
import '$helper';
Future<void> main(List<String> args) async {
  if (args.single == 'early') {
    stdout.write('EARLY_EXIT\\n');
    await stdout.flush();
    return;
  }
  if (args.single == 'oversize') {
    stdout.add(List.filled(16385, 65));
    await stdout.flush();
    return;
  }
  stdout.writeln('CLIENT_PASS');
  await finishTrustedClientProcess();
}
''');
      final child = await Process.start(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        source.path,
        mode,
      ]);
      owned = child;
      final ready = Completer<void>();
      final observed = <int>[];
      final completion = TrustedClientCompletion(
        output: child.stdout.map((bytes) {
          if (observed.length + bytes.length <= 16384) observed.addAll(bytes);
          if (!ready.isCompleted &&
              ascii
                  .decode(observed, allowInvalid: true)
                  .split('\n')
                  .contains(
                    trustedClientReady.substring(
                      0,
                      trustedClientReady.length - 1,
                    ),
                  )) {
            ready.complete();
          }
          return bytes;
        }),
        errors: child.stderr,
        exit: child.exitCode,
        write: child.stdin.add,
        flush: child.stdin.flush,
        close: child.stdin.close,
      );
      capture = completion;
      await body(child, completion, ready.future);
    },
    cleanup: () => runOwnedFixtureLifecycle(
      body: () async {
        final child = owned;
        if (child != null) {
          await capture!.cleanup(
            kill: () => child.kill(),
            exit: child.exitCode,
          );
        }
      },
      cleanup: () async => root.deleteSync(recursive: true),
    ),
  );
}

void main() {
  test(
    'real stdin flush and ACK EOF release a retained live child after epilogue',
    () async {
      await withChild('normal', (child, completion, ready) async {
        final identity = RetainedProcessIdentity.open(child.pid);
        try {
          await ready.timeout(const Duration(seconds: 12));
          final epilogue = Completer<void>();
          final continuation = () async {
            await epilogue.future;
            identity.revalidate();
            return completion.complete(const Duration(seconds: 12));
          }();
          // Client body/finally and READY have finished. The retained process is
          // still live while its parent's protocol epilogue is held.
          identity.revalidate();
          epilogue.complete();
          expect(await continuation, 0);
          expect(completion.output, 'CLIENT_PASS\n$trustedClientReady');
          expect(completion.errors, isEmpty);
          expect(identity.revalidate, throwsStateError);
        } finally {
          identity.close();
        }
      });
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'real early child exit drains output and refuses missing READY',
    () async {
      await withChild('early', (child, completion, ready) async {
        await expectLater(
          completion.complete(const Duration(seconds: 12)),
          throwsStateError,
        );
        expect(await child.exitCode, 0);
        expect(completion.output, 'EARLY_EXIT\n');
        expect(completion.errors, isEmpty);
      });
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'real oversized stdout is bounded and cannot become successful completion',
    () async {
      await withChild('oversize', (child, completion, ready) async {
        await expectLater(
          completion.complete(const Duration(seconds: 12)),
          throwsStateError,
        );
        expect(completion.output.length, lessThanOrEqualTo(16384));
        expect(completion.errors, isEmpty);
      });
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
