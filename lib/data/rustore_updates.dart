import 'dart:async';

import 'package:flutter_rustore_update/flutter_rustore_update.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_updates.dart';

abstract interface class RuStoreBridge {
  Future<UpdateInfo> info();
  Future<DownloadResponse> download();
  Future<void> install();
  Stream<RequestResponse> get states;
  Future<void> openStore();
}

class NativeRuStoreBridge implements RuStoreBridge {
  NativeRuStoreBridge(this.packageName);
  final String packageName;
  @override
  Future<UpdateInfo> info() => RustoreUpdateClient.info();
  @override
  Future<DownloadResponse> download() => RustoreUpdateClient.download();
  @override
  Future<void> install() => RustoreUpdateClient.completeUpdateFlexible();
  @override
  Stream<RequestResponse> get states => RustoreUpdateClient.stateStream;
  @override
  Future<void> openStore() async {
    final uri = Uri.https('www.rustore.ru', '/catalog/app/$packageName');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Store unavailable');
    }
  }
}

class RuStoreUpdater extends UpdateController {
  RuStoreUpdater({
    required this.installedVersion,
    required this.installedBuild,
    required this.packageName,
    RuStoreBridge? bridge,
  }) : _bridge = bridge ?? NativeRuStoreBridge(packageName) {
    _subscription = _bridge.states.listen(
      _onState,
      onError: (Object _) => _error(),
    );
  }
  final int installedBuild;
  final String packageName;
  final RuStoreBridge _bridge;
  late final StreamSubscription<RequestResponse> _subscription;
  bool _disposed = false, _opening = false;
  UpdateInfo? _info;
  @override
  final String installedVersion;
  @override
  UpdateState state = UpdateState.idle;
  @override
  String message = '';
  @override
  double? progress;
  @override
  bool get isStore => true;
  @override
  String? get availableVersion =>
      _info == null ? null : 'сборка ${_info!.availableVersionCode}';
  @override
  String get notes =>
      'Обновление через RuStore. Описание версии доступно на странице приложения.';
  void _emit(UpdateState next, [String text = '']) {
    if (_disposed) return;
    state = next;
    message = text;
    notifyListeners();
  }

  void _error() => _emit(
    UpdateState.error,
    'RuStore не смог проверить или выполнить обновление. Проверьте наличие актуального RuStore, вход в аккаунт и разрешение установки.',
  );
  UpdateState _status(int status) => switch (status) {
    1 => UpdateState.downloaded,
    2 || 4 || 5 => UpdateState.downloading,
    3 => UpdateState.error,
    _ => UpdateState.available,
  };
  void _onState(RequestResponse value) {
    if (_disposed || value.packageName != packageName || _info == null) return;
    progress = value.totalBytesToDownload > 0
        ? (value.bytesDownloaded / value.totalBytesToDownload).clamp(0.0, 1.0)
        : null;
    if (value.installStatus == 3) {
      _error();
    } else {
      _emit(
        _status(value.installStatus),
        value.installStatus == 4 ? 'RuStore выполняет установку.' : '',
      );
    }
  }

  @override
  Future<void> check() async {
    if (busy || _opening || _disposed) return;
    _emit(UpdateState.checking);
    try {
      final info = await _bridge.info().timeout(const Duration(seconds: 25));
      if (_disposed || state != UpdateState.checking) return;
      if (info.packageName != packageName) throw StateError('Package mismatch');
      _info = info;
      if (info.updateAvailability == 1) {
        _emit(UpdateState.current);
      } else if (info.updateAvailability == 2 || info.updateAvailability == 3) {
        if (info.availableVersionCode <= installedBuild) {
          throw StateError('Not newer');
        }
        if (info.installStatus == 3) {
          _error();
        } else {
          _emit(_status(info.installStatus));
        }
      } else {
        _emit(
          UpdateState.unsupported,
          'RuStore пока не сообщил о доступности обновлений. Откройте страницу приложения.',
        );
      }
    } catch (_) {
      _error();
    }
  }

  @override
  Future<void> download() async {
    if (busy || _opening || _disposed || state != UpdateState.available) return;
    _emit(UpdateState.downloading);
    try {
      // RuStore requires a fresh info object for each download attempt.
      final info = await _bridge.info().timeout(const Duration(seconds: 25));
      if (info.packageName != packageName ||
          info.updateAvailability != 2 ||
          info.availableVersionCode <= installedBuild) {
        throw StateError('Update unavailable');
      }
      _info = info;
      final result = await _bridge.download();
      if (result.code == 0) {
        _emit(UpdateState.available, 'Скачивание отменено.');
      } else if (result.code != -1) {
        _error();
      }
      // Completion is exclusively reported by the SDK state stream.
    } catch (_) {
      _error();
    }
  }

  @override
  Future<void> openInstaller() async {
    if (_disposed || _opening || state != UpdateState.downloaded) return;
    _opening = true;
    try {
      _emit(
        UpdateState.downloaded,
        'Установка запрошена в RuStore. Следуйте указаниям магазина.',
      );
      await _bridge.install();
    } catch (_) {
      _error();
    } finally {
      _opening = false;
    }
  }

  @override
  Future<void> openStore() async {
    try {
      await _bridge.openStore();
    } catch (_) {
      _emit(
        UpdateState.error,
        'Не удалось открыть RuStore. Проверьте доступ к интернету.',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
