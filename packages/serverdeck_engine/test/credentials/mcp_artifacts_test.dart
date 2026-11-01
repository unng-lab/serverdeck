import '../support/memory_platform.dart' show Files, Protection;

import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/credentials/mcp_credential_files.dart';
import 'package:serverdeck_engine/credentials/mcp_credentials.dart';
import 'package:test/test.dart';

const owner = 'S-1-5-21-1-2-3-1001';
const workspace = '12345678-1234-4234-9234-123456789a21';
const grant = '12345678-1234-4234-9234-123456789a22';
const firstSecret = '12345678-1234-4234-9234-123456789a23';
const nextSecret = '12345678-1234-4234-9234-123456789a24';
McpCredentialBinding binding({String secret = firstSecret}) =>
    McpCredentialBinding(
      workspaceId: workspace,
      grantId: grant,
      secretRef: secret,
      ownerSid: owner,
      issuedAt: '2026-10-30T10:00:00.000Z',
    );
Matcher failure([String code = 'STORAGE_BLOCKED']) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));

McpCredentialFiles artifacts(Files files, Protection protection) =>
    McpCredentialFiles(
      localAppData: files.root,
      protectedFiles: files,
      workspaceId: workspace,
      ownerSid: owner,
      custody: McpCredentialCustody(protection),
    );

void main() {
  test('stage is inert, bridge is read-only, publication and revocation retain exact bindings', () async {
    final fs = Files(), protection = Protection();
    addTearDown(protection.dispose);
    final files = artifacts(fs, protection), current = binding();
    final originalWrites = fs.writes;
    await expectLater(files.readForBridge(grant), failure());
    expect(fs.writes, originalWrites);
    await files.stage(current);
    expect(await files.readLookupForRecovery(grant), isNull);
    final key = await files.openReferenced(current);
    key.close();
    await files.publish(current, revoked: false);
    final loaded = await files.readForBridge(grant);
    expect(loaded.binding.secretRef, firstSecret);
    loaded.key.close();
    final afterPublish = fs.writes;
    await files.publish(current, revoked: false);
    expect(fs.writes, afterPublish);
    await files.publish(current, revoked: true);
    await expectLater(files.readForBridge(grant), failure('FORBIDDEN'));
    expect((await files.readLookupForRecovery(grant))!.revoked, isTrue);
    await files.validateInventory();
  });

  test('failed atomic promotion leaves the previous lookup and inert pending file for recovery', () async {
    final fs = Files(), protection = Protection();
    addTearDown(protection.dispose);
    final files = artifacts(fs, protection);
    await files.stage(binding());
    await files.publish(binding(), revoked: false);
    await files.stage(binding(secret: nextSecret));
    fs.failRename = true;
    await expectLater(
      files.publish(binding(secret: nextSecret), revoked: false),
      failure(),
    );
    expect(
      fs.data.keys.where((path) => path.endsWith('.pending')),
      hasLength(1),
    );
    final old = await files.readForBridge(grant);
    expect(old.binding.secretRef, firstSecret);
    old.key.close();
    await files.validateInventory();
    fs.failRename = false;
    await files.publish(binding(secret: nextSecret), revoked: false);
    final next = await files.readForBridge(grant);
    expect(next.binding.secretRef, nextSecret);
    next.key.close();
  });

  test(
    'space refusal and malformed inventory do not create or repair a lookup',
    () async {
      final fs = Files()..noSpace = true, protection = Protection();
      addTearDown(protection.dispose);
      final files = artifacts(fs, protection);
      await expectLater(files.stage(binding()), failure('RESOURCE_LIMIT'));
      expect(fs.writes, 0);
      fs.noSpace = false;
      await files.stage(binding());
      final folder = p.join(files.directory, 'mcp-credentials', grant);
      fs.data[p.join(folder, 'unexpected-file')] = [1];
      await expectLater(files.validateInventory(), failure());
      expect(
        fs.data.keys.any((path) => path.endsWith('current.json')),
        isFalse,
      );
    },
  );

  test('owner/path mismatch, denied parent and bounded directory inventory fail closed', () async {
    final fs = Files(), protection = Protection();
    addTearDown(protection.dispose);
    expect(
      () => McpCredentialFiles(
        localAppData: fs.root,
        protectedFiles: fs,
        workspaceId: workspace,
        ownerSid: 'S-1-5-21-9-9-9-1001',
        custody: McpCredentialCustody(protection),
      ),
      failure(),
    );
    final files = artifacts(fs, protection);
    fs.denied.add(files.directory);
    await expectLater(files.stage(binding()), failure());
    expect(fs.writes, 0);
    fs.denied.clear();
    final root = p.join(files.directory, 'mcp-credentials');
    fs.dirs.add(root);
    for (var i = 0; i < 4097; i++) {
      fs.dirs.add(
        p.join(
          root,
          '12345678-1234-4234-9234-${i.toRadixString(16).padLeft(12, '0')}',
        ),
      );
    }
    await expectLater(files.stage(binding()), failure('RESOURCE_LIMIT'));
    expect(fs.writes, 0);
  });
}
