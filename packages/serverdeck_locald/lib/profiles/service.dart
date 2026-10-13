import 'package:serverdeck_protocol/models.dart';

import '../credentials/provider.dart';
import '../storage/models.dart';
import 'settings_service.dart';

class PreparedMutation {
  PreparedMutation(this.value, this.result);
  final Map<String, Object?> value;
  final MutationResult result;
}

/// Pure model preparation plus custody. Only the coordinator commits the result.
class ProfileService {
  ProfileService(this.credentials);
  final CredentialProvider credentials;
  final settings = SettingsService();

  ProfilesSnapshot list(WorkspaceState state) {
    final profiles = state.profiles.values.toList()
      ..sort((a, b) {
        final name = a.name.compareTo(b.name);
        return name != 0 ? name : a.id.compareTo(b.id);
      });
    return ProfilesSnapshot(
      state.storeRevision,
      List.unmodifiable(
        profiles.map(
          (p) => p.view(
            p.credentialRef == null ? null : state.credentials[p.credentialRef],
          ),
        ),
      ),
    );
  }

  ProfileSnapshot get(WorkspaceState state, String id) {
    final profile = state.profiles[id];
    if (profile == null) throw StateError('NOT_FOUND');
    return ProfileSnapshot(
      state.storeRevision,
      profile.view(
        profile.credentialRef == null
            ? null
            : state.credentials[profile.credentialRef],
      ),
    );
  }

  Future<PreparedMutation> prepare(
    WorkspaceState state,
    ApiMethod method,
    Map<String, Object?> params,
    String timestamp,
  ) async {
    if (state.receipts.length >= 10000) throw StateError('RESOURCE_LIMIT');
    final value = state.toJson();
    final revision = nextRevision(state.storeRevision);
    value['storeRevision'] = revision;
    if (method == ApiMethod.settingsUpdate) {
      final next = settings.prepare(state, params);
      value['settings'] = next;
      return PreparedMutation(
        value,
        MutationResult(
          entityId: null,
          entityRevision: next['revision'] as String,
          storeRevision: revision,
          deleted: false,
        ),
      );
    }
    final id = params['profileId'] as String;
    final old = state.profiles[id];
    final creating = method == ApiMethod.profilesCreate;
    if (creating) {
      if (old != null) throw StateError('ALREADY_EXISTS');
      if (state.profiles.length >= 250) throw StateError('RESOURCE_LIMIT');
    } else {
      if (old == null) throw StateError('NOT_FOUND');
      if (params['expectedRevision'] != old.revision)
        throw StateError('REVISION_CONFLICT');
    }
    final profiles = value['profiles'] as Map,
        blobs = value['credentials'] as Map;
    if (method == ApiMethod.profilesDelete) {
      profiles.remove(id);
      if (old!.credentialRef != null) blobs.remove(old.credentialRef);
      if (state.settings.toJson()['selectedProfileId'] == id) {
        value['settings'] = {
          ...state.settings.toJson(),
          'revision': nextRevision(state.settings.revision),
          'selectedProfileId': null,
        };
      }
      return PreparedMutation(
        value,
        MutationResult(
          entityId: id,
          entityRevision: old.revision,
          storeRevision: revision,
          deleted: true,
        ),
      );
    }
    final previous = old?.toJson();
    final action = params['credential'] as Map<String, Object?>;
    final entityRevision = creating ? '1' : nextRevision(old!.revision);
    final credentialRevision = creating
        ? '1'
        : action['action'] == 'keep'
        ? old!.credentialRevision
        : nextRevision(old!.credentialRevision);
    final connectionChanged =
        !creating &&
        ['address', 'port', 'sshUser'].any((f) => params[f] != previous![f]);
    final connectionRevision = creating
        ? '1'
        : connectionChanged
        ? nextRevision(previous!['connectionRevision'] as String)
        : previous!['connectionRevision'];
    String? reference = old?.credentialRef;
    if (action['action'] != 'keep') {
      if (reference != null) blobs.remove(reference);
      reference = null;
      if (action['action'] == 'replace') {
        final record = await credentials.replace(
          state,
          id,
          credentialRevision,
          timestamp,
          action,
        );
        reference = record.id;
        blobs[record.id] = record.toJson();
      }
    }
    profiles[id] = {
      'id': id,
      'revision': entityRevision,
      for (final field in ['name', 'address', 'port', 'sshUser', 'tags'])
        field: params[field],
      'credentialRef': reference,
      'credentialRevision': credentialRevision,
      'connectionRevision': connectionRevision,
      'trustRevision': connectionRevision,
      'createdAt': previous?['createdAt'] ?? timestamp,
      'updatedAt': timestamp,
    };
    return PreparedMutation(
      value,
      MutationResult(
        entityId: id,
        entityRevision: entityRevision,
        storeRevision: revision,
        deleted: false,
      ),
    );
  }
}
