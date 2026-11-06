import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/models.dart';
import '../runtime/capability.dart';
import '../storage/domain_repository.dart';
import 'console_models.dart';

abstract final class ConsoleSettingsCodec {
  static bool _keys(Map value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);
  static void _invalid() =>
      throw const OperationFailure(FailureCode.invalidArgument);
  static String? nameError(String name) {
    final value = name.trim();
    if (!isWellFormedUnicode(value) ||
        value.runes.isEmpty ||
        value.runes.length > 80) {
      return 'Название должно содержать от 1 до 80 символов.';
    }
    return null;
  }

  static String? pathError(String path) {
    if (!isWellFormedUnicode(path) ||
        !path.startsWith('/') ||
        utf8.encode(path).length > 1024 ||
        path.contains('\u0000') ||
        path.contains('\r') ||
        path.contains('\n')) {
      return 'Укажите абсолютный Linux-путь до 1024 байт без NUL и переводов строк.';
    }
    return null;
  }

  static ConsoleConfiguration normalized(ConsoleConfiguration value) {
    if (value.revision < 1 ||
        value.revision > 9007199254740991 ||
        value.profiles.length > 16)
      _invalid();
    final ids = <String>{'login'};
    final profiles = <ConsoleShellProfile>[];
    for (final profile in value.profiles) {
      if (!isCanonicalUuid(profile.id) ||
          !ids.add(profile.id) ||
          nameError(profile.name) != null ||
          profile.path == null ||
          pathError(profile.path!) != null)
        _invalid();
      profiles.add(
        ConsoleShellProfile(
          id: profile.id,
          name: profile.name.trim(),
          path: profile.path,
        ),
      );
    }
    if (!ids.contains(value.defaultId)) _invalid();
    return ConsoleConfiguration(
      revision: value.revision,
      defaultId: value.defaultId,
      profiles: List.unmodifiable(profiles),
    );
  }

  static String encode(ConsoleConfiguration raw) {
    final value = normalized(raw);
    final json = jsonEncode({
      'version': 1,
      'revision': value.revision,
      'defaultId': value.defaultId,
      'profiles': [for (final p in value.profiles) p.toJson()],
    });
    if (utf8.encode(json).length > 32768) _invalid();
    return json;
  }

  static ConsoleConfiguration decode(String? json) {
    if (json == null) return const ConsoleConfiguration();
    try {
      if (utf8.encode(json).length > 32768) _invalid();
      final value = jsonDecode(json);
      if (value is! Map ||
          !_keys(value, {'version', 'revision', 'defaultId', 'profiles'}) ||
          value['version'] != 1 ||
          value['version'] is! int ||
          value['revision'] is! int ||
          value['defaultId'] is! String ||
          value['profiles'] is! List)
        _invalid();
      final map = value as Map;
      final profiles = <ConsoleShellProfile>[];
      for (final profile in map['profiles'] as List) {
        if (profile is! Map ||
            !_keys(profile, {'id', 'name', 'path'}) ||
            profile['id'] is! String ||
            profile['name'] is! String ||
            profile['path'] is! String)
          _invalid();
        final p = profile as Map;
        final name = p['name'] as String;
        if (name != name.trim()) _invalid();
        profiles.add(
          ConsoleShellProfile(
            id: p['id'] as String,
            name: name,
            path: p['path'] as String,
          ),
        );
      }
      return normalized(
        ConsoleConfiguration(
          revision: map['revision'] as int,
          defaultId: map['defaultId'] as String,
          profiles: profiles,
        ),
      );
    } catch (_) {
      throw const OperationFailure(FailureCode.storageUnavailable);
    }
  }
}

final class ConsoleSettingsOwner implements Listenable, RuntimeCapability {
  ConsoleSettingsOwner({
    required this.actors,
    required this.gate,
    required this.repository,
    this.onChanged,
  });
  final ActorAuthority actors;
  final DomainCommandGate gate;
  final DomainRepository repository;
  final VoidCallback? onChanged;
  final _notifier = _SettingsNotifier();
  bool _stopped = false, _disposed = false;
  @override
  String get id => 'console-settings';
  ConsoleConfiguration get snapshot => ConsoleSettingsCodec.decode(
    repository.read((r) => r.settings.terminalConfiguration),
  );
  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);
  Future<OperationResult<MutationValue>> save(
    UiActor actor,
    ConsoleConfiguration draft, {
    required int expectedRevision,
  }) async {
    final result = await gate.submit(
      actor,
      (context) => repository.write(
        (records) => context.linearize(() {
          if (_stopped) throw const OperationFailure(FailureCode.shuttingDown);
          final settings = records.settings;
          final current = ConsoleSettingsCodec.decode(
            settings.terminalConfiguration,
          );
          if (current.revision != expectedRevision)
            throw const OperationFailure(FailureCode.conflict);
          final normalized = ConsoleSettingsCodec.normalized(draft);
          final revision = nextRevision(current.revision);
          settings.terminalConfiguration = ConsoleSettingsCodec.encode(
            ConsoleConfiguration(
              revision: revision,
              defaultId: normalized.defaultId,
              profiles: normalized.profiles,
            ),
          );
          settings.settingsRevision = nextRevision(settings.settingsRevision);
          settings.dataRevision = nextRevision(settings.dataRevision);
          records.putSettings(settings);
          return MutationValue(entityId: actors.ownerEpoch, revision: revision);
        }),
      ),
    );
    if (result.ok && !_disposed) {
      _notifier.changed();
      onChanged?.call();
    }
    return result;
  }

  @override
  Future<void> stopAdmission() async {
    _stopped = true;
  }

  @override
  Future<void> cancelPending() async {}
  @override
  Future<void> closeSessions() async {}
  @override
  Future<void> drain() async {}
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _stopped = true;
    _disposed = true;
    _notifier.dispose();
  }
}

final class _SettingsNotifier extends ChangeNotifier {
  void changed() => notifyListeners();
}
