import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/migration_journal.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:serverdeck_protocol/codec.dart';

import '../automation/snapshot_test.dart' as g;
import 'grant_transaction_scenarios.dart'
    show grantCreate, credentialFiles, baselineRetained;
import 'operational_snapshot_child.dart' show check, sameJson;
import 'grant_publication_scenarios.dart' show verifyPublicationRecovery;

Future<void> main(List<String> args) async {
  final root = p.normalize(p.absolute(args[0])),
      bundle = args[1],
      committed = args[2] == 'committed';
  check(
    p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) &&
        p.basename(root).startsWith('serverdeck-operational-snapshot-'),
  );
  final sid = currentUserSid(),
      custody = KeyCustody(DpapiProtection(), currentUserSid());
  final hash = (await Sha256().hash(utf8.encode('operational-fixture-$root')))
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.$hash',
    sid,
  );
  ReceiptKeyMaterial? key;
  StateStore? store;
  try {
    check(lease.isHeld);
    final directory = p.join(
      root,
      'ServerDeckNext',
      'v1',
      'workspaces',
      'default',
    );
    final manifest = MigrationManifest.fromJson(
      StrictCodec().decode(
        await readProtectedFile(
          root,
          p.join(directory, 'workspace.manifest.json'),
          sid,
          maxBytes: 4096,
        ),
        maxBytes: 4096,
      ),
    );
    final wrapper = await readProtectedFile(
      root,
      p.join(directory, 'receipt-key.dpapi'),
      sid,
      maxBytes: 16384,
    );
    key = await custody.openReceiptKey(
      wrapper,
      manifest.workspaceId,
      manifest.receiptKeyId,
    );
    Future<StateStore> open() => StateStore.openOperational(
      localAppData: root,
      appRoot: bundle,
      lease: lease,
      custody: custody,
      receiptKey: key!,
    );
    store = await open();
    final files = McpCredentialFiles(
      localAppData: root,
      workspaceId: manifest.workspaceId,
      ownerSid: sid,
      custody: McpCredentialCustody(DpapiProtection()),
    );
    if (args[2].startsWith('pointer-')) {
      store = await verifyPublicationRecovery(
        store,
        open,
        files,
        args[2].substring(8),
      );
      return;
    }
    check(
      store.state.storeRevision == '0' &&
          store.state.profiles.isEmpty &&
          store.state.receipts.isEmpty,
    );
    check(store.operational.automation.grants.length == (committed ? 1 : 0));
    check(store.operational.automation.receipts.length == (committed ? 1 : 0));
    final count = credentialFiles(files);
    final result = await OwnerGrantService(store)
        .submitOwner('grant.create', grantCreate(800, 801));
    sameJson(
      {'grantId': g.id(801), 'revision': 1},
      result,
      'actual-crash-replay',
    );
    check(credentialFiles(files) == count + (committed ? 0 : 2));
    final loaded = await files.readForBridge(g.id(801));
    try {
      check(
        loaded.binding.secretRef ==
            store.operational.automation.grants[g.id(801)]!.secretRef,
      );
    } finally {
      loaded.key.close();
    }
    final before = store.operational;
    check(
      before.rows['grants']!.single.nativeId == 1 &&
          before.rows['receipts']!.single.nativeId == 1,
    );
    await store.close();
    store = await open();
    baselineRetained(before, store.operational);
    sameJson(
      result,
      await OwnerGrantService(store)
          .submitOwner('grant.create', grantCreate(800, 801)),
      'second-crash-replay',
    );
    check(
      base64Encode(wrapper) ==
          base64Encode(
            await readProtectedFile(
              root,
              p.join(directory, 'receipt-key.dpapi'),
              sid,
              maxBytes: 16384,
            ),
          ),
    );
    stdout.writeln('ACTUAL_HARD_CRASH_GRANT_ATOMIC_RECOVERY_REPLAY_PROVED');
  } finally {
    if (store != null) await store.close();
    if (StateStore.hasOpenReservation) exit(1);
    key?.close();
    await lease.close();
  }
}
