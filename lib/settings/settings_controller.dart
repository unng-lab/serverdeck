import 'package:flutter/foundation.dart';
import 'package:serverdeck_protocol/models.dart';

import '../profiles/mutation_controller.dart';
import '../profiles/profile_controller.dart';

/// Owns one RAM draft. Current snapshots never silently replace the draft.
class SettingsController extends ChangeNotifier {
  SettingsController({required this.model}) {
    mutation = MutationController(model: model);
    model.addListener(_firstSnapshot);
    _firstSnapshot();
  }
  final ProfileController model;
  late final MutationController mutation;
  late String revision;
  late ThemePreference theme;
  late bool reduceMotion;
  String? selectedProfileId;
  List<ProfileView> profiles = const [];
  bool initialized = false;
  bool reloading = false, _disposed = false;
  bool _baseDisposed = false;
  int _notifications = 0;
  String? readError;

  void _firstSnapshot() {
    if (_disposed ||
        initialized ||
        !model.loaded ||
        model.bootstrap.state != ReadinessState.ready)
      return;
    _capture();
    initialized = true;
    _notify();
  }

  void _capture() {
    final current = model.settings!;
    revision = current.revision;
    theme = current.theme;
    reduceMotion = current.reduceMotion;
    selectedProfileId = current.selectedProfileId;
    profiles = List.unmodifiable(model.profiles);
  }

  bool get editable =>
      initialized && !reloading && mutation.state == MutationPresentation.idle;

  void edit({ThemePreference? theme, bool? reduceMotion}) {
    if (!editable || _disposed) return;
    this.theme = theme ?? this.theme;
    this.reduceMotion = reduceMotion ?? this.reduceMotion;
    _notify();
  }

  void select(String? id) {
    if (!editable || _disposed) return;
    selectedProfileId = id;
    _notify();
  }

  Future<void> save() async {
    if (!editable || _disposed || !model.loaded) return;
    await mutation.submit(ApiMethod.settingsUpdate, {
      'expectedRevision': revision,
      'theme': theme.name,
      'reduceMotion': reduceMotion,
      'selectedProfileId': selectedProfileId,
    });
  }

  Future<void> reload() async {
    if (_disposed || reloading || mutation.busy) return;
    reloading = true;
    _notify();
    if (_disposed) return;
    await model.refresh();
    if (_disposed) return;
    reloading = false;
    if (model.loaded) {
      _capture();
      readError = null;
      mutation.reset();
    } else {
      readError = 'Не удалось перечитать настройки; сохранение не повторено';
    }
    _notify();
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
    model.removeListener(_firstSnapshot);
    mutation.dispose();
    profiles = const [];
    selectedProfileId = null;
    if (_notifications == 0) {
      _baseDisposed = true;
      super.dispose();
    }
  }
}
