import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:serverdeck_protocol/models.dart';

import '../bootstrap/bootstrap_controller.dart';
import '../bootstrap/local_api_client.dart';

/// A service-owned snapshot projection. Drafts and mutations live separately.
class ProfileController extends ChangeNotifier {
  ProfileController({required this.bootstrap}) {
    _subscription = bootstrap.client.snapshots.listen(_accept);
    _errorSubscription = bootstrap.client.snapshotErrors.listen((code) {
      if (_disposed || !_ready) return;
      _clear();
      _error = code;
      _notify();
    });
    bootstrap.addListener(_readiness);
    _readiness();
  }
  final BootstrapController bootstrap;
  late final StreamSubscription<ClientSnapshot> _subscription;
  late final StreamSubscription<ErrorCode> _errorSubscription;
  List<ProfileView> _profiles = const [];
  SettingsView? _settings;
  ErrorCode? _error;
  String? _revision;
  bool _ready = false, _disposed = false, _baseDisposed = false;
  int _notifications = 0;

  List<ProfileView> get profiles => _profiles;
  SettingsView? get settings => _settings;
  String? get storeRevision => _revision;
  ErrorCode? get error => _error;
  bool get loaded => _ready && _settings != null && _error == null;
  ProfileView? get selected {
    final id = _settings?.selectedProfileId;
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  void _readiness() {
    if (_disposed) return;
    final ready = bootstrap.state == ReadinessState.ready;
    if (ready == _ready) return;
    _ready = ready;
    _clear();
    _revision = null;
    _notify();
    if (ready && !_disposed) refresh().ignore();
  }

  Future<void> refresh() async {
    if (_disposed || !_ready) return;
    try {
      await bootstrap.client.refreshSnapshot();
    } on Object {
      // Only the client's guarded error stream may update presentation. A
      // joined Future can still belong to a retired polling epoch.
    }
  }

  void _accept(ClientSnapshot snapshot) {
    if (_disposed ||
        !_ready ||
        snapshot.generation != bootstrap.client.generation ||
        snapshot.profiles.generation != snapshot.settings.generation ||
        snapshot.profiles.result['storeRevision'] !=
            snapshot.settings.result['storeRevision'])
      return;
    try {
      bootstrap.client.captureResult('profiles.list', snapshot.profiles.result);
      bootstrap.client.captureResult('settings.get', snapshot.settings.result);
      final revision = snapshot.storeRevision;
      if (_revision != null &&
          BigInt.parse(revision) < BigInt.parse(_revision!)) {
        return;
      }
      final profiles = (snapshot.profiles.result['profiles'] as List)
          .map((raw) {
            final value = raw as Map<String, Object?>;
            final credential = value['credential'] as Map<String, Object?>;
            return ProfileView(
              id: value['id'] as String,
              revision: value['revision'] as String,
              name: value['name'] as String,
              address: value['address'] as String,
              port: value['port'] as int,
              sshUser: value['sshUser'] as String,
              tags: List<String>.unmodifiable(value['tags'] as List),
              credentialRevision: value['credentialRevision'] as String,
              connectionRevision: value['connectionRevision'] as String,
              trustRevision: value['trustRevision'] as String,
              createdAt: value['createdAt'] as String,
              updatedAt: value['updatedAt'] as String,
              credentialKind: CredentialKind.values.byName(
                credential['kind'] as String,
              ),
              credentialConfigured: credential['configured'] as bool,
            );
          })
          .toList(growable: false);
      final value =
          snapshot.settings.result['settings'] as Map<String, Object?>;
      final settings = SettingsView(
        revision: value['revision'] as String,
        theme: ThemePreference.values.byName(value['theme'] as String),
        reduceMotion: value['reduceMotion'] as bool,
        selectedProfileId: value['selectedProfileId'] as String?,
      );
      if (settings.selectedProfileId != null &&
          !profiles.any(
            (profile) => profile.id == settings.selectedProfileId,
          )) {
        throw const FormatException('INCOMPATIBLE');
      }
      _profiles = List.unmodifiable(profiles);
      _settings = settings;
      _revision = revision;
      _error = null;
      _notify();
    } on Object {
      _clear();
      _error = ErrorCode.incompatible;
      _notify();
    }
  }

  void _clear() {
    _profiles = const [];
    _settings = null;
    _error = null;
  }

  void _notify() {
    if (_disposed) return;
    _notifications++;
    try {
      notifyListeners();
    } finally {
      _notifications--;
      _disposeBase();
    }
  }

  void _disposeBase() {
    if (_disposed && !_baseDisposed && _notifications == 0) {
      _baseDisposed = true;
      super.dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    bootstrap.removeListener(_readiness);
    _subscription.cancel().ignore();
    _errorSubscription.cancel().ignore();
    _clear();
    if (_notifications == 0) {
      _baseDisposed = true;
      super.dispose();
    }
  }
}
