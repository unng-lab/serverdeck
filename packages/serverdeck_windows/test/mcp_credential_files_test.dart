import 'dart:io';
import 'dart:convert';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

const workspace = '12345678-1234-4234-9234-123456789abc';
const grant = '12345678-1234-4234-9234-123456789abd';
const secret = '12345678-1234-4234-9234-123456789abe';
const replacement = '12345678-1234-4234-9234-123456789abf';

class Fixture {
  Fixture() {
    temp = Directory.systemTemp.createTempSync('serverdeck-mcp-files-');
    root = p.normalize(p.absolute(temp.path));
    var folder = root;
    for (final component in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
      folder = p.join(folder, component);
      createProtectedDirectory(root, folder, sid);
    }
    directory = folder;
    files = McpCredentialFiles(
      localAppData: root,
      workspaceId: workspace,
      ownerSid: sid,
      custody: McpCredentialCustody(DpapiProtection()),
    );
  }
  late final Directory temp;
  late final String root, directory;
  final sid = currentUserSid();
  late final McpCredentialFiles files;
  String get credentials => p.join(directory, 'mcp-credentials');
  String get lookup => p.join(credentials, grant, 'current.json');
  McpCredentialBinding binding([String ref = secret]) => McpCredentialBinding(
    workspaceId: workspace,
    grantId: grant,
    secretRef: ref,
    ownerSid: sid,
    issuedAt: '2026-10-21T10:00:00.000Z',
  );
  void close() {
    if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) ||
        !p.basename(root).startsWith('serverdeck-mcp-files-'))
      throw StateError('UNSAFE_FIXTURE');
    temp.deleteSync(recursive: true);
  }
}

Matcher error(String code) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));

// Native CREATE_NEW with explicit ACL, then an owned synthetic zero-filled file.
// No production quota overrides or injected file metadata.
void quotaFile(Fixture f, int n, int size) {
  final id = '20000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
  final path = p.join(f.credentials, grant, '$id.dpapi');
  final attributes = SecurityAttributes(ownerOnlySddl(f.sid));
  final native = path.toNativeUtf16();
  try {
    final result = CreateFile(
      PCWSTR(native),
      0x40000000,
      FILE_SHARE_MODE(0),
      attributes.pointer,
      CREATE_NEW,
      FILE_FLAGS_AND_ATTRIBUTES(0),
      null,
    );
    if (!result.value.isValid) throw StateError('QUOTA_FIXTURE_FAILED');
    if (!CloseHandle(result.value).value)
      throw StateError('QUOTA_FIXTURE_CLOSE');
  } finally {
    calloc.free(native);
    attributes.close();
  }
  if (size != 0) {
    final writer = File(path).openSync(mode: FileMode.writeOnly);
    try {
      writer.truncateSync(size);
      writer.flushSync();
    } finally {
      writer.closeSync();
    }
  }
}

