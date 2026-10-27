import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/native_schema.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import 'credential_validation_test.dart' as credentialFixture;
import 'models_test.dart' as fixture;
import 'support/native_snapshot_fixture.dart';
import 'support/native_artifact.dart';

bool hasBytes(List<int> bytes, String marker) {
  final pattern = utf8.encode(marker);
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

Uint8List replaceBytes(Uint8List input, String before, String after) {
  final source = utf8.encode(before), replacement = utf8.encode(after);
  if (source.length != replacement.length) throw StateError('TEST_LENGTH');
  final copy = Uint8List.fromList(input);
  var replaced = 0;
  for (var i = 0; i <= copy.length - source.length; i++) {
    if (List.generate(
      source.length,
      (j) => copy[i + j] == source[j],
    ).every((v) => v)) {
      copy.setRange(i, i + replacement.length, replacement);
      replaced++;
    }
  }
  if (replaced == 0) throw StateError('TEST_MARKER_MISSING');
  return copy;
}

void main() {
  group('native records', () {
    setUpAll(() async {
      final setupWatch = Stopwatch()..start();
      try {
        final nativeLibrary = nativeArtifactForTest();
        await Isar.initializeIsarCore(
          libraries: {Abi.windowsX64: nativeLibrary},
          download: false,
        );
      } finally {
        setupWatch.stop();
        // ignore: avoid_print
        print(
          'NATIVE_RECORDS_SETUP_ELAPSED_MS:${setupWatch.elapsedMilliseconds}',
        );
      }
    });

    test('ordinary rows persist with DPAPI secrets; unique collision rolls back all writes', () async {
      final workloadWatch = Stopwatch()..start();
      try {
        final sid = currentUserSid();
        const secretMarker = 'synthetic-access-secret-6eea5d71';
        final custody = KeyCustody(DpapiProtection(), sid);
        final blob = await custody.wrapCredential(
          fixture.workspace,
          fixture.profileId,
          fixture.credentialId,
          {'action': 'replace', 'kind': 'password', 'password': secretMarker},
        );
        final state = credentialFixture.state(sid, blob);
        final records = WorkspaceRecords.fromState(state);
        final metadata = jsonDecode(records.workspace.payload) as Map;
        expect(metadata.keys.toSet(), {
          'schemaVersion',
          'workspaceId',
          'receiptKeyId',
          'ownerSid',
          'storeRevision',
        });
        expect(records.workspace.id, 1);
        expect(records.settings.id, 1);
        expect(records.profiles.single.entityId, fixture.profileId);
        expect(records.credentials.single.entityId, fixture.credentialId);
        expect(records.receipts.single.entityId, fixture.requestId);
        expect(records.profiles.single.payload, contains('example.invalid'));
        expect(
          records.credentials.single.payload,
          isNot(contains(secretMarker)),
        );
        expect(workspaceSchemas.map((s) => s.name).toSet(), {
          'StoredWorkspace',
          'StoredSettings',
          'StoredProfile',
          'StoredCredential',
          'StoredReceipt',
        });
        for (final schema in [
          StoredProfileSchema,
          StoredCredentialSchema,
          StoredReceiptSchema,
        ]) {
          final index = schema.indexes.values.single;
          expect(index.unique, isTrue);
          expect(index.replace, isFalse);
          expect(index.properties.single.caseSensitive, isTrue);
          expect(index.properties.single.type, IndexType.hash);
          expect(schema.links, isEmpty);
        }

        final parent = Directory.systemTemp.createTempSync(
          'serverdeck-records-fixture-',
        );
        final root = p.normalize(p.absolute(parent.path));
        if (!p.isWithin(
          p.normalize(p.absolute(Directory.systemTemp.path)),
          root,
        )) {
          throw StateError('UNSAFE_TEST_DIRECTORY');
        }
        final database = p.join(root, 'workspace');
        Isar? isar;
        try {
          createProtectedDirectory(root, database, sid);
          for (final name in ['workspace.isar', 'workspace.isar-lck']) {
            await createProtectedEmptyFile(root, p.join(database, name), sid);
          }
          isar = await Isar.open(
            workspaceSchemas,
            directory: database,
            name: 'workspace',
            maxSizeMiB: 64,
            relaxedDurability: false,
            inspector: false,
          );
          final Isar active = isar;
          await active.writeTxn(() async {
            await active.storedWorkspaces.put(records.workspace);
            await active.storedSettings.put(records.settings);
            await active.storedProfiles.putAll(records.profiles);
            await active.storedCredentials.putAll(records.credentials);
            await active.storedReceipts.putAll(records.receipts);
          });
          await expectLater(
            active.writeTxn(() async {
              await active.storedWorkspaces.put(
                StoredWorkspace()
                  ..payload = records.workspace.payload.replaceFirst(
                    '"storeRevision":"1"',
                    '"storeRevision":"2"',
                  ),
              );
              await active.storedProfiles.put(
                StoredProfile()
                  ..entityId = fixture.profileId
                  ..payload = records.profiles.single.payload,
              );
            }),
            throwsA(isA<IsarError>()),
          );
          expect(
            (await active.storedWorkspaces.get(1))!.payload,
            records.workspace.payload,
          );
          expect(await active.storedProfiles.count(), 1);
          await isar.close();
          isar = null;
          final bytes = File(p.join(database, 'workspace.isar'))
              .readAsBytesSync();
          final unchanged = Uint8List.fromList(bytes);
          validateNativeSnapshot(bytes);
          expect(bytes, unchanged);
          for (final info in [false, true]) {
            final branch = branchFixture(bytes, info: info);
            validateNativeSnapshot(branch.bytes);
            final damaged = Uint8List.fromList(branch.bytes);
            final d = ByteData.sublistView(damaged);
            damaged.fillRange(
              branch.separator + 8,
              branch.separator +
                  8 +
                  d.getUint16(branch.separator + 6, Endian.little),
              0x7a,
            );
            expect(
              () => validateNativeSnapshot(damaged),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'code',
                  'STORAGE_BLOCKED',
                ),
              ),
            );
          }
          for (final incompatible in [
            replaceBytes(bytes, '"version":2', '"version":3'),
            replaceBytes(
              bytes,
              '"name":"StoredProfile"',
              '"name":"ForeignProfil"',
            ),
            replaceBytes(bytes, '_info', '_xxxx'),
          ]) {
            ByteData.sublistView(incompatible).setUint32(
              namedDescriptor(bytes, 'StoredProfile') + 8,
              0,
              Endian.little,
            );
            expect(
              () => validateNativeSnapshot(incompatible),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'code',
                  'STORAGE_BLOCKED',
                ),
              ),
            );
          }
          expect(
            () => validateNativeSnapshot(Uint8List.sublistView(bytes, 0, 100)),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'code',
                'STORAGE_BLOCKED',
              ),
            ),
          );
          expect(
            () => validateNativeSnapshot(
              replaceBytes(bytes, '"version":2', '"version":3'),
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'code',
                'INCOMPATIBLE',
              ),
            ),
          );
          expect(
            () => validateNativeSnapshot(
              replaceBytes(bytes, '"version":2', '"version":x'),
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'code',
                'STORAGE_BLOCKED',
              ),
            ),
          );
          final native = ByteData.sublistView(bytes);
          final size = native.getUint32(64, Endian.little);
          var selected = 0;
          for (var i = 1; i < 3; i++) {
            if (native.getUint64(i * size + 28, Endian.little) >
                native.getUint64(selected + 28, Endian.little))
              selected = i * size;
          }
          final main = native.getUint32(selected + 116, Endian.little) * size;
          for (final corrupt in <void Function(ByteData)>[
            (d) => d.setUint32(selected + 116, 0, Endian.little),
            (d) => d.setUint64(selected + 188, 1, Endian.little),
            (d) => d.setUint16(main + 12, 3, Endian.little),
            (d) => d.setUint16(main + 20, 0, Endian.little),
            (d) => d.setUint16(
              main + 22,
              d.getUint16(main + 20, Endian.little),
              Endian.little,
            ),
            (d) => d.setUint64(selected + 140, 100, Endian.little),
          ]) {
            final damaged = Uint8List.fromList(bytes);
            corrupt(ByteData.sublistView(damaged));
            expect(
              () => validateNativeSnapshot(damaged),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'code',
                  'STORAGE_BLOCKED',
                ),
              ),
            );
          }
          expect(
            File(p.join(database, 'workspace.isar')).readAsBytesSync(),
            unchanged,
          );
          expect(hasBytes(bytes, 'example.invalid'), isTrue);
          expect(hasBytes(bytes, secretMarker), isFalse);
          requireOwnerOnlyFileAcl(database, sid);
          for (final name in ['workspace.isar', 'workspace.isar-lck']) {
            requireOwnerOnlyFileAcl(p.join(database, name), sid);
          }
          isar = await Isar.open(
            workspaceSchemas,
            directory: database,
            name: 'workspace',
            maxSizeMiB: 64,
            relaxedDurability: false,
            inspector: false,
          );
          expect(
            (await isar.storedWorkspaces.get(1))!.payload,
            records.workspace.payload,
          );
          expect(
            (await isar.storedReceipts.get(records.receipts.single.id))!
                .payload,
            records.receipts.single.payload,
          );
          final persisted = jsonDecode(
            (await isar.storedCredentials.get(records.credentials.single.id))!
                .payload,
          ) as Map;
          final recovered = await custody.openCredential(
            persisted['protectedBlob'] as String,
            fixture.workspace,
            fixture.profileId,
            fixture.credentialId,
          );
          expect(recovered['password'], secretMarker);
          recovered.clear();
          await isar.close();
          isar = null;
          for (final name in ['foreign.isar', 'foreign.isar.lock']) {
            await createProtectedEmptyFile(root, p.join(database, name), sid);
          }
          isar = await Isar.open(
            workspaceSchemas
                .where((schema) => schema.name != 'StoredSettings')
                .toList(),
            directory: database,
            name: 'foreign',
            maxSizeMiB: 64,
            relaxedDurability: false,
            inspector: false,
          );
          await isar.close();
          isar = null;
          final foreignFile = File(p.join(database, 'foreign.isar'));
          final foreign = foreignFile.readAsBytesSync();
          expect(
            () => validateNativeSnapshot(foreign),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'code',
                'INCOMPATIBLE',
              ),
            ),
          );
          expect(foreignFile.readAsBytesSync(), foreign);
        } finally {
          await isar?.close();
          parent.deleteSync(recursive: true);
        }
      } finally {
        workloadWatch.stop();
        // ignore: avoid_print
        print(
          'NATIVE_RECORDS_WORKLOAD_ELAPSED_MS:${workloadWatch.elapsedMilliseconds}',
        );
      }
    }, testOn: 'windows');
  }, testOn: 'windows');
}
