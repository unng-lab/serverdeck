import 'package:serverdeck_engine/storage/preflight.dart';
import 'package:serverdeck_protocol/codec.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/storage/native_schema.dart';
import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_engine/storage/workspace_snapshot.dart';
import 'package:test/test.dart';

import '../support/native_workspace_fixture.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'workspace_snapshot_test.dart' show Setup;

Matcher failure([String code = 'STORAGE_BLOCKED']) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));
String get directory => p.absolute('unit-detached-native-snapshot');
NativeWorkspaceRows decode(NativeFixture source) =>
    NativeWorkspaceRows.fromSnapshot(source.bytes, directory: directory);

Future<WorkspaceSnapshot> inspect(Setup setup, WorkspaceRowSource source) =>
    inspectWorkspaceSnapshot(
      source,
      setup.key,
      setup.custody,
      localAppData: setup.files.root,
      lease: setup.lease,
      protectedFiles: setup.files,
    );

void main() {
  test(
    'empty inline GC PNL remains valid but four-byte GC overflow refuses',
    () async {
      final setup = await Setup.create();
      final inline = nativeFixture(
        setup.source.data,
        gc: true,
        gcPayloadBytes: 4,
      );
      await preflightWorkspace(
        inline.bytes,
        files: setup.files,
        lease: setup.lease,
        key: setup.key,
        custody: setup.custody,
      );
      final bad = nativeFixture(
        setup.source.data,
        gc: true,
        gcPayloadBytes: 4,
        forceGcOverflow: true,
      );
      final before = Uint8List.fromList(bad.bytes);
      await expectLater(
        preflightWorkspace(
          bad.bytes,
          files: setup.files,
          lease: setup.lease,
          key: setup.key,
          custody: setup.custody,
        ),
        failure(),
      );
      expect(bad.bytes, before);
      expect(setup.files.writes, 0);
    },
  );

  test(
    'GC may retain one reserved overflow page with all pages accounted',
    () async {
      final setup = await Setup.create();
      final source = nativeFixture(
        setup.source.data,
        gc: true,
        gcPayloadBytes: 8196,
        gcFreePages: 2048,
        gcSparePages: 1,
      );
      final before = Uint8List.fromList(source.bytes);
      await preflightWorkspace(
        source.bytes,
        files: setup.files,
        lease: setup.lease,
        key: setup.key,
        custody: setup.custody,
      );
      expect(source.bytes, before);
      expect(setup.files.writes, 0);
    },
  );

  for (final mode in [
    'truncated',
    'out of range',
    'free overlap',
    'extra reserve',
  ]) {
    test(
      'GC reserved overflow $mode refuses with unchanged bytes/no writes',
      () async {
        final setup = await Setup.create();
        final source = nativeFixture(
          setup.source.data,
          gc: true,
          gcPayloadBytes: 8196,
          gcFreePages: 2048,
          gcSparePages: mode == 'extra reserve' ? 2 : 1,
        );
        final overflow = (source.objectOffset('gc') - 20) ~/ pageSize;
        if (mode == 'out of range') {
          source.data.setUint32(
            overflow * pageSize + 12,
            source.bytes.length ~/ pageSize,
            Endian.little,
          );
        }
        if (mode == 'free overlap') {
          source.data.setUint32(
            overflow * pageSize + 24,
            overflow + 1,
            Endian.little,
          );
        }
        final bytes = mode == 'truncated'
            ? Uint8List.fromList(
                source.bytes.sublist(0, source.bytes.length - pageSize),
              )
            : source.bytes;
        final before = Uint8List.fromList(bytes);
        await expectLater(
          preflightWorkspace(
            bytes,
            files: setup.files,
            lease: setup.lease,
            key: setup.key,
            custody: setup.custody,
          ),
          failure(),
        );
        expect(bytes, before);
        expect(setup.files.writes, 0);
      },
    );
  }

  for (final mode in [
    'single-child branch',
    'odd leaf upper',
    'odd branch upper',
  ]) {
    test('committed $mode refuses before native open with no writes', () async {
      final setup = await Setup.create();
      final source = nativeFixture(
        {
          'StoredProfile': [
            const StoredRow(1, '{}', entityId: 'hello'),
            if (mode == 'odd branch upper')
              const StoredRow(256, '{}', entityId: 'world'),
          ],
        },
        branch: mode != 'odd leaf upper',
        singleChildBranch: mode == 'single-child branch',
      );
      final base = source.roots['StoredProfile']! * pageSize;
      if (mode == 'single-child branch') {
        expect(source.data.getUint16(base + 12, Endian.little), 2);
      } else {
        expect(() => decode(source), returnsNormally);
        final upper = source.data.getUint16(base + 14, Endian.little);
        source.data.setUint16(base + 14, upper - 1, Endian.little);
      }
      final before = Uint8List.fromList(source.bytes);
      await expectLater(
        preflightWorkspace(
          source.bytes,
          files: setup.files,
          lease: setup.lease,
          key: setup.key,
          custody: setup.custody,
        ),
        failure(),
      );
      expect(source.bytes, before);
      expect(setup.files.writes, 0);
    });
  }

  for (final mode in ['root', 'branch child', 'overflow']) {
    test(
      'page newer than $mode transaction front refuses without writes',
      () async {
        final setup = await Setup.create();
        final source = nativeFixture({
          'StoredProfile': [
            const StoredRow(1, '{}', entityId: 'hello'),
            if (mode == 'branch child')
              const StoredRow(256, '{}', entityId: 'world'),
          ],
          if (mode == 'overflow')
            'StoredCredential': [
              StoredRow(
                83,
                jsonEncode({'blob': 'x' * 40000}),
                entityId: fixture.credential,
              ),
            ],
        }, branch: mode == 'branch child');
        expect(() => decode(source), returnsNormally);
        int page;
        if (mode == 'root') {
          page = source.roots['StoredProfile']!;
        } else if (mode == 'branch child') {
          page = source.data.getUint32(
            source.firstNode('StoredProfile'),
            Endian.little,
          );
        } else {
          page = (source.objectOffset('StoredCredential') - 20) ~/ pageSize;
        }
        // Still below selected meta5, but above the root/tree/leaf front3.
        source.data.setUint64(page * pageSize, 4, Endian.little);
        final before = Uint8List.fromList(source.bytes);
        await expectLater(
          preflightWorkspace(
            source.bytes,
            files: setup.files,
            lease: setup.lease,
            key: setup.key,
            custody: setup.custody,
          ),
          failure(),
        );
        expect(source.bytes, before);
        expect(setup.files.writes, 0);
      },
    );
  }

  test('only the exact pinned steady signature admits the newest meta', () {
    for (final signature in [0, 1, 2, 3, 0x7fffffffffffffff]) {
      final source = nativeFixture({});
      source.data.setUint64(2 * pageSize + 188, signature, Endian.little);
      expect(() => decode(source), failure(), reason: 'signature $signature');
    }
    expect(() => decode(nativeFixture({})), returnsNormally);
  });

  test(
    'geometry rejects invalid bounds and any native correction before open',
    () async {
      final setup = await Setup.create();
      final valid = nativeFixture(setup.source.data);
      final pages = valid.bytes.length ~/ pageSize;
      for (final change in <(int, int)>[
        (44, 0),
        (44, 2),
        (44, 0x80000001),
        (48, 0),
        (48, 2),
        (48, 0x80000001),
        (52, 0),
        (52, 2),
        (52, pages + 17),
        (52, pages - 1),
      ]) {
        final source = nativeFixture(setup.source.data);
        source.data.setUint32(
          2 * pageSize + change.$1,
          change.$2,
          Endian.little,
        );
        await expectLater(
          preflightWorkspace(
            source.bytes,
            files: setup.files,
            lease: setup.lease,
            key: setup.key,
            custody: setup.custody,
          ),
          failure(),
          reason: 'geometry $change',
        );
        expect(setup.files.writes, 0);
      }
    },
  );

  test(
    'equal complete transactions clash even when all referenced bytes match',
    () {
      final source = nativeFixture({});
      source.data.setUint64(pageSize + 28, 5, Endian.little);
      source.data.setUint64(pageSize + 196, 5, Endian.little);
      expect(() => decode(source), failure());
    },
  );

  test('provider diagnostics are normalized before preflight and never cause writes', () async {
    final setup = await Setup.create();
    setup.files.denied.add(setup.files.root);
    await expectLater(
      preflightWorkspace(
        nativeFixture(setup.source.data).bytes,
        files: setup.files,
        lease: setup.lease,
        key: setup.key,
        custody: setup.custody,
      ),
      failure(),
    );
    expect(setup.files.writes, 0);
  });

  test('complete read-only preflight validates optional executor sidecar without writes', () async {
    final setup = await Setup.create(populated: true);
    final bytes = nativeFixture(setup.source.data).bytes;
    final snapshot = await preflightWorkspace(
      bytes,
      files: setup.files,
      lease: setup.lease,
      key: setup.key,
      custody: setup.custody,
    );
    expect(snapshot.foundation.foundation.workspaceId, fixture.workspace);
    expect(setup.files.writes, 0);
    final document = <String, Object?>{
      'format': 1,
      'workspaceId': fixture.workspace,
      'receiptKeyId': fixture.receiptKey,
      'records': [],
    };
    final encoded = StrictCodec().encode({
      'document': document,
      'mac': setup.custody.receiptDigestSync(setup.key, {
        'purpose': 'executor-enrollments-v1',
        'document': document,
      }),
    }, maxBytes: 4096);
    final path = p.join(setup.source.directory, 'executor-enrollments.json');
    setup.files.data[path] = encoded;
    await expectLater(
      preflightWorkspace(
        bytes,
        files: setup.files,
        lease: setup.lease,
        key: setup.key,
        custody: setup.custody,
      ),
      failure(),
    );
    expect(setup.files.data[path], encoded);
    expect(setup.files.writes, 0);
  });

  test('ambiguous equal committed metas and out-of-range complete transaction refuse', () {
    final ambiguous = nativeFixture({});
    ambiguous.data.setUint64(pageSize + 28, 5, Endian.little);
    ambiguous.data.setUint64(pageSize + 196, 5, Endian.little);
    ambiguous.data.setUint32(pageSize + 116, 0, Endian.little);
    expect(() => decode(ambiguous), failure());
    final invalid = nativeFixture({});
    invalid.data.setInt64(28, -1, Endian.little);
    invalid.data.setInt64(196, -1, Endian.little);
    expect(() => decode(invalid), failure());
  });
  test('all16 native trees preserve IDs/bytes in a detached immutable committed view', () async {
    final setup = await Setup.create(populated: true);
    final source = nativeFixture(setup.source.data, gc: true);
    final view = NativeWorkspaceRows.fromSnapshot(
      source.bytes,
      directory: setup.source.directory,
    );
    source.bytes.fillRange(0, source.bytes.length, 0);
    final snapshot = await inspect(setup, view);
    for (final entry in setup.source.data.entries) {
      final expected = List.of(entry.value)
        ..sort((a, b) => a.nativeId.compareTo(b.nativeId));
      expect(
        snapshot.rows[entry.key]!.map(
          (r) => (r.nativeId, r.entityId, r.payload),
        ),
        expected.map((r) => (r.nativeId, r.entityId, r.payload)),
      );
    }
    expect(setup.files.writes, 0);
    expect(await setup.artifacts.readLookupForRecovery(fixture.grant), isNull);
    await expectLater(view.read('unknown', limit: 1), failure());
    await expectLater(view.read('StoredWorkspace', limit: 0), failure());
  });

  test(
    'reopened rows must match preflight before lookup publication',
    () async {
      final setup = await Setup.create(populated: true);
      final view = NativeWorkspaceRows.fromSnapshot(
        nativeFixture(setup.source.data).bytes,
        directory: setup.source.directory,
      );
      final before = await inspect(setup, view),
          after = await inspect(setup, setup.source);
      requireSameWorkspaceRows(before, after);
      expect(setup.files.writes, 0);
      await recoverWorkspaceLookups(
        after,
        files: setup.files,
        lease: setup.lease,
        key: setup.key,
        custody: setup.custody,
      );
      expect(
        (await setup.artifacts.readLookupForRecovery(fixture.grant))!
            .binding
            .secretRef,
        fixture.secretRef,
      );
      expect(setup.files.writes, greaterThan(0));
      final old = setup.source.data['StoredProfile']!.single;
      setup.source.data['StoredProfile'] = [
        StoredRow(old.nativeId + 1, old.payload, entityId: old.entityId),
      ];
      final changed = await inspect(setup, setup.source);
      expect(() => requireSameWorkspaceRows(before, changed), failure());
    },
  );

  test(
    'raw whitespace changes after open are not silently normalized by readback',
    () async {
      final setup = await Setup.create();
      final old = setup.source.data['StoredSettings']!.single;
      setup.source.data['StoredSettings'] = [
        StoredRow(1, '  ${old.payload}\n'),
      ];
      final before = await inspect(
        setup,
        NativeWorkspaceRows.fromSnapshot(
          nativeFixture(setup.source.data).bytes,
          directory: setup.source.directory,
        ),
      );
      setup.source.data['StoredSettings'] = [old];
      final after = await inspect(setup, setup.source);
      expect(() => requireSameWorkspaceRows(before, after), failure());
      expect(setup.files.writes, 0);
    },
  );

  test(
    'numeric IDs across branch pages and independent XXH3 vector index decode',
    () async {
      final source = nativeFixture({
        'StoredProfile': [
          const StoredRow(256, '{"n":256}', entityId: 'hello'),
          const StoredRow(1, '{"n":1}', entityId: 'other'),
        ],
      }, branch: true);
      final rows = await decode(source).read('StoredProfile', limit: 251);
      expect(rows.map((r) => r.nativeId), [1, 256]);
      expect(rows.last.entityId, 'hello');
      expect(rows.last.payload, '{"n":256}');
    },
  );

  test(
    'overflow payload is bounded and corrupt overflow page counts are refused',
    () async {
      final payload = jsonEncode({'blob': 'x' * 40000});
      final source = nativeFixture({
        'StoredCredential': [
          StoredRow(83, payload, entityId: fixture.credential),
        ],
      });
      expect(
        (await decode(
          source,
        ).read('StoredCredential', limit: 251)).single.payload,
        payload,
      );
      final node = source.firstNode('StoredCredential');
      final pointer = node + 8 + source.data.getUint16(node + 6, Endian.little);
      final overflow = source.data.getUint32(pointer, Endian.little);
      source.data.setUint32(overflow * pageSize + 12, 0, Endian.little);
      expect(() => decode(source), failure());
    },
  );

  test('wrong/missing index entry and native ID mappings fail before native access', () {
    for (final mode in ['hash', 'id', 'duplicate-page']) {
      final source = nativeFixture({
        'StoredProfile': [const StoredRow(71, '{}', entityId: fixture.profile)],
      });
      final index = source.firstNode('_i_StoredProfile_entityId');
      if (mode == 'hash') source.bytes[index + 8] ^= 1;
      if (mode == 'id') source.bytes[index + 16] ^= 1;
      if (mode == 'duplicate-page') {
        // Point index descriptor at the already visited collection page.
        final main = source.roots['main']! * pageSize;
        final count = source.data.getUint16(main + 12, Endian.little) ~/ 2;
        for (var i = 0; i < count; i++) {
          final node =
              main +
              20 +
              source.data.getUint16(main + 20 + i * 2, Endian.little);
          final length = source.data.getUint16(node + 6, Endian.little);
          final name = utf8.decode(
            source.bytes.sublist(node + 8, node + 8 + length),
          );
          if (name == '_i_StoredProfile_entityId') {
            source.data.setUint32(
              node + 8 + length + 8,
              source.roots['StoredProfile']!,
              Endian.little,
            );
          }
        }
      }
      expect(() => decode(source), failure());
    }
  });

  test('malformed object offsets/static size/UTF8 never reach native deserialization', () {
    for (final mode in ['static', 'offset', 'overlap', 'utf8']) {
      final source = nativeFixture({
        'StoredProfile': [const StoredRow(71, '{}', entityId: fixture.profile)],
      });
      final at = source.objectOffset('StoredProfile');
      if (mode == 'static') source.bytes[at] = 7;
      if (mode == 'offset') {
        source.bytes[at + 2] = 255;
        source.bytes[at + 3] = 255;
        source.bytes[at + 4] = 255;
      }
      if (mode == 'overlap')
        source.bytes.setRange(
          at + 5,
          at + 8,
          source.bytes.sublist(at + 2, at + 5),
        );
      if (mode == 'utf8') source.bytes[at + 11] = 255;
      expect(() => decode(source), failure());
    }
    for (final id in [0, -1]) {
      expect(
        () => decode(
          nativeFixture({
            'StoredProfile': [StoredRow(id, '{}', entityId: fixture.profile)],
          }),
        ),
        failure(),
      );
    }
  });

  test('GC cannot free live pages or contain out-of-range page numbers', () {
    for (final mode in ['live', 'range', 'count']) {
      final source = nativeFixture({}, gc: true);
      final node = source.firstNode('gc'), value = node + 16;
      if (mode == 'live')
        source.data.setUint32(value + 4, source.roots['main']!, Endian.little);
      if (mode == 'range')
        source.data.setUint32(
          value + 4,
          source.bytes.length ~/ pageSize,
          Endian.little,
        );
      if (mode == 'count') source.data.setUint32(value, 1000, Endian.little);
      expect(() => decode(source), failure());
    }
  });

  test('logical corruption after binary extraction refuses without file publication', () async {
    for (final name in [
      'StoredProfile',
      'StoredHostTrust',
      'StoredMcpGrant',
      'StoredAutomationJob',
    ]) {
      final setup = await Setup.create(populated: true);
      setup.source.data[name] = [
        StoredRow(71, '{}', entityId: fixture.profile),
      ];
      final source = nativeFixture(setup.source.data);
      await expectLater(
        inspect(
          setup,
          NativeWorkspaceRows.fromSnapshot(
            source.bytes,
            directory: setup.source.directory,
          ),
        ),
        failure(),
      );
      expect(setup.files.writes, 0);
    }
  });
}
