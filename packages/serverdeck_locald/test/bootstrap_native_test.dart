import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/discovery.dart';
import 'package:serverdeck_locald/bootstrap/discovery_file.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import 'support/native_artifact.dart';

void main() {
  test(
    'compiled owner authenticates, becomes ready, closes and reopens workspace',
    () async {
      final sid = currentUserSid();
      final namespace = await DiscoveryNamespace.forOwner(sid);
      final reservation = await MutexLease.acquire(namespace.mutexName, sid);
      try {
        expect(
          reservation.isHeld,
          true,
          reason: 'Fixture requires unoccupied owner namespace',
        );
      } finally {
        await reservation.close();
      }
      final fixture = Directory.systemTemp.createTempSync(
        'serverdeck-bootstrap-fixture-',
      );
      final root = p.normalize(p.absolute(fixture.path));
      if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root))
        throw StateError('UNSAFE_TEST_DIRECTORY');
      Process? owner;
      Process? observer;
      StreamIterator<String>? observerOutput;
      Future<String>? observerErrors;
      DiscoveryDescriptor? crashedDescriptor;
      var failed = false;
      final peers = <Process>[];
      try {
        final bundle = Directory(p.join(root, 'bundle'))..createSync();
        final local = Directory(p.join(root, 'local'))..createSync();
        for (final entry in {
          'locald.exe': 'bin/locald.dart',
          'serverdeck.exe': 'test/support/bootstrap_client.dart',
        }.entries) {
          final compile = await Process.run(Platform.resolvedExecutable, [
            'compile',
            'exe',
            entry.value,
            '-o',
            p.join(bundle.path, entry.key),
          ]);
          expect(
            compile.exitCode,
            0,
            reason: '${compile.stdout}\n${compile.stderr}',
          );
        }
        final nativeLibrary = nativeArtifactForTest();
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
        String? workspace, previousGeneration;
        for (var run = 0; run < 6; run++) {
          if (run == 2) {
            final startupWatch = Stopwatch()..start();
            owner = await Process.start(
              p.join(bundle.path, 'locald.exe'),
              ['--workspace', 'default', '--app-root', bundle.path],
              environment: {'LOCALAPPDATA': local.path},
            );
            final idleOutput = owner.stdout.transform(utf8.decoder).join();
            final idleErrors = owner.stderr.transform(utf8.decoder).join();
            expect(
              await owner.exitCode.timeout(const Duration(seconds: 40)),
              1,
            );
            expect((await idleErrors).trim(), 'TIMEOUT');
            expect(
              startupWatch.elapsed,
              greaterThanOrEqualTo(const Duration(seconds: 29)),
            );
            expect(startupWatch.elapsed, lessThan(const Duration(seconds: 40)));
            await idleOutput; // Drain the real pipe before fixture reuse.
            owner = null;
            expect(
              File(
                p.join(
                  local.path,
                  'ServerDeckNext',
                  'v1',
                  'runtime',
                  'default.discovery',
                ),
              ).existsSync(),
              false,
            );
          }
          owner = await Process.start(
            p.join(bundle.path, 'locald.exe'),
            ['--workspace', 'default', '--app-root', bundle.path],
            environment: {'LOCALAPPDATA': local.path},
          );
          final stdoutResult = owner.stdout.transform(utf8.decoder).join();
          final stderrResult = owner.stderr.transform(utf8.decoder).join();
          if (run == 0) {
            // A contender must not bind the service before its first actual
            // owner/MCP session, nor acquire a keeper session of its own.
            final coldLocal = Directory(p.join(root, 'cold-contender-local'))
              ..createSync();
            final contender = await Process.run(
              p.join(bundle.path, 'locald.exe'),
              ['--workspace', 'default', '--app-root', bundle.path],
              environment: {'LOCALAPPDATA': coldLocal.path},
            ).timeout(const Duration(seconds: 35));
            expect(
              contender.exitCode,
              0,
              reason: '${contender.stdout}\n${contender.stderr}',
            );
            expect(contender.stderr, isEmpty);
            expect(coldLocal.listSync(), isEmpty);
          }
          if (run == 4 || run == 5) {
            // Protected publication follows owner mutex acquisition. Confirm
            // this launched owner before observer setup and the pending timer.
            final publicationWatch = Stopwatch()..start();
            final publishedDiscovery = DiscoveryFile(
              localAppData: local.path,
              runtimeDirectory: p.join(
                local.path,
                'ServerDeckNext',
                'v1',
                'runtime',
              ),
              ownerSid: sid,
              custody: DiscoveryCustody(DpapiProtection(), sid),
            );
            while (true) {
              expect(
                publicationWatch.elapsed,
                lessThan(const Duration(seconds: 25)),
              );
              if (File(publishedDiscovery.path).existsSync()) {
                final published = await publishedDiscovery.read(
                  (jsonDecode(manifestFile.readAsStringSync())
                          as Map)['buildId']
                      as String,
                );
                try {
                  if (published.generation != previousGeneration &&
                      published.serverPid == owner.pid) {
                    if (run == 4)
                      stdout.writeln('COMPILED_OWNER_MUTEX_PUBLISHED');
                    break;
                  }
                } finally {
                  published.close();
                }
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          }
          late final ProcessResult client;
          if (run == 0 || run >= 4) {
            if (run == 4) {
              observer = await Process.start(Platform.resolvedExecutable, [
                'test/support/bootstrap_mutex_observer.dart',
                namespace.mutexName,
              ], workingDirectory: p.absolute('../serverdeck_windows'));
              observerOutput = StreamIterator(
                observer.stdout
                    .transform(utf8.decoder)
                    .transform(const LineSplitter()),
              );
              observerErrors = observer.stderr.transform(utf8.decoder).join();
              expect(
                await observerOutput.moveNext().timeout(
                  const Duration(seconds: 10),
                ),
                true,
              );
              expect(observerOutput.current, 'MUTEX_OBSERVER_HELD');
            }
            final peer = await Process.start(
              p.join(bundle.path, 'serverdeck.exe'),
              [
                local.path,
                bundle.path,
                run == 4
                    ? 'client-owner-loss'
                    : run == 5
                    ? 'recover'
                    : 'hold',
              ],
            );
            peers.add(peer);
            final ready = Completer<void>(), lines = <String>[];
            Stopwatch? ownerLossWatch;
            final stdoutDone = Completer<void>();
            Object? stdoutFailure;
            final subscription = peer.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .listen(
                  (line) {
                    lines.add(line);
                    if (line == 'COMPILED_OWNER_LOSS_SEND') {
                      expect(ownerLossWatch, isNull);
                      ownerLossWatch = Stopwatch()..start();
                      peer.stdin.writeln('send');
                      unawaited(peer.stdin.flush());
                    }
                    if (line == 'COMPILED_BOOTSTRAP_HELD_READY' &&
                        !ready.isCompleted)
                      ready.complete();
                  },
                  onError: (Object error) => stdoutFailure = error,
                  onDone: () {
                    stdoutDone.complete();
                  },
                );
            final peerErrors = peer.stderr.transform(utf8.decoder).join();
            var scenarioCompleted = false;
            var exited = false;
            unawaited(
              owner.exitCode.then((_) {
                exited = true;
              }),
            );
            try {
              final launchedOwner = owner;
              await Future.any<void>([
                ready.future,
                peer.exitCode.then((code) async {
                  if (!ready.isCompleted)
                    throw StateError(
                      'FIXTURE_PEER_BEFORE_READY:$code:${(await peerErrors).trim()}',
                    );
                }),
                launchedOwner.exitCode.then((code) async {
                  if (!ready.isCompleted) {
                    throw StateError(
                      'COMPILED_OWNER_BEFORE_READY:$code:${(await stderrResult).trim()}',
                    );
                  }
                }),
              ]).timeout(const Duration(seconds: 30));
              final discovery = File(
                p.join(
                  local.path,
                  'ServerDeckNext',
                  'v1',
                  'runtime',
                  'default.discovery',
                ),
              );
              final before = discovery.readAsBytesSync();
              if (run == 4) {
                crashedDescriptor =
                    await DiscoveryFile(
                      localAppData: local.path,
                      runtimeDirectory: discovery.parent.path,
                      ownerSid: sid,
                      custody: DiscoveryCustody(DpapiProtection(), sid),
                    ).read(
                      (jsonDecode(manifestFile.readAsStringSync())
                              as Map)['buildId']
                          as String,
                    );

                // The Process object is the child started above with an owned
                // fixture LOCALAPPDATA/bundle; never kill an external owner.
                expect(ownerLossWatch, isNotNull);
                expect(
                  ownerLossWatch!.elapsed,
                  lessThan(const Duration(seconds: 4)),
                );
                expect(owner.kill(), true);
                expect(
                  await owner.exitCode.timeout(const Duration(seconds: 10)),
                  isNot(0),
                );
                expect(ownerLossWatch, isNotNull);
                expect(
                  ownerLossWatch!.elapsed,
                  lessThan(const Duration(seconds: 4)),
                );
                stdout.writeln(
                  'COMPILED_OWNER_LOSS_EXIT_MS=${ownerLossWatch!.elapsedMilliseconds}',
                );
                await stdoutResult;
                await stderrResult;
                owner = null;
                observer!.stdin.writeln('abandoned');
                await observer.stdin.flush();
                expect(
                  await observerOutput!.moveNext().timeout(
                    const Duration(seconds: 5),
                  ),
                  true,
                );
                expect(observerOutput.current, 'MUTEX_ABANDONED_CONFIRMED');
                expect(discovery.readAsBytesSync(), before);
              } else if (run == 5) {
                final refreshed = await DiscoveryFile(
                  localAppData: local.path,
                  runtimeDirectory: discovery.parent.path,
                  ownerSid: sid,
                  custody: DiscoveryCustody(DpapiProtection(), sid),
                ).read(crashedDescriptor!.buildId);
                final oldToken = crashedDescriptor.bootstrapToken;
                final newToken = refreshed.bootstrapToken;
                try {
                  expect(refreshed.workspaceId, crashedDescriptor.workspaceId);
                  expect(
                    refreshed.generation,
                    isNot(crashedDescriptor.generation),
                  );
                  expect(newToken, isNot(oldToken));
                  expect(refreshed.serverPid, owner.pid);
                } finally {
                  oldToken.fillRange(0, oldToken.length, 0);
                  newToken.fillRange(0, newToken.length, 0);
                  refreshed.close();
                }
                observer!.stdin.writeln('acquired');
                await observer.stdin.flush();
                expect(
                  await observerOutput!.moveNext().timeout(
                    const Duration(seconds: 5),
                  ),
                  true,
                );
                expect(observerOutput.current, 'MUTEX_REACQUIRED_CONFIRMED');
                observer.stdin.writeln('close');
                await observer.stdin.close();
                expect(
                  await observer.exitCode.timeout(const Duration(seconds: 5)),
                  0,
                  reason: await observerErrors,
                );
                await observerOutput.cancel();
                observerOutput = null;
                observer = null;
                crashedDescriptor.close();
                crashedDescriptor = null;
              } else {
                for (final mode in [
                  'reject-proof',
                  'reject-build',
                  'reject-capability',
                  'read-only',
                  'client-native',
                  'client-loss',
                  'client-sessions',
                ]) {
                  final probe = await Process.start(
                    p.join(
                      bundle.path,
                      mode == 'read-only' ? 'mcp.exe' : 'serverdeck.exe',
                    ),
                    [local.path, bundle.path, mode],
                  );
                  peers.add(probe);
                  final probeOutput = probe.stdout
                      .transform(utf8.decoder)
                      .join();
                  final probeErrors = probe.stderr
                      .transform(utf8.decoder)
                      .join();
                  late final int probeExit;
                  try {
                    probeExit = await probe.exitCode.timeout(
                      Duration(seconds: mode == 'client-loss' ? 30 : 15),
                    );
                  } on TimeoutException {
                    // Only this owned console child; never terminate the owner.
                    probe.kill();
                    await probe.exitCode.timeout(const Duration(seconds: 5));
                    await Future.wait([probeOutput, probeErrors]);
                    rethrow;
                  }
                  expect(probeExit, 0, reason: await probeErrors);
                  expect(await probeErrors, isEmpty);
                  expect(
                    await probeOutput,
                    contains(
                      mode == 'client-loss'
                          ? 'COMPILED_PRODUCTION_CLIENT_LOSS_RECOVERY_PROVED'
                          : mode == 'client-sessions'
                          ? 'COMPILED_PRODUCTION_EIGHT_SESSIONS_REUSE_PROVED'
                          : mode == 'client-native'
                          ? 'COMPILED_PRODUCTION_CLIENT_ROUNDTRIP_PROVED'
                          : mode == 'read-only'
                          ? 'COMPILED_BOOTSTRAP_READ_ONLY_PROVED'
                          : 'COMPILED_BOOTSTRAP_AUTH_REJECTED_PROVED',
                    ),
                  );
                  expect(exited, false);
                  if (mode == 'client-sessions') {
                    expect(
                      RegExp(
                        r'^COMPILED_PRODUCTION_SAME_ENDPOINT_REUSE_PROVED\r?$',
                        multiLine: true,
                      ).allMatches(await probeOutput).length,
                      1,
                    );
                  }
                  expect(discovery.readAsBytesSync(), before);
                }
                final loserLocal = Directory(p.join(root, 'loser-local'))
                  ..createSync();
                final loser = await Process.run(
                  p.join(bundle.path, 'locald.exe'),
                  ['--workspace', 'default', '--app-root', bundle.path],
                  environment: {'LOCALAPPDATA': loserLocal.path},
                ).timeout(const Duration(seconds: 35));
                expect(
                  loser.exitCode,
                  0,
                  reason: '${loser.stdout}\n${loser.stderr}',
                );
                expect(loser.stderr, isEmpty);
                expect(exited, false);
                expect(discovery.readAsBytesSync(), before);
                expect(loserLocal.listSync(), isEmpty);
              }
              scenarioCompleted = true;
            } finally {
              try {
                try {
                  peer.stdin.writeln(run == 4 ? 'crash' : 'close');
                  await peer.stdin.close();
                } on SocketException {
                  // A failed startup may already have closed the peer. Retain
                  // its original failure instead of masking it during cleanup.
                  if (scenarioCompleted) rethrow;
                }
                final peerExit = await peer.exitCode.timeout(
                  // An unauthenticated peer has a bounded 25-second discovery
                  // loop. Join it even when the owner failed before publishing.
                  const Duration(seconds: 35),
                );
                if (scenarioCompleted)
                  expect(peerExit, 0, reason: await peerErrors);
                await stdoutDone.future.timeout(const Duration(seconds: 10));
                if (stdoutFailure != null)
                  throw StateError('FIXTURE_STDOUT_FAILED');
                client = ProcessResult(
                  peer.pid,
                  peerExit,
                  lines.join('\n'),
                  await peerErrors,
                );
              } catch (_) {
                // Preserve the startup/scenario failure. The outer cleanup
                // retries joins and retains evidence if ownership is unresolved.
                if (scenarioCompleted) rethrow;
              } finally {
                await subscription.cancel();
              }
            }
          } else {
            client = await Process.run(p.join(bundle.path, 'serverdeck.exe'), [
              local.path,
              bundle.path,
              if (run == 3) 'expire',
            ]).timeout(Duration(seconds: run == 3 ? 95 : 35));
          }
          expect(
            client.exitCode,
            0,
            reason: '${client.stdout}\n${client.stderr}',
          );
          final output = client.stdout.toString();
          expect(
            output,
            contains(
              run == 4
                  ? 'COMPILED_BOOTSTRAP_OWNER_CRASH_PROVED'
                  : run == 3
                  ? 'COMPILED_BOOTSTRAP_LEASE_EXPIRED_PROVED'
                  : 'COMPILED_BOOTSTRAP_READY_CLOSE_PROVED',
            ),
          );
          final id = RegExp(r'WORKSPACE_ID=([^\r\n]+)')
              .firstMatch(output)!
              .group(1)!;
          final generation = RegExp(r'GENERATION=([^\r\n]+)')
              .firstMatch(output)!
              .group(1)!;
          if (workspace != null) expect(id, workspace);
          if (previousGeneration != null)
            expect(generation, isNot(previousGeneration));
          workspace = id;
          previousGeneration = generation;
          stdout.writeln('COMPILED_BOOTSTRAP_RUN_${run}_COMPLETED');
          if (run == 5)
            expect(output, contains('COMPILED_BOOTSTRAP_RECOVERY_DATA_PROVED'));
          if (run == 4) {
            expect(
              output,
              contains('COMPILED_OWNER_LOSS_PENDING_FAILURE_PROVED'),
            );
            continue; // Stale discovery is intentionally retained.
          }
          expect(
            await owner!.exitCode.timeout(const Duration(seconds: 10)),
            0,
            reason: '${await stdoutResult}\n${await stderrResult}',
          );
          expect(await stderrResult, isEmpty);
          owner = null;
          expect(
            File(
              p.join(
                local.path,
                'ServerDeckNext',
                'v1',
                'runtime',
                'default.discovery',
              ),
            ).existsSync(),
            false,
          );
          expect(
            File(
              p.join(
                local.path,
                'ServerDeckNext',
                'v1',
                'workspaces',
                'default',
                'workspace.isar',
              ),
            ).existsSync(),
            true,
          );
        }
        final original = manifestFile.readAsStringSync();
        final database = p.join(
          local.path,
          'ServerDeckNext',
          'v1',
          'workspaces',
          'default',
          'workspace.isar',
        );
        Map<String, String> snapshotLocal() => {
          for (final file
              in local
                  .listSync(recursive: true, followLinks: false)
                  .whereType<File>())
            p.relative(file.path, from: local.path): fileSha256(file.path),
        };
        final workspaceDirectory = Directory(p.dirname(database));
        final workspaceManifest = File(
          p.join(workspaceDirectory.path, 'workspace.manifest.json'),
        );
        final receiptWrapper = File(
          p.join(workspaceDirectory.path, 'receipt-key.dpapi'),
        );
        Map<String, String> snapshotWorkspace() => {
          for (final file
              in workspaceDirectory
                  .listSync(recursive: true, followLinks: false)
                  .whereType<File>())
            p.relative(file.path, from: workspaceDirectory.path): fileSha256(
              file.path,
            ),
        };
        for (final fault in [
          'manifest-json',
          'manifest-schema',
          'receipt-dpapi',
          'native-pages',
        ]) {
          final intactWorkspace = snapshotWorkspace();
          final damagedFile = fault.startsWith('manifest-')
              ? workspaceManifest
              : fault == 'receipt-dpapi'
              ? receiptWrapper
              : File(database);
          final originalBytes = damagedFile.readAsBytesSync();
          try {
            switch (fault) {
              case 'manifest-json':
                damagedFile.writeAsStringSync('{');
              case 'manifest-schema':
                final changed = jsonDecode(utf8.decode(originalBytes)) as Map;
                changed['schema'] = 4;
                damagedFile.writeAsStringSync(jsonEncode(changed));
              case 'receipt-dpapi':
                final changed = List<int>.of(originalBytes);
                changed[0] ^= 0xff;
                damagedFile.writeAsBytesSync(changed);
              case 'native-pages':
                damagedFile.writeAsBytesSync(originalBytes.sublist(0, 64));
            }
            final damagedWorkspace = snapshotWorkspace();
            owner = await Process.start(
              p.join(bundle.path, 'locald.exe'),
              ['--workspace', 'default', '--app-root', bundle.path],
              environment: {'LOCALAPPDATA': local.path},
            );
            final output = owner.stdout.transform(utf8.decoder).join();
            final errors = owner.stderr.transform(utf8.decoder).join();
            final expectedCode = fault == 'manifest-schema'
                ? 'INCOMPATIBLE'
                : 'STORAGE_BLOCKED';
            final refused = await Process.run(
              p.join(bundle.path, 'serverdeck.exe'),
              [
                local.path,
                bundle.path,
                fault == 'manifest-schema'
                    ? 'blocked-incompatible'
                    : 'blocked-storage',
              ],
            ).timeout(const Duration(seconds: 35));
            expect(
              refused.exitCode,
              0,
              reason: '${refused.stdout}\n${refused.stderr}',
            );
            expect(
              refused.stdout,
              contains('COMPILED_BOOTSTRAP_BLOCKED_OPERATIONS_PROVED'),
            );
            expect(refused.stderr, isEmpty);
            expect(
              await owner.exitCode.timeout(const Duration(seconds: 10)),
              1,
            );
            await output;
            expect((await errors).trim(), expectedCode);
            owner = null;
            if (fault == 'manifest-schema') {
              // No diagnostic authentication this time: the original startup
              // watchdog must still close the owner, preserving INCOMPATIBLE
              // rather than replacing it with its later TIMEOUT reason.
              final failedWatch = Stopwatch()..start();
              owner = await Process.start(
                p.join(bundle.path, 'locald.exe'),
                ['--workspace', 'default', '--app-root', bundle.path],
                environment: {'LOCALAPPDATA': local.path},
              );
              final failedOutput = owner.stdout.transform(utf8.decoder).join();
              final failedErrors = owner.stderr.transform(utf8.decoder).join();
              expect(
                await owner.exitCode.timeout(const Duration(seconds: 40)),
                1,
              );
              expect((await failedErrors).trim(), expectedCode);
              await failedOutput;
              expect(
                failedWatch.elapsed,
                greaterThanOrEqualTo(const Duration(seconds: 29)),
              );
              expect(
                failedWatch.elapsed,
                lessThan(const Duration(seconds: 40)),
              );
              owner = null;
              stdout.writeln(
                'COMPILED_FAILED_WORKSPACE_NO_AUTH_WATCHDOG_PROVED',
              );
            }
            expect(snapshotWorkspace(), damagedWorkspace);
            expect(
              File(
                p.join(
                  local.path,
                  'ServerDeckNext',
                  'v1',
                  'runtime',
                  'default.discovery',
                ),
              ).existsSync(),
              false,
            );
          } finally {
            // Restore only this owned fixture after its resource owner exits.
            if (owner != null) {
              await owner.exitCode.timeout(const Duration(seconds: 40));
              owner = null;
            }
            damagedFile.writeAsBytesSync(originalBytes);
          }
          expect(snapshotWorkspace(), intactWorkspace);
          // A fresh normal production owner must still read the original
          // committed profile/receipt after every rejected open attempt.
          owner = await Process.start(
            p.join(bundle.path, 'locald.exe'),
            ['--workspace', 'default', '--app-root', bundle.path],
            environment: {'LOCALAPPDATA': local.path},
          );
          final restoredOutput = owner.stdout.transform(utf8.decoder).join();
          final restoredErrors = owner.stderr.transform(utf8.decoder).join();
          final restored = await Process.run(
            p.join(bundle.path, 'serverdeck.exe'),
            [local.path, bundle.path, 'verify-recovered'],
          ).timeout(const Duration(seconds: 35));
          expect(
            restored.exitCode,
            0,
            reason: '${restored.stdout}\n${restored.stderr}',
          );
          expect(
            restored.stdout,
            contains('COMPILED_BOOTSTRAP_RECOVERY_DATA_PROVED'),
          );
          expect(await owner.exitCode.timeout(const Duration(seconds: 10)), 0);
          await restoredOutput;
          expect(await restoredErrors, isEmpty);
          owner = null;
        }
        final beforeFiles = snapshotLocal();
        final beforeDatabase = fileSha256(database);
        for (final mutation in ['testOnly', 'build', 'appRoot', 'hash']) {
          final invalid = jsonDecode(original) as Map<String, dynamic>;
          switch (mutation) {
            case 'testOnly':
              invalid['testOnly'] = true;
            case 'build':
              invalid['buildId'] = 'invalid-build';
            case 'appRoot':
              invalid['appRoot'] = root;
            case 'hash':
              (invalid['sha256'] as Map)['libisar.dll'] = '0' * 64;
          }
          manifestFile.writeAsStringSync(jsonEncode(invalid));
          final refused = await Process.run(
            p.join(bundle.path, 'locald.exe'),
            ['--workspace', 'default', '--app-root', bundle.path],
            environment: {'LOCALAPPDATA': local.path},
          ).timeout(const Duration(seconds: 10));
          expect(refused.exitCode, 1);
          expect(refused.stderr.toString().trim(), 'INCOMPATIBLE');
          expect(refused.stdout, isEmpty);
          expect(fileSha256(database), beforeDatabase);
          expect(snapshotLocal(), beforeFiles);
          expect(
            File(
              p.join(
                local.path,
                'ServerDeckNext',
                'v1',
                'runtime',
                'default.discovery',
              ),
            ).existsSync(),
            false,
          );
        }
        manifestFile.writeAsStringSync(original);
        final dll = File(p.join(bundle.path, 'libisar.dll'));
        final dllBytes = dll.readAsBytesSync();
        try {
          dll.deleteSync(); // Owned fixture; all compiled processes have exited.
          final refused = await Process.run(
            p.join(bundle.path, 'locald.exe'),
            ['--workspace', 'default', '--app-root', bundle.path],
            environment: {'LOCALAPPDATA': local.path},
          ).timeout(const Duration(seconds: 10));
          expect(refused.exitCode, 1);
          expect(refused.stderr.toString().trim(), 'PREREQUISITE_UNAVAILABLE');
          expect(refused.stdout, isEmpty);
          expect(snapshotLocal(), beforeFiles);
        } finally {
          dll.writeAsBytesSync(dllBytes);
        }
      } catch (_) {
        failed = true;
        rethrow;
      } finally {
        var cleanupFailed = false;
        Future<void> clean(Future<void> Function() action) async {
          try {
            await action();
          } catch (_) {
            cleanupFailed = true;
          }
        }

        for (final peer in peers) {
          await clean(() async {
            try {
              await peer.stdin.close();
            } on IOException {
              // The retained child may already have exited.
            }
            await peer.exitCode.timeout(const Duration(seconds: 35));
          });
        }
        await clean(() async {
          final observed = observer;
          if (observed != null) {
            await observed.stdin.close();
            await observed.exitCode.timeout(const Duration(seconds: 10));
            await observerErrors;
          }
          await observerOutput?.cancel();
        });
        crashedDescriptor?.close();
        await clean(() async {
          if (owner != null) {
            // Join the actual startup watchdog; never kill an external owner.
            await owner.exitCode.timeout(const Duration(seconds: 40));
          }
        });
        if (!failed && !cleanupFailed) {
          await clean(() async => fixture.deleteSync(recursive: true));
        }
        if (cleanupFailed) {
          if (!failed) throw StateError('FIXTURE_CLEANUP_UNCONFIRMED');
          stderr.writeln('FIXTURE_CLEANUP_UNCONFIRMED');
        }
        if (failed || cleanupFailed)
          stderr.writeln('FIXTURE_EVIDENCE_RETAINED:$root');
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
