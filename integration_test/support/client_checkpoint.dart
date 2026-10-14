import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

Future<String> _digest(List<int> bytes) async =>
    (await Sha256().hash(bytes)).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

/// Acceptance only: all reads use the real production client and owner.
Future<void> clientCheckpoint(
  LocalApiClient client,
  String root,
  String mode,
) async {
  if (!{'capture', 'verify'}.contains(mode))
    throw StateError('CHECKPOINT_MODE');
  requireSafePath(root, root);
  final sid = currentUserSid();
  final durable = await readProtectedFile(
    root,
    p.join(root, 'durable-checkpoint.json'),
    sid,
    maxBytes: 4096,
  );
  final profiles = (await client.read(ApiMethod.profilesList)).result;
  final settings = (await client.read(ApiMethod.settingsGet)).result;
  final receipts = (await client.read(ApiMethod.mutationsRecent, {
    'limit': 20,
  })).result;
  final rows = profiles['profiles'] as List;
  final events = receipts['receipts'] as List;
  if (profiles['storeRevision'] != '1' ||
      settings['storeRevision'] != '1' ||
      rows.length != 1 ||
      events.length != 1 ||
      receipts['truncated'] != false ||
      (rows.single as Map)['id'] != 'b2435678-1234-4234-8234-123456789012' ||
      (events.single as Map)['requestId'] !=
          'a2435678-1234-4234-8234-123456789012') {
    throw StateError('CLIENT_CHECKPOINT_STATE');
  }
  final state = {
    'profiles': profiles,
    'settings': settings,
    'receipts': receipts,
  };
  final encoded = StrictCodec().encode(state, maxBytes: 65536);
  final stateHash = await _digest(encoded);
  final durableHash = await _digest(durable);
  final expected = {
    'format': 1,
    'ownerSid': sid,
    'durableCheckpointSha256': durableHash,
    'publicStateSha256': stateHash,
    'publicState': state,
  };
  final path = p.join(root, 'client-checkpoint.json');
  if (mode == 'capture') {
    await writeNewProtectedFile(
      root,
      path,
      sid,
      utf8.encode(jsonEncode(expected)),
    );
  } else {
    final original = await readProtectedFile(root, path, sid, maxBytes: 65536);
    final record = StrictCodec().decode(original, maxBytes: 65536);
    if (record['format'] != 1 ||
        record['ownerSid'] != sid ||
        record['durableCheckpointSha256'] != durableHash ||
        record['publicStateSha256'] != stateHash ||
        base64.encode(
              StrictCodec().encode(
                record['publicState'] as Map<String, Object?>,
                maxBytes: 65536,
              ),
            ) !=
            base64.encode(encoded)) {
      throw StateError('CLIENT_CHECKPOINT_MISMATCH');
    }
    await writeNewProtectedFile(
      root,
      p.join(root, 'client-verification.json'),
      sid,
      utf8.encode(
        jsonEncode({
          'format': 1,
          'scenario': 'production-client-durable-checkpoint',
          'checkpointSha256': await _digest(original),
          'publicStateSha256': stateHash,
          'durableCheckpointSha256': durableHash,
          'storeRevision': '1',
          'profiles': 1,
          'receipts': 1,
          'fullAcceptance': false,
          'rebootProven': false,
        }),
      ),
    );
  }
}
