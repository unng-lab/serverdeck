import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/build_bundle.dart';
import 'package:serverdeck_windows/mcp_build_bundle.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

Matcher code(String value) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', value));

void ownRoot(String path) {
  final root = p.normalize(p.absolute(path));
  if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) ||
      !p.basename(root).startsWith('serverdeck-mcp-bundle-')) {
    throw StateError('UNSAFE_FIXTURE');
  }
}

Future<String> boundedOutput(Stream<List<int>> source) async {
  final bytes = <int>[];
  await for (final chunk in source) {
    if (bytes.length + chunk.length > 65536) return 'OUTPUT_LIMIT';
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

Future<void> compilePeer(
  String executable, {
  String source = 'test/support/bundle_peer_child.dart',
}) async {
  final child = await Process.start(Platform.resolvedExecutable, [
    'compile',
    'exe',
    source,
    '-o',
    executable,
  ]);
  final output = boundedOutput(child.stdout),
      errors = boundedOutput(child.stderr);
  try {
    expect(
      await child.exitCode.timeout(const Duration(seconds: 90)),
      0,
      reason: '${await output}\n${await errors}',
    );
  } finally {
    child.kill();
    await child.exitCode.timeout(const Duration(seconds: 10));
  }
}

class Fixture {
  Fixture(String compiled) {
    root = Directory.systemTemp.createTempSync('serverdeck-mcp-bundle-case-');
    path = p.normalize(p.absolute(root.path));
    ownRoot(path);
    for (final file in ['serverdeck.exe', 'locald.exe', 'mcp.exe']) {
      File(compiled).copySync(p.join(path, file));
    }
    // Verifier hashes a DLL but never loads it: this fixture qualifies process
    // identity only, not an ABI/native-runtime or a product MCP build.
    File(p.join(path, 'libisar.dll')).writeAsBytesSync([7, 8, 9]);
    document = {
      'format': 2,
      'product': 'serverdeck-next',
      'buildId': '${'a' * 40}+Debug+${'b' * 64}',
      'configuration': 'Debug',
      'testOnly': false,
      'appRoot': path,
      'apiMajor': 1,
      'apiMinor': 1,
      'workspaceSchema': 2,
      'sha256': {
        for (final name in [
          'serverdeck.exe',
          'locald.exe',
          'mcp.exe',
          'libisar.dll',
        ])
          name: fileSha256(p.join(path, name)),
      },
    };
    write();
  }
  late final Directory root;
  late final String path;
  late final Map<String, Object?> document;
  final children = <Process>[];
  final errors = <Future<String>>[];
  final identities = <RetainedProcessIdentity>[];
  String get manifestPath => p.join(path, 'foundation.manifest.json');
  void write([String? contents]) =>
      File(manifestPath).writeAsStringSync(contents ?? jsonEncode(document));
  Future<RetainedProcessIdentity> start(String executable) async {
    final child = await Process.start(executable, []);
    children.add(child);
    errors.add(boundedOutput(child.stderr));
    final ready = await child.stdout.first.timeout(const Duration(seconds: 10));
    expect(ready.length, lessThanOrEqualTo(64));
    expect(utf8.decode(ready).trim(), 'READY');
    final identity = RetainedProcessIdentity.open(child.pid);
    identities.add(identity);
    return identity;
  }

  Future<void> close() async {
    for (final identity in identities) identity.close();
    for (final child in children) {
      child.kill();
      await child.exitCode.timeout(const Duration(seconds: 10));
    }
    for (final error in errors)
      expect(await error.timeout(const Duration(seconds: 5)), isEmpty);
    ownRoot(path);
    root.deleteSync(recursive: true);
  }
}

void main() {
  late Directory compiledRoot;
  late String compiled;
  late Fixture fixture;
  setUpAll(() async {
    compiledRoot = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-compiled-',
    );
    ownRoot(compiledRoot.path);
    compiled = p.join(compiledRoot.path, 'peer.exe');
    await compilePeer(compiled);
  });
  tearDownAll(() {
    ownRoot(compiledRoot.path);
    compiledRoot.deleteSync(recursive: true);
  });
  setUp(() {
    fixture = Fixture(compiled);
  });
  tearDown(() async {
    await fixture.close();
  });

  test(
    'actual retained PE role comes only from verified fixed image path',
    () async {
      final bundle = await verifyMcpBuildBundle(fixture.path);
      final names = {
        'serverdeck.exe': BundlePeerRole.owner,
        'mcp.exe': BundlePeerRole.mcp,
        'locald.exe': BundlePeerRole.locald,
      };
      for (final entry in names.entries) {
        final identity = await fixture.start(p.join(fixture.path, entry.key));
        final proof = bundle.verifyPeer(identity, currentUserSid());
        expect(proof.role, entry.value);
        proof.revalidate();
        expect(
          () => bundle.verifyPeer(identity, 'S-1-0-0'),
          code('UNAUTHORIZED'),
        );
        identity.close();
        expect(() => proof.role, code('UNAUTHORIZED'));
        expect(
          () => bundle.verifyPeer(identity, currentUserSid()),
          code('UNAUTHORIZED'),
        );
      }
      expect(
        Directory(p.join(fixture.path, 'ServerDeckNext')).existsSync(),
        isFalse,
      );
      expect(() => bundle.manifest.sha256.clear(), throwsUnsupportedError);
    },
    testOn: 'windows',
  );

  test(
    'same bytes outside bundle or under an unrecognized name have no role',
    () async {
      final bundle = await verifyMcpBuildBundle(fixture.path);
      final outside = File(compiled)
          .copySync(p.join(compiledRoot.path, 'serverdeck.exe'));
      final stranger = File(compiled)
          .copySync(p.join(fixture.path, 'stranger.exe'));
      for (final path in [outside.path, stranger.path]) {
        final identity = await fixture.start(path);
        expect(
          () => bundle.verifyPeer(identity, currentUserSid()),
          code('UNAUTHORIZED'),
        );
      }
    },
    testOn: 'windows',
  );

  test(
    'retained proof refuses process exit and changed manifest bytes',
    () async {
      final bundle = await verifyMcpBuildBundle(fixture.path);
      final identity = await fixture.start(p.join(fixture.path, 'mcp.exe'));
      final proof = bundle.verifyPeer(identity, currentUserSid());
      fixture.write('${jsonEncode(fixture.document)} ');
      expect(proof.revalidate, code('UNAUTHORIZED'));
      expect(() => proof.role, code('UNAUTHORIZED'));
      fixture.write(' ' * 16385);
      expect(proof.revalidate, code('UNAUTHORIZED'));
      fixture.write();
      fixture.children.single.kill();
      await fixture.children.single.exitCode.timeout(
        const Duration(seconds: 10),
      );
      expect(proof.revalidate, code('UNAUTHORIZED'));
    },
    testOn: 'windows',
  );

  test('actual changed but runnable PE image fails the retained expected hash', () async {
    final bundle = await verifyMcpBuildBundle(fixture.path);
    final path = p.join(fixture.path, 'serverdeck.exe');
    final bytes = File(path).readAsBytesSync();
    expect(bytes.take(2), [0x4d, 0x5a]);
    // DOS stub is not executed by the Windows PE loader; the appended AOT image
    // remains intact. Prove actual process liveness before hash refusal.
    bytes[0x40] ^= 1;
    File(path).writeAsBytesSync(bytes);
    final identity = await fixture.start(path);
    identity.revalidate();
    expect(
      () => bundle.verifyPeer(identity, currentUserSid()),
      code('UNAUTHORIZED'),
    );
    await expectLater(verifyMcpBuildBundle(fixture.path), code('INCOMPATIBLE'));
  }, testOn: 'windows');

  test('closed formats testOnly and bounded malformed manifests fail without fallback', () async {
    await expectLater(verifyBuildBundle(fixture.path), code('INCOMPATIBLE'));
    fixture.document['testOnly'] = true;
    fixture.write();
    await expectLater(verifyMcpBuildBundle(fixture.path), code('INCOMPATIBLE'));
    expect(
      (await verifyMcpBuildBundle(
        fixture.path,
        testOnly: true,
      )).manifest.testOnly,
      isTrue,
    );
    fixture.document['testOnly'] = false;
    fixture.write();
    await expectLater(
      verifyMcpBuildBundle(fixture.path, testOnly: true),
      code('INCOMPATIBLE'),
    );
    final valid = jsonEncode(fixture.document);
    for (final input in [
      valid.replaceFirst('"format":2', '"format":2,"format":2'),
      valid.replaceFirst('"apiMinor":1', '"apiMinor":0'),
      valid.replaceFirst('"format":2', '"format":3'),
      ' ' * 16385,
      '{',
    ]) {
      fixture.write(input);
      await expectLater(
        verifyMcpBuildBundle(fixture.path),
        code('INCOMPATIBLE'),
      );
    }
    fixture.document
      ..['format'] = 1
      ..remove('product')
      ..remove('apiMajor')
      ..remove('apiMinor')
      ..remove('workspaceSchema');
    (fixture.document['sha256'] as Map).remove('mcp.exe');
    fixture.write();
    expect((await verifyBuildBundle(fixture.path)).sha256.length, 3);
    await expectLater(verifyMcpBuildBundle(fixture.path), code('INCOMPATIBLE'));
    await expectLater(
      verifyMcpBuildBundle('relative'),
      code('PREREQUISITE_UNAVAILABLE'),
    );
  }, testOn: 'windows');

  test(
    'missing tampered wrong-root and reparse bundle inputs fail closed',
    () async {
      final dll = File(p.join(fixture.path, 'libisar.dll'));
      dll.writeAsBytesSync([10]);
      await expectLater(
        verifyMcpBuildBundle(fixture.path),
        code('INCOMPATIBLE'),
      );
      dll.writeAsBytesSync([7, 8, 9]);
      fixture.document['appRoot'] = p.join(fixture.path, 'other');
      fixture.write();
      await expectLater(
        verifyMcpBuildBundle(fixture.path),
        code('INCOMPATIBLE'),
      );
      fixture.document['appRoot'] = fixture.path;
      fixture.write();
      final link = Link(p.join(fixture.path, 'alias'));
      link.createSync(fixture.path);
      try {
        await expectLater(
          verifyMcpBuildBundle(link.path),
          code('PREREQUISITE_UNAVAILABLE'),
        );
      } finally {
        link.deleteSync();
      }
      final bridge = p.join(fixture.path, 'mcp.exe');
      File(bridge).deleteSync();
      final fileLink = Link(bridge)..createSync(compiled);
      try {
        await expectLater(
          verifyMcpBuildBundle(fixture.path),
          code('PREREQUISITE_UNAVAILABLE'),
        );
      } finally {
        fileLink.deleteSync();
      }
      await expectLater(
        verifyMcpBuildBundle(fixture.path),
        code('PREREQUISITE_UNAVAILABLE'),
      );
    },
    testOn: 'windows',
  );
}
