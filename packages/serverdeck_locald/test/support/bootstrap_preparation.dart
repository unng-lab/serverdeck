import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

enum BootstrapFixturePhase {
  prepareStart('prepare-start'),
  compileOwner('compile-owner'),
  compileClient('compile-client'),
  selectNative('select-native'),
  manifest('manifest'),
  prepared('prepared'),
  behaviorStart('behavior-start'),
  namespaceCheck('namespace-check'),
  run0('run-0'),
  run1('run-1'),
  run2('run-2'),
  run3('run-3'),
  run4('run-4'),
  run5('run-5'),
  refusalChecks('refusal-checks'),
  cleanup('cleanup'),
  complete('complete');

  const BootstrapFixturePhase(this.identifier);

  final String identifier;
}

void bootstrapFixturePhase(BootstrapFixturePhase phase) {
  // The test JSON reporter captures print events for fixed fixture phases.
  // ignore: avoid_print
  print('BOOTSTRAP_FIXTURE_PHASE:${phase.identifier}');
}

class PreparedBootstrapFixture {
  PreparedBootstrapFixture._(
    this.fixture,
    this.root,
    this.bundle,
    this.local,
    this.manifestFile,
  );

  final Directory fixture;
  final String root;
  final Directory bundle;
  final Directory local;
  final File manifestFile;

  static Future<PreparedBootstrapFixture> prepare() async {
    bootstrapFixturePhase(BootstrapFixturePhase.prepareStart);
    final fixture = Directory.systemTemp.createTempSync(
      'serverdeck-bootstrap-fixture-',
    );
    final root = p.normalize(p.absolute(fixture.path));
    if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root)) {
      throw StateError('UNSAFE_TEST_DIRECTORY');
    }
    try {
      final bundle = Directory(p.join(root, 'bundle'))..createSync();
      final local = Directory(p.join(root, 'local'))..createSync();
      for (final entry in {
        'locald.exe': 'bin/locald.dart',
        'serverdeck.exe': 'test/support/bootstrap_client.dart',
      }.entries) {
        bootstrapFixturePhase(
          entry.key == 'locald.exe'
              ? BootstrapFixturePhase.compileOwner
              : BootstrapFixturePhase.compileClient,
        );
        final compile = await _runPreparationProcess(
          Platform.resolvedExecutable,
          ['compile', 'exe', entry.value, '-o', p.join(bundle.path, entry.key)],
        );
        expect(
          compile.exitCode,
          0,
          reason: '${compile.stdout}\n${compile.stderr}',
        );
      }
      bootstrapFixturePhase(BootstrapFixturePhase.selectNative);
      final nativeLibrary = await _nativeArtifactForBootstrap();
      bootstrapFixturePhase(BootstrapFixturePhase.manifest);
      File(p.join(bundle.path, 'serverdeck.exe'))
          .copySync(p.join(bundle.path, 'mcp.exe'));
      File(nativeLibrary).copySync(p.join(bundle.path, 'libisar.dll'));
      final manifestFile = File(
        p.join(bundle.path, 'foundation.manifest.json'),
      );
      manifestFile.writeAsStringSync(
        jsonEncode({
          'format': 3,
          'product': 'serverdeck-next',
          'apiMajor': 1,
          'apiMinor': 1,
          'workspaceSchema': 3,
          'buildId': '${'a' * 40}+Debug+${'b' * 64}',
          'configuration': 'Debug',
          'testOnly': false,
          'appRoot': bundle.path,
          'sha256': {
            for (final name in [
              'locald.exe',
              'serverdeck.exe',
              'mcp.exe',
              'libisar.dll',
            ])
              name: fileSha256(p.join(bundle.path, name)),
          },
        }),
      );
      bootstrapFixturePhase(BootstrapFixturePhase.prepared);
      return PreparedBootstrapFixture._(
        fixture,
        root,
        bundle,
        local,
        manifestFile,
      );
    } catch (_) {
      // Preparation never starts an owner. Retain its owned bundle for evidence
      // rather than letting a hook delete files while a timed-out body runs.
      stderr.writeln('FIXTURE_EVIDENCE_RETAINED:$root');
      rethrow;
    }
  }
}

// Use the same resolver, arguments, working directory and inherited environment
// as nativeArtifactForTest(); qualification remains in the repository script.
Future<String> _nativeArtifactForBootstrap() async {
  final root = p.normalize(p.absolute('../..'));
  final result = await _runPreparationProcess('pwsh', [
    '-NoProfile',
    '-File',
    p.join(root, 'tools', 'resolve-native-artifact.ps1'),
  ], workingDirectory: root);
  if (result.exitCode != 0) {
    throw StateError('NATIVE_TEST_ARTIFACT_SELECTION_FAILED: ${result.stderr}');
  }
  if (result.stdoutTruncated) {
    throw StateError('NATIVE_TEST_ARTIFACT_SELECTION_OUTPUT_LIMIT');
  }
  final selection = jsonDecode(result.stdout) as Map<String, dynamic>;
  final dll = selection['dll'] as String;
  if (!p.isAbsolute(dll) || !File(dll).existsSync()) {
    throw StateError('NATIVE_TEST_ARTIFACT_MISSING');
  }
  return dll;
}

class _PreparationProcessResult {
  _PreparationProcessResult(
    this.exitCode,
    this.stdout,
    this.stderr,
    this.stdoutTruncated,
  );

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool stdoutTruncated;
}

Future<_PreparationProcessResult> _runPreparationProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final child = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final output = _BoundedPreparationOutput(child.stdout);
  final errors = _BoundedPreparationOutput(child.stderr);
  var exited = false;
  final exit = child.exitCode.then((code) {
    exited = true;
    return code;
  });
  final completion = Future.wait<void>([
    exit.then<void>((_) {}),
    output.done,
    errors.done,
  ], eagerError: true);
  try {
    // setUpAll has its own package:test hook timeout (12 minutes). The group
    // timeout does not bound it, so every owned preparation child is bounded.
    await completion.timeout(const Duration(seconds: 90));
    return _PreparationProcessResult(
      await exit,
      output.text,
      errors.text,
      output.truncated,
    );
  } catch (error, stack) {
    // Only the Process returned by this preparation call may be terminated.
    if (!exited) child.kill();
    try {
      await Future.wait<void>([
        exit.then<void>((_) {}),
        output.done.catchError((Object _) {}),
        errors.done.catchError((Object _) {}),
      ]).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw StateError('BOOTSTRAP_PREPARATION_CHILD_CLEANUP_UNCONFIRMED');
    }
    Error.throwWithStackTrace(error, stack);
  } finally {
    await Future.wait([output.cancel(), errors.cancel()]);
  }
}

class _BoundedPreparationOutput {
  _BoundedPreparationOutput(Stream<List<int>> source) {
    _subscription = source.listen(
      (chunk) {
        final remaining = 65536 - _bytes.length;
        if (chunk.length > remaining) truncated = true;
        _bytes.addAll(chunk.take(remaining));
        // Keep draining after the capture cap so neither pipe blocks its child.
      },
      onError: (Object error, StackTrace stack) {
        if (!_done.isCompleted) _done.completeError(error, stack);
      },
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
    );
  }

  final _bytes = <int>[];
  final _done = Completer<void>();
  late final StreamSubscription<List<int>> _subscription;
  bool truncated = false;

  Future<void> get done => _done.future;
  String get text => utf8.decode(_bytes, allowMalformed: true);
  Future<void> cancel() => _subscription.cancel();
}
