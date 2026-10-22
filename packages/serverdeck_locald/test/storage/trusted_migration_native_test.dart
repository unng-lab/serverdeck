import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../support/native_artifact.dart';

Stream<List<int>> bounded(Stream<List<int>> source) async* {
  var total = 0;
  await for (final bytes in source) {
    total += bytes.length;
    if (total > 65536) throw StateError('FIXTURE_OUTPUT_LIMIT');
    yield bytes;
  }
}

void main() {
  late Directory root;
  late String executable, dll;
  setUpAll(() async {
    dll = nativeArtifactForTest();
    root = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-upgrade-build-',
    );
    executable = p.join(root.path, 'actor.exe');
    final child = await Process.start(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-DSERVERDECK_TEST_MIGRATION_PROBES=true',
      'test/support/trusted_migration_actor.dart',
      '-o',
      executable,
    ]);
    final out = b.boundedOutput(child.stdout),
        err = b.boundedOutput(child.stderr);
    try {
      expect(
        await child.exitCode.timeout(const Duration(seconds: 90)),
        0,
        reason: '${await out}\n${await err}',
      );
    } finally {
      child.kill();
      await child.exitCode;
    }
  });
  tearDownAll(() {
    b.ownRoot(root.path);
    root.deleteSync(recursive: true);
  });
  b.Fixture fixture() {
    final f = b.Fixture(executable);
    File(dll).copySync(p.join(f.path, 'libisar.dll'));
    (f.document['sha256'] as Map)['libisar.dll'] = fileSha256(
      p.join(f.path, 'libisar.dll'),
    );
    f.document['format'] = 3;
    f.document['workspaceSchema'] = 3;
    f.write();
    return f;
  }

  Future<void> run(b.Fixture f, String mode) async {
    final name = mode == 'role-owner'
        ? 'serverdeck.exe'
        : mode == 'role-mcp'
        ? 'mcp.exe'
        : 'locald.exe';
    final child = await Process.start(p.join(f.path, name), [f.path, mode]);
    f.children.add(child);
    final out = b.boundedOutput(child.stdout),
        err = b.boundedOutput(child.stderr);
    f.errors.add(err);
    expect(
      await child.exitCode.timeout(const Duration(seconds: 60)),
      0,
      reason: '${await out}\n${await err}',
    );
    expect(await out, contains('PASS:$mode'));
  }

  Future<void> killAt(b.Fixture f, String boundary) async {
    final child = await Process.start(p.join(f.path, 'locald.exe'), [
      f.path,
      'kill',
      boundary,
    ]);
    f.children.add(child);
    final err = b.boundedOutput(child.stderr);
    f.errors.add(err);
    final lines = StreamIterator(
      bounded(child.stdout)
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    try {
      final watch = Stopwatch()..start();
      var count = 0;
      while (true) {
        final remaining = const Duration(seconds: 60) - watch.elapsed;
        expect(remaining > Duration.zero, isTrue);
        expect(await lines.moveNext().timeout(remaining), isTrue);
        expect(++count, lessThanOrEqualTo(64));
        expect(lines.current.length, lessThanOrEqualTo(4096));
        if (lines.current.startsWith('BOUNDARY:')) {
          expect(lines.current, 'BOUNDARY:$boundary');
          break;
        }
      }
      expect(child.kill(), isTrue);
      await child.exitCode.timeout(const Duration(seconds: 15));
    } finally {
      await lines.cancel();
    }
  }

  for (final source in [1, 2])
    test(
      'actual trusted migration from$source retains all old rows and repeats',
      () async {
        final f = fixture();
        try {
          await run(f, 'prepare$source');
          await run(f, 'verify');
          await run(f, 'verify');
        } finally {
          await f.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  for (final mode in [
    'writer-graph',
    for (final state in [
      'queued',
      'running',
      'cancel-requested',
      'unknown',
      'reconciling',
    ])
      'writer-busy-$state',
  ])
    test(
      'trusted writes preserve full automation graph $mode',
      () async {
        final f = fixture();
        try {
          await run(f, 'prepare2');
          await run(f, mode);
        } finally {
          await f.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  test(
    'trusted migration holds one reservation across both steps',
    () async {
      final f = fixture();
      try {
        await run(f, 'prepare1');
        await run(f, 'reservation');
        await run(f, 'verify');
      } finally {
        await f.close();
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'actual occupied source refuses before staging',
    () async {
      final f = fixture();
      try {
        await run(f, 'prepare-busy');
        await run(f, 'busy');
      } finally {
        await f.close();
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 2)),
  );
  for (final mode in ['role-owner', 'role-mcp', 'format2'])
    test(
      'trusted migration refuses $mode',
      () async {
        final f = fixture();
        try {
          if (mode == 'format2') {
            f.document['format'] = 2;
            f.document['workspaceSchema'] = 2;
            f.write();
          }
          await run(f, mode);
        } finally {
          await f.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  for (final fault in [
    'dpapi',
    'space-initial',
    'space-published',
    'close-false',
    'close-throw',
    'close-target',
  ]) {
    test(
      'trusted migration fault $fault fails closed and recovers',
      () async {
        final f = fixture();
        try {
          await run(f, 'prepare2');
          await run(f, 'fault-$fault');
          await run(f, 'verify');
          await run(f, 'verify');
        } finally {
          await f.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  test(
    'trusted migration rejects unknown protected stage before active preflight',
    () async {
      final f = fixture();
      try {
        await run(f, 'prepare2');
        final active = p.join(
          f.path,
          'ServerDeckNext',
          'v1',
          'workspaces',
          'default',
        );
        final stage = '$active.upgrading-2-3';
        createProtectedDirectory(f.path, stage, currentUserSid());
        await writeNewProtectedFile(
          f.path,
          p.join(stage, 'unknown'),
          currentUserSid(),
          [1, 2, 3],
        );
        final hash = fileSha256(p.join(active, 'workspace.isar'));
        await run(f, 'blocked');
        expect(fileSha256(p.join(active, 'workspace.isar')), hash);
        File(p.join(stage, 'unknown')).deleteSync();
        await run(f, 'verify');
      } finally {
        await f.close();
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 2)),
  );
  for (final damage in ['source', 'target', 'rows', 'cross-step'])
    test(
      'trusted migration rejects bound journal $damage damage',
      () async {
        final f = fixture();
        try {
          await run(f, 'prepare2');
          await killAt(
            f,
            damage == 'source' || damage == 'cross-step'
                ? 'preparedJournal'
                : 'databasePublished',
          );
          final active = p.join(
            f.path,
            'ServerDeckNext',
            'v1',
            'workspaces',
            'default',
          );
          final journal = File(
            p.join('$active.upgrading-2-3', 'migration.json'),
          );
          final original = journal.readAsBytesSync();
          final fields =
              jsonDecode(utf8.decode(original)) as Map<String, Object?>;
          if (damage == 'cross-step') {
            fields['fromSchema'] = 1;
            fields['toSchema'] = 2;
          } else {
            fields[damage == 'source'
                    ? 'sourceDbDigest'
                    : damage == 'target'
                    ? 'targetDbDigest'
                    : 'sourceRowsDigest'] =
                '0' * 64;
          }
          journal.writeAsStringSync(jsonEncode(fields), flush: true);
          final hashes = {
            for (final name in [
              'workspace.isar',
              'workspace.manifest.json',
              'receipt-key.dpapi',
            ])
              name: fileSha256(p.join(active, name)),
          };
          await run(f, 'blocked');
          for (final e in hashes.entries)
            expect(fileSha256(p.join(active, e.key)), e.value);
          journal.writeAsBytesSync(original, flush: true);
          await run(f, 'verify');
          await run(f, 'verify');
        } finally {
          await f.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  final boundaries = [
    'sourceValidated',
    'journalFlushed',
    'backupCopied',
    'sourceRowsValidated',
    'nativeSchemaOpened',
    'uncommittedMarker',
    'markerCommitted',
    'candidateClosed',
    'preparedJournal',
    'databasePublished',
    'targetVerified',
    'manifestPublished',
    'cleanupFile:1',
    'cleanupFile:2',
    'cleanupFile:3',
    'journalRemoved',
    'stageRemoved',
  ];
  for (final scenario in [
    for (final boundary in boundaries) (source: 2, boundary: boundary),
    (source: 1, boundary: 'databasePublished:1'),
    (source: 1, boundary: 'databasePublished:2'),
  ]) {
    final boundary = scenario.boundary;
    test(
      'actual trusted migration kill recovery from${scenario.source} $boundary',
      () async {
        final f = fixture();
        try {
          await run(f, 'prepare${scenario.source}');
          await killAt(f, boundary);
          final active = p.join(
            f.path,
            'ServerDeckNext',
            'v1',
            'workspaces',
            'default',
          );
          final baseline = jsonDecode(
            File(p.join(f.path, 'fixture-baseline.json')).readAsStringSync(),
          ) as Map;
          expect(
            fileSha256(p.join(active, 'receipt-key.dpapi')),
            baseline['receipt-key.dpapi'],
          );
          if ([
            'sourceValidated',
            'journalFlushed',
            'backupCopied',
            'sourceRowsValidated',
            'nativeSchemaOpened',
            'uncommittedMarker',
            'markerCommitted',
            'candidateClosed',
            'preparedJournal',
          ].contains(boundary)) {
            expect(
              fileSha256(p.join(active, 'workspace.isar')),
              baseline['workspace.isar'],
            );
            expect(
              fileSha256(p.join(active, 'workspace.manifest.json')),
              baseline['workspace.manifest.json'],
            );
          }
          await run(f, 'verify');
          await run(f, 'verify');
        } finally {
          await f.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
