import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

// Separate acceptance executable. No production entry point or runtime flag.
Future<void> main(List<String> arguments) async {
  try {
    await runCheckpoint(arguments);
  } on Object {
    // Also covers failures during resource close; never print raw exceptions.
    stderr.writeln('ENVIRONMENT_CHECKPOINT_FAILED');
    exitCode = 1;
  }
}

Future<void> runCheckpoint(List<String> arguments) async {
  MutexLease? lease;
  Workspace? workspace;
  try {
    if (arguments.length != 3 || !{'seed', 'verify'}.contains(arguments[2])) {
      throw StateError('INVALID_ARGUMENTS');
    }
    final root = p.normalize(p.absolute(arguments[0]));
    if (!RegExp(r'[\\/]\.local[\\/]environment-acceptance-[a-f0-9]{32}$')
        .hasMatch(root)) {
      throw StateError('OWNED_FIXTURE_REQUIRED');
    }
    final sid = currentUserSid();
    requireSafePath(root, root);
    final local = p.join(root, 'profile');
    final checkpoint = p.join(local, 'durable-checkpoint.json');
    final seed = arguments[2] == 'seed';
    if (seed) {
      if (Directory(local).existsSync() || File(checkpoint).existsSync()) {
        throw StateError('FIXTURE_ALREADY_USED');
      }
      createProtectedDirectory(root, local, sid);
    } else {
      // A missing fixture must never become a new empty workspace.
      requireOwnerOnlyFileAcl(checkpoint, sid);
      requireOwnerOnlyFileAcl(local, sid);
      for (final name in [
        'workspace.manifest.json',
        'receipt-key.dpapi',
        'workspace.isar',
        'workspace.isar-lck',
      ]) {
        requireOwnerOnlyFileAcl(
          p.join(local, 'ServerDeckNext', 'v1', 'workspaces', 'default', name),
          sid,
        );
      }
    }
    final digest = await Sha256().hash(utf8.encode(root));
    final suffix = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    lease = await MutexLease.acquire('Global\\ServerDeckNext.v1.$suffix', sid);
    if (!lease.isHeld) throw StateError('LEASE_REQUIRED');
    final custody = KeyCustody(DpapiProtection(), sid);
    workspace = await Workspace.open(
      localAppData: local,
      appRoot: arguments[1],
      lease: lease,
      custody: custody,
    );
    if (seed) {
      final coordinator = MutationCoordinator(
        workspace.store,
        custody,
        workspace.receiptKey,
      );
      try {
        await coordinator.submit(
          'a2435678-1234-4234-8234-123456789012',
          ApiMethod.profilesCreate,
          {
            'profileId': 'b2435678-1234-4234-8234-123456789012',
            'name': 'Environment checkpoint',
            'address': 'example.invalid',
            'sshUser': 'synthetic',
            'credential': {
              'action': 'replace',
              'kind': 'password',
              'password': 'synthetic-environment-password-243',
            },
          },
          requester: 'owned-environment-fixture',
        );
      } finally {
        await coordinator.close();
      }
    }
    final state = workspace.store.state;
    if (state.profiles.length != 1 ||
        state.credentials.length != 1 ||
        state.receipts.length != 1) {
      throw StateError('DURABLE_STATE_MISMATCH');
    }
    final stateHash = await Sha256().hash(StrictCodec().encode(state.toJson()));
    final expected = {
      'format': 1,
      'ownerSid': sid,
      'workspaceId': state.workspaceId,
      'receiptKeyId': workspace.receiptKey.receiptKeyId,
      'stateSha256': base64.encode(stateHash.bytes),
    };
    if (seed) {
      await writeNewProtectedFile(
        root,
        checkpoint,
        sid,
        utf8.encode(jsonEncode(expected)),
      );
    } else {
      final bytes = await readProtectedFile(
        root,
        checkpoint,
        sid,
        maxBytes: 4096,
      );
      final previous = jsonDecode(utf8.decode(bytes));
      if (jsonEncode(previous) != jsonEncode(expected)) {
        throw StateError('DURABLE_STATE_MISMATCH');
      }
    }
    final credential = state.credentials.values.single;
    final secret = await custody.openCredential(
      credential.protectedBlob,
      state.workspaceId,
      credential.profileId,
      credential.id,
    );
    try {
      if (secret['password'] != 'synthetic-environment-password-243') {
        throw StateError('CREDENTIAL_RECOVERY_FAILED');
      }
    } finally {
      secret.clear();
    }
    await workspace.close();
    workspace = null;
    stdout.writeln(
      seed
          ? 'ENVIRONMENT_DURABLE_CHECKPOINT_CREATED'
          : 'ENVIRONMENT_DURABLE_STATE_AND_CREDENTIAL_VERIFIED',
    );
  } finally {
    await workspace?.close();
    await lease?.close();
  }
}
