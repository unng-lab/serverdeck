import 'key_custody.dart';
import 'models.dart';

/// Startup gate: all persisted blobs must be usable by their owning OS user.
Future<void> validateWorkspaceCredentials(
  WorkspaceState state,
  KeyCustody custody,
) async {
  if (state.ownerSid != custody.ownerSid) {
    throw StateError('STORAGE_BLOCKED');
  }
  for (final credential in state.credentials.values) {
    final secret = await custody.openCredential(
      credential.protectedBlob,
      state.workspaceId,
      credential.profileId,
      credential.id,
    );
    try {
      if (secret['kind'] != credential.kind.name) {
        throw StateError('STORAGE_BLOCKED');
      }
    } finally {
      secret.clear();
    }
  }
}
