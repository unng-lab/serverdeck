import 'package:serverdeck_protocol/models.dart';

import '../storage/models.dart';

class SettingsService {
  SettingsSnapshot get(WorkspaceState state) =>
      SettingsSnapshot(state.storeRevision, state.settings);
  Map<String, Object?> prepare(
    WorkspaceState state,
    Map<String, Object?> params,
  ) {
    if (params['expectedRevision'] != state.settings.revision)
      throw StateError('REVISION_CONFLICT');
    final selected = params['selectedProfileId'];
    if (selected != null && !state.profiles.containsKey(selected))
      throw StateError('NOT_FOUND');
    return {
      'revision': nextRevision(state.settings.revision),
      'theme': params['theme'],
      'reduceMotion': params['reduceMotion'],
      'selectedProfileId': selected,
    };
  }
}
