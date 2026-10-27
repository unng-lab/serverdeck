import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/codec.dart';

void _check(bool condition) {
  if (!condition) throw StateError('RESOURCE_BOUNDARY_FIXTURE_FAILED');
}

/// Exact byte limits of all five native row documents. Padding is valid JSON
/// whitespace, so rejection cannot be attributed to changed business fields.
/// Operates only on the caller's owned synthetic repository, with each native
/// instance closed before the production repository opens.
Future<void> verifyRecordByteLimits(
  Future<StateStore> Function() open,
  Future<Isar> Function() nativeOpen,
) async {
  final baselineStore = await open();
  late String baselineState;
  try {
    baselineState = base64.encode(
      StrictCodec().canonical(baselineStore.state.toJson()),
    );
  } finally {
    await baselineStore.close();
  }
  final raw = await nativeOpen();
  late StoredWorkspace workspace;
  late StoredSettings settings;
  late StoredProfile profile;
  late StoredCredential credential;
  late StoredReceipt receipt;
  try {
    workspace = (await raw.storedWorkspaces.get(1))!;
    settings = (await raw.storedSettings.get(1))!;
    profile = (await raw.storedProfiles.where().findFirst())!;
    credential = (await raw.storedCredentials.where().findFirst())!;
    receipt = (await raw.storedReceipts.where().findFirst())!;
  } finally {
    _check(await raw.close());
  }

  Future<String> rows(Isar native) async => jsonEncode({
    'workspace': [
      for (final r in await native.storedWorkspaces.where().findAll())
        [r.id, r.payload],
    ],
    'settings': [
      for (final r in await native.storedSettings.where().findAll())
        [r.id, r.payload],
    ],
    'profiles': [
      for (final r in await native.storedProfiles.where().findAll())
        [r.id, r.entityId, r.payload],
    ],
    'credentials': [
      for (final r in await native.storedCredentials.where().findAll())
        [r.id, r.entityId, r.payload],
    ],
    'receipts': [
      for (final r in await native.storedReceipts.where().findAll())
        [r.id, r.entityId, r.payload],
    ],
  });
  final cases = <(String, int, String, Future<void> Function(Isar, String))>[
    (
      'workspace',
      4096,
      workspace.payload,
      (db, value) async {
        workspace.payload = value;
        await db.storedWorkspaces.put(workspace);
      },
    ),
    (
      'settings',
      4096,
      settings.payload,
      (db, value) async {
        settings.payload = value;
        await db.storedSettings.put(settings);
      },
    ),
    (
      'profile',
      16 * 1024,
      profile.payload,
      (db, value) async {
        profile.payload = value;
        await db.storedProfiles.put(profile);
      },
    ),
    (
      'credential',
      512 * 1024,
      credential.payload,
      (db, value) async {
        credential.payload = value;
        await db.storedCredentials.put(credential);
      },
    ),
    (
      'receipt',
      4096,
      receipt.payload,
      (db, value) async {
        receipt.payload = value;
        await db.storedReceipts.put(receipt);
      },
    ),
  ];
  for (final entry in cases) {
    final bytes = utf8.encode(entry.$3).length;
    _check(bytes < entry.$2);
    for (final excess in [0, 1]) {
      final padded = entry.$3 + ' ' * (entry.$2 + excess - bytes);
      _check(utf8.encode(padded).length == entry.$2 + excess);
      final writer = await nativeOpen();
      late String written;
      try {
        await writer.writeTxn(() => entry.$4(writer, padded));
        written = await rows(writer);
      } finally {
        _check(await writer.close());
      }
      try {
        if (excess == 0) {
          final accepted = await open();
          try {
            _check(
              base64.encode(StrictCodec().canonical(accepted.state.toJson())) ==
                  baselineState,
            );
          } finally {
            await accepted.close();
          }
        } else {
          var refused = false;
          StateStore? unexpected;
          try {
            unexpected = await open();
          } on StateError catch (error) {
            _check(error.message == 'STORAGE_BLOCKED');
            refused = true;
          } finally {
            await unexpected?.close();
          }
          _check(refused);
        }
        final preserved = await nativeOpen();
        try {
          _check(await rows(preserved) == written);
        } finally {
          _check(await preserved.close());
        }
      } finally {
        final restore = await nativeOpen();
        try {
          await restore.writeTxn(() => entry.$4(restore, entry.$3));
        } finally {
          _check(await restore.close());
        }
      }
    }
    final restored = await open();
    try {
      _check(
        base64.encode(StrictCodec().canonical(restored.state.toJson())) ==
            baselineState,
      );
    } finally {
      await restored.close();
    }
  }
  // Emitted only after every exact-limit/one-byte-over/preservation/reopen check.
  stdout.writeln('NATIVE_FIVE_RECORD_BYTE_LIMITS_PRESERVED_PROVED');
}
