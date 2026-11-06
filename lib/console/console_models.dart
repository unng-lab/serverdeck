import '../domain/actor.dart';
import '../runtime/owned_work.dart';

final class ConsoleShellProfile {
  const ConsoleShellProfile({required this.id, required this.name, this.path});
  static const login = ConsoleShellProfile(
    id: 'login',
    name: 'Оболочка входа сервера',
  );
  final String id, name;
  final String? path;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (path != null) 'path': path,
  };
}

final class ConsoleConfiguration {
  const ConsoleConfiguration({
    this.revision = 1,
    this.defaultId = 'login',
    this.profiles = const [],
  });
  final int revision;
  final String defaultId;
  final List<ConsoleShellProfile> profiles;
  List<ConsoleShellProfile> get all => [ConsoleShellProfile.login, ...profiles];
  ConsoleShellProfile? profile(String id) {
    if (id == 'login') return ConsoleShellProfile.login;
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}

/// Transport-owned identity. Neither token nor disconnected latch comes from JSON.
final class ConsoleMcpBinding {
  ConsoleMcpBinding(this.actor);
  final McpActor actor;
  final Object token = Object();
  final disconnected = WorkCancellation();
  void close() => disconnected.cancel();
}

final class ConsoleCaller {
  const ConsoleCaller.ui(UiActor this.actor) : binding = null;
  ConsoleCaller.mcp(McpActor context, ConsoleMcpBinding connection)
    : actor = context,
      binding = connection {
    if (context.ownerEpoch != connection.actor.ownerEpoch ||
        context.clientId != connection.actor.clientId ||
        context.grantVersion != connection.actor.grantVersion) {
      throw ArgumentError('Mismatched console identity');
    }
  }
  final Actor actor;
  final ConsoleMcpBinding? binding;
}

sealed class ConsoleProjection {
  const ConsoleProjection();
  Map<String, Object?> toJson();
}

final class ConsoleInputView {
  const ConsoleInputView(
    this.kind, {
    this.clientId,
    this.name,
    this.expiresInMs,
  });
  final String kind;
  final String? clientId, name;
  final int? expiresInMs;
  Map<String, Object?> toJson() => {
    'kind': kind,
    if (clientId != null) 'clientId': clientId,
    if (name != null) 'name': name,
    if (expiresInMs != null) 'expiresInMs': expiresInMs,
  };
}

final class ConsoleSessionView {
  const ConsoleSessionView({
    required this.sessionId,
    required this.profileId,
    required this.generation,
    required this.shellProfileId,
    required this.shellName,
    required this.state,
    required this.partial,
    required this.historyVersion,
    required this.inputOwner,
    this.reason,
    this.exitCode,
  });
  final String sessionId, profileId, shellProfileId, shellName, state;
  final int generation, historyVersion;
  final String? reason;
  final int? exitCode;
  final bool partial;
  final ConsoleInputView inputOwner;
  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'profileId': profileId,
    'generation': generation,
    'shellProfileId': shellProfileId,
    'shellName': shellName,
    'state': state,
    'partial': partial,
    'historyVersion': historyVersion,
    'inputOwner': inputOwner.toJson(),
    if (reason != null) 'reason': reason,
    if (exitCode != null) 'exitCode': exitCode,
  };
}

final class ConsoleSessionsValue extends ConsoleProjection {
  const ConsoleSessionsValue(this.sessions, this.nextOperationSequence);
  final List<ConsoleSessionView> sessions;
  final int nextOperationSequence;
  @override
  Map<String, Object?> toJson() => {
    'sessions': [for (final s in sessions) s.toJson()],
    'nextOperationSequence': nextOperationSequence,
  };
}

final class ConsoleProfilesValue extends ConsoleProjection {
  const ConsoleProfilesValue(this.configuration, this.nextOperationSequence);
  final ConsoleConfiguration configuration;
  final int nextOperationSequence;
  @override
  Map<String, Object?> toJson() => {
    'profiles': [for (final p in configuration.all) p.toJson()],
    'defaultId': configuration.defaultId,
    'nextOperationSequence': nextOperationSequence,
  };
}

final class ConsoleActionValue extends ConsoleProjection {
  const ConsoleActionValue({
    required this.sessionId,
    required this.generation,
    required this.state,
    this.replayed = false,
    this.status = 'accepted',
    this.acceptedBytes = 0,
    this.leaseToken,
    this.operationSequence = 0,
  });
  final String sessionId, state, status;
  final int generation, acceptedBytes, operationSequence;
  final bool replayed;
  final String? leaseToken;
  ConsoleActionValue asReplay() => ConsoleActionValue(
    sessionId: sessionId,
    generation: generation,
    state: state,
    replayed: true,
    status: status,
    acceptedBytes: acceptedBytes,
    leaseToken: leaseToken,
    operationSequence: operationSequence,
  );
  @override
  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'generation': generation,
    'state': state,
    'replayed': replayed,
    'status': status,
    'acceptedBytes': acceptedBytes,
    if (leaseToken != null) 'leaseToken': leaseToken,
    'operationSequence': operationSequence,
  };
}

final class ConsoleHistoryRow {
  const ConsoleHistoryRow({
    required this.section,
    required this.row,
    required this.offset,
    required this.text,
    required this.wrapped,
  });
  final String section, text;
  final int row, offset;
  final bool wrapped;
  Map<String, Object?> toJson() => {
    'section': section,
    'row': row,
    'offset': offset,
    'text': text,
    'wrapped': wrapped,
  };
}

final class ConsoleHistoryValue extends ConsoleProjection {
  const ConsoleHistoryValue({
    required this.session,
    required this.activeBuffer,
    required this.cursorX,
    required this.cursorY,
    required this.historyVersion,
    required this.historyGap,
    required this.truncated,
    required this.partial,
    required this.rows,
    this.nextCursor,
  });
  final ConsoleSessionView session;
  final String activeBuffer;
  final int cursorX, cursorY, historyVersion;
  final bool historyGap, truncated, partial;
  final List<ConsoleHistoryRow> rows;
  final String? nextCursor;
  @override
  Map<String, Object?> toJson() => {
    'session': session.toJson(),
    'activeBuffer': activeBuffer,
    'cursor': {'x': cursorX, 'y': cursorY},
    'historyVersion': historyVersion,
    'historyGap': historyGap,
    'truncated': truncated,
    'partial': partial,
    'rows': [for (final row in rows) row.toJson()],
    'nextCursor': nextCursor,
  };
}
