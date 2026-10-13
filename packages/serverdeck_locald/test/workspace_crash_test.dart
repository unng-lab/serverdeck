import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import 'support/vm_debugger.dart';
import 'support/native_artifact.dart';

void main() {
  final source = File('lib/storage/workspace.dart').readAsLinesSync();
  int line(String text, {bool last = false}) {
    final matches = [
      for (var i = 0; i < source.length; i++)
        if (source[i].contains(text)) i + 1,
    ];
    if (matches.isEmpty) throw StateError('MISSING_INIT_BOUNDARY');
    return last ? matches.last : matches.first;
  }

  final boundaries = <String, ({int line, bool ready, int files, bool active})>{
    'staging-created': (
      line: line('key = await custody.createReceiptKey'),
      ready: false,
      files: 0,
      active: false,
    ),
    'key-flushed': (
      line: line('await writeNewProtectedFile(', last: true),
      ready: false,
      files: 1,
      active: false,
    ),
    'manifest-flushed': (
      line: line("for (final name in ['workspace.isar'"),
      ready: false,
      files: 2,
      active: false,
    ),
    'native-files-created': (
      line: line('initial = await Isar.open('),
      ready: false,
      files: 4,
      active: false,
    ),
    'uncommitted-initial-rows': (
      line: line('await database.storedSettings.put('),
      ready: false,
      files: 4,
      active: false,
    ),
    'initial-transaction-durable': (
      line: line('if (!await database.close())'),
      ready: true,
      files: 4,
      active: false,
    ),
    'before-promotion': (
      line: line('await promoteProtectedPath('),
      ready: true,
      files: 4,
      active: false,
    ),
    'after-promotion': (
      line: line('store = await openStore(active);', last: true),
      ready: true,
      files: 4,
      active: true,
    ),
    'active-opened': (
      line: line('transferred = true;'),
      ready: true,
      files: 4,
      active: true,
    ),
  };
  for (final entry in boundaries.entries) {
    test(
      'hard process crash at initialization ${entry.key}',
      () async {
        final nativeLibrary = nativeArtifactForTest();
        final parent = Directory.systemTemp.createTempSync(
          'serverdeck-init-crash-',
        );
        final root = p.normalize(p.absolute(parent.path));
        if (!p.isWithin(
          p.normalize(p.absolute(Directory.systemTemp.path)),
          root,
        ))
          throw StateError('UNSAFE_TEST_DIRECTORY');
        final bundle = Directory(p.join(root, 'bundle'))..createSync();
        final local = Directory(p.join(root, 'local'))..createSync();
        Process? child;
        VmDebugger? debugger;
        StreamSubscription<String>? output, errors;
        final logs = <String>[];
        try {
          File(p.join(bundle.path, 'serverdeck.exe'))
              .writeAsBytesSync([1, 2, 3]);
          File(p.join(bundle.path, 'locald.exe')).writeAsBytesSync([4, 5, 6]);
          File(nativeLibrary).copySync(p.join(bundle.path, 'libisar.dll'));
          File(p.join(bundle.path, 'foundation.manifest.json'))
              .writeAsStringSync(
                jsonEncode({
                  'format': 1,
                  'buildId': '${'a' * 40}+Debug+${'b' * 64}',
                  'configuration': 'Debug',
                  'testOnly': false,
                  'appRoot': bundle.path,
                  'sha256': {
                    for (final name in [
                      'serverdeck.exe',
                      'locald.exe',
                      'libisar.dll',
                    ])
                      name: fileSha256(p.join(bundle.path, name)),
                  },
                }),
              );
          final vm = p.join(
            p.dirname(Platform.resolvedExecutable),
            'dartvm.exe',
          );
          final uri = Completer<Uri>(), waiting = Completer<void>();
          child = await Process.start(vm, [
            '--enable-vm-service=0',
            'test/support/workspace_vm_child.dart',
            local.path,
            bundle.path,
            'create',
            if (entry.key == 'staging-created') 'trace-check',
          ]);
          output = child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((value) {
                logs.add(value);
                final match = RegExp(r'http://127\.0\.0\.1:\d+/[^ ]*/')
                    .firstMatch(value);
                if (match != null && !uri.isCompleted)
                  uri.complete(Uri.parse(match.group(0)!));
                if (value == 'WAITING_FOR_DEBUGGER' && !waiting.isCompleted)
                  waiting.complete();
              });
          errors = child.stderr
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(logs.add);
          await waiting.future.timeout(const Duration(seconds: 20));
          debugger = await VmDebugger.connect(
            await uri.future.timeout(const Duration(seconds: 15)),
          );
          await debugger.call('streamListen', {'streamId': 'Debug'});
          final machine = await debugger.call('getVM');
          final isolate =
              (machine['isolates'] as List).cast<Map>().singleWhere(
                    (v) => v['name'] == 'main',
                  )['id']
                  as String;
          final scripts = await debugger.call('getScripts', {
            'isolateId': isolate,
          });
          final script = (scripts['scripts'] as List).cast<Map>().singleWhere(
            (v) => (v['uri'] as String).endsWith('/storage/workspace.dart'),
          );
          final breakpoint = await debugger.call('addBreakpointWithScriptUri', {
            'isolateId': isolate,
            'scriptUri': script['uri'],
            'line': entry.value.line,
          });
          expect(breakpoint['resolved'], true);
          await debugger.call('setExceptionPauseMode', {
            'isolateId': isolate,
            'mode': 'All',
          });
          final paused = debugger.tracedPause(
            isolate,
            breakpoint['id'] as String,
          );
          child.stdin.writeln('start');
          await child.stdin.flush();
          await child.stdin.close();
          await Future.any([
            paused,
            child.exitCode.then(
              (exit) => throw StateError('INIT_CHILD_EXIT_$exit'),
            ),
          ]);
          if (entry.key == 'staging-created')
            expect(debugger.observedExceptions, contains('TRACE_CHECK'));
          if (entry.key == 'staging-created') {
            final diagnostics = await debugger.describePauses(
              isolateId: isolate,
            );
            final main = diagnostics.singleWhere(
              (value) => value.name == 'main',
            );
            expect(main.phase, 'PauseBreakpoint');
            expect(main.livePorts, greaterThan(0));
            expect(main.receivePorts, greaterThan(0));
            expect(main.pauseOnExit, false);
            expect(
              main.allocationFrames.any(
                (v) => v.contains('MutexLease.acquire'),
              ),
              true,
            );
          }
          final stack = await debugger.call('getStack', {'isolateId': isolate});
          expect(
            (stack['frames'] as List).first['location']['script']['uri'],
            script['uri'],
          );
          final location = (stack['frames'] as List).first['location'] as Map;
          final scriptObject = await debugger.call('getObject', {
            'isolateId': isolate,
            'objectId': script['id'],
          });
          final table = (scriptObject['tokenPosTable'] as List).cast<List>();
          final token = location['tokenPos'];
          final actualLine = table
              .singleWhere(
                (row) =>
                    [for (var i = 1; i < row.length; i += 2) row[i]]
                        .contains(token),
              )
              .first;
          expect(
            actualLine,
            entry.value.line,
            reason: 'Debugger must stop at the requested init boundary',
          );
          final active = p.join(
            local.path,
            'ServerDeckNext',
            'v1',
            'workspaces',
            'default',
          );
          final staging = '$active.creating';
          expect(Directory(active).existsSync(), entry.value.active);
          expect(Directory(staging).existsSync(), !entry.value.active);
          final inspected = entry.value.active ? active : staging;
          if (File(p.join(inspected, 'workspace.isar-lck')).existsSync()) {
            requireOwnerOnlyFileAcl(
              p.join(inspected, 'workspace.isar-lck'),
              currentUserSid(),
            );
          }
          expect(
            Directory(inspected).listSync().whereType<File>().length,
            entry.value.files,
            reason: Directory(inspected)
                .listSync()
                .map((v) => p.basename(v.path))
                .join(','),
          );
          Map<String, String> identities() => {
            for (final name in ['receipt-key.dpapi', 'workspace.manifest.json'])
              if (File(p.join(inspected, name)).existsSync())
                name: base64.encode(
                  File(p.join(inspected, name)).readAsBytesSync(),
                ),
          };
          final before = identities();
          expect(logs.contains('OWNED_WORKSPACE_READY'), false);
          expect(child.kill(), true);
          await child.exitCode.timeout(const Duration(seconds: 10));
          await debugger.close();
          debugger = null;
          await output.cancel();
          output = null;
          await errors.cancel();
          errors = null;
          child = null;
          final verificationUri = Completer<Uri>(),
              verificationWaiting = Completer<void>();
          child = await Process.start(vm, [
            '--enable-vm-service=0',
            'test/support/workspace_vm_child.dart',
            local.path,
            bundle.path,
            entry.value.ready ? 'verify-ready' : 'verify-blocked',
            'wait-debugger',
          ]);
          final verificationLog = <String>[];
          final outputDone = Completer<void>(), errorsDone = Completer<void>();
          output = child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((value) {
                verificationLog.add(value);
                final match = RegExp(r'http://127\.0\.0\.1:\d+/[^ ]*/')
                    .firstMatch(value);
                if (match != null && !verificationUri.isCompleted)
                  verificationUri.complete(Uri.parse(match.group(0)!));
                if (value == 'WAITING_FOR_DEBUGGER' &&
                    !verificationWaiting.isCompleted)
                  verificationWaiting.complete();
              }, onDone: outputDone.complete);
          errors = child.stderr
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(verificationLog.add, onDone: errorsDone.complete);
          await verificationWaiting.future.timeout(const Duration(seconds: 20));
          debugger = await VmDebugger.connect(
            await verificationUri.future.timeout(const Duration(seconds: 15)),
          );
          await debugger.call('streamListen', {'streamId': 'Debug'});
          final verificationMachine = await debugger.call('getVM');
          final verificationIsolate =
              (verificationMachine['isolates'] as List).cast<Map>().singleWhere(
                    (v) => v['name'] == 'main',
                  )['id']
                  as String;
          await debugger.call('setExceptionPauseMode', {
            'isolateId': verificationIsolate,
            'mode': 'All',
          });
          final verificationExit = debugger.tracedExit(
            verificationIsolate,
            child.exitCode.timeout(const Duration(seconds: 30)),
          );
          child.stdin.writeln('start');
          await child.stdin.flush();
          await child.stdin.close();
          int exit;
          try {
            exit = await verificationExit;
          } on TimeoutException {
            await debugger.reportTimeout(verificationLog);
            rethrow;
          }
          await debugger.close();
          debugger = null;
          await Future.wait([outputDone.future, errorsDone.future])
              .timeout(const Duration(seconds: 5));
          expect(
            exit,
            0,
            reason: verificationLog
                .where((v) => !v.contains('http://'))
                .join('\n'),
          );
          for (final marker in [
            'STDIN_GATE_COMPLETE',
            'WORKSPACE_CLOSE_BEGIN',
            'WORKSPACE_CLOSE_END',
            'MUTEX_CLOSE_BEGIN',
            'MUTEX_CLOSE_END',
            'VERIFIER_MAIN_RETURNING',
          ]) {
            expect(verificationLog, contains(marker));
          }
          expect(
            verificationLog,
            contains(
              entry.value.ready
                  ? 'OWNED_WORKSPACE_READY'
                  : 'PARTIAL_WORKSPACE_PRESERVED',
            ),
          );
          final afterDirectory = entry.value.ready ? active : inspected;
          expect(
            Directory(active).existsSync(),
            entry.value.ready || entry.value.active,
          );
          expect(
            Directory(staging).existsSync(),
            !entry.value.ready && !entry.value.active,
          );
          for (final value in before.entries) {
            expect(
              base64.encode(
                File(p.join(afterDirectory, value.key)).readAsBytesSync(),
              ),
              value.value,
            );
          }
          if (!entry.value.ready)
            expect(
              Directory(inspected).listSync().whereType<File>().length,
              entry.value.files,
            );
        } catch (error) {
          // Service auth URL is test-local; print only safe program markers/errors.
          stderr.writeln(
            logs.where((value) => !value.contains('http://')).join('\n'),
          );
          rethrow;
        } finally {
          if (child != null) {
            child.kill();
            await child.exitCode.timeout(const Duration(seconds: 10));
          }
          await debugger?.close();
          await output?.cancel();
          await errors?.cancel();
          parent.deleteSync(recursive: true);
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 100)),
    );
  }
}
