import 'package:flutter/foundation.dart';

import 'foundation_shell.dart';

enum DeckView {
  profiles,
  server,
  software,
  logs,
  jobs,
  automationProfiles,
  grants,
  settings,
  recentOperations;

  FoundationSection get section => switch (this) {
    profiles || server => FoundationSection.servers,
    software => FoundationSection.software,
    logs => FoundationSection.logs,
    jobs || automationProfiles || recentOperations => FoundationSection.jobs,
    settings || grants => FoundationSection.settings,
  };

  static DeckView forSection(FoundationSection section) => switch (section) {
    FoundationSection.servers => profiles,
    FoundationSection.software => software,
    FoundationSection.logs => logs,
    FoundationSection.jobs => jobs,
    FoundationSection.settings => settings,
  };
}

/// RAM-only location. It contains typed identities, never credentials or authority.
@immutable
class DeckLocation {
  const DeckLocation({
    this.view = DeckView.profiles,
    this.serverId,
    this.entityId,
  });
  FoundationSection get section => view.section;
  final DeckView view;
  final String? serverId, entityId;

  DeckLocation withServer(String? id) =>
      DeckLocation(view: view, serverId: id, entityId: entityId);
}

class DeckNavigationController extends ValueNotifier<DeckLocation> {
  DeckNavigationController() : super(const DeckLocation());
  void open(DeckLocation location) => value = location;
}