void main() {
  group(
    'compiled credential-space child',
    () {
      late Directory compiled;
      late String ordinary, probe;
      void ownCompiled() {
        final root = p.normalize(p.absolute(compiled.path));
        if (!p.isWithin(
              p.normalize(p.absolute(Directory.systemTemp.path)),
              root,
            ) ||
            !p.basename(root).startsWith('serverdeck-mcp-space-aot-')) {
          throw StateError('UNSAFE_FIXTURE');
        }
      }

      setUpAll(() async {
        compiled = Directory.systemTemp.createTempSync(
          'serverdeck-mcp-space-aot-',
        );
        ownCompiled();
        ordinary = p.join(compiled.path, 'ordinary.exe');
        probe = p.join(compiled.path, 'probe.exe');
        // Compile separately from the runtime deadline. Cold JIT compilation must
        // not consume the 30s budget for the actual native file/DPAPI operation.
        for (final enabled in [false, true]) {
          final compiler = await Process.start(Platform.resolvedExecutable, [
            'compile',
            'exe',
            if (enabled) '-DSERVERDECK_TEST_MCP_FILE_PROBES=true',
            'test/support/mcp_credential_space_child.dart',
            '-o',
            enabled ? probe : ordinary,
          ]);
          final output = compiler.stdout.transform(utf8.decoder).join();
          final errors = compiler.stderr.transform(utf8.decoder).join();
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
        }
      });
      tearDownAll(() {
        ownCompiled();
        compiled.deleteSync(recursive: true);
      });

      test(
        'actual caller-space query refuses stage/publication; normal builds cannot install probes',
        () async {
          for (final mode in [
            'disabled',
            'initial',
            'stage',
            'publish',
            'revoke',
          ]) {
            final child = await Process.start(
              mode == 'disabled' ? ordinary : probe,
              [mode],
            );
            final output = child.stdout.transform(utf8.decoder).join();
            final errors = child.stderr.transform(utf8.decoder).join();
            try {
              final code = await child.exitCode.timeout(
                const Duration(seconds: 30),
              );
              final stdout = await output.timeout(const Duration(seconds: 5));
              final stderr = await errors.timeout(const Duration(seconds: 5));
              expect(code, 0, reason: '$mode: $stdout$stderr');
              expect(
                stdout,
                contains(
                  mode == 'disabled' ? 'PROBES_DISABLED' : 'SPACE_REFUSED',
                ),
              );
            } finally {
              child.kill();
              await child.exitCode.timeout(const Duration(seconds: 10));
            }
          }
        },
        testOn: 'windows',
        timeout: const Timeout(Duration(minutes: 3)),
      );
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'real file symbolic reparses at blob and lookup never follow the target',
    () async {
      for (final object in ['blob', 'lookup']) {
        final f = Fixture();
        Link? link;
        try {
          await f.files.stage(f.binding());
          await f.files.publish(f.binding(), revoked: false);
          final source = object == 'blob'
              ? p.join(f.credentials, grant, '$secret.dpapi')
              : f.lookup;
          final moved = p.join(f.root, 'moved-$object');
          if (!p.isWithin(f.root, p.absolute(source)) ||
              !p.isWithin(f.root, p.absolute(moved))) {
            throw StateError('UNSAFE_FIXTURE_MOVE');
          }
          final before = File(source).readAsBytesSync();
          File(source).renameSync(moved);
          link = Link(source)..createSync(moved);
          expect(
            FileSystemEntity.typeSync(source, followLinks: false),
            FileSystemEntityType.link,
          );
          await expectLater(
            f.files.readForBridge(grant),
            error('STORAGE_BLOCKED'),
          );
          await expectLater(
            f.files.stage(f.binding(replacement)),
            error('STORAGE_BLOCKED'),
          );
          await expectLater(
            f.files.publish(f.binding(), revoked: false),
            error('STORAGE_BLOCKED'),
          );
          expect(File(moved).readAsBytesSync(), before);
        } finally {
          if (link != null &&
              FileSystemEntity.typeSync(link.path, followLinks: false) ==
                  FileSystemEntityType.link) {
            link.deleteSync();
          }
          f.close();
        }
      }
    },
    testOn: 'windows',
  );
  test('current blob corruption blocks reads and publication; missing workspace is never initialized', () async {
    final f = Fixture();
    try {
      await f.files.stage(f.binding());
      await f.files.publish(f.binding(), revoked: false);
      final original = File(f.lookup).readAsBytesSync();
      await replaceProtectedFile(
        f.root,
        p.join(f.credentials, grant, '$secret.dpapi'),
        f.sid,
        [1, 2, 3],
      );
      await expectLater(f.files.readForBridge(grant), error('STORAGE_BLOCKED'));
      await expectLater(
        f.files.publish(f.binding(), revoked: false),
        error('STORAGE_BLOCKED'),
      );
      expect(File(f.lookup).readAsBytesSync(), original);
      final moved = p.join(f.root, 'missing-workspace');
      if (!p.isWithin(f.root, f.directory) || !p.isWithin(f.root, moved))
        throw StateError('UNSAFE_FIXTURE_MOVE');
      Directory(f.directory).renameSync(moved);
      await expectLater(
        f.files.stage(f.binding(replacement)),
        error('STORAGE_BLOCKED'),
      );
      await expectLater(f.files.readForBridge(grant), error('STORAGE_BLOCKED'));
      expect(Directory(f.directory).existsSync(), isFalse);
    } finally {
      f.close();
    }
  }, testOn: 'windows');
  test(
    'real file-count and byte budgets reserve stage plus publication headroom',
    () async {
      for (final mode in ['files', 'bytes']) {
        final f = Fixture();
        try {
          await f.files.stage(f.binding());
          await f.files.publish(f.binding(), revoked: false);
          final original = File(f.lookup).readAsBytesSync();
          if (mode == 'files') {
            for (var n = 0; n < 4094; n++) {
              quotaFile(f, n, 0);
            }
          } else {
            for (var n = 0; n < 2047; n++) {
              quotaFile(f, n, 16384);
            }
            final used =
                original.length +
                File(p.join(f.credentials, grant, '$secret.dpapi'))
                    .lengthSync();
            quotaFile(f, 2047, 16384 - used);
          }
          await expectLater(
            f.files.stage(f.binding(replacement)),
            error('RESOURCE_LIMIT'),
          );
          expect(
            File(p.join(f.credentials, grant, '$replacement.dpapi'))
                .existsSync(),
            isFalse,
          );
          expect(File(f.lookup).readAsBytesSync(), original);
          await f.files.publish(f.binding(), revoked: false);
        } finally {
          f.close();
        }
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'directory quota refuses a new identity before creating any child',
    () async {
      final f = Fixture();
      try {
        await f.files.stage(f.binding());
        await f.files.publish(f.binding(), revoked: false);
        for (var n = 0; n < 4095; n++) {
          final id =
              '10000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
          createProtectedDirectory(f.root, p.join(f.credentials, id), f.sid);
        }
        final candidate = McpCredentialBinding(
          workspaceId: workspace,
          grantId: replacement,
          secretRef: replacement,
          ownerSid: f.sid,
          issuedAt: '2026-10-21T10:00:00.000Z',
        );
        final original = File(f.lookup).readAsBytesSync();
        await expectLater(f.files.stage(candidate), error('RESOURCE_LIMIT'));
        expect(
          Directory(p.join(f.credentials, replacement)).existsSync(),
          isFalse,
        );
        expect(File(f.lookup).readAsBytesSync(), original);
        await f.files.publish(
          f.binding(),
          revoked: false,
        ); // No-write replay at quota.
      } finally {
        f.close();
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'unsafe owner ACL at every protected ancestor and credential object fails closed',
    () async {
      for (final level in [
        'product',
        'version',
        'workspaces',
        'workspace',
        'root',
        'grant',
        'blob',
        'lookup',
      ]) {
        final f = Fixture();
        try {
          await f.files.stage(f.binding());
          await f.files.publish(f.binding(), revoked: false);
          final target = switch (level) {
            'product' => p.join(f.root, 'ServerDeckNext'),
            'version' => p.join(f.root, 'ServerDeckNext', 'v1'),
            'workspaces' => p.dirname(f.directory),
            'workspace' => f.directory,
            'root' => f.credentials,
            'grant' => p.join(f.credentials, grant),
            'blob' => p.join(f.credentials, grant, '$secret.dpapi'),
            _ => f.lookup,
          };
          final original = File(f.lookup).readAsBytesSync();
          final acl = await Process.run('icacls.exe', [
            target,
            '/grant',
            '*S-1-1-0:(F)',
          ]);
          expect(acl.exitCode, 0);
          await expectLater(
            f.files.readForBridge(grant),
            error('STORAGE_BLOCKED'),
          );
          await expectLater(
            f.files.publish(f.binding(), revoked: false),
            error('STORAGE_BLOCKED'),
          );
          expect(File(f.lookup).readAsBytesSync(), original);
        } finally {
          f.close();
        }
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'real directory reparses at each protected level are refused without touching their targets',
    () async {
      for (final level in [
        'product',
        'version',
        'workspaces',
        'workspace',
        'root',
        'grant',
      ]) {
        final f = Fixture();
        Link? junction;
        try {
          await f.files.stage(f.binding());
          await f.files.publish(f.binding(), revoked: false);
          final target = switch (level) {
            'product' => p.join(f.root, 'ServerDeckNext'),
            'version' => p.join(f.root, 'ServerDeckNext', 'v1'),
            'workspaces' => p.dirname(f.directory),
            'workspace' => f.directory,
            'root' => f.credentials,
            _ => p.join(f.credentials, grant),
          };
          final moved = p.join(f.root, 'moved');
          if (!p.isWithin(f.root, p.absolute(target)) ||
              !p.isWithin(f.root, p.absolute(moved))) {
            throw StateError('UNSAFE_FIXTURE_MOVE');
          }
          final original = File(f.lookup).readAsBytesSync();
          Directory(target).renameSync(moved);
          junction = Link(target);
          final setup = await Process.run(
            'powershell.exe',
            [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              'New-Item -ItemType Junction -Path \$env:SERVERDECK_TEST_JUNCTION -Target \$env:SERVERDECK_TEST_TARGET -ErrorAction Stop | Out-Null',
            ],
            environment: {
              'SERVERDECK_TEST_JUNCTION': target,
              'SERVERDECK_TEST_TARGET': moved,
            },
          );
          expect(setup.exitCode, 0);
          await expectLater(
            f.files.readForBridge(grant),
            error('STORAGE_BLOCKED'),
          );
          await expectLater(
            f.files.stage(f.binding(replacement)),
            error('STORAGE_BLOCKED'),
          );
          expect(File(f.lookup).readAsBytesSync(), original);
        } finally {
          if (junction != null &&
              FileSystemEntity.typeSync(junction.path, followLinks: false) ==
                  FileSystemEntityType.link) {
            junction.deleteSync();
          }
          f.close();
        }
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'lookup bounds, identity and schema errors are safely classified',
    () async {
      final f = Fixture();
      try {
        await f.files.stage(f.binding());
        await f.files.publish(f.binding(), revoked: false);
        final valid = jsonDecode(File(f.lookup).readAsStringSync()) as Map;
        for (final bytes in [
          List<int>.filled(4097, 32),
          utf8.encode('{"format":1,"format":1}'),
          utf8.encode(jsonEncode({...valid, 'grantId': replacement})),
          utf8.encode(jsonEncode({...valid, 'workspaceId': replacement})),
          utf8.encode(jsonEncode({...valid, 'revoked': 'false'})),
          utf8.encode(jsonEncode({...valid, 'extra': true})),
        ]) {
          await replaceProtectedFile(f.root, f.lookup, f.sid, bytes);
          await expectLater(
            f.files.readForBridge(grant),
            error('STORAGE_BLOCKED'),
          );
          expect(File(f.lookup).readAsBytesSync(), bytes);
        }
        await replaceProtectedFile(
          f.root,
          f.lookup,
          f.sid,
          utf8.encode(jsonEncode({...valid, 'format': 2})),
        );
        await expectLater(f.files.readForBridge(grant), error('INCOMPATIBLE'));
      } finally {
        f.close();
      }
    },
    testOn: 'windows',
  );
  test('real staged files stay inert; immutable replacement and atomic retained readers', () async {
    final f = Fixture();
    try {
      await expectLater(f.files.readForBridge(grant), error('STORAGE_BLOCKED'));
      expect(Directory(f.credentials).existsSync(), isFalse);
      await f.files.stage(f.binding());
      expect(File(f.lookup).existsSync(), isFalse);
      final blob = File(p.join(f.credentials, grant, '$secret.dpapi'));
      final original = blob.readAsBytesSync();
      await expectLater(f.files.stage(f.binding()), error('STORAGE_BLOCKED'));
      expect(blob.readAsBytesSync(), original);
      await f.files.publish(f.binding(), revoked: false);
      final first = await f.files.readForBridge(grant);
      final retained = ProtectedSnapshotReader.open(
        f.root,
        f.lookup,
        f.sid,
        maxBytes: 4096,
      );
      final oldLookup = File(f.lookup).readAsBytesSync();
      try {
        await f.files.stage(f.binding(replacement));
        await f.files.publish(f.binding(replacement), revoked: false);
        expect(retained.read(), oldLookup);
        final second = await f.files.readForBridge(grant);
        try {
          expect(second.binding.secretRef, replacement);
          expect(
            await second.key.verify([1, 2, 3], await first.key.mac([1, 2, 3])),
            isFalse,
          );
        } finally {
          second.key.close();
        }
      } finally {
        retained.close();
        first.key.close();
      }
      await f.files.publish(f.binding(replacement), revoked: true);
      await expectLater(f.files.readForBridge(grant), error('FORBIDDEN'));
      final revokedKey = await f.files.openReferenced(f.binding(replacement));
      revokedKey.close();
      expect(blob.readAsBytesSync(), original);
    } finally {
      f.close();
    }
  }, testOn: 'windows');

  test(
    'corrupt lookup cannot be repaired and missing/current blobs fail closed',
    () async {
      final f = Fixture();
      try {
        await f.files.stage(f.binding());
        await f.files.publish(f.binding(), revoked: false);
        await replaceProtectedFile(f.root, f.lookup, f.sid, [123, 125]);
        final bad = File(f.lookup).readAsBytesSync();
        await expectLater(
          f.files.publish(f.binding(), revoked: false),
          error('STORAGE_BLOCKED'),
        );
        await expectLater(
          f.files.readForBridge(grant),
          error('STORAGE_BLOCKED'),
        );
        expect(File(f.lookup).readAsBytesSync(), bad);
        await expectLater(
          f.files.openReferenced(f.binding(replacement)),
          error('STORAGE_BLOCKED'),
        );
      } finally {
        f.close();
      }
    },
    testOn: 'windows',
  );

  test('well-named partial orphan and pending files remain inert, unknown names block writes', () async {
    final f = Fixture();
    try {
      await f.files.stage(f.binding());
      final folder = p.join(f.credentials, grant);
      final orphan = p.join(folder, '$replacement.dpapi');
      final pending = p.join(folder, 'current.json.${'a' * 32}.pending');
      await createProtectedEmptyFile(f.root, orphan, f.sid);
      await writeNewProtectedFile(f.root, pending, f.sid, [1]);
      await f.files.publish(f.binding(), revoked: false);
      expect(File(orphan).lengthSync(), 0);
      expect(File(pending).readAsBytesSync(), [1]);
      final bad = p.join(folder, 'unexpected');
      await writeNewProtectedFile(f.root, bad, f.sid, [1]);
      final current = File(f.lookup).readAsBytesSync();
      await expectLater(
        f.files.stage(f.binding(replacement)),
        error('STORAGE_BLOCKED'),
      );
      expect(File(f.lookup).readAsBytesSync(), current);
    } finally {
      f.close();
    }
  }, testOn: 'windows');
}
