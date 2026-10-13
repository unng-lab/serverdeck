import 'dart:math';

import '../storage/key_custody.dart';
import '../storage/models.dart';

class CredentialProvider {
  CredentialProvider(this.custody);
  final KeyCustody custody;

  Future<CredentialRecord> replace(
    WorkspaceState state,
    String profileId,
    String revision,
    String timestamp,
    Map<String, Object?> action,
  ) async {
    final random = Random.secure();
    String id;
    do {
      final bytes = List.generate(16, (_) => random.nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final text = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      id =
          '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
    } while (state.credentials.containsKey(id));
    final blob = await custody.wrapCredential(
      state.workspaceId,
      profileId,
      id,
      action,
    );
    return CredentialRecord.fromJson({
      'id': id,
      'profileId': profileId,
      'revision': revision,
      'kind': action['kind'],
      'protectedBlob': blob,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
  }
}
