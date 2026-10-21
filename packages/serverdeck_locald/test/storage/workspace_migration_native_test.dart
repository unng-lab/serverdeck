import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import '../support/migration_fixture.dart';

Future<String> run(MigrationFixture fixture, String mode) async {
  final child = await fixture.startMigration(mode);
  final output = child.stdout.transform(utf8.decoder).join();
  final errors = child.stderr.transform(utf8.decoder).join();
  expect(
    await child.exitCode.timeout(const Duration(seconds: 60)),
    0,
    reason: await errors,
  );
  return output;
}

Future<void> killAt(MigrationFixture fixture, String boundary) async {
  final child = await fixture.startMigration('kill', boundary);
  final errors = child.stderr.transform(utf8.decoder).join();
  final lines = StreamIterator(
    child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  try {
    while (await lines.moveNext().timeout(const Duration(seconds: 60))) {
      if (lines.current == 'BOUNDARY:$boundary') {
        expect(child.kill(), isTrue);
        expect(
          await child.exitCode.timeout(const Duration(seconds: 15)),
          isNot(0),
        );
        return;
      }
    }
    fail('Boundary $boundary not reached: ${await errors}');
  } finally {
    await lines.cancel();
  }
}

String active(MigrationFixture fixture) => p.join(
  fixture.root,
  'local',
  'ServerDeckNext',
  'v1',
  'workspaces',
  'default',
);

void main() {
  late Directory executableRoot;
  late String executable;
  setUpAll(() async {
    executableRoot = Directory.systemTemp.createTempSync(
      'serverdeck-migration-executable-',
    );
    executable = p.join(executableRoot.path, 'migration-fixture.exe');
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-DSERVERDECK_TEST_MIGRATION_PROBES=true',
      'test/support/migration_orchestrator_child.dart',
      '-o',
      executable,
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
  });
  tearDownAll(() {
    final target = p.normalize(p.absolute(executableRoot.path));
    if (!p.isWithin(
          p.normalize(p.absolute(Directory.systemTemp.path)),
          target,
        ) ||
        !p.basename(target).startsWith('serverdeck-migration-executable-')) {
      throw StateError('UNSAFE_FIXTURE');
    }
    executableRoot.deleteSync(recursive: true);
  });

  for (final variant in ['partial-native', 'future-marker']) {
    test(
      'migration refuses $variant without resetting unknown data',
      () async {
        final fixture = MigrationFixture.create(
          migrationExecutable: executable,
        );
        try {
          await run(fixture, 'prepare-$variant');
          final baseline = jsonDecode(
            File(p.join(fixture.root, 'baseline.json')).readAsStringSync(),
          ) as Map;
          expect(await run(fixture, 'refuse'), contains('REFUSED'));
          for (final name in [
            'workspace.isar',
            'workspace.manifest.json',
            'receipt-key.dpapi',
          ]) {
            expect(fileSha256(p.join(active(fixture), name)), baseline[name]);
          }
          if (variant == 'partial-native')
            expect(
              Directory('${active(fixture)}.upgrading-1-2').existsSync(),
              isFalse,
            );
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  for (final location in [
    'manifest',
    'key',
    'database',
    'lock',
    'stage-backup',
    'stage-db',
    'stage-dir',
  ]) {
    test(
      'migration refuses actual $location reparse and preserves its target',
      () async {
        final fixture = MigrationFixture.create(
          migrationExecutable: executable,
        );
        try {
          await run(fixture, 'prepare');
          final stage = '${active(fixture)}.upgrading-1-2';
          if (location.startsWith('stage-'))
            await killAt(fixture, 'preparedJournal');
          final path = switch (location) {
            'manifest' => p.join(active(fixture), 'workspace.manifest.json'),
            'key' => p.join(active(fixture), 'receipt-key.dpapi'),
            'database' => p.join(active(fixture), 'workspace.isar'),
            'lock' => p.join(active(fixture), 'workspace.isar-lck'),
            'stage-backup' => p.join(stage, 'original.isar'),
            'stage-db' => p.join(stage, 'workspace.isar'),
            _ => stage,
          };
          final retained = p.join(fixture.root, 'local', 'retained-$location');
          final before =
              FileSystemEntity.typeSync(path) == FileSystemEntityType.file
              ? fileSha256(path)
              : null;
          await promoteProtectedPath(
            fixture.root,
            path,
            retained,
            currentUserSid(),
          );
          try {
            await Link(path).create(retained);
            expect(
              FileSystemEntity.typeSync(path, followLinks: false),
              FileSystemEntityType.link,
            );
            expect(await run(fixture, 'refuse'), contains('REFUSED'));
            if (before != null) expect(fileSha256(retained), before);
            final baseline = jsonDecode(
              File(p.join(fixture.root, 'baseline.json')).readAsStringSync(),
            ) as Map;
            for (final name in [
              'workspace.isar',
              'workspace.manifest.json',
              'receipt-key.dpapi',
            ]) {
              expect(fileSha256(p.join(active(fixture), name)), baseline[name]);
            }
          } finally {
            if (FileSystemEntity.typeSync(path, followLinks: false) ==
                FileSystemEntityType.link)
              Link(path).deleteSync();
            await promoteProtectedPath(
              fixture.root,
              retained,
              path,
              currentUserSid(),
            );
          }
          await run(fixture, 'migrate');
          expect(
            await run(fixture, 'verify'),
            contains('EXACT_STATE_CREDENTIAL_RECEIPT_PRESERVATION_VERIFIED'),
          );
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  for (final fault in [
    'dpapi-key',
    'dpapi-credential',
    'space-initial',
    'space-journal',
    'space-published',
    'close-false',
    'close-throw',
    'boundary-nativeSchemaOpened',
    'boundary-uncommittedMarker',
    'boundary-markerCommitted',
    'boundary-preparedJournal',
    'boundary-databasePublished',
    'boundary-manifestPublished',
    'boundary-cleanupFile',
  ]) {
    test(
      'migration fault $fault retains source and required ownership',
      () async {
        final fixture = MigrationFixture.create(
          migrationExecutable: executable,
        );
        try {
          await run(fixture, 'prepare');
          if (fault.startsWith('close-')) {
            final child = await fixture.startMigration('fault-$fault');
            final errors = child.stderr.transform(utf8.decoder).join();
            final lines = StreamIterator(
              child.stdout
                  .transform(utf8.decoder)
                  .transform(const LineSplitter()),
            );
            var retained = false;
            try {
              while (await lines.moveNext().timeout(
                const Duration(seconds: 30),
              )) {
                if (lines.current == 'FAULT_RETAINED') {
                  retained = true;
                  break;
                }
              }
              expect(retained, isTrue, reason: retained ? null : await errors);
              expect(child.kill(), isTrue);
              expect(await child.exitCode, isNot(0));
            } finally {
              await lines.cancel();
            }
          } else {
            expect(
              await run(fixture, 'fault-$fault'),
              contains('FAULT_REFUSED'),
            );
          }
          final baseline = jsonDecode(
            File(p.join(fixture.root, 'baseline.json')).readAsStringSync(),
          ) as Map;
          final published = [
            'space-published',
            'boundary-databasePublished',
            'boundary-manifestPublished',
            'boundary-cleanupFile',
          ].contains(fault);
          for (final name in [
            'receipt-key.dpapi',
            if (!published) ...['workspace.isar', 'workspace.manifest.json'],
          ]) {
            expect(
              fileSha256(p.join(active(fixture), name)),
              baseline[name],
              reason: '$fault/$name',
            );
          }
          if (fault == 'dpapi-key' || fault == 'space-initial')
            expect(
              Directory('${active(fixture)}.upgrading-1-2').existsSync(),
              isFalse,
            );
          await run(fixture, 'migrate');
          expect(
            await run(fixture, 'verify'),
            contains('EXACT_STATE_CREDENTIAL_RECEIPT_PRESERVATION_VERIFIED'),
          );
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test(
    'migration preserves noncanonical raw payload bytes and native IDs',
    () async {
      final fixture = MigrationFixture.create(migrationExecutable: executable);
      try {
        await run(fixture, 'prepare-raw');
        await killAt(fixture, 'databasePublished');
        await run(fixture, 'migrate');
        expect(
          await run(fixture, 'verify'),
          contains('EXACT_STATE_CREDENTIAL_RECEIPT_PRESERVATION_VERIFIED'),
        );
      } finally {
        await fixture.close();
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  for (final state in [
    'missing-manifest',
    'journal-residue',
    'foreign-residue',
    'partial-stage',
  ]) {
    test(
      'migration recovery handles $state with strict bindings',
      () async {
        final fixture = MigrationFixture.create(
          migrationExecutable: executable,
        );
        try {
          await run(fixture, 'prepare');
          await killAt(
            fixture,
            state == 'missing-manifest'
                ? 'databasePublished'
                : 'preparedJournal',
          );
          final stage = '${active(fixture)}.upgrading-1-2';
          if (state == 'missing-manifest') {
            File(p.join(stage, 'manifest2.json')).deleteSync();
          } else if (state == 'partial-stage') {
            // Only a known stage copy is damaged; the intact source1 must be rebuilt.
            File(p.join(stage, 'workspace.isar'))
                .writeAsBytesSync([1, 2, 3], flush: true);
          } else {
            final value = jsonDecode(
              File(p.join(stage, 'migration.json')).readAsStringSync(),
            ) as Map<String, Object?>;
            if (state == 'foreign-residue')
              value['migrationId'] = '30000000-0000-4000-8000-000000000003';
            await writeNewProtectedFile(
              fixture.root,
              p.join(stage, 'migration.json.new'),
              currentUserSid(),
              utf8.encode(jsonEncode(value)),
            );
          }
          if (state == 'foreign-residue') {
            final before = {
              for (final name in [
                'workspace.isar',
                'workspace.manifest.json',
                'receipt-key.dpapi',
              ])
                name: fileSha256(p.join(active(fixture), name)),
            };
            expect(await run(fixture, 'refuse'), contains('REFUSED'));
            for (final entry in before.entries)
              expect(
                fileSha256(p.join(active(fixture), entry.key)),
                entry.value,
              );
          } else {
            await run(fixture, 'migrate');
            await run(fixture, 'migrate');
            expect(
              await run(fixture, 'verify'),
              contains('EXACT_STATE_CREDENTIAL_RECEIPT_PRESERVATION_VERIFIED'),
            );
          }
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  for (final ancestor in ['ServerDeckNext', 'v1']) {
    test(
      'migration refuses permissive $ancestor ancestor before staging',
      () async {
        final fixture = MigrationFixture.create(
          migrationExecutable: executable,
        );
        try {
          await run(fixture, 'prepare');
          final path = p.joinAll([
            fixture.root,
            'local',
            'ServerDeckNext',
            if (ancestor == 'v1') 'v1',
          ]);
          final acl = await Process.run('icacls.exe', [
            path,
            '/grant',
            '*S-1-1-0:(OI)(CI)(F)',
          ]);
          expect(acl.exitCode, 0, reason: '${acl.stdout}${acl.stderr}');
          expect(
            () => requireOwnerOnlyFileAcl(path, currentUserSid()),
            throwsStateError,
          );
          final baseline = jsonDecode(
            File(p.join(fixture.root, 'baseline.json')).readAsStringSync(),
          ) as Map;
          expect(await run(fixture, 'refuse'), contains('REFUSED'));
          for (final name in [
            'workspace.isar',
            'workspace.manifest.json',
            'receipt-key.dpapi',
          ]) {
            expect(fileSha256(p.join(active(fixture), name)), baseline[name]);
          }
          expect(
            Directory('${active(fixture)}.upgrading-1-2').existsSync(),
            isFalse,
          );
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test(
    'native migration completes, preserves DPAPI data and is repeatable',
    () async {
      final fixture = MigrationFixture.create(migrationExecutable: executable);
      try {
        expect(await run(fixture, 'prepare'), contains('PREPARED'));
        expect(await run(fixture, 'migrate'), contains('MIGRATED'));
        expect(await run(fixture, 'migrate'), contains('MIGRATED'));
        expect(
          await run(fixture, 'verify'),
          contains('EXACT_STATE_CREDENTIAL_RECEIPT_PRESERVATION_VERIFIED'),
        );
      } finally {
        await fixture.close();
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 3)),
  );

  for (final boundary in [
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
  ]) {
    test(
      'native process termination at $boundary recovers without reset',
      () async {
        final fixture = MigrationFixture.create(
          migrationExecutable: executable,
        );
        try {
          await run(fixture, 'prepare');
          await killAt(fixture, boundary);
          final beforeCommit = ![
            'databasePublished',
            'targetVerified',
            'manifestPublished',
            'cleanupFile:1',
            'cleanupFile:2',
            'cleanupFile:3',
            'journalRemoved',
            'stageRemoved',
          ].contains(boundary);
          final baseline = jsonDecode(
            File(p.join(fixture.root, 'baseline.json')).readAsStringSync(),
          ) as Map;
          for (final name in [
            'receipt-key.dpapi',
            if (beforeCommit) ...['workspace.isar', 'workspace.manifest.json'],
          ]) {
            expect(
              fileSha256(p.join(active(fixture), name)),
              baseline[name],
              reason: '$boundary/$name',
            );
          }
          await run(fixture, 'migrate');
          await run(fixture, 'migrate');
          expect(
            await run(fixture, 'verify'),
            contains('EXACT_STATE_CREDENTIAL_RECEIPT_PRESERVATION_VERIFIED'),
          );
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  for (final damage in [
    'unknown-file',
    'malformed-journal',
    'source-hash',
    'target-hash',
  ]) {
    test(
      'migration refuses $damage without resetting active files',
      () async {
        final fixture = MigrationFixture.create(
          migrationExecutable: executable,
        );
        try {
          await run(fixture, 'prepare');
          await killAt(
            fixture,
            damage == 'target-hash' ? 'databasePublished' : 'journalFlushed',
          );
          final stage = '${active(fixture)}.upgrading-1-2';
          if (damage == 'unknown-file') {
            await writeNewProtectedFile(
              fixture.root,
              p.join(stage, 'foreign'),
              currentUserSid(),
              [1],
            );
          } else if (damage == 'malformed-journal') {
            File(p.join(stage, 'migration.json'))
                .writeAsStringSync('{}', flush: true);
          } else {
            // A structural mutation-free hash mismatch: native DB remains valid.
            final journal = File(p.join(stage, 'migration.json'));
            final value =
                jsonDecode(journal.readAsStringSync()) as Map<String, Object?>;
            value[damage == 'source-hash'
                    ? 'sourceDbDigest'
                    : 'targetDbDigest'] =
                '0' * 64;
            journal.writeAsStringSync(jsonEncode(value), flush: true);
          }
          final hashes = {
            for (final name in [
              'workspace.isar',
              'workspace.manifest.json',
              'receipt-key.dpapi',
            ])
              name: fileSha256(p.join(active(fixture), name)),
          };
          expect(await run(fixture, 'refuse'), contains('REFUSED'));
          for (final entry in hashes.entries)
            expect(fileSha256(p.join(active(fixture), entry.key)), entry.value);
          expect(Directory(stage).existsSync(), isTrue);
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
