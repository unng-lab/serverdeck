import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../../../serverdeck_windows/test/support/native_fixture_job.dart';

void main() {
  late Directory compiledRoot;
  late String executable, observed;
  setUpAll(() async {
    compiledRoot = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-auth-',
    );
    b.ownRoot(compiledRoot.path);
    executable = p.join(compiledRoot.path, 'auth.exe');
    await b.compilePeer(
      executable,
      source: 'test/support/trusted_auth_actor.dart',
    );
    observed = p.join(compiledRoot.path, 'observed.exe');
    final compiler = await Process.start(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-DSERVERDECK_TEST_NATIVE_OBSERVATION=true',
      'test/support/trusted_auth_actor.dart',
      '-o',
      observed,
    ]);
    final output = b.boundedOutput(compiler.stdout),
        errors = b.boundedOutput(compiler.stderr);
    try {
      expect(
        await compiler.exitCode.timeout(const Duration(seconds: 90)),
        0,
        reason: '${await output}\n${await errors}',
      );
    } finally {
      compiler.kill();
      await compiler.exitCode.timeout(const Duration(seconds: 10));
    }
  });
  tearDownAll(() {
    b.ownRoot(compiledRoot.path);
    compiledRoot.deleteSync(recursive: true);
  });
  test(
    'hard-killed fixture owner cannot leave its native client child',
    () async {
      final fixture = b.Fixture(executable);
      fixture.document['format'] = 3;
      fixture.document['workspaceSchema'] = 3;
      fixture.write();
      StreamIterator<String>? lines;
      try {
        final server = await Process.start(p.join(fixture.path, 'locald.exe'), [
          'scenario',
          fixture.path,
          'orphan',
        ]);
        fixture.children.add(server);
        fixture.errors.add(b.boundedOutput(server.stderr));
        lines = StreamIterator(
          server.stdout.transform(utf8.decoder).transform(const LineSplitter()),
        );
        expect(
          await lines.moveNext().timeout(const Duration(seconds: 10)),
          isTrue,
        );
        expect(lines.current, matches(r'^CHILD:[1-9][0-9]{0,9}$'));
        final child = RetainedProcessIdentity.open(
          int.parse(lines.current.substring(6)),
        );
        fixture.identities.add(child);
        expect(
          p.equals(child.imagePath, p.join(fixture.path, 'mcp.exe')),
          isTrue,
        );
        expect(child.sid, currentUserSid());
        child.revalidate();
        server.kill();
        await server.exitCode.timeout(const Duration(seconds: 10));
        final watch = Stopwatch()..start();
        while (!fixtureProcessExited(child) &&
            watch.elapsed < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(fixtureProcessExited(child), isTrue);
      } finally {
        await lines?.cancel();
        await fixture.close();
      }
    },
    testOn: 'windows',
  );
  for (final scenario in [
    'roles',
    'native-gate',
    'stale-close',
    'proofs',
    'quota',
    'expiry',
    'close',
    'snapshot',
    'deadline',
    'client',
    'framing',
    'tamper',
    'owner-context',
    'owner-context-detach',
    'owner-context-expiry',
    'owner-context-budget',
    'owner-context-native',
    'owner-context-stop',
    'owner-context-physical',
  ]) {
    test(
      'actual format3 API1.1 bootstrap and session $scenario',
      () async {
        final fixture = b.Fixture(
          scenario == 'owner-context-physical' ? observed : executable,
        );
        fixture.document['format'] = 3;
        fixture.document['workspaceSchema'] = 3;
        fixture.write();
        try {
          final child = await Process.start(
            p.join(fixture.path, 'locald.exe'),
            ['scenario', fixture.path, scenario],
          );
          fixture.children.add(child);
          final output = b.boundedOutput(child.stdout),
              errors = b.boundedOutput(child.stderr);
          fixture.errors.add(errors);
          expect(
            await child.exitCode.timeout(const Duration(seconds: 70)),
            0,
            reason: '${await output}\n${await errors}',
          );
          expect((await output).trim(), 'PASS:$scenario');
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }
}
