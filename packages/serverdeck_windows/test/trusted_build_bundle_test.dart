import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/mcp_build_bundle.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import 'mcp_build_bundle_test.dart' as base;

void main() {
  late Directory root;
  late String compiled;
  late base.Fixture fixture;
  setUpAll(() async {
    root = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-trusted-compiled-',
    );
    base.ownRoot(root.path);
    compiled = p.join(root.path, 'peer.exe');
    await base.compilePeer(compiled);
  });
  tearDownAll(() {
    base.ownRoot(root.path);
    root.deleteSync(recursive: true);
  });
  setUp(() {
    fixture = base.Fixture(compiled);
    fixture.document['format'] = 3;
    fixture.document['workspaceSchema'] = 3;
    fixture.write();
  });
  tearDown(() async {
    await fixture.close();
  });

  test(
    'format3 fixed-path actual PE roles use separate unforgeable proof type',
    () async {
      final bundle = await verifyTrustedBuildBundle(fixture.path);
      expect(bundle.manifest.workspaceSchema, 3);
      expect(bundle, isNot(isA<McpBuildBundle>()));
      for (final entry in {
        'serverdeck.exe': BundlePeerRole.owner,
        'mcp.exe': BundlePeerRole.mcp,
        'locald.exe': BundlePeerRole.locald,
      }.entries) {
        final identity = await fixture.start(p.join(fixture.path, entry.key));
        final proof = bundle.verifyPeer(identity, currentUserSid());
        expect(proof.role, entry.value);
        expect(proof, isNot(isA<VerifiedBundlePeer>()));
        expect(
          () => bundle.verifyPeer(identity, 'S-1-0-0'),
          base.code('UNAUTHORIZED'),
        );
        identity.close();
        expect(proof.revalidate, base.code('UNAUTHORIZED'));
      }
      await expectLater(
        verifyMcpBuildBundle(fixture.path),
        base.code('INCOMPATIBLE'),
      );
      expect(
        Directory(p.join(fixture.path, 'ServerDeckNext')).existsSync(),
        isFalse,
      );
    },
    testOn: 'windows',
  );

  test('format2 and format3 bytes/proofs never authorize each other', () async {
    final identity = await fixture.start(p.join(fixture.path, 'mcp.exe'));
    final trusted = await verifyTrustedBuildBundle(fixture.path);
    final trustedProof = trusted.verifyPeer(identity, currentUserSid());
    fixture.document['format'] = 2;
    fixture.document['workspaceSchema'] = 2;
    fixture.write();
    expect(trustedProof.revalidate, base.code('UNAUTHORIZED'));
    await expectLater(
      verifyTrustedBuildBundle(fixture.path),
      base.code('INCOMPATIBLE'),
    );
    final old = await verifyMcpBuildBundle(fixture.path);
    final oldProof = old.verifyPeer(identity, currentUserSid());
    fixture.document['format'] = 3;
    fixture.document['workspaceSchema'] = 3;
    fixture.write();
    expect(oldProof.revalidate, base.code('UNAUTHORIZED'));
    final fresh = (await verifyTrustedBuildBundle(fixture.path))
        .verifyPeer(identity, currentUserSid());
    expect(fresh.role, BundlePeerRole.mcp);
  }, testOn: 'windows');

  test(
    'same bytes outside root and changed artifacts/oversized manifests refuse',
    () async {
      final bundle = await verifyTrustedBuildBundle(fixture.path);
      final outside = File(compiled)
          .copySync(p.join(root.path, 'serverdeck.exe'));
      final identity = await fixture.start(outside.path);
      expect(
        () => bundle.verifyPeer(identity, currentUserSid()),
        base.code('UNAUTHORIZED'),
      );
      fixture.write(' ' * 16385);
      await expectLater(
        verifyTrustedBuildBundle(fixture.path),
        base.code('INCOMPATIBLE'),
      );
      fixture.write();
      File(p.join(fixture.path, 'libisar.dll')).writeAsBytesSync([1, 2, 3]);
      await expectLater(
        verifyTrustedBuildBundle(fixture.path),
        base.code('INCOMPATIBLE'),
      );
    },
    testOn: 'windows',
  );
}
